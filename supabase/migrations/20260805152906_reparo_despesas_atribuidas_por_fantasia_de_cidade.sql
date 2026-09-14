-- Recuperada do transcript da sessão (C--Users-PC/374b5203-fb74-4f92-b284-ba488b300c96.jsonl, 2026-08-05T15:28:59.787Z) em 14/09/2026 —
-- a migration foi aplicada em produção pela ferramenta MCP apply_migration, que registrou a
-- versão 20260805152906 sem gravar arquivo no repositório (MF-AUD-058). Conteúdo abaixo é o que
-- foi enviado ao banco naquela chamada.

-- Reparo: 82 despesas foram atribuídas ao fornecedor errado.
--
-- O cadastro da Coremma tinha nome fantasia "Itajai" — a CIDADE. Como o casamento por nome
-- aceitava qualquer substring, todo estabelecimento de Itajaí que aparece na fatura casou
-- com ela. Nenhuma das 82 é de fato da Coremma. Com o fornecedor errado veio também o
-- histórico aprendido dele, que sobrepôs a categoria certa — então categoria E fornecedor
-- estão errados, e corrigir só um dos dois deixaria metade do engano de pé.
--
-- Enquanto existirem, elas ainda ENSINAM o motor: o histórico por fornecedor lê os
-- lançamentos e conclui "Coremma é sempre aquela categoria". O engano se reproduz.
--
-- Aqui elas voltam para a fila, para serem reclassificadas pelo motor já corrigido. Nada
-- se perde: a cópia fica na tabela de reparo e as transações bancárias, que são o fato,
-- nunca foram tocadas.

CREATE TABLE IF NOT EXISTS public.reparo_coremma_20260805 AS
SELECT p.*, now() AS reparado_em
FROM public.payables p
WHERE p.supplier_id = '90245354-45a5-48b7-a833-6992db49dea4'
  AND p.origin = 'bank_reconciliation';

-- Tabela nova no Supabase é legível por anônimo até que se diga o contrário, e esta guarda
-- valores e fornecedores. Fecha antes de existir para alguém.
ALTER TABLE public.reparo_coremma_20260805 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.reparo_coremma_20260805 FROM anon, authenticated;

COMMENT ON TABLE public.reparo_coremma_20260805 IS
  'Cópia das 82 despesas atribuídas por engano à Coremma (nome fantasia "Itajai" casava com qualquer estabelecimento de Itajaí). Devolvidas à fila em 05/08/2026 para reclassificação.';

-- As transações voltam a ser pendentes: é o que as faz reaparecer na caixa de entrada.
UPDATE public.bank_transactions b
   SET reconciled = false, dismissed_reason = NULL
 WHERE b.id IN (
   SELECT bank_transaction_id FROM public.reparo_coremma_20260805
    WHERE bank_transaction_id IS NOT NULL
 );

-- A decisão antiga não some: fica registrada como superada, com o motivo escrito.
UPDATE public.finance_review_queue q
   SET status = 'superseded',
       decision_note = 'Reparo 05/08/2026: fornecedor atribuído por engano (nome fantasia "Itajai" no cadastro da Coremma). Devolvida à fila para reclassificação.'
 WHERE q.created_payable_id IN (SELECT id FROM public.reparo_coremma_20260805);

DELETE FROM public.payables p
 WHERE p.id IN (SELECT id FROM public.reparo_coremma_20260805);
