-- Cancelar uma OS não solta o Pix que também paga outra conta (03/10/2026).
-- Run: npx supabase db query --linked -f supabase/tests/cancelar_os_reacomoda_pix.sql
-- Termina em ROLLBACK. Usa dados criados aqui (não depende de nenhuma conta real).
begin;

do $$
declare
  -- OS exige cliente e barco: um barco cadastrado e o dono dele.
  v_barco uuid := (select id from public.vessels where client_id is not null order by created_at limit 1);
  v_cliente uuid := (select client_id from public.vessels where id = v_barco);
  v_conta uuid := (select id from public.bank_connections where provider <> 'caixa' order by created_at limit 1);
  v_admin uuid := (select id from public.app_users where role = 'admin' and active order by created_at limit 1);
  v_os_a uuid; v_os_b uuid; v_os_c uuid;
  v_tx uuid; v_tx2 uuid; v_a uuid; v_b uuid; v_c uuid;
  r jsonb;
  j json;
begin
  insert into public.service_orders (client_id, vessel_id, service_order_number, status, quote_status) values (v_cliente, v_barco, 'OS-TESTE-A', 'open', 'approved') returning id into v_os_a;
  insert into public.service_orders (client_id, vessel_id, service_order_number, status, quote_status) values (v_cliente, v_barco, 'OS-TESTE-B', 'open', 'approved') returning id into v_os_b;
  insert into public.service_orders (client_id, vessel_id, service_order_number, status, quote_status) values (v_cliente, v_barco, 'OS-TESTE-C', 'open', 'approved') returning id into v_os_c;

  -- ── T1. Um Pix paga os sinais de duas OS; cancelar uma OS mantém a linha com a outra ────────
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, bank_connection_id, reconciled)
  values (current_date, 'TESTE Pix de duas OS', 4800, 'credit', v_conta, false) returning id into v_tx;
  insert into public.receivables (client_id, service_order_id, is_deposit, description, issue_date, due_date, amount, paid_amount, balance_amount, status)
  values (v_cliente, v_os_a, true, 'TESTE Sinal A', current_date, current_date, 2280, 0, 2280, 'pending') returning id into v_a;
  insert into public.receivables (client_id, service_order_id, is_deposit, description, issue_date, due_date, amount, paid_amount, balance_amount, status)
  values (v_cliente, v_os_b, true, 'TESTE Sinal B', current_date, current_date, 2520, 0, 2520, 'pending') returning id into v_b;
  r := public.aplicar_entrada_em_contas(v_tx, jsonb_build_array(
         jsonb_build_object('receivable_id', v_a, 'valor', 2280),
         jsonb_build_object('receivable_id', v_b, 'valor', 2520)), null, v_admin);

  j := public.cancel_service_order_cascade(v_os_a, 'TESTE cancelar a OS A');
  if (j ->> 'payments_cancelled')::int <> 1 then raise exception 'T1: um pagamento estornado, veio %', j; end if;
  if not (select reconciled from public.bank_transactions where id = v_tx) then
    raise exception 'T1: a linha ainda paga o sinal B e não pode voltar para a fila';
  end if;
  if (select receivable_id from public.payments where id = (select reconciled_payment_id from public.bank_transactions where id = v_tx)) <> v_b then
    raise exception 'T1: a linha devia ficar presa ao pagamento do sinal B';
  end if;
  if not exists (select 1 from public.receivables where id = v_b and bank_transaction_id = v_tx) then
    raise exception 'T1: o sinal B devia virar a conta dona da linha';
  end if;
  if exists (select 1 from public.receivables where id = v_a and (status <> 'cancelled' or bank_transaction_id is not null)) then
    raise exception 'T1: o sinal A cancelado não pode continuar dono da linha';
  end if;

  -- ── T2. Pix de uma OS só: cancelar a OS devolve a linha para a fila, como antes ─────────────
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, bank_connection_id, reconciled)
  values (current_date, 'TESTE Pix de uma OS', 1000, 'credit', v_conta, false) returning id into v_tx2;
  insert into public.receivables (client_id, service_order_id, is_deposit, description, issue_date, due_date, amount, paid_amount, balance_amount, status)
  values (v_cliente, v_os_c, true, 'TESTE Sinal C', current_date, current_date, 1000, 0, 1000, 'pending') returning id into v_c;
  r := public.aplicar_entrada_em_contas(v_tx2, jsonb_build_array(jsonb_build_object('receivable_id', v_c, 'valor', 1000)), null, v_admin);

  j := public.cancel_service_order_cascade(v_os_c, 'TESTE cancelar a OS C');
  if (select reconciled from public.bank_transactions where id = v_tx2)
     or (select reconciled_payment_id from public.bank_transactions where id = v_tx2) is not null then
    raise exception 'T2: sem outra conta, a linha volta para a fila';
  end if;
  if exists (select 1 from public.receivables where bank_transaction_id = v_tx2) then
    raise exception 'T2: nenhuma conta cancelada pode ficar dona da linha';
  end if;
  if (select status from public.service_orders where id = v_os_c) <> 'cancelled' then
    raise exception 'T2: a OS devia estar cancelada';
  end if;
end $$;

select 'ok: cancelar a OS de um sinal mantém o Pix com a outra conta (dona trocada); Pix de uma OS só volta para a fila sem conta cancelada como dona' as resultado;

rollback;
