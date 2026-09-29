-- Prova: o dia de diarista ligado a OS entra no lucro de cada uma, dividido igual; quem não é
-- admin/financeiro não vê o custo (migration 20260929173000_lucro_por_os_com_mao_de_obra).
--
-- ═══ COMO RODAR ═══
--
--   supabase db query --linked -f supabase/tests/lucro_por_os_mao_de_obra.sql --output json
--
-- Seguro em produção: a transação inteira termina em ROLLBACK. Usa as duas OS mais recentes e um
-- dia sem lançamento do primeiro freelancer de diária.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

do $$
declare
  v_dono uuid;
  v_fav uuid;
  v_desde date;
  v_dia date;
  v_os uuid[];
  v_antes numeric[];
  v_depois numeric[];
  v_custo numeric[];
  v_dias numeric[];
  v_valor numeric;
  r jsonb;
  v_tec uuid;
  v_visto integer;
begin
  select id into v_dono from public.app_users where role = 'admin' and active order by created_at limit 1;
  select wp.payee_id, greatest(wp.vigencia_inicio, coalesce(p.conta_corrente_desde, wp.vigencia_inicio)) into v_fav, v_desde
    from public.work_profiles wp join public.payees p on p.id = wp.payee_id
   where wp.modo_pagamento = 'diaria' and wp.vigencia_fim is null order by wp.vigencia_inicio limit 1;
  select d::date into v_dia from generate_series(v_desde, public._hoje_brt(), interval '1 day') d
   where not exists (select 1 from public.work_shifts ws join public.work_profiles wp on wp.id = ws.work_profile_id
                      where wp.payee_id = v_fav and ws.data = d::date and ws.fracao is not null)
   order by d limit 1;
  select array_agg(id order by created_at desc) into v_os from (select id, created_at from public.service_orders order by created_at desc limit 2) x;
  if v_dono is null or v_fav is null or v_dia is null or cardinality(v_os) < 2 then
    insert into _resultado values ('setup', false, 'sem admin, freelancer, dia livre ou duas OS');
    return;
  end if;

  select array_agg(net_profit order by array_position(v_os, os_id)) into v_antes
    from public.vw_os_profitability where os_id = any (v_os);

  -- Um dia inteiro nas duas OS.
  r := public.registrar_diaria(v_fav, v_dia, 'inteiro', v_os, 'teste lucro por OS', 10, 0, null, 'painel', v_dono);
  v_valor := (r ->> 'valor_dia')::numeric;

  select array_agg(net_profit order by array_position(v_os, os_id)),
         array_agg(labor_cost_real order by array_position(v_os, os_id)),
         array_agg(labor_days order by array_position(v_os, os_id))
    into v_depois, v_custo, v_dias
    from public.vw_os_profitability where os_id = any (v_os);

  -- T1. Cada OS leva metade do dia (com os extras), e o lucro cai exatamente isso.
  insert into _resultado values ('T1 metade para cada OS',
    v_custo[1] = round(v_valor / 2, 2) and v_custo[2] = round(v_valor / 2, 2) and v_dias[1] = 0.5 and v_dias[2] = 0.5,
    'dia ' || v_valor || ' → ' || v_custo[1] || ' + ' || v_custo[2]);
  insert into _resultado values ('T2 lucro desconta a mão de obra',
    v_antes[1] - v_depois[1] = v_custo[1] and v_antes[2] - v_depois[2] = v_custo[2],
    'antes ' || v_antes[1] || ' / depois ' || v_depois[1]);

  -- T3. A view de custo diz o mesmo que a de lucro, e quem trabalhou.
  insert into _resultado values ('T3 custo por OS',
    (select custo_real_mao_de_obra from public.v_custo_real_mao_de_obra_por_os where service_order_id = v_os[1]) = v_custo[1]
    and (select quem_trabalhou from public.v_custo_real_mao_de_obra_por_os where service_order_id = v_os[1]) is not null,
    (select quem_trabalhou from public.v_custo_real_mao_de_obra_por_os where service_order_id = v_os[1]));

  -- T4. Tirar a OS do dia tira o custo dela.
  perform public.registrar_diaria(v_fav, v_dia, 'inteiro', array[v_os[2]], null, null, null, null, 'painel', v_dono);
  insert into _resultado values ('T4 tirar a OS tira o custo',
    coalesce((select labor_cost_real from public.vw_os_profitability where os_id = v_os[1]), -1) = coalesce(v_custo[1] - round(v_valor / 2, 2), 0)
    and (select labor_cost_real from public.vw_os_profitability where os_id = v_os[2]) = v_custo[2] + round(v_valor / 2, 2),
    'OS 2 agora ' || (select labor_cost_real from public.vw_os_profitability where os_id = v_os[2]));

  -- T5. Técnico não vê custo de mão de obra (RLS das diárias vale através da view).
  select id into v_tec from public.app_users where role = 'technician' order by created_at limit 1;
  if v_tec is null then
    insert into _resultado values ('T5 técnico', true, 'sem técnico cadastrado: pulado');
  else
    perform set_config('request.jwt.claims', json_build_object('sub', v_tec, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_tec::text, true);
    execute 'set local role authenticated';
    select count(*) into v_visto from public.v_custo_real_mao_de_obra_por_os;
    execute 'reset role';
    insert into _resultado values ('T5 técnico', v_visto = 0, v_visto || ' linha(s) de custo visíveis');
  end if;

  -- T6. anon não lê nenhuma das duas.
  insert into _resultado values ('T6 anon',
    not has_table_privilege('anon', 'public.v_custo_real_mao_de_obra_por_os', 'select')
    and not has_table_privilege('anon', 'public.vw_os_profitability', 'select'),
    'sem select para anon');
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
