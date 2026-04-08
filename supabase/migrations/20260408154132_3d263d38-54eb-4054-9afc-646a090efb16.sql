
CREATE TABLE payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  receivable_id uuid REFERENCES receivables(id) ON DELETE CASCADE,
  payable_id uuid REFERENCES payables(id) ON DELETE CASCADE,
  payment_date date NOT NULL DEFAULT CURRENT_DATE,
  amount numeric(12,2) NOT NULL,
  payment_method text NOT NULL DEFAULT 'pix'
    CHECK (payment_method IN ('pix','credit_card','debit_card','cash','bank_transfer','check')),
  installments integer DEFAULT 1,
  card_fee_percent numeric(6,4) DEFAULT 0,
  net_amount numeric(12,2),
  notes text,
  created_at timestamptz DEFAULT now(),
  CONSTRAINT chk_payment_target CHECK (
    (receivable_id IS NOT NULL AND payable_id IS NULL) OR
    (receivable_id IS NULL AND payable_id IS NOT NULL)
  )
);

CREATE TABLE bank_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transaction_date date NOT NULL,
  description text NOT NULL,
  amount numeric(12,2) NOT NULL,
  transaction_type text NOT NULL CHECK (transaction_type IN ('credit','debit')),
  bank_ref_id text,
  reconciled boolean DEFAULT false,
  reconciled_payment_id uuid REFERENCES payments(id),
  import_batch_id text,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
CREATE POLICY allow_all_payments ON payments
  AS PERMISSIVE FOR ALL TO anon, authenticated
  USING (true) WITH CHECK (true);

ALTER TABLE bank_transactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY allow_all_bank_transactions ON bank_transactions
  AS PERMISSIVE FOR ALL TO anon, authenticated
  USING (true) WITH CHECK (true);
