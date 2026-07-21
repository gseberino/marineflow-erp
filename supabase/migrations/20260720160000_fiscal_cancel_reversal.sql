-- ─────────────────────────────────────────────────────────────────────────────
-- Migration: reversão financeira ao CANCELAR a NF-e (#C)
--   Quando uma NF-e avulsa que teve estoque/recebível lançados (#2/#A) é
--   CANCELADA, um trigger reverte automaticamente:
--     • cancela os recebíveis NÃO PAGOS gerados por ela (via issued_fiscal_document_id);
--     • estorna a baixa de estoque (repõe as quantidades) com um movimento
--       compensatório 'fiscal_note_cancel_reversal'.
--   Recebíveis com pagamento (parcial/total) NÃO são mexidos — exigem tratamento
--   humano (reembolso). Idempotente via stock_reversed_at.
-- Dispara por QUALQUER caminho que marque 'cancelled' (webhook/reconcile/manual).
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.issued_fiscal_documents
  ADD COLUMN IF NOT EXISTS stock_reversed_at timestamptz;

-- Tipo de movimento para o estorno (entrada de volta ao estoque por cancelamento).
ALTER TABLE public.inventory_movements
  DROP CONSTRAINT IF EXISTS inventory_movements_movement_type_check;
ALTER TABLE public.inventory_movements
  ADD CONSTRAINT inventory_movements_movement_type_check
  CHECK (movement_type IN (
    'purchase','manual_adjustment','service_usage','return','transfer',
    'manual_add','manual_remove','import','fiscal_note_entry',
    'service_order_usage','manual_add_stock','manual_remove_stock',
    'fiscal_note_exit','fiscal_note_cancel_reversal'
  ));

CREATE OR REPLACE FUNCTION public.reverse_nfe_settlement_on_cancel()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r record;
BEGIN
  -- Só age na transição para 'cancelled', quando houve lançamento e ainda não
  -- foi revertido (idempotente).
  IF NEW.status = 'cancelled'
     AND OLD.status IS DISTINCT FROM 'cancelled'
     AND NEW.stock_settled_at IS NOT NULL
     AND NEW.stock_reversed_at IS NULL THEN

    -- 1) Cancela os recebíveis NÃO PAGOS desta nota (paid_amount = 0).
    UPDATE receivables
       SET status = 'cancelled', updated_at = now()
     WHERE issued_fiscal_document_id = NEW.id
       AND status <> 'paid'
       AND COALESCE(paid_amount, 0) = 0;

    -- 2) Estorna a baixa de estoque: para cada baixa 'fiscal_note_exit' desta
    --    nota, repõe a quantidade e registra um movimento compensatório.
    FOR r IN
      SELECT product_id, quantity_delta
        FROM inventory_movements
       WHERE reference_type = 'issued_fiscal_document'
         AND reference_id = NEW.id
         AND movement_type = 'fiscal_note_exit'
    LOOP
      -- quantity_delta é negativo (baixa); subtrair o negativo repõe o estoque.
      UPDATE products
         SET stock_quantity = stock_quantity - r.quantity_delta, updated_at = now()
       WHERE id = r.product_id;

      INSERT INTO inventory_movements
        (product_id, movement_type, quantity_delta, reference_type, reference_id, notes)
      VALUES
        (r.product_id, 'fiscal_note_cancel_reversal', -r.quantity_delta,
         'issued_fiscal_document', NEW.id,
         'Estorno de estoque — NF-e ' || COALESCE(NEW.series::text,'') || '/'
           || COALESCE(NEW.number::text,'') || ' cancelada');
    END LOOP;

    NEW.stock_reversed_at := now();
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_reverse_nfe_settlement_on_cancel ON public.issued_fiscal_documents;
CREATE TRIGGER trg_reverse_nfe_settlement_on_cancel
  BEFORE UPDATE ON public.issued_fiscal_documents
  FOR EACH ROW
  EXECUTE FUNCTION public.reverse_nfe_settlement_on_cancel();
