ALTER TABLE public.service_order_expenses
  ADD COLUMN IF NOT EXISTS supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL;

ALTER TABLE public.service_order_expenses
  ADD COLUMN IF NOT EXISTS receipt_storage_path text;

INSERT INTO storage.buckets (id, name, public)
VALUES ('expense-receipts', 'expense-receipts', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "expense_receipts_public_read" ON storage.objects;
CREATE POLICY "expense_receipts_public_read"
ON storage.objects FOR SELECT USING (bucket_id = 'expense-receipts');

DROP POLICY IF EXISTS "expense_receipts_auth_insert" ON storage.objects;
CREATE POLICY "expense_receipts_auth_insert"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'expense-receipts');

DROP POLICY IF EXISTS "expense_receipts_auth_delete" ON storage.objects;
CREATE POLICY "expense_receipts_auth_delete"
ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'expense-receipts');