ALTER TABLE service_orders
  ADD COLUMN IF NOT EXISTS payment_conditions text;

CREATE TABLE IF NOT EXISTS public.payment_condition_presets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  label text NOT NULL,
  sort_order integer DEFAULT 0,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE public.payment_condition_presets ENABLE ROW LEVEL SECURITY;

CREATE POLICY payment_condition_presets_select_auth
  ON public.payment_condition_presets
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL);

CREATE POLICY payment_condition_presets_insert_auth
  ON public.payment_condition_presets
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY payment_condition_presets_update_auth
  ON public.payment_condition_presets
  FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY payment_condition_presets_delete_admin
  ON public.payment_condition_presets
  FOR DELETE TO authenticated
  USING (is_admin(auth.uid()));

INSERT INTO public.payment_condition_presets (label, sort_order) VALUES
  ('À vista', 1),
  ('50% de sinal + 50% na entrega', 2),
  ('50% mão de obra + 100% materiais antecipados', 3),
  ('30 dias após conclusão', 4),
  ('Faturado mensalmente', 5);
