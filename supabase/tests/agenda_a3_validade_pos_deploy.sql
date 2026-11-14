-- Conferência DEPOIS de publicar o conserto da validade do A-3 (migration 20261113400000_agenda_a3_validade.sql). Roteiro:
-- agenda-pesquisa/fila-do-dono/agenda-a3-validade-publicar.md. A prova do comportamento é a de supabase/tests/agenda_a3_validade.sql (na bancada);
-- aqui só se lê o que ficou em produção.
-- bancada: depende de 20261113400000
--
-- SÓ LEITURA EM PRODUÇÃO: nenhum INSERT, UPDATE ou DELETE (só na tabela TEMPORÁRIA do resultado); termina em ROLLBACK. Das mensagens ao cliente, só
-- contagens e o tipo (nenhum texto). A versão confere-se POR NOME.
--
--   M  a migration registrada por nome
--   F  as 2 recriadas: 1 assinatura, definer, volatilidade, search_path=public, as portas de antes, o md5 do corpo (sem CR) da migration; tirados os
--      blocos da validade, o corpo de produção de 14/11; tirados também os do A-1/A-3, o enfileirar de 20261028100800; o gatilho segue na guarda; sem WHERE
--   Z  os zeros: nenhuma confirmação, véspera ou acesso da rodada enviada no dia do serviço ou depois (30 dias); nenhuma mensagem viva com a hora depois
--      da validade; o passo fila sem erro em 24 h. E só mostra: as confirmações e vésperas de 7 dias (enviadas, recusadas pelo teto do dia, vivas com a
--      validade em outro dia que o de nascer)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, DEPOIS do passo 1 e no dia seguinte:  npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_a3_validade_pos_deploy.sql
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
set local timezone = 'UTC';

-- O corpo sem os blocos de um marcador ("-- <p_marca> (F5): … -- <p_marca> (F5): fim"; p_marca é uma expressão regular).
create function pg_temp.sem_blocos(p text, p_marca text) returns text language plpgsql immutable as $f$
declare
  v_fora text[] := '{}';
  v_dentro boolean := false;
  l text;
begin
  foreach l in array string_to_array(replace(p, chr(13), ''), E'\n') loop
    if not v_dentro and l ~ ('^\s*-- ' || p_marca || ' \(F5\):') and l !~ '\(F5\): fim\s*$' then v_dentro := true; continue; end if;
    if v_dentro then
      if l ~ ('^\s*-- ' || p_marca || ' \(F5\): fim\s*$') then v_dentro := false; end if;
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
select 'M1 migration 20261113400000 registrada', exists (select 1 from supabase_migrations.schema_migrations m where m.version = '20261113400000'), null;

-- ── F. As 2 recriadas ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────
create temp table _f (f text, definer boolean, vol "char", service_role boolean, m text, antes text) on commit drop;
insert into _f values
  ('_agenda_cliente_mensagens_so_muda()', false, 'v', true, 'dea449bb712db77d9f1a9f73b9b96e98', '89bdf01e9f6f759236c9c5dc92578f30'),
  ('_agenda_cliente_enfileirar(uuid,timestamp with time zone)', true, 'v', false, '9dffd2b5102afab6d9abbf89d19a3882', '38775240c466381c78714aea11fa8d71');

insert into _resultado
select format('F1 %s: 1 assinatura, definer %s, volatilidade %s, search_path=public; as portas de antes (service_role %s; anon, authenticated e PUBLIC nunca)',
              r.f, r.definer, r.vol, r.service_role),
       p.oid is not null
       and (select count(*) from pg_proc x where x.pronamespace = p.pronamespace and x.proname = p.proname) = 1
       and p.prosecdef = r.definer and p.provolatile = r.vol and 'search_path=public' = any (coalesce(p.proconfig, '{}'))
       and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
       and has_function_privilege('service_role', p.oid, 'execute') = r.service_role
       and not coalesce((select bool_or(a.grantee = 0) from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.privilege_type = 'EXECUTE'), false),
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
insert into _resultado
select format('F3 %s: tirados os blocos "-- PEDIDO A-3, VALIDADE (F5):", é o corpo de produção de 14/11 (md5 %s…)', r.f, left(r.antes, 8)),
       p.oid is not null and md5(pg_temp.sem_blocos(p.prosrc, 'PEDIDO A-3, VALIDADE')) = r.antes,
       case when p.oid is null then 'NÃO EXISTE' else md5(pg_temp.sem_blocos(p.prosrc, 'PEDIDO A-3, VALIDADE')) end
  from _f r
  left join pg_proc p on p.oid = to_regprocedure('public.' || r.f);
insert into _resultado
select 'F4 o enfileirar, tirados também os blocos do A-1/A-3, é o de 20261028100800 (md5 39c92c14…); o gatilho BEFORE UPDATE agenda_cliente_mensagens_so_muda segue na guarda',
       md5(pg_temp.sem_blocos((select p.prosrc from pg_proc p where p.oid = 'public._agenda_cliente_enfileirar(uuid, timestamptz)'::regprocedure),
                              'PEDIDO A-[0-9]( e A-[0-9])?')) = '39c92c146c43d1a24dcdb42afaea14b7'
       and exists (select 1 from pg_trigger t where t.tgrelid = 'public.agenda_cliente_mensagens'::regclass and not t.tgisinternal
                     and t.tgname = 'agenda_cliente_mensagens_so_muda' and t.tgfoid = 'public._agenda_cliente_mensagens_so_muda()'::regprocedure
                     and pg_get_triggerdef(t.oid) like '%BEFORE UPDATE%'),
       null;
insert into _resultado
select 'F5 nenhum UPDATE/DELETE sem WHERE no nível de cima das 2 (o pg_safeupdate do PostgREST recusaria)', count(s) = 0, string_agg(s, ' | ')
  from _f r
  left join pg_proc p on p.oid = to_regprocedure('public.' || r.f)
  left join lateral pg_temp.sem_where(p.prosrc) s on true;

-- ── Z. Os zeros, e o que só se mostra ──────────────────────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'Z1 nenhuma confirmação, véspera ou acesso da rodada enviada (30 dias) no dia do serviço de que fala ou depois',
       count(*) = 0, coalesce(string_agg(m.tipo || ':' || m.estado, ', '), 'nenhuma')
  from public.agenda_cliente_mensagens m
 where m.modo = 'ligado' and m.origem = 'rodada' and m.tipo in ('confirmar', 'vespera', 'acesso') and m.enviada_em > now() - interval '30 days'
   and (m.enviada_em at time zone 'America/Sao_Paulo')::date >= coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo);
insert into _resultado
select 'Z2 nenhuma mensagem ao cliente viva (registrada ou esperando o dono) com a hora de sair depois da validade',
       count(*) = 0, coalesce(string_agg(m.tipo || ':' || m.estado, ', '), 'nenhuma')
  from public.agenda_cliente_mensagens m
 where m.estado in ('registrada', 'aguardando_dono') and m.enviar_em > m.valida_ate;
insert into _resultado
select 'Z3 o passo fila da rodada do cliente sem erro nas últimas 24 h (app_error_logs agenda / cliente:fila) e nenhum aberto',
       count(*) = 0, string_agg(left(e.message, 120), ' | ')
  from public.app_error_logs e
 where e.context = 'agenda' and e.action = 'cliente:fila' and (e.last_seen_at > now() - interval '24 hours' or e.resolved_at is null);
insert into _resultado
select 'Z4 as confirmações e vésperas de 7 dias em ligado: enviadas, recusadas pelo teto do dia e vivas com a validade num dia depois do de nascer (só mostra)', true,
       format('enviadas %s; teto_dia %s; vivas com a validade empurrada %s', count(*) filter (where m.enviada_em is not null),
              count(*) filter (where m.recusa_motivo = 'teto_dia'),
              count(*) filter (where m.estado in ('registrada', 'aguardando_dono')
                                 and (m.valida_ate at time zone 'America/Sao_Paulo')::date > (m.criada_em at time zone 'America/Sao_Paulo')::date))
  from public.agenda_cliente_mensagens m
 where m.modo = 'ligado' and m.tipo in ('confirmar', 'vespera') and m.criada_em > now() - interval '7 days';

select teste, ok, detalhe from _resultado order by teste;

rollback;
