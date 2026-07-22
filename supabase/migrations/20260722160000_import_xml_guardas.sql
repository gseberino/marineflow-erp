-- ─────────────────────────────────────────────────────────────────────────────
-- Guardas da entrada de mercadoria por XML — achados na reconferência.
--
-- 1) GATE DE ADMIN: confirm_nfe_import e revert_nfe_import estavam executáveis
--    por QUALQUER usuário autenticado. A página é admin-only, mas a RPC é
--    chamável direto pela API — e ela soma estoque, cria conta a pagar e, no
--    revert, APAGA movimentos e contas a pagar. Mesmo gate já usado em
--    settle_nfe_stock_and_receivable.
--    auth.uid() nulo (service_role / SQL direto) segue permitido: é o contexto
--    do próprio servidor, já privilegiado.
--
-- 2) VALIDAÇÃO DE ITENS: item sem quantidade/valor abortava com erro cru de
--    constraint ("null value in column quantity_delta..."), ilegível para quem
--    está conferindo a nota. Agora falha cedo, dizendo qual item e o quê.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.confirm_nfe_import(
  p_note_id           uuid,
  p_supplier_id       uuid  DEFAULT NULL,
  p_manual_mappings   jsonb DEFAULT '[]'::jsonb,
  p_purchase_order_id uuid  DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_status      text;
  v_items       jsonb;
  v_total       numeric;
  v_nfe_number  text;
  v_issuer_name text;
  v_item        RECORD;
  v_match       RECORD;
  v_manual      uuid;
  v_product_id  uuid;
  v_reason      text;
  v_created     int := 0;
  v_moved       int := 0;
  v_payable_id  uuid;
  v_margin      numeric;
  v_cat_id      uuid;
  v_old_cost    numeric;
  v_sale        numeric;
  v_detail      jsonb := '[]'::jsonb;
  v_prazo       int;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT status, items, total_amount, nfe_number, issuer_name
    INTO v_status, v_items, v_total, v_nfe_number, v_issuer_name
    FROM fiscal_notes WHERE id = p_note_id
    FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Nota fiscal não encontrada.';
  END IF;
  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'Esta nota já foi processada ou cancelada (status: %).', v_status;
  END IF;

  -- Validação ANTES de escrever qualquer coisa: mensagem útil em vez de erro
  -- de constraint no meio do laço.
  FOR v_item IN SELECT * FROM jsonb_to_recordset(v_items) AS x(
    index int, description text, quantity numeric, unit_price numeric
  ) LOOP
    IF v_item.quantity IS NULL OR v_item.quantity <= 0 THEN
      RAISE EXCEPTION 'Item % (%): quantidade ausente ou inválida no XML. Confira o arquivo.',
        coalesce(v_item.index, 0), coalesce(v_item.description, 'sem descrição');
    END IF;
    IF v_item.unit_price IS NULL OR v_item.unit_price < 0 THEN
      RAISE EXCEPTION 'Item % (%): valor unitário ausente ou inválido no XML.',
        coalesce(v_item.index, 0), coalesce(v_item.description, 'sem descrição');
    END IF;
  END LOOP;

  FOR v_item IN SELECT * FROM jsonb_to_recordset(v_items) AS x(
    index int, sku_supplier text, description text, ncm text, unit text,
    quantity numeric, unit_price numeric, total_price numeric,
    barcode text, origin text
  ) LOOP
    v_manual := NULL;
    SELECT (val->>'internal_product_id')::uuid INTO v_manual
      FROM jsonb_array_elements(coalesce(p_manual_mappings, '[]'::jsonb)) AS val
      WHERE val->>'sku_supplier' = v_item.sku_supplier
        AND coalesce(val->>'internal_product_id', '') <> ''
      LIMIT 1;

    SELECT * INTO v_match FROM match_nfe_item(
      p_supplier_id, v_item.barcode, v_item.sku_supplier, v_item.description, v_manual);
    v_product_id := v_match.product_id;
    v_reason     := v_match.match_reason;

    IF v_product_id IS NULL THEN
      SELECT id, coalesce(default_profit_margin, 30) INTO v_cat_id, v_margin
        FROM product_categories WHERE lower(name) = 'importados' AND active LIMIT 1;
      v_margin := coalesce(v_margin, 30);

      INSERT INTO products (
        name, sku, barcode, category, product_category_id, unit,
        cost_price, sale_price, stock_quantity, ncm, fiscal_origin,
        supplier_id, active, fiscal_complete
      ) VALUES (
        v_item.description,
        v_item.sku_supplier,
        v_item.barcode,
        'Importados',
        v_cat_id,
        coalesce(nullif(btrim(v_item.unit), ''), 'UN'),
        v_item.unit_price,
        round(v_item.unit_price * (1 + v_margin / 100), 2),
        0,
        regexp_replace(coalesce(v_item.ncm, ''), '\D', '', 'g'),
        coalesce(nullif(regexp_replace(coalesce(v_item.origin, ''), '\D', '', 'g'), '')::int, 0),
        p_supplier_id,
        true,
        false
      ) RETURNING id INTO v_product_id;
      v_created := v_created + 1;
    ELSE
      UPDATE products
         SET barcode = coalesce(barcode, nullif(v_item.barcode, '')),
             supplier_id = coalesce(supplier_id, p_supplier_id),
             updated_at = now()
       WHERE id = v_product_id;
    END IF;

    IF p_supplier_id IS NOT NULL AND coalesce(v_item.sku_supplier, '') <> '' THEN
      INSERT INTO supplier_product_mappings (supplier_id, supplier_sku, supplier_description, internal_product_id)
      VALUES (p_supplier_id, v_item.sku_supplier, v_item.description, v_product_id)
      ON CONFLICT (supplier_id, supplier_sku) DO UPDATE
        SET supplier_description = EXCLUDED.supplier_description,
            internal_product_id  = EXCLUDED.internal_product_id,
            updated_at = now();
    END IF;

    INSERT INTO inventory_movements (
      product_id, movement_type, quantity_delta, unit_cost_snapshot,
      reference_type, reference_id, notes
    ) VALUES (
      v_product_id, 'purchase', v_item.quantity, v_item.unit_price,
      'import', p_note_id, 'Entrada via NF-e ' || coalesce(v_nfe_number, '')
    );
    v_moved := v_moved + 1;

    SELECT cost_price, sale_price INTO v_old_cost, v_sale FROM products WHERE id = v_product_id;
    SELECT coalesce(default_profit_margin, 30) INTO v_margin
      FROM product_categories pc
      JOIN products p ON p.id = v_product_id
      WHERE pc.id = p.product_category_id OR lower(pc.name) = lower(p.category)
      LIMIT 1;
    v_margin := coalesce(v_margin, 30);
    IF v_item.unit_price > coalesce(v_old_cost, 0)
       OR coalesce(v_sale, 0) < v_item.unit_price * (1 + v_margin / 100) THEN
      INSERT INTO price_update_suggestions (
        product_id, fiscal_note_id, current_sale_price, suggested_sale_price, margin_percent
      ) VALUES (
        v_product_id, p_note_id, v_sale,
        round(v_item.unit_price * (1 + v_margin / 100), 2), v_margin
      );
    END IF;

    UPDATE products
       SET cost_price = v_item.unit_price,
           stock_quantity = coalesce(stock_quantity, 0) + v_item.quantity,
           last_stock_entry_at = now(),
           updated_at = now()
     WHERE id = v_product_id;

    v_detail := v_detail || jsonb_build_object(
      'sku_supplier', v_item.sku_supplier,
      'description',  v_item.description,
      'product_id',   v_product_id,
      'match_reason', v_reason,
      'quantity',     v_item.quantity
    );
  END LOOP;

  IF p_supplier_id IS NOT NULL THEN
    -- Prazo do próprio cadastro do fornecedor quando houver (ex.: "28", "30
    -- dias"); 28 dias continua como padrão.
    SELECT nullif(regexp_replace(coalesce(payment_terms, ''), '\D', '', 'g'), '')::int
      INTO v_prazo FROM suppliers WHERE id = p_supplier_id;
    IF v_prazo IS NULL OR v_prazo <= 0 OR v_prazo > 365 THEN v_prazo := 28; END IF;

    INSERT INTO payables (
      supplier_id, supplier_name, amount, balance_amount, description,
      issue_date, due_date, status, expense_category, origin, fiscal_note_id
    ) VALUES (
      p_supplier_id, v_issuer_name, v_total, v_total,
      'Compra ref. NF-e ' || coalesce(v_nfe_number, '') || ' - ' || coalesce(v_issuer_name, ''),
      now()::date, (now() + (v_prazo || ' days')::interval)::date,
      'pending', 'Compras de Mercadorias', 'fiscal_note', p_note_id
    ) RETURNING id INTO v_payable_id;
  END IF;

  UPDATE fiscal_notes
     SET status = 'confirmed',
         confirmed_at = now(),
         supplier_id = coalesce(p_supplier_id, supplier_id),
         purchase_order_id = coalesce(p_purchase_order_id, purchase_order_id),
         import_result = jsonb_build_object(
           'items', v_detail, 'products_created', v_created,
           'movements', v_moved, 'payable_id', v_payable_id, 'at', now()
         ),
         updated_at = now()
   WHERE id = p_note_id;

  RETURN jsonb_build_object(
    'success', true,
    'products_created', v_created,
    'movements_created', v_moved,
    'payable_id', v_payable_id,
    'items', v_detail
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.revert_nfe_import(p_note_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_status  text;
  v_mov     RECORD;
  v_undone  int := 0;
  v_payable int := 0;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT status INTO v_status FROM fiscal_notes WHERE id = p_note_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Nota fiscal não encontrada.';
  END IF;
  IF v_status <> 'confirmed' THEN
    RAISE EXCEPTION 'Só é possível desfazer uma importação confirmada (status: %).', v_status;
  END IF;

  FOR v_mov IN
    SELECT product_id, quantity_delta FROM inventory_movements
     WHERE reference_type = 'import' AND reference_id = p_note_id
  LOOP
    UPDATE products
       SET stock_quantity = coalesce(stock_quantity, 0) - v_mov.quantity_delta,
           updated_at = now()
     WHERE id = v_mov.product_id;
    v_undone := v_undone + 1;
  END LOOP;

  DELETE FROM inventory_movements WHERE reference_type = 'import' AND reference_id = p_note_id;

  DELETE FROM payables
   WHERE fiscal_note_id = p_note_id AND coalesce(paid_amount, 0) = 0;
  GET DIAGNOSTICS v_payable = ROW_COUNT;

  DELETE FROM price_update_suggestions WHERE fiscal_note_id = p_note_id;

  UPDATE fiscal_notes
     SET status = 'pending', confirmed_at = NULL, import_result = NULL, updated_at = now()
   WHERE id = p_note_id;

  RETURN jsonb_build_object(
    'success', true, 'movements_reverted', v_undone, 'payables_removed', v_payable
  );
END;
$$;

REVOKE ALL ON FUNCTION public.confirm_nfe_import(uuid, uuid, jsonb, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.revert_nfe_import(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_nfe_import(uuid, uuid, jsonb, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revert_nfe_import(uuid) TO authenticated;
