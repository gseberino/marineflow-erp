-- Ajustar uma conta a receber ao valor do banco (02/10/2026).
-- Run: npx supabase db query --linked -f supabase/tests/ajustar_ao_valor_do_banco.sql
-- Termina em ROLLBACK. Usa dados criados aqui (não depende de nenhuma conta real), para o teste
-- não envelhecer quando os lançamentos de produção mudarem.
begin;

do $$
declare
  v_cliente uuid := (select id from public.clients order by created_at limit 1);
  v_conta uuid := (select id from public.bank_connections where provider <> 'caixa' order by created_at limit 1);
  v_admin uuid := (select id from public.app_users where role = 'admin' and active order by created_at limit 1);
  v_tx uuid; v_rec uuid; v_pag uuid;
  r jsonb;
begin
  -- ── T1. Banco maior: o cliente pagou R$ 0,53 a mais ──────────────────────────────
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, bank_connection_id, reconciled)
  values (current_date, 'TESTE Pix a mais', 100.53, 'credit', v_conta, true) returning id into v_tx;
  insert into public.receivables (client_id, description, issue_date, due_date, amount, paid_amount, balance_amount, status, bank_transaction_id)
  values (v_cliente, 'TESTE sinal', current_date, current_date, 100, 100, 0, 'paid', v_tx) returning id into v_rec;
  insert into public.payments (receivable_id, amount, payment_date, payment_method, status)
  values (v_rec, 100, current_date, 'pix', 'confirmed') returning id into v_pag;
  update public.bank_transactions set reconciled_payment_id = v_pag where id = v_tx;

  r := public.ajustar_ao_valor_do_banco('receivable', v_rec, null, v_admin);
  if (r ->> 'diferenca')::numeric <> 0.53 then raise exception 'T1: diferença errada: %', r; end if;
  if not exists (select 1 from public.receivables where id = v_rec and amount = 100.53 and paid_amount = 100.53
                  and balance_amount = 0 and status = 'paid' and notes like '%pagou R$ 0,53 a mais%') then
    raise exception 'T1: o lançamento não passou a valer o banco';
  end if;
  if (select amount from public.payments where id = v_pag) <> 100.53 then raise exception 'T1: o pagamento não passou a valer o banco'; end if;
  if (select diferenca from public.conciliacao_lancamentos where lado = 'receivable' and id = v_rec) <> 0 then
    raise exception 'T1: a conciliação ainda acusa diferença';
  end if;
  if not exists (select 1 from public.reconciliation_log where receivable_id = v_rec and acao = 'ajustou_ao_banco' and autor = v_admin) then
    raise exception 'T1: não ficou na trilha';
  end if;

  -- ── T2. Ajustar de novo: já bate ─────────────────────────────────────────────────
  begin
    perform public.ajustar_ao_valor_do_banco('receivable', v_rec, null, v_admin);
    raise exception 'ajustou duas vezes';
  exception when others then
    if sqlerrm not like '%já bate com o banco%' then raise exception 'T2: %', sqlerrm; end if;
  end;

  -- ── T3. Banco menor: R$ 20 em aberto viram desconto (o caso da OS-00046) ──────────
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, bank_connection_id, reconciled)
  values (current_date, 'TESTE Pix a menos', 500, 'credit', v_conta, true) returning id into v_tx;
  insert into public.receivables (client_id, description, issue_date, due_date, amount, paid_amount, balance_amount, status, bank_transaction_id)
  values (v_cliente, 'TESTE revenda', current_date, current_date, 520, 500, 20, 'partially_paid', v_tx) returning id into v_rec;
  insert into public.payments (receivable_id, amount, payment_date, payment_method, status)
  values (v_rec, 500, current_date, 'pix', 'confirmed') returning id into v_pag;
  update public.bank_transactions set reconciled_payment_id = v_pag where id = v_tx;

  r := public.ajustar_ao_valor_do_banco('receivable', v_rec, 'combinado com o cliente', v_admin);
  if not exists (select 1 from public.receivables where id = v_rec and amount = 500 and paid_amount = 500
                  and balance_amount = 0 and status = 'paid' and notes like '%deixam de ser cobrados (desconto)%'
                  and notes like '%combinado com o cliente%') then
    raise exception 'T3: o desconto não foi aplicado: %', r;
  end if;

  -- ── T4. Dois pagamentos: recusa (o caso da OS-00034) ────────────────────────────
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, bank_connection_id, reconciled)
  values (current_date, 'TESTE Pix parcial', 25000, 'credit', v_conta, true) returning id into v_tx;
  insert into public.receivables (client_id, description, issue_date, due_date, amount, paid_amount, balance_amount, status, bank_transaction_id)
  values (v_cliente, 'TESTE saldo final', current_date, current_date, 29000, 29000, 0, 'paid', v_tx) returning id into v_rec;
  insert into public.payments (receivable_id, amount, payment_date, payment_method, status)
  values (v_rec, 25000, current_date, 'pix', 'confirmed') returning id into v_pag;
  insert into public.payments (receivable_id, amount, payment_date, payment_method, status)
  values (v_rec, 4000, current_date, 'cash', 'confirmed');
  update public.bank_transactions set reconciled_payment_id = v_pag where id = v_tx;
  begin
    perform public.ajustar_ao_valor_do_banco('receivable', v_rec, null, v_admin);
    raise exception 'ajustou com dois pagamentos';
  exception when others then
    if sqlerrm not like '%2 pagamento(s)%' then raise exception 'T4: %', sqlerrm; end if;
  end;
  if (select amount from public.receivables where id = v_rec) <> 29000 then raise exception 'T4: mexeu no valor'; end if;

  -- ── T5. Conta a pagar e lançamento sem banco: recusa com o caminho ─────────────────
  begin
    perform public.ajustar_ao_valor_do_banco('payable', gen_random_uuid(), null, v_admin);
    raise exception 'aceitou conta a pagar';
  exception when others then
    if sqlerrm not like '%desfaça a aprovação%' then raise exception 'T5: %', sqlerrm; end if;
  end;

  -- ── T6. Quem pode chamar ────────────────────────────────────────────────────────
  if has_function_privilege('anon', 'public.ajustar_ao_valor_do_banco(text, uuid, text, uuid)', 'execute') then
    raise exception 'T6: anon não pode ajustar lançamento';
  end if;
  if not has_function_privilege('authenticated', 'public.ajustar_ao_valor_do_banco(text, uuid, text, uuid)', 'execute') then
    raise exception 'T6: o financeiro logado precisa poder ajustar';
  end if;
end $$;

select 'ok: banco maior ajusta e acaba a diferença, banco menor vira desconto, dois pagamentos recusa, conta a pagar recusa, trilha e permissões certas' as resultado;
rollback;
