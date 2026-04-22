ALTER TABLE public.service_orders
  ADD COLUMN IF NOT EXISTS payment_method TEXT,
  ADD COLUMN IF NOT EXISTS card_installments INTEGER DEFAULT 1;