-- Prova do motor da Agenda de Produção, Fase 7d (pacote P4): onde é o serviço, no motor (migration 20261107100300; spec-fase7d §5.4, §6.2, §8.3
-- agenda_fase7d_motor.sql, R6.3-7, R6.7b, R6.8 e R6.9).
-- bancada: depende de 20261107100300
--
--   M0  as portas: as 9 novas, só do service_role; as recriadas com as de antes; agenda_propor definer
--   M1  sombra = antes, em md5 e SEM projeção (R6.8): com os 6 modos desligados e em sombra e os locais cadastrados, agenda_propor (semana e OS),
--       o contexto, os itens, os parâmetros, o fora, a carga, os textos e as perguntas gravadas são os das funções da 7c rodando no lugar
--   M1b chave ausente (R6.8-3): em sombra, nenhuma das chaves novas no contexto, no item nem em v_par (o que o M1 compara, dito por nome)
--   M1c prova sem relógio (R6.8): com _agenda_local_resolvido, _agenda_local_mascara, _agenda_viagem_da_os e _agenda_estado_do_bem lançando exceção e
--       contando as chamadas, agenda_vigiar, agenda_propor e agenda_cliente_vigiar rodam em sombra: 0 chamadas, nenhum erro
--   M2  o calendário: J1 fora de 20/07; o "por que não"; a violação local da publicada só com a variável (R6.8-4), com o texto; o fixado pelo dono
--       fica; o meio-dia fora do horário do local conferido (fora_h); a retirada só com o pátio
--   M3  o acesso (AG7-14): com modo_local_autorizacao ligado, J2 sai igual ao de sombra (md5): nenhuma pessoa nem dia muda
--   M4  o pátio: o 4º entra depois do 1º sair; patio_cheio (motivo sem_encaixe, R6.3-7); sem vagas, sem limite; a reserva 2c não ocupa vaga; a entrada no
--       EST; o bem parado sem plano ocupa; a reserva por teto e a condicionada passam pelo pátio; a 2ª volta sem o bloco; o _agenda_ctx_com
--   M5  a pernoite: 6 meios seguidos, a mesma equipe, sem abre e fecha; dia quebrado = sem bloco; quem falta = sem bloco; a violação leva a viagem inteira
--   M6  a ida e volta: 4 meios em 2 dias, quem começou vem primeiro
--   M7  o mesmo dia: o v_mh olha o dia; quem já está lá; o critério local; J9 e J10 juntos; a suposição "juntei com"
--   M8  a troca: em dezembro sim, em julho não (a tupla do _agenda_melhor, R6.8-5; a ordem das pessoas, depois do k4; a suposição "evitei")
--   M9  as cópias: as 11 recriadas só mudam nos blocos "-- FASE 7d:", vivas e na migration
--   M10 a revisão não corta a estrada (R6.9-2)
--   M11 a escada e o validador conhecem o local (R6.9-3)
--   M12 o freio (R6.7b): com os 6 modos ligados e *gestor, só propor*, tudo volta ao que é em sombra (md5)
--   M13 a matriz: os cenários J com cada modo ligado, um a um e juntos: a proposta nunca sai inválida, e cada modo só mexe no que é dele
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7d_motor.sql
--   Seguro em produção: termina em ROLLBACK. M0 roda em qualquer banco; o resto usa as fixtures e só roda na bancada (fora dela sai PULADO).
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
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  if position(format('create or replace function public.%s(', p_nome) in v) = 0 then return ''; end if;
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'\nas $function$' in v) + length(E'\nas $function$'));
  return left(v, position('$function$' in v) - 1);
end $f$;
create function pg_temp.inteira(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  return left(v, position(E'\n$function$;' in v) + length(E'\n$function$;') - 1);
end $f$;
-- O texto sem os blocos "-- FASE 7d: … -- FASE 7d: fim" e sem as marcas "-- (7d … -- (7d: fim)" de dentro dos blocos da 7c.
create function pg_temp.sem_7d(p text) returns text language plpgsql immutable as $f$
declare
  v_fora   text[] := '{}';
  v_dentro int := 0;
  l        text;
begin
  foreach l in array string_to_array(replace(p, E'\r\n', E'\n'), E'\n') loop
    if v_dentro = 0 and l ~ '^\s*-- FASE 7[def]:' and l !~ '^\s*-- FASE 7[def]: fim' then
      v_dentro := 1;
      continue;
    end if;
    if v_dentro = 1 and l ~ '^\s*-- FASE 7[def]: fim' then
      v_dentro := 0;
      continue;
    end if;
    if v_dentro = 0 and l ~ '^\s*-- \(7[def] ' then
      v_dentro := 2;
      continue;
    end if;
    if v_dentro = 2 and l ~ '^\s*-- \(7[def]: fim\)' then
      v_dentro := 0;
      continue;
    end if;
    if v_dentro = 0 then
      v_fora := v_fora || l;
    end if;
  end loop;
  return array_to_string(v_fora, E'\n');
end $f$;
create function pg_temp.como(p_papel text, p_sql text) returns text language plpgsql as $f$
declare
  v text;
begin
  perform set_config('request.jwt.claims', json_build_object('role', p_papel)::text, true);
  begin
    execute format('set local role %I', p_papel);
    execute p_sql into v;
    reset role;
  exception when others then
    v := 'erro ' || sqlstate || ': ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;
-- A projeção (OS, pessoa, dia, turno, presença, tipo) e o que fica de fora (OS, motivo).
create function pg_temp.projecao(p jsonb) returns text language sql immutable as $f$
  select coalesce((select string_agg(format('%s %s %s %s [%s]', i ->> 'op', i ->> 'numero', i ->> 'tipo', coalesce(i ->> 'reserva_de', '-'),
                                            (select string_agg(concat_ws(' ', a ->> 'nome', a ->> 'dia', a ->> 'turno', a ->> 'presenca'), ', '
                                                               order by a ->> 'dia', a ->> 'turno', a ->> 'presenca', a ->> 'nome')
                                               from jsonb_array_elements(coalesce(i -> 'alocacoes', '[]'::jsonb)) a)),
                                     ' | ' order by i ->> 'op', i ->> 'numero', i ->> 'tipo', i ->> 'reserva_de')
                     from jsonb_array_elements(coalesce(p -> 'itens', '[]'::jsonb)) i), '')
         || ' || ' || coalesce((select string_agg(format('%s %s', f ->> 'numero', f ->> 'motivo'), ', ' order by f ->> 'numero', f ->> 'motivo')
                                  from jsonb_array_elements(coalesce(p -> 'fora', '[]'::jsonb)) f), '')
$f$;
-- O item "criar" de uma OS da proposta (o compromisso; sem ele, a reserva) e os dias/meios-dias dele.
create function pg_temp.item(p jsonb, p_numero text) returns jsonb language sql immutable as $f$
  select i from jsonb_array_elements(coalesce(p -> 'itens', '[]'::jsonb)) i
   where i ->> 'op' = 'criar' and i ->> 'numero' = p_numero order by i ->> 'tipo' = 'reserva' limit 1
$f$;
create function pg_temp.fora(p jsonb, p_numero text) returns jsonb language sql immutable as $f$
  select f from jsonb_array_elements(coalesce(p -> 'fora', '[]'::jsonb)) f where f ->> 'numero' = p_numero limit 1
$f$;
create function pg_temp.meios(p_item jsonb) returns text language sql immutable as $f$
  select string_agg(distinct (a ->> 'dia') || ' ' || (a ->> 'turno'), ', ')
    from jsonb_array_elements(coalesce(p_item -> 'alocacoes', '[]'::jsonb)) a where a ->> 'presenca' = 'turno'
$f$;
create function pg_temp.n_meios(p_item jsonb) returns int language sql immutable as $f$
  select count(distinct (a ->> 'dia', a ->> 'turno'))::int
    from jsonb_array_elements(coalesce(p_item -> 'alocacoes', '[]'::jsonb)) a where a ->> 'presenca' = 'turno'
$f$;
create function pg_temp.pessoas(p_item jsonb) returns text language sql immutable as $f$
  select string_agg(distinct a ->> 'nome', ', ')
    from jsonb_array_elements(coalesce(p_item -> 'alocacoes', '[]'::jsonb)) a where a ->> 'presenca' = 'turno'
$f$;
create function pg_temp.dias(p_item jsonb) returns date[] language sql immutable as $f$
  select array(select distinct (a ->> 'dia')::date from jsonb_array_elements(coalesce(p_item -> 'alocacoes', '[]'::jsonb)) a order by 1)
$f$;
-- O motor da 7c no lugar: as 11 recriadas pelas origens (a tabela do R6.1), dentro de uma subtransação desfeita por quem chama.
create function pg_temp.motor_da_7c() returns void language plpgsql as $f$
begin
  execute pg_temp.inteira(current_setting('agenda_teste.mig_motor_fase7c'), '_agenda_contexto');
  execute pg_temp.inteira(current_setting('agenda_teste.mig_motor_fase7c'), '_agenda_tentar_bloco');
  execute pg_temp.inteira(current_setting('agenda_teste.mig_motor_fase7c'), '_agenda_encaixar');
  execute pg_temp.inteira(current_setting('agenda_teste.mig_motor_fase7c'), '_agenda_por_que_nao');
  execute pg_temp.inteira(current_setting('agenda_teste.mig_motor_fase7b'), '_agenda_melhor');
  execute pg_temp.inteira(current_setting('agenda_teste.mig_motor_fase2'), '_agenda_ctx_com');
  execute pg_temp.inteira(current_setting('agenda_teste.mig_violacao_fase7c'), '_agenda_violacoes');
  execute pg_temp.inteira(current_setting('agenda_teste.mig_violacao_fase7c'), '_agenda_gestor_reparo');
  execute pg_temp.inteira(current_setting('agenda_teste.mig_motor_fase7b'), '_agenda_validar_itens');
  execute pg_temp.inteira(current_setting('agenda_teste.mig_correcao2_fase7b'), '_agenda_gestor_pessoa_meios');
  execute pg_temp.inteira(current_setting('agenda_teste.mig_correcao_fase7c'), 'agenda_propor');
end $f$;
create function pg_temp.textos_ok() returns boolean language sql stable as $f$
  select coalesce(current_setting('agenda_teste.mig_motor_fase7c', true), '') <> ''
     and coalesce(current_setting('agenda_teste.mig_motor_fase7b', true), '') <> ''
     and coalesce(current_setting('agenda_teste.mig_motor_fase2', true), '') <> ''
     and coalesce(current_setting('agenda_teste.mig_violacao_fase7c', true), '') <> ''
     and coalesce(current_setting('agenda_teste.mig_correcao2_fase7b', true), '') <> ''
     and coalesce(current_setting('agenda_teste.mig_correcao_fase7c', true), '') <> ''
     and coalesce(current_setting('agenda_teste.mig_motor_fase7d', true), '') <> ''
$f$;

-- ── M0. As portas (sem fixture) ────────────────────────────────────────────────────────────────────────────────────
with f(sig, vol) as (values
  ('public._agenda_patio_cabe(jsonb, integer, integer, integer, integer, integer)', 'i'),
  ('public._agenda_patio_intervalo(jsonb, integer, integer, integer)', 'i'),
  ('public._agenda_patio_frase(text, integer, boolean)', 'i'),
  ('public._agenda_patio_contexto(date, date, date, uuid[], jsonb, uuid[], boolean[])', 's'),
  ('public._agenda_viagem_extra(text, integer, integer)', 'i'),
  ('public._agenda_viagem_suposicao(jsonb, text)', 's'),
  ('public._agenda_irmao_chave(integer[], integer, integer, integer[], integer, integer[], integer)', 'i'),
  ('public._agenda_troca_evitada(integer[], integer[], integer, integer[], integer, integer, integer, integer[], integer)', 'i'),
  ('public._agenda_gestor_estrada(uuid, date, jsonb)', 's'))
insert into _resultado
select 'M0a as 9 novas: invoker, com o search_path fixo, a volatilidade certa e só do service_role (nem public, nem anon, nem authenticated: a porta do motor)',
       count(p.oid) = 9 and count(*) = 9
       and bool_and(coalesce(not p.prosecdef and p.provolatile = f.vol and array_to_string(p.proconfig, ',') = 'search_path=public'
                             and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                             and has_function_privilege('service_role', p.oid, 'execute')
                             and not exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0), false)),
       string_agg(f.sig, '; ') filter (where p.oid is null or p.provolatile <> f.vol or p.prosecdef
                                          or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
  from f left join pg_proc p on p.oid = to_regprocedure(f.sig);
insert into _resultado
select 'M0b o anon e o técnico logado não alcançam as novas (42501, rodando)',
       pg_temp.como('anon', 'select public._agenda_patio_cabe(''[]''::jsonb, 1, 1, 1, 1, 1)::text') like 'erro 42501%'
       and pg_temp.como('authenticated', 'select public._agenda_patio_cabe(''[]''::jsonb, 1, 1, 1, 1, 1)::text') like 'erro 42501%'
       and pg_temp.como('anon', 'select public._agenda_viagem_extra(''pernoite'', 2, 4)::text') like 'erro 42501%'
       and pg_temp.como('authenticated', 'select public._agenda_viagem_extra(''pernoite'', 2, 4)::text') like 'erro 42501%',
       pg_temp.como('anon', 'select public._agenda_patio_cabe(''[]''::jsonb, 1, 1, 1, 1, 1)::text');
with f(sig) as (values
  ('public._agenda_contexto(date, date, date, uuid[], uuid[])'),
  ('public._agenda_tentar_bloco(jsonb, boolean[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], jsonb, integer, boolean, integer)'),
  ('public._agenda_encaixar(jsonb, jsonb, jsonb)'), ('public._agenda_por_que_nao(jsonb, jsonb, integer, integer)'),
  ('public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)'))
insert into _resultado
select 'M0c as recriadas do motor continuam só do service_role; agenda_propor continua definer, com as mesmas assinaturas',
       count(p.oid) = 5
       and bool_and(not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                    and has_function_privilege('service_role', p.oid, 'execute'))
       and (select prosecdef from pg_proc where oid = to_regprocedure('public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)')),
       string_agg(f.sig, '; ') filter (where p.oid is null)
  from f left join pg_proc p on p.oid = to_regprocedure(f.sig);

-- ── As fixtures ────────────────────────────────────────────────────────────────────────────────────────────────────
do $carga$
begin
  if coalesce(current_setting('agenda_teste.fase7d', true), '') = '' or coalesce(current_setting('agenda_teste.fase7c', true), '') = ''
     or coalesce(current_setting('agenda_teste.fase7b', true), '') = '' then
    return;
  end if;
  perform set_config('agenda_teste.fase7c_etiquetas', 'mv', true);
  execute current_setting('agenda_teste.fase7d');
end
$carga$;
create function pg_temp.carregada() returns boolean language sql stable as $f$
  select exists (select 1 from public.service_orders so where so.service_order_number = 'OS-J1')
$f$;
create function pg_temp.os(p_numero text) returns uuid language sql stable as $f$
  select so.id from public.service_orders so where so.service_order_number = p_numero
$f$;
create function pg_temp.lista(p text[]) returns uuid[] language sql stable as $f$
  select array(select pg_temp.os(x) from unnest(p) x)
$f$;
create function pg_temp.pessoa(p_nome text) returns uuid language sql stable as $f$
  select id from public.payees where name = p_nome and active order by id limit 1
$f$;
-- o gestor da 7a ligado (1 pessoa por OS), sem o freio, e os 6 modos da 7d num valor só
create function pg_temp.gestor() returns void language sql as $f$
  update public.agenda_config
     set modo_marcar_sozinho = 'ligado', modo_encaixe_aprovacao = 'ligado', modo_revisao_diaria = 'ligado', modo_compre_ate = 'ligado',
         modo_vaga_fechamento = 'ligado', gestor_so_propor = false, gestor_so_propor_em = null,
         marcar_sozinho_desde = timestamptz '2026-10-29 16:46-03', modo_proposta = 'ligado'
   where id
$f$;
create function pg_temp.modos(p_modo text) returns void language sql as $f$
  update public.agenda_config
     set modo_local_calendario = p_modo, modo_local_autorizacao = p_modo, modo_bem = p_modo, modo_patio = p_modo, modo_viagem = p_modo, modo_mesmo_local = p_modo
   where id
$f$;
create function pg_temp.modo(p_coluna text, p_modo text) returns void language plpgsql as $f$
begin
  execute format('update public.agenda_config set %I = %L where id', p_coluna, p_modo);
end $f$;
create function pg_temp.dono(p_numeros text[], p_presenca text) returns void language sql as $f$
  update public.os_planejamento set dono_presenca = p_presenca where service_order_id = any (pg_temp.lista(p_numeros))
$f$;
-- O motor no cenário J (hoje = sex 16/07/2027 16:20) e no D (hoje = seg 30/11/2026), sem gravar.
create function pg_temp.j(p_numeros text[], p_r jsonb default '{}'::jsonb) returns jsonb language sql as $f$
  select public.agenda_propor('os', null, null, pg_temp.lista(p_numeros), p_r, false, 'vigia', null, date '2027-07-16',
                              pg_temp.em(date '2027-07-16', '16:20'))
$f$;
create function pg_temp.d(p_numeros text[], p_hoje date default date '2026-11-30') returns jsonb language sql as $f$
  select public.agenda_propor('os', null, null, pg_temp.lista(p_numeros), '{}'::jsonb, false, 'vigia', null, p_hoje, pg_temp.em(p_hoje, '16:20'))
$f$;
-- O texto sem os ids das alocações novas (gen_random_uuid a cada rodada).
create function pg_temp.sem_ids(p text) returns text language sql immutable as $f$
  select regexp_replace(regexp_replace(p, '"alocacao_id": "[0-9a-f-]{36}"', '"alocacao_id": "U"', 'g'),
                        '"proposta_id": "[0-9a-f-]{36}"', '"proposta_id": "U"', 'g')
$f$;
-- O retrato do motor em p_hoje (a semana, a OS, o contexto, e o que fica gravado: itens, parâmetros, fora, carga, textos e perguntas), em md5.
create function pg_temp.retrato(p_hoje date, p_oss uuid[], p_ini date) returns text language plpgsql as $f$
declare
  v_ag timestamptz := pg_temp.em(p_hoje, '16:20');
  v1   text;
  v2   text;
  v3   text;
  v4   text;
  v5   text;
  v_q0 timestamptz;
begin
  v1 := public.agenda_propor('semana', null, null, null, '{}'::jsonb, false, 'motor', null, p_hoje, v_ag)::text;
  v2 := public.agenda_propor('os', null, null, p_oss, '{}'::jsonb, false, 'vigia', null, p_hoje, v_ag)::text;
  v3 := public._agenda_contexto(p_ini, p_ini + 41, p_hoje, '{}'::uuid[], p_oss)::text;
  perform public.agenda_propor('os', null, null, p_oss, '{}'::jsonb, true, 'vigia', null, p_hoje, v_ag);
  select string_agg(pg_temp.sem_ids(concat_ws('|', p.escopo, p.modo, p.estado, p.itens::text, p.parametros::text, p.fora::text, p.carga::text,
                                              p.textos::text, p.pontuacao::text)), E'\n' order by p.criada_em, p.os_alvo::text)
    into v4
    from public.agenda_propostas p
   where p.criada_em = v_ag;
  select coalesce(string_agg(concat_ws('|', q.tipo, q.chave, q.texto, q.opcoes::text, q.recomendacao, q.modo, q.estado), E'\n' order by q.chave), '')
    into v5
    from public.agenda_perguntas q
   where q.criada_em = v_ag;
  return md5(v1) || md5(v2) || md5(v3) || md5(coalesce(v4, '')) || md5(v5) || ':' || length(v2) || ':' || length(coalesce(v4, ''));
end $f$;

-- ── M1. Sombra = antes, em md5 e sem projeção ──────────────────────────────────────────────────────────────────────
do $m1$
declare
  v_res  jsonb := '[]'::jsonb;
  c      record;
  v_novo text;
  v_ant  text;
  v_oss  uuid[];
  v_dif  text;
  v_tot  int := 0;
begin
  if not pg_temp.carregada() or not pg_temp.textos_ok() then
    insert into _resultado values ('M1 sombra = antes', true, 'PULADO: sem as fixtures e as migrations como texto (rode pela bancada)');
    return;
  end if;
  v_oss := array(select so.id from public.service_orders so
                  where so.service_order_number ~ '^OS-(J|D)[0-9]+$' or so.service_order_number like 'OS-9717_' order by 1);
  for c in select * from (values
      ('sombra, J', 'sombra', date '2027-07-16', date '2027-07-12'), ('desligado, J', 'desligado', date '2027-07-16', date '2027-07-12'),
      ('sombra, dezembro', 'sombra', date '2026-11-30', date '2026-11-30'), ('desligado, dezembro', 'desligado', date '2026-11-30', date '2026-11-30'),
      ('sombra, novembro', 'sombra', date '2026-11-04', date '2026-11-02')) t(nome, modo, hoje, ini) loop
    begin
      perform pg_temp.gestor();
      perform pg_temp.modos(c.modo);
      v_novo := pg_temp.retrato(c.hoje, v_oss, c.ini);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    begin
      perform pg_temp.gestor();
      perform pg_temp.modos(c.modo);
      perform pg_temp.motor_da_7c();
      v_ant := pg_temp.retrato(c.hoje, v_oss, c.ini);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    v_tot := v_tot + 1;
    if v_novo is distinct from v_ant then
      v_dif := concat_ws('; ', v_dif, format('%s: %s × %s', c.nome, v_novo, v_ant));
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'M1 com os 6 modos desligados e em sombra e os locais cadastrados, a semana, a OS, o contexto, os itens, os parâmetros, o fora, a carga, os textos e as perguntas gravadas são os das 11 funções da 7c rodando no lugar, em md5 e sem projeção',
    v_dif is null, coalesce(v_dif, format('%s retratos iguais; o último, %s', v_tot, v_ant)));
  perform pg_temp.gravar(v_res);
end
$m1$;

-- ── M1b. Chave ausente fora de ligado (R6.8-3) ─────────────────────────────────────────────────────────────────────
do $m1b$
declare
  v_res jsonb := '[]'::jsonb;
  v     jsonb;
  v_ctx jsonb;
  v_it  text[];
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('M1b chave ausente', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.gestor();
    perform pg_temp.modos('sombra');
    v := pg_temp.j(array['OS-J3', 'OS-J6', 'OS-J7', 'OS-J9', 'OS-J10']);
    v_ctx := public._agenda_contexto(date '2027-07-12', date '2027-08-29', date '2027-07-16', '{}'::uuid[], pg_temp.lista(array['OS-J3', 'OS-J6']));
    v_it := array(select k from jsonb_array_elements(v -> 'itens') i, jsonb_object_keys(i) k
                   where k in ('viagem', 'imax_os', 'local_texto', 'suposicoes', 'fora_h', 'local_txt', 'mesmo_dia', 'troca', 'local_curto'));
    v_res := pg_temp.ok(v_res, 'M1b.1 em sombra, nenhum item da proposta tem viagem, imax_os, local_texto, suposicoes, fora_h, local_txt nem local_curto',
      cardinality(v_it) = 0, array_to_string(v_it, ', '));
    v_res := pg_temp.ok(v_res, 'M1b.2 em sombra, o contexto não tem mun, mun_nomes nem nenhuma chave pat*',
      not (v_ctx ?| array['mun', 'mun_nomes', 'pat', 'pat_max', 'pat_nomes', 'pat_ent', 'pat_sai', 'pat_int', 'pat_ret', 'pat_tent']),
      (select string_agg(k, ', ') from jsonb_object_keys(v_ctx) k where k like 'pat%' or k like 'mun%'));
    -- o contraste: com os modos ligados, as chaves existem (a prova de cima não é vazia)
    perform pg_temp.modos('ligado');
    v_ctx := public._agenda_contexto(date '2027-07-12', date '2027-08-29', date '2027-07-16', '{}'::uuid[], pg_temp.lista(array['OS-J3', 'OS-J6']));
    v_res := pg_temp.ok(v_res, 'M1b.3 com os modos ligados, o contexto tem mun, mun_nomes e todas as chaves pat*',
      v_ctx ?& array['mun', 'mun_nomes', 'pat', 'pat_max', 'pat_nomes', 'pat_ent', 'pat_sai', 'pat_int', 'pat_ret', 'pat_tent'],
      (select string_agg(k, ', ') from jsonb_object_keys(v_ctx) k where k like 'pat%' or k like 'mun%'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$m1b$;

-- ── M1c. A prova sem relógio: nada chama as leituras do local em sombra (R6.8) ─────────────────────────────────────
do $m1c$
declare
  v_res jsonb := '[]'::jsonb;
  v_n   bigint;
  v     jsonb;
  v_h   date := date '2027-07-16';
  v_ag  timestamptz := pg_temp.em(date '2027-07-16', '16:20');
  v_err int;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('M1c prova sem relógio', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.gestor();
    perform pg_temp.modos('sombra');
    -- as versões que lançam contam antes: a vigia engole exceção por passo, e só o erro não prova nada; a sequência não volta com o savepoint
    create temp sequence m1c_chamadas;
    create or replace function public._agenda_local_resolvido(p_os uuid, p_hoje date) returns jsonb language plpgsql stable set search_path to 'public', 'pg_temp' as $x$
    begin perform nextval('m1c_chamadas'); raise exception 'M1c: _agenda_local_resolvido chamada em sombra'; end $x$;
    create or replace function public._agenda_local_mascara(p_os uuid, p_d_ini date, p_d_fim date, p_hoje date, p_local jsonb default null) returns jsonb language plpgsql stable set search_path to 'public', 'pg_temp' as $x$
    begin perform nextval('m1c_chamadas'); raise exception 'M1c: _agenda_local_mascara chamada em sombra'; end $x$;
    create or replace function public._agenda_viagem_da_os(p_os uuid, p_hoje date, p_local jsonb default null) returns jsonb language plpgsql stable set search_path to 'public', 'pg_temp' as $x$
    begin perform nextval('m1c_chamadas'); raise exception 'M1c: _agenda_viagem_da_os chamada em sombra'; end $x$;
    create or replace function public._agenda_estado_do_bem(p_os uuid, p_hoje date) returns jsonb language plpgsql stable set search_path to 'public', 'pg_temp' as $x$
    begin perform nextval('m1c_chamadas'); raise exception 'M1c: _agenda_estado_do_bem chamada em sombra'; end $x$;
    v := public.agenda_vigiar(v_h, v_ag);
    v := public.agenda_propor('semana', null, null, null, '{}'::jsonb, false, 'motor', null, v_h, v_ag);
    v := public.agenda_propor('os', null, null, pg_temp.lista(array['OS-J1', 'OS-J2', 'OS-J3', 'OS-J6', 'OS-J7', 'OS-J9']), '{}'::jsonb, true, 'vigia', null, v_h, v_ag);
    v := public.agenda_cliente_vigiar(v_h, v_ag);
    v := public._agenda_contexto(date '2027-07-12', date '2027-08-29', v_h, '{}'::uuid[], pg_temp.lista(array['OS-J1']));
    select count(*) into v_err from public.app_error_logs e where e.message like 'M1c:%';
    select last_value - 1 + case when is_called then 1 else 0 end into v_n from m1c_chamadas;
    v_res := pg_temp.ok(v_res, 'M1c em sombra, agenda_vigiar, agenda_propor (semana e OS, gravando), agenda_cliente_vigiar e o contexto rodam sem nenhuma chamada às 4 leituras do local e sem erro',
      v_n = 0 and v_err = 0, format('chamadas %s, erros %s', v_n, v_err));
    -- o contraste: com o modo ligado, a mesma prova acusa (senão ela não prova nada)
    perform pg_temp.modo('modo_local_calendario', 'ligado');
    begin
      v := public.agenda_propor('os', null, null, pg_temp.lista(array['OS-J1']), '{}'::jsonb, false, 'vigia', null, v_h, v_ag);
      v_res := pg_temp.ok(v_res, 'M1c.2 o contraste: com o calendário ligado, a versão que lança é chamada', false, 'não lançou');
    exception when others then
      select last_value - 1 + case when is_called then 1 else 0 end into v_n from m1c_chamadas;
      v_res := pg_temp.ok(v_res, 'M1c.2 o contraste: com o calendário ligado, a versão que lança é chamada', sqlerrm like 'M1c:%', sqlerrm);
    end;
    -- a máscara só com o calendário ou o pátio: com a viagem e o mesmo local ligados, o local é lido e a máscara não
    create or replace function public._agenda_local_resolvido(p_os uuid, p_hoje date) returns jsonb language sql stable set search_path to 'public', 'pg_temp' as $x$
      select jsonb_build_object('fonte', 'nenhum', 'texto', 'não sei onde é o serviço', 'suposicao', false) $x$;
    create or replace function public._agenda_viagem_da_os(p_os uuid, p_hoje date, p_local jsonb default null) returns jsonb language sql stable set search_path to 'public', 'pg_temp' as $x$
      select jsonb_build_object('tipo', 'regional', 'extra_por', 0, 'suposicao', false, 'sem_abre_fecha', false) $x$;
    perform pg_temp.modo('modo_local_calendario', 'sombra');
    perform pg_temp.modo('modo_viagem', 'ligado');
    perform pg_temp.modo('modo_mesmo_local', 'ligado');
    begin
      v := public.agenda_propor('os', null, null, pg_temp.lista(array['OS-J3']), '{}'::jsonb, false, 'vigia', null, v_h, v_ag);
      v_res := pg_temp.ok(v_res, 'M1c.3 com a viagem e o mesmo local ligados, a máscara não é lida (R6.8-1: só calendário e pátio)', true, null);
    exception when others then
      v_res := pg_temp.ok(v_res, 'M1c.3 com a viagem e o mesmo local ligados, a máscara não é lida (R6.8-1: só calendário e pátio)', false, sqlerrm);
    end;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$m1c$;

-- O bloco de 5 dias (10 meios-dias), 3 pessoas, sem o dono: o _agenda_tentar_bloco puro, para provar cada chave sem o resto do motor.
create function pg_temp.bloco(p_o jsonb, p_g jsonb default '{}'::jsonb, p_ocup int[] default null, p_fr int[] default null, p_loc int[] default null,
                              p_d0 int default 1) returns jsonb language plpgsql as $f$
begin
  return public._agenda_tentar_bloco(
    jsonb_build_object('nh', 10, 'nd', 5, 'np', 3, 'nw', 1, 'dono', 0, 'wip', 2, 'imax', 2) || p_g,
    array_fill(true, array[5]), array_fill(1, array[5]), array_fill(1, array[30]), array_fill(0, array[10]),
    coalesce(p_ocup, array_fill(0, array[30])), coalesce(p_fr, array_fill(0, array[40])),
    array_fill(10, array[3]), array_fill(0, array[3]), array_fill(10, array[3]), coalesce(p_loc, array_fill(0, array[4])),
    jsonb_build_object('i', 1, 'passos', 4, 'dm', 1, 'dtd', 1) || p_o, p_d0, false, 1);
end $f$;
-- ocup com a pessoa q no meio-dia h na OS x
create function pg_temp.ocupa(p_ocup int[], p_q int, p_h int, p_x int) returns int[] language plpgsql as $f$
declare
  v int[] := coalesce(p_ocup, array_fill(0, array[30]));
begin
  v[(p_q - 1) * 10 + p_h] := p_x;
  return v;
end $f$;
-- O contexto de 10 dias (2 semanas), 2 pessoas e 3 OS, com um pátio de 1 vaga: o _agenda_encaixar puro.
create function pg_temp.ctx(p_x jsonb default '{}'::jsonb) returns jsonb language sql immutable as $f$
  select jsonb_build_object('d_ini', '2027-07-12', 'nd', 10, 'nh', 20, 'np', 2, 'nw', 2, 'dono', 0, 'util', to_jsonb(array_fill(true, array[10])),
           'sem', '[1,1,1,1,1,2,2,2,2,2]'::jsonb, 'cap', to_jsonb(array_fill(1, array[40])), 'curta', to_jsonb(array_fill(0, array[20])),
           'ocup', to_jsonb(array_fill(0, array[40])), 'fr', to_jsonb(array_fill(0, array[80])), 'teto80', '[20,20,20,20]'::jsonb,
           'teto100', '[20,20,20,20]'::jsonb, 'uso_c', '[0,0,0,0]'::jsonb, 'uso_r', '[0,0,0,0]'::jsonb, 'loc', '[0,0,0]'::jsonb)
         || jsonb_build_object('pat', '[1,1,1]'::jsonb, 'pat_max', '[1]'::jsonb, 'pat_nomes', '["Pátio X"]'::jsonb, 'pat_ent', '[0,0,0]'::jsonb,
                               'pat_sai', '[0,0,0]'::jsonb, 'pat_int', '[]'::jsonb, 'pat_ret', 1, 'pat_tent', 3)
         || p_x
$f$;
create function pg_temp.fila(p_x jsonb default '{}'::jsonb) returns jsonb language sql immutable as $f$
  select jsonb_build_object('i', 1, 'os', 'a', 'ordem', 1, 'classe', 2, 'passos', 2, 'est', 1, 'est_cond', 1, 'dm', 1, 'dtd', 1, 'min_h', 1) || p_x
$f$;
create function pg_temp.par(p_x jsonb default '{}'::jsonb) returns jsonb language sql immutable as $f$
  select jsonb_build_object('wip', 2, 'imax', 2, 'inicios', 10, 'semana', false) || p_x
$f$;
-- O cenário D no dia em que a OS-D1 está: Alex, Rafael e Bruno fora da semana; o João só à tarde no dia, com a semana mais carregada que a do Roberto (a
-- ordem de antes dá o Roberto). Sobra a tarde do dia, para o Roberto (em BC de manhã) e o João.
create function pg_temp.d_so_a_tarde() returns void language plpgsql as $f$
begin
  insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, criado_em)
  select p.id, daterange(date '2026-11-30', date '2026-12-04', '[]'), null, 'indisponivel', 'dono', 'não vem (teste)', timestamptz '2026-11-20 10:01-03'
    from public.payees p where p.name in ('Alex', 'Rafael', 'Bruno') and p.active;
  insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, criado_em)
  select p.id, daterange(date '2026-12-01', date '2026-12-01', '[]'), 'manha', 'indisponivel', 'dono', 'só à tarde (teste)', timestamptz '2026-11-20 10:01-03'
    from public.payees p where p.name = 'João' and p.active;
  insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
  select md5('m8:' || x.turno)::uuid, pg_temp.os('OS-J8'), pg_temp.pessoa('João'), date '2026-12-03', x.turno, 'turno', 'execucao', 'publicada', 'motor', timestamptz '2026-11-20 10:01-03'
    from (values ('manha'), ('tarde')) x(turno);
end $f$;

-- ── M2. O calendário ───────────────────────────────────────────────────────────────────────────────────────────────
do $m2$
declare
  v_res  jsonb := '[]'::jsonb;
  v      jsonb;
  v2     jsonb;
  i      jsonb;
  v_ant  text;
  v_adm  uuid;
  v_h    date := date '2027-07-15';
  v_ag   timestamptz := pg_temp.em(date '2027-07-16', '16:20');
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('M2 o calendário', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  v_adm := (select id from public.app_users where role = 'admin' and active order by created_at limit 1);
  begin
    perform pg_temp.gestor();
    perform pg_temp.modos('sombra');
    perform pg_temp.dono(array['OS-J3', 'OS-J4', 'OS-J5', 'OS-J9', 'OS-J10'], 'nunca');
    -- na quinta, sem as publicadas de 20/07 (J1 e J2 enchem as 2 frentes do dia), o J3 pega seg 19 e ter 20: em teste ele cai no feriado; ligado, não
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'replanejado', cancelada_em = v_ag where dia = date '2027-07-20';
    v := public.agenda_propor('os', null, null, pg_temp.lista(array['OS-J3']), '{}'::jsonb, false, 'vigia', null, v_h, pg_temp.em(v_h, '16:20'));
    v_res := pg_temp.ok(v_res, 'M2a em teste, o motorhome suposto no pátio (BC) cai em ter 20/07, que é dia útil da HBR (a régua: sem isto, a prova de baixo não prova nada)',
      date '2027-07-20' = any (pg_temp.dias(pg_temp.item(v, 'OS-J3'))), pg_temp.meios(pg_temp.item(v, 'OS-J3')));
    perform pg_temp.modo('modo_local_calendario', 'ligado');
    v := public.agenda_propor('os', null, null, pg_temp.lista(array['OS-J3']), '{}'::jsonb, false, 'vigia', null, v_h, pg_temp.em(v_h, '16:20'));
    i := pg_temp.item(v, 'OS-J3');
    v_res := pg_temp.ok(v_res, 'M2b com o calendário ligado, o J3 pula 20/07 (seg 19 e qua 21, os 2 dias, sem contar como parado), e o item diz onde',
      pg_temp.n_meios(i) = 4 and pg_temp.dias(i) = array[date '2027-07-19', date '2027-07-21'] and (i ->> 'interrupcoes')::int = 0
      and i ->> 'local_texto' = 'MP Motorhomes (suposição: motorhome vem ao pátio)',
      pg_temp.meios(i) || ' / ' || (i ->> 'local_texto'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.gestor();
    perform pg_temp.modos('sombra');
    perform pg_temp.modo('modo_local_calendario', 'ligado');
    perform pg_temp.dono(array['OS-J3', 'OS-J4', 'OS-J5', 'OS-J9', 'OS-J10'], 'nunca');
    -- o dia pedido pelo dono: a regra 3 não vale para ele, mas o bem fora vale, com o porquê
    v := pg_temp.j(array['OS-J1'], jsonb_build_object('fixar', jsonb_build_array(jsonb_build_object('os', pg_temp.os('OS-J1'), 'de', '2027-07-20'))));
    v_res := pg_temp.ok(v_res, 'M2c o "por que não" do dia pedido: "Lenine (OS-J1): não cabe ter 20/07: ter 20/07 é feriado em Balneário Camboriú."',
      pg_temp.fora(v, 'OS-J1') ->> 'texto' = 'Lenine (OS-J1): não cabe ter 20/07: ter 20/07 é feriado em Balneário Camboriú.'
      and pg_temp.fora(v, 'OS-J1') ->> 'motivo' = 'fixar_nao_cabe', pg_temp.fora(v, 'OS-J1')::text);
    -- a violação local só com a variável, a da rodada diária (R6.8-4)
    v := pg_temp.j(array['OS-J1', 'OS-J2']);
    v_res := pg_temp.ok(v_res, 'M2d sem agenda.local_violacao, a publicada em 20/07 não viola, nem com o modo ligado: a vigia fica igual (R6.8-4)',
      not exists (select 1 from jsonb_array_elements(v -> 'itens') x where x ->> 'motivo' = 'local'), pg_temp.projecao(v));
    perform set_config('agenda.local_violacao', 'on', true);
    v := pg_temp.j(array['OS-J1', 'OS-J2']);
    i := (select x from jsonb_array_elements(v -> 'itens') x where x ->> 'motivo' = 'local');
    v_res := pg_temp.ok(v_res, 'M2e com a variável, a violação local da publicada, com o texto: "Lenine (OS-J1): sai ter 20/07 — o local não recebe a equipe nesse dia." e o J1 volta depois do feriado; o J2 fica (a Marina Itajaí não fecha em 20/07)',
      i ->> 'texto' = 'Lenine (OS-J1): sai ter 20/07 — o local não recebe a equipe nesse dia.' and (i ->> 'violada')::boolean
      and date '2027-07-20' < (pg_temp.dias(pg_temp.item(v, 'OS-J1')))[1]
      and not exists (select 1 from jsonb_array_elements(v -> 'itens') x where x ->> 'op' = 'cancelar' and x ->> 'numero' = 'OS-J2'),
      pg_temp.projecao(v));
    -- a ordem (R6.9-8): o dia fechado que também está com o bem fora é local, não cliente; sem a variável, cliente
    update public.os_planejamento set bem_indisponivel = datemultirange(daterange(date '2027-07-20', date '2027-07-20', '[]')) where service_order_id = pg_temp.os('OS-J1');
    v := pg_temp.j(array['OS-J1']);
    v_res := pg_temp.ok(v_res, 'M2e2 a violação local vem antes do bem fora (R6.9-8): o mesmo dia, motivo local',
      exists (select 1 from jsonb_array_elements(v -> 'itens') x where x ->> 'motivo' = 'local') and not exists (select 1 from jsonb_array_elements(v -> 'itens') x where x ->> 'motivo' = 'cliente'), pg_temp.projecao(v));
    update public.os_planejamento set bem_indisponivel = '{}'::datemultirange where service_order_id = pg_temp.os('OS-J1');
    -- em teste, a variável não acorda nada
    perform pg_temp.modo('modo_local_calendario', 'sombra');
    v := pg_temp.j(array['OS-J1', 'OS-J2']);
    v_res := pg_temp.ok(v_res, 'M2f com a variável e o modo em teste, nenhuma violação local (o modo vale, pelo _agenda_local_modo)',
      not exists (select 1 from jsonb_array_elements(v -> 'itens') x where x ->> 'motivo' = 'local'), pg_temp.projecao(v));
    perform pg_temp.modo('modo_local_calendario', 'ligado');
    -- o que o dono fixou não cai
    update public.agenda_alocacoes set estado = 'fixada', fixado_por = 'dono' where service_order_id = pg_temp.os('OS-J1');
    v := pg_temp.j(array['OS-J1']);
    v_res := pg_temp.ok(v_res, 'M2g o fixado pelo dono fica, com a variável e o modo ligado: nenhuma saída local',
      not exists (select 1 from jsonb_array_elements(v -> 'itens') x where x ->> 'op' = 'cancelar'), pg_temp.projecao(v));
    perform set_config('agenda.local_violacao', '', true);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- O horário do local conferido: a Marina Itajaí (conferida) só abre à tarde
  begin
    perform pg_temp.gestor();
    perform pg_temp.modos('sombra');
    perform pg_temp.dono(array['OS-J9', 'OS-J10'], 'nunca');
    update public.agenda_locais set abre = time '13:00', atualizado_por = v_adm where nome = 'Marina Itajaí';
    v := pg_temp.j(array['OS-J9']);
    i := pg_temp.item(v, 'OS-J9');
    v_res := pg_temp.ok(v_res, 'M2h em teste, a OS de meio dia na Marina Itajaí vai de manhã (a abertura às 13:00 não pesa)',
      pg_temp.meios(i) like '%manha', pg_temp.meios(i));
    perform pg_temp.modo('modo_local_calendario', 'ligado');
    v := pg_temp.j(array['OS-J9']);
    i := pg_temp.item(v, 'OS-J9');
    v_res := pg_temp.ok(v_res, 'M2i com o calendário ligado, a Marina Itajaí conferida só à tarde: fora_h pula a manhã', pg_temp.meios(i) like '%tarde', pg_temp.meios(i));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- A violação do meio-dia e a da retirada: a publicada do J12 em seg 26/07, na Marina Itajaí (manhã e tarde, Rafael)
  begin
    perform pg_temp.gestor();
    perform pg_temp.modos('sombra');
    perform pg_temp.modo('modo_local_calendario', 'ligado');
    perform set_config('agenda.local_violacao', 'on', true);
    update public.agenda_locais set abre = time '13:00', atualizado_por = v_adm where nome = 'Marina Itajaí';
    v2 := public._agenda_violacoes(array[pg_temp.os('OS-J12')], array(select k.service_order_id from public.os_carteira(date '2027-07-16') k), false,
            jsonb_build_object(pg_temp.os('OS-J12')::text, jsonb_build_object('pront', public.os_prontidao(pg_temp.os('OS-J12'), date '2027-07-16'),
                                                                              'meios', public.agenda_meios_da_os(pg_temp.os('OS-J12'), date '2027-07-16'))),
            date '2027-07-16', date '2027-07-19');
    v_res := pg_temp.ok(v_res, 'M2o a violação do meio-dia fora do horário: só a manhã é local; a tarde vai junto como replanejado',
      (select count(*) from jsonb_array_elements(v2) x where x ->> 'motivo' = 'local' and x ->> 'turno' = 'manha') = 1
      and (select count(*) from jsonb_array_elements(v2) x where x ->> 'motivo' = 'local' and x ->> 'turno' = 'tarde') = 0, v2::text);
    update public.agenda_locais set abre = time '08:00', atualizado_por = v_adm where nome = 'Marina Itajaí';
    update public.os_planejamento set retirada_em = date '2027-07-26', entrada_fonte = 'dono' where service_order_id = pg_temp.os('OS-J12');
    v2 := public._agenda_violacoes(array[pg_temp.os('OS-J12')], array(select k.service_order_id from public.os_carteira(date '2027-07-16') k), false,
            jsonb_build_object(pg_temp.os('OS-J12')::text, jsonb_build_object('pront', public.os_prontidao(pg_temp.os('OS-J12'), date '2027-07-16'),
                                                                              'meios', public.agenda_meios_da_os(pg_temp.os('OS-J12'), date '2027-07-16'))),
            date '2027-07-16', date '2027-07-19');
    v_res := pg_temp.ok(v_res, 'M2p sem o pátio ligado, a retirada não viola', jsonb_array_length(v2) = 0, v2::text);
    perform pg_temp.modo('modo_patio', 'ligado');
    v2 := public._agenda_violacoes(array[pg_temp.os('OS-J12')], array(select k.service_order_id from public.os_carteira(date '2027-07-16') k), false,
            jsonb_build_object(pg_temp.os('OS-J12')::text, jsonb_build_object('pront', public.os_prontidao(pg_temp.os('OS-J12'), date '2027-07-16'),
                                                                              'meios', public.agenda_meios_da_os(pg_temp.os('OS-J12'), date '2027-07-16'))),
            date '2027-07-16', date '2027-07-19');
    v_res := pg_temp.ok(v_res, 'M2q com o pátio ligado, a publicada no dia da retirada em diante é local (a manhã e a tarde)',
      (select count(*) from jsonb_array_elements(v2) x where x ->> 'motivo' = 'local') = 2, v2::text);
    perform set_config('agenda.local_violacao', '', true);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- fora_h no bloco puro
  v := pg_temp.bloco('{"fora_h": [3]}');
  v_res := pg_temp.ok(v_res, 'M2j fora_h: o meio-dia é pulado (sem passo) e o bloco segue',
    v -> 'h' = '[1, 2, 4, 5]'::jsonb and (v ->> 'int')::int = 0, v -> 'h' ->> 0);
  v := pg_temp.bloco('{"fora_h": [3, 4]}');
  v_res := pg_temp.ok(v_res, 'M2k fora_h nos dois meios-dias do dia: o dia não conta como dia parado',
    v -> 'h' = '[1, 2, 5, 6]'::jsonb and (v ->> 'int')::int = 0, v::text);
  v := pg_temp.bloco('{"fora_h": [3, 4], "imax_os": 0}');
  v_res := pg_temp.ok(v_res, 'M2l e nem com imax_os 0 ele derruba o bloco', v is not null and v -> 'h' = '[1, 2, 5, 6]'::jsonb, v::text);
  v := pg_temp.bloco('{"fora_h": [1]}');
  v_res := pg_temp.ok(v_res, 'M2m o 1º meio-dia fora do horário: o bloco começa na tarde do mesmo dia', (v ->> 'ini')::int = 2, v::text);
  v := pg_temp.bloco('{"bem": [2]}');
  v_res := pg_temp.ok(v_res, 'M2n a referência do bloco puro: sem as chaves, os dias do bem fora são pulados', v -> 'h' = '[1, 2, 5, 6]'::jsonb, v::text);
  perform pg_temp.gravar(v_res);
end
$m2$;

-- ── M3. O acesso não é filtro de pessoa (AG7-14) ───────────────────────────────────────────────────────────────────
do $m3$
declare
  v_res jsonb := '[]'::jsonb;
  a     text;
  b     text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('M3 o acesso', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.gestor();
    perform pg_temp.modos('sombra');
    a := pg_temp.j(array['OS-J2'])::text;
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    b := pg_temp.j(array['OS-J2'])::text;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M3 com modo_local_autorizacao ligado, J2 (só o Roberto autorizado) sai igual ao de teste, em md5: o acesso não muda pessoa nem dia',
    md5(a) = md5(b) and length(a) > 100, md5(a));
  perform pg_temp.gravar(v_res);
end
$m3$;

-- ── M4. O pátio ────────────────────────────────────────────────────────────────────────────────────────────────────
do $m4$
declare
  v_res  jsonb := '[]'::jsonb;
  v      jsonb;
  i      jsonb;
  f      jsonb;
  v_adm  uuid;
  v_som  text;
  v_h    date := date '2027-07-16';
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('M4 o pátio', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  v_adm := (select id from public.app_users where role = 'admin' and active order by created_at limit 1);
  begin
    perform pg_temp.gestor();
    perform pg_temp.modos('sombra');
    perform pg_temp.dono(array['OS-J3', 'OS-J4', 'OS-J5', 'OS-J8', 'OS-J9', 'OS-J10', 'OS-J11'], 'nunca');
    v := pg_temp.j(array['OS-J3', 'OS-J4', 'OS-J5']);
    v_som := pg_temp.projecao(v);
    v_res := pg_temp.ok(v_res, 'M4a em teste, os 3 motorhomes entram sem olhar o pátio: J5 em sex 23/07, com J3 e J4 lá',
      (pg_temp.dias(pg_temp.item(v, 'OS-J5')))[1] = date '2027-07-23', v_som);
    perform pg_temp.modo('modo_patio', 'ligado');
    update public.agenda_locais set vagas = 2, atualizado_por = v_adm where tipo = 'patio_hbr';
    v := pg_temp.j(array['OS-J3', 'OS-J4', 'OS-J5']);
    v_res := pg_temp.ok(v_res, 'M4b com 2 vagas, o 3º entra quando um sai: J5 só em seg 26/07 (J3 sai sex 23, o d.u. depois do fim)',
      (pg_temp.dias(pg_temp.item(v, 'OS-J5')))[1] = date '2027-07-26' and (pg_temp.dias(pg_temp.item(v, 'OS-J3')))[1] = date '2027-07-21'
      and pg_temp.n_meios(pg_temp.item(v, 'OS-J5')) = 4, pg_temp.projecao(v));
    -- o "por que não" lê o pátio como o motor o deixou: J3 pedido em qua 21 ocupa a 2ª vaga (a 1ª é do J1 publicado), e J4, pedido no mesmo dia, já não cabe
    v := pg_temp.j(array['OS-J3', 'OS-J4'], jsonb_build_object('fixar', jsonb_build_array(jsonb_build_object('os', pg_temp.os('OS-J3'), 'de', '2027-07-21'),
                                                                                           jsonb_build_object('os', pg_temp.os('OS-J4'), 'de', '2027-07-21'))));
    v_res := pg_temp.ok(v_res, 'M4b2 o "por que não" vê o que o motor acabou de ocupar: "não cabe qua 21/07: a MP Motorhomes está cheia nesse dia (2 vagas)."',
      pg_temp.fora(v, 'OS-J4') ->> 'texto' = 'Renato (OS-J4): não cabe qua 21/07: a MP Motorhomes está cheia nesse dia (2 vagas).', pg_temp.projecao(v) || ' / ' || (pg_temp.fora(v, 'OS-J4')::text));
    -- o plano vigente ocupa: com 1 vaga, o J1 publicado (ter 20, sai qua 21) segura o pátio
    update public.agenda_locais set vagas = 1, atualizado_por = v_adm where tipo = 'patio_hbr';
    v := pg_temp.j(array['OS-J3']);
    v_res := pg_temp.ok(v_res, 'M4b3 com 1 vaga, o plano vigente ocupa: o J1 publicado em ter 20 fica até qua 21, e o J3 começa qui 22',
      (pg_temp.dias(pg_temp.item(v, 'OS-J3')))[1] = date '2027-07-22', pg_temp.projecao(v));
    update public.agenda_locais set vagas = null, atualizado_por = v_adm where tipo = 'patio_hbr';
    v := pg_temp.j(array['OS-J3', 'OS-J4', 'OS-J5']);
    v_res := pg_temp.ok(v_res, 'M4c sem vagas ditas, nada limita: a mesma projeção do teste, e nenhum patio_cheio', pg_temp.projecao(v) = v_som, pg_temp.projecao(v));
    -- o bem parado sem plano ocupa até o fim do horizonte; com 1 vaga, ninguém entra
    update public.agenda_locais set vagas = 1, atualizado_por = v_adm where tipo = 'patio_hbr';
    update public.os_planejamento set entrada_em = date '2027-07-01', entrada_fonte = 'dono' where service_order_id = pg_temp.os('OS-J11');
    v := pg_temp.j(array['OS-J3']);
    f := pg_temp.fora(v, 'OS-J3');
    v_res := pg_temp.ok(v_res, 'M4d o bem parado no pátio, sem plano e fora da fila, ocupa: com 1 vaga, o J3 vai ao fora com motivo sem_encaixe, patio_cheio e o texto próprio (R6.3-7, R6.5)',
      f ->> 'motivo' = 'sem_encaixe' and (f ->> 'patio_cheio')::boolean
      and f ->> 'texto' = 'Vanderlei (OS-J3): a MP Motorhomes fica cheia nas próximas semanas (1 vaga). Me diga se cabe mais um, ou quando outro motorhome sai.'
      and pg_temp.item(v, 'OS-J3') is null, f::text);
    v := pg_temp.j(array['OS-J3'], jsonb_build_object('fixar', jsonb_build_array(jsonb_build_object('os', pg_temp.os('OS-J3'), 'de', '2027-07-21'))));
    f := pg_temp.fora(v, 'OS-J3');
    v_res := pg_temp.ok(v_res, 'M4e o dia pedido pelo dono com o pátio cheio: "não cabe qua 21/07: a MP Motorhomes está cheia nesse dia (1 vaga)."',
      f ->> 'texto' = 'Vanderlei (OS-J3): não cabe qua 21/07: a MP Motorhomes está cheia nesse dia (1 vaga).' and f ->> 'motivo' = 'fixar_nao_cabe', f::text);
    -- a entrada no EST: o motorhome chega em 27/07
    update public.os_planejamento set entrada_em = null, entrada_fonte = null where service_order_id = pg_temp.os('OS-J11');
    update public.agenda_locais set vagas = 3, atualizado_por = v_adm where tipo = 'patio_hbr';
    update public.os_planejamento set entrada_em = date '2027-07-27', entrada_fonte = 'dono' where service_order_id = pg_temp.os('OS-J3');
    v := pg_temp.j(array['OS-J3']);
    v_res := pg_temp.ok(v_res, 'M4f a entrada entra no EST: com o motorhome chegando em 27/07, o J3 começa aí',
      (pg_temp.dias(pg_temp.item(v, 'OS-J3')))[1] = date '2027-07-27', pg_temp.projecao(v));
    perform pg_temp.modo('modo_patio', 'sombra');
    v := pg_temp.j(array['OS-J3']);
    v_res := pg_temp.ok(v_res, 'M4g em teste, a entrada não pesa', (pg_temp.dias(pg_temp.item(v, 'OS-J3')))[1] = date '2027-07-21', pg_temp.projecao(v));
    perform pg_temp.modo('modo_patio', 'ligado');
    update public.os_planejamento set entrada_em = null, entrada_fonte = 'dono', retirada_em = date '2027-07-22' where service_order_id = pg_temp.os('OS-J3');
    v := pg_temp.j(array['OS-J3']);
    v_res := pg_temp.ok(v_res, 'M4h a retirada fecha os dias a partir dela: o bem sai em 22/07 e os 2 dias não cabem antes (fora, sem encaixe)',
      pg_temp.item(v, 'OS-J3') is null, pg_temp.projecao(v));
    perform pg_temp.modo('modo_patio', 'sombra');
    v := pg_temp.j(array['OS-J3']);
    v_res := pg_temp.ok(v_res, 'M4i em teste, a retirada não pesa', pg_temp.n_meios(pg_temp.item(v, 'OS-J3')) = 4, pg_temp.projecao(v));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- O encaixe puro: cada caminho que fixa bloco passa pelo pátio (R6.8-6)
  v := public._agenda_encaixar(pg_temp.ctx('{"pat_int": [{"k": 1, "i": 9, "d1": 1, "d2": 3}]}'), jsonb_build_array(pg_temp.fila()), pg_temp.par());
  v_res := pg_temp.ok(v_res, 'M4j o compromisso: com o pátio ocupado até o dia 3, o bloco de 1 dia começa no dia 4; a saída ganha pat_int com ele (d2 = o d.u. depois do fim)',
    (v -> 'colocadas' -> 0 ->> 'd0')::int = 4 and v -> 'colocadas' -> 0 ->> 'tipo' = 'compromisso'
    and v -> 'pat_int' @> '[{"k": 1, "i": 1, "d1": 4, "d2": 5}]'::jsonb, v::text);
  v := public._agenda_encaixar(pg_temp.ctx('{"pat_int": [{"k": 1, "i": 9, "d1": 1, "d2": 3}], "teto80": [0,0,0,0]}'), jsonb_build_array(pg_temp.fila()), pg_temp.par());
  v_res := pg_temp.ok(v_res, 'M4k a reserva por teto (chamadas 6 e 7): sem lugar na carga, a reserva até 100% também espera o pátio: dia 4',
    v -> 'colocadas' -> 0 ->> 'reserva_de' = 'teto' and (v -> 'colocadas' -> 0 ->> 'd0')::int = 4
    and v -> 'pat_int' @> '[{"k": 1, "i": 1, "d1": 4}]'::jsonb, v::text);
  v := public._agenda_encaixar(pg_temp.ctx('{"pat_int": [{"k": 1, "i": 9, "d1": 1, "d2": 3}]}'), jsonb_build_array(pg_temp.fila('{"classe": 3}')), pg_temp.par());
  v_res := pg_temp.ok(v_res, 'M4l a reserva condicionada (chamadas 8 e 9) também: dia 4',
    v -> 'colocadas' -> 0 ->> 'reserva_de' = 'condicionada' and (v -> 'colocadas' -> 0 ->> 'd0')::int = 4
    and v -> 'pat_int' @> '[{"k": 1, "i": 1, "d1": 4}]'::jsonb, v::text);
  v := public._agenda_encaixar(pg_temp.ctx('{"pat_int": [{"k": 1, "i": 9, "d1": 1, "d2": 10}]}'), jsonb_build_array(pg_temp.fila('{"classe": 3}')), pg_temp.par());
  v_res := pg_temp.ok(v_res, 'M4m a condicionada sem vaga: fora sem_encaixe com patio_cheio, e não sem_reserva',
    v -> 'fora' = '[{"i": 1, "motivo": "sem_encaixe", "patio_cheio": true}]'::jsonb and jsonb_array_length(v -> 'colocadas') = 0, v::text);
  v := public._agenda_encaixar(pg_temp.ctx('{"pat_int": [{"k": 1, "i": 9, "d1": 1, "d2": 10}], "teto80": [0,0,0,0]}'), jsonb_build_array(pg_temp.fila()), pg_temp.par());
  v_res := pg_temp.ok(v_res, 'M4n a por teto sem vaga: sem bloco (o fora é o do compromisso, sem_encaixe, que aqui é da carga: a reserva é que não saiu)',
    jsonb_array_length(v -> 'colocadas') = 0 and v -> 'fora' -> 0 ->> 'motivo' = 'sem_encaixe', v::text);
  v := public._agenda_encaixar(pg_temp.ctx('{"pat_int": [{"k": 1, "i": 9, "d1": 1, "d2": 10}]}'), jsonb_build_array(pg_temp.fila()), pg_temp.par());
  v_res := pg_temp.ok(v_res, 'M4o o compromisso sem vaga em nenhuma tentativa: fora sem_encaixe com patio_cheio, e não vai à reserva por teto (a reserva é de quem não coube na carga)',
    v -> 'fora' = '[{"i": 1, "motivo": "sem_encaixe", "patio_cheio": true}]'::jsonb and jsonb_array_length(v -> 'colocadas') = 0, v::text);
  -- as tentativas: 3 intervalos separados por 1 dia livre curto demais para o bloco de 2 dias; a 4ª tentativa acha
  v := public._agenda_encaixar(pg_temp.ctx('{"pat_int": [{"k": 1, "i": 7, "d1": 1, "d2": 2}, {"k": 1, "i": 8, "d1": 4, "d2": 5}, {"k": 1, "i": 9, "d1": 7, "d2": 8}]}'),
                               jsonb_build_array(pg_temp.fila('{"passos": 2, "est": 1}')), pg_temp.par());
  v_res := pg_temp.ok(v_res, 'M4p o pátio com folgas de 1 dia: tenta de novo depois de cada dia cheio, até o bloco caber (d1 a d2 com a retirada: dias 9 e 10)',
    (v -> 'colocadas' -> 0 ->> 'd0')::int = 9, v::text);
  v := public._agenda_encaixar(pg_temp.ctx('{"pat_tent": 1, "pat_int": [{"k": 1, "i": 7, "d1": 1, "d2": 2}, {"k": 1, "i": 8, "d1": 4, "d2": 5}, {"k": 1, "i": 9, "d1": 7, "d2": 8}]}'),
                               jsonb_build_array(pg_temp.fila('{"passos": 2, "est": 1}')), pg_temp.par());
  v_res := pg_temp.ok(v_res, 'M4q patio_tentativas 1: acaba antes de achar: patio_cheio (o parâmetro manda), sem reserva por teto (ela é de quem não coube na carga)',
    v -> 'fora' = '[{"i": 1, "motivo": "sem_encaixe", "patio_cheio": true}]'::jsonb and jsonb_array_length(v -> 'colocadas') = 0, v::text);
  v := public._agenda_encaixar(pg_temp.ctx('{"pat_tent": 2, "pat_int": [{"k": 1, "i": 7, "d1": 1, "d2": 2}, {"k": 1, "i": 8, "d1": 4, "d2": 5}, {"k": 1, "i": 9, "d1": 7, "d2": 8}]}'),
                               jsonb_build_array(pg_temp.fila('{"passos": 2, "est": 1}')), pg_temp.par());
  v_res := pg_temp.ok(v_res, 'M4q2 sem vaga nas tentativas do compromisso, a OS não vai à reserva por teto, que acharia lugar com as tentativas dela: a reserva é de quem não coube na carga',
    v -> 'fora' = '[{"i": 1, "motivo": "sem_encaixe", "patio_cheio": true}]'::jsonb and jsonb_array_length(v -> 'colocadas') = 0, v::text);
  v := public._agenda_encaixar(pg_temp.ctx('{"pat_int": [{"k": 1, "i": 9, "d1": 1, "d2": 8}]}'), jsonb_build_array(pg_temp.fila('{"passos": 2, "est": 1}')), pg_temp.par());
  v_res := pg_temp.ok(v_res, 'M4r o serviço de vários dias: a tentativa pula os dias cheios seguidos de uma vez (com 1 vaga presa até o dia 8, entra no 9, e não dá "cheio" à toa)',
    (v -> 'colocadas' -> 0 ->> 'd0')::int = 9, v::text);
  -- dois da fila: quem entra primeiro ocupa, e o segundo vê
  v := public._agenda_encaixar(pg_temp.ctx(), jsonb_build_array(pg_temp.fila(), pg_temp.fila('{"i": 2, "os": "b", "ordem": 2}')), pg_temp.par());
  v_res := pg_temp.ok(v_res, 'M4s a 2ª da fila vê o que a 1ª ocupou: com 1 vaga, a 1ª no dia 1 (sai no d.u. seguinte, o 2), a 2ª no dia 3',
    (v -> 'colocadas' -> 0 ->> 'd0')::int = 1 and (v -> 'colocadas' -> 1 ->> 'd0')::int = 3, v::text);
  -- a própria OS não conta contra ela (i = p_i)
  v := public._agenda_encaixar(pg_temp.ctx('{"pat_int": [{"k": 1, "i": 1, "d1": 1, "d2": 3}]}'), jsonb_build_array(pg_temp.fila()), pg_temp.par());
  v_res := pg_temp.ok(v_res, 'M4t o que a própria OS já ocupa não conta contra ela', (v -> 'colocadas' -> 0 ->> 'd0')::int = 1, v::text);
  -- OS sem pátio
  v := public._agenda_encaixar(pg_temp.ctx('{"pat": [0,0,0], "pat_int": [{"k": 1, "i": 9, "d1": 1, "d2": 10}]}'), jsonb_build_array(pg_temp.fila()), pg_temp.par());
  v_res := pg_temp.ok(v_res, 'M4u a OS fora de pátio não olha o pátio, e o dela não entra em pat_int',
    (v -> 'colocadas' -> 0 ->> 'd0')::int = 1 and jsonb_array_length(v -> 'pat_int') = 1, v::text);
  -- o pedido do dono
  v := public._agenda_encaixar(pg_temp.ctx('{"pat_int": [{"k": 1, "i": 9, "d1": 1, "d2": 3}]}'),
                               jsonb_build_array(pg_temp.fila('{"fixar_de": 2, "fixar_ate": 2}')), pg_temp.par());
  v_res := pg_temp.ok(v_res, 'M4v o dia pedido pelo dono com o pátio cheio: fixar_nao_cabe, sem patio_cheio (o texto é o "não cabe <dia>")',
    v -> 'fora' = '[{"i": 1, "motivo": "fixar_nao_cabe"}]'::jsonb, v::text);
  v := public._agenda_encaixar(pg_temp.ctx('{"pat_int": [{"k": 1, "i": 9, "d1": 1, "d2": 3}]}'),
                               jsonb_build_array(pg_temp.fila('{"fixar_de": 2, "fixar_ate": 6}')), pg_temp.par());
  v_res := pg_temp.ok(v_res, 'M4w o pedido com uma faixa de dias: tenta dentro dela, depois do dia cheio', (v -> 'colocadas' -> 0 ->> 'd0')::int = 4, v::text);
  -- a dupla inferida (a 3ª chamada) dentro do laço: o bloco que entra é o de depois da volta
  v := public._agenda_encaixar(pg_temp.ctx('{"pat_int": [{"k": 1, "i": 9, "d1": 1, "d2": 3}]}'),
                               jsonb_build_array(pg_temp.fila('{"passos": 2, "passos1": 2, "dk": [1, 1], "dupla_fonte": "regra"}')),
                               pg_temp.par('{"dupla_modo": "ligado", "dupla_espera": 0}'));
  v_res := pg_temp.ok(v_res, 'M4x a dupla inferida passa pelo pátio: dia 4', (v -> 'colocadas' -> 0 ->> 'd0')::int = 4, v::text);
  -- a reserva de pátio 2c não ocupa vaga
  v := public._agenda_encaixar(pg_temp.ctx('{"pat_int": [{"k": 1, "i": 9, "d1": 1, "d2": 10}]}'),
                               jsonb_build_array(pg_temp.fila('{"classe": 1, "passos": 0, "patio_passos": 2, "patio_bem": [], "est_patio": 1}')), pg_temp.par());
  v_res := pg_temp.ok(v_res, 'M4y a reserva de pátio (2c, a 10ª chamada) não olha nem ocupa vaga: entra com o pátio cheio e fora de pat_int',
    v -> 'colocadas' -> 0 ->> 'reserva_de' = 'patio' and (v -> 'colocadas' -> 0 ->> 'd0')::int = 1 and jsonb_array_length(v -> 'pat_int') = 1, v::text);
  -- sem pat no contexto (as simulações, o modo fora de ligado): as 2 saídas de antes, sem pat_int
  v := public._agenda_encaixar(pg_temp.ctx() - array['pat', 'pat_max', 'pat_nomes', 'pat_ent', 'pat_sai', 'pat_int', 'pat_ret', 'pat_tent'],
                               jsonb_build_array(pg_temp.fila()), pg_temp.par());
  v_res := pg_temp.ok(v_res, 'M4z sem pat no contexto, a saída de antes: sem pat_int', not (v ? 'pat_int') and (v -> 'colocadas' -> 0 ->> 'd0')::int = 1, v::text);
  -- _agenda_ctx_com
  v := public._agenda_ctx_com(pg_temp.ctx('{"sem": [1,1,1,1,1,2,2,2,2,2]}'),
         '[{"i": 1, "tipo": "compromisso", "ini": 1, "fim": 2, "p": [1, 1], "h": [1, 2], "pr": [0, 0], "na_janela": true},
           {"i": 2, "tipo": "reserva", "reserva_de": "patio", "ini": 3, "fim": 4, "p": [2, 2], "h": [3, 4], "pr": [0, 0], "na_janela": true}]'::jsonb);
  v_res := pg_temp.ok(v_res, 'M4za _agenda_ctx_com: o bloco gravado entra no que ocupa o pátio, para a decisão do dono simular certo; a reserva de pátio não',
    v -> 'pat_int' = '[{"d1": 1, "d2": 2, "i": 1, "k": 1}]'::jsonb, v -> 'pat_int' ->> 0);
  v_res := pg_temp.ok(v_res, 'M4zb _agenda_patio_cabe: 0 = cabe; o 1º dia cheio; conta OS distinta; só o pátio k; o intervalo inclusivo',
    public._agenda_patio_cabe('[{"k": 1, "i": 2, "d1": 3, "d2": 4}, {"k": 1, "i": 2, "d1": 3, "d2": 4}]', 1, 1, 1, 5, 2) = 0
    and public._agenda_patio_cabe('[{"k": 1, "i": 2, "d1": 3, "d2": 4}, {"k": 1, "i": 3, "d1": 4, "d2": 5}]', 1, 1, 1, 5, 2) = 4
    and public._agenda_patio_cabe('[{"k": 2, "i": 2, "d1": 1, "d2": 5}]', 1, 1, 1, 5, 1) = 0
    and public._agenda_patio_cabe('[{"k": 1, "i": 2, "d1": 5, "d2": 5}]', 1, 1, 1, 5, 1) = 5
    and public._agenda_patio_cabe('[{"k": 1, "i": 2, "d1": 6, "d2": 7}]', 1, 1, 1, 5, 1) = 0
    and public._agenda_patio_cabe(null, 1, 1, 1, 5, 1) = 0, null);
  v := public._agenda_patio_intervalo(pg_temp.ctx('{"util": [true, true, true, true, true, false, false, true, true, true]}'), 1, 9, 10);
  v_res := pg_temp.ok(v_res, 'M4zc o intervalo: a retirada é o d.u. seguinte pelo util (sex → seg, pulando o fim de semana)',
    v = '{"d1": 5, "d2": 8, "i": 1, "k": 1, "max": 1}'::jsonb, v::text);
  v := public._agenda_patio_intervalo(pg_temp.ctx('{"pat_ent": [2,0,0], "pat_sai": [9,0,0]}'), 1, 9, 10);
  v_res := pg_temp.ok(v_res, 'M4zd com entrada e retirada: d1 = a entrada, d2 = a retirada − 1',
    v = '{"d1": 2, "d2": 8, "i": 1, "k": 1, "max": 1}'::jsonb, v::text);
  v_res := pg_temp.ok(v_res, 'M4ze sem pat, sem pátio ou sem vagas: nulo',
    public._agenda_patio_intervalo('{}'::jsonb, 1, 1, 2) is null and public._agenda_patio_intervalo(pg_temp.ctx('{"pat": [0,0,0]}'), 1, 1, 2) is null
    and public._agenda_patio_intervalo(pg_temp.ctx('{"pat_max": [0]}'), 1, 1, 2) is null and public._agenda_patio_intervalo(pg_temp.ctx(), 9, 1, 2) is null, null);
  perform pg_temp.gravar(v_res);
end
$m4$;

-- ── M5. A pernoite ─────────────────────────────────────────────────────────────────────────────────────────────────
do $m5$
declare
  v_res jsonb := '[]'::jsonb;
  v     jsonb;
  i     jsonb;
  c     jsonb;
  v_ok  boolean;
  v_h   date := date '2027-07-16';
  v_ag  timestamptz := pg_temp.em(date '2027-07-16', '16:20');
  v_p   uuid;
  v_fr  int[];
begin
  -- o bloco puro: 6 meios seguidos, a mesma pessoa
  v := pg_temp.bloco('{"viagem": "pernoite", "imax_os": 0, "passos": 6}');
  v_res := pg_temp.ok(v_res, 'M5a pernoite: 6 meios seguidos, a mesma pessoa', v -> 'h' = '[1, 2, 3, 4, 5, 6]'::jsonb and v -> 'p' = '[1, 1, 1, 1, 1, 1]'::jsonb, v::text);
  v := pg_temp.bloco('{"viagem": "pernoite", "imax_os": 0, "passos": 6}', '{}', pg_temp.ocupa(null, 1, 4, 2));
  v_res := pg_temp.ok(v_res, 'M5b quem falta num meio-dia: sem bloco, mesmo com outro livre (a mesma equipe é inteira)', v is null, v::text);
  v := pg_temp.bloco('{"passos": 6}', '{}', pg_temp.ocupa(null, 1, 4, 2));
  v_res := pg_temp.ok(v_res, 'M5c a referência: sem pernoite, o outro livre entra', v is not null and v -> 'p' @> '[2]'::jsonb, v::text);
  v_fr := array_fill(0, array[40]);
  v_fr[(4 - 1) * 4 + 1] := 2;
  v_fr[(4 - 1) * 4 + 2] := 3;
  v := pg_temp.bloco('{"viagem": "pernoite", "imax_os": 0, "passos": 6}', '{}', null, v_fr);
  v_res := pg_temp.ok(v_res, 'M5c2 meio-dia sem passo por outra razão (as frentes cheias), depois de começar: sem bloco', v is null, v::text);
  v := pg_temp.bloco('{"passos": 4}', '{}', null, v_fr);
  v_res := pg_temp.ok(v_res, 'M5c3 a referência: sem pernoite, o meio-dia sem passo é pulado', v -> 'h' = '[1, 2, 3, 5]'::jsonb, v::text);
  v := pg_temp.bloco('{"viagem": "pernoite", "imax_os": 0, "passos": 6, "bem": [2]}');
  v_res := pg_temp.ok(v_res, 'M5d dia quebrado (o bem fora no dia 2): sem bloco', v is null, v::text);
  v := pg_temp.bloco('{"viagem": "pernoite", "imax_os": 0, "passos": 6, "fora_h": [3]}');
  v_res := pg_temp.ok(v_res, 'M5e meio-dia fora do horário depois de começar: sem bloco', v is null, v::text);
  v := pg_temp.bloco('{"viagem": "pernoite", "imax_os": 0, "passos": 6, "fora_h": [1]}');
  v_res := pg_temp.ok(v_res, 'M5f o 1º meio-dia fora do horário não conta (ainda não começou): começa à tarde', (v ->> 'ini')::int = 2 and v -> 'h' = '[2, 3, 4, 5, 6, 7]'::jsonb, v::text);
  v := pg_temp.bloco('{"viagem": "pernoite", "imax_os": 0, "passos": 4, "dk": [1, 1, 2, 2]}');
  v_res := pg_temp.ok(v_res, 'M5g o passo que pede mais gente do que a equipe do 1º passo: sem bloco', v is null, v::text);
  v := pg_temp.bloco('{"viagem": "pernoite", "imax_os": 0, "passos": 4, "dk": [2, 2, 1, 1]}');
  v_res := pg_temp.ok(v_res, 'M5h o passo que pede menos: a equipe do 1º passo vai inteira, nos 4 meios-dias',
    v -> 'p' = '[1, 2, 1, 2, 1, 2, 1, 2]'::jsonb and v -> 'h' = '[1, 1, 2, 2, 3, 3, 4, 4]'::jsonb, v::text);
  v := pg_temp.bloco('{"viagem": "pernoite", "imax_os": 0, "passos": 4, "dt_m": false}', '{"hab": [2,0,0,0, 2,0,0,0, 2,0,0,0], "custo": [1,1,1]}');
  v_res := pg_temp.ok(v_res, 'M5i o critério: 1º passo pela regra, os outros continuidade', (v -> 'cr' ->> 1)::int = 4 and (v -> 'cr' ->> 3)::int = 4, v::text);
  v := pg_temp.bloco('{"passos": 4, "imax_os": 0}', '{}', pg_temp.ocupa(pg_temp.ocupa(pg_temp.ocupa(pg_temp.ocupa(pg_temp.ocupa(pg_temp.ocupa(null, 1, 3, 2), 1, 4, 2), 2, 3, 2), 2, 4, 2), 3, 3, 2), 3, 4, 2));
  v_res := pg_temp.ok(v_res, 'M5j imax_os 0: o dia inteiro sem ninguém é interrupção de mais', v is null, v::text);
  v := pg_temp.bloco('{"passos": 4}', '{}', pg_temp.ocupa(pg_temp.ocupa(pg_temp.ocupa(pg_temp.ocupa(pg_temp.ocupa(pg_temp.ocupa(null, 1, 3, 2), 1, 4, 2), 2, 3, 2), 2, 4, 2), 3, 3, 2), 3, 4, 2));
  v_res := pg_temp.ok(v_res, 'M5k a referência: sem imax_os, vale o imax do p_g', (v ->> 'int')::int = 1, v::text);
  if not pg_temp.carregada() then
    insert into _resultado values ('M5 a pernoite no motor', true, 'PULADO: sem as fixtures (rode pela bancada)');
    perform pg_temp.gravar(v_res);
    return;
  end if;
  begin
    perform pg_temp.gestor();
    perform pg_temp.modos('sombra');
    perform pg_temp.dono(array['OS-J6', 'OS-J7'], 'abre_e_fecha');
    v := pg_temp.j(array['OS-J6']);
    i := pg_temp.item(v, 'OS-J6');
    v_res := pg_temp.ok(v_res, 'M5l em teste, J6 são 4 meios-dias, com o dono abrindo e fechando (a viagem não pesa)',
      pg_temp.n_meios(i) = 4 and (i ->> 'abre')::boolean and (i ->> 'fecha')::boolean and not i ? 'viagem', pg_temp.meios(i));
    perform pg_temp.modo('modo_viagem', 'ligado');
    v := pg_temp.j(array['OS-J6']);
    i := pg_temp.item(v, 'OS-J6');
    v_res := pg_temp.ok(v_res, 'M5m ligado: 4 + 2 = 6 meios seguidos (3 dias), a mesma equipe, sem abre e fecha, e o item diz a viagem',
      pg_temp.n_meios(i) = 6 and pg_temp.pessoas(i) !~ ',' and not (i ->> 'abre')::boolean and not (i ->> 'fecha')::boolean
      and i ->> 'viagem' = 'pernoite' and (i ->> 'imax_os')::int = 0
      and pg_temp.dias(i) = array[date '2027-07-21', date '2027-07-22', date '2027-07-23']
      and not exists (select 1 from jsonb_array_elements(i -> 'alocacoes') a where a ->> 'presenca' <> 'turno'),
      pg_temp.meios(i) || ' / ' || pg_temp.pessoas(i));
    v_res := pg_temp.ok(v_res, 'M5n as suposições do item, nas palavras da §6.2',
      i -> 'suposicoes' = '["Iate Clube Caiobá fica em Guaratuba (PR): supus viagem com pernoite; a ida e a volta ocupam 1 meio-dia cada", "supus que você não vai abrir e fechar esse serviço (fora da região)"]'::jsonb,
      (i -> 'suposicoes')::text);
    v := pg_temp.j(array['OS-J6'], jsonb_build_object('fixar', jsonb_build_array(jsonb_build_object('os', pg_temp.os('OS-J6'), 'de', '2027-07-23'))));
    v_res := pg_temp.ok(v_res, 'M5n2 o "por que não" da pernoite: na sex 23/07 não há 3 dias úteis seguidos',
      pg_temp.fora(v, 'OS-J6') ->> 'texto' = 'Kalmar (OS-J6): não cabe sex 23/07: a viagem precisa de 3 dias úteis seguidos com a mesma equipe.', pg_temp.fora(v, 'OS-J6')::text);
    -- o dia quebrado no motor: o bem fora na qui 22: a viagem não cabe qua-qui-sex nem atravessa o fim de semana
    update public.os_planejamento set bem_indisponivel = datemultirange(daterange(date '2027-07-22', date '2027-07-22', '[]')) where service_order_id = pg_temp.os('OS-J6');
    v := pg_temp.j(array['OS-J6']);
    i := pg_temp.item(v, 'OS-J6');
    v_res := pg_temp.ok(v_res, 'M5o com o bem fora na qui 22, a viagem vai para seg 26 a qua 28 (dias úteis seguidos, sem atravessar o fim de semana)',
      pg_temp.dias(i) = array[date '2027-07-26', date '2027-07-27', date '2027-07-28'], pg_temp.meios(i));
    update public.os_planejamento set bem_indisponivel = '{}'::datemultirange where service_order_id = pg_temp.os('OS-J6');
    -- a violação leva a viagem inteira
    v_p := pg_temp.pessoa('Rafael');
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    select md5('m5:' || x.dia || x.turno)::uuid, pg_temp.os('OS-J6'), v_p, x.dia, x.turno, 'turno', 'execucao', 'publicada', 'motor', v_ag
      from (values (date '2027-07-21', 'manha'), (date '2027-07-21', 'tarde'), (date '2027-07-22', 'manha'), (date '2027-07-22', 'tarde'),
                   (date '2027-07-23', 'manha'), (date '2027-07-23', 'tarde')) x(dia, turno);
    update public.os_planejamento set nao_antes_de = date '2027-07-22', nao_antes_motivo = 'cliente' where service_order_id = pg_temp.os('OS-J6');
    -- o congelado até sex 23/07: o "depois" das violações de sempre não alcança nada; só a pernoite junta a viagem
    c := public._agenda_violacoes(array[pg_temp.os('OS-J6')], array(select k.service_order_id from public.os_carteira(v_h) k), false,
           jsonb_build_object(pg_temp.os('OS-J6')::text, jsonb_build_object('pront', public.os_prontidao(pg_temp.os('OS-J6'), v_h),
                                                                            'meios', public.agenda_meios_da_os(pg_temp.os('OS-J6'), v_h))), v_h,
           date '2027-07-23');
    v_res := pg_temp.ok(v_res, 'M5p a violação de um meio-dia leva todos os futuros da pernoite, mesmo no congelado: 2 violados (qua), 4 replanejados',
      jsonb_array_length(c) = 6 and (select count(*) from jsonb_array_elements(c) x where (x ->> 'violada')::boolean) = 2
      and (select count(*) from jsonb_array_elements(c) x where x ->> 'motivo' = 'replanejado') = 4, c::text);
    update public.agenda_alocacoes set estado = 'fixada', fixado_por = 'dono' where id = md5('m5:' || date '2027-07-23' || 'tarde')::uuid;
    c := public._agenda_violacoes(array[pg_temp.os('OS-J6')], array(select k.service_order_id from public.os_carteira(v_h) k), false,
           jsonb_build_object(pg_temp.os('OS-J6')::text, jsonb_build_object('pront', public.os_prontidao(pg_temp.os('OS-J6'), v_h),
                                                                            'meios', public.agenda_meios_da_os(pg_temp.os('OS-J6'), v_h))), v_h,
           date '2027-07-23');
    v_res := pg_temp.ok(v_res, 'M5p2 o que o dono fixou fica de fora da viagem que cai', jsonb_array_length(c) = 5
      and not exists (select 1 from jsonb_array_elements(c) x where x ->> 'dia' = '2027-07-23' and x ->> 'turno' = 'tarde'), c::text);
    perform pg_temp.modo('modo_viagem', 'sombra');
    c := public._agenda_violacoes(array[pg_temp.os('OS-J6')], array(select k.service_order_id from public.os_carteira(v_h) k), false,
           jsonb_build_object(pg_temp.os('OS-J6')::text, jsonb_build_object('pront', public.os_prontidao(pg_temp.os('OS-J6'), v_h),
                                                                            'meios', public.agenda_meios_da_os(pg_temp.os('OS-J6'), v_h))), v_h,
           date '2027-07-23');
    v_res := pg_temp.ok(v_res, 'M5q em teste, a mesma violação só leva os 2 violados: quem junta a viagem é o modo',
      jsonb_array_length(c) = 2 and (select count(*) from jsonb_array_elements(c) x where (x ->> 'violada')::boolean) = 2, c::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$m5$;

-- ── M6. A ida e volta ──────────────────────────────────────────────────────────────────────────────────────────────
do $m6$
declare
  v_res jsonb := '[]'::jsonb;
  v     jsonb;
  i     jsonb;
begin
  v_res := pg_temp.ok(v_res, 'M6a o custo da viagem: ida e volta com 1 meio-dia por dia (2 → +2, 3 → +3, 5 → +5); sem estrada (0); pernoite (+2); regional (0); nada sem passos',
    public._agenda_viagem_extra('bate_volta', 1, 2) = 2 and public._agenda_viagem_extra('bate_volta', 1, 3) = 3 and public._agenda_viagem_extra('bate_volta', 1, 5) = 5
    and public._agenda_viagem_extra('bate_volta', 0, 4) = 0 and public._agenda_viagem_extra('pernoite', 2, 4) = 2 and public._agenda_viagem_extra('pernoite', 4, 1) = 4
    and public._agenda_viagem_extra('regional', 0, 4) = 0 and public._agenda_viagem_extra('pernoite', 2, 0) = 0 and public._agenda_viagem_extra('bate_volta', 1, null) = 0, null);
  -- ida e volta: quem começou vem primeiro, sem obrigar: a pessoa 1 começa; no 2º dia a pessoa 1 tem menos carga? a carga da pessoa 2 é menor, mas ela fica
  v := public._agenda_tentar_bloco(
    jsonb_build_object('nh', 10, 'nd', 5, 'np', 3, 'nw', 1, 'dono', 0, 'wip', 2, 'imax', 2),
    array_fill(true, array[5]), array_fill(1, array[5]), array_fill(1, array[30]), array_fill(0, array[10]),
    pg_temp.ocupa(pg_temp.ocupa(null, 1, 2, 2), 1, 3, 2), array_fill(0, array[40]),
    array_fill(10, array[3]), array[0, 3, 3], array_fill(10, array[3]), array_fill(0, array[4]),
    '{"i": 1, "passos": 4, "dm": 1, "dtd": 1, "viagem": "bate_volta"}', 1, false, 1);
  v_res := pg_temp.ok(v_res, 'M6b ida e volta: quem começou volta assim que está livre (ocupado no h2 e no h3, ele fica fora só ali, sem obrigar)',
    v -> 'p' -> 0 = '1'::jsonb and v -> 'p' -> 3 = '1'::jsonb and v -> 'p' -> 1 <> '1'::jsonb, v::text);
  v := public._agenda_tentar_bloco(
    jsonb_build_object('nh', 10, 'nd', 5, 'np', 3, 'nw', 1, 'dono', 0, 'wip', 2, 'imax', 2),
    array_fill(true, array[5]), array_fill(1, array[5]), array_fill(1, array[30]), array_fill(0, array[10]),
    pg_temp.ocupa(pg_temp.ocupa(null, 1, 2, 2), 1, 3, 2), array_fill(0, array[40]),
    array_fill(10, array[3]), array[0, 3, 3], array_fill(10, array[3]), array_fill(0, array[4]),
    '{"i": 1, "passos": 4, "dm": 1, "dtd": 1}', 1, false, 1);
  v_res := pg_temp.ok(v_res, 'M6c a referência: sem a chave, quem estava no meio-dia anterior fica (o 2º que entrou): a ordem de antes',
    v -> 'p' -> 3 <> '1'::jsonb, v::text);
  if not pg_temp.carregada() then
    insert into _resultado values ('M6 a ida e volta no motor', true, 'PULADO: sem as fixtures (rode pela bancada)');
    perform pg_temp.gravar(v_res);
    return;
  end if;
  begin
    perform pg_temp.gestor();
    perform pg_temp.modos('sombra');
    perform pg_temp.modo('modo_viagem', 'ligado');
    perform pg_temp.dono(array['OS-J7'], 'abre_e_fecha');
    v := pg_temp.j(array['OS-J7']);
    i := pg_temp.item(v, 'OS-J7');
    v_res := pg_temp.ok(v_res, 'M6d J7 (1 dia em Florianópolis): 2 + 2 = 4 meios em 2 dias, sem abre e fecha, e a suposição',
      pg_temp.n_meios(i) = 4 and cardinality(pg_temp.dias(i)) = 2 and not (i ->> 'abre')::boolean and i ->> 'viagem' = 'bate_volta' and not i ? 'imax_os'
      and i -> 'suposicoes' @> '["Veleiros da Ilha fica em Florianópolis: supus ida e volta no mesmo dia; cada dia rende meio dia de serviço", "supus que você não vai abrir e fechar esse serviço (fora da região)"]'::jsonb,
      (i -> 'suposicoes')::text);
    -- a dupla inferida que vai com 1 pessoa, pela estimativa do orçamento: 2 meios-dias em vez de 1 (a duração que conserva as diárias-pessoa), e a estrada é a deles
    update public.agenda_config set modo_dupla = 'ligado', dupla_espera_max_du = 0 where id;
    update public.service_order_services set name_snapshot = 'Troca do banco de baterias' where service_order_id = pg_temp.os('OS-J7');
    update public.os_planejamento set dias = null, estimativa_fonte = null where service_order_id = pg_temp.os('OS-J7');
    insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, criado_em)
    select p.id, daterange(date '2027-07-19', date '2027-08-13', '[]'), null, 'indisponivel', 'dono', 'não vem (teste)', timestamptz '2027-07-15 10:01-03'
      from public.payees p where p.name in ('Roberto', 'João', 'Rafael', 'Bruno') and p.active;
    v := pg_temp.j(array['OS-J7']);
    i := pg_temp.item(v, 'OS-J7');
    v_res := pg_temp.ok(v_res, 'M6f a dupla inferida com 1 pessoa, de ida e volta: passos1 soma a estrada dele (2 + 2 = 4 meios-dias, não 2 + 1)', pg_temp.n_meios(i) = 4, pg_temp.meios(i));
    delete from public.agenda_disponibilidade where nota = 'não vem (teste)';
    update public.os_planejamento set dias = 1, estimativa_fonte = 'dono' where service_order_id = pg_temp.os('OS-J7');
    update public.service_order_services set name_snapshot = 'Troca do GPS' where service_order_id = pg_temp.os('OS-J7');
    update public.agenda_config set modo_dupla = 'desligado', bate_volta_meios_dia = 0 where id;
    v := pg_temp.j(array['OS-J7']);
    i := pg_temp.item(v, 'OS-J7');
    v_res := pg_temp.ok(v_res, 'M6e com bate_volta_meios_dia 0, a ida e volta não custa meio-dia: os 2 de sempre, e a suposição diz isso',
      pg_temp.n_meios(i) = 2 and i -> 'suposicoes' @> '["Veleiros da Ilha fica em Florianópolis: supus ida e volta no mesmo dia; a estrada não tira meio-dia de serviço"]'::jsonb,
      (i -> 'suposicoes')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$m6$;

-- ── M7. O mesmo dia ────────────────────────────────────────────────────────────────────────────────────────────────
do $m7$
declare
  v_res jsonb := '[]'::jsonb;
  v     jsonb;
  v_a   jsonb;
  v_b   jsonb;
  v_fr  int[] := array_fill(0, array[40]);
  v_oc  int[];
  v_hab jsonb := '{"hab": [2,0,0,0, 2,0,0,0, 2,0,0,0], "custo": [1,1,1]}';
begin
  -- o v_mh olha o dia: a OS 2, no mesmo local, está à tarde (h2); o bloco de meio dia é de manhã
  v_fr[(2 - 1) * 4 + 1] := 2;
  v := pg_temp.bloco('{"passos": 1}', '{}', null, v_fr, array[1, 1, 0, 0]);
  v_res := pg_temp.ok(v_res, 'M7a sem mesmo_dia, o "mesmo local" só vê o mesmo meio-dia', not (v ->> 'mesmo')::boolean, v::text);
  v := pg_temp.bloco('{"passos": 1}', '{"mesmo_dia": true}', null, v_fr, array[1, 1, 0, 0]);
  v_res := pg_temp.ok(v_res, 'M7b com mesmo_dia, ele vê os dois meios-dias do dia', (v ->> 'mesmo')::boolean, v::text);
  v := pg_temp.bloco('{"passos": 1}', '{"mesmo_dia": true}', null, v_fr, array[1, 2, 0, 0]);
  v_res := pg_temp.ok(v_res, 'M7c outro local: não', not (v ->> 'mesmo')::boolean, v::text);
  v_fr := array_fill(0, array[40]);
  v_fr[(2 - 1) * 4 + 1] := -2;
  v := pg_temp.bloco('{"passos": 1}', '{"mesmo_dia": true}', null, v_fr, array[1, 1, 0, 0]);
  v_res := pg_temp.ok(v_res, 'M7d a frente da reserva também (como no meio-dia)', (v ->> 'mesmo')::boolean, v::text);
  v_fr := array_fill(0, array[40]);
  v_fr[(2 - 1) * 4 + 1] := 1;
  v := pg_temp.bloco('{"passos": 1}', '{"mesmo_dia": true}', null, v_fr, array[1, 1, 0, 0]);
  v_res := pg_temp.ok(v_res, 'M7e a frente da própria OS no outro meio-dia não é "o mesmo local"', not (v ->> 'mesmo')::boolean, v::text);
  -- quem já está lá: a pessoa 3 está à tarde na OS 2, do mesmo local
  v_oc := pg_temp.ocupa(null, 3, 2, 2);
  v := pg_temp.bloco('{"passos": 1}', '{}'::jsonb || v_hab, v_oc, null, array[1, 1, 0, 0]);
  v_res := pg_temp.ok(v_res, 'M7f a referência: na escolha de antes, sem mesmo_dia, vai a pessoa 1', v -> 'p' = '[1]'::jsonb, v::text);
  v := pg_temp.bloco('{"passos": 1}', '{"mesmo_dia": true}'::jsonb || v_hab, v_oc, null, array[1, 1, 0, 0]);
  v_res := pg_temp.ok(v_res, 'M7g na escolha de antes, com mesmo_dia, vai quem já está lá, e o critério é local (5)',
    v -> 'p' = '[3]'::jsonb and (v -> 'cr' ->> 0)::int = 5, v::text);
  v := pg_temp.bloco('{"passos": 1}', '{"mesmo_dia": true}'::jsonb || v_hab, pg_temp.ocupa(null, 3, 2, -2), null, array[1, 1, 0, 0]);
  v_res := pg_temp.ok(v_res, 'M7h também com a reserva no outro meio-dia', v -> 'p' = '[3]'::jsonb, v::text);
  v := pg_temp.bloco('{"passos": 1}', '{"mesmo_dia": true}'::jsonb || v_hab, v_oc, null, array[1, 2, 0, 0]);
  v_res := pg_temp.ok(v_res, 'M7i a outra OS em outro local: a ordem de antes', v -> 'p' = '[1]'::jsonb, v::text);
  -- a escolha da 7c: o k4 já olha o irmão; mesmo_dia amplia para a reserva (R6.9-6)
  v := pg_temp.bloco('{"passos": 1}', '{"hab_modo": 1, "n": {"ene": 2, "com": 2, "dia": 2, "alt": 2, "par": 2}}'::jsonb || v_hab, pg_temp.ocupa(null, 3, 2, -2), null, array[1, 1, 0, 0]);
  v_res := pg_temp.ok(v_res, 'M7j na escolha da 7c, sem mesmo_dia, o k4 não vê a reserva: pessoa 1', v -> 'p' = '[1]'::jsonb, v::text);
  v := pg_temp.bloco('{"passos": 1}', '{"mesmo_dia": true, "hab_modo": 1, "n": {"ene": 2, "com": 2, "dia": 2, "alt": 2, "par": 2}}'::jsonb || v_hab, pg_temp.ocupa(null, 3, 2, -2), null, array[1, 1, 0, 0]);
  v_res := pg_temp.ok(v_res, 'M7k com mesmo_dia, o k4 amplia: quem tem a reserva no mesmo local, com o critério local', v -> 'p' = '[3]'::jsonb and (v -> 'cr' ->> 0)::int = 5, v::text);
  -- o k4 fica depois do líder, da continuidade e do nível: sem chave nova logo depois do líder
  v := pg_temp.bloco('{"passos": 1, "lid_plan": 2}', '{"mesmo_dia": true, "hab_modo": 1, "n": {"ene": 2, "com": 2, "dia": 2, "alt": 2, "par": 2}}'::jsonb || v_hab, v_oc, null, array[1, 1, 0, 0]);
  v_res := pg_temp.ok(v_res, 'M7l o responsável planejado ainda vem antes do mesmo local (R6.9-6: nenhuma chave nova logo depois do líder)', v -> 'p' = '[2]'::jsonb, v::text);
  v := pg_temp.bloco('{"passos": 1}', ('{"mesmo_dia": true, "hab_modo": 1, "n": {"ene": 2, "com": 2, "dia": 2, "alt": 2, "par": 2}}'::jsonb || v_hab)
                     || '{"hab": [1,0,0,0, 2,0,0,0, 2,0,0,0]}'::jsonb, v_oc, null, array[1, 1, 0, 0]);
  v_res := pg_temp.ok(v_res, 'M7m o nível (k3, o menos qualificado que dá conta) vem antes do mesmo local', v -> 'p' = '[1]'::jsonb, v::text);
  if not pg_temp.carregada() then
    insert into _resultado values ('M7 o mesmo dia no motor', true, 'PULADO: sem as fixtures (rode pela bancada)');
    perform pg_temp.gravar(v_res);
    return;
  end if;
  begin
    perform pg_temp.gestor();
    perform pg_temp.modos('sombra');
    perform pg_temp.dono(array['OS-J8', 'OS-J9', 'OS-J10'], 'nunca');
    v_a := pg_temp.j(array['OS-J9', 'OS-J10', 'OS-J8']);
    perform pg_temp.modo('modo_mesmo_local', 'ligado');
    v_b := pg_temp.j(array['OS-J9', 'OS-J10', 'OS-J8']);
    v_res := pg_temp.ok(v_res, 'M7n J9 e J10, na Marina Itajaí: ligado, no mesmo dia e com a mesma pessoa, e o item diz "juntei com"',
      pg_temp.dias(pg_temp.item(v_b, 'OS-J9')) = pg_temp.dias(pg_temp.item(v_b, 'OS-J10'))
      and pg_temp.pessoas(pg_temp.item(v_b, 'OS-J9')) = pg_temp.pessoas(pg_temp.item(v_b, 'OS-J10'))
      and pg_temp.item(v_b, 'OS-J9') -> 'suposicoes' @> '["juntei com Igor (OS-J10) no mesmo dia, na Marina Itajaí"]'::jsonb,
      pg_temp.projecao(v_b) || ' / ' || (pg_temp.item(v_b, 'OS-J9') -> 'suposicoes')::text);
    v_res := pg_temp.ok(v_res, 'M7o em teste, a mesma entrada não junta: outra pessoa ou outro dia (a régua)',
      pg_temp.pessoas(pg_temp.item(v_a, 'OS-J9')) <> pg_temp.pessoas(pg_temp.item(v_a, 'OS-J10')), pg_temp.projecao(v_a));
    v_a := public._agenda_contexto(date '2027-07-12', date '2027-08-29', date '2027-07-16', '{}'::uuid[], pg_temp.lista(array['OS-J9', 'OS-J10', 'OS-J8', 'OS-J2']));
    v_res := pg_temp.ok(v_res, 'M7p o contexto ligado: J9, J10 e J2 na mesma chave do local real; J8 (Penha, pela cidade) noutra, com o município',
      v_a -> 'loc' -> 0 = v_a -> 'loc' -> 1 and v_a -> 'loc' -> 0 = v_a -> 'loc' -> 3 and v_a -> 'loc' -> 2 <> v_a -> 'loc' -> 0
      and v_a -> 'mun_nomes' @> '["Penha", "Itajaí"]'::jsonb and (v_a -> 'mun' ->> 2)::int > 0, (v_a -> 'loc')::text || (v_a -> 'mun')::text);
    -- a chave velha (a marina da OS, senão a cidade) separa J14 (o local dito pelo dono, Tedesco) e D1 (a marina Tedesco); a do local real junta
    v_a := public._agenda_contexto(date '2027-07-12', date '2027-08-29', date '2027-07-16', '{}'::uuid[], pg_temp.lista(array['OS-J14', 'OS-D1']));
    v_res := pg_temp.ok(v_res, 'M7q ligado, loc vem da chave do local real (R6.9-7): o local dito e a marina da OS, no mesmo lugar, ficam juntos', v_a -> 'loc' -> 0 = v_a -> 'loc' -> 1 and (v_a -> 'loc' ->> 0)::int > 0, (v_a -> 'loc')::text);
    perform pg_temp.modo('modo_mesmo_local', 'sombra');
    v_a := public._agenda_contexto(date '2027-07-12', date '2027-08-29', date '2027-07-16', '{}'::uuid[], pg_temp.lista(array['OS-J14', 'OS-D1']));
    v_res := pg_temp.ok(v_res, 'M7r em teste, a chave velha, byte a byte: não junta', v_a -> 'loc' -> 0 <> v_a -> 'loc' -> 1, (v_a -> 'loc')::text);
    perform pg_temp.modo('modo_mesmo_local', 'ligado');
    -- o município é pelo nome normalizado: a cidade do cliente com outra grafia é o mesmo município do local
    update public.clients set city = 'BALNEARIO CAMBORIU' where id = (select client_id from public.service_orders where service_order_number = 'OS-D3');
    v_a := public._agenda_contexto(date '2027-07-12', date '2027-08-29', date '2027-07-16', '{}'::uuid[], pg_temp.lista(array['OS-D1', 'OS-D3']));
    v_res := pg_temp.ok(v_res, 'M7s mun normalizado: Balneário Camboriú (o local) e BALNEARIO CAMBORIU (a cidade do cliente) são o mesmo município', v_a -> 'mun' -> 0 = v_a -> 'mun' -> 1 and (v_a -> 'mun' ->> 0)::int > 0, (v_a -> 'mun')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$m7$;

-- ── M8. A troca ────────────────────────────────────────────────────────────────────────────────────────────────────
do $m8$
declare
  v_res jsonb := '[]'::jsonb;
  v     jsonb;
  i     jsonb;
  v_hab jsonb := '{"hab": [2,0,0,0, 2,0,0,0, 2,0,0,0], "custo": [1,1,1]}';
  v_oc  int[];
  v_j   uuid;
begin
  v_res := pg_temp.ok(v_res, 'M8a a tupla de _agenda_melhor (R6.8-5): fim primeiro; o sábado antes dos turnos do dono; a troca depois das interrupções e antes do mesmo local; sem troca, a ordem de antes',
    public._agenda_melhor('{"fim": 3, "md": 0, "int": 0, "mesmo": false, "d0": 1, "troca": 2}', '{"fim": 4, "md": 0, "int": 0, "mesmo": true, "d0": 1}')
    and public._agenda_melhor('{"fim": 3, "sab": 0, "md": 3, "int": 0, "mesmo": false, "d0": 1}', '{"fim": 3, "sab": 1, "md": 0, "int": 0, "mesmo": true, "d0": 1}')
    and public._agenda_melhor('{"fim": 3, "md": 0, "int": 0, "mesmo": false, "d0": 2, "troca": 1}', '{"fim": 3, "md": 0, "int": 1, "mesmo": true, "d0": 1}')
    and public._agenda_melhor('{"fim": 3, "md": 0, "int": 0, "mesmo": false, "d0": 2}', '{"fim": 3, "md": 0, "int": 0, "mesmo": true, "d0": 1, "troca": 1}')
    and not public._agenda_melhor('{"fim": 3, "md": 0, "int": 0, "mesmo": true, "d0": 1, "troca": 1}', '{"fim": 3, "md": 0, "int": 0, "mesmo": false, "d0": 2}')
    and public._agenda_melhor('{"fim": 3, "md": 0, "int": 0, "mesmo": true, "d0": 2, "troca": 0}', '{"fim": 3, "md": 0, "int": 0, "mesmo": false, "d0": 1}')
    and public._agenda_melhor('{"fim": 3, "md": 0, "int": 0, "mesmo": true, "d0": 1}', '{"fim": 3, "md": 0, "int": 0, "mesmo": true, "d0": 2}'), null);
  -- as pessoas 1 (a primeira da ordem de antes) e 3 têm a OS 2, de outro município, à tarde
  v_oc := pg_temp.ocupa(pg_temp.ocupa(null, 1, 2, 2), 3, 2, 2);
  v := pg_temp.bloco('{"passos": 1}', '{"troca": true, "mun": [1, 2, 0, 0]}'::jsonb || v_hab, v_oc);
  v_res := pg_temp.ok(v_res, 'M8b a ordem prefere quem não troca: vai a pessoa 2, a saída diz troca 0 e o município evitado, e o critério é local',
    v -> 'p' = '[2]'::jsonb and (v ->> 'troca')::int = 0 and (v ->> 'evitou')::int = 2 and (v -> 'cr' ->> 0)::int = 5, v::text);
  v := pg_temp.bloco('{"passos": 1}', '{"mun": [1, 2, 0, 0]}'::jsonb || v_hab, v_oc);
  v_res := pg_temp.ok(v_res, 'M8c sem troca no p_g (fora da temporada), a ordem de antes e nenhuma chave nova', v -> 'p' = '[1]'::jsonb and not v ? 'troca' and not v ? 'evitou', v::text);
  v := pg_temp.bloco('{"passos": 1}', '{"troca": true, "mun": [1, 1, 0, 0]}'::jsonb || v_hab, v_oc);
  v_res := pg_temp.ok(v_res, 'M8d o mesmo município não é troca', v -> 'p' = '[1]'::jsonb and (v ->> 'troca')::int = 0 and not v ? 'evitou', v::text);
  v := pg_temp.bloco('{"passos": 1}', '{"troca": true, "mun": [0, 2, 0, 0]}'::jsonb || v_hab, v_oc);
  v_res := pg_temp.ok(v_res, 'M8e o município desta OS desconhecido: não é troca', v -> 'p' = '[1]'::jsonb and (v ->> 'troca')::int = 0, v::text);
  v := pg_temp.bloco('{"passos": 1}', '{"troca": true, "mun": [1, 0, 0, 0]}'::jsonb || v_hab, v_oc);
  v_res := pg_temp.ok(v_res, 'M8f o município da outra OS desconhecido: não é troca', v -> 'p' = '[1]'::jsonb and (v ->> 'troca')::int = 0, v::text);
  v := pg_temp.bloco('{"passos": 1}', '{"troca": true, "mun": [1, 2, 0, 0]}'::jsonb || v_hab, pg_temp.ocupa(pg_temp.ocupa(pg_temp.ocupa(null, 1, 2, 2), 2, 1, 3), 3, 1, 3));
  v_res := pg_temp.ok(v_res, 'M8g só a pessoa que troca está livre: ela vai (o custo não atrasa serviço), e a saída conta 1', v -> 'p' = '[1]'::jsonb and (v ->> 'troca')::int = 1, v::text);
  v := pg_temp.bloco('{"passos": 1}', '{"troca": true, "hab_modo": 1, "mun": [1, 2, 0, 0], "n": {"ene": 2, "com": 2, "dia": 2, "alt": 2, "par": 2}}'::jsonb || v_hab, v_oc);
  v_res := pg_temp.ok(v_res, 'M8h na escolha da 7c, a troca depois do k4 (R6.9-6): vai a pessoa 2, com o critério local, e a saída diz o que evitou', v -> 'p' = '[2]'::jsonb and (v -> 'cr' ->> 0)::int = 5 and (v ->> 'evitou')::int = 2, v::text);
  v := pg_temp.bloco('{"passos": 1}', '{"troca": true, "hab_modo": 1, "mun": [1, 2, 0, 0], "n": {"ene": 2, "com": 2, "dia": 2, "alt": 2, "par": 2}}'::jsonb || v_hab
                     || '{"hab": [1,0,0,0, 2,0,0,0, 2,0,0,0]}'::jsonb, v_oc);
  v_res := pg_temp.ok(v_res, 'M8i o nível vem antes da troca: o menos qualificado que dá conta, mesmo trocando', v -> 'p' = '[1]'::jsonb and (v ->> 'troca')::int = 1, v::text);
  if not pg_temp.carregada() then
    insert into _resultado values ('M8 a troca no motor', true, 'PULADO: sem as fixtures (rode pela bancada)');
    perform pg_temp.gravar(v_res);
    return;
  end if;
  -- Cenário D: seg 30/11/2026, temporada. Roberto com a OS-D1 (Tedesco, BC) de manhã; a OS-D2 (Penha) e a D3 (BC) disputam a tarde dele.
  begin
    perform pg_temp.gestor();
    perform pg_temp.modos('sombra');
    perform pg_temp.dono(array['OS-D2', 'OS-D3'], 'nunca');
    update public.agenda_config set congelamento_du = 0 where id;
    v_j := pg_temp.pessoa('João');
    -- de manhã, ninguém mais: só a tarde do dia sobra; João com a semana mais carregada que Roberto (a ordem de antes dá Roberto)
    perform pg_temp.d_so_a_tarde();
    v := pg_temp.d(array['OS-D2', 'OS-D3']);
    i := pg_temp.item(v, 'OS-D2');
    v_res := pg_temp.ok(v_res, 'M8j a referência, em teste: a OS-D2 (Penha) fica com a tarde do Roberto, que está em BC de manhã',
      pg_temp.pessoas(i) = 'Roberto', pg_temp.projecao(v));
    perform pg_temp.modo('modo_mesmo_local', 'ligado');
    v := pg_temp.d(array['OS-D2', 'OS-D3']);
    i := pg_temp.item(v, 'OS-D2');
    v_res := pg_temp.ok(v_res, 'M8k em dezembro (temporada), ligado: a OS-D2 não vai com o Roberto, a D3 (BC) vai, e o item diz o que evitou',
      pg_temp.pessoas(i) <> 'Roberto' and pg_temp.pessoas(pg_temp.item(v, 'OS-D3')) = 'Roberto'
      and i -> 'suposicoes' @> '["evitei pôr a mesma pessoa em Penha e em Balneário Camboriú no mesmo dia (temporada)"]'::jsonb,
      pg_temp.projecao(v) || ' / ' || (i -> 'suposicoes')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.gestor();
    perform pg_temp.modos('sombra');
    perform pg_temp.dono(array['OS-D2', 'OS-D3'], 'nunca');
    update public.agenda_config set congelamento_du = 0, temporada_meses = '{1,2,3}' where id;
    perform pg_temp.d_so_a_tarde();
    perform pg_temp.modo('modo_mesmo_local', 'ligado');
    v := pg_temp.d(array['OS-D2', 'OS-D3']);
    v_res := pg_temp.ok(v_res, 'M8l o mesmo cenário fora da temporada, ligado: a troca não pesa: a OS-D2 fica com o Roberto, como em teste',
      pg_temp.pessoas(pg_temp.item(v, 'OS-D2')) = 'Roberto' and not pg_temp.item(v, 'OS-D2') -> 'suposicoes' @> '["evitei pôr a mesma pessoa em Penha e em Balneário Camboriú no mesmo dia (temporada)"]'::jsonb,
      pg_temp.projecao(v));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$m8$;

-- ── M9. As cópias ──────────────────────────────────────────────────────────────────────────────────────────────────
do $m9$
declare
  v_res jsonb := '[]'::jsonb;
  f     record;
  v_mig text;
  v_viv text;
  v_dif text;
  v_n   int := 0;
  v_tot int := 0;
begin
  if not pg_temp.textos_ok() then
    insert into _resultado values ('M9 as cópias', true, 'PULADO: sem as migrations como texto (rode pela bancada)');
    return;
  end if;
  v_mig := current_setting('agenda_teste.mig_motor_fase7d');
  for f in select * from (values
      ('_agenda_contexto', 'agenda_teste.mig_motor_fase7c'), ('_agenda_tentar_bloco', 'agenda_teste.mig_motor_fase7c'),
      ('_agenda_encaixar', 'agenda_teste.mig_motor_fase7c'), ('_agenda_por_que_nao', 'agenda_teste.mig_motor_fase7c'),
      ('_agenda_melhor', 'agenda_teste.mig_motor_fase7b'), ('_agenda_ctx_com', 'agenda_teste.mig_motor_fase2'),
      ('_agenda_violacoes', 'agenda_teste.mig_violacao_fase7c'), ('_agenda_gestor_reparo', 'agenda_teste.mig_violacao_fase7c'),
      ('_agenda_validar_itens', 'agenda_teste.mig_motor_fase7b'), ('_agenda_gestor_pessoa_meios', 'agenda_teste.mig_correcao2_fase7b'),
      ('agenda_propor', 'agenda_teste.mig_correcao_fase7c')) t(nome, fonte) loop
    select replace(p.prosrc, E'\r\n', E'\n') into v_viv from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = f.nome;
    v_tot := v_tot + 1;
    if pg_temp.sem_7d(pg_temp.corpo(v_mig, f.nome)) is distinct from pg_temp.corpo(current_setting(f.fonte), f.nome) then
      v_dif := concat_ws('; ', v_dif, f.nome || ': a migration, tirados os blocos, não é a origem');
    end if;
    -- (correção da 7d, Onda 1) agenda_propor passou a viver na 20261107100800: a viva e a desta migration são comparadas sem os blocos
    if pg_temp.sem_7d(v_viv) is distinct from pg_temp.sem_7d(pg_temp.corpo(v_mig, f.nome)) then
      v_dif := concat_ws('; ', v_dif, f.nome || ': a viva não é a da migration');
    end if;
    v_n := v_n + (select count(*)::int from regexp_matches(pg_temp.corpo(v_mig, f.nome), '-- FASE 7d: fim|-- \(7d: fim\)', 'g'));
  end loop;
  v_res := pg_temp.ok(v_res, 'M9a as 11 recriadas: tirados os blocos "-- FASE 7d:" e as marcas "-- (7d", o corpo é o da origem (R6.1), e a viva é a da migration',
    v_dif is null and v_tot = 11 and v_n >= 11, coalesce(v_dif, format('%s funções, %s blocos', v_tot, v_n)));
  v_res := pg_temp.ok(v_res, 'M9b a migration só cria as 11 recriadas e as 9 novas: nenhuma outra função, nenhuma tabela, nenhum dado',
    (select count(*) from regexp_matches(v_mig, 'create or replace function public\.', 'g')) = 20
    and position('alter table' in lower(regexp_replace(v_mig, '--[^\n]*', '', 'g'))) = 0
    and position('create table' in lower(regexp_replace(v_mig, '--[^\n]*', '', 'g'))) = 0,
    (select count(*)::text from regexp_matches(v_mig, 'create or replace function public\.', 'g')));
  perform pg_temp.gravar(v_res);
end
$m9$;

-- ── M10. A revisão não corta a estrada (R6.9-2) ────────────────────────────────────────────────────────────────────
do $m10$
declare
  v_res jsonb := '[]'::jsonb;
  v_os  uuid;
  v_m   jsonb;
  v_pm  jsonb;
  v_c   jsonb;
  v_p   uuid;
  v_h   date := date '2027-07-16';
  v_ag  timestamptz := pg_temp.em(date '2027-07-16', '16:20');
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('M10 a revisão e a estrada', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.gestor();
    perform pg_temp.modos('sombra');
    perform pg_temp.dono(array['OS-J7', 'OS-J6'], 'nunca');
    v_os := pg_temp.os('OS-J7');
    v_p := pg_temp.pessoa('Bruno');
    -- publicada com a estrada: 4 meios-dias, 2 de serviço + 2 de estrada
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    select md5('m10:' || x.dia || x.turno)::uuid, v_os, v_p, x.dia, x.turno, 'turno', 'execucao', 'publicada', 'motor', v_ag
      from (values (date '2027-07-26', 'manha'), (date '2027-07-26', 'tarde'), (date '2027-07-27', 'manha'), (date '2027-07-27', 'tarde')) x(dia, turno);
    update public.os_planejamento set estimativa_fonte = 'orcamento' where service_order_id = v_os;
    v_m := public.agenda_meios_da_os(v_os, v_h);
    v_pm := public._agenda_gestor_pessoa_meios(v_os, v_h, v_m);
    v_res := pg_temp.ok(v_res, 'M10a em teste, o precisa não tem a estrada, byte a byte: a de antes (a revisão acharia 2 a mais)',
      (v_pm ->> 'precisa')::int = (v_m ->> 'total')::int * (v_pm ->> 'pessoas')::int and (v_pm ->> 'tem')::numeric = 4, v_pm::text);
    v_c := public._agenda_gestor_corte(v_os, v_h, v_ag);
    v_res := pg_temp.ok(v_res, 'M10b em teste, o corte acha a sobra de 2 (a régua)', (v_c ->> 'sobra')::int = 2, v_c::text);
    perform pg_temp.modo('modo_viagem', 'ligado');
    v_pm := public._agenda_gestor_pessoa_meios(v_os, v_h, v_m);
    v_res := pg_temp.ok(v_res, 'M10c com a viagem ligada, o precisa soma os meios de estrada × as pessoas: 2 + 2 = 4',
      (v_pm ->> 'precisa')::int = 4 and (v_pm ->> 'tem')::numeric = 4 and (v_pm ->> 'pessoas')::int = 1, v_pm::text);
    v_c := public._agenda_gestor_corte(v_os, v_h, v_ag);
    v_res := pg_temp.ok(v_res, 'M10d com a viagem ligada, nada a cortar: a revisão não diz "o orçamento mudou"', v_c ->> 'motivo' = 'nada_a_cortar', v_c::text);
    v_pm := public._agenda_gestor_pessoa_meios(v_os, v_h, v_m || '{"sem_estrada": true}'::jsonb);
    v_res := pg_temp.ok(v_res, 'M10e a marca sem_estrada corta a recursão: a conta de antes', (v_pm ->> 'precisa')::int = 2, v_pm::text);
    v_pm := public._agenda_gestor_pessoa_meios(pg_temp.os('OS-J6'), v_h, public.agenda_meios_da_os(pg_temp.os('OS-J6'), v_h));
    v_res := pg_temp.ok(v_res, 'M10f a pernoite: 4 + 2 = 6', (v_pm ->> 'precisa')::int = 6, v_pm::text);
    v_pm := public._agenda_gestor_pessoa_meios(pg_temp.os('OS-J8'), v_h, public.agenda_meios_da_os(pg_temp.os('OS-J8'), v_h));
    v_res := pg_temp.ok(v_res, 'M10g a regional: nada a somar', (v_pm ->> 'precisa')::int = 2, v_pm::text);
    perform pg_temp.modo('modo_viagem', 'desligado');
    v_pm := public._agenda_gestor_pessoa_meios(v_os, v_h, v_m);
    v_res := pg_temp.ok(v_res, 'M10h desligado: nada a somar', (v_pm ->> 'precisa')::int = 2, v_pm::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$m10$;

-- ── M11. A escada e o validador conhecem o local (R6.9-3) ──────────────────────────────────────────────────────────
do $m11$
declare
  v_res jsonb := '[]'::jsonb;
  v     jsonb;
  v_it  jsonb;
  v_h   date := date '2027-07-16';
  v_ag  timestamptz := pg_temp.em(date '2027-07-16', '16:20');
  v_os  uuid;
  v_al  jsonb;
  v_adm uuid;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('M11 a escada e o validador', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  v_adm := (select id from public.app_users where role = 'admin' and active order by created_at limit 1);
  begin
    perform pg_temp.gestor();
    perform pg_temp.modos('sombra');
    v_os := pg_temp.os('OS-J3');
    v_al := jsonb_build_array(jsonb_build_object('payee_id', pg_temp.pessoa('Alex'), 'nome', 'Alex', 'dia', '2027-07-20', 'turno', 'manha', 'presenca', 'turno'));
    v_it := jsonb_build_array(jsonb_build_object('op', 'criar', 'os', v_os, 'numero', 'OS-J3', 'tipo', 'execucao', 'alocacoes', v_al, 'evento_real', false,
                                                 'fixar_dono', false, 'abre', false, 'fecha', false, 'critica', null, 'decisao', null));
    v := public._agenda_validar_itens(v_it, '{"p_restricoes": {}}'::jsonb, v_h, v_ag, false, null);
    v_res := pg_temp.ok(v_res, 'M11a em teste, a regra 3 não olha o local', not exists (select 1 from jsonb_array_elements(v) e where e ->> 'regra' = '3'), v::text);
    perform pg_temp.modo('modo_local_calendario', 'ligado');
    v := public._agenda_validar_itens(v_it, '{"p_restricoes": {}}'::jsonb, v_h, v_ag, false, null);
    v_res := pg_temp.ok(v_res, 'M11b ligado, a regra 3 soma a máscara: nada no dia que o local não recebe, com o motivo (a escada passa por aqui)',
      exists (select 1 from jsonb_array_elements(v) e where e ->> 'regra' = '3' and e ->> 'texto' = 'OS-J3 ter 20/07: ter 20/07 é feriado em Balneário Camboriú.'), v::text);
    v := public._agenda_validar_itens(jsonb_set(v_it, '{0,tipo}', '"reserva"'), '{"p_restricoes": {}}'::jsonb, v_h, v_ag, false, null);
    v_res := pg_temp.ok(v_res, 'M11c a reserva fica de fora, como a regra 3 de antes', not exists (select 1 from jsonb_array_elements(v) e where e ->> 'regra' = '3'), v::text);
    v := public._agenda_validar_itens(jsonb_set(v_it, '{0,fixar_dono}', 'true'), '{"p_restricoes": {}}'::jsonb, v_h, v_ag, false, null);
    v_res := pg_temp.ok(v_res, 'M11d o pedido do dono fica de fora, como a regra 3 de antes', not exists (select 1 from jsonb_array_elements(v) e where e ->> 'regra' = '3'), v::text);
    -- o meio-dia fora do horário
    update public.agenda_locais set abre = time '13:00', atualizado_por = v_adm where nome = 'Marina Itajaí';
    v_os := pg_temp.os('OS-J9');
    v_it := jsonb_set(jsonb_set(jsonb_set(v_it, '{0,os}', to_jsonb(v_os)), '{0,numero}', '"OS-J9"'), '{0,alocacoes,0,dia}', '"2027-07-21"');
    v := public._agenda_validar_itens(v_it, '{"p_restricoes": {}}'::jsonb, v_h, v_ag, false, null);
    v_res := pg_temp.ok(v_res, 'M11e ligado, o meio-dia fora do horário do local conferido também',
      exists (select 1 from jsonb_array_elements(v) e where e ->> 'regra' = '3' and e ->> 'texto' = 'OS-J9 qua 21/07: o local não recebe a equipe nesse meio-dia.'), v::text);
    v := public._agenda_validar_itens(jsonb_set(v_it, '{0,alocacoes,0,turno}', '"tarde"'), '{"p_restricoes": {}}'::jsonb, v_h, v_ag, false, null);
    v_res := pg_temp.ok(v_res, 'M11f a tarde do mesmo dia passa', not exists (select 1 from jsonb_array_elements(v) e where e ->> 'regra' = '3'), v::text);
    -- a regra 13: o dia fechado não é dia parado
    update public.agenda_config set interrupcoes_max = 0 where id;
    v_os := pg_temp.os('OS-J3');
    v_al := jsonb_build_array(jsonb_build_object('payee_id', pg_temp.pessoa('Alex'), 'nome', 'Alex', 'dia', '2027-07-19', 'turno', 'manha', 'presenca', 'turno'),
                              jsonb_build_object('payee_id', pg_temp.pessoa('Alex'), 'nome', 'Alex', 'dia', '2027-07-21', 'turno', 'manha', 'presenca', 'turno'));
    v_it := jsonb_build_array(jsonb_build_object('op', 'criar', 'os', v_os, 'numero', 'OS-J3', 'tipo', 'execucao', 'alocacoes', v_al, 'evento_real', false,
                                                 'fixar_dono', false, 'abre', false, 'fecha', false, 'critica', null, 'decisao', null));
    v := public._agenda_validar_itens(v_it, '{"p_restricoes": {}}'::jsonb, v_h, v_ag, false, null);
    v_res := pg_temp.ok(v_res, 'M11g ligado, a regra 13 não conta o dia fechado como parado (o motor o pula): sem isto, o bloco que atravessa 20/07 sairia inválido',
      not exists (select 1 from jsonb_array_elements(v) e where e ->> 'regra' = '13'), v::text);
    perform pg_temp.modo('modo_local_calendario', 'sombra');
    v := public._agenda_validar_itens(v_it, '{"p_restricoes": {}}'::jsonb, v_h, v_ag, false, null);
    v_res := pg_temp.ok(v_res, 'M11h em teste, a regra 13 de antes conta', exists (select 1 from jsonb_array_elements(v) e where e ->> 'regra' = '13'), v::text);
    -- o dia parado de verdade continua contando, com o modo ligado
    perform pg_temp.modo('modo_local_calendario', 'ligado');
    v_it := jsonb_set(v_it, '{0,alocacoes,1,dia}', '"2027-07-23"');
    v := public._agenda_validar_itens(v_it, '{"p_restricoes": {}}'::jsonb, v_h, v_ag, false, null);
    v_res := pg_temp.ok(v_res, 'M11i ligado, o dia parado de verdade (qua 21, qui 22) continua violando a regra 13', exists (select 1 from jsonb_array_elements(v) e where e ->> 'regra' = '13'), v::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- A escada na pernoite
  begin
    perform pg_temp.gestor();
    perform pg_temp.modos('sombra');
    perform pg_temp.dono(array['OS-J6'], 'nunca');
    v_os := pg_temp.os('OS-J6');
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    select md5('m11:' || x.dia || x.turno)::uuid, v_os, pg_temp.pessoa('Rafael'), x.dia, x.turno, 'turno', 'execucao', 'publicada', 'motor', v_ag
      from (values (date '2027-07-21', 'manha'), (date '2027-07-21', 'tarde'), (date '2027-07-22', 'manha'), (date '2027-07-22', 'tarde'),
                   (date '2027-07-23', 'manha'), (date '2027-07-23', 'tarde')) x(dia, turno);
    update public.payees set active = false where id = pg_temp.pessoa('Rafael');
    v := public._agenda_gestor_reparo(v_os, v_h, v_ag);
    v_res := pg_temp.ok(v_res, 'M11j a referência, em teste: a escada olha a OS de viagem (a violação é de pessoa)', v ->> 'motivo' is distinct from 'fora_da_escada', v::text);
    perform pg_temp.modo('modo_viagem', 'ligado');
    v := public._agenda_gestor_reparo(v_os, v_h, v_ag);
    v_res := pg_temp.ok(v_res, 'M11k com a viagem ligada, a OS de pernoite é fora_da_escada: a troca de pessoa quebraria a mesma equipe', v ->> 'motivo' = 'fora_da_escada' and not (v ->> 'reparavel')::boolean, v::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$m11$;

-- ── M12. O freio (R6.7b) ───────────────────────────────────────────────────────────────────────────────────────────
do $m12$
declare
  v_res jsonb := '[]'::jsonb;
  v_oss uuid[];
  a     text;
  b     text;
  c     text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('M12 o freio', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  v_oss := pg_temp.lista(array['OS-J1', 'OS-J2', 'OS-J3', 'OS-J4', 'OS-J5', 'OS-J6', 'OS-J7', 'OS-J8', 'OS-J9', 'OS-J10']);
  begin
    perform pg_temp.gestor();
    perform pg_temp.dono(array['OS-J6', 'OS-J7', 'OS-J9', 'OS-J10'], 'nunca');
    update public.agenda_config set gestor_so_propor = true, gestor_so_propor_em = timestamptz '2027-07-15 10:00-03' where id;
    perform pg_temp.modos('sombra');
    a := pg_temp.retrato(date '2027-07-16', v_oss, date '2027-07-12');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.gestor();
    perform pg_temp.dono(array['OS-J6', 'OS-J7', 'OS-J9', 'OS-J10'], 'nunca');
    update public.agenda_config set gestor_so_propor = true, gestor_so_propor_em = timestamptz '2027-07-15 10:00-03' where id;
    perform pg_temp.modos('ligado');
    b := pg_temp.retrato(date '2027-07-16', v_oss, date '2027-07-12');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.gestor();
    perform pg_temp.dono(array['OS-J6', 'OS-J7', 'OS-J9', 'OS-J10'], 'nunca');
    perform pg_temp.modos('ligado');
    c := pg_temp.retrato(date '2027-07-16', v_oss, date '2027-07-12');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M12a com os 6 modos ligados e *gestor, só propor*, o retrato inteiro é o de em teste (md5): o freio devolve tudo a sombra', a = b, a || ' × ' || b);
  v_res := pg_temp.ok(v_res, 'M12b sem o freio, os mesmos modos ligados mudam o retrato (a régua: sem isto, a prova de cima não prova nada)', b <> c, c);
  begin
    perform pg_temp.gestor();
    perform pg_temp.modos('ligado');
    update public.agenda_config set gestor_so_propor = true where id;
    v_res := pg_temp.ok(v_res, 'M12c todo leitor passa pelo freio: o contexto, a violação com a variável, a escada e o precisa',
      not public._agenda_contexto(date '2027-07-12', date '2027-08-29', date '2027-07-16', '{}'::uuid[], v_oss) ?| array['mun', 'pat']
      and public._agenda_gestor_estrada(pg_temp.os('OS-J7'), date '2027-07-16', public.agenda_meios_da_os(pg_temp.os('OS-J7'), date '2027-07-16')) = '{}'::jsonb, null);
    perform set_config('agenda.local_violacao', 'on', true);
    v_res := pg_temp.ok(v_res, 'M12d com o freio, a variável ligada não acorda a violação local',
      not exists (select 1 from jsonb_array_elements(pg_temp.j(array['OS-J1']) -> 'itens') x where x ->> 'motivo' = 'local'), null);
    perform set_config('agenda.local_violacao', '', true);
    -- a escada e o validador com o freio: a OS de pernoite segue a escada, e o dia fechado passa
    perform pg_temp.dono(array['OS-J6'], 'nunca');
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    select md5('m12:' || x.turno)::uuid, pg_temp.os('OS-J6'), pg_temp.pessoa('Rafael'), date '2027-07-21', x.turno, 'turno', 'execucao', 'publicada', 'motor', pg_temp.em(date '2027-07-16', '10:00')
      from (values ('manha'), ('tarde')) x(turno);
    update public.payees set active = false where id = pg_temp.pessoa('Rafael');
    v_res := pg_temp.ok(v_res, 'M12e com o freio, a escada não vê a pernoite', public._agenda_gestor_reparo(pg_temp.os('OS-J6'), date '2027-07-16', pg_temp.em(date '2027-07-16', '16:20')) ->> 'motivo' is distinct from 'fora_da_escada', null);
    v_res := pg_temp.ok(v_res, 'M12f com o freio, a regra 3 não soma a máscara',
      not exists (select 1 from jsonb_array_elements(public._agenda_validar_itens(jsonb_build_array(jsonb_build_object('op', 'criar', 'os', pg_temp.os('OS-J3'), 'numero', 'OS-J3', 'tipo', 'execucao',
                    'alocacoes', jsonb_build_array(jsonb_build_object('payee_id', pg_temp.pessoa('Alex'), 'nome', 'Alex', 'dia', '2027-07-20', 'turno', 'manha', 'presenca', 'turno')),
                    'evento_real', false, 'fixar_dono', false, 'abre', false, 'fecha', false, 'critica', null, 'decisao', null)), '{"p_restricoes": {}}'::jsonb, date '2027-07-16', pg_temp.em(date '2027-07-16', '16:20'), false, null)) e where e ->> 'regra' = '3'), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$m12$;

-- ── M13. A matriz: os cenários J com cada modo, um a um e juntos ───────────────────────────────────────────────────
do $m13$
declare
  v_res  jsonb := '[]'::jsonb;
  c      record;
  v      jsonb;
  v_base jsonb;
  v_oss  text[] := array['OS-J1', 'OS-J2', 'OS-J3', 'OS-J4', 'OS-J5', 'OS-J6', 'OS-J7', 'OS-J8', 'OS-J9', 'OS-J10', 'OS-J11', 'OS-J12', 'OS-J13', 'OS-J14'];
  v_err  text;
  v_nov  text;
  v_h    date := date '2027-07-16';
  v_ag   timestamptz := pg_temp.em(date '2027-07-16', '16:20');
  v_id   uuid;
  v_alo  int;
  v_can  int;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('M13 a matriz', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  for c in select * from (values
      ('modo_local_calendario'), ('modo_local_autorizacao'), ('modo_bem'), ('modo_patio'), ('modo_viagem'), ('modo_mesmo_local'), ('todos')) t(modo) loop
    begin
      perform pg_temp.gestor();
      perform pg_temp.modos('sombra');
      perform pg_temp.dono(array['OS-J3', 'OS-J4', 'OS-J5', 'OS-J6', 'OS-J7', 'OS-J8', 'OS-J9', 'OS-J10', 'OS-J11', 'OS-J14'], 'nunca');
      v_base := pg_temp.j(v_oss);
      if c.modo = 'todos' then
        perform pg_temp.modos('ligado');
      else
        perform pg_temp.modo(c.modo, 'ligado');
      end if;
      -- a proposta sai válida (agenda_propor lança se não) e a do dia seguinte também, gravada
      v := pg_temp.j(v_oss);
      if c.modo = 'todos' then
        v_nov := pg_temp.projecao(v);
      end if;
      perform public.agenda_propor('os', null, null, pg_temp.lista(v_oss), '{}'::jsonb, true, 'vigia', null, v_h, v_ag);
      -- cada modo só mexe no que é dele
      if c.modo = 'modo_local_autorizacao' and pg_temp.projecao(v) <> pg_temp.projecao(v_base) then
        v_err := concat_ws('; ', v_err, 'o acesso mudou a projeção');
      end if;
      -- nada em 20/07 no que o local em BC não recebe (o que entra; o publicado de antes é da rodada diária)
      if c.modo in ('modo_local_calendario', 'todos') and exists (
           select 1 from jsonb_array_elements(v -> 'itens') i, jsonb_array_elements(i -> 'alocacoes') a
            where i ->> 'op' = 'criar' and a ->> 'dia' = '2027-07-20' and i ->> 'numero' in ('OS-J1', 'OS-J3', 'OS-J4', 'OS-J5', 'OS-J11', 'OS-J14')) then
        v_err := concat_ws('; ', v_err, 'o calendário deixou 20/07: ' || pg_temp.projecao(v));
      end if;
      if c.modo = 'modo_patio' and exists (select 1 from jsonb_array_elements(v -> 'itens') i where i ? 'viagem') then
        v_err := concat_ws('; ', v_err, 'o pátio pôs viagem no item');
      end if;
      if c.modo = 'modo_mesmo_local' and pg_temp.n_meios(pg_temp.item(v, 'OS-J6')) <> 4 then
        v_err := concat_ws('; ', v_err, 'o mesmo local somou a estrada');
      end if;
      if c.modo = 'modo_viagem' and (pg_temp.n_meios(pg_temp.item(v, 'OS-J6')) <> 6 or pg_temp.n_meios(pg_temp.item(v, 'OS-J7')) <> 4) then
        v_err := concat_ws('; ', v_err, 'a viagem não somou a estrada: ' || pg_temp.projecao(v));
      end if;
      if c.modo in ('modo_viagem', 'modo_patio', 'modo_local_calendario', 'modo_mesmo_local', 'todos')
         and not exists (select 1 from jsonb_array_elements(v -> 'itens') i where i ->> 'op' = 'criar' and i ? 'local_texto') then
        v_err := concat_ws('; ', v_err, c.modo || ' sem local_texto');
      end if;
      if c.modo = 'modo_bem' and exists (select 1 from jsonb_array_elements(v -> 'itens') i where i ->> 'op' = 'criar' and i ? 'local_texto') then
        v_err := concat_ws('; ', v_err, 'modo_bem sozinho leu o local no motor (R6.8-1)');
      end if;
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
      when others then
        v_err := concat_ws('; ', v_err, c.modo || ': ' || sqlerrm);
    end;
  end loop;
  v_res := pg_temp.ok(v_res, 'M13a J inteiro pelo motor com cada um dos 6 modos ligado e com todos: a proposta sai válida, simulada e gravada, e cada modo só mexe no que é dele',
    v_err is null, coalesce(v_err, v_nov));
  -- O caminho inteiro da rodada do P5: com a variável, agenda_replanejar cancela com o motivo local (a lista fechada) e publica fora do feriado
  begin
    perform pg_temp.gestor();
    perform pg_temp.modos('ligado');
    perform set_config('agenda.local_violacao', 'on', true);
    v := public.agenda_replanejar(array[pg_temp.os('OS-J1')], 'local', 'vigia', v_h, v_ag);
    perform set_config('agenda.local_violacao', '', true);
    select count(*) filter (where a.estado = 'cancelada' and a.cancelada_motivo = 'local'),
           count(*) filter (where a.estado in ('publicada', 'fixada') and a.dia > date '2027-07-20')
      into v_can, v_alo
      from public.agenda_alocacoes a where a.service_order_id = pg_temp.os('OS-J1');
    v_res := pg_temp.ok(v_res, 'M13b agenda_replanejar com a variável: a publicada em 20/07 sai com cancelada_motivo = local e a OS volta depois do feriado',
      v_can = 2 and v_alo >= 1, format('canceladas %s, novas %s; %s', v_can, v_alo, v::text));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$m13$;

select teste, ok, detalhe from _resultado order by teste;
rollback;
