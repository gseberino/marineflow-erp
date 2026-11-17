-- Prova das perguntas com prazo no bloco da agenda (17/11/2026; migration 20270122100000; plano agenda-pesquisa/perguntas-com-prazo-1711/PLANO.md, FASE 1, com as respostas
-- do dono 1A e 2A): a linha (m) das perguntas do gestor com prazo (perda 76) volta ao fechamento das 17:30 como decisão do bloco.
-- bancada: depende de 20270122100000
--
--   P0  a cópia: tirados os blocos "-- PRAZO NO BLOCO:", o corpo vivo é o de 20261109100200 (o de produção em 17/11), byte a byte; a porta e o comentário; e o mesmo
--       para a saúde (_agenda_saude_comunicacao, a de 20261109101200); só essas 2 funções têm os blocos
--   P1  sem a linha do gestor, a saída de antes, byte a byte (a função de 20261109100200 rodando como pg_temp): a fixture da 7f, os níveis, o cliente, as vagas, a (m) sem
--       prazo; e a contraprova em sombra (a vigia em sombra: a (m) chega em sombra; o bloco em sombra: o texto do dono não muda)
--   P2  com a linha do gestor: entra logo depois da crítica que perde amanhã e antes do cliente, nunca é cortada (a inteira até o nível 2, a curta dali em diante), a ordem
--       fica sem nenhuma dos 4 tipos com prazo (também a que não está na linha), a ficha do dia entra, o veredito conta o mesmo, as vagas
--   P3  2 fichas no mesmo dia: a inteira escreve e leva as 2; a curta só escreve e só leva a 1ª
--   P4  o registro, pelo caminho do Secretário (agenda_fechamento_guardar + a fila mandou + o tique): conta como mostradas só as do nível que saiu; a ficha mostrada antes do
--       prazo vence nele ("sem resposta até …: a ficha vai como eu disse", sem assumida_por); a 2ª ficha, que não apareceu, não vence; mostrada depois do prazo, não vence
--   P5  de ponta a ponta com o gestor de verdade (o replay de 29/10): a situacao com prazo que o gestor perguntou sai no bloco, é registrada e vence no prazo (resolvida,
--       opcao_escolhida = opcao_padrao, "sem resposta até …", assumida_por nulo); com o bloco de antes ela saía pela ordem, cortada e sem a data do prazo (a armadilha); sem registro, não vence; mostrada só
--       depois do prazo, também não. Roda logo depois do P0, antes de a fixture da 7f entrar (o replay puro, como no Y1 de agenda_fase77a_correcao2.sql).
--   P6  a saúde (revisão da F1): o fechamento acima de 1.000 no mínimo do bloco com a linha do gestor (a crítica, a do gestor e a do cliente, as 3 que nunca saem) não é
--       bloco_grande (na saúde de antes era: o achado); acima do mínimo, com uma decisão da ordem que ainda podia sair, é, nas duas; com a do gestor em 1º, a tolerância
--       é 1 a menos; sem a linha do gestor, a saúde é a de antes, byte a byte (a função de 20261109101200 rodando como pg_temp); e nunca conta mais que a de antes
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Fora dela sai PULADO: tudo aqui usa as fixtures e as migrations como texto, que nunca rodam em produção.
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
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  if position(format('create or replace function public.%s(', p_nome) in v) = 0 then return ''; end if;
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'\nas $function$' in v) + length(E'\nas $function$'));
  return left(v, position('$function$' in v) - 1);
end $f$;
-- O texto sem os blocos "-- PRAZO NO BLOCO: … -- PRAZO NO BLOCO: fim" (as linhas de abrir e de fechar saem junto).
create function pg_temp.sem_prazo(p text) returns text language sql immutable as $f$
  select array_to_string(array(
           select l from (select l, o, sum(case when l ~ '^\s*-- PRAZO NO BLOCO:' and l !~ '^\s*-- PRAZO NO BLOCO: fim' then 1
                                                when l ~ '^\s*-- PRAZO NO BLOCO: fim' then -1 else 0 end)
                                       over (order by o rows between unbounded preceding and current row) as dentro,
                                 l ~ '^\s*-- PRAZO NO BLOCO: fim' as fecha
                            from unnest(string_to_array(replace(p, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o)) x
            where dentro = 0 and not fecha order by o), E'\n')
$f$;
create function pg_temp.na_bancada() returns boolean language sql stable as $f$
  select coalesce(current_setting('agenda_teste.fase7f', true), '') <> ''
     and coalesce(current_setting('agenda_teste.mig_bloco_fase7f', true), '') <> ''
     and coalesce(current_setting('agenda_teste.mig_mudou_fase7f', true), '') <> ''
     and coalesce(current_setting('agenda_teste.replay2910', true), '') <> ''
$f$;
-- as perguntas e as OS da fixture da 7f; as perguntas de prazo deste teste
create function pg_temp.q(p_c text) returns uuid language sql immutable as $f$ select ('f7f00000-0000-4000-8000-0000000005' || p_c)::uuid $f$;
create function pg_temp.osf(p_n text) returns uuid language sql immutable as $f$ select ('f7f00000-0000-4000-8000-000000097' || p_n)::uuid $f$;
create function pg_temp.g(p_c text) returns uuid language sql immutable as $f$ select ('b10c0000-0000-4000-8000-0000000000' || p_c)::uuid $f$;
-- as OS do replay, pelo número
create function pg_temp.os_num(p_numero text) returns uuid language sql stable as $f$
  select so.id from public.service_orders so where so.service_order_number = p_numero
$f$;
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
-- O bloco valendo, o prazo valendo, sem o freio; a vigia ligada (a linha (m) só vem ligada com ela) e a equipe ligada (o modo da ficha_estimativa).
create function pg_temp.liga() returns void language sql as $f$
  update public.agenda_config
     set modo_bloco_agenda = 'ligado', modo_veto = 'ligado', gestor_so_propor = false, modo_proposta = 'ligado', modo_vigia = 'ligado', modo_equipe = 'ligado'
   where id
$f$;
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
-- As perguntas das linhas de decisão de um nível, na ordem, pelo nome curto (g01 = a 1ª ficha, q06 = a crítica da fixture …).
create function pg_temp.decs(p_b jsonb, p_n int) returns text language sql stable as $f$
  select string_agg(case when l ->> 'pergunta_id' like 'b10c0000%' then 'g' || right(l ->> 'pergunta_id', 2)
                         when l ->> 'pergunta_id' like 'f7f00000%' then 'q' || right(l ->> 'pergunta_id', 2)
                         else l ->> 'pergunta_id' end, ',' order by o)
    from jsonb_array_elements(pg_temp.no_nivel(p_b, p_n)) with ordinality t(l, o)
   where l ->> 'parte' = 'decisao' and l ->> 'pergunta_id' is not null
$f$;
-- As linhas do fechamento do dia (o que agenda_textos_do_fechamento passa ao bloco), às 17:30.
create function pg_temp.linhas(p_hoje date default date '2026-11-10') returns jsonb language plpgsql as $f$
begin
  perform set_config('agenda.agora', ((p_hoje + time '17:30') at time zone 'America/Sao_Paulo')::text, true);
  return public._agenda_linhas_do_fechamento(p_hoje);
end $f$;
-- O bloco novo e o de antes (a função de 20261109100200, como pg_temp.bloco_7f), sobre as mesmas linhas, às 17:30.
create function pg_temp.sobre(p_linhas jsonb, p_hoje date default date '2026-11-10') returns jsonb language sql as $f$
  select public.agenda_bloco_do_fechamento(p_hoje, (p_hoje + time '17:30') at time zone 'America/Sao_Paulo', p_linhas)
$f$;
create function pg_temp.antes(p_linhas jsonb, p_hoje date default date '2026-11-10') returns jsonb language plpgsql as $f$
begin
  return pg_temp.bloco_7f(p_hoje, (p_hoje + time '17:30') at time zone 'America/Sao_Paulo', p_linhas);
end $f$;
-- O bloco que agenda_textos_do_fechamento mandaria às 17:30 do dia (o caminho de verdade).
create function pg_temp.bloco(p_hoje date default date '2026-11-10') returns jsonb language plpgsql as $f$
begin
  perform set_config('agenda.agora', ((p_hoje + time '17:30') at time zone 'America/Sao_Paulo')::text, true);
  return public.agenda_textos_do_fechamento(p_hoje, public.agenda_somar_du(p_hoje, 1)) -> 'bloco';
end $f$;
create function pg_temp.l(p_tipo text, p_texto text, p_extra jsonb default '{}') returns jsonb language sql immutable as $f$
  select jsonb_build_object('tipo', p_tipo, 'texto', p_texto, 'perda', 50, 'pergunta_id', null, 'acao_ids', '[]'::jsonb, 'modo', 'ligado') || p_extra
$f$;
-- As linhas no formato que o Secretário manda ao registro (registrarAgendaDoFechamento, secretario-tarde.ts): pergunta_id, acao_ids, e pergunta_ids, veto_ate e veto_diria
-- só quando vêm.
create function pg_temp.do_ts(p jsonb) returns jsonb language sql immutable as $f$
  select coalesce(jsonb_agg(jsonb_build_object('pergunta_id', l -> 'pergunta_id', 'acao_ids', coalesce(l -> 'acao_ids', '[]'::jsonb))
                            || case when jsonb_typeof(l -> 'pergunta_ids') = 'array' and jsonb_array_length(l -> 'pergunta_ids') > 0
                                    then jsonb_build_object('pergunta_ids', l -> 'pergunta_ids') else '{}'::jsonb end
                            || case when jsonb_typeof(l -> 'veto_ate') = 'string' then jsonb_build_object('veto_ate', l -> 'veto_ate') else '{}'::jsonb end
                            || case when jsonb_typeof(l -> 'veto_diria') = 'string' then jsonb_build_object('veto_diria', l -> 'veto_diria') else '{}'::jsonb end
                            order by o), '[]'::jsonb)
    from jsonb_array_elements(p) with ordinality t(l, o)
$f$;
-- A linha da fila da tarde (a chave de resumo_tarde_registrar), pendente.
create function pg_temp.fila_da_tarde(p_dia date) returns uuid language sql as $f$
  insert into public.whatsapp_send_queue (phone_normalized, message, source, priority, max_attempts, dedupe_key)
  values ('5547900000210', 'Fechamento de teste', 'ai_briefing_tarde', 5, 3, 'secretario_tarde:' || p_dia || ':5547900000210')
  returning id
$f$;
create function pg_temp.vezes(p uuid) returns int language sql stable as $f$
  select q.mostrada_vezes from public.agenda_perguntas q where q.id = p
$f$;
-- As perguntas do gestor com prazo, na forma em que o gestor as grava (_agenda_gestor_perguntar; os textos com o tamanho e o prazo dos reais), sobre a fixture da 7f
-- (ter 10/11/2026): g01 a ficha_estimativa do Alex para amanhã (o prazo é a hora da ficha, hoje 19:30); g03 a situacao do Giancarlo e g04 a estimativa do Tadeu (prazo
-- qua 11/11 18:00); g05 a situacao do Lenine com o prazo de ontem, que passou sem ser mostrada (fora da linha (m), que só leva prazo de hoje em diante, e ainda aberta na
-- ordem). Com p_duas, g02 a ficha_estimativa do Roberto para amanhã (a 2ª ficha do dia).
create function pg_temp.perguntas_de_prazo(p_duas boolean default false) returns void language plpgsql as $f$
declare
  v_alex uuid := (select id from public.payees where name = 'Alex' and active order by id limit 1);
  v_rob  uuid := (select id from public.payees where name = 'Roberto' and active order by id limit 1);
  c_ficha constant jsonb := '[{"n": 1, "texto": "Mande", "efeito": {"mandar": true}}, {"n": 2, "texto": "Segure a ficha: eu não mando e você fala com ele", "efeito": {"segurar": true}}]';
  c_dias  constant jsonb := '[{"n": 1, "texto": "Conta 1 dia", "efeito": {"dias": 1, "feito": "contei 1 dia"}}, {"n": 2, "texto": "Eu digo os dias", "efeito": {"dizer": true}}]';
begin
  insert into public.agenda_perguntas (id, tipo, chave, service_order_id, os_ids, perda_em, texto, opcoes, recomendacao, opcao_padrao, modo, criada_em, expira_em, veto_ate)
  values
    (pg_temp.g('01'), 'ficha_estimativa', format('ficha_estimativa:%s:2026-11-11', v_alex), pg_temp.osf('303'), array[pg_temp.osf('303')], date '2026-11-10',
     'Hoje às 19:30 a ficha de amanhã vai para Alex: Vanderlei, qua 11/11 de manhã — dia 2 de 2, pela minha estimativa. 1) Mande (recomendo); 2) Segure a ficha: eu não mando e você fala com ele.',
     c_ficha, 1, 1, 'ligado', timestamptz '2026-11-10 16:50-03', timestamptz '2026-11-11 19:30-03', timestamptz '2026-11-10 19:30-03'),
    (pg_temp.g('03'), 'situacao', 'situacao:' || pg_temp.osf('305') || ':comecada', pg_temp.osf('305'), array[pg_temp.osf('305')], date '2026-11-11',
     'O serviço do Giancarlo (lancha, Troca do GPS) já começou? Pelo orçamento, conto 1 dia de trabalho. Sem resposta até qua 11/11 às 18:00, conto 1 dia.',
     c_dias, 1, 1, 'ligado', timestamptz '2026-11-10 16:51-03', timestamptz '2026-11-12 18:00-03', timestamptz '2026-11-11 18:00-03'),
    (pg_temp.g('04'), 'estimativa', 'estimativa:' || pg_temp.osf('306'), pg_temp.osf('306'), array[pg_temp.osf('306')], date '2026-11-11',
     'Quantos dias leva a Instalação de placa solar do Tadeu? Pelo orçamento, conto 1 dia; sem resposta até qua 11/11 às 18:00, fica assim.',
     c_dias, 1, 1, 'ligado', timestamptz '2026-11-10 16:52-03', timestamptz '2026-11-12 18:00-03', timestamptz '2026-11-11 18:00-03'),
    (pg_temp.g('05'), 'situacao', 'situacao:' || pg_temp.osf('302') || ':comecada', pg_temp.osf('302'), array[pg_temp.osf('302')], date '2026-11-09',
     'O serviço do Lenine (motorhome, Troca do inversor) já começou? Pelo orçamento, conto 3 dias de trabalho. Sem resposta até seg 09/11 às 18:00, conto 3 dias.',
     c_dias, 1, 1, 'ligado', timestamptz '2026-11-09 10:00-03', timestamptz '2026-11-12 18:00-03', timestamptz '2026-11-09 18:00-03');
  if p_duas then
    insert into public.agenda_perguntas (id, tipo, chave, service_order_id, os_ids, perda_em, texto, opcoes, recomendacao, opcao_padrao, modo, criada_em, expira_em, veto_ate)
    values (pg_temp.g('02'), 'ficha_estimativa', format('ficha_estimativa:%s:2026-11-11', v_rob), pg_temp.osf('304'), array[pg_temp.osf('304')], date '2026-11-10',
            'Hoje às 19:30 a ficha de amanhã vai para Roberto: Flávio, qua 11/11 o dia todo — dia 1 de 1, pela minha estimativa. 1) Mande (recomendo); 2) Segure a ficha: eu não mando e você fala com ele.',
            c_ficha, 1, 1, 'ligado', timestamptz '2026-11-10 16:50:30-03', timestamptz '2026-11-11 19:30-03', timestamptz '2026-11-10 19:30-03');
  end if;
end $f$;
-- (P6) As linhas do bloco como o Secretário as grava no detalhe (secretario-tarde.ts: bloco_diria.linhas e bloco_mostrou = {parte, texto}; o texto como blocoDaAgenda o
-- deixa, com os espaços juntados); com p_so_decisoes, só o veredito e as decisões (para medir só a conta das decisões).
create function pg_temp.do_secretario(p jsonb, p_so_decisoes boolean default false) returns jsonb language sql immutable as $f$
  select coalesce(jsonb_agg(jsonb_build_object('parte', l ->> 'parte', 'texto', btrim(regexp_replace(l ->> 'texto', '\s+', ' ', 'g'))) order by o), '[]'::jsonb)
    from jsonb_array_elements(p) with ordinality t(l, o)
   where not p_so_decisoes or l ->> 'parte' in ('veredito', 'decisao')
$f$;
-- (P6) Um fechamento ligado gravado em resumo_tarde como o Secretário o grava (detalhe.caracteres; detalhe.agenda: bloco_diria, bloco_mostrou no nível que saiu e
-- linhas_diria = as linhas que a agenda diria, {tipo, perda, modo, texto}). Em plpgsql: a tabela só nasce no P6.
create function pg_temp.tarde(p_dia date, p_chars int, p_linhas jsonb, p_b jsonb, p_nivel int, p_so_decisoes boolean default false) returns void language plpgsql as $f$
begin
  insert into public.resumo_tarde (dia, phone_normalized, turno, modo, formato, texto, detalhe)
  values (p_dia, '5547900000210', 'fechamento', 'novo', 'ligado', 'Fechamento de teste.',
          jsonb_build_object('caracteres', p_chars, 'agenda', jsonb_build_object(
            'modo', 'ligado',
            'bloco_diria', jsonb_build_object('modo', p_b ->> 'modo', 'nivel', (p_b ->> 'nivel')::int, 'chars', (p_b ->> 'chars')::int,
                                              'nada_mudou', (p_b ->> 'nada_mudou')::boolean, 'incompleto', (p_b ->> 'incompleto')::boolean,
                                              'linhas', pg_temp.do_secretario(pg_temp.no_nivel(p_b, (p_b ->> 'nivel')::int))),
            'bloco_mostrou', pg_temp.do_secretario(pg_temp.no_nivel(p_b, p_nivel), p_so_decisoes),
            'linhas_diria', (select coalesce(jsonb_agg(jsonb_build_object('tipo', l -> 'tipo', 'perda', l -> 'perda', 'modo', l -> 'modo', 'texto', l -> 'texto') order by o), '[]'::jsonb)
                               from jsonb_array_elements(p_linhas) with ordinality t(l, o)))));
end $f$;
-- A subtransação que se desfaz: o caso mexe no estado à vontade.
create function pg_temp.desfaz() returns void language plpgsql as $f$
begin
  raise exception using errcode = 'P0001', message = '__desfaz__';
end $f$;

-- A função de antes (20261109100200, a de produção em 17/11), como pg_temp: a régua do "byte a byte".
do $c$
begin
  if coalesce(current_setting('agenda_teste.mig_bloco_fase7f', true), '') <> '' then
    execute format('create function pg_temp.bloco_7f(p_hoje date, p_agora timestamptz, p_linhas jsonb) returns jsonb language plpgsql stable as %L',
                   pg_temp.corpo(current_setting('agenda_teste.mig_bloco_fase7f'), 'agenda_bloco_do_fechamento'));
  end if;
  -- (P6) a saúde de antes (20261109101200, a de produção em 17/11), do mesmo jeito
  if coalesce(current_setting('agenda_teste.mig_mudou_fase7f', true), '') <> '' then
    execute format('create function pg_temp.saude_7f(p_hoje date, p_agora timestamptz) returns jsonb language plpgsql stable set search_path to ''public'' as %L',
                   pg_temp.corpo(current_setting('agenda_teste.mig_mudou_fase7f'), '_agenda_saude_comunicacao'));
  end if;
end
$c$;

-- ── P0. A cópia, a porta e o comentário ───────────────────────────────────────────────────
do $p$
declare
  r     jsonb := '[]';
  v     text;
  v_7f  text;
begin
  if not pg_temp.na_bancada() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'P o prazo no bloco', true, 'PULADO: sem as fixtures e as migrations como texto (rode pela bancada)'));
    return;
  end if;
  select replace(p.prosrc, E'\r\n', E'\n') into v from pg_proc p where p.oid = 'public.agenda_bloco_do_fechamento(date, timestamptz, jsonb)'::regprocedure;
  v_7f := pg_temp.corpo(current_setting('agenda_teste.mig_bloco_fase7f'), 'agenda_bloco_do_fechamento');
  r := pg_temp.ok(r, 'P0a tirados os blocos "-- PRAZO NO BLOCO:", o corpo vivo é o de 20261109100200, byte a byte',
    char_length(v_7f) > 5000 and pg_temp.sem_prazo(v) = v_7f, format('vivo %s letras; sem os blocos %s; 7f %s', length(v), length(pg_temp.sem_prazo(v)), length(v_7f)));
  r := pg_temp.ok(r, 'P0b o tirador morde: o corpo vivo tem os 8 blocos, e nenhum abre dentro de outro',
    (select count(*) from regexp_matches(v, '-- PRAZO NO BLOCO: fim', 'g')) = 8
    and not exists (select 1 from (select l, sum(case when l ~ '^\s*-- PRAZO NO BLOCO:' and l !~ ': fim' then 1 when l ~ '^\s*-- PRAZO NO BLOCO: fim' then -1 else 0 end)
                                              over (order by o) as prof
                                     from unnest(string_to_array(v, E'\n')) with ordinality u(l, o)) y
                     where y.prof > 1 or y.prof < 0), null);
  r := pg_temp.ok(r, 'P0c o corpo de 20261109100200 é o de produção em 17/11 (md5 69b35d93…): a cópia partiu da definição viva', md5(v_7f) = '69b35d93a6031f5b40a94e9b1aec94f9', md5(v_7f));
  r := pg_temp.ok(r, 'P0d a porta de produção: definer, stable, search_path=public; anon e PUBLIC não executam; authenticated e service_role, sim',
    (select p.prosecdef and p.provolatile = 's' and p.proconfig = array['search_path=public'] from pg_proc p where p.oid = 'public.agenda_bloco_do_fechamento(date, timestamptz, jsonb)'::regprocedure)
    and not has_function_privilege('anon', 'public.agenda_bloco_do_fechamento(date, timestamptz, jsonb)', 'execute')
    and not has_function_privilege('public', 'public.agenda_bloco_do_fechamento(date, timestamptz, jsonb)', 'execute')
    and has_function_privilege('authenticated', 'public.agenda_bloco_do_fechamento(date, timestamptz, jsonb)', 'execute')
    and has_function_privilege('service_role', 'public.agenda_bloco_do_fechamento(date, timestamptz, jsonb)', 'execute'), null);
  r := pg_temp.ok(r, 'P0e o comentário guarda o de antes inteiro e acrescenta o PRAZO NO BLOCO',
    obj_description('public.agenda_bloco_do_fechamento(date, timestamptz, jsonb)'::regprocedure, 'pg_proc')
      like 'Agenda de Produção (Fase 7f, P3; §5.3, §6.1, R8.4, R8.5-15, R8.7, R8.8): o bloco da agenda na tarde, %Administrador, financeiro ou service_role; senão 42501. PRAZO NO BLOCO (17/11/2026, 20270122100000;%', null);
  -- a saúde (revisão da F1): a mesma régua
  select replace(p.prosrc, E'\r\n', E'\n') into v from pg_proc p where p.oid = 'public._agenda_saude_comunicacao(date, timestamptz)'::regprocedure;
  v_7f := pg_temp.corpo(current_setting('agenda_teste.mig_mudou_fase7f'), '_agenda_saude_comunicacao');
  r := pg_temp.ok(r, 'P0f a saúde: tirado o bloco "-- PRAZO NO BLOCO:", o corpo vivo de _agenda_saude_comunicacao é o de 20261109101200, byte a byte; e o bloco é 1 só',
    char_length(v_7f) > 5000 and pg_temp.sem_prazo(v) = v_7f and (select count(*) from regexp_matches(v, '-- PRAZO NO BLOCO: fim', 'g')) = 1,
    format('vivo %s letras; sem o bloco %s; 7f %s', length(v), length(pg_temp.sem_prazo(v)), length(v_7f)));
  r := pg_temp.ok(r, 'P0g a saúde: o corpo de 20261109101200 é o de produção em 17/11 (md5 6288e345…): a cópia partiu da definição viva', md5(v_7f) = '6288e345b16e1692b39dd8032ec304ea', md5(v_7f));
  r := pg_temp.ok(r, 'P0h a saúde: a porta de produção (definer, stable, search_path=public; anon e PUBLIC não executam; authenticated e service_role, sim)',
    (select p.prosecdef and p.provolatile = 's' and p.proconfig = array['search_path=public'] from pg_proc p where p.oid = 'public._agenda_saude_comunicacao(date, timestamptz)'::regprocedure)
    and not has_function_privilege('anon', 'public._agenda_saude_comunicacao(date, timestamptz)', 'execute')
    and not has_function_privilege('public', 'public._agenda_saude_comunicacao(date, timestamptz)', 'execute')
    and has_function_privilege('authenticated', 'public._agenda_saude_comunicacao(date, timestamptz)', 'execute')
    and has_function_privilege('service_role', 'public._agenda_saude_comunicacao(date, timestamptz)', 'execute'), null);
  r := pg_temp.ok(r, 'P0i a saúde: o comentário de produção inteiro (md5 856d0bd4…) e o PRAZO NO BLOCO acrescentado no fim',
    md5(split_part(obj_description('public._agenda_saude_comunicacao(date, timestamptz)'::regprocedure, 'pg_proc'), ' PRAZO NO BLOCO (17/11/2026', 1)) = '856d0bd4519239b11f49276638f88a85'
    and obj_description('public._agenda_saude_comunicacao(date, timestamptz)'::regprocedure, 'pg_proc') like '% PRAZO NO BLOCO (17/11/2026, 20270122100000;%bloco_grande%',
    md5(split_part(obj_description('public._agenda_saude_comunicacao(date, timestamptz)'::regprocedure, 'pg_proc'), ' PRAZO NO BLOCO (17/11/2026', 1)));
  r := pg_temp.ok(r, 'P0j só as 2 funções desta migration têm os blocos "-- PRAZO NO BLOCO:"',
    (select string_agg(p.proname, ',' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosrc like '%-- PRAZO NO BLOCO:%')
      = '_agenda_saude_comunicacao,agenda_bloco_do_fechamento',
    (select string_agg(p.proname, ',' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosrc like '%-- PRAZO NO BLOCO:%'));
  perform pg_temp.gravar(r);
end
$p$;

-- ── P5. De ponta a ponta com o gestor de verdade (o replay de 29/10, sem a fixture da 7f) ─────
do $p$
declare
  r      jsonb := '[]';
  c_sex  constant date := date '2026-10-30';
  c_ter  constant date := date '2026-11-03';
  v_nel  uuid;
  v_lin  jsonb;
  v_m    jsonb;
  b      jsonb;
  v_q    uuid;
  q      public.agenda_perguntas;
  v_det  text;
begin
  if not pg_temp.na_bancada() then return; end if;
  -- Roda ANTES do P1 (que carrega a fixture da 7f por cima do replay): aqui é o replay puro, como no Y1 de agenda_fase77a_correcao2.sql, e tudo se desfaz no fim.
  begin
    execute current_setting('agenda_teste.replay2910');
    insert into public.os_planejamento (service_order_id, dono_presenca)
    select so.id, 'abre_e_fecha' from public.service_orders so where so.service_order_number in ('OS-00074', 'OS-00069')
    on conflict (service_order_id) do update set dono_presenca = 'abre_e_fecha';
    update public.agenda_config
       set modo_marcar_sozinho = 'ligado', modo_encaixe_aprovacao = 'ligado', modo_revisao_diaria = 'ligado', modo_compre_ate = 'ligado',
           modo_vaga_fechamento = 'ligado', gestor_so_propor = false, gestor_so_propor_em = null,
           marcar_sozinho_desde = timestamptz '2026-10-29 16:46-03',
           marcar_regras = '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada,sinal_cobrar}'
     where id;
    v_nel := pg_temp.os_num('OS-00112');
    perform public.agenda_gestor_rodar(c_sex, pg_temp.em(c_sex, '16:53'));
    -- o fechamento de sex 17:30 com o bloco ligado, a vigia ligada (a linha (m) só vem ligada com ela) e o prazo ligado
    perform pg_temp.liga();
    v_lin := public._agenda_linhas_do_fechamento(c_sex);
    v_m := (select l from jsonb_array_elements(v_lin) l where l ->> 'tipo' = 'pergunta' and l -> 'perda' = '76'::jsonb and l ->> 'modo' = 'ligado');
    v_q := (select x.id from public.agenda_perguntas x where x.service_order_id = v_nel and x.tipo in ('situacao', 'estimativa') and x.estado = 'aberta' and x.modo = 'ligado'
                                                         and x.veto_ate is not null order by x.criada_em desc limit 1);
    r := pg_temp.ok(r, 'P5a o gestor (sex 30/10 16:53) pergunta a do Nelson (OS-00112) com prazo, e a linha (m) ligada de perda 76 a leva',
      v_q is not null and v_m -> 'pergunta_ids' @> to_jsonb(array[v_q::text]), coalesce(v_m::text, 'sem a linha (m)') || ' | ' || coalesce(v_q::text, 'sem a pergunta'));
    b := public.agenda_bloco_do_fechamento(c_sex, pg_temp.em(c_sex, '17:30'), v_lin);
    r := pg_temp.ok(r, 'P5b o bloco das 17:30 a mostra, como decisão, em todos os níveis',
      (select bool_and(exists (select 1 from jsonb_array_elements(pg_temp.no_nivel(b, k)) l where l ->> 'parte' = 'decisao' and l -> 'pergunta_ids' @> to_jsonb(array[v_q::text])))
         from generate_series(0, (b ->> 'nivel_min')::int) k), pg_temp.texto(b, (b ->> 'nivel')::int));
    -- o controle (a armadilha do PLANO): o bloco de antes descartava a linha (m), e aqui, com a ordem curta, a do Nelson saía pela ordem numa linha cortada em 220 letras,
    -- sem a data ("… Se você não me…"): mostrada assim, o prazo a decidiria sem o dono ter lido até quando. O novo a leva só na linha do gestor (as 2 formas, com as outras
    -- perguntas dela), com a data escrita nas duas. A 1ª da linha (MP ou Nelson, criadas na mesma hora) sai pelo id: o teste não depende de qual.
    r := pg_temp.ok(r, 'P5c o controle: o bloco de antes a levava pela ordem, cortada e sem a data do prazo; o novo, só na linha do gestor, com a data (ter 03/11 18:00) na inteira e na curta',
      exists (select 1 from jsonb_array_elements(pg_temp.bloco_7f(c_sex, pg_temp.em(c_sex, '17:30'), v_lin) -> 'linhas') l
               where l ->> 'pergunta_id' = v_q::text and l ->> 'texto' like '%…' and l ->> 'texto' not like '%03/11%')
      and (select count(*) = 2 and bool_and(l ->> 'texto' like '%Nelson (OS-00112)%' and l ->> 'texto' ~ 'ter 03/11 (às )?18:00' and jsonb_array_length(l -> 'pergunta_ids') > 1)
             from jsonb_array_elements(b -> 'linhas') l where l -> 'pergunta_ids' @> to_jsonb(array[v_q::text])),
      (select string_agg(format('[%s-%s] %s', l ->> 'nivel_entra', coalesce(l ->> 'nivel_de_corte', '-'), l ->> 'texto'), ' || ')
         from jsonb_array_elements(pg_temp.bloco_7f(c_sex, pg_temp.em(c_sex, '17:30'), v_lin) -> 'linhas') l where l ->> 'parte' = 'decisao')
      || ' ## novo: ' || (select string_agg(format('[%s-%s] %s', l ->> 'nivel_entra', coalesce(l ->> 'nivel_de_corte', '-'), l ->> 'texto'), ' || ')
         from jsonb_array_elements(b -> 'linhas') l where l ->> 'parte' = 'decisao'));
    begin
      -- sem o registro do fechamento (o dono não a viu): no tique depois do prazo ela não vence
      perform public._agenda_gestor_vetos(c_ter, (select x.veto_ate from public.agenda_perguntas x where x.id = v_q) + interval '7 minutes');
      select * into q from public.agenda_perguntas x where x.id = v_q;
      v_det := format('%s | %s', q.estado, q.resolvida_motivo);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    r := pg_temp.ok(r, 'P5d sem o registro do fechamento (o dono não a viu), no tique depois do prazo ela não vence: segue aberta', v_det like 'aberta | %', v_det);
    begin
      -- mostrada só depois do prazo: não vence
      perform public.agenda_fechamento_registrar(c_ter, pg_temp.do_ts(pg_temp.no_nivel(b, (b ->> 'nivel')::int)), 'fechamento',
                                                 (select x.veto_ate from public.agenda_perguntas x where x.id = v_q) + interval '30 minutes');
      perform public._agenda_gestor_vetos(c_ter, (select x.veto_ate from public.agenda_perguntas x where x.id = v_q) + interval '45 minutes');
      select * into q from public.agenda_perguntas x where x.id = v_q;
      v_det := format('%s | %s | vezes %s', q.estado, q.resolvida_motivo, q.mostrada_vezes);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    r := pg_temp.ok(r, 'P5e mostrada só depois do prazo, não vence: segue aberta', v_det like 'aberta | % | vezes 1', v_det);
    -- o caminho de verdade: o fechamento de sex 17:30 sai no nível dado, e no tique depois do prazo ela vence
    perform public.agenda_fechamento_registrar(c_sex, pg_temp.do_ts(pg_temp.no_nivel(b, (b ->> 'nivel')::int)), 'fechamento', pg_temp.em(c_sex, '17:35'));
    perform public._agenda_gestor_vetos(c_ter, (select x.veto_ate from public.agenda_perguntas x where x.id = v_q) + interval '7 minutes');
    select * into q from public.agenda_perguntas x where x.id = v_q;
    r := pg_temp.ok(r, 'P5f mostrada no bloco antes do prazo, ela vence nele: resolvida, opcao_escolhida = opcao_padrao, "sem resposta até …: ficou como eu disse", assumida_por nulo',
      q.mostrada_vezes = 1 and q.mostrada_em = pg_temp.em(c_sex, '17:35') and q.estado = 'resolvida' and q.opcao_escolhida = q.opcao_padrao
      and q.resolvida_motivo like 'sem resposta até %' and q.resolvida_motivo like '%como eu disse' and q.assumida_por is null,
      format('%s | %s | %s | escolhida %s padrão %s | vezes %s', q.estado, q.resolvida_motivo, q.assumida_por, q.opcao_escolhida, q.opcao_padrao, q.mostrada_vezes));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  update public.agenda_config set modo_bloco_agenda = 'desligado' where id;
  perform pg_temp.gravar(r);
end
$p$;

-- ── P1. Sem a linha do gestor: a de antes, byte a byte ─────────────────────────────────────
do $p$
declare
  r     jsonb := '[]';
  v_lin jsonb;
  b     jsonb;
  a     jsonb;
  x     record;
  c_txt constant text := 'Mensagem para Vera (véspera), sai qua 11/11 às 09:00: "Amanhã estamos aí às 8h. Está confirmado? Responda SIM.". *manda cliente Vera* ou *segura cliente Vera*. E mais 1: *agenda clientes* mostra; *manda cliente* manda todas.';
  c_pl  constant jsonb := jsonb_build_array(pg_temp.l('compras', 'Compras: Kamell: Cerbo de Nelson — compre até qui 12/11.'), pg_temp.l('comissao', 'Comissão de outubro: R$ 100,00.'),
                                            pg_temp.l('cliente', 'Amanhã, a partir das 09:00, vou mandar: a confirmação de qua 11/11 para Flávio. Para não mandar: *segura cliente Flávio*.'));
begin
  if not pg_temp.na_bancada() then return; end if;
  execute current_setting('agenda_teste.fase7f');
  perform pg_temp.liga();
  -- a fixture da 7f não tem pergunta de prazo: o bloco é o de antes, nos jeitos de cortar
  for x in select * from (values
      ('P1a a fixture da 7f (ter 10/11 17:30), as linhas de verdade', 'select pg_temp.linhas()', 520, 3),
      ('P1b bloco_max_chars 300, com compras, comissão e o que sai amanhã', 'select pg_temp.linhas() || ' || quote_literal(c_pl::text) || '::jsonb', 300, 3),
      ('P1c a mensagem ao cliente com a crítica que perde amanhã', format('select pg_temp.linhas() || jsonb_build_array(pg_temp.l(''cliente'', %L, jsonb_build_object(''pergunta_id'', pg_temp.q(''04''))))', c_txt), 520, 3),
      ('P1d 1 vaga só', 'select pg_temp.linhas()', 520, 1),
      ('P1e 5 vagas', 'select pg_temp.linhas()', 800, 5)) t(nome, sql, mx, dm) loop
    update public.agenda_config set bloco_max_chars = x.mx, bloco_decisoes_max = x.dm where id;
    execute x.sql into v_lin;
    b := pg_temp.sobre(v_lin);
    a := pg_temp.antes(v_lin);
    r := pg_temp.ok(r, x.nome || ': sem a linha do gestor, a saída de antes, byte a byte', b::text = a::text and jsonb_array_length(b -> 'linhas') > 2, pg_temp.texto(b, 0));
  end loop;
  update public.agenda_config set bloco_max_chars = 520, bloco_decisoes_max = 3 where id;

  -- as perguntas de prazo existem, mas a linha (m) não chega ligada ao bloco
  begin
    perform pg_temp.perguntas_de_prazo(true);
    update public.agenda_config set modo_vigia = 'sombra' where id;
    v_lin := pg_temp.linhas();
    b := pg_temp.sobre(v_lin);
    r := pg_temp.ok(r, 'P1f contraprova: com a vigia em sombra, a linha (m) chega em sombra (o que a agenda diria) e o bloco é o de antes, byte a byte',
      exists (select 1 from jsonb_array_elements(v_lin) l where l ->> 'tipo' = 'pergunta' and l -> 'perda' = '76'::jsonb and l ->> 'modo' = 'sombra')
      and b::text = pg_temp.antes(v_lin)::text, pg_temp.texto(b, 0));
    update public.agenda_config set modo_vigia = 'ligado' where id;
    -- a linha (m) que veio sem pergunta_ids (forma estranha) não entra: a de antes
    v_lin := (select jsonb_agg(case when l ->> 'tipo' = 'pergunta' and l -> 'perda' = '76'::jsonb then l - 'pergunta_ids' else l end) from jsonb_array_elements(pg_temp.linhas()) l);
    r := pg_temp.ok(r, 'P1g a linha de perda 76 sem pergunta_ids não vira decisão: a de antes, byte a byte', pg_temp.sobre(v_lin)::text = pg_temp.antes(v_lin)::text, null);
    -- a linha (m) sem prazo (perda 30: só o "Espero você") não entra: a de antes
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste do prazo' where id in (pg_temp.g('01'), pg_temp.g('02'), pg_temp.g('03'), pg_temp.g('05'));
    insert into public.agenda_perguntas (id, tipo, chave, service_order_id, os_ids, perda_em, texto, opcoes, recomendacao, modo, criada_em, expira_em)
    values (pg_temp.g('06'), 'estimativa', 'estimativa:' || pg_temp.osf('301'), pg_temp.osf('301'), array[pg_temp.osf('301')], date '2026-11-17',
            'Quantos dias leva a Revisão do banco de baterias do Nelson? Acima de 8 diárias eu não marco sozinho: me diga os dias.',
            '[{"n": 1, "texto": "Conta 9 dias", "efeito": {"dias": 9, "feito": "contei 9 dias"}}, {"n": 2, "texto": "Eu digo os dias", "efeito": {"dizer": true}}]', 1, 'ligado',
            timestamptz '2026-11-10 16:53-03', timestamptz '2026-11-17 16:53-03');
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste do prazo' where id = pg_temp.g('04');
    v_lin := pg_temp.linhas();
    b := pg_temp.sobre(v_lin);
    r := pg_temp.ok(r, 'P1h a linha (m) sem prazo (perda 30, "Espero você") continua descartada: a de antes, byte a byte',
      exists (select 1 from jsonb_array_elements(v_lin) l where l ->> 'tipo' = 'pergunta' and l -> 'perda' = '30'::jsonb and l ->> 'texto' like '%Nelson%')
      and b::text = pg_temp.antes(v_lin)::text, pg_temp.texto(b, 0));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  -- o bloco em sombra: o texto do dono não muda (as linhas são as de antes); a chave bloco diz sombra e leva o que ele diria
  begin
    perform pg_temp.perguntas_de_prazo();
    update public.agenda_config set modo_bloco_agenda = 'desligado' where id;
    a := public.agenda_textos_do_fechamento(date '2026-11-10', date '2026-11-11');
    update public.agenda_config set modo_bloco_agenda = 'sombra' where id;
    b := public.agenda_textos_do_fechamento(date '2026-11-10', date '2026-11-11');
    r := pg_temp.ok(r, 'P1i contraprova: o bloco em sombra — tirada a chave bloco, a saída é a do desligado (md5); a chave diz sombra (o TS só fala pelo ligado)',
      md5((b - 'bloco')::text) = md5(a::text) and b #>> '{bloco,modo}' = 'sombra' and not a ? 'bloco', null);
    update public.agenda_config set modo_bloco_agenda = 'desligado' where id;
    r := pg_temp.ok(r, 'P1j desligado: {modo} e nada mais, com as perguntas de prazo abertas', pg_temp.sobre(pg_temp.linhas()) = '{"modo": "desligado"}'::jsonb, null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  update public.agenda_config set modo_bloco_agenda = 'desligado' where id;
  perform pg_temp.gravar(r);
end
$p$;

-- ── P2. Com a linha do gestor ──────────────────────────────────────────────────────────────
do $p$
declare
  r     jsonb := '[]';
  v_lin jsonb;
  v_m   jsonb;
  b     jsonb;
  a     jsonb;
  v_ord int;
  v_ok  boolean;
  v_det text;
  k     int;
  c_txt constant text := 'Mensagem para Vera (véspera), sai qua 11/11 às 09:00: "Amanhã estamos aí às 8h. Está confirmado? Responda SIM.". *manda cliente Vera* ou *segura cliente Vera*. E mais 1: *agenda clientes* mostra; *manda cliente* manda todas.';
begin
  if not pg_temp.na_bancada() then return; end if;
  begin
    perform pg_temp.liga();
    perform pg_temp.perguntas_de_prazo();
    v_lin := pg_temp.linhas();
    v_m := (select l from jsonb_array_elements(v_lin) l where l ->> 'tipo' = 'pergunta' and l -> 'perda' = '76'::jsonb and l ->> 'modo' = 'ligado');
    b := pg_temp.sobre(v_lin);
    a := pg_temp.antes(v_lin);
    r := pg_temp.ok(r, 'P2a o cenário: a linha (m) ligada, perda 76, com a ficha, a situacao e a estimativa (a situacao de ontem fica fora dela), e a forma curta; o bloco de antes a descartava',
      v_m -> 'pergunta_ids' = jsonb_build_array(pg_temp.g('01'), pg_temp.g('03'), pg_temp.g('04')) and v_m ? 'texto_curto'
      and not exists (select 1 from jsonb_array_elements(a -> 'linhas') l where l -> 'pergunta_ids' = v_m -> 'pergunta_ids'), coalesce(v_m::text, 'sem a linha (m)'));
    r := pg_temp.ok(r, 'P2b o caminho de verdade (agenda_textos_do_fechamento) dá o mesmo bloco que as linhas dele', pg_temp.bloco()::text = b::text, null);
    r := pg_temp.ok(r, 'P2c a linha do gestor entra logo depois da crítica que perde amanhã (a nao_cabe do Flávio, q06): prazo antes das outras',
      split_part(pg_temp.decs(b, 0), ',', 1) = 'q06' and split_part(pg_temp.decs(b, 0), ',', 2) = 'g01', pg_temp.decs(b, 0));
    r := pg_temp.ok(r, 'P2d duas formas, parte decisao: a inteira entra no 0 e sai no 2; a curta entra no 2 e nunca sai (o entra/corte do Mudou)',
      (select string_agg(format('%s:%s', l ->> 'nivel_entra', coalesce(l ->> 'nivel_de_corte', '-')), ',' order by o)
         from jsonb_array_elements(b -> 'linhas') with ordinality t(l, o) where l ->> 'pergunta_id' = pg_temp.g('01')::text and l ->> 'parte' = 'decisao') = '0:2,2:-', b::text);
    -- em todo nível, uma forma dela à vista, e a crítica também
    v_ok := true;
    v_det := null;
    for k in 0 .. (b ->> 'nivel_min')::int loop
      if (select count(*) from jsonb_array_elements(pg_temp.no_nivel(b, k)) l where l ->> 'pergunta_id' = pg_temp.g('01')::text) <> 1
         or position('q06' in coalesce(pg_temp.decs(b, k), '')) = 0 then
        v_ok := false;
        v_det := coalesce(v_det || ' | ', '') || format('nível %s: %s', k, pg_temp.decs(b, k));
      end if;
    end loop;
    r := pg_temp.ok(r, 'P2e não é cortada em nenhum nível: do 0 ao nivel_min, uma forma dela à vista (e a 1ª decisão também)', v_ok, v_det);
    r := pg_temp.ok(r, 'P2f nivel_min: só o veredito, a 1ª decisão e a curta do gestor', pg_temp.partes(b, (b ->> 'nivel_min')::int) = 'veredito,decisao,decisao'
      and pg_temp.decs(b, (b ->> 'nivel_min')::int) = 'q06,g01', pg_temp.texto(b, (b ->> 'nivel_min')::int));
    r := pg_temp.ok(r, 'P2g a ordem fica sem nenhuma situacao, estimativa, reestimar ou ficha_estimativa aberta com prazo: nem as da linha nem a de ontem, que não está nela (g05)',
      not exists (select 1 from jsonb_array_elements(b -> 'linhas') l join public.agenda_perguntas q on q.id = (l ->> 'pergunta_id')::uuid
                   where q.tipo in ('situacao', 'estimativa', 'reestimar', 'ficha_estimativa') and q.veto_ate is not null and l ->> 'pergunta_id' <> pg_temp.g('01')::text)
      and exists (select 1 from jsonb_array_elements(public.agenda_perguntas_em_ordem(date '2026-11-10', pg_temp.em(date '2026-11-10', '17:30'))) e where e ->> 'id' = pg_temp.g('05')::text),
      pg_temp.decs(b, 0));
    r := pg_temp.ok(r, 'P2h a ficha do dia entra: a inteira com o texto dela e as opções; a curta sem as opções ("Para segurar, me diga.") e com o prazo das outras',
      (select l ->> 'texto' from jsonb_array_elements(b -> 'linhas') l where l ->> 'pergunta_id' = pg_temp.g('01')::text and l ->> 'nivel_entra' = '0')
        like '· Hoje às 19:30 a ficha de amanhã vai para Alex: Vanderlei, qua 11/11 de manhã — dia 2 de 2, pela minha estimativa. 1) Mande (recomendo); 2) Segure a ficha%Também, sem resposta até qua 11/11 18:00: Giancarlo (OS-F5) 1 dia; Tadeu (OS-F6) 1 dia.'
      and (select l ->> 'texto' from jsonb_array_elements(b -> 'linhas') l where l ->> 'pergunta_id' = pg_temp.g('01')::text and l ->> 'nivel_entra' = '2')
        = '· Hoje às 19:30 a ficha de amanhã vai para Alex: Vanderlei, qua 11/11 de manhã — dia 2 de 2, pela minha estimativa. Para segurar, me diga. Sem resposta até qua 11/11 18:00, conto: Giancarlo (OS-F5) 1 dia; Tadeu (OS-F6) 1 dia.',
      (select string_agg(l ->> 'texto', ' || ') from jsonb_array_elements(b -> 'linhas') l where l ->> 'pergunta_id' = pg_temp.g('01')::text));
    r := pg_temp.ok(r, 'P2i cada forma leva as perguntas que escreve (sem 2ª ficha, as 3 nas duas); pergunta_id = a 1ª (L1g); veto_ate nulo e sem veto_diria (L1h: o prazo já está gravado em cada uma)',
      (select bool_and(l -> 'pergunta_ids' = jsonb_build_array(pg_temp.g('01'), pg_temp.g('03'), pg_temp.g('04')) and l -> 'pergunta_ids' ->> 0 = l ->> 'pergunta_id'
                       and l -> 'veto_ate' = 'null'::jsonb and not l ? 'veto_diria') and count(*) = 2
         from jsonb_array_elements(b -> 'linhas') l where l ->> 'pergunta_id' = pg_temp.g('01')::text)
      and (select bool_and(q.veto_ate is not null) from public.agenda_perguntas q where q.id in (pg_temp.g('01'), pg_temp.g('03'), pg_temp.g('04'))), null);
    r := pg_temp.ok(r, 'P2j a linha do gestor no formato do bloco: começa por "· " (sem o "Agenda: "), cabe no leitor do Secretário (até 800 letras por linha) e não diz as palavras que o dono não usa',
      (select bool_and(l ->> 'texto' like '· %' and l ->> 'texto' not like '· Agenda:%' and char_length(l ->> 'texto') <= 800
                       and l ->> 'texto' !~* '\m(proposta|veto|lote|classe|zona|destrava|ppc)\M')
         from jsonb_array_elements(b -> 'linhas') l where l ->> 'pergunta_id' = pg_temp.g('01')::text), null);
    r := pg_temp.ok(r, 'P2k o veredito conta o mesmo que antes: as perguntas da linha contam como respostas que o dono deve, e a 1ª linha é a de antes, letra a letra',
      split_part(pg_temp.texto(b, 0), E'\n', 1) = split_part(pg_temp.texto(a, 0), E'\n', 1) and split_part(pg_temp.texto(b, 0), E'\n', 1) like '%preciso de % respostas suas%',
      split_part(pg_temp.texto(b, 0), E'\n', 1) || ' × ' || split_part(pg_temp.texto(a, 0), E'\n', 1));
    -- "(e mais N em *agenda pendências*)": em cada nível antes do último, as da ordem à vista + N = as da ordem que ficaram (sem as da linha e sem os 4 tipos com
    -- prazo); no último, como hoje, só o veredito e as que nunca saem, sem a conta
    select count(*)::int into v_ord
      from jsonb_array_elements(public.agenda_perguntas_em_ordem(date '2026-11-10', pg_temp.em(date '2026-11-10', '17:30'))) e
      join public.agenda_perguntas q on q.id = (e ->> 'id')::uuid
     where q.opcao_escolhida is null and not (q.tipo in ('situacao', 'estimativa', 'reestimar', 'ficha_estimativa') and q.veto_ate is not null);
    v_ok := true;
    v_det := null;
    for k in 0 .. (b ->> 'nivel_min')::int - 1 loop
      if (select count(*) from jsonb_array_elements(pg_temp.no_nivel(b, k)) l where l ->> 'parte' = 'decisao' and l ->> 'pergunta_id' is not null and l ->> 'pergunta_id' <> pg_temp.g('01')::text)
         + coalesce((select (substring(l ->> 'texto' from '^\(e mais (\d+) em'))::int from jsonb_array_elements(pg_temp.no_nivel(b, k)) l where l ->> 'texto' like '(e mais %'), 0)
         <> v_ord then
        v_ok := false;
        v_det := coalesce(v_det || ' | ', '') || format('nível %s: %s', k, pg_temp.texto(b, k));
      end if;
    end loop;
    r := pg_temp.ok(r, format('P2l "(e mais N em *agenda pendências*)": em cada nível, as da ordem à vista + N = as %s da ordem que ficam', v_ord), v_ok and v_ord > 3, v_det);
    r := pg_temp.ok(r, 'P2m as vagas: a do gestor ocupa 1 das 3 (a crítica, ela e mais 1 da ordem): o bloco não cresce',
      (select count(*) from jsonb_array_elements(pg_temp.no_nivel(b, 0)) l where l ->> 'parte' = 'decisao' and l ->> 'pergunta_id' is not null) = 3, pg_temp.decs(b, 0));
    v_ok := true;
    for k in 1 .. (b ->> 'nivel_min')::int loop
      v_ok := v_ok and char_length(pg_temp.texto(b, k)) <= char_length(pg_temp.texto(b, k - 1));
    end loop;
    r := pg_temp.ok(r, 'P2n cada nível tem no máximo as letras do anterior; o nível dado é o que cabe em bloco_max_chars (ou o último), e chars é o tamanho dele',
      v_ok and (b ->> 'chars')::int = char_length(pg_temp.texto(b, (b ->> 'nivel')::int))
      and ((b ->> 'chars')::int <= 520 or (b ->> 'nivel')::int = (b ->> 'nivel_min')::int)
      and ((b ->> 'nivel')::int = 0 or char_length(pg_temp.texto(b, (b ->> 'nivel')::int - 1)) > 520), format('nivel %s de %s, chars %s', b ->> 'nivel', b ->> 'nivel_min', b ->> 'chars'));
    r := pg_temp.ok(r, 'P2o não é nada_mudou nem incompleto', not (b ->> 'nada_mudou')::boolean and not (b ->> 'incompleto')::boolean, null);

    -- com a mensagem ao cliente (2A: o prazo 1º, o cliente 2º; as duas garantidas)
    b := pg_temp.sobre(v_lin || jsonb_build_array(pg_temp.l('cliente', c_txt, jsonb_build_object('pergunta_id', pg_temp.q('04')))));
    r := pg_temp.ok(r, 'P2p com a mensagem ao cliente: a crítica, o gestor, o cliente — e as 3 vagas ficam com elas',
      pg_temp.decs(b, 0) = 'q06,g01,q04', pg_temp.decs(b, 0));
    v_ok := true;
    v_det := null;
    for k in 0 .. (b ->> 'nivel_min')::int loop
      if pg_temp.decs(b, k) <> 'q06,g01,q04' then
        v_ok := false;
        v_det := coalesce(v_det || ' | ', '') || format('nível %s: %s', k, pg_temp.decs(b, k));
      end if;
    end loop;
    r := pg_temp.ok(r, 'P2q a do gestor e a do cliente nunca são cortadas (nivel_de_corte nulo): as 3 em todos os níveis',
      v_ok and (select bool_and(l ->> 'nivel_de_corte' is null) from jsonb_array_elements(b -> 'linhas') l
                 where l ->> 'pergunta_id' = pg_temp.q('04')::text or (l ->> 'pergunta_id' = pg_temp.g('01')::text and l ->> 'nivel_entra' = '2')), v_det);
    -- 1 vaga só: as que nunca saem entram assim mesmo; 5 vagas: o resto vem da ordem
    update public.agenda_config set bloco_decisoes_max = 1 where id;
    b := pg_temp.sobre(v_lin || jsonb_build_array(pg_temp.l('cliente', c_txt, jsonb_build_object('pergunta_id', pg_temp.q('04')))));
    r := pg_temp.ok(r, 'P2r com 1 vaga só, a crítica, o gestor e o cliente entram assim mesmo (nunca saem), e nada mais da ordem; o último nível é o 3',
      pg_temp.decs(b, 0) = 'q06,g01,q04' and (b ->> 'nivel_min')::int = 3, pg_temp.decs(b, 0) || ' / ' || (b ->> 'nivel_min'));
    update public.agenda_config set bloco_decisoes_max = 5 where id;
    b := pg_temp.sobre(v_lin || jsonb_build_array(pg_temp.l('cliente', c_txt, jsonb_build_object('pergunta_id', pg_temp.q('04')))));
    r := pg_temp.ok(r, 'P2s com 5 vagas: as 3 garantidas e mais 2 da ordem, que saem uma por nível a partir do 3 (a última primeiro)',
      split_part(pg_temp.decs(b, 0), ',', 1) || ',' || split_part(pg_temp.decs(b, 0), ',', 2) || ',' || split_part(pg_temp.decs(b, 0), ',', 3) = 'q06,g01,q04'
      and array_length(string_to_array(pg_temp.decs(b, 0), ','), 1) = 5 and array_length(string_to_array(pg_temp.decs(b, 3), ','), 1) = 4
      and pg_temp.decs(b, 4) = 'q06,g01,q04' and (b ->> 'nivel_min')::int = 5, pg_temp.decs(b, 0) || ' / ' || pg_temp.decs(b, 3));
    update public.agenda_config set bloco_decisoes_max = 3 where id;
    -- sem a crítica: a do gestor é a 1ª
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste do prazo' where id = pg_temp.q('06');
    b := pg_temp.sobre(pg_temp.linhas());
    r := pg_temp.ok(r, 'P2t sem crítica que perde amanhã, a linha do gestor é a 1ª decisão', split_part(pg_temp.decs(b, 0), ',', 1) = 'g01'
      and pg_temp.decs(b, (b ->> 'nivel_min')::int) = 'g01', pg_temp.decs(b, 0));
    -- sem a forma curta: a inteira nunca sai
    b := pg_temp.sobre((select jsonb_agg(case when l ->> 'tipo' = 'pergunta' and l -> 'perda' = '76'::jsonb then l - 'texto_curto' else l end) from jsonb_array_elements(pg_temp.linhas()) l));
    r := pg_temp.ok(r, 'P2u sem texto_curto, a inteira nunca é cortada (uma forma só)',
      (select string_agg(format('%s:%s', l ->> 'nivel_entra', coalesce(l ->> 'nivel_de_corte', '-')), ',') from jsonb_array_elements(b -> 'linhas') l where l ->> 'pergunta_id' = pg_temp.g('01')::text) = '0:-',
      null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  update public.agenda_config set modo_bloco_agenda = 'desligado' where id;
  perform pg_temp.gravar(r);
end
$p$;

-- ── P3. Duas fichas no mesmo dia ───────────────────────────────────────────────────────────
do $p$
declare
  r     jsonb := '[]';
  b     jsonb;
  v_int jsonb;
  v_cur jsonb;
begin
  if not pg_temp.na_bancada() then return; end if;
  begin
    perform pg_temp.liga();
    perform pg_temp.perguntas_de_prazo(true);
    b := pg_temp.sobre(pg_temp.linhas());
    v_int := (select l from jsonb_array_elements(b -> 'linhas') l where l ->> 'pergunta_id' = pg_temp.g('01')::text and l ->> 'nivel_entra' = '0');
    v_cur := (select l from jsonb_array_elements(b -> 'linhas') l where l ->> 'pergunta_id' = pg_temp.g('01')::text and l ->> 'nivel_entra' = '2');
    r := pg_temp.ok(r, 'P3a a inteira escreve a 2ª ficha (Flávio, OS-F4) e a leva: as 4 perguntas',
      v_int -> 'pergunta_ids' = jsonb_build_array(pg_temp.g('01'), pg_temp.g('02'), pg_temp.g('03'), pg_temp.g('04')) and v_int ->> 'texto' like '%Flávio (OS-F4)%', v_int::text);
    r := pg_temp.ok(r, 'P3b a curta só escreve a 1ª ficha e só a leva: a 2ª (g02) fica de fora das pergunta_ids, como do texto',
      v_cur -> 'pergunta_ids' = jsonb_build_array(pg_temp.g('01'), pg_temp.g('03'), pg_temp.g('04')) and v_cur ->> 'texto' not like '%OS-F4%' and v_cur ->> 'texto' not like '%Roberto%',
      v_cur::text);
    perform public.agenda_fechamento_registrar(date '2026-11-10', pg_temp.do_ts(pg_temp.no_nivel(b, (b ->> 'nivel_min')::int)), 'fechamento', timestamptz '2026-11-10 17:45-03');
    r := pg_temp.ok(r, 'P3c registrado o último nível (a curta): a 1ª ficha, a situacao e a estimativa contam como mostradas; a 2ª ficha, que não apareceu, não',
      pg_temp.vezes(pg_temp.g('01')) = 1 and pg_temp.vezes(pg_temp.g('03')) = 1 and pg_temp.vezes(pg_temp.g('04')) = 1 and pg_temp.vezes(pg_temp.g('02')) = 0,
      format('g01 %s g02 %s g03 %s g04 %s', pg_temp.vezes(pg_temp.g('01')), pg_temp.vezes(pg_temp.g('02')), pg_temp.vezes(pg_temp.g('03')), pg_temp.vezes(pg_temp.g('04'))));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.liga();
    perform pg_temp.perguntas_de_prazo(true);
    b := pg_temp.sobre(pg_temp.linhas());
    perform public.agenda_fechamento_registrar(date '2026-11-10', pg_temp.do_ts(pg_temp.no_nivel(b, 0)), 'fechamento', timestamptz '2026-11-10 17:45-03');
    r := pg_temp.ok(r, 'P3d registrado o nível 0 (a inteira): as 2 fichas, a situacao e a estimativa contam como mostradas, uma vez cada',
      pg_temp.vezes(pg_temp.g('01')) = 1 and pg_temp.vezes(pg_temp.g('02')) = 1 and pg_temp.vezes(pg_temp.g('03')) = 1 and pg_temp.vezes(pg_temp.g('04')) = 1
      and pg_temp.vezes(pg_temp.g('05')) = 0, null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  update public.agenda_config set modo_bloco_agenda = 'desligado' where id;
  perform pg_temp.gravar(r);
end
$p$;

-- ── P4. O registro pelo caminho do Secretário, e o prazo da ficha ─────────────────────────
do $p$
declare
  r     jsonb := '[]';
  b     jsonb;
  v_f   uuid;
  v_g   jsonb;
  q1    public.agenda_perguntas;
  q2    public.agenda_perguntas;
  c_saiu constant timestamptz := timestamptz '2026-11-10 17:35-03';
begin
  if not pg_temp.na_bancada() then return; end if;
  begin
    perform pg_temp.liga();
    perform pg_temp.perguntas_de_prazo(true);
    b := pg_temp.bloco();
    -- o Secretário cheio manda o último nível: a curta
    v_f := pg_temp.fila_da_tarde(date '2026-11-10');
    v_g := public.agenda_fechamento_guardar(date '2026-11-10', pg_temp.do_ts(pg_temp.no_nivel(b, (b ->> 'nivel_min')::int)), v_f, 'fechamento', timestamptz '2026-11-10 17:30-03');
    r := pg_temp.ok(r, 'P4a guardado com a fila pendente: nada conta ainda', v_g ->> 'estado' = 'esperando' and pg_temp.vezes(pg_temp.g('01')) = 0, v_g::text);
    update public.whatsapp_send_queue set status = 'sent', sent_at = c_saiu where id = v_f;
    perform public.agenda_aviso_conferir(timestamptz '2026-11-10 17:45-03');
    r := pg_temp.ok(r, 'P4b a fila mandou às 17:35: contam como mostradas, na hora em que saiu, só as que a forma curta escreve (a 2ª ficha não)',
      (select bool_and(q.mostrada_vezes = 1 and q.mostrada_em = c_saiu and q.mostrada_via = 'fechamento') from public.agenda_perguntas q
        where q.id in (pg_temp.g('01'), pg_temp.g('03'), pg_temp.g('04')))
      and pg_temp.vezes(pg_temp.g('02')) = 0 and pg_temp.vezes(pg_temp.g('05')) = 0,
      format('g01 %s g02 %s g03 %s g04 %s', pg_temp.vezes(pg_temp.g('01')), pg_temp.vezes(pg_temp.g('02')), pg_temp.vezes(pg_temp.g('03')), pg_temp.vezes(pg_temp.g('04'))));
    r := pg_temp.ok(r, 'P4c o registro não mexe no prazo gravado (a linha não leva veto_ate)',
      (select bool_and(q.veto_ate = case q.id when pg_temp.g('01') then timestamptz '2026-11-10 19:30-03' else timestamptz '2026-11-11 18:00-03' end)
         from public.agenda_perguntas q where q.id in (pg_temp.g('01'), pg_temp.g('03'), pg_temp.g('04'))), null);
    -- 19:35: a ficha venceu às 19:30, mostrada às 17:35 — vale o que eu disse; a 2ª ficha, nunca mostrada, não
    perform public._agenda_gestor_vetos(date '2026-11-10', timestamptz '2026-11-10 19:35-03');
    select * into q1 from public.agenda_perguntas x where x.id = pg_temp.g('01');
    select * into q2 from public.agenda_perguntas x where x.id = pg_temp.g('02');
    r := pg_temp.ok(r, 'P4d a ficha mostrada antes do prazo vence nele: resolvida, "sem resposta até ter 10/11 19:30: a ficha vai como eu disse", sem assumida_por (o caminho do gestor; a ficha não grava opcao_escolhida)',
      q1.estado = 'resolvida' and q1.resolvida_motivo = 'sem resposta até ter 10/11 19:30: a ficha vai como eu disse' and q1.assumida_por is null and q1.opcao_escolhida is null,
      format('%s | %s | %s', q1.estado, q1.resolvida_motivo, q1.assumida_por));
    r := pg_temp.ok(r, 'P4e a 2ª ficha, que a forma curta não escreveu, não vence: segue aberta (a rotina das 19:30 a segura, como antes)', q2.estado = 'aberta', q2.estado);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- mostrada só depois do prazo: não vence
    perform pg_temp.liga();
    perform pg_temp.perguntas_de_prazo();
    b := pg_temp.bloco();
    perform public.agenda_fechamento_registrar(date '2026-11-10', pg_temp.do_ts(pg_temp.no_nivel(b, (b ->> 'nivel')::int)), 'fechamento', timestamptz '2026-11-10 19:40-03');
    perform public._agenda_gestor_vetos(date '2026-11-10', timestamptz '2026-11-10 19:45-03');
    r := pg_temp.ok(r, 'P4f a ficha mostrada só depois do prazo (19:40) não vence no tique das 19:45: segue aberta',
      (select q.estado = 'aberta' and q.mostrada_vezes = 1 from public.agenda_perguntas q where q.id = pg_temp.g('01')), null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  update public.agenda_config set modo_bloco_agenda = 'desligado' where id;
  perform pg_temp.gravar(r);
end
$p$;

-- ── P6. A saúde: o fechamento no mínimo do bloco com a linha do gestor (revisão da F1) ─────
-- A bancada não tem resumo_tarde (é do Secretário, 20261015210000, fora dela): ela nasce aqui só com as colunas que a saúde lê, como em agenda_fase7f_leituras.sql, e
-- some no rollback. Cada caso grava fechamentos ligados de 1.100 letras (acima do texto_max de 1.000) como o Secretário os grava e compara a saúde nova com a de antes.
do $p$
declare
  r      jsonb := '[]';
  v_lin  jsonb;
  b      jsonb;
  a      jsonb;
  sn     jsonb;
  sa     jsonb;
  k      int;
  v_det  text;
  c_h    constant date := date '2026-11-10';
  c_a    constant timestamptz := timestamptz '2026-11-10 18:00-03';
  c_txt  constant text := 'Mensagem para Vera (véspera), sai qua 11/11 às 09:00: "Amanhã estamos aí às 8h. Está confirmado? Responda SIM.". *manda cliente Vera* ou *segura cliente Vera*. E mais 1: *agenda clientes* mostra; *manda cliente* manda todas.';
begin
  if not pg_temp.na_bancada() then return; end if;
  if to_regclass('public.resumo_tarde') is null then
    create table public.resumo_tarde (id uuid primary key default gen_random_uuid(), dia date not null, phone_normalized text not null, turno text not null,
                                      modo text not null, formato text not null, texto text, detalhe jsonb not null default '{}'::jsonb,
                                      criado_em timestamptz not null default now());
  end if;
  begin
    perform pg_temp.liga();
    perform pg_temp.perguntas_de_prazo();
    v_lin := pg_temp.linhas() || jsonb_build_array(pg_temp.l('cliente', c_txt, jsonb_build_object('pergunta_id', pg_temp.q('04'))));
    b := pg_temp.sobre(v_lin);
    -- o achado: o Secretário cheio manda o último nível (textoComOBloco), com as 3 que nunca saem
    perform pg_temp.tarde(c_h, 1100, v_lin, b, (b ->> 'nivel_min')::int);
    sn := public._agenda_saude_comunicacao(c_h, c_a);
    sa := pg_temp.saude_7f(c_h, c_a);
    r := pg_temp.ok(r, 'P6a o achado da revisão: o fechamento de 1.100 letras no mínimo do bloco (o veredito, a crítica, a do gestor e a do cliente, que nunca saem) era bloco_grande na saúde de antes e derrubava o zeros_ok; agora não, e o resto da saúde é o mesmo',
      pg_temp.partes(b, (b ->> 'nivel_min')::int) = 'veredito,decisao,decisao,decisao' and pg_temp.decs(b, (b ->> 'nivel_min')::int) = 'q06,g01,q04'
      and (sa ->> 'bloco_grande')::int = 1 and not (sa ->> 'zeros_ok')::boolean and (sn ->> 'bloco_grande')::int = 0
      and (sn - 'bloco_grande' - 'zeros_ok') = (sa - 'bloco_grande' - 'zeros_ok'),
      format('antes %s (zeros_ok %s), agora %s (zeros_ok %s); no mínimo: %s', sa ->> 'bloco_grande', sa ->> 'zeros_ok', sn ->> 'bloco_grande', sn ->> 'zeros_ok',
             pg_temp.texto(b, (b ->> 'nivel_min')::int)));
    -- a premissa da conta: a crítica antes da do gestor é numerada ("Decisão N:"), a do gestor e o "e mais" não; e, no nível de antes do último, as 3 e o "e mais" (a
    -- tolerância de antes para a 1ª e o "e mais", agora com as 3 que nunca saem) não são bloco grande — com a 1ª sem número a tolerância seria 1 a menos e contaria
    delete from public.resumo_tarde;
    perform pg_temp.tarde(c_h, 1100, v_lin, b, (b ->> 'nivel_min')::int - 1, true);
    v_det := pg_temp.texto(b, (b ->> 'nivel_min')::int - 1);
    r := pg_temp.ok(r, 'P6a2 no nível de antes do último (a crítica numerada, a do gestor, a do cliente e o "e mais"; só o veredito e as decisões): não é bloco_grande (antes era)',
      (select string_agg(case when l ->> 'texto' ~ '^· Decisão [0-9]+: ' then 'n' when l ->> 'texto' like '(e mais %' then 'e' when l ->> 'texto' like '· Mensagem para %' then 'c' else 'g' end, ''
                         order by o)
         from jsonb_array_elements(pg_temp.no_nivel(b, (b ->> 'nivel_min')::int - 1)) with ordinality t(l, o) where l ->> 'parte' = 'decisao') = 'ngce'
      and (public._agenda_saude_comunicacao(c_h, c_a) ->> 'bloco_grande')::int = 0 and (pg_temp.saude_7f(c_h, c_a) ->> 'bloco_grande')::int = 1, v_det);
    -- acima do mínimo, ele ainda podia ceder: com 5 vagas, no nível 3 sobra 1 da ordem e o "e mais"; só o veredito e as decisões, para medir só a conta delas
    delete from public.resumo_tarde;
    update public.agenda_config set bloco_decisoes_max = 5 where id;
    b := pg_temp.sobre(v_lin);
    perform pg_temp.tarde(c_h, 1100, v_lin, b, 3, true);
    r := pg_temp.ok(r, 'P6b acima do mínimo (5 vagas, nível 3: a crítica, a do gestor, a do cliente, 1 da ordem que ainda pode sair e o "e mais"): bloco_grande nas duas',
      (select count(*) from jsonb_array_elements(pg_temp.no_nivel(b, 3)) l where l ->> 'parte' = 'decisao') >= 5
      and (public._agenda_saude_comunicacao(c_h, c_a) ->> 'bloco_grande')::int = 1 and (pg_temp.saude_7f(c_h, c_a) ->> 'bloco_grande')::int = 1,
      pg_temp.decs(b, 3) || ' | agora ' || (public._agenda_saude_comunicacao(c_h, c_a) ->> 'bloco_grande'));
    delete from public.resumo_tarde;
    perform pg_temp.tarde(c_h, 1100, v_lin, b, (b ->> 'nivel_min')::int, true);
    r := pg_temp.ok(r, 'P6c o mesmo com 5 vagas, no mínimo (só as 3 que nunca saem): não é bloco_grande (antes era)',
      pg_temp.partes(b, (b ->> 'nivel_min')::int) = 'veredito,decisao,decisao,decisao' and pg_temp.decs(b, (b ->> 'nivel_min')::int) = 'q06,g01,q04'
      and (public._agenda_saude_comunicacao(c_h, c_a) ->> 'bloco_grande')::int = 0 and (pg_temp.saude_7f(c_h, c_a) ->> 'bloco_grande')::int = 1,
      pg_temp.decs(b, (b ->> 'nivel_min')::int) || ' / nivel_min ' || (b ->> 'nivel_min'));
    update public.agenda_config set bloco_decisoes_max = 3 where id;
    -- sem a crítica, a do gestor é a 1ª: a tolerância é 1 a menos (a 1ª não é numerada)
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste do prazo' where id = pg_temp.q('06');
    v_lin := pg_temp.linhas() || jsonb_build_array(pg_temp.l('cliente', c_txt, jsonb_build_object('pergunta_id', pg_temp.q('04'))));
    b := pg_temp.sobre(v_lin);
    delete from public.resumo_tarde;
    perform pg_temp.tarde(c_h, 1100, v_lin, b, 2, true);
    v_det := format('nível 2: %s → %s', pg_temp.decs(b, 2), public._agenda_saude_comunicacao(c_h, c_a) ->> 'bloco_grande');
    r := pg_temp.ok(r, 'P6d a do gestor em 1º (sem crítica), com o cliente: no nível 2 (a do gestor, a do cliente, 1 da ordem e o "e mais") ainda podia ceder: bloco_grande',
      split_part(pg_temp.decs(b, 0), ',', 1) = 'g01' and (select count(*) from jsonb_array_elements(pg_temp.no_nivel(b, 2)) l where l ->> 'parte' = 'decisao') >= 4
      and (public._agenda_saude_comunicacao(c_h, c_a) ->> 'bloco_grande')::int = 1, v_det);
    delete from public.resumo_tarde;
    perform pg_temp.tarde(c_h, 1100, v_lin, b, (b ->> 'nivel_min')::int - 1, true);
    perform pg_temp.tarde(c_h, 1100, v_lin, b, (b ->> 'nivel_min')::int, true);
    r := pg_temp.ok(r, 'P6e a do gestor em 1º: no último nível (a do gestor e a do cliente) e no de antes dele (com o "e mais", a tolerância de antes para a 1ª e o "e mais"), não é bloco_grande',
      pg_temp.decs(b, (b ->> 'nivel_min')::int) = 'g01,q04' and (public._agenda_saude_comunicacao(c_h, c_a) ->> 'bloco_grande')::int = 0,
      format('%s / %s → %s', pg_temp.texto(b, (b ->> 'nivel_min')::int - 1), pg_temp.decs(b, (b ->> 'nivel_min')::int), public._agenda_saude_comunicacao(c_h, c_a) ->> 'bloco_grande'));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  -- sem a linha do gestor: a saúde de antes, byte a byte (a fixture da 7f sem pergunta de prazo, com o cliente; e com a vigia em sombra, a (m) chega em sombra)
  begin
    perform pg_temp.liga();
    v_lin := pg_temp.linhas() || jsonb_build_array(pg_temp.l('cliente', c_txt, jsonb_build_object('pergunta_id', pg_temp.q('04'))));
    b := pg_temp.sobre(v_lin);
    for k in 0 .. (b ->> 'nivel_min')::int loop
      perform pg_temp.tarde(c_h - k, 1100, v_lin, b, k);
      perform pg_temp.tarde(c_h - k, 1100, v_lin, b, k, true);
    end loop;
    perform pg_temp.perguntas_de_prazo();
    update public.agenda_config set modo_vigia = 'sombra' where id;
    v_lin := pg_temp.linhas() || jsonb_build_array(pg_temp.l('cliente', c_txt, jsonb_build_object('pergunta_id', pg_temp.q('04'))));
    b := pg_temp.sobre(v_lin);
    for k in 0 .. (b ->> 'nivel_min')::int loop
      perform pg_temp.tarde(c_h - k, 1100, v_lin, b, k, true);
    end loop;
    sn := public._agenda_saude_comunicacao(c_h, c_a);
    sa := pg_temp.saude_7f(c_h, c_a);
    r := pg_temp.ok(r, 'P6f sem a linha do gestor (sem pergunta de prazo; com a vigia em sombra, a (m) em sombra): cada nível gravado, a saúde nova é a de antes, byte a byte',
      sn::text = sa::text and (sa ->> 'bloco_grande')::int > 0
      and exists (select 1 from jsonb_array_elements(v_lin) l where l ->> 'tipo' = 'pergunta' and l -> 'perda' = '76'::jsonb and l ->> 'modo' = 'sombra'),
      format('bloco_grande %s (antes %s); fechamentos %s', sn ->> 'bloco_grande', sa ->> 'bloco_grande', (select count(*) from public.resumo_tarde)));
    -- os fechamentos de antes de aplicar (na janela de 7 dias): a (m) ligada nas linhas que a agenda diria, mas o bloco de antes, que a descartava
    delete from public.resumo_tarde;
    update public.agenda_config set modo_vigia = 'ligado' where id;
    v_lin := pg_temp.linhas() || jsonb_build_array(pg_temp.l('cliente', c_txt, jsonb_build_object('pergunta_id', pg_temp.q('04'))));
    a := pg_temp.antes(v_lin);
    for k in 0 .. (a ->> 'nivel_min')::int loop
      perform pg_temp.tarde(c_h - k, 1100, v_lin, a, k);
      perform pg_temp.tarde(c_h - k, 1100, v_lin, a, k, true);
    end loop;
    sn := public._agenda_saude_comunicacao(c_h, c_a);
    sa := pg_temp.saude_7f(c_h, c_a);
    r := pg_temp.ok(r, 'P6g os fechamentos de antes de aplicar (a (m) ligada nas linhas, o bloco de antes sem ela): a saúde nova nunca conta mais bloco_grande que a de antes, e o resto é o mesmo',
      (sn ->> 'bloco_grande')::int <= (sa ->> 'bloco_grande')::int and (sa ->> 'bloco_grande')::int > 0 and (sn - 'bloco_grande' - 'zeros_ok') = (sa - 'bloco_grande' - 'zeros_ok'),
      format('agora %s, antes %s', sn ->> 'bloco_grande', sa ->> 'bloco_grande'));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  update public.agenda_config set modo_bloco_agenda = 'desligado' where id;
  perform pg_temp.gravar(r);
end
$p$;

select teste, ok, detalhe from _resultado order by ok, teste;
rollback;
