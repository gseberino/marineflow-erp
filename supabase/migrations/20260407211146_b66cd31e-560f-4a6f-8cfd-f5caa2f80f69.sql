
-- 1. Suppliers table
CREATE TABLE public.suppliers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_name text NOT NULL,
  trade_name text,
  cnpj_cpf text,
  contact_name text,
  contact_phone text,
  contact_email text,
  website text,
  postal_code text,
  address_line_1 text,
  address_number text,
  address_complement text,
  neighborhood text,
  city text,
  state text,
  country text DEFAULT 'Brazil',
  payment_terms text,
  notes text,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- 2. Product-supplier relationship
CREATE TABLE public.product_suppliers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  supplier_id uuid NOT NULL REFERENCES public.suppliers(id) ON DELETE CASCADE,
  supplier_sku text,
  cost_price numeric(12,2),
  currency text DEFAULT 'BRL',
  lead_time_days integer,
  minimum_order_qty numeric(10,3) DEFAULT 1,
  is_preferred boolean DEFAULT false,
  last_purchase_date date,
  last_purchase_price numeric(12,2),
  notes text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(product_id, supplier_id)
);

-- 3. Link payables to supplier
ALTER TABLE public.payables
  ADD COLUMN IF NOT EXISTS supplier_id uuid REFERENCES public.suppliers(id);

-- 4. RLS
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "allow_all_suppliers" ON public.suppliers FOR ALL TO authenticated USING (true) WITH CHECK (true);

ALTER TABLE public.product_suppliers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "allow_all_product_suppliers" ON public.product_suppliers FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 5. Triggers
CREATE TRIGGER set_updated_at_suppliers
  BEFORE UPDATE ON public.suppliers
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER set_updated_at_product_suppliers
  BEFORE UPDATE ON public.product_suppliers
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- 6. Seed company address keys
INSERT INTO public.app_settings (key, value, description) VALUES
  ('company_postal_code', '88301-000', 'CEP da empresa'),
  ('company_neighborhood', 'Cidade Nova', 'Bairro da empresa'),
  ('company_city', 'Itajaí', 'Cidade da empresa'),
  ('company_state', 'SC', 'Estado da empresa'),
  ('company_country', 'Brazil', 'País da empresa')
ON CONFLICT (key) DO NOTHING;
