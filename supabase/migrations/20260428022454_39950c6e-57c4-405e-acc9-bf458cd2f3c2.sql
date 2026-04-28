-- Garantia em produtos e serviços
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS default_warranty_days integer DEFAULT 0;
ALTER TABLE public.services ADD COLUMN IF NOT EXISTS default_warranty_days integer DEFAULT 0;

-- Garantia nos itens de OS
ALTER TABLE public.service_order_parts ADD COLUMN IF NOT EXISTS warranty_days integer DEFAULT 0;
ALTER TABLE public.service_order_services ADD COLUMN IF NOT EXISTS warranty_days integer DEFAULT 0;

-- Tabela de notas fiscais importadas
CREATE TABLE IF NOT EXISTS public.fiscal_notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nfe_key text UNIQUE NOT NULL,
  nfe_number text,
  issuer_name text,
  issuer_cnpj text,
  issue_date date,
  total_value numeric DEFAULT 0,
  status text NOT NULL DEFAULT 'imported',
  xml_url text,
  raw_xml text,
  payable_id uuid,
  supplier_id uuid,
  notes text,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.fiscal_note_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fiscal_note_id uuid NOT NULL REFERENCES public.fiscal_notes(id) ON DELETE CASCADE,
  c_prod text,
  x_prod text,
  ncm text,
  unit text,
  q_com numeric DEFAULT 0,
  v_un_com numeric DEFAULT 0,
  v_prod numeric DEFAULT 0,
  matched_product_id uuid,
  inventory_movement_id uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.fiscal_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fiscal_note_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated_all_fiscal_notes" ON public.fiscal_notes
  FOR ALL TO authenticated USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "authenticated_all_fiscal_note_items" ON public.fiscal_note_items
  FOR ALL TO authenticated USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);

CREATE TRIGGER update_fiscal_notes_updated_at
  BEFORE UPDATE ON public.fiscal_notes
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE INDEX IF NOT EXISTS idx_fiscal_note_items_note ON public.fiscal_note_items(fiscal_note_id);
CREATE INDEX IF NOT EXISTS idx_fiscal_note_items_matched_product ON public.fiscal_note_items(matched_product_id);