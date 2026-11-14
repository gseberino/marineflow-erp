-- Prova dos pedidos A-1, A-3 e A-5 da F5 do retorno à Agenda de Produção (migration 20261113300000_agenda_pedidos_retorno.sql): a mensagem da agenda
-- espera o dia seguinte quando a saída do orçamento já foi ao cliente hoje (A-1); a confirmação espera o dia útil seguinte ao "Fechado" (A-3); o teto do
-- dia a todos soma as iniciadas do retorno (A-5).
-- bancada: depende de 20261113300000
--
--   P0  a forma e as portas (vale em produção): as 2 novas (invoker, STABLE, ninguém executa); as 3 recriadas = a origem de produção de 13/11 + só os
--       blocos "-- PEDIDO A-x (F5):" (md5 sem CR), com as portas de antes; os 2 gatilhos da fila seguem chamando a trava; nenhum UPDATE/DELETE sem WHERE
--   R0  sem retorno_saidas (a bancada da agenda deixa as migrations do retorno de fora): as 2 novas devolvem null e 0 (a agenda fica como antes). Na bancada,
--       o teste cria a tabela com as colunas que as 2 novas leem e os CHECKs de emissor, classe e estado da F5 (o "orcamento" e o "comercial" que a
--       bancada não tem); ela some no rollback. Com a tabela de verdade (produção), R0 sai PULADO e A, B e M também (precisam da fixture-fase5).
--   A1  (fixture-fase5; sex 30/10/2026) A-1: a confirmação do Flávio (livre, vale até sáb 31/10) e o lembrete do orçamento já enviado a ele às 09:00: no
--       enfileirar das 10:00 ela espera o dia seguinte (registrada, sáb 31/10 08:00, motivo orcamento_hoje; nada na fila, nada recusado); no sábado sai;
--       a que vale só na sexta não tem como esperar e fica recusada pelo teto do dia; o aviso de atraso que não pode esperar vira a pergunta crítica ao
--       dono (d13); sem saída hoje (a de ontem), a de antes; o que não conta (sombra, agendada, recusada, outro emissor, outro cliente, a de depois de agora);
--       incerta e enviando contam; o passo fila de ponta a ponta; o *manda cliente* do dono responde a hora nova
--   A3  A-3: o "Fechado" de sex 30/10: a confirmação de sábado espera ter 03/11 (o dia útil: sábado, domingo e Finados fora), motivo orcamento_fechado; a
--       véspera não espera (o A-3 é só da confirmação); a confirmação que vale só no sábado fica recusada; o "Fechado" de hoje leva ao dia útil (não ao
--       sábado); o "Fechado" antigo não segura; com sábado útil, o sábado já é o dia útil
--   A5  A-5: o teto do dia a todos (cliente_total_dia_max 2) com 2 iniciadas do retorno de hoje a outro cliente recusa a confirmação (teto_total); o que
--       não conta (resposta imediata ou atrasada, sombra, agendada, de ontem); por cliente, como antes; o gatilho da fila conta igual (23514 teto_total)
--   B1  a 2ª trava: a linha da fila do dia do orçamento é recusada (23514, teto_dia); sem a saída, entra
--   M   sem os pedidos (as 3 recriadas sem os blocos, numa subtransação), as mesmas cenas do A1a, A3a, A5a e B1 deixam a mensagem ir no mesmo dia (o
--       teste morde)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration:  npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_pedidos_retorno.sql
--   Sem as fixtures (produção) R0, A, B e M saem PULADO; P0 roda e não grava nada. Termina em ROLLBACK: nada fica gravado e nenhuma mensagem sai.
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
-- O dia e a hora de Brasília de um instante ('2026-10-31 08:00').
create function pg_temp.br(p timestamptz) returns text language sql immutable as $f$
  select to_char(p at time zone 'America/Sao_Paulo', 'YYYY-MM-DD HH24:MI')
$f$;
-- O corpo (prosrc, sem CR) de uma função pela assinatura.
create function pg_temp.src(p_assinatura text) returns text language sql stable as $f$
  select replace(p.prosrc, chr(13), '') from pg_proc p where p.oid = to_regprocedure(p_assinatura)
$f$;
-- Tira os blocos "-- PEDIDO A-x (F5): … -- PEDIDO A-x (F5): fim" (o que a 20261113300000 acrescentou).
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
  c_esp  constant text := 'public._agenda_cliente_orcamento_espera(uuid, text, date, timestamptz)';
  c_ret  constant text := 'public._agenda_cliente_retorno_no_periodo(date, date)';
  c_enf  constant text := 'public._agenda_cliente_enfileirar(uuid, timestamptz)';
  c_tra  constant text := 'public._agenda_fila_do_cliente()';
  c_per  constant text := 'public._agenda_cliente_no_periodo(uuid, date, date, uuid)';
  v_n int;
begin
  v_res := pg_temp.ok(v_res, 'P0a _agenda_cliente_orcamento_espera: 1 assinatura, invoker, STABLE, search_path=public; ninguém executa (nem anon, authenticated, service_role ou PUBLIC)',
    (select count(*) from pg_proc x where x.pronamespace = 'public'::regnamespace and x.proname = '_agenda_cliente_orcamento_espera') = 1
    and pg_temp.porta(c_esp) = 'f s | f f f f'
    and (select coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=public%' from pg_proc p where p.oid = to_regprocedure(c_esp)),
    pg_temp.porta(c_esp));
  v_res := pg_temp.ok(v_res, 'P0b _agenda_cliente_retorno_no_periodo: 1 assinatura, invoker, STABLE, search_path=public; ninguém executa',
    (select count(*) from pg_proc x where x.pronamespace = 'public'::regnamespace and x.proname = '_agenda_cliente_retorno_no_periodo') = 1
    and pg_temp.porta(c_ret) = 'f s | f f f f'
    and (select coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=public%' from pg_proc p where p.oid = to_regprocedure(c_ret)),
    pg_temp.porta(c_ret));
  v_res := pg_temp.ok(v_res, 'P0c _agenda_cliente_enfileirar: tirados os 2 blocos "-- PEDIDO A-1 e A-3 (F5):", é o corpo de produção de 13/11 (20261028100800, md5 39c92c14…); definer, ninguém executa',
    md5(pg_temp.sem_pedido(pg_temp.src(c_enf))) = '39c92c146c43d1a24dcdb42afaea14b7' and md5(pg_temp.src(c_enf)) <> '39c92c146c43d1a24dcdb42afaea14b7'
    and (select count(*) from regexp_matches(pg_temp.src(c_enf), '-- PEDIDO A-1 e A-3 \(F5\): fim', 'g')) = 2
    and pg_temp.porta(c_enf) = 't v | f f f f',
    md5(pg_temp.sem_pedido(pg_temp.src(c_enf))) || ' ' || pg_temp.porta(c_enf));
  v_res := pg_temp.ok(v_res, 'P0d _agenda_fila_do_cliente (a 2ª trava): tirado o bloco "-- PEDIDO A-1 e A-3 (F5):", é o corpo de produção de 13/11 (20261028100200, md5 6e462b74…); definer, ninguém executa; os 2 gatilhos da fila seguem nela, só para agenda-cliente',
    md5(pg_temp.sem_pedido(pg_temp.src(c_tra))) = '6e462b7407bf84237607f2ab7b11df1b' and md5(pg_temp.src(c_tra)) <> '6e462b7407bf84237607f2ab7b11df1b'
    and (select count(*) from regexp_matches(pg_temp.src(c_tra), '-- PEDIDO A-1 e A-3 \(F5\): fim', 'g')) = 1
    and pg_temp.porta(c_tra) = 't v | f f f f'
    and (select count(*) from pg_trigger t where t.tgrelid = 'public.whatsapp_send_queue'::regclass and not t.tgisinternal
           and t.tgfoid = to_regprocedure(c_tra) and t.tgname in ('trg_agenda_fila_do_cliente', 'trg_agenda_fila_do_cliente_linha')
           and pg_get_triggerdef(t.oid) like '%agenda-cliente%') = 2,
    md5(pg_temp.sem_pedido(pg_temp.src(c_tra))) || ' ' || pg_temp.porta(c_tra));
  v_res := pg_temp.ok(v_res, 'P0e _agenda_cliente_no_periodo: tirado o bloco "-- PEDIDO A-5 (F5):", é o corpo de produção de 13/11 (20261028100200, md5 d99e071a…); SQL, invoker, STABLE, ninguém executa',
    md5(pg_temp.sem_pedido(pg_temp.src(c_per))) = 'd99e071a323385c9b46f468b7a93eaff' and md5(pg_temp.src(c_per)) <> 'd99e071a323385c9b46f468b7a93eaff'
    and (select count(*) from regexp_matches(pg_temp.src(c_per), '-- PEDIDO A-5 \(F5\): fim', 'g')) = 1
    and pg_temp.porta(c_per) = 'f s | f f f f'
    and (select l.lanname = 'sql' from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = to_regprocedure(c_per)),
    md5(pg_temp.sem_pedido(pg_temp.src(c_per))) || ' ' || pg_temp.porta(c_per));
  select count(*) into v_n
    from unnest(array[c_esp, c_ret, c_enf, c_tra, c_per]) a(f), pg_temp.sem_where(pg_temp.src(a.f)) s;
  v_res := pg_temp.ok(v_res, 'P0f nenhum UPDATE/DELETE sem WHERE no nível de cima das 5 (o pg_safeupdate do PostgREST recusaria); o detector acusa um sem WHERE (controle)',
    v_n = 0 and (select count(*) from pg_temp.sem_where('begin delete from x; update y set a = 1 where b; end')) = 1,
    (select string_agg(s, ' | ') from unnest(array[c_esp, c_ret, c_enf, c_tra, c_per]) a(f), pg_temp.sem_where(pg_temp.src(a.f)) s));
  perform pg_temp.gravar(v_res);
end
$p0$;

-- ── R0. Sem a tabela do retorno, a agenda fica como antes; na bancada, a tabela de teste ───────────────────────────────────────────────
do $r0$
declare
  v_res jsonb := '[]'::jsonb;
begin
  if to_regclass('public.retorno_saidas') is not null then
    insert into _resultado values ('R0 sem retorno_saidas', true, 'PULADO: a tabela do retorno existe (produção ou a bancada do retorno)');
    return;
  end if;
  v_res := pg_temp.ok(v_res, 'R0a sem retorno_saidas (a bancada da agenda): _agenda_cliente_orcamento_espera devolve null e _agenda_cliente_retorno_no_periodo 0; o total do dia é só o da agenda',
    public._agenda_cliente_orcamento_espera('c1000000-0000-4000-8000-000000000004', 'confirmar', date '2026-10-30', pg_temp.em('2026-10-30 10:00')) is null
    and public._agenda_cliente_retorno_no_periodo(date '2026-10-30', date '2026-10-30') = 0
    and public._agenda_cliente_no_periodo(null, date '2026-10-30', date '2026-10-30', null)
        = (select count(*)::int from public.agenda_cliente_mensagens m where m.modo = 'ligado'
             and m.estado in ('enfileirada', 'enviada', 'respondida', 'sem_resposta')
             and (m.enviar_em at time zone 'America/Sao_Paulo')::date = date '2026-10-30'),
    null);
  -- A tabela de teste: as colunas de retorno_saidas (20261116100100) que as 2 novas leem e as que o insert do teste precisa, com os CHECKs de emissor,
  -- classe e estado da F5 (20270112100000) e o de enviada_em. Some no rollback. Com a tabela de verdade, o mesmo insert vale (as colunas NOT NULL dela).
  create table public.retorno_saidas (
    id               uuid primary key default gen_random_uuid(),
    emissor          text not null default 'retorno' check (emissor in ('retorno', 'fila', 'parceiro', 'orcamento')),
    tipo             text not null,
    origem           text,
    classe           text check (classe in ('resposta_imediata', 'resposta_atrasada', 'aviso', 'resumo_parceiro', 'comercial')),
    chave            text not null check (chave ~ '^[0-9]{8}$'),
    phone_normalized text not null,
    client_id        uuid references public.clients(id) on delete set null,
    modo             text not null check (modo in ('sombra', 'ligado')),
    estado           text not null default 'agendada' check (estado in ('agendada', 'preparada', 'enviando', 'sombra', 'enviada', 'incerta',
                                                                         'recusada', 'cancelada', 'contada')),
    motivo           text,
    enviar_em        timestamptz not null,
    decidida_em      timestamptz,
    enviada_em       timestamptz,
    texto            text,
    dados            jsonb not null default '{}',
    dedupe_key       text not null unique,
    criada_em        timestamptz not null default now(),
    constraint retorno_saidas_enviada check ((estado = 'enviada') = (enviada_em is not null))
  );
  v_res := pg_temp.ok(v_res, 'R0b a tabela de teste existe (só neste teste; some no rollback)', to_regclass('public.retorno_saidas') is not null, null);
  perform pg_temp.gravar(v_res);
end
$r0$;

-- ── A, B e M. A agenda e as saídas do orçamento (a fixture-fase5; sex 30/10/2026) ──────────────────────────────────────────────────────

-- Liga a mensagem ao cliente (todos os tipos) com a aprovação dos primeiros dias (0: livre; 3: o OK do dono é pedido) e a conversa viva desligada
-- (para isolar o pedido: ela tem a sua prova).
create function pg_temp.ligar(p_aprov int default 0) returns void language sql as $f$
  update public.agenda_config
     set modo_cliente = 'ligado', cliente_aprovacao_dias = p_aprov, cliente_conversa_viva_min = 0,
         cliente_tipos_ligados = array['confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento', 'pode_atrasar', 'nova_data',
                                       'pronto', 'pronto_lembrete', 'pos_servico', 'mudanca_no_dia']
   where id
$f$;
create function pg_temp.msg(p_id uuid) returns public.agenda_cliente_mensagens language sql stable as $f$
  select m.* from public.agenda_cliente_mensagens m where m.id = p_id
$f$;
-- Uma saída do retorno ao cliente (p_em = a hora da decisão e, na enviada, a do envio). A chave e o telefone são os do teste.
create function pg_temp.saida(p_cliente uuid, p_emissor text, p_tipo text, p_classe text, p_estado text, p_em timestamptz, p_modo text default 'ligado')
returns uuid language plpgsql as $f$
declare
  v uuid;
begin
  execute $i$
    insert into public.retorno_saidas (emissor, tipo, origem, classe, chave, phone_normalized, client_id, modo, estado, motivo, enviar_em, decidida_em,
                                       enviada_em, texto, dedupe_key)
    values ($1, $2, case when $1 = 'orcamento' then 'retorno_orcamento' end, $3, '90000304', '5547990000304', $4, $5, $6,
            case when $6 in ('recusada', 'cancelada') then 'canal' end, $7, $7, case when $6 = 'enviada' then $7 end,
            'Mensagem do retorno (teste)', 'teste-a1a3:' || gen_random_uuid())
    returning id $i$
  into v using p_emissor, p_tipo, p_classe, p_cliente, p_modo, p_estado, p_em;
  return v;
end $f$;
-- A confirmação do Flávio (ter 03/11), pela rodada: sai p_alvo, vale até p_valida (null = o fim da janela do dia do envio).
create function pg_temp.confirmar_flavio(p_alvo timestamptz, p_valida timestamptz, p_agora timestamptz, p_chave text default null) returns uuid
language plpgsql as $f$
declare
  r jsonb;
begin
  perform set_config('agenda_teste.hoje', to_char(p_agora at time zone 'America/Sao_Paulo', 'YYYY-MM-DD'), true);
  r := public._agenda_cliente_registrar('confirmar', null, '05000000-0000-4000-8000-000000000104', date '2026-11-03',
                                        case when p_chave is null then '{}'::jsonb else jsonb_build_object('chave', p_chave) end,
                                        p_alvo, p_valida, 'rodada', null, p_agora);
  return (r ->> 'id')::uuid;
end $f$;
-- A linha da fila desta mensagem, como o enfileirar a poria (o telefone dele, ou o de teste), direto: o que a 2ª trava diz ('entrou' ou o detail do 23514).
create function pg_temp.na_fila(p_msg uuid) returns text language plpgsql as $f$
declare
  m public.agenda_cliente_mensagens;
  v_fone text;
  v_det text;
begin
  select x.* into m from public.agenda_cliente_mensagens x where x.id = p_msg;
  v_fone := public._agenda_cliente_telefone(m.client_id);
  if coalesce((select x.value::text from public.app_settings x where x.key = 'wa_test_mode'), 'false') in ('true', '"true"') then
    v_fone := nullif(regexp_replace(coalesce((select x.value::text from public.app_settings x where x.key = 'wa_test_number'), ''), '\D', '', 'g'), '');
  end if;
  begin
    insert into public.whatsapp_send_queue (phone_normalized, message, source, source_ref_id, priority, scheduled_for, max_attempts, dedupe_key)
    values (v_fone, m.texto, 'agenda-cliente', m.id, 5, m.enviar_em, 1, m.dedupe_key);
    return 'entrou';
  exception when sqlstate '23514' then
    get stacked diagnostics v_det = pg_exception_detail;
    return v_det;
  end;
end $f$;

do $a$
declare
  v_res  jsonb := '[]'::jsonb;
  c_flav constant uuid := '05000000-0000-4000-8000-000000000104';
  c_cli  constant uuid := 'c1000000-0000-4000-8000-000000000004';   -- Flávio
  c_nel  constant uuid := 'c1000000-0000-4000-8000-000000000005';   -- Nelson (o outro cliente)
  c_dono constant uuid := 'aa000000-0000-4000-8000-000000000001';
  r      jsonb;
  m      public.agenda_cliente_mensagens;
  v_m    uuid;
  v_m2   uuid;
  v_ok   boolean;
  v_n0   int;
  v_n1   int;
  t      text;
  x      jsonb;
begin
  if coalesce(current_setting('agenda_teste.fase5', true), '') = '' or to_regclass('public.retorno_saidas') is null then
    insert into _resultado values ('A1–A5, B1, M (fixture-fase5)', true, 'PULADO: sem agenda_teste.fase5 ou sem a tabela de teste (rode pela bancada)');
    return;
  end if;
  begin
  execute current_setting('agenda_teste.fase5');

  -- ── A1a/A1b. A-1: a confirmação espera o dia seguinte e sai nele ──
  begin
    perform pg_temp.ligar(0);
    perform pg_temp.saida(c_cli, 'orcamento', 'orc_lembrete', 'comercial', 'enviada', pg_temp.em('2026-10-30 09:00'));
    v_m := pg_temp.confirmar_flavio(pg_temp.em('2026-10-30 10:00'), public._agenda_cliente_fim_da_janela(date '2026-10-30', 1), pg_temp.em('2026-10-30 09:30'));
    m := pg_temp.msg(v_m);
    t := format('nasceu %s/%s/%s, vale até %s', m.estado, m.aprovacao, m.modo, pg_temp.br(m.valida_ate));
    r := public._agenda_cliente_enfileirar(v_m, pg_temp.em('2026-10-30 10:00'));
    m := pg_temp.msg(v_m);
    v_res := pg_temp.ok(v_res, 'A1a o lembrete do orçamento já foi ao Flávio às 09:00: a confirmação (livre, vale até sáb 31/10) espera o dia seguinte — registrada, sáb 31/10 08:00, motivo orcamento_hoje; nada na fila, nada recusado',
      r ->> 'estado' = 'registrada' and r ->> 'motivo' = 'orcamento_hoje' and m.estado = 'registrada' and m.recusa_motivo is null
      and pg_temp.br(m.enviar_em) like '2026-10-31 08:0%' and (r ->> 'enviar_em')::timestamptz = m.enviar_em and m.fila_id is null
      and not exists (select 1 from public.whatsapp_send_queue q where q.source_ref_id = v_m),
      format('%s; %s; agora %s/%s sai %s', t, r, m.estado, coalesce(m.recusa_motivo, '-'), pg_temp.br(m.enviar_em)));
    r := public._agenda_cliente_enfileirar(v_m, m.enviar_em);
    m := pg_temp.msg(v_m);
    v_res := pg_temp.ok(v_res, 'A1b no sábado ela sai: enfileirada na hora nova (a linha da fila com scheduled_for = enviar_em)',
      r ->> 'estado' = 'enfileirada' and m.estado = 'enfileirada'
      and exists (select 1 from public.whatsapp_send_queue q where q.id = m.fila_id and q.scheduled_for = m.enviar_em and q.source = 'agenda-cliente'),
      format('%s; %s', r, m.estado));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A1c. A que vale só na sexta não tem como esperar: o teto do dia ──
  begin
    perform pg_temp.ligar(0);
    perform pg_temp.saida(c_cli, 'orcamento', 'orc_lembrete', 'comercial', 'enviada', pg_temp.em('2026-10-30 09:00'));
    v_m := pg_temp.confirmar_flavio(pg_temp.em('2026-10-30 10:00'), null, pg_temp.em('2026-10-30 09:30'));
    t := pg_temp.br((pg_temp.msg(v_m)).valida_ate);
    r := public._agenda_cliente_enfileirar(v_m, pg_temp.em('2026-10-30 10:00'));
    m := pg_temp.msg(v_m);
    v_res := pg_temp.ok(v_res, 'A1c a confirmação que vale só na sexta (até 19:00) não tem como esperar o sábado: fica recusada pelo teto do dia (teto_dia), nada na fila',
      t = '2026-10-30 19:00' and r ->> 'estado' = 'recusada' and r ->> 'motivo' = 'teto_dia' and m.estado = 'recusada' and m.recusa_motivo = 'teto_dia'
      and not exists (select 1 from public.whatsapp_send_queue q where q.source_ref_id = v_m),
      format('vale até %s; %s', t, r));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A1d. O aviso de atraso que não pode esperar vira a pergunta crítica ao dono (d13) ──
  begin
    perform pg_temp.ligar(0);
    perform public._agenda_cliente_gravar_prometido(c_flav, 'firme', date '2026-11-03', date '2026-11-03', 'dono', null,
                                                    pg_temp.em('2026-10-29 10:00'), 'teste A1d');
    x := public._agenda_cliente_risco(c_flav, date '2026-10-30');
    perform pg_temp.saida(c_cli, 'orcamento', 'orc_lembrete', 'comercial', 'enviada', pg_temp.em('2026-10-30 09:00'));
    perform set_config('agenda_teste.hoje', '2026-10-30', true);
    r := public._agenda_cliente_registrar('pode_atrasar', x ->> 'variante', c_flav, (x ->> 'faixa_de')::date,
           jsonb_build_object('prometido_tipo', 'firme', 'dito_de', x -> 'dito_de', 'dito_ate', x -> 'dito_ate',
                              'forma', 'fim', 'dia', x -> 'faixa_de', 'fim', x -> 'faixa_ate'),
           pg_temp.em('2026-10-30 10:00'), pg_temp.em('2026-10-30 19:00'), 'rodada', null, pg_temp.em('2026-10-30 10:00'));
    m := pg_temp.msg((r ->> 'id')::uuid);
    v_res := pg_temp.ok(v_res, 'A1d o aviso de atraso registrado depois do lembrete do orçamento, que vale só hoje: não fica mudo — vira a pergunta crítica cliente_aviso ao dono ("Recomendo você ligar", contando a mensagem do orçamento na semana); nada na fila',
      m.estado = 'aguardando_dono' and m.aprovacao = 'critica' and r ->> 'motivo' = 'teto_dia'
      and exists (select 1 from public.agenda_perguntas q where q.id = m.pergunta_id and q.tipo = 'cliente_aviso' and q.estado = 'aberta'
                    and q.texto like '%não cabe:%já recebeu 1 mensagem esta semana. Recomendo você ligar.%')
      and not exists (select 1 from public.whatsapp_send_queue q where q.source_ref_id = m.id),
      format('%s; %s/%s; %s', r, m.estado, m.aprovacao, (select q.texto from public.agenda_perguntas q where q.id = m.pergunta_id)));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A1e. Sem saída do orçamento hoje (a de ontem): a de antes ──
  begin
    perform pg_temp.ligar(0);
    perform pg_temp.saida(c_cli, 'orcamento', 'orc_lembrete', 'comercial', 'enviada', pg_temp.em('2026-10-29 16:00'));
    v_m := pg_temp.confirmar_flavio(pg_temp.em('2026-10-30 10:00'), public._agenda_cliente_fim_da_janela(date '2026-10-30', 1), pg_temp.em('2026-10-30 09:30'));
    r := public._agenda_cliente_enfileirar(v_m, pg_temp.em('2026-10-30 10:00'));
    m := pg_temp.msg(v_m);
    v_res := pg_temp.ok(v_res, 'A1e o lembrete do orçamento foi ontem (qui 29/10): a confirmação sai hoje, como antes (enfileirada às 10:00)',
      r ->> 'estado' = 'enfileirada' and pg_temp.br(m.enviar_em) = '2026-10-30 10:00', format('%s; sai %s', r, pg_temp.br(m.enviar_em)));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A1f/A1g. O que não conta, e o que conta como a F5 conta ──
  begin
    perform pg_temp.ligar(0);
    perform pg_temp.saida(c_cli, 'orcamento', 'orc_lembrete', 'comercial', 'sombra', pg_temp.em('2026-10-30 09:00'), 'sombra');
    perform pg_temp.saida(c_cli, 'orcamento', 'orc_lembrete', 'comercial', 'preparada', pg_temp.em('2026-10-30 09:01'), 'sombra');
    perform pg_temp.saida(c_cli, 'orcamento', 'orc_vespera', 'comercial', 'agendada', pg_temp.em('2026-10-30 09:02'));
    perform pg_temp.saida(c_cli, 'orcamento', 'orc_lembrete', 'comercial', 'recusada', pg_temp.em('2026-10-30 09:03'));
    perform pg_temp.saida(c_cli, 'orcamento', 'orc_encerramento', 'comercial', 'cancelada', pg_temp.em('2026-10-30 09:04'));
    perform pg_temp.saida(c_cli, 'retorno', 'recibo_cliente', 'resposta_imediata', 'enviada', pg_temp.em('2026-10-30 09:05'));
    perform pg_temp.saida(c_cli, 'parceiro', 'parceiro_aviso_cliente', 'aviso', 'enviada', pg_temp.em('2026-10-30 09:06'));
    perform pg_temp.saida(c_nel, 'orcamento', 'orc_lembrete', 'comercial', 'enviada', pg_temp.em('2026-10-30 09:07'));
    perform pg_temp.saida(c_cli, 'orcamento', 'orc_lembrete', 'comercial', 'enviada', pg_temp.em('2026-10-30 10:30'));
    v_ok := public._agenda_cliente_orcamento_espera(c_cli, 'confirmar', date '2026-10-30', pg_temp.em('2026-10-30 10:00')) is null;
    v_m := pg_temp.confirmar_flavio(pg_temp.em('2026-10-30 10:00'), public._agenda_cliente_fim_da_janela(date '2026-10-30', 1), pg_temp.em('2026-10-30 09:30'));
    r := public._agenda_cliente_enfileirar(v_m, pg_temp.em('2026-10-30 10:00'));
    v_res := pg_temp.ok(v_res, 'A1f não conta: a do orçamento em sombra, preparada, agendada, recusada ou cancelada; a de outro emissor (o recibo, o aviso da F4); a do orçamento a outro cliente; a enviada depois de agora (10:30) — a confirmação sai às 10:00',
      v_ok and r ->> 'estado' = 'enfileirada', format('espera %s; %s', v_ok, r));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.saida(c_cli, 'orcamento', 'orc_lembrete', 'comercial', 'incerta', pg_temp.em('2026-10-30 10:10'));
    perform pg_temp.saida(c_nel, 'orcamento', 'orc_encerramento', 'comercial', 'enviando', pg_temp.em('2026-10-30 10:12'));
    v_res := pg_temp.ok(v_res, 'A1g conta como a F5 conta: a do orçamento incerta (ao Flávio, 10:10) ou enviando (ao Nelson, 10:12) segura dali em diante (orcamento_hoje, sáb 31/10); antes da hora dela, não',
      public._agenda_cliente_orcamento_espera(c_cli, 'vespera', date '2026-10-30', pg_temp.em('2026-10-30 10:05')) is null
      and public._agenda_cliente_orcamento_espera(c_cli, 'vespera', date '2026-10-30', pg_temp.em('2026-10-30 10:15'))
          = jsonb_build_object('dia', '2026-10-31', 'motivo', 'orcamento_hoje')
      and public._agenda_cliente_orcamento_espera(c_nel, 'vespera', date '2026-10-30', pg_temp.em('2026-10-30 10:11')) is null
      and public._agenda_cliente_orcamento_espera(c_nel, 'confirmar', date '2026-10-30', pg_temp.em('2026-10-30 10:15'))
          = jsonb_build_object('dia', '2026-10-31', 'motivo', 'orcamento_hoje'),
      null);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A1h. O passo fila de ponta a ponta ──
  begin
    perform pg_temp.ligar(0);
    perform pg_temp.saida(c_cli, 'orcamento', 'orc_lembrete', 'comercial', 'enviada', pg_temp.em('2026-10-30 09:00'));
    v_m := pg_temp.confirmar_flavio(pg_temp.em('2026-10-30 10:00'), public._agenda_cliente_fim_da_janela(date '2026-10-30', 1), pg_temp.em('2026-10-30 09:30'));
    r := public._agenda_cliente_fila(date '2026-10-30', pg_temp.em('2026-10-30 10:00'));
    m := pg_temp.msg(v_m);
    t := format('sex: %s, %s sai %s', r, m.estado, pg_temp.br(m.enviar_em));
    v_ok := m.estado = 'registrada' and pg_temp.br(m.enviar_em) like '2026-10-31 08:0%' and (r ->> 'esperando')::int >= 1;
    r := public._agenda_cliente_fila(date '2026-10-31', m.enviar_em);
    m := pg_temp.msg(v_m);
    v_res := pg_temp.ok(v_res, 'A1h o passo fila de ponta a ponta: na sexta 10:00 a confirmação fica esperando (sáb 31/10 08:00); no tique de sábado vai à fila',
      v_ok and m.estado = 'enfileirada' and (r ->> 'enfileiradas')::int >= 1, format('%s; sáb: %s, %s', t, r, m.estado));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A1i. O *manda cliente* do dono no dia do orçamento responde a hora nova ──
  begin
    perform pg_temp.ligar(3);
    perform pg_temp.saida(c_cli, 'orcamento', 'orc_lembrete', 'comercial', 'enviada', pg_temp.em('2026-10-30 09:00'));
    v_m := pg_temp.confirmar_flavio(pg_temp.em('2026-10-30 10:00'), public._agenda_cliente_fim_da_janela(date '2026-10-30', 1), pg_temp.em('2026-10-30 09:30'));
    m := pg_temp.msg(v_m);
    t := m.estado || '/' || m.aprovacao;
    r := public.agenda_cliente_decidir_dito(c_dono, 'manda', 'Flávio', 'whatsapp', date '2026-10-30', pg_temp.em('2026-10-30 10:00'));
    m := pg_temp.msg(v_m);
    v_res := pg_temp.ok(v_res, 'A1i a confirmação pedida ao dono, e o *manda cliente Flávio* às 10:00 depois do lembrete do orçamento: aprovada, espera sábado, e a resposta diz quando sai (não "agora")',
      t = 'aguardando_dono/pedida' and m.aprovacao = 'aprovada' and m.estado in ('registrada', 'aguardando_dono') and pg_temp.br(m.enviar_em) like '2026-10-31 08:0%'
      and coalesce(r ->> 'texto', '') like 'Mando para Flávio %' and coalesce(r ->> 'texto', '') not like '%agora%'
      and not exists (select 1 from public.whatsapp_send_queue q where q.source_ref_id = v_m),
      format('%s → %s/%s sai %s; %s', t, m.estado, m.aprovacao, pg_temp.br(m.enviar_em), coalesce(r ->> 'texto', r::text)));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A3a. A-3: o "Fechado" de sexta; a confirmação de sábado espera ter 03/11 ──
  begin
    perform pg_temp.ligar(0);
    perform pg_temp.saida(c_cli, 'orcamento', 'orc_fechado', 'resposta_imediata', 'enviada', pg_temp.em('2026-10-30 15:00'));
    v_m := pg_temp.confirmar_flavio(pg_temp.em('2026-10-31 09:00'), public._agenda_cliente_fim_da_janela(date '2026-10-31', 1), pg_temp.em('2026-10-30 16:00'));
    m := pg_temp.msg(v_m);
    t := format('nasceu %s, sai %s, vale até %s', m.estado, pg_temp.br(m.enviar_em), pg_temp.br(m.valida_ate));
    r := public._agenda_cliente_enfileirar(v_m, pg_temp.em('2026-10-31 09:00'));
    m := pg_temp.msg(v_m);
    v_res := pg_temp.ok(v_res, 'A3a o "Fechado" saiu sex 30/10 15:00: a confirmação de sáb 31/10 espera o dia útil seguinte — ter 03/11 08:00 (sábado, domingo e Finados fora), motivo orcamento_fechado; nada na fila',
      r ->> 'estado' = 'registrada' and r ->> 'motivo' = 'orcamento_fechado' and m.estado = 'registrada' and m.recusa_motivo is null
      and pg_temp.br(m.enviar_em) like '2026-11-03 08:0%' and not exists (select 1 from public.whatsapp_send_queue q where q.source_ref_id = v_m),
      format('%s; %s; agora sai %s', t, r, pg_temp.br(m.enviar_em)));
    v_res := pg_temp.ok(v_res, 'A3b a véspera do mesmo sábado não espera (o A-3 é só da confirmação; o "Fechado" foi ontem, não hoje)',
      public._agenda_cliente_orcamento_espera(c_cli, 'vespera', date '2026-10-31', pg_temp.em('2026-10-31 09:00')) is null
      and public._agenda_cliente_orcamento_espera(c_cli, 'confirmar', date '2026-10-31', pg_temp.em('2026-10-31 09:00'))
          = jsonb_build_object('dia', '2026-11-03', 'motivo', 'orcamento_fechado'),
      null);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A3c. A confirmação de sábado que vale só no sábado: recusada ──
  begin
    perform pg_temp.ligar(0);
    perform pg_temp.saida(c_cli, 'orcamento', 'orc_fechado', 'resposta_imediata', 'enviada', pg_temp.em('2026-10-30 15:00'));
    v_m := pg_temp.confirmar_flavio(pg_temp.em('2026-10-31 09:00'), null, pg_temp.em('2026-10-30 16:00'));
    r := public._agenda_cliente_enfileirar(v_m, pg_temp.em('2026-10-31 09:00'));
    m := pg_temp.msg(v_m);
    v_res := pg_temp.ok(v_res, 'A3c a confirmação de sábado que vale só no sábado (até 13:00) não tem como esperar ter 03/11: recusada (teto_dia), nada na fila',
      r ->> 'estado' = 'recusada' and m.recusa_motivo = 'teto_dia' and not exists (select 1 from public.whatsapp_send_queue q where q.source_ref_id = v_m),
      r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A3d–A3f. O "Fechado" de hoje leva ao dia útil; o antigo não segura; o sábado útil ──
  begin
    perform pg_temp.ligar(0);
    perform pg_temp.saida(c_cli, 'orcamento', 'orc_fechado', 'resposta_imediata', 'enviada', pg_temp.em('2026-10-30 09:00'));
    v_m := pg_temp.confirmar_flavio(pg_temp.em('2026-10-30 10:00'), public._agenda_cliente_fim_da_janela(date '2026-10-30', 2), pg_temp.em('2026-10-30 09:30'));
    r := public._agenda_cliente_enfileirar(v_m, pg_temp.em('2026-10-30 10:00'));
    m := pg_temp.msg(v_m);
    v_res := pg_temp.ok(v_res, 'A3d o "Fechado" saiu hoje às 09:00: a confirmação de hoje espera o dia útil (ter 03/11, motivo orcamento_fechado), não o sábado; outra mensagem (a véspera) só o dia seguinte (sáb 31/10, orcamento_hoje)',
      r ->> 'motivo' = 'orcamento_fechado' and pg_temp.br(m.enviar_em) like '2026-11-03 08:0%'
      and public._agenda_cliente_orcamento_espera(c_cli, 'vespera', date '2026-10-30', pg_temp.em('2026-10-30 10:00'))
          = jsonb_build_object('dia', '2026-10-31', 'motivo', 'orcamento_hoje'),
      format('%s; sai %s', r, pg_temp.br(m.enviar_em)));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.saida(c_cli, 'orcamento', 'orc_fechado', 'resposta_imediata', 'enviada', pg_temp.em('2026-10-27 15:00'));
    v_ok := public._agenda_cliente_orcamento_espera(c_cli, 'confirmar', date '2026-10-30', pg_temp.em('2026-10-30 10:00')) is null
            and public._agenda_cliente_orcamento_espera(c_cli, 'confirmar', date '2026-10-28', pg_temp.em('2026-10-28 10:00')) is null
            and public._agenda_cliente_orcamento_espera(c_cli, 'confirmar', date '2026-10-27', pg_temp.em('2026-10-27 16:00'))
                = jsonb_build_object('dia', '2026-10-28', 'motivo', 'orcamento_fechado');
    v_res := pg_temp.ok(v_res, 'A3e o "Fechado" de ter 27/10 segura a confirmação só até qua 28/10 (o dia útil seguinte); na sexta não segura mais', v_ok, null);
    perform pg_temp.saida(c_cli, 'orcamento', 'orc_fechado', 'resposta_imediata', 'enviada', pg_temp.em('2026-10-30 15:00'));
    update public.agenda_config set sabado_util = true where id;
    v_res := pg_temp.ok(v_res, 'A3f o dia útil é o da agenda (agenda_somar_du): com sábado útil, o "Fechado" de sexta segura a confirmação só até sábado',
      public._agenda_cliente_orcamento_espera(c_cli, 'confirmar', date '2026-10-31', pg_temp.em('2026-10-31 09:00')) is null
      and public._agenda_cliente_orcamento_espera(c_cli, 'confirmar', date '2026-10-30', pg_temp.em('2026-10-30 16:00'))
          = jsonb_build_object('dia', '2026-10-31', 'motivo', 'orcamento_fechado'),
      null);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A5. O teto do dia a todos soma as iniciadas do retorno ──
  begin
    perform pg_temp.ligar(0);
    update public.agenda_config set cliente_total_dia_max = 2 where id;
    v_n0 := public._agenda_cliente_no_periodo(null, date '2026-10-30', date '2026-10-30', null);
    -- o que não conta
    perform pg_temp.saida(c_nel, 'retorno', 'recibo_cliente', 'resposta_imediata', 'enviada', pg_temp.em('2026-10-30 08:10'));
    perform pg_temp.saida(c_nel, 'retorno', 'adiamento', 'resposta_atrasada', 'enviada', pg_temp.em('2026-10-30 08:11'));
    perform pg_temp.saida(c_nel, 'orcamento', 'orc_lembrete', 'comercial', 'sombra', pg_temp.em('2026-10-30 08:12'), 'sombra');
    perform pg_temp.saida(c_nel, 'parceiro', 'parceiro_aviso_cliente', 'aviso', 'agendada', pg_temp.em('2026-10-30 08:13'));
    perform pg_temp.saida(c_nel, 'parceiro', 'parceiro_aviso_cliente', 'aviso', 'cancelada', pg_temp.em('2026-10-30 08:14'));
    perform pg_temp.saida(c_nel, 'orcamento', 'orc_lembrete', 'comercial', 'enviada', pg_temp.em('2026-10-29 16:00'));
    v_n1 := public._agenda_cliente_no_periodo(null, date '2026-10-30', date '2026-10-30', null);
    v_ok := v_n1 = v_n0;
    -- o que conta: 1 aviso enviado e 1 comercial incerta, hoje, ao Nelson
    perform pg_temp.saida(c_nel, 'parceiro', 'parceiro_aviso_cliente', 'aviso', 'enviada', pg_temp.em('2026-10-30 08:20'));
    v_res := pg_temp.ok(v_res, 'A5a o que não conta no teto: resposta imediata ou atrasada, sombra, agendada, cancelada, a de ontem; 1 aviso enviado hoje conta 1 (o resumo_parceiro e o comercial, abaixo)',
      v_ok and public._agenda_cliente_no_periodo(null, date '2026-10-30', date '2026-10-30', null) = v_n0 + 1
      and public._agenda_cliente_retorno_no_periodo(date '2026-10-30', date '2026-10-30') = 1
      and public._agenda_cliente_retorno_no_periodo(date '2026-10-29', date '2026-10-30') = 2,
      format('antes %s, com os que não contam %s, com o aviso %s', v_n0, v_n1, public._agenda_cliente_no_periodo(null, date '2026-10-30', date '2026-10-30', null)));
    v_m := pg_temp.confirmar_flavio(pg_temp.em('2026-10-30 10:00'), null, pg_temp.em('2026-10-30 09:30'));
    v_m2 := pg_temp.confirmar_flavio(pg_temp.em('2026-10-30 10:00'), null, pg_temp.em('2026-10-30 09:30'), 'a5:trava');
    t := pg_temp.na_fila(v_m2);
    perform pg_temp.saida(c_nel, 'orcamento', 'orc_lembrete', 'comercial', 'incerta', pg_temp.em('2026-10-30 09:40'));
    r := public._agenda_cliente_enfileirar(v_m, pg_temp.em('2026-10-30 10:00'));
    v_res := pg_temp.ok(v_res, 'A5b com o total de 2 por dia e 2 iniciadas do retorno de hoje (ao Nelson: um aviso e um lembrete do orçamento), a confirmação do Flávio fica recusada (teto_total); com 1, ela entrava',
      v_n0 = 0 and t = 'entrou' and r ->> 'estado' = 'recusada' and r ->> 'motivo' = 'teto_total' and (pg_temp.msg(v_m)).recusa_motivo = 'teto_total',
      format('antes %s; com 1: %s; com 2: %s', v_n0, t, r));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.ligar(0);
    update public.agenda_config set cliente_total_dia_max = 2 where id;
    perform pg_temp.saida(c_nel, 'parceiro', 'parceiro_painel', 'resumo_parceiro', 'enviada', pg_temp.em('2026-10-30 08:20'));
    perform pg_temp.saida(c_nel, 'orcamento', 'orc_lembrete', 'comercial', 'enviando', pg_temp.em('2026-10-30 09:40'));
    v_m := pg_temp.confirmar_flavio(pg_temp.em('2026-10-30 10:00'), null, pg_temp.em('2026-10-30 09:30'));
    v_res := pg_temp.ok(v_res, 'A5c a 2ª trava (o gatilho da fila) conta igual: com o resumo ao parceiro e o lembrete enviando, a linha direta da fila é recusada com 23514 teto_total; por cliente, a conta não muda (as do retorno não entram)',
      pg_temp.na_fila(v_m) = 'teto_total'
      and public._agenda_cliente_no_periodo(c_nel, date '2026-10-30', date '2026-10-30', null)
          = (select count(*)::int from public.agenda_cliente_mensagens x where x.modo = 'ligado' and x.client_id = c_nel
               and x.estado in ('enfileirada', 'enviada', 'respondida', 'sem_resposta') and (x.enviar_em at time zone 'America/Sao_Paulo')::date = date '2026-10-30'),
      pg_temp.na_fila(v_m));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── B1. A 2ª trava: a mesma regra do A-1 ──
  begin
    perform pg_temp.ligar(0);
    v_m := pg_temp.confirmar_flavio(pg_temp.em('2026-10-30 10:00'), null, pg_temp.em('2026-10-30 09:30'));
    v_m2 := pg_temp.confirmar_flavio(pg_temp.em('2026-10-30 10:00'), null, pg_temp.em('2026-10-30 09:30'), 'b1:depois');
    t := pg_temp.na_fila(v_m);
    perform pg_temp.saida(c_cli, 'orcamento', 'orc_lembrete', 'comercial', 'enviada', pg_temp.em('2026-10-30 09:00'));
    v_res := pg_temp.ok(v_res, 'B1 a 2ª trava: sem a saída do orçamento a linha direta entra; com o lembrete enviado hoje ao Flávio, a outra é recusada com 23514 teto_dia',
      t = 'entrou' and pg_temp.na_fila(v_m2) = 'teto_dia', t || ' / ' || pg_temp.na_fila(v_m2));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── M. Sem os pedidos (as 3 recriadas sem os blocos, numa subtransação): as mesmas cenas mandam no mesmo dia (o teste morde) ──
  begin
    execute format('create or replace function public._agenda_cliente_enfileirar(p_msg uuid, p_agora timestamptz default now()) returns jsonb language plpgsql volatile security definer set search_path to ''public'' as %L',
                   pg_temp.sem_pedido(pg_temp.src('public._agenda_cliente_enfileirar(uuid, timestamptz)')));
    execute format('create or replace function public._agenda_fila_do_cliente() returns trigger language plpgsql security definer set search_path to ''public'' as %L',
                   pg_temp.sem_pedido(pg_temp.src('public._agenda_fila_do_cliente()')));
    execute format('create or replace function public._agenda_cliente_no_periodo(p_cliente uuid, p_de date, p_ate date, p_exceto uuid) returns integer language sql stable set search_path to ''public'' as %L',
                   pg_temp.sem_pedido(pg_temp.src('public._agenda_cliente_no_periodo(uuid, date, date, uuid)')));
    -- M1 = A1a
    begin
      perform pg_temp.ligar(0);
      perform pg_temp.saida(c_cli, 'orcamento', 'orc_lembrete', 'comercial', 'enviada', pg_temp.em('2026-10-30 09:00'));
      v_m := pg_temp.confirmar_flavio(pg_temp.em('2026-10-30 10:00'), public._agenda_cliente_fim_da_janela(date '2026-10-30', 1), pg_temp.em('2026-10-30 09:30'));
      r := public._agenda_cliente_enfileirar(v_m, pg_temp.em('2026-10-30 10:00'));
      v_res := pg_temp.ok(v_res, 'M1 sem o A-1 (o enfileirar de 20261028100800): com o lembrete do orçamento enviado às 09:00, a confirmação vai à fila na mesma sexta às 10:00 (duas mensagens no dia; o A1a morde)',
        r ->> 'estado' = 'enfileirada' and pg_temp.br((pg_temp.msg(v_m)).enviar_em) = '2026-10-30 10:00', r::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    -- M2 = A3a
    begin
      perform pg_temp.ligar(0);
      perform pg_temp.saida(c_cli, 'orcamento', 'orc_fechado', 'resposta_imediata', 'enviada', pg_temp.em('2026-10-30 15:00'));
      v_m := pg_temp.confirmar_flavio(pg_temp.em('2026-10-31 09:00'), public._agenda_cliente_fim_da_janela(date '2026-10-31', 1), pg_temp.em('2026-10-30 16:00'));
      r := public._agenda_cliente_enfileirar(v_m, pg_temp.em('2026-10-31 09:00'));
      v_res := pg_temp.ok(v_res, 'M2 sem o A-3: com o "Fechado" de sexta, a confirmação vai à fila no sábado (o A3a morde)',
        r ->> 'estado' = 'enfileirada' and pg_temp.br((pg_temp.msg(v_m)).enviar_em) like '2026-10-31 09:0%', r::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    -- M3 = A5b
    begin
      perform pg_temp.ligar(0);
      update public.agenda_config set cliente_total_dia_max = 2 where id;
      perform pg_temp.saida(c_nel, 'parceiro', 'parceiro_aviso_cliente', 'aviso', 'enviada', pg_temp.em('2026-10-30 08:20'));
      perform pg_temp.saida(c_nel, 'orcamento', 'orc_lembrete', 'comercial', 'incerta', pg_temp.em('2026-10-30 09:40'));
      v_m := pg_temp.confirmar_flavio(pg_temp.em('2026-10-30 10:00'), null, pg_temp.em('2026-10-30 09:30'));
      r := public._agenda_cliente_enfileirar(v_m, pg_temp.em('2026-10-30 10:00'));
      v_res := pg_temp.ok(v_res, 'M3 sem o A-5: com 2 iniciadas do retorno hoje e o total de 2, a confirmação vai à fila (o teto não vê o retorno; o A5b morde)',
        r ->> 'estado' = 'enfileirada', r::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    -- M4 = B1
    begin
      perform pg_temp.ligar(0);
      perform pg_temp.saida(c_cli, 'orcamento', 'orc_lembrete', 'comercial', 'enviada', pg_temp.em('2026-10-30 09:00'));
      v_m := pg_temp.confirmar_flavio(pg_temp.em('2026-10-30 10:00'), null, pg_temp.em('2026-10-30 09:30'));
      v_res := pg_temp.ok(v_res, 'M4 sem a regra na 2ª trava: com o lembrete enviado hoje, a linha direta da fila entra (o B1 morde)',
        pg_temp.na_fila(v_m) = 'entrou', null);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    raise exception 'desfaz' using errcode = 'P0097';
  exception when sqlstate 'P0097' then null;
  end;

  raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$a$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
