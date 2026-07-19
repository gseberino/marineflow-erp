-- ─────────────────────────────────────────────────────────────────────────────
-- Migration: integração estoque + financeiro na venda AVULSA (#2)
--   Botão opt-in "Baixar estoque + gerar recebível" numa NF-e avulsa autorizada.
--   • movement_type ganha 'fiscal_note_exit' (baixa de saída por NF-e — espelha
--     o 'fiscal_note_entry' da importação de entrada).
--   • issued_fiscal_documents ganha source_items (produtos+qtd da emissão, para a
--     baixa mapear com exatidão), stock_settled_at e receivable_id (idempotência).
--   • RPC settle_nfe_stock_and_receivable: atômica, admin-only, idempotente.
--     Notas de OS NÃO entram (a OS já baixa estoque/financeiro). Item digitado à
--     mão (sem product_id) não baixa. Recebível à vista (vence hoje) por padrão.
-- Sem segredos. Reversível (colunas aditivas; a RPC pode ser dropada).
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. movement_type de saída por NF-e
ALTER TABLE public.inventory_movements
  DROP CONSTRAINT IF EXISTS inventory_movements_movement_type_check;
ALTER TABLE public.inventory_movements
  ADD CONSTRAINT inventory_movements_movement_type_check
  CHECK (movement_type IN (
    'purchase','manual_adjustment','service_usage','return','transfer',
    'manual_add','manual_remove','import','fiscal_note_entry',
    'service_order_usage','manual_add_stock','manual_remove_stock',
    'fiscal_note_exit'
  ));

-- 2. Colunas de rastreio na nota emitida
ALTER TABLE public.issued_fiscal_documents
  ADD COLUMN IF NOT EXISTS source_items     jsonb,
  ADD COLUMN IF NOT EXISTS stock_settled_at timestamptz,
  ADD COLUMN IF NOT EXISTS receivable_id    uuid REFERENCES public.receivables(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.issued_fiscal_documents.source_items IS
  'Itens da emissão com vínculo ao catálogo: [{product_id, quantity, unit_price}] — usado pela baixa de estoque (só itens ligados a produto).';

-- 3. RPC atômica: baixa estoque dos itens ligados a produto + cria o recebível.
CREATE OR REPLACE FUNCTION public.settle_nfe_stock_and_receivable(p_document_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_doc          issued_fiscal_documents;
  v_item         jsonb;
  v_pid          uuid;
  v_qty          numeric;
  v_total        numeric := 0;
  v_pay_method   text;
  v_receivable   uuid;
  v_stock_items  int := 0;
BEGIN
  IF NOT public.is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT * INTO v_doc FROM issued_fiscal_documents WHERE id = p_document_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Documento não encontrado.'; END IF;
  IF v_doc.status <> 'authorized' THEN
    RAISE EXCEPTION 'A nota precisa estar autorizada para lançar estoque/recebível.';
  END IF;
  IF v_doc.origin_type <> 'manual' THEN
    RAISE EXCEPTION 'Apenas notas avulsas — as vindas de OS já baixam estoque e geram financeiro pelo fluxo da OS.';
  END IF;
  IF v_doc.stock_settled_at IS NOT NULL THEN
    RAISE EXCEPTION 'Esta nota já teve estoque e recebível lançados.';
  END IF;
  IF v_doc.client_id IS NULL THEN
    RAISE EXCEPTION 'A nota não tem cliente vinculado (necessário para gerar o recebível).';
  END IF;

  -- Baixa de estoque: só itens com product_id (item avulso digitado à mão não baixa).
  IF v_doc.source_items IS NOT NULL THEN
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_doc.source_items) LOOP
      v_pid := NULLIF(v_item->>'product_id','')::uuid;
      v_qty := COALESCE((v_item->>'quantity')::numeric, 0);
      IF v_pid IS NOT NULL AND v_qty > 0 THEN
        UPDATE products
           SET stock_quantity = GREATEST(0, stock_quantity - v_qty), updated_at = now()
         WHERE id = v_pid;
        INSERT INTO inventory_movements
          (product_id, movement_type, quantity_delta, reference_type, reference_id, notes, created_by)
        VALUES
          (v_pid, 'fiscal_note_exit', -v_qty, 'issued_fiscal_document', p_document_id,
           'Baixa por NF-e ' || COALESCE(v_doc.series::text,'') || '/' || COALESCE(v_doc.number::text,''),
           auth.uid());
        v_stock_items := v_stock_items + 1;
      END IF;
    END LOOP;
  END IF;

  -- Total e forma de pagamento vêm do payload salvo (fonte da verdade do valor).
  v_total := COALESCE((v_doc.request_payload->'payments'->0->>'amount')::numeric, 0);
  v_pay_method := v_doc.request_payload->'payments'->0->>'method';

  -- Recebível à vista (vence hoje) — a contadora/usuário ajusta o vencimento depois.
  INSERT INTO receivables
    (client_id, description, issue_date, due_date, amount, balance_amount, status, payment_method, notes)
  VALUES
    (v_doc.client_id,
     'NF-e ' || COALESCE(v_doc.series::text,'') || '/' || COALESCE(v_doc.number::text,''),
     CURRENT_DATE, CURRENT_DATE, v_total, v_total, 'pending', v_pay_method,
     'Gerado a partir da NF-e ' || COALESCE(v_doc.access_key,''))
  RETURNING id INTO v_receivable;

  UPDATE issued_fiscal_documents
     SET stock_settled_at = now(), receivable_id = v_receivable, updated_at = now()
   WHERE id = p_document_id;

  RETURN jsonb_build_object(
    'ok', true, 'receivable_id', v_receivable, 'stock_items', v_stock_items, 'amount', v_total
  );
END;
$$;

-- Chamada pelo front por um ADMIN autenticado (gate is_admin interno). Escrita
-- privilegiada em estoque/financeiro só via esta RPC — não expor a anon.
REVOKE ALL ON FUNCTION public.settle_nfe_stock_and_receivable(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.settle_nfe_stock_and_receivable(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.settle_nfe_stock_and_receivable(uuid) TO authenticated;
