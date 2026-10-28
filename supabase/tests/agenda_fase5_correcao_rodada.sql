-- Prova da correção C2 da Fase 5 da Agenda de Produção (migration 20261028100800): a rodada, os textos e o miúdo. Cada caso
-- é o cenário do revisor (revisao-fase5-correcao.md, itens 1, 3, 4, 6, 7, 8, 12, 15, 22, 23 e 24; revisao-fase5-regressao.md,
-- B3) e falha no código de antes da correção.
-- bancada: depende de 20261028100800
--
--   C2a (item 1; x3, x3b) a mensagem que só existiu em teste não conta como "o cliente ouviu" com a mensagem ao cliente
--       ligada: duas semanas em sombra, a onda 2 ligada e o *choveu* não mandam o M10 a quem nunca recebeu o dia; nem com o
--       tipo do acesso fora das ondas; com o acesso de fato enviado, o M10 sai (e à tarde diz "Boa tarde", item 12)
--   C2b (item 3; x1) o aviso de atraso aprovado depois do dia marcado sai na hora (não morre por "janela"); o aviso que não
--       sai pelo canal (sem conversa) abre UMA vez a pergunta "não saiu" ao dono antes da data; a linha que o provedor não
--       entregou deixa a mensagem recusada com o motivo "entrega"
--   C2c (item 4; x7b) um cliente cujo texto não fecha (o barco "Bravo 20155") não derruba o passo: o outro é registrado, o
--       erro fica em app_error_logs (cliente:confirmar:os) e a rodada não falha
--   C2d (item 6; x6) o aviso remarcado em que só o fim mudou: a forma fim (o texto byte a byte), o fim no base, e a
--       revalidação que recusa quando o último dia muda
--   C2e (item 7; x6) a data firme que o dono pediu (cliente_avisar firme) vai à fila mesmo sem o material todo; a da rodada
--       com o material fora de A continua recusada
--   C2f (item 8) a peça crítica sem previsão: o aviso sem data, sem prometido; ao sair, o prometido da OS fica nulo e não
--       volta o "passou sem aviso"; com todos os críticos com data, continua a faixa (variante peca)
--   C2g (item 12) a saudação pela hora do envio: a véspera das 14:00 diz "Boa tarde" e não fica desatualizada quando a hora
--       muda depois
--   C2h (item 15) sem artigo antes do nome: a regra (_agenda_cliente_sem_artigo) e o texto do aviso crítico com o serviço
--       sem o possessivo do cliente
--   C2i (item 22) sem entrega registrada e com o "ficou pronto" enviado sem resposta, o pós-serviço não sai; respondido, sai
--   C2j (item 23) o "2º atraso" não conta o prometido que mudou a pedido do cliente (só aviso de atraso ou nova data
--       enviados)
--   C2k (item 24) a OS faturada (invoiced) logo depois de concluída recebe o "ficou pronto"
--   C2l (B3) o cartão conta o que espera o dono igual ao foco, sem chamá-lo; o índice da conversa existe e serve ao d10
--   C2z as cópias recriadas só mudam nos blocos "-- CORREÇÃO FASE 5:" (os da C1 incluídos); as portas e o security
--       definer das novas. Os blocos "-- FASE 6:" saem também (a Fase 6, P5, recria _agenda_cliente_risco)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase5_correcao_rodada.sql
--   C2z roda em qualquer lugar (as cópias só com as migrations como texto); o resto só na bancada (a fixture-fase5; fora
--   dela, PULADO). Termina em ROLLBACK: nada fica gravado e nenhuma mensagem sai.
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
create function pg_temp.hora(p_t timestamptz) returns text language sql immutable as $f$
  select to_char(p_t at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI')
$f$;

-- Liga a mensagem ao cliente (todos os tipos, ou os dados) e a aprovação dos primeiros dias (0 = sem aprovação).
create function pg_temp.ligar(p_tipos text[] default null, p_aprov int default 0) returns void language sql as $f$
  update public.agenda_config
     set modo_cliente = 'ligado', cliente_aprovacao_dias = p_aprov,
         cliente_tipos_ligados = coalesce(p_tipos, array['confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento',
                                                          'pode_atrasar', 'nova_data', 'pronto', 'pronto_lembrete',
                                                          'pos_servico', 'mudanca_no_dia'])
   where id
$f$;

-- Um tique da rodada, com o "hoje" de quem lê o relógio (_hoje_brt) acompanhando.
create function pg_temp.vig(p_quando text) returns jsonb language plpgsql as $f$
begin
  perform set_config('agenda_teste.hoje', left(p_quando, 10), true);
  return public.agenda_cliente_vigiar(left(p_quando, 10)::date, pg_temp.em(p_quando));
end $f$;

-- As mensagens de uma OS (sem a do Nelson de 22/10, da fixture), na ordem em que nasceram.
create function pg_temp.msgs(p_os uuid, p_tipo text default null) returns jsonb language sql stable as $f$
  select coalesce(jsonb_agg(jsonb_build_object('tipo', m.tipo, 'variante', m.variante, 'modo', m.modo, 'estado', m.estado,
                                               'motivo', m.recusa_motivo, 'aprovacao', m.aprovacao,
                                               'enviar', pg_temp.hora(m.enviar_em), 'texto', m.texto, 'id', m.id,
                                               'dia_alvo', m.dia_alvo, 'prometido_tipo', m.prometido_tipo, 'base', m.base)
                            order by m.criada_em, m.id), '[]'::jsonb)
    from public.agenda_cliente_mensagens m
   where m.service_order_id = p_os and (p_tipo is null or m.tipo = p_tipo)
     and m.id <> 'd5000000-0000-4000-8000-0000000000a1'
$f$;

-- A linha da fila de uma mensagem sai (o worker): o gatilho do envio faz o resto.
create function pg_temp.saiu(p_msg uuid, p_quando text) returns void language sql as $f$
  update public.whatsapp_send_queue set status = 'sent', sent_at = pg_temp.em(p_quando), attempts = 1
   where source = 'agenda-cliente' and source_ref_id = p_msg
$f$;

-- O corpo de uma função numa migration (entre o "as $function$"/"as $$" que abre e o fecho), e as linhas sem os blocos
-- "-- CORREÇÃO FASE 5: … -- CORREÇÃO FASE 5: fim" (os da C1 e os da C2).
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
create function pg_temp.sem_correcao(p_corpo text) returns text[] language plpgsql as $f$
declare
  v_b text[] := '{}'; v_bloco boolean := false; l text;
  -- FASE 6: os blocos "-- FASE 6: … -- FASE 6: fim" também saem (a Fase 6 recria _agenda_cliente_risco: spec-fase6 §3.1,
  -- item 11); um bloco da Fase 6 dentro de um da correção sai junto com ele
  v_f6 boolean := false;
  -- FASE 6: fim
begin
  foreach l in array string_to_array(replace(p_corpo, E'\r\n', E'\n'), E'\n') loop
    -- FASE 6: (P5) fora de um bloco da correção, o bloco da Fase 6 sai inteiro (o fim é lido pelo prefixo)
    if not v_bloco and not v_f6 and l ~ '^\s*-- FASE 6:' and l !~ '^\s*-- FASE 6: fim' then v_f6 := true; continue; end if;
    if v_f6 then
      if l ~ '^\s*-- FASE 6: fim' then v_f6 := false; end if;
      continue;
    end if;
    -- FASE 6: fim
    if not v_bloco and l ~ '^\s*-- CORREÇÃO FASE 5:' and l !~ '^\s*-- CORREÇÃO FASE 5: fim' then v_bloco := true; continue; end if;
    if v_bloco then
      if l ~ '^\s*-- CORREÇÃO FASE 5: fim' then v_bloco := false; end if;
      continue;
    end if;
    v_b := v_b || l;
  end loop;
  return v_b;
end $f$;

-- ── C2a–C2l (a fixture-fase5; sex 30/10/2026) ────────────────────────────────────────────────────────────
do $c2$
declare
  v_res jsonb := '[]'::jsonb;
  c_flav     constant uuid := '05000000-0000-4000-8000-000000000104';
  c_rod      constant uuid := '05000000-0000-4000-8000-000000000096';
  c_nel      constant uuid := '05000000-0000-4000-8000-000000000112';
  c_ven      constant uuid := '05000000-0000-4000-8000-000000000069';
  c_luc      constant uuid := '05000000-0000-4000-8000-000000000122';
  c_cli_flav constant uuid := 'c1000000-0000-4000-8000-000000000004';
  c_cli_nel  constant uuid := 'c1000000-0000-4000-8000-000000000005';
  c_dono     constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_ondas2   constant text[] := array['material_chegou', 'nova_data', 'pode_atrasar', 'confirmar', 'vespera', 'acesso', 'mudanca_no_dia'];
  r     jsonb;
  r2    jsonb;
  x     jsonb;
  v_id  uuid;
  v_t   text;
  v_n   int;
begin
  if coalesce(current_setting('agenda_teste.fase5', true), '') = '' then
    insert into _resultado values ('C2a–C2l (fixture-fase5)', true, 'PULADO: sem agenda_teste.fase5 (rode pela bancada)');
    return;
  end if;
  begin
  execute current_setting('agenda_teste.fase5');

  -- ── C2a. O "ouviu" em ligado é só o que saiu (item 1) ──
  begin
    -- x3b: o caminho do roteiro (§10) — duas semanas em sombra, a onda 2 ligada, o *choveu*
    update public.agenda_config set modo_cliente = 'sombra' where id;
    perform pg_temp.vig('2026-10-30 17:00');
    perform pg_temp.ligar(c_ondas2);
    perform pg_temp.vig('2026-11-02 17:00');
    perform set_config('agenda_teste.hoje', '2026-11-03', true);
    perform public.agenda_choveu(c_dono, null, 'whatsapp', date '2026-11-03', pg_temp.em('2026-11-03 14:00'));
    r := pg_temp.vig('2026-11-03 14:15');
    v_res := pg_temp.ok(v_res, 'C2a1 (x3b) sombra, depois a onda 2 e o *choveu*: o Flávio, que nunca recebeu ter 03/11 de verdade, não recebe o M10 (nada da mudança no dia)',
      not public._agenda_cliente_ouviu(c_flav, date '2026-11-03', pg_temp.em('2026-11-03 14:15'))
      and jsonb_array_length(pg_temp.msgs(c_flav, 'mudanca_no_dia')) = 0
      and not exists (select 1 from public.whatsapp_send_queue q join public.agenda_cliente_mensagens m on m.id = q.source_ref_id
                       where q.source = 'agenda-cliente' and m.tipo = 'mudanca_no_dia'),
      (r #>> '{contagens,mudanca_no_dia}') || ' ' || pg_temp.msgs(c_flav)::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    -- x3: ligado, mas o acesso fora das ondas (fica em teste) e a mudança no dia ligada
    perform pg_temp.ligar(array['material_chegou', 'nova_data', 'pode_atrasar', 'mudanca_no_dia']);
    perform pg_temp.vig('2026-10-30 17:00');
    perform set_config('agenda_teste.hoje', '2026-11-03', true);
    perform public.agenda_choveu(c_dono, null, 'whatsapp', date '2026-11-03', pg_temp.em('2026-11-03 14:00'));
    r := pg_temp.vig('2026-11-03 14:15');
    v_res := pg_temp.ok(v_res, 'C2a2 (x3) o tipo que confirma a data fora das ondas: a sombra do acesso não conta, e o M10 não vai ao Flávio',
      jsonb_array_length(pg_temp.msgs(c_flav, 'acesso')) >= 1 and pg_temp.msgs(c_flav, 'acesso') -> 0 ->> 'modo' = 'sombra'
      and jsonb_array_length(pg_temp.msgs(c_flav, 'mudanca_no_dia')) = 0,
      pg_temp.msgs(c_flav)::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    -- o acesso de fato enviado (sáb 31/10 09:00): o dia foi ouvido, o M10 sai — e às 14:15 diz "Boa tarde" (item 12)
    perform pg_temp.ligar();
    perform pg_temp.vig('2026-10-30 17:00');
    perform pg_temp.vig('2026-10-31 09:00');
    v_id := (pg_temp.msgs(c_flav, 'acesso') -> 0 ->> 'id')::uuid;
    perform pg_temp.saiu(v_id, '2026-10-31 09:00:20');
    perform set_config('agenda_teste.hoje', '2026-11-03', true);
    perform public.agenda_choveu(c_dono, null, 'whatsapp', date '2026-11-03', pg_temp.em('2026-11-03 14:00'));
    r := pg_temp.vig('2026-11-03 14:15');
    x := pg_temp.msgs(c_flav, 'mudanca_no_dia');
    v_res := pg_temp.ok(v_res, 'C2a3 o acesso enviado de verdade: o M10 de chuva sai (enfileirado) e, às 14:15, abre com "Boa tarde, Flávio." (item 12)',
      (select estado from public.agenda_cliente_mensagens where id = v_id) = 'enviada'
      and jsonb_array_length(x) = 1 and x -> 0 ->> 'estado' = 'enfileirada' and x -> 0 ->> 'modo' = 'ligado'
      and x -> 0 ->> 'texto' = 'Boa tarde, Flávio. Com a chuva de hoje não dá para trabalhar no seu motorhome com segurança. Podemos passar para quarta (04/11), pela manhã? Responda SIM ou me diga outro dia.'
      and x -> 0 #>> '{base,dados,saudacao}' = 'Boa tarde',
      x::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── C2b. O aviso de atraso que não sai não fica mudo (item 3) ──
  begin
    -- x1: os 3 primeiros dias pedem o dono; ele aprova na ter 03/11 às 10:00 (o M6 era para sáb 31/10 09:01)
    perform pg_temp.ligar(null, 3);
    perform pg_temp.vig('2026-10-30 17:00');
    perform pg_temp.vig('2026-11-03 09:45');
    perform set_config('agenda_teste.hoje', '2026-11-03', true);
    r := public.agenda_cliente_decidir_dito(c_dono, 'manda', 'Nelson', 'whatsapp', date '2026-11-03', pg_temp.em('2026-11-03 10:00'));
    x := pg_temp.msgs(c_nel, 'pode_atrasar');
    v_res := pg_temp.ok(v_res, 'C2b1 (x1) o M6 aprovado depois do dia marcado, ainda válido: "Mando para Nelson agora." e enfileirado às 10:00 de ter 03/11 (antes: recusado por "janela")',
      r ->> 'texto' = 'Mando para Nelson agora.' and jsonb_array_length(x) = 1 and x -> 0 ->> 'estado' = 'enfileirada'
      and x -> 0 ->> 'enviar' = '03/11 10:00',
      r::text || ' ' || x::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    -- R4g: o Nelson nunca escreveu (sem conversa no último ano): o M6 de sáb 09:01 é recusado no envio
    perform pg_temp.ligar();
    delete from public.whatsapp_messages where direction = 'inbound' and right(phone_normalized, 8) = '00000305';
    perform pg_temp.vig('2026-10-30 17:00');
    r := pg_temp.vig('2026-10-31 09:15');
    r2 := pg_temp.vig('2026-10-31 09:30');
    x := pg_temp.msgs(c_nel, 'pode_atrasar');
    v_res := pg_temp.ok(v_res, 'C2b2 (R4g) o aviso de atraso recusado pelo canal (sem conversa), com a data dita por vir: a pergunta "não saiu" ao dono, uma vez, com o motivo',
      jsonb_array_length(x) = 1 and x -> 0 ->> 'estado' = 'recusada' and x -> 0 ->> 'motivo' = 'sem_conversa'
      and (select count(*) from public.agenda_perguntas q where q.chave = 'cliente_resposta:nao_saiu:' || (x -> 0 ->> 'id')) = 1
      and (select q.texto from public.agenda_perguntas q where q.chave = 'cliente_resposta:nao_saiu:' || (x -> 0 ->> 'id'))
          = 'Não consegui avisar Nelson do atraso (o cliente não escreveu para a HBR nos últimos 365 dias, e mensagem automática a quem não escreve arrisca o número): recomendo você ligar hoje.'
      and (r #>> '{contagens,atraso,nao_saiu}')::int = 1 and (r2 #>> '{contagens,atraso,nao_saiu}')::int = 0,
      x::text || ' ' || (r #>> '{contagens,atraso}'));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    -- E11d: o "ficou pronto" da Lucenira enfileirado; o provedor não entrega (o worker desiste: failed)
    perform pg_temp.ligar();
    perform pg_temp.vig('2026-10-30 15:15');
    v_id := (pg_temp.msgs(c_luc, 'pronto') -> 0 ->> 'id')::uuid;
    update public.whatsapp_send_queue set status = 'failed', attempts = 3, failed_reason = 'provedor: número inválido'
     where source = 'agenda-cliente' and source_ref_id = v_id;
    r := pg_temp.vig('2026-10-30 15:30');
    v_res := pg_temp.ok(v_res, 'C2b3 (E11d) a linha que o provedor não entregou (failed): a mensagem fica recusada com o motivo "entrega" (antes: enfileirada para sempre); o motivo em texto',
      (select m.estado = 'recusada' and m.recusa_motivo = 'entrega' from public.agenda_cliente_mensagens m where m.id = v_id)
      and (r #>> '{contagens,fila,entrega}')::int = 1
      and public._agenda_cliente_motivo_texto('entrega') = 'o WhatsApp não conseguiu entregar a mensagem',
      (r #>> '{contagens,fila}') || ' ' || pg_temp.msgs(c_luc)::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── C2c. Uma OS que faz o texto lançar não derruba o passo (item 4) ──
  begin
    perform pg_temp.ligar();
    update public.vessels set name = 'Bravo 20155' where id = (select vessel_id from public.service_orders where id = c_flav);
    r := pg_temp.vig('2026-10-30 17:00');
    v_res := pg_temp.ok(v_res, 'C2c1 (x7b) o barco "Bravo 20155" faz o texto do Flávio cair no proibido: o Rodrigo é registrado mesmo assim, o erro do Flávio fica em app_error_logs (agenda / cliente:confirmar:os) e a rodada não falha',
      jsonb_array_length(pg_temp.msgs(c_rod)) = 1 and jsonb_array_length(pg_temp.msgs(c_flav)) = 0
      and (r #>> '{contagens,confirmar,erros_os}')::int = 1 and jsonb_array_length(r -> 'falhas') = 0
      and exists (select 1 from public.app_error_logs e
                   where e.context = 'agenda' and e.action = 'cliente:confirmar:os' and e.details ->> 'os' = c_flav::text
                     and e.message like 'mensagem ao cliente, passo confirmar, OS-00104: %'),
      (r #>> '{contagens,confirmar}') || ' ' || (r -> 'falhas')::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── C2d. O remarcado em que só o fim mudou (item 6) ──
  begin
    -- o Flávio ouviu ter 03/11 (um dia); o plano é ter 03/11 à tarde e qua 04/11 de manhã: o início é o mesmo
    perform pg_temp.ligar();
    perform public._agenda_cliente_gravar_prometido(c_flav, 'firme', date '2026-11-03', date '2026-11-03', 'dono', null,
                                                    pg_temp.em('2026-10-29 10:00'), 'teste C2d');
    x := public._agenda_cliente_risco(c_flav, date '2026-10-30');
    r := public._agenda_cliente_registrar('pode_atrasar', x ->> 'variante', c_flav, (x ->> 'faixa_de')::date,
           jsonb_build_object('prometido_tipo', 'firme', 'dito_de', x -> 'dito_de', 'dito_ate', x -> 'dito_ate',
                              'forma', 'fim', 'dia', x -> 'faixa_de', 'fim', x -> 'faixa_ate'),
           pg_temp.em('2026-10-30 10:00'), pg_temp.em('2026-11-03 19:00'), 'rodada', null, pg_temp.em('2026-10-30 10:00'));
    v_id := (r ->> 'id')::uuid;
    v_res := pg_temp.ok(v_res, 'C2d1 o risco do replano com o mesmo início que o cliente ouviu vem com a forma fim; o texto (byte a byte) e o fim no base',
      x ->> 'variante' = 'remarcado' and x ->> 'forma' = 'fim'
      and r ->> 'texto' = 'Olá, Flávio! Aqui é o Gustavo, da HBR Marine Solutions. A instalação do compressor vai precisar de mais um dia: agora fica de terça (03/11) até quarta (04/11). Desculpe pela mudança. Pode ser? Responda SIM ou me diga outro dia.'
      and (select m.base ->> 'fim' = '2026-11-04' and m.base #>> '{dados,forma}' = 'fim' and m.prometido_tipo = 'firme'
             from public.agenda_cliente_mensagens m where m.id = v_id),
      x::text || ' ' || r::text);
    -- o último dia do plano muda (qua 04/11 sai): a revalidação recusa data_mudou
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'desfeito', cancelada_em = pg_temp.em('2026-10-30 10:05')
     where service_order_id = c_flav and dia = date '2026-11-04' and estado in ('publicada', 'fixada');
    v_res := pg_temp.ok(v_res, 'C2d2 a forma fim: com o último dia do plano diferente do fim dito, a revalidação recusa (data_mudou)',
      public._agenda_cliente_revalidar(v_id, pg_temp.em('2026-10-30 10:10')) = 'data_mudou',
      public._agenda_cliente_revalidar(v_id, pg_temp.em('2026-10-30 10:10')));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── C2e. A data firme do dono sai (item 7; x6) ──
  begin
    perform pg_temp.ligar();
    update public.os_planejamento set prometido_tipo = 'firme', prometido_de = date '2026-11-03', prometido_ate = date '2026-11-04',
           prometido_original_ate = date '2026-11-04', prometido_fonte = 'dono', prometido_em = now()
     where service_order_id = c_ven;
    r := public.agenda_cliente_preparar(c_dono, 'OS-00069', 'pode_atrasar', true, 'avisa o Vanderlei com a data firme',
                                        date '2026-10-30', pg_temp.em('2026-10-30 10:00'));
    r2 := public.agenda_cliente_decidir_dito(c_dono, 'manda', 'Vanderlei', 'whatsapp', date '2026-10-30', pg_temp.em('2026-10-30 10:05'));
    x := pg_temp.msgs(c_ven, 'pode_atrasar');
    v_res := pg_temp.ok(v_res, 'C2e1 (x6) o firme do dono com o material ainda não todo na mão: preparado com firme_do_dono e, no *manda cliente*, vai à fila (antes: recusado por "material")',
      r2 ->> 'texto' = 'Mando para Vanderlei agora.' and jsonb_array_length(x) = 1 and x -> 0 ->> 'estado' = 'enfileirada'
      and (x -> 0 #>> '{base,dados,firme_do_dono}')::boolean
      and r ->> 'texto' like 'Pronto para Vanderlei, sai agora: "Olá, Vanderlei! Aqui é o Gustavo, da HBR Marine Solutions. O serviço no Mar Azul vai precisar de mais um dia: agora fica de terça (03/11) até quinta (05/11).%',
      r::text || ' ' || r2::text || ' ' || x::text);
    -- a mesma data firme registrada pela rodada (sem o dono): o passo do material continua valendo
    r := public._agenda_cliente_registrar('pode_atrasar', 'remarcado', c_ven, date '2026-11-03',
           jsonb_build_object('dia', '2026-11-03', 'fim', '2026-11-05', 'prometido_tipo', 'firme', 'dito_de', '2026-11-03',
                              'dito_ate', '2026-11-04', 'chave', 'c2e'),
           pg_temp.em('2026-10-30 11:00'), pg_temp.em('2026-11-04 19:00'), 'rodada', null, pg_temp.em('2026-10-30 10:30'));
    v_res := pg_temp.ok(v_res, 'C2e2 a data firme da rodada com o material fora de A continua recusada (material)',
      public._agenda_cliente_revalidar((r ->> 'id')::uuid, pg_temp.em('2026-10-30 11:00')) = 'material',
      public._agenda_cliente_revalidar((r ->> 'id')::uuid, pg_temp.em('2026-10-30 11:00')));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── C2f. A peça sem previsão não vira data (item 8) ──
  begin
    perform pg_temp.ligar();
    x := public._agenda_cliente_risco(c_nel, date '2026-10-30');
    perform pg_temp.vig('2026-10-30 17:00');
    perform pg_temp.vig('2026-10-31 09:15');
    v_id := (pg_temp.msgs(c_nel, 'pode_atrasar') -> 0 ->> 'id')::uuid;
    perform pg_temp.saiu(v_id, '2026-10-31 09:15:20');
    v_res := pg_temp.ok(v_res, 'C2f1 o Nelson (2 críticos sem previsão, o painel em 11/11): o aviso sem data (peca_sem_data, condicional, o texto byte a byte), sem prometido; ao sair, o prometido da OS fica nulo (o de antes no histórico)',
      x ->> 'variante' = 'peca_sem_data' and x ->> 'tipo' = 'condicional'
      and (select m.estado = 'enviada' and m.prometido_tipo is null and m.texto = 'Nelson, quero te avisar com antecedência: ainda faltam peças do serviço no seu veleiro sem data de chegada, então o serviço no seu veleiro, que estava para quinta (05/11), vai atrasar. Te digo a nova data assim que elas chegarem. Se isso atrapalhar algum plano seu, me diga.'
             from public.agenda_cliente_mensagens m where m.id = v_id)
      and (select p.prometido_ate is null and p.prometido_tipo is null and p.prometido_original_ate is null
                  and p.historico -> -1 #>> '{antes,prometido_ate}' = '2026-11-05'
             from public.os_planejamento p where p.service_order_id = c_nel),
      x::text || ' ' || (select to_jsonb(p) - 'historico' from public.os_planejamento p where p.service_order_id = c_nel)::text);
    -- a data antiga (qui 05/11) passa: sem o prometido, nada de "passou sem aviso" nem outro aviso
    r := pg_temp.vig('2026-11-06 10:00');
    v_res := pg_temp.ok(v_res, 'C2f2 depois do aviso sem data, a data antiga passa sem a pergunta "passou sem aviso" e sem outro aviso de atraso',
      not exists (select 1 from public.agenda_perguntas q where q.chave like 'cliente_aviso:' || c_nel || ':%')
      and jsonb_array_length(pg_temp.msgs(c_nel, 'pode_atrasar')) = 1,
      (r #>> '{contagens,atraso}'));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    -- R4i do revisor: todos os críticos com data — continua a faixa (variante peca), com o texto de antes
    perform pg_temp.ligar();
    update public.os_material set situacao = 'comprado', comprado_em = date '2026-10-28', comprado_fonte = 'dono', fonte = 'dono',
           previsao_ate = date '2026-11-10', previsao_fonte = 'dono'
     where service_order_part_id in (md5('peca:112:1')::uuid, md5('peca:112:2')::uuid, md5('peca:112:3')::uuid);
    x := public._agenda_cliente_risco(c_nel, date '2026-10-30');
    v_res := pg_temp.ok(v_res, 'C2f3 (R4i) com todos os críticos com previsão, o aviso continua com a faixa (variante peca, sem a forma sem data)',
      x ->> 'variante' = 'peca' and (x ->> 'risco')::boolean and x ->> 'faixa_de' = '2026-11-12',
      x::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── C2g. A saudação pela hora do envio (item 12) ──
  begin
    perform pg_temp.ligar();
    -- a véspera do Flávio registrada para seg 02/11? é Finados: a do toque de sáb 31/10 às 14:00 (depois do sábado de
    -- janela) vai à próxima janela; aqui a hora é marcada para ter 03/11 14:00 à mão (o alvo) — o texto diz "Boa tarde"
    r := public._agenda_cliente_registrar('acesso', null, c_flav, date '2026-11-04', jsonb_build_object('chave', 'c2g'),
           pg_temp.em('2026-11-03 14:00'), pg_temp.em('2026-11-03 19:00'), 'rodada', null, pg_temp.em('2026-10-30 10:00'));
    v_id := (r ->> 'id')::uuid;
    v_res := pg_temp.ok(v_res, 'C2g1 a mensagem que sai às 14:00 abre com "Boa tarde" (gravado em base.dados.saudacao)',
      r ->> 'texto' like 'Boa tarde, Flávio! Aqui é o Gustavo, da HBR Marine Solutions. %'
      and (select m.base #>> '{dados,saudacao}' = 'Boa tarde' from public.agenda_cliente_mensagens m where m.id = v_id),
      r::text);
    -- a hora muda depois (a conversa viva empurra para as 16:00 do mesmo dia): a revalidação não a dá como desatualizada
    update public.agenda_cliente_mensagens set enviar_em = pg_temp.em('2026-11-03 16:00') where id = v_id;
    v_t := public._agenda_cliente_revalidar(v_id, pg_temp.em('2026-11-03 16:00'));
    v_res := pg_temp.ok(v_res, 'C2g2 a hora que muda depois do registro não deixa a mensagem desatualizada (a saudação é a do registro)',
      v_t is distinct from 'desatualizada', coalesce(v_t, 'sai'));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── C2h. Ao dono, sem artigo antes do nome (item 15) ──
  v_res := pg_temp.ok(v_res, 'C2h1 a regra: "O Flávio respondeu", "ao Flávio", "do Flávio", "para o Flávio" e "aviso o Flávio" perdem o artigo; o serviço "no seu motorhome" e outro nome ficam',
    public._agenda_cliente_sem_artigo('O Flávio respondeu. Mando ao Flávio o aviso do Flávio; você liga para o Flávio; não aviso o Flávio. O serviço no seu motorhome, o Flávio Junior? o Nelson.', c_flav)
      = 'Flávio respondeu. Mando para Flávio o aviso de Flávio; você liga para Flávio; não aviso Flávio. O serviço no seu motorhome, Flávio Junior? o Nelson.',
    public._agenda_cliente_sem_artigo('O Flávio respondeu. Mando ao Flávio o aviso do Flávio; você liga para o Flávio; não aviso o Flávio. O serviço no seu motorhome, o Flávio Junior? o Nelson.', c_flav));
  v_t := public._agenda_cliente_texto_do_aviso('segundo_atraso', 'pode_atrasar', c_nel,
           '{"faixa_de": "2026-11-12", "faixa_ate": "2026-11-13"}', date '2026-10-30');
  v_res := pg_temp.ok(v_res, 'C2h2 o aviso crítico ao dono: o serviço sem o possessivo do cliente ("O serviço da OS-00112") e o nome sem artigo',
    v_t = 'O serviço da OS-00112 de Nelson vai atrasar de novo (qui 05/11 → qui 12 e sex 13/11). É o 2º atraso: recomendo você ligar. 1) Você liga e eu não mando nada (recomendo); 2) Eu mando o aviso escrito; 3) Não aviso agora.',
    v_t);
  v_t := public._agenda_cliente_texto_do_aviso('passou', 'pode_atrasar', c_flav, '{"dito_de": "2026-11-03", "dito_ate": "2026-11-03"}',
                                              date '2026-11-04');
  v_res := pg_temp.ok(v_res, 'C2h3 com o serviço dito ao cliente (servico_cliente), o aviso usa ele: "A data que Flávio ouviu …"',
    v_t like 'A data que Flávio ouviu (ter 03/11) passou sem aviso. Recomendo você ligar hoje.%', v_t);

  -- ── C2i. O pós-serviço sem entrega registrada (item 22) ──
  begin
    perform pg_temp.ligar();
    perform pg_temp.vig('2026-10-30 15:15');
    v_id := (pg_temp.msgs(c_luc, 'pronto') -> 0 ->> 'id')::uuid;
    perform pg_temp.saiu(v_id, '2026-10-30 15:15:20');
    r := pg_temp.vig('2026-11-05 09:30');
    v_res := pg_temp.ok(v_res, 'C2i1 (R6e) a Lucenira (concluída sex 30/10, sem entrega) recebeu o "ficou pronto" e não respondeu: no 5º dia o pós-serviço ("Já deu para usar?") não sai',
      (select estado from public.agenda_cliente_mensagens where id = v_id) = 'enviada'
      and jsonb_array_length(pg_temp.msgs(c_luc, 'pos_servico')) = 0 and (r #>> '{contagens,pos_servico,sem_entrega}')::int = 1,
      (r #>> '{contagens,pos_servico}') || ' ' || pg_temp.msgs(c_luc)::text);
    -- ela respondeu (combinou a entrega): o pós-serviço sai
    update public.agenda_cliente_mensagens set estado = 'respondida', resposta_id = gen_random_uuid()
     where service_order_id = c_luc and tipo in ('pronto', 'pronto_lembrete') and estado in ('enviada', 'sem_resposta');
    update public.agenda_cliente_mensagens set estado = 'recusada', recusa_motivo = 'segurada', aprovacao = 'segurada',
           aprovada_em = pg_temp.em('2026-11-05 09:30')
     where service_order_id = c_luc and tipo = 'pronto_lembrete' and estado in ('registrada', 'aguardando_dono');
    r := pg_temp.vig('2026-11-05 09:45');
    v_res := pg_temp.ok(v_res, 'C2i2 com o "ficou pronto" respondido, o pós-serviço sai (sem entrega registrada)',
      jsonb_array_length(pg_temp.msgs(c_luc, 'pos_servico')) = 1, (r #>> '{contagens,pos_servico}') || ' ' || pg_temp.msgs(c_luc, 'pos_servico')::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── C2j. O 2º atraso conta só os avisos enviados (item 23) ──
  begin
    -- o Nelson pediu outro dia antes (o prometido foi de qua 04/11 para qui 05/11 a pedido dele); nenhum aviso de atraso
    -- nem nova data enviados
    update public.os_planejamento set prometido_original_ate = date '2026-11-04' where service_order_id = c_nel;
    x := public._agenda_cliente_risco(c_nel, date '2026-10-30');
    v_res := pg_temp.ok(v_res, 'C2j1 (R4j) o prometido que mudou a pedido do cliente (original antes do de agora), sem aviso enviado: não é o 2º atraso',
      not (x ->> 'segundo')::boolean, x::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── C2k. A OS faturada recebe o "ficou pronto" (item 24) ──
  begin
    perform pg_temp.ligar();
    perform set_config('agenda.porta', 'on', true);
    update public.service_orders set status = 'invoiced' where id = c_luc;
    perform set_config('agenda.porta', 'off', true);
    r := pg_temp.vig('2026-10-30 15:15');
    x := pg_temp.msgs(c_luc, 'pronto');
    v_res := pg_temp.ok(v_res, 'C2k1 (R6f) a Lucenira faturada logo depois de concluída: o "ficou pronto" é registrado e vai à fila (a revalidação a vale como concluída)',
      jsonb_array_length(x) = 1 and x -> 0 ->> 'estado' = 'enfileirada'
      and public._agenda_cliente_revalidar((x -> 0 ->> 'id')::uuid, pg_temp.em('2026-10-30 15:16')) is null,
      x::text || ' ' || (r #>> '{contagens,pronto}'));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── C2l. O cartão conta direto (B3) ──
  begin
    perform pg_temp.ligar(null, 3);
    perform pg_temp.vig('2026-10-30 17:00');
    perform set_config('agenda.agora', pg_temp.em('2026-10-30 17:05')::text, true);
    v_n := (public.os_plano_da_os(c_nel, date '2026-10-30') #>> '{cliente,esperando_voce,n}')::int;
    v_res := pg_temp.ok(v_res, 'C2l1 o cartão "Plano" conta o que espera o dono igual ao foco clientes (o aviso de atraso do Nelson esperando *manda cliente*)',
      v_n = 1 and v_n = (public._agenda_ver_clientes(c_nel, date '2026-10-30') #>> '{dados,esperando}')::int,
      format('cartão %s; foco %s', v_n, public._agenda_ver_clientes(c_nel, date '2026-10-30') #>> '{dados,esperando}'));
    v_res := pg_temp.ok(v_res, 'C2l2 o cartão não monta mais o foco inteiro (a conta direta antes da chamada que não roda)',
      (select p.prosrc like '%a conta direta%' or p.prosrc like '%direto nas tabelas%'
         from pg_proc p where p.oid = 'public._agenda_cliente_da_os(uuid, date)'::regprocedure), null);
    perform set_config('agenda.agora', '', true);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

    raise exception 'desfaz a fixture' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$c2$;

-- ── C2z. As cópias e as portas ──────────────────────────────────────────────────────────────────────────
do $c2z$
declare
  v_tex  text := coalesce(current_setting('agenda_teste.mig_textos_fase5', true), '');
  v_env  text := coalesce(current_setting('agenda_teste.mig_envio_fase5', true), '');
  v_rod  text := coalesce(current_setting('agenda_teste.mig_rodada_fase5', true), '');
  v_lei  text := coalesce(current_setting('agenda_teste.mig_leituras_fase5', true), '');
  v_tel  text := coalesce(current_setting('agenda_teste.mig_telas_fase5', true), '');
  v_c1   text := coalesce(current_setting('agenda_teste.mig_correcao_resposta_fase5', true), '');
  v_velho text[];
  v_novo text[];
  v_src  text;
  r record;
begin
  -- as portas das novas: ninguém de fora (nem o service_role); search_path fixo; só a que escreve o prometido é definer
  insert into _resultado
  select format('C2z0 %s: interna (sem anon, authenticated nem service_role), search_path fixo, security definer = %s', f, d),
         not has_function_privilege('anon', to_regprocedure(f), 'execute')
         and not has_function_privilege('authenticated', to_regprocedure(f), 'execute')
         and not has_function_privilege('service_role', to_regprocedure(f), 'execute')
         and (select p.prosecdef = d and array_to_string(p.proconfig, ',') like '%search_path=%' from pg_proc p where p.oid = to_regprocedure(f)),
         null
    from (values ('public._agenda_cliente_sem_artigo(text, uuid)', false),
                 ('public._agenda_cliente_erro_da_os(text, uuid, text, text, date)', false),
                 ('public._agenda_cliente_tirar_prometido(uuid, uuid, timestamptz, text)', true)) t(f, d);
  insert into _resultado
  select 'C2z0 as leituras recriadas continuam para authenticated e service_role (nunca anon)',
         bool_and(has_function_privilege('authenticated', to_regprocedure(f), 'execute')
                  and has_function_privilege('service_role', to_regprocedure(f), 'execute')
                  and not has_function_privilege('anon', to_regprocedure(f), 'execute')), null
    from unnest(array['public._agenda_cliente_texto(text, text, uuid, jsonb, date)', 'public._agenda_cliente_ouviu(uuid, date, timestamptz)',
                      'public._agenda_cliente_risco(uuid, date)', 'public._agenda_cliente_fechamento(date)',
                      'public.agenda_cliente_preparar(uuid, text, text, boolean, text, date, timestamptz)']) f;
  insert into _resultado
  select 'C2z0 a lista fechada da recusa ganhou "entrega" e o índice da conversa existe',
         exists (select 1 from pg_constraint k where k.conrelid = 'public.agenda_cliente_mensagens'::regclass
                    and k.conname = 'agenda_cliente_mensagens_recusa_motivo_check' and pg_get_constraintdef(k.oid) like '%entrega%')
         and exists (select 1 from pg_indexes i where i.schemaname = 'public' and i.indexname = 'agenda_wa_recebidas_por_chave'),
         null;

  if v_tex = '' or v_env = '' or v_rod = '' or v_lei = '' or v_tel = '' or v_c1 = '' then
    insert into _resultado values ('C2z as cópias', true, 'PULADO: sem agenda_teste.mig_*_fase5 (rode pela bancada)');
    return;
  end if;
  for r in
    select * from (values
      ('_agenda_cliente_texto', 'public._agenda_cliente_texto(text, text, uuid, jsonb, date)', 'textos'),
      ('_agenda_cliente_texto_do_aviso', 'public._agenda_cliente_texto_do_aviso(text, text, uuid, jsonb, date)', 'envio'),
      ('_agenda_cliente_perguntar', 'public._agenda_cliente_perguntar(text, text, uuid, date, date, text, text, timestamptz, timestamptz)', 'envio'),
      ('_agenda_cliente_registrar', 'public._agenda_cliente_registrar(text, text, uuid, date, jsonb, timestamptz, timestamptz, text, text, timestamptz, uuid)', 'envio'),
      ('_agenda_cliente_enviada', 'public._agenda_cliente_enviada()', 'envio'),
      ('_agenda_cliente_fila', 'public._agenda_cliente_fila(date, timestamptz)', 'envio'),
      ('_agenda_cliente_ouviu', 'public._agenda_cliente_ouviu(uuid, date, timestamptz)', 'rodada'),
      ('_agenda_cliente_risco', 'public._agenda_cliente_risco(uuid, date)', 'rodada'),
      ('_agenda_cliente_acorde', 'public._agenda_cliente_acorde(uuid, text, text, date, date, uuid)', 'rodada'),
      ('_agenda_cliente_material', 'public._agenda_cliente_material(date, timestamptz)', 'rodada'),
      ('_agenda_cliente_mudanca_no_dia', 'public._agenda_cliente_mudanca_no_dia(date, timestamptz)', 'rodada'),
      ('_agenda_cliente_atraso', 'public._agenda_cliente_atraso(date, timestamptz)', 'rodada'),
      ('_agenda_cliente_andamento', 'public._agenda_cliente_andamento(date, timestamptz)', 'rodada'),
      ('_agenda_cliente_pronto', 'public._agenda_cliente_pronto(date, timestamptz)', 'rodada'),
      ('_agenda_cliente_pos_servico', 'public._agenda_cliente_pos_servico(date, timestamptz)', 'rodada'),
      ('agenda_cliente_preparar', 'public.agenda_cliente_preparar(uuid, text, text, boolean, text, date, timestamptz)', 'leituras'),
      ('_agenda_cliente_fechamento', 'public._agenda_cliente_fechamento(date)', 'leituras'),
      ('_agenda_cliente_da_os', 'public._agenda_cliente_da_os(uuid, date)', 'telas'),
      ('_agenda_cliente_motivo_texto', 'public._agenda_cliente_motivo_texto(text)', 'c1'),
      ('_agenda_cliente_revalidar', 'public._agenda_cliente_revalidar(uuid, timestamptz)', 'c1'),
      ('_agenda_cliente_enfileirar', 'public._agenda_cliente_enfileirar(uuid, timestamptz)', 'c1'),
      ('_agenda_cliente_decidir', 'public._agenda_cliente_decidir(uuid, smallint, uuid, text, text, timestamptz)', 'c1'),
      ('_agenda_cliente_confirmar', 'public._agenda_cliente_confirmar(date, timestamptz)', 'c1'),
      ('agenda_resposta_do_cliente', 'public.agenda_resposta_do_cliente(text, text, uuid, text, text, text, timestamptz)', 'c1')
    ) t(nome, assinatura, fonte)
  loop
    v_src := pg_temp.corpo(case r.fonte when 'textos' then v_tex when 'envio' then v_env when 'rodada' then v_rod
                                        when 'leituras' then v_lei when 'telas' then v_tel else v_c1 end, r.nome);
    v_velho := pg_temp.sem_correcao(v_src);
    v_novo := pg_temp.sem_correcao((select p.prosrc from pg_proc p where p.oid = r.assinatura::regprocedure));
    insert into _resultado select format('C2z1 a cópia de %s (de %s) só acrescenta os blocos "-- CORREÇÃO FASE 5:" e guarda os da C1', r.nome,
                                          case r.fonte when 'c1' then '20261028100700' when 'textos' then '20261028100100'
                                                       when 'envio' then '20261028100200' when 'rodada' then '20261028100300'
                                                       when 'leituras' then '20261028100500' else '20261028100600' end),
      v_novo = v_velho and cardinality(v_velho) > 5
      and (select count(*) from regexp_matches(p.prosrc, '-- CORREÇÃO FASE 5:', 'g'))
          > (select count(*) from regexp_matches(v_src, '-- CORREÇÃO FASE 5:', 'g'))
      and not exists (select 1 from unnest(string_to_array(v_src, E'\n')) l
                       where l ~ '-- CORREÇÃO FASE 5:' and position(l in p.prosrc) = 0),
      format('linhas %s × %s', array_length(v_novo, 1), array_length(v_velho, 1))
    from pg_proc p where p.oid = r.assinatura::regprocedure;
  end loop;
end
$c2z$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
