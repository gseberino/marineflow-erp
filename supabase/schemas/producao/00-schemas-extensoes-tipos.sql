-- 00 · Schemas, extensões e tipos
-- Gerado por scripts/snapshot-producao.mjs a partir dos catálogos do banco de produção.
-- NÃO editar à mão: regenerar. A data e as contagens ficam no README.md ao lado.

-- Schemas presentes: auth, cron, extensions, graphql, graphql_public, net, pgbouncer, private, public, realtime, storage, supabase_migrations, vault

-- Extensões (nome · versão · schema):
--   btree_gist · 1.7 · extensions
--   pg_cron · 1.6.4 · pg_catalog
--   pg_net · 0.20.0 · public
--   pg_stat_statements · 1.11 · extensions
--   pg_trgm · 1.6 · public
--   pgcrypto · 1.3 · extensions
--   plpgsql · 1.0 · pg_catalog
--   supabase_vault · 0.3.1 · vault
--   unaccent · 1.1 · extensions
--   uuid-ossp · 1.1 · extensions

CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS supabase_vault WITH SCHEMA vault;
CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;

