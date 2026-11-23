-- Prova: a conta com boleto conhecido é baixada quando o banco mostra o pagamento — e SÓ no caso seguro
-- (migration 20270222100000_baixa_pelo_boleto).
--
-- ═══ COMO RODAR ═══
--
--   npx supabase@2.111.0 db query --linked -f <caminho completo>/supabase/tests/baixa_pelo_boleto.sql --output json
--
-- Seguro em produção: termina em ROLLBACK. Cria fornecedores, contas, saídas de banco e propostas de teste só dentro da
-- transação (banco 999, que não existe, e valores com centavos improváveis). A função varre a fila inteira, então as
-- provas olham o ESTADO de cada conta e de cada proposta de teste, nunca a contagem geral. A tabela final tem de
-- mostrar ok = true em todas as linhas.
--
-- ANTES de a migration estar aplicada: rodar o ensaio (a migration + este corpo na mesma transação).
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

-- Uma conta em aberto com boleto conhecido.
create function pg_temp.conta(p_forn uuid, p_nome text, p_valor numeric, p_venc date, p_linha text,
                              p_status text default 'pending', p_pago numeric default 0) returns uuid
language plpgsql as $$
declare v uuid;
begin
  insert into public.payables (supplier_id, supplier_name, description, issue_date, due_date, amount, status, paid_amount, balance_amount, origin, boleto_linha)
  values (p_forn, p_nome, 'conta de teste da baixa pelo boleto', p_venc - 10, p_venc, p_valor, p_status, p_pago, p_valor - p_pago, 'boleto', p_linha)
  returning id into v;
  return v;
end $$;

-- Uma saída do banco, com a proposta pendente na fila (p_fila = false: sem proposta).
create function pg_temp.saida(p_valor numeric, p_data date, p_banco text default '999', p_metodo text default 'BOLETO',
                              p_doc text default null, p_fila boolean default true, p_situacao text default null) returns uuid
language plpgsql as $$
declare v uuid; v_bc uuid;
begin
  select id into v_bc from public.bank_connections where provider <> 'caixa' order by created_at limit 1;
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, payment_method, bank_ref_id,
                                        bank_connection_id, counterparty_bank, counterparty_document, counterparty_name, tx_status)
  values (p_data, 'Pagamento Boleto BCO TESTE', p_valor, 'debit', p_metodo, 'teste-baixa-' || gen_random_uuid(), v_bc,
          p_banco, p_doc, 'FAVORECIDO DE TESTE', p_situacao)
  returning id into v;
  if p_fila then
    insert into public.finance_review_queue (kind, status, bank_transaction_id, title, confidence, suggested_amount, suggested_date)
    values ('create_payable', 'pending', v, 'Pagamento Boleto BCO TESTE', 50, p_valor, p_data);
  end if;
  return v;
end $$;

create function pg_temp.linha(p_banco text default '999') returns text
language sql as $$ select p_banco || lpad((floor(random() * 1e15))::bigint::text, 44, '7') $$;

-- A conta ficou paga por esta linha do banco?
create function pg_temp.baixada(p_conta uuid, p_tx uuid) returns boolean
language sql as $$
  select exists (select 1 from public.payables where id = p_conta and status = 'paid' and bank_transaction_id = p_tx and balance_amount = 0)
$$;

-- Nada mudou: conta em aberto sem linha do banco, proposta ainda pendente.
create function pg_temp.intacta(p_conta uuid, p_tx uuid) returns boolean
language sql as $$
  select exists (select 1 from public.payables where id = p_conta and status in ('pending', 'overdue', 'partially_paid') and bank_transaction_id is null)
     and not exists (select 1 from public.bank_transactions where id = p_tx and reconciled)
     and not exists (select 1 from public.finance_review_queue where bank_transaction_id = p_tx and automatica = 'boleto')
$$;

do $$
declare
  v_hoje date := public._hoje_brt();
  v_f1 uuid; v_f2 uuid;
  v_cnpj1 text := '77' || lpad((floor(random() * 1000000))::bigint::text, 6, '0') || '000155';
  v_cnpj1_filial text;
  v_cnpj2 text := '66' || lpad((floor(random() * 1000000))::bigint::text, 6, '0') || '000144';
  a uuid; a2 uuid; t uuid; t2 uuid;
  r jsonb;
  n int;
  ok boolean;
begin
  v_cnpj1_filial := left(v_cnpj1, 8) || '000236';
  insert into public.suppliers (name, cnpj_cpf) values ('FORNECEDOR UM DO TESTE DA BAIXA', v_cnpj1) returning id into v_f1;
  insert into public.suppliers (name, cnpj_cpf) values ('FORNECEDOR DOIS DO TESTE DA BAIXA', v_cnpj2) returning id into v_f2;

  -- B1: o caso seguro → baixa, com tudo no lugar
  a := pg_temp.conta(null, 'Boletos TESTE', 4321.07, v_hoje - 2, pg_temp.linha());
  t := pg_temp.saida(4321.07, v_hoje - 2);
  r := public.baixar_pelo_boleto('{}', v_hoje);
  ok := pg_temp.baixada(a, t)
    and exists (select 1 from public.payables where id = a and paid_amount = 4321.07)
    and exists (select 1 from public.bank_transactions where id = t and reconciled and reconciled_payment_id is not null)
    and exists (select 1 from public.payments where payable_id = a and status = 'confirmed' and amount = 4321.07
                   and payment_date = v_hoje - 2 and notes ilike 'concilia%')
    and exists (select 1 from public.finance_review_queue where bank_transaction_id = t and status = 'approved'
                   and automatica = 'boleto' and decided_at is not null and decision_note like 'Baixada sozinha pelo boleto: Boletos TESTE%')
    and exists (select 1 from public.reconciliation_log where bank_transaction_id = t and payable_id = a and acao = 'conciliou'
                   and autor is null and detalhe like 'Baixa automática pelo boleto%')
    and exists (select 1 from jsonb_array_elements(r -> 'itens') i where (i ->> 'transacao')::uuid = t and (i ->> 'conta')::uuid = a);
  insert into _resultado values ('B1 caso seguro: baixa, pagamento na data do banco, marcada na fila e no registro', ok, left(r::text, 300));

  -- B2: desfazer devolve tudo; a linha desfeita nunca mais é baixada sozinha
  perform public.desfazer_aprovacao('payable', a, 'teste da baixa', null);
  ok := exists (select 1 from public.payables where id = a and status = 'pending' and bank_transaction_id is null and balance_amount = 4321.07 and paid_amount = 0)
    and exists (select 1 from public.payments where payable_id = a and status = 'cancelled')
    and not exists (select 1 from public.payments where payable_id = a and status = 'confirmed')
    and exists (select 1 from public.bank_transactions where id = t and not reconciled);
  insert into _resultado values ('B2a desfazer: conta volta a ficar em aberto, pagamento estornado, linha solta', ok, '');
  -- a varredura seguinte propõe a linha de novo
  insert into public.finance_review_queue (kind, status, bank_transaction_id, title, confidence, suggested_amount, suggested_date)
  values ('create_payable', 'pending', t, 'Pagamento Boleto BCO TESTE', 50, 4321.07, v_hoje - 2);
  r := public.baixar_pelo_boleto('{}', v_hoje);
  ok := exists (select 1 from public.payables where id = a and status = 'pending' and bank_transaction_id is null)
    and exists (select 1 from public.finance_review_queue where bank_transaction_id = t and status = 'pending');
  insert into _resultado values ('B2b linha com baixa desfeita não é baixada de novo', ok, '');

  -- B3: banco do boleto diferente do banco da saída → fica
  a := pg_temp.conta(null, 'Boletos TESTE', 4322.09, v_hoje - 2, pg_temp.linha());
  t := pg_temp.saida(4322.09, v_hoje - 2, '998');
  r := public.baixar_pelo_boleto('{}', v_hoje);
  insert into _resultado values ('B3 banco do boleto diferente: não baixa', pg_temp.intacta(a, t), '');

  -- B4: um centavo de diferença → fica
  a := pg_temp.conta(null, 'Boletos TESTE', 4323.11, v_hoje - 2, pg_temp.linha());
  t := pg_temp.saida(4323.12, v_hoje - 2);
  r := public.baixar_pelo_boleto('{}', v_hoje);
  insert into _resultado values ('B4 um centavo de diferença: não baixa', pg_temp.intacta(a, t), '');

  -- B5: saída que não é por boleto → fica
  a := pg_temp.conta(null, 'Boletos TESTE', 4324.13, v_hoje - 2, pg_temp.linha());
  t := pg_temp.saida(4324.13, v_hoje - 2, '999', 'PIX');
  r := public.baixar_pelo_boleto('{}', v_hoje);
  insert into _resultado values ('B5 pagamento por Pix: não baixa', pg_temp.intacta(a, t), '');

  -- B6: duas parcelas iguais do mesmo fornecedor → baixa a do vencimento do pagamento; a outra fica
  a  := pg_temp.conta(v_f1, 'FORNECEDOR UM DO TESTE DA BAIXA', 4325.17, v_hoje - 16, pg_temp.linha());
  a2 := pg_temp.conta(v_f1, 'FORNECEDOR UM DO TESTE DA BAIXA', 4325.17, v_hoje - 2, pg_temp.linha());
  t  := pg_temp.saida(4325.17, v_hoje - 16);
  r := public.baixar_pelo_boleto('{}', v_hoje);
  ok := pg_temp.baixada(a, t)
    and exists (select 1 from public.payables where id = a2 and status = 'pending' and bank_transaction_id is null);
  insert into _resultado values ('B6 parcelas iguais: baixa a do vencimento mais próximo, a outra continua em aberto', ok, '');
  -- o segundo pagamento baixa a segunda
  t2 := pg_temp.saida(4325.17, v_hoje - 2);
  r := public.baixar_pelo_boleto('{}', v_hoje);
  insert into _resultado values ('B6b o pagamento seguinte baixa a parcela seguinte', pg_temp.baixada(a2, t2), '');

  -- B7: empate (duas contas à mesma distância do pagamento) → pergunta
  a  := pg_temp.conta(v_f1, 'FORNECEDOR UM DO TESTE DA BAIXA', 4326.19, v_hoje - 8, pg_temp.linha());
  a2 := pg_temp.conta(v_f1, 'FORNECEDOR UM DO TESTE DA BAIXA', 4326.19, v_hoje - 2, pg_temp.linha());
  t  := pg_temp.saida(4326.19, v_hoje - 5);
  r := public.baixar_pelo_boleto('{}', v_hoje);
  ok := pg_temp.intacta(a, t) and pg_temp.intacta(a2, t)
    and exists (select 1 from public.finance_review_queue where bank_transaction_id = t and status = 'pending');
  insert into _resultado values ('B7 empate entre duas contas: não baixa, a pergunta continua na fila', ok, r ->> 'ambiguas');

  -- B8: mesmo valor e banco, fornecedores diferentes → pergunta
  a  := pg_temp.conta(v_f1, 'FORNECEDOR UM DO TESTE DA BAIXA', 4327.23, v_hoje - 3, pg_temp.linha());
  a2 := pg_temp.conta(v_f2, 'FORNECEDOR DOIS DO TESTE DA BAIXA', 4327.23, v_hoje - 9, pg_temp.linha());
  t  := pg_temp.saida(4327.23, v_hoje - 3);
  r := public.baixar_pelo_boleto('{}', v_hoje);
  insert into _resultado values ('B8 duas contas de fornecedores diferentes: não baixa', pg_temp.intacta(a, t) and pg_temp.intacta(a2, t), '');

  -- B9: linha reservada na rodada (p_exceto) → fica; sem a reserva, baixa
  a := pg_temp.conta(null, 'Boletos TESTE', 4328.29, v_hoje - 2, pg_temp.linha());
  t := pg_temp.saida(4328.29, v_hoje - 2);
  r := public.baixar_pelo_boleto(array[t], v_hoje);
  ok := pg_temp.intacta(a, t);
  r := public.baixar_pelo_boleto('{}', v_hoje);
  insert into _resultado values ('B9 linha reservada fica; sem a reserva, baixa', ok and pg_temp.baixada(a, t), '');

  -- B10: sem proposta pendente na fila → fica
  a := pg_temp.conta(null, 'Boletos TESTE', 4329.31, v_hoje - 2, pg_temp.linha());
  t := pg_temp.saida(4329.31, v_hoje - 2, '999', 'BOLETO', null, false);
  insert into public.finance_review_queue (kind, status, bank_transaction_id, title, confidence, suggested_amount, suggested_date)
  values ('create_payable', 'rejected', t, 'Pagamento Boleto BCO TESTE', 50, 4329.31, v_hoje - 2);
  r := public.baixar_pelo_boleto('{}', v_hoje);
  insert into _resultado values ('B10 sem pergunta pendente na fila (recusada): não baixa', pg_temp.intacta(a, t), '');

  -- B11: documento do favorecido diferente do fornecedor da conta → fica; filial do mesmo CNPJ → baixa
  a := pg_temp.conta(v_f1, 'FORNECEDOR UM DO TESTE DA BAIXA', 4330.37, v_hoje - 2, pg_temp.linha());
  t := pg_temp.saida(4330.37, v_hoje - 2, '999', 'BOLETO', v_cnpj2);
  r := public.baixar_pelo_boleto('{}', v_hoje);
  insert into _resultado values ('B11a favorecido com outro CNPJ: não baixa', pg_temp.intacta(a, t), '');
  a := pg_temp.conta(v_f1, 'FORNECEDOR UM DO TESTE DA BAIXA', 4331.41, v_hoje - 2, pg_temp.linha());
  t := pg_temp.saida(4331.41, v_hoje - 2, '999', 'BOLETO', v_cnpj1_filial);
  r := public.baixar_pelo_boleto('{}', v_hoje);
  insert into _resultado values ('B11b favorecido é filial do mesmo CNPJ: baixa', pg_temp.baixada(a, t), '');

  -- B12: conta já paga em parte → fica
  a := pg_temp.conta(null, 'Boletos TESTE', 4332.43, v_hoje - 2, pg_temp.linha(), 'partially_paid', 10);
  t := pg_temp.saida(4332.43, v_hoje - 2);
  r := public.baixar_pelo_boleto('{}', v_hoje);
  insert into _resultado values ('B12 conta paga em parte: não baixa', pg_temp.intacta(a, t), '');

  -- B13: boleto de arrecadação (48 dígitos, sem banco) → fica
  a := pg_temp.conta(null, 'Boletos TESTE', 4333.47, v_hoje - 2, '999' || lpad((floor(random() * 1e15))::bigint::text, 45, '7'));
  t := pg_temp.saida(4333.47, v_hoje - 2);
  r := public.baixar_pelo_boleto('{}', v_hoje);
  insert into _resultado values ('B13 boleto de arrecadação (48 dígitos): não baixa', pg_temp.intacta(a, t), '');

  -- B14: dois pagamentos iguais esperando e uma conta só → pergunta
  a  := pg_temp.conta(null, 'Boletos TESTE', 4334.53, v_hoje - 2, pg_temp.linha());
  t  := pg_temp.saida(4334.53, v_hoje - 2);
  t2 := pg_temp.saida(4334.53, v_hoje - 1);
  r := public.baixar_pelo_boleto('{}', v_hoje);
  insert into _resultado values ('B14 mais pagamentos iguais do que contas: não baixa', pg_temp.intacta(a, t) and pg_temp.intacta(a, t2), '');

  -- B15: pago 40 dias depois do vencimento → fica
  a := pg_temp.conta(null, 'Boletos TESTE', 4335.59, v_hoje - 41, pg_temp.linha());
  t := pg_temp.saida(4335.59, v_hoje - 1);
  r := public.baixar_pelo_boleto('{}', v_hoje);
  insert into _resultado values ('B15 pago fora da janela do vencimento: não baixa', pg_temp.intacta(a, t), '');

  -- B16: saída que o banco ainda marca como pendente, e saída tirada da fila → ficam
  a := pg_temp.conta(null, 'Boletos TESTE', 4336.61, v_hoje - 2, pg_temp.linha());
  t := pg_temp.saida(4336.61, v_hoje - 2, '999', 'BOLETO', null, true, 'PENDING');
  a2 := pg_temp.conta(null, 'Boletos TESTE', 4337.67, v_hoje - 2, pg_temp.linha());
  t2 := pg_temp.saida(4337.67, v_hoje - 2);
  update public.bank_transactions set dismissed_kind = 'ignored', dismissed_at = now() where id = t2;
  r := public.baixar_pelo_boleto('{}', v_hoje);
  insert into _resultado values ('B16 saída pendente no banco ou fora da fila: não baixa', pg_temp.intacta(a, t) and pg_temp.intacta(a2, t2), '');

  -- B17: conta cancelada e conta já casada com outra linha → ficam
  a := pg_temp.conta(null, 'Boletos TESTE', 4338.71, v_hoje - 2, pg_temp.linha(), 'cancelled');
  t := pg_temp.saida(4338.71, v_hoje - 2);
  r := public.baixar_pelo_boleto('{}', v_hoje);
  ok := exists (select 1 from public.payables where id = a and status = 'cancelled' and bank_transaction_id is null)
    and exists (select 1 from public.finance_review_queue where bank_transaction_id = t and status = 'pending');
  insert into _resultado values ('B17 conta cancelada: não baixa', ok, '');

  -- B18: chave desligada → pula e não toca em nada
  a := pg_temp.conta(null, 'Boletos TESTE', 4339.73, v_hoje - 2, pg_temp.linha());
  t := pg_temp.saida(4339.73, v_hoje - 2);
  insert into public.app_settings (key, value) values ('boleto_baixa_modo', 'desligado')
    on conflict (key) do update set value = excluded.value;
  r := public.baixar_pelo_boleto('{}', v_hoje);
  insert into _resultado values ('B18 chave boleto_baixa_modo = desligado pula', coalesce((r ->> 'pulado')::boolean, false) and pg_temp.intacta(a, t), r::text);
  delete from public.app_settings where key = 'boleto_baixa_modo';

  -- B19: a marca "boleto" cabe na fila; marca inventada não
  begin
    update public.finance_review_queue set automatica = 'inventada' where bank_transaction_id = t;
    insert into _resultado values ('B19 marca inventada é recusada', false, 'aceitou');
  exception when check_violation then
    insert into _resultado values ('B19 marca inventada é recusada', true, '');
  end;
end $$;

-- B20–B22: só o serviço executa (as duas funções)
insert into _resultado
select 'B20 anon NÃO executa',
       not has_function_privilege('anon', 'public.baixar_pelo_boleto(uuid[], date)', 'execute')
   and not has_function_privilege('anon', 'public._contas_que_o_boleto_paga(uuid)', 'execute'), ''
union all
select 'B21 authenticated NÃO executa',
       not has_function_privilege('authenticated', 'public.baixar_pelo_boleto(uuid[], date)', 'execute')
   and not has_function_privilege('authenticated', 'public._contas_que_o_boleto_paga(uuid)', 'execute'), ''
union all
select 'B22 service_role executa',
       has_function_privilege('service_role', 'public.baixar_pelo_boleto(uuid[], date)', 'execute')
   and has_function_privilege('service_role', 'public._contas_que_o_boleto_paga(uuid)', 'execute'), '';

select teste, ok, detalhe from _resultado order by (substring(teste from 'B(\d+)'))::int, teste;

rollback;
