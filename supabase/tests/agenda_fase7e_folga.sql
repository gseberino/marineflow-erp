-- Prova da folga da semana, da temporada e da urgência no motor da Agenda de Produção, Fase 7e (pacote P4; migration 20261111100300; spec-fase7e §5.3, §8.3 e o bloco R7: R7.3-4, R7.4, R7.5-13, R7.5-14, R7.6, R7.7-3, R7.8, R7.12, R7.13).
-- bancada: depende de 20261111100300
--
--   F0  as funções: portas, tipo
--   F1  a folga medida: os números da §8.2 (0,11), o medindo (semanas, resíduos, σ = 0: R7.4), o piso e o teto, quem conta, o passo, o freio não muda a conta, o erro;
--       F1v a folga em uso que fica sem medida volta ao padrão por passo, com ação e *desfaz* (conferência do P4); F1w o texto de medindo diz o que falta
--   F2  a carga da semana: desligado, sombra, freio = carga_max; ligado 0,84 / 0,74 / 0,79 / 0,70; limites; p_teste; floor com 1 técnico (10 → 7 em 0,75 e 0,70); carga_semana só em ligado e só quando muda o teto
--   F3  o motor e o validador na mesma carga, nos 4 pontos dos 2 ramos (com e sem sábado), semana a semana; o por pessoa não muda sem o teto da equipe
--   F3b a frase da carga e a troca pela do dono (R7.5-14)
--   F4  a urgência: as 3 regras, a OS sem linha, sem chave em sombra (sem urgente_teste), 100% no motor e no validador, o motivo só quando passou do teto, a normal antes da urgente na fila
--   F5g os ganchos do puxar (o P4b é quem chama): o dia, quem vem, a regra 7 estreita, a máscara do local
--   F6  as cópias: tirados os blocos do P4, o corpo é o da origem; o que não se recria
--   M1  sombra = antes, em md5: contexto, motor e validador contra as definições de antes (desligado, sombra, ligado com o freio)
--   M1c sem relógio: com as funções da margem lançando, os 3 caminhos rodam em sombra
--
-- ═══ COMO RODAR ═══  Na bancada: node scripts/bancada-agenda/rodar.mjs. Em produção, só DEPOIS de aplicar a migration, com o OK: npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7e_folga.sql
--   Tudo dentro de begin/rollback. O que usa fixture só roda na bancada (fora dela sai PULADO). Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;

create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;

-- ── F0. As funções (sem fixture) ─────────────────────────────────────────────────────────────────
insert into _resultado
select 'F0a as 2 leituras: authenticated e service_role, nunca anon nem public; stable, invoker, search_path fixo',
       count(*) = 2
       and bool_and(not has_function_privilege('anon', p.oid, 'execute'))
       and bool_and(not coalesce((select bool_or(a.grantee = 0) from aclexplode(p.proacl) a where a.privilege_type = 'EXECUTE'), false))
       and bool_and(has_function_privilege('authenticated', p.oid, 'execute') and has_function_privilege('service_role', p.oid, 'execute'))
       and bool_and(p.provolatile = 's' and not p.prosecdef and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')),
       string_agg(p.proname, ', ')
  from pg_proc p where p.oid in ('public._agenda_carga_da_semana(date, boolean)'::regprocedure, 'public._agenda_os_urgente(uuid, date)'::regprocedure);

insert into _resultado
select 'F0b o passo da rodada: definer, volatile, search_path fixo, sem porta para ninguém (anon, authenticated, service_role nem public)',
       p.prosecdef and p.provolatile = 'v' and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')
       and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('service_role', p.oid, 'execute')
       and not coalesce((select bool_or(a.grantee = 0) from aclexplode(p.proacl) a where a.privilege_type = 'EXECUTE'), false),
       p.proacl::text
  from pg_proc p where p.oid = 'public._agenda_aprender_folga_semana(date, timestamptz)'::regprocedure;

-- ── A fixture e os ajudantes ───────────────────────────────────────────────────────────────────
do $carga$
begin
  if coalesce(current_setting('agenda_teste.fase7e', true), '') <> '' then
    execute current_setting('agenda_teste.fase7e');
    perform set_config('marineflow.agrupar_orcamentos', 'on', true);
    update public.service_orders set merged_into_id = 'e7e00000-0000-4000-8000-000000000e00'
     where service_order_number not like 'OS-7E%' and service_order_number <> 'OS-E0' and merged_into_id is null;
    perform set_config('marineflow.agrupar_orcamentos', '', true);
  end if;
end
$carga$;

create function pg_temp.fx() returns boolean language sql stable as $f$ select coalesce(current_setting('agenda_teste.fase7e', true), '') <> '' $f$;
create function pg_temp.os(p_nome text) returns uuid language sql immutable as $f$ select md5('e7e:os:' || p_nome)::uuid $f$;
create function pg_temp.adm() returns uuid language sql stable as $f$ select id from public.app_users where role = 'admin' and active order by id limit 1 $f$;
create function pg_temp.pessoa(p_nome text) returns uuid language sql stable as $f$ select id from public.payees where name = p_nome and active limit 1 $f$;
create function pg_temp.lines(p_t text) returns setof text language sql immutable as $f$ select regexp_split_to_table(p_t, E'\n') $f$;
create function pg_temp.sem_p4(p_t text) returns text language plpgsql immutable as $f$
declare
  l text;
  fora text[] := '{}';
  dentro boolean := false;
begin
  for l in select pg_temp.lines(replace(p_t, E'\r\n', E'\n')) loop
    if not dentro and l ~ '^\s*-- (FASE 7e: \(7e P4|\(7e P4)' then dentro := true; continue; end if;
    if dentro and l ~ '^\s*-- (FASE 7e: fim|\(7e: fim\))' then dentro := false; continue; end if;
    if dentro then continue; end if;
    fora := fora || l;
  end loop;
  return array_to_string(fora, E'\n');
end $f$;
create function pg_temp.inteira(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  return left(v, position(E'\n$function$;' in v) + length(E'\n$function$;') - 1);
end $f$;
create function pg_temp.regra(p_v jsonb, p_n int) returns text language sql immutable as $f$
  select coalesce(string_agg(e ->> 'texto', ' | ' order by o), '-')
    from jsonb_array_elements(coalesce(p_v, '[]'::jsonb)) with ordinality t(e, o) where (e ->> 'regra')::int = p_n
$f$;
-- Os modos: a folga, a urgência, o freio e o portão do teto da equipe (com uma_pessoa: a equipe do serviço é 1, como em produção)
create function pg_temp.modos(p_folga text, p_urg text, p_freio boolean, p_regra boolean default true) returns void language sql as $f$
  update public.agenda_config set modo_folga_semana = p_folga, modo_urgencia = p_urg, modo_aprendizado = 'ligado', gestor_so_propor = p_freio, modo_marcar_sozinho = 'ligado',
         marcar_regras = case when p_regra then '{teto_equipe,uma_pessoa}'::text[] else '{uma_pessoa}'::text[] end where id
$f$;
-- A folga em uso (a linha que o gravador deixa)
create function pg_temp.folga(p_uso numeric) returns void language sql as $f$
  insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, calculado, em_uso, estado, calculado_em)
  values ('folga_semana', 'equipe', 'geral', 0.15, 8, 8, p_uso, p_uso, 'em_uso', now())
  on conflict (item, chave) do update set em_uso = excluded.em_uso, calculado = excluded.calculado, estado = 'em_uso'
$f$;
-- Os resíduos todos iguais (σ = 0): a razão de cada OS medida passa a ser o viés calculado da classe dela
create function pg_temp.sigma_zero() returns void language plpgsql as $f$
begin
  set local session_replication_role = replica;
  update public.agenda_medidas_os m set razao_estimativa = (select a.calculado from public.agenda_aprendizado a where a.item = 'vies' and a.chave = 'estimativa:' || m.classe_bem || ':' || m.classe_sistema)
   where m.motivo_razao is null and m.razao_estimativa is not null;
  set local session_replication_role = origin;
end $f$;
-- As ações do aprendizado da folga, e a carga de uma semana sem temporada (12/04: 0,80 + 0,15 − a folga em uso; em janeiro, o piso de 0,60 esconderia o passo)
create function pg_temp.acoes_folga() returns int language sql stable as $f$ select count(*)::int from public.agenda_acoes where tipo = 'aprendizado' and antes ->> 'item' = 'folga_semana' $f$;
create function pg_temp.carga_abr() returns numeric language sql stable as $f$ select (public._agenda_carga_da_semana(date '2027-04-12') ->> 'carga')::numeric $f$;
-- A semana só com o Alex na equipe (a régua de produção: 1 técnico)
create function pg_temp.so_alex(p_seg date) returns void language sql as $f$
  insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, criado_por)
  select p.id, daterange(p_seg, p_seg + 6, '[]'), 'indisponivel', 'dono', 'teste 7e P4: só o Alex nesta semana', pg_temp.adm()
    from public.payees p where p.name in ('Bruno', 'João', 'Rafael', 'Roberto') and p.active
$f$;
-- Uma OS pronta para o motor, com os dias ditos pelo dono (sem ele no turno)
create function pg_temp.pronta(p_n int, p_dias numeric, p_prio smallint default null, p_prec date default null, p_priority text default 'normal') returns uuid language plpgsql as $f$
declare
  v_os uuid := md5('e7e:f:' || p_n)::uuid;
begin
  perform set_config('agenda.porta', 'on', true);
  insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at, converted_to_os_at, grand_total, priority)
  values (v_os, 'OS-7EF' || p_n, 'e7e00000-0000-4000-8000-000000000c02', 'e7e00000-0000-4000-8000-000000000b02', 'open', 'approved', 'repair',
          timestamptz '2026-12-01 10:00-03', timestamptz '2026-12-01 10:00-03', timestamptz '2026-12-02 10:00-03', 1000, p_priority);
  insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at)
  values (v_os, 'Reparo do quadro', 'visit', 1, 1000, 1000, timestamptz '2026-12-01 10:00-03');
  perform set_config('agenda.porta', 'off', true);
  insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, dono_presenca, material_conferido_em, prioridade_manual, precisa_ate)
  values (v_os, p_dias, 'dono', timestamptz '2026-12-05 10:00-03', 'nunca', timestamptz '2026-12-05 10:00-03', p_prio, p_prec);
  return v_os;
end $f$;
-- Publica N meios-dias de uma pessoa, a partir da manhã de p_de, em dias úteis (o que já está na semana)
create function pg_temp.publica(p_os uuid, p_quem uuid, p_n int, p_de date) returns void language plpgsql as $f$
declare
  v_d date := p_de;
  v_t text := 'manha';
  k   int;
begin
  for k in 1 .. p_n loop
    while not public.agenda_dia_util(v_d) loop v_d := v_d + 1; end loop;
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    values (p_os, p_quem, v_d, v_t, 'turno', 'execucao', 'publicada', 'motor', timestamptz '2027-01-07 10:00-03');
    if v_t = 'manha' then v_t := 'tarde'; else v_t := 'manha'; v_d := v_d + 1; end if;
  end loop;
end $f$;
create function pg_temp.item(p_os uuid, p_numero text, p_quem uuid, p_nome text, p_dia date, p_turno text default 'manha', p_tipo text default 'execucao', p_extra jsonb default '{}') returns jsonb language sql immutable as $f$
  select jsonb_build_object('op', 'criar', 'os', p_os, 'numero', p_numero, 'tipo', p_tipo,
           'alocacoes', jsonb_build_array(jsonb_build_object('payee_id', p_quem, 'nome', p_nome, 'dia', p_dia, 'turno', p_turno, 'presenca', 'turno'))) || p_extra
$f$;
create function pg_temp.pr(p_os uuid[], p_de date, p_ate date, p_hoje date, p_agora timestamptz, p_restr jsonb default '{}'::jsonb) returns jsonb language sql as $f$
  select public.agenda_propor('os', p_de, p_ate, p_os, p_restr, false, 'motor', null, p_hoje, p_agora)
$f$;
create function pg_temp.sem(p_de date, p_ate date, p_hoje date, p_agora timestamptz, p_restr jsonb default '{}'::jsonb) returns jsonb language sql as $f$
  select public.agenda_propor('semana', p_de, p_ate, null, p_restr, false, 'motor', null, p_hoje, p_agora)
$f$;
-- OS fora do caminho do motor
create function pg_temp.fora(p_os uuid[]) returns void language plpgsql as $f$
begin
  perform set_config('marineflow.agrupar_orcamentos', 'on', true);
  update public.service_orders set merged_into_id = 'e7e00000-0000-4000-8000-000000000e00' where id = any (p_os);
  perform set_config('marineflow.agrupar_orcamentos', '', true);
end $f$;
create function pg_temp.criar(p jsonb, p_os uuid) returns jsonb language sql immutable as $f$
  select i from jsonb_array_elements(p -> 'itens') i where i ->> 'op' = 'criar' and i ->> 'os' = p_os::text and i ->> 'tipo' <> 'reserva' limit 1
$f$;
create function pg_temp.reserva(p jsonb, p_os uuid) returns jsonb language sql immutable as $f$
  select i from jsonb_array_elements(p -> 'itens') i where i ->> 'op' = 'criar' and i ->> 'os' = p_os::text and i ->> 'tipo' = 'reserva' limit 1
$f$;
create function pg_temp.sem_aprendizado(p_where text) returns void language plpgsql as $f$
begin
  set local session_replication_role = replica;
  execute format('delete from public.agenda_aprendizado where %s', p_where);
  set local session_replication_role = origin;
end $f$;
create function pg_temp.limpa_janela() returns void language plpgsql as $f$
begin
  set local session_replication_role = replica;
  delete from public.agenda_alocacoes where dia between date '2026-10-12' and date '2027-01-03';
  set local session_replication_role = origin;
end $f$;
-- A história da folga (§8.2): p_ps = os pessoa-meios por OS na semana de p_seg, em dias úteis, 2 pessoas
create function pg_temp.semana(p_seg date, p_ps int[], p_base int) returns void language plpgsql as $f$
declare
  p int;
  k int := 0;
  v_cel int := 0;
  v_os uuid;
begin
  foreach p in array p_ps loop
    k := k + 1;
    v_os := pg_temp.pronta(p_base + k, 1);
    update public.service_orders set status = 'completed' where id = v_os;
    for i in 1 .. p loop
      insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
      values (v_os, case when v_cel % 2 = 0 then 'e7e00000-0000-4000-8000-00000000aa01'::uuid else 'e7e00000-0000-4000-8000-00000000aa02'::uuid end,
              p_seg + (v_cel / 4), case when (v_cel / 2) % 2 = 0 then 'manha' else 'tarde' end, 'turno', 'execucao', 'publicada', 'motor', p_seg - 7);
      v_cel := v_cel + 1;
    end loop;
  end loop;
end $f$;

-- ── F1. A folga medida ─────────────────────────────────────────────────────────────────────────
do $f1$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-01-07';
  c_agora constant timestamptz := timestamptz '2027-01-07 16:05-03';
  r  jsonb;
  r2 jsonb;
  v_a public.agenda_aprendizado%rowtype;
  v_ac public.agenda_acoes%rowtype;
  v_c numeric;
  v_n int;
  v_err int;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'F1 a folga', true, 'PULADO: sem a fixture (rode pela bancada)'));
    return;
  end if;
  begin
    perform set_config('marineflow.agrupar_orcamentos', 'on', true);
    update public.service_orders set merged_into_id = 'e7e00000-0000-4000-8000-000000000e00' where id in (pg_temp.os('V1'), pg_temp.os('Z1'), pg_temp.os('R1'));
    perform set_config('marineflow.agrupar_orcamentos', '', true);
    update public.agenda_config set modo_aprendizado = 'ligado', modo_vies = 'sombra', modo_folga_semana = 'sombra', gestor_so_propor = true where id;
    perform public._agenda_aprender_congelar(c_hoje);
    perform public._agenda_aprender_medir(c_hoje);
    perform public._agenda_aprender_vies(c_hoje, c_agora);
    perform pg_temp.limpa_janela();
    perform pg_temp.semana(date '2026-11-02', array[2,2,2,2], 100);
    perform pg_temp.semana(date '2026-11-09', array[4,2,2,2], 110);
    perform pg_temp.semana(date '2026-11-16', array[2,2,2,2,2], 120);
    perform pg_temp.semana(date '2026-11-23', array[4,4,2], 130);
    perform pg_temp.semana(date '2026-11-30', array[2,2,2,2], 140);
    perform pg_temp.semana(date '2026-12-07', array[6,2,2], 150);
    perform pg_temp.semana(date '2026-12-14', array[2,2,2,2,2], 160);
    perform pg_temp.semana(date '2026-12-21', array[4,2,2,2], 170);

    r := public._agenda_aprender_folga_semana(c_hoje, c_agora);
    select * into v_a from public.agenda_aprendizado where item = 'folga_semana' and chave = 'equipe';
    v_res := pg_temp.ok(v_res, 'F1a 8 semanas (a de 28/12 sem compromisso não conta) e 8 resíduos (os 2 do dono não entram: razao_estimativa nula); sem erro',
      (r ->> 'semanas')::int = 8 and (r ->> 'residuos')::int = 8 and (r ->> 'erros')::int = 0, r::text);
    v_res := pg_temp.ok(v_res, 'F1b a mediana de g = 0,5146 e z = 0,8416 (o P80), como na §8.2',
      round((r ->> 'g')::numeric, 4) = 0.5146 and (v_a.detalhe ->> 'z')::numeric = 0.8416, v_a.detalhe::text);
    v_res := pg_temp.ok(v_res, 'F1c o calculado da §8.2: 0,11 (σ pelo viés calculado da classe, arredondado como está na linha: 0,2534; a §8.2 usava o sem arredondar, 0,2551)',
      v_a.calculado = 0.11 and (r ->> 'calculado')::numeric = 0.11 and round((r ->> 'sigma')::numeric, 4) = 0.2534, r::text);
    v_res := pg_temp.ok(v_res, 'F1d em teste: estado sombra, nada em uso, n = 8, a chave geral, o padrão 0,15 e a amostra {semana, g, pm, os}',
      v_a.estado = 'sombra' and v_a.em_uso is null and v_a.n = 8 and v_a.nivel = 'geral' and v_a.padrao = 0.15 and v_a.n_min = 8
      and jsonb_array_length(v_a.amostra) = 8 and (v_a.amostra -> 0) ?& array['semana', 'g', 'pm', 'os']
      and (select count(*) = 1 from jsonb_array_elements(v_a.amostra) e where e ->> 'semana' = '2026-12-07' and (e ->> 'pm')::numeric = 10 and (e ->> 'os')::int = 3 and (e ->> 'g')::numeric = 0.6633),
      v_a.amostra::text);
    r2 := public._agenda_aprender_folga_semana(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'F1e rodar de novo dá o mesmo calculado e nenhuma ação', (r2 ->> 'calculado')::numeric = 0.11 and r2 ->> 'acao_id' is null, r2::text);

    -- o passo: o alvo 0,08 anda de 0,15 para 0,10 e depois 0,08
    begin
      update public.agenda_config set modo_folga_semana = 'ligado', folga_semana_max = 0.08, folga_percentil = 0.95 where id;
      r := public._agenda_aprender_folga_semana(c_hoje, c_agora);
      select * into v_a from public.agenda_aprendizado where item = 'folga_semana' and chave = 'equipe';
      v_res := pg_temp.ok(v_res, 'F1f o teto folga_semana_max (0,08) e o passo: de 0,15 para 0,10 na 1ª rodada (o alvo fica no calculado)',
        (r ->> 'calculado')::numeric = 0.08 and v_a.em_uso = 0.10 and v_a.estado = 'em_uso', r::text || ' em_uso ' || v_a.em_uso);
      r := public._agenda_aprender_folga_semana(c_hoje, c_agora);
      select * into v_a from public.agenda_aprendizado where item = 'folga_semana' and chave = 'equipe';
      v_res := pg_temp.ok(v_res, 'F1g a 2ª rodada põe 0,08', v_a.em_uso = 0.08, 'em_uso ' || v_a.em_uso);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;

    -- o piso folga_semana_min no lugar do zero (R7.4)
    begin
      update public.agenda_config set folga_percentil = 0.50 where id;
      r := public._agenda_aprender_folga_semana(c_hoje, c_agora);
      v_res := pg_temp.ok(v_res, 'F1h com z = 0, o piso folga_semana_min (0,05), e não 0 (R7.4)', (r ->> 'calculado')::numeric = 0.05, r::text);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;

    -- a linha de 7 semanas = medindo
    begin
      set local session_replication_role = replica;
      delete from public.agenda_alocacoes where dia between date '2026-12-21' and date '2026-12-27';
      set local session_replication_role = origin;
      r := public._agenda_aprender_folga_semana(c_hoje, c_agora);
      select * into v_a from public.agenda_aprendizado where item = 'folga_semana' and chave = 'equipe';
      v_res := pg_temp.ok(v_res, 'F1i com 7 semanas: calculado nulo, medindo', r ->> 'calculado' is null and (r ->> 'semanas')::int = 7 and v_a.estado = 'medindo' and v_a.calculado is null and v_a.n = 7, r::text);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;

    -- com 5 resíduos (a amostra máxima) = medindo
    begin
      update public.agenda_config set fator_amostra_max = 6, folga_residuos_min = 7 where id;
      r := public._agenda_aprender_folga_semana(c_hoje, c_agora);
      v_res := pg_temp.ok(v_res, 'F1j menos resíduos que o mínimo (6, as 6 mais recentes, para um mínimo de 7): medindo, mesmo com 8 semanas', r ->> 'calculado' is null and (r ->> 'residuos')::int = 6 and (r ->> 'semanas')::int = 8, r::text);
      v_res := pg_temp.ok(v_res, 'F1j2 a amostra são as 6 medidas mais recentes (o σ delas), não as mais antigas',
        (r ->> 'sigma')::numeric = (with x as (select m.razao_estimativa / coalesce((select a.calculado from public.agenda_aprendizado a where a.item = 'vies' and a.chave = 'estimativa:' || m.classe_bem || ':' || m.classe_sistema), (select a.calculado from public.agenda_aprendizado a where a.item = 'vies' and a.chave = 'estimativa:todas')) as rr
                                                 from public.agenda_medidas_os m where m.motivo_razao is null and m.razao_estimativa is not null order by m.concluida_em desc, m.service_order_id limit 6),
                                         md as (select public._agenda_percentil(array(select rr from x), 0.5) mr)
                                    select round(14826::numeric / 10000 * public._agenda_percentil(array(select abs(x.rr - md.mr) from x, md), 0.5), 4)),
        r::text);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;

    -- σ = 0 (R7.4: o dia feito ecoa o plano): medindo, e não folga 0
    begin
      set local session_replication_role = replica;
      update public.agenda_medidas_os m set razao_estimativa = (select a.calculado from public.agenda_aprendizado a where a.item = 'vies' and a.chave = 'estimativa:' || m.classe_bem || ':' || m.classe_sistema)
       where m.motivo_razao is null and m.razao_estimativa is not null;
      set local session_replication_role = origin;
      r := public._agenda_aprender_folga_semana(c_hoje, c_agora);
      select * into v_a from public.agenda_aprendizado where item = 'folga_semana' and chave = 'equipe';
      v_res := pg_temp.ok(v_res, 'F1k σ = 0: calculado nulo, medindo (a carga não sobe por falta de medida; R7.4)',
        r ->> 'calculado' is null and (r ->> 'sigma')::numeric = 0 and v_a.estado = 'medindo', r::text);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;

    -- sem viés calculado de ninguém: sem resíduo e sem divisão por nulo
    begin
      perform pg_temp.sem_aprendizado($$item = 'vies'$$);
      r := public._agenda_aprender_folga_semana(c_hoje, c_agora);
      v_res := pg_temp.ok(v_res, 'F1l sem o viés calculado: 0 resíduos, σ nulo, medindo, sem erro (R7.12-2)',
        (r ->> 'residuos')::int = 0 and r ->> 'sigma' is null and r ->> 'calculado' is null and (r ->> 'erros')::int = 0, r::text);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;

    -- sem a fina, o geral
    begin
      perform pg_temp.sem_aprendizado($$item = 'vies' and chave <> 'estimativa:todas'$$);
      r := public._agenda_aprender_folga_semana(c_hoje, c_agora);
      v_res := pg_temp.ok(v_res, 'F1m sem a classe fina, o viés geral (estimativa:todas): 8 resíduos e σ calculado', (r ->> 'residuos')::int = 8 and r ->> 'sigma' is not null, r::text);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;

    -- janela: medidas de fora da janela não entram
    begin
      r := public._agenda_aprender_folga_semana(c_hoje + 800, c_agora);
      v_res := pg_temp.ok(v_res, 'F1n fora de aprender_janela_dias (800 dias depois, janela de 365), a medida não entra', (r ->> 'residuos')::int = 0, r::text);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;

    -- quem conta: reserva, cancelada, proposta e presença curta não; a semana de hoje e a de fora de folga_semanas não
    begin
      insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, reserva_de) values
        (md5('e7e:f:101')::uuid, 'e7e00000-0000-4000-8000-00000000aa01', date '2026-11-06', 'tarde', 'turno', 'reserva', 'publicada', 'motor', timestamptz '2026-11-01 10:00-03', 'teto');
      insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, cancelada_em, cancelada_motivo) values
        (md5('e7e:f:101')::uuid, 'e7e00000-0000-4000-8000-00000000aa02', date '2026-11-06', 'tarde', 'turno', 'execucao', 'cancelada', 'motor', timestamptz '2026-11-01 10:00-03', timestamptz '2026-11-02 10:00-03', 'replanejado');
      insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em) values
        (md5('e7e:f:101')::uuid, public._agenda_dono(null), date '2026-11-05', 'tarde', 'abertura', 'execucao', 'publicada', 'motor', timestamptz '2026-11-01 10:00-03');
      r := public._agenda_aprender_folga_semana(c_hoje, c_agora);
      select * into v_a from public.agenda_aprendizado where item = 'folga_semana' and chave = 'equipe';
      v_res := pg_temp.ok(v_res, 'F1o reserva, cancelada e presença curta não entram: a semana de 02/11 continua 8 pessoa-meios e g = 0,5',
        (select (e ->> 'pm')::numeric = 8 and (e ->> 'g')::numeric = 0.5 from jsonb_array_elements(v_a.amostra) e where e ->> 'semana' = '2026-11-02'), v_a.amostra::text);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;

    -- fixada conta; a semana só com pouco serviço não conta (folga_meios_min); a semana de hoje e antes de folga_semanas não entram
    begin
      insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, fixado_por) values
        (md5('e7e:f:101')::uuid, 'e7e00000-0000-4000-8000-00000000aa02', date '2026-11-06', 'tarde', 'turno', 'execucao', 'fixada', 'motor', timestamptz '2026-11-01 10:00-03', 'dono');
      insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em) values
        (md5('e7e:f:101')::uuid, 'e7e00000-0000-4000-8000-00000000aa02', date '2026-12-28', 'manha', 'turno', 'execucao', 'publicada', 'motor', timestamptz '2026-12-20 10:00-03'),
        (md5('e7e:f:101')::uuid, 'e7e00000-0000-4000-8000-00000000aa02', date '2027-01-05', 'manha', 'turno', 'execucao', 'publicada', 'motor', timestamptz '2026-12-20 10:00-03'),
        (md5('e7e:f:101')::uuid, 'e7e00000-0000-4000-8000-00000000aa02', date '2027-01-05', 'tarde', 'turno', 'execucao', 'publicada', 'motor', timestamptz '2026-12-20 10:00-03'),
        (md5('e7e:f:101')::uuid, 'e7e00000-0000-4000-8000-00000000aa01', date '2027-01-05', 'manha', 'turno', 'execucao', 'publicada', 'motor', timestamptz '2026-12-20 10:00-03'),
        (md5('e7e:f:101')::uuid, 'e7e00000-0000-4000-8000-00000000aa01', date '2027-01-05', 'tarde', 'turno', 'execucao', 'publicada', 'motor', timestamptz '2026-12-20 10:00-03');
      r := public._agenda_aprender_folga_semana(c_hoje, c_agora);
      select * into v_a from public.agenda_aprendizado where item = 'folga_semana' and chave = 'equipe';
      v_res := pg_temp.ok(v_res, 'F1p a fixada conta (02/11 vai a 9 pessoa-meios); a semana de 28/12 com 1 meio-dia não conta (folga_meios_min); a semana de hoje (04/01) não é semana completa',
        (select (e ->> 'pm')::numeric = 9 from jsonb_array_elements(v_a.amostra) e where e ->> 'semana' = '2026-11-02')
        and (r ->> 'semanas')::int = 8
        and not exists (select 1 from jsonb_array_elements(v_a.amostra) e where e ->> 'semana' in ('2026-12-28', '2027-01-04')), v_a.amostra::text);
      update public.agenda_config set folga_semanas = 8, folga_semanas_min = 4 where id;
      r := public._agenda_aprender_folga_semana(c_hoje, c_agora);
      select * into v_a from public.agenda_aprendizado where item = 'folga_semana' and chave = 'equipe';
      v_res := pg_temp.ok(v_res, 'F1q folga_semanas = 8 olha só as 8 semanas antes de hoje (de 09/11 a 28/12): a de 02/11 sai',
        (r ->> 'semanas')::int = 7 and not exists (select 1 from jsonb_array_elements(v_a.amostra) e where e ->> 'semana' = '2026-11-02'), v_a.amostra::text);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;

    -- (correção da conferência) a folga em uso que fica sem medida volta ao padrão por passo, com ação e *desfaz*; e o texto diz o que falta
    -- σ = 0 com a folga em uso: 0,30 → 0,25 → 0,20 → 0,15 → medindo (a carga anda junto; a ação e o texto em cada passo)
    begin
      update public.agenda_config set modo_folga_semana = 'ligado', gestor_so_propor = false where id;
      perform pg_temp.folga(0.30);
      perform pg_temp.sigma_zero();
      v_c := pg_temp.carga_abr();
      r := public._agenda_aprender_folga_semana(c_hoje, c_agora);
      select * into v_a from public.agenda_aprendizado where item = 'folga_semana' and chave = 'equipe';
      v_res := pg_temp.ok(v_res, 'F1v1 σ = 0 com a folga em uso (0,30): anda um passo para o padrão (0,25), continua em uso, sem calculado inventado e com o n de verdade',
        v_a.estado = 'em_uso' and v_a.em_uso = 0.25 and v_a.calculado is null and v_a.n = 8 and r ->> 'calculado' is null and r ->> 'estado' = 'em_uso' and (r ->> 'em_uso')::numeric = 0.25, r::text);
      v_res := pg_temp.ok(v_res, 'F1v2 a carga da semana muda só um passo: 0,65 → 0,70', v_c = 0.65 and pg_temp.carga_abr() = 0.70, v_c || ' -> ' || pg_temp.carga_abr());
      select * into v_ac from public.agenda_acoes where tipo = 'aprendizado' and antes ->> 'item' = 'folga_semana' order by criada_em desc limit 1;
      v_res := pg_temp.ok(v_res, 'F1v3 nasce 1 ação aprendizado (de 0,30 para 0,25), executada, com *desfaz* e a conta de quem a faz',
        pg_temp.acoes_folga() = 1 and v_ac.executada and v_ac.desfazivel_ate is not null and (v_ac.antes ->> 'em_uso')::numeric = 0.30 and (v_ac.depois ->> 'em_uso')::numeric = 0.25 and (r ->> 'acao_id')::uuid = v_ac.id, row_to_json(v_ac)::text);
      v_res := pg_temp.ok(v_res, 'F1v4 a ação diz o que mudou, sem "medi"',
        v_ac.texto = 'Fiquei sem medida para a folga da semana (as 8 OS medidas ainda não mostraram variação). Passei a guardar 25% da semana para o serviço que passa do previsto (era 30%) e volto aos 15% de sempre aos poucos. *desfaz aprendizado* volta.', v_ac.texto);
      v_res := pg_temp.ok(v_res, 'F1v5 a linha do foco, a caminho do padrão',
        v_a.texto = 'Sem medida para a folga da semana (as 8 OS medidas ainda não mostraram variação): guardo 25% da semana para o serviço que passa do previsto desde qui 07/01 e volto aos 15% de sempre aos poucos.', v_a.texto);
      r := public._agenda_aprender_folga_semana(c_hoje, c_agora + interval '1 minute');
      v_c := pg_temp.carga_abr();
      select * into v_a from public.agenda_aprendizado where item = 'folga_semana' and chave = 'equipe';
      v_res := pg_temp.ok(v_res, 'F1v6 a 2ª rodada: 0,20 e a carga 0,75', v_a.em_uso = 0.20 and v_a.estado = 'em_uso' and v_c = 0.75, r::text || ' c ' || v_c);
      r := public._agenda_aprender_folga_semana(c_hoje, c_agora + interval '2 minute');
      v_c := pg_temp.carga_abr();
      select * into v_a from public.agenda_aprendizado where item = 'folga_semana' and chave = 'equipe';
      select * into v_ac from public.agenda_acoes where tipo = 'aprendizado' and antes ->> 'item' = 'folga_semana' order by criada_em desc limit 1;
      v_res := pg_temp.ok(v_res, 'F1v7 a 3ª rodada chega ao padrão: 0,15, a carga 0,80, 3 ações, nenhum passo maior que 0,05', v_a.em_uso = 0.15 and v_a.estado = 'em_uso' and v_c = 0.80 and pg_temp.acoes_folga() = 3, r::text || ' c ' || v_c);
      v_res := pg_temp.ok(v_res, 'F1v8 o último passo não promete voltar "aos poucos": a ação e o foco dizem que voltou',
        v_ac.texto = 'Fiquei sem medida para a folga da semana (as 8 OS medidas ainda não mostraram variação). Voltei a guardar os 15% de sempre da semana para o serviço que passa do previsto (era 20%). *desfaz aprendizado* volta.'
        and v_a.texto = 'Sem medida para a folga da semana (as 8 OS medidas ainda não mostraram variação): voltei a guardar os 15% de sempre da semana para o serviço que passa do previsto.', v_ac.texto || ' / ' || v_a.texto);
      r := public._agenda_aprender_folga_semana(c_hoje, c_agora + interval '3 minute');
      select * into v_a from public.agenda_aprendizado where item = 'folga_semana' and chave = 'equipe';
      v_res := pg_temp.ok(v_res, 'F1v9 no padrão, a rodada seguinte cai em medindo sem mudar a carga e sem ação (efeito que não muda número não vira texto)',
        v_a.estado = 'medindo' and v_a.em_uso is null and pg_temp.carga_abr() = 0.80 and pg_temp.acoes_folga() = 3 and v_a.texto like 'Folga da semana: as semanas já bastam%', r::text || ' ' || v_a.texto);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;

    -- semanas abaixo do mínimo, com a folga em uso (uma temporada baixa): volta um passo, o n é o de verdade e o texto diz as semanas
    begin
      update public.agenda_config set modo_folga_semana = 'ligado', gestor_so_propor = false where id;
      perform pg_temp.folga(0.20);
      set local session_replication_role = replica;
      delete from public.agenda_alocacoes where dia between date '2026-12-21' and date '2026-12-27';
      set local session_replication_role = origin;
      r := public._agenda_aprender_folga_semana(c_hoje, c_agora);
      select * into v_a from public.agenda_aprendizado where item = 'folga_semana' and chave = 'equipe';
      select * into v_ac from public.agenda_acoes where tipo = 'aprendizado' and antes ->> 'item' = 'folga_semana' order by criada_em desc limit 1;
      v_res := pg_temp.ok(v_res, 'F1v10 com 7 semanas: de 0,20 para 0,15 (um passo), n = 7 de verdade, sem calculado',
        v_a.em_uso = 0.15 and v_a.estado = 'em_uso' and v_a.n = 7 and v_a.calculado is null, r::text);
      v_res := pg_temp.ok(v_res, 'F1v11 a ação diz que faltam semanas', pg_temp.acoes_folga() = 1 and v_ac.texto = 'Fiquei sem medida para a folga da semana (7 de 8 semanas com serviço marcado medidas). Voltei a guardar os 15% de sempre da semana para o serviço que passa do previsto (era 20%). *desfaz aprendizado* volta.', v_ac.texto);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;

    -- resíduos abaixo do mínimo, com a folga em uso
    begin
      update public.agenda_config set modo_folga_semana = 'ligado', gestor_so_propor = false, fator_amostra_max = 6, folga_residuos_min = 7 where id;
      perform pg_temp.folga(0.25);
      r := public._agenda_aprender_folga_semana(c_hoje, c_agora);
      select * into v_a from public.agenda_aprendizado where item = 'folga_semana' and chave = 'equipe';
      v_res := pg_temp.ok(v_res, 'F1v12 com 6 resíduos para um mínimo de 7: de 0,25 para 0,20 e o foco diz quantas OS faltam',
        v_a.em_uso = 0.20 and v_a.texto = 'Sem medida para a folga da semana (6 de 7 OS medidas): guardo 20% da semana para o serviço que passa do previsto desde qui 07/01 e volto aos 15% de sempre aos poucos.', v_a.texto);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;

    -- o *desfaz* da volta: o dono manda; a trava segura sem medida; passada a trava, volta a andar
    begin
      update public.agenda_config set modo_folga_semana = 'ligado', gestor_so_propor = false where id;
      perform pg_temp.folga(0.30);
      perform pg_temp.sigma_zero();
      r := public._agenda_aprender_folga_semana(c_hoje, c_agora);
      select * into v_ac from public.agenda_acoes where tipo = 'aprendizado' and antes ->> 'item' = 'folga_semana' order by criada_em desc limit 1;
      r2 := public._agenda_desfazer_aprendizado(v_ac.id, pg_temp.adm(), 'dono', c_hoje, c_agora + interval '10 minute');
      select * into v_a from public.agenda_aprendizado where item = 'folga_semana' and chave = 'equipe';
      v_res := pg_temp.ok(v_res, 'F1v13 o *desfaz* da volta devolve 0,30, trava e a carga volta a 0,65 (releitura depois da ação)',
        (r2 ->> 'ok')::boolean and v_a.estado = 'travado' and v_a.em_uso = 0.30 and v_a.travado_ate = c_hoje + 28 and pg_temp.carga_abr() = 0.65, r2::text);
      v_res := pg_temp.ok(v_res, 'F1v14 o foco da trava, sem número medido, diz o que falta e até quando',
        v_a.texto = 'Sem medida para a folga da semana (as 8 OS medidas ainda não mostraram variação); fico com 30% até qui 04/02, como você decidiu.', v_a.texto);
      r := public._agenda_aprender_folga_semana(c_hoje + 28, c_agora + interval '28 day');
      select * into v_a from public.agenda_aprendizado where item = 'folga_semana' and chave = 'equipe';
      v_res := pg_temp.ok(v_res, 'F1v15 no último dia da trava, sem medida, a rodada não mexe: 0,30, travado, sem ação nova, a carga igual',
        v_a.estado = 'travado' and v_a.em_uso = 0.30 and v_a.travado_ate = c_hoje + 28 and pg_temp.acoes_folga() = 1 and pg_temp.carga_abr() = 0.65 and r ->> 'estado' = 'travado', r::text);
      r := public._agenda_aprender_folga_semana(c_hoje + 29, c_agora + interval '29 day');
      select * into v_a from public.agenda_aprendizado where item = 'folga_semana' and chave = 'equipe';
      v_res := pg_temp.ok(v_res, 'F1v16 passada a trava, volta a andar um passo, com nova ação', v_a.estado = 'em_uso' and v_a.em_uso = 0.25 and pg_temp.acoes_folga() = 2 and v_a.travado_ate is null, r::text);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;

    -- com o interruptor fora de ligado não há o que trazer de volta (a carga já é a de sempre)
    begin
      update public.agenda_config set modo_folga_semana = 'sombra', gestor_so_propor = false where id;
      perform pg_temp.folga(0.30);
      perform pg_temp.sigma_zero();
      r := public._agenda_aprender_folga_semana(c_hoje, c_agora);
      select * into v_a from public.agenda_aprendizado where item = 'folga_semana' and chave = 'equipe';
      v_res := pg_temp.ok(v_res, 'F1v17 modo_folga_semana em sombra: medindo, em_uso nulo, nenhuma ação', v_a.estado = 'medindo' and v_a.em_uso is null and pg_temp.acoes_folga() = 0, r::text);
      update public.agenda_config set modo_folga_semana = 'ligado', modo_aprendizado = 'sombra' where id;
      perform pg_temp.folga(0.30);
      r := public._agenda_aprender_folga_semana(c_hoje, c_agora);
      select * into v_a from public.agenda_aprendizado where item = 'folga_semana' and chave = 'equipe';
      v_res := pg_temp.ok(v_res, 'F1v18 modo_aprendizado em sombra: medindo, em_uso nulo, nenhuma ação', v_a.estado = 'medindo' and v_a.em_uso is null and pg_temp.acoes_folga() = 0, r::text);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;

    -- em uso no próprio padrão: nada muda, nada é contado
    begin
      update public.agenda_config set modo_folga_semana = 'ligado', gestor_so_propor = false where id;
      perform pg_temp.folga(0.15);
      perform pg_temp.sigma_zero();
      r := public._agenda_aprender_folga_semana(c_hoje, c_agora);
      select * into v_a from public.agenda_aprendizado where item = 'folga_semana' and chave = 'equipe';
      v_res := pg_temp.ok(v_res, 'F1v19 em uso no padrão (0,15): medindo, nenhuma ação', v_a.estado = 'medindo' and v_a.em_uso is null and pg_temp.acoes_folga() = 0, r::text);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;

    -- abaixo do padrão, a volta sobe (o sinal do passo)
    begin
      update public.agenda_config set modo_folga_semana = 'ligado', gestor_so_propor = false where id;
      perform pg_temp.folga(0.05);
      perform pg_temp.sigma_zero();
      r := public._agenda_aprender_folga_semana(c_hoje, c_agora);
      select * into v_a from public.agenda_aprendizado where item = 'folga_semana' and chave = 'equipe';
      select * into v_ac from public.agenda_acoes where tipo = 'aprendizado' and antes ->> 'item' = 'folga_semana' order by criada_em desc limit 1;
      v_res := pg_temp.ok(v_res, 'F1v20 em uso abaixo do padrão (0,05): sobe um passo (0,10), a ação diz de quanto para quanto',
        v_a.em_uso = 0.10 and v_a.estado = 'em_uso' and v_ac.texto = 'Fiquei sem medida para a folga da semana (as 8 OS medidas ainda não mostraram variação). Passei a guardar 10% da semana para o serviço que passa do previsto (era 5%) e volto aos 15% de sempre aos poucos. *desfaz aprendizado* volta.', v_ac.texto);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;

    -- o freio não muda o que o gravador faz (modo cru, R7.6); e só a folga volta por passo
    begin
      update public.agenda_config set modo_folga_semana = 'ligado', gestor_so_propor = true where id;
      perform pg_temp.folga(0.30);
      perform pg_temp.sigma_zero();
      r := public._agenda_aprender_folga_semana(c_hoje, c_agora);
      select * into v_a from public.agenda_aprendizado where item = 'folga_semana' and chave = 'equipe';
      v_res := pg_temp.ok(v_res, 'F1v21 com o freio, o gravador anda igual (modo cru) e a carga fica a de sempre (a medida não depende do freio)',
        v_a.em_uso = 0.25 and v_a.estado = 'em_uso' and pg_temp.acoes_folga() = 1 and pg_temp.carga_abr() = (select carga_max from public.agenda_config where id), r::text);
      update public.agenda_config set modo_tempo_compra = 'ligado', gestor_so_propor = false where id;
      insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, calculado, em_uso, estado, calculado_em)
      values ('tempo_compra', 'todas', 'todas', 2, 3, 5, 4, 4, 'em_uso', c_agora);
      r := public._agenda_aprendizado_gravar('tempo_compra', 'todas', 'todas', null, 5, '[]'::jsonb, 2, '{}'::jsonb, c_agora);
      v_res := pg_temp.ok(v_res, 'F1v22 só a folga volta por passo: o tempo de compra sem medida segue o de antes (medindo, em_uso nulo; achado 162)', r ->> 'estado' = 'medindo' and r ->> 'em_uso' is null, r::text);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;

    -- o caminho normal, com número medido, não muda de texto; e sem resíduo no detalhe é "nenhuma OS"
    v_res := pg_temp.ok(v_res, 'F1w0 com calculado, a linha em uso segue a §6.2 (nada do bloco da volta)',
      public._agenda_aprendizado_texto('folga_semana', 'foco_em_uso', '{"chave": "equipe", "n": 8, "n_min": 8, "padrao": 0.15, "carga_max": 0.8, "calculado": 0.08, "em_uso": 0.10, "efetivo": 0.15, "desde": "2027-01-07"}'::jsonb)
        = 'Pelo quanto as OS variaram em 8 semanas, guardo 10% da semana para o serviço que passa do previsto desde qui 07/01 e chego a 8% aos poucos (era 15%).', null);
    v_res := pg_temp.ok(v_res, 'F1w5 semanas bastando e sem resíduo no detalhe (12 de 8): "nenhuma OS medida ainda", nunca "12 de 8"',
      public._agenda_aprendizado_texto('folga_semana', 'foco_medindo', '{"chave": "equipe", "n": 12, "n_min": 8, "padrao": 0.15, "carga_max": 0.8}'::jsonb)
        = 'Folga da semana: as semanas já bastam (12), mas falta saber o quanto as OS variam: nenhuma OS medida ainda; guardo 20% da semana da equipe (15% para o serviço que passa do previsto e 5% para urgência e falta).', null);
    v_res := pg_temp.ok(v_res, 'F1w6 resíduos no mínimo exato (6 de 6) já não faltam: é a variação que falta',
      public._agenda_aprendizado_texto('folga_semana', 'foco_medindo', '{"chave": "equipe", "n": 12, "n_min": 8, "padrao": 0.15, "carga_max": 0.8, "detalhe": {"residuos": 6, "residuos_min": 6}}'::jsonb)
        = 'Folga da semana: as semanas já bastam (12), mas falta saber o quanto as OS variam: as 6 OS medidas ainda não mostraram variação; guardo 20% da semana da equipe (15% para o serviço que passa do previsto e 5% para urgência e falta).', null);
    -- o texto de medindo: com as semanas bastando, diz o que falta; abaixo delas, a §6.2. Do passo até a linha gravada.
    begin
      update public.agenda_config set folga_semanas_min = 6 where id;
      perform pg_temp.sem_aprendizado($$item = 'vies'$$);
      r := public._agenda_aprender_folga_semana(c_hoje, c_agora);
      select * into v_a from public.agenda_aprendizado where item = 'folga_semana' and chave = 'equipe';
      v_res := pg_temp.ok(v_res, 'F1w1 semanas além do mínimo (8 para 6) e 0 resíduos: reprova o "8 de 6" e diz que nenhuma OS foi medida',
        v_a.n = 8 and v_a.n_min = 6 and v_a.estado = 'medindo' and v_a.texto = 'Folga da semana: as semanas já bastam (8), mas falta saber o quanto as OS variam: nenhuma OS medida ainda; guardo 20% da semana da equipe (15% para o serviço que passa do previsto e 5% para urgência e falta).', v_a.texto);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    begin
      update public.agenda_config set folga_semanas_min = 6, fator_amostra_max = 6, folga_residuos_min = 7 where id;
      r := public._agenda_aprender_folga_semana(c_hoje, c_agora);
      select * into v_a from public.agenda_aprendizado where item = 'folga_semana' and chave = 'equipe';
      v_res := pg_temp.ok(v_res, 'F1w2 resíduos abaixo do mínimo: diz quantos de quantos, nunca "8 de 6 semanas"',
        v_a.estado = 'medindo' and v_a.texto = 'Folga da semana: as semanas já bastam (8), mas falta saber o quanto as OS variam: 6 de 7 OS medidas; guardo 20% da semana da equipe (15% para o serviço que passa do previsto e 5% para urgência e falta).', v_a.texto);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    begin
      perform pg_temp.sigma_zero();
      r := public._agenda_aprender_folga_semana(c_hoje, c_agora);
      select * into v_a from public.agenda_aprendizado where item = 'folga_semana' and chave = 'equipe';
      v_res := pg_temp.ok(v_res, 'F1w3 σ = 0 com 8 semanas para 8 (no mínimo exato já bastam): diz que as OS ainda não variaram',
        v_a.n = 8 and v_a.n_min = 8 and v_a.estado = 'medindo' and v_a.texto = 'Folga da semana: as semanas já bastam (8), mas falta saber o quanto as OS variam: as 8 OS medidas ainda não mostraram variação; guardo 20% da semana da equipe (15% para o serviço que passa do previsto e 5% para urgência e falta).', v_a.texto);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    begin
      set local session_replication_role = replica;
      delete from public.agenda_alocacoes where dia between date '2026-12-21' and date '2026-12-27';
      set local session_replication_role = origin;
      r := public._agenda_aprender_folga_semana(c_hoje, c_agora);
      select * into v_a from public.agenda_aprendizado where item = 'folga_semana' and chave = 'equipe';
      v_res := pg_temp.ok(v_res, 'F1w4 abaixo do mínimo de semanas, o texto da §6.2',
        v_a.estado = 'medindo' and v_a.texto = 'Folga da semana: 7 de 8 semanas com serviço marcado medidas; guardo 20% da semana da equipe (15% para o serviço que passa do previsto e 5% para urgência e falta).', v_a.texto);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;

    -- o freio e o modo não mudam a conta (lição 2): a medida não depende do freio
    begin
      update public.agenda_config set gestor_so_propor = false, modo_folga_semana = 'desligado' where id;
      r := public._agenda_aprender_folga_semana(c_hoje, c_agora);
      update public.agenda_config set gestor_so_propor = true, modo_folga_semana = 'ligado' where id;
      r2 := public._agenda_aprender_folga_semana(c_hoje, c_agora);
      v_res := pg_temp.ok(v_res, 'F1r sem freio e desligado × com freio e ligado: o mesmo calculado (a medida não lê o freio nem o modo)',
        (r ->> 'calculado')::numeric = 0.11 and (r2 ->> 'calculado')::numeric = 0.11 and r ->> 'sigma' = r2 ->> 'sigma', r::text || ' / ' || r2::text);
      select count(*) into v_n from public.agenda_aprendizado where item = 'folga_semana' and chave = 'equipe' and estado = 'em_uso';
      v_res := pg_temp.ok(v_res, 'F1s o gravador usa o modo cru: ligado com freio já entra em uso (soltar o freio não recomeça do padrão; R7.6)', v_n = 1, 'n ' || v_n);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;

    -- o passo que falha registra e segue
    begin
      select count(*) into v_err from public.app_error_logs where context = 'agenda' and action = 'aprender:folga_semana';
      create or replace function public._agenda_aprendizado_gravar(p_item text, p_chave text, p_nivel text, p_calculado numeric, p_n integer, p_amostra jsonb, p_padrao numeric, p_detalhe jsonb, p_agora timestamptz)
        returns jsonb language plpgsql as $x$ begin raise exception 'gravador quebrou'; end $x$;
      r := public._agenda_aprender_folga_semana(c_hoje, c_agora);
      v_res := pg_temp.ok(v_res, 'F1t erro no gravador: não lança, devolve erros = 1 e registra em aprender:folga_semana',
        (r ->> 'erros')::int = 1 and (select count(*) from public.app_error_logs where context = 'agenda' and action = 'aprender:folga_semana') = v_err + 1, r::text);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;

    begin
      r := public._agenda_aprender_folga_semana(null, c_agora);
      v_res := pg_temp.ok(v_res, 'F1u sem o dia, 22023', false, r::text);
    exception when sqlstate '22023' then
      v_res := pg_temp.ok(v_res, 'F1u sem o dia, 22023', true);
    end;
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then
    v_res := pg_temp.ok(v_res, 'F1 sem exceção', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$f1$;

-- ── F2. A carga da semana ───────────────────────────────────────────────────────────────────────
do $f2$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-02-01';
  c_jan constant date := date '2027-01-11';
  c_abr constant date := date '2027-04-12';
  c_nov constant date := date '2026-11-09';
  c_fev constant date := date '2027-02-08';
  v jsonb;
  v_c jsonb;
  r jsonb;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'F2 a carga', true, 'PULADO: sem a fixture (rode pela bancada)'));
    return;
  end if;
  begin
    perform pg_temp.modos('desligado', 'desligado', false);
    v := public._agenda_carga_da_semana(c_jan);
    v_res := pg_temp.ok(v_res, 'F2a desligado: carga_max, a folga padrão, sem dizer temporada nenhuma', (v ->> 'carga')::numeric = 0.80 and (v ->> 'folga')::numeric = 0.15 and (v ->> 'extra')::numeric = 0 and v ->> 'por' is null and v ->> 'texto' is null, v::text);
    perform pg_temp.modos('sombra', 'desligado', false);
    v_res := pg_temp.ok(v_res, 'F2b em sombra: carga_max', (public._agenda_carga_da_semana(c_jan) ->> 'carga')::numeric = 0.80, null);
    perform pg_temp.modos('ligado', 'desligado', true);
    v_res := pg_temp.ok(v_res, 'F2c ligado com o freio: carga_max (o freio manda; R7.6)', (public._agenda_carga_da_semana(c_jan) ->> 'carga')::numeric = 0.80, null);
    perform pg_temp.modos('ligado', 'desligado', false);
    v := public._agenda_carga_da_semana(c_jan);
    v_res := pg_temp.ok(v_res, 'F2d ligado sem a folga medida: jan 0,70 (a temporada de barco, +10%), abr 0,80',
      (v ->> 'carga')::numeric = 0.70 and (v ->> 'extra')::numeric = 0.10 and v ->> 'por' = 'barco' and v ->> 'texto' = 'temporada de barco' and (v ->> 'folga')::numeric = 0.15
      and (public._agenda_carga_da_semana(c_abr) ->> 'carga')::numeric = 0.80, v::text);
    perform pg_temp.folga(0.11);
    v_res := pg_temp.ok(v_res, 'F2e ligado com a folga 0,11: abr 0,84, jan 0,74, nov 0,79 (a §8.2)',
      (public._agenda_carga_da_semana(c_abr) ->> 'carga')::numeric = 0.84 and (public._agenda_carga_da_semana(c_jan) ->> 'carga')::numeric = 0.74
      and (public._agenda_carga_da_semana(c_nov) ->> 'carga')::numeric = 0.79, (public._agenda_carga_da_semana(c_nov))::text);
    update public.agenda_config set modo_aprendizado = 'sombra' where id;
    v_res := pg_temp.ok(v_res, 'F2f com o aprendizado fora, vale o padrão e sobra a temporada: jan 0,70', (public._agenda_carga_da_semana(c_jan) ->> 'carga')::numeric = 0.70, null);
    update public.agenda_config set modo_aprendizado = 'ligado' where id;
    update public.agenda_aprendizado set em_uso = 0.30, calculado = 0.30 where item = 'folga_semana' and chave = 'equipe';
    update public.agenda_config set carga_semana_min = 0.72 where id;
    v_res := pg_temp.ok(v_res, 'F2g o piso carga_semana_min: 0,80 + (0,15 − 0,30) − 0,10 = 0,55 fica em 0,72', (public._agenda_carga_da_semana(c_jan) ->> 'carga')::numeric = 0.72, null);
    update public.agenda_config set carga_semana_min = 0.60 where id;
    update public.agenda_aprendizado set em_uso = 0.05, calculado = 0.05 where item = 'folga_semana' and chave = 'equipe';
    update public.agenda_config set carga_max = 0.88, carga_semana_max = 0.90 where id;
    v_res := pg_temp.ok(v_res, 'F2h o teto carga_semana_max: 0,88 + 0,10 em abr = 0,98 fica em 0,90', (public._agenda_carga_da_semana(c_abr) ->> 'carga')::numeric = 0.90, null);
    update public.agenda_config set carga_max = 0.80, carga_semana_max = 0.95 where id;
    -- p_teste: o que seria, com o calculado em sombra
    perform pg_temp.sem_aprendizado($$item = 'folga_semana'$$);
    perform pg_temp.modos('sombra', 'desligado', false);
    insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, calculado, estado, calculado_em) values ('folga_semana', 'equipe', 'geral', 0.15, 8, 8, 0.11, 'sombra', now());
    v_res := pg_temp.ok(v_res, 'F2i p_teste em sombra: jan 0,74, pelo calculado em teste', (public._agenda_carga_da_semana(c_jan, true) ->> 'carga')::numeric = 0.74 and (public._agenda_carga_da_semana(c_jan, true) ->> 'folga')::numeric = 0.11, null);
    update public.agenda_aprendizado set estado = 'medindo' where item = 'folga_semana';
    v_res := pg_temp.ok(v_res, 'F2j p_teste sem o calculado em sombra (medindo): o padrão, jan 0,70', (public._agenda_carga_da_semana(c_jan, true) ->> 'carga')::numeric = 0.70, null);
    perform pg_temp.sem_aprendizado($$item = 'folga_semana'$$);
    v_res := pg_temp.ok(v_res, 'F2k sem segunda, nulo', public._agenda_carga_da_semana(null) is null, null);

    -- floor com 1 técnico (R7.10-5): 10 → 7 em 0,75 e em 0,70; 8 em 0,80
    perform pg_temp.so_alex(c_fev);
    perform pg_temp.so_alex(c_abr);
    perform pg_temp.modos('ligado', 'desligado', false);
    v_c := public._agenda_contexto(c_fev, c_fev + 6, c_hoje);
    v_res := pg_temp.ok(v_res, 'F2l 1 técnico, sem folga medida, fev (0,70): 10 meios-dias → 7 (floor), carga_semana 0,7', v_c -> 'teto_equipe' = '[7]'::jsonb and v_c -> 'carga_semana' = '[0.70]'::jsonb, concat_ws(' ', v_c -> 'teto_equipe', v_c -> 'carga_semana'));
    perform pg_temp.folga(0.10);
    v_c := public._agenda_contexto(c_fev, c_fev + 6, c_hoje);
    v_res := pg_temp.ok(v_res, 'F2m com a folga 0,10, fev (0,75): 10 → 7 também (a temporada de 5 ou 10% dá o mesmo com 1 técnico; R7.10-5)', v_c -> 'teto_equipe' = '[7]'::jsonb and v_c -> 'carga_semana' = '[0.75]'::jsonb, concat_ws(' ', v_c -> 'teto_equipe', v_c -> 'carga_semana'));
    perform pg_temp.sem_aprendizado($$item = 'folga_semana'$$);
    v_c := public._agenda_contexto(c_abr, c_abr + 6, c_hoje);
    v_res := pg_temp.ok(v_res, 'F2n abr sem nada: 0,80 → 8, igual ao de sempre, e a carga da semana sai carga_max', v_c -> 'teto_equipe' = '[8]'::jsonb and v_c -> 'carga_semana' = '[0.80]'::jsonb, concat_ws(' ', v_c -> 'teto_equipe', v_c -> 'carga_semana'));
    perform pg_temp.folga(0.16);
    v_c := public._agenda_contexto(c_abr, c_abr + 6, c_hoje);
    v_res := pg_temp.ok(v_res, 'F2o abr com a folga 0,16 (0,79): 10 → 7, e carga_semana diz 0,79 (muda o teto)', v_c -> 'teto_equipe' = '[7]'::jsonb and v_c -> 'carga_semana' = '[0.79]'::jsonb, concat_ws(' ', v_c -> 'teto_equipe', v_c -> 'carga_semana'));
    -- esperado 9: floor(0,79 × 9) = 7 = floor(0,80 × 9): o arredondamento apaga o efeito
    insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, criado_por)
    values (pg_temp.pessoa('Alex'), daterange(c_abr + 4, c_abr + 4, '[]'), 'tarde', 'indisponivel', 'dono', 'teste', pg_temp.adm());
    v_c := public._agenda_contexto(c_abr, c_abr + 6, c_hoje);
    v_res := pg_temp.ok(v_res, 'F2p o arredondamento apaga o efeito: esperado 9, 0,79 e 0,80 dão 7: o teto fica e carga_semana diz 0,80 (a carga de antes: nada a dizer)',
      v_c -> 'teto_equipe' = '[7]'::jsonb and v_c -> 'carga_semana' = '[0.80]'::jsonb, concat_ws(' ', v_c -> 'esperado', v_c -> 'teto_equipe', v_c -> 'carga_semana'));
    -- a chave não existe fora de ligado; sem a regra, sem carga da semana
    perform pg_temp.modos('sombra', 'desligado', false);
    v_c := public._agenda_contexto(c_fev, c_fev + 6, c_hoje);
    v_res := pg_temp.ok(v_res, 'F2q em sombra: o teto de sempre (8) e a chave carga_semana ausente', v_c -> 'teto_equipe' = '[8]'::jsonb and not v_c ? 'carga_semana', (v_c -> 'teto_equipe')::text);
    perform pg_temp.modos('ligado', 'desligado', true);
    v_c := public._agenda_contexto(c_fev, c_fev + 6, c_hoje);
    v_res := pg_temp.ok(v_res, 'F2r com o freio: sem teto da equipe e sem a chave (o caminho por pessoa)', not v_c ? 'teto_equipe' and not v_c ? 'carga_semana', null);
    perform pg_temp.modos('ligado', 'desligado', false, false);
    v_c := public._agenda_contexto(c_fev, c_fev + 6, c_hoje);
    v_res := pg_temp.ok(v_res, 'F2s ligado, sem a regra teto_equipe: por pessoa, sem carga da semana (R7.6)', not v_c ? 'teto_equipe' and not v_c ? 'carga_semana', null);
    -- duas semanas com cargas diferentes, cada uma com a sua
    perform pg_temp.modos('ligado', 'desligado', false);
    perform pg_temp.sem_aprendizado($$item = 'folga_semana'$$);
    perform pg_temp.so_alex(date '2027-03-29');
    v_c := public._agenda_contexto(date '2027-03-22', date '2027-04-04', c_hoje);
    v_res := pg_temp.ok(v_res, 'F2t duas semanas: 22/03 é março (a quinta 25/03: +5%) e 29/03 é abril (a quinta 01/04: +0%): cada uma com a sua carga',
      v_c -> 'carga_semana' = '[0.75, 0.80]'::jsonb, (v_c -> 'carga_semana')::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then
    v_res := pg_temp.ok(v_res, 'F2 sem exceção', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$f2$;

-- ── F3. O motor e o validador na mesma carga ────────────────────────────────────────────────────
do $f3$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-02-04';
  c_ag   constant timestamptz := timestamptz '2027-02-04 10:00-03';
  c_fev  constant date := date '2027-02-08';
  c_abr  constant date := date '2027-04-12';
  v_a    uuid;
  v_b    uuid;
  v_oc   uuid;
  v_oc2  uuid;
  v_alex uuid;
  r      jsonb;
  v_it   jsonb;
  v_v    jsonb;
  v_t    text;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'F3 o motor e o validador', true, 'PULADO: sem a fixture (rode pela bancada)'));
    return;
  end if;
  begin
    v_alex := pg_temp.pessoa('Alex');
    perform pg_temp.so_alex(c_fev);
    perform pg_temp.so_alex(c_abr);
    -- a semana de 08/02 com 7 meios-dias do Alex já publicados; o mesmo em 12/04
    perform pg_temp.fora(array(select id from public.service_orders where service_order_number like 'OS-7E%' or service_order_number = 'OS-E0'));
    v_oc := pg_temp.pronta(300, 3.5);
    perform pg_temp.publica(v_oc, v_alex, 7, c_fev);
    v_oc2 := pg_temp.pronta(301, 3.5);
    perform pg_temp.publica(v_oc2, v_alex, 7, c_abr);
    -- os itens da OS nova (1 meio-dia na quinta de cada semana, à tarde: a tarde é a célula livre)
    v_a := pg_temp.pronta(302, 0.5);
    v_b := pg_temp.pronta(303, 0.5);
    v_it := jsonb_build_array(pg_temp.item(v_a, 'OS-7EF302', v_alex, 'Alex', c_fev + 4, 'manha'));

    perform pg_temp.modos('sombra', 'desligado', false);
    v_t := pg_temp.regra(public._agenda_validar_itens(v_it, '{}'::jsonb, c_hoje, c_ag, false), 6);
    v_res := pg_temp.ok(v_res, 'F3a em sombra, a soma da equipe com 80%: 8 meios-dias cabem na semana de 08/02', v_t = '-', v_t);
    perform pg_temp.modos('ligado', 'desligado', false);
    v_t := pg_temp.regra(public._agenda_validar_itens(v_it, '{}'::jsonb, c_hoje, c_ag, false), 6);
    v_res := pg_temp.ok(v_res, 'F3b ligado, 0,70 em fev: a mesma OS passa do limite, com o número da semana (ponto 1 e 2 do ramo sem sábado)', v_t = 'A equipe passaria do limite da semana de 08/02: 8 meios-dias de serviço para 7.', v_t);
    v_v := public._agenda_validar_itens(jsonb_build_array(pg_temp.item(v_b, 'OS-7EF303', v_alex, 'Alex', c_abr + 4, 'manha')), '{}'::jsonb, c_hoje, c_ag, false);
    v_res := pg_temp.ok(v_res, 'F3c abril (0,80): a mesma conta passa na semana dela', pg_temp.regra(v_v, 6) = '-', pg_temp.regra(v_v, 6));
    -- as 2 semanas numa proposta só: cada uma com a carga dela
    v_v := public._agenda_validar_itens(v_it || jsonb_build_array(pg_temp.item(v_b, 'OS-7EF303', v_alex, 'Alex', c_abr + 4, 'manha')), '{}'::jsonb, c_hoje, c_ag, false);
    v_res := pg_temp.ok(v_res, 'F3d uma proposta em 2 semanas: só a de fevereiro passa do limite (a de abril tem a carga dela)', pg_temp.regra(v_v, 6) = 'A equipe passaria do limite da semana de 08/02: 8 meios-dias de serviço para 7.', pg_temp.regra(v_v, 6));
    -- o que o validador deixou como estava: depois da conta da equipe, cf.carga_max e v_n voltam (a regra 7 ainda lê v_n)
    v_v := public._agenda_validar_itens(jsonb_build_array(pg_temp.item(v_a, 'OS-7EF302', v_alex, 'Alex', c_hoje, 'manha')), '{}'::jsonb, c_hoje, c_ag, false);
    v_res := pg_temp.ok(v_res, 'F3e a regra 7 continua valendo com o laço por semana (os dias congelados da proposta)', pg_temp.regra(v_v, 7) <> '-', pg_temp.regra(v_v, 7));
    v_v := public._agenda_validar_itens(jsonb_build_array(pg_temp.item(v_a, 'OS-7EF302', v_alex, 'Alex', c_hoje, 'manha'), pg_temp.item(v_b, 'OS-7EF303', v_alex, 'Alex', c_fev + 4, 'tarde')), '{}'::jsonb, c_hoje, c_ag, false);
    v_res := pg_temp.ok(v_res, 'F3n duas semanas (a 1ª no congelado): depois do laço a regra 7 vê as duas semanas (v_n volta inteiro)', pg_temp.regra(v_v, 7) <> '-', pg_temp.regra(v_v, 7));
    -- acima_da_carga: sem o teto da equipe
    v_t := pg_temp.regra(public._agenda_validar_itens(v_it, '{"p_restricoes": {"acima_da_carga": true}}'::jsonb, c_hoje, c_ag, false), 6);
    v_res := pg_temp.ok(v_res, 'F3f acima_da_carga: sem o teto da equipe (ligado também)', v_t = '-', v_t);

    -- os outros 2 pontos: o ramo com sábado (modo_sabado ligado e o sábado oferecido)
    insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, criado_em, semana_dita)
    values (v_alex, daterange(c_fev + 5, c_fev + 5, '[]'), 'manha', 'disponivel', 'diarista', 'Disse que pode', c_ag, c_fev);
    update public.agenda_config set modo_sabado = 'ligado' where id;
    v_t := pg_temp.regra(public._agenda_validar_itens(v_it, '{}'::jsonb, c_hoje, c_ag, false), 6);
    v_res := pg_temp.ok(v_res, 'F3g ramo do sábado (ligado): 7 + o sábado oferecido = 8 meios-dias de limite: os 8 cabem', v_t = '-', v_t);
    v_t := pg_temp.regra(public._agenda_validar_itens(v_it || jsonb_build_array(pg_temp.item(v_b, 'OS-7EF303', v_alex, 'Alex', c_fev + 4, 'tarde')), '{}'::jsonb, c_hoje, c_ag, false), 6);
    v_res := pg_temp.ok(v_res, 'F3h ramo do sábado: 9 passam do limite de 8 (7 + 1), com o número da semana (ponto 3 e 4)', v_t = 'A equipe passaria do limite da semana de 08/02: 9 meios-dias de serviço para 8.', v_t);
    v_v := public._agenda_validar_itens(jsonb_build_array(pg_temp.item(v_a, 'OS-7EF302', v_alex, 'Alex', c_hoje, 'manha'), pg_temp.item(v_b, 'OS-7EF303', v_alex, 'Alex', c_fev + 4, 'tarde')), '{}'::jsonb, c_hoje, c_ag, false);
    v_res := pg_temp.ok(v_res, 'F3o no ramo do sábado também: depois do laço a regra 7 vê as duas semanas', pg_temp.regra(v_v, 7) <> '-', pg_temp.regra(v_v, 7));
    update public.agenda_config set modo_sabado = 'desligado' where id;
    delete from public.agenda_disponibilidade where payee_id = v_alex and periodo = daterange(c_fev + 5, c_fev + 5, '[]');

    -- o motor: a OS de meio dia não cabe a 70%; com sombra cabe
    perform pg_temp.modos('sombra', 'desligado', false);
    r := pg_temp.sem(c_fev, c_fev + 4, c_hoje, c_ag);
    v_res := pg_temp.ok(v_res, 'F3i em sombra, o motor põe a OS de meio dia na semana de 08/02 (8 de 8)',
      (pg_temp.criar(r, v_a) -> 'alocacoes' -> 0 ->> 'dia')::date between c_fev and c_fev + 4, coalesce((pg_temp.criar(r, v_a))::text, (r -> 'fora')::text));
    perform pg_temp.modos('ligado', 'desligado', false);
    r := pg_temp.sem(c_fev, c_fev + 4, c_hoje, c_ag);
    v_res := pg_temp.ok(v_res, 'F3j ligado (70%): o compromisso não cabe na semana de 08/02 e o motor não lança (motor e validador leem a mesma carga)',
      coalesce((pg_temp.criar(r, v_a) -> 'alocacoes' -> 0 ->> 'dia')::date not between c_fev and c_fev + 4, true), coalesce((pg_temp.criar(r, v_a))::text, 'sem compromisso; reserva: ' || coalesce((pg_temp.reserva(r, v_a))::text, 'nenhuma') || ' fora: ' || (r -> 'fora')::text));
    v_res := pg_temp.ok(v_res, 'F3k a proposta do motor passa no validador com a mesma carga', public._agenda_validar_itens(r -> 'itens', '{"p_restricoes": {}}'::jsonb, c_hoje, c_ag, false) = '[]'::jsonb,
      public._agenda_validar_itens(r -> 'itens', '{"p_restricoes": {}}'::jsonb, c_hoje, c_ag, false)::text);
    -- F3b: a frase da carga. A reserva por teto da semana de 08/02 diz a carga dela
    v_res := pg_temp.ok(v_res, 'F3l a reserva por teto diz a carga da semana (R7.5-14): "não coube na carga de 70%"',
      pg_temp.reserva(r, v_a) -> 'motivos' @> '["não coube na carga de 70%"]'::jsonb, coalesce((pg_temp.reserva(r, v_a))::text, 'sem reserva: ' || (r -> 'itens')::text));
    -- arredondamento: 0,79 com esperado 9 = mesmo teto: a frase fica a de antes
    perform pg_temp.folga(0.16);
    update public.agenda_config set folga_temporada_barco = '{0,0,0,0,0,0,0,0,0,0,0,0}'::numeric(3,2)[], folga_temporada_rv = '{0,0,0,0,0,0,0,0,0,0,0,0}'::numeric(3,2)[] where id;
    insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, criado_por)
    values (v_alex, daterange(c_fev + 4, c_fev + 4, '[]'), 'tarde', 'indisponivel', 'dono', 'teste', pg_temp.adm());
    -- (fica com 8 meios-dias livres: 7 publicados + 1 de manhã na sex; o bloco cai na reserva só se teto = 7)
    r := pg_temp.sem(c_fev, c_fev + 4, c_hoje, c_ag);
    v_res := pg_temp.ok(v_res, 'F3m carga 0,79 e esperado 9: o teto é o mesmo de 0,80 (7): a frase continua "não coube na carga de 80%" (efeito que o arredondamento apaga não é efeito)',
      pg_temp.reserva(r, v_a) -> 'motivos' @> '["não coube na carga de 80%"]'::jsonb, coalesce((pg_temp.reserva(r, v_a))::text, 'sem reserva: ' || (r -> 'itens')::text));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then
    v_res := pg_temp.ok(v_res, 'F3 sem exceção', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$f3$;

-- ── F3c. A troca pela frase do dono ─────────────────────────────────────────────────────────────
do $f3c$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-02-04';
  c_ag   constant timestamptz := timestamptz '2027-02-04 10:00-03';
  c_fev  constant date := date '2027-02-08';
  v_a    uuid;
  v_oc   uuid;
  v_alex uuid;
  v_dono uuid;
  r      jsonb;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'F3c a frase do dono', true, 'PULADO: sem a fixture (rode pela bancada)'));
    return;
  end if;
  begin
    v_alex := pg_temp.pessoa('Alex');
    v_dono := public._agenda_dono(null);
    perform pg_temp.so_alex(c_fev);
    v_oc := pg_temp.pronta(310, 3.5);
    perform pg_temp.publica(v_oc, v_alex, 7, c_fev);
    v_a := pg_temp.pronta(311, 0.5);
    perform pg_temp.fora(array(select id from public.service_orders where service_order_number like 'OS-7E%' and id not in (v_oc, v_a) or service_order_number = 'OS-E0'));
    -- o dono em campo, com a OS precisando dele o turno inteiro, e a parte dele em uso (a régua da Fase 6)
    insert into public.agenda_disponibilidade (payee_id, dias_semana, situacao, origem, nota, criado_por)
    values (v_dono, '{1,2,3,4,5}', 'disponivel', 'dono', 'teste 7e P4: em campo de segunda a sexta', pg_temp.adm());
    update public.os_planejamento set dono_presenca = 'sempre' where service_order_id = v_a;
    insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos) values (v_a, v_alex, 'dia');
    update public.agenda_config set modo_dias = 'desligado', modo_aprendizado = 'ligado', aprendizado_ligados = '{capacidade_dono}' where id;
    insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, calculado, em_uso, estado, calculado_em)
    values ('capacidade_dono', 'dono', 'geral', 0.8, 1, 8, 0.60, 0.60, 'em_uso', now())
    on conflict (item, chave) do update set em_uso = 0.60, calculado = 0.60, estado = 'em_uso';
    perform pg_temp.modos('ligado', 'desligado', false);
    r := pg_temp.sem(c_fev, c_fev + 4, c_hoje, c_ag);
    v_res := pg_temp.ok(v_res, 'F3c1 a OS que precisa do dono, com a parte dele abaixo da carga da semana (60 < 70): a frase do dono entra no lugar da de "carga de 70%" (os 2 pontos da frase usam o mesmo número; R7.5-14)',
      (pg_temp.reserva(r, v_a) -> 'motivos') @> '["não coube na sua parte da semana (60%)"]'::jsonb and not (pg_temp.reserva(r, v_a) -> 'motivos') @> '["não coube na carga de 70%"]'::jsonb,
      coalesce((pg_temp.reserva(r, v_a) -> 'motivos')::text, 'sem reserva; itens: ' || (r -> 'itens')::text));
    -- 0,75: acima da carga da semana (0,70) e abaixo do carga_max (0,80): a comparação é com a carga da semana
    update public.agenda_aprendizado set em_uso = 0.75, calculado = 0.75 where item = 'capacidade_dono' and chave = 'dono';
    r := pg_temp.sem(c_fev, c_fev + 4, c_hoje, c_ag);
    v_res := pg_temp.ok(v_res, 'F3c2 a parte do dono (75%) não está abaixo da carga da semana (70%): a frase fica a da carga',
      (pg_temp.reserva(r, v_a) -> 'motivos') @> '["não coube na carga de 70%"]'::jsonb, coalesce((pg_temp.reserva(r, v_a) -> 'motivos')::text, 'sem reserva'));
    -- sem a folga ligada (sombra): a de antes, com 75 < 80, é a do dono
    perform pg_temp.modos('sombra', 'desligado', false);
    r := pg_temp.sem(c_fev, c_fev + 4, c_hoje, c_ag);
    v_res := pg_temp.ok(v_res, 'F3c3 em sombra (carga 80%, teto 8), a OS ainda cabe: nenhuma reserva nem frase nova', pg_temp.reserva(r, v_a) is null and (r::text) !~ 'carga de', left(r::text, 300));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then
    v_res := pg_temp.ok(v_res, 'F3c sem exceção', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$f3c$;

-- ── F4. A urgência ──────────────────────────────────────────────────────────────────────────────
do $f4$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-02-04';
  c_u    constant date := date '2027-02-01';
  c_ag   constant timestamptz := timestamptz '2027-02-04 10:00-03';
  c_fev  constant date := date '2027-02-08';
  v_a    uuid; v_b uuid; v_c uuid; v_d uuid; v_e uuid; v_oc uuid; v_n uuid; v_u uuid; v_cond uuid;
  v_alex uuid;
  r      jsonb;
  v_i    jsonb;
  v      jsonb;
  v_t    text;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'F4 a urgência', true, 'PULADO: sem a fixture (rode pela bancada)'));
    return;
  end if;
  begin
    v_alex := pg_temp.pessoa('Alex');
    perform pg_temp.so_alex(c_fev);
    -- as 3 regras
    v_a := pg_temp.pronta(400, 0.5, 1::smallint);
    v_b := pg_temp.pronta(401, 0.5, null, null, 'urgent');
    v_c := pg_temp.pronta(402, 0.5, null, date '2027-02-05');
    v_d := pg_temp.pronta(403, 0.5, null, date '2027-02-12');
    v_e := pg_temp.pronta(404, 0.5);
    delete from public.os_planejamento where service_order_id = v_e;
    v := public._agenda_os_urgente(v_a, c_u);
    v_res := pg_temp.ok(v_res, 'F4a prioridade_manual = 1: "passa na frente"', (v ->> 'urgente')::boolean and v ->> 'motivo' = 'prioridade' and v ->> 'texto' = 'passa na frente', v::text);
    v := public._agenda_os_urgente(v_b, c_u);
    update public.os_planejamento set prioridade_manual = 2 where service_order_id = v_a;
    v_res := pg_temp.ok(v_res, 'F4a2 prioridade_manual = 2 não é passar na frente', not (public._agenda_os_urgente(v_a, c_u) ->> 'urgente')::boolean, null);
    update public.os_planejamento set prioridade_manual = 1 where service_order_id = v_a;
    v_res := pg_temp.ok(v_res, 'F4b priority urgent: "marcada como urgente"', (v ->> 'urgente')::boolean and v ->> 'motivo' = 'urgente' and v ->> 'texto' = 'marcada como urgente', v::text);
    v := public._agenda_os_urgente(v_c, c_u);
    v_res := pg_temp.ok(v_res, 'F4c precisa_ate em 4 dias úteis (urgencia_du 5): "o cliente precisa até sex 05/02"', (v ->> 'urgente')::boolean and v ->> 'motivo' = 'prazo' and v ->> 'texto' = 'o cliente precisa até sex 05/02', v::text);
    v := public._agenda_os_urgente(v_d, c_u);
    v_res := pg_temp.ok(v_res, 'F4d precisa_ate em 9 dias úteis: não urgente', not (v ->> 'urgente')::boolean and v ->> 'motivo' is null and v ->> 'texto' is null, v::text);
    v := public._agenda_os_urgente(v_e, c_u);
    v_res := pg_temp.ok(v_res, 'F4e OS sem linha em os_planejamento (o caso comum; R7.12-3): não urgente, sem erro', not (v ->> 'urgente')::boolean, v::text);
    update public.agenda_config set urgencia_du = 9 where id;
    v_res := pg_temp.ok(v_res, 'F4f urgencia_du é o parâmetro (9: a de 12/02 vira urgente)', (public._agenda_os_urgente(v_d, c_u) ->> 'urgente')::boolean, null);
    update public.agenda_config set urgencia_du = 5 where id;
    v := public._agenda_os_urgente(v_c, date '2027-02-08');
    v_res := pg_temp.ok(v_res, 'F4g precisa_ate já passou: continua urgente', (v ->> 'urgente')::boolean, v::text);

    -- a OS urgente no motor. A semana de 08/02 com 7 meios-dias e carga 0,70 (teto 7): ela cabe só com a folga
    perform pg_temp.fora(array(select id from public.service_orders where (service_order_number like 'OS-7E%' or service_order_number = 'OS-E0') and id not in (v_a, v_e)));
    v_oc := pg_temp.pronta(410, 3.5);
    perform pg_temp.publica(v_oc, v_alex, 7, c_fev);
    perform pg_temp.modos('ligado', 'ligado', false);
    r := pg_temp.sem(c_fev, c_fev + 4, c_hoje, c_ag);
    v_i := pg_temp.criar(r, v_a);
    v_res := pg_temp.ok(v_res, 'F4h a urgente cabe na semana cheia (teto100): compromisso em 08/02, mesmo com a equipe no limite (70%)',
      (v_i -> 'alocacoes' -> 0 ->> 'dia')::date between c_fev and c_fev + 4, coalesce(v_i::text, (r -> 'itens')::text));
    v_res := pg_temp.ok(v_res, 'F4i o item leva urgente (a chave do item só em ligado) e o motivo diz o porquê e a folga',
      (v_i ->> 'urgente')::boolean and v_i -> 'motivos' @> '["urgente: passa na frente; usei a folga da semana"]'::jsonb, coalesce((v_i -> 'motivos')::text, ''));
    r := public.agenda_propor('os', c_fev, c_fev + 4, array[v_a], '{}'::jsonb, true, 'motor', null, c_hoje, c_ag);
    v_res := pg_temp.ok(v_res, 'F4j as urgentes ficam em parametros.p_restricoes, para a revalidação ao aplicar',
      (select pr.parametros -> 'p_restricoes' -> 'urgentes' = jsonb_build_array(v_a) from public.agenda_propostas pr where pr.id = (r ->> 'proposta_id')::uuid), r::text);
    v_res := pg_temp.ok(v_res, 'F4k a proposta persistida passa em agenda_validar: a revalidação vê a urgente', public.agenda_validar((r ->> 'proposta_id')::uuid, null, c_hoje, c_ag) = '[]'::jsonb, public.agenda_validar((r ->> 'proposta_id')::uuid, null, c_hoje, c_ag)::text);
    -- urgente que coube dentro do teto: sem a frase da folga (efeito que não aconteceu não se diz)
    insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, criado_por) values (public._agenda_dono(null), daterange(date '2027-02-12', date '2027-02-12', '[]'), 'manha', 'disponivel', 'dono', 'teste 7e P4', pg_temp.adm());
    perform pg_temp.publica(v_oc, public._agenda_dono(null), 1, date '2027-02-12');  -- o dono no turno não conta na soma da equipe
    perform pg_temp.modos('sombra', 'ligado', false);
    r := pg_temp.sem(c_fev, c_fev + 4, c_hoje, c_ag);
    v_i := pg_temp.criar(r, v_a);
    v_res := pg_temp.ok(v_res, 'F4l urgente que coube no teto (8 com sombra da folga, o dono fora da soma): urgente sem a frase da folga (ela não usou a folga)',
      (v_i ->> 'urgente')::boolean and not exists (select 1 from jsonb_array_elements_text(v_i -> 'motivos') m where m like 'urgente:%' or m like '%folga da semana%'), coalesce((v_i -> 'motivos')::text, ''));
    -- em sombra e com o freio: sem chave
    perform pg_temp.modos('ligado', 'sombra', false);
    r := pg_temp.sem(c_fev, c_fev + 4, c_hoje, c_ag);
    v_i := pg_temp.criar(r, v_a);
    v_t := r::text;
    v_res := pg_temp.ok(v_res, 'F4m modo_urgencia em sombra (e sem urgente_teste): sem as chaves, sem frase, sem teto100 (não cabe)',
      v_i is null and v_t !~ 'urgente' and v_t !~ 'usei a folga', coalesce(left(v_i::text, 700), substring(v_t from '.{120}urgente.{80}'), left(v_t, 300)));
    perform pg_temp.modos('ligado', 'ligado', true);
    r := pg_temp.sem(c_fev, c_fev + 4, c_hoje, c_ag);
    v_t := r::text;
    v_res := pg_temp.ok(v_res, 'F4n ligado com o freio = sombra (R7.6): sem as chaves', v_t !~ 'urgente' and v_t !~ 'usei a folga', left(v_t, 600));
    perform pg_temp.modos('ligado', 'ligado', false);
    r := pg_temp.pr(array[v_e], c_fev, c_fev + 4, c_hoje, c_ag);
    v_i := (select i from jsonb_array_elements(r -> 'itens') i where i ->> 'os' = v_e::text limit 1);
    v_res := pg_temp.ok(v_res, 'F4o a OS comum continua sem chave em ligado', v_i is not null and not v_i ? 'urgente' and (v_i -> 'motivos')::text !~ 'urgente', left(coalesce(v_i::text, r::text), 500));
    -- urgente de fora não vale: só o motor faz a lista
    v := public.agenda_propor('os', c_fev, c_fev + 4, array[v_e], jsonb_build_object('urgentes', jsonb_build_array(v_e)), true, 'motor', null, c_hoje, c_ag);
    v_res := pg_temp.ok(v_res, 'F4p a lista de urgentes que vem de fora sai (só o motor faz: ela levaria o validador a 100%)',
      (select not (pr.parametros -> 'p_restricoes') ? 'urgentes' from public.agenda_propostas pr where pr.id = (v ->> 'proposta_id')::uuid), coalesce(v ->> 'proposta_id', v::text));

    -- uma OS urgente que só pode ser reserva (classe 3: o material não foi conferido): o item da reserva não diz urgente nem usa a folga
    v_cond := pg_temp.pronta(420, 0.5, 1::smallint);
    update public.os_planejamento set material_conferido_em = null where service_order_id = v_cond;
    perform pg_temp.modos('ligado', 'ligado', false);
    r := pg_temp.sem(c_fev, c_fev + 4, c_hoje, c_ag);
    v_i := pg_temp.reserva(r, v_cond);
    v_res := pg_temp.ok(v_res, 'F4x a reserva de OS urgente (classe 3) não diz urgente nem que usou a folga',
      coalesce(not v_i ? 'urgente' and (v_i -> 'motivos')::text !~ 'urgente', false), coalesce(v_i::text, 'sem reserva: ' || coalesce((pg_temp.criar(r, v_cond))::text, 'nada') || ' fora: ' || coalesce((select e::text from jsonb_array_elements(r -> 'fora') e where e ->> 'os' = v_cond::text), '-')));
    perform pg_temp.fora(array[v_cond]);
    -- a regra 6 por pessoa (sem o teto da equipe) e o caso da normal antes da urgente na fila: o motor não lança (R7.12-1)
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_em = c_ag, cancelada_motivo = 'replanejado' where service_order_id = v_oc;
    perform pg_temp.fora(array[v_a, v_oc]);
    v_n := pg_temp.pronta(411, 4);                                  -- 8 meios-dias (a normal, antes na fila pelo número)
    v_u := pg_temp.pronta(412, 1, null, null, 'urgent');            -- 2 meios-dias (a urgente, depois)
    perform pg_temp.modos('ligado', 'ligado', false, false);
    r := pg_temp.pr(array[v_n, v_u], c_fev, c_fev + 4, c_hoje, c_ag);
    v_res := pg_temp.ok(v_res, 'F4q sem o teto da equipe: a normal (8 = 80%) e a urgente (2, indo a 100%) na mesma semana do Alex: o motor monta e o validador aceita (agenda_propor não lança)',
      (pg_temp.criar(r, v_n) -> 'alocacoes' -> 0 ->> 'dia')::date between c_fev and c_fev + 4 and (pg_temp.criar(r, v_u) -> 'alocacoes' -> 0 ->> 'dia')::date between c_fev and c_fev + 4, left((r -> 'itens')::text, 800));
    v_t := (pg_temp.criar(r, v_u) -> 'motivos')::text;
    v_res := pg_temp.ok(v_res, 'F4r por pessoa, passou de 8 (a teto80 dele): a urgente diz o motivo', pg_temp.criar(r, v_u) -> 'motivos' @> '["urgente: marcada como urgente; usei a folga da semana"]'::jsonb, v_t);
    v := public._agenda_validar_itens(r -> 'itens', jsonb_build_object('p_restricoes', '{}'::jsonb), c_hoje, c_ag, false);
    v_res := pg_temp.ok(v_res, 'F4s sem a lista, a mesma proposta não passa (o controle: a soma por pessoa recusa)', pg_temp.regra(v, 6) <> '-', pg_temp.regra(v, 6));
    v := public._agenda_validar_itens(r -> 'itens', jsonb_build_object('p_restricoes', jsonb_build_object('urgentes', jsonb_build_array(v_u))), c_hoje, c_ag, false);
    v_res := pg_temp.ok(v_res, 'F4t com a urgente na lista, passa (o teto da semana inteira da pessoa)', pg_temp.regra(v, 6) = '-', pg_temp.regra(v, 6));
    perform pg_temp.publica(pg_temp.pronta(414, 3.5), v_alex, 7, c_fev);
    v := public._agenda_validar_itens(jsonb_build_array(pg_temp.item(v_n, 'OS-7EF411', v_alex, 'Alex', c_fev + 4, 'manha'), pg_temp.item(v_n, 'OS-7EF411', v_alex, 'Alex', c_fev + 4, 'tarde'), pg_temp.item(v_u, 'OS-7EF412', v_alex, 'Alex', c_fev + 3, 'tarde', 'reserva', '{"reserva_de": "teto"}'::jsonb)),
                                      jsonb_build_object('p_restricoes', jsonb_build_object('urgentes', jsonb_build_array(v_u))), c_hoje, c_ag, false);
    v_res := pg_temp.ok(v_res, 'F4w a reserva da urgente não abre a semana da pessoa para o compromisso normal (9 de 8: recusa pela pessoa)', pg_temp.regra(v, 6) like '%Alex passaria do limite%', pg_temp.regra(v, 6));
    -- a urgente não vira pedido do dono fora da regra 6 (a regra 7, o congelado)
    v := public._agenda_validar_itens(jsonb_build_array(pg_temp.item(v_u, 'OS-7EF412', v_alex, 'Alex', c_hoje, 'tarde')),
                                      jsonb_build_object('p_restricoes', jsonb_build_object('urgentes', jsonb_build_array(v_u))), c_hoje, c_ag, false);
    v_res := pg_temp.ok(v_res, 'F4u a urgente não vale no congelado: a regra 7 segue recusando (v_n volta ao que era)', pg_temp.regra(v, 7) <> '-', pg_temp.regra(v, 7));
    -- com o teto da equipe: a urgente sai da soma; a normal (só) continua contando
    perform pg_temp.modos('ligado', 'ligado', false, true);
    perform pg_temp.so_alex(date '2027-02-15');
    v_oc := pg_temp.pronta(413, 3.5);
    perform pg_temp.publica(v_oc, v_alex, 7, date '2027-02-15');
    v := public._agenda_validar_itens(jsonb_build_array(pg_temp.item(v_u, 'OS-7EF412', v_alex, 'Alex', date '2027-02-19', 'manha'), pg_temp.item(v_n, 'OS-7EF411', v_alex, 'Alex', date '2027-02-19', 'tarde')),
                                      jsonb_build_object('p_restricoes', jsonb_build_object('urgentes', jsonb_build_array(v_u))), c_hoje, c_ag, false);
    v_res := pg_temp.ok(v_res, 'F4v na soma da equipe: a urgente não conta, a normal da semana conta: 8 para 7 (só a normal)', pg_temp.regra(v, 6) = 'A equipe passaria do limite da semana de 15/02: 8 meios-dias de serviço para 7.', pg_temp.regra(v, 6));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then
    v_res := pg_temp.ok(v_res, 'F4 sem exceção', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$f4$;

-- ── F5g. Os ganchos do puxar (quem chama é o P4b) ───────────────────────────────────────────────
do $f5$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-02-10';                       -- qua
  c_ag   constant timestamptz := timestamptz '2027-02-10 17:31-03';
  c_d    constant date := date '2027-02-11';                       -- qui: amanhã, dentro do congelado
  v_a    uuid; v_b uuid; v_c uuid; v_a2 uuid;
  v_alex uuid;
  v_rob  uuid;
  r      jsonb;
  v_i    jsonb;
  v_p    jsonb;
  v      jsonb;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'F5g o puxar', true, 'PULADO: sem a fixture (rode pela bancada)'));
    return;
  end if;
  begin
    v_alex := pg_temp.pessoa('Alex');
    v_rob := pg_temp.pessoa('Roberto');
    v_a := pg_temp.pronta(500, 0.5);
    v_p := jsonb_build_object('puxar', jsonb_build_object('dia', c_d, 'pessoas', jsonb_build_array(v_rob), 'os', v_a), 'acima_da_carga', true);
    perform pg_temp.modos('sombra', 'sombra', false);
    r := pg_temp.pr(array[v_a], c_d, null, c_hoje, c_ag);
    v_i := pg_temp.criar(r, v_a);
    v_res := pg_temp.ok(v_res, 'F5g1 sem puxar, amanhã é congelado: a OS não entra em 11/02', coalesce((v_i -> 'alocacoes' -> 0 ->> 'dia')::date > c_d, true), coalesce(v_i::text, ''));
    r := pg_temp.pr(array[v_a], c_d, null, c_hoje, c_ag, v_p);
    v_i := pg_temp.criar(r, v_a);
    v_res := pg_temp.ok(v_res, 'F5g2 com puxar: compromisso em 11/02, só com o Roberto, que o puxar diz (o motor preferiria o Alex: as células das outras pessoas no dia ficam sem capacidade)',
      (v_i -> 'alocacoes' -> 0 ->> 'dia')::date = c_d and (select bool_and((a ->> 'payee_id')::uuid = v_rob) from jsonb_array_elements(v_i -> 'alocacoes') a), coalesce(v_i::text, (r -> 'itens')::text));
    v_res := pg_temp.ok(v_res, 'F5g3 o motivo da puxada, sem dizer urgente', v_i -> 'motivos' @> '["puxada para a folga que sobrou de amanhã"]'::jsonb and (v_i::text) !~ 'urgente', (v_i -> 'motivos')::text);
    -- o validador: a exceção da regra 7, estreita
    v := public._agenda_validar_itens(jsonb_build_array(pg_temp.item(v_a, 'OS-7EF500', v_rob, 'Roberto', c_d)), jsonb_build_object('p_restricoes', v_p), c_hoje, c_ag, false);
    v_res := pg_temp.ok(v_res, 'F5g4 a regra 7 aceita o item da OS puxada, no dia e de quem o puxar diz', pg_temp.regra(v, 7) = '-', pg_temp.regra(v, 7));
    v := public._agenda_validar_itens(jsonb_build_array(pg_temp.item(v_a, 'OS-7EF500', v_rob, 'Roberto', c_d)), jsonb_build_object('p_restricoes', '{"acima_da_carga": true}'::jsonb), c_hoje, c_ag, false);
    v_res := pg_temp.ok(v_res, 'F5g5 sem puxar, a regra 7 recusa o mesmo item', pg_temp.regra(v, 7) <> '-', pg_temp.regra(v, 7));
    v := public._agenda_validar_itens(jsonb_build_array(pg_temp.item(v_a, 'OS-7EF500', v_alex, 'Alex', c_d)), jsonb_build_object('p_restricoes', v_p), c_hoje, c_ag, false);
    v_res := pg_temp.ok(v_res, 'F5g6 outra pessoa: recusa', pg_temp.regra(v, 7) <> '-', pg_temp.regra(v, 7));
    v := public._agenda_validar_itens(jsonb_build_array(pg_temp.item(v_a, 'OS-7EF500', v_rob, 'Roberto', c_hoje)), jsonb_build_object('p_restricoes', v_p), c_hoje, c_ag, false);
    v_res := pg_temp.ok(v_res, 'F5g7 outro dia (hoje, já começou): recusa', pg_temp.regra(v, 7) <> '-', pg_temp.regra(v, 7));
    v := public._agenda_validar_itens(jsonb_build_array(pg_temp.item(v_a, 'OS-7EF500', v_rob, 'Roberto', c_d)), jsonb_build_object('p_restricoes', jsonb_build_object('puxar', jsonb_build_object('dia', c_d + 1, 'pessoas', jsonb_build_array(v_rob), 'os', v_a))), c_hoje, c_ag, false);
    v_res := pg_temp.ok(v_res, 'F5g7b o puxar é para outro dia (sex 12/02): o item de amanhã continua recusado', pg_temp.regra(v, 7) <> '-', pg_temp.regra(v, 7));
    v := public._agenda_validar_itens(jsonb_build_array(pg_temp.item(pg_temp.os('E1'), 'OS-7E1', v_rob, 'Roberto', c_d)), jsonb_build_object('p_restricoes', v_p), c_hoje, c_ag, false);
    v_res := pg_temp.ok(v_res, 'F5g8 outra OS: recusa', pg_temp.regra(v, 7) <> '-', pg_temp.regra(v, 7));
    v := public._agenda_validar_itens(jsonb_build_array(pg_temp.item(v_a, 'OS-7EF500', v_rob, 'Roberto', c_d, 'manha', 'reserva')), jsonb_build_object('p_restricoes', v_p), c_hoje, c_ag, false);
    v_res := pg_temp.ok(v_res, 'F5g9 reserva da OS puxada: recusa (só o compromisso criado)', pg_temp.regra(v, 7) <> '-', pg_temp.regra(v, 7));
    -- o EST: a máscara do local não pode ser pisada (R7.7-3)
    create or replace function public._agenda_local_mascara(p_os uuid, p_d_ini date, p_d_fim date, p_hoje date, p_local jsonb default null) returns jsonb language sql stable as $x$
      select jsonb_build_object('dias', '[]'::jsonb, 'meios', '[]'::jsonb, 'motivos', '[]'::jsonb, 'notas', '[]'::jsonb, 'sai', 0, 'ent', date '2027-02-12' - p_d_ini + 1)
    $x$;
    update public.agenda_config set modo_patio = 'ligado' where id;
    r := pg_temp.pr(array[v_a], c_d, null, c_hoje, c_ag, v_p);
    v_i := pg_temp.criar(r, v_a);
    v_res := pg_temp.ok(v_res, 'F5g10 com a máscara do local dizendo que o bem só entra em 12/02: não cai em 11/02 (greatest com o EST; R7.7-3)',
      coalesce((v_i -> 'alocacoes' -> 0 ->> 'dia')::date > c_d, true), coalesce(v_i::text, ''));
    execute pg_temp.inteira(current_setting('agenda_teste.mig_correcao_fase7d'), '_agenda_local_mascara');
    update public.agenda_config set modo_patio = 'desligado' where id;
    -- "só depois de" e o que ela já tem marcado também passam por cima do dia
    r := pg_temp.pr(array[v_a], c_d, null, c_hoje, c_ag, v_p || jsonb_build_object('so_depois_de', jsonb_build_array(jsonb_build_object('os', v_a, 'dia', '2027-02-12'))));
    v_i := pg_temp.criar(r, v_a);
    v_res := pg_temp.ok(v_res, 'F5g11 só depois de 12/02: não cai em 11/02', coalesce((v_i -> 'alocacoes' -> 0 ->> 'dia')::date > c_d, true), coalesce(v_i::text, ''));
    -- uma OS de 1 dia que já tem meio-dia marcado em 12/02: o que falta cai depois do que ela já tem, e não em 11/02
    v_b := pg_temp.pronta(501, 1);
    perform pg_temp.publica(v_b, v_alex, 1, date '2027-02-12');
    r := pg_temp.pr(array[v_b], c_d, null, c_hoje, c_ag, jsonb_build_object('puxar', jsonb_build_object('dia', c_d, 'pessoas', jsonb_build_array(v_rob), 'os', v_b), 'acima_da_carga', true));
    v_res := pg_temp.ok(v_res, 'F5g12 já marcada em 12/02: o EST fica no que ela tem (não cai em 11/02)',
      coalesce((pg_temp.criar(r, v_b) -> 'alocacoes' -> 0 ->> 'dia')::date >= date '2027-02-12', false), left((r -> 'itens')::text, 400));
    -- a 2ª OS na mesma proposta não é puxada
    v_c := pg_temp.pronta(502, 0.5);
    r := pg_temp.pr(array[v_a, v_c], c_d, null, c_hoje, c_ag, v_p);
    v_i := pg_temp.criar(r, v_c);
    v_res := pg_temp.ok(v_res, 'F5g13 a outra OS da proposta não é puxada: não entra em 11/02, e fora do dia da puxada a grade é a de sempre (as outras pessoas continuam livres)',
      (v_i -> 'alocacoes' -> 0 ->> 'dia')::date > c_d and (v_i -> 'alocacoes' -> 0 ->> 'payee_id')::uuid <> v_rob, coalesce(v_i::text, ''));
    -- sem acima_da_carga, a OS puxada vai a 100% da semana da pessoa (teto100); as outras células dela, no resto da semana, ficam como estão
    perform pg_temp.fora(array[v_a, v_b, v_c]);
    perform pg_temp.publica(pg_temp.pronta(503, 4), v_rob, 6, date '2027-02-08');
    perform pg_temp.publica(pg_temp.pronta(504, 1), v_rob, 2, date '2027-02-12');
    v_a2 := pg_temp.pronta(505, 0.5);
    perform pg_temp.modos('sombra', 'sombra', false, false);
    r := pg_temp.pr(array[v_a2], c_d, null, c_hoje, c_ag, jsonb_build_object('puxar', jsonb_build_object('dia', c_d, 'pessoas', jsonb_build_array(v_rob), 'os', v_a2)));
    v_i := pg_temp.criar(r, v_a2);
    v_res := pg_temp.ok(v_res, 'F5g14 sem acima_da_carga, a OS puxada usa os 100% da pessoa (8 já marcados de 10 + 1 no dia da puxada): teto100', (v_i -> 'alocacoes' -> 0 ->> 'dia')::date = c_d and (v_i -> 'alocacoes' -> 0 ->> 'payee_id')::uuid = v_rob, coalesce(v_i::text, left((r -> 'itens')::text, 400)));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then
    v_res := pg_temp.ok(v_res, 'F5g sem exceção', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$f5$;

-- ── F6. As cópias ───────────────────────────────────────────────────────────────────────────────
do $f6$
declare
  v_res jsonb := '[]'::jsonb;
  v_m text := coalesce(current_setting('agenda_teste.mig_folga_fase7e', true), '');
  v_7d text := coalesce(current_setting('agenda_teste.mig_motor_fase7d', true), '');
  v_7dc text := coalesce(current_setting('agenda_teste.mig_correcao_fase7d', true), '');
  v_7e2 text := coalesce(current_setting('agenda_teste.mig_medicao_fase7e', true), '');
  n text;
begin
  if v_m = '' then
    perform pg_temp.gravar(pg_temp.ok('[]', 'F6 as cópias', true, 'PULADO: sem a migration como texto (rode pela bancada)'));
    return;
  end if;
  foreach n in array array['_agenda_contexto', '_agenda_validar_itens'] loop
    v_res := pg_temp.ok(v_res, 'F6a ' || n || ': tirados os blocos do P4, o corpo é o da 7d P4 (20261107100300)', pg_temp.sem_p4(pg_temp.inteira(v_m, n)) = pg_temp.inteira(v_7d, n), null);
    v_res := pg_temp.ok(v_res, 'F6b ' || n || ': tem bloco do P4', pg_temp.inteira(v_m, n) ~ '\(7e P4', null);
  end loop;
  v_res := pg_temp.ok(v_res, 'F6c agenda_propor: tirados os blocos do P4, o corpo é o da correção da 7d (20261107100800)', pg_temp.sem_p4(pg_temp.inteira(v_m, 'agenda_propor')) = pg_temp.inteira(v_7dc, 'agenda_propor'), null);
  foreach n in array array['_agenda_aprendizado_gravar', '_agenda_aprendizado_texto'] loop
    v_res := pg_temp.ok(v_res, 'F6f ' || n || ': tirados os blocos do P4, o corpo é o do P2 (20261111100100), e tem bloco do P4', v_7e2 <> '' and pg_temp.sem_p4(pg_temp.inteira(v_m, n)) = pg_temp.inteira(v_7e2, n) and pg_temp.inteira(v_m, n) ~ '\(7e P4', null);
  end loop;
  v_res := pg_temp.ok(v_res, 'F6d a migration não recria o que R7.1 e R7.13 tiram daqui (_agenda_gestor_puxar é do P4b; _agenda_aprendido, _agenda_encaixar, _agenda_tentar_bloco, agenda_vigiar, agenda_cliente_vigiar, agenda_capacidade_semanal)',
    v_m !~ 'create or replace function public\.(_agenda_gestor_puxar|_agenda_aprendido|_agenda_encaixar|_agenda_tentar_bloco|agenda_vigiar|agenda_cliente_vigiar|agenda_gestor_rodar|agenda_capacidade_semanal)\(', null);
  v_res := pg_temp.ok(v_res, 'F6e sem urgente_teste (R7.13)', v_m !~ 'urgente_teste', null);
  perform pg_temp.gravar(v_res);
end
$f6$;

-- ── M1. Sombra = antes, em md5 (R7.12-10) ───────────────────────────────────────────────────────
-- Põe no lugar as 3 funções de antes (o corpo das origens) e as novas (da migration), sem a transação sair do lugar
create function pg_temp.motor_de(p_qual text) returns void language plpgsql as $f$
begin
  if p_qual = 'antes' then
    execute pg_temp.inteira(current_setting('agenda_teste.mig_motor_fase7d'), '_agenda_contexto');
    execute pg_temp.inteira(current_setting('agenda_teste.mig_motor_fase7d'), '_agenda_validar_itens');
    execute pg_temp.inteira(current_setting('agenda_teste.mig_correcao_fase7d'), 'agenda_propor');
  else
    execute pg_temp.inteira(current_setting('agenda_teste.mig_folga_fase7e'), '_agenda_contexto');
    execute pg_temp.inteira(current_setting('agenda_teste.mig_folga_fase7e'), '_agenda_validar_itens');
    execute pg_temp.inteira(current_setting('agenda_teste.mig_folga_fase7e'), 'agenda_propor');
  end if;
end $f$;
create function pg_temp.foto(p_os uuid[], p_it jsonb) returns text language plpgsql as $f$
declare
  c_hoje constant date := date '2027-02-01';
  c_ag constant timestamptz := timestamptz '2027-02-01 10:00-03';
begin
  return md5(concat_ws('|',
    public._agenda_contexto(date '2027-02-01', date '2027-03-14', c_hoje)::text,
    public.agenda_propor('os', date '2027-02-08', date '2027-03-05', p_os, '{}'::jsonb, false, 'motor', null, c_hoje, c_ag)::text,
    public.agenda_propor('semana', null, null, null, '{}'::jsonb, false, 'motor', null, c_hoje, c_ag)::text,
    public._agenda_validar_itens(p_it, '{}'::jsonb, c_hoje, c_ag, false)::text));
end $f$;
do $m1$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-02-01';
  c_ag constant timestamptz := timestamptz '2027-02-01 10:00-03';
  c_fev constant date := date '2027-02-08';
  v_a uuid; v_b uuid; v_alex uuid; v_oc uuid;
  v_oss uuid[];
  v_it jsonb;
  m text[];
  a text; b text;
  v_c jsonb;
begin
  if not pg_temp.fx() or coalesce(current_setting('agenda_teste.mig_folga_fase7e', true), '') = '' then
    perform pg_temp.gravar(pg_temp.ok('[]', 'M1 sombra', true, 'PULADO: sem a fixture (rode pela bancada)'));
    return;
  end if;
  begin
    v_alex := pg_temp.pessoa('Alex');
    perform pg_temp.so_alex(c_fev);
    v_oc := pg_temp.pronta(600, 3.5);
    perform pg_temp.publica(v_oc, v_alex, 7, c_fev);
    v_a := pg_temp.pronta(601, 0.5, 1::smallint);
    v_b := pg_temp.pronta(602, 2, null, date '2027-02-05');
    v_oss := array[v_a, v_b, pg_temp.pronta(603, 1.5, null, null, 'urgent')];
    v_it := jsonb_build_array(pg_temp.item(v_a, 'OS-7EF601', v_alex, 'Alex', c_fev + 4, 'manha'));
    -- uma folga em uso (para a sombra ter o que ignorar) e a temporada de fevereiro
    perform pg_temp.folga(0.11);
    foreach m slice 1 in array array[['desligado', 'desligado', 'false'], ['sombra', 'sombra', 'false'], ['ligado', 'ligado', 'true']] loop
      perform pg_temp.modos(m[1], m[2], m[3]::boolean);
      perform pg_temp.motor_de('antes');
      a := pg_temp.foto(v_oss, v_it);
      perform pg_temp.motor_de('novo');
      b := pg_temp.foto(v_oss, v_it);
      v_res := pg_temp.ok(v_res, format('M1a folga %s, urgência %s, freio %s: contexto, motor (OS e semana) e validador iguais às definições de antes, em md5', m[1], m[2], m[3]), a = b, a || ' / ' || b);
    end loop;
    -- o controle: em ligado sem o freio, diferem
    perform pg_temp.modos('ligado', 'ligado', false);
    perform pg_temp.motor_de('antes');
    a := pg_temp.foto(v_oss, v_it);
    perform pg_temp.motor_de('novo');
    b := pg_temp.foto(v_oss, v_it);
    v_res := pg_temp.ok(v_res, 'M1b o controle morde: ligado e sem o freio, a foto difere', a <> b, a || ' / ' || b);
    -- as chaves novas não existem em sombra
    perform pg_temp.modos('sombra', 'sombra', false);
    v_c := public._agenda_contexto(date '2027-02-01', date '2027-03-14', c_hoje);
    v_res := pg_temp.ok(v_res, 'M1c em sombra, nem carga_semana no contexto, nem urgentes em p_restricoes da proposta', not v_c ? 'carga_semana'
      and (public.agenda_propor('os', c_fev, c_fev + 4, v_oss, '{}'::jsonb, false, 'motor', null, c_hoje, c_ag))::text !~ '(urgente|carga_semana|puxada)', null);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then
    v_res := pg_temp.ok(v_res, 'M1 sem exceção', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$m1$;

-- ── M1c. Sem relógio (R7.8): com as funções da margem lançando, os caminhos em sombra não as chamam ─
do $m1c$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-02-01';
  c_ag constant timestamptz := timestamptz '2027-02-01 10:00-03';
  v_a uuid;
  r jsonb;
  v_err text;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'M1c', true, 'PULADO: sem a fixture (rode pela bancada)'));
    return;
  end if;
  begin
    v_a := pg_temp.pronta(700, 0.5, 1::smallint);
    perform pg_temp.modos('sombra', 'sombra', false);
    create or replace function public._agenda_margem_modo(p_item text) returns text language plpgsql stable as $x$ begin raise exception 'chamou _agenda_margem_modo'; end $x$;
    create or replace function public._agenda_margem_em_uso(p_item text, p_chave text) returns numeric language plpgsql stable as $x$ begin raise exception 'chamou _agenda_margem_em_uso'; end $x$;
    create or replace function public._agenda_os_urgente(p_os uuid, p_hoje date) returns jsonb language plpgsql stable as $x$ begin raise exception 'chamou _agenda_os_urgente'; end $x$;
    create or replace function public._agenda_carga_da_semana(p_seg date, p_teste boolean default false) returns jsonb language plpgsql stable as $x$ begin raise exception 'chamou _agenda_carga_da_semana'; end $x$;
    create or replace function public._agenda_vies_da_os(p_os uuid) returns jsonb language plpgsql stable as $x$ begin raise exception 'chamou _agenda_vies_da_os'; end $x$;
    create or replace function public._agenda_tempo_interno_compra(p_os uuid) returns int language plpgsql stable as $x$ begin raise exception 'chamou _agenda_tempo_interno_compra'; end $x$;
    v_err := null;
    begin
      r := pg_temp.pr(array[v_a], date '2027-02-08', date '2027-02-12', c_hoje, c_ag);
      perform public._agenda_validar_itens(r -> 'itens', '{}'::jsonb, c_hoje, c_ag, false);
    exception when others then v_err := sqlerrm; end;
    v_res := pg_temp.ok(v_res, 'M1c1 agenda_propor e o validador em sombra não chamam nenhuma das 5', v_err is null, v_err);
    v_err := null;
    begin perform public.agenda_vigiar(c_hoje, c_ag); exception when others then v_err := sqlerrm; end;
    v_res := pg_temp.ok(v_res, 'M1c2 agenda_vigiar em sombra não chama', v_err is null or v_err !~ 'chamou', v_err);
    v_err := null;
    begin perform public.agenda_cliente_vigiar(c_hoje, c_ag); exception when others then v_err := sqlerrm; end;
    v_res := pg_temp.ok(v_res, 'M1c3 agenda_cliente_vigiar em sombra não chama', v_err is null or v_err !~ 'chamou', v_err);
    -- ligado com o freio é sombra também: nenhuma chamada, nem na simulação da regra (agenda.gestor = sombra: a regra vale, o freio segue valendo)
    perform pg_temp.modos('ligado', 'ligado', true);
    perform set_config('agenda.gestor', 'sombra', true);
    v_err := null;
    begin
      r := pg_temp.pr(array[v_a], date '2027-02-08', date '2027-02-12', c_hoje, c_ag);
      perform public._agenda_validar_itens(r -> 'itens', '{}'::jsonb, c_hoje, c_ag, false);
    exception when others then v_err := sqlerrm; end;
    perform set_config('agenda.gestor', '', true);
    v_res := pg_temp.ok(v_res, 'M1c4 ligado com o freio: o portão de custo fecha antes (R7.8), nem _agenda_margem_modo é chamada', v_err is null, v_err);
    -- o controle: ligado sem o freio, chama (a função que lança lança)
    perform pg_temp.modos('ligado', 'ligado', false);
    v_err := null;
    begin r := pg_temp.pr(array[v_a], date '2027-02-08', date '2027-02-12', c_hoje, c_ag); exception when others then v_err := sqlerrm; end;
    v_res := pg_temp.ok(v_res, 'M1c5 o controle: ligado sem o freio, a urgência e a carga são chamadas', v_err ~ 'chamou', coalesce(v_err, 'não lançou'));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then
    v_res := pg_temp.ok(v_res, 'M1c sem exceção', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$m1c$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
