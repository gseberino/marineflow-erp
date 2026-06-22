-- Versiona a migração "rename_cols_normalize_column_names" que foi aplicada
-- diretamente no banco em 2026-06-12 mas nunca havia sido salva como migration.
--
-- CONTEXTO: o banco de produção (okurngvcodmljjicopdp) JÁ tem estas colunas
-- renomeadas. Esta migration existe para PARIDADE de versionamento — garante
-- que um ambiente novo (clone/staging) chegue ao mesmo schema, e impede que
-- código e banco voltem a divergir silenciosamente (causa do incidente de jun/2026).
--
-- É IDEMPOTENTE: cada rename só ocorre se a coluna antiga ainda existir e a
-- nova ainda não existir. Rodar de novo num banco já migrado é no-op seguro.

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('clients',                'full_name_or_company_name', 'name'),
      ('external_quote_leads',   'full_name_or_company_name', 'name'),
      ('suppliers',              'supplier_name',             'name'),
      ('suppliers',              'contact_phone',             'phone'),
      ('suppliers',              'contact_email',             'email'),
      ('marinas',                'marina_name',               'name'),
      ('marinas',                'contact_phone',             'phone'),
      ('marinas',                'contact_email',             'email'),
      ('products',               'product_name',              'name'),
      ('services',               'service_name',              'name'),
      ('whatsapp_leads',         'display_name',              'name'),
      ('external_quote_parts',   'product_name_snapshot',     'name_snapshot'),
      ('service_order_services', 'service_name_snapshot',     'name_snapshot'),
      ('external_quote_services','service_name_snapshot',     'name_snapshot'),
      ('collections',            'contact_phone',             'phone')
    ) AS t(tbl, oldcol, newcol)
  LOOP
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = r.tbl AND column_name = r.oldcol
    ) AND NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = r.tbl AND column_name = r.newcol
    ) THEN
      EXECUTE format('ALTER TABLE public.%I RENAME COLUMN %I TO %I', r.tbl, r.oldcol, r.newcol);
      RAISE NOTICE 'Renamed %.% -> %', r.tbl, r.oldcol, r.newcol;
    END IF;
  END LOOP;
END $$;
