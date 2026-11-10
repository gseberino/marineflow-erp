-- Prova da correção do NOVO-agenda-98 da Agenda de Produção (migration 20261113100000): a pergunta do OK de uma mensagem ao
-- cliente (cliente_aprovar) fica aberta enquanto a mensagem dela espera o dono, também com a OS já concluída ("ficou pronto",
-- pós-serviço). Antes, _agenda_vigia_limpeza a fechava no tique seguinte ("a OS saiu da carteira"), e *manda cliente* e *segura
-- cliente* respondiam "Essa pergunta já foi respondida ou resolvida.".
-- bancada: depende de 20261113100000
--
--   C0  a cópia e a porta: o corpo vivo e o da migration, sem o bloco "-- CORREÇÃO 10/11 (98):", são o de 20261031100300 byte a
--       byte (e o md5 de produção de hoje, de fora); 1 bloco; a migration só recria esta função; ninguém de fora a executa
--   C1  o "ficou pronto" da Lucenira (OS concluída hoje), com o OK pedido: a pergunta segue aberta depois da limpeza e de um tique
--       inteiro da vigia; o fechamento do dia e *agenda pendências* a mostram com *manda cliente Lucenira*
--   C2  *manda cliente Lucenira* acha a mensagem: "Mando para Lucenira agora.", a mensagem vai à fila (enfileirada, a linha
--       pendente; nada sai: a bancada não tem worker) e a pergunta fica respondida; relida depois de outra limpeza, igual
--   C3  *segura cliente Lucenira* acha e segura: a mensagem recusada (segurada) e a pergunta respondida; nada na fila
--   C4  sem resposta: até a validade a pergunta fica aberta; passada a validade, vence (pela limpeza ou pelo passo fila, nas
--       duas ordens), e a mensagem vence junto: nenhuma pergunta aberta sem mensagem esperando, nenhuma mensagem esperando sem
--       pergunta aberta
--   C5  o pós-serviço do Robson (OS concluída e entregue), com o OK pedido: a pergunta segue aberta e *manda cliente Robson* enfileira
--   C6  a mensagem que saiu de aguardando_dono por um caminho que não fecha a pergunta: a limpeza a fecha pela regra de antes
--   C7  as outras perguntas fecham como antes: a mesma cena (as perguntas da fixture e mais 9 de outros tipos, de OS concluídas
--       e da carteira) com a limpeza de agora e com a de 20261031100300 rodada como pg_temp, com e sem o freio: as perguntas,
--       as propostas, as alocações, as mensagens e a fila, linha a linha, iguais, fora as 2 poupadas (que a de antes fecha)
--   C8  sem o conserto (a definição de 20261031100300 de volta, numa subtransação), a mesma cena fecha a pergunta e o *manda*
--       responde "Essa pergunta já foi respondida ou resolvida.": as condições de C1 e C2 dão falso (o teste morde)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   C0 roda em qualquer lugar (a comparação com o texto das migrations só na bancada, que as passa em agenda_teste.*); C1 a
--   C8 só na bancada (a fixture-fase5, sex 30/10/2026; fora dela, PULADO). Termina em ROLLBACK: nada fica gravado e nenhuma
--   mensagem sai.
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

-- A definição inteira de uma função numa migration (do "create or replace function" ao "$function$;"), e o corpo (entre o
-- "as $function$" e o "$function$;", como o prosrc).
create function pg_temp.inteira(p_mig text, p_nome text) returns text language plpgsql immutable as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  return left(v, position(E'\n$function$;' in v) + length(E'\n$function$;') - 1);
end $f$;
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql immutable as $f$
declare
  v text := pg_temp.inteira(p_mig, p_nome);
begin
  v := substr(v, position(E'\nas $function$' in v) + length(E'\nas $function$'));
  return left(v, length(v) - length('$function$;'));
end $f$;
-- As linhas fora do bloco "-- CORREÇÃO 10/11 (98): … -- CORREÇÃO 10/11 (98): fim".
create function pg_temp.sem_98(p text) returns text language plpgsql immutable as $f$
declare
  v_fora text[] := '{}';
  v_dentro boolean := false;
  l text;
begin
  foreach l in array string_to_array(replace(p, E'\r\n', E'\n'), E'\n') loop
    if not v_dentro and l ~ '^\s*-- CORREÇÃO 10/11 \(98\):' and l !~ '^\s*-- CORREÇÃO 10/11 \(98\): fim' then
      v_dentro := true;
      continue;
    end if;
    if v_dentro then
      if l ~ '^\s*-- CORREÇÃO 10/11 \(98\): fim' then v_dentro := false; end if;
      continue;
    end if;
    v_fora := v_fora || l;
  end loop;
  return array_to_string(v_fora, E'\n');
end $f$;

-- ── C0. A cópia e a porta ───────────────────────────────────────────────────────────────────────────────
do $copia$
declare
  v_res  jsonb := '[]'::jsonb;
  v_7a   text := coalesce(current_setting('agenda_teste.mig_perguntas_fase7a', true), '');
  v_98   text := coalesce(current_setting('agenda_teste.mig_correcao_98', true), '');
  v_vivo text;
  v_n    int;
  -- o md5 do corpo de _agenda_vigia_limpeza em produção hoje (o de 20261031100300, sem CR): sql/wf7f9_md5_sem_final.sql, parte A
  c_md5_producao constant text := '4e8e904cdf2d768b83a8cd8d005d38d9';
begin
  select replace(p.prosrc, E'\r\n', E'\n') into v_vivo
    from pg_proc p where p.oid = 'public._agenda_vigia_limpeza(date, timestamptz)'::regprocedure;
  v_res := pg_temp.ok(v_res, 'C0a o corpo vivo tem 1 bloco "-- CORREÇÃO 10/11 (98):", e sem ele é o corpo de produção de hoje (md5 de 20261031100300, de fora)',
    (select count(*) from regexp_matches(v_vivo, '-- CORREÇÃO 10/11 \(98\): fim', 'g')) = 1
    and md5(pg_temp.sem_98(v_vivo)) = c_md5_producao and md5(v_vivo) <> c_md5_producao,
    format('md5 sem o bloco %s; com %s', md5(pg_temp.sem_98(v_vivo)), md5(v_vivo)));
  select pg_temp.ok(v_res, 'C0b a porta: 1 assinatura, invoker, volátil, search_path=public; nem anon, nem authenticated, nem service_role, nem PUBLIC',
    (select count(*) from pg_proc x where x.pronamespace = 'public'::regnamespace and x.proname = '_agenda_vigia_limpeza') = 1
    and not p.prosecdef and p.provolatile = 'v' and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=public%'
    and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
    and not has_function_privilege('service_role', p.oid, 'execute')
    and not coalesce((select bool_or(a.grantee = 0) from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                       where a.privilege_type = 'EXECUTE'), false),
    format('definer %s, volatilidade %s, config %s', p.prosecdef, p.provolatile, p.proconfig))
    into v_res
    from pg_proc p where p.oid = 'public._agenda_vigia_limpeza(date, timestamptz)'::regprocedure;
  if v_7a = '' or v_98 = '' then
    v_res := pg_temp.ok(v_res, 'C0c as cópias pelo texto das migrations', true,
      'PULADO: sem agenda_teste.mig_perguntas_fase7a / mig_correcao_98 (rode pela bancada)');
  else
    v_res := pg_temp.ok(v_res, 'C0c o corpo vivo é o da 20261113100000, e os dois, sem o bloco, são o de 20261031100300 byte a byte; o tirador morde (com o bloco, diferem)',
      v_vivo = pg_temp.corpo(v_98, '_agenda_vigia_limpeza')
      and pg_temp.sem_98(pg_temp.corpo(v_98, '_agenda_vigia_limpeza')) = pg_temp.corpo(v_7a, '_agenda_vigia_limpeza')
      and pg_temp.sem_98(v_vivo) = pg_temp.corpo(v_7a, '_agenda_vigia_limpeza')
      and v_vivo <> pg_temp.corpo(v_7a, '_agenda_vigia_limpeza')
      and pg_temp.sem_98(pg_temp.inteira(v_98, '_agenda_vigia_limpeza')) = pg_temp.inteira(v_7a, '_agenda_vigia_limpeza'),
      format('vivo %s, da 98 %s, da 7a %s, vivo sem o bloco %s letras', length(v_vivo), length(pg_temp.corpo(v_98, '_agenda_vigia_limpeza')),
             length(pg_temp.corpo(v_7a, '_agenda_vigia_limpeza')), length(pg_temp.sem_98(v_vivo))));
    -- o que a migration faz, fora dos comentários: 1 create or replace (esta), o comment e o revoke; nenhuma tabela, dado, gatilho, cron ou grant
    v_98 := regexp_replace(replace(v_98, E'\r\n', E'\n'), E'--[^\n]*', '', 'g');
    select count(*) into v_n from regexp_matches(v_98, 'create or replace function', 'gi');
    v_res := pg_temp.ok(v_res, 'C0d a migration só recria _agenda_vigia_limpeza (com o comment e o revoke de antes): nenhuma tabela, dado, gatilho, cron ou grant',
      v_n = 1
      and v_98 like '%comment on function public._agenda_vigia_limpeza(date, timestamptz) is %'
      and v_98 like '%revoke all on function public._agenda_vigia_limpeza(date, timestamptz) from public, anon, authenticated, service_role;%'
      and (select count(*) from regexp_matches(regexp_replace(v_98, '\$function\$.*\$function\$', '', 's'),
             '\m(alter|insert|update|delete|create table|create index|create trigger|grant|cron|drop)\M', 'gi')) = 0,
      format('%s create or replace', v_n));
  end if;
  perform pg_temp.gravar(v_res);
end
$copia$;

-- ── C1 a C8 (a fixture-fase5; sex 30/10/2026) ──────────────────────────────────────────────────────────────

-- Liga a mensagem ao cliente (todos os tipos) com a aprovação dos primeiros dias (3: o OK do dono é pedido).
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

-- A limpeza da vigia (o passo 1 de agenda_vigiar), na hora dada.
create function pg_temp.limpa(p_quando text) returns jsonb language plpgsql as $f$
begin
  perform set_config('agenda_teste.hoje', left(p_quando, 10), true);
  return public._agenda_vigia_limpeza(left(p_quando, 10)::date, pg_temp.em(p_quando));
end $f$;

-- A mensagem de um tipo de uma OS (a mais nova) e a pergunta dela.
create function pg_temp.msg(p_os uuid, p_tipo text) returns public.agenda_cliente_mensagens language sql stable as $f$
  select m.* from public.agenda_cliente_mensagens m where m.service_order_id = p_os and m.tipo = p_tipo
   order by m.criada_em desc, m.id desc limit 1
$f$;
create function pg_temp.perg(p_id uuid) returns public.agenda_perguntas language sql stable as $f$
  select q.* from public.agenda_perguntas q where q.id = p_id
$f$;

-- Nenhuma órfã: pergunta cliente_aprovar aberta com a mensagem fora de aguardando_dono, nem mensagem pedida esperando com a
-- pergunta fechada.
create function pg_temp.orfas() returns int language sql stable as $f$
  select (select count(*)::int from public.agenda_perguntas q join public.agenda_cliente_mensagens m on m.pergunta_id = q.id
           where q.tipo = 'cliente_aprovar' and q.estado = 'aberta' and m.estado <> 'aguardando_dono')
       + (select count(*)::int from public.agenda_cliente_mensagens m join public.agenda_perguntas q on q.id = m.pergunta_id
           where m.estado = 'aguardando_dono' and m.aprovacao = 'pedida' and q.estado <> 'aberta')
$f$;

-- O retrato do que a limpeza grava (e do que ela poderia tocar): as perguntas, as propostas, as alocações, as mensagens e a fila,
-- linha a linha.
create function pg_temp.retrato() returns jsonb language sql stable as $f$
  select jsonb_build_object(
    'perguntas', (select coalesce(jsonb_agg(to_jsonb(q) order by q.id), '[]'::jsonb) from public.agenda_perguntas q),
    'propostas', (select coalesce(jsonb_agg(to_jsonb(p) order by p.id), '[]'::jsonb) from public.agenda_propostas p),
    'alocacoes', (select coalesce(jsonb_agg(to_jsonb(a) order by a.id), '[]'::jsonb) from public.agenda_alocacoes a),
    'mensagens', (select coalesce(jsonb_agg(to_jsonb(m) order by m.id), '[]'::jsonb) from public.agenda_cliente_mensagens m),
    'fila', (select coalesce(jsonb_agg(to_jsonb(w) order by w.id), '[]'::jsonb) from public.whatsapp_send_queue w))
$f$;

-- As perguntas que diferem entre dois retratos (pelo id), e se o resto é igual.
create function pg_temp.diferentes(p_a jsonb, p_b jsonb) returns text[] language sql immutable as $f$
  select coalesce(array_agg(coalesce(a.e ->> 'id', b.e ->> 'id') order by coalesce(a.e ->> 'id', b.e ->> 'id')), '{}')
    from jsonb_array_elements(p_a -> 'perguntas') a(e)
    full join jsonb_array_elements(p_b -> 'perguntas') b(e) on a.e ->> 'id' = b.e ->> 'id'
   where a.e is distinct from b.e
$f$;
create function pg_temp.resto_igual(p_a jsonb, p_b jsonb) returns boolean language sql immutable as $f$
  select (p_a - 'perguntas') = (p_b - 'perguntas')
$f$;

do $c$
declare
  v_res  jsonb := '[]'::jsonb;
  c_flav constant uuid := '05000000-0000-4000-8000-000000000104';
  c_luc  constant uuid := '05000000-0000-4000-8000-000000000122';
  c_rob  constant uuid := '05000000-0000-4000-8000-000000000121';
  c_cli_flav constant uuid := 'c1000000-0000-4000-8000-000000000004';
  c_cli_luc  constant uuid := 'c1000000-0000-4000-8000-000000000012';
  c_cli_rob  constant uuid := 'c1000000-0000-4000-8000-000000000007';
  c_dono constant uuid := 'aa000000-0000-4000-8000-000000000001';
  v_7a   text := coalesce(current_setting('agenda_teste.mig_perguntas_fase7a', true), '');
  r      jsonb;
  r2     jsonb;
  t      text;
  m      public.agenda_cliente_mensagens;
  q      public.agenda_perguntas;
  v_ql   uuid;   -- a pergunta da Lucenira (o pronto)
  v_qr   uuid;   -- a pergunta do Robson (o pós-serviço)
  v_ml   uuid;
  v_val  timestamptz;
  v_ok   boolean;
  v_n    int;
  v_a    jsonb;
  v_b    jsonb;
  v_ra   jsonb;
  v_rb   jsonb;
  v_dif  text[];
  v_ids  uuid[];
  v_ex   uuid;
  v_freio boolean;
begin
  if coalesce(current_setting('agenda_teste.fase5', true), '') = '' or v_7a = '' then
    insert into _resultado values ('C1–C8 (fixture-fase5)', true, 'PULADO: sem agenda_teste.fase5 / mig_perguntas_fase7a (rode pela bancada)');
    return;
  end if;
  begin
  execute current_setting('agenda_teste.fase5');
  -- a de antes, rodada como pg_temp (a âncora do C7): o corpo de 20261031100300, sem nenhuma mudança
  execute replace(pg_temp.inteira(v_7a, '_agenda_vigia_limpeza'), 'create or replace function public._agenda_vigia_limpeza(',
                  'create function pg_temp.limpeza_antes(');

  -- ── C1. O "ficou pronto" de OS concluída, com o OK pedido ──
  begin
    perform pg_temp.ligar(3);
    perform pg_temp.vig('2026-10-30 15:15');
    m := pg_temp.msg(c_luc, 'pronto');
    v_ql := m.pergunta_id;
    q := pg_temp.perg(v_ql);
    v_res := pg_temp.ok(v_res, 'C1a a cena: o "ficou pronto" da Lucenira (OS concluída às 15:00) espera o dono (pedida), com a pergunta cliente_aprovar aberta; a OS está fora da carteira (concluida)',
      m.estado = 'aguardando_dono' and m.aprovacao = 'pedida' and m.modo = 'ligado'
      and q.tipo = 'cliente_aprovar' and q.estado = 'aberta' and q.chave = 'cliente_aprovar:' || m.id and q.service_order_id = c_luc
      and public.os_prontidao(c_luc, date '2026-10-30') ->> 'estado' = 'concluida',
      format('%s %s %s; pergunta %s %s', m.estado, m.aprovacao, m.modo, q.tipo, q.estado));
    r := pg_temp.limpa('2026-10-30 15:30');
    q := pg_temp.perg(v_ql);
    v_res := pg_temp.ok(v_res, 'C1b a limpeza das 15:30 deixa a pergunta aberta (antes: resolvida, "a OS saiu da carteira")',
      q.estado = 'aberta' and q.resolvida_motivo is null and (pg_temp.msg(c_luc, 'pronto')).estado = 'aguardando_dono',
      format('%s %s; %s', q.estado, coalesce(q.resolvida_motivo, '-'), r));
    perform set_config('agenda_teste.hoje', '2026-10-30', true);
    r := public.agenda_vigiar(date '2026-10-30', pg_temp.em('2026-10-30 15:45'));
    q := pg_temp.perg(v_ql);
    v_res := pg_temp.ok(v_res, 'C1c um tique inteiro da vigia (agenda_vigiar, 15:45): a pergunta segue aberta, e o passo limpeza rodou sem erro',
      q.estado = 'aberta' and r #> '{contagens,limpeza}' is not null
      and not exists (select 1 from jsonb_array_elements(coalesce(r -> 'falhas', '[]'::jsonb)) f where f ->> 'passo' = 'limpeza'),
      format('%s; limpeza %s; falhas %s', q.estado, r #> '{contagens,limpeza}', r -> 'falhas'));
    perform set_config('agenda.agora', pg_temp.em('2026-10-30 17:30')::text, true);
    r := public._agenda_cliente_fechamento(date '2026-10-30');
    r2 := public._agenda_ver_decisoes(date '2026-10-30', pg_temp.em('2026-10-30 17:30'));
    perform set_config('agenda.agora', '', true);
    -- (em *agenda pendências*, a pergunta vem no texto ou, se o teto do foco a cortou, em dados.abertas, que leva todas as abertas)
    v_res := pg_temp.ok(v_res, 'C1d o fechamento do dia (a linha da mensagem que espera, com a pergunta) e *agenda pendências* mostram a mensagem com *manda cliente Lucenira*',
      exists (select 1 from jsonb_array_elements(r) e where e ->> 'pergunta_id' = v_ql::text and e ->> 'texto' like '%*manda cliente Lucenira*%')
      and (r2 ->> 'texto' like '%*manda cliente Lucenira*%'
           or exists (select 1 from jsonb_array_elements(coalesce(r2 #> '{dados,abertas}', '[]'::jsonb)) e where e ->> 'texto' like '%*manda cliente Lucenira*%')),
      left(r::text, 300) || ' | ' || left(coalesce(r2 ->> 'texto', '-'), 300));
    v_res := pg_temp.ok(v_res, 'C1e nenhuma órfã', pg_temp.orfas() = 0, pg_temp.orfas()::text);

    -- ── C2. *manda cliente Lucenira* ──
    begin
      perform set_config('agenda_teste.hoje', '2026-10-30', true);
      r := public.agenda_cliente_decidir_dito(c_dono, 'manda', 'Lucenira', 'whatsapp', date '2026-10-30', pg_temp.em('2026-10-30 15:50'));
      m := pg_temp.msg(c_luc, 'pronto');
      q := pg_temp.perg(v_ql);
      v_res := pg_temp.ok(v_res, 'C2a *manda cliente Lucenira*: "Mando para Lucenira agora.", a mensagem aprovada e enfileirada (a linha pendente da fila, com a chave dela), a pergunta respondida (1, as palavras, pelo WhatsApp)',
        (r ->> 'ok')::boolean and r ->> 'texto' = 'Mando para Lucenira agora.' and (r ->> 'decididas')::int = 1
        and m.estado = 'enfileirada' and m.aprovacao = 'aprovada' and m.aprovada_por = c_dono and m.fila_id is not null
        and exists (select 1 from public.whatsapp_send_queue w where w.id = m.fila_id and w.source = 'agenda-cliente'
                      and w.source_ref_id = m.id and w.status = 'pending' and w.dedupe_key = m.dedupe_key)
        and q.estado = 'respondida' and q.opcao_escolhida = 1 and q.respondida_via = 'whatsapp' and q.resposta = 'manda cliente Lucenira',
        r::text || ' | ' || m.estado || ' ' || m.aprovacao || ' | ' || q.estado);
      r := pg_temp.limpa('2026-10-30 16:00');
      v_res := pg_temp.ok(v_res, 'C2b relida depois da limpeza das 16:00: a pergunta segue respondida, a mensagem enfileirada; nenhuma órfã',
        (pg_temp.perg(v_ql)).estado = 'respondida' and (pg_temp.msg(c_luc, 'pronto')).estado = 'enfileirada' and pg_temp.orfas() = 0,
        (pg_temp.perg(v_ql)).estado || ' ' || (pg_temp.msg(c_luc, 'pronto')).estado);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- ── C3. *segura cliente Lucenira* ──
    begin
      perform set_config('agenda_teste.hoje', '2026-10-30', true);
      r := public.agenda_cliente_decidir_dito(c_dono, 'segura', 'Lucenira', 'whatsapp', date '2026-10-30', pg_temp.em('2026-10-30 15:50'));
      m := pg_temp.msg(c_luc, 'pronto');
      q := pg_temp.perg(v_ql);
      v_res := pg_temp.ok(v_res, 'C3 *segura cliente Lucenira*: "Segurei a mensagem de Lucenira: ela não sai.", a mensagem recusada (segurada), a pergunta respondida (2); nada na fila; nenhuma órfã',
        (r ->> 'ok')::boolean and r ->> 'texto' = 'Segurei a mensagem de Lucenira: ela não sai.'
        and m.estado = 'recusada' and m.recusa_motivo = 'segurada' and m.aprovacao = 'segurada'
        and q.estado = 'respondida' and q.opcao_escolhida = 2
        and not exists (select 1 from public.whatsapp_send_queue w where w.source_ref_id = m.id) and pg_temp.orfas() = 0,
        r::text || ' | ' || m.estado || ' ' || coalesce(m.recusa_motivo, '-') || ' | ' || q.estado);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- ── C4. Sem resposta: até a validade, aberta; depois, vencida (nas duas ordens) ──
    v_val := (pg_temp.msg(c_luc, 'pronto')).valida_ate;
    begin
      r := pg_temp.limpa(to_char((v_val - interval '1 minute') at time zone 'America/Sao_Paulo', 'YYYY-MM-DD HH24:MI'));
      q := pg_temp.perg(v_ql);
      v_ok := q.estado = 'aberta';
      t := q.estado;
      r := pg_temp.limpa(to_char((v_val + interval '1 minute') at time zone 'America/Sao_Paulo', 'YYYY-MM-DD HH24:MI'));
      q := pg_temp.perg(v_ql);
      r2 := pg_temp.vig(to_char((v_val + interval '2 minutes') at time zone 'America/Sao_Paulo', 'YYYY-MM-DD HH24:MI'));
      m := pg_temp.msg(c_luc, 'pronto');
      v_res := pg_temp.ok(v_res, 'C4a até a validade (1 min antes) a limpeza a deixa aberta; 1 min depois ela vence (vencida, pela validade) e o passo fila vence a mensagem (recusada, vencida); nenhuma órfã',
        v_ok and q.estado = 'vencida' and (r ->> 'vencidas')::int >= 1
        and m.estado = 'recusada' and m.recusa_motivo = 'vencida' and m.aprovacao = 'vencida' and (pg_temp.perg(v_ql)).estado = 'vencida'
        and pg_temp.orfas() = 0,
        format('validade %s; antes %s; depois %s; mensagem %s %s %s', v_val, t, q.estado, m.estado, m.recusa_motivo, m.aprovacao));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      r2 := pg_temp.vig(to_char((v_val + interval '1 minute') at time zone 'America/Sao_Paulo', 'YYYY-MM-DD HH24:MI'));
      q := pg_temp.perg(v_ql);
      r := pg_temp.limpa(to_char((v_val + interval '2 minutes') at time zone 'America/Sao_Paulo', 'YYYY-MM-DD HH24:MI'));
      m := pg_temp.msg(c_luc, 'pronto');
      v_res := pg_temp.ok(v_res, 'C4b na outra ordem (o passo fila antes): a mensagem e a pergunta vencem juntas ("a mensagem ao cliente venceu sem a resposta do dono"), e a limpeza depois não mexe; nenhuma órfã',
        q.estado = 'vencida' and q.resolvida_motivo = 'a mensagem ao cliente venceu sem a resposta do dono'
        and (pg_temp.perg(v_ql)).estado = 'vencida' and m.estado = 'recusada' and m.recusa_motivo = 'vencida' and pg_temp.orfas() = 0,
        format('%s %s; mensagem %s %s', q.estado, coalesce(q.resolvida_motivo, '-'), m.estado, m.recusa_motivo));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      -- no dia seguinte, antes da validade, os tiques da limpeza continuam a poupá-la
      r := pg_temp.limpa('2026-10-31 09:00');
      v_res := pg_temp.ok(v_res, 'C4c sáb 31/10 09:00 (antes da validade): a pergunta segue aberta', (pg_temp.perg(v_ql)).estado = 'aberta'
        and v_val > pg_temp.em('2026-10-31 09:00'), format('%s; validade %s', (pg_temp.perg(v_ql)).estado, v_val));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- ── C6. A mensagem que saiu de aguardando_dono por um caminho que não fecha a pergunta ──
    begin
      update public.agenda_cliente_mensagens set estado = 'recusada', recusa_motivo = 'status' where id = (pg_temp.msg(c_luc, 'pronto')).id;
      r := pg_temp.limpa('2026-10-30 16:00');
      q := pg_temp.perg(v_ql);
      v_res := pg_temp.ok(v_res, 'C6 a mensagem recusada por fora (a pergunta ficou aberta): a limpeza a fecha pela regra de antes ("a OS saiu da carteira"); nenhuma órfã',
        q.estado = 'resolvida' and q.resolvida_motivo = 'a OS saiu da carteira' and pg_temp.orfas() = 0,
        format('%s %s', q.estado, coalesce(q.resolvida_motivo, '-')));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── C5. O pós-serviço do Robson (OS concluída e entregue), com o OK pedido ──
  begin
    perform pg_temp.ligar(3);
    perform pg_temp.vig('2026-10-30 10:00');
    m := pg_temp.msg(c_rob, 'pos_servico');
    v_qr := m.pergunta_id;
    r := pg_temp.limpa('2026-10-30 10:15');
    q := pg_temp.perg(v_qr);
    v_ok := m.estado = 'aguardando_dono' and m.aprovacao = 'pedida' and q.tipo = 'cliente_aprovar' and q.estado = 'aberta'
            and public.os_prontidao(c_rob, date '2026-10-30') ->> 'estado' = 'concluida';
    t := format('%s %s; pergunta %s %s', m.estado, m.aprovacao, q.tipo, q.estado);
    perform set_config('agenda_teste.hoje', '2026-10-30', true);
    r := public.agenda_cliente_decidir_dito(c_dono, 'manda', 'Robson', 'whatsapp', date '2026-10-30', pg_temp.em('2026-10-30 10:20'));
    m := pg_temp.msg(c_rob, 'pos_servico');
    q := pg_temp.perg(v_qr);
    v_res := pg_temp.ok(v_res, 'C5 o pós-serviço do Robson (OS concluída) espera o dono; depois da limpeza das 10:15 a pergunta segue aberta, e *manda cliente Robson* o enfileira ("Mando para Robson agora.", a pergunta respondida)',
      v_ok and (r ->> 'ok')::boolean and r ->> 'texto' = 'Mando para Robson agora.' and m.estado = 'enfileirada'
      and exists (select 1 from public.whatsapp_send_queue w where w.id = m.fila_id and w.source_ref_id = m.id and w.status = 'pending')
      and q.estado = 'respondida' and q.opcao_escolhida = 1 and pg_temp.orfas() = 0,
      t || ' | ' || r::text || ' | ' || m.estado || ' | ' || q.estado);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── C7. As outras perguntas: a limpeza de agora × a de 20261031100300, linha a linha, com e sem o freio ──
  begin
    perform pg_temp.ligar(3);
    perform pg_temp.vig('2026-10-30 10:00');
    perform pg_temp.vig('2026-10-30 15:15');
    v_qr := (pg_temp.msg(c_rob, 'pos_servico')).pergunta_id;
    v_ql := (pg_temp.msg(c_luc, 'pronto')).pergunta_id;
    -- mais 9 perguntas abertas, de outros tipos e de outras situações (o que a limpeza fecha pela OS, pelo tipo ou deixa)
    -- (1) cliente_aprovar de OS da carteira (o Flávio), com a mensagem esperando: as duas deixam aberta
    v_ex := gen_random_uuid();
    v_ids := array[public._agenda_cliente_perguntar('cliente_aprovar', 'cliente_aprovar:' || v_ex, c_flav, date '2026-11-03', date '2026-11-02',
                     'Mensagem para Flávio (andamento), sai seg 02/11: "teste (C98)". *manda cliente Flávio* ou *segura cliente Flávio*.',
                     'ligado', pg_temp.em('2026-10-30 15:16'), pg_temp.em('2026-11-03 19:00'))];
    insert into public.agenda_cliente_mensagens (id, client_id, service_order_id, tipo, origem, modo, texto, enviar_em, valida_ate, aprovacao,
                                                 pergunta_id, estado, dedupe_key, criada_em)
    values (v_ex, c_cli_flav, c_flav, 'andamento', 'dono', 'ligado', 'teste (C98)', pg_temp.em('2026-11-03 09:00'),
            pg_temp.em('2026-11-03 19:00'), 'pedida', v_ids[1], 'aguardando_dono', 'agenda-cliente:c98:flavio', pg_temp.em('2026-10-30 15:16'));
    -- (2) cliente_aprovar de OS concluída cuja mensagem já não espera (recusada por fora): as duas fecham
    v_ex := gen_random_uuid();
    v_ids := v_ids || public._agenda_cliente_perguntar('cliente_aprovar', 'cliente_aprovar:' || v_ex, c_luc, date '2026-10-30', date '2026-10-30',
                        'Mensagem para Lucenira (andamento), sai hoje: "teste (C98)". *manda cliente Lucenira* ou *segura cliente Lucenira*.',
                        'ligado', pg_temp.em('2026-10-30 15:17'), pg_temp.em('2026-10-31 13:00'));
    insert into public.agenda_cliente_mensagens (id, client_id, service_order_id, tipo, origem, modo, texto, enviar_em, valida_ate, aprovacao,
                                                 pergunta_id, estado, recusa_motivo, dedupe_key, criada_em)
    values (v_ex, c_cli_luc, c_luc, 'andamento', 'dono', 'ligado', 'teste (C98)', pg_temp.em('2026-10-30 16:00'),
            pg_temp.em('2026-10-31 13:00'), 'pedida', v_ids[2], 'recusada', 'status', 'agenda-cliente:c98:lucenira', pg_temp.em('2026-10-30 15:17'));
    -- (3) cliente_aviso (crítica) de OS concluída, com a mensagem esperando: as duas fecham (só cliente_aprovar é poupada)
    v_ex := gen_random_uuid();
    v_ids := v_ids || public._agenda_cliente_perguntar('cliente_aviso', 'cliente_aviso:' || c_rob || ':2026-11-03', c_rob, date '2026-11-03', date '2026-11-03',
                        'A data que Robson ouviu passou sem aviso. Recomendo você ligar hoje. (C98)', 'ligado', pg_temp.em('2026-10-30 15:18'),
                        pg_temp.em('2026-11-03 19:00'));
    insert into public.agenda_cliente_mensagens (id, client_id, service_order_id, tipo, variante, origem, modo, texto, enviar_em, valida_ate,
                                                 aprovacao, pergunta_id, estado, dedupe_key, criada_em)
    values (v_ex, c_cli_rob, c_rob, 'pode_atrasar', 'execucao', 'rodada', 'ligado', 'teste (C98)', pg_temp.em('2026-11-03 09:00'),
            pg_temp.em('2026-11-03 19:00'), 'critica', v_ids[3], 'aguardando_dono', 'agenda-cliente:c98:robson', pg_temp.em('2026-10-30 15:18'));
    -- (4) cliente_resposta de OS concluída: as duas fecham
    v_ids := v_ids || public._agenda_cliente_perguntar('cliente_resposta', 'cliente_resposta:c98', c_luc, date '2026-10-30', null,
                        'Lucenira respondeu: "teste (C98)". (C98)', 'ligado', pg_temp.em('2026-10-30 15:19'), null);
    -- (5) a (8) as da vigia: parada, chegou, duracao e estouro de OS concluídas; (9) parada da carteira (o Flávio, que não está parado)
    insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, texto, modo, criada_em, expira_em)
    values ('parada', 'parada:' || c_luc, c_luc, array[c_luc], 'A OS da Lucenira está parada? (C98)', 'ligado', pg_temp.em('2026-10-30 15:20'), null),
           ('chegou', 'chegou:c98:2026-10-29', c_rob, array[c_rob], 'Chegou a peça do Robson? (C98)', 'ligado', pg_temp.em('2026-10-30 15:21'), null),
           ('duracao', 'duracao:' || c_luc, c_luc, array[c_luc], 'Quantos dias leva a OS da Lucenira? (C98)', 'ligado', pg_temp.em('2026-10-30 15:22'), null),
           ('estouro', 'estouro:' || c_rob || ':3', c_rob, array[c_rob], 'O Robson passou do combinado? (C98)', 'ligado', pg_temp.em('2026-10-30 15:23'), null),
           ('parada', 'parada:' || c_flav, c_flav, array[c_flav], 'A OS do Flávio está parada? (C98)', 'ligado', pg_temp.em('2026-10-30 15:24'), null);
    select count(*)::int into v_n from public.agenda_perguntas where estado = 'aberta';
    foreach v_freio in array array[false, true] loop
      update public.agenda_config set gestor_so_propor = v_freio where id;
      begin
        v_ra := pg_temp.limpa('2026-10-30 15:30');
        v_a := pg_temp.retrato();
        raise exception 'desfaz' using errcode = 'P0098';
      exception when sqlstate 'P0098' then null;
      end;
      begin
        perform set_config('agenda_teste.hoje', '2026-10-30', true);
        v_rb := pg_temp.limpeza_antes(date '2026-10-30', pg_temp.em('2026-10-30 15:30'));
        v_b := pg_temp.retrato();
        raise exception 'desfaz' using errcode = 'P0098';
      exception when sqlstate 'P0098' then null;
      end;
      v_dif := pg_temp.diferentes(v_a, v_b);
      v_res := pg_temp.ok(v_res, format('C7%s %s: %s perguntas abertas; a de agora × a de 20261031100300: diferem só as 2 poupadas (o pronto da Lucenira e o pós-serviço do Robson: abertas agora, "a OS saiu da carteira" antes); as propostas, as alocações, as mensagens e a fila iguais; "resolvidas" 2 a menos',
                                        case when v_freio then 'b' else 'a' end, case when v_freio then 'com o freio' else 'sem o freio' end, v_n),
        v_dif = (select array_agg(x order by x) from unnest(array[v_ql::text, v_qr::text]) x)
        and pg_temp.resto_igual(v_a, v_b)
        and (select bool_and(e ->> 'estado' = 'aberta') from jsonb_array_elements(v_a -> 'perguntas') e where (e ->> 'id')::uuid in (v_ql, v_qr))
        and (select bool_and(e ->> 'estado' = 'resolvida' and e ->> 'resolvida_motivo' = 'a OS saiu da carteira')
               from jsonb_array_elements(v_b -> 'perguntas') e where (e ->> 'id')::uuid in (v_ql, v_qr))
        and (v_ra - 'resolvidas') = (v_rb - 'resolvidas') and (v_rb ->> 'resolvidas')::int - (v_ra ->> 'resolvidas')::int = 2,
        format('diferentes %s; agora %s; antes %s', array_length(v_dif, 1), v_ra, v_rb));
    end loop;
    -- as 9 de fora, uma a uma, no retrato de agora (o último, com o freio); a parada do Flávio fica como a de antes a deixar (C7a e C7b)
    v_res := pg_temp.ok(v_res, 'C7c as 9 de fora, na de agora: a cliente_aprovar do Flávio (da carteira, esperando) aberta; a cliente_aprovar sem mensagem esperando, a cliente_aviso, a cliente_resposta e as 4 da vigia de OS concluída fecham ("a OS saiu da carteira")',
      (select bool_and(case when (e ->> 'id')::uuid = v_ids[1] then e ->> 'estado' = 'aberta'
                            else e ->> 'estado' = 'resolvida' and e ->> 'resolvida_motivo' = 'a OS saiu da carteira' end)
         from jsonb_array_elements(v_a -> 'perguntas') e where (e ->> 'id')::uuid = any (v_ids))
      and (select count(*) from jsonb_array_elements(v_a -> 'perguntas') e where (e ->> 'id')::uuid = any (v_ids)) = 4
      and (select count(*) from jsonb_array_elements(v_a -> 'perguntas') e
            where e ->> 'chave' in ('parada:' || c_luc, 'chegou:c98:2026-10-29', 'duracao:' || c_luc, 'estouro:' || c_rob || ':3')
              and e ->> 'estado' = 'resolvida' and e ->> 'resolvida_motivo' = 'a OS saiu da carteira') = 4
      and cardinality(v_ids) = 4,
      (select string_agg(e ->> 'tipo' || '=' || (e ->> 'estado') || ':' || coalesce(e ->> 'resolvida_motivo', ''), '; ' order by e ->> 'criada_em')
         from jsonb_array_elements(v_a -> 'perguntas') e where (e ->> 'criada_em')::timestamptz >= pg_temp.em('2026-10-30 15:16')));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── C8. Sem o conserto: a definição de 20261031100300 de volta (numa subtransação) ──
  begin
    execute pg_temp.inteira(v_7a, '_agenda_vigia_limpeza');
    perform pg_temp.ligar(3);
    perform pg_temp.vig('2026-10-30 15:15');
    m := pg_temp.msg(c_luc, 'pronto');
    v_ql := m.pergunta_id;
    r := pg_temp.limpa('2026-10-30 15:30');
    q := pg_temp.perg(v_ql);
    perform set_config('agenda_teste.hoje', '2026-10-30', true);
    r := public.agenda_cliente_decidir_dito(c_dono, 'manda', 'Lucenira', 'whatsapp', date '2026-10-30', pg_temp.em('2026-10-30 15:50'));
    m := pg_temp.msg(c_luc, 'pronto');
    -- (as órfãs são 2: o pronto da Lucenira e o pós-serviço do Robson, que o tique das 15:15 registrou para ter 03/11 09:00, também pedido)
    v_res := pg_temp.ok(v_res, 'C8 sem o conserto, a mesma cena: a limpeza fecha a pergunta ("a OS saiu da carteira"), o *manda* responde "Essa pergunta já foi respondida ou resolvida." e a mensagem segue esperando, sem fila (2 órfãs: o pronto e o pós-serviço): as condições do C1b, do C1e e do C2a dão falso',
      q.estado = 'resolvida' and q.resolvida_motivo = 'a OS saiu da carteira'
      and r ->> 'texto' = 'Essa pergunta já foi respondida ou resolvida.' and m.estado = 'aguardando_dono' and m.fila_id is null
      and pg_temp.orfas() = 2
      and not (q.estado = 'aberta')
      and not (m.estado = 'enfileirada' and r ->> 'texto' = 'Mando para Lucenira agora.'),
      format('%s %s | %s | %s', q.estado, coalesce(q.resolvida_motivo, '-'), r, m.estado));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  v_res := pg_temp.ok(v_res, 'C8b depois da subtransação, a definição viva é a da correção de novo (com o bloco)',
    (select p.prosrc like '%-- CORREÇÃO 10/11 (98): fim%' from pg_proc p where p.oid = 'public._agenda_vigia_limpeza(date, timestamptz)'::regprocedure),
    null);

    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$c$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
