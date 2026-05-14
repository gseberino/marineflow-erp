
ALTER TABLE public.whatsapp_leads ADD COLUMN name text GENERATED ALWAYS AS (display_name) STORED;
ALTER TABLE public.external_quote_leads ADD COLUMN name text GENERATED ALWAYS AS (full_name_or_company_name) STORED;
