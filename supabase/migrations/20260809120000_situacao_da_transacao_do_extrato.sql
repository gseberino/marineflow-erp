-- A situação de uma linha do extrato — o dado que faltava para desembaralhar o financeiro.
--
-- O PROBLEMA
-- `bank_transactions.reconciled` é um booleano carregando TRÊS significados diferentes.
-- Medido em produção em 09/08/2026, das 1.679 linhas com reconciled = true:
--
--     41  casaram com um pagamento que JÁ EXISTIA no sistema   → conciliação de verdade
--  1.627  apenas GERARAM um lançamento a partir da linha       → registro, não conciliação
--     11  não deixaram rastro nenhum                           → ninguém sabe o que houve
--
-- Com os três colapsados num booleano, a tela de conciliação só conseguia perguntar "já foi
-- tratada?", e por isso listava o extrato inteiro como se fosse trabalho de conciliação. A
-- separação que o mercado faz (QuickBooks: For Review → Cleared → Reconciled; NetSuite: Match
-- Bank Data vs. Reconcile Account Statement) é impossível de representar num booleano.
--
-- A SOLUÇÃO É LER, NÃO REESCREVER
-- Toda a informação necessária já está nas colunas atuais: `reconciled_payment_id` diz que
-- casou, e `payables/receivables.bank_transaction_id` diz que virou lançamento. Nada de
-- migração destrutiva, nada de coluna nova para manter em sincronia — uma view derivada, que
-- não pode divergir da verdade porque É a verdade lida de outro ângulo.
--
-- POR QUE 'sem_rastro' EXISTE
-- As 11 órfãs poderiam cair em 'lancada' por um fallback `when reconciled then ...`. Seria
-- cômodo e seria mentira: são todas ENTRADAS (R$ 51.473), e duas delas são pares duplicados
-- do mesmo valor no mesmo dia — uma vinda do OFX, outra do feed —, o que sugere que alguém
-- marcou como conciliada só para tirar da frente. Esconder isso num balde de 1.627 é garantir
-- que ninguém olhe de novo. Estado próprio, número pequeno, decisão humana.

create or replace view public.bank_transactions_situacao
with (security_invoker = on)
as
select
  bt.*,
  case
    -- Ordem importa: descarte vence tudo, e casamento real vence registro.
    when bt.dismissed_reason is not null then 'fora'
    when bt.reconciled_payment_id is not null then 'conciliada'
    when exists (select 1 from public.payables    p where p.bank_transaction_id = bt.id)
      or exists (select 1 from public.receivables r where r.bank_transaction_id = bt.id)
      then 'lancada'
    when bt.reconciled then 'sem_rastro'
    else 'nova'
  end as situacao,
  -- Cartão não é conta bancária: não tem contraparte, não sai do caixa na data da compra e
  -- pertence a uma fatura. Separar aqui evita repetir `source_type = 'credit_card'` em cada
  -- consulta da UI — e evita que alguém esqueça de repetir.
  (bt.source_type = 'credit_card') as e_cartao
from public.bank_transactions bt;

comment on view public.bank_transactions_situacao is
  'Linha do extrato com a situação real derivada: nova, lancada, conciliada, sem_rastro, fora. '
  'Substitui a leitura do booleano `reconciled`, que colapsava três significados em um.';

-- View nova no Supabase vaza por padrão: sem revogar, `anon` lê o extrato inteiro. O
-- security_invoker acima faz a RLS das tabelas base valer, mas o GRANT de leitura é separado
-- e vem aberto — os dois são necessários, e na MESMA migration.
revoke all on public.bank_transactions_situacao from anon;
grant select on public.bank_transactions_situacao to authenticated;
