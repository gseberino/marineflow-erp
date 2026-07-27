-- Extrato bancário: deduplicação por identificador do banco + campos de enriquecimento.
--
-- Contexto: a importação de extrato (OFX/CSV) já existia e gravava o FITID em
-- bank_ref_id, mas nada impedia a mesma transação de entrar duas vezes — reimportar
-- um período sobreposto duplicava tudo. O FITID é único e estável por conta no padrão
-- OFX, então ele é a chave natural de deduplicação.
--
-- Índice único NÃO-parcial de propósito: em Postgres NULL nunca conflita com NULL,
-- então linhas sem identificador (CSV, que não tem FITID) continuam entrando
-- normalmente, enquanto linhas com FITID ficam protegidas. Isso também permite ao
-- PostgREST inferir o índice num upsert (on_conflict), o que um índice parcial impediria.
--
-- Seguro de aplicar: bank_transactions está vazia (0 linhas) e todas as mudanças são
-- aditivas — nenhuma coluna existente é alterada ou removida.

-- source_type entra na chave de dedupe, então não pode ser nulo (extrato de conta e
-- fatura de cartão podem, em tese, repetir identificador).
ALTER TABLE public.bank_transactions
  ALTER COLUMN source_type SET DEFAULT 'bank';
UPDATE public.bank_transactions SET source_type = 'bank' WHERE source_type IS NULL;
ALTER TABLE public.bank_transactions
  ALTER COLUMN source_type SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS bank_transactions_bank_ref_unique
  ON public.bank_transactions (bank_ref_id, source_type);

COMMENT ON INDEX public.bank_transactions_bank_ref_unique IS
  'Dedupe de extrato: FITID (OFX) ou id da transação do provedor. NULLs não conflitam, então CSV sem identificador continua sendo aceito.';

-- ── Enriquecimento (usado pela conciliação automática e pelas futuras integrações) ──
-- pix_end_to_end_id é o casamento mais forte que existe para Pix: identificador único
-- da transação no SPI, presente tanto no extrato quanto no retorno de cobrança.
ALTER TABLE public.bank_transactions
  ADD COLUMN IF NOT EXISTS pix_end_to_end_id   text,
  ADD COLUMN IF NOT EXISTS counterparty_name   text,
  ADD COLUMN IF NOT EXISTS counterparty_document text,
  ADD COLUMN IF NOT EXISTS balance_after       numeric(14,2),
  ADD COLUMN IF NOT EXISTS provider            text NOT NULL DEFAULT 'manual',
  ADD COLUMN IF NOT EXISTS dismissed_reason    text;

COMMENT ON COLUMN public.bank_transactions.provider IS
  'Origem da linha: manual (importação OFX/CSV) ou o provedor que a sincronizou (pluggy, cora, c6, inter).';
COMMENT ON COLUMN public.bank_transactions.dismissed_reason IS
  'Motivo informado ao ignorar a transação na tela de conciliação.';

CREATE INDEX IF NOT EXISTS idx_bank_transactions_pix_e2e
  ON public.bank_transactions (pix_end_to_end_id)
  WHERE pix_end_to_end_id IS NOT NULL;

-- Conciliação e listagem sempre filtram por pendentes ordenadas por data.
CREATE INDEX IF NOT EXISTS idx_bank_transactions_pendentes
  ON public.bank_transactions (reconciled, transaction_date DESC);
