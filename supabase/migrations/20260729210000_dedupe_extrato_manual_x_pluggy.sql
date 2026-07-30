-- Remove da fila o extrato que entrou duas vezes: uma pelo arquivo OFX importado à mão e
-- outra pela sincronização automática da MESMA conta do C6.
--
-- POR QUE O DEDUPE EXISTENTE NÃO PEGOU: ele compara `bank_ref_id`, e cada fonte inventa o
-- seu — o parser de arquivo gera um ULID local, o Pluggy devolve o UUID dele. São ids
-- diferentes para o mesmo fato, então as duas versões passaram.
--
-- POR QUE ISTO É URGENTE: a caixa de entrada financeira propõe um lançamento por
-- transação. Com a linha duplicada, o gestor aprovaria a MESMA despesa duas vezes, e o
-- resultado do mês nasceria errado sem nenhum sinal de que algo está errado.
--
-- CRITÉRIO (conservador de propósito — na dúvida, deixa passar em vez de esconder):
--   · mesma data exata, mesmo valor, mesmo sentido (entrada/saída);
--   · mesma natureza de conta (só `bank` — a perna do cartão é outro fato, não cópia);
--   · descrição compatível nos 15 primeiros caracteres, depois de tirar o prefixo
--     "PIX RECEBIDO DE", que só a importação manual escreve;
--   · pareamento 1 para 1 (row_number), senão três pedágios de R$ 5,70 no mesmo dia
--     casariam todos com o primeiro.
--
-- A cópia manual é a que sai, não a do Pluggy: a automática traz nome e CNPJ da
-- contraparte, que é justamente o dado de que a classificação precisa.
--
-- NADA É APAGADO. As linhas ficam marcadas com motivo próprio, e desfazer é:
--   UPDATE bank_transactions SET reconciled=false, dismissed_reason=NULL
--    WHERE dismissed_reason = 'Duplicata da importação manual (mesma transação veio pela sincronização automática)';

WITH norm AS (
  SELECT id, provider, source_type, transaction_date, amount, transaction_type, reconciled,
         trim(regexp_replace(upper(unaccent(coalesce(description, ''))),
                             '^(PIX RECEBIDO DE|PIX ENVIADO PARA|PIX)\s+', '')) AS d
  FROM public.bank_transactions
),
man AS (
  SELECT *, row_number() OVER (PARTITION BY transaction_date, amount, transaction_type ORDER BY id) AS rn
  FROM norm WHERE provider = 'manual' AND reconciled = false
),
plu AS (
  SELECT *, row_number() OVER (PARTITION BY transaction_date, amount, transaction_type ORDER BY id) AS rn
  FROM norm WHERE provider = 'pluggy' AND source_type = 'bank'
),
duplicadas AS (
  SELECT man.id
  FROM man
  JOIN plu ON plu.transaction_date = man.transaction_date
          AND plu.amount           = man.amount
          AND plu.transaction_type = man.transaction_type
          AND plu.rn               = man.rn
  WHERE left(plu.d, 15) = left(man.d, 15)
)
UPDATE public.bank_transactions bt
SET reconciled = true,
    dismissed_reason = 'Duplicata da importação manual (mesma transação veio pela sincronização automática)'
FROM duplicadas d
WHERE bt.id = d.id;
