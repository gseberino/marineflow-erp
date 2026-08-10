-- Escreve o MOTIVO de cada cliente sugerido pelo reparo anterior.
--
-- O reparo preencheu `suggested_client_id` em 29 entradas, mas o campo `reasoning` continuou
-- falando só da categoria. Um cliente que aparece preenchido sem explicação é indistinguível
-- de um palpite — e este sistema já foi mordido por classificação silenciosa (o nome fantasia
-- "Itajai" atribuiu 160 despesas ao fornecedor errado sem uma linha de erro em lugar nenhum).
--
-- A distinção importa para o gestor saber quanto revisar:
--   documento  → identidade. CPF/CNPJ do extrato bate com o cadastro. Confiável.
--   nome exato → aproximação. Duas empresas podem ter o mesmo nome, e o pagador pode ser
--                uma pessoa pagando pela empresa. Pede conferência.

update public.finance_review_queue q
set reasoning = trim(both ' ·' from
      coalesce(q.reasoning, '') || ' · ' ||
      case
        when regexp_replace(coalesce(bt.counterparty_document, ''), '\D', '', 'g') =
             regexp_replace(coalesce(c.cpf_cnpj, ''), '\D', '', 'g')
         and length(regexp_replace(coalesce(c.cpf_cnpj, ''), '\D', '', 'g')) >= 11
        then 'Cliente reconhecido pelo CPF/CNPJ: ' || c.name
        else 'Nome idêntico ao do cliente ' || c.name || ' — confira antes de aprovar'
      end)
from public.bank_transactions bt, public.clients c
where bt.id = q.bank_transaction_id
  and c.id = q.suggested_client_id
  and q.status = 'pending'
  and q.kind = 'create_receivable'
  and q.reasoning not like '%Cliente reconhecido%'
  and q.reasoning not like '%Nome idêntico ao do cliente%';
