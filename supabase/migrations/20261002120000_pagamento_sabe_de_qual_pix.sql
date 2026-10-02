-- Um Pix para várias contas e uma conta com vários Pix — forma A, fase F1 (02/10/2026).
--
-- O dono aprovou a forma A (aplicação de pagamento): cada Pix é um recebimento, e o sistema
-- guarda quanto dele foi para cada conta; o saldo da conta e a sobra do Pix são calculados. No
-- MarineFlow isso já existe pela metade, sem tabela nova: a LINHA DO BANCO é o recebimento (o
-- dinheiro que entrou) e cada PAGAMENTO é a aplicação de parte dele numa conta (payments já tem
-- conta, valor, data e desfazer sem apagar, pelo status 'cancelled'). Faltava o pagamento saber
-- de qual Pix veio. Hoje é o contrário: a linha aponta para UM pagamento
-- (bank_transactions.reconciled_payment_id), e por isso um Pix não paga duas contas.
--
-- Medido antes (02/10): 107 contas a receber; 31 pagamentos; 68 receitas que nasceram do
-- Extrato estavam pagas SEM nenhum pagamento (R$ 550.618,46, todas com a linha do banco e o
-- mesmo valor dela, nenhuma com OS). Levantamento de quem lê payments: nenhuma tela soma
-- pagamentos com contas pagas ou com o extrato, então nada passa a contar em dobro. Simulação só
-- de leitura deste arquivo: zero diferença em pago e situação nas 107 contas.
--
-- Esta fase não muda o jeito de trabalhar. Ela:
--   1. dá a cada pagamento o Pix de onde veio (payments.bank_transaction_id; vários pagamentos
--      podem vir do mesmo Pix);
--   2. tira o pagamento das cópias de Pix (linha marcada como duplicata que ainda apontava para
--      o pagamento da linha verdadeira: New Comércio, Lucenira, Maria Goreti);
--   3. registra o pagamento das receitas que nasceram do extrato, pela função que a aprovação do
--      Extrato (finance-review) passa a chamar;
--   4. liga o Pix de R$ 4.800 do Lenine (11/08) aos pagamentos dos sinais ORÇ-00074 e ORÇ-00077,
--      que ele pagou (confirmado pelo dono em 02/10) — o primeiro Pix que paga duas contas;
--   5. mantém a ligação em dia quando o caminho antigo liga ou desliga a linha de um pagamento;
--   6. corrige o ajuste ao valor do banco, que mudava o valor do pagamento e deixava o líquido
--      no valor antigo (ORÇ-00073: 1.866,00 com líquido 1.865,47);
--   7. cria a conferência: recebimentos_do_extrato (quanto de cada entrada foi aplicado e quanto
--      sobra) e conferencia_dos_pagamentos (onde o modelo novo discorda do que está gravado).

-- 1. O pagamento sabe de qual Pix veio ------------------------------------------------------
alter table public.payments
  add column if not exists bank_transaction_id uuid references public.bank_transactions(id) on delete set null;
create index if not exists idx_payments_bank_transaction_id
  on public.payments (bank_transaction_id) where bank_transaction_id is not null;
comment on column public.payments.bank_transaction_id is
  'De qual linha do banco (Pix, TED…) veio este pagamento. Vários pagamentos podem vir da mesma linha: um Pix que pagou várias contas.';

-- 2. Cópia de Pix não segura pagamento ------------------------------------------------------
-- Mesma regra das outras 148 duplicatas e da Rita (02/10): a cópia fica sem pagamento.
with copia as (
  select c.id, c.reconciled_payment_id
    from public.bank_transactions c
   where c.dismissed_kind = 'duplicata'
     and c.reconciled_payment_id is not null
     and exists (select 1 from public.bank_transactions v
                  where v.reconciled_payment_id = c.reconciled_payment_id
                    and v.id <> c.id and v.dismissed_kind is null)
), limpa as (
  update public.bank_transactions t set reconciled_payment_id = null
    from copia where t.id = copia.id
  returning t.id, copia.reconciled_payment_id as pagamento, t.amount
)
insert into public.reconciliation_log (acao, bank_transaction_id, valor, detalhe, antes, depois)
select 'limpou_copia', id, amount,
       'Cópia do Pix (duplicata) deixou de apontar para o pagamento da linha verdadeira (F1, 02/10/2026).',
       jsonb_build_object('reconciled_payment_id', pagamento), jsonb_build_object('reconciled_payment_id', null)
  from limpa;

-- 3. O que já se sabia: a linha aponta para o pagamento -------------------------------------
-- Se mais de uma linha aponta para o mesmo pagamento (sobrou só a da Mundo Doce, pergunta
-- aberta ao dono), vale a que não é cópia, de valor mais próximo e data mais próxima.
update public.payments p set bank_transaction_id = escolha.linha
  from (
    select distinct on (t.reconciled_payment_id) t.reconciled_payment_id as pagamento, t.id as linha
      from public.bank_transactions t
      join public.payments p2 on p2.id = t.reconciled_payment_id
     order by t.reconciled_payment_id,
              (t.dismissed_kind is null) desc,
              abs(abs(t.amount) - p2.amount),
              abs(t.transaction_date - p2.payment_date)
  ) escolha
 where p.id = escolha.pagamento and p.bank_transaction_id is null;

-- 4. A receita que nasceu do extrato ganha o seu pagamento ----------------------------------
-- Aprovar uma entrada no Extrato cria a conta já paga, ligada à linha, mas sem pagamento. Sem
-- ele, a conta não diz de onde recebeu, e um pagamento à mão lançado depois
-- (register_payment_and_update_balance soma os pagamentos) zeraria o recebido do extrato.
create or replace function public.registrar_pagamento_da_receita_do_extrato(p_receivable_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.receivables%rowtype;
  t public.bank_transactions%rowtype;
  v_pagamento uuid;
begin
  select * into r from public.receivables where id = p_receivable_id for update;
  if not found or r.status = 'cancelled' or r.bank_transaction_id is null or coalesce(r.paid_amount, 0) <= 0 then
    return null;
  end if;
  -- Já tem pagamento confirmado: nada a registrar (pode ser chamada de novo sem efeito).
  if exists (select 1 from public.payments where receivable_id = r.id and status = 'confirmed') then
    return null;
  end if;
  select * into t from public.bank_transactions where id = r.bank_transaction_id;
  if t.id is null or t.transaction_type <> 'credit' then return null; end if;

  insert into public.payments (receivable_id, amount, payment_date, payment_method, installments,
                               card_fee_percent, net_amount, notes, status, bank_transaction_id)
  values (r.id, r.paid_amount, t.transaction_date,
          case when coalesce(t.payment_method, '') ilike '%pix%' or coalesce(t.description, '') ilike '%pix%' then 'pix'
               when t.card_last_digits is not null then 'debit_card'
               else 'bank_transfer' end,
          1, 0, r.paid_amount,
          'Conciliado com o extrato de ' || to_char(t.transaction_date, 'DD/MM/YYYY') || ' (a receita nasceu desta linha do banco).',
          'confirmed', t.id)
  returning id into v_pagamento;

  update public.bank_transactions set reconciled_payment_id = v_pagamento
   where id = t.id and reconciled_payment_id is null;
  return v_pagamento;
end;
$$;
comment on function public.registrar_pagamento_da_receita_do_extrato(uuid) is
  'Registra o pagamento de uma receita que nasceu de uma entrada do extrato (conta paga ligada à linha, sem pagamento). Idempotente.';
revoke all on function public.registrar_pagamento_da_receita_do_extrato(uuid) from public;
revoke all on function public.registrar_pagamento_da_receita_do_extrato(uuid) from anon;
revoke all on function public.registrar_pagamento_da_receita_do_extrato(uuid) from authenticated;
grant execute on function public.registrar_pagamento_da_receita_do_extrato(uuid) to service_role;

select public.registrar_pagamento_da_receita_do_extrato(r.id)
  from public.receivables r
 where r.status <> 'cancelled' and r.bank_transaction_id is not null and coalesce(r.paid_amount, 0) > 0
   and not exists (select 1 from public.payments p where p.receivable_id = r.id and p.status = 'confirmed');

-- 5. O Pix do Lenine pagou dois sinais ------------------------------------------------------
update public.payments set bank_transaction_id = 'fdb480ce-203e-4262-8b96-962b520f4ddf'
 where id in ('8eeb0b3c-05c4-401f-abe6-ee4387742243', '281cc406-8544-4687-b115-8d38341ef251')
   and status = 'confirmed' and bank_transaction_id is null;
insert into public.reconciliation_log (acao, bank_transaction_id, valor, detalhe, depois)
select 'aplicou_pix', 'fdb480ce-203e-4262-8b96-962b520f4ddf', 4800,
       'Pix de R$ 4.800 do Lenine (11/08) aplicado aos sinais ORÇ-00074 (R$ 2.280) e ORÇ-00077 (R$ 2.520) — confirmado pelo dono em 02/10/2026.',
       jsonb_build_object('pagamentos', jsonb_build_array('8eeb0b3c-05c4-401f-abe6-ee4387742243', '281cc406-8544-4687-b115-8d38341ef251'))
 where exists (select 1 from public.payments
                where bank_transaction_id = 'fdb480ce-203e-4262-8b96-962b520f4ddf'
                  and id = '8eeb0b3c-05c4-401f-abe6-ee4387742243');

-- 6. O caminho antigo continua valendo e a ligação acompanha --------------------------------
-- Telas e funções de hoje ligam a linha a UM pagamento por reconciled_payment_id. Quando ligam,
-- o pagamento passa a saber da linha; quando desligam, deixa de saber.
create or replace function public._pagamento_segue_a_linha()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' and old.reconciled_payment_id is not null
     and old.reconciled_payment_id is distinct from new.reconciled_payment_id then
    update public.payments set bank_transaction_id = null
     where id = old.reconciled_payment_id and bank_transaction_id = new.id;
  end if;
  if new.reconciled_payment_id is not null
     and (tg_op = 'INSERT' or old.reconciled_payment_id is distinct from new.reconciled_payment_id) then
    update public.payments set bank_transaction_id = new.id
     where id = new.reconciled_payment_id and bank_transaction_id is distinct from new.id;
  end if;
  return null;
end;
$$;
revoke all on function public._pagamento_segue_a_linha() from public;
revoke all on function public._pagamento_segue_a_linha() from anon;
revoke all on function public._pagamento_segue_a_linha() from authenticated;

drop trigger if exists trg_pagamento_segue_a_linha on public.bank_transactions;
create trigger trg_pagamento_segue_a_linha
  after insert or update of reconciled_payment_id on public.bank_transactions
  for each row execute function public._pagamento_segue_a_linha();

-- 7. Ajuste ao valor do banco: o líquido acompanha o valor -----------------------------------
create or replace function public.ajustar_ao_valor_do_banco(
  p_tipo text,
  p_id uuid,
  p_motivo text default null,
  p_autor uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  r public.receivables%rowtype;
  t public.bank_transactions%rowtype;
  v_pagamento public.payments%rowtype;
  v_pagamentos integer;
  v_banco numeric;
  v_dif numeric;
  v_msg text;
  v_nota text;
begin
  if p_tipo <> 'receivable' then
    raise exception 'O ajuste ao valor do banco vale para conta a receber. Numa conta a pagar, desfaça a aprovação e aprove de novo com o valor certo.';
  end if;

  select * into r from public.receivables where id = p_id for update;
  if not found then raise exception 'Lançamento não encontrado.'; end if;
  if r.status = 'cancelled' then raise exception 'Este lançamento está cancelado.'; end if;
  if r.bank_transaction_id is null then
    raise exception 'Este lançamento não está ligado a nenhuma linha do extrato: não há valor do banco para seguir.';
  end if;
  perform public._recusa_se_mes_fechado(r.issue_date, 'ajustar este lançamento ao valor do banco');

  select * into t from public.bank_transactions where id = r.bank_transaction_id;
  v_banco := abs(t.amount);

  -- Só o caso inequívoco: UM pagamento confirmado, e é o que a linha do banco registrou.
  select count(*) into v_pagamentos from public.payments where receivable_id = r.id and status = 'confirmed';
  select * into v_pagamento from public.payments
   where id = t.reconciled_payment_id and receivable_id = r.id and status = 'confirmed';
  if v_pagamentos <> 1 or v_pagamento.id is null then
    raise exception 'Este lançamento tem % pagamento(s) e nem todos vieram desta linha do banco. Confira os pagamentos antes: ajustar aqui apagaria a diferença sem saber de onde ela vem.',
      v_pagamentos;
  end if;

  v_dif := round(v_banco - r.amount, 2);
  if abs(v_dif) < 0.005 and abs(v_pagamento.amount - v_banco) < 0.005 then
    raise exception 'O lançamento já bate com o banco (%).', public._brl(v_banco);
  end if;

  v_msg := case
    when v_dif > 0 then 'Ajustado ao banco: o cliente pagou ' || public._brl(v_dif) || ' a mais; o lançamento passou de '
                        || public._brl(r.amount) || ' para ' || public._brl(v_banco) || '.'
    when v_dif < 0 then 'Ajustado ao banco: ' || public._brl(-v_dif) || ' deixam de ser cobrados (desconto); o lançamento passou de '
                        || public._brl(r.amount) || ' para ' || public._brl(v_banco) || '.'
    else 'Ajustado ao banco: o pagamento passou a ' || public._brl(v_banco) || '.'
  end;
  v_nota := '[' || to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY') || '] ' || v_msg
            || coalesce(' Motivo: ' || nullif(btrim(p_motivo), '') || '.', '');

  -- O líquido acompanha quando era igual ao valor (Pix, transferência); com taxa de cartão ele
  -- é outro número e fica como está.
  update public.payments
     set amount = v_banco,
         net_amount = case when net_amount is null or round(net_amount, 2) = round(amount, 2) then v_banco else net_amount end
   where id = v_pagamento.id;
  update public.receivables
     set amount = v_banco, paid_amount = v_banco, balance_amount = 0, status = 'paid',
         notes = btrim(coalesce(notes, '') || ' ' || v_nota)
   where id = r.id;

  insert into public.reconciliation_log (acao, autor, bank_transaction_id, receivable_id, valor, detalhe, antes, depois)
  values ('ajustou_ao_banco', v_autor, t.id, r.id, v_banco,
          left(coalesce(nullif(btrim(p_motivo), ''), v_msg) || ' · ' || coalesce(r.description, ''), 300),
          jsonb_build_object('amount', r.amount, 'paid_amount', r.paid_amount, 'status', r.status, 'pagamento', v_pagamento.amount),
          jsonb_build_object('amount', v_banco, 'paid_amount', v_banco, 'status', 'paid', 'pagamento', v_banco));

  return jsonb_build_object('ok', true, 'antes', r.amount, 'depois', v_banco, 'diferenca', v_dif, 'message', v_msg);
end;
$$;
revoke all on function public.ajustar_ao_valor_do_banco(text, uuid, text, uuid) from public;
revoke all on function public.ajustar_ao_valor_do_banco(text, uuid, text, uuid) from anon;
grant execute on function public.ajustar_ao_valor_do_banco(text, uuid, text, uuid) to authenticated, service_role;

-- O ajuste do ORÇ-00073 (02/10) deixou o líquido no valor antigo.
update public.payments set net_amount = amount
 where id = '9feea7b9-a111-44a0-ab4c-003c13618819'
   and round(net_amount, 2) = 1865.47 and round(amount, 2) = 1866.00;

-- 8. Conferência ------------------------------------------------------------------------------
-- Quanto de cada entrada do banco já foi aplicado em contas a receber, e quanto sobra.
create or replace view public.recebimentos_do_extrato
with (security_invoker = on) as
select t.id as bank_transaction_id,
       t.bank_connection_id,
       t.transaction_date as data,
       t.amount as valor,
       coalesce(t.counterparty_name, t.description) as quem,
       t.counterparty_document as documento,
       t.dismissed_kind,
       coalesce(a.aplicado, 0) as aplicado,
       round(t.amount - coalesce(a.aplicado, 0), 2) as sobra,
       coalesce(a.contas, 0) as contas,
       a.receivable_ids
  from public.bank_transactions t
  left join lateral (
    select sum(p.amount) as aplicado,
           count(distinct p.receivable_id) as contas,
           array_agg(distinct p.receivable_id) as receivable_ids
      from public.payments p
     where p.bank_transaction_id = t.id and p.status = 'confirmed' and p.receivable_id is not null
  ) a on true
 where t.transaction_type = 'credit';
comment on view public.recebimentos_do_extrato is
  'Cada entrada do banco como recebimento: quanto dela foi aplicado em contas a receber (pagamentos confirmados que vieram dela) e quanto sobra.';

revoke all on public.recebimentos_do_extrato from anon;
grant select on public.recebimentos_do_extrato to authenticated, service_role;

-- Onde o modelo novo (pago = soma dos pagamentos; entrada aplicada ≤ valor da entrada) discorda
-- do que está gravado. Vazia = os dois contam a mesma história. Em 02/10 ficou 1 linha conhecida:
-- o Pix de R$ 3.000 da Mundo Doce (07/08) apontando para o pagamento do sinal do Vanderlei,
-- pergunta aberta ao dono.
create or replace view public.conferencia_dos_pagamentos
with (security_invoker = on) as
with pagos as (
  select r.id, r.description, r.amount, r.paid_amount, r.status, r.bank_transaction_id,
         coalesce(sum(p.amount) filter (where p.status = 'confirmed'), 0) as soma
    from public.receivables r
    left join public.payments p on p.receivable_id = r.id
   group by r.id
)
select 'pago_diferente_da_soma'::text as problema, g.id as receivable_id, null::uuid as bank_transaction_id,
       g.description as descricao, g.paid_amount as gravado, g.soma as calculado
  from pagos g
 where g.status <> 'cancelled' and round(coalesce(g.paid_amount, 0), 2) <> round(g.soma, 2)
union all
select 'situacao_diferente', g.id, null, g.description, null, g.soma
  from pagos g
 where g.status <> 'cancelled' and g.amount > 0
   and case when round(g.soma, 2) >= round(g.amount, 2) then 'paid'
            when g.soma > 0 then 'partially_paid' else 'aberta' end
       <> case when g.status in ('pending', 'overdue') then 'aberta' else g.status end
union all
select 'entrada_aplicada_a_mais', null, e.bank_transaction_id, e.quem, e.valor, e.aplicado
  from public.recebimentos_do_extrato e
 where e.aplicado > e.valor + 0.005
union all
select 'conta_ligada_sem_pagamento_da_linha', g.id, g.bank_transaction_id, g.description, null, null
  from pagos g
 where g.status <> 'cancelled' and g.bank_transaction_id is not null
   and not exists (select 1 from public.payments p
                    where p.receivable_id = g.id and p.status = 'confirmed' and p.bank_transaction_id = g.bank_transaction_id)
union all
select 'linha_aponta_pagamento_de_outra', p.receivable_id, t.id, coalesce(t.counterparty_name, t.description), t.amount, p.amount
  from public.bank_transactions t
  join public.payments p on p.id = t.reconciled_payment_id
 where p.status = 'confirmed' and p.receivable_id is not null
   and p.bank_transaction_id is distinct from t.id;
comment on view public.conferencia_dos_pagamentos is
  'Onde "pago = soma dos pagamentos" e "entrada aplicada ≤ valor da entrada" discordam do que está gravado. Vazia = tudo bate.';

revoke all on public.conferencia_dos_pagamentos from anon;
grant select on public.conferencia_dos_pagamentos to authenticated, service_role;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261002120000', 'pagamento_sabe_de_qual_pix')
on conflict do nothing;
