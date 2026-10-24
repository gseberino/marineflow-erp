-- Cenário sintético da comissão "o maior dos dois" (Agenda de Produção, Fase 3, P5), NÚMEROS À MÃO. NUNCA rodar em
-- produção. Roda dentro do begin/rollback de supabase/tests/agenda_fase3_comissao.sql (o rodar.mjs passa este arquivo em
-- agenda_teste.cenario_comissao), por cima da fixture de 23/10 (fixture-2310.sql: o Roberto, o João e o Mickael com perfil
-- de diária; o Gustavo é o sócio, sem perfil; as diárias da fixture vão só até sáb 17/10). Ids com o prefixo d5000000 e OS
-- de OS-00501 a OS-00507 (livres nas fixtures e nos testes em 24/10). Só primeiros nomes; nenhum documento.
--
-- Novembro de 2026 (a conta esperada, célula a célula, está no teste, seção S):
--   OS-00501  concluída qui 05/11, paga sex 06/11 no cartão de crédito (R$ 10.000, líquido R$ 9.700: taxa R$ 300);
--             material R$ 1.500 + R$ 499,50; uma nota AUTORIZADA mas de HOMOLOGAÇÃO (não conta). Lucro 7.700,50 →
--             comissão 1.540,10. Dias: Roberto 3 (ter 03, qua 04, metade de qui 05, meia sex 06), João 1 (meias ter 03 e
--             qua 04); a falta do Mickael em qua 04 ligada a ela não leva parte. A divisão 3:1 dá 1.155,08 + 385,03 =
--             1.540,11: a sobra de −0,01 vai à maior parte (Roberto 1.155,07).
--   OS-00502  faturada, concluída seg 09/11, paga no Pix (R$ 5.000; um pagamento CANCELADO de R$ 999 não conta); material
--             R$ 1.200; nota autorizada de produção → imposto 6% = R$ 300. Lucro 3.500 → comissão 700. Dias: Roberto 1,5
--             (metade de qui 05, que tem 2 OS, e seg 09).
--   OS-00503  concluída qui 12/11, paga sex 13/11 (R$ 3.000); material R$ 500; despesa NÃO faturável R$ 250 (deslocamento);
--             uma nota CANCELADA (não conta). Lucro 2.250 → comissão 450, sem dia ligado → "sem dia para dividir".
--   OS-00504  concluída seg 16/11, paga em PARTE (R$ 1.000 de R$ 2.000) → fora; espera o pagamento.
--   OS-00505  concluída qui 29/10 (OUTUBRO), sinal de R$ 2.000 pago ter 20/10 e saldo de R$ 2.000 pago ter 10/11 → conta em
--             NOVEMBRO (o mais tarde dos dois); um recebível CANCELADO com pagamento de R$ 500 não conta. Material R$ 1.000.
--             Lucro 3.000 → comissão 600. Dias: Roberto 1 (qui 29/10).
--   OS-00506  concluída qua 18/11, paga no débito (R$ 1.000, card_fee_percent 1,5 e sem líquido: taxa R$ 15); material
--             R$ 485. Lucro 500 → comissão 100. Dias: Roberto, João e Mickael 1 cada (ter 27/10): 33,33 × 3 = 99,99, a sobra
--             de +0,01 empata e vai ao menor payee_id (Roberto 33,34).
--   OS-00507  concluída qui 19/11 às 22:30 de Brasília (01:30 UTC do dia 20), paga no Pix (R$ 800); material R$ 1.000 →
--             lucro −200, comissão 0 (lucro_negativo).
-- Diárias de novembro: Roberto (R$ 180) ter 03, qua 04, qui 05, meia sex 06, seg 09 e ter 10 (sem OS) = 5,5 → R$ 990;
-- João (R$ 150) meias ter 03 e qua 04 e qui 05 inteira (sem OS) = 2 → R$ 300; Mickael só a falta de qua 04 → R$ 0.
-- A alíquota: company_fiscal_settings 6,00 e a linha simples_aliquota de app_settings "6".

-- ── A alíquota do Simples ───────────────────────────────────────────────────────────────────────────────
insert into public.company_fiscal_settings (legal_name, tax_regime, nfse_total_tax_rate_sn)
values ('Bancada', 'simples', 6.00)
on conflict (singleton_guard) do update set nfse_total_tax_rate_sn = excluded.nfse_total_tax_rate_sn;
insert into public.app_settings (key, value) values ('simples_aliquota', '6')
on conflict (key) do update set value = excluded.value;

-- ── As OS ───────────────────────────────────────────────────────────────────────────────────────────────
insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type,
                                   created_at, check_in_at, check_out_at, grand_total)
values
  ('d5000000-0000-4000-8000-000000000501', 'OS-00501', 'c1000000-0000-4000-8000-000000000001', 'f1000000-0000-4000-8000-000000000001',
   'completed', 'approved', 'repair', '2026-10-01 12:00-03', '2026-11-03 08:00-03', '2026-11-05 17:00-03', 10000),
  ('d5000000-0000-4000-8000-000000000502', 'OS-00502', 'c1000000-0000-4000-8000-000000000001', 'f1000000-0000-4000-8000-000000000001',
   'invoiced', 'approved', 'repair', '2026-10-01 12:00-03', '2026-11-05 08:00-03', '2026-11-09 17:00-03', 5000),
  ('d5000000-0000-4000-8000-000000000503', 'OS-00503', 'c1000000-0000-4000-8000-000000000001', 'f1000000-0000-4000-8000-000000000001',
   'completed', 'approved', 'repair', '2026-10-01 12:00-03', '2026-11-12 08:00-03', '2026-11-12 17:00-03', 3000),
  ('d5000000-0000-4000-8000-000000000504', 'OS-00504', 'c1000000-0000-4000-8000-000000000001', 'f1000000-0000-4000-8000-000000000001',
   'completed', 'approved', 'repair', '2026-10-01 12:00-03', '2026-11-16 08:00-03', '2026-11-16 17:00-03', 2000),
  ('d5000000-0000-4000-8000-000000000505', 'OS-00505', 'c1000000-0000-4000-8000-000000000001', 'f1000000-0000-4000-8000-000000000001',
   'completed', 'approved', 'repair', '2026-10-01 12:00-03', '2026-10-29 08:00-03', '2026-10-29 17:00-03', 4000),
  ('d5000000-0000-4000-8000-000000000506', 'OS-00506', 'c1000000-0000-4000-8000-000000000001', 'f1000000-0000-4000-8000-000000000001',
   'completed', 'approved', 'repair', '2026-10-01 12:00-03', '2026-10-27 08:00-03', '2026-11-18 17:00-03', 1000),
  ('d5000000-0000-4000-8000-000000000507', 'OS-00507', 'c1000000-0000-4000-8000-000000000001', 'f1000000-0000-4000-8000-000000000001',
   'completed', 'approved', 'repair', '2026-10-01 12:00-03', '2026-11-19 08:00-03', '2026-11-19 22:30-03', 800);

-- ── O que entrou ────────────────────────────────────────────────────────────────────────────────────────
-- Recebíveis: [n da OS, sufixo, valor, pago, situação, sinal]. O gatilho trg_sync_payment_status põe o payment_status da OS.
insert into public.receivables (id, client_id, service_order_id, description, issue_date, due_date, amount, status,
                                paid_amount, balance_amount, is_deposit)
select ('d5000000-0000-4000-8000-0000001' || r.os || r.suf)::uuid, 'c1000000-0000-4000-8000-000000000001',
       ('d5000000-0000-4000-8000-000000000' || r.os)::uuid, 'Cobrança — OS-00' || r.os, r.dia::date, r.dia::date,
       r.valor, r.situacao, r.pago, r.valor - r.pago, r.sinal
  from (values
    ('501', '01', 10000, 10000, 'paid', false, '2026-11-06'),
    ('502', '01', 5000, 5000, 'paid', false, '2026-11-09'),
    ('503', '01', 3000, 3000, 'paid', false, '2026-11-13'),
    ('504', '01', 2000, 1000, 'partially_paid', false, '2026-11-16'),
    ('505', '01', 2000, 2000, 'paid', true, '2026-10-20'),
    ('505', '02', 2000, 2000, 'paid', false, '2026-11-10'),
    ('505', '03', 500, 0, 'cancelled', false, '2026-11-10'),
    ('506', '01', 1000, 1000, 'paid', false, '2026-11-18'),
    ('507', '01', 800, 800, 'paid', false, '2026-11-19')
  ) as r(os, suf, valor, pago, situacao, sinal, dia);

insert into public.payments (receivable_id, payment_date, amount, payment_method, card_fee_percent, net_amount, status)
select ('d5000000-0000-4000-8000-0000001' || p.os || p.suf)::uuid, p.dia::date, p.valor, p.meio, p.taxa_pct, p.liquido, p.situacao
  from (values
    ('501', '01', '2026-11-06', 10000, 'credit_card', 0, 9700, 'confirmed'),
    ('502', '01', '2026-11-09', 5000, 'pix', 0, null, 'confirmed'),
    ('502', '01', '2026-11-09', 999, 'pix', 0, null, 'cancelled'),
    ('503', '01', '2026-11-13', 3000, 'pix', 0, null, 'confirmed'),
    ('504', '01', '2026-11-16', 1000, 'pix', 0, null, 'confirmed'),
    ('505', '01', '2026-10-20', 2000, 'pix', 0, null, 'confirmed'),
    ('505', '02', '2026-11-10', 2000, 'pix', 0, null, 'confirmed'),
    ('505', '03', '2026-11-10', 500, 'pix', 0, null, 'confirmed'),
    ('506', '01', '2026-11-18', 1000, 'debit_card', 1.5, null, 'confirmed'),
    ('507', '01', '2026-11-19', 800, 'pix', 0, null, 'confirmed')
  ) as p(os, suf, dia, valor, meio, taxa_pct, liquido, situacao);

-- ── Material ao custo, despesas e notas ─────────────────────────────────────────────────────────────────
insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
                                        line_total_cost, line_total_sale)
select ('d5000000-0000-4000-8000-000000000' || m.os)::uuid, 'b1000000-0000-4000-8000-000000000004', 1, m.custo, m.custo * 2,
       m.custo, m.custo * 2
  from (values ('501', 1500.00), ('501', 499.50), ('502', 1200.00), ('503', 500.00), ('504', 300.00), ('505', 1000.00),
               ('506', 485.00), ('507', 1000.00)) as m(os, custo);

insert into public.service_order_expenses (service_order_id, category, description, amount, expense_date, billable_to_client)
values ('d5000000-0000-4000-8000-000000000503', 'deslocamento', 'Deslocamento até a marina', 250, date '2026-11-12', false);

insert into public.issued_fiscal_documents (document_type, origin_type, origin_id, status, environment, authorized_at)
values
  ('nfse', 'service_order', 'd5000000-0000-4000-8000-000000000502', 'authorized', 'producao', '2026-11-09 18:00-03'),
  ('nfse', 'service_order', 'd5000000-0000-4000-8000-000000000501', 'authorized', 'homologacao', '2026-11-05 18:00-03'),
  ('nfse', 'service_order', 'd5000000-0000-4000-8000-000000000503', 'cancelled', 'producao', null);

-- ── As diárias e o vínculo com as OS ────────────────────────────────────────────────────────────────────
-- [quem, dia, fração (0 = falta), valor da diária, OS ligadas]
create temp table _comissao_dias (perfil uuid, dia date, fracao numeric, valor numeric, os text[]) on commit drop;
insert into _comissao_dias values
  -- Roberto
  ('cc000000-0000-4000-8000-000000000002', '2026-10-27', 1.0, 180, '{506}'),
  ('cc000000-0000-4000-8000-000000000002', '2026-10-29', 1.0, 180, '{505}'),
  ('cc000000-0000-4000-8000-000000000002', '2026-11-03', 1.0, 180, '{501}'),
  ('cc000000-0000-4000-8000-000000000002', '2026-11-04', 1.0, 180, '{501}'),
  ('cc000000-0000-4000-8000-000000000002', '2026-11-05', 1.0, 180, '{501,502}'),
  ('cc000000-0000-4000-8000-000000000002', '2026-11-06', 0.5, 180, '{501}'),
  ('cc000000-0000-4000-8000-000000000002', '2026-11-09', 1.0, 180, '{502}'),
  ('cc000000-0000-4000-8000-000000000002', '2026-11-10', 1.0, 180, '{}'),
  -- João
  ('cc000000-0000-4000-8000-000000000003', '2026-10-27', 1.0, 150, '{506}'),
  ('cc000000-0000-4000-8000-000000000003', '2026-11-03', 0.5, 150, '{501}'),
  ('cc000000-0000-4000-8000-000000000003', '2026-11-04', 0.5, 150, '{501}'),
  ('cc000000-0000-4000-8000-000000000003', '2026-11-05', 1.0, 150, '{}'),
  -- Mickael
  ('cc000000-0000-4000-8000-000000000004', '2026-10-27', 1.0, 130, '{506}'),
  ('cc000000-0000-4000-8000-000000000004', '2026-11-04', 0.0, 130, '{501}');

insert into public.work_shifts (id, work_profile_id, data, tipo, fracao, valor_diaria, origem, status,
                                registrado_por, aprovado_por, aprovado_em)
select md5('comissao:' || d.perfil || ':' || d.dia)::uuid, d.perfil, d.dia,
       case when d.fracao = 0 then 'falta' else 'diaria' end, d.fracao, d.valor, 'painel', 'aprovado',
       'aa000000-0000-4000-8000-000000000001', 'aa000000-0000-4000-8000-000000000001', (d.dia || ' 20:00-03')::timestamptz
  from _comissao_dias d;

insert into public.work_shift_os (shift_id, service_order_id)
select md5('comissao:' || d.perfil || ':' || d.dia)::uuid, ('d5000000-0000-4000-8000-000000000' || o.os)::uuid
  from _comissao_dias d cross join lateral unnest(d.os) as o(os);
