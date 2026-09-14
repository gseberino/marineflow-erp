# Snapshot do schema de produção

Gerado por `node scripts/snapshot-producao.mjs` em **2026-09-14 23:33:19.019177+00** (banco `postgres`),
lendo os catálogos do Postgres pela CLI (`supabase db query --linked`) — sem pg_dump e sem Docker.

**Por que existe (MF-AUD-058):** o histórico de migrations não reconstrói a produção — havia
migrations aplicadas sem arquivo e arquivos aplicados sem registro. Este diretório é a descrição
fiel do que está no ar. Regenerar e olhar o `git diff` é a forma de ver deriva.

**Não é para `db push`.** É referência, prova e ponto de partida para subir um ambiente do zero
(os arquivos estão em ordem de criação).

## Contagens

| objeto | quantidade |
|---|---:|
| versões em `schema_migrations` | 484 (última: `20260914120000`) |
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
- Funções **executáveis por anon** (ACL padrão ou grant explícito): 2 — `ai_so_status_change_hook()`, `share_token_da_requisicao()`
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
