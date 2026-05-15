-- purchase_orders.sql — idempotente

-- 1. Tabela principal
CREATE TABLE IF NOT EXISTS purchase_orders (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  po_number        text NOT NULL UNIQUE,
  status           text NOT NULL DEFAULT 'draft'
                     CHECK (status IN ('draft','sent','partial','received','cancelled')),
  supplier_id      uuid REFERENCES suppliers(id) ON DELETE SET NULL,
  service_order_id uuid REFERENCES service_orders(id) ON DELETE SET NULL,
  expected_date    date,
  received_date    date,
  notes            text,
  total_amount     numeric(12,2) NOT NULL DEFAULT 0,
  created_by       text NOT NULL DEFAULT 'sistema',
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

-- 2. Itens
CREATE TABLE IF NOT EXISTS purchase_order_items (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  purchase_order_id uuid NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
  product_id        uuid REFERENCES products(id) ON DELETE SET NULL,
  description       text NOT NULL,
  quantity          numeric(10,3) NOT NULL DEFAULT 1,
  unit_cost         numeric(12,2) NOT NULL DEFAULT 0,
  received_qty      numeric(10,3) NOT NULL DEFAULT 0,
  created_at        timestamptz NOT NULL DEFAULT now()
);

-- 3. updated_at trigger
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

DROP TRIGGER IF EXISTS trg_po_updated_at ON purchase_orders;
CREATE TRIGGER trg_po_updated_at
  BEFORE UPDATE ON purchase_orders
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 4. RLS
ALTER TABLE purchase_orders      ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_order_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "auth_all_po"  ON purchase_orders;
DROP POLICY IF EXISTS "auth_all_poi" ON purchase_order_items;
CREATE POLICY "auth_all_po"  ON purchase_orders      FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all_poi" ON purchase_order_items FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 5. Recalc total function
CREATE OR REPLACE FUNCTION recalc_po_total(p_po_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  UPDATE purchase_orders
  SET total_amount = (
    SELECT COALESCE(SUM(quantity * unit_cost), 0)
    FROM purchase_order_items
    WHERE purchase_order_id = p_po_id
  )
  WHERE id = p_po_id;
END;
$$;

CREATE OR REPLACE FUNCTION trg_poi_recalc_total()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM recalc_po_total(OLD.purchase_order_id);
  ELSE
    PERFORM recalc_po_total(NEW.purchase_order_id);
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_poi_total ON purchase_order_items;
CREATE TRIGGER trg_poi_total
  AFTER INSERT OR UPDATE OR DELETE ON purchase_order_items
  FOR EACH ROW EXECUTE FUNCTION trg_poi_recalc_total();
