-- Prova da conclusão no banco, Agenda de Produção Fase 3 (pacote P2; migration 20261026100100): a porta completa, as
-- cobranças da conclusão, a conversão ORÇ→OS mantendo o número, a entrega, os marcos e o desfazer.
-- bancada: depende de 20261026100100
--
--   C  concluir: as cobranças da condição e a saída na mesma transação (a parcela "na entrega" vence no dia da saída pelo
--      gatilho); "já tem" não cria nada e o texto conta o vencimento que mudou; período fechado = nada muda e o texto diz
--      por quê; o técnico da OS conclui e a cobrança nasce (NOVO-agenda-14); o vendedor não conclui; a assinatura (sem
--      login) e o gestor (equipe, sem autor) concluem; o motor não; a saída que já existia fica; p_check_out vira a saída;
--      concluir 2× = 1 conjunto de cobranças; 21h30 de Brasília = a parcela "na entrega" vence no dia seguinte (paridade
--      intencional do NOVO-agenda-21)
--   V  converter: ORÇ-93006 → OS-93006 (o número troca só o prefixo), converted_to_os_at uma vez e original_quote_amount;
--      orçamento → concluída converte e conclui na mesma chamada (2 ações); o passo X recusado não deixa a conversão;
--      agendada sem dia em ligado converte e fica aprovada; quem não converte (técnico) e quem converte (vendedor,
--      assinatura); número que já é de outra OS; o sinal pago converte mantendo o número (handle_quote_deposit_payment)
--   F  faturar só concluída e só o administrador; faturada não reabre pela porta; reabrir pela tela mantém a saída e as
--      cobranças; concluída → outro status / cancelar recusados com o texto; a porta via desfazer sem o desfazer da agenda
--   D  desfazer em 24 h: cancela as cobranças da conclusão e apaga a comissão de vendedor pendente (a conclusão de novo a
--      recria: revisão da Fase 3, item 4), volta o status e a saída e devolve os vencimentos "na entrega"; com pagamento, fora
--      do prazo, entregue ou pela tela: recusa e nada muda
--   E  a entrega: numa OS em andamento conclui e entrega (duas ações); já entregue = nada; nunca antes da saída; o
--      vendedor não registra; o desfazer da entrega que concluiu junto volta tudo
--   W  com login, a via não é de quem chama (revisão da Fase 3, R6): motor, vigia, equipe e assinatura só sem login; dono e
--      conferência só do administrador ou do financeiro (na porta e na entrega)
--   M  os marcos e o texto deles ("(24 dias úteis)", sem "du")
--   J  portas: só _agenda_escrever_os e _agenda_escrever_conclusao ligam agenda.porta; anon sem execute; quem executa o quê;
--      security definer; a cópia de agenda_desfazer só muda nos blocos -- FASE 3: (e -- FASE 4:, do P4 da Fase 4); a porta
--      com 8 e com 9 argumentos
--   L  (só na bancada, com fixture-fase3.sql) o Lenine (OS-00074, sem sinal: as duas parcelas nascem) e o Vanderlei
--      (OS-00069, sinal pago: nada nasce e o saldo na entrega passa a vencer hoje), os textos da spec
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs --ate 20261026100100
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase3_conclusao.sql
--   Seguro em produção: as pessoas, os logins, o cliente, as OS e as cobranças de teste ("TESTE P2", OS-93xxx/ORÇ-93xxx)
--   só são inseridos; o fuso, o modo da agenda e o período fechado mudam só dentro da transação; termina em ROLLBACK. Os
--   gatilhos de produção da conclusão rodam nas OS de teste e são desfeitos junto. As seções J (cópia) e L só rodam na
--   bancada (fora dela, PULADO).
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

-- O Supabase roda em UTC: o gatilho do vencimento "na entrega" (sync_balance_due_on_completion) usa check_out_at::date
-- no fuso da sessão. A bancada fica igual.
set local timezone = 'UTC';
select set_config('agenda.hoje', '2026-10-29', true);

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

-- Executa p_sql (que devolve um valor) como o papel p_papel com o login p_uid: o resultado em texto, ou
-- 'erro <estado>: <mensagem>'. Volta ao dono do teste no fim.
create function pg_temp.como(p_uid uuid, p_papel text, p_sql text) returns text language plpgsql as $f$
declare
  v text;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('request.jwt.claims',
    case when p_uid is null then json_build_object('role', p_papel)::text
         else json_build_object('sub', p_uid, 'role', p_papel)::text end, true);
  begin
    execute format('set local role %I', p_papel);
    execute p_sql into v;
    reset role;
  exception when others then
    v := 'erro ' || sqlstate || ': ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;

create function pg_temp.os(n int) returns uuid language sql immutable as $f$
  select ('f3200000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $f$;

-- O que ficou no banco para a OS n.
create function pg_temp.estado(p_n int) returns jsonb language sql as $f$
  select jsonb_build_object(
    'status', so.status, 'numero', so.service_order_number, 'quote_status', so.quote_status,
    'check_in_banco', so.check_in_at, 'check_out_banco', so.check_out_at, 'delivered_banco', so.delivered_at,
    'convertida_em', so.converted_to_os_at, 'orcado', so.original_quote_amount,
    'n_rec', (select count(*) from public.receivables r where r.service_order_id = so.id and r.status <> 'cancelled'),
    'n_acoes', (select count(*) from public.agenda_acoes a where a.service_order_id = so.id))
    from public.service_orders so where so.id = pg_temp.os(p_n) $f$;

-- A porta com o dia fixo (qui 29/10/2026) e, por padrão, as 16:30; devolve o que ela disse + o estado no banco.
create function pg_temp.porta(p_n int, p_para text, p_via text,
                              p_autor uuid default 'a3200000-0000-4000-8000-000000000001',
                              p_check_out timestamptz default null,
                              p_agora timestamptz default '2026-10-29 16:30-03') returns jsonb language plpgsql as $f$
begin
  return public.os_transicionar_status(pg_temp.os(p_n), p_para, p_via, null, p_autor, null, date '2026-10-29', p_agora, p_check_out)
         || jsonb_build_object('banco', pg_temp.estado(p_n));
end $f$;

-- A SQL da porta para pg_temp.como (com login: o autor é o login).
create function pg_temp.porta_sql(p_n int, p_para text, p_via text, p_campo text default 'texto') returns text
language sql immutable as $f$
  select format($s$select (public.os_transicionar_status(%L, %L, %L, null, null, null, date '2026-10-29',
                                                        timestamptz '2026-10-29 16:30-03') ->> %L)$s$,
                pg_temp.os(p_n), p_para, p_via, p_campo) $f$;

-- A ação mais nova do tipo dado na OS n.
create function pg_temp.acao(p_n int, p_tipo text) returns public.agenda_acoes language sql as $f$
  select a.* from public.agenda_acoes a where a.service_order_id = pg_temp.os(p_n) and a.tipo = p_tipo
   order by a.criada_em desc, a.id desc limit 1 $f$;

-- ── Montagem ────────────────────────────────────────────────────────────────────────────────────────────
update public.agenda_config set modo_proposta = 'desligado', modo_vigia = 'desligado' where id;

insert into public.app_users (id, full_name, email, role, active) values
  ('a3200000-0000-4000-8000-000000000001', 'TESTE P2 admin', 'teste-p2-admin@teste.invalid', 'admin', true),
  ('a3200000-0000-4000-8000-000000000002', 'TESTE P2 técnico', 'teste-p2-tecnico@teste.invalid', 'technician', true),
  ('a3200000-0000-4000-8000-000000000003', 'TESTE P2 outro técnico', 'teste-p2-outro@teste.invalid', 'technician', true),
  ('a3200000-0000-4000-8000-000000000004', 'TESTE P2 vendedor', 'teste-p2-vendedor@teste.invalid', 'seller', true),
  ('a3200000-0000-4000-8000-000000000005', 'TESTE P2 financeiro', 'teste-p2-financeiro@teste.invalid', 'financial', true);
insert into public.clients (id, type, name) values ('c3200000-0000-4000-8000-000000000001', 'individual', 'Lenine TESTE P2');
insert into public.vessels (id, client_id, name)
values ('c3210000-0000-4000-8000-000000000001', 'c3200000-0000-4000-8000-000000000001', 'Lancha TESTE P2');
insert into public.payment_condition_presets (id, label, sort_order, active, installments) values
  ('d3200000-0000-4000-8000-000000000001', 'TESTE P2 — 50% de sinal + 50% na entrega', 99, true,
   '[{"label":"Entrada 50%","tipo":"aprovacao","services_pct":50,"parts_pct":50,"expenses_pct":50,"days_after_approval":0},
     {"label":"Saldo 50%","tipo":"entrega","services_pct":50,"parts_pct":50,"expenses_pct":50,"days_after_approval":0}]');

insert into public.service_orders (id, client_id, vessel_id, service_order_number, status, quote_status,
                                   payment_condition_preset_id, labor_cost_total, parts_cost_total, grand_total,
                                   check_in_at, check_out_at, converted_to_os_at)
select pg_temp.os(x.n), 'c3200000-0000-4000-8000-000000000001', 'c3210000-0000-4000-8000-000000000001', x.numero, x.status,
       x.qs, case when x.preset then 'd3200000-0000-4000-8000-000000000001'::uuid end, x.valor, 0, x.valor,
       -- o início: das OS em andamento e concluídas (menos a 08, que testa o marco sem início, e a 10, que reabre e o ganha)
       case when x.status in ('in_progress', 'completed') and x.n not in (8, 10) then timestamptz '2026-10-27 08:00-03' end,
       x.saida,
       case when x.numero like 'OS-%' then timestamptz '2026-09-22 10:00-03' end
  from (values
    (1,  'OS-93001',  'in_progress', 'approved',         true,  4560::numeric, null::timestamptz),
    (2,  'OS-93002',  'in_progress', 'approved',         false, 5600, null),
    (3,  'OS-93003',  'in_progress', 'approved',         true,  1000, null),
    (4,  'OS-93004',  'in_progress', 'approved',         true,  2000, null),
    (5,  'OS-93005',  'in_progress', 'approved',         true,  1000, null),
    (6,  'ORÇ-93006', 'draft',       'sent',             false, 800,  null),
    (7,  'ORÇ-93007', 'draft',       'approved',         true,  1000, null),
    (8,  'OS-93008',  'in_progress', 'approved',         false, 100,  null),
    (9,  'OS-93009',  'completed',   'approved',         false, 100,  timestamptz '2026-10-20 17:00-03'),
    (10, 'OS-93010',  'completed',   'approved',         false, 100,  timestamptz '2026-10-20 17:00-03'),
    (11, 'OS-93011',  'in_progress', 'approved',         true,  4560, null),
    (12, 'OS-93012',  'in_progress', 'approved',         true,  1000, null),
    (13, 'OS-93013',  'in_progress', 'approved',         true,  1000, null),
    (15, 'OS-93015',  'in_progress', 'approved',         true,  3000, null),
    (16, 'OS-93016',  'draft',       'approved',         false, 500,  null),
    (22, 'ORÇ-93022', 'draft',       'awaiting_deposit', false, 1000, null),
    (24, 'OS-93024',  'in_progress', 'approved',         true,  1000, null),
    (25, 'OS-93025',  'in_progress', 'approved',         true,  1000, null),
    (26, 'ORÇ-93026', 'draft',       'sent',             false, 700,  null),
    (27, 'ORÇ-93027', 'draft',       'sent',             true,  1000, null),
    (28, 'ORÇ-93028', 'draft',       'sent',             false, 300,  null),
    (29, 'ORÇ-93029', 'draft',       'sent',             false, 300,  null),
    (32, 'ORÇ-93032', 'draft',       'sent',             false, 300,  null),
    (33, 'OS-93033',  'in_progress', 'approved',         true,  1000, null),
    (34, 'OS-93034',  'in_progress', 'approved',         true,  1000, null),
    (35, 'OS-93035',  'in_progress', 'approved',         false, 0,    null),
    (36, 'OS-93036',  'in_progress', 'approved',         false, 0,    timestamptz '2026-10-27 17:00-03'),
    (37, 'OS-93037',  'in_progress', 'approved',         true,  1000, null),
    (38, 'OS-93038',  'in_progress', 'approved',         true,  1000, null),
    (39, 'OS-93039',  'in_progress', 'approved',         true,  1000, null),
    (40, 'ORÇ-93040', 'draft',       'sent',             false, 300,  null),
    (41, 'ORÇ-93041', 'draft',       'awaiting_deposit', false, 300,  null),
    (42, 'OS-93040',  'approved',    'approved',         false, 300,  null),
    (43, 'OS-93041',  'approved',    'approved',         false, 300,  null),
    (44, 'OS-93044',  'open',        'approved',         false, 300,  null)
  ) as x(n, numero, status, qs, preset, valor, saida);

-- A OS-93016 é um orçamento que já foi convertido uma vez (voltou a rascunho): a conversão e o valor orçado não mudam.
update public.service_orders set converted_to_os_at = timestamptz '2026-09-01 10:00-03', original_quote_amount = 450
 where id = pg_temp.os(16);
-- A OS-93011 tem comissão de vendedor (o gatilho de produção cria a linha em commissions ao concluir).
update public.service_orders set commissioned_user_id = 'a3200000-0000-4000-8000-000000000004', commission_amount = 100,
                                 commission_rate = 0.05
 where id = pg_temp.os(11);

-- O técnico está nas OS 04, 09, 10 e 37.
insert into public.service_order_technicians (service_order_id, user_id)
select pg_temp.os(n), 'a3200000-0000-4000-8000-000000000002' from unnest(array[4, 9, 10, 37]) n;

-- OS-93002: o sinal pago e o saldo na entrega (com a cobrança em collections), como o register_deposit_and_convert grava.
insert into public.receivables (id, client_id, service_order_id, description, issue_date, due_date, amount, status, paid_amount,
                                balance_amount, is_deposit, due_on_completion) values
  ('e3200000-0000-4000-8000-000000000201', 'c3200000-0000-4000-8000-000000000001', pg_temp.os(2), 'Sinal — ORÇ-93002',
   date '2026-07-28', date '2026-07-28', 2800, 'paid', 2800, 0, true, false),
  ('e3200000-0000-4000-8000-000000000202', 'c3200000-0000-4000-8000-000000000001', pg_temp.os(2), 'Saldo — OS-93002',
   date '2026-07-29', date '2026-07-29', 2800, 'pending', 0, 2800, false, true),
  -- OS-93010: concluída antes, com a cobrança dela.
  ('e3200000-0000-4000-8000-000000001001', 'c3200000-0000-4000-8000-000000000001', pg_temp.os(10), 'OS-93010',
   date '2026-10-20', date '2026-11-19', 100, 'pending', 0, 100, false, false);
insert into public.collections (id, service_order_id, receivable_id, client_id, amount, due_date, status, description)
values ('e3200000-0000-4000-8000-000000000203', pg_temp.os(2), 'e3200000-0000-4000-8000-000000000202',
        'c3200000-0000-4000-8000-000000000001', 2800, date '2026-07-29', 'pending', 'Saldo');

-- ── C. Concluir ─────────────────────────────────────────────────────────────────────────────────────────
do $c$
declare
  r jsonb; a public.agenda_acoes; v text;
  c_admin  constant uuid := 'a3200000-0000-4000-8000-000000000001';
  c_tec    constant uuid := 'a3200000-0000-4000-8000-000000000002';
  c_vend   constant uuid := 'a3200000-0000-4000-8000-000000000004';
begin
  -- C01 sem sinal, condição 50/50: as duas parcelas e a saída, na mesma chamada.
  r := pg_temp.porta(1, 'completed', 'dono');
  a := pg_temp.acao(1, 'concluir');
  insert into _resultado values ('C01 sem sinal, 50% + 50%: conclui com a saída e as duas cobranças, e o texto diz quais',
    (r ->> 'ok')::boolean and (r ->> 'mudou')::boolean and r -> 'banco' ->> 'status' = 'completed'
    and (r -> 'banco' ->> 'check_out_banco')::timestamptz = timestamptz '2026-10-29 16:30-03'
    and (r -> 'banco' ->> 'n_rec')::int = 2 and (r -> 'banco' ->> 'n_acoes')::int = 1
    and r ->> 'texto' = 'Lenine (OS-93001): concluída — saída qui 29/10 16:30. Cobranças: Entrada 50% R$ 2.280,00 (vence hoje) · Saldo 50% R$ 2.280,00 (vence hoje).',
    r ->> 'texto');
  insert into _resultado
  select 'C01 …as cobranças: "Entrada 50% — OS-93001" vence hoje; "Saldo 50% — OS-93001" na entrega (due_on_completion), no dia da saída',
         count(*) = 2
         and bool_and(r.amount = 2280 and r.issue_date = date '2026-10-29' and r.due_date = date '2026-10-29'
                      and r.status = 'pending' and r.paid_amount = 0 and r.balance_amount = 2280 and not r.is_deposit)
         and bool_or(r.description = 'Entrada 50% — OS-93001' and not r.due_on_completion)
         and bool_or(r.description = 'Saldo 50% — OS-93001' and r.due_on_completion),
         string_agg(r.description || ' ' || r.amount || ' ' || r.due_date || ' ' || r.due_on_completion, ' | ')
    from public.receivables r where r.service_order_id = pg_temp.os(1);
  insert into _resultado values ('C01 …a ação concluir: as duas cobranças, do dono, desfazível em 24 h, antes/depois com a saída',
    a.executada and a.origem = 'dono' and a.autor = c_admin and a.status_antes = 'in_progress' and a.status_depois = 'completed'
    and cardinality(a.receivable_ids) = 2
    and a.receivable_ids <@ array(select r.id from public.receivables r where r.service_order_id = pg_temp.os(1))
    and a.desfazivel_ate = timestamptz '2026-10-30 16:30-03' and a.antes ->> 'check_out_at' is null
    and (a.depois ->> 'check_out_at')::timestamptz = timestamptz '2026-10-29 16:30-03' and a.depois ->> 'cobrancas' = 'parcelas'
    and a.texto = r ->> 'texto',
    row_to_json(a)::text);

  -- C02 de novo: nada (idempotência: um conjunto de cobranças só).
  r := pg_temp.porta(1, 'completed', 'dono');
  insert into _resultado values ('C02 concluir de novo não cria nada (1 conjunto de cobranças)',
    (r ->> 'ok')::boolean and not (r ->> 'mudou')::boolean and (r -> 'banco' ->> 'n_rec')::int = 2
    and (r -> 'banco' ->> 'n_acoes')::int = 1 and r ->> 'texto' = 'Lenine (OS-93001) já está concluída.', r::text);

  -- C03 com sinal pago e saldo na entrega: nada nasce; o saldo passa a vencer no dia da saída (o gatilho de produção).
  r := pg_temp.porta(2, 'completed', 'dono');
  insert into _resultado values ('C03 com o sinal pago: as cobranças já existiam, nada nasce, e o texto conta o saldo que passa a vencer hoje',
    (r ->> 'ok')::boolean and r -> 'banco' ->> 'status' = 'completed' and (r -> 'banco' ->> 'n_rec')::int = 2
    and r -> 'cobrancas' ->> 'motivo' = 'ja_tem' and jsonb_array_length(r -> 'cobrancas' -> 'criados') = 0
    and r ->> 'texto' = 'Lenine (OS-93002): concluída — saída qui 29/10 16:30. As cobranças já existiam (sinal pago); o saldo na entrega (R$ 2.800,00) passa a vencer hoje.',
    r ->> 'texto');
  insert into _resultado values ('C03 …o saldo na entrega e a cobrança dele vencem no dia da saída (sync_balance_due_on_completion)',
    (select due_date from public.receivables where id = 'e3200000-0000-4000-8000-000000000202') = date '2026-10-29'
    and (select due_date from public.collections where id = 'e3200000-0000-4000-8000-000000000203') = date '2026-10-29'
    and cardinality((pg_temp.acao(2, 'concluir')).receivable_ids) = 0,
    (select due_date::text from public.receivables where id = 'e3200000-0000-4000-8000-000000000202'));

  -- C04 período fechado: nada muda.
  insert into public.periodos_fechados (ano, mes) values (2026, 10);
  r := pg_temp.porta(3, 'completed', 'dono');
  insert into _resultado values ('C04 período de outubro fechado: não conclui, nada muda (status, saída, cobranças, ações) e o texto diz por quê',
    not (r ->> 'ok')::boolean and not (r ->> 'mudou')::boolean and r -> 'banco' ->> 'status' = 'in_progress'
    and r -> 'banco' ->> 'check_out_banco' is null and (r -> 'banco' ->> 'n_rec')::int = 0 and (r -> 'banco' ->> 'n_acoes')::int = 0
    and r ->> 'texto' = 'Não concluí: o período de outubro está fechado no financeiro (as cobranças da conclusão entrariam nele). Reabra o período e conclua de novo.',
    r ->> 'texto');
  delete from public.periodos_fechados where ano = 2026 and mes = 10;

  -- C05 o técnico da OS conclui pelo painel e a cobrança nasce (a porta é definer: NOVO-agenda-14).
  v := pg_temp.como(c_tec, 'authenticated', pg_temp.porta_sql(4, 'completed', 'tela', 'ok'));
  a := pg_temp.acao(4, 'concluir');
  insert into _resultado values ('C05 o técnico da OS conclui pela tela e as cobranças nascem (antes, a RLS de receivables barrava)',
    v = 'true' and (pg_temp.estado(4) ->> 'n_rec')::int = 2 and a.autor = c_tec and a.origem = 'tela' and a.desfazivel_ate is null,
    v || ' ' || pg_temp.estado(4)::text);

  -- C06 o vendedor não conclui.
  v := pg_temp.como(c_vend, 'authenticated', pg_temp.porta_sql(5, 'completed', 'tela'));
  insert into _resultado values ('C06 o vendedor recebe 42501 ao concluir, e nada muda',
    v = 'erro 42501: Concluir é com o administrador ou o técnico da OS.'
    and pg_temp.estado(5) ->> 'status' = 'in_progress' and (pg_temp.estado(5) ->> 'n_rec')::int = 0, v);

  -- C07 a assinatura do cliente (sem login, service role) conclui; com login, não.
  r := public.os_transicionar_status(pg_temp.os(24), 'completed', 'assinatura', null, null, null, date '2026-10-29',
                                     timestamptz '2026-10-29 16:30-03');
  a := pg_temp.acao(24, 'concluir');
  insert into _resultado values ('C07 a assinatura (sem login) conclui com as cobranças, sem autor, origem sistema, sem desfazer pela agenda',
    (r ->> 'ok')::boolean and (pg_temp.estado(24) ->> 'n_rec')::int = 2 and a.autor is null and a.origem = 'sistema'
    and a.depois ->> 'via' = 'assinatura' and a.desfazivel_ate is null, r ->> 'texto');
  v := pg_temp.como(c_admin, 'authenticated', pg_temp.porta_sql(25, 'completed', 'assinatura'));
  insert into _resultado values ('C07 …a assinatura com login (pelo painel) é 42501',
    v = 'erro 42501: Você não pode mudar o status desta OS.' and pg_temp.estado(25) ->> 'status' = 'in_progress', v);

  -- C08 o gestor (equipe, sem autor) conclui e a conclusão dele se desfaz; o motor sem autor não conclui.
  r := pg_temp.porta(33, 'completed', 'equipe', null);
  a := pg_temp.acao(33, 'concluir');
  insert into _resultado values ('C08 o gestor (equipe, sem autor) conclui; a ação é da equipe e se desfaz em 24 h',
    (r ->> 'ok')::boolean and a.origem = 'equipe' and a.autor is null and a.desfazivel_ate = timestamptz '2026-10-30 16:30-03',
    r ->> 'texto');
  v := pg_temp.erro_de(format($s$select public.os_transicionar_status(%L, 'completed', 'motor', null, null, null, date '2026-10-29', now())$s$,
                              pg_temp.os(34)));
  insert into _resultado values ('C08 …o motor sem autor não conclui: 42501',
    v = '42501 Concluir é com o administrador ou o técnico da OS.' and pg_temp.estado(34) ->> 'status' = 'in_progress', v);

  -- C09 a saída: p_check_out quando ela não existe; a que já existe fica.
  r := pg_temp.porta(35, 'completed', 'dono', p_check_out => timestamptz '2026-10-28 18:00-03');
  insert into _resultado values ('C09 p_check_out vira a saída (qua 28/10 18:00); total zero: sem cobrança',
    (r -> 'banco' ->> 'check_out_banco')::timestamptz = timestamptz '2026-10-28 18:00-03'
    and r ->> 'texto' = 'Lenine (OS-93035): concluída — saída qua 28/10 18:00. Sem cobrança: o total da OS está zerado.'
    and (r -> 'banco' ->> 'n_rec')::int = 0, r ->> 'texto');
  r := pg_temp.porta(36, 'completed', 'dono', p_check_out => timestamptz '2026-10-28 18:00-03');
  insert into _resultado values ('C09 …a saída que já existia (ter 27/10 17:00) fica',
    (r -> 'banco' ->> 'check_out_banco')::timestamptz = timestamptz '2026-10-27 17:00-03'
    and r ->> 'texto' = 'Lenine (OS-93036): concluída — saída ter 27/10 17:00. Sem cobrança: o total da OS está zerado.', r ->> 'texto');

  -- C10 21h30 de Brasília (00h30 UTC do dia seguinte): a parcela "na entrega" vence no dia seguinte.
  r := pg_temp.porta(38, 'completed', 'dono', p_agora => timestamptz '2026-10-29 21:30-03');
  insert into _resultado values ('C10 paridade intencional (NOVO-agenda-21): concluída às 21h30, o saldo na entrega vence sex 30/10 (o gatilho usa o dia UTC); a emissão é qui 29/10',
    r ->> 'texto' = 'Lenine (OS-93038): concluída — saída qui 29/10 21:30. Cobranças: Entrada 50% R$ 500,00 (vence hoje) · Saldo 50% R$ 500,00 (vence sex 30/10).'
    and (select bool_and(issue_date = date '2026-10-29') from public.receivables where service_order_id = pg_temp.os(38)),
    r ->> 'texto');

  -- C11 a porta com os 8 argumentos da Fase 2 (sem p_check_out) resolve pela de 9.
  r := public.os_transicionar_status(pg_temp.os(44), 'scheduled', 'dono', null, c_admin, null, date '2026-10-29',
                                     timestamptz '2026-10-29 16:30-03');
  insert into _resultado values ('C11 a porta chamada com os 8 argumentos da Fase 2 continua respondendo (o 9º tem default)',
    (r ->> 'ok')::boolean and r ->> 'texto' = 'Lenine (OS-93044): de aberta para agendada.', r::text);
end
$c$;

-- ── V. Converter ────────────────────────────────────────────────────────────────────────────────────────
do $v$
declare
  r jsonb; v text; n int;
  c_admin  constant uuid := 'a3200000-0000-4000-8000-000000000001';
  c_tec    constant uuid := 'a3200000-0000-4000-8000-000000000002';
  c_vend   constant uuid := 'a3200000-0000-4000-8000-000000000004';
begin
  -- V01 o vendedor converte pela tela: o número troca só o prefixo.
  v := pg_temp.como(c_vend, 'authenticated', pg_temp.porta_sql(6, 'approved', 'tela'));
  insert into _resultado values ('V01 o vendedor converte ORÇ-93006 → OS-93006 (aprovada): o número troca só o prefixo, a conversão e o valor orçado gravados',
    v = 'Orçamento ORÇ-93006 virou a OS-93006 (aprovada).'
    and pg_temp.estado(6) ->> 'numero' = 'OS-93006' and pg_temp.estado(6) ->> 'status' = 'approved'
    and (pg_temp.estado(6) ->> 'convertida_em')::timestamptz = timestamptz '2026-10-29 16:30-03'
    and (pg_temp.estado(6) ->> 'orcado')::numeric = 800 and (pg_temp.estado(6) ->> 'n_acoes')::int = 1
    and (pg_temp.acao(6, 'status')).depois ->> 'convertido' = 'true', v || ' ' || pg_temp.estado(6)::text);

  -- V02 orçamento → concluída: converte e conclui na mesma chamada (as cobranças com o número novo).
  r := pg_temp.porta(7, 'completed', 'dono');
  insert into _resultado values ('V02 ORÇ-93007 → concluída na mesma chamada: converte (OS-93007) e conclui, 2 ações, as cobranças com o número novo',
    (r ->> 'ok')::boolean and (r ->> 'convertido')::boolean and r ->> 'de' = 'draft' and r ->> 'para' = 'completed'
    and r -> 'banco' ->> 'numero' = 'OS-93007' and r -> 'banco' ->> 'status' = 'completed' and (r -> 'banco' ->> 'n_rec')::int = 2
    and (r -> 'banco' ->> 'n_acoes')::int = 2
    and (select bool_and(description like '% — OS-93007') from public.receivables where service_order_id = pg_temp.os(7))
    and (pg_temp.acao(7, 'concluir')).status_antes = 'approved'
    and r ->> 'texto' = 'Orçamento ORÇ-93007 virou a OS-93007 (aprovada). Lenine (OS-93007): concluída — saída qui 29/10 16:30. Cobranças: Entrada 50% R$ 500,00 (vence hoje) · Saldo 50% R$ 500,00 (vence hoje).',
    r ->> 'texto');

  -- V03 o vendedor converte mas não conclui: orçamento → concluída é 42501 e nada fica.
  v := pg_temp.como(c_vend, 'authenticated', pg_temp.porta_sql(27, 'completed', 'tela'));
  insert into _resultado values ('V03 o vendedor pede orçamento → concluída: 42501 e nada fica (nem a conversão)',
    v = 'erro 42501: Concluir é com o administrador ou o técnico da OS.'
    and pg_temp.estado(27) ->> 'numero' = 'ORÇ-93027' and pg_temp.estado(27) ->> 'status' = 'draft'
    and pg_temp.estado(27) ->> 'convertida_em' is null and (pg_temp.estado(27) ->> 'n_acoes')::int = 0, v);

  -- V04 o passo X recusado: orçamento → faturada não converte.
  r := pg_temp.porta(28, 'invoiced', 'tela');
  insert into _resultado values ('V04 orçamento → faturada: "Fature depois de concluir." e a conversão também não fica',
    not (r ->> 'ok')::boolean and not (r ->> 'mudou')::boolean and r ->> 'texto' = 'Fature depois de concluir.'
    and r -> 'banco' ->> 'numero' = 'ORÇ-93028' and r -> 'banco' ->> 'status' = 'draft' and r -> 'banco' ->> 'convertida_em' is null
    and (r -> 'banco' ->> 'n_acoes')::int = 0, r::text);

  -- V05 em ligado, orçamento → agendada sem dia no plano: converte e fica aprovada.
  update public.agenda_config set modo_proposta = 'ligado' where id;
  r := pg_temp.porta(29, 'scheduled', 'tela');
  update public.agenda_config set modo_proposta = 'desligado' where id;
  insert into _resultado values ('V05 em ligado, orçamento → agendada sem dia no plano: converte e fica aprovada, e o texto diz as duas coisas',
    (r ->> 'ok')::boolean and (r ->> 'mudou')::boolean and r ->> 'para' = 'approved' and r -> 'banco' ->> 'numero' = 'OS-93029'
    and r ->> 'texto' = 'Orçamento ORÇ-93029 virou a OS-93029 (aprovada). Sem dia no plano: a OS continua aprovada.', r ->> 'texto');

  -- V06 o técnico não converte.
  v := pg_temp.como(c_tec, 'authenticated', pg_temp.porta_sql(32, 'approved', 'tela'));
  insert into _resultado values ('V06 o técnico não converte orçamento: 42501',
    v = 'erro 42501: Converter orçamento em OS é com o administrador ou o vendedor.' and pg_temp.estado(32) ->> 'status' = 'draft', v);

  -- V07 a assinatura converte (signature_status_after = 'approved' em produção: NOVO-agenda-23).
  r := public.os_transicionar_status(pg_temp.os(26), 'approved', 'assinatura', null, null, null, date '2026-10-29',
                                     timestamptz '2026-10-29 16:30-03');
  insert into _resultado values ('V07 a assinatura do cliente aprova o orçamento convertendo (ORÇ-93026 → OS-93026)',
    (r ->> 'ok')::boolean and pg_temp.estado(26) ->> 'numero' = 'OS-93026' and pg_temp.estado(26) ->> 'status' = 'approved', r::text);

  -- V08 o que já foi convertido uma vez: converted_to_os_at e o valor orçado ficam.
  r := pg_temp.porta(16, 'approved', 'dono');
  insert into _resultado values ('V08 converted_to_os_at e original_quote_amount são gravados uma vez só (o de antes fica)',
    (r ->> 'ok')::boolean and r -> 'banco' ->> 'numero' = 'OS-93016'
    and (r -> 'banco' ->> 'convertida_em')::timestamptz = timestamptz '2026-09-01 10:00-03'
    and (r -> 'banco' ->> 'orcado')::numeric = 450, r::text);

  -- V09 o número novo que já é de outra OS: não converte.
  r := pg_temp.porta(40, 'approved', 'dono');
  insert into _resultado values ('V09 ORÇ-93040 com a OS-93040 já existindo: não converte, e diz por quê',
    not (r ->> 'ok')::boolean and r ->> 'texto' = 'Não converti: o número OS-93040 já é de outra OS.'
    and r -> 'banco' ->> 'status' = 'draft' and r -> 'banco' ->> 'numero' = 'ORÇ-93040', r ->> 'texto');

  -- V10 o sinal pago converte mantendo o número (handle_quote_deposit_payment recriada).
  insert into public.receivables (id, client_id, service_order_id, description, issue_date, due_date, amount, status, paid_amount,
                                  balance_amount, is_deposit) values
    ('e3200000-0000-4000-8000-000000002201', 'c3200000-0000-4000-8000-000000000001', pg_temp.os(22), 'Sinal — ORÇ-93022',
     date '2026-10-29', date '2026-10-29', 300, 'pending', 0, 300, true),
    ('e3200000-0000-4000-8000-000000004101', 'c3200000-0000-4000-8000-000000000001', pg_temp.os(41), 'Sinal — ORÇ-93041',
     date '2026-10-29', date '2026-10-29', 100, 'pending', 0, 100, true);
  update public.receivables set status = 'paid', paid_amount = amount, balance_amount = 0
   where id in ('e3200000-0000-4000-8000-000000002201', 'e3200000-0000-4000-8000-000000004101');
  insert into _resultado values ('V10 o sinal pago converte ORÇ-93022 → OS-93022 (aprovada, convertida, valor orçado guardado)',
    pg_temp.estado(22) ->> 'numero' = 'OS-93022' and pg_temp.estado(22) ->> 'status' = 'approved'
    and pg_temp.estado(22) ->> 'quote_status' = 'approved' and pg_temp.estado(22) ->> 'convertida_em' is not null
    and (pg_temp.estado(22) ->> 'orcado')::numeric = 1000, pg_temp.estado(22)::text);
  insert into _resultado values ('V10 …com a OS-93041 já existindo, o sinal pago converte e o número fica ORÇ-93041 (o pagamento não quebra)',
    pg_temp.estado(41) ->> 'numero' = 'ORÇ-93041' and pg_temp.estado(41) ->> 'status' = 'approved'
    and pg_temp.estado(41) ->> 'convertida_em' is not null, pg_temp.estado(41)::text);
end
$v$;

-- ── F. Faturar, reabrir e o resto da concluída ──────────────────────────────────────────────────────────
do $f$
declare
  r jsonb; v text;
  c_tec constant uuid := 'a3200000-0000-4000-8000-000000000002';
begin
  r := pg_temp.porta(8, 'invoiced', 'assistente');
  insert into _resultado values ('F01 em andamento → faturada: recusa, "Fature depois de concluir."',
    not (r ->> 'ok')::boolean and r ->> 'texto' = 'Fature depois de concluir.' and r -> 'banco' ->> 'status' = 'in_progress', r::text);

  v := pg_temp.como(c_tec, 'authenticated', pg_temp.porta_sql(9, 'invoiced', 'tela'));
  insert into _resultado values ('F02 o técnico (da OS) não fatura: 42501', v = 'erro 42501: Faturar e reabrir são com o administrador.', v);
  r := pg_temp.porta(9, 'invoiced', 'tela');
  insert into _resultado values ('F02 …o administrador fatura a concluída',
    (r ->> 'ok')::boolean and r -> 'banco' ->> 'status' = 'invoiced' and r ->> 'texto' = 'Lenine (OS-93009): faturada.'
    and (pg_temp.acao(9, 'status')).status_depois = 'invoiced', r ->> 'texto');
  r := pg_temp.porta(9, 'in_progress', 'tela');
  insert into _resultado values ('F03 faturada não reabre pela porta: "reabrir é pelo financeiro"',
    not (r ->> 'ok')::boolean and r ->> 'texto' = 'A OS-93009 está faturada: reabrir é pelo financeiro.'
    and r -> 'banco' ->> 'status' = 'invoiced', r ->> 'texto');

  v := pg_temp.como(c_tec, 'authenticated', pg_temp.porta_sql(10, 'in_progress', 'tela'));
  insert into _resultado values ('F04 o técnico (da OS) não reabre: 42501', v = 'erro 42501: Faturar e reabrir são com o administrador.', v);
  r := pg_temp.porta(10, 'in_progress', 'tela');
  insert into _resultado values ('F04 …reabrir pela tela: em andamento, a saída e a cobrança ficam (paridade), o início entra',
    (r ->> 'ok')::boolean and r -> 'banco' ->> 'status' = 'in_progress'
    and (r -> 'banco' ->> 'check_out_banco')::timestamptz = timestamptz '2026-10-20 17:00-03'
    and (r -> 'banco' ->> 'check_in_banco')::timestamptz = timestamptz '2026-10-29 16:30-03'
    and (r -> 'banco' ->> 'n_rec')::int = 1
    and r ->> 'texto' = 'Reabri o Lenine (OS-93010). As cobranças da conclusão continuam; se for o caso, ajuste no financeiro.',
    r ->> 'texto');

  r := pg_temp.porta(36, 'cancelled', 'tela');
  insert into _resultado values ('F05 concluída → cancelada: "Cancelar é pelo botão Cancelar OS."',
    not (r ->> 'ok')::boolean and r ->> 'texto' = 'Cancelar é pelo botão Cancelar OS.' and r -> 'banco' ->> 'status' = 'completed', r::text);
  r := pg_temp.porta(36, 'scheduled', 'tela');
  insert into _resultado values ('F05 …concluída → agendada pela tela: recusa',
    not (r ->> 'ok')::boolean and r ->> 'texto' = 'A OS-93036 está concluída: a agenda não muda o status dela.', r::text);
  r := pg_temp.porta(35, 'in_progress', 'assistente');
  insert into _resultado values ('F05 …reabrir pelo assistente: recusa (reabrir é pela tela ou pelo dono)',
    not (r ->> 'ok')::boolean and r ->> 'texto' = 'A OS-93035 está concluída: a agenda não muda o status dela.'
    and r -> 'banco' ->> 'status' = 'completed', r::text);

  r := pg_temp.porta(1, 'in_progress', 'desfazer');
  insert into _resultado values ('F06 a porta via desfazer, fora do desfazer da agenda: recusa e nada muda',
    not (r ->> 'ok')::boolean and r ->> 'texto' = 'Desfazer a conclusão é pelo *desfaz* da agenda; para reabrir, use a tela da OS.'
    and r -> 'banco' ->> 'status' = 'completed' and r -> 'banco' ->> 'check_out_banco' is not null, r::text);
end
$f$;

-- ── D. Desfazer a conclusão ─────────────────────────────────────────────────────────────────────────────
do $d$
declare
  r jsonb; a public.agenda_acoes; v_ids uuid[];
  c_admin constant uuid := 'a3200000-0000-4000-8000-000000000001';
  c_agora constant timestamptz := '2026-10-29 17:00-03';
begin
  -- D01 a conclusão com comissão de vendedor, desfeita em 24 h.
  r := pg_temp.porta(11, 'completed', 'dono');
  a := pg_temp.acao(11, 'concluir');
  v_ids := a.receivable_ids;
  insert into _resultado values ('D01 a conclusão gerou 2 cobranças e a comissão de vendedor (o gatilho de produção), guardada na ação',
    cardinality(v_ids) = 2 and jsonb_array_length(a.depois -> 'comissoes') = 1
    and exists (select 1 from public.commissions cm where cm.service_order_id = pg_temp.os(11) and cm.status = 'pending'),
    a.depois::text);
  r := public.agenda_desfazer(a.id, c_admin, 'dono', date '2026-10-29', c_agora);
  insert into _resultado values ('D01 …desfeito: volta para em andamento, sem a saída, as 2 cobranças canceladas e a comissão pendente apagada',
    (r ->> 'ok')::boolean
    and r ->> 'texto' = 'Desfeito: o Lenine (OS-93011) voltou para em andamento; cancelei as 2 cobranças da conclusão (R$ 4.560,00) e a comissão de vendedor que ela gerou.'
    and pg_temp.estado(11) ->> 'status' = 'in_progress' and pg_temp.estado(11) ->> 'check_out_banco' is null
    and (pg_temp.estado(11) ->> 'n_rec')::int = 0
    and (select bool_and(status = 'cancelled' and balance_amount = 0) from public.receivables where id = any (v_ids))
    -- revisão da Fase 3 (item 4): a comissão pendente que nasceu com a conclusão sai (cancelada, ficava para sempre)
    and not exists (select 1 from public.commissions where service_order_id = pg_temp.os(11)),
    r ->> 'texto');
  insert into _resultado values ('D01 …o registro: a conclusão desfeita, a ação desfazer apontando para ela, e o status pela porta (via desfazer)',
    (select desfeita_em = c_agora and desfeita_pela is not null from public.agenda_acoes where id = a.id)
    and exists (select 1 from public.agenda_acoes d where d.desfaz_a = a.id and d.tipo = 'desfazer' and d.receivable_ids @> v_ids
                                                     and jsonb_array_length(d.depois -> 'comissoes_apagadas') = 1
                                                     and (d.depois -> 'comissoes_apagadas' -> 0 ->> 'amount')::numeric = 100)
    and exists (select 1 from public.agenda_acoes s where s.service_order_id = pg_temp.os(11) and s.tipo = 'status'
                                                     and s.status_antes = 'completed' and s.status_depois = 'in_progress'
                                                     and s.depois ->> 'via' = 'desfazer'),
    null);
  r := public.agenda_desfazer(a.id, c_admin, 'dono', date '2026-10-29', c_agora);
  insert into _resultado values ('D01 …desfazer de novo: "Isso já foi desfeito."',
    not (r ->> 'ok')::boolean and r ->> 'texto' = 'Isso já foi desfeito.', r::text);

  -- D06 (revisão da Fase 3, item 4) concluir de novo depois do desfazer: a comissão de vendedor volta pendente. O gatilho de
  -- produção (sync_commission_on_so_complete) insere com ON CONFLICT (service_order_id, user_id) DO NOTHING: se o desfazer
  -- só a cancelasse, ela ficaria cancelada para sempre.
  r := public.os_transicionar_status(pg_temp.os(11), 'completed', 'dono', null, c_admin, null, date '2026-10-29',
                                     timestamptz '2026-10-29 17:30-03', null);
  insert into _resultado values ('D06 conclui → desfaz → conclui: a comissão de vendedor está pendente de novo (uma só) e a conclusão nova a guarda',
    (r ->> 'ok')::boolean
    and (select count(*) from public.commissions cm where cm.service_order_id = pg_temp.os(11)) = 1
    and (select cm.status from public.commissions cm where cm.service_order_id = pg_temp.os(11)) = 'pending'
    and jsonb_array_length((pg_temp.acao(11, 'concluir')).depois -> 'comissoes') = 1,
    (select string_agg(cm.status || ' ' || cm.amount, ', ') from public.commissions cm where cm.service_order_id = pg_temp.os(11)));

  -- D02 o "já tinha": desfazer devolve o vencimento do saldo na entrega e o da cobrança dele.
  a := pg_temp.acao(2, 'concluir');
  r := public.agenda_desfazer(a.id, c_admin, 'dono', date '2026-10-29', c_agora);
  insert into _resultado values ('D02 desfazer a conclusão sem cobrança criada: volta, e o saldo na entrega e a cobrança voltam a 29/07',
    (r ->> 'ok')::boolean and r ->> 'texto' = 'Desfeito: o Lenine (OS-93002) voltou para em andamento.'
    and (select due_date from public.receivables where id = 'e3200000-0000-4000-8000-000000000202') = date '2026-07-29'
    and (select due_date from public.collections where id = 'e3200000-0000-4000-8000-000000000203') = date '2026-07-29'
    and (select status from public.receivables where id = 'e3200000-0000-4000-8000-000000000202') = 'pending',
    r ->> 'texto');

  -- D03 com pagamento numa cobrança da conclusão: recusa e nada muda.
  r := pg_temp.porta(12, 'completed', 'dono');
  a := pg_temp.acao(12, 'concluir');
  insert into public.payments (receivable_id, payment_date, amount, payment_method, status)
  values (a.receivable_ids[1], date '2026-10-29', 100, 'pix', 'confirmed');
  r := public.agenda_desfazer(a.id, c_admin, 'dono', date '2026-10-29', c_agora);
  insert into _resultado values ('D03 já entrou pagamento: não desfaz, e nada muda',
    not (r ->> 'ok')::boolean
    and r ->> 'texto' = 'Não dá para desfazer: já entrou pagamento na cobrança da conclusão. Reabra pela OS e ajuste no financeiro.'
    and pg_temp.estado(12) ->> 'status' = 'completed' and (pg_temp.estado(12) ->> 'n_rec')::int = 2
    and (select desfeita_em is null from public.agenda_acoes where id = a.id), r::text);

  -- D04 fora do prazo.
  r := pg_temp.porta(13, 'completed', 'dono');
  a := pg_temp.acao(13, 'concluir');
  r := public.agenda_desfazer(a.id, c_admin, 'dono', date '2026-10-30', timestamptz '2026-10-30 17:00-03');
  insert into _resultado values ('D04 passou o prazo (24 h): não desfaz',
    not (r ->> 'ok')::boolean
    and r ->> 'texto' = 'Não dá mais para desfazer a conclusão do Lenine (OS-93013): passou o prazo. Para mudar, use a tela da OS.'
    and pg_temp.estado(13) ->> 'status' = 'completed', r::text);

  -- D05 a conclusão pela tela não se desfaz pela agenda.
  a := pg_temp.acao(4, 'concluir');
  r := public.agenda_desfazer(a.id, c_admin, 'dono', date '2026-10-29', c_agora);
  insert into _resultado values ('D05 a conclusão feita na tela: o desfazer da agenda recusa (reabrir é pela tela)',
    not (r ->> 'ok')::boolean and r ->> 'texto' = 'A conclusão do Lenine (OS-93004) foi feita na OS: para mudar, use a tela da OS.'
    and pg_temp.estado(4) ->> 'status' = 'completed', r::text);
end
$d$;

-- ── E. A entrega ────────────────────────────────────────────────────────────────────────────────────────
do $e$
declare
  r jsonb; v text; a public.agenda_acoes; c public.agenda_acoes;
  c_admin constant uuid := 'a3200000-0000-4000-8000-000000000001';
  c_vend  constant uuid := 'a3200000-0000-4000-8000-000000000004';
begin
  v := pg_temp.erro_de(format($s$update public.service_orders set delivered_at = now() where id = %L$s$, pg_temp.os(1)));
  insert into _resultado values ('E01 delivered_at direto (UPDATE) é recusado pelo gatilho',
    v = 'P0001 A entrega é registrada na OS (botão Entregue) ou dizendo "entreguei <cliente>".', v);

  -- E02 "entreguei" numa OS em andamento: conclui e entrega no mesmo pedido.
  r := public.os_registrar_marco(pg_temp.os(15), 'entrega', 'dono', null, c_admin, 'entreguei o Lenine', date '2026-10-29',
                                 timestamptz '2026-10-29 16:30-03');
  a := pg_temp.acao(15, 'entregar');
  c := pg_temp.acao(15, 'concluir');
  insert into _resultado values ('E02 a entrega numa OS em andamento conclui antes (saída e cobranças) e entrega, no mesmo pedido',
    (r ->> 'ok')::boolean and (r ->> 'concluiu')::boolean and pg_temp.estado(15) ->> 'status' = 'completed'
    and (pg_temp.estado(15) ->> 'delivered_banco')::timestamptz = timestamptz '2026-10-29 16:30-03'
    and (pg_temp.estado(15) ->> 'delivered_banco')::timestamptz >= (pg_temp.estado(15) ->> 'check_out_banco')::timestamptz
    and (pg_temp.estado(15) ->> 'n_rec')::int = 2 and (pg_temp.estado(15) ->> 'n_acoes')::int = 2
    and r ->> 'texto' = 'O Lenine (OS-93015) ainda estava em andamento: concluí e marquei a entrega (qui 29/10 às 16:30). Cobranças: Entrada 50% R$ 1.500,00 (vence hoje) · Saldo 50% R$ 1.500,00 (vence hoje).',
    r ->> 'texto');
  insert into _resultado values ('E02 …a ação entregar aponta a conclusão, é do dono, desfazível, e guarda o trecho',
    a.origem = 'dono' and a.desfazivel_ate = timestamptz '2026-10-30 16:30-03' and (a.depois ->> 'concluir_acao')::uuid = c.id
    and a.motivo = 'entreguei o Lenine', row_to_json(a)::text);

  r := public.os_registrar_marco(pg_temp.os(15), 'entrega', 'dono', null, c_admin, null, date '2026-10-29',
                                 timestamptz '2026-10-29 17:10-03');
  insert into _resultado values ('E03 já entregue: nada muda', (r ->> 'ok')::boolean and not (r ->> 'mudou')::boolean
    and r ->> 'texto' = 'O Lenine (OS-93015) já foi entregue em qui 29/10.' and (pg_temp.estado(15) ->> 'n_acoes')::int = 2, r::text);

  -- E04 desfazer a entrega que concluiu junto: volta tudo.
  r := public.agenda_desfazer(a.id, c_admin, 'dono', date '2026-10-29', timestamptz '2026-10-29 17:20-03');
  insert into _resultado values ('E04 desfazer a entrega que concluiu junto: volta para em andamento, sem entrega, sem saída, as cobranças canceladas',
    (r ->> 'ok')::boolean
    and r ->> 'texto' = 'Desfeito: o Lenine (OS-93015) voltou para em andamento, sem a entrega; cancelei as 2 cobranças da conclusão (R$ 3.000,00).'
    and pg_temp.estado(15) ->> 'status' = 'in_progress' and pg_temp.estado(15) ->> 'delivered_banco' is null
    and pg_temp.estado(15) ->> 'check_out_banco' is null and (pg_temp.estado(15) ->> 'n_rec')::int = 0
    and (select count(*) from public.agenda_acoes where id in (a.id, c.id) and desfeita_em is not null) = 2,
    r ->> 'texto');

  -- E05 entrega de uma OS já concluída, com p_quando antes da saída: a entrega fica na saída.
  r := public.os_registrar_marco(pg_temp.os(1), 'entrega', 'dono', timestamptz '2026-10-29 10:00-03', c_admin, null,
                                 date '2026-10-29', timestamptz '2026-10-29 17:00-03');
  insert into _resultado values ('E05 a entrega nunca antes da saída (p_quando 10:00, saída 16:30 → entregue às 16:30)',
    (r ->> 'ok')::boolean and not (r ->> 'concluiu')::boolean
    and (pg_temp.estado(1) ->> 'delivered_banco')::timestamptz = timestamptz '2026-10-29 16:30-03'
    and r ->> 'texto' = 'Entregue: o Lenine (OS-93001), qui 29/10 às 16:30.', r ->> 'texto');
  r := public.agenda_desfazer((pg_temp.acao(1, 'concluir')).id, c_admin, 'dono', date '2026-10-29', timestamptz '2026-10-29 17:30-03');
  insert into _resultado values ('E06 a conclusão de uma OS entregue não se desfaz antes da entrega',
    not (r ->> 'ok')::boolean
    and r ->> 'texto' = 'Não dá para desfazer a conclusão: o Lenine (OS-93001) já foi entregue (qui 29/10). Desfaça a entrega antes.'
    and pg_temp.estado(1) ->> 'status' = 'completed', r::text);

  v := pg_temp.como(c_vend, 'authenticated',
         format($s$select (public.os_registrar_marco(%L, 'entrega', 'tela') ->> 'texto')$s$, pg_temp.os(39)));
  insert into _resultado values ('E07 o vendedor não registra a entrega: 42501',
    v = 'erro 42501: Registrar a entrega é com o administrador ou o técnico da OS.' and pg_temp.estado(39) ->> 'status' = 'in_progress', v);

  -- E08 o marco conclusão é a porta (o técnico da OS, pela tela).
  v := pg_temp.como('a3200000-0000-4000-8000-000000000002', 'authenticated',
         format($s$select (public.os_registrar_marco(%L, 'conclusao', 'tela', null, null, null, date '2026-10-29',
                                                     timestamptz '2026-10-29 16:30-03') ->> 'marco')$s$, pg_temp.os(37)));
  insert into _resultado values ('E08 o marco conclusão (técnico da OS, tela) é a porta: concluída, com as cobranças, marco conclusao',
    v = 'conclusao' and pg_temp.estado(37) ->> 'status' = 'completed'
    and (pg_temp.estado(37) ->> 'n_rec')::int = 2 and (pg_temp.acao(37, 'concluir')).origem = 'tela'
    and (pg_temp.acao(37, 'concluir')).autor = 'a3200000-0000-4000-8000-000000000002', v);

  v := pg_temp.erro_de(format($s$select public.os_registrar_marco(%L, 'chegada', 'dono')$s$, pg_temp.os(1)));
  insert into _resultado values ('E09 marco que não existe: 22023', v = '22023 Marco desconhecido: "chegada".', v);
end
$e$;

-- ── W. Com login, a via não é de quem chama (revisão da Fase 3, R6) ─────────────────────────────────────
-- O motor, a vigia, o gestor (equipe) e a assinatura são só do banco (sem login); o dono e a conferência, só do
-- administrador ou do financeiro. Antes, o técnico da OS chamava a porta com 'dono' e a conclusão saía como do dono (com o
-- desfazer da agenda), e qualquer login dizia 'equipe' ou 'motor'.
do $w$
declare
  v text; v2 text;
  c_admin constant uuid := 'a3200000-0000-4000-8000-000000000001';
  c_tec   constant uuid := 'a3200000-0000-4000-8000-000000000002';
  c_fin   constant uuid := 'a3200000-0000-4000-8000-000000000005';
begin
  insert into public.service_orders (id, client_id, vessel_id, service_order_number, status, quote_status, labor_cost_total,
                                     parts_cost_total, grand_total, check_in_at, converted_to_os_at)
  select pg_temp.os(n), 'c3200000-0000-4000-8000-000000000001', 'c3210000-0000-4000-8000-000000000001', 'OS-930' || n,
         'in_progress', 'approved', 0, 0, 0, timestamptz '2026-10-27 08:00-03', timestamptz '2026-09-22 10:00-03'
    from unnest(array[45, 46, 47]) n;
  insert into public.service_order_technicians (service_order_id, user_id) values (pg_temp.os(45), c_tec);

  -- W01 a porta: o técnico da OS com a via do dono, da conferência ou do gestor = 42501, e nada muda.
  v := pg_temp.como(c_tec, 'authenticated', pg_temp.porta_sql(45, 'completed', 'dono'))
       || ' | ' || pg_temp.como(c_tec, 'authenticated', pg_temp.porta_sql(45, 'completed', 'conferencia'))
       || ' | ' || pg_temp.como(c_tec, 'authenticated', pg_temp.porta_sql(45, 'completed', 'equipe'));
  insert into _resultado values ('W01 o técnico da OS, com login, pela via do dono, da conferência ou do gestor: 42501, nada muda',
    v = 'erro 42501: Você não pode mudar o status desta OS. | erro 42501: Você não pode mudar o status desta OS.'
        || ' | erro 42501: Você não pode mudar o status desta OS.'
    and pg_temp.estado(45) ->> 'status' = 'in_progress' and (pg_temp.estado(45) ->> 'n_acoes')::int = 0, v);

  -- W02 o administrador com login também não diz que é o motor, a vigia ou o gestor.
  v := pg_temp.como(c_admin, 'authenticated', pg_temp.porta_sql(46, 'awaiting_parts', 'motor'))
       || ' | ' || pg_temp.como(c_admin, 'authenticated', pg_temp.porta_sql(46, 'completed', 'vigia'))
       || ' | ' || pg_temp.como(c_admin, 'authenticated', pg_temp.porta_sql(46, 'completed', 'equipe'));
  insert into _resultado values ('W02 o administrador com login, pela via do motor, da vigia ou do gestor: 42501, nada muda',
    v = 'erro 42501: Você não pode mudar o status desta OS. | erro 42501: Você não pode mudar o status desta OS.'
        || ' | erro 42501: Você não pode mudar o status desta OS.'
    and pg_temp.estado(46) ->> 'status' = 'in_progress' and (pg_temp.estado(46) ->> 'n_acoes')::int = 0, v);

  -- W03 o marco: o técnico da OS com a via do dono e o administrador com a do gestor = 42501 (a entrega não sai).
  v := pg_temp.como(c_tec, 'authenticated',
         format($s$select (public.os_registrar_marco(%L, 'entrega', 'dono', null, null, null, date '2026-10-29',
                                                     timestamptz '2026-10-29 16:30-03') ->> 'texto')$s$, pg_temp.os(45)))
       || ' | ' || pg_temp.como(c_admin, 'authenticated',
         format($s$select (public.os_registrar_marco(%L, 'entrega', 'equipe', null, null, null, date '2026-10-29',
                                                     timestamptz '2026-10-29 16:30-03') ->> 'texto')$s$, pg_temp.os(46)));
  insert into _resultado values ('W03 a entrega com login: o técnico pela via do dono e o administrador pela do gestor = 42501',
    v = 'erro 42501: Você não pode registrar a entrega por este caminho. | erro 42501: Você não pode registrar a entrega por este caminho.'
    and pg_temp.estado(45) ->> 'delivered_banco' is null and pg_temp.estado(46) ->> 'delivered_banco' is null, v);

  -- W04 o certo continua: o técnico da OS pela tela conclui (origem tela); o financeiro pela via do dono conclui.
  v := pg_temp.como(c_tec, 'authenticated', pg_temp.porta_sql(45, 'completed', 'tela', 'ok'));
  v2 := pg_temp.como(c_fin, 'authenticated', pg_temp.porta_sql(47, 'completed', 'dono', 'ok'));
  insert into _resultado values ('W04 o técnico da OS pela tela e o financeiro pela via do dono concluem',
    v = 'true' and v2 = 'true'
    and (pg_temp.acao(45, 'concluir')).origem = 'tela' and (pg_temp.acao(45, 'concluir')).autor = c_tec
    and (pg_temp.acao(47, 'concluir')).origem = 'dono' and (pg_temp.acao(47, 'concluir')).autor = c_fin,
    v || ' | ' || v2);

  -- W05 sem login (o WhatsApp, a rotina), as vias do banco continuam: o gestor conclui sem autor.
  v := pg_temp.como(null, 'service_role',
         format($s$select (public.os_transicionar_status(%L, 'completed', 'equipe', null, null, null, date '2026-10-29',
                                                         timestamptz '2026-10-29 16:30-03') ->> 'ok')$s$, pg_temp.os(46)));
  insert into _resultado values ('W05 sem login (service_role), o gestor (equipe) conclui como antes', v = 'true', v);
end
$w$;

-- ── M. Os marcos ────────────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'M01 os 4 marcos da OS-93001: entrada (conversão), início, conclusão e entrega, com os dias úteis entre eles',
       -- revisão da Fase 3 (item 9): sem o jargão "du"
       m ->> 'texto' = format('Entrada ter 22/09 · início ter 27/10 (%s dias úteis) · conclusão qui 29/10 (2 dias úteis) · entrega qui 29/10',
                              public.agenda_du_entre(date '2026-09-22', date '2026-10-27'))
       and m -> 'entrada' ->> 'fonte' = 'conversao' and (m -> 'conclusao' ->> 'du')::int = 2 and (m -> 'entrega' ->> 'du')::int = 0
       and m ->> 'sem_entrega_du' is null,
       m::text
  from (select public.agenda_marcos_da_os(pg_temp.os(1), date '2026-10-29') m) x;
insert into _resultado
select 'M02 marco sem data = "—"; concluída sem entrega conta os dias úteis',
       a ->> 'texto' = 'Entrada ter 22/09 · início — · conclusão — · entrega —'
       and b ->> 'texto' = format('Entrada ter 22/09 · início ter 27/10 (%s dias úteis) · conclusão qui 29/10 (2 dias úteis) · entrega —',
                                  public.agenda_du_entre(date '2026-09-22', date '2026-10-27'))
       and (b ->> 'sem_entrega_du')::int = public.agenda_du_entre(date '2026-10-29', date '2026-11-03'),
       a ->> 'texto' || ' | ' || (b ->> 'texto')
  from (select public.agenda_marcos_da_os(pg_temp.os(8), date '2026-10-29') a,
               public.agenda_marcos_da_os(pg_temp.os(12), date '2026-11-03') b) x;
insert into _resultado
select 'M03 OS que não existe: P0002', pg_temp.erro_de('select public.agenda_marcos_da_os(gen_random_uuid())') = 'P0002 Não encontrei a OS.', null;

-- ── J. Portas ───────────────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'J1 só duas funções ligam agenda.porta: _agenda_escrever_os e _agenda_escrever_conclusao',
       array_agg(p.proname::text order by p.proname) = array['_agenda_escrever_conclusao', '_agenda_escrever_os'],
       string_agg(p.proname, ', ' order by p.proname)
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace and p.prosrc like '%set_config(''agenda.porta''%';

insert into _resultado
select format('J2 %s: %s', f.nome, f.regra),
       coalesce(bool_and(case f.regra
         when 'authenticated e service_role; anon não' then has_function_privilege('authenticated', p.oid, 'execute')
              and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')
         when 'só service_role' then has_function_privilege('service_role', p.oid, 'execute')
              and not has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')
         when 'ninguém (nem service_role)' then not has_function_privilege('service_role', p.oid, 'execute')
              and not has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')
         end), false) and count(p.oid) = 1,
       string_agg(pg_get_function_identity_arguments(p.oid), ' | ')
  from (values ('os_transicionar_status', 'authenticated e service_role; anon não'),
               ('os_registrar_marco', 'authenticated e service_role; anon não'),
               ('agenda_marcos_da_os', 'authenticated e service_role; anon não'),
               ('_os_recebiveis_da_conclusao', 'só service_role'),
               ('_os_numero_js', 'só service_role'), ('_os_rotulo_js', 'só service_role'),
               ('_os_cobrancas_texto', 'só service_role'), ('_os_erro_da_conclusao', 'só service_role'),
               ('agenda_desfazer', 'só service_role'),
               ('_os_criar_recebiveis_da_conclusao', 'ninguém (nem service_role)'),
               ('_agenda_escrever_conclusao', 'ninguém (nem service_role)'),
               ('_agenda_desfazer_marco', 'ninguém (nem service_role)')) f(nome, regra)
  left join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = f.nome
 group by f.nome, f.regra;

insert into _resultado
select 'J3 anon não executa nenhuma função da conclusão nem o gatilho do sinal',
       count(*) filter (where has_function_privilege('anon', p.oid, 'execute')) = 0,
       string_agg(p.proname, ', ') filter (where has_function_privilege('anon', p.oid, 'execute'))
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('os_transicionar_status', 'os_registrar_marco', 'agenda_marcos_da_os', '_os_recebiveis_da_conclusao',
                     '_os_criar_recebiveis_da_conclusao', '_agenda_escrever_conclusao', '_agenda_desfazer_marco',
                     '_os_numero_js', '_os_rotulo_js', '_os_cobrancas_texto', '_os_erro_da_conclusao',
                     'handle_quote_deposit_payment', 'agenda_desfazer');

insert into _resultado
select 'J4 security definer: a porta, o marco, as cobranças, a escrita e o desfazer; a leitura dos marcos e os textos não; search_path fixo',
       count(*) = 11
       and bool_and(p.prosecdef = (p.proname in ('os_transicionar_status', 'os_registrar_marco', '_os_recebiveis_da_conclusao',
                                                 '_os_criar_recebiveis_da_conclusao', '_agenda_escrever_conclusao',
                                                 '_agenda_desfazer_marco')))
       and bool_and(coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%'),
       string_agg(p.proname || ':' || p.prosecdef::text, ', ' order by p.proname)
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('os_transicionar_status', 'os_registrar_marco', 'agenda_marcos_da_os', '_os_recebiveis_da_conclusao',
                     '_os_criar_recebiveis_da_conclusao', '_agenda_escrever_conclusao', '_agenda_desfazer_marco',
                     '_os_numero_js', '_os_rotulo_js', '_os_cobrancas_texto', '_os_erro_da_conclusao');

-- A cópia de agenda_desfazer (corpo de 20261025100200): fora do bloco "-- FASE 3: … -- FASE 3: fim", igual.
do $copia$
declare
  v_mig   text := current_setting('agenda_teste.mig_motor_fase2', true);
  v_ini   int;
  v_corpo text;
  v_novo  text := (select p.prosrc from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'agenda_desfazer');
begin
  if coalesce(v_mig, '') = '' then
    insert into _resultado values ('J5 a cópia de agenda_desfazer só muda no bloco "-- FASE 3:"', true,
      'PULADO: sem agenda_teste.mig_motor_fase2 (rode pela bancada)');
    return;
  end if;
  v_mig := replace(v_mig, E'\r\n', E'\n');
  v_ini := position('create or replace function public.agenda_desfazer(' in v_mig);
  v_corpo := substr(v_mig, v_ini);
  v_corpo := substr(v_corpo, position(E'as $function$\n' in v_corpo) + length(E'as $function$'));
  v_corpo := left(v_corpo, position(E'\n$function$;' in v_corpo));
  v_novo := replace(v_novo, E'\r\n', E'\n');
  -- FASE 7 (7a P7): recriada de novo em 20261031100600 (os ramos estimar, dupla e gestor e quem saiu da equipe), com blocos
  -- "-- FASE 7: … -- FASE 7: fim" (um deles dentro do laço, com 4 espaços): saem antes, linha a linha (o fim pelo prefixo)
  v_novo := array_to_string(array(
    select t.l from (select u.l, u.o, u.l ~ '^\s*-- FASE 7: fim' as fim,
                            sum(case when u.l ~ '^\s*-- FASE 7:' and u.l !~ '^\s*-- FASE 7: fim' then 1
                                     when u.l ~ '^\s*-- FASE 7: fim' then -1 else 0 end) over (order by u.o) as nivel
                       from unnest(string_to_array(v_novo, E'\n')) with ordinality u(l, o)) t
     where t.nivel = 0 and not t.fim order by t.o), E'\n');
  -- FASE 7 (7a P7): fim
  -- FASE 3 (P4): agenda_desfazer foi recriada de novo em 20261026100300 (a diária da agenda e a ausência da equipe), com
  -- dois blocos "-- FASE 3: … -- FASE 3: fim": tira todos (cada um é só acréscimo ao corpo de 20261025100200).
  loop
    v_ini := position('  -- FASE 3: ' in v_novo);
    exit when v_ini = 0 or position(E'  -- FASE 3: fim\n' in v_novo) < v_ini;
    v_novo := left(v_novo, v_ini - 1)
              || substr(v_novo, position(E'  -- FASE 3: fim\n' in v_novo) + length(E'  -- FASE 3: fim\n'));
  end loop;
  -- FASE 4 (P4): recriada de novo em 20261027100400 (a ação material vai a _agenda_desfazer_material), com um bloco
  -- "-- FASE 4: … -- FASE 4: fim" depois dos da Fase 3: sai do mesmo jeito (cada um é só acréscimo).
  loop
    v_ini := position('  -- FASE 4: ' in v_novo);
    exit when v_ini = 0 or position(E'  -- FASE 4: fim\n' in v_novo) < v_ini;
    v_novo := left(v_novo, v_ini - 1)
              || substr(v_novo, position(E'  -- FASE 4: fim\n' in v_novo) + length(E'  -- FASE 4: fim\n'));
  end loop;
  -- FASE 5 (P4): recriada de novo em 20261028100400 (a resposta do cliente vai a _agenda_desfazer_cliente; o replano do
  -- pedido do cliente desfeito direto tira o pedido), com dois blocos "-- FASE 5: … -- FASE 5: fim": saem do mesmo jeito.
  loop
    v_ini := position('  -- FASE 5: ' in v_novo);
    exit when v_ini = 0 or position(E'  -- FASE 5: fim\n' in v_novo) < v_ini;
    v_novo := left(v_novo, v_ini - 1)
              || substr(v_novo, position(E'  -- FASE 5: fim\n' in v_novo) + length(E'  -- FASE 5: fim\n'));
  end loop;
  -- FASE 6 (P6): recriada de novo em 20261029100600 (a ação aprendizado vai a _agenda_desfazer_aprendizado), com um bloco
  -- "-- FASE 6: … -- FASE 6: fim" depois dos da Fase 5: sai do mesmo jeito.
  loop
    v_ini := position('  -- FASE 6: ' in v_novo);
    exit when v_ini = 0 or position(E'  -- FASE 6: fim\n' in v_novo) < v_ini;
    v_novo := left(v_novo, v_ini - 1)
              || substr(v_novo, position(E'  -- FASE 6: fim\n' in v_novo) + length(E'  -- FASE 6: fim\n'));
  end loop;
  insert into _resultado values ('J5 a cópia de agenda_desfazer só muda nos blocos "-- FASE 3:", "-- FASE 4:", "-- FASE 5:" e "-- FASE 6:" (o resto é o corpo de 20261025100200)',
    v_novo = v_corpo and position('_agenda_desfazer_marco' in v_novo) = 0 and position('_agenda_desfazer_diaria' in v_novo) = 0
    and position('_agenda_desfazer_material' in v_novo) = 0 and position('_agenda_desfazer_cliente' in v_novo) = 0
    and position('_agenda_desfazer_aprendizado' in v_novo) = 0,
    case when v_novo = v_corpo then null else format('%s × %s caracteres', length(v_novo), length(v_corpo)) end);
end
$copia$;

-- ── L. Os textos da spec com a carteira da Fase 3 (só na bancada) ──────────────────────────────────────
do $l$
declare
  v_res jsonb := '[]'::jsonb;
  r jsonb;
  c_admin constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_lenine constant uuid := '05000000-0000-4000-8000-000000000074';
  c_vand   constant uuid := '05000000-0000-4000-8000-000000000069';
begin
  if coalesce(current_setting('agenda_teste.fase3', true), '') = '' then
    insert into _resultado values ('L1 Lenine e Vanderlei (fixture-fase3)', true, 'PULADO: sem agenda_teste.fase3 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase3');
    r := public.os_transicionar_status(c_lenine, 'completed', 'dono', null, c_admin, null, date '2026-10-29',
                                       timestamptz '2026-10-29 16:30-03');
    v_res := v_res || jsonb_build_array(jsonb_build_array(
      'L1 Lenine (OS-00074, sem sinal, 50% + 50%): as duas parcelas de R$ 2.280,00 nascem e vencem hoje',
      (r ->> 'ok')::boolean
      and r ->> 'texto' = 'Lenine (OS-00074): concluída — saída qui 29/10 16:30. Cobranças: Entrada 50% R$ 2.280,00 (vence hoje) · Saldo 50% R$ 2.280,00 (vence hoje).'
      and (select count(*) from public.receivables where service_order_id = c_lenine and status <> 'cancelled') = 2,
      r ->> 'texto'));
    r := public.os_transicionar_status(c_vand, 'completed', 'dono', null, c_admin, null, date '2026-10-29',
                                       timestamptz '2026-10-29 16:30-03');
    v_res := v_res || jsonb_build_array(jsonb_build_array(
      'L2 Vanderlei (OS-00069, sinal pago e saldo na entrega): nada nasce, o saldo de R$ 2.800,00 passa a vencer hoje',
      (r ->> 'ok')::boolean
      and r ->> 'texto' = 'Vanderlei (OS-00069): concluída — saída qui 29/10 16:30. As cobranças já existiam (sinal pago); o saldo na entrega (R$ 2.800,00) passa a vencer hoje.'
      and (select due_date from public.receivables where id = 'd3000000-0000-4000-8000-000000000011') = date '2026-10-29',
      r ->> 'texto'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(v_res) e;
end
$l$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
