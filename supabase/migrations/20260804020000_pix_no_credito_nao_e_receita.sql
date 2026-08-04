-- "Valor adicionado na conta por cartão de crédito" não é receita — é dívida.
--
-- É o "Pix no Crédito" do Nubank: quando não há saldo, o banco adiciona o valor na conta
-- usando o LIMITE DO CARTÃO, o Pix sai em seguida, e a cobrança vai para a fatura.
--
-- Os dados confirmam sem margem: as 9 entradas têm, cada uma, uma saída de valor IDÊNTICO
-- no MESMO DIA. Entra e sai no mesmo instante — o dinheiro nunca foi da empresa.
--
-- Contar a entrada como receita inventaria faturamento. E o gasto verdadeiro já aparece
-- duas vezes no caminho: na saída do Pix e no pagamento da fatura. São três registros para
-- um único gasto se ninguém separar as pernas.

UPDATE public.bank_transactions
SET reconciled = true,
    dismissed_reason = 'Limite do cartão adicionado à conta (Pix no Crédito) — é dívida, não receita; a despesa real é a saída correspondente'
WHERE transaction_type = 'credit'
  AND reconciled = false
  AND (
    upper(unaccent(description)) LIKE '%VALOR ADICIONADO NA CONTA POR CARTAO%'
    OR upper(unaccent(description)) LIKE '%PIX NO CREDITO%'
  );
