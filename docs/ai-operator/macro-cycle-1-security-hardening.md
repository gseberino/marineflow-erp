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

### approve (`ai_op_can_approve`)

| Action class | admin | technician | financial | seller | external_seller | other |
| --- | :-: | :-: | :-: | :-: | :-: | :-: |
| Qualquer ação operacional (WhatsApp, OS, agenda, estoque, compras, cadastros, conversão de rascunho, ações desconhecidas) | ✓ | – | – | – | – | – |
| verify_memory_note / reject_memory_note | ✓ | ✓ | – | – | – | – |
| Usuário inativo (qualquer papel) | – | – | – | – | – | – |

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
