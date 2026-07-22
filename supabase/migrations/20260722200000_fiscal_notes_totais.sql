-- ─────────────────────────────────────────────────────────────────────────────
-- Composição dos totais da NF-e importada.
--
-- MOTIVO: a conferência avisava "a soma dos itens é diferente do total da nota"
-- em TODA nota com IPI — um falso alarme. Na primeira importação real (Kamell
-- NF 34.395): itens 10.782,26 + IPI 856,41 = 11.638,67, que é exatamente o total.
-- A comparação ingênua (soma dos itens × vNF) ignorava que o total da NF-e é:
--
--   vNF = vProd + IPI + frete + seguro + outras despesas − desconto
--
-- Guardando a composição dá para validar a equação de verdade E mostrar ao
-- conferente de onde vem cada parcela, em vez de um alerta vermelho inútil.
-- Aditiva.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.fiscal_notes
  ADD COLUMN IF NOT EXISTS total_products numeric,
  ADD COLUMN IF NOT EXISTS total_discount numeric,
  ADD COLUMN IF NOT EXISTS total_freight  numeric,
  ADD COLUMN IF NOT EXISTS total_other    numeric,
  ADD COLUMN IF NOT EXISTS total_insurance numeric;

COMMENT ON COLUMN public.fiscal_notes.total_products IS
  'vProd do <ICMSTot>: soma dos itens, antes de IPI/frete/desconto.';

-- Preview passa a validar a EQUAÇÃO da nota, não uma igualdade simplista.
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
    v_manual := NULL;
    SELECT (val->>'internal_product_id')::uuid INTO v_manual
      FROM jsonb_array_elements(coalesce(p_manual_mappings, '[]'::jsonb)) AS val
      WHERE val->>'sku_supplier' = v_item.sku_supplier
        AND coalesce(val->>'internal_product_id', '') <> ''
      LIMIT 1;

    SELECT * INTO v_match FROM match_nfe_item(
      p_supplier_id, v_item.barcode, v_item.sku_supplier, v_item.description, v_manual);

    v_pname := NULL; v_psku := NULL; v_punit := NULL;
    v_pncm := NULL; v_pcost := NULL; v_pstock := NULL;
    IF v_match.product_id IS NOT NULL THEN
      SELECT name, sku, unit, ncm, cost_price, stock_quantity
        INTO v_pname, v_psku, v_punit, v_pncm, v_pcost, v_pstock
        FROM products WHERE id = v_match.product_id;
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
      'match_reason',  v_match.match_reason,
      'product_id',    v_match.product_id,
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

  -- vNF = produtos + IPI + frete + seguro + outras despesas − desconto.
  -- Notas antigas (importadas antes da composição existir) não têm as parcelas:
  -- nesse caso não afirmamos divergência, para não repetir o falso alarme.
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
    -- Tolerância de 1 centavo: arredondamento por item é normal.
    'total_matches', (abs(round(v_esperado, 2) - round(coalesce(v_total, 0), 2)) <= 0.01)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.preview_nfe_import(uuid, uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.preview_nfe_import(uuid, uuid, jsonb) TO authenticated;
