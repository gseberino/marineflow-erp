-- Prova dos consertos de 12/11/2026 da Agenda de Produção (migration 20261112300000_agenda_consertos_carona_where.sql): a carona chamada
-- só com p_autor, p_os e p_canal (como o ai-agent chama pelo PostgREST) e o UPDATE/DELETE sem WHERE (o pg_safeupdate do PostgREST recusa).
-- bancada: depende de 20261112300000
--
--   C0  a carona: p_hoje = _hoje_brt() e p_agora = now() por padrão; o corpo de 20261027100300 byte a byte (md5 sem CR, o de produção em
--       12/11); 1 assinatura só; definer com search_path, volátil; só service_role executa
--   C1  o dia padrão perto da meia-noite UTC: _hoje_brt() é (now() at time zone 'America/Sao_Paulo')::date; com now() em 12/11 00:49 UTC
--       (a hora do 404 em produção) dá 11/11, 02:59:59 UTC ainda 11/11, 03:00 UTC 12/11 — com a sessão em UTC, em São Paulo e em
--       Kiritimati (UTC+14)
--   C2  a chamada só com os 3 nomes acha a função (notação nomeada, posicional e pelo json_to_record, o formato da chamada do PostgREST):
--       p_autor nulo = null, sem gravar nada (vale em produção)
--   C3  (fixture-fase3) a carona de verdade só com os 3 nomes: "Aproveitando: …", carona_em = now(); a mesma resposta da chamada com
--       p_hoje = _hoje_brt() e p_agora = now()
--   C4  (fixture-fase3) o dia é o de São Paulo, não o da sessão: com a sessão em Kiritimati (outro dia), a pergunta que saiu hoje no
--       fechamento não vai de novo; com p_hoje = current_date ela iria (a prova de que o teste distingue)
--   W1  agenda_cliente_decidir_dito: o corpo de 20261028100800 + só a linha marcada ("where true"); defaults, definer e portas de antes
--   W2  o detector de UPDATE/DELETE sem WHERE no nível de cima: acusa o que tem de acusar; não acusa o ';' de um texto (o falso positivo
--       de _agenda_aplicar_habilidade na consulta de referência), "for update", "do update set" nem o WHERE dentro de "with x as (…)"
--   W3  nenhuma função da agenda (agenda*, _agenda*) com UPDATE/DELETE sem WHERE no nível de cima (vale em produção)
--   W4  (fixture-fase3) *segura cliente* duas vezes na mesma transação: o "where true" limpa a tabela temporária (uma linha esquecida
--       nela mudaria a resposta)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_consertos_carona_where.sql
--   Sem a fixture (produção) C3, C4 e W4 saem PULADO; C0–C2 e W1–W3 rodam e não gravam nada. Termina em ROLLBACK.
-- O que este teste NÃO roda: o PostgREST de verdade (a busca da função pelos nomes e o pg_safeupdate, que a bancada não tem). A chamada
-- nomeada com os 3 argumentos é a que o PostgREST monta; o safeupdate só olha se o UPDATE/DELETE tem WHERE (W2 e W3).
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

set local timezone = 'UTC';

-- Tira os parênteses equilibrados (de dentro para fora) e corta no 1º que sobrar: o que fica é o nível de cima do comando.
create function pg_temp.nivel_de_cima(p text) returns text language plpgsql immutable as $f$
declare
  n text;
begin
  loop
    n := regexp_replace(p, '\([^()]*\)', '', 'g');
    exit when n = p;
    p := n;
  end loop;
  return regexp_replace(p, '[()].*$', '');
end
$f$;

-- Os comandos UPDATE/DELETE sem WHERE no nível de cima de um corpo PL/pgSQL (sem comentários de linha; os literais em branco).
create function pg_temp.sem_where(p_corpo text) returns setof text language sql immutable as $f$
  with c as (
    select regexp_replace(regexp_replace(p_corpo, '--[^\n]*', '', 'g'), '''(?:[^'']|'''')*''', '''''', 'g') as corpo
  ), cmds as (
    select m[1] as cmd
      from c, regexp_matches(c.corpo,
        '(?<![a-z0-9_.])(?<!for\s)(?<!do\s)((?:update|delete\s+from)\s+(?:only\s+)?(?!(?:set|of|on|or|loop|skip|nowait)\M)(?:[a-z_][a-z0-9_]*\.)?[a-z_][a-z0-9_]*\M[^;]*)',
        'gi') as m
  )
  select btrim(regexp_replace(cmd, '\s+', ' ', 'g')) from cmds where pg_temp.nivel_de_cima(cmd) !~* '\mwhere\M'
$f$;

-- ── C0. A forma da carona ──────────────────────────────────────────────────────────────────────────────────────────────────────

insert into _resultado
select 'C0 a carona: p_hoje = _hoje_brt() e p_agora = now() por padrão; o corpo de 20261027100300 (md5 b1186db6…); 1 assinatura; definer, search_path, volátil; só service_role',
       coalesce((
         select p.pronargdefaults = 2
            and pg_get_function_arguments(p.oid) ~ '^p_autor uuid, p_os text\[\], p_canal text, p_hoje date DEFAULT (public\.)?_hoje_brt\(\), p_agora timestamp with time zone DEFAULT now\(\)$'
            and md5(replace(p.prosrc, chr(13), '')) = 'b1186db65b9e98fe8b7326607036d5aa'
            and p.prosecdef and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=public%' and p.provolatile = 'v'
            and has_function_privilege('service_role', p.oid, 'execute')
            and not has_function_privilege('authenticated', p.oid, 'execute')
            and not has_function_privilege('anon', p.oid, 'execute')
            and (select count(*) from pg_proc x where x.pronamespace = 'public'::regnamespace and x.proname = 'agenda_carona') = 1
           from pg_proc p where p.oid = to_regprocedure('public.agenda_carona(uuid, text[], text, date, timestamptz)')), false),
       (select pg_get_function_arguments(p.oid) || ' | md5 ' || md5(replace(p.prosrc, chr(13), ''))
          from pg_proc p where p.oid = to_regprocedure('public.agenda_carona(uuid, text[], text, date, timestamptz)'));

-- ── C1. O dia padrão perto da meia-noite UTC ───────────────────────────────────────────────────────────────────────────────────

do $c1$
declare
  v_src  text := (select p.prosrc from pg_proc p where p.oid = to_regprocedure('public._hoje_brt()'));
  v_expr text;
  v_tz   text;
  v_d1   date;
  v_d2   date;
  v_d3   date;
  v_ok   boolean := true;
  v_det  text := '';
begin
  v_expr := rtrim(btrim(coalesce(v_src, '')), '; ');
  if lower(regexp_replace(v_expr, '\s+', ' ', 'g')) <> 'select (now() at time zone ''america/sao_paulo'')::date' then
    insert into _resultado values ('C1 o dia padrão perto da meia-noite UTC é o de São Paulo', false, 'o corpo de _hoje_brt mudou: ' || coalesce(v_src, '(sem a função)'));
    return;
  end if;
  foreach v_tz in array array['UTC', 'America/Sao_Paulo', 'Pacific/Kiritimati'] loop
    perform set_config('timezone', v_tz, true);
    execute replace(v_expr, 'now()', '''2026-11-12 00:49:00+00''::timestamptz') into v_d1;
    execute replace(v_expr, 'now()', '''2026-11-12 02:59:59+00''::timestamptz') into v_d2;
    execute replace(v_expr, 'now()', '''2026-11-12 03:00:00+00''::timestamptz') into v_d3;
    v_ok := v_ok and v_d1 = date '2026-11-11' and v_d2 = date '2026-11-11' and v_d3 = date '2026-11-12';
    v_det := v_det || format('%s: %s %s %s; ', v_tz, v_d1, v_d2, v_d3);
  end loop;
  perform set_config('timezone', 'UTC', true);
  insert into _resultado values ('C1 o dia padrão (_hoje_brt) perto da meia-noite UTC é o de São Paulo: 00:49 e 02:59:59 UTC de 12/11 = 11/11; 03:00 = 12/11; em qualquer fuso da sessão',
    v_ok, v_det);
end
$c1$;

-- ── C2. A chamada só com os 3 nomes ────────────────────────────────────────────────────────────────────────────────────────────

do $c2$
declare
  r1 jsonb;
  r2 jsonb;
  r3 jsonb;
  v_antes text := (select md5(coalesce(string_agg(q.id::text || coalesce(q.carona_em::text, '-'), ',' order by q.id), '')) from public.agenda_perguntas q);
  v_err text := '';
begin
  begin
    r1 := public.agenda_carona(p_autor => null::uuid, p_os => array['OS-00112'], p_canal => 'whatsapp');
    r2 := public.agenda_carona(null::uuid, array['OS-00112'], 'painel');
    select public.agenda_carona(p_autor := b.p_autor, p_os := b.p_os, p_canal := b.p_canal) into r3
      from json_to_record('{"p_autor": null, "p_os": ["OS-00112"], "p_canal": "whatsapp"}'::json) as b(p_autor uuid, p_os text[], p_canal text);
  exception when others then
    v_err := sqlstate || ' ' || sqlerrm;
  end;
  insert into _resultado values ('C2 só com p_autor, p_os e p_canal (nomeada, posicional e pelo json_to_record do PostgREST): acha a função; p_autor nulo = null; nada gravado',
    v_err = '' and r1 is null and r2 is null and r3 is null
    and v_antes = (select md5(coalesce(string_agg(q.id::text || coalesce(q.carona_em::text, '-'), ',' order by q.id), '')) from public.agenda_perguntas q),
    nullif(v_err, ''));
end
$c2$;

-- ── C3, C4 e W4. Com a carteira da Fase 3 ──────────────────────────────────────────────────────────────────────────────────────

do $cen$
declare
  c_admin constant uuid := 'aa000000-0000-4000-8000-000000000001';
  d04     constant date := date '2026-11-04';
  r3      jsonb;
  r5      jsonb;
  r_def   jsonb;
  r_cd    jsonb;
  r1      jsonb;
  r2      jsonb;
  v_q     uuid;
  v_car   timestamptz;
  v_agora timestamptz;
  v_sess  date;
  v_n     int;
  v_err   text := '';
  v_err3  text := '';
  v_err4  text := '';
begin
  if coalesce(current_setting('agenda_teste.fase3', true), '') = '' then
    insert into _resultado values
      ('C3 a carona de verdade só com os 3 nomes', true, 'PULADO: sem agenda_teste.fase3 (rode pela bancada)'),
      ('C4 o dia é o de São Paulo, não o da sessão', true, 'PULADO: sem agenda_teste.fase3 (rode pela bancada)'),
      ('W4 *segura cliente* 2x na mesma transação', true, 'PULADO: sem agenda_teste.fase3 (rode pela bancada)');
    return;
  end if;
  execute current_setting('agenda_teste.fase3');
  -- as perguntas da OS-00112 (o Nelson: a decisão "não cabe" aberta e o "chegou?" do painel), como no K do agenda_fase3_acompanhamento.sql
  perform public.agenda_vigiar(d04, (d04 + time '09:00') at time zone 'America/Sao_Paulo');

  -- C3: só com os 3 nomes × com p_hoje = _hoje_brt() e p_agora = now(), cada uma desfeita
  begin
    r3 := public.agenda_carona(p_autor => c_admin, p_os => array['OS-00112'], p_canal => 'whatsapp');
    select q.carona_em into v_car from public.agenda_perguntas q where q.id = (r3 ->> 'pergunta_id')::uuid;
    v_agora := now();
    raise exception 'desfaz' using errcode = 'P0099';
  exception
    when sqlstate 'P0099' then null;
    when others then v_err3 := sqlstate || ' ' || sqlerrm;
  end;
  begin
    r5 := public.agenda_carona(c_admin, array['OS-00112'], 'whatsapp', public._hoje_brt(), now());
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  insert into _resultado values ('C3 a carona de verdade só com os 3 nomes: "Aproveitando: …", carona_em = now(); igual à chamada com p_hoje = _hoje_brt() e p_agora = now()',
    v_err3 = '' and r3 ->> 'texto' like 'Aproveitando: %' and v_car = v_agora and r3 = r5,
    coalesce(nullif(v_err3, ''), coalesce(r3::text, 'null') || ' / ' || coalesce(r5::text, 'null')));

  -- C4: a pergunta escolhida já saiu hoje (São Paulo) no fechamento; a sessão em Kiritimati (UTC+14) está em outro dia
  v_q := (r5 ->> 'pergunta_id')::uuid;
  begin
    perform set_config('timezone', 'Pacific/Kiritimati', true);
    v_sess := current_date;
    update public.agenda_perguntas set mostrada_via = 'fechamento', mostrada_em = now(), mostrada_vezes = mostrada_vezes + 1 where id = v_q;
    r_def := public.agenda_carona(p_autor => c_admin, p_os => array['OS-00112'], p_canal => 'whatsapp');
    raise exception 'desfaz' using errcode = 'P0099';
  exception
    when sqlstate 'P0099' then null;
    when others then v_err4 := sqlstate || ' ' || sqlerrm;
  end;
  begin
    perform set_config('timezone', 'Pacific/Kiritimati', true);
    update public.agenda_perguntas set mostrada_via = 'fechamento', mostrada_em = now(), mostrada_vezes = mostrada_vezes + 1 where id = v_q;
    r_cd := public.agenda_carona(c_admin, array['OS-00112'], 'whatsapp', current_date, now());
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  insert into _resultado values ('C4 o dia é o de São Paulo, não o da sessão: em Kiritimati (outro dia), a que saiu hoje no fechamento não vai de novo; com p_hoje = current_date iria',
    v_err4 = '' and v_q is not null and v_sess <> public._hoje_brt() and r_def is null and (r_cd ->> 'pergunta_id')::uuid = v_q,
    coalesce(nullif(v_err4, ''),
             format('sessão %s, São Paulo %s; padrão %s; current_date %s', v_sess, public._hoje_brt(), coalesce(r_def::text, 'null'), coalesce(r_cd::text, 'null'))));

  -- W4: *segura cliente* com um nome que não existe, duas vezes; entre as duas, uma linha esquecida na tabela temporária
  begin
    update public.agenda_config set modo_cliente = 'ligado' where id;
    r1 := public.agenda_cliente_decidir_dito(c_admin, 'segura', 'Ninguém Deste Nome', 'whatsapp', d04, now());
    insert into _agenda_cliente_alvo (id, pergunta_id, estado, aprovacao, enviar_em, client_id, nome, completo)
    values (gen_random_uuid(), null, 'aguardando_dono', 'pedida', now(), gen_random_uuid(), 'Esquecido', 'Esquecido');
    r2 := public.agenda_cliente_decidir_dito(c_admin, 'segura', 'Ninguém Deste Nome', 'whatsapp', d04, now());
    select count(*) into v_n from _agenda_cliente_alvo;
    raise exception 'desfaz' using errcode = 'P0099';
  exception
    when sqlstate 'P0099' then null;
    when others then v_err := sqlstate || ' ' || sqlerrm;
  end;
  insert into _resultado values ('W4 *segura cliente* 2x na mesma transação: o "where true" limpa a tabela temporária (a linha esquecida não conta)',
    v_err = '' and r1 ->> 'status' = 'nao_achei' and r2 = r1 and v_n = 0,
    coalesce(nullif(v_err, ''), coalesce(r1::text, 'null') || ' / ' || coalesce(r2::text, 'null') || ' / linhas ' || coalesce(v_n::text, '?')));
end
$cen$;

-- ── W1. agenda_cliente_decidir_dito: só a linha marcada ───────────────────────────────────────────────────────────────────────

insert into _resultado
select 'W1 agenda_cliente_decidir_dito: o corpo de 20261028100800 (md5 ee49cf50…) + só a linha marcada ("where true"); defaults, definer e portas de antes',
       coalesce((
         select md5(replace(replace(replace(p.prosrc, chr(13), ''),
                  '  -- CONSERTO 12/11 (pg_safeupdate): pelo PostgREST, DELETE sem WHERE é recusado (HTTP 400); "where true" apaga tudo, como antes.' || E'\n', ''),
                  'delete from _agenda_cliente_alvo where true;', 'delete from _agenda_cliente_alvo;')) = 'ee49cf5005d294fde1f125c7550fbe0e'
            and (char_length(p.prosrc) - char_length(replace(p.prosrc, 'delete from _agenda_cliente_alvo where true;', '')))
                = char_length('delete from _agenda_cliente_alvo where true;')
            and pg_get_function_arguments(p.oid) ~ '^p_autor uuid, p_acao text, p_alvo text DEFAULT NULL::text, p_canal text DEFAULT ''whatsapp''::text, p_hoje date DEFAULT (public\.)?_hoje_brt\(\), p_agora timestamp with time zone DEFAULT now\(\)$'
            and p.prosecdef and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=public%' and p.provolatile = 'v'
            and has_function_privilege('authenticated', p.oid, 'execute') and has_function_privilege('service_role', p.oid, 'execute')
            and not has_function_privilege('anon', p.oid, 'execute')
           from pg_proc p where p.oid = to_regprocedure('public.agenda_cliente_decidir_dito(uuid, text, text, text, date, timestamptz)')), false),
       null;

-- ── W2. O detector ─────────────────────────────────────────────────────────────────────────────────────────────────────────────

insert into _resultado
with r as (
  select array(select pg_temp.sem_where($t$
         begin
           delete from _tmp_x;
           update public.t set a = (select b from u where u.id = 1);
           update t set a = 1 where b;
           update public.agenda_perguntas set m = case when x then 'a' else 'b; c' end where id = v;
           select 1 from t where id = 1 for update;
           for r in select * from t for update loop null; end loop;
           insert into t values (1) on conflict (id) do update set a = 2;
           with x as (update t set a = 1 where b returning 1) select count(*) from x;
           delete from t where id = any (select 1);
           -- update t set a = 1;
         end $t$)) as achados
)
select 'W2 o detector acusa DELETE/UPDATE sem WHERE (tabela temporária, public., WHERE só no subselect) e não o '';'' de um texto, for update, do update set, nem o "with x as (update … where …)"',
       r.achados = array['delete from _tmp_x', 'update public.t set a = (select b from u where u.id = 1)'],
       array_to_string(r.achados, ' | ')
  from r;

-- ── W3. As funções da agenda ───────────────────────────────────────────────────────────────────────────────────────────────────

insert into _resultado
select 'W3 nenhuma função da agenda (agenda*, _agenda*) com UPDATE/DELETE sem WHERE no nível de cima (o pg_safeupdate do PostgREST recusaria)',
       count(*) = 0, nullif(string_agg(x.f || ': ' || left(x.cmd, 120), ' | ' order by x.f), '')
  from (select p.oid::regprocedure::text as f, s.cmd
          from pg_proc p
          cross join lateral pg_temp.sem_where(p.prosrc) as s(cmd)
         where p.pronamespace = 'public'::regnamespace
           and (p.proname like 'agenda%' or p.proname like '\_agenda%')
           and p.prolang in (select l.oid from pg_language l where l.lanname in ('plpgsql', 'sql'))) x;

select teste, ok, detalhe from _resultado order by teste;

rollback;
