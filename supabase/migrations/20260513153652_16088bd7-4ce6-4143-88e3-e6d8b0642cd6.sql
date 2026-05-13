-- Add generated 'name' columns aliasing real columns so existing app code works
ALTER TABLE public.clients   ADD COLUMN IF NOT EXISTS name text GENERATED ALWAYS AS (full_name_or_company_name) STORED;
ALTER TABLE public.vessels   ADD COLUMN IF NOT EXISTS name text GENERATED ALWAYS AS (boat_name) STORED;
ALTER TABLE public.products  ADD COLUMN IF NOT EXISTS name text GENERATED ALWAYS AS (product_name) STORED;
ALTER TABLE public.marinas   ADD COLUMN IF NOT EXISTS name text GENERATED ALWAYS AS (marina_name) STORED;
ALTER TABLE public.suppliers ADD COLUMN IF NOT EXISTS name text GENERATED ALWAYS AS (supplier_name) STORED;
ALTER TABLE public.services  ADD COLUMN IF NOT EXISTS name text GENERATED ALWAYS AS (service_name) STORED;