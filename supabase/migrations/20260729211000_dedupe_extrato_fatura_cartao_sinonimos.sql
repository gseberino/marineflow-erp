-- Segunda passada do dedupe: o mesmo pagamento de fatura escrito de dois jeitos.
--
-- A primeira passada compara os 15 primeiros caracteres da descrição, e "FATURA DE CARTAO"
-- (como o OFX escreve) não bate com "PGTO FATURA CARTAO C6" (como o Pluggy escreve) — são
-- o mesmo fato com palavras diferentes. Aqui o critério de identidade não é o texto: é
-- ambos os lados serem reconhecidamente pagamento de fatura, na mesma data, mesmo valor e
-- mesmo sentido, pareados 1 para 1.
--
-- Desfazer: mesmo `dismissed_reason` da primeira passada.

WITH man AS (
  SELECT id, transaction_date, amount, transaction_type,
         row_number() OVER (PARTITION BY transaction_date, amount, transaction_type ORDER BY id) AS rn
  FROM public.bank_transactions
  WHERE provider = 'manual' AND reconciled = false
    AND upper(unaccent(description)) ~ 'FATURA DE CARTAO|FATURA CARTAO'
),
plu AS (
  SELECT id, transaction_date, amount, transaction_type,
         row_number() OVER (PARTITION BY transaction_date, amount, transaction_type ORDER BY id) AS rn
  FROM public.bank_transactions
  WHERE provider = 'pluggy' AND source_type = 'bank'
    AND upper(unaccent(description)) ~ 'PGTO FAT|PGTO FATURA CARTAO|FATURA CARTAO'
),
duplicadas AS (
  SELECT man.id
  FROM man
  JOIN plu ON plu.transaction_date = man.transaction_date
          AND plu.amount           = man.amount
          AND plu.transaction_type = man.transaction_type
          AND plu.rn               = man.rn
)
UPDATE public.bank_transactions bt
SET reconciled = true,
    dismissed_reason = 'Duplicata da importação manual (mesma transação veio pela sincronização automática)'
FROM duplicadas d
WHERE bt.id = d.id;
