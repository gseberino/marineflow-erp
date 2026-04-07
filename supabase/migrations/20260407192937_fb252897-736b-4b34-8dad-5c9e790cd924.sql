
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
-- 10. inventory_movements (immutable log — no updated_at)
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
  ('display_currency', 'BRL', 'Moeda de exibição padrão'),
  ('language', 'pt-BR', 'Idioma padrão'),
  ('company_name', 'MarineFlow', 'Nome da empresa'),
  ('company_address', 'Rua José Domingos Machado, 230, Cidade Nova, Itajaí - SC', 'Endereço da base operacional'),
  ('travel_base_lat', '-26.9189', 'Latitude da base para cálculo de deslocamento'),
  ('travel_base_lng', '-48.6728', 'Longitude da base para cálculo de deslocamento'),
  ('travel_cost_per_km', '3.50', 'Custo por km de deslocamento em BRL'),
  ('card_fee_percent', '3.5', 'Taxa média de cartão de crédito (%)');

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
