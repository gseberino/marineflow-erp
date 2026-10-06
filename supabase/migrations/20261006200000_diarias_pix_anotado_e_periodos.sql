-- Diárias: Pix anotado à mão aparece (e desconta) na hora, e o extrato ganha atalhos de período
-- que dependem da pessoa ("em aberto", "desde o último pagamento").
--
-- O DEFEITO (dono, 06/10/2026): "lancei pelo botão Lançar o Pix que já fiz ao Roberto, e não
-- apareceu no extrato de diárias; o que lancei como dinheiro/bolso apareceu". Não era perda: o
-- "Lançar" com Pix grava uma ANOTAÇÃO (anotacoes_do_extrato) que espera a linha do banco; o
-- pagamento só nasce quando o motor do extrato casa as duas e o lançamento é aprovado — e o motor
-- roda às 06:10 e 15:10. Até lá a conta corrente não via nada. Decisão do dono: a anotação aparece
-- já descontando ("Anotado — aguardando o banco"); quando vira lançamento, some daqui e o
-- pagamento entra pelo caminho normal (nunca os dois).
--
-- PERÍODOS (pedido do mesmo dia): além de De/Até livres, atalhos — em aberto (desde a última vez
-- que o saldo com ele zerou), desde o último pagamento, últimos 15 dias, semana atual. "Em aberto"
-- e "desde o último pagamento" são POR PESSOA: por isso moram aqui, e o resumo calcula cada um.

-- 1. A conta corrente ganha as anotações e a marca "aguardando" (muda o tipo de retorno: drop).
drop function if exists public._conta_corrente_linhas(uuid);

create function public._conta_corrente_linhas(p_favorecido_id uuid)
returns table(data date, tipo text, id uuid, jornada text, fracao numeric, valor_diaria numeric, extras numeric,
              descontos numeric, trabalhado numeric, pago numeric, descricao text, conta text, categoria text,
              observacao text, os jsonb, criado_em timestamptz, aguardando boolean)
language sql
stable
security definer
set search_path = public
as $$
  with fav as (
    select id, coalesce(conta_corrente_desde, date '1900-01-01') as desde
      from public.payees where id = p_favorecido_id
  )
  select ws.data, 'dia'::text, ws.id,
         case ws.fracao when 1 then 'inteiro' when 0.5 then 'meio' else 'faltou' end,
         ws.fracao, ws.valor_diaria, ws.extras, ws.descontos, ws.valor_dia, 0::numeric,
         null::text, null::text, null::text, ws.observacao,
         coalesce((select jsonb_agg(jsonb_build_object('id', so.id, 'numero', so.service_order_number)
                                    order by so.service_order_number)
                     from public.work_shift_os wo
                     join public.service_orders so on so.id = wo.service_order_id
                    where wo.shift_id = ws.id), '[]'::jsonb),
         ws.created_at, false
    from public.work_shifts ws
    join public.work_profiles wp on wp.id = ws.work_profile_id
    join fav on fav.id = wp.payee_id
   where ws.fracao is not null and ws.data >= fav.desde
  union all
  -- O que ele recebeu: lançamento no nome dele (conta o que foi pago dele) ou pago do bolso do
  -- sócio para ele (conta o valor inteiro — o dinheiro já chegou a ele, o reembolso é do sócio).
  select p.issue_date, 'pagamento'::text, p.id, null::text, null::numeric, null::numeric, null::numeric,
         null::numeric, 0::numeric,
         case when p.payee_id = fav.id then coalesce(p.paid_amount, 0) else p.amount end,
         p.description,
         case when p.payee_id = fav.id
              then coalesce(bc.label, case when p.payment_method = 'cash' then 'Caixa (dinheiro)' end, 'Sem conta ligada')
              else 'Bolso de ' || coalesce(soc.name, 'sócio') end,
         p.expense_category, null::text, '[]'::jsonb, p.created_at, false
    from public.payables p
    join fav on (p.payee_id = fav.id or p.beneficiario_id = fav.id)
    left join public.payees soc on soc.id = p.payee_id
    left join public.bank_transactions bt on bt.id = p.bank_transaction_id
    left join public.bank_connections bc on bc.id = bt.bank_connection_id
   where p.status <> 'cancelled' and p.issue_date >= fav.desde
     and (case when p.payee_id = fav.id then coalesce(p.paid_amount, 0) else p.amount end) > 0
  union all
  -- Pix/débito ANOTADO para ele que ainda não virou lançamento (decisão do dono, 06/10/2026: já
  -- desconta). Esperando a linha do banco, ou já casado com ela e esperando a aprovação. Quando o
  -- lançamento existe, ele entra pela parte de cima e esta linha sai — nunca os dois. Linha casada
  -- que foi RECUSADA na fila não conta: o dono disse que não era aquilo.
  select a.data_prevista, 'pagamento'::text, a.id, null::text, null::numeric, null::numeric, null::numeric,
         null::numeric, 0::numeric, a.valor,
         coalesce(a.descricao, 'Pix anotado'),
         'Anotado — aguardando o banco',
         a.categoria, null::text, '[]'::jsonb, a.criada_em, true
    from public.anotacoes_do_extrato a
    join fav on fav.id = a.favorecido_id
   where a.sentido = 'debit' and a.data_prevista >= fav.desde
     and (a.status = 'aguardando'
          or (a.status = 'aplicada' and a.bank_transaction_id is not null
              and not exists (select 1 from public.payables p
                               where p.bank_transaction_id = a.bank_transaction_id and p.status <> 'cancelled')
              and not exists (select 1 from public.finance_review_queue q
                               where q.bank_transaction_id = a.bank_transaction_id and q.status = 'rejected')));
$$;

-- 2. O período de um atalho, para uma pessoa. De e até inclusivos; nulo = sem limite.
create or replace function public._periodo_do_atalho(p_favorecido_id uuid, p_atalho text)
returns table(de date, ate date)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_hoje date := public._hoje_brt();
  v_ini numeric;
  v_marco date;
begin
  case coalesce(p_atalho, 'tudo')
    when 'tudo' then
      return query select null::date, null::date;
    when 'este_mes' then
      return query select date_trunc('month', v_hoje)::date, (date_trunc('month', v_hoje) + interval '1 month - 1 day')::date;
    when 'mes_anterior' then
      return query select (date_trunc('month', v_hoje) - interval '1 month')::date, (date_trunc('month', v_hoje) - interval '1 day')::date;
    when 'semana_atual' then
      return query select v_hoje - (extract(isodow from v_hoje)::int - 1), v_hoje;
    when 'ultimos_15_dias' then
      return query select v_hoje - 14, v_hoje;
    when 'desde_ultimo_pagamento' then
      -- Do dia seguinte ao último pagamento; o pagamento em si fica no "saldo antes do período".
      select max(l.data) into v_marco from public._conta_corrente_linhas(p_favorecido_id) l where l.tipo = 'pagamento';
      return query select case when v_marco is null then null else v_marco + 1 end, null::date;
    when 'em_aberto' then
      -- Do dia seguinte à última vez que o saldo com ele chegou a zero (ou ficou a favor da
      -- empresa): é o que falta pagar. Mesma ordem do extrato: no mesmo dia, o dia antes do
      -- pagamento. Nunca zerou → desde o início da conta corrente.
      select saldo_anterior into v_ini from public.payees where id = p_favorecido_id;
      select max(o.data) into v_marco
        from (select l.data,
                     coalesce(v_ini, 0) + sum(l.trabalhado - l.pago) over (
                       order by l.data, case l.tipo when 'dia' then 0 else 1 end, l.criado_em, l.id
                       rows between unbounded preceding and current row) as saldo
                from public._conta_corrente_linhas(p_favorecido_id) l) o
       where o.saldo <= 0.005;
      return query select case when v_marco is null then null else v_marco + 1 end, null::date;
    else
      raise exception 'Período desconhecido: "%". Use em_aberto, desde_ultimo_pagamento, ultimos_15_dias, semana_atual, este_mes, mes_anterior ou tudo.', p_atalho;
  end case;
end;
$$;

-- 3. Conta corrente com atalho (o atalho manda; sem ele, De/Até como antes). Novo parâmetro = drop.
drop function if exists public.conta_corrente_freelancer(uuid, date, date, uuid);

create function public.conta_corrente_freelancer(
  p_favorecido_id uuid,
  p_de date default null,
  p_ate date default null,
  p_autor uuid default null,
  p_atalho text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_fav record;
  v_perfil record;
  v_de date := p_de;
  v_ate date := p_ate;
  v_anterior numeric;
  v_linhas jsonb;
  v_dias numeric;
  v_trab numeric;
  v_pago numeric;
  v_aguardando numeric;
  v_final numeric;
  v_dias_tudo numeric;
  v_pago_tudo numeric;
begin
  select id, name, conta_corrente_desde, saldo_anterior into v_fav
    from public.payees where id = p_favorecido_id;
  if v_fav.id is null then raise exception 'Freelancer não encontrado entre os favorecidos.'; end if;

  if p_atalho is not null then
    select x.de, x.ate into v_de, v_ate from public._periodo_do_atalho(p_favorecido_id, p_atalho) x;
  end if;

  v_de := greatest(coalesce(v_de, v_fav.conta_corrente_desde, date '1900-01-01'),
                   coalesce(v_fav.conta_corrente_desde, date '1900-01-01'));
  v_ate := coalesce(v_ate, date '9999-12-31');
  if v_ate < v_de then raise exception 'Período invertido: % a %.', to_char(v_de, 'DD/MM/YYYY'), to_char(v_ate, 'DD/MM/YYYY'); end if;

  select * into v_perfil from public.work_profiles
   where payee_id = p_favorecido_id and modo_pagamento = 'diaria'
     and vigencia_inicio <= least(v_ate, public._hoje_brt())
   order by vigencia_inicio desc limit 1;

  select v_fav.saldo_anterior + coalesce(sum(l.trabalhado - l.pago), 0) into v_anterior
    from public._conta_corrente_linhas(p_favorecido_id) l where l.data < v_de;

  with l as (
    select * from public._conta_corrente_linhas(p_favorecido_id) where data between v_de and v_ate
  ), o as (
    select l.*, v_anterior + sum(l.trabalhado - l.pago) over (
             order by l.data, case l.tipo when 'dia' then 0 else 1 end, l.criado_em, l.id
             rows between unbounded preceding and current row) as saldo,
           row_number() over (order by l.data, case l.tipo when 'dia' then 0 else 1 end, l.criado_em, l.id) as ordem
      from l
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'data', o.data, 'tipo', o.tipo, 'id', o.id, 'jornada', o.jornada, 'fracao', o.fracao,
           'valor_diaria', o.valor_diaria, 'extras', o.extras, 'descontos', o.descontos,
           'trabalhado', o.trabalhado, 'pago', o.pago, 'descricao', o.descricao, 'conta', o.conta,
           'categoria', o.categoria, 'observacao', o.observacao, 'os', o.os, 'saldo', round(o.saldo, 2),
           'aguardando', o.aguardando, 'criado_em', o.criado_em)
           order by o.ordem), '[]'::jsonb),
         coalesce(sum(o.fracao) filter (where o.tipo = 'dia'), 0),
         coalesce(sum(o.trabalhado), 0),
         coalesce(sum(o.pago), 0),
         coalesce(sum(o.pago) filter (where o.aguardando), 0)
    into v_linhas, v_dias, v_trab, v_pago, v_aguardando
    from o;

  v_final := v_anterior + v_trab - v_pago;

  select coalesce(sum(l.fracao) filter (where l.tipo = 'dia'), 0), coalesce(sum(l.pago), 0)
    into v_dias_tudo, v_pago_tudo
    from public._conta_corrente_linhas(p_favorecido_id) l where l.data <= v_ate;

  return jsonb_build_object(
    'favorecido', jsonb_build_object('id', v_fav.id, 'nome', v_fav.name,
                                     'desde', v_fav.conta_corrente_desde, 'saldo_inicial', v_fav.saldo_anterior,
                                     'diaria', v_perfil.valor_diaria),
    'atalho', p_atalho,
    'de', case when v_de = date '1900-01-01' then null else v_de end,
    'ate', case when v_ate = date '9999-12-31' then null else v_ate end,
    'saldo_anterior', round(v_anterior, 2),
    'linhas', v_linhas,
    'dias', v_dias,
    'trabalhado', round(v_trab, 2),
    'pago', round(v_pago, 2),
    'pago_aguardando_banco', round(v_aguardando, 2),
    'saldo_final', round(v_final, 2),
    'estado', public._estado_do_saldo(v_final, v_dias_tudo, v_pago_tudo)
  );
end;
$$;

-- 4. Resumo com atalho: cada pessoa no período DELA ("em aberto" de um não é o de outro).
drop function if exists public.resumo_freelancers(date, date, uuid);

create function public.resumo_freelancers(
  p_de date default null,
  p_ate date default null,
  p_autor uuid default null,
  p_atalho text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_pessoas jsonb := '[]'::jsonb;
  f record;
  c jsonb;
  v_ultimo date;
begin
  for f in
    select distinct p.id, p.name
      from public.payees p
      join public.work_profiles wp on wp.payee_id = p.id and wp.modo_pagamento = 'diaria'
     where p.active
     order by p.name
  loop
    c := public.conta_corrente_freelancer(f.id, p_de, p_ate, p_autor, p_atalho);
    select max(l.data) into v_ultimo
      from public._conta_corrente_linhas(f.id) l
     where l.tipo = 'pagamento'
       and l.data <= coalesce((c ->> 'ate')::date, date '9999-12-31')
       and l.data >= coalesce((c ->> 'de')::date, date '1900-01-01');
    v_pessoas := v_pessoas || jsonb_build_object(
      'id', f.id, 'nome', f.name,
      'diaria', c -> 'favorecido' -> 'diaria',
      'desde', c -> 'favorecido' -> 'desde',
      'de', c -> 'de', 'ate', c -> 'ate',
      'dias', c -> 'dias', 'trabalhado', c -> 'trabalhado', 'pago', c -> 'pago',
      'pago_aguardando_banco', c -> 'pago_aguardando_banco',
      'ultimo_pagamento', v_ultimo,
      'saldo_final', c -> 'saldo_final', 'estado', c -> 'estado');
  end loop;

  return jsonb_build_object(
    'pessoas', v_pessoas,
    'atalho', p_atalho,
    'trabalhado', coalesce((select sum((x ->> 'trabalhado')::numeric) from jsonb_array_elements(v_pessoas) x), 0),
    'pago', coalesce((select sum((x ->> 'pago')::numeric) from jsonb_array_elements(v_pessoas) x), 0),
    'dias', coalesce((select sum((x ->> 'dias')::numeric) from jsonb_array_elements(v_pessoas) x), 0),
    'deve', coalesce((select sum(greatest((x ->> 'saldo_final')::numeric, 0)) from jsonb_array_elements(v_pessoas) x), 0),
    'adiantado', coalesce((select sum(greatest(-(x ->> 'saldo_final')::numeric, 0)) from jsonb_array_elements(v_pessoas) x), 0)
  );
end;
$$;

-- 5. Quem pode: o mesmo de antes (as internas fechadas; as públicas só para logado e servidor).
revoke all on function public._conta_corrente_linhas(uuid) from public, anon, authenticated;
revoke all on function public._periodo_do_atalho(uuid, text) from public, anon, authenticated;
revoke all on function public.conta_corrente_freelancer(uuid, date, date, uuid, text) from public, anon;
revoke all on function public.resumo_freelancers(date, date, uuid, text) from public, anon;
grant execute on function public.conta_corrente_freelancer(uuid, date, date, uuid, text) to authenticated, service_role;
grant execute on function public.resumo_freelancers(date, date, uuid, text) to authenticated, service_role;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261006200000', 'diarias_pix_anotado_e_periodos')
on conflict (version) do nothing;
