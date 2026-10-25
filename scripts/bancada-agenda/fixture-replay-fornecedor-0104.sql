-- Replay da conversa do fornecedor da OS-00104 (Flávio) na bancada da Agenda de Produção (Fase 4, P4): o estado de
-- ter 13/10/2026 às 18:00, SINTÉTICO. Roda POR CIMA de fixture-2310.sql, dentro do begin/rollback do teste
-- (supabase/tests/agenda_fase4_detector.sql; o rodar.mjs passa este arquivo em agenda_teste.replay_fornecedor_0104).
-- NUNCA rodar em produção. Só primeiros nomes; o telefone é do tipo "55479000002xx".
--
-- O que aconteceu de verdade (int-compras-prazos.md §4.7, trechos #3 a #10): o dono fechou o compressor com o Mateus
-- Honório pelo WhatsApp, pagou por Pix, a NF veio em PDF e o Mateus avisou "Já foi coletado" às 17:19. A HBR tinha escrito
-- "chega aqui amanha se eles retirarem hoje" às 14:01. A OC-00004 (rascunho, texto livre, sem data) ficou como única
-- marca no sistema; a OS seguiu "aguardando peças" sem previsão. Em 20/10 o Mateus perguntou "Recebeu o compressor?" e
-- ninguém respondeu. A pergunta do replay: com o detector, às 17:19 de 13/10 sai a previsão de qua 14/10 (fonte
-- fornecedor, com os dois trechos)? E o "Recebeu?" de 20/10 vira o "chegou?" uma vez?
--
-- O estado de 13/10, 18:00:
--   · OS-00104 aguardando peças (fixture-2310), a OC-00004 do Mateus criada em 13/10 (rascunho, texto livre, sem
--     expected_date): a linha de material dela nasce pela sincronização de 13/10 — a caminho, fonte oc, comprada em 13/10,
--     sem previsão. É a ÚNICA compra viva do Mateus (casou_por unico);
--   · o Mateus com telefone (o cadastro real não tem cidade nem UF: sem a conversa, a agenda não saberia quando chega);
--   · as mensagens #3 a #10, com os horários reais (Brasília); a de 20/10 também (fica fora da janela até lá).

update public.suppliers set phone = '5547900000201', contact_name = 'Mateus' where id = 'dd000000-0000-4000-8000-000000000004';

update public.service_orders set updated_at = timestamptz '2026-10-13 12:00-03' where id = '05000000-0000-4000-8000-000000000104';

-- A linha do compressor como a sincronização de 13/10 a deixa (a OC-00004 é de 13/10, 12:00).
select set_config('agenda.hoje', '2026-10-13', true);
select public.os_material_sincronizar('05000000-0000-4000-8000-000000000104', date '2026-10-13');
select set_config('agenda.hoje', '', true);

-- A conversa (outbound = a HBR escreveu; inbound = o Mateus).
insert into public.whatsapp_messages (id, direction, phone_normalized, message_type, body, occurred_at, delivery_status) values
  ('d4000000-0000-4000-8000-000000000401', 'outbound', '5547900000201', 'text', 'vamos fechar então',
   timestamptz '2026-10-13 14:01:05-03', 'read'),
  ('d4000000-0000-4000-8000-000000000402', 'outbound', '5547900000201', 'text',
   'voce consegue deixar separado para a transportadora retirar?', timestamptz '2026-10-13 14:01:20-03', 'read'),
  ('d4000000-0000-4000-8000-000000000403', 'outbound', '5547900000201', 'text', 'chega aqui amanha se eles retirarem hoje',
   timestamptz '2026-10-13 14:01:40-03', 'read'),
  ('d4000000-0000-4000-8000-000000000404', 'inbound', '5547900000201', 'text', 'Estou confirmando se tenho disponivel no estoque',
   timestamptz '2026-10-13 14:04:00-03', 'received'),
  ('d4000000-0000-4000-8000-000000000405', 'inbound', '5547900000201', 'text', 'Tenho disponivel',
   timestamptz '2026-10-13 15:08:00-03', 'received'),
  ('d4000000-0000-4000-8000-000000000406', 'inbound', '5547900000201', 'text', 'Vamos emitir a NFe',
   timestamptz '2026-10-13 15:31:00-03', 'received'),
  ('d4000000-0000-4000-8000-000000000407', 'inbound', '5547900000201', 'text', 'Em breve esta pronto para coleta',
   timestamptz '2026-10-13 15:31:30-03', 'received'),
  ('d4000000-0000-4000-8000-000000000408', 'inbound', '5547900000201', 'document', 'NF 1810- HBR.pdf',
   timestamptz '2026-10-13 15:47:00-03', 'received'),
  ('d4000000-0000-4000-8000-000000000409', 'inbound', '5547900000201', 'text', 'Já foi coletado',
   timestamptz '2026-10-13 17:19:00-03', 'received'),
  ('d4000000-0000-4000-8000-000000000410', 'inbound', '5547900000201', 'text', 'Recebeu o compressor?',
   timestamptz '2026-10-20 09:58:00-03', 'received'),
  ('d4000000-0000-4000-8000-000000000411', 'inbound', '5547900000201', 'text', 'Deu tudo certo?',
   timestamptz '2026-10-20 09:58:20-03', 'received');

do $confere$
begin
  if (select count(*) from public.os_material m
       where m.purchase_order_item_id = '71000000-0000-4000-8000-000000000001' and m.situacao = 'a_caminho' and m.fonte = 'oc'
         and m.fornecedor_id = 'dd000000-0000-4000-8000-000000000004' and m.comprado_em = date '2026-10-13'
         and m.previsao_ate is null) <> 1 then
    raise exception 'fixture-replay-fornecedor-0104: a linha do compressor não ficou a caminho pela OC-00004, sem previsão';
  end if;
end
$confere$;
