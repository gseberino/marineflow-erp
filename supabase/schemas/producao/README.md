# Snapshot do schema de produção

Gerado por `node scripts/snapshot-producao.mjs` em **2026-10-06 19:51:25.497093+00** (banco `postgres`),
lendo os catálogos do Postgres pela CLI (`supabase db query --linked`) — sem pg_dump e sem Docker.

**Por que existe (MF-AUD-058):** o histórico de migrations não reconstrói a produção — havia
migrations aplicadas sem arquivo e arquivos aplicados sem registro. Este diretório é a descrição
fiel do que está no ar. Regenerar e olhar o `git diff` é a forma de ver deriva.

**Não é para `db push`.** É referência, prova e ponto de partida para subir um ambiente do zero
(os arquivos estão em ordem de criação).

## Contagens

| objeto | quantidade |
|---|---:|
| versões em `schema_migrations` | 563 (última: `20261006150000`) |
| schemas | 13 |
| extensões | 10 |
| enums / domains / tipos compostos | 0 / 0 / 0 |
| sequências | 1 |
| tabelas (colunas) | 143 (2213) |
| tabelas com RLS | 143 de 143 |
| chaves estrangeiras | 286 |
| índices (fora de constraint) | 336 |
| funções/procedures | 244 (146 SECURITY DEFINER) |
| views | 22 |
| triggers | 108 |
| políticas de RLS | 281 (31 alcançam anon/public) |
| grants de tabela | 431 |
| crons | 26 |
| buckets | 10 |

## Sinais que valem olhar

- Tabelas **sem RLS**: —
- Funções SECURITY DEFINER **sem `search_path` fixo**: —
- Funções **executáveis por anon** (ACL padrão ou grant explícito): 9 — `_e_concordancia(p_texto text)`, `ai_gateway_claim_job(p_worker_id text, p_token text, p_providers text[], p_lease_seconds integer)`, `ai_gateway_complete_job(p_worker_id text, p_token text, p_job_id uuid, p_lease_id uuid, p_response jsonb, p_provider_used text, p_model_used text, p_duration_ms integer, p_usage jsonb)`, `ai_gateway_fail_job(p_worker_id text, p_token text, p_job_id uuid, p_lease_id uuid, p_error_code text, p_error text, p_retryable boolean, p_retry_after_seconds integer, p_count_attempt boolean, p_provider_used text, p_model_used text, p_duration_ms integer, p_usage jsonb)`, `ai_gateway_heartbeat(p_worker_id text, p_token text, p_job_id uuid, p_lease_id uuid, p_lease_seconds integer)`, `ai_gateway_ping(p_worker_id text, p_token text, p_version text, p_estado jsonb)`, `calc_so_totals(so_id uuid)`, `share_token_da_requisicao()`, `whatsapp_send_queue_idempotencia()`
- Views **sem `security_invoker`**: —
- Buckets **públicos**: `company-assets`, `product-images`, `whatsapp_status`

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
