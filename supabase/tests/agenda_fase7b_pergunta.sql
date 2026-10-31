-- Prova da pergunta da semana da Agenda de Produção, Fase 7b (pacote P3): a pergunta à equipe com dias fixos e telefone, a do dono
-- só quando faz diferença, as respostas, o cadastro pela régua de 30/10 (a chamada com o telefone dentro, o contato de quem vem sob
-- demanda, a regra d14 só de quem tem dias fixos, o "2) Não" gravado) e a linha (n) da equipe no fechamento (migration
-- 20261101100200).
-- bancada: depende de 20261101100200
--
--   Q1  a gramática da resposta (_agenda_ler_dias_da_equipe): a tabela da §8.3, byte a byte (+ o plural e o "ter que")
--   Q2  a pergunta na qui 16:45: em sombra registrada com ":sombra"; em ligado enfileirada; com o "como foi" e a ficha previstos,
--       adiada e mandada na sex; nunca no domingo; nunca depois de pode_perguntar_ate; nem antes de equipe_hora_dias; a 1ª em ligado
--       espera a chamada; a elegibilidade do R4.2(a) (Alex sem telefone, Mateus sob demanda na lista e Roberto parado não recebem)
--   Q3  as respostas: "seg ter qui" depois do "como foi" vai à semana; "ok" depois do "como foi" vai ao "como foi"; "ok" com a
--       pergunta por último = igual; "segunda não posso" = não entendi, nada de indisponível no dia da ficha (A3); "não vou amanhã" =
--       o "não vou" de antes, no dia da ficha; o 2º "não entendi" vai ao dono (equipe_resposta)
--   Q4  _agenda_rotina_sem_resposta não fecha a pergunta da semana (A2)
--   Q5  o fechamento da semana: sem_resposta, a dias_semana vencida, o resumo byte a byte (sem resposta e conflito), idempotente
--   Q6  a dias_semana do dono: sem motivo não nasce; com a do lote aberta não nasce pelo dono_sem_padrao; o dono_sem_padrao com as
--       opções; a 2 cria o padrão do dono e o motivo some; a 3 prende só a semana e o motivo volta; a 1 só responde; a semente;
--       {sempre} byte a byte; dono_dias_semanal false; com quem chamar ligado espera o diário até 17:15
--   Q7  o cadastro: a chamada byte a byte (o exemplo do R4.1-2), o telefone dentro dela, as opções; o telefone sozinho e fechado
--       quando aparece; a d14 (Rafael entra; Roberto, João e Mickael nunca; o *desfaz* para); o contato de quem vem sob demanda (o
--       Mateus nunca pela d14; o "2) Não" grava a linha parada e nada volta; o "1) Ponho" e o *desfaz*); no máximo 3 abertas; o prazo
--       da chamada depois de vista
--   Q8  o foco equipe byte a byte com a equipe real (ligado e em teste)
--   Q9  com os modos desligados: nada (a rodada, o registro, o foco, as linhas do fechamento e a chamada da 7a, byte a byte)
--   Q10 em sombra a resposta não é consumida e nada é gravado
--   Q11 a linha (n): perda 75 e vaga própria com a (e) cheia; conta como mostrada (pergunta_ids) e ganha o prazo; a dias_semana e o
--       telefone na mesma linha, curtos; a (e) não as repete; sem nenhuma aberta, a saída de antes; a espera da chamada para em 7 dias
--   Q12 as cópias: tirados os blocos "-- FASE 7b:", o corpo de cada recriada é o da origem, com o número de blocos
--   Q13 as portas: as novas (invoker/definer, volatilidade, grants), o anon 42501, o foco equipe para authenticated e service_role,
--       as recriadas com as portas de antes
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7b_pergunta.sql
--   Seguro em produção: termina em ROLLBACK. Q1 e Q13 rodam em qualquer banco; o resto usa as fixtures e as migrations como texto e só
--   roda na bancada (fora dela sai PULADO).
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
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
-- O corpo de uma função numa migration (o texto entre "as $function$" e "$function$") e a definição inteira.
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  if position(format('create or replace function public.%s(', p_nome) in v) = 0 then return ''; end if;
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'\nas $function$' in v) + length(E'\nas $function$'));
  return left(v, position('$function$' in v) - 1);
end $f$;
create function pg_temp.inteira(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  return left(v, position(E'\n$function$;' in v) + length(E'\n$function$;') - 1);
end $f$;
-- O texto sem os blocos "-- FASE 7b: … -- FASE 7b: fim" (as linhas de abrir e de fechar saem junto).
create function pg_temp.sem_7b(p text) returns text language sql immutable as $f$
  select array_to_string(array(
           select l from (select l, o, sum(case when l ~ '^\s*-- FASE 7b:' and l !~ '-- FASE 7b: fim' then 1
                                                when l ~ '^\s*-- FASE 7b: fim' then -1 else 0 end)
                                       over (order by o rows between unbounded preceding and current row) as dentro,
                                 l ~ '^\s*-- FASE 7b: fim' as fecha
                            from unnest(string_to_array(replace(p, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o)) x
            where dentro = 0 and not fecha order by o), E'\n')
$f$;
-- p_sql (que devolve um valor) como o papel p_papel: o resultado em texto, ou 'erro <estado>: <mensagem>'.
create function pg_temp.como(p_papel text, p_sql text) returns text language plpgsql as $f$
declare
  v text;
begin
  perform set_config('request.jwt.claims', json_build_object('role', p_papel)::text, true);
  begin
    execute format('set local role %I', p_papel);
    execute p_sql into v;
    reset role;
  exception when others then
    v := 'erro ' || sqlstate || ': ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;

-- ── Q1. A gramática da resposta (sem fixture) ──────────────────────────────────────────────────────────────────
with c(o, t, espera) as (values
  (1, 'seg ter qui', 'dias:1,2,4'), (2, 'segunda, terça e quinta', 'dias:1,2,4'), (3, 'de segunda a quarta', 'dias:1,2,3'),
  (4, 'seg a sex', 'dias:1,2,3,4,5'), (5, 'todos', 'dias:1,2,3,4,5'), (6, 'todos os dias', 'dias:1,2,3,4,5'),
  (7, 'a semana toda', 'dias:1,2,3,4,5'), (8, 'todos menos quarta', 'dias:1,2,4,5'), (9, 'só segunda', 'dias:1'),
  (10, 'seg a sáb', 'dias:1,2,3,4,5+sab'), (11, 'sábado de manhã também, e terça', 'dias:2+sab'), (12, 'nenhum', 'nenhum'),
  (13, 'nenhum dia', 'nenhum'), (14, 'essa semana não posso', 'nenhum'), (15, 'não posso nessa semana', 'nenhum'),
  (16, 'igual', 'igual'), (17, 'o mesmo', 'igual'), (18, 'pode manter', 'igual'), (19, 'ok', 'igual'), (20, 'sim', 'igual'),
  (21, 'segunda não posso', 'nao_entendi'), (22, 'não posso quarta', 'nao_entendi'), (23, 'terça só de manhã', 'nao_entendi'),
  (24, 'seg à tarde', 'nao_entendi'), (25, 'vou ver e te falo', 'nao_entendi'), (26, '?', 'nao_entendi'), (27, '', 'nao_entendi'),
  (28, 'domingo', 'nao_entendi'), (29, 'Segunda a sexta', 'dias:1,2,3,4,5'), (30, 'terças e quintas', 'dias:2,4'),
  (31, 'qua, qui e sex', 'dias:3,4,5'), (32, 'semana de folga', 'nenhum'), (33, 'não vou poder', 'nenhum'),
  (34, 'Sábado', 'dias+sab'), (35, 'os mesmos dias', 'igual'), (36, 'beleza', 'igual'), (37, 'não vou amanhã', 'nao_entendi'),
  (38, 'seg qua e sábado de manhã', 'dias:1,3+sab'), (39, 'mesma coisa', 'igual'), (40, 'vou ter que ver', 'nao_entendi'),
  (41, 'terças só à tarde', 'nao_entendi'))
, l as (
  select c.o, c.t, c.espera,
         (r ->> 'tipo') || coalesce(':' || (select string_agg(x, ',') from jsonb_array_elements_text(r -> 'dias') x), '')
         || case when (r ->> 'sabado')::boolean then '+sab' else '' end as leu
    from c cross join lateral (select public._agenda_ler_dias_da_equipe(c.t) as r) y)
insert into _resultado
select 'Q1 _agenda_ler_dias_da_equipe: as 41 frases (a tabela da §8.3 + o plural, o "ter que" e o turno com plural)',
       bool_and(l.leu = l.espera) and count(*) = 41,
       string_agg(format('"%s" leu %s (era %s)', l.t, l.leu, l.espera), '; ' order by l.o) filter (where l.leu <> l.espera)
  from l;

-- ── As fixtures e as definições de antes (uma vez; cada caso abaixo roda numa subtransação desfeita) ─────────────
-- A base é a equipe REAL de produção (agenda_teste.fase7b_equipe = 'real': o Alex e o dono); quem precisa de Mateus, Rafael e Bruno
-- os carrega dentro do caso (pg_temp.equipe_toda).
do $carga$
declare
  v_m text;
begin
  if coalesce(current_setting('agenda_teste.fase7b', true), '') = '' or coalesce(current_setting('agenda_teste.fase7a', true), '') = ''
     or coalesce(current_setting('agenda_teste.replay2910', true), '') = '' then
    return;
  end if;
  perform set_config('agenda_teste.fase7b_equipe', 'real', true);
  execute current_setting('agenda_teste.fase7b');
  perform set_config('agenda_teste.fase7b_equipe', '', true);
  v_m := coalesce(current_setting('agenda_teste.mig_acompanhamento_fase3', true), '');
  if v_m <> '' then
    execute replace(pg_temp.inteira(v_m, '_agenda_ver_equipe'), 'create or replace function public._agenda_ver_equipe(',
                    'create function pg_temp.ver_equipe_antes(');
  end if;
  v_m := coalesce(current_setting('agenda_teste.mig_correcao2_fase7a', true), '');
  if v_m <> '' then
    execute replace(pg_temp.inteira(v_m, '_agenda_linhas_do_fechamento'), 'create or replace function public._agenda_linhas_do_fechamento(',
                    'create function pg_temp.linhas_antes(');
  end if;
end
$carga$;

create function pg_temp.carregada() returns boolean language sql stable as $f$
  select exists (select 1 from public.agenda_equipe_contato c join public.payees py on py.id = c.payee_id
                  where py.name = 'Alex' and c.incluido_por = 'dono')
     and to_regprocedure('pg_temp.ver_equipe_antes(date)') is not null
     and to_regprocedure('pg_temp.linhas_antes(date)') is not null
$f$;
create function pg_temp.adm() returns uuid language sql stable as $f$
  select id from public.app_users where role = 'admin' and active order by id limit 1
$f$;
create function pg_temp.pessoa(p_nome text) returns uuid language sql stable as $f$
  select id from public.payees where name = p_nome and active order by id limit 1
$f$;
create function pg_temp.modos(p_dias text, p_cad text) returns void language sql as $f$
  update public.agenda_config set modo_dias = p_dias, modo_cadastro = p_cad where id
$f$;
create function pg_temp.rodar(p_dia date, p_hora text) returns jsonb language plpgsql as $f$
begin
  return public.agenda_equipe_semana(p_dia, pg_temp.em(p_dia, p_hora));
end $f$;
-- Mateus, Rafael e Bruno (a fixture sem a variante real; o que já está fica)
create function pg_temp.equipe_toda() returns void language plpgsql as $f$
begin
  perform set_config('agenda_teste.fase7b_equipe', '', true);
  execute current_setting('agenda_teste.fase7b');
end $f$;
-- a resposta da pessoa pelo WhatsApp (o telefone dela)
create function pg_temp.responde(p_nome text, p_texto text, p_wa text, p_dia date, p_hora text) returns jsonb language plpgsql as $f$
begin
  return public.agenda_resposta_da_equipe((select py.phone from public.payees py where py.name = p_nome and py.active limit 1), p_texto, p_wa,
                                          pg_temp.em(p_dia, p_hora));
end $f$;
-- as linhas vivas da semana presa: "dd/mm=situacao"
create function pg_temp.semana(p_payee uuid, p_seg date) returns text language sql stable as $f$
  select coalesce(string_agg(to_char(lower(d.periodo), 'DD/MM') || '=' || d.situacao, ' ' order by lower(d.periodo), d.turno), '-')
    from public.agenda_disponibilidade d
   where d.payee_id = p_payee and d.substituida_em is null and d.semana_dita = p_seg
$f$;
-- as mensagens dias: "Nome:modo:estado"
create function pg_temp.dias_msgs() returns text language sql stable as $f$
  select coalesce(string_agg(py.name || ':' || m.modo || ':' || m.estado || ':' || to_char(m.dia, 'DD/MM'), ' ' order by py.name, m.dia), '-')
    from public.agenda_equipe_mensagens m join public.payees py on py.id = m.payee_id where m.tipo = 'dias'
$f$;
-- o texto das perguntas abertas cuja chave casa
create function pg_temp.aberta(p_like text) returns text language sql stable as $f$
  select string_agg(q.texto, ' | ' order by q.criada_em, q.id) from public.agenda_perguntas q where q.estado = 'aberta' and q.chave like p_like
$f$;
-- um meio-dia vigente (não reserva) da pessoa
create function pg_temp.aloc(p_payee uuid, p_dia date) returns void language sql as $f$
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
  select so.id, p_payee, p_dia, 'manha', 'turno', 'execucao', 'publicada', 'motor', now()
    from public.service_orders so where so.service_order_number = 'OS-00074'
$f$;

-- ── Q2. A pergunta da semana à equipe ──────────────────────────────────────────────────────────────────────────
do $q2$
declare
  v_res jsonb := '[]'::jsonb;
  v     jsonb;
  a     text;
  b     text;
  v_raf uuid;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('Q2 (a pergunta da semana)', true, 'PULADO: sem as fixtures da 7b e as migrations como texto (rode pela bancada)');
    return;
  end if;
  -- em sombra: só o Rafael (rotina, dias fixos, telefone); o Alex sem telefone, o Mateus sob demanda na lista e o Roberto parado não
  begin
    perform pg_temp.equipe_toda();
    v_raf := pg_temp.pessoa('Rafael');
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, criado_em)
    select pg_temp.pessoa('Mateus'), daterange(d, d, '[]'), 'disponivel', 'dono', 'Você disse que vem (sob demanda)', pg_temp.em('2026-11-05', '10:00')
      from unnest(array[date '2026-11-11', date '2026-11-12']) d;
    insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por, incluido_em)
    values (pg_temp.pessoa('Mateus'), true, 'dono', pg_temp.em('2026-11-05', '10:00'));
    -- o Roberto com a semente de volta (dias fixos, telefone, perfil), mas parado na rotina
    update public.agenda_disponibilidade set substituida_em = null
     where payee_id = pg_temp.pessoa('Roberto') and origem = 'historico';
    perform pg_temp.modos('sombra', 'desligado');
    v := pg_temp.rodar('2026-11-05', '16:45');
    a := pg_temp.dias_msgs();
    b := (select m.dedupe_key from public.agenda_equipe_mensagens m where m.tipo = 'dias');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q2a em sombra, qui 05/11 16:45: só o Rafael (na rotina, com dias fixos e telefone) ganha a pergunta da semana de 16/11, registrada com ":sombra"; o Alex (sem telefone), o Mateus (sob demanda, na lista) e o Roberto (parado) não — e nada fica registrado deles',
    a = 'Rafael:sombra:registrada:16/11' and b = format('agenda-equipe:dias:%s:2026-11-16:sombra', v_raf), a || ' / ' || coalesce(b, '-'));

  -- em ligado: enfileirada, a linha na fila com a chave dela; o texto da §6.1
  begin
    perform pg_temp.equipe_toda();
    v_raf := pg_temp.pessoa('Rafael');
    perform pg_temp.modos('ligado', 'desligado');
    v := pg_temp.rodar('2026-11-05', '16:45');
    a := pg_temp.dias_msgs();
    b := (select m.texto from public.agenda_equipe_mensagens m where m.tipo = 'dias');
    v := v || jsonb_build_object('fila', exists (select 1 from public.whatsapp_send_queue q
                                                  where q.dedupe_key = format('agenda-equipe:dias:%s:2026-11-16', v_raf)));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q2b em ligado: enfileirada, na fila com a chave agenda-equipe:dias:<Rafael>:2026-11-16, o texto da §6.1 byte a byte',
    a = 'Rafael:ligado:enfileirada:16/11' and (v ->> 'fila')::boolean
    and b = 'Oi, Rafael! Para a semana de 16/11 a 20/11, quais dias você pode vir? Na última você disse: de seg a sex. Se mudou, mande só os dias (ex.: seg ter qui) ou "nenhum". Se está igual, não precisa responder.',
    a || ' / ' || coalesce(b, '-'));

  -- com o "como foi" de hoje e a ficha de amanhã previstos, o teto (2) está cheio: adiada; na sex 06/11 sai
  begin
    perform pg_temp.equipe_toda();
    v_raf := pg_temp.pessoa('Rafael');
    perform pg_temp.aloc(v_raf, date '2026-11-05');
    perform pg_temp.aloc(v_raf, date '2026-11-06');
    perform pg_temp.modos('ligado', 'desligado');
    b := public._agenda_equipe_previstas_hoje(v_raf, date '2026-11-05', pg_temp.em('2026-11-05', '16:45'))::text;
    v := pg_temp.rodar('2026-11-05', '16:45');
    a := pg_temp.dias_msgs() || ' adiada=' || coalesce(v #>> '{contagens,perguntar,adiada}', '-');
    b := b || '/' || public._agenda_equipe_previstas_hoje(v_raf, date '2026-11-06', pg_temp.em('2026-11-06', '16:45'))::text;
    v := pg_temp.rodar('2026-11-06', '16:45');
    a := a || ' | sex: ' || pg_temp.dias_msgs();
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q2c com o "como foi" de hoje e a ficha de amanhã previstos (_agenda_equipe_previstas_hoje = 2), a pergunta é adiada; na sex 06/11 (só o "como foi" previsto, 1) ela sai',
    a = '- adiada=1 | sex: Rafael:ligado:enfileirada:16/11' and b = '2/1', a || ' previstas ' || b);

  -- nunca no domingo, nunca depois de pode_perguntar_ate (ter 10/11), nunca antes de equipe_hora_dias
  begin
    perform pg_temp.equipe_toda();
    perform pg_temp.modos('ligado', 'desligado');
    v := pg_temp.rodar('2026-11-08', '16:45');
    a := pg_temp.dias_msgs();
    v := pg_temp.rodar('2026-11-11', '16:45');
    a := a || '/' || pg_temp.dias_msgs();
    v := pg_temp.rodar('2026-11-05', '16:30');
    a := a || '/' || pg_temp.dias_msgs();
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q2d nada no domingo 08/11, nada na qua 11/11 (depois de pode_perguntar_ate, ter 10/11), nada às 16:30 (antes de equipe_hora_dias)',
    a = '-/-/-', a);

  -- com o cadastro ligado, a 1ª pergunta em ligado espera a chamada (nasce no mesmo tique); respondida, sai no tique seguinte
  begin
    perform pg_temp.equipe_toda();
    perform pg_temp.modos('ligado', 'ligado');
    v := pg_temp.rodar('2026-11-05', '16:45');
    a := pg_temp.dias_msgs() || ' espera=' || coalesce(v #>> '{contagens,perguntar,espera_chamada}', '-');
    update public.agenda_perguntas set estado = 'respondida', opcao_escolhida = 1, respondida_em = pg_temp.em('2026-11-05', '16:50')
     where chave like 'equipe_cadastro:chamada:%' and estado = 'aberta';
    v := pg_temp.rodar('2026-11-05', '17:00');
    a := a || ' | ' || pg_temp.dias_msgs();
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q2e com modo_cadastro ligado, a 1ª pergunta em ligado espera a chamada respondida (16:45 espera; respondida, 17:00 sai)',
    a = '- espera=true | Rafael:ligado:enfileirada:16/11', a);
  perform pg_temp.gravar(v_res);
end
$q2$;

-- ── Q3, Q4, Q10. As respostas ───────────────────────────────────────────────────────────────────────────────────
do $q3$
declare
  v_res jsonb := '[]'::jsonb;
  v     jsonb;
  a     text;
  b     text;
  v_raf uuid;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('Q3, Q4, Q10 (as respostas)', true, 'PULADO: sem as fixtures da 7b e as migrations como texto (rode pela bancada)');
    return;
  end if;
  -- "seg ter qui" depois do "como foi": vai à semana (a semana presa, o padrão, o "Anotei")
  begin
    perform pg_temp.equipe_toda();
    v_raf := pg_temp.pessoa('Rafael');
    perform pg_temp.modos('ligado', 'desligado');
    v := pg_temp.rodar('2026-11-05', '16:45');
    perform public._agenda_equipe_registrar(v_raf, date '2026-11-05', 'como_foi', 'Como foi hoje, Rafael?', pg_temp.em('2026-11-05', '17:00'));
    v := pg_temp.responde('Rafael', 'seg ter qui', 'WA-Q3a', '2026-11-05', '17:30');
    a := (v ->> 'tipo') || '/' || (v ->> 'consumiu') || '/' || pg_temp.semana(v_raf, date '2026-11-16') || '/'
         || (select string_agg(d.dias_semana::text || ':' || d.origem, ' ') from public.agenda_disponibilidade d
              where d.payee_id = v_raf and d.substituida_em is null and d.dias_semana is not null)
         || '/' || (select m.estado from public.agenda_equipe_mensagens m where m.payee_id = v_raf and m.tipo = 'como_foi');
    b := v ->> 'resposta';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q3a "seg ter qui" depois do "como foi" vai à semana: a semana de 16/11 presa (sex 20/11 é feriado), o padrão do Rafael passa a {1,2,4}, "Anotei: na semana de 16/11 você pode seg, ter e qui. Obrigado!"; o "como foi" continua esperando',
    a = 'dias/true/16/11=disponivel 17/11=disponivel 18/11=indisponivel 19/11=disponivel/{1,2,4}:diarista/enfileirada'
    and b = 'Anotei: na semana de 16/11 você pode seg, ter e qui. Obrigado!', a || ' / ' || coalesce(b, '-'));

  -- "ok" depois do "como foi" é do "como foi"
  begin
    perform pg_temp.equipe_toda();
    v_raf := pg_temp.pessoa('Rafael');
    perform pg_temp.modos('ligado', 'desligado');
    v := pg_temp.rodar('2026-11-05', '16:45');
    perform public._agenda_equipe_registrar(v_raf, date '2026-11-05', 'como_foi', 'Como foi hoje, Rafael?', pg_temp.em('2026-11-05', '17:00'));
    v := pg_temp.responde('Rafael', 'ok', 'WA-Q3b', '2026-11-05', '17:30');
    a := coalesce(v ->> 'tipo', '-') || '/' || (select m.estado from public.agenda_equipe_mensagens m where m.payee_id = v_raf and m.tipo = 'dias')
         || '/' || (select m.estado from public.agenda_equipe_mensagens m where m.payee_id = v_raf and m.tipo = 'como_foi');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q3b "ok" depois do "como foi" vai ao "como foi" (respondido); a pergunta da semana continua aberta',
    a = 'ok/enfileirada/respondida', a);

  -- "ok" com a pergunta da semana por último = igual: nada gravado
  begin
    perform pg_temp.equipe_toda();
    v_raf := pg_temp.pessoa('Rafael');
    perform pg_temp.modos('ligado', 'desligado');
    v := pg_temp.rodar('2026-11-05', '16:45');
    v := pg_temp.responde('Rafael', 'ok', 'WA-Q3c', '2026-11-05', '17:00');
    a := (v ->> 'leitura') || '/' || pg_temp.semana(v_raf, date '2026-11-16') || '/'
         || (select m.estado from public.agenda_equipe_mensagens m where m.payee_id = v_raf and m.tipo = 'dias');
    b := v ->> 'resposta';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q3c "ok" com a pergunta da semana por último = igual: nada gravado, "Anotei: semana de 16/11 igual (de seg a sex). Obrigado!"',
    a = 'igual/-/respondida' and b = 'Anotei: semana de 16/11 igual (de seg a sex). Obrigado!', a || ' / ' || coalesce(b, '-'));

  -- "segunda não posso" (a ficha de amanhã mandada antes, a pergunta da semana por último): não entendi — nada de indisponível (A3)
  begin
    perform pg_temp.equipe_toda();
    v_raf := pg_temp.pessoa('Rafael');
    perform pg_temp.modos('ligado', 'desligado');
    perform public._agenda_equipe_registrar(v_raf, date '2026-11-06', 'ficha', 'Amanhã, sex 06/11: Lenine, o dia todo.', pg_temp.em('2026-11-05', '16:00'));
    v := pg_temp.rodar('2026-11-05', '16:45');
    v := pg_temp.responde('Rafael', 'segunda não posso', 'WA-Q3d', '2026-11-05', '17:00');
    a := (v ->> 'leitura') || '/' || (v ->> 'vez') || '/'
         || (select count(*) from public.agenda_disponibilidade d where d.payee_id = v_raf and d.situacao = 'indisponivel' and d.substituida_em is null)::text
         || '/' || (select m.estado from public.agenda_equipe_mensagens m where m.payee_id = v_raf and m.tipo = 'ficha');
    b := v ->> 'resposta';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q3d "segunda não posso" com a pergunta da semana por último (a ficha de sex 06/11 antes): não entendi (1ª vez), nenhuma linha indisponível, a ficha não é respondida (A3)',
    a = 'nao_entendi/1/0/enfileirada'
    and b = 'Não entendi os dias da semana de 16/11. Mande só os dias, assim: seg ter qui (ou "nenhum").', a || ' / ' || coalesce(b, '-'));

  -- "não vou amanhã": o "não vou" de antes, no dia da ficha (sex 06/11, não a segunda da semana)
  begin
    perform pg_temp.equipe_toda();
    v_raf := pg_temp.pessoa('Rafael');
    perform pg_temp.modos('ligado', 'desligado');
    perform public._agenda_equipe_registrar(v_raf, date '2026-11-06', 'ficha', 'Amanhã, sex 06/11: Lenine, o dia todo.', pg_temp.em('2026-11-05', '16:00'));
    v := pg_temp.rodar('2026-11-05', '16:45');
    v := pg_temp.responde('Rafael', 'não vou amanhã', 'WA-Q3e', '2026-11-05', '17:00');
    a := (v ->> 'tipo') || '/' || (v ->> 'dia') || '/'
         || (select string_agg(to_char(lower(d.periodo), 'DD/MM'), ' ') from public.agenda_disponibilidade d
              where d.payee_id = v_raf and d.situacao = 'indisponivel' and d.substituida_em is null and d.semana_dita is null)
         || '/' || (select m.estado from public.agenda_equipe_mensagens m where m.payee_id = v_raf and m.tipo = 'dias');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q3e "não vou amanhã" é o "não vou" de antes, no dia da ficha (06/11); a pergunta da semana continua aberta',
    a = 'nao_vou/2026-11-06/06/11/enfileirada', a);

  -- o 2º "não entendi" vai ao dono (equipe_resposta) e a mensagem fica respondida
  begin
    perform pg_temp.equipe_toda();
    v_raf := pg_temp.pessoa('Rafael');
    perform pg_temp.modos('ligado', 'desligado');
    v := pg_temp.rodar('2026-11-05', '16:45');
    v := pg_temp.responde('Rafael', 'vou ver e te falo', 'WA-Q3f1', '2026-11-05', '17:00');
    a := (v ->> 'vez');
    v := pg_temp.responde('Rafael', 'vou ver e te falo', 'WA-Q3f2', '2026-11-05', '17:10');
    a := a || '/' || (v ->> 'vez') || '/' || (select m.estado from public.agenda_equipe_mensagens m where m.payee_id = v_raf and m.tipo = 'dias');
    b := pg_temp.aberta(format('equipe_resposta:%s:2026-11-16:dias', v_raf));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q3f o 2º "não entendi" na semana: a pergunta equipe_resposta ao dono (o texto da §6.2) e a mensagem respondida',
    a = '1/2/respondida'
    and b = 'Rafael respondeu "vou ver e te falo" à pergunta dos dias da semana de 16/11, e eu não entendi. Diga os dias dele (ex.: Rafael vem seg e ter na semana de 16/11).',
    a || ' / ' || coalesce(b, '-'));

  -- Q4: _agenda_rotina_sem_resposta não fecha a pergunta da semana (a ficha das 16:00 fecha)
  begin
    perform pg_temp.equipe_toda();
    v_raf := pg_temp.pessoa('Rafael');
    perform pg_temp.modos('ligado', 'desligado');
    perform public._agenda_equipe_registrar(v_raf, date '2026-11-06', 'ficha', 'Amanhã, sex 06/11: Lenine, o dia todo.', pg_temp.em('2026-11-05', '16:00'));
    v := pg_temp.rodar('2026-11-05', '16:45');
    v := public._agenda_rotina_sem_resposta(date '2026-11-06', pg_temp.em('2026-11-06', '08:00'));
    a := (select string_agg(m.tipo || '=' || m.estado, ' ' order by m.tipo) from public.agenda_equipe_mensagens m where m.payee_id = v_raf);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q4 _agenda_rotina_sem_resposta (sex 08:00, 14 h depois): a ficha vira sem_resposta, a pergunta da semana continua enfileirada (A2)',
    a = 'dias=enfileirada ficha=sem_resposta', a);

  -- Q10: em sombra a resposta não é consumida e nada é gravado
  begin
    perform pg_temp.equipe_toda();
    v_raf := pg_temp.pessoa('Rafael');
    perform pg_temp.modos('sombra', 'desligado');
    v := pg_temp.rodar('2026-11-05', '16:45');
    v := pg_temp.responde('Rafael', 'seg ter qui', 'WA-Q10', '2026-11-05', '17:30');
    a := coalesce(v ->> 'consumiu', '-') || '/' || pg_temp.semana(v_raf, date '2026-11-16') || '/' || pg_temp.dias_msgs();
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q10 em sombra: a resposta "seg ter qui" não é consumida, nada é gravado e a mensagem continua só registrada',
    a = 'false/-/Rafael:sombra:registrada:16/11', a);
  perform pg_temp.gravar(v_res);
end
$q3$;

-- ── Q5. O fechamento da semana ──────────────────────────────────────────────────────────────────────────────────
do $q5$
declare
  v_res jsonb := '[]'::jsonb;
  v     jsonb;
  a     text;
  b     text;
  v_raf uuid;
  n     int;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('Q5 (o fechamento da semana)', true, 'PULADO: sem as fixtures da 7b e as migrations como texto (rode pela bancada)');
    return;
  end if;
  -- sem resposta: a mensagem vira sem_resposta, a dias_semana vence, o resumo; de novo, nada
  begin
    perform pg_temp.equipe_toda();
    v_raf := pg_temp.pessoa('Rafael');
    perform pg_temp.modos('ligado', 'desligado');
    v := pg_temp.rodar('2026-11-05', '16:45');
    insert into public.agenda_perguntas (tipo, chave, payee_id, dia, perda_em, texto, modo, criada_em)
    values ('dias_semana', format('dias_semana:%s:2026-11-16', public._agenda_dono(null)), public._agenda_dono(null), date '2026-11-16',
            date '2026-11-12', 'Semana de 16/11: (teste)', 'ligado', pg_temp.em('2026-11-05', '16:45'));
    v := pg_temp.rodar('2026-11-12', '16:15');
    a := pg_temp.dias_msgs() || '/' || (select q.estado || ':' || q.resolvida_motivo from public.agenda_perguntas q where q.tipo = 'dias_semana');
    select string_agg(x.texto || ' [' || x.executada || ']', ' | ') into b from public.agenda_acoes x
     where x.tipo = 'equipe' and x.depois ->> 'motivo' = 'dias_da_semana';
    v := pg_temp.rodar('2026-11-12', '16:30');
    n := (select count(*) from public.agenda_acoes x where x.tipo = 'equipe' and x.depois ->> 'motivo' = 'dias_da_semana');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q5a o prazo da semana (qui 12/11 16:00): a pergunta sem resposta vira sem_resposta, a dias_semana vence ("sem resposta: vale o que estava") e o resumo da §6.3 byte a byte; o tique seguinte não refaz',
    a = 'Rafael:ligado:sem_resposta:16/11/vencida:sem resposta: vale o que estava'
    and b = 'Dias da semana de 16/11: Alex de seg a sex (você disse); você só abre e fecha. Rafael não respondeu: vale a última (de seg a sex). [true]'
    and n = 1, a || ' / ' || coalesce(b, '-') || ' / ' || n);

  -- o conflito: o dono tinha combinado qua 18/11 com o Rafael; ele responde "seg ter qui" (sem a quarta): mantém o do dono e diz
  begin
    perform pg_temp.equipe_toda();
    v_raf := pg_temp.pessoa('Rafael');
    perform pg_temp.modos('ligado', 'desligado');
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, criado_em)
    values (v_raf, daterange(date '2026-11-18', date '2026-11-18', '[]'), 'disponivel', 'dono', 'Você disse que vem', pg_temp.em('2026-11-05', '10:00'));
    v := pg_temp.rodar('2026-11-05', '16:45');
    v := pg_temp.responde('Rafael', 'seg ter qui', 'WA-Q5b', '2026-11-05', '17:30');
    v := pg_temp.rodar('2026-11-12', '16:15');
    select string_agg(x.texto, ' | ') into b from public.agenda_acoes x where x.tipo = 'equipe' and x.depois ->> 'motivo' = 'dias_da_semana';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q5b a exceção do dono no dia vence a resposta e o resumo diz: "Rafael não incluiu qua 18/11, que você tinha combinado com ele: mantive o que você disse."',
    b = 'Dias da semana de 16/11: Alex de seg a sex (você disse); Rafael seg, ter e qui (disse em 05/11); você só abre e fecha. Rafael não incluiu qua 18/11, que você tinha combinado com ele: mantive o que você disse.',
    coalesce(b, '-'));

  -- sem ninguém perguntado e sem a dias_semana da semana: nada fecha (a semana antes da 7b)
  begin
    perform pg_temp.modos('ligado', 'desligado');
    v := pg_temp.rodar('2026-11-12', '16:15');
    n := (select count(*) from public.agenda_acoes x where x.tipo = 'equipe' and x.depois ->> 'motivo' = 'dias_da_semana');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q5c sem ninguém perguntado e sem a dias_semana da semana, o prazo não gera resumo', n = 0, n::text);
  perform pg_temp.gravar(v_res);
end
$q5$;

-- ── Q6. A pergunta dos dias do dono ─────────────────────────────────────────────────────────────────────────────
do $q6$
declare
  v_res  jsonb := '[]'::jsonb;
  v      jsonb;
  a      text;
  b      text;
  q      public.agenda_perguntas%rowtype;
  v_dono uuid := public._agenda_dono(null);
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('Q6 (a pergunta do dono)', true, 'PULADO: sem as fixtures da 7b e as migrations como texto (rode pela bancada)');
    return;
  end if;
  -- com a padrao_do_dono:sem_dias do lote aberta: o dono_sem_padrao não pergunta de novo, e sem outro motivo nada nasce
  begin
    perform pg_temp.modos('ligado', 'desligado');
    v := pg_temp.rodar('2026-11-05', '16:45');
    a := coalesce(v #>> '{contagens,perguntar,dono}', '-') || '/' || coalesce(pg_temp.aberta('dias_semana:%'), '-');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q6a com a pergunta padrao_do_dono:sem_dias aberta (a do lote), nada nasce: sem motivo (a 7b não pergunta duas vezes)',
    a = 'sem_motivo/-', a);

  -- a do lote resolvida: o dono sem dias e as OS que precisam dele → a pergunta com as 3 opções (recomendo a 2)
  begin
    perform pg_temp.modos('ligado', 'desligado');
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where chave = 'padrao_do_dono:sem_dias' and estado = 'aberta';
    v := pg_temp.rodar('2026-11-05', '16:45');
    select x.* into q from public.agenda_perguntas x where x.tipo = 'dias_semana' and x.estado = 'aberta';
    a := q.chave || '/' || q.modo || '/' || q.perda_em || '/' || q.recomendacao || '/' || jsonb_array_length(q.opcoes) || '/'
         || (v #>> '{contagens,perguntar,motivos}');
    b := q.texto;
    -- a 2: "Fico em campo de seg a sex" cria o padrão do dono; na quinta seguinte o motivo sumiu
    v := public.agenda_decidir(q.id, 2::smallint, pg_temp.adm(), 'whatsapp', '2', date '2026-11-05', pg_temp.em('2026-11-05', '17:40'));
    a := a || ' | ' || (v ->> 'texto') || ' | '
         || (select string_agg(d.dias_semana::text || ':' || d.origem || ':' || coalesce(d.frequencia::text, 'sem_frequencia'), ' ')
               from public.agenda_disponibilidade d
              where d.payee_id = v_dono and d.substituida_em is null and d.dias_semana is not null);
    v := pg_temp.rodar('2026-11-12', '16:45');
    a := a || ' | ' || coalesce(v #>> '{contagens,perguntar,dono}', '-');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- FASE 7b: (correção da revisão da 7b, achados 3 e 10) a resposta da opção 2 diz que é toda semana
  v_res := pg_temp.ok(v_res, 'Q6b o dono_sem_padrao: a pergunta dias_semana (chave dias_semana:<dono>:2026-11-16, perda_em qui 12/11, 3 opções, recomendo a 2); a opção 2 cria o padrão do dono {1..5} origem dono sem frequência ("Anotei: você fica em campo de seg a sex, toda semana a partir de agora. Se mudar, me diga.") e na quinta seguinte o motivo sumiu',
    a = format('dias_semana:%s:2026-11-16/ligado/2026-11-12/2/3/["dono_sem_padrao"] | Anotei: você fica em campo de seg a sex, toda semana a partir de agora. Se mudar, me diga. | {1,2,3,4,5}:dono:sem_frequencia | sem_motivo', v_dono)
    -- FASE 7b: fim
    and b like 'Semana de 16/11: conto com Alex de seg a sex (você disse). % de você em campo e eu não sei seus dias: conto que você só abre e fecha. Se mudar algo, me diga (ex.: fico em campo seg a qua; Mateus vem ter e qua). 1) Fica assim; 2) Fico em campo de seg a sex (recomendo); 3) Nenhum dia: só abro e fecho.'
    and b like '%Rodrigo (OS-00096, diagnóstico)%', a || ' / ' || coalesce(b, '-'));

  -- a 3 ("Nenhum dia") prende só a semana: na quinta seguinte, com as OS ainda esperando, nasce a da semana seguinte; a 1 só responde
  begin
    perform pg_temp.modos('ligado', 'desligado');
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where chave = 'padrao_do_dono:sem_dias' and estado = 'aberta';
    v := pg_temp.rodar('2026-11-05', '16:45');
    select x.* into q from public.agenda_perguntas x where x.tipo = 'dias_semana' and x.estado = 'aberta';
    v := public.agenda_decidir(q.id, 3::smallint, pg_temp.adm(), 'whatsapp', '3', date '2026-11-05', pg_temp.em('2026-11-05', '17:40'));
    a := (v ->> 'texto') || ' | ' || pg_temp.semana(v_dono, date '2026-11-16') || ' | '
         || coalesce((select string_agg(d.dias_semana::text, ' ') from public.agenda_disponibilidade d
                       where d.payee_id = v_dono and d.substituida_em is null and d.dias_semana is not null), 'sem padrão');
    v := pg_temp.rodar('2026-11-12', '16:45');
    a := a || ' | ' || coalesce(v #>> '{contagens,perguntar,dono}', '-') || ' '
         || coalesce((select x.chave from public.agenda_perguntas x where x.tipo = 'dias_semana' and x.estado = 'aberta'), '-');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q6c a opção 3 ("Nenhum dia") prende só a semana de 16/11 (so_pontas; o padrão não muda); na qui 12/11, com as OS ainda esperando, nasce a de 23/11',
    a = format('Anotei: na semana de 16/11 você só abre e fecha. | 16/11=so_pontas 17/11=so_pontas 18/11=so_pontas 19/11=so_pontas | sem padrão | perguntei dias_semana:%s:2026-11-23', v_dono),
    a);
  begin
    perform pg_temp.modos('ligado', 'desligado');
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where chave = 'padrao_do_dono:sem_dias' and estado = 'aberta';
    v := pg_temp.rodar('2026-11-05', '16:45');
    select x.* into q from public.agenda_perguntas x where x.tipo = 'dias_semana' and x.estado = 'aberta';
    v := public.agenda_decidir(q.id, 1::smallint, pg_temp.adm(), 'whatsapp', '1', date '2026-11-05', pg_temp.em('2026-11-05', '17:40'));
    a := (v ->> 'texto') || ' | ' || pg_temp.semana(v_dono, date '2026-11-16') || ' | '
         || (select x.estado || ':' || x.opcao_escolhida from public.agenda_perguntas x where x.id = q.id);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q6d a opção 1 ("Fica assim") só fica respondida: nenhuma linha', a = 'Anotei: na semana de 16/11 fica assim. | - | respondida:1', a);

  -- a semente: o João na grade sem telefone, pelos dias do histórico (a pergunta do lote aberta não segura este motivo)
  begin
    perform pg_temp.modos('ligado', 'desligado');
    update public.agenda_disponibilidade set substituida_em = null where payee_id = pg_temp.pessoa('João') and origem = 'historico';
    v := pg_temp.rodar('2026-11-05', '16:45');
    select x.* into q from public.agenda_perguntas x where x.tipo = 'dias_semana' and x.estado = 'aberta';
    a := q.recomendacao || '/' || jsonb_array_length(q.opcoes);
    b := q.texto;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q6e a semente: "João (sem telefone): conto de ter a sex, pelo que veio nas últimas 8 semanas." (só a opção 1)',
    a = '1/1'
    and b = 'Semana de 16/11: conto com Alex de seg a sex (você disse) e João de ter a sex (pelo histórico). João (sem telefone): conto de ter a sex, pelo que veio nas últimas 8 semanas. Se mudar algo, me diga (ex.: fico em campo seg a qua; Mateus vem ter e qua). 1) Fica assim.',
    a || ' / ' || coalesce(b, '-'));

  -- {sempre}: toda quinta, byte a byte; dono_dias_semanal false: nunca
  begin
    perform pg_temp.modos('ligado', 'desligado');
    update public.agenda_config set dias_semana_motivos = '{sempre}' where id;
    v := pg_temp.rodar('2026-11-05', '16:45');
    b := pg_temp.aberta('dias_semana:%');
    update public.agenda_perguntas set estado = 'resolvida' where tipo = 'dias_semana' and estado = 'aberta';
    update public.agenda_config set dono_dias_semanal = false where id;
    v := pg_temp.rodar('2026-11-12', '16:45');
    a := coalesce(pg_temp.aberta('dias_semana:%'), '-');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q6f com dias_semana_motivos {sempre}, toda quinta (o texto byte a byte); com dono_dias_semanal false, nunca',
    b = 'Semana de 16/11: conto com Alex de seg a sex (você disse). Se mudar algo, me diga (ex.: fico em campo seg a qua; Mateus vem ter e qua). 1) Fica assim.'
    and a = '-', coalesce(b, '-') || ' / ' || a);

  -- com quem chamar ligado, a pergunta espera o diário de hoje do gestor até o tique das 17:15
  begin
    perform pg_temp.modos('ligado', 'desligado');
    update public.agenda_config set dias_semana_motivos = '{sempre,chamar}', modo_chamar = 'ligado' where id;
    v := pg_temp.rodar('2026-11-05', '16:45');
    a := coalesce(v #>> '{contagens,perguntar,dono}', '-');
    v := pg_temp.rodar('2026-11-05', '17:00');
    a := a || '/' || coalesce(v #>> '{contagens,perguntar,dono}', '-');
    v := pg_temp.rodar('2026-11-05', '17:15');
    a := a || '/' || coalesce(v #>> '{contagens,perguntar,dono}', '-');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q6g com modo_chamar ligado e sem o diário de hoje do gestor: 16:45 e 17:00 esperam, 17:15 pergunta',
    a = 'espera_o_diario/espera_o_diario/perguntei', a);
  perform pg_temp.gravar(v_res);
end
$q6$;

-- ── Q7. O cadastro: a chamada, o telefone, a d14 e o contato ─────────────────────────────────────────────────────
do $q7$
declare
  v_res jsonb := '[]'::jsonb;
  v     jsonb;
  a     text;
  b     text;
  q     public.agenda_perguntas%rowtype;
  v_raf uuid;
  v_mat uuid;
  v_id  uuid;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('Q7 (o cadastro)', true, 'PULADO: sem as fixtures da 7b e as migrations como texto (rode pela bancada)');
    return;
  end if;
  -- a chamada de hoje, byte a byte (o exemplo do R4.1-2); o telefone do Alex só dentro dela; as opções
  begin
    perform pg_temp.modos('desligado', 'ligado');
    v := pg_temp.rodar('2026-11-05', '16:45');
    select x.* into q from public.agenda_perguntas x where x.chave like 'equipe_cadastro:chamada:%' and x.estado = 'aberta';
    a := q.chave || '/' || q.modo || '/' || coalesce(q.perda_em::text, 'sem perda_em') || '/' || q.recomendacao || '/'
         || (q.expira_em = q.criada_em + interval '7 days') || '/' || coalesce(pg_temp.aberta('equipe_cadastro:telefone:%'), 'sem telefone sozinho');
    b := q.texto;
    v := public.agenda_decidir(q.id, 2::smallint, pg_temp.adm(), 'whatsapp', '2', date '2026-11-05', pg_temp.em('2026-11-05', '17:40'));
    a := a || ' | ' || (v ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q7a a chamada (equipe_cadastro:chamada:<segunda de hoje>), byte a byte o exemplo do R4.1-2: conto com Alex, o telefone dele dentro (nenhuma pergunta do telefone sozinha), quem vem sob demanda, Roberto e João saíram; sem perda_em, expira em 7 dias; a opção 2 diz como dizer quem saiu ou entrou, sem diária',
    a = 'equipe_cadastro:chamada:2026-11-02/ligado/sem perda_em/1/true/sem telefone sozinho | Me diga quem saiu ou quem entrou e em que dias vem (ex.: Alex saiu; Mateus vem qua e qui; Mateus vem toda terça).'
    and b = 'Na agenda conto com Alex: você disse todo dia útil. Alex não tem telefone no cadastro: sem ele não mando a ficha; para pôr, diga: o telefone do Alex é … Quem você chama quando precisa eu só conto nos dias que você disser (ex.: Mateus vem qua e qui). Roberto e João saíram da agenda em 30/10: não conto com eles. Está certo? 1) Está certo (recomendo); 2) Mudou. Se não responder em 3 dias úteis depois de ver, sigo assim.',
    a || ' / ' || coalesce(b, '-'));

  -- a chamada respondida (1): no dia seguinte nasce o telefone do Alex sozinho; o telefone cadastrado fecha a pergunta
  begin
    perform pg_temp.modos('desligado', 'ligado');
    v := pg_temp.rodar('2026-11-05', '16:45');
    select x.* into q from public.agenda_perguntas x where x.chave like 'equipe_cadastro:chamada:%' and x.estado = 'aberta';
    v := public.agenda_decidir(q.id, 1::smallint, pg_temp.adm(), 'whatsapp', '1', date '2026-11-05', pg_temp.em('2026-11-05', '17:40'));
    a := (v ->> 'texto');
    v := pg_temp.rodar('2026-11-06', '16:45');
    b := pg_temp.aberta('equipe_cadastro:telefone:%');
    update public.payees set phone = '5547900000099' where id = pg_temp.pessoa('Alex');
    v := pg_temp.rodar('2026-11-06', '17:00');
    a := a || ' | ' || (select x.estado || ':' || x.resolvida_motivo from public.agenda_perguntas x where x.chave like 'equipe_cadastro:telefone:%');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q7b a chamada respondida 1 ("Anotei: sigo com a equipe que tenho."); no dia seguinte, o telefone do Alex numa pergunta só dele (o texto do R4.1-1); com o telefone cadastrado, ela fecha ("telefone cadastrado")',
    a = 'Anotei: sigo com a equipe que tenho. | resolvida:telefone cadastrado'
    and b = 'Alex não tem telefone no cadastro: sem ele não mando a ficha da véspera (conto com Alex: você disse todo dia útil). Para pôr, diga: o telefone do Alex é …',
    a || ' / ' || coalesce(b, '-'));

  -- a d14 (no dia do plano): o Rafael (dias fixos, telefone) sem linha entra, com a ação desfazível; o *desfaz* para; ele não volta.
  -- Roberto (parado), Mickael (sem linha de disponibilidade) e João (saiu; mesmo com telefone) nunca.
  begin
    perform pg_temp.equipe_toda();
    v_raf := pg_temp.pessoa('Rafael');
    delete from public.agenda_equipe_contato where payee_id = v_raf;
    update public.payees set phone = '5547900000098' where id = pg_temp.pessoa('João');
    perform pg_temp.modos('desligado', 'ligado');
    v := pg_temp.rodar('2026-11-05', '16:45');
    select x.id, x.texto into v_id, b from public.agenda_acoes x where x.tipo = 'equipe' and x.depois ->> 'motivo' = 'regra_d14';
    a := (select string_agg(py.name || ':' || c.recebe_rotina || ':' || c.incluido_por, ' ' order by py.name)
            from public.agenda_equipe_contato c join public.payees py on py.id = c.payee_id where c.parou_em is null);
    v := public.agenda_desfazer(v_id, pg_temp.adm(), 'dono', date '2026-11-05', pg_temp.em('2026-11-05', '18:00'));
    a := a || ' | ' || (v ->> 'texto') || ' | '
         || (select c.recebe_rotina || ':' || c.parou_motivo from public.agenda_equipe_contato c where c.payee_id = v_raf);
    v := pg_temp.rodar('2026-11-12', '16:45');
    a := a || ' | ' || (select count(*) from public.agenda_acoes x where x.tipo = 'equipe' and x.depois ->> 'motivo' = 'regra_d14')::text;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q7c a regra d14: o Rafael entra (regra) com "Pus Rafael na rotina da equipe (vem de seg a sex e tem telefone): …"; Roberto, João (com telefone) e Mickael não; o *desfaz* o para ("desfeito pelo dono") e na quinta seguinte ele não volta',
    a = 'Alex:true:dono Rafael:true:regra | Desfeito: Rafael sai da rotina da equipe e não recebe mais a ficha nem a pergunta dos dias. | false:desfeito pelo dono | 1'
    and b = 'Pus Rafael na rotina da equipe (vem de seg a sex e tem telefone): ele passa a receber a ficha e a pergunta dos dias. *desfaz* tira.',
    a || ' / ' || coalesce(b, '-'));

  -- o contato: o Mateus (sob demanda, com telefone, com as datas ditas) nunca entra pela d14; a pergunta do contato; o "2) Não"
  -- grava a linha parada e, na quinta seguinte, nem a d14 nem a pergunta voltam (também com dias fixos)
  begin
    perform pg_temp.equipe_toda();
    v_mat := pg_temp.pessoa('Mateus');
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, criado_em)
    select v_mat, daterange(d, d, '[]'), 'disponivel', 'dono', 'Você disse que vem (sob demanda)', pg_temp.em('2026-11-05', '10:00')
      from unnest(array[date '2026-11-11', date '2026-11-12']) d;
    perform pg_temp.modos('desligado', 'ligado');
    v := pg_temp.rodar('2026-11-05', '16:45');
    select x.* into q from public.agenda_perguntas x where x.chave = 'equipe_cadastro:contato:' || v_mat and x.estado = 'aberta';
    b := q.texto;
    a := coalesce((select c.incluido_por from public.agenda_equipe_contato c where c.payee_id = v_mat), 'sem linha');
    v := public.agenda_decidir(q.id, 2::smallint, pg_temp.adm(), 'whatsapp', '2', date '2026-11-05', pg_temp.em('2026-11-05', '17:40'));
    a := a || ' | ' || (v ->> 'texto') || ' | '
         || (select c.recebe_rotina || ':' || c.incluido_por || ':' || (c.parou_em is not null) || ':' || c.parou_motivo
               from public.agenda_equipe_contato c where c.payee_id = v_mat);
    insert into public.agenda_disponibilidade (payee_id, dias_semana, situacao, origem, nota, criado_em)
    values (v_mat, '{3,4}', 'disponivel', 'dono', 'você disse', pg_temp.em('2026-11-06', '10:00'));
    v := pg_temp.rodar('2026-11-12', '16:45');
    a := a || ' | ' || coalesce(pg_temp.aberta('equipe_cadastro:contato:' || v_mat), 'sem pergunta') || ' | '
         || (select count(*) from public.agenda_acoes x where x.tipo = 'equipe' and x.depois ->> 'motivo' = 'regra_d14' and x.payee_id = v_mat)::text;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q7d o Mateus (sob demanda) não entra pela d14 e ganha a pergunta do contato (o texto do R4.1-6); o "2) Não" grava a linha parada ("você disse que não") e na quinta seguinte nem a pergunta nem a d14 voltam, mesmo com dias fixos',
    a = 'sem linha | Anotei: Mateus fica fora da rotina da equipe. | false:dono:true:você disse que não | sem pergunta | 0'
    and b = 'Mateus tem telefone, mas não está na rotina da equipe. Ponho? Ele passa a receber a ficha da véspera nos dias em que vier (os dias dele quem diz é você). 1) Ponho (recomendo); 2) Não.',
    a || ' / ' || coalesce(b, '-'));

  -- o "1) Ponho": entra na rotina (dono), com a ação desfazível; o *desfaz* para
  begin
    perform pg_temp.equipe_toda();
    v_mat := pg_temp.pessoa('Bruno');
    perform pg_temp.modos('desligado', 'ligado');
    v := pg_temp.rodar('2026-11-05', '16:45');
    select x.* into q from public.agenda_perguntas x where x.chave = 'equipe_cadastro:contato:' || v_mat and x.estado = 'aberta';
    v := public.agenda_decidir(q.id, 1::smallint, pg_temp.adm(), 'whatsapp', '1', date '2026-11-05', pg_temp.em('2026-11-05', '17:40'));
    a := (v ->> 'texto') || ' | ' || (select c.recebe_rotina || ':' || c.incluido_por from public.agenda_equipe_contato c where c.payee_id = v_mat);
    v := public.agenda_desfazer((v ->> 'acao_id')::uuid, pg_temp.adm(), 'dono', date '2026-11-05', pg_temp.em('2026-11-05', '17:50'));
    a := a || ' | ' || (v ->> 'texto') || ' | ' || (select c.recebe_rotina || ':' || c.parou_motivo from public.agenda_equipe_contato c where c.payee_id = v_mat);
    v := pg_temp.rodar('2026-11-05', '18:00');
    a := a || ' | ' || (select x.estado || ':' || coalesce(x.resolvida_motivo, '-') from public.agenda_perguntas x where x.id = q.id);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q7e o "1) Ponho" (Bruno): entra na rotina pelo dono ("Pus Bruno na rotina da equipe, como você pediu. *desfaz* tira."); o *desfaz* o para',
    a = 'Pus Bruno na rotina da equipe, como você pediu. *desfaz* tira. | true:dono | Desfeito: Bruno sai da rotina da equipe e não recebe mais a ficha nem a pergunta dos dias. | false:desfeito pelo dono | respondida:-',
    a);

  -- no máximo equipe_cadastro_abertas_max (3) abertas: com 3 abertas, nada nasce
  begin
    perform pg_temp.modos('desligado', 'ligado');
    insert into public.agenda_perguntas (tipo, chave, texto, modo, criada_em)
    select 'equipe_cadastro', 'equipe_cadastro:teste:' || n, 'Pergunta de teste ' || n, 'ligado', pg_temp.em('2026-11-04', '10:00')
      from generate_series(1, 3) n;
    v := pg_temp.rodar('2026-11-05', '16:45');
    a := (select count(*) from public.agenda_perguntas x where x.tipo = 'equipe_cadastro' and x.estado = 'aberta')::text;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q7f com 3 perguntas da equipe abertas (equipe_cadastro_abertas_max), a chamada não nasce', a = '3', a);

  -- o prazo da chamada: vista às 17:30, ganha veto_ate = 3 dias úteis depois (ter 10/11 18:00); vence depois dele; a não vista nunca vence aqui
  begin
    perform pg_temp.modos('desligado', 'ligado');
    v := pg_temp.rodar('2026-11-05', '16:45');
    select x.* into q from public.agenda_perguntas x where x.chave like 'equipe_cadastro:chamada:%' and x.estado = 'aberta';
    v := public.agenda_fechamento_registrar(date '2026-11-05', jsonb_build_array(jsonb_build_object('pergunta_id', q.id)), 'fechamento',
                                            pg_temp.em('2026-11-05', '17:30'));
    v := pg_temp.rodar('2026-11-05', '17:45');
    a := (select to_char(x.veto_ate at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') || ':' || (x.expira_em > x.veto_ate)
            from public.agenda_perguntas x where x.id = q.id);
    v := pg_temp.rodar('2026-11-10', '17:45');
    a := a || '/' || (select x.estado from public.agenda_perguntas x where x.id = q.id);
    v := pg_temp.rodar('2026-11-10', '18:15');
    a := a || '/' || (select x.estado || ':' || x.resolvida_motivo from public.agenda_perguntas x where x.id = q.id);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q7g a chamada vista (qui 17:30) ganha o prazo: ter 10/11 às 18:00 (3 dias úteis depois), com o expira_em depois dele; às 17:45 de ter ainda aberta, às 18:15 vencida ("sem resposta: segui como estava")',
    a = '10/11 18:00:true/aberta/vencida:sem resposta: segui como estava', a);
  begin
    perform pg_temp.modos('desligado', 'ligado');
    v := pg_temp.rodar('2026-11-05', '16:45');
    v := pg_temp.rodar('2026-11-11', '18:15');
    a := (select x.estado || ':' || coalesce(x.veto_ate::text, 'sem prazo') from public.agenda_perguntas x where x.chave like 'equipe_cadastro:chamada:%');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q7h a chamada nunca vista não ganha prazo nem vence pela rodada (o teto de 7 dias é o expira_em da limpeza)',
    a = 'aberta:sem prazo', a);
  perform pg_temp.gravar(v_res);
end
$q7$;

-- ── Q8. O foco equipe ───────────────────────────────────────────────────────────────────────────────────────────
do $q8$
declare
  v_res jsonb := '[]'::jsonb;
  a     text;
  b     text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('Q8 (o foco equipe)', true, 'PULADO: sem as fixtures da 7b e as migrations como texto (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.modos('ligado', 'ligado');
    a := public._agenda_ver_equipe(date '2026-11-05') ->> 'texto';
    perform pg_temp.modos('sombra', 'sombra');
    b := public._agenda_ver_equipe(date '2026-11-05') ->> 'texto';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q8a o foco equipe com a equipe real, ligado, byte a byte (Alex sem telefone, você, as faltas, as duplas, ninguém sob demanda, Roberto e João saíram)',
    a = concat_ws(E'\n',
          'A equipe não tem plano hoje nem no próximo dia útil.',
          'Dias da semana de 16/11 (o prazo é qui 12/11 às 16:00; ninguém da rotina tem telefone e dias fixos para eu perguntar):',
          '• Alex: de seg a sex (você disse; sem telefone).',
          '• Você: só abre e fecha.',
          'Semana de 09/11: Alex de seg a sex; você só abre e fecha.',
          'Faltas nos dias ditos (8 semanas): Alex ainda pouco para medir.',
          'Duplas nos últimos 60 dias: 17 de 35 dias com diária tiveram 2 pessoas ou mais.',
          'Sob demanda: ninguém dito.',
          'Saíram da agenda em 30/10: Roberto e João.'), a);
  v_res := pg_temp.ok(v_res, 'Q8b em teste, a 1ª linha diz que não perguntei a ninguém (e por quê); o resto igual',
    b = replace(a, 'Dias da semana de 16/11 (o prazo é qui 12/11 às 16:00; ninguém da rotina tem telefone e dias fixos para eu perguntar):',
                'Em teste (não perguntei a ninguém): os dias da semana de 16/11 — ninguém da rotina tem telefone e dias fixos para eu perguntar; os dias abaixo são os de agora.'),
    b);
  -- com a equipe toda em teste: a quem eu perguntaria, o Rafael pelo que ele disse, o Bruno sob demanda
  begin
    perform pg_temp.equipe_toda();
    perform pg_temp.modos('sombra', 'sombra');
    a := public._agenda_ver_equipe(date '2026-11-05') ->> 'texto';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q8c com a equipe da fixture em teste: "eu perguntaria a Rafael na qui 05/11 às 16:45 …", "• Rafael: de seg a sex (disse em 29/10).", "Sob demanda (só nos dias que você diz): Bruno (ter 10/11)."',
    a like '%Em teste (não perguntei a ninguém): eu perguntaria a Rafael na qui 05/11 às 16:45 os dias da semana de 16/11; os dias abaixo são os de agora.%'
    and a like E'%\n• Rafael: de seg a sex (disse em 29/10).\n%' and a like E'%\nSob demanda (só nos dias que você diz): Bruno (ter 10/11).\n%', a);
  perform pg_temp.gravar(v_res);
end
$q8$;

-- ── Q9. Com os modos da 7b desligados: nada muda ────────────────────────────────────────────────────────────────
do $q9$
declare
  v_res jsonb := '[]'::jsonb;
  v     jsonb;
  a     text;
  b     text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('Q9 (os modos desligados)', true, 'PULADO: sem as fixtures da 7b e as migrations como texto (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.equipe_toda();
    perform pg_temp.modos('desligado', 'desligado');
    v := pg_temp.rodar('2026-11-05', '16:45');
    a := (v ->> 'rodou') || '/'
         || (public._agenda_equipe_registrar(pg_temp.pessoa('Rafael'), date '2026-11-16', 'dias', 'Oi, Rafael! teste', pg_temp.em('2026-11-05', '16:45'))
             ->> 'criada')
         || '/' || pg_temp.dias_msgs() || '/'
         || ((public._agenda_ver_equipe(date '2026-11-05'))::text = (pg_temp.ver_equipe_antes(date '2026-11-05'))::text) || '/'
         || ((public._agenda_linhas_do_fechamento(date '2026-11-05'))::text = (pg_temp.linhas_antes(date '2026-11-05'))::text) || '/'
         || coalesce(public._agenda_gestor_equipe(date '2026-11-05', pg_temp.em('2026-11-05', '16:52')) ->> 'pulado', 'não pulou');
    -- a chamada da 7a (sem opções) aberta: o fechamento a mostra na (e), como antes
    insert into public.agenda_perguntas (tipo, chave, texto, modo, criada_em)
    values ('equipe_cadastro', 'equipe_cadastro:chamada:2026-11-16', 'Para marcar a semana de 16/11 eu conto com Alex (seg a sex), como você disse. Se a equipe mudou, me diga quem vem e em que dias.', 'ligado', pg_temp.em('2026-11-05', '16:52'));
    a := a || '/' || ((public._agenda_linhas_do_fechamento(date '2026-11-05'))::text = (pg_temp.linhas_antes(date '2026-11-05'))::text);
    b := public.agenda_decidir((select x.id from public.agenda_perguntas x where x.chave = 'equipe_cadastro:chamada:2026-11-16'), 1::smallint,
                               pg_temp.adm(), 'whatsapp', '1', date '2026-11-05', pg_temp.em('2026-11-05', '17:40')) ->> 'texto';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q9 com modo_dias e modo_cadastro desligados: a rodada {rodou: false}, o registro do tipo dias {criada: false}, nenhuma mensagem, o foco equipe e as linhas do fechamento byte a byte (também com a chamada da 7a aberta), a chamada da 7a não é pulada e continua "não é de decisão"',
    a = 'false/false/-/true/true/não pulou/true' and b = 'Essa pergunta não é de decisão.', a || ' / ' || coalesce(b, '-'));
  perform pg_temp.gravar(v_res);
end
$q9$;

-- ── Q11. A linha (n) da equipe no fechamento ────────────────────────────────────────────────────────────────────
do $q11$
declare
  v_res jsonb := '[]'::jsonb;
  v     jsonb;
  l     jsonb;
  a     text;
  b     text;
  q     public.agenda_perguntas%rowtype;
  v_ids text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('Q11 (a linha da equipe)', true, 'PULADO: sem as fixtures da 7b e as migrations como texto (rode pela bancada)');
    return;
  end if;
  -- a chamada nunca vista: perda 75, a sua linha; a (e) continua com as de fornecedor (30) e não a repete
  begin
    perform pg_temp.modos('ligado', 'ligado');
    v := pg_temp.rodar('2026-11-05', '16:45');
    select x.* into q from public.agenda_perguntas x where x.chave like 'equipe_cadastro:chamada:%' and x.estado = 'aberta';
    l := public._agenda_linhas_do_fechamento(date '2026-11-05');
    a := (select string_agg((x ->> 'perda') || ':' || (x ->> 'tipo') || ':' || (x ->> 'modo') || ':' || (x ->> 'pergunta_id' = q.id::text), ' ')
            from jsonb_array_elements(l) x where x ->> 'tipo' = 'pergunta');
    b := (select x ->> 'texto' from jsonb_array_elements(l) x where x ->> 'pergunta_id' = q.id::text);
    -- o fechamento mostra a linha: a chamada conta como mostrada; a rodada seguinte grava o prazo; a perda volta a 30
    v := public.agenda_fechamento_registrar(date '2026-11-05',
           (select jsonb_agg(x) from jsonb_array_elements(l) x where x ->> 'pergunta_id' = q.id::text), 'fechamento', pg_temp.em('2026-11-05', '17:30'));
    v := pg_temp.rodar('2026-11-05', '17:45');
    a := a || ' | ' || (select x.mostrada_vezes || ':' || to_char(x.veto_ate at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI')
                          from public.agenda_perguntas x where x.id = q.id)
         || ' | ' || (select x ->> 'perda' from jsonb_array_elements(public._agenda_linhas_do_fechamento(date '2026-11-06')) x
                       where x ->> 'pergunta_id' = q.id::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q11a a chamada nunca vista vai na linha (n) com perda 75 e modo ligado (a pergunta de fato (e), das de fornecedor, continua com 30 e não a repete); mostrada no fechamento, conta como vista, ganha o prazo (ter 10/11 18:00) e a perda volta a 30',
    a = '75:pergunta:ligado:true 30:pergunta:ligado:false | 1:10/11 18:00 | 30' and b = 'Agenda: ' || q.texto, a || ' / ' || coalesce(b, '-'));

  -- a dias_semana e o telefone na mesma linha, curtos; pergunta_ids com as três; o texto curto
  begin
    perform pg_temp.modos('ligado', 'ligado');
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where chave = 'padrao_do_dono:sem_dias' and estado = 'aberta';
    update public.agenda_config set dias_semana_motivos = '{sempre}' where id;
    v := pg_temp.rodar('2026-11-05', '16:45');
    insert into public.agenda_perguntas (tipo, chave, payee_id, texto, modo, criada_em)
    values ('equipe_cadastro', 'equipe_cadastro:telefone:' || pg_temp.pessoa('Alex'), pg_temp.pessoa('Alex'),
            'Alex não tem telefone no cadastro: sem ele não mando a ficha da véspera. Para pôr, diga: o telefone do Alex é …', 'ligado',
            pg_temp.em('2026-11-05', '16:46'));
    l := public._agenda_linhas_do_fechamento(date '2026-11-05');
    select x into v from jsonb_array_elements(l) x where x ->> 'tipo' = 'pergunta' and (x ->> 'perda')::int = 75;
    a := jsonb_array_length(v -> 'pergunta_ids')::text || '/' || (v ->> 'modo');
    b := (v ->> 'texto') || ' || ' || (v ->> 'texto_curto');
    v_ids := (select string_agg(x ->> 'pergunta_id', ',') from jsonb_array_elements(l) x where x ->> 'tipo' = 'pergunta' and (x ->> 'perda')::int = 30);
    a := a || '/' || coalesce((select string_agg(z.tipo, ',') from public.agenda_perguntas z where z.id::text = any (string_to_array(v_ids, ','))), '-');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- FASE 7b: (correção da revisão da 7b, achado 17) a dias_semana que vai só como "Também: …" não conta como mostrada (fora de
  -- pergunta_ids): pergunta_ids com a chamada e o telefone
  v_res := pg_temp.ok(v_res, 'Q11b a chamada (inteira), a dias_semana e o telefone (curtos) na mesma linha, pergunta_ids com a chamada e o telefone (a dias_semana curta não conta como mostrada); o texto_curto só pelo nome; a (e) fica com a de fornecedor',
    a = '2/ligado/fornecedores_prazo'
    -- FASE 7b: fim
    -- FASE 7b: (correção 3 da 7b) a forma curta leva o prazo de quem vence e o "sigo assim" (a chamada contada, com o cadastro ligado;
    -- os dias da semana, com os dias ligados); o telefone não vence e fica como antes
    and b like 'Agenda: Na agenda conto com Alex: % Também: os dias da semana de 16/11 (responda em *agenda pendências*). Também: o telefone do Alex (sem ele não mando a ficha). || Agenda, equipe: a equipe da agenda está certa? — sem resposta até ter 10/11 às 18:00, sigo assim; os dias da semana de 16/11 — sem resposta até qui 12/11 às 16:00, sigo assim; o telefone do Alex. *agenda pendências* mostra.',
    -- FASE 7b: fim
    a || ' / ' || coalesce(b, '-'));

  -- sem nenhuma pergunta da equipe aberta, com os modos ligados: a saída de antes, byte a byte
  begin
    perform pg_temp.modos('ligado', 'ligado');
    a := ((public._agenda_linhas_do_fechamento(date '2026-11-05'))::text = (pg_temp.linhas_antes(date '2026-11-05'))::text)::text;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q11c com os modos ligados e nenhuma pergunta da equipe aberta, as linhas do fechamento são as de antes, byte a byte', a = 'true', a);

  -- a espera da chamada não vista para em 7 dias: na qui 12/11 a pergunta da semana sai (a de 23/11)
  begin
    perform pg_temp.equipe_toda();
    perform pg_temp.modos('ligado', 'ligado');
    v := pg_temp.rodar('2026-11-05', '16:45');
    a := coalesce(v #>> '{contagens,perguntar,espera_chamada}', '-') || '/' || pg_temp.dias_msgs();
    v := pg_temp.rodar('2026-11-12', '17:00');
    a := a || '/' || pg_temp.dias_msgs() || '/'
         || (select x.estado from public.agenda_perguntas x where x.chave like 'equipe_cadastro:chamada:2026-11-02');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q11d a chamada nunca vista segura a 1ª pergunta em ligado no máximo 7 dias: na qui 12/11 17:00 (ela ainda aberta) a da semana de 23/11 sai',
    a = 'true/-/Rafael:ligado:enfileirada:23/11/aberta', a);
  perform pg_temp.gravar(v_res);
end
$q11$;

-- ── Q12. As cópias ───────────────────────────────────────────────────────────────────────────────────────────────
do $copia$
declare
  f      record;
  v_mig  text;
  v_novo text;
  v_n    int;
begin
  -- FASE 7b: (correção da revisão da 7b) a correção 20261101100800 recria agenda_resposta_da_equipe, agenda_decidir, agenda_desfazer e
  -- _agenda_linhas_do_fechamento: os blocos dela de fora são "-- FASE 7b:" (agenda_desfazer +3); os de dentro de um bloco da 7b têm a
  -- marca de dentro e saem junto com ele (não contam aqui)
  -- FASE 7b: fim
  for f in select * from (values
      ('_agenda_equipe_registrar', 'public._agenda_equipe_registrar(uuid, date, text, text, timestamptz, date, text)', 'mig_equipe_fase3', '20261026100300', 1),
      ('_agenda_rotina_sem_resposta', 'public._agenda_rotina_sem_resposta(date, timestamptz)', 'mig_equipe_fase3', '20261026100300', 1),
      ('agenda_resposta_da_equipe', 'public.agenda_resposta_da_equipe(text, text, text, timestamptz)', 'mig_equipe_fase3', '20261026100300', 4),
      ('agenda_decidir', 'public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz)', 'mig_perguntas_fase7a', '20261031100300', 2),
      ('agenda_desfazer', 'public.agenda_desfazer(uuid, uuid, text, date, timestamptz)', 'mig_rodada_fase7a', '20261031100600', 5),
      ('_agenda_ver_equipe', 'public._agenda_ver_equipe(date)', 'mig_acompanhamento_fase3', '20261026100500', 2),
      ('_agenda_linhas_do_fechamento', 'public._agenda_linhas_do_fechamento(date)', 'mig_correcao2_fase7a', '20261031100985', 4),
      ('_agenda_gestor_equipe', 'public._agenda_gestor_equipe(date, timestamptz)', 'mig_correcao_fase7a', '20261031100980', 1))
      as x(nome, sig, mig, versao, blocos) loop
    v_mig := coalesce(current_setting('agenda_teste.' || f.mig, true), '');
    if v_mig = '' then
      insert into _resultado values (format('Q12 %s: a cópia', f.nome), true, format('PULADO: sem agenda_teste.%s (rode pela bancada)', f.mig));
      continue;
    end if;
    select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = f.sig::regprocedure;
    select count(*) into v_n from regexp_matches(v_novo, '-- FASE 7b: fim', 'g');
    insert into _resultado values (
      format('Q12 %s: sem os %s blocos "-- FASE 7b:", é o corpo de %s', f.nome, f.blocos, f.versao),
      pg_temp.corpo(v_mig, f.nome) <> '' and pg_temp.sem_7b(v_novo) = pg_temp.corpo(v_mig, f.nome) and v_n = f.blocos,
      format('blocos %s; fonte %s letras; novo sem os blocos %s letras', v_n, length(pg_temp.corpo(v_mig, f.nome)), length(pg_temp.sem_7b(v_novo))));
  end loop;
end
$copia$;

-- ── Q13. As portas ───────────────────────────────────────────────────────────────────────────────────────────────
with f(sig, vol) as (values
  ('public._agenda_ler_dias_da_equipe(text)', 'i'), ('public._agenda_equipe_previstas_hoje(uuid, date, timestamptz)', 's'),
  ('public._agenda_equipe_texto_dias(uuid, date)', 's'))
insert into _resultado
select 'Q13a as 3 novas de leitura e de texto: invoker, search_path fixo, a volatilidade da spec; nem anon nem authenticated, só o service_role',
       bool_and(not p.prosecdef and p.provolatile = f.vol and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=public%'
                and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                and has_function_privilege('service_role', p.oid, 'execute')) and count(*) = 3,
       string_agg(f.sig, ', ') filter (where has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
  from f join pg_proc p on p.oid = f.sig::regprocedure;
insert into _resultado
select 'Q13b o motivo da pergunta do dono: invoker, STABLE, sem grant a ninguém (nem service_role); a rodada: security definer, VOLATILE, só o service_role',
       not m.prosecdef and m.provolatile = 's' and not has_function_privilege('service_role', m.oid, 'execute')
       and not has_function_privilege('authenticated', m.oid, 'execute') and not has_function_privilege('anon', m.oid, 'execute')
       and r.prosecdef and r.provolatile = 'v' and coalesce(array_to_string(r.proconfig, ','), '') like '%search_path=public%'
       and has_function_privilege('service_role', r.oid, 'execute') and not has_function_privilege('authenticated', r.oid, 'execute')
       and not has_function_privilege('anon', r.oid, 'execute'), null
  from pg_proc m, pg_proc r
 where m.oid = 'public._agenda_dias_semana_motivos(date, date)'::regprocedure
   and r.oid = 'public.agenda_equipe_semana(date, timestamp with time zone)'::regprocedure;
insert into _resultado
select 'Q13c anon recebe 42501 na rodada da semana e na leitura das respostas',
       pg_temp.como('anon', $q$select public.agenda_equipe_semana(date '2026-11-05', now())::text$q$) like 'erro 42501%'
       and pg_temp.como('anon', $q$select public._agenda_ler_dias_da_equipe('seg')::text$q$) like 'erro 42501%',
       pg_temp.como('anon', $q$select public.agenda_equipe_semana(date '2026-11-05', now())::text$q$);
-- uma consulta como um papel com um login (o admin do painel): o texto que volta ou "erro <sqlstate>: <mensagem>"
create function pg_temp.como_login(p_uid uuid, p_papel text, p_sql text) returns text language plpgsql as $f$
declare
  v text;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', p_papel)::text, true);
  begin
    execute format('set local role %I', p_papel);
    execute p_sql into v;
    reset role;
  exception when others then
    v := 'erro ' || sqlstate || ': ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;
do $q13d$
declare
  a text;
  b text;
  c text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('Q13d (o foco equipe pelo painel)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.modos('ligado', 'ligado');
    a := pg_temp.como('service_role', $q$select public._agenda_ver_equipe(date '2026-11-05') ->> 'texto'$q$);
    b := pg_temp.como_login(pg_temp.adm(), 'authenticated', $q$select public._agenda_ver_equipe(date '2026-11-05') ->> 'texto'$q$);
    -- sem o grant do P3, o admin do painel recebia 42501 (a leitura do P2 era só do service_role)
    revoke execute on function public._agenda_dias_declarados(uuid, date) from authenticated;
    c := pg_temp.como_login(pg_temp.adm(), 'authenticated', $q$select public._agenda_ver_equipe(date '2026-11-05') ->> 'texto'$q$);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  insert into _resultado values (
    'Q13d o foco equipe (invoker, do painel e do WhatsApp) com os modos da 7b ligados: o service_role e o admin logado (authenticated) leem o bloco da semana; sem o grant do P3 nas leituras do P2, o painel recebia 42501; anon nunca',
    a like '%Dias da semana de 16/11%' and b like '%Dias da semana de 16/11%' and c like 'erro 42501%'
    and has_function_privilege('authenticated', 'public._agenda_chance_de_falta(uuid, date)'::regprocedure, 'execute')
    and not has_function_privilege('anon', 'public._agenda_dias_declarados(uuid, date)'::regprocedure, 'execute'),
    left(coalesce(a, '-'), 120) || ' / ' || left(coalesce(b, '-'), 120) || ' / ' || left(coalesce(c, '-'), 120));
end
$q13d$;
with f(sig, quem) as (values
  ('public._agenda_equipe_registrar(uuid, date, text, text, timestamptz, date, text)', 'n'),
  ('public._agenda_rotina_sem_resposta(date, timestamptz)', 'n'), ('public._agenda_gestor_equipe(date, timestamptz)', 'n'),
  ('public.agenda_resposta_da_equipe(text, text, text, timestamptz)', 's'),
  ('public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz)', 's'),
  ('public.agenda_desfazer(uuid, uuid, text, date, timestamptz)', 's'),
  ('public._agenda_ver_equipe(date)', 'a'), ('public._agenda_linhas_do_fechamento(date)', 'a'))
insert into _resultado
select 'Q13e as recriadas com as portas de antes (as de dentro: ninguém; as RPCs: só service_role; as leituras: authenticated e service_role; nunca anon)',
       bool_and(not has_function_privilege('anon', p.oid, 'execute')
                and has_function_privilege('service_role', p.oid, 'execute') = (f.quem <> 'n')
                and has_function_privilege('authenticated', p.oid, 'execute') = (f.quem = 'a')) and count(*) = 8,
       string_agg(f.sig, ', ') filter (where has_function_privilege('anon', p.oid, 'execute')
                                          or has_function_privilege('service_role', p.oid, 'execute') <> (f.quem <> 'n')
                                          or has_function_privilege('authenticated', p.oid, 'execute') <> (f.quem = 'a'))
  from f join pg_proc p on p.oid = f.sig::regprocedure;

select teste, ok, detalhe from _resultado order by teste;

rollback;
