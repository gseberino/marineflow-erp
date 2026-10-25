-- Prova da rotina da equipe e da diária automática, Agenda de Produção Fase 3 (pacote P4; migration 20261026100300).
-- bancada: depende de 20261026100300
--
-- Sobre a carteira da Fase 3 (scripts/bancada-agenda/fixture-fase3.sql: qui 29/10/2026, a semana de 03 a 06/11 publicada
-- pela vigia; o Roberto — telefone sintético 5547900000001, na lista da rotina — no Vanderlei (OS-00069) de ter 03 a qui
-- 05/11 o dia todo e no Lenine (OS-00074) seg 09 (manhã) e ter 10/11; o João sem telefone e fora da lista, à tarde no
-- Flávio em ter 03/11; o dono abre e fecha; seg 02/11 é Finados):
--   L  a leitura da resposta sem IA, frase a frase (roda sempre)
--   A  a rotina e o envio: a ficha das 19:30 (sexta → terça, depois do feriado), nada às 19:29, nada duplicado, nada no
--      domingo, ninguém fora da lista; o 07:45 só sem o OK; o silêncio das 9h (indisponível, replano e acorde) e o falso
--      silêncio (presença, mensagem não entendida); o "como foi" que leva a ficha e as 19:30 caladas (teto 2 provado com o
--      3º forçado); a janela no envio e na trava da fila; a fila velha; sombra (fila vazia); wa_test_mode; desligado
--   B  a resposta: "ok" à ficha confirma sem responder; "não vou" remaneja e responde; "o que tem pra amanhã" sem valores;
--      o recibo mais novo fica com o "ok"; a mesma mensagem duas vezes; quem não é da equipe
--   C  a diária: o "ok" do "como foi" lança (ligada à OS, desfazível); "só de manhã" pergunta (crítica, 3 opções); o *dia
--      feito* lança a meia do João; o dono pula; turno igual só liga, sem OS pergunta de ligar, diferente pergunta e fica
--      igual byte a byte; meio dia em duas OS; acerto fechado; sombra; a decisão; *diária Roberto meia*/*não*; desfazer
--   D  a repescagem (a diária lançada 4 dias depois preenche o resultado)
--   E  a conclusão pelo técnico ("terminei" no último dia conclui; fora dele pergunta; proposta em sombra só registra) e a
--      OS concluída antes do fim do plano (a vigia seguinte tira os meios-dias futuros dela)
--   F  a intervenção do dono ("eu fui no Lenine" sem estar no plano)
--   G  a saúde (os zeros na fixture; a diária forçada sem confirmação e a fila forçada fora da janela aparecem)
--   H  o acorde avisa quem já recebeu a ficha
--   J  portas
--
-- Revisão da Fase 3 (C1): L ganhou o atraso, o meio período e o "não dá pra terminar" (item 2); A30–A31 o teto contado igual
-- e o 23514 que vira recusa (R5); B2b e B16–B19 a resposta direta (NOVO-agenda-28); B10–B11 o "amanhã não vou" ao "como
-- foi" (item 3); B12–B13 o atraso que não é falta (item 2); B14–B15 o "ok, só de manhã" (item 7).
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs --ate 20261026100300
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase3_equipe_diarias.sql
--   Sem a fixture (produção) os cenários saem PULADO e só L e J rodam. Os cenários mexem em linhas só dentro de
--   subtransações desfeitas na hora; termina em ROLLBACK.
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
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
create function pg_temp.modos(p_equipe text, p_diaria text) returns void language sql as $f$
  update public.agenda_config set modo_equipe = p_equipe, modo_diaria = p_diaria where id
$f$;
create function pg_temp.rodar(p_dia date, p_hora text) returns jsonb language sql as $f$
  select public.agenda_rotina_rodar(p_dia, pg_temp.em(p_dia, p_hora))
$f$;
create function pg_temp.resp(p_texto text, p_dia date, p_hora text, p_wa text default null) returns jsonb language sql as $f$
  select public.agenda_resposta_da_equipe('5547900000001', p_texto, coalesce(p_wa, md5(p_texto || p_dia || p_hora)),
                                          pg_temp.em(p_dia, p_hora))
$f$;
-- As mensagens do Roberto, em ordem.
create function pg_temp.msgs() returns jsonb language sql stable as $f$
  select coalesce(jsonb_agg(jsonb_build_object('tipo', m.tipo, 'dia', m.dia, 'estado', m.estado, 'modo', m.modo,
                                               'motivo', m.recusa_motivo, 'texto', m.texto, 'leva', m.leva_ficha_de)
                            order by m.enviar_em, m.criada_em, m.tipo), '[]'::jsonb)
    from public.agenda_equipe_mensagens m where m.payee_id = 'bb000000-0000-4000-8000-000000000002'
$f$;
create function pg_temp.n_fila() returns int language sql stable as $f$
  select count(*)::int from public.whatsapp_send_queue q where q.source = 'agenda-equipe'
$f$;
-- O turno de uma pessoa num dia (a linha inteira, para provar que não mudou).
create function pg_temp.turno(p_payee uuid, p_dia date) returns jsonb language sql stable as $f$
  select to_jsonb(ws) || jsonb_build_object('os', (select coalesce(jsonb_agg(wo.service_order_id order by wo.service_order_id), '[]')
                                                     from public.work_shift_os wo where wo.shift_id = ws.id))
    from public.work_shifts ws join public.work_profiles wp on wp.id = ws.work_profile_id
   where wp.payee_id = p_payee and ws.data = p_dia and ws.fracao is not null
$f$;

-- ── L. A leitura da resposta (roda sempre) ────────────────────────────────────────────────────────────────
insert into _resultado
select format('L %s → %s', x.frase, x.esperado),
       (select public._agenda_ler_resposta_da_equipe(x.frase) @> x.esperado::jsonb), public._agenda_ler_resposta_da_equipe(x.frase)::text
  from (values
    -- pergunta
    ('oque tem pra fazer amanhã', '{"tipo":"pergunta","dia":"amanha"}'),
    ('O que tem pra amanhã?', '{"tipo":"pergunta","dia":"amanha"}'),
    ('o q tem p amanha', '{"tipo":"nao_entendi"}'),
    ('amanhã tem oq', '{"tipo":"pergunta","dia":"amanha"}'),
    ('qual é pra hoje', '{"tipo":"pergunta","dia":"hoje"}'),
    ('onde é amanhã?', '{"tipo":"pergunta","dia":"amanha"}'),
    ('oq e pra fazer hoje', '{"tipo":"pergunta","dia":"hoje"}'),
    -- não vou
    ('hoje não vou conseguir, tô ruim', '{"tipo":"nao_vou"}'),
    ('nao vou', '{"tipo":"nao_vou"}'),
    ('amanhã não', '{"tipo":"nao_vou"}'),
    ('não posso ir', '{"tipo":"nao_vou"}'),
    ('to doente', '{"tipo":"nao_vou"}'),
    ('não vai dar hoje', '{"tipo":"nao_vou"}'),
    ('tô no hospital', '{"tipo":"nao_vou"}'),
    ('amanhã não vou, tô doente', '{"tipo":"nao_vou"}'),
    ('ok amanhã não vou', '{"tipo":"nao_vou"}'),
    -- (C1, item 2) hora, atraso, turno ou "ficar": não é falta do dia inteiro (vai ao dono, nada é remanejado)
    ('não consigo chegar às 8, chego às 9', '{"tipo":"nao_entendi"}'),
    ('vou atrasar, não consigo chegar 8h', '{"tipo":"nao_entendi"}'),
    ('não vou conseguir chegar cedo, chego 9h', '{"tipo":"nao_entendi"}'),
    ('não vou poder ficar a tarde', '{"tipo":"nao_entendi"}'),
    ('não posso amanhã à tarde', '{"tipo":"nao_entendi"}'),
    ('hoje não posso de manhã', '{"tipo":"nao_entendi"}'),
    ('não posso às 10, só depois', '{"tipo":"nao_entendi"}'),
    ('não vou conseguir, só depois do almoço', '{"tipo":"nao_entendi"}'),
    ('não dá pra terminar hoje', '{"tipo":"turnos","terminou":false}'),
    ('não vou conseguir terminar hoje', '{"tipo":"turnos","terminou":false}'),
    -- presença
    ('bom dia to na MP', '{"tipo":"presenca"}'),
    ('cheguei', '{"tipo":"presenca"}'),
    ('já tô aqui', '{"tipo":"presenca"}'),
    ('tô chegando', '{"tipo":"presenca"}'),
    ('ja estou na marina', '{"tipo":"presenca"}'),
    -- turnos e terminou
    ('foi o dia todo, terminei', '{"tipo":"turnos","turnos":["manha","tarde"],"terminou":true}'),
    ('manhã e tarde', '{"tipo":"turnos","turnos":["manha","tarde"]}'),
    ('fiquei só de manhã', '{"tipo":"turnos","turnos":["manha"]}'),
    ('só de manhã, falta passar os cabos', '{"tipo":"turnos","turnos":["manha"],"terminou":false}'),
    ('so manha', '{"tipo":"turnos","turnos":["manha"]}'),
    ('fui até o meio dia', '{"tipo":"turnos","turnos":["manha"]}'),
    ('só à tarde', '{"tipo":"turnos","turnos":["tarde"]}'),
    ('so de tarde', '{"tipo":"turnos","turnos":["tarde"]}'),
    ('não fui', '{"tipo":"turnos","turnos":[]}'),
    ('faltei hoje', '{"tipo":"turnos","turnos":[]}'),
    ('fiz meio dia', '{"tipo":"turnos","turnos":["meio"]}'),
    ('ok, terminei', '{"tipo":"turnos","turnos":null,"terminou":true,"ok":true}'),
    ('terminei', '{"tipo":"turnos","turnos":null,"terminou":true,"ok":false}'),
    ('acabou o serviço', '{"tipo":"turnos","terminou":true}'),
    ('não terminei', '{"tipo":"turnos","terminou":false}'),
    ('ainda não acabou', '{"tipo":"turnos","terminou":false}'),
    ('amanhã termino', '{"tipo":"turnos","terminou":false}'),
    ('ficou pronto', '{"tipo":"turnos","terminou":true}'),
    ('ok mas nao terminei', '{"tipo":"turnos","terminou":false,"ok":true}'),
    ('só de manhã... não, o dia todo', '{"tipo":"nao_entendi"}'),
    -- ok
    ('ok', '{"tipo":"ok","ok":true}'),
    ('OK!', '{"tipo":"ok"}'),
    ('beleza', '{"tipo":"ok"}'),
    ('👍', '{"tipo":"ok"}'),
    ('blz, combinado', '{"tipo":"ok"}'),
    ('tudo certo', '{"tipo":"ok"}'),
    ('sim', '{"tipo":"ok"}'),
    ('foi tudo como o previsto', '{"tipo":"ok"}'),
    -- não entendi
    ('deu ruim no inversor', '{"tipo":"nao_entendi"}'),
    ('', '{"tipo":"nao_entendi"}'),
    ('manda o pix', '{"tipo":"nao_entendi"}')
  ) as x(frase, esperado);

-- ── A, B, C, D, E, F, G, H: os cenários sobre a carteira da Fase 3 (só na bancada) ──────────────────────────
do $eq$
declare
  v_res     jsonb := '[]'::jsonb;
  r         jsonb;
  r2        jsonb;
  v_txt     text;
  v_m       jsonb;
  v_t       jsonb;
  v_id      uuid;
  v_n       int;
  c_admin   constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_gustavo constant uuid := 'bb000000-0000-4000-8000-000000000001';
  c_roberto constant uuid := 'bb000000-0000-4000-8000-000000000002';
  c_joao    constant uuid := 'bb000000-0000-4000-8000-000000000003';
  c_perfil_roberto constant uuid := 'cc000000-0000-4000-8000-000000000002';
  c_lenine  constant uuid := '05000000-0000-4000-8000-000000000074';
  c_vand    constant uuid := '05000000-0000-4000-8000-000000000069';
  c_flavio  constant uuid := '05000000-0000-4000-8000-000000000104';
  d30 constant date := date '2026-10-30';
  d31 constant date := date '2026-10-31';
  d01 constant date := date '2026-11-01';
  d02 constant date := date '2026-11-02';
  d03 constant date := date '2026-11-03';
  d04 constant date := date '2026-11-04';
  d05 constant date := date '2026-11-05';
  d08 constant date := date '2026-11-08';
  c_ficha03 constant text :=
    'Roberto, terça (03/11): 8h no barco do Vanderlei, com o Gustavo. Serviço: instalação de carregador DC-DC e proteções. Responde OK se tá certo.';
  c_como_foi constant text := 'Como foi hoje? Ficou manhã e tarde? Terminou o previsto? Se foi tudo como o previsto, responde OK.';
begin
  if coalesce(current_setting('agenda_teste.fase3', true), '') = '' then
    insert into _resultado values ('A0 os cenários (fixture-fase3)', true, 'PULADO: sem agenda_teste.fase3 (rode pela bancada)');
    return;
  end if;
  execute current_setting('agenda_teste.fase3');
  -- O registrar_diaria (a decisão do dono e a correção pela palavra) recusa "dia no futuro" pelo relógio de verdade
  -- (_hoje_brt): aqui o "hoje" do teste vale também para ele. Dentro da transação: o ROLLBACK do fim desfaz.
  create or replace function public._hoje_brt() returns date language sql stable set search_path to 'public' as $h$
    select coalesce(nullif(current_setting('agenda_teste.hoje', true), '')::date, (now() at time zone 'America/Sao_Paulo')::date)
  $h$;
  perform set_config('agenda_teste.hoje', '2026-11-08', true);

  -- ── A. A rotina e o envio ──────────────────────────────────────────────────────────────────────────────
  -- A1–A4: sexta 30/10, véspera do fim de semana com o feriado de segunda: a ficha é a de terça.
  begin
    perform pg_temp.modos('ligado', 'ligado');
    r := pg_temp.rodar(d30, '19:29');
    v_res := pg_temp.ok(v_res, 'A1 sex 30/10 19:29: nada à equipe (antes da hora da ficha)',
      (r ->> 'rodou')::boolean and jsonb_array_length(pg_temp.msgs()) = 0 and pg_temp.n_fila() = 0, r::text);
    r := pg_temp.rodar(d30, '19:30');
    v_m := pg_temp.msgs();
    v_res := pg_temp.ok(v_res, 'A2 sex 30/10 19:30: 1 ficha do Roberto, a de ter 03/11 ("terça (03/11)", depois de Finados), sem "R$" nem "OS-"',
      jsonb_array_length(v_m) = 1 and v_m -> 0 ->> 'tipo' = 'ficha' and v_m -> 0 ->> 'dia' = '2026-11-03'
      and v_m -> 0 ->> 'estado' = 'enfileirada' and v_m -> 0 ->> 'texto' = c_ficha03
      and position('R$' in v_m -> 0 ->> 'texto') = 0 and position('OS-' in v_m -> 0 ->> 'texto') = 0, v_m::text);
    v_res := pg_temp.ok(v_res, 'A3 a fila de sempre: source agenda-equipe, o telefone dele, 19:30, 3 tentativas (a última às 19:40), a chave sem ":sombra"',
      (select count(*) = 1 and bool_and(q.phone_normalized = '5547900000001' and q.scheduled_for = pg_temp.em(d30, '19:30')
                                          and q.max_attempts = 3 and q.status = 'pending'
                                          and q.dedupe_key = format('agenda-equipe:ficha:%s:2026-11-03', c_roberto)
                                          and q.message = c_ficha03)
         from public.whatsapp_send_queue q where q.source = 'agenda-equipe'),
      (select jsonb_agg(to_jsonb(q) - 'id')::text from public.whatsapp_send_queue q where q.source = 'agenda-equipe'));
    -- o worker manda (na bancada ninguém manda: a linha da fila é marcada como enviada)
    update public.whatsapp_send_queue set status = 'sent', sent_at = pg_temp.em(d30, '19:31') where source = 'agenda-equipe';
    r := pg_temp.rodar(d30, '19:45');
    v_res := pg_temp.ok(v_res, 'A4 o tique seguinte (19:45) não duplica; o João (sem telefone, fora da lista) não recebe nada',
      jsonb_array_length(pg_temp.msgs()) = 1 and pg_temp.n_fila() = 1
      and not exists (select 1 from public.agenda_equipe_mensagens m where m.payee_id = c_joao), pg_temp.msgs()::text);
    -- A6: o "ok" à ficha confirma terça, sem resposta; às 07:45 de terça nada sai
    r := pg_temp.resp('ok', d30, '20:10');
    v_res := pg_temp.ok(v_res, 'A6 "ok" à ficha: consumiu, terça confirmada (diarista), a ficha respondida, nenhuma resposta',
      (r ->> 'consumiu')::boolean and r ->> 'resposta' is null
      and exists (select 1 from public.agenda_disponibilidade d where d.payee_id = c_roberto and d.situacao = 'confirmada'
                                                              and d.origem = 'diarista' and d.periodo @> d03 and d.substituida_em is null)
      and pg_temp.msgs() -> 0 ->> 'estado' = 'respondida'
      and not exists (select 1 from public.agenda_equipe_mensagens m where m.tipo = 'resposta'), r::text);
    r := pg_temp.rodar(d01, '19:30');
    r2 := pg_temp.rodar(d01, '08:00');
    v_res := pg_temp.ok(v_res, 'A5 dom 01/11 (19:30 e 08:00): nada à equipe',
      jsonb_array_length(pg_temp.msgs()) = 1 and pg_temp.n_fila() = 1, pg_temp.msgs()::text);
    r := pg_temp.rodar(d03, '07:45');
    v_res := pg_temp.ok(v_res, 'A7 ter 03/11 07:45 com o OK da véspera: nenhuma confirmação',
      not exists (select 1 from public.agenda_equipe_mensagens m where m.tipo = 'confirmar'), pg_temp.msgs()::text);
    -- A8: 17:00 o "como foi" (sem a confirmação de manhã: não leva a ficha); 19:30 a ficha de quarta; 2 no dia
    r := pg_temp.rodar(d03, '17:00');
    r := pg_temp.rodar(d03, '19:30');
    v_m := pg_temp.msgs();
    v_res := pg_temp.ok(v_res, 'A8 ter 03/11: o "como foi hoje?" às 17:00 (sem levar a ficha) e a ficha de qua 04/11 às 19:30: 2 no dia',
      (select count(*) from jsonb_array_elements(v_m) e where e ->> 'tipo' = 'como_foi' and e ->> 'dia' = '2026-11-03'
                                                         and e ->> 'texto' = c_como_foi and e ->> 'leva' is null
                                                         and e ->> 'estado' = 'enfileirada') = 1
      and (select count(*) from jsonb_array_elements(v_m) e where e ->> 'tipo' = 'ficha' and e ->> 'dia' = '2026-11-04'
                                                         and e ->> 'estado' = 'enfileirada'
                                                         and e ->> 'texto' like 'Roberto, amanhã (qua 04/11): 8h no barco do Vanderlei%') = 1,
      v_m::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A9–A12: sem o OK da véspera, a confirmação das 07:45; o "como foi" leva a ficha e as 19:30 ficam caladas; o teto.
  begin
    perform pg_temp.modos('ligado', 'ligado');
    r := pg_temp.rodar(d30, '19:30');
    r := pg_temp.rodar(d03, '07:44');
    v_res := pg_temp.ok(v_res, 'A9 ter 03/11 07:44: nada (antes da hora da confirmação)',
      not exists (select 1 from public.agenda_equipe_mensagens m where m.tipo = 'confirmar'), pg_temp.msgs()::text);
    r := pg_temp.rodar(d03, '07:45');
    v_res := pg_temp.ok(v_res, 'A10 ter 03/11 07:45 sem o OK: "Bom dia, Roberto. Hoje é Vanderlei às 8h. Tá confirmado?"',
      exists (select 1 from public.agenda_equipe_mensagens m
               where m.tipo = 'confirmar' and m.dia = d03 and m.estado = 'enfileirada'
                 and m.texto = 'Bom dia, Roberto. Hoje é Vanderlei às 8h. Tá confirmado?'), pg_temp.msgs()::text);
    r := pg_temp.resp('cheguei', d03, '08:05');
    perform pg_temp.rodar(d03, '17:00');
    perform pg_temp.rodar(d03, '19:30');
    v_m := pg_temp.msgs();
    v_res := pg_temp.ok(v_res, 'A11 dia com a confirmação de manhã: às 17:00 o "como foi" leva a ficha de qua 04/11; às 19:30 nada (2 no dia)',
      (select count(*) from jsonb_array_elements(v_m) e
        where e ->> 'tipo' = 'como_foi' and e ->> 'leva' = '2026-11-04'
          and e ->> 'texto' = c_como_foi || ' Amanhã (qua 04/11): 8h no barco do Vanderlei.') = 1
      and not exists (select 1 from jsonb_array_elements(v_m) e where e ->> 'tipo' = 'ficha' and e ->> 'dia' = '2026-11-04')
      and (select count(*) from public.agenda_equipe_mensagens m
            where m.tipo <> 'resposta' and (m.enviar_em at time zone 'America/Sao_Paulo')::date = d03
              and m.estado in ('enfileirada', 'respondida', 'sem_resposta')) = 2, v_m::text);
    -- o 3º horário forçado no mesmo dia (uma ficha à mão às 18:00): recusada pelo teto; e a fila recusa direto
    r := public._agenda_equipe_registrar(c_roberto, d05, 'ficha', 'Roberto, quinta (05/11): teste do teto.', pg_temp.em(d03, '18:00'));
    v_res := pg_temp.ok(v_res, 'A12 o 3º no dia (forçado às 18:00): recusada/teto, nada na fila',
      r ->> 'estado' = 'recusada' and r ->> 'motivo' = 'teto'
      and not exists (select 1 from public.whatsapp_send_queue q where q.source_ref_id = (r ->> 'id')::uuid), r::text);
    v_id := (r ->> 'id')::uuid;
    v_txt := pg_temp.erro_de(format($q$insert into public.whatsapp_send_queue (phone_normalized, message, source, source_ref_id,
                                                                              scheduled_for, max_attempts, dedupe_key)
                                       values ('5547900000001', 'teste', 'agenda-equipe', %L, %L, 1, 'teste-teto')$q$,
                                    v_id, pg_temp.em(d03, '18:00')));
    v_res := pg_temp.ok(v_res, 'A13 a trava da fila recusa o 3º no dia mesmo direto no INSERT (23514)',
      v_txt like '23514 Teto de mensagens à equipe no dia (2)%', v_txt);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A14–A17: a janela (no envio e na fila), a fila velha e a nova tentativa fora da janela.
  begin
    perform pg_temp.modos('ligado', 'ligado');
    r := public._agenda_equipe_registrar(c_roberto, d04, 'ficha', 'Roberto, amanhã: teste da janela.', pg_temp.em(d03, '20:10'));
    v_res := pg_temp.ok(v_res, 'A14 enviar_em 20:10: recusada/janela, nada na fila',
      r ->> 'estado' = 'recusada' and r ->> 'motivo' = 'janela' and pg_temp.n_fila() = 0, r::text);
    r := public._agenda_equipe_registrar(c_roberto, d04, 'confirmar', 'Bom dia, teste da janela.', pg_temp.em(d04, '07:20'));
    v_res := pg_temp.ok(v_res, 'A15 enviar_em 07:20 (antes das 07:30): recusada/janela',
      r ->> 'estado' = 'recusada' and r ->> 'motivo' = 'janela' and pg_temp.n_fila() = 0, r::text);
    v_id := (r ->> 'id')::uuid;
    v_txt := pg_temp.erro_de(format($q$insert into public.whatsapp_send_queue (phone_normalized, message, source, source_ref_id,
                                                                              scheduled_for, max_attempts, dedupe_key)
                                       values ('5547900000001', 'teste', 'agenda-equipe', %L, %L, 1, 'teste-meia-noite')$q$,
                                    v_id, pg_temp.em(d04, '00:00')));
    r2 := jsonb_build_object('meia_noite', v_txt);
    v_txt := pg_temp.erro_de(format($q$insert into public.whatsapp_send_queue (phone_normalized, message, source, source_ref_id,
                                                                              scheduled_for, max_attempts, dedupe_key)
                                       values ('5547900000001', 'teste', 'agenda-equipe', %L, %L, 3, 'teste-ultima')$q$,
                                    v_id, pg_temp.em(d04, '19:55')));
    r2 := r2 || jsonb_build_object('ultima_20_05', v_txt);
    v_txt := pg_temp.erro_de($q$insert into public.whatsapp_send_queue (phone_normalized, message, source, scheduled_for, dedupe_key)
                                values ('5547900000001', 'teste', 'agenda-equipe', now(), 'teste-sem-mensagem')$q$);
    r2 := r2 || jsonb_build_object('sem_mensagem', v_txt);
    v_res := pg_temp.ok(v_res, 'A16 a trava da fila: meia-noite, a última tentativa às 20:05 e a linha sem mensagem da agenda são recusadas no INSERT',
      r2 ->> 'meia_noite' like '23514 Mensagem à equipe fora da janela%' and r2 ->> 'ultima_20_05' like '23514 Mensagem à equipe fora da janela%'
      and r2 ->> 'sem_mensagem' like '42501 A fila da equipe só aceita%', r2::text);
    -- a fila velha: a ficha das 19:30 que o worker não mandou até as 20:05 vira falha (não sai às 22:00)
    r := pg_temp.rodar(d30, '19:30');
    v_id := (select q.id from public.whatsapp_send_queue q where q.source = 'agenda-equipe');
    r := pg_temp.rodar(d30, '20:05');
    v_res := pg_temp.ok(v_res, 'A17 fila velha: a ficha que não saiu até o fim da janela vira falha às 20:05 e a mensagem fica recusada/janela',
      (select q.status = 'failed' from public.whatsapp_send_queue q where q.id = v_id)
      and (select m.estado = 'recusada' and m.recusa_motivo = 'janela' from public.agenda_equipe_mensagens m where m.fila_id = v_id)
      and (r #>> '{contagens,fila,canceladas}')::int = 1, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  begin
    -- o dono desliga a equipe (volta à sombra, ou desliga tudo) com a ficha ainda na fila: ela não sai mais
    perform pg_temp.modos('ligado', 'ligado');
    r := pg_temp.rodar(d30, '19:30');
    v_id := (select q.id from public.whatsapp_send_queue q where q.source = 'agenda-equipe');
    perform pg_temp.modos('desligado', 'desligado');
    r := pg_temp.rodar(d30, '19:40');
    v_res := pg_temp.ok(v_res, 'A17b a equipe desligada com a ficha na fila: a linha vira falha e a mensagem fica recusada/modo (nada sai)',
      not (r ->> 'rodou')::boolean
      and (select q.status = 'failed' from public.whatsapp_send_queue q where q.id = v_id)
      and (select m.estado = 'recusada' and m.recusa_motivo = 'modo' from public.agenda_equipe_mensagens m where m.fila_id = v_id),
      r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  begin
    perform pg_temp.modos('ligado', 'ligado');
    r := pg_temp.rodar(d30, '19:30');
    v_id := (select q.id from public.whatsapp_send_queue q where q.source = 'agenda-equipe');
    -- o worker marca a nova tentativa para daqui a 5 min; às 19:58 + 5 = 20:03 passaria da janela
    update public.whatsapp_send_queue set scheduled_for = pg_temp.em(d30, '20:03'), attempts = 1 where id = v_id;
    v_res := pg_temp.ok(v_res, 'A18 a nova tentativa que cairia às 20:03 vira falha (o gatilho da fila)',
      (select q.status = 'failed' and q.failed_reason like 'agenda-equipe:%' from public.whatsapp_send_queue q where q.id = v_id),
      (select to_jsonb(q)::text from public.whatsapp_send_queue q where q.id = v_id));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A19–A21: sombra, o modo de teste do WhatsApp, a lista e desligado.
  begin
    perform pg_temp.modos('sombra', 'sombra');
    r := pg_temp.rodar(d30, '19:30');
    v_m := pg_temp.msgs();
    v_res := pg_temp.ok(v_res, 'A19 sombra: a ficha fica registrada (chave com ":sombra") e a fila não recebe nada',
      jsonb_array_length(v_m) = 1 and v_m -> 0 ->> 'estado' = 'registrada' and v_m -> 0 ->> 'modo' = 'sombra'
      and pg_temp.n_fila() = 0
      and exists (select 1 from public.agenda_equipe_mensagens m where m.dedupe_key like '%:sombra'), v_m::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modos('ligado', 'ligado');
    insert into public.app_settings (key, value) values ('wa_test_mode', 'true'), ('wa_test_number', '5547911112222')
      on conflict (key) do update set value = excluded.value;
    r := pg_temp.rodar(d30, '19:30');
    v_res := pg_temp.ok(v_res, 'A20 wa_test_mode ligado: a ficha vai para o número de teste',
      (select q.phone_normalized from public.whatsapp_send_queue q where q.source = 'agenda-equipe') = '5547911112222',
      (select q.phone_normalized from public.whatsapp_send_queue q where q.source = 'agenda-equipe'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modos('ligado', 'ligado');
    insert into public.app_settings (key, value) values ('wa_test_mode', 'true') on conflict (key) do update set value = 'true';
    delete from public.app_settings where key = 'wa_test_number';
    r := pg_temp.rodar(d30, '19:30');
    v_m := pg_temp.msgs();
    v_res := pg_temp.ok(v_res, 'A21 wa_test_mode sem número de teste: nada sai (recusada/sem_telefone)',
      v_m -> 0 ->> 'estado' = 'recusada' and v_m -> 0 ->> 'motivo' = 'sem_telefone' and pg_temp.n_fila() = 0, v_m::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modos('ligado', 'ligado');
    update public.agenda_equipe_contato set recebe_rotina = false, parou_em = pg_temp.em(d30, '10:00'), parou_motivo = 'pediu para parar'
     where payee_id = c_roberto;
    r := pg_temp.rodar(d30, '19:30');
    v_res := pg_temp.ok(v_res, 'A22 quem parou (fora da lista): nenhuma mensagem',
      jsonb_array_length(pg_temp.msgs()) = 0 and pg_temp.n_fila() = 0, pg_temp.msgs()::text);
    perform pg_temp.modos('desligado', 'desligado');
    v_n := (select count(*) from public.agenda_vigia_rodadas x where x.rotina = 'rotina');
    r := pg_temp.rodar(d30, '19:45');
    v_res := pg_temp.ok(v_res, 'A23 equipe e diária desligadas: {rodou: false}, nada gravado (nem a rodada)',
      not (r ->> 'rodou')::boolean and (select count(*) from public.agenda_vigia_rodadas x where x.rotina = 'rotina') = v_n
      and jsonb_array_length(pg_temp.msgs()) = 0, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A24–A26: o silêncio das 9h e o falso silêncio.
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.rodar(d03, '07:45');
    update public.whatsapp_send_queue set status = 'sent', sent_at = pg_temp.em(d03, '07:46') where source = 'agenda-equipe';
    r := pg_temp.rodar(d03, '09:00');
    v_res := pg_temp.ok(v_res, 'A24 09:00 sem resposta: indisponível hoje (agente), a ação equipe, o replano tira o Roberto de hoje e o acorde ao dono',
      exists (select 1 from public.agenda_disponibilidade d where d.payee_id = c_roberto and d.situacao = 'indisponivel'
                                                            and d.origem = 'agente' and d.periodo @> d03 and d.substituida_em is null
                                                            and d.nota = 'Sem resposta à confirmação até 09:00')
      and exists (select 1 from public.agenda_acoes a where a.tipo = 'equipe' and a.payee_id = c_roberto and a.executada
                                                    and a.depois ->> 'motivo' = 'silencio')
      and not exists (select 1 from public.agenda_alocacoes a where a.payee_id = c_roberto and a.dia = d03
                                                              and a.estado in ('publicada', 'fixada'))
      and (select m.estado from public.agenda_equipe_mensagens m where m.tipo = 'confirmar') = 'sem_resposta'
      and jsonb_array_length(r -> 'acordes') = 1
      and r -> 'acordes' -> 0 ->> 'texto' like 'O Roberto não respondeu à confirmação de hoje até as 9h. Mudei a agenda de hoje:%',
      r::text);
    -- desfazer o replano tira a ausência (senão a vigia replanejaria de novo)
    r2 := public.agenda_desfazer((r -> 'acordes' -> 0 ->> 'acao_id')::uuid, c_admin, 'dono', d03, pg_temp.em(d03, '09:20'));
    v_res := pg_temp.ok(v_res, 'A25 *desfaz* do replano do silêncio: o Roberto volta ao plano de hoje e a ausência sai',
      (r2 ->> 'ok')::boolean
      and exists (select 1 from public.agenda_alocacoes a where a.payee_id = c_roberto and a.dia = d03 and a.estado in ('publicada', 'fixada'))
      and not exists (select 1 from public.agenda_disponibilidade d where d.payee_id = c_roberto and d.situacao = 'indisponivel'
                                                                and d.periodo @> d03 and d.substituida_em is null), r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.rodar(d03, '07:45');
    update public.whatsapp_send_queue set status = 'sent', sent_at = pg_temp.em(d03, '07:46') where source = 'agenda-equipe';
    r2 := pg_temp.resp('bom dia, cheguei', d03, '08:05');
    r := pg_temp.rodar(d03, '09:00');
    v_res := pg_temp.ok(v_res, 'A26 09:00 depois de "cheguei": nada (presença é confirmação)',
      (r2 ->> 'consumiu')::boolean and (r #>> '{contagens,silencio,silencio}')::int = 0
      and not exists (select 1 from public.agenda_disponibilidade d where d.payee_id = c_roberto and d.situacao = 'indisponivel'),
      r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.rodar(d03, '07:45');
    update public.whatsapp_send_queue set status = 'sent', sent_at = pg_temp.em(d03, '07:46') where source = 'agenda-equipe';
    r2 := pg_temp.resp('deu ruim no inversor', d03, '08:10');
    r := pg_temp.rodar(d03, '09:00');
    v_res := pg_temp.ok(v_res, 'A27 09:00 depois de "deu ruim no inversor": nada muda; vira a pergunta ao dono com o trecho',
      (r2 ->> 'consumiu')::boolean and (r #>> '{contagens,silencio,silencio}')::int = 0
      and not exists (select 1 from public.agenda_disponibilidade d where d.payee_id = c_roberto and d.situacao = 'indisponivel')
      and exists (select 1 from public.agenda_perguntas q where q.tipo = 'equipe_resposta' and q.estado = 'aberta'
                                                        and q.texto = 'O Roberto respondeu "deu ruim no inversor" à confirmação de ter 03/11.'),
      (select string_agg(q.texto, ' | ') from public.agenda_perguntas q where q.tipo = 'equipe_resposta'));
    -- e a mensagem que o webhook não leu (só ficou em whatsapp_messages) também não é silêncio
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.rodar(d03, '07:45');
    update public.whatsapp_send_queue set status = 'sent', sent_at = pg_temp.em(d03, '07:46') where source = 'agenda-equipe';
    insert into public.whatsapp_messages (direction, phone_normalized, body, created_at)
    values ('inbound', '5547900000001', 'tô indo', pg_temp.em(d03, '08:30'));
    r := pg_temp.rodar(d03, '09:00');
    v_res := pg_temp.ok(v_res, 'A28 09:00 com uma mensagem dele que a agenda não leu (só em whatsapp_messages): não é silêncio',
      (r #>> '{contagens,silencio,silencio}')::int = 0
      and not exists (select 1 from public.agenda_disponibilidade d where d.payee_id = c_roberto and d.situacao = 'indisponivel'),
      r::text);
    -- e a confirmação que não saiu (a fila ainda pending) também não
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.rodar(d03, '07:45');
    r := pg_temp.rodar(d03, '09:00');
    v_res := pg_temp.ok(v_res, 'A29 09:00 com a confirmação ainda na fila (não saiu): não é silêncio',
      (r #>> '{contagens,silencio,silencio}')::int = 0, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A30–A31 (revisão C1, R5): o teto contado igual na função e na trava da fila; o 23514 da trava vira a recusa.
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.rodar(d30, '19:30');
    -- a ficha das 19:30 entrou na fila e falhou (o worker parado): ela conta no teto do dia, como a trava da fila conta
    update public.whatsapp_send_queue set status = 'failed', failed_reason = 'teste' where source = 'agenda-equipe';
    update public.agenda_equipe_mensagens set estado = 'recusada', recusa_motivo = 'janela' where tipo = 'ficha';
    r := public._agenda_equipe_registrar(c_roberto, d04, 'confirmar', 'Roberto, teste do teto 1.', pg_temp.em(d30, '19:40'));
    r2 := public._agenda_equipe_registrar(c_roberto, d05, 'confirmar', 'Roberto, teste do teto 2.', pg_temp.em(d30, '19:45'));
    v_res := pg_temp.ok(v_res, 'A30 a ficha que entrou na fila e falhou conta no teto: a 2ª do dia entra; a 3ª é recusada/teto, sem erro (antes a trava da fila estourava 23514)',
      r ->> 'estado' = 'enfileirada' and r2 ->> 'estado' = 'recusada' and r2 ->> 'motivo' = 'teto'
      and not exists (select 1 from public.whatsapp_send_queue q where q.source_ref_id = (r2 ->> 'id')::uuid),
      r::text || ' ' || r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.rodar(d03, '07:45');
    update public.whatsapp_send_queue set status = 'sent', sent_at = pg_temp.em(d03, '07:46') where source = 'agenda-equipe';
    -- a trava da fila recusando tudo (23514, como no teto): uma trava de teste depois da de verdade, desfeita no fim
    create function public._teste_fila_cheia() returns trigger language plpgsql as $t$
    begin
      raise exception 'Teto de mensagens à equipe no dia (teste).' using errcode = '23514', detail = 'teto';
    end
    $t$;
    create trigger trg_teste_fila_cheia before insert on public.whatsapp_send_queue
      for each row when (new.source = 'agenda-equipe') execute function public._teste_fila_cheia();
    r := pg_temp.resp('hoje não vou, tô doente', d03, '07:50');
    v_res := pg_temp.ok(v_res, 'A31 a trava da fila recusa a resposta (23514): ela fica recusada/teto e a falta, a ação e o replano ficam (nada é desfeito)',
      (r ->> 'consumiu')::boolean and r ->> 'envio' = 'recusada' and r ->> 'resposta' is null
      and exists (select 1 from public.agenda_equipe_mensagens m where m.tipo = 'resposta' and m.estado = 'recusada'
                                                                and m.recusa_motivo = 'teto')
      and exists (select 1 from public.agenda_disponibilidade d where d.payee_id = c_roberto and d.situacao = 'indisponivel'
                                                            and d.periodo @> d03 and d.substituida_em is null)
      and exists (select 1 from public.agenda_acoes a where a.tipo = 'equipe' and a.depois ->> 'motivo' = 'nao_vou')
      and not exists (select 1 from public.agenda_alocacoes a where a.payee_id = c_roberto and a.dia = d03
                                                            and a.estado in ('publicada', 'fixada')), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── B. A resposta ──────────────────────────────────────────────────────────────────────────────────────
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.rodar(d30, '19:30');
    update public.whatsapp_send_queue set status = 'sent', sent_at = pg_temp.em(d30, '19:31') where source = 'agenda-equipe';
    r := pg_temp.resp('amanhã não vou, tô doente', d30, '19:50', 'WA-NAO-VOU');
    v_res := pg_temp.ok(v_res, 'B1 "não vou" à ficha de terça: indisponível ter 03/11 (diarista), o replano, a ação equipe e "Tá bom, aviso o Gustavo."',
      (r ->> 'consumiu')::boolean and r ->> 'resposta' = 'Tá bom, aviso o Gustavo.'
      and exists (select 1 from public.agenda_disponibilidade d where d.payee_id = c_roberto and d.situacao = 'indisponivel'
                                                            and d.origem = 'diarista' and d.periodo @> d03)
      and exists (select 1 from public.agenda_acoes a where a.tipo = 'equipe' and a.depois ->> 'motivo' = 'nao_vou'
                                                    and (a.depois ->> 'dia')::date = d03)
      and not exists (select 1 from public.agenda_alocacoes a where a.payee_id = c_roberto and a.dia = d03 and a.estado in ('publicada', 'fixada'))
      and exists (select 1 from public.agenda_equipe_mensagens m where m.tipo = 'resposta' and m.estado = 'enfileirada'
                                                                and m.texto = 'Tá bom, aviso o Gustavo.'), r::text);
    r2 := pg_temp.resp('amanhã não vou, tô doente', d30, '19:50', 'WA-NAO-VOU');
    v_res := pg_temp.ok(v_res, 'B2 a mesma mensagem de novo: nada muda (1 resposta enfileirada, 1 ação)',
      (r2 ->> 'repetida')::boolean
      and (select count(*) from public.agenda_equipe_mensagens m where m.tipo = 'resposta' and m.estado = 'enfileirada') = 1
      and (select count(*) from public.agenda_acoes a where a.tipo = 'equipe') = 1, r2::text);
    -- (C1, NOVO-agenda-28) a resposta direta a uma mensagem dele às 20:00 (o fim da janela da equipe) sai na hora, com as
    -- tentativas até 10 min depois; a das 22:30 fica para o início da janela de sábado (07:30)
    r := public._agenda_equipe_registrar(c_roberto, d03, 'resposta', 'Tá bom, teste da janela.', pg_temp.em(d30, '20:00'), null,
                                         'WA-JANELA');
    r2 := public._agenda_equipe_registrar(c_roberto, d03, 'resposta', 'Tá bom, teste da noite.', pg_temp.em(d30, '22:30'), null,
                                          'WA-NOITE');
    v_res := pg_temp.ok(v_res, 'B2b a resposta direta das 20:00 sai na hora (3 tentativas, até 20:10); a das 22:30 vai às 07:30 de sábado',
      r ->> 'estado' = 'enfileirada' and r2 ->> 'estado' = 'enfileirada'
      and (select q.scheduled_for = pg_temp.em(d30, '20:00') and q.max_attempts = 3 from public.whatsapp_send_queue q
            where q.source_ref_id = (r ->> 'id')::uuid)
      and (select q.scheduled_for = pg_temp.em(d31, '07:30') and m.enviar_em = pg_temp.em(d31, '07:30')
             from public.whatsapp_send_queue q join public.agenda_equipe_mensagens m on m.id = q.source_ref_id
            where q.source_ref_id = (r2 ->> 'id')::uuid),
      r::text || ' ' || r2::text);
    -- o acorde sai pela rotina (sábado 31/10, o próximo dia útil é terça)
    r := pg_temp.rodar(d31, '08:00');
    v_res := pg_temp.ok(v_res, 'B3 o acorde do "não vou" sai pela rotina no tique seguinte',
      jsonb_array_length(r -> 'acordes') = 1
      and r -> 'acordes' -> 0 ->> 'texto' like 'O Roberto avisou que não vem terça (03/11). Mudei a agenda de%', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modos('ligado', 'ligado');
    r := pg_temp.resp('oque tem pra fazer amanhã', d02, '18:00');
    v_txt := (select m.texto from public.agenda_equipe_mensagens m where m.tipo = 'resposta');
    v_res := pg_temp.ok(v_res, 'B4 "oque tem pra fazer amanhã" (seg 02/11): a ficha de terça, sem valores nem número, enfileirada',
      (r ->> 'consumiu')::boolean
      and v_txt = 'Roberto, amanhã (ter 03/11): 8h no barco do Vanderlei, com o Gustavo, o dia todo. Dúvida, fala com o Gustavo.'
      and r ->> 'resposta' = v_txt and position('R$' in v_txt) = 0 and position('OS-' in v_txt) = 0
      and (select count(*) from public.whatsapp_send_queue q where q.source = 'agenda-equipe') = 1, coalesce(v_txt, r::text));
    r := pg_temp.resp('o que tem pra amanhã?', d31, '10:00');
    v_res := pg_temp.ok(v_res, 'B5 sábado: "Amanhã é domingo: não tem serviço marcado."',
      r ->> 'resposta' = 'Amanhã é domingo: não tem serviço marcado.', r::text);
    r := pg_temp.resp('o que tem pra amanhã?', d05, '18:00');
    v_res := pg_temp.ok(v_res, 'B6 sem plano para ele amanhã (sex 06/11): "Ainda não tenho o plano de amanhã…" e a pergunta ao dono',
      r ->> 'resposta' = 'Ainda não tenho o plano de amanhã. Vou ver com o Gustavo e te falo.'
      and exists (select 1 from public.agenda_perguntas q where q.tipo = 'equipe_resposta' and q.dia = date '2026-11-06'
                                                        and q.texto like 'O Roberto perguntou o que tem amanhã (sex 06/11)%'), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modos('sombra', 'sombra');
    r := pg_temp.resp('o que tem pra amanhã?', d02, '18:00');
    v_res := pg_temp.ok(v_res, 'B7 em sombra a pergunta só registra: consumiu false, a resposta registrada, a fila vazia',
      not (r ->> 'consumiu')::boolean and pg_temp.n_fila() = 0
      and exists (select 1 from public.agenda_equipe_mensagens m where m.tipo = 'resposta' and m.estado = 'registrada'), r::text);
    perform pg_temp.modos('desligado', 'desligado');
    r := pg_temp.resp('o que tem pra amanhã?', d02, '18:05');
    r2 := public.agenda_resposta_da_equipe('5511988887777', 'ok', 'WA-X', pg_temp.em(d02, '18:05'));
    v_res := pg_temp.ok(v_res, 'B8 desligado = consumiu false; telefone de fora da equipe = consumiu false',
      not (r ->> 'consumiu')::boolean and not (r2 ->> 'consumiu')::boolean, r::text || ' ' || r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.rodar(d30, '19:30');
    -- o recibo do acerto do Roberto mandado depois da ficha: o "ok" é do recibo (NOVO-agenda-17)
    insert into public.acertos_diarias (numero, favorecido_id, de, ate, saldo_anterior, dias, trabalhado, pago_no_periodo,
                                        valor_do_acerto, status, criado_por, enviado_ao_freelancer_em, telefone_enviado)
    values (2, c_roberto, date '2026-09-07', date '2026-09-30', 0, 10, 2000, 0, 2000, 'fechado', c_admin,
            pg_temp.em(d30, '19:50'), '5547900000001');
    r := pg_temp.resp('ok', d30, '20:00');
    v_res := pg_temp.ok(v_res, 'B9 "ok" com o recibo de diárias mandado depois da ficha: consumiu false (é do recibo); a ficha segue enfileirada',
      not (r ->> 'consumiu')::boolean and r ->> 'motivo' = 'recibo' and pg_temp.msgs() -> 0 ->> 'estado' = 'enfileirada'
      and not exists (select 1 from public.agenda_disponibilidade d where d.payee_id = c_roberto and d.situacao = 'confirmada'), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- B10–B11 (revisão C1, item 3): o "amanhã não vou" respondido ao "como foi" que levava a ficha de amanhã.
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.rodar(d30, '19:30');
    update public.whatsapp_send_queue set status = 'sent', sent_at = pg_temp.em(d30, '19:31') where source = 'agenda-equipe';
    perform pg_temp.rodar(d03, '07:45');
    update public.whatsapp_send_queue set status = 'sent', sent_at = pg_temp.em(d03, '07:46')
     where source = 'agenda-equipe' and status = 'pending';
    perform pg_temp.resp('cheguei', d03, '08:05');
    perform pg_temp.rodar(d03, '17:00');
    update public.whatsapp_send_queue set status = 'sent', sent_at = pg_temp.em(d03, '17:01')
     where source = 'agenda-equipe' and status = 'pending';
    r := pg_temp.resp('amanhã não vou', d03, '18:10');
    v_res := pg_temp.ok(v_res, 'B10 "amanhã não vou" ao "como foi" que levava a ficha de qua 04/11: indisponível qua 04/11 (não hoje), a ação e "Tá bom, aviso o Gustavo."; o "como foi" de hoje segue esperando e nenhuma pergunta da diária de hoje',
      (r ->> 'consumiu')::boolean and r ->> 'tipo' = 'nao_vou' and r ->> 'dia' = '2026-11-04'
      and r ->> 'resposta' = 'Tá bom, aviso o Gustavo.'
      and exists (select 1 from public.agenda_disponibilidade d where d.payee_id = c_roberto and d.situacao = 'indisponivel'
                                                            and d.origem = 'diarista' and d.periodo @> d04 and d.substituida_em is null)
      and not exists (select 1 from public.agenda_disponibilidade d where d.payee_id = c_roberto and d.situacao = 'indisponivel'
                                                                and d.periodo @> d03 and d.substituida_em is null)
      and exists (select 1 from public.agenda_acoes a where a.tipo = 'equipe' and a.depois ->> 'motivo' = 'nao_vou'
                                                    and (a.depois ->> 'dia')::date = d04)
      and (select m.estado = 'enfileirada' and m.resposta_em is null from public.agenda_equipe_mensagens m
            where m.tipo = 'como_foi' and m.dia = d03)
      and not exists (select 1 from public.agenda_perguntas q where q.tipo = 'diaria' and q.payee_id = c_roberto and q.dia = d03),
      r::text);
    -- o "ok" de depois responde o "como foi" de hoje: a diária de hoje entra e amanhã não vira confirmado
    r := pg_temp.resp('ok', d03, '18:20');
    v_res := pg_temp.ok(v_res, 'B11 o "ok" de depois é a resposta do "como foi" de hoje (a diária de ter 03/11 entra) e não confirma qua 04/11',
      (r ->> 'consumiu')::boolean and (pg_temp.turno(c_roberto, d03) ->> 'fracao')::numeric = 1
      and not exists (select 1 from public.agenda_disponibilidade d where d.payee_id = c_roberto and d.situacao = 'confirmada'
                                                                and d.periodo @> d04 and d.substituida_em is null),
      r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- B12–B13 (revisão C1, item 2): o atraso não é falta.
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.rodar(d03, '07:45');
    update public.whatsapp_send_queue set status = 'sent', sent_at = pg_temp.em(d03, '07:46') where source = 'agenda-equipe';
    v_txt := (select string_agg(a.id::text, ',' order by a.id) from public.agenda_alocacoes a
               where a.payee_id = c_roberto and a.dia = d03 and a.estado in ('publicada', 'fixada'));
    r := pg_temp.resp('não consigo chegar às 8, chego às 9', d03, '07:50');
    v_res := pg_temp.ok(v_res, 'B12 "não consigo chegar às 8, chego às 9" à confirmação: nada fica indisponível, o plano de hoje fica, nenhuma resposta a ele e a pergunta ao dono com o trecho',
      (r ->> 'consumiu')::boolean and r ->> 'tipo' = 'nao_entendi' and r ->> 'resposta' is null
      and not exists (select 1 from public.agenda_disponibilidade d where d.payee_id = c_roberto and d.situacao = 'indisponivel'
                                                                and d.periodo @> d03 and d.substituida_em is null)
      and v_txt = (select string_agg(a.id::text, ',' order by a.id) from public.agenda_alocacoes a
                    where a.payee_id = c_roberto and a.dia = d03 and a.estado in ('publicada', 'fixada'))
      and not exists (select 1 from public.agenda_equipe_mensagens m where m.tipo = 'resposta')
      and not exists (select 1 from public.agenda_acoes a where a.tipo = 'equipe')
      and exists (select 1 from public.agenda_perguntas q
                   where q.tipo = 'equipe_resposta' and q.estado = 'aberta'
                     and q.texto = 'O Roberto respondeu "não consigo chegar às 8, chego às 9" à confirmação de ter 03/11.'),
      r::text);
    r := pg_temp.rodar(d03, '09:00');
    v_res := pg_temp.ok(v_res, 'B13 e às 09:00 não é silêncio (ele respondeu)',
      (r #>> '{contagens,silencio,silencio}')::int = 0
      and not exists (select 1 from public.agenda_disponibilidade d where d.payee_id = c_roberto and d.situacao = 'indisponivel'),
      r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- B14–B15 (revisão C1, item 7): "ok, só de manhã" com o dia todo no plano não confirma o dia.
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.rodar(d30, '19:30');
    update public.whatsapp_send_queue set status = 'sent', sent_at = pg_temp.em(d30, '19:31') where source = 'agenda-equipe';
    r := pg_temp.resp('ok, só de manhã', d30, '20:10');
    v_res := pg_temp.ok(v_res, 'B14 "ok, só de manhã" à ficha de terça (o plano é o dia todo): não confirma; a pergunta ao dono "…, e o plano é o dia todo."',
      (r ->> 'consumiu')::boolean and pg_temp.msgs() -> 0 ->> 'estado' = 'respondida'
      and not exists (select 1 from public.agenda_disponibilidade d where d.payee_id = c_roberto and d.situacao = 'confirmada'
                                                                and d.periodo @> d03)
      and exists (select 1 from public.agenda_perguntas q
                   where q.tipo = 'equipe_resposta' and q.estado = 'aberta'
                     and q.texto = 'O Roberto respondeu "ok, só de manhã" à ficha de ter 03/11, e o plano é o dia todo.'),
      (select string_agg(q.texto, ' | ') from public.agenda_perguntas q where q.tipo = 'equipe_resposta'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.rodar(d30, '19:30');
    update public.whatsapp_send_queue set status = 'sent', sent_at = pg_temp.em(d30, '19:31') where source = 'agenda-equipe';
    r := pg_temp.resp('ok, o dia todo', d30, '20:10');
    v_res := pg_temp.ok(v_res, 'B15 "ok, o dia todo" (igual ao plano): confirma terça, sem pergunta ao dono',
      (r ->> 'consumiu')::boolean
      and exists (select 1 from public.agenda_disponibilidade d where d.payee_id = c_roberto and d.situacao = 'confirmada'
                                                            and d.periodo @> d03 and d.substituida_em is null)
      and not exists (select 1 from public.agenda_perguntas q where q.tipo = 'equipe_resposta'), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- B16–B19 (revisão C1, NOVO-agenda-28): a resposta direta a uma mensagem do técnico.
  v_res := pg_temp.ok(v_res, 'B16 a hora da resposta: 07:10 e 21:59 na hora; 05:40 às 07:30 do dia; 22:00 às 07:30 de amanhã; sáb 23:00 e dom 10:00 às 07:30 de segunda',
    public._agenda_equipe_quando_responder(pg_temp.em(d03, '07:10')) = pg_temp.em(d03, '07:10')
    and public._agenda_equipe_quando_responder(pg_temp.em(d03, '21:59')) = pg_temp.em(d03, '21:59')
    and public._agenda_equipe_quando_responder(pg_temp.em(d03, '05:40')) = pg_temp.em(d03, '07:30')
    and public._agenda_equipe_quando_responder(pg_temp.em(d03, '22:00')) = pg_temp.em(d04, '07:30')
    and public._agenda_equipe_quando_responder(pg_temp.em(d31, '23:00')) = pg_temp.em(d02, '07:30')
    and public._agenda_equipe_quando_responder(pg_temp.em(d01, '10:00')) = pg_temp.em(d02, '07:30'),
    null);
  begin
    perform pg_temp.modos('ligado', 'ligado');
    r := pg_temp.resp('hoje não vou, tô doente', d03, '07:10');
    v_id := (select m.id from public.agenda_equipe_mensagens m where m.tipo = 'resposta');
    v_res := pg_temp.ok(v_res, 'B17 "não vou" às 07:10 (antes da janela): o "Tá bom, aviso o Gustavo." sai na hora (07:10, 3 tentativas até 07:20)',
      (r ->> 'consumiu')::boolean and r ->> 'resposta' = 'Tá bom, aviso o Gustavo.' and r ->> 'envio' = 'enfileirada'
      and (select q.scheduled_for = pg_temp.em(d03, '07:10') and q.max_attempts = 3 and q.status = 'pending'
             from public.whatsapp_send_queue q where q.source_ref_id = v_id), r::text);
    -- a linha de fora com outra chave é recusada (o worker reconhece a resposta direta pela chave da mensagem)
    v_txt := pg_temp.erro_de(format($q$insert into public.whatsapp_send_queue (phone_normalized, message, source, source_ref_id,
                                                                              scheduled_for, max_attempts, dedupe_key)
                                       values ('5547900000001', 'teste', 'agenda-equipe', %L, %L, 1, 'outra-chave')$q$,
                                    v_id, pg_temp.em(d03, '07:10')));
    -- a nova tentativa (+5 min) dentro do prazo segue; a que passaria dos 10 min (ainda antes das 07:30) vira falha
    update public.whatsapp_send_queue set scheduled_for = pg_temp.em(d03, '07:15'), attempts = 1 where source_ref_id = v_id;
    r2 := jsonb_build_object('chave', v_txt, 'as_07_15', (select q.status from public.whatsapp_send_queue q where q.source_ref_id = v_id));
    update public.whatsapp_send_queue set scheduled_for = pg_temp.em(d03, '07:21'), attempts = 2 where source_ref_id = v_id;
    r2 := r2 || jsonb_build_object('as_07_21', (select q.status from public.whatsapp_send_queue q where q.source_ref_id = v_id));
    v_res := pg_temp.ok(v_res, 'B18 a linha de fora com outra chave é recusada (42501); a nova tentativa às 07:15 segue; a das 07:21 (fora da janela e passados os 10 min) vira falha',
      r2 ->> 'chave' like '42501 A fila da equipe só aceita a mensagem com a chave dela%' and r2 ->> 'as_07_15' = 'pending'
      and r2 ->> 'as_07_21' = 'failed', r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modos('ligado', 'ligado');
    r := pg_temp.resp('hoje não vou, tô doente', d03, '05:40');
    v_id := (select m.id from public.agenda_equipe_mensagens m where m.tipo = 'resposta');
    r2 := pg_temp.rodar(d03, '06:00');
    v_res := pg_temp.ok(v_res, 'B19 "não vou" às 05:40: o "Tá bom" fica para as 07:30 do dia, e a rotina das 06:00 não derruba a linha marcada para depois',
      (r ->> 'consumiu')::boolean and r ->> 'envio' = 'enfileirada'
      and (select q.scheduled_for = pg_temp.em(d03, '07:30') and q.status = 'pending'
             from public.whatsapp_send_queue q where q.source_ref_id = v_id), r::text || ' ' || r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── C. A diária ────────────────────────────────────────────────────────────────────────────────────────
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.rodar(d03, '17:00');
    r := pg_temp.resp('ok', d03, '17:12');
    v_t := pg_temp.turno(c_roberto, d03);
    v_res := pg_temp.ok(v_res, 'C1 "ok" ao "como foi" (o dia todo no plano): 1 diária inteira de R$ 180, aprovada, origem agente, ligada ao Vanderlei',
      (r ->> 'consumiu')::boolean and r ->> 'diaria' in ('lancada', 'ja_tratada')
      and (v_t ->> 'fracao')::numeric = 1 and (v_t ->> 'valor_dia')::numeric = 180 and v_t ->> 'status' = 'aprovado'
      and v_t ->> 'origem' = 'agente' and v_t -> 'os' = jsonb_build_array(c_vand)
      and v_t ->> 'aprovado_por' = c_admin::text, coalesce(v_t::text, r::text));
    v_res := pg_temp.ok(v_res, 'C2 as alocações dele no dia ficam cumpridas (via equipe) e com a diária; a ação diaria desfazível, com o texto',
      not exists (select 1 from public.agenda_alocacoes a
                   where a.payee_id = c_roberto and a.dia = d03 and a.estado in ('publicada', 'fixada')
                     and (a.resultado is distinct from 'cumprido' or a.resultado_via is distinct from 'equipe'
                          or a.work_shift_id is distinct from (v_t ->> 'id')::uuid))
      and exists (select 1 from public.agenda_acoes a
                   where a.tipo = 'diaria' and a.payee_id = c_roberto and a.executada and a.desfazivel_ate is not null
                     and a.origem = 'equipe' and a.work_shift_id = (v_t ->> 'id')::uuid
                     and a.texto = 'Roberto, ter 03/11: dia inteiro no Vanderlei (OS-00069), R$ 180,00 — ele confirmou às 17:12.'),
      (select string_agg(a.texto, ' | ') from public.agenda_acoes a where a.tipo = 'diaria'));
    -- C3: a palavra *diária Roberto meia* corrige o que a agenda lançou (pelo registrar_diaria)
    r := public.agenda_diaria_dita(c_admin, 'Roberto', 'meia', null, 'whatsapp', d03, pg_temp.em(d03, '17:40'));
    v_res := pg_temp.ok(v_res, 'C3 *diária Roberto meia* depois do automático: "Corrigido: Roberto, ter 03/11, meia diária (era dia inteiro)."',
      (r ->> 'ok')::boolean and r ->> 'texto' = 'Corrigido: Roberto, ter 03/11, meia diária (era dia inteiro).'
      and (pg_temp.turno(c_roberto, d03) ->> 'fracao')::numeric = 0.5, r::text);
    -- C4: *diária Roberto não* apaga o turno que a agenda lançou
    r := public.agenda_diaria_dita(c_admin, 'Roberto', 'não', null, 'whatsapp', d03, pg_temp.em(d03, '17:45'));
    v_res := pg_temp.ok(v_res, 'C4 *diária Roberto não*: "Apaguei a diária de ter 03/11 do Roberto que eu tinha lançado." e o turno some',
      (r ->> 'ok')::boolean and r ->> 'texto' = 'Apaguei a diária de ter 03/11 do Roberto que eu tinha lançado.'
      and pg_temp.turno(c_roberto, d03) is null, r::text);
    -- e a rotina não lança de novo (a diária daquele dia já foi tratada)
    r := pg_temp.rodar(d03, '18:00');
    v_res := pg_temp.ok(v_res, 'C5 depois de apagada, a rotina não lança de novo', pg_temp.turno(c_roberto, d03) is null, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.rodar(d03, '17:00');
    r := pg_temp.resp('ok', d03, '17:12');
    r2 := public.agenda_desfazer((select a.id from public.agenda_acoes a where a.tipo = 'diaria' and a.executada), c_admin, 'dono', d03,
                                 pg_temp.em(d03, '18:00'));
    v_res := pg_temp.ok(v_res, 'C6 *desfaz* da diária da agenda (dentro do prazo): o turno some e a ação fica desfeita',
      (r2 ->> 'ok')::boolean and pg_temp.turno(c_roberto, d03) is null
      and exists (select 1 from public.agenda_acoes a where a.tipo = 'diaria' and a.desfeita_em is not null), r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.rodar(d03, '17:00');
    r := pg_temp.resp('fiquei só de manhã', d03, '17:12');
    v_res := pg_temp.ok(v_res, 'C7 "fiquei só de manhã" (o plano era o dia todo): nenhuma diária e a pergunta crítica com 3 opções, recomendando a 1',
      pg_temp.turno(c_roberto, d03) is null
      and exists (select 1 from public.agenda_perguntas q
                   where q.tipo = 'diaria' and q.critica and q.estado = 'aberta' and q.payee_id = c_roberto and q.dia = d03
                     and jsonb_array_length(q.opcoes) = 3 and q.recomendacao = 1
                     and q.recomendacao_texto = 'Recomendo a 1: é o que o Roberto respondeu às 17:12.'
                     and q.opcoes -> 0 ->> 'texto' = 'meia diária no Vanderlei (OS-00069) (R$ 90,00), como o Roberto disse'
                     and q.opcoes -> 1 ->> 'texto' = 'dia inteiro no Vanderlei (OS-00069) (R$ 180,00), como estava no plano'
                     and q.texto = 'O Roberto respondeu "fiquei só de manhã" e o plano de ter 03/11 era o dia todo no Vanderlei (OS-00069).'),
      (select jsonb_agg(to_jsonb(q) - 'id')::text from public.agenda_perguntas q where q.tipo = 'diaria'));
    v_res := pg_temp.ok(v_res, 'C8 só a manhã dele fica cumprida (via equipe); a tarde fica sem resultado',
      (select a.resultado from public.agenda_alocacoes a where a.payee_id = c_roberto and a.dia = d03 and a.turno = 'manha'
                                                         and a.estado in ('publicada', 'fixada')) = 'cumprido'
      and (select a.resultado from public.agenda_alocacoes a where a.payee_id = c_roberto and a.dia = d03 and a.turno = 'tarde'
                                                             and a.estado in ('publicada', 'fixada')) is null, null);
    -- a decisão: opção 1 (meia)
    r := public.agenda_decidir((select q.id from public.agenda_perguntas q where q.tipo = 'diaria' and q.estado = 'aberta'), 1::smallint,
                               c_admin, 'whatsapp', 'diária Roberto meia', d03, pg_temp.em(d03, '17:40'));
    v_res := pg_temp.ok(v_res, 'C9 a decisão do dono (1, meia): turno meio, a ação diaria crítica com a pergunta',
      (r ->> 'ok')::boolean and (pg_temp.turno(c_roberto, d03) ->> 'fracao')::numeric = 0.5
      and exists (select 1 from public.agenda_acoes a where a.tipo = 'diaria' and a.critica and a.pergunta_id is not null
                                                    and a.executada and a.origem = 'dono'), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- C10: o *dia feito* do dono às 17:30 lança a meia do João (e a do Roberto, que não respondeu)
    perform pg_temp.modos('ligado', 'ligado');
    r := public.agenda_conferir_dia(c_admin, 'cumprido', null, null, 'whatsapp', d03, pg_temp.em(d03, '17:30'));
    v_res := pg_temp.ok(v_res, 'C10 *dia feito* às 17:30: lança a meia diária do João (R$ 75) e a do Roberto (R$ 180); o dono (sócio) não tem diária',
      (r ->> 'ok')::boolean
      and r ->> 'texto' like '%Lancei as diárias: Roberto (dia, R$ 180,00) e João (meia, R$ 75,00). *diária João inteira* corrige.'
      and (pg_temp.turno(c_joao, d03) ->> 'fracao')::numeric = 0.5 and pg_temp.turno(c_joao, d03) -> 'os' = jsonb_build_array(c_flavio)
      and (pg_temp.turno(c_roberto, d03) ->> 'fracao')::numeric = 1 and pg_temp.turno(c_gustavo, d03) is null, r ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- C11: em sombra nada é lançado: só a ação executada = false
    perform pg_temp.modos('sombra', 'sombra');
    r := public.agenda_conferir_dia(c_admin, 'cumprido', null, null, 'whatsapp', d03, pg_temp.em(d03, '17:30'));
    v_res := pg_temp.ok(v_res, 'C11 modo_diaria em sombra: 0 work_shifts novos, ações diaria com executada = false e "Em teste: lançaria …"',
      pg_temp.turno(c_joao, d03) is null and pg_temp.turno(c_roberto, d03) is null
      and (select count(*) from public.agenda_acoes a where a.tipo = 'diaria' and not a.executada) = 2
      and r ->> 'texto' like '%Em teste: lançaria Roberto (dia, R$ 180,00) e João (meia, R$ 75,00).', r ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- C12–C14: o turno que já existe
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.rodar(d03, '17:00');
    perform public.registrar_diaria(c_roberto, d03, 'inteiro', array[c_vand], null, null, null, null, 'painel', c_admin);
    r := pg_temp.resp('ok', d03, '17:12');
    v_res := pg_temp.ok(v_res, 'C12 turno igual (dia inteiro no Vanderlei) já lançado pelo dono: só liga a alocação, nenhuma ação diaria',
      r ->> 'diaria' in ('igual', 'ja_tratada')
      and not exists (select 1 from public.agenda_acoes a where a.tipo = 'diaria')
      and not exists (select 1 from public.agenda_alocacoes a where a.payee_id = c_roberto and a.dia = d03
                                                            and a.estado in ('publicada', 'fixada')
                                                            and a.work_shift_id is distinct from (pg_temp.turno(c_roberto, d03) ->> 'id')::uuid),
      r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.rodar(d03, '17:00');
    perform public.registrar_diaria(c_roberto, d03, 'inteiro', null, null, null, null, null, 'painel', c_admin);
    r := pg_temp.resp('ok', d03, '17:12');
    v_res := pg_temp.ok(v_res, 'C13 turno igual sem OS: a pergunta de ligar (não crítica, 2 opções); o turno fica sem OS',
      exists (select 1 from public.agenda_perguntas q where q.tipo = 'diaria_ligar' and not q.critica and q.estado = 'aberta'
                                                    and jsonb_array_length(q.opcoes) = 2
                                                    and q.texto = 'A diária de ter 03/11 do Roberto já estava lançada, sem OS. Ligo ao Vanderlei (OS-00069)? Me responda aqui.')
      and pg_temp.turno(c_roberto, d03) -> 'os' = '[]'::jsonb,
      (select string_agg(q.texto, ' | ') from public.agenda_perguntas q where q.tipo like 'diaria%'));
    r := public.agenda_decidir((select q.id from public.agenda_perguntas q where q.tipo = 'diaria_ligar'), 1::smallint, c_admin,
                               'whatsapp', 'liga', d03, pg_temp.em(d03, '17:40'));
    v_res := pg_temp.ok(v_res, 'C14 "liga": a diária passa a ter o Vanderlei',
      (r ->> 'ok')::boolean and pg_temp.turno(c_roberto, d03) -> 'os' = jsonb_build_array(c_vand), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.rodar(d03, '17:00');
    perform public.registrar_diaria(c_roberto, d03, 'meio', array[c_vand], null, null, null, null, 'painel', c_admin);
    v_t := pg_temp.turno(c_roberto, d03);
    r := pg_temp.resp('ok', d03, '17:12');
    v_res := pg_temp.ok(v_res, 'C15 turno diferente (meia já lançada, ele disse o dia todo): a pergunta crítica e o turno byte a byte igual',
      pg_temp.turno(c_roberto, d03) = v_t
      and exists (select 1 from public.agenda_perguntas q where q.tipo = 'diaria' and q.critica and q.estado = 'aberta'
                                                    and q.opcoes -> 0 -> 'efeito' ->> 'diaria' = 'manter' and q.recomendacao = 1),
      (select string_agg(q.texto, ' | ') from public.agenda_perguntas q where q.tipo = 'diaria'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- C16: meio dia em duas OS (manhã no Vanderlei, tarde no Flávio) → 1 diária inteira ligada às duas
    perform pg_temp.modos('ligado', 'ligado');
    perform set_config('agenda.hoje', '2026-11-03', true);
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'dono'
     where payee_id = c_roberto and dia = d03 and turno = 'tarde' and estado in ('publicada', 'fixada');
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado, origem)
    values (c_flavio, c_roberto, d03, 'tarde', 'publicada', 'dono');
    perform pg_temp.rodar(d03, '17:00');
    r := pg_temp.resp('ok', d03, '17:12');
    v_t := pg_temp.turno(c_roberto, d03);
    v_res := pg_temp.ok(v_res, 'C16 meio dia no Vanderlei e meio no Flávio: 1 diária inteira com os 2 vínculos',
      (v_t ->> 'fracao')::numeric = 1
      and v_t -> 'os' = (select jsonb_agg(x order by x) from unnest(array[c_vand, c_flavio]) x), coalesce(v_t::text, r::text));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- C17: o acerto fechado do período → a pergunta crítica, nada lançado
    perform pg_temp.modos('ligado', 'ligado');
    insert into public.acertos_diarias (numero, favorecido_id, de, ate, saldo_anterior, dias, trabalhado, pago_no_periodo,
                                        valor_do_acerto, status, criado_por, criado_em)
    values (3, c_roberto, d03, d03, 0, 1, 180, 0, 180, 'fechado', c_admin, pg_temp.em(d03, '12:00'));
    perform pg_temp.rodar(d03, '17:00');
    r := pg_temp.resp('ok', d03, '17:12');
    v_res := pg_temp.ok(v_res, 'C17 acerto do período fechado: nenhuma diária e a pergunta crítica "o acerto desse período já foi fechado"',
      pg_temp.turno(c_roberto, d03) is null
      and exists (select 1 from public.agenda_perguntas q where q.tipo = 'diaria' and q.critica and q.estado = 'aberta'
                                                    and q.texto like '%o acerto desse período já foi fechado.'),
      (select string_agg(q.texto, ' | ') from public.agenda_perguntas q where q.tipo = 'diaria'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modos('ligado', 'ligado');
    r := public.agenda_diaria_dita(c_admin, 'Mickael', 'inteira', null, 'whatsapp', d03, pg_temp.em(d03, '17:40'));
    r2 := public.agenda_diaria_dita(c_admin, 'Roberto', 'meia', 'ontem', 'whatsapp', d04, pg_temp.em(d04, '17:40'));
    v_res := pg_temp.ok(v_res, 'C18 *diária <nome> …* sem nada da agenda: nao_achei (o turno segue ao modelo e ao registrar_diaria)',
      r ->> 'status' = 'nao_achei' and r2 ->> 'status' = 'nao_achei' and pg_temp.turno(c_roberto, d03) is null,
      r::text || ' ' || r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── D. A repescagem: a diária lançada 4 dias depois preenche o resultado ─────────────────────────────────
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform public.registrar_diaria(c_roberto, d04, 'inteiro', array[c_vand], null, null, null, null, 'painel', c_admin);
    r := pg_temp.rodar(d08, '10:00');
    v_res := pg_temp.ok(v_res, 'D1 a diária do dono de qua 04/11 lançada dom 08/11: as alocações dele no dia ficam cumpridas (via sistema)',
      not exists (select 1 from public.agenda_alocacoes a
                   where a.payee_id = c_roberto and a.dia = d04 and a.estado in ('publicada', 'fixada')
                     and (a.resultado is distinct from 'cumprido' or a.resultado_via is distinct from 'sistema'
                          or a.resultado_trecho is distinct from 'diária lançada em qua 04/11'))
      and (r #>> '{contagens,resultado_pela_diaria,alocacoes}')::int = 2, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── E. A conclusão pelo técnico ────────────────────────────────────────────────────────────────────────
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.rodar(d05, '17:00');
    r := pg_temp.resp('ok, terminei', d05, '17:15');
    r := pg_temp.rodar(d05, '17:30');
    v_res := pg_temp.ok(v_res, 'E1 "ok, terminei" no último dia do Vanderlei: a OS concluída pela porta (via equipe), desfazível',
      (select so.status from public.service_orders so where so.id = c_vand) = 'completed'
      and exists (select 1 from public.agenda_acoes a where a.tipo = 'concluir' and a.service_order_id = c_vand and a.origem = 'equipe'
                                                    and a.executada and a.desfazivel_ate is not null)
      and (r #>> '{contagens,conclusao,concluidas}')::int = 1, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.rodar(d04, '17:00');
    r := pg_temp.resp('ok, terminei', d04, '17:15');
    r := pg_temp.rodar(d04, '17:30');
    v_res := pg_temp.ok(v_res, 'E2 "terminei" fora do último dia: nada conclui e vira a pergunta "concluir"',
      (select so.status from public.service_orders so where so.id = c_vand) <> 'completed'
      and exists (select 1 from public.agenda_perguntas q
                   where q.tipo = 'concluir' and q.estado = 'aberta'
                     and q.texto = 'O Roberto disse que terminou o Vanderlei (OS-00069), mas o plano tinha mais 1 dia (qui 05/11). *concluiu Vanderlei* fecha a OS.'),
      (select string_agg(q.texto, ' | ') from public.agenda_perguntas q where q.tipo = 'concluir'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.rodar(d05, '17:00');
    r := pg_temp.resp('ok, terminei', d05, '17:15');
    update public.agenda_config set modo_proposta = 'sombra' where id;
    r := pg_temp.rodar(d05, '17:30');
    v_res := pg_temp.ok(v_res, 'E3 com a agenda automática em sombra: nada conclui; só a ação concluir com executada = false',
      (select so.status from public.service_orders so where so.id = c_vand) <> 'completed'
      and exists (select 1 from public.agenda_acoes a where a.tipo = 'concluir' and not a.executada and a.service_order_id = c_vand),
      r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  begin
    -- E4: a OS concluída antes do fim do plano (pela palavra do dono) não fica com meios-dias pendurados: a vigia do tique
    -- seguinte os tira (violação "a OS saiu da carteira"). A conclusão não mexe no plano; quem limpa é a vigia.
    r := public.agenda_concluir_dito(c_admin, 'Lenine', 'whatsapp', d03, pg_temp.em(d03, '10:00'));
    v_n := (select count(*) from public.agenda_alocacoes a where a.service_order_id = c_lenine and a.dia > d03
                                                         and a.estado in ('publicada', 'fixada'));
    r2 := public.agenda_vigiar(d03, pg_temp.em(d03, '10:15'));
    v_res := pg_temp.ok(v_res, 'E4 OS concluída antes do fim do plano: a vigia seguinte tira os meios-dias futuros dela (os_saiu)',
      (r ->> 'ok')::boolean and v_n > 0
      and not exists (select 1 from public.agenda_alocacoes a where a.service_order_id = c_lenine and a.dia > d03
                                                            and a.estado in ('publicada', 'fixada'))
      and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = c_lenine and a.cancelada_motivo = 'os_saiu'),
      format('futuras antes: %s; vigia: %s', v_n, r2 #>> '{contagens,violacoes,texto}'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── F. A intervenção do dono ───────────────────────────────────────────────────────────────────────────
  begin
    perform pg_temp.modos('ligado', 'ligado');
    r := public.agenda_rascunho_andamento(c_admin, 'whatsapp', 'Lenine', 'trabalhou', null, array['eu'], null,
                                          'eu fui no Lenine hoje', d03, pg_temp.em(d03, '16:00'));
    perform set_config('agenda.agora', pg_temp.em(d03, '16:05')::text, true);
    r2 := public.agenda_rascunho_gravar(c_admin, d03);
    v_res := pg_temp.ok(v_res, 'F1 "eu fui no Lenine" sem estar no plano: o rascunho aceita, o *grava* anota 1 intervenção (nenhuma prevista)',
      (r ->> 'ok')::boolean and (r2 ->> 'ok')::boolean
      and (select count(*) from public.agenda_intervencoes_do_dono i
            where i.service_order_id = c_lenine and i.dia = d03 and i.prevista = 'nenhuma' and i.origem = 'conversa') = 1
      and r2 ->> 'texto' like '%Anotei que você foi ao Lenine sem estar no plano: isso ajusta a sua presença nas OS parecidas.%',
      r ->> 'releitura' || ' || ' || (r2 ->> 'texto'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── G. A saúde ─────────────────────────────────────────────────────────────────────────────────────────
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.rodar(d03, '17:00');
    perform pg_temp.resp('ok', d03, '17:12');
    r := public.agenda_saude(d03, pg_temp.em(d03, '18:00'));
    v_res := pg_temp.ok(v_res, 'G1 agenda_saude na fixture: acima_do_teto, fora_da_janela, sem_confirmacao, sobrescreveu_turno e payables de comissão = 0',
      (r #>> '{equipe,acima_do_teto}')::int = 0 and (r #>> '{equipe,fora_da_janela}')::int = 0
      and (r #>> '{diarias,sem_confirmacao}')::int = 0 and (r #>> '{diarias,sobrescreveu_turno}')::int = 0
      and (r #>> '{diarias,lancadas_7d}')::int = 1 and (r #>> '{comissao,payables_de_comissao_tecnico_7d}')::int = 0
      and r #>> '{comissao,pagamento}' = 'desligado' and (r #>> '{rotina,rodou_nas_ultimas_2h}')::boolean
      and coalesce((r #>> '{conclusao,sem_recebivel_quando_devia}')::int, 0) = 0,
      jsonb_build_object('equipe', r -> 'equipe', 'diarias', r -> 'diarias', 'rotina', r -> 'rotina', 'ok', r -> 'ok')::text);
    -- forçando: a diária da agenda sem confirmação (gatilho desligado) e uma linha da fila da equipe à meia-noite
    alter table public.agenda_acoes disable trigger agenda_acoes_diaria_confirmada;
    insert into public.agenda_acoes (dia, executada, origem, tipo, payee_id, depois, texto)
    values (d04, true, 'conferencia', 'diaria', c_joao, jsonb_build_object('dia', d04), 'TESTE: diária sem confirmação');
    alter table public.agenda_acoes enable trigger agenda_acoes_diaria_confirmada;
    alter table public.whatsapp_send_queue disable trigger trg_agenda_fila_da_equipe;
    insert into public.whatsapp_send_queue (phone_normalized, message, source, scheduled_for, dedupe_key)
    values ('5547900000001', 'teste', 'agenda-equipe', pg_temp.em(d04, '00:00'), 'teste-saude-meia-noite');
    alter table public.whatsapp_send_queue enable trigger trg_agenda_fila_da_equipe;
    r := public.agenda_saude(d04, pg_temp.em(d04, '08:00'));
    v_res := pg_temp.ok(v_res, 'G2 forçando (gatilhos desligados): sem_confirmacao = 1, fora_da_janela = 1 e ok = false',
      (r #>> '{diarias,sem_confirmacao}')::int = 1 and (r #>> '{equipe,fora_da_janela}')::int = 1 and not (r ->> 'ok')::boolean,
      jsonb_build_object('equipe', r -> 'equipe', 'diarias', r -> 'diarias')::text);
    v_txt := pg_temp.erro_de(format($q$insert into public.agenda_acoes (dia, executada, origem, tipo, payee_id, depois, texto)
                                       values (%L, true, 'equipe', 'diaria', %L, jsonb_build_object('dia', %L::date), 'TESTE')$q$,
                                    d04, c_joao, d04));
    v_res := pg_temp.ok(v_res, 'G3 com o gatilho: a diária da agenda sem confirmação é recusada (23514)',
      v_txt like '23514 Diária sem confirmação%', v_txt);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── H. O acorde avisa quem já recebeu a ficha ──────────────────────────────────────────────────────────
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.rodar(d03, '19:30');
    insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, alocacoes_canceladas, texto)
    values (d03, true, 'vigia', 'mover', c_vand, array[c_vand],
            array(select a.id from public.agenda_alocacoes a where a.payee_id = c_roberto and a.dia = d04 and a.estado in ('publicada', 'fixada')),
            'Vanderlei (OS-00069): teste de mudança.')
    returning id into v_id;
    v_txt := public._agenda_texto_do_acorde(v_id, d04, d03);
    v_res := pg_temp.ok(v_res, 'H1 a mudança de amanhã atinge quem já recebeu a ficha: "O Roberto já recebeu a ficha de amanhã com o Vanderlei: avise ele da mudança."',
      v_txt like '%O Roberto já recebeu a ficha de amanhã com o Vanderlei: avise ele da mudança.', v_txt);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  perform pg_temp.gravar(v_res);
end $eq$;

-- ── J. Portas (rodam sempre) ────────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('J1 %s: só service_role', f),
       not has_function_privilege('authenticated', f::regprocedure, 'execute')
       and not has_function_privilege('anon', f::regprocedure, 'execute')
       and has_function_privilege('service_role', f::regprocedure, 'execute'), null
  from unnest(array[
    'public.agenda_equipe_ficha(uuid, date, date)',
    'public.agenda_resposta_da_equipe(text, text, text, timestamptz)',
    'public.agenda_rotina_rodar(date, timestamptz)',
    'public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz)',
    'public.agenda_desfazer(uuid, uuid, text, date, timestamptz)']) f;

insert into _resultado
select format('J2 %s: authenticated e service_role; anon não', f),
       has_function_privilege('authenticated', f::regprocedure, 'execute')
       and has_function_privilege('service_role', f::regprocedure, 'execute')
       and not has_function_privilege('anon', f::regprocedure, 'execute'), null
  from unnest(array[
    'public.agenda_diaria_dita(uuid, text, text, text, text, date, timestamptz)',
    'public.agenda_diaria_da_agenda(uuid, date)',
    'public._agenda_ler_resposta_da_equipe(text)',
    'public._agenda_confirmacao_do_dia(uuid, date)',
    'public._agenda_payee_do_telefone(text, date)',
    'public.agenda_registrar_dia(uuid, date, text, text, uuid, uuid[], text, text, date, timestamptz, text)',
    'public.agenda_saude(date, timestamptz)',
    'public._agenda_texto_do_acorde(uuid, date, date)',
    -- (revisão C1) a janela de uma tentativa: a saúde (invoker) lê
    'public._agenda_equipe_fora_da_janela(text, timestamptz, timestamptz)']) f;

insert into _resultado
select format('J3 %s: ninguém de fora', f),
       not has_function_privilege('authenticated', f::regprocedure, 'execute')
       and not has_function_privilege('anon', f::regprocedure, 'execute')
       and not has_function_privilege('service_role', f::regprocedure, 'execute'), null
  from unnest(array[
    'public._agenda_equipe_enfileirar(uuid)',
    'public._agenda_equipe_registrar(uuid, date, text, text, timestamptz, date, text)',
    'public._agenda_diaria_do_dia(uuid, date, text, date, timestamptz)',
    'public._agenda_lancar_diaria(uuid, date, numeric, uuid[], text, text, uuid, date, timestamptz, jsonb)',
    'public._agenda_decidir_diaria(uuid, smallint, uuid, text, text, date, timestamptz)',
    'public._agenda_desfazer_diaria(uuid, uuid, date, timestamptz, boolean)',
    'public._agenda_rotina_ficha(date, timestamptz)',
    'public._agenda_rotina_silencio(date, timestamptz)',
    -- (revisão C1) a hora da resposta e o teto contado num lugar só
    'public._agenda_equipe_quando_responder(timestamptz)',
    'public._agenda_equipe_no_dia(uuid, date, boolean, uuid)']) f;

insert into _resultado
select 'J4 os gatilhos novos: a trava da fila só para agenda-equipe (INSERT e a nova tentativa) e a diária sem confirmação',
       (select count(*) from pg_trigger t where t.tgrelid = 'public.whatsapp_send_queue'::regclass
                                           and t.tgname in ('trg_agenda_fila_da_equipe', 'trg_agenda_fila_da_equipe_tentativa')
                                           and pg_get_triggerdef(t.oid) like '%agenda-equipe%') = 2
       and exists (select 1 from pg_trigger t where t.tgrelid = 'public.agenda_acoes'::regclass
                                             and t.tgname = 'agenda_acoes_diaria_confirmada'), null;

select teste, ok, detalhe from _resultado order by teste;

rollback;
