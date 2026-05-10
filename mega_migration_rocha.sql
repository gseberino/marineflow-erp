-- MARINEFLOW ROCHA - SCRIPT DE INSTALAÇÃO ÚNICA (ZERO FALHAS)
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO anon;
GRANT ALL ON SCHEMA public TO authenticated;
GRANT ALL ON SCHEMA public TO service_role;

-- 2. PRE-REQUISITOS (Tabelas que causam conflito se não criadas na ordem certa)
CREATE TABLE public.fiscal_notes (
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

CREATE TABLE public.fiscal_note_items (
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

CREATE TABLE public.supplier_product_mappings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_id UUID,
  supplier_sku TEXT NOT NULL,
  supplier_description TEXT,
  internal_product_id UUID,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(supplier_id, supplier_sku)
);

CREATE TABLE public.product_price_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID,
  old_cost NUMERIC,
  new_cost NUMERIC,
  fiscal_note_id UUID REFERENCES public.fiscal_notes(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE public.price_update_suggestions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID,
  fiscal_note_id UUID REFERENCES public.fiscal_notes(id) ON DELETE CASCADE,
  current_sale_price NUMERIC,
  suggested_sale_price NUMERIC,
  margin_percent NUMERIC,
  status TEXT DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 1. Shared trigger function for updated_at
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

-- ============================================================
-- 1. app_users
-- ============================================================
CREATE TABLE public.app_users (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name text NOT NULL,
  email text NOT NULL UNIQUE,
  phone text,
  role text NOT NULL CHECK (role IN ('admin', 'technician', 'financial')),
  active boolean NOT NULL DEFAULT true,
  avatar_url text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.app_users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated users can do everything on app_users" ON public.app_users FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE TRIGGER update_app_users_updated_at BEFORE UPDATE ON public.app_users FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 2. marinas
-- ============================================================
CREATE TABLE public.marinas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  marina_name text NOT NULL,
  contact_name text,
  contact_phone text,
  contact_email text,
  address_line_1 text,
  city text,
  state text,
  postal_code text,
  country text DEFAULT 'Brazil',
  latitude numeric(10,7),
  longitude numeric(10,7),
  access_notes text,
  billing_notes text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.marinas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated users can do everything on marinas" ON public.marinas FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE TRIGGER update_marinas_updated_at BEFORE UPDATE ON public.marinas FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 3. clients
-- ============================================================
CREATE TABLE public.clients (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type text NOT NULL CHECK (type IN ('individual', 'company')),
  full_name_or_company_name text NOT NULL,
  cpf_cnpj text,
  phone text,
  whatsapp text,
  email text,
  address_line_1 text,
  address_line_2 text,
  city text,
  state text,
  postal_code text,
  country text DEFAULT 'Brazil',
  notes text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated users can do everything on clients" ON public.clients FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE TRIGGER update_clients_updated_at BEFORE UPDATE ON public.clients FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 4. vessels
-- ============================================================
CREATE TABLE public.vessels (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id uuid NOT NULL REFERENCES public.clients(id) ON DELETE RESTRICT,
  marina_id uuid REFERENCES public.marinas(id) ON DELETE RESTRICT,
  boat_name text NOT NULL,
  manufacturer text,
  model text,
  year integer,
  hull_id_or_registration text,
  length_feet numeric(6,2),
  beam_feet numeric(6,2),
  draft_feet numeric(6,2),
  engine_type text,
  engine_brand text,
  engine_model text,
  engine_quantity integer DEFAULT 1,
  propulsion_type text,
  shore_power_type text,
  battery_bank_summary text,
  inverter_charger_summary text,
  navigation_electronics_summary text,
  electrical_system_notes text,
  current_marina_name_snapshot text,
  current_dock_position text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.vessels ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated users can do everything on vessels" ON public.vessels FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE TRIGGER update_vessels_updated_at BEFORE UPDATE ON public.vessels FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 5. products
-- ============================================================
CREATE TABLE public.products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sku text UNIQUE,
  product_name text NOT NULL,
  category text,
  brand text,
  unit text DEFAULT 'pcs',
  cost_price numeric(12,2) DEFAULT 0,
  sale_price numeric(12,2) DEFAULT 0,
  cost_currency text DEFAULT 'BRL',
  sale_currency text DEFAULT 'BRL',
  stock_quantity numeric(10,3) DEFAULT 0,
  minimum_stock numeric(10,3) DEFAULT 0,
  location_bin text,
  barcode text,
  notes text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated users can do everything on products" ON public.products FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE TRIGGER update_products_updated_at BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 6. service_orders
-- ============================================================
CREATE TABLE public.service_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  service_order_number text NOT NULL UNIQUE,
  client_id uuid NOT NULL REFERENCES public.clients(id) ON DELETE RESTRICT,
  vessel_id uuid NOT NULL REFERENCES public.vessels(id) ON DELETE RESTRICT,
  marina_id uuid REFERENCES public.marinas(id) ON DELETE RESTRICT,
  requested_by_name text,
  scheduled_start_at timestamptz,
  scheduled_end_at timestamptz,
  check_in_at timestamptz,
  check_out_at timestamptz,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','scheduled','open','in_progress','awaiting_parts','awaiting_client','completed','invoiced','cancelled')),
  priority text NOT NULL DEFAULT 'normal' CHECK (priority IN ('low','normal','high','urgent')),
  service_type text CHECK (service_type IN ('diagnosis','repair','installation','preventive_maintenance','consulting','engineering_project','commissioning','inspection')),
  problem_description text,
  initial_findings text,
  diagnosis text,
  solution_applied text,
  technician_notes text,
  internal_notes text,
  customer_visible_report text,
  hourly_rate numeric(10,2) DEFAULT 0,
  estimated_hours numeric(8,2) DEFAULT 0,
  labor_hours_total numeric(8,2) DEFAULT 0,
  labor_cost_total numeric(12,2) DEFAULT 0,
  travel_distance_km numeric(8,2) DEFAULT 0,
  travel_cost_per_km numeric(8,2) DEFAULT 0,
  technician_count_for_travel integer DEFAULT 1,
  travel_cost_total numeric(12,2) DEFAULT 0,
  parts_cost_total numeric(12,2) DEFAULT 0,
  subcontract_cost_total numeric(12,2) DEFAULT 0,
  discount_amount numeric(12,2) DEFAULT 0,
  tax_amount numeric(12,2) DEFAULT 0,
  grand_total numeric(12,2) DEFAULT 0,
  currency text DEFAULT 'BRL',
  invoicing_status text DEFAULT 'not_invoiced' CHECK (invoicing_status IN ('not_invoiced','invoiced','partially_invoiced')),
  payment_status text DEFAULT 'unpaid' CHECK (payment_status IN ('unpaid','partially_paid','paid')),
  client_signature_url text,
  created_by uuid REFERENCES public.app_users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.service_orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated users can do everything on service_orders" ON public.service_orders FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE TRIGGER update_service_orders_updated_at BEFORE UPDATE ON public.service_orders FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 7. service_order_technicians
-- ============================================================
CREATE TABLE public.service_order_technicians (
  id uuid DEFAULT gen_random_uuid(),
  service_order_id uuid NOT NULL REFERENCES public.service_orders(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.app_users(id) ON DELETE RESTRICT,
  role_in_order text DEFAULT 'technician',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (service_order_id, user_id)
);
ALTER TABLE public.service_order_technicians ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated users can do everything on service_order_technicians" ON public.service_order_technicians FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE TRIGGER update_service_order_technicians_updated_at BEFORE UPDATE ON public.service_order_technicians FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 8. service_order_parts
-- ============================================================
CREATE TABLE public.service_order_parts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  service_order_id uuid NOT NULL REFERENCES public.service_orders(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  quantity numeric(10,3) NOT NULL,
  unit_cost_snapshot numeric(12,2) NOT NULL,
  unit_sale_snapshot numeric(12,2) NOT NULL,
  currency_snapshot text DEFAULT 'BRL',
  line_total_cost numeric(12,2) NOT NULL,
  line_total_sale numeric(12,2) NOT NULL,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.service_order_parts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated users can do everything on service_order_parts" ON public.service_order_parts FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE TRIGGER update_service_order_parts_updated_at BEFORE UPDATE ON public.service_order_parts FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 9. time_entries
-- ============================================================
CREATE TABLE public.time_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  service_order_id uuid NOT NULL REFERENCES public.service_orders(id) ON DELETE CASCADE,
  technician_user_id uuid NOT NULL REFERENCES public.app_users(id) ON DELETE RESTRICT,
  started_at timestamptz NOT NULL,
  ended_at timestamptz,
  duration_minutes integer,
  billable boolean DEFAULT true,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.time_entries ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated users can do everything on time_entries" ON public.time_entries FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE TRIGGER update_time_entries_updated_at BEFORE UPDATE ON public.time_entries FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 10. inventory_movements (immutable log â€” no updated_at)
-- ============================================================
CREATE TABLE public.inventory_movements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  movement_type text NOT NULL CHECK (movement_type IN ('purchase','manual_adjustment','service_usage','return','transfer')),
  quantity_delta numeric(10,3) NOT NULL,
  reference_type text,
  reference_id uuid,
  unit_cost_snapshot numeric(12,2),
  notes text,
  created_by uuid REFERENCES public.app_users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.inventory_movements ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated users can do everything on inventory_movements" ON public.inventory_movements FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- ============================================================
-- 11. invoices
-- ============================================================
CREATE TABLE public.invoices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_number text NOT NULL UNIQUE,
  service_order_id uuid REFERENCES public.service_orders(id) ON DELETE RESTRICT,
  client_id uuid NOT NULL REFERENCES public.clients(id) ON DELETE RESTRICT,
  issue_date date NOT NULL,
  due_date date NOT NULL,
  subtotal numeric(12,2) DEFAULT 0,
  discount_amount numeric(12,2) DEFAULT 0,
  tax_amount numeric(12,2) DEFAULT 0,
  total_amount numeric(12,2) DEFAULT 0,
  currency text DEFAULT 'BRL',
  status text DEFAULT 'draft' CHECK (status IN ('draft','sent','paid','overdue','cancelled')),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated users can do everything on invoices" ON public.invoices FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE TRIGGER update_invoices_updated_at BEFORE UPDATE ON public.invoices FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 12. receivables
-- ============================================================
CREATE TABLE public.receivables (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id uuid NOT NULL REFERENCES public.clients(id) ON DELETE RESTRICT,
  invoice_id uuid REFERENCES public.invoices(id) ON DELETE RESTRICT,
  service_order_id uuid REFERENCES public.service_orders(id) ON DELETE RESTRICT,
  description text NOT NULL,
  issue_date date NOT NULL,
  due_date date NOT NULL,
  amount numeric(12,2) NOT NULL,
  currency text DEFAULT 'BRL',
  status text DEFAULT 'pending' CHECK (status IN ('pending','partially_paid','paid','overdue','cancelled')),
  payment_method text,
  paid_amount numeric(12,2) DEFAULT 0,
  balance_amount numeric(12,2) DEFAULT 0,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.receivables ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated users can do everything on receivables" ON public.receivables FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE TRIGGER update_receivables_updated_at BEFORE UPDATE ON public.receivables FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 13. payables
-- ============================================================
CREATE TABLE public.payables (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_name text,
  expense_category text,
  description text NOT NULL,
  issue_date date NOT NULL,
  due_date date NOT NULL,
  amount numeric(12,2) NOT NULL,
  currency text DEFAULT 'BRL',
  status text DEFAULT 'pending' CHECK (status IN ('pending','partially_paid','paid','overdue','cancelled')),
  payment_method text,
  paid_amount numeric(12,2) DEFAULT 0,
  balance_amount numeric(12,2) DEFAULT 0,
  linked_service_order_id uuid REFERENCES public.service_orders(id) ON DELETE RESTRICT,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.payables ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated users can do everything on payables" ON public.payables FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE TRIGGER update_payables_updated_at BEFORE UPDATE ON public.payables FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 14. exchange_rates
-- ============================================================
CREATE TABLE public.exchange_rates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  from_currency text NOT NULL,
  to_currency text NOT NULL,
  rate numeric(18,8) NOT NULL,
  source text DEFAULT 'manual',
  recorded_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.exchange_rates ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated users can do everything on exchange_rates" ON public.exchange_rates FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- ============================================================
-- 15. app_settings
-- ============================================================
CREATE TABLE public.app_settings (
  key text PRIMARY KEY,
  value text NOT NULL,
  description text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated users can do everything on app_settings" ON public.app_settings FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE TRIGGER update_app_settings_updated_at BEFORE UPDATE ON public.app_settings FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Seed default settings
INSERT INTO public.app_settings (key, value, description) VALUES
  ('base_currency', 'BRL', 'Moeda base do sistema'),
  ('display_currency', 'BRL', 'Moeda de exibiÃ§Ã£o padrÃ£o'),
  ('language', 'pt-BR', 'Idioma padrÃ£o'),
  ('company_name', 'MarineFlow', 'Nome da empresa'),
  ('company_address', 'Rua JosÃ© Domingos Machado, 230, Cidade Nova, ItajaÃ­ - SC', 'EndereÃ§o da base operacional'),
  ('travel_base_lat', '-26.9189', 'Latitude da base para cÃ¡lculo de deslocamento'),
  ('travel_base_lng', '-48.6728', 'Longitude da base para cÃ¡lculo de deslocamento'),
  ('travel_cost_per_km', '3.50', 'Custo por km de deslocamento em BRL'),
  ('card_fee_percent', '3.5', 'Taxa mÃ©dia de cartÃ£o de crÃ©dito (%)');

-- ============================================================
-- Useful indexes
-- ============================================================
CREATE INDEX idx_vessels_client_id ON public.vessels(client_id);
CREATE INDEX idx_vessels_marina_id ON public.vessels(marina_id);
CREATE INDEX idx_service_orders_client_id ON public.service_orders(client_id);
CREATE INDEX idx_service_orders_vessel_id ON public.service_orders(vessel_id);
CREATE INDEX idx_service_orders_marina_id ON public.service_orders(marina_id);
CREATE INDEX idx_service_orders_status ON public.service_orders(status);
CREATE INDEX idx_service_order_parts_so_id ON public.service_order_parts(service_order_id);
CREATE INDEX idx_time_entries_so_id ON public.time_entries(service_order_id);
CREATE INDEX idx_inventory_movements_product_id ON public.inventory_movements(product_id);
CREATE INDEX idx_receivables_client_id ON public.receivables(client_id);
CREATE INDEX idx_payables_linked_so_id ON public.payables(linked_service_order_id);
CREATE INDEX idx_invoices_client_id ON public.invoices(client_id);
CREATE INDEX idx_invoices_so_id ON public.invoices(service_order_id);
CREATE INDEX idx_exchange_rates_currencies ON public.exchange_rates(from_currency, to_currency, recorded_at);

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
  ('company_city', 'ItajaÃ­', 'Cidade da empresa'),
  ('company_state', 'SC', 'Estado da empresa'),
  ('company_country', 'Brazil', 'PaÃ­s da empresa')
ON CONFLICT (key) DO NOTHING;

DO $$
DECLARE
  t text;
  tables text[] := ARRAY[
    'clients', 'vessels', 'marinas', 'products', 'service_orders',
    'service_order_technicians', 'service_order_parts', 'time_entries',
    'inventory_movements', 'invoices', 'receivables', 'payables',
    'exchange_rates', 'app_settings', 'app_users', 'suppliers',
    'product_suppliers'
  ];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    EXECUTE format('DROP POLICY IF EXISTS "allow_all_%s" ON %I', t, t);
    EXECUTE format('DROP POLICY IF EXISTS "Authenticated users can do everything on %s" ON %I', t, t);
    EXECUTE format('DROP POLICY IF EXISTS "Authenticated users can do everything on %s" ON %I', regexp_replace(t, '_', ' ', 'g'), t);
    EXECUTE format(
      'CREATE POLICY "allow_all_%s" ON %I AS PERMISSIVE FOR ALL TO anon, authenticated USING (true) WITH CHECK (true)',
      t, t
    );
  END LOOP;
END $$;

-- 1. Services catalog table
CREATE TABLE services (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  service_name text NOT NULL,
  description text,
  category text,
  billing_unit text NOT NULL DEFAULT 'hour' 
    CHECK (billing_unit IN ('hour', 'visit', 'day', 'unit')),
  default_price numeric(12,2) DEFAULT 0,
  currency text DEFAULT 'BRL',
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE services ENABLE ROW LEVEL SECURITY;
CREATE POLICY allow_all_services ON services 
  AS PERMISSIVE FOR ALL TO anon, authenticated 
  USING (true) WITH CHECK (true);

CREATE TRIGGER set_updated_at_services
  BEFORE UPDATE ON services
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 2. Service order labor lines
CREATE TABLE service_order_services (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  service_order_id uuid NOT NULL REFERENCES service_orders(id) ON DELETE CASCADE,
  service_id uuid REFERENCES services(id),
  service_name_snapshot text NOT NULL,
  description_snapshot text,
  billing_unit_snapshot text NOT NULL DEFAULT 'hour',
  quantity numeric(10,3) NOT NULL DEFAULT 1,
  unit_price_snapshot numeric(12,2) NOT NULL DEFAULT 0,
  line_total numeric(12,2) NOT NULL DEFAULT 0,
  notes text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE service_order_services ENABLE ROW LEVEL SECURITY;
CREATE POLICY allow_all_service_order_services ON service_order_services
  AS PERMISSIVE FOR ALL TO anon, authenticated
  USING (true) WITH CHECK (true);

CREATE TRIGGER set_updated_at_service_order_services
  BEFORE UPDATE ON service_order_services
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 3. Card installment fee table
CREATE TABLE card_installment_fees (
  installments integer PRIMARY KEY CHECK (installments BETWEEN 1 AND 6),
  fee_percent numeric(6,4) NOT NULL DEFAULT 0,
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE card_installment_fees ENABLE ROW LEVEL SECURITY;
CREATE POLICY allow_all_card_fees ON card_installment_fees
  AS PERMISSIVE FOR ALL TO anon, authenticated
  USING (true) WITH CHECK (true);

-- Seed default installment fees
INSERT INTO card_installment_fees (installments, fee_percent) VALUES
  (1, 2.49),
  (2, 3.49),
  (3, 4.49),
  (4, 5.49),
  (5, 6.49),
  (6, 7.49)
ON CONFLICT (installments) DO NOTHING;

-- 4. Seed standard terms into app_settings
INSERT INTO app_settings (key, value, description) VALUES
  ('terms_warranty', 
   'Os serviÃ§os executados possuem garantia de 90 dias para mÃ£o de obra a contar da data de conclusÃ£o. PeÃ§as e equipamentos seguem a garantia do fabricante.',
   'Termos de garantia padrÃ£o'),
  ('terms_cancellation',
   'O cancelamento do serviÃ§o deve ser comunicado com no mÃ­nimo 24 horas de antecedÃªncia. ServiÃ§os jÃ¡ iniciados serÃ£o cobrados proporcionalmente Ã s horas trabalhadas e materiais utilizados.',
   'Termos de cancelamento'),
  ('terms_delivery',
   'O prazo de entrega de produtos e equipamentos importados pode variar de 15 a 45 dias Ãºteis, sujeito Ã  disponibilidade do fabricante e liberaÃ§Ã£o alfandegÃ¡ria.',
   'ObservaÃ§Ãµes sobre prazo de entrega'),
  ('terms_responsibilities',
   'O cliente Ã© responsÃ¡vel por garantir acesso Ã  embarcaÃ§Ã£o no horÃ¡rio agendado. A empresa nÃ£o se responsabiliza por danos prÃ©-existentes nÃ£o documentados antes do inÃ­cio do serviÃ§o.',
   'Responsabilidades e obrigaÃ§Ãµes'),
  ('terms_general',
   'Todos os serviÃ§os sÃ£o executados por profissionais qualificados. Os valores apresentados neste documento sÃ£o vÃ¡lidos por 15 dias a partir da data de emissÃ£o.',
   'ObservaÃ§Ãµes gerais')
ON CONFLICT (key) DO NOTHING;

CREATE TABLE payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  receivable_id uuid REFERENCES receivables(id) ON DELETE CASCADE,
  payable_id uuid REFERENCES payables(id) ON DELETE CASCADE,
  payment_date date NOT NULL DEFAULT CURRENT_DATE,
  amount numeric(12,2) NOT NULL,
  payment_method text NOT NULL DEFAULT 'pix'
    CHECK (payment_method IN ('pix','credit_card','debit_card','cash','bank_transfer','check')),
  installments integer DEFAULT 1,
  card_fee_percent numeric(6,4) DEFAULT 0,
  net_amount numeric(12,2),
  notes text,
  created_at timestamptz DEFAULT now(),
  CONSTRAINT chk_payment_target CHECK (
    (receivable_id IS NOT NULL AND payable_id IS NULL) OR
    (receivable_id IS NULL AND payable_id IS NOT NULL)
  )
);

CREATE TABLE bank_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transaction_date date NOT NULL,
  description text NOT NULL,
  amount numeric(12,2) NOT NULL,
  transaction_type text NOT NULL CHECK (transaction_type IN ('credit','debit')),
  bank_ref_id text,
  reconciled boolean DEFAULT false,
  reconciled_payment_id uuid REFERENCES payments(id),
  import_batch_id text,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
CREATE POLICY allow_all_payments ON payments
  AS PERMISSIVE FOR ALL TO anon, authenticated
  USING (true) WITH CHECK (true);

ALTER TABLE bank_transactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY allow_all_bank_transactions ON bank_transactions
  AS PERMISSIVE FOR ALL TO anon, authenticated
  USING (true) WITH CHECK (true);

-- 1. Operational expenses table
CREATE TABLE service_order_expenses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  service_order_id uuid REFERENCES service_orders(id) ON DELETE CASCADE,
  category text NOT NULL,
  description text NOT NULL,
  amount numeric(12,2) NOT NULL,
  currency text DEFAULT 'BRL',
  expense_date date NOT NULL DEFAULT CURRENT_DATE,
  paid_by text NOT NULL DEFAULT 'company'
    CHECK (paid_by IN ('company', 'technician')),
  technician_user_id uuid REFERENCES app_users(id),
  reimbursed boolean DEFAULT false,
  reimbursed_at timestamptz,
  reimbursed_payment_id uuid REFERENCES payments(id),
  receipt_url text,
  linked_payable_id uuid REFERENCES payables(id),
  notes text,
  created_by uuid REFERENCES app_users(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE service_order_expenses ENABLE ROW LEVEL SECURITY;

CREATE POLICY allow_all_service_order_expenses ON service_order_expenses
  AS PERMISSIVE FOR ALL TO anon, authenticated
  USING (true) WITH CHECK (true);

CREATE TRIGGER set_updated_at_so_expenses
  BEFORE UPDATE ON service_order_expenses
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 2. Add operational_cost_total to service_orders
ALTER TABLE service_orders
  ADD COLUMN IF NOT EXISTS operational_cost_total numeric(12,2) DEFAULT 0;

-- 3. Add source_type to bank_transactions
ALTER TABLE bank_transactions
  ADD COLUMN IF NOT EXISTS source_type text DEFAULT 'bank';

-- 4. Add direct SO link to bank_transactions
ALTER TABLE bank_transactions
  ADD COLUMN IF NOT EXISTS reconciled_service_order_id uuid REFERENCES service_orders(id);

ALTER TABLE payables
  ADD COLUMN IF NOT EXISTS origin text DEFAULT 'manual',
  ADD COLUMN IF NOT EXISTS bank_transaction_id uuid REFERENCES bank_transactions(id);

ALTER TABLE payables ADD CONSTRAINT chk_payables_origin CHECK (origin IN ('manual', 'service_order_expense', 'bank_reconciliation'));

UPDATE payables SET origin = 'service_order_expense' 
  WHERE linked_service_order_id IS NOT NULL AND origin = 'manual';

CREATE TABLE financial_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  type text NOT NULL CHECK (type IN ('payable', 'receivable')),
  color text DEFAULT '#6b7280',
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE financial_categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY allow_all_financial_categories ON financial_categories
  AS PERMISSIVE FOR ALL TO anon, authenticated
  USING (true) WITH CHECK (true);

CREATE TABLE saved_filters (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  filter_type text NOT NULL CHECK (filter_type IN ('payable', 'receivable')),
  filter_config jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE saved_filters ENABLE ROW LEVEL SECURITY;

CREATE POLICY allow_all_saved_filters ON saved_filters
  AS PERMISSIVE FOR ALL TO anon, authenticated
  USING (true) WITH CHECK (true);

INSERT INTO financial_categories (name, type, color) VALUES
  ('PeÃ§as e Materiais', 'payable', '#3b82f6'),
  ('VeÃ­culo e CombustÃ­vel', 'payable', '#f59e0b'),
  ('Ferramentas e Equipamentos', 'payable', '#8b5cf6'),
  ('Seguro', 'payable', '#06b6d4'),
  ('Aluguel', 'payable', '#84cc16'),
  ('SalÃ¡rios', 'payable', '#ec4899'),
  ('Impostos', 'payable', '#ef4444'),
  ('Marketing', 'payable', '#f97316'),
  ('AlimentaÃ§Ã£o de Campo', 'payable', '#a16207'),
  ('PedÃ¡gio e Estacionamento', 'payable', '#78716c'),
  ('Outros', 'payable', '#6b7280');

INSERT INTO financial_categories (name, type, color) VALUES
  ('ServiÃ§os TÃ©cnicos', 'receivable', '#10b981'),
  ('Venda de Produtos', 'receivable', '#3b82f6'),
  ('Consultoria', 'receivable', '#8b5cf6'),
  ('Adiantamento', 'receivable', '#f59e0b'),
  ('Reembolso de Cliente', 'receivable', '#06b6d4'),
  ('Contrato Recorrente', 'receivable', '#84cc16'),
  ('Outros', 'receivable', '#6b7280');

ALTER TABLE receivables
  ADD COLUMN IF NOT EXISTS category text;

-- 1. Audit log table
CREATE TABLE audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  table_name text NOT NULL,
  record_id uuid NOT NULL,
  action text NOT NULL CHECK (action IN (
    'update', 'cancel', 'reopen', 'reversal', 'cascade_update'
  )),
  changed_by text NOT NULL DEFAULT 'sistema',
  changed_at timestamptz DEFAULT now(),
  previous_value jsonb,
  new_value jsonb,
  reason text,
  triggered_by_table text,
  triggered_by_id uuid
);

ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY allow_all_audit_log ON audit_log
  AS PERMISSIVE FOR ALL TO anon, authenticated
  USING (true) WITH CHECK (true);

-- 2. Add cancellation/reopen columns to service_orders
ALTER TABLE service_orders
  ADD COLUMN IF NOT EXISTS cancelled_at timestamptz,
  ADD COLUMN IF NOT EXISTS cancellation_reason text,
  ADD COLUMN IF NOT EXISTS reopened_at timestamptz,
  ADD COLUMN IF NOT EXISTS reopen_reason text;

-- 3. Add cancellation tracking to payments
ALTER TABLE payments
  ADD COLUMN IF NOT EXISTS cancelled_at timestamptz,
  ADD COLUMN IF NOT EXISTS cancellation_reason text,
  ADD COLUMN IF NOT EXISTS status text DEFAULT 'confirmed'
    CHECK (status IN ('confirmed', 'cancelled'));
CREATE TABLE import_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type text NOT NULL CHECK (entity_type IN ('products', 'services', 'clients', 'suppliers')),
  filename text NOT NULL,
  total_rows integer DEFAULT 0,
  imported_rows integer DEFAULT 0,
  skipped_rows integer DEFAULT 0,
  conflict_rows integer DEFAULT 0,
  status text DEFAULT 'pending' CHECK (status IN ('pending', 'mapping', 'reviewing', 'completed', 'cancelled')),
  column_mapping jsonb DEFAULT '{}',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE import_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY allow_all_import_sessions ON import_sessions
  AS PERMISSIVE FOR ALL TO anon, authenticated
  USING (true) WITH CHECK (true);

-- Add fiscal and pricing fields to products
ALTER TABLE products
  ADD COLUMN IF NOT EXISTS ncm text,
  ADD COLUMN IF NOT EXISTS csosn text DEFAULT '400',
  ADD COLUMN IF NOT EXISTS fiscal_origin integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS icms_rate numeric(6,4) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS ipi_rate numeric(6,4) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS pis_rate numeric(6,4) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS cofins_rate numeric(6,4) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS commission_rate numeric(6,4) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS profit_margin numeric(6,4) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS use_global_fiscal boolean DEFAULT true;

-- Add fiscal default columns to app_settings
ALTER TABLE app_settings
  ADD COLUMN IF NOT EXISTS default_csosn text DEFAULT '400',
  ADD COLUMN IF NOT EXISTS default_fiscal_origin integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS default_icms_rate numeric(6,4) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS default_ipi_rate numeric(6,4) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS default_pis_rate numeric(6,4) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS default_cofins_rate numeric(6,4) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS default_commission_rate numeric(6,4) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS default_profit_margin numeric(6,4) DEFAULT 30,
  ADD COLUMN IF NOT EXISTS simples_aliquota numeric(6,4) DEFAULT 6;

-- Add commission fields to service_orders
ALTER TABLE service_orders
  ADD COLUMN IF NOT EXISTS commission_rate numeric(6,4) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS commission_amount numeric(12,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS commissioned_person text;

CREATE TABLE product_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  description text,
  default_profit_margin numeric(6,4) DEFAULT 30,
  default_commission_rate numeric(6,4) DEFAULT 0,
  is_commissionable boolean DEFAULT true,
  default_csosn text DEFAULT '400',
  default_fiscal_origin integer DEFAULT 0,
  default_ncm text,
  default_icms_rate numeric(6,4) DEFAULT 0,
  default_ipi_rate numeric(6,4) DEFAULT 0,
  default_pis_rate numeric(6,4) DEFAULT 0,
  default_cofins_rate numeric(6,4) DEFAULT 0,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE product_categories ENABLE ROW LEVEL SECURITY;
CREATE POLICY allow_all_product_categories ON product_categories
  AS PERMISSIVE FOR ALL TO anon, authenticated
  USING (true) WITH CHECK (true);

CREATE TRIGGER set_updated_at_product_categories
  BEFORE UPDATE ON product_categories
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

ALTER TABLE products
  ADD COLUMN IF NOT EXISTS product_category_id uuid REFERENCES product_categories(id),
  ADD COLUMN IF NOT EXISTS is_commissionable boolean DEFAULT true;

INSERT INTO product_categories (name, default_profit_margin, default_commission_rate, is_commissionable, default_csosn) VALUES
  ('EletrÃ´nicos e NavegaÃ§Ã£o', 35, 5, true, '400'),
  ('Equipamentos ElÃ©tricos', 30, 5, true, '400'),
  ('PeÃ§as e Componentes', 40, 3, true, '400'),
  ('AcessÃ³rios NÃ¡uticos', 45, 5, true, '400'),
  ('Ferramentas', 30, 0, false, '400'),
  ('ConsumÃ­veis', 25, 0, false, '400'),
  ('Cabos e Conectores', 40, 3, true, '400'),
  ('SeguranÃ§a e EPIs', 35, 0, false, '400'),
  ('Outros', 30, 0, false, '400');
ALTER TABLE inventory_movements
  ADD COLUMN IF NOT EXISTS adjusted_by text DEFAULT 'sistema';
ALTER TABLE public.service_orders ADD COLUMN IF NOT EXISTS extra_notes text;
ALTER TABLE service_orders
  ADD COLUMN IF NOT EXISTS commissioned_user_id uuid REFERENCES app_users(id),
  ADD COLUMN IF NOT EXISTS quote_validity_days integer DEFAULT 15,
  ADD COLUMN IF NOT EXISTS quote_validity_date date;
ALTER TABLE app_users DROP CONSTRAINT IF EXISTS app_users_role_check;

ALTER TABLE app_users ADD CONSTRAINT app_users_role_check
  CHECK (role IN ('admin', 'technician', 'financial', 'seller', 'other'));

CREATE TABLE vessel_contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vessel_id uuid NOT NULL REFERENCES vessels(id) ON DELETE CASCADE,
  full_name text NOT NULL,
  role text NOT NULL DEFAULT 'owner',
  phone text,
  email text,
  notes text,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE vessel_contacts ENABLE ROW LEVEL SECURITY;
CREATE POLICY allow_all_vessel_contacts ON vessel_contacts
  AS PERMISSIVE FOR ALL TO anon, authenticated
  USING (true) WITH CHECK (true);

ALTER TABLE service_orders
  ADD COLUMN IF NOT EXISTS requested_by_contact_id uuid
    REFERENCES vessel_contacts(id);
ALTER TABLE app_users DROP CONSTRAINT IF EXISTS app_users_id_fkey;
-- Helper function: check admin without recursion
CREATE OR REPLACE FUNCTION public.is_admin(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.app_users
    WHERE id = _user_id AND role = 'admin' AND active = true
  )
$$;

-- Generic: replace allow_all_* policies on most tables with authenticated-only
DO $$
DECLARE
  t text;
  tbls text[] := ARRAY[
    'bank_transactions','card_installment_fees','clients','exchange_rates',
    'financial_categories','import_sessions','inventory_movements','invoices',
    'marinas','payables','payments','product_categories','product_suppliers',
    'products','receivables','saved_filters','service_order_expenses',
    'service_order_parts','service_order_services','service_order_technicians',
    'service_orders','services','suppliers','time_entries','vessel_contacts','vessels'
  ];
BEGIN
  FOREACH t IN ARRAY tbls LOOP
    EXECUTE format('DROP POLICY IF EXISTS allow_all_%I ON public.%I', t, t);
    EXECUTE format($f$
      CREATE POLICY "authenticated_all_%1$s" ON public.%1$I
      FOR ALL TO authenticated
      USING (auth.uid() IS NOT NULL)
      WITH CHECK (auth.uid() IS NOT NULL)
    $f$, t);
  END LOOP;
END $$;

-- Also handle the historical name variants that don't follow allow_all_<table>
DROP POLICY IF EXISTS allow_all_card_fees ON public.card_installment_fees;
DROP POLICY IF EXISTS allow_all_financial_categories ON public.financial_categories;

-- Sensitive tables: read for any authenticated, write for admins only
-- app_settings
DROP POLICY IF EXISTS allow_all_app_settings ON public.app_settings;
CREATE POLICY "app_settings_select_auth" ON public.app_settings
  FOR SELECT TO authenticated USING (auth.uid() IS NOT NULL);
CREATE POLICY "app_settings_write_admin" ON public.app_settings
  FOR INSERT TO authenticated WITH CHECK (public.is_admin(auth.uid()));
CREATE POLICY "app_settings_update_admin" ON public.app_settings
  FOR UPDATE TO authenticated USING (public.is_admin(auth.uid())) WITH CHECK (public.is_admin(auth.uid()));
CREATE POLICY "app_settings_delete_admin" ON public.app_settings
  FOR DELETE TO authenticated USING (public.is_admin(auth.uid()));

-- audit_log
DROP POLICY IF EXISTS allow_all_audit_log ON public.audit_log;
CREATE POLICY "audit_log_select_auth" ON public.audit_log
  FOR SELECT TO authenticated USING (auth.uid() IS NOT NULL);
CREATE POLICY "audit_log_insert_auth" ON public.audit_log
  FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);
-- no update/delete on audit_log

-- app_users
DROP POLICY IF EXISTS allow_all_app_users ON public.app_users;
CREATE POLICY "app_users_select_auth" ON public.app_users
  FOR SELECT TO authenticated USING (auth.uid() IS NOT NULL);
CREATE POLICY "app_users_insert_admin" ON public.app_users
  FOR INSERT TO authenticated WITH CHECK (public.is_admin(auth.uid()));
CREATE POLICY "app_users_update_admin" ON public.app_users
  FOR UPDATE TO authenticated USING (public.is_admin(auth.uid())) WITH CHECK (public.is_admin(auth.uid()));
CREATE POLICY "app_users_delete_admin" ON public.app_users
  FOR DELETE TO authenticated USING (public.is_admin(auth.uid()));
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
  ('Ã€ vista', 1),
  ('50% de sinal + 50% na entrega', 2),
  ('50% mÃ£o de obra + 100% materiais antecipados', 3),
  ('30 dias apÃ³s conclusÃ£o', 4),
  ('Faturado mensalmente', 5);
DROP POLICY IF EXISTS "allow_all_app_settings" ON app_settings;
DROP POLICY IF EXISTS "Enable read access for all users" ON app_settings;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON app_settings;
DROP POLICY IF EXISTS "Enable update for authenticated users only" ON app_settings;
DROP POLICY IF EXISTS "authenticated_full_access" ON app_settings;
DROP POLICY IF EXISTS "app_settings_delete_admin" ON app_settings;
DROP POLICY IF EXISTS "app_settings_select_auth" ON app_settings;
DROP POLICY IF EXISTS "app_settings_update_admin" ON app_settings;
DROP POLICY IF EXISTS "app_settings_write_admin" ON app_settings;
DROP POLICY IF EXISTS "anon_read_app_settings" ON app_settings;

CREATE POLICY "authenticated_full_access" ON app_settings
  AS PERMISSIVE FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "anon_read_app_settings" ON app_settings
  AS PERMISSIVE FOR SELECT
  TO anon
  USING (true);
ALTER TABLE service_orders 
ADD COLUMN IF NOT EXISTS share_token UUID DEFAULT gen_random_uuid() UNIQUE;

CREATE INDEX IF NOT EXISTS idx_service_orders_share_token ON service_orders(share_token);

CREATE POLICY "Public document viewing via share_token" ON service_orders
  FOR SELECT
  TO anon
  USING (share_token IS NOT NULL);

CREATE POLICY "Public parts viewing via service order" ON service_order_parts
  FOR SELECT TO anon USING (TRUE);

CREATE POLICY "Public services viewing via service order" ON service_order_services
  FOR SELECT TO anon USING (TRUE);

CREATE POLICY "Public company settings viewing" ON app_settings
  FOR SELECT TO anon USING (TRUE);

CREATE POLICY "Public clients viewing via service order" ON clients
  FOR SELECT TO anon USING (TRUE);

CREATE POLICY "Public vessels viewing via service order" ON vessels
  FOR SELECT TO anon USING (TRUE);
UPDATE service_orders SET share_token = gen_random_uuid() WHERE share_token IS NULL;
-- Secure admin check without recursive RLS. Keep existing parameter name to allow CREATE OR REPLACE.
CREATE OR REPLACE FUNCTION public.is_admin(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.app_users
    WHERE id = _user_id
      AND role = 'admin'
      AND active = true
  );
$$;

-- Helper function for provisioning an app profile shape.
-- This is intentionally created in public schema only; no trigger is attached to reserved auth schemas.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.app_users (id, email, full_name, role)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email),
    'technician'
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$$;

-- Replace app_users role CHECK constraint with the full role set expected by the app.
DO $$
DECLARE
  constraint_name text;
BEGIN
  SELECT tc.constraint_name
  INTO constraint_name
  FROM information_schema.table_constraints tc
  JOIN information_schema.constraint_column_usage ccu
    ON ccu.constraint_name = tc.constraint_name
   AND ccu.constraint_schema = tc.constraint_schema
  WHERE tc.table_schema = 'public'
    AND tc.table_name = 'app_users'
    AND tc.constraint_type = 'CHECK'
    AND ccu.column_name = 'role'
  LIMIT 1;

  IF constraint_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.app_users DROP CONSTRAINT %I', constraint_name);
  END IF;
END $$;

ALTER TABLE public.app_users
ADD CONSTRAINT app_users_role_check
CHECK (role IN ('admin', 'technician', 'financial', 'seller', 'other'));

-- Tighten app_users RLS policies.
DROP POLICY IF EXISTS app_users_select_auth ON public.app_users;
DROP POLICY IF EXISTS app_users_insert_admin ON public.app_users;
DROP POLICY IF EXISTS app_users_update_admin ON public.app_users;
DROP POLICY IF EXISTS app_users_delete_admin ON public.app_users;
DROP POLICY IF EXISTS authenticated_full_access ON public.app_users;
DROP POLICY IF EXISTS select_app_users ON public.app_users;
DROP POLICY IF EXISTS insert_app_users ON public.app_users;
DROP POLICY IF EXISTS update_app_users ON public.app_users;
DROP POLICY IF EXISTS delete_app_users ON public.app_users;
DROP POLICY IF EXISTS manage_app_users ON public.app_users;
DROP POLICY IF EXISTS app_users_select_self_or_admin ON public.app_users;
DROP POLICY IF EXISTS app_users_insert_admin_only ON public.app_users;
DROP POLICY IF EXISTS app_users_update_admin_only ON public.app_users;
DROP POLICY IF EXISTS app_users_delete_admin_only ON public.app_users;

CREATE POLICY app_users_select_self_or_admin
ON public.app_users
FOR SELECT
TO authenticated
USING (auth.uid() = id OR public.is_admin(auth.uid()));

CREATE POLICY app_users_insert_admin_only
ON public.app_users
FOR INSERT
TO authenticated
WITH CHECK (public.is_admin(auth.uid()));

CREATE POLICY app_users_update_admin_only
ON public.app_users
FOR UPDATE
TO authenticated
USING (public.is_admin(auth.uid()))
WITH CHECK (public.is_admin(auth.uid()));

CREATE POLICY app_users_delete_admin_only
ON public.app_users
FOR DELETE
TO authenticated
USING (public.is_admin(auth.uid()));

-- ============================================================
-- Assinatura digital pelo link pÃºblico da OS
-- ============================================================

-- 1) Tabela de assinaturas (histÃ³rico completo)
CREATE TABLE public.service_order_signatures (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  service_order_id uuid NOT NULL REFERENCES public.service_orders(id) ON DELETE CASCADE,
  share_token uuid NOT NULL,
  signature_image_url text,                      -- PNG do desenho (storage)
  accepted_name text NOT NULL,                   -- nome digitado pelo cliente
  accepted_terms_snapshot text,                  -- termos vigentes no momento do aceite
  document_hash text NOT NULL,                   -- hash do conteÃºdo da OS no momento
  ip_address text,
  user_agent text,
  signed_at timestamptz NOT NULL DEFAULT now(),
  superseded_at timestamptz,                     -- preenchido quando OS Ã© alterada
  superseded_reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_so_signatures_service_order ON public.service_order_signatures(service_order_id);
CREATE INDEX idx_so_signatures_signed_at ON public.service_order_signatures(signed_at DESC);

-- 2) Colunas na service_orders para refletir status de assinatura
ALTER TABLE public.service_orders
  ADD COLUMN IF NOT EXISTS signed_at timestamptz,
  ADD COLUMN IF NOT EXISTS signed_document_hash text,
  ADD COLUMN IF NOT EXISTS signed_by_name text,
  ADD COLUMN IF NOT EXISTS requires_resignature boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS resignature_requested_at timestamptz;

-- 3) RLS na tabela de assinaturas
ALTER TABLE public.service_order_signatures ENABLE ROW LEVEL SECURITY;

-- Authenticated lÃª tudo (equipe interna)
CREATE POLICY "auth_read_signatures"
ON public.service_order_signatures
FOR SELECT
TO authenticated
USING (auth.uid() IS NOT NULL);

-- Authenticated pode atualizar (para marcar superseded)
CREATE POLICY "auth_update_signatures"
ON public.service_order_signatures
FOR UPDATE
TO authenticated
USING (auth.uid() IS NOT NULL)
WITH CHECK (auth.uid() IS NOT NULL);

-- Anon pode ler assinaturas vinculadas a uma OS com share_token vÃ¡lido
-- (necessÃ¡rio para a pÃ¡gina pÃºblica mostrar "Assinado em")
CREATE POLICY "anon_read_signatures_by_token"
ON public.service_order_signatures
FOR SELECT
TO anon
USING (
  EXISTS (
    SELECT 1 FROM public.service_orders so
    WHERE so.id = service_order_signatures.service_order_id
      AND so.share_token IS NOT NULL
      AND so.share_token = service_order_signatures.share_token
  )
);

-- INSERT por anon serÃ¡ feito EXCLUSIVAMENTE via edge function com service_role,
-- entÃ£o NÃƒO criamos polÃ­tica de INSERT para anon (mais seguro).

-- 4) Storage bucket para imagens de assinatura
INSERT INTO storage.buckets (id, name, public)
VALUES ('signatures', 'signatures', true)
ON CONFLICT (id) DO NOTHING;

-- Policies do bucket: leitura pÃºblica, escrita sÃ³ via service_role
CREATE POLICY "signatures_public_read"
ON storage.objects FOR SELECT
USING (bucket_id = 'signatures');

-- 5) Settings keys para controlar quais blocos aparecem no link pÃºblico
INSERT INTO public.app_settings (key, value, description) VALUES
  ('public_view_show_service_prices', 'true', 'Mostrar preÃ§os de serviÃ§os no link pÃºblico'),
  ('public_view_show_parts_prices', 'true', 'Mostrar preÃ§os de peÃ§as no link pÃºblico'),
  ('public_view_show_travel_cost', 'true', 'Mostrar custo de deslocamento no link pÃºblico'),
  ('public_view_show_discount', 'true', 'Mostrar desconto no link pÃºblico'),
  ('public_view_show_tax', 'true', 'Mostrar impostos no link pÃºblico'),
  ('public_view_show_terms', 'true', 'Mostrar termos e condiÃ§Ãµes no link pÃºblico'),
  ('public_view_show_bank_details', 'true', 'Mostrar dados bancÃ¡rios no link pÃºblico'),
  ('public_view_show_payment_instructions', 'true', 'Mostrar instruÃ§Ãµes de pagamento no link pÃºblico'),
  ('public_view_show_extra_notes', 'true', 'Mostrar notas extras no link pÃºblico'),
  ('public_view_show_validity', 'true', 'Mostrar validade do orÃ§amento no link pÃºblico'),
  ('public_view_allow_signature', 'true', 'Permitir assinatura digital pelo link pÃºblico'),
  ('signature_status_after', 'approved', 'Status para o qual a OS muda apÃ³s assinatura do cliente')
ON CONFLICT (key) DO NOTHING;

-- Trigger: marca requires_resignature quando OS assinada Ã© editada
CREATE OR REPLACE FUNCTION public.detect_so_change_after_signature()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.signed_at IS NOT NULL
     AND NEW.requires_resignature = false
     AND (
       NEW.problem_description IS DISTINCT FROM OLD.problem_description OR
       NEW.diagnosis IS DISTINCT FROM OLD.diagnosis OR
       NEW.solution_applied IS DISTINCT FROM OLD.solution_applied OR
       NEW.customer_visible_report IS DISTINCT FROM OLD.customer_visible_report OR
       NEW.payment_conditions IS DISTINCT FROM OLD.payment_conditions OR
       NEW.extra_notes IS DISTINCT FROM OLD.extra_notes OR
       NEW.grand_total IS DISTINCT FROM OLD.grand_total OR
       NEW.labor_cost_total IS DISTINCT FROM OLD.labor_cost_total OR
       NEW.parts_cost_total IS DISTINCT FROM OLD.parts_cost_total OR
       NEW.travel_cost_total IS DISTINCT FROM OLD.travel_cost_total OR
       NEW.discount_amount IS DISTINCT FROM OLD.discount_amount OR
       NEW.tax_amount IS DISTINCT FROM OLD.tax_amount OR
       NEW.operational_cost_total IS DISTINCT FROM OLD.operational_cost_total OR
       NEW.quote_validity_date IS DISTINCT FROM OLD.quote_validity_date
     )
  THEN
    NEW.requires_resignature := true;
    NEW.resignature_requested_at := now();

    -- supersede assinaturas anteriores
    UPDATE public.service_order_signatures
    SET superseded_at = now(),
        superseded_reason = 'OS alterada apÃ³s assinatura'
    WHERE service_order_id = NEW.id
      AND superseded_at IS NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_detect_so_change_after_signature ON public.service_orders;
CREATE TRIGGER trg_detect_so_change_after_signature
BEFORE UPDATE ON public.service_orders
FOR EACH ROW
EXECUTE FUNCTION public.detect_so_change_after_signature();
ALTER TABLE public.audit_log DROP CONSTRAINT IF EXISTS audit_log_action_check;
ALTER TABLE public.audit_log ADD CONSTRAINT audit_log_action_check
  CHECK (action = ANY (ARRAY[
    'update','cancel','reopen','reversal','cascade_update',
    'client_signature','whatsapp_send','whatsapp_send_api','whatsapp_received',
    'lead_created','lead_matched','lead_converted'
  ]));
-- whatsapp_leads: fila de novos contatos
CREATE TABLE public.whatsapp_leads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_normalized text NOT NULL,
  display_name text,
  first_message text,
  last_message_at timestamptz NOT NULL DEFAULT now(),
  message_count integer NOT NULL DEFAULT 1,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','linked','converted','discarded')),
  linked_client_id uuid REFERENCES public.clients(id) ON DELETE SET NULL,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (phone_normalized)
);

CREATE INDEX idx_whatsapp_leads_status ON public.whatsapp_leads(status);
CREATE INDEX idx_whatsapp_leads_phone ON public.whatsapp_leads(phone_normalized);

ALTER TABLE public.whatsapp_leads ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view leads"
  ON public.whatsapp_leads FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can insert leads"
  ON public.whatsapp_leads FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "Authenticated users can update leads"
  ON public.whatsapp_leads FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Authenticated users can delete leads"
  ON public.whatsapp_leads FOR DELETE TO authenticated USING (true);

CREATE TRIGGER trg_whatsapp_leads_updated_at
  BEFORE UPDATE ON public.whatsapp_leads
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- whatsapp_messages: histÃ³rico de mensagens
CREATE TABLE public.whatsapp_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  direction text NOT NULL CHECK (direction IN ('inbound','outbound')),
  phone_normalized text NOT NULL,
  message_type text NOT NULL DEFAULT 'text'
    CHECK (message_type IN ('text','image','audio','video','document','location','contact','sticker','other')),
  body text,
  media_url text,
  client_id uuid REFERENCES public.clients(id) ON DELETE SET NULL,
  lead_id uuid REFERENCES public.whatsapp_leads(id) ON DELETE SET NULL,
  service_order_id uuid REFERENCES public.service_orders(id) ON DELETE SET NULL,
  zapi_message_id text,
  delivery_status text DEFAULT 'received'
    CHECK (delivery_status IN ('received','sent','delivered','read','failed')),
  raw_payload jsonb,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_whatsapp_messages_phone ON public.whatsapp_messages(phone_normalized);
CREATE INDEX idx_whatsapp_messages_client ON public.whatsapp_messages(client_id);
CREATE INDEX idx_whatsapp_messages_lead ON public.whatsapp_messages(lead_id);
CREATE INDEX idx_whatsapp_messages_occurred ON public.whatsapp_messages(occurred_at DESC);

ALTER TABLE public.whatsapp_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view messages"
  ON public.whatsapp_messages FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can insert messages"
  ON public.whatsapp_messages FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "Authenticated users can update messages"
  ON public.whatsapp_messages FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Authenticated users can delete messages"
  ON public.whatsapp_messages FOR DELETE TO authenticated USING (true);
-- Bucket pÃºblico para PDFs enviados ao cliente
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('documents', 'documents', true, 26214400, ARRAY['application/pdf'])
ON CONFLICT (id) DO UPDATE
SET public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Policies (idempotentes)
DROP POLICY IF EXISTS "documents_public_read" ON storage.objects;
CREATE POLICY "documents_public_read"
ON storage.objects FOR SELECT
TO anon, authenticated
USING (bucket_id = 'documents');

DROP POLICY IF EXISTS "documents_authenticated_insert" ON storage.objects;
CREATE POLICY "documents_authenticated_insert"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'documents');

DROP POLICY IF EXISTS "documents_authenticated_update" ON storage.objects;
CREATE POLICY "documents_authenticated_update"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'documents')
WITH CHECK (bucket_id = 'documents');

DROP POLICY IF EXISTS "documents_authenticated_delete" ON storage.objects;
CREATE POLICY "documents_authenticated_delete"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'documents');
-- 1) Templates de mensagem WhatsApp
CREATE TABLE IF NOT EXISTS public.whatsapp_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  category text NOT NULL DEFAULT 'general',
  body text NOT NULL,
  active boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.whatsapp_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY whatsapp_templates_all_auth
  ON public.whatsapp_templates FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);

CREATE TRIGGER trg_whatsapp_templates_updated
  BEFORE UPDATE ON public.whatsapp_templates
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

INSERT INTO public.whatsapp_templates (name, category, body, sort_order) VALUES
  ('ConfirmaÃ§Ã£o de OS', 'service_order', 'OlÃ¡ {cliente}, sua Ordem de ServiÃ§o {os} foi aberta. Acompanhe pelo link: {link}', 10),
  ('OrÃ§amento enviado', 'quote', 'OlÃ¡ {cliente}, segue o orÃ§amento {os} no valor de {valor}. Acesso: {link}', 20),
  ('CobranÃ§a - lembrete', 'billing', 'OlÃ¡ {cliente}, lembramos da cobranÃ§a "{descricao}" no valor de {valor} com vencimento em {vencimento}.', 30),
  ('CobranÃ§a - vencida', 'billing', 'OlÃ¡ {cliente}, a cobranÃ§a "{descricao}" no valor de {valor} venceu em {vencimento}. Por favor, regularize.', 40),
  ('OS concluÃ­da', 'service_order', 'OlÃ¡ {cliente}, sua OS {os} foi concluÃ­da. Total: {valor}. Detalhes: {link}', 50);

-- 2) Realtime
ALTER TABLE public.whatsapp_messages REPLICA IDENTITY FULL;
ALTER TABLE public.whatsapp_leads REPLICA IDENTITY FULL;

DO $$ BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.whatsapp_messages;
  EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.whatsapp_leads;
  EXCEPTION WHEN duplicate_object THEN NULL; END;
END $$;

-- 3) Estado de leitura por usuÃ¡rio
CREATE TABLE IF NOT EXISTS public.whatsapp_read_state (
  user_id uuid PRIMARY KEY,
  last_read_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.whatsapp_read_state ENABLE ROW LEVEL SECURITY;

CREATE POLICY whatsapp_read_state_self
  ON public.whatsapp_read_state FOR ALL TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE TRIGGER trg_whatsapp_read_state_updated
  BEFORE UPDATE ON public.whatsapp_read_state
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TABLE public.client_whatsapp_settings (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  client_id uuid NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
  context text NOT NULL CHECK (context IN ('service_order','quote','billing')),
  message_body text,
  link_title text,
  link_description text,
  pdf_filename_pattern text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (client_id, context)
);

ALTER TABLE public.client_whatsapp_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "client_whatsapp_settings_all_auth"
  ON public.client_whatsapp_settings
  FOR ALL
  TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

CREATE INDEX idx_client_whatsapp_settings_client ON public.client_whatsapp_settings(client_id);

CREATE TRIGGER update_client_whatsapp_settings_updated_at
  BEFORE UPDATE ON public.client_whatsapp_settings
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();
-- Tabela de agendamentos de envio Z-API
CREATE TABLE public.whatsapp_scheduled_sends (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Alvo do envio
  target_kind text NOT NULL CHECK (target_kind IN ('service_order', 'receivable')),
  service_order_id uuid REFERENCES public.service_orders(id) ON DELETE CASCADE,
  receivable_id uuid REFERENCES public.receivables(id) ON DELETE CASCADE,
  client_id uuid REFERENCES public.clients(id) ON DELETE SET NULL,
  -- ConteÃºdo
  phone text NOT NULL,
  message text NOT NULL,
  send_mode text NOT NULL DEFAULT 'link' CHECK (send_mode IN ('link', 'document')),
  context text,
  document_type text,
  link_title text,
  link_description text,
  pdf_filename text,
  caption text,
  include_link_in_caption boolean NOT NULL DEFAULT true,
  -- Agendamento
  scheduled_at timestamptz NOT NULL,
  recurrence_type text NOT NULL DEFAULT 'once' CHECK (recurrence_type IN ('once', 'daily', 'weekly', 'monthly')),
  recurrence_days_of_week int[] DEFAULT NULL, -- 0=domingo .. 6=sÃ¡bado, para weekly
  recurrence_day_of_month int DEFAULT NULL,    -- 1..31 para monthly
  recurrence_end_date timestamptz DEFAULT NULL,
  next_run_at timestamptz NOT NULL,
  last_run_at timestamptz DEFAULT NULL,
  -- Retry
  auto_retry boolean NOT NULL DEFAULT true,
  max_attempts int NOT NULL DEFAULT 3,
  attempt_count int NOT NULL DEFAULT 0,
  -- Estado
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'sent', 'failed', 'cancelled')),
  last_error text,
  last_response jsonb,
  -- Auditoria
  created_by uuid REFERENCES public.app_users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chk_target CHECK (
    (target_kind = 'service_order' AND service_order_id IS NOT NULL) OR
    (target_kind = 'receivable' AND receivable_id IS NOT NULL)
  )
);

CREATE INDEX idx_wss_next_run ON public.whatsapp_scheduled_sends(next_run_at) WHERE status = 'pending';
CREATE INDEX idx_wss_status ON public.whatsapp_scheduled_sends(status);
CREATE INDEX idx_wss_so ON public.whatsapp_scheduled_sends(service_order_id);
CREATE INDEX idx_wss_rec ON public.whatsapp_scheduled_sends(receivable_id);

ALTER TABLE public.whatsapp_scheduled_sends ENABLE ROW LEVEL SECURITY;

CREATE POLICY whatsapp_scheduled_sends_all_auth ON public.whatsapp_scheduled_sends
  FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

CREATE TRIGGER trg_wss_updated_at
  BEFORE UPDATE ON public.whatsapp_scheduled_sends
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- FunÃ§Ã£o para calcular prÃ³xima execuÃ§Ã£o de agendamentos recorrentes
CREATE OR REPLACE FUNCTION public.compute_next_run(
  _from timestamptz,
  _recurrence_type text,
  _days_of_week int[],
  _day_of_month int
) RETURNS timestamptz
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  base timestamptz := _from + interval '1 minute';
  candidate timestamptz;
  i int;
  dow int;
BEGIN
  IF _recurrence_type = 'once' THEN
    RETURN NULL;
  ELSIF _recurrence_type = 'daily' THEN
    RETURN base;
  ELSIF _recurrence_type = 'weekly' THEN
    IF _days_of_week IS NULL OR array_length(_days_of_week, 1) = 0 THEN
      RETURN base + interval '7 days';
    END IF;
    FOR i IN 0..7 LOOP
      candidate := base + (i || ' days')::interval;
      dow := EXTRACT(DOW FROM candidate)::int;
      IF dow = ANY(_days_of_week) THEN
        RETURN candidate;
      END IF;
    END LOOP;
    RETURN base + interval '7 days';
  ELSIF _recurrence_type = 'monthly' THEN
    candidate := base + interval '1 month';
    IF _day_of_month IS NOT NULL THEN
      candidate := date_trunc('month', candidate) + ((_day_of_month - 1) || ' days')::interval
                   + (EXTRACT(HOUR FROM _from) || ' hours')::interval
                   + (EXTRACT(MINUTE FROM _from) || ' minutes')::interval;
    END IF;
    RETURN candidate;
  END IF;
  RETURN NULL;
END;
$$;
-- 1. Collections table
CREATE TABLE IF NOT EXISTS public.collections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  service_order_id UUID REFERENCES public.service_orders(id) ON DELETE SET NULL,
  receivable_id UUID REFERENCES public.receivables(id) ON DELETE SET NULL,
  description TEXT,
  standalone_amount NUMERIC(12,2),
  client_id UUID NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
  amount NUMERIC(12,2) NOT NULL,
  due_date DATE NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','sent','viewed','paid','overdue','disputed','cancelled')),
  contact_name TEXT,
  contact_phone TEXT,
  contact_whatsapp TEXT,
  send_method TEXT DEFAULT 'text_link'
    CHECK (send_method IN ('pdf','text','text_link')),
  message_template TEXT,
  paid_at TIMESTAMPTZ,
  paid_amount NUMERIC(12,2),
  paid_method TEXT,
  payment_confirmed_by TEXT DEFAULT 'manual'
    CHECK (payment_confirmed_by IN ('manual','whatsapp','auto')),
  auto_rule_enabled BOOLEAN DEFAULT false,
  rule_days_before INTEGER DEFAULT 3,
  rule_days_after INTEGER DEFAULT 5,
  last_auto_sent_at TIMESTAMPTZ,
  created_by UUID REFERENCES public.app_users(id),
  notes TEXT
);

ALTER TABLE public.collections ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated_full_access" ON public.collections
  AS PERMISSIVE FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

CREATE INDEX IF NOT EXISTS idx_collections_client ON public.collections(client_id);
CREATE INDEX IF NOT EXISTS idx_collections_status ON public.collections(status);
CREATE INDEX IF NOT EXISTS idx_collections_due_date ON public.collections(due_date);
CREATE INDEX IF NOT EXISTS idx_collections_so ON public.collections(service_order_id);

CREATE TRIGGER collections_updated_at
  BEFORE UPDATE ON public.collections
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- 2. Collection contact history
CREATE TABLE IF NOT EXISTS public.collection_contacts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  collection_id UUID NOT NULL REFERENCES public.collections(id) ON DELETE CASCADE,
  contact_type TEXT NOT NULL
    CHECK (contact_type IN (
      'whatsapp_sent','whatsapp_delivered','whatsapp_read',
      'call_made','call_answered','call_no_answer',
      'email_sent','manual_note','payment_promised','paid'
    )),
  notes TEXT,
  promised_date DATE,
  created_by UUID REFERENCES public.app_users(id)
);

ALTER TABLE public.collection_contacts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated_full_access" ON public.collection_contacts
  AS PERMISSIVE FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

CREATE INDEX IF NOT EXISTS idx_collection_contacts_coll ON public.collection_contacts(collection_id, created_at DESC);

-- 3. Collection message templates
CREATE TABLE IF NOT EXISTS public.collection_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  name TEXT NOT NULL,
  body TEXT NOT NULL,
  is_default BOOLEAN DEFAULT false,
  send_method TEXT DEFAULT 'text_link'
    CHECK (send_method IN ('pdf','text','text_link'))
);

ALTER TABLE public.collection_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated_full_access" ON public.collection_templates
  AS PERMISSIVE FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

INSERT INTO public.collection_templates (name, body, is_default, send_method) VALUES
('CobranÃ§a PadrÃ£o',
 E'OlÃ¡, {{nome}}! ðŸ‘‹\n\nPassamos para informar que a fatura {{numero_os}} no valor de *R$ {{valor}}* vence em *{{vencimento}}*.\n\nðŸ’° Para pagamento via PIX:\nChave: {{pix}}\n\nQualquer dÃºvida, estamos Ã  disposiÃ§Ã£o!\n\n*{{empresa}}* ðŸš¢',
 true, 'text_link'),
('Lembrete de Vencimento',
 E'OlÃ¡, {{nome}}! â°\n\nLembramos que sua fatura {{numero_os}} de *R$ {{valor}}* vence *hoje*.\n\nðŸ’° PIX: {{pix}}\n\nEvite juros e multas realizando o pagamento hoje. Obrigado!',
 false, 'text'),
('CobranÃ§a em Atraso',
 E'OlÃ¡, {{nome}}. ðŸ“‹\n\nIdentificamos que a fatura {{numero_os}} de *R$ {{valor}}* encontra-se em atraso desde {{vencimento}}.\n\nSolicito que entre em contato para regularizar a situaÃ§Ã£o.\n\nðŸ’° PIX: {{pix}}\n\nAtenciosamente,\n*{{empresa}}*',
 false, 'text_link');
ALTER TABLE public.payment_condition_presets
  ADD COLUMN IF NOT EXISTS installments JSONB DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS auto_generate_collections BOOLEAN DEFAULT true;

UPDATE public.payment_condition_presets
SET installments = '[{"label":"Ã€ vista","percent":100,"days_after_approval":0}]'::jsonb
WHERE (label ILIKE '%Ã  vista%' OR label ILIKE '%avista%')
  AND (installments IS NULL OR installments = '[]'::jsonb);

UPDATE public.payment_condition_presets
SET installments = '[{"label":"Entrada 50%","percent":50,"days_after_approval":0},{"label":"Saldo 50%","percent":50,"days_after_approval":30}]'::jsonb
WHERE (label ILIKE '%50%50%' OR label ILIKE '%50/50%')
  AND (installments IS NULL OR installments = '[]'::jsonb);

ALTER TABLE public.service_orders
  ADD COLUMN IF NOT EXISTS payment_condition_preset_id UUID
  REFERENCES public.payment_condition_presets(id) ON DELETE SET NULL;
ALTER TABLE public.service_orders
  ADD COLUMN IF NOT EXISTS payment_method TEXT,
  ADD COLUMN IF NOT EXISTS card_installments INTEGER DEFAULT 1;
ALTER TABLE public.service_orders DROP CONSTRAINT IF EXISTS service_orders_status_check;
ALTER TABLE public.service_orders ADD CONSTRAINT service_orders_status_check
  CHECK (status = ANY (ARRAY['draft','scheduled','open','in_progress','awaiting_parts','awaiting_client','approved','completed','invoiced','cancelled']));
ALTER TABLE public.service_order_signatures ADD COLUMN IF NOT EXISTS signed_pdf_url text; COMMENT ON COLUMN public.service_order_signatures.signed_pdf_url IS 'URL publica do PDF da OS no exato estado em que foi assinado pelo cliente. Usado como prova juridica imutavel.';
-- Blocklist de nÃºmeros (listas de transmissÃ£o, fornecedores spam)
CREATE TABLE IF NOT EXISTS public.whatsapp_blocked_numbers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_normalized text NOT NULL UNIQUE,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid
);
ALTER TABLE public.whatsapp_blocked_numbers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_all_blocked" ON public.whatsapp_blocked_numbers
  FOR ALL TO authenticated USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);

-- Respostas rÃ¡pidas / templates de saudaÃ§Ã£o
CREATE TABLE IF NOT EXISTS public.whatsapp_quick_replies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shortcut text NOT NULL,
  body text NOT NULL,
  active boolean NOT NULL DEFAULT true,
  sort_order int DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.whatsapp_quick_replies ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_all_quick" ON public.whatsapp_quick_replies
  FOR ALL TO authenticated USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);

-- AtribuiÃ§Ã£o e flags em leads
ALTER TABLE public.whatsapp_leads
  ADD COLUMN IF NOT EXISTS assigned_to uuid,
  ADD COLUMN IF NOT EXISTS is_broadcast boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS unread_count int DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_inbound_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_outbound_at timestamptz;

-- Flag broadcast em mensagens
ALTER TABLE public.whatsapp_messages
  ADD COLUMN IF NOT EXISTS is_broadcast boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS sent_by uuid;

-- AtribuiÃ§Ã£o tambÃ©m para clients (conversas com clientes existentes)
CREATE TABLE IF NOT EXISTS public.whatsapp_conversation_assignments (
  phone_normalized text PRIMARY KEY,
  assigned_to uuid,
  notified_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.whatsapp_conversation_assignments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_all_assign" ON public.whatsapp_conversation_assignments
  FOR ALL TO authenticated USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);

CREATE INDEX IF NOT EXISTS idx_wa_msgs_phone ON public.whatsapp_messages(phone_normalized, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_wa_leads_status ON public.whatsapp_leads(status, last_message_at DESC);
-- 1) DeduplicaÃ§Ã£o: garante que zapi_message_id seja Ãºnico quando informado
-- Antes, limpa duplicatas mantendo a primeira ocorrÃªncia
DELETE FROM public.whatsapp_messages a
USING public.whatsapp_messages b
WHERE a.zapi_message_id IS NOT NULL
  AND a.zapi_message_id = b.zapi_message_id
  AND a.created_at > b.created_at;

CREATE UNIQUE INDEX IF NOT EXISTS whatsapp_messages_zapi_message_id_unique
  ON public.whatsapp_messages (zapi_message_id)
  WHERE zapi_message_id IS NOT NULL;

-- 2) Ãndices de rastreamento
CREATE INDEX IF NOT EXISTS whatsapp_messages_phone_created_idx
  ON public.whatsapp_messages (phone_normalized, created_at DESC);

CREATE INDEX IF NOT EXISTS whatsapp_messages_direction_created_idx
  ON public.whatsapp_messages (direction, created_at DESC);

CREATE INDEX IF NOT EXISTS whatsapp_messages_delivery_status_idx
  ON public.whatsapp_messages (delivery_status)
  WHERE delivery_status IN ('sent', 'queued', 'failed');

CREATE INDEX IF NOT EXISTS whatsapp_messages_lead_id_idx
  ON public.whatsapp_messages (lead_id) WHERE lead_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS whatsapp_messages_client_id_idx
  ON public.whatsapp_messages (client_id) WHERE client_id IS NOT NULL;

-- 3) Leads: Ã­ndices para fila de pendentes
CREATE INDEX IF NOT EXISTS whatsapp_leads_status_last_inbound_idx
  ON public.whatsapp_leads (status, last_inbound_at DESC NULLS LAST);

CREATE INDEX IF NOT EXISTS whatsapp_leads_unread_idx
  ON public.whatsapp_leads (unread_count DESC) WHERE unread_count > 0;
CREATE TABLE public.agenda_tasks (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT,
  technician_user_id UUID NOT NULL REFERENCES public.app_users(id) ON DELETE CASCADE,
  scheduled_start_at TIMESTAMPTZ NOT NULL,
  scheduled_end_at TIMESTAMPTZ,
  priority TEXT NOT NULL DEFAULT 'normal',
  status TEXT NOT NULL DEFAULT 'pending',
  location TEXT,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  notes TEXT,
  created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.agenda_tasks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated_all_agenda_tasks"
  ON public.agenda_tasks FOR ALL
  TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

CREATE INDEX agenda_tasks_tech_start_idx
  ON public.agenda_tasks (technician_user_id, scheduled_start_at);

CREATE INDEX agenda_tasks_start_idx
  ON public.agenda_tasks (scheduled_start_at);

CREATE TRIGGER update_agenda_tasks_updated_at
  BEFORE UPDATE ON public.agenda_tasks
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();
ALTER TABLE public.app_users
  ADD COLUMN IF NOT EXISTS postal_code text,
  ADD COLUMN IF NOT EXISTS address_line_1 text,
  ADD COLUMN IF NOT EXISTS address_number text,
  ADD COLUMN IF NOT EXISTS address_complement text,
  ADD COLUMN IF NOT EXISTS neighborhood text,
  ADD COLUMN IF NOT EXISTS city text,
  ADD COLUMN IF NOT EXISTS state text,
  ADD COLUMN IF NOT EXISTS country text DEFAULT 'Brazil',
  ADD COLUMN IF NOT EXISTS notes text;
DELETE FROM public.whatsapp_messages 
WHERE direction='inbound' 
  AND message_type='other' 
  AND raw_payload->>'type' IN ('MessageStatusCallback','DeliveryCallback','PresenceChatCallback','NotificationCallback','ConnectedCallback','DisconnectedCallback');
CREATE TABLE IF NOT EXISTS public.whatsapp_send_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_normalized text NOT NULL,
  message text NOT NULL,
  source text NOT NULL DEFAULT 'manual',
  source_ref_id uuid,
  priority integer NOT NULL DEFAULT 5,
  status text NOT NULL DEFAULT 'pending',
  attempts integer NOT NULL DEFAULT 0,
  max_attempts integer NOT NULL DEFAULT 3,
  scheduled_for timestamptz NOT NULL DEFAULT now(),
  processing_started_at timestamptz,
  sent_at timestamptz,
  failed_reason text,
  zapi_message_id text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_wa_queue_pending ON public.whatsapp_send_queue (status, scheduled_for, priority) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_wa_queue_phone ON public.whatsapp_send_queue (phone_normalized, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_wa_queue_source ON public.whatsapp_send_queue (source, created_at DESC);

ALTER TABLE public.whatsapp_send_queue ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated_all_wa_queue"
ON public.whatsapp_send_queue FOR ALL
TO authenticated
USING (auth.uid() IS NOT NULL)
WITH CHECK (auth.uid() IS NOT NULL);

CREATE TRIGGER trg_wa_queue_updated_at
BEFORE UPDATE ON public.whatsapp_send_queue
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

INSERT INTO public.app_settings (key, value, description) VALUES
  ('whatsapp_queue_enabled', 'true', 'Liga/desliga o worker da fila de envio WhatsApp.'),
  ('whatsapp_queue_max_per_run', '5', 'Quantas mensagens o worker envia por execuÃ§Ã£o (cada cron tick).'),
  ('whatsapp_queue_delay_ms', '1500', 'Delay entre envios consecutivos do worker (ms).'),
  ('whatsapp_queue_max_per_hour', '60', 'Limite global de envios por hora (rate limit).')
ON CONFLICT (key) DO NOTHING;
-- Helper functions
CREATE OR REPLACE FUNCTION public.wa_normalize_phone(raw text)
RETURNS text
LANGUAGE plpgsql IMMUTABLE
SET search_path = public
AS $$
DECLARE s text; d text; ddd text; rest text;
BEGIN
  IF raw IS NULL OR raw = '' THEN RETURN ''; END IF;
  s := split_part(raw, '@', 1);
  d := regexp_replace(s, '\D', '', 'g');
  IF d = '' THEN RETURN ''; END IF;
  IF length(d) > 14 THEN RETURN ''; END IF;
  IF left(d, 2) = '00' THEN d := substr(d, 3); END IF;
  IF length(d) = 12 AND left(d, 2) = '55' THEN
    ddd := substr(d, 3, 2);
    rest := substr(d, 5);
    IF length(rest) = 8 AND left(rest, 1) ~ '[6-9]' THEN
      d := '55' || ddd || '9' || rest;
    END IF;
  END IF;
  IF length(d) BETWEEN 12 AND 14 THEN RETURN d; END IF;
  IF length(d) IN (10, 11) THEN RETURN '55' || d; END IF;
  RETURN d;
END;
$$;

-- Returns body as text, message_type as text via composite (scalar function for easy UPDATE)
CREATE OR REPLACE FUNCTION public.wa_extract_body_text(p jsonb)
RETURNS text
LANGUAGE plpgsql IMMUTABLE
SET search_path = public
AS $$
BEGIN
  IF p IS NULL THEN RETURN '[mensagem nÃ£o reconhecida]'; END IF;
  IF jsonb_typeof(p->'text') = 'string' THEN RETURN p->>'text'; END IF;
  IF p->'text'->>'message' IS NOT NULL THEN RETURN p->'text'->>'message'; END IF;
  IF jsonb_typeof(p->'message') = 'string' THEN RETURN p->>'message'; END IF;
  IF p->'message'->>'conversation' IS NOT NULL THEN RETURN p->'message'->>'conversation'; END IF;
  IF p->'message'->'extendedTextMessage'->>'text' IS NOT NULL THEN RETURN p->'message'->'extendedTextMessage'->>'text'; END IF;
  IF p->>'body' IS NOT NULL THEN RETURN p->>'body'; END IF;
  IF p->>'caption' IS NOT NULL THEN RETURN p->>'caption'; END IF;
  IF p ? 'image' THEN RETURN COALESCE(p->'image'->>'caption', '[imagem]'); END IF;
  IF p ? 'audio' THEN RETURN '[Ã¡udio]'; END IF;
  IF p ? 'video' THEN RETURN COALESCE(p->'video'->>'caption', '[vÃ­deo]'); END IF;
  IF p ? 'document' THEN RETURN COALESCE(p->'document'->>'caption', '[documento] ' || COALESCE(p->'document'->>'fileName', '')); END IF;
  IF p ? 'sticker' THEN RETURN '[sticker]'; END IF;
  IF p ? 'reaction' THEN RETURN '[reaÃ§Ã£o] ' || COALESCE(p->'reaction'->>'value', ''); END IF;
  IF p ? 'poll' OR p ? 'pollCreation' THEN RETURN '[enquete]'; END IF;
  IF p ? 'listResponseMessage' OR p->'message' ? 'listResponseMessage' THEN RETURN COALESCE(p->'listResponseMessage'->'singleSelectReply'->>'selectedRowId', '[resposta de lista]'); END IF;
  IF p ? 'buttonsResponseMessage' OR p->'message' ? 'buttonsResponseMessage' THEN RETURN COALESCE(p->'buttonsResponseMessage'->>'selectedDisplayText', '[resposta de botÃ£o]'); END IF;
  IF p ? 'location' THEN RETURN '[localizaÃ§Ã£o] ' || COALESCE(p->'location'->>'latitude', '') || ',' || COALESCE(p->'location'->>'longitude', ''); END IF;
  IF p ? 'contact' OR p ? 'contacts' OR p ? 'contactsArrayMessage' THEN RETURN '[contato] ' || COALESCE(p->'contact'->>'displayName', ''); END IF;
  RETURN '[mensagem nÃ£o reconhecida]';
END;
$$;

CREATE OR REPLACE FUNCTION public.wa_extract_message_type(p jsonb)
RETURNS text
LANGUAGE plpgsql IMMUTABLE
SET search_path = public
AS $$
BEGIN
  IF p IS NULL THEN RETURN 'other'; END IF;
  IF jsonb_typeof(p->'text') = 'string' OR p->'text'->>'message' IS NOT NULL
     OR jsonb_typeof(p->'message') = 'string' OR p->'message'->>'conversation' IS NOT NULL
     OR p->'message'->'extendedTextMessage'->>'text' IS NOT NULL
     OR p->>'body' IS NOT NULL OR p->>'caption' IS NOT NULL THEN RETURN 'text'; END IF;
  IF p ? 'image' THEN RETURN 'image'; END IF;
  IF p ? 'audio' THEN RETURN 'audio'; END IF;
  IF p ? 'video' THEN RETURN 'video'; END IF;
  IF p ? 'document' THEN RETURN 'document'; END IF;
  IF p ? 'sticker' THEN RETURN 'sticker'; END IF;
  IF p ? 'reaction' THEN RETURN 'reaction'; END IF;
  IF p ? 'poll' OR p ? 'pollCreation' THEN RETURN 'poll'; END IF;
  IF p ? 'listResponseMessage' OR p->'message' ? 'listResponseMessage' THEN RETURN 'list_response'; END IF;
  IF p ? 'buttonsResponseMessage' OR p->'message' ? 'buttonsResponseMessage' THEN RETURN 'button_response'; END IF;
  IF p ? 'location' THEN RETURN 'location'; END IF;
  IF p ? 'contact' OR p ? 'contacts' OR p ? 'contactsArrayMessage' THEN RETURN 'contact'; END IF;
  RETURN 'other';
END;
$$;

-- Build remap and merge duplicate leads
CREATE TEMP TABLE _lead_remap ON COMMIT DROP AS
SELECT id AS lead_id, phone_normalized AS old_phone,
       public.wa_normalize_phone(phone_normalized) AS new_phone,
       message_count, created_at
FROM public.whatsapp_leads;

DELETE FROM public.whatsapp_messages WHERE lead_id IN (
  SELECT lead_id FROM _lead_remap WHERE new_phone = '' OR new_phone IS NULL
);
DELETE FROM public.whatsapp_leads WHERE id IN (
  SELECT lead_id FROM _lead_remap WHERE new_phone = '' OR new_phone IS NULL
);
DELETE FROM _lead_remap WHERE new_phone = '' OR new_phone IS NULL;

CREATE TEMP TABLE _keepers ON COMMIT DROP AS
SELECT DISTINCT ON (new_phone) new_phone, lead_id AS keeper_id
FROM _lead_remap
ORDER BY new_phone, message_count DESC NULLS LAST, created_at ASC;

UPDATE public.whatsapp_messages m
SET lead_id = k.keeper_id
FROM _lead_remap r
JOIN _keepers k ON k.new_phone = r.new_phone
WHERE m.lead_id = r.lead_id AND r.lead_id <> k.keeper_id;

DELETE FROM public.whatsapp_leads
WHERE id IN (
  SELECT r.lead_id FROM _lead_remap r
  JOIN _keepers k ON k.new_phone = r.new_phone
  WHERE r.lead_id <> k.keeper_id
);

UPDATE public.whatsapp_leads l
SET phone_normalized = k.new_phone
FROM _keepers k
WHERE l.id = k.keeper_id AND l.phone_normalized <> k.new_phone;

-- Messages: drop invalid, renormalize the rest
DELETE FROM public.whatsapp_messages
WHERE public.wa_normalize_phone(phone_normalized) = '';

UPDATE public.whatsapp_messages
SET phone_normalized = public.wa_normalize_phone(phone_normalized)
WHERE phone_normalized <> public.wa_normalize_phone(phone_normalized);

-- Recompute counts
UPDATE public.whatsapp_leads l
SET message_count = COALESCE(sub.cnt, 0)
FROM (
  SELECT lead_id, COUNT(*) AS cnt FROM public.whatsapp_messages
  WHERE lead_id IS NOT NULL GROUP BY lead_id
) sub
WHERE l.id = sub.lead_id;

-- Re-extract bodies for "other"/placeholder messages (scalar functions, no LATERAL needed)
UPDATE public.whatsapp_messages
SET body = public.wa_extract_body_text(raw_payload),
    message_type = public.wa_extract_message_type(raw_payload)
WHERE (message_type = 'other' OR body = '[mensagem nÃ£o reconhecida]')
  AND raw_payload IS NOT NULL
  AND public.wa_extract_message_type(raw_payload) <> 'other';

-- Fix direction
UPDATE public.whatsapp_messages
SET direction = 'outbound'
WHERE direction = 'inbound'
  AND raw_payload->>'fromMe' = 'true';
CREATE OR REPLACE FUNCTION public.wa_normalize_phone(raw text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  s text;
  d text;
  ddd text;
  rest text;
BEGIN
  IF raw IS NULL OR raw = '' THEN RETURN ''; END IF;
  s := split_part(raw, '@', 1);
  d := regexp_replace(s, '\D', '', 'g');
  IF d = '' THEN RETURN ''; END IF;
  IF length(d) > 14 THEN RETURN ''; END IF;
  IF left(d, 2) = '00' THEN d := substring(d from 3); END IF;
  IF length(d) = 12 AND left(d, 2) = '55' THEN
    ddd := substring(d from 3 for 2);
    rest := substring(d from 5);
    IF rest ~ '^[6-8]' THEN
      d := '55' || ddd || '9' || rest;
    END IF;
  END IF;
  IF length(d) BETWEEN 12 AND 14 THEN RETURN d; END IF;
  IF length(d) IN (10, 11) THEN RETURN '55' || d; END IF;
  RETURN d;
END;
$$;

WITH bad_messages AS (
  SELECT id,
    '55' || substring(phone_normalized from 3 for 2) || substring(phone_normalized from 6) AS fixed
  FROM public.whatsapp_messages
  WHERE length(phone_normalized) = 13
    AND left(phone_normalized, 2) = '55'
    AND substring(phone_normalized from 5 for 1) = '9'
    AND substring(phone_normalized from 6 for 1) = '9'
)
UPDATE public.whatsapp_messages m
SET phone_normalized = b.fixed
FROM bad_messages b
WHERE m.id = b.id;

WITH bad_leads AS (
  SELECT id,
    '55' || substring(phone_normalized from 3 for 2) || substring(phone_normalized from 6) AS fixed
  FROM public.whatsapp_leads
  WHERE length(phone_normalized) = 13
    AND left(phone_normalized, 2) = '55'
    AND substring(phone_normalized from 5 for 1) = '9'
    AND substring(phone_normalized from 6 for 1) = '9'
)
UPDATE public.whatsapp_leads l
SET phone_normalized = b.fixed
FROM bad_leads b
WHERE l.id = b.id;
ALTER TABLE public.whatsapp_messages ALTER COLUMN occurred_at SET DEFAULT now();
-- Adiciona coluna image_url em products
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS image_url text;

-- Cria bucket pÃºblico para imagens de produtos
INSERT INTO storage.buckets (id, name, public)
VALUES ('product-images', 'product-images', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- PolÃ­ticas de storage para product-images
DROP POLICY IF EXISTS "product_images_public_read" ON storage.objects;
CREATE POLICY "product_images_public_read"
ON storage.objects FOR SELECT
USING (bucket_id = 'product-images');

DROP POLICY IF EXISTS "product_images_auth_insert" ON storage.objects;
CREATE POLICY "product_images_auth_insert"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'product-images');

DROP POLICY IF EXISTS "product_images_auth_update" ON storage.objects;
CREATE POLICY "product_images_auth_update"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'product-images');

DROP POLICY IF EXISTS "product_images_auth_delete" ON storage.objects;
CREATE POLICY "product_images_auth_delete"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'product-images');
ALTER TABLE public.service_order_expenses
  ADD COLUMN IF NOT EXISTS supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL;

ALTER TABLE public.service_order_expenses
  ADD COLUMN IF NOT EXISTS receipt_storage_path text;

INSERT INTO storage.buckets (id, name, public)
VALUES ('expense-receipts', 'expense-receipts', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "expense_receipts_public_read" ON storage.objects;
CREATE POLICY "expense_receipts_public_read"
ON storage.objects FOR SELECT USING (bucket_id = 'expense-receipts');

DROP POLICY IF EXISTS "expense_receipts_auth_insert" ON storage.objects;
CREATE POLICY "expense_receipts_auth_insert"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'expense-receipts');

DROP POLICY IF EXISTS "expense_receipts_auth_delete" ON storage.objects;
CREATE POLICY "expense_receipts_auth_delete"
ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'expense-receipts');
ALTER TABLE public.service_order_services ADD COLUMN IF NOT EXISTS technician_user_id uuid;
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS fiscal_complete boolean NOT NULL DEFAULT true;
ALTER TABLE service_orders
  ADD COLUMN IF NOT EXISTS travel_hours numeric DEFAULT 0,
  ADD COLUMN IF NOT EXISTS ferry_cost numeric DEFAULT 0,
  ADD COLUMN IF NOT EXISTS travel_type text DEFAULT 'comercial'
    CHECK (travel_type IN ('comercial', 'urgencia', 'fds_feriado'));
ALTER TABLE service_orders
  ADD COLUMN IF NOT EXISTS travel_hours numeric DEFAULT 0,
  ADD COLUMN IF NOT EXISTS ferry_cost numeric DEFAULT 0,
  ADD COLUMN IF NOT EXISTS travel_type text DEFAULT 'comercial'
    CHECK (travel_type IN ('comercial', 'urgencia', 'fds_feriado'));
INSERT INTO storage.buckets (id, name, public)
VALUES ('company-assets', 'company-assets', true)
ON CONFLICT (id) DO NOTHING;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'company_assets_public_read' AND tablename = 'objects' AND schemaname = 'storage') THEN
    CREATE POLICY "company_assets_public_read"
    ON storage.objects FOR SELECT USING (bucket_id = 'company-assets');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'company_assets_auth_write' AND tablename = 'objects' AND schemaname = 'storage') THEN
    CREATE POLICY "company_assets_auth_write"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'company-assets');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'company_assets_auth_update' AND tablename = 'objects' AND schemaname = 'storage') THEN
    CREATE POLICY "company_assets_auth_update"
    ON storage.objects FOR UPDATE TO authenticated
    USING (bucket_id = 'company-assets');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'company_assets_auth_delete' AND tablename = 'objects' AND schemaname = 'storage') THEN
    CREATE POLICY "company_assets_auth_delete"
    ON storage.objects FOR DELETE TO authenticated
    USING (bucket_id = 'company-assets');
  END IF;
END $$;
ALTER TABLE public.saved_filters DROP CONSTRAINT IF EXISTS saved_filters_filter_type_check;
ALTER TABLE public.saved_filters ADD CONSTRAINT saved_filters_filter_type_check CHECK (filter_type IN ('payable','receivable','service_orders','products','vessels','agenda'));
ALTER TABLE public.saved_filters ADD COLUMN IF NOT EXISTS user_id uuid;
CREATE INDEX IF NOT EXISTS saved_filters_type_idx ON public.saved_filters(filter_type);
-- Adiciona campos de garantia para controle a nÃ­vel de item e serviÃ§o
ALTER TABLE "public"."service_order_parts" ADD COLUMN IF NOT EXISTS "warranty_days" integer DEFAULT 0;
ALTER TABLE "public"."service_order_services" ADD COLUMN IF NOT EXISTS "warranty_days" integer DEFAULT 0;

-- Para produtos novos, podemos tambÃ©m colocar no cadastro base, mas para o controle de OS a nÃ­vel de item, isso Ã© suficiente.
ALTER TABLE "public"."products" ADD COLUMN IF NOT EXISTS "default_warranty_days" integer DEFAULT 0;
ALTER TABLE "public"."services" ADD COLUMN IF NOT EXISTS "default_warranty_days" integer DEFAULT 0;
-- Tabelas para suporte a Notas Fiscais e XML
CREATE TABLE IF NOT EXISTS "public"."fiscal_notes" (
    "id" uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    "company_id" uuid,
    "nfe_key" text UNIQUE,
    "nfe_number" text,
    "issue_date" timestamp with time zone,
    "issuer_name" text,
    "issuer_cnpj" text,
    "total_value" numeric(12,2),
    "xml_url" text,
    "status" text DEFAULT 'pending', -- pending, processed, error
    "created_at" timestamp with time zone DEFAULT now(),
    "updated_at" timestamp with time zone DEFAULT now()
);

-- Relacionar itens da nota fiscal com produtos do sistema
CREATE TABLE IF NOT EXISTS "public"."fiscal_note_items" (
    "id" uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    "fiscal_note_id" uuid REFERENCES "public"."fiscal_notes"("id") ON DELETE CASCADE,
    "product_id" uuid REFERENCES "public"."products"("id"),
    "item_index" integer,
    "description" text,
    "sku_internal" text,
    "sku_supplier" text,
    "quantity" numeric(12,4),
    "unit_price" numeric(12,2),
    "total_price" numeric(12,2),
    "ncm" text,
    "cfop" text,
    "processed" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT now()
);

-- Adicionar campo para controlar Ãºltima entrada no produto
ALTER TABLE "public"."products" ADD COLUMN IF NOT EXISTS "last_stock_entry_at" timestamp with time zone;
ALTER TABLE "public"."products" ADD COLUMN IF NOT EXISTS "supplier_id" uuid REFERENCES "public"."suppliers"("id");
-- Tabela de ComissÃµes
CREATE TABLE IF NOT EXISTS "public"."commissions" (
    "id" uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    "service_order_id" uuid REFERENCES "public"."service_orders"("id") ON DELETE CASCADE,
    "user_id" uuid REFERENCES "public"."app_users"("id"), -- TÃ©cnico ou Vendedor
    "amount" numeric(12,2) NOT NULL,
    "base_value" numeric(12,2), -- Valor base para o cÃ¡lculo (ex: lucro ou total)
    "percentage" numeric(5,2),
    "status" text DEFAULT 'pending', -- pending, approved, paid, cancelled
    "paid_at" timestamp with time zone,
    "payable_id" uuid REFERENCES "public"."payables"("id"), -- VÃ­nculo com o financeiro
    "created_at" timestamp with time zone DEFAULT now(),
    "updated_at" timestamp with time zone DEFAULT now()
);

-- Habilitar RLS
ALTER TABLE "public"."commissions" ENABLE ROW LEVEL SECURITY;

-- PolÃ­tica simples: admin vÃª tudo, tÃ©cnico vÃª as suas
CREATE POLICY "Admins can do everything on commissions" ON "public"."commissions"
    FOR ALL TO authenticated USING (public.is_admin(auth.uid())) WITH CHECK (public.is_admin(auth.uid()));

CREATE POLICY "Users can view own commissions" ON "public"."commissions"
    FOR SELECT TO authenticated USING (auth.uid() = user_id);
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Migration: fiscal_notes table + confirm_nfe_import RPC
-- 100% idempotent: safe to run even if any part was already applied
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- 1. Create table if it doesn't exist yet
-- SKIPPED PRE-CREATED TABLE: fiscal_notes

-- 2. Add missing columns (safe if they already exist)
ALTER TABLE fiscal_notes ADD COLUMN IF NOT EXISTS issued_at    timestamptz;
ALTER TABLE fiscal_notes ADD COLUMN IF NOT EXISTS total_amount numeric(14,2) DEFAULT 0;
ALTER TABLE fiscal_notes ADD COLUMN IF NOT EXISTS tax_icms     numeric(14,2) DEFAULT 0;
ALTER TABLE fiscal_notes ADD COLUMN IF NOT EXISTS tax_ipi      numeric(14,2) DEFAULT 0;
ALTER TABLE fiscal_notes ADD COLUMN IF NOT EXISTS tax_pis      numeric(14,2) DEFAULT 0;
ALTER TABLE fiscal_notes ADD COLUMN IF NOT EXISTS tax_cofins   numeric(14,2) DEFAULT 0;
ALTER TABLE fiscal_notes ADD COLUMN IF NOT EXISTS items        jsonb DEFAULT '[]';
ALTER TABLE fiscal_notes ADD COLUMN IF NOT EXISTS xml_content  text;
ALTER TABLE fiscal_notes ADD COLUMN IF NOT EXISTS confirmed_at timestamptz;

-- 3. Status constraint (drop old variations, add canonical one)
ALTER TABLE fiscal_notes DROP CONSTRAINT IF EXISTS fiscal_notes_status_check;
ALTER TABLE fiscal_notes DROP CONSTRAINT IF EXISTS chk_fiscal_notes_status;
ALTER TABLE fiscal_notes ADD CONSTRAINT fiscal_notes_status_check
  CHECK (status IN ('pending','confirmed','cancelled','error'));

-- 4. Indexes
CREATE INDEX IF NOT EXISTS idx_fiscal_notes_status    ON fiscal_notes (status);
CREATE INDEX IF NOT EXISTS idx_fiscal_notes_nfe_key   ON fiscal_notes (nfe_key);
CREATE INDEX IF NOT EXISTS idx_fiscal_notes_issued_at ON fiscal_notes (issued_at DESC);

-- 5. RLS
ALTER TABLE fiscal_notes ENABLE ROW LEVEL SECURITY;

-- Drop ALL known policy names (handles both old and new naming conventions)
DROP POLICY IF EXISTS "fiscal_notes_select"           ON fiscal_notes;
DROP POLICY IF EXISTS "fiscal_notes_insert"           ON fiscal_notes;
DROP POLICY IF EXISTS "fiscal_notes_update"           ON fiscal_notes;
DROP POLICY IF EXISTS "authenticated_all_fiscal_notes" ON fiscal_notes;

CREATE POLICY "fiscal_notes_select" ON fiscal_notes FOR SELECT TO authenticated USING (true);
CREATE POLICY "fiscal_notes_insert" ON fiscal_notes FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "fiscal_notes_update" ON fiscal_notes FOR UPDATE TO authenticated USING (true);

-- 6. Extend payables.origin constraint
ALTER TABLE public.payables DROP CONSTRAINT IF EXISTS chk_payables_origin;
ALTER TABLE public.payables ADD CONSTRAINT chk_payables_origin
  CHECK (origin IN ('manual','service_order_expense','bank_reconciliation','fiscal_note','commission'));

-- 7. Extend inventory_movements.movement_type constraint
ALTER TABLE public.inventory_movements
  DROP CONSTRAINT IF EXISTS inventory_movements_movement_type_check;
ALTER TABLE public.inventory_movements
  ADD CONSTRAINT inventory_movements_movement_type_check
  CHECK (movement_type IN (
    'purchase','manual_adjustment','service_usage','return','transfer',
    'manual_add','manual_remove','import','fiscal_note_entry',
    'service_order_usage','manual_add_stock','manual_remove_stock'
  ));

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 8. RPC: confirm_nfe_import (atomic: stock + movements + payable + audit)
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
CREATE OR REPLACE FUNCTION confirm_nfe_import(
  p_note_id      uuid,
  p_supplier_id  uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_note              fiscal_notes%ROWTYPE;
  v_item              jsonb;
  v_product_id        uuid;
  v_qty               numeric;
  v_cost              numeric;
  v_movements         int := 0;
  v_created_products  int := 0;
  v_supplier_name     text;
BEGIN
  SELECT * INTO v_note FROM fiscal_notes WHERE id = p_note_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'fiscal_note % not found', p_note_id;
  END IF;
  IF v_note.status <> 'pending' THEN
    RAISE EXCEPTION 'fiscal_note already has status %, cannot confirm again', v_note.status;
  END IF;

  IF p_supplier_id IS NOT NULL THEN
    SELECT supplier_name INTO v_supplier_name FROM suppliers WHERE id = p_supplier_id;
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(v_note.items, '[]')) LOOP
    v_qty  := COALESCE((v_item->>'quantity')::numeric, 0);
    v_cost := COALESCE((v_item->>'unit_price')::numeric, 0);

    SELECT id INTO v_product_id
      FROM products
     WHERE (sku IS NOT NULL AND sku = (v_item->>'sku_supplier'))
        OR lower(product_name) = lower(COALESCE(v_item->>'description', ''))
     LIMIT 1;

    IF v_product_id IS NULL THEN
      INSERT INTO products (product_name, sku, cost_price, stock_quantity, ncm, active)
      VALUES (
        COALESCE(v_item->>'description', 'Produto sem nome'),
        v_item->>'sku_supplier',
        v_cost,
        v_qty,
        v_item->>'ncm',
        true
      )
      RETURNING id INTO v_product_id;
      v_created_products := v_created_products + 1;
    ELSE
      UPDATE products
         SET stock_quantity = stock_quantity + v_qty,
             cost_price     = v_cost,
             updated_at     = now()
       WHERE id = v_product_id;
    END IF;

    INSERT INTO inventory_movements (
      product_id, movement_type, quantity_delta,
      unit_cost_snapshot, reference_type, reference_id, notes
    ) VALUES (
      v_product_id,
      'purchase',
      v_qty,
      v_cost,
      'fiscal_note',
      p_note_id,
      format('NF-e %s â€“ %s',
        COALESCE(v_note.nfe_number, '?'),
        COALESCE(v_note.issuer_name, '?')
      )
    );
    v_movements := v_movements + 1;
  END LOOP;

  IF p_supplier_id IS NOT NULL THEN
    INSERT INTO payables (
      supplier_id, supplier_name, description,
      issue_date, due_date, amount, status, origin, notes
    ) VALUES (
      p_supplier_id,
      COALESCE(v_supplier_name, v_note.issuer_name),
      format('NF-e nÂº %s â€“ %s',
        COALESCE(v_note.nfe_number, '?'),
        COALESCE(v_note.issuer_name, '?')
      ),
      CURRENT_DATE,
      (CURRENT_DATE + interval '30 days')::date,
      v_note.total_amount,
      'pending',
      'fiscal_note',
      format('ImportaÃ§Ã£o automÃ¡tica â€“ chave %s', COALESCE(v_note.nfe_key, 'sem-chave'))
    );
  END IF;

  UPDATE fiscal_notes
     SET status = 'confirmed', confirmed_at = now(), updated_at = now()
   WHERE id = p_note_id;

  INSERT INTO audit_logs (table_name, record_id, action, new_value, reason)
  VALUES (
    'fiscal_notes',
    p_note_id,
    'confirm_import',
    jsonb_build_object(
      'movements_created', v_movements,
      'products_created',  v_created_products,
      'total_amount',      v_note.total_amount,
      'supplier_id',       p_supplier_id
    ),
    'ConfirmaÃ§Ã£o de importaÃ§Ã£o de NF-e'
  );

  RETURN jsonb_build_object(
    'success',           true,
    'movements_created', v_movements,
    'products_created',  v_created_products
  );
END;
$$;
-- MigraÃ§Ã£o para suporte a mapeamento inteligente de produtos de fornecedores
-- Nome: 20260428020000_supplier_product_mappings.sql

-- SKIPPED PRE-CREATED TABLE: supplier_product_mappings

-- Habilitar RLS
ALTER TABLE public.supplier_product_mappings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Enable all for authenticated users" ON public.supplier_product_mappings
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- ComentÃ¡rios para documentaÃ§Ã£o
COMMENT ON TABLE public.supplier_product_mappings IS 'Armazena o vÃ­nculo entre SKUs de fornecedores (XML) e produtos internos do catÃ¡logo.';

-- Atualizar a funÃ§Ã£o confirm_nfe_import para usar mapeamentos
CREATE OR REPLACE FUNCTION confirm_nfe_import(
    p_note_id UUID,
    p_supplier_id UUID DEFAULT NULL,
    p_manual_mappings JSONB DEFAULT '[]'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_note_status TEXT;
    v_items JSONB;
    v_item RECORD;
    v_product_id UUID;
    v_movement_id UUID;
    v_products_created INT := 0;
    v_movements_created INT := 0;
    v_payable_id UUID;
    v_total_amount DECIMAL;
    v_nfe_number TEXT;
    v_issuer_name TEXT;
    v_issuer_cnpj TEXT;
    v_manual_prod_id UUID;
BEGIN
    -- 1. Validar status da nota
    SELECT status, items, total_amount, nfe_number, issuer_name, issuer_cnpj
    INTO v_note_status, v_items, v_total_amount, v_nfe_number, v_issuer_name, v_issuer_cnpj
    FROM fiscal_notes WHERE id = p_note_id;

    IF v_note_status != 'pending' THEN
        RAISE EXCEPTION 'Esta nota jÃ¡ foi processada ou cancelada.';
    END IF;

    -- 2. Processar cada item
    FOR v_item IN SELECT * FROM jsonb_to_recordset(v_items) AS x(
        sku_supplier TEXT,
        description TEXT,
        ncm TEXT,
        unit TEXT,
        quantity DECIMAL,
        unit_price DECIMAL,
        total_price DECIMAL
    ) LOOP
        
        v_product_id := NULL;

        -- 2.1 Verificar mapeamento manual enviado pelo frontend
        IF p_manual_mappings IS NOT NULL AND v_item.sku_supplier IS NOT NULL THEN
            SELECT (val->>'internal_product_id')::UUID INTO v_manual_prod_id
            FROM jsonb_array_elements(p_manual_mappings) AS val
            WHERE val->>'sku_supplier' = v_item.sku_supplier;
            
            IF v_manual_prod_id IS NOT NULL THEN
                v_product_id := v_manual_prod_id;
            END IF;
        END IF;

        -- 2.2 Se nÃ£o tem manual, tentar encontrar por mapeamento prÃ©vio no banco
        IF v_product_id IS NULL AND p_supplier_id IS NOT NULL AND v_item.sku_supplier IS NOT NULL THEN
            SELECT internal_product_id INTO v_product_id
            FROM supplier_product_mappings
            WHERE supplier_id = p_supplier_id AND supplier_sku = v_item.sku_supplier;
        END IF;

        -- 2.3 Se nÃ£o encontrou mapping, tentar por SKU interno
        IF v_product_id IS NULL THEN
            SELECT id INTO v_product_id FROM products 
            WHERE sku = v_item.sku_supplier AND active = true;
        END IF;

        -- 2.4 Se ainda nÃ£o encontrou, tentar por nome exato
        IF v_product_id IS NULL THEN
            SELECT id INTO v_product_id FROM products 
            WHERE LOWER(product_name) = LOWER(v_item.description) AND active = true;
        END IF;

        -- 2.5 Se ainda nÃ£o encontrou, CRIAR novo produto
        IF v_product_id IS NULL THEN
            INSERT INTO products (
                product_name,
                sku,
                category,
                unit,
                cost_price,
                sale_price,
                stock_quantity,
                fiscal_ncm,
                active,
                fiscal_complete
            ) VALUES (
                v_item.description,
                v_item.sku_supplier,
                'Importados',
                COALESCE(v_item.unit, 'un'),
                v_item.unit_price,
                v_item.unit_price * 1.3, -- Margem padrÃ£o 30%
                0, -- ComeÃ§a com 0, o movimento vai adicionar
                v_item.ncm,
                true,
                false -- Marcar como incompleto para revisÃ£o fiscal
            ) RETURNING id INTO v_product_id;
            
            v_products_created := v_products_created + 1;
        END IF;

        -- 2.6 Persistir mapeamento (aprendizado automÃ¡tico)
        IF p_supplier_id IS NOT NULL AND v_item.sku_supplier IS NOT NULL THEN
            INSERT INTO supplier_product_mappings (supplier_id, supplier_sku, supplier_description, internal_product_id)
            VALUES (p_supplier_id, v_item.sku_supplier, v_item.description, v_product_id)
            ON CONFLICT (supplier_id, supplier_sku) DO UPDATE SET
                supplier_description = EXCLUDED.supplier_description,
                internal_product_id = EXCLUDED.internal_product_id,
                updated_at = now();
        END IF;

        -- 3. Registrar movimento de estoque
        INSERT INTO inventory_movements (
            product_id,
            movement_type,
            quantity_delta,
            unit_cost_snapshot,
            reference_type,
            fiscal_note_id,
            notes
        ) VALUES (
            v_product_id,
            'purchase',
            v_item.quantity,
            v_item.unit_price,
            'import',
            p_note_id,
            'Entrada via NF-e ' || v_nfe_number
        ) RETURNING id INTO v_movement_id;

        v_movements_created := v_movements_created + 1;

        -- 4. InteligÃªncia de PreÃ§o: Gerar sugestÃ£o se o custo aumentou ou para manter margem
        DECLARE
            v_old_cost DECIMAL;
            v_current_sale DECIMAL;
            v_category_margin DECIMAL;
            v_suggested_sale DECIMAL;
        BEGIN
            SELECT cost_price, sale_price INTO v_old_cost, v_current_sale FROM products WHERE id = v_product_id;
            
            -- Buscar margem da categoria (se nÃ£o tiver, usar 30%)
            SELECT COALESCE(default_profit_margin, 30) INTO v_category_margin 
            FROM product_categories 
            WHERE name = (SELECT category FROM products WHERE id = v_product_id);

            -- Se o novo custo for maior que o antigo, ou se a margem atual estiver defasada
            IF v_item.unit_price > v_old_cost OR v_current_sale < (v_item.unit_price * (1 + v_category_margin/100)) THEN
                v_suggested_sale := v_item.unit_price * (1 + v_category_margin/100);
                
                INSERT INTO price_update_suggestions (product_id, fiscal_note_id, current_sale_price, suggested_sale_price, margin_percent)
                VALUES (v_product_id, p_note_id, v_current_sale, v_suggested_sale, v_category_margin);
            END IF;
        END;

        -- Atualizar custo e estoque no produto
        UPDATE products SET 
            cost_price = v_item.unit_price,
            stock_quantity = stock_quantity + v_item.quantity,
            updated_at = now()
        WHERE id = v_product_id;
    END LOOP;

    -- 4. Gerar conta a pagar se tiver fornecedor
    IF p_supplier_id IS NOT NULL THEN
        INSERT INTO payables (
            supplier_id,
            amount,
            balance_amount,
            description,
            issue_date,
            due_date,
            status,
            expense_category,
            fiscal_note_id,
            origin
        ) VALUES (
            p_supplier_id,
            v_total_amount,
            v_total_amount,
            'Compra ref. NF-e ' || v_nfe_number || ' - ' || v_issuer_name,
            now()::date,
            (now() + interval '28 days')::date, -- Prazo padrÃ£o
            'pending',
            'Compras de Mercadorias',
            p_note_id,
            'fiscal_import'
        ) RETURNING id INTO v_payable_id;
    END IF;

    -- 5. Finalizar nota
    UPDATE fiscal_notes SET 
        status = 'confirmed',
        confirmed_at = now(),
        updated_at = now()
    WHERE id = p_note_id;

    RETURN jsonb_build_object(
        'success', true,
        'products_created', v_products_created,
        'movements_created', v_movements_created,
        'payable_id', v_payable_id
    );
END;
$$;
-- Garantia em produtos e serviÃ§os
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS default_warranty_days integer DEFAULT 0;
ALTER TABLE public.services ADD COLUMN IF NOT EXISTS default_warranty_days integer DEFAULT 0;

-- Garantia nos itens de OS
ALTER TABLE public.service_order_parts ADD COLUMN IF NOT EXISTS warranty_days integer DEFAULT 0;
ALTER TABLE public.service_order_services ADD COLUMN IF NOT EXISTS warranty_days integer DEFAULT 0;

-- Tabela de notas fiscais importadas
-- SKIPPED PRE-CREATED TABLE: fiscal_notes

-- SKIPPED PRE-CREATED TABLE: fiscal_note_items

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
-- price_intelligence.sql â€” idempotente
-- SKIPPED PRE-CREATED TABLE: product_price_history

-- SKIPPED PRE-CREATED TABLE: price_update_suggestions

ALTER TABLE public.product_price_history    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.price_update_suggestions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Enable all for authenticated users" ON public.product_price_history;
DROP POLICY IF EXISTS "Enable all for authenticated users" ON public.price_update_suggestions;
CREATE POLICY "Enable all for authenticated users" ON public.product_price_history    FOR ALL TO authenticated USING (true);
CREATE POLICY "Enable all for authenticated users" ON public.price_update_suggestions FOR ALL TO authenticated USING (true);

DROP TRIGGER IF EXISTS tr_log_product_cost_change ON public.products;

CREATE OR REPLACE FUNCTION log_product_cost_change()
RETURNS TRIGGER AS $$
BEGIN
    IF (OLD.cost_price IS DISTINCT FROM NEW.cost_price) THEN
        INSERT INTO product_price_history (product_id, old_cost, new_cost)
        VALUES (NEW.id, OLD.cost_price, NEW.cost_price);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_log_product_cost_change
    AFTER UPDATE OF cost_price ON public.products
    FOR EACH ROW EXECUTE FUNCTION log_product_cost_change();
-- View de Lucratividade Real por Ordem de ServiÃ§o
-- Nome: 20260428040000_profitability_view.sql

CREATE OR REPLACE VIEW public.vw_os_profitability AS
WITH os_costs AS (
    -- Soma dos custos de peÃ§as baseados no snapshot de custo (vindo do XML ou entrada manual)
    SELECT 
        service_order_id,
        SUM(quantity * unit_cost_snapshot) as total_parts_cost
    FROM public.service_order_parts
    GROUP BY service_order_id
),
os_commissions AS (
    -- Soma das comissÃµes aprovadas ou pendentes para a OS
    SELECT 
        service_order_id,
        SUM(amount) as total_commission
    FROM public.commissions
    WHERE status != 'cancelled'
    GROUP BY service_order_id
)
SELECT 
    so.id as os_id,
    so.service_order_number,
    so.status,
    so.grand_total as revenue,
    COALESCE(oc.total_parts_cost, 0) as parts_cost,
    COALESCE(so.travel_cost_total, 0) as travel_cost,
    COALESCE(so.operational_cost_total, 0) as operational_cost,
    COALESCE(com.total_commission, 0) as commission_cost,
    -- Lucro Bruto (Receita - Custo de PeÃ§as)
    (so.grand_total - COALESCE(oc.total_parts_cost, 0)) as gross_profit,
    -- Lucro LÃ­quido (Receita - Todos os Custos)
    (so.grand_total - 
        COALESCE(oc.total_parts_cost, 0) - 
        COALESCE(so.travel_cost_total, 0) - 
        COALESCE(so.operational_cost_total, 0) - 
        COALESCE(com.total_commission, 0)
    ) as net_profit,
    -- Margem LÃ­quida %
    CASE 
        WHEN so.grand_total > 0 THEN 
            ((so.grand_total - COALESCE(oc.total_parts_cost, 0) - COALESCE(so.travel_cost_total, 0) - COALESCE(so.operational_cost_total, 0) - COALESCE(com.total_commission, 0)) / so.grand_total) * 100
        ELSE 0 
    END as net_margin_percent,
    so.created_at,
    so.check_out_at as finished_at,
    c.full_name_or_company_name as client_name
FROM 
    public.service_orders so
LEFT JOIN os_costs oc ON oc.service_order_id = so.id
LEFT JOIN os_commissions com ON com.service_order_id = so.id
LEFT JOIN public.clients c ON c.id = so.client_id;

-- PermissÃµes
GRANT SELECT ON public.vw_os_profitability TO authenticated;
-- OtimizaÃ§Ã£o de Performance - Ãndices
-- Nome: 20260428050000_performance_indices.sql

-- Ãndices para buscas rÃ¡pidas em inventÃ¡rio
CREATE INDEX IF NOT EXISTS idx_products_sku      ON public.products(sku)      WHERE active = true;
CREATE INDEX IF NOT EXISTS idx_products_category ON public.products(category) WHERE active = true;

-- Ãndices para movimentos de estoque
CREATE INDEX IF NOT EXISTS idx_inv_movements_product_date ON public.inventory_movements(product_id, created_at DESC);
-- NOTE: idx_inv_movements_fiscal_note removed â€” fiscal_note_id column does not exist in inventory_movements

-- Ãndices para o financeiro
CREATE INDEX IF NOT EXISTS idx_payables_supplier_status  ON public.payables(supplier_id, status);
CREATE INDEX IF NOT EXISTS idx_receivables_client_status ON public.receivables(client_id, status);
CREATE INDEX IF NOT EXISTS idx_payments_date             ON public.payments(payment_date DESC);

-- Ãndices para Ordens de ServiÃ§o
CREATE INDEX IF NOT EXISTS idx_service_orders_client_status ON public.service_orders(client_id, status);
CREATE INDEX IF NOT EXISTS idx_service_orders_created_at    ON public.service_orders(created_at DESC);

-- Atualizar estatÃ­sticas do query planner
ANALYZE public.products;
ANALYZE public.inventory_movements;
ANALYZE public.service_orders;
ANALYZE public.payables;
ANALYZE public.receivables;
-- Migration: Add asset_type to vessels
-- Name: 20260428070000_asset_types.sql

ALTER TABLE public.vessels ADD COLUMN IF NOT EXISTS asset_type TEXT DEFAULT 'Lancha';

-- Comment on column
COMMENT ON COLUMN public.vessels.asset_type IS 'Type of the asset (e.g., Lancha, Veleiro, CatamarÃ£, Motorhome, Camper, Trailer). Default is Lancha for legacy data.';
ALTER TABLE service_orders ADD COLUMN photos JSONB DEFAULT '[]'::jsonb;
-- financial_dre.sql â€” idempotente
CREATE TABLE IF NOT EXISTS cost_centers (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name VARCHAR NOT NULL,
  type VARCHAR NOT NULL CHECK (type IN ('revenue', 'expense', 'both')),
  parent_id UUID REFERENCES cost_centers(id),
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE cost_centers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Enable read/write for all authenticated users" ON cost_centers;
CREATE POLICY "Enable read/write for all authenticated users"
  ON cost_centers FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Insert default DRE structure (only if table is empty)
INSERT INTO cost_centers (name, type)
SELECT name, type FROM (VALUES
  ('Receitas Operacionais',             'revenue'),
  ('DeduÃ§Ãµes e Impostos',               'expense'),
  ('Custos VariÃ¡veis (CPV/CSV)',        'expense'),
  ('Despesas Operacionais Fixas',       'expense'),
  ('Despesas com Pessoal',              'expense'),
  ('Despesas Administrativas',          'expense'),
  ('Resultado Financeiro (Taxas/Juros)','expense')
) AS v(name, type)
WHERE NOT EXISTS (SELECT 1 FROM cost_centers LIMIT 1);

-- Add cost center columns (safe if already exist)
ALTER TABLE payables    ADD COLUMN IF NOT EXISTS cost_center_id UUID REFERENCES cost_centers(id);
ALTER TABLE payables    ADD COLUMN IF NOT EXISTS sub_category VARCHAR;
ALTER TABLE receivables ADD COLUMN IF NOT EXISTS cost_center_id UUID REFERENCES cost_centers(id);
ALTER TABLE receivables ADD COLUMN IF NOT EXISTS sub_category VARCHAR;
-- Sincroniza estruturas das Fases 1-4 que ainda nÃ£o foram aplicadas

-- 1. Ativos genÃ©ricos (Barcos / Motorhomes / etc)
ALTER TABLE public.vessels ADD COLUMN IF NOT EXISTS asset_type TEXT DEFAULT 'Lancha';
COMMENT ON COLUMN public.vessels.asset_type IS 'Tipo do ativo (Lancha, Veleiro, CatamarÃ£, Motorhome, Camper, Trailer)';

-- 2. Fotos de Ordem de ServiÃ§o
ALTER TABLE public.service_orders ADD COLUMN IF NOT EXISTS photos JSONB DEFAULT '[]'::jsonb;

-- 3. Centros de Custo (DRE)
CREATE TABLE IF NOT EXISTS public.cost_centers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR NOT NULL,
  type VARCHAR NOT NULL CHECK (type IN ('revenue','expense','both')),
  parent_id UUID REFERENCES public.cost_centers(id),
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.cost_centers ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='cost_centers' AND policyname='cost_centers_all_authenticated') THEN
    CREATE POLICY "cost_centers_all_authenticated" ON public.cost_centers
      FOR ALL TO authenticated USING (true) WITH CHECK (true);
  END IF;
END $$;

INSERT INTO public.cost_centers (name, type)
SELECT v.name, v.type FROM (VALUES
  ('Receitas Operacionais','revenue'),
  ('DeduÃ§Ãµes e Impostos','expense'),
  ('Custos VariÃ¡veis (CPV/CSV)','expense'),
  ('Despesas Operacionais Fixas','expense'),
  ('Despesas com Pessoal','expense'),
  ('Despesas Administrativas','expense'),
  ('Resultado Financeiro (Taxas/Juros)','expense')
) AS v(name,type)
WHERE NOT EXISTS (SELECT 1 FROM public.cost_centers cc WHERE cc.name = v.name);

ALTER TABLE public.payables ADD COLUMN IF NOT EXISTS cost_center_id UUID REFERENCES public.cost_centers(id);
ALTER TABLE public.payables ADD COLUMN IF NOT EXISTS sub_category VARCHAR;
ALTER TABLE public.receivables ADD COLUMN IF NOT EXISTS cost_center_id UUID REFERENCES public.cost_centers(id);
ALTER TABLE public.receivables ADD COLUMN IF NOT EXISTS sub_category VARCHAR;

-- 4. ComissÃµes
CREATE TABLE IF NOT EXISTS public.commissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_order_id UUID REFERENCES public.service_orders(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.app_users(id),
  amount NUMERIC(12,2) NOT NULL,
  base_value NUMERIC(12,2),
  percentage NUMERIC(5,2),
  status TEXT DEFAULT 'pending',
  paid_at TIMESTAMPTZ,
  payable_id UUID REFERENCES public.payables(id),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.commissions ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='commissions' AND policyname='commissions_admin_all') THEN
    CREATE POLICY "commissions_admin_all" ON public.commissions
      FOR ALL TO authenticated USING (public.is_admin(auth.uid())) WITH CHECK (public.is_admin(auth.uid()));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='commissions' AND policyname='commissions_self_select') THEN
    CREATE POLICY "commissions_self_select" ON public.commissions
      FOR SELECT TO authenticated USING (auth.uid() = user_id);
  END IF;
END $$;

-- 5. Mapeamento SKU fornecedor -> produto interno
-- SKIPPED PRE-CREATED TABLE: supplier_product_mappings
ALTER TABLE public.supplier_product_mappings ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='supplier_product_mappings' AND policyname='spm_all_authenticated') THEN
    CREATE POLICY "spm_all_authenticated" ON public.supplier_product_mappings
      FOR ALL TO authenticated USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 6. InteligÃªncia de preÃ§os
-- SKIPPED PRE-CREATED TABLE: product_price_history
ALTER TABLE public.product_price_history ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='product_price_history' AND policyname='pph_all_authenticated') THEN
    CREATE POLICY "pph_all_authenticated" ON public.product_price_history
      FOR ALL TO authenticated USING (true) WITH CHECK (true);
  END IF;
END $$;

-- SKIPPED PRE-CREATED TABLE: price_update_suggestions
ALTER TABLE public.price_update_suggestions ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='price_update_suggestions' AND policyname='pus_all_authenticated') THEN
    CREATE POLICY "pus_all_authenticated" ON public.price_update_suggestions
      FOR ALL TO authenticated USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 7. Produtos: Ãºltima entrada de estoque
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS last_stock_entry_at TIMESTAMPTZ;
ALTER TABLE service_orders ADD COLUMN IF NOT EXISTS reminder_sent_at TIMESTAMPTZ;
-- Add HR and Financial fields to app_users
ALTER TABLE public.app_users 
ADD COLUMN IF NOT EXISTS cpf TEXT,
ADD COLUMN IF NOT EXISTS rg TEXT,
ADD COLUMN IF NOT EXISTS birth_date DATE,
ADD COLUMN IF NOT EXISTS hiring_date DATE,
ADD COLUMN IF NOT EXISTS resignation_date DATE,
ADD COLUMN IF NOT EXISTS department TEXT,
ADD COLUMN IF NOT EXISTS salary_base NUMERIC(15,2),
ADD COLUMN IF NOT EXISTS pix_key TEXT,
ADD COLUMN IF NOT EXISTS emergency_contact_name TEXT,
ADD COLUMN IF NOT EXISTS emergency_contact_phone TEXT,
ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}'::jsonb;

-- Update RLS to ensure sensitive data is protected (basic check)
-- Assume Admins can see everything, others can see their own
COMMENT ON COLUMN public.app_users.salary_base IS 'Sensible data - restricted to admin/HR';
COMMENT ON COLUMN public.app_users.cpf IS 'Sensible data';

-- 1. Allow external_seller role
ALTER TABLE public.app_users DROP CONSTRAINT IF EXISTS app_users_role_check;

-- 2. Helper: check if user is external seller
CREATE OR REPLACE FUNCTION public.is_external_seller(_user_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.app_users
    WHERE id = _user_id AND role = 'external_seller' AND active = true
  );
$$;

-- 3. Helper: financial or admin
CREATE OR REPLACE FUNCTION public.is_admin_or_financial(_user_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.app_users
    WHERE id = _user_id AND role IN ('admin','financial') AND active = true
  );
$$;

-- 4. external_quote_leads
CREATE TABLE public.external_quote_leads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by uuid NOT NULL,
  promoted_client_id uuid REFERENCES public.clients(id) ON DELETE SET NULL,
  type text NOT NULL DEFAULT 'individual',
  full_name_or_company_name text NOT NULL,
  cpf_cnpj text,
  phone text,
  whatsapp text,
  email text,
  address_line_1 text,
  address_line_2 text,
  city text,
  state text,
  postal_code text,
  country text DEFAULT 'Brazil',
  boat_name text,
  boat_manufacturer text,
  boat_model text,
  boat_year integer,
  boat_length_feet numeric,
  marina_name text,
  notes text,
  promoted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.external_quote_leads ENABLE ROW LEVEL SECURITY;

CREATE POLICY eql_select ON public.external_quote_leads FOR SELECT TO authenticated
USING (created_by = auth.uid() OR is_admin_or_financial(auth.uid()));

CREATE POLICY eql_insert ON public.external_quote_leads FOR INSERT TO authenticated
WITH CHECK (created_by = auth.uid());

CREATE POLICY eql_update ON public.external_quote_leads FOR UPDATE TO authenticated
USING (created_by = auth.uid() OR is_admin_or_financial(auth.uid()))
WITH CHECK (created_by = auth.uid() OR is_admin_or_financial(auth.uid()));

CREATE POLICY eql_delete ON public.external_quote_leads FOR DELETE TO authenticated
USING (is_admin_or_financial(auth.uid()));

CREATE TRIGGER trg_eql_updated BEFORE UPDATE ON public.external_quote_leads
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- 5. external_quotes
CREATE TABLE public.external_quotes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  quote_number text NOT NULL UNIQUE DEFAULT ('EQ-' || to_char(now(),'YYYYMMDD') || '-' || substr(gen_random_uuid()::text,1,6)),
  created_by uuid NOT NULL,
  lead_id uuid REFERENCES public.external_quote_leads(id) ON DELETE SET NULL,
  client_id uuid REFERENCES public.clients(id) ON DELETE SET NULL,
  vessel_id uuid REFERENCES public.vessels(id) ON DELETE SET NULL,
  marina_id uuid REFERENCES public.marinas(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'draft', -- draft, submitted, approved, rejected, converted, cancelled
  service_type text,
  problem_description text,
  initial_findings text,
  customer_visible_report text,
  internal_notes text,
  hourly_rate numeric DEFAULT 0,
  estimated_hours numeric DEFAULT 0,
  labor_cost_total numeric DEFAULT 0,
  travel_distance_km numeric DEFAULT 0,
  travel_cost_per_km numeric DEFAULT 0,
  travel_cost_total numeric DEFAULT 0,
  parts_cost_total numeric DEFAULT 0,
  subcontract_cost_total numeric DEFAULT 0,
  discount_amount numeric DEFAULT 0,
  tax_amount numeric DEFAULT 0,
  grand_total numeric DEFAULT 0,
  currency text DEFAULT 'BRL',
  quote_validity_days integer DEFAULT 15,
  quote_validity_date date,
  payment_conditions text,
  submitted_at timestamptz,
  reviewed_by uuid,
  reviewed_at timestamptz,
  rejection_reason text,
  converted_service_order_id uuid REFERENCES public.service_orders(id) ON DELETE SET NULL,
  converted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.external_quotes ENABLE ROW LEVEL SECURITY;

CREATE POLICY eq_select ON public.external_quotes FOR SELECT TO authenticated
USING (created_by = auth.uid() OR is_admin_or_financial(auth.uid()));

CREATE POLICY eq_insert ON public.external_quotes FOR INSERT TO authenticated
WITH CHECK (created_by = auth.uid());

CREATE POLICY eq_update ON public.external_quotes FOR UPDATE TO authenticated
USING (
  (created_by = auth.uid() AND status IN ('draft','rejected'))
  OR is_admin_or_financial(auth.uid())
)
WITH CHECK (
  (created_by = auth.uid() AND status IN ('draft','submitted','rejected'))
  OR is_admin_or_financial(auth.uid())
);

CREATE POLICY eq_delete ON public.external_quotes FOR DELETE TO authenticated
USING (is_admin_or_financial(auth.uid()) OR (created_by = auth.uid() AND status = 'draft'));

CREATE TRIGGER trg_eq_updated BEFORE UPDATE ON public.external_quotes
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE INDEX idx_eq_created_by ON public.external_quotes(created_by);
CREATE INDEX idx_eq_status ON public.external_quotes(status);

-- 6. external_quote_parts
CREATE TABLE public.external_quote_parts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  external_quote_id uuid NOT NULL REFERENCES public.external_quotes(id) ON DELETE CASCADE,
  product_id uuid REFERENCES public.products(id) ON DELETE SET NULL,
  product_name_snapshot text NOT NULL,
  quantity numeric NOT NULL DEFAULT 1,
  unit_cost_snapshot numeric NOT NULL DEFAULT 0,
  unit_sale_snapshot numeric NOT NULL DEFAULT 0,
  currency_snapshot text DEFAULT 'BRL',
  line_total_cost numeric NOT NULL DEFAULT 0,
  line_total_sale numeric NOT NULL DEFAULT 0,
  warranty_days integer DEFAULT 0,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.external_quote_parts ENABLE ROW LEVEL SECURITY;

CREATE POLICY eqp_all ON public.external_quote_parts FOR ALL TO authenticated
USING (EXISTS (SELECT 1 FROM public.external_quotes q WHERE q.id = external_quote_id
  AND (q.created_by = auth.uid() OR is_admin_or_financial(auth.uid()))))
WITH CHECK (EXISTS (SELECT 1 FROM public.external_quotes q WHERE q.id = external_quote_id
  AND (q.created_by = auth.uid() OR is_admin_or_financial(auth.uid()))));

CREATE TRIGGER trg_eqp_updated BEFORE UPDATE ON public.external_quote_parts
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- 7. external_quote_services
CREATE TABLE public.external_quote_services (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  external_quote_id uuid NOT NULL REFERENCES public.external_quotes(id) ON DELETE CASCADE,
  service_id uuid,
  service_name_snapshot text NOT NULL,
  description_snapshot text,
  billing_unit_snapshot text NOT NULL DEFAULT 'hour',
  quantity numeric NOT NULL DEFAULT 1,
  unit_price_snapshot numeric NOT NULL DEFAULT 0,
  line_total numeric NOT NULL DEFAULT 0,
  warranty_days integer DEFAULT 0,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.external_quote_services ENABLE ROW LEVEL SECURITY;

CREATE POLICY eqs_all ON public.external_quote_services FOR ALL TO authenticated
USING (EXISTS (SELECT 1 FROM public.external_quotes q WHERE q.id = external_quote_id
  AND (q.created_by = auth.uid() OR is_admin_or_financial(auth.uid()))))
WITH CHECK (EXISTS (SELECT 1 FROM public.external_quotes q WHERE q.id = external_quote_id
  AND (q.created_by = auth.uid() OR is_admin_or_financial(auth.uid()))));

CREATE TRIGGER trg_eqs_updated BEFORE UPDATE ON public.external_quote_services
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- 8. Conversion function
CREATE OR REPLACE FUNCTION public.convert_external_quote_to_so(_quote_id uuid)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  q public.external_quotes%ROWTYPE;
  l public.external_quote_leads%ROWTYPE;
  v_client_id uuid;
  v_vessel_id uuid;
  v_so_id uuid;
  v_so_number text;
BEGIN
  IF NOT is_admin_or_financial(auth.uid()) THEN
    RAISE EXCEPTION 'Apenas Admin/Financeiro podem converter orÃ§amentos.';
  END IF;

  SELECT * INTO q FROM public.external_quotes WHERE id = _quote_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'OrÃ§amento nÃ£o encontrado.'; END IF;
  IF q.status = 'converted' THEN RAISE EXCEPTION 'OrÃ§amento jÃ¡ convertido (OS %).', q.converted_service_order_id; END IF;
  IF q.status NOT IN ('approved','submitted') THEN RAISE EXCEPTION 'OrÃ§amento precisa estar aprovado.'; END IF;

  -- Resolve client (promote lead if needed)
  v_client_id := q.client_id;
  IF v_client_id IS NULL AND q.lead_id IS NOT NULL THEN
    SELECT * INTO l FROM public.external_quote_leads WHERE id = q.lead_id;
    IF l.promoted_client_id IS NOT NULL THEN
      v_client_id := l.promoted_client_id;
    ELSE
      INSERT INTO public.clients (
        type, full_name_or_company_name, cpf_cnpj, phone, whatsapp, email,
        address_line_1, address_line_2, city, state, postal_code, country, notes
      ) VALUES (
        l.type, l.full_name_or_company_name, l.cpf_cnpj, l.phone, l.whatsapp, l.email,
        l.address_line_1, l.address_line_2, l.city, l.state, l.postal_code, l.country,
        COALESCE(l.notes,'') || E'\n[Promovido de lead externo]'
      ) RETURNING id INTO v_client_id;

      UPDATE public.external_quote_leads
      SET promoted_client_id = v_client_id, promoted_at = now()
      WHERE id = l.id;
    END IF;
  END IF;

  IF v_client_id IS NULL THEN RAISE EXCEPTION 'NÃ£o foi possÃ­vel resolver o cliente.'; END IF;

  -- Resolve vessel (create from lead if needed)
  v_vessel_id := q.vessel_id;
  IF v_vessel_id IS NULL AND q.lead_id IS NOT NULL AND l.boat_name IS NOT NULL THEN
    INSERT INTO public.vessels (
      client_id, boat_name, manufacturer, model, year, length_feet, current_marina_name_snapshot
    ) VALUES (
      v_client_id, l.boat_name, COALESCE(l.boat_manufacturer,''), COALESCE(l.boat_model,''),
      l.boat_year, COALESCE(l.boat_length_feet,0), l.marina_name
    ) RETURNING id INTO v_vessel_id;
  END IF;

  IF v_vessel_id IS NULL THEN RAISE EXCEPTION 'EmbarcaÃ§Ã£o obrigatÃ³ria para criar OS.'; END IF;

  -- Generate OS number
  v_so_number := 'OS-' || to_char(now(),'YYYYMMDD') || '-' || substr(gen_random_uuid()::text,1,6);

  -- Create service order
  INSERT INTO public.service_orders (
    service_order_number, client_id, vessel_id, marina_id, status, priority,
    service_type, problem_description, initial_findings, customer_visible_report,
    internal_notes, hourly_rate, estimated_hours, labor_cost_total,
    travel_distance_km, travel_cost_per_km, travel_cost_total,
    parts_cost_total, subcontract_cost_total, discount_amount, tax_amount,
    grand_total, currency, quote_validity_days, quote_validity_date,
    payment_conditions, created_by
  ) VALUES (
    v_so_number, v_client_id, v_vessel_id, q.marina_id, 'approved', 'normal',
    q.service_type, q.problem_description, q.initial_findings, q.customer_visible_report,
    COALESCE(q.internal_notes,'') || E'\n[Convertido do orÃ§amento externo ' || q.quote_number || ']',
    q.hourly_rate, q.estimated_hours, q.labor_cost_total,
    q.travel_distance_km, q.travel_cost_per_km, q.travel_cost_total,
    q.parts_cost_total, q.subcontract_cost_total, q.discount_amount, q.tax_amount,
    q.grand_total, q.currency, q.quote_validity_days, q.quote_validity_date,
    q.payment_conditions, auth.uid()
  ) RETURNING id INTO v_so_id;

  -- Copy parts
  INSERT INTO public.service_order_parts (
    service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
    currency_snapshot, line_total_cost, line_total_sale, warranty_days, notes
  )
  SELECT v_so_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
         currency_snapshot, line_total_cost, line_total_sale, warranty_days, notes
  FROM public.external_quote_parts WHERE external_quote_id = q.id AND product_id IS NOT NULL;

  -- Copy services
  INSERT INTO public.service_order_services (
    service_order_id, service_id, service_name_snapshot, description_snapshot,
    billing_unit_snapshot, quantity, unit_price_snapshot, line_total, warranty_days, notes
  )
  SELECT v_so_id, service_id, service_name_snapshot, description_snapshot,
         billing_unit_snapshot, quantity, unit_price_snapshot, line_total, warranty_days, notes
  FROM public.external_quote_services WHERE external_quote_id = q.id;

  -- Mark quote as converted
  UPDATE public.external_quotes
  SET status = 'converted',
      converted_service_order_id = v_so_id,
      converted_at = now(),
      client_id = v_client_id,
      vessel_id = v_vessel_id,
      reviewed_by = COALESCE(reviewed_by, auth.uid()),
      reviewed_at = COALESCE(reviewed_at, now())
  WHERE id = q.id;

  -- Audit
  INSERT INTO public.audit_log (table_name, record_id, action, new_value, reason, triggered_by_table, triggered_by_id, changed_by)
  VALUES ('service_orders', v_so_id, 'create_from_external_quote',
          jsonb_build_object('service_order_number', v_so_number, 'external_quote_id', q.id),
          'Convertido do orÃ§amento externo ' || q.quote_number,
          'external_quotes', q.id, auth.uid()::text);

  RETURN v_so_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.convert_external_quote_to_so(_quote_id uuid)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  q public.external_quotes%ROWTYPE;
  l public.external_quote_leads%ROWTYPE;
  v_client_id uuid;
  v_vessel_id uuid;
  v_so_id uuid;
  v_so_number text;
BEGIN
  IF NOT is_admin_or_financial(auth.uid()) THEN
    RAISE EXCEPTION 'Apenas Admin/Financeiro podem converter orÃ§amentos.';
  END IF;

  SELECT * INTO q FROM public.external_quotes WHERE id = _quote_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'OrÃ§amento nÃ£o encontrado.'; END IF;
  IF q.status = 'converted' THEN RAISE EXCEPTION 'OrÃ§amento jÃ¡ convertido (OS %).', q.converted_service_order_id; END IF;
  IF q.status NOT IN ('approved','submitted') THEN RAISE EXCEPTION 'OrÃ§amento precisa estar aprovado.'; END IF;

  v_client_id := q.client_id;
  IF v_client_id IS NULL AND q.lead_id IS NOT NULL THEN
    SELECT * INTO l FROM public.external_quote_leads WHERE id = q.lead_id;
    IF l.promoted_client_id IS NOT NULL THEN
      v_client_id := l.promoted_client_id;
    ELSE
      INSERT INTO public.clients (
        type, full_name_or_company_name, cpf_cnpj, phone, whatsapp, email,
        address_line_1, address_line_2, city, state, postal_code, country, notes
      ) VALUES (
        l.type, l.full_name_or_company_name, l.cpf_cnpj, l.phone, l.whatsapp, l.email,
        l.address_line_1, l.address_line_2, l.city, l.state, l.postal_code, l.country,
        COALESCE(l.notes,'') || E'\n[Promovido de lead externo]'
      ) RETURNING id INTO v_client_id;

      UPDATE public.external_quote_leads
      SET promoted_client_id = v_client_id, promoted_at = now()
      WHERE id = l.id;
    END IF;
  END IF;

  IF v_client_id IS NULL THEN RAISE EXCEPTION 'NÃ£o foi possÃ­vel resolver o cliente.'; END IF;

  v_vessel_id := q.vessel_id;
  IF v_vessel_id IS NULL AND q.lead_id IS NOT NULL AND l.boat_name IS NOT NULL THEN
    INSERT INTO public.vessels (
      client_id, boat_name, manufacturer, model, year, length_feet, current_marina_name_snapshot
    ) VALUES (
      v_client_id, l.boat_name, COALESCE(l.boat_manufacturer,''), COALESCE(l.boat_model,''),
      l.boat_year, COALESCE(l.boat_length_feet,0), l.marina_name
    ) RETURNING id INTO v_vessel_id;
  END IF;

  IF v_vessel_id IS NULL THEN RAISE EXCEPTION 'EmbarcaÃ§Ã£o obrigatÃ³ria para criar OS.'; END IF;

  v_so_number := 'OS-' || to_char(now(),'YYYYMMDD') || '-' || substr(gen_random_uuid()::text,1,6);

  INSERT INTO public.service_orders (
    service_order_number, client_id, vessel_id, marina_id, status, priority,
    service_type, problem_description, initial_findings, customer_visible_report,
    internal_notes, hourly_rate, estimated_hours, labor_cost_total,
    travel_distance_km, travel_cost_per_km, travel_cost_total,
    parts_cost_total, subcontract_cost_total, discount_amount, tax_amount,
    grand_total, currency, quote_validity_days, quote_validity_date,
    payment_conditions, created_by
  ) VALUES (
    v_so_number, v_client_id, v_vessel_id, q.marina_id, 'approved', 'normal',
    q.service_type, q.problem_description, q.initial_findings, q.customer_visible_report,
    COALESCE(q.internal_notes,'') || E'\n[Convertido do orÃ§amento externo ' || q.quote_number || ']',
    q.hourly_rate, q.estimated_hours, q.labor_cost_total,
    q.travel_distance_km, q.travel_cost_per_km, q.travel_cost_total,
    q.parts_cost_total, q.subcontract_cost_total, q.discount_amount, q.tax_amount,
    q.grand_total, q.currency, q.quote_validity_days, q.quote_validity_date,
    q.payment_conditions, auth.uid()
  ) RETURNING id INTO v_so_id;

  INSERT INTO public.service_order_parts (
    service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
    currency_snapshot, line_total_cost, line_total_sale, warranty_days, notes
  )
  SELECT v_so_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
         currency_snapshot, line_total_cost, line_total_sale, warranty_days, notes
  FROM public.external_quote_parts WHERE external_quote_id = q.id AND product_id IS NOT NULL;

  INSERT INTO public.service_order_services (
    service_order_id, service_id, service_name_snapshot, description_snapshot,
    billing_unit_snapshot, quantity, unit_price_snapshot, line_total, warranty_days, notes
  )
  SELECT v_so_id, service_id, service_name_snapshot, description_snapshot,
         billing_unit_snapshot, quantity, unit_price_snapshot, line_total, warranty_days, notes
  FROM public.external_quote_services WHERE external_quote_id = q.id;

  UPDATE public.external_quotes
  SET status = 'converted',
      converted_service_order_id = v_so_id,
      converted_at = now(),
      client_id = v_client_id,
      vessel_id = v_vessel_id,
      reviewed_by = COALESCE(reviewed_by, auth.uid()),
      reviewed_at = COALESCE(reviewed_at, now())
  WHERE id = q.id;

  INSERT INTO public.audit_log (table_name, record_id, action, new_value, reason, triggered_by_table, triggered_by_id, changed_by)
  VALUES ('service_orders', v_so_id, 'lead_converted',
          jsonb_build_object('service_order_number', v_so_number, 'external_quote_id', q.id, 'client_id', v_client_id, 'vessel_id', v_vessel_id),
          'Convertido do orÃ§amento externo ' || q.quote_number,
          'external_quotes', q.id, COALESCE(auth.uid()::text,'system'));

  RETURN v_so_id;
END;
$$;
CREATE OR REPLACE FUNCTION public.deduct_stock_on_os_complete()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed' THEN
    UPDATE products p
    SET stock_quantity = GREATEST(0, p.stock_quantity - sop.quantity)
    FROM service_order_parts sop
    WHERE sop.service_order_id = NEW.id
      AND sop.product_id = p.id;

    INSERT INTO inventory_movements (
      product_id, movement_type, quantity_delta,
      reference_type, reference_id, notes, unit_cost_snapshot
    )
    SELECT
      sop.product_id,
      'service_order_usage',
      -sop.quantity,
      'service_order',
      NEW.id,
      'Baixa automÃ¡tica ao concluir OS ' || NEW.service_order_number,
      sop.unit_cost_snapshot
    FROM service_order_parts sop
    WHERE sop.service_order_id = NEW.id
      AND sop.product_id IS NOT NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_deduct_stock_on_os_complete ON public.service_orders;

CREATE TRIGGER trg_deduct_stock_on_os_complete
  AFTER UPDATE ON public.service_orders
  FOR EACH ROW EXECUTE FUNCTION public.deduct_stock_on_os_complete();
ALTER TABLE public.service_order_services
  ADD COLUMN IF NOT EXISTS warranty_months integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS warranty_expires_at date;

ALTER TABLE public.service_order_parts
  ADD COLUMN IF NOT EXISTS warranty_months integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS warranty_expires_at date,
  ADD COLUMN IF NOT EXISTS serial_number text;

CREATE OR REPLACE FUNCTION public.calc_warranty_expiry()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.warranty_months > 0 THEN
    NEW.warranty_expires_at := CURRENT_DATE + (NEW.warranty_months || ' months')::interval;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_warranty_services ON public.service_order_services;
CREATE TRIGGER trg_warranty_services
  BEFORE INSERT OR UPDATE ON public.service_order_services
  FOR EACH ROW EXECUTE FUNCTION public.calc_warranty_expiry();

DROP TRIGGER IF EXISTS trg_warranty_parts ON public.service_order_parts;
CREATE TRIGGER trg_warranty_parts
  BEFORE INSERT OR UPDATE ON public.service_order_parts
  FOR EACH ROW EXECUTE FUNCTION public.calc_warranty_expiry();
ALTER TABLE service_order_services
  ADD COLUMN IF NOT EXISTS started_at timestamptz,
  ADD COLUMN IF NOT EXISTS finished_at timestamptz,
  ADD COLUMN IF NOT EXISTS elapsed_minutes integer DEFAULT 0;
CREATE TABLE IF NOT EXISTS public.service_order_photos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  service_order_id uuid NOT NULL REFERENCES public.service_orders(id) ON DELETE CASCADE,
  uploaded_by uuid REFERENCES public.app_users(id),
  storage_path text NOT NULL,
  public_url text NOT NULL,
  caption text,
  photo_type text NOT NULL DEFAULT 'progress'
    CHECK (photo_type IN ('before','progress','after','problem'))
);

CREATE INDEX IF NOT EXISTS idx_so_photos_order ON public.service_order_photos(service_order_id);

ALTER TABLE public.service_order_photos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "so_photos_auth" ON public.service_order_photos
  FOR ALL
  TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

INSERT INTO storage.buckets (id, name, public)
VALUES ('service-order-photos', 'service-order-photos', true)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "so_photos_bucket_select" ON storage.objects
  FOR SELECT TO public
  USING (bucket_id = 'service-order-photos');

CREATE POLICY "so_photos_bucket_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'service-order-photos');

CREATE POLICY "so_photos_bucket_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'service-order-photos');

CREATE POLICY "so_photos_bucket_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'service-order-photos');
CREATE TABLE IF NOT EXISTS public.push_subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  user_id uuid NOT NULL REFERENCES public.app_users(id) ON DELETE CASCADE,
  endpoint text NOT NULL UNIQUE,
  p256dh text NOT NULL,
  auth text NOT NULL,
  user_agent text
);

ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "push_own" ON public.push_subscriptions
  FOR ALL
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());
-- purchase_orders.sql â€” idempotente

-- 1. Tabela principal
CREATE TABLE IF NOT EXISTS purchase_orders (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  po_number        text NOT NULL UNIQUE,
  status           text NOT NULL DEFAULT 'draft'
                     CHECK (status IN ('draft','sent','partial','received','cancelled')),
  supplier_id      uuid REFERENCES suppliers(id) ON DELETE SET NULL,
  service_order_id uuid REFERENCES service_orders(id) ON DELETE SET NULL,
  expected_date    date,
  received_date    date,
  notes            text,
  total_amount     numeric(12,2) NOT NULL DEFAULT 0,
  created_by       text NOT NULL DEFAULT 'sistema',
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

-- 2. Itens
CREATE TABLE IF NOT EXISTS purchase_order_items (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  purchase_order_id uuid NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
  product_id        uuid REFERENCES products(id) ON DELETE SET NULL,
  description       text NOT NULL,
  quantity          numeric(10,3) NOT NULL DEFAULT 1,
  unit_cost         numeric(12,2) NOT NULL DEFAULT 0,
  received_qty      numeric(10,3) NOT NULL DEFAULT 0,
  created_at        timestamptz NOT NULL DEFAULT now()
);

-- 3. updated_at trigger
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

DROP TRIGGER IF EXISTS trg_po_updated_at ON purchase_orders;
CREATE TRIGGER trg_po_updated_at
  BEFORE UPDATE ON purchase_orders
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 4. RLS
ALTER TABLE purchase_orders      ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_order_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "auth_all_po"  ON purchase_orders;
DROP POLICY IF EXISTS "auth_all_poi" ON purchase_order_items;
CREATE POLICY "auth_all_po"  ON purchase_orders      FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all_poi" ON purchase_order_items FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 5. Recalc total function
CREATE OR REPLACE FUNCTION recalc_po_total(p_po_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  UPDATE purchase_orders
  SET total_amount = (
    SELECT COALESCE(SUM(quantity * unit_cost), 0)
    FROM purchase_order_items
    WHERE purchase_order_id = p_po_id
  )
  WHERE id = p_po_id;
END;
$$;

CREATE OR REPLACE FUNCTION trg_poi_recalc_total()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM recalc_po_total(OLD.purchase_order_id);
  ELSE
    PERFORM recalc_po_total(NEW.purchase_order_id);
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_poi_total ON purchase_order_items;
CREATE TRIGGER trg_poi_total
  AFTER INSERT OR UPDATE OR DELETE ON purchase_order_items
  FOR EACH ROW EXECUTE FUNCTION trg_poi_recalc_total();
-- Add 'service_order_usage' to the inventory_movements.movement_type constraint.
-- The trigger trg_deduct_stock_on_os_complete uses this value but it was
-- missing from the allowed list, causing a check constraint violation on OS
-- completion. Also drop the trigger to prevent double stock deduction
-- (stock is already deducted by the app when parts are added to an OS).

ALTER TABLE public.inventory_movements
  DROP CONSTRAINT IF EXISTS inventory_movements_movement_type_check;

ALTER TABLE public.inventory_movements
  ADD CONSTRAINT inventory_movements_movement_type_check
  CHECK (movement_type IN (
    'purchase', 'manual_adjustment', 'service_usage', 'service_order_usage',
    'return', 'transfer', 'manual_add', 'manual_remove', 'import', 'fiscal_note_entry'
  ));

-- Drop the trigger that double-deducts stock on OS completion.
-- Stock deduction is handled at part-add time by the application layer.
DROP TRIGGER IF EXISTS trg_deduct_stock_on_os_complete ON public.service_orders;
-- Creates an RPC to register a payment and automatically update the parent's balance safely inside a transaction.
-- This prevents race conditions where two simultaneous payments could overwrite each other's balance calculations.

CREATE OR REPLACE FUNCTION register_payment_and_update_balance(
  p_receivable_id UUID,
  p_payable_id UUID,
  p_amount NUMERIC,
  p_payment_date DATE,
  p_payment_method TEXT,
  p_installments INTEGER,
  p_card_fee_percent NUMERIC,
  p_net_amount NUMERIC,
  p_notes TEXT
) RETURNS JSON AS $$
DECLARE
  v_payment_id UUID;
  v_total_paid NUMERIC;
  v_original_amount NUMERIC;
  v_new_balance NUMERIC;
  v_new_status TEXT;
  v_table_name TEXT;
  v_parent_id UUID;
BEGIN
  -- 1. Insert the payment record
  INSERT INTO public.payments (
    receivable_id, payable_id, amount, payment_date, payment_method, 
    installments, card_fee_percent, net_amount, notes, status
  ) VALUES (
    p_receivable_id, p_payable_id, p_amount, p_payment_date, p_payment_method, 
    p_installments, p_card_fee_percent, p_net_amount, p_notes, 'confirmed'
  ) RETURNING id INTO v_payment_id;

  -- Determine which parent table we are updating
  IF p_receivable_id IS NOT NULL THEN
    v_table_name := 'receivables';
    v_parent_id := p_receivable_id;
  ELSIF p_payable_id IS NOT NULL THEN
    v_table_name := 'payables';
    v_parent_id := p_payable_id;
  ELSE
    RAISE EXCEPTION 'Must provide either receivable_id or payable_id';
  END IF;

  -- 2. Calculate the new total paid (Locking isn't strictly needed for SUM if we are the only transaction committing right now,
  -- but PostgreSQL handles this consistently in READ COMMITTED mode for sequential inserts).
  SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
  FROM public.payments
  WHERE (receivable_id = p_receivable_id OR payable_id = p_payable_id)
    AND status = 'confirmed';

  -- 3. Lock the parent row and get its original amount
  IF v_table_name = 'receivables' THEN
    SELECT amount INTO v_original_amount
    FROM public.receivables
    WHERE id = v_parent_id
    FOR UPDATE;
  ELSE
    SELECT amount INTO v_original_amount
    FROM public.payables
    WHERE id = v_parent_id
    FOR UPDATE;
  END IF;

  -- 4. Calculate new balance and status
  v_new_balance := GREATEST(0, v_original_amount - v_total_paid);
  
  IF v_total_paid >= v_original_amount THEN
    v_new_status := 'paid';
  ELSIF v_total_paid > 0 THEN
    v_new_status := 'partially_paid';
  ELSE
    v_new_status := 'pending';
  END IF;

  -- 5. Update the parent row
  IF v_table_name = 'receivables' THEN
    UPDATE public.receivables
    SET paid_amount = v_total_paid,
        balance_amount = v_new_balance,
        status = v_new_status
    WHERE id = v_parent_id;
  ELSE
    UPDATE public.payables
    SET paid_amount = v_total_paid,
        balance_amount = v_new_balance,
        status = v_new_status
    WHERE id = v_parent_id;
  END IF;

  -- Return the inserted payment ID and new balances
  RETURN json_build_object(
    'payment_id', v_payment_id,
    'total_paid', v_total_paid,
    'balance_amount', v_new_balance,
    'status', v_new_status
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
-- Creates an atomic RPC for service order cancellation.
-- All operations (stock restore, receivable cancellation, payment cancellation,
-- bank unreconciliation) happen inside a SINGLE PostgreSQL transaction.
-- If ANY step fails, ALL changes are rolled back, preventing partial/zombie states.

CREATE OR REPLACE FUNCTION cancel_service_order_cascade(
  p_service_order_id UUID,
  p_reason TEXT
) RETURNS JSON AS $$
DECLARE
  v_part RECORD;
  v_receivable RECORD;
  v_payment RECORD;
  v_parts_restored INT := 0;
  v_receivables_cancelled INT := 0;
  v_payments_cancelled INT := 0;
  v_now TIMESTAMPTZ := NOW();
BEGIN
  -- â”€â”€ 1. Restore stock for all parts in this SO â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  FOR v_part IN
    SELECT id, product_id, quantity, unit_cost_snapshot
    FROM public.service_order_parts
    WHERE service_order_id = p_service_order_id
  LOOP
    UPDATE public.products
    SET stock_quantity = stock_quantity + v_part.quantity
    WHERE id = v_part.product_id;

    INSERT INTO public.inventory_movements
      (product_id, movement_type, quantity_delta, reference_type, reference_id, unit_cost_snapshot)
    VALUES
      (v_part.product_id, 'return', v_part.quantity, 'service_order_cancel', p_service_order_id, v_part.unit_cost_snapshot);

    v_parts_restored := v_parts_restored + 1;
  END LOOP;

  -- â”€â”€ 2. Cancel linked receivables and their confirmed payments â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  FOR v_receivable IN
    SELECT id, status
    FROM public.receivables
    WHERE service_order_id = p_service_order_id
  LOOP
    FOR v_payment IN
      SELECT id, amount
      FROM public.payments
      WHERE receivable_id = v_receivable.id
        AND status = 'confirmed'
    LOOP
      -- Cancel the payment
      UPDATE public.payments
      SET status = 'cancelled',
          cancelled_at = v_now,
          cancellation_reason = p_reason
      WHERE id = v_payment.id;

      -- Undo bank reconciliation
      UPDATE public.bank_transactions
      SET reconciled = FALSE,
          reconciled_payment_id = NULL
      WHERE reconciled_payment_id = v_payment.id;

      v_payments_cancelled := v_payments_cancelled + 1;
    END LOOP;

    -- Cancel the receivable itself
    UPDATE public.receivables
    SET status = 'cancelled',
        balance_amount = 0
    WHERE id = v_receivable.id;

    v_receivables_cancelled := v_receivables_cancelled + 1;
  END LOOP;

  -- â”€â”€ 3. Mark the service order as cancelled â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  UPDATE public.service_orders
  SET status = 'cancelled',
      cancelled_at = v_now,
      cancellation_reason = p_reason
  WHERE id = p_service_order_id;

  RETURN json_build_object(
    'success', TRUE,
    'parts_restored', v_parts_restored,
    'receivables_cancelled', v_receivables_cancelled,
    'payments_cancelled', v_payments_cancelled
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
CREATE OR REPLACE FUNCTION public.cancel_service_order_cascade(
  p_service_order_id UUID,
  p_reason TEXT
) RETURNS JSON AS $$
DECLARE
  v_part RECORD;
  v_receivable RECORD;
  v_payment RECORD;
  v_parts_restored INT := 0;
  v_receivables_cancelled INT := 0;
  v_payments_cancelled INT := 0;
  v_now TIMESTAMPTZ := NOW();
BEGIN
  FOR v_part IN
    SELECT id, product_id, quantity, unit_cost_snapshot FROM public.service_order_parts WHERE service_order_id = p_service_order_id
  LOOP
    UPDATE public.products SET stock_quantity = stock_quantity + v_part.quantity WHERE id = v_part.product_id;
    INSERT INTO public.inventory_movements (product_id, movement_type, quantity_delta, reference_type, reference_id, unit_cost_snapshot)
    VALUES (v_part.product_id, 'return', v_part.quantity, 'service_order_cancel', p_service_order_id, v_part.unit_cost_snapshot);
    v_parts_restored := v_parts_restored + 1;
  END LOOP;

  FOR v_receivable IN
    SELECT id, status FROM public.receivables WHERE service_order_id = p_service_order_id
  LOOP
    FOR v_payment IN
      SELECT id, amount FROM public.payments WHERE receivable_id = v_receivable.id AND status = 'confirmed'
    LOOP
      UPDATE public.payments SET status = 'cancelled', cancelled_at = v_now, cancellation_reason = p_reason WHERE id = v_payment.id;
      UPDATE public.bank_transactions SET reconciled = FALSE, reconciled_payment_id = NULL WHERE reconciled_payment_id = v_payment.id;
      v_payments_cancelled := v_payments_cancelled + 1;
    END LOOP;
    UPDATE public.receivables SET status = 'cancelled', balance_amount = 0 WHERE id = v_receivable.id;
    v_receivables_cancelled := v_receivables_cancelled + 1;
  END LOOP;

  UPDATE public.service_orders SET status = 'cancelled', cancelled_at = v_now, cancellation_reason = p_reason WHERE id = p_service_order_id;

  RETURN json_build_object('success', TRUE, 'parts_restored', v_parts_restored, 'receivables_cancelled', v_receivables_cancelled, 'payments_cancelled', v_payments_cancelled);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
CREATE OR REPLACE FUNCTION public.register_payment_and_update_balance(
  p_receivable_id UUID,
  p_payable_id UUID,
  p_amount NUMERIC,
  p_payment_date DATE,
  p_payment_method TEXT,
  p_installments INTEGER,
  p_card_fee_percent NUMERIC,
  p_net_amount NUMERIC,
  p_notes TEXT
) RETURNS JSON AS $$
DECLARE
  v_payment_id UUID;
  v_total_paid NUMERIC;
  v_original_amount NUMERIC;
  v_new_balance NUMERIC;
  v_new_status TEXT;
  v_table_name TEXT;
  v_parent_id UUID;
BEGIN
  INSERT INTO public.payments (
    receivable_id, payable_id, amount, payment_date, payment_method, 
    installments, card_fee_percent, net_amount, notes, status
  ) VALUES (
    p_receivable_id, p_payable_id, p_amount, p_payment_date, p_payment_method, 
    p_installments, p_card_fee_percent, p_net_amount, p_notes, 'confirmed'
  ) RETURNING id INTO v_payment_id;

  IF p_receivable_id IS NOT NULL THEN
    v_table_name := 'receivables';
    v_parent_id := p_receivable_id;
  ELSIF p_payable_id IS NOT NULL THEN
    v_table_name := 'payables';
    v_parent_id := p_payable_id;
  ELSE
    RAISE EXCEPTION 'Must provide either receivable_id or payable_id';
  END IF;

  SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
  FROM public.payments
  WHERE (receivable_id = p_receivable_id OR payable_id = p_payable_id)
    AND status = 'confirmed';

  IF v_table_name = 'receivables' THEN
    SELECT amount INTO v_original_amount
    FROM public.receivables
    WHERE id = v_parent_id
    FOR UPDATE;
  ELSE
    SELECT amount INTO v_original_amount
    FROM public.payables
    WHERE id = v_parent_id
    FOR UPDATE;
  END IF;

  v_new_balance := GREATEST(0, v_original_amount - v_total_paid);
  
  IF v_total_paid >= v_original_amount THEN
    v_new_status := 'paid';
  ELSIF v_total_paid > 0 THEN
    v_new_status := 'partially_paid';
  ELSE
    v_new_status := 'pending';
  END IF;

  IF v_table_name = 'receivables' THEN
    UPDATE public.receivables
    SET paid_amount = v_total_paid,
        balance_amount = v_new_balance,
        status = v_new_status
    WHERE id = v_parent_id;
  ELSE
    UPDATE public.payables
    SET paid_amount = v_total_paid,
        balance_amount = v_new_balance,
        status = v_new_status
    WHERE id = v_parent_id;
  END IF;

  RETURN json_build_object(
    'payment_id', v_payment_id,
    'total_paid', v_total_paid,
    'balance_amount', v_new_balance,
    'status', v_new_status
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
-- Migration: adiciona suporte a target_kind = 'manual' na tabela whatsapp_scheduled_sends
-- Permite agendar mensagens avulsas sem vincular a OS ou recebÃ­vel

-- 1. Remove a constraint antiga que exige service_order_id ou receivable_id
ALTER TABLE whatsapp_scheduled_sends
  DROP CONSTRAINT IF EXISTS chk_target;

-- 2. Remove o CHECK inline do target_kind original (recriado na nova constraint)
-- (a constraint inline jÃ¡ foi dropada com o DROP CONSTRAINT acima em alguns Postgres,
--  mas fazemos o ALTER COLUMN para garantir)
ALTER TABLE whatsapp_scheduled_sends
  ALTER COLUMN target_kind TYPE text;

-- 3. Recria a constraint permitindo 'manual', 'service_order' e 'receivable'
ALTER TABLE whatsapp_scheduled_sends
  ADD CONSTRAINT chk_target CHECK (
    (target_kind = 'service_order' AND service_order_id IS NOT NULL) OR
    (target_kind = 'receivable'    AND receivable_id    IS NOT NULL) OR
    (target_kind = 'manual')
  );
-- Migration: cria tabela de referÃªncia de APIs e popula com Z-API
-- Objetivo: Reduzir carga de trabalho futura ao ter mapeamento completo da API disponÃ­vel para a IA e sistema.

CREATE TABLE IF NOT EXISTS public.api_references (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider text NOT NULL, -- ex: 'z-api'
  category text NOT NULL, -- ex: 'messages', 'status', 'instance', 'webhooks'
  endpoint_name text NOT NULL,
  http_method text NOT NULL DEFAULT 'POST',
  path text NOT NULL,
  description text,
  payload_example jsonb,
  is_implemented boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(provider, path)
);

-- Habilita RLS
ALTER TABLE public.api_references ENABLE ROW LEVEL SECURITY;
CREATE POLICY "api_references_read_auth" ON public.api_references FOR SELECT TO authenticated USING (true);

-- Popula com as principais funcionalidades da Z-API
INSERT INTO public.api_references (provider, category, endpoint_name, path, description, is_implemented)
VALUES 
  ('z-api', 'messages', 'Send Text', '/send-text', 'Envia mensagem de texto simples.', true),
  ('z-api', 'messages', 'Send Image', '/send-image', 'Envia imagem com legenda opcional.', true),
  ('z-api', 'messages', 'Send Video', '/send-video', 'Envia vÃ­deo com legenda opcional.', false),
  ('z-api', 'messages', 'Send Audio', '/send-audio', 'Envia Ã¡udio (PTT ou arquivo).', false),
  ('z-api', 'messages', 'Send Document', '/send-document/pdf', 'Envia documento PDF.', true),
  ('z-api', 'messages', 'Send Link', '/send-link', 'Envia link com preview customizado.', true),
  ('z-api', 'messages', 'Send Contact', '/send-contact', 'Envia contato (VCard).', false),
  ('z-api', 'messages', 'Send Location', '/send-location', 'Envia localizaÃ§Ã£o geogrÃ¡fica.', false),
  ('z-api', 'status', 'Send Text Status', '/send-text-status', 'Posta texto no Status (Stories).', false),
  ('z-api', 'status', 'Send Image Status', '/send-image-status', 'Posta imagem no Status (Stories).', false),
  ('z-api', 'status', 'Send Video Status', '/send-video-status', 'Posta vÃ­deo no Status (Stories).', false),
  ('z-api', 'instance', 'Get QR Code', '/qr-code', 'ObtÃ©m o QR Code para conexÃ£o.', false),
  ('z-api', 'instance', 'Get Status', '/status', 'Verifica se a instÃ¢ncia estÃ¡ conectada.', false),
  ('z-api', 'instance', 'Restart', '/restart', 'Reinicia a instÃ¢ncia do WhatsApp.', false),
  ('z-api', 'webhooks', 'Set Webhook', '/set-webhook', 'Configura URL de callback.', false),
  ('z-api', 'webhooks', 'Get Webhooks', '/webhooks', 'Lista webhooks configurados.', false);
-- Migration: cria tabela de agendamento de Status (Stories) do WhatsApp via Z-API
-- Objetivo: Permitir que o usuÃ¡rio agende postagens no Status com imagem, vÃ­deo ou texto.

CREATE TABLE IF NOT EXISTS public.whatsapp_status_scheduled (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  content_type text NOT NULL CHECK (content_type IN ('text', 'image', 'video')),
  media_url text, -- URL da mÃ­dia hospedada no Supabase Storage
  text_content text, -- Texto do status ou legenda da mÃ­dia
  background_color text DEFAULT '#000000', -- Para status de texto
  font_type integer DEFAULT 0, -- Ãndice da fonte na Z-API (0 a 5)
  
  scheduled_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'sent', 'failed', 'cancelled')),
  error_message text,
  zapi_message_id text,
  
  created_by uuid REFERENCES public.app_users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Ãndices para performance
CREATE INDEX idx_wss_status_pending ON public.whatsapp_status_scheduled(scheduled_at) WHERE status = 'pending';
CREATE INDEX idx_wss_status_lookup ON public.whatsapp_status_scheduled(status);

-- RLS
ALTER TABLE public.whatsapp_status_scheduled ENABLE ROW LEVEL SECURITY;
CREATE POLICY "whatsapp_status_scheduled_all_auth" ON public.whatsapp_status_scheduled
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Trigger updated_at
CREATE TRIGGER trg_whatsapp_status_scheduled_updated_at
  BEFORE UPDATE ON public.whatsapp_status_scheduled
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- RESTAURAÇÃO DE DADOS VITAIS
INSERT INTO public.app_settings (key, value, description)
VALUES 
  ('zapi_instance_id', '3F1FD3133D825357683E06ABA24BC57F', 'ID da Instância Z-API'),
  ('zapi_token', '20E2744092170E81D5E41938', 'Token da Instância Z-API'),
  ('zapi_client_token', 'F50b1eeec33d14e6fb780852a11fb2db7S', 'Token de Cliente Z-API'),
  ('zapi_test_number', '5547999159654', 'Número para testes de redirecionamento'),
  ('base_latitude', '-26.9189', 'Latitude da Base Náutica'),
  ('base_longitude', '-48.6728', 'Longitude da Base Náutica'),
  ('km_rate', '3.50', 'Valor por KM rodado'),
  ('tech_hour_rate', '200.00', 'Valor da hora técnica'),
  ('gemini_api_key', 'AIzaSyD3BtMc8KPbhPItua6YuoCtjALb4a5HglQ', 'Chave da API do Google Gemini')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

