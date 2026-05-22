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

## Matriz de autorização (`ai_op_can_approve`)

| Action | admin | technician | financial | seller | external_seller | other |
| --- | :-: | :-: | :-: | :-: | :-: | :-: |
| send_whatsapp_message / send_collection_reminder / send_service_order_link | ✓ | – | – | – | – | – |
| schedule_whatsapp_message / cancel_scheduled_whatsapp | ✓ | – | – | – | – | – |
| adjust_inventory / create_purchase_order | ✓ | – | ✓ | – | – | – |
| create_agenda_task / update_agenda_task / schedule_service_order | ✓ | ✓ | – | – | – | – |
| create_service_order / update_service_order_status / add_service_order_item / add_service_to_order / apply_service_order_discount / convert_draft_to_service_order | ✓ | – | – | ✓ | – | – |
| create_client / create_vessel / create_product | ✓ | – | ✓ | ✓ | – | – |
| verify_memory_note / reject_memory_note | ✓ | ✓ | – | – | – | – |
| (ações desconhecidas) | ✓ | – | – | – | – | – |
| usuário inativo | – | – | – | – | – | – |

**`external_seller` nunca aprova nada do operator.** Fail-closed para qualquer combinação não listada.

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
