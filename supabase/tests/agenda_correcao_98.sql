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
--   C9  (a conferência de 10/11) a matriz: todo tipo de mensagem ao cliente (a lista fechada da tabela) × a OS fora da carteira
--       de 7 jeitos (concluída, concluída e entregue, faturada, faturada e entregue, cancelada, juntada, rascunho), com a mensagem
--       esperando o dono: depois da limpeza, a pergunta fica aberta se e só se a revalidação de verdade (_agenda_cliente_revalidar,
--       a que recusa a mensagem na hora de sair) não diz "status" — 8 de 91: o pronto e o lembrete de OS concluída ou faturada e
--       não entregue, o pós-serviço de OS concluída ou faturada; com e sem o freio; a cliente_aviso (crítica) de pronto e de
--       pós-serviço fecha nos 7 (só cliente_aprovar é poupada); e a de 20261031100300 fecha todas
--   C10 (a conferência de 10/11) a cena dela na fixture: a véspera do Flávio pedida pela rodada e a OS cancelada (ou concluída)
--       antes do OK, e o "ficou pronto" da Lucenira com a OS entregue antes do OK: a limpeza fecha a pergunta ("a OS saiu da
--       carteira"), o fechamento, *agenda pendências* e a ordem não a mostram, o *manda* não promete ("Mando para …") nem manda
--       ligar, e na hora de sair não nasce pergunta "não saiu" (a 1ª versão da 98, de 9abb46f0, deixava tudo isso acontecer)
--   C11 (a reconferência de 10/11) a OS da mensagem poupada volta do concluído para a carteira: o "ficou pronto" da Lucenira
--       poupado e a OS reaberta pela porta de verdade (os_transicionar_status, pela tela) para em andamento, aguardando peças ou
--       aguardando o cliente; o pós-serviço do Robson (para ter 03/11 09:00) e a OS reaberta: a limpeza seguinte fecha a pergunta
--       com o motivo próprio ("a OS não está mais concluída: a mensagem ao cliente não sai"), o fechamento, *agenda pendências* e a
--       ordem não a mostram, o *manda* não promete nem manda ligar, e na hora de sair não nasce "não saiu" (a 2ª versão, de
--       e387cb93, deixava a pergunta aberta até a validade); a OS reaberta antes da 1ª limpeza (o caminho de antes da 98) fecha
--       igual; a matriz da carteira (13 tipos × 7 estados da OS na carteira) contra a de 20261031100300 e a revalidação de verdade:
--       mudam só o pronto, o lembrete e o pós-serviço; e a OS concluída ou faturada e congelada (a prontidão diz congelada) deixa a
--       pergunta do pronto aberta (o status deixa sair)
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

-- (C9) O estado de cada pergunta dada, pelo tipo dela e o da mensagem dela:
-- {"cliente_aprovar/pronto": "aberta:", "cliente_aprovar/vespera": "resolvida:a OS saiu da carteira", …}.
create function pg_temp.c9_estados(p_ids uuid[]) returns jsonb language sql stable as $f$
  select coalesce(jsonb_object_agg(q.tipo || '/' || m.tipo, q.estado || ':' || coalesce(q.resolvida_motivo, '')), '{}'::jsonb)
    from public.agenda_cliente_mensagens m join public.agenda_perguntas q on q.id = m.pergunta_id
   where q.id = any (p_ids)
$f$;

-- (C10) A pergunta aparece numa leitura (um jsonb qualquer: o fechamento, as linhas dele, *agenda pendências*, a ordem)? Pelo id
-- ou pelas palavras *manda cliente <nome>*.
create function pg_temp.mostra(p_leitura jsonb, p_id uuid, p_nome text) returns boolean language sql immutable as $f$
  select coalesce(p_leitura::text like '%' || p_id::text || '%' or p_leitura::text like '%*manda cliente ' || p_nome || '*%', false)
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
  v_tipos text[];   -- (C9) os tipos de mensagem ao cliente (a lista fechada da tabela)
  v_est  text;      -- (C9, C10) o estado da OS
  v_rev  jsonb;     -- (C9) a revalidação de verdade, pelo tipo
  v_c    jsonb;
  v_lin  text[];    -- (C9) uma linha por mensagem: estado da OS|tipo|prontidão|revalidação|agora sem o freio|agora com o freio|a de antes
  v_pr   text;
  v_alvo text;      -- (C11) o status para onde a OS é reaberta
  v_k    int;       -- (C11) o número da volta
  -- (C11) o motivo próprio da pergunta do pronto, do lembrete e do pós-serviço de OS que voltou para a carteira
  c_mot_reaberta constant text := 'a OS não está mais concluída: a mensagem ao cliente não sai';
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

  -- ── C9. A matriz (a conferência de 10/11): fica aberta só a pergunta da mensagem que a regra do status ainda deixa sair ──
  -- A âncora é a revalidação de verdade (_agenda_cliente_revalidar, a que recusa a mensagem na hora de sair), chamada antes da
  -- limpeza. O que vem antes do status nela (o d10) e o que o esconde (o M11 e a semana em teste dizem tipo_em_teste antes) fica
  -- fora do caminho: conversa sem prazo, o M11 desde 01/10, as camadas ligadas, sem o freio. Assim ela diz "status" ou outra
  -- coisa só pelo status da OS.
  begin
    perform pg_temp.ligar(3);
    update public.agenda_config set cliente_conversa_dias = 0, onde_fica_desde = date '2026-10-01', modo_cliente_camadas = 'ligado',
                                    gestor_so_propor = false where id;
    select array_agg(x[1] order by x[1]) into v_tipos
      from regexp_matches((select pg_get_constraintdef(c.oid) from pg_constraint c
                            where c.conrelid = 'public.agenda_cliente_mensagens'::regclass
                              and c.conname = 'agenda_cliente_mensagens_tipo_check'), '''([a-z_]+)''', 'g') x;
    v_lin := '{}';
    foreach v_est in array array['concluida', 'concluida_entregue', 'faturada', 'faturada_entregue', 'cancelada', 'juntada', 'rascunho'] loop
      begin
        -- a OS do Flávio (da carteira) sai dela; a entrega só pela porta, a junção só com a marca das funções de agrupar
        perform set_config('agenda.porta', 'on', true);
        perform set_config('marineflow.agrupar_orcamentos', 'on', true);
        update public.service_orders
           set status = case when v_est like 'concluida%' then 'completed' when v_est like 'faturada%' then 'invoiced'
                             when v_est = 'rascunho' then 'draft' else 'cancelled' end,
               quote_status = case when v_est = 'rascunho' then 'draft' else quote_status end,
               check_out_at = case when v_est like '%entregue' then coalesce(check_out_at, pg_temp.em('2026-10-30 08:00')) else check_out_at end,
               delivered_at = case when v_est like '%entregue' then pg_temp.em('2026-10-30 09:00') end,
               merged_into_id = case when v_est = 'juntada' then c_rob end
         where id = c_flav;
        perform set_config('agenda.porta', 'off', true);
        perform set_config('marineflow.agrupar_orcamentos', 'off', true);
        -- uma mensagem de cada tipo esperando o dono, cada uma com a pergunta cliente_aprovar aberta (como a do C7); e 2 com a
        -- pergunta cliente_aviso (a crítica, como a do C7), de pronto e de pós-serviço: só cliente_aprovar é poupada
        v_ids := '{}';
        foreach t in array v_tipos || array['aviso:pronto', 'aviso:pos_servico'] loop
          v_ex := gen_random_uuid();
          v_ids := v_ids || public._agenda_cliente_perguntar(case when t like 'aviso:%' then 'cliente_aviso' else 'cliente_aprovar' end,
                              case when t like 'aviso:%' then 'cliente_aviso:' else 'cliente_aprovar:' end || v_ex, c_flav, date '2026-11-03',
                              date '2026-11-02', format('Mensagem para Flávio (%s), sai seg 02/11: "teste (C98, C9)". *manda cliente Flávio* ou *segura cliente Flávio*.', t),
                              'ligado', pg_temp.em('2026-10-30 10:00'), pg_temp.em('2026-11-03 19:00'));
          insert into public.agenda_cliente_mensagens (id, client_id, service_order_id, tipo, origem, modo, texto, enviar_em, valida_ate,
                                                       aprovacao, pergunta_id, estado, dedupe_key, criada_em)
          values (v_ex, c_cli_flav, c_flav, replace(t, 'aviso:', ''), 'rodada', 'ligado', 'teste (C98, C9)', pg_temp.em('2026-11-02 09:00'),
                  pg_temp.em('2026-11-03 19:00'), case when t like 'aviso:%' then 'critica' else 'pedida' end, v_ids[cardinality(v_ids)],
                  'aguardando_dono', 'agenda-cliente:c98:c9:' || t, pg_temp.em('2026-10-30 10:00'));
        end loop;
        perform set_config('agenda_teste.hoje', '2026-10-30', true);
        select jsonb_object_agg(qq.tipo || '/' || mm.tipo, coalesce(public._agenda_cliente_revalidar(mm.id, pg_temp.em('2026-10-30 10:15')), 'sai'))
          into v_rev
          from public.agenda_cliente_mensagens mm join public.agenda_perguntas qq on qq.id = mm.pergunta_id where qq.id = any (v_ids);
        v_pr := public.os_prontidao(c_flav, date '2026-10-30') ->> 'estado';
        -- a de agora, sem e com o freio; e a de 20261031100300 (a âncora do "como antes")
        foreach v_freio in array array[false, true] loop
          begin
            update public.agenda_config set gestor_so_propor = v_freio where id;
            r := pg_temp.limpa('2026-10-30 10:15');
            if v_freio then v_b := pg_temp.c9_estados(v_ids); else v_a := pg_temp.c9_estados(v_ids); end if;
            raise exception 'desfaz' using errcode = 'P0098';
          exception when sqlstate 'P0098' then null;
          end;
        end loop;
        begin
          r := pg_temp.limpeza_antes(date '2026-10-30', pg_temp.em('2026-10-30 10:15'));
          v_c := pg_temp.c9_estados(v_ids);
          raise exception 'desfaz' using errcode = 'P0098';
        exception when sqlstate 'P0098' then null;
        end;
        v_lin := v_lin || (select array_agg(format('%s|%s|%s|%s|%s|%s|%s', v_est, k, v_pr, v_rev ->> k, v_a ->> k, v_b ->> k, v_c ->> k) order by k)
                             from jsonb_object_keys(v_rev) k);
        raise exception 'desfaz' using errcode = 'P0098';
      exception when sqlstate 'P0098' then null;
      end;
    end loop;
    -- as linhas: 1 estado da OS | 2 pergunta/mensagem | 3 prontidão | 4 revalidação | 5 agora sem o freio | 6 agora com o freio | 7 a de antes
    -- (91 cliente_aprovar: 13 tipos × 7; e 14 cliente_aviso: pronto e pós-serviço × 7)
    v_res := pg_temp.ok(v_res, 'C9a a cena: os 13 tipos da lista fechada × a OS fora da carteira de 7 jeitos = 91 mensagens esperando o dono com a pergunta cliente_aprovar aberta (e 14 com a cliente_aviso); a prontidão diz concluida nas concluídas e faturadas e fora_da_carteira na cancelada, na juntada e no rascunho; a de 20261031100300 fecha as 105 ("a OS saiu da carteira")',
      cardinality(v_tipos) = 13
      and v_tipos @> array['pronto', 'pronto_lembrete', 'pos_servico', 'onde_fica', 'semana', 'vespera', 'confirmar', 'andamento', 'pode_atrasar']
      and cardinality(v_lin) = 105
      and (select count(*) from unnest(v_lin) l where split_part(l, '|', 2) like 'cliente_aprovar/%') = 91
      and (select bool_and(split_part(l, '|', 3) = case when split_part(l, '|', 1) like 'concluida%' or split_part(l, '|', 1) like 'faturada%'
                                                       then 'concluida' else 'fora_da_carteira' end
                           and split_part(l, '|', 7) = 'resolvida:a OS saiu da carteira')
             from unnest(v_lin) l),
      format('%s tipos, %s linhas; prontidão: %s; a de antes: %s', cardinality(v_tipos), cardinality(v_lin),
             (select string_agg(distinct split_part(l, '|', 1) || '=' || split_part(l, '|', 3), ', ') from unnest(v_lin) l),
             (select string_agg(distinct split_part(l, '|', 7), ', ') from unnest(v_lin) l)));
    v_res := pg_temp.ok(v_res, 'C9b a de agora (sem o freio): a pergunta cliente_aprovar fica aberta se e só se a revalidação de verdade não diz "status", nas 91; as outras fecham como antes ("a OS saiu da carteira"); as abertas são as 8 em que o status deixa sair: o pronto e o lembrete de OS concluída ou faturada não entregue, o pós-serviço de OS concluída ou faturada',
      (select bool_and(case when split_part(l, '|', 4) = 'status' then split_part(l, '|', 5) = 'resolvida:a OS saiu da carteira'
                            else split_part(l, '|', 5) = 'aberta:' end)
         from unnest(v_lin) l where split_part(l, '|', 2) like 'cliente_aprovar/%')
      and (select array_agg(x order by x collate "C")
             from (select split_part(l, '|', 1) || ':' || split_part(l, '|', 2) x from unnest(v_lin) l where split_part(l, '|', 5) = 'aberta:') s)
          = array['concluida:cliente_aprovar/pos_servico', 'concluida:cliente_aprovar/pronto', 'concluida:cliente_aprovar/pronto_lembrete',
                  'concluida_entregue:cliente_aprovar/pos_servico', 'faturada:cliente_aprovar/pos_servico', 'faturada:cliente_aprovar/pronto',
                  'faturada:cliente_aprovar/pronto_lembrete', 'faturada_entregue:cliente_aprovar/pos_servico'],
      format('abertas: %s; a revalidação diz: %s; divergências: %s',
             (select string_agg(split_part(l, '|', 1) || ':' || split_part(l, '|', 2), ', ' order by l) from unnest(v_lin) l where split_part(l, '|', 5) = 'aberta:'),
             (select string_agg(x || ' ' || n, ', ' order by x) from (select split_part(l, '|', 4) x, count(*) n from unnest(v_lin) l
                                                                      where split_part(l, '|', 2) like 'cliente_aprovar/%' group by 1) s),
             coalesce((select string_agg(l, '; ' order by l) from unnest(v_lin) l
                        where split_part(l, '|', 2) like 'cliente_aprovar/%'
                          and (split_part(l, '|', 4) = 'status') = (split_part(l, '|', 5) = 'aberta:')), '-')));
    v_res := pg_temp.ok(v_res, 'C9c com o freio, a de agora decide o mesmo nas 105',
      (select bool_and(split_part(l, '|', 5) = split_part(l, '|', 6)) from unnest(v_lin) l) and cardinality(v_lin) = 105,
      coalesce((select string_agg(l, '; ' order by l) from unnest(v_lin) l where split_part(l, '|', 5) <> split_part(l, '|', 6)), '-'));
    v_res := pg_temp.ok(v_res, 'C9d a cliente_aviso (a crítica) de pronto e de pós-serviço fecha como antes nos 7 estados, também onde o status deixaria a mensagem sair: só cliente_aprovar é poupada',
      (select count(*) from unnest(v_lin) l where split_part(l, '|', 2) like 'cliente_aviso/%'
                                              and split_part(l, '|', 5) = 'resolvida:a OS saiu da carteira'
                                              and split_part(l, '|', 5) = split_part(l, '|', 7)) = 14,
      (select string_agg(split_part(l, '|', 1) || ':' || split_part(l, '|', 2) || '=' || split_part(l, '|', 5), ', ' order by l)
         from unnest(v_lin) l where split_part(l, '|', 2) like 'cliente_aviso/%'));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── C10. A cena da conferência (10/11) na fixture: a mensagem que já não pode sair não deixa a pergunta aberta ──
  -- (1, 2) a véspera do Flávio (ter 03/11; sai seg 02/11 09:00) pedida pela rodada (o tipo ainda não liberado: 3 dias de aprovação),
  -- e a OS cancelada (1) ou concluída (2) às 10:05, antes do OK
  foreach v_est in array array['cancelled', 'completed'] loop
    begin
      perform pg_temp.ligar(3);
      perform set_config('agenda_teste.hoje', '2026-10-30', true);
      r := public._agenda_cliente_registrar('vespera', null, c_flav, date '2026-11-03', '{}'::jsonb, pg_temp.em('2026-11-02 09:00'),
                                            null, 'rodada', null, pg_temp.em('2026-10-30 09:30'));
      v_ml := (r ->> 'id')::uuid;
      select x.* into m from public.agenda_cliente_mensagens x where x.id = v_ml;
      v_ql := m.pergunta_id;
      v_ok := m.estado = 'aguardando_dono' and m.aprovacao = 'pedida' and m.modo = 'ligado' and (pg_temp.perg(v_ql)).estado = 'aberta';
      t := format('nasceu %s/%s/%s, pergunta %s', m.estado, m.aprovacao, m.modo, (pg_temp.perg(v_ql)).estado);
      update public.service_orders
         set status = v_est, check_out_at = case when v_est = 'completed' then coalesce(check_out_at, pg_temp.em('2026-10-30 10:05')) else check_out_at end
       where id = c_flav;
      v_pr := coalesce(public._agenda_cliente_revalidar(v_ml, pg_temp.em('2026-10-30 10:10')), 'sai');
      r := pg_temp.limpa('2026-10-30 10:15');
      q := pg_temp.perg(v_ql);
      v_res := pg_temp.ok(v_res, format('C10a%s a véspera do Flávio pedida pela rodada, e a OS %s antes do OK (a revalidação já diz "status"): a limpeza seguinte fecha a pergunta ("a OS saiu da carteira")',
                                        case v_est when 'cancelled' then '1' else '2' end, case v_est when 'cancelled' then 'cancelada' else 'concluída' end),
        v_ok and v_pr = 'status' and q.estado = 'resolvida' and q.resolvida_motivo = 'a OS saiu da carteira' and (r ->> 'resolvidas')::int >= 1,
        format('%s; revalidação %s; 10:15 %s %s; limpeza %s', t, v_pr, q.estado, coalesce(q.resolvida_motivo, '-'), r));
      perform set_config('agenda.agora', pg_temp.em('2026-10-30 17:30')::text, true);
      v_a := public._agenda_cliente_fechamento(date '2026-10-30');
      v_b := public._agenda_linhas_do_fechamento(date '2026-10-30');
      r2 := public._agenda_ver_decisoes(date '2026-10-30', pg_temp.em('2026-10-30 17:30'));
      v_c := public.agenda_perguntas_em_ordem(date '2026-10-30', pg_temp.em('2026-10-30 17:30'));
      perform set_config('agenda.agora', '', true);
      v_res := pg_temp.ok(v_res, format('C10b%s 17:30: o fechamento do dia (a linha da mensagem e as linhas do fechamento), *agenda pendências* e a ordem das perguntas não a mostram',
                                        case v_est when 'cancelled' then '1' else '2' end),
        not pg_temp.mostra(v_a, v_ql, 'Flávio') and not pg_temp.mostra(v_b, v_ql, 'Flávio')
        and not pg_temp.mostra(r2, v_ql, 'Flávio') and not pg_temp.mostra(v_c, v_ql, 'Flávio')
        and jsonb_typeof(v_b) = 'array' and jsonb_typeof(v_c) = 'array',
        format('mensagem %s, linhas %s, pendências %s, ordem %s', pg_temp.mostra(v_a, v_ql, 'Flávio'), pg_temp.mostra(v_b, v_ql, 'Flávio'),
               pg_temp.mostra(r2, v_ql, 'Flávio'), pg_temp.mostra(v_c, v_ql, 'Flávio')));
      r := public.agenda_cliente_decidir_dito(c_dono, 'manda', 'Flávio', 'whatsapp', date '2026-10-30', pg_temp.em('2026-10-30 17:35'));
      select x.* into m from public.agenda_cliente_mensagens x where x.id = v_ml;
      v_res := pg_temp.ok(v_res, format('C10c%s 17:35 *manda cliente Flávio*: não promete ("Mando para Flávio …"); a mensagem segue pedida, sem aprovação e sem fila',
                                        case v_est when 'cancelled' then '1' else '2' end),
        coalesce(r ->> 'texto', '') not like '%Mando para Flávio%' and m.aprovacao = 'pedida' and m.estado = 'aguardando_dono' and m.fila_id is null,
        r::text || ' | ' || m.estado || ' ' || m.aprovacao);
      r2 := pg_temp.vig('2026-11-02 09:00');
      select x.* into m from public.agenda_cliente_mensagens x where x.id = v_ml;
      v_res := pg_temp.ok(v_res, format('C10d%s seg 02/11 09:00, a hora de sair: nenhuma pergunta "não saiu" para ela, e ela não foi à fila',
                                        case v_est when 'cancelled' then '1' else '2' end),
        not exists (select 1 from public.agenda_perguntas x where x.chave = 'cliente_resposta:nao_saiu:' || v_ml)
        and not exists (select 1 from public.whatsapp_send_queue w where w.source_ref_id = v_ml)
        and m.estado not in ('enfileirada', 'enviada') and m.aprovacao <> 'aprovada',
        format('mensagem %s/%s/%s', m.estado, m.aprovacao, coalesce(m.recusa_motivo, '-')));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
  end loop;
  -- (3) o "ficou pronto" da Lucenira (OS concluída às 15:00) esperando o OK, e a OS entregue às 16:00, antes do OK
  begin
    perform pg_temp.ligar(3);
    perform pg_temp.vig('2026-10-30 15:15');
    m := pg_temp.msg(c_luc, 'pronto');
    v_ml := m.id;
    v_ql := m.pergunta_id;
    v_ok := m.estado = 'aguardando_dono' and m.aprovacao = 'pedida' and (pg_temp.perg(v_ql)).estado = 'aberta';
    perform set_config('agenda.porta', 'on', true);
    update public.service_orders set delivered_at = pg_temp.em('2026-10-30 16:00') where id = c_luc;
    perform set_config('agenda.porta', 'off', true);
    v_pr := coalesce(public._agenda_cliente_revalidar(v_ml, pg_temp.em('2026-10-30 16:10')), 'sai');
    r := pg_temp.limpa('2026-10-30 16:15');
    q := pg_temp.perg(v_ql);
    v_res := pg_temp.ok(v_res, 'C10e o "ficou pronto" da Lucenira esperando o OK, e a OS entregue às 16:00 (a revalidação já diz "status"): a limpeza das 16:15 fecha a pergunta ("a OS saiu da carteira")',
      v_ok and v_pr = 'status' and q.estado = 'resolvida' and q.resolvida_motivo = 'a OS saiu da carteira',
      format('revalidação %s; 16:15 %s %s; limpeza %s', v_pr, q.estado, coalesce(q.resolvida_motivo, '-'), r));
    perform set_config('agenda.agora', pg_temp.em('2026-10-30 17:30')::text, true);
    v_a := public._agenda_cliente_fechamento(date '2026-10-30');
    v_b := public._agenda_linhas_do_fechamento(date '2026-10-30');
    r2 := public._agenda_ver_decisoes(date '2026-10-30', pg_temp.em('2026-10-30 17:30'));
    v_c := public.agenda_perguntas_em_ordem(date '2026-10-30', pg_temp.em('2026-10-30 17:30'));
    perform set_config('agenda.agora', '', true);
    v_res := pg_temp.ok(v_res, 'C10f 17:30: o fechamento do dia, *agenda pendências* e a ordem das perguntas não a mostram',
      not pg_temp.mostra(v_a, v_ql, 'Lucenira') and not pg_temp.mostra(v_b, v_ql, 'Lucenira')
      and not pg_temp.mostra(r2, v_ql, 'Lucenira') and not pg_temp.mostra(v_c, v_ql, 'Lucenira'),
      format('mensagem %s, linhas %s, pendências %s, ordem %s', pg_temp.mostra(v_a, v_ql, 'Lucenira'), pg_temp.mostra(v_b, v_ql, 'Lucenira'),
             pg_temp.mostra(r2, v_ql, 'Lucenira'), pg_temp.mostra(v_c, v_ql, 'Lucenira')));
    r := public.agenda_cliente_decidir_dito(c_dono, 'manda', 'Lucenira', 'whatsapp', date '2026-10-30', pg_temp.em('2026-10-30 17:35'));
    m := pg_temp.msg(c_luc, 'pronto');
    v_res := pg_temp.ok(v_res, 'C10g 17:35 *manda cliente Lucenira*: não promete nem manda ligar ("Não mandei … Recomendo ligar."); a mensagem segue esperando, sem fila; nenhuma pergunta "não saiu"',
      coalesce(r ->> 'texto', '') not like '%Mando para Lucenira%' and coalesce(r ->> 'texto', '') not like '%Recomendo ligar%'
      and m.estado = 'aguardando_dono' and m.fila_id is null
      and not exists (select 1 from public.agenda_perguntas x where x.chave = 'cliente_resposta:nao_saiu:' || v_ml),
      r::text || ' | ' || m.estado || ' ' || m.aprovacao);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── C11. A OS da mensagem poupada volta do concluído para a carteira (a reconferência de 10/11) ──
  -- (1, 2, 3) o "ficou pronto" da Lucenira (OS concluída às 15:00) esperando o OK, poupado pela limpeza das 15:30; às 16:00 a OS é
  -- reaberta pela porta de verdade (os_transicionar_status, pela tela, o dono) para em andamento, aguardando peças ou aguardando o
  -- cliente. A revalidação já diz "status": a mensagem não sai mais. A limpeza das 16:15 fecha a pergunta com o motivo próprio.
  v_k := 0;
  foreach v_alvo in array array['in_progress', 'awaiting_parts', 'awaiting_client'] loop
    v_k := v_k + 1;
    begin
      perform pg_temp.ligar(3);
      perform pg_temp.vig('2026-10-30 15:15');
      m := pg_temp.msg(c_luc, 'pronto');
      v_ml := m.id;
      v_ql := m.pergunta_id;
      r := pg_temp.limpa('2026-10-30 15:30');
      v_ok := m.estado = 'aguardando_dono' and m.aprovacao = 'pedida' and (pg_temp.perg(v_ql)).estado = 'aberta';
      t := format('15:30 %s', (pg_temp.perg(v_ql)).estado);
      perform set_config('agenda_teste.hoje', '2026-10-30', true);
      r := public.os_transicionar_status(c_luc, v_alvo, 'tela', 'C98: reaberta', c_dono, null, date '2026-10-30',
                                         pg_temp.em('2026-10-30 16:00'), null);
      v_pr := coalesce(public._agenda_cliente_revalidar(v_ml, pg_temp.em('2026-10-30 16:10')), 'sai');
      t := t || format('; porta %s "%s"; status %s; prontidão %s; revalidação %s', r ->> 'ok', r ->> 'texto',
                       (select so.status from public.service_orders so where so.id = c_luc),
                       public.os_prontidao(c_luc, date '2026-10-30') ->> 'estado', v_pr);
      v_ok := v_ok and coalesce((r ->> 'ok')::boolean, false)
              and (select so.status from public.service_orders so where so.id = c_luc) = v_alvo
              and public.os_prontidao(c_luc, date '2026-10-30') ->> 'estado' not in ('concluida', 'fora_da_carteira') and v_pr = 'status';
      r := pg_temp.limpa('2026-10-30 16:15');
      q := pg_temp.perg(v_ql);
      v_res := pg_temp.ok(v_res, format('C11a%s o "ficou pronto" da Lucenira poupado (aberto às 15:30) e a OS reaberta às 16:00 pela porta para %s (a revalidação já diz "status"): a limpeza das 16:15 fecha a pergunta com o motivo próprio ("%s"); a mensagem segue esperando, sem sair',
                                        v_k, v_alvo, c_mot_reaberta),
        v_ok and q.estado = 'resolvida' and q.resolvida_motivo = c_mot_reaberta and (r ->> 'resolvidas')::int >= 1
        and (pg_temp.msg(c_luc, 'pronto')).estado = 'aguardando_dono',
        format('%s; 16:15 %s %s; limpeza %s', t, q.estado, coalesce(q.resolvida_motivo, '-'), r));
      perform set_config('agenda.agora', pg_temp.em('2026-10-30 17:30')::text, true);
      v_a := public._agenda_cliente_fechamento(date '2026-10-30');
      v_b := public._agenda_linhas_do_fechamento(date '2026-10-30');
      r2 := public._agenda_ver_decisoes(date '2026-10-30', pg_temp.em('2026-10-30 17:30'));
      v_c := public.agenda_perguntas_em_ordem(date '2026-10-30', pg_temp.em('2026-10-30 17:30'));
      perform set_config('agenda.agora', '', true);
      v_res := pg_temp.ok(v_res, format('C11b%s 17:30 (OS %s): o fechamento do dia (a linha da mensagem e as linhas do fechamento), *agenda pendências* e a ordem das perguntas não a mostram', v_k, v_alvo),
        not pg_temp.mostra(v_a, v_ql, 'Lucenira') and not pg_temp.mostra(v_b, v_ql, 'Lucenira')
        and not pg_temp.mostra(r2, v_ql, 'Lucenira') and not pg_temp.mostra(v_c, v_ql, 'Lucenira')
        and jsonb_typeof(v_b) = 'array' and jsonb_typeof(v_c) = 'array',
        format('mensagem %s, linhas %s, pendências %s, ordem %s', pg_temp.mostra(v_a, v_ql, 'Lucenira'), pg_temp.mostra(v_b, v_ql, 'Lucenira'),
               pg_temp.mostra(r2, v_ql, 'Lucenira'), pg_temp.mostra(v_c, v_ql, 'Lucenira')));
      r := public.agenda_cliente_decidir_dito(c_dono, 'manda', 'Lucenira', 'whatsapp', date '2026-10-30', pg_temp.em('2026-10-30 17:35'));
      m := pg_temp.msg(c_luc, 'pronto');
      v_res := pg_temp.ok(v_res, format('C11c%s 17:35 *manda cliente Lucenira* (OS %s): não promete ("Mando para Lucenira …") nem manda ligar ("Recomendo ligar."); a mensagem segue pedida, sem fila; nenhuma pergunta "não saiu"', v_k, v_alvo),
        coalesce(r ->> 'texto', '') not like '%Mando para Lucenira%' and coalesce(r ->> 'texto', '') not like '%Recomendo ligar%'
        and m.estado = 'aguardando_dono' and m.aprovacao = 'pedida' and m.fila_id is null
        and not exists (select 1 from public.agenda_perguntas x where x.chave = 'cliente_resposta:nao_saiu:' || v_ml),
        r::text || ' | ' || m.estado || ' ' || m.aprovacao);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
  end loop;
  -- (4) o pós-serviço do Robson (OS concluída e entregue) que o tique das 15:15 registrou para ter 03/11 09:00, pedido; poupado
  -- às 15:30; a OS reaberta às 16:00 (pela porta; se ela não reabrir a OS entregue, como no replay, por um update com a marca dela)
  begin
    perform pg_temp.ligar(3);
    perform pg_temp.vig('2026-10-30 15:15');
    m := pg_temp.msg(c_rob, 'pos_servico');
    v_ml := m.id;
    v_ql := m.pergunta_id;
    v_val := m.enviar_em;
    r := pg_temp.limpa('2026-10-30 15:30');
    v_ok := m.estado = 'aguardando_dono' and m.aprovacao = 'pedida' and (pg_temp.perg(v_ql)).estado = 'aberta'
            and m.enviar_em > pg_temp.em('2026-10-31 00:00');
    t := format('pós-serviço %s/%s, sai %s; 15:30 %s', m.estado, m.aprovacao, m.enviar_em, (pg_temp.perg(v_ql)).estado);
    perform set_config('agenda_teste.hoje', '2026-10-30', true);
    r := public.os_transicionar_status(c_rob, 'in_progress', 'tela', 'C98: reaberta', c_dono, null, date '2026-10-30',
                                       pg_temp.em('2026-10-30 16:00'), null);
    if (select so.status from public.service_orders so where so.id = c_rob) <> 'in_progress' then
      perform set_config('agenda.porta', 'on', true);
      update public.service_orders set status = 'in_progress' where id = c_rob;
      perform set_config('agenda.porta', 'off', true);
      t := t || format('; reaberta por update (a porta: %s)', coalesce(r ->> 'texto', '-'));
    else
      t := t || format('; reaberta pela porta ("%s")', r ->> 'texto');
    end if;
    v_pr := coalesce(public._agenda_cliente_revalidar(v_ml, pg_temp.em('2026-10-30 16:10')), 'sai');
    r := pg_temp.limpa('2026-10-30 16:15');
    q := pg_temp.perg(v_ql);
    v_res := pg_temp.ok(v_res, format('C11d1 o pós-serviço do Robson (para ter 03/11 09:00) poupado e a OS reaberta às 16:00 (a revalidação já diz "status"): a limpeza das 16:15 fecha a pergunta com o motivo próprio'),
      v_ok and v_pr = 'status' and q.estado = 'resolvida' and q.resolvida_motivo = c_mot_reaberta,
      format('%s; revalidação %s; 16:15 %s %s', t, v_pr, q.estado, coalesce(q.resolvida_motivo, '-')));
    r := public.agenda_cliente_decidir_dito(c_dono, 'manda', 'Robson', 'whatsapp', date '2026-10-30', pg_temp.em('2026-10-30 16:20'));
    m := pg_temp.msg(c_rob, 'pos_servico');
    v_res := pg_temp.ok(v_res, 'C11d2 16:20 *manda cliente Robson*: não promete ("Mando para Robson …") nem manda ligar; a mensagem segue pedida, sem aprovação e sem fila',
      coalesce(r ->> 'texto', '') not like '%Mando para Robson%' and coalesce(r ->> 'texto', '') not like '%Recomendo ligar%'
      and m.aprovacao = 'pedida' and m.estado = 'aguardando_dono' and m.fila_id is null,
      r::text || ' | ' || m.estado || ' ' || m.aprovacao);
    r2 := pg_temp.vig(to_char(v_val at time zone 'America/Sao_Paulo', 'YYYY-MM-DD HH24:MI'));
    m := pg_temp.msg(c_rob, 'pos_servico');
    v_res := pg_temp.ok(v_res, 'C11d3 na hora de sair (ter 03/11 09:00): nenhuma pergunta "não saiu" para ela, e ela não foi à fila',
      not exists (select 1 from public.agenda_perguntas x where x.chave = 'cliente_resposta:nao_saiu:' || v_ml)
      and not exists (select 1 from public.whatsapp_send_queue w where w.source_ref_id = v_ml)
      and m.estado not in ('enfileirada', 'enviada') and m.aprovacao <> 'aprovada',
      format('sai %s; mensagem %s/%s/%s', v_val, m.estado, m.aprovacao, coalesce(m.recusa_motivo, '-')));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  -- (5) a OS reaberta às 15:20, antes da 1ª limpeza depois do pronto (o caminho que já existia sem a 98, parte do NOVO-agenda-291):
  -- a de agora fecha igual; a de 20261031100300 (pg_temp.limpeza_antes) a deixava aberta
  begin
    perform pg_temp.ligar(3);
    perform pg_temp.vig('2026-10-30 15:15');
    m := pg_temp.msg(c_luc, 'pronto');
    v_ql := m.pergunta_id;
    perform set_config('agenda_teste.hoje', '2026-10-30', true);
    r := public.os_transicionar_status(c_luc, 'in_progress', 'tela', 'C98: reaberta', c_dono, null, date '2026-10-30',
                                       pg_temp.em('2026-10-30 15:20'), null);
    begin
      r2 := pg_temp.limpeza_antes(date '2026-10-30', pg_temp.em('2026-10-30 15:30'));
      t := (pg_temp.perg(v_ql)).estado;
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    r2 := pg_temp.limpa('2026-10-30 15:30');
    q := pg_temp.perg(v_ql);
    v_res := pg_temp.ok(v_res, 'C11e a OS reaberta às 15:20, antes da 1ª limpeza depois do pronto: a de agora fecha a pergunta com o motivo próprio; a de 20261031100300 a deixava aberta (o caminho de antes da 98)',
      coalesce((r ->> 'ok')::boolean, false) and q.estado = 'resolvida' and q.resolvida_motivo = c_mot_reaberta and t = 'aberta',
      format('porta "%s"; agora %s %s; antes %s', r ->> 'texto', q.estado, coalesce(q.resolvida_motivo, '-'), t));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  -- (6) a matriz da carteira: os 13 tipos da lista fechada × a OS do Flávio em 7 estados da carteira, cada mensagem esperando o dono
  -- com a pergunta cliente_aprovar aberta (e 2 com a cliente_aviso); a âncora é a de 20261031100300 e a revalidação de verdade
  -- (o d10, o M11 e as camadas fora do caminho, como no C9)
  begin
    perform pg_temp.ligar(3);
    update public.agenda_config set cliente_conversa_dias = 0, onde_fica_desde = date '2026-10-01', modo_cliente_camadas = 'ligado',
                                    gestor_so_propor = false where id;
    v_lin := '{}';
    foreach v_est in array array['scheduled', 'open', 'in_progress', 'awaiting_parts', 'awaiting_client', 'approved', 'draft_aprovado'] loop
      begin
        perform set_config('agenda.porta', 'on', true);
        update public.service_orders
           set status = case when v_est = 'draft_aprovado' then 'draft' else v_est end,
               quote_status = case when v_est = 'draft_aprovado' then 'approved' else quote_status end,
               delivered_at = null
         where id = c_flav;
        perform set_config('agenda.porta', 'off', true);
        v_ids := '{}';
        foreach t in array v_tipos || array['aviso:pronto', 'aviso:pos_servico'] loop
          v_ex := gen_random_uuid();
          v_ids := v_ids || public._agenda_cliente_perguntar(case when t like 'aviso:%' then 'cliente_aviso' else 'cliente_aprovar' end,
                              case when t like 'aviso:%' then 'cliente_aviso:' else 'cliente_aprovar:' end || v_ex, c_flav, date '2026-11-03',
                              date '2026-11-02', format('Mensagem para Flávio (%s), sai seg 02/11: "teste (C98, C11)". *manda cliente Flávio* ou *segura cliente Flávio*.', t),
                              'ligado', pg_temp.em('2026-10-30 10:00'), pg_temp.em('2026-11-03 19:00'));
          insert into public.agenda_cliente_mensagens (id, client_id, service_order_id, tipo, origem, modo, texto, enviar_em, valida_ate,
                                                       aprovacao, pergunta_id, estado, dedupe_key, criada_em)
          values (v_ex, c_cli_flav, c_flav, replace(t, 'aviso:', ''), 'rodada', 'ligado', 'teste (C98, C11)', pg_temp.em('2026-11-02 09:00'),
                  pg_temp.em('2026-11-03 19:00'), case when t like 'aviso:%' then 'critica' else 'pedida' end, v_ids[cardinality(v_ids)],
                  'aguardando_dono', 'agenda-cliente:c98:c11:' || t, pg_temp.em('2026-10-30 10:00'));
        end loop;
        perform set_config('agenda_teste.hoje', '2026-10-30', true);
        select jsonb_object_agg(qq.tipo || '/' || mm.tipo, coalesce(public._agenda_cliente_revalidar(mm.id, pg_temp.em('2026-10-30 10:15')), 'sai'))
          into v_rev
          from public.agenda_cliente_mensagens mm join public.agenda_perguntas qq on qq.id = mm.pergunta_id where qq.id = any (v_ids);
        v_pr := public.os_prontidao(c_flav, date '2026-10-30') ->> 'estado';
        foreach v_freio in array array[false, true] loop
          begin
            update public.agenda_config set gestor_so_propor = v_freio where id;
            r := pg_temp.limpa('2026-10-30 10:15');
            if v_freio then v_b := pg_temp.c9_estados(v_ids); else v_a := pg_temp.c9_estados(v_ids); end if;
            raise exception 'desfaz' using errcode = 'P0098';
          exception when sqlstate 'P0098' then null;
          end;
        end loop;
        begin
          r := pg_temp.limpeza_antes(date '2026-10-30', pg_temp.em('2026-10-30 10:15'));
          v_c := pg_temp.c9_estados(v_ids);
          raise exception 'desfaz' using errcode = 'P0098';
        exception when sqlstate 'P0098' then null;
        end;
        v_lin := v_lin || (select array_agg(format('%s|%s|%s|%s|%s|%s|%s', v_est, k, v_pr, v_rev ->> k, v_a ->> k, v_b ->> k, v_c ->> k) order by k)
                             from jsonb_object_keys(v_rev) k);
        raise exception 'desfaz' using errcode = 'P0098';
      exception when sqlstate 'P0098' then null;
      end;
    end loop;
    -- as linhas: 1 estado da OS | 2 pergunta/mensagem | 3 prontidão | 4 revalidação | 5 agora sem o freio | 6 agora com o freio | 7 a de antes
    v_res := pg_temp.ok(v_res, 'C11f1 a cena: os 13 tipos × a OS do Flávio em 7 estados da carteira (agendada, aberta, em andamento, aguardando peças, aguardando o cliente, aprovada, orçamento aprovado) = 91 mensagens esperando o dono com a cliente_aprovar aberta (e 14 com a cliente_aviso); a prontidão nunca diz concluida nem fora_da_carteira; a revalidação de verdade diz "status" no pronto, no lembrete e no pós-serviço dos 7',
      cardinality(v_lin) = 105
      and (select count(*) from unnest(v_lin) l where split_part(l, '|', 2) like 'cliente_aprovar/%') = 91
      and (select bool_and(split_part(l, '|', 3) not in ('concluida', 'fora_da_carteira')) from unnest(v_lin) l)
      and (select count(*) from unnest(v_lin) l
            where split_part(l, '|', 2) in ('cliente_aprovar/pronto', 'cliente_aprovar/pronto_lembrete', 'cliente_aprovar/pos_servico')
              and split_part(l, '|', 4) = 'status') = 21,
      format('%s linhas; prontidão: %s; revalidação do pronto/lembrete/pós-serviço: %s', cardinality(v_lin),
             (select string_agg(distinct split_part(l, '|', 1) || '=' || split_part(l, '|', 3), ', ') from unnest(v_lin) l),
             (select string_agg(distinct split_part(l, '|', 4), ', ') from unnest(v_lin) l
               where split_part(l, '|', 2) in ('cliente_aprovar/pronto', 'cliente_aprovar/pronto_lembrete', 'cliente_aprovar/pos_servico'))));
    v_res := pg_temp.ok(v_res, 'C11f2 a de agora (sem o freio) × a de 20261031100300, nas 105: só a cliente_aprovar do pronto, do lembrete e do pós-serviço muda (as 21: aberta antes, resolvida agora com o motivo próprio); as outras 70 cliente_aprovar (a do NOVO-agenda-291) e as 14 cliente_aviso ficam como antes',
      (select count(*) from unnest(v_lin) l
        where split_part(l, '|', 2) in ('cliente_aprovar/pronto', 'cliente_aprovar/pronto_lembrete', 'cliente_aprovar/pos_servico')
          and split_part(l, '|', 5) = 'resolvida:' || c_mot_reaberta and split_part(l, '|', 7) = 'aberta:') = 21
      and (select bool_and(split_part(l, '|', 5) = split_part(l, '|', 7)) from unnest(v_lin) l
            where split_part(l, '|', 2) not in ('cliente_aprovar/pronto', 'cliente_aprovar/pronto_lembrete', 'cliente_aprovar/pos_servico'))
      and (select count(*) from unnest(v_lin) l
            where split_part(l, '|', 2) not in ('cliente_aprovar/pronto', 'cliente_aprovar/pronto_lembrete', 'cliente_aprovar/pos_servico')) = 84,
      format('mudaram %s; agora: %s; antes: %s',
             (select count(*) from unnest(v_lin) l where split_part(l, '|', 5) <> split_part(l, '|', 7)),
             (select string_agg(x || ' ' || n, ', ' order by x) from (select split_part(l, '|', 5) x, count(*) n from unnest(v_lin) l group by 1) s),
             (select string_agg(x || ' ' || n, ', ' order by x) from (select split_part(l, '|', 7) x, count(*) n from unnest(v_lin) l group by 1) s)));
    v_res := pg_temp.ok(v_res, 'C11f3 com o freio, a de agora decide o mesmo nas 105',
      (select bool_and(split_part(l, '|', 5) = split_part(l, '|', 6)) from unnest(v_lin) l) and cardinality(v_lin) = 105,
      coalesce((select string_agg(l, '; ' order by l) from unnest(v_lin) l where split_part(l, '|', 5) <> split_part(l, '|', 6)), '-'));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  -- (7) o erro contrário: a OS da Lucenira concluída (ou faturada) e congelada (em espera até qui 05/11: a prontidão diz congelada, e
  -- a regra "a OS saiu da carteira" não vale); o status deixa o pronto sair, e a pergunta fica aberta, como antes
  foreach v_alvo in array array['completed', 'invoiced'] loop
    begin
      perform pg_temp.ligar(3);
      perform pg_temp.vig('2026-10-30 15:15');
      m := pg_temp.msg(c_luc, 'pronto');
      v_ml := m.id;
      v_ql := m.pergunta_id;
      perform set_config('agenda.porta', 'on', true);
      update public.service_orders set status = v_alvo where id = c_luc;
      perform set_config('agenda.porta', 'off', true);
      insert into public.os_planejamento (service_order_id, congelada_ate, revisar_em) values (c_luc, date '2026-11-05', date '2026-11-05')
      on conflict (service_order_id) do update set congelada_ate = excluded.congelada_ate, revisar_em = excluded.revisar_em;
      v_pr := coalesce(public._agenda_cliente_revalidar(v_ml, pg_temp.em('2026-10-30 15:25')), 'sai');
      begin
        r2 := pg_temp.limpeza_antes(date '2026-10-30', pg_temp.em('2026-10-30 15:30'));
        t := (pg_temp.perg(v_ql)).estado;
        raise exception 'desfaz' using errcode = 'P0098';
      exception when sqlstate 'P0098' then null;
      end;
      r := pg_temp.limpa('2026-10-30 15:30');
      q := pg_temp.perg(v_ql);
      v_res := pg_temp.ok(v_res, format('C11g%s a OS da Lucenira %s e congelada (a prontidão diz congelada; a revalidação deixa o pronto sair): a pergunta fica aberta, como na de 20261031100300',
                                        case v_alvo when 'completed' then '1' else '2' end, case v_alvo when 'completed' then 'concluída' else 'faturada' end),
        m.estado = 'aguardando_dono' and public.os_prontidao(c_luc, date '2026-10-30') ->> 'estado' = 'congelada' and v_pr <> 'status'
        and q.estado = 'aberta' and t = 'aberta',
        format('prontidão %s; revalidação %s; agora %s %s; antes %s', public.os_prontidao(c_luc, date '2026-10-30') ->> 'estado', v_pr,
               q.estado, coalesce(q.resolvida_motivo, '-'), t));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
  end loop;

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
