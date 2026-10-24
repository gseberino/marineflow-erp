-- Cenário do motor da Agenda de Produção (Fase 2, P2): o caso à mão da spec-fase2 §14.2, SINTÉTICO.
-- Roda POR CIMA de fixture-2310.sql (as pessoas de lá: o dono Gustavo, o Roberto e o João), dentro do begin/rollback do
-- teste (supabase/tests/agenda_fase2_motor.sql; o rodar.mjs passa este arquivo em agenda_teste.cenario_motor).
-- NUNCA rodar em produção.
--
-- Hoje: qui 29/10/2026 (o dia do plano). Congelado até sex 30/10. A semana que vem: seg 02/11 é Finados → ter 03 a sáb 07/11.
--
-- Quem vem (padrões ditos pelo dono, um meio-dia por turno):
--   · o dono (Gustavo): seg a sex; sexta à tarde não (escritório);
--   · Roberto: seg a sex, os dois turnos;
--   · João: só à tarde, de ter a sex.
--   (O Mickael não tem padrão: fica fora da grade, como na fixture.)
--
-- As três OS, todas com o sinal pago, aprovadas no mesmo dia (20/10):
--   · A (Antônio, OS-00201): 2 dias; Roberto o dia todo, João à tarde; o dono abre e fecha; material conferido (nada a
--     comprar);
--   · B (Beatriz, OS-00202): diagnóstico, meio dia; Gustavo e Roberto o dia todo; material conferido;
--   · C (Caio, OS-00203): 3 dias com o Roberto; falta um cabo que se compra na Premel (Itajaí: entrega local, 1 dia útil),
--     sem compra combinada → só reserva condicionada.
--
-- O que a agenda_propor('semana') tem de dar (conferido à mão, célula por célula — o teste fixa):
--   A: ter 03 manhã (Roberto + você abrindo), ter 03 tarde (Roberto + João), qua 04 manhã (Roberto), qua 04 tarde
--      (Roberto + João + você fechando). A vem antes de B na fila: as duas são classe 2 e a razão crítica de A
--      (13 du ÷ 2 dias) é menor que a de B (13 ÷ 0,5).
--   B: qui 05 manhã (você o turno inteiro + Roberto). Ter 03 e qua 04 não dão: em cada meio-dia ou você está abrindo
--      ou fechando o A (03 manhã, 04 tarde), ou o Roberto e o João estão no A (03 tarde), ou o João não vem de manhã e não
--      há outro diarista (04 manhã).
--   C: reserva condicionada (compra) de qui 05 à tarde a ter 10/11 de manhã: os 6 meios-dias do Roberto (qui 05 tarde,
--      sex 06 manhã e tarde; seg 09 manhã e tarde; ter 10 manhã), cabendo no teto de 100% de cada semana (8 meios na
--      semana de 02/11: 5 de compromisso + 3 de reserva; 3 na de 09/11); condicao_ate ter 03/11 = 05/11 − (folga 1 +
--      entrega local 1) dias úteis.
--   Nada em seg 02/11 (Finados) nem em qui 29 e sex 30/10 (congelado).
--   Carga da semana de 02/11: Roberto 5 meios de compromisso (teto de 80% = floor(0,8 × 8) = 6); João 2 (floor(0,8 × 4)
--   = 3); você 1 turno inteiro (B) — a abertura e o fechamento não contam.

-- ── 1. A carteira da fixture sai do caminho (o cenário é só A, B e C) ──────────────────────────────────
update public.service_orders
   set status = 'cancelled', cancelled_at = timestamptz '2026-10-28 18:00-03'
 where status in ('open', 'approved', 'scheduled', 'in_progress', 'awaiting_parts', 'awaiting_client');
update public.service_orders
   set quote_status = 'rejected'
 where status = 'draft' and quote_status in ('approved', 'awaiting_deposit');

-- ── 2. Quem vem: os padrões ditos (a semente do histórico sai) ─────────────────────────────────────────
update public.agenda_disponibilidade set substituida_em = timestamptz '2026-10-28 18:00-03' where substituida_em is null;
insert into public.agenda_disponibilidade (payee_id, dias_semana, turno, situacao, origem, nota, criado_por, criado_em) values
  ('bb000000-0000-4000-8000-000000000001', '{1,2,3,4,5}', null,    'disponivel',   'dono', 'você disse', 'aa000000-0000-4000-8000-000000000001', timestamptz '2026-10-28 18:00-03'),
  ('bb000000-0000-4000-8000-000000000001', '{5}',         'tarde', 'indisponivel', 'dono', 'escritório', 'aa000000-0000-4000-8000-000000000001', timestamptz '2026-10-28 18:00-03'),
  ('bb000000-0000-4000-8000-000000000002', '{1,2,3,4,5}', null,    'disponivel',   'dono', 'você disse', 'aa000000-0000-4000-8000-000000000001', timestamptz '2026-10-28 18:00-03'),
  ('bb000000-0000-4000-8000-000000000003', '{2,3,4,5}',   'tarde', 'disponivel',   'dono', 'você disse', 'aa000000-0000-4000-8000-000000000001', timestamptz '2026-10-28 18:00-03');

-- ── 3. As três OS ──────────────────────────────────────────────────────────────────────────────────────
insert into public.clients (id, type, name) values
  ('c4000000-0000-4000-8000-000000000201', 'individual', 'Antônio'),
  ('c4000000-0000-4000-8000-000000000202', 'individual', 'Beatriz'),
  ('c4000000-0000-4000-8000-000000000203', 'individual', 'Caio');
insert into public.vessels (id, client_id, name, asset_type) values
  ('f4000000-0000-4000-8000-000000000201', 'c4000000-0000-4000-8000-000000000201', 'Lancha A', 'Lancha'),
  ('f4000000-0000-4000-8000-000000000202', 'c4000000-0000-4000-8000-000000000202', 'Lancha B', 'Lancha'),
  ('f4000000-0000-4000-8000-000000000203', 'c4000000-0000-4000-8000-000000000203', 'Lancha C', 'Lancha');
insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type,
                                   created_at, updated_at, converted_to_os_at, grand_total)
values
  ('05000000-0000-4000-8000-000000000201', 'OS-00201', 'c4000000-0000-4000-8000-000000000201', 'f4000000-0000-4000-8000-000000000201',
   'approved', 'approved', 'repair', timestamptz '2026-10-15 12:00-03', timestamptz '2026-10-20 12:00-03', timestamptz '2026-10-20 12:00-03', 2160),
  ('05000000-0000-4000-8000-000000000202', 'OS-00202', 'c4000000-0000-4000-8000-000000000202', 'f4000000-0000-4000-8000-000000000202',
   'approved', 'approved', 'diagnosis', timestamptz '2026-10-15 12:00-03', timestamptz '2026-10-20 12:00-03', timestamptz '2026-10-20 12:00-03', 250),
  ('05000000-0000-4000-8000-000000000203', 'OS-00203', 'c4000000-0000-4000-8000-000000000203', 'f4000000-0000-4000-8000-000000000203',
   'approved', 'approved', 'repair', timestamptz '2026-10-15 12:00-03', timestamptz '2026-10-20 12:00-03', timestamptz '2026-10-20 12:00-03', 2160);
-- Linhas de catálogo (não são texto livre: não pedem "tem peça embutida?").
insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                           unit_price_snapshot, line_total, created_at)
values
  (md5('cen:servico:201')::uuid, '05000000-0000-4000-8000-000000000201', '5e000000-0000-4000-8000-000000000003',
   'Revisão do sistema elétrico', 'unit', 1, 2160, 2160, timestamptz '2026-10-15 12:00-03'),
  (md5('cen:servico:202')::uuid, '05000000-0000-4000-8000-000000000202', '5e000000-0000-4000-8000-000000000005',
   'Visita técnica — diagnóstico', 'visit', 1, 250, 250, timestamptz '2026-10-15 12:00-03'),
  (md5('cen:servico:203')::uuid, '05000000-0000-4000-8000-000000000203', '5e000000-0000-4000-8000-000000000003',
   'Revisão do sistema elétrico', 'unit', 1, 2160, 2160, timestamptz '2026-10-15 12:00-03');
insert into public.receivables (id, client_id, service_order_id, description, issue_date, due_date, amount, status,
                                paid_amount, balance_amount, is_deposit)
select md5('cen:sinal:' || n)::uuid, ('c4000000-0000-4000-8000-000000000' || n)::uuid, ('05000000-0000-4000-8000-000000000' || n)::uuid,
       'Sinal OS-00' || n, date '2026-10-20', date '2026-10-20', 500, 'paid', 500, 0, true
  from (values ('201'), ('202'), ('203')) v(n);

-- ── 4. O que o dono disse de cada uma ──────────────────────────────────────────────────────────────────
insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, dono_presenca,
                                    material_conferido_em, trecho, atualizado_por)
values
  ('05000000-0000-4000-8000-000000000201', 2, 'dono', timestamptz '2026-10-28 18:00-03', 'abre_e_fecha',
   timestamptz '2026-10-28 18:00-03', 'o Antônio são dois dias com o Roberto, o João ajuda à tarde, eu abro e fecho; não tem peça',
   'aa000000-0000-4000-8000-000000000001'),
  ('05000000-0000-4000-8000-000000000202', 0.5, 'dono', timestamptz '2026-10-28 18:00-03', null,
   timestamptz '2026-10-28 18:00-03', 'a Beatriz é meio dia de diagnóstico, eu e o Roberto; não tem peça',
   'aa000000-0000-4000-8000-000000000001'),
  ('05000000-0000-4000-8000-000000000203', 3, 'dono', timestamptz '2026-10-28 18:00-03', null,
   null, 'o Caio são três dias com o Roberto', 'aa000000-0000-4000-8000-000000000001');
insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos) values
  ('05000000-0000-4000-8000-000000000201', 'bb000000-0000-4000-8000-000000000002', 'dia'),
  ('05000000-0000-4000-8000-000000000201', 'bb000000-0000-4000-8000-000000000003', 'tarde'),
  ('05000000-0000-4000-8000-000000000202', 'bb000000-0000-4000-8000-000000000001', 'dia'),
  ('05000000-0000-4000-8000-000000000202', 'bb000000-0000-4000-8000-000000000002', 'dia'),
  ('05000000-0000-4000-8000-000000000203', 'bb000000-0000-4000-8000-000000000002', 'dia');
-- C: o cabo falta e é da Premel (o dono disse), sem dia de compra.
insert into public.os_material (id, service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico,
                                situacao, fonte, fornecedor_id, trecho, conferido_em, atualizado_por)
values ('a4000000-0000-4000-8000-000000000203', '05000000-0000-4000-8000-000000000203', 'dono', 'Cabo de bateria 25mm',
        1, 0, true, 'falta', 'dono', 'dd000000-0000-4000-8000-000000000001', 'falta o cabo de 25, compro na Premel',
        timestamptz '2026-10-28 18:00-03', 'aa000000-0000-4000-8000-000000000001');
