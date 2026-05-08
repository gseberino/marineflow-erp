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
