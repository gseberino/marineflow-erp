
-- 1. Operational expenses table
CREATE TABLE service_order_expenses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  service_order_id uuid REFERENCES service_orders(id) ON DELETE CASCADE,
  category text NOT NULL,
  description text NOT NULL,
  amount numeric(12,2) NOT NULL,
  currency text DEFAULT 'BRL',
  expense_date date NOT NULL DEFAULT CURRENT_DATE,
  paid_by text NOT NULL DEFAULT 'company'
    CHECK (paid_by IN ('company', 'technician')),
  technician_user_id uuid REFERENCES app_users(id),
  reimbursed boolean DEFAULT false,
  reimbursed_at timestamptz,
  reimbursed_payment_id uuid REFERENCES payments(id),
  receipt_url text,
  linked_payable_id uuid REFERENCES payables(id),
  notes text,
  created_by uuid REFERENCES app_users(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE service_order_expenses ENABLE ROW LEVEL SECURITY;

CREATE POLICY allow_all_service_order_expenses ON service_order_expenses
  AS PERMISSIVE FOR ALL TO anon, authenticated
  USING (true) WITH CHECK (true);

CREATE TRIGGER set_updated_at_so_expenses
  BEFORE UPDATE ON service_order_expenses
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 2. Add operational_cost_total to service_orders
ALTER TABLE service_orders
  ADD COLUMN IF NOT EXISTS operational_cost_total numeric(12,2) DEFAULT 0;

-- 3. Add source_type to bank_transactions
ALTER TABLE bank_transactions
  ADD COLUMN IF NOT EXISTS source_type text DEFAULT 'bank';

-- 4. Add direct SO link to bank_transactions
ALTER TABLE bank_transactions
  ADD COLUMN IF NOT EXISTS reconciled_service_order_id uuid REFERENCES service_orders(id);
