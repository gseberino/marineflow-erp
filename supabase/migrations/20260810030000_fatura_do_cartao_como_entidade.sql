-- A fatura do cartão como entidade — F3 do plano de reorganização do financeiro.
--
-- O gestor: "as transações do cartão constam individualmente como contas a pagar, quando
-- na verdade o que deveria acontecer é identificar transações individuais como despesas e
-- suas devidas categorias, e para contas a pagar, apenas a fatura total do cartão."
--
-- ELE ESTÁ CERTO NO CONCEITO, E A IMPLEMENTAÇÃO LITERAL DOBRARIA O CUSTO
-- As 914 compras no cartão (R$ 133.971) JÁ são as despesas, lançadas por competência — que
-- é o correto e o que todo ERP faz. A fatura é essa mesma despesa sendo liquidada. Criar uma
-- conta a pagar por fatura somaria R$ 239 mil de gasto onde houve R$ 134 mil.
--
-- A separação que ele quer já existe no dado, escondida: `status = paid` é o LIVRO (o que
-- aconteceu) e `status = pending` é a OBRIGAÇÃO (o que se deve). Das 1.676 contas a pagar,
-- 1.650 são livro e 4 são obrigação. O que faltava não era um registro novo — era enxergar.
--
-- ESTA VIEW É A FATURA QUE NINGUÉM CONSEGUIA VER
-- `bill_id` chegou preenchido em 899 linhas pelo backfill e nunca foi exposto. Sem ele, uma
-- compra de cartão era um evento solto: não dava para responder "quanto fechou a fatura de
-- junho?" nem "esta saída de R$ 4.751 no banco corresponde a quais compras?".
--
-- O pagamento é SUGESTÃO, não fato. Casa por valor exato numa janela de 45 dias após a
-- última compra do ciclo. O provedor não entrega o vínculo, então afirmar seria inventar —
-- e conciliação errada com cara de certeza é pior que conciliação ausente.

create or replace view public.faturas_do_cartao
with (security_invoker = on)
as
with compras as (
  select
    bt.bill_id,
    bt.provider_account_id,
    count(*)                                   as compras,
    min(bt.transaction_date)                   as primeira_compra,
    max(bt.transaction_date)                   as ultima_compra,
    round(sum(bt.amount)::numeric, 2)          as total,
    -- Um ciclo pode ter mais de um cartão (adicional). Mostrar os finais evita a pergunta
    -- "de qual cartão é esta fatura?" que o total sozinho não responde.
    string_agg(distinct bt.card_last_digits, ', '
      order by bt.card_last_digits)            as cartoes,
    count(*) filter (where bt.installment_label is not null) as compras_parceladas
  from public.bank_transactions bt
  where bt.source_type = 'credit_card'
    and bt.transaction_type = 'debit'
    and bt.bill_id is not null
  group by bt.bill_id, bt.provider_account_id
)
select
  c.bill_id,
  c.provider_account_id,
  c.compras,
  c.compras_parceladas,
  c.primeira_compra,
  c.ultima_compra,
  c.total,
  c.cartoes,
  pg.id            as pagamento_id,
  pg.transaction_date as pagamento_data,
  pg.amount        as pagamento_valor,
  pg.description   as pagamento_descricao
from compras c
left join lateral (
  select b.id, b.transaction_date, b.amount, b.description
  from public.bank_transactions b
  where b.source_type = 'bank'
    and b.transaction_type = 'debit'
    -- Só linhas que o próprio banco diz serem fatura de cartão. Sem este filtro, qualquer
    -- saída de valor igual viraria "o pagamento da fatura".
    and (b.description ilike '%FAT%CARTAO%'
      or b.description ilike '%FATURA%CART%'
      or b.description ilike '%PGTO%CARTAO%'
      or b.description = 'DEBITO DE CARTAO')
    -- Valor exato: um centavo de diferença já é outra coisa.
    and round(b.amount::numeric, 2) = c.total
    and b.transaction_date >= c.ultima_compra
    and b.transaction_date <= c.ultima_compra + interval '45 days'
  order by b.transaction_date
  limit 1
) pg on true;

comment on view public.faturas_do_cartao is
  'Uma linha por fatura de cartao (bill_id): compras, periodo, total, cartoes do ciclo e o pagamento no extrato quando o valor casa exatamente. O pagamento e sugestao — o provedor nao entrega esse vinculo.';

-- View nova vaza por padrão: security_invoker acima faz a RLS das tabelas base valer, mas o
-- GRANT de leitura é separado e vem aberto. Os dois, na mesma migration.
revoke all on public.faturas_do_cartao from anon;
grant select on public.faturas_do_cartao to authenticated;
