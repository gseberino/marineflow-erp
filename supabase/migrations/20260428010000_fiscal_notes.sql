-- ─────────────────────────────────────────────────────────────────────────────
-- Migration: fiscal_notes table + confirm_nfe_import RPC
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Tabela principal de notas fiscais importadas
CREATE TABLE IF NOT EXISTS fiscal_notes (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nfe_key       text UNIQUE,
  nfe_number    text,
  issuer_name   text,
  issuer_cnpj   text,
  issued_at     timestamptz,
  total_amount  numeric(14,2) DEFAULT 0,
  tax_icms      numeric(14,2) DEFAULT 0,
  tax_ipi       numeric(14,2) DEFAULT 0,
  tax_pis       numeric(14,2) DEFAULT 0,
  tax_cofins    numeric(14,2) DEFAULT 0,
  items         jsonb NOT NULL DEFAULT '[]',
  xml_content   text,                          -- XML original armazenado
  status        text NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending','confirmed','cancelled','error')),
  confirmed_at  timestamptz,
  created_at    timestamptz DEFAULT now(),
  updated_at    timestamptz DEFAULT now()
);

-- Índices para queries frequentes
CREATE INDEX IF NOT EXISTS idx_fiscal_notes_status    ON fiscal_notes (status);
CREATE INDEX IF NOT EXISTS idx_fiscal_notes_nfe_key   ON fiscal_notes (nfe_key);
CREATE INDEX IF NOT EXISTS idx_fiscal_notes_issued_at ON fiscal_notes (issued_at DESC);

-- RLS
ALTER TABLE fiscal_notes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "fiscal_notes_select" ON fiscal_notes;
DROP POLICY IF EXISTS "fiscal_notes_insert" ON fiscal_notes;
DROP POLICY IF EXISTS "fiscal_notes_update" ON fiscal_notes;
CREATE POLICY "fiscal_notes_select" ON fiscal_notes FOR SELECT TO authenticated USING (true);
CREATE POLICY "fiscal_notes_insert" ON fiscal_notes FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "fiscal_notes_update" ON fiscal_notes FOR UPDATE TO authenticated USING (true);

-- 2. Extend payables.origin to include 'fiscal_note' and 'commission'
ALTER TABLE public.payables DROP CONSTRAINT IF EXISTS chk_payables_origin;
ALTER TABLE public.payables ADD CONSTRAINT chk_payables_origin
  CHECK (origin IN ('manual','service_order_expense','bank_reconciliation','fiscal_note','commission'));

-- 3. Extend inventory_movements.movement_type constraint
ALTER TABLE public.inventory_movements
  DROP CONSTRAINT IF EXISTS inventory_movements_movement_type_check;
ALTER TABLE public.inventory_movements
  ADD CONSTRAINT inventory_movements_movement_type_check
  CHECK (movement_type IN (
    'purchase','manual_adjustment','service_usage','return','transfer',
    'manual_add','manual_remove','import','fiscal_note_entry'
  ));

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. RPC: confirm_nfe_import (atomic: stock + movements + payable + audit)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION confirm_nfe_import(
  p_note_id      uuid,
  p_supplier_id  uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_note              fiscal_notes%ROWTYPE;
  v_item              jsonb;
  v_product_id        uuid;
  v_qty               numeric;
  v_cost              numeric;
  v_movements         int := 0;
  v_created_products  int := 0;
  v_supplier_name     text;
BEGIN
  SELECT * INTO v_note FROM fiscal_notes WHERE id = p_note_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'fiscal_note % not found', p_note_id;
  END IF;
  IF v_note.status <> 'pending' THEN
    RAISE EXCEPTION 'fiscal_note already has status %, cannot confirm again', v_note.status;
  END IF;

  -- Resolve supplier name for the payable snapshot
  IF p_supplier_id IS NOT NULL THEN
    SELECT supplier_name INTO v_supplier_name FROM suppliers WHERE id = p_supplier_id;
  END IF;

  -- Process each item
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_note.items) LOOP
    v_qty  := COALESCE((v_item->>'quantity')::numeric, 0);
    v_cost := COALESCE((v_item->>'unit_price')::numeric, 0);

    SELECT id INTO v_product_id
      FROM products
     WHERE (sku IS NOT NULL AND sku = (v_item->>'sku_supplier'))
        OR lower(product_name) = lower(COALESCE(v_item->>'description', ''))
     LIMIT 1;

    IF v_product_id IS NULL THEN
      INSERT INTO products (product_name, sku, cost_price, stock_quantity, ncm, active)
      VALUES (
        COALESCE(v_item->>'description', 'Produto sem nome'),
        v_item->>'sku_supplier',
        v_cost,
        v_qty,
        v_item->>'ncm',
        true
      )
      RETURNING id INTO v_product_id;
      v_created_products := v_created_products + 1;
    ELSE
      UPDATE products
         SET stock_quantity = stock_quantity + v_qty,
             cost_price     = v_cost,
             updated_at     = now()
       WHERE id = v_product_id;
    END IF;

    INSERT INTO inventory_movements (
      product_id, movement_type, quantity_delta,
      unit_cost_snapshot, reference_type, reference_id, notes
    ) VALUES (
      v_product_id,
      'purchase',
      v_qty,
      v_cost,
      'fiscal_note',
      p_note_id,
      format('NF-e %s – %s',
        COALESCE(v_note.nfe_number, '?'),
        COALESCE(v_note.issuer_name, '?')
      )
    );
    v_movements := v_movements + 1;
  END LOOP;

  -- Create payable (optional)
  IF p_supplier_id IS NOT NULL THEN
    INSERT INTO payables (
      supplier_id, supplier_name, description,
      issue_date, due_date, amount, status, origin, notes
    ) VALUES (
      p_supplier_id,
      COALESCE(v_supplier_name, v_note.issuer_name),
      format('NF-e nº %s – %s',
        COALESCE(v_note.nfe_number, '?'),
        COALESCE(v_note.issuer_name, '?')
      ),
      CURRENT_DATE,
      (CURRENT_DATE + interval '30 days')::date,
      v_note.total_amount,
      'pending',
      'fiscal_note',
      format('Importação automática – chave %s', COALESCE(v_note.nfe_key, 'sem-chave'))
    );
  END IF;

  -- Mark as confirmed
  UPDATE fiscal_notes
     SET status = 'confirmed', confirmed_at = now(), updated_at = now()
   WHERE id = p_note_id;

  -- Audit
  INSERT INTO audit_logs (table_name, record_id, action, new_value, reason)
  VALUES (
    'fiscal_notes',
    p_note_id,
    'confirm_import',
    jsonb_build_object(
      'movements_created', v_movements,
      'products_created',  v_created_products,
      'total_amount',      v_note.total_amount,
      'supplier_id',       p_supplier_id
    ),
    'Confirmação de importação de NF-e'
  );

  RETURN jsonb_build_object(
    'success',           true,
    'movements_created', v_movements,
    'products_created',  v_created_products
  );
END;
$$;
