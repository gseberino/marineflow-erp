-- Guarda o que o provedor já mandava e o código descartava.
--
-- O gestor reclamou de ter que abrir o internet banking para saber de quem era cada
-- lançamento. A causa não era o banco omitir: era o tipo TypeScript do cliente declarar
-- apenas `name` e `documentNumber` dentro de payer/receiver. O JSON chegava completo e o
-- código lia dois campos — tipo parcial não filtra nada em runtime, só esconde o resto de
-- quem escreve o código.
--
-- O provedor entrega, e agora guardamos:
--   · banco, agência e conta da contraparte (routingNumber/ISPB, branchNumber, accountNumber)
--   · forma de pagamento (PIX/TED/DOC/BOLETO) — muda como se prova o pagamento
--   · a mensagem escrita pelo pagador, que costuma dizer a que a despesa se refere
--   · o ESTABELECIMENTO (merchant): razão social e CNPJ. É a peça que faltava para os
--     1.086 lançamentos de cartão que não tinham identificação nenhuma — compra em loja
--     não tem contraparte de Pix, tem merchant.
--   · parcela da compra no cartão ("3/6")
--
-- Chave Pix NÃO entra: a documentação do provedor não a expõe no extrato (só no fluxo de
-- pagamento). Preferir a ausência a inventar um campo que nunca seria preenchido.

ALTER TABLE public.bank_transactions
  ADD COLUMN IF NOT EXISTS counterparty_bank    text,
  ADD COLUMN IF NOT EXISTS counterparty_branch  text,
  ADD COLUMN IF NOT EXISTS counterparty_account text,
  ADD COLUMN IF NOT EXISTS payment_method       text,
  ADD COLUMN IF NOT EXISTS payment_reason       text,
  ADD COLUMN IF NOT EXISTS merchant_name        text,
  ADD COLUMN IF NOT EXISTS merchant_document    text,
  ADD COLUMN IF NOT EXISTS installment_label    text;

COMMENT ON COLUMN public.bank_transactions.counterparty_bank IS
  'Banco de quem recebeu/pagou (routingNumber ou ISPB). Existe para o gestor identificar sem abrir o internet banking.';
COMMENT ON COLUMN public.bank_transactions.merchant_name IS
  'Razão social do estabelecimento. Identifica melhor que o histórico: "NETFLIX ENTRETENIMENTO BRASIL" contra "EC *NETFLIX SAO PAULO BRA".';
COMMENT ON COLUMN public.bank_transactions.payment_reason IS
  'Mensagem que o pagador escreveu na transferência — costuma dizer a que a despesa se refere.';
