-- ─────────────────────────────────────────────────────────────────────────────
-- Migration: plano de pagamento definido NA EMISSÃO da NF-e avulsa
--   issued_fiscal_documents.payment_terms (jsonb): forma + à vista/parcelado +
--   parcelas com vencimentos, escolhidos direto no diálogo de emissão. Depois é
--   reaproveitado ao "Baixar estoque + recebível" (pré-preenche as parcelas) e,
--   quando a Contora confirmar o grupo cobr/dup, alimenta as duplicatas no XML.
-- Aditiva e reversível.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.issued_fiscal_documents
  ADD COLUMN IF NOT EXISTS payment_terms jsonb;

COMMENT ON COLUMN public.issued_fiscal_documents.payment_terms IS
  'Plano de pagamento da emissão: {mode: avista|parcelado, method, installments:[{due_date,amount,method}]}. Reaproveitado nos recebíveis.';
