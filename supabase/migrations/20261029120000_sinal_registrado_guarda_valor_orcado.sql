-- Sinal registrado pela tela (register_deposit_and_convert) guarda o valor orçado e não pega número de outra OS.
--
-- POR QUE: dos três caminhos que convertem orçamento em OS, só este não guardava original_quote_amount
-- (43 das 47 OS convertidas até 28/10/2026 sem ele: o resumo da OS não mostra "orçado R$ X (+diferença)").
-- E trocava ORÇ-→OS- sem conferir se o OS- já era de outra OS. O gatilho do sinal pago e a porta da
-- conversão (agenda, Fase 3) já fazem as duas coisas. O resto da função fica igual (copiado de produção).
--
-- Sem dados: não preenche as 43 antigas (o total de hoje não é o orçado de então).
-- Prova: supabase/tests/sinal_registrado_guarda_valor_orcado.sql

CREATE OR REPLACE FUNCTION public.register_deposit_and_convert(p_service_order_id uuid, p_amount numeric, p_payment_date date, p_payment_method text, p_card_fee_percent numeric DEFAULT 0, p_notes text DEFAULT NULL::text, p_balance_installments jsonb DEFAULT NULL::jsonb, p_create_collections boolean DEFAULT true)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_receivable_id UUID;
  v_payment_id    UUID;
  v_net_amount    NUMERIC;
  v_so_number     TEXT;
  v_client_id     UUID;
  v_client_name   TEXT;
  v_client_phone  TEXT;
  v_client_wa     TEXT;
  v_inst          JSONB;
  v_bal_id        UUID;
  v_bal_count     INT := 0;
  v_existing_bal  INT;
BEGIN
  -- Técnico não registra sinal nem converte orçamento (chamada sem usuário = sistema).
  IF auth.uid() IS NOT NULL AND EXISTS (SELECT 1 FROM public.app_users WHERE id = auth.uid() AND role = 'technician') THEN
    RAISE EXCEPTION 'Técnico não registra sinal nem converte orçamento.' USING ERRCODE = '42501';
  END IF;

  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Valor do sinal deve ser maior que zero';
  END IF;

  SELECT so.service_order_number, so.client_id, c.name, c.phone, c.whatsapp
  INTO v_so_number, v_client_id, v_client_name, v_client_phone, v_client_wa
  FROM public.service_orders so
  LEFT JOIN public.clients c ON c.id = so.client_id
  WHERE so.id = p_service_order_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ordem de serviço não encontrada: %', p_service_order_id;
  END IF;

  v_net_amount := p_amount - (p_amount * COALESCE(p_card_fee_percent, 0) / 100.0);

  INSERT INTO public.receivables (
    service_order_id, client_id, description, issue_date, due_date,
    amount, balance_amount, paid_amount, status, is_deposit
  ) VALUES (
    p_service_order_id, v_client_id, 'Sinal — ' || COALESCE(v_so_number, ''),
    p_payment_date, p_payment_date, p_amount, 0, p_amount, 'paid', true
  ) RETURNING id INTO v_receivable_id;

  INSERT INTO public.payments (
    receivable_id, amount, payment_date, payment_method,
    card_fee_percent, net_amount, notes, status
  ) VALUES (
    v_receivable_id, p_amount, p_payment_date, p_payment_method,
    COALESCE(p_card_fee_percent, 0), v_net_amount, p_notes, 'confirmed'
  ) RETURNING id INTO v_payment_id;

  SELECT COUNT(*) INTO v_existing_bal
  FROM public.receivables
  WHERE service_order_id = p_service_order_id AND NOT is_deposit AND status <> 'cancelled';

  IF v_existing_bal = 0
     AND p_balance_installments IS NOT NULL
     AND jsonb_typeof(p_balance_installments) = 'array' THEN
    FOR v_inst IN SELECT * FROM jsonb_array_elements(p_balance_installments) LOOP
      IF COALESCE((v_inst->>'amount')::numeric, 0) > 0 THEN
        INSERT INTO public.receivables (
          service_order_id, client_id, description, issue_date, due_date,
          amount, balance_amount, paid_amount, status, is_deposit, reminder_sent_at, due_on_completion
        ) VALUES (
          p_service_order_id, v_client_id,
          COALESCE(v_inst->>'description', 'Saldo — ' || COALESCE(v_so_number, '')),
          p_payment_date, (v_inst->>'due_date')::date,
          (v_inst->>'amount')::numeric, (v_inst->>'amount')::numeric, 0, 'pending', false,
          now(), COALESCE((v_inst->>'due_on_completion')::boolean, false)
        ) RETURNING id INTO v_bal_id;
        v_bal_count := v_bal_count + 1;

        IF p_create_collections THEN
          INSERT INTO public.collections (
            service_order_id, receivable_id, client_id, amount, due_date, status,
            description, contact_name, phone, contact_whatsapp, auto_rule_enabled
          ) VALUES (
            p_service_order_id, v_bal_id, v_client_id, (v_inst->>'amount')::numeric,
            (v_inst->>'due_date')::date, 'pending',
            COALESCE(v_inst->>'description', 'Saldo'), v_client_name, v_client_phone, v_client_wa, false
          );
        END IF;
      END IF;
    END LOOP;
  END IF;

  -- 29/10/2026: como o gatilho do sinal pago (handle_quote_deposit_payment) e a porta da conversão:
  -- o número só troca o prefixo se o "OS-" não for de outra OS (o sinal nunca quebra por isso), e o
  -- valor orçado fica guardado. Antes ficava vazio aqui, e o resumo da OS perdia o "orçado R$ X".
  UPDATE public.service_orders so
  SET
    status = CASE WHEN so.status = 'draft' THEN 'open' ELSE so.status END,
    converted_to_os_at = CASE WHEN so.status = 'draft' AND so.converted_to_os_at IS NULL THEN NOW() ELSE so.converted_to_os_at END,
    service_order_number = CASE
      WHEN so.status = 'draft' AND so.service_order_number LIKE 'ORÇ-%'
           AND NOT EXISTS (SELECT 1 FROM public.service_orders o2
                           WHERE o2.service_order_number = 'OS-' || substr(so.service_order_number, 5) AND o2.id <> so.id)
        THEN 'OS-' || substr(so.service_order_number, 5)
      ELSE so.service_order_number
    END,
    original_quote_amount = CASE
      WHEN so.status = 'draft' AND so.converted_to_os_at IS NULL
        THEN COALESCE(so.original_quote_amount, NULLIF(so.grand_total, 0))
      ELSE so.original_quote_amount
    END
  WHERE so.id = p_service_order_id;

  RETURN json_build_object(
    'receivable_id',       v_receivable_id,
    'payment_id',          v_payment_id,
    'net_amount',          v_net_amount,
    'balance_receivables', v_bal_count
  );
END;
$function$
;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261029120000', 'sinal_registrado_guarda_valor_orcado') on conflict (version) do nothing;
