-- Recuperada do transcript da sessão (C--Users-PC/374b5203-fb74-4f92-b284-ba488b300c96.jsonl, 2026-08-06T09:28:32.889Z) em 14/09/2026 —
-- a migration foi aplicada em produção pela ferramenta MCP apply_migration, que registrou a
-- versão 20260806092842 sem gravar arquivo no repositório (MF-AUD-058). Conteúdo abaixo é o que
-- foi enviado ao banco naquela chamada.

-- "Ignorada" era um sumiço, não um estado.
--
-- 380 transações (R$ 370 mil) saíram de vista com um texto solto em `dismissed_reason` e
-- nada mais: sem quem, sem quando, sem tipo, sem como voltar atrás. Cada caso estava certo
-- — duplicata, fatura de cartão, transferência entre contas, parcela de compra parcelada —
-- e o conjunto era inauditável. Um sistema que tira linhas de vista sem um livro do porquê
-- não é confiável por mais correto que cada decisão tenha sido.
--
-- Aqui a saída de "pendente" passa a ter identidade: QUEM, QUANDO e DE QUE TIPO. É o que
-- permite listar, conferir e desfazer.

ALTER TABLE public.bank_transactions
  ADD COLUMN IF NOT EXISTS dismissed_at timestamptz,
  ADD COLUMN IF NOT EXISTS dismissed_by uuid REFERENCES public.app_users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS dismissed_kind text;

COMMENT ON COLUMN public.bank_transactions.dismissed_kind IS
  'Por que saiu da fila: duplicata | fatura_cartao | transferencia | mecanica_cartao | parcela | manual. '
  'Sem CHECK de propósito — lista fechada faz um tipo novo falhar em silêncio no lugar de aparecer.';

-- Classifica o que já existe pelo texto que foi gravado na época.
UPDATE public.bank_transactions SET dismissed_kind = CASE
  WHEN dismissed_reason ILIKE '%duplicata%'                THEN 'duplicata'
  WHEN dismissed_reason ILIKE '%fatura do cart%'           THEN 'fatura_cartao'
  WHEN dismissed_reason ILIKE '%transfer%ncia entre contas%' THEN 'transferencia'
  WHEN dismissed_reason ILIKE '%parcela da compra%'        THEN 'parcela'
  WHEN dismissed_reason ILIKE '%pix no cr%'
    OR dismissed_reason ILIKE '%ajuste do banco%'
    OR dismissed_reason ILIKE '%estorno de compra%'        THEN 'mecanica_cartao'
  ELSE 'manual'
END
WHERE dismissed_reason IS NOT NULL AND dismissed_kind IS NULL;

-- A aba das ignoradas filtra por aqui; sem índice ela varre a tabela inteira a cada abertura.
CREATE INDEX IF NOT EXISTS idx_bank_transactions_ignoradas
  ON public.bank_transactions (dismissed_kind, transaction_date DESC)
  WHERE dismissed_reason IS NOT NULL;
