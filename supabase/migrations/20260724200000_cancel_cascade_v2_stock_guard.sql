-- Modelo de estoque v2: ao cancelar uma OS, o físico NÃO deve ser "restaurado" — no v2 ele nunca
-- foi baixado no add (só reservado). A própria mudança para status='cancelled' dispara o trigger
-- so_status_stock, que recomputa a reserva (cancelled sai do conjunto comprometido). Então a
-- restauração de estoque da seção 1 só roda no modelo antigo (flag OFF). Resto do RPC inalterado.

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
    'payments_cancelled', v_payments_cancelled
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
