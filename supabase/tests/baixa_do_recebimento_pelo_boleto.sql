-- Prova: a conta a RECEBER de NF-e é baixada quando o banco mostra o crédito do boleto do cliente — e SÓ no caso seguro
-- (migration 20270228100000_baixa_do_recebimento_pelo_boleto).
--
-- ═══ COMO RODAR ═══
--
--   npx supabase@2.111.0 db query --linked -f <caminho completo>/supabase/tests/baixa_do_recebimento_pelo_boleto.sql --output json
--
-- Seguro em produção: termina em ROLLBACK. Cria conta de banco, clientes, notas, contas a receber, créditos e propostas
-- de teste só dentro da transação. A função varre a fila inteira, então as provas olham o ESTADO de cada conta e de
-- cada linha de teste, nunca a contagem geral (o R0 mostra o que ela baixaria no dado real). Cada caso usa um valor
-- próprio (base sorteada, passo de R$ 10): a regra conta contas e créditos de MESMO VALOR por perto, e valores
-- repetidos entre casos se atrapalhariam. Datas ancoradas em _hoje_brt(). Cada caso roda no seu sub-bloco: um insert
-- barrado vira linha ok = false com o erro, em vez de derrubar o relatório. Caso negativo, sempre que cabe, é par
-- mínimo: prova que ficou, conserta SÓ a condição que faltava e prova que baixou. A tabela final tem de mostrar
-- ok = true em todas as linhas.
-- Cláusula SEM caso próprio (revisão de 24/11/2026): "nenhum pagamento ligado à linha" isolada das outras travas —
-- inserir pagamento solto dispara os gatilhos de payments; ela é exercida junto com o registro em R2b e R2d.
--
-- ANTES de a migration estar aplicada: rodar o ensaio (a migration + este corpo na mesma transação).
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
create temp table _negativos (caso text, conta uuid, linha uuid) on commit drop;
create temp table _ctx (conexao uuid) on commit drop;

with nova as (
  insert into public.bank_connections (provider, external_id, label, account_kind)
  values ('manual', 'teste-baixa-rec-' || gen_random_uuid(), 'Conta Teste Baixa do Recebimento', 'bank')
  returning id)
insert into _ctx select id from nova;

-- Uma NF-e de teste do cliente.
create function pg_temp.nf(p_cli uuid, p_status text default 'authorized', p_ambiente text default 'producao') returns uuid
language plpgsql as $$
declare v uuid;
begin
  insert into public.issued_fiscal_documents (document_type, origin_type, client_id, environment, status, series, number, stock_settled_at)
  values ('nfe', 'manual', p_cli, p_ambiente, p_status, 999, 900000 + floor(random() * 90000)::int, now())
  returning id into v;
  return v;
end $$;

-- Uma conta a receber em aberto, como a que a NF-e grava (emissão = vencimento, para não cruzar mês).
create function pg_temp.conta(p_cli uuid, p_nf uuid, p_valor numeric, p_venc date, p_status text default 'pending',
                              p_pago numeric default 0, p_forma text default '14') returns uuid
language plpgsql as $$
declare v uuid;
begin
  insert into public.receivables (client_id, description, issue_date, due_date, amount, paid_amount, balance_amount, status,
                                  payment_method, notes, issued_fiscal_document_id)
  values (p_cli, 'NF-e 999/1 (parcela 1/1) TESTE', p_venc, p_venc, p_valor, p_pago, p_valor - p_pago, p_status,
          p_forma, 'Gerado a partir da NF-e (teste)', p_nf)
  returning id into v;
  return v;
end $$;

-- Uma entrada do banco, com a proposta na fila (p_fila nulo: sem proposta).
create function pg_temp.credito(p_valor numeric, p_data date, p_desc text default 'CREDITO DE BOLETO', p_metodo text default 'OTHER',
                                p_fila text default 'pending', p_situacao text default 'POSTED', p_tipo text default 'credit',
                                p_fonte text default 'bank', p_conexao boolean default true,
                                p_kind text default 'create_receivable') returns uuid
language plpgsql as $$
declare v uuid;
begin
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, source_type, provider, payment_method,
                                        provider_category, tx_status, bank_ref_id, bank_connection_id)
  values (p_data, p_desc, p_valor, p_tipo, p_fonte, 'pluggy', p_metodo, 'Transfer - Bank Slip', p_situacao,
          'teste-baixa-rec-' || gen_random_uuid(), case when p_conexao then (select conexao from _ctx) end)
  returning id into v;
  if p_fila is not null then
    insert into public.finance_review_queue (kind, status, bank_transaction_id, title, confidence, suggested_amount, suggested_date,
                                             suggested_category, dre_group, suggested_description)
    values (p_kind, p_fila, v, 'Receita: ' || p_desc, 30, p_valor, p_data, 'Outras receitas', 'receita', p_desc);
  end if;
  return v;
end $$;

-- A conta ficou paga por esta linha do banco?
create function pg_temp.baixada(p_conta uuid, p_tx uuid) returns boolean
language sql as $$
  select exists (select 1 from public.receivables where id = p_conta and status = 'paid' and bank_transaction_id = p_tx and balance_amount = 0)
     and exists (select 1 from public.payments where receivable_id = p_conta and bank_transaction_id = p_tx and status = 'confirmed')
     and exists (select 1 from public.finance_review_queue where bank_transaction_id = p_tx and status = 'approved' and automatica = 'boleto')
$$;

-- Nada aconteceu entre esta conta e esta linha: sem vínculo, sem pagamento, sem marca na fila, sem registro.
create function pg_temp.intacta(p_conta uuid, p_tx uuid) returns boolean
language sql as $$
  select not exists (select 1 from public.receivables where id = p_conta and (bank_transaction_id = p_tx or status = 'paid'))
     and not exists (select 1 from public.payments where receivable_id = p_conta and bank_transaction_id = p_tx)
     and not exists (select 1 from public.bank_transactions where id = p_tx and reconciled_payment_id is not null)
     and not exists (select 1 from public.finance_review_queue where bank_transaction_id = p_tx and automatica = 'boleto')
     and not exists (select 1 from public.reconciliation_log where bank_transaction_id = p_tx and receivable_id = p_conta)
$$;

-- Caso negativo que fica até o fim: guarda para a varredura final (R99).
create function pg_temp.fica(p_caso text, p_conta uuid, p_tx uuid) returns boolean
language plpgsql as $$
begin
  insert into _negativos values (p_caso, p_conta, p_tx);
  return pg_temp.intacta(p_conta, p_tx);
end $$;

do $$
declare
  v_hoje date := public._hoje_brt();
  v_b numeric := 700000 + floor(random() * 90000);
  k int := 0;
  v numeric;
  v_c1 uuid; v_c2 uuid; v_n1 uuid; v_n2 uuid; v_nx uuid;
  a uuid; a2 uuid; t uuid; t2 uuid; p uuid; x uuid;
  r jsonb;
  ok boolean;
begin
  -- a chave ligada, qualquer que seja o estado de produção
  delete from public.app_settings where key = 'boleto_recebido_baixa_modo';
  insert into public.clients (type, name) values ('company', 'CLIENTE UM DO TESTE DA BAIXA DO RECEBIMENTO PELO BOLETO ' || gen_random_uuid()) returning id into v_c1;
  insert into public.clients (type, name) values ('company', 'CLIENTE DOIS DO TESTE DA BAIXA DO RECEBIMENTO ' || gen_random_uuid()) returning id into v_c2;
  v_n1 := pg_temp.nf(v_c1);
  v_n2 := pg_temp.nf(v_c2);

  -- R0 (informativo): o que a função baixaria hoje no dado real, sem gravar
  r := public.baixar_recebido_pelo_boleto('{}', v_hoje, true);
  insert into _resultado values ('R0 (informativo) o que baixaria no dado real, simulando', true, left(r::text, 900));

  -- R1: o caso seguro → baixa, com tudo no lugar
  begin
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := pg_temp.baixada(a, t)
      and exists (select 1 from public.receivables where id = a and paid_amount = v)
      and exists (select 1 from public.bank_transactions where id = t and reconciled and reconciled_payment_id is not null)
      and exists (select 1 from public.payments where receivable_id = a and status = 'confirmed' and amount = v
                     and payment_date = v_hoje and notes ilike 'concilia%' and bank_transaction_id = t)
      and exists (select 1 from public.finance_review_queue where bank_transaction_id = t and status = 'approved'
                     and automatica = 'boleto' and decided_at is not null and decided_by is null and created_receivable_id is null
                     and decision_note = 'CLIENTE UM DO TESTE DA BAIXA DO RECEBIME — recebimento baixado sozinho pelo boleto: NF-e 999/1 (parcela 1/1) TESTE, vencimento '
                                         || to_char(v_hoje, 'DD/MM/YYYY') || ' (mesmo valor, crédito no dia do vencimento)')
      and exists (select 1 from public.reconciliation_log where bank_transaction_id = t and receivable_id = a and acao = 'conciliou'
                     and autor is null and detalhe like 'Baixa automática pelo boleto%')
      -- os leitores (tela, assistente, resumo) reconhecem a baixa de pé por ela ter UM registro só na linha
      and (select count(*) from public.reconciliation_log where bank_transaction_id = t) = 1
      and exists (select 1 from jsonb_array_elements(r -> 'itens') i where (i ->> 'transacao')::uuid = t and (i ->> 'conta')::uuid = a
                     and (i ->> 'valor')::numeric = v and (i ->> 'vencimento')::date = v_hoje and i ->> 'cliente' like 'CLIENTE UM DO TESTE%');
    insert into _resultado values ('R1 caso seguro: baixa, pagamento na data do banco, marcada na fila (sem created_receivable_id) e no registro', ok, left(r::text, 300));

    -- R2: desfazer devolve a conta para em aberto (não cancela) e nem a linha nem a conta voltam a ser baixadas sozinhas
    r := public.desfazer_aprovacao('receivable', a, 'teste da baixa do recebimento', null);
    ok := exists (select 1 from public.receivables where id = a and status = 'pending' and bank_transaction_id is null and balance_amount = v and paid_amount = 0)
      and exists (select 1 from public.payments where receivable_id = a and status = 'cancelled')
      and not exists (select 1 from public.payments where receivable_id = a and status = 'confirmed')
      and exists (select 1 from public.bank_transactions where id = t and not reconciled and reconciled_payment_id is null)
      and exists (select 1 from public.reconciliation_log where bank_transaction_id = t and receivable_id = a and acao = 'desconciliou');
    insert into _resultado values ('R2a desfazer: conta volta a ficar em aberto (não cancelada), pagamento estornado, linha solta', ok, left(r::text, 200));
    -- a análise seguinte propõe a linha de novo
    insert into public.finance_review_queue (kind, status, bank_transaction_id, title, confidence, suggested_amount, suggested_date)
    values ('create_receivable', 'pending', t, 'Receita: CREDITO DE BOLETO', 30, v, v_hoje);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := exists (select 1 from public.receivables where id = a and status = 'pending' and bank_transaction_id is null)
      and exists (select 1 from public.finance_review_queue where bank_transaction_id = t and status = 'pending')
      and not exists (select 1 from public.payments where receivable_id = a and status = 'confirmed');
    insert into _resultado values ('R2b a linha em que a baixa foi desfeita nunca mais é baixada sozinha', ok, '');
    -- o banco manda uma cópia da linha: a CONTA desfeita também não volta sozinha
    update public.bank_transactions set dismissed_kind = 'duplicata', reconciled = true where id = t;
    update public.finance_review_queue set status = 'superseded' where bank_transaction_id = t and status = 'pending';
    t2 := pg_temp.credito(v, v_hoje);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R2c outra linha igual depois do desfazer: a conta desfeita não volta a ser baixada', pg_temp.fica('R2c', a, t2), '');
  exception when others then
    insert into _resultado values ('R1/R2 caso seguro e desfazer', false, sqlstate || ': ' || sqlerrm);
  end;

  -- R2d: estornar o pagamento pelo histórico da conta (desfazer_aplicacao) também tira a conta da baixa sozinha
  begin
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := pg_temp.baixada(a, t);
    select id into p from public.payments where receivable_id = a and status = 'confirmed';
    perform public.desfazer_aplicacao(p, 'teste da baixa do recebimento', null);
    insert into public.finance_review_queue (kind, status, bank_transaction_id, title, confidence, suggested_amount, suggested_date)
    select 'create_receivable', 'pending', t, 'Receita: CREDITO DE BOLETO', 30, v, v_hoje
     where not exists (select 1 from public.finance_review_queue where bank_transaction_id = t and status = 'pending' and kind = 'create_receivable');
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := ok and not exists (select 1 from public.payments where receivable_id = a and status = 'confirmed')
      and not exists (select 1 from public.receivables where id = a and (status = 'paid' or bank_transaction_id is not null));
    insert into _resultado values ('R2d pagamento estornado pelo histórico (desfazer_aplicacao): não baixa de novo', ok, '');
  exception when others then
    insert into _resultado values ('R2d pagamento estornado pelo histórico (desfazer_aplicacao): não baixa de novo', false, sqlstate || ': ' || sqlerrm);
  end;

  -- R1b / R1c: conta 'overdue' e forma de pagamento boleto (15) também baixam
  begin
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje, 'overdue');
    t := pg_temp.credito(v, v_hoje);
    k := k + 1; v := v_b + 10 * k + 0.07;
    a2 := pg_temp.conta(v_c2, v_n2, v, v_hoje, 'pending', 0, '15');
    t2 := pg_temp.credito(v, v_hoje, 'credito de boleto ', 'BOLETO');
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R1b conta com status overdue: baixa', pg_temp.baixada(a, t), '');
    insert into _resultado values ('R1c forma de pagamento 15 (boleto), descrição com caixa e espaço diferentes: baixa', pg_temp.baixada(a2, t2), '');
  exception when others then
    insert into _resultado values ('R1b/R1c overdue e forma 15', false, sqlstate || ': ' || sqlerrm);
  end;

  -- R3: um centavo de diferença, para mais e para menos → não baixa
  begin
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v + 0.01, v_hoje);
    k := k + 1; v := v_b + 10 * k + 0.07;
    a2 := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t2 := pg_temp.credito(v - 0.01, v_hoje);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R3a crédito um centavo MAIOR: não baixa', pg_temp.fica('R3a', a, t), '');
    insert into _resultado values ('R3b crédito um centavo MENOR: não baixa', pg_temp.fica('R3b', a2, t2), '');
  exception when others then
    insert into _resultado values ('R3 um centavo de diferença', false, sqlstate || ': ' || sqlerrm);
  end;

  -- R4: o crédito tem de cair NO DIA do vencimento
  begin
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje - 1);
    t := pg_temp.credito(v, v_hoje);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := pg_temp.intacta(a, t);
    update public.receivables set due_date = v_hoje where id = a;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R4a pago um dia DEPOIS do vencimento: não baixa; com o vencimento no dia, baixa', ok and pg_temp.baixada(a, t), '');
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje + 1);
    t := pg_temp.credito(v, v_hoje);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R4b pago um dia ANTES do vencimento: não baixa', pg_temp.fica('R4b', a, t), '');
  exception when others then
    insert into _resultado values ('R4 dia do vencimento', false, sqlstate || ': ' || sqlerrm);
  end;

  -- R5: conta parcialmente paga → não baixa, nem pelo valor cheio nem pelo saldo
  begin
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje, 'partially_paid', 3.33);
    t := pg_temp.credito(v, v_hoje);
    t2 := pg_temp.credito(v - 3.33, v_hoje);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R5a conta parcialmente paga, crédito do valor cheio: não baixa', pg_temp.fica('R5a', a, t), '');
    insert into _resultado values ('R5b conta parcialmente paga, crédito do saldo: não baixa', pg_temp.fica('R5b', a, t2), '');
  exception when others then
    insert into _resultado values ('R5 conta parcialmente paga', false, sqlstate || ': ' || sqlerrm);
  end;

  -- R6: só conta nascida de NF-e autorizada de produção, do mesmo cliente, com duplicata/boleto
  begin
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, null, v, v_hoje);
    t := pg_temp.credito(v, v_hoje);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := pg_temp.intacta(a, t);
    update public.receivables set issued_fiscal_document_id = v_n1 where id = a;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R6a conta sem NF: não baixa; com a NF, baixa', ok and pg_temp.baixada(a, t), '');

    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje, 'pending', 0, null);
    t := pg_temp.credito(v, v_hoje);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := pg_temp.intacta(a, t);
    update public.receivables set payment_method = '17' where id = a;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := ok and pg_temp.intacta(a, t);
    update public.receivables set payment_method = '14' where id = a;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R6b forma de pagamento vazia ou Pix (17): não baixa; duplicata (14), baixa', ok and pg_temp.baixada(a, t), '');

    k := k + 1; v := v_b + 10 * k + 0.07;
    v_nx := pg_temp.nf(v_c1, 'cancelled');
    a := pg_temp.conta(v_c1, v_nx, v, v_hoje);
    t := pg_temp.credito(v, v_hoje);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := pg_temp.intacta(a, t);
    update public.issued_fiscal_documents set status = 'authorized' where id = v_nx;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R6c NF cancelada: não baixa; autorizada, baixa', ok and pg_temp.baixada(a, t), '');

    k := k + 1; v := v_b + 10 * k + 0.07;
    v_nx := pg_temp.nf(v_c1, 'authorized', 'homologacao');
    a := pg_temp.conta(v_c1, v_nx, v, v_hoje);
    t := pg_temp.credito(v, v_hoje);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := pg_temp.intacta(a, t);
    update public.issued_fiscal_documents set environment = 'producao' where id = v_nx;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R6d NF de homologação: não baixa; de produção, baixa', ok and pg_temp.baixada(a, t), '');

    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n2, v, v_hoje);
    t := pg_temp.credito(v, v_hoje);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R6e NF de outro cliente: não baixa', pg_temp.fica('R6e', a, t), '');
  exception when others then
    insert into _resultado values ('R6 conta de NF-e com duplicata/boleto', false, sqlstate || ': ' || sqlerrm);
  end;

  -- R7: duas contas candidatas (mesmo valor, mesmo dia) → nenhuma baixa, com um crédito ou com dois
  begin
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    a2 := pg_temp.conta(v_c2, v_n2, v, v_hoje);
    t := pg_temp.credito(v, v_hoje);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := pg_temp.intacta(a, t) and pg_temp.intacta(a2, t);
    t2 := pg_temp.credito(v, v_hoje);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := ok and pg_temp.fica('R7a', a, t) and pg_temp.fica('R7a', a2, t) and pg_temp.fica('R7a', a, t2) and pg_temp.fica('R7a', a2, t2);
    insert into _resultado values ('R7a duas contas iguais de clientes diferentes: nenhuma baixa, nem quando chega o segundo crédito', ok, '');

    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    a2 := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R7b duas contas iguais do MESMO cliente no mesmo dia: nenhuma baixa', pg_temp.fica('R7b', a, t) and pg_temp.fica('R7b', a2, t), '');
  exception when others then
    insert into _resultado values ('R7 duas contas candidatas', false, sqlstate || ': ' || sqlerrm);
  end;

  -- R8: nada parecido por perto
  begin
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje);
    t2 := pg_temp.credito(v, v_hoje);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R8a dois créditos iguais no mesmo dia para uma conta: nenhum baixa', pg_temp.fica('R8a', a, t) and pg_temp.fica('R8a', a, t2), '');

    -- a parcela anterior, de valor igual, ainda em aberto: o cliente pode estar pagando a atrasada
    k := k + 1; v := v_b + 10 * k + 0.07;
    a2 := pg_temp.conta(v_c1, v_n1, v, v_hoje - 28);
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := pg_temp.intacta(a, t) and pg_temp.intacta(a2, t);
    update public.receivables set status = 'paid', paid_amount = amount, balance_amount = 0 where id = a2;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R8b parcela anterior de mesmo valor em aberto: não baixa; com ela paga, baixa a do dia', ok and pg_temp.baixada(a, t), '');

    -- outra conta em aberto de mesmo valor que NÃO é de NF-e (ex.: de OS), vencida
    k := k + 1; v := v_b + 10 * k + 0.07;
    a2 := pg_temp.conta(v_c2, null, v, v_hoje - 5, 'pending', 0, null);
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := pg_temp.intacta(a, t) and pg_temp.intacta(a2, t);
    update public.receivables set status = 'cancelled' where id = a2;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R8c outra conta vencida de mesmo valor, de qualquer origem: não baixa; sem ela, baixa', ok and pg_temp.baixada(a, t), '');

    -- outro crédito solto de mesmo valor por perto, com outra descrição e sem proposta na fila
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje);
    t2 := pg_temp.credito(v, v_hoje - 10, 'TRANSFERENCIA RECEBIDA TESTE', 'PIX', null);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := pg_temp.intacta(a, t) and pg_temp.intacta(a, t2);
    update public.bank_transactions set dismissed_kind = 'duplicata', reconciled = true where id = t2;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R8d outro crédito solto de mesmo valor em 45 dias: não baixa; sem ele, baixa', ok and pg_temp.baixada(a, t), '');
  exception when others then
    insert into _resultado values ('R8 nada parecido por perto', false, sqlstate || ': ' || sqlerrm);
  end;

  -- R9: linha com qualquer registro de conciliação é do dono
  begin
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje);
    insert into public.reconciliation_log (acao, bank_transaction_id, valor, detalhe) values ('desconciliou', t, v, 'teste da baixa do recebimento');
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := exists (select 1 from public.receivables where id = a and status = 'pending' and bank_transaction_id is null)
      and exists (select 1 from public.finance_review_queue where bank_transaction_id = t and status = 'pending');
    insert into _negativos values ('R9', a, null);
    insert into _resultado values ('R9 linha que já teve um vínculo desfeito: não baixa', ok, '');
  exception when others then
    insert into _resultado values ('R9 linha que já teve um vínculo desfeito: não baixa', false, sqlstate || ': ' || sqlerrm);
  end;

  -- R10: linha reservada da rodada fica; sem a reserva, baixa
  begin
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje);
    r := public.baixar_recebido_pelo_boleto(array[t], v_hoje);
    ok := pg_temp.intacta(a, t);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R10 linha reservada (p_exceto) fica; sem a reserva, baixa', ok and pg_temp.baixada(a, t), '');
  exception when others then
    insert into _resultado values ('R10 linha reservada (p_exceto) fica; sem a reserva, baixa', false, sqlstate || ': ' || sqlerrm);
  end;

  -- R11: chave desligada → pula e não toca em nada; religada, baixa
  begin
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje);
    insert into public.app_settings (key, value) values ('boleto_recebido_baixa_modo', 'desligado')
      on conflict (key) do update set value = excluded.value;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := coalesce((r ->> 'pulado')::boolean, false) and pg_temp.intacta(a, t);
    delete from public.app_settings where key = 'boleto_recebido_baixa_modo';
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R11 chave boleto_recebido_baixa_modo = desligado pula; religada, baixa', ok and pg_temp.baixada(a, t), '');
  exception when others then
    delete from public.app_settings where key = 'boleto_recebido_baixa_modo';
    insert into _resultado values ('R11 chave boleto_recebido_baixa_modo = desligado pula; religada, baixa', false, sqlstate || ': ' || sqlerrm);
  end;

  -- R12: só o crédito de boleto de banco conectado, pela descrição exata
  begin
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje, 'TRANSFERENCIA RECEBIDA TESTE', 'PIX');
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R12a entrada por Pix: não baixa', pg_temp.fica('R12a', a, t), '');

    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje, 'REF. LIQ. BOLETO COMP EXTERNO');
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := pg_temp.intacta(a, t);
    update public.bank_transactions set description = 'CREDITO DE BOLETO' where id = t;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R12b outro texto do banco para boleto: não baixa; com a descrição exata, baixa', ok and pg_temp.baixada(a, t), '');

    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje, 'ESTORNO CREDITO DE BOLETO');
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R12c descrição que só CONTÉM o texto (estorno): não baixa', pg_temp.fica('R12c', a, t), '');

    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje, 'CREDITO DE BOLETO', 'BOLETO', 'pending', 'POSTED', 'credit', 'credit_card');
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R12d linha de cartão de crédito: não baixa', pg_temp.fica('R12d', a, t), '');

    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje, 'CREDITO DE BOLETO', 'OTHER', 'pending', 'POSTED', 'debit');
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R12e SAÍDA com a descrição do boleto: não baixa', pg_temp.fica('R12e', a, t), '');

    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje, 'CREDITO DE BOLETO', 'OTHER', 'pending', 'POSTED', 'credit', 'bank', false);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R12f linha sem conta de banco conectada (importada à mão): não baixa', pg_temp.fica('R12f', a, t), '');

    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje, 'CREDITO DE BOLETO', 'PIX');
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R12g descrição do boleto com forma Pix: não baixa', pg_temp.fica('R12g', a, t), '');
  exception when others then
    insert into _resultado values ('R12 só o crédito de boleto', false, sqlstate || ': ' || sqlerrm);
  end;

  -- R13: só linha efetivada (POSTED)
  begin
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje, 'CREDITO DE BOLETO', 'OTHER', 'pending', 'PENDING');
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := pg_temp.intacta(a, t);
    update public.bank_transactions set tx_status = null where id = t;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := ok and pg_temp.intacta(a, t);
    update public.bank_transactions set tx_status = 'POSTED' where id = t;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R13 linha PENDING ou sem situação: não baixa; POSTED, baixa', ok and pg_temp.baixada(a, t), '');
  exception when others then
    insert into _resultado values ('R13 linha PENDING ou sem situação: não baixa; POSTED, baixa', false, sqlstate || ': ' || sqlerrm);
  end;

  -- R14: só com proposta de receita pendente na fila
  begin
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje, 'CREDITO DE BOLETO', 'OTHER', 'rejected');
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R14a proposta recusada pelo dono: não baixa', pg_temp.fica('R14a', a, t), '');
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje, 'CREDITO DE BOLETO', 'OTHER', null);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R14b linha sem proposta na fila: não baixa', pg_temp.fica('R14b', a, t), '');
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje, 'CREDITO DE BOLETO', 'OTHER', 'pending', 'POSTED', 'credit', 'bank', true, 'internal_transfer');
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R14c proposta de outro tipo (transferência interna): não baixa', pg_temp.fica('R14c', a, t), '');
    -- uma proposta de receita + outra pendente para a mesma linha
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje);
    insert into public.finance_review_queue (kind, status, bank_transaction_id, title, confidence, suggested_amount, suggested_date)
    values ('internal_transfer', 'pending', t, 'Transferência entre contas (teste)', 30, v, v_hoje);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := pg_temp.intacta(a, t);
    update public.finance_review_queue set status = 'superseded' where bank_transaction_id = t and kind = 'internal_transfer';
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R14d outra proposta pendente para a mesma linha: não baixa; sem ela, baixa', ok and pg_temp.baixada(a, t), '');
    -- outra proposta pendente que cita a linha como a "outra ponta"
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje);
    k := k + 1;
    t2 := pg_temp.credito(v_b + 10 * k + 0.07, v_hoje, 'TRANSFERENCIA RECEBIDA TESTE', 'PIX', null);
    insert into public.finance_review_queue (kind, status, bank_transaction_id, related_transaction_id, title, confidence, suggested_amount, suggested_date)
    values ('internal_transfer', 'pending', t2, t, 'Transferência entre contas (teste)', 30, v, v_hoje);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R14e linha citada por outra proposta pendente (related_transaction_id): não baixa', pg_temp.fica('R14e', a, t), '');
  exception when others then
    insert into _resultado values ('R14 proposta na fila', false, sqlstate || ': ' || sqlerrm);
  end;

  -- R15: linha tirada da fila ou já conciliada
  begin
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje);
    update public.bank_transactions set dismissed_kind = 'manual' where id = t;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R15a linha fora da fila (dispensada): não baixa', pg_temp.fica('R15a', a, t), '');
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje);
    update public.bank_transactions set reconciled = true where id = t;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R15b linha já conciliada: não baixa', pg_temp.fica('R15b', a, t), '');
  exception when others then
    insert into _resultado values ('R15 linha dispensada ou conciliada', false, sqlstate || ': ' || sqlerrm);
  end;

  -- R16: conta cancelada; conta já casada com outra linha
  begin
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje, 'cancelled');
    t := pg_temp.credito(v, v_hoje);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R16a conta cancelada: não baixa', pg_temp.fica('R16a', a, t), '');
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje);
    k := k + 1;
    t2 := pg_temp.credito(v_b + 10 * k + 0.07, v_hoje, 'TRANSFERENCIA RECEBIDA TESTE', 'PIX', null);
    update public.receivables set bank_transaction_id = t2 where id = a;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R16b conta já casada com outra linha do banco: não baixa', pg_temp.fica('R16b', a, t), '');
  exception when others then
    insert into _resultado values ('R16 conta cancelada ou já casada', false, sqlstate || ': ' || sqlerrm);
  end;

  -- R17: crédito com data depois de "hoje" fica para depois
  begin
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje + 1);
    t := pg_temp.credito(v, v_hoje + 1);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := pg_temp.intacta(a, t);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje + 1);
    insert into _resultado values ('R17 crédito com data futura: não baixa hoje; no dia, baixa', ok and pg_temp.baixada(a, t), '');
  exception when others then
    insert into _resultado values ('R17 crédito com data futura: não baixa hoje; no dia, baixa', false, sqlstate || ': ' || sqlerrm);
  end;

  -- R19: conta de sinal, conta em fatura
  begin
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    update public.receivables set is_deposit = true where id = a;
    t := pg_temp.credito(v, v_hoje);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := pg_temp.intacta(a, t);
    update public.receivables set is_deposit = false where id = a;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R19a conta de sinal: não baixa; conta comum, baixa', ok and pg_temp.baixada(a, t), '');
  exception when others then
    insert into _resultado values ('R19a conta de sinal: não baixa; conta comum, baixa', false, sqlstate || ': ' || sqlerrm);
  end;
  begin
    k := k + 1; v := v_b + 10 * k + 0.07;
    insert into public.invoices (invoice_number, client_id, issue_date, due_date)
    values ('FAT-TESTE-' || left(gen_random_uuid()::text, 8), v_c1, v_hoje, v_hoje) returning id into x;
    perform set_config('marineflow.fatura', x::text, true);
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    update public.receivables set invoice_id = x where id = a;
    perform set_config('marineflow.fatura', '', true);
    t := pg_temp.credito(v, v_hoje);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R19b conta dentro de fatura: não é candidata (sem erro a cada rodada)',
      pg_temp.fica('R19b', a, t) and not exists (select 1 from jsonb_array_elements_text(r -> 'erros') e where e like '%fatura%'), left(r::text, 200));
  exception when others then
    perform set_config('marineflow.fatura', '', true);
    insert into _resultado values ('R19b conta dentro de fatura: não é candidata (sem erro a cada rodada)', false, sqlstate || ': ' || sqlerrm);
  end;

  -- R23: simular devolve o que baixaria e não grava nada
  begin
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje, true);
    ok := pg_temp.intacta(a, t) and coalesce((r ->> 'simulado')::boolean, false)
      and exists (select 1 from public.finance_review_queue where bank_transaction_id = t and status = 'pending')
      and exists (select 1 from jsonb_array_elements(r -> 'itens') i where (i ->> 'transacao')::uuid = t and (i ->> 'conta')::uuid = a);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R23 p_simular: mostra o que baixaria sem gravar; de verdade, baixa', ok and pg_temp.baixada(a, t), '');
  exception when others then
    insert into _resultado values ('R23 p_simular: mostra o que baixaria sem gravar; de verdade, baixa', false, sqlstate || ': ' || sqlerrm);
  end;

  -- R24: o que o dono já disse sobre a linha segura a baixa
  begin
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje);
    insert into public.anotacoes_do_extrato (sentido, valor, data_prevista, bank_transaction_id, status)
    values ('credit', v, v_hoje, t, 'aguardando');
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R24a linha com anotação do dono: não baixa', pg_temp.fica('R24a', a, t), '');
  exception when others then
    insert into _resultado values ('R24a linha com anotação do dono: não baixa', false, sqlstate || ': ' || sqlerrm);
  end;
  begin
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje);
    insert into public.pagadores_do_cliente (client_id, documento, nome, relacao, bank_transaction_id)
    values (v_c2, lpad((floor(random() * 1e13))::bigint::text, 14, '7'), 'PAGADOR DE TESTE', 'outro', t);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R24b linha com pagador guardado: não baixa', pg_temp.fica('R24b', a, t), '');
  exception when others then
    insert into _resultado values ('R24b linha com pagador guardado: não baixa', false, sqlstate || ': ' || sqlerrm);
  end;

  -- R25 / R26: a fila não pode discordar (cliente sugerido, vínculo sugerido)
  begin
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje);
    update public.finance_review_queue set suggested_client_id = v_c2 where bank_transaction_id = t;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := pg_temp.intacta(a, t);
    update public.finance_review_queue set suggested_client_id = v_c1 where bank_transaction_id = t;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R25 a fila sugeriu OUTRO cliente: não baixa; o mesmo cliente, baixa', ok and pg_temp.baixada(a, t), '');

    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje);
    k := k + 1;
    a2 := pg_temp.conta(v_c1, v_n1, v_b + 10 * k + 0.07, v_hoje + 20);
    update public.finance_review_queue
       set vinculo_sugerido = jsonb_build_object('principal', jsonb_build_object('tipo', 'receivable', 'lancamentoId', a2, 'nivel', 'weak'))
     where bank_transaction_id = t;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := pg_temp.intacta(a, t) and pg_temp.intacta(a2, t);
    update public.finance_review_queue
       set vinculo_sugerido = jsonb_build_object('principal', jsonb_build_object('tipo', 'receivable', 'lancamentoId', a, 'nivel', 'weak'))
     where bank_transaction_id = t;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R26 a fila sugeriu OUTRA conta: não baixa; a mesma conta (como no dado real), baixa', ok and pg_temp.baixada(a, t), '');
  exception when others then
    insert into _resultado values ('R25/R26 a fila não pode discordar', false, sqlstate || ': ' || sqlerrm);
  end;

  -- R27: outra conta PARCIALMENTE paga pelo banco (tem linha) cujo SALDO é igual ao crédito também segura
  begin
    k := k + 1; v := v_b + 10 * k + 0.07;
    k := k + 1;
    t2 := pg_temp.credito(v_b + 10 * k + 0.07, v_hoje - 6, 'TRANSFERENCIA RECEBIDA TESTE', 'PIX', null);
    update public.bank_transactions set reconciled = true where id = t2;
    a2 := pg_temp.conta(v_c2, null, v + 3.33, v_hoje - 5, 'partially_paid', 3.33, null);
    update public.receivables set bank_transaction_id = t2 where id = a2;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := pg_temp.intacta(a, t);
    update public.receivables set status = 'paid', paid_amount = amount, balance_amount = 0 where id = a2;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R27 outra conta parcialmente paga (com linha do banco) de SALDO igual: não baixa; com ela quitada, baixa', ok and pg_temp.baixada(a, t), '');
  exception when others then
    insert into _resultado values ('R27 outra conta parcialmente paga (com linha do banco) de SALDO igual: não baixa; com ela quitada, baixa', false, sqlstate || ': ' || sqlerrm);
  end;

  -- R28: a borda da janela dos créditos iguais soltos — 45 dias segura, 46 não
  begin
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje);
    t2 := pg_temp.credito(v, v_hoje - 45, 'TRANSFERENCIA RECEBIDA TESTE', 'PIX', null);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := pg_temp.intacta(a, t);
    update public.bank_transactions set transaction_date = v_hoje - 46 where id = t2;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R28 crédito igual solto a 45 dias: não baixa; a 46 dias, baixa', ok and pg_temp.baixada(a, t), '');
    -- o outro lado: crédito igual solto 45 dias DEPOIS do boleto (o caso do dado real, baixado semanas depois do crédito)
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje - 46);
    t := pg_temp.credito(v, v_hoje - 46);
    t2 := pg_temp.credito(v, v_hoje - 1, 'TRANSFERENCIA RECEBIDA TESTE', 'PIX', null);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := pg_temp.intacta(a, t);
    update public.bank_transactions set transaction_date = v_hoje where id = t2;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R28b crédito igual solto 45 dias DEPOIS do boleto: não baixa; 46 dias depois, baixa', ok and pg_temp.baixada(a, t), '');
  exception when others then
    insert into _resultado values ('R28 crédito igual solto a 45 dias: não baixa; a 46 dias, baixa', false, sqlstate || ': ' || sqlerrm);
  end;

  -- R29: linha que já teve OUTRA proposta decidida (aprovada, recusada ou automática) é do dono — isolado do registro
  begin
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje);
    insert into public.finance_review_queue (kind, status, bank_transaction_id, title, confidence, suggested_amount, suggested_date)
    values ('create_receivable', 'approved', t, 'Receita: CREDITO DE BOLETO (antiga)', 30, v, v_hoje) returning id into x;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := pg_temp.intacta(a, t);
    update public.finance_review_queue set status = 'rejected' where id = x;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := ok and pg_temp.intacta(a, t);
    update public.finance_review_queue set status = 'superseded', automatica = 'regra' where id = x;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := ok and pg_temp.intacta(a, t);
    update public.finance_review_queue set automatica = null where id = x;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R29 outra proposta da linha aprovada, recusada ou automática: não baixa; só substituída, baixa', ok and pg_temp.baixada(a, t), '');
  exception when others then
    insert into _resultado values ('R29 outra proposta da linha aprovada, recusada ou automática: não baixa; só substituída, baixa', false, sqlstate || ': ' || sqlerrm);
  end;

  -- R30: a fila sugeriu saldo de OS ou sinal de orçamento (vínculo SEM lancamentoId, destino em principal.id) → discorda
  begin
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje);
    update public.finance_review_queue
       set vinculo_sugerido = jsonb_build_object('principal', jsonb_build_object('tipo', 'service_order_balance', 'id', gen_random_uuid(), 'lancamentoId', null, 'nivel', 'weak'))
     where bank_transaction_id = t;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := pg_temp.intacta(a, t);
    update public.finance_review_queue set vinculo_sugerido = null where bank_transaction_id = t;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R30 a fila sugeriu saldo de OS (vínculo sem lancamentoId): não baixa; sem sugestão, baixa', ok and pg_temp.baixada(a, t), '');
  exception when others then
    insert into _resultado values ('R30 a fila sugeriu saldo de OS (vínculo sem lancamentoId): não baixa; sem sugestão, baixa', false, sqlstate || ': ' || sqlerrm);
  end;

  -- R31: comprovante ligado à linha → é do dono
  begin
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje);
    insert into public.comprovantes (numero, situacao, modo, rota, origem, dono_id, wa_message_id, phone_normalized, tipo_whatsapp, recebido_em, arquivo_sha256, bank_transaction_id)
    values (public._comprovante_proximo_numero(), 'lido', 'dono', 'comprovante', 'webhook',
            (select id from public.app_users where public.is_admin_or_financial(id) order by created_at limit 1),
            'TESTE-BAIXA-REC-' || gen_random_uuid(), '5500000000000', 'image', now(),
            md5(random()::text || clock_timestamp()::text) || md5(clock_timestamp()::text || random()::text), t)
    returning id into x;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := pg_temp.intacta(a, t);
    delete from public.comprovantes where id = x;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R31 linha com comprovante ligado: não baixa; sem ele, baixa', ok and pg_temp.baixada(a, t), '');
  exception when others then
    insert into _resultado values ('R31 linha com comprovante ligado: não baixa; sem ele, baixa', false, sqlstate || ': ' || sqlerrm);
  end;

  -- R32: conta ligada a OS, e conta que é saldo de orçamento agrupado → não são candidatas
  begin
    insert into public.vessels (client_id, name, asset_type) values (v_c1, 'Embarcação de teste da baixa', 'Lancha') returning id into x;
    insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, grand_total)
    values ('OS-T' || lpad((floor(random() * 1e7))::int::text, 7, '0'), v_c1, x, 'approved', 'approved', 'repair', 100)
    returning id into x;

    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    update public.receivables set service_order_id = x where id = a;
    t := pg_temp.credito(v, v_hoje);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := pg_temp.intacta(a, t);
    update public.receivables set service_order_id = null where id = a;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R32a conta ligada a uma OS: não baixa; sem a OS, baixa', ok and pg_temp.baixada(a, t), '');

    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    insert into public.orcamento_agrupamentos (agrupado_id, saldo_criado_id) values (x, a) returning id into p;
    t := pg_temp.credito(v, v_hoje);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := pg_temp.intacta(a, t);
    delete from public.orcamento_agrupamentos where id = p;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R32b conta que é saldo de orçamento agrupado: não baixa; sem o agrupamento, baixa', ok and pg_temp.baixada(a, t), '');
  exception when others then
    insert into _resultado values ('R32 conta ligada a OS ou a orçamento agrupado', false, sqlstate || ': ' || sqlerrm);
  end;

  -- R18 (por último: fecha mês): mês do crédito fechado e mês da nota fechado não são candidatos — e não viram erro
  begin
    k := k + 1; v := v_b + 10 * k + 0.07;
    a := pg_temp.conta(v_c1, v_n1, v, v_hoje);
    t := pg_temp.credito(v, v_hoje);
    k := k + 1;
    a2 := pg_temp.conta(v_c1, v_n1, v_b + 10 * k + 0.07, v_hoje);
    update public.receivables set issue_date = (date_trunc('month', v_hoje) - interval '5 days')::date where id = a2;
    t2 := pg_temp.credito(v_b + 10 * k + 0.07, v_hoje);

    insert into public.periodos_fechados (ano, mes) values (extract(year from v_hoje)::int, extract(month from v_hoje)::int);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := pg_temp.intacta(a, t) and pg_temp.intacta(a2, t2) and (r ->> 'barradas')::int = 0;
    delete from public.periodos_fechados where ano = extract(year from v_hoje)::int and mes = extract(month from v_hoje)::int;

    insert into public.periodos_fechados (ano, mes)
    values (extract(year from (date_trunc('month', v_hoje) - interval '5 days'))::int, extract(month from (date_trunc('month', v_hoje) - interval '5 days'))::int);
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    ok := ok and pg_temp.baixada(a, t) and pg_temp.intacta(a2, t2) and (r ->> 'barradas')::int = 0;
    delete from public.periodos_fechados
     where ano = extract(year from (date_trunc('month', v_hoje) - interval '5 days'))::int
       and mes = extract(month from (date_trunc('month', v_hoje) - interval '5 days'))::int;
    r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
    insert into _resultado values ('R18 mês do crédito fechado ou mês da NOTA fechado: não baixa e não vira erro; reaberto, baixa', ok and pg_temp.baixada(a2, t2), left(r::text, 200));
  exception when others then
    insert into _resultado values ('R18 mês do crédito fechado ou mês da NOTA fechado: não baixa e não vira erro; reaberto, baixa', false, sqlstate || ': ' || sqlerrm);
  end;

  -- R99: depois de todas as rodadas, nenhum caso negativo foi baixado por uma chamada posterior
  r := public.baixar_recebido_pelo_boleto('{}', v_hoje);
  insert into _resultado
  select 'R99 varredura final: nenhum caso negativo foi baixado depois',
         not exists (select 1 from _negativos n
                      where (n.linha is not null and not pg_temp.intacta(n.conta, n.linha))
                         or exists (select 1 from public.receivables rr where rr.id = n.conta and rr.status = 'paid')),
         coalesce((select string_agg(distinct n.caso, ', ') from _negativos n
                    where (n.linha is not null and not pg_temp.intacta(n.conta, n.linha))
                       or exists (select 1 from public.receivables rr where rr.id = n.conta and rr.status = 'paid')), '');
end $$;

-- R20–R22: só o serviço executa (as duas funções)
insert into _resultado
select 'R20 anon NÃO executa',
       not has_function_privilege('anon', 'public.baixar_recebido_pelo_boleto(uuid[], date, boolean)', 'execute')
   and not has_function_privilege('anon', 'public._contas_que_o_credito_de_boleto_paga(uuid)', 'execute'), ''
union all
select 'R21 authenticated NÃO executa',
       not has_function_privilege('authenticated', 'public.baixar_recebido_pelo_boleto(uuid[], date, boolean)', 'execute')
   and not has_function_privilege('authenticated', 'public._contas_que_o_credito_de_boleto_paga(uuid)', 'execute'), ''
union all
select 'R22 service_role executa',
       has_function_privilege('service_role', 'public.baixar_recebido_pelo_boleto(uuid[], date, boolean)', 'execute')
   and has_function_privilege('service_role', 'public._contas_que_o_credito_de_boleto_paga(uuid)', 'execute'), '';

select teste, ok, detalhe from _resultado order by (substring(teste from 'R(\d+)'))::int, teste;

rollback;
