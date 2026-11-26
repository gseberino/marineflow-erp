-- Prova da OPÇÃO A da agenda (19/11/2026; migration 20270128100000_agenda_aprovacao_na_manha.sql): o pedido de aprovação da mensagem ao cliente entra no
-- resumo da manhã, com o prazo do banco, e a exibição é contada pelo contador que já existe (agenda_perguntas.mostrada_*), pelo caminho do fechamento
-- (agenda_fechamento_guardar → a fila manda → _agenda_fechamento_conferir → agenda_fechamento_registrar), com via 'manha'.
-- bancada: depende de 20270128100000
--
--   P0  a forma e as portas (vale em produção): agenda_aprovacoes_da_manha definer, stable, só service_role; guardar e registrar com as portas de antes
--       (só service_role); os 3 corpos = os da migration (md5 sem CR); os CHECKs de mostrada_via e de agenda_fechamento_fila.via aceitam 'manha' e só ela
--       a mais; nenhum UPDATE/DELETE sem WHERE nas 3 (pg_safeupdate)
--   P1  as recusas de sempre (vale em produção, nada grava): a guarda recusa outra via (acorde) e, na manhã, linha com ação ou com prazo (22023); a leitura
--       sem o dia ou a hora (22004); o registro com via manha numa lista vazia conta 0
--   A1  (fixture-fase5) a véspera do Flávio pedida pela rodada esperando o dono: a manhã escreve 1 linha "Flávio: o aviso da véspera de … Mando? (vence …)"
--       com o prazo de valida_ate (hoje: "19h"; na véspera: "amanhã 19h"; antes: "<dia curto> 19h"), as palavras *manda cliente Flávio* e
--       *segura cliente Flávio*, e a pergunta dela em linhas[]
--   A2  modo_cliente em teste (sombra) ou desligado: nada (total 0, texto nulo)
--   A3  depois do prazo (valida_ate), nada; depois do *manda cliente Flávio*, nada (a aprovação saiu do "esperando o dono")
--   A4  a manhã guardada com a fila pendente não conta; a fila manda: o tique do motor conta 1 vez, via 'manha', na hora em que saiu; nada é decidido (a
--       mensagem segue esperando o dono, a pergunta aberta) e o fechamento das 17:30 continua mostrando a mensagem mesmo depois de 2 manhãs (o contador
--       chega a perguntas_vezes_max e a linha do cliente não olha para ele)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration:  npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_aprovacao_na_manha.sql
--   Sem as fixtures (produção) A sai PULADO; P0 e P1 rodam e não gravam nada. Termina em ROLLBACK: nada fica gravado e nenhuma mensagem sai.
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
-- (26/11/2026, pacote 1 do assistente, A5/A4, 20270301120400) Tira os blocos "-- P1 AGENDA: … -- P1 AGENDA: fim", devolvendo as linhas "--antes:" de
-- dentro deles, e o CR: a camada mais nova sai primeiro. A manhã ganhou 3 deles, cada um DENTRO de um bloco TERMINOU (a linha de antes de cada um é
-- a do "terminou?"); sem eles, o corpo volta ao de produção de 26/11, e o src abaixo tira os TERMINOU como antes. Provado em agenda_p1_manha.sql.
create function pg_temp.sem_p1(p text) returns text language sql immutable as $p1$
  select array_to_string(array(
           select case when dentro > 0 and l ~ '^--antes:' then substr(l, 9) else l end
             from (select l, o, sum(case when l ~ '^\s*-- P1 AGENDA:' and l !~ '^\s*-- P1 AGENDA: fim' then 1
                                         when l ~ '^\s*-- P1 AGENDA: fim' then -1 else 0 end)
                                over (order by o rows between unbounded preceding and current row) as dentro,
                          l ~ '^\s*-- P1 AGENDA: fim' as fecha
                     from unnest(string_to_array(replace(p, chr(13), ''), E'\n')) with ordinality u(l, o)) x
            where (dentro = 0 and not fecha) or (dentro > 0 and l ~ '^--antes:')
            order by o), E'\n')
$p1$;
-- O corpo (prosrc, sem CR) de uma função pela assinatura.
-- (23/11/2026, 20270223100000) Sem os blocos "-- TERMINOU: … -- TERMINOU: fim" (devolvidas as linhas "--antes:"): o "terminou ou falta dia?" acrescentou
-- 3 deles a agenda_aprovacoes_da_manha, e o corpo desta Opção A continua o mesmo; o resto é provado em agenda_terminou_falta_dia.sql.
-- (26/11/2026, 20270301120400) e antes, sem os "-- P1 AGENDA:" (pg_temp.sem_p1): o md5 esperado não muda.
create function pg_temp.src(p_assinatura text) returns text language sql stable as $f$
  select array_to_string(array(
           select case when dentro > 0 and l ~ '^--antes:' then substr(l, 9) else l end
             from (select l, o, sum(case when l ~ '^\s*-- TERMINOU:' and l !~ '^\s*-- TERMINOU: fim' then 1
                                         when l ~ '^\s*-- TERMINOU: fim' then -1 else 0 end)
                                over (order by o rows between unbounded preceding and current row) as dentro,
                          l ~ '^\s*-- TERMINOU: fim' as fecha
                     from unnest(string_to_array(pg_temp.sem_p1(p.prosrc), E'\n')) with ordinality u(l, o)) x
            where (dentro = 0 and not fecha) or (dentro > 0 and l ~ '^--antes:')
            order by o), E'\n')
    from pg_proc p where p.oid = to_regprocedure(p_assinatura)
$f$;
-- Tira os blocos "-- OPÇÃO A: … -- OPÇÃO A: fim", devolvendo as linhas "--antes:" de dentro deles (a convenção da FICHA PAGA): o corpo de antes.
create function pg_temp.sem_opcao_a(p text) returns text language sql immutable as $oa$
  select array_to_string(array(
           select case when dentro > 0 and l ~ '^--antes:' then substr(l, 9) else l end
             from (select l, o, sum(case when l ~ '^\s*-- OPÇÃO A:' and l !~ '^\s*-- OPÇÃO A: fim' then 1
                                         when l ~ '^\s*-- OPÇÃO A: fim' then -1 else 0 end)
                                over (order by o rows between unbounded preceding and current row) as dentro,
                          l ~ '^\s*-- OPÇÃO A: fim' as fecha
                     from unnest(string_to_array(replace(p, chr(13), ''), E'\n')) with ordinality u(l, o)) x
            where (dentro = 0 and not fecha) or (dentro > 0 and l ~ '^--antes:')
            order by o), E'\n')
$oa$;
-- A porta de uma função: "definer volatilidade | anon authenticated service_role public" (EXECUTE; t ou f).
create function pg_temp.porta(p_assinatura text) returns text language sql stable as $f$
  select format('%s %s | %s %s %s %s', p.prosecdef, p.provolatile, has_function_privilege('anon', p.oid, 'execute'),
                has_function_privilege('authenticated', p.oid, 'execute'), has_function_privilege('service_role', p.oid, 'execute'),
                coalesce((select bool_or(a.grantee = 0) from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.privilege_type = 'EXECUTE'), false))
    from pg_proc p where p.oid = to_regprocedure(p_assinatura)
$f$;
-- UPDATE/DELETE sem WHERE no nível de cima (o detector da 20261112300000, resumido: sem comentários nem strings).
create function pg_temp.sem_where(p_corpo text) returns setof text language sql immutable as $f$
  with c as (
    select regexp_replace(regexp_replace(p_corpo, '--[^\n]*', '', 'g'), '''(?:[^'']|'''')*''', '''''', 'g') as corpo
  )
  select btrim(regexp_replace(m[1], '\s+', ' ', 'g'))
    from c, regexp_matches(c.corpo, '(?<![a-z0-9_.])((?:update|delete\s+from)\s+(?:only\s+)?(?!(?:set|of|on|or|loop|skip|nowait)\M)(?:[a-z_][a-z0-9_]*\.)?[a-z_][a-z0-9_]*\M[^;]*)', 'gi') as m
   where m[1] !~* '\mwhere\M'
$f$;

-- ── P0. A forma e as portas ──────────────────────────────────────────────────────────────────────────────────────────────────────────
do $p0$
declare
  v_res jsonb := '[]'::jsonb;
  r     record;
  v_def text;
begin
  for r in select * from (values
      ('public.agenda_aprovacoes_da_manha(date,timestamptz)', 't s | f f t f', '2b1ce097e178e73c5668fad5b44298e0'),
      ('public.agenda_fechamento_guardar(date,jsonb,uuid,text,timestamptz)', 't v | f f t f', '83007d5c25b4b1911392d036cd21589b'),
      ('public.agenda_fechamento_registrar(date,jsonb,text,timestamptz)', 't v | f f t f', '1ba6ba7bdb6a405b1dff3a00e1fe47f4')
    ) x(f, porta, m)
  loop
    v_res := pg_temp.ok(v_res, format('P0a %s: a porta (definer, volatilidade; só service_role) e o corpo da migration (md5 sem CR %s…)', r.f, left(r.m, 8)),
      pg_temp.porta(r.f) = r.porta and md5(pg_temp.src(r.f)) = r.m
      and exists (select 1 from pg_proc p, unnest(p.proconfig) c where p.oid = to_regprocedure(r.f) and replace(c, '"', '') = 'search_path=public'),
      coalesce(pg_temp.porta(r.f), 'NÃO EXISTE') || ' md5 ' || coalesce(md5(pg_temp.src(r.f)), '-') || ' config '
      || coalesce((select array_to_string(p.proconfig, ',') from pg_proc p where p.oid = to_regprocedure(r.f)), '-'));
    v_res := pg_temp.ok(v_res, format('P0b %s: nenhum UPDATE/DELETE sem WHERE (pg_safeupdate)', r.f),
      not exists (select 1 from pg_temp.sem_where(coalesce(pg_temp.src(r.f), ''))),
      (select string_agg(x, ' | ') from pg_temp.sem_where(coalesce(pg_temp.src(r.f), '')) x));
  end loop;
  select pg_get_constraintdef(c.oid) into v_def from pg_constraint c
   where c.conrelid = 'public.agenda_perguntas'::regclass and c.conname = 'agenda_perguntas_mostrada_via_check';
  v_res := pg_temp.ok(v_res, 'P0c agenda_perguntas.mostrada_via: as 4 de antes (fechamento, acorde, conversa, aviso) e manha',
    v_def = 'CHECK ((mostrada_via = ANY (ARRAY[''fechamento''::text, ''acorde''::text, ''conversa''::text, ''aviso''::text, ''manha''::text])))', v_def);
  select pg_get_constraintdef(c.oid) into v_def from pg_constraint c
   where c.conrelid = 'public.agenda_fechamento_fila'::regclass and c.conname = 'agenda_fechamento_fila_via_check';
  v_res := pg_temp.ok(v_res, 'P0d agenda_fechamento_fila.via: fechamento e manha',
    v_def = 'CHECK ((via = ANY (ARRAY[''fechamento''::text, ''manha''::text])))', v_def);
  -- as 2 recriadas, tirados os blocos "-- OPÇÃO A:" (e devolvidas as linhas "--antes:"), são as de produção de hoje, byte a byte
  v_res := pg_temp.ok(v_res, 'P0e guardar e registrar sem os blocos da Opção A = os corpos de produção de 19/11 (md5 sem CR c12f67c9… e 9a035e2b…)',
    md5(pg_temp.sem_opcao_a(pg_temp.src('public.agenda_fechamento_guardar(date,jsonb,uuid,text,timestamptz)'))) = 'c12f67c90b394bce4e29458ceabd91e0'
    and md5(pg_temp.sem_opcao_a(pg_temp.src('public.agenda_fechamento_registrar(date,jsonb,text,timestamptz)'))) = '9a035e2b8afd1ac0ac48b794ae344daf'
    and pg_temp.src('public.agenda_fechamento_guardar(date,jsonb,uuid,text,timestamptz)') like '%-- OPÇÃO A:%',
    md5(pg_temp.sem_opcao_a(pg_temp.src('public.agenda_fechamento_guardar(date,jsonb,uuid,text,timestamptz)'))) || ' / '
    || md5(pg_temp.sem_opcao_a(pg_temp.src('public.agenda_fechamento_registrar(date,jsonb,text,timestamptz)'))));
  perform pg_temp.gravar(v_res);
end
$p0$;

-- ── P1. As recusas (nada grava) ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $p1$
declare
  v_res jsonb := '[]'::jsonb;
  v_err text := '';
  r     jsonb;
begin
  begin
    perform public.agenda_fechamento_guardar(date '2026-11-21', '[]'::jsonb, gen_random_uuid(), 'acorde', now());
  exception when others then v_err := v_err || sqlstate || ';';
  end;
  begin
    perform public.agenda_fechamento_guardar(date '2026-11-21', jsonb_build_array(jsonb_build_object('pergunta_id', gen_random_uuid(), 'acao_ids', jsonb_build_array(gen_random_uuid()))),
                                             gen_random_uuid(), 'manha', now());
  exception when others then v_err := v_err || sqlstate || ';';
  end;
  begin
    perform public.agenda_fechamento_guardar(date '2026-11-21', jsonb_build_array(jsonb_build_object('pergunta_id', gen_random_uuid(), 'veto_ate', now())),
                                             gen_random_uuid(), 'manha', now());
  exception when others then v_err := v_err || sqlstate || ';';
  end;
  begin
    perform public.agenda_fechamento_guardar(date '2026-11-21', '[1]'::jsonb, gen_random_uuid(), 'manha', now());
  exception when others then v_err := v_err || sqlstate || ';';
  end;
  begin
    perform public.agenda_aprovacoes_da_manha(null, now());
  exception when others then v_err := v_err || sqlstate || ';';
  end;
  v_res := pg_temp.ok(v_res, 'P1a as recusas: a guarda com outra via (22023); na manhã, linha com ação, com prazo ou que não é objeto (22023); a leitura sem o dia (22004)',
    v_err = '22023;22023;22023;22023;22004;', v_err);
  -- a manhã só com perguntas e sem a linha da fila: nada guardado (a recusa do sem_fila de sempre)
  r := public.agenda_fechamento_guardar(date '2026-11-21', jsonb_build_array(jsonb_build_object('pergunta_id', gen_random_uuid(), 'acao_ids', '[]'::jsonb)),
                                        gen_random_uuid(), 'manha', now());
  v_res := pg_temp.ok(v_res, 'P1b a manhã com a linha certa e sem a linha da fila: {ok false, sem_fila}, nada guardado',
    r ->> 'motivo' = 'sem_fila' and coalesce((r ->> 'ok')::boolean, true) = false, r::text);
  r := public.agenda_fechamento_registrar(date '2026-11-21', '[]'::jsonb, 'manha', now());
  v_res := pg_temp.ok(v_res, 'P1c o registro aceita a via manha (lista vazia: 0 perguntas, 0 ações)',
    (r ->> 'perguntas')::int = 0 and (r ->> 'acoes')::int = 0, r::text);
  perform pg_temp.gravar(v_res);
end
$p1$;

-- ── A. A manhã com a véspera pedida (a fixture-fase5) ────────────────────────────────────────────────────────────────────────────────

-- Liga a mensagem ao cliente (todos os tipos) com a aprovação dos primeiros dias (3: o OK do dono é pedido).
create function pg_temp.ligar(p_aprov int default 3) returns void language sql as $f$
  update public.agenda_config
     set modo_cliente = 'ligado', cliente_aprovacao_dias = p_aprov,
         cliente_tipos_ligados = array['confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento', 'pode_atrasar', 'nova_data',
                                       'pronto', 'pronto_lembrete', 'pos_servico', 'mudanca_no_dia']
   where id
$f$;
-- A véspera do Flávio (ter 03/11; sai seg 02/11 09:00), pela rodada, registrada às 09:30 de sex 30/10 (a mesma do teste dos consertos de 13/11).
create function pg_temp.vespera_flavio() returns uuid language plpgsql as $f$
declare
  r jsonb;
begin
  perform set_config('agenda_teste.hoje', '2026-10-30', true);
  r := public._agenda_cliente_registrar('vespera', null, '05000000-0000-4000-8000-000000000104', date '2026-11-03', '{}'::jsonb, pg_temp.em('2026-11-02 09:00'),
                                        null, 'rodada', null, pg_temp.em('2026-10-30 09:30'));
  return (r ->> 'id')::uuid;
end $f$;
-- O prazo como a manhã escreve, a partir de valida_ate (Brasília) e do dia da manhã.
create function pg_temp.vence(p_valida timestamptz, p_hoje date) returns text language sql stable as $f$
  select 'vence ' || case when (p_valida at time zone 'America/Sao_Paulo')::date = p_hoje then ''
                          when (p_valida at time zone 'America/Sao_Paulo')::date = p_hoje + 1 then 'amanhã '
                          else public._dia_curto((p_valida at time zone 'America/Sao_Paulo')::date) || ' ' end
         || to_char(p_valida at time zone 'America/Sao_Paulo', 'FMHH24') || 'h'
         || case when extract(minute from p_valida at time zone 'America/Sao_Paulo') <> 0 then to_char(p_valida at time zone 'America/Sao_Paulo', 'MI') else '' end
$f$;

do $a$
declare
  v_res   jsonb := '[]'::jsonb;
  c_dono  constant uuid := 'aa000000-0000-4000-8000-000000000001';
  m       public.agenda_cliente_mensagens;
  q       public.agenda_perguntas;
  v_m     uuid;
  v_q     uuid;
  v_dia   date;
  v_manha timestamptz;
  v_oque  text;
  r       jsonb;
  r1      jsonb;
  r2      jsonb;
  v_f     uuid;
  v_f2    uuid;
  v_saiu  timestamptz;
  v_lin   jsonb;
  v_cli   jsonb;
begin
  if coalesce(current_setting('agenda_teste.fase5', true), '') = '' then
    insert into _resultado values ('A1–A4 (fixture-fase5)', true, 'PULADO: sem agenda_teste.fase5 (rode pela bancada)');
    return;
  end if;
  begin
  execute current_setting('agenda_teste.fase5');

  -- ── A1. A linha da manhã ──
  begin
    perform pg_temp.ligar(3);
    v_m := pg_temp.vespera_flavio();
    select * into m from public.agenda_cliente_mensagens x where x.id = v_m;
    v_q := m.pergunta_id;
    v_dia := (m.valida_ate at time zone 'America/Sao_Paulo')::date;
    v_manha := (v_dia::timestamp + time '07:30') at time zone 'America/Sao_Paulo';
    v_oque := public._agenda_cliente_o_que(m.tipo, coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo));
    r := public.agenda_aprovacoes_da_manha(v_dia, v_manha);
    r1 := public.agenda_aprovacoes_da_manha(v_dia - 1, v_manha - interval '1 day');
    r2 := public.agenda_aprovacoes_da_manha(v_dia - 2, v_manha - interval '2 days');
    v_res := pg_temp.ok(v_res, 'A1a a véspera pedida esperando o dono: 1 linha "Flávio: <o que>. Mando? (vence <hora>)" com o prazo de valida_ate, a pergunta dela em linhas[]',
      m.estado = 'aguardando_dono' and m.aprovacao = 'pedida' and (r ->> 'total')::int = 1
      and r #>> '{linhas,0,pergunta_id}' = v_q::text and r #>> '{linhas,0,mensagem_id}' = v_m::text
      and r #>> '{linhas,0,texto}' = format('Flávio: %s. Mando? (%s)', v_oque, pg_temp.vence(m.valida_ate, v_dia))
      and (r #>> '{linhas,0,vence_em}')::timestamptz = m.valida_ate,
      format('%s/%s; %s', m.estado, m.aprovacao, r::text));
    v_res := pg_temp.ok(v_res, 'A1b o bloco: o título, a linha com "• ", as palavras que já existem (*manda cliente Flávio* / *segura cliente Flávio*) e *agenda clientes*',
      r ->> 'texto' = '📨 Mensagem ao cliente esperando o seu sim:' || E'\n' || '• ' || (r #>> '{linhas,0,texto}') || E'\n'
                       || 'Para mandar: *manda cliente Flávio*. Para não mandar: *segura cliente Flávio*. O texto: *agenda clientes*.',
      r ->> 'texto');
    v_res := pg_temp.ok(v_res, 'A1c o prazo pelo dia da manhã: no dia "vence 19h", na véspera "vence amanhã 19h", antes "vence <dia curto> 19h" (a hora é a de valida_ate)',
      r #>> '{linhas,0,texto}' like '%(vence ' || to_char(m.valida_ate at time zone 'America/Sao_Paulo', 'FMHH24') || 'h%)'
      and r1 #>> '{linhas,0,texto}' like '%(vence amanhã %h%)'
      and r2 #>> '{linhas,0,texto}' like '%(vence ' || public._dia_curto(v_dia) || ' %h%)',
      concat_ws(' | ', r #>> '{linhas,0,texto}', r1 #>> '{linhas,0,texto}', r2 #>> '{linhas,0,texto}'));

    -- ── A2. Em teste ou desligado: nada ──
    update public.agenda_config set modo_cliente = 'sombra' where id;
    r1 := public.agenda_aprovacoes_da_manha(v_dia, v_manha);
    update public.agenda_config set modo_cliente = 'desligado' where id;
    r2 := public.agenda_aprovacoes_da_manha(v_dia, v_manha);
    update public.agenda_config set modo_cliente = 'ligado' where id;
    v_res := pg_temp.ok(v_res, 'A2 modo_cliente em teste ou desligado: nada (total 0, texto nulo; o *manda cliente* também não valeria)',
      (r1 ->> 'total')::int = 0 and r1 -> 'texto' = 'null'::jsonb and (r2 ->> 'total')::int = 0 and r2 -> 'texto' = 'null'::jsonb,
      r1::text || ' / ' || r2::text);

    -- ── A3. Depois do prazo, nada; depois do *manda*, nada ──
    r1 := public.agenda_aprovacoes_da_manha(v_dia, m.valida_ate + interval '1 minute');
    v_res := pg_temp.ok(v_res, 'A3a depois de valida_ate a mensagem não aparece (não sai mais)', (r1 ->> 'total')::int = 0, r1::text);

    -- ── A4. A manhã guardada; a fila manda; o motor conta ──
    insert into public.whatsapp_send_queue (phone_normalized, message, source, priority, max_attempts, dedupe_key)
    values ('5547900000210', 'Manhã de teste', 'ai_briefing', 4, 3, 'teste_manha:' || v_dia)
    returning id into v_f;
    v_lin := jsonb_build_array(jsonb_build_object('pergunta_id', v_q, 'acao_ids', '[]'::jsonb));
    r := public.agenda_fechamento_guardar(v_dia, v_lin, v_f, 'manha', v_manha);
    select * into q from public.agenda_perguntas x where x.id = v_q;
    v_res := pg_temp.ok(v_res, 'A4a a manhã guardada com a fila pendente: {ok, esperando}, via manha em agenda_fechamento_fila; a pergunta ainda não conta',
      r ->> 'estado' = 'esperando' and q.mostrada_vezes = 0 and q.mostrada_via is null
      and (select f.via from public.agenda_fechamento_fila f where f.fila_id = v_f) = 'manha',
      r::text || ' vezes ' || q.mostrada_vezes);
    v_saiu := v_manha + interval '2 minutes';
    update public.whatsapp_send_queue set status = 'sent', sent_at = v_saiu where id = v_f;
    r := public.agenda_aviso_conferir(v_manha + interval '15 minutes');
    select * into q from public.agenda_perguntas x where x.id = v_q;
    select * into m from public.agenda_cliente_mensagens x where x.id = v_m;
    v_res := pg_temp.ok(v_res, 'A4b a fila mandou: o tique do motor conta a pergunta 1 vez, via manha, na hora em que saiu; a linha fica registrada',
      q.mostrada_vezes = 1 and q.mostrada_via = 'manha' and q.mostrada_em = v_saiu
      and (select f.estado from public.agenda_fechamento_fila f where f.fila_id = v_f) = 'registrada',
      format('vezes %s via %s em %s', q.mostrada_vezes, q.mostrada_via, q.mostrada_em));
    v_res := pg_temp.ok(v_res, 'A4c mostrar não decide: a mensagem segue esperando o dono, a pergunta aberta, nada foi à fila do cliente; o prazo (veto_ate) não nasce',
      m.estado = 'aguardando_dono' and m.aprovacao = 'pedida' and q.estado = 'aberta' and q.veto_ate is null and m.fila_id is null,
      format('%s/%s pergunta %s veto %s', m.estado, m.aprovacao, q.estado, q.veto_ate));
    -- 2ª manhã (o dia seguinte de calendário, só para contar): o contador chega a perguntas_vezes_max
    insert into public.whatsapp_send_queue (phone_normalized, message, source, priority, max_attempts, dedupe_key, status, sent_at)
    values ('5547900000210', 'Manhã de teste 2', 'ai_briefing', 4, 3, 'teste_manha2:' || v_dia, 'sent', v_saiu + interval '1 minute')
    returning id into v_f2;
    r := public.agenda_fechamento_guardar(v_dia, v_lin, v_f2, 'manha', v_saiu + interval '2 minutes');
    select * into q from public.agenda_perguntas x where x.id = v_q;
    r1 := public.agenda_fechamento_guardar(v_dia, v_lin, v_f2, 'manha', v_saiu + interval '3 minutes');
    -- o fechamento da véspera do envio (17:30): a linha do cliente de _agenda_cliente_fechamento
    perform set_config('agenda.agora', ((((m.enviar_em at time zone 'America/Sao_Paulo')::date - 1)::timestamp + time '17:30') at time zone 'America/Sao_Paulo')::text, true);
    v_cli := public._agenda_cliente_fechamento((m.enviar_em at time zone 'America/Sao_Paulo')::date - 1);
    perform set_config('agenda.agora', '', true);
    v_res := pg_temp.ok(v_res, 'A4d a fila já tinha mandado: conta na hora (2ª vez); a mesma linha da fila de novo não conta; com o contador em perguntas_vezes_max, o fechamento ainda mostra a mensagem (*manda cliente Flávio*)',
      r ->> 'estado' = 'registrada' and (r ->> 'perguntas')::int = 1 and q.mostrada_vezes = 2 and r1 ->> 'estado' = 'ja_existe'
      and (select x.mostrada_vezes from public.agenda_perguntas x where x.id = v_q) = 2
      and q.mostrada_vezes >= (select c.perguntas_vezes_max from public.agenda_config c where c.id)
      and v_cli::text like '%' || v_q::text || '%' and v_cli::text like '%*manda cliente Flávio*%',
      format('%s | %s | vezes %s | fechamento %s', r, r1, q.mostrada_vezes, left(v_cli::text, 200)));

    -- A3b: o *manda cliente Flávio* tira a mensagem do "esperando o dono": a manhã seguinte não a pede mais
    r := public.agenda_cliente_decidir_dito(c_dono, 'manda', 'Flávio', 'whatsapp', v_dia - 1, v_manha - interval '1 day' + interval '10 minutes');
    r1 := public.agenda_aprovacoes_da_manha(v_dia, v_manha);
    v_res := pg_temp.ok(v_res, 'A3b depois do *manda cliente Flávio* a manhã não pede mais (aprovada sai do esperando o dono)',
      (r ->> 'ok')::boolean and (r1 ->> 'total')::int = 0, coalesce(r ->> 'texto', r::text) || ' | ' || r1::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$a$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
