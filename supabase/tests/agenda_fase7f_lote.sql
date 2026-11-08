-- Prova do lote do dono da Agenda de Produção, Fase 7f (pacote P4): fora do fechamento só a exceção; o resto espera o bloco das 17:30, que o registra; a quinta com a mensagem própria
-- da semana (migration 20261109100300; spec-fase7f §5.4, §6.3, §8.3 agenda_fase7f_lote.sql e R8.5-12 a 14 e 27, R8.6, R8.7, R8.8, R8.12, R8.13). O texto é o do montador
-- (_shared/agenda/aviso-do-gestor.ts): aqui ele é juntado por _agenda_lote_texto, que o O4f confere contra o mesmo texto que aviso-do-gestor_test.ts confere no montador.
-- bancada: depende de 20261109100300
--
--   O0   sempre: 1 assinatura de agenda_aviso_enfileirar; o CHECK novo; as portas
--   O1   _agenda_e_excecao: dia com ficha, falta de hoje, crítica que perde amanhã, mudança do próximo dia útil no que o cliente sabe; e as não exceções
--   O2   o lote ligado com o bloco fora de ligado = sombra; sombra = o aviso de antes (texto, ações, perguntas, prazo); o controle reprova
--   O3   a cota: os acordes e os avisos de exceção do dia; acima dela espera o bloco, sem frase
--   O4   a quinta: uma vez; só no dia e na hora; propria × fechamento; sem mudança com pergunta, pela fila; o texto; a sombra; o freio e o prazo; o bloco da quinta depois dela
--   O5   o acorde "Já avisei o Roberto." fica para o P5: nada cria a mensagem de mudança da equipe
--   O6   as cópias só mudam nos blocos; a migration cria e recria só o que diz
--   O7   com o lote, a rodada de aprontar não sai no aviso
--   O8   o caminho inteiro: a rodada guarda, o bloco mostra, o registro conta; nada sai 2 vezes nem some
--   O9   o freio: o lote não o respeita
--   O10  "lote só depois de v_n = 0": a rodada sem nada não lê nada novo
--   O11  a rodada comunicar: com tudo em sombra não manda nada; contagens.lote_guardaria em sombra e ligado; o pré-passo que falha
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Fora dela, só o O0 roda; o resto sai PULADO: usa a fixture da 7f, que nunca roda em produção.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;
create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;
create function pg_temp.como(p_uid uuid, p_papel text, p_sql text) returns text language plpgsql as $f$
declare
  v text;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('request.jwt.claims',
    case when p_uid is null then json_build_object('role', p_papel)::text
         else json_build_object('sub', p_uid, 'role', p_papel)::text end, true);
  begin
    execute format('set local role %I', p_papel);
    execute p_sql into v;
    reset role;
  exception when others then
    v := 'erro ' || sqlstate || ': ' || sqlerrm;
  end;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;
create function pg_temp.lanca(p_sql text) returns text language plpgsql as $f$
begin
  begin
    execute p_sql;
  exception when others then
    return sqlstate;
  end;
  return 'ok';
end $f$;
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  if position(format('create or replace function public.%s(', p_nome) in v) = 0 then return ''; end if;
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'\nas $function$' in v) + length(E'\nas $function$'));
  return left(v, position('$function$' in v) - 1);
end $f$;
-- O texto sem os blocos "-- FASE 7f: … -- FASE 7f: fim" e, dentro de bloco de antes, "-- (7f … -- (7f: fim)" (as linhas de abrir e de fechar saem junto).
create function pg_temp.sem_7f(p text) returns text language sql immutable as $f$
  select array_to_string(array(
           select l from (select l, o, sum(case when l ~ '^\s*-- (FASE 7f:|\(7f )' and l !~ '^\s*-- (FASE 7f: fim|\(7f: fim\))' then 1
                                                when l ~ '^\s*-- (FASE 7f: fim|\(7f: fim\))' then -1 else 0 end)
                                       over (order by o rows between unbounded preceding and current row) as dentro,
                                 l ~ '^\s*-- (FASE 7f: fim|\(7f: fim\))' as fecha
                            from unnest(string_to_array(replace(p, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o)) x
            where dentro = 0 and not fecha order by o), E'\n')
$f$;
create function pg_temp.adm() returns uuid language sql stable as $f$
  select id from public.app_users where role = 'admin' and active order by created_at, id limit 1
$f$;
create function pg_temp.na_bancada() returns boolean language sql stable as $f$
  select coalesce(current_setting('agenda_teste.fase7f', true), '') <> ''
     and coalesce(current_setting('agenda_teste.mig_lote_fase7f', true), '') <> ''
$f$;
create function pg_temp.q(p_c text) returns uuid language sql immutable as $f$ select ('f7f00000-0000-4000-8000-0000000005' || p_c)::uuid $f$;
create function pg_temp.a(p_c text) returns uuid language sql immutable as $f$ select ('f7f00000-0000-4000-8000-0000000006' || p_c)::uuid $f$;
create function pg_temp.os(p_n text) returns uuid language sql immutable as $f$ select ('f7f00000-0000-4000-8000-000000097' || p_n)::uuid $f$;
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
-- O cenário: a fixture da 7f, o aviso ligado (a agenda automática e a vigia em ligado), o dono no WhatsApp, o freio de produção (gestor_so_propor) e só as 4 ações da etapa por contar.
create function pg_temp.prepara() returns void language plpgsql as $f$
begin
  execute current_setting('agenda_teste.fase7f');
  update public.agenda_config set modo_proposta = 'ligado', modo_vigia = 'ligado', modo_leitura = 'ligado', gestor_aviso_dia_max = 3, gestor_so_propor = true where id;
  update public.app_users set ai_whatsapp_enabled = true, phone_normalized = '5547900000210' where id = pg_temp.adm();
  update public.agenda_acoes set contada_em = timestamptz '2026-11-09 17:30-03', contada_via = 'fechamento'
   where contada_em is null and executada and id::text not like 'f7f00000-0000-4000-8000-00000000060%';
end $f$;
create function pg_temp.modos(p_lote text, p_bloco text) returns void language sql as $f$
  update public.agenda_config set modo_lote_dono = p_lote, modo_bloco_agenda = p_bloco where id
$f$;
create function pg_temp.ids(p jsonb) returns uuid[] language sql immutable as $f$
  select array(select x::uuid from jsonb_array_elements(coalesce(p -> 'mudancas', '[]'::jsonb)) m, jsonb_array_elements_text(m -> 'acao_ids') x)
$f$;
create function pg_temp.pids(p jsonb) returns uuid[] language sql immutable as $f$
  select array(select x::uuid from jsonb_array_elements_text(case when jsonb_typeof(p -> 'perguntas') = 'object' then p #> '{perguntas,pergunta_ids}' else '[]'::jsonb end) x)
$f$;
-- Um tique do aviso como o task-automations faz: as peças e, quando é para avisar, o enfileirar com o texto montado.
create function pg_temp.avisar(p_agora timestamptz) returns jsonb language plpgsql as $f$
declare
  v_dia date := (p_agora at time zone 'America/Sao_Paulo')::date;
  p jsonb := public.agenda_aviso_pecas(v_dia, p_agora);
begin
  if not coalesce((p ->> 'avisar')::boolean, false) then
    return p || jsonb_build_object('enfileirou', false);
  end if;
  return public.agenda_aviso_enfileirar(public._agenda_lote_texto(p), pg_temp.ids(p), pg_temp.pids(p), jsonb_typeof(p -> 'perguntas') = 'object', v_dia, p_agora)
         || jsonb_build_object('pecas', p);
end $f$;
-- A rodada comunicar e o que o task-automations faz com os avisos dela (agenda-comunicar.ts): monta e enfileira com p_semana, num instante próprio (p_envio).
create function pg_temp.comunicar(p_agora timestamptz, p_envio timestamptz) returns jsonb language plpgsql as $f$
declare
  v_dia date := (p_agora at time zone 'America/Sao_Paulo')::date;
  r jsonb := public.agenda_comunicar_rodar(v_dia, p_agora);
  p jsonb;
  e jsonb := '[]';
begin
  for p in select x from jsonb_array_elements(coalesce(r -> 'avisos', '[]'::jsonb)) x loop
    e := e || jsonb_build_array(public.agenda_aviso_enfileirar(public._agenda_lote_texto(p), pg_temp.ids(p), pg_temp.pids(p), jsonb_typeof(p -> 'perguntas') = 'object',
                                                                 v_dia, p_envio, true));
  end loop;
  return r || jsonb_build_object('enfileirar', e);
end $f$;
-- A fila mandou (o worker): as linhas agenda-dono pendentes saem na hora dada; e o conferir do tique seguinte.
create function pg_temp.saiu(p_quando timestamptz) returns jsonb language sql as $f$
  update public.whatsapp_send_queue set status = 'sent', sent_at = p_quando, attempts = attempts + 1 where source = 'agenda-dono' and status = 'pending';
  select public.agenda_aviso_conferir(p_quando + interval '10 minutes');
$f$;
-- O bloco que agenda_textos_do_fechamento mandaria às 17:30 do dia, e as linhas do nível em que ele cabe (o que o Secretário mostra e registra).
create function pg_temp.bloco(p_hoje date) returns jsonb language plpgsql as $f$
begin
  perform set_config('agenda.agora', pg_temp.em(p_hoje, '17:30')::text, true);
  return public.agenda_textos_do_fechamento(p_hoje, public.agenda_somar_du(p_hoje, 1)) -> 'bloco';
end $f$;
create function pg_temp.no_nivel(p_b jsonb) returns jsonb language sql immutable as $f$
  select coalesce(jsonb_agg(l order by o), '[]'::jsonb) from jsonb_array_elements(p_b -> 'linhas') with ordinality t(l, o)
   where (l ->> 'nivel_entra')::int <= (p_b ->> 'nivel')::int and (l ->> 'nivel_de_corte' is null or (p_b ->> 'nivel')::int < (l ->> 'nivel_de_corte')::int)
$f$;
create function pg_temp.texto_do_bloco(p_b jsonb) returns text language sql immutable as $f$
  select string_agg(l ->> 'texto', E'\n' order by o) from jsonb_array_elements(pg_temp.no_nivel(p_b)) with ordinality t(l, o)
$f$;
-- Como uma ação está contada: a via, ou "-".
create function pg_temp.via(p_a uuid) returns text language sql stable as $f$
  select coalesce(contada_via, '-') from public.agenda_acoes where id = p_a
$f$;
-- O texto do *o que mudou* de uma ação (o que o aviso e o bloco escrevem dela).
create function pg_temp.frase(p_a uuid) returns text language sql stable as $f$
  select texto from public.agenda_acoes where id = p_a
$f$;
create function pg_temp.desfaz() returns void language plpgsql as $f$
begin
  raise exception using errcode = 'P0001', message = '__desfaz__';
end $f$;

-- A fixture entra uma vez, na transação de fora: cada caso mexe nela dentro de uma subtransação desfeita, e o pg_temp.prepara de cada um não a carrega de novo (ela confere se
-- já está lá). Carregada dentro da subtransação, ela sairia junto a cada caso, e o arquivo levaria minutos.
do $o$
begin
  if pg_temp.na_bancada() then
    execute current_setting('agenda_teste.fase7f');
  end if;
end
$o$;

-- ── O0. Sempre ──────────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'O0a uma assinatura só de agenda_aviso_enfileirar, a de 7 argumentos, com p_semana default false (R8.5-16: duas fariam o PostgREST recusar)',
       count(*) = 1 and bool_and(pg_get_function_identity_arguments(p.oid) like '%p_agora timestamp with time zone, p_semana boolean'
                                 and pg_get_function_arguments(p.oid) like '%p_semana boolean DEFAULT false'),
       string_agg(pg_get_function_identity_arguments(p.oid), ' | ')
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'agenda_aviso_enfileirar';
insert into _resultado
select 'O0b o CHECK de agenda_dono_avisos: dono_aviso_conta_mudanca no lugar de "cardinality(acao_ids) > 0", que não existe mais',
       exists (select 1 from pg_constraint where conrelid = 'public.agenda_dono_avisos'::regclass and conname = 'dono_aviso_conta_mudanca'
                  and pg_get_constraintdef(oid) like '%cardinality(acao_ids) > 0%agenda-dono:semana:%cardinality(pergunta_ids) > 0%')
       and not exists (select 1 from pg_constraint where conrelid = 'public.agenda_dono_avisos'::regclass and contype = 'c'
                          and pg_get_constraintdef(oid) = 'CHECK ((cardinality(acao_ids) > 0))'),
       (select string_agg(conname, ', ' order by conname) from pg_constraint where conrelid = 'public.agenda_dono_avisos'::regclass and contype = 'c');
with f(sig) as (values ('public._agenda_lote_ligado()'), ('public._agenda_lote_cota(date)'), ('public._agenda_e_excecao(jsonb, date, timestamptz)'),
                       ('public._agenda_lote_mudancas(date)'), ('public._agenda_lote_fora(jsonb)'), ('public._agenda_lote_texto(jsonb)'),
                       ('public._agenda_comunicar_quinta(date, timestamptz)'), ('public._agenda_comunicar_lote_guardaria(date, timestamptz)'))
insert into _resultado
select 'O0c as 8 novas: ninguém de fora (nem anon, nem authenticated, nem service_role); invoker; search_path fixo',
       count(*) = 8 and bool_and(not has_function_privilege('anon', f.sig, 'execute') and not has_function_privilege('authenticated', f.sig, 'execute')
                                 and not has_function_privilege('service_role', f.sig, 'execute') and not p.prosecdef
                                 and p.proconfig = array['search_path=public']),
       string_agg(f.sig, ', ') filter (where p.prosecdef or has_function_privilege('service_role', f.sig, 'execute'))
  from f join pg_proc p on p.oid = f.sig::regprocedure;
with f(sig) as (values ('public.agenda_aviso_pecas(date, timestamptz)'), ('public.agenda_aviso_enfileirar(text, uuid[], uuid[], boolean, date, timestamptz, boolean)'),
                       ('public.agenda_comunicar_rodar(date, timestamptz)'))
insert into _resultado
select 'O0d as 3 recriadas: só o service_role; security definer; search_path fixo (a de enfileirar nasceu de novo: o grant é desta migration)',
       count(*) = 3 and bool_and(not has_function_privilege('anon', f.sig, 'execute') and not has_function_privilege('authenticated', f.sig, 'execute')
                                 and has_function_privilege('service_role', f.sig, 'execute') and p.prosecdef and p.proconfig = array['search_path=public']), null
  from f join pg_proc p on p.oid = f.sig::regprocedure;
insert into _resultado
select 'O0e a chave do aviso diz o que é (aviso, excecao, semana): o comentário da coluna diz as 3',
       col_description('public.agenda_dono_avisos'::regclass,
                       (select attnum from pg_attribute where attrelid = 'public.agenda_dono_avisos'::regclass and attname = 'dedupe_key'))
         like '%agenda-dono:aviso:%agenda-dono:excecao:%agenda-dono:semana:%', null;

-- O4v: o texto que a sombra guarda é o que o montador junta. As peças e o texto são os MESMOS de _shared/agenda/aviso-do-gestor_test.ts ("semana: o texto é o mesmo…"):
-- os dois lados conferem o mesmo texto, letra a letra.
with p(pecas, esperado) as (values
  (jsonb_build_object('avisar', true, 'semana', true, 'rodada', '2026-11-12T20:00:00+00:00', 'dia', '2026-11-12', 'limite', 2400,
     'cabecalho', 'Agenda — o que eu mudei sozinho:',
     'mudancas', jsonb_build_array(
        jsonb_build_object('texto', 'Marquei Lenine em seg 16/11 com Alex (3 dias, estimativa minha). *desfaz Lenine* volta como estava.', 'acao_ids', jsonb_build_array('e513491a-ed1b-4636-9185-44294948343f')),
        jsonb_build_object('texto', 'Passei Vanderlei da tarde de hoje para qua 11/11 de manhã. *desfaz Vanderlei* volta como estava.', 'acao_ids', jsonb_build_array('0b1c6a35-7d0e-4c55-9a51-6f2b8c1d2e30'))),
     'fora', 'Ficou de fora: MP (esperando o sinal).', 'rodape', '*agenda plano* mostra tudo.',
     'perguntas', jsonb_build_object('texto', E'Para a semana que vem preciso de:\n· Decisão 2: O serviço do Giancarlo (lancha, Troca do GPS) não cabe nas 2… Recomendo a opção 1: Passa para a semana seguinte, sem mudar o que já está marcado.\n· Você: Quais dias você fica em campo na semana de 16/11? Hoje eu conto você só para abrir e… Por enquanto conto você só para abrir e fechar.\n(e mais 3 em *agenda pendências*)\nPode ser um áudio só, citando o nome do cliente.',
                                     'pergunta_ids', jsonb_build_array('6037294c-834c-48b0-9943-6d41d85453ec', 'e452fa40-581c-41af-a037-2adc6297b971'))),
   E'Agenda — o que eu mudei sozinho:\n• Marquei Lenine em seg 16/11 com Alex (3 dias, estimativa minha). *desfaz Lenine* volta como estava.\n• Passei Vanderlei da tarde de hoje para qua 11/11 de manhã. *desfaz Vanderlei* volta como estava.\nFicou de fora: MP (esperando o sinal).\n*agenda plano* mostra tudo.\n\nPara a semana que vem preciso de:\n· Decisão 2: O serviço do Giancarlo (lancha, Troca do GPS) não cabe nas 2… Recomendo a opção 1: Passa para a semana seguinte, sem mudar o que já está marcado.\n· Você: Quais dias você fica em campo na semana de 16/11? Hoje eu conto você só para abrir e… Por enquanto conto você só para abrir e fechar.\n(e mais 3 em *agenda pendências*)\nPode ser um áudio só, citando o nome do cliente.'))
insert into _resultado
select 'O4v o texto que a sombra guarda (_agenda_lote_texto) é o que o montador junta: as mesmas peças e o mesmo texto do teste do montador; sem mudança, o cabeçalho da semana',
       public._agenda_lote_texto(p.pecas) = p.esperado
       and public._agenda_lote_texto(p.pecas || jsonb_build_object('cabecalho', 'Agenda — a semana que vem:', 'mudancas', '[]'::jsonb, 'fora', null))
           = E'Agenda — a semana que vem:\n*agenda plano* mostra tudo.\n\n' || (p.pecas #>> '{perguntas,texto}'),
       public._agenda_lote_texto(p.pecas)
  from p;

-- ── O1. A exceção ───────────────────────────────────────────────────────────────────────────────────
do $o$
declare
  r       jsonb := '[]';
  c_hoje  constant date := date '2026-11-10';
  c_agora constant timestamptz := timestamptz '2026-11-10 14:15-03';
  v_rob   uuid;
  v_al    uuid;
  v_a     uuid;
  v_b     uuid;
begin
  if not pg_temp.na_bancada() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'O o lote', true, 'PULADO: sem a fixture e a migration como texto (rode pela bancada)'));
    return;
  end if;
  begin
    perform pg_temp.prepara();
    select id into v_rob from public.payees where name = 'Roberto' and active;
    r := pg_temp.ok(r, 'O1a o dia com ficha: tirar o Roberto da tarde de hoje, com a ficha de hoje enviada, é exceção',
      public._agenda_e_excecao(jsonb_build_object('acao_ids', jsonb_build_array(pg_temp.a('03'))), c_hoje, c_agora), null);
    r := pg_temp.ok(r, 'O1b não exceção: o encaixe de seg 16/11 (longe) e o remanejo de hoje para amanhã que ninguém soube',
      not public._agenda_e_excecao(jsonb_build_object('acao_ids', jsonb_build_array(pg_temp.a('01'))), c_hoje, c_agora)
      and not public._agenda_e_excecao(jsonb_build_object('acao_ids', jsonb_build_array(pg_temp.a('02'))), c_hoje, c_agora), null);
    r := pg_temp.ok(r, 'O1c um grupo com uma exceção é exceção (a mudança sai inteira)',
      public._agenda_e_excecao(jsonb_build_object('acao_ids', jsonb_build_array(pg_temp.a('01'), pg_temp.a('03'))), c_hoje, c_agora), null);
    -- a falta de hoje
    insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
    values (c_hoje, true, 'equipe', 'equipe', pg_temp.os('304'), array[pg_temp.os('304')], v_rob, jsonb_build_object('motivo', 'nao_vou', 'dia', c_hoje), 'O Roberto avisou que não vem hoje.')
    returning id into v_a;
    insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
    values (c_hoje, true, 'equipe', 'equipe', pg_temp.os('304'), array[pg_temp.os('304')], v_rob, jsonb_build_object('motivo', 'nao_vou', 'dia', date '2026-11-20'), 'O Roberto avisou que não vem dia 20.')
    returning id into v_b;
    r := pg_temp.ok(r, 'O1d a falta de hoje é exceção; a de um dia longe não',
      public._agenda_e_excecao(jsonb_build_object('acao_ids', jsonb_build_array(v_a)), c_hoje, c_agora)
      and not public._agenda_e_excecao(jsonb_build_object('acao_ids', jsonb_build_array(v_b)), c_hoje, c_agora), null);
    -- a crítica que perde amanhã
    r := pg_temp.ok(r, 'O1e a crítica que perde amanhã é exceção (Flávio, qua 11/11); a que perde depois não (Giancarlo, qui 12/11); a não crítica também não',
      public._agenda_e_excecao(jsonb_build_object('pergunta_id', pg_temp.q('06')), c_hoje, c_agora)
      and not public._agenda_e_excecao(jsonb_build_object('pergunta_id', pg_temp.q('07')), c_hoje, c_agora)
      and not public._agenda_e_excecao(jsonb_build_object('pergunta_ids', jsonb_build_array(pg_temp.q('02'), pg_temp.q('03'))), c_hoje, c_agora), null);
    -- a mudança do próximo dia útil no que o cliente sabe (Nelson ouviu a semana de 16 a 21/11): amanhã sai da faixa; dentro da faixa e longe, não
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem)
    values (pg_temp.os('301'), (select id from public.payees where name = 'Rafael' and active), date '2026-11-11', 'manha', 'turno', 'execucao', 'publicada', 'motor') returning id into v_al;
    insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, alocacoes_criadas, texto, desfazivel_ate)
    values (c_hoje, true, 'vigia', 'mover', pg_temp.os('301'), array[pg_temp.os('301')], array[v_al], 'Passei Nelson para amanhã.', c_agora + interval '1 day') returning id into v_a;
    insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, alocacoes_criadas, texto, desfazivel_ate)
    values (c_hoje, true, 'vigia', 'mover', pg_temp.os('301'), array[pg_temp.os('301')],
            array[md5('f7f:aloc:301:roberto:2026-11-18:manha')::uuid], 'Passei Nelson de manhã na qua 18/11.', c_agora + interval '1 day') returning id into v_b;
    r := pg_temp.ok(r, 'O1f a mudança de amanhã que sai do que o cliente ouviu é exceção; a de dentro da faixa, longe, não',
      public._agenda_e_excecao(jsonb_build_object('acao_ids', jsonb_build_array(v_a)), c_hoje, c_agora)
      and not public._agenda_e_excecao(jsonb_build_object('acao_ids', jsonb_build_array(v_b)), c_hoje, c_agora), null);
    -- a ficha que o gestor segurou ("Fale com Alex"): 3 dos 5 avisos reais de 03 a 07/11 eram ela
    insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
    values (c_hoje, true, 'vigia', 'equipe', pg_temp.os('302'), array[pg_temp.os('302')], v_rob,
            jsonb_build_object('motivo', 'ficha_segurada', 'dia', date '2026-11-11', 'por', 'sem_telefone'), 'Não mandei a ficha de qua 11/11 a Roberto. Fale com Roberto.')
    returning id into v_a;
    insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
    values (c_hoje, true, 'vigia', 'equipe', pg_temp.os('302'), array[pg_temp.os('302')], v_rob,
            jsonb_build_object('motivo', 'ficha_segurada', 'dia', date '2026-11-16', 'por', 'sem_telefone'), 'Não mandei a ficha de seg 16/11 a Roberto.')
    returning id into v_b;
    r := pg_temp.ok(r, 'O1i a ficha que o gestor segurou para o próximo dia útil é exceção (só o dono avisa antes do dia); a de um dia longe, não; a classe do P1 não a conta',
      public._agenda_e_excecao(jsonb_build_object('acao_ids', jsonb_build_array(v_a)), c_hoje, c_agora)
      and not public._agenda_e_excecao(jsonb_build_object('acao_ids', jsonb_build_array(v_b)), c_hoje, c_agora)
      and not (public._agenda_classe_da_saida('acao', v_a, c_hoje, c_agora) ->> 'excecao')::boolean, null);
    insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
    values (c_hoje, true, 'vigia', 'equipe', pg_temp.os('302'), array[pg_temp.os('302')], v_rob,
            jsonb_build_object('motivo', 'regra_d14', 'dia', date '2026-11-11'), 'Pus o Roberto na rotina da equipe.')
    returning id into v_b;
    r := pg_temp.ok(r, 'O1i2 outra ação da equipe para o próximo dia útil (pôr na rotina) não é exceção: só a ficha segurada e a falta',
      not public._agenda_e_excecao(jsonb_build_object('acao_ids', jsonb_build_array(v_b)), c_hoje, c_agora), null);
    insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
    values (c_hoje, false, 'vigia', 'equipe', pg_temp.os('302'), array[pg_temp.os('302')], v_rob,
            jsonb_build_object('motivo', 'ficha_segurada', 'dia', date '2026-11-11', 'por', 'sem_telefone'), 'Em teste: eu seguraria a ficha de qua 11/11 do Roberto.')
    returning id into v_b;
    r := pg_temp.ok(r, 'O1i3 a ficha segurada em teste (sombra) não é exceção: nada foi segurado',
      not public._agenda_e_excecao(jsonb_build_object('acao_ids', jsonb_build_array(v_b)), c_hoje, c_agora), null);
    r := pg_temp.ok(r, 'O1e2 numa lista de perguntas, uma crítica que perde amanhã basta',
      public._agenda_e_excecao(jsonb_build_object('pergunta_ids', jsonb_build_array(pg_temp.q('07'), pg_temp.q('06'))), c_hoje, c_agora), null);
    r := pg_temp.ok(r, 'O1g item sem id = 22023; ação que não existe = P0002 (quem chama decide: o aviso a manda, como antes); sem o dia = 22004',
      pg_temp.lanca($q$select public._agenda_e_excecao('{"acao_ids": []}', date '2026-11-10', now())$q$) = '22023'
      and pg_temp.lanca($q$select public._agenda_e_excecao('{"acao_ids": ["00000000-0000-4000-8000-000000000000"]}', date '2026-11-10', now())$q$) = 'P0002'
      and pg_temp.lanca($q$select public._agenda_e_excecao('{"acao_ids": []}', null, now())$q$) = '22004', null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$o$;

do $o$
declare
  r jsonb := '[]';
  v jsonb;
begin
  if not pg_temp.na_bancada() then return; end if;
  begin
    perform pg_temp.prepara();
    perform pg_temp.modos('ligado', 'ligado');
    create or replace function public._agenda_e_excecao(p_item jsonb, p_hoje date, p_agora timestamptz) returns boolean language plpgsql as $f$
    begin
      raise exception 'a classe não leu' using errcode = 'P0097';
    end $f$;
    v := public.agenda_aviso_pecas(date '2026-11-10', timestamptz '2026-11-10 14:15-03');
    r := pg_temp.ok(r, 'O1h a classificação que lança não cala a mudança: com o lote ligado, as 3 saem, como antes',
      (v ->> 'avisar')::boolean and jsonb_array_length(v -> 'mudancas') = 3, v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$o$;

-- ── O2. Sombra é o aviso de antes ───────────────────────────────────────────────────────────────────
-- O que se compara de cada rodada: as peças, e depois do enfileirar e do envio o texto registrado, as ações e as perguntas que ele contou, a linha da fila, as ações contadas e as
-- perguntas mostradas com o prazo. A régua é a rodada com os 2 modos desligados (o código de antes). O controle: o lote ligado de verdade muda.
do $o$
declare
  r       jsonb := '[]';
  c_tic   constant timestamptz := timestamptz '2026-11-10 14:15-03';
  v_ref   text;
  v       text;
  v_dif   text;
  v_n     int := 0;
  x       record;
  f       boolean;
begin
  if not pg_temp.na_bancada() then return; end if;
  create temp table _rodada (lote text, bloco text, freio boolean, foto text) on commit drop;
  foreach f in array array[true, false] loop
    for x in select * from (values ('desligado', 'desligado'), ('sombra', 'desligado'), ('sombra', 'sombra'), ('sombra', 'ligado'),
                                    ('ligado', 'desligado'), ('ligado', 'sombra'), ('desligado', 'ligado'), ('ligado', 'ligado')) t(lote, bloco) loop
      begin
        perform pg_temp.prepara();
        update public.agenda_config set gestor_so_propor = f where id;
        perform pg_temp.modos(x.lote, x.bloco);
        perform pg_temp.avisar(c_tic);
        perform pg_temp.saiu(c_tic + interval '5 minutes');
        select jsonb_build_object(
                 'pecas', (public.agenda_aviso_pecas(date '2026-11-10', c_tic) - 'rodada'),
                 'aviso', (select jsonb_agg(jsonb_build_object('texto', v.texto, 'acoes', v.acao_ids, 'perguntas', v.pergunta_ids, 'com', v.com_perguntas,
                                                               'estado', v.estado, 'chave', split_part(v.dedupe_key, ':', 2)) order by v.criada_em)
                             from public.agenda_dono_avisos v where v.dia = date '2026-11-10'),
                 'fila', (select jsonb_agg(jsonb_build_object('m', q.message, 's', q.source, 'st', q.status) order by q.created_at)
                            from public.whatsapp_send_queue q where q.source = 'agenda-dono'),
                 'acoes', (select jsonb_object_agg(a.id, coalesce(a.contada_via, '-')) from public.agenda_acoes a where a.id::text like 'f7f00000-0000-4000-8000-00000000060%'),
                 'perguntas', (select jsonb_object_agg(q.id, jsonb_build_object('v', q.mostrada_vezes, 'via', q.mostrada_via, 'ate', q.veto_ate, 'teria', q.veto_teria_em))
                                 from public.agenda_perguntas q where q.id::text like 'f7f00000-0000-4000-8000-00000000050%'))::text into v;
        perform pg_temp.desfaz();
      exception when sqlstate 'P0001' then
        if sqlerrm <> '__desfaz__' then raise; end if;
      end;
      insert into _rodada values (x.lote, x.bloco, f, v);
    end loop;
  end loop;
  foreach f in array array[true, false] loop
    v_ref := (select foto from _rodada where lote = 'desligado' and bloco = 'desligado' and freio = f);
    for x in select * from _rodada where freio = f and not (lote = 'desligado' and bloco = 'desligado') and not (lote = 'ligado' and bloco = 'ligado') loop
      v_n := v_n + 1;
      if x.foto is distinct from v_ref then
        v_dif := coalesce(v_dif || ', ', '') || format('%s/%s freio %s', x.lote, x.bloco, f);
      end if;
    end loop;
  end loop;
  r := pg_temp.ok(r, format('O2a sombra, e o lote ligado com o bloco fora de ligado: o aviso de antes — as peças, o texto, as ações, as perguntas, a fila, o contado, as mostradas e o prazo (%s rodadas, com e sem o freio)', v_n),
    v_dif is null and v_n = 12, v_dif);
  r := pg_temp.ok(r, 'O2b a régua tem o que comparar: o aviso de antes saiu, com as 3 mudanças e as perguntas',
    (select foto from _rodada where lote = 'desligado' and bloco = 'desligado' and freio) like '%"estado": "enviada"%'
    and (select foto from _rodada where lote = 'desligado' and bloco = 'desligado' and freio) like '%"chave": "aviso"%', null);
  r := pg_temp.ok(r, 'O2c o controle reprova: com o lote e o bloco ligados, a rodada muda (com e sem o freio)',
    (select bool_and(x2.foto is distinct from (select foto from _rodada where lote = 'desligado' and bloco = 'desligado' and freio = x2.freio))
       from _rodada x2 where x2.lote = 'ligado' and x2.bloco = 'ligado'), null);
  perform pg_temp.gravar(r);
end
$o$;

-- ── O3. A cota ──────────────────────────────────────────────────────────────────────────────────────
do $o$
declare
  r       jsonb := '[]';
  c_hoje  constant date := date '2026-11-10';
  v       jsonb;
  w       jsonb;
  b       jsonb;
  v_al    uuid;
  v_nova  uuid;
begin
  if not pg_temp.na_bancada() then return; end if;
  begin
    perform pg_temp.prepara();
    perform pg_temp.modos('ligado', 'ligado');
    v := pg_temp.avisar(pg_temp.em(c_hoje, '14:15'));
    r := pg_temp.ok(r, 'O3a com o lote: a rodada leva só a exceção (o Roberto, que tinha a ficha), com a chave da exceção',
      (v ->> 'enfileirou')::boolean and pg_temp.via(pg_temp.a('03')) = 'aviso' and pg_temp.via(pg_temp.a('01')) = '-' and pg_temp.via(pg_temp.a('02')) = '-'
      and (select split_part(dedupe_key, ':', 2) from public.agenda_dono_avisos where id = (v ->> 'id')::uuid) = 'excecao'
      and jsonb_array_length(v #> '{pecas,mudancas}') = 1, v::text);
    r := pg_temp.ok(r, 'O3b a cota de hoje acabou: 1 − 0 acordes − 1 aviso de exceção', public._agenda_lote_cota(c_hoje) = 0, public._agenda_lote_cota(c_hoje)::text);
    r := pg_temp.ok(r, 'O3h2 o aviso de exceção de hoje não conta na cota de amanhã', public._agenda_lote_cota(c_hoje + 1) = 1, null);
    -- outra exceção: tirar o Roberto de amanhã no Flávio, que o cliente confirmou
    v_al := md5('f7f:aloc:304:roberto:2026-11-11:manha')::uuid;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, alocacoes_canceladas, payee_id, texto, desfazivel_ate)
    values (pg_temp.em(c_hoje, '14:20'), c_hoje, true, 'vigia', 'cancelar', pg_temp.os('304'), array[pg_temp.os('304')], array[v_al], null,
            'Tirei o Roberto de amanhã de manhã no Flávio.', pg_temp.em(c_hoje, '14:20') + interval '1 day') returning id into v_nova;
    w := public.agenda_aviso_pecas(c_hoje, pg_temp.em(c_hoje, '14:30'));
    r := pg_temp.ok(r, 'O3c acima da cota, a exceção espera o bloco: {avisar false, motivo cota}, com as 3 por contar e a exceção',
      w = jsonb_build_object('avisar', false, 'motivo', 'cota', 'pendentes', 3, 'excecoes', 1), w::text);
    r := pg_temp.ok(r, 'O3d a 1ª trava confere a cota de novo: o enfileirar direto recusa (cota), sem gravar nada',
      public.agenda_aviso_enfileirar('Agenda — teste.', array[v_nova], '{}'::uuid[], false, c_hoje, pg_temp.em(c_hoje, '14:31')) ->> 'motivo' = 'cota'
      and (select count(*) from public.agenda_dono_avisos where dia = c_hoje) = 1 and pg_temp.via(v_nova) = '-', null);
    update public.agenda_config set acordes_dia_max = 2 where id;
    w := pg_temp.avisar(pg_temp.em(c_hoje, '14:45'));
    r := pg_temp.ok(r, 'O3e com acordes_dia_max 2, a 2ª exceção sai; a cota volta a 0',
      (w ->> 'enfileirou')::boolean and pg_temp.via(v_nova) = 'aviso' and public._agenda_lote_cota(c_hoje) = 0 and pg_temp.via(pg_temp.a('01')) = '-', w::text);
    -- o bloco das 17:30 mostra o que esperou, sem frase de "era para te chamar" (R8.5-27)
    b := pg_temp.bloco(c_hoje);
    r := pg_temp.ok(r, 'O3f o bloco conta o que esperou (o encaixe e o remanejo), sem "era para te chamar" (R8.5-27), e não repete o que os avisos contaram',
      exists (select 1 from jsonb_array_elements(pg_temp.no_nivel(b)) l where l ->> 'parte' = 'mudou' and l -> 'acao_ids' @> jsonb_build_array(pg_temp.a('01'), pg_temp.a('02')))
      and not exists (select 1 from jsonb_array_elements(b -> 'linhas') l where l -> 'acao_ids' ?| array[pg_temp.a('03')::text, v_nova::text])
      and (select string_agg(l ->> 'texto', ' ') from jsonb_array_elements(b -> 'linhas') l) not like '%era para te chamar%', pg_temp.texto_do_bloco(b));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- o acorde do dia conta na mesma cota (uma fonte só, §3.1 item 4)
    perform pg_temp.prepara();
    perform pg_temp.modos('ligado', 'ligado');
    insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, texto, contada_em, contada_via)
    values (c_hoje, true, 'vigia', 'mover', pg_temp.os('305'), array[pg_temp.os('305')], 'Um acorde de hoje.', pg_temp.em(c_hoje, '10:00'), 'acorde');
    v := public.agenda_aviso_pecas(c_hoje, pg_temp.em(c_hoje, '14:15'));
    r := pg_temp.ok(r, 'O3g o acorde de hoje gastou a cota: a exceção espera o bloco', v ->> 'motivo' = 'cota' and public._agenda_lote_cota(c_hoje) = 0, v::text);
    r := pg_temp.ok(r, 'O3h o aviso de exceção de ontem e o aviso de sempre de hoje não contam na cota de hoje',
      public._agenda_lote_cota(c_hoje + 1) = 1, null);
    -- o aviso de sempre, a semana e a exceção que não entrou na fila não contam na cota
    insert into public.agenda_dono_avisos (rodada, dia, texto, acao_ids, pergunta_ids, telefone, enviar_em, estado, dedupe_key, fila_id)
    values (pg_temp.em(c_hoje + 1, '10:00'), c_hoje + 1, 'Agenda — de antes do lote.', array[pg_temp.a('01')], '{}', '5547900000210', pg_temp.em(c_hoje + 1, '10:00'), 'enfileirada',
            'agenda-dono:aviso:teste-cota', gen_random_uuid()),
           (pg_temp.em(c_hoje + 1, '10:01'), c_hoje + 1, 'Agenda — a semana.', '{}', array[pg_temp.q('01')], '5547900000210', pg_temp.em(c_hoje + 1, '10:01'), 'enfileirada',
            'agenda-dono:semana:' || (c_hoje + 1)::text, gen_random_uuid());
    insert into public.agenda_dono_avisos (rodada, dia, texto, acao_ids, pergunta_ids, telefone, enviar_em, estado, recusa_motivo, dedupe_key, fila_id, devolvida_em)
    values (pg_temp.em(c_hoje + 1, '10:02'), c_hoje + 1, 'Agenda — exceção recusada.', array[pg_temp.a('01')], '{}', '5547900000210', pg_temp.em(c_hoje + 1, '10:02'), 'recusada', 'janela',
            'agenda-dono:excecao:teste-cota', null, pg_temp.em(c_hoje + 1, '10:02'));
    r := pg_temp.ok(r, 'O3j o aviso de sempre, a mensagem da semana e a exceção que não entrou na fila não gastam a cota', public._agenda_lote_cota(c_hoje + 1) = 1,
      public._agenda_lote_cota(c_hoje + 1)::text);
    r := pg_temp.ok(r, 'O3i sem o dia: 22004', pg_temp.lanca($q$select public._agenda_lote_cota(null)$q$) = '22004', null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$o$;

-- ── O4. A quinta ────────────────────────────────────────────────────────────────────────────────────
do $o$
declare
  r       jsonb := '[]';
  c_qui   constant date := date '2026-11-12';
  c_17    constant timestamptz := timestamptz '2026-11-12 17:00-03';
  v       jsonb;
  w       jsonb;
  p       jsonb;
  b       jsonb;
  v_txt   text;
  v_id    uuid;
  v_q     uuid;
begin
  if not pg_temp.na_bancada() then return; end if;
  begin
    perform pg_temp.prepara();
    perform pg_temp.modos('ligado', 'ligado');
    r := pg_temp.ok(r, 'O4a fora do dia do plano (ter 10/11), antes da hora (qui 16:45): nada',
      public._agenda_comunicar_quinta(date '2026-11-10', timestamptz '2026-11-10 17:00-03') = '{"pulado": true, "motivo": "dia"}'::jsonb
      and public._agenda_comunicar_quinta(c_qui, timestamptz '2026-11-12 16:45-03') = '{"pulado": true, "motivo": "cedo"}'::jsonb, null);
    update public.agenda_config set dono_semana_aviso = 'fechamento' where id;
    r := pg_temp.ok(r, 'O4b com dono_semana_aviso = fechamento, nada aqui (a semana vai no bloco); e o enfileirar da semana recusa (modo)',
      public._agenda_comunicar_quinta(c_qui, c_17) = '{"pulado": true, "motivo": "fechamento"}'::jsonb
      and public.agenda_aviso_enfileirar('Agenda — a semana.', '{}'::uuid[], array[pg_temp.q('01')], true, c_qui, c_17, true) ->> 'motivo' = 'modo', null);
    update public.agenda_config set dono_semana_aviso = 'propria' where id;
    perform pg_temp.modos('desligado', 'ligado');
    r := pg_temp.ok(r, 'O4c com o lote desligado, nada', public._agenda_comunicar_quinta(c_qui, c_17) = '{"pulado": true, "motivo": "desligado"}'::jsonb, null);
    perform pg_temp.modos('ligado', 'ligado');
    v := public._agenda_comunicar_quinta(c_qui, c_17);
    p := v -> 'avisos' -> 0;
    v_txt := public._agenda_lote_texto(p);
    r := pg_temp.ok(r, 'O4d no 1º tique depois de dono_semana_hora: as peças, semana, com o que mudou e não foi contado (as 3) e as perguntas',
      jsonb_array_length(v -> 'avisos') = 1 and (p ->> 'semana')::boolean and jsonb_array_length(p -> 'mudancas') = 3
      and p ->> 'cabecalho' = 'Agenda — o que eu mudei sozinho:' and p ->> 'rodape' = '*agenda plano* mostra tudo.'
      and jsonb_array_length(p #> '{perguntas,pergunta_ids}') between 1 and 5, v::text);
    r := pg_temp.ok(r, 'O4e o texto: as mudanças, "Para a semana que vem preciso de:", as linhas na ordem com "Decisão N:", o fim de sempre; dentro do teto do aviso (R8.5-13)',
      v_txt like 'Agenda — o que eu mudei sozinho:' || E'\n• %' and v_txt like '%' || E'\n\nPara a semana que vem preciso de:\n· %'
      and v_txt like '%· Decisão %' and v_txt like '%' || E'\nPode ser um áudio só, citando o nome do cliente.'
      and char_length(v_txt) <= (select gestor_aviso_texto_max from public.agenda_config where id), v_txt);
    r := pg_temp.ok(r, 'O4e2 com o freio, nenhuma linha promete prazo (o veto_ate do texto é nulo, P2)', v_txt not like '%Sem resposta até%', null);
    r := pg_temp.ok(r, 'O4e3 até perguntas_abertas_max linhas e "(e mais N em *agenda pendências*)" com o resto',
      (select count(*) from regexp_matches(v_txt, E'\n· ', 'g')) = least(5, (select count(*) from jsonb_array_elements(public.agenda_perguntas_em_ordem(c_qui, c_17))))
      and (case when (select count(*) from jsonb_array_elements(public.agenda_perguntas_em_ordem(c_qui, c_17))) > 5 then v_txt like '%(e mais % em *agenda pendências*)%' else true end), null);
    -- a cota do dia gasta por um acorde: a semana não conta nela
    insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, texto, contada_em, contada_via)
    values (c_qui, true, 'vigia', 'mover', pg_temp.os('305'), array[pg_temp.os('305')], 'Um acorde de hoje.', pg_temp.em(c_qui, '10:00'), 'acorde');
    w := pg_temp.comunicar(c_17, c_17 + interval '20 seconds');
    v_id := (w -> 'enfileirar' -> 0 ->> 'id')::uuid;
    r := pg_temp.ok(r, 'O4f pela rodada comunicar: o aviso devolvido vai à fila pela origem agenda-dono, com a chave da semana, as 3 mudanças contadas e as perguntas',
      (w -> 'enfileirar' -> 0 ->> 'enfileirou')::boolean
      and (select v2.dedupe_key = 'agenda-dono:semana:2026-11-12' and v2.com_perguntas and cardinality(v2.acao_ids) = 3 and cardinality(v2.pergunta_ids) between 1 and 5
             from public.agenda_dono_avisos v2 where v2.id = v_id)
      and (select q.source = 'agenda-dono' and q.message = public._agenda_lote_texto(w -> 'avisos' -> 0) from public.whatsapp_send_queue q where q.id = (w -> 'enfileirar' -> 0 ->> 'fila_id')::uuid)
      and pg_temp.via(pg_temp.a('01')) = 'aviso' and pg_temp.via(pg_temp.a('02')) = 'aviso' and pg_temp.via(pg_temp.a('03')) = 'aviso', w::text);
    r := pg_temp.ok(r, 'O4g uma vez: a 2ª rodada devolve {ja_saiu}, e o enfileirar da semana de novo, ja_existe',
      public._agenda_comunicar_quinta(c_qui, c_17 + interval '15 minutes') = '{"ja_saiu": true, "estado": "enfileirada"}'::jsonb
      and public.agenda_aviso_enfileirar('Agenda — de novo.', '{}'::uuid[], array[pg_temp.q('01')], true, c_qui, c_17 + interval '16 minutes', true) ->> 'motivo' = 'ja_existe', null);
    -- o bloco das 17:30 da quinta: a semana já foi, e nada se repete
    perform pg_temp.saiu(c_17 + interval '1 minute');
    b := pg_temp.bloco(c_qui);
    r := pg_temp.ok(r, 'O4h o bloco das 17:30 da quinta: sem a parte semana, sem as mudanças que ela contou e sem as perguntas não críticas que ela levou (a crítica volta: a regra do P3)',
      not exists (select 1 from jsonb_array_elements(b -> 'linhas') l where l ->> 'parte' = 'semana' or l -> 'acao_ids' ?| array[pg_temp.a('01')::text, pg_temp.a('02')::text, pg_temp.a('03')::text])
      and not exists (select 1 from jsonb_array_elements(b -> 'linhas') l join public.agenda_dono_avisos v2 on v2.id = v_id
                       join public.agenda_perguntas q on q.id = (l ->> 'pergunta_id')::uuid
                       where l ->> 'pergunta_id' is not null and q.id = any (v2.pergunta_ids) and not q.critica)
      and exists (select 1 from jsonb_array_elements(b -> 'linhas') l join public.agenda_perguntas q on q.id = (l ->> 'pergunta_id')::uuid where q.critica), pg_temp.texto_do_bloco(b));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- a quinta com tudo o que havia: o bloco das 17:30 só diz a hora em que ela foi (R8.5-15)
    perform pg_temp.prepara();
    perform pg_temp.modos('ligado', 'ligado');
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste do lote' where estado = 'aberta';
    w := pg_temp.comunicar(c_17, c_17 + interval '20 seconds');
    perform pg_temp.saiu(c_17 + interval '1 minute');
    b := pg_temp.bloco(c_qui);
    r := pg_temp.ok(r, 'O4h2 a quinta levou tudo: o veredito do bloco diz "a semana que vem foi às 17:01; desde então nada mudou."',
      (w -> 'enfileirar' -> 0 ->> 'enfileirou')::boolean and pg_temp.texto_do_bloco(b) like 'Agenda: a semana que vem foi às 17:01; desde então nada mudou.%', pg_temp.texto_do_bloco(b));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- O4b: sem mudança, com pergunta, sai do mesmo jeito
    perform pg_temp.prepara();
    perform pg_temp.modos('ligado', 'ligado');
    update public.agenda_acoes set contada_em = timestamptz '2026-11-11 17:30-03', contada_via = 'fechamento' where contada_em is null and executada;
    w := pg_temp.comunicar(c_17, c_17 + interval '20 seconds');
    p := w -> 'contagens' -> 'quinta';
    r := pg_temp.ok(r, 'O4i sem mudança, com pergunta aberta: sai pela fila (agenda-dono), sem ação, com o cabeçalho da semana e as perguntas (O4b)',
      (w -> 'enfileirar' -> 0 ->> 'enfileirou')::boolean
      and (select cardinality(v2.acao_ids) = 0 and cardinality(v2.pergunta_ids) > 0 and v2.texto like 'Agenda — a semana que vem:' || E'\n*agenda plano* mostra tudo.\n\nPara a semana que vem preciso de:%'
             from public.agenda_dono_avisos v2 where v2.id = (w -> 'enfileirar' -> 0 ->> 'id')::uuid)
      and (select count(*) from public.whatsapp_send_queue q where q.source = 'agenda-dono' and q.dedupe_key = 'agenda-dono:semana:2026-11-12') = 1, w::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- sem nada: nem mudança nem pergunta
    perform pg_temp.prepara();
    perform pg_temp.modos('ligado', 'ligado');
    update public.agenda_acoes set contada_em = timestamptz '2026-11-11 17:30-03', contada_via = 'fechamento' where contada_em is null and executada;
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste do lote' where estado = 'aberta';
    r := pg_temp.ok(r, 'O4j sem mudança e sem pergunta: nada a mandar ({motivo nada}); o enfileirar da semana sem as duas = 22023; o aviso de sempre sem mudança, 22023 como antes',
      public._agenda_comunicar_quinta(c_qui, c_17) = '{"motivo": "nada"}'::jsonb
      and pg_temp.lanca(format($q$select public.agenda_aviso_enfileirar('Agenda — a semana.', '{}'::uuid[], '{}'::uuid[], true, %L::date, %L::timestamptz, true)$q$, c_qui, c_17)) = '22023'
      and pg_temp.lanca(format($q$select public.agenda_aviso_enfileirar('Agenda — teste.', '{}'::uuid[], array[%L::uuid], true, %L::date, %L::timestamptz)$q$, pg_temp.q('01'), c_qui, c_17)) = '22023', null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.prepara();
    perform pg_temp.modos('ligado', 'ligado');
    r := pg_temp.ok(r, 'O4j2 p_semana nulo é o aviso de sempre: sem mudança, 22023',
      pg_temp.lanca(format($q$select public.agenda_aviso_enfileirar('Agenda — teste.', '{}'::uuid[], array[%L::uuid], true, %L::date, %L::timestamptz, null)$q$, pg_temp.q('01'), c_qui, c_17)) = '22023', null);
    update public.agenda_perguntas set opcao_escolhida = 1 where id = pg_temp.q('07');
    v := public._agenda_comunicar_quinta(c_qui, c_17);
    r := pg_temp.ok(r, 'O4x a pergunta que o dono já escolheu não volta na quinta',
      not (v -> 'avisos' -> 0 #> '{perguntas,pergunta_ids}') ? pg_temp.q('07')::text and jsonb_array_length(v -> 'avisos' -> 0 #> '{perguntas,pergunta_ids}') > 0, v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- o CHECK: só a mensagem da semana vai sem ação, e só com pergunta
    perform pg_temp.prepara();
    r := pg_temp.ok(r, 'O4k o CHECK novo: sem ação, só a chave da semana e com pergunta; o aviso de sempre sem ação e a semana sem pergunta, 23514',
      pg_temp.lanca($q$insert into public.agenda_dono_avisos (rodada, dia, texto, acao_ids, pergunta_ids, telefone, enviar_em, dedupe_key)
                       values (now(), current_date, 'Agenda.', '{}', '{}', '5547900000210', now(), 'agenda-dono:aviso:x')$q$) = '23514'
      and pg_temp.lanca($q$insert into public.agenda_dono_avisos (rodada, dia, texto, acao_ids, pergunta_ids, telefone, enviar_em, dedupe_key)
                           values (now(), current_date, 'Agenda.', '{}', '{}', '5547900000210', now(), 'agenda-dono:semana:2026-11-12')$q$) = '23514'
      and pg_temp.lanca(format($q$insert into public.agenda_dono_avisos (rodada, dia, texto, acao_ids, pergunta_ids, telefone, enviar_em, dedupe_key)
                                  values (now(), current_date, 'Agenda.', '{}', array[%L::uuid], '5547900000210', now(), 'agenda-dono:semana:2026-11-12')$q$, pg_temp.q('01'))) = 'ok'
      and pg_temp.lanca($q$insert into public.agenda_dono_avisos (rodada, dia, texto, acao_ids, pergunta_ids, telefone, enviar_em, dedupe_key)
                           values (now() + interval '1 second', current_date, 'Agenda.', '{}', '{}', '5547900000210', now(), 'agenda-dono:excecao:x')$q$) = '23514', null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- a sombra: só quinta_diria, com o texto, uma vez por dia; nada na fila
    perform pg_temp.prepara();
    perform pg_temp.modos('sombra', 'sombra');
    w := public.agenda_comunicar_rodar(c_qui, c_17);
    r := pg_temp.ok(r, 'O4l em sombra: contagens.quinta.quinta_diria com o texto, nenhum aviso devolvido, nada registrado nem na fila',
      w #>> '{contagens,quinta,quinta_diria,texto}' like 'Agenda — o que eu mudei sozinho:%Para a semana que vem preciso de:%'
      and (w #>> '{contagens,quinta,quinta_diria,cabe}')::boolean and w -> 'avisos' = '[]'::jsonb
      and not exists (select 1 from public.agenda_dono_avisos where dia = c_qui) and not exists (select 1 from public.whatsapp_send_queue where source = 'agenda-dono')
      and (select x.contagens #>> '{quinta,quinta_diria,caracteres}' from public.agenda_vigia_rodadas x where x.rotina = 'comunicar' order by x.rodou_em desc limit 1)::int
          = char_length(w #>> '{contagens,quinta,quinta_diria,texto}'), w::text);
    r := pg_temp.ok(r, 'O4m a 2ª rodada em sombra no mesmo dia não diz de novo ({ja_diria})',
      public._agenda_comunicar_quinta(c_qui, c_17 + interval '15 minutes') = '{"ja_diria": true}'::jsonb, null);
    v_txt := w #>> '{contagens,quinta,quinta_diria,texto}';
    perform pg_temp.modos('ligado', 'ligado');
    r := pg_temp.ok(r, 'O4n o texto que a sombra diz é o que sairia ligado: as mesmas peças, o mesmo montador',
      v_txt = public._agenda_lote_texto(public._agenda_comunicar_quinta(c_qui, c_17) -> 'avisos' -> 0), null);
    perform pg_temp.modos('ligado', 'sombra');
    r := pg_temp.ok(r, 'O4o o lote ligado com o bloco em sombra age como sombra (O2): só diz, e já disse hoje',
      public._agenda_comunicar_quinta(c_qui, c_17) = '{"ja_diria": true}'::jsonb
      and public.agenda_aviso_enfileirar('Agenda — a semana.', '{}'::uuid[], array[pg_temp.q('01')], true, c_qui, c_17, true) ->> 'motivo' = 'modo', null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$o$;

-- ── O4 (o prazo). O que estava no texto é o que vale ────────────────────────────────────────────────
-- §3.1 item 7: o prazo só começa de um prazo que o dono leu. A quinta grava, depois que a fila mandou, o prazo de cada pergunta cuja linha está no texto que saiu; com o freio, só o
-- veto_teria_em (o que seria, para medir), como o registrar do P3.
do $o$
declare
  r       jsonb := '[]';
  c_qui   constant date := date '2026-11-12';
  c_17    constant timestamptz := timestamptz '2026-11-12 17:00-03';
  w       jsonb;
  v_q     public.agenda_perguntas;
  v_txt   text;
begin
  if not pg_temp.na_bancada() then return; end if;
  begin
    perform pg_temp.prepara();
    perform pg_temp.modos('ligado', 'ligado');
    -- o teto (perguntas_abertas_max) fecharia as mais velhas antes da quinta: com 10, as 8 da fixture ficam abertas e saem todas
    update public.agenda_config set modo_veto = 'ligado', gestor_so_propor = false, perguntas_abertas_max = 10 where id;
    w := pg_temp.comunicar(c_17, c_17 + interval '20 seconds');
    v_txt := (select v.texto from public.agenda_dono_avisos v where v.id = (w -> 'enfileirar' -> 0 ->> 'id')::uuid);
    r := pg_temp.ok(r, 'O4p sem o freio e com o prazo ligado, a linha da quinta promete o prazo: "Sem resposta até sex 13/11 às 18:00"',
      v_txt like '%· Você: %Sem resposta até sex 13/11 às 18:00%', v_txt);
    r := pg_temp.ok(r, 'O4q antes de a fila mandar, nenhum prazo é gravado: o dono ainda não leu',
      public._agenda_comunicar_quinta(c_qui, c_17 + interval '5 minutes') = '{"ja_saiu": true, "estado": "enfileirada"}'::jsonb
      and (select veto_ate is null from public.agenda_perguntas where id = pg_temp.q('01')), null);
    perform pg_temp.saiu(c_17 + interval '1 minute');
    w := public._agenda_comunicar_quinta(c_qui, c_17 + interval '15 minutes');
    select * into v_q from public.agenda_perguntas where id = pg_temp.q('01');
    r := pg_temp.ok(r, 'O4r depois que saiu, o tique seguinte grava o prazo que estava no texto, uma vez; a pergunta contou como mostrada pelo aviso',
      (w ->> 'prazos')::int >= 1 and v_q.veto_ate = timestamptz '2026-11-13 18:00-03' and v_q.mostrada_via = 'aviso' and v_q.mostrada_em = timestamptz '2026-11-12 17:01-03'
      and public._agenda_comunicar_quinta(c_qui, c_17 + interval '30 minutes') = '{"ja_saiu": true, "estado": "enviada"}'::jsonb, w::text);
    r := pg_temp.ok(r, 'O4s a que não promete prazo no texto não ganha prazo (Flávio espera o cliente, a diária é dinheiro); o prazo que já existia fica (Nelson, ter 10/11)',
      (select veto_ate is null from public.agenda_perguntas where id = pg_temp.q('06')) and (select veto_ate is null from public.agenda_perguntas where id = pg_temp.q('08'))
      and (select veto_ate = timestamptz '2026-11-10 18:00-03' from public.agenda_perguntas where id = pg_temp.q('02'))
      and (select count(*) from public.agenda_perguntas q join public.agenda_dono_avisos v on v.dedupe_key = 'agenda-dono:semana:2026-11-12'
            where q.id = any (v.pergunta_ids)) = 8, null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- com o freio: o texto sem prazo, e o tique seguinte só mede
    perform pg_temp.prepara();
    perform pg_temp.modos('ligado', 'ligado');
    update public.agenda_config set modo_veto = 'ligado', gestor_so_propor = true, perguntas_abertas_max = 10 where id;
    w := pg_temp.comunicar(c_17, c_17 + interval '20 seconds');
    perform pg_temp.saiu(c_17 + interval '1 minute');
    w := public._agenda_comunicar_quinta(c_qui, c_17 + interval '15 minutes');
    select * into v_q from public.agenda_perguntas where id = pg_temp.q('01');
    r := pg_temp.ok(r, 'O4t com o freio: a linha não promete prazo, e depois do envio só veto_teria_em (o que seria); veto_ate fica nulo',
      v_q.veto_ate is null and v_q.veto_teria_em = timestamptz '2026-11-13 18:00-03'
      and (select v.texto not like '%Sem resposta até%' from public.agenda_dono_avisos v where v.dedupe_key = 'agenda-dono:semana:2026-11-12'), w::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- o controle que reprova: o freio solto DEPOIS de sair. A linha refeita agora promete prazo, mas não é a do texto que o dono leu: nada é gravado
    perform pg_temp.prepara();
    perform pg_temp.modos('ligado', 'ligado');
    update public.agenda_config set modo_veto = 'ligado', gestor_so_propor = true, perguntas_abertas_max = 10 where id;
    w := pg_temp.comunicar(c_17, c_17 + interval '20 seconds');
    perform pg_temp.saiu(c_17 + interval '1 minute');
    update public.agenda_config set gestor_so_propor = false where id;
    w := public._agenda_comunicar_quinta(c_qui, c_17 + interval '15 minutes');
    select * into v_q from public.agenda_perguntas where id = pg_temp.q('01');
    r := pg_temp.ok(r, 'O4u o freio solto depois do envio: a linha de agora promete prazo, mas o texto que saiu não; nenhum prazo nem teria gravado',
      v_q.veto_ate is null and v_q.veto_teria_em is null and not w ? 'prazos'
      and public._agenda_pergunta_linha(pg_temp.q('01'), c_qui, c_17) ->> 'texto' like '%Sem resposta até%', w::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$o$;

-- ── O5. O acorde fica para o P5 ─────────────────────────────────────────────────────────────────────
-- §5.4 manda "Já avisei o Roberto." quando a mensagem de mudança da pessoa foi registrada. Essa mensagem só nasce no P5: hoje nada a cria. Sem ela, o texto de antes é o certo, e recriar
-- seria cópia sem efeito.
do $o$
declare
  r     jsonb := '[]';
  v_mig text := coalesce(current_setting('agenda_teste.mig_lote_fase7f', true), '');
  v_rob uuid;
begin
  if not pg_temp.na_bancada() then return; end if;
  -- (7f P5) o P5 (20261109101000) recria _agenda_texto_do_acorde com o "Já avisei" e cria a mensagem de mudança: com ele no banco, a viva tem o bloco dele e a prova é
  -- o E3 de agenda_fase7f_equipe.sql; sem ele, o de antes
  r := pg_temp.ok(r, 'O5a a migration não recria _agenda_texto_do_acorde, e a viva não tem bloco da 7f (até o P5, que a recria: E3 de agenda_fase7f_equipe)',
    position('function public._agenda_texto_do_acorde(' in v_mig) = 0
    and (select p.prosrc not like '%FASE 7f%' or (to_regprocedure('public._agenda_comunicar_mudancas_equipe(date, timestamptz)') is not null and p.prosrc like '%(7f P5%')
           from pg_proc p where p.oid = 'public._agenda_texto_do_acorde(uuid, date, date)'::regprocedure), null);
  begin
    perform pg_temp.prepara();
    update public.agenda_config set modo_equipe = 'ligado' where id;
    select id into v_rob from public.payees where name = 'Roberto' and active;
    r := pg_temp.ok(r, 'O5b nenhum caminho registra a mensagem de mudança à equipe: o registrar recusa o tipo (22023), e nenhuma função a insere (até o P5, que a cria)',
      case when to_regprocedure('public._agenda_comunicar_mudancas_equipe(date, timestamptz)') is not null
           -- (7f P5) com o P5: o registrar aceita a mudança no ramo dela (com os modos da equipe desligados, nada grava), e quem a insere é ele
           then (public._agenda_equipe_registrar(v_rob, date '2026-11-11', 'mudanca', 'Roberto, mudou.', now(), null, null, '{}'::date[]) ->> 'modo') = 'desligado'
           else pg_temp.lanca(format($q$select public._agenda_equipe_registrar(%L::uuid, date '2026-11-11', 'mudanca', 'Roberto, mudou.', now())$q$, v_rob)) = '22023'
                and not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosrc ~ 'insert into public\.agenda_equipe_mensagens' and p.prosrc ~ '''mudanca''') end,
      null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$o$;

-- ── O6. As cópias ───────────────────────────────────────────────────────────────────────────────────
do $o$
declare
  r     jsonb := '[]';
  v_mig text := coalesce(current_setting('agenda_teste.mig_lote_fase7f', true), '');
  x     record;
  v_or  text;
begin
  if v_mig = '' or coalesce(current_setting('agenda_teste.mig_correcao2_fase7a', true), '') = '' or coalesce(current_setting('agenda_teste.mig_correcao_revisao', true), '') = ''
     or coalesce(current_setting('agenda_teste.mig_perguntas_fase7f', true), '') = '' then
    perform pg_temp.gravar(pg_temp.ok('[]', 'O6 as cópias', true, 'PULADO: sem as migrations como texto (rode pela bancada)'));
    return;
  end if;
  for x in select * from (values
      ('agenda_aviso_pecas', 'public.agenda_aviso_pecas(date, timestamptz)', 'mig_correcao2_fase7a', 4),
      ('agenda_aviso_enfileirar', 'public.agenda_aviso_enfileirar(text, uuid[], uuid[], boolean, date, timestamptz, boolean)', 'mig_correcao_revisao', 6),
      ('agenda_comunicar_rodar', 'public.agenda_comunicar_rodar(date, timestamptz)', 'mig_perguntas_fase7f', 2)) t(nome, assin, mig, blocos) loop
    v_or := current_setting('agenda_teste.' || x.mig);
    r := pg_temp.ok(r, format('O6a %s: tirados os blocos da 7f, a origem, byte a byte', x.nome),
      char_length(pg_temp.corpo(v_or, x.nome)) > 500 and pg_temp.sem_7f(pg_temp.corpo(v_mig, x.nome)) = replace(pg_temp.corpo(v_or, x.nome), E'\r\n', E'\n'), null);
    r := pg_temp.ok(r, format('O6b %s: a viva é a desta migration', x.nome),
      (select replace(p.prosrc, E'\r\n', E'\n') from pg_proc p where p.oid = x.assin::regprocedure) = pg_temp.corpo(v_mig, x.nome), null);
    r := pg_temp.ok(r, format('O6c %s: %s blocos da 7f, e nenhum aberto dentro de um bloco de antes (os tiradores das etapas de antes não fecham no fim errado)', x.nome, x.blocos),
      (select count(*) from regexp_matches(pg_temp.corpo(v_mig, x.nome), '-- FASE 7f: fim', 'g')) = x.blocos
      and not exists (select 1 from (select l, sum(case when l ~ '^\s*-- FASE 7[bcd]?:' and l !~ ': fim' then 1 when l ~ '^\s*-- FASE 7[bcd]?: fim' then -1 else 0 end) over (order by o) as prof
                                       from unnest(string_to_array(pg_temp.corpo(v_mig, x.nome), E'\n')) with ordinality u(l, o)) y
                       where y.prof > 0 and y.l ~ '^\s*-- FASE 7f:'), null);
  end loop;
  r := pg_temp.ok(r, 'O6d a migration cria as 8 e recria as 3: o conferir, as mudanças do aviso, o acorde, as linhas e o bloco ficam (R8.1)',
    (select string_agg(distinct m[1], ',' order by m[1]) from regexp_matches(v_mig, 'create or replace function public\.([a-z_0-9]+)\(', 'g') m)
    = '_agenda_comunicar_lote_guardaria,_agenda_comunicar_quinta,_agenda_e_excecao,_agenda_lote_cota,_agenda_lote_fora,_agenda_lote_ligado,_agenda_lote_mudancas,_agenda_lote_texto,agenda_aviso_enfileirar,agenda_aviso_pecas,agenda_comunicar_rodar', null);
  -- fora dos corpos das funções (o enfileirar escreve na fila e no registro do aviso, como antes)
  v_or := regexp_replace(v_mig, '\$function\$.*?\$function\$', '', 'g');
  r := pg_temp.ok(r, 'O6e sem dado: fora das funções, nenhum insert, nenhum update; a única mudança de tabela é o CHECK de agenda_dono_avisos',
    v_or ~* 'create or replace function public\._agenda_lote_ligado' and v_or !~* '\n\s*insert into public\.' and v_or !~* '\n\s*update public\.'
    and (select count(*) from regexp_matches(v_or, '\n\s*alter table public\.([a-z_]+)', 'gi')) = 1
    and v_or ~* 'alter table public\.agenda_dono_avisos add constraint dono_aviso_conta_mudanca', null);
  r := pg_temp.ok(r, 'O6f a assinatura de 6 argumentos sai antes da nova (drop), e só ela',
    v_mig ~ 'drop function if exists public\.agenda_aviso_enfileirar\(text, uuid\[\], uuid\[\], boolean, date, timestamptz\);'
    and (select count(*) from regexp_matches(v_mig, '\n\s*drop function', 'g')) = 1, null);
  perform pg_temp.gravar(r);
end
$o$;

-- ── O7 e O9. A rodada de aprontar e o freio ─────────────────────────────────────────────────────────
do $o$
declare
  r      jsonb := '[]';
  c_hoje constant date := date '2026-11-10';
  c_tic  constant timestamptz := timestamptz '2026-11-10 14:15-03';
  a      jsonb;
  b      jsonb;
  c      jsonb;
begin
  if not pg_temp.na_bancada() then return; end if;
  begin
    perform pg_temp.prepara();
    perform pg_temp.modos('sombra', 'sombra');
    a := public.agenda_aviso_pecas(c_hoje, c_tic);
    perform pg_temp.modos('ligado', 'ligado');
    b := public.agenda_aviso_pecas(c_hoje, c_tic);
    update public.agenda_config set gestor_so_propor = false where id;
    c := public.agenda_aviso_pecas(c_hoje, c_tic);
    r := pg_temp.ok(r, 'O7a o controle: sem o lote, a rodada de aprontar vai no aviso (as perguntas que destravam, uma vez por dia)',
      jsonb_typeof(a -> 'perguntas') = 'object' and jsonb_array_length(a #> '{perguntas,pergunta_ids}') > 0, a::text);
    r := pg_temp.ok(r, 'O7b com o lote, a rodada de aprontar não sai no aviso: as perguntas ficam para o bloco e para a quinta (R8.5-14)',
      (b ->> 'avisar')::boolean and b -> 'perguntas' = 'null'::jsonb and b ->> 'perguntas_erro' is null, b::text);
    r := pg_temp.ok(r, 'O9a o lote não respeita o freio (R8.6): com e sem gestor_so_propor, a mesma rodada', b = c, null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$o$;

-- ── O8. O caminho inteiro ───────────────────────────────────────────────────────────────────────────
do $o$
declare
  r      jsonb := '[]';
  c_hoje constant date := date '2026-11-10';
  v      jsonb;
  w      jsonb;
  b      jsonb;
  b2     jsonb;
begin
  if not pg_temp.na_bancada() then return; end if;
  begin
    perform pg_temp.prepara();
    perform pg_temp.modos('ligado', 'ligado');
    -- 14:15 a rodada guarda: só a exceção vai
    v := pg_temp.avisar(pg_temp.em(c_hoje, '14:15'));
    perform pg_temp.saiu(pg_temp.em(c_hoje, '14:20'));
    w := public.agenda_aviso_pecas(c_hoje, pg_temp.em(c_hoje, '14:30'));
    r := pg_temp.ok(r, 'O8a a rodada guarda: o aviso leva a exceção e sai; o tique seguinte não manda o resto ({motivo lote}, 2 por contar)',
      (v ->> 'enfileirou')::boolean and pg_temp.via(pg_temp.a('03')) = 'aviso' and w = '{"avisar": false, "motivo": "lote", "pendentes": 2}'::jsonb, w::text);
    -- 17:30 o bloco mostra; o registro conta
    b := pg_temp.bloco(c_hoje);
    r := pg_temp.ok(r, 'O8b o bloco das 17:30 mostra o que esperou, na linha Mudou, com os ids delas',
      exists (select 1 from jsonb_array_elements(pg_temp.no_nivel(b)) l where l ->> 'parte' = 'mudou'
                 and l -> 'acao_ids' @> jsonb_build_array(pg_temp.a('01'), pg_temp.a('02')) and not l -> 'acao_ids' @> jsonb_build_array(pg_temp.a('03'))),
      pg_temp.texto_do_bloco(b));
    perform public.agenda_fechamento_registrar(c_hoje, pg_temp.no_nivel(b), 'fechamento', pg_temp.em(c_hoje, '17:31'));
    r := pg_temp.ok(r, 'O8c o registro conta: as 2 pelo fechamento, a exceção pelo aviso; cada uma uma vez',
      pg_temp.via(pg_temp.a('01')) = 'fechamento' and pg_temp.via(pg_temp.a('02')) = 'fechamento' and pg_temp.via(pg_temp.a('03')) = 'aviso'
      and (select count(*) from public.agenda_acoes where executada and contada_em is null and desfeita_em is null and dia between c_hoje - 6 and c_hoje) = 0, null);
    -- nada sai 2 vezes nem some
    w := public.agenda_aviso_pecas(c_hoje, pg_temp.em(c_hoje, '18:15'));
    b2 := pg_temp.bloco(date '2026-11-11');
    r := pg_temp.ok(r, 'O8d nada sai 2 vezes: o aviso seguinte não tem nada, o bloco do dia seguinte não repete, 1 aviso e 1 linha na fila no dia',
      w = '{"avisar": false, "motivo": "nada_mudou"}'::jsonb
      and pg_temp.texto_do_bloco(b2) not like '%' || pg_temp.frase(pg_temp.a('01')) || '%' and pg_temp.texto_do_bloco(b2) not like '%' || pg_temp.frase(pg_temp.a('02')) || '%'
      and (select count(*) from public.agenda_dono_avisos where dia = c_hoje) = 1 and (select count(*) from public.whatsapp_send_queue where source = 'agenda-dono') = 1,
      pg_temp.texto_do_bloco(b2));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- o mesmo caminho em sombra: o aviso conta tudo, como antes, e o bloco não repete
    perform pg_temp.prepara();
    perform pg_temp.modos('sombra', 'ligado');
    v := pg_temp.avisar(pg_temp.em(c_hoje, '14:15'));
    b := pg_temp.bloco(c_hoje);
    r := pg_temp.ok(r, 'O8e em sombra o aviso leva as 3, como antes, e o bloco não as repete',
      pg_temp.via(pg_temp.a('01')) = 'aviso' and pg_temp.via(pg_temp.a('02')) = 'aviso' and pg_temp.via(pg_temp.a('03')) = 'aviso'
      and not exists (select 1 from jsonb_array_elements(b -> 'linhas') l where l ->> 'parte' = 'mudou' and l -> 'acao_ids' @> jsonb_build_array(pg_temp.a('01'))), v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$o$;

-- ── O10. "Lote só depois de v_n = 0" ────────────────────────────────────────────────────────────────
-- R8.8 e R8.13: o filtro roda depois de "nada mudou" e das esperas de antes (a janela, a pausa do fechamento, o teto, o dono). A prova: com um dublê de _agenda_lote_ligado que lança,
-- a rodada sem nada, a de fora da janela e a da pausa devolvem o de antes; a rodada com algo a contar chega nele (o controle).
do $o$
declare
  r      jsonb := '[]';
  c_hoje constant date := date '2026-11-10';
  v      jsonb;
  w      jsonb;
begin
  if not pg_temp.na_bancada() then return; end if;
  begin
    perform pg_temp.prepara();
    perform pg_temp.modos('ligado', 'ligado');
    create or replace function public._agenda_lote_ligado() returns boolean language plpgsql as $f$
    begin
      raise exception 'o lote foi lido' using errcode = 'P0099';
    end $f$;
    r := pg_temp.ok(r, 'O10a fora da janela e na pausa do fechamento: a resposta de antes, sem ler o lote',
      public.agenda_aviso_pecas(c_hoje, pg_temp.em(c_hoje, '20:00')) = '{"avisar": false, "motivo": "fora_da_janela", "janela": "janela", "pendentes": 3}'::jsonb
      and public.agenda_aviso_pecas(c_hoje, pg_temp.em(c_hoje, '17:30')) = '{"avisar": false, "motivo": "fechamento", "pendentes": 3}'::jsonb, null);
    r := pg_temp.ok(r, 'O10b o controle: com algo a contar, na janela, a rodada chega no lote (o dublê lança)',
      pg_temp.lanca(format($q$select public.agenda_aviso_pecas(%L::date, %L::timestamptz)$q$, c_hoje, pg_temp.em(c_hoje, '14:15'))) = 'P0099', null);
    update public.agenda_acoes set contada_em = pg_temp.em(c_hoje, '12:00'), contada_via = 'fechamento' where contada_em is null and executada;
    v := public.agenda_aviso_pecas(c_hoje, pg_temp.em(c_hoje, '14:15'));
    r := pg_temp.ok(r, 'O10c a rodada sem nada (v_n = 0): {avisar false, motivo nada_mudou}, a de antes, sem ler o lote', v = '{"avisar": false, "motivo": "nada_mudou"}'::jsonb, v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- e a rodada sem nada é a mesma com o lote desligado (o código de antes)
    perform pg_temp.prepara();
    update public.agenda_acoes set contada_em = pg_temp.em(c_hoje, '12:00'), contada_via = 'fechamento' where contada_em is null and executada;
    v := public.agenda_aviso_pecas(c_hoje, pg_temp.em(c_hoje, '14:15'));
    perform pg_temp.modos('ligado', 'ligado');
    w := public.agenda_aviso_pecas(c_hoje, pg_temp.em(c_hoje, '14:15'));
    r := pg_temp.ok(r, 'O10d a rodada sem nada: desligado e ligado dão o mesmo', v = w, w::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$o$;

-- ── O11. A rodada comunicar ─────────────────────────────────────────────────────────────────────────
do $o$
declare
  r      jsonb := '[]';
  c_hoje constant date := date '2026-11-10';
  c_tic  constant timestamptz := timestamptz '2026-11-10 14:15-03';
  c_17   constant timestamptz := timestamptz '2026-11-12 17:00-03';
  v      jsonb;
  w      jsonb;
  v_n    int;
  v_al   uuid;
  v_nova uuid;
begin
  if not pg_temp.na_bancada() then return; end if;
  begin
    -- com tudo em sombra, a rodada não manda nada novo
    perform pg_temp.prepara();
    update public.agenda_config set modo_bloco_agenda = 'sombra', modo_veto = 'sombra', modo_lote_dono = 'sombra', modo_equipe_previsto = 'sombra', modo_equipe_convite = 'sombra',
                                    modo_cliente_camadas = 'sombra' where id;
    v_n := (select count(*) from public.whatsapp_send_queue) + (select count(*) from public.agenda_dono_avisos) + (select count(*) from public.agenda_equipe_mensagens)
           + (select count(*) from public.agenda_cliente_mensagens);
    w := pg_temp.comunicar(c_17, c_17 + interval '20 seconds');
    r := pg_temp.ok(r, 'O11a com os 6 em sombra: a rodada roda, não devolve aviso e nada entra na fila nem nos registros de mensagem; a quinta só diz',
      (w ->> 'rodou')::boolean and w -> 'avisos' = '[]'::jsonb and w -> 'enfileirar' = '[]'::jsonb
      and (select count(*) from public.whatsapp_send_queue) + (select count(*) from public.agenda_dono_avisos) + (select count(*) from public.agenda_equipe_mensagens)
          + (select count(*) from public.agenda_cliente_mensagens) = v_n
      and w #> '{contagens,quinta,quinta_diria}' is not null and w #> '{contagens,lote_guardaria}' = '{"modo": "sombra"}'::jsonb, w::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- em sombra, com o aviso desta rodada: o que o lote teria guardado
    perform pg_temp.prepara();
    perform pg_temp.modos('sombra', 'sombra');
    v := pg_temp.avisar(c_tic);
    w := public.agenda_comunicar_rodar(c_hoje, c_tic);
    r := pg_temp.ok(r, 'O11b em sombra, contagens.lote_guardaria: do aviso desta rodada, o lote levaria a exceção e guardaria as 2 e as perguntas',
      (v ->> 'enfileirou')::boolean
      and w #>> '{contagens,lote_guardaria,modo}' = 'sombra' and w #>> '{contagens,lote_guardaria,aviso}' = v ->> 'id'
      and w #> '{contagens,lote_guardaria,levaria,ids}' = jsonb_build_array(pg_temp.a('03'))
      and w #> '{contagens,lote_guardaria,guardaria,ids}' @> jsonb_build_array(pg_temp.a('01'), pg_temp.a('02'))
      and (w #>> '{contagens,lote_guardaria,guardaria,acoes}')::int = 2
      and (w #>> '{contagens,lote_guardaria,guardaria,perguntas}')::int = jsonb_array_length(v #> '{pecas,perguntas,pergunta_ids}')
      and (w #>> '{contagens,lote_guardaria,acima_da_cota}')::int = 0
      and (select x.contagens -> 'lote_guardaria' from public.agenda_vigia_rodadas x where x.rotina = 'comunicar' order by x.rodou_em desc limit 1) = w #> '{contagens,lote_guardaria}', w::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.prepara();
    perform pg_temp.modos('sombra', 'sombra');
    insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, texto, contada_em, contada_via)
    values (c_hoje, true, 'vigia', 'mover', pg_temp.os('305'), array[pg_temp.os('305')], 'Um acorde de hoje.', pg_temp.em(c_hoje, '10:00'), 'acorde');
    v := pg_temp.avisar(c_tic);
    w := public.agenda_comunicar_rodar(c_hoje, c_tic);
    r := pg_temp.ok(r, 'O11b2 em sombra, com a cota gasta por um acorde: a exceção do aviso teria esperado o bloco (acima_da_cota 1)',
      (w #>> '{contagens,lote_guardaria,acima_da_cota}')::int = 1, w::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.prepara();
    perform pg_temp.modos('sombra', 'sombra');
    v := pg_temp.avisar(c_tic);
    w := public.agenda_comunicar_rodar(c_hoje, c_tic + interval '15 minutes');
    r := pg_temp.ok(r, 'O11c a rodada seguinte, sem aviso dela: só o modo', w #> '{contagens,lote_guardaria}' = '{"modo": "sombra"}'::jsonb, w::text);
    perform pg_temp.modos('desligado', 'sombra');
    w := public.agenda_comunicar_rodar(c_hoje, c_tic + interval '30 minutes');
    r := pg_temp.ok(r, 'O11d com o lote desligado, a chave não aparece', (w ->> 'rodou')::boolean and not w -> 'contagens' ? 'lote_guardaria', w::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- ligado: a cota e a exceção acima dela, que o P7 conta na saúde
    perform pg_temp.prepara();
    perform pg_temp.modos('ligado', 'ligado');
    w := public.agenda_comunicar_rodar(c_hoje, c_tic);
    r := pg_temp.ok(r, 'O11e ligado, com cota: {modo ligado, cota_livre 1}', w #> '{contagens,lote_guardaria}' = '{"modo": "ligado", "cota_livre": 1}'::jsonb, w::text);
    v := pg_temp.avisar(c_tic + interval '1 minute');
    v_al := md5('f7f:aloc:304:roberto:2026-11-11:manha')::uuid;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, alocacoes_canceladas, texto, desfazivel_ate)
    values (pg_temp.em(c_hoje, '14:20'), c_hoje, true, 'vigia', 'cancelar', pg_temp.os('304'), array[pg_temp.os('304')], array[v_al],
            'Tirei o Roberto de amanhã de manhã no Flávio.', pg_temp.em(c_hoje, '14:20') + interval '1 day') returning id into v_nova;
    w := public.agenda_comunicar_rodar(c_hoje, pg_temp.em(c_hoje, '14:30'));
    r := pg_temp.ok(r, 'O11f ligado, sem cota: a exceção que espera o bloco, com o id (é dali que o P7 a conta na saúde, R8.5-27)',
      w #> '{contagens,lote_guardaria}' = jsonb_build_object('modo', 'ligado', 'cota_livre', 0, 'acima_da_cota', 1, 'acima_da_cota_ids', jsonb_build_array(v_nova)), w::text);
    update public.agenda_acoes set contada_em = pg_temp.em(c_hoje, '14:31'), contada_via = 'fechamento' where contada_em is null and executada;
    w := public.agenda_comunicar_rodar(c_hoje, pg_temp.em(c_hoje, '14:45'));
    r := pg_temp.ok(r, 'O11f2 ligado, sem cota e sem nada por contar: só a cota, sem ler as mudanças', w #> '{contagens,lote_guardaria}' = '{"modo": "ligado", "cota_livre": 0}'::jsonb, w::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- o pré-passo que falha não derruba a rodada
    perform pg_temp.prepara();
    perform pg_temp.modos('sombra', 'sombra');
    create or replace function public._agenda_comunicar_lote_guardaria(p_hoje date, p_agora timestamptz) returns jsonb language plpgsql as $f$
    begin
      raise exception 'estourou' using errcode = 'P0098';
    end $f$;
    v_n := (select count(*) from public.app_error_logs where action = 'comunicar:lote_guardaria');
    w := public.agenda_comunicar_rodar(c_hoje, c_tic);
    r := pg_temp.ok(r, 'O11g o pré-passo que falha: registra em comunicar:lote_guardaria, entra em falhas, e os passos rodam',
      (w ->> 'rodou')::boolean and (w ->> 'erros')::int = 1 and w -> 'falhas' -> 0 ->> 'passo' = 'lote_guardaria'
      and w -> 'contagens' ? 'destrava' and w -> 'contagens' ? 'quinta' and not w -> 'contagens' ? 'lote_guardaria'
      and (select count(*) from public.app_error_logs where action = 'comunicar:lote_guardaria') = v_n + 1, w::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  r := pg_temp.ok(r, 'O11h sem o dia ou a hora: 22004 no pré-passo, 22023 na quinta',
    pg_temp.lanca($q$select public._agenda_comunicar_lote_guardaria(null, now())$q$) = '22004'
    and pg_temp.lanca($q$select public._agenda_comunicar_quinta(current_date, null)$q$) = '22023', null);
  perform pg_temp.gravar(r);
end
$o$;

select teste, ok, detalhe from _resultado order by ok, teste;
rollback;
