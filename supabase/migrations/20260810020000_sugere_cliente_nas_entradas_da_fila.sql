-- Preenche o cliente sugerido nas entradas que JÁ estão na fila.
--
-- POR QUE PRECISA DE UM REPARO, E NÃO SÓ DA CORREÇÃO NO MOTOR
-- O gerador de propostas agora sugere o cliente pelo CPF/CNPJ do extrato — mas ele ignora,
-- de propósito, toda transação que já tem proposta na fila (`naFila`), senão cada chamada
-- criaria propostas duplicadas. As 87 entradas que nasceram sem cliente ficariam sem ele
-- para sempre, e cada uma exigiria uma escolha manual só para poder ser aprovada.
--
-- É SUGESTÃO, NÃO LANÇAMENTO
-- Escreve apenas em `finance_review_queue.suggested_client_id`, de propostas PENDENTES.
-- Nada é lançado, nenhum recebível é criado, e o gestor troca no seletor se discordar.
-- Reversível com um update para null.
--
-- DOCUMENTO É IDENTIDADE; NOME É APROXIMAÇÃO
-- O casamento por nome exige igualdade EXATA e nome ÚNICO no cadastro. Nunca "contém":
-- foi o casamento por substring que fez todo estabelecimento de Itajaí virar o fornecedor
-- "Coremma" e atribuiu 160 despesas ao errado, sem uma linha de erro. E nome repetido no
-- cadastro sai fora — escolher um dos dois seria sorteio.
--
-- Medido antes de aplicar: 87 entradas sem cliente, 24 casam por documento e 5 por nome.
-- As 58 restantes continuam pedindo a escolha, que é o correto: não há evidência para elas.

with nomes_unicos as (
  -- Nome que aparece uma vez só. Repetido não entra: ambiguidade não se resolve por sorteio.
  -- `array_agg[1]` em vez de min(): não existe min(uuid), e como o HAVING já garante uma
  -- linha só, pegar a primeira é exato — não é escolha arbitrária disfarçada de agregação.
  select upper(trim(name)) as nome, (array_agg(id))[1] as id
  from public.clients
  group by 1
  having count(*) = 1
),
casamento as (
  select
    q.id as proposta_id,
    coalesce(
      (select c.id from public.clients c
        where c.cpf_cnpj is not null
          and regexp_replace(c.cpf_cnpj, '\D', '', 'g')
              = regexp_replace(coalesce(bt.counterparty_document, ''), '\D', '', 'g')
          and length(regexp_replace(coalesce(bt.counterparty_document, ''), '\D', '', 'g')) >= 11
        limit 1),
      (select n.id from nomes_unicos n
        where n.nome = upper(trim(bt.counterparty_name)))
    ) as cliente_id
  from public.finance_review_queue q
  join public.bank_transactions bt on bt.id = q.bank_transaction_id
  where q.status = 'pending'
    and q.kind = 'create_receivable'
    and q.suggested_client_id is null
)
update public.finance_review_queue q
set suggested_client_id = casamento.cliente_id,
    updated_at = now()
from casamento
where q.id = casamento.proposta_id
  and casamento.cliente_id is not null;
