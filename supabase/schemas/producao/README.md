# Snapshot do schema de produção

Gerado por `node scripts/snapshot-producao.mjs` em **2026-09-14 22:19:12.850899+00** (banco `postgres`),
lendo os catálogos do Postgres pela CLI (`supabase db query --linked`) — sem pg_dump e sem Docker.

**Por que existe (MF-AUD-058):** o histórico de migrations não reconstrói a produção — havia
migrations aplicadas sem arquivo e arquivos aplicados sem registro. Este diretório é a descrição
fiel do que está no ar. Regenerar e olhar o `git diff` é a forma de ver deriva.

**Não é para `db push`.** É referência, prova e ponto de partida para subir um ambiente do zero
(os arquivos estão em ordem de criação).

## Contagens

| objeto | quantidade |
|---|---:|
| versões em `schema_migrations` | 483 (última: `20260914100000`) |
| schemas | 13 |
| extensões | 10 |
| enums / domains / tipos compostos | 0 / 0 / 0 |
| sequências | 1 |
| tabelas (colunas) | 129 (2015) |
| tabelas com RLS | 129 de 129 |
| chaves estrangeiras | 256 |
| índices (fora de constraint) | 232 |
| funções/procedures | 134 (65 SECURITY DEFINER) |
| views | 20 |
| triggers | 91 |
| políticas de RLS | 267 (36 alcançam anon/public) |
| grants de tabela | 401 |
| crons | 19 |
| buckets | 8 |

## Sinais que valem olhar

- Tabelas **sem RLS**: —
- Funções SECURITY DEFINER **sem `search_path` fixo**: —
- Funções **executáveis por anon** (ACL padrão ou grant explícito): 38 — `ai_so_status_change_hook()`, `backfill_message_identity(p_limit integer)`, `bi_margin_by_category(_since date)`, `bi_revenue_by_brand(_since date, _brand text)`, `bi_top_clients(_since date, _limit integer)`, `calc_shift_duration()`, `calc_warranty_expiry()`, `compute_next_run(_from timestamp with time zone, _recurrence_type text, _days_of_week integer[], _day_of_month integer)`, `deduct_stock_on_os_complete()`, `detect_so_change_after_signature()`, `get_agenda_conflicts(p_user_id uuid, p_start timestamp with time zone, p_end timestamp with time zone, p_exclude_task uuid, p_exclude_so uuid)`, `get_entity_open_loops(p_entity_type text, p_entity_id uuid, p_limit integer)`, `get_open_loops(p_direction text, p_limit integer)`, `log_product_cost_change()`, `normalize_alias(_s text)`, `normalize_product_text(t text)`, `pode_ver_folha(_user_id uuid)`, `recalc_po_total(p_po_id uuid)`, `record_conversation_loop(p_entity_type text, p_entity_id uuid, p_loop_key text, p_kind text, p_title text, p_detail text, p_service_order_id uuid, p_due_at timestamp with time zone, p_priority text, p_evidence text, p_evidence_at timestamp with time zone, p_source_message_id uuid)`, `record_conversation_loop(p_entity_type text, p_entity_id uuid, p_loop_key text, p_kind text, p_title text, p_detail text, p_service_order_id uuid, p_due_at timestamp with time zone, p_priority text, p_evidence text, p_evidence_at timestamp with time zone, p_source_message_id uuid, p_direction text)`, `refresh_entity_open_loops()`, `resolve_contact_identity(p_phone text)`, `search_products_trgm(_term text, _lim integer)`, `set_ai_agent_memory_updated_at()`, `set_ai_agent_tasks_updated_at()`, `set_ai_inbound_sessions_updated_at()`, `set_ai_workflows_updated_at()`, `set_updated_at_now()`, `share_token_da_requisicao()`, `touch_fiscal_emission_draft()`, `touch_open_loop(p_loop_id uuid, p_evidence text, p_evidence_at timestamp with time zone, p_source_message_id uuid)`, `touch_updated_at()`, `trg_poi_recalc_total()`, `update_updated_at_column()`, `wa_extract_body_text(p jsonb)`, `wa_extract_message_type(p jsonb)`, `wa_normalize_phone(raw text)`, `whatsapp_pending_inbox(_since timestamp with time zone, _limit integer)`
- Views **sem `security_invoker`**: —
- Buckets **públicos**: `company-assets`, `documents`, `expense-receipts`, `product-images`, `service-order-photos`, `signatures`, `whatsapp_status`

## Arquivos

| arquivo | conteúdo |
|---|---|
| `00-schemas-extensoes-tipos.sql` | schemas, extensões, enums, domains, tipos compostos |
| `01-sequencias.sql` | sequências (as de IDENTITY só comentadas) |
| `02-tabelas.sql` | CREATE TABLE com colunas, PK/UNIQUE/CHECK, comentários, RLS |
| `03-chaves-estrangeiras.sql` | ALTER TABLE ADD CONSTRAINT … FOREIGN KEY |
| `04-indices.sql` | índices fora de constraint |
| `05-funcoes.sql` | `pg_get_functiondef` de cada função + COMMENT + privilégios |
| `06-views.sql` | views em ordem de dependência, com `reloptions` e privilégios |
| `07-triggers.sql` | triggers de public, auth e storage |
| `08-politicas-rls.sql` | CREATE POLICY reconstruído de `pg_policies` |
| `09-privilegios.sql` | grants de tabela/view para anon/authenticated/service_role |
| `10-cron-e-storage.sql` | jobs do pg_cron e buckets |
