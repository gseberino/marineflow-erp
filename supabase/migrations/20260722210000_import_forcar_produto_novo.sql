-- ─────────────────────────────────────────────────────────────────────────────
-- "Criar como Novo Produto" precisa ser uma DECISÃO, não a ausência de decisão.
--
-- PROBLEMA: escolher essa opção na tela apenas REMOVIA o vínculo manual do item.
-- Sem vínculo, o servidor executava a cascata normalmente — e se ela casasse por
-- descrição ou SKU, o item era vinculado a um produto existente, silenciosamente
-- contrariando a escolha do usuário. Não havia como forçar a criação.
--
-- Agora o mapeamento manual aceita {"sku_supplier": "X", "force_new": true}, que
-- pula a cascata e devolve 'novo'.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.preview_nfe_import(
  p_note_id         uuid,
  p_supplier_id     uuid  DEFAULT NULL,
  p_manual_mappings jsonb DEFAULT '[]'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_items   jsonb;
  v_status  text;
  v_total   numeric;
  v_prod    numeric;
  v_ipi     numeric;
  v_desc    numeric;
  v_frete   numeric;
  v_seg     numeric;
  v_outro   numeric;
  v_item    RECORD;
  v_match   RECORD;
  v_manual  uuid;
  v_forcar  boolean;
  v_reason  text;
  v_pid     uuid;
  v_pname   text;
  v_psku    text;
  v_punit   text;
  v_pncm    text;
  v_pcost   numeric;
  v_pstock  numeric;
  v_out     jsonb := '[]'::jsonb;
  v_soma    numeric := 0;
  v_esperado numeric;
BEGIN
  SELECT items, status, total_amount,
         total_products, tax_ipi, total_discount, total_freight, total_insurance, total_other
    INTO v_items, v_status, v_total,
         v_prod, v_ipi, v_desc, v_frete, v_seg, v_outro
    FROM fiscal_notes WHERE id = p_note_id;
  IF v_items IS NULL THEN
    RAISE EXCEPTION 'Nota fiscal não encontrada.';
  END IF;

  FOR v_item IN SELECT * FROM jsonb_to_recordset(v_items) AS x(
    index int, sku_supplier text, description text, ncm text, unit text,
    quantity numeric, unit_price numeric, total_price numeric, barcode text
  ) LOOP
    v_manual := NULL; v_forcar := false;
    SELECT (val->>'internal_product_id')::uuid, coalesce((val->>'force_new')::boolean, false)
      INTO v_manual, v_forcar
      FROM jsonb_array_elements(coalesce(p_manual_mappings, '[]'::jsonb)) AS val
      WHERE val->>'sku_supplier' = v_item.sku_supplier
      LIMIT 1;

    IF v_forcar THEN
      v_pid := NULL; v_reason := 'novo';
    ELSE
      SELECT * INTO v_match FROM match_nfe_item(
        p_supplier_id, v_item.barcode, v_item.sku_supplier, v_item.description, v_manual);
      v_pid := v_match.product_id; v_reason := v_match.match_reason;
    END IF;

    v_pname := NULL; v_psku := NULL; v_punit := NULL;
    v_pncm := NULL; v_pcost := NULL; v_pstock := NULL;
    IF v_pid IS NOT NULL THEN
      SELECT name, sku, unit, ncm, cost_price, stock_quantity
        INTO v_pname, v_psku, v_punit, v_pncm, v_pcost, v_pstock
        FROM products WHERE id = v_pid;
    END IF;

    v_soma := v_soma + coalesce(v_item.total_price, v_item.quantity * v_item.unit_price, 0);

    v_out := v_out || jsonb_build_object(
      'index',         v_item.index,
      'sku_supplier',  v_item.sku_supplier,
      'description',   v_item.description,
      'barcode',       v_item.barcode,
      'quantity',      v_item.quantity,
      'unit_price',    v_item.unit_price,
      'total_price',   v_item.total_price,
      'match_reason',  v_reason,
      'product_id',    v_pid,
      'product_name',  v_pname,
      'product_sku',   v_psku,
      'product_unit',  v_punit,
      'product_ncm',   v_pncm,
      'current_cost',  v_pcost,
      'current_stock', v_pstock,
      'cost_changed',  (v_pcost IS NOT NULL
                         AND round(v_pcost, 2) <> round(coalesce(v_item.unit_price, 0), 2)),
      'unit_changed',  (v_punit IS NOT NULL AND coalesce(v_item.unit, '') <> ''
                         AND upper(btrim(v_punit)) <> upper(btrim(v_item.unit))),
      'ncm_changed',   (coalesce(v_pncm, '') <> '' AND coalesce(v_item.ncm, '') <> ''
                         AND regexp_replace(v_pncm, '\D', '', 'g')
                             <> regexp_replace(v_item.ncm, '\D', '', 'g'))
    );
  END LOOP;

  v_esperado := round(v_soma, 2)
              + coalesce(v_ipi, 0) + coalesce(v_frete, 0)
              + coalesce(v_seg, 0) + coalesce(v_outro, 0)
              - coalesce(v_desc, 0);

  RETURN jsonb_build_object(
    'status',        v_status,
    'already_done',  (v_status <> 'pending'),
    'items',         v_out,
    'items_sum',     round(v_soma, 2),
    'note_total',    round(coalesce(v_total, 0), 2),
    'total_products', v_prod,
    'total_ipi',      coalesce(v_ipi, 0),
    'total_discount', coalesce(v_desc, 0),
    'total_freight',  coalesce(v_frete, 0),
    'total_insurance', coalesce(v_seg, 0),
    'total_other',    coalesce(v_outro, 0),
    'expected_total', round(v_esperado, 2),
    'total_matches', (abs(round(v_esperado, 2) - round(coalesce(v_total, 0), 2)) <= 0.01)
  );
END;
$$;

-- A confirmação precisa honrar a mesma decisão, senão a tela mostra "produto
-- novo" e o banco vincula a um existente.
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
  v_forcar      boolean;
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
    v_manual := NULL; v_forcar := false;
    SELECT (val->>'internal_product_id')::uuid, coalesce((val->>'force_new')::boolean, false)
      INTO v_manual, v_forcar
      FROM jsonb_array_elements(coalesce(p_manual_mappings, '[]'::jsonb)) AS val
      WHERE val->>'sku_supplier' = v_item.sku_supplier
      LIMIT 1;

    IF v_forcar THEN
      v_product_id := NULL; v_reason := 'novo';
    ELSE
      SELECT * INTO v_match FROM match_nfe_item(
        p_supplier_id, v_item.barcode, v_item.sku_supplier, v_item.description, v_manual);
      v_product_id := v_match.product_id;
      v_reason     := v_match.match_reason;
    END IF;

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

REVOKE ALL ON FUNCTION public.preview_nfe_import(uuid, uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.confirm_nfe_import(uuid, uuid, jsonb, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.preview_nfe_import(uuid, uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_nfe_import(uuid, uuid, jsonb, uuid) TO authenticated;
