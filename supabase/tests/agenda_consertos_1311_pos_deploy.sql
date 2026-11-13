-- Conferência DEPOIS de publicar os consertos de 13/11 da Agenda de Produção (migration 20261113200000_agenda_consertos_1311.sql). Roteiro:
-- agenda-pesquisa/fila-do-dono/consertos-1311-publicar.md; notas: notas-fase7g.md, "Consertos 13/11". A prova do comportamento é a de
-- supabase/tests/agenda_consertos_1311.sql (na bancada); aqui só se lê o que ficou em produção.
-- bancada: depende de 20261113200000
--
-- SÓ LEITURA EM PRODUÇÃO: nenhum INSERT, UPDATE ou DELETE (só na tabela TEMPORÁRIA do resultado); as funções chamadas são STABLE ou IMMUTABLE
-- (_agenda_cliente_premissa, _agenda_rotulo_os); termina em ROLLBACK. Das mensagens ao cliente, só contagens e o tipo (nenhum texto).
-- A versão confere-se POR NOME (20261113200000 entra depois de versões maiores já no ar, como a F5 do retorno, 20270112*).
--
--   M  a migration registrada por nome
--   F  as 7 funções: a assinatura (1 por nome), definer, volatilidade, search_path=public, as portas (anon e PUBLIC nunca) e o md5 do corpo (sem CR) da migration;
--      e as 4 recriadas, tirado o conserto, = o corpo de produção de 13/11 (o de antes); agenda_fechamento_registrar intacta; nenhum UPDATE/DELETE sem WHERE
--   T  a tabela agenda_fechamento_fila: RLS ligada, anon sem nada, authenticated só lê (policy TO authenticated), service_role escreve, nunca apagada, os CHECKs
--   A  (a) nenhuma mensagem ao cliente em ligado ainda não enviada com a premissa de plano caída (rode logo depois de um tique: :02–:05, :17–:20, :32–:35,
--      :47–:50); o passo fila sem erro desde a publicação; as que caíram (só mostra)
--   B  (b) nenhum fechamento esperando a fila há mais de 1 dia (a conferência do motor roda); nenhum que caiu por erro e nenhum erro de fechamento:conferir em
--      24 h; as linhas por estado (só mostra)
--   D  (c) e (d) pelo resultado puro: o rótulo "foi recusado" e o curto de antes
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs   (A e B, que leem a produção, só mostram lá)
--   Em produção, DEPOIS do passo 1 e no dia seguinte (B, depois do fechamento das 17:30 e de um tique):
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_consertos_1311_pos_deploy.sql
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
set local timezone = 'UTC';

create temp table _pg on commit drop as
select coalesce(current_setting('agenda_teste.feriados', true), '') <> '' as bancada;

-- O corpo sem os blocos "-- CONSERTO 13/11 (x): … -- CONSERTO 13/11 (x): fim".
create function pg_temp.sem_c13(p text) returns text language plpgsql immutable as $f$
declare
  v_fora text[] := '{}';
  v_dentro boolean := false;
  l text;
begin
  foreach l in array string_to_array(replace(p, chr(13), ''), E'\n') loop
    if not v_dentro and l ~ '^\s*-- CONSERTO 13/11 \([a-z]\):' and l !~ '^\s*-- CONSERTO 13/11 \([a-z]\): fim' then v_dentro := true; continue; end if;
    if v_dentro then
      if l ~ '^\s*-- CONSERTO 13/11 \([a-z]\): fim' then v_dentro := false; end if;
      continue;
    end if;
    v_fora := v_fora || l;
  end loop;
  return array_to_string(v_fora, E'\n');
end $f$;
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

-- ── M. A migration, por nome ───────────────────────────────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'M1 migration 20261113200000 registrada', exists (select 1 from supabase_migrations.schema_migrations m where m.version = '20261113200000'), null;

-- ── F. As 7 funções ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
create temp table _f (f text, definer boolean, vol "char", papeis text, m text, antes text) on commit drop;
insert into _f values
  -- (a)
  ('_agenda_cliente_premissa(uuid,timestamp with time zone)', false, 's', '', '6dcad6ce841da1ef8378101c45451cea', null),
  ('_agenda_cliente_fila(date,timestamp with time zone)', false, 'v', '', 'ab582abbaa4e0e2453ba2b2a274eaf8a', '24775239340211340eb435c32bbab9b3'),
  -- (b)
  ('_agenda_fechamento_conferir(timestamp with time zone,uuid)', false, 'v', '', 'dab2eed1b24b3fd37fabf52e2a88df74', null),
  ('agenda_fechamento_guardar(date,jsonb,uuid,text,timestamp with time zone)', true, 'v', 'service_role', 'c12f67c90b394bce4e29458ceabd91e0', null),
  ('agenda_aviso_conferir(timestamp with time zone)', true, 'v', 'service_role', '8665c73034a74e0b89d1e3c6a91b51f0', '9cae4565a4d09039c4e692ea56b51e55'),
  -- (c) e (d): as linhas trocadas voltam no F3
  ('_agenda_porque_da_os(uuid,date,timestamp with time zone)', true, 's', 'authenticated service_role', '8cbcbd131425b64976d96b4e65dd6cb4', 'b25261435b91ff328b9fa85ad58b73e5'),
  ('_agenda_rotulo_os(text,text,boolean,text,boolean)', false, 'i', 'authenticated service_role', '726f8157bd6da7cc652013d341f84365', 'c5bd3e8e361e4b545d82bf8ab784c5cf');

insert into _resultado
select format('F1 %s: 1 assinatura, definer %s, volatilidade %s, search_path=public, portas (%s; anon e PUBLIC nunca)', r.f, r.definer, r.vol, coalesce(nullif(r.papeis, ''), 'ninguém')),
       p.oid is not null
       and (select count(*) from pg_proc x where x.pronamespace = p.pronamespace and x.proname = p.proname) = 1
       and p.prosecdef = r.definer and p.provolatile = r.vol and 'search_path=public' = any (coalesce(p.proconfig, '{}'))
       and not has_function_privilege('anon', p.oid, 'execute')
       and not coalesce((select bool_or(a.grantee = 0) from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.privilege_type = 'EXECUTE'), false)
       and has_function_privilege('authenticated', p.oid, 'execute') = (r.papeis like '%authenticated%')
       and has_function_privilege('service_role', p.oid, 'execute') = (r.papeis like '%service_role%'),
       case when p.oid is null then 'NÃO EXISTE'
            else format('definer %s; %s; %s; anon %s, authenticated %s, service_role %s', p.prosecdef, p.provolatile, p.proconfig,
                        has_function_privilege('anon', p.oid, 'execute'), has_function_privilege('authenticated', p.oid, 'execute'),
                        has_function_privilege('service_role', p.oid, 'execute')) end
  from _f r
  left join pg_proc p on p.oid = to_regprocedure('public.' || r.f);
insert into _resultado
select format('F2 %s: o corpo é o da migration (md5 sem CR %s…)', r.f, left(r.m, 8)), p.oid is not null and md5(replace(p.prosrc, chr(13), '')) = r.m,
       case when p.oid is null then 'NÃO EXISTE' when md5(replace(p.prosrc, chr(13), '')) <> r.m then 'md5 ' || md5(replace(p.prosrc, chr(13), '')) end
  from _f r
  left join pg_proc p on p.oid = to_regprocedure('public.' || r.f);
-- as recriadas, tirado o conserto (os blocos de (a) e (b); a linha marcada de (c) e (d) de volta à de antes): o corpo de produção de 13/11
insert into _resultado
select format('F3 %s: tirado o conserto, é o corpo de produção de 13/11 (md5 %s…)', r.f, left(r.antes, 8)),
       p.oid is not null and md5(case when r.f like '\_agenda\_porque\_da\_os(%'
                                      then replace(replace(p.prosrc, chr(13), ''),
                                             $l$case when v_tipo = 'reserva' and v_quem = 'dono' then 'reservado por você' when v_tipo = 'reserva' then 'reservado pelo gestor' when v_quem = 'dono' then 'marcado por você' else 'marcado pelo gestor' end,  -- CONSERTO 13/11 (c): NOVO-agenda-296, a reserva não é marcação (R9.12-9)$l$,
                                             $l$case when v_quem = 'dono' then 'marcado por você' else 'marcado pelo gestor' end,$l$)
                                      when r.f like '\_agenda\_rotulo\_os(%'
                                      then replace(replace(p.prosrc, chr(13), ''),
                                             $l$then 'foi recusado' else 'recusado' end  -- CONSERTO 13/11 (d): pedido A-2 da F5, vencer não é recusar$l$,
                                             $l$then 'foi recusado (ou venceu)' else 'recusado ou vencido' end$l$)
                                      else pg_temp.sem_c13(p.prosrc) end) = r.antes,
       case when p.oid is null then 'NÃO EXISTE' end
  from _f r
  left join pg_proc p on p.oid = to_regprocedure('public.' || r.f)
 where r.antes is not null;
insert into _resultado
select 'F4 agenda_fechamento_registrar intacta (md5 9a035e2b…, o de produção de 13/11): quem conta continua sendo ela',
       md5(replace(p.prosrc, chr(13), '')) = '9a035e2b8afd1ac0ac48b794ae344daf', md5(replace(p.prosrc, chr(13), ''))
  from pg_proc p where p.oid = to_regprocedure('public.agenda_fechamento_registrar(date, jsonb, text, timestamptz)');
insert into _resultado
select 'F5 nenhum UPDATE/DELETE sem WHERE no nível de cima das 7 (o pg_safeupdate do PostgREST recusaria)',
       count(s) = 0, string_agg(s, ' | ')
  from _f r
  left join pg_proc p on p.oid = to_regprocedure('public.' || r.f)
  left join lateral pg_temp.sem_where(p.prosrc) s on true;

-- ── T. A tabela nova ───────────────────────────────────────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'T1 agenda_fechamento_fila: RLS ligada; anon sem nada; authenticated só SELECT pela policy TO authenticated; service_role escreve; nunca apagada; 3 coerências e os CHECKs de via, estado e motivo',
       c.relrowsecurity
       and not has_table_privilege('anon', c.oid, 'select') and not has_table_privilege('anon', c.oid, 'insert')
       and not has_table_privilege('anon', c.oid, 'update') and not has_table_privilege('anon', c.oid, 'delete')
       and has_table_privilege('authenticated', c.oid, 'select') and not has_table_privilege('authenticated', c.oid, 'insert')
       and not has_table_privilege('authenticated', c.oid, 'update') and not has_table_privilege('authenticated', c.oid, 'delete')
       and has_table_privilege('service_role', c.oid, 'insert') and has_table_privilege('service_role', c.oid, 'update')
       and (select count(*) = 1 and bool_and(p.roles = '{authenticated}' and p.cmd = 'SELECT') from pg_policies p
             where p.schemaname = 'public' and p.tablename = 'agenda_fechamento_fila')
       and exists (select 1 from pg_trigger t where t.tgrelid = c.oid and not t.tgisinternal and t.tgfoid = 'public._agenda_registro_nao_apaga()'::regprocedure)
       and (select count(*) from pg_constraint k where k.conrelid = c.oid and k.contype = 'c') = 7,
       format('rls %s; checks %s; policies %s', c.relrowsecurity, (select count(*) from pg_constraint k where k.conrelid = c.oid and k.contype = 'c'),
              (select string_agg(p.policyname || ':' || p.roles::text || ':' || p.cmd, ', ') from pg_policies p where p.schemaname = 'public' and p.tablename = 'agenda_fechamento_fila'))
  from pg_class c where c.oid = to_regclass('public.agenda_fechamento_fila');

-- ── A. (a) A mensagem que caiu com o plano ─────────────────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'A1 nenhuma mensagem ao cliente em ligado ainda não enviada (registrada ou esperando o dono) com a premissa de plano caída (rode logo depois de um tique; na bancada, só mostra)',
       count(*) filter (where public._agenda_cliente_premissa(m.id, now()) is not null) = 0 or (select bancada from _pg),
       format('%s viva(s) em ligado; com o plano caído: %s', count(*),
              coalesce(string_agg(m.tipo || ':' || public._agenda_cliente_premissa(m.id, now()), ', ')
                         filter (where public._agenda_cliente_premissa(m.id, now()) is not null), 'nenhuma'))
  from public.agenda_cliente_mensagens m
 where m.modo = 'ligado' and m.estado in ('registrada', 'aguardando_dono');
insert into _resultado
select 'A2 o passo fila da rodada do cliente sem erro nas últimas 24 h (app_error_logs agenda / cliente:fila) e nenhum aberto',
       count(*) = 0, string_agg(left(e.message, 120), ' | ')
  from public.app_error_logs e
 where e.context = 'agenda' and e.action = 'cliente:fila' and (e.last_seen_at > now() - interval '24 hours' or e.resolved_at is null);
insert into _resultado
select 'A3 as que caíram com o plano (as rodadas do cliente das últimas 48 h com plano_caiu; só mostra)', true,
       format('%s rodada(s) com plano_caiu, %s mensagem(ns)', count(*) filter (where (r.contagens #>> '{fila,plano_caiu}') is not null),
              coalesce(sum((r.contagens #>> '{fila,plano_caiu}')::int), 0))
  from public.agenda_vigia_rodadas r
 where r.rotina = 'cliente' and r.rodou_em > now() - interval '48 hours';

-- ── B. (b) O fechamento que espera a fila ─────────────────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'B1 nenhum fechamento esperando a fila há mais de 1 dia (a conferência do motor, agenda_aviso_conferir, roda)',
       count(*) filter (where f.estado = 'esperando' and f.criada_em < now() - interval '1 day 1 hour') = 0,
       format('por estado: %s', coalesce((select string_agg(x.estado || '=' || x.n, ', ' order by x.estado)
                                           from (select y.estado, count(*) as n from public.agenda_fechamento_fila y group by y.estado) x), 'nenhuma linha'))
  from public.agenda_fechamento_fila f;
insert into _resultado
select 'B2 nenhum fechamento caiu por erro nas últimas 24 h e nenhum erro de fechamento:conferir em 24 h (nem aberto)',
       (select count(*) from public.agenda_fechamento_fila f where f.motivo = 'erro' and f.resolvida_em > now() - interval '24 hours') = 0
       and (select count(*) from public.app_error_logs e where e.context = 'agenda' and e.action = 'fechamento:conferir'
              and (e.last_seen_at > now() - interval '24 hours' or e.resolved_at is null)) = 0,
       (select string_agg(left(e.message, 120), ' | ') from public.app_error_logs e where e.context = 'agenda' and e.action = 'fechamento:conferir'
          and (e.last_seen_at > now() - interval '24 hours' or e.resolved_at is null));
insert into _resultado
select 'B3 o último fechamento guardado: o estado, quando saiu e quantas perguntas e ações contou (só mostra)', true,
       coalesce((select format('dia %s: %s%s; perguntas %s, ações %s', f.dia, f.estado, coalesce(' (' || f.motivo || ')', ''),
                               coalesce(f.resultado ->> 'perguntas', '-'), coalesce(f.resultado ->> 'acoes', '-'))
                   from public.agenda_fechamento_fila f order by f.criada_em desc limit 1), 'nenhum ainda');

-- ── D. (c) e (d) pelo resultado ────────────────────────────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'D1 o orçamento recusado: a frase "foi recusado"; o rótulo curto "recusado"',
       public._agenda_rotulo_os('draft', 'rejected', false, null, true) = 'foi recusado'
       and public._agenda_rotulo_os('draft', 'rejected', false, null, false) = 'recusado',
       public._agenda_rotulo_os('draft', 'rejected', false, null, true);

select teste, ok, detalhe from _resultado order by teste;

rollback;
