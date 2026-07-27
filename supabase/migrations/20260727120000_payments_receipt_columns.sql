-- ═══════════════════════════════════════════════════════════════
-- Comprovante de pagamento em payments (usado no sinal — RegisterDepositDialog)
--
-- Aditivo e reversível: o diálogo "Receber sinal" passa a permitir anexar o comprovante
-- (PIX/transferência) ao pagamento. O arquivo vai para o bucket 'expense-receipts' (já
-- existente), caminho deposits/<os_id>/<uuid>. Espelha o padrão já usado em
-- service_order_expenses (receipt_url + receipt_storage_path).
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS receipt_url          text,
  ADD COLUMN IF NOT EXISTS receipt_storage_path text;

COMMENT ON COLUMN public.payments.receipt_url          IS 'URL pública do comprovante anexado (bucket expense-receipts).';
COMMENT ON COLUMN public.payments.receipt_storage_path IS 'Caminho do comprovante no storage (para remoção/gestão).';
