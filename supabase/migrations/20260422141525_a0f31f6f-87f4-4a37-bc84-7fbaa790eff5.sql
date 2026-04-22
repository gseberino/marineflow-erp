ALTER TABLE public.payment_condition_presets
  ADD COLUMN IF NOT EXISTS installments JSONB DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS auto_generate_collections BOOLEAN DEFAULT true;

UPDATE public.payment_condition_presets
SET installments = '[{"label":"À vista","percent":100,"days_after_approval":0}]'::jsonb
WHERE (label ILIKE '%à vista%' OR label ILIKE '%avista%')
  AND (installments IS NULL OR installments = '[]'::jsonb);

UPDATE public.payment_condition_presets
SET installments = '[{"label":"Entrada 50%","percent":50,"days_after_approval":0},{"label":"Saldo 50%","percent":50,"days_after_approval":30}]'::jsonb
WHERE (label ILIKE '%50%50%' OR label ILIKE '%50/50%')
  AND (installments IS NULL OR installments = '[]'::jsonb);

ALTER TABLE public.service_orders
  ADD COLUMN IF NOT EXISTS payment_condition_preset_id UUID
  REFERENCES public.payment_condition_presets(id) ON DELETE SET NULL;