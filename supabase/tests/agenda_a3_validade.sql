-- Prova do conserto da validade do pedido A-3 da F5 (migration 20261113400000_agenda_a3_validade.sql): a confirmação empurrada pelo "Fechado" e a
-- véspera empurrada pelo orçamento do dia levam a validade junto (não caem mais por ela), sem nunca sair no dia do serviço ou depois; a revalidação
-- continua mandando; a guarda da tabela só aceita esse avanço.
-- bancada: depende de 20261113400000
--
--   P0  a forma e as portas (vale em produção): a guarda e o enfileirar = a origem de produção de 14/11 + só os blocos "-- PEDIDO A-3, VALIDADE (F5):"
--       (md5 sem CR); tirados também os do A-1/A-3, o enfileirar é o de 20261028100800; as portas de antes; o gatilho segue na guarda; sem WHERE
--   R0  na bancada da agenda (sem retorno_saidas), a tabela de teste do A-1/A-3 (as colunas que a regra lê e os CHECKs da F5); some no rollback
--   V1  (fixture-fase5) o caso mais comum: o "Fechado" de ter 27/10 14:00 e a confirmação do Flávio (ter 03/11) marcada para as 15:00, valendo só
--       na terça: ela espera qua 28/10 08:00 e a validade vai junto (qua 28/10 19:00, 1 dia); nada recusado, nada na fila
--   V2  na quarta ela sai (enfileirada, o texto igual ao registrado: a confirmação fala o dia por extenso); o passo fila de ponta a ponta faz o mesmo
--   V3  a revalidação continua mandando: empurrada, e a OS voltando a esperar peça, na quarta ela cai (status)
--   V4  (b) o "Fechado" de sex 30/10: o dia útil seguinte é ter 03/11, o próprio dia do serviço — a confirmação cai (teto_dia), valha ela só na
--       sexta ou até terça (antes do conserto, a de validade longa ia para ter 03/11 08:00, no dia do serviço)
--   V5  a véspera de sex 30/10 ("Na terça (03/11) chegamos …") com o lembrete do orçamento já enviado: espera sáb 31/10 com a validade junto e sai
--       no sábado (o texto não muda)
--   V6  (c) a véspera empurrada para um dia em que o texto mudaria ("Amanhã", seg 02/11) a revalidação recusa (desatualizada)
--   V7  a confirmação empurrada só pelo lembrete (A-1, orcamento_hoje) não leva a validade: cai como antes (teto_dia), a validade intacta
--   G1  a guarda: sem o caminho, mudar a validade dá o erro de sempre; com o caminho ligado, só o avanço junto com a hora, esperando, em ligado,
--       confirmar ou véspera, e nada mais mudando
--   M   sem o conserto (as 2 recriadas sem os blocos, numa subtransação): o V1 cai (teto_dia), o V4 de validade longa vai ao dia do serviço e a
--       guarda recusa o avanço (o teste morde)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration:  npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_a3_validade.sql
--   Sem as fixtures (produção) R0, V, G e M saem PULADO; P0 roda e não grava nada. Termina em ROLLBACK.
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
create function pg_temp.br(p timestamptz) returns text language sql immutable as $f$
  select to_char(p at time zone 'America/Sao_Paulo', 'YYYY-MM-DD HH24:MI')
$f$;
create function pg_temp.src(p_assinatura text) returns text language sql stable as $f$
  select replace(p.prosrc, chr(13), '') from pg_proc p where p.oid = to_regprocedure(p_assinatura)
$f$;
-- Tira os blocos de um marcador ("-- <p_marca> (F5): … -- <p_marca> (F5): fim"); p_marca é uma expressão regular.
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
create function pg_temp.sem_validade(p text) returns text language sql immutable as $f$
  select pg_temp.sem_blocos(p, 'PEDIDO A-3, VALIDADE')
$f$;
create function pg_temp.porta(p_assinatura text) returns text language sql stable as $f$
  select format('%s %s | %s %s %s %s', p.prosecdef, p.provolatile, has_function_privilege('anon', p.oid, 'execute'),
                has_function_privilege('authenticated', p.oid, 'execute'), has_function_privilege('service_role', p.oid, 'execute'),
                coalesce((select bool_or(a.grantee = 0) from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.privilege_type = 'EXECUTE'), false))
    from pg_proc p where p.oid = to_regprocedure(p_assinatura)
$f$;
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
  c_gua constant text := 'public._agenda_cliente_mensagens_so_muda()';
  c_enf constant text := 'public._agenda_cliente_enfileirar(uuid, timestamptz)';
begin
  v_res := pg_temp.ok(v_res, 'P0a _agenda_cliente_mensagens_so_muda (a guarda): tirado o bloco "-- PEDIDO A-3, VALIDADE (F5):", é o corpo de produção de 14/11 (20261028100000, md5 89bdf01e…); invoker, só service_role além do dono; o gatilho BEFORE UPDATE segue nela',
    md5(pg_temp.sem_validade(pg_temp.src(c_gua))) = '89bdf01e9f6f759236c9c5dc92578f30' and md5(pg_temp.src(c_gua)) <> '89bdf01e9f6f759236c9c5dc92578f30'
    and (select count(*) from regexp_matches(pg_temp.src(c_gua), '-- PEDIDO A-3, VALIDADE \(F5\): fim', 'g')) = 1
    and pg_temp.porta(c_gua) = 'f v | f f t f'
    and exists (select 1 from pg_trigger t where t.tgrelid = 'public.agenda_cliente_mensagens'::regclass and not t.tgisinternal
                  and t.tgname = 'agenda_cliente_mensagens_so_muda' and t.tgfoid = to_regprocedure(c_gua)),
    md5(pg_temp.sem_validade(pg_temp.src(c_gua))) || ' ' || pg_temp.porta(c_gua));
  v_res := pg_temp.ok(v_res, 'P0b _agenda_cliente_enfileirar: tirados os 2 blocos "-- PEDIDO A-3, VALIDADE (F5):", é o corpo de produção de 14/11 (o A-1/A-3, 20261113300000, md5 38775240…); tirados também os do A-1/A-3, o de 20261028100800 (39c92c14…); definer, ninguém executa',
    md5(pg_temp.sem_validade(pg_temp.src(c_enf))) = '38775240c466381c78714aea11fa8d71'
    and md5(pg_temp.sem_blocos(pg_temp.src(c_enf), 'PEDIDO A-[0-9]( e A-[0-9])?')) = '39c92c146c43d1a24dcdb42afaea14b7'
    and (select count(*) from regexp_matches(pg_temp.src(c_enf), '-- PEDIDO A-3, VALIDADE \(F5\): fim', 'g')) = 2
    and pg_temp.porta(c_enf) = 't v | f f f f',
    md5(pg_temp.sem_validade(pg_temp.src(c_enf))) || ' ' || pg_temp.porta(c_enf));
  v_res := pg_temp.ok(v_res, 'P0c nenhum UPDATE/DELETE sem WHERE no nível de cima das 2 (o pg_safeupdate do PostgREST recusaria)',
    (select count(*) from unnest(array[c_gua, c_enf]) a(f), pg_temp.sem_where(pg_temp.src(a.f)) s) = 0,
    (select string_agg(s, ' | ') from unnest(array[c_gua, c_enf]) a(f), pg_temp.sem_where(pg_temp.src(a.f)) s));
  perform pg_temp.gravar(v_res);
end
$p0$;

-- ── R0. Na bancada da agenda, a tabela de teste do retorno ─────────────────────────────────────────────────────────────────────────────
do $r0$
begin
  if to_regclass('public.retorno_saidas') is not null then
    insert into _resultado values ('R0 a tabela do retorno', true, 'PULADO: a tabela do retorno existe (produção ou a bancada do retorno)');
    return;
  end if;
  -- as colunas de retorno_saidas (20261116100100) que a regra do A-1/A-3 lê e o insert do teste precisa, com os CHECKs de emissor, classe e estado
  -- da F5 (20270112100000) e o de enviada_em; some no rollback
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
  insert into _resultado values ('R0 a tabela de teste do retorno existe (só neste teste; some no rollback)', to_regclass('public.retorno_saidas') is not null, null);
end
$r0$;

-- ── V, G e M (a fixture-fase5) ─────────────────────────────────────────────────────────────────────────────────────────────────────────
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
create function pg_temp.saida(p_cliente uuid, p_tipo text, p_classe text, p_em timestamptz) returns uuid language plpgsql as $f$
declare
  v uuid;
begin
  execute $i$
    insert into public.retorno_saidas (emissor, tipo, origem, classe, chave, phone_normalized, client_id, modo, estado, enviar_em, decidida_em,
                                       enviada_em, texto, dedupe_key)
    values ('orcamento', $1, 'retorno_orcamento', $2, '90000304', '5547990000304', $3, 'ligado', 'enviada', $4, $4, $4,
            'Mensagem do retorno (teste)', 'teste-a3v:' || gen_random_uuid())
    returning id $i$
  into v using p_tipo, p_classe, p_cliente, p_em;
  return v;
end $f$;
-- Uma mensagem do Flávio (OS-00104, o serviço em ter 03/11) pela rodada: p_tipo confirmar ou vespera, sai p_alvo, vale até p_valida (null = o fim
-- da janela do dia do envio).
create function pg_temp.flavio(p_tipo text, p_alvo timestamptz, p_valida timestamptz, p_agora timestamptz, p_chave text default null) returns uuid
language plpgsql as $f$
declare
  r jsonb;
begin
  perform set_config('agenda_teste.hoje', to_char(p_agora at time zone 'America/Sao_Paulo', 'YYYY-MM-DD'), true);
  r := public._agenda_cliente_registrar(p_tipo, null, '05000000-0000-4000-8000-000000000104', date '2026-11-03',
                                        case when p_chave is null then '{}'::jsonb else jsonb_build_object('chave', p_chave) end,
                                        p_alvo, p_valida, 'rodada', null, p_agora);
  return (r ->> 'id')::uuid;
end $f$;
-- Uma tentativa de UPDATE: 'ok' ou o erro.
create function pg_temp.tenta(p_sql text) returns text language plpgsql as $f$
begin
  execute p_sql;
  return 'ok';
exception when others then
  return 'erro ' || sqlstate || ': ' || sqlerrm;
end $f$;

do $v$
declare
  v_res  jsonb := '[]'::jsonb;
  c_flav constant uuid := '05000000-0000-4000-8000-000000000104';
  c_cli  constant uuid := 'c1000000-0000-4000-8000-000000000004';
  c_erro constant text := 'erro P0001: A mensagem ao cliente registrada não muda: só o estado, a aprovação, a fila, o envio e a resposta.';
  r      jsonb;
  m      public.agenda_cliente_mensagens;
  m0     public.agenda_cliente_mensagens;
  v_m    uuid;
  v_ok   boolean;
  t      text;
  v_rv   text;
begin
  if coalesce(current_setting('agenda_teste.fase5', true), '') = '' or to_regclass('public.retorno_saidas') is null then
    insert into _resultado values ('V1–V7, G1, M (fixture-fase5)', true, 'PULADO: sem agenda_teste.fase5 ou sem a tabela de teste (rode pela bancada)');
    return;
  end if;
  begin
  execute current_setting('agenda_teste.fase5');

  -- ── V1–V2. O caso mais comum: o "Fechado" e a confirmação no mesmo dia ──
  begin
    perform pg_temp.ligar(0);
    perform pg_temp.saida(c_cli, 'orc_fechado', 'resposta_imediata', pg_temp.em('2026-10-27 14:00'));
    v_m := pg_temp.flavio('confirmar', pg_temp.em('2026-10-27 15:00'), null, pg_temp.em('2026-10-27 14:30'));
    m0 := pg_temp.msg(v_m);
    r := public._agenda_cliente_enfileirar(v_m, pg_temp.em('2026-10-27 15:00'));
    m := pg_temp.msg(v_m);
    v_res := pg_temp.ok(v_res, 'V1 o "Fechado" de ter 27/10 14:00 e a confirmação (serviço ter 03/11) marcada para as 15:00, valendo só na terça: espera qua 28/10 08:00 com a validade junto (qua 28/10 19:00, a mesma distância de 1 dia); nada recusado, nada na fila',
      pg_temp.br(m0.valida_ate) = '2026-10-27 19:00' and r ->> 'estado' = 'registrada' and r ->> 'motivo' = 'orcamento_fechado'
      and m.estado = 'registrada' and m.recusa_motivo is null and pg_temp.br(m.enviar_em) like '2026-10-28 08:0%'
      and pg_temp.br(m.valida_ate) = '2026-10-28 19:00' and (r ->> 'valida_ate')::timestamptz = m.valida_ate
      and not exists (select 1 from public.whatsapp_send_queue q where q.source_ref_id = v_m),
      format('antes: sai %s, vale %s; %s; agora %s/%s sai %s vale %s', pg_temp.br(m0.enviar_em), pg_temp.br(m0.valida_ate), r, m.estado,
             coalesce(m.recusa_motivo, '-'), pg_temp.br(m.enviar_em), pg_temp.br(m.valida_ate)));
    r := public._agenda_cliente_enfileirar(v_m, m.enviar_em);
    m := pg_temp.msg(v_m);
    v_res := pg_temp.ok(v_res, 'V2a na quarta ela sai: enfileirada na hora nova, com o texto registrado (a confirmação fala o dia por extenso: a revalidação não acha diferença)',
      r ->> 'estado' = 'enfileirada' and m.estado = 'enfileirada' and m.texto = m0.texto
      and exists (select 1 from public.whatsapp_send_queue q where q.id = m.fila_id and q.scheduled_for = m.enviar_em and q.message = m0.texto),
      r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.ligar(0);
    perform pg_temp.saida(c_cli, 'orc_fechado', 'resposta_imediata', pg_temp.em('2026-10-27 14:00'));
    v_m := pg_temp.flavio('confirmar', pg_temp.em('2026-10-27 15:00'), null, pg_temp.em('2026-10-27 14:30'));
    r := public._agenda_cliente_fila(date '2026-10-27', pg_temp.em('2026-10-27 15:00'));
    m := pg_temp.msg(v_m);
    t := format('ter: %s, %s sai %s vale %s', r, m.estado, pg_temp.br(m.enviar_em), pg_temp.br(m.valida_ate));
    v_ok := m.estado = 'registrada' and pg_temp.br(m.valida_ate) = '2026-10-28 19:00' and (r ->> 'esperando')::int >= 1 and (r ->> 'vencidas')::int = 0;
    r := public._agenda_cliente_fila(date '2026-10-27', pg_temp.em('2026-10-27 19:30'));
    v_ok := v_ok and (pg_temp.msg(v_m)).estado = 'registrada';
    r := public._agenda_cliente_fila(date '2026-10-28', (pg_temp.msg(v_m)).enviar_em);
    m := pg_temp.msg(v_m);
    v_res := pg_temp.ok(v_res, 'V2b o passo fila de ponta a ponta: na terça a confirmação fica esperando (não vence às 19:30, a validade foi junto); no tique de quarta vai à fila',
      v_ok and m.estado = 'enfileirada' and (r ->> 'enfileiradas')::int >= 1, format('%s; qua: %s, %s', t, r, m.estado));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── V3. A revalidação continua mandando ──
  begin
    perform pg_temp.ligar(0);
    perform pg_temp.saida(c_cli, 'orc_fechado', 'resposta_imediata', pg_temp.em('2026-10-27 14:00'));
    v_m := pg_temp.flavio('confirmar', pg_temp.em('2026-10-27 15:00'), null, pg_temp.em('2026-10-27 14:30'));
    r := public._agenda_cliente_enfileirar(v_m, pg_temp.em('2026-10-27 15:00'));
    update public.service_orders set status = 'awaiting_parts' where id = c_flav;
    r := public._agenda_cliente_enfileirar(v_m, (pg_temp.msg(v_m)).enviar_em);
    m := pg_temp.msg(v_m);
    v_res := pg_temp.ok(v_res, 'V3 a revalidação continua mandando: empurrada com a validade, e a OS voltando a esperar peça, na quarta ela cai (status), nada na fila',
      r ->> 'estado' = 'recusada' and m.recusa_motivo = 'status' and not exists (select 1 from public.whatsapp_send_queue q where q.source_ref_id = v_m),
      r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── V4. (b) O dia útil seguinte ao "Fechado" já é o dia do serviço ──
  begin
    perform pg_temp.ligar(0);
    perform pg_temp.saida(c_cli, 'orc_fechado', 'resposta_imediata', pg_temp.em('2026-10-30 09:00'));
    v_m := pg_temp.flavio('confirmar', pg_temp.em('2026-10-30 10:00'), null, pg_temp.em('2026-10-30 09:30'));
    r := public._agenda_cliente_enfileirar(v_m, pg_temp.em('2026-10-30 10:00'));
    m := pg_temp.msg(v_m);
    t := format('só sexta: %s, vale %s', r, pg_temp.br(m.valida_ate));
    v_ok := r ->> 'estado' = 'recusada' and m.recusa_motivo = 'teto_dia' and pg_temp.br(m.valida_ate) = '2026-10-30 19:00';
    v_m := pg_temp.flavio('confirmar', pg_temp.em('2026-10-30 10:00'), public._agenda_cliente_fim_da_janela(date '2026-10-30', 2), pg_temp.em('2026-10-30 09:30'), 'v4:longa');
    r := public._agenda_cliente_enfileirar(v_m, pg_temp.em('2026-10-30 10:00'));
    m := pg_temp.msg(v_m);
    v_res := pg_temp.ok(v_res, 'V4 (b) o "Fechado" de sex 30/10: o dia útil seguinte é ter 03/11, o próprio dia do serviço — a confirmação cai (teto_dia), valha só na sexta ou até terça 19:00; nunca vai ao dia do serviço',
      v_ok and r ->> 'estado' = 'recusada' and m.recusa_motivo = 'teto_dia' and pg_temp.br(m.valida_ate) = '2026-11-03 19:00'
      and not exists (select 1 from public.whatsapp_send_queue q where q.source = 'agenda-cliente' and q.dedupe_key like 'agenda-cliente:confirmar:' || c_flav || '%'),
      format('%s; até terça: %s', t, r));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── V5–V6. A véspera empurrada pelo orçamento do dia (A-1) ──
  begin
    perform pg_temp.ligar(0);
    perform pg_temp.saida(c_cli, 'orc_lembrete', 'comercial', pg_temp.em('2026-10-30 09:00'));
    v_m := pg_temp.flavio('vespera', pg_temp.em('2026-10-30 10:00'), null, pg_temp.em('2026-10-30 09:30'));
    m0 := pg_temp.msg(v_m);
    r := public._agenda_cliente_enfileirar(v_m, pg_temp.em('2026-10-30 10:00'));
    m := pg_temp.msg(v_m);
    t := format('%s; sai %s vale %s', r, pg_temp.br(m.enviar_em), pg_temp.br(m.valida_ate));
    v_ok := r ->> 'motivo' = 'orcamento_hoje' and m.estado = 'registrada' and pg_temp.br(m.enviar_em) like '2026-10-31 08:0%'
            and pg_temp.br(m.valida_ate) = '2026-10-31 19:00' and m0.texto like '%Na terça (03/11)%';
    r := public._agenda_cliente_enfileirar(v_m, m.enviar_em);
    m := pg_temp.msg(v_m);
    v_res := pg_temp.ok(v_res, 'V5 a véspera de sex 30/10 ("Na terça (03/11) chegamos …") com o lembrete do orçamento já enviado: espera sáb 31/10 com a validade junto (sáb 19:00) e sai no sábado com o texto registrado',
      v_ok and r ->> 'estado' = 'enfileirada' and m.texto = m0.texto, format('%s; sáb: %s', t, r));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    -- a mesma véspera levada pelo caminho da guarda (a hora e a validade juntas) para seg 02/11, um dia em que o texto diria "Amanhã"
    perform pg_temp.ligar(0);
    v_m := pg_temp.flavio('vespera', pg_temp.em('2026-10-30 10:00'), null, pg_temp.em('2026-10-30 09:30'));
    v_rv := public._agenda_cliente_revalidar(v_m, pg_temp.em('2026-10-30 10:00'));
    perform set_config('agenda.cliente_validade_avanca', 'on', true);
    update public.agenda_cliente_mensagens set enviar_em = pg_temp.em('2026-11-02 10:00'), valida_ate = pg_temp.em('2026-11-02 19:00') where id = v_m;
    perform set_config('agenda.cliente_validade_avanca', '', true);
    r := public._agenda_cliente_enfileirar(v_m, pg_temp.em('2026-11-02 10:00'));
    m := pg_temp.msg(v_m);
    v_res := pg_temp.ok(v_res, 'V6 (c) a revalidação manda no texto: a véspera que fala "Na terça (03/11)", com a hora num dia em que diria "Amanhã" (seg 02/11), cai (desatualizada), nada na fila',
      v_rv is null and r ->> 'estado' = 'recusada' and m.recusa_motivo = 'desatualizada'
      and not exists (select 1 from public.whatsapp_send_queue q where q.source_ref_id = v_m),
      format('na sexta %s; na segunda %s', coalesce(v_rv, 'vale'), r));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── V7. A confirmação empurrada só pelo lembrete (A-1) não leva a validade ──
  begin
    perform pg_temp.ligar(0);
    perform pg_temp.saida(c_cli, 'orc_lembrete', 'comercial', pg_temp.em('2026-10-27 09:00'));
    v_m := pg_temp.flavio('confirmar', pg_temp.em('2026-10-27 15:00'), null, pg_temp.em('2026-10-27 14:30'));
    r := public._agenda_cliente_enfileirar(v_m, pg_temp.em('2026-10-27 15:00'));
    m := pg_temp.msg(v_m);
    v_res := pg_temp.ok(v_res, 'V7 a confirmação empurrada só pelo lembrete do orçamento (A-1, orcamento_hoje), valendo só na terça: cai como antes (teto_dia), a validade intacta',
      r ->> 'estado' = 'recusada' and m.recusa_motivo = 'teto_dia' and pg_temp.br(m.valida_ate) = '2026-10-27 19:00', r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── G1. A guarda ──
  begin
    perform pg_temp.ligar(0);
    v_m := pg_temp.flavio('confirmar', pg_temp.em('2026-10-27 15:00'), null, pg_temp.em('2026-10-27 14:30'));
    t := pg_temp.tenta(format('update public.agenda_cliente_mensagens set enviar_em = enviar_em + interval ''1 day'', valida_ate = valida_ate + interval ''1 day'' where id = %L', v_m));
    perform set_config('agenda.cliente_validade_avanca', 'on', true);
    v_ok := t = c_erro
      and pg_temp.tenta(format('update public.agenda_cliente_mensagens set valida_ate = valida_ate - interval ''1 hour'', enviar_em = enviar_em + interval ''1 hour'' where id = %L', v_m)) = c_erro
      and pg_temp.tenta(format('update public.agenda_cliente_mensagens set valida_ate = valida_ate + interval ''1 day'' where id = %L', v_m)) = c_erro
      and pg_temp.tenta(format('update public.agenda_cliente_mensagens set enviar_em = valida_ate + interval ''2 days'', valida_ate = valida_ate + interval ''1 day'' where id = %L', v_m)) = c_erro
      and pg_temp.tenta(format('update public.agenda_cliente_mensagens set enviar_em = enviar_em + interval ''1 day'', valida_ate = valida_ate + interval ''1 day'', texto = ''Outro texto qualquer.'' where id = %L', v_m)) = c_erro;
    v_res := pg_temp.ok(v_res, 'G1a a guarda: sem o caminho, mudar a validade dá o erro de sempre; com o caminho ligado, também recusa a validade que volta, a que anda sem a hora, a hora fora da validade nova e outra coluna mudando junto',
      v_ok, t);
    t := pg_temp.tenta(format('update public.agenda_cliente_mensagens set enviar_em = enviar_em + interval ''1 day'', valida_ate = valida_ate + interval ''1 day'' where id = %L', v_m));
    m := pg_temp.msg(v_m);
    update public.agenda_cliente_mensagens set estado = 'enfileirada', fila_id = gen_random_uuid() where id = v_m;
    v_res := pg_temp.ok(v_res, 'G1b com o caminho ligado, a hora e a validade andam juntas na mensagem esperando; enfileirada, não mais',
      t = 'ok' and pg_temp.br(m.valida_ate) = '2026-10-28 19:00'
      and pg_temp.tenta(format('update public.agenda_cliente_mensagens set valida_ate = valida_ate + interval ''1 day'' where id = %L', v_m)) = c_erro,
      t);
    perform set_config('agenda.cliente_validade_avanca', '', true);
    update public.agenda_config set modo_cliente = 'sombra' where id;
    v_m := pg_temp.flavio('confirmar', pg_temp.em('2026-10-27 15:00'), null, pg_temp.em('2026-10-27 14:30'), 'g1:sombra');
    perform set_config('agenda.cliente_validade_avanca', 'on', true);
    v_res := pg_temp.ok(v_res, 'G1c em teste (sombra), nem com o caminho ligado a validade muda',
      (pg_temp.msg(v_m)).modo = 'sombra'
      and pg_temp.tenta(format('update public.agenda_cliente_mensagens set enviar_em = enviar_em + interval ''1 day'', valida_ate = valida_ate + interval ''1 day'' where id = %L', v_m)) = c_erro,
      null);
    perform set_config('agenda.cliente_validade_avanca', '', true);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── M. Sem o conserto (as 2 recriadas sem os blocos da validade, numa subtransação): o teste morde ──
  begin
    execute format('create or replace function public._agenda_cliente_enfileirar(p_msg uuid, p_agora timestamptz default now()) returns jsonb language plpgsql volatile security definer set search_path to ''public'' as %L',
                   pg_temp.sem_validade(pg_temp.src('public._agenda_cliente_enfileirar(uuid, timestamptz)')));
    execute format('create or replace function public._agenda_cliente_mensagens_so_muda() returns trigger language plpgsql set search_path to ''public'' as %L',
                   pg_temp.sem_validade(pg_temp.src('public._agenda_cliente_mensagens_so_muda()')));
    begin
      perform pg_temp.ligar(0);
      perform pg_temp.saida(c_cli, 'orc_fechado', 'resposta_imediata', pg_temp.em('2026-10-27 14:00'));
      v_m := pg_temp.flavio('confirmar', pg_temp.em('2026-10-27 15:00'), null, pg_temp.em('2026-10-27 14:30'));
      r := public._agenda_cliente_enfileirar(v_m, pg_temp.em('2026-10-27 15:00'));
      v_res := pg_temp.ok(v_res, 'M1 sem o conserto (o A-1/A-3 de 20261113300000): a confirmação do V1 cai (teto_dia) — o cliente fica sem a data prometida (o V1 morde)',
        r ->> 'estado' = 'recusada' and r ->> 'motivo' = 'teto_dia', r::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      perform pg_temp.ligar(0);
      perform pg_temp.saida(c_cli, 'orc_fechado', 'resposta_imediata', pg_temp.em('2026-10-30 09:00'));
      v_m := pg_temp.flavio('confirmar', pg_temp.em('2026-10-30 10:00'), public._agenda_cliente_fim_da_janela(date '2026-10-30', 2), pg_temp.em('2026-10-30 09:30'));
      r := public._agenda_cliente_enfileirar(v_m, pg_temp.em('2026-10-30 10:00'));
      v_res := pg_temp.ok(v_res, 'M2 sem o conserto: a confirmação de validade longa depois do "Fechado" de sexta vai para ter 03/11 08:00, o dia do serviço (o V4 morde)',
        r ->> 'estado' = 'registrada' and pg_temp.br((pg_temp.msg(v_m)).enviar_em) like '2026-11-03 08:0%', r::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      perform pg_temp.ligar(0);
      v_m := pg_temp.flavio('confirmar', pg_temp.em('2026-10-27 15:00'), null, pg_temp.em('2026-10-27 14:30'));
      perform set_config('agenda.cliente_validade_avanca', 'on', true);
      t := pg_temp.tenta(format('update public.agenda_cliente_mensagens set enviar_em = enviar_em + interval ''1 day'', valida_ate = valida_ate + interval ''1 day'' where id = %L', v_m));
      perform set_config('agenda.cliente_validade_avanca', '', true);
      v_res := pg_temp.ok(v_res, 'M3 sem o conserto, a guarda recusa até o avanço pelo caminho (o G1b morde)', t = c_erro, t);
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
$v$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
