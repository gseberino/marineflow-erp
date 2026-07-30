-- Preenche o nome da contraparte que o banco deixou em branco.
--
-- O QUE ACONTECEU: em 162 movimentações o provedor mandou o CNPJ/CPF da contraparte e
-- deixou o campo do nome vazio. Não é falha de leitura — nome e documento saem do MESMO
-- objeto no pacote do provedor, e não existe nenhuma linha com nome e sem documento, o que
-- só é possível se o campo veio vazio da origem.
--
-- O nome, porém, não está perdido: 119 desses documentos são de CLIENTES já cadastrados e
-- 83 de FORNECEDORES. O documento é identidade — casar por ele é mais confiável do que
-- qualquer nome que o banco pudesse ter mandado, porque não sofre com abreviação nem com
-- variação de grafia.
--
-- Só preenche o que está vazio; nome informado pelo banco nunca é sobrescrito.

UPDATE public.bank_transactions bt
SET counterparty_name = s.name
FROM public.suppliers s
WHERE bt.counterparty_name IS NULL
  AND bt.counterparty_document IS NOT NULL
  AND regexp_replace(coalesce(s.cnpj_cpf, ''), '\D', '', 'g') = bt.counterparty_document
  AND length(bt.counterparty_document) >= 11;

-- Cliente depois de fornecedor: quem paga a empresa quase sempre é cliente, mas um mesmo
-- documento pode estar nos dois cadastros, e nesse caso o vínculo de fornecedor é o que
-- interessa para classificar despesa.
UPDATE public.bank_transactions bt
SET counterparty_name = c.name
FROM public.clients c
WHERE bt.counterparty_name IS NULL
  AND bt.counterparty_document IS NOT NULL
  AND regexp_replace(coalesce(c.cpf_cnpj, ''), '\D', '', 'g') = bt.counterparty_document
  AND length(bt.counterparty_document) >= 11;

-- Sem cadastro correspondente, o próprio histórico serve — desde que não seja a narração
-- da operação. "ACRISIO LOPES CANCADO FILHO" é nome; "TRANSF ENVIADA PIX" não é.
UPDATE public.bank_transactions
SET counterparty_name = trim(regexp_replace(description, '\s{2,}[A-Z\s]{2,}\s+BRA\s*$', '', 'i'))
WHERE counterparty_name IS NULL
  AND description IS NOT NULL
  AND length(trim(description)) >= 4
  AND upper(unaccent(description)) !~ '^(TRANSF|TRANSFER|PIX |PGTO|PAGAMENTO|FATURA|SALDO|CDB|APLICACAO|RESGATE|TARIFA|IOF|JUROS|MULTA|DARF|TRIBUTO|DAS |GPS |FGTS|VENDAS|CREDITO|DEBITO|ESTORNO|DEVOLUCAO|COMPRA|SEM DESCRICAO|VALOR ADICIONADO)';
