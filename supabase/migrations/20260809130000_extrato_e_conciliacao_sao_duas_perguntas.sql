-- Duas telas, duas perguntas, dois modelos de leitura.
--
-- "Conciliação bancária eu faço com tudo aquilo que eu lancei no sistema e vou comparar com
--  o extrato. E não o inverso." — o gestor, e ele está certo.
--
-- Hoje uma tela só tenta responder as duas perguntas partindo do mesmo lugar (o extrato), e
-- por isso não responde bem nenhuma. Cada view abaixo parte do lado certo:
--
--   extrato_a_tratar        parte do EXTRATO   → "o que o banco trouxe e eu não registrei?"
--   conciliacao_lancamentos parte do LANÇAMENTO → "o que eu registrei bate com o banco?"
--
-- É a separação que QuickBooks (For Review × Reconcile) e NetSuite (Match Bank Data ×
-- Reconcile Account Statement) fazem há anos.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. EXTRATO A TRATAR — a fila, que é o extrato, não a fila de propostas
-- ─────────────────────────────────────────────────────────────────────────────
--
-- A CAIXA DE ENTRADA MOSTRAVA 2 DE 101.
-- Ela lia `finance_review_queue`, ou seja, listava PROPOSTAS — e só existe proposta para
-- débito. Medido em 09/08/2026, do que precisa de atenção:
--
--     87 créditos (R$ 628 mil)  sem proposta  → invisíveis na caixa, reapareciam na conciliação
--      3 débitos de conta        2 com proposta
--      2 débitos de cartão      sem proposta
--     11 sem rastro             sem proposta
--
-- A proposta da IA é um ATRIBUTO da linha, não a fonte da lista. Invertendo isso, a fila
-- passa a ser o extrato — e o crédito de R$ 628 mil deixa de sumir.

create or replace view public.extrato_a_tratar
with (security_invoker = on)
as
select
  v.id,
  v.transaction_date,
  v.description,
  v.amount,
  v.transaction_type,
  v.source_type,
  v.situacao,
  v.e_cartao,
  v.bank_ref_id,
  v.balance_after,
  v.tx_status,
  -- Quem está do outro lado (conta bancária: Pix, TED, boleto)
  v.counterparty_name,
  v.counterparty_document,
  v.counterparty_bank,
  v.payment_method,
  v.payment_reason,
  -- Quem está do outro lado (cartão: não há CNPJ, a identidade é o estabelecimento + ramo)
  v.merchant_name,
  v.merchant_document,
  v.payee_mcc,
  v.merchant_category,
  v.provider_category,
  v.card_last_digits,
  v.installment_label,
  v.bill_id,
  -- A proposta da IA, quando existe. LATERAL com LIMIT 1 de propósito: hoje não há transação
  -- com duas propostas pendentes, mas nada no banco impede — e uma linha duplicada na tela
  -- vira lançamento em dobro.
  q.id                  as proposta_id,
  q.title               as proposta_titulo,
  q.reasoning           as proposta_motivo,
  q.confidence          as proposta_confianca,
  q.suggested_category  as proposta_categoria,
  q.suggested_supplier_id as proposta_fornecedor_id,
  q.suggested_client_id   as proposta_cliente_id,
  q.suggested_payee_id    as proposta_favorecido_id,
  q.suggested_description as proposta_descricao,
  q.dre_group           as proposta_dre_group,
  q.applied_rule_id     as proposta_regra_id
from public.bank_transactions_situacao v
left join lateral (
  select fq.*
  from public.finance_review_queue fq
  where fq.bank_transaction_id = v.id
    and fq.status = 'pending'
  order by fq.created_at desc
  limit 1
) q on true
where v.situacao in ('nova', 'sem_rastro');

comment on view public.extrato_a_tratar is
  'A fila do Extrato: linhas que o banco trouxe e ainda nao viraram lancamento, com a proposta da IA anexada quando existe. A proposta e atributo da linha, nao a fonte da lista.';

revoke all on public.extrato_a_tratar from anon;
grant select on public.extrato_a_tratar to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. CONCILIAÇÃO — parte do lançamento, que é o lado que o gestor descreveu
-- ─────────────────────────────────────────────────────────────────────────────
--
-- O QUE ESTA VIEW REVELA DE IMEDIATO: nenhum dos 23 recebíveis tem `bank_transaction_id`.
-- Dezesseis deles estão marcados como PAGOS. Ou seja: o dinheiro entrou no banco, alguém deu
-- baixa no sistema, e os dois lados nunca se encontraram. É exatamente a conciliação que
-- nunca aconteceu — e é o outro lado dos 87 créditos parados no extrato.

create or replace view public.conciliacao_lancamentos
with (security_invoker = on)
as
select
  'payable'::text            as lado,
  p.id,
  p.description,
  p.amount,
  p.status,
  p.due_date,
  p.issue_date,
  p.supplier_name            as contraparte,
  p.expense_category         as categoria,
  p.bank_transaction_id,
  case when p.bank_transaction_id is not null
       then 'conciliado' else 'sem_extrato' end as situacao,
  bt.transaction_date        as extrato_data,
  bt.amount                  as extrato_valor,
  bt.description             as extrato_descricao,
  -- Divergência entre o que registrei e o que o banco diz. Só faz sentido quando há par.
  case when p.bank_transaction_id is not null
       then round((p.amount - bt.amount)::numeric, 2) end as diferenca
from public.payables p
left join public.bank_transactions bt on bt.id = p.bank_transaction_id

union all

select
  'receivable'::text,
  r.id,
  r.description,
  r.amount,
  r.status,
  r.due_date,
  r.issue_date,
  c.name,
  r.category,
  r.bank_transaction_id,
  case when r.bank_transaction_id is not null
       then 'conciliado' else 'sem_extrato' end,
  bt.transaction_date,
  bt.amount,
  bt.description,
  case when r.bank_transaction_id is not null
       then round((r.amount - bt.amount)::numeric, 2) end
from public.receivables r
left join public.bank_transactions bt on bt.id = r.bank_transaction_id
left join public.clients c on c.id = r.client_id;

comment on view public.conciliacao_lancamentos is
  'Conciliacao vista do lado certo: um lancamento por linha (pagar ou receber), com a linha do extrato que casou e a diferenca. situacao = conciliado | sem_extrato.';

revoke all on public.conciliacao_lancamentos from anon;
grant select on public.conciliacao_lancamentos to authenticated;
