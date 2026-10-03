-- "Este Pix paga…": aplicar uma entrada em várias contas e desfazer (02/10/2026).
-- Run: npx supabase db query --linked -f supabase/tests/este_pix_paga.sql
-- Termina em ROLLBACK. Usa dados criados aqui (não depende de nenhuma conta real).
begin;

do $$
declare
  v_cliente uuid := (select id from public.clients order by created_at limit 1);
  v_conta uuid := (select id from public.bank_connections where provider <> 'caixa' order by created_at limit 1);
  v_admin uuid := (select id from public.app_users where role = 'admin' and active order by created_at limit 1);
  v_tx uuid; v_tx2 uuid; v_a uuid; v_b uuid; v_c uuid;
  v_pa uuid; v_pb uuid;
  r jsonb;
  e record;
begin
  -- ── T1. Um Pix paga dois sinais (o caso do Lenine) ──────────────────────────────────
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, bank_connection_id, reconciled)
  values (current_date, 'TESTE Pix recebido de LENINE', 4800, 'credit', v_conta, false) returning id into v_tx;
  insert into public.receivables (client_id, description, issue_date, due_date, amount, paid_amount, balance_amount, status)
  values (v_cliente, 'TESTE Sinal A', current_date, current_date, 2280, 0, 2280, 'pending') returning id into v_a;
  insert into public.receivables (client_id, description, issue_date, due_date, amount, paid_amount, balance_amount, status)
  values (v_cliente, 'TESTE Sinal B', current_date, current_date, 2520, 0, 2520, 'pending') returning id into v_b;

  r := public.aplicar_entrada_em_contas(v_tx, jsonb_build_array(
         jsonb_build_object('receivable_id', v_a, 'valor', 2280),
         jsonb_build_object('receivable_id', v_b, 'valor', 2520)), null, v_admin);
  if (r ->> 'contas')::int <> 2 then raise exception 'T1: %', r; end if;
  if exists (select 1 from public.receivables where id in (v_a, v_b) and (status <> 'paid' or balance_amount <> 0)) then
    raise exception 'T1: os dois sinais deviam estar pagos';
  end if;
  if (select count(*) from public.payments where bank_transaction_id = v_tx and status = 'confirmed' and payment_method = 'pix') <> 2 then
    raise exception 'T1: deviam ser 2 pagamentos Pix ligados à entrada';
  end if;
  select * into e from public.recebimentos_do_extrato where bank_transaction_id = v_tx;
  if e.aplicado <> 4800 or e.sobra <> 0 or e.contas <> 2 then raise exception 'T1: entrada %', row_to_json(e); end if;
  if not (select reconciled from public.bank_transactions where id = v_tx) then raise exception 'T1: a entrada devia ficar conciliada'; end if;
  if (select count(*) from public.receivables where bank_transaction_id = v_tx) <> 1 then
    raise exception 'T1: o vínculo antigo fica com uma conta só (índice único)';
  end if;
  if exists (select 1 from public.conferencia_dos_pagamentos where bank_transaction_id = v_tx or receivable_id in (v_a, v_b)) then
    raise exception 'T1: a conferência acusa a aplicação';
  end if;
  if not exists (select 1 from public.reconciliation_log where acao = 'aplicou_pix' and bank_transaction_id = v_tx and autor = v_admin) then
    raise exception 'T1: não ficou na trilha';
  end if;

  -- Aplicar de novo: já está toda aplicada.
  begin
    perform public.aplicar_entrada_em_contas(v_tx, jsonb_build_array(jsonb_build_object('receivable_id', v_a, 'valor', 1)), null, v_admin);
    raise exception 'aplicou duas vezes';
  exception when others then
    if sqlerrm not like '%já está toda aplicada%' then raise exception 'T1b: %', sqlerrm; end if;
  end;

  -- ── T2. Desfazer uma das aplicações; depois a outra ─────────────────────────────────
  select id into v_pb from public.payments where receivable_id = v_b and bank_transaction_id = v_tx and status = 'confirmed';
  select id into v_pa from public.payments where receivable_id = v_a and bank_transaction_id = v_tx and status = 'confirmed';
  r := public.desfazer_aplicacao(v_pb, 'teste', v_admin);
  if (r ->> 'entrada_livre')::boolean then raise exception 'T2: a entrada ainda paga o sinal A'; end if;
  if not exists (select 1 from public.receivables where id = v_b and status = 'pending' and paid_amount = 0 and balance_amount = 2520) then
    raise exception 'T2: o sinal B devia voltar a pendente';
  end if;
  if (select status from public.payments where id = v_pb) <> 'cancelled' then raise exception 'T2: pagamento não estornado'; end if;
  r := public.desfazer_aplicacao(v_pa, null, v_admin);
  if not (r ->> 'entrada_livre')::boolean then raise exception 'T2: a entrada devia ficar livre'; end if;
  if exists (select 1 from public.bank_transactions where id = v_tx and (reconciled or reconciled_payment_id is not null)) then
    raise exception 'T2: a entrada devia voltar para a fila';
  end if;
  if exists (select 1 from public.receivables where bank_transaction_id = v_tx) then
    raise exception 'T2: nenhuma conta devia continuar ligada à entrada';
  end if;
  begin
    perform public.desfazer_aplicacao(v_pa, null, v_admin);
    raise exception 'desfez duas vezes';
  exception when others then
    if sqlerrm not like '%já foi estornado%' then raise exception 'T2b: %', sqlerrm; end if;
  end;

  -- ── T3. Uma OS paga em dois Pix ─────────────────────────────────────────────────────
  insert into public.receivables (client_id, description, issue_date, due_date, amount, paid_amount, balance_amount, status)
  values (v_cliente, 'TESTE Saldo da OS', current_date, current_date, 1000, 0, 1000, 'pending') returning id into v_c;
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, bank_connection_id)
  values (current_date, 'TESTE TED parte 1', 600, 'credit', v_conta) returning id into v_tx;
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, bank_connection_id)
  values (current_date, 'TESTE TED parte 2', 400, 'credit', v_conta) returning id into v_tx2;
  perform public.aplicar_entrada_em_contas(v_tx, jsonb_build_array(jsonb_build_object('receivable_id', v_c, 'valor', 600)), null, v_admin);
  if (select status from public.receivables where id = v_c) <> 'partially_paid' then raise exception 'T3: devia ficar parcial'; end if;
  perform public.aplicar_entrada_em_contas(v_tx2, jsonb_build_array(jsonb_build_object('receivable_id', v_c, 'valor', 400)), null, v_admin);
  if not exists (select 1 from public.receivables where id = v_c and status = 'paid' and paid_amount = 1000) then
    raise exception 'T3: dois Pix deviam quitar a OS';
  end if;
  if (select payment_method from public.payments where bank_transaction_id = v_tx2) <> 'bank_transfer' then
    raise exception 'T3: TED devia virar transferência';
  end if;
  if exists (select 1 from public.conferencia_dos_pagamentos where receivable_id = v_c or bank_transaction_id in (v_tx, v_tx2)) then
    raise exception 'T3: a conferência acusa a OS paga em dois Pix';
  end if;

  -- ── T4. Sobra, excesso e conta já paga são recusados com explicação ─────────────────
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, bank_connection_id)
  values (current_date, 'TESTE Pix com sobra', 500, 'credit', v_conta) returning id into v_tx;
  insert into public.receivables (client_id, description, issue_date, due_date, amount, paid_amount, balance_amount, status)
  values (v_cliente, 'TESTE Conta de 400', current_date, current_date, 400, 0, 400, 'pending') returning id into v_a;
  begin
    perform public.aplicar_entrada_em_contas(v_tx, jsonb_build_array(jsonb_build_object('receivable_id', v_a, 'valor', 400)), null, v_admin);
    raise exception 'aceitou sobra';
  exception when others then
    if sqlerrm not like '%Sobram R$%' then raise exception 'T4a: %', sqlerrm; end if;
  end;
  begin
    perform public.aplicar_entrada_em_contas(v_tx, jsonb_build_array(jsonb_build_object('receivable_id', v_a, 'valor', 500)), null, v_admin);
    raise exception 'aceitou R$ 100 a mais';
  exception when others then
    if sqlerrm not like '%Acima de R$ 10, avalie%' then raise exception 'T4b: %', sqlerrm; end if;
  end;
  begin
    perform public.aplicar_entrada_em_contas(v_tx, jsonb_build_array(jsonb_build_object('receivable_id', v_c, 'valor', 500)), null, v_admin);
    raise exception 'aceitou conta paga';
  exception when others then
    if sqlerrm not like '%já está paga%' then raise exception 'T4c: %', sqlerrm; end if;
  end;

  -- ── T5. Até R$ 10 a mais é receita; até R$ 10 a menos, com quitar, é desconto ─────────
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, bank_connection_id)
  values (current_date, 'TESTE Pix a mais', 1866, 'credit', v_conta) returning id into v_tx;
  insert into public.receivables (client_id, description, issue_date, due_date, amount, paid_amount, balance_amount, status)
  values (v_cliente, 'TESTE Sinal 1865,47', current_date, current_date, 1865.47, 0, 1865.47, 'pending') returning id into v_a;
  perform public.aplicar_entrada_em_contas(v_tx, jsonb_build_array(jsonb_build_object('receivable_id', v_a, 'valor', 1866)), null, v_admin);
  if not exists (select 1 from public.receivables where id = v_a and amount = 1866 and paid_amount = 1866 and status = 'paid'
                  and notes like '%pagou R$ 0,53 a mais (receita)%') then
    raise exception 'T5: os R$ 0,53 a mais deviam virar receita da conta';
  end if;
  -- Desfazer devolve o valor original da conta.
  select id into v_pa from public.payments where receivable_id = v_a and bank_transaction_id = v_tx;
  perform public.desfazer_aplicacao(v_pa, null, v_admin);
  if not exists (select 1 from public.receivables where id = v_a and amount = 1865.47 and paid_amount = 0 and status = 'pending') then
    raise exception 'T5: desfazer devia devolver o valor de R$ 1.865,47';
  end if;

  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, bank_connection_id)
  values (current_date, 'TESTE Pix a menos', 995, 'credit', v_conta) returning id into v_tx;
  insert into public.receivables (client_id, description, issue_date, due_date, amount, paid_amount, balance_amount, status)
  values (v_cliente, 'TESTE Conta de 1000', current_date, current_date, 1000, 0, 1000, 'pending') returning id into v_b;
  perform public.aplicar_entrada_em_contas(v_tx, jsonb_build_array(jsonb_build_object('receivable_id', v_b, 'valor', 995, 'quitar', true)), null, v_admin);
  if not exists (select 1 from public.receivables where id = v_b and amount = 995 and paid_amount = 995 and status = 'paid'
                  and notes like '%R$ 5,00 deixam de ser cobrados (desconto)%') then
    raise exception 'T5: os R$ 5 deviam virar desconto';
  end if;

  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, bank_connection_id)
  values (current_date, 'TESTE Pix bem a menos', 980, 'credit', v_conta) returning id into v_tx;
  insert into public.receivables (client_id, description, issue_date, due_date, amount, paid_amount, balance_amount, status)
  values (v_cliente, 'TESTE Outra de 1000', current_date, current_date, 1000, 0, 1000, 'pending') returning id into v_c;
  begin
    perform public.aplicar_entrada_em_contas(v_tx, jsonb_build_array(jsonb_build_object('receivable_id', v_c, 'valor', 980, 'quitar', true)), null, v_admin);
    raise exception 'quitou R$ 20 por desconto';
  exception when others then
    if sqlerrm not like '%acima de R$ 10 não se quita%' then raise exception 'T5b: %', sqlerrm; end if;
  end;
  -- Sem quitar, fica parcial com R$ 20 em aberto.
  perform public.aplicar_entrada_em_contas(v_tx, jsonb_build_array(jsonb_build_object('receivable_id', v_c, 'valor', 980)), null, v_admin);
  if not exists (select 1 from public.receivables where id = v_c and status = 'partially_paid' and balance_amount = 20) then
    raise exception 'T5c: devia ficar parcial com R$ 20';
  end if;

  -- ── T6. Entrada fora da fila e saída do banco são recusadas ──────────────────────────
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, bank_connection_id, dismissed_kind)
  values (current_date, 'TESTE cópia', 100, 'credit', v_conta, 'duplicata') returning id into v_tx;
  begin
    perform public.aplicar_entrada_em_contas(v_tx, jsonb_build_array(jsonb_build_object('receivable_id', v_c, 'valor', 20)), null, v_admin);
    raise exception 'aplicou cópia';
  exception when others then
    if sqlerrm not like '%fora da fila%' then raise exception 'T6a: %', sqlerrm; end if;
  end;
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, bank_connection_id)
  values (current_date, 'TESTE saída', 20, 'debit', v_conta) returning id into v_tx;
  begin
    perform public.aplicar_entrada_em_contas(v_tx, jsonb_build_array(jsonb_build_object('receivable_id', v_c, 'valor', 20)), null, v_admin);
    raise exception 'aplicou saída';
  exception when others then
    if sqlerrm not like '%Só uma entrada%' then raise exception 'T6b: %', sqlerrm; end if;
  end;

  -- ── T8. "Este Pix é o sinal que já lancei à mão": liga sem criar outro pagamento ──────
  insert into public.receivables (client_id, description, issue_date, due_date, amount, paid_amount, balance_amount, status)
  values (v_cliente, 'TESTE Sinal recebido à mão', current_date, current_date, 700, 700, 0, 'paid') returning id into v_a;
  insert into public.payments (receivable_id, amount, payment_date, payment_method, notes, status)
  values (v_a, 700, current_date, 'pix', 'Sinal registrado pelo botão Receber sinal', 'confirmed') returning id into v_pa;
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, bank_connection_id)
  values (current_date, 'TESTE Pix do sinal', 700, 'credit', v_conta) returning id into v_tx;
  perform public.aplicar_entrada_em_contas(v_tx, jsonb_build_array(jsonb_build_object('pagamento_id', v_pa)), null, v_admin);
  if (select count(*) from public.payments where receivable_id = v_a) <> 1 then raise exception 'T8: criou outro pagamento'; end if;
  if (select bank_transaction_id from public.payments where id = v_pa) is distinct from v_tx then raise exception 'T8: o pagamento não ficou ligado à entrada'; end if;
  if not exists (select 1 from public.receivables where id = v_a and status = 'paid' and paid_amount = 700 and bank_transaction_id = v_tx) then
    raise exception 'T8: a conta devia continuar paga e segurar a entrada';
  end if;
  perform public.desfazer_aplicacao(v_pa, null, v_admin);
  if not exists (select 1 from public.payments where id = v_pa and status = 'confirmed' and bank_transaction_id is null) then
    raise exception 'T8: desfazer devia só desligar o pagamento lançado à mão';
  end if;
  if (select status from public.receivables where id = v_a) <> 'paid' then raise exception 'T8: a conta devia continuar paga'; end if;
  if exists (select 1 from public.bank_transactions where id = v_tx and reconciled) then raise exception 'T8: a entrada devia voltar para a fila'; end if;

  -- ── T9. Proteções com um Pix em duas contas ──────────────────────────────────────────
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, bank_connection_id)
  values (current_date, 'TESTE Pix de dois sinais', 3000, 'credit', v_conta) returning id into v_tx;
  insert into public.receivables (client_id, description, issue_date, due_date, amount, paid_amount, balance_amount, status)
  values (v_cliente, 'TESTE Sinal C', current_date, current_date, 1000, 0, 1000, 'pending') returning id into v_a;
  insert into public.receivables (client_id, description, issue_date, due_date, amount, paid_amount, balance_amount, status)
  values (v_cliente, 'TESTE Sinal D', current_date, current_date, 2000, 0, 2000, 'pending') returning id into v_b;
  perform public.aplicar_entrada_em_contas(v_tx, jsonb_build_array(
         jsonb_build_object('receivable_id', v_a, 'valor', 1000), jsonb_build_object('receivable_id', v_b, 'valor', 2000)), null, v_admin);
  if (select bank_transaction_id from public.receivables where id = v_a) is distinct from v_tx then raise exception 'T9: C devia segurar a entrada'; end if;

  -- A conciliação vê as duas contas conciliadas, sem diferença.
  if exists (select 1 from public.conciliacao_lancamentos where id in (v_a, v_b)
              and (situacao <> 'conciliado' or diferenca <> 0)) then
    raise exception 'T9: a conciliação devia ver as duas contas conciliadas e sem diferença';
  end if;

  -- Ajustar C ao valor inteiro do Pix contaria o dinheiro duas vezes.
  begin
    perform public.ajustar_ao_valor_do_banco('receivable', v_a, null, v_admin);
    raise exception 'ajustou conta de Pix dividido';
  exception when others then
    if sqlerrm not like '%também paga 1 outra(s) conta(s)%' then raise exception 'T9a: %', sqlerrm; end if;
  end;

  -- Casar a entrada com mais uma conta pelo caminho antigo: recusado.
  insert into public.receivables (client_id, description, issue_date, due_date, amount, paid_amount, balance_amount, status)
  values (v_cliente, 'TESTE Outra conta', current_date, current_date, 3000, 0, 3000, 'pending') returning id into v_c;
  begin
    perform public.conciliar_lancamento('receivable', v_c, v_tx, v_admin);
    raise exception 'casou entrada já aplicada';
  exception when others then
    if sqlerrm not like '%já está vinculada%' and sqlerrm not like '%já paga outra(s) conta(s)%' then raise exception 'T9b: %', sqlerrm; end if;
  end;

  -- Desfazer o vínculo de C: a entrada continua pagando D, que passa a segurá-la.
  r := public.desfazer_aprovacao('receivable', v_a, 'teste', v_admin);
  if r ->> 'message' not like '%continua pagando%' then raise exception 'T9c: %', r; end if;
  if not exists (select 1 from public.receivables where id = v_a and status = 'pending' and paid_amount = 0 and bank_transaction_id is null) then
    raise exception 'T9c: C devia voltar a pendente e sem vínculo';
  end if;
  if not exists (select 1 from public.bank_transactions where id = v_tx and reconciled) then
    raise exception 'T9c: a entrada devia continuar conciliada (ainda paga D)';
  end if;
  if (select bank_transaction_id from public.receivables where id = v_b) is distinct from v_tx then
    raise exception 'T9c: D devia passar a segurar a entrada';
  end if;
  if (select p.receivable_id from public.bank_transactions t join public.payments p on p.id = t.reconciled_payment_id where t.id = v_tx) <> v_b then
    raise exception 'T9c: a entrada devia apontar para o pagamento de D';
  end if;

  -- Cancelar D: nada mais da entrada está aplicado; ela volta para a fila.
  r := public.cancelar_lancamento('receivable', v_b, 'teste de cancelamento', v_admin);
  if r ->> 'linha_do_extrato' <> 'fila' then raise exception 'T9d: %', r; end if;
  if exists (select 1 from public.bank_transactions where id = v_tx and (reconciled or reconciled_payment_id is not null)) then
    raise exception 'T9d: a entrada devia voltar para a fila';
  end if;

  -- Cancelar uma conta que NÃO segura a entrada: a entrada segue com a outra conta.
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, bank_connection_id)
  values (current_date, 'TESTE Pix de mais dois', 900, 'credit', v_conta) returning id into v_tx;
  insert into public.receivables (client_id, description, issue_date, due_date, amount, paid_amount, balance_amount, status)
  values (v_cliente, 'TESTE Sinal E', current_date, current_date, 400, 0, 400, 'pending') returning id into v_a;
  insert into public.receivables (client_id, description, issue_date, due_date, amount, paid_amount, balance_amount, status)
  values (v_cliente, 'TESTE Sinal F', current_date, current_date, 500, 0, 500, 'pending') returning id into v_b;
  perform public.aplicar_entrada_em_contas(v_tx, jsonb_build_array(
         jsonb_build_object('receivable_id', v_a, 'valor', 400), jsonb_build_object('receivable_id', v_b, 'valor', 500)), null, v_admin);
  r := public.cancelar_lancamento('receivable', v_b, 'teste: F era de outro cliente', v_admin);
  if r ->> 'message' not like '%continuam pagando outras contas%' then raise exception 'T9e: %', r; end if;
  if not exists (select 1 from public.bank_transactions where id = v_tx and reconciled) then
    raise exception 'T9e: a entrada devia continuar conciliada (ainda paga E)';
  end if;
  -- E a conciliação passa a acusar a sobra da entrada (R$ 500) na conta E.
  if (select diferenca from public.conciliacao_lancamentos where id = v_a) <> -500 then
    raise exception 'T9e: a conciliação devia acusar a sobra de R$ 500';
  end if;

  -- ── T7. Quem pode chamar ─────────────────────────────────────────────────────────────
  if has_function_privilege('anon', 'public.aplicar_entrada_em_contas(uuid, jsonb, text, uuid)', 'execute')
     or has_function_privilege('anon', 'public.desfazer_aplicacao(uuid, text, uuid)', 'execute') then
    raise exception 'T7: anon não aplica nem desfaz';
  end if;
  if not has_function_privilege('authenticated', 'public.aplicar_entrada_em_contas(uuid, jsonb, text, uuid)', 'execute') then
    raise exception 'T7: o financeiro logado precisa poder aplicar';
  end if;
  if has_function_privilege('authenticated', 'public._reacomodar_entrada(uuid)', 'execute')
     or has_function_privilege('anon', 'public._reacomodar_entrada(uuid)', 'execute') then
    raise exception 'T7: _reacomodar_entrada é só das funções do banco';
  end if;
end $$;

select 'ok: um Pix paga duas contas, desfazer devolve tudo e solta a entrada, OS paga em dois Pix, sobra/excesso/conta paga recusados, R$ 10 a mais vira receita e a menos vira desconto, pagamento já lançado só liga e desliga, desfazer/cancelar/ajustar/conciliar não soltam nem dobram um Pix de duas contas, conciliação sem diferença, permissões certas' as resultado;

rollback;
