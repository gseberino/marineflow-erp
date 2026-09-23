-- O recebivel gerado a partir da NF-e nascia com o valor e a data errados.
--
-- DOIS DEFEITOS, no caminho que grava dinheiro no banco:
--
--  1. VALOR. A funcao lia
--       v_total := (request_payload->'payments'->0->>'amount')::numeric
--     que e a FORMA DE PAGAMENTO declarada, nao o valor da nota. Coincide numa venda a
--     vista e falha em todo o resto: devolucao nao declara pagamento e NFS-e nem tem esse
--     campo, entao o titulo nascia com R$ 0,00. O mesmo erro ja foi corrigido na tela
--     (src/lib/nota-fiscal-leitura.ts) -- aqui e a outra ponta, e e a que persiste.
--
--  2. DATA. issue_date e, no caso a vista, due_date usavam CURRENT_DATE. Lancar hoje uma
--     nota de julho criava um titulo "emitido hoje", desligado do documento. A emissao do
--     titulo e a da nota; o vencimento a vista tambem, salvo plano em contrario.
--
-- A conta do total e a mesma do vNF da NF-e, conferida contra os XMLs autorizados pela
-- SEFAZ em 23/09/2026 (2/24 -> 1.862,55 e 2/29 -> 17.568,17, no centavo):
--
--     vNF = SOMA( round(quantidade x preco_unitario, 2) - desconto
--                 + outras_despesas + ipi_devolvido )
--
-- Cada linha e arredondada antes de somar, que e o que o XML faz.

create or replace function public.settle_nfe_stock_and_receivable(
  p_document_id uuid,
  p_installments jsonb default null::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
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
  v_data_nota    date;
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

  -- ── O VALOR DA NOTA (vNF), e não a forma de pagamento declarada ───────────
  SELECT round(sum(round((i->>'quantity')::numeric * (i->>'unit_price')::numeric, 2)
                   - COALESCE((i->>'discount')::numeric, 0)
                   + COALESCE((i->>'other_expenses')::numeric, 0)
                   + COALESCE((i->'returned_ipi'->>'value')::numeric, 0)), 2)
    INTO v_total
    FROM jsonb_array_elements(COALESCE(v_doc.request_payload->'items', '[]'::jsonb)) i;

  -- NFS-e não tem itens: o líquido é o que o tomador deve. Último recurso, o pagamento
  -- declarado — que só sobra para nota sem item nenhum.
  v_total := COALESCE(
    NULLIF(v_total, 0),
    (v_doc.request_payload->'amounts'->>'net_amount')::numeric,
    (v_doc.request_payload->'amounts'->>'service_amount')::numeric,
    (v_doc.request_payload->'payments'->0->>'amount')::numeric,
    0);

  IF v_total <= 0 THEN
    RAISE EXCEPTION 'Não foi possível calcular o valor desta nota — um recebível de R$ 0,00 não seria cobrável.';
  END IF;

  v_pay_method := v_doc.request_payload->'payments'->0->>'method';

  -- ── A DATA DA NOTA, e não a de hoje ───────────────────────────────────────
  -- Mesma ordem de confiabilidade da tela: carimbo da SEFAZ (já com fuso), evento de
  -- autorização da NFS-e, a coluna, e por fim a criação da linha.
  v_data_nota := (COALESCE(
      (v_doc.provider_status->'sefaz'->>'authorized_at')::timestamptz,
      CASE WHEN v_doc.provider_status->'latest_event'->>'status' = 'authorized'
           THEN (v_doc.provider_status->'latest_event'->>'created_at')::timestamptz END,
      v_doc.authorized_at,
      v_doc.created_at
    ) AT TIME ZONE 'America/Sao_Paulo')::date;

  IF p_installments IS NULL OR jsonb_typeof(p_installments) <> 'array' OR jsonb_array_length(p_installments) = 0 THEN
    -- À vista: um recebível, emitido e vencendo na data da nota.
    INSERT INTO receivables
      (client_id, description, issue_date, due_date, amount, balance_amount, status, payment_method, notes, issued_fiscal_document_id)
    VALUES
      (v_doc.client_id,
       'NF-e ' || COALESCE(v_doc.series::text,'') || '/' || COALESCE(v_doc.number::text,''),
       v_data_nota, v_data_nota, v_total, v_total, 'pending', v_pay_method,
       'Gerado a partir da NF-e ' || COALESCE(v_doc.access_key,''), p_document_id)
    RETURNING id INTO v_receivable;
    v_first_recv := v_receivable;
    v_n := 1;
  ELSE
    -- Parcelado: um recebível por parcela, com os valores e vencimentos que vieram --
    -- que são os da própria nota, salvo se o gestor os alterou de propósito na tela.
    v_n := jsonb_array_length(p_installments);
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_installments) LOOP
      v_idx := v_idx + 1;
      v_desc := 'NF-e ' || COALESCE(v_doc.series::text,'') || '/' || COALESCE(v_doc.number::text,'')
                || ' (parcela ' || v_idx || '/' || v_n || ')';
      INSERT INTO receivables
        (client_id, description, issue_date, due_date, amount, balance_amount, status, payment_method, notes, issued_fiscal_document_id)
      VALUES
        (v_doc.client_id, v_desc, v_data_nota,
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
    'amount', v_total, 'installments', v_n, 'issue_date', v_data_nota
  );
END;
$function$;
