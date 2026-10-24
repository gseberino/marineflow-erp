-- Fixture da bancada da Agenda de Produção: a carteira de 23/10/2026, SINTÉTICA.
-- Espelho do que os SELECTs de 23/10 mostraram em produção (scratchpad agenda-pesquisa/sql: g01, g04, g05, g06,
-- g09, g11, g12, g14, g15, f01b, f04, f05) — mesmos números de OS, status, datas, valores das linhas e datas das
-- diárias. Só primeiros nomes; nenhum documento, telefone, e-mail ou endereço real; ids inventados.
--
-- Carregada por scripts/bancada-agenda/bancada.mjs (criarBancada({ fixture: true })), depois das migrations.
-- NUNCA rodar em produção.
--
-- Carteira (11 itens): OS-00069 Vanderlei · OS-00074 Lenine · OS-00100 Giancarlo · OS-00104 Flávio ·
-- OS-00112 Nelson · OS-00096 Rodrigo · ORÇ-00083 Robson · ORÇ-00095 MP · OS-00032 e OS-00033 Kalmar ·
-- OS-00076 Rodrigo. Fora dela: ORÇ-00119 (César – Palazzo, enviado), ORÇ-00114/00115 (César, rascunho) e a
-- OS-00050 (Kalmar, concluída na mesma marina do Lenine: a marina "já conhecida").
-- Equipe: Roberto (27 diárias de 07/09 a 17/10), João (desde 29/09, meias de 06 a 15/10, falta em 05/10),
-- Mickael (última diária 18/09, faltas até 29/09). Nenhuma diária depois de sáb 17/10.

-- ── Interruptor do estoque v2 (o gatilho das peças reserva por ele) ────────────────────────────────────
insert into public.app_settings (key, value) values ('stock_model_v2', 'on') on conflict (key) do update set value = 'on';

-- ── Pessoas ─────────────────────────────────────────────────────────────────────────────────────────────
insert into public.app_users (id, full_name, email, role, active) values
  ('aa000000-0000-4000-8000-000000000001', 'Gustavo', 'gustavo@bancada.invalid', 'admin', true),
  ('aa000000-0000-4000-8000-000000000002', 'Roberto', 'roberto@bancada.invalid', 'technician', false),
  ('aa000000-0000-4000-8000-000000000003', 'Mickael', 'mickael@bancada.invalid', 'technician', false);

insert into public.payees (id, name, kind, active, app_user_id) values
  ('bb000000-0000-4000-8000-000000000001', 'Gustavo', 'socio',     true, 'aa000000-0000-4000-8000-000000000001'),
  ('bb000000-0000-4000-8000-000000000002', 'Roberto', 'prestador', true, 'aa000000-0000-4000-8000-000000000002'),
  ('bb000000-0000-4000-8000-000000000003', 'João',    'prestador', true, null),
  ('bb000000-0000-4000-8000-000000000004', 'Mickael', 'prestador', true, 'aa000000-0000-4000-8000-000000000003');

insert into public.work_profiles (id, payee_id, tipo_vinculo, modo_pagamento, valor_diaria, vigencia_inicio) values
  ('cc000000-0000-4000-8000-000000000002', 'bb000000-0000-4000-8000-000000000002', 'diarista', 'diaria', 200, '2026-08-23'),
  ('cc000000-0000-4000-8000-000000000003', 'bb000000-0000-4000-8000-000000000003', 'diarista', 'diaria', 200, '2026-09-29'),
  ('cc000000-0000-4000-8000-000000000004', 'bb000000-0000-4000-8000-000000000004', 'diarista', 'diaria', 200, '2026-08-23');

-- As datas exatas de g14: "m" = meia, "F" = falta.
insert into public.work_shifts (id, work_profile_id, data, tipo, fracao, valor_diaria, origem, status,
                                registrado_por, aprovado_por, aprovado_em)
select md5('ws:' || d.perfil || ':' || d.dia)::uuid, d.perfil::uuid, d.dia::date,
       case when d.marca = 'F' then 'falta' else 'diaria' end,
       case d.marca when 'F' then 0 when 'm' then 0.5 else 1 end,
       200, 'painel', 'aprovado',
       'aa000000-0000-4000-8000-000000000001', 'aa000000-0000-4000-8000-000000000001',
       (d.dia || ' 20:00-03')::timestamptz
  from (values
    -- Roberto
    ('cc000000-0000-4000-8000-000000000002', '2026-09-07', ''), ('cc000000-0000-4000-8000-000000000002', '2026-09-08', ''),
    ('cc000000-0000-4000-8000-000000000002', '2026-09-09', ''), ('cc000000-0000-4000-8000-000000000002', '2026-09-10', ''),
    ('cc000000-0000-4000-8000-000000000002', '2026-09-11', ''), ('cc000000-0000-4000-8000-000000000002', '2026-09-15', ''),
    ('cc000000-0000-4000-8000-000000000002', '2026-09-16', ''), ('cc000000-0000-4000-8000-000000000002', '2026-09-17', ''),
    ('cc000000-0000-4000-8000-000000000002', '2026-09-18', ''), ('cc000000-0000-4000-8000-000000000002', '2026-09-23', ''),
    ('cc000000-0000-4000-8000-000000000002', '2026-09-24', ''), ('cc000000-0000-4000-8000-000000000002', '2026-09-25', ''),
    ('cc000000-0000-4000-8000-000000000002', '2026-09-28', ''), ('cc000000-0000-4000-8000-000000000002', '2026-09-29', ''),
    ('cc000000-0000-4000-8000-000000000002', '2026-09-30', ''), ('cc000000-0000-4000-8000-000000000002', '2026-10-01', ''),
    ('cc000000-0000-4000-8000-000000000002', '2026-10-02', ''), ('cc000000-0000-4000-8000-000000000002', '2026-10-05', ''),
    ('cc000000-0000-4000-8000-000000000002', '2026-10-06', ''), ('cc000000-0000-4000-8000-000000000002', '2026-10-07', ''),
    ('cc000000-0000-4000-8000-000000000002', '2026-10-08', ''), ('cc000000-0000-4000-8000-000000000002', '2026-10-09', ''),
    ('cc000000-0000-4000-8000-000000000002', '2026-10-13', ''), ('cc000000-0000-4000-8000-000000000002', '2026-10-14', ''),
    ('cc000000-0000-4000-8000-000000000002', '2026-10-15', ''), ('cc000000-0000-4000-8000-000000000002', '2026-10-16', ''),
    ('cc000000-0000-4000-8000-000000000002', '2026-10-17', ''),
    -- João
    ('cc000000-0000-4000-8000-000000000003', '2026-09-29', ''), ('cc000000-0000-4000-8000-000000000003', '2026-09-30', ''),
    ('cc000000-0000-4000-8000-000000000003', '2026-10-01', ''), ('cc000000-0000-4000-8000-000000000003', '2026-10-05', 'F'),
    ('cc000000-0000-4000-8000-000000000003', '2026-10-06', 'm'), ('cc000000-0000-4000-8000-000000000003', '2026-10-07', 'm'),
    ('cc000000-0000-4000-8000-000000000003', '2026-10-08', 'm'), ('cc000000-0000-4000-8000-000000000003', '2026-10-09', 'm'),
    ('cc000000-0000-4000-8000-000000000003', '2026-10-14', 'm'), ('cc000000-0000-4000-8000-000000000003', '2026-10-15', 'm'),
    ('cc000000-0000-4000-8000-000000000003', '2026-10-16', ''), ('cc000000-0000-4000-8000-000000000003', '2026-10-17', ''),
    -- Mickael
    ('cc000000-0000-4000-8000-000000000004', '2026-09-14', ''), ('cc000000-0000-4000-8000-000000000004', '2026-09-16', ''),
    ('cc000000-0000-4000-8000-000000000004', '2026-09-17', ''), ('cc000000-0000-4000-8000-000000000004', '2026-09-18', ''),
    ('cc000000-0000-4000-8000-000000000004', '2026-09-19', 'F'), ('cc000000-0000-4000-8000-000000000004', '2026-09-21', 'F'),
    ('cc000000-0000-4000-8000-000000000004', '2026-09-22', 'F'), ('cc000000-0000-4000-8000-000000000004', '2026-09-23', 'F'),
    ('cc000000-0000-4000-8000-000000000004', '2026-09-24', 'F'), ('cc000000-0000-4000-8000-000000000004', '2026-09-25', 'F'),
    ('cc000000-0000-4000-8000-000000000004', '2026-09-28', 'F'), ('cc000000-0000-4000-8000-000000000004', '2026-09-29', 'F')
  ) as d(perfil, dia, marca);

-- ── Fornecedores ────────────────────────────────────────────────────────────────────────────────────────
insert into public.suppliers (id, name, trade_name, city, state, active) values
  ('dd000000-0000-4000-8000-000000000001', 'PREMEL MAT. ELETRICOS LTDA', null, 'Itajaí', 'SC', true),
  ('dd000000-0000-4000-8000-000000000002', 'KAMELL COMERCIO GLOBAL LTDA', 'KAMELL COMERCIO GLOBAL', 'Vila Velha', 'ES', true),
  ('dd000000-0000-4000-8000-000000000003', 'Kamell Comercio Global', null, 'Itajaí', 'SC', true),
  ('dd000000-0000-4000-8000-000000000004', 'Mateus Honório', null, null, null, true);

-- ── Clientes, unidades e marina ─────────────────────────────────────────────────────────────────────────
insert into public.marinas (id, name, city, state) values
  ('ee000000-0000-4000-8000-000000000001', 'Marina de Itajaí', 'Itajaí', 'SC');

insert into public.clients (id, type, name) values
  ('c1000000-0000-4000-8000-000000000001', 'individual', 'Vanderlei'),
  ('c1000000-0000-4000-8000-000000000002', 'individual', 'LENINE'),
  ('c1000000-0000-4000-8000-000000000003', 'individual', 'Giancarlo'),
  ('c1000000-0000-4000-8000-000000000004', 'individual', 'Flávio'),
  ('c1000000-0000-4000-8000-000000000005', 'individual', 'Nelson'),
  ('c1000000-0000-4000-8000-000000000006', 'individual', 'Rodrigo'),
  ('c1000000-0000-4000-8000-000000000007', 'individual', 'ROBSON'),
  ('c1000000-0000-4000-8000-000000000008', 'company',    'MP MOTOR HOMES'),
  ('c1000000-0000-4000-8000-000000000009', 'company',    'KALMAR PERSONAL BOATS'),
  ('c1000000-0000-4000-8000-000000000010', 'individual', 'César – Palazzo'),
  ('c1000000-0000-4000-8000-000000000011', 'individual', 'César');

insert into public.vessels (id, client_id, marina_id, name, asset_type) values
  ('f1000000-0000-4000-8000-000000000001', 'c1000000-0000-4000-8000-000000000001', null, 'Mar Azul', 'Lancha'),
  ('f1000000-0000-4000-8000-000000000002', 'c1000000-0000-4000-8000-000000000002', 'ee000000-0000-4000-8000-000000000001', 'Brisa', 'Lancha'),
  ('f1000000-0000-4000-8000-000000000003', 'c1000000-0000-4000-8000-000000000003', null, 'Motorhome', 'Motorhome'),
  ('f1000000-0000-4000-8000-000000000004', 'c1000000-0000-4000-8000-000000000004', null, 'Lancha', 'Lancha'),
  ('f1000000-0000-4000-8000-000000000005', 'c1000000-0000-4000-8000-000000000005', null, 'Veleiro', 'Veleiro'),
  ('f1000000-0000-4000-8000-000000000006', 'c1000000-0000-4000-8000-000000000006', null, 'Lancha', 'Lancha'),
  ('f1000000-0000-4000-8000-000000000007', 'c1000000-0000-4000-8000-000000000007', null, 'Motorhome', 'Motorhome'),
  ('f1000000-0000-4000-8000-000000000008', 'c1000000-0000-4000-8000-000000000008', null, 'Motorhome NVT', 'Motorhome'),
  ('f1000000-0000-4000-8000-000000000009', 'c1000000-0000-4000-8000-000000000009', 'ee000000-0000-4000-8000-000000000001', 'Kalmar 40', 'Lancha'),
  ('f1000000-0000-4000-8000-000000000010', 'c1000000-0000-4000-8000-000000000010', null, 'Palazzo', 'Lancha'),
  ('f1000000-0000-4000-8000-000000000011', 'c1000000-0000-4000-8000-000000000011', null, 'Lancha', 'Lancha');

-- ── Catálogo: serviços e produtos ───────────────────────────────────────────────────────────────────────
insert into public.services (id, name, billing_unit, default_price) values
  ('5e000000-0000-4000-8000-000000000001', 'Instalação de carregador DC-DC e proteções', 'unit', 5600),
  ('5e000000-0000-4000-8000-000000000002', 'Mão de obra técnica', 'hour', 200),
  ('5e000000-0000-4000-8000-000000000003', 'Revisão do sistema elétrico', 'unit', 2160),
  ('5e000000-0000-4000-8000-000000000004', 'Integração do sistema de lítio', 'unit', 3100),
  ('5e000000-0000-4000-8000-000000000005', 'Visita técnica — diagnóstico', 'visit', 250),
  ('5e000000-0000-4000-8000-000000000006', 'Reparo do sistema elétrico', 'unit', 11300),
  ('5e000000-0000-4000-8000-000000000007', 'Instalação de claraboia', 'unit', 1480),
  ('5e000000-0000-4000-8000-000000000008', 'Testes finais e entrega', 'unit', 1200),
  ('5e000000-0000-4000-8000-000000000009', 'Instalação de banco de baterias de lítio', 'unit', 4142.60),
  ('5e000000-0000-4000-8000-000000000010', 'Serviço elétrico', 'unit', 320);

insert into public.products (id, name, stock_quantity, cost_price, sale_price, supplier_id) values
  ('b1000000-0000-4000-8000-000000000001', 'Kit Cabos/ Conectores/ Terminais do Novo Sistema', 0, 360, 600, null),
  ('b1000000-0000-4000-8000-000000000002', 'Porta Fusível MIDI c/ Capa Proteção', 0, 25, 45.05, null),
  ('b1000000-0000-4000-8000-000000000003', 'KIT CABOS ELETRICOS P/ DC-DC 12V 60A', 0, 420, 695, null),
  ('b1000000-0000-4000-8000-000000000004', 'Cabos Elétricos Diversos (2,5mm / 4,0mm / 6,0mm)', 0, 210, 350, null),
  ('b1000000-0000-4000-8000-000000000005', 'KIT Cabos Comunicação e Energia para Lítio', 0, 900, 1521.49, null),
  ('b1000000-0000-4000-8000-000000000006', 'CENTRAL DE CONTROLE CERBO GX VICTRON ENERGY. - UTILIZADO PARA MONITORAMENTO DE', 0, 1900, 3054.44, 'dd000000-0000-4000-8000-000000000002'),
  ('b1000000-0000-4000-8000-000000000007', 'Orion-Tr Smart 12/12-30A Victron (USADO)', 0, 900, 1500, null),
  ('b1000000-0000-4000-8000-000000000008', 'Painel Touch de Monitoramento e Controle de Energia – HBR 7"', 0, 1250, 2088.30, null),
  ('b1000000-0000-4000-8000-000000000009', 'Claraboia de Teto Com LED - Blackout e Tela Mosquiteiro', 0, 2000, 3307.70, null),
  ('b1000000-0000-4000-8000-000000000010', 'Sikaflex 221 (selante de vedação)', -2, 95, 163.46, null),
  ('b1000000-0000-4000-8000-000000000011', 'Bateria de lítio 12V 100Ah', 0, 2000, 3200, null),
  ('b1000000-0000-4000-8000-000000000012', 'Carregador Victron Blue Smart IP22 12/30', 0, 700, 1100, null),
  ('b1000000-0000-4000-8000-000000000013', 'Disjuntor DC 100A', 0, 250, 420.36, null),
  ('b1000000-0000-4000-8000-000000000014', 'Barramento Victron Lynx Distributor', 0, 350, 560, null),
  ('b1000000-0000-4000-8000-000000000015', 'Cabos e terminais de bateria', 0, 110, 186, null),
  ('b1000000-0000-4000-8000-000000000016', 'Inversor 12V 1000W', 0, 350, 570.48, null),
  ('b1000000-0000-4000-8000-000000000017', 'Tomada USB 12V', 0, 80, 133.40, null);

-- ── Ordens de serviço e orçamentos ──────────────────────────────────────────────────────────────────────
-- id = '05000000-0000-4000-8000-' + o número com 12 dígitos.
insert into public.service_orders (id, service_order_number, client_id, vessel_id, marina_id, status, quote_status,
  service_type, created_at, updated_at, converted_to_os_at, signed_at, scheduled_start_at, scheduled_end_at, grand_total)
values
  ('05000000-0000-4000-8000-000000000069', 'OS-00069', 'c1000000-0000-4000-8000-000000000001', 'f1000000-0000-4000-8000-000000000001', null,
   'open', 'approved', 'repair', '2026-07-24 12:00-03', '2026-10-03 12:00-03', '2026-07-29 12:00-03', null, null, null, 7605.40),
  ('05000000-0000-4000-8000-000000000074', 'OS-00074', 'c1000000-0000-4000-8000-000000000002', 'f1000000-0000-4000-8000-000000000002', 'ee000000-0000-4000-8000-000000000001',
   'open', 'approved', 'repair', '2026-08-05 12:00-03', '2026-10-13 12:00-03', '2026-08-12 12:00-03', null, null, null, 4560),
  ('05000000-0000-4000-8000-000000000100', 'OS-00100', 'c1000000-0000-4000-8000-000000000003', 'f1000000-0000-4000-8000-000000000003', null,
   'open', 'approved', 'repair', '2026-09-16 12:00-03', '2026-10-13 12:00-03', '2026-10-13 12:00-03', null, null, null, 5739),
  ('05000000-0000-4000-8000-000000000104', 'OS-00104', 'c1000000-0000-4000-8000-000000000004', 'f1000000-0000-4000-8000-000000000004', null,
   'awaiting_parts', 'approved', 'repair', '2026-09-22 12:00-03', '2026-10-22 12:00-03', '2026-09-23 12:00-03', null,
   '2026-10-06 06:00-03', '2026-10-08 18:00-03', 2760),
  ('05000000-0000-4000-8000-000000000112', 'OS-00112', 'c1000000-0000-4000-8000-000000000005', 'f1000000-0000-4000-8000-000000000005', null,
   'awaiting_parts', 'sent', 'repair', '2026-10-04 12:00-03', '2026-10-13 12:00-03', '2026-10-06 12:00-03', null, null, null, 11264.23),
  ('05000000-0000-4000-8000-000000000096', 'OS-00096', 'c1000000-0000-4000-8000-000000000006', 'f1000000-0000-4000-8000-000000000006', null,
   'approved', 'rejected', 'repair', '2026-09-11 12:00-03', '2026-10-16 12:00-03', '2026-10-16 12:00-03', null, null, null, 250),
  ('05000000-0000-4000-8000-000000000083', 'ORÇ-00083', 'c1000000-0000-4000-8000-000000000007', 'f1000000-0000-4000-8000-000000000007', null,
   'draft', 'approved', 'repair', '2026-08-19 12:00-03', '2026-10-13 12:00-03', null, '2026-08-23 12:00-03', null, null, 5151.16),
  ('05000000-0000-4000-8000-000000000095', 'ORÇ-00095', 'c1000000-0000-4000-8000-000000000008', 'f1000000-0000-4000-8000-000000000008', null,
   'draft', 'awaiting_deposit', 'repair', '2026-09-09 12:00-03', '2026-10-06 12:00-03', null, null, null, null, 14461),
  ('05000000-0000-4000-8000-000000000032', 'OS-00032', 'c1000000-0000-4000-8000-000000000009', 'f1000000-0000-4000-8000-000000000009', 'ee000000-0000-4000-8000-000000000001',
   'awaiting_client', 'approved', 'installation', '2026-05-15 12:00-03', '2026-09-23 12:00-03', '2026-05-15 12:00-03', null, null, null, 14000),
  ('05000000-0000-4000-8000-000000000033', 'OS-00033', 'c1000000-0000-4000-8000-000000000009', 'f1000000-0000-4000-8000-000000000009', 'ee000000-0000-4000-8000-000000000001',
   'awaiting_client', 'approved', 'repair', '2026-05-15 12:00-03', '2026-09-29 12:00-03', '2026-05-15 12:00-03', '2026-05-22 12:00-03',
   '2026-05-25 05:30-03', '2026-05-29 14:00-03', 11300),
  ('05000000-0000-4000-8000-000000000076', 'OS-00076', 'c1000000-0000-4000-8000-000000000006', 'f1000000-0000-4000-8000-000000000006', null,
   'awaiting_client', 'draft', 'repair', '2026-08-07 12:00-03', '2026-08-08 12:00-03', '2026-08-07 12:00-03', null, null, null, 740),
  ('05000000-0000-4000-8000-000000000119', 'ORÇ-00119', 'c1000000-0000-4000-8000-000000000010', 'f1000000-0000-4000-8000-000000000010', null,
   'draft', 'sent', 'installation', '2026-10-15 12:00-03', '2026-10-15 12:00-03', null, null, null, null, 9608.96),
  ('05000000-0000-4000-8000-000000000114', 'ORÇ-00114', 'c1000000-0000-4000-8000-000000000011', 'f1000000-0000-4000-8000-000000000011', null,
   'draft', 'draft', 'repair', '2026-10-08 12:00-03', '2026-10-08 12:00-03', null, null, null, null, 2022.61),
  ('05000000-0000-4000-8000-000000000115', 'ORÇ-00115', 'c1000000-0000-4000-8000-000000000011', 'f1000000-0000-4000-8000-000000000011', null,
   'draft', 'draft', 'repair', '2026-10-08 12:30-03', '2026-10-08 12:30-03', null, null, null, null, 453.40),
  ('05000000-0000-4000-8000-000000000050', 'OS-00050', 'c1000000-0000-4000-8000-000000000009', 'f1000000-0000-4000-8000-000000000009', 'ee000000-0000-4000-8000-000000000001',
   'completed', 'approved', 'repair', '2026-06-10 12:00-03', '2026-07-02 12:00-03', '2026-06-10 12:00-03', null,
   '2026-06-29 08:00-03', '2026-07-01 17:00-03', 3000);

insert into public.service_order_technicians (service_order_id, user_id) values
  ('05000000-0000-4000-8000-000000000104', 'aa000000-0000-4000-8000-000000000002'),
  ('05000000-0000-4000-8000-000000000033', 'aa000000-0000-4000-8000-000000000001');

-- Linhas de serviço (g04/g05): catálogo com service_id; texto livre com service_id nulo. created_at em ordem.
insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot,
  quantity, unit_price_snapshot, line_total, created_at)
select md5('servico:' || l.os || ':' || l.n)::uuid, ('05000000-0000-4000-8000-' || lpad(l.os, 12, '0'))::uuid,
       l.servico::uuid, l.nome, l.unidade, l.qtd, l.preco, l.total,
       '2026-07-01 12:00-03'::timestamptz + make_interval(secs => l.n)
  from (values
    ('69', 1, '5e000000-0000-4000-8000-000000000001', 'Instalação de carregador DC-DC e proteções', 'unit', 1, 5600, 5600),
    ('74', 1, '5e000000-0000-4000-8000-000000000002', 'Mão de obra técnica', 'hour', 12, 200, 2400),
    ('74', 2, '5e000000-0000-4000-8000-000000000003', 'Revisão do sistema elétrico', 'unit', 1, 2160, 2160),
    ('100', 1, null, 'Realocação do banco de baterias', 'visit', 1, 1135, 1135),
    ('100', 2, null, 'Realocação e ligação dos controladores solares', 'visit', 1, 920, 920),
    ('100', 3, null, 'Barramento e proteções do sistema de corrente contínua', 'visit', 1, 2804, 2804),
    ('100', 4, null, 'Migração dos circuitos de iluminação para o quadro 12V', 'visit', 1, 605, 605),
    ('100', 5, null, 'Instalação de autotransformador 220/110V', 'visit', 1, 275, 275),
    ('104', 1, null, 'Conversão do sistema de refrigeração para 12V — Refrigerador Consul CRC28FB', 'unit', 1, 2500, 2500),
    ('104', 2, null, 'Diagnóstico de vazamento do sistema de água pressurizado', 'hour', 1, 260, 260),
    ('104', 3, null, 'Substituição da tampa da boia (valor a definir — pendente análise de tempo e cotação da peça)', 'unit', 1, 0, 0),
    ('112', 1, '5e000000-0000-4000-8000-000000000004', 'Integração do sistema de lítio', 'unit', 1, 3100, 3100),
    ('96', 1, '5e000000-0000-4000-8000-000000000005', 'Visita técnica — diagnóstico', 'visit', 1, 250, 250),
    ('83', 1, '5e000000-0000-4000-8000-000000000002', 'Mão de obra técnica', 'hour', 1, 200, 200),
    ('83', 2, '5e000000-0000-4000-8000-000000000007', 'Instalação de claraboia', 'unit', 1, 1480, 1480),
    ('95', 1, null, 'Kit 1 — Iluminação LED', 'unit', 1, 4250, 4250),
    ('95', 2, null, 'Kit 2 — Elétrica Interna', 'unit', 1, 1606, 1606),
    ('95', 3, null, 'Kit 3 — Sistema de Energia', 'unit', 1, 4060, 4060),
    ('95', 4, null, 'Kit 4 — Água e Sanitário', 'unit', 1, 2455, 2455),
    ('95', 5, null, 'Kit 5 — Conectividade Starlink', 'unit', 1, 1390, 1390),
    ('95', 6, null, 'Kit 6 — Cabine e Revestimento', 'unit', 1, 700, 700),
    ('95', 7, null, 'Desmontagem do Gerador (cortesia)', 'unit', 1, 0, 0),
    ('32', 1, null, 'Inspeção inicial, planejamento da instalação e conferência do local', 'visit', 1, 800, 800),
    ('32', 2, null, 'Posicionamento, alinhamento, base, coxins e fixação do gerador', 'visit', 1, 2400, 2400),
    ('32', 3, null, 'Instalação hidráulica/mecânica de água salgada, mangueiras, registros, conexões e bomba, se aplicável', 'visit', 1, 2000, 2000),
    ('32', 4, null, 'Instalação de escapamento úmido, waterlock/silencioso, mangueiras, respiro/anti-sifão e saída, se necessário', 'visit', 1, 2000, 2000),
    ('32', 5, null, 'Sistema de combustível diesel: alimentação, retorno, filtros, válvulas, mangueiras e suportação', 'visit', 1, 1600, 1600),
    ('32', 6, null, 'Sistema elétrico DC: bateria, cabos, terminais, proteção, chave geral, aterramento e partida', 'visit', 1, 1600, 1600),
    ('32', 7, null, 'Sistema elétrico AC: disjuntor, transferência, intertravamento, conexão ao quadro e testes', 'visit', 1, 2000, 2000),
    ('32', 8, null, 'Organização, documentação, lista de materiais pendentes e entrega técnica', 'visit', 1, 400, 400),
    ('32', 9, '5e000000-0000-4000-8000-000000000008', 'Testes finais e entrega', 'unit', 1, 1200, 1200),
    ('33', 1, '5e000000-0000-4000-8000-000000000006', 'Reparo do sistema elétrico', 'unit', 1, 11300, 11300),
    ('76', 1, null, 'Deslocamento técnico', 'hour', 1, 200, 200),
    ('76', 2, null, 'Mão de obra - Substituição de conector e emenda no cabo de dados Starlink', 'hour', 1.5, 200, 300),
    ('76', 3, null, 'Conector de cabo de dados Starlink', 'unit', 1, 240, 240),
    ('119', 1, '5e000000-0000-4000-8000-000000000009', 'Instalação de banco de baterias de lítio', 'unit', 1, 4142.60, 4142.60),
    ('114', 1, '5e000000-0000-4000-8000-000000000010', 'Serviço elétrico', 'unit', 1, 1452.13, 1452.13),
    ('115', 1, '5e000000-0000-4000-8000-000000000010', 'Serviço elétrico', 'unit', 1, 320, 320),
    ('50', 1, '5e000000-0000-4000-8000-000000000006', 'Reparo do sistema elétrico', 'unit', 1, 3000, 3000)
  ) as l(os, n, servico, nome, unidade, qtd, preco, total);

-- Peças (g06/g09): todas sem estoque (o Sikaflex com −2); só o Cerbo GX tem fornecedor (Kamell ES).
insert into public.service_order_parts (id, service_order_id, product_id, quantity, unit_cost_snapshot,
  unit_sale_snapshot, line_total_cost, line_total_sale, created_at)
select md5('peca:' || p.os || ':' || p.n)::uuid, ('05000000-0000-4000-8000-' || lpad(p.os, 12, '0'))::uuid,
       ('b1000000-0000-4000-8000-' || lpad(p.produto, 12, '0'))::uuid, p.qtd,
       pr.cost_price, pr.sale_price, pr.cost_price * p.qtd, p.total,
       '2026-07-01 12:00-03'::timestamptz + make_interval(secs => p.n)
  from (values
    ('69', 1, '1', 1, 600), ('69', 2, '2', 8, 360.40), ('69', 3, '3', 1, 695), ('69', 4, '4', 1, 350),
    ('112', 1, '5', 1, 1521.49), ('112', 2, '6', 1, 3054.44), ('112', 3, '7', 1, 1500), ('112', 4, '8', 1, 2088.30),
    ('83', 1, '9', 1, 3307.70), ('83', 2, '10', 1, 163.46),
    ('119', 1, '11', 1, 3200), ('119', 2, '12', 1, 1100), ('119', 3, '13', 1, 420.36), ('119', 4, '14', 1, 560),
    ('119', 5, '15', 1, 186),
    ('114', 1, '16', 1, 570.48), ('115', 1, '17', 1, 133.40)
  ) as p(os, n, produto, qtd, total)
  join public.products pr on pr.id = ('b1000000-0000-4000-8000-' || lpad(p.produto, 12, '0'))::uuid;

-- OC-00004 (g15): rascunho de 13/10, Mateus Honório, o compressor da OS-00104 em texto livre, 0 de 1 recebido.
insert into public.purchase_orders (id, po_number, status, supplier_id, service_order_id, expected_date, created_at, updated_at)
values ('70000000-0000-4000-8000-000000000004', 'OC-00004', 'draft', 'dd000000-0000-4000-8000-000000000004',
        '05000000-0000-4000-8000-000000000104', null, '2026-10-13 12:00-03', '2026-10-13 12:00-03');
insert into public.purchase_order_items (id, purchase_order_id, product_id, description, quantity, unit_cost, received_qty, created_at)
values ('71000000-0000-4000-8000-000000000001', '70000000-0000-4000-8000-000000000004', null,
        'Compressor 12V de geladeira SS65', 1, 0, 0, '2026-10-13 12:00-03');

-- ── Dinheiro: sinais pagos (g04) e a conta de hoje ──────────────────────────────────────────────────────
insert into public.receivables (id, client_id, service_order_id, description, issue_date, due_date, amount, status,
  paid_amount, balance_amount, is_deposit)
select md5('sinal:' || s.os)::uuid, so.client_id, so.id, 'Sinal ' || so.service_order_number,
       so.converted_to_os_at::date, so.converted_to_os_at::date, s.valor, 'paid', s.valor, 0, true
  from (values ('69', 4500), ('74', 2280), ('100', 2869.50), ('104', 2070), ('112', 7600)) as s(os, valor)
  join public.service_orders so on so.id = ('05000000-0000-4000-8000-' || lpad(s.os, 12, '0'))::uuid;

insert into public.payables (id, description, expense_category, issue_date, due_date, amount, status, paid_amount, balance_amount)
values (md5('conta:luz:2310')::uuid, 'Conta de energia do galpão', 'utilidades', '2026-10-10', '2026-10-23', 312.40,
        'pending', 0, 312.40);

-- ── Pendências do dono: 1 tarefa manual atrasada e 3 da R1 vencendo hoje ────────────────────────────────
insert into public.agenda_tasks (id, title, assignee_user_id, created_by, status, priority, kind, source, due_at,
  related_entity_type, related_entity_id, automation_key, created_at, updated_at)
values
  (md5('tarefa:manual:2010')::uuid, 'Ligar para a marina sobre a vaga do Kalmar', 'aa000000-0000-4000-8000-000000000001',
   'aa000000-0000-4000-8000-000000000001', 'pending', 'normal', 'task', 'manual', '2026-10-20 18:00-03', null, null, null,
   '2026-10-15 10:00-03', '2026-10-15 10:00-03'),
  (md5('tarefa:r1:69')::uuid, 'Agendar OS-00069 — Vanderlei', 'aa000000-0000-4000-8000-000000000001', null, 'pending',
   'high', 'task', 'automation', '2026-10-23 09:00-03', 'service_order', '05000000-0000-4000-8000-000000000069',
   'r1:so:05000000-0000-4000-8000-000000000069', '2026-10-22 09:00-03', '2026-10-22 09:00-03'),
  (md5('tarefa:r1:74')::uuid, 'Agendar OS-00074 — LENINE', 'aa000000-0000-4000-8000-000000000001', null, 'pending',
   'high', 'task', 'automation', '2026-10-23 09:00-03', 'service_order', '05000000-0000-4000-8000-000000000074',
   'r1:so:05000000-0000-4000-8000-000000000074', '2026-10-22 09:00-03', '2026-10-22 09:00-03'),
  (md5('tarefa:r1:100')::uuid, 'Agendar OS-00100 — Giancarlo', 'aa000000-0000-4000-8000-000000000001', null, 'pending',
   'high', 'task', 'automation', '2026-10-23 09:00-03', 'service_order', '05000000-0000-4000-8000-000000000100',
   'r1:so:05000000-0000-4000-8000-000000000100', '2026-10-22 09:00-03', '2026-10-22 09:00-03');

-- ── A semente de disponibilidade (só quando a bancada foi até 20261024160200) ──────────────────────────
do $semente$
begin
  if to_regprocedure('public.agenda_disponibilidade_semear(date)') is not null then
    perform public.agenda_disponibilidade_semear(date '2026-10-23');
  end if;
end
$semente$;
