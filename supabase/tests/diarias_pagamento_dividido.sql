-- Prova: o pagamento do técnico dividido entre diárias e reembolso (resposta 4 do dono, 11/10/2026;
-- migration 20261011301000).
--
--   P1 proposta: os reembolsos em aberto, os do acerto primeiro, por data, somando enquanto cabe no valor
--   P2 Pix: anotado em Diárias + divisão PENDENTE; a conta corrente já diz o reembolso; depois da aprovação
--      da linha, a manutenção divide (principal Diárias + uma parte por categoria, somando a linha) e a
--      conta corrente mostra UMA linha, com o saldo igual ao de antes da divisão
--   P3 dinheiro: lançado no Caixa e dividido na hora
--   P4 bolso do sócio: uma conta ao sócio por parte (sem linha do banco não há divisao_id)
--   P5 dividir o Pix que veio do banco sem registro; juntar de volta (lista vazia); dividir de novo
--   P6 recusa (22023, nada muda): reembolso de outro técnico, já pago, que passa do valor, mês fechado
--   P7 desfazer a aprovação (Pix) e cancelar o lançamento (Caixa) juntam as partes; a divisão fica desfeita
--      e os reembolsos voltam a ficar em aberto
--   P8 RLS: anon nada; authenticated só lê, e só quem vê a folha; as RPCs sem anon
--   (correção da revisão dos ajustes, 11/10/2026)
--   P9 cancelar o CMP cujo reembolso já foi pago num pagamento dividido bloqueia (reembolso_dividido); o que só
--      estava na divisão pendente do Pix anotado sai dela (o último desfaz a divisão)
--   P10 a manutenção divide sem o reembolso cancelado por fora; erro de regra (22023) = desfeita com o motivo
--   P11 baixa registrada à parte não se divide; o Pix sem data vai sem ela; no bolso do sócio, a divisão vale
--       enquanto a conta da parte do reembolso vale
--
-- ═══ COMO RODAR ═══ (só com o OK nomeado C3 da spec dos ajustes do dono; também roda no ensaio PGlite)
--
--   supabase db query --linked -f supabase/tests/diarias_pagamento_dividido.sql --output json
--
-- Seguro em produção: termina em ROLLBACK. Freelancers, sócio, conta, linhas do extrato e reembolsos de
-- mentira (os reembolsos por insert direto, como as funções dos comprovantes fazem); as rotas reais
-- (anotar_transacao, lancar_no_caixa, desfazer_aprovacao, cancelar_lancamento) gravam e são desfeitas. A
-- aprovação da linha do Pix é a da tela feita à mão (anotação aplicada + lançamento do técnico em Diárias
-- na linha, origin bank_reconciliation). Valores quebrados (517,37) para a anotação não casar com uma linha
-- real do extrato. Sem id nem data fixos.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
create temp table _ctx (dono uuid, tecnico_user uuid, fav uuid, fav2 uuid, socio uuid, conta uuid,
                        r1 uuid, r2 uuid, r3 uuid, r4 uuid, r5 uuid, r6 uuid, r9 uuid, pix uuid, caixa uuid) on commit drop;

create function pg_temp._hoje() returns date language sql stable as $$ select (now() at time zone 'America/Sao_Paulo')::date $$;
create function pg_temp._letras(n integer) returns text language sql volatile as $$
  select upper(translate(substr(md5(random()::text || clock_timestamp()::text), 1, n), '0123456789', 'ghijklmnop'))
$$;
create function pg_temp._reemb(p_fav uuid, p_dias integer, p_valor numeric, p_codigo text, p_categoria text) returns uuid language sql as $$
  insert into public.diarias_reembolsos (favorecido_id, data, valor, descricao, origem, origem_codigo, categoria)
  values (p_fav, pg_temp._hoje() - p_dias, p_valor, 'Reembolso ' || p_codigo || ' · Loja Teste', 'comprovante', p_codigo, p_categoria)
  returning id
$$;

do $$
declare
  v_dono uuid := gen_random_uuid();
  v_tec uuid := gen_random_uuid();
  v_fav uuid;
  v_fav2 uuid;
  v_socio uuid;
  v_perfil uuid;
  v_conta uuid;
  r1 uuid; r2 uuid; r3 uuid; r4 uuid; r5 uuid; r6 uuid; r9 uuid;
  v_ac jsonb;
begin
  insert into public.app_users (id, full_name, email, role, active, created_at)
  values (v_dono, 'Admin de teste divisão', 'teste-div-' || v_dono || '@teste.invalido', 'admin', true, now() - interval '30 years'),
         (v_tec, 'Técnico de teste divisão', 'teste-div-' || v_tec || '@teste.invalido', 'technician', true, now());
  insert into public.payees (name, kind, active, conta_corrente_desde)
  values ('Freelancer Divisão ' || pg_temp._letras(6), 'diarista', true, pg_temp._hoje() - 30) returning id into v_fav;
  insert into public.work_profiles (payee_id, tipo_vinculo, modo_pagamento, valor_diaria, vigencia_inicio)
  values (v_fav, 'freelancer', 'diaria', 300, pg_temp._hoje() - 30) returning id into v_perfil;
  insert into public.work_shifts (work_profile_id, data, tipo, fracao, valor_diaria) values (v_perfil, pg_temp._hoje() - 10, 'diaria', 1, 300);
  insert into public.payees (name, kind, active, conta_corrente_desde)
  values ('Outro Freelancer Divisão ' || pg_temp._letras(6), 'diarista', true, pg_temp._hoje() - 30) returning id into v_fav2;
  insert into public.work_profiles (payee_id, tipo_vinculo, modo_pagamento, valor_diaria, vigencia_inicio)
  values (v_fav2, 'freelancer', 'diaria', 300, pg_temp._hoje() - 30);
  insert into public.payees (name, kind, active) values ('Sócio Divisão ' || pg_temp._letras(4), 'socio', true) returning id into v_socio;
  insert into public.bank_connections (provider, external_id, label, account_kind)
  values ('manual', 'teste-div-' || gen_random_uuid(), 'Conta Teste Divisão', 'bank') returning id into v_conta;
  -- R1 dentro do acerto que vai fechar; R2..R6 depois dele (período aberto; R2 sozinho no dia, para a
  -- ordem da proposta não depender do empate em criado_em); R9 de outro técnico
  r1 := pg_temp._reemb(v_fav, 6, 62, 'CMP-99911', 'Combustível e deslocamento');
  v_ac := public.fechar_acerto_diarias(v_fav, pg_temp._hoje() - 5, false, v_dono);
  r2 := pg_temp._reemb(v_fav, 2, 30, 'CMP-99912', null);
  r3 := pg_temp._reemb(v_fav, 1, 40, 'CMP-99913', 'Alimentação de campo');
  r4 := pg_temp._reemb(v_fav, 1, 25, 'CMP-99914', 'Combustível e deslocamento');
  r5 := pg_temp._reemb(v_fav, 1, 50, 'CMP-99915', 'Pedágio e estacionamento');
  r6 := pg_temp._reemb(v_fav, 1, 70, 'CMP-99916', 'Categoria que não existe');
  r9 := pg_temp._reemb(v_fav2, 1, 15, 'CMP-99919', 'Outras despesas');
  insert into _ctx values (v_dono, v_tec, v_fav, v_fav2, v_socio, v_conta, r1, r2, r3, r4, r5, r6, r9, null, null);
end $$;

create function pg_temp._c() returns _ctx language sql stable as $$ select * from _ctx $$;
create function pg_temp._linha(p_valor numeric, p_data date default null) returns uuid language sql as $$
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, source_type, bank_connection_id)
  values (coalesce(p_data, pg_temp._hoje()), 'PIX ENVIADO TESTE DIVISAO', p_valor, 'debit', 'bank', (select conta from _ctx))
  returning id
$$;
-- o lançamento que a aprovação da linha cria (a rota da tela): pago, do técnico, em Diárias
create function pg_temp._aprovado(p_tx uuid, p_valor numeric, p_data date default null) returns uuid language sql as $$
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category,
                               payee_id, bank_transaction_id, origin)
  values ('Pagamento de diárias (teste)', coalesce(p_data, pg_temp._hoje()), coalesce(p_data, pg_temp._hoje()), p_valor, p_valor, 0,
          'paid', 'Diárias de freelancers', (select fav from _ctx), p_tx, 'bank_reconciliation')
  returning id
$$;
create function pg_temp._partes(p_raiz uuid) returns text language sql stable as $$
  select string_agg(x.expense_category || ' ' || round(x.amount, 2), ' + ' order by x.divisao_id nulls first, x.expense_category)
    from public.payables x where (x.id = p_raiz or x.divisao_id = p_raiz) and x.status <> 'cancelled'
$$;

-- ═══ P1 ═════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  c _ctx := pg_temp._c();
  p jsonb;
  p500 jsonb;
begin
  p := public.proposta_de_divisao_do_pagamento(c.fav, 100, c.dono);
  p500 := public.proposta_de_divisao_do_pagamento(c.fav, 500, c.dono);
  insert into _resultado values ('P1 proposta: os do acerto primeiro, por data, somando enquanto cabe; categoria inexistente = Outras despesas',
    jsonb_array_length(p->'em_aberto') = 6 and p->'em_aberto'->0->>'id' = c.r1::text and p->'em_aberto'->0->>'acerto' is not null
    and p->'em_aberto'->1->>'acerto' is null and p->'propostos' = jsonb_build_array(c.r1, c.r2)
    and (p->>'reembolsos')::numeric = 92 and (p->>'diarias')::numeric = 8
    and p->'partes' = '[{"valor": 8.00, "categoria": "Diárias de freelancers"}, {"valor": 62.00, "categoria": "Combustível e deslocamento"}, {"valor": 30.00, "categoria": "Outras despesas"}]'::jsonb
    and jsonb_array_length(p500->'propostos') = 6 and (p500->>'reembolsos')::numeric = 277 and (p500->>'diarias')::numeric = 223
    and exists (select 1 from jsonb_array_elements(p500->'em_aberto') e where e->>'id' = c.r6::text and e->>'categoria' = 'Outras despesas')
    and p->'favorecido'->>'id' = c.fav::text,
    'propostos=' || jsonb_array_length(p->'propostos') || ' reembolsos=' || coalesce(p->>'reembolsos', '-') || ' partes=' || coalesce(p->>'partes', '-'));
exception when others then
  insert into _resultado values ('P1 proposta: os do acerto primeiro, por data, somando enquanto cabe; categoria inexistente = Outras despesas', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ P2 ═════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  c _ctx := pg_temp._c();
  r jsonb;
  v_anot uuid;
  cc0 jsonb;
  cc1 jsonb;
  cc2 jsonb;
  v_l jsonb;
  v_r1 jsonb;
  v_tx uuid;
  v_pay uuid;
  v_n integer;
  d record;
  p jsonb;
  v_pagamentos integer;
begin
  cc0 := public.conta_corrente_freelancer(c.fav, null, null, c.dono, null);
  r := public.registrar_pagamento_do_freelancer(c.fav, 517.37, pg_temp._hoje(), 'pix', null, array[c.r1, c.r2], 'Acerto da quinzena', c.dono);
  v_anot := (r->>'anotacao_id')::uuid;
  cc1 := public.conta_corrente_freelancer(c.fav, null, null, c.dono, null);
  select x into v_l from jsonb_array_elements(cc1->'linhas') x where x->>'id' = v_anot::text;
  select x into v_r1 from jsonb_array_elements(cc1->'linhas') x where x->>'id' = c.r1::text;
  p := public.proposta_de_divisao_do_pagamento(c.fav, 100, c.dono);
  -- a linha do banco chega, a anotação a classifica e o dono aprova (o lançamento do técnico em Diárias)
  v_tx := pg_temp._linha(517.37);
  update public.anotacoes_do_extrato set status = 'aplicada', aplicada_em = now(), bank_transaction_id = v_tx where id = v_anot;
  v_pay := pg_temp._aprovado(v_tx, 517.37);
  v_n := public._diarias_aplicar_divisoes_pendentes(20);
  select * into d from public.diarias_pagamentos_divididos where anotacao_id = v_anot;
  cc2 := public.conta_corrente_freelancer(c.fav, null, null, c.dono, null);
  select count(*) into v_pagamentos from jsonb_array_elements(cc2->'linhas') x where x->>'tipo' = 'pagamento';
  select x into v_l from jsonb_array_elements(cc2->'linhas') x where x->>'id' = v_pay::text;
  update _ctx set pix = v_pay;
  insert into _resultado values ('P2 Pix: anotado com a divisão pendente; depois da aprovação, a manutenção divide; uma linha na conta corrente, saldo igual',
    (r->>'ok')::boolean and r->>'forma' = 'pix' and r->'divisao'->>'status' = 'pendente'
    and (r->'divisao'->>'diarias')::numeric = 425.37 and (r->'divisao'->>'reembolsos')::numeric = 92
    and (select categoria from public.anotacoes_do_extrato where id = v_anot) = 'Diárias de freelancers'
    and (select favorecido_id from public.anotacoes_do_extrato where id = v_anot) = c.fav
    and (cc1->>'saldo_final')::numeric = (cc0->>'saldo_final')::numeric - 517.37
    and v_r1->>'observacao' like 'pago em %'
    and not (p->'em_aberto' @> jsonb_build_array(jsonb_build_object('id', c.r1)))
    and v_n >= 1 and d.status = 'aplicada' and d.payable_id = v_pay
    and pg_temp._partes(v_pay) = 'Diárias de freelancers 425.37 + Combustível e deslocamento 62.00 + Outras despesas 30.00'
    and (select sum(amount) from public.payables x where (x.id = v_pay or x.divisao_id = v_pay) and x.status <> 'cancelled') = 517.37
    and (select count(*) from public.payables x where x.divisao_id = v_pay and x.bank_transaction_id = v_tx and x.payee_id = c.fav) = 2
    and (cc2->>'saldo_final')::numeric = (cc1->>'saldo_final')::numeric
    and (v_l->>'pago')::numeric = 517.37 and v_l->>'descricao' like '%(inclui reembolso de despesas pagas pelo técnico: R$ 92,00)'
    and exists (select 1 from public.reconciliation_log g where g.payable_id = v_pay and g.acao = 'dividiu_pagamento_diarias'),
    'divisao=' || coalesce(r->'divisao'->>'status', r->>'message', '-') || ' manutencao=' || v_n || ' partes=' || coalesce(pg_temp._partes(v_pay), '-')
    || ' saldo ' || coalesce(cc0->>'saldo_final', '-') || '→' || coalesce(cc1->>'saldo_final', '-') || '→' || coalesce(cc2->>'saldo_final', '-')
    || ' pagamentos=' || v_pagamentos);
exception when others then
  insert into _resultado values ('P2 Pix: anotado com a divisão pendente; depois da aprovação, a manutenção divide; uma linha na conta corrente, saldo igual', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ P3 / P4 ════════════════════════════════════════════════════════════════════════════════
do $$
declare
  c _ctx := pg_temp._c();
  r3 jsonb;
  r4 jsonb;
  d3 record;
  d4 record;
  v_socio_contas text;
  v_caixa uuid;
begin
  r3 := public.registrar_pagamento_do_freelancer(c.fav, 200, pg_temp._hoje(), 'dinheiro', null, array[c.r3], null, c.dono);
  select * into d3 from public.diarias_pagamentos_divididos where payable_id = (r3->>'payable_id')::uuid and status = 'aplicada';
  v_caixa := (r3->>'payable_id')::uuid;
  update _ctx set caixa = v_caixa;
  r4 := public.registrar_pagamento_do_freelancer(c.fav, 100, pg_temp._hoje(), 'socio', c.socio, array[c.r4], null, c.dono);
  select * into d4 from public.diarias_pagamentos_divididos where payable_id = (r4->>'payable_id')::uuid and status = 'aplicada';
  select string_agg(x.expense_category || ' ' || round(x.amount, 2) || ' ' || x.status, ' + ' order by x.amount desc) into v_socio_contas
    from public.payables x where x.payee_id = c.socio and x.beneficiario_id = c.fav and x.status <> 'cancelled';
  insert into _resultado values ('P3/P4 dinheiro divide na hora (Caixa); bolso do sócio = uma conta ao sócio por parte',
    (r3->>'ok')::boolean and r3->'divisao'->>'status' = 'aplicada' and d3.id is not null
    and pg_temp._partes((r3->>'payable_id')::uuid) = 'Diárias de freelancers 160.00 + Alimentação de campo 40.00'
    and (select payment_method from public.payables where id = (r3->>'payable_id')::uuid) = 'cash'
    and (r4->>'ok')::boolean and r4->'divisao'->>'status' = 'aplicada' and d4.id is not null
    and v_socio_contas = 'Diárias de freelancers 75.00 pending + Combustível e deslocamento 25.00 pending'
    and not exists (select 1 from public.payables x where x.payee_id = c.socio and x.divisao_id is not null)
    and exists (select 1 from public.payables x where x.payee_id = c.socio and x.amount = 25
                 and x.description like '%Reembolso de despesas pagas pelo técnico (CMP-99914)%'),
    'dinheiro=' || coalesce(pg_temp._partes((r3->>'payable_id')::uuid), r3->>'message', '-') || ' socio=' || coalesce(v_socio_contas, '-'));
exception when others then
  insert into _resultado values ('P3/P4 dinheiro divide na hora (Caixa); bolso do sócio = uma conta ao sócio por parte', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ P5 / P6 ════════════════════════════════════════════════════════════════════════════════
do $$
declare
  c _ctx := pg_temp._c();
  v_tx uuid := pg_temp._linha(300);
  v_pay uuid;
  d1 jsonb;
  d2 jsonb;
  d3 jsonb;
  v_partes1 text;
  v_partes2 text;
  v_outro text := 'nenhum erro';
  v_pago text := 'nenhum erro';
  v_passa text := 'nenhum erro';
  v_mes text := 'nenhum erro';
  v_dia_velho date := (date_trunc('month', now() - interval '25 years') + interval '14 days')::date;
  v_tx_velho uuid;
  v_pay_velho uuid;
  v_r7 uuid;
begin
  -- o Pix que veio do banco sem registro (a regra por CPF lançou em Diárias)
  v_pay := pg_temp._aprovado(v_tx, 300);
  d1 := public.dividir_pagamento_do_freelancer(v_pay, array[c.r5], c.dono);
  v_partes1 := pg_temp._partes(v_pay);
  d2 := public.dividir_pagamento_do_freelancer(v_pay, '{}'::uuid[], c.dono);
  v_partes2 := pg_temp._partes(v_pay);
  d3 := public.dividir_pagamento_do_freelancer(v_pay, array[c.r5], c.dono);
  -- P6: as recusas (nada muda)
  begin
    perform public.dividir_pagamento_do_freelancer(v_pay, array[c.r5, c.r9], c.dono);
  exception when sqlstate '22023' then v_outro := sqlstate;
  end;
  begin
    perform public.registrar_pagamento_do_freelancer(c.fav, 100, pg_temp._hoje(), 'pix', null, array[c.r3], null, c.dono);
  exception when sqlstate '22023' then v_pago := sqlstate;
  end;
  begin
    perform public.registrar_pagamento_do_freelancer(c.fav, 50, pg_temp._hoje(), 'pix', null, array[c.r6], null, c.dono);
  exception when sqlstate '22023' then v_passa := sqlstate;
  end;
  v_tx_velho := pg_temp._linha(80, v_dia_velho);
  v_pay_velho := pg_temp._aprovado(v_tx_velho, 80, v_dia_velho);
  insert into public.periodos_fechados (ano, mes) values (extract(year from v_dia_velho)::int, extract(month from v_dia_velho)::int);
  begin
    perform public.dividir_pagamento_do_freelancer(v_pay_velho, array[c.r6], c.dono);
  exception when sqlstate '22023' then v_mes := sqlstate;
  end;
  delete from public.periodos_fechados where ano = extract(year from v_dia_velho)::int and mes = extract(month from v_dia_velho)::int;
  insert into _resultado values ('P5/P6 dividir o Pix do banco, juntar de volta e dividir de novo; recusa outro técnico, já pago, acima do valor, mês fechado',
    (d1->>'ok')::boolean and d1->'divisao'->>'status' = 'aplicada'
    and v_partes1 = 'Diárias de freelancers 250.00 + Pedágio e estacionamento 50.00'
    and (d2->>'ok')::boolean and d2->'divisao'->>'status' = 'desfeita' and v_partes2 = 'Diárias de freelancers 300.00'
    and (d3->>'ok')::boolean and d3->'divisao'->>'status' = 'aplicada'
    and pg_temp._partes(v_pay) = 'Diárias de freelancers 250.00 + Pedágio e estacionamento 50.00'
    and (select count(*) from public.diarias_pagamentos_divididos where payable_id = v_pay and status = 'aplicada') = 1
    and v_outro = '22023' and v_pago = '22023' and v_passa = '22023' and v_mes = '22023'
    and pg_temp._partes(v_pay_velho) = 'Diárias de freelancers 80.00',
    'dividiu=' || coalesce(v_partes1, '-') || ' juntou=' || coalesce(v_partes2, '-') || ' recusas=' || v_outro || '/' || v_pago || '/' || v_passa || '/' || v_mes);
exception when others then
  insert into _resultado values ('P5/P6 dividir o Pix do banco, juntar de volta e dividir de novo; recusa outro técnico, já pago, acima do valor, mês fechado', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ P7 ═════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  c _ctx := pg_temp._c();
  v_des jsonb;
  v_canc jsonb;
  v_n integer;
  d record;
  dc record;
  p jsonb;
begin
  -- o dono desfaz a aprovação do Pix dividido (P2) e cancela o pagamento em dinheiro dividido (P3): as partes
  -- juntam (_juntar_divisao, como em todo pagamento dividido) e o lançamento cai
  v_des := public.desfazer_aprovacao('payable', c.pix, 'teste da divisão', c.dono);
  v_canc := public.cancelar_lancamento('payable', c.caixa, 'teste da divisão', c.dono);
  v_n := public._diarias_aplicar_divisoes_pendentes(20);
  select * into d from public.diarias_pagamentos_divididos where payable_id = c.pix order by criado_em desc limit 1;
  select * into dc from public.diarias_pagamentos_divididos where payable_id = c.caixa order by criado_em desc limit 1;
  p := public.proposta_de_divisao_do_pagamento(c.fav, 100, c.dono);
  insert into _resultado values ('P7 desfazer a aprovação e cancelar o lançamento juntam as partes; a divisão fica desfeita e os reembolsos voltam a ficar em aberto',
    (v_des->>'ok')::boolean and d.status = 'desfeita' and d.desfeita_em is not null
    and not exists (select 1 from public.payables x where x.divisao_id = c.pix and x.status <> 'cancelled')
    and (v_canc->>'ok')::boolean and dc.status = 'desfeita'
    and not exists (select 1 from public.payables x where (x.id = c.caixa or x.divisao_id = c.caixa) and x.status <> 'cancelled')
    and p->'em_aberto' @> jsonb_build_array(jsonb_build_object('id', c.r1)) and p->'em_aberto' @> jsonb_build_array(jsonb_build_object('id', c.r2))
    and p->'em_aberto' @> jsonb_build_array(jsonb_build_object('id', c.r3)),
    'desfazer=' || coalesce(v_des->>'ok', '-') || ' divisao=' || coalesce(d.status, '-') || ' cancelar=' || coalesce(v_canc->>'ok', '-')
    || ' divisao_caixa=' || coalesce(dc.status, '-') || ' em_aberto=' || jsonb_array_length(p->'em_aberto'));
exception when others then
  insert into _resultado values ('P7 desfazer a aprovação e cancelar o lançamento juntam as partes; a divisão fica desfeita e os reembolsos voltam a ficar em aberto', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ P9 / P10 / P11 (correção da revisão dos ajustes, 11/10/2026) ═══════════════════════════
do $$
declare
  c _ctx := pg_temp._c();
  r10 uuid := pg_temp._reemb(c.fav, 1, 33, 'CMP-99920', 'Alimentação de campo');
  r11 uuid := pg_temp._reemb(c.fav, 1, 21, 'CMP-99921', 'Combustível e deslocamento');
  r12 uuid := pg_temp._reemb(c.fav, 1, 22, 'CMP-99922', 'Pedágio e estacionamento');
  r13 uuid := pg_temp._reemb(c.fav, 1, 13, 'CMP-99923', 'Alimentação de campo');
  r14 uuid := pg_temp._reemb(c.fav, 1, 14, 'CMP-99924', 'Pedágio e estacionamento');
  r15 uuid := pg_temp._reemb(c.fav, 1, 15, 'CMP-99925', 'Alimentação de campo');
  v_cmp public.comprovantes;
  v_tx uuid;
  v_pay uuid;
  v_bloq jsonb;
  v_ok1 jsonb;
  v_ok2 jsonb;
  rp jsonb;
  rq jsonb;
  rs jsonb;
  dp record;
  dq record;
  ds record;
  v_n integer;
  v_tx2 uuid;
  v_pay2 uuid;
  v_tx3 uuid;
  v_pay3 uuid;
  v_pay4 uuid;
  v_conc text := 'nenhum erro';
  v_sem_data jsonb;
  d4 record;
  v_partes_socio uuid[];
  p_meio jsonb;
  p_fim jsonb;
  v_falhas text[];
begin
  -- P9 (a): o reembolso já pago num Pix DIVIDIDO: cancelar o CMP dele bloqueia (reembolso_dividido), nada muda
  v_tx := pg_temp._linha(150);
  v_pay := pg_temp._aprovado(v_tx, 150);
  perform public.dividir_pagamento_do_freelancer(v_pay, array[r10], c.dono);
  v_cmp.id := gen_random_uuid();
  v_cmp.codigo := 'CMP-99920';
  v_cmp.efeitos := jsonb_build_array(jsonb_build_object('tipo', 'reembolso_tecnico', 'reembolso_id', r10));
  v_bloq := public._comprovante_desfazer(v_cmp, 'CMP-99920 cancelado: teste', 'teste', c.dono);
  -- P9 (b): o reembolso que só estava na divisão PENDENTE de um Pix anotado sai dela (a divisão é refeita com
  -- o outro); o último que sai desfaz a divisão
  rp := public.registrar_pagamento_do_freelancer(c.fav, 117.29, pg_temp._hoje(), 'pix', null, array[r11, r12], null, c.dono);
  v_cmp.codigo := 'CMP-99921';
  v_cmp.efeitos := jsonb_build_array(jsonb_build_object('tipo', 'reembolso_tecnico', 'reembolso_id', r11));
  v_ok1 := public._comprovante_desfazer(v_cmp, 'CMP-99921 cancelado: teste', 'teste', c.dono);
  select * into dp from public.diarias_pagamentos_divididos where anotacao_id = (rp->>'anotacao_id')::uuid;
  v_cmp.codigo := 'CMP-99922';
  v_cmp.efeitos := jsonb_build_array(jsonb_build_object('tipo', 'reembolso_tecnico', 'reembolso_id', r12));
  v_ok2 := public._comprovante_desfazer(v_cmp, 'CMP-99922 cancelado: teste', 'teste', c.dono);
  -- P10: a manutenção tira da pendente o reembolso cancelado por fora; o erro de regra (a linha não bate com o
  -- lançamento: 22023) deixa a divisão desfeita com o motivo, nunca tentando de novo
  rq := public.registrar_pagamento_do_freelancer(c.fav, 211.43, pg_temp._hoje(), 'pix', null, array[r13, r14], null, c.dono);
  update public.diarias_reembolsos set status = 'cancelado', cancelado_em = now(), motivo_cancelamento = 'teste' where id = r13;
  v_tx2 := pg_temp._linha(211.43);
  update public.anotacoes_do_extrato set status = 'aplicada', aplicada_em = now(), bank_transaction_id = v_tx2
   where id = (rq->>'anotacao_id')::uuid;
  v_pay2 := pg_temp._aprovado(v_tx2, 211.43);
  rs := public.registrar_pagamento_do_freelancer(c.fav, 90.17, pg_temp._hoje(), 'pix', null, array[r15], null, c.dono);
  v_tx3 := pg_temp._linha(90.17);
  update public.anotacoes_do_extrato set status = 'aplicada', aplicada_em = now(), bank_transaction_id = v_tx3
   where id = (rs->>'anotacao_id')::uuid;
  v_pay3 := pg_temp._aprovado(v_tx3, 95.17);       -- o lançamento não bate com a linha
  v_n := public._diarias_aplicar_divisoes_pendentes(20);
  select * into dq from public.diarias_pagamentos_divididos where anotacao_id = (rq->>'anotacao_id')::uuid;
  select * into ds from public.diarias_pagamentos_divididos where anotacao_id = (rs->>'anotacao_id')::uuid;
  -- P11 (a): o pagamento com baixa registrada à parte ("Conciliado com o extrato") não se divide por aqui
  v_tx := pg_temp._linha(140);
  v_pay4 := pg_temp._aprovado(v_tx, 140);
  insert into public.payments (payable_id, amount, status, notes, bank_transaction_id)
  values (v_pay4, 140, 'confirmed', 'Conciliado com o extrato (teste)', v_tx);
  begin
    perform public.dividir_pagamento_do_freelancer(v_pay4, array[r15], c.dono);
  exception when sqlstate '22023' then v_conc := case when sqlerrm like '%baixa registrada à parte%' then sqlstate else sqlerrm end;
  end;
  -- P11 (b): o Pix sem a data dita vai sem ela (anotação com a janela larga) e a saída diz o que a anotação disse
  v_sem_data := public.registrar_pagamento_do_freelancer(c.fav, 63.71, null, 'pix', null, '{}'::uuid[], null, c.dono);
  -- P11 (c): bolso do sócio (P4): a divisão guarda a conta da parte do reembolso; cancelar só a das diárias não
  -- reabre o reembolso, cancelar a do reembolso reabre
  select * into d4 from public.diarias_pagamentos_divididos
   where c.r4 = any (reembolsos) and status = 'aplicada' order by criado_em desc limit 1;
  v_partes_socio := d4.lancamentos;
  update public.payables set status = 'cancelled' where id = d4.payable_id and not (id = any (coalesce(d4.lancamentos, '{}')));
  p_meio := public.proposta_de_divisao_do_pagamento(c.fav, 1000, c.dono);
  update public.payables set status = 'cancelled' where id = any (coalesce(d4.lancamentos, '{}'));
  p_fim := public.proposta_de_divisao_do_pagamento(c.fav, 1000, c.dono);

  select array_agg(nome) into v_falhas from (values
    ('pago_bloqueia', not (v_bloq->>'ok')::boolean and v_bloq->'bloqueios'->0->>'motivo' = 'reembolso_dividido'
                      and v_bloq->'bloqueios'->0->>'como_destravar' like '%Desfazer a divisão%'
                      and (select status from public.diarias_reembolsos where id = r10) = 'ativo'),
    ('sai_da_pendente', (v_ok1->>'ok')::boolean and dp.status = 'pendente' and dp.reembolsos = array[r12]
                        and dp.partes = '[{"valor": 95.29, "codigos": [], "categoria": "Diárias de freelancers"}, {"valor": 22.00, "codigos": ["CMP-99922"], "categoria": "Pedágio e estacionamento"}]'::jsonb
                        and (select status from public.diarias_reembolsos where id = r11) = 'cancelado'),
    ('ultimo_desfaz', (v_ok2->>'ok')::boolean
                      and (select status from public.diarias_pagamentos_divididos where id = dp.id) = 'desfeita'),
    ('manutencao_sem_cancelado', dq.status = 'aplicada' and dq.reembolsos = array[r14]
                                 and pg_temp._partes(v_pay2) = 'Diárias de freelancers 197.43 + Pedágio e estacionamento 14.00'),
    ('regra_desfaz', ds.status = 'desfeita' and ds.motivo like 'não deu para dividir:%'
                     and pg_temp._partes(v_pay3) = 'Diárias de freelancers 95.17'),
    ('conciliado_recusa', v_conc = '22023' and pg_temp._partes(v_pay4) = 'Diárias de freelancers 140.00'),
    ('pix_sem_data', (v_sem_data->>'ok')::boolean and v_sem_data ? 'substituidas' and v_sem_data ? 'falta_quem'
                     and (select data_exata from public.anotacoes_do_extrato where id = (v_sem_data->>'anotacao_id')::uuid) = false),
    ('socio_partes', coalesce(cardinality(v_partes_socio), 0) = 1
                     and not (p_meio->'em_aberto' @> jsonb_build_array(jsonb_build_object('id', c.r4)))
                     and p_fim->'em_aberto' @> jsonb_build_array(jsonb_build_object('id', c.r4)))
  ) as t(nome, ok) where not coalesce(ok, false);
  insert into _resultado values ('P9/P10/P11 cancelar o CMP com o reembolso pago numa divisão bloqueia; da pendente ele sai; a manutenção não trava; conciliado não divide; Pix sem data; sócio por parte',
    v_falhas is null,
    coalesce('falhou: ' || array_to_string(v_falhas, ', ') || ' | ', '')
    || 'bloqueio=' || coalesce(v_bloq->'bloqueios'->0->>'motivo', v_bloq->>'ok', '-') || ' pendente=' || coalesce(dp.status, '-')
    || '/' || coalesce(dp.partes::text, '-') || ' manutencao=' || coalesce(dq.status, '-') || '/' || coalesce(ds.status, '-')
    || ' ' || coalesce(ds.motivo, '') || ' conciliado=' || v_conc || ' socio=' || coalesce(cardinality(v_partes_socio)::text, '-'));
exception when others then
  insert into _resultado values ('P9/P10/P11 cancelar o CMP com o reembolso pago numa divisão bloqueia; da pendente ele sai; a manutenção não trava; conciliado não divide; Pix sem data; sócio por parte', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ P8 ═════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  c _ctx := pg_temp._c();
  v_anon text := 'leu';
  v_auth_escreve text := 'escreveu';
  v_tec integer;
  v_adm integer;
begin
  begin
    execute 'set local role anon';
    perform 1 from public.diarias_pagamentos_divididos limit 1;
  exception when others then
    v_anon := sqlstate;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', c.tecnico_user::text, true);
  execute 'set local role authenticated';
  select count(*) into v_tec from public.diarias_pagamentos_divididos where favorecido_id = c.fav;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', c.dono::text, true);
  execute 'set local role authenticated';
  select count(*) into v_adm from public.diarias_pagamentos_divididos where favorecido_id = c.fav;
  begin
    insert into public.diarias_pagamentos_divididos (favorecido_id, reembolsos) values (c.fav, array[c.r1]);
  exception when others then
    v_auth_escreve := sqlstate;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', '', true);
  insert into _resultado values ('P8 RLS: anon nada; authenticated só lê, e só quem vê a folha; as RPCs sem anon',
    v_anon = '42501' and v_tec = 0 and v_adm >= 3 and v_auth_escreve = '42501'
    and not has_function_privilege('anon', 'public.registrar_pagamento_do_freelancer(uuid, numeric, date, text, uuid, uuid[], text, uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.dividir_pagamento_do_freelancer(uuid, uuid[], uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public._diarias_dividir(uuid, uuid[], uuid, uuid)', 'execute'),
    'anon=' || v_anon || ' tecnico=' || v_tec || ' admin=' || v_adm || ' admin_escreve=' || v_auth_escreve);
exception when others then
  execute 'reset role';
  insert into _resultado values ('P8 RLS: anon nada; authenticated só lê, e só quem vê a folha; as RPCs sem anon', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
