-- Fix constraint to include ALL filter types used in the app
ALTER TABLE public.saved_filters DROP CONSTRAINT IF EXISTS saved_filters_filter_type_check;
ALTER TABLE public.saved_filters ADD CONSTRAINT saved_filters_filter_type_check
  CHECK (filter_type IN (
    'payable','receivable','service_orders','products','vessels','agenda',
    'clients','suppliers','marinas','services','inventory','purchase_orders',
    'collections','crm','external_quotes','whatsapp_leads','whatsapp_scheduled','whatsapp_logs'
  ));

-- Add is_default column
ALTER TABLE public.saved_filters ADD COLUMN IF NOT EXISTS is_default boolean NOT NULL DEFAULT false;

-- One default preset per filter_type per user (NULL user_id treated as anonymous sentinel)
CREATE UNIQUE INDEX IF NOT EXISTS saved_filters_one_default_per_type
  ON public.saved_filters (filter_type, COALESCE(user_id, '00000000-0000-0000-0000-000000000000'::uuid))
  WHERE is_default = true;
