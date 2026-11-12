-- Prova do *livre* de 4 semanas e do "se aprovar hoje" pelo encaixe, Fase 7g (pacote P4; migration 20261112100300; spec-fase7g §5.4, §6.3, §8.3
-- agenda_fase7g_livre.sql e o bloco R9: R9.3-2 (AG7-32), R9.4-6, R9.5-28, R9.7, R9.8, R9.12, R9.13 — "L4 só pelo texto; L6 (AG7-32); L7 o ctp com login de admin").
-- bancada: depende de 20261112100300
--
-- Os cenários:
--   H  o de hoje do teste do P2 do lote (agenda_correcao_2910_p2.sql): a fixture-2310 com a vigia de qui 29/10 às 16:30 (só a reserva do Lenine, João e Roberto),
--      e a OS-00901 (Daniel: 2 dias com o Roberto, você abre e fecha, sinal pago) do H16 de lá
--   M  o do motor (cenario-motor.sql, o mesmo do C10 de agenda_fase7g_como_pensei.sql): a semana de 02/11 com A, B e C, a folga contada à mão no P3
--
--   L0  o catálogo: as 2 novas (definer, STABLE, search_path) e as portas (authenticated e service_role, nunca anon); as 3 recriadas com as portas de antes
--   L1  o *livre*: desligado = a de antes (20261101100800) byte a byte; em sombra = a de antes + dados.teste; ligado: livre_semanas semanas, as 3 primeiras com os
--       MESMOS meios-dias de cada pessoa que a de antes, a linha curta igual, os totais (pode, marcado, reservado, livre) contra a grade do motor e a folga contra
--       a de agenda_como_pensei nos 2 ramos (com e sem a regra teto_equipe) e contra a conta à mão; o texto do §6.3
--   L2  o 1º dia do encaixe da OS (_agenda_entrada_simulada_da_os + _agenda_encaixe_simulado) = o da agenda_propor('os', aplicar = false) para ela, sem e com
--       compra pendente (as mesmas fontes); a entrada (passos, gente, dono, nao_antes_de)
--   L3  agenda_encaixe_do_novo = a de antes (20261031100980) byte a byte, nos 3 modos, nos 6 casos do P2 do lote e mais 4; o simulado com a mesma entrada também;
--       com passos e nao_antes_de, outra resposta (o controle que morde)
--   L4  com modo_explicar ligado, nenhuma saída da agenda_ver (livre, semana, semana que vem, simular, ctp) diz "fim da fila", "Pela fila" nem "Livre ela não está"
--       (só pelo texto, R9.4-6); com contraste (desligado diz "Pela fila") e com texto plantado
--   L5  o ctp: desligado = a de antes (20261024160500) byte a byte; em sombra = a de antes + dados.teste {de, ate, texto}; a OS aprovada diz o estado; sem base
--       pede os dias; o texto ligado inteiro
--   L6  AG7-32: a frase depois de "Para o cliente:" não diz pronto, termina, até nem a data de fim; com texto plantado que reprova
--   L7  o ctp com login: o admin lê (ligado), o técnico leva 42501 (ligado); o service_role lê
--   L8  as cópias: as 3 recriadas, tiradas os blocos -- FASE 7g, são as da origem (md5 do R9.1); o simulado é o corpo de agenda_encaixe_do_novo; a migration só
--       cria as 2 novas e recria só as 3
--   L9  o peso: desligado, o ctp não chama a entrada nem o simulado; em sombra, 1 vez cada
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado: npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7g_livre.sql
--   Seguro em produção: termina em ROLLBACK. O que usa o cenário, a fixture ou as migrations como texto só roda na bancada (fora dela sai PULADO).
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

set local timezone = 'UTC';

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;
create function pg_temp.igual(p_res jsonb, p_nome text, p_visto text, p_esperado text) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, p_visto is not distinct from p_esperado,
           case when p_visto is distinct from p_esperado then 'veio: ' || coalesce(p_visto, '(null)') end))
$f$;
create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;
create function pg_temp.modo(p_m text) returns void language sql as $f$
  update public.agenda_config set modo_explicar = p_m where id
$f$;
create function pg_temp.vigiar(p_dia date, p_hora text) returns jsonb language sql as $f$
  select public.agenda_vigiar(p_dia, (p_dia + p_hora::time) at time zone 'America/Sao_Paulo')
$f$;
create function pg_temp.agora(p_dia date, p_hora text) returns void language sql as $f$
  select set_config('agenda.agora', ((p_dia + p_hora::time) at time zone 'America/Sao_Paulo')::text, true)
$f$;
-- A agenda_ver do dono pelo WhatsApp (service_role, sem login), como a palavra a chama.
create function pg_temp.ver(p_foco text, p_periodo text, p_hoje date) returns text language sql as $f$
  select public.agenda_ver('aa000000-0000-4000-8000-000000000001', p_periodo, null, p_foco, null, null, false, p_hoje) ->> 'texto'
$f$;
create function pg_temp.sim(p_simular jsonb, p_hoje date) returns text language sql as $f$
  select public.agenda_ver('aa000000-0000-4000-8000-000000000001', null, null, null, null, p_simular, false, p_hoje) ->> 'texto'
$f$;
create function pg_temp.se_aprovar(p_os text, p_hoje date) returns text language sql as $f$
  select public.agenda_ver('aa000000-0000-4000-8000-000000000001', null, null, null, p_os, null, true, p_hoje) ->> 'texto'
$f$;
-- Nenhum dos 3 textos da projeção da Fase 1 (R9.4-6, L4): falso também com texto nulo ou vazio (R9.12-4)
create function pg_temp.sem_fila(p_t text) returns boolean language sql immutable as $f$
  select coalesce(length(p_t) > 0 and position('fim da fila' in p_t) = 0 and position('Pela fila' in p_t) = 0 and position('Livre ela não está' in p_t) = 0, false)
$f$;
-- AG7-32 (L6): a frase depois de "Para o cliente:" existe, não diz pronto, termina nem até, e não traz a data de fim (DD/MM) — falso também sem a frase
create function pg_temp.sem_fim(p_t text, p_fim date) returns boolean language sql immutable as $f$
  select coalesce(length(x.f) > 0 and x.f !~* '(pronto|pronta|termina|até)' and (p_fim is null or position(to_char(p_fim, 'DD/MM') in x.f) = 0), false)
    from (select substring(p_t from 'Para o cliente: (.*)$') as f) x
$f$;
-- Uma consulta como um papel (e um login): o texto que volta ou "erro <sqlstate>: <mensagem>".
create function pg_temp.como(p_uid uuid, p_papel text, p_sql text) returns text language plpgsql as $f$
declare
  v text;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('request.jwt.claims',
    case when p_uid is null then json_build_object('role', p_papel)::text
         else json_build_object('sub', p_uid, 'role', p_papel)::text end, true);
  begin
    execute format('set local role %I', p_papel);
    execute p_sql into v;
    reset role;
  exception when others then
    v := 'erro ' || sqlstate || ': ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;
-- A função inteira (do "create or replace" ao fecho) de p_nome na migration p_mig, e o corpo (prosrc) sem os blocos -- FASE 7g: (7g P4 … -- FASE 7g: fim.
create function pg_temp.inteira(p_mig text, p_nome text) returns text language plpgsql immutable as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  if position(format('create or replace function public.%s(', p_nome) in v) = 0 then return null; end if;
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  return left(v, position(E'\n$function$;' in v) + length(E'\n$function$;') - 1);
end $f$;
create function pg_temp.sem7g(p text) returns text language plpgsql immutable as $f$
declare
  v_fora text[] := '{}';
  v_den  boolean := false;
  x      text;
begin
  foreach x in array string_to_array(replace(p, chr(13), ''), E'\n') loop
    if not v_den and x ~ '^\s*-- FASE 7g: \(7g P4' then v_den := true; continue; end if;
    if v_den and x ~ '^\s*-- FASE 7g: fim' then v_den := false; continue; end if;
    continue when v_den;
    v_fora := v_fora || x;
  end loop;
  return array_to_string(v_fora, E'\n');
end $f$;
create function pg_temp.chamadas(p_nome text) returns bigint language sql as $f$
  select coalesce(sum(f.calls), 0)::bigint from pg_stat_xact_user_functions f where f.schemaname = 'public' and f.funcname = p_nome
$f$;
-- O 1º dia (e os dias) que a agenda_propor('os', aplicar = false) daria à OS: o item criar dela
create function pg_temp.dias_do_motor(p_os uuid, p_hoje date) returns text language plpgsql as $f$
declare
  r jsonb := public.agenda_propor('os', null, null, array[p_os], '{}'::jsonb, false, 'motor', null, p_hoje, (p_hoje + time '17:40') at time zone 'America/Sao_Paulo');
begin
  return (select string_agg(distinct a ->> 'dia', ',' order by a ->> 'dia')
            from jsonb_array_elements(r -> 'itens') i, jsonb_array_elements(i -> 'alocacoes') a
           where i ->> 'op' = 'criar' and (i ->> 'os')::uuid = p_os);
end $f$;
create function pg_temp.dias_do_encaixe(p_os uuid, p_hoje date) returns text language sql as $f$
  select string_agg(d, ',' order by d) from jsonb_array_elements_text(
    public._agenda_encaixe_simulado(public._agenda_entrada_simulada_da_os(p_os, p_hoje), p_hoje) -> 'dias') d
$f$;

-- As definições de ANTES (as origens da cópia), rodadas como pg_temp: a régua do que não muda fora de ligado.
do $antes$
declare
  v_7a text := coalesce(current_setting('agenda_teste.mig_correcao_fase7a', true), '');
  v_7b text := coalesce(current_setting('agenda_teste.mig_correcao_fase7b', true), '');
  v_f1 text := coalesce(current_setting('agenda_teste.mig_leituras_fase1', true), '');
begin
  if v_7a = '' or v_7b = '' or v_f1 = '' then return; end if;
  execute replace(pg_temp.inteira(v_7a, 'agenda_encaixe_do_novo'), 'create or replace function public.agenda_encaixe_do_novo(', 'create function pg_temp.encaixe_antes(');
  execute replace(pg_temp.inteira(v_7b, 'agenda_livre_de_verdade'), 'create or replace function public.agenda_livre_de_verdade(', 'create function pg_temp.livre_antes(');
  execute replace(pg_temp.inteira(v_f1, 'agenda_ctp'), 'create or replace function public.agenda_ctp(', 'create function pg_temp.ctp_antes(');
end
$antes$;

-- ── L0. O catálogo e as portas ───────────────────────────────────────────────────────────────────────
do $l0$
declare
  v_res jsonb := '[]'::jsonb;
  v     text;
begin
  select string_agg(format('%s:%s:%s:%s', p.proname, p.prosecdef, p.provolatile, coalesce(array_to_string(p.proconfig, ','), '-')), ' | ' order by p.proname collate "C") into v
    from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('_agenda_encaixe_simulado', '_agenda_entrada_simulada_da_os', 'agenda_ctp', 'agenda_encaixe_do_novo', 'agenda_livre_de_verdade');
  v_res := pg_temp.igual(v_res, 'L0a as 2 novas definer e STABLE; as 3 recriadas como eram (o ctp invoker); search_path fixo', v,
    '_agenda_encaixe_simulado:t:s:search_path=public | _agenda_entrada_simulada_da_os:t:s:search_path=public | agenda_ctp:f:s:search_path=public'
    || ' | agenda_encaixe_do_novo:t:s:search_path=public | agenda_livre_de_verdade:t:s:search_path=public');
  select string_agg(format('%s:%s%s%s', f, case when has_function_privilege('anon', f, 'execute') then 'A' else '-' end,
                           case when has_function_privilege('authenticated', f, 'execute') then 'U' else '-' end,
                           case when has_function_privilege('service_role', f, 'execute') then 'S' else '-' end), ' | ' order by f) into v
    from unnest(array['public._agenda_encaixe_simulado(jsonb, date)', 'public._agenda_entrada_simulada_da_os(uuid, date)', 'public.agenda_ctp(uuid, date)',
                      'public.agenda_encaixe_do_novo(numeric, jsonb, text, date)', 'public.agenda_livre_de_verdade(date, timestamptz)']) f;
  v_res := pg_temp.igual(v_res, 'L0b as portas: authenticated (o painel) e service_role (o WhatsApp) nas 5; anon em nenhuma', v,
    'public._agenda_encaixe_simulado(jsonb, date):-US | public._agenda_entrada_simulada_da_os(uuid, date):-US | public.agenda_ctp(uuid, date):-US'
    || ' | public.agenda_encaixe_do_novo(numeric, jsonb, text, date):-US | public.agenda_livre_de_verdade(date, timestamptz):-US');
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('L0 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$l0$;

-- ── H. O cenário de hoje do P2 do lote (L1, L2, L3, L4, L5, L6, L7, L9) ─────────────────────────────
do $h$
declare
  v_fix   boolean := to_regprocedure('pg_temp.ctp_antes(uuid, date)') is not null
                     and exists (select 1 from public.payees where id = 'bb000000-0000-4000-8000-000000000002')
                     and exists (select 1 from public.service_orders where id = '05000000-0000-4000-8000-000000000074');
  c_hoje  constant date := date '2026-10-29';
  c_admin constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_tec   constant uuid := 'aa000000-0000-4000-8000-000000000002';
  c_dono  constant text := 'bb000000-0000-4000-8000-000000000001';
  c_rob   constant text := 'bb000000-0000-4000-8000-000000000002';
  c_joao  constant text := 'bb000000-0000-4000-8000-000000000003';
  c_901   constant uuid := '05000000-0000-4000-8000-000000000901';
  c_orcs  constant text[] := array['ORÇ-00119', 'ORÇ-00114', 'ORÇ-00115', 'ORÇ-00083', 'ORÇ-00095', 'OS-00074', 'OS-00112'];
  v_res   jsonb := '[]'::jsonb;
  r       jsonb;
  x       jsonb;
  a       jsonb;
  b       jsonb;
  v_t     text;
  v_q     text := '';
  v_n     int := 0;
  v_m     text;
  v_os    uuid;
  v_casos jsonb;
  k       int;
  v_c0    bigint;
  v_c1    bigint;
begin
  if not v_fix then
    insert into _resultado values ('L1–L9 cenários de hoje', true,
      'PULADO: sem a fixture-2310 e as migrations como texto (mig_correcao_fase7a, mig_correcao_fase7b, mig_leituras_fase1): rode pela bancada');
    return;
  end if;
  perform set_config('agenda.hoje', c_hoje::text, true);
  begin
    update public.agenda_config set modo_proposta = 'ligado', modo_vigia = 'ligado', modo_leitura = 'ligado' where id;
    r := pg_temp.vigiar(c_hoje, '16:30');
    perform pg_temp.agora(c_hoje, '17:40');

    -- ── L3. O encaixe de um serviço novo: byte a byte nos 3 modos ──
    v_casos := jsonb_build_array(
      jsonb_build_array(2, '[]'::jsonb, null),
      jsonb_build_array(2, jsonb_build_array(jsonb_build_object('payee_id', c_rob, 'nome', 'Roberto', 'eh_dono', false, 'turnos', 'dia')), null),
      jsonb_build_array(1, jsonb_build_array(jsonb_build_object('payee_id', c_rob, 'nome', 'Roberto', 'eh_dono', false, 'turnos', 'dia')), null),
      jsonb_build_array(2, jsonb_build_array(jsonb_build_object('payee_id', c_dono, 'nome', 'você', 'eh_dono', true, 'turnos', 'dia'),
                                             jsonb_build_object('payee_id', c_rob, 'nome', 'Roberto', 'eh_dono', false, 'turnos', 'dia')), null),
      jsonb_build_array(0.5, jsonb_build_array(jsonb_build_object('payee_id', c_joao, 'nome', 'João', 'eh_dono', false, 'turnos', 'dia')), null),
      jsonb_build_array(5, '[]'::jsonb, null),
      jsonb_build_array(2, jsonb_build_array(jsonb_build_object('payee_id', 'bb000000-0000-4000-8000-0000000000ff', 'nome', 'Mickael', 'eh_dono', false, 'turnos', 'dia')), null),
      jsonb_build_array(1.5, jsonb_build_array(jsonb_build_object('payee_id', c_joao, 'nome', 'João', 'eh_dono', false, 'turnos', 'tarde')), 'abre_e_fecha'),
      jsonb_build_array(2, '[]'::jsonb, 'sempre'),
      jsonb_build_array(3, '[]'::jsonb, 'nunca'));
    foreach v_m in array array['desligado', 'sombra', 'ligado'] loop
      perform pg_temp.modo(v_m);
      for k in 0 .. jsonb_array_length(v_casos) - 1 loop
        x := v_casos -> k;
        a := pg_temp.encaixe_antes((x ->> 0)::numeric, x -> 1, x ->> 2, c_hoje);
        b := public.agenda_encaixe_do_novo((x ->> 0)::numeric, x -> 1, x ->> 2, c_hoje);
        r := public._agenda_encaixe_simulado(jsonb_build_object('dias', (x ->> 0)::numeric, 'gente', x -> 1, 'dono', x ->> 2), c_hoje);
        v_n := v_n + 1;
        if a::text is distinct from b::text or a::text is distinct from r::text then
          v_q := v_q || format('[%s caso %s: %s | %s | %s] ', v_m, k + 1, a ->> 'texto', b ->> 'texto', r ->> 'texto');
        end if;
      end loop;
    end loop;
    v_res := pg_temp.ok(v_res, 'L3a agenda_encaixe_do_novo e o simulado com a mesma entrada = a de antes (20261031100980), byte a byte: 10 casos × 3 modos',
      v_q = '' and v_n = 30 and (pg_temp.encaixe_antes(2, '[]'::jsonb, null, c_hoje) ->> 'cabe')::boolean, coalesce(nullif(v_q, ''), v_n::text));
    -- o controle que morde: com passos (4 meios-dias num serviço de 1 dia) e com nao_antes_de, outra resposta
    a := public._agenda_encaixe_simulado(jsonb_build_object('dias', 1, 'gente', v_casos -> 2 -> 1), c_hoje);
    b := public._agenda_encaixe_simulado(jsonb_build_object('dias', 1, 'gente', v_casos -> 2 -> 1, 'passos', 4), c_hoje);
    r := public._agenda_encaixe_simulado(jsonb_build_object('dias', 1, 'gente', v_casos -> 2 -> 1, 'nao_antes_de', date '2026-11-16'), c_hoje);
    v_res := pg_temp.ok(v_res, 'L3b o simulado: passos manda nos meios-dias (4 = 2 dias) e nao_antes_de no 1º dia (a partir de seg 16/11)',
      jsonb_array_length(a -> 'dias') = 1 and jsonb_array_length(b -> 'dias') = 2 and (r ->> 'de')::date >= date '2026-11-16' and (a ->> 'de')::date < date '2026-11-16',
      (a - 'meios_por_semana')::text || ' | ' || (b - 'meios_por_semana')::text || ' | ' || (r - 'meios_por_semana')::text);

    -- ── L1. O *livre* (o cenário de hoje): desligado, sombra e ligado ──
    perform pg_temp.modo('desligado');
    a := pg_temp.livre_antes(c_hoje, now()) - 'ms';
    b := public.agenda_livre_de_verdade(c_hoje, now()) - 'ms';
    v_res := pg_temp.ok(v_res, 'L1a desligado: o *livre* é o de antes (20261101100800), byte a byte (sem o ms)', a = b and a ->> 'fonte' = 'simulacao', b::text);
    perform pg_temp.modo('sombra');
    b := public.agenda_livre_de_verdade(c_hoje, now()) - 'ms';
    v_res := pg_temp.ok(v_res, 'L1b sombra: o de antes byte a byte e, só em dados.teste, as livre_semanas (4) semanas novas com os totais',
      (b - 'dados') = a and jsonb_array_length(b #> '{dados,teste,semanas}') = 4 and b #> '{dados,teste,semanas,0}' ? 'totais'
      and not (a ? 'dados'), (b -> 'dados')::text);
    perform pg_temp.modo('ligado');
    b := public.agenda_livre_de_verdade(c_hoje, now()) - 'ms';
    v_q := '';
    for k in 0 .. 2 loop
      if (b #> array['semanas', k::text, 'pessoas']) is distinct from (a #> array['semanas', k::text, 'pessoas'])
         or (b #>> array['semanas', k::text, 'seg']) is distinct from (a #>> array['semanas', k::text, 'seg']) then
        v_q := v_q || format('[semana %s: %s | %s] ', k + 1, b #> array['semanas', k::text, 'pessoas'], a #> array['semanas', k::text, 'pessoas']);
      end if;
    end loop;
    v_res := pg_temp.ok(v_res, 'L1c ligado: 4 semanas; as 3 primeiras com os MESMOS meios-dias de cada pessoa que a de antes; a linha curta (texto) igual',
      jsonb_array_length(b -> 'semanas') = 4 and v_q = '' and b ->> 'texto' = a ->> 'texto' and not (b ? 'dados'), coalesce(nullif(v_q, ''), b ->> 'texto'));
    -- os totais contra a grade do motor (Σ teto100, Σ uso_c, Σ uso_r da equipe sem você) e o livre contra a soma das pessoas
    x := public._agenda_grade_de_agora(c_hoje) -> 'ctx';
    v_q := '';
    for k in 0 .. 3 loop
      r := b #> array['semanas', k::text];
      select format('%s/%s/%s/%s', coalesce(sum((x -> 'teto100' ->> ((p.p - 1) * (x ->> 'nw')::int + w.w - 1))::int), 0),
                    coalesce(sum((x -> 'uso_c' ->> ((p.p - 1) * (x ->> 'nw')::int + w.w - 1))::int), 0),
                    coalesce(sum((x -> 'uso_r' ->> ((p.p - 1) * (x ->> 'nw')::int + w.w - 1))::int), 0),
                    (select coalesce(sum((e ->> 'meios')::int), 0) from jsonb_array_elements(r -> 'pessoas') e where not (e ->> 'eh_dono')::boolean))
        into v_t
        from (select ((r ->> 'seg')::date - (x ->> 'seg')::date) / 7 + 1 as w) w,
             generate_series(1, (x ->> 'np')::int) p(p)
       where p.p <> coalesce((x ->> 'dono')::int, 0);
      if v_t is distinct from format('%s/%s/%s/%s', r #>> '{totais,pode}', r #>> '{totais,marcado}', r #>> '{totais,reservado}', r #>> '{totais,livre}') then
        v_q := v_q || format('[semana %s: grade %s, livre %s] ', k + 1, v_t, r -> 'totais');
      end if;
    end loop;
    v_res := pg_temp.ok(v_res, 'L1d os totais de cada semana = a grade do motor (Σ teto100, Σ compromisso, Σ reserva da equipe sem você) e livre = Σ meios das pessoas',
      v_q = '', coalesce(nullif(v_q, ''), (select string_agg((s -> 'totais')::text, ' ') from jsonb_array_elements(b -> 'semanas') s)));
    v_res := pg_temp.igual(v_res, 'L1e o texto do *livre* ligado (§6.3): o título, as 4 semanas (pode, marcado, reservado, livre por pessoa: os números do H3 do lote nas 3 primeiras), a folga fora da conta, a nota de você e como perguntar; sem o que ocupa',
      pg_temp.ver('livre', null, c_hoje),
      'Livre de verdade (pelo plano de agora):' || E'\n'
      || '• Semana de 03 a 06/11 (seg 02 é Finados): a equipe pode 5 dias e meio; nada marcado; reservado 4 dias; livre 1 dia e meio (Roberto 1 dia e meio, João nada).' || E'\n'
      || '• Semana de 09 a 13/11: pode 6 dias; nada marcado; reservado 2 dias; livre 4 dias (Roberto 3 dias, João 1 dia).' || E'\n'
      || '• Semana de 16 a 19/11 (sex 20 é Consciência Negra): pode 4 dias e meio; nada marcado; livre 3 dias e meio (Roberto 2 dias e meio, João 1 dia).' || E'\n'
      || '• Semana de 23 a 27/11: pode 6 dias; nada marcado; livre 5 dias (Roberto 3 dias e meio, João 1 dia e meio).' || E'\n'
      || 'Fora da conta: a folga de 18% para imprevisto.' || E'\n'
      || 'Você fica de fora da conta: não sei em que dias você fica em campo (é só me dizer, por exemplo, "fico em campo de segunda a sexta").' || E'\n'
      || 'Para um serviço novo, me diga quantos dias e com quem, que eu digo o 1º dia que cabe.');

    -- ── L4. Nenhuma saída da agenda_ver diz a projeção da Fase 1 (ligado) ──
    v_q := '';
    for v_t in select unnest(array[pg_temp.ver('livre', null, c_hoje), pg_temp.ver(null, 'semana', c_hoje), pg_temp.ver(null, 'proxima_semana', c_hoje),
                                   pg_temp.sim('{"dias": 2}', c_hoje), pg_temp.sim('{"dias": 1, "com_quem": ["Roberto"]}', c_hoje),
                                   pg_temp.se_aprovar('ORÇ-00119', c_hoje), pg_temp.se_aprovar('ORÇ-00114', c_hoje)]) loop
      if not pg_temp.sem_fila(v_t) then v_q := v_q || '[' || coalesce(v_t, '(nulo)') || '] '; end if;
    end loop;
    v_res := pg_temp.ok(v_res, 'L4a ligado: *livre*, *agenda*, *agenda semana que vem*, 2 serviços novos e 2 "se aprovar hoje" sem "fim da fila", "Pela fila" nem "Livre ela não está"',
      v_q = '', v_q);
    perform pg_temp.modo('desligado');
    v_t := pg_temp.se_aprovar('ORÇ-00119', c_hoje);
    v_res := pg_temp.ok(v_res, 'L4b o contraste: desligado, o "se aprovar hoje" é o da fila (a régua morde); e o texto plantado reprova',
      not pg_temp.sem_fila(v_t) and position('Pela fila' in v_t) > 0 and not pg_temp.sem_fila('Livre ela não está: há 7 serviços') and not pg_temp.sem_fila('')
      and not pg_temp.sem_fila(null) and pg_temp.sem_fila('Pelo plano de agora, cabe em ter 03/11.'), v_t);

    -- ── L5. O ctp: desligado e sombra = o de antes; o texto ligado ──
    v_q := '';
    foreach v_t in array c_orcs loop
      v_os := (select id from public.service_orders where service_order_number = v_t);
      a := pg_temp.ctp_antes(v_os, c_hoje);
      perform pg_temp.modo('desligado');
      b := public.agenda_ctp(v_os, c_hoje);
      if a is distinct from b then v_q := v_q || format('[desligado %s] ', v_t); end if;
      perform pg_temp.modo('sombra');
      b := public.agenda_ctp(v_os, c_hoje);
      if (b #- '{dados,teste}') is distinct from a then v_q := v_q || format('[sombra %s: %s] ', v_t, b ->> 'texto'); end if;
      if coalesce((a #>> '{dados,na_carteira}')::boolean, false) = (b #> '{dados,teste}' is not null) then v_q := v_q || format('[teste %s] ', v_t); end if;
      if b #> '{dados,teste}' is not null and not (b #> '{dados,teste}' ?& array['de', 'ate', 'texto']) then v_q := v_q || format('[chaves %s] ', v_t); end if;
    end loop;
    v_res := pg_temp.ok(v_res, 'L5a o ctp de 5 ORÇ e 2 OS aprovadas: desligado = o de antes (20261024160500) byte a byte; em sombra = o de antes + dados.teste {de, ate, texto} (só nos ORÇ)',
      v_q = '', v_q);
    perform pg_temp.modo('ligado');
    v_os := (select id from public.service_orders where service_order_number = 'ORÇ-00119');
    r := public.agenda_ctp(v_os, c_hoje);
    v_res := pg_temp.igual(v_res, 'L5b ligado, ORÇ-00119: a duração e o material de antes, o encaixe (2 pessoas, você abre e fecha; peças sem fornecedor) e a frase ao cliente pela semana em que começa',
      r ->> 'texto',
      'ORÇ-00119 (César), se o cliente aprovar hoje: 1,5 a 2,5 dias com 2 pessoas (estimativa minha, pelo valor) e 5 itens a comprar (de quem?). '
      || 'Pelo plano de agora, cabe em qui 19, ter 24 e qua 25/11, com João e Roberto; você abre e fecha. Isso se as peças chegarem antes: falta saber de quem comprar.' || E'\n'
      || 'Para o cliente: "semana de 16/11, uns 3 dias de serviço; confirmo a data quando as peças chegarem". É simulação: não marca nada.');
    v_res := pg_temp.ok(v_res, 'L5c ligado: dados.inicio = o 1º dia do encaixe, dados.encaixe sem o texto, sem dados.teste',
      r #>> '{dados,inicio,de}' = r #>> '{dados,encaixe,de}' and r #>> '{dados,inicio,ate}' = r #>> '{dados,encaixe,de}' and not (r #> '{dados,encaixe}' ? 'texto')
      and r #> '{dados,teste}' is null, (r -> 'dados')::text);
    perform pg_temp.modo('sombra');
    x := public.agenda_ctp(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'L5d em sombra, dados.teste diz o que ligado diria (o mesmo texto e o mesmo 1º dia)',
      x #>> '{dados,teste,texto}' = r ->> 'texto' and x #>> '{dados,teste,de}' = r #>> '{dados,inicio,de}', (x -> 'dados')::text);
    perform pg_temp.modo('ligado');
    r := public.agenda_ctp('05000000-0000-4000-8000-000000000074', c_hoje);
    v_res := pg_temp.ok(v_res, 'L5e a OS já aprovada diz o estado, como hoje (ligado)', r = pg_temp.ctp_antes('05000000-0000-4000-8000-000000000074', c_hoje), r ->> 'texto');
    r := public.agenda_ctp('05000000-0000-4000-8000-000000000115', c_hoje);
    v_res := pg_temp.igual(v_res, 'L5f ligado, ORÇ-00115: meio dia, 1 pessoa; a semana de 02/11 (o 1º dia é ter 03/11: seg é Finados)', r ->> 'texto',
      'ORÇ-00115 (César), se o cliente aprovar hoje: meio dia, 1 pessoa (estimativa minha, pelo valor) e 1 item a comprar (de quem?). '
      || 'Pelo plano de agora, cabe em ter 03/11, com Roberto; você abre e fecha. Isso se as peças chegarem antes: falta saber de quem comprar.' || E'\n'
      || 'Para o cliente: "semana de 02/11, meio dia de serviço; confirmo a data quando as peças chegarem". É simulação: não marca nada.');
    -- sem base de duração (um ORÇ sem serviço nem valor): pede os dias, sem simular (R9.12-1: a recusa diz por onde sair); em sombra, o de antes + dados.teste
    insert into public.clients (id, type, name) values ('c4000000-0000-4000-8000-000000000902', 'individual', 'Elias');
    insert into public.vessels (id, client_id, name, asset_type) values ('f4000000-0000-4000-8000-000000000902', 'c4000000-0000-4000-8000-000000000902', 'Lancha E', 'Lancha');
    insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at, grand_total)
    values ('05000000-0000-4000-8000-000000000902', 'ORÇ-00902', 'c4000000-0000-4000-8000-000000000902', 'f4000000-0000-4000-8000-000000000902', 'draft', 'draft', 'repair',
            timestamptz '2026-10-28 12:00-03', timestamptz '2026-10-28 12:00-03', 0);
    r := public.agenda_ctp('05000000-0000-4000-8000-000000000902', c_hoje);
    perform pg_temp.modo('sombra');
    x := public.agenda_ctp('05000000-0000-4000-8000-000000000902', c_hoje);
    perform pg_temp.modo('ligado');
    v_res := pg_temp.ok(v_res, 'L5g sem base de duração: ligado pede os dias ("me diga quantos dias"), sem encaixe; em sombra, o de antes + dados.teste com o mesmo texto',
      coalesce((r #>> '{dados,duracao,sem_base}')::boolean, false) and r ->> 'texto' like '%Pelo plano de agora: me diga quantos dias, que eu digo o 1º dia que cabe.%'
      and r ->> 'texto' like '%Para o cliente, ainda não: o orçamento não dá base para estimar os dias. É simulação: não marca nada.' and jsonb_typeof(r #> '{dados,encaixe}') = 'null'
      and pg_temp.sem_fila(r ->> 'texto') and (x #- '{dados,teste}') = pg_temp.ctp_antes('05000000-0000-4000-8000-000000000902', c_hoje)
      and x #>> '{dados,teste,texto}' = r ->> 'texto', r ->> 'texto');

    -- ── L6. AG7-32: a frase ao cliente sem o dia em que fica pronto ──
    v_q := '';
    foreach v_t in array c_orcs[1:3] loop
      v_os := (select id from public.service_orders where service_order_number = v_t);
      r := public.agenda_ctp(v_os, c_hoje);
      if not pg_temp.sem_fim(r ->> 'texto', case when r #>> '{dados,encaixe,ate}' is distinct from to_char((r #>> '{dados,encaixe,de}')::date
                                                       - (extract(isodow from (r #>> '{dados,encaixe,de}')::date)::int - 1), 'YYYY-MM-DD')
                                                  then (r #>> '{dados,encaixe,ate}')::date end) then
        v_q := v_q || format('[%s: %s] ', v_t, r ->> 'texto');
      end if;
    end loop;
    v_res := pg_temp.ok(v_res, 'L6a ligado, os 3 ORÇ que ainda não foram aprovados: a frase depois de "Para o cliente:" existe e não diz pronto, termina, até nem o último dia do encaixe', v_q = '', v_q);
    v_res := pg_temp.ok(v_res, 'L6b a régua morde: com "pronto", "até", a data de fim ou sem a frase, reprova',
      not pg_temp.sem_fim('Para o cliente: "fica pronto na semana de 09/11".', null) and not pg_temp.sem_fim('Para o cliente: "até 20/11".', null)
      and not pg_temp.sem_fim('Para o cliente: "semana de 09/11, termina dia 13".', null) and not pg_temp.sem_fim('Para o cliente: "semana de 09/11".', date '2026-11-09')
      and not pg_temp.sem_fim('Pelo plano de agora, cabe em seg 09/11.', null) and not pg_temp.sem_fim('Para o cliente: ', null)
      and pg_temp.sem_fim('Para o cliente: "semana de 09/11, uns 2 dias de serviço". É simulação: não marca nada.', date '2026-11-11'), null);

    -- ── L7. O ctp com login (ligado) ──
    v_os := (select id from public.service_orders where service_order_number = 'ORÇ-00119');
    v_t := pg_temp.como(c_admin, 'authenticated', format('select public.agenda_ctp(%L::uuid, %L::date) ->> ''texto''', v_os, c_hoje));
    v_res := pg_temp.ok(v_res, 'L7a o admin com login (o painel) lê o "se aprovar hoje" pelo encaixe (sem 42501: as 2 novas têm a porta de authenticated)',
      v_t = public.agenda_ctp(v_os, c_hoje) ->> 'texto' and position('Pelo plano de agora' in v_t) > 0, v_t);
    -- o técnico: o ctp já não abria para ele antes (a config da agenda fica fora do alcance dele: P0002), e segue igual; as 2 novas, com a porta delas (42501)
    v_t := pg_temp.como(c_tec, 'authenticated', format('select public.agenda_ctp(%L::uuid, %L::date) ->> ''texto''', v_os, c_hoje));
    perform pg_temp.modo('desligado');
    v_q := pg_temp.como(c_tec, 'authenticated', format('select public.agenda_ctp(%L::uuid, %L::date) ->> ''texto''', v_os, c_hoje));
    perform pg_temp.modo('ligado');
    v_q := v_q || ' | ' || pg_temp.como(c_tec, 'authenticated', format('select public._agenda_entrada_simulada_da_os(%L::uuid, %L::date)::text', v_os, c_hoje))
           || ' | ' || pg_temp.como(c_tec, 'authenticated', format('select public._agenda_encaixe_simulado(''{"dias": 1}''::jsonb, %L::date)::text', c_hoje));
    v_res := pg_temp.ok(v_res, 'L7b o técnico com login: o ctp ligado dá o mesmo erro de antes (desligado); a entrada e o simulado, 42501 da porta deles',
      v_t like 'erro %' and v_q like v_t || ' | erro 42501: A agenda de produção é com o administrador.% | erro 42501: A agenda de produção é com o administrador.%',
      v_t || ' || ' || v_q);
    v_t := pg_temp.como(null, 'service_role', format('select public.agenda_ctp(%L::uuid, %L::date) ->> ''texto''', v_os, c_hoje));
    v_res := pg_temp.ok(v_res, 'L7c o service_role (o WhatsApp) lê', position('Pelo plano de agora' in v_t) > 0, v_t);
    v_t := pg_temp.como(null, 'anon', format('select public._agenda_entrada_simulada_da_os(%L::uuid, %L::date)::text', v_os, c_hoje))
           || ' | ' || pg_temp.como(null, 'anon', format('select public._agenda_encaixe_simulado(''{"dias": 1}''::jsonb, %L::date)::text', c_hoje));
    v_res := pg_temp.ok(v_res, 'L7d anon não executa a entrada nem o simulado (42501)', v_t like 'erro 42501%| erro 42501%', v_t);

    -- ── L9. O peso ──
    set local track_functions = 'all';
    v_os := (select id from public.service_orders where service_order_number = 'ORÇ-00119');
    perform pg_temp.modo('desligado');
    v_c0 := pg_temp.chamadas('_agenda_entrada_simulada_da_os') + pg_temp.chamadas('_agenda_encaixe_simulado');
    perform public.agenda_ctp(v_os, c_hoje);
    perform public.agenda_livre_de_verdade(c_hoje, now());
    v_c1 := pg_temp.chamadas('_agenda_entrada_simulada_da_os') + pg_temp.chamadas('_agenda_encaixe_simulado');
    perform pg_temp.modo('sombra');
    perform public.agenda_ctp(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'L9 desligado: o ctp e o *livre* não chamam a entrada nem o simulado; em sombra, o ctp chama cada um 1 vez',
      v_c1 = v_c0 and pg_temp.chamadas('_agenda_entrada_simulada_da_os') + pg_temp.chamadas('_agenda_encaixe_simulado') = v_c1 + 2,
      format('%s → %s → %s', v_c0, v_c1, pg_temp.chamadas('_agenda_entrada_simulada_da_os') + pg_temp.chamadas('_agenda_encaixe_simulado')));

    -- ── L2. O 1º dia do encaixe da OS = o da agenda_propor ──
    perform pg_temp.modo('ligado');
    insert into public.clients (id, type, name) values ('c4000000-0000-4000-8000-000000000901', 'individual', 'Daniel');
    insert into public.vessels (id, client_id, name, asset_type)
    values ('f4000000-0000-4000-8000-000000000901', 'c4000000-0000-4000-8000-000000000901', 'Lancha D', 'Lancha');
    insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type,
                                       created_at, updated_at, converted_to_os_at, grand_total)
    values (c_901, 'OS-00901', 'c4000000-0000-4000-8000-000000000901', 'f4000000-0000-4000-8000-000000000901',
            'approved', 'approved', 'repair', timestamptz '2026-10-28 12:00-03', timestamptz '2026-10-28 12:00-03', timestamptz '2026-10-28 12:00-03', 2160);
    insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at)
    values (md5('7g:p4:servico:901')::uuid, c_901, '5e000000-0000-4000-8000-000000000003', 'Revisão do sistema elétrico', 'unit', 1, 2160, 2160,
            timestamptz '2026-10-28 12:00-03');
    insert into public.receivables (id, client_id, service_order_id, description, issue_date, due_date, amount, status, paid_amount, balance_amount, is_deposit)
    values (md5('7g:p4:sinal:901')::uuid, 'c4000000-0000-4000-8000-000000000901', c_901, 'Sinal OS-00901', date '2026-10-28', date '2026-10-28', 500, 'paid', 500, 0, true);
    insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, dono_presenca, material_conferido_em, trecho, atualizado_por)
    values (c_901, 2, 'dono', timestamptz '2026-10-28 18:00-03', 'abre_e_fecha', timestamptz '2026-10-28 18:00-03', 'dois dias com o Roberto, eu abro e fecho', c_admin);
    insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos) values (c_901, c_rob::uuid, 'dia');
    x := public._agenda_entrada_simulada_da_os(c_901, c_hoje);
    v_res := pg_temp.ok(v_res, 'L2a a entrada da OS-00901: 4 meios-dias (2 dias), o Roberto o dia todo, você abre e fecha, a partir do dia que a prontidão diz',
      (x ->> 'passos')::int = 4 and (x ->> 'dias')::numeric = 2 and x -> 'gente' = jsonb_build_array(jsonb_build_object('payee_id', c_rob, 'nome', 'Roberto', 'eh_dono', false, 'turnos', 'dia'))
      and x ->> 'dono' = 'abre_e_fecha' and x ->> 'nao_antes_de' = public.os_prontidao(c_901, c_hoje) ->> 'est' and x ->> 'rotulo' like 'OS-00901 (%', x::text);
    v_t := pg_temp.dias_do_motor(c_901, c_hoje);
    v_res := pg_temp.ok(v_res, 'L2b sem compra: os dias do encaixe da OS = os da agenda_propor(''os'', aplicar = false) (seg 09 e qua 11/11)',
      v_t = pg_temp.dias_do_encaixe(c_901, c_hoje) and v_t = '2026-11-09,2026-11-11', v_t || ' | ' || coalesce(pg_temp.dias_do_encaixe(c_901, c_hoje), '(nulo)'));
    -- a compra pendente: um cabo crítico de um fornecedor de 8 dias úteis (conferido) segura o início
    insert into public.suppliers (id, name, modalidade, prazo_dias_uteis, prazo_fonte, active)
    values (md5('7g:p4:forn')::uuid, 'Fornecedor do cabo', 'entrega_local', 8, 'dono', true);
    insert into public.os_material (id, service_order_id, origem, descricao, quantidade_necessaria, critico, situacao, fonte, fornecedor_id, conferido_em)
    values (md5('7g:p4:mat:901')::uuid, c_901, 'dono', 'Cabo de bateria 35 mm', 2, true, 'falta', 'dono', md5('7g:p4:forn')::uuid, timestamptz '2026-10-28 10:00-03');
    v_t := pg_temp.dias_do_motor(c_901, c_hoje);
    v_res := pg_temp.ok(v_res, 'L2c com a compra pendente: o 1º dia do encaixe = o da agenda_propor, e depois de qua 11/11 (o cabo segura o início)',
      split_part(v_t, ',', 1) = split_part(pg_temp.dias_do_encaixe(c_901, c_hoje), ',', 1) and split_part(v_t, ',', 1)::date > date '2026-11-11'
      and (public._agenda_entrada_simulada_da_os(c_901, c_hoje) ->> 'nao_antes_de')::date > date '2026-11-11',
      coalesce(v_t, '(nulo)') || ' | ' || coalesce(pg_temp.dias_do_encaixe(c_901, c_hoje), '(nulo)') || ' | ' || (public._agenda_entrada_simulada_da_os(c_901, c_hoje) ->> 'nao_antes_de'));
    begin
      perform public._agenda_entrada_simulada_da_os(null, c_hoje);
      v_t := 'sem erro';
    exception when others then
      v_t := sqlstate;
    end;
    v_res := pg_temp.ok(v_res, 'L2d a OS que não existe: entrada nula; sem a OS: 22004',
      public._agenda_entrada_simulada_da_os('05000000-0000-4000-8000-000000000999', c_hoje) is null and v_t = '22004', v_t);

    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('L1–L9 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$h$;

-- ── M. A folga nos 2 ramos, contra agenda_como_pensei e a conta à mão (L1) ──────────────────────────
-- A âncora (o C10 de agenda_fase7g_como_pensei.sql, a conta de fora da grade): na semana de 02/11 o Roberto espera 8 meios-dias e o João 4; você fica fora da
-- equipe. Carga 0,8: teto80 Roberto 6, João 3; o teto da equipe floor(0,8 × 12) = 9 → folga 3 nos 2 ramos. Carga 0,7: teto80 Roberto 5 (floor 5,6), João 2
-- (floor 2,8) → ramo pessoa 12 − 7 = 5; ramo equipe floor(8,4) = 8 → 12 − 8 = 4 (os 2 ramos dão números diferentes: a regra de cada um é exercida).
do $m$
declare
  v_res jsonb := '[]'::jsonb;
  v_l   jsonb;
  v_c   jsonb;
  v_q   text := '';
  v_cg  numeric;
  v_fr  boolean;
begin
  if coalesce(current_setting('agenda_teste.cenario_motor', true), '') = '' then
    perform pg_temp.gravar(pg_temp.ok('[]', 'L1f a folga nos 2 ramos', true, 'PULADO: sem o cenário do motor (rode pela bancada)'));
    return;
  end if;
  begin
    execute current_setting('agenda_teste.cenario_motor');
    update public.agenda_config set modo_proposta = 'ligado', modo_vigia = 'ligado', gestor_so_propor = false, modo_marcar_sozinho = 'desligado' where id;
    perform public.agenda_vigiar(date '2026-10-29', (date '2026-10-29' + time '16:30') at time zone 'America/Sao_Paulo');
    update public.agenda_config set modo_explicar = 'ligado', modo_marcar_sozinho = 'ligado', gestor_so_propor = true,
           marcar_sozinho_desde = (date '2026-10-29' + time '16:00') at time zone 'America/Sao_Paulo',
           marcar_regras = '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada,sinal_cobrar}'
     where id;
    foreach v_cg in array array[0.8, 0.7] loop
      foreach v_fr in array array[true, false] loop
        update public.agenda_config set carga_max = v_cg, gestor_so_propor = v_fr where id;
        v_l := public.agenda_livre_de_verdade(date '2026-10-29', (date '2026-10-29' + time '17:00') at time zone 'America/Sao_Paulo');
        v_c := public.agenda_como_pensei(date '2026-11-02', date '2026-10-29', (date '2026-10-29' + time '17:00') at time zone 'America/Sao_Paulo');
        v_q := v_q || format('[carga %s, freio %s: livre %s/%s, como pensei %s/%s, ramo %s] ', v_cg, v_fr, v_l #>> '{semanas,0,totais,folga}', v_l #>> '{semanas,0,totais,pode}',
                             v_c #>> '{folga,meios}', v_c #>> '{folga,base}', v_c #>> '{folga,ramo}');
      end loop;
    end loop;
    v_res := pg_temp.igual(v_res, 'L1f a folga da 1ª semana do *livre* (seg 02/11) = a de agenda_como_pensei e a conta à mão, nos 2 ramos e com 2 cargas (0,7 separa os ramos)',
      v_q, '[carga 0.8, freio t: livre 3/12, como pensei 3/12, ramo pessoa] [carga 0.8, freio f: livre 3/12, como pensei 3/12, ramo teto_equipe] '
           || '[carga 0.7, freio t: livre 5/12, como pensei 5/12, ramo pessoa] [carga 0.7, freio f: livre 4/12, como pensei 4/12, ramo teto_equipe] ');
    update public.agenda_config set carga_max = 0.8, gestor_so_propor = true where id;
    v_l := public.agenda_livre_de_verdade(date '2026-10-29', (date '2026-10-29' + time '17:00') at time zone 'America/Sao_Paulo');
    v_res := pg_temp.igual(v_res, 'L1g o texto do *livre* no cenário do motor (você em campo: "você" na semana, fora dos totais da equipe; a folga fora da conta)',
      v_l ->> 'texto_completo',
      'Livre de verdade (pelo plano de agora):' || E'\n'
      || '• Semana de 03 a 06/11 (seg 02 é Finados): a equipe pode 6 dias; marcado 3 dias e meio; reservado 1 dia e meio; livre meio dia (João meio dia, Roberto nada); você 2 dias.' || E'\n'
      || '• Semana de 09 a 13/11: pode 7 dias; nada marcado; reservado 1 dia e meio; livre 5 dias (Roberto 3 dias e meio, João 1 dia e meio); você 3 dias e meio.' || E'\n'
      || '• Semana de 16 a 19/11 (sex 20 é Consciência Negra): pode 5 dias e meio; nada marcado; livre 4 dias (Roberto 3 dias, João 1 dia); você 3 dias.' || E'\n'
      || '• Semana de 23 a 27/11: pode 7 dias; nada marcado; livre 5 dias e meio (Roberto 4 dias, João 1 dia e meio); você 3 dias e meio.' || E'\n'
      || 'Fora da conta: a folga de 24% para imprevisto.' || E'\n'
      || 'Para um serviço novo, me diga quantos dias e com quem, que eu digo o 1º dia que cabe.');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('L1f o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$m$;

-- ── L8. As cópias ────────────────────────────────────────────────────────────────────────────────────
do $l8$
declare
  v_res jsonb := '[]'::jsonb;
  v_mig text := replace(coalesce(current_setting('agenda_teste.mig_livre_fase7g', true), ''), chr(13), '');
  v     text;
  x     record;
begin
  for x in select * from (values ('public.agenda_encaixe_do_novo(numeric, jsonb, text, date)', 'e9333e07be2808185c3351698e50930c'),
                                 ('public._agenda_encaixe_simulado(jsonb, date)', 'e9333e07be2808185c3351698e50930c'),
                                 ('public.agenda_ctp(uuid, date)', 'd7760665552fa30a76b34c30f3ecf605'),
                                 ('public.agenda_livre_de_verdade(date, timestamptz)', '79b284f05d99aadb3099649138e7d520')) t(f, h) loop
    select p.prosrc into v from pg_proc p where p.oid = x.f::regprocedure;
    v_res := pg_temp.ok(v_res, format('L8a %s sem os blocos da 7g é o corpo da origem (md5 %s…, o do R9.1), e os blocos existem', x.f, left(x.h, 8)),
      md5(pg_temp.sem7g(v)) = x.h and pg_temp.sem7g(v) <> replace(v, chr(13), ''), md5(pg_temp.sem7g(v)));
  end loop;
  if v_mig = '' then
    v_res := pg_temp.ok(v_res, 'L8b as funções da migration', true, 'PULADO: sem agenda_teste.mig_livre_fase7g (rode pela bancada)');
  else
    select string_agg(m[1], ',' order by m[1] collate "C") into v from regexp_matches(v_mig, 'create or replace function public\.([a-z_0-9]+)\(', 'g') m;
    v_res := pg_temp.igual(v_res, 'L8b a migration cria as 2 novas e recria só agenda_ctp, agenda_encaixe_do_novo e agenda_livre_de_verdade (agenda_simular não, R9.4-6)', v,
      '_agenda_encaixe_simulado,_agenda_entrada_simulada_da_os,agenda_ctp,agenda_encaixe_do_novo,agenda_livre_de_verdade');
  end if;
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('L8 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$l8$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
