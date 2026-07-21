-- ─────────────────────────────────────────────────────────────────────────────
-- Migration: pagamento parcelado da NF-e avulsa (#A) — recebíveis por parcela
--   • receivables.issued_fiscal_document_id: vínculo do recebível à NF-e que o
--     gerou (rastreio + base para a reversão financeira no cancelamento, #C).
--   • settle_nfe_stock_and_receivable ganha p_installments (jsonb): quando
--     informado, cria UM recebível por parcela (com vencimento/valor/forma);
--     quando nulo, mantém o comportamento à vista (um recebível vencendo hoje).
-- Aditiva e reversível. Sem segredos.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.receivables
  ADD COLUMN IF NOT EXISTS issued_fiscal_document_id uuid
    REFERENCES public.issued_fiscal_documents(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_receivables_ifd
  ON public.receivables (issued_fiscal_document_id);

-- Substitui a versão de 1 argumento (evita ambiguidade de overload).
DROP FUNCTION IF EXISTS public.settle_nfe_stock_and_receivable(uuid);

CREATE OR REPLACE FUNCTION public.settle_nfe_stock_and_receivable(
  p_document_id uuid,
  p_installments jsonb DEFAULT NULL
)
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
  v_first_recv   uuid := NULL;
  v_stock_items  int := 0;
  v_n            int;
  v_idx          int := 0;
  v_desc         text;
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

  -- Baixa de estoque: só itens com product_id.
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

  v_total := COALESCE((v_doc.request_payload->'payments'->0->>'amount')::numeric, 0);
  v_pay_method := v_doc.request_payload->'payments'->0->>'method';

  IF p_installments IS NULL OR jsonb_typeof(p_installments) <> 'array' OR jsonb_array_length(p_installments) = 0 THEN
    -- À vista: um recebível vencendo hoje.
    INSERT INTO receivables
      (client_id, description, issue_date, due_date, amount, balance_amount, status, payment_method, notes, issued_fiscal_document_id)
    VALUES
      (v_doc.client_id,
       'NF-e ' || COALESCE(v_doc.series::text,'') || '/' || COALESCE(v_doc.number::text,''),
       CURRENT_DATE, CURRENT_DATE, v_total, v_total, 'pending', v_pay_method,
       'Gerado a partir da NF-e ' || COALESCE(v_doc.access_key,''), p_document_id)
    RETURNING id INTO v_receivable;
    v_first_recv := v_receivable;
    v_n := 1;
  ELSE
    -- Parcelado: um recebível por parcela.
    v_n := jsonb_array_length(p_installments);
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_installments) LOOP
      v_idx := v_idx + 1;
      v_desc := 'NF-e ' || COALESCE(v_doc.series::text,'') || '/' || COALESCE(v_doc.number::text,'')
                || ' (parcela ' || v_idx || '/' || v_n || ')';
      INSERT INTO receivables
        (client_id, description, issue_date, due_date, amount, balance_amount, status, payment_method, notes, issued_fiscal_document_id)
      VALUES
        (v_doc.client_id, v_desc, CURRENT_DATE,
         (v_item->>'due_date')::date,
         (v_item->>'amount')::numeric, (v_item->>'amount')::numeric,
         'pending', COALESCE(NULLIF(v_item->>'method',''), v_pay_method),
         'Gerado a partir da NF-e ' || COALESCE(v_doc.access_key,''), p_document_id)
      RETURNING id INTO v_receivable;
      IF v_first_recv IS NULL THEN v_first_recv := v_receivable; END IF;
    END LOOP;
  END IF;

  UPDATE issued_fiscal_documents
     SET stock_settled_at = now(), receivable_id = v_first_recv, updated_at = now()
   WHERE id = p_document_id;

  RETURN jsonb_build_object(
    'ok', true, 'receivable_id', v_first_recv, 'stock_items', v_stock_items,
    'amount', v_total, 'installments', v_n
  );
END;
$$;

REVOKE ALL     ON FUNCTION public.settle_nfe_stock_and_receivable(uuid, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.settle_nfe_stock_and_receivable(uuid, jsonb) FROM anon;
GRANT  EXECUTE ON FUNCTION public.settle_nfe_stock_and_receivable(uuid, jsonb) TO authenticated;
