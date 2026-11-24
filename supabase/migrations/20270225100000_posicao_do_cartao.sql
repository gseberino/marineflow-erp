-- Posição do cartão de crédito, como o BANCO informa (24/11/2026).
--
-- POR QUE ISTO EXISTE: a fila de pagamentos da semana (20270224100000) só tem contas a pagar. A fatura do cartão é a
-- maior saída que falta nela, e o sistema não tem de onde tirá-la: medido em 24/11, não existe em nenhuma tabela o
-- vencimento, o fechamento, o valor em aberto nem o que já foi pago de uma fatura. A view faturas_do_cartao só soma
-- compras por código de fatura (casou pagamento em 1 de 30), e a previsão de caixa da tela INFERE a data pelo dia em que
-- o dono costuma pagar. Como ele paga a fatura em pedaços (20 pagamentos num ciclo do C6), "compras menos pagamentos"
-- não dá o que falta. Afirmar "vence dia X, R$ Y" com isso seria inventar.
--
-- O provedor entrega esses números e a sincronização nunca os guardou: a conta de crédito vem com um saldo e os dados
-- de crédito (vencimento, mínimo, limite), e há uma lista de faturas (vencimento, total, pagamentos). O que o saldo quer
-- dizer nestes dois bancos (fatura aberta ou limite usado, que inclui parcela futura) ainda não se sabe: por isso a
-- coluna se chama saldo_informado, e não fatura.
-- Esta migration só cria ONDE guardar. Nada lê estas tabelas ainda: primeiro se vê o dado real de cada cartão, depois se
-- decide a linha da fila (regra financeira se mede no dado real antes de valer).
--
-- Sem dados: duas tabelas vazias. Só o servidor lê e grava (o conteúdo cru do banco fica aqui).

-- 1. O retrato do cartão a cada sincronização -----------------------------------------------------------------------
-- Uma linha por conta de crédito por sincronização (como bank_balance_checks): a série mostra como o número anda
-- quando entra compra e quando entra pagamento, que é o que falta saber para confiar nele.
create table if not exists public.cartao_posicoes (
  id                  bigint generated always as identity primary key,
  bank_connection_id  uuid not null references public.bank_connections(id) on delete cascade,
  provider_account_id text not null,
  nome                text,
  final               text,
  saldo_informado     numeric(14,2),
  vencimento          date,
  fechamento          date,
  minimo              numeric(14,2),
  limite              numeric(14,2),
  limite_disponivel   numeric(14,2),
  situacao            text,
  dados               jsonb,
  faturas_lidas       integer,
  faturas_erro        text,
  faturas_vistas      jsonb,
  provedor_atualizado_em timestamptz,
  lido_em             timestamptz not null default now()
);

comment on table public.cartao_posicoes is
  'O que o banco informou do cartão de crédito em cada sincronização (saldo da conta de crédito, vencimento, mínimo, limite e o estado das faturas). Uma linha por conta de crédito por sincronização. Só o servidor lê e grava.';
comment on column public.cartao_posicoes.saldo_informado is
  'O saldo que o provedor devolve para a conta de crédito, como veio. Pela documentação é a fatura aberta ainda não paga; em conexão de Open Finance (o caso do C6 e do Nubank) é o limite usado, que inclui parcela futura. NÃO é "quanto falta pagar" até se conferir no dado real.';
comment on column public.cartao_posicoes.dados is
  'Os dados de crédito crus que o provedor mandou, para conferir o que cada banco preenche.';
comment on column public.cartao_posicoes.faturas_erro is
  'Por que a lista de faturas não veio nesta sincronização (nulo = veio). O retrato é gravado mesmo assim.';
comment on column public.cartao_posicoes.faturas_vistas is
  'O estado das faturas NESTA leitura (código, vencimento, total, mínimo, pago, encargos, quantos pagamentos e o último): a tabela das faturas é regravada a cada passagem, e é aqui que fica a série. Só as sem vencimento, a vencer ou vencidas há até 60 dias. Nulo = a lista não veio.';
comment on column public.cartao_posicoes.provedor_atualizado_em is
  'Quando o provedor foi ao banco pela última vez (ele vai uma vez por dia; a sincronização lê três). lido_em é quando o sistema leu: leituras com o mesmo provedor_atualizado_em repetem o mesmo dado.';

create index if not exists cartao_posicoes_conta_lido_em
  on public.cartao_posicoes (provider_account_id, lido_em desc);

-- 2. As faturas que o banco emitiu ----------------------------------------------------------------------------------
-- Uma linha por fatura (o código é o mesmo bill_id das compras em bank_transactions). A sincronização regrava a cada
-- passagem: o total e os pagamentos de uma fatura mudam depois de fechada.
create table if not exists public.cartao_faturas_do_banco (
  bill_id             text primary key,
  bank_connection_id  uuid not null references public.bank_connections(id) on delete cascade,
  provider_account_id text not null,
  vencimento          date,
  fechamento          date,
  total               numeric(14,2),
  minimo              numeric(14,2),
  pago                numeric(14,2),
  encargos            numeric(14,2),
  dados               jsonb,
  visto_em            timestamptz not null default now(),
  lido_em             timestamptz not null default now()
);

comment on table public.cartao_faturas_do_banco is
  'As faturas do cartão como o banco as emitiu (vencimento, total, mínimo, pagamentos, encargos). Regravada a cada sincronização. Só o servidor lê e grava.';
comment on column public.cartao_faturas_do_banco.pago is
  'Soma dos pagamentos que o banco lista NESTA fatura (nulo = o banco não mandou a lista, ou algum item veio sem valor). Pela documentação, os pagamentos listados numa fatura quitam a ANTERIOR: total menos pago na mesma linha mistura duas faturas. Não usar como "quanto falta" sem conferir no dado real.';
comment on column public.cartao_faturas_do_banco.visto_em is
  'Quando a fatura apareceu pela primeira vez. Mostra com que antecedência do vencimento o banco a entrega.';

create index if not exists cartao_faturas_do_banco_conta_vencimento
  on public.cartao_faturas_do_banco (provider_account_id, vencimento desc);

-- 3. Só o servidor (sem policy: RLS ligada fecha para todos os outros; revogar dos três e provar no teste) ----------
alter table public.cartao_posicoes enable row level security;
alter table public.cartao_faturas_do_banco enable row level security;

revoke all on table public.cartao_posicoes from public, anon, authenticated;
revoke all on table public.cartao_faturas_do_banco from public, anon, authenticated;
grant select, insert, update, delete on table public.cartao_posicoes to service_role;
grant select, insert, update, delete on table public.cartao_faturas_do_banco to service_role;
