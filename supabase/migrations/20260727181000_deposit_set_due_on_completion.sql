-- register_deposit_and_convert: marca as parcelas de saldo "na entrega" com due_on_completion=true,
-- para o trigger sync_balance_due_on_completion reajustar o vencimento à conclusão real da OS.
-- O diálogo envia due_on_completion por parcela em p_balance_installments (dueBasis='delivery').
CREATE OR REPLACE FUNCTION public.register_deposit_and_convert(
  p_service_order_id     UUID,
  p_amount               NUMERIC,
  p_payment_date         DATE,
  p_payment_method       TEXT,
  p_card_fee_percent     NUMERIC DEFAULT 0,
  p_notes                TEXT    DEFAULT NULL,
  p_balance_installments JSONB   DEFAULT NULL,
  p_create_collections   BOOLEAN DEFAULT true
) RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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

  UPDATE public.service_orders
  SET
    status = CASE WHEN status = 'draft' THEN 'open' ELSE status END,
    converted_to_os_at = CASE WHEN status = 'draft' AND converted_to_os_at IS NULL THEN NOW() ELSE converted_to_os_at END,
    service_order_number = CASE
      WHEN status = 'draft' AND service_order_number LIKE 'ORÇ-%'
        THEN REPLACE(service_order_number, 'ORÇ-', 'OS-')
      ELSE service_order_number
    END
  WHERE id = p_service_order_id;

  RETURN json_build_object(
    'receivable_id',       v_receivable_id,
    'payment_id',          v_payment_id,
    'net_amount',          v_net_amount,
    'balance_receivables', v_bal_count
  );
END;
$$;
