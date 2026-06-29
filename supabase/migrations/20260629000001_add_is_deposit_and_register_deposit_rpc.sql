-- ═══════════════════════════════════════════════════════════════
-- BLOCO 1.1 — Coluna is_deposit + RPC register_deposit_and_convert
--
-- Problema: a coluna is_deposit não existe mas é referenciada em
-- use-pdf.ts:30, ServiceOrderForm.tsx:1257 e usada para
-- renderizar o card "Sinal Recebido" no PDF de fatura.
-- A RPC register_deposit_and_convert é chamada em
-- RegisterDepositDialog.tsx:120 mas também não existia.
-- ═══════════════════════════════════════════════════════════════

-- 1. Adiciona coluna is_deposit à tabela receivables
ALTER TABLE public.receivables
  ADD COLUMN IF NOT EXISTS is_deposit boolean NOT NULL DEFAULT false;

-- 2. Índice parcial para acelerar a query de deposit_paid
--    (usePDFData e fetchPDFData filtram: is_deposit=true + status='paid')
CREATE INDEX IF NOT EXISTS idx_receivables_deposit
  ON public.receivables (service_order_id, is_deposit, status)
  WHERE is_deposit = true;

-- 3. RPC register_deposit_and_convert
--    Registra o sinal de um orçamento e o converte em OS atomicamente.
--    Parâmetros expostos pelo RegisterDepositDialog.tsx (linha 120-127):
--      p_service_order_id, p_amount, p_payment_date, p_payment_method,
--      p_card_fee_percent, p_notes
CREATE OR REPLACE FUNCTION public.register_deposit_and_convert(
  p_service_order_id  UUID,
  p_amount            NUMERIC,
  p_payment_date      DATE,
  p_payment_method    TEXT,
  p_card_fee_percent  NUMERIC DEFAULT 0,
  p_notes             TEXT    DEFAULT NULL
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
BEGIN
  -- Validação
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Valor do sinal deve ser maior que zero';
  END IF;

  -- Busca dados da OS
  SELECT service_order_number, client_id
  INTO v_so_number, v_client_id
  FROM public.service_orders
  WHERE id = p_service_order_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ordem de serviço não encontrada: %', p_service_order_id;
  END IF;

  v_net_amount := p_amount - (p_amount * COALESCE(p_card_fee_percent, 0) / 100.0);

  -- Cria receivable de sinal (is_deposit = true, já pago)
  INSERT INTO public.receivables (
    service_order_id,
    client_id,
    description,
    issue_date,
    due_date,
    amount,
    balance_amount,
    paid_amount,
    status,
    is_deposit
  ) VALUES (
    p_service_order_id,
    v_client_id,
    'Sinal — ' || COALESCE(v_so_number, ''),
    p_payment_date,
    p_payment_date,
    p_amount,
    0,           -- balance_amount=0: já quitado
    p_amount,    -- paid_amount=total
    'paid',
    true
  ) RETURNING id INTO v_receivable_id;

  -- Registra o pagamento associado
  INSERT INTO public.payments (
    receivable_id,
    amount,
    payment_date,
    payment_method,
    card_fee_percent,
    net_amount,
    notes,
    status
  ) VALUES (
    v_receivable_id,
    p_amount,
    p_payment_date,
    p_payment_method,
    COALESCE(p_card_fee_percent, 0),
    v_net_amount,
    p_notes,
    'confirmed'
  ) RETURNING id INTO v_payment_id;

  -- Converte orçamento (draft) em OS (open)
  UPDATE public.service_orders
  SET
    status             = CASE WHEN status = 'draft' THEN 'open' ELSE status END,
    converted_to_os_at = CASE WHEN status = 'draft' AND converted_to_os_at IS NULL
                              THEN NOW() ELSE converted_to_os_at END,
    -- Troca prefixo ORÇ- → OS- para manter numeração unificada
    service_order_number = CASE
      WHEN status = 'draft' AND service_order_number LIKE 'ORÇ-%'
        THEN REPLACE(service_order_number, 'ORÇ-', 'OS-')
      ELSE service_order_number
    END
  WHERE id = p_service_order_id;

  RETURN json_build_object(
    'receivable_id', v_receivable_id,
    'payment_id',    v_payment_id,
    'net_amount',    v_net_amount
  );
END;
$$;

-- Garante que autenticados possam chamar (registro de sinal é feito pelo
-- vendedor/técnico, não apenas admin)
GRANT EXECUTE ON FUNCTION public.register_deposit_and_convert TO authenticated;
