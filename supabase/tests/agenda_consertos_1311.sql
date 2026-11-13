-- Prova dos consertos de 13/11/2026 da Agenda de Produção (migration 20261113200000_agenda_consertos_1311.sql): (a) a mensagem ao cliente que ainda não saiu cai
-- quando o plano que a originou cai; (b) o fechamento só conta como mostrado o que a fila MANDOU; (c) NOVO-agenda-296, a reserva não é "marcado"; (d) o pedido
-- A-2 da F5, "foi recusado".
-- bancada: depende de 20261113200000
--
--   P0  a forma e as portas (vale em produção): as 3 novas (a premissa e a conferência invoker e sem grant; a guarda definer, só service_role); a tabela nova
--       (RLS ligada, anon sem nada, authenticated só lê pela policy TO authenticated, nunca apagada); as 4 recriadas = a origem de produção + só o conserto
--       (md5 de produção de 13/11, sem CR) e com as portas de antes; agenda_fechamento_registrar intacta; nenhum UPDATE/DELETE sem WHERE nas 7 (pg_safeupdate)
--   A1  (fixture-fase5) a cena do Nelson com o Flávio: a véspera pedida pela rodada esperando o dono; a vigia desmarca (as alocações canceladas, a OS volta a
--       esperar peça): no tique seguinte a mensagem cai (recusada, status), a pergunta sai da fila do dono (descartada, "o plano caiu: …"), *agenda pendências*
--       não a mostra, o *manda* não promete, nada vai à fila e nenhum "não saiu" nasce (o dono não tinha aprovado); a revalidação da hora de sair também recusa
--   A2  o plano não cai: o mesmo tique deixa a mensagem esperando e a pergunta aberta; sem nada caindo, o passo fila devolve as chaves de antes (sem plano_caiu)
--   A3  o plano muda de dia (as alocações de ter 03/11 canceladas, a OS segue agendada): a véspera cai com data_mudou
--   A4  a aprovada que espera a hora (*manda cliente Flávio* antes de seg 02/11 09:00) e a OS cancelada: cai (status) e o dono fica sabendo que não saiu (o
--       "não saiu" de quem aprovou, como na hora de sair)
--   A5  os outros tipos: a confirmação (livre, registrada para sáb 31/10) com o dia mudado cai (data_mudou); o "ficou pronto" da Lucenira com a OS cancelada cai
--       (status)
--   A6  em teste (sombra), nada cai
--   A7  sem conversa recente (a revalidação diz sem_conversa) e com o plano de pé, nada cai; e a conversa que falta não esconde o plano: desmarcada a OS,
--       a mensagem cai pelo plano (status)
--   A8  sem o conserto (o passo fila de antes, numa subtransação), a mesma cena do A1 deixa a mensagem esperando e a pergunta aberta (o teste morde)
--   B1  (fixture-fase7f) a guarda com a fila pendente (o WhatsApp fora): nada conta (a pergunta não fica mostrada, o prazo não nasce, a ação não fica contada);
--       o aviso do motor confere e espera; o caminho de antes (agenda_fechamento_registrar na hora) contava (o controle)
--   B2  a fila manda: o tique seguinte conta na hora em que saiu (sent_at), igual ao registro de antes nessa hora; o tique depois não conta de novo
--   B3  a fila desiste (failed), a linha dela some ou não sai em 1 dia: cai e nada conta (a pergunta volta no próximo fechamento)
--   B4  a fila já tinha mandado quando a guarda chegou: conta na hora; a mesma linha da fila 2x não conta de novo; sem a linha da fila: nada guardado; o resto
--       das recusas (via, sem o dia, a fila ou a hora)
--   B5  uma linha que não fecha cai com erro, uma vez, vai a app_error_logs e não derruba o aviso nem os outros fechamentos
--   C1  (cenario_motor) o porquê: a reserva sua "reservado por você", a do gestor "reservado pelo gestor"; a marcada sua e a do gestor como antes; sem o
--       conserto, a reserva dizia "marcado …" (morde)
--   D1  o rótulo: o orçamento recusado, na frase, "foi recusado"; o rótulo curto, "recusado"; sem o conserto, "foi recusado (ou venceu)" e "recusado ou vencido" (morde)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration:  npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_consertos_1311.sql
--   Sem as fixtures (produção) A, B e C saem PULADO; P0 e D rodam e não gravam nada. Termina em ROLLBACK: nada fica gravado e nenhuma mensagem sai.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

set local timezone = 'UTC';

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;
create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;
-- A hora de Brasília escrita como se fala: pg_temp.em('2026-10-30 10:00') = timestamptz '2026-10-30 10:00-03'.
create function pg_temp.em(p_quando text) returns timestamptz language sql immutable as $f$
  select (p_quando::timestamp) at time zone 'America/Sao_Paulo'
$f$;
-- O corpo (prosrc, sem CR) de uma função pela assinatura.
create function pg_temp.src(p_assinatura text) returns text language sql stable as $f$
  select replace(p.prosrc, chr(13), '') from pg_proc p where p.oid = to_regprocedure(p_assinatura)
$f$;
-- Tira os blocos "-- CONSERTO 13/11 (x): … -- CONSERTO 13/11 (x): fim" (o que a 20261113200000 acrescentou).
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
-- A porta de uma função: "definer volatilidade | anon authenticated service_role public" (EXECUTE; t ou f).
create function pg_temp.porta(p_assinatura text) returns text language sql stable as $f$
  select format('%s %s | %s %s %s %s', p.prosecdef, p.provolatile, has_function_privilege('anon', p.oid, 'execute'),
                has_function_privilege('authenticated', p.oid, 'execute'), has_function_privilege('service_role', p.oid, 'execute'),
                coalesce((select bool_or(a.grantee = 0) from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.privilege_type = 'EXECUTE'), false))
    from pg_proc p where p.oid = to_regprocedure(p_assinatura)
$f$;
-- Tira os parênteses equilibrados (de dentro para fora) e corta no 1º que sobrar: o nível de cima do comando (o detector da 20261112300000).
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

-- ── P0. A forma e as portas ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
do $p0$
declare
  v_res jsonb := '[]'::jsonb;
  c_prem  constant text := 'public._agenda_cliente_premissa(uuid, timestamptz)';
  c_conf  constant text := 'public._agenda_fechamento_conferir(timestamptz, uuid)';
  c_guar  constant text := 'public.agenda_fechamento_guardar(date, jsonb, uuid, text, timestamptz)';
  c_fila  constant text := 'public._agenda_cliente_fila(date, timestamptz)';
  c_aviso constant text := 'public.agenda_aviso_conferir(timestamptz)';
  c_pq    constant text := 'public._agenda_porque_da_os(uuid, date, timestamptz)';
  c_rot   constant text := 'public._agenda_rotulo_os(text, text, boolean, text, boolean)';
  -- as 2 linhas trocadas em (c) e (d), como estão na migration (a de antes volta no lugar para conferir a origem)
  c_pq_novo  constant text := $l$                            'quem', v_quem, 'quem_texto', case when v_tipo = 'reserva' and v_quem = 'dono' then 'reservado por você' when v_tipo = 'reserva' then 'reservado pelo gestor' when v_quem = 'dono' then 'marcado por você' else 'marcado pelo gestor' end,  -- CONSERTO 13/11 (c): NOVO-agenda-296, a reserva não é marcação (R9.12-9)$l$;
  c_pq_antes constant text := $l$                            'quem', v_quem, 'quem_texto', case when v_quem = 'dono' then 'marcado por você' else 'marcado pelo gestor' end,$l$;
  c_rot_novo  constant text := $l$      when p_quote_status = 'rejected' then case when p_frase then 'foi recusado' else 'recusado' end  -- CONSERTO 13/11 (d): pedido A-2 da F5, vencer não é recusar$l$;
  c_rot_antes constant text := $l$      when p_quote_status = 'rejected' then case when p_frase then 'foi recusado (ou venceu)' else 'recusado ou vencido' end$l$;
  v text;
  v_n int;
begin
  v_res := pg_temp.ok(v_res, 'P0a _agenda_cliente_premissa: 1 assinatura, invoker, STABLE, search_path=public; ninguém executa (nem anon, authenticated, service_role ou PUBLIC)',
    (select count(*) from pg_proc x where x.pronamespace = 'public'::regnamespace and x.proname = '_agenda_cliente_premissa') = 1
    and pg_temp.porta(c_prem) = 'f s | f f f f'
    and (select coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=public%' from pg_proc p where p.oid = to_regprocedure(c_prem)),
    pg_temp.porta(c_prem));
  v_res := pg_temp.ok(v_res, 'P0b _agenda_fechamento_conferir: 1 assinatura, invoker, volátil, search_path=public; ninguém executa',
    (select count(*) from pg_proc x where x.pronamespace = 'public'::regnamespace and x.proname = '_agenda_fechamento_conferir') = 1
    and pg_temp.porta(c_conf) = 'f v | f f f f'
    and (select coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=public%' from pg_proc p where p.oid = to_regprocedure(c_conf)),
    pg_temp.porta(c_conf));
  v_res := pg_temp.ok(v_res, 'P0c agenda_fechamento_guardar: 1 assinatura, definer, volátil, search_path=public; só o service_role executa',
    (select count(*) from pg_proc x where x.pronamespace = 'public'::regnamespace and x.proname = 'agenda_fechamento_guardar') = 1
    and pg_temp.porta(c_guar) = 't v | f f t f'
    and (select coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=public%' from pg_proc p where p.oid = to_regprocedure(c_guar)),
    pg_temp.porta(c_guar));
  v_res := pg_temp.ok(v_res, 'P0d agenda_fechamento_fila: RLS ligada; anon sem nada; authenticated só SELECT, pela policy TO authenticated (admin/financeiro); service_role tudo; nunca apagada',
    (select c.relrowsecurity from pg_class c where c.oid = 'public.agenda_fechamento_fila'::regclass)
    and not has_table_privilege('anon', 'public.agenda_fechamento_fila', 'select') and not has_table_privilege('anon', 'public.agenda_fechamento_fila', 'insert')
    and not has_table_privilege('anon', 'public.agenda_fechamento_fila', 'update') and not has_table_privilege('anon', 'public.agenda_fechamento_fila', 'delete')
    and has_table_privilege('authenticated', 'public.agenda_fechamento_fila', 'select') and not has_table_privilege('authenticated', 'public.agenda_fechamento_fila', 'insert')
    and not has_table_privilege('authenticated', 'public.agenda_fechamento_fila', 'update') and not has_table_privilege('authenticated', 'public.agenda_fechamento_fila', 'delete')
    and has_table_privilege('service_role', 'public.agenda_fechamento_fila', 'insert')
    and (select count(*) from pg_policies p where p.schemaname = 'public' and p.tablename = 'agenda_fechamento_fila') = 1
    and (select p.roles = '{authenticated}' and p.cmd = 'SELECT' and p.qual like '%is_admin_or_financial%' from pg_policies p
          where p.schemaname = 'public' and p.tablename = 'agenda_fechamento_fila')
    and exists (select 1 from pg_trigger t where t.tgrelid = 'public.agenda_fechamento_fila'::regclass and not t.tgisinternal
                  and t.tgfoid = 'public._agenda_registro_nao_apaga()'::regprocedure),
    (select string_agg(p.policyname || ':' || p.roles::text || ':' || p.cmd, ', ') from pg_policies p where p.schemaname = 'public' and p.tablename = 'agenda_fechamento_fila'));
  -- as 4 recriadas: a origem de produção de 13/11 + só o conserto
  v_res := pg_temp.ok(v_res, 'P0e _agenda_cliente_fila: tirados os 3 blocos "-- CONSERTO 13/11 (a):", é o corpo de produção de 13/11 (20261028100800, md5 24775239…); porta de antes (ninguém)',
    md5(pg_temp.sem_c13(pg_temp.src(c_fila))) = '24775239340211340eb435c32bbab9b3' and md5(pg_temp.src(c_fila)) <> '24775239340211340eb435c32bbab9b3'
    and (select count(*) from regexp_matches(pg_temp.src(c_fila), '-- CONSERTO 13/11 \(a\): fim', 'g')) = 3
    and pg_temp.porta(c_fila) = 'f v | f f f f',
    md5(pg_temp.sem_c13(pg_temp.src(c_fila))) || ' ' || pg_temp.porta(c_fila));
  v_res := pg_temp.ok(v_res, 'P0f agenda_aviso_conferir: tirados os 2 blocos "-- CONSERTO 13/11 (b):", é o corpo de produção de 13/11 (20261030100300, md5 9cae4565…); definer, só service_role',
    md5(pg_temp.sem_c13(pg_temp.src(c_aviso))) = '9cae4565a4d09039c4e692ea56b51e55' and md5(pg_temp.src(c_aviso)) <> '9cae4565a4d09039c4e692ea56b51e55'
    and (select count(*) from regexp_matches(pg_temp.src(c_aviso), '-- CONSERTO 13/11 \(b\): fim', 'g')) = 2
    and pg_temp.porta(c_aviso) = 't v | f f t f',
    md5(pg_temp.sem_c13(pg_temp.src(c_aviso))) || ' ' || pg_temp.porta(c_aviso));
  v := pg_temp.src(c_pq);
  v_res := pg_temp.ok(v_res, 'P0g _agenda_porque_da_os: com a linha de antes no lugar da marcada, é o corpo de produção de 13/11 (20261112100200, md5 b2526143…); a linha nova 1x; definer, authenticated e service_role',
    position(c_pq_novo in v) > 0 and (select count(*) from regexp_matches(v, 'CONSERTO 13/11', 'g')) = 1
    and md5(replace(v, c_pq_novo, c_pq_antes)) = 'b25261435b91ff328b9fa85ad58b73e5'
    and pg_temp.porta(c_pq) = 't s | f t t f',
    md5(replace(v, c_pq_novo, c_pq_antes)) || ' ' || pg_temp.porta(c_pq));
  v := pg_temp.src(c_rot);
  v_res := pg_temp.ok(v_res, 'P0h _agenda_rotulo_os: com a linha de antes no lugar da marcada, é o corpo de produção de 13/11 (20261024160400, md5 c5bd3e8e…); IMMUTABLE, invoker, authenticated e service_role',
    position(c_rot_novo in v) > 0 and (select count(*) from regexp_matches(v, 'CONSERTO 13/11', 'g')) = 1
    and md5(replace(v, c_rot_novo, c_rot_antes)) = 'c5bd3e8e361e4b545d82bf8ab784c5cf'
    and pg_temp.porta(c_rot) = 'f i | f t t f',
    md5(replace(v, c_rot_novo, c_rot_antes)) || ' ' || pg_temp.porta(c_rot));
  v_res := pg_temp.ok(v_res, 'P0i agenda_fechamento_registrar não muda (md5 de produção de 13/11, 9a035e2b…; definer, só service_role): quem conta continua sendo ela',
    md5(pg_temp.src('public.agenda_fechamento_registrar(date, jsonb, text, timestamptz)')) = '9a035e2b8afd1ac0ac48b794ae344daf'
    and pg_temp.porta('public.agenda_fechamento_registrar(date, jsonb, text, timestamptz)') = 't v | f f t f',
    md5(pg_temp.src('public.agenda_fechamento_registrar(date, jsonb, text, timestamptz)')));
  select count(*) into v_n
    from unnest(array[c_prem, c_conf, c_guar, c_fila, c_aviso, c_pq, c_rot]) a(f), pg_temp.sem_where(pg_temp.src(a.f)) s;
  v_res := pg_temp.ok(v_res, 'P0j nenhum UPDATE/DELETE sem WHERE no nível de cima das 7 (o pg_safeupdate do PostgREST recusaria); o detector acusa um sem WHERE (controle)',
    v_n = 0 and (select count(*) from pg_temp.sem_where('begin delete from x; update y set a = 1 where b; end')) = 1,
    (select string_agg(s, ' | ') from unnest(array[c_prem, c_conf, c_guar, c_fila, c_aviso, c_pq, c_rot]) a(f), pg_temp.sem_where(pg_temp.src(a.f)) s));
  perform pg_temp.gravar(v_res);
end
$p0$;

-- ── A. A mensagem ao cliente cai quando o plano cai (a fixture-fase5; sex 30/10/2026) ──────────────────────────────────────────────────────

-- Liga a mensagem ao cliente (todos os tipos) com a aprovação dos primeiros dias (3: o OK do dono é pedido; 0: livre).
create function pg_temp.ligar(p_aprov int default 3) returns void language sql as $f$
  update public.agenda_config
     set modo_cliente = 'ligado', cliente_aprovacao_dias = p_aprov,
         cliente_tipos_ligados = array['confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento', 'pode_atrasar', 'nova_data',
                                       'pronto', 'pronto_lembrete', 'pos_servico', 'mudanca_no_dia']
   where id
$f$;
-- Um tique da rodada do cliente, com o "hoje" de quem lê o relógio acompanhando.
create function pg_temp.vig(p_quando text) returns jsonb language plpgsql as $f$
begin
  perform set_config('agenda_teste.hoje', left(p_quando, 10), true);
  return public.agenda_cliente_vigiar(left(p_quando, 10)::date, pg_temp.em(p_quando));
end $f$;
create function pg_temp.msg(p_id uuid) returns public.agenda_cliente_mensagens language sql stable as $f$
  select m.* from public.agenda_cliente_mensagens m where m.id = p_id
$f$;
create function pg_temp.perg(p_id uuid) returns public.agenda_perguntas language sql stable as $f$
  select q.* from public.agenda_perguntas q where q.id = p_id
$f$;
-- A vigia desmarca a OS: as alocações de p_de em diante canceladas (motivo material) e, com p_status, o status volta.
create function pg_temp.desmarca(p_os uuid, p_de date, p_status text default null, p_ate date default null) returns void language plpgsql as $f$
begin
  perform set_config('agenda.mexe_fixado', 'on', true);
  update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'material'
   where service_order_id = p_os and dia >= p_de and (p_ate is null or dia <= p_ate) and estado in ('publicada', 'fixada');
  perform set_config('agenda.mexe_fixado', 'off', true);
  if p_status is not null then
    update public.service_orders set status = p_status where id = p_os;
  end if;
end $f$;
-- A pergunta aparece numa leitura? Pelo id ou pelas palavras *manda cliente <nome>*.
create function pg_temp.mostra(p_leitura jsonb, p_id uuid, p_nome text) returns boolean language sql immutable as $f$
  select coalesce(p_leitura::text like '%' || p_id::text || '%' or p_leitura::text like '%*manda cliente ' || p_nome || '*%', false)
$f$;
-- A véspera do Flávio (ter 03/11; sai seg 02/11 09:00), pela rodada, registrada às 09:30 de sex 30/10.
create function pg_temp.vespera_flavio() returns uuid language plpgsql as $f$
declare
  r jsonb;
begin
  perform set_config('agenda_teste.hoje', '2026-10-30', true);
  r := public._agenda_cliente_registrar('vespera', null, '05000000-0000-4000-8000-000000000104', date '2026-11-03', '{}'::jsonb, pg_temp.em('2026-11-02 09:00'),
                                        null, 'rodada', null, pg_temp.em('2026-10-30 09:30'));
  return (r ->> 'id')::uuid;
end $f$;

do $a$
declare
  v_res  jsonb := '[]'::jsonb;
  c_flav constant uuid := '05000000-0000-4000-8000-000000000104';
  c_luc  constant uuid := '05000000-0000-4000-8000-000000000122';
  c_dono constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_chaves_antes constant text[] := array['canceladas', 'enfileiradas', 'entrega', 'esperando', 'pela_janela', 'pelo_modo', 'recusadas', 'revalidadas', 'vencidas'];
  r      jsonb;
  r2     jsonb;
  m      public.agenda_cliente_mensagens;
  q      public.agenda_perguntas;
  v_m    uuid;
  v_q    uuid;
  v_pm   text;
  v_rv   text;
  v_ok   boolean;
  t      text;
  v_src  text;
begin
  if coalesce(current_setting('agenda_teste.fase5', true), '') = '' then
    insert into _resultado values ('A1–A8 (fixture-fase5)', true, 'PULADO: sem agenda_teste.fase5 (rode pela bancada)');
    return;
  end if;
  begin
  execute current_setting('agenda_teste.fase5');

  -- ── A1. A cena do Nelson, com o Flávio ──
  begin
    perform pg_temp.ligar(3);
    v_m := pg_temp.vespera_flavio();
    m := pg_temp.msg(v_m);
    v_q := m.pergunta_id;
    r2 := public._agenda_ver_decisoes(date '2026-10-30', pg_temp.em('2026-10-30 09:45'));
    v_ok := m.estado = 'aguardando_dono' and m.aprovacao = 'pedida' and m.modo = 'ligado' and (pg_temp.perg(v_q)).estado = 'aberta'
            and public._agenda_cliente_premissa(v_m, pg_temp.em('2026-10-30 09:45')) is null and pg_temp.mostra(r2, v_q, 'Flávio');
    t := format('nasceu %s/%s/%s, pergunta %s, mostra antes %s', m.estado, m.aprovacao, m.modo, (pg_temp.perg(v_q)).estado, pg_temp.mostra(r2, v_q, 'Flávio'));
    perform pg_temp.desmarca(c_flav, date '2026-10-30', 'awaiting_parts');
    v_pm := public._agenda_cliente_premissa(v_m, pg_temp.em('2026-10-30 10:00'));
    v_rv := public._agenda_cliente_revalidar(v_m, pg_temp.em('2026-10-30 10:00'));
    r := pg_temp.vig('2026-10-30 10:00');
    m := pg_temp.msg(v_m);
    q := pg_temp.perg(v_q);
    v_res := pg_temp.ok(v_res, 'A1a a véspera pedida esperando o dono; a vigia desmarca (alocações canceladas, a OS volta a esperar peça): no tique seguinte a mensagem cai (recusada, status) e a pergunta sai da fila do dono (descartada, "o plano caiu: …")',
      v_ok and v_pm = 'status' and m.estado = 'recusada' and m.recusa_motivo = 'status' and m.aprovacao = 'pedida'
      and q.estado = 'descartada' and q.resolvida_motivo like 'o plano caiu: a OS não está mais como a mensagem ao cliente supunha%'
      and (r #>> '{contagens,fila,plano_caiu}')::int >= 1,
      format('%s; premissa %s; depois %s/%s; pergunta %s %s; fila %s', t, v_pm, m.estado, coalesce(m.recusa_motivo, '-'), q.estado,
             coalesce(q.resolvida_motivo, '-'), r #> '{contagens,fila}'));
    v_res := pg_temp.ok(v_res, 'A1b a revalidação da hora de sair também recusava (a premissa só adianta o que a hora de sair faria)',
      v_rv is not null, coalesce(v_rv, 'null'));
    r2 := public._agenda_ver_decisoes(date '2026-10-30', pg_temp.em('2026-10-30 17:30'));
    perform set_config('agenda.agora', pg_temp.em('2026-10-30 17:30')::text, true);
    r := public._agenda_linhas_do_fechamento(date '2026-10-30');
    perform set_config('agenda.agora', '', true);
    v_res := pg_temp.ok(v_res, 'A1c *agenda pendências* e as linhas do fechamento não a mostram mais',
      not pg_temp.mostra(r2, v_q, 'Flávio') and not pg_temp.mostra(r, v_q, 'Flávio') and jsonb_typeof(r) = 'array',
      format('pendências %s, fechamento %s', pg_temp.mostra(r2, v_q, 'Flávio'), pg_temp.mostra(r, v_q, 'Flávio')));
    r := public.agenda_cliente_decidir_dito(c_dono, 'manda', 'Flávio', 'whatsapp', date '2026-10-30', pg_temp.em('2026-10-30 17:35'));
    m := pg_temp.msg(v_m);
    v_res := pg_temp.ok(v_res, 'A1d *manda cliente Flávio* depois: não promete ("Mando para Flávio …"); a mensagem segue recusada, sem fila; nenhum "não saiu" (o dono não tinha aprovado)',
      coalesce(r ->> 'texto', '') not like '%Mando para Flávio%' and m.estado = 'recusada' and m.fila_id is null
      and not exists (select 1 from public.whatsapp_send_queue w where w.source_ref_id = v_m)
      and not exists (select 1 from public.agenda_perguntas x where x.chave = 'cliente_resposta:nao_saiu:' || v_m),
      coalesce(r ->> 'texto', r::text) || ' | ' || m.estado);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A2. O plano não cai ──
  begin
    perform pg_temp.ligar(3);
    v_m := pg_temp.vespera_flavio();
    v_q := (pg_temp.msg(v_m)).pergunta_id;
    v_ok := not exists (select 1 from public.agenda_cliente_mensagens x where x.modo = 'ligado' and x.estado in ('registrada', 'aguardando_dono')
                         and public._agenda_cliente_premissa(x.id, pg_temp.em('2026-10-30 10:00')) is not null);
    r := pg_temp.vig('2026-10-30 10:00');
    m := pg_temp.msg(v_m);
    q := pg_temp.perg(v_q);
    v_res := pg_temp.ok(v_res, 'A2a o plano não caiu: o tique deixa a véspera esperando o dono e a pergunta aberta',
      m.estado = 'aguardando_dono' and m.recusa_motivo is null and q.estado = 'aberta', m.estado || ' ' || q.estado);
    v_res := pg_temp.ok(v_res, 'A2b sem nada caindo, o passo fila devolve as chaves de antes, byte a byte (plano_caiu só quando alguma caiu)',
      v_ok and (select array_agg(k order by k) from jsonb_object_keys(r #> '{contagens,fila}') k) = c_chaves_antes,
      (r #> '{contagens,fila}')::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A3. O plano muda de dia ──
  begin
    perform pg_temp.ligar(3);
    v_m := pg_temp.vespera_flavio();
    v_q := (pg_temp.msg(v_m)).pergunta_id;
    perform pg_temp.desmarca(c_flav, date '2026-11-03', null, date '2026-11-03');
    v_pm := public._agenda_cliente_premissa(v_m, pg_temp.em('2026-10-30 10:00'));
    v_rv := public._agenda_cliente_revalidar(v_m, pg_temp.em('2026-10-30 10:00'));
    r := pg_temp.vig('2026-10-30 10:00');
    m := pg_temp.msg(v_m);
    q := pg_temp.perg(v_q);
    v_res := pg_temp.ok(v_res, 'A3 as alocações de ter 03/11 canceladas (a OS segue agendada, o plano começa qua 04/11): a véspera de ter 03/11 cai com data_mudou; a pergunta sai ("o plano caiu: o dia …"); a revalidação também recusava',
      (select status from public.service_orders where id = c_flav) = 'scheduled'
      and (public._agenda_plano_da_os(c_flav, date '2026-10-30') ->> 'proximo_dia') = '2026-11-04'
      and v_pm = 'data_mudou' and v_rv is not null and m.estado = 'recusada' and m.recusa_motivo = 'data_mudou'
      and q.estado = 'descartada' and q.resolvida_motivo like 'o plano caiu: o dia de que a mensagem ao cliente falava mudou%',
      format('premissa %s, revalidação %s; %s/%s; pergunta %s %s', v_pm, coalesce(v_rv, 'null'), m.estado, coalesce(m.recusa_motivo, '-'), q.estado, coalesce(q.resolvida_motivo, '-')));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A4. A aprovada que espera a hora ──
  begin
    perform pg_temp.ligar(3);
    v_m := pg_temp.vespera_flavio();
    r := public.agenda_cliente_decidir_dito(c_dono, 'manda', 'Flávio', 'whatsapp', date '2026-10-30', pg_temp.em('2026-10-30 09:40'));
    m := pg_temp.msg(v_m);
    v_ok := m.aprovacao = 'aprovada' and m.estado in ('registrada', 'aguardando_dono') and m.fila_id is null;
    t := format('*manda*: %s; %s/%s', coalesce(r ->> 'texto', r::text), m.estado, m.aprovacao);
    update public.service_orders set status = 'cancelled' where id = c_flav;
    r := pg_temp.vig('2026-10-30 10:00');
    m := pg_temp.msg(v_m);
    q := (select x from public.agenda_perguntas x where x.chave = 'cliente_resposta:nao_saiu:' || v_m);
    v_res := pg_temp.ok(v_res, 'A4 a véspera aprovada pelo dono esperando a hora de sair, e a OS cancelada: cai (status) no tique, e o dono fica sabendo que não saiu ("a OS mudou antes de a mensagem sair"), como na hora de sair',
      v_ok and m.estado = 'recusada' and m.recusa_motivo = 'status' and q.estado = 'aberta' and q.texto like '%não saiu: a OS mudou antes de a mensagem sair%'
      and not exists (select 1 from public.whatsapp_send_queue w where w.source_ref_id = v_m),
      format('%s; depois %s/%s; não saiu: %s', t, m.estado, coalesce(m.recusa_motivo, '-'), coalesce(q.estado, 'nenhuma')));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A5. Os outros tipos ──
  begin
    perform pg_temp.ligar(0);
    perform set_config('agenda_teste.hoje', '2026-10-30', true);
    r := public._agenda_cliente_registrar('confirmar', null, c_flav, date '2026-11-03', '{}'::jsonb, pg_temp.em('2026-10-31 09:00'),
                                          null, 'rodada', null, pg_temp.em('2026-10-30 09:30'));
    v_m := (r ->> 'id')::uuid;
    m := pg_temp.msg(v_m);
    t := format('nasceu %s/%s/%s', m.estado, m.aprovacao, m.modo);
    v_ok := m.modo = 'ligado' and m.estado in ('registrada', 'aguardando_dono') and m.fila_id is null;
    perform pg_temp.desmarca(c_flav, date '2026-11-03', null, date '2026-11-03');
    r := pg_temp.vig('2026-10-30 10:00');
    m := pg_temp.msg(v_m);
    v_res := pg_temp.ok(v_res, 'A5a a confirmação (registrada para sáb 31/10 09:00, ainda não é a hora) com o dia mudado cai (data_mudou)',
      v_ok and m.estado = 'recusada' and m.recusa_motivo = 'data_mudou' and m.enviada_em is null,
      format('%s; depois %s/%s', t, m.estado, coalesce(m.recusa_motivo, '-')));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.ligar(3);
    perform pg_temp.vig('2026-10-30 15:15');
    select x.* into m from public.agenda_cliente_mensagens x where x.service_order_id = c_luc and x.tipo = 'pronto' order by x.criada_em desc limit 1;
    v_m := m.id;
    v_q := m.pergunta_id;
    v_ok := m.estado = 'aguardando_dono' and m.aprovacao = 'pedida';
    update public.service_orders set status = 'cancelled' where id = c_luc;
    r := pg_temp.vig('2026-10-30 15:30');
    m := pg_temp.msg(v_m);
    q := pg_temp.perg(v_q);
    v_res := pg_temp.ok(v_res, 'A5b o "ficou pronto" da Lucenira esperando o dono, e a OS cancelada: cai (status); a pergunta sai da fila do dono',
      v_ok and m.estado = 'recusada' and m.recusa_motivo = 'status' and q.estado <> 'aberta',
      format('%s; depois %s/%s; pergunta %s', v_ok, m.estado, coalesce(m.recusa_motivo, '-'), q.estado));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A6. Em teste, nada cai ──
  begin
    perform pg_temp.ligar(3);
    update public.agenda_config set modo_cliente = 'sombra' where id;
    v_m := pg_temp.vespera_flavio();
    m := pg_temp.msg(v_m);
    t := m.modo || '/' || m.estado;
    perform pg_temp.desmarca(c_flav, date '2026-10-30', 'awaiting_parts');
    r := pg_temp.vig('2026-10-30 10:00');
    m := pg_temp.msg(v_m);
    v_res := pg_temp.ok(v_res, 'A6 em teste (sombra): a mensagem registrada fica como está, mesmo com o plano caído',
      t = 'sombra/registrada' and m.estado = 'registrada' and m.recusa_motivo is null and coalesce((r #>> '{contagens,fila,plano_caiu}')::int, 0) = 0,
      t || ' → ' || m.estado);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A7. A conversa que falta não esconde o plano ──
  begin
    perform pg_temp.ligar(3);
    v_m := pg_temp.vespera_flavio();
    update public.agenda_config set cliente_conversa_dias = 1 where id;
    -- A7a: sem conversa e com o plano de pé, nada cai (o que não é do plano fica com a hora de sair, como antes)
    v_rv := public._agenda_cliente_revalidar(v_m, pg_temp.em('2026-10-30 09:50'));
    r := pg_temp.vig('2026-10-30 09:50');
    m := pg_temp.msg(v_m);
    v_res := pg_temp.ok(v_res, 'A7a sem conversa recente e com o plano de pé (a revalidação diz sem_conversa, a premissa vale): a véspera segue esperando o dono — o tique não derruba o que não é do plano',
      v_rv = 'sem_conversa' and public._agenda_cliente_premissa(v_m, pg_temp.em('2026-10-30 09:50')) is null and m.estado = 'aguardando_dono'
      and (pg_temp.perg(m.pergunta_id)).estado = 'aberta',
      format('revalidação %s; %s', coalesce(v_rv, 'null'), m.estado));
    perform pg_temp.desmarca(c_flav, date '2026-10-30', 'awaiting_parts');
    v_rv := public._agenda_cliente_revalidar(v_m, pg_temp.em('2026-10-30 10:00'));
    r := pg_temp.vig('2026-10-30 10:00');
    m := pg_temp.msg(v_m);
    v_res := pg_temp.ok(v_res, 'A7b e então a vigia desmarca: a revalidação ainda diz sem_conversa (vem antes do status), e a véspera cai pelo plano (status)',
      v_rv = 'sem_conversa' and m.estado = 'recusada' and m.recusa_motivo = 'status',
      format('revalidação %s; %s/%s', coalesce(v_rv, 'null'), m.estado, coalesce(m.recusa_motivo, '-')));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A8. Sem o conserto, a mesma cena do A1 deixa o pedido falso na fila do dono ──
  begin
    v_src := pg_temp.sem_c13(pg_temp.src('public._agenda_cliente_fila(date, timestamptz)'));
    execute format('create or replace function public._agenda_cliente_fila(p_hoje date, p_agora timestamptz) returns jsonb language plpgsql volatile set search_path to ''public'' as %L', v_src);
    perform pg_temp.ligar(3);
    v_m := pg_temp.vespera_flavio();
    v_q := (pg_temp.msg(v_m)).pergunta_id;
    perform pg_temp.desmarca(c_flav, date '2026-10-30', 'awaiting_parts');
    r := pg_temp.vig('2026-10-30 10:00');
    m := pg_temp.msg(v_m);
    q := pg_temp.perg(v_q);
    r2 := public._agenda_ver_decisoes(date '2026-10-30', pg_temp.em('2026-10-30 17:30'));
    v_res := pg_temp.ok(v_res, 'A8 sem o conserto (o passo fila de 20261028100800): a véspera segue esperando o dono com o plano caído, a pergunta aberta e *agenda pendências* pedindo *manda* (o teste morde)',
      m.estado = 'aguardando_dono' and q.estado = 'aberta' and pg_temp.mostra(r2, v_q, 'Flávio') and not ((r -> 'contagens') -> 'fila') ? 'plano_caiu',
      format('%s; pergunta %s; mostra %s', m.estado, q.estado, pg_temp.mostra(r2, v_q, 'Flávio')));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$a$;

-- ── B. O fechamento só conta o que a fila mandou (a fixture-fase7f; ter 10/11/2026) ─────────────────────────────────────────────────────

-- A linha da fila da tarde (a chave de resumo_tarde_registrar), pendente.
create function pg_temp.fila_da_tarde(p_dia date) returns uuid language sql as $f$
  insert into public.whatsapp_send_queue (phone_normalized, message, source, priority, max_attempts, dedupe_key)
  values ('5547900000210', 'Fechamento de teste', 'ai_briefing_tarde', 5, 3, 'secretario_tarde:' || p_dia || ':5547900000210')
  returning id
$f$;
-- O que o fechamento mostrou de uma pergunta e de uma ação (o que agenda_fechamento_registrar grava).
create function pg_temp.mostrou(p_q uuid, p_a uuid) returns jsonb language sql stable as $f$
  select jsonb_build_object('q', (select jsonb_build_object('vezes', q.mostrada_vezes, 'em', q.mostrada_em, 'via', q.mostrada_via, 'veto_ate', q.veto_ate,
                                                         'veto_teria_em', q.veto_teria_em) from public.agenda_perguntas q where q.id = p_q),
                            'a', (select jsonb_build_object('em', a.contada_em, 'via', a.contada_via) from public.agenda_acoes a where a.id = p_a))
$f$;

do $b$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje  constant date := date '2026-11-10';
  c_q     constant uuid := 'f7f00000-0000-4000-8000-000000000501';
  c_a     constant uuid := 'f7f00000-0000-4000-8000-000000000601';
  c_prazo constant timestamptz := timestamptz '2026-11-11 18:00-03';
  c_saiu  constant timestamptz := timestamptz '2026-11-10 17:35-03';
  v_lin   jsonb;
  v_f     uuid;
  v_f2    uuid;
  r       jsonb;
  r2      jsonb;
  v_antes jsonb;
  v_dep   jsonb;
  v_dir   jsonb;
  v_ok    boolean;
  v_err   text;
  v_n     int;
begin
  if coalesce(current_setting('agenda_teste.fase7f', true), '') = '' then
    insert into _resultado values ('B1–B5 (fixture-fase7f)', true, 'PULADO: sem agenda_teste.fase7f (rode pela bancada)');
    return;
  end if;
  begin
  execute current_setting('agenda_teste.fase7f');
  v_lin := jsonb_build_array(jsonb_build_object('pergunta_id', c_q, 'acao_ids', jsonb_build_array(c_a), 'veto_ate', c_prazo),
                             jsonb_build_object('pergunta_id', null, 'acao_ids', jsonb_build_array('f7f00000-0000-4000-8000-000000000602')));
  v_antes := pg_temp.mostrou(c_q, c_a);

  -- ── B1 e B2. A fila pendente; depois, a fila manda ──
  begin
    v_f := pg_temp.fila_da_tarde(c_hoje);
    r := public.agenda_fechamento_guardar(c_hoje, v_lin, v_f, 'fechamento', timestamptz '2026-11-10 17:30-03');
    v_res := pg_temp.ok(v_res, 'B1a a guarda com a fila pendente (o WhatsApp fora): {ok, esperando}; nada conta — a pergunta não fica mostrada, o prazo não nasce, a ação não fica contada',
      (r ->> 'ok')::boolean and r ->> 'estado' = 'esperando' and (r ->> 'perguntas')::int = 0 and pg_temp.mostrou(c_q, c_a) = v_antes
      and (v_antes #>> '{q,vezes}')::int = 0 and v_antes #> '{q,veto_ate}' = 'null'::jsonb and v_antes #> '{a,em}' = 'null'::jsonb
      and (select f.estado = 'esperando' and f.fila_id = v_f and f.linhas = v_lin from public.agenda_fechamento_fila f where f.id = (r ->> 'id')::uuid),
      r::text || ' | ' || pg_temp.mostrou(c_q, c_a)::text);
    r := public.agenda_aviso_conferir(timestamptz '2026-11-10 17:32-03');
    v_res := pg_temp.ok(v_res, 'B1b o aviso do motor (17:32) confere e espera: a fila segue pendente, nada conta, e a resposta é a de antes (sem a chave fechamento)',
      not r ? 'fechamento' and pg_temp.mostrou(c_q, c_a) = v_antes
      and (select f.estado from public.agenda_fechamento_fila f where f.fila_id = v_f) = 'esperando',
      r::text);
    update public.whatsapp_send_queue set status = 'sent', sent_at = c_saiu where id = v_f;
    r := public.agenda_aviso_conferir(timestamptz '2026-11-10 17:45-03');
    v_dep := pg_temp.mostrou(c_q, c_a);
    v_res := pg_temp.ok(v_res, 'B2a a fila mandou às 17:35: o tique das 17:45 conta na hora em que saiu — a pergunta mostrada (17:35, fechamento) com o prazo do texto, a ação contada; a linha registrada',
      (v_dep #>> '{q,vezes}')::int = 1 and (v_dep #>> '{q,em}')::timestamptz = c_saiu and v_dep #>> '{q,via}' = 'fechamento'
      and (v_dep #>> '{q,veto_ate}')::timestamptz = c_prazo and (v_dep #>> '{a,em}')::timestamptz = c_saiu and v_dep #>> '{a,via}' = 'fechamento'
      and (r #>> '{fechamento,registradas}')::int = 1 and (r #>> '{fechamento,perguntas}')::int = 1 and (r #>> '{fechamento,acoes}')::int = 2
      and (select f.estado = 'registrada' and f.enviada_em = c_saiu and f.resolvida_em = timestamptz '2026-11-10 17:45-03'
             from public.agenda_fechamento_fila f where f.fila_id = v_f),
      r::text || ' | ' || v_dep::text);
    r := public.agenda_aviso_conferir(timestamptz '2026-11-10 18:00-03');
    v_res := pg_temp.ok(v_res, 'B2b o tique seguinte não conta de novo (a pergunta segue 1 vez mostrada) e responde como antes',
      not r ? 'fechamento' and pg_temp.mostrou(c_q, c_a) = v_dep, r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  -- B2c: o registro de antes, chamado direto na hora em que a fila mandou, grava o mesmo (a guarda só adia)
  begin
    perform public.agenda_fechamento_registrar(c_hoje, v_lin, 'fechamento', c_saiu);
    v_dir := pg_temp.mostrou(c_q, c_a);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  v_res := pg_temp.ok(v_res, 'B2c o que a guarda conta é, campo a campo, o que agenda_fechamento_registrar gravaria na hora em que a fila mandou',
    v_dir = v_dep, coalesce(v_dir::text, 'null') || ' × ' || coalesce(v_dep::text, 'null'));
  -- B1c: o controle — o caminho de antes (o Secretário chamava o registro logo depois de enfileirar) contava com a fila pendente
  begin
    v_f := pg_temp.fila_da_tarde(c_hoje);
    perform public.agenda_fechamento_registrar(c_hoje, v_lin, 'fechamento', timestamptz '2026-11-10 17:30-03');
    v_dir := pg_temp.mostrou(c_q, c_a);
    v_res := pg_temp.ok(v_res, 'B1c o controle: o registro de antes, com a mesma fila pendente, já contava a pergunta como mostrada e começava o prazo (o defeito)',
      (select status from public.whatsapp_send_queue where id = v_f) = 'pending' and (v_dir #>> '{q,vezes}')::int = 1
      and (v_dir #>> '{q,veto_ate}')::timestamptz = c_prazo, v_dir::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── B3. A fila desiste, a linha some, ou não sai em 1 dia ──
  begin
    v_f := pg_temp.fila_da_tarde(c_hoje);
    perform public.agenda_fechamento_guardar(c_hoje, v_lin, v_f, 'fechamento', timestamptz '2026-11-10 17:30-03');
    update public.whatsapp_send_queue set status = 'failed', failed_reason = 'teste: o provedor desistiu' where id = v_f;
    r := public.agenda_aviso_conferir(timestamptz '2026-11-10 19:45-03');
    v_res := pg_temp.ok(v_res, 'B3a a fila desistiu (failed): a linha cai (fila_falhou) e nada conta — a pergunta segue nunca mostrada, sem prazo, e volta no próximo fechamento',
      (select f.estado = 'caiu' and f.motivo = 'fila_falhou' and f.enviada_em is null from public.agenda_fechamento_fila f where f.fila_id = v_f)
      and pg_temp.mostrou(c_q, c_a) = v_antes and (r #>> '{fechamento,caidas}')::int = 1 and (r #>> '{fechamento,registradas}')::int = 0,
      r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    v_f := pg_temp.fila_da_tarde(c_hoje);
    perform public.agenda_fechamento_guardar(c_hoje, v_lin, v_f, 'fechamento', timestamptz '2026-11-10 17:30-03');
    delete from public.whatsapp_send_queue where id = v_f;
    r := public.agenda_aviso_conferir(timestamptz '2026-11-10 18:00-03');
    v_res := pg_temp.ok(v_res, 'B3b a linha da fila sumiu: cai (fila_sumiu) e nada conta',
      (select f.estado = 'caiu' and f.motivo = 'fila_sumiu' from public.agenda_fechamento_fila f where f.fila_id = v_f) and pg_temp.mostrou(c_q, c_a) = v_antes,
      r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    v_f := pg_temp.fila_da_tarde(c_hoje);
    perform public.agenda_fechamento_guardar(c_hoje, v_lin, v_f, 'fechamento', timestamptz '2026-11-10 17:30-03');
    r := public.agenda_aviso_conferir(timestamptz '2026-11-11 17:29-03');
    v_ok := (select f.estado = 'esperando' from public.agenda_fechamento_fila f where f.fila_id = v_f);
    r := public.agenda_aviso_conferir(timestamptz '2026-11-11 17:31-03');
    v_res := pg_temp.ok(v_res, 'B3c pendente: espera até 1 dia (qua 17:29 ainda esperando) e depois cai (nao_saiu), sem contar',
      v_ok and (select f.estado = 'caiu' and f.motivo = 'nao_saiu' from public.agenda_fechamento_fila f where f.fila_id = v_f) and pg_temp.mostrou(c_q, c_a) = v_antes,
      r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── B4. A fila já mandou; 2x; sem a linha; as recusas ──
  begin
    v_f := pg_temp.fila_da_tarde(c_hoje);
    update public.whatsapp_send_queue set status = 'sent', sent_at = c_saiu where id = v_f;
    r := public.agenda_fechamento_guardar(c_hoje, v_lin, v_f, 'fechamento', timestamptz '2026-11-10 17:36-03');
    v_dep := pg_temp.mostrou(c_q, c_a);
    r2 := public.agenda_fechamento_guardar(c_hoje, v_lin, v_f, 'fechamento', timestamptz '2026-11-10 17:40-03');
    v_res := pg_temp.ok(v_res, 'B4a a fila já tinha mandado (17:35) quando a guarda chegou (17:36): conta na hora em que saiu, {estado registrada}; a mesma linha da fila de novo = ja_existe e não conta 2x',
      r ->> 'estado' = 'registrada' and (r ->> 'perguntas')::int = 1 and (v_dep #>> '{q,vezes}')::int = 1 and (v_dep #>> '{q,em}')::timestamptz = c_saiu
      and r2 ->> 'estado' = 'ja_existe' and pg_temp.mostrou(c_q, c_a) = v_dep
      and (select count(*) from public.agenda_fechamento_fila f where f.fila_id = v_f) = 1,
      r::text || ' | ' || r2::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    select count(*) into v_n from public.agenda_fechamento_fila;
    r := public.agenda_fechamento_guardar(c_hoje, v_lin, gen_random_uuid(), 'fechamento', timestamptz '2026-11-10 17:30-03');
    v_res := pg_temp.ok(v_res, 'B4b sem a linha da fila: {ok false, sem_fila}, nada guardado e nada conta',
      not (r ->> 'ok')::boolean and r ->> 'motivo' = 'sem_fila' and (select count(*) from public.agenda_fechamento_fila) = v_n
      and pg_temp.mostrou(c_q, c_a) = v_antes, r::text);
    v_err := '';
    begin
      perform public.agenda_fechamento_guardar(c_hoje, v_lin, gen_random_uuid(), 'acorde', now());
    exception when others then v_err := v_err || sqlstate || ';';
    end;
    begin
      perform public.agenda_fechamento_guardar(c_hoje, v_lin, null, 'fechamento', now());
    exception when others then v_err := v_err || sqlstate || ';';
    end;
    begin
      perform public.agenda_fechamento_guardar(null, v_lin, gen_random_uuid(), 'fechamento', now());
    exception when others then v_err := v_err || sqlstate || ';';
    end;
    begin
      perform public.agenda_fechamento_guardar(c_hoje, '{"x": 1}'::jsonb, gen_random_uuid(), 'fechamento', now());
    exception when others then v_err := v_err || sqlstate || ';';
    end;
    begin
      perform public._agenda_fechamento_conferir(null);
    exception when others then v_err := v_err || sqlstate || ';';
    end;
    v_res := pg_temp.ok(v_res, 'B4c as recusas: outra via (22023), sem a fila ou o dia (22004), linhas fora de lista (22023), a conferência sem a hora (22004)',
      v_err = '22023;22004;22004;22023;22004;', v_err);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── B5. Uma linha que não fecha ──
  begin
    v_f := pg_temp.fila_da_tarde(c_hoje);
    v_f2 := pg_temp.fila_da_tarde(c_hoje + 1);
    perform public.agenda_fechamento_guardar(c_hoje, '[{"pergunta_id": "nao-e-uuid", "acao_ids": []}]'::jsonb, v_f, 'fechamento', timestamptz '2026-11-10 17:30-03');
    perform public.agenda_fechamento_guardar(c_hoje + 1, v_lin, v_f2, 'fechamento', timestamptz '2026-11-11 17:30-03');
    update public.whatsapp_send_queue set status = 'sent', sent_at = c_saiu where id in (v_f, v_f2);
    select coalesce(sum(e.occurrences), 0)::int into v_n from public.app_error_logs e where e.action = 'fechamento:conferir';
    v_err := '';
    begin
      r := public.agenda_aviso_conferir(timestamptz '2026-11-11 17:45-03');
    exception when others then v_err := sqlstate || ' ' || sqlerrm;
    end;
    r2 := public.agenda_aviso_conferir(timestamptz '2026-11-11 18:00-03');
    v_res := pg_temp.ok(v_res, 'B5 a linha que não fecha cai com erro, uma vez, vai a app_error_logs (agenda / fechamento:conferir); o aviso não quebra e o outro fechamento conta',
      v_err = '' and (select f.estado = 'caiu' and f.motivo = 'erro' and f.resultado ? 'erro' from public.agenda_fechamento_fila f where f.fila_id = v_f)
      and (select f.estado = 'registrada' from public.agenda_fechamento_fila f where f.fila_id = v_f2)
      and (select coalesce(sum(e.occurrences), 0)::int from public.app_error_logs e where e.action = 'fechamento:conferir') = v_n + 1
      and (r #>> '{fechamento,caidas}')::int = 1 and (r #>> '{fechamento,registradas}')::int = 1 and not r2 ? 'fechamento',
      coalesce(nullif(v_err, ''), r::text));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$b$;

-- ── C. O porquê de uma OS reservada (o cenario_motor; qui 29/10/2026) ────────────────────────────────────────────────────────────────────

create function pg_temp.os(p_n text) returns uuid language sql immutable as $f$
  select ('05000000-0000-4000-8000-' || lpad(p_n, 12, '0'))::uuid
$f$;
-- Uma OS a mais no cenário (o molde de agenda_fase7g_como_pensei.sql), com uma alocação de turno à tarde.
create function pg_temp.os_com(p_n text, p_cliente text, p_dia date, p_tipo text, p_origem text) returns uuid language plpgsql as $f$
declare
  v_os uuid := pg_temp.os(p_n);
  v_cl uuid := ('c4000000-0000-4000-8000-' || lpad(p_n, 12, '0'))::uuid;
begin
  insert into public.clients (id, type, name) values (v_cl, 'individual', p_cliente);
  insert into public.vessels (id, client_id, name, asset_type) values (('f4000000-0000-4000-8000-' || lpad(p_n, 12, '0'))::uuid, v_cl, 'Lancha', 'Lancha');
  insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at, converted_to_os_at, grand_total)
  values (v_os, 'OS-' || lpad(p_n, 5, '0'), v_cl, ('f4000000-0000-4000-8000-' || lpad(p_n, 12, '0'))::uuid, 'approved', 'approved', 'repair',
          timestamptz '2026-10-15 12:00-03', timestamptz '2026-10-20 12:00-03', timestamptz '2026-10-20 12:00-03', 2160);
  insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at)
  values (md5('c13:servico:' || p_n)::uuid, v_os, '5e000000-0000-4000-8000-000000000003', 'Revisão do sistema elétrico', 'unit', 1, 2160, 2160, timestamptz '2026-10-15 12:00-03');
  insert into public.receivables (id, client_id, service_order_id, description, issue_date, due_date, amount, status, paid_amount, balance_amount, is_deposit)
  values (md5('c13:sinal:' || p_n)::uuid, v_cl, v_os, 'Sinal', date '2026-10-20', date '2026-10-20', 500, 'paid', 500, 0, true);
  insert into public.os_planejamento (service_order_id, dono_presenca, material_conferido_em) values (v_os, 'nunca', timestamptz '2026-10-28 18:00-03');
  insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, reserva_de, estado, origem, publicada_em, motivos, criado_em, suposicoes)
  values (md5('c13:' || p_n)::uuid, v_os, 'bb000000-0000-4000-8000-000000000003', p_dia, 'tarde', 'turno', p_tipo, case when p_tipo = 'reserva' then 'teto' end,
          'publicada', p_origem, timestamptz '2026-10-26 16:30-03', '[]', timestamptz '2026-10-26 16:30-03', '[]'::jsonb);
  return v_os;
end $f$;

do $c$
declare
  v_res jsonb := '[]'::jsonb;
  p1 jsonb; p2 jsonb; p3 jsonb; p4 jsonb; p5 jsonb;
  v_src text;
  c_agora constant timestamptz := timestamptz '2026-10-29 17:00-03';
begin
  if coalesce(current_setting('agenda_teste.cenario_motor', true), '') = '' then
    insert into _resultado values ('C1 (cenario_motor)', true, 'PULADO: sem agenda_teste.cenario_motor (rode pela bancada)');
    return;
  end if;
  begin
  execute current_setting('agenda_teste.cenario_motor');
  -- as OS antes (a leitura é STABLE: vê o que já estava gravado quando o comando começou)
  perform pg_temp.os_com('931', 'Hugo', date '2026-11-18', 'reserva', 'dono');
  perform pg_temp.os_com('932', 'Ivo', date '2026-11-19', 'reserva', 'motor');
  perform pg_temp.os_com('933', 'Jair', date '2026-11-20', 'execucao', 'dono');
  perform pg_temp.os_com('934', 'Kleber', date '2026-11-23', 'execucao', 'motor');
  p1 := public._agenda_porque_da_os(pg_temp.os('931'), date '2026-10-29', c_agora);
  p2 := public._agenda_porque_da_os(pg_temp.os('932'), date '2026-10-29', c_agora);
  p3 := public._agenda_porque_da_os(pg_temp.os('933'), date '2026-10-29', c_agora);
  p4 := public._agenda_porque_da_os(pg_temp.os('934'), date '2026-10-29', c_agora);
  v_res := pg_temp.ok(v_res, 'C1a a reserva sua: estado reservada, quem dono, quem_texto "reservado por você" (o texto longo já dizia "você reservou")',
    p1 ->> 'estado' = 'reservada' and p1 ->> 'quem' = 'dono' and p1 ->> 'quem_texto' = 'reservado por você' and p1 ->> 'texto' like '%você reservou%', p1::text);
  v_res := pg_temp.ok(v_res, 'C1b a reserva do gestor: quem gestor, quem_texto "reservado pelo gestor" (o texto longo, "reservei")',
    p2 ->> 'estado' = 'reservada' and p2 ->> 'quem' = 'gestor' and p2 ->> 'quem_texto' = 'reservado pelo gestor' and p2 ->> 'texto' like '%reservei%', p2::text);
  v_res := pg_temp.ok(v_res, 'C1c a marcada não muda: a sua "marcado por você", a do gestor "marcado pelo gestor"',
    p3 ->> 'estado' = 'marcada' and p3 ->> 'quem_texto' = 'marcado por você' and p4 ->> 'estado' = 'marcada' and p4 ->> 'quem_texto' = 'marcado pelo gestor',
    (p3 ->> 'quem_texto') || ' / ' || (p4 ->> 'quem_texto'));
  -- sem o conserto (a linha de antes no lugar), a reserva dizia "marcado …"
  begin
    v_src := replace(pg_temp.src('public._agenda_porque_da_os(uuid, date, timestamptz)'),
      $l$'quem_texto', case when v_tipo = 'reserva' and v_quem = 'dono' then 'reservado por você' when v_tipo = 'reserva' then 'reservado pelo gestor' when v_quem = 'dono' then 'marcado por você' else 'marcado pelo gestor' end,$l$,
      $l$'quem_texto', case when v_quem = 'dono' then 'marcado por você' else 'marcado pelo gestor' end,$l$);
    execute format('create or replace function public._agenda_porque_da_os(p_os uuid, p_hoje date, p_agora timestamptz) returns jsonb language plpgsql stable security definer set search_path to ''public'' as %L', v_src);
    p5 := public._agenda_porque_da_os(pg_temp.os('931'), date '2026-10-29', c_agora);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  v_res := pg_temp.ok(v_res, 'C1d sem o conserto (a linha de antes), a mesma reserva dizia "marcado por você" na chave (o teste morde)',
    p5 ->> 'estado' = 'reservada' and p5 ->> 'quem_texto' = 'marcado por você', coalesce(p5::text, 'null'));
  raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$c$;

-- ── D. O rótulo do orçamento recusado (vale em produção) ────────────────────────────────────────────────────────────────────────────────
do $d$
declare
  v_res jsonb := '[]'::jsonb;
  v_src text;
  v_antes text;
  v_antes_curto text;
begin
  v_res := pg_temp.ok(v_res, 'D1a a frase do orçamento recusado (fora da carteira): "foi recusado"',
    public._agenda_rotulo_os('draft', 'rejected', false, null, true) = 'foi recusado', public._agenda_rotulo_os('draft', 'rejected', false, null, true));
  v_res := pg_temp.ok(v_res, 'D1b o rótulo curto é "recusado" (era "recusado ou vencido"), e as outras frases não mudam (enviado, aprovado, concluída)',
    public._agenda_rotulo_os('draft', 'rejected', false, null, false) = 'recusado'
    and public._agenda_rotulo_os('draft', 'sent', false, null, true) = 'foi enviado e espera a aprovação do cliente'
    and public._agenda_rotulo_os('draft', 'approved', true, null, true) = 'orçamento assinado'
    and public._agenda_rotulo_os('completed', null, false, null, true) = 'já foi concluída',
    public._agenda_rotulo_os('draft', 'rejected', false, null, false));
  if coalesce(current_setting('agenda_teste.feriados', true), '') = '' then
    v_res := pg_temp.ok(v_res, 'D1c sem o conserto, a frase de antes', true, 'PULADO: recria a função numa subtransação; só na bancada');
    perform pg_temp.gravar(v_res);
    return;
  end if;
  begin
    v_src := replace(pg_temp.src('public._agenda_rotulo_os(text, text, boolean, text, boolean)'),
      $l$then 'foi recusado' else 'recusado' end  -- CONSERTO 13/11 (d): pedido A-2 da F5, vencer não é recusar$l$,
      $l$then 'foi recusado (ou venceu)' else 'recusado ou vencido' end$l$);
    execute format('create or replace function public._agenda_rotulo_os(p_status text, p_quote_status text, p_assinado boolean, p_juntado_em text, p_frase boolean) returns text language sql immutable set search_path to ''public'' as %L', v_src);
    v_antes := public._agenda_rotulo_os('draft', 'rejected', false, null, true);
    v_antes_curto := public._agenda_rotulo_os('draft', 'rejected', false, null, false);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  v_res := pg_temp.ok(v_res, 'D1c sem o conserto (a linha de antes), a frase era "foi recusado (ou venceu)" e o rótulo curto "recusado ou vencido" (o teste morde)',
    v_antes = 'foi recusado (ou venceu)' and v_antes_curto = 'recusado ou vencido', v_antes || ' / ' || v_antes_curto);
  perform pg_temp.gravar(v_res);
end
$d$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
