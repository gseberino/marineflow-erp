-- Prova do bloco da Agenda de Produção, Fase 7f (pacote P3): o veredito, o dia, o que mudou, as decisões e as compras nos 3 turnos, cortando por dentro, e o registro do que o dono viu
-- (migration 20261109100200; spec-fase7f §5.3, §6.1, §8.3 agenda_fase7f_bloco.sql e R8.4, R8.5-15, R8.6, R8.7, R8.8, R8.12, R8.13). O corte contra os 1.000 é do TS: secretario-tarde-texto_test.ts.
-- bancada: depende de 20261109100200
--
--   L0   desligado: {modo} e nada mais; a saída de antes, e nada novo é lido
--   L1   o bloco inteiro da fixture, byte a byte (ter 10/11 17:30)
--   L2   "nada mudou" em 1 linha; amanhã vazio; sexta; a quinta com a mensagem enviada, na hora dela; só compras
--   L3   os níveis de corte (bloco_max_chars 300): cada nível, o que cede e o que nunca sai
--   L4   parte que falha = incompleto e a frase de falha, nunca "nada mudou"; L4b nenhum tipo some: a lista fechada, com tipo novo reprovado; L4c cada tipo no destino da tabela
--   L5   o registro: o prazo no mesmo update, só o que foi escrito; pergunta_ids e conferencia contam; o veto_diria; de ponta a ponta com o prazo que vence
--   L6   as 2 saídas de agenda_textos_do_fechamento; sombra é a de antes, tirada a chave; o bloco não relê
--   L7   as cópias só mudam nos blocos
--   L8   Decisão N = n de agenda_decisoes_abertas, com a ordem do bloco diferente da numeração
--   L9   o "Hoje" não afirma o que não houve
--   L10  as portas
--   L11  o que sai das linhas: o que o dono já respondeu, o que o aviso já levou, a mensagem ao cliente, a semana
--   L12  o freio: o bloco funciona com gestor_so_propor, sem escrever prazo
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Fora dela sai PULADO: tudo aqui usa a fixture da 7f, que nunca roda em produção.
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
-- p_sql (que devolve um valor) como o papel p_papel com o login p_uid: o resultado em texto, ou 'erro <estado>: <mensagem>'.
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
  select id from public.app_users where role = 'admin' and active order by created_at limit 1
$f$;
create function pg_temp.na_bancada() returns boolean language sql stable as $f$
  select coalesce(current_setting('agenda_teste.fase7f', true), '') <> ''
     and coalesce(current_setting('agenda_teste.mig_bloco_fase7f', true), '') <> ''
$f$;
create function pg_temp.q(p_c text) returns uuid language sql immutable as $f$ select ('f7f00000-0000-4000-8000-0000000005' || p_c)::uuid $f$;
create function pg_temp.os(p_n text) returns uuid language sql immutable as $f$ select ('f7f00000-0000-4000-8000-000000097' || p_n)::uuid $f$;
-- O bloco valendo, com o prazo valendo: sem o freio.
create function pg_temp.liga() returns void language sql as $f$
  update public.agenda_config set modo_bloco_agenda = 'ligado', modo_veto = 'ligado', gestor_so_propor = false, modo_proposta = 'ligado' where id
$f$;
-- As linhas do bloco num nível: o que o Secretário faz com elas.
create function pg_temp.no_nivel(p_b jsonb, p_n int) returns jsonb language sql immutable as $f$
  select coalesce(jsonb_agg(l order by o), '[]'::jsonb) from jsonb_array_elements(p_b -> 'linhas') with ordinality t(l, o)
   where (l ->> 'nivel_entra')::int <= p_n and (l ->> 'nivel_de_corte' is null or p_n < (l ->> 'nivel_de_corte')::int)
$f$;
create function pg_temp.texto(p_b jsonb, p_n int) returns text language sql immutable as $f$
  select string_agg(l ->> 'texto', E'\n' order by o) from jsonb_array_elements(pg_temp.no_nivel(p_b, p_n)) with ordinality t(l, o)
$f$;
create function pg_temp.partes(p_b jsonb, p_n int) returns text language sql immutable as $f$
  select string_agg(l ->> 'parte', ',' order by o) from jsonb_array_elements(pg_temp.no_nivel(p_b, p_n)) with ordinality t(l, o)
$f$;
-- O bloco que agenda_textos_do_fechamento mandaria às 17:30 do dia.
create function pg_temp.bloco(p_hoje date default date '2026-11-10') returns jsonb language plpgsql as $f$
begin
  perform set_config('agenda.agora', ((p_hoje + time '17:30') at time zone 'America/Sao_Paulo')::text, true);
  return public.agenda_textos_do_fechamento(p_hoje, public.agenda_somar_du(p_hoje, 1)) -> 'bloco';
end $f$;
-- O bloco direto, sobre linhas dadas.
create function pg_temp.sobre(p_linhas jsonb, p_hoje date default date '2026-11-10') returns jsonb language sql as $f$
  select public.agenda_bloco_do_fechamento(p_hoje, (p_hoje + time '17:30') at time zone 'America/Sao_Paulo', p_linhas)
$f$;
create function pg_temp.l(p_tipo text, p_texto text, p_extra jsonb default '{}') returns jsonb language sql immutable as $f$
  select jsonb_build_object('tipo', p_tipo, 'texto', p_texto, 'perda', 50, 'pergunta_id', null, 'acao_ids', '[]'::jsonb, 'modo', 'ligado') || p_extra
$f$;
-- Sem pergunta aberta e sem ação por contar: o dia em que nada mudou.
create function pg_temp.limpa() returns void language sql as $f$
  update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste do bloco' where estado = 'aberta';
  update public.agenda_acoes set contada_em = timestamptz '2026-11-09 17:30-03', contada_via = 'fechamento' where contada_em is null;
$f$;
-- A subtransação que se desfaz: o caso mexe no estado à vontade.
create function pg_temp.desfaz() returns void language plpgsql as $f$
begin
  raise exception using errcode = 'P0001', message = '__desfaz__';
end $f$;

-- ── L0. Desligado ──────────────────────────────────────────────────────────────────────────
do $l$
declare
  r jsonb := '[]';
  v jsonb;
begin
  if not pg_temp.na_bancada() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'L o bloco', true, 'PULADO: sem a fixture e a migration como texto (rode pela bancada)'));
    return;
  end if;
  execute current_setting('agenda_teste.fase7f');
  r := pg_temp.ok(r, 'L0a desligado, como nasce', (select modo_bloco_agenda = 'desligado' from public.agenda_config), null);
  r := pg_temp.ok(r, 'L0b desligado: {modo} e nada mais', pg_temp.sobre('[]') = '{"modo": "desligado"}'::jsonb, pg_temp.sobre('[]')::text);
  v := public.agenda_textos_do_fechamento(date '2026-11-10', date '2026-11-11');
  r := pg_temp.ok(r, 'L0c desligado: agenda_textos_do_fechamento sem a chave bloco', not v ? 'bloco', null);
  begin
    perform public.agenda_bloco_do_fechamento(null, now(), '[]');
    r := pg_temp.ok(r, 'L0e sem o dia: 22004', false, 'aceitou');
  exception when sqlstate '22004' then
    r := pg_temp.ok(r, 'L0e sem o dia: 22004', true, null);
  end;
  begin
    perform public.agenda_bloco_do_fechamento(date '2026-11-10', null, '[]');
    r := pg_temp.ok(r, 'L0e2 sem a hora: 22004', false, 'aceitou');
  exception when sqlstate '22004' then
    r := pg_temp.ok(r, 'L0e2 sem a hora: 22004', true, null);
  end;
  begin
    perform public._agenda_feito_planejado(null);
    r := pg_temp.ok(r, 'L0f _agenda_feito_planejado sem o dia: 22004', false, 'aceitou');
  exception when sqlstate '22004' then
    r := pg_temp.ok(r, 'L0f _agenda_feito_planejado sem o dia: 22004', true, null);
  end;
  -- com o caminho novo estourando, desligado não encosta nele
  begin
    create or replace function public._agenda_feito_planejado(p_hoje date) returns jsonb language plpgsql stable as 'begin raise exception ''não devia rodar''; end';
    create or replace function public.agenda_bloco_do_fechamento(p_hoje date, p_agora timestamptz, p_linhas jsonb) returns jsonb language plpgsql stable as 'begin raise exception ''não devia rodar''; end';
    r := pg_temp.ok(r, 'L0d desligado: agenda_textos_do_fechamento não chama o bloco', not public.agenda_textos_do_fechamento(date '2026-11-10', date '2026-11-11') ? 'bloco', null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$l$;

-- ── L1. O bloco inteiro ────────────────────────────────────────────────────────────────────
do $l$
declare
  r jsonb := '[]';
  b jsonb;
begin
  if not pg_temp.na_bancada() then return; end if;
  perform pg_temp.liga();
  b := pg_temp.bloco();
  r := pg_temp.ok(r, 'L1a o bloco inteiro, nível 0, byte a byte', pg_temp.texto(b, 0) = array_to_string(array[
    'Agenda: mudei 3 coisas e preciso de 8 respostas suas. Amanhã (qua 11/11): Vanderlei com Alex e Flávio com Roberto.',
    'Hoje: 3 de 6 meios-dias feitos; Vanderlei à tarde não (material); falta dizer como foi em 2 (*dia feito* confirma).',
    'Hoje era o último dia do Ivo (OS-97179) no plano: terminou? *concluiu Ivo* fecha a OS (saída e cobranças da condição).',
    'Mudou: Tirei o Roberto da tarde de hoje no Flávio: o cliente pediu. *desfaz Flávio* volta como estava. Marquei Lenine em seg 16/11 com Alex (3 dias, estimativa minha). *desfaz Lenine* volta como estava. Passei Vanderlei da tarde de hoje para qua 11/11 de manhã. *desfaz Vanderlei* volta como estava.',
    '· Decisão 1: O serviço do Flávio (lancha, Revisão do piloto automático) não cabe mais em qua 11/11 com… Isto espera você: mexe no dia que o cliente já sabe.',
    '· Você: Quais dias você fica em campo na semana de 16/11? Hoje eu conto você só para abrir e… Sem resposta até qua 11/11 às 18:00, continuo contando você só para abrir e fechar.',
    '· Nelson: marquei 3 dias pela estimativa (ter 17 a qui 19/11). Sem resposta até ter 10/11 às 18:00, fica assim; se for outro número, me diga os dias.',
    '(e mais 5 em *agenda pendências*)'], E'\n'), pg_temp.texto(b, 0));
  r := pg_temp.ok(r, 'L1b o nível dado cabe em bloco_max_chars, e chars é o tamanho dele', char_length(pg_temp.texto(b, (b ->> 'nivel')::int)) = (b ->> 'chars')::int and (b ->> 'chars')::int <= 520
    and (b ->> 'nivel')::int > 0, format('nivel %s chars %s', b ->> 'nivel', b ->> 'chars'));
  r := pg_temp.ok(r, 'L1c o nível dado é o menor que cabe', char_length(pg_temp.texto(b, (b ->> 'nivel')::int - 1)) > 520, null);
  r := pg_temp.ok(r, 'L1d não está nada_mudou nem incompleto', (b ->> 'nada_mudou')::boolean = false and (b ->> 'incompleto')::boolean = false and not b ? 'sem_destino', null);
  r := pg_temp.ok(r, 'L1e as 3 ações da fixture na linha do Mudou, e nas 2 formas dela',
    (select bool_and(jsonb_array_length(l -> 'acao_ids') = 3) and count(*) = 2 from jsonb_array_elements(b -> 'linhas') l where l ->> 'parte' = 'mudou'), null);
  r := pg_temp.ok(r, 'L1f as 2 chaves de pergunta em toda linha do bloco', (select bool_and(l ? 'pergunta_id' and l ? 'pergunta_ids' and l ? 'acao_ids') from jsonb_array_elements(b -> 'linhas') l), null);
  r := pg_temp.ok(r, 'L1g a linha de decisão leva a pergunta nas 2 chaves',
    (select bool_and(l -> 'pergunta_ids' = jsonb_build_array(l ->> 'pergunta_id')) from jsonb_array_elements(b -> 'linhas') l where l ->> 'pergunta_id' is not null), null);
  r := pg_temp.ok(r, 'L1h a linha só diz o prazo que ela carrega',
    (select bool_and((l ->> 'texto' like '%Sem resposta até%') = (l ->> 'veto_ate' is not null)) from jsonb_array_elements(b -> 'linhas') l where l ->> 'parte' = 'decisao'), null);
  r := pg_temp.ok(r, 'L1i toda linha de decisão de verdade começa por "· "',
    (select bool_and(l ->> 'texto' like '· %') from jsonb_array_elements(b -> 'linhas') l where l ->> 'parte' = 'decisao' and l ->> 'pergunta_id' is not null), null);
  r := pg_temp.ok(r, 'L1j sem as palavras que o dono não usa', pg_temp.texto(b, 0) !~* '\m(proposta|veto|lote|classe|zona|destrava|ppc)\M' and char_length(pg_temp.texto(b, 0)) > 100, null);
  update public.agenda_config set modo_bloco_agenda = 'desligado' where id;
  perform pg_temp.gravar(r);
end
$l$;

-- ── L2. O veredito ─────────────────────────────────────────────────────────────────────────
do $l$
declare
  r jsonb := '[]';
  b jsonb;
  v_ac uuid;
begin
  if not pg_temp.na_bancada() then return; end if;
  begin
    perform pg_temp.liga();
    perform pg_temp.limpa();
    b := pg_temp.sobre('[]', date '2026-11-14');
    r := pg_temp.ok(r, 'L2a nada mudou, sem plano hoje: 1 linha só, e o veredito curto; sábado: o próximo dia útil é segunda',
      pg_temp.texto(b, 0) = 'Agenda: nada mudou. Segunda (16/11): Lenine com Alex.' and (b ->> 'nada_mudou')::boolean, pg_temp.texto(b, 0));
    b := pg_temp.sobre('[]', date '2026-11-13');
    r := pg_temp.ok(r, 'L2b sexta: "Segunda (16/11)" no lugar de "Amanhã"; com plano hoje, a linha do dia fica, e nada_mudou continua',
      pg_temp.texto(b, 0) = E'Agenda: nada mudou. Segunda (16/11): Lenine com Alex.\nHoje: 2 meios-dias marcados; falta dizer como foi (*dia feito* confirma).' and (b ->> 'nada_mudou')::boolean, pg_temp.texto(b, 0));
    b := pg_temp.sobre('[]', date '2026-11-24');
    b := pg_temp.sobre('[]', date '2026-11-09');
    r := pg_temp.ok(r, 'L2c2 o dono amanhã é "você"', pg_temp.texto(b, 0) = 'Agenda: nada mudou. Amanhã (ter 10/11): Ivo com você e João e Vanderlei com Alex e Rafael.', pg_temp.texto(b, 0));
    b := pg_temp.sobre('[]', date '2026-11-24');
    r := pg_temp.ok(r, 'L2c amanhã vazio: o próximo serviço', pg_temp.texto(b, 0) = 'Agenda: nada mudou. Amanhã (qua 25/11) sem serviço marcado; o próximo é Otto, ter 01/12.', pg_temp.texto(b, 0));
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_em = now(), cancelada_motivo = 'replanejado' where dia > date '2026-11-25' and estado in ('publicada', 'fixada');
    b := pg_temp.sobre('[]', date '2026-11-24');
    r := pg_temp.ok(r, 'L2d sem nada marcado adiante: a frase para aí', pg_temp.texto(b, 0) = 'Agenda: nada mudou. Amanhã (qua 25/11) sem serviço marcado.', pg_temp.texto(b, 0));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.liga();
    perform pg_temp.limpa();
    -- a quinta, com a mensagem própria já enviada: a hora é a que saiu (R8.5-15), e o texto não inventa 16:50
    v_ac := (select id from public.agenda_acoes order by criada_em desc limit 1);
    insert into public.agenda_dono_avisos (rodada, dia, texto, acao_ids, telefone, enviar_em, estado, dedupe_key, enviada_em)
    values (timestamptz '2026-11-12 17:00-03', date '2026-11-12', 'A semana.', array[v_ac], '5547999999999', timestamptz '2026-11-12 17:00-03', 'enviada', 'agenda-dono:semana:2026-11-12', timestamptz '2026-11-12 17:03-03');
    b := pg_temp.sobre('[]', date '2026-11-12');
    r := pg_temp.ok(r, 'L2e a quinta com a mensagem enviada: a hora em que ela saiu', split_part(pg_temp.texto(b, 0), E'\n', 1) = 'Agenda: a semana que vem foi às 17:03; desde então nada mudou.', pg_temp.texto(b, 0));
    b := pg_temp.sobre(jsonb_build_array(pg_temp.l('semana', 'Agenda: publiquei a semana.', '{"acao_ids": ["f7f00000-0000-4000-8000-000000000601"]}')), date '2026-11-12');
    r := pg_temp.ok(r, 'L2f com a mensagem enviada, a linha semana sai: ela já contou', pg_temp.partes(b, 0) not like '%semana%' and split_part(pg_temp.texto(b, 0), E'\n', 1) like 'Agenda: a semana que vem foi às 17:03%', pg_temp.texto(b, 0));
    b := pg_temp.sobre(jsonb_build_array(pg_temp.l('compras', 'Compras: Kamell: Cerbo.')), date '2026-11-12');
    r := pg_temp.ok(r, 'L2f2 com a mensagem enviada e algo a dizer: o veredito de sempre, e a compra sem linha em agenda_gestor_dia conta 1', split_part(pg_temp.texto(b, 0), E'\n', 1) like 'Agenda: nada mudou; 1 compra vence. Amanhã (sex 13/11)%', pg_temp.texto(b, 0));
    update public.agenda_dono_avisos set estado = 'enfileirada', enviada_em = null where dia = date '2026-11-12';
    b := pg_temp.sobre('[]', date '2026-11-12');
    r := pg_temp.ok(r, 'L2g ainda na fila não é "foi às": o veredito de sempre', split_part(pg_temp.texto(b, 0), E'\n', 1) = 'Agenda: nada mudou. Amanhã (sex 13/11): Lenine com Roberto.', pg_temp.texto(b, 0));
    insert into public.agenda_dono_avisos (rodada, dia, texto, acao_ids, telefone, enviar_em, estado, dedupe_key, enviada_em)
    values (timestamptz '2026-11-12 11:00-03', date '2026-11-12', 'O aviso de sempre.', array[v_ac], '5547999999999', timestamptz '2026-11-12 11:00-03', 'enviada', 'agenda-dono:aviso:outro', timestamptz '2026-11-12 11:03-03');
    b := pg_temp.sobre('[]', date '2026-11-12');
    r := pg_temp.ok(r, 'L2g2 o aviso de sempre, enviado na quinta, não é a mensagem da semana', split_part(pg_temp.texto(b, 0), E'\n', 1) = 'Agenda: nada mudou. Amanhã (sex 13/11): Lenine com Roberto.', pg_temp.texto(b, 0));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.liga();
    perform pg_temp.limpa();
    insert into public.agenda_gestor_dia (dia, calculado_em, modos, compras) values (date '2026-11-14', now(), '{}', '[{"texto": "Kamell: Cerbo de Nelson — compre até seg 16/11.", "compre_ate": "2026-11-16"}]')
    on conflict (dia) do update set compras = excluded.compras;
    b := pg_temp.sobre(jsonb_build_array(pg_temp.l('compras', 'Compras: Kamell: Cerbo de Nelson — compre até seg 16/11.')), date '2026-11-14');
    r := pg_temp.ok(r, 'L2h só compras: "nada mudou" e a compra que vence, e não conta como nada_mudou',
      pg_temp.texto(b, 0) = E'Agenda: nada mudou; 1 compra vence até seg 16/11. Segunda (16/11): Lenine com Alex.\nCompras: Kamell: Cerbo de Nelson — compre até seg 16/11.' and not (b ->> 'nada_mudou')::boolean, pg_temp.texto(b, 0));
    r := pg_temp.ok(r, 'L2i a compra cortada', pg_temp.texto(b, 1) = E'Agenda: nada mudou; 1 compra vence até seg 16/11. Segunda (16/11): Lenine com Alex.\n+1 compra (*agenda compras*).', pg_temp.texto(b, 1));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.liga();
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste do bloco' where estado = 'aberta';
    b := pg_temp.sobre('[]');
    r := pg_temp.ok(r, 'L2j só mudanças: "mudei N coisas", sem falar em respostas, e não é nada_mudou', split_part(pg_temp.texto(b, 0), E'\n', 1) = 'Agenda: mudei 3 coisas. Amanhã (qua 11/11): Vanderlei com Alex e Flávio com Roberto.' and not (b ->> 'nada_mudou')::boolean, pg_temp.texto(b, 0));
    perform pg_temp.limpa();
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, reserva_de, criado_em)
    select a.service_order_id, a.payee_id, date '2026-11-25', a.turno, a.presenca, 'reserva', 'publicada', 'motor', timestamptz '2026-11-05 16:30-03', 'patio', timestamptz '2026-11-05 16:30-03'
      from public.agenda_alocacoes a where a.service_order_id = pg_temp.os('306') and a.estado = 'publicada' limit 1;
    b := pg_temp.sobre('[]', date '2026-11-24');
    r := pg_temp.ok(r, 'L2k a reserva sai como reserva, sem dizer quem vai', pg_temp.texto(b, 0) = 'Agenda: nada mudou. Amanhã (qua 25/11): Tadeu (reserva).', pg_temp.texto(b, 0));
    b := pg_temp.sobre('[]', date '2026-11-23');
    r := pg_temp.ok(r, 'L2k2 "o próximo" nunca é reserva', split_part(pg_temp.texto(b, 0), E'\n', 1) = 'Agenda: nada mudou. Amanhã (ter 24/11) sem serviço marcado; o próximo é Otto, ter 01/12.', pg_temp.texto(b, 0));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$l$;

-- ── L3. Os níveis ──────────────────────────────────────────────────────────────────────────
do $l$
declare
  r  jsonb := '[]';
  b  jsonb;
  c_pl constant jsonb := jsonb_build_array(pg_temp.l('compras', 'Compras: Kamell: Cerbo de Nelson — compre até qui 12/11.'), pg_temp.l('comissao', 'Comissão de outubro: R$ 100,00.'),
                                           pg_temp.l('cliente', 'Amanhã, a partir das 09:00, vou mandar: a confirmação de qua 11/11 para Flávio. Para não mandar: *segura cliente Flávio*.'));
begin
  if not pg_temp.na_bancada() then return; end if;
  begin
    perform pg_temp.liga();
    update public.agenda_config set bloco_max_chars = 300 where id;
    insert into public.agenda_gestor_dia (dia, calculado_em, modos, compras) values (date '2026-11-10', now(), '{}', '[{"texto": "Kamell: Cerbo de Nelson — compre até qui 12/11.", "compre_ate": "2026-11-12"}]')
    on conflict (dia) do update set compras = excluded.compras;
    b := pg_temp.sobre(c_pl);
    r := pg_temp.ok(r, 'L3a nível 0: tudo, na ordem do texto', pg_temp.partes(b, 0) = 'veredito,hoje,mudou,decisao,decisao,decisao,decisao,compras,outras,outras', pg_temp.partes(b, 0));
    r := pg_temp.ok(r, 'L3b nível 1: as outras saem e as compras viram +N (§3.1 item 6, R8.4)',
      pg_temp.partes(b, 1) = 'veredito,hoje,mudou,decisao,decisao,decisao,decisao,compras' and pg_temp.texto(b, 1) like '%+1 compra (*agenda compras*).' and pg_temp.texto(b, 1) not like '%Comissão%', pg_temp.partes(b, 1));
    r := pg_temp.ok(r, 'L3c nível 2: Mudou vira a contagem', pg_temp.texto(b, 2) like '%Mudou: mudei 3 coisas (*o que mudou*).%' and pg_temp.texto(b, 2) not like '%Marquei Lenine%', null);
    r := pg_temp.ok(r, 'L3d nível 3: 1 decisão a menos, e a conta acompanha', pg_temp.texto(b, 3) like '%(e mais 6 em *agenda pendências*)%' and pg_temp.texto(b, 3) not like '%Nelson: marquei%' and pg_temp.texto(b, 3) like '%Você:%', null);
    r := pg_temp.ok(r, 'L3e nível 4: só a 1ª decisão', pg_temp.texto(b, 4) like '%(e mais 7 em *agenda pendências*)%' and pg_temp.texto(b, 4) not like '%Você:%' and pg_temp.texto(b, 4) like '%Decisão 1%', null);
    r := pg_temp.ok(r, 'L3f o último nível: só o veredito e a 1ª decisão, que nunca saem',
      (b ->> 'nivel_min')::int = 5 and pg_temp.partes(b, 5) = 'veredito,decisao' and pg_temp.texto(b, 5) like 'Agenda: mudei 3 coisas%Decisão 1%' and pg_temp.texto(b, 5) not like '%(e mais%', pg_temp.texto(b, 5));
    r := pg_temp.ok(r, 'L3g o veredito e a 1ª decisão são as únicas sem corte',
      (select count(*) = 2 from jsonb_array_elements(b -> 'linhas') l where l ->> 'nivel_de_corte' is null), null);
    r := pg_temp.ok(r, 'L3h cada nível tem menos letras que o anterior', (select bool_and(char_length(pg_temp.texto(b, k)) < char_length(pg_temp.texto(b, k - 1))) from generate_series(1, 5) k), null);
    r := pg_temp.ok(r, 'L3i o bloco de 300 pede o último nível: nada mais cabe, e chars é o tamanho dele, acima do teto: o veredito e a 1ª decisão não saem',
      (b ->> 'nivel')::int = 5 and (b ->> 'chars')::int = char_length(pg_temp.texto(b, 5)), format('nivel %s chars %s', b ->> 'nivel', b ->> 'chars'));
    update public.agenda_config set bloco_decisoes_max = 1 where id;
    b := pg_temp.sobre(c_pl);
    r := pg_temp.ok(r, 'L3j com 1 decisão só, o último nível é o 3', (b ->> 'nivel_min')::int = 3 and pg_temp.partes(b, 2) = 'veredito,hoje,mudou,decisao,decisao,compras' and pg_temp.partes(b, 3) = 'veredito,decisao' and pg_temp.texto(b, 2) like '%(e mais 7 em *agenda pendências*)%', pg_temp.partes(b, 2));
    update public.agenda_config set bloco_mudancas_max = 1, bloco_decisoes_max = 3, bloco_max_chars = 800 where id;
    b := pg_temp.sobre(c_pl);
    -- a frase de uma ação vai a 400 letras: a linha cabe no bloco, frase a frase, ou fica só a contagem
    b := pg_temp.sobre(jsonb_build_array(pg_temp.l('conclusao', 'Concluí o Ivo: ' || repeat('palavra ', 60) || '.')));
    r := pg_temp.ok(r, 'L3k2 a linha Mudou nunca passa do bloco: cede frase a frase e diz quantas ficaram de fora',
      (select char_length(l ->> 'texto') <= 800 from jsonb_array_elements(pg_temp.no_nivel(b, 0)) l where l ->> 'parte' = 'mudou') and pg_temp.texto(b, 0) like '%Concluí o Ivo%', pg_temp.partes(b, 0));
    update public.agenda_config set bloco_max_chars = 300 where id;
    b := pg_temp.sobre(jsonb_build_array(pg_temp.l('conclusao', 'Concluí o Ivo: ' || repeat('palavra ', 60) || '.')));
    r := pg_temp.ok(r, 'L3k3 nem 1 frase cabendo: só a contagem, desde o nível 0', pg_temp.texto(b, 0) like '%Mudou: mudei 4 coisas (*o que mudou*).%' and pg_temp.texto(b, 0) not like '%Concluí o Ivo%', pg_temp.texto(b, 0));
    update public.agenda_config set bloco_max_chars = 800 where id;
    b := pg_temp.sobre(c_pl);
    r := pg_temp.ok(r, 'L3k bloco_mudancas_max: as frases param e o resto vai para *o que mudou*, com os ids de todas', pg_temp.texto(b, 0) like '%Mudou: Tirei o Roberto da tarde de hoje no Flávio: o cliente pediu. *desfaz Flávio* volta como estava. (e mais 2 em *o que mudou*).%'
      and (select jsonb_array_length(l -> 'acao_ids') = 3 from jsonb_array_elements(b -> 'linhas') l where l ->> 'parte' = 'mudou' limit 1), pg_temp.texto(b, 0));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- a ordem do Mudou: a exceção, depois o que mexe no que alguém sabe, depois a mais antiga. A classe vem de um dublê, que põe a exceção e o que mexe no que a equipe sabe fora da ordem de gravação
    perform pg_temp.liga();
    create or replace function public._agenda_classe_da_saida(p_tipo text, p_ref uuid, p_hoje date, p_agora timestamptz) returns jsonb language sql stable as $s$
      select jsonb_build_object('excecao', p_ref = 'f7f00000-0000-4000-8000-000000000602',
                                'afeta', jsonb_build_object('equipe', p_ref = 'f7f00000-0000-4000-8000-000000000603', 'cliente', false))
    $s$;
    b := pg_temp.sobre('[]');
    r := pg_temp.ok(r, 'L3m o Mudou: a exceção primeiro, depois quem mexe no que alguém sabe, depois a mais antiga', pg_temp.texto(b, 0) like '%Mudou: Passei Vanderlei %Tirei o Roberto %Marquei Lenine %', pg_temp.texto(b, 0));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- a publicação não é frase do Mudou: ela é a parte semana
    perform pg_temp.liga();
    perform pg_temp.limpa();
    create or replace function public._agenda_mudancas(p_de date, p_ate date, p_executada boolean, p_fechamento boolean, p_agora timestamptz default null) returns jsonb language sql stable as $s$
      select '[{"tipo": "publicacao", "acao_ids": ["f7f00000-0000-4000-8000-000000000601"], "itens": ["A PUBLICACAO"], "em": "2026-11-10"}]'::jsonb
    $s$;
    b := pg_temp.sobre('[]', date '2026-11-13');
    r := pg_temp.ok(r, 'L3n a publicação não vira frase do Mudou nem conta como mudança', pg_temp.texto(b, 0) not like '%A PUBLICACAO%' and pg_temp.texto(b, 0) like 'Agenda: nada mudou.%', pg_temp.texto(b, 0));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- sem resto: nada de "(e mais 0)"
    perform pg_temp.liga();
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste do bloco' where id not in (pg_temp.q('06'), pg_temp.q('01')) and estado = 'aberta';
    b := pg_temp.sobre('[]');
    r := pg_temp.ok(r, 'L3o com todas à vista, sem "(e mais 0)", e a conta só nasce quando uma sai', pg_temp.texto(b, 0) not like '%(e mais%' and pg_temp.texto(b, 3) like '%(e mais 1 em *agenda pendências*)%', pg_temp.texto(b, 3));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.liga();
    perform pg_temp.limpa();
    b := pg_temp.sobre('[]', date '2026-11-13');
    r := pg_temp.ok(r, 'L3l sem decisão: o último nível é o 3, e o veredito fica sozinho', (b ->> 'nivel_min')::int = 3 and pg_temp.partes(b, 3) = 'veredito' and pg_temp.partes(b, 2) = 'veredito,hoje', pg_temp.partes(b, 3));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$l$;

-- ── L4. A parte que falha e a lista fechada ────────────────────────────────────────────────
do $l$
declare
  r jsonb := '[]';
  b jsonb;
  x record;
  c_falha constant text := 'Agenda: não consegui ler a agenda inteira agora; *agenda* mostra o que está marcado.';
  c_compra constant jsonb := jsonb_build_array(pg_temp.l('compras', 'Compras: Kamell: Cerbo.'));
begin
  if not pg_temp.na_bancada() then return; end if;
  for x in select * from (values
      ('hoje', 'create or replace function public._agenda_feito_planejado(p_hoje date) returns jsonb language plpgsql stable as ''begin raise exception ''''falhou''''; end'''),
      ('mudou', 'create or replace function public._agenda_classe_da_saida(p_tipo text, p_ref uuid, p_hoje date, p_agora timestamptz) returns jsonb language plpgsql stable as ''begin raise exception ''''falhou''''; end'''),
      ('decisao', 'create or replace function public.agenda_perguntas_em_ordem(p_hoje date, p_agora timestamptz) returns jsonb language plpgsql stable as ''begin raise exception ''''falhou''''; end'''),
      ('compras', 'alter table public.agenda_gestor_dia rename to agenda_gestor_dia_x'),
      ('amanha', 'alter view public.v_agenda_dia rename to v_agenda_dia_x')) t(parte, sql) loop
    begin
      perform pg_temp.liga();
      execute x.sql;
      b := pg_temp.sobre(c_compra);
      r := pg_temp.ok(r, format('L4a %s que falha: incompleto, a frase de falha e nunca "nada mudou"', x.parte),
        (b ->> 'incompleto')::boolean and not (b ->> 'nada_mudou')::boolean and split_part(pg_temp.texto(b, 0), E'\n', 1) = c_falha, pg_temp.texto(b, 0));
      if x.parte <> 'amanha' then
        r := pg_temp.ok(r, format('L4b %s que falha: o resto do bloco sai', x.parte), case x.parte when 'decisao' then pg_temp.texto(b, 0) like '%Mudou:%' else pg_temp.texto(b, 0) like '%Decisão 1%' end, pg_temp.texto(b, 0));
      end if;
      perform pg_temp.desfaz();
    exception when sqlstate 'P0001' then
      if sqlerrm <> '__desfaz__' then raise; end if;
    end;
  end loop;
  begin
    -- a conferência não some com a falha do Hoje; e, sem mais nada, a falha não vira "nada mudou"
    perform pg_temp.liga();
    perform pg_temp.limpa();
    create or replace function public._agenda_feito_planejado(p_hoje date) returns jsonb language plpgsql stable as 'begin raise exception ''falhou''; end';
    b := pg_temp.sobre(jsonb_build_array(pg_temp.l('dia', 'A CONFERENCIA.', '{"pergunta_id": "f7f00000-0000-4000-8000-000000000501"}')));
    r := pg_temp.ok(r, 'L4b2 o Hoje que falha deixa a linha da conferência', pg_temp.texto(b, 0) like '%A CONFERENCIA.%', pg_temp.texto(b, 0));
    r := pg_temp.ok(r, 'L4b3 sem nada a dizer, a falha não é nada_mudou', not (b ->> 'nada_mudou')::boolean and (b ->> 'incompleto')::boolean, b::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  -- o tempo esgotado não é parte que falha: sobe, e quem lê registra (57014)
  begin
    perform pg_temp.liga();
    create or replace function public._agenda_feito_planejado(p_hoje date) returns jsonb language plpgsql stable as 'begin raise exception using errcode = ''57014'', message = ''canceling statement due to statement timeout''; end';
    begin
      b := pg_temp.sobre('[]');
      r := pg_temp.ok(r, 'L4c query_canceled sobe', false, 'não subiu');
    exception when query_canceled then
      r := pg_temp.ok(r, 'L4c query_canceled sobe', true, null);
    end;
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$l$;

-- L4d a lista fechada: os tipos que as 2 funções montam, lidos do corpo delas: tipo novo sem destino reprova aqui.
do $l$
declare
  r  jsonb := '[]';
  v  text[];
  c_tipos constant text[] := array['cliente', 'comissao', 'compras', 'conclusao', 'decisao', 'dia', 'diaria', 'gestor', 'mudancas', 'pergunta', 'ppc', 'semana'];
  b  jsonb;
  v_fonte text;
begin
  if not pg_temp.na_bancada() then return; end if;
  v_fonte := pg_get_functiondef('public._agenda_linhas_do_fechamento(date)'::regprocedure) || pg_get_functiondef('public._agenda_cliente_fechamento(date)'::regprocedure);
  v := array(select distinct m[1] from regexp_matches(v_fonte, E'''tipo'',\\s*''([a-z_]+)''', 'g') m order by 1);
  r := pg_temp.ok(r, 'L4d os tipos que as linhas montam são estes 12 (a spec conta 11): tipo novo tem de ganhar destino em _agenda_bloco_destino e entrar aqui', v = c_tipos, array_to_string(v, ','));
  r := pg_temp.ok(r, 'L4e todo tipo tem destino', not exists (select 1 from unnest(v) t where public._agenda_bloco_destino(t) is null), null);
  r := pg_temp.ok(r, 'L4f a lista de _agenda_bloco_destino não tem tipo a mais', public._agenda_bloco_destino('novo') is null
    and (select count(*) from regexp_matches(pg_get_functiondef('public._agenda_bloco_destino(text)'::regprocedure), E'when ''', 'g')) = 12, null);
  perform pg_temp.liga();
  b := pg_temp.sobre(jsonb_build_array(pg_temp.l('novo', 'Uma linha de um tipo que ainda não existe.')));
  r := pg_temp.ok(r, 'L4g tipo sem destino não some: vai para outras, e o bloco diz qual', pg_temp.texto(b, 0) like '%Uma linha de um tipo que ainda não existe.%' and b -> 'sem_destino' = '["novo"]'::jsonb, pg_temp.texto(b, 0));
  update public.agenda_config set modo_bloco_agenda = 'desligado' where id;
  perform pg_temp.gravar(r);
end
$l$;

-- L4h cada tipo no destino da tabela de R8.4, com linhas de verdade na forma de cada um
do $l$
declare
  r jsonb := '[]';
  b jsonb;
  t text;
begin
  if not pg_temp.na_bancada() then return; end if;
  perform pg_temp.liga();
  b := pg_temp.sobre(jsonb_build_array(
    pg_temp.l('decisao', 'DECISAO DAS LINHAS'), pg_temp.l('pergunta', 'PERGUNTA DAS LINHAS'), pg_temp.l('diaria', 'DIARIA DAS LINHAS'), pg_temp.l('gestor', 'GESTOR DAS LINHAS'),
    pg_temp.l('mudancas', 'MUDANCAS DAS LINHAS'),
    pg_temp.l('conclusao', 'Concluí o Ivo: o Roberto disse que terminou. *desfaz OS-97179* reabre.', '{"acao_ids": ["f7f00000-0000-4000-8000-000000000604"]}'),
    pg_temp.l('comissao', 'Comissão de outubro: R$ 100,00.'),
    pg_temp.l('cliente', 'Amanhã, a partir das 09:00, vou mandar: a confirmação. Para não mandar: *segura cliente Flávio*.'),
    pg_temp.l('ppc', 'Semana de 09 a 13/11 até ter 10/11: 2 de 3 dias de serviço cumpridos (67%). Não cumprido: Vanderlei ter 10/11 (material). Sem conferência: ter 10/11 (Ivo) — *dia feito 10/11* confirma.'),
    pg_temp.l('dia', 'Etapas (Alex não tem telefone: quem passa e confere é você). Amanhã, Alex no Flávio: Terminar: isto.', '{"texto_curto": "Etapas: amanhã, Alex no Flávio (1 etapa)."}'),
    pg_temp.l('semana', 'Agenda: publiquei a semana que vem. *desfaz semana* volta.', '{"acao_ids": ["f7f00000-0000-4000-8000-000000000605"]}'),
    pg_temp.l('compras', 'COMPRAS DAS LINHAS'),
    pg_temp.l('comissao', 'LINHA EM TESTE', '{"modo": "sombra"}')));
  t := pg_temp.texto(b, 0);
  r := pg_temp.ok(r, 'L4h decisao, pergunta e diaria vêm da ordem, não do texto das linhas', t not like '%DAS LINHAS%' or t not similar to '%(DECISAO|PERGUNTA|DIARIA) DAS LINHAS%', t);
  r := pg_temp.ok(r, 'L4i gestor sai: *agenda gestor* mostra', t not like '%GESTOR DAS LINHAS%', null);
  r := pg_temp.ok(r, 'L4j mudancas: as frases vêm de _agenda_mudancas, não da linha', t not like '%MUDANCAS DAS LINHAS%' and t like '%Marquei Lenine%', null);
  r := pg_temp.ok(r, 'L4k conclusao em Mudou, primeiro, e conta na soma', t like 'Agenda: mudei 5 coisas%' and t like '%Mudou: Concluí o Ivo%', t);
  r := pg_temp.ok(r, 'L4l comissao e o que sai amanhã em outras', pg_temp.partes(b, 0) like '%outras,outras' and pg_temp.texto(b, 1) not like '%Comissão%', pg_temp.partes(b, 0));
  r := pg_temp.ok(r, 'L4m ppc: a 1ª frase, em hoje, e cede no nível 2', t like '%Semana de 09 a 13/11 até ter 10/11: 2 de 3 dias de serviço cumpridos (67%).%' and t not like '%Sem conferência%' and pg_temp.texto(b, 2) not like '%2 de 3 dias%', null);
  r := pg_temp.ok(r, 'L4n Etapas: a forma curta, em hoje, e cede no nível 2', t like '%Etapas: amanhã, Alex no Flávio (1 etapa).%' and t not like '%Terminar: isto%' and pg_temp.texto(b, 2) not like '%Etapas%', null);
  r := pg_temp.ok(r, 'L4o semana: sem a mensagem da quinta, a linha fica, e cede no nível 2 para a contagem, com os ids', t like '%Agenda: publiquei a semana que vem. *desfaz semana* volta.%'
    and pg_temp.texto(b, 2) not like '%publiquei a semana%'
    and (select l -> 'acao_ids' @> '["f7f00000-0000-4000-8000-000000000605"]'::jsonb from jsonb_array_elements(pg_temp.no_nivel(b, 2)) l where l ->> 'parte' = 'mudou'), null);
  r := pg_temp.ok(r, 'L4o2 a linha semana leva as ações dela', (select l -> 'acao_ids' = '["f7f00000-0000-4000-8000-000000000605"]'::jsonb from jsonb_array_elements(pg_temp.no_nivel(b, 0)) l where l ->> 'parte' = 'semana'), null);
  r := pg_temp.ok(r, 'L4p compras: o texto das linhas', t like '%COMPRAS DAS LINHAS%', null);
  r := pg_temp.ok(r, 'L4q a linha em sombra nunca entra', t not like '%LINHA EM TESTE%', null);
  update public.agenda_config set modo_bloco_agenda = 'desligado' where id;
  perform pg_temp.gravar(r);
end
$l$;

-- ── L5. O registro ─────────────────────────────────────────────────────────────────────────
do $l$
declare
  r   jsonb := '[]';
  b   jsonb;
  v   jsonb;
  q   public.agenda_perguntas;
  c_agora constant timestamptz := timestamptz '2026-11-10 17:45-03';
  c_prazo constant timestamptz := timestamptz '2026-11-11 18:00-03';
  c_hoje  constant date := date '2026-11-10';
begin
  if not pg_temp.na_bancada() then return; end if;
  begin
    -- o nulo: a pergunta sem prazo ganha o do texto, no mesmo update
    v := public.agenda_fechamento_registrar(c_hoje, jsonb_build_array(jsonb_build_object('pergunta_id', pg_temp.q('01'), 'acao_ids', '[]'::jsonb, 'veto_ate', c_prazo)), 'fechamento', c_agora);
    select * into q from public.agenda_perguntas x where x.id = pg_temp.q('01');
    r := pg_temp.ok(r, 'L5a de nulo: veto_ate, mostrada_vezes, mostrada_em e mostrada_via juntos', q.veto_ate = c_prazo and q.mostrada_vezes = 1 and q.mostrada_em = c_agora and q.mostrada_via = 'fechamento' and (v ->> 'perguntas')::int = 1, row_to_json(q)::text);
    -- sem veto_ate na linha, nada muda
    update public.agenda_perguntas set estado = estado where false;
    v := public.agenda_fechamento_registrar(c_hoje, jsonb_build_array(jsonb_build_object('pergunta_id', pg_temp.q('04'), 'acao_ids', '[]'::jsonb)), 'fechamento', c_agora);
    select * into q from public.agenda_perguntas x where x.id = pg_temp.q('04');
    r := pg_temp.ok(r, 'L5b sem veto_ate na linha: mostrada sobe, e o prazo fica nulo', q.veto_ate is null and q.mostrada_vezes = 1 and q.mostrada_em = c_agora, null);
    -- a que espera o dono não ganha prazo
    update public.agenda_perguntas set veto_espera = 'dono' where id = pg_temp.q('07') and veto_espera is null;
    perform public.agenda_fechamento_registrar(c_hoje, jsonb_build_array(jsonb_build_object('pergunta_id', pg_temp.q('07'), 'acao_ids', '[]'::jsonb, 'veto_ate', c_prazo)), 'fechamento', c_agora);
    r := pg_temp.ok(r, 'L5c a que espera o dono não ganha prazo, e conta como mostrada',
      (select x.veto_ate is null and x.mostrada_em = c_agora from public.agenda_perguntas x where x.id = pg_temp.q('07')), null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- de valor a valor: o 7a gravou um prazo que passou sem a pergunta ter sido mostrada: vale o que o dono está lendo
    update public.agenda_perguntas set veto_ate = timestamptz '2026-11-09 18:00-03' where id = pg_temp.q('01');
    perform public.agenda_fechamento_registrar(c_hoje, jsonb_build_array(jsonb_build_object('pergunta_id', pg_temp.q('01'), 'acao_ids', '[]'::jsonb, 'veto_ate', c_prazo)), 'fechamento', c_agora);
    r := pg_temp.ok(r, 'L5d o prazo velho que passou sem ser mostrado dá lugar ao do texto', (select x.veto_ate = c_prazo and x.mostrada_vezes = 1 from public.agenda_perguntas x where x.id = pg_temp.q('01')), null);
    -- mostrada depois do prazo velho: "nunca mostrada antes dele" inclui essa
    update public.agenda_perguntas set veto_ate = timestamptz '2026-11-09 18:00-03', mostrada_vezes = 1, mostrada_em = timestamptz '2026-11-09 18:30-03' where id = pg_temp.q('04');
    perform public.agenda_fechamento_registrar(c_hoje, jsonb_build_array(jsonb_build_object('pergunta_id', pg_temp.q('04'), 'acao_ids', '[]'::jsonb, 'veto_ate', c_prazo)), 'fechamento', c_agora);
    r := pg_temp.ok(r, 'L5e mostrada só depois do prazo velho: também ganha o novo', (select x.veto_ate = c_prazo from public.agenda_perguntas x where x.id = pg_temp.q('04')), null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- o que o dono já viu com prazo não muda: a 02 da fixture foi mostrada em 09/11 com o prazo de 10/11 18:00
    perform public.agenda_fechamento_registrar(c_hoje, jsonb_build_array(jsonb_build_object('pergunta_id', pg_temp.q('02'), 'acao_ids', '[]'::jsonb, 'veto_ate', c_prazo)), 'fechamento', c_agora);
    r := pg_temp.ok(r, 'L5f prazo que ele já viu, ainda de pé, não muda', (select x.veto_ate = timestamptz '2026-11-10 18:00-03' and x.mostrada_em = c_agora from public.agenda_perguntas x where x.id = pg_temp.q('02')), null);
    perform public.agenda_fechamento_registrar(date '2026-11-11', jsonb_build_array(jsonb_build_object('pergunta_id', pg_temp.q('03'), 'acao_ids', '[]'::jsonb, 'veto_ate', timestamptz '2026-11-12 18:00-03')), 'fechamento', timestamptz '2026-11-11 17:30-03');
    r := pg_temp.ok(r, 'L5g prazo que ele viu e que venceu não muda: quem decide é a rodada', (select x.veto_ate = timestamptz '2026-11-10 18:00-03' from public.agenda_perguntas x where x.id = pg_temp.q('03')), null);
    update public.agenda_perguntas set veto_ate = timestamptz '2026-11-20 18:00-03' where id = pg_temp.q('04');
    perform public.agenda_fechamento_registrar(c_hoje, jsonb_build_array(jsonb_build_object('pergunta_id', pg_temp.q('04'), 'acao_ids', '[]'::jsonb, 'veto_ate', c_prazo)), 'fechamento', c_agora);
    r := pg_temp.ok(r, 'L5h prazo que ainda vale, nunca mostrado: fica, sem recuar', (select x.veto_ate = timestamptz '2026-11-20 18:00-03' from public.agenda_perguntas x where x.id = pg_temp.q('04')), null);
    update public.agenda_perguntas set veto_ate = timestamptz '2026-11-20 18:00-03' where id = pg_temp.q('01');
    perform public.agenda_fechamento_registrar(c_hoje, jsonb_build_array(jsonb_build_object('pergunta_id', pg_temp.q('01'), 'acao_ids', '[]'::jsonb, 'veto_ate', timestamptz '2026-11-21 18:00-03')), 'fechamento', c_agora);
    r := pg_temp.ok(r, 'L5h2 prazo que ainda vale, nunca mostrado: nem um prazo maior o troca', (select x.veto_ate = timestamptz '2026-11-20 18:00-03' and x.mostrada_vezes = 1 from public.agenda_perguntas x where x.id = pg_temp.q('01')), null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- pergunta_ids: cada uma conta uma vez, a pergunta_id não conta 2 vezes
    v := public.agenda_fechamento_registrar(c_hoje, jsonb_build_array(jsonb_build_object('pergunta_id', pg_temp.q('01'), 'pergunta_ids', jsonb_build_array(pg_temp.q('01'), pg_temp.q('04')), 'acao_ids', '[]'::jsonb)), 'fechamento', c_agora);
    r := pg_temp.ok(r, 'L5i pergunta_ids conta todas, e a da pergunta_id uma vez só', (v ->> 'perguntas')::int = 2
      and (select bool_and(x.mostrada_vezes = 1) and count(*) = 2 from public.agenda_perguntas x where x.id in (pg_temp.q('01'), pg_temp.q('04'))), v::text);
    -- veto_diria: mede, sem prazo
    perform public.agenda_fechamento_registrar(c_hoje, jsonb_build_array(jsonb_build_object('pergunta_id', pg_temp.q('07'), 'acao_ids', '[]'::jsonb, 'veto_diria', c_prazo)), 'fechamento', c_agora);
    r := pg_temp.ok(r, 'L5j veto_diria vai para veto_teria_em, e o prazo fica nulo', (select x.veto_teria_em = c_prazo and x.veto_ate is null from public.agenda_perguntas x where x.id = pg_temp.q('07')), null);
    perform public.agenda_fechamento_registrar(date '2026-11-11', jsonb_build_array(jsonb_build_object('pergunta_id', pg_temp.q('07'), 'acao_ids', '[]'::jsonb, 'veto_diria', timestamptz '2026-11-12 18:00-03')), 'fechamento', timestamptz '2026-11-11 17:30-03');
    r := pg_temp.ok(r, 'L5k veto_teria_em é o 1º, uma vez só', (select x.veto_teria_em = c_prazo from public.agenda_perguntas x where x.id = pg_temp.q('07')), null);
    -- o caminho de sempre
    v := public.agenda_fechamento_registrar(c_hoje, jsonb_build_array(jsonb_build_object('pergunta_id', null, 'acao_ids', jsonb_build_array('f7f00000-0000-4000-8000-000000000601'))), 'fechamento', c_agora);
    r := pg_temp.ok(r, 'L5l a linha sem pergunta conta a ação, como antes', (v ->> 'perguntas')::int = 0 and (v ->> 'acoes')::int = 1, v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- de ponta a ponta: a conferência da linha dia conta como mostrada
    perform pg_temp.liga();
    insert into public.agenda_perguntas (tipo, chave, dia, texto, modo, criada_em)
    values ('conferencia', 'conferencia:2026-11-10', c_hoje, 'Hoje a agenda tinha Vanderlei. Foi isso? Responda *dia feito* ou conte o que mudou.', 'ligado', timestamptz '2026-11-10 17:00-03');
    b := pg_temp.bloco();
    v := (select l from jsonb_array_elements(b -> 'linhas') l where l ->> 'parte' = 'hoje' and l ->> 'pergunta_id' is not null limit 1);
    r := pg_temp.ok(r, 'L5m a linha Hoje leva a pergunta conferencia', (select x.tipo = 'conferencia' from public.agenda_perguntas x where x.id = (v ->> 'pergunta_id')::uuid), coalesce(v::text, 'sem a linha'));
    perform public.agenda_fechamento_registrar(c_hoje, jsonb_build_array(v), 'fechamento', c_agora);
    r := pg_temp.ok(r, 'L5n a conferência conta como mostrada', (select x.mostrada_vezes = 1 and x.mostrada_via = 'fechamento' from public.agenda_perguntas x where x.id = (v ->> 'pergunta_id')::uuid), null);
    -- de ponta a ponta: o prazo nasce do texto, e vale
    b := pg_temp.bloco();
    perform public.agenda_fechamento_registrar(c_hoje, pg_temp.no_nivel(b, 0), 'fechamento', c_agora);
    select * into q from public.agenda_perguntas x where x.id = pg_temp.q('01');
    r := pg_temp.ok(r, 'L5o a pergunta mostrada com prazo ganha o prazo que estava no texto', q.veto_ate = c_prazo and q.mostrada_vezes = 1 and pg_temp.texto(b, 0) like '%Você:%Sem resposta até qua 11/11 às 18:00%', pg_temp.texto(b, 0));
    r := pg_temp.ok(r, 'L5p as ações do que saiu ficam contadas', (select count(*) = 3 from public.agenda_acoes a where a.contada_em = c_agora), null);
    perform public._agenda_gestor_vetos(date '2026-11-11', timestamptz '2026-11-11 18:05-03');
    r := pg_temp.ok(r, 'L5q e ela vence nesse prazo', (select x.estado = 'resolvida' and x.assumida_por = 'prazo' from public.agenda_perguntas x where x.id = pg_temp.q('01')), null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- nível cortado: a decisão que saiu do texto não conta como mostrada e não ganha prazo
    perform pg_temp.liga();
    b := pg_temp.bloco();
    perform public.agenda_fechamento_registrar(c_hoje, pg_temp.no_nivel(b, (b ->> 'nivel_min')::int), 'fechamento', c_agora);
    select * into q from public.agenda_perguntas x where x.id = pg_temp.q('01');
    r := pg_temp.ok(r, 'L5r no último nível, a decisão que saiu do texto não ganha prazo nem conta', q.veto_ate is null and q.mostrada_vezes = 0, null);
    r := pg_temp.ok(r, 'L5s e as ações ficam por contar', not exists (select 1 from public.agenda_acoes a where a.contada_em = c_agora), null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$l$;

-- ── L6. As 2 saídas, a sombra e o peso ─────────────────────────────────────────────────────
do $l$
declare
  r  jsonb := '[]';
  a  jsonb;
  b  jsonb;
  v  text;
  x  record;
  c_h constant date := date '2026-11-10';
  c_d constant date := date '2026-11-11';
begin
  if not pg_temp.na_bancada() then return; end if;
  for x in select * from unnest(array['desligado', 'sombra', 'ligado']) m loop
    begin
      perform pg_temp.liga();
      update public.agenda_config set modo_vaga_fechamento = x.m, modo_bloco_agenda = 'desligado' where id;
      a := public.agenda_textos_do_fechamento(c_h, c_d);
      update public.agenda_config set modo_bloco_agenda = 'ligado' where id;
      b := public.agenda_textos_do_fechamento(c_h, c_d);
      r := pg_temp.ok(r, format('L6a modo_vaga_fechamento %s: a saída leva o bloco', x.m), (b -> 'bloco' ->> 'modo') = 'ligado' and jsonb_array_length(b #> '{bloco,linhas}') > 2, null);
      r := pg_temp.ok(r, format('L6b modo_vaga_fechamento %s: tirada a chave, a saída é a de antes', x.m), (b - 'bloco')::text = a::text, null);
      perform pg_temp.desfaz();
    exception when sqlstate 'P0001' then
      if sqlerrm <> '__desfaz__' then raise; end if;
    end;
  end loop;
  begin
    perform pg_temp.liga();
    update public.agenda_config set modo_bloco_agenda = 'desligado' where id;
    a := public.agenda_textos_do_fechamento(c_h, c_d);
    update public.agenda_config set modo_bloco_agenda = 'sombra' where id;
    b := public.agenda_textos_do_fechamento(c_h, c_d);
    r := pg_temp.ok(r, 'L6c em sombra, a chave existe e diz sombra', b -> 'bloco' ->> 'modo' = 'sombra', null);
    r := pg_temp.ok(r, 'L6d em sombra, tirada a chave, md5 igual ao desligado: as linhas não mudam', md5((b - 'bloco')::text) = md5(a::text), null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    update public.agenda_config set modo_leitura = 'desligado', modo_bloco_agenda = 'ligado' where id;
    r := pg_temp.ok(r, 'L6e a leitura desligada cala tudo: sem bloco', not public.agenda_textos_do_fechamento(c_h, c_d) ? 'bloco', null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  -- o bloco não relê: nenhuma destas no corpo dele; agenda_textos_do_fechamento lê as linhas 1 vez por caminho
  v := pg_temp.corpo(current_setting('agenda_teste.mig_bloco_fase7f'), 'agenda_bloco_do_fechamento');
  r := pg_temp.ok(r, 'L6f o bloco recebe as linhas: não relê as linhas, as compras, a semana medida nem o dia da equipe',
    char_length(v) > 2000 and v !~ '_agenda_linhas_do_fechamento\(|_agenda_compras_da_semana\(|agenda_ppc\(|_agenda_dia_da_equipe\(|_agenda_cliente_fechamento\(', null);
  v := pg_temp.corpo(current_setting('agenda_teste.mig_bloco_fase7f'), 'agenda_textos_do_fechamento');
  r := pg_temp.ok(r, 'L6g 3 chamadas de _agenda_linhas_do_fechamento no corpo: a do modo vaga, a do bloco na saída final e a da saída de antes',
    (select count(*) = 3 from regexp_matches(v, '_agenda_linhas_do_fechamento\(', 'g')) and v like '%agenda_bloco_do_fechamento(p_hoje, coalesce(nullif(current_setting(''agenda.agora'', true), '''')::timestamptz, now()), v_f7_lin)%', null);
  perform pg_temp.gravar(r);
end
$l$;

-- ── L7. As cópias ──────────────────────────────────────────────────────────────────────────
do $l$
declare
  r     jsonb := '[]';
  v_mig text := current_setting('agenda_teste.mig_bloco_fase7f', true);
  v_or  text := current_setting('agenda_teste.mig_correcao_fase7a', true);
  x     record;
begin
  if coalesce(v_mig, '') = '' or coalesce(v_or, '') = '' then
    perform pg_temp.gravar(pg_temp.ok('[]', 'L7 as cópias', true, 'PULADO: sem as migrations como texto (rode pela bancada)'));
    return;
  end if;
  for x in select * from (values
      ('agenda_textos_do_fechamento', 'public.agenda_textos_do_fechamento(date, date)'),
      ('agenda_fechamento_registrar', 'public.agenda_fechamento_registrar(date, jsonb, text, timestamptz)')) t(nome, assin) loop
    r := pg_temp.ok(r, format('L7a %s: tirados os blocos da 7f, a origem, byte a byte', x.nome),
      char_length(pg_temp.corpo(v_or, x.nome)) > 500 and pg_temp.sem_7f(pg_temp.corpo(v_mig, x.nome)) = replace(pg_temp.corpo(v_or, x.nome), E'\r\n', E'\n'), null);
    r := pg_temp.ok(r, format('L7b %s: a viva é a desta migration', x.nome),
      (select replace(p.prosrc, E'\r\n', E'\n') from pg_proc p where p.oid = x.assin::regprocedure) = pg_temp.corpo(v_mig, x.nome), null);
    r := pg_temp.ok(r, format('L7c %s: o tirador morde: a cópia tem bloco da 7f', x.nome), pg_temp.corpo(v_mig, x.nome) like '%-- FASE 7f:%', null);
    r := pg_temp.ok(r, format('L7c2 %s: nenhum bloco da 7f aberto dentro de outro: os tiradores das etapas de antes não fecham no fim de um bloco de dentro', x.nome),
      not exists (select 1 from (select l, sum(case when l ~ '^\s*-- FASE 7[bcdeg]?:' and l !~ ': fim' then 1 when l ~ '^\s*-- FASE 7[bcdeg]?: fim' then -1 else 0 end) over (order by o) as prof
                                   from unnest(string_to_array(pg_temp.corpo(v_mig, x.nome), E'\n')) with ordinality u(l, o)) y
                   where y.prof > 0 and y.l ~ '^\s*-- FASE 7f:'), null);
  end loop;
  r := pg_temp.ok(r, 'L7d a migration só recria as 2 e cria as 4: agenda_decisoes_abertas, as linhas e as compras ficam (R8.1)',
    (select string_agg(distinct m[1], ',' order by m[1]) from regexp_matches(v_mig, 'create or replace function public\.([a-z_0-9]+)\(', 'g') m)
    = '_agenda_bloco_destino,_agenda_bloco_linha,_agenda_feito_planejado,agenda_bloco_do_fechamento,agenda_fechamento_registrar,agenda_textos_do_fechamento', null);
  r := pg_temp.ok(r, 'L7e sem alter table nem dado: só funções', v_mig !~* '(^|\n)\s*alter\s+table' and v_mig !~* '\n\s*insert into public\.', null);
  perform pg_temp.gravar(r);
end
$l$;

-- ── L8. Decisão N = n ──────────────────────────────────────────────────────────────────────
do $l$
declare
  r jsonb := '[]';
  b jsonb;
  c_agora constant timestamptz := timestamptz '2026-11-10 17:30-03';
  v_ab jsonb;
  v_ruim text;
  v_pos int := 0;
  v_fora int := 0;
  l jsonb;
  v_n int;
begin
  if not pg_temp.na_bancada() then return; end if;
  begin
    perform pg_temp.liga();
    update public.agenda_config set bloco_decisoes_max = 5, bloco_max_chars = 800 where id;
    -- sem as do meio, as críticas de n 2 e 3 sobem no bloco, e a ordem dele deixa de ser a do n: o dono vem antes delas
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste do bloco' where id in (pg_temp.q('02'), pg_temp.q('03'), pg_temp.q('04'), pg_temp.q('05'));
    b := pg_temp.sobre('[]');
    v_ab := public.agenda_decisoes_abertas(c_agora);
    for l in select x from jsonb_array_elements(pg_temp.no_nivel(b, 0)) x where x ->> 'parte' = 'decisao' and x ->> 'pergunta_id' is not null loop
      v_pos := v_pos + 1;
      v_n := (select (e ->> 'n')::int from jsonb_array_elements(v_ab) e where e ->> 'id' = l ->> 'pergunta_id');
      if (substring(l ->> 'texto' from '^· Decisão (\d+):'))::int is distinct from v_n then
        v_ruim := coalesce(v_ruim || ' | ', '') || format('%s: n %s', l ->> 'texto', v_n);
      end if;
      if v_n is not null and v_n <> v_pos then
        v_fora := v_fora + 1;
      end if;
    end loop;
    r := pg_temp.ok(r, 'L8a toda linha: "Decisão N" é o n da pergunta; quem não tem n não ganha número', v_pos >= 3 and v_ruim is null, coalesce(v_ruim, format('%s linhas', v_pos)));
    r := pg_temp.ok(r, 'L8b o controle: a posição no bloco não é o n: se o bloco numerasse pela ordem, a L8a reprovaria', v_fora > 0, format('%s fora', v_fora));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$l$;

-- ── L9. O "Hoje" ───────────────────────────────────────────────────────────────────────────
do $l$
declare
  r jsonb := '[]';
  f jsonb;
  c_h constant date := date '2026-11-12';  -- qui 12/11: 1 meio-dia de Roberto, no Lenine
  v_os uuid := pg_temp.os('302');
begin
  if not pg_temp.na_bancada() then return; end if;
  begin
    perform set_config('agenda.hoje', '2026-11-20', true);
    f := public._agenda_feito_planejado(date '2026-11-14');
    r := pg_temp.ok(r, 'L9a sem plano hoje: texto nulo', f ->> 'texto' is null and (f ->> 'planejados')::int = 0, f::text);
    -- o caso real: 0 de 53 alocações com resultado
    f := public._agenda_feito_planejado(date '2026-11-11');
    r := pg_temp.ok(r, 'L9b nenhum resultado: nunca "feitos", sempre "falta dizer como foi"', f ->> 'texto' = 'Hoje: 3 meios-dias marcados; falta dizer como foi (*dia feito* confirma).' and (f ->> 'pendentes')::int = 3 and (f ->> 'feitos')::numeric = 0, f::text);
    f := public._agenda_feito_planejado(c_h);
    r := pg_temp.ok(r, 'L9c 1 meio-dia: o singular', f ->> 'texto' = 'Hoje: 1 meio-dia marcado; falta dizer como foi (*dia feito* confirma).', f ->> 'texto');
    update public.agenda_alocacoes set resultado = 'cumprido' where dia = c_h and tipo <> 'reserva';
    r := pg_temp.ok(r, 'L9d 1 meio-dia feito', public._agenda_feito_planejado(c_h) ->> 'texto' = 'Hoje: o meio-dia marcado foi feito.', public._agenda_feito_planejado(c_h)::text);
    update public.agenda_alocacoes set resultado = 'cumprido' where dia = date '2026-11-11' and tipo <> 'reserva';
    r := pg_temp.ok(r, 'L9e todos feitos: "foram feitos" só com resultado gravado', public._agenda_feito_planejado(date '2026-11-11') ->> 'texto' = 'Hoje: os 3 meios-dias marcados foram feitos.', public._agenda_feito_planejado(date '2026-11-11')::text);
    update public.agenda_alocacoes set resultado = 'parcial', motivo = 'clima' where id = (select id from public.agenda_alocacoes where dia = date '2026-11-11' and tipo <> 'reserva' order by id limit 1);
    f := public._agenda_feito_planejado(date '2026-11-11');
    r := pg_temp.ok(r, 'L9f parcial conta meio, e a frase diz', f ->> 'texto' like 'Hoje: 2,5 de 3 meios-dias feitos; % em parte (chuva).' and (f ->> 'feitos')::numeric = 2.5, f ->> 'texto');
    update public.agenda_alocacoes set resultado = 'sem_registro', motivo = null where dia = date '2026-11-11' and tipo <> 'reserva';
    f := public._agenda_feito_planejado(date '2026-11-11');
    r := pg_temp.ok(r, 'L9g sem_registro não diz nem feito nem não feito: falta dizer', f ->> 'texto' = 'Hoje: 3 meios-dias marcados; falta dizer como foi (*dia feito* confirma).', f ->> 'texto');
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- a cancelada hoje por material conta como marcada que não aconteceu; a replanejada, não
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_em = timestamptz '2026-11-12 10:00-03', cancelada_motivo = 'material' where dia = c_h and tipo <> 'reserva';
    f := public._agenda_feito_planejado(c_h);
    r := pg_temp.ok(r, 'L9h a cancelada hoje por material: marcada, não feita, com o motivo', f ->> 'texto' = 'Hoje: 0 de 1 meio-dia feitos; Lenine de manhã não (material).' and (f ->> 'planejados')::int = 1 and (f ->> 'pendentes')::int = 0, f ->> 'texto');
    update public.agenda_alocacoes set cancelada_motivo = 'pessoa' where dia = c_h and tipo <> 'reserva';
    r := pg_temp.ok(r, 'L9i a cancelada por pessoa: o motivo em palavra do dono', public._agenda_feito_planejado(c_h) ->> 'texto' like '% não (equipe).', public._agenda_feito_planejado(c_h) ->> 'texto');
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_em = timestamptz '2026-11-11 10:00-03', cancelada_motivo = 'material' where dia = c_h and tipo <> 'reserva';
    r := pg_temp.ok(r, 'L9j a cancelada antes de hoje não estava marcada hoje', public._agenda_feito_planejado(c_h) ->> 'texto' is null, public._agenda_feito_planejado(c_h)::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_em = timestamptz '2026-11-12 10:00-03', cancelada_motivo = 'replanejado' where dia = c_h and tipo <> 'reserva';
    r := pg_temp.ok(r, 'L9k a replanejada hoje não conta', public._agenda_feito_planejado(c_h) ->> 'texto' is null, null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, reserva_de, criado_em)
    select pg_temp.os('306'), a.payee_id, date '2026-11-11', 'tarde', 'turno', 'reserva', 'publicada', 'motor', timestamptz '2026-11-05 16:30-03', 'patio', timestamptz '2026-11-05 16:30-03'
      from public.agenda_alocacoes a where a.service_order_id = pg_temp.os('306') and a.estado = 'publicada' limit 1;
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, criado_em)
    values (pg_temp.os('306'), public._agenda_dono(null), date '2026-11-11', 'manha', 'abertura', 'execucao', 'publicada', 'motor', timestamptz '2026-11-05 16:30-03', timestamptz '2026-11-05 16:30-03');
    r := pg_temp.ok(r, 'L9l nem a reserva nem quem só abre é meio-dia marcado', (select count(*) = 5 from public.agenda_alocacoes x where x.dia = date '2026-11-11' and x.estado = 'publicada')
      and (public._agenda_feito_planejado(date '2026-11-11') ->> 'planejados')::int = 3, public._agenda_feito_planejado(date '2026-11-11')::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  -- as frases do dia que só a linha traz
  begin
    perform pg_temp.liga();
    f := pg_temp.sobre(jsonb_build_array(pg_temp.l('dia', 'Agenda de hoje: Lenine (OS-F2) — Roberto o dia todo. O Roberto confirmou o dia todo e lancei a diária dele (R$ 1.200,00). Hoje era o último dia do Lenine (OS-F2) no plano: terminou? *concluiu Lenine* fecha a OS (saída e cobranças da condição). *diária Roberto meia* corrige. Mudei sozinho: Passei isto. *desfaz Lenine* volta como estava.',
                                               '{"pergunta_id": "f7f00000-0000-4000-8000-000000000501"}')), c_h);
    r := pg_temp.ok(r, 'L9m a diária lançada e o último dia não somem', pg_temp.texto(f, 0) like '%O Roberto confirmou o dia todo e lancei a diária dele (R$ 1.200,00).%' and pg_temp.texto(f, 0) like '%Hoje era o último dia do Lenine (OS-F2) no plano: terminou? *concluiu Lenine* fecha a OS (saída e cobranças da condição).%'
      and pg_temp.texto(f, 0) like '%*diária Roberto meia* corrige.%', pg_temp.texto(f, 0));
    r := pg_temp.ok(r, 'L9n o texto da conferência em si não entra: o Hoje está no lugar dele, e o Mudou é de quem ele é', pg_temp.texto(f, 0) not like '%Agenda de hoje%' and pg_temp.texto(f, 0) not like '%Mudei sozinho%', null);
    r := pg_temp.ok(r, 'L9o elas cedem no nível 2, e o Hoje fica', pg_temp.texto(f, 2) not like '%lancei a diária%' and pg_temp.texto(f, 2) like '%Hoje: 1 meio-dia marcado%', null);
    f := pg_temp.sobre(jsonb_build_array(pg_temp.l('dia', 'A linha do dia.', '{"pergunta_id": "f7f00000-0000-4000-8000-000000000501", "acao_ids": ["f7f00000-0000-4000-8000-000000000601", "f7f00000-0000-4000-8000-000000000604"]}')));
    r := pg_temp.ok(r, 'L9o2 a ação que o Mudou conta não vai também no Hoje', (select l -> 'acao_ids' = '["f7f00000-0000-4000-8000-000000000604"]'::jsonb from jsonb_array_elements(pg_temp.no_nivel(f, 0)) l where l ->> 'parte' = 'hoje' and l ->> 'pergunta_id' is not null), f::text);
    f := pg_temp.sobre(jsonb_build_array(pg_temp.l('dia', 'A linha do dia sem plano.', '{"pergunta_id": "f7f00000-0000-4000-8000-000000000501"}')), date '2026-11-14');
    r := pg_temp.ok(r, 'L9p com a conferência aberta e sem plano hoje, a linha dela não some', pg_temp.texto(f, 0) like '%A linha do dia sem plano.%', pg_temp.texto(f, 0));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$l$;

-- ── L10. As portas ─────────────────────────────────────────────────────────────────────────
do $l$
declare
  r     jsonb := '[]';
  v     text;
  v_tec uuid := 'aa000000-0000-4000-8000-0000000000ff';
  x     record;
begin
  if not pg_temp.na_bancada() then return; end if;
  update public.agenda_config set modo_bloco_agenda = 'ligado' where id;
  for x in select * from (values
      ('_agenda_feito_planejado', $q$select public._agenda_feito_planejado(date '2026-11-10')::text$q$),
      ('_agenda_bloco_destino', $q$select public._agenda_bloco_destino('dia')$q$),
      ('_agenda_bloco_linha', $q$select public._agenda_bloco_linha('hoje', 'x', 0, 1)::text$q$)) t(nome, sql) loop
    r := pg_temp.ok(r, format('L10a %s: service_role, authenticated e anon não alcançam', x.nome),
      pg_temp.como(null, 'service_role', x.sql) like 'erro 42501%' and pg_temp.como(v_tec, 'authenticated', x.sql) like 'erro 42501%' and pg_temp.como(null, 'anon', x.sql) like 'erro 42501%',
      format('%s | %s | %s', pg_temp.como(null, 'service_role', x.sql), pg_temp.como(v_tec, 'authenticated', x.sql), pg_temp.como(null, 'anon', x.sql)));
  end loop;
  v := $q$select public.agenda_bloco_do_fechamento(date '2026-11-10', timestamptz '2026-11-10 17:30-03', '[]') ->> 'modo'$q$;
  r := pg_temp.ok(r, 'L10b agenda_bloco_do_fechamento: anon não; técnico 42501; authenticated sem login 42501; service_role e administrador passam, e por dentro alcançam as sem grant',
    pg_temp.como(null, 'anon', v) like 'erro 42501%' and pg_temp.como(v_tec, 'authenticated', v) like 'erro 42501%' and pg_temp.como(null, 'authenticated', v) like 'erro 42501%'
    and pg_temp.como(null, 'service_role', v) = 'ligado' and pg_temp.como(pg_temp.adm(), 'authenticated', v) = 'ligado',
    format('%s | %s | %s | %s | %s', pg_temp.como(null, 'anon', v), pg_temp.como(v_tec, 'authenticated', v), pg_temp.como(null, 'authenticated', v), pg_temp.como(null, 'service_role', v), pg_temp.como(pg_temp.adm(), 'authenticated', v)));
  r := pg_temp.ok(r, 'L10c anon nem tem o grant; é definer com search_path', not has_function_privilege('anon', 'public.agenda_bloco_do_fechamento(date, timestamptz, jsonb)', 'execute')
    and (select p.prosecdef and p.proconfig = array['search_path=public'] from pg_proc p where p.oid = 'public.agenda_bloco_do_fechamento(date, timestamptz, jsonb)'::regprocedure), null);
  v := $q$select (public.agenda_textos_do_fechamento(date '2026-11-10', date '2026-11-11') ? 'bloco')::text$q$;
  r := pg_temp.ok(r, 'L10d o técnico nem chega ao bloco: agenda_config já é fechada para ele, como antes', pg_temp.como(v_tec, 'authenticated', v) like 'erro P0002%', pg_temp.como(v_tec, 'authenticated', v));
  r := pg_temp.ok(r, 'L10e o service_role e o administrador leem a chave', pg_temp.como(null, 'service_role', v) = 'true' and pg_temp.como(pg_temp.adm(), 'authenticated', v) = 'true', pg_temp.como(null, 'service_role', v));
  v := format('select (public.agenda_fechamento_registrar(date ''2026-11-10'', ''[]'', ''fechamento'', now()))::text');
  r := pg_temp.ok(r, 'L10f agenda_fechamento_registrar: a porta de antes', pg_temp.como(null, 'anon', v) like 'erro 42501%', pg_temp.como(null, 'anon', v));
  update public.agenda_config set modo_bloco_agenda = 'desligado' where id;
  perform pg_temp.gravar(r);
end
$l$;

-- ── L11. O que sai das linhas ──────────────────────────────────────────────────────────────
do $l$
declare
  r jsonb := '[]';
  b jsonb;
  c_txt constant text := 'Mensagem para Vera (véspera), sai qua 11/11 às 09:00: "Amanhã estamos aí às 8h. Está confirmado? Responda SIM.". *manda cliente Vera* ou *segura cliente Vera*. E mais 1: *agenda clientes* mostra; *manda cliente* manda todas.';
  c_cli constant jsonb := pg_temp.l('cliente', 'x');
begin
  if not pg_temp.na_bancada() then return; end if;
  begin
    perform pg_temp.liga();
    -- o que o dono já respondeu não volta
    update public.agenda_perguntas set opcao_escolhida = 1 where id = pg_temp.q('01');
    b := pg_temp.bloco();
    r := pg_temp.ok(r, 'L11a o que o dono já escolheu não volta ao bloco', pg_temp.texto(b, 0) not like '%· Você:%', pg_temp.texto(b, 0));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.liga();
    -- o que o aviso de hoje já levou fica para amanhã; a crítica, não
    insert into public.agenda_dono_avisos (rodada, dia, texto, acao_ids, pergunta_ids, telefone, enviar_em, estado, dedupe_key)
    values (timestamptz '2026-11-10 10:00-03', date '2026-11-10', 'O aviso.', array['f7f00000-0000-4000-8000-000000000601']::uuid[], array[pg_temp.q('01'), pg_temp.q('06')], '5547999999999',
            timestamptz '2026-11-10 10:00-03', 'enfileirada', 'agenda-dono:aviso:teste');
    b := pg_temp.bloco();
    r := pg_temp.ok(r, 'L11b a pergunta que o aviso de hoje levou fica de fora; a crítica fica', pg_temp.texto(b, 0) not like '%· Você:%' and pg_temp.texto(b, 0) like '%Decisão 1: O serviço do Flávio%', pg_temp.texto(b, 0));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.liga();
    -- a mensagem ao cliente: decisão, sem prazo, sem a mensagem inteira, logo depois da crítica que perde amanhã
    b := pg_temp.sobre(jsonb_build_array(c_cli || jsonb_build_object('texto', c_txt, 'pergunta_id', pg_temp.q('04'))));
    r := pg_temp.ok(r, 'L11c a mensagem ao cliente: sem o texto dela, com as palavras e sem prazo',
      (select l ->> 'texto' = '· Mensagem para Vera (véspera), sai qua 11/11 às 09:00. *manda cliente Vera* ou *segura cliente Vera*. E mais 1: *agenda clientes* mostra; *manda cliente* manda todas.'
              and l ->> 'veto_ate' is null
         from jsonb_array_elements(pg_temp.no_nivel(b, 0)) l where l ->> 'pergunta_id' = pg_temp.q('04')::text), pg_temp.texto(b, 0));
    r := pg_temp.ok(r, 'L11d ela entra logo depois da crítica que perde amanhã, antes dos dias do dono',
      (select string_agg(l ->> 'pergunta_id', ',' order by o) from jsonb_array_elements(pg_temp.no_nivel(b, 0)) with ordinality t(l, o) where l ->> 'pergunta_id' is not null)
      = concat_ws(',', pg_temp.q('06'), pg_temp.q('04'), pg_temp.q('01')), pg_temp.texto(b, 0));
    r := pg_temp.ok(r, 'L11e a pergunta dela não aparece 2 vezes', (select count(*) = 1 from jsonb_array_elements(b -> 'linhas') l where l ->> 'pergunta_id' = pg_temp.q('04')::text), null);
    r := pg_temp.ok(r, 'L11f a linha cabe em 220, e a mensagem que não casa com o molde é cortada, nunca inteira',
      (select char_length(l ->> 'texto') <= 222 from jsonb_array_elements(pg_temp.no_nivel(pg_temp.sobre(jsonb_build_array(c_cli || jsonb_build_object('texto', repeat('palavra ', 80), 'pergunta_id', pg_temp.q('04')))), 0)) l where l ->> 'pergunta_id' = pg_temp.q('04')::text), null);
    r := pg_temp.ok(r, 'L11g a mensagem que espera conta nas respostas', split_part(pg_temp.texto(b, 0), E'\n', 1) like 'Agenda: mudei 3 coisas e preciso de 8 respostas suas.%', split_part(pg_temp.texto(b, 0), E'\n', 1));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- sem pergunta na fila, a mensagem ainda sai, sozinha, primeiro
    perform pg_temp.liga();
    perform pg_temp.limpa();
    b := pg_temp.sobre(jsonb_build_array(c_cli || jsonb_build_object('texto', c_txt, 'pergunta_id', pg_temp.q('04'))));
    r := pg_temp.ok(r, 'L11h a mensagem que não está na ordem (a pergunta fora de ligado ou vencida) não some', pg_temp.texto(b, 0) like '%· Mensagem para Vera%' and pg_temp.texto(b, 0) like 'Agenda: preciso de 1 resposta sua.%' and not (b ->> 'nada_mudou')::boolean, pg_temp.texto(b, 0));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$l$;

-- ── L12. O freio ───────────────────────────────────────────────────────────────────────────
do $l$
declare
  r jsonb := '[]';
  b jsonb;
  s jsonb;
begin
  if not pg_temp.na_bancada() then return; end if;
  begin
    perform pg_temp.liga();
    s := pg_temp.bloco();
    update public.agenda_config set gestor_so_propor = true where id;
    b := pg_temp.bloco();
    r := pg_temp.ok(r, 'L12a com *gestor, só propor*, o bloco é ligado: ele não respeita o freio (R8.6)', b ->> 'modo' = 'ligado' and pg_temp.texto(b, 0) like 'Agenda: mudei 3 coisas%', pg_temp.texto(b, 0));
    r := pg_temp.ok(r, 'L12b com o freio, nenhum prazo escrito nem carregado', pg_temp.texto(b, 0) not like '%Sem resposta até%' and char_length(pg_temp.texto(b, 0)) > 100
      and (select bool_and(l ->> 'veto_ate' is null) from jsonb_array_elements(b -> 'linhas') l), pg_temp.texto(b, 0));
    r := pg_temp.ok(r, 'L12c o controle: sem o freio, a mesma fixture escreve o prazo', pg_temp.texto(s, 0) like '%Sem resposta até%', null);
    r := pg_temp.ok(r, 'L12d com o freio, o prazo que seria vai para medir', (select count(*) >= 1 from jsonb_array_elements(b -> 'linhas') l where l ->> 'veto_diria' is not null), null);
    perform public.agenda_fechamento_registrar(date '2026-11-10', pg_temp.no_nivel(b, 0), 'fechamento', timestamptz '2026-11-10 17:45-03');
    r := pg_temp.ok(r, 'L12e o registro com o freio não liga relógio nenhum: mostra, e só mede',
      (select x.veto_ate is null and x.mostrada_vezes = 1 and x.veto_teria_em is not null from public.agenda_perguntas x where x.id = pg_temp.q('01')), null);
    perform public._agenda_gestor_vetos(date '2026-11-11', timestamptz '2026-11-11 18:05-03');
    r := pg_temp.ok(r, 'L12f e no prazo que seria nada vence', (select x.estado = 'aberta' from public.agenda_perguntas x where x.id = pg_temp.q('01')), null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- modo_veto em sombra, sem o freio: o mesmo
    perform pg_temp.liga();
    update public.agenda_config set modo_veto = 'sombra' where id;
    b := pg_temp.bloco();
    r := pg_temp.ok(r, 'L12g prazo em sombra: bloco sem "Sem resposta até", e com o que seria', pg_temp.texto(b, 0) not like '%Sem resposta até%' and (select count(*) >= 1 from jsonb_array_elements(b -> 'linhas') l where l ->> 'veto_diria' is not null), null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$l$;

select teste, ok, detalhe from _resultado order by ok, teste;
rollback;
