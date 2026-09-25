-- Fase 3 do Financeiro Confiável: menos cliques, extrato por conta com saldo, e o mês
-- fecha com prova.
--
-- O dono nunca fechou um mês "porque não tinha confiança nos lançamentos". Fechar deixa de
-- ser um botão solto e passa a ser a conclusão de uma verificação que o sistema roda sozinho.

-- ── 3.1 Lançar sozinho o que tem alta confiança ────────────────────────────────────────
-- Calibração medida em 25/09/2026 sobre as aprovações reais: saídas com confiança 85+ e
-- abaixo de R$ 500 acertaram a categoria em 98,6% (590 casos); regras, 98,3% (302). Decisão
-- do dono: SIM, com lista do que foi lançado sozinho e desfazer.
alter table public.finance_review_queue
  add column if not exists automatica text check (automatica in ('regra', 'confianca'));
comment on column public.finance_review_queue.automatica is
  'Aprovada sem clique: por regra com autonomia, ou por confiança alta (finance_auto_approve). Tudo desfazível.';

insert into public.app_settings (key, value, description)
values
  ('finance_auto_approve', 'on',
   'Lançar sozinho saídas de confiança alta abaixo do limite de lote (decisão do dono em 25/09/2026). on/off.'),
  ('finance_auto_approve_min_confidence', '85',
   'Confiança mínima para lançar sozinho. 85 = faixa que acertou 98,6% em 25/09/2026.')
on conflict (key) do nothing;

-- ── 3.2 Extrato da conta, com saldo dia a dia ──────────────────────────────────────────
-- Saldo após cada linha = linha de base da conta + soma com sinal de tudo até ela — a
-- MESMA conta que a conferência de saldo faz (soma_transacoes_conexao), para a tela e o
-- alerta nunca discordarem. Pendente e duplicata não mexem no saldo; compra de cartão não é
-- movimento da conta (é da fatura) e fica fora.
create or replace function public.extrato_da_conta(p_conexao uuid, p_de date, p_ate date)
returns table (
  id uuid, data date, descricao text, contraparte text, documento text, tipo text,
  valor numeric, saldo_apos numeric, situacao text, pendente boolean,
  lancamento_tipo text, lancamento_id uuid, lancamento_descricao text, categoria text, quem text,
  tipo_fora text, motivo_fora text, proposta_id uuid
)
language sql
stable
security invoker
set search_path = public
as $$
  with base as (
    select c.saldo_base from public.bank_connections c where c.id = p_conexao
  ),
  mov as (
    select t.*,
           (coalesce(t.tx_status, '') <> 'PENDING' and coalesce(t.dismissed_kind, '') <> 'duplicata') as conta_no_saldo,
           case when t.transaction_type = 'credit' then t.amount else -t.amount end as com_sinal
      from public.bank_transactions_situacao t
     where t.bank_connection_id = p_conexao
       and coalesce(t.source_type, 'bank') in ('bank', 'cash')
  ),
  acumulado as (
    select m.*,
           sum(case when m.conta_no_saldo then m.com_sinal else 0 end)
             over (order by m.transaction_date, m.created_at, m.id rows unbounded preceding) as soma_ate_aqui
      from mov m
  )
  select a.id, a.transaction_date, a.description,
         coalesce(a.counterparty_name, a.merchant_name), a.counterparty_document, a.transaction_type,
         a.com_sinal,
         case when (select saldo_base from base) is null then null
              else round((select saldo_base from base) + a.soma_ate_aqui, 2) end,
         a.situacao, coalesce(a.tx_status, '') = 'PENDING',
         case when p.id is not null then 'payable' when r.id is not null then 'receivable' end,
         coalesce(p.id, r.id),
         coalesce(p.description, r.description),
         coalesce(p.expense_category, r.category),
         coalesce(s.name, pe.name, cl.name, p.supplier_name),
         a.dismissed_kind, a.dismissed_reason,
         q.id
    from acumulado a
    left join public.payables p on p.bank_transaction_id = a.id and p.status <> 'cancelled'
    left join public.receivables r on r.bank_transaction_id = a.id and r.status <> 'cancelled'
    left join public.suppliers s on s.id = p.supplier_id
    left join public.payees pe on pe.id = p.payee_id
    left join public.clients cl on cl.id = r.client_id
    left join lateral (
      select fq.id from public.finance_review_queue fq
       where fq.bank_transaction_id = a.id and fq.status = 'pending'
       order by fq.created_at desc limit 1
    ) q on true
   where a.transaction_date between p_de and p_ate
   order by a.transaction_date desc, a.created_at desc, a.id desc;
$$;

revoke all on function public.extrato_da_conta(uuid, date, date) from public, anon;
grant execute on function public.extrato_da_conta(uuid, date, date) to authenticated, service_role;

-- ── 3.3 O mês está pronto? ─────────────────────────────────────────────────────────────
-- Cada item diz se BLOQUEIA o fechamento ou só avisa. Bloqueia o que deixaria o número
-- errado; avisa o que pede um olhar mas pode ser legítimo.
create or replace function public.checklist_do_mes(p_ano integer, p_mes integer)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_ini date := make_date(p_ano, p_mes, 1);
  v_fim date := (make_date(p_ano, p_mes, 1) + interval '1 month - 1 day')::date;
  v_itens jsonb := '[]'::jsonb;
  v_n integer;
  v_valor numeric;
  v_det text;
begin
  -- 1. Saldo de cada conta confere com o banco (a última conferência).
  select count(*), string_agg(c.label || ' difere ' || public._brl(abs(k.diferenca)), '; ')
    into v_n, v_det
    from public.bank_connections c
    join lateral (select * from public.bank_balance_checks b where b.bank_connection_id = c.id
                   order by b.conferido_em desc limit 1) k on true
   where coalesce(c.active, true) and not k.fecha;
  v_itens := v_itens || jsonb_build_object('chave', 'saldo_confere', 'bloqueia', true, 'ok', v_n = 0,
    'titulo', 'O saldo de cada conta confere com o banco', 'quantidade', v_n,
    'detalhe', coalesce(v_det, 'Todas as contas conferem na última sincronização.'));

  -- 2. Nada do extrato do mês sem destino (nem lançado, nem casado, nem fora da fila).
  select count(*), coalesce(sum(t.amount), 0) into v_n, v_valor
    from public.bank_transactions_situacao t
   where t.transaction_date between v_ini and v_fim and t.situacao = 'nova'
     and coalesce(t.tx_status, '') <> 'PENDING';
  v_itens := v_itens || jsonb_build_object('chave', 'extrato_tratado', 'bloqueia', true, 'ok', v_n = 0,
    'titulo', 'Todo movimento do banco no mês tem destino', 'quantidade', v_n, 'valor', v_valor,
    'detalhe', case when v_n = 0 then 'Nada esperando no Extrato.' else v_n || ' linha(s) esperando no Extrato.' end);

  -- 3. Nenhuma despesa lançada em dobro: uma com banco e outra sem, mesmo valor, mesma
  --    contraparte, até 5 dias. (Duas COM banco são dois pagamentos reais.)
  select count(*) into v_n
    from public.payables a
    join public.payables b on b.id <> a.id
     and a.bank_transaction_id is not null and b.bank_transaction_id is null
     and b.status <> 'cancelled' and abs(a.amount - b.amount) < 0.01
     and abs(a.issue_date - b.issue_date) <= 5
     and coalesce(a.supplier_id::text, upper(a.supplier_name), '') = coalesce(b.supplier_id::text, upper(b.supplier_name), '')
     and coalesce(a.supplier_id::text, upper(a.supplier_name), '') <> ''
   where a.status <> 'cancelled' and a.issue_date between v_ini and v_fim;
  v_itens := v_itens || jsonb_build_object('chave', 'sem_duplicata', 'bloqueia', true, 'ok', v_n = 0,
    'titulo', 'Nenhuma despesa lançada em dobro', 'quantidade', v_n,
    'detalhe', case when v_n = 0 then 'Nenhum par suspeito.' else v_n || ' par(es) com o mesmo valor e fornecedor, um pelo banco e outro à mão.' end);

  -- 4. Lançamento casado com o extrato pelo mesmo valor.
  select count(*) into v_n
    from public.conciliacao_lancamentos l
   where l.situacao = 'conciliado' and coalesce(l.diferenca, 0) <> 0
     and coalesce(l.extrato_data, l.issue_date) between v_ini and v_fim;
  v_itens := v_itens || jsonb_build_object('chave', 'conciliacao_bate', 'bloqueia', true, 'ok', v_n = 0,
    'titulo', 'Nenhum lançamento com valor diferente do extrato', 'quantidade', v_n,
    'detalhe', case when v_n = 0 then 'Todos batem.' else v_n || ' lançamento(s) difere(m) do banco — veja a Conciliação.' end);

  -- 5. Tudo tem categoria (sem ela o valor some do resultado).
  select (select count(*) from public.payables where status <> 'cancelled' and issue_date between v_ini and v_fim and expense_category is null)
       + (select count(*) from public.receivables where status <> 'cancelled' and issue_date between v_ini and v_fim and category is null)
    into v_n;
  v_itens := v_itens || jsonb_build_object('chave', 'tudo_categorizado', 'bloqueia', true, 'ok', v_n = 0,
    'titulo', 'Todo lançamento tem categoria', 'quantidade', v_n,
    'detalhe', case when v_n = 0 then 'Nada sem categoria.' else v_n || ' lançamento(s) sem categoria não entram no DRE.' end);

  -- 6. Aviso: pago sem nenhum rastro no banco (ou no caixa).
  select count(*) into v_n from public.conciliacao_lancamentos l
   where l.situacao = 'sem_extrato' and l.status = 'paid' and l.issue_date between v_ini and v_fim;
  v_itens := v_itens || jsonb_build_object('chave', 'pago_sem_banco', 'bloqueia', false, 'ok', v_n = 0,
    'titulo', 'Pagos com rastro no banco ou no caixa', 'quantidade', v_n,
    'detalhe', case when v_n = 0 then 'Todo pagamento tem rastro.' else v_n || ' lançamento(s) pago(s) sem linha do banco — confira na Conciliação.' end);

  -- 7. Aviso: "Outras despesas" costuma esconder o que merecia categoria própria.
  select count(*), coalesce(sum(amount), 0) into v_n, v_valor from public.payables
   where status <> 'cancelled' and issue_date between v_ini and v_fim and expense_category = 'Outras despesas';
  v_itens := v_itens || jsonb_build_object('chave', 'outras_despesas', 'bloqueia', false, 'ok', v_n = 0,
    'titulo', 'Pouco em "Outras despesas"', 'quantidade', v_n, 'valor', v_valor,
    'detalhe', case when v_n = 0 then 'Nada em "Outras despesas".' else v_n || ' lançamento(s), ' || public._brl(v_valor) || ', em "Outras despesas".' end);

  return jsonb_build_object(
    'ano', p_ano, 'mes', p_mes,
    'pronto', not exists (select 1 from jsonb_array_elements(v_itens) i where (i ->> 'bloqueia')::boolean and not (i ->> 'ok')::boolean),
    'itens', v_itens
  );
end;
$$;

revoke all on function public.checklist_do_mes(integer, integer) from public, anon;
grant execute on function public.checklist_do_mes(integer, integer) to authenticated, service_role;

-- ── Fechar o mês: com a verificação verde, ou com o motivo escrito ──────────────────────
-- A verificação roda no servidor no momento do clique (não na tela, que pode estar velha).
-- Fechar com pendência exige motivo, que fica na trilha junto com o retrato da verificação.
create or replace function public.fechar_mes(p_ano integer, p_mes integer, p_motivo text default null, p_autor uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_check jsonb;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_existente record;
begin
  if v_autor is not null and not public.is_admin(v_autor) then
    raise exception 'Só o administrador fecha o mês.' using errcode = '42501';
  end if;
  if p_mes not between 1 and 12 then raise exception 'Mês inválido: %', p_mes; end if;

  select * into v_existente from public.periodos_fechados where ano = p_ano and mes = p_mes;
  if v_existente.id is not null and v_existente.reaberto_em is null then
    raise exception 'O mês %/% já está fechado.', lpad(p_mes::text, 2, '0'), p_ano;
  end if;

  v_check := public.checklist_do_mes(p_ano, p_mes);
  if not (v_check ->> 'pronto')::boolean and (v_motivo is null or length(v_motivo) < 10) then
    raise exception 'O mês ainda não está pronto. Resolva os itens pendentes ou escreva o motivo de fechar assim mesmo.';
  end if;

  if v_existente.id is not null then
    update public.periodos_fechados
       set fechado_em = now(), fechado_por = v_autor, reaberto_em = null, reaberto_por = null
     where id = v_existente.id;
  else
    insert into public.periodos_fechados (ano, mes, fechado_em, fechado_por) values (p_ano, p_mes, now(), v_autor);
  end if;

  insert into public.reconciliation_log (acao, autor, detalhe, antes, depois)
  values ('fechou_periodo', v_autor,
          left(lpad(p_mes::text, 2, '0') || '/' || p_ano
               || case when (v_check ->> 'pronto')::boolean then ' — verificação completa'
                       else ' — fechado com pendência: ' || v_motivo end, 300),
          null, v_check);

  return jsonb_build_object('ok', true, 'pronto', (v_check ->> 'pronto')::boolean,
    'message', 'Mês ' || lpad(p_mes::text, 2, '0') || '/' || p_ano || ' fechado.'
      || case when (v_check ->> 'pronto')::boolean then '' else ' Pendências registradas na trilha com o seu motivo.' end);
end;
$$;

revoke all on function public.fechar_mes(integer, integer, text, uuid) from public, anon;
grant execute on function public.fechar_mes(integer, integer, text, uuid) to authenticated, service_role;

insert into supabase_migrations.schema_migrations (version, name)
values ('20260926120000', 'mes_pronto_e_extrato_com_saldo')
on conflict do nothing;
