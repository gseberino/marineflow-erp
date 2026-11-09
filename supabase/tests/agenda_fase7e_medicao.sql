-- Prova da medição da Agenda de Produção, Fase 7e (pacote P2; migration 20261111100100; spec-fase7e §5.1, §6.2, §6.3, §8.3 e o bloco R7: R7.3, R7.4, R7.5-1 a 7, 9, 19, 20, 22, 23, R7.6, R7.12, R7.13).
-- bancada: depende de 20261111100100
--
--   M0  as funções: portas, tipo, NOT NULL e DEFAULT de pm_reais e compra_pendente
--   M1  congelar a estimativa do início: bruta ao R$ da config mesmo com o R$ aprendido em uso; check-in OU 1º dia; pessoas; pessoa-meios (o dono que vai junto, R7.4); prazo planejado; uma vez só; atualizado_em (R7.5-22); o erro de uma OS
--   M2  os pessoa-meios reais: dupla, parcial, diária fora do plano por pessoa; M2b o dono que vai junto (12, não 24), com e sem o freio
--   M3  as razões e cada motivo_razao, a porta de R7.4 (M3b Alex sem perfil, M3c sem check-in, M3d o plano falso), M3e a medida por orçamento (os 2 update + o insert, R7.5-1), idempotência, reaberta
--   M4  agenda_medir_compra: as 4 fontes da compra, fonte nula, o miúdo, o retrato, a previsão anterior à compra, o que muda só com diferença; o desvio 10 (a medida que some, o fornecedor nulo sem versão); M4b a forma real
--   M5  o congelar da marcação: congela, a OS sem linha, solta, o vies_dono_fixo fica
--   M6  o gravador por passo: 1,00 → 1,30 → 1,45, nunca pergunta, a trava do *desfaz*, o dono só medida, promessa e folga da compra nunca em uso, o modo cru (R7.6), M6b *desfaz* volta 1,30 e o texto diz 1,30, os textos de §6.2/§6.3
--   M7  _agenda_margem_em_uso: as 9 combinações, o freio, o dono, _agenda_aprendido intacta; _agenda_tempo_interno_compra em OS sem linha
--   M8  as cópias das recriadas contra a origem, _agenda_aprendido sem recriar
--
-- ═══ COMO RODAR ═══  Na bancada: node scripts/bancada-agenda/rodar.mjs. Em produção, só DEPOIS de aplicar a migration, com o OK: npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7e_medicao.sql
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

create function pg_temp.erro(p_sql text) returns text language plpgsql as $f$
begin
  execute p_sql;
  return 'aceitou';
exception when others then
  return 'erro ' || sqlstate || ': ' || sqlerrm;
end $f$;

-- ── M0. As funções (sem fixture) ─────────────────────────────────────────────────────────────────────
create temp table _f7e_p2 (f text primary key, quem text) on commit drop;
insert into _f7e_p2 values
  ('public._agenda_margem_tipo_os(uuid)', 'interna'),
  ('public._agenda_margem_dp_bruto(uuid, jsonb)', 'interna'),
  ('public._agenda_margem_dono_e_pessoa(uuid)', 'interna'),
  ('public._agenda_material_critico(uuid)', 'interna'),
  ('public._agenda_aprender_congelar_marcacao(date)', 'escrita'),
  ('public.agenda_medir_compra(uuid, date)', 'escrita'),
  ('public._agenda_aprender_medir_compras(date)', 'passo'),
  ('public._agenda_margem_em_uso(text, text)', 'leitura'),
  ('public._agenda_vies_da_os(uuid)', 'leitura'),
  ('public._agenda_tempo_interno_compra(uuid)', 'leitura');

insert into _resultado
select 'M0a as 10 funções novas existem; só as 3 leituras têm porta para authenticated e service_role; as outras, sem grant nem service_role; anon nada',
       count(*) = 10
       and bool_and(not has_function_privilege('anon', f::regprocedure, 'execute'))
       and bool_and(has_function_privilege('authenticated', f::regprocedure, 'execute') = (quem = 'leitura'))
       and bool_and(has_function_privilege('service_role', f::regprocedure, 'execute') = (quem = 'leitura')),
       string_agg(f, ', ') filter (where has_function_privilege('anon', f::regprocedure, 'execute')
                                      or has_function_privilege('authenticated', f::regprocedure, 'execute') <> (quem = 'leitura')
                                      or has_function_privilege('service_role', f::regprocedure, 'execute') <> (quem = 'leitura'))
  from _f7e_p2;

insert into _resultado
select 'M0b leituras STABLE invoker; as de escrita VOLATILE definer; search_path fixo em todas',
       bool_and(coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%')
       and bool_and(case k.quem when 'escrita' then p.provolatile = 'v' and p.prosecdef
                                when 'passo' then p.provolatile = 'v' and not p.prosecdef
                                else p.provolatile = 's' and not p.prosecdef end),
       string_agg(p.proname || ':' || p.provolatile::text || ':' || p.prosecdef::text, ', ' order by p.proname)
  from _f7e_p2 k join pg_proc p on p.oid = k.f::regprocedure;

insert into _resultado
select 'M0c as recriadas continuam: o congelar e a medida definer sem grant; o gravador definer sem grant; o valor e o texto leitura',
       bool_and(not has_function_privilege('anon', f, 'execute')
                and not has_function_privilege('authenticated', f, 'execute') and not has_function_privilege('service_role', f, 'execute')),
       null
  from unnest(array['public._agenda_aprender_congelar(date)', 'public.agenda_medir_os(uuid, date)',
                    'public._agenda_aprendizado_gravar(text, text, text, numeric, integer, jsonb, numeric, jsonb, timestamptz)']) f;

insert into _resultado
select 'M0d pm_reais e compra_pendente NOT NULL com DEFAULT 0 e false (R7.5-1)',
       count(*) = 2 and bool_and(a.attnotnull) and bool_and(coalesce(pg_get_expr(d.adbin, d.adrelid), '') = case a.attname when 'pm_reais' then '0' else 'false' end),
       string_agg(a.attname || '=' || coalesce(pg_get_expr(d.adbin, d.adrelid), 'sem'), ', ')
  from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
 where a.attrelid = 'public.agenda_medidas_os'::regclass and a.attname in ('pm_reais', 'compra_pendente');

-- ── A fixture e os ajudantes ─────────────────────────────────────────────────────────────────────────
do $carga$
begin
  if coalesce(current_setting('agenda_teste.fase7e', true), '') <> '' then
    execute current_setting('agenda_teste.fase7e');
  end if;
end
$carga$;

-- Este teste só olha as OS-7E*: as das outras fixtures (centenas, a meio segundo cada, nos 2 laços do congelar e em cada bloco) saem do caminho, como agrupadas. Tudo é desfeito no ROLLBACK.
do $so7e$
begin
  if coalesce(current_setting('agenda_teste.fase7e', true), '') <> '' then
    perform set_config('marineflow.agrupar_orcamentos', 'on', true);
    update public.service_orders set merged_into_id = 'e7e00000-0000-4000-8000-000000000e00'
     where service_order_number not like 'OS-7E%' and service_order_number <> 'OS-E0' and merged_into_id is null;
    perform set_config('marineflow.agrupar_orcamentos', '', true);
  end if;
end
$so7e$;

create function pg_temp.fx() returns boolean language sql stable as $f$ select coalesce(current_setting('agenda_teste.fase7e', true), '') <> '' $f$;
create function pg_temp.os(p_nome text) returns uuid language sql immutable as $f$ select md5('e7e:os:' || p_nome)::uuid $f$;
create function pg_temp.dono() returns uuid language sql stable as $f$ select public._agenda_dono(null) $f$;
create function pg_temp.caio() returns uuid language sql immutable as $f$ select 'e7e00000-0000-4000-8000-00000000aa01'::uuid $f$;
create function pg_temp.zeca() returns uuid language sql immutable as $f$ select 'e7e00000-0000-4000-8000-00000000aa02'::uuid $f$;
-- Uma OS concluída nova (o n distingue; a 1ª linha é mão de obra)
create function pg_temp.nova_os(p_n int, p_ini date, p_fim date, p_mo numeric default 764, p_servico text default 'Reparo na porta da cabine') returns uuid language plpgsql as $f$
declare
  v_os uuid := md5('e7e:os:x' || p_n)::uuid;
begin
  perform set_config('agenda.porta', 'on', true);
  insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type,
                                     created_at, updated_at, converted_to_os_at, check_in_at, check_out_at, delivered_at, grand_total)
  values (v_os, 'OS-7EX' || p_n, 'e7e00000-0000-4000-8000-000000000c02', 'e7e00000-0000-4000-8000-000000000b02', 'completed', 'approved', 'repair',
          ((p_ini - 20) + time '10:00') at time zone 'America/Sao_Paulo', ((p_fim + 1) + time '10:00') at time zone 'America/Sao_Paulo',
          ((p_ini - 14) + time '10:00') at time zone 'America/Sao_Paulo', (p_ini + time '08:00') at time zone 'America/Sao_Paulo',
          (p_fim + time '17:00') at time zone 'America/Sao_Paulo', ((p_fim + 1) + time '10:00') at time zone 'America/Sao_Paulo', p_mo);
  insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at)
  values (v_os, p_servico, 'visit', 1, p_mo, p_mo, ((p_ini - 20) + time '10:00') at time zone 'America/Sao_Paulo');
  perform set_config('agenda.porta', 'off', true);
  return v_os;
end $f$;
create function pg_temp.aloc(p_os uuid, p_payee uuid, p_dia date, p_turno text, p_res text default 'cumprido', p_presenca text default 'turno') returns void language plpgsql as $f$
begin
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, resultado, motivo, resultado_via, resultado_em)
  values (p_os, p_payee, p_dia, p_turno, p_presenca, 'execucao', 'publicada', 'motor', ((p_dia - 1) + time '16:30') at time zone 'America/Sao_Paulo',
          p_res, case when p_res in ('parcial', 'nao_cumprido') then 'estimativa' end, 'dia_feito', case when p_res is not null then (p_dia + time '17:30') at time zone 'America/Sao_Paulo' end);
end $f$;
-- A diária do perfil de Caio num dia, ligada à OS
create function pg_temp.diaria(p_os uuid, p_dia date) returns void language plpgsql as $f$
begin
  insert into public.work_shifts (id, work_profile_id, data, tipo, fracao, valor_diaria, origem, status, registrado_por, aprovado_por, aprovado_em)
  values (md5('e7e:x-ws:' || p_dia)::uuid, 'e7e00000-0000-4000-8000-00000000ab01', p_dia, 'diaria', 1, 200, 'painel', 'aprovado',
          'aa000000-0000-4000-8000-000000000001', 'aa000000-0000-4000-8000-000000000001', (p_dia + time '20:00') at time zone 'America/Sao_Paulo');
  insert into public.work_shift_os (shift_id, service_order_id) values (md5('e7e:x-ws:' || p_dia)::uuid, p_os);
end $f$;

-- ── M1. Congelar a estimativa do início ──────────────────────────────────────────────────────────────
do $m1$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-01-07';
  r1     jsonb;
  r2     jsonb;
  v_os   uuid;
  v_x    uuid;
  v_dp   numeric;
  v_ini  date;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'M1 congelar', true, 'PULADO: sem a fixture (rode pela bancada)'));
    return;
  end if;
  perform set_config('agenda.hoje', c_hoje::text, true);
  begin
    -- o R$ por diária aprendido em uso: a estimativa bruta tem de ficar no R$ da config (764)
    update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = array['fator', 'mo'] where id;
    insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, calculado, em_uso, estado, calculado_em)
    values ('mo', 'todas', 'todas', 764, 3, 8, 1000, 1000, 'em_uso', now());

    r1 := public._agenda_aprender_congelar(c_hoje);
    v_os := pg_temp.os('E1');
    select dp_bruto_no_inicio into v_dp from public.os_planejamento where service_order_id = v_os;
    v_res := pg_temp.ok(v_res, 'M1a a estimativa bruta é MO ÷ o R$ da config (764), mesmo com o R$ aprendido em uso: E1 = 3.820 ÷ 764 = 5', v_dp = 5, format('%s', v_dp));
    select estimativa_no_inicio_em into v_ini from public.os_planejamento where service_order_id = v_os;
    v_res := pg_temp.ok(v_res, 'M1b o dia da estimativa é o do check-in; o prazo planejado e o 1º dia saem das alocações vigentes (E1: 12 meios-dias, 6 dias úteis)',
      v_ini = (select (check_in_at at time zone 'America/Sao_Paulo')::date from public.service_orders where id = v_os)
      and (select inicio_plano_no_inicio = v_ini and prazo_plano_no_inicio = 6 from public.os_planejamento where service_order_id = v_os), format('%s', v_ini));
    v_res := pg_temp.ok(v_res, 'M1c conta as estimativas congeladas no retorno', (r1 ->> 'estimativas_congeladas')::int >= 17, r1::text);
    -- sem check-in, o 1º dia da alocação vigente vale
    v_os := pg_temp.os('V1');
    v_res := pg_temp.ok(v_res, 'M1d sem check-in, o 1º dia de alocação vigente não reserva: V1 congela nesse dia (R7.4)',
      (select estimativa_no_inicio_em = (select min(a.dia) from public.agenda_alocacoes a where a.service_order_id = v_os and a.tipo <> 'reserva')
         from public.os_planejamento where service_order_id = v_os)
      and (select dp_bruto_no_inicio = 1 from public.os_planejamento where service_order_id = v_os), null);
    -- uma vez só: mudar a MO depois não muda o congelado
    update public.service_order_services set line_total = 7640, unit_price_snapshot = 7640 where service_order_id = pg_temp.os('E1');
    r2 := public._agenda_aprender_congelar(c_hoje);
    v_res := pg_temp.ok(v_res, 'M1e uma vez só: na 2ª rodada nada congela e o que mudou no orçamento depois não muda o congelado',
      (r2 ->> 'estimativas_congeladas')::int = 0
      and (select dp_bruto_no_inicio = 5 from public.os_planejamento where service_order_id = pg_temp.os('E1')), r2::text);
    -- o diagnóstico não sai do valor (R7.5-9): dp nulo, mas a data grava
    v_res := pg_temp.ok(v_res, 'M1f o diagnóstico não sai do valor: dp_bruto nulo, a data grava (R7.5-9), e o dono é uma das pessoas: pm_plano = os 10 meios',
      (select dp_bruto_no_inicio is null and estimativa_no_inicio_em is not null and pm_plano_no_inicio = 10
         from public.os_planejamento where service_order_id = pg_temp.os('D1')),
      (select format('dp=%s em=%s pm=%s', dp_bruto_no_inicio, estimativa_no_inicio_em, pm_plano_no_inicio) from public.os_planejamento where service_order_id = pg_temp.os('D1')));
    -- a OS sem base não tem estimativa
    v_res := pg_temp.ok(v_res, 'M1g sem base: dp_bruto nulo, a data grava (uma vez só)',
      (select dp_bruto_no_inicio is null and estimativa_no_inicio_em is not null from public.os_planejamento where service_order_id = pg_temp.os('I3')), null);
    -- R7.5-22: a linha nasce com atualizado_em antigo (a marca d'água do encaixe do gestor não pode ver)
    v_res := pg_temp.ok(v_res, 'M1h a linha nova de os_planejamento nasce com atualizado_em = a criação da OS, não now(): o encaixe do gestor não vê (R7.5-22)',
      (select pl.atualizado_em = so.created_at from public.os_planejamento pl join public.service_orders so on so.id = pl.service_order_id where pl.service_order_id = pg_temp.os('E2')),
      null);
    -- o update na linha que já existe não toca atualizado_em
    v_x := pg_temp.nova_os(1, date '2026-05-04', date '2026-05-04', 764);
    insert into public.os_planejamento (service_order_id, atualizado_em) values (v_x, timestamptz '2026-04-01 10:00-03');
    perform public._agenda_aprender_congelar(c_hoje);
    v_res := pg_temp.ok(v_res, 'M1i na linha que já existe o congelar não mexe em atualizado_em (R7.5-22)',
      (select atualizado_em = timestamptz '2026-04-01 10:00-03' and estimativa_no_inicio_em = date '2026-05-04' from public.os_planejamento where service_order_id = v_x), null);
    -- a OS fora da janela, a agrupada e a que nem começou não congelam
    update public.agenda_config set aprender_janela_dias = 90 where id;
    v_x := pg_temp.nova_os(2, date '2026-05-11', date '2026-05-11', 764);
    r2 := public._agenda_aprender_congelar(c_hoje);
    v_res := pg_temp.ok(v_res, 'M1j fora da janela não congela', (select estimativa_no_inicio_em is null from public.os_planejamento where service_order_id = v_x) is not false, r2::text);
    update public.agenda_config set aprender_janela_dias = 365 where id;
    perform set_config('marineflow.agrupar_orcamentos', 'on', true);
    update public.service_orders set merged_into_id = pg_temp.os('E1') where id = v_x;
    perform set_config('marineflow.agrupar_orcamentos', '', true);
    r2 := public._agenda_aprender_congelar(c_hoje);
    v_res := pg_temp.ok(v_res, 'M1k a OS agrupada não congela', not exists (select 1 from public.os_planejamento where service_order_id = v_x and estimativa_no_inicio_em is not null), null);
    perform set_config('marineflow.agrupar_orcamentos', 'on', true);
    update public.service_orders set merged_into_id = null where id = v_x;
    perform set_config('marineflow.agrupar_orcamentos', '', true);
    -- o erro de uma OS não derruba as outras nem o que o 1º laço gravou: a régua do dono lança para a OS X2 (desfeito no rollback)
    execute format($f$create or replace function public._agenda_margem_dono_e_pessoa(p_os uuid) returns boolean language plpgsql stable set search_path to 'public' as $b$ begin if p_os = %L then raise exception 'plantado'; end if; return false; end $b$$f$, v_x);
    v_x := pg_temp.nova_os(3, date '2026-05-12', date '2026-05-12', 764);
    r2 := public._agenda_aprender_congelar(c_hoje);
    v_res := pg_temp.ok(v_res, 'M1l o erro de uma OS (a MO estoura a coluna) não derruba as outras: vai a app_error_logs e a seguinte congela',
      exists (select 1 from public.os_planejamento where service_order_id = v_x and estimativa_no_inicio_em is not null)
      and exists (select 1 from public.app_error_logs e where e.context = 'agenda' and e.action = 'aprender:congelar'), r2::text);
    -- arredondar a zero não pode cair no CHECK > 0
    v_x := pg_temp.nova_os(4, date '2026-05-13', date '2026-05-13', 1);
    r2 := public._agenda_aprender_congelar(c_hoje);
    v_res := pg_temp.ok(v_res, 'M1m a estimativa que arredonda a 0 fica nula, sem cair no CHECK > 0 (R$ 1)',
      (select dp_bruto_no_inicio is null and estimativa_no_inicio_em is not null from public.os_planejamento where service_order_id = v_x), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$m1$;

-- M1n: o dono que vai junto no pm_plano do início (R7.4): com a equipe dita soma, sem ela não
do $m1n$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-01-07';
  v_a    uuid;
  v_b    uuid;
begin
  if not pg_temp.fx() then return; end if;
  perform set_config('agenda.hoje', c_hoje::text, true);
  begin
    v_a := pg_temp.nova_os(11, date '2026-05-18', date '2026-05-19', 3056);  -- 4 diárias-pessoa, 8 pessoa-meios
    v_b := pg_temp.nova_os(12, date '2026-05-20', date '2026-05-21', 3056);
    -- a sempre: o dono vai junto o tempo todo, sem equipe dita (a regra uma_pessoa não é pela regra: não muda a medida)
    insert into public.os_planejamento (service_order_id, dono_presenca) values (v_a, 'sempre'), (v_b, 'sempre');
    update public.agenda_config set equipe_sugerida = 2 where id;
    insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos) values (v_b, pg_temp.dono(), 'dia'), (v_b, pg_temp.caio(), 'dia');
    -- as duas com 8 meios (4 dias de 2 pessoas): a alocação é o de menos, o molde é o que conta
    perform public._agenda_aprender_congelar(c_hoje);
    v_res := pg_temp.ok(v_res, 'M1n o dono que vai junto não soma no pm_plano do início; com a equipe dita, soma (R7.4)',
      (select pm_plano_no_inicio from public.os_planejamento where service_order_id = v_b) > (select pm_plano_no_inicio from public.os_planejamento where service_order_id = v_a),
      (select format('junto=%s dita=%s', (select pm_plano_no_inicio from public.os_planejamento where service_order_id = v_a), (select pm_plano_no_inicio from public.os_planejamento where service_order_id = v_b))));
    v_res := pg_temp.ok(v_res, 'M1o as pessoas do início: com a equipe dita, o maior desejado + o dono no turno',
      (select pessoas_no_inicio = 2 from public.os_planejamento where service_order_id = v_b), (select format('%s', pessoas_no_inicio) from public.os_planejamento where service_order_id = v_b));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$m1n$;

-- M1p/M1q: a estimativa congelada não muda com o freio (a conferência do P2: com o freio, _agenda_gestor_regra é falsa e congelava a MO com deslocamento e outro molde); agenda.gestor volta ao valor de antes
do $m1p$
declare
  v_res   jsonb := '[]'::jsonb;
  c_hoje  constant date := date '2027-01-07';
  c_regras constant text[] := '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada,sinal_cobrar}';
  v_a     uuid;
  v_b     uuid;
  v_f     boolean;
  v_foto  text;
  v_com   text;
  v_sem   text;
begin
  if not pg_temp.fx() then return; end if;
  perform set_config('agenda.hoje', c_hoje::text, true);
  foreach v_f in array array[true, false] loop
    begin
      update public.agenda_config set modo_marcar_sozinho = 'ligado', marcar_regras = c_regras, equipe_sugerida = 2, equipe_padrao = 1, gestor_so_propor = v_f where id;
      v_a := pg_temp.nova_os(61, date '2026-07-20', date '2026-07-21', 1528, 'Instalação de inversor e baterias');
      insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at)
      values (v_a, 'Deslocamento técnico', 'visit', 1, 382, 382, timestamptz '2026-07-01 10:00-03');
      v_b := pg_temp.nova_os(62, date '2026-07-22', date '2026-07-23', 1528);
      insert into public.os_planejamento (service_order_id, dono_presenca) values (v_b, 'sempre');
      perform public._agenda_aprender_congelar(c_hoje);
      v_foto := (select format('a: dp=%s pm=%s pes=%s | b: dp=%s pm=%s pes=%s', a.dp_bruto_no_inicio, a.pm_plano_no_inicio, a.pessoas_no_inicio, b.dp_bruto_no_inicio, b.pm_plano_no_inicio, b.pessoas_no_inicio)
                   from public.os_planejamento a, public.os_planejamento b where a.service_order_id = v_a and b.service_order_id = v_b);
      if v_f then v_com := v_foto; else v_sem := v_foto; end if;
      if v_f then
        v_res := pg_temp.ok(v_res, 'M1p1 com o freio, a OS com linha de deslocamento congela sem ele: 1.528 ÷ 764 = 2,00 (não 2,50)', (select dp_bruto_no_inicio = 2 from public.os_planejamento where service_order_id = v_a), v_foto);
        v_res := pg_temp.ok(v_res, 'M1p2 com o freio, a OS com o dono no turno congela o molde do gestor (1 pessoa, 4 meios), não o de 2 pessoas', (select pm_plano_no_inicio = 4 from public.os_planejamento where service_order_id = v_b), v_foto);
      end if;
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  v_res := pg_temp.ok(v_res, 'M1p3 com freio = sem freio, nas duas OS', v_com is not null and v_com = v_sem, format('%s // %s', v_com, v_sem));
  perform pg_temp.gravar(v_res);
end
$m1p$;

do $m1q$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-01-07';
  v_x    uuid;
  v_y    uuid;
  v_got  text;
begin
  if not pg_temp.fx() then return; end if;
  perform set_config('agenda.hoje', c_hoje::text, true);
  begin
    -- com valor de antes
    v_x := pg_temp.nova_os(63, date '2026-07-27', date '2026-07-27', 764);
    perform set_config('agenda.gestor', 'xpto', true);
    perform public._agenda_aprender_congelar(c_hoje);
    v_got := current_setting('agenda.gestor', true);
    v_res := pg_temp.ok(v_res, 'M1q1 agenda.gestor volta ao valor que tinha antes do congelar (xpto), não a vazio', v_got = 'xpto' and exists (select 1 from public.os_planejamento where service_order_id = v_x and estimativa_no_inicio_em is not null), v_got);
    -- com a simulação já posta por quem chamou
    v_x := pg_temp.nova_os(64, date '2026-07-28', date '2026-07-28', 764);
    perform set_config('agenda.gestor', 'sombra', true);
    perform public._agenda_aprender_congelar(c_hoje);
    v_got := current_setting('agenda.gestor', true);
    v_res := pg_temp.ok(v_res, 'M1q2 quem já estava em simulação continua nela', v_got = 'sombra', v_got);
    -- vazio
    v_x := pg_temp.nova_os(65, date '2026-07-29', date '2026-07-29', 764);
    perform set_config('agenda.gestor', '', true);
    perform public._agenda_aprender_congelar(c_hoje);
    v_got := current_setting('agenda.gestor', true);
    v_res := pg_temp.ok(v_res, 'M1q3 vazio continua vazio', v_got = '', v_got);
    -- erro de uma OS no meio da simulação: as outras seguem e o valor de antes volta
    alter function public.agenda_meios_da_os(uuid, date) rename to agenda_meios_da_os_de_verdade;
    v_x := pg_temp.nova_os(66, date '2026-07-30', date '2026-07-30', 764);
    v_y := pg_temp.nova_os(67, date '2026-07-31', date '2026-07-31', 764);
    execute format($f$create function public.agenda_meios_da_os(p_so_id uuid, p_hoje date) returns jsonb language plpgsql stable as $b$ begin if p_so_id = %L then raise exception 'plantado no meio da simulação'; end if; return public.agenda_meios_da_os_de_verdade(p_so_id, p_hoje); end $b$$f$, v_x);
    perform set_config('agenda.gestor', 'xpto', true);
    perform public._agenda_aprender_congelar(c_hoje);
    v_got := current_setting('agenda.gestor', true);
    v_res := pg_temp.ok(v_res, 'M1q4 o erro de uma OS no meio da simulação: a OS fica de fora, a seguinte congela e o valor de antes volta',
      v_got = 'xpto' and not exists (select 1 from public.os_planejamento where service_order_id = v_x and estimativa_no_inicio_em is not null)
      and exists (select 1 from public.os_planejamento where service_order_id = v_y and estimativa_no_inicio_em is not null), v_got);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$m1q$;

-- M3j/M3k: a medida da margem também sai sem o freio; as colunas da Fase 6 continuam lendo o freio (v_sug)
do $m3j$
declare
  v_res   jsonb := '[]'::jsonb;
  c_hoje  constant date := date '2027-01-07';
  c_regras constant text[] := '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada,sinal_cobrar}';
  v_a     uuid;
  v_b     uuid;
  v_c     uuid;
  v_f     boolean;
  v_com   text;
  v_sem   text;
  v_foto  text;
  v_got   text;
begin
  if not pg_temp.fx() then return; end if;
  perform set_config('agenda.hoje', c_hoje::text, true);
  foreach v_f in array array[true, false] loop
    begin
      update public.agenda_config set modo_marcar_sozinho = 'ligado', marcar_regras = c_regras, equipe_sugerida = 2, equipe_padrao = 1, gestor_so_propor = v_f where id;
      -- a sem linha de planejamento: o caminho recalculada
      v_a := pg_temp.nova_os(68, date '2026-08-24', date '2026-08-25', 1528, 'Instalação de inversor e baterias');
      insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at)
      values (v_a, 'Deslocamento técnico', 'visit', 1, 382, 382, timestamptz '2026-07-01 10:00-03');
      perform pg_temp.aloc(v_a, pg_temp.zeca(), date '2026-08-24', 'manha');
      perform set_config('agenda.gestor', 'xpto', true);
      perform public.agenda_medir_os(v_a, c_hoje);
      v_got := current_setting('agenda.gestor', true);
      -- os dias ditos, sem o plano congelado: as pessoas vêm da sugestão (5 dias × 2 meios × 1 pessoa, não 2)
      v_b := pg_temp.nova_os(69, date '2026-08-26', date '2026-08-28', 3820, 'Instalação de inversor e baterias');
      insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em) values (v_b, 5, 'dono', timestamptz '2026-08-01 10:00-03');
      perform public.agenda_medir_os(v_b, c_hoje);
      perform set_config('agenda.gestor', '', true);
      -- com a estimativa congelada (dp) mas sem o plano e as pessoas do início: as pessoas ainda vêm da sugestão; com a dupla dita, 2
      v_c := pg_temp.nova_os(70, date '2026-08-31', date '2026-09-02', 3820, 'Instalação de inversor e baterias');
      insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, estimativa_no_inicio_em, dp_bruto_no_inicio, dupla_dita, dupla_em)
      values (v_c, 5, 'dono', timestamptz '2026-08-01 10:00-03', date '2026-08-31', 5, 'todos', timestamptz '2026-08-01 10:00-03');
      perform public.agenda_medir_os(v_c, c_hoje);
      v_foto := (select format('a: pm_est=%s origem=%s | b: pm_dono=%s', a.pm_estimados, a.estimativa_origem, b.pm_plano_dono) from public.agenda_medidas_os a, public.agenda_medidas_os b where a.service_order_id = v_a and b.service_order_id = v_b);
      if v_f then
        v_com := v_foto;
        v_res := pg_temp.ok(v_res, 'M3j o caminho recalculada, com o freio: sem o deslocamento (pm 4,0), e agenda.gestor volta a xpto', (select pm_estimados = 4 and estimativa_origem = 'recalculada' from public.agenda_medidas_os where service_order_id = v_a) and v_got = 'xpto', v_foto || ' gestor=' || coalesce(v_got, 'nulo'));
        v_res := pg_temp.ok(v_res, 'M3j2 v_sug não mudou: a coluna mo da Fase 6 segue com o freio, com o deslocamento', (select mo = 1910 from public.agenda_medidas_os where service_order_id = v_a), (select mo::text from public.agenda_medidas_os where service_order_id = v_a));
        v_res := pg_temp.ok(v_res, 'M3k as pessoas do plano do dono, com o freio: as do gestor (5 dias, 10 meios × 1 = 10)', (select pm_plano_dono = 10 from public.agenda_medidas_os where service_order_id = v_b), v_foto);
        v_res := pg_temp.ok(v_res, 'M3k3 dp congelado, sem plano nem pessoas do início: as pessoas ainda vêm da sugestão (a dupla dita: 10 × 2 = 20)', (select pm_plano_dono = 20 from public.agenda_medidas_os where service_order_id = v_c), (select coalesce(pm_plano_dono::text, 'nulo') from public.agenda_medidas_os where service_order_id = v_c));
      else
        v_sem := v_foto;
        v_res := pg_temp.ok(v_res, 'M3j3 sem o freio a coluna mo já é sem o deslocamento (é o freio que muda v_sug, e só nas colunas da Fase 6)', (select mo = 1528 from public.agenda_medidas_os where service_order_id = v_a), (select mo::text from public.agenda_medidas_os where service_order_id = v_a));
      end if;
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  v_res := pg_temp.ok(v_res, 'M3k2 a medida da margem: com freio = sem freio', v_com is not null and v_com = v_sem, format('%s // %s', v_com, v_sem));
  perform pg_temp.gravar(v_res);
end
$m3j$;

-- ── M2. Os pessoa-meios reais ────────────────────────────────────────────────────────────────────────
do $m2$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-01-07';
  v_x    uuid;
  v_d    date := date '2026-05-25';
  r      record;
  j      int;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'M2 pessoa-meios', true, 'PULADO: sem a fixture'));
    return;
  end if;
  perform set_config('agenda.hoje', c_hoje::text, true);
  -- M2a dupla no meio-dia conta 2; parcial meio
  begin
    v_x := pg_temp.nova_os(21, v_d, v_d, 1528);
    perform pg_temp.aloc(v_x, pg_temp.caio(), v_d, 'manha');
    perform pg_temp.aloc(v_x, pg_temp.zeca(), v_d, 'manha');
    perform pg_temp.aloc(v_x, pg_temp.caio(), v_d, 'tarde', 'parcial');
    perform pg_temp.diaria(v_x, v_d);
    perform public.agenda_medir_os(v_x, c_hoje);
    v_res := pg_temp.ok(v_res, 'M2a dupla num meio-dia = 2 pessoa-meios; parcial 0,5: 2,5', (select pm_reais = 2.5 from public.agenda_medidas_os where service_order_id = v_x), (select pm_reais::text from public.agenda_medidas_os where service_order_id = v_x));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- M2b o dono que vai junto não dobra (achado 26 da 7a: 12, não 24)
  begin
    v_x := pg_temp.nova_os(22, date '2026-07-13', date '2026-07-18', 9168);
    insert into public.os_planejamento (service_order_id, dono_presenca) values (v_x, 'sempre');
    for j in 0 .. 5 loop
      perform pg_temp.aloc(v_x, pg_temp.caio(), date '2026-07-13' + j, 'manha');
      perform pg_temp.aloc(v_x, pg_temp.caio(), date '2026-07-13' + j, 'tarde');
      perform pg_temp.aloc(v_x, pg_temp.dono(), date '2026-07-13' + j, 'manha');
      perform pg_temp.aloc(v_x, pg_temp.dono(), date '2026-07-13' + j, 'tarde');
    end loop;
    perform pg_temp.diaria(v_x, date '2026-07-13');
    perform public.agenda_medir_os(v_x, c_hoje);
    v_res := pg_temp.ok(v_res, 'M2b o dono que vai junto não conta: 12 pessoa-meios, não 24 (a régua do tem, R7.4)', (select pm_reais = 12 from public.agenda_medidas_os where service_order_id = v_x), (select pm_reais::text from public.agenda_medidas_os where service_order_id = v_x));
    -- com o freio ligado, a mesma conta (a régua não lê _agenda_gestor_regra)
    update public.agenda_config set gestor_so_propor = true where id;
    perform public.agenda_medir_os(v_x, c_hoje);
    v_res := pg_temp.ok(v_res, 'M2b2 com *gestor, só propor* a conta é a mesma: a medição não lê o freio (R7.6)', (select pm_reais = 12 from public.agenda_medidas_os where service_order_id = v_x), (select pm_reais::text from public.agenda_medidas_os where service_order_id = v_x));
    update public.agenda_config set gestor_so_propor = false where id;
    -- com a equipe dita, ele é uma das pessoas: 24
    insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos) values (v_x, pg_temp.dono(), 'dia');
    perform public.agenda_medir_os(v_x, c_hoje);
    v_res := pg_temp.ok(v_res, 'M2b3 com a equipe dita, o dono conta: 24', (select pm_reais = 24 from public.agenda_medidas_os where service_order_id = v_x), (select pm_reais::text from public.agenda_medidas_os where service_order_id = v_x));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- M2b4 o dono sozinho no meio-dia conta como 1
  begin
    v_x := pg_temp.nova_os(23, date '2026-06-22', date '2026-06-22', 764);
    insert into public.os_planejamento (service_order_id, dono_presenca) values (v_x, 'sempre');
    perform pg_temp.aloc(v_x, pg_temp.dono(), date '2026-06-22', 'manha');
    perform pg_temp.aloc(v_x, pg_temp.caio(), date '2026-06-22', 'tarde');
    perform pg_temp.diaria(v_x, date '2026-06-22');
    perform public.agenda_medir_os(v_x, c_hoje);
    v_res := pg_temp.ok(v_res, 'M2b4 o dono sozinho no meio-dia conta: manhã só ele + tarde o técnico = 2', (select pm_reais = 2 from public.agenda_medidas_os where service_order_id = v_x), (select pm_reais::text from public.agenda_medidas_os where service_order_id = v_x));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- M2b5 o outro que faltou (nao_cumprido) não faz o dono ir junto: ele conta
  begin
    v_x := pg_temp.nova_os(24, date '2026-06-24', date '2026-06-24', 764);
    insert into public.os_planejamento (service_order_id, dono_presenca) values (v_x, 'sempre');
    perform pg_temp.aloc(v_x, pg_temp.dono(), date '2026-06-24', 'manha');
    perform pg_temp.aloc(v_x, pg_temp.caio(), date '2026-06-24', 'manha', 'nao_cumprido');
    perform pg_temp.diaria(v_x, date '2026-06-24');
    perform public.agenda_medir_os(v_x, c_hoje);
    v_res := pg_temp.ok(v_res, 'M2b5 o outro do meio-dia que não cumpriu não faz o dono "ir junto": ele conta 1', (select pm_reais = 1 from public.agenda_medidas_os where service_order_id = v_x), (select pm_reais::text from public.agenda_medidas_os where service_order_id = v_x));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- M2b6/7 comissionamento e diagnóstico: o dono é uma das pessoas e conta junto com o técnico (R7.4)
  begin
    v_x := pg_temp.nova_os(27, date '2026-07-06', date '2026-07-06', 1528);
    perform set_config('agenda.porta', 'on', true);
    update public.service_orders set service_type = 'commissioning' where id = v_x;
    perform set_config('agenda.porta', 'off', true);
    perform pg_temp.aloc(v_x, pg_temp.dono(), date '2026-07-06', 'manha');
    perform pg_temp.aloc(v_x, pg_temp.caio(), date '2026-07-06', 'manha');
    perform pg_temp.diaria(v_x, date '2026-07-06');
    perform public.agenda_medir_os(v_x, c_hoje);
    v_res := pg_temp.ok(v_res, 'M2b6 no comissionamento o dono conta junto com o técnico: 2 pessoa-meios (R7.4)', (select pm_reais = 2 from public.agenda_medidas_os where service_order_id = v_x), (select pm_reais::text from public.agenda_medidas_os where service_order_id = v_x));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    v_x := pg_temp.nova_os(28, date '2026-07-07', date '2026-07-07', 1528, 'DIAGNÓSTICO TÉCNICO NO LOCAL');
    perform pg_temp.aloc(v_x, pg_temp.dono(), date '2026-07-07', 'manha');
    perform pg_temp.aloc(v_x, pg_temp.caio(), date '2026-07-07', 'manha');
    perform pg_temp.diaria(v_x, date '2026-07-07');
    perform public.agenda_medir_os(v_x, c_hoje);
    v_res := pg_temp.ok(v_res, 'M2b7 no diagnóstico (pela linha de maior valor) o dono conta junto com o técnico: 2', (select pm_reais = 2 from public.agenda_medidas_os where service_order_id = v_x), (select pm_reais::text from public.agenda_medidas_os where service_order_id = v_x));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- M2c a diária ligada fora do plano, por pessoa: conta para quem não tem alocação dela naquele dia, mesmo com outro no plano
  begin
    v_x := pg_temp.nova_os(25, date '2026-06-29', date '2026-06-30', 764);
    perform pg_temp.aloc(v_x, pg_temp.zeca(), date '2026-06-29', 'manha');     -- o Zeca no plano; a diária é de Caio, num dia em que ele não tem alocação da OS
    perform pg_temp.aloc(v_x, pg_temp.zeca(), date '2026-06-30', 'manha');
    perform pg_temp.diaria(v_x, date '2026-06-29');
    perform public.agenda_medir_os(v_x, c_hoje);
    v_res := pg_temp.ok(v_res, 'M2c a diária de quem não está na alocação daquele dia conta por pessoa: 2 meios do Zeca + a diária de Caio (2) = 4', (select pm_reais = 4 from public.agenda_medidas_os where service_order_id = v_x), (select pm_reais::text from public.agenda_medidas_os where service_order_id = v_x));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- M2d a diária de Caio no dia em que ele já está na alocação: não conta de novo
  begin
    v_x := pg_temp.nova_os(26, date '2026-07-06', date '2026-07-06', 764);
    perform pg_temp.aloc(v_x, pg_temp.caio(), date '2026-07-06', 'manha');
    perform pg_temp.diaria(v_x, date '2026-07-06');
    perform public.agenda_medir_os(v_x, c_hoje);
    v_res := pg_temp.ok(v_res, 'M2d a diária de quem está na alocação do dia não conta de novo', (select pm_reais = 1 from public.agenda_medidas_os where service_order_id = v_x), (select pm_reais::text from public.agenda_medidas_os where service_order_id = v_x));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$m2$;

-- ── M3. As razões e cada motivo_razao ────────────────────────────────────────────────────────────────
do $m3$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-01-07';
  r1     jsonb;
  v_x    uuid;
  r      record;
  v_dif  text;
  v_v    int;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'M3 razões', true, 'PULADO: sem a fixture'));
    return;
  end if;
  perform set_config('agenda.hoje', c_hoje::text, true);
  begin
    perform public._agenda_aprender_congelar(c_hoje);
    for r in select nome from unnest(array['E1','E2','E3','E4','G1','G2','G3','B1','D1','D2','I1','I2','I3','I5','R1','V1','Z1']) nome loop
      perform public.agenda_medir_os(pg_temp.os(r.nome), c_hoje);
    end loop;
    for r in select * from (values ('E1', 'rv', 'energia', 10::numeric, 11.5::numeric, 1.15::numeric), ('E2','rv','energia',5,6,1.20), ('E3','rv','energia',5,6.5,1.30), ('E4','rv','energia',10,14.5,1.45),
                                   ('G1','rv','geral',4,3,0.75), ('G2','rv','geral',5,4,0.80), ('G3','rv','geral',10,8.5,0.85), ('B1','barco','energia',5,7,1.40)) t(nome, bem, sis, pm_e, pm_r, razao) loop
      if not exists (select 1 from public.agenda_medidas_os m where m.service_order_id = pg_temp.os(r.nome) and m.classe_bem = r.bem and m.classe_sistema = r.sis
                       and m.pm_estimados = r.pm_e and m.pm_reais = r.pm_r and m.razao_estimativa = r.razao and m.estimativa_origem = 'congelada' and m.motivo_razao is null and m.razao_prazo is not null) then
        v_dif := coalesce(v_dif, '') || r.nome || ':' || (select format('%s/%s/%s/%s/%s', m.pm_estimados, m.pm_reais, m.razao_estimativa, m.motivo_razao, m.razao_prazo) from public.agenda_medidas_os m where m.service_order_id = pg_temp.os(r.nome)) || ' ';
      end if;
    end loop;
    v_res := pg_temp.ok(v_res, 'M3a os 8 da §8.2: pm_estimados, pm_reais, razao_estimativa (1,15 1,20 1,30 1,45 0,75 0,80 0,85 1,40), estimativa congelada, motivo_razao nulo', v_dif is null, v_dif);
    v_res := pg_temp.ok(v_res, 'M3a2 a OS do plano concluída no último dia: razao_prazo = 1,00 (E1, 6 dias úteis planejados e reais)',
      (select razao_prazo = 1.00 and prazo_real_du = 6 and prazo_plano_du = 6 from public.agenda_medidas_os where service_order_id = pg_temp.os('E1')),
      (select format('%s %s %s', razao_prazo, prazo_real_du, prazo_plano_du) from public.agenda_medidas_os where service_order_id = pg_temp.os('E1')));
    v_res := pg_temp.ok(v_res, 'M3a2b a OS sem os dias do dono: pm_plano_dono e razao_dono nulos, mesmo com o plano do início congelado',
      (select pm_plano_dono is null and razao_dono is null from public.agenda_medidas_os where service_order_id = pg_temp.os('E1')) and (select pm_plano_no_inicio is not null from public.os_planejamento where service_order_id = pg_temp.os('E1')),
      (select format('%s %s', pm_plano_dono, razao_dono) from public.agenda_medidas_os where service_order_id = pg_temp.os('E1')));
    v_res := pg_temp.ok(v_res, 'M3a3 as 2 do dono: razao_dono 1,05 e 1,10, razao_estimativa nula (diagnóstico, R7.5-9); pm_plano_dono = o molde (10)',
      (select razao_dono = 1.05 and razao_estimativa is null and pm_plano_dono = 10 and motivo_razao is null from public.agenda_medidas_os where service_order_id = pg_temp.os('D1'))
      and (select razao_dono = 1.10 from public.agenda_medidas_os where service_order_id = pg_temp.os('D2')),
      (select format('%s %s %s %s', razao_dono, razao_estimativa, pm_plano_dono, motivo_razao) from public.agenda_medidas_os where service_order_id = pg_temp.os('D1')));
    -- a porta de R7.4
    v_res := pg_temp.ok(v_res, 'M3b Zeca sem perfil de diária, com o resultado: vale (motivo_razao nulo), e a Fase 6 segue dizendo sem_diaria nas medidas dela: sem_dias_no_inicio (motivo e valida não mudam)',
      (select motivo_razao is null and razao_estimativa = 1.00 and not valida and motivo is distinct from null from public.agenda_medidas_os where service_order_id = pg_temp.os('Z1')),
      (select format('%s %s %s', motivo_razao, razao_estimativa, motivo) from public.agenda_medidas_os where service_order_id = pg_temp.os('Z1')));
    v_res := pg_temp.ok(v_res, 'M3b2 o diarista com perfil, sem a diária ligada: sem_diaria', (select motivo_razao = 'sem_diaria' and razao_estimativa is null from public.agenda_medidas_os where service_order_id = pg_temp.os('I1')), null);
    v_res := pg_temp.ok(v_res, 'M3c sem check-in, com dia cumprido: vale (o início é o 1º meio-dia feito, R7.4)',
      (select motivo_razao is null and razao_estimativa = 1.00 and prazo_real_du = 1 from public.agenda_medidas_os where service_order_id = pg_temp.os('V1')),
      (select format('%s %s %s', motivo_razao, razao_estimativa, prazo_real_du) from public.agenda_medidas_os where service_order_id = pg_temp.os('V1')));
    v_res := pg_temp.ok(v_res, 'M3d o plano falso concluído sem nada feito: sem_trabalho (nao_cumprido em tudo), conferencia_incompleta com sem_registro; não mede',
      (select motivo_razao = 'sem_trabalho' and razao_estimativa is null from public.agenda_medidas_os where service_order_id = pg_temp.os('I5'))
      and (select motivo_razao = 'conferencia_incompleta' from public.agenda_medidas_os where service_order_id = pg_temp.os('I2')), null);
    v_res := pg_temp.ok(v_res, 'M3d2 sem estimativa nem plano do dono: sem_estimativa', (select motivo_razao = 'sem_estimativa' and razao_estimativa is null from public.agenda_medidas_os where service_order_id = pg_temp.os('I3')), null);
    -- sem_inicio: sem check-in e sem meio-dia feito; o check-in sozinho já vale
    v_x := pg_temp.nova_os(31, date '2026-05-14', date '2026-05-14', 764);
    update public.service_orders set check_in_at = null where id = v_x;
    perform pg_temp.aloc(v_x, pg_temp.caio(), date '2026-05-14', 'manha', 'nao_cumprido');
    perform public.agenda_medir_os(v_x, c_hoje);
    v_res := pg_temp.ok(v_res, 'M3e sem check-in e sem meio-dia feito: sem_inicio', (select motivo_razao = 'sem_inicio' from public.agenda_medidas_os where service_order_id = v_x), (select coalesce(motivo_razao, 'nulo') from public.agenda_medidas_os where service_order_id = v_x));
    -- sem_fim: concluída, sem check-out e sem o instante da porta
    v_x := pg_temp.nova_os(34, date '2026-05-15', date '2026-05-15', 764);
    perform pg_temp.aloc(v_x, pg_temp.caio(), date '2026-05-15', 'manha');
    perform pg_temp.diaria(v_x, date '2026-05-15');
    perform set_config('agenda.porta', 'on', true);
    update public.service_orders set check_out_at = null, delivered_at = null where id = v_x;
    perform set_config('agenda.porta', 'off', true);
    perform public.agenda_medir_os(v_x, c_hoje);
    v_res := pg_temp.ok(v_res, 'M3e2 concluída sem o dia da conclusão: sem_fim', (select motivo_razao = 'sem_fim' and razao_estimativa is null from public.agenda_medidas_os where service_order_id = v_x), (select coalesce(motivo_razao, 'nulo') from public.agenda_medidas_os where service_order_id = v_x));
    -- a idempotência: 2ª rodada, a mesma versão em todas
    select count(*) into v_v from public.agenda_medidas_os where service_order_id = any (array[pg_temp.os('E1'), pg_temp.os('D1'), pg_temp.os('I1')]);
    r1 := public.agenda_medir_os(pg_temp.os('E1'), c_hoje);
    v_res := pg_temp.ok(v_res, 'M3f 2 rodadas = a mesma versão (não anda de versão a cada rodada, R7.5-1)', r1 ->> 'mudou' = 'false' and r1 ->> 'versao' = '1' and r1 ? 'razao_estimativa' and r1 ? 'motivo_razao', r1::text);
    -- a reaberta
    perform set_config('agenda.porta', 'on', true);
    update public.service_orders set status = 'in_progress' where id = pg_temp.os('R1');
    perform set_config('agenda.porta', 'off', true);
    r1 := public.agenda_medir_os(pg_temp.os('R1'), c_hoje);
    v_res := pg_temp.ok(v_res, 'M3g a medida que voltou de concluída: motivo_razao reaberta (versão + 1 e sem razão)', r1 ->> 'motivo_razao' = 'reaberta'
      and (select motivo_razao = 'reaberta' and razao_estimativa is null and versao = 2 from public.agenda_medidas_os where service_order_id = pg_temp.os('R1')), r1::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$m3$;

-- M3h: os 3 caminhos de gravação (R7.5-1): a nova (insert), a do 1º update (fonte orcamento) e a do 2º update (as outras). Sem nulo em nenhuma, 2 rodadas = 1 versão.
do $m3h$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-01-07';
  v_x    uuid;
  v_y    uuid;
  r1     jsonb;
  r2     jsonb;
  r3     jsonb;
begin
  if not pg_temp.fx() then return; end if;
  perform set_config('agenda.hoje', c_hoje::text, true);
  begin
    v_x := pg_temp.nova_os(32, date '2026-05-26', date '2026-05-27', 1528);
    insert into public.os_planejamento (service_order_id, dias_no_inicio, dias_no_inicio_fonte, dias_no_inicio_em) values (v_x, 2, 'orcamento', date '2026-05-26');
    perform pg_temp.aloc(v_x, pg_temp.caio(), date '2026-05-26', 'manha');
    perform pg_temp.diaria(v_x, date '2026-05-26');
    r1 := public.agenda_medir_os(v_x, c_hoje);   -- insert
    perform pg_temp.aloc(v_x, pg_temp.caio(), date '2026-05-26', 'tarde');
    r2 := public.agenda_medir_os(v_x, c_hoje);   -- 1º update (orcamento)
    r3 := public.agenda_medir_os(v_x, c_hoje);
    v_res := pg_temp.ok(v_res, 'M3h a OS de fonte orcamento: as colunas gravam pelo 1º update (pm_reais anda) e a 2ª rodada não muda (M3e de R7.13)',
      r1 ->> 'nova' = 'true' and r2 ->> 'mudou' = 'true' and r3 ->> 'mudou' = 'false' and r2 ->> 'versao' = '2'
      and (select pm_reais = 2 and dias_fonte = 'orcamento' and versao = 2 and compra_pendente is not null from public.agenda_medidas_os where service_order_id = v_x),
      format('%s / %s / %s', r1, r2, r3));
    v_y := pg_temp.nova_os(33, date '2026-05-28', date '2026-05-28', 764);
    perform pg_temp.aloc(v_y, pg_temp.caio(), date '2026-05-28', 'manha');
    perform pg_temp.diaria(v_y, date '2026-05-28');
    perform public.agenda_medir_os(v_y, c_hoje);
    perform pg_temp.aloc(v_y, pg_temp.caio(), date '2026-05-28', 'tarde');
    r2 := public.agenda_medir_os(v_y, c_hoje);   -- 2º update
    r3 := public.agenda_medir_os(v_y, c_hoje);
    v_res := pg_temp.ok(v_res, 'M3i as outras: o 2º update grava as colunas (pm_reais 1 → 2) e a 2ª rodada não muda',
      r2 ->> 'mudou' = 'true' and r3 ->> 'mudou' = 'false' and (select pm_reais = 2 and versao = 2 from public.agenda_medidas_os where service_order_id = v_y), format('%s / %s', r2, r3));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$m3h$;

-- ── M4. A medida da compra ───────────────────────────────────────────────────────────────────────────
create function pg_temp.mc(p_linha text) returns jsonb language sql stable as $f$
  select to_jsonb(m) from public.agenda_medidas_compra m where m.os_material_id = md5('e7e:material:' || p_linha)::uuid
$f$;

do $m4$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-01-07';
  l      text;
  r1     jsonb;
  r2     jsonb;
  v_os0  constant uuid := 'e7e00000-0000-4000-8000-000000000e00';
  v_l    uuid;
  v_n    int;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'M4 compras', true, 'PULADO: sem a fixture'));
    return;
  end if;
  perform set_config('agenda.hoje', c_hoje::text, true);
  -- UTC, como na produção: a entrada com só a data tem de cair no dia certo (a mutação "tudo é timestamptz" recua um dia aqui)
  perform set_config('timezone', 'UTC', true);
  begin
    foreach l in array array['m1','m2','m3','m4','m5','m6'] loop
      perform public.agenda_medir_compra(md5('e7e:material:' || l)::uuid, c_hoje);
    end loop;
    -- as 4 fontes, na ordem
    v_res := pg_temp.ok(v_res, 'M4a a 1ª fonte: comprado_em da linha, fonte nula vira dono; 3 dias úteis da aprovação (01/12) à compra (04/12)',
      pg_temp.mc('m1') ->> 'comprado_em' = '2026-12-04' and pg_temp.mc('m1') ->> 'comprado_fonte' = 'dono' and (pg_temp.mc('m1') ->> 'tempo_compra_du')::int = 3
      and (pg_temp.mc('m1') ->> 'valida_tempo')::boolean and not (pg_temp.mc('m1') ->> 'valida_prazo')::boolean and pg_temp.mc('m1') ->> 'motivo' = 'sem_chegada', pg_temp.mc('m1')::text);
    v_res := pg_temp.ok(v_res, 'M4b a 2ª fonte: a nota ligada (nfe), sem comprado_em na linha', pg_temp.mc('m4') ->> 'comprado_em' = '2026-12-07' and pg_temp.mc('m4') ->> 'comprado_fonte' = 'nfe' and pg_temp.mc('m4') ->> 'entrega' like 'nota:%', pg_temp.mc('m4')::text);
    v_res := pg_temp.ok(v_res, 'M4c a 3ª fonte: a 1ª entrada do histórico pela chave para (R7.5-3), o em só com a data', pg_temp.mc('m5') ->> 'comprado_em' = '2026-12-02' and pg_temp.mc('m5') ->> 'comprado_fonte' = 'registro', pg_temp.mc('m5')::text);
    v_res := pg_temp.ok(v_res, 'M4d a 4ª fonte: na mão direto com fonte dono = balcão: fora do tempo, fora do prazo',
      pg_temp.mc('m6') ->> 'comprado_fonte' = 'balcao' and pg_temp.mc('m6') ->> 'comprado_em' = '2026-12-03' and not (pg_temp.mc('m6') ->> 'valida_tempo')::boolean
      and not (pg_temp.mc('m6') ->> 'valida_prazo')::boolean and pg_temp.mc('m6') ->> 'motivo' = 'balcao_inferido', pg_temp.mc('m6')::text);
    v_res := pg_temp.ok(v_res, 'M4e a linha em falta entra: fonte nula passa pelo is distinct from (R7.5-4) e sem compra o tempo é nulo, não 0 (R7.12-2)',
      pg_temp.mc('m2') is not null and pg_temp.mc('m2') -> 'tempo_compra_du' = 'null' and pg_temp.mc('m2') -> 'comprado_em' = 'null' and pg_temp.mc('m2') ->> 'motivo' = 'sem_compra', pg_temp.mc('m2')::text);
    v_res := pg_temp.ok(v_res, 'M4f compre_ate_base: sem marcação não há retrato nem prazo contado; a linha entra (R7.5-6)', pg_temp.mc('m3') -> 'prazo_contado_du' = 'null' and pg_temp.mc('m3') -> 'primeiro_dia' = 'null' and pg_temp.mc('m3') ->> 'motivo' = 'sem_compra', pg_temp.mc('m3')::text);
    -- 2 rodadas, nada muda; mudar a linha muda, versão + 1
    r1 := public.agenda_medir_compra(md5('e7e:material:m1')::uuid, c_hoje);
    v_res := pg_temp.ok(v_res, 'M4g 2ª rodada: nada muda (versão 1)', r1 ->> 'mudou' = 'false' and r1 ->> 'versao' = '1', r1::text);
    update public.os_material set comprado_em = date '2026-12-09' where id = md5('e7e:material:m1')::uuid;
    r1 := public.agenda_medir_compra(md5('e7e:material:m1')::uuid, c_hoje);
    v_res := pg_temp.ok(v_res, 'M4h a linha mudou: versão + 1 e o que mudou no histórico', r1 ->> 'mudou' = 'true' and r1 ->> 'versao' = '2'
      and jsonb_array_length(pg_temp.mc('m1') -> 'historico') = 1 and pg_temp.mc('m1') ->> 'comprado_em' = '2026-12-09', r1::text);
    -- o miúdo que a coluna diz crítico (R7.5-5): valor 100 abaixo do limiar = não entra
    insert into public.service_order_parts (id, service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot, line_total_cost, line_total_sale, created_at)
    select md5('e7e:x-peca')::uuid, v_os0, (select id from public.products order by id limit 1), 1, 50, 100, 50, 100, timestamptz '2026-12-02 10:00-03';
    insert into public.os_material (id, service_order_id, service_order_part_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico, situacao, fonte, atualizado_por)
    values (md5('e7e:material:x1')::uuid, v_os0, md5('e7e:x-peca')::uuid, 'peca', 'Parafuso', 1, 0, true, 'falta', null, 'aa000000-0000-4000-8000-000000000001');
    r1 := public.agenda_medir_compra(md5('e7e:material:x1')::uuid, c_hoje);
    v_res := pg_temp.ok(v_res, 'M4i critico true na coluna, valor 100 (abaixo de critico_valor_min) e sem fato do dono: nao_critica, sem linha na medida (R7.5-5)',
      r1 ->> 'medida' = 'false' and r1 ->> 'motivo' = 'nao_critica' and pg_temp.mc('x1') is null and not public._agenda_material_critico(md5('e7e:material:x1')::uuid), r1::text);
    update public.os_material set fonte = 'dono' where id = md5('e7e:material:x1')::uuid;
    r1 := public.agenda_medir_compra(md5('e7e:material:x1')::uuid, c_hoje);
    v_res := pg_temp.ok(v_res, 'M4i2 o fato do dono vence: fonte dono com critico true entra', r1 ->> 'medida' = 'true' and public._agenda_material_critico(md5('e7e:material:x1')::uuid), r1::text);
    -- a peça tem precisou_em = greatest(aprovada, created_at da peça em Brasília)
    v_res := pg_temp.ok(v_res, 'M4i3 precisou_em: a peça lançada depois da aprovação (02/12) vale pela peça', pg_temp.mc('x1') ->> 'precisou_em' = '2026-12-02', pg_temp.mc('x1')::text);
    -- M4c2 a entrada do histórico com hora (forma do relógio): o dia em Brasília; a chegada só quando na mão
    insert into public.os_material (id, service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico, situacao, fonte, chegou_em, historico, atualizado_por)
    values (md5('e7e:material:x5')::uuid, v_os0, 'dono', 'Cabo', 1, 0, true, 'comprado', null, date '2026-12-08',
            jsonb_build_array(jsonb_build_object('em', '2026-12-05T01:00:00+00:00', 'de', 'falta', 'para', 'comprado', 'por', 'dono', 'autor', null, 'trecho', 'x', 'nota', null)), 'aa000000-0000-4000-8000-000000000001');
    r1 := public.agenda_medir_compra(md5('e7e:material:x5')::uuid, c_hoje);
    v_res := pg_temp.ok(v_res, 'M4c2 a entrada do histórico com hora (forma do relógio): o dia em Brasília (22:00 de 04/12) e chegou_em só quando na mão', pg_temp.mc('x5') ->> 'comprado_em' = '2026-12-04' and pg_temp.mc('x5') -> 'chegou_em' = 'null', pg_temp.mc('x5')::text);
    -- M4i6 a crítica de fonte estoque: não entra (a linha fica fora da medida), ainda que em falta
    insert into public.os_material (id, service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico, situacao, fonte, atualizado_por)
    values (md5('e7e:material:x4')::uuid, v_os0, 'dono', 'Óleo', 1, 0, true, 'falta', 'estoque', 'aa000000-0000-4000-8000-000000000001');
    r1 := public.agenda_medir_compra(md5('e7e:material:x4')::uuid, c_hoje);
    v_res := pg_temp.ok(v_res, 'M4i6 a linha crítica de estoque, em falta: não entra na medida', r1 ->> 'medida' = 'false' and r1 ->> 'motivo' = 'sem_compra' and pg_temp.mc('x4') is null, r1::text);
    -- o estoque não entra; sem compra nem falta, também não
    update public.os_material set fonte = 'estoque', situacao = 'dispensado' where id = md5('e7e:material:x1')::uuid;
    r1 := public.agenda_medir_compra(md5('e7e:material:x1')::uuid, c_hoje);
    v_res := pg_temp.ok(v_res, 'M4i4 o miúdo que deixou de valer (fonte estoque): nao_critica, versão nova, nada válido', r1 ->> 'mudou' = 'true' and pg_temp.mc('x1') ->> 'motivo' = 'nao_critica' and not (pg_temp.mc('x1') ->> 'valida_tempo')::boolean, r1::text);
    -- a crítica sem valor que virou estoque/dispensada fica sem_compra
    update public.os_material set fonte = 'estoque', situacao = 'dispensado' where id = md5('e7e:material:m2')::uuid;
    r1 := public.agenda_medir_compra(md5('e7e:material:m2')::uuid, c_hoje);
    v_res := pg_temp.ok(v_res, 'M4i5 a crítica que virou estoque: sem_compra, sem entrar de novo com a compra', pg_temp.mc('m2') ->> 'motivo' = 'sem_compra', r1::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform set_config('timezone', 'Etc/GMT+3', true);
  perform pg_temp.gravar(v_res);
end
$m4$;

-- M4r (R7.5-5): _agenda_material_critico dá o mesmo que os_prontidao, com a regra critico_por_valor ligada, em toda linha da fixture (peça abaixo e acima do limiar, texto livre, oc, dono); sem a regra, ele continua igual (não tem portão)
do $m4r$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-01-07';
  v_os0  constant uuid := 'e7e00000-0000-4000-8000-000000000e00';
  v_dif  text;
  v_n    int := 0;
  v_c    int;
  r      record;
begin
  if not pg_temp.fx() then return; end if;
  perform set_config('agenda.hoje', c_hoje::text, true);
  begin
    update public.agenda_config set modo_marcar_sozinho = 'ligado', gestor_so_propor = false, marcar_regras = '{critico_por_valor}' where id;
    insert into public.service_order_parts (id, service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot, line_total_cost, line_total_sale, created_at)
    select md5('e7e:x-p' || n)::uuid, v_os0, (select id from public.products order by id limit 1), 1, 50, v, 50, v, timestamptz '2026-12-02 10:00-03'
      from (values (1, 100::numeric), (2, 900)) t(n, v);
    insert into public.os_material (id, service_order_id, service_order_part_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico, situacao, fonte, atualizado_por)
    select md5('e7e:material:p' || n)::uuid, v_os0, md5('e7e:x-p' || n)::uuid, 'peca', 'Peça ' || n, 1, 0, true, 'falta', null, 'aa000000-0000-4000-8000-000000000001' from generate_series(1, 2) n;
    update public.agenda_config set critico_valor_min = 300 where id;
    for r in select i, i ->> 'id' as id from jsonb_array_elements(public.os_prontidao(v_os0, c_hoje) #> '{material,itens}') i where i ->> 'id' is not null loop
      v_n := v_n + 1;
      if public._agenda_material_critico(r.id::uuid) is distinct from coalesce((r.i ->> 'critico')::boolean, true) then
        v_dif := coalesce(v_dif, '') || r.id || ' ';
      end if;
    end loop;
    select count(*) into v_c from jsonb_array_elements(public.os_prontidao(v_os0, c_hoje) #> '{material,itens}') i where not coalesce((i ->> 'critico')::boolean, true);
    v_res := pg_temp.ok(v_res, 'M4r a função dá o mesmo crítico que os_prontidao (critico_por_valor ligada), em toda linha, e a peça de R$ 100 sai não crítica', v_n >= 7 and v_c >= 1 and v_dif is null, format('linhas=%s nao_criticas=%s dif=%s', v_n, v_c, v_dif));
    update public.agenda_config set modo_marcar_sozinho = 'desligado' where id;
    v_res := pg_temp.ok(v_res, 'M4r2 sem a regra, a função continua igual (sem portão); a prontidão diz crítico de novo na coluna, mas a medida usa a função', not public._agenda_material_critico(md5('e7e:material:p1')::uuid), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$m4r$;

-- M4j: o retrato (o molde do P10: compre_ate_base na forma real), gravado uma vez; a chegada contada, o atraso, o limite, primeiro dia cumprido, a previsão anterior à compra, compra_pendente
do $m4j$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-01-07';
  v_x    uuid;
  v_os   uuid;
  v_l    uuid := md5('e7e:material:x2')::uuid;
  r1     jsonb;
begin
  if not pg_temp.fx() then return; end if;
  perform set_config('agenda.hoje', c_hoje::text, true);
  begin
    v_x := pg_temp.nova_os(41, date '2026-11-16', date '2026-11-18', 2292);
    v_os := v_x;
    -- publicada em 10/11 (marcado_em); 1º dia 16/11; uma linha em falta com o compre até gravado na forma real (padrão)
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, resultado, resultado_via, resultado_em)
    values (v_os, pg_temp.caio(), date '2026-11-16', 'manha', 'turno', 'execucao', 'publicada', 'motor', timestamptz '2026-11-10 16:30-03', 'cumprido', 'dia_feito', timestamptz '2026-11-16 17:30-03');
    insert into public.os_planejamento (service_order_id, marcado_em, vies_marcado, tempo_compra_marcado, folga_compra_marcada, atualizado_em)
    values (v_os, date '2026-11-10', 1, 1, 0, timestamptz '2026-10-01 10:00-03');
    insert into public.os_material (id, service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico, situacao, fonte, comprado_em, comprado_fonte, compre_ate, compre_ate_em, compre_ate_base, atualizado_por, previsao_original_em)
    values (v_l, v_os, 'dono', 'Bateria', 1, 0, true, 'comprado', null, date '2026-11-12', 'dono', date '2026-11-05', timestamptz '2026-11-01 10:00-03',
            jsonb_build_object('primeiro', date '2026-11-16', 'folga', 1, 'prazo', 2, 'prazo_fonte', 'padrao', 'interno', 1), 'aa000000-0000-4000-8000-000000000001', date '2026-11-11');
    r1 := public.agenda_medir_compra(v_l, c_hoje);
    v_res := pg_temp.ok(v_res, 'M4j o retrato da marcação: marcada_em (o dia da publicada), primeiro_dia (16/11), compre_ate gravado, prazo contado da base (R7.5-6), chegada contada (1º dia − folga), sem_fornecedor pela fonte padrão',
      pg_temp.mc('x2') ->> 'marcada_em' = '2026-11-10' and pg_temp.mc('x2') ->> 'primeiro_dia' = '2026-11-16' and pg_temp.mc('x2') ->> 'compre_ate' = '2026-11-05'
      and (pg_temp.mc('x2') ->> 'prazo_contado_du')::int = 2 and pg_temp.mc('x2') ->> 'prazo_fonte' = 'padrao' and (pg_temp.mc('x2') ->> 'tempo_interno_du')::int = 1
      and pg_temp.mc('x2') ->> 'chegada_contada' = '2026-11-13' and (pg_temp.mc('x2') ->> 'sem_fornecedor')::boolean, pg_temp.mc('x2')::text);
    -- M4n2 a compra antes da marcação: sem retrato, sem folga, motivo comprada_antes_de_marcar
    insert into public.os_material (id, service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico, situacao, fonte, comprado_em, chegou_em, atualizado_por)
    values (md5('e7e:material:x6')::uuid, v_os, 'dono', 'Terminal', 1, 1, true, 'na_mao', 'dono', date '2026-11-05', date '2026-11-20', 'aa000000-0000-4000-8000-000000000001');
    r1 := public.agenda_medir_compra(md5('e7e:material:x6')::uuid, c_hoje);
    v_res := pg_temp.ok(v_res, 'M4n2 a compra antes da marcação: sem retrato, comprada_antes_de_marcar, não vale para a folga', pg_temp.mc('x6') -> 'marcada_em' = 'null' and pg_temp.mc('x6') ->> 'motivo' = 'comprada_antes_de_marcar' and not (pg_temp.mc('x6') ->> 'valida_folga')::boolean, pg_temp.mc('x6')::text);
    -- compra depois do limite, previsão anterior à compra
    v_res := pg_temp.ok(v_res, 'M4k comprou depois do limite; a previsão anterior à compra fica marcada (compra_antes, d6) e a linha vale', (pg_temp.mc('x2') ->> 'comprou_ate_o_limite')::boolean = false and pg_temp.mc('x2') ->> 'motivo' = 'sem_chegada', pg_temp.mc('x2')::text);
    update public.os_material set situacao = 'na_mao', chegou_em = date '2026-11-20', quantidade_na_mao = 1 where id = v_l;
    r1 := public.agenda_medir_compra(v_l, c_hoje);
    v_res := pg_temp.ok(v_res, 'M4l chegou: prazo real e atraso (contada 13/11 → chegou 20/11, 4 d.u.: 20/11 é feriado; da compra 12/11, 5); a previsão anterior à compra entra como compra_antes e a linha vale',
      (pg_temp.mc('x2') ->> 'prazo_real_du')::int = 5 and (pg_temp.mc('x2') ->> 'atraso_chegada_du')::int = 4 and (pg_temp.mc('x2') ->> 'valida_prazo')::boolean and (pg_temp.mc('x2') ->> 'valida_folga')::boolean and pg_temp.mc('x2') ->> 'motivo' = 'compra_antes', pg_temp.mc('x2')::text);
    v_res := pg_temp.ok(v_res, 'M4m primeiro_dia_cumprido: houve meio-dia cumprido no 1º dia', (pg_temp.mc('x2') ->> 'primeiro_dia_cumprido')::boolean, pg_temp.mc('x2')::text);
    -- o retrato não muda: mudar a marcação e as alocações não toca nele
    update public.os_planejamento set marcado_em = date '2026-11-15' where service_order_id = v_os;
    update public.agenda_alocacoes set publicada_em = timestamptz '2026-11-15 16:30-03' where service_order_id = v_os;
    r1 := public.agenda_medir_compra(v_l, c_hoje);
    v_res := pg_temp.ok(v_res, 'M4n o retrato é gravado uma vez e não muda depois', r1 ->> 'mudou' = 'false' and pg_temp.mc('x2') ->> 'marcada_em' = '2026-11-10', r1::text);
    -- compra_pendente na OS: a medida com marcada_em e comprado depois
    r1 := public.agenda_medir_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'M4o compra_pendente na medida da OS: a compra veio depois da marcação (R7.5-1)', (select compra_pendente from public.agenda_medidas_os where service_order_id = v_os), r1::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$m4j$;

-- M4p: o desvio 10 do P1: a medida some com a linha (a cascata) e fornecedor_id vira nulo sem versão nova
do $m4p$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-01-07';
  v_os0  constant uuid := 'e7e00000-0000-4000-8000-000000000e00';
  v_forn constant uuid := 'e7e00000-0000-4000-8000-00000000ff01';
  v_l    uuid := md5('e7e:material:m4')::uuid;
  v_rem  uuid := md5('e7e:remessa:1')::uuid;
  v_l2   uuid := md5('e7e:material:x3')::uuid;
  v_peca uuid := md5('e7e:x-peca-2')::uuid;
  r1     jsonb;
  r2     jsonb;
  v_ver  int;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'M4p desvio 10', true, 'PULADO: sem a fixture'));
    return;
  end if;
  perform set_config('agenda.hoje', c_hoje::text, true);
  begin
    -- o fornecedor vem da nota: apagar o fornecedor deixa a medida com fornecedor nulo, sem versão nova (ON DELETE SET NULL)
    insert into public.suppliers (id, name) values (v_forn, 'Fornecedor do teste');
    update public.material_remessas set fornecedor_id = v_forn where id = v_rem;
    update public.os_material set compre_ate = date '2026-12-05', compre_ate_em = timestamptz '2026-12-01 10:00-03',
           compre_ate_base = jsonb_build_object('primeiro', date '2026-12-10', 'folga', 1, 'prazo', 2, 'prazo_fonte', 'fornecedor', 'interno', 1)
     where id = v_l;
    r1 := public.agenda_medir_compra(v_l, c_hoje);
    select versao into v_ver from public.agenda_medidas_compra where os_material_id = v_l;
    v_res := pg_temp.ok(v_res, 'M4p1 a medida guarda o fornecedor da nota', pg_temp.mc('m4') ->> 'fornecedor_id' = v_forn::text and v_ver = 1, pg_temp.mc('m4')::text);
    delete from public.suppliers where id = v_forn;
    v_res := pg_temp.ok(v_res, 'M4p2 apagar o fornecedor (fora da agenda) passa: fornecedor_id nulo e sem versão nova', pg_temp.mc('m4') -> 'fornecedor_id' = 'null' and (pg_temp.mc('m4') ->> 'versao')::int = 1, pg_temp.mc('m4')::text);
    r2 := public.agenda_medir_compra(v_l, c_hoje);
    v_res := pg_temp.ok(v_res, 'M4p3 a rodada seguinte vê o nulo como o de hoje: não acha diferença, não falha (desvio 10)', r2 ->> 'mudou' = 'false' and r2 ->> 'ok' = 'true', r2::text);
    -- a medida some com a linha: a peça tirada da OS
    insert into public.service_order_parts (id, service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot, line_total_cost, line_total_sale, created_at)
    select v_peca, v_os0, (select id from public.products order by id limit 1), 1, 450, 900, 450, 900, timestamptz '2026-12-02 10:00-03';
    insert into public.os_material (id, service_order_id, service_order_part_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico, situacao, fonte, atualizado_por)
    values (v_l2, v_os0, v_peca, 'peca', 'Bomba', 1, 0, true, 'falta', null, 'aa000000-0000-4000-8000-000000000001');
    r1 := public.agenda_medir_compra(v_l2, c_hoje);
    v_res := pg_temp.ok(v_res, 'M4p4 a linha da peça gravou medida', pg_temp.mc('x3') is not null, r1::text);
    delete from public.service_order_parts where id = v_peca;
    v_res := pg_temp.ok(v_res, 'M4p5 tirar a peça da OS (fora da agenda) passa e leva a medida', pg_temp.mc('x3') is null, null);
    r1 := public.agenda_medir_compra(v_l2, c_hoje);
    v_res := pg_temp.ok(v_res, 'M4p6 a linha que sumiu: medida falso, sem_linha, sem erro', r1 ->> 'ok' = 'true' and r1 ->> 'medida' = 'false' and r1 ->> 'motivo' = 'sem_linha', r1::text);
    r1 := public._agenda_aprender_medir_compras(c_hoje);
    v_res := pg_temp.ok(v_res, 'M4p7 o passo da rodada segue sem erro depois das duas coisas', (r1 ->> 'erros')::int = 0 and (r1 ->> 'olhadas')::int > 0, r1::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$m4p$;

-- M4q: o passo da rodada: o erro de uma linha não derruba as outras; a linha fora da janela sem mudança não é olhada; a OS agrupada não entra
do $m4q$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-01-07';
  v_os0  constant uuid := 'e7e00000-0000-4000-8000-000000000e00';
  r1     jsonb;
  v_ini  int;
begin
  if not pg_temp.fx() then return; end if;
  perform set_config('agenda.hoje', c_hoje::text, true);
  begin
    r1 := public._agenda_aprender_medir_compras(c_hoje);
    v_res := pg_temp.ok(v_res, 'M4q1 o passo devolve {olhadas, medidas, validas, erros} e mede as 6 linhas da OS-E0 (janela de 365)',
      (r1 ->> 'olhadas')::int >= 6 and (r1 ->> 'medidas')::int >= 6 and r1 ? 'validas' and (r1 -> 'validas') ? 'tempo' and (r1 ->> 'erros')::int = 0, r1::text);
    -- o histórico com o "em" torto: a linha cai no EXCEPTION, as outras seguem
    update public.os_material set historico = '[{"em": "torto", "para": "comprado"}]'::jsonb, comprado_em = null, remessa_id = null where id = md5('e7e:material:m5')::uuid;
    r1 := public._agenda_aprender_medir_compras(c_hoje);
    v_res := pg_temp.ok(v_res, 'M4q2 o erro de uma linha (a data torta) não derruba o passo: 1 erro, as outras medidas, app_error_logs aprender:medir_compras',
      (r1 ->> 'erros')::int = 1 and (r1 ->> 'medidas')::int >= 5
      and exists (select 1 from public.app_error_logs e where e.context = 'agenda' and e.action = 'aprender:medir_compras'), r1::text);
    -- janela: a OS aprovada há mais de N dias sem mudança depois da medida não é olhada; com mudança depois da medida, é
    update public.os_material set historico = '[]'::jsonb where id = md5('e7e:material:m5')::uuid;
    update public.agenda_config set aprender_janela_dias = 90 where id;
    perform public._agenda_aprender_medir_compras(c_hoje);   -- medida gravada; agora a OS sai da janela
    update public.service_orders set converted_to_os_at = timestamptz '2026-06-01 10:00-03' where id = v_os0;
    update public.os_material set atualizado_em = timestamptz '2026-01-01 10:00-03';
    r1 := public._agenda_aprender_medir_compras(c_hoje);
    v_ini := (r1 ->> 'olhadas')::int;
    v_res := pg_temp.ok(v_res, 'M4q3 a OS fora da janela e a linha sem mudança depois da medida: não olha', v_ini = 0, r1::text);
    update public.os_material set atualizado_em = now() + interval '1 day' where id = md5('e7e:material:m1')::uuid;
    r1 := public._agenda_aprender_medir_compras(c_hoje);
    update public.agenda_config set aprender_janela_dias = 365 where id;
    v_res := pg_temp.ok(v_res, 'M4q3b a linha que mudou depois da medida é olhada mesmo fora da janela', (r1 ->> 'olhadas')::int = 1, r1::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$m4q$;

-- ── M5. O congelar da marcação ───────────────────────────────────────────────────────────────────────
do $m5$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-01-07';
  v_x    uuid;
  v_y    uuid;
  r1     jsonb;
  r2     jsonb;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'M5 marcação', true, 'PULADO: sem a fixture'));
    return;
  end if;
  perform set_config('agenda.hoje', c_hoje::text, true);
  begin
    v_x := pg_temp.nova_os(51, date '2027-01-11', date '2027-01-12', 764);
    v_y := pg_temp.nova_os(52, date '2027-01-13', date '2027-01-14', 764);
    -- de hoje em diante, sem resultado: publicada em 05/01
    perform set_config('agenda.porta', 'on', true);
    update public.service_orders set status = 'open' where id in (v_x, v_y);
    perform set_config('agenda.porta', 'off', true);
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    values (v_x, pg_temp.caio(), date '2027-01-11', 'manha', 'turno', 'execucao', 'publicada', 'motor', timestamptz '2027-01-05 16:30-03');
    r1 := public._agenda_aprender_congelar_marcacao(c_hoje);
    v_res := pg_temp.ok(v_res, 'M5a a OS com compromisso e sem linha em os_planejamento congela: marcado_em = o dia da publicada, viés 1,00, tempo = compra_interna_du, folga 0, sem chave',
      (r1 ->> 'congeladas')::int >= 1
      and (select marcado_em = date '2027-01-05' and vies_marcado = 1 and vies_marcado_chave is null and tempo_compra_marcado = (select compra_interna_du from public.agenda_config where id)
                  and folga_compra_marcada = 0 from public.os_planejamento where service_order_id = v_x), r1::text);
    v_res := pg_temp.ok(v_res, 'M5b a linha nasce com atualizado_em = a criação da OS (R7.5-22)',
      (select pl.atualizado_em = so.created_at from public.os_planejamento pl join public.service_orders so on so.id = pl.service_order_id where pl.service_order_id = v_x), null);
    r2 := public._agenda_aprender_congelar_marcacao(c_hoje);
    v_res := pg_temp.ok(v_res, 'M5c uma vez só: a 2ª rodada não congela a mesma', not exists (select 1 from public.agenda_acoes a where false) and (r2 ->> 'congeladas')::int < (r1 ->> 'congeladas')::int, r2::text);
    -- soltar: sem compromisso vigente nem meio-dia feito
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_em = timestamptz '2027-01-06 10:00-03', cancelada_motivo = 'replanejado' where service_order_id = v_x;
    r1 := public._agenda_aprender_congelar_marcacao(c_hoje);
    v_res := pg_temp.ok(v_res, 'M5d a OS que voltou à fila solta o congelado (as 5 colunas)', (r1 ->> 'soltas')::int >= 1
      and (select marcado_em is null and vies_marcado is null and tempo_compra_marcado is null and folga_compra_marcada is null from public.os_planejamento where service_order_id = v_x), r1::text);
    -- a saída do dono fica
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    values (v_y, pg_temp.caio(), date '2027-01-13', 'manha', 'turno', 'execucao', 'publicada', 'motor', timestamptz '2027-01-05 16:30-03');
    perform public._agenda_aprender_congelar_marcacao(c_hoje);
    update public.os_planejamento set vies_dono_fixo = true where service_order_id = v_y;
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_em = timestamptz '2027-01-06 10:00-03', cancelada_motivo = 'replanejado' where service_order_id = v_y;
    r1 := public._agenda_aprender_congelar_marcacao(c_hoje);
    v_res := pg_temp.ok(v_res, 'M5e vies_dono_fixo: a OS que voltou à fila não solta (R7.3-2)', (select marcado_em is not null from public.os_planejamento where service_order_id = v_y), r1::text);
    -- o viés em uso e o meio-dia feito; a OS só com meio-dia feito no passado (sem alocação futura)
    update public.os_planejamento set vies_dono_fixo = false, marcado_em = null, vies_marcado = null, vies_marcado_chave = null, tempo_compra_marcado = null, folga_compra_marcada = null where service_order_id = v_y;
    update public.agenda_config set modo_aprendizado = 'ligado', modo_vies = 'ligado', gestor_so_propor = false where id;
    insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, calculado, em_uso, estado, calculado_em)
    values ('vies', 'estimativa:rv:geral', 'fina', 1, 1, 3, 1.2, 1.2, 'em_uso', now());
    perform pg_temp.aloc(v_y, pg_temp.caio(), date '2027-01-06', 'manha');
    r1 := public._agenda_aprender_congelar_marcacao(c_hoje);
    v_res := pg_temp.ok(v_res, 'M5f só com meio-dia feito (sem alocação futura) congela; o viés em uso e a chave fina',
      (select vies_marcado = 1.2 and vies_marcado_chave = 'estimativa:rv:geral' from public.os_planejamento where service_order_id = v_y),
      (select format('%s %s', vies_marcado, vies_marcado_chave) from public.os_planejamento where service_order_id = v_y));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$m5$;

-- ── M6. O gravador por passo ─────────────────────────────────────────────────────────────────────────
create function pg_temp.grava(p_item text, p_chave text, p_nivel text, p_calc numeric, p_n int, p_padrao numeric, p_detalhe jsonb, p_agora timestamptz) returns jsonb language sql as $f$
  select public._agenda_aprendizado_gravar(p_item, p_chave, p_nivel, p_calc, p_n, '[]'::jsonb, p_padrao, p_detalhe, p_agora)
$f$;

do $m6$
declare
  v_res   jsonb := '[]'::jsonb;
  c_d1    constant timestamptz := timestamptz '2027-01-07 16:05-03';
  c_d2    constant timestamptz := timestamptz '2027-01-08 16:05-03';
  c_d3    constant timestamptz := timestamptz '2027-01-11 16:05-03';
  c_ch    constant text := 'estimativa:rv:energia';
  r1      jsonb;
  r2      jsonb;
  r3      jsonb;
  v_a1    uuid;
  v_a2    uuid;
  v_txt   text;
  v_undo  jsonb;
  v_q     uuid;
  r       record;
begin
  begin
    update public.agenda_config set modo_aprendizado = 'ligado', modo_vies = 'ligado', gestor_so_propor = false where id;
    -- 1,00 → 1,30 → 1,45 em 2 rodadas (passo 0,30); depois nada
    r1 := pg_temp.grava('vies', c_ch, 'fina', 1.45, 6, 1, '{}'::jsonb, c_d1);
    v_a1 := (r1 ->> 'acao_id')::uuid;
    r2 := pg_temp.grava('vies', c_ch, 'fina', 1.45, 6, 1, '{}'::jsonb, c_d2);
    v_a2 := (r2 ->> 'acao_id')::uuid;
    r3 := pg_temp.grava('vies', c_ch, 'fina', 1.45, 6, 1, '{}'::jsonb, c_d3);
    v_res := pg_temp.ok(v_res, 'M6a 1,00 → 1,30 → 1,45 em 2 rodadas (passo fator_troca_max 0,30); na 3ª nada muda',
      r1 ->> 'estado' = 'em_uso' and (r1 ->> 'em_uso')::numeric = 1.30 and r2 ->> 'estado' = 'em_uso' and (r2 ->> 'em_uso')::numeric = 1.45
      and r3 ->> 'estado' = 'em_uso' and (r3 ->> 'em_uso')::numeric = 1.45 and r3 ->> 'acao_id' is null, format('%s / %s / %s', r1, r2, r3));
    v_res := pg_temp.ok(v_res, 'M6a2 o calculado guarda o alvo (1,45) e a coluna da linha é o passo', (select calculado = 1.45 and em_uso = 1.45 and estado = 'em_uso' from public.agenda_aprendizado where item = 'vies' and chave = c_ch), null);
    v_res := pg_temp.ok(v_res, 'M6b nunca pergunta: nenhuma pergunta da chave', not exists (select 1 from public.agenda_perguntas q where q.chave like 'aprendizado:vies:%'), null);
    v_res := pg_temp.ok(v_res, 'M6c a ação guarda o passo: antes.em_uso nulo e valor 1, depois.em_uso 1,30, depois.alvo 1,45, item, chave, nivel, estado (R7.5-19)',
      (select antes ->> 'item' = 'vies' and antes ->> 'chave' = c_ch and antes ->> 'nivel' = 'fina' and antes -> 'em_uso' = 'null' and (antes ->> 'valor')::numeric = 1 and antes ->> 'estado' = 'medindo'
              and (depois ->> 'em_uso')::numeric = 1.30 and (depois ->> 'alvo')::numeric = 1.45 and executada and tipo = 'aprendizado' from public.agenda_acoes where id = v_a1)
      and (select (antes ->> 'em_uso')::numeric = 1.30 and (depois ->> 'em_uso')::numeric = 1.45 from public.agenda_acoes where id = v_a2),
      (select antes::text || ' ' || depois::text from public.agenda_acoes where id = v_a1));
    -- as frases
    v_txt := (select texto from public.agenda_acoes where id = v_a1);
    v_res := pg_temp.ok(v_res, 'M6d o texto da ação, por passo: §6.3 ("Passei a marcar com 1,30× (era 1,00×) e subo até 1,45×")',
      v_txt = 'Aprendi com as OS concluídas: as OS de energia em motorhome levam 1,45× o que eu estimo pelo orçamento (6 OS). Passei a marcar com 1,30× (era 1,00×) e subo até 1,45× aos poucos, só nos serviços que eu ainda não marquei. *desfaz aprendizado* volta.', v_txt);
    v_txt := (select texto from public.agenda_acoes where id = v_a2);
    v_res := pg_temp.ok(v_res, 'M6d2 no alvo: §6.3 ("Passei a marcar os dias delas com 1,45× (era 1,30×)")',
      v_txt = 'Aprendi com as OS concluídas: as OS de energia em motorhome levam 1,45× o que eu estimo pelo orçamento (6 OS). Passei a marcar os dias delas com 1,45× (era 1,30×), só nos serviços que eu ainda não marquei. *desfaz aprendizado* volta.', v_txt);
    v_txt := (select texto from public.agenda_aprendizado where item = 'vies' and chave = c_ch);
    v_res := pg_temp.ok(v_res, 'M6d3 o foco, em uso no alvo: §6.2', v_txt = 'As OS de energia em motorhome levam 1,45× o que eu estimo pelo orçamento (6 OS medidas): marco os dias delas com 1,45× desde sex 08/01.', v_txt);
    -- M6e o *desfaz* (a frase do dono: agenda_desfazer_dito) volta um passo: 1,30, e o texto diz 1,30 (R7.5-19, 20)
    v_undo := public._agenda_desfazer_aprendizado(v_a2, null, 'dono', date '2027-01-09', timestamptz '2027-01-09 10:00-03');
    v_txt := (select texto from public.agenda_acoes where tipo = 'desfazer' order by criada_em desc, id desc limit 1);
    v_res := pg_temp.ok(v_res, 'M6e (M6b de R7.13) *desfaz* volta 1,30 e o texto diz 1,30, com a ressalva da OS marcada; volta um passo só (a 1ª ação segue)',
      (select em_uso = 1.30 and estado = 'travado' from public.agenda_aprendizado where item = 'vies' and chave = c_ch)
      and v_txt = 'Desfeito: as OS de energia em motorhome voltam a 1,30× o que sai do orçamento, só nas que eu ainda não marquei. Não troco de novo por 28 dias, salvo se o medido mudar muito.',
      format('%s | %s', v_undo, v_txt));
    -- a trava
    r1 := pg_temp.grava('vies', c_ch, 'fina', 1.50, 6, 1, '{}'::jsonb, timestamptz '2027-01-12 16:05-03');
    v_res := pg_temp.ok(v_res, 'M6f na trava, o medido andou até um passo do valor recusado (1,50 contra 1,45): fica travado, com o que vale', r1 ->> 'estado' = 'travado' and (r1 ->> 'vale')::numeric = 1.30, r1::text);
    r1 := pg_temp.grava('vies', c_ch, 'fina', 1.80, 6, 1, '{}'::jsonb, timestamptz '2027-01-13 16:05-03');
    v_res := pg_temp.ok(v_res, 'M6g o medido andou mais que um passo (1,80): sai da trava e anda um passo (1,30 → 1,60)', r1 ->> 'estado' = 'em_uso' and (r1 ->> 'em_uso')::numeric = 1.60, r1::text);
    -- sombra e medindo
    r1 := pg_temp.grava('vies', 'estimativa:todas', 'todas', 1.20, 0, 1, '{}'::jsonb, c_d1);
    v_res := pg_temp.ok(v_res, 'M6h poucas medidas (n abaixo do mínimo): medindo', r1 ->> 'estado' = 'medindo' and r1 -> 'em_uso' = 'null', r1::text);
    update public.agenda_config set modo_vies = 'sombra' where id;
    r1 := pg_temp.grava('vies', 'estimativa:rv:geral', 'fina', 1.20, 5, 1, '{}'::jsonb, c_d1);
    v_res := pg_temp.ok(v_res, 'M6i em sombra: sombra, em_uso nulo, sem ação', r1 ->> 'estado' = 'sombra' and r1 -> 'em_uso' = 'null' and r1 ->> 'acao_id' is null, r1::text);
    update public.agenda_config set modo_vies = 'ligado', modo_aprendizado = 'sombra' where id;
    r1 := pg_temp.grava('vies', 'estimativa:rv:geral', 'fina', 1.20, 5, 1, '{}'::jsonb, c_d1);
    v_res := pg_temp.ok(v_res, 'M6i2 modo_aprendizado fora de ligado: sombra', r1 ->> 'estado' = 'sombra', r1::text);
    update public.agenda_config set modo_aprendizado = 'ligado', gestor_so_propor = true where id;
    r1 := pg_temp.grava('vies', 'estimativa:todas', 'todas', 1.20, 5, 1, '{}'::jsonb, c_d1);
    v_res := pg_temp.ok(v_res, 'M6j o freio não entra no gravador (R7.6): ligado + freio = em_uso (sombra pelo efetivo, nunca aqui)', r1 ->> 'estado' = 'em_uso' and (r1 ->> 'em_uso')::numeric = 1.20, r1::text);
    update public.agenda_config set gestor_so_propor = false where id;
    -- o dono
    update public.agenda_config set vies_corrige_dono = false where id;
    r1 := pg_temp.grava('vies', 'dono:todas', 'todas', 1.20, 3, 1, '{}'::jsonb, c_d1);
    v_res := pg_temp.ok(v_res, 'M6k sem vies_corrige_dono, a chave dono: fica em teste', r1 ->> 'estado' = 'sombra', r1::text);
    update public.agenda_config set vies_corrige_dono = true where id;
    r1 := pg_temp.grava('vies', 'dono:todas', 'todas', 1.20, 3, 1, '{}'::jsonb, c_d1);
    v_res := pg_temp.ok(v_res, 'M6k2 com vies_corrige_dono (o padrão), a chave dono: anda', r1 ->> 'estado' = 'em_uso', r1::text);
    -- os que nunca entram em uso
    update public.agenda_config set modo_promessa = 'ligado', modo_folga_compra = 'ligado', modo_tempo_compra = 'ligado', modo_folga_semana = 'ligado', vies_corrige_dono = true where id;
    r1 := pg_temp.grava('promessa', 'todas', 'todas', 1.40, 8, 1.5, '{}'::jsonb, c_d1);
    v_res := pg_temp.ok(v_res, 'M6l a promessa nunca em uso, nem com o interruptor ligado (AG7-32)', r1 ->> 'estado' = 'sombra', r1::text);
    r1 := pg_temp.grava('folga_compra', 'todas', 'geral', 2, 5, 0, '{}'::jsonb, c_d1);
    v_res := pg_temp.ok(v_res, 'M6m a folga da compra nunca em uso nesta etapa (R7.5-16: sem leitor)', r1 ->> 'estado' = 'sombra', r1::text);
    r1 := pg_temp.grava('prazo_sem_fornecedor', 'todas', 'geral', 5, 3, 7, '{}'::jsonb, c_d1);
    v_res := pg_temp.ok(v_res, 'M6n a peça sem fornecedor é só medida', r1 ->> 'estado' = 'sombra', r1::text);
    -- o arredondamento e o passo de cada item
    r1 := pg_temp.grava('folga_semana', 'equipe', 'geral', 0.08, 8, 0.15, '{}'::jsonb, c_d1);
    v_res := pg_temp.ok(v_res, 'M6o a folga da semana anda 0,05 por rodada, 2 casas: 0,15 → 0,10 (alvo 0,08)', r1 ->> 'estado' = 'em_uso' and (r1 ->> 'em_uso')::numeric = 0.10 and (select calculado = 0.08 from public.agenda_aprendizado where item = 'folga_semana' and chave = 'equipe'), r1::text);
    r1 := pg_temp.grava('tempo_compra', 'todas', 'geral', 2.2, 4, 1, '{}'::jsonb, c_d1);
    v_res := pg_temp.ok(v_res, 'M6p o tempo de compra é inteiro: 1 + 1,2 = 2,2 → 2', r1 ->> 'estado' = 'em_uso' and (r1 ->> 'em_uso')::numeric = 2, r1::text);
    r1 := pg_temp.grava('tempo_compra', 'todas', 'geral', 9, 4, 1, '{}'::jsonb, c_d2);
    v_res := pg_temp.ok(v_res, 'M6p2 passo em dias: fornecedor_troca_max_du (3): 2 → 5 (alvo 9)', (r1 ->> 'em_uso')::numeric = 5, r1::text);
    -- a pergunta aberta (que não deveria existir) sai
    insert into public.agenda_perguntas (tipo, chave, dia, texto, opcoes, recomendacao, modo, criada_em)
    values ('aprendizado', 'aprendizado:vies:dono:rv:energia', date '2027-01-07', 'Pergunta de teste da margem, ainda aberta.', '[{"n":1,"texto":"a","efeito":{}},{"n":2,"texto":"b","efeito":{}}]'::jsonb, 1, 'ligado', c_d1) returning id into v_q;
    insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, calculado, em_uso, estado, calculado_em, pergunta_id)
    values ('vies', 'dono:rv:energia', 'fina', 1, 1, 2, 1.1, null, 'pergunta', c_d1, v_q);
    r1 := pg_temp.grava('vies', 'dono:rv:energia', 'fina', 1.1, 2, 1, '{}'::jsonb, c_d1);
    v_res := pg_temp.ok(v_res, 'M6q a pergunta aberta da chave da margem sai ("anda aos poucos")', (select estado = 'resolvida' and resolvida_motivo = 'O aprendizado agora anda aos poucos, sem pergunta.' from public.agenda_perguntas where id = v_q), null);
    -- item desconhecido continua recusado (urgencia não é item que se aprende)
    v_res := pg_temp.ok(v_res, 'M6r urgencia não é item que se grave: 22023', pg_temp.erro($q$select public._agenda_aprendizado_gravar('urgencia', 'x', 'geral', 1, 1, '[]'::jsonb, 1, '{}'::jsonb, now())$q$) like 'erro 22023%', pg_temp.erro($q$select public._agenda_aprendizado_gravar('urgencia', 'x', 'geral', 1, 1, '[]'::jsonb, 1, '{}'::jsonb, now())$q$));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$m6$;

-- M6s: os textos de §6.2/§6.3, com R7.3 (byte a byte; cada um a partir do p_d, sem passar pelo gravador)
do $m6s$
declare
  v_res jsonb := '[]'::jsonb;
  c     constant jsonb := '{"n_min": 1, "desde": "2027-01-07", "travado_ate": "2027-02-04", "trava_dias": 28, "padrao": 1, "detalhe": {}, "passo": 0.3}';
  t     text;
begin
  t := public._agenda_aprendizado_texto('vies', 'foco_medindo', c || '{"chave": "estimativa:todas", "n": 0}');
  v_res := pg_temp.ok(v_res, 'M6s1 n = 0 diz nenhuma ainda (nunca "medi")', t = 'Estimativa pelo valor: nenhuma OS medida ainda; marco os dias como saem do orçamento.', t);
  t := public._agenda_aprendizado_texto('vies', 'foco_sombra', c || '{"chave": "estimativa:todas", "n": 8, "calculado": 1.11}');
  v_res := pg_temp.ok(v_res, 'M6s2 em teste, o geral', t = 'Em teste: as OS levam 1,11× o que eu estimo pelo orçamento (8 OS medidas). Hoje marco os dias como saem do orçamento.', t);
  t := public._agenda_aprendizado_texto('vies', 'foco_sombra', c || '{"chave": "estimativa:rv:energia", "n": 4, "calculado": 1.17}');
  v_res := pg_temp.ok(v_res, 'M6s3 em teste, a classe', t = 'Em teste: as OS de energia em motorhome levam 1,17× o que eu estimo pelo orçamento (4 OS medidas; junto com o geral das OS). Hoje marco os dias como saem do orçamento.', t);
  t := public._agenda_aprendizado_texto('vies', 'foco_em_uso', c || '{"chave": "estimativa:rv:energia", "n": 6, "calculado": 1.45, "em_uso": 1.3}');
  v_res := pg_temp.ok(v_res, 'M6s4 em uso, a caminho', t = 'As OS de energia em motorhome levam 1,45× o que eu estimo pelo orçamento (6 OS medidas): marco com 1,30× desde qui 07/01 e chego a 1,45× aos poucos (até 0,3× por dia).', t);
  t := public._agenda_aprendizado_texto('vies', 'foco_travado', c || '{"chave": "estimativa:rv:energia", "n": 4, "calculado": 1.17, "efetivo": 1}');
  v_res := pg_temp.ok(v_res, 'M6s5 travado', t = 'As OS de energia em motorhome levam 1,17× o que eu estimo pelo orçamento (4 OS medidas); fico com 1,00× até qui 04/02, como você decidiu.', t);
  t := public._agenda_aprendizado_texto('vies', 'acao', c || '{"chave": "estimativa:rv:geral", "n": 3, "calculado": 0.99, "em_uso": 0.99, "efetivo": 1}');
  v_res := pg_temp.ok(v_res, 'M6s6 abaixo de 1: "marcar os dias delas com 0,99×"', t = 'Aprendi com as OS concluídas: as OS de outros serviços em motorhome levam 0,99× o que eu estimo pelo orçamento (3 OS). Passei a marcar os dias delas com 0,99× (era 1,00×), só nos serviços que eu ainda não marquei. *desfaz aprendizado* volta.', t);
  t := public._agenda_aprendizado_texto('vies', 'acao', c || '{"chave": "estimativa:todas", "n": 6, "calculado": 0.7, "em_uso": 1.0, "efetivo": 1.3}');
  v_res := pg_temp.ok(v_res, 'M6s7 por passo para baixo: "desço até"', t like '%Passei a marcar com 1,00× (era 1,30×) e desço até 0,70× aos poucos%', t);
  t := public._agenda_aprendizado_texto('vies', 'foco_sombra', c || '{"chave": "dono:todas", "n": 5, "calculado": 1.08}');
  v_res := pg_temp.ok(v_res, 'M6s8 o dono em teste, sem "nos seus dias eu não mexo" (R7.3-2)', t = 'Em teste: nos dias que você diz, as OS levam 1,08× o que você combinou (5 OS medidas). Hoje conto os seus dias como você disse.' and t not like '%não mexo%', t);
  t := public._agenda_aprendizado_texto('vies', 'acao', c || '{"chave": "dono:rv:energia", "n": 5, "calculado": 1.2, "em_uso": 1.2, "efetivo": 1}');
  v_res := pg_temp.ok(v_res, 'M6s9 o dono em uso diz os dois números (R7.3-2)', t = 'Aprendi com as OS concluídas: nos dias que você diz, as OS levam 1,20× o que você combinou (5 OS). Passei a contar os seus dias com 1,20× (era 1,00×), sempre dizendo os dois números, só nos serviços que eu ainda não marquei. *desfaz aprendizado* volta.', t);
  t := public._agenda_aprendizado_texto('vies', 'desfeito', c || '{"chave": "dono:todas", "n": 5, "volta": 1.1}');
  v_res := pg_temp.ok(v_res, 'M6s10 desfeito do dono', t = 'Desfeito: os seus dias voltam a 1,10×, só nos serviços que eu ainda não marquei. Não troco de novo por 28 dias, salvo se o medido mudar muito.', t);
  -- folga da semana
  t := public._agenda_aprendizado_texto('folga_semana', 'foco_medindo', c || '{"chave": "equipe", "n": 3, "n_min": 8, "padrao": 0.15, "carga_max": 0.8}');
  v_res := pg_temp.ok(v_res, 'M6s11 folga, medindo, com os 3 números', t = 'Folga da semana: 3 de 8 semanas com serviço marcado medidas; guardo 20% da semana da equipe (15% para o serviço que passa do previsto e 5% para urgência e falta).', t);
  t := public._agenda_aprendizado_texto('folga_semana', 'foco_medindo', c || '{"chave": "equipe", "n": 0, "n_min": 8, "padrao": 0.15, "carga_max": 0.8}');
  v_res := pg_temp.ok(v_res, 'M6s11b folga, n = 0 diz nenhuma', t = 'Folga da semana: nenhuma semana com serviço marcado medida ainda; guardo 20% da semana da equipe (15% para o serviço que passa do previsto e 5% para urgência e falta).', t);
  t := public._agenda_aprendizado_texto('folga_semana', 'foco_sombra', c || '{"chave": "equipe", "n": 8, "padrao": 0.15, "calculado": 0.11}');
  v_res := pg_temp.ok(v_res, 'M6s12 folga, em teste', t = 'Em teste: pelo quanto as OS variaram em 8 semanas, 11% da semana bastariam para o serviço que passa do previsto; hoje guardo 15%.', t);
  t := public._agenda_aprendizado_texto('folga_semana', 'foco_em_uso', c || '{"chave": "equipe", "n": 8, "padrao": 0.15, "calculado": 0.11, "em_uso": 0.11}');
  v_res := pg_temp.ok(v_res, 'M6s13 folga, em uso', t = 'Pelo quanto as OS variaram em 8 semanas, guardo 11% da semana para o serviço que passa do previsto desde qui 07/01 (era 15%).', t);
  t := public._agenda_aprendizado_texto('folga_semana', 'acao', c || '{"chave": "equipe", "n": 8, "padrao": 0.15, "calculado": 0.11, "em_uso": 0.11, "efetivo": 0.15, "detalhe": {"proxima_semana": "na semana de 11/01 marco até 74% da semana da equipe (com a temporada de barco)"}}');
  v_res := pg_temp.ok(v_res, 'M6s14 folga, a ação com a semana que vem (§6.3)', t = 'Medi 8 semanas de serviço marcado: as OS variaram menos do que eu contava. Passei a guardar 11% da semana para o serviço que passa do previsto (era 15%): na semana de 11/01 marco até 74% da semana da equipe (com a temporada de barco). *desfaz aprendizado* volta.', t);
  t := public._agenda_aprendizado_texto('folga_semana', 'desfeito', c || '{"chave": "equipe", "volta": 0.15}');
  v_res := pg_temp.ok(v_res, 'M6s15 folga, desfeito', t = 'Desfeito: volto a guardar 15% da semana para o serviço que passa do previsto. Não troco de novo por 28 dias, salvo se o medido mudar muito.', t);
  -- promessa (R7.3-1)
  t := public._agenda_aprendizado_texto('promessa', 'foco_medindo', c || '{"chave": "todas", "n": 0}');
  v_res := pg_temp.ok(v_res, 'M6s16 prazo real, nenhuma', t = 'Prazo real: nenhuma OS medida ainda. Só para você: ao cliente não digo data de pronto.', t);
  t := public._agenda_aprendizado_texto('promessa', 'foco_sombra', c || '{"chave": "todas", "n": 8, "calculado": 1.4, "fator_percentil": 0.8, "detalhe": {"p80": 1.34}}');
  v_res := pg_temp.ok(v_res, 'M6s17 prazo real, 8 OS (R7.3-1)', t = 'Prazo real: 8 em cada 10 OS terminaram em até 1,34× os dias planejados (8 OS). Com essa folga, um serviço de 5 dias acaba em até 7 dias úteis. Só para você: ao cliente não digo data de pronto.', t);
  -- tempo de compra (R7.3-5: o padrão é 1)
  t := public._agenda_aprendizado_texto('tempo_compra', 'foco_medindo', c || '{"chave": "todas", "n": 1, "n_min": 3, "padrao": 1}');
  v_res := pg_temp.ok(v_res, 'M6s18 tempo, medindo', t = 'Seu tempo para comprar: 1 de 3 OS medidas (da aprovação até a compra); no "compre até" conto 1 dia útil (padrão).', t);
  t := public._agenda_aprendizado_texto('tempo_compra', 'foco_medindo', c || '{"chave": "todas", "n": 0, "n_min": 3, "padrao": 1}');
  v_res := pg_temp.ok(v_res, 'M6s18b tempo, n = 0', t = 'Seu tempo para comprar: nenhuma OS medida ainda (da aprovação até a compra); no "compre até" conto 1 dia útil (padrão).', t);
  t := public._agenda_aprendizado_texto('tempo_compra', 'foco_sombra', c || '{"chave": "todas", "n": 4, "padrao": 1, "calculado": 2, "detalhe": {"percentil": 4}}');
  v_res := pg_temp.ok(v_res, 'M6s19 tempo, em teste (R7.3-5)', t = 'Em teste: da aprovação até a compra você levou 4 dias úteis (o do meio de 4 OS); junto com o padrão de 1, eu contaria 2 dias úteis no "compre até". Hoje conto 1.', t);
  t := public._agenda_aprendizado_texto('tempo_compra', 'foco_em_uso', c || '{"chave": "todas", "n": 4, "padrao": 1, "calculado": 2, "em_uso": 2}');
  v_res := pg_temp.ok(v_res, 'M6s20 tempo, em uso', t = 'Da aprovação até a compra você leva por volta de 2 dias úteis (4 OS medidas): é o que conto no "compre até" desde qui 07/01.', t);
  t := public._agenda_aprendizado_texto('tempo_compra', 'acao', c || '{"chave": "todas", "n": 4, "padrao": 1, "calculado": 2, "em_uso": 2, "efetivo": 1}');
  v_res := pg_temp.ok(v_res, 'M6s21 tempo, a ação (R7.3-5)', t = 'Medi o seu tempo da aprovação até a compra (4 OS): passei a contar 2 dias úteis no "compre até" (era 1), só nas OS que eu ainda não marquei: o pedido de compra sai 1 dia útil mais cedo. *desfaz aprendizado* volta.', t);
  t := public._agenda_aprendizado_texto('tempo_compra', 'desfeito', c || '{"chave": "todas", "volta": 1}');
  v_res := pg_temp.ok(v_res, 'M6s22 tempo, desfeito com a ressalva', t = 'Desfeito: volto a contar 1 dia útil no "compre até", só nas OS que eu ainda não marquei. Não troco de novo por 28 dias, salvo se o medido mudar muito.', t);
  -- folga da compra
  t := public._agenda_aprendizado_texto('folga_compra', 'foco_medindo', c || '{"chave": "todas", "n": 1, "n_min": 3, "folga_material_du": 1}');
  v_res := pg_temp.ok(v_res, 'M6s23 folga da compra, medindo', t = 'OS marcadas antes da compra: 1 de 3 medidas; dou 1 dia útil entre a chegada da peça e o 1º dia, como em todas.', t);
  t := public._agenda_aprendizado_texto('folga_compra', 'foco_sombra', c || '{"chave": "todas", "n": 5, "calculado": 2, "detalhe": {"maior": 4, "no_prazo": 2, "comecaram_no_dia": 3}}');
  v_res := pg_temp.ok(v_res, 'M6s24 folga da compra, em teste', t = 'Em teste: nas OS marcadas antes da compra, a peça chegou até 4 dias úteis depois do que eu contava (5 OS; 2 no prazo; 3 começaram no dia marcado); eu daria 2 dias úteis a mais só a elas. Hoje não dou.', t);
  -- peça sem fornecedor (R7.3-5: conta 7)
  t := public._agenda_aprendizado_texto('prazo_sem_fornecedor', 'foco_medindo', c || '{"chave": "todas", "n": 1, "n_min": 3, "padrao": 7}');
  v_res := pg_temp.ok(v_res, 'M6s25 sem fornecedor, medindo (R7.3-5: conta 7)', t = 'Peças compradas sem fornecedor dito antes: 1 de 3 compras medidas; conto 7 dias úteis (padrão).', t);
  t := public._agenda_aprendizado_texto('prazo_sem_fornecedor', 'foco_sombra', c || '{"chave": "todas", "n": 3, "padrao": 7, "calculado": 5}');
  v_res := pg_temp.ok(v_res, 'M6s26 sem fornecedor, só medida', t = 'Peças compradas sem fornecedor dito antes: chegaram em até 5 dias úteis depois da compra (3 compras); conto 7 dias úteis (o padrão é decisão sua).', t);
  -- o valor
  v_res := pg_temp.ok(v_res, 'M6s27 o valor: 1,17× / 1,30× com 2 casas; 11%; 1 dia útil, 5 dias úteis',
    public._agenda_aprendizado_valor('vies', 1.17) = '1,17×' and public._agenda_aprendizado_valor('promessa', 1.3) = '1,30×' and public._agenda_aprendizado_valor('folga_semana', 0.11) = '11%'
    and public._agenda_aprendizado_valor('tempo_compra', 1) = '1 dia útil' and public._agenda_aprendizado_valor('prazo_sem_fornecedor', 5) = '5 dias úteis', null);
  v_res := pg_temp.ok(v_res, 'M6s28 nenhum jargão nos textos (a varredura confere o texto antes)',
    (select bool_and(length(x) > 0 and x !~* 'viés|dispers|percentil|mediana|credibilidade|amostra|\mdu\M') from (
       select public._agenda_aprendizado_texto('vies', 'foco_sombra', c || '{"chave": "estimativa:todas", "n": 8, "calculado": 1.11}') x
       union all select public._agenda_aprendizado_texto('tempo_compra', 'foco_sombra', c || '{"chave": "todas", "n": 4, "padrao": 1, "calculado": 2, "detalhe": {"percentil": 4}}')
       union all select public._agenda_aprendizado_texto('folga_semana', 'foco_em_uso', c || '{"chave": "equipe", "n": 8, "padrao": 0.15, "calculado": 0.11, "em_uso": 0.11}')) t)
    and 'o viés' ~* 'viés', null);
  perform pg_temp.gravar(v_res);
end
$m6s$;

-- ── M7. O leitor da margem ───────────────────────────────────────────────────────────────────────────
do $m7$
declare
  v_res jsonb := '[]'::jsonb;
  r     record;
  v_dif text;
  v_got numeric;
  v_x   uuid;
begin
  begin
    insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, calculado, em_uso, estado, calculado_em)
    values ('vies', 'estimativa:todas', 'todas', 1, 1, 5, 1.20, 1.20, 'em_uso', now()), ('vies', 'dono:todas', 'todas', 1, 1, 5, 1.10, 1.10, 'em_uso', now());
    update public.agenda_config set gestor_so_propor = false, vies_corrige_dono = true where id;
    for r in select ap, m from unnest(array['desligado','sombra','ligado']) ap, unnest(array['desligado','sombra','ligado']) m loop
      update public.agenda_config set modo_aprendizado = r.ap, modo_vies = r.m where id;
      v_got := public._agenda_margem_em_uso('vies', 'estimativa:todas');
      if (r.ap = 'ligado' and r.m = 'ligado') then
        if v_got is distinct from 1.20 then v_dif := coalesce(v_dif, '') || format('[%s/%s: %s] ', r.ap, r.m, v_got); end if;
      elsif v_got is not null then
        v_dif := coalesce(v_dif, '') || format('[%s/%s: %s] ', r.ap, r.m, v_got);
      end if;
    end loop;
    v_res := pg_temp.ok(v_res, 'M7a as 9 combinações de modo_aprendizado × modo_vies: só ligado × ligado dá o valor', v_dif is null, v_dif);
    update public.agenda_config set modo_aprendizado = 'ligado', modo_vies = 'ligado', gestor_so_propor = true where id;
    v_res := pg_temp.ok(v_res, 'M7b o freio apaga o leitor (R7.6: ligado + freio = sombra pelo efetivo)', public._agenda_margem_em_uso('vies', 'estimativa:todas') is null, null);
    update public.agenda_config set gestor_so_propor = false where id;
    v_res := pg_temp.ok(v_res, 'M7c dono: com vies_corrige_dono, o valor; sem ele, nulo', public._agenda_margem_em_uso('vies', 'dono:todas') = 1.10, null);
    update public.agenda_config set vies_corrige_dono = false where id;
    v_res := pg_temp.ok(v_res, 'M7c2 sem vies_corrige_dono, a chave dono: não vale', public._agenda_margem_em_uso('vies', 'dono:todas') is null, null);
    update public.agenda_config set vies_corrige_dono = true, modo_promessa = 'ligado', gestor_so_propor = false where id;
    insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, calculado, em_uso, estado, calculado_em)
    values ('promessa', 'todas', 'todas', 1.5, 1, 5, 1.4, 1.4, 'em_uso', now());
    v_res := pg_temp.ok(v_res, 'M7d promessa nunca vale pelo leitor, nem com o modo ligado (AG7-32)', public._agenda_margem_em_uso('promessa', 'todas') is null, null);
    v_res := pg_temp.ok(v_res, 'M7e _agenda_aprendido segue nula para os itens da margem (nenhum está na lista: não foi recriada, R7.5-7)', public._agenda_aprendido('vies', 'estimativa:todas') is null, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$m7$;

do $m7b$
declare
  v_res jsonb := '[]'::jsonb;
  v_x   uuid;
  v_t   int;
  v     jsonb;
begin
  if not pg_temp.fx() then return; end if;
  begin
    -- OS sem linha em os_planejamento: o caso comum (R7.12-3)
    v_x := pg_temp.nova_os(71, date '2026-06-01', date '2026-06-01', 764);
    update public.agenda_config set modo_tempo_compra = 'desligado', compra_interna_du = 2, gestor_so_propor = false where id;
    v_t := public._agenda_tempo_interno_compra(v_x);
    v_res := pg_temp.ok(v_res, 'M7f tempo interno sem linha em os_planejamento: o parâmetro (nunca nulo)', v_t = 2, format('%s', v_t));
    update public.agenda_config set modo_tempo_compra = 'ligado', modo_aprendizado = 'ligado' where id;
    insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, calculado, em_uso, estado, calculado_em)
    values ('tempo_compra', 'todas', 'geral', 2, 3, 5, 4, 4, 'em_uso', now());
    v_t := public._agenda_tempo_interno_compra(v_x);
    v_res := pg_temp.ok(v_res, 'M7g com o modo ligado, o em uso', v_t = 4, format('%s', v_t));
    update public.agenda_config set gestor_so_propor = true where id;
    v_t := public._agenda_tempo_interno_compra(v_x);
    v_res := pg_temp.ok(v_res, 'M7g2 o freio volta ao parâmetro', v_t = 2, format('%s', v_t));
    update public.agenda_config set gestor_so_propor = false where id;
    insert into public.os_planejamento (service_order_id, marcado_em, tempo_compra_marcado, vies_marcado, folga_compra_marcada) values (v_x, date '2026-05-20', 7, 1, 0);
    v_t := public._agenda_tempo_interno_compra(v_x);
    v_res := pg_temp.ok(v_res, 'M7h com o congelado na marcação, vale o congelado', v_t = 7, format('%s', v_t));
    -- o viés da OS
    v := public._agenda_vies_da_os(pg_temp.os('E1'));
    v_res := pg_temp.ok(v_res, 'M7i _agenda_vies_da_os sem nada em uso: nulo no em uso e chave nula', v -> 'vies_em_uso' = 'null' and v -> 'chave' = 'null' and v ? 'teria', v::text);
    update public.agenda_config set modo_aprendizado = 'ligado', modo_vies = 'ligado' where id;
    insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, calculado, em_uso, estado, calculado_em)
    values ('vies', 'estimativa:rv:energia', 'fina', 1, 1, 4, 1.17, 1.17, 'em_uso', now());
    v := public._agenda_vies_da_os(pg_temp.os('E1'));
    v_res := pg_temp.ok(v_res, 'M7j a fina vale antes do geral; chave = a que deu o valor', (v ->> 'vies_em_uso')::numeric = 1.17 and v ->> 'chave' = 'estimativa:rv:energia' and (v ->> 'teria')::numeric = 1.17, v::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$m7b$;

-- ── M8. As cópias e o que não foi recriado ───────────────────────────────────────────────────────────
do $m8$
declare
  v_res jsonb := '[]'::jsonb;
  v_m   text := coalesce(current_setting('agenda_teste.mig_medicao_fase7e', true), '');
  v_f   text;
  v_sem text;
  v_o   text;
begin
  if v_m = '' then
    perform pg_temp.gravar(pg_temp.ok('[]', 'M8 as cópias', true, 'PULADO: sem a migration como texto (rode pela bancada)'));
    return;
  end if;
  v_res := pg_temp.ok(v_res, 'M8a _agenda_aprendido NÃO é recriada (R7.5-7), nem nenhum dos que R7.1 proíbe', v_m !~ 'create or replace function public\._agenda_aprendido\(' and v_m !~ 'function public\.agenda_aprender\(', null);
  v_f := replace((select prosrc from pg_proc where oid = 'public._agenda_aprendido(text, text)'::regprocedure), E'\r\n', E'\n');
  v_res := pg_temp.ok(v_res, 'M7 (md5) o corpo de _agenda_aprendido é o da Fase 6, byte a byte (R7.13)', md5(v_f) = '5f9a7356a011c30cb8ed041e813a907d', md5(v_f));
  perform pg_temp.gravar(v_res);
end
$m8$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
