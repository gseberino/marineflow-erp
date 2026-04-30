
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
    COALESCE(q.internal_notes,'') || E'\n[Convertido do orçamento externo ' || q.quote_number || ']',
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
          'Convertido do orçamento externo ' || q.quote_number,
          'external_quotes', q.id, COALESCE(auth.uid()::text,'system'));

  RETURN v_so_id;
END;
$$;
