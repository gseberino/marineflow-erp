-- Prova do VENCE PRIMEIRO (20/11/2026; migration 20270129200000_agenda_fechamento_vence_primeiro.sql): no fechamento das 17:30, a mensagem ao cliente
-- mostrada inteira (com *manda cliente* / *segura cliente*) é a que VENCE primeiro (least(valida_ate, expira_em), o prazo da manhã), não a que sai primeiro.
-- bancada: depende de 20270129200000
--
--   P0  (vale em produção) a porta de _agenda_cliente_fechamento não muda (invoker, stable; authenticated e service_role, sem anon nem public); o corpo,
--       tirado o bloco "-- VENCE PRIMEIRO:" e devolvida a linha "--antes:", é o de produção de 20/11 (md5 sem CR 6744241e…); o comentário diz a mudança
--   V1  (fixture-fase5) duas mensagens do Flávio esperando o dono: a confirmação SAI antes (sáb 31/10 10:00) mas VENCE 1 dia depois da véspera
--       (registrada com a validade 1 dia depois da da véspera). O fechamento das 17:30 da véspera do envio da véspera mostra inteira a
--       véspera (a que vence primeiro) e "E mais 1"; a ordem de antes (enviar_em) mostraria a confirmação
--   V2  empate no prazo: vale a ordem de antes (a que sai primeiro)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration:  npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fechamento_vence_primeiro.sql
--   Sem as fixtures (produção) V sai PULADO; P0 roda e não grava nada. Termina em ROLLBACK: nada fica gravado e nenhuma mensagem sai.
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
create function pg_temp.em(p_quando text) returns timestamptz language sql immutable as $f$
  select (p_quando::timestamp) at time zone 'America/Sao_Paulo'
$f$;
create function pg_temp.src(p_assinatura text) returns text language sql stable as $f$
  select replace(p.prosrc, chr(13), '') from pg_proc p where p.oid = to_regprocedure(p_assinatura)
$f$;
-- Tira os blocos "-- VENCE PRIMEIRO: … -- VENCE PRIMEIRO: fim", devolvendo as linhas "--antes:" de dentro deles: o corpo de antes.
create function pg_temp.sem_vence(p text) returns text language sql immutable as $vp$
  select array_to_string(array(
           select case when dentro > 0 and l ~ '^--antes:' then substr(l, 9) else l end
             from (select l, o, sum(case when l ~ '^\s*-- VENCE PRIMEIRO:' and l !~ '^\s*-- VENCE PRIMEIRO: fim' then 1
                                         when l ~ '^\s*-- VENCE PRIMEIRO: fim' then -1 else 0 end)
                                over (order by o rows between unbounded preceding and current row) as dentro,
                          l ~ '^\s*-- VENCE PRIMEIRO: fim' as fecha
                     from unnest(string_to_array(replace(p, chr(13), ''), E'\n')) with ordinality u(l, o)) x
            where (dentro = 0 and not fecha) or (dentro > 0 and l ~ '^--antes:')
            order by o), E'\n')
$vp$;
create function pg_temp.porta(p_assinatura text) returns text language sql stable as $f$
  select format('%s %s | %s %s %s %s', p.prosecdef, p.provolatile, has_function_privilege('anon', p.oid, 'execute'),
                has_function_privilege('authenticated', p.oid, 'execute'), has_function_privilege('service_role', p.oid, 'execute'),
                coalesce((select bool_or(a.grantee = 0) from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.privilege_type = 'EXECUTE'), false))
    from pg_proc p where p.oid = to_regprocedure(p_assinatura)
$f$;

-- ── P0. A porta, o corpo e o comentário ─────────────────────────────────────────────────────────────
do $p0$
declare
  v_res jsonb := '[]'::jsonb;
  c_f   constant text := 'public._agenda_cliente_fechamento(date)';
begin
  v_res := pg_temp.ok(v_res, 'P0a a porta não muda: invoker, stable; authenticated e service_role; sem anon nem public',
    pg_temp.porta(c_f) = 'f s | f t t f', coalesce(pg_temp.porta(c_f), 'NÃO EXISTE'));
  v_res := pg_temp.ok(v_res, 'P0b sem o bloco VENCE PRIMEIRO (e com a linha --antes: de volta) o corpo é o de produção de 20/11 (md5 sem CR 6744241e…); o bloco está lá',
    left(md5(pg_temp.sem_vence(pg_temp.src(c_f))), 8) = '6744241e' and pg_temp.src(c_f) like '%-- VENCE PRIMEIRO:%'
    and pg_temp.src(c_f) like '%order by least(m.valida_ate, coalesce(q.expira_em, m.valida_ate)) nulls last, m.enviar_em, cl.name, m.tipo, m.id%',
    md5(pg_temp.sem_vence(pg_temp.src(c_f))));
  v_res := pg_temp.ok(v_res, 'P0c o comentário diz a mudança (VENCE PRIMEIRO, 20270129200000)',
    obj_description(to_regprocedure(c_f), 'pg_proc') like '%VENCE PRIMEIRO (20/11/2026, 20270129200000%', null);
  perform pg_temp.gravar(v_res);
end
$p0$;

-- ── V. As duas mensagens do Flávio (a fixture-fase5) ────────────────────────────────────────────────

create function pg_temp.ligar() returns void language sql as $f$
  update public.agenda_config
     set modo_cliente = 'ligado', cliente_aprovacao_dias = 3,
         cliente_tipos_ligados = array['confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento', 'pode_atrasar', 'nova_data',
                                       'pronto', 'pronto_lembrete', 'pos_servico', 'mudanca_no_dia']
   where id
$f$;

do $v$
declare
  v_res  jsonb := '[]'::jsonb;
  c_os   constant uuid := '05000000-0000-4000-8000-000000000104';
  ma     public.agenda_cliente_mensagens;   -- a véspera (a validade padrão da rodada)
  mb     public.agenda_cliente_mensagens;   -- a confirmação: sai sáb 31/10 10:00
  r      jsonb;
  v_cli  jsonb;
  v_ant  uuid;
  v_dia  date;
  v_pa   timestamptz;
  v_pb   timestamptz;
begin
  if coalesce(current_setting('agenda_teste.fase5', true), '') = '' then
    insert into _resultado values ('V1–V2 (fixture-fase5)', true, 'PULADO: sem agenda_teste.fase5 (rode pela bancada)');
    return;
  end if;

  -- ── V0/V1. A confirmação sai antes e vence 1 dia depois da véspera ──
  begin
    execute current_setting('agenda_teste.fase5');
    perform pg_temp.ligar();
    perform set_config('agenda_teste.hoje', '2026-10-30', true);
    r := public._agenda_cliente_registrar('vespera', null, c_os, date '2026-11-03', '{}'::jsonb, pg_temp.em('2026-11-02 09:00'),
                                          null, 'rodada', null, pg_temp.em('2026-10-30 09:30'));
    select * into ma from public.agenda_cliente_mensagens x where x.id = (r ->> 'id')::uuid;
    r := public._agenda_cliente_registrar('confirmar', null, c_os, date '2026-11-03', '{}'::jsonb, pg_temp.em('2026-10-31 10:00'),
                                          ma.valida_ate + interval '1 day', 'rodada', null, pg_temp.em('2026-10-30 09:35'));
    select * into mb from public.agenda_cliente_mensagens x where x.id = (r ->> 'id')::uuid;
    v_dia := (ma.enviar_em at time zone 'America/Sao_Paulo')::date - 1;
    select least(ma.valida_ate, coalesce(q.expira_em, ma.valida_ate)) into v_pa from public.agenda_perguntas q where q.id = ma.pergunta_id;
    select least(mb.valida_ate, coalesce(q.expira_em, mb.valida_ate)) into v_pb from public.agenda_perguntas q where q.id = mb.pergunta_id;
    v_res := pg_temp.ok(v_res, 'V0 o cenário: as duas esperando o dono (pedida); a confirmação sai antes e vence depois da véspera',
      ma.estado = 'aguardando_dono' and ma.aprovacao = 'pedida' and mb.estado = 'aguardando_dono' and mb.aprovacao = 'pedida'
      and mb.enviar_em < ma.enviar_em and v_pb > v_pa,
      format('véspera %s/%s sai %s prazo %s | confirmação %s/%s sai %s prazo %s', ma.estado, ma.aprovacao, ma.enviar_em, v_pa,
             mb.estado, mb.aprovacao, mb.enviar_em, v_pb));
    -- a ordem de antes (enviar_em) teria escolhido a confirmação
    select m.pergunta_id into v_ant from public.agenda_cliente_mensagens m where m.id in (ma.id, mb.id) order by m.enviar_em, m.tipo, m.id limit 1;
    perform set_config('agenda.agora', ((v_dia::timestamp + time '17:30') at time zone 'America/Sao_Paulo')::text, true);
    v_cli := public._agenda_cliente_fechamento(v_dia);
    perform set_config('agenda.agora', '', true);
    v_res := pg_temp.ok(v_res, 'V1a a mensagem inteira é a véspera (vence primeiro), não a confirmação (sai primeiro, a ordem de antes)',
      v_cli #>> '{0,pergunta_id}' = ma.pergunta_id::text and v_ant = mb.pergunta_id
      and v_cli #>> '{0,texto}' like 'Mensagem para Flávio (' || public._agenda_cliente_tipo_texto('vespera') || ')%',
      left(v_cli::text, 400));
    v_res := pg_temp.ok(v_res, 'V1b a outra fica no "E mais 1", com as palavras de sempre; perda 75',
      v_cli #>> '{0,texto}' like '%*manda cliente Flávio* ou *segura cliente Flávio*. E mais 1:%' and (v_cli #>> '{0,perda}')::int = 75,
      v_cli #>> '{0,texto}');
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── V2. Empate no prazo: a de antes (a que sai primeiro) ──
  begin
    execute current_setting('agenda_teste.fase5');
    perform pg_temp.ligar();
    perform set_config('agenda_teste.hoje', '2026-10-30', true);
    r := public._agenda_cliente_registrar('vespera', null, c_os, date '2026-11-03', '{}'::jsonb, pg_temp.em('2026-11-02 09:00'),
                                          null, 'rodada', null, pg_temp.em('2026-10-30 09:30'));
    select * into ma from public.agenda_cliente_mensagens x where x.id = (r ->> 'id')::uuid;
    r := public._agenda_cliente_registrar('confirmar', null, c_os, date '2026-11-03', '{}'::jsonb, pg_temp.em('2026-10-31 10:00'),
                                          ma.valida_ate, 'rodada', null, pg_temp.em('2026-10-30 09:35'));
    select * into mb from public.agenda_cliente_mensagens x where x.id = (r ->> 'id')::uuid;
    v_dia := (ma.enviar_em at time zone 'America/Sao_Paulo')::date - 1;
    perform set_config('agenda.agora', ((v_dia::timestamp + time '17:30') at time zone 'America/Sao_Paulo')::text, true);
    v_cli := public._agenda_cliente_fechamento(v_dia);
    perform set_config('agenda.agora', '', true);
    v_res := pg_temp.ok(v_res, 'V2 com o mesmo prazo, a que sai primeiro (a confirmação), como antes',
      mb.valida_ate = ma.valida_ate and v_cli #>> '{0,pergunta_id}' = mb.pergunta_id::text, left(v_cli::text, 300));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$v$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
