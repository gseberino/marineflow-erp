-- O pagamento sabe de qual Pix veio — forma A, fase F1 (02/10/2026).
-- Run: npx supabase db query --linked -f supabase/tests/pagamento_sabe_de_qual_pix.sql
-- Termina em ROLLBACK. Usa dados criados aqui (não depende de nenhuma conta real), para o teste
-- não envelhecer quando os lançamentos de produção mudarem.
begin;

do $$
declare
  v_cliente uuid := (select id from public.clients order by created_at limit 1);
  v_conta uuid := (select id from public.bank_connections where provider <> 'caixa' order by created_at limit 1);
  v_admin uuid := (select id from public.app_users where role = 'admin' and active order by created_at limit 1);
  v_tx uuid; v_rec uuid; v_rec2 uuid; v_rec3 uuid; v_pag uuid; v_pag2 uuid;
  v_ret uuid;
  e record;
begin
  -- ── T1. Receita que nasceu do extrato ganha o seu pagamento, uma vez só ─────────────
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, bank_connection_id, reconciled)
  values (current_date - 3, 'TESTE Pix recebido de FULANO', 1234.56, 'credit', v_conta, true) returning id into v_tx;
  insert into public.receivables (client_id, description, issue_date, due_date, amount, paid_amount, balance_amount, status, bank_transaction_id)
  values (v_cliente, 'TESTE receita do extrato', current_date - 3, current_date - 3, 1234.56, 1234.56, 0, 'paid', v_tx) returning id into v_rec;

  v_ret := public.registrar_pagamento_da_receita_do_extrato(v_rec);
  if v_ret is null then raise exception 'T1: não registrou o pagamento'; end if;
  if not exists (select 1 from public.payments where id = v_ret and receivable_id = v_rec and amount = 1234.56
                  and net_amount = 1234.56 and status = 'confirmed' and payment_method = 'pix'
                  and payment_date = current_date - 3 and bank_transaction_id = v_tx
                  and notes like 'Conciliado com o extrato de %') then
    raise exception 'T1: pagamento com dados errados';
  end if;
  if (select reconciled_payment_id from public.bank_transactions where id = v_tx) is distinct from v_ret then
    raise exception 'T1: a linha do banco não aponta para o pagamento';
  end if;
  if public.registrar_pagamento_da_receita_do_extrato(v_rec) is not null then
    raise exception 'T1: registrou duas vezes';
  end if;
  if exists (select 1 from public.conferencia_dos_pagamentos where receivable_id = v_rec or bank_transaction_id = v_tx) then
    raise exception 'T1: a conferência acusa a receita do extrato';
  end if;

  -- ── T2. O gatilho acompanha o caminho antigo (liga e desliga) ───────────────────────
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, bank_connection_id, reconciled)
  values (current_date, 'TESTE TED recebida', 800, 'credit', v_conta, false) returning id into v_tx;
  insert into public.receivables (client_id, description, issue_date, due_date, amount, paid_amount, balance_amount, status)
  values (v_cliente, 'TESTE pagamento lançado à mão', current_date, current_date, 800, 800, 0, 'paid') returning id into v_rec;
  insert into public.payments (receivable_id, amount, payment_date, payment_method, status)
  values (v_rec, 800, current_date, 'bank_transfer', 'confirmed') returning id into v_pag;

  update public.bank_transactions set reconciled = true, reconciled_payment_id = v_pag where id = v_tx;
  if (select bank_transaction_id from public.payments where id = v_pag) is distinct from v_tx then
    raise exception 'T2: ao ligar a linha, o pagamento não ficou sabendo';
  end if;
  update public.bank_transactions set reconciled = false, reconciled_payment_id = null where id = v_tx;
  if (select bank_transaction_id from public.payments where id = v_pag) is not null then
    raise exception 'T2: ao desligar a linha, o pagamento continuou apontando para ela';
  end if;

  -- ── T3. Um Pix paga duas contas; aplicar mais do que entrou é acusado ────────────────
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, bank_connection_id, reconciled)
  values (current_date, 'TESTE Pix dos dois sinais', 4800, 'credit', v_conta, true) returning id into v_tx;
  insert into public.receivables (client_id, description, issue_date, due_date, amount, paid_amount, balance_amount, status)
  values (v_cliente, 'TESTE sinal A', current_date, current_date, 2280, 2280, 0, 'paid') returning id into v_rec;
  insert into public.receivables (client_id, description, issue_date, due_date, amount, paid_amount, balance_amount, status)
  values (v_cliente, 'TESTE sinal B', current_date, current_date, 2520, 2520, 0, 'paid') returning id into v_rec2;
  insert into public.payments (receivable_id, amount, payment_date, payment_method, status, bank_transaction_id)
  values (v_rec, 2280, current_date, 'pix', 'confirmed', v_tx), (v_rec2, 2520, current_date, 'pix', 'confirmed', v_tx);

  select * into e from public.recebimentos_do_extrato where bank_transaction_id = v_tx;
  if e.aplicado <> 4800 or e.sobra <> 0 or e.contas <> 2 then
    raise exception 'T3: o Pix devia estar todo aplicado em 2 contas: %', row_to_json(e);
  end if;
  if exists (select 1 from public.conferencia_dos_pagamentos where bank_transaction_id = v_tx or receivable_id in (v_rec, v_rec2)) then
    raise exception 'T3: a conferência acusa um Pix bem aplicado';
  end if;

  insert into public.receivables (client_id, description, issue_date, due_date, amount, paid_amount, balance_amount, status)
  values (v_cliente, 'TESTE conta a mais', current_date, current_date, 100, 100, 0, 'paid') returning id into v_rec3;
  insert into public.payments (receivable_id, amount, payment_date, payment_method, status, bank_transaction_id)
  values (v_rec3, 100, current_date, 'pix', 'confirmed', v_tx);
  if not exists (select 1 from public.conferencia_dos_pagamentos where problema = 'entrada_aplicada_a_mais' and bank_transaction_id = v_tx) then
    raise exception 'T3: aplicar R$ 4.900 de um Pix de R$ 4.800 passou sem ser acusado';
  end if;

  -- ── T4. Pago gravado diferente da soma dos pagamentos é acusado ─────────────────────
  insert into public.receivables (client_id, description, issue_date, due_date, amount, paid_amount, balance_amount, status)
  values (v_cliente, 'TESTE pago sem pagamento', current_date, current_date, 300, 300, 0, 'paid') returning id into v_rec;
  if not exists (select 1 from public.conferencia_dos_pagamentos where problema = 'pago_diferente_da_soma' and receivable_id = v_rec) then
    raise exception 'T4: conta paga sem pagamento passou sem ser acusada';
  end if;

  -- ── T5. Ajuste ao valor do banco: o líquido acompanha; com taxa de cartão, não ───────
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, bank_connection_id, reconciled)
  values (current_date, 'TESTE Pix a mais', 100.53, 'credit', v_conta, true) returning id into v_tx;
  insert into public.receivables (client_id, description, issue_date, due_date, amount, paid_amount, balance_amount, status, bank_transaction_id)
  values (v_cliente, 'TESTE sinal', current_date, current_date, 100, 100, 0, 'paid', v_tx) returning id into v_rec;
  insert into public.payments (receivable_id, amount, net_amount, payment_date, payment_method, status)
  values (v_rec, 100, 100, current_date, 'pix', 'confirmed') returning id into v_pag;
  update public.bank_transactions set reconciled_payment_id = v_pag where id = v_tx;
  perform public.ajustar_ao_valor_do_banco('receivable', v_rec, null, v_admin);
  if (select net_amount from public.payments where id = v_pag) <> 100.53 then
    raise exception 'T5: o líquido ficou no valor antigo';
  end if;

  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, bank_connection_id, reconciled)
  values (current_date, 'TESTE maquininha', 1010, 'credit', v_conta, true) returning id into v_tx;
  insert into public.receivables (client_id, description, issue_date, due_date, amount, paid_amount, balance_amount, status, bank_transaction_id)
  values (v_cliente, 'TESTE cartão', current_date, current_date, 1000, 1000, 0, 'paid', v_tx) returning id into v_rec;
  insert into public.payments (receivable_id, amount, net_amount, card_fee_percent, payment_date, payment_method, status)
  values (v_rec, 1000, 970, 3, current_date, 'credit_card', 'confirmed') returning id into v_pag2;
  update public.bank_transactions set reconciled_payment_id = v_pag2 where id = v_tx;
  perform public.ajustar_ao_valor_do_banco('receivable', v_rec, null, v_admin);
  if (select net_amount from public.payments where id = v_pag2) <> 970 then
    raise exception 'T5: o líquido com taxa de cartão foi sobrescrito';
  end if;

  -- ── T6. Quem pode chamar e ler ──────────────────────────────────────────────────────
  if has_function_privilege('anon', 'public.registrar_pagamento_da_receita_do_extrato(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.registrar_pagamento_da_receita_do_extrato(uuid)', 'execute') then
    raise exception 'T6: registrar o pagamento da receita do extrato é só do servidor';
  end if;
  if has_function_privilege('anon', 'public._pagamento_segue_a_linha()', 'execute') then
    raise exception 'T6: anon não executa o gatilho';
  end if;
  if has_table_privilege('anon', 'public.recebimentos_do_extrato', 'select')
     or has_table_privilege('anon', 'public.conferencia_dos_pagamentos', 'select') then
    raise exception 'T6: anon não lê as views de conferência';
  end if;
  if not has_table_privilege('authenticated', 'public.recebimentos_do_extrato', 'select') then
    raise exception 'T6: o financeiro logado precisa ler os recebimentos do extrato';
  end if;
end $$;

select 'ok: receita do extrato ganha pagamento uma vez, gatilho liga e desliga, Pix pagando duas contas sem sobra, excesso e pago sem pagamento acusados, líquido acompanha o ajuste, permissões certas' as resultado;

rollback;
