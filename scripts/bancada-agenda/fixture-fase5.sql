-- Fixture da Fase 5 da Agenda de Produção: a carteira de sex 30/10/2026 com os clientes e a conversa, SINTÉTICA.
-- = fixture-fase4.sql (que executa as das Fases 3 e 2 e o pós-rodada da Fase 1 por dentro) + o que a mensagem ao cliente
-- precisa. Roda dentro do begin/rollback do teste (o rodar.mjs passa este arquivo em agenda_teste.fase5 e os de antes nos
-- seus nomes). NUNCA rodar em produção. Só primeiros nomes; telefones do tipo "55479000003xx" (o do dono é o do login,
-- 5547900000210, da fixture-fase4); ids novos com o prefixo d5000000 e as OS 121 a 123 (livres nas fixtures e nos testes
-- em 27/10).
--
-- O calendário (spec-fase5 §8.2): hoje é sex 30/10/2026; sáb 31/10 tem janela de 08 a 13; dom 01/11 nunca; seg 02/11 é
-- Finados. O plano publicado (fixture-fase3): Vanderlei ter 03 a qui 05/11, Flávio ter 03 (à tarde) e qua 04/11 (de manhã),
-- Rodrigo qua 04/11 à tarde, Lenine sex 06 a ter 10/11; o Nelson não cabe (pergunta crítica aberta) e o Giancarlo está com o
-- motorhome fora até 11/11.
--
-- P1 (27/10) — os clientes e a conversa:
--   · telefones (WhatsApp) sintéticos: Vanderlei …301, Giancarlo …303, Flávio …304, Nelson …305, Robson …307, Kalmar …309
--     (com opt-out), Lucenira …312; o Lenine segue SEM telefone (NOVO-agenda-37) e o Rodrigo com o da fixture-fase4 (…211,
--     o mesmo da Souper); o "MP" sem telefone;
--   · a conversa (uma mensagem DELE, recebida): Vanderlei qui 15/10, Flávio ter 20/10, Nelson qua 21/10, Kalmar seg 19/10,
--     Robson sex 23/10, Lucenira qua 28/10 e o Giancarlo HOJE às 09:40 (a "conversa viva" de quem roda às 10:00);
--   · o Flávio: o bem passa a Motorhome (como a spec descreve; a fixture de 23/10 dizia Lancha), sem acesso registrado, e o
--     serviço como ele conhece: "a instalação do compressor";
--   · o Nelson: a AliExpress mudou a entrega do painel de qua 04/11 para qua 11/11 (o original continua 04/11) e o cliente
--     ouviu "quinta (05/11)" numa mensagem da agenda enviada qui 22/10 às 10:00 (o M1 aprovado pelo dono): prometido firme
--     de qui 05/11 a qui 05/11, original 05/11, fonte mensagem;
--   · o Robson: a OS-00121, concluída qui 22/10 e entregue sex 23/10 (o pós-serviço);
--   · a Lucenira (cliente nova): a OS-00122 da lancha dela na Marina de Itajaí, vaga 12, concluída HOJE às 15:00 e sem
--     entrega (o "ficou pronto"); o serviço como ela conhece: "a troca das baterias";
--   · o dono como cliente: "Gustavo", com o WhatsApp do login dele (…210) e a OS-00123 concluída em setembro — nunca recebe
--     nem é lido como cliente;
--   · a empresa: app_settings.company_name = "HBR Marine Solutions" (como em produção, m5_12).
-- As variações da spec (o Vanderlei em awaiting_parts, a Lucenira sem conversa, o *choveu* de qui 29/10, os prometidos do
-- Nelson) são dos testes de cada pacote, em subtransação. Os pacotes seguintes acrescentam o que é deles em seções próprias
-- no fim deste arquivo.
-- Os modos ao fim: os da fixture-fase4 (proposta e vigia ligados; equipe, diária, material, detector e fornecedor
-- desligados) e modo_cliente desligado, como a linha nasce: cada teste liga o que precisa.

do $fase5$
begin
  if coalesce(current_setting('agenda_teste.fase4', true), '') = '' then
    raise exception 'fixture-fase5: falta agenda_teste.fase4 (rode pela bancada: scripts/bancada-agenda/rodar.mjs)';
  end if;
  execute current_setting('agenda_teste.fase4');
end
$fase5$;

-- ── A empresa ───────────────────────────────────────────────────────────────────────────────────────────
insert into public.app_settings (key, value) values ('company_name', 'HBR Marine Solutions')
  on conflict (key) do update set value = excluded.value;

-- ── Os clientes: telefone, opt-out e os novos ──────────────────────────────────────────────────────────
update public.clients set whatsapp = '5547900000301' where id = 'c1000000-0000-4000-8000-000000000001';   -- Vanderlei
update public.clients set whatsapp = '5547900000303' where id = 'c1000000-0000-4000-8000-000000000003';   -- Giancarlo
update public.clients set whatsapp = '5547900000304' where id = 'c1000000-0000-4000-8000-000000000004';   -- Flávio
update public.clients set whatsapp = '5547900000305' where id = 'c1000000-0000-4000-8000-000000000005';   -- Nelson
update public.clients set whatsapp = '5547900000307' where id = 'c1000000-0000-4000-8000-000000000007';   -- Robson
update public.clients set whatsapp = '5547900000309', opt_out_whatsapp = true
 where id = 'c1000000-0000-4000-8000-000000000009';                                                        -- Kalmar

insert into public.clients (id, type, name, whatsapp, city) values
  ('c1000000-0000-4000-8000-000000000012', 'individual', 'Lucenira', '5547900000312', 'Itajaí'),
  ('c1000000-0000-4000-8000-000000000013', 'individual', 'Gustavo',  '5547900000210', 'Itajaí');

-- O bem do Flávio é um motorhome (spec §8.2); a lancha da Lucenira na marina, vaga 12; a do dono.
update public.vessels set name = 'Motorhome', asset_type = 'Motorhome' where id = 'f1000000-0000-4000-8000-000000000004';
insert into public.vessels (id, client_id, marina_id, name, asset_type, current_dock_position) values
  ('f1000000-0000-4000-8000-000000000012', 'c1000000-0000-4000-8000-000000000012', 'ee000000-0000-4000-8000-000000000001',
   'Lancha', 'Lancha', '12'),
  ('f1000000-0000-4000-8000-000000000013', 'c1000000-0000-4000-8000-000000000013', null, 'Lancha', 'Lancha', null);

-- ── As OS novas: Robson (entregue sex 23/10), Lucenira (concluída hoje), o dono (setembro) ──────────────
-- A entrega só entra pela porta (o gatilho da Fase 3): a chave local, como a fixture de 23/10 não precisou.
select set_config('agenda.porta', 'on', true);
insert into public.service_orders (id, service_order_number, client_id, vessel_id, marina_id, status, quote_status,
  service_type, created_at, updated_at, converted_to_os_at, check_in_at, check_out_at, delivered_at, grand_total)
values
  ('05000000-0000-4000-8000-000000000121', 'OS-00121', 'c1000000-0000-4000-8000-000000000007',
   'f1000000-0000-4000-8000-000000000007', null, 'completed', 'approved', 'repair', '2026-10-08 12:00-03', '2026-10-23 16:00-03',
   '2026-10-12 12:00-03', '2026-10-21 08:00-03', '2026-10-22 17:00-03', '2026-10-23 16:00-03', 1200),
  ('05000000-0000-4000-8000-000000000122', 'OS-00122', 'c1000000-0000-4000-8000-000000000012',
   'f1000000-0000-4000-8000-000000000012', 'ee000000-0000-4000-8000-000000000001', 'completed', 'approved', 'repair',
   '2026-10-14 12:00-03', '2026-10-30 15:00-03', '2026-10-16 12:00-03', '2026-10-28 08:00-03', '2026-10-30 15:00-03', null, 3400),
  ('05000000-0000-4000-8000-000000000123', 'OS-00123', 'c1000000-0000-4000-8000-000000000013',
   'f1000000-0000-4000-8000-000000000013', null, 'completed', 'approved', 'repair', '2026-09-01 12:00-03', '2026-09-10 17:00-03',
   '2026-09-02 12:00-03', '2026-09-09 08:00-03', '2026-09-10 17:00-03', null, 500);
select set_config('agenda.porta', 'off', true);

-- ── Como o serviço é dito ao cliente ────────────────────────────────────────────────────────────────────
update public.os_planejamento set servico_cliente = 'a instalação do compressor'
 where service_order_id = '05000000-0000-4000-8000-000000000104';                                          -- Flávio
insert into public.os_planejamento (service_order_id, servico_cliente)
values ('05000000-0000-4000-8000-000000000122', 'a troca das baterias');                                  -- Lucenira

-- ── A conversa: uma mensagem DELE em cada um (o "já conversou" da d10) ──────────────────────────────────
insert into public.whatsapp_messages (id, direction, phone_normalized, message_type, body, occurred_at, delivery_status) values
  ('d5000000-0000-4000-8000-000000000301', 'inbound', '5547900000301', 'text', 'Bom dia! Tudo certo para a semana que vem?',
   timestamptz '2026-10-15 10:00-03', 'received'),
  ('d5000000-0000-4000-8000-000000000304', 'inbound', '5547900000304', 'text', 'Oi, alguma novidade do compressor?',
   timestamptz '2026-10-20 09:00-03', 'received'),
  ('d5000000-0000-4000-8000-000000000305', 'inbound', '5547900000305', 'text', 'Bom dia! E o painel?',
   timestamptz '2026-10-21 08:30-03', 'received'),
  ('d5000000-0000-4000-8000-000000000309', 'inbound', '5547900000309', 'text', 'Ok, obrigado.',
   timestamptz '2026-10-19 11:00-03', 'received'),
  ('d5000000-0000-4000-8000-000000000307', 'inbound', '5547900000307', 'text', 'Valeu, ficou ótimo!',
   timestamptz '2026-10-23 17:30-03', 'received'),
  ('d5000000-0000-4000-8000-000000000312', 'inbound', '5547900000312', 'text', 'Oi, como está o serviço?',
   timestamptz '2026-10-28 14:00-03', 'received'),
  ('d5000000-0000-4000-8000-000000000303', 'inbound', '5547900000303', 'text', 'O motorhome volta dia 12 mesmo, combinado?',
   timestamptz '2026-10-30 09:40-03', 'received');

-- ── O Nelson: a peça mudou para 11/11 e ele ouviu "quinta (05/11)" em 22/10 ────────────────────────────
select set_config('agenda.hoje', '2026-10-29', true);
update public.os_material
   set previsao_ate = date '2026-11-11', previsao_fonte = 'fornecedor',
       trecho = 'a AliExpress mudou a entrega do painel para 11/11'
 where service_order_part_id = md5('peca:112:4')::uuid;                                    -- Painel Touch HBR 7"
select set_config('agenda.hoje', '', true);

insert into public.agenda_cliente_mensagens (id, client_id, service_order_id, tipo, variante, origem, dia_alvo, prometido_tipo,
  modo, texto, base, enviar_em, valida_ate, aprovacao, aprovada_em, aprovada_por, estado, dedupe_key, enviada_em, criada_em)
values ('d5000000-0000-4000-8000-0000000000a1', 'c1000000-0000-4000-8000-000000000005', '05000000-0000-4000-8000-000000000112',
        'confirmar', 'primeira', 'rodada', date '2026-11-05', 'firme', 'ligado',
        'Olá, Nelson! Aqui é o Gustavo, da HBR Marine Solutions. Conseguimos encaixar o serviço no seu veleiro para quinta (05/11), o dia todo, com previsão de 1 dia de trabalho. Pode ser? Responda SIM para confirmar, ou me diga um dia melhor. A partir de agora te mando por aqui as novidades do serviço.',
        '{"status": "awaiting_parts", "dia_alvo": "2026-11-05", "fim": "2026-11-05", "nivel": "C", "primeira": true, "envio": "2026-10-22"}',
        timestamptz '2026-10-22 10:00-03', timestamptz '2026-10-22 19:00-03', 'aprovada', timestamptz '2026-10-22 09:30-03',
        'aa000000-0000-4000-8000-000000000001', 'enviada',
        'agenda-cliente:confirmar:05000000-0000-4000-8000-000000000112:2026-11-05', timestamptz '2026-10-22 10:00:30-03',
        timestamptz '2026-10-21 17:00-03');

update public.os_planejamento
   set prometido_tipo = 'firme', prometido_de = date '2026-11-05', prometido_ate = date '2026-11-05',
       prometido_original_ate = date '2026-11-05', prometido_em = timestamptz '2026-10-22 10:00:30-03',
       prometido_fonte = 'mensagem', prometido_mensagem_id = 'd5000000-0000-4000-8000-0000000000a1'
 where service_order_id = '05000000-0000-4000-8000-000000000112';

-- ── Os auxiliares de tempo dos testes da Fase 5 (spec §8.1) ─────────────────────────────────────────────
-- O "hoje" do teste vale também para quem lê o relógio de verdade (_hoje_brt: o padrão de p_hoje das funções novas e o
-- registrar_diaria), como nos testes da Fase 3: set_config('agenda_teste.hoje', 'AAAA-MM-DD', true). Sem ele, o de sempre.
-- Dentro da transação do teste: o ROLLBACK do fim desfaz.
create or replace function public._hoje_brt() returns date language sql stable set search_path to 'public' as $h$
  select coalesce(nullif(current_setting('agenda_teste.hoje', true), '')::date, (now() at time zone 'America/Sao_Paulo')::date)
$h$;
-- A hora de Brasília escrita como se fala: pg_temp.agora('2026-10-30 10:00') = timestamptz '2026-10-30 10:00-03'.
create or replace function pg_temp.agora(p_quando text) returns timestamptz language sql stable as $a$
  select (p_quando::timestamp) at time zone 'America/Sao_Paulo'
$a$;

-- ── Confere o estado de que os testes da Fase 5 partem ──────────────────────────────────────────────────
do $confere$
declare
  v_falta text;
begin
  v_falta := case
    when (select string_agg(a.dia::text || ' ' || a.turno, ',' order by a.dia, a.turno)
            from (select distinct dia, turno from public.agenda_alocacoes
                   where service_order_id = '05000000-0000-4000-8000-000000000104' and estado in ('publicada', 'fixada')
                     and tipo <> 'reserva') a) is distinct from '2026-11-03 tarde,2026-11-04 manha'
      then 'o Flávio não está publicado em ter 03/11 à tarde e qua 04/11 de manhã'
    when (select status from public.service_orders where id = '05000000-0000-4000-8000-000000000104') <> 'scheduled'
      then 'o Flávio não está agendado'
    when (select status from public.service_orders where id = '05000000-0000-4000-8000-000000000112') <> 'awaiting_parts'
      or public._agenda_plano_da_os('05000000-0000-4000-8000-000000000112', date '2026-10-30') is not null
      then 'o Nelson não está esperando peça sem plano'
    when (select previsao_original from public.os_material where service_order_part_id = md5('peca:112:4')::uuid)
         is distinct from date '2026-11-04'
      then 'o painel do Nelson perdeu o original de qua 04/11'
    when (public._agenda_plano_da_os('05000000-0000-4000-8000-000000000069', date '2026-10-30') ->> 'proximo_dia')
         is distinct from '2026-11-03'
      or (public.os_prontidao('05000000-0000-4000-8000-000000000069', date '2026-10-30') #>> '{material,estado}') = 'completo'
      then 'o Vanderlei não está publicado em ter 03/11 com material faltando'
    when (select clients.phone is not null or clients.whatsapp is not null from public.clients
           where id = 'c1000000-0000-4000-8000-000000000002')
      then 'o Lenine tem telefone'
  end;
  if v_falta is not null then
    raise exception 'fixture-fase5: %', v_falta;
  end if;
end
$confere$;
