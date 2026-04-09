
ALTER TABLE payables
  ADD COLUMN IF NOT EXISTS origin text DEFAULT 'manual',
  ADD COLUMN IF NOT EXISTS bank_transaction_id uuid REFERENCES bank_transactions(id);

ALTER TABLE payables ADD CONSTRAINT chk_payables_origin CHECK (origin IN ('manual', 'service_order_expense', 'bank_reconciliation'));

UPDATE payables SET origin = 'service_order_expense' 
  WHERE linked_service_order_id IS NOT NULL AND origin = 'manual';
