ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS fiscal_complete boolean NOT NULL DEFAULT true;