-- Prova das perguntas do gestor da agenda, Fase 7a (pacote P4): a pergunta antes de marcar, o prazo e o que vale sem resposta
-- (migration 20261031100300), sobre a carteira REAL de 29/10 (o replay) e a sintética da 7a.
-- bancada: depende de 20261031100300
--
--   Q0 as portas e o que é (sem fixture): o prazo é leitura (authenticated e service_role); o gravador da pergunta, o dos dias e o
--      despacho são definer sem grant; os passos (a pergunta da OS, o prazo vencido, a chamada da equipe) são invoker sem grant;
--      agenda_decidir continua só do service_role e a limpeza sem grant
--   Q1 as perguntas da §6.3 byte a byte (situacao: começou sem rastro — Nelson —, com rastro — Paulo —, parada — Vanderlei em
--      05/11 —; estimativa: grande — Giancarlo —, embutida — Sérgio —, sem mão de obra — Tânia —; a chamada da equipe) e o que
--      não ganha pergunta (esperando o cliente, o orçamento; a classe 2); desde o 7a P12 o sinal não segura e o MP (sem mão de
--      obra) ganha a pergunta sem mão de obra da §6.3; o Flávio preso pelo material também é
--      perguntado; o seco não grava; o gravado (prazo, opção padrão, perda, validade), uma aberta por chave, o motivo que muda, a
--      fechada que não volta (e a vencida sem ser vista, que volta); desligado e sombra
--   Q2 o prazo (_agenda_veto_ate): qui 16:52 = sex 30/10 18:00; sex = ter 03/11 (Finados); sábado; p_du 3 e 0; veto_hora e veto_du
--   Q3 o prazo vencido (_agenda_gestor_vetos): antes do prazo nada; vencida sem ser vista não aplica (sem_mostrar); vista antes
--      aplica a opção 1 (os dias, a ação, o motivo); idempotente; vista depois do prazo não; respondida não; o dono que já disse os
--      dias vence; com *gestor, só propor* não (em_teste); pergunta crítica nunca tem prazo
--   Q4 _agenda_gestor_gravar_dias: os dias com a fonte orcamento, o histórico (com as chaves do planejar), a ação estimar
--      desfazível (o ramo do *desfaz* é do P7: a ação leva o antes de que ele precisa); o dono pela opção 1; recusa sobre os
--      dias do dono e do aceito; duração inválida
--   Q5 a limpeza: a respondida pelo *grava* ("você respondeu"), a OS que saiu da carteira, o motivo que sumiu ("não precisa
--      mais"); com o gestor fora de ligado, só os dias ditos resolvem
--   Q6 agenda_decidir despacha os 10 tipos do gestor (e não os de antes: equipe_cadastro, duracao, dia_avisado); situacao e
--      estimativa: 1 grava (o dono), 2 fica aberta (o prazo não vale mais), 3 "Use *concluiu …*" / "não marco"; opção que não
--      existe, já resolvida, em teste, a condição que sumiu
--   Q7 as cópias: agenda_decidir (de 20261029100900) e _agenda_vigia_limpeza (de 20261030100500) sem os blocos "-- FASE 7:"
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7a_perguntas.sql
--   Seguro em produção: Q0 e Q7 (as cópias saem PULADO sem as migrations como texto) só leem; Q1 a Q6 usam as fixtures e só
--   rodam na bancada (fora dela saem PULADO). Termina em ROLLBACK.
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

-- A OS pelo número (os ids do replay são md5: nunca por id).
create function pg_temp.os(p_numero text) returns uuid language sql stable as $f$
  select so.id from public.service_orders so where so.service_order_number = p_numero
$f$;

-- O instante em Brasília.
create function pg_temp.em(p text) returns timestamptz language sql immutable as $f$
  select (p || '-03')::timestamptz
$f$;

-- O corpo de uma função a partir do texto da migration.
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'\nas $function$' in v) + length(E'\nas $function$'));
  return left(v, position('$function$' in v) - 1);
end $f$;

-- O corpo sem os blocos "-- FASE 7: … -- FASE 7: fim" (o fim lido pelo prefixo).
create function pg_temp.sem_fase7(p_corpo text) returns text language plpgsql as $f$
declare
  v_b text[] := '{}'; v_bloco boolean := false; l text;
begin
  foreach l in array string_to_array(replace(p_corpo, E'\r\n', E'\n'), E'\n') loop
    if not v_bloco and l ~ '^\s*-- FASE 7:' and l !~ '^\s*-- FASE 7: fim' then v_bloco := true; continue; end if;
    if v_bloco then
      if l ~ '^\s*-- FASE 7: fim' then v_bloco := false; end if;
      continue;
    end if;
    v_b := v_b || l;
  end loop;
  return array_to_string(v_b, E'\n');
end $f$;

-- ── Q0. As portas e o que é (sem fixture) ───────────────────────────────────────────────────────────────
with f(assinatura, quem, definer) as (values
  ('public._agenda_veto_ate(timestamptz, smallint)', 'leitura', false),
  ('public._agenda_gestor_perguntar(text, text, uuid, text, jsonb, smallint, timestamptz, smallint, text, timestamptz)', 'ninguem', true),
  ('public._agenda_gestor_gravar_dias(uuid, numeric, text, uuid, timestamptz)', 'ninguem', true),
  ('public._agenda_gestor_decidir(uuid, smallint, uuid, text, text, date, timestamptz)', 'ninguem', true),
  ('public._agenda_gestor_perguntas_da_os(uuid, date, timestamptz, boolean)', 'ninguem', false),
  ('public._agenda_gestor_vetos(date, timestamptz)', 'ninguem', false),
  ('public._agenda_gestor_equipe(date, timestamptz)', 'ninguem', false),
  ('public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz)', 'servico', true),
  ('public._agenda_vigia_limpeza(date, timestamptz)', 'ninguem', false))
insert into _resultado
select 'Q0a as portas: o prazo para authenticated e service_role; o gravador da pergunta, o dos dias e o despacho (definer) e os 3 passos (invoker) para ninguém; agenda_decidir só service_role; a limpeza para ninguém; nunca anon',
       bool_and(not has_function_privilege('anon', f.assinatura, 'execute')
                and has_function_privilege('authenticated', f.assinatura, 'execute') = (f.quem = 'leitura')
                and has_function_privilege('service_role', f.assinatura, 'execute') = (f.quem in ('leitura', 'servico'))
                and p.prosecdef = f.definer
                and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%'),
       string_agg(f.assinatura, ', ') filter (where has_function_privilege('anon', f.assinatura, 'execute')
                                              or has_function_privilege('authenticated', f.assinatura, 'execute') <> (f.quem = 'leitura')
                                              or has_function_privilege('service_role', f.assinatura, 'execute') <> (f.quem in ('leitura', 'servico'))
                                              or p.prosecdef <> f.definer)
  from f join pg_proc p on p.oid = f.assinatura::regprocedure;
insert into _resultado
select 'Q0b o prazo é STABLE; os gravadores, o despacho e os passos são VOLATILE',
       bool_and(case when p.proname = '_agenda_veto_ate' then p.provolatile = 's' else p.provolatile = 'v' end) and count(*) = 7,
       string_agg(p.proname || ':' || p.provolatile::text, ', ' order by p.proname)
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('_agenda_veto_ate', '_agenda_gestor_perguntar', '_agenda_gestor_gravar_dias', '_agenda_gestor_decidir',
                     '_agenda_gestor_perguntas_da_os', '_agenda_gestor_vetos', '_agenda_gestor_equipe');

-- ── Q1 a Q6: com as fixtures (o replay de 29/10 e a sintética, por cima) ──────────────────────────────────
do $fx$
declare
  v_res    jsonb := '[]'::jsonb;
  c_hoje   constant date := date '2026-10-29';
  c_agora  constant timestamptz := timestamptz '2026-10-29 16:52-03';
  c_sex    constant date := date '2026-10-30';
  c_prazo  constant timestamptz := timestamptz '2026-10-30 18:00-03';
  c_tique  constant timestamptz := timestamptz '2026-10-30 18:07-03';
  c_nelson constant text := 'Nelson (OS-00112) está como ''aguardando peças'': o serviço já começou? Se você não me disser nada até sex 30/10 às 18:00, conto o serviço inteiro (4 dias, estimativa minha). 1) Não começou: conte tudo (recomendo); 2) Já começou: eu digo quanto falta; 3) Já terminou.';
  -- (correção da 7a, achado 20: acima de 8 diárias, sem prazo nem opção padrão — o gestor não marca sozinho; recomenda a 2)
  -- (correção 2 da 7a, achado 20 de novo, 20261031100985: a 3ª opção "Já terminou (ou já entreguei)" — o Giancarlo foi entregue)
  c_gianc  constant text := 'Giancarlo (OS-00130): pelo valor do orçamento são 10 diárias (10 dias com 1 pessoa). É mais de 8 diárias: não marco sozinho. Me diga os dias. 1) Marque 10 dias; 2) Eu digo os dias (recomendo); 3) Já terminou (ou já entreguei).';
  v_carteira text[] := array['OS-00074', 'OS-00069', 'OS-00130', 'OS-00112', 'OS-00104', 'OS-00096', 'OS-00076', 'OS-00032',
                             'OS-00033', 'ORÇ-00083', 'ORÇ-00095'];
  v_adm    uuid;
  v_alex   uuid;
  v_mick   uuid;
  v_n      int;
  v_k      int;
  v_t      text;
  v_qn     uuid;
  v_qg     uuid;
  v_q      uuid;
  v_q2     uuid;
  v_a      uuid;
  v_a2     uuid;
  v_t2     text;
  v_d2     jsonb;
  p        jsonb;
  d        jsonb;
  e        jsonb;
  x        record;
  pl       record;
  ac       record;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = ''
     or coalesce(current_setting('agenda_teste.fase7a', true), '') = '' then
    insert into _resultado values ('Q1 a Q6 (as fixtures da 7a)', true,
      'PULADO: sem agenda_teste.replay2910 e agenda_teste.fase7a (rode pela bancada)');
    return;
  end if;
  execute current_setting('agenda_teste.replay2910');
  execute current_setting('agenda_teste.fase7a');
  select u.id into v_adm from public.app_users u where u.role = 'admin' order by u.id limit 1;
  select py.id into v_alex from public.payees py where py.name like 'Alex%' order by py.id limit 1;
  select py.id into v_mick from public.payees py where py.name like 'Mickael%' order by py.id limit 1;
  -- a presença do dono do Lenine e do Vanderlei como em produção (abre e fecha; o replay dá "sempre": notas do P2)
  insert into public.os_planejamento (service_order_id, dono_presenca)
  select pg_temp.os(n), 'abre_e_fecha' from unnest(array['OS-00074', 'OS-00069']) n
  on conflict (service_order_id) do update set dono_presenca = 'abre_e_fecha';
  update public.agenda_config set modo_marcar_sozinho = 'ligado', gestor_so_propor = false where id;

  -- ── Q1. As perguntas (seco: nada gravado) ───────────────────────────────────────────────────────────────
  select count(*) into v_k from public.agenda_perguntas;
  p := public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-00112'), c_hoje, c_agora, true);
  v_res := pg_temp.ok(v_res, 'Q1a situação, começou sem rastro (Nelson, "aguardando peças"): o texto da §6.3, a chave, as 3 opções (a 1 com os 4 dias), a recomendação e a opção padrão 1, o prazo sex 30/10 18:00',
    p ->> 'texto' = c_nelson
    and p ->> 'chave' = 'situacao:' || pg_temp.os('OS-00112') || ':comecada' and p ->> 'tipo' = 'situacao'
    and p ->> 'motivo' = 'situacao' and p ->> 'variante' = 'comecada' and p ->> 'curto' = 'já começou?'
    and p -> 'opcoes' = jsonb_build_array(
          jsonb_build_object('n', 1, 'texto', 'Não começou: conte tudo',
                             'efeito', jsonb_build_object('dias', 4, 'feito', 'contei o serviço inteiro, 4 dias (estimativa minha)')),
          jsonb_build_object('n', 2, 'texto', 'Já começou: eu digo quanto falta', 'efeito', jsonb_build_object('dizer', true)),
          jsonb_build_object('n', 3, 'texto', 'Já terminou', 'efeito', jsonb_build_object('terminou', true)))
    and p ->> 'recomendacao' = '1' and p ->> 'opcao_padrao' = '1' and (p ->> 'veto_ate')::timestamptz = c_prazo
    and not (p ->> 'perguntou')::boolean,
    p::text);
  p := public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-97001'), c_hoje, c_agora, true);
  v_res := pg_temp.ok(v_res, 'Q1b situação, com rastro (Paulo: check-in 26/10 e a diária ligada): "já começou em 26/10: quanto falta?", 1 dia para terminar',
    p ->> 'texto' = 'Paulo (OS-97001) já começou em 26/10: quanto falta? Se você não me disser nada até sex 30/10 às 18:00, marco 1 dia para terminar. 1) 1 dia (recomendo); 2) Eu digo quanto falta; 3) Já terminou.'
    and p ->> 'variante' = 'rastro' and p #>> '{opcoes,0,efeito,dias}' = '1'
    and p #>> '{opcoes,0,efeito,feito}' = 'contei 1 dia para terminar (estimativa minha)',
    p ->> 'texto');
  p := public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-00069'), date '2026-11-05', timestamptz '2026-11-05 16:52-03', true);
  v_res := pg_temp.ok(v_res, 'Q1c situação, parada (Vanderlei em qui 05/11: sem nada desde 03/10, mais de 30 dias): "ainda é para fazer o serviço inteiro?", 7,5 dias, até sex 06/11 às 18:00',
    p ->> 'texto' = 'Vanderlei (OS-00069) está parado desde 03/10: ainda é para fazer o serviço inteiro? Se você não me disser nada até sex 06/11 às 18:00, conto o serviço inteiro (7,5 dias, estimativa minha). 1) Sim, inteiro (recomendo); 2) Eu digo o que falta; 3) Não é mais para fazer.'
    and p ->> 'variante' = 'parada' and p #>> '{opcoes,2,efeito}' = '{"nao_fazer": true}' and p ->> 'curto' = 'parado desde 03/10',
    p ->> 'texto');
  p := public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-00130'), c_hoje, c_agora, true);
  v_res := pg_temp.ok(v_res, 'Q1d estimativa, grande (Giancarlo: 9,87 diárias, mais de 8): "10 diárias (10 dias com 1 pessoa)", não marco sozinho — sem prazo nem opção padrão, recomenda a 2 (correção da 7a, achado 20)',
    p ->> 'texto' = c_gianc and p ->> 'chave' = 'estimativa:' || pg_temp.os('OS-00130') || ':grande'
    and p ->> 'curto' = '10 diárias pela estimativa' and p #>> '{opcoes,0,efeito,dias}' = '10'
    and p -> 'veto_ate' = 'null'::jsonb and p -> 'opcao_padrao' = 'null'::jsonb and p ->> 'recomendacao' = '2',
    p ->> 'texto');
  p := public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-97002'), c_hoje, c_agora, true);
  -- (correção da 7a, achado 21: a peça embutida não segura mais a OS — a estimativa conta tudo como mão de obra e vale —, então o
  -- Sérgio não é perguntado; a suposição fica dita na prontidão)
  v_res := pg_temp.ok(v_res, 'Q1e estimativa, embutida (Sérgio: a linha de serviço pode ter peça junto): não pergunta mais — a estimativa conta tudo como mão de obra e vale (correção da 7a, achado 21)',
    not (p ->> 'perguntou')::boolean and p ->> 'por' = 'nada_a_perguntar' and not (p ? 'chave')
    and (public._agenda_gestor_estimativa(pg_temp.os('OS-97002'), c_hoje) ->> 'usa')::boolean,
    p ->> 'texto');
  begin
    delete from public.service_order_services s where s.service_order_id = pg_temp.os('OS-97003') and s.name_snapshot !~* 'deslocamento';
    p := public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-97003'), c_hoje, c_agora, true);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q1f estimativa, sem mão de obra (Tânia só com o deslocamento, que sai da mão de obra): "marco 1 dia", a recomendação é a 2 e a opção padrão continua a 1',
    p ->> 'texto' = 'Tânia (OS-97003): o orçamento não tem mão de obra separada, então não sei quantos dias leva. Se você não me disser nada até sex 30/10 às 18:00, marco 1 dia. 1) Marque 1 dia; 2) Eu digo os dias (recomendo).'
    and p ->> 'recomendacao' = '2' and p ->> 'opcao_padrao' = '1' and p ->> 'variante' = 'sem_base',
    p ->> 'texto');
  p := public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-00104'), c_hoje, c_agora, true);
  e := public._agenda_classe_agora(pg_temp.os('OS-00104'), c_hoje) - 'pront';
  v_res := pg_temp.ok(v_res, 'Q1g o Flávio fica fora pelo material (o compressor venceu: "chegou?") e também é perguntado — a situação dele está pendente e o "conto o serviço inteiro" não fica falso por causa do material (desvio da §5.4, notas P4)',
    e ->> 'classe' = '4' and e ->> 'motivo' = 'material'
    and p ->> 'texto' = 'Flávio (OS-00104) está como ''aguardando peças'': o serviço já começou? Se você não me disser nada até sex 30/10 às 18:00, conto o serviço inteiro (3,5 dias, estimativa minha). 1) Não começou: conte tudo (recomendo); 2) Já começou: eu digo quanto falta; 3) Já terminou.',
    (e ->> 'motivo') || ' | ' || coalesce(p ->> 'texto', p::text));
  select string_agg(n || ':' || coalesce(y2.r ->> 'classe_motivo', '?'), ' ' order by n), count(*) filter (where y2.r ? 'chave')
    into v_t, v_n
    from unnest(array['OS-00032', 'OS-00033', 'OS-00076', 'ORÇ-00083', 'OS-00074', 'OS-00069', 'OS-00096']) n
   cross join lateral (select public._agenda_gestor_perguntas_da_os(pg_temp.os(n), c_hoje, c_agora, true) as r) y2;
  v_res := pg_temp.ok(v_res, 'Q1h não ganham pergunta: Kalmar ×2 e Rodrigo-76 (esperando o cliente; a Kalmar tem check-in em junho e "marco 1 dia" seria falso), Robson (orçamento) e a classe 2 (Lenine, Vanderlei, Rodrigo-96)',
    v_n = 0 and v_t = 'ORÇ-00083:orcamento OS-00032:cliente OS-00033:cliente OS-00069:pronta OS-00074:pronta OS-00076:cliente OS-00096:pronta',
    v_t);
  -- (7a P12: com a regra sinal_cobrar o sinal não segura mais — AG7-09 —, e o MP, que esperava o sinal, ganha a pergunta da
  -- estimativa sem mão de obra: o texto da §6.3, byte a byte)
  p := public._agenda_gestor_perguntas_da_os(pg_temp.os('ORÇ-00095'), c_hoje, c_agora, true);
  v_res := pg_temp.ok(v_res, 'Q1i o MP (ORÇ-00095, só kits), sem o sinal travando desde o 7a P12, ganha a pergunta da estimativa sem mão de obra (§6.3): "MP (ORÇ-00095): o orçamento não tem mão de obra separada, então não sei quantos dias leva. …"; padrão 1, recomendação 2',
    p ->> 'texto' = 'MP (ORÇ-00095): o orçamento não tem mão de obra separada, então não sei quantos dias leva. Se você não me disser nada até sex 30/10 às 18:00, marco 1 dia. 1) Marque 1 dia; 2) Eu digo os dias (recomendo).'
    and p ->> 'chave' = 'estimativa:' || pg_temp.os('ORÇ-00095') || ':sem_base' and (p ->> 'opcao_padrao')::int = 1
    and (p ->> 'recomendacao')::int = 2,
    coalesce(p ->> 'texto', p::text));
  select count(*) into v_n from public.agenda_perguntas;
  v_res := pg_temp.ok(v_res, 'Q1i o seco não grava nada', v_n = v_k, format('%s → %s', v_k, v_n));

  -- gravado (ligado)
  p := public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-00112'), c_hoje, c_agora, false);
  v_qn := (p ->> 'pergunta_id')::uuid;
  select * into x from public.agenda_perguntas q where q.id = v_qn;
  v_res := pg_temp.ok(v_res, 'Q1j gravada em ligado: o texto, situacao, modo ligado, veto_ate sex 30/10 18:00, opcao_padrao 1, recomendação 1, perda_em sex 30/10, expira_em = o prazo + desfazer_validade, a OS',
    (p ->> 'perguntou')::boolean and (p ->> 'nova')::boolean and p ->> 'modo' = 'ligado'
    and x.texto = c_nelson and x.tipo = 'situacao' and x.modo = 'ligado' and x.estado = 'aberta' and not x.critica
    and x.veto_ate = c_prazo and x.opcao_padrao = 1 and x.recomendacao = 1 and x.perda_em = c_sex
    and x.expira_em = c_prazo + (select desfazer_validade from public.agenda_config where id)
    and x.service_order_id = pg_temp.os('OS-00112') and x.os_ids = array[pg_temp.os('OS-00112')] and x.criada_em = c_agora
    and x.opcoes = p -> 'opcoes',
    format('%s %s %s %s %s', x.modo, x.veto_ate, x.opcao_padrao, x.perda_em, x.expira_em));
  p := public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-00112'), c_hoje, c_agora + interval '1 hour', false);
  select count(*) into v_n from public.agenda_perguntas q where q.service_order_id = pg_temp.os('OS-00112') and q.tipo = 'situacao';
  v_res := pg_temp.ok(v_res, 'Q1k uma aberta por chave e modo: a 2ª vez devolve a mesma (nova = false) e não grava outra',
    (p ->> 'pergunta_id')::uuid = v_qn and not (p ->> 'nova')::boolean and v_n = 1, p::text);
  -- o motivo muda (o check-in do Nelson aparece: agora é "quanto falta?"): a de antes sai, a nova entra
  begin
    update public.service_orders set check_in_at = timestamptz '2026-10-27 08:00-03' where id = pg_temp.os('OS-00112');
    p := public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-00112'), c_hoje, c_agora, false);
    select string_agg(q.chave || ':' || q.estado || ':' || coalesce(q.resolvida_motivo, '-'), ' | ' order by q.criada_em, q.chave)
      into v_t from public.agenda_perguntas q where q.service_order_id = pg_temp.os('OS-00112') and q.tipo = 'situacao';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q1l o motivo que muda (o check-in apareceu): a pergunta de antes resolve "mudou o que falta saber: perguntei de novo" e a nova (com rastro) entra',
    (p ->> 'perguntou')::boolean and p ->> 'variante' = 'rastro'
    and v_t = format('situacao:%s:comecada:resolvida:mudou o que falta saber: perguntei de novo | situacao:%s:rastro:aberta:-',
                     pg_temp.os('OS-00112'), pg_temp.os('OS-00112')),
    v_t);
  -- a fechada não volta na mesma chave; a vencida sem ter sido vista volta
  begin
    update public.agenda_perguntas set estado = 'respondida', respondida_em = c_agora, opcao_escolhida = 2 where id = v_qn;
    p := public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-00112'), c_hoje, c_agora, false);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    update public.agenda_perguntas set estado = 'vencida' where id = v_qn;
    d := public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-00112'), date '2026-11-03', timestamptz '2026-11-03 16:52-03', false);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    update public.agenda_perguntas set mostrada_vezes = 1, mostrada_em = timestamptz '2026-10-29 17:30-03', mostrada_via = 'fechamento'
     where id = v_qn;
    update public.agenda_perguntas set estado = 'vencida' where id = v_qn;
    e := public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-00112'), date '2026-11-03', timestamptz '2026-11-03 16:52-03', false);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q1m a fechada não volta na mesma chave (respondida = ja_perguntei); a vencida que o dono nunca viu volta com prazo novo (ter 03/11 → qua 04/11 18:00); a vencida que ele viu antes do prazo não',
    not (p ->> 'perguntou')::boolean and p ->> 'por' = 'ja_perguntei'
    and (d ->> 'perguntou')::boolean and (d ->> 'pergunta_id')::uuid <> v_qn and (d ->> 'veto_ate')::timestamptz = timestamptz '2026-11-04 18:00-03'
    and not (e ->> 'perguntou')::boolean and e ->> 'por' = 'ja_perguntei',
    p::text || ' | ' || d::text || ' | ' || e::text);
  -- desligado: nada; sombra sem a simulação: as regras não valem (nada a perguntar); dentro da simulação, o mesmo texto, em sombra
  begin
    update public.agenda_config set modo_marcar_sozinho = 'desligado' where id;
    p := public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-00130'), c_hoje, c_agora, false);
    update public.agenda_config set modo_marcar_sozinho = 'sombra' where id;
    d := public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-00130'), c_hoje, c_agora, false);
    perform set_config('agenda.gestor', 'sombra', true);
    e := public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-00130'), c_hoje, c_agora, false);
    perform set_config('agenda.gestor', '', true);
    select q.modo, q.texto into x from public.agenda_perguntas q where q.id = (e ->> 'pergunta_id')::uuid;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q1n desligado = nada gravado; em sombra fora da simulação as regras não valem (nada a perguntar); dentro da simulação (agenda.gestor = sombra) a mesma pergunta, gravada em sombra',
    p ->> 'por' = 'desligado' and d ->> 'por' = 'nada_a_perguntar' and (e ->> 'perguntou')::boolean and e ->> 'modo' = 'sombra'
    and x.modo = 'sombra' and x.texto = c_gianc,
    p::text || ' | ' || d::text || ' | ' || coalesce(x.modo, '-'));

  -- a chamada da equipe (qui 29/10, depois da publicação: a semana de 09/11)
  begin
    p := public._agenda_gestor_equipe(c_hoje, c_agora);
    select * into x from public.agenda_perguntas q where q.id = (p ->> 'pergunta_id')::uuid;
    d := public._agenda_gestor_equipe(c_hoje, c_agora + interval '15 minutes');
    e := public._agenda_gestor_equipe(c_sex, timestamptz '2026-10-30 16:52-03');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q1o a chamada da equipe (§6.3): a semana de 09/11 só com a semente (Roberto seg a sex, João ter a sex) e o Mickael com diária cadastrada que nunca esteve na agenda — sem prazo, sem opções, chave equipe_cadastro:chamada:2026-11-09, uma por semana, só no dia do plano',
    -- (correção da 7a, achado 4: quem só tem a diária cadastrada — o Mickael — não entra mais na chamada)
    (p ->> 'criada')::boolean and (p ->> 'semente')::boolean and p ->> 'sumidos' = '0'
    and x.texto = 'Para marcar a semana de 09/11 eu conto com Roberto (seg a sex) e João (ter a sex), pelo que vieram nas últimas 8 semanas. Se a equipe mudou, me diga quem vem e em que dias.'
    and x.tipo = 'equipe_cadastro' and x.chave = 'equipe_cadastro:chamada:2026-11-09' and x.opcoes = '[]'::jsonb
    and x.veto_ate is null and x.opcao_padrao is null and x.modo = 'ligado' and x.perda_em = date '2026-11-05'
    and x.expira_em = c_agora + interval '7 days'
    and not (d ->> 'criada')::boolean and d ->> 'motivo' = 'já perguntei desta semana'
    and not (e ->> 'criada')::boolean and e ->> 'motivo' = 'a chamada da equipe é no dia do plano',
    coalesce(x.texto, p::text) || ' | ' || d::text || ' | ' || e::text);
  -- a equipe declarada pelo dono (a correção de 30/10: Roberto e João fora, o Alex todo dia útil)
  begin
    update public.agenda_disponibilidade set substituida_em = timestamptz '2026-10-30 00:11-03'
     where payee_id in (select id from public.payees where name in ('Roberto', 'João')) and substituida_em is null;
    insert into public.agenda_disponibilidade (payee_id, dias_semana, situacao, origem, nota, criado_por)
    values (v_alex, '{1,2,3,4,5}', 'disponivel', 'dono', 'todo dia útil (teste P4)', v_adm);
    begin
      p := public._agenda_gestor_equipe(c_hoje, c_agora);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, criado_por)
    values (v_mick, daterange(date '2026-10-30', null), 'indisponivel', 'dono', 'saiu (teste P4)', v_adm);
    d := public._agenda_gestor_equipe(c_hoje, c_agora);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- (correção da 7a, achado 4: com a equipe declarada pelo dono e sem a semente, nada a perguntar — o Mickael, só com a diária
  -- cadastrada, não faz mais a chamada nascer toda quinta)
  v_res := pg_temp.ok(v_res, 'Q1p com a equipe que o dono declarou (Alex), nada a perguntar ("a equipe está dita"), com ou sem o Mickael na agenda: quem só tem a diária cadastrada não entra na chamada (correção da 7a, achado 4)',
    not (p ->> 'criada')::boolean and p ->> 'motivo' = 'a equipe está dita'
    and not (d ->> 'criada')::boolean and d ->> 'motivo' = 'a equipe está dita',
    p::text || ' | ' || d::text);
  begin
    update public.agenda_config set modo_marcar_sozinho = 'sombra' where id;
    p := public._agenda_gestor_equipe(c_hoje, c_agora);
    select q.modo into v_t from public.agenda_perguntas q where q.id = (p ->> 'pergunta_id')::uuid;
    update public.agenda_config set modo_marcar_sozinho = 'desligado' where id;
    d := public._agenda_gestor_equipe(c_hoje, c_agora);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q1q a chamada em sombra fica em sombra; com o gestor desligado, nada',
    (p ->> 'criada')::boolean and v_t = 'sombra' and not (d ->> 'criada')::boolean and d ->> 'motivo' = 'o gestor está desligado',
    p::text || ' | ' || d::text);

  -- ── Q2. O prazo ────────────────────────────────────────────────────────────────────────────────────────
  v_res := pg_temp.ok(v_res, 'Q2a de qui 29/10 16:52 = sex 30/10 18:00; de sex 30/10 10:00 = ter 03/11 18:00 (seg 02/11 é Finados); de sáb 31/10 = ter 03/11; de qui com p_du 3 = qua 04/11; com p_du 0 = o mesmo dia',
    public._agenda_veto_ate(c_agora) = c_prazo
    and public._agenda_veto_ate(timestamptz '2026-10-30 10:00-03') = timestamptz '2026-11-03 18:00-03'
    and public._agenda_veto_ate(timestamptz '2026-10-31 11:00-03') = timestamptz '2026-11-03 18:00-03'
    and public._agenda_veto_ate(c_agora, 3::smallint) = timestamptz '2026-11-04 18:00-03'
    and public._agenda_veto_ate(c_agora, 0::smallint) = timestamptz '2026-10-29 18:00-03'
    -- a hora em Brasília: 23:30 de qui em Brasília já é sex em UTC, e o prazo continua sex 30/10
    and public._agenda_veto_ate(timestamptz '2026-10-29 23:30-03') = c_prazo,
    public._agenda_veto_ate(c_agora)::text);
  begin
    update public.agenda_config set veto_hora = '17:45', veto_du = 2 where id;
    v_t := public._agenda_veto_ate(c_agora)::text;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform public._agenda_veto_ate(null);
    v_n := 0;
  exception when sqlstate '22004' then v_n := 1;
  end;
  v_res := pg_temp.ok(v_res, 'Q2b a hora e os dias vêm de agenda_config (veto_hora 17:45 e veto_du 2: ter 03/11 17:45); sem a hora = 22004',
    v_t::timestamptz = timestamptz '2026-11-03 17:45-03' and v_n = 1, v_t);

  -- ── Q3. O prazo vencido ─────────────────────────────────────────────────────────────────────────────────
  -- as perguntas do Nelson (Q1j) e do Giancarlo, gravadas qui 16:52
  v_qg := (public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-00130'), c_hoje, c_agora, false) ->> 'pergunta_id')::uuid;
  d := public._agenda_gestor_vetos(c_sex, timestamptz '2026-10-30 17:00-03');
  e := public._agenda_gestor_vetos(c_sex, c_tique);
  select count(*) filter (where q.estado = 'aberta') into v_n from public.agenda_perguntas q where q.id in (v_qn, v_qg);
  -- (correção da 7a, achado 20: a do Giancarlo, acima de 8 diárias, não tem prazo — o prazo não a vê; só a do Nelson)
  v_res := pg_temp.ok(v_res, 'Q3a antes do prazo, nada; vencido sem o dono ter visto, nada (sem_mostrar 1: a do Nelson; a do Giancarlo não tem prazo, correção da 7a, achado 20): as duas continuam abertas',
    d ->> 'aplicadas' = '0' and d ->> 'sem_mostrar' = '0' and e ->> 'aplicadas' = '0' and e ->> 'sem_mostrar' = '1' and v_n = 2,
    d::text || ' | ' || e::text);
  -- vista depois do prazo também não
  begin
    update public.agenda_perguntas set mostrada_vezes = 1, mostrada_em = timestamptz '2026-10-30 18:01-03', mostrada_via = 'aviso'
     where id in (v_qn, v_qg);
    d := public._agenda_gestor_vetos(c_sex, c_tique);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- com *gestor, só propor*: o modo do gestor vale sombra, nada se aplica (em_teste)
  begin
    update public.agenda_perguntas set mostrada_vezes = 1, mostrada_em = timestamptz '2026-10-29 17:30-03', mostrada_via = 'fechamento'
     where id in (v_qn, v_qg);
    update public.agenda_config set gestor_so_propor = true where id;
    e := public._agenda_gestor_vetos(c_sex, c_tique);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q3b vista só depois do prazo não aplica (sem_mostrar); com *gestor, só propor*, a vista também não (em_teste)',
    d ->> 'aplicadas' = '0' and d ->> 'sem_mostrar' = '1' and e ->> 'aplicadas' = '0' and e ->> 'em_teste' = '1',
    d::text || ' | ' || e::text);
  -- vistas no fechamento de qui 17:30: no tique de sex 18:07 a opção 1 vale
  update public.agenda_perguntas set mostrada_vezes = 1, mostrada_em = timestamptz '2026-10-29 17:30-03', mostrada_via = 'fechamento'
   where id in (v_qn, v_qg);
  select count(*) into v_k from public.agenda_acoes;
  e := public._agenda_gestor_vetos(c_sex, c_tique);
  d := public._agenda_gestor_vetos(c_sex, c_tique + interval '15 minutes');
  select string_agg(format('%s %s %s', so.service_order_number, trim_scale(pl2.dias), pl2.estimativa_fonte), ' | ' order by so.service_order_number)
    into v_t
    from public.os_planejamento pl2 join public.service_orders so on so.id = pl2.service_order_id
   where so.service_order_number in ('OS-00112', 'OS-00130');
  select * into x from public.agenda_perguntas q where q.id = v_qn;
  v_res := pg_temp.ok(v_res, 'Q3c vista antes do prazo: no tique de sex 18:07 a do Nelson vale como disse (4 dias, fonte orcamento); a do Giancarlo, sem prazo (correção da 7a, achado 20), não grava nada e continua aberta; a pergunta resolvida "sem resposta até sex 30/10 18:00: ficou como eu disse", com a opção 1; a OS vai ao encaixe do tique; o tique seguinte não refaz',
    e ->> 'aplicadas' = '1' and jsonb_array_length(e -> 'os') = 1 and e -> 'os' @> to_jsonb(pg_temp.os('OS-00112'))
    and jsonb_array_length(e -> 'acoes') = 1 and d ->> 'aplicadas' = '0'
    and v_t = 'OS-00112 4 orcamento'
    and (select q.estado = 'aberta' from public.agenda_perguntas q where q.id = v_qg)
    and x.estado = 'resolvida' and x.resolvida_motivo = 'sem resposta até sex 30/10 18:00: ficou como eu disse'
    and x.opcao_escolhida = 1 and x.respondida_em is null,
    e::text || ' | ' || v_t || ' | ' || coalesce(x.resolvida_motivo, '-'));
  select * into ac from public.agenda_acoes a where a.pergunta_id = v_qn and a.tipo = 'estimar';
  select count(*) into v_n from public.agenda_acoes;
  v_res := pg_temp.ok(v_res, 'Q3d a ação estimar do prazo (§6.4): "Sem resposta sobre Nelson até sex 30/10 às 18:00: contei o serviço inteiro, 4 dias (estimativa minha). *desfaz Nelson* volta.", origem vigia, executada, desfazível por desfazer_validade',
    ac.texto = 'Sem resposta sobre Nelson até sex 30/10 às 18:00: contei o serviço inteiro, 4 dias (estimativa minha). *desfaz Nelson* volta.'
    and ac.origem = 'vigia' and ac.executada and not ac.critica and ac.dia = c_sex and ac.autor is null
    and ac.desfazivel_ate = c_tique + (select desfazer_validade from public.agenda_config where id)
    and ac.service_order_id = pg_temp.os('OS-00112') and v_n = v_k + 1,
    coalesce(ac.texto, '-') || ' | ' || coalesce(ac.origem, '-'));
  e := public._agenda_classe_agora(pg_temp.os('OS-00112'), c_sex) - 'pront';
  v_res := pg_temp.ok(v_res, 'Q3e com os dias gravados, o Nelson sai do "já começou?" (a classe deixa de ser situacao)',
    e ->> 'motivo' <> 'situacao' and e ->> 'classe' <> '4', e::text);
  -- respondida pelo dono (a opção 2, aberta) não vence; o dono que já disse os dias vence o prazo
  begin
    v_q := (public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-97001'), c_hoje, c_agora, false) ->> 'pergunta_id')::uuid;
    -- (correção da 7a, achado 21: o Sérgio, com a peça embutida, não é mais perguntado; a pergunta com prazo é a do MP, sem mão de
    -- obra separada)
    v_q2 := (public._agenda_gestor_perguntas_da_os(pg_temp.os('ORÇ-00095'), c_hoje, c_agora, false) ->> 'pergunta_id')::uuid;
    update public.agenda_perguntas set mostrada_vezes = 1, mostrada_em = timestamptz '2026-10-29 17:30-03', mostrada_via = 'fechamento'
     where id in (v_q, v_q2);
    d := public.agenda_decidir(v_q, 2::smallint, v_adm, 'whatsapp', '2', c_hoje, timestamptz '2026-10-29 17:40-03');
    insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em)
    values (pg_temp.os('ORÇ-00095'), 3, 'dono', timestamptz '2026-10-30 09:00-03')
    on conflict (service_order_id) do update set dias = 3, estimativa_fonte = 'dono', estimativa_em = excluded.estimativa_em;
    e := public._agenda_gestor_vetos(c_sex, c_tique);
    select string_agg(q.estado || ':' || coalesce(q.resolvida_motivo, '-'), ' | ' order by q.chave) into v_t
      from public.agenda_perguntas q where q.id in (v_q, v_q2);
    select pl2.dias || ' ' || pl2.estimativa_fonte into v_t2 from public.os_planejamento pl2 where pl2.service_order_id = pg_temp.os('ORÇ-00095');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q3f a respondida pelo dono (opção 2, ainda aberta) não vence (respondidas 1); com os dias do dono gravados, o prazo não grava nada e a pergunta resolve "você já disse os dias" (sem_condicao 1)',
    e ->> 'aplicadas' = '0' and e ->> 'respondidas' = '1' and e ->> 'sem_condicao' = '1'
    and v_t = 'resolvida:você já disse os dias | aberta:-' and v_t2 = '3.0 dono',
    e::text || ' | ' || coalesce(v_t, '-') || ' | ' || coalesce(v_t2, '-'));
  begin
    perform public._agenda_gestor_perguntar('onda', 'onda:teste:p4', null, 'Mudou muita coisa de uma vez.',
      '[{"n": 1, "texto": "Faço tudo"}, {"n": 2, "texto": "Não mudo nada"}]'::jsonb, 1::smallint, c_prazo, 1::smallint,
      'ligado', c_agora);
    v_n := 0;
  exception when sqlstate '23514' then v_n := 1;
  end;
  v_res := pg_temp.ok(v_res, 'Q3g pergunta crítica nunca tem prazo: o CHECK veto_nao_critica recusa (23514)', v_n = 1, v_n::text);

  -- ── Q4. _agenda_gestor_gravar_dias ──────────────────────────────────────────────────────────────────────
  select * into pl from public.os_planejamento where service_order_id = pg_temp.os('OS-00112');
  e := pl.historico -> (jsonb_array_length(pl.historico) - 1);
  v_res := pg_temp.ok(v_res, 'Q4a os dias do prazo: os_planejamento.dias 4, fonte orcamento, estimativa_em = o tique; o histórico com as chaves do planejar (em = o dia em Brasília, por gestor, antes nulo, depois 4/orcamento) e a pergunta',
    pl.dias = 4 and pl.estimativa_fonte = 'orcamento' and pl.estimativa_em = c_tique and pl.atualizado_por is null
    and e ->> 'em' = '2026-10-30' and e ->> 'por' = 'gestor' and e ->> 'pergunta' = v_qn::text and e ->> 'quando' is not null
    and e -> 'antes' = jsonb_build_object('dias', null, 'estimativa_fonte', null, 'estimativa_em', null)
    and e #>> '{depois,dias}' = '4' and e #>> '{depois,estimativa_fonte}' = 'orcamento',
    e::text);
  v_res := pg_temp.ok(v_res, 'Q4b a ação estimar leva o antes que o *desfaz* do P7 devolve (dias, estimativa_fonte, estimativa_em nulos) e o depois',
    ac.antes = jsonb_build_object('dias', null, 'estimativa_fonte', null, 'estimativa_em', null)
    and ac.depois ->> 'dias' = '4' and ac.depois ->> 'estimativa_fonte' = 'orcamento' and ac.pergunta_id is not null
    and ac.motivo = 'sem resposta até o prazo',
    ac.antes::text || ' | ' || ac.depois::text);
  begin
    -- sobre os dias do dono e do aceito, nada
    -- (correção da 7a, achado 20: o Giancarlo não ganhou os 10 dias pelo prazo — a linha pode não existir)
    insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em)
    values (pg_temp.os('OS-00130'), 2, 'dono', c_tique)
    on conflict (service_order_id) do update set dias = 2, estimativa_fonte = 'dono';
    v_a := public._agenda_gestor_gravar_dias(pg_temp.os('OS-00130'), 10, 'teste', null, c_tique);
    select pl2.dias || ' ' || pl2.estimativa_fonte into v_t from public.os_planejamento pl2 where pl2.service_order_id = pg_temp.os('OS-00130');
    update public.os_planejamento set estimativa_fonte = 'aceita' where service_order_id = pg_temp.os('OS-00130');
    v_a2 := public._agenda_gestor_gravar_dias(pg_temp.os('OS-00130'), 10, 'teste', null, c_tique);
    select count(*) into v_n from public.agenda_acoes a where a.texto = 'teste';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q4c os dias do dono vencem: sobre dono e aceita, nada é gravado (null, sem ação)',
    v_a is null and v_a2 is null and v_t = '2.0 dono' and v_n = 0, coalesce(v_t, '-'));
  v_n := 0;
  foreach v_t in array array['0', '0.3', '61'] loop
    begin
      perform public._agenda_gestor_gravar_dias(pg_temp.os('OS-00104'), v_t::numeric, 'teste', null, c_tique);
    exception when sqlstate '22023' then v_n := v_n + 1;
    end;
  end loop;
  v_res := pg_temp.ok(v_res, 'Q4d duração que não é meio dia em meio dia, até 60 (0; 0,3; 61): 22023', v_n = 3, v_n::text);

  -- ── Q5. A limpeza ───────────────────────────────────────────────────────────────────────────────────────
  begin
    v_q := (public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-97001'), c_hoje, c_agora, false) ->> 'pergunta_id')::uuid;
    v_q2 := (public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-97002'), c_hoje, c_agora, false) ->> 'pergunta_id')::uuid;
    v_a := (public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-00104'), c_hoje, c_agora, false) ->> 'pergunta_id')::uuid;
    -- com *gestor, só propor*: o motivo não é reavaliado (a OS que passou a esperar o cliente continua com a pergunta)
    update public.service_orders set status = 'awaiting_client' where id = pg_temp.os('OS-00104');
    update public.agenda_config set gestor_so_propor = true where id;
    perform public._agenda_vigia_limpeza(c_sex, timestamptz '2026-10-30 09:00-03');
    select q.estado into v_t2 from public.agenda_perguntas q where q.id = v_a;
    update public.agenda_config set gestor_so_propor = false where id;
    -- o dono disse os dias do Paulo pelo *grava*; o Sérgio saiu da carteira; o Flávio passou a esperar o cliente
    insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em)
    values (pg_temp.os('OS-97001'), 1.5, 'dono', timestamptz '2026-10-30 08:00-03')
    on conflict (service_order_id) do update set dias = 1.5, estimativa_fonte = 'dono', estimativa_em = excluded.estimativa_em;
    update public.service_orders set status = 'completed' where id = pg_temp.os('OS-97002');
    p := public._agenda_vigia_limpeza(c_sex, timestamptz '2026-10-30 09:15-03');
    select string_agg(so.service_order_number || ':' || q.estado || ':' || coalesce(q.resolvida_motivo, '-'), ' | '
                      order by so.service_order_number)
      into v_t
      from public.agenda_perguntas q join public.service_orders so on so.id = q.service_order_id where q.id in (v_q, v_q2, v_a);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q5 a limpeza: o Paulo com os dias ditos ("você respondeu"), o Flávio esperando o cliente ("não precisa mais"); o Sérgio, com a peça embutida, nem foi perguntado (correção da 7a, achado 21); com *gestor, só propor*, o motivo não é reavaliado',
    v_t = 'OS-00104:resolvida:não precisa mais | OS-97001:resolvida:você respondeu' and v_q2 is null
    and v_t2 = 'aberta' and (p ->> 'resolvidas')::int >= 2,
    coalesce(v_t, '-') || ' | só propor: ' || coalesce(v_t2, '-'));

  -- ── Q6. agenda_decidir ──────────────────────────────────────────────────────────────────────────────────
  -- os 10 tipos do gestor vão ao despacho (que responde com gestor = true); os de antes não
  begin
    -- (o reavaliar e o reestimar são da revisão; o compre_ate, da cobrança: os modos deles ligados também)
    update public.agenda_config set modo_revisao_diaria = 'ligado', modo_compre_ate = 'ligado' where id;
    select string_agg(t.tipo || '=' || coalesce(r2.r ->> 'gestor', 'não') || ':' || (r2.r ->> 'texto'), ' | ' order by t.tipo)
      into v_t
      from (values ('situacao', false), ('estimativa', false), ('reavaliar', false), ('reestimar', false), ('ficha_estimativa', false),
                   ('onda', true), ('sabado', true), ('bem_livre', false), ('compre_ate', false), ('sinal', false),
                   ('equipe_cadastro', false), ('duracao', false), ('dia_avisado', true)) t(tipo, crit)
     cross join lateral (
       select public.agenda_decidir(public._agenda_gestor_perguntar(t.tipo, t.tipo || ':teste:p4', pg_temp.os('OS-00074'),
                'Pergunta de teste do ' || t.tipo || '.',
                case when t.crit or t.tipo in ('situacao', 'estimativa', 'reavaliar', 'reestimar', 'ficha_estimativa')
                     then '[{"n": 1, "texto": "Um"}, {"n": 2, "texto": "Dois"}]'::jsonb else '[]'::jsonb end,
                case when t.crit or t.tipo in ('situacao', 'estimativa', 'reavaliar', 'reestimar', 'ficha_estimativa') then 1::smallint end,
                null, null, case when t.tipo = 'dia_avisado' then 'sombra' else 'ligado' end, c_agora),
              1::smallint, v_adm, 'whatsapp', '1', c_hoje, c_agora) as r) r2;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- (7a P8: a onda decide no despacho — a opção sem efeito conhecido, como a deste teste, "não tem o que fazer"; 7a P9: o
  -- reavaliar e o reestimar também; 7a P11: a ficha_estimativa também; 7a P12: o sabado também)
  v_res := pg_temp.ok(v_res, 'Q6a agenda_decidir manda os 10 tipos do gestor ao despacho (gestor = true: bem_livre, compre_ate e sinal "não tem opções"; a onda, do P8, o reavaliar e o reestimar, do P9, a ficha_estimativa, do P11, e o sabado, do P12, "não tem o que fazer" com a opção sem efeito) e não os de antes (equipe_cadastro e duracao: "não é de decisão"; dia_avisado: a crítica de sempre)',
    v_t = 'bem_livre=true:Essa pergunta não tem opções: me responda com as suas palavras.'
          || ' | compre_ate=true:Essa pergunta não tem opções: me responda com as suas palavras.'
          || ' | dia_avisado=não:A agenda automática ainda está em teste: mostro como ficaria, mas não marco nada.'
          || ' | duracao=não:Essa pergunta não é de decisão. | equipe_cadastro=não:Essa pergunta não é de decisão.'
          || ' | estimativa=true:Essa opção não tem o que fazer: nada mudou.'
          || ' | ficha_estimativa=true:Essa opção não tem o que fazer: nada mudou.'
          || ' | onda=true:Essa opção não tem o que fazer: nada mudou.'
          || ' | reavaliar=true:Essa opção não tem o que fazer: nada mudou.'
          || ' | reestimar=true:Essa opção não tem o que fazer: nada mudou.'
          || ' | sabado=true:Essa opção não tem o que fazer: nada mudou.'
          || ' | sinal=true:Essa pergunta não tem opções: me responda com as suas palavras.'
          || ' | situacao=true:Essa opção não tem o que fazer: nada mudou.',
    v_t);
  -- situacao/estimativa pelo dono
  begin
    p := public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-97001'), c_hoje, c_agora, false);
    d := public.agenda_decidir((p ->> 'pergunta_id')::uuid, 1::smallint, v_adm, 'whatsapp', '1', c_hoje, timestamptz '2026-10-29 17:40-03');
    select * into x from public.agenda_perguntas q where q.id = (p ->> 'pergunta_id')::uuid;
    select * into ac from public.agenda_acoes a where a.id = (d ->> 'acao_id')::uuid;
    select * into pl from public.os_planejamento where service_order_id = pg_temp.os('OS-97001');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q6b a opção 1 pelo dono: a pergunta respondida (o dono, whatsapp, "1"), 1 dia gravado com a fonte orcamento, a ação estimar de origem dono com "Combinado, Paulo: contei 1 dia para terminar (estimativa minha). *desfaz Paulo* volta."',
    (d ->> 'ok')::boolean and x.estado = 'respondida' and x.opcao_escolhida = 1 and x.respondida_por = v_adm and x.respondida_via = 'whatsapp'
    and x.resposta = '1' and pl.dias = 1 and pl.estimativa_fonte = 'orcamento' and pl.atualizado_por = v_adm
    and ac.origem = 'dono' and ac.autor = v_adm and ac.motivo = 'você escolheu na pergunta'
    and ac.texto = 'Combinado, Paulo: contei 1 dia para terminar (estimativa minha). *desfaz Paulo* volta.'
    and d ->> 'texto' = ac.texto and pl.historico -> (jsonb_array_length(pl.historico) - 1) ->> 'por' = 'dono',
    d::text);
  -- (correção da 7a, achado 21: a peça embutida do Sérgio não pergunta mais; a opção 2 é provada no grande do Giancarlo, que desde
  -- o achado 20 não tem prazo e recomenda a 2)
  begin
    p := public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-00130'), c_hoje, c_agora, false);
    d := public.agenda_decidir((p ->> 'pergunta_id')::uuid, 2::smallint, v_adm, 'whatsapp', 'eu digo', c_hoje, c_agora);
    select * into x from public.agenda_perguntas q where q.id = (p ->> 'pergunta_id')::uuid;
    e := public.agenda_decidir((p ->> 'pergunta_id')::uuid, 5::smallint, v_adm, 'whatsapp', '5', c_hoje, c_agora);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q6c a opção 2: "Me diga os dias (ex.: ''Giancarlo 3 dias'')." e a pergunta fica aberta com a escolha; a opção que não existe lista as opções',
    (d ->> 'ok')::boolean and (d ->> 'aberta')::boolean and d ->> 'texto' = 'Me diga os dias (ex.: ''Giancarlo 3 dias'').'
    and x.estado = 'aberta' and x.opcao_escolhida = 2 and x.resposta = 'eu digo'
    -- (correção 2 da 7a, achado 20 de novo: a 3ª opção do serviço grande)
    and not (e ->> 'ok')::boolean and e ->> 'texto' = 'Essa opção não existe. As opções são: 1) Marque 10 dias; 2) Eu digo os dias; 3) Já terminou (ou já entreguei).',
    d::text || ' | ' || e::text);
  begin
    p := public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-00104'), c_hoje, c_agora, false);
    d := public.agenda_decidir((p ->> 'pergunta_id')::uuid, 3::smallint, v_adm, 'whatsapp', '3', c_hoje, c_agora);
    select q.estado into v_t from public.agenda_perguntas q where q.id = (p ->> 'pergunta_id')::uuid;
    e := public.agenda_decidir((p ->> 'pergunta_id')::uuid, 1::smallint, v_adm, 'whatsapp', '1', c_hoje, c_agora);
    p := public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-00069'), date '2026-11-05', timestamptz '2026-11-05 16:52-03', false);
    v_d2 := public.agenda_decidir((p ->> 'pergunta_id')::uuid, 3::smallint, v_adm, 'whatsapp', '3', date '2026-11-05',
                                timestamptz '2026-11-05 17:40-03');
    select count(*) into v_n from public.os_planejamento pl2
     where pl2.service_order_id in (pg_temp.os('OS-00104'), pg_temp.os('OS-00069')) and pl2.dias is not null;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Q6d a opção 3: "Use *concluiu Flávio*." (nada é concluído aqui) e, na parada, "Combinado: não marco Vanderlei. …" — as duas respondidas, sem dias; responder de novo = "já foi respondida"',
    (d ->> 'ok')::boolean and d ->> 'texto' = 'Use *concluiu Flávio*.' and v_t = 'respondida'
    and not (e ->> 'ok')::boolean and e ->> 'texto' = 'Essa pergunta já foi respondida ou resolvida.'
    and (v_d2 ->> 'ok')::boolean and v_d2 ->> 'texto' = 'Combinado: não marco Vanderlei. Para tirar o serviço da carteira, cancele a OS.'
    and v_n = 0,
    d::text || ' | ' || e::text || ' | ' || v_d2::text);
  begin
    p := public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-97001'), c_hoje, c_agora, false);
    update public.agenda_config set gestor_so_propor = true where id;
    d := public.agenda_decidir((p ->> 'pergunta_id')::uuid, 1::smallint, v_adm, 'whatsapp', '1', c_hoje, c_agora);
    update public.agenda_config set gestor_so_propor = false where id;
    insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em)
    values (pg_temp.os('OS-97001'), 2, 'dono', c_agora)
    on conflict (service_order_id) do update set dias = 2, estimativa_fonte = 'dono', estimativa_em = excluded.estimativa_em;
    e := public.agenda_decidir((p ->> 'pergunta_id')::uuid, 1::smallint, v_adm, 'whatsapp', '1', c_hoje, c_agora);
    select q.estado || ':' || q.resolvida_motivo into v_t from public.agenda_perguntas q where q.id = (p ->> 'pergunta_id')::uuid;
    select pl2.dias || ' ' || pl2.estimativa_fonte into v_t2 from public.os_planejamento pl2 where pl2.service_order_id = pg_temp.os('OS-97001');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform public._agenda_gestor_decidir((p ->> 'pergunta_id')::uuid, 1::smallint, v_adm, 'sms', null, c_hoje, c_agora);
    v_n := 0;
  exception when sqlstate '22023' then v_n := 1;
  end;
  v_res := pg_temp.ok(v_res, 'Q6e com *gestor, só propor* a decisão não muda nada ("está em teste"); com os dias do dono já gravados, a opção 1 não grava e a pergunta resolve ("Não mudei nada: você já disse os dias."); canal desconhecido = 22023',
    not (d ->> 'ok')::boolean and d ->> 'texto' = 'O gestor da agenda está em teste: mostro o que eu faria, mas não mudo nada.'
    and not (e ->> 'ok')::boolean and (e ->> 'sem_condicao')::boolean and e ->> 'texto' = 'Não mudei nada: você já disse os dias.'
    and v_t = 'resolvida:você já disse os dias' and v_t2 = '2.0 dono' and v_n = 1,
    d::text || ' | ' || e::text || ' | ' || coalesce(v_t, '-'));

  perform pg_temp.gravar(v_res);
end
$fx$;

-- ── Q7. As cópias ───────────────────────────────────────────────────────────────────────────────────────
do $copia$
declare
  v_c6   text := coalesce(current_setting('agenda_teste.mig_correcao_calculo_fase6', true), '');
  v_rv   text := coalesce(current_setting('agenda_teste.mig_correcao_revisao', true), '');
  v_novo text;
begin
  if v_c6 = '' or v_rv = '' then
    insert into _resultado values ('Q7 as cópias só acrescentam os blocos "-- FASE 7:"', true,
      'PULADO: sem agenda_teste.mig_correcao_calculo_fase6 / mig_correcao_revisao (rode pela bancada)');
    return;
  end if;
  select replace(p.prosrc, E'\r\n', E'\n') into v_novo
    from pg_proc p where p.oid = 'public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz)'::regprocedure;
  insert into _resultado values ('Q7a agenda_decidir: sem o bloco "-- FASE 7:" (o despacho do gestor), é o corpo de 20261029100900',
    pg_temp.sem_fase7(v_novo) = pg_temp.corpo(v_c6, 'agenda_decidir')
    and (select count(*) from regexp_matches(v_novo, '-- FASE 7: fim', 'g')) = 1,
    format('fonte %s × novo sem blocos %s caracteres', length(pg_temp.corpo(v_c6, 'agenda_decidir')), length(pg_temp.sem_fase7(v_novo))));
  select replace(p.prosrc, E'\r\n', E'\n') into v_novo
    from pg_proc p where p.oid = 'public._agenda_vigia_limpeza(date, timestamptz)'::regprocedure;
  insert into _resultado values ('Q7b _agenda_vigia_limpeza: sem o bloco "-- FASE 7:" (a pergunta do gestor), é o corpo de 20261030100500',
    pg_temp.sem_fase7(v_novo) = pg_temp.corpo(v_rv, '_agenda_vigia_limpeza')
    and (select count(*) from regexp_matches(v_novo, '-- FASE 7: fim', 'g')) = 1,
    format('fonte %s × novo sem blocos %s caracteres', length(pg_temp.corpo(v_rv, '_agenda_vigia_limpeza')), length(pg_temp.sem_fase7(v_novo))));
end
$copia$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
