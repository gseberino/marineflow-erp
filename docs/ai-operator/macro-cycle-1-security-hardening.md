# MarineFlow AI Operator — Macro Ciclo 1 (continuação · security hardening)

> Continuação da branch `feat/marineflow-ai-operator-macro-cycle-1`.
> Esta rodada corrige bloqueios de segurança encontrados na revisão
> independente da fundação criada anteriormente. Nenhuma migration foi
> aplicada e nenhuma Edge Function foi implantada nesta sessão — a
> aplicação remota fica para o ambiente do Gustavo (vide §"Como aplicar").

## Bloqueios endereçados

| # | Bloqueio | Status | Onde foi corrigido |
| --- | --- | --- | --- |
| 5.1 | Audit declarado append-only, mas com UPDATE policy | ✅ Corrigido | foundation migration v2 — audit só tem `select` para admin/financial; sem INSERT/UPDATE/DELETE policies para `authenticated` (apenas service_role grava). |
| 5.2 | Pending actions com UPDATE genérico | ✅ Corrigido | foundation v2 — sem policy de INSERT/UPDATE para `authenticated`; trigger `ai_op_protect_pending_action` bloqueia mutação de campos imutáveis (`action_name`, `risk_level`, `payload`, `requested_by_user_id`, `session_id`, `draft_id`, `created_at`) e impõe transições válidas. |
| 5.3 | Aprovação/rejeição sem checagem de papel | ✅ Corrigido | helper SQL `ai_op_can_approve(user_id, action)` com matriz determinística; `ai-operator-core` chama-o via RPC antes de aprovar/rejeitar. Tentativas negadas → `action_*_denied` em `ai_operator_audit`. |
| 5.4 | Session ID aceito sem ownership | ✅ Corrigido | `sessionBelongsTo` em `ai-operator-core` valida `owner_user_id = auth.uid()` (ou admin) antes de continuar; tentativas falhas → `session_access_denied` em audit. Tools internas validam `draft.session_id == sessionId`. |
| 5.5 | Channel intake fail-open sem secret | ✅ Corrigido | extraído `auth.ts` com `validateIntakeAuth` — sem secret retorna 503; sem/inválido token retorna 403; comparação em tempo constante. |
| 5.6 | Memória técnica virava fato confirmado | ✅ Corrigido | nova coluna `verification_status` (`candidate`/`verified`/`rejected`); IA cria sempre `candidate`; promoção/rejeição via endpoints `verify_memory_note`/`reject_memory_note` (admin ou technician). Tool renomeada para `register_memory_candidate` (alias `register_memory_note` retém compat). |
| 5.7 | WhatsApp bridge aplicaria ingestão real | ✅ Não aplicada | migration movida para `supabase/deferred-migrations/` (fora de `migrations/`, ignorada pelo pipeline). README documenta condições para futura ativação. |
| 5.8 | Modelo hardcoded | ✅ Configurável | `AI_OPERATOR_MODEL` (env) com default `gemini-3-flash` (mesmo do legacy). |
| 5.9 | RLS ampla demais | ✅ Corrigido | policies granulares — apenas SELECT por authenticated; nenhuma INSERT/UPDATE policy para `authenticated` em sessões/mensagens/drafts/items/pending/audit/memory/channel_events. Toda gravação passa pelo backend com service_role + validações explícitas. |

## Matriz de aprovação — Macro Ciclo 1 RESTRITIVA

> Esta é a política para a **primeira homologação**. A delegação ampla
> (seller para OS, financial para estoque, technician para agenda) foi
> intencionalmente removida até existir executor real para cada classe
> de ação. Macro ciclo seguinte reabrirá com atribuição formal.

### approve_action endpoint (admin-only)

Pre-auth (`preAuthorizeApprove`) bloqueia qualquer role ≠ admin **antes** de
qualquer leitura de `ai_operator_pending_actions`. SQL `ai_op_can_approve`
faz a segunda checagem (admin-only para operacional). Memória técnica não
passa por este endpoint — ver `verify_memory_note`/`reject_memory_note`.

| Action class | admin | technician | financial | seller | external_seller | other |
| --- | :-: | :-: | :-: | :-: | :-: | :-: |
| Qualquer pending action (operacional, conversão, cadastros, envios, agenda, estoque, compras, desconhecidas) | ✓ | – | – | – | – | – |
| Usuário inativo (qualquer papel) | – | – | – | – | – | – |

### Memory governance endpoints (admin OR technician)

| Endpoint | admin | technician | demais |
| --- | :-: | :-: | :-: |
| `verify_memory_note` | ✓ | ✓ | – |
| `reject_memory_note` | ✓ | ✓ | – |

### reject (`ai_op_can_reject`)

| Cenário | admin | technician | financial | seller | external_seller | other | solicitante |
| --- | :-: | :-: | :-: | :-: | :-: | :-: | :-: |
| Ação operacional (qualquer) | ✓ | – | – | – | – | – | ✓ |
| verify/reject de memória técnica | ✓ | ✓ | – | – | – | – | n/a (governança) |
| Usuário inativo | – | – | – | – | – | – | – |

Toda decisão (positiva ou negativa) é registrada em `ai_operator_audit`.
Tentativas negadas usam `event_type='action_approve_denied'` ou
`'action_reject_denied'` com `event_category='security'`.

## Governança de leitura de memória técnica

| `verification_status` | admin | technician | financial | seller | other | external_seller | created_by |
| --- | :-: | :-: | :-: | :-: | :-: | :-: | :-: |
| `verified` | ✓ | ✓ | ✓ | ✓ | ✓ | – | – |
| `candidate` | ✓ | ✓ | – | – | – | – | ✓ |
| `rejected` | ✓ | ✓ | – | – | – | – | ✓ |

`external_seller` nunca recebe candidatos/rejeitados nem mesmo notas verificadas (papel externo, fora do escopo operacional interno).

## Validação de referências do ERP

Antes de gravar qualquer `client_id`/`vessel_id`/`product_id`/`service_id`
em `ai_operator_drafts`, `ai_operator_draft_items` ou `ai_operator_memory_notes`,
o `ai-operator-core` valida que o usuário consegue ler a entidade com seu
próprio JWT (cliente `sb` com a anon key + Authorization Bearer). Isso
respeita as policies de RLS reais de `clients`/`vessels`/`products`/`services`.

- **Visível** → grava a referência.
- **Invisível por RLS / inexistente** → grava o registro SEM a referência e
  audita `event_type='entity_reference_blocked'` (`event_category='security'`).
- **Erro de DB** → tratado como invisível (fail-closed).
- O helper [`entity-validation.ts`](../../supabase/functions/ai-operator-core/entity-validation.ts)
  é testado isoladamente em [`ai-operator-entity-validation.test.ts`](../../src/test/ai-operator-entity-validation.test.ts).

## Aplicação em staging — estado atual

- **Supabase staging** `okurngvcodmljjicopdp`: a foundation
  `ai_operator_foundation` foi aplicada antes do deploy do core
  (registro Supabase `20260523005653`). Tabelas, helpers privados,
  funções server-only, policies, triggers e schema `private` criados.
- **`ai-operator-core`**: AINDA não implantada — depende do hardening
  abaixo entrar primeiro.
- **`ai-operator-channel-intake`**: não implantada.
- **Bridge WhatsApp** (`supabase/deferred-migrations/20260522190100_*`):
  não aplicada.

## Pós-DDL Advisor — remediação de search_path

Após a aplicação da foundation, o Supabase Security Advisor sinalizou:

- **`function_search_path_mutable`** em `public.ai_op_protect_pending_action`.

A função não consulta nenhuma tabela (usa apenas `NEW`/`OLD`/`TG_OP` e
`raise exception`), logo a remediação adequada é `set search_path = ''`,
que impede qualquer resolução de nome não-qualificado em runtime.

**Foi criada migration aditiva de hardening**:
`supabase/migrations/20260523010000_ai_operator_harden_pending_trigger_search_path.sql`

Ela:
- executa `CREATE OR REPLACE FUNCTION` mantendo o corpo idêntico (bloqueio
  de campos imutáveis + transições válidas);
- adiciona `SET search_path = ''`;
- reafirma `REVOKE EXECUTE FROM public, anon, authenticated` e
  `GRANT EXECUTE TO service_role`;
- **não** altera tabelas, policies, dados, outras funções nem bridge WhatsApp.

A foundation (`20260522190000`) também foi atualizada para ambientes novos
— já nasce com `set search_path = ''` nesta trigger function.

Os demais alertas globais do Advisor (RLS de outros módulos, buckets,
funções legadas fora do AI Operator) **serão tratados em macro ciclo
separado** — fogem ao escopo desta correção.

## Modelo de IA para homologação

- Default do `ai-operator-core`: `gemini-2.5-flash` (alinhado ao `ai-agent`
  legacy após upgrade do projeto). Override por env `AI_OPERATOR_MODEL`.
- O legacy expõe `GEMINI_MODEL_SMART` / `GEMINI_MODEL_FAST` / `GEMINI_MODEL`
  — o operador interno **não** lê esses para evitar contaminar configuração
  do agente atual. Use `AI_OPERATOR_MODEL` se quiser desviar.
- Recomendação para homologação do cenário Raymarine: manter o default
  (mesmo modelo já validado em produção do agente). Não baixar para um
  modelo mais simples; o operador depende de fidelidade alta a instrução
  (tool calling + classificação técnica + criação estruturada de rascunho).

## Superfície RPC / SECURITY DEFINER (varredura final)

### Funções em `private` (não expostas pela Data API)

Helpers de papel/atividade vivem em `schema private`. PostgREST só expõe
schemas listados em `db-schemas` (padrão `public`) — `private` fica fora
de RPC. As funções permanecem invocáveis pelas POLICIES de RLS porque
`authenticated` recebe `EXECUTE` direto via `GRANT`.

| Função | EXECUTE |
| --- | --- |
| `private.ai_op_is_admin(uuid)` | `authenticated`, `service_role` (sem PUBLIC, sem anon, sem RPC) |
| `private.ai_op_is_active(uuid)` | idem |
| `private.ai_op_is_admin_or_financial(uuid)` | idem |
| `private.ai_op_is_internal(uuid)` | idem |

Usadas pelas policies de SELECT de `ai_operator_*`. Cliente
autenticado não consegue invocá-las via Data API (PostgREST não mapeia
`private`).

### Funções em `public` server-only (locked down)

Permanecem em `public` apenas porque o `ai-operator-core` precisa chamá-las
via `supabase-js .rpc()` com a service role. EXECUTE revogado de
`PUBLIC/anon/authenticated`; só `service_role` tem permissão:

| Função | Quem chama |
| --- | --- |
| `public.ai_op_can_approve(uuid, text)` | `ai-operator-core` (service_role) |
| `public.ai_op_can_reject(uuid, uuid)` | `ai-operator-core` (service_role) |
| `public.ai_op_protect_pending_action()` | trigger `trg_ai_op_pending_guard` (executado pelo engine sob service_role no UPDATE) |

Mesmo um cliente `authenticated` com conhecimento dos nomes não consegue
chamar via Data API — RPC retorna 401/403.

### Approve gate: admin-only no Macro Ciclo 1

`preAuthorizeApprove` permite apenas `admin`. `technician` continua com
endpoints próprios (`verify_memory_note` / `reject_memory_note`) para
governança de memória — não precisa nem deve passar por `approve_action`.

## Como aplicar em staging (passos para Gustavo)

1. **Aplicar migration `20260522190000_ai_operator_foundation.sql`** em `okurngvcodmljjicopdp`:
   - Via Supabase CLI: `supabase db push` (com `SUPABASE_DB_PASSWORD` configurado).
   - Ou via SQL Editor do Supabase Dashboard colando o arquivo.
   - Verificar: tabelas `ai_operator_*` criadas com RLS habilitada; funções
     `ai_op_is_admin`, `ai_op_is_active`, `ai_op_can_approve` existem;
     trigger `trg_ai_op_pending_guard` em `ai_operator_pending_actions`.

2. **NÃO aplicar** `supabase/deferred-migrations/20260522190100_ai_operator_whatsapp_bridge.sql`.

3. **Deploy da Edge Function `ai-operator-core`**:
   - `supabase functions deploy ai-operator-core --project-ref okurngvcodmljjicopdp`
   - Secrets necessárias (já existentes ou a criar):
     - `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`
     - `GEMINI_API_KEY` (mesma do legacy `ai-agent`)
     - `AI_OPERATOR_MODEL` (opcional; default `gemini-3-flash`)

4. **NÃO** implantar `ai-operator-channel-intake` nesta rodada (sem `AI_OPERATOR_INTAKE_TOKEN` configurada ela já é fail-closed; mantemos sem deploy por opção arquitetural — nada chama ela ainda).

5. **Validar no preview Vercel** da branch:
   - URL: `https://marineflow-erp-git-feat-marineflow-ai-oper-<hash>-...vercel.app`
   - Login normal → abrir o widget de IA → clicar no botão "Bot" para entrar em Modo Operador (beta).
   - Enviar o prompt Raymarine de homologação.
   - Conferir no Supabase: linhas em `ai_operator_sessions`, `ai_operator_messages`, `ai_operator_drafts`, `ai_operator_draft_items`, `ai_operator_audit`. Nenhuma OS oficial criada.

## Testes locais

```
npm test
```

Atualmente 11 arquivos, **52/52** passam, incluindo:
- `ai-operator-risk.test.ts` — gate determinístico (8 casos).
- `ai-operator-approval-matrix.test.ts` — espelho TS da matriz SQL (9 casos).
- `ai-operator-channel-intake.test.ts` — fail-closed do intake (9 casos).

Build (`npm run build`) ok. Avisos de chunk size são preexistentes.

## Limites desta sessão

- Migrations criadas mas **não aplicadas** remotamente (não há credenciais
  Supabase no ambiente desta sessão — `.env*` não foram lidos por regra).
- Edge Functions corrigidas em código mas **não implantadas** remotamente.
- Cenário Raymarine **não executado end-to-end** porque depende de
  migration + deploy + preview com usuário autenticado real.

Tudo que depende de credenciais foi documentado com o comando exato em
"Como aplicar". O próximo passo seguro é:

1. Aplicar a foundation v2 em staging.
2. Deploy de `ai-operator-core` em staging com secrets corretas.
3. Validar Raymarine no preview.
4. Atualizar este documento com IDs/screenshots de evidência.
