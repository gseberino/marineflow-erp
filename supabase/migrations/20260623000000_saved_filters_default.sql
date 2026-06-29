-- Add is_default flag to saved_filters
ALTER TABLE public.saved_filters
  ADD COLUMN IF NOT EXISTS is_default boolean NOT NULL DEFAULT false;

-- Expand filter_type CHECK constraint to cover all types used in the app
ALTER TABLE public.saved_filters
  DROP CONSTRAINT IF EXISTS saved_filters_filter_type_check;

ALTER TABLE public.saved_filters
  ADD CONSTRAINT saved_filters_filter_type_check
  CHECK (filter_type IN (
    'payable', 'receivable', 'service_orders', 'quotes', 'products', 'vessels',
    'agenda', 'clients', 'suppliers', 'marinas', 'services', 'inventory',
    'purchase_orders', 'collections', 'crm', 'external_quotes',
    'whatsapp_leads', 'whatsapp_scheduled', 'whatsapp_logs'
  ));

-- Index for efficient default lookup per user
CREATE INDEX IF NOT EXISTS saved_filters_default_idx
  ON public.saved_filters (filter_type, user_id)
  WHERE is_default = true;
