import { supabase } from '@/integrations/supabase/client';
import { writeAuditLog } from '@/hooks/use-audit-log';

export async function updateReceivableFromSO(serviceOrderId: string, newTotal: number) {
  const { data: receivables } = await supabase
    .from('receivables')
    .select('*')
    .eq('service_order_id', serviceOrderId)
    .not('status', 'eq', 'paid');

  if (!receivables || receivables.length === 0) return;

  for (const rec of receivables) {
    const prev = { ...rec };
    const paidAmount = Number(rec.paid_amount || 0);
    const balance = Math.max(0, newTotal - paidAmount);
    const status = paidAmount >= newTotal ? 'paid' : paidAmount > 0 ? 'partially_paid' : 'pending';

    await supabase.from('receivables').update({
      amount: newTotal,
      balance_amount: balance,
      status,
    }).eq('id', rec.id);

    await writeAuditLog({
      table_name: 'receivables',
      record_id: rec.id,
      action: 'cascade_update',
      previous_value: { amount: prev.amount, balance_amount: prev.balance_amount, status: prev.status },
      new_value: { amount: newTotal, balance_amount: balance, status },
      reason: 'Atualização automática por alteração do total da OS',
      triggered_by_table: 'service_orders',
      triggered_by_id: serviceOrderId,
    });
  }
}

export async function cancelServiceOrderCascade(serviceOrderId: string, reason: string) {
  // ── Attempt atomic RPC first ─────────────────────────────────────────────
  // The RPC runs inside a single PostgreSQL transaction (BEGIN/COMMIT).
  // If ANY step fails, ALL changes roll back — no zombie/partial states.
  const { data: rpcData, error: rpcErr } = await supabase.rpc('cancel_service_order_cascade', {
    p_service_order_id: serviceOrderId,
    p_reason: reason,
  });

  if (!rpcErr && rpcData?.success) {
    await writeAuditLog({
      table_name: 'service_orders',
      record_id: serviceOrderId,
      action: 'cancel',
      new_value: { status: 'cancelled' },
      reason,
    });
    return {
      parts_restored: rpcData.parts_restored,
      receivables_cancelled: rpcData.receivables_cancelled,
      payments_cancelled: rpcData.payments_cancelled,
    };
  }

  // ── Fallback: legacy sequential approach ─────────────────────────────────
  console.warn('[cancelServiceOrderCascade] RPC unavailable, using fallback.', rpcErr);
  let partsRestored = 0;
  let receivablesCancelled = 0;
  let paymentsCancelled = 0;

  // 1. Restore parts stock
  const { data: parts } = await supabase
    .from('service_order_parts')
    .select('*')
    .eq('service_order_id', serviceOrderId);

  for (const part of parts || []) {
    const { data: prod } = await supabase
      .from('products')
      .select('stock_quantity')
      .eq('id', part.product_id)
      .single();

    await supabase.from('products').update({
      stock_quantity: (prod?.stock_quantity || 0) + part.quantity,
    }).eq('id', part.product_id);

    await supabase.from('inventory_movements').insert({
      product_id: part.product_id,
      movement_type: 'return',
      quantity_delta: part.quantity,
      reference_type: 'service_order_cancel',
      reference_id: serviceOrderId,
      unit_cost_snapshot: part.unit_cost_snapshot,
    });

    partsRestored++;
  }

  // 2. Cancel receivables and their payments
  const { data: receivables } = await supabase
    .from('receivables')
    .select('*')
    .eq('service_order_id', serviceOrderId);

  for (const rec of receivables || []) {
    const { data: payments } = await supabase
      .from('payments')
      .select('*')
      .eq('receivable_id', rec.id)
      .eq('status', 'confirmed');

    for (const payment of payments || []) {
      await supabase.from('payments').update({
        status: 'cancelled',
        cancelled_at: new Date().toISOString(),
        cancellation_reason: reason,
      }).eq('id', payment.id);

      await supabase.from('bank_transactions').update({
        reconciled: false,
        reconciled_payment_id: null,
      }).eq('reconciled_payment_id', payment.id);

      await writeAuditLog({
        table_name: 'payments',
        record_id: payment.id,
        action: 'cancel',
        previous_value: { status: 'confirmed', amount: payment.amount },
        new_value: { status: 'cancelled' },
        reason,
        triggered_by_table: 'service_orders',
        triggered_by_id: serviceOrderId,
      });
      paymentsCancelled++;
    }

    await supabase.from('receivables').update({
      status: 'cancelled',
      balance_amount: 0,
    }).eq('id', rec.id);

    await writeAuditLog({
      table_name: 'receivables',
      record_id: rec.id,
      action: 'cancel',
      previous_value: { status: rec.status },
      new_value: { status: 'cancelled' },
      reason,
      triggered_by_table: 'service_orders',
      triggered_by_id: serviceOrderId,
    });
    receivablesCancelled++;
  }

  // 3. Update service order
  await supabase.from('service_orders').update({
    status: 'cancelled',
    cancelled_at: new Date().toISOString(),
    cancellation_reason: reason,
  }).eq('id', serviceOrderId);

  await writeAuditLog({
    table_name: 'service_orders',
    record_id: serviceOrderId,
    action: 'cancel',
    new_value: { status: 'cancelled' },
    reason,
  });

  return { parts_restored: partsRestored, receivables_cancelled: receivablesCancelled, payments_cancelled: paymentsCancelled };
}


export async function reopenServiceOrder(serviceOrderId: string, reason: string) {
  const { data: so } = await supabase
    .from('service_orders')
    .select('status')
    .eq('id', serviceOrderId)
    .single();

  if (!so || !['invoiced', 'completed'].includes(so.status)) {
    throw new Error('Só é possível reabrir OS com status Faturada ou Concluída.');
  }

  // Cancel payments on receivables
  const { data: receivables } = await supabase
    .from('receivables')
    .select('*')
    .eq('service_order_id', serviceOrderId);

  for (const rec of receivables || []) {
    const { data: payments } = await supabase
      .from('payments')
      .select('*')
      .eq('receivable_id', rec.id)
      .eq('status', 'confirmed');

    for (const payment of payments || []) {
      await supabase.from('payments').update({
        status: 'cancelled',
        cancelled_at: new Date().toISOString(),
        cancellation_reason: `${reason} (reabertura de OS)`,
      }).eq('id', payment.id);

      await supabase.from('bank_transactions').update({
        reconciled: false,
        reconciled_payment_id: null,
      }).eq('reconciled_payment_id', payment.id);

      await writeAuditLog({
        table_name: 'payments',
        record_id: payment.id,
        action: 'cancel',
        previous_value: { status: 'confirmed' },
        new_value: { status: 'cancelled' },
        reason: `${reason} (reabertura de OS)`,
        triggered_by_table: 'service_orders',
        triggered_by_id: serviceOrderId,
      });
    }

    await supabase.from('receivables').update({
      paid_amount: 0,
      balance_amount: rec.amount,
      status: 'pending',
    }).eq('id', rec.id);

    await writeAuditLog({
      table_name: 'receivables',
      record_id: rec.id,
      action: 'reopen',
      previous_value: { status: rec.status, paid_amount: rec.paid_amount },
      new_value: { status: 'pending', paid_amount: 0 },
      reason,
      triggered_by_table: 'service_orders',
      triggered_by_id: serviceOrderId,
    });
  }

  await supabase.from('service_orders').update({
    status: 'completed',
    reopened_at: new Date().toISOString(),
    reopen_reason: reason,
  }).eq('id', serviceOrderId);

  await writeAuditLog({
    table_name: 'service_orders',
    record_id: serviceOrderId,
    action: 'reopen',
    previous_value: { status: so.status },
    new_value: { status: 'completed' },
    reason,
  });
}

export async function recalcReceivableBalance(receivableId: string) {
  const { data: payments } = await supabase
    .from('payments')
    .select('amount')
    .eq('receivable_id', receivableId)
    .eq('status', 'confirmed');

  const totalPaid = (payments || []).reduce((s, p) => s + Number(p.amount), 0);

  const { data: rec } = await supabase
    .from('receivables')
    .select('amount')
    .eq('id', receivableId)
    .single();

  const amount = Number(rec?.amount || 0);
  const balance = Math.max(0, amount - totalPaid);
  const status = totalPaid >= amount ? 'paid' : totalPaid > 0 ? 'partially_paid' : 'pending';

  await supabase.from('receivables').update({
    paid_amount: totalPaid,
    balance_amount: balance,
    status,
  }).eq('id', receivableId);
}

export async function recalcPayableBalance(payableId: string) {
  const { data: payments } = await supabase
    .from('payments')
    .select('amount')
    .eq('payable_id', payableId)
    .eq('status', 'confirmed');

  const totalPaid = (payments || []).reduce((s, p) => s + Number(p.amount), 0);

  const { data: pay } = await supabase
    .from('payables')
    .select('amount')
    .eq('id', payableId)
    .single();

  const amount = Number(pay?.amount || 0);
  const balance = Math.max(0, amount - totalPaid);
  const status = totalPaid >= amount ? 'paid' : totalPaid > 0 ? 'partially_paid' : 'pending';

  await supabase.from('payables').update({
    paid_amount: totalPaid,
    balance_amount: balance,
    status,
  }).eq('id', payableId);
}

export async function cancelPaymentCascade(paymentId: string, reason: string) {
  const { data: payment } = await supabase
    .from('payments')
    .select('*')
    .eq('id', paymentId)
    .single();

  if (!payment) throw new Error('Pagamento não encontrado');

  await supabase.from('payments').update({
    status: 'cancelled',
    cancelled_at: new Date().toISOString(),
    cancellation_reason: reason,
  }).eq('id', paymentId);

  if (payment.receivable_id) {
    await recalcReceivableBalance(payment.receivable_id);
  }
  if (payment.payable_id) {
    await recalcPayableBalance(payment.payable_id);
  }

  // Undo bank reconciliation
  await supabase.from('bank_transactions').update({
    reconciled: false,
    reconciled_payment_id: null,
  }).eq('reconciled_payment_id', paymentId);

  // Undo technician expense reimbursement if this payment was the proof
  await supabase.from('service_order_expenses').update({
    reimbursed: false,
    reimbursed_at: null,
    reimbursed_payment_id: null,
  }).eq('reimbursed_payment_id', paymentId);

  await writeAuditLog({
    table_name: 'payments',
    record_id: paymentId,
    action: 'cancel',
    previous_value: { status: 'confirmed', amount: payment.amount },
    new_value: { status: 'cancelled' },
    reason,
  });
}
