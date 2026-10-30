-- Prova da medição contra a estimativa do gestor da agenda, Fase 7a (pacote P6; migration 20261031100500), sobre a carteira REAL
-- de 29/10 (o replay: o Lenine marcado pela estimativa, executado e concluído) e a fixture da Fase 6 (as medidas de antes).
-- bancada: depende de 20261031100500
--
--   M0 as portas e o que é (sem fixture): as 3 recriadas sem grant a ninguém (nem service_role), nunca anon; os dias no início
--      STABLE e invoker, o congelar e a medida VOLATILE e definer; search_path fixo
--   M1 _agenda_dias_no_inicio com a fonte orcamento: o Lenine marcado pela estimativa e com check-in em ter 03/11 → os 6 dias da
--      estimativa (5,97 diárias-pessoa), a mesma conta de agenda_meios_da_os; nada em sombra (desligado, sombra, a simulação da
--      sombra, *gestor, só propor*, sem a regra); os dias gravados pelo prazo (o Nelson, 4 dias) pelos passos de antes; o dono
--      que disse os dias depois do check-in tira a estimativa
--   M2 o congelar com dp_no_inicio: em sombra nada; ligado, o Lenine congela 6 dias da estimativa com 5,97 (uma vez); a OS sem
--      linha de planejamento ganha a linha; os dias gravados pelo prazo congelam sem dp; em sombra, não
--   M3 a medida orcamento: válida, fator nulo, fator_orcamento (14 meios-dias reais de 12: 1,17), dp_no_inicio 5,97, dp_reais 7;
--      a definição de antes daria fator 1,17 (o fator aprendido a leria); medir de novo e desligar o gestor não mudam a medida; a
--      inválida (a conferência incompleta) sem fator_orcamento e com as diárias-pessoa; os meios-dias de turno do dono em dp_reais
--   M4 o aprendizado: _agenda_aprender_fator não muda com a medida nova (md5), e muda com a definição de antes (o controle);
--      _agenda_aprender_mo a conta (10 → 11 OS)
--   M5 a diária nasce ligada ao Lenine pela conferência do dia (o João em ter 03/11, o Roberto em qui 05/11), sem nada novo na
--      diária; as alocações do Lenine com duracao_fonte orcamento
--   M6 as cópias: _agenda_dias_no_inicio e _agenda_aprender_congelar (de 20261029100100) e agenda_medir_os (de 20261029100900) sem
--      os blocos "-- FASE 7:"
--   M7 com o portão falso (desligado, sombra, a simulação da sombra, *gestor, só propor*, sem a regra), o congelar e a medida da
--      fixture da Fase 6 saem byte a byte como os de antes (as definições de antes rodadas como pg_temp); ligado, não (o controle)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7a_medicao.sql
--   Seguro em produção: M0 e M6 (as cópias saem PULADO sem as migrations como texto) só leem; M1 a M5 e M7 usam as fixtures e só
--   rodam na bancada (fora dela saem PULADO). Termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;

create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;

-- A OS pelo número e a pessoa pelo primeiro nome (os ids do replay são md5: nunca por id).
create function pg_temp.os(p_numero text) returns uuid language sql stable as $f$
  select so.id from public.service_orders so where so.service_order_number = p_numero
$f$;
create function pg_temp.pessoa(p_nome text) returns uuid language sql stable as $f$
  select p.id from public.payees p where p.name = p_nome order by p.id limit 1
$f$;
-- A hora de Brasília num dia.
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;

-- A função inteira (do "create or replace" ao "$function$;") e só o corpo, a partir do texto da migration.
create function pg_temp.inteira(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  return left(v, position(E'\n$function$;' in v) + length(E'\n$function$;') - 1);
end $f$;
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'\nas $function$' in v) + length(E'\nas $function$'));
  return left(v, position('$function$' in v) - 1);
end $f$;

-- O corpo sem os blocos "-- FASE 7: … -- FASE 7: fim" (o fim lido pelo prefixo).
create function pg_temp.sem_fase7(p_corpo text) returns text language plpgsql as $f$
declare
  v_b text[] := '{}'; v_bloco boolean := false; l text;
begin
  foreach l in array string_to_array(replace(p_corpo, E'\r\n', E'\n'), E'\n') loop
    if not v_bloco and l ~ '^\s*-- FASE 7:' and l !~ '^\s*-- FASE 7: fim' then v_bloco := true; continue; end if;
    if v_bloco then
      if l ~ '^\s*-- FASE 7: fim' then v_bloco := false; end if;
      continue;
    end if;
    v_b := v_b || l;
  end loop;
  return array_to_string(v_b, E'\n');
end $f$;

-- As definições de antes (o P6 copiou delas), como pg_temp: os dias no início e o congelar de 20261029100100, a medida de
-- 20261029100900; as duas últimas chamam os dias no início de antes.
create function pg_temp.criar_as_de_antes() returns boolean language plpgsql as $f$
declare
  v_m6 text := coalesce(current_setting('agenda_teste.mig_medicao_fase6', true), '');
  v_c6 text := coalesce(current_setting('agenda_teste.mig_correcao_calculo_fase6', true), '');
begin
  if v_m6 = '' or v_c6 = '' then
    return false;
  end if;
  if to_regprocedure('pg_temp.dni_antes(uuid)') is null then
    execute replace(pg_temp.inteira(v_m6, '_agenda_dias_no_inicio'), 'create or replace function public._agenda_dias_no_inicio(',
                    'create function pg_temp.dni_antes(');
    execute replace(replace(pg_temp.inteira(v_m6, '_agenda_aprender_congelar'),
                            'create or replace function public._agenda_aprender_congelar(', 'create function pg_temp.congelar_antes('),
                    'public._agenda_dias_no_inicio(', 'pg_temp.dni_antes(');
    execute replace(replace(pg_temp.inteira(v_c6, 'agenda_medir_os'),
                            'create or replace function public.agenda_medir_os(', 'create function pg_temp.medir_antes('),
                    'public._agenda_dias_no_inicio(', 'pg_temp.dni_antes(');
  end if;
  return true;
end $f$;

-- A medida, coluna a coluna (sem medida_em, versao e historico).
create function pg_temp.medida(p_os uuid) returns jsonb language sql stable as $f$
  select to_jsonb(m) - array['medida_em', 'versao', 'historico', 'service_order_id'] from public.agenda_medidas_os m
   where m.service_order_id = p_os
$f$;

-- ── M0. As portas e o que é (sem fixture) ───────────────────────────────────────────────────────────────
with f(assinatura) as (values
  ('public._agenda_dias_no_inicio(uuid)'), ('public._agenda_aprender_congelar(date)'), ('public.agenda_medir_os(uuid, date)'))
insert into _resultado
select 'M0a as 3 recriadas com as portas de antes: internas da rodada do aprendizado, sem grant a ninguém (nem service_role); nunca anon',
       bool_and(not has_function_privilege('anon', f.assinatura, 'execute')
                and not has_function_privilege('authenticated', f.assinatura, 'execute')
                and not has_function_privilege('service_role', f.assinatura, 'execute')),
       string_agg(f.assinatura, ', ') filter (where has_function_privilege('anon', f.assinatura, 'execute')
                                              or has_function_privilege('authenticated', f.assinatura, 'execute')
                                              or has_function_privilege('service_role', f.assinatura, 'execute'))
  from f;
insert into _resultado
select 'M0b as 3 continuam como eram: os dias no início STABLE e invoker; o congelar e a medida VOLATILE e definer; search_path fixo',
       bool_and(coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%')
       and bool_and(case p.proname when '_agenda_dias_no_inicio' then p.provolatile = 's' and not p.prosecdef
                                   else p.provolatile = 'v' and p.prosecdef end) and count(*) = 3,
       string_agg(p.proname || ':' || p.provolatile::text || ':' || p.prosecdef::text, ', ' order by p.proname)
  from pg_proc p
 where p.oid in ('public._agenda_dias_no_inicio(uuid)'::regprocedure, 'public._agenda_aprender_congelar(date)'::regprocedure,
                 'public.agenda_medir_os(uuid, date)'::regprocedure);

-- ── M1, M2, M3 e M5: o Lenine marcado pela estimativa (o replay de 29/10) ──────────────────────────────────────
do $rp$
declare
  v_res   jsonb := '[]'::jsonb;
  c_d29   constant date := date '2026-10-29';
  c_a29   constant timestamptz := timestamptz '2026-10-29 16:52-03';
  c_d03   constant date := date '2026-11-03';
  c_d05   constant date := date '2026-11-05';
  c_d10   constant date := date '2026-11-10';
  c_d11   constant date := date '2026-11-11';
  c_todas constant text[] := '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada,sinal_cobrar}';
  c_est   constant jsonb := '{"em": "2026-11-03", "dp": 5.97, "dias": 6, "fonte": "orcamento", "origem": "estimativa"}';
  v_len   uuid;
  v_nel   uuid;
  v_adm   uuid;
  v_joao  uuid;
  v_rob   uuid;
  v_ws    uuid;
  r       jsonb;
  r2      jsonb;
  v       jsonb;
  v_t     text;
  v_ok    boolean;
  v_n     int;
  d       date;
  x       record;
  m       public.agenda_medidas_os;
  pl      public.os_planejamento;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = '' or not pg_temp.criar_as_de_antes() then
    insert into _resultado values ('M1, M2, M3 e M5 (o replay de 29/10)', true,
      'PULADO: sem agenda_teste.replay2910, mig_medicao_fase6 e mig_correcao_calculo_fase6 (rode pela bancada)');
    return;
  end if;
  -- tudo numa subtransação desfeita no fim: o replay apaga o mundo sintético de 23/10, e os blocos seguintes usam a fixture da Fase 6
  begin
  execute current_setting('agenda_teste.replay2910');
  v_len := pg_temp.os('OS-00074');
  v_nel := pg_temp.os('OS-00112');
  v_joao := pg_temp.pessoa('João');
  v_rob := pg_temp.pessoa('Roberto');
  select u.id into v_adm from public.app_users u where u.role = 'admin' order by u.id limit 1;
  -- a presença do dono do Lenine como em produção (abre e fecha; o replay dá "sempre": notas do P2)
  insert into public.os_planejamento (service_order_id, dono_presenca) values (v_len, 'abre_e_fecha')
  on conflict (service_order_id) do update set dono_presenca = 'abre_e_fecha';
  update public.agenda_config set modo_marcar_sozinho = 'ligado', gestor_so_propor = false, marcar_regras = c_todas where id;

  -- qui 29/10: o gestor marca o Lenine pela estimativa (6 dias, 1 pessoa por meio-dia; a reserva vira compromisso)
  r := public.agenda_propor('os', null, null, array[v_len], '{}'::jsonb, true, 'motor', null, c_d29, c_a29);
  r2 := public.agenda_aplicar((r ->> 'proposta_id')::uuid, null, 'motor', null, null, c_d29, c_a29);
  select string_agg(format('%s %s %s', a.dia, a.turno, public._agenda_nome_curto(p.name)), ' | ' order by a.dia, a.turno),
         bool_and(a.duracao_fonte = 'orcamento')
    into v_t, v_ok
    from public.agenda_alocacoes a join public.payees p on p.id = a.payee_id
   where a.service_order_id = v_len and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno';
  v_res := pg_temp.ok(v_res, 'M5a o gestor marca o Lenine pela estimativa: 12 meios-dias de 1 pessoa (João ter 03 e qua 04/11, Roberto qui 05 a ter 10/11), todas as alocações com duracao_fonte orcamento',
    (r2 ->> 'ok')::boolean and v_ok
    and v_t = '2026-11-03 manha João | 2026-11-03 tarde João | 2026-11-04 manha João | 2026-11-04 tarde João | '
           || '2026-11-05 manha Roberto | 2026-11-05 tarde Roberto | 2026-11-06 manha Roberto | 2026-11-06 tarde Roberto | '
           || '2026-11-09 manha Roberto | 2026-11-09 tarde Roberto | 2026-11-10 manha Roberto | 2026-11-10 tarde Roberto'
    and not exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_len and a.estado in ('publicada', 'fixada')
                     and a.tipo <> 'reserva' and a.duracao_fonte is distinct from 'orcamento'),
    coalesce(v_t, '—') || ' / ' || (r2 ->> 'texto'));

  -- ter 03/11 17:30: o dono confere o dia (*dia feito*) → o check-in do Lenine e a diária do João ligada a ele
  r := public.agenda_conferir_dia(v_adm, 'cumprido', null, null, 'whatsapp', c_d03, pg_temp.em(c_d03, '17:30'));
  select ws.id, ws.fracao, (select array_agg(wo.service_order_id) from public.work_shift_os wo where wo.shift_id = ws.id) as os
    into x
    from public.work_shifts ws join public.work_profiles wp on wp.id = ws.work_profile_id
   where wp.payee_id = v_joao and ws.data = c_d03;
  v_res := pg_temp.ok(v_res, 'M5b a conferência de ter 03/11 lança a diária do João (dia inteiro) ligada ao Lenine, e as alocações dele nesse dia apontam para ela',
    (r ->> 'ok')::boolean and x.fracao = 1 and x.os = array[v_len]
    and r ->> 'texto' like '%Lancei a diária: João (dia, R$ 200,00).%'
    and not exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_len and a.payee_id = v_joao and a.dia = c_d03
                     and a.estado in ('publicada', 'fixada') and a.work_shift_id is distinct from x.id)
    and (select (check_in_at at time zone 'America/Sao_Paulo')::date from public.service_orders where id = v_len) = c_d03,
    r ->> 'texto');

  -- ── M1. _agenda_dias_no_inicio com a fonte orcamento ──
  v := public._agenda_dias_no_inicio(v_len);
  v_res := pg_temp.ok(v_res, 'M1a ligado, com o check-in de ter 03/11 e sem dias ditos: os dias que o gestor usou — 6 dias da estimativa, 5,97 diárias-pessoa (origem estimativa)',
    v = c_est, coalesce(v::text, 'nulo'));
  r := public.agenda_meios_da_os(v_len, c_d03);
  v_res := pg_temp.ok(v_res, 'M1b a mesma conta de agenda_meios_da_os no dia do check-in (fonte orcamento, 6 dias)',
    r ->> 'fonte' = 'orcamento' and (r ->> 'dias')::numeric = (v ->> 'dias')::numeric, r ->> 'fonte' || ' ' || (r ->> 'dias'));
  v_t := '';
  v_ok := true;
  for x in select * from (values
      ('desligado', 'desligado', false, c_todas, ''),
      ('sombra', 'sombra', false, c_todas, ''),
      ('a simulação da sombra', 'sombra', false, c_todas, 'sombra'),
      ('gestor, só propor', 'ligado', true, c_todas, ''),
      ('ligado sem a regra estimativa', 'ligado', false, array_remove(c_todas, 'estimativa'), '')
    ) t(nome, modo, so_propor, regras, var)
  loop
    update public.agenda_config set modo_marcar_sozinho = x.modo, gestor_so_propor = x.so_propor, marcar_regras = x.regras where id;
    perform set_config('agenda.gestor', x.var, true);
    v := public._agenda_dias_no_inicio(v_len);
    perform set_config('agenda.gestor', '', true);
    if v is not null or pg_temp.dni_antes(v_len) is not null then
      v_ok := false;
      v_t := v_t || format('[%s: %s] ', x.nome, v);
    end if;
  end loop;
  update public.agenda_config set modo_marcar_sozinho = 'ligado', gestor_so_propor = false, marcar_regras = c_todas where id;
  v_res := pg_temp.ok(v_res, 'M1c nada em sombra: desligado, sombra, dentro da simulação da sombra, *gestor, só propor* e sem a regra estimativa, nulo (como a definição de antes)',
    v_ok, nullif(v_t, ''));
  -- os dias que o gestor gravou quando a pergunta venceu (sex 30/10 18:07: o Nelson, 4 dias) e o check-in depois (qui 05/11)
  begin
    insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em)
    values (v_nel, 4, 'orcamento', timestamptz '2026-10-30 18:07-03')
    on conflict (service_order_id) do update set dias = 4, estimativa_fonte = 'orcamento', estimativa_em = timestamptz '2026-10-30 18:07-03';
    perform set_config('agenda.porta', 'on', true);
    update public.service_orders set check_in_at = pg_temp.em(c_d05, '08:00') where id = v_nel;
    perform set_config('agenda.porta', 'off', true);
    v := public._agenda_dias_no_inicio(v_nel);
    update public.agenda_config set modo_marcar_sozinho = 'desligado' where id;
    r := public._agenda_dias_no_inicio(v_nel);
    update public.agenda_config set modo_marcar_sozinho = 'ligado' where id;
    v_res := pg_temp.ok(v_res, 'M1d os dias gravados pelo prazo (Nelson, 4 dias) saem pelos passos de antes, com a fonte orcamento e sem dp, ligado ou não',
      v = '{"em": "2026-11-05", "dias": 4.0, "fonte": "orcamento", "origem": "atual"}' and r = v, v::text || ' / ' || r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- o dono diz os dias depois do check-in (qua 04/11): sem o congelado, não há estimativa (o congelar do dia do check-in a guarda)
  begin
    update public.os_planejamento set dias = 5, estimativa_fonte = 'dono', estimativa_em = pg_temp.em(date '2026-11-04', '10:00')
     where service_order_id = v_len;
    v := public._agenda_dias_no_inicio(v_len);
    v_res := pg_temp.ok(v_res, 'M1e o dono disse os dias só depois do check-in: nulo (nem os dele, nem a estimativa)', v is null, v::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── M2. O congelar com dp_no_inicio ──
  begin
    update public.agenda_config set modo_marcar_sozinho = 'sombra' where id;
    r := public._agenda_aprender_congelar(c_d03);
    r2 := pg_temp.congelar_antes(c_d03);
    v_res := pg_temp.ok(v_res, 'M2a em sombra nada congela (como antes): o Lenine fica sem os dias do início',
      r = r2 and r ->> 'congeladas' = '0'
      and (select dias_no_inicio is null and dp_no_inicio is null from public.os_planejamento where service_order_id = v_len),
      r::text || ' / ' || r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- a OS sem linha de planejamento (a linha tirada no teste): o congelar a cria
    delete from public.os_planejamento where service_order_id = v_len;
    v := public._agenda_dias_no_inicio(v_len);
    r := public._agenda_aprender_congelar(c_d03);
    select * into pl from public.os_planejamento where service_order_id = v_len;
    v_res := pg_temp.ok(v_res, 'M2b a OS sem linha de planejamento: a estimativa no dia do check-in e a linha nasce no congelar (só os dias do início; os de agora nulos)',
      v = c_est and r ->> 'congeladas' = '1'
      and pl.dias is null and pl.estimativa_fonte is null and pl.dias_no_inicio = 6 and pl.dias_no_inicio_fonte = 'orcamento'
      and pl.dias_no_inicio_em = c_d03 and pl.dp_no_inicio = 5.97 and pl.dono_presenca is null,
      r::text || ' / ' || to_jsonb(pl)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- os dias gravados pelo prazo (o Nelson) congelam sem dp; em sombra, não
    insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em)
    values (v_nel, 4, 'orcamento', timestamptz '2026-10-30 18:07-03')
    on conflict (service_order_id) do update set dias = 4, estimativa_fonte = 'orcamento', estimativa_em = timestamptz '2026-10-30 18:07-03';
    perform set_config('agenda.porta', 'on', true);
    update public.service_orders set check_in_at = pg_temp.em(c_d05, '08:00') where id = v_nel;
    perform set_config('agenda.porta', 'off', true);
    update public.agenda_config set modo_marcar_sozinho = 'sombra' where id;
    r2 := public._agenda_aprender_congelar(c_d05);
    v_ok := (select dias_no_inicio is null from public.os_planejamento where service_order_id = v_nel);
    update public.agenda_config set modo_marcar_sozinho = 'ligado' where id;
    r := public._agenda_aprender_congelar(c_d05);
    select * into pl from public.os_planejamento where service_order_id = v_nel;
    v_res := pg_temp.ok(v_res, 'M2c os dias gravados pelo prazo (Nelson, 4 dias): ligado, congelam com a fonte orcamento e sem dp; em sombra, não',
      v_ok and r2 ->> 'congeladas' = '0' and pl.dias_no_inicio = 4 and pl.dias_no_inicio_fonte = 'orcamento'
      and pl.dias_no_inicio_em = c_d05 and pl.dp_no_inicio is null,
      r2::text || ' / ' || r::text || ' / ' || to_jsonb(pl)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- ligado, no dia do check-in (o tique da rodada das 16:00, depois da conferência): o Lenine congela uma vez
  r := public._agenda_aprender_congelar(c_d03);
  r2 := public._agenda_aprender_congelar(c_d03);
  select * into pl from public.os_planejamento where service_order_id = v_len;
  v_res := pg_temp.ok(v_res, 'M2d ligado: o Lenine congela os 6 dias da estimativa, com 5,97 diárias-pessoa (dp_no_inicio), uma vez só; a definição de antes não congelaria',
    r ->> 'congeladas' = '1' and r2 ->> 'congeladas' = '0'
    and pl.dias_no_inicio = 6 and pl.dias_no_inicio_fonte = 'orcamento' and pl.dias_no_inicio_em = c_d03 and pl.dp_no_inicio = 5.97
    and pl.dias is null and pl.dono_presenca = 'abre_e_fecha'
    and public._agenda_dias_no_inicio(v_len) = '{"em": "2026-11-03", "dias": 6.0, "fonte": "orcamento", "origem": "coluna"}',
    r::text || ' / ' || r2::text || ' / ' || to_jsonb(pl)::text);

  -- qua 04 a seg 09/11: as conferências do dia (as diárias de João e Roberto)
  foreach d in array array[date '2026-11-04', date '2026-11-05', date '2026-11-06', date '2026-11-09'] loop
    r := public.agenda_conferir_dia(v_adm, 'cumprido', null, null, 'whatsapp', d, pg_temp.em(d, '17:30'));
  end loop;
  select ws.fracao, (select array_agg(wo.service_order_id) from public.work_shift_os wo where wo.shift_id = ws.id) as os into x
    from public.work_shifts ws join public.work_profiles wp on wp.id = ws.work_profile_id
   where wp.payee_id = v_rob and ws.data = c_d05;
  v_res := pg_temp.ok(v_res, 'M5c a conferência de qui 05/11 lança a diária do Roberto ligada ao Lenine (o caminho de sempre: nada novo na diária)',
    x.fracao = 1 and x.os = array[v_len], to_jsonb(x)::text);

  -- ── M3. A medida orcamento ──
  begin
    -- a inválida: concluída na ter 10/11 sem a conferência do dia (os 2 meios-dias do Roberto sem registro)
    perform set_config('agenda.porta', 'on', true);
    update public.service_orders set status = 'completed', check_out_at = pg_temp.em(c_d10, '17:00') where id = v_len;
    perform set_config('agenda.porta', 'off', true);
    perform public.agenda_medir_os(v_len, c_d10);
    v := pg_temp.medida(v_len);
    v_res := pg_temp.ok(v_res, 'M3a a medida por estimativa inválida (a conferência incompleta): sem fator nem fator_orcamento, com as diárias-pessoa estimadas (5,97) e as reais (5 diárias ligadas)',
      v ->> 'valida' = 'false' and v ->> 'motivo' = 'conferencia_incompleta' and v ->> 'dias_fonte' = 'orcamento'
      and v -> 'fator' = 'null'::jsonb and v -> 'fator_orcamento' = 'null'::jsonb
      and (v ->> 'dp_no_inicio')::numeric = 5.97 and (v ->> 'dp_reais')::numeric = 5 and (v ->> 'diarias_ligadas')::numeric = 5,
      v::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- ter 10/11: a última conferência; qua 11/11: o João volta um dia fora do plano (a diária ligada ao Lenine) e o serviço termina
  r := public.agenda_conferir_dia(v_adm, 'cumprido', null, null, 'whatsapp', c_d10, pg_temp.em(c_d10, '17:30'));
  -- (a diária fora do plano entra direto: registrar_diaria recusa dia depois do relógio da bancada)
  insert into public.work_shifts (work_profile_id, data, tipo, origem, status, observacao, registrado_por, aprovado_por,
                                  aprovado_em, fracao, valor_diaria, extras, descontos)
  select w.id, c_d11, 'diaria', 'painel', 'aprovado', 'TESTE AG7a: um dia fora do plano', v_adm, v_adm, pg_temp.em(c_d11, '18:00'),
         1, w.valor_diaria, 0, 0
    from public.work_profiles w
   where w.payee_id = v_joao and w.modo_pagamento = 'diaria' and w.vigencia_inicio <= c_d11
     and (w.vigencia_fim is null or w.vigencia_fim >= c_d11)
   order by w.vigencia_inicio desc limit 1
  returning id into v_ws;
  insert into public.work_shift_os (shift_id, service_order_id) values (v_ws, v_len);
  perform set_config('agenda.porta', 'on', true);
  update public.service_orders set status = 'completed', check_out_at = pg_temp.em(c_d11, '17:00') where id = v_len;
  perform set_config('agenda.porta', 'off', true);
  -- o controle: a definição de antes daria fator a essa OS (e o fator aprendido, ligado, a leria)
  begin
    r2 := pg_temp.medir_antes(v_len, c_d11);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  r := public.agenda_medir_os(v_len, c_d11);
  v := pg_temp.medida(v_len);
  v_res := pg_temp.ok(v_res, 'M3b a medida por estimativa vale (concluída, check-in, conferência completa, diária ligada): 6 dias da fonte orcamento, 12 meios-dias planejados, 14 reais (12 + 2 fora do plano), fator nulo e fator_orcamento 1,17',
    v ->> 'valida' = 'true' and v -> 'motivo' = 'null'::jsonb and v ->> 'dias_fonte' = 'orcamento'
    and (v ->> 'dias_no_inicio')::numeric = 6 and (v ->> 'meios_planejados')::int = 12 and (v ->> 'meios_cumpridos')::numeric = 14
    and (v ->> 'meios_fora_do_plano')::int = 2 and v -> 'fator' = 'null'::jsonb and (v ->> 'fator_orcamento')::numeric = 1.17
    and (r ->> 'valida')::boolean and r -> 'fator' = 'null'::jsonb,
    v::text);
  v_res := pg_temp.ok(v_res, 'M3c as diárias-pessoa: estimadas 5,97 (as congeladas no check-in) e reais 7 (7 diárias ligadas: João 3, Roberto 4; o dono só abre e fecha)',
    (v ->> 'dp_no_inicio')::numeric = 5.97 and (v ->> 'dp_reais')::numeric = 7 and (v ->> 'diarias_ligadas')::numeric = 7
    and v ->> 'so_o_dono' = 'false' and (v ->> 'mo')::numeric = 4560, v::text);
  v_res := pg_temp.ok(v_res, 'M3d o controle: a definição de antes (20261029100900) daria a essa OS o fator 1,17 — o que o aprendizado do fator leria',
    (r2 ->> 'valida')::boolean and (r2 ->> 'fator')::numeric = 1.17, r2::text);
  r := public.agenda_medir_os(v_len, c_d11);
  update public.agenda_config set modo_marcar_sozinho = 'desligado' where id;
  r2 := public.agenda_medir_os(v_len, c_d11);
  select * into m from public.agenda_medidas_os where service_order_id = v_len;
  v_res := pg_temp.ok(v_res, 'M3e medir de novo não muda nada, e desligar o gestor depois também não (a medida não tem portão: o fator fica à parte)',
    r ->> 'mudou' = 'false' and r2 ->> 'mudou' = 'false' and m.versao = 1 and m.fator is null and m.fator_orcamento = 1.17,
    r::text || ' / ' || r2::text);
  update public.agenda_config set modo_marcar_sozinho = 'ligado' where id;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$rp$;

-- ── M3f e M4: a fixture da Fase 6 (as medidas de antes) ──────────────────────────────────────────────────────
do $f6$
declare
  v_res   jsonb := '[]'::jsonb;
  c_hoje  constant date := date '2026-10-30';
  c_agora constant timestamptz := timestamptz '2026-10-30 16:05-03';
  c_regras constant text[] := '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada,sinal_cobrar}';
  c_141   constant uuid := '05000000-0000-4000-8000-000000000141';
  c_140   constant uuid := '05000000-0000-4000-8000-000000000140';
  v_md0   text;
  v_md1   text;
  v_md2   text;
  v_f0    jsonb;
  v_f1    jsonb;
  v_mo0   public.agenda_aprendizado;
  v_mo1   public.agenda_aprendizado;
  v       jsonb;
  r       record;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' or not pg_temp.criar_as_de_antes() then
    insert into _resultado values ('M3f e M4 (a fixture da Fase 6)', true,
      'PULADO: sem agenda_teste.fase6, mig_medicao_fase6 e mig_correcao_calculo_fase6 (rode pela bancada)');
    return;
  end if;
  begin
  execute current_setting('agenda_teste.fase6');
  update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = '{fator,mo}' where id;

  -- sem o gestor (as medidas de antes): o fator e o R$ por diária aprendidos
  begin
    perform public._agenda_aprender_medir(c_hoje);
    v_f0 := public._agenda_aprender_fator(c_hoje, c_agora);
    select md5(string_agg(format('%s %s %s %s %s %s %s', a.chave, a.nivel, a.calculado, a.n, a.estado, a.em_uso, a.amostra), '|' order by a.chave))
      into v_md0 from public.agenda_aprendizado a where a.item = 'fator';
    perform public._agenda_aprender_mo(c_hoje, c_agora);
    select * into v_mo0 from public.agenda_aprendizado a where a.item = 'mo';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- com o gestor ligado (sem a regra da peça embutida, para a 141 ser marcada pela estimativa): a 141 passa a medida orcamento
  update public.agenda_config set modo_marcar_sozinho = 'ligado', gestor_so_propor = false, marcar_regras = c_regras where id;
  begin
    v := public._agenda_dias_no_inicio(c_141);
    perform public._agenda_aprender_congelar(c_hoje);
    perform public._agenda_aprender_medir(c_hoje);
    v_res := pg_temp.ok(v_res, 'M4a com o gestor ligado, a 141 (antes "dias sugeridos") é medida contra a estimativa do check-in (2 dias, 1,81 diárias-pessoa): vale, sem fator, fator_orcamento 0,50 (2 meios-dias de 4), dp_reais 1',
      v = '{"em": "2026-09-23", "dp": 1.81, "dias": 2, "fonte": "orcamento", "origem": "estimativa"}'
      and (select m.valida and m.dias_fonte = 'orcamento' and m.fator is null and m.fator_orcamento = 0.50 and m.dp_no_inicio = 1.81
                  and m.dp_reais = 1.00 and m.meios_planejados = 4
             from public.agenda_medidas_os m where m.service_order_id = c_141),
      v::text || ' / ' || pg_temp.medida(c_141)::text);
    v_f1 := public._agenda_aprender_fator(c_hoje, c_agora);
    select md5(string_agg(format('%s %s %s %s %s %s %s', a.chave, a.nivel, a.calculado, a.n, a.estado, a.em_uso, a.amostra), '|' order by a.chave))
      into v_md1 from public.agenda_aprendizado a where a.item = 'fator';
    v_res := pg_temp.ok(v_res, 'M4b o fator aprendido não muda com a medida nova: a mesma saída e as mesmas linhas (md5) que sem o gestor',
      v_md1 = v_md0 and v_f1 = v_f0, v_f0::text || ' / ' || v_f1::text);
    perform public._agenda_aprender_mo(c_hoje, c_agora);
    select * into v_mo1 from public.agenda_aprendizado a where a.item = 'mo';
    v_res := pg_temp.ok(v_res, 'M4c o R$ por diária aprendido conta a OS por estimativa: 10 → 11 OS com diária ligada, a 141 na amostra',
      v_mo0.n = 10 and v_mo1.n = 11 and v_mo1.amostra @> jsonb_build_array(jsonb_build_object('numero', 'OS-00141'))
      and not v_mo0.amostra @> jsonb_build_array(jsonb_build_object('numero', 'OS-00141')),
      format('antes %s %s; depois %s %s', v_mo0.n, v_mo0.detalhe, v_mo1.n, v_mo1.detalhe));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- o controle: a medida de antes, com o gestor ligado, daria fator à 141 e o fator aprendido mudaria
  begin
    perform public._agenda_aprender_congelar(c_hoje);
    for r in select so.id from public.service_orders so where so.status in ('completed', 'invoiced') order by so.id loop
      perform pg_temp.medir_antes(r.id, c_hoje);
    end loop;
    perform public._agenda_aprender_fator(c_hoje, c_agora);
    select md5(string_agg(format('%s %s %s %s %s %s %s', a.chave, a.nivel, a.calculado, a.n, a.estado, a.em_uso, a.amostra), '|' order by a.chave))
      into v_md2 from public.agenda_aprendizado a where a.item = 'fator';
    v_res := pg_temp.ok(v_res, 'M4d o controle: com a definição de antes, a 141 ganharia o fator 0,50 e o fator aprendido mudaria (md5 diferente)',
      v_md2 <> v_md0 and (select m.fator = 0.50 from public.agenda_medidas_os m where m.service_order_id = c_141),
      pg_temp.medida(c_141)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- os meios-dias de turno do dono: a 140 (diagnóstico, só o dono, 2 meios-dias de turno) com os dias congelados como estimativa
  begin
    update public.os_planejamento set dias_no_inicio = 1, dias_no_inicio_fonte = 'orcamento', dias_no_inicio_em = date '2026-09-21',
                                      dp_no_inicio = 0.33
     where service_order_id = c_140;
    perform public.agenda_medir_os(c_140, c_hoje);
    v := pg_temp.medida(c_140);
    v_res := pg_temp.ok(v_res, 'M3f a OS só do dono por estimativa: vale, fator_orcamento 1,00, dp_reais 1 (nenhuma diária + os 2 meios-dias de turno dele ÷ 2), dp_no_inicio o congelado',
      v ->> 'valida' = 'true' and v ->> 'so_o_dono' = 'true' and v -> 'fator' = 'null'::jsonb and (v ->> 'fator_orcamento')::numeric = 1
      and (v ->> 'dp_reais')::numeric = 1 and (v ->> 'diarias_ligadas')::numeric = 0 and (v ->> 'dp_no_inicio')::numeric = 0.33,
      v::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$f6$;

-- ── M7. Com o portão falso, byte a byte as de antes (a fixture da Fase 6) ─────────────────────────────────────
do $m7$
declare
  c_hoje  constant date := date '2026-10-30';
  c_todas constant text[] := '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada,sinal_cobrar}';
  x       record;
  r       record;
  v_novo  text;
  v_antes text;
  v_det   text := '';
  v_ok    boolean := true;
  v_ctl   boolean;
  s       text;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' or not pg_temp.criar_as_de_antes() then
    insert into _resultado values ('M7 o portão falso (a fixture da Fase 6)', true,
      'PULADO: sem agenda_teste.fase6, mig_medicao_fase6 e mig_correcao_calculo_fase6 (rode pela bancada)');
    return;
  end if;
  begin
  execute current_setting('agenda_teste.fase6');
  for x in select * from (values
      ('desligado', 'desligado', false, c_todas, ''),
      ('sombra', 'sombra', false, c_todas, ''),
      ('a simulação da sombra', 'sombra', false, c_todas, 'sombra'),
      ('gestor, só propor', 'ligado', true, c_todas, ''),
      ('ligado sem a regra estimativa', 'ligado', false, array_remove(c_todas, 'estimativa'), ''),
      ('ligado (o controle)', 'ligado', false, c_todas, '')
    ) t(nome, modo, so_propor, regras, var)
  loop
    update public.agenda_config set modo_marcar_sozinho = x.modo, gestor_so_propor = x.so_propor, marcar_regras = x.regras where id;
    foreach s in array array['novo', 'antes'] loop
      begin
        perform set_config('agenda.gestor', x.var, true);
        if s = 'novo' then
          v_novo := public._agenda_aprender_congelar(c_hoje)::text;
          for r in select so.id from public.service_orders so where so.status in ('completed', 'invoiced') order by so.id loop
            v_novo := v_novo || coalesce(public._agenda_dias_no_inicio(r.id)::text, '-') || public.agenda_medir_os(r.id, c_hoje)::text;
          end loop;
          select v_novo || md5(string_agg(to_jsonb(pl)::text, '|' order by pl.service_order_id)) into v_novo
            from (select service_order_id, dias_no_inicio, dias_no_inicio_fonte, dias_no_inicio_em, dp_no_inicio
                    from public.os_planejamento) pl;
          select v_novo || md5(string_agg((to_jsonb(m) - 'medida_em')::text, '|' order by m.service_order_id)) into v_novo
            from public.agenda_medidas_os m;
        else
          v_antes := pg_temp.congelar_antes(c_hoje)::text;
          for r in select so.id from public.service_orders so where so.status in ('completed', 'invoiced') order by so.id loop
            v_antes := v_antes || coalesce(pg_temp.dni_antes(r.id)::text, '-') || pg_temp.medir_antes(r.id, c_hoje)::text;
          end loop;
          select v_antes || md5(string_agg(to_jsonb(pl)::text, '|' order by pl.service_order_id)) into v_antes
            from (select service_order_id, dias_no_inicio, dias_no_inicio_fonte, dias_no_inicio_em, dp_no_inicio
                    from public.os_planejamento) pl;
          select v_antes || md5(string_agg((to_jsonb(m) - 'medida_em')::text, '|' order by m.service_order_id)) into v_antes
            from public.agenda_medidas_os m;
        end if;
        perform set_config('agenda.gestor', '', true);
        raise exception 'desfaz' using errcode = 'P0099';
      exception when sqlstate 'P0099' then null;
      end;
    end loop;
    if x.nome = 'ligado (o controle)' then
      v_ctl := v_novo is distinct from v_antes;
    elsif v_novo is distinct from v_antes then
      v_ok := false;
      v_det := v_det || format('[%s] ', x.nome);
    end if;
  end loop;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  insert into _resultado values (
    'M7 com o portão falso (desligado, sombra, a simulação da sombra, *gestor, só propor*, sem a regra), o congelar, os dias no início e a medida das 18 OS concluídas da Fase 6 saem byte a byte como os de antes; ligado, não (o controle: a 141 por estimativa)',
    v_ok and v_ctl, nullif(v_det, ''));
end
$m7$;

-- ── M6. As cópias ───────────────────────────────────────────────────────────────────────────────────────
do $copias$
declare
  v_m6   text := coalesce(current_setting('agenda_teste.mig_medicao_fase6', true), '');
  v_c6   text := coalesce(current_setting('agenda_teste.mig_correcao_calculo_fase6', true), '');
  r      record;
  v_novo text;
  v_n    int;
begin
  if v_m6 = '' or v_c6 = '' then
    insert into _resultado values ('M6 as cópias', true, 'PULADO: sem as migrations como texto (rode pela bancada)');
    return;
  end if;
  for r in select * from (values
      ('_agenda_dias_no_inicio', 'public._agenda_dias_no_inicio(uuid)', v_m6, '20261029100100', 3),
      ('_agenda_aprender_congelar', 'public._agenda_aprender_congelar(date)', v_m6, '20261029100100', 2),
      ('agenda_medir_os', 'public.agenda_medir_os(uuid, date)', v_c6, '20261029100900', 3)
    ) t(nome, assinatura, fonte, versao, blocos)
  loop
    select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = r.assinatura::regprocedure;
    select count(*) into v_n from regexp_matches(v_novo, '-- FASE 7: fim', 'g');
    insert into _resultado
    select format('M6 %s: sem os %s blocos "-- FASE 7:", é o corpo de %s (a mais nova antes da 7a P6)', r.nome, r.blocos, r.versao),
           v_n = r.blocos and pg_temp.corpo(r.fonte, r.nome) <> '' and pg_temp.sem_fase7(v_novo) = pg_temp.corpo(r.fonte, r.nome),
           format('blocos %s; fonte %s letras; novo sem os blocos %s letras', v_n, length(pg_temp.corpo(r.fonte, r.nome)),
                  length(pg_temp.sem_fase7(v_novo)));
  end loop;
end
$copias$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
