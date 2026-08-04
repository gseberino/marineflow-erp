-- Crédito em fatura de cartão NUNCA é receita da empresa.
--
-- O usuário percebeu olhando "PAGAMENTO RECEBIDO": 121 lançamentos somando R$ 105.672
-- que estavam na fila esperando conciliação, prontos para virar receita falsa. Eles são a
-- OUTRA PERNA do pagamento da fatura — o mesmo dinheiro que já sai da conta corrente como
-- "PGTO FATURA CARTAO". Contar os dois lados dobraria o valor e quebraria o fluxo de caixa.
--
-- A regra é estrutural, não uma lista de exceções: dinheiro de cliente não entra pelo
-- cartão de crédito DA PRÓPRIA EMPRESA. Todo crédito ali é pagamento de fatura, estorno de
-- compra (que abate despesa) ou ajuste do banco. Nenhuma delas é faturamento.

UPDATE public.bank_transactions
SET reconciled = true,
    dismissed_reason = CASE
      WHEN upper(unaccent(description)) LIKE '%PAGAMENTO RECEBIDO%'
        THEN 'Pagamento da fatura do cartão — a saída já está contada na conta corrente'
      WHEN upper(unaccent(description)) LIKE 'CREDITO DE "%'
        THEN 'Estorno de compra no cartão — abate a despesa, não é receita'
      ELSE 'Ajuste do banco no cartão (atraso, rotativo, encerramento) — não é receita'
    END
WHERE source_type = 'credit_card'
  AND transaction_type = 'credit'
  AND reconciled = false;
