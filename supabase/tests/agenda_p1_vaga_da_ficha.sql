-- Prova da vaga da ficha de amanhã, parte 1: a conta (pacote 1 do assistente, 27/11/2026; migration 20270301120500_agenda_p1_vaga_da_ficha.sql;
-- achado NOVO-agenda-p1-18). Na qui 26/11/2026 a pergunta dos dias das 16:45 tomou a 2ª vaga do dia e a ficha de sex 27/11 nasceu recusada
-- por teto: _agenda_equipe_previstas_hoje deixava de contar a ficha sempre que a confirmação do dia tinha saído, mesmo com o dia já fora do
-- plano (sem "como foi" para levá-la). Agora a ficha só deixa de contar à parte quando o "como foi" de HOJE ainda vai nascer: a confirmação
-- de hoje saiu (não recusada), a pessoa ainda tem plano vivo hoje e o "como foi" de hoje não foi registrado.
-- bancada: depende de 20270301120500
--
--   P0  a forma (vale em produção, nada grava): P0a a porta de antes (invoker, STABLE, EXECUTE só de service_role, search_path=public); P0b
--       nenhum UPDATE/DELETE sem WHERE; P0c tirado o bloco "-- P1 AGENDA: (VAGA," e devolvidas as 3 linhas "--antes:", o corpo é o de antes
--       (md5 sem CR 7e86318b…, o da 20261109101000 e o de produção), o corpo vivo é outro e há exatamente 1 bloco; P0d a forma do bloco: o
--       CÓDIGO dele (sem as linhas de comentário) não lê a chave do silêncio nem a hora da ficha, não lê a configuração, não usa o relógio e
--       não traz número nem hora literal (só o "select 1" dos exists e os tipos e estados que a função de antes já lia); fica antes do bloco
--       "-- FASE 7f:"; P0e o comentário ganhou o trecho uma vez, no fim; P0f o único chamador continua sendo agenda_equipe_semana
--   Sobre a fixture-fase3 (o Roberto, telefone sintético 5547900000001, na rotina, com dias fixos; qui 05/11/2026 o dia todo no Vanderlei,
--   OS-00069; a pergunta dos dias ligada), com o Roberto fixado pelo dono no Lenine (OS-00074) na sex 06/11 de manhã: o plano de amanhã.
--   Cada tique é a rotina (agenda_rotina_rodar) e, depois, a semana da equipe (agenda_equipe_semana), na ordem do task-automations:
--   V0  o ponto de partida: o teto 2, a pergunta dos dias às 16:45, a ficha às 19:30, o plano de hoje e o de amanhã, a quinta da pergunta
--   V1  o caso de qui 26/11 ('tirar', técnico calado), com a ficha às 19:30 e às 17:45: V1a a confirmação das 07:45 sai e o silêncio das
--       09:00 tira o dia (o plano de amanhã fica de pé); V1b às 16:45 a conta dá 1 (a ficha guarda a vaga), a pergunta dos dias é adiada
--       (nenhuma linha 'dias') e às 17:00 não há "como foi"; V1d na hora da ficha ela é enfileirada como a 2ª do dia; a fila do dia fica
--       com 2 proativas e a pergunta continua adiada; V1e a saúde: ficha_recusada_por_teto_com_dias = 0
--   V1c o controle: o MESMO cenário com o corpo de antes (o corpo vivo sem o bloco, recriado só dentro da subtransação): a conta dá 0, a
--       pergunta dos dias sai às 16:45 como a 2ª e a ficha nasce recusada por teto (a saúde acusa 1). É o defeito de 26/11
--   V2  'manter', técnico calado (o mundo de produção): o 2º pedido das 09:00 é tipo resposta; 16:45 a conta dá 1 e a pergunta é adiada;
--       17:00 o "como foi" leva a ficha; na hora da ficha, nada novo; 2 proativas na fila. V2c igual ao corpo de antes, byte a byte
--   V3  ele respondeu "ok" de manhã: a conta dá 1, a pergunta é adiada, "como foi" + ficha. Igual ao corpo de antes
--   V4  sem plano hoje e com plano amanhã: a conta dá 1; a pergunta sai como a 1ª e a ficha como a 2ª. Igual ao corpo de antes. V4b a
--       confirmação não sai (ele já confirmou o dia na véspera) com plano hoje e amanhã: a conta dá 2 (o "como foi" e a ficha, cada um com
--       a sua vaga), a pergunta é adiada, o "como foi" vai sem a ficha e a ficha vai sozinha. Igual ao corpo de antes. V4c a confirmação
--       nasce RECUSADA (veto: a ficha de hoje segurada) com plano hoje e amanhã: recusada não é "saiu", a conta dá 2. Igual ao de antes
--   V5  'manter' e o dia sai do plano depois da confirmação (V5a ele diz "hoje não vou"; V5b o dono tira o dia): 16:45 a pergunta é adiada
--       e a ficha vai sozinha como a 2ª. V5c o controle com o corpo de antes: a pergunta sai e a ficha é recusada por teto
--   V6  a confirmação saiu e o "como foi" de hoje já foi registrado SEM a ficha (ela espera o "mande" do dono): a conta dá 1 (antes 0)
--   V7  a pergunta adiada sai noutro dia: na sexta, com 2 mensagens, adia de novo; no sábado às 16:45 sai (1 linha 'dias' na semana)
--   V8  o teto nunca é passado: em todos os cenários acima com o corpo novo, as proativas na fila do dia <= equipe_proativas_dia_max
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration:  npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_p1_vaga_da_ficha.sql
--   Sem a fixture (produção) os V saem PULADO; P0 roda e não grava nada. Termina em ROLLBACK: nada fica gravado e nenhuma mensagem sai.
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
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
-- O corpo (prosrc, sem CR) de uma função pela assinatura.
create function pg_temp.src(p_assinatura text) returns text language sql stable as $f$
  select replace(p.prosrc, chr(13), '') from pg_proc p where p.oid = to_regprocedure(p_assinatura)
$f$;
-- Tira os blocos "-- <marca>: … -- <marca>: fim" (p_marca é uma alternância de regex), devolvendo as linhas "--antes:" de dentro deles: o
-- corpo de antes (o mesmo removedor de agenda_p1_silencio.sql).
create function pg_temp.sem_blocos(p text, p_marca text) returns text language sql immutable as $st$
  select array_to_string(array(
           select case when dentro > 0 and l ~ '^--antes:' then substr(l, 9) else l end
             from (select l, o, sum(case when l ~ ('^\s*-- (' || p_marca || '):') and l !~ ('^\s*-- (' || p_marca || '): fim') then 1
                                         when l ~ ('^\s*-- (' || p_marca || '): fim') then -1 else 0 end)
                                over (order by o rows between unbounded preceding and current row) as dentro,
                          l ~ ('^\s*-- (' || p_marca || '): fim') as fecha
                     from unnest(string_to_array(replace(p, chr(13), ''), E'\n')) with ordinality u(l, o)) x
            where (dentro = 0 and not fecha) or (dentro > 0 and l ~ '^--antes:')
            order by o), E'\n')
$st$;
-- Só o CÓDIGO do bloco "-- P1 AGENDA: (VAGA, …" (sem as linhas de comentário: a de abrir, a de fechar, as do texto e as "--antes:").
create function pg_temp.codigo_da_vaga(p text) returns text language plpgsql immutable as $st$
declare
  l      text;
  fora   text[] := '{}';
  dentro boolean := false;
begin
  foreach l in array string_to_array(replace(p, chr(13), ''), E'\n') loop
    if not dentro and l ~ '^\s*-- P1 AGENDA: \(VAGA,' then dentro := true; continue; end if;
    if dentro and l ~ '^\s*-- P1 AGENDA: fim' then dentro := false; continue; end if;
    if dentro and l !~ '^\s*--' then fora := fora || l; end if;
  end loop;
  return array_to_string(fora, E'\n');
end $st$;
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
-- Um tique, na ordem do task-automations: a rotina da equipe e, depois, a semana da equipe (a pergunta dos dias é sempre decidida depois da
-- rotina do mesmo tique). A resposta do Roberto (o telefone sintético da fixture-fase3) e o worker que manda (na bancada ninguém manda).
create function pg_temp.tique(p_dia date, p_hora text) returns jsonb language plpgsql as $f$
declare
  a jsonb;
  b jsonb;
begin
  a := public.agenda_rotina_rodar(p_dia, pg_temp.em(p_dia, p_hora));
  b := public.agenda_equipe_semana(p_dia, pg_temp.em(p_dia, p_hora));
  return jsonb_build_object('rotina', a, 'semana', b,
                            'erros', coalesce((a ->> 'erros')::int, 0) + coalesce((b ->> 'erros')::int, 0)
                                     + case when coalesce((a ->> 'rodou')::boolean, false) and coalesce((b ->> 'rodou')::boolean, false) then 0 else 1 end);
end $f$;
create function pg_temp.resp(p_texto text, p_dia date, p_hora text) returns jsonb language sql as $f$
  select public.agenda_resposta_da_equipe('5547900000001', p_texto, md5(p_texto || p_dia || p_hora), pg_temp.em(p_dia, p_hora))
$f$;
create function pg_temp.saiu(p_dia date, p_hora text) returns void language sql as $f$
  update public.whatsapp_send_queue set status = 'sent', sent_at = pg_temp.em(p_dia, p_hora)
   where source = 'agenda-equipe' and status = 'pending' and scheduled_for <= pg_temp.em(p_dia, p_hora)
$f$;
-- A mensagem de um tipo da pessoa no dia (a mais nova).
create function pg_temp.msg(p_payee uuid, p_tipo text, p_dia date) returns public.agenda_equipe_mensagens language sql stable as $f$
  select * from public.agenda_equipe_mensagens where payee_id = p_payee and tipo = p_tipo and dia = p_dia order by criada_em desc, id desc limit 1
$f$;
-- Os meios-dias vigentes da pessoa no dia (fora reserva): o "plano vivo" que a conta e a rotina leem.
create function pg_temp.vivo(p_payee uuid, p_dia date) returns int language sql stable as $f$
  select count(*)::int from public.agenda_alocacoes a
   where a.payee_id = p_payee and a.dia = p_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
$f$;
-- As mensagens à pessoa, na ordem em que saem: "HH:MI tipo estado[/motivo][ (leva a ficha de DD/MM)]" com o dia de envio quando não é p_dia.
create function pg_temp.linha(p_payee uuid, p_dia date) returns text language sql stable as $f$
  select coalesce(string_agg(format('%s %s %s%s%s',
           to_char(m.enviar_em at time zone 'America/Sao_Paulo', case when (m.enviar_em at time zone 'America/Sao_Paulo')::date = p_dia then 'HH24:MI' else 'DD/MM HH24:MI' end),
           m.tipo, m.estado, coalesce('/' || m.recusa_motivo, ''),
           case when m.leva_ficha_de is not null then ' (leva a ficha de ' || to_char(m.leva_ficha_de, 'DD/MM') || ')' else '' end),
           '; ' order by m.enviar_em, m.criada_em, m.tipo), '(nenhuma)')
    from public.agenda_equipe_mensagens m where m.payee_id = p_payee
$f$;
-- O retrato das mensagens à pessoa e da fila dela (sem os ids): o que se compara, byte a byte, entre o corpo novo e o de antes.
create function pg_temp.retrato(p_payee uuid) returns jsonb language sql stable as $f$
  select jsonb_build_object(
    'mensagens', (select coalesce(jsonb_agg(jsonb_build_object('tipo', m.tipo, 'dia', m.dia, 'modo', m.modo, 'estado', m.estado, 'motivo', m.recusa_motivo,
                                                               'leva', m.leva_ficha_de, 'texto', m.texto, 'enviar_em', m.enviar_em, 'chave', m.dedupe_key,
                                                               'na_fila', m.fila_id is not null, 'resposta', m.resposta_texto)
                                            order by m.enviar_em, m.criada_em, m.tipo, m.dedupe_key), '[]'::jsonb)
                    from public.agenda_equipe_mensagens m where m.payee_id = p_payee),
    'fila', (select coalesce(jsonb_agg(jsonb_build_object('chave', q.dedupe_key, 'quando', q.scheduled_for, 'texto', md5(q.message), 'status', q.status)
                                       order by q.scheduled_for, q.dedupe_key), '[]'::jsonb)
               from public.whatsapp_send_queue q join public.agenda_equipe_mensagens m on m.id = q.source_ref_id
              where q.source = 'agenda-equipe' and m.payee_id = p_payee))
$f$;
-- O corpo de ANTES no lugar do vivo (o vivo sem o bloco, com as "--antes:" devolvidas), com o cabeçalho de sempre. Só dentro de uma
-- subtransação desfeita: é o controle (V1c, V5c) e a régua do "igual ao de antes". Devolve o md5 do corpo recriado.
create function pg_temp.corpo_de_antes() returns text language plpgsql as $f$
declare
  v_antes text := pg_temp.sem_blocos(pg_temp.src('public._agenda_equipe_previstas_hoje(uuid,date,timestamptz)'), 'P1 AGENDA');
begin
  execute format('create or replace function public._agenda_equipe_previstas_hoje(p_payee uuid, p_hoje date, p_agora timestamp with time zone) '
                 'returns integer language plpgsql stable set search_path to ''public'' as %L', v_antes);
  return md5(pg_temp.src('public._agenda_equipe_previstas_hoje(uuid,date,timestamptz)'));
end $f$;
-- A quinta 05/11 do Roberto, tique a tique, num dos mundos: p_acao é a chave do silêncio ('tirar' ou 'manter'); p_hora_ficha, a hora da
-- ficha ('19:30' ou '17:45'); p_manha, o que acontece de manhã: 'calado' (não responde), 'ok' (responde ok às 08:10), 'nao_vou' (responde
-- "hoje não vou" às 08:10), 'dono_tira' (o dono tira o dia dele às 08:10, depois da confirmação), 'sem_plano_hoje' (o dia sai antes das
-- 07:45), 'ja_confirmou' (ele respondeu "ok" à ficha na véspera: o dia já está confirmado e a confirmação das 07:45 não sai) ou
-- 'confirmacao_vetada' (a ficha de HOJE está segurada: a confirmação das 07:45 nasce recusada por veto). Devolve o que se observou. Não
-- desfaz nada: quem chama desfaz (pg_temp.roda).
create function pg_temp.quinta(p_acao text, p_hora_ficha text, p_manha text) returns jsonb language plpgsql as $f$
declare
  c_rob   constant uuid := 'bb000000-0000-4000-8000-000000000002';
  d       constant date := date '2026-11-05';
  am      constant date := date '2026-11-06';
  c_ficha constant time := p_hora_ficha::time;
  t       jsonb;
  v       jsonb := '{}'::jsonb;
  v_erros int := 0;
  v_h     text;
begin
  -- a chave do silêncio e a hora da ficha do caso (com a ficha às 17:45 a janela do veto do dono fecha às 17:30, como em produção: o CHECK
  -- de agenda_config pede veto_hora < equipe_hora_ficha)
  update public.agenda_config
     set equipe_silencio_acao = p_acao, equipe_hora_ficha = c_ficha,
         veto_hora = case when veto_hora < c_ficha then veto_hora else c_ficha - interval '15 minutes' end
   where id;
  if p_manha = 'sem_plano_hoje' then
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'dono'
     where payee_id = c_rob and dia = d and estado in ('publicada', 'fixada');
  elsif p_manha = 'ja_confirmou' then
    -- o que o "ok" à ficha da véspera grava (agenda_resposta_da_equipe): o dia confirmado; _agenda_rotina_confirmar pula quem já confirmou
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, trecho, criado_em)
    values (c_rob, daterange(d, d, '[]'), 'confirmada', 'diarista', 'Confirmou a ficha: ok', 'ok', pg_temp.em(d - 1, '19:40'));
  elsif p_manha = 'confirmacao_vetada' then
    -- a ficha de HOJE segurada (a regra trocada só aqui por uma que diz "não" para hoje e "sim" para os outros dias: a subtransação a
    -- desfaz, como no S8c de agenda_p1_silencio.sql): a confirmação das 07:45 fica registrada como recusada (veto) e não vai à fila
    create or replace function public._agenda_ficha_liberada(p_payee uuid, p_dia date, p_agora timestamptz) returns boolean
      language sql stable set search_path to 'public' as $fl$ select p_dia is distinct from date '2026-11-05' $fl$;
  end if;
  t := pg_temp.tique(d, '07:45');
  v_erros := v_erros + (t ->> 'erros')::int;
  perform pg_temp.saiu(d, '07:46');
  v := v || jsonb_build_object('confirmar_0745', coalesce((pg_temp.msg(c_rob, 'confirmar', d)).estado, '-'));
  if p_manha = 'ok' then
    perform pg_temp.resp('ok', d, '08:10');
  elsif p_manha = 'nao_vou' then
    perform pg_temp.resp('hoje não vou', d, '08:10');
  elsif p_manha = 'dono_tira' then
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'dono'
     where payee_id = c_rob and dia = d and estado in ('publicada', 'fixada');
  end if;
  t := pg_temp.tique(d, '09:00');
  v_erros := v_erros + (t ->> 'erros')::int;
  perform pg_temp.saiu(d, '09:01');
  v := v || jsonb_build_object(
    'silencio_0900', coalesce((t #>> '{rotina,contagens,silencio,silencio}')::int, 0),
    'segundo_pedido', coalesce((select r.tipo || ' ' || r.estado from public.agenda_equipe_mensagens r
                                 where r.dedupe_key = format('agenda-equipe:resposta:%s:reconfirmar:%s', c_rob, d)), '-'),
    'confirmar_0900', coalesce((pg_temp.msg(c_rob, 'confirmar', d)).estado, '-'));
  -- 16:45: a conta (antes do tique) e a pergunta dos dias (no tique)
  v := v || jsonb_build_object(
    'hoje_vivo', pg_temp.vivo(c_rob, d), 'amanha_vivo', pg_temp.vivo(c_rob, am),
    'fila_1645', public._agenda_equipe_no_dia(c_rob, d, false, null),
    'previstas_1645', public._agenda_equipe_previstas_hoje(c_rob, d, pg_temp.em(d, '16:45')));
  t := pg_temp.tique(d, '16:45');
  v_erros := v_erros + (t ->> 'erros')::int;
  perform pg_temp.saiu(d, '16:46');
  v := v || jsonb_build_object(
    'adiada_1645', coalesce((t #>> '{semana,contagens,perguntar,adiada}')::int, 0),
    'saiu_1645', coalesce((t #>> '{semana,contagens,perguntar,enfileirada}')::int, 0),
    'dias_1645', (select count(*) from public.agenda_equipe_mensagens m where m.payee_id = c_rob and m.tipo = 'dias'));
  -- 17:00: o "como foi"
  v := v || jsonb_build_object('previstas_1700', public._agenda_equipe_previstas_hoje(c_rob, d, pg_temp.em(d, '17:00')));
  t := pg_temp.tique(d, '17:00');
  v_erros := v_erros + (t ->> 'erros')::int;
  perform pg_temp.saiu(d, '17:01');
  v := v || jsonb_build_object(
    'como_foi', coalesce((select m.estado || case when m.leva_ficha_de is not null then ' leva ' || m.leva_ficha_de else ' sem a ficha' end
                            from public.agenda_equipe_mensagens m where m.payee_id = c_rob and m.tipo = 'como_foi' and m.dia = d), '-'),
    'adiada_1700', coalesce((t #>> '{semana,contagens,perguntar,adiada}')::int, 0),
    'saiu_1700', coalesce((t #>> '{semana,contagens,perguntar,enfileirada}')::int, 0));
  -- o tique de antes da hora da ficha, o da hora e o seguinte
  foreach v_h in array array[to_char(c_ficha - interval '15 minutes', 'HH24:MI'), to_char(c_ficha, 'HH24:MI'),
                             to_char(c_ficha + interval '15 minutes', 'HH24:MI')] loop
    if v_h::time = c_ficha then
      v := v || jsonb_build_object(
        'ficha_antes_da_hora', coalesce((pg_temp.msg(c_rob, 'ficha', am)).estado, '-'),
        'fila_na_hora', public._agenda_equipe_no_dia(c_rob, d, false, null),
        'previstas_na_hora', public._agenda_equipe_previstas_hoje(c_rob, d, pg_temp.em(d, v_h)));
    end if;
    t := pg_temp.tique(d, v_h);
    v_erros := v_erros + (t ->> 'erros')::int;
    perform pg_temp.saiu(d, v_h);
    if v_h::time = c_ficha then
      v := v || jsonb_build_object(
        'ficha_no_tique', coalesce(t #> '{rotina,contagens,ficha,por_estado}', 'null'::jsonb),
        'adiada_na_hora', coalesce((t #>> '{semana,contagens,perguntar,adiada}')::int, 0),
        'saiu_na_hora', coalesce((t #>> '{semana,contagens,perguntar,enfileirada}')::int, 0));
    elsif v_h::time > c_ficha then
      v := v || jsonb_build_object('ficha_no_tique_seguinte', coalesce(t #> '{rotina,contagens,ficha,por_estado}', 'null'::jsonb));
    end if;
  end loop;
  return v || jsonb_build_object(
    'erros', v_erros,
    'ficha', coalesce((select m.estado || coalesce('/' || m.recusa_motivo, '') || case when m.fila_id is not null then ' na fila' else '' end
                               || ' às ' || to_char(m.enviar_em at time zone 'America/Sao_Paulo', 'HH24:MI')
                         from public.agenda_equipe_mensagens m where m.payee_id = c_rob and m.tipo = 'ficha' and m.dia = am), '-'),
    'dias', coalesce((select string_agg(m.estado || ' ' || to_char(m.enviar_em at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI'), ', ' order by m.enviar_em)
                        from public.agenda_equipe_mensagens m where m.payee_id = c_rob and m.tipo = 'dias'), '-'),
    'proativas', public._agenda_equipe_no_dia(c_rob, d, false, null),
    'respostas', public._agenda_equipe_no_dia(c_rob, d, true, null),
    'saude', (public.agenda_saude(d, pg_temp.em(d, '20:00')) #>> '{equipe_dias,ficha_recusada_por_teto_com_dias}')::int,
    'linha', pg_temp.linha(c_rob, d),
    'retrato', pg_temp.retrato(c_rob));
end $f$;
-- Roda a quinta com o corpo novo ('novo') ou com o de antes ('antes') e desfaz tudo (a subtransação): só o que se observou fica.
create function pg_temp.roda(p_corpo text, p_acao text, p_hora_ficha text, p_manha text) returns jsonb language plpgsql as $f$
declare
  r jsonb;
begin
  begin
    if p_corpo = 'antes' then
      r := jsonb_build_object('md5_do_corpo', pg_temp.corpo_de_antes());
    else
      r := jsonb_build_object('md5_do_corpo', md5(pg_temp.src('public._agenda_equipe_previstas_hoje(uuid,date,timestamptz)')));
    end if;
    r := r || pg_temp.quinta(p_acao, p_hora_ficha, p_manha);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  return r;
end $f$;

-- ── P0. A forma (vale em produção; nada grava) ───────────────────────────────────────────────────────────────────────────────────────
do $p0$
declare
  v_res   jsonb := '[]'::jsonb;
  c_p     constant text := 'public._agenda_equipe_previstas_hoje(uuid,date,timestamptz)';
  c_antes constant text := '7e86318b5a6ba01f3b960a9a73debb3a';
  v_s     text := coalesce(pg_temp.src(c_p), '');
  v_cod   text;
  v_sem_c text;
  v_com   text := coalesce(obj_description(to_regprocedure(c_p), 'pg_proc'), '');
begin
  v_res := pg_temp.ok(v_res, 'P0a _agenda_equipe_previstas_hoje: a porta de antes (invoker, STABLE | anon authenticated service_role public = só service_role) e search_path=public',
    pg_temp.porta(c_p) = 'f s | f f t f'
    and exists (select 1 from pg_proc p, unnest(p.proconfig) c where p.oid = to_regprocedure(c_p) and replace(c, '"', '') = 'search_path=public')
    and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = '_agenda_equipe_previstas_hoje') = 1
    and (select pg_get_function_result(p.oid) from pg_proc p where p.oid = to_regprocedure(c_p)) = 'integer',
    coalesce(pg_temp.porta(c_p), 'NÃO EXISTE') || ' config '
    || coalesce((select array_to_string(p.proconfig, ',') from pg_proc p where p.oid = to_regprocedure(c_p)), '-'));
  v_res := pg_temp.ok(v_res, 'P0b _agenda_equipe_previstas_hoje: nenhum UPDATE/DELETE sem WHERE (pg_safeupdate); a função só lê (nenhum insert, update ou delete)',
    not exists (select 1 from pg_temp.sem_where(v_s))
    and regexp_replace(v_s, '--[^\n]*', '', 'g') !~* '\m(insert|update|delete)\M',
    (select string_agg(x, ' | ') from pg_temp.sem_where(v_s) x));
  v_res := pg_temp.ok(v_res, 'P0c sem o bloco "-- P1 AGENDA: (VAGA," (devolvidas as 3 linhas "--antes:") o corpo é o de antes (md5 sem CR 7e86318b…, o da 20261109101000 e o de produção); o corpo vivo é outro; exatamente 1 bloco',
    md5(pg_temp.sem_blocos(v_s, 'P1 AGENDA')) = c_antes and md5(v_s) <> c_antes
    and (select count(*) from regexp_matches(v_s, '^\s*-- P1 AGENDA: \(VAGA, 27/11/2026\)', 'gn')) = 1
    and (select count(*) from regexp_matches(v_s, '^\s*-- P1 AGENDA:', 'gn')) = 2
    and (select count(*) from regexp_matches(v_s, '^\s*-- P1 AGENDA: fim', 'gn')) = 1
    and (select count(*) from regexp_matches(v_s, '^--antes:', 'gn')) = 3,
    format('sem o bloco %s; vivo %s; blocos VAGA %s; linhas --antes: %s', md5(pg_temp.sem_blocos(v_s, 'P1 AGENDA')), md5(v_s),
           (select count(*) from regexp_matches(v_s, '^\s*-- P1 AGENDA: \(VAGA, 27/11/2026\)', 'gn')),
           (select count(*) from regexp_matches(v_s, '^--antes:', 'gn'))));
  v_cod := pg_temp.codigo_da_vaga(v_s);
  v_sem_c := regexp_replace(v_s, '--[^\n]*', '', 'g');
  v_res := pg_temp.ok(v_res, 'P0d a forma do bloco: o CÓDIGO dele (sem os comentários) não lê a chave do silêncio nem a hora da ficha (nem a função inteira), não lê a configuração nem o relógio, não traz número nem hora literal (só o "select 1" dos exists) e só os tipos e estados que a função de antes já lia; exige as três coisas juntas; fica antes do bloco "-- FASE 7f:"',
    length(v_cod) > 0
    and v_cod !~ 'equipe_silencio_acao|equipe_hora_ficha' and v_sem_c !~ 'equipe_silencio_acao|equipe_hora_ficha'
    and v_cod !~* 'agenda_config|_agenda_cfg|\mcf\.|\m(now|clock_timestamp|current_date|current_timestamp|localtimestamp)\M'
    and replace(v_cod, 'exists (select 1 from', 'exists (select from') !~ '[0-9]'
    and (select array_agg(distinct m[1] order by m[1]) from regexp_matches(v_cod, '''([^'']*)''', 'g') m)
        = array['como_foi', 'confirmar', 'fixada', 'publicada', 'recusada', 'reserva']
    and regexp_replace(v_cod, '\s+', ' ', 'g') like
        '%and not (exists (select 1 from public.agenda_equipe_mensagens m where m.payee_id = p_payee and m.modo = v_modo and m.tipo = ''confirmar'' and m.dia = p_hoje and m.estado <> ''recusada'') and exists (select 1 from public.agenda_alocacoes a where a.payee_id = p_payee and a.dia = p_hoje and a.estado in (''publicada'', ''fixada'') and a.tipo <> ''reserva'') and not exists (select 1 from public.agenda_equipe_mensagens m where m.payee_id = p_payee and m.modo = v_modo and m.tipo = ''como_foi'' and m.dia = p_hoje)) then'
    and position('-- P1 AGENDA: fim' in v_s) between 1 and position('-- FASE 7f:' in v_s),
    regexp_replace(v_cod, '\s+', ' ', 'g'));
  v_res := pg_temp.ok(v_res, 'P0e o comentário da função ganhou o trecho "P1 AGENDA (VAGA, 27/11/2026, 20270301120500)" uma vez, no fim (o de antes fica à frente, inteiro)',
    (select count(*) from regexp_matches(v_com, 'P1 AGENDA \(VAGA, 27/11/2026', 'g')) = 1
    and v_com like 'Agenda de Produção (Fase 7b, P3; §3.1-7, §5.2): quantas mensagens a rotina da equipe ainda vai começar hoje para a pessoa%'
    and v_com like '%FASE 7f (P5): na quinta,%(R8.5-19). P1 AGENDA (VAGA, 27/11/2026, 20270301120500): a ficha de amanhã só deixa de contar à parte quando%'
    and v_com like '%Vale com as duas ações do silêncio e com qualquer hora da ficha.',
    format('%s letras; fim: …%s', length(v_com), right(v_com, 150)));
  v_res := pg_temp.ok(v_res, 'P0f o único chamador da conta continua sendo agenda_equipe_semana (a pergunta dos dias): nenhuma outra função do banco a chama',
    (select string_agg(p.proname, ', ' order by p.proname) from pg_proc p
      where p.pronamespace = 'public'::regnamespace and p.proname <> '_agenda_equipe_previstas_hoje'
        and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') like '%_agenda_equipe_previstas_hoje(%') = 'agenda_equipe_semana'
    and pg_temp.src('public.agenda_equipe_semana(date,timestamptz)')
        like '%public._agenda_equipe_no_dia((e ->> ''id'')::uuid, p_hoje, false, null)%+ public._agenda_equipe_previstas_hoje((e ->> ''id'')::uuid, p_hoje, p_agora) < cf.equipe_proativas_dia_max%',
    (select string_agg(p.proname, ', ' order by p.proname) from pg_proc p
      where p.pronamespace = 'public'::regnamespace and p.proname <> '_agenda_equipe_previstas_hoje'
        and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') like '%_agenda_equipe_previstas_hoje(%'));
  perform pg_temp.gravar(v_res);
end
$p0$;

-- ── V. O Roberto na quinta 05/11 (a fixture-fase3) ───────────────────────────────────────────────────────────────────────────────────
do $v$
declare
  v_res     jsonb := '[]'::jsonb;
  c_roberto constant uuid := 'bb000000-0000-4000-8000-000000000002';
  c_vand    constant uuid := '05000000-0000-4000-8000-000000000069';
  c_lenine  constant uuid := '05000000-0000-4000-8000-000000000074';
  c_p       constant text := 'public._agenda_equipe_previstas_hoje(uuid,date,timestamptz)';
  c_antes   constant text := '7e86318b5a6ba01f3b960a9a73debb3a';
  d05       constant date := date '2026-11-05';   -- a quinta (hoje)
  d06       constant date := date '2026-11-06';   -- a sexta (amanhã)
  d07       constant date := date '2026-11-07';   -- o sábado
  d09       constant date := date '2026-11-09';   -- a segunda
  v_teto    int;
  v_vivo    text;
  v_h       text;
  v_m       text;
  n         jsonb;   -- com o corpo novo
  a         jsonb;   -- com o corpo de antes
  t         jsonb;
  x         jsonb;
  v_prox    jsonb := '{}'::jsonb;   -- as proativas na fila do dia de cada cenário com o corpo novo (V8)
  v_i       int;
  v_j       int;
  v_k       int;
  v_txt     text;
begin
  if coalesce(current_setting('agenda_teste.fase3', true), '') = '' then
    insert into _resultado values ('V0–V8 (fixture-fase3)', true, 'PULADO: sem agenda_teste.fase3 (rode pela bancada)');
    return;
  end if;
  begin
  execute current_setting('agenda_teste.fase3');
  update public.agenda_config set modo_equipe = 'ligado', modo_dias = 'ligado' where id;
  -- o plano de amanhã: o dono fixa o Roberto no Lenine na sex 06/11 de manhã (fixada: o replano do silêncio e o do "não vou" não a movem,
  -- como a alocação de sex 27/11 ficou de pé em 26/11)
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, fixado_por, publicada_em)
  values (c_lenine, c_roberto, d06, 'manha', 'turno', 'execucao', 'fixada', 'dono', 'dono', pg_temp.em(d05, '07:00'));
  v_teto := (select cfg.equipe_proativas_dia_max from public.agenda_config cfg);
  v_vivo := (select string_agg(format('%s %s %s', a2.dia, a2.turno, so.service_order_number), ', ' order by a2.dia, a2.turno)
               from public.agenda_alocacoes a2 join public.service_orders so on so.id = a2.service_order_id
              where a2.payee_id = c_roberto and a2.dia in (d05, d06) and a2.estado in ('publicada', 'fixada') and a2.tipo <> 'reserva');

  v_res := pg_temp.ok(v_res, 'V0 o ponto de partida: o teto de proativas 2, a pergunta dos dias às 16:45, o "como foi" às 17:00, a ficha às 19:30, a chave do silêncio no padrão (tirar), a equipe e a pergunta dos dias ligadas; o Roberto na rotina, com telefone e dias fixos, na qui 05/11 o dia todo no Vanderlei e na sex 06/11 de manhã no Lenine; a semana perguntada é a de seg 16/11 (da qui 05/11 até a ter 10/11); a função viva é a nova',
    (select cfg.equipe_proativas_dia_max = 2 and cfg.equipe_hora_dias = time '16:45' and cfg.equipe_hora_como_foi = time '17:00'
            and cfg.equipe_hora_ficha = time '19:30' and cfg.equipe_silencio_acao = 'tirar' and cfg.modo_equipe = 'ligado' and cfg.modo_dias = 'ligado'
            and cfg.modo_cadastro = 'desligado' and cfg.modo_equipe_previsto = 'desligado' and cfg.modo_equipe_convite = 'desligado'
       from public.agenda_config cfg)
    and v_vivo = '2026-11-05 manha OS-00069, 2026-11-05 tarde OS-00069, 2026-11-06 manha OS-00074'
    and exists (select 1 from public.agenda_equipe_contato c where c.payee_id = c_roberto and c.recebe_rotina and c.parou_em is null)
    and public._agenda_equipe_tem_telefone(c_roberto)
    and exists (select 1 from public.agenda_disponibilidade dp where dp.payee_id = c_roberto and dp.substituida_em is null and dp.dias_semana is not null
                                                             and dp.situacao in ('disponivel', 'confirmada'))
    and public._agenda_semana_perguntada(d05) ->> 'quinta' = '2026-11-05' and public._agenda_semana_perguntada(d05) ->> 'seg' = '2026-11-16'
    and public._agenda_semana_perguntada(d05) ->> 'pode_perguntar_ate' = '2026-11-10'
    and extract(isodow from d05)::int = 4 and public.agenda_somar_du(d05, 1) = d06 and public.agenda_somar_du(d06, 1) = d09
    and md5(pg_temp.src(c_p)) <> c_antes,
    format('teto %s | plano %s | semana %s', v_teto, v_vivo, public._agenda_semana_perguntada(d05)));

  -- ── V1 e V1c. O caso de qui 26/11: 'tirar', técnico calado; com a ficha às 19:30 e às 17:45 ──
  foreach v_h in array array['19:30', '17:45'] loop
    n := pg_temp.roda('novo', 'tirar', v_h, 'calado');
    a := pg_temp.roda('antes', 'tirar', v_h, 'calado');
    v_prox := v_prox || jsonb_build_object(format('V1 %s', v_h), n -> 'proativas');
    v_res := pg_temp.ok(v_res, format('V1a (ficha às %s) o cenário de qui 26/11: a confirmação das 07:45 sai (1ª do dia); às 09:00, sem resposta, o silêncio tira o dia (a confirmação vira sem_resposta, nenhum 2º pedido); às 16:45 o Roberto não tem plano vivo hoje, tem 1 meio-dia amanhã e 1 proativa na fila do dia', v_h),
      n ->> 'confirmar_0745' = 'enfileirada' and (n ->> 'silencio_0900')::int = 1 and n ->> 'confirmar_0900' = 'sem_resposta'
      and n ->> 'segundo_pedido' = '-' and (n ->> 'hoje_vivo')::int = 0 and (n ->> 'amanha_vivo')::int = 1 and (n ->> 'fila_1645')::int = 1
      and (n ->> 'erros')::int = 0,
      (n - 'retrato' - 'linha')::text);
    v_res := pg_temp.ok(v_res, format('V1b (ficha às %s) às 16:45 a conta dá 1 (a ficha de amanhã guarda a vaga dela: 1 na fila + 1 prevista = o teto) e a pergunta dos dias é ADIADA: nenhuma linha ''dias'' é criada; às 17:00 não nasce "como foi" (sem plano hoje) e a pergunta continua adiada', v_h),
      (n ->> 'previstas_1645')::int = 1 and (n ->> 'fila_1645')::int + (n ->> 'previstas_1645')::int = v_teto
      and (n ->> 'adiada_1645')::int = 1 and (n ->> 'saiu_1645')::int = 0 and (n ->> 'dias_1645')::int = 0
      and (n ->> 'previstas_1700')::int = 1 and n ->> 'como_foi' = '-' and (n ->> 'adiada_1700')::int = 1 and (n ->> 'saiu_1700')::int = 0,
      format('previstas 16:45 %s | fila %s | adiada %s | saiu %s | linhas dias %s | 17:00 como foi %s, adiada %s', n ->> 'previstas_1645', n ->> 'fila_1645',
             n ->> 'adiada_1645', n ->> 'saiu_1645', n ->> 'dias_1645', n ->> 'como_foi', n ->> 'adiada_1700'));
    v_res := pg_temp.ok(v_res, format('V1d (ficha às %s) na hora da ficha (não antes) a ficha de sex 06/11 é enfileirada como a 2ª do dia (havia 1 na fila); a fila do dia fica com 2 proativas (a confirmação e a ficha), a pergunta dos dias continua adiada (nenhuma linha ''dias'') e o tique seguinte não manda nada', v_h),
      n ->> 'ficha_antes_da_hora' = '-' and (n ->> 'fila_na_hora')::int = 1 and (n ->> 'previstas_na_hora')::int = 1
      and n -> 'ficha_no_tique' = '{"enfileirada": 1}'::jsonb and n ->> 'ficha' = format('enfileirada na fila às %s', v_h)
      and (n ->> 'adiada_na_hora')::int = 1 and (n ->> 'saiu_na_hora')::int = 0 and n ->> 'dias' = '-'
      and n -> 'ficha_no_tique_seguinte' = '{}'::jsonb
      and (n ->> 'proativas')::int = 2 and (n ->> 'respostas')::int = 0
      and n ->> 'linha' = format('07:45 confirmar sem_resposta; %s ficha enfileirada', v_h),
      format('%s | proativas %s | ficha %s | dias %s', n ->> 'linha', n ->> 'proativas', n ->> 'ficha', n ->> 'dias'));
    v_res := pg_temp.ok(v_res, format('V1e (ficha às %s) a saúde: ficha_recusada_por_teto_com_dias = 0 (a pergunta dos dias não tomou a vaga da ficha)', v_h),
      (n ->> 'saude')::int = 0, n ->> 'saude');
    v_res := pg_temp.ok(v_res, format('V1c (ficha às %s) o CONTROLE: o mesmo cenário com o corpo de antes (o vivo sem o bloco, md5 7e86318b…) repete o defeito de 26/11 — a conta dá 0 (1 na fila + 0 < o teto), a pergunta dos dias SAI às 16:45 como a 2ª do dia e a ficha de sex 06/11 nasce RECUSADA por teto, fora da fila; a saúde acusa 1', v_h),
      a ->> 'md5_do_corpo' = c_antes and n ->> 'md5_do_corpo' <> c_antes
      and a ->> 'confirmar_0745' = 'enfileirada' and (a ->> 'silencio_0900')::int = 1 and (a ->> 'hoje_vivo')::int = 0 and (a ->> 'amanha_vivo')::int = 1
      and (a ->> 'fila_1645')::int = 1 and (a ->> 'previstas_1645')::int = 0
      and (a ->> 'adiada_1645')::int = 0 and (a ->> 'saiu_1645')::int = 1 and (a ->> 'dias_1645')::int = 1 and a ->> 'dias' = 'enfileirada 05/11 16:45'
      and a ->> 'como_foi' = '-' and (a ->> 'fila_na_hora')::int = 2
      and a -> 'ficha_no_tique' = '{"recusada": 1}'::jsonb and a ->> 'ficha' = format('recusada/teto às %s', v_h)
      and (a ->> 'proativas')::int = 2 and (a ->> 'saude')::int = 1 and (a ->> 'erros')::int = 0
      and a ->> 'linha' = format('07:45 confirmar sem_resposta; 16:45 dias enfileirada; %s ficha recusada/teto', v_h),
      format('corpo %s | previstas %s | %s | saúde %s', a ->> 'md5_do_corpo', a ->> 'previstas_1645', a ->> 'linha', a ->> 'saude'));
  end loop;

  -- ── V2. 'manter', técnico calado (o mundo de produção desde 27/11): tem de ficar IGUAL ──
  foreach v_h in array array['19:30', '17:45'] loop
    n := pg_temp.roda('novo', 'manter', v_h, 'calado');
    a := pg_temp.roda('antes', 'manter', v_h, 'calado');
    v_prox := v_prox || jsonb_build_object(format('V2 %s', v_h), n -> 'proativas');
    v_res := pg_temp.ok(v_res, format('V2a (ficha às %s) ''manter'', técnico calado: às 09:00 o dia fica (2 meios-dias hoje), a confirmação continua enfileirada e o 2º pedido é tipo resposta (conta no teto de respostas, não no de proativas); às 16:45 a conta dá 1 (o "como foi" que vai nascer) e a pergunta dos dias é adiada', v_h),
      n ->> 'confirmar_0745' = 'enfileirada' and (n ->> 'silencio_0900')::int = 1 and n ->> 'confirmar_0900' = 'enfileirada'
      and n ->> 'segundo_pedido' = 'resposta enfileirada' and (n ->> 'hoje_vivo')::int = 2 and (n ->> 'amanha_vivo')::int = 1
      and (n ->> 'fila_1645')::int = 1 and (n ->> 'previstas_1645')::int = 1
      and (n ->> 'adiada_1645')::int = 1 and (n ->> 'saiu_1645')::int = 0 and (n ->> 'dias_1645')::int = 0 and (n ->> 'erros')::int = 0,
      (n - 'retrato' - 'linha')::text);
    v_res := pg_temp.ok(v_res, format('V2b (ficha às %s) às 17:00 o "como foi" sai e leva a ficha de sex 06/11 (a 2ª do dia); na hora da ficha, nada novo (nenhuma linha de ficha, nem no tique seguinte); no dia, 2 proativas e 1 resposta na fila; a pergunta dos dias segue adiada', v_h),
      n ->> 'como_foi' = 'enfileirada leva 2026-11-06' and (n ->> 'adiada_1700')::int = 1
      and n ->> 'ficha_antes_da_hora' = '-' and n -> 'ficha_no_tique' = '{}'::jsonb and n -> 'ficha_no_tique_seguinte' = '{}'::jsonb and n ->> 'ficha' = '-'
      and (n ->> 'fila_na_hora')::int = 2 and (n ->> 'previstas_na_hora')::int = 0 and (n ->> 'adiada_na_hora')::int = 1 and n ->> 'dias' = '-'
      and (n ->> 'proativas')::int = 2 and (n ->> 'respostas')::int = 1 and (n ->> 'saude')::int = 0
      and n ->> 'linha' = '07:45 confirmar enfileirada; 09:00 resposta enfileirada; 17:00 como_foi enfileirada (leva a ficha de 06/11)',
      format('%s | proativas %s, respostas %s', n ->> 'linha', n ->> 'proativas', n ->> 'respostas'));
    v_res := pg_temp.ok(v_res, format('V2c (ficha às %s) é o comportamento de antes, IGUAL: com o corpo de antes (md5 7e86318b…), as mesmas mensagens (texto, hora, estado, chave), a mesma fila, as mesmas contas e os mesmos tiques, byte a byte', v_h),
      a ->> 'md5_do_corpo' = c_antes and (n - 'md5_do_corpo') = (a - 'md5_do_corpo') and jsonb_array_length(n #> '{retrato,mensagens}') = 3,
      case when (n - 'md5_do_corpo') = (a - 'md5_do_corpo') then format('%s mensagens iguais', jsonb_array_length(n #> '{retrato,mensagens}'))
           else format('novo %s ≠ antes %s', (n - 'retrato')::text, (a - 'retrato')::text) end);
  end loop;

  -- ── V3. Ele respondeu "ok" de manhã (com 'manter'; com 'tirar' o dia também fica) ──
  foreach v_m in array array['manter', 'tirar'] loop
    n := pg_temp.roda('novo', v_m, '19:30', 'ok');
    a := pg_temp.roda('antes', v_m, '19:30', 'ok');
    v_prox := v_prox || jsonb_build_object(format('V3 %s', v_m), n -> 'proativas');
    v_res := pg_temp.ok(v_res, format('V3 (chave %s) ele respondeu "ok" às 08:10: a confirmação respondida, nenhum silêncio; 16:45 a conta dá 1 e a pergunta dos dias é adiada; 17:00 o "como foi" leva a ficha de sex 06/11; na hora da ficha, nada; 2 proativas no dia. Igual ao corpo de antes, byte a byte', v_m),
      n ->> 'confirmar_0745' = 'enfileirada' and n ->> 'confirmar_0900' = 'respondida' and (n ->> 'silencio_0900')::int = 0 and n ->> 'segundo_pedido' = '-'
      and (n ->> 'hoje_vivo')::int = 2 and (n ->> 'fila_1645')::int = 1 and (n ->> 'previstas_1645')::int = 1
      and (n ->> 'adiada_1645')::int = 1 and (n ->> 'dias_1645')::int = 0
      and n ->> 'como_foi' = 'enfileirada leva 2026-11-06' and n ->> 'ficha' = '-' and n -> 'ficha_no_tique' = '{}'::jsonb and n ->> 'dias' = '-'
      and (n ->> 'proativas')::int = 2 and (n ->> 'erros')::int = 0
      and n ->> 'linha' = '07:45 confirmar respondida; 17:00 como_foi enfileirada (leva a ficha de 06/11)'
      and a ->> 'md5_do_corpo' = c_antes and (n - 'md5_do_corpo') = (a - 'md5_do_corpo'),
      format('%s | previstas %s | igual ao de antes: %s', n ->> 'linha', n ->> 'previstas_1645', (n - 'md5_do_corpo') = (a - 'md5_do_corpo')));
  end loop;

  -- ── V4. Sem plano hoje e com plano amanhã ──
  n := pg_temp.roda('novo', 'manter', '19:30', 'sem_plano_hoje');
  a := pg_temp.roda('antes', 'manter', '19:30', 'sem_plano_hoje');
  v_prox := v_prox || jsonb_build_object('V4', n -> 'proativas');
  v_res := pg_temp.ok(v_res, 'V4 sem plano hoje e com plano amanhã: nenhuma confirmação e nenhum "como foi"; 16:45 a conta dá 1 (a ficha) com a fila vazia: 0 + 1 < 2, a pergunta dos dias SAI como a 1ª; na hora da ficha ela é enfileirada como a 2ª; 2 proativas no dia. Igual ao corpo de antes, byte a byte',
    n ->> 'confirmar_0745' = '-' and (n ->> 'silencio_0900')::int = 0 and (n ->> 'hoje_vivo')::int = 0 and (n ->> 'amanha_vivo')::int = 1
    and (n ->> 'fila_1645')::int = 0 and (n ->> 'previstas_1645')::int = 1
    and (n ->> 'adiada_1645')::int = 0 and (n ->> 'saiu_1645')::int = 1 and n ->> 'dias' = 'enfileirada 05/11 16:45'
    and n ->> 'como_foi' = '-' and (n ->> 'fila_na_hora')::int = 1 and n -> 'ficha_no_tique' = '{"enfileirada": 1}'::jsonb
    and n ->> 'ficha' = 'enfileirada na fila às 19:30' and (n ->> 'proativas')::int = 2 and (n ->> 'saude')::int = 0 and (n ->> 'erros')::int = 0
    and n ->> 'linha' = '16:45 dias enfileirada; 19:30 ficha enfileirada'
    and a ->> 'md5_do_corpo' = c_antes and (n - 'md5_do_corpo') = (a - 'md5_do_corpo'),
    format('%s | previstas %s | igual ao de antes: %s', n ->> 'linha', n ->> 'previstas_1645', (n - 'md5_do_corpo') = (a - 'md5_do_corpo')));

  -- ── V4b. A confirmação não sai (ele já confirmou o dia na véspera), com plano hoje e amanhã: sem confirmação, a ficha conta como antes ──
  n := pg_temp.roda('novo', 'manter', '19:30', 'ja_confirmou');
  a := pg_temp.roda('antes', 'manter', '19:30', 'ja_confirmou');
  v_prox := v_prox || jsonb_build_object('V4b', n -> 'proativas');
  v_res := pg_temp.ok(v_res, 'V4b a confirmação das 07:45 não sai (ele já confirmou o dia na véspera, com o "ok" à ficha), com plano hoje e amanhã: 16:45 a conta dá 2 (o "como foi" e a ficha, cada um com a sua vaga: sem a confirmação o "como foi" não leva a ficha) e a pergunta dos dias é adiada; 17:00 o "como foi" vai sem a ficha (a 1ª); na hora da ficha ela vai sozinha (a 2ª); 2 proativas. Igual ao corpo de antes, byte a byte',
    n ->> 'confirmar_0745' = '-' and (n ->> 'silencio_0900')::int = 0 and (n ->> 'hoje_vivo')::int = 2 and (n ->> 'amanha_vivo')::int = 1
    and (n ->> 'fila_1645')::int = 0 and (n ->> 'previstas_1645')::int = 2
    and (n ->> 'adiada_1645')::int = 1 and (n ->> 'saiu_1645')::int = 0 and (n ->> 'dias_1645')::int = 0
    and n ->> 'como_foi' = 'enfileirada sem a ficha' and (n ->> 'fila_na_hora')::int = 1 and (n ->> 'previstas_na_hora')::int = 1
    and n -> 'ficha_no_tique' = '{"enfileirada": 1}'::jsonb and n ->> 'ficha' = 'enfileirada na fila às 19:30' and n ->> 'dias' = '-'
    and (n ->> 'proativas')::int = 2 and (n ->> 'saude')::int = 0 and (n ->> 'erros')::int = 0
    and n ->> 'linha' = '17:00 como_foi enfileirada; 19:30 ficha enfileirada'
    and a ->> 'md5_do_corpo' = c_antes and (n - 'md5_do_corpo') = (a - 'md5_do_corpo'),
    format('%s | previstas %s | igual ao de antes: %s', n ->> 'linha', n ->> 'previstas_1645', (n - 'md5_do_corpo') = (a - 'md5_do_corpo')));

  -- ── V4c. A confirmação nasce recusada (veto), com plano hoje e amanhã: recusada não é "saiu" ──
  n := pg_temp.roda('novo', 'manter', '19:30', 'confirmacao_vetada');
  a := pg_temp.roda('antes', 'manter', '19:30', 'confirmacao_vetada');
  v_prox := v_prox || jsonb_build_object('V4c', n -> 'proativas');
  v_res := pg_temp.ok(v_res, 'V4c a confirmação das 07:45 nasce RECUSADA por veto (a ficha de hoje segurada) e não vai à fila, com plano hoje e amanhã: recusada não é "saiu" — 16:45 a conta dá 2 (o "como foi" e a ficha) e a pergunta dos dias é adiada; 17:00 o "como foi" vai sem a ficha (a 1ª); na hora da ficha ela vai sozinha (a 2ª); 2 proativas. Igual ao corpo de antes, byte a byte',
    n ->> 'confirmar_0745' = 'recusada' and (n ->> 'silencio_0900')::int = 0 and (n ->> 'hoje_vivo')::int = 2 and (n ->> 'amanha_vivo')::int = 1
    and (n ->> 'fila_1645')::int = 0 and (n ->> 'previstas_1645')::int = 2
    and (n ->> 'adiada_1645')::int = 1 and (n ->> 'saiu_1645')::int = 0 and (n ->> 'dias_1645')::int = 0
    and n ->> 'como_foi' = 'enfileirada sem a ficha' and (n ->> 'fila_na_hora')::int = 1 and (n ->> 'previstas_na_hora')::int = 1
    and n -> 'ficha_no_tique' = '{"enfileirada": 1}'::jsonb and n ->> 'ficha' = 'enfileirada na fila às 19:30' and n ->> 'dias' = '-'
    and (n ->> 'proativas')::int = 2 and (n ->> 'saude')::int = 0 and (n ->> 'erros')::int = 0
    and n ->> 'linha' = '07:45 confirmar recusada/veto; 17:00 como_foi enfileirada; 19:30 ficha enfileirada'
    and a ->> 'md5_do_corpo' = c_antes and (n - 'md5_do_corpo') = (a - 'md5_do_corpo'),
    format('%s | previstas %s | igual ao de antes: %s', n ->> 'linha', n ->> 'previstas_1645', (n - 'md5_do_corpo') = (a - 'md5_do_corpo')));

  -- ── V5. 'manter' e o dia sai do plano depois da confirmação ──
  foreach v_m in array array['nao_vou', 'dono_tira'] loop
    n := pg_temp.roda('novo', 'manter', '19:30', v_m);
    a := pg_temp.roda('antes', 'manter', '19:30', v_m);
    v_prox := v_prox || jsonb_build_object(format('V5 %s', v_m), n -> 'proativas');
    v_res := pg_temp.ok(v_res, format('V5%s ''manter'' e o dia sai do plano depois da confirmação das 07:45 (%s): às 16:45 ele não tem plano vivo hoje e tem amanhã; a conta dá 1, a pergunta dos dias é ADIADA (nenhuma linha ''dias''); não há "como foi"; na hora da ficha ela vai sozinha, enfileirada como a 2ª do dia; 2 proativas',
                                      case when v_m = 'nao_vou' then 'a' else 'b' end,
                                      case when v_m = 'nao_vou' then 'ele responde "hoje não vou" às 08:10' else 'o dono tira o dia dele às 08:10' end),
      n ->> 'confirmar_0745' = 'enfileirada' and (n ->> 'silencio_0900')::int = 0 and n ->> 'segundo_pedido' = '-'
      and n ->> 'confirmar_0900' = case when v_m = 'nao_vou' then 'respondida' else 'enfileirada' end
      and (n ->> 'hoje_vivo')::int = 0 and (n ->> 'amanha_vivo')::int = 1 and (n ->> 'fila_1645')::int = 1 and (n ->> 'previstas_1645')::int = 1
      and (n ->> 'adiada_1645')::int = 1 and (n ->> 'saiu_1645')::int = 0 and (n ->> 'dias_1645')::int = 0 and n ->> 'como_foi' = '-'
      and n ->> 'ficha_antes_da_hora' = '-' and (n ->> 'fila_na_hora')::int = 1 and n -> 'ficha_no_tique' = '{"enfileirada": 1}'::jsonb
      and n ->> 'ficha' = 'enfileirada na fila às 19:30' and n ->> 'dias' = '-' and (n ->> 'proativas')::int = 2 and (n ->> 'saude')::int = 0
      and (n ->> 'erros')::int = 0,
      format('%s | previstas %s | proativas %s, respostas %s', n ->> 'linha', n ->> 'previstas_1645', n ->> 'proativas', n ->> 'respostas'));
    v_res := pg_temp.ok(v_res, format('V5c (%s) o CONTROLE com o corpo de antes: a conta dá 0, a pergunta dos dias sai às 16:45 como a 2ª e a ficha de sex 06/11 nasce recusada por teto (com ''manter'' o furo continuava aberto nesta rota)',
                                      case when v_m = 'nao_vou' then '"hoje não vou"' else 'o dono tira o dia' end),
      a ->> 'md5_do_corpo' = c_antes and (a ->> 'hoje_vivo')::int = 0 and (a ->> 'amanha_vivo')::int = 1 and (a ->> 'fila_1645')::int = 1
      and (a ->> 'previstas_1645')::int = 0 and (a ->> 'saiu_1645')::int = 1 and a ->> 'dias' = 'enfileirada 05/11 16:45'
      and a -> 'ficha_no_tique' = '{"recusada": 1}'::jsonb and a ->> 'ficha' = 'recusada/teto às 19:30' and (a ->> 'proativas')::int = 2
      and (a ->> 'saude')::int = 1,
      format('%s | previstas %s | saúde %s', a ->> 'linha', a ->> 'previstas_1645', a ->> 'saude'));
  end loop;

  -- ── V6. A confirmação saiu e o "como foi" de hoje já foi registrado SEM a ficha (ela espera o "mande" do dono) ──
  begin
    perform pg_temp.tique(d05, '07:45');
    perform pg_temp.saiu(d05, '07:46');
    perform pg_temp.resp('ok', d05, '08:10');
    -- a pergunta da ficha pela estimativa aberta, sem o "mande": o "como foi" das 17:00 vai sem a ficha (a regra de _agenda_rotina_como_foi)
    insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, payee_id, dia, perda_em, texto, opcoes, recomendacao, opcao_padrao, modo,
                                         criada_em, expira_em, veto_ate)
    values ('ficha_estimativa', format('ficha_estimativa:%s:%s', c_roberto, d06), c_lenine, array[c_lenine], c_roberto, d06, d05,
            'Hoje às 19:30 a ficha de amanhã vai para Roberto: Lenine, sex 06/11 de manhã, pela minha estimativa. 1) Mande (recomendo); 2) Segure a ficha: eu não mando e você fala com ele.',
            '[{"n": 1, "texto": "Mande", "efeito": {"mandar": true}}, {"n": 2, "texto": "Segure a ficha: eu não mando e você fala com ele", "efeito": {"segurar": true}}]'::jsonb,
            1, 1, 'ligado', pg_temp.em(d05, '16:50'), pg_temp.em(d06, '19:30'), pg_temp.em(d05, '19:30'));
    v_i := public._agenda_equipe_previstas_hoje(c_roberto, d05, pg_temp.em(d05, '16:55'));
    t := pg_temp.tique(d05, '17:00');
    perform pg_temp.saiu(d05, '17:01');
    v_j := public._agenda_equipe_previstas_hoje(c_roberto, d05, pg_temp.em(d05, '17:05'));
    x := jsonb_build_object(
      'como_foi', (select m.estado || case when m.leva_ficha_de is null then ' sem a ficha' else ' leva ' || m.leva_ficha_de end
                     from public.agenda_equipe_mensagens m where m.payee_id = c_roberto and m.tipo = 'como_foi' and m.dia = d05),
      'confirmar', (pg_temp.msg(c_roberto, 'confirmar', d05)).estado, 'hoje_vivo', pg_temp.vivo(c_roberto, d05), 'amanha_vivo', pg_temp.vivo(c_roberto, d06),
      'ficha', coalesce((pg_temp.msg(c_roberto, 'ficha', d06)).estado, '-'), 'fila', public._agenda_equipe_no_dia(c_roberto, d05, false, null),
      'erros', t ->> 'erros');
    begin
      v_txt := pg_temp.corpo_de_antes();
      v_k := public._agenda_equipe_previstas_hoje(c_roberto, d05, pg_temp.em(d05, '17:05'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    v_res := pg_temp.ok(v_res, 'V6 a confirmação saiu, ele ainda tem plano hoje e o "como foi" das 17:00 foi registrado SEM a ficha (a pergunta da ficha pela estimativa aberta, sem o "mande"): a ficha de amanhã volta a guardar a vaga dela — a conta dá 1 às 17:05 (com o corpo de antes dava 0); às 16:55, antes do "como foi", dava 1 (o "como foi" por nascer)',
      x ->> 'confirmar' = 'respondida' and (x ->> 'hoje_vivo')::int = 2 and (x ->> 'amanha_vivo')::int = 1 and x ->> 'como_foi' = 'enfileirada sem a ficha'
      and x ->> 'ficha' = '-' and (x ->> 'erros')::int = 0
      and v_i = 1 and v_j = 1 and v_k = 0 and v_txt = c_antes and md5(pg_temp.src(c_p)) <> c_antes,
      format('16:55 %s | 17:05 novo %s, antes %s | %s', v_i, v_j, v_k, x::text));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── V7. A pergunta adiada sai noutro dia: quinta (o V1), sexta com 2 mensagens, sábado ──
  begin
    x := pg_temp.quinta('tirar', '19:30', 'calado');
    v_res := pg_temp.ok(v_res, 'V7a na quinta (o V1: ''tirar'', calado, ficha às 19:30) a pergunta dos dias ficou adiada o dia todo e a ficha de sex 06/11 saiu',
      (x ->> 'adiada_1645')::int = 1 and (x ->> 'adiada_na_hora')::int = 1 and x ->> 'dias' = '-' and x ->> 'ficha' = 'enfileirada na fila às 19:30',
      x ->> 'linha');
    v_prox := v_prox || jsonb_build_object('V7 quinta', x -> 'proativas');
    -- a sexta: a confirmação das 07:45, o "ok" dele às 08:10, o "como foi" das 17:00 com a ficha de seg 09/11
    t := pg_temp.tique(d06, '07:45');
    perform pg_temp.saiu(d06, '07:46');
    perform pg_temp.resp('ok', d06, '08:10');
    t := pg_temp.tique(d06, '09:00');
    v_i := public._agenda_equipe_no_dia(c_roberto, d06, false, null);
    v_j := public._agenda_equipe_previstas_hoje(c_roberto, d06, pg_temp.em(d06, '16:45'));
    t := pg_temp.tique(d06, '16:45');
    x := jsonb_build_object('sex_fila_1645', v_i, 'sex_previstas_1645', v_j, 'sex_hoje_vivo', pg_temp.vivo(c_roberto, d06), 'seg_vivo', pg_temp.vivo(c_roberto, d09),
                            'sex_adiada_1645', coalesce((t #>> '{semana,contagens,perguntar,adiada}')::int, 0),
                            'sex_saiu_1645', coalesce((t #>> '{semana,contagens,perguntar,enfileirada}')::int, 0), 'sex_erros', (t ->> 'erros')::int);
    t := pg_temp.tique(d06, '17:00');
    perform pg_temp.saiu(d06, '17:01');
    x := x || jsonb_build_object('sex_adiada_1700', coalesce((t #>> '{semana,contagens,perguntar,adiada}')::int, 0));
    t := pg_temp.tique(d06, '19:30');
    perform pg_temp.saiu(d06, '19:31');
    x := x || jsonb_build_object(
      'sex_como_foi', coalesce((select m.estado || case when m.leva_ficha_de is null then ' sem a ficha' else ' leva ' || m.leva_ficha_de end
                                  from public.agenda_equipe_mensagens m where m.payee_id = c_roberto and m.tipo = 'como_foi' and m.dia = d06), '-'),
      'sex_adiada_1930', coalesce((t #>> '{semana,contagens,perguntar,adiada}')::int, 0),
      'sex_proativas', public._agenda_equipe_no_dia(c_roberto, d06, false, null),
      'sex_dias', (select count(*) from public.agenda_equipe_mensagens m where m.payee_id = c_roberto and m.tipo = 'dias'));
    v_res := pg_temp.ok(v_res, 'V7b na sexta, com 2 mensagens (a confirmação das 07:45 e o "como foi" das 17:00 levando a ficha de seg 09/11), a pergunta dos dias é adiada de novo: às 16:45 há 1 na fila e 1 prevista; nenhuma linha ''dias''',
      (x ->> 'sex_fila_1645')::int = 1 and (x ->> 'sex_previstas_1645')::int = 1 and (x ->> 'sex_hoje_vivo')::int >= 1 and (x ->> 'seg_vivo')::int >= 1
      and (x ->> 'sex_adiada_1645')::int = 1 and (x ->> 'sex_saiu_1645')::int = 0 and (x ->> 'sex_adiada_1700')::int = 1 and (x ->> 'sex_adiada_1930')::int = 1
      and x ->> 'sex_como_foi' = 'enfileirada leva 2026-11-09' and (x ->> 'sex_proativas')::int = 2 and (x ->> 'sex_dias')::int = 0
      and (x ->> 'sex_erros')::int = 0,
      x::text || ' | ' || pg_temp.linha(c_roberto, d06));
    v_prox := v_prox || jsonb_build_object('V7 sexta', x -> 'sex_proativas');
    -- o sábado: sem plano, sem rotina; a pergunta dos dias sai às 16:45, sozinha
    t := pg_temp.tique(d07, '07:45');
    t := pg_temp.tique(d07, '16:30');
    v_i := (select count(*) from public.agenda_equipe_mensagens m where m.payee_id = c_roberto and m.tipo = 'dias');
    v_j := public._agenda_equipe_previstas_hoje(c_roberto, d07, pg_temp.em(d07, '16:45'));
    t := pg_temp.tique(d07, '16:45');
    perform pg_temp.saiu(d07, '16:46');
    x := jsonb_build_object('sab_dias_1630', v_i, 'sab_previstas', v_j, 'sab_saiu_1645', coalesce((t #>> '{semana,contagens,perguntar,enfileirada}')::int, 0),
                            'sab_adiada_1645', coalesce((t #>> '{semana,contagens,perguntar,adiada}')::int, 0), 'sab_erros', (t ->> 'erros')::int);
    t := pg_temp.tique(d07, '17:00');
    x := x || jsonb_build_object(
      'dias', (select string_agg(format('%s semana de %s, enviar %s', m.estado, to_char(m.dia, 'DD/MM'), to_char(m.enviar_em at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI')), ' ; ')
                 from public.agenda_equipe_mensagens m where m.payee_id = c_roberto and m.tipo = 'dias'),
      'n_dias', (select count(*) from public.agenda_equipe_mensagens m where m.payee_id = c_roberto and m.tipo = 'dias'),
      'sab_proativas', public._agenda_equipe_no_dia(c_roberto, d07, false, null),
      'sab_na_fila', (select count(*) from public.whatsapp_send_queue q join public.agenda_equipe_mensagens m on m.id = q.source_ref_id
                       where m.payee_id = c_roberto and m.tipo = 'dias'));
    v_res := pg_temp.ok(v_res, 'V7c no sábado 07/11 (sem plano e sem rotina) a pergunta adiada SAI às 16:45, sozinha: antes das 16:45 nada; 1 linha ''dias'' na semana (a de seg 16/11), enfileirada e na fila; 1 proativa no dia; o tique seguinte não cria outra',
      (x ->> 'sab_dias_1630')::int = 0 and (x ->> 'sab_previstas')::int = 0 and (x ->> 'sab_saiu_1645')::int = 1 and (x ->> 'sab_adiada_1645')::int = 0
      and x ->> 'dias' = 'enfileirada semana de 16/11, enviar 07/11 16:45' and (x ->> 'n_dias')::int = 1 and (x ->> 'sab_na_fila')::int = 1
      and (x ->> 'sab_proativas')::int = 1 and (x ->> 'sab_erros')::int = 0,
      x::text);
    v_prox := v_prox || jsonb_build_object('V7 sábado', x -> 'sab_proativas');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── V8. O teto nunca é passado ──
  v_res := pg_temp.ok(v_res, 'V8 o teto nunca é passado: em todos os cenários acima com o corpo novo (V1 a V5 e V7), as proativas na fila do dia ficam em no máximo equipe_proativas_dia_max (2); a conta só decide quem espera',
    (select count(*) = 14 and bool_and((e.value)::int <= v_teto) and bool_and((e.value)::int >= 1) from jsonb_each_text(v_prox) e),
    format('teto %s | %s', v_teto, v_prox::text));

  raise exception 'desfaz' using errcode = 'P0096';
  exception when sqlstate 'P0096' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$v$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
