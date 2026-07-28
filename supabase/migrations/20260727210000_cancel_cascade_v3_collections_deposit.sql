-- cancel_service_order_cascade v3:
--  (#1) cancela também as COBRANÇAS (collections) vinculadas — uma OS cancelada não pode ficar com
--       cobrança "pendente" na lista (risco de cobrar cliente de OS que não existe mais).
--  (#3) retorna deposit_paid = soma dos SINAIS já recebidos, para o frontend AVISAR que há dinheiro
--       recebido a tratar (devolução/retenção) no cancelamento. (Não define política — só sinaliza.)
-- Resto do RPC inalterado (estoque v2, cancelamento de recebíveis/pagamentos, marca a OS).

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
  v_collections_cancelled INT := 0;
  v_deposit_paid NUMERIC := 0;
  v_now TIMESTAMPTZ := NOW();
BEGIN
  -- ── 1. Restore stock for all parts in this SO (só no modelo antigo) ───────
  IF NOT public.stock_model_v2_on() THEN
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
  END IF;

  -- ── 2. Cancel linked receivables and their confirmed payments ─────────────
  FOR v_receivable IN
    SELECT id, status, is_deposit, paid_amount
    FROM public.receivables
    WHERE service_order_id = p_service_order_id
      AND status <> 'cancelled'
  LOOP
    -- Sinal já recebido → soma para sinalizar ao usuário (dinheiro a tratar no cancelamento).
    IF v_receivable.is_deposit AND COALESCE(v_receivable.paid_amount, 0) > 0 THEN
      v_deposit_paid := v_deposit_paid + v_receivable.paid_amount;
    END IF;

    FOR v_payment IN
      SELECT id, amount
      FROM public.payments
      WHERE receivable_id = v_receivable.id
        AND status = 'confirmed'
    LOOP
      UPDATE public.payments
      SET status = 'cancelled',
          cancelled_at = v_now,
          cancellation_reason = p_reason
      WHERE id = v_payment.id;

      UPDATE public.bank_transactions
      SET reconciled = FALSE,
          reconciled_payment_id = NULL
      WHERE reconciled_payment_id = v_payment.id;

      v_payments_cancelled := v_payments_cancelled + 1;
    END LOOP;

    UPDATE public.receivables
    SET status = 'cancelled',
        balance_amount = 0
    WHERE id = v_receivable.id;

    v_receivables_cancelled := v_receivables_cancelled + 1;
  END LOOP;

  -- ── 2b. Cancel linked collections (cobranças/dunning) ─────────────────────
  UPDATE public.collections
  SET status = 'cancelled'
  WHERE service_order_id = p_service_order_id
    AND status <> 'cancelled';
  GET DIAGNOSTICS v_collections_cancelled = ROW_COUNT;

  -- ── 3. Mark the service order as cancelled ────────────────────────────────
  UPDATE public.service_orders
  SET status = 'cancelled',
      cancelled_at = v_now,
      cancellation_reason = p_reason
  WHERE id = p_service_order_id;

  RETURN json_build_object(
    'success', TRUE,
    'parts_restored', v_parts_restored,
    'receivables_cancelled', v_receivables_cancelled,
    'payments_cancelled', v_payments_cancelled,
    'collections_cancelled', v_collections_cancelled,
    'deposit_paid', v_deposit_paid
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
