ALTER TABLE public.saved_filters DROP CONSTRAINT IF EXISTS saved_filters_filter_type_check;
ALTER TABLE public.saved_filters ADD CONSTRAINT saved_filters_filter_type_check CHECK (filter_type IN ('payable','receivable','service_orders','products','vessels','agenda'));
ALTER TABLE public.saved_filters ADD COLUMN IF NOT EXISTS user_id uuid;
CREATE INDEX IF NOT EXISTS saved_filters_type_idx ON public.saved_filters(filter_type);