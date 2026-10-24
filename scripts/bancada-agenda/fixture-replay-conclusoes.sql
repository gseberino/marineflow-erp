-- Replay das conclusões reais (Agenda de Produção, Fase 3, P2): as 21 OS concluídas ou faturadas de produção
-- até 2026-10-24, SÓ NÚMEROS. GERADO por scripts/bancada-agenda/gerar-replay-conclusoes.mjs a partir do SELECT
-- scratchpad/agenda-pesquisa/sql/i06_replay_export.sql — não edite à mão: regere.
-- Roda dentro do begin/rollback de supabase/tests/agenda_fase3_replay_conclusoes.sql (o rodar.mjs passa este arquivo em
-- agenda_teste.replay_conclusoes). Só cria duas tabelas temporárias; quem monta as OS na bancada é o teste. NUNCA rodar em
-- produção. Sem nome, documento, telefone, descrição de recebível nem id de produção.

create temp table _replay_os (
  numero text primary key, status text, check_out_at timestamptz, created_at timestamptz, converted_to_os_at timestamptz,
  labor_cost_total numeric, parts_cost_total numeric, operational_cost_total numeric, travel_cost_total numeric,
  subcontract_cost_total numeric, is_travel_billable boolean, discount_amount numeric, tax_amount numeric, grand_total numeric,
  tem_preset boolean, preset_installments jsonb, custom_payment_installments jsonb
) on commit drop;

create temp table _replay_rec (
  numero text not null, n int not null, amount numeric, status text, is_deposit boolean, due_on_completion boolean,
  issue_date date, due_date date, paid_amount numeric, balance_amount numeric, created_at timestamptz,
  primary key (numero, n)
) on commit drop;

insert into _replay_os values
  ('OS-00001', 'invoiced', '2026-04-08T16:44:41.738000Z', '2026-04-07T22:28:52.034802Z', '2026-04-07T22:28:52.034802Z', 130, 29852.63, 0, 16.1, 400, true, 0, 0, 30398.73, false, null, null),
  ('OS-00016', 'completed', '2026-06-22T15:23:40.947000Z', '2026-04-25T19:54:39.986054Z', '2026-04-25T19:54:39.986054Z', 0, 0, 0, 0, 0, true, 0, 0, 0, false, null, null),
  ('OS-00048', 'invoiced', '2026-06-22T15:54:53.717000Z', '2026-06-18T14:52:11.832478Z', '2026-06-18T14:52:11.832478Z', 310, 0, 0, 0, 0, true, 60, 0, 250, false, null, null),
  ('OS-00047', 'invoiced', '2026-06-22T15:55:50.498000Z', '2026-06-18T14:46:21.123018Z', '2026-06-22T15:55:48.781000Z', 575, 181, 0, 0, 0, true, 0, 0, 756, false, null, null),
  ('OS-00046', 'invoiced', '2026-06-22T15:55:56.137000Z', '2026-06-18T14:36:22.531093Z', '2026-06-22T15:55:52.744000Z', 520, 0, 0, 0, 0, true, 0, 0, 520, false, null, null),
  ('OS-00045', 'invoiced', '2026-06-22T15:55:59.245000Z', '2026-06-18T14:28:58.671678Z', '2026-06-22T15:55:57.695000Z', 1650, 0, 0, 0, 0, true, 0, 0, 1650, false, null, null),
  ('OS-00044', 'invoiced', '2026-06-22T15:56:42.049000Z', '2026-06-18T14:14:56.375034Z', '2026-06-22T15:56:40.776000Z', 1950, 1173.4, 0, 0, 0, true, 123.4, 0, 3000, false, null, null),
  ('OS-00034', 'completed', '2026-07-29T14:53:40.187000Z', '2026-05-15T15:56:09.023025Z', '2026-06-22T15:57:01.203000Z', 5500, 27139.73, 0, 0, 0, true, 3639.73, 0, 29000, true, '[{"days_after_approval":0,"expenses_pct":100,"label":"Sinal","parts_pct":100,"services_pct":50,"tipo":"aprovacao"},{"days_after_approval":0,"expenses_pct":0,"label":"Saldo","parts_pct":0,"services_pct":50,"tipo":"entrega"}]'::jsonb, null),
  ('OS-00041', 'completed', '2026-07-29T14:53:51.878000Z', '2026-06-02T14:26:39.636960Z', '2026-06-22T15:56:54.403000Z', 3500, 4973.18, 0, 100, 0, true, 0, 0, 8573.18, true, '[{"days_after_approval":0,"expenses_pct":100,"label":"Sinal","parts_pct":100,"services_pct":50,"tipo":"aprovacao"},{"days_after_approval":0,"expenses_pct":0,"label":"Saldo","parts_pct":0,"services_pct":50,"tipo":"entrega"}]'::jsonb, null),
  ('OS-00073', 'invoiced', '2026-08-04T11:19:43.505000Z', '2026-07-30T18:41:46.883372Z', '2026-07-31T15:38:32.201070Z', 0, 1865.47, 0, 0, 0, true, 0, 0, 1865.47, true, '[{"days_after_approval":0,"label":"À vista","percent":100}]'::jsonb, null),
  ('ORÇ-00070', 'completed', '2026-08-04T11:20:07.085000Z', '2026-07-25T17:04:05.583908Z', null, 1685, 3636.36, 0, 0, 0, true, 0, 0, 5321.36, true, '[{"days_after_approval":0,"expenses_pct":100,"label":"Sinal","parts_pct":100,"services_pct":50,"tipo":"aprovacao"},{"days_after_approval":0,"expenses_pct":0,"label":"Saldo","parts_pct":0,"services_pct":50,"tipo":"entrega"}]'::jsonb, null),
  ('OS-00060', 'completed', '2026-08-13T23:21:48.751000Z', '2026-07-14T02:17:33.522598Z', '2026-07-27T18:09:02.828961Z', 2500, 18060.67, 0, 0, 0, true, 560.67, 0, 20000, true, '[{"days_after_approval":0,"expenses_pct":100,"label":"Sinal","parts_pct":100,"services_pct":50,"tipo":"aprovacao"},{"days_after_approval":0,"expenses_pct":0,"label":"Saldo","parts_pct":0,"services_pct":50,"tipo":"entrega"}]'::jsonb, null),
  ('OS-00075', 'completed', '2026-08-13T23:22:40.351000Z', '2026-08-06T11:07:26.734125Z', '2026-08-13T23:21:29.678026Z', 538.33, 192.01, 0, 0, 0, true, 230.34, 0, 500, true, '[{"days_after_approval":0,"expenses_pct":100,"label":"À vista","parts_pct":100,"services_pct":100,"tipo":"aprovacao"}]'::jsonb, null),
  ('OS-00084', 'completed', '2026-08-21T11:51:36.046000Z', '2026-08-20T14:12:15.752236Z', '2026-08-21T11:51:22.496505Z', 400, 191.41, 0, 0, 0, true, 0, 0, 591.41, false, null, null),
  ('OS-00105', 'completed', '2026-09-05T20:00:00.000000Z', '2026-09-05T15:00:00.000000Z', null, 0, 0, 0, 0, 0, true, 0, 0, 0, false, null, null),
  ('OS-00094', 'completed', '2026-10-03T18:58:11.452000Z', '2026-09-03T15:45:22.499065Z', '2026-09-23T01:35:59.500553Z', 730, 477.02, 0, 0, 0, true, 127.02, 0, 1080, true, '[{"days_after_approval":0,"expenses_pct":100,"label":"À vista","parts_pct":100,"services_pct":100,"tipo":"aprovacao"}]'::jsonb, null),
  ('OS-00077', 'completed', '2026-10-13T13:11:17.660000Z', '2026-08-11T15:45:08.910525Z', '2026-08-12T16:05:21.796548Z', 0, 2843.24, 0, 0, 0, true, 323.24, 0, 2520, false, null, null),
  ('OS-00051', 'completed', '2026-10-13T13:11:50.108000Z', '2026-06-22T15:12:47.301600Z', '2026-06-23T11:18:47.363042Z', 3420, 4883.74, 0, 0, 0, true, 0, 0, 8303.74, true, '[{"days_after_approval":0,"expenses_pct":100,"label":"Sinal","parts_pct":100,"services_pct":50,"tipo":"aprovacao"},{"days_after_approval":0,"expenses_pct":0,"label":"Saldo","parts_pct":0,"services_pct":50,"tipo":"entrega"}]'::jsonb, null),
  ('OS-00038', 'completed', '2026-10-13T13:11:52.439000Z', '2026-05-22T13:08:20.543521Z', '2026-05-22T13:08:20.543521Z', 16890, 0, 0, 0, 0, true, 0, 0, 16890, true, '[{"days_after_approval":0,"label":"À vista","percent":100}]'::jsonb, null),
  ('OS-00061', 'completed', '2026-10-13T13:12:02.414000Z', '2026-07-17T14:18:37.112959Z', '2026-07-29T14:59:57.464066Z', 5450, 410, 0, 0, 0, true, 220, 0, 5640, false, null, null),
  ('OS-00110', 'completed', '2026-10-13T13:19:53.482000Z', '2026-09-25T10:05:04.431555Z', '2026-10-13T13:17:32.145446Z', 3320, 2795, 0, 0, 0, true, 515, 0, 5600, true, '[{"days_after_approval":0,"expenses_pct":50,"label":"Entrada 50%","parts_pct":50,"services_pct":50,"tipo":"aprovacao"},{"days_after_approval":0,"expenses_pct":50,"label":"Saldo 50%","parts_pct":50,"services_pct":50,"tipo":"entrega"}]'::jsonb, null);

insert into _replay_rec values
  ('OS-00001', 1, 500, 'paid', false, false, '2026-07-23', '2026-07-23', 500, 0, '2026-08-04T11:13:59.559426Z'),
  ('OS-00001', 2, 500, 'paid', false, false, '2026-06-19', '2026-06-19', 500, 0, '2026-08-04T11:14:02.860515Z'),
  ('OS-00001', 3, 500, 'paid', false, false, '2026-06-13', '2026-06-13', 500, 0, '2026-08-04T11:14:04.971380Z'),
  ('OS-00001', 4, 500, 'paid', false, false, '2026-04-16', '2026-04-16', 500, 0, '2026-08-04T11:14:06.396502Z'),
  ('OS-00016', 1, 0, 'cancelled', false, false, '2026-06-22', '2026-07-22', 0, 0, '2026-06-22T15:23:40.979980Z'),
  ('OS-00048', 1, 250, 'paid', false, false, '2026-06-22', '2026-07-22', 250, 0, '2026-06-22T15:54:53.682750Z'),
  ('OS-00048', 2, 4500, 'paid', false, false, '2026-07-28', '2026-07-28', 4500, 0, '2026-08-04T11:13:21.128974Z'),
  ('OS-00047', 1, 756, 'pending', false, false, '2026-06-22', '2026-07-22', 0, 756, '2026-06-22T15:55:50.488948Z'),
  ('OS-00046', 1, 520, 'partially_paid', false, false, '2026-06-22', '2026-07-22', 500, 20, '2026-06-22T15:55:56.120544Z'),
  ('OS-00045', 1, 1650, 'pending', false, false, '2026-06-22', '2026-07-22', 0, 1650, '2026-06-22T15:55:59.215576Z'),
  ('OS-00044', 1, 3000, 'paid', false, false, '2026-06-22', '2026-07-22', 3000, 0, '2026-06-22T15:56:42.014816Z'),
  ('OS-00034', 1, 29000, 'paid', false, false, '2026-06-29', '2026-06-29', 29000, 0, '2026-06-29T14:51:36.377516Z'),
  ('OS-00041', 1, 8573.18, 'paid', false, false, '2026-06-29', '2026-06-29', 8573.18, 0, '2026-06-29T01:55:34.919304Z'),
  ('OS-00073', 1, 1866, 'paid', true, false, '2026-07-31', '2026-07-31', 1866, 0, '2026-07-31T15:38:32.201070Z'),
  ('OS-00073', 2, 1865.47, 'cancelled', false, false, '2026-08-04', '2026-08-04', 0, 0, '2026-08-04T11:19:44.558377Z'),
  ('ORÇ-00070', 1, 5321.36, 'paid', false, false, '2026-07-29', '2026-07-29', 5321.36, 0, '2026-07-29T14:46:01.687632Z'),
  ('OS-00060', 1, 18001.04, 'paid', true, false, '2026-07-20', '2026-07-20', 18001.04, 0, '2026-07-27T18:09:02.828961Z'),
  ('OS-00060', 2, 1998.96, 'paid', false, false, '2026-07-27', '2026-08-26', 1998.96, 0, '2026-07-27T18:48:25.591674Z'),
  ('OS-00075', 1, 500, 'paid', true, false, '2026-08-12', '2026-08-12', 500, 0, '2026-08-13T23:21:29.678026Z'),
  ('OS-00075', 2, 500, 'cancelled', false, false, '2026-08-13', '2026-08-13', 0, 0, '2026-08-13T23:22:40.337417Z'),
  ('OS-00084', 1, 591.41, 'paid', true, false, '2026-08-21', '2026-08-21', 591.41, 0, '2026-08-21T11:51:22.496505Z'),
  ('OS-00084', 2, 591.41, 'cancelled', false, false, '2026-08-21', '2026-09-20', 0, 0, '2026-08-21T11:51:36.578411Z'),
  ('OS-00105', 1, 1685, 'paid', false, false, '2026-09-05', '2026-09-05', 1685, 0, '2026-09-23T12:17:34.757079Z'),
  ('OS-00105', 2, 1350, 'paid', false, false, '2026-09-05', '2026-09-05', 1350, 0, '2026-09-23T12:17:34.757079Z'),
  ('OS-00094', 1, 1080, 'paid', true, false, '2026-09-08', '2026-09-08', 1080, 0, '2026-09-23T01:35:59.500553Z'),
  ('OS-00077', 1, 2520, 'paid', true, false, '2026-08-11', '2026-08-11', 2520, 0, '2026-08-12T16:05:21.796548Z'),
  ('OS-00051', 1, 6593.74, 'paid', true, false, '2026-06-22', '2026-06-22', 6593.74, 0, '2026-06-23T11:18:47.363042Z'),
  ('OS-00051', 2, 1710, 'pending', false, true, '2026-07-27', '2026-10-13', 0, 1710, '2026-07-27T18:48:25.591674Z'),
  ('OS-00038', 1, 16890, 'pending', false, false, '2026-10-13', '2026-10-13', 0, 16890, '2026-10-13T13:11:52.744444Z'),
  ('OS-00061', 1, 5000, 'paid', true, false, '2026-07-28', '2026-07-28', 5000, 0, '2026-07-29T14:59:57.464066Z'),
  ('OS-00110', 1, 5600, 'paid', true, false, '2026-10-09', '2026-10-09', 5600, 0, '2026-10-13T13:17:32.145446Z');
