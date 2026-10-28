-- Prova da correção C1 da Fase 5 da Agenda de Produção (migration 20261028100700): a resposta do cliente, o botão "Pedir
-- confirmação" e o envio. Cada caso é o cenário do revisor (revisao-fase5-correcao.md e revisao-fase5-regressao.md) e falha
-- no código de antes da correção.
-- bancada: depende de 20261028100700
--
--   C1a (A1 = item 11; o r04 da regressão) a resposta só é da agenda quando a última mensagem da HBR ao número é a dela:
--       o pedido do botão antigo depois do aviso → consumiu false e o "sim" de 30/09 confirma a OS do botão; sem ele, o
--       mesmo "Sim" é ciência; o dono falando depois → não consome; o eco da própria mensagem da agenda não conta; o M1 pelo
--       botão (origem botao) não é "outra conversa"; em teste, a sombra também não registra
--   C1b (item 2) o PARAR vale sempre para quem recebeu mensagem da agenda em 30 dias: 4 dias depois do pós-serviço; depois
--       de outra resposta; as vivas canceladas; sem mensagem enviada (ou há mais de 30 dias) não consome
--   C1c (item 16) o acesso com negação vai ao dono e não marca o acesso
--   C1d (item 17) falta/remarcar com um número de dia não entendido ("volto dia 20") vai ao dono e nada muda
--   C1e (item 9) o "dia N" sem mês: "dia 31" em novembro não entendido; "dia 2" e "dia 3/12" (e "vou viajar até 20/12")
--       além de cliente_pedido_max_du dias úteis vão ao dono; o parâmetro mexe na regra
--   C1f (itens 5, 19 e 21; M1 e B1) o botão pela interna com a hora fixa: a confirmação da rodada esperando o dono é
--       aprovada pelo clique; a segurada ganha a 2ª pelo botão; a já mandada, a que vai sair sozinha e a 2ª recusada só dizem;
--       sem conversa e o teto viram o erro no clique, de dia e de noite, sem gravar nada; o caminho antigo fora do horário
--       recusa (em teste e fora das ondas), dentro do horário vai como antes, e desligado vai a qualquer hora (30/09)
--   C1g (item 5c / M1) a mensagem que o dono mandou mandar e que é recusada depois (o passo fila de manhã, o worker) abre a
--       pergunta "não saiu"; a segurada, a da rodada não aprovada e a recusa na hora da decisão não abrem
--   C1h (item 13) o d10 na revalidação: revalidar e pode_sair dizem sem_conversa; a nova tentativa da fila também
--   C1i (item 14) o intervalo remarca a hora em vez de recusar; passou da validade = vencida
--   C1j (item 20) o M1 do dia que o botão antigo já pediu (ou que o cliente já confirmou) não sai; sem o pedido, sai
--   C1z as cópias recriadas só mudam nos blocos "-- CORREÇÃO FASE 5:" (e _pedir_confirmacao nas 7 linhas do now()); as
--       portas e o security definer das novas
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase5_correcao_resposta.sql
--   C1z roda em qualquer lugar (as cópias só com as migrations como texto); o resto só na bancada (a fixture-fase5; fora
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

create function pg_temp.erro_de(p_sql text) returns text language plpgsql as $f$
declare
  v_estado text; v_msg text;
begin
  execute p_sql;
  return 'sem erro';
exception when others then
  get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
  return v_estado || ' ' || v_msg;
end $f$;

-- A hora de Brasília escrita como se fala: pg_temp.em('2026-10-30 10:00') = timestamptz '2026-10-30 10:00-03'.
create function pg_temp.em(p_quando text) returns timestamptz language sql immutable as $f$
  select (p_quando::timestamp) at time zone 'America/Sao_Paulo'
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

-- Uma mensagem da agenda já enviada ao cliente (o que a rodada e o envio teriam deixado).
create function pg_temp.enviada(p_cli uuid, p_os uuid, p_tipo text, p_dia date, p_em timestamptz, p_var text default null,
                                p_modo text default 'ligado', p_texto text default 'mensagem de teste (C1F5)',
                                p_origem text default 'rodada') returns uuid language sql as $f$
  insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, variante, origem, dia_alvo, modo, texto, base,
                                               enviar_em, valida_ate, aprovacao, aprovada_em, estado, dedupe_key, enviada_em,
                                               criada_em)
  values (p_cli, p_os, p_tipo, p_var, p_origem, p_dia, p_modo, p_texto,
          case when p_dia is null then '{}'::jsonb else jsonb_build_object('dia_alvo', p_dia) end,
          p_em, p_em + interval '9 hours', case when p_origem = 'botao' then 'aprovada' else 'livre' end,
          case when p_origem = 'botao' then p_em end,
          case when p_modo = 'sombra' then 'registrada' else 'enviada' end, 'agenda-cliente:teste:' || gen_random_uuid(),
          case when p_modo = 'sombra' then null else p_em end, p_em - interval '1 hour')
  returning id
$f$;

-- A mensagem do cliente que chega (a intenção e a expressão são as do leitor do TS, provadas no reply-router_test.ts).
create function pg_temp.resp(p_fone text, p_body text, p_int text, p_expr text, p_em timestamptz) returns jsonb
language plpgsql as $f$
begin
  perform set_config('agenda_teste.hoje', (p_em at time zone 'America/Sao_Paulo')::date::text, true);
  return public.agenda_resposta_do_cliente(p_fone, p_body, gen_random_uuid(), 'text', p_int, p_expr, p_em);
end $f$;

-- A rodada do cliente com o "hoje" da hora dada.
create function pg_temp.vig(p text) returns jsonb language plpgsql as $f$
begin
  perform set_config('agenda_teste.hoje', left(p, 10), true);
  return public.agenda_cliente_vigiar(left(p, 10)::date, pg_temp.em(p));
end $f$;

-- O botão pela interna, com a hora fixa (o "hoje" acompanha).
create function pg_temp.botao(p_os uuid, p_quando text) returns jsonb language plpgsql as $f$
begin
  perform set_config('agenda_teste.hoje', left(p_quando, 10), true);
  return public._pedir_confirmacao(p_os, 'aa000000-0000-4000-8000-000000000001', pg_temp.em(p_quando));
end $f$;
create function pg_temp.botao_erro(p_os uuid, p_quando text) returns text language sql as $f$
  select pg_temp.erro_de(format('select pg_temp.botao(%L, %L)', p_os, p_quando))
$f$;

-- Os dias publicados/fixados de uma OS: "2026-11-03 tarde publicada,…".
create function pg_temp.plano(p_os uuid) returns text language sql stable as $f$
  select coalesce(string_agg(x.d, ',' order by x.d), '')
    from (select distinct a.dia::text || ' ' || a.turno || ' ' || a.estado as d
            from public.agenda_alocacoes a
           where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva') x
$f$;

-- O corpo de uma função numa migration (entre o "as $function$"/"as $$" que abre e o fecho), e as linhas sem os blocos
-- "-- CORREÇÃO FASE 5: … -- CORREÇÃO FASE 5: fim".
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
begin
  foreach l in array string_to_array(replace(p_corpo, E'\r\n', E'\n'), E'\n') loop
    if not v_bloco and l ~ '^\s*-- CORREÇÃO FASE 5:' and l !~ '^\s*-- CORREÇÃO FASE 5: fim' then v_bloco := true; continue; end if;
    if v_bloco then
      if l ~ '^\s*-- CORREÇÃO FASE 5: fim' then v_bloco := false; end if;
      continue;
    end if;
    v_b := v_b || l;
  end loop;
  return v_b;
end $f$;

-- ── C1a–C1j (a fixture-fase5; sex 30/10/2026) ────────────────────────────────────────────────────────────
do $c1$
declare
  v_res jsonb := '[]'::jsonb;
  c_flav     constant uuid := '05000000-0000-4000-8000-000000000104';
  c_rod      constant uuid := '05000000-0000-4000-8000-000000000096';
  c_nel      constant uuid := '05000000-0000-4000-8000-000000000112';
  c_rob      constant uuid := '05000000-0000-4000-8000-000000000121';
  c_luc      constant uuid := '05000000-0000-4000-8000-000000000122';
  c_os198    constant uuid := 'd5000000-0000-4000-8000-00000000f198';
  c_cli_flav constant uuid := 'c1000000-0000-4000-8000-000000000004';
  c_cli_nel  constant uuid := 'c1000000-0000-4000-8000-000000000005';
  c_cli_rod  constant uuid := 'c1000000-0000-4000-8000-000000000006';
  c_cli_rob  constant uuid := 'c1000000-0000-4000-8000-000000000007';
  c_cli_luc  constant uuid := 'c1000000-0000-4000-8000-000000000012';
  c_dono     constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_f        constant text := '5547900000304';    -- o WhatsApp do Flávio
  c_n        constant text := '5547900000305';    -- o do Nelson
  c_plano    constant text := '2026-11-03 tarde publicada,2026-11-04 manha publicada';
  r     jsonb;
  r2    jsonb;
  r3    jsonb;
  x     jsonb;
  v_id  uuid;
  v_id2 uuid;
  v_t   text;
  v_e   text;
  v_n   int;
begin
  if coalesce(current_setting('agenda_teste.fase5', true), '') = '' then
    insert into _resultado values ('C1a–C1j (fixture-fase5)', true, 'PULADO: sem agenda_teste.fase5 (rode pela bancada)');
    return;
  end if;
  begin
  execute current_setting('agenda_teste.fase5');

  -- ── C1a. A outra conversa (A1 = item 11; o r04 da regressão) ──
  -- O botão e o "sim" de 30/09 leem o relógio (now()): o cenário do r04 é contado dele (o pedido do botão de 1 h atrás,
  -- o aviso de ontem), e nada aqui depende da hora do dia (a resposta não olha a janela).
  begin
    perform set_config('agenda_teste.hoje', '', true);
    -- a onda 1 (a confirmação fora das ondas); o plano em sombra (a regra de 30/09 no botão e no "sim")
    perform pg_temp.ligar(array['material_chegou', 'nova_data', 'pode_atrasar']);
    update public.agenda_config set modo_proposta = 'sombra' where id;
    perform set_config('agenda.porta', 'on', true);
    insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at,
                                       updated_at, converted_to_os_at, grand_total, scheduled_start_at, scheduled_end_at,
                                       client_confirmation_requested_at)
    select c_os198, 'OS-00198', so.client_id, so.vessel_id, 'scheduled', 'approved', 'repair', now() - interval '5 days',
           now() - interval '5 days', now() - interval '5 days', 100, now() + interval '5 days', now() + interval '5 days 4 hours',
           now() - interval '1 hour'
      from public.service_orders so where so.id = c_nel;
    perform set_config('agenda.porta', 'off', true);
    -- o aviso de atraso da agenda ao Nelson (OS-00112), mandado ontem: espera resposta
    v_id := pg_temp.enviada(c_cli_nel, c_nel, 'pode_atrasar', date '2026-11-12', now() - interval '1 day', 'peca');
    r := public.agenda_resposta_do_cliente(c_n, 'Sim', gen_random_uuid(), 'text', 'acordo', null, now());
    r2 := public.registrar_confirmacao_do_cliente(c_n, 'Sim', null);
    v_res := pg_temp.ok(v_res, 'C1a1 (r04) o pedido do botão antigo depois do aviso da agenda: a agenda NÃO consome (outra_conversa); o "sim" de 30/09 confirma a OS-00198; o aviso continua enviado, sem resposta gravada',
      r ->> 'consumiu' = 'false' and r ->> 'motivo' = 'outra_conversa' and (r ->> 'mensagem_id')::uuid = v_id
      and (r2 ->> 'confirmou')::boolean and r2 ->> 'os' = 'OS-00198'
      and (select m.estado = 'enviada' and m.resposta_id is null from public.agenda_cliente_mensagens m where m.id = v_id)
      and not exists (select 1 from public.agenda_cliente_respostas x where x.client_id = c_cli_nel),
      r::text || ' / ' || r2::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform set_config('agenda_teste.hoje', '', true);
    perform pg_temp.ligar(array['material_chegou', 'nova_data', 'pode_atrasar']);
    v_id := pg_temp.enviada(c_cli_nel, c_nel, 'pode_atrasar', date '2026-11-12', now() - interval '1 day', 'peca',
                            p_texto := 'Nelson, quero te avisar com antecedência: a peça ainda não chegou.');
    -- o eco da própria mensagem da agenda (o webhook grava o que a HBR mandou, fromMe) não é outra conversa
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, occurred_at, delivery_status, wa_message_id)
    values ('outbound', c_n, 'text', 'Nelson, quero te avisar com antecedência: a peça ainda não chegou.',
            now() - interval '1 day' + interval '3 seconds', 'sent', 'WA-ECO-C1A');
    r := public.agenda_resposta_do_cliente(c_n, 'Sim', gen_random_uuid(), 'text', 'acordo', null, now());
    v_res := pg_temp.ok(v_res, 'C1a2 sem o pedido do botão, o mesmo "Sim" ao aviso de atraso é ciência (a agenda consome); o eco da mensagem dela não conta como outra conversa',
      r ->> 'consumiu' = 'true' and r ->> 'efeito' = 'ciencia', r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.ligar();
    v_id := pg_temp.enviada(c_cli_flav, c_flav, 'confirmar', date '2026-11-03', pg_temp.em('2026-10-31 09:00'), 'primeira');
    -- o dono escreveu ao Flávio depois da confirmação ("e a vaga, mudou?")
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, occurred_at, delivery_status)
    values ('outbound', c_f, 'text', 'Flávio, a vaga continua a 12?', pg_temp.em('2026-10-31 09:30'), 'sent');
    r := pg_temp.resp(c_f, 'Sim', 'acordo', null, pg_temp.em('2026-10-31 10:00'));
    v_res := pg_temp.ok(v_res, 'C1a3 o dono falou com o cliente depois da mensagem da agenda: o "Sim" é da conversa dele (consumiu false); o dia não é confirmado',
      r ->> 'consumiu' = 'false' and r ->> 'motivo' = 'outra_conversa' and pg_temp.plano(c_flav) = c_plano
      and (select client_confirmed_at is null from public.service_orders where id = c_flav), r::text);
    -- o PARAR, mesmo assim, é honrado (C1b)
    r2 := pg_temp.resp(c_f, 'PARAR', 'opt_out', null, pg_temp.em('2026-10-31 10:05'));
    v_res := pg_temp.ok(v_res, 'C1a4 depois de outra conversa o PARAR continua valendo (item 2): opt-out, consumiu true',
      r2 ->> 'consumiu' = 'true' and r2 ->> 'efeito' = 'opt_out'
      and (select opt_out_whatsapp from public.clients where id = c_cli_flav), r2::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    -- o M1 pelo botão (origem botao) grava o pedido de confirmação da OS com a hora do envio: não é "outra conversa"
    perform pg_temp.ligar();
    v_id := pg_temp.enviada(c_cli_flav, c_flav, 'confirmar', date '2026-11-03', pg_temp.em('2026-10-31 09:00'), 'primeira',
                            p_origem := 'botao');
    perform set_config('agenda.porta', 'on', true);
    update public.service_orders set client_confirmation_requested_at = pg_temp.em('2026-10-31 09:00') where id = c_flav;
    perform set_config('agenda.porta', 'off', true);
    v_res := pg_temp.ok(v_res, 'C1a5 o pedido que o próprio M1 pelo botão gravou (a hora do envio) não é outra conversa; o pedido do botão antigo uma hora depois é',
      not public._agenda_cliente_outra_conversa(array[c_cli_flav], c_f, pg_temp.em('2026-10-31 09:00'), pg_temp.em('2026-10-31 10:00'))
      and public._agenda_cliente_outra_conversa(array[c_cli_nel], c_n, pg_temp.em('2026-10-31 09:00'), pg_temp.em('2026-10-31 10:00')) = false,
      null);
    perform set_config('agenda.porta', 'on', true);
    update public.service_orders set client_confirmation_requested_at = pg_temp.em('2026-10-31 09:45') where id = c_flav;
    perform set_config('agenda.porta', 'off', true);
    v_res := pg_temp.ok(v_res, 'C1a6 o pedido do botão antigo (09:45) depois do M1 da agenda (09:00) é outra conversa',
      public._agenda_cliente_outra_conversa(array[c_cli_flav], c_f, pg_temp.em('2026-10-31 09:00'), pg_temp.em('2026-10-31 10:00')),
      null);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    -- em teste: a sombra que teria saído às 09:00 e o pedido do botão antigo às 09:30 → nem a sombra registra
    update public.agenda_config set modo_cliente = 'sombra' where id;
    v_id := pg_temp.enviada(c_cli_flav, c_flav, 'confirmar', date '2026-11-03', pg_temp.em('2026-10-31 09:00'), 'primeira',
                            p_modo := 'sombra');
    perform set_config('agenda.porta', 'on', true);
    update public.service_orders set client_confirmation_requested_at = pg_temp.em('2026-10-31 09:30') where id = c_flav;
    perform set_config('agenda.porta', 'off', true);
    r := pg_temp.resp(c_f, 'Sim', 'acordo', null, pg_temp.em('2026-10-31 10:00'));
    v_res := pg_temp.ok(v_res, 'C1a7 em teste também: depois do botão antigo, a resposta não é registrada como se fosse à agenda',
      r ->> 'consumiu' = 'false' and r ->> 'motivo' = 'outra_conversa'
      and not exists (select 1 from public.agenda_cliente_respostas x where x.client_id = c_cli_flav), r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── C1b. O PARAR vale sempre (item 2; o x13 do revisor) ──
  begin
    perform pg_temp.ligar();
    -- o pós-serviço do Robson saiu sex 30/10 09:31 ("… é só responder PARAR"); uma viva dele esperando (o lembrete de amanhã)
    v_id := pg_temp.enviada(c_cli_rob, c_rob, 'pos_servico', null, pg_temp.em('2026-10-30 09:31'));
    insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, origem, modo, texto, enviar_em, valida_ate,
                                                 aprovacao, estado, dedupe_key, criada_em)
    values (c_cli_rob, c_rob, 'pronto_lembrete', 'rodada', 'ligado', 'mensagem de teste (C1F5)', pg_temp.em('2026-11-04 09:00'),
            pg_temp.em('2026-11-04 19:00'), 'livre', 'registrada', 'agenda-cliente:teste:c1b', pg_temp.em('2026-11-03 08:00'))
    returning id into v_id2;
    r := pg_temp.resp('5547900000307', 'PARAR', 'opt_out', null, pg_temp.em('2026-11-03 10:00'));
    v_res := pg_temp.ok(v_res, 'C1b1 (A9b) o PARAR 4 dias depois do pós-serviço (fora das 72 h): consumiu, opt-out marcado, a viva recusada (opt_out), a resposta e a ação gravadas',
      r ->> 'consumiu' = 'true' and r ->> 'efeito' = 'opt_out'
      and (select opt_out_whatsapp from public.clients where id = c_cli_rob)
      and (select m.estado = 'recusada' and m.recusa_motivo = 'opt_out' from public.agenda_cliente_mensagens m where m.id = v_id2)
      and (select x.efeito = 'opt_out' and x.intencao = 'opt_out' and x.mensagem_id = v_id and x.acao_id = (r ->> 'acao_id')::uuid
             from public.agenda_cliente_respostas x where x.id = (r ->> 'resposta_id')::uuid)
      and (select a.texto = 'O Robson pediu para não receber mais mensagens: não mando mais nada a ele.' and a.origem = 'cliente'
                  and a.desfazivel_ate is null and (a.depois ->> 'canceladas')::int = 1
             from public.agenda_acoes a where a.id = (r ->> 'acao_id')::uuid),
      r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.ligar();
    v_id := pg_temp.enviada(c_cli_rob, c_rob, 'pos_servico', null, pg_temp.em('2026-10-30 09:31'));
    r := pg_temp.resp('5547900000307', 'Tudo certo, obrigado!', 'acordo', null, pg_temp.em('2026-10-30 11:00'));
    r2 := pg_temp.resp('5547900000307', 'PARAR', 'opt_out', null, pg_temp.em('2026-10-30 11:05'));
    v_res := pg_temp.ok(v_res, 'C1b2 (A9c) o PARAR depois de outra resposta (a mensagem já respondida): consumiu e o opt-out marcado',
      r ->> 'consumiu' = 'true' and r2 ->> 'consumiu' = 'true' and r2 ->> 'efeito' = 'opt_out'
      and (select opt_out_whatsapp from public.clients where id = c_cli_rob), r::text || ' ' || r2::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.ligar();
    -- o Flávio nunca recebeu nada da agenda; o Robson recebeu há 31 dias
    perform pg_temp.enviada(c_cli_rob, c_rob, 'pos_servico', null, pg_temp.em('2026-10-02 09:31'));
    r := pg_temp.resp(c_f, 'PARAR', 'opt_out', null, pg_temp.em('2026-11-02 10:00'));
    r2 := pg_temp.resp('5547900000307', 'PARAR', 'opt_out', null, pg_temp.em('2026-11-02 10:00'));
    v_res := pg_temp.ok(v_res, 'C1b3 sem mensagem da agenda enviada nos últimos 30 dias o PARAR não é da agenda (o de hoje, manejarRespostaAutomatica, segue com o dele)',
      r ->> 'consumiu' = 'false' and r2 ->> 'consumiu' = 'false'
      and not (select coalesce(opt_out_whatsapp, false) from public.clients where id = c_cli_flav)
      and not (select coalesce(opt_out_whatsapp, false) from public.clients where id = c_cli_rob), r::text || ' ' || r2::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── C1c. O acesso com negação (item 16) ──
  begin
    perform pg_temp.ligar();
    v_id := pg_temp.enviada(c_cli_flav, c_flav, 'acesso', date '2026-11-03', pg_temp.em('2026-10-31 09:00'));
    v_t := (select coalesce(site_access, '') from public.service_orders where id = c_flav);
    r := pg_temp.resp(c_f, 'Não sei onde vai estar a chave ainda', 'acesso', null, pg_temp.em('2026-10-31 10:00'));
    v_res := pg_temp.ok(v_res, 'C1c1 (A7c) "não sei onde vai estar a chave" vai ao dono: o campo de acesso da OS e o acesso_ok_em não mudam',
      r ->> 'efeito' = 'ao_dono'
      and (select q.texto from public.agenda_perguntas q where q.id = (r ->> 'pergunta_id')::uuid)
          like '%: falou do acesso, mas ainda não sabe (ou não tem) a chave. Não respondi nada; é com você.'
      and (select coalesce(site_access, '') from public.service_orders where id = c_flav) = v_t
      and not exists (select 1 from public.os_planejamento p where p.service_order_id = c_flav and p.acesso_ok_em is not null),
      r::text);
    update public.agenda_cliente_mensagens set estado = 'enviada', resposta_id = null where id = v_id;
    r2 := pg_temp.resp(c_f, 'A chave fica com o marinheiro', 'acesso', null, pg_temp.em('2026-10-31 10:05'));
    v_res := pg_temp.ok(v_res, 'C1c2 o acesso afirmado continua anotado (anotou_acesso)', r2 ->> 'efeito' = 'anotou_acesso', r2::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── C1d. Falta/remarcar com o dia que o banco não entendeu (item 17) ──
  begin
    perform pg_temp.ligar();
    v_id := pg_temp.enviada(c_cli_flav, c_flav, 'confirmar', date '2026-11-03', pg_temp.em('2026-10-29 09:00'), 'primeira');
    r := pg_temp.resp(c_f, 'Tô viajando, volto dia 20', 'falta', null, pg_temp.em('2026-10-29 10:00'));
    v_res := pg_temp.ok(v_res, 'C1d1 (A6d) "tô viajando, volto dia 20" (falta sem o dia entendido, com um número de dia): vai ao dono, o plano não muda',
      r ->> 'efeito' = 'ao_dono'
      and (select q.texto from public.agenda_perguntas q where q.id = (r ->> 'pergunta_id')::uuid)
          like '%: falou de outro dia, que eu não entendi. Não respondi nada; é com você.'
      and pg_temp.plano(c_flav) = c_plano
      and not exists (select 1 from public.os_planejamento p where p.service_order_id = c_flav and p.bem_indisponivel <> '{}'::datemultirange),
      r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── C1e. O "dia N" sem mês e o teto do pedido (item 9; o x10 do revisor) ──
  x := (select jsonb_object_agg(e, public._agenda_cliente_data_da_resposta(e, date '2026-11-03', date '2026-11-04'))
          from unnest(array['dia 31', 'dia 30', 'dia 2', 'dia 3/12', 'dia 3', 'quarta 4', 'sexta', 'dia 31/11', 'amanhã']) e);
  v_res := pg_temp.ok(v_res, 'C1e1 (A5c) em ter 03/11: "dia 31" (novembro não tem) = não entendi; "dia 30" = 30/11; "dia 2" = 02/12 (o mês seguinte); "dia 3/12" como dito; "dia 3" = hoje; "quarta 4" = 04/11; o resto como antes',
    x -> 'dia 31' = 'null'::jsonb and x #>> '{dia 30,de}' = '2026-11-30' and x #>> '{dia 2,de}' = '2026-12-02'
    and x #>> '{dia 3/12,de}' = '2026-12-03' and x #>> '{dia 3,de}' = '2026-11-03' and x #>> '{quarta 4,de}' = '2026-11-04'
    and x #>> '{sexta,de}' = '2026-11-06' and x -> 'dia 31/11' = 'null'::jsonb and x #>> '{amanhã,de}' = '2026-11-04', x::text);
  v_res := pg_temp.ok(v_res, 'C1e2 em sáb 31/01/2027 "dia 30" cairia em fevereiro (não existe) = não entendi; "dia 31" = hoje',
    public._agenda_cliente_data_da_resposta('dia 30', date '2027-01-31', null) is null
    and public._agenda_cliente_data_da_resposta('dia 31', date '2027-01-31', null) ->> 'de' = '2027-01-31', null);
  begin
    perform pg_temp.ligar();
    v_id := pg_temp.enviada(c_cli_flav, c_flav, 'confirmar', date '2026-11-03', pg_temp.em('2026-10-31 09:00'), 'primeira');
    r := pg_temp.resp(c_f, 'Pode ser dia 31?', 'data', 'dia 31', pg_temp.em('2026-11-03 07:00'));
    update public.agenda_cliente_mensagens set estado = 'enviada', resposta_id = null where id = v_id;
    r2 := pg_temp.resp(c_f, 'Melhor dia 3/12', 'data', 'dia 3/12', pg_temp.em('2026-11-03 07:01'));
    update public.agenda_cliente_mensagens set estado = 'enviada', resposta_id = null where id = v_id;
    r3 := pg_temp.resp(c_f, 'Vou viajar até 20/12', 'falta', 'até 20/12', pg_temp.em('2026-11-03 07:02'));
    v_res := pg_temp.ok(v_res, 'C1e3 (A5c/A5d) "dia 31" em novembro vai ao dono (não entendi); "dia 3/12" e "vou viajar até 20/12" passam de cliente_pedido_max_du (10) dias úteis do combinado: ao dono, sem replano',
      r ->> 'efeito' = 'ao_dono' and r2 ->> 'efeito' = 'ao_dono' and r3 ->> 'efeito' = 'ao_dono'
      and (select q.texto from public.agenda_perguntas q where q.id = (r ->> 'pergunta_id')::uuid) like '%: não entendi o dia que ele pediu.%'
      and (select q.texto from public.agenda_perguntas q where q.id = (r2 ->> 'pergunta_id')::uuid)
          like '%: pediu qui 03/12, mais de 10 dias úteis depois do combinado: remarque você.%'
      and (select q.texto from public.agenda_perguntas q where q.id = (r3 ->> 'pergunta_id')::uuid)
          like '%: disse que não dá até dom 20/12, mais de 10 dias úteis depois do combinado: remarque você.%'
      and pg_temp.plano(c_flav) = c_plano
      and (select nao_antes_de is null and bem_indisponivel = '{}'::datemultirange from public.os_planejamento where service_order_id = c_flav),
      r::text || ' ' || r2::text || ' ' || r3::text);
    -- o parâmetro mexe na regra: com 25 dias úteis, o "dia 3/12" (21 dias úteis depois) remarca sozinho
    update public.agenda_config set cliente_pedido_max_du = 25 where id;
    update public.agenda_cliente_mensagens set estado = 'enviada', resposta_id = null where id = v_id;
    x := pg_temp.resp(c_f, 'Melhor dia 3/12', 'data', 'dia 3/12', pg_temp.em('2026-11-03 07:03'));
    v_res := pg_temp.ok(v_res, 'C1e4 o teto é o parâmetro (cliente_pedido_max_du = 25): o mesmo "dia 3/12" vira o pedido com o replano',
      x ->> 'efeito' = 'replanejou'
      and (select nao_antes_de = date '2026-12-03' from public.os_planejamento where service_order_id = c_flav), x::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── C1f. O botão pela interna, com a hora fixa (itens 5, 19 e 21; M1 e B1) ──
  begin
    -- (o x8 do revisor) a rodada de sex 30/10 17:00 registra a confirmação do Rodrigo esperando o dono (os 3 dias)
    perform pg_temp.ligar(null, 3);
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, occurred_at, delivery_status)
    values ('inbound', '5547900000211', 'text', 'Oi, tudo bem?', pg_temp.em('2026-10-20 10:00'), 'received');
    perform pg_temp.vig('2026-10-30 17:00');
    select m.id into v_id from public.agenda_cliente_mensagens m where m.service_order_id = c_rod and m.tipo = 'confirmar';
    r := pg_temp.botao(c_rod, '2026-10-30 17:30');
    v_res := pg_temp.ok(v_res, 'C1f1 (E9g) a confirmação da rodada esperando o dono: o clique a APROVA (a pergunta respondida pela tela) e diz quando sai; nada novo registrado',
      (r ->> 'aprovou')::boolean and r ->> 'message' = 'Mando ao Rodrigo amanhã às 09:00.' and (r ->> 'id')::uuid = v_id
      and (select m.aprovacao = 'aprovada' and m.aprovada_por = c_dono and m.estado = 'aguardando_dono'
             from public.agenda_cliente_mensagens m where m.id = v_id)
      and (select q.estado = 'respondida' and q.respondida_via = 'tela' and q.opcao_escolhida = 1
             from public.agenda_perguntas q join public.agenda_cliente_mensagens m on m.pergunta_id = q.id where m.id = v_id)
      and (select count(*) from public.agenda_cliente_mensagens m where m.service_order_id = c_rod) = 1,
      r::text);
    r2 := pg_temp.botao(c_rod, '2026-10-30 17:35');
    v_res := pg_temp.ok(v_res, 'C1f2 o clique de novo: a confirmação já vai sair sozinha (aviso neutro, nada muda)',
      (r2 ->> 'nada_feito')::boolean and r2 ->> 'message' = 'A confirmação de qua 04/11 para Rodrigo já vai sair sozinha: sai amanhã às 09:00.',
      r2::text);
    -- o dono segurou: o clique pede de novo, pelo botão (a 2ª chave); a de antes continua segurada
    update public.agenda_cliente_mensagens set estado = 'recusada', recusa_motivo = 'segurada', aprovacao = 'segurada',
                                           aprovada_em = coalesce(aprovada_em, pg_temp.em('2026-10-30 17:36'))
     where id = v_id;
    r3 := pg_temp.botao(c_rod, '2026-10-30 17:40');
    v_res := pg_temp.ok(v_res, 'C1f3 (E9g) com a da rodada segurada, o clique registra a 2ª pelo botão (agenda-cliente:confirmar:<os>:<dia>:botao), aprovada, na fila agora; a segurada não muda',
      r3 ->> 'message' = 'Pedido de confirmação na fila para Rodrigo. Quando ele responder SIM, a OS fica confirmada.'
      and (select m.dedupe_key = format('agenda-cliente:confirmar:%s:2026-11-04:botao', c_rod) and m.origem = 'botao'
                  and m.aprovacao = 'aprovada' and m.estado = 'enfileirada'
             from public.agenda_cliente_mensagens m where m.id = (r3 ->> 'id')::uuid)
      and (select m.estado = 'recusada' and m.recusa_motivo = 'segurada' from public.agenda_cliente_mensagens m where m.id = v_id),
      r3::text);
    -- a 2ª pelo botão sai; o clique depois diz quando saiu
    update public.whatsapp_send_queue set status = 'sent', sent_at = pg_temp.em('2026-10-30 17:40:20')
     where source = 'agenda-cliente' and source_ref_id = (r3 ->> 'id')::uuid;
    v_t := pg_temp.botao(c_rod, '2026-10-30 18:00') ->> 'message';
    v_res := pg_temp.ok(v_res, 'C1f4 a confirmação já mandada: o clique diz quando ("Já mandei …"), sem mandar de novo',
      v_t = 'Já mandei a confirmação de qua 04/11 para Rodrigo (sex 30/10 às 17:40).'
      and (select count(*) from public.whatsapp_send_queue q where q.source = 'agenda-cliente') = 1, v_t);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    -- a 2ª pelo botão recusada: o clique diz o porquê (não registra uma 3ª)
    perform pg_temp.ligar();
    insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, variante, origem, dia_alvo, modo, texto, enviar_em,
                                                 valida_ate, aprovacao, aprovada_em, estado, recusa_motivo, dedupe_key, criada_em)
    values (c_cli_flav, c_flav, 'confirmar', 'primeira', 'botao', date '2026-11-03', 'ligado', 'mensagem de teste (C1F5)',
            pg_temp.em('2026-10-30 09:00'), pg_temp.em('2026-10-30 19:00'), 'aprovada', pg_temp.em('2026-10-30 09:00'), 'recusada',
            'material', format('agenda-cliente:confirmar:%s:2026-11-03:botao', c_flav), pg_temp.em('2026-10-30 09:00'));
    v_e := pg_temp.botao_erro(c_flav, '2026-10-30 10:00');
    v_res := pg_temp.ok(v_res, 'C1f5 a 2ª pelo botão já recusada: o clique diz o porquê e não registra outra',
      v_e = 'P0001 A confirmação de ter 03/11 já foi pedida pelo botão e não saiu: o material ainda não está todo na mão, e a data não é firme. Confirme com Flávio por telefone.'
      and (select count(*) from public.agenda_cliente_mensagens m where m.service_order_id = c_flav) = 1, v_e);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    -- (E9h; o M1 da regressão) o Flávio sem conversa: o erro no clique, de dia (10:00) e de noite (20:00), nada gravado
    perform pg_temp.ligar();
    delete from public.whatsapp_messages where phone_normalized = c_f;
    v_e := pg_temp.botao_erro(c_flav, '2026-10-30 10:00');
    v_t := pg_temp.botao_erro(c_flav, '2026-10-30 20:00');
    v_res := pg_temp.ok(v_res, 'C1f6 (E9h) sem conversa, o clique dá o erro na hora — de dia e de noite (antes, à noite, respondia "sai amanhã" e de manhã a mensagem era recusada calada); nada gravado',
      v_e = 'P0001 Flávio não escreveu para a HBR nos últimos 365 dias: mensagem automática a quem não escreve arrisca o número. Confirme por telefone.'
      and v_t = v_e
      and not exists (select 1 from public.agenda_cliente_mensagens m where m.service_order_id = c_flav)
      and not exists (select 1 from public.whatsapp_send_queue q where q.source in ('agenda-cliente', 'agenda-confirmacao')),
      v_e || ' / ' || v_t);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    -- o teto do dia em que a mensagem sairia (o Flávio já recebeu uma hoje): o erro no clique, de noite também (o dia é o de amanhã)
    perform pg_temp.ligar();
    perform pg_temp.enviada(c_cli_flav, c_flav, 'acesso', date '2026-11-03', pg_temp.em('2026-10-30 09:00'));
    v_e := pg_temp.botao_erro(c_flav, '2026-10-30 10:00');
    perform pg_temp.enviada(c_cli_flav, c_flav, 'vespera', date '2026-11-03', pg_temp.em('2026-10-31 08:00'));
    v_t := pg_temp.botao_erro(c_flav, '2026-10-30 20:00');
    v_res := pg_temp.ok(v_res, 'C1f7 o teto do dia do envio vira o erro no clique: hoje (10:00) e amanhã cedo (o clique às 20:00, com a de sáb 08:00)',
      v_e = 'P0001 Flávio já recebeu as mensagens que cabem (no máximo 1 por dia e 3 por semana): confirme por telefone.'
      and v_t = v_e
      and not exists (select 1 from public.agenda_cliente_mensagens m where m.service_order_id = c_flav and m.tipo = 'confirmar'),
      v_e || ' / ' || v_t);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    -- (E9i; item 19) o caminho antigo — a mensagem ao cliente em teste, ou a confirmação fora das ondas — fora do horário
    update public.agenda_config set modo_cliente = 'sombra' where id;
    v_e := pg_temp.botao_erro(c_flav, '2026-10-30 20:00');
    v_t := pg_temp.botao_erro(c_flav, '2026-10-31 13:30');
    perform pg_temp.ligar(array['pronto']);
    v_n := (select count(*) from public.whatsapp_send_queue q where q.source = 'agenda-confirmacao');
    r := pg_temp.botao(c_flav, '2026-10-30 10:00');
    v_res := pg_temp.ok(v_res, 'C1f8 (E9i) o caminho antigo fora do horário recusa ("peça amanhã a partir das 08:00"; no sábado depois das 13:00, a terça depois de Finados); dentro, vai como antes (agenda-confirmacao)',
      v_e = 'P0001 Fora do horário de mensagens ao cliente: peça amanhã a partir das 08:00.'
      and v_t = 'P0001 Fora do horário de mensagens ao cliente: peça ter 03/11 a partir das 08:00.'
      and (r ->> 'ok')::boolean and r ->> 'agenda' is null
      and (select count(*) from public.whatsapp_send_queue q where q.source = 'agenda-confirmacao' and q.source_ref_id = c_flav) = 1
      and v_n = 0,
      v_e || ' / ' || v_t || ' / ' || r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    -- desligado (antes da Fase 5): como em 30/09, a qualquer hora
    update public.agenda_config set modo_cliente = 'desligado' where id;
    r := pg_temp.botao(c_flav, '2026-10-30 22:00');
    v_res := pg_temp.ok(v_res, 'C1f9 com modo_cliente desligado o botão faz o que fazia em 30/09 (vai à fila também à noite)',
      (r ->> 'ok')::boolean
      and exists (select 1 from public.whatsapp_send_queue q where q.source = 'agenda-confirmacao' and q.source_ref_id = c_flav),
      r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── C1g. O aviso de "não saiu" (item 5c / M1) ──
  begin
    -- o clique às 20:00 (dentro de tudo) registra para sáb 08:00; de manhã o Flávio já não "conversou" (a conversa apagada
    -- simula o ano que passou): o passo fila recusa — e o dono fica sabendo
    perform pg_temp.ligar();
    r := pg_temp.botao(c_flav, '2026-10-30 20:00');
    v_id := (r ->> 'id')::uuid;
    v_res := pg_temp.ok(v_res, 'C1g0 o clique fora do horário registra para a manhã seguinte e diz quando',
      r ->> 'message' like 'Pedido de confirmação a Flávio registrado: sai amanhã às 08:00% (fora do horário de mensagens agora).'
      and (select m.estado = 'registrada' and m.origem = 'botao' from public.agenda_cliente_mensagens m where m.id = v_id), r::text);
    delete from public.whatsapp_messages where phone_normalized = c_f;
    perform set_config('agenda_teste.hoje', '2026-10-31', true);
    perform public._agenda_cliente_fila(date '2026-10-31', pg_temp.em('2026-10-31 08:00'));
    v_res := pg_temp.ok(v_res, 'C1g1 a mensagem do botão recusada de manhã (sem_conversa) abre a pergunta "não saiu" ao dono (cliente_resposta:nao_saiu:<id>, 7 dias)',
      (select m.estado = 'recusada' and m.recusa_motivo = 'sem_conversa' from public.agenda_cliente_mensagens m where m.id = v_id)
      and (select q.tipo = 'cliente_resposta' and q.estado = 'aberta' and q.service_order_id = c_flav and q.dia = date '2026-11-03'
                  and q.texto = 'A confirmação de ter 03/11 que você pediu pelo botão para Flávio não saiu: o cliente não escreveu para a HBR nos últimos 365 dias, e mensagem automática a quem não escreve arrisca o número. Recomendo ligar.'
                  and q.expira_em - q.criada_em = interval '7 days'
             from public.agenda_perguntas q where q.chave = 'cliente_resposta:nao_saiu:' || v_id),
      (select string_agg(q.chave || ' ' || q.texto, ' | ') from public.agenda_perguntas q where q.chave like 'cliente_resposta:nao_saiu:%'));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    -- na saída (o worker grava a recusa pelo PostgREST, como recusarNaFila): também avisa
    perform pg_temp.ligar();
    r := pg_temp.botao(c_flav, '2026-10-30 10:00');
    v_id := (r ->> 'id')::uuid;
    update public.agenda_cliente_mensagens set estado = 'recusada', recusa_motivo = 'material' where id = v_id;
    v_res := pg_temp.ok(v_res, 'C1g2 a recusa na saída (o worker) também avisa, com o motivo dela',
      (select q.texto like '%não saiu: o material ainda não está todo na mão, e a data não é firme. Recomendo ligar.'
             from public.agenda_perguntas q where q.chave = 'cliente_resposta:nao_saiu:' || v_id), r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    -- não avisa: a segurada (o dono decidiu), a da rodada que ninguém aprovou e a recusa na hora da decisão
    perform pg_temp.ligar(null, 3);
    perform pg_temp.vig('2026-10-30 17:00');
    select m.id into v_id from public.agenda_cliente_mensagens m where m.service_order_id = c_rod and m.tipo = 'confirmar';
    -- o Rodrigo nunca escreveu: o *manda cliente* às 09:00 de sáb, na hora de sair, recusa — e diz no texto
    perform set_config('agenda_teste.hoje', '2026-10-31', true);
    r := public._agenda_cliente_decidir((select m.pergunta_id from public.agenda_cliente_mensagens m where m.id = v_id), 1::smallint,
                                        c_dono, 'whatsapp', 'manda cliente Rodrigo', pg_temp.em('2026-10-31 09:00'));
    v_id2 := pg_temp.enviada(c_cli_luc, c_luc, 'pronto', null, pg_temp.em('2026-10-30 16:00'));
    update public.agenda_cliente_mensagens set estado = 'recusada', recusa_motivo = 'janela', enviada_em = null where id = v_id2;
    v_res := pg_temp.ok(v_res, 'C1g3 a recusa na hora do *manda cliente* vai no texto da resposta, sem a pergunta "não saiu"; a da rodada não aprovada recusada também não abre',
      r ->> 'texto' like 'Não mandei ao Rodrigo: %'
      and (select m.estado = 'recusada' from public.agenda_cliente_mensagens m where m.id = v_id)
      and not exists (select 1 from public.agenda_perguntas q where q.chave like 'cliente_resposta:nao_saiu:%')
      and coalesce(current_setting('agenda.cliente_recusa_na_hora', true), '') = '', r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── C1h. O d10 na revalidação (item 13) ──
  begin
    perform pg_temp.ligar();
    perform set_config('agenda_teste.hoje', '2026-10-30', true);
    r := public._agenda_cliente_registrar('vespera', null, c_flav, date '2026-11-03', '{}'::jsonb, pg_temp.em('2026-10-30 10:00'),
                                          null, 'rodada', null, pg_temp.em('2026-10-30 10:00'));
    v_id := (r ->> 'id')::uuid;
    v_t := (select q.id::text from public.whatsapp_send_queue q where q.source = 'agenda-cliente' and q.source_ref_id = v_id);
    delete from public.whatsapp_messages where phone_normalized = c_f;
    x := public.agenda_cliente_pode_sair(v_t::uuid, pg_temp.em('2026-10-30 10:00:40'));
    v_res := pg_temp.ok(v_res, 'C1h1 (E6) sem conversa, a revalidação diz sem_conversa — e o pode_sair do worker também (antes só a 1ª trava olhava)',
      r ->> 'estado' = 'enfileirada'
      and public._agenda_cliente_revalidar(v_id, pg_temp.em('2026-10-30 10:00:40')) = 'sem_conversa'
      and x = '{"pode": false, "motivo": "sem_conversa"}'::jsonb, r::text || ' / ' || x::text);
    -- a nova tentativa (+5 min) que o worker marca: a trava da fila revalida e a mensagem fica recusada sem_conversa
    update public.whatsapp_send_queue set status = 'pending', scheduled_for = scheduled_for + interval '5 minutes', attempts = 1
     where id = v_t::uuid;
    v_res := pg_temp.ok(v_res, 'C1h2 (E6) a nova tentativa sem conversa: a linha falha e a mensagem fica recusada (sem_conversa)',
      (select q.status = 'failed' from public.whatsapp_send_queue q where q.id = v_t::uuid)
      and (select m.estado = 'recusada' and m.recusa_motivo = 'sem_conversa' from public.agenda_cliente_mensagens m where m.id = v_id),
      (select q.status || ' ' || coalesce(q.failed_reason, '') from public.whatsapp_send_queue q where q.id = v_t::uuid));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── C1i. O intervalo remarca a hora (item 14) ──
  begin
    perform pg_temp.ligar();
    perform set_config('agenda_teste.hoje', '2026-10-30', true);
    r := public._agenda_cliente_registrar('pos_servico', null, c_rob, null, '{}'::jsonb, pg_temp.em('2026-10-30 10:00'), null,
                                          'rodada', null, pg_temp.em('2026-10-30 10:00'));
    r2 := public._agenda_cliente_registrar('pronto', null, c_luc, null, '{}'::jsonb, pg_temp.em('2026-10-30 15:00'), null, 'rodada',
                                           null, pg_temp.em('2026-10-30 10:00'));
    v_id := (r2 ->> 'id')::uuid;
    -- a do Robson voltou (a nova tentativa) para perto da hora da Lucenira
    update public.agenda_cliente_mensagens set enviar_em = pg_temp.em('2026-10-30 10:00:10') where id = v_id;
    r3 := public._agenda_cliente_enfileirar(v_id, pg_temp.em('2026-10-30 10:00'));
    v_res := pg_temp.ok(v_res, 'C1i1 (E3m) o choque de intervalo remarca a hora (≥ 30 s depois da outra) e a mensagem fica registrada — não é recusada',
      r ->> 'estado' = 'enfileirada' and r3 ->> 'estado' = 'registrada' and r3 ->> 'motivo' = 'intervalo'
      and (r3 ->> 'enviar_em')::timestamptz >= (r ->> 'enviar_em')::timestamptz + interval '30 seconds'
      and (select m.estado = 'registrada' and m.enviar_em = (r3 ->> 'enviar_em')::timestamptz
             from public.agenda_cliente_mensagens m where m.id = v_id),
      r3::text);
    -- no tique seguinte, ela sai
    x := public._agenda_cliente_fila(date '2026-10-30', pg_temp.em('2026-10-30 10:01'));
    v_res := pg_temp.ok(v_res, 'C1i2 o passo fila seguinte a enfileira na hora nova',
      (select m.estado = 'enfileirada' from public.agenda_cliente_mensagens m where m.id = v_id), x::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.ligar();
    perform set_config('agenda_teste.hoje', '2026-10-30', true);
    r := public._agenda_cliente_registrar('pos_servico', null, c_rob, null, '{}'::jsonb, pg_temp.em('2026-10-30 18:59:40'), null,
                                          'rodada', null, pg_temp.em('2026-10-30 18:59:40'));
    r2 := public._agenda_cliente_registrar('pronto', null, c_luc, null, '{}'::jsonb, pg_temp.em('2026-10-30 18:50'),
                                           pg_temp.em('2026-10-30 19:00'), 'rodada', null, pg_temp.em('2026-10-30 18:00'));
    v_id := (r2 ->> 'id')::uuid;
    update public.agenda_cliente_mensagens set enviar_em = (r ->> 'enviar_em')::timestamptz + interval '5 seconds' where id = v_id;
    r3 := public._agenda_cliente_enfileirar(v_id, pg_temp.em('2026-10-30 18:59:40'));
    v_res := pg_temp.ok(v_res, 'C1i3 a hora nova que passaria da validade: vencida (não vai à manhã seguinte)',
      r3 = '{"estado": "recusada", "motivo": "vencida"}'::jsonb, r::text || ' / ' || r3::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── C1j. O M1 do dia que o botão antigo já pediu (item 20) ──
  begin
    perform pg_temp.ligar();
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, occurred_at, delivery_status)
    values ('inbound', '5547900000211', 'text', 'Oi, tudo bem?', pg_temp.em('2026-10-20 10:00'), 'received');
    perform pg_temp.vig('2026-10-30 17:00');
    v_n := (select count(*) from public.agenda_cliente_mensagens m where m.service_order_id = c_rod and m.tipo = 'confirmar');
    raise exception 'desfaz' using errcode = 'P0097';
  exception when sqlstate 'P0097' then null;
  end;
  begin
    perform pg_temp.ligar();
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, occurred_at, delivery_status)
    values ('inbound', '5547900000211', 'text', 'Oi, tudo bem?', pg_temp.em('2026-10-20 10:00'), 'received');
    -- o botão antigo pediu a confirmação de qua 04/11 hoje às 08:00 (em teste, antes da onda 2)
    perform set_config('agenda.porta', 'on', true);
    update public.service_orders set client_confirmation_requested_at = pg_temp.em('2026-10-30 08:00'),
                                     client_confirmed_at = null, client_confirmed_for = null
     where id = c_rod;
    perform set_config('agenda.porta', 'off', true);
    x := pg_temp.vig('2026-10-30 17:00');
    v_res := pg_temp.ok(v_res, 'C1j1 (R2e) o botão antigo já pediu a confirmação de qua 04/11 (dentro da validade): a rodada não registra o M1 desse dia (sem o pedido, registra)',
      v_n = 1
      and (public._agenda_cliente_dia_a_confirmar(c_rod, pg_temp.em('2026-10-30 17:00')) at time zone 'America/Sao_Paulo')::date = date '2026-11-04'
      and not exists (select 1 from public.agenda_cliente_mensagens m where m.service_order_id = c_rod and m.tipo = 'confirmar'),
      x -> 'contagens' ->> 'confirmar');
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.ligar();
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, occurred_at, delivery_status)
    values ('inbound', '5547900000211', 'text', 'Oi, tudo bem?', pg_temp.em('2026-10-20 10:00'), 'received');
    -- o cliente já confirmou qua 04/11 (pelo botão, dias atrás)
    perform set_config('agenda.porta', 'on', true);
    update public.service_orders set client_confirmation_requested_at = pg_temp.em('2026-10-20 08:00'),
                                     client_confirmed_at = pg_temp.em('2026-10-20 09:00'),
                                     client_confirmed_for = public._agenda_cliente_dia_a_confirmar(c_rod, pg_temp.em('2026-10-30 17:00'))
     where id = c_rod;
    perform set_config('agenda.porta', 'off', true);
    perform pg_temp.vig('2026-10-30 17:00');
    v_res := pg_temp.ok(v_res, 'C1j2 o cliente já confirmou qua 04/11: a rodada não pede de novo',
      not exists (select 1 from public.agenda_cliente_mensagens m where m.service_order_id = c_rod and m.tipo = 'confirmar'), null);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

    raise exception 'desfaz tudo' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$c1$;

-- ── C1z. As cópias e as portas ──────────────────────────────────────────────────────────────────────────
do $c1z$
declare
  v_env  text := coalesce(current_setting('agenda_teste.mig_envio_fase5', true), '');
  v_rod  text := coalesce(current_setting('agenda_teste.mig_rodada_fase5', true), '');
  v_resp text := coalesce(current_setting('agenda_teste.mig_respostas_fase5', true), '');
  -- _pedir_confirmacao: as 7 linhas do corpo que mudam fora dos blocos (de → para; o montador tem a mesma lista, mais o nome)
  v_troc constant text[][] := array[
    array['  v_hoje := public._hoje_brt();', '  v_hoje := (p_agora at time zone ''America/Sao_Paulo'')::date;'],
    array['  if v_os.scheduled_start_at < now() then', '  if v_os.scheduled_start_at < p_agora then'],
    array['               (v_os.scheduled_start_at at time zone ''America/Sao_Paulo'')::date, v_dados, now(), null, ''botao'', null, now(),',
          '               (v_os.scheduled_start_at at time zone ''America/Sao_Paulo'')::date, v_dados, p_agora, null, ''botao'', null, p_agora,'],
    array['                      v_quem, public._agenda_cliente_quando_texto((v_r ->> ''enviar_em'')::timestamptz, now()), v_quem)',
          '                      v_quem, public._agenda_cliente_quando_texto((v_r ->> ''enviar_em'')::timestamptz, p_agora), v_quem)'],
    array['        when (v_r ->> ''enviar_em'')::timestamptz <= now() + interval ''15 minutes''',
          '        when (v_r ->> ''enviar_em'')::timestamptz <= p_agora + interval ''15 minutes'''],
    array['                    public._agenda_cliente_quando_texto((v_r ->> ''enviar_em'')::timestamptz, now())) end);',
          '                    public._agenda_cliente_quando_texto((v_r ->> ''enviar_em'')::timestamptz, p_agora)) end);'],
    array['     set client_confirmation_requested_at = now(), client_confirmed_at = null, client_confirmed_for = null',
          '     set client_confirmation_requested_at = p_agora, client_confirmed_at = null, client_confirmed_for = null']];
  v_velho text[];
  v_novo text[];
  v_n int := 0;
  r record;
  i int;
  j int;
begin
  -- as portas das novas: ninguém de fora (nem o service_role); security definer com search_path fixo
  insert into _resultado
  select format('C1z0 %s: interna (sem anon, authenticated nem service_role), security definer, search_path fixo', f),
         not has_function_privilege('anon', to_regprocedure(f), 'execute')
         and not has_function_privilege('authenticated', to_regprocedure(f), 'execute')
         and not has_function_privilege('service_role', to_regprocedure(f), 'execute')
         and (select p.prosecdef and array_to_string(p.proconfig, ',') like '%search_path=%' from pg_proc p where p.oid = to_regprocedure(f)),
         null
    from unnest(array['public._agenda_cliente_motivo_texto(text)',
                      'public._agenda_cliente_outra_conversa(uuid[], text, timestamptz, timestamptz)',
                      'public._agenda_cliente_avisar_recusa()', 'public._pedir_confirmacao(uuid, uuid, timestamptz)']) f;
  insert into _resultado
  select 'C1z0 o botão continua para authenticated e service_role (nunca anon); a casca chama a interna com now()',
         has_function_privilege('authenticated', 'public.pedir_confirmacao_do_agendamento(uuid, uuid)', 'execute')
         and has_function_privilege('service_role', 'public.pedir_confirmacao_do_agendamento(uuid, uuid)', 'execute')
         and not has_function_privilege('anon', 'public.pedir_confirmacao_do_agendamento(uuid, uuid)', 'execute')
         and (select p.prosrc like '%return public._pedir_confirmacao(p_os, p_autor, now());%' from pg_proc p
               where p.oid = 'public.pedir_confirmacao_do_agendamento(uuid, uuid)'::regprocedure),
         null;
  insert into _resultado
  select 'C1z0 o gatilho do "não saiu" em agenda_cliente_mensagens: AFTER UPDATE OF estado, só a recusada aprovada (menos segurada) em ligado',
         exists (select 1 from pg_trigger t where t.tgrelid = 'public.agenda_cliente_mensagens'::regclass
                    and t.tgname = 'trg_agenda_cliente_recusada' and not t.tgisinternal
                    and pg_get_triggerdef(t.oid) like '%AFTER UPDATE OF estado%'
                    and pg_get_triggerdef(t.oid) like '%aprovada%' and pg_get_triggerdef(t.oid) like '%segurada%'),
         null;

  if v_env = '' or v_rod = '' or v_resp = '' then
    insert into _resultado values ('C1z as cópias', true, 'PULADO: sem agenda_teste.mig_*_fase5 (rode pela bancada)');
    return;
  end if;
  for r in
    select * from (values
      ('_agenda_cliente_revalidar', 'public._agenda_cliente_revalidar(uuid, timestamptz)', v_env),
      ('_agenda_cliente_enfileirar', 'public._agenda_cliente_enfileirar(uuid, timestamptz)', v_env),
      ('_agenda_cliente_confirmar', 'public._agenda_cliente_confirmar(date, timestamptz)', v_rod),
      ('_agenda_cliente_decidir', 'public._agenda_cliente_decidir(uuid, smallint, uuid, text, text, timestamptz)', v_rod),
      ('_agenda_cliente_data_da_resposta', 'public._agenda_cliente_data_da_resposta(text, date, date)', v_resp),
      ('agenda_resposta_do_cliente', 'public.agenda_resposta_do_cliente(text, text, uuid, text, text, text, timestamptz)', v_resp)
    ) t(nome, assinatura, mig)
  loop
    v_velho := string_to_array(pg_temp.corpo(r.mig, r.nome), E'\n');
    v_novo := pg_temp.sem_correcao((select p.prosrc from pg_proc p where p.oid = r.assinatura::regprocedure));
    insert into _resultado values (format('C1z1 a cópia de %s só acrescenta os blocos "-- CORREÇÃO FASE 5:" (× a migration da Fase 5)', r.nome),
      v_novo = v_velho and cardinality(v_velho) > 20
      and (select p.prosrc like '%-- CORREÇÃO FASE 5:%' from pg_proc p where p.oid = r.assinatura::regprocedure),
      format('linhas %s × %s', array_length(v_novo, 1), array_length(v_velho, 1)));
  end loop;
  -- _pedir_confirmacao: o corpo de pedir_confirmacao_do_agendamento (100200) com as 7 linhas do now()
  v_velho := string_to_array(pg_temp.corpo(v_env, 'pedir_confirmacao_do_agendamento'), E'\n');
  for i in 1 .. coalesce(array_length(v_velho, 1), 0) loop
    for j in 1 .. 7 loop
      if v_velho[i] = v_troc[j][1] then
        v_velho[i] := v_troc[j][2];
        v_n := v_n + 1;
      end if;
    end loop;
  end loop;
  v_novo := pg_temp.sem_correcao((select p.prosrc from pg_proc p where p.oid = 'public._pedir_confirmacao(uuid, uuid, timestamptz)'::regprocedure));
  insert into _resultado values ('C1z2 _pedir_confirmacao é o corpo de pedir_confirmacao_do_agendamento (20261028100200) com as 7 linhas do now() → p_agora e os blocos "-- CORREÇÃO FASE 5:"',
    v_n = 7 and v_novo = v_velho
    and (select p.prosrc !~ 'now\(\)' from pg_proc p where p.oid = 'public._pedir_confirmacao(uuid, uuid, timestamptz)'::regprocedure),
    format('trocas %s; linhas %s × %s', v_n, array_length(v_novo, 1), array_length(v_velho, 1)));
end
$c1z$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
