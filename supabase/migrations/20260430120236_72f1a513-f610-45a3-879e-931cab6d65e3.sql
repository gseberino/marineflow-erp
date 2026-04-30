
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
    RAISE EXCEPTION 'Apenas Admin/Financeiro podem converter orçamentos.';
  END IF;

  SELECT * INTO q FROM public.external_quotes WHERE id = _quote_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Orçamento não encontrado.'; END IF;
  IF q.status = 'converted' THEN RAISE EXCEPTION 'Orçamento já convertido (OS %).', q.converted_service_order_id; END IF;
  IF q.status NOT IN ('approved','submitted') THEN RAISE EXCEPTION 'Orçamento precisa estar aprovado.'; END IF;

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

  IF v_client_id IS NULL THEN RAISE EXCEPTION 'Não foi possível resolver o cliente.'; END IF;

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

  IF v_vessel_id IS NULL THEN RAISE EXCEPTION 'Embarcação obrigatória para criar OS.'; END IF;

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
    COALESCE(q.internal_notes,'') || E'\n[Convertido do orçamento externo ' || q.quote_number || ']',
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
          'Convertido do orçamento externo ' || q.quote_number,
          'external_quotes', q.id, auth.uid()::text);

  RETURN v_so_id;
END;
$$;
