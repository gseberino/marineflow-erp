-- Espelho de produção da comissão "o maior dos dois" (Agenda de Produção, Fase 3, P5): SÓ NÚMEROS. NUNCA rodar em
-- produção. Roda dentro do begin/rollback de supabase/tests/agenda_fase3_comissao.sql (o rodar.mjs passa este arquivo em
-- agenda_teste.cenario_comissao_2410), por cima da fixture de 23/10 (fixture-2310.sql: o Roberto, o João e o Mickael com
-- perfil de diária; o Gustavo, sócio, sem perfil).
--
-- De onde vêm os números (SELECTs de 24/10/2026, só leitura, scratchpad agenda-pesquisa/sql/):
--   · i04_comissao_base: as 21 OS concluídas ou faturadas de produção — status, payment_status, a data da saída em
--     Brasília, o valor da OS, o que entrou (pagamentos confirmados dos recebíveis vivos) e a data do último, o material ao
--     custo, as despesas e as notas autorizadas ligadas. Nenhuma tem pagamento no cartão (taxa 0);
--   · i09_comissao_diarias: as 56 diárias de produção (todas de 07/09 a 23/10), por primeiro nome, dia, fração, valor da
--     diária, acréscimos e descontos. NENHUMA está ligada a uma OS (work_shift_os vazia, work_shifts.service_order_id nulo).
-- Sem nome de cliente, documento, telefone, descrição de recebível nem id de produção: os ids são md5 do número.
--
-- Como cada OS vira linhas: um recebível com o que entrou (pago) ou com o valor da OS (pendente/pago em parte) e um
-- pagamento confirmado com o que entrou na data do último; uma peça com o material ao custo; a despesa da OS-00105; as notas
-- (nfe + nfse, autorizadas, de produção) da OS-00060 e da OS-00075. O payment_status sai do gatilho de produção
-- (trg_sync_payment_status) e o teste confere que bate com o de i04. A OS-00016 (valor 0, nada recebido) fica sem recebível.
-- As diárias da fixture de 23/10 (todas a R$ 200) saem e entram as 56 de produção.

-- ── A alíquota do Simples (i05: 6,00 na NFS-e; a linha simples_aliquota "6") ─────────────────────────────
insert into public.company_fiscal_settings (legal_name, tax_regime, nfse_total_tax_rate_sn)
values ('Bancada', 'simples', 6.00)
on conflict (singleton_guard) do update set nfse_total_tax_rate_sn = excluded.nfse_total_tax_rate_sn;
insert into public.app_settings (key, value) values ('simples_aliquota', '6')
on conflict (key) do update set value = excluded.value;

-- ── As 21 OS (i04) ──────────────────────────────────────────────────────────────────────────────────────
create temp table _espelho_i04 (
  numero text primary key, status text, payment_status text, saida date, valor numeric, recebido numeric,
  ultimo_pagamento date, material numeric, despesas numeric, notas int
) on commit drop;

insert into _espelho_i04 values
  ('OS-00001',  'invoiced',  'paid',           '2026-04-08', 30398.73,  2000.00, '2026-07-23', 16798.34,    0, 0),
  ('OS-00016',  'completed', 'unpaid',         '2026-06-22',     0.00,     0.00, null,             0.00,    0, 0),
  ('OS-00044',  'invoiced',  'paid',           '2026-06-22',  3000.00,  3000.00, '2026-06-19',   331.00,    0, 0),
  ('OS-00045',  'invoiced',  'unpaid',         '2026-06-22',  1650.00,     0.00, null,             0.00,    0, 0),
  ('OS-00046',  'invoiced',  'partially_paid', '2026-06-22',   520.00,   500.00, '2026-06-09',     0.00,    0, 0),
  ('OS-00047',  'invoiced',  'unpaid',         '2026-06-22',   756.00,     0.00, null,            95.94,    0, 0),
  ('OS-00048',  'invoiced',  'paid',           '2026-06-22',   250.00,  4750.00, '2026-07-28',     0.00,    0, 0),
  ('OS-00034',  'completed', 'paid',           '2026-07-29', 29000.00, 29000.00, '2026-07-20', 13909.43,    0, 0),
  ('OS-00041',  'completed', 'paid',           '2026-07-29',  8573.18,  8573.18, '2026-07-20',  3480.91,    0, 0),
  ('ORÇ-00070', 'completed', 'paid',           '2026-08-04',  5321.36,  5321.36, '2026-07-29',  2900.00,    0, 0),
  ('OS-00073',  'invoiced',  'paid',           '2026-08-04',  1865.47,  1866.00, '2026-07-31',  1354.90,    0, 0),
  ('OS-00060',  'completed', 'paid',           '2026-08-13', 20000.00, 20000.00, '2026-08-13', 10490.50,    0, 2),
  ('OS-00075',  'completed', 'paid',           '2026-08-13',   500.00,   500.00, '2026-08-12',   136.90,    0, 2),
  ('OS-00084',  'completed', 'paid',           '2026-08-21',   591.41,   591.41, '2026-08-21',    83.70,    0, 0),
  ('OS-00105',  'completed', 'paid',           '2026-09-05',     0.00,  3035.00, '2026-09-05',     0.00, 1905, 0),
  ('OS-00094',  'completed', 'paid',           '2026-10-03',  1080.00,  1080.00, '2026-09-08',   273.74,    0, 0),
  ('OS-00038',  'completed', 'unpaid',         '2026-10-13', 16890.00,     0.00, null,             0.00,    0, 0),
  ('OS-00051',  'completed', 'partially_paid', '2026-10-13',  8303.74,  6593.74, '2026-06-22',  3233.65,    0, 0),
  ('OS-00061',  'completed', 'paid',           '2026-10-13',  5640.00,  5000.00, '2026-07-28',     0.00,    0, 0),
  ('OS-00077',  'completed', 'paid',           '2026-10-13',  2520.00,  2520.00, '2026-08-11',  1863.25,    0, 0),
  ('OS-00110',  'completed', 'paid',           '2026-10-13',  5600.00,  5600.00, '2026-10-09',  1592.00,    0, 0);

insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type,
                                   created_at, check_out_at, grand_total)
select md5('espelho:' || e.numero)::uuid, e.numero, 'c1000000-0000-4000-8000-000000000001',
       'f1000000-0000-4000-8000-000000000001', e.status, 'approved', 'repair', ((e.saida - 30) || ' 12:00-03')::timestamptz,
       (e.saida || ' 12:00-03')::timestamptz, e.valor
  from _espelho_i04 e;

-- pago: um recebível com o que entrou; pago em parte ou pendente: o valor da OS, com o que entrou
insert into public.receivables (id, client_id, service_order_id, description, issue_date, due_date, amount, status,
                                paid_amount, balance_amount)
select md5('espelho:rec:' || e.numero)::uuid, 'c1000000-0000-4000-8000-000000000001', md5('espelho:' || e.numero)::uuid,
       'Cobrança — ' || e.numero, coalesce(e.ultimo_pagamento, e.saida), coalesce(e.ultimo_pagamento, e.saida),
       case when e.payment_status = 'paid' then e.recebido else e.valor end,
       case e.payment_status when 'paid' then 'paid' when 'partially_paid' then 'partially_paid' else 'pending' end,
       e.recebido, case when e.payment_status = 'paid' then 0 else e.valor - e.recebido end
  from _espelho_i04 e
 where e.recebido > 0 or e.valor > 0;

insert into public.payments (receivable_id, payment_date, amount, payment_method, status)
select md5('espelho:rec:' || e.numero)::uuid, e.ultimo_pagamento, e.recebido, 'pix', 'confirmed'
  from _espelho_i04 e
 where e.recebido > 0;

insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
                                        line_total_cost, line_total_sale)
select md5('espelho:' || e.numero)::uuid, 'b1000000-0000-4000-8000-000000000004', 1, e.material, e.material,
       e.material, e.material
  from _espelho_i04 e
 where e.material > 0;

insert into public.service_order_expenses (service_order_id, category, description, amount, expense_date)
select md5('espelho:' || e.numero)::uuid, 'outros', 'Despesa da OS', e.despesas, e.saida
  from _espelho_i04 e
 where e.despesas > 0;

insert into public.issued_fiscal_documents (document_type, origin_type, origin_id, status, environment, authorized_at)
select t.tipo, 'service_order', md5('espelho:' || e.numero)::uuid, 'authorized', 'producao', (e.saida || ' 18:00-03')::timestamptz
  from _espelho_i04 e cross join (values ('nfe'), ('nfse')) as t(tipo)
 where e.notas = 2;

-- ── As 56 diárias (i09) ─────────────────────────────────────────────────────────────────────────────────
delete from public.work_shift_os;
delete from public.work_shifts;
update public.work_profiles set valor_diaria = 160 where id = 'cc000000-0000-4000-8000-000000000002';   -- Roberto
update public.work_profiles set valor_diaria = 150 where id = 'cc000000-0000-4000-8000-000000000003';   -- João
update public.work_profiles set valor_diaria = 130 where id = 'cc000000-0000-4000-8000-000000000004';   -- Mickael

-- [R = Roberto, J = João, M = Mickael; dia; fração (0 = falta); valor da diária; acréscimos; descontos]
insert into public.work_shifts (id, work_profile_id, data, tipo, fracao, valor_diaria, extras, descontos, origem, status,
                                registrado_por, aprovado_por, aprovado_em)
select md5('espelho:ws:' || d.quem || ':' || d.dia)::uuid,
       case d.quem when 'R' then 'cc000000-0000-4000-8000-000000000002'::uuid
                   when 'J' then 'cc000000-0000-4000-8000-000000000003'::uuid
                   else 'cc000000-0000-4000-8000-000000000004'::uuid end,
       d.dia::date, case when d.fracao = 0 then 'falta' else 'diaria' end, d.fracao, d.valor, d.extras, d.descontos,
       'importado', 'aprovado', 'aa000000-0000-4000-8000-000000000001', 'aa000000-0000-4000-8000-000000000001',
       (d.dia || ' 20:00-03')::timestamptz
  from (values
    ('R', '2026-09-07', 1.0, 160, 0, 0), ('R', '2026-09-08', 1.0, 160, 0, 0), ('R', '2026-09-09', 1.0, 160, 0, 0), ('R', '2026-09-10', 1.0, 160, 0, 0),
    ('R', '2026-09-11', 1.0, 160, 0, 0), ('M', '2026-09-14', 1.0, 130, 0, 0), ('R', '2026-09-15', 1.0, 160, 0, 0), ('M', '2026-09-16', 1.0, 130, 20, 0),
    ('R', '2026-09-16', 1.0, 160, 20, 0), ('M', '2026-09-17', 1.0, 130, 20, 0), ('R', '2026-09-17', 1.0, 160, 20, 0), ('M', '2026-09-18', 1.0, 130, 20, 100),
    ('R', '2026-09-18', 1.0, 160, 20, 0), ('M', '2026-09-19', 0.0, 130, 0, 0), ('M', '2026-09-21', 0.0, 130, 0, 0), ('M', '2026-09-22', 0.0, 130, 0, 0),
    ('M', '2026-09-23', 0.0, 130, 0, 0), ('R', '2026-09-23', 1.0, 160, 0, 0), ('M', '2026-09-24', 0.0, 130, 0, 0), ('R', '2026-09-24', 1.0, 160, 0, 0),
    ('M', '2026-09-25', 0.0, 130, 0, 0), ('R', '2026-09-25', 1.0, 160, 0, 0), ('M', '2026-09-28', 0.0, 130, 0, 0), ('R', '2026-09-28', 1.0, 160, 0, 0),
    ('J', '2026-09-29', 1.0, 150, 0, 0), ('M', '2026-09-29', 0.0, 130, 0, 0), ('R', '2026-09-29', 1.0, 160, 0, 0), ('J', '2026-09-30', 1.0, 130, 0, 0),
    ('R', '2026-09-30', 1.0, 160, 0, 0), ('J', '2026-10-01', 1.0, 150, 0, 0), ('R', '2026-10-01', 1.0, 160, 0, 0), ('R', '2026-10-02', 1.0, 160, 0, 0),
    ('J', '2026-10-05', 0.0, 150, 0, 0), ('R', '2026-10-05', 1.0, 160, 0, 0), ('J', '2026-10-06', 0.5, 150, 0, 0), ('R', '2026-10-06', 1.0, 160, 0, 0),
    ('J', '2026-10-07', 0.5, 150, 0, 0), ('R', '2026-10-07', 1.0, 160, 0, 0), ('J', '2026-10-08', 0.5, 150, 0, 0), ('R', '2026-10-08', 1.0, 160, 0, 0),
    ('J', '2026-10-09', 0.5, 150, 0, 0), ('R', '2026-10-09', 1.0, 160, 0, 0), ('R', '2026-10-13', 1.0, 160, 0, 0), ('J', '2026-10-14', 0.5, 150, 0, 0),
    ('R', '2026-10-14', 1.0, 160, 0, 0), ('J', '2026-10-15', 0.5, 150, 0, 0), ('R', '2026-10-15', 1.0, 160, 0, 0), ('J', '2026-10-16', 1.0, 150, 0, 20),
    ('R', '2026-10-16', 1.0, 160, 20, 0), ('J', '2026-10-17', 1.0, 150, 0, 0), ('R', '2026-10-17', 1.0, 160, 0, 0), ('R', '2026-10-19', 1.0, 160, 0, 0),
    ('R', '2026-10-20', 1.0, 160, 0, 0), ('R', '2026-10-21', 1.0, 160, 0, 0), ('R', '2026-10-22', 1.0, 160, 0, 0), ('R', '2026-10-23', 0.5, 160, 0, 0)
  ) as d(quem, dia, fracao, valor, extras, descontos);
