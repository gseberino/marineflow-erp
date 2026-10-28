-- Prova do cliente no aprendizado da Agenda de Produção, Fase 6 (pacote P5; migration 20261029100500): a 1ª data dita ao
-- cliente (que nunca zera), a pontualidade medida contra ela e a folga do aviso de atraso (a faixa do M6).
-- bancada: depende de 20261029100900
--
--   C1 a 1ª promessa: a 1ª gravação grava, a 2ª não muda; o aviso "ainda faltam peças sem data" (o caminho real: a rodada, a
--      fila e o envio) zera o prometido e o original, e não a 1ª; a promessa seguinte acha a de antes; o preenchimento da
--      migration (pelo histórico, pelo original, pela 1ª data do histórico; só onde é nula; 2× = 1×) e a medida igual
--   C2 a pontualidade (5 de 7; o atraso chega a 2 dias úteis): só medida — em teste e ligada com todos os itens continua em
--      teste, sem ação, sem pergunta, e o leitor devolve nulo; abaixo do mínimo, medindo; a reaberta sai da conta
--   C3 a folga (2 dias úteis): em teste e ligada sem "aviso_cliente", a faixa de sempre; ligada, entra sozinha (a ação com o
--      texto da spec) e só o fim da faixa da peça e da execução anda (o início, o fim novo, o risco e o atraso não); o M6
--      novo diz a faixa nova (o modelo de sempre); o peca_sem_data e o remarcado não mudam; o teto, a troca grande (pergunta,
--      sem folga enquanto espera) e o abaixo do mínimo; o modo em teste volta a faixa na hora
--   C4 o estouro do risco pelo fator de campo: a OS com 6,5 meios-dias feitos de 4 estoura com 1,5× e não com 1,7× em uso;
--      ligado sem "fator" na lista, o de sempre; o técnico numa cadeia definer fica com o padrão (sem 42501), e o técnico
--      direto continua sem alcançar a agenda (P0002, como antes); o service_role (a rodada) usa o aprendido
--   C5 as cópias só acrescentam os blocos "-- FASE 6:" (o cabeçalho de cada uma igual); o risco sem os blocos da correção e da
--      Fase 6 é o de 20261028100300 (o C2z); as portas; nada na migration escreve mensagem a terceiros
--   C6 o risco da spec (o M6 registrado e ainda não enviado quando a folga liga): o aviso vivo não é recusado nem trocado —
--      sai com a faixa de antes (sem a folga), a rodada não registra outro (a chave), e depois de sair o plano cabe na faixa
--      que o cliente ouviu (nenhum aviso a mais). A folga vale do aviso seguinte em diante
--   C7 byte a byte: em teste, ligado sem a lista e ligado com as perguntas abertas (nada em uso), o risco de cada OS ativa em
--      4 dias e a rodada do cliente inteira (as mensagens, as perguntas e as ações de 4 tiques e um envio) saem iguais às das
--      definições de 20261028100800/20261028100100 (rodadas no lugar por um instante); o controle, com a folga e o fator em
--      uso, acusa a diferença
--   C8 (correção C1, 20261029100900) o teto no P80 da folga (2,2 → 3); a folga mede contra o fim do plano (faixa_ate_plano),
--      sem o vaivém de 2 para 0
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase6_cliente.sql
--   Seguro em produção: tudo dentro de begin/rollback. C5 roda em qualquer lugar (as cópias só com as migrations como texto);
--   C1 a C4, C6 e C7 só na bancada (a fixture-fase6; fora dela, PULADO). Nenhuma mensagem sai.
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

-- Roda p_sql como p_papel (com o login p_uid, ou sem login): o texto do resultado, ou 'erro <estado>: <mensagem>'.
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
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;

-- O risco chamado de dentro de uma função security definer (o caminho de uma cadeia definer com o login de quem chama).
create function pg_temp.risco_por_definer(p_os uuid, p_hoje date) returns jsonb language sql security definer as $f$
  select public._agenda_cliente_risco(p_os, p_hoje)
$f$;

create function pg_temp.os(p_n text) returns uuid language sql immutable as $f$
  select ('05000000-0000-4000-8000-000000000' || lpad(p_n, 3, '0'))::uuid
$f$;

-- A hora de Brasília escrita como se fala: pg_temp.em('2026-10-30 10:00') = timestamptz '2026-10-30 10:00-03'.
create function pg_temp.em(p_quando text) returns timestamptz language sql immutable as $f$
  select (p_quando::timestamp) at time zone 'America/Sao_Paulo'
$f$;

-- Liga a mensagem ao cliente (todos os tipos), sem a aprovação dos primeiros dias.
create function pg_temp.ligar_cliente() returns void language sql as $f$
  update public.agenda_config
     set modo_cliente = 'ligado', cliente_aprovacao_dias = 0,
         cliente_tipos_ligados = array['confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento', 'pode_atrasar',
                                       'nova_data', 'pronto', 'pronto_lembrete', 'pos_servico', 'mudanca_no_dia']
   where id
$f$;

-- Um tique da rodada do cliente, com o "hoje" de quem lê o relógio (_hoje_brt) acompanhando.
create function pg_temp.vig(p_quando text) returns jsonb language plpgsql as $f$
begin
  perform set_config('agenda_teste.hoje', left(p_quando, 10), true);
  return public.agenda_cliente_vigiar(left(p_quando, 10)::date, pg_temp.em(p_quando));
end $f$;

-- Os avisos de atraso de uma OS (sem a mensagem do Nelson de 22/10, da fixture), na ordem em que nasceram.
create function pg_temp.avisos(p_os uuid) returns jsonb language sql stable as $f$
  select coalesce(jsonb_agg(jsonb_build_object('variante', m.variante, 'modo', m.modo, 'estado', m.estado, 'motivo', m.recusa_motivo,
                                               'faixa_de', m.faixa_de, 'faixa_ate', m.faixa_ate, 'texto', m.texto, 'id', m.id,
                                               'chave', m.dedupe_key)
                            order by m.criada_em, m.id), '[]'::jsonb)
    from public.agenda_cliente_mensagens m
   where m.service_order_id = p_os and m.tipo = 'pode_atrasar' and m.id <> 'd5000000-0000-4000-8000-0000000000a1'
$f$;

-- A linha da fila de uma mensagem sai (o worker): o gatilho do envio faz o resto.
create function pg_temp.saiu(p_msg uuid, p_quando text) returns void language sql as $f$
  update public.whatsapp_send_queue set status = 'sent', sent_at = pg_temp.em(p_quando), attempts = 1
   where source = 'agenda-cliente' and source_ref_id = p_msg
$f$;

-- O Nelson (OS-00112) com todos os críticos com previsão (ter 10/11, do dono): o M6 da peça (faixa qui 12 a sex 13/11).
create function pg_temp.nelson_com_data() returns void language sql as $f$
  update public.os_material set situacao = 'comprado', comprado_em = date '2026-10-28', comprado_fonte = 'dono', fonte = 'dono',
         previsao_ate = date '2026-11-10', previsao_fonte = 'dono'
   where service_order_part_id in (md5('peca:112:1')::uuid, md5('peca:112:2')::uuid, md5('peca:112:3')::uuid)
$f$;

-- A OS-00100 (Giancarlo, energia em motorhome) em andamento, com 2 dias ditos pelo dono (4 meios-dias) e o Roberto no plano
-- de ter 13 a sex 16/10, conferido: 6 meios-dias cumpridos e um parcial (6,5 feitos); o cliente ouviu sex 30/10 (o mesmo
-- cenário do O3 de agenda_fase6_os.sql).
create function pg_temp.giancarlo_em_andamento() returns void language plpgsql as $f$
begin
  perform set_config('agenda.porta', 'on', true);
  update public.service_orders set status = 'in_progress', check_in_at = timestamptz '2026-10-13 08:00-03'
   where id = pg_temp.os('100');
  perform set_config('agenda.porta', 'off', true);
  update public.os_planejamento set dias = 2, estimativa_fonte = 'dono' where service_order_id = pg_temp.os('100');
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em,
                                       resultado, motivo, resultado_via, resultado_em)
  select pg_temp.os('100'), 'bb000000-0000-4000-8000-000000000002', dia::date, turno, 'turno', 'execucao', 'publicada', 'motor',
         (dia::date - 1 + time '16:30') at time zone 'America/Sao_Paulo', resultado, motivo, 'dia_feito',
         (dia::date + time '17:30') at time zone 'America/Sao_Paulo'
    from (values ('2026-10-13', 'manha', 'cumprido', null), ('2026-10-13', 'tarde', 'cumprido', null),
                 ('2026-10-14', 'manha', 'cumprido', null), ('2026-10-14', 'tarde', 'cumprido', null),
                 ('2026-10-15', 'manha', 'cumprido', null), ('2026-10-15', 'tarde', 'cumprido', null),
                 ('2026-10-16', 'manha', 'parcial', 'imprevisto_tecnico')) a(dia, turno, resultado, motivo);
  perform public._agenda_cliente_gravar_prometido(pg_temp.os('100'), 'firme', date '2026-10-30', date '2026-10-30', 'dono', null,
                                                  pg_temp.em('2026-10-29 10:00'), 'teste do P5');
end $f$;

-- O aprendizado do dia (as medidas, o fator e o cliente), no modo e com a lista dados.
create function pg_temp.aprender(p_modo text, p_lista text[]) returns jsonb language plpgsql as $f$
begin
  update public.agenda_config set modo_aprendizado = p_modo, aprendizado_ligados = p_lista where id;
  perform public._agenda_aprender_medir(date '2026-10-30');
  perform public._agenda_aprender_fator(date '2026-10-30', pg_temp.em('2026-10-30 16:05'));
  return public._agenda_aprender_cliente(date '2026-10-30', pg_temp.em('2026-10-30 16:05'));
end $f$;

-- O corpo de uma função numa migration (entre "as $tag$" e o fecho) e a função inteira (do "create or replace" ao fecho).
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
  v_tag text;
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v_tag := (regexp_match(v, E'\nas (\\$[a-z]*\\$)\n'))[1];
  v := substr(v, position(E'\nas ' || v_tag || E'\n' in v) + length(E'\nas ' || v_tag));
  return left(v, position(E'\n' || v_tag || ';' in v));
end $f$;
create function pg_temp.inteira(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  return left(v, position(E'\n$function$;' in v) + length(E'\n$function$;') - 1);
end $f$;

-- As linhas fora dos blocos "-- FASE 6: … -- FASE 6: fim" (o fim é lido pelo prefixo, como nos testes de cópia de antes) e,
-- com p_correcao, também fora dos blocos "-- CORREÇÃO FASE 5:" (o que o C2z compara com a 20261028100300).
create function pg_temp.sem_blocos(p_corpo text, p_correcao boolean default false) returns text[] language plpgsql as $f$
declare
  v_b text[] := '{}'; v_f6 boolean := false; v_c5 boolean := false; l text;
begin
  foreach l in array string_to_array(replace(p_corpo, E'\r\n', E'\n'), E'\n') loop
    if not v_c5 and not v_f6 and l ~ '^\s*-- FASE 6:' and l !~ '^\s*-- FASE 6: fim' then v_f6 := true; continue; end if;
    if v_f6 then
      if l ~ '^\s*-- FASE 6: fim' then v_f6 := false; end if;
      continue;
    end if;
    if p_correcao and not v_c5 and l ~ '^\s*-- CORREÇÃO FASE 5:' and l !~ '^\s*-- CORREÇÃO FASE 5: fim' then v_c5 := true; continue; end if;
    if v_c5 then
      if l ~ '^\s*-- CORREÇÃO FASE 5: fim' then v_c5 := false; end if;
      continue;
    end if;
    v_b := v_b || l;
  end loop;
  return v_b;
end $f$;

-- O que a rodada do cliente deixou (sem os ids sorteados nem as horas do relógio): as mensagens, as perguntas e as ações.
create function pg_temp.retrato() returns text language sql stable as $f$
  select md5(coalesce((select string_agg(concat_ws('|', m.service_order_id, m.tipo, m.variante, m.modo, m.estado, m.recusa_motivo,
                                                   m.aprovacao, m.enviar_em, m.valida_ate, m.dia_alvo, m.faixa_de, m.faixa_ate,
                                                   m.prometido_tipo, m.texto, m.dedupe_key, m.enviada_em,
                                                   regexp_replace((m.base - 'envio')::text, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', 'ID', 'g')),
                                         E'\n' order by m.dedupe_key, m.texto)
                         from public.agenda_cliente_mensagens m), '')
             || coalesce((select string_agg(concat_ws('|', q.tipo, q.estado, q.modo, q.dia,
                                                   regexp_replace(q.chave, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', 'ID', 'g'),
                                                   q.texto, regexp_replace(q.opcoes::text, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', 'ID', 'g')),
                                         E'\n' order by q.tipo, regexp_replace(q.chave, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', 'ID', 'g'), q.texto)
                            from public.agenda_perguntas q where q.tipo like 'cliente%'), '')
             || coalesce((select string_agg(concat_ws('|', a.tipo, a.origem, a.service_order_id, a.dia, a.texto,
                                                   regexp_replace(a.depois::text, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', 'ID', 'g')),
                                         E'\n' order by a.service_order_id, a.texto)
                            from public.agenda_acoes a where a.tipo = 'cliente'), ''))
$f$;

-- A rodada do cliente de sex 30/10 a ter 03/11 (4 tiques e o envio do aviso do Nelson): a soma do que ela devolveu.
create function pg_temp.rodada() returns text language plpgsql as $f$
declare
  v text := '';
  v_id uuid;
begin
  v := v || (pg_temp.vig('2026-10-30 17:00') -> 'contagens')::text;
  v := v || (pg_temp.vig('2026-10-31 09:15') -> 'contagens')::text;
  select m.id into v_id from public.agenda_cliente_mensagens m
   where m.service_order_id = pg_temp.os('112') and m.tipo = 'pode_atrasar' and m.estado = 'enfileirada' limit 1;
  if v_id is not null then
    perform pg_temp.saiu(v_id, '2026-10-31 09:15:20');
  end if;
  v := v || (pg_temp.vig('2026-11-03 10:00') -> 'contagens')::text;
  v := v || (pg_temp.vig('2026-11-03 17:00') -> 'contagens')::text;
  return md5(v) || ':' || pg_temp.retrato();
end $f$;

-- ── C1. A 1ª promessa ───────────────────────────────────────────────────────────────────────────────────
do $c1$
declare
  v_res jsonb := '[]'::jsonb;
  v_mig text := coalesce(current_setting('agenda_teste.mig_cliente_fase6', true), '');
  c_nel constant uuid := '05000000-0000-4000-8000-000000000112';
  p   public.os_planejamento;
  j   jsonb;
  v_id uuid;
  v_a text;
  v_b text;
  v_m text;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' or v_mig = '' then
    insert into _resultado values ('C1 a 1ª promessa (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase6');

    -- (a) a OS que nunca ouviu data: a 1ª gravação grava a 1ª promessa; a 2ª muda o prometido e não a 1ª
    j := public._agenda_cliente_gravar_prometido(pg_temp.os('100'), 'firme', date '2026-10-30', date '2026-10-30', 'dono', null,
                                                 pg_temp.em('2026-10-29 10:00'), 'c1a');
    select * into p from public.os_planejamento where service_order_id = pg_temp.os('100');
    v_res := pg_temp.ok(v_res, 'C1a a 1ª data dita (sex 30/10) vai a prometido_primeiro_ate junto com o original; o retorno do gravador é o de sempre',
      p.prometido_primeiro_ate = date '2026-10-30' and p.prometido_original_ate = date '2026-10-30'
      and j = jsonb_build_object('gravou', true, 'os', pg_temp.os('100'), 'tipo', 'firme', 'de', '2026-10-30', 'ate', '2026-10-30',
                                 'original_ate', '2026-10-30', 'primeira_promessa', true),
      to_jsonb(p)::text || ' ' || j::text);
    perform public._agenda_cliente_gravar_prometido(pg_temp.os('100'), 'faixa', date '2026-11-03', date '2026-11-04', 'mensagem', null,
                                                    pg_temp.em('2026-10-30 17:00'), 'c1a 2');
    select * into p from public.os_planejamento where service_order_id = pg_temp.os('100');
    v_res := pg_temp.ok(v_res, 'C1b a 2ª promessa (03 a 04/11) muda o prometido e não a 1ª (nem o original)',
      p.prometido_ate = date '2026-11-04' and p.prometido_primeiro_ate = date '2026-10-30' and p.prometido_original_ate = date '2026-10-30',
      to_jsonb(p)::text);

    -- (b) o caminho real do aviso sem data: o Nelson ouviu qui 05/11 (o *grava* do dono de novo, para a linha da fixture
    -- ganhar a 1ª promessa); os críticos sem previsão → o M6 peca_sem_data sai → o prometido e o original zeram, a 1ª não
    perform public._agenda_cliente_gravar_prometido(c_nel, 'firme', date '2026-11-05', date '2026-11-05', 'dono', null,
                                                    pg_temp.em('2026-10-29 10:00'), 'c1c');
    perform pg_temp.ligar_cliente();
    perform pg_temp.vig('2026-10-30 17:00');
    perform pg_temp.vig('2026-10-31 09:15');
    v_id := (pg_temp.avisos(c_nel) -> 0 ->> 'id')::uuid;
    perform pg_temp.saiu(v_id, '2026-10-31 09:15:20');
    select * into p from public.os_planejamento where service_order_id = c_nel;
    v_res := pg_temp.ok(v_res, 'C1c o aviso "ainda faltam peças sem data" saiu de verdade: o prometido e o original ficam nulos (Fase 5), a 1ª promessa (qui 05/11) fica',
      pg_temp.avisos(c_nel) -> 0 ->> 'variante' = 'peca_sem_data'
      and (select m.estado from public.agenda_cliente_mensagens m where m.id = v_id) = 'enviada'
      and p.prometido_ate is null and p.prometido_original_ate is null and p.prometido_primeiro_ate = date '2026-11-05',
      to_jsonb(p)::text);
    -- as peças ganham data e o M7/M6 da nova data é gravado: o original recomeça (NOVO-agenda-44), a 1ª continua a de antes
    perform public._agenda_cliente_gravar_prometido(c_nel, 'faixa', date '2026-11-12', date '2026-11-13', 'mensagem', null,
                                                    pg_temp.em('2026-11-03 10:00'), 'c1d');
    select * into p from public.os_planejamento where service_order_id = c_nel;
    v_res := pg_temp.ok(v_res, 'C1d a promessa seguinte (12 a 13/11): o original vira a nova (como na Fase 5) e a 1ª promessa continua qui 05/11',
      p.prometido_ate = date '2026-11-13' and p.prometido_original_ate = date '2026-11-13' and p.prometido_primeiro_ate = date '2026-11-05',
      to_jsonb(p)::text);

    -- (c) o preenchimento da migration (rodado de novo aqui, inteiro): as linhas da fixture que só têm o original (131 a 136
    -- e as da Fase 5), a 137 que já tem a 1ª (fica), e três montadas: só o histórico do aviso sem data, o original novo com
    -- o histórico do de antes, e só a 1ª data gravada no histórico; uma sem nada fica nula
    insert into public.os_planejamento (service_order_id) values (pg_temp.os('104')) on conflict (service_order_id) do nothing;
    update public.os_planejamento
       set prometido_tipo = null, prometido_de = null, prometido_ate = null, prometido_original_ate = null,
           prometido_primeiro_ate = null,
           historico = '[{"em": "2026-10-20", "autor": null, "trecho": "aviso sem data", "antes": {"prometido_tipo": "firme", "prometido_ate": "2026-10-22", "prometido_original_ate": "2026-10-21"}, "depois": {"prometido_ate": null}}]'
     where service_order_id = pg_temp.os('104');
    update public.os_planejamento
       set prometido_tipo = 'faixa', prometido_de = date '2026-11-12', prometido_ate = date '2026-11-13',
           prometido_original_ate = date '2026-11-13', prometido_primeiro_ate = null,
           historico = '[{"em": "2026-10-01", "depois": {"dias": 2}}, {"em": "2026-10-20", "antes": {"prometido_ate": "2026-11-05", "prometido_original_ate": "2026-11-05"}, "depois": {"prometido_ate": null}}, {"em": "2026-11-03", "antes": {"prometido_ate": null}, "depois": {"prometido_ate": "2026-11-13"}}]'
     where service_order_id = c_nel;
    update public.os_planejamento
       set prometido_tipo = null, prometido_de = null, prometido_ate = null, prometido_original_ate = null,
           prometido_primeiro_ate = null,
           historico = '[{"em": "2026-10-02", "depois": {"dias": 1}}, {"em": "2026-10-05", "antes": {"prometido_ate": null}, "depois": {"prometido_tipo": "firme", "prometido_ate": "2026-10-09"}}, {"em": "2026-10-06", "antes": {"prometido_ate": "2026-10-09"}, "depois": {"prometido_ate": "2026-10-12"}}]'
     where service_order_id = pg_temp.os('100');
    perform public._agenda_aprender_medir(date '2026-10-30');
    v_m := md5((select string_agg(format('%s %s %s', x.service_order_id, x.prometido_primeiro_ate, x.atraso_cliente_du), ','
                                  order by x.service_order_id) from public.agenda_medidas_os x));
    execute v_mig;
    v_a := md5((select string_agg(to_jsonb(x)::text, ',' order by x.service_order_id) from public.os_planejamento x));
    execute v_mig;
    v_b := md5((select string_agg(to_jsonb(x)::text, ',' order by x.service_order_id) from public.os_planejamento x));
    v_res := pg_temp.ok(v_res, 'C1e o preenchimento: pelo histórico do aviso sem data (qua 21/10), pelo de antes do original novo (qui 05/11), pela 1ª data do histórico (sex 09/10); a 137 fica 23/10; a sem nada, nula',
      (select prometido_primeiro_ate from public.os_planejamento where service_order_id = pg_temp.os('104')) = date '2026-10-21'
      and (select prometido_primeiro_ate from public.os_planejamento where service_order_id = c_nel) = date '2026-11-05'
      and (select prometido_primeiro_ate from public.os_planejamento where service_order_id = pg_temp.os('100')) = date '2026-10-09'
      and (select prometido_primeiro_ate from public.os_planejamento where service_order_id = pg_temp.os('137')) = date '2026-10-23'
      and exists (select 1 from public.os_planejamento where prometido_primeiro_ate is null and prometido_original_ate is null
                     and not exists (select 1 from jsonb_array_elements(historico) e where e #>> '{depois,prometido_ate}' is not null
                                                                                      or e #>> '{antes,prometido_original_ate}' is not null)),
      (select string_agg(format('%s=%s', right(service_order_id::text, 3), prometido_primeiro_ate), ' ' order by 1)
         from public.os_planejamento where prometido_primeiro_ate is not null));
    v_res := pg_temp.ok(v_res, 'C1f o preenchimento só onde era nula: as do original (131 a 136) ganham ele; nenhuma linha fica com o original sem a 1ª; rodar 2× = 1×',
      v_a = v_b
      and not exists (select 1 from public.os_planejamento where prometido_original_ate is not null and prometido_primeiro_ate is null)
      and (select bool_and(prometido_primeiro_ate = prometido_original_ate) from public.os_planejamento
            where service_order_id between pg_temp.os('131') and pg_temp.os('136')),
      v_a || ' ' || v_b);
    perform public._agenda_aprender_medir(date '2026-10-30');
    v_res := pg_temp.ok(v_res, 'C1g a medida das concluídas não muda com o preenchimento (a mesma 1ª promessa e o mesmo atraso: o P1 já lia o original)',
      v_m = md5((select string_agg(format('%s %s %s', x.service_order_id, x.prometido_primeiro_ate, x.atraso_cliente_du), ','
                                    order by x.service_order_id) from public.agenda_medidas_os x)), v_m);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$c1$;

-- ── C2. A pontualidade ──────────────────────────────────────────────────────────────────────────────────
do $c2$
declare
  v_res jsonb := '[]'::jsonb;
  a public.agenda_aprendizado;
  j jsonb;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('C2 a pontualidade (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase6');
    j := pg_temp.aprender('sombra', '{}');
    select * into a from public.agenda_aprendizado where item = 'cliente_pontualidade' and chave = 'todas';
    v_res := pg_temp.ok(v_res, 'C2a 5 de 7 OS prontas até a 1ª data dita (0,71; a 137 pela 1ª promessa, 23/10); o atraso chega a 2 dias úteis; em teste; o texto da spec',
      a.calculado = 0.71 and a.n = 7 and a.n_min = 6 and a.estado = 'sombra' and a.em_uso is null and a.nivel = 'todas'
      and a.padrao is null and a.detalhe = '{"n": 7, "no_prazo": 5, "p80_atraso_du": 2}'::jsonb
      and a.texto = 'Pontualidade: 5 de 7 OS ficaram prontas até o dia dito primeiro ao cliente; o atraso chega a 2 dias úteis.'
      and jsonb_array_length(a.amostra) = 7 and a.amostra -> 0 ->> 'numero' = 'OS-00136'
      and (select string_agg(e ->> 'atraso_du', ',' order by e ->> 'numero') from jsonb_array_elements(a.amostra) e) = '0,-1,-1,-1,2,-1,2'
      and (a.amostra -> 0 ->> 'primeiro') = '2026-10-30'
      and (select e ->> 'primeiro' from jsonb_array_elements(a.amostra) e where e ->> 'numero' = 'OS-00137') = '2026-10-23',
      to_jsonb(a)::text);
    -- ligado com todos os itens na lista: continua só medida
    j := pg_temp.aprender('ligado', '{fator,mo,presenca,fornecedor,capacidade_dono,aviso_cliente,revisao}');
    select * into a from public.agenda_aprendizado where item = 'cliente_pontualidade' and chave = 'todas';
    v_res := pg_temp.ok(v_res, 'C2b ligado com todos os itens: a pontualidade continua em teste (só medida) — sem em uso, sem ação, sem pergunta; o leitor devolve nulo',
      a.estado = 'sombra' and a.em_uso is null and a.acao_id is null and a.pergunta_id is null
      and public._agenda_aprendido('cliente_pontualidade', 'todas') is null
      and not exists (select 1 from public.agenda_acoes x where x.tipo = 'aprendizado' and x.depois ->> 'item' = 'cliente_pontualidade')
      and not exists (select 1 from public.agenda_perguntas q where q.chave like 'aprendizado:cliente_pontualidade:%')
      and j #>> '{pontualidade,estado}' = 'sombra',
      to_jsonb(a)::text);
    -- abaixo do mínimo: medindo
    update public.agenda_config set cliente_n_min = 8 where id;
    j := pg_temp.aprender('sombra', '{}');
    select * into a from public.agenda_aprendizado where item = 'cliente_pontualidade' and chave = 'todas';
    v_res := pg_temp.ok(v_res, 'C2c com o mínimo em 8: medindo, e o texto diz quantas faltam',
      a.estado = 'medindo' and a.n = 7 and a.n_min = 8
      and a.texto = 'Pontualidade: 7 de 8 OS com a 1ª data dita ao cliente medidas.', to_jsonb(a)::text);
    update public.agenda_config set cliente_n_min = 6 where id;
    -- a reaberta sai da conta (a 135, que atrasou 2 dias úteis, volta para em andamento)
    perform set_config('agenda.porta', 'on', true);
    update public.service_orders set status = 'in_progress' where id = pg_temp.os('135');
    perform set_config('agenda.porta', 'off', true);
    j := pg_temp.aprender('sombra', '{}');
    select * into a from public.agenda_aprendizado where item = 'cliente_pontualidade' and chave = 'todas';
    v_res := pg_temp.ok(v_res, 'C2d a OS reaberta (135) sai da conta: 5 de 6',
      a.n = 6 and a.detalhe ->> 'no_prazo' = '5' and a.calculado = 0.83
      and (select motivo from public.agenda_medidas_os where service_order_id = pg_temp.os('135')) = 'reaberta',
      to_jsonb(a)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$c2$;

-- ── C3. A folga do aviso ────────────────────────────────────────────────────────────────────────────────
do $c3$
declare
  v_res jsonb := '[]'::jsonb;
  c_nel  constant uuid := '05000000-0000-4000-8000-000000000112';
  c_flav constant uuid := '05000000-0000-4000-8000-000000000104';
  c_hoje constant date := date '2026-10-30';
  a  public.agenda_aprendizado;
  j  jsonb;
  r0 jsonb;
  r1 jsonb;
  e0 jsonb;
  e1 jsonb;
  s0 jsonb;
  s1 jsonb;
  f0 jsonb;
  f1 jsonb;
  x  jsonb;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('C3 a folga do aviso (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase6');
    perform pg_temp.nelson_com_data();
    perform pg_temp.giancarlo_em_andamento();
    j := pg_temp.aprender('sombra', '{}');
    select * into a from public.agenda_aprendizado where item = 'aviso_folga' and chave = 'todas';
    r0 := public._agenda_cliente_risco(c_nel, c_hoje);
    e0 := public._agenda_cliente_risco(pg_temp.os('100'), c_hoje);
    v_res := pg_temp.ok(v_res, 'C3a em teste: os 5 avisos (estouros 2, 0, 2, 2 e 1; a correção C1 pôs a faixa da 136 até 27/10 na fixture) dão 2 dias úteis (P80 2); padrão 0; o texto da spec; o leitor devolve nulo',
      a.calculado = 2 and a.n = 5 and a.n_min = 5 and a.padrao = 0 and a.estado = 'sombra' and a.em_uso is null
      and a.detalhe = '{"n": 5, "p50": 2, "maior": 2, "no_prazo": 1}'::jsonb
      and a.texto = 'Avisos de atraso: em 5, o serviço terminou até 2 dias úteis depois do fim que eu disse (em teste: eu daria a faixa com 2 dias úteis a mais).'
      and jsonb_array_length(a.amostra) = 5 and public._agenda_aprendido('aviso_folga', 'todas') is null,
      to_jsonb(a)::text);
    v_res := pg_temp.ok(v_res, 'C3b em teste, a faixa de sempre: a peça do Nelson qui 12 a sex 13/11; a execução do Giancarlo ter 03 a qua 04/11',
      r0 ->> 'variante' = 'peca' and r0 ->> 'faixa_de' = '2026-11-12' and r0 ->> 'faixa_ate' = '2026-11-13'
      and e0 ->> 'variante' = 'execucao' and e0 ->> 'faixa_de' = '2026-11-03' and e0 ->> 'faixa_ate' = '2026-11-04',
      r0::text || ' ' || e0::text);
    -- ligado sem aviso_cliente na lista: nada muda
    j := pg_temp.aprender('ligado', '{fator,mo}');
    v_res := pg_temp.ok(v_res, 'C3c ligado sem "aviso_cliente" na lista: em teste, e a faixa de sempre',
      j #>> '{aviso_folga,estado}' = 'sombra' and public._agenda_cliente_risco(c_nel, c_hoje) = r0, j::text);
    -- ligado com aviso_cliente: a troca de 0 para 2 cabe (aviso_troca_max_du 2) → entra sozinha, com a ação
    j := pg_temp.aprender('ligado', '{aviso_cliente}');
    select * into a from public.agenda_aprendizado where item = 'aviso_folga' and chave = 'todas';
    v_res := pg_temp.ok(v_res, 'C3d ligado: entra sozinha (em uso 2), com a ação aprendizado do "o que mudou" (o texto da spec §6.3, desfazível)',
      a.estado = 'em_uso' and a.em_uso = 2 and public._agenda_aprendido('aviso_folga', 'todas') = 2
      and (select x.texto = 'Os avisos de atraso erraram para menos (5 avisos): passei a dar a faixa com 2 dias úteis a mais. *desfaz aprendizado* volta.'
                  and x.origem = 'vigia' and x.desfazivel_ate is not null and x.depois ->> 'em_uso' = '2'
             from public.agenda_acoes x where x.id = a.acao_id)
      and a.texto = 'Avisos de atraso: em 5, o serviço terminou até 2 dias úteis depois do fim que eu disse: dou a faixa com 2 dias úteis a mais desde sex 30/10.',
      to_jsonb(a)::text);
    r1 := public._agenda_cliente_risco(c_nel, c_hoje);
    e1 := public._agenda_cliente_risco(pg_temp.os('100'), c_hoje);
    v_res := pg_temp.ok(v_res, 'C3e com a folga, só o fim da faixa anda 2 dias úteis: a peça qui 12 a ter 17/11 (o início, o fim novo, o risco e o atraso iguais); a execução ter 03 a sex 06/11',
      r1 ->> 'faixa_ate' = '2026-11-17' and (r1 - 'faixa_ate') = (r0 - 'faixa_ate')
      and e1 ->> 'faixa_ate' = '2026-11-06' and (e1 - 'faixa_ate') = (e0 - 'faixa_ate'),
      r1::text || ' ' || e1::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- o peca_sem_data (o Nelson da fixture, críticos sem previsão) e o remarcado do Flávio (o mesmo de C2d da correção C2), com e
  -- sem a folga em uso
  begin
    execute current_setting('agenda_teste.fase6');
    perform public._agenda_cliente_gravar_prometido(c_flav, 'firme', date '2026-11-03', date '2026-11-03', 'dono', null,
                                                    pg_temp.em('2026-10-29 10:00'), 'c3');
    s0 := public._agenda_cliente_risco(c_nel, c_hoje);
    f0 := public._agenda_cliente_risco(c_flav, c_hoje);
    j := pg_temp.aprender('ligado', '{aviso_cliente}');
    s1 := public._agenda_cliente_risco(c_nel, c_hoje);
    f1 := public._agenda_cliente_risco(c_flav, c_hoje);
    v_res := pg_temp.ok(v_res, 'C3f o aviso "sem data" (peca_sem_data) e o remarcado só no fim (forma fim) não ganham a folga',
      public._agenda_aprendido('aviso_folga', 'todas') = 2
      and s0 ->> 'variante' = 'peca_sem_data' and s1 = s0 and f0 ->> 'variante' = 'remarcado' and f0 ->> 'forma' = 'fim' and f1 = f0,
      s1::text || ' / ' || f1::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- o M6 novo com a folga em uso: o modelo de sempre, a data nova dentro dele
  begin
    execute current_setting('agenda_teste.fase6');
    perform pg_temp.nelson_com_data();
    perform pg_temp.giancarlo_em_andamento();
    perform pg_temp.ligar_cliente();
    j := pg_temp.aprender('ligado', '{aviso_cliente}');
    perform pg_temp.vig('2026-10-30 17:00');
    v_res := pg_temp.ok(v_res, 'C3g o M6 registrado com a folga em uso diz a faixa nova no modelo de sempre (Nelson: "entre quinta (12/11) e terça (17/11)"; Giancarlo: "entre terça (03/11) e sexta (06/11)")',
      pg_temp.avisos(c_nel) -> 0 ->> 'texto' = 'Nelson, quero te avisar com antecedência: a peça do serviço no seu veleiro ainda não chegou e agora está prevista para quarta (11/11). Por isso, o serviço no seu veleiro, que estava para quinta (05/11), deve ficar entre quinta (12/11) e terça (17/11). Te confirmo a data assim que a peça chegar. Se isso atrapalhar algum plano seu, me diga.'
      and pg_temp.avisos(c_nel) -> 0 ->> 'faixa_ate' = '2026-11-17'
      and pg_temp.avisos(pg_temp.os('100')) -> 0 ->> 'texto' = 'Olá, Giancarlo! Aqui é o Gustavo, da HBR Marine Solutions. O serviço no seu motorhome está levando mais tempo do que eu estimei. A nova previsão para terminar é entre terça (03/11) e sexta (06/11). Qualquer dúvida, me chama.'
      and pg_temp.avisos(c_nel) -> 0 ->> 'chave' = 'agenda-cliente:pode_atrasar:' || c_nel || ':2026-11-12',
      pg_temp.avisos(c_nel)::text || ' ' || pg_temp.avisos(pg_temp.os('100'))::text);
    -- o modo em teste volta a faixa na hora (o leitor confere o modo)
    update public.agenda_config set modo_aprendizado = 'sombra' where id;
    v_res := pg_temp.ok(v_res, 'C3h o modo de aprendizado em teste devolve a faixa de sempre na hora (sem rodar nada)',
      public._agenda_cliente_risco(c_nel, c_hoje) ->> 'faixa_ate' = '2026-11-13' and public._agenda_aprendido('aviso_folga', 'todas') is null,
      public._agenda_cliente_risco(c_nel, c_hoje)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- o teto, a troca grande e o abaixo do mínimo
  begin
    execute current_setting('agenda_teste.fase6');
    perform pg_temp.nelson_com_data();
    update public.agenda_config set aviso_folga_max_du = 1 where id;
    j := pg_temp.aprender('ligado', '{aviso_cliente}');
    v_res := pg_temp.ok(v_res, 'C3i o teto (aviso_folga_max_du 1): a folga fica em 1 dia útil; a faixa do Nelson qui 12 a seg 16/11',
      (j #>> '{aviso_folga,calculado}')::numeric = 1 and j #>> '{aviso_folga,estado}' = 'em_uso'
      and public._agenda_cliente_risco(c_nel, c_hoje) ->> 'faixa_ate' = '2026-11-16', j::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    execute current_setting('agenda_teste.fase6');
    perform pg_temp.nelson_com_data();
    update public.agenda_config set aviso_troca_max_du = 1 where id;
    j := pg_temp.aprender('ligado', '{aviso_cliente}');
    select * into a from public.agenda_aprendizado where item = 'aviso_folga' and chave = 'todas';
    v_res := pg_temp.ok(v_res, 'C3j a troca grande (0 → 2 com o limite em 1): pergunta crítica, com o texto (sem a opção 3: o que vale é o padrão); enquanto espera, sem folga',
      a.estado = 'pergunta' and a.em_uso is null and public._agenda_aprendido('aviso_folga', 'todas') is null
      and (select q.tipo = 'aprendizado' and q.estado = 'aberta' and q.chave = 'aprendizado:aviso_folga:todas'
                  and q.texto = 'Medi os avisos de atraso: em 5, o serviço terminou até 2 dias úteis depois do fim que eu disse, e hoje eu dou a faixa do plano. É uma troca grande. 1) Passo a dar a faixa com 2 dias úteis a mais (recomendo); 2) Fico com a faixa do plano.'
                  and jsonb_array_length(q.opcoes) = 2
             from public.agenda_perguntas q where q.id = a.pergunta_id)
      and a.texto = 'Avisos de atraso: em 5, o serviço terminou até 2 dias úteis depois do fim que eu disse, e hoje dou a faixa do plano: a troca espera a sua resposta.'
      and public._agenda_cliente_risco(c_nel, c_hoje) ->> 'faixa_ate' = '2026-11-13',
      to_jsonb(a)::text || ' ' || coalesce((select q.texto from public.agenda_perguntas q where q.id = a.pergunta_id), '-'));
    update public.agenda_config set aviso_troca_max_du = 2, aviso_n_min = 6 where id;
    j := pg_temp.aprender('ligado', '{aviso_cliente}');
    select * into a from public.agenda_aprendizado where item = 'aviso_folga' and chave = 'todas';
    v_res := pg_temp.ok(v_res, 'C3k com o mínimo em 6: medindo (a pergunta aberta se resolve), sem folga, e o texto diz quantos faltam',
      a.estado = 'medindo' and a.em_uso is null
      and a.texto = 'Avisos de atraso: 5 de 6 avisos medidos; dou a faixa do plano (padrão).'
      and not exists (select 1 from public.agenda_perguntas q where q.chave = 'aprendizado:aviso_folga:todas' and q.estado = 'aberta'),
      to_jsonb(a)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$c3$;

-- ── C4. O estouro do risco pelo fator de campo ──────────────────────────────────────────────────────────
do $c4$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje constant date := date '2026-10-30';
  c_tec  constant uuid := 'aa000000-0000-4000-8000-0000000000ff';
  x0 jsonb;
  x1 jsonb;
  v  text;
  j  jsonb;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('C4 o estouro pelo fator (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase6');
    perform pg_temp.giancarlo_em_andamento();
    j := pg_temp.aprender('sombra', '{}');
    x0 := public._agenda_cliente_risco(pg_temp.os('100'), c_hoje);
    v_res := pg_temp.ok(v_res, 'C4a em teste (1,5×): 6,5 meios-dias feitos de 4 estoura — o risco (o cliente ouviu sex 30/10; o fim novo ter 03/11)',
      (x0 ->> 'estouro')::boolean and (x0 ->> 'risco')::boolean and x0 ->> 'fim_novo' = '2026-11-03', x0::text);
    j := pg_temp.aprender('ligado', '{mo,aviso_cliente}');
    v_res := pg_temp.ok(v_res, 'C4b ligado sem "fator" na lista: o estouro de sempre',
      public._agenda_cliente_risco(pg_temp.os('100'), c_hoje) - 'faixa_ate' = x0 - 'faixa_ate', null);
    j := pg_temp.aprender('ligado', '{fator}');
    x1 := public._agenda_cliente_risco(pg_temp.os('100'), c_hoje);
    v_res := pg_temp.ok(v_res, 'C4c ligado com o fator em uso (1,7× nas OS de energia em motorhome): os mesmos 6,5 de 4 não estouram — sem risco (o fim do plano, sex 16/10)',
      (public.agenda_fator_de_campo(pg_temp.os('100'), c_hoje) ->> 'fator')::numeric = 1.7
      and not (x1 ->> 'estouro')::boolean and not (x1 ->> 'risco')::boolean and x1 ->> 'fim_novo' = '2026-10-16', x1::text);
    v := pg_temp.como(c_tec, 'authenticated', format($q$select pg_temp.risco_por_definer(%L, date '2026-10-30')::text$q$, pg_temp.os('100')));
    v_res := pg_temp.ok(v_res, 'C4d o técnico numa cadeia definer: o fator de campo seria 42501 para ele; o risco fica com o padrão (estoura), sem erro',
      pg_temp.como(c_tec, 'authenticated', format($q$select public.agenda_fator_de_campo(%L, date '2026-10-30')::text$q$, pg_temp.os('100'))) like 'erro 42501%'
      and v not like 'erro%' and (v::jsonb ->> 'estouro')::boolean, v);
    v_res := pg_temp.ok(v_res, 'C4e o técnico direto continua sem alcançar a agenda (P0002 no _agenda_cfg, como antes da Fase 6); o service_role e o administrador usam o aprendido',
      pg_temp.como(c_tec, 'authenticated', format($q$select public._agenda_cliente_risco(%L, date '2026-10-30')::text$q$, pg_temp.os('100'))) like 'erro P0002%'
      and pg_temp.como(null, 'service_role', format($q$select public._agenda_cliente_risco(%L, date '2026-10-30') ->> 'estouro'$q$, pg_temp.os('100'))) = 'false'
      and pg_temp.como('aa000000-0000-4000-8000-000000000001', 'authenticated',
            format($q$select public._agenda_cliente_risco(%L, date '2026-10-30') ->> 'estouro'$q$, pg_temp.os('100'))) = 'false',
      pg_temp.como(c_tec, 'authenticated', format($q$select public._agenda_cliente_risco(%L, date '2026-10-30')::text$q$, pg_temp.os('100'))));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$c4$;

-- ── C5. As cópias, as portas e nenhuma mensagem nova ────────────────────────────────────────────────────
do $c5$
declare
  v_tex5 text := coalesce(current_setting('agenda_teste.mig_textos_fase5', true), '');
  v_c2   text := coalesce(current_setting('agenda_teste.mig_correcao_rodada_fase5', true), '');
  v_rod5 text := coalesce(current_setting('agenda_teste.mig_rodada_fase5', true), '');
  v_dono text := coalesce(current_setting('agenda_teste.mig_dono_fase6', true), '');
  v_esta text := coalesce(current_setting('agenda_teste.mig_cliente_fase6', true), '');
  rc record;
begin
  insert into _resultado
  select 'C5a o passo novo: sem grant a ninguém (nem service_role), invoker, search_path fixo, volátil',
         not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
         and not has_function_privilege('service_role', p.oid, 'execute') and not p.prosecdef and p.provolatile = 'v'
         and array_to_string(p.proconfig, ',') like '%search_path=%', null
    from pg_proc p where p.oid = to_regprocedure('public._agenda_aprender_cliente(date, timestamptz)');
  insert into _resultado
  select 'C5b as recriadas com as portas de antes: o gravador do prometido sem grant (definer); o risco e os textos para authenticated e service_role, nunca anon',
         not has_function_privilege('anon', 'public._agenda_cliente_gravar_prometido(uuid, text, date, date, text, uuid, timestamptz, text)', 'execute')
         and not has_function_privilege('authenticated', 'public._agenda_cliente_gravar_prometido(uuid, text, date, date, text, uuid, timestamptz, text)', 'execute')
         and not has_function_privilege('service_role', 'public._agenda_cliente_gravar_prometido(uuid, text, date, date, text, uuid, timestamptz, text)', 'execute')
         and (select prosecdef from pg_proc where oid = 'public._agenda_cliente_gravar_prometido(uuid, text, date, date, text, uuid, timestamptz, text)'::regprocedure)
         and has_function_privilege('authenticated', 'public._agenda_cliente_risco(uuid, date)', 'execute')
         and has_function_privilege('service_role', 'public._agenda_cliente_risco(uuid, date)', 'execute')
         and not has_function_privilege('anon', 'public._agenda_cliente_risco(uuid, date)', 'execute')
         and has_function_privilege('authenticated', 'public._agenda_aprendizado_texto(text, text, jsonb)', 'execute')
         and not has_function_privilege('anon', 'public._agenda_aprendizado_texto(text, text, jsonb)', 'execute')
         and (select not prosecdef and provolatile = 's' from pg_proc where oid = 'public._agenda_cliente_risco(uuid, date)'::regprocedure)
         and (select provolatile = 'i' from pg_proc where oid = 'public._agenda_aprendizado_texto(text, text, jsonb)'::regprocedure),
         null;

  if v_tex5 = '' or v_c2 = '' or v_rod5 = '' or v_dono = '' or v_esta = '' then
    insert into _resultado values ('C5 as cópias', true, 'PULADO: sem agenda_teste.mig_* (rode pela bancada)');
    return;
  end if;
  for rc in
    select * from (values
      ('_agenda_cliente_gravar_prometido', 'public._agenda_cliente_gravar_prometido(uuid, text, date, date, text, uuid, timestamptz, text)', v_tex5, '20261028100100', 1),
      ('_agenda_cliente_risco', 'public._agenda_cliente_risco(uuid, date)', v_c2, '20261028100800', 3),
      ('_agenda_aprendizado_texto', 'public._agenda_aprendizado_texto(text, text, jsonb)', v_dono, '20261029100400', 1)
    ) t(nome, sig, fonte, de, novos)
  loop
    -- FASE 6 (P6): _agenda_aprendizado_texto foi recriada de novo em 20261029100600 (a carga e o planejador): a cópia do P5 é
    -- conferida no texto da 20261029100500 (o R8 de agenda_fase6_rodada.sql confere a do P6 contra ela); as outras duas, no
    -- banco, como antes
    insert into _resultado
    select format('C5c a cópia de %s (de %s) só acrescenta %s bloco(s) "-- FASE 6:"; fora deles, a fonte linha a linha', rc.nome, rc.de, rc.novos),
           pg_temp.sem_blocos(x.src) = pg_temp.sem_blocos(pg_temp.corpo(rc.fonte, rc.nome))
           and cardinality(pg_temp.sem_blocos(x.src)) > 5
           and (select count(*) from regexp_matches(x.src, '-- FASE 6: fim', 'g'))
               = (select count(*) from regexp_matches(pg_temp.corpo(rc.fonte, rc.nome), '-- FASE 6: fim', 'g')) + rc.novos
           and x.src ~ '-- FASE 6: \(P5\)',
           format('%s linhas fora dos blocos; %s blocos', cardinality(pg_temp.sem_blocos(x.src)),
                  (select count(*) from regexp_matches(x.src, '-- FASE 6: fim', 'g')))
      from pg_proc p
      cross join lateral (select case when rc.nome = '_agenda_aprendizado_texto' then pg_temp.corpo(v_esta, rc.nome)
                                      else p.prosrc end as src) x
     where p.oid = rc.sig::regprocedure;
  end loop;
  insert into _resultado
  select 'C5d o risco sem os blocos da correção C2 e da Fase 6 é o de 20261028100300 (o que o C2z confere); a folga mora dentro do bloco da correção do retorno',
         pg_temp.sem_blocos(p.prosrc, true) = pg_temp.sem_blocos(pg_temp.corpo(v_rod5, '_agenda_cliente_risco'), true)
         and position('-- FASE 6: (P5) a folga do aviso' in p.prosrc) > position('-- CORREÇÃO FASE 5: (item 8)' in p.prosrc)
         and position('-- FASE 6: (P5) a folga do aviso' in p.prosrc)
             < position('-- CORREÇÃO FASE 5: fim' in substr(p.prosrc, position('-- CORREÇÃO FASE 5: (item 8)' in p.prosrc)))
               + position('-- CORREÇÃO FASE 5: (item 8)' in p.prosrc),
         null
    from pg_proc p where p.oid = 'public._agenda_cliente_risco(uuid, date)'::regprocedure;
  insert into _resultado
  select 'C5e nada na migration escreve mensagem a terceiros (fila do WhatsApp, mensagens ao cliente, à equipe ou ao fornecedor) nem em agenda_config',
         v_esta !~* 'insert\s+into\s+public\.(whatsapp_\w+|agenda_cliente_mensagens|agenda_equipe_mensagens|agenda_fornecedor_mensagens)'
         and v_esta !~* 'update\s+public\.(whatsapp_\w+|agenda_cliente_mensagens|agenda_config)\M'
         and v_esta !~* '_agenda_cliente_(registrar|enfileirar)\(',
         null;
end
$c5$;

-- ── C6. O risco da spec: o M6 registrado e ainda não enviado quando a folga liga ────────────────────────
do $c6$
declare
  v_res jsonb := '[]'::jsonb;
  c_nel constant uuid := '05000000-0000-4000-8000-000000000112';
  x0 jsonb;
  x1 jsonb;
  r  jsonb;
  j  jsonb;
  v_id uuid;
  v_t text;
  p  public.os_planejamento;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('C6 o M6 registrado quando a folga liga (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase6');
    perform pg_temp.nelson_com_data();
    perform pg_temp.ligar_cliente();
    j := pg_temp.aprender('sombra', '{}');
    -- sex 30/10 17:00: o M6 da peça (12 a 13/11) é registrado para sáb 31/10 09:01, sem a folga (em teste)
    perform pg_temp.vig('2026-10-30 17:00');
    x0 := pg_temp.avisos(c_nel);
    v_id := (x0 -> 0 ->> 'id')::uuid;
    v_t := x0 -> 0 ->> 'texto';
    -- a folga liga às 17:05 (o dono deu o OK) — o risco passa a dizer até ter 17/11
    j := pg_temp.aprender('ligado', '{aviso_cliente}');
    r := pg_temp.vig('2026-10-30 17:15');
    x1 := pg_temp.avisos(c_nel);
    v_res := pg_temp.ok(v_res, 'C6a com a folga em uso, o aviso registrado antes NÃO é recusado nem trocado: o mesmo (12 a 13/11), registrado; a rodada não registra outro (a chave pelo início da faixa, que não muda)',
      jsonb_array_length(x0) = 1 and x0 -> 0 ->> 'estado' = 'registrada' and x0 -> 0 ->> 'faixa_ate' = '2026-11-13'
      and public._agenda_cliente_risco(c_nel, date '2026-10-30') ->> 'faixa_ate' = '2026-11-17'
      and jsonb_array_length(x1) = 1 and x1 -> 0 ->> 'estado' = 'registrada' and x1 -> 0 ->> 'faixa_ate' = '2026-11-13'
      and (r #>> '{contagens,atraso,registradas}')::int = 0 and (r #>> '{contagens,atraso,desatualizadas}')::int = 0,
      x1::text || ' ' || (r #>> '{contagens,atraso}'));
    v_res := pg_temp.ok(v_res, 'C6b a revalidação deixa sair (refaz o texto com os dados do registro: o mesmo), ao contrário do que a spec previa ("desatualizada")',
      public._agenda_cliente_revalidar(v_id, pg_temp.em('2026-10-31 09:15')) is null,
      coalesce(public._agenda_cliente_revalidar(v_id, pg_temp.em('2026-10-31 09:15')), 'sai'));
    -- sáb 31/10 09:15: vai à fila e sai, com a faixa SEM a folga
    perform pg_temp.vig('2026-10-31 09:15');
    perform pg_temp.saiu(v_id, '2026-10-31 09:15:20');
    select * into p from public.os_planejamento where service_order_id = c_nel;
    v_res := pg_temp.ok(v_res, 'C6c o que sai é o texto registrado (a faixa de antes, 12 a 13/11), e ela vira o prometido; a 1ª promessa fica qui 05/11',
      (select m.estado = 'enviada' and m.texto = v_t from public.agenda_cliente_mensagens m where m.id = v_id)
      and v_t like '%deve ficar entre quinta (12/11) e sexta (13/11).%'
      and p.prometido_de = date '2026-11-12' and p.prometido_ate = date '2026-11-13' and p.prometido_primeiro_ate = date '2026-11-05',
      to_jsonb(p)::text);
    -- ter 03/11: o plano cabe no que o cliente ouviu → nenhum aviso a mais (nem a pergunta)
    perform pg_temp.vig('2026-11-03 17:00');
    v_res := pg_temp.ok(v_res, 'C6d depois de sair, o plano (fim sex 13/11) cabe na faixa que o cliente ouviu: sem risco e nenhum aviso a mais (a folga vale do próximo aviso em diante)',
      not (public._agenda_cliente_risco(c_nel, date '2026-11-03') ->> 'risco')::boolean
      and jsonb_array_length(pg_temp.avisos(c_nel)) = 1
      and not exists (select 1 from public.agenda_perguntas q where q.chave like 'cliente_aviso:' || c_nel || ':%'),
      pg_temp.avisos(c_nel)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$c6$;

-- ── C7. Byte a byte com as definições de antes ──────────────────────────────────────────────────────────
do $c7$
declare
  v_res jsonb := '[]'::jsonb;
  v_c2   text := coalesce(current_setting('agenda_teste.mig_correcao_rodada_fase5', true), '');
  v_tex5 text := coalesce(current_setting('agenda_teste.mig_textos_fase5', true), '');
  v_modo record;
  v_dia  date;
  v_os   uuid;
  v_n    int;
  v_dif  text;
  v_novo text;
  v_antes text;
  v_trocou boolean;
  j jsonb;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' or v_c2 = '' or v_tex5 = '' then
    insert into _resultado values ('C7 byte a byte (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  for v_modo in
    select * from (values (1, 'em teste', 'sombra', '{}'::text[], false),
                          (2, 'ligado sem a lista', 'ligado', '{mo,presenca}'::text[], false),
                          (3, 'ligado com as perguntas abertas (nada em uso)', 'ligado', '{fator,aviso_cliente}'::text[], true),
                          (4, 'o controle: a folga e o fator em uso', 'ligado', '{fator,aviso_cliente}'::text[], false)) m(k, nome, modo, lista, perguntas)
     order by k
  loop
    begin
      execute current_setting('agenda_teste.fase6');
      execute replace(pg_temp.inteira(v_c2, '_agenda_cliente_risco'), 'create or replace function public._agenda_cliente_risco(',
                      'create function pg_temp.risco_de_antes(');
      perform pg_temp.nelson_com_data();
      perform pg_temp.giancarlo_em_andamento();
      perform pg_temp.ligar_cliente();
      if v_modo.perguntas then
        update public.agenda_config set fator_troca_max = 0.10, aviso_troca_max_du = 1 where id;
      end if;
      j := pg_temp.aprender(v_modo.modo, v_modo.lista);

      -- o risco de cada OS ativa (e das que têm prometido) em 4 dias
      v_n := 0;
      v_dif := null;
      for v_dia in select unnest(array[date '2026-10-30', date '2026-11-02', date '2026-11-03', date '2026-11-06']) loop
        for v_os in select k.service_order_id from public.os_carteira(v_dia) k
                    union select p.service_order_id from public.os_planejamento p where p.prometido_ate is not null loop
          v_n := v_n + 1;
          if public._agenda_cliente_risco(v_os, v_dia)::text is distinct from pg_temp.risco_de_antes(v_os, v_dia)::text then
            v_dif := concat_ws(', ', v_dif, format('%s em %s', right(v_os::text, 3), to_char(v_dia, 'DD/MM')));
          end if;
        end loop;
      end loop;
      if v_modo.k < 4 then
        v_res := pg_temp.ok(v_res, format('C7a%s %s: o risco de %s pares (OS, dia) é o da 20261028100800, byte a byte', v_modo.k, v_modo.nome, v_n),
          v_dif is null and v_n > 20, coalesce(v_dif, '—'));
      else
        v_res := pg_temp.ok(v_res, 'C7a4 o controle (a folga e o fator em uso): a mesma comparação acusa o Nelson (a folga) e o Giancarlo (o fator)',
          v_dif like '%112 em 30/10%' and v_dif like '%100 em 30/10%', v_dif);
      end if;

      -- a rodada do cliente inteira: com as definições novas e, por um instante (desfeito na hora), com as de antes
      begin
        v_novo := pg_temp.rodada();
        raise exception 'desfaz' using errcode = 'P0098';
      exception when sqlstate 'P0098' then null;
      end;
      v_trocou := false;
      begin
        execute pg_temp.inteira(v_c2, '_agenda_cliente_risco');
        execute pg_temp.inteira(v_tex5, '_agenda_cliente_gravar_prometido');
        v_trocou := (select bool_and(prosrc !~ '-- FASE 6:') from pg_proc
                      where oid in ('public._agenda_cliente_risco(uuid, date)'::regprocedure,
                                    'public._agenda_cliente_gravar_prometido(uuid, text, date, date, text, uuid, timestamptz, text)'::regprocedure));
        v_antes := pg_temp.rodada();
        raise exception 'desfaz' using errcode = 'P0098';
      exception when sqlstate 'P0098' then null;
      end;
      if v_modo.k < 4 then
        v_res := pg_temp.ok(v_res, format('C7b%s %s: a rodada do cliente (4 tiques e o envio do aviso do Nelson: as contagens, as mensagens, as perguntas e as ações) sai igual à de antes, byte a byte', v_modo.k, v_modo.nome),
          v_trocou and v_novo = v_antes
          and (select prosrc from pg_proc where oid = 'public._agenda_cliente_risco(uuid, date)'::regprocedure) ~ '-- FASE 6: \(P5\)',
          v_novo || ' / ' || coalesce(v_antes, '-'));
      else
        v_res := pg_temp.ok(v_res, 'C7b4 o controle: com a folga e o fator em uso, a rodada sai diferente (a conferência enxerga a mudança)',
          v_trocou and v_novo <> v_antes, v_novo || ' / ' || coalesce(v_antes, '-'));
      end if;
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  perform pg_temp.gravar(v_res);
end
$c7$;

-- ── C8. A correção C1 (20261029100900): itens 4 e 11 ─────────────────────────────────────────────────────
-- (item 11) um arredondamento só: o P80 da folga sobe para o teto, como o atraso do fornecedor (2,2 → 3). (item 4) a folga
-- mede o erro do PLANO: o aviso que sai com a folga em uso guarda o fim da faixa sem ela (base.dados.faixa_ate_plano), e a
-- rodada seguinte, com os avisos que já saíram com a folga, continua com ela — sem o vaivém de 2 para 0 (o rev-f6 c5).
do $c8$
declare
  v_res jsonb := '[]'::jsonb;
  c_nel constant uuid := '05000000-0000-4000-8000-000000000112';
  j  jsonb;
  a  public.agenda_aprendizado;
  n0 int;
  v_m jsonb;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('C8 a correção C1 do cliente (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;

  -- (item 11) com a faixa da 136 até 26/10 (estouro 3): os estouros 2, 0, 2, 3 e 1 → P80 2,2 → 3 dias úteis (o teto)
  begin
    execute current_setting('agenda_teste.fase6');
    alter table public.agenda_cliente_mensagens disable trigger user;  -- (só a simulação: a mensagem que saiu não se reescreve)
    update public.agenda_cliente_mensagens set faixa_ate = date '2026-10-26' where id = 'd6000000-0000-4000-8000-000000000636';
    alter table public.agenda_cliente_mensagens enable trigger user;
    j := pg_temp.aprender('sombra', '{}');
    select * into a from public.agenda_aprendizado where item = 'aviso_folga' and chave = 'todas';
    v_res := pg_temp.ok(v_res, 'C8a (C1, item 11) os estouros 2, 0, 2, 3 e 1 (P80 2,2) dão 3 dias úteis de folga: o teto, como o atraso do fornecedor (não o mais próximo)',
      a.calculado = 3 and a.n = 5 and (a.detalhe ->> 'maior')::numeric = 3, to_jsonb(a)::text);
    v_res := pg_temp.ok(v_res, 'C8b (C1, item 11) a pontualidade usa a mesma conta (o P80 1,6 do atraso com o cliente → 2 dias úteis)',
      (select (x.detalhe ->> 'p80_atraso_du')::int from public.agenda_aprendizado x where x.item = 'cliente_pontualidade') = 2, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- (item 4) a folga em uso (2) e os avisos que saíram com ela: a rodada seguinte continua em 2, sem ação nova
  begin
    execute current_setting('agenda_teste.fase6');
    j := pg_temp.aprender('ligado', '{aviso_cliente}');
    select count(*) into n0 from public.agenda_acoes x where x.tipo = 'aprendizado' and x.antes ->> 'item' = 'aviso_folga';
    -- os mesmos 5 serviços, com o aviso que teria saído com a folga em uso: o fim da faixa 2 dias úteis depois e, guardado, o fim
    -- do plano (o que _agenda_cliente_registrar grava em base.dados.faixa_ate_plano)
    alter table public.agenda_cliente_mensagens disable trigger user;  -- (só a simulação)
    update public.agenda_cliente_mensagens
       set base = jsonb_set(coalesce(base, '{}'::jsonb), '{dados}',
                            coalesce(base -> 'dados', '{}'::jsonb) || jsonb_build_object('faixa_ate_plano', faixa_ate)),
           faixa_ate = public.agenda_somar_du(faixa_ate, 2)
     where tipo = 'pode_atrasar' and modo = 'ligado' and enviada_em is not null and faixa_ate is not null;
    alter table public.agenda_cliente_mensagens enable trigger user;
    perform public._agenda_aprender_medir(date '2026-11-03');
    j := public._agenda_aprender_cliente(date '2026-11-03', pg_temp.em('2026-11-03 16:05'));
    select * into a from public.agenda_aprendizado where item = 'aviso_folga' and chave = 'todas';
    v_res := pg_temp.ok(v_res, 'C8c (C1, item 4) os avisos que saíram com a folga medem contra o fim do PLANO: na rodada seguinte a folga continua 2, em uso, sem ação nova (sem o vaivém de 2 para 0)',
      a.estado = 'em_uso' and a.em_uso = 2 and a.calculado = 2
      and (select count(*) from public.agenda_acoes x where x.tipo = 'aprendizado' and x.antes ->> 'item' = 'aviso_folga') = n0,
      to_jsonb(a)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- (item 4) o M6 novo com a folga em uso guarda o fim do plano
  begin
    execute current_setting('agenda_teste.fase6');
    perform pg_temp.nelson_com_data();
    perform pg_temp.ligar_cliente();
    j := pg_temp.aprender('ligado', '{aviso_cliente}');
    perform pg_temp.vig('2026-10-30 17:00');
    select m.base -> 'dados' into v_m from public.agenda_cliente_mensagens m
     where m.service_order_id = c_nel and m.tipo = 'pode_atrasar' and m.id <> 'd5000000-0000-4000-8000-0000000000a1'
     order by m.criada_em desc limit 1;
    v_res := pg_temp.ok(v_res, 'C8d (C1, item 4) o aviso registrado com a folga em uso diz a faixa com ela (até ter 17/11) e guarda o fim do plano (faixa_ate_plano sex 13/11)',
      v_m ->> 'faixa_ate' = '2026-11-17' and v_m ->> 'faixa_ate_plano' = '2026-11-13', coalesce(v_m::text, '—'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$c8$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
