-- Cancelar uma OS não solta o Pix que também paga outra conta (forma A).
--
-- POR QUE: cancel_service_order_cascade (julho) estornava os pagamentos das contas da OS e fazia
-- `reconciled = false` em toda linha do banco ligada a eles. Desde 02/10 um Pix pode pagar várias
-- contas: cancelar a OS de um dos sinais soltava a linha inteira, ela voltava para a fila do
-- Extrato com a outra conta ainda paga por ela, e aprová-la de novo contava o dinheiro em dobro.
-- Era o mesmo defeito que a F2 corrigiu em cancelar_lancamento/desfazer_aprovacao — esta função
-- ficou de fora.
--
-- Agora, como cancelar_lancamento: a conta cancelada deixa de ser a "dona" da linha, e cada linha
-- tocada passa por _reacomodar_entrada — continua conciliada se ainda paga outra conta; senão volta
-- para a fila, como antes. Nada mais muda (estoque, cobranças, status da OS).

create or replace function public.cancel_service_order_cascade(p_service_order_id uuid, p_reason text)
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_part record;
  v_receivable record;
  v_payment record;
  v_parts_restored int := 0;
  v_receivables_cancelled int := 0;
  v_payments_cancelled int := 0;
  v_collections_cancelled int := 0;
  v_deposit_paid numeric := 0;
  v_now timestamptz := now();
  v_linhas uuid[] := '{}';
  v_linha uuid;
begin
  if not public.stock_model_v2_on() then
    for v_part in
      select id, product_id, quantity, unit_cost_snapshot
      from public.service_order_parts
      where service_order_id = p_service_order_id
    loop
      insert into public.inventory_movements
        (product_id, movement_type, quantity_delta, reference_type, reference_id, unit_cost_snapshot)
      values
        (v_part.product_id, 'return', v_part.quantity, 'service_order_cancel', p_service_order_id, v_part.unit_cost_snapshot);
      v_parts_restored := v_parts_restored + 1;
    end loop;
  end if;

  for v_receivable in
    select id, status, is_deposit, paid_amount, bank_transaction_id
    from public.receivables
    where service_order_id = p_service_order_id
      and status <> 'cancelled'
  loop
    if v_receivable.is_deposit and coalesce(v_receivable.paid_amount, 0) > 0 then
      v_deposit_paid := v_deposit_paid + v_receivable.paid_amount;
    end if;
    if v_receivable.bank_transaction_id is not null then
      v_linhas := v_linhas || v_receivable.bank_transaction_id;
    end if;

    for v_payment in
      select p.id, p.amount, p.bank_transaction_id,
             (select t.id from public.bank_transactions t where t.reconciled_payment_id = p.id limit 1) as linha_presa
      from public.payments p
      where p.receivable_id = v_receivable.id
        and p.status = 'confirmed'
    loop
      update public.payments
      set status = 'cancelled',
          cancelled_at = v_now,
          cancellation_reason = p_reason
      where id = v_payment.id;

      if v_payment.bank_transaction_id is not null then
        v_linhas := v_linhas || v_payment.bank_transaction_id;
      end if;
      if v_payment.linha_presa is not null then
        v_linhas := v_linhas || v_payment.linha_presa;
      end if;
      v_payments_cancelled := v_payments_cancelled + 1;
    end loop;

    update public.receivables
    set status = 'cancelled',
        balance_amount = 0,
        bank_transaction_id = null
    where id = v_receivable.id;

    v_receivables_cancelled := v_receivables_cancelled + 1;
  end loop;

  -- Cada linha tocada: segue presa a outra conta que ela ainda paga, ou volta para a fila.
  for v_linha in select distinct unnest(v_linhas)
  loop
    if not public._reacomodar_entrada(v_linha) then
      update public.bank_transactions
         set reconciled = false, reconciled_payment_id = null
       where id = v_linha;
    end if;
  end loop;

  update public.collections
  set status = 'cancelled'
  where service_order_id = p_service_order_id
    and status <> 'cancelled';
  get diagnostics v_collections_cancelled = row_count;

  update public.service_orders
  set status = 'cancelled',
      cancelled_at = v_now,
      cancellation_reason = p_reason
  where id = p_service_order_id;

  return json_build_object(
    'success', true,
    'parts_restored', v_parts_restored,
    'receivables_cancelled', v_receivables_cancelled,
    'payments_cancelled', v_payments_cancelled,
    'collections_cancelled', v_collections_cancelled,
    'deposit_paid', v_deposit_paid
  );
end;
$function$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261003220000', 'cancelar_os_reacomoda_pix')
on conflict do nothing;
