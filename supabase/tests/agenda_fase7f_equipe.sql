-- Prova da equipe da Agenda de Produção, Fase 7f (pacote P5): a semana prevista na quinta junto da ficha, a mudança nos dias que a pessoa já ouviu (uma por pessoa às
-- 19:30, ou na hora quando o dia já teve ficha), o convite com SIM para o dia novo em cima da hora, e a resposta a cada um (migration 20261109101000; spec-fase7f §3.2,
-- §5.5, §6.3, §6.4, §8.3 agenda_fase7f_equipe.sql e R8.5-16 a 19, R8.6, R8.7, R8.8, R8.11, R8.12, R8.13).
-- bancada: depende de 20261109101000
--
--   E0   sempre: 1 assinatura do registro (R8.5-16); os 4 passos com o nome que a rodada chama; as portas; quem chama o registro
--   E1   o previsto: junto da ficha da quinta; sozinho; a ficha recusada e a que foi no "como foi" (E1b); a reserva fora; João sem telefone; o Alex; não se recria
--   E2   _agenda_dias_avisados e a mudança das 19:30 (uma por pessoa; junto da ficha; o dia novo a menos de 72 h fica para o convite)
--   E3   a mudança na hora do dia que teve ficha; o acorde "Já avisei o Roberto." pelos 2 caminhos, com o estado depois; o "não vou" que a chama
--   E4   o convite (< 72 h, uma por pessoa e dia, prazo na ficha da véspera); o Alex declarado nunca; o prazo passado = exceção; a ficha não sai sem SIM (E4b)
--   E5   SIM, NÃO, vencido (o caminho do não vou, sem_sim, o acorde), o SIM acima do teto de respostas (E5b), o SIM tardio, o que não se entende
--   E6   a resposta ao previsto e à mudança: ok = ciência; "não posso quarta" = ao dono, sem remanejar; a ficha que levou a semana
--   E7   a janela, o domingo e o teto de 2 (o previsto conta no dia; nunca a 3ª)
--   E8   o freio e a sombra: com gestor_so_propor e os 2 modos ligados nada vai à fila; em teste só registra (":sombra"); desligado, o de antes
--   E9   as cópias só mudam nos blocos; a migration cria e recria só o que diz
--   E10  o texto: sem valor, sem número de OS, sem nome de outro cliente; a varredura confere o tamanho e reprova um texto plantado
--   E11  os cantos: cada guarda das funções novas com o caso que a reprova (o registro, o previsto sozinho, o que ele ouviu, a mudança na hora, o convite, a ficha longa)
--   E12  mais cantos: o previsto guarda o que ele já ouviu fora da semana que vem; a ficha não repete a mudança que já saiu; o "como foi" longo; o SIM depois do prazo;
--        "sexta não vou" à ficha da sexta; "mudou" sem outro dia; o dia antigo e o dia com ficha não viram convite; o dono nunca é convidado
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Fora dela, só o E0 roda; o resto sai PULADO: usa a fixture da 7f, que nunca roda em produção.
--
-- A fixture é a da 7f (fixture-fase7f.sql, R8.12-8): Roberto (com telefone, não declarado: o diarista do convite), João (sem telefone) e o Alex (prestador, declarado
-- pelo dono, sem telefone, todo dia útil: como em produção). O Roberto e o João saíram da rotina na fixture da 7c; aqui voltam (pg_temp.prepara).
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
create function pg_temp.na_bancada() returns boolean language sql stable as $f$
  select coalesce(current_setting('agenda_teste.fase7f', true), '') <> ''
     and coalesce(current_setting('agenda_teste.mig_equipe_fase7f', true), '') <> ''
$f$;
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
create function pg_temp.p(p_nome text) returns uuid language sql stable as $f$
  select id from public.payees where name = p_nome and active order by created_at, id limit 1
$f$;
create function pg_temp.fone(p_nome text) returns text language sql stable as $f$
  select case when length(x) in (10, 11) then '55' || x else x end
    from (select regexp_replace(coalesce(phone, ''), '\D', '', 'g') as x from public.payees where id = pg_temp.p(p_nome)) y
$f$;
create function pg_temp.os(p_n text) returns uuid language sql immutable as $f$ select ('f7f00000-0000-4000-8000-000000097' || p_n)::uuid $f$;
create function pg_temp.aloc(p_n text, p_quem text, p_dia text, p_turno text) returns uuid language sql immutable as $f$
  select md5('f7f:aloc:' || p_n || ':' || p_quem || ':' || p_dia || ':' || p_turno)::uuid
$f$;
-- O cenário: a fixture da 7f, a equipe e a agenda automática ligadas, os 2 modos da equipe e o freio como o caso pede; o Roberto e o João de volta à rotina (o João sem
-- telefone); nada de etapas (modo_tarefas, para a ficha ser a de sempre) nem acesso.
create function pg_temp.prepara(p_prev text, p_conv text, p_freio boolean) returns void language plpgsql as $f$
begin
  execute current_setting('agenda_teste.fase7f');
  update public.agenda_config
     set modo_equipe = 'ligado', modo_proposta = 'ligado', modo_vigia = 'ligado', modo_tarefas = 'desligado',
         modo_equipe_previsto = p_prev, modo_equipe_convite = p_conv, gestor_so_propor = p_freio
   where id;
  update public.agenda_equipe_contato set recebe_rotina = true, parou_em = null, parou_motivo = null where payee_id = pg_temp.p('Roberto');
  insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por) values (pg_temp.p('João'), true, 'dono')
  on conflict (payee_id) do update set recebe_rotina = true, parou_em = null, parou_motivo = null;
end $f$;
-- A fila mandou (o worker): as linhas agenda-equipe pendentes até a hora dada saem.
create function pg_temp.saiu(p_quando timestamptz) returns void language sql as $f$
  update public.whatsapp_send_queue set status = 'sent', sent_at = p_quando, attempts = attempts + 1
   where source = 'agenda-equipe' and status = 'pending' and scheduled_for <= p_quando;
$f$;
-- Um tique: a rotina da equipe e a rodada comunicar (a ordem do task-automations: a rotina antes, a comunicar depois da vigia e do cliente).
create function pg_temp.tique(p_agora timestamptz) returns jsonb language plpgsql as $f$
declare
  v_dia date := (p_agora at time zone 'America/Sao_Paulo')::date;
  a jsonb;
  b jsonb;
begin
  a := public.agenda_rotina_rodar(v_dia, p_agora);
  b := public.agenda_comunicar_rodar(v_dia, p_agora);
  return jsonb_build_object('rotina', a, 'comunicar', b);
end $f$;
create function pg_temp.msg(p_payee uuid, p_tipo text, p_dia date) returns public.agenda_equipe_mensagens language sql stable as $f$
  select * from public.agenda_equipe_mensagens where payee_id = p_payee and tipo = p_tipo and dia = p_dia order by criada_em desc, id desc limit 1
$f$;
-- Quantas mensagens que o sistema começa a pessoa tem na fila nesse dia (o teto de 2).
create function pg_temp.na_fila(p_payee uuid, p_dia date) returns int language sql stable as $f$
  select public._agenda_equipe_no_dia(p_payee, p_dia, false, null)
$f$;
-- Nenhuma mensagem da 7f foi à fila (a fila só tem as de antes).
create function pg_temp.fila_7f() returns int language sql stable as $f$
  select count(*)::int from public.whatsapp_send_queue q join public.agenda_equipe_mensagens m on m.id = q.source_ref_id
   where q.source = 'agenda-equipe' and (m.tipo in ('previsto', 'mudanca', 'convite') or m.dias is not null)
$f$;
-- A varredura do texto à equipe (§6.4, R8.12-4): não é vazio; sem valor; sem número de OS; sem o nome de cliente de OS em que a pessoa não esteve.
create function pg_temp.limpo(p_texto text, p_payee uuid) returns boolean language sql stable as $f$
  select coalesce(length(btrim(p_texto)) > 0, false)
     and p_texto !~ 'R\$' and p_texto !~ '\m[0-9]+,[0-9]{2}\M' and p_texto !~* '\mOS-' and p_texto !~ '\m(OS|O\.S\.)\s*[0-9]'
     and not exists (select 1 from public.service_orders so join public.clients cl on cl.id = so.client_id
                      where so.service_order_number like 'OS-F%'
                        and not exists (select 1 from public.agenda_alocacoes a where a.service_order_id = so.id and a.payee_id = p_payee)
                        and p_texto ~ ('\m' || public._agenda_nome_curto(cl.name) || '\M'))
$f$;
create function pg_temp.desfaz() returns void language plpgsql as $f$
begin
  raise exception using errcode = 'P0001', message = '__desfaz__';
end $f$;

-- A fixture entra uma vez, na transação de fora: cada caso mexe nela dentro de uma subtransação desfeita (pg_temp.prepara não a carrega de novo: ela confere).
do $e$
begin
  if pg_temp.na_bancada() then
    execute current_setting('agenda_teste.fase7f');
  end if;
end
$e$;

-- ── E0. Sempre ──────────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'E0a uma assinatura só do registro, a de 10 argumentos (p_dias, p_alocacoes e p_chave com default null); a de 7 saiu (R8.5-16: duas dariam 42725)',
       count(*) = 1
       and bool_and(pg_get_function_identity_arguments(p.oid) = 'p_payee uuid, p_dia date, p_tipo text, p_texto text, p_enviar_em timestamp with time zone, p_leva_ficha_de date, p_responde text, p_dias date[], p_alocacoes uuid[], p_chave text'
                    and pg_get_function_arguments(p.oid) like '%p_dias date[] DEFAULT NULL::date[], p_alocacoes uuid[] DEFAULT NULL::uuid[], p_chave text DEFAULT NULL::text')
       and to_regprocedure('public._agenda_equipe_registrar(uuid, date, text, text, timestamptz, date, text)') is null,
       string_agg(pg_get_function_identity_arguments(p.oid), ' | ')
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = '_agenda_equipe_registrar';
insert into _resultado
select 'E0b os 4 passos da equipe existem com o nome e a assinatura que a rodada comunicar procura (to_regprocedure, date e timestamptz)',
       bool_and(to_regprocedure(format('public.%I(date, timestamp with time zone)', '_agenda_comunicar_' || x)) is not null),
       string_agg(x || '=' || (to_regprocedure(format('public.%I(date, timestamp with time zone)', '_agenda_comunicar_' || x)) is not null)::text, ', ')
  from unnest(array['previsto', 'mudancas_equipe', 'convites', 'convites_vencidos']) x;
with f(sig, quem) as (values
  ('public._agenda_dias_avisados(uuid, date, date, text)', '-'),
  ('public._agenda_dias_do_plano_da_pessoa(uuid, date, date, date)', 's'),
  ('public._agenda_equipe_convite_prazo(date)', '-'),
  ('public._agenda_equipe_ja_avisei(uuid, date, uuid)', 'as'),
  ('public._agenda_equipe_semana_da_pessoa(uuid, date, timestamptz, text)', '-'),
  ('public._agenda_equipe_previsto_sozinho(uuid, date)', 's'),
  ('public._agenda_equipe_mudanca_na_hora(uuid, date, timestamptz)', '-'),
  ('public._agenda_comunicar_previsto(date, timestamptz)', '-'),
  ('public._agenda_comunicar_mudancas_equipe(date, timestamptz)', '-'),
  ('public._agenda_comunicar_convites(date, timestamptz)', '-'),
  ('public._agenda_comunicar_convites_vencidos(date, timestamptz)', '-'),
  ('public._agenda_equipe_registrar(uuid, date, text, text, timestamptz, date, text, date[], uuid[], text)', '-'),
  ('public._agenda_rotina_sem_resposta(date, timestamptz)', '-'),
  ('public._agenda_rotina_ficha(date, timestamptz)', '-'),
  ('public._agenda_rotina_como_foi(date, timestamptz)', '-'),
  ('public._agenda_rotina_acordes_da_equipe(date, timestamptz)', '-'),
  ('public._agenda_equipe_previstas_hoje(uuid, date, timestamptz)', 's'),
  ('public.agenda_resposta_da_equipe(text, text, text, timestamptz)', 's'),
  ('public._agenda_texto_do_acorde(uuid, date, date)', 'as'))
insert into _resultado
select 'E0c as portas: anon e PUBLIC nunca; authenticated só onde o chamador invoker tem; service_role só onde diz; as novas são invoker com search_path fixo',
       count(*) = 19
       and bool_and(not has_function_privilege('anon', f.sig::regprocedure, 'execute')
                    and has_function_privilege('authenticated', f.sig::regprocedure, 'execute') = (f.quem like '%a%')
                    and has_function_privilege('service_role', f.sig::regprocedure, 'execute') = (f.quem like '%s%')
                    and not coalesce((select bool_or(a.grantee = 0) from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                                       where a.privilege_type = 'EXECUTE'), false)
                    and p.proconfig @> array['search_path=public'])
       and bool_and(not p.prosecdef or p.proname in ('agenda_resposta_da_equipe', '_agenda_equipe_registrar')),  -- as 2 definer de antes
       string_agg(format('%s a=%s s=%s d=%s', p.proname, has_function_privilege('authenticated', f.sig::regprocedure, 'execute'),
                         has_function_privilege('service_role', f.sig::regprocedure, 'execute'), p.prosecdef), '; ')
  from f join pg_proc p on p.oid = to_regprocedure(f.sig);
-- quem chama o registro (o grep no banco): cada um é exercitado abaixo (E1, E2, E3, E5, E6), pelos testes de antes na bancada inteira, e o eval da 3ª mensagem
insert into _resultado
select 'E0d quem chama o registro é a lista conhecida (as 6 de antes e as 4 novas); toda chamada é de 5 a 10 argumentos com nome (nenhuma "não é única")',
       string_agg(p.proname, ',' order by p.proname)
       = '_agenda_comunicar_convites,_agenda_comunicar_mudancas_equipe,_agenda_comunicar_previsto,_agenda_equipe_mudanca_na_hora,_agenda_local_avisar_acesso,_agenda_rotina_como_foi,_agenda_rotina_confirmar,_agenda_rotina_ficha,agenda_equipe_semana,agenda_resposta_da_equipe',
       string_agg(p.proname, ',' order by p.proname)
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace and p.prosrc ~ 'public\._agenda_equipe_registrar\(' and p.proname <> '_agenda_equipe_registrar';
insert into _resultado
select 'E0e a chamada de 5 argumentos (a dos chamadores de antes e do eval) resolve na função nova: com a equipe desligada, {criada: false}, nada grava',
       (select (public._agenda_equipe_registrar(pg_temp.p('Gustavo'), current_date, 'ficha', 'teste', now()) ->> 'criada') is not null
          from public.agenda_config c where c.id and c.modo_equipe = 'desligado')
       is distinct from false, null;

-- ── E1. O previsto ──────────────────────────────────────────────────────────────────────────────────
do $e$
declare
  r      jsonb := '[]';
  c_qui  constant date := date '2026-11-12';
  c_sex  constant date := date '2026-11-13';
  c_seg  constant date := date '2026-11-16';
  v_rob  uuid;
  v_ficha text;
  v_t    jsonb;
  m      public.agenda_equipe_mensagens;
  v_n    int;
begin
  if not pg_temp.na_bancada() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'E1 o previsto', true, 'PULADO: sem agenda_teste.fase7f (rode pela bancada)'));
    return;
  end if;
  v_rob := pg_temp.p('Roberto');
  -- E1a: junto da ficha da quinta
  begin
    perform pg_temp.prepara('ligado', 'desligado', false);
    perform set_config('agenda.hoje', c_qui::text, true);
    v_ficha := public.agenda_equipe_ficha(v_rob, c_sex, c_qui) ->> 'texto_ficha';
    v_t := pg_temp.tique(pg_temp.em(c_qui, '19:30'));
    m := pg_temp.msg(v_rob, 'ficha', c_sex);
    r := pg_temp.ok(r, 'E1a na quinta, a ficha das 19:30 leva o previsto: "<ficha> Semana que vem (previsto, pode mudar): qua 18 e qui 19/11." e grava os dias',
      m.texto = v_ficha || ' Semana que vem (previsto, pode mudar): qua 18 e qui 19/11.' and m.dias = array[date '2026-11-18', date '2026-11-19']
      and m.estado = 'enfileirada' and m.modo = 'ligado'
      and (select q.message from public.whatsapp_send_queue q where q.id = m.fila_id) = m.texto, m.texto || ' | ' || coalesce(m.dias::text, '-'));
    r := pg_temp.ok(r, 'E1a2 o passo previsto não manda outro (tem a ficha); 2 mensagens na fila do dia (o "como foi" e a ficha com o previsto), nunca 3',
      v_t #>> '{comunicar,contagens,previsto,por_estado,tem_ficha}' = '1'
      and not exists (select 1 from public.agenda_equipe_mensagens x where x.payee_id = v_rob and x.tipo = 'previsto' and x.dia = c_seg)
      and pg_temp.na_fila(v_rob, c_qui) = 2, (v_t #> '{comunicar,contagens,previsto}')::text || ' fila ' || pg_temp.na_fila(v_rob, c_qui));
    r := pg_temp.ok(r, 'E1a3 o que ele ouviu depois: qua 18 e qui 19/11 (o ter 17 do previsto de 05/11 foi trocado: o previsto vale a semana inteira)',
      public._agenda_dias_avisados(v_rob, date '2026-11-14', date '2026-11-22') = array[date '2026-11-18', date '2026-11-19'],
      public._agenda_dias_avisados(v_rob, date '2026-11-14', date '2026-11-22')::text);
    -- não se recria: o tique seguinte não faz nada novo
    v_n := (select count(*) from public.agenda_equipe_mensagens where payee_id = v_rob);
    v_t := pg_temp.tique(pg_temp.em(c_qui, '19:45'));
    r := pg_temp.ok(r, 'E1f o tique seguinte não recria a ficha nem o previsto',
      (select count(*) from public.agenda_equipe_mensagens where payee_id = v_rob) = v_n, null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  -- E1g: sozinho (sem plano amanhã); a reserva fica fora; João sem telefone; o Alex (sem telefone)
  begin
    perform pg_temp.prepara('ligado', 'desligado', false);
    perform set_config('agenda.hoje', c_qui::text, true);
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_em = pg_temp.em(c_qui, '10:00'), cancelada_motivo = 'cliente'
     where payee_id = v_rob and dia = c_sex and estado in ('publicada', 'fixada');
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, reserva_de, estado, origem, publicada_em, duracao_fonte, criado_em)
    values (md5('f7f:p5:reserva:rob')::uuid, pg_temp.os('306'), v_rob, date '2026-11-20', 'manha', 'turno', 'reserva', 'teto', 'publicada', 'motor',
            pg_temp.em(c_qui, '16:30'), 'orcamento', pg_temp.em(c_qui, '16:30'));
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, duracao_fonte, criado_em)
    values (md5('f7f:p5:joao:17')::uuid, pg_temp.os('301'), pg_temp.p('João'), date '2026-11-17', 'manha', 'turno', 'execucao', 'publicada', 'motor',
            pg_temp.em(c_qui, '16:30'), 'orcamento', pg_temp.em(c_qui, '16:30'));
    v_t := pg_temp.tique(pg_temp.em(c_qui, '19:30'));
    m := pg_temp.msg(v_rob, 'previsto', c_seg);
    r := pg_temp.ok(r, 'E1g sem a ficha de amanhã, o previsto sai sozinho, com o texto da §6.4, a chave da semana e os dias',
      m.texto = 'Roberto, semana que vem (previsto, pode mudar): qua 18 e qui 19/11. Se algum desses dias não der, me fala.'
      and m.dias = array[date '2026-11-18', date '2026-11-19'] and m.estado = 'enfileirada'
      and m.dedupe_key = format('agenda-equipe:previsto:%s:%s', v_rob, c_seg), coalesce(m.texto, '-') || ' | ' || coalesce(m.dedupe_key, '-'));
    r := pg_temp.ok(r, 'E1c a reserva da sex 20/11 não entra (a reserva não avisa a equipe: Fase 2)',
      not (date '2026-11-20' = any (m.dias)) and m.texto not like '%20/11%', m.dias::text);
    r := pg_temp.ok(r, 'E1d o João, na rotina e com dia na semana que vem, sem telefone: não recebe nada (contado como sem_telefone)',
      not exists (select 1 from public.agenda_equipe_mensagens x where x.payee_id = pg_temp.p('João') and x.tipo in ('previsto', 'mudanca', 'convite'))
      and (v_t #>> '{comunicar,contagens,previsto,por_estado,sem_telefone}')::int >= 2, (v_t #> '{comunicar,contagens,previsto}')::text);
    r := pg_temp.ok(r, 'E1e o Alex (prestador, declarado, sem telefone, todo dia útil): nenhuma mensagem da 7f',
      not exists (select 1 from public.agenda_equipe_mensagens x where x.payee_id = pg_temp.p('Alex') and x.tipo in ('previsto', 'mudanca', 'convite')), null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  -- E1b: a ficha recusada (o teto já cheio) e a ficha que foi no "como foi"
  begin
    perform pg_temp.prepara('ligado', 'desligado', false);
    perform set_config('agenda.hoje', c_qui::text, true);
    perform public._agenda_equipe_registrar(v_rob, date '2026-12-01', 'ficha', 'Roberto, teste do teto 1.', pg_temp.em(c_qui, '10:00'));
    perform public._agenda_equipe_registrar(v_rob, date '2026-12-02', 'ficha', 'Roberto, teste do teto 2.', pg_temp.em(c_qui, '10:05'));
    v_t := pg_temp.tique(pg_temp.em(c_qui, '19:30'));
    m := pg_temp.msg(v_rob, 'ficha', c_sex);
    r := pg_temp.ok(r, 'E1b a ficha com o previsto recusada pelo teto não conta como "tem ficha": o passo tenta o previsto sozinho, e o teto o recusa também — nunca a 3ª',
      m.estado = 'recusada' and m.recusa_motivo = 'teto' and m.dias is not null
      and (pg_temp.msg(v_rob, 'previsto', c_seg)).estado = 'recusada' and (pg_temp.msg(v_rob, 'previsto', c_seg)).recusa_motivo = 'teto'
      and pg_temp.na_fila(v_rob, c_qui) = 2, coalesce(m.estado, '-') || '/' || coalesce((pg_temp.msg(v_rob, 'previsto', c_seg)).estado, '-') || ' fila ' || pg_temp.na_fila(v_rob, c_qui));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.prepara('ligado', 'desligado', false);
    perform set_config('agenda.hoje', c_qui::text, true);
    -- a confirmação da manhã (o Roberto tem o Lenine hoje) e o "como foi" das 17:00, que leva a ficha de amanhã
    v_t := pg_temp.tique(pg_temp.em(c_qui, '07:45'));
    perform pg_temp.saiu(pg_temp.em(c_qui, '07:46'));
    v_t := pg_temp.tique(pg_temp.em(c_qui, '17:00'));
    m := pg_temp.msg(v_rob, 'como_foi', c_qui);
    r := pg_temp.ok(r, 'E1b2 a ficha que vai no "como foi" das 17:00 leva o previsto (uma mensagem só) e grava os dias',
      m.leva_ficha_de = c_sex and m.texto like '% Semana que vem (previsto, pode mudar): qua 18 e qui 19/11.' and m.dias = array[date '2026-11-18', date '2026-11-19']
      and m.estado = 'enfileirada', coalesce(m.texto, '-'));
    perform pg_temp.saiu(pg_temp.em(c_qui, '17:01'));
    v_t := pg_temp.tique(pg_temp.em(c_qui, '19:30'));
    r := pg_temp.ok(r, 'E1b3 às 19:30, nem ficha nem previsto a mais: "tem ficha" é também a do "como foi" (R8.5-17); 2 na fila do dia (a confirmação e o "como foi")',
      v_t #>> '{comunicar,contagens,previsto,por_estado,tem_ficha}' = '1'
      and not exists (select 1 from public.agenda_equipe_mensagens x where x.payee_id = v_rob and ((x.tipo = 'ficha' and x.dia = c_sex) or (x.tipo = 'previsto' and x.dia = c_seg)))
      and pg_temp.na_fila(v_rob, c_qui) = 2, (v_t #> '{comunicar,contagens,previsto}')::text || ' fila ' || pg_temp.na_fila(v_rob, c_qui));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$e$;

-- ── E2. O que ele ouviu e a mudança das 19:30 ───────────────────────────────────────────────────────
do $e$
declare
  r      jsonb := '[]';
  c_qua  constant date := date '2026-11-11';
  c_qui  constant date := date '2026-11-12';
  v_rob  uuid;
  v_ficha text;
  v_t    jsonb;
  m      public.agenda_equipe_mensagens;
  v_n    int;
begin
  if not pg_temp.na_bancada() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'E2 a mudança', true, 'PULADO: sem agenda_teste.fase7f (rode pela bancada)'));
    return;
  end if;
  v_rob := pg_temp.p('Roberto');
  begin
    perform pg_temp.prepara('ligado', 'desligado', false);
    perform set_config('agenda.hoje', c_qua::text, true);
    r := pg_temp.ok(r, 'E2a o que ele ouviu: o previsto de qui 05/11 (ter 17 e qua 18)',
      public._agenda_dias_avisados(v_rob, date '2026-11-13', date '2026-11-22') = array[date '2026-11-17', date '2026-11-18'], null);
    v_ficha := public.agenda_equipe_ficha(v_rob, c_qui, c_qua) ->> 'texto_ficha';
    v_t := pg_temp.tique(pg_temp.em(c_qua, '19:30'));
    m := pg_temp.msg(v_rob, 'ficha', c_qui);
    r := pg_temp.ok(r, 'E2b a mudança vai junto da ficha das 19:30: "<ficha> Na semana: sai ter 17/11; entra qui 19/11." (a sex 13/11, nova a menos de 72 h, é o convite: não entra)',
      m.texto = v_ficha || ' Na semana: sai ter 17/11; entra qui 19/11.' and m.dias = array[date '2026-11-18', date '2026-11-19'] and m.estado = 'enfileirada',
      coalesce(m.texto, '-') || ' | ' || coalesce(m.dias::text, '-'));
    r := pg_temp.ok(r, 'E2c junto da ficha, nenhuma mudança a mais; o que ele ouviu passa a ser qua 18 e qui 19/11 (a última substitui)',
      not exists (select 1 from public.agenda_equipe_mensagens x where x.payee_id = v_rob and x.tipo = 'mudanca')
      and public._agenda_dias_avisados(v_rob, date '2026-11-13', date '2026-11-22') = array[date '2026-11-18', date '2026-11-19'],
      (v_t #> '{comunicar,contagens,mudancas_equipe}')::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- sem a ficha de amanhã: a mudança sai sozinha, uma por pessoa
    perform pg_temp.prepara('ligado', 'desligado', false);
    perform set_config('agenda.hoje', c_qua::text, true);
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_em = pg_temp.em(c_qua, '10:00'), cancelada_motivo = 'cliente'
     where payee_id = v_rob and dia = c_qui and estado in ('publicada', 'fixada');
    v_t := pg_temp.tique(pg_temp.em(c_qua, '19:30'));
    m := pg_temp.msg(v_rob, 'mudanca', c_qua);
    r := pg_temp.ok(r, 'E2d sem a ficha de amanhã, a mudança sai sozinha às 19:30: o texto da §6.4, a chave das 19:30 do dia, os dias que ficam',
      m.texto = 'Roberto, mudou a sua semana: sai ter 17/11; entra qui 19/11. Fica: qua 18 e qui 19/11.'
      and m.dedupe_key = format('agenda-equipe:mudanca:%s:%s:19h', v_rob, c_qua) and m.dias = array[date '2026-11-18', date '2026-11-19']
      and m.alocacao_ids is null and m.estado = 'enfileirada', coalesce(m.texto, '-') || ' | ' || coalesce(m.dedupe_key, '-'));
    perform pg_temp.saiu(pg_temp.em(c_qua, '19:31'));
    v_n := (select count(*) from public.agenda_equipe_mensagens where payee_id = v_rob and tipo = 'mudanca');
    v_t := pg_temp.tique(pg_temp.em(c_qua, '19:45'));
    r := pg_temp.ok(r, 'E2e uma por pessoa: o tique seguinte não manda outra (nem há diferença: ele já ouviu)',
      (select count(*) from public.agenda_equipe_mensagens where payee_id = v_rob and tipo = 'mudanca') = v_n and v_n = 1, v_n::text);
    r := pg_temp.ok(r, 'E2f quem não ouviu nada da semana (o Rafael) não ganha mudança, mesmo com dia novo no plano',
      not exists (select 1 from public.agenda_equipe_mensagens x where x.payee_id = pg_temp.p('Rafael') and x.tipo = 'mudanca'), null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$e$;

-- ── E3. A mudança na hora e o acorde ────────────────────────────────────────────────────────────────
-- O Roberto recebeu a ficha de qua 11/11 (o Flávio) na ter 10/11 às 19:30; às 19:40 o dono tira o Roberto desse dia (a ação do dono). O Flávio fica com sex 20/11.
create function pg_temp.e3_cenario(p_origem text default 'dono') returns uuid language plpgsql as $f$
declare
  v_rob uuid := pg_temp.p('Roberto');
  v_a   uuid := md5('f7f:p5:acao:' || p_origem)::uuid;
begin
  perform set_config('agenda.hoje', '2026-11-10', true);
  insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, dedupe_key)
  values (v_rob, date '2026-11-11', 'ficha', 'ligado', 'Roberto, amanhã (qua 11/11): 8h na lancha do Flávio. Responde OK se tá certo.', pg_temp.em(date '2026-11-10', '19:30'),
          'enfileirada', format('agenda-equipe:ficha:%s:2026-11-11', v_rob));
  insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, duracao_fonte, criado_em)
  values (md5('f7f:p5:flavio:20')::uuid, pg_temp.os('304'), pg_temp.p('Alex'), date '2026-11-20', 'tarde', 'turno', 'execucao', 'publicada', 'dono',
          pg_temp.em(date '2026-11-10', '19:40'), 'dono', pg_temp.em(date '2026-11-10', '19:40'));
  update public.agenda_alocacoes set estado = 'cancelada', cancelada_em = pg_temp.em(date '2026-11-10', '19:40'), cancelada_motivo = 'cliente'
   where id in (pg_temp.aloc('304', 'roberto', '2026-11-11', 'manha'), pg_temp.aloc('304', 'roberto', '2026-11-11', 'tarde'));
  insert into public.agenda_acoes (id, criada_em, dia, executada, origem, tipo, service_order_id, os_ids, alocacoes_criadas, alocacoes_canceladas, payee_id, texto,
                                   desfazivel_ate)
  values (v_a, pg_temp.em(date '2026-11-10', '19:40'), date '2026-11-10', true, p_origem, 'mover', pg_temp.os('304'), array[pg_temp.os('304')],
          array[md5('f7f:p5:flavio:20')::uuid],
          array[pg_temp.aloc('304', 'roberto', '2026-11-11', 'manha'), pg_temp.aloc('304', 'roberto', '2026-11-11', 'tarde')], v_rob,
          'Passei Flávio de qua 11/11 para sex 20/11 com Alex.', pg_temp.em(date '2026-11-11', '19:40'));
  return v_a;
end $f$;
do $e$
declare
  r      jsonb := '[]';
  c_ter  constant date := date '2026-11-10';
  c_qua  constant date := date '2026-11-11';
  v_rob  uuid;
  v_a    uuid;
  v_t    jsonb;
  v_txt  text;
  v_antes text;
  m      public.agenda_equipe_mensagens;
  v_eq   uuid;
begin
  if not pg_temp.na_bancada() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'E3 a mudança na hora', true, 'PULADO: sem agenda_teste.fase7f (rode pela bancada)'));
    return;
  end if;
  v_rob := pg_temp.p('Roberto');
  begin
    perform pg_temp.prepara('ligado', 'desligado', false);
    v_a := pg_temp.e3_cenario();
    v_antes := public._agenda_texto_do_acorde(v_a, c_qua, c_ter);
    r := pg_temp.ok(r, 'E3a o controle: antes da mensagem de mudança, o acorde manda o dono avisar (o texto de antes)',
      v_antes like '% O Roberto já recebeu a ficha de amanhã com o Flávio: avise ele da mudança.' and v_antes not like '%Já avisei%', v_antes);
    v_t := public._agenda_comunicar_mudancas_equipe(c_ter, pg_temp.em(c_ter, '19:45'));
    m := pg_temp.msg(v_rob, 'mudanca', c_qua);
    r := pg_temp.ok(r, 'E3b a decisão do dono tirou o Roberto de amanhã, que já teve ficha: a mensagem na hora, com o texto da §6.4, a chave da ação e as alocações que saíram',
      m.texto = 'Roberto, amanhã (qua 11/11) não precisa vir: o serviço do Flávio mudou de dia. Desculpa o aviso em cima.'
      and m.dedupe_key = format('agenda-equipe:mudanca:%s:2026-11-11:%s', v_rob, v_a) and m.dias = '{}'::date[]
      and m.alocacao_ids = array(select x from unnest(array[pg_temp.aloc('304', 'roberto', '2026-11-11', 'manha'), pg_temp.aloc('304', 'roberto', '2026-11-11', 'tarde')]) x order by x)
      and m.estado = 'enfileirada' and exists (select 1 from public.whatsapp_send_queue q where q.id = m.fila_id and q.dedupe_key = m.dedupe_key),
      coalesce(m.texto, '-') || ' | ' || v_t::text);
    -- caminho 1 do acorde: o texto que a vigia escreve (_agenda_texto_do_acorde)
    v_txt := public._agenda_texto_do_acorde(v_a, c_qua, c_ter);
    r := pg_temp.ok(r, 'E3c com a mensagem na fila, o acorde diz " Já avisei o Roberto." no lugar do "avise ele" (o estado depois: _agenda_equipe_ja_avisei e a fila)',
      v_txt like '% Já avisei o Roberto.' and v_txt not like '%avise ele%' and public._agenda_equipe_ja_avisei(v_rob, c_qua, v_a), v_txt);
    -- caminho 2: a rotina da equipe (o acorde da falta de outra pessoa, cujo replano é esta ação)
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
    values (pg_temp.em(c_ter, '19:39'), c_ter, true, 'equipe', 'equipe', pg_temp.os('304'), array[pg_temp.os('304')], pg_temp.p('Rafael'),
            jsonb_build_object('motivo', 'nao_vou', 'dia', c_qua, 'replano_acoes', jsonb_build_array(v_a), 'acorde', true),
            'O Rafael avisou que não vem amanhã (qua 11/11).')
    returning id into v_eq;
    v_t := public._agenda_rotina_acordes_da_equipe(c_ter, pg_temp.em(c_ter, '19:50'));
    r := pg_temp.ok(r, 'E3d pela rotina da equipe (o 2º caminho do acorde), o mesmo " Já avisei o Roberto."',
      v_t -> 'acordes' -> 0 ->> 'texto' like 'O Rafael avisou que não vem amanhã (qua 11/11). Mudei a agenda de amanhã: %' and v_t -> 'acordes' -> 0 ->> 'texto' like '% Já avisei o Roberto.',
      v_t::text);
    -- a mudança na fila mas recusada (o teto) não é "avisei"
    update public.agenda_equipe_mensagens set estado = 'recusada', recusa_motivo = 'teto' where id = m.id;
    v_txt := public._agenda_texto_do_acorde(v_a, c_qua, c_ter);
    r := pg_temp.ok(r, 'E3e a mensagem de mudança recusada (o teto) não é "Já avisei": o acorde volta a mandar o dono avisar',
      v_txt like '%: avise ele da mudança.' and v_txt not like '%Já avisei%' and not public._agenda_equipe_ja_avisei(v_rob, c_qua, v_a), v_txt);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- só o dia que já teve ficha; quem faltou não recebe; fora da janela, espera
    perform pg_temp.prepara('ligado', 'desligado', false);
    v_a := pg_temp.e3_cenario();
    v_t := public._agenda_equipe_mudanca_na_hora(v_a, c_ter, pg_temp.em(c_ter, '20:05'));
    r := pg_temp.ok(r, 'E3f fora da janela (20:05), nada: espera o próximo tique dentro dela',
      v_t ->> 'motivo' = 'janela' and not exists (select 1 from public.agenda_equipe_mensagens x where x.payee_id = v_rob and x.tipo = 'mudanca'), v_t::text);
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, criado_em)
    values (v_rob, daterange(c_qua, c_qua, '[]'), 'indisponivel', 'diarista', 'teste: ele avisou', pg_temp.em(c_ter, '19:41'));
    v_t := public._agenda_equipe_mudanca_na_hora(v_a, c_ter, pg_temp.em(c_ter, '19:45'));
    r := pg_temp.ok(r, 'E3g quem faltou (indisponível no dia) não recebe a mudança: ele sabe',
      not exists (select 1 from public.agenda_equipe_mensagens x where x.payee_id = v_rob and x.tipo = 'mudanca'), v_t::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.prepara('ligado', 'desligado', false);
    perform set_config('agenda.hoje', c_ter::text, true);
    -- o dono tira o Roberto da qua 18/11, que não teve ficha: nada na hora (fica para a mudança das 19:30)
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_em = pg_temp.em(c_ter, '15:00'), cancelada_motivo = 'cliente'
     where id in (pg_temp.aloc('301', 'roberto', '2026-11-18', 'manha'), pg_temp.aloc('301', 'roberto', '2026-11-18', 'tarde'));
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, alocacoes_canceladas, payee_id, texto)
    values (pg_temp.em(c_ter, '15:00'), c_ter, true, 'dono', 'cancelar', pg_temp.os('301'), array[pg_temp.os('301')],
            array[pg_temp.aloc('301', 'roberto', '2026-11-18', 'manha'), pg_temp.aloc('301', 'roberto', '2026-11-18', 'tarde')], v_rob,
            'Tirei o Roberto de qua 18/11 no Nelson.');
    v_t := public._agenda_comunicar_mudancas_equipe(c_ter, pg_temp.em(c_ter, '15:15'));
    r := pg_temp.ok(r, 'E3h na hora, só o dia que já teve ficha ou confirmação: a qua 18/11 (sem ficha) não ganha mensagem na hora',
      not exists (select 1 from public.agenda_equipe_mensagens x where x.payee_id = v_rob and x.tipo = 'mudanca') and v_t -> 'na_hora' = '{}'::jsonb, v_t::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- o "não vou" de outra pessoa: depois do replano, quem já tinha a ficha fica sabendo na hora (o replano é um dublê que devolve a ação do dono)
    perform pg_temp.prepara('ligado', 'desligado', false);
    v_a := pg_temp.e3_cenario();
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, duracao_fonte, criado_em)
    values (md5('f7f:p5:rafael:11')::uuid, pg_temp.os('303'), pg_temp.p('Rafael'), c_qua, 'manha', 'turno', 'execucao', 'publicada', 'motor',
            pg_temp.em(c_ter, '10:00'), 'dono', pg_temp.em(c_ter, '10:00'));
    insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, dedupe_key)
    values (pg_temp.p('Rafael'), c_qua, 'ficha', 'ligado', 'Rafael, amanhã (qua 11/11): 8h no motorhome do Vanderlei. Responde OK se tá certo.',
            pg_temp.em(c_ter, '19:30'), 'enfileirada', format('agenda-equipe:ficha:%s:2026-11-11', pg_temp.p('Rafael')));
    execute format($d$create or replace function public.agenda_replanejar(p_os uuid[], p_motivo text default null, p_origem text default %L, p_hoje date default public._hoje_brt(), p_agora timestamptz default now(), p_autor uuid default null)
                      returns jsonb language sql as $q$ select jsonb_build_object('acoes', jsonb_build_array(%L::text), 'texto', 'teste do replano.') $q$$d$, 'vigia', v_a);
    v_t := public.agenda_resposta_da_equipe(pg_temp.fone('Rafael'), 'amanhã não vou', 'wa-e3i', pg_temp.em(c_ter, '19:42'));
    m := pg_temp.msg(v_rob, 'mudanca', c_qua);
    r := pg_temp.ok(r, 'E3i o "não vou" do Rafael: depois do replano, a mudança na hora do Roberto (que já tinha a ficha) nasce ali mesmo, antes do acorde',
      v_t ->> 'tipo' = 'nao_vou' and m.estado = 'enfileirada' and m.dedupe_key = format('agenda-equipe:mudanca:%s:2026-11-11:%s', v_rob, v_a)
      and public._agenda_equipe_ja_avisei(v_rob, c_qua, v_a), v_t::text || ' | ' || coalesce(m.texto, '-'));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$e$;

-- ── E4. O convite ───────────────────────────────────────────────────────────────────────────────────
-- O Roberto tem sex 13/11 com o Lenine, criada qua 11/11 10:00 (46 h antes das 8h do dia): dia novo a menos de 72 h. O prazo do SIM: qui 12/11 às 19:30.
do $e$
declare
  r      jsonb := '[]';
  c_qua  constant date := date '2026-11-11';
  c_qui  constant date := date '2026-11-12';
  c_sex  constant date := date '2026-11-13';
  v_rob  uuid;
  v_alex uuid;
  v_raf  uuid;
  v_t    jsonb;
  m      public.agenda_equipe_mensagens;
  v_n    int;
begin
  if not pg_temp.na_bancada() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'E4 o convite', true, 'PULADO: sem agenda_teste.fase7f (rode pela bancada)'));
    return;
  end if;
  v_rob := pg_temp.p('Roberto');
  v_alex := pg_temp.p('Alex');
  v_raf := pg_temp.p('Rafael');
  begin
    perform pg_temp.prepara('desligado', 'ligado', false);
    perform set_config('agenda.hoje', c_qua::text, true);
    r := pg_temp.ok(r, 'E4a0 o prazo do SIM é a ficha da véspera: qui 12/11 às 19:30',
      public._agenda_equipe_convite_prazo(c_sex) = pg_temp.em(c_qui, '19:30'), public._agenda_equipe_convite_prazo(c_sex)::text);
    v_t := public._agenda_comunicar_convites(c_qua, pg_temp.em(c_qua, '10:15'));
    m := pg_temp.msg(v_rob, 'convite', c_sex);
    r := pg_temp.ok(r, 'E4a o convite: o texto da §6.4 com o prazo, a chave do dia, os dias e as alocações que o SIM confirma',
      m.texto = 'Roberto, apareceu serviço para sex 13/11: 8h no motorhome do Lenine. Pode vir? Responde SIM ou NÃO até qui 12/11 às 19:30.'
      and m.dedupe_key = format('agenda-equipe:convite:%s:2026-11-13', v_rob) and m.dias = array[c_sex]
      and m.alocacao_ids = array(select x from unnest(array[pg_temp.aloc('302', 'roberto', '2026-11-13', 'manha'), pg_temp.aloc('302', 'roberto', '2026-11-13', 'tarde')]) x order by x)
      and m.estado = 'enfileirada', coalesce(m.texto, '-') || ' | ' || v_t::text);
    v_n := (select count(*) from public.agenda_equipe_mensagens where tipo = 'convite');
    v_t := public._agenda_comunicar_convites(c_qua, pg_temp.em(c_qua, '10:30'));
    r := pg_temp.ok(r, 'E4a2 um por pessoa e dia: o tique seguinte não convida de novo',
      (select count(*) from public.agenda_equipe_mensagens where tipo = 'convite') = v_n, v_t::text);
    -- a ficha não sai sem o SIM; com o SIM, sai
    perform pg_temp.saiu(pg_temp.em(c_qua, '10:16'));
    v_t := pg_temp.tique(pg_temp.em(c_qui, '19:30'));
    r := pg_temp.ok(r, 'E4b a ficha de sex 13/11 não sai a quem tem o convite sem o SIM ("só vira dia dele com o sim")',
      not exists (select 1 from public.agenda_equipe_mensagens x where x.payee_id = v_rob and x.tipo = 'ficha' and x.dia = c_sex), (v_t #> '{rotina,contagens,ficha}')::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.prepara('desligado', 'ligado', false);
    perform set_config('agenda.hoje', c_qua::text, true);
    v_t := public._agenda_comunicar_convites(c_qua, pg_temp.em(c_qua, '10:15'));
    perform pg_temp.saiu(pg_temp.em(c_qua, '10:16'));
    v_t := public.agenda_resposta_da_equipe(pg_temp.fone('Roberto'), 'sim', 'wa-e4c', pg_temp.em(c_qua, '11:00'));
    v_t := pg_temp.tique(pg_temp.em(c_qui, '19:30'));
    r := pg_temp.ok(r, 'E4c com o SIM, a ficha de sex 13/11 sai (o controle do E4b)',
      exists (select 1 from public.agenda_equipe_mensagens x where x.payee_id = v_rob and x.tipo = 'ficha' and x.dia = c_sex and x.estado = 'enfileirada'), null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- o Alex, declarado pelo dono, com telefone de teste e um dia novo em cima da hora: nunca convidado; sem o padrão do dono, seria (o controle)
    perform pg_temp.prepara('desligado', 'ligado', false);
    perform set_config('agenda.hoje', c_qua::text, true);
    update public.payees set phone = '47900000777' where id = v_alex;
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, duracao_fonte, criado_em)
    values (md5('f7f:p5:alex:13')::uuid, pg_temp.os('305'), v_alex, c_sex, 'manha', 'turno', 'execucao', 'publicada', 'motor', pg_temp.em(c_qua, '10:00'), 'orcamento',
            pg_temp.em(c_qua, '10:00'));
    v_t := public._agenda_comunicar_convites(c_qua, pg_temp.em(c_qua, '10:15'));
    r := pg_temp.ok(r, 'E4d o Alex (prestador declarado pelo dono, todo dia útil) nunca é convidado: _agenda_tecnico_declarado cobre',
      public._agenda_tecnico_declarado(v_alex, c_sex) and not exists (select 1 from public.agenda_equipe_mensagens x where x.payee_id = v_alex and x.tipo = 'convite'),
      v_t::text);
    update public.payees set created_at = timestamptz '2026-11-01 10:00-03' where id = v_alex;  -- o cadastro de ontem: o padrão do dono é de novato, e ele deixa de ser o técnico declarado
    v_t := public._agenda_comunicar_convites(c_qua, pg_temp.em(c_qua, '10:30'));
    r := pg_temp.ok(r, 'E4d2 o controle: com o cadastro recente (o padrão do dono vira de novato), o Alex deixa de ser declarado e seria convidado',
      not public._agenda_tecnico_declarado(v_alex, c_sex) and exists (select 1 from public.agenda_equipe_mensagens x where x.payee_id = v_alex and x.tipo = 'convite'),
      v_t::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- o prazo já passado: o Rafael marcado para qui 12/11 depois das 19:30 de quarta não é convidado (nasceria vencido); a exceção vai ao dono, uma vez
    perform pg_temp.prepara('desligado', 'ligado', false);
    perform set_config('agenda.hoje', c_qui::text, true);
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, duracao_fonte, criado_em)
    values (md5('f7f:p5:rafael:12')::uuid, pg_temp.os('305'), v_raf, c_qui, 'tarde', 'turno', 'execucao', 'publicada', 'motor', pg_temp.em(c_qua, '21:00'), 'orcamento',
            pg_temp.em(c_qua, '21:00'));
    v_t := public._agenda_comunicar_convites(c_qui, pg_temp.em(c_qui, '07:45'));
    v_t := public._agenda_comunicar_convites(c_qui, pg_temp.em(c_qui, '08:00'));
    r := pg_temp.ok(r, 'E4e prazo passado: nenhum convite; a ação equipe convite_sem_prazo, com acorde, uma vez (2 tiques)',
      not exists (select 1 from public.agenda_equipe_mensagens x where x.payee_id = v_raf and x.tipo = 'convite')
      and (select count(*) from public.agenda_acoes a where a.tipo = 'equipe' and a.payee_id = v_raf and a.depois ->> 'motivo' = 'convite_sem_prazo'
              and (a.depois ->> 'acorde')::boolean and a.executada) = 1, v_t::text);
    v_t := public._agenda_rotina_acordes_da_equipe(c_qui, pg_temp.em(c_qui, '08:15'));
    r := pg_temp.ok(r, 'E4e2 o acorde da exceção é a frase da ação (não "avisou que não vem"), e diz por onde sair: falar com ele',
      v_t -> 'acordes' -> 0 ->> 'texto' = 'O Rafael foi marcado para qui 12/11 em cima da hora, e já passou a hora de pedir o SIM dele (qua 11/11 às 19:30): fale com ele.',
      v_t::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- a troca no mesmo dia não é dia novo; o João sem telefone não é convidado
    perform pg_temp.prepara('desligado', 'ligado', false);
    perform set_config('agenda.hoje', c_qua::text, true);
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, duracao_fonte, criado_em,
                                         cancelada_em, cancelada_motivo)
    values (md5('f7f:p5:rafael:13:velha')::uuid, pg_temp.os('306'), v_raf, c_sex, 'manha', 'turno', 'execucao', 'cancelada', 'motor', pg_temp.em(date '2026-11-01', '10:00'),
            'orcamento', pg_temp.em(date '2026-11-01', '10:00'), pg_temp.em(c_qua, '10:00'), 'cliente');
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, duracao_fonte, criado_em)
    values (md5('f7f:p5:rafael:13:nova')::uuid, pg_temp.os('305'), v_raf, c_sex, 'manha', 'turno', 'execucao', 'publicada', 'motor', pg_temp.em(c_qua, '10:00'), 'orcamento',
            pg_temp.em(c_qua, '10:00')),
           (md5('f7f:p5:joao:13')::uuid, pg_temp.os('305'), pg_temp.p('João'), c_sex, 'tarde', 'turno', 'execucao', 'publicada', 'motor', pg_temp.em(c_qua, '10:00'),
            'orcamento', pg_temp.em(c_qua, '10:00'));
    v_t := public._agenda_comunicar_convites(c_qua, pg_temp.em(c_qua, '10:15'));
    r := pg_temp.ok(r, 'E4f a troca dentro do mesmo dia (a alocação de antes saiu quando a nova entrou) não é dia novo: o Rafael não é convidado; o João, sem telefone, também não',
      not exists (select 1 from public.agenda_equipe_mensagens x where x.payee_id in (v_raf, pg_temp.p('João')) and x.tipo = 'convite')
      and exists (select 1 from public.agenda_equipe_mensagens x where x.payee_id = v_rob and x.tipo = 'convite'), v_t::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$e$;

-- ── E5. A resposta ao convite ───────────────────────────────────────────────────────────────────────
do $e$
declare
  r      jsonb := '[]';
  c_qua  constant date := date '2026-11-11';
  c_qui  constant date := date '2026-11-12';
  c_sex  constant date := date '2026-11-13';
  v_rob  uuid;
  v_t    jsonb;
  m      public.agenda_equipe_mensagens;
  i      int;
begin
  if not pg_temp.na_bancada() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'E5 a resposta ao convite', true, 'PULADO: sem agenda_teste.fase7f (rode pela bancada)'));
    return;
  end if;
  v_rob := pg_temp.p('Roberto');
  begin
    perform pg_temp.prepara('desligado', 'ligado', false);
    perform set_config('agenda.hoje', c_qua::text, true);
    perform public._agenda_comunicar_convites(c_qua, pg_temp.em(c_qua, '10:15'));
    perform pg_temp.saiu(pg_temp.em(c_qua, '10:16'));
    v_t := public.agenda_resposta_da_equipe(pg_temp.fone('Roberto'), 'SIM', 'wa-e5a', pg_temp.em(c_qua, '11:00'));
    m := pg_temp.msg(v_rob, 'convite', c_sex);
    r := pg_temp.ok(r, 'E5a o SIM confirma: a disponibilidade confirmada no dia, o convite respondido (convite: sim) e "Combinado, até sex 13/11." na fila',
      v_t ->> 'leitura' = 'sim' and v_t ->> 'resposta' = 'Combinado, até sex 13/11.' and m.estado = 'respondida' and m.leitura ->> 'convite' = 'sim'
      and exists (select 1 from public.agenda_disponibilidade d where d.payee_id = v_rob and d.situacao = 'confirmada' and d.periodo @> c_sex and d.substituida_em is null)
      and exists (select 1 from public.agenda_equipe_mensagens x where x.payee_id = v_rob and x.tipo = 'resposta' and x.texto = 'Combinado, até sex 13/11.'
                    and x.estado = 'enfileirada'), v_t::text);
    r := pg_temp.ok(r, 'E5a2 o que ele ouviu ganha a sex 13/11 (o convite com SIM conta pela hora do SIM)',
      c_sex = any (public._agenda_dias_avisados(v_rob, c_qua, date '2026-11-22')), public._agenda_dias_avisados(v_rob, c_qua, date '2026-11-22')::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- o SIM acima do teto de 4 respostas do dia: a resposta é recusada, o SIM vale (grava antes)
    perform pg_temp.prepara('desligado', 'ligado', false);
    perform set_config('agenda.hoje', c_qua::text, true);
    perform public._agenda_comunicar_convites(c_qua, pg_temp.em(c_qua, '10:15'));
    perform pg_temp.saiu(pg_temp.em(c_qua, '10:16'));
    for i in 1 .. 4 loop
      perform public._agenda_equipe_registrar(v_rob, c_qua, 'resposta', 'Tá bom ' || i, pg_temp.em(c_qua, '10:2' || i), null, 'wa-teto-' || i);
    end loop;
    v_t := public.agenda_resposta_da_equipe(pg_temp.fone('Roberto'), 'sim', 'wa-e5b', pg_temp.em(c_qua, '11:00'));
    m := pg_temp.msg(v_rob, 'convite', c_sex);
    r := pg_temp.ok(r, 'E5b acima do teto de 4 respostas: "Combinado…" é recusada pelo teto, e o SIM continua valendo (a disponibilidade e o convite respondido)',
      v_t ->> 'envio' = 'recusada' and v_t ->> 'resposta' is null and m.estado = 'respondida' and m.leitura ->> 'convite' = 'sim'
      and exists (select 1 from public.agenda_disponibilidade d where d.payee_id = v_rob and d.situacao = 'confirmada' and d.periodo @> c_sex and d.substituida_em is null)
      and (select x.recusa_motivo from public.agenda_equipe_mensagens x where x.payee_id = v_rob and x.tipo = 'resposta' and x.texto = 'Combinado, até sex 13/11.') = 'teto',
      v_t::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- o NÃO: o caminho do "não vou" com o dia do convite
    perform pg_temp.prepara('desligado', 'ligado', false);
    perform set_config('agenda.hoje', c_qua::text, true);
    perform public._agenda_comunicar_convites(c_qua, pg_temp.em(c_qua, '10:15'));
    perform pg_temp.saiu(pg_temp.em(c_qua, '10:16'));
    v_t := public.agenda_resposta_da_equipe(pg_temp.fone('Roberto'), 'NÃO', 'wa-e5c', pg_temp.em(c_qua, '11:00'));
    m := pg_temp.msg(v_rob, 'convite', c_sex);
    r := pg_temp.ok(r, 'E5c o NÃO é o "não vou" do dia do convite: indisponível na sex 13/11, a ação equipe nao_vou, o convite respondido (convite: nao), "Tá bom, aviso o Gustavo."',
      v_t ->> 'tipo' = 'nao_vou' and (v_t ->> 'dia')::date = c_sex and v_t ->> 'resposta' = 'Tá bom, aviso o Gustavo.'
      and m.estado = 'respondida' and m.leitura ->> 'convite' = 'nao' and m.acao_id is not null
      and exists (select 1 from public.agenda_disponibilidade d where d.payee_id = v_rob and d.situacao = 'indisponivel' and d.periodo @> c_sex)
      and exists (select 1 from public.agenda_acoes a where a.id = m.acao_id and a.tipo = 'equipe' and a.depois ->> 'motivo' = 'nao_vou' and (a.depois ->> 'dia')::date = c_sex),
      v_t::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- o SIM tardio: mais de equipe_resposta_validade (14 h) depois, antes do prazo; a rotina do "sem resposta" não fecha o convite
    perform pg_temp.prepara('desligado', 'ligado', false);
    perform set_config('agenda.hoje', c_qua::text, true);
    perform public._agenda_comunicar_convites(c_qua, pg_temp.em(c_qua, '10:15'));
    perform pg_temp.saiu(pg_temp.em(c_qua, '10:16'));
    perform public._agenda_rotina_sem_resposta(c_qui, pg_temp.em(c_qui, '07:00'));
    r := pg_temp.ok(r, 'E5d a validade da resposta (14 h) não fecha o convite: ele vale até o prazo',
      (pg_temp.msg(v_rob, 'convite', c_sex)).estado = 'enfileirada', (pg_temp.msg(v_rob, 'convite', c_sex)).estado);
    v_t := public.agenda_resposta_da_equipe(pg_temp.fone('Roberto'), 'ok', 'wa-e5d', pg_temp.em(c_qui, '08:00'));
    r := pg_temp.ok(r, 'E5d2 o SIM de qui 08:00 (22 h depois) ainda é do convite', v_t ->> 'leitura' = 'sim' and (pg_temp.msg(v_rob, 'convite', c_sex)).estado = 'respondida',
      v_t::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- o que não é SIM nem NÃO: ao dono, e o convite segue esperando
    perform pg_temp.prepara('desligado', 'ligado', false);
    perform set_config('agenda.hoje', c_qua::text, true);
    perform public._agenda_comunicar_convites(c_qua, pg_temp.em(c_qua, '10:15'));
    perform pg_temp.saiu(pg_temp.em(c_qua, '10:16'));
    v_t := public.agenda_resposta_da_equipe(pg_temp.fone('Roberto'), 'talvez, vejo depois', 'wa-e5e', pg_temp.em(c_qua, '11:00'));
    r := pg_temp.ok(r, 'E5e "talvez, vejo depois": a pergunta ao dono com o trecho e o prazo; o convite continua esperando o SIM; nada muda no plano',
      v_t ->> 'leitura' = 'nao_entendi' and (pg_temp.msg(v_rob, 'convite', c_sex)).estado = 'enfileirada'
      and exists (select 1 from public.agenda_perguntas q where q.chave = format('equipe_resposta:%s:2026-11-13:convite', v_rob) and q.estado = 'aberta'
                    and q.texto like 'O Roberto respondeu "talvez, vejo depois" ao convite de sex 13/11, e eu não entendi. Sem o SIM dele até qui 12/11 às 19:30, ele sai do dia.')
      and not exists (select 1 from public.agenda_disponibilidade d where d.payee_id = v_rob and d.periodo @> c_sex), v_t::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- o vencido: o convite antigo da fixture (qui 12/11, prazo qua 11/11 19:30), sem resposta
    perform pg_temp.prepara('desligado', 'ligado', false);
    perform set_config('agenda.hoje', c_qua::text, true);
    v_t := public._agenda_comunicar_convites_vencidos(c_qua, pg_temp.em(c_qua, '19:45'));
    m := pg_temp.msg(v_rob, 'convite', c_qui);
    r := pg_temp.ok(r, 'E5f vencido: o caminho do "não vou" — indisponível na qui 12/11 ("Não respondeu ao convite"), a ação equipe sem_sim com acorde, o convite sem_resposta',
      (v_t ->> 'vencidos')::int = 1 and m.estado = 'sem_resposta' and m.acao_id is not null
      and exists (select 1 from public.agenda_disponibilidade d where d.payee_id = v_rob and d.situacao = 'indisponivel' and d.periodo @> c_qui
                    and d.nota = 'Não respondeu ao convite')
      and exists (select 1 from public.agenda_acoes a where a.id = m.acao_id and a.tipo = 'equipe' and a.executada and a.depois ->> 'motivo' = 'sem_sim'
                    and (a.depois ->> 'acorde')::boolean and a.texto like 'O Roberto não respondeu ao convite de qui 12/11: tirei ele do Lenine.%'
                    and jsonb_array_length(a.depois -> 'replano_acoes') > 0)
      and not exists (select 1 from public.agenda_alocacoes x where x.payee_id = v_rob and x.dia = c_qui and x.estado in ('publicada', 'fixada') and x.tipo <> 'reserva'),
      v_t::text || ' ' || coalesce((select a.texto from public.agenda_acoes a where a.id = m.acao_id), '-'));
    v_t := public._agenda_rotina_acordes_da_equipe(c_qua, pg_temp.em(c_qua, '20:00'));
    r := pg_temp.ok(r, 'E5g o acorde do vencido é exceção e diz o que houve: "O Roberto não respondeu ao convite de qui 12/11: tirei ele do Lenine." (não "avisou que não vem")',
      v_t -> 'acordes' -> 0 ->> 'texto' like 'O Roberto não respondeu ao convite de qui 12/11: tirei ele do Lenine.%'
      and v_t -> 'acordes' -> 0 ->> 'texto' not like '%avisou que não vem%', v_t::text);
    v_t := public._agenda_comunicar_convites_vencidos(c_qua, pg_temp.em(c_qua, '19:50'));
    r := pg_temp.ok(r, 'E5h o vencido não roda 2 vezes', (v_t ->> 'vencidos')::int = 0
      and (select count(*) from public.agenda_acoes a where a.tipo = 'equipe' and a.depois ->> 'motivo' = 'sem_sim') = 1, v_t::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$e$;

-- ── E6. A resposta ao previsto e à mudança ──────────────────────────────────────────────────────────
do $e$
declare
  r      jsonb := '[]';
  c_qui  constant date := date '2026-11-12';
  c_sex  constant date := date '2026-11-13';
  c_seg  constant date := date '2026-11-16';
  v_rob  uuid;
  v_t    jsonb;
  m      public.agenda_equipe_mensagens;
  v_plano text;
begin
  if not pg_temp.na_bancada() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'E6 a resposta ao previsto', true, 'PULADO: sem agenda_teste.fase7f (rode pela bancada)'));
    return;
  end if;
  v_rob := pg_temp.p('Roberto');
  begin
    perform pg_temp.prepara('ligado', 'desligado', false);
    perform set_config('agenda.hoje', c_qui::text, true);
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_em = pg_temp.em(c_qui, '10:00'), cancelada_motivo = 'cliente'
     where payee_id = v_rob and dia = c_sex and estado in ('publicada', 'fixada');
    perform pg_temp.tique(pg_temp.em(c_qui, '17:00'));
    perform pg_temp.saiu(pg_temp.em(c_qui, '17:01'));
    perform pg_temp.tique(pg_temp.em(c_qui, '19:30'));
    perform pg_temp.saiu(pg_temp.em(c_qui, '19:31'));
    v_t := public.agenda_resposta_da_equipe(pg_temp.fone('Roberto'), 'ok', 'wa-e6a', pg_temp.em(c_qui, '19:40'));
    m := pg_temp.msg(v_rob, 'previsto', c_seg);
    r := pg_temp.ok(r, 'E6a o ok ao previsto é ciência: respondida, nada muda, sem resposta automática',
      (v_t ->> 'ciencia')::boolean and m.estado = 'respondida' and (m.leitura ->> 'ciencia')::boolean
      and not exists (select 1 from public.agenda_equipe_mensagens x where x.payee_id = v_rob and x.tipo = 'resposta' and x.criada_em >= pg_temp.em(c_qui, '19:40'))
      and not exists (select 1 from public.agenda_disponibilidade d where d.payee_id = v_rob and d.criado_em >= pg_temp.em(c_qui, '19:40')), v_t::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.prepara('ligado', 'desligado', false);
    perform set_config('agenda.hoje', c_qui::text, true);
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_em = pg_temp.em(c_qui, '10:00'), cancelada_motivo = 'cliente'
     where payee_id = v_rob and dia = c_sex and estado in ('publicada', 'fixada');
    perform pg_temp.tique(pg_temp.em(c_qui, '17:00'));
    perform pg_temp.saiu(pg_temp.em(c_qui, '17:01'));
    perform pg_temp.tique(pg_temp.em(c_qui, '19:30'));
    perform pg_temp.saiu(pg_temp.em(c_qui, '19:31'));
    v_plano := (select string_agg(concat_ws('|', a.id, a.estado), ',' order by a.id) from public.agenda_alocacoes a where a.payee_id = v_rob);
    v_t := public.agenda_resposta_da_equipe(pg_temp.fone('Roberto'), 'não posso quarta', 'wa-e6b', pg_temp.em(c_qui, '19:40'));
    m := pg_temp.msg(v_rob, 'previsto', c_seg);
    r := pg_temp.ok(r, 'E6b "não posso quarta" ao previsto vai ao dono com o trecho, e nada é remanejado (nem indisponível, nem ação, o plano igual)',
      (v_t ->> 'ao_dono')::boolean and m.estado = 'respondida'
      and exists (select 1 from public.agenda_perguntas q where q.chave = format('equipe_resposta:%s:2026-11-16:previsto', v_rob) and q.estado = 'aberta'
                    and q.texto = 'O Roberto respondeu "não posso quarta" à semana prevista dele, e eu não mudei nada: diga o que fazer.')
      and not exists (select 1 from public.agenda_disponibilidade d where d.payee_id = v_rob and d.criado_em >= pg_temp.em(c_qui, '19:40'))
      and not exists (select 1 from public.agenda_acoes a where a.payee_id = v_rob and a.criada_em >= pg_temp.em(c_qui, '19:40'))
      and (select string_agg(concat_ws('|', a.id, a.estado), ',' order by a.id) from public.agenda_alocacoes a where a.payee_id = v_rob) = v_plano, v_t::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- a ficha da quinta que levou a semana: "não posso quarta" é da semana (ao dono); "não vou" sem dia é o de sempre (o dia da ficha)
    perform pg_temp.prepara('ligado', 'desligado', false);
    perform set_config('agenda.hoje', c_qui::text, true);
    perform pg_temp.tique(pg_temp.em(c_qui, '17:00'));
    perform pg_temp.saiu(pg_temp.em(c_qui, '17:01'));
    perform pg_temp.tique(pg_temp.em(c_qui, '19:30'));
    perform pg_temp.saiu(pg_temp.em(c_qui, '19:31'));
    v_t := public.agenda_resposta_da_equipe(pg_temp.fone('Roberto'), 'não posso quarta', 'wa-e6c', pg_temp.em(c_qui, '19:40'));
    m := pg_temp.msg(v_rob, 'ficha', c_sex);
    r := pg_temp.ok(r, 'E6c à ficha que levou a semana, "não posso quarta" vai ao dono: a ficha segue esperando o OK, e a sex 13/11 não sai do plano',
      (v_t ->> 'semana')::boolean and m.estado = 'enfileirada'
      and exists (select 1 from public.agenda_perguntas q where q.chave = format('equipe_resposta:%s:2026-11-13:semana', v_rob) and q.estado = 'aberta')
      and not exists (select 1 from public.agenda_disponibilidade d where d.payee_id = v_rob and d.situacao = 'indisponivel' and d.criado_em >= pg_temp.em(c_qui, '19:40')),
      v_t::text);
    v_t := public.agenda_resposta_da_equipe(pg_temp.fone('Roberto'), 'amanhã não vou', 'wa-e6d', pg_temp.em(c_qui, '19:50'));
    r := pg_temp.ok(r, 'E6d o controle: "amanhã não vou" à mesma ficha é o de sempre (indisponível na sex 13/11)',
      v_t ->> 'tipo' = 'nao_vou' and (v_t ->> 'dia')::date = c_sex
      and exists (select 1 from public.agenda_disponibilidade d where d.payee_id = v_rob and d.situacao = 'indisponivel' and d.periodo @> c_sex), v_t::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- o ok à mudança na hora é ciência
    perform pg_temp.prepara('ligado', 'desligado', false);
    perform pg_temp.e3_cenario();
    perform public._agenda_equipe_mudanca_na_hora(md5('f7f:p5:acao:dono')::uuid, date '2026-11-10', pg_temp.em(date '2026-11-10', '19:45'));
    perform pg_temp.saiu(pg_temp.em(date '2026-11-10', '19:46'));
    v_t := public.agenda_resposta_da_equipe(pg_temp.fone('Roberto'), 'ok', 'wa-e6e', pg_temp.em(date '2026-11-10', '19:50'));
    r := pg_temp.ok(r, 'E6e o ok à mudança na hora é ciência (a mensagem respondida, sem resposta automática)',
      (v_t ->> 'ciencia')::boolean and v_t ->> 'tipo' = 'mudanca' and (pg_temp.msg(v_rob, 'mudanca', date '2026-11-11')).estado = 'respondida', v_t::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$e$;

-- ── E7. A janela, o domingo e o teto ────────────────────────────────────────────────────────────────
do $e$
declare
  r      jsonb := '[]';
  c_qui  constant date := date '2026-11-12';
  c_sex  constant date := date '2026-11-13';
  c_dom  constant date := date '2026-11-15';
  v_rob  uuid;
  v_t    jsonb;
  v_a    int;
  v_b    int;
  v_c    int;
  v_d    int;
begin
  r := pg_temp.ok(r, 'E7a os tipos novos usam a janela normal da equipe (07:30 a 20:00, nunca o domingo): a mesma regra da ficha',
    (select bool_and(public._agenda_equipe_fora_da_janela(t, pg_temp.em(c_qui, '07:29'), pg_temp.em(c_qui, '07:29')) = 'janela'
                     and public._agenda_equipe_fora_da_janela(t, pg_temp.em(c_qui, '07:30'), pg_temp.em(c_qui, '07:30')) is null
                     and public._agenda_equipe_fora_da_janela(t, pg_temp.em(c_qui, '19:59'), pg_temp.em(c_qui, '19:59')) is null
                     and public._agenda_equipe_fora_da_janela(t, pg_temp.em(c_qui, '20:00'), pg_temp.em(c_qui, '20:00')) = 'janela'
                     and public._agenda_equipe_fora_da_janela(t, pg_temp.em(c_dom, '10:00'), pg_temp.em(c_dom, '10:00')) = 'domingo'
                     and public._agenda_equipe_fora_da_janela(t, pg_temp.em(c_qui, '22:30'), pg_temp.em(c_qui, '22:30'))
                         is not distinct from public._agenda_equipe_fora_da_janela('ficha', pg_temp.em(c_qui, '22:30'), pg_temp.em(c_qui, '22:30')))
       from unnest(array['previsto', 'mudanca', 'convite']) t), null);
  if not pg_temp.na_bancada() then
    perform pg_temp.gravar(r || pg_temp.ok('[]', 'E7 os tiques', true, 'PULADO: sem agenda_teste.fase7f (rode pela bancada)'));
    return;
  end if;
  v_rob := pg_temp.p('Roberto');
  begin
    perform pg_temp.prepara('ligado', 'ligado', false);
    v_t := public.agenda_comunicar_rodar(c_dom, pg_temp.em(c_dom, '10:00'));
    r := pg_temp.ok(r, 'E7b no domingo a rodada não roda', not (v_t ->> 'rodou')::boolean and v_t ->> 'motivo' = 'domingo', v_t::text);
    v_t := public._agenda_comunicar_mudancas_equipe(c_dom, pg_temp.em(c_dom, '10:00'))
           || jsonb_build_object('convites', public._agenda_comunicar_convites(c_dom, pg_temp.em(c_dom, '10:00')));
    r := pg_temp.ok(r, 'E7c chamados no domingo, os passos não registram nada (a mudança espera a janela; o convite também)',
      v_t ->> 'motivo' = 'janela' and not exists (select 1 from public.agenda_equipe_mensagens x where x.tipo in ('previsto', 'mudanca', 'convite') and x.criada_em >= pg_temp.em(c_dom, '00:00')),
      v_t::text);
    v_t := public._agenda_comunicar_previsto(c_qui, pg_temp.em(c_qui, '20:05'));
    r := pg_temp.ok(r, 'E7d na quinta depois das 20:00 o previsto não registra (nada à noite; a lição de setembro)', v_t ->> 'motivo' = 'janela', v_t::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- o teto de 2 na quinta: o previsto que vai junto da ficha não conta a mais; o que vai sozinho conta (a pergunta dos dias da 7b o vê)
    perform pg_temp.prepara('desligado', 'desligado', false);
    v_a := public._agenda_equipe_previstas_hoje(v_rob, c_qui, pg_temp.em(c_qui, '16:45'));
    update public.agenda_config set modo_equipe_previsto = 'ligado' where id;
    v_b := public._agenda_equipe_previstas_hoje(v_rob, c_qui, pg_temp.em(c_qui, '16:45'));
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_em = pg_temp.em(c_qui, '10:00'), cancelada_motivo = 'cliente'
     where payee_id = v_rob and dia = c_sex and estado in ('publicada', 'fixada');
    v_c := public._agenda_equipe_previstas_hoje(v_rob, c_qui, pg_temp.em(c_qui, '16:45'));
    update public.agenda_config set gestor_so_propor = true where id;
    v_d := public._agenda_equipe_previstas_hoje(v_rob, c_qui, pg_temp.em(c_qui, '16:45'));
    update public.agenda_config set gestor_so_propor = false, modo_equipe_previsto = 'desligado' where id;
    r := pg_temp.ok(r, 'E7e _agenda_equipe_previstas_hoje na quinta: com a ficha de amanhã, o previsto vai junto (a conta não muda); sem ela, o previsto sozinho conta +1; com o freio, a conta de antes',
      v_b = v_a and v_c = public._agenda_equipe_previstas_hoje(v_rob, c_qui, pg_temp.em(c_qui, '16:45')) + 1 and v_d = v_c - 1,
      format('desligado com ficha %s; ligado com ficha %s; ligado sem ficha %s; freio sem ficha %s; desligado sem ficha %s', v_a, v_b, v_c, v_d,
             public._agenda_equipe_previstas_hoje(v_rob, c_qui, pg_temp.em(c_qui, '16:45'))));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$e$;

-- ── E8. O freio e a sombra ──────────────────────────────────────────────────────────────────────────
-- O dia de tiques da quarta e da quinta, com o convite antigo vencendo e a mudança das 19:30, em 3 estados: os 2 modos desligados (o de antes), em teste, e ligados com o
-- freio (o caso real: _agenda_fala_modo = teste). As mensagens de antes (a ficha, o "como foi", a confirmação, a resposta) iguais nos 3; nada da 7f na fila; em teste, só ":sombra".
create function pg_temp.e8_dia(p_prev text, p_conv text, p_freio boolean) returns jsonb language plpgsql as $f$
declare
  v_rob uuid := pg_temp.p('Roberto');
  v_j   jsonb;
  x     jsonb;
begin
  perform pg_temp.prepara(p_prev, p_conv, p_freio);
  perform set_config('agenda.hoje', '2026-11-11', true);
  perform public._agenda_comunicar_convites(date '2026-11-11', pg_temp.em(date '2026-11-11', '10:15'));
  perform pg_temp.tique(pg_temp.em(date '2026-11-11', '17:00'));
  perform pg_temp.saiu(pg_temp.em(date '2026-11-11', '17:01'));
  perform pg_temp.tique(pg_temp.em(date '2026-11-11', '19:30'));
  perform pg_temp.saiu(pg_temp.em(date '2026-11-11', '19:31'));
  x := public.agenda_resposta_da_equipe(pg_temp.fone('Roberto'), 'ok', 'wa-e8', pg_temp.em(date '2026-11-11', '19:40'));
  perform pg_temp.tique(pg_temp.em(date '2026-11-12', '07:30'));
  perform pg_temp.tique(pg_temp.em(date '2026-11-12', '19:30'));
  select jsonb_build_object(
    'antes', (select coalesce(jsonb_agg(jsonb_build_object('p', m.payee_id, 'dia', m.dia, 'tipo', m.tipo, 'modo', m.modo, 'estado', m.estado, 'motivo', m.recusa_motivo,
                                                           'texto', m.texto, 'chave', m.dedupe_key, 'leva', m.leva_ficha_de, 'dias', m.dias)
                                        order by m.payee_id, m.dia, m.tipo, m.dedupe_key), '[]')
                from public.agenda_equipe_mensagens m where m.tipo not in ('previsto', 'mudanca', 'convite')),
    'novas', (select coalesce(jsonb_agg(jsonb_build_object('tipo', m.tipo, 'modo', m.modo, 'estado', m.estado, 'chave', m.dedupe_key) order by m.dedupe_key), '[]')
                from public.agenda_equipe_mensagens m where m.tipo in ('previsto', 'mudanca', 'convite') and m.criada_em >= pg_temp.em(date '2026-11-11', '00:00')),
    'fila', (select coalesce(jsonb_agg(jsonb_build_object('m', md5(q.message), 'k', q.dedupe_key) order by q.dedupe_key), '[]') from public.whatsapp_send_queue q where q.source = 'agenda-equipe'),
    'fila_7f', pg_temp.fila_7f(),
    'resposta', x,
    'acordes', public._agenda_rotina_acordes_da_equipe(date '2026-11-12', pg_temp.em(date '2026-11-12', '19:45')),
    'acoes', (select coalesce(jsonb_agg(jsonb_build_object('tipo', a.tipo, 'motivo', a.depois ->> 'motivo', 'exec', a.executada, 'texto', a.texto) order by a.criada_em, a.texto), '[]')
                from public.agenda_acoes a where a.dia >= date '2026-11-11'),
    'disp', (select coalesce(jsonb_agg(jsonb_build_object('p', d.payee_id, 'situacao', d.situacao, 'periodo', d.periodo::text) order by d.payee_id, d.periodo::text), '[]')
               from public.agenda_disponibilidade d where d.criado_em >= pg_temp.em(date '2026-11-11', '00:00')))
    into v_j;
  return v_j;
end $f$;
do $e$
declare
  r      jsonb := '[]';
  v_des  jsonb;
  v_som  jsonb;
  v_frei jsonb;
  v_lig  jsonb;
begin
  if not pg_temp.na_bancada() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'E8 o freio e a sombra', true, 'PULADO: sem agenda_teste.fase7f (rode pela bancada)'));
    return;
  end if;
  begin
    v_des := pg_temp.e8_dia('desligado', 'desligado', true);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    v_som := pg_temp.e8_dia('sombra', 'sombra', true);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    v_frei := pg_temp.e8_dia('ligado', 'ligado', true);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    v_lig := pg_temp.e8_dia('ligado', 'ligado', false);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  r := pg_temp.ok(r, 'E8a desligados: nenhuma mensagem da 7f, nada da 7f na fila, nenhuma ação dela',
    v_des -> 'novas' = '[]'::jsonb and (v_des ->> 'fila_7f')::int = 0 and not (v_des -> 'acoes')::text ~ 'sem_sim|convite_sem_prazo', (v_des -> 'novas')::text);
  r := pg_temp.ok(r, 'E8b em teste: a ficha, o "como foi", a confirmação, a resposta, o acorde, as ações e a disponibilidade iguais aos desligados; a fila igual',
    v_som -> 'antes' = v_des -> 'antes' and v_som -> 'fila' = v_des -> 'fila' and v_som -> 'resposta' = v_des -> 'resposta'
    and v_som -> 'acordes' = v_des -> 'acordes' and v_som -> 'acoes' = v_des -> 'acoes' and v_som -> 'disp' = v_des -> 'disp',
    left((v_som -> 'antes')::text, 300));
  r := pg_temp.ok(r, 'E8c em teste só registra: as mensagens da 7f com modo sombra, estado registrada e a chave ":sombra"; nada delas na fila',
    jsonb_array_length(v_som -> 'novas') > 0 and (v_som ->> 'fila_7f')::int = 0
    and not exists (select 1 from jsonb_array_elements(v_som -> 'novas') n where n ->> 'modo' <> 'sombra' or n ->> 'estado' <> 'registrada' or n ->> 'chave' not like '%:sombra'),
    (v_som -> 'novas')::text);
  r := pg_temp.ok(r, 'E8d ligados com o freio (gestor_so_propor, o caso real) = em teste: o mesmo que a sombra, byte a byte, e nada vai à fila',
    v_frei = v_som, case when v_frei = v_som then null else left((v_frei -> 'novas')::text, 400) end);
  r := pg_temp.ok(r, 'E8e o controle: ligados sem o freio, a fila ganha as mensagens da 7f e o convite vencido tira o Roberto do dia',
    (v_lig ->> 'fila_7f')::int > 0 and (v_lig -> 'acoes')::text ~ 'sem_sim' and v_lig -> 'antes' <> v_des -> 'antes', (v_lig ->> 'fila_7f'));
  perform pg_temp.gravar(r);
end
$e$;

-- ── E9. As cópias ───────────────────────────────────────────────────────────────────────────────────
do $e$
declare
  r     jsonb := '[]';
  v_mig text := coalesce(current_setting('agenda_teste.mig_equipe_fase7f', true), '');
  x     record;
  v_a   text;
  v_n   int;
begin
  if v_mig = '' then
    perform pg_temp.gravar(pg_temp.ok('[]', 'E9 as cópias', true, 'PULADO: sem agenda_teste.mig_equipe_fase7f (rode pela bancada)'));
    return;
  end if;
  for x in select * from (values
      ('_agenda_equipe_registrar', 'public._agenda_equipe_registrar(uuid, date, text, text, timestamptz, date, text, date[], uuid[], text)', 'mig_pergunta_fase7b', 4),
      ('_agenda_equipe_previstas_hoje', 'public._agenda_equipe_previstas_hoje(uuid, date, timestamptz)', 'mig_pergunta_fase7b', 1),
      ('_agenda_rotina_sem_resposta', 'public._agenda_rotina_sem_resposta(date, timestamptz)', 'mig_pergunta_fase7b', 1),
      ('_agenda_rotina_ficha', 'public._agenda_rotina_ficha(date, timestamptz)', 'mig_correcao2_fase7a', 4),
      ('_agenda_rotina_como_foi', 'public._agenda_rotina_como_foi(date, timestamptz)', 'mig_protecoes_fase7a', 3),
      ('agenda_resposta_da_equipe', 'public.agenda_resposta_da_equipe(text, text, text, timestamptz)', 'mig_tarefas_fase7c', 5),
      ('_agenda_texto_do_acorde', 'public._agenda_texto_do_acorde(uuid, date, date)', 'mig_equipe_fase3', 2),
      ('_agenda_rotina_acordes_da_equipe', 'public._agenda_rotina_acordes_da_equipe(date, timestamptz)', 'mig_equipe_fase3', 1)) t(nome, sig, fonte, blocos)
  loop
    select count(*) into v_n from regexp_matches(replace((select p.prosrc from pg_proc p where p.oid = x.sig::regprocedure), E'\r\n', E'\n'), '-- FASE 7f: fim', 'g');
    r := pg_temp.ok(r, format('E9a %s: a viva é a desta migration; sem os %s blocos "-- FASE 7f:", é o corpo da origem (agenda_teste.%s), byte a byte', x.nome, x.blocos, x.fonte),
      coalesce(current_setting('agenda_teste.' || x.fonte, true), '') <> ''
      and replace((select p.prosrc from pg_proc p where p.oid = x.sig::regprocedure), E'\r\n', E'\n') = pg_temp.corpo(v_mig, x.nome)
      and v_n = x.blocos
      and pg_temp.sem_7f(pg_temp.corpo(v_mig, x.nome)) = pg_temp.corpo(current_setting('agenda_teste.' || x.fonte, true), x.nome)
      and pg_temp.corpo(current_setting('agenda_teste.' || x.fonte, true), x.nome) <> '',
      format('blocos %s; origem %s letras; viva sem os blocos %s letras', v_n, length(pg_temp.corpo(current_setting('agenda_teste.' || x.fonte, true), x.nome)),
             length(pg_temp.sem_7f(pg_temp.corpo(v_mig, x.nome)))));
  end loop;
  select string_agg(distinct m[1], ',' order by m[1]) into v_a
    from regexp_matches(v_mig, 'create or replace function public\.([a-z_0-9]+)\(', 'g') m;
  r := pg_temp.ok(r, 'E9b a migration cria as 11 novas e recria só as 8 que diz (a rodada comunicar, a ficha da equipe, as do cliente e as do motor ficam)',
    v_a = '_agenda_comunicar_convites,_agenda_comunicar_convites_vencidos,_agenda_comunicar_mudancas_equipe,_agenda_comunicar_previsto,_agenda_dias_avisados,_agenda_dias_do_plano_da_pessoa,_agenda_equipe_convite_prazo,_agenda_equipe_ja_avisei,_agenda_equipe_mudanca_na_hora,_agenda_equipe_previstas_hoje,_agenda_equipe_previsto_sozinho,_agenda_equipe_registrar,_agenda_equipe_semana_da_pessoa,_agenda_rotina_acordes_da_equipe,_agenda_rotina_como_foi,_agenda_rotina_ficha,_agenda_rotina_sem_resposta,_agenda_texto_do_acorde,agenda_resposta_da_equipe',
    v_a);
  r := pg_temp.ok(r, 'E9c sem tabela, coluna nem dado: nenhum alter table, insert, update de agenda_config; 1 drop function (a assinatura velha do registro)',
    v_mig !~* '\malter table\M' and v_mig !~* 'update public\.agenda_config' and v_mig !~* 'insert into public\.agenda_config'
    and (select count(*) from regexp_matches(v_mig, '^drop function', 'gn')) = 1, null);
  perform pg_temp.gravar(r);
end
$e$;

-- ── E10. O texto à equipe ───────────────────────────────────────────────────────────────────────────
do $e$
declare
  r      jsonb := '[]';
  v_rob  uuid;
  v_txt  text[] := '{}';
  v_ruins text;
begin
  if not pg_temp.na_bancada() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'E10 o texto', true, 'PULADO: sem agenda_teste.fase7f (rode pela bancada)'));
    return;
  end if;
  v_rob := pg_temp.p('Roberto');
  r := pg_temp.ok(r, 'E10a a varredura morde: reprova o texto plantado com valor, com número de OS, com o nome de outro cliente, e o vazio',
    not pg_temp.limpo('Roberto, sex 13/11: Lenine, R$ 300,00.', v_rob) and not pg_temp.limpo('Roberto, sex 13/11: OS-F2.', v_rob)
    and not pg_temp.limpo('Roberto, sex 13/11: no lugar do Giancarlo.', v_rob) and not pg_temp.limpo('', v_rob) and not pg_temp.limpo(null, v_rob)
    and pg_temp.limpo('Roberto, sex 13/11: 8h no motorhome do Lenine.', v_rob), null);
  begin
    -- todos os textos que a 7f escreve à equipe nos cenários de cima, juntos: o previsto (junto e sozinho), a mudança (junto, sozinha, na hora) e o convite
    perform pg_temp.prepara('ligado', 'ligado', false);
    perform set_config('agenda.hoje', '2026-11-10', true);
    perform pg_temp.e3_cenario();
    perform public._agenda_comunicar_mudancas_equipe(date '2026-11-10', pg_temp.em(date '2026-11-10', '19:45'));
    perform public._agenda_comunicar_convites(date '2026-11-11', pg_temp.em(date '2026-11-11', '10:15'));
    perform pg_temp.saiu(pg_temp.em(date '2026-11-11', '10:16'));
    perform pg_temp.tique(pg_temp.em(date '2026-11-11', '19:30'));
    perform pg_temp.saiu(pg_temp.em(date '2026-11-11', '19:31'));
    perform public.agenda_resposta_da_equipe(pg_temp.fone('Roberto'), 'sim', 'wa-e10', pg_temp.em(date '2026-11-11', '19:40'));
    perform pg_temp.tique(pg_temp.em(date '2026-11-12', '19:30'));
    select array_agg(m.texto order by m.criada_em), string_agg(m.texto, ' || ') filter (where not pg_temp.limpo(m.texto, m.payee_id))
      into v_txt, v_ruins
      from public.agenda_equipe_mensagens m
     where m.criada_em >= pg_temp.em(date '2026-11-10', '19:44') and (m.tipo in ('previsto', 'mudanca', 'convite') or m.dias is not null
                                                                        or m.texto like 'Combinado, até %');
    r := pg_temp.ok(r, 'E10b os textos da 7f à equipe (o convite, a mudança na hora, a mudança junto da ficha, o previsto, "Combinado"): nenhum vazio, nenhum com valor, OS ou cliente de outro',
      cardinality(v_txt) >= 4 and v_ruins is null, coalesce(v_ruins, array_to_string(v_txt, ' || ')));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$e$;

-- ── E11. Os cantos: cada guarda das funções novas tem o caso que a reprova ───────────────────────────
do $e$
declare
  r      jsonb := '[]';
  c_ter  constant date := date '2026-11-10';
  c_qua  constant date := date '2026-11-11';
  c_qui  constant date := date '2026-11-12';
  c_sex  constant date := date '2026-11-13';
  c_seg  constant date := date '2026-11-16';
  v_rob  uuid;
  v_raf  uuid;
  v_a    uuid;
  v_t    jsonb;
  v_txt  text;
  m      public.agenda_equipe_mensagens;
  v_ficha text;
begin
  if not pg_temp.na_bancada() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'E11 os cantos', true, 'PULADO: sem agenda_teste.fase7f (rode pela bancada)'));
    return;
  end if;
  v_rob := pg_temp.p('Roberto');
  v_raf := pg_temp.p('Rafael');
  -- o registro: as guardas do ramo novo
  begin
    perform pg_temp.prepara('desligado', 'desligado', false);
    v_t := public._agenda_equipe_registrar(v_rob, c_qua, 'mudanca', 'Roberto, mudou.', pg_temp.em(c_qua, '10:00'), null, null, '{}'::date[], null, 'agenda-equipe:mudanca:x:19h');
    r := pg_temp.ok(r, 'E11a com a equipe ligada e o previsto desligado, o registro da mudança não grava nada ({criada: false, modo: desligado})',
      v_t ->> 'modo' = 'desligado' and not (v_t ->> 'criada')::boolean and not exists (select 1 from public.agenda_equipe_mensagens where tipo = 'mudanca'), v_t::text);
    update public.agenda_config set modo_equipe_previsto = 'ligado', modo_equipe_convite = 'ligado' where id;
    r := pg_temp.ok(r, 'E11b o ramo novo recusa (22023): o texto vazio, o previsto sem dias, o convite sem as alocações e o convite de outro dia',
      pg_temp.lanca(format($q$select public._agenda_equipe_registrar(%L::uuid, date '2026-11-16', 'previsto', '  ', now(), null, null, array[date '2026-11-18'])$q$, v_rob)) = '22023'
      and pg_temp.lanca(format($q$select public._agenda_equipe_registrar(%L::uuid, date '2026-11-16', 'previsto', 'Roberto, semana.', now())$q$, v_rob)) = '22023'
      and pg_temp.lanca(format($q$select public._agenda_equipe_registrar(%L::uuid, date '2026-11-16', 'previsto', 'Roberto, semana.', now(), null, null, '{}'::date[])$q$, v_rob)) = '22023'
      and pg_temp.lanca(format($q$select public._agenda_equipe_registrar(%L::uuid, date '2026-11-13', 'convite', 'Roberto, pode vir?', now(), null, null, array[date '2026-11-13'])$q$, v_rob)) = '22023'
      and pg_temp.lanca(format($q$select public._agenda_equipe_registrar(%L::uuid, date '2026-11-13', 'convite', 'Roberto, pode vir?', now(), null, null, array[date '2026-11-14'], array[gen_random_uuid()])$q$, v_rob)) = '22023',
      null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  -- o previsto sozinho (a conta da 7b): só na quinta, só com dia na semana que vem, e não depois de sair
  begin
    perform pg_temp.prepara('ligado', 'desligado', false);
    perform set_config('agenda.hoje', c_qua::text, true);
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_em = pg_temp.em(c_qua, '09:00'), cancelada_motivo = 'cliente'
     where payee_id = v_rob and dia in (c_qui, c_sex) and estado in ('publicada', 'fixada');
    r := pg_temp.ok(r, 'E11c o previsto sozinho só conta na quinta (na quarta, sem ficha de amanhã e com dia na semana que vem, não)',
      not public._agenda_equipe_previsto_sozinho(v_rob, c_qua) and public._agenda_equipe_previsto_sozinho(v_rob, c_qui), null);
    r := pg_temp.ok(r, 'E11d sem dia na semana que vem (o Rafael), o previsto sozinho não conta',
      not public._agenda_equipe_previsto_sozinho(v_raf, c_qui), null);
    perform public._agenda_comunicar_previsto(c_qui, pg_temp.em(c_qui, '19:30'));
    r := pg_temp.ok(r, 'E11e depois que o previsto da semana saiu, ele não conta mais', not public._agenda_equipe_previsto_sozinho(v_rob, c_qui)
      and (pg_temp.msg(v_rob, 'previsto', c_seg)).estado = 'enfileirada', null);
    v_t := public._agenda_comunicar_previsto(c_qui, pg_temp.em(c_qui, '16:00'));
    r := pg_temp.ok(r, 'E11f antes das 19:30 da quinta o passo previsto pula (cedo)', v_t ->> 'motivo' = 'cedo', v_t::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.prepara('ligado', 'desligado', false);
    perform set_config('agenda.hoje', c_qui::text, true);
    v_t := public._agenda_comunicar_previsto(c_qui, pg_temp.em(c_qui, '16:00'));
    r := pg_temp.ok(r, 'E11f2 o controle do cedo: às 16:00 nenhuma mensagem nasce (às 19:30 a ficha a leva)',
      not exists (select 1 from public.agenda_equipe_mensagens x where x.payee_id = v_rob and x.tipo = 'previsto' and x.dia = c_seg), v_t::text);
    -- a semana de quem não ouviu nada: sem mudança, mesmo com dia novo
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, duracao_fonte, criado_em)
    values (md5('f7f:p5:rafael:18')::uuid, pg_temp.os('301'), v_raf, date '2026-11-20', 'manha', 'turno', 'execucao', 'publicada', 'motor',
            pg_temp.em(date '2026-11-05', '16:30'), 'orcamento', pg_temp.em(date '2026-11-05', '16:30'));
    r := pg_temp.ok(r, 'E11g quem não ouviu nada da semana (o Rafael) não tem mudança, mesmo com dia novo no plano (a semana dele diz o plano)',
      jsonb_typeof(public._agenda_equipe_semana_da_pessoa(v_raf, c_qua, pg_temp.em(c_qua, '19:30')) -> 'mudanca') is distinct from 'object'
      and public._agenda_equipe_semana_da_pessoa(v_raf, c_qua, pg_temp.em(c_qua, '19:30')) -> 'plano' ? '2026-11-20', null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  -- o que ele ouviu: a ficha recusada não conta; o convite sem SIM não conta; o SIM depois da mudança das 19:30 conta; a mudança na hora só troca o dia dela
  begin
    perform pg_temp.prepara('ligado', 'desligado', false);
    perform set_config('agenda.hoje', c_qui::text, true);
    perform public._agenda_equipe_registrar(v_rob, date '2026-12-01', 'ficha', 'Roberto, teste do teto 1.', pg_temp.em(c_qui, '10:00'));
    perform public._agenda_equipe_registrar(v_rob, date '2026-12-02', 'ficha', 'Roberto, teste do teto 2.', pg_temp.em(c_qui, '10:05'));
    perform pg_temp.tique(pg_temp.em(c_qui, '19:30'));
    r := pg_temp.ok(r, 'E11h a ficha e o previsto recusados (o teto) não contam no que ele ouviu: segue ter 17 e qua 18 do previsto de 05/11',
      public._agenda_dias_avisados(v_rob, date '2026-11-14', date '2026-11-22') = array[date '2026-11-17', date '2026-11-18'],
      public._agenda_dias_avisados(v_rob, date '2026-11-14', date '2026-11-22')::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.prepara('ligado', 'ligado', false);
    perform set_config('agenda.hoje', c_qua::text, true);
    -- sem o Flávio de hoje (nenhum "como foi" hoje): o convite das 10:15 e a mudança das 19:30 são as 2 do dia
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_em = pg_temp.em(c_qua, '09:00'), cancelada_motivo = 'cliente'
     where payee_id = v_rob and dia = c_qua and estado in ('publicada', 'fixada');
    perform public._agenda_comunicar_convites(c_qua, pg_temp.em(c_qua, '10:15'));
    perform pg_temp.saiu(pg_temp.em(c_qua, '10:16'));
    r := pg_temp.ok(r, 'E11i o convite sem o SIM não conta no que ele ouviu', not (c_sex = any (public._agenda_dias_avisados(v_rob, c_qua, date '2026-11-22'))), null);
    perform pg_temp.tique(pg_temp.em(c_qua, '19:30'));
    perform pg_temp.saiu(pg_temp.em(c_qua, '19:31'));
    -- o "ok" à mudança das 19:30 (ciência) e, depois, o SIM ao convite das 10:15
    perform public.agenda_resposta_da_equipe(pg_temp.fone('Roberto'), 'ok', 'wa-e11j1', pg_temp.em(c_qua, '19:35'));
    v_t := public.agenda_resposta_da_equipe(pg_temp.fone('Roberto'), 'sim', 'wa-e11j', pg_temp.em(c_qua, '19:40'));
    r := pg_temp.ok(r, 'E11j o SIM depois da mudança das 19:30 conta pela hora do SIM: a sex 13/11 entra no que ele ouviu (a mudança das 19:30 não a apaga)',
      v_t ->> 'leitura' = 'sim' and c_sex = any (public._agenda_dias_avisados(v_rob, c_qua, date '2026-11-22'))
      and (select x.estado from public.agenda_equipe_mensagens x where x.payee_id = v_rob and x.dedupe_key = format('agenda-equipe:mudanca:%s:2026-11-11:19h', v_rob)) = 'respondida',
      v_t::text || ' ' || public._agenda_dias_avisados(v_rob, c_qua, date '2026-11-22')::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- a mudança na hora: só troca o dia dela; de outra ação não é "avisei"; sem telefone, nada; a ação desfeita, nada; a da vigia, só pelo replano da falta
    perform pg_temp.prepara('ligado', 'desligado', false);
    v_a := pg_temp.e3_cenario();
    perform public._agenda_equipe_mudanca_na_hora(v_a, c_ter, pg_temp.em(c_ter, '19:45'));
    r := pg_temp.ok(r, 'E11k a mudança na hora só troca o dia dela: o que ele ouviu da semana (ter 17, qua 18) fica',
      public._agenda_dias_avisados(v_rob, date '2026-11-12', date '2026-11-22') = array[date '2026-11-17', date '2026-11-18'], null);
    insert into public.agenda_acoes (id, criada_em, dia, executada, origem, tipo, service_order_id, os_ids, alocacoes_criadas, alocacoes_canceladas, payee_id, texto)
    values (md5('f7f:p5:acao:outra')::uuid, pg_temp.em(c_ter, '19:50'), c_ter, true, 'vigia', 'mover', pg_temp.os('304'), array[pg_temp.os('304')],
            array[pg_temp.aloc('304', 'roberto', '2026-11-11', 'manha')], '{}', v_rob, 'Outra mudança no Flávio de qua 11/11.');
    v_txt := public._agenda_texto_do_acorde(md5('f7f:p5:acao:outra')::uuid, c_qua, c_ter);
    r := pg_temp.ok(r, 'E11l a mensagem de mudança é de uma ação: o acorde de outra ação do mesmo dia não diz "Já avisei"',
      v_txt not like '%Já avisei%' and v_txt like '%avise ele da mudança.', v_txt);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.prepara('ligado', 'desligado', false);
    v_a := pg_temp.e3_cenario();
    update public.payees set phone = null where id = v_rob;
    v_t := public._agenda_equipe_mudanca_na_hora(v_a, c_ter, pg_temp.em(c_ter, '19:45'));
    r := pg_temp.ok(r, 'E11m sem telefone, a mudança na hora não nasce (nada recusado na tabela; o acorde segue mandando o dono avisar)',
      not exists (select 1 from public.agenda_equipe_mensagens x where x.payee_id = v_rob and x.tipo = 'mudanca'), v_t::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.prepara('ligado', 'desligado', false);
    v_a := pg_temp.e3_cenario();
    update public.agenda_acoes set desfeita_em = pg_temp.em(c_ter, '19:42'), desfeita_pela = id where id = v_a;
    v_t := public._agenda_equipe_mudanca_na_hora(v_a, c_ter, pg_temp.em(c_ter, '19:45'));
    r := pg_temp.ok(r, 'E11n a ação desfeita não vira mensagem (o dia voltou)', v_t ->> 'motivo' = 'sem_troca'
      and not exists (select 1 from public.agenda_equipe_mensagens x where x.payee_id = v_rob and x.tipo = 'mudanca'), v_t::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.prepara('ligado', 'desligado', false);
    v_a := pg_temp.e3_cenario('vigia');
    v_t := public._agenda_comunicar_mudancas_equipe(c_ter, pg_temp.em(c_ter, '19:45'));
    r := pg_temp.ok(r, 'E11o a ação da vigia sozinha (sem decisão do dono nem falta de ninguém) não vira mensagem na hora (o acorde manda o dono avisar)',
      not exists (select 1 from public.agenda_equipe_mensagens x where x.payee_id = v_rob and x.tipo = 'mudanca' and x.dia = c_qua) and v_t -> 'na_hora' = '{}'::jsonb, v_t::text);
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
    values (pg_temp.em(c_ter, '19:39'), c_ter, true, 'equipe', 'equipe', pg_temp.os('304'), array[pg_temp.os('304')], v_raf,
            jsonb_build_object('motivo', 'nao_vou', 'dia', c_qua, 'replano_acoes', jsonb_build_array(v_a), 'acorde', true), 'O Rafael avisou que não vem amanhã (qua 11/11).');
    v_t := public._agenda_comunicar_mudancas_equipe(c_ter, pg_temp.em(c_ter, '19:50'));
    r := pg_temp.ok(r, 'E11p a mesma ação da vigia, sendo o replano da falta de outra pessoa, vira a mensagem na hora',
      exists (select 1 from public.agenda_equipe_mensagens x where x.payee_id = v_rob and x.tipo = 'mudanca' and x.dia = c_qua and x.estado = 'enfileirada'), v_t::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  -- o convite: só o dia novo a menos de 72 h; com o freio, a exceção não vira ação; fora da janela e no teto, espera
  begin
    perform pg_temp.prepara('desligado', 'ligado', false);
    perform set_config('agenda.hoje', c_qua::text, true);
    perform public._agenda_comunicar_convites(c_qua, pg_temp.em(c_qua, '10:15'));
    r := pg_temp.ok(r, 'E11q só os dias novos a menos de 72 h: o Roberto tem os convites da qui 12/11 (o da fixture) e da sex 13/11; a qua 18 e a qui 19/11 (criadas em 05/11) não',
      (select array_agg(x.dia order by x.dia) from public.agenda_equipe_mensagens x where x.payee_id = v_rob and x.tipo = 'convite') = array[c_qui, c_sex], null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.prepara('desligado', 'ligado', true);
    perform set_config('agenda.hoje', c_qui::text, true);
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, duracao_fonte, criado_em)
    values (md5('f7f:p5:rafael:12')::uuid, pg_temp.os('305'), v_raf, c_qui, 'tarde', 'turno', 'execucao', 'publicada', 'motor', pg_temp.em(c_qua, '21:00'), 'orcamento',
            pg_temp.em(c_qua, '21:00'));
    v_t := public._agenda_comunicar_convites(c_qui, pg_temp.em(c_qui, '07:45'));
    r := pg_temp.ok(r, 'E11r com o freio (o convite em teste), o prazo passado só conta: nenhuma ação, nenhum acorde',
      (v_t #>> '{por_estado,sem_prazo}')::int >= 1
      and not exists (select 1 from public.agenda_acoes a where a.tipo = 'equipe' and a.depois ->> 'motivo' = 'convite_sem_prazo'), v_t::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.prepara('desligado', 'ligado', false);
    perform set_config('agenda.hoje', c_qua::text, true);
    v_t := public._agenda_comunicar_convites(c_qua, pg_temp.em(c_qua, '21:00'));
    r := pg_temp.ok(r, 'E11s fora da janela (21:00), o convite espera: nenhuma linha nasce (nem recusada)',
      (v_t #>> '{por_estado,espera_janela}')::int >= 1 and not exists (select 1 from public.agenda_equipe_mensagens x where x.payee_id = v_rob and x.tipo = 'convite' and x.dia = c_sex),
      v_t::text);
    perform public._agenda_equipe_registrar(v_rob, date '2026-12-01', 'ficha', 'Roberto, teste do teto 1.', pg_temp.em(c_qua, '10:00'));
    perform public._agenda_equipe_registrar(v_rob, date '2026-12-02', 'ficha', 'Roberto, teste do teto 2.', pg_temp.em(c_qua, '10:05'));
    v_t := public._agenda_comunicar_convites(c_qua, pg_temp.em(c_qua, '10:15'));
    r := pg_temp.ok(r, 'E11t no teto do dia, o convite espera (o dia seguinte, antes do prazo): nenhuma linha recusada',
      (v_t #>> '{por_estado,espera_teto}')::int >= 1 and not exists (select 1 from public.agenda_equipe_mensagens x where x.payee_id = v_rob and x.tipo = 'convite' and x.dia = c_sex),
      v_t::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.prepara('desligado', 'ligado', false);
    perform set_config('agenda.hoje', c_qua::text, true);
    v_t := public._agenda_comunicar_convites_vencidos(c_qua, pg_temp.em(c_qua, '19:00'));
    r := pg_temp.ok(r, 'E11u antes do prazo (qua 19:00; o prazo é 19:30), o convite antigo não vence', (v_t ->> 'vencidos')::int = 0
      and (pg_temp.msg(v_rob, 'convite', c_qui)).estado = 'enfileirada', v_t::text);
    -- o SIM com os turnos diferentes do plano (só de manhã, e o plano é o dia todo) não confirma: vai ao dono
    perform public._agenda_comunicar_convites(c_qua, pg_temp.em(c_qua, '10:15'));
    perform pg_temp.saiu(pg_temp.em(c_qua, '10:16'));
    v_t := public.agenda_resposta_da_equipe(pg_temp.fone('Roberto'), 'sim, só de manhã', 'wa-e11v', pg_temp.em(c_qua, '11:00'));
    r := pg_temp.ok(r, 'E11v "sim, só de manhã" com o plano do dia todo não é o SIM: vai ao dono, e o convite segue esperando',
      v_t ->> 'leitura' = 'nao_entendi' and (pg_temp.msg(v_rob, 'convite', c_sex)).estado = 'enfileirada'
      and not exists (select 1 from public.agenda_disponibilidade d where d.payee_id = v_rob and d.situacao = 'confirmada' and d.periodo @> c_sex), v_t::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- a ficha sem a semana (o previsto desligado): "não posso quarta" é o caminho de antes (o dia da ficha)
    perform pg_temp.prepara('desligado', 'desligado', false);
    perform set_config('agenda.hoje', c_qua::text, true);
    perform pg_temp.tique(pg_temp.em(c_qua, '17:00'));
    perform pg_temp.saiu(pg_temp.em(c_qua, '17:01'));
    perform pg_temp.tique(pg_temp.em(c_qua, '19:30'));
    perform pg_temp.saiu(pg_temp.em(c_qua, '19:31'));
    v_t := public.agenda_resposta_da_equipe(pg_temp.fone('Roberto'), 'não posso quarta', 'wa-e11w', pg_temp.em(c_qua, '19:40'));
    r := pg_temp.ok(r, 'E11w à ficha sem a semana (dias nulos), "não posso quarta" é o "não vou" de sempre (o dia da ficha): o P5 não muda isso',
      v_t ->> 'tipo' = 'nao_vou' and (v_t ->> 'dia')::date = c_qui and not (v_t ? 'semana'), v_t::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- a ficha longa (um dublê de agenda_equipe_ficha com 580 letras): o previsto não cabe em 600 e a ficha sai sem ele, inteira, sem dias
    perform pg_temp.prepara('ligado', 'desligado', false);
    perform set_config('agenda.hoje', c_qui::text, true);
    v_ficha := 'Roberto, sexta (13/11): ' || repeat('serviço longo. ', 36) || 'Responde OK se tá certo.';
    execute format($d$create or replace function public.agenda_equipe_ficha(p_payee uuid, p_dia date, p_hoje date) returns jsonb language sql stable as $q$
                        select jsonb_build_object('tem_plano', true, 'texto_ficha', %L::text, 'texto_curto', 'Sexta (13/11): 8h.', 'texto_como_foi', 'Como foi hoje?',
                                                  'texto_confirmar', 'Bom dia.', 'texto_resposta', 'Roberto.', 'os', '[]'::jsonb, 'turnos', '["manha"]'::jsonb) $q$$d$, v_ficha);
    perform public._agenda_rotina_ficha(c_qui, pg_temp.em(c_qui, '19:30'));
    m := pg_temp.msg(v_rob, 'ficha', c_sex);
    r := pg_temp.ok(r, 'E11x a ficha que não comporta o previsto (passaria de 600 letras) sai inteira, sem ele e sem dias',
      m.texto = v_ficha and m.dias is null and char_length(v_ficha) between 550 and 600, char_length(v_ficha)::text || ' ' || coalesce(m.dias::text, 'sem dias'));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$e$;

-- ── E12. Mais cantos (os que a 1ª rodada de mutações achou sem caso) ─────────────────────────────────
do $e$
declare
  r      jsonb := '[]';
  c_ter  constant date := date '2026-11-10';
  c_qua  constant date := date '2026-11-11';
  c_qui  constant date := date '2026-11-12';
  c_sex  constant date := date '2026-11-13';
  v_rob  uuid;
  v_raf  uuid;
  v_a    uuid;
  v_t    jsonb;
  v_s    jsonb;
  v_txt  text;
  m      public.agenda_equipe_mensagens;
  v_cf   text;
  v_curto text;
begin
  if not pg_temp.na_bancada() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'E12 mais cantos', true, 'PULADO: sem agenda_teste.fase7f (rode pela bancada)'));
    return;
  end if;
  v_rob := pg_temp.p('Roberto');
  v_raf := pg_temp.p('Rafael');
  begin
    -- o previsto da quinta guarda o que ele já ouviu fora da semana que vem (o sábado desta semana)
    perform pg_temp.prepara('ligado', 'desligado', false);
    perform set_config('agenda.hoje', c_qui::text, true);
    insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, dedupe_key, dias)
    values (v_rob, c_qua, 'mudanca', 'ligado', 'Roberto, mudou a sua semana: entra sáb 14/11.', pg_temp.em(c_qua, '19:30'), 'enfileirada',
            format('agenda-equipe:mudanca:%s:2026-11-11:19h', v_rob), array[date '2026-11-14', date '2026-11-18', date '2026-11-19']);
    v_s := public._agenda_equipe_semana_da_pessoa(v_rob, c_qui, pg_temp.em(c_qui, '19:30'));
    r := pg_temp.ok(r, 'E12a o previsto da quinta troca só a semana que vem: o sáb 14/11 que ele ouviu continua no que ele terá ouvido',
      v_s -> 'estado_previsto' ? '2026-11-14' and v_s -> 'estado_previsto' ? '2026-11-18', (v_s -> 'estado_previsto')::text);
    -- a ficha não leva a mudança da semana que já saiu hoje (a das 19:30 sozinha)
    perform set_config('agenda.hoje', c_qua::text, true);
    perform public._agenda_rotina_ficha(c_qua, pg_temp.em(c_qua, '19:45'));
    m := pg_temp.msg(v_rob, 'ficha', c_qui);
    r := pg_temp.ok(r, 'E12b a ficha não repete a mudança da semana que já saiu hoje (a das 19:30)', m.texto is not null and m.texto not like '%Na semana:%', m.texto);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- o "como foi" longo (um dublê de agenda_equipe_ficha): a semana não cabe, e ele sai sem ela, sem dias
    perform pg_temp.prepara('ligado', 'desligado', false);
    perform set_config('agenda.hoje', c_qui::text, true);
    v_cf := 'Como foi hoje? ' || repeat('etapa longa. ', 20);
    v_curto := 'Sexta (13/11): ' || repeat('motorhome longe. ', 16);
    execute format($d$create or replace function public.agenda_equipe_ficha(p_payee uuid, p_dia date, p_hoje date) returns jsonb language sql stable as $q$
                        select jsonb_build_object('tem_plano', true, 'texto_ficha', 'Roberto, ficha.', 'texto_curto', %L::text, 'texto_como_foi', %L::text,
                                                  'texto_confirmar', 'Bom dia.', 'texto_resposta', 'Roberto.', 'os', '[]'::jsonb, 'turnos', '["manha"]'::jsonb) $q$$d$,
                   v_curto, v_cf);
    insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, dedupe_key)
    values (v_rob, c_qui, 'confirmar', 'ligado', 'Bom dia, Roberto. Tá confirmado?', pg_temp.em(c_qui, '07:45'), 'enfileirada', format('agenda-equipe:confirmar:%s:2026-11-12', v_rob));
    perform public._agenda_rotina_como_foi(c_qui, pg_temp.em(c_qui, '17:00'));
    m := pg_temp.msg(v_rob, 'como_foi', c_qui);
    r := pg_temp.ok(r, 'E12c o "como foi" com a ficha de amanhã que não comporta a semana (passaria de 600 letras) sai como antes: sem ela, sem dias',
      m.texto = v_cf || ' ' || v_curto and m.leva_ficha_de = c_sex and m.dias is null,
      char_length(v_cf || ' ' || v_curto)::text || ' ' || coalesce(m.dias::text, 'sem dias') || ' ' || coalesce(left(m.texto, 60), '-'));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- a resposta depois do prazo (o convite ainda na fila, antes de o passo vencer) não é o SIM
    perform pg_temp.prepara('desligado', 'ligado', false);
    perform set_config('agenda.hoje', c_qua::text, true);
    perform public._agenda_comunicar_convites(c_qua, pg_temp.em(c_qua, '10:15'));
    perform pg_temp.saiu(pg_temp.em(c_qua, '10:16'));
    v_t := public.agenda_resposta_da_equipe(pg_temp.fone('Roberto'), 'sim', 'wa-e12d', pg_temp.em(c_qui, '19:35'));
    r := pg_temp.ok(r, 'E12d o "sim" depois do prazo (qui 19:35; o prazo era 19:30) não confirma o convite: ele segue sem SIM e o passo dos vencidos o fecha',
      coalesce(v_t ->> 'leitura', '') <> 'sim' and (pg_temp.msg(v_rob, 'convite', c_sex)).estado = 'enfileirada'
      and not exists (select 1 from public.agenda_disponibilidade d where d.payee_id = v_rob and d.situacao = 'confirmada' and d.periodo @> c_sex), v_t::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- à ficha que levou a semana, "sexta não vou" (o dia da própria ficha) é o "não vou" de sempre
    perform pg_temp.prepara('ligado', 'desligado', false);
    perform set_config('agenda.hoje', c_qui::text, true);
    perform pg_temp.tique(pg_temp.em(c_qui, '17:00'));
    perform pg_temp.saiu(pg_temp.em(c_qui, '17:01'));
    perform pg_temp.tique(pg_temp.em(c_qui, '19:30'));
    perform pg_temp.saiu(pg_temp.em(c_qui, '19:31'));
    v_t := public.agenda_resposta_da_equipe(pg_temp.fone('Roberto'), 'sexta não vou', 'wa-e12e', pg_temp.em(c_qui, '19:40'));
    r := pg_temp.ok(r, 'E12e à ficha que levou a semana, "sexta não vou" (o dia dela) é o "não vou" da sexta, como antes',
      v_t ->> 'tipo' = 'nao_vou' and (v_t ->> 'dia')::date = c_sex and not (v_t ? 'semana'), v_t::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- o serviço sem outro dia: "mudou", não "mudou de dia"
    perform pg_temp.prepara('ligado', 'desligado', false);
    v_a := pg_temp.e3_cenario();
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_em = pg_temp.em(c_ter, '19:41'), cancelada_motivo = 'cliente'
     where id = md5('f7f:p5:flavio:20')::uuid;
    perform public._agenda_equipe_mudanca_na_hora(v_a, c_ter, pg_temp.em(c_ter, '19:45'));
    m := pg_temp.msg(v_rob, 'mudanca', c_qua);
    r := pg_temp.ok(r, 'E12f sem outro dia do serviço no plano, a mensagem diz que mudou, não que "mudou de dia"',
      m.texto = 'Roberto, amanhã (qua 11/11) não precisa vir: o serviço do Flávio mudou. Desculpa o aviso em cima.', m.texto);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- o dia que não é novo (marcado há mais de 72 h) não vira a exceção do prazo; o dia novo com a ficha já mandada não vira convite
    perform pg_temp.prepara('desligado', 'ligado', false);
    perform set_config('agenda.hoje', c_qua::text, true);
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, duracao_fonte, criado_em)
    values (md5('f7f:p5:rafael:13:ficha')::uuid, pg_temp.os('305'), v_raf, c_sex, 'manha', 'turno', 'execucao', 'publicada', 'motor', pg_temp.em(c_qua, '10:00'), 'orcamento',
            pg_temp.em(c_qua, '10:00'));
    insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, dedupe_key)
    values (v_raf, c_sex, 'ficha', 'ligado', 'Rafael, sexta (13/11): 8h na lancha do Giancarlo. Responde OK se tá certo.', pg_temp.em(c_qua, '10:05'), 'enfileirada',
            format('agenda-equipe:ficha:%s:2026-11-13', v_raf));
    v_t := public._agenda_comunicar_convites(c_qua, pg_temp.em(c_qua, '10:15'));
    r := pg_temp.ok(r, 'E12g a qua 11/11 do Roberto (marcada em 05/11, mais de 72 h antes) não vira a exceção do prazo; a sex 13/11 do Rafael, com a ficha já mandada, não vira convite',
      not exists (select 1 from public.agenda_acoes a where a.tipo = 'equipe' and a.depois ->> 'motivo' = 'convite_sem_prazo')
      and not exists (select 1 from public.agenda_equipe_mensagens x where x.payee_id = v_raf and x.tipo = 'convite'), v_t::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- o dono nunca é convidado, mesmo posto na rotina, com telefone e com dia novo (ele não é declarado: o _agenda_tecnico_declarado não o cobre)
    perform pg_temp.prepara('desligado', 'ligado', false);
    perform set_config('agenda.hoje', c_qua::text, true);
    insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por) values (public._agenda_dono(null), true, 'dono')
    on conflict (payee_id) do update set recebe_rotina = true, parou_em = null, parou_motivo = null;
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, duracao_fonte, criado_em)
    values (md5('f7f:p5:dono:13')::uuid, pg_temp.os('305'), public._agenda_dono(null), c_sex, 'tarde', 'turno', 'execucao', 'publicada', 'motor', pg_temp.em(c_qua, '10:00'),
            'orcamento', pg_temp.em(c_qua, '10:00'));
    v_t := public._agenda_comunicar_convites(c_qua, pg_temp.em(c_qua, '10:15'));
    r := pg_temp.ok(r, 'E12h o dono (o Gustavo, com telefone e sem dia declarado), posto na rotina com a sex 13/11 nova, não é convidado; o Roberto, no mesmo passo, é',
      public._agenda_equipe_tem_telefone(public._agenda_dono(null)) and not public._agenda_tecnico_declarado(public._agenda_dono(null), c_sex)
      and not exists (select 1 from public.agenda_equipe_mensagens x where x.payee_id = public._agenda_dono(null) and x.tipo = 'convite')
      and exists (select 1 from public.agenda_equipe_mensagens x where x.payee_id = v_rob and x.tipo = 'convite' and x.dia = c_sex), v_t::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$e$;

select teste, ok, detalhe from _resultado order by ok, teste;
rollback;
