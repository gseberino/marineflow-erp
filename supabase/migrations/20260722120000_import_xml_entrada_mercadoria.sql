-- ─────────────────────────────────────────────────────────────────────────────
-- Entrada de mercadoria por XML de NF-e — casamento inteligente, conferência,
-- vínculo com ordem de compra e desfazer.
--
-- CONTEXTO: a auditoria mostrou que este fluxo NUNCA operou. Além da edge
-- function nunca ter sido deployada, a RPC `confirm_nfe_import` referenciava
-- colunas que NÃO EXISTEM no schema atual e falharia em três pontos:
--   products.product_name / products.fiscal_ncm  → hoje são name / ncm
--   inventory_movements.fiscal_note_id           → não existe (há reference_id)
--   payables.fiscal_note_id                      → não existe
-- Por isso `fiscal_notes` está zerada em produção.
--
-- Esta migration reescreve o fluxo com as colunas corretas e adiciona:
--   • casamento em cascata registrando COMO casou (manual → GTIN → de-para →
--     SKU → descrição normalizada → novo);
--   • preview_nfe_import(): simulação read-only para a tela de conferência;
--   • vínculo opcional com a ordem de compra (conferência em três vias);
--   • revert_nfe_import(): desfaz a importação (estorna estoque e conta a pagar).
-- Aditiva: nenhuma linha existente é alterada ou removida.
-- ─────────────────────────────────────────────────────────────────────────────

-- unaccent: casar "PARAFUSO M8 INOX" com "Parafuso M8  Inox." sem acento/pontuação
CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA extensions;

-- ── 1. Colunas de rastreio ───────────────────────────────────────────────────
ALTER TABLE public.fiscal_notes
  ADD COLUMN IF NOT EXISTS supplier_id       uuid REFERENCES public.suppliers(id),
  ADD COLUMN IF NOT EXISTS purchase_order_id uuid REFERENCES public.purchase_orders(id),
  ADD COLUMN IF NOT EXISTS import_result     jsonb;

ALTER TABLE public.payables
  ADD COLUMN IF NOT EXISTS fiscal_note_id uuid REFERENCES public.fiscal_notes(id);

COMMENT ON COLUMN public.fiscal_notes.import_result IS
  'Resultado da confirmação: itens, produto casado e o motivo do casamento (auditoria).';

-- Casar por código de barras precisa ser rápido e o campo é opcional.
CREATE INDEX IF NOT EXISTS idx_products_barcode
  ON public.products (barcode) WHERE barcode IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_payables_fiscal_note
  ON public.payables (fiscal_note_id) WHERE fiscal_note_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_inv_mov_reference
  ON public.inventory_movements (reference_type, reference_id);

-- ── 2. Normalização de descrição ─────────────────────────────────────────────
-- Maiúsculas, sem acento e com qualquer pontuação/espaço colapsado, para que
-- variações tipográficas do mesmo produto casem entre si.
CREATE OR REPLACE FUNCTION public.normalize_product_text(t text)
RETURNS text
LANGUAGE sql
STABLE
PARALLEL SAFE
SET search_path = public, extensions
AS $$
  SELECT btrim(regexp_replace(upper(extensions.unaccent(coalesce(t, ''))), '[^A-Z0-9]+', ' ', 'g'));
$$;

-- ── 3. Casamento em cascata ──────────────────────────────────────────────────
-- Devolve o produto e o MOTIVO. O motivo é o que permite a tela de conferência
-- mostrar por que cada item foi vinculado — e o usuário discordar antes de
-- confirmar. Ordem: decisão do usuário > identidade global (GTIN) > histórico
-- com aquele fornecedor > código interno > descrição.
CREATE OR REPLACE FUNCTION public.match_nfe_item(
  p_supplier_id       uuid,
  p_barcode           text,
  p_sku_supplier      text,
  p_description       text,
  p_manual_product_id uuid DEFAULT NULL
)
RETURNS TABLE (product_id uuid, match_reason text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF p_manual_product_id IS NOT NULL THEN
    RETURN QUERY SELECT p_manual_product_id, 'manual'::text;
    RETURN;
  END IF;

  IF coalesce(p_barcode, '') <> '' THEN
    SELECT id INTO v_id FROM products
      WHERE barcode = p_barcode AND active ORDER BY created_at LIMIT 1;
    IF v_id IS NOT NULL THEN
      RETURN QUERY SELECT v_id, 'barcode'::text;
      RETURN;
    END IF;
  END IF;

  IF p_supplier_id IS NOT NULL AND coalesce(p_sku_supplier, '') <> '' THEN
    SELECT m.internal_product_id INTO v_id FROM supplier_product_mappings m
      JOIN products p ON p.id = m.internal_product_id AND p.active
      WHERE m.supplier_id = p_supplier_id AND m.supplier_sku = p_sku_supplier
      LIMIT 1;
    IF v_id IS NOT NULL THEN
      RETURN QUERY SELECT v_id, 'de_para'::text;
      RETURN;
    END IF;
  END IF;

  IF coalesce(p_sku_supplier, '') <> '' THEN
    SELECT id INTO v_id FROM products
      WHERE sku = p_sku_supplier AND active ORDER BY created_at LIMIT 1;
    IF v_id IS NOT NULL THEN
      RETURN QUERY SELECT v_id, 'sku'::text;
      RETURN;
    END IF;
  END IF;

  IF coalesce(p_description, '') <> '' THEN
    SELECT id INTO v_id FROM products
      WHERE active
        AND normalize_product_text(name) = normalize_product_text(p_description)
      ORDER BY created_at LIMIT 1;
    IF v_id IS NOT NULL THEN
      RETURN QUERY SELECT v_id, 'descricao'::text;
      RETURN;
    END IF;
  END IF;

  RETURN QUERY SELECT NULL::uuid, 'novo'::text;
END;
$$;

-- ── 4. Simulação (tela de conferência) ───────────────────────────────────────
-- READ-ONLY: mostra o que aconteceria, sem tocar em estoque nem no financeiro.
-- É o que permite conferir ANTES de confirmar, como fazem os ERPs de mercado.
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
  v_items    jsonb;
  v_status   text;
  v_item     RECORD;
  v_match    RECORD;
  v_manual   uuid;
  v_prod     RECORD;
  v_out      jsonb := '[]'::jsonb;
  v_soma     numeric := 0;
  v_total    numeric;
BEGIN
  SELECT items, status, total_amount INTO v_items, v_status, v_total
    FROM fiscal_notes WHERE id = p_note_id;
  IF v_items IS NULL THEN
    RAISE EXCEPTION 'Nota fiscal não encontrada.';
  END IF;

  FOR v_item IN SELECT * FROM jsonb_to_recordset(v_items) AS x(
    index int, sku_supplier text, description text, ncm text, unit text,
    quantity numeric, unit_price numeric, total_price numeric, barcode text
  ) LOOP
    v_manual := NULL;
    SELECT (val->>'internal_product_id')::uuid INTO v_manual
      FROM jsonb_array_elements(coalesce(p_manual_mappings, '[]'::jsonb)) AS val
      WHERE val->>'sku_supplier' = v_item.sku_supplier
      LIMIT 1;

    SELECT * INTO v_match FROM match_nfe_item(
      p_supplier_id, v_item.barcode, v_item.sku_supplier, v_item.description, v_manual);

    v_prod := NULL;
    IF v_match.product_id IS NOT NULL THEN
      SELECT id, name, sku, barcode, unit, cost_price, stock_quantity, ncm
        INTO v_prod FROM products WHERE id = v_match.product_id;
    END IF;

    v_soma := v_soma + coalesce(v_item.total_price, v_item.quantity * v_item.unit_price, 0);

    v_out := v_out || jsonb_build_object(
      'index',          v_item.index,
      'sku_supplier',   v_item.sku_supplier,
      'description',    v_item.description,
      'barcode',        v_item.barcode,
      'quantity',       v_item.quantity,
      'unit_price',     v_item.unit_price,
      'match_reason',   v_match.match_reason,
      'product_id',     v_match.product_id,
      'product_name',   v_prod.name,
      'product_sku',    v_prod.sku,
      'product_unit',   v_prod.unit,
      'product_ncm',    v_prod.ncm,
      'current_cost',   v_prod.cost_price,
      'current_stock',  v_prod.stock_quantity,
      -- Divergências que o conferente precisa ver antes de aceitar
      'cost_changed',   (v_prod.cost_price IS NOT NULL
                          AND round(v_prod.cost_price, 2) <> round(coalesce(v_item.unit_price, 0), 2)),
      'unit_changed',   (v_prod.unit IS NOT NULL AND coalesce(v_item.unit, '') <> ''
                          AND upper(btrim(v_prod.unit)) <> upper(btrim(v_item.unit))),
      'ncm_changed',    (coalesce(v_prod.ncm, '') <> '' AND coalesce(v_item.ncm, '') <> ''
                          AND regexp_replace(v_prod.ncm, '\D', '', 'g')
                              <> regexp_replace(v_item.ncm, '\D', '', 'g'))
    );
  END LOOP;

  RETURN jsonb_build_object(
    'status',        v_status,
    'already_done',  (v_status <> 'pending'),
    'items',         v_out,
    'items_sum',     round(v_soma, 2),
    'note_total',    round(coalesce(v_total, 0), 2),
    -- Soma dos itens x total da nota: diferença aponta frete/desconto/despesas
    -- não distribuídos, ou XML truncado.
    'total_matches', (round(v_soma, 2) = round(coalesce(v_total, 0), 2))
  );
END;
$$;

-- ── 5. Confirmação ───────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.confirm_nfe_import(uuid, uuid, jsonb);
CREATE FUNCTION public.confirm_nfe_import(
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
BEGIN
  SELECT status, items, total_amount, nfe_number, issuer_name
    INTO v_status, v_items, v_total, v_nfe_number, v_issuer_name
    FROM fiscal_notes WHERE id = p_note_id
    FOR UPDATE;   -- trava a nota: dois cliques simultâneos não duplicam a entrada

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Nota fiscal não encontrada.';
  END IF;
  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'Esta nota já foi processada ou cancelada (status: %).', v_status;
  END IF;

  FOR v_item IN SELECT * FROM jsonb_to_recordset(v_items) AS x(
    index int, sku_supplier text, description text, ncm text, unit text,
    quantity numeric, unit_price numeric, total_price numeric,
    barcode text, origin text
  ) LOOP
    v_manual := NULL;
    SELECT (val->>'internal_product_id')::uuid INTO v_manual
      FROM jsonb_array_elements(coalesce(p_manual_mappings, '[]'::jsonb)) AS val
      WHERE val->>'sku_supplier' = v_item.sku_supplier
      LIMIT 1;

    SELECT * INTO v_match FROM match_nfe_item(
      p_supplier_id, v_item.barcode, v_item.sku_supplier, v_item.description, v_manual);
    v_product_id := v_match.product_id;
    v_reason     := v_match.match_reason;

    IF v_product_id IS NULL THEN
      -- Margem da categoria (a RPC antiga criava com 30% fixo e só depois
      -- consultava a margem — nascia com preço fora da política).
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
        0,                                   -- o movimento abaixo é que soma
        regexp_replace(coalesce(v_item.ncm, ''), '\D', '', 'g'),
        coalesce(nullif(regexp_replace(coalesce(v_item.origin, ''), '\D', '', 'g'), '')::int, 0),
        p_supplier_id,
        true,
        false                                -- marca p/ revisão fiscal
      ) RETURNING id INTO v_product_id;
      v_created := v_created + 1;
    ELSE
      -- Aprende o GTIN quando o produto ainda não tinha: o próximo XML casa
      -- direto pelo código de barras, sem depender de descrição.
      UPDATE products
         SET barcode = coalesce(barcode, nullif(v_item.barcode, '')),
             supplier_id = coalesce(supplier_id, p_supplier_id),
             updated_at = now()
       WHERE id = v_product_id;
    END IF;

    -- De-para (aprendizado): só com fornecedor identificado.
    IF p_supplier_id IS NOT NULL AND coalesce(v_item.sku_supplier, '') <> '' THEN
      INSERT INTO supplier_product_mappings (supplier_id, supplier_sku, supplier_description, internal_product_id)
      VALUES (p_supplier_id, v_item.sku_supplier, v_item.description, v_product_id)
      ON CONFLICT (supplier_id, supplier_sku) DO UPDATE
        SET supplier_description = EXCLUDED.supplier_description,
            internal_product_id  = EXCLUDED.internal_product_id,
            updated_at = now();
    END IF;

    -- Movimento de estoque (reference_type/reference_id é o padrão da tabela;
    -- a RPC antiga usava uma coluna fiscal_note_id que não existe).
    INSERT INTO inventory_movements (
      product_id, movement_type, quantity_delta, unit_cost_snapshot,
      reference_type, reference_id, notes
    ) VALUES (
      v_product_id, 'purchase', v_item.quantity, v_item.unit_price,
      'import', p_note_id, 'Entrada via NF-e ' || coalesce(v_nfe_number, '')
    );
    v_moved := v_moved + 1;

    -- Sugestão de preço quando o custo sobe ou a margem defasa.
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
    INSERT INTO payables (
      supplier_id, supplier_name, amount, balance_amount, description,
      issue_date, due_date, status, expense_category, origin, fiscal_note_id
    ) VALUES (
      p_supplier_id, v_issuer_name, v_total, v_total,
      'Compra ref. NF-e ' || coalesce(v_nfe_number, '') || ' - ' || coalesce(v_issuer_name, ''),
      now()::date, (now() + interval '28 days')::date,
      'pending', 'Compras de Mercadorias', 'fiscal_import', p_note_id
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

-- A sobrecarga de 2 argumentos tornava AMBÍGUA qualquer chamada com 2 args
-- (ambas casavam por default) e era código morto.
DROP FUNCTION IF EXISTS public.confirm_nfe_import(uuid, uuid);

-- ── 6. Desfazer importação ───────────────────────────────────────────────────
-- Antes não havia volta: um erro de conferência ficava gravado no estoque.
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
  SELECT status INTO v_status FROM fiscal_notes WHERE id = p_note_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Nota fiscal não encontrada.';
  END IF;
  IF v_status <> 'confirmed' THEN
    RAISE EXCEPTION 'Só é possível desfazer uma importação confirmada (status: %).', v_status;
  END IF;

  -- Estorna o estoque de cada movimento gerado por esta nota.
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

  -- Só remove a conta a pagar se ainda não houve pagamento.
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

-- ── 7. Permissões ────────────────────────────────────────────────────────────
-- SECURITY DEFINER exige revogar de anon/authenticated explicitamente: o
-- Supabase concede EXECUTE a esses papéis por padrão em funções novas do schema
-- public (REVOKE ... FROM PUBLIC sozinho NÃO cobre).
REVOKE ALL ON FUNCTION public.match_nfe_item(uuid, text, text, text, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.revert_nfe_import(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.confirm_nfe_import(uuid, uuid, jsonb, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.preview_nfe_import(uuid, uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.preview_nfe_import(uuid, uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_nfe_import(uuid, uuid, jsonb, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revert_nfe_import(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.match_nfe_item(uuid, text, text, text, uuid) TO authenticated;
