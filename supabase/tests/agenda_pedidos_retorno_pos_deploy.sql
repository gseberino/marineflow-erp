-- Conferência DEPOIS de publicar os pedidos A-1, A-3 e A-5 da F5 à Agenda de Produção (migration 20261113300000_agenda_pedidos_retorno.sql). Roteiro:
-- agenda-pesquisa/fila-do-dono/agenda-a1a3-publicar.md. A prova do comportamento é a de supabase/tests/agenda_pedidos_retorno.sql (na bancada); aqui só se
-- lê o que ficou em produção.
-- bancada: depende de 20261113300000
--
-- SÓ LEITURA EM PRODUÇÃO: nenhum INSERT, UPDATE ou DELETE (só na tabela TEMPORÁRIA do resultado); as funções chamadas são STABLE
-- (_agenda_cliente_orcamento_espera, _agenda_cliente_retorno_no_periodo, _agenda_cliente_no_periodo); termina em ROLLBACK. Das mensagens ao cliente e das
-- saídas do retorno, só contagens e o tipo (nenhum texto). A versão confere-se POR NOME (20261113300000 entra depois de versões maiores já no ar).
--
--   M  a migration registrada por nome
--   F  as 5 funções: 1 assinatura, definer, volatilidade, search_path=public, as portas (ninguém além do dono) e o md5 do corpo (sem CR) da migration; as 3
--      recriadas, tirados os blocos do pedido, = o corpo de produção de 13/11 (o de antes); os 2 gatilhos da fila seguem na trava; o botão
--      (_pedir_confirmacao) intacto, contando o teto_total pela mesma conta; nenhum UPDATE/DELETE sem WHERE
--   Z  os zeros: nenhuma mensagem da agenda enviada (30 dias) num dia em que a saída do orçamento ao mesmo cliente já tinha ido antes dela (A-1) nem a
--      confirmação antes do dia útil seguinte ao "Fechado" (A-3); nenhuma mensagem ao cliente viva com a hora vencida há mais de 2 tiques; o passo fila
--      sem erro em 24 h. E só mostra: as remarcadas e recusadas pelo teto em 7 dias, e o maior dia (agenda + iniciadas do retorno) em 30 dias
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs   (sem as tabelas do retorno, Z conta zero)
--   Em produção, DEPOIS do passo 1 e no dia seguinte:  npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_pedidos_retorno_pos_deploy.sql
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
set local timezone = 'UTC';

create temp table _pg on commit drop as
select coalesce(current_setting('agenda_teste.feriados', true), '') <> '' as bancada;

-- O corpo sem os blocos "-- PEDIDO A-3, VALIDADE (F5): … fim" (o conserto da validade, 20261113400000, acrescenta 2 ao enfileirar: o F2 confere o
-- corpo desta migration por baixo dele).
create function pg_temp.sem_validade(p text) returns text language plpgsql immutable as $f$
declare
  v_fora text[] := '{}';
  v_dentro boolean := false;
  l text;
begin
  foreach l in array string_to_array(replace(p, chr(13), ''), E'\n') loop
    if not v_dentro and l ~ '^\s*-- PEDIDO A-3, VALIDADE \(F5\):' and l !~ '\(F5\): fim\s*$' then v_dentro := true; continue; end if;
    if v_dentro then
      if l ~ '^\s*-- PEDIDO A-3, VALIDADE \(F5\): fim\s*$' then v_dentro := false; end if;
      continue;
    end if;
    v_fora := v_fora || l;
  end loop;
  return array_to_string(v_fora, E'\n');
end $f$;
-- O corpo sem os blocos "-- PEDIDO A-x (F5): … -- PEDIDO A-x (F5): fim".
create function pg_temp.sem_pedido(p text) returns text language plpgsql immutable as $f$
declare
  v_fora text[] := '{}';
  v_dentro boolean := false;
  l text;
begin
  foreach l in array string_to_array(replace(p, chr(13), ''), E'\n') loop
    if not v_dentro and l ~ '^\s*-- PEDIDO A-[0-9]( e A-[0-9])? \(F5\):' and l !~ '\(F5\): fim\s*$' then v_dentro := true; continue; end if;
    if v_dentro then
      if l ~ '^\s*-- PEDIDO A-[0-9]( e A-[0-9])? \(F5\): fim\s*$' then v_dentro := false; end if;
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
select 'M1 migration 20261113300000 registrada', exists (select 1 from supabase_migrations.schema_migrations m where m.version = '20261113300000'), null;

-- ── F. As 5 funções ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
create temp table _f (f text, definer boolean, vol "char", m text, antes text) on commit drop;
insert into _f values
  ('_agenda_cliente_orcamento_espera(uuid,text,date,timestamp with time zone)', false, 's', '22b4e32ae0afc318f07b48e1d9ef250b', null),
  ('_agenda_cliente_retorno_no_periodo(date,date)', false, 's', 'e5b4ea16438d364f0f3a58dacd63bfd4', null),
  ('_agenda_cliente_enfileirar(uuid,timestamp with time zone)', true, 'v', '38775240c466381c78714aea11fa8d71', '39c92c146c43d1a24dcdb42afaea14b7'),
  ('_agenda_fila_do_cliente()', true, 'v', '481c533952c68d94d1ce7997a2373023', '6e462b7407bf84237607f2ab7b11df1b'),
  ('_agenda_cliente_no_periodo(uuid,date,date,uuid)', false, 's', '2a50b6a633d2db82260867d86e9d958c', 'd99e071a323385c9b46f468b7a93eaff');

insert into _resultado
select format('F1 %s: 1 assinatura, definer %s, volatilidade %s, search_path=public; só o dono executa (anon, authenticated, service_role e PUBLIC nunca)', r.f, r.definer, r.vol),
       p.oid is not null
       and (select count(*) from pg_proc x where x.pronamespace = p.pronamespace and x.proname = p.proname) = 1
       and p.prosecdef = r.definer and p.provolatile = r.vol and 'search_path=public' = any (coalesce(p.proconfig, '{}'))
       and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
       and not has_function_privilege('service_role', p.oid, 'execute')
       and not coalesce((select bool_or(a.grantee = 0) from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.privilege_type = 'EXECUTE'), false),
       case when p.oid is null then 'NÃO EXISTE'
            else format('definer %s; %s; %s; anon %s, authenticated %s, service_role %s', p.prosecdef, p.provolatile, p.proconfig,
                        has_function_privilege('anon', p.oid, 'execute'), has_function_privilege('authenticated', p.oid, 'execute'),
                        has_function_privilege('service_role', p.oid, 'execute')) end
  from _f r
  left join pg_proc p on p.oid = to_regprocedure('public.' || r.f);
insert into _resultado
select format('F2 %s: o corpo é o da migration (md5 sem CR %s…; com o conserto da validade por cima, tirados os blocos dele)', r.f, left(r.m, 8)),
       p.oid is not null and md5(pg_temp.sem_validade(p.prosrc)) = r.m,
       case when p.oid is null then 'NÃO EXISTE' when md5(pg_temp.sem_validade(p.prosrc)) <> r.m then 'md5 ' || md5(pg_temp.sem_validade(p.prosrc)) end
  from _f r
  left join pg_proc p on p.oid = to_regprocedure('public.' || r.f);
insert into _resultado
select format('F3 %s: tirados os blocos do pedido, é o corpo de produção de 13/11 (md5 %s…)', r.f, left(r.antes, 8)),
       p.oid is not null and md5(pg_temp.sem_pedido(p.prosrc)) = r.antes,
       case when p.oid is null then 'NÃO EXISTE' else md5(pg_temp.sem_pedido(p.prosrc)) end
  from _f r
  left join pg_proc p on p.oid = to_regprocedure('public.' || r.f)
 where r.antes is not null;
insert into _resultado
select 'F4 os 2 gatilhos da fila (trg_agenda_fila_do_cliente no INSERT e trg_agenda_fila_do_cliente_linha no UPDATE) seguem na trava, só para agenda-cliente',
       count(*) = 2, string_agg(t.tgname, ', ')
  from pg_trigger t
 where t.tgrelid = 'public.whatsapp_send_queue'::regclass and not t.tgisinternal and t.tgfoid = 'public._agenda_fila_do_cliente()'::regprocedure
   and t.tgname in ('trg_agenda_fila_do_cliente', 'trg_agenda_fila_do_cliente_linha') and pg_get_triggerdef(t.oid) like '%agenda-cliente%';
insert into _resultado
select 'F5 o botão (_pedir_confirmacao) intacto (md5 7539d570…, o de produção de 13/11): conta o teto_total por _agenda_cliente_no_periodo, que agora soma o retorno',
       md5(replace(p.prosrc, chr(13), '')) = '7539d570396da13ca37baf93621dc11c'
       and p.prosrc like '%_agenda_cliente_no_periodo(null, v_dia_e, v_dia_e, v_ja.id) >= v_cf.cliente_total_dia_max%',
       md5(replace(p.prosrc, chr(13), ''))
  from pg_proc p where p.oid = to_regprocedure('public._pedir_confirmacao(uuid, uuid, timestamptz)');
insert into _resultado
select 'F6 nenhum UPDATE/DELETE sem WHERE no nível de cima das 5 (o pg_safeupdate do PostgREST recusaria)',
       count(s) = 0, string_agg(s, ' | ')
  from _f r
  left join pg_proc p on p.oid = to_regprocedure('public.' || r.f)
  left join lateral pg_temp.sem_where(p.prosrc) s on true;

-- ── Z. Os zeros, e o que só se mostra ──────────────────────────────────────────────────────────────────────────────────────────────────
-- Z1: a mensagem da agenda que saiu (30 dias) num dia em que, ANTES dela, a saída do orçamento já tinha ido ao mesmo cliente (A-1), ou a confirmação
-- antes do dia útil seguinte ao "Fechado" (A-3). A conta é a da própria regra (_agenda_cliente_orcamento_espera, na hora do envio). Sem retorno_saidas
-- (a bancada), a regra devolve null: 0.
insert into _resultado
select 'Z1 nenhuma mensagem da agenda enviada (30 dias) no dia em que a saída do orçamento ao mesmo cliente já tinha ido antes dela, nem a confirmação antes do dia útil seguinte ao "Fechado"',
       count(*) filter (where public._agenda_cliente_orcamento_espera(m.client_id, m.tipo, (m.enviada_em at time zone 'America/Sao_Paulo')::date,
                                                                       m.enviada_em - interval '1 second') is not null) = 0,
       format('%s enviada(s) em 30 dias; com o orçamento antes no dia: %s', count(*),
              count(*) filter (where public._agenda_cliente_orcamento_espera(m.client_id, m.tipo, (m.enviada_em at time zone 'America/Sao_Paulo')::date,
                                                                              m.enviada_em - interval '1 second') is not null))
  from public.agenda_cliente_mensagens m
 where m.modo = 'ligado' and m.enviada_em > now() - interval '30 days';
insert into _resultado
select 'Z2 com a mensagem ao cliente ligada, nenhuma viva (registrada ou esperando o dono, livre ou aprovada) com a hora de sair vencida há mais de 30 minutos: o passo fila a manda, recusa ou remarca a cada tique (na bancada, só mostra)',
       count(*) = 0 or (select bancada from _pg), coalesce(string_agg(m.tipo || ':' || m.estado, ', '), 'nenhuma')
  from public.agenda_cliente_mensagens m
  join public.agenda_config c on c.modo_cliente = 'ligado' and m.tipo = any (c.cliente_tipos_ligados)
 where m.modo = 'ligado' and m.estado in ('registrada', 'aguardando_dono') and m.aprovacao in ('livre', 'aprovada')
   and m.enviar_em < now() - interval '30 minutes' and m.valida_ate > now();
insert into _resultado
select 'Z3 o passo fila da rodada do cliente sem erro nas últimas 24 h (app_error_logs agenda / cliente:fila) e nenhum aberto',
       count(*) = 0, string_agg(left(e.message, 120), ' | ')
  from public.app_error_logs e
 where e.context = 'agenda' and e.action = 'cliente:fila' and (e.last_seen_at > now() - interval '24 hours' or e.resolved_at is null);
insert into _resultado
select 'Z4 as mensagens ao cliente de 7 dias recusadas pelo teto (dia e total) e as vivas com a hora no dia seguinte ao de nascer (só mostra)', true,
       format('teto_dia %s, teto_total %s; vivas com a hora em outro dia que o de nascer %s',
              count(*) filter (where m.recusa_motivo = 'teto_dia'), count(*) filter (where m.recusa_motivo = 'teto_total'),
              count(*) filter (where m.estado in ('registrada', 'aguardando_dono')
                                 and (m.enviar_em at time zone 'America/Sao_Paulo')::date > (m.criada_em at time zone 'America/Sao_Paulo')::date))
  from public.agenda_cliente_mensagens m
 where m.modo = 'ligado' and m.criada_em > now() - interval '7 days';
insert into _resultado
select 'Z5 o maior dia de 30 dias no teto do dia a todos: as da agenda + as iniciadas do retorno (só mostra; o teto é cliente_total_dia_max)', true,
       coalesce((select format('%s: %s (agenda %s + retorno %s); teto %s', d, public._agenda_cliente_no_periodo(null, d, d, null),
                               public._agenda_cliente_no_periodo(null, d, d, null) - public._agenda_cliente_retorno_no_periodo(d, d),
                               public._agenda_cliente_retorno_no_periodo(d, d), (select c.cliente_total_dia_max from public.agenda_config c limit 1))
                   from generate_series((now() at time zone 'America/Sao_Paulo')::date - 30, (now() at time zone 'America/Sao_Paulo')::date, interval '1 day') g(x),
                        lateral (select g.x::date as d) dd
                  order by public._agenda_cliente_no_periodo(null, d, d, null) desc, d desc limit 1), 'nenhum');

select teste, ok, detalhe from _resultado order by teste;

rollback;
