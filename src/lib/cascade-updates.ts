import { supabase } from '@/integrations/supabase/client';
import { writeAuditLog } from '@/hooks/use-audit-log';
import { redistribuirRecebiveis } from '@/lib/receivable-redistribution';

/**
 * Lançada quando uma mudança no total da OS faria o novo total ficar abaixo
 * do que o cliente já pagou. O mutation que chamou recalcTotals/recalcExpenseTotals
 * (que por sua vez chama updateReceivableFromSO) deve capturar esse erro e
 * reverter a alteração que o originou — ver Fix C no plano de correção.
 */
export class GrandTotalBelowPaidError extends Error {}

/**
 * O supabase-js DEVOLVE o erro, não lança: nestas cascatas cada gravação era um `await` sem conferir,
 * e uma falha no meio deixava metade feita, calada (inventário de 03/10/2026). Toda escrita e leitura
 * daqui passa por este ajudante.
 */
function conferir<T extends { error: { message: string } | null }>(r: T, oQue: string): T {
  if (r.error) throw new Error(`${oQue}: ${r.error.message}`);
  return r;
}

export async function updateReceivableFromSO(serviceOrderId: string, newTotal: number) {
  const { data: receivables } = conferir(await supabase
    .from('receivables')
    .select('*')
    .eq('service_order_id', serviceOrderId)
    .not('status', 'eq', 'cancelled'), 'Não consegui ler as contas da OS');

  if (!receivables || receivables.length === 0) return;

  // [MF-AUD-009] A aritmética saiu daqui para `receivable-redistribution.ts`, um módulo puro
  // que o AGENTE também usa. Antes, a regra existia só nesta função: pelo caminho do agente
  // (RPC `recalc_so_totals`) não havia cascata nem piso, e dava para derrubar o total da OS
  // abaixo do que o cliente já tinha pago. Duas fórmulas de dinheiro divergem — este arquivo
  // passou a ser só o "quem grava".
  const plano = redistribuirRecebiveis(receivables, newTotal);

  if (plano.bloqueado) {
    throw new GrandTotalBelowPaidError(plano.motivo!);
  }

  for (const alt of plano.alteracoes) {
    conferir(await supabase.from('receivables').update({
      amount: alt.amount,
      balance_amount: alt.balance_amount,
      status: alt.status,
    }).eq('id', alt.id), 'Não consegui atualizar a conta da OS');

    await writeAuditLog({
      table_name: 'receivables',
      record_id: alt.id,
      action: 'cascade_update',
      previous_value: alt.anterior,
      new_value: {
        amount: alt.amount,
        balance_amount: alt.balance_amount,
        status: alt.status,
      },
      reason: 'Atualização automática por alteração do total da OS (redistribuição proporcional)',
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

  if (!rpcErr && (rpcData as any)?.success) {
    await writeAuditLog({
      table_name: 'service_orders',
      record_id: serviceOrderId,
      action: 'cancel',
      new_value: { status: 'cancelled' },
      reason,
    });
    return {
      parts_restored: (rpcData as any).parts_restored,
      receivables_cancelled: (rpcData as any).receivables_cancelled,
      payments_cancelled: (rpcData as any).payments_cancelled,
      collections_cancelled: (rpcData as any).collections_cancelled ?? 0,
      deposit_paid: Number((rpcData as any).deposit_paid ?? 0),
    };
  }

  // O caminho antigo, passo a passo no navegador, rodava quando a função falhava: sem transação (metade
  // feita a cada erro) e soltando a linha do banco inteira mesmo quando o Pix paga outra conta — o
  // defeito que a função do banco corrige desde 03/10/2026. Falhou a função, falha o cancelamento.
  throw new Error(`Não consegui cancelar a OS: ${rpcErr?.message ?? 'resposta inesperada do banco'}`);
}


export async function reopenServiceOrder(serviceOrderId: string, reason: string) {
  const { data: so } = conferir(await supabase
    .from('service_orders')
    .select('status')
    .eq('id', serviceOrderId)
    .single(), 'Não consegui ler a OS');

  if (!so || !['invoiced', 'completed'].includes(so.status)) {
    throw new Error('Só é possível reabrir OS com status Faturada ou Concluída.');
  }

  // Cancel payments on receivables
  const { data: receivables } = conferir(await supabase
    .from('receivables')
    .select('*')
    .eq('service_order_id', serviceOrderId), 'Não consegui ler as contas da OS');

  // Pagamento que veio de uma linha do banco não se estorna daqui: um Pix pode pagar outras contas
  // (forma A), e soltar a linha faria o dinheiro voltar para a fila e entrar em dobro (03/10/2026).
  const idsDasContas = (receivables || []).map((r) => r.id);
  if (idsDasContas.length > 0) {
    const { data: doExtrato } = conferir(await supabase
      .from('payments')
      .select('id')
      .in('receivable_id', idsDasContas)
      .eq('status', 'confirmed')
      .not('bank_transaction_id', 'is', null)
      .limit(1), 'Não consegui ler os pagamentos da OS');
    if ((doExtrato ?? []).length > 0) {
      throw new Error('Esta OS tem pagamento que veio do extrato do banco. Para reabrir, desfaça antes o vínculo na correção do lançamento (Ligado ao extrato).');
    }
  }

  for (const rec of receivables || []) {
    const { data: payments } = conferir(await supabase
      .from('payments')
      .select('*')
      .eq('receivable_id', rec.id)
      .eq('status', 'confirmed'), 'Não consegui ler os pagamentos da conta');

    for (const payment of payments || []) {
      conferir(await supabase.from('payments').update({
        status: 'cancelled',
        cancelled_at: new Date().toISOString(),
        cancellation_reason: `${reason} (reabertura de OS)`,
      }).eq('id', payment.id), 'Não consegui estornar o pagamento');

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

    conferir(await supabase.from('receivables').update({
      paid_amount: 0,
      balance_amount: rec.amount,
      status: 'pending',
    }).eq('id', rec.id), 'Não consegui reabrir a conta');

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

  conferir(await supabase.from('service_orders').update({
    status: 'completed',
    reopened_at: new Date().toISOString(),
    reopen_reason: reason,
  }).eq('id', serviceOrderId), 'Não consegui reabrir a OS');

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
  const { data: payments } = conferir(await supabase
    .from('payments')
    .select('amount')
    .eq('receivable_id', receivableId)
    .eq('status', 'confirmed'), 'Não consegui ler os pagamentos da conta');

  const totalPaid = (payments || []).reduce((s, p) => s + Number(p.amount), 0);

  const { data: rec } = conferir(await supabase
    .from('receivables')
    .select('amount')
    .eq('id', receivableId)
    .single(), 'Não consegui ler a conta');

  const amount = Number(rec?.amount || 0);
  const balance = Math.max(0, amount - totalPaid);
  const status = totalPaid >= amount ? 'paid' : totalPaid > 0 ? 'partially_paid' : 'pending';

  conferir(await supabase.from('receivables').update({
    paid_amount: totalPaid,
    balance_amount: balance,
    status,
  }).eq('id', receivableId), 'Não consegui recalcular a conta');
}

export async function recalcPayableBalance(payableId: string) {
  const { data: payments } = conferir(await supabase
    .from('payments')
    .select('amount')
    .eq('payable_id', payableId)
    .eq('status', 'confirmed'), 'Não consegui ler os pagamentos da conta');

  const totalPaid = (payments || []).reduce((s, p) => s + Number(p.amount), 0);

  const { data: pay } = conferir(await supabase
    .from('payables')
    .select('amount')
    .eq('id', payableId)
    .single(), 'Não consegui ler a conta');

  const amount = Number(pay?.amount || 0);
  const balance = Math.max(0, amount - totalPaid);
  const status = totalPaid >= amount ? 'paid' : totalPaid > 0 ? 'partially_paid' : 'pending';

  conferir(await supabase.from('payables').update({
    paid_amount: totalPaid,
    balance_amount: balance,
    status,
  }).eq('id', payableId), 'Não consegui recalcular a conta');
}

/** Pagamento que veio do extrato: o caminho que devolve a linha para a fila, em vez do estorno. */
function orientacaoDoExtrato(p: { receivable_id?: string | null; payable_id?: string | null }): string {
  return p.payable_id
    ? 'Este pagamento veio do extrato do banco: não se estorna aqui. Em Contas a pagar, abra "Corrigir" neste lançamento e, '
      + 'no quadro "Ligado ao extrato", use "Desfazer a aprovação" (ou "Desfazer o vínculo com o extrato") — a linha volta '
      + 'para a fila do Extrato.'
    : 'Este pagamento veio do extrato do banco: não se estorna aqui. Em Contas a receber, abra "Corrigir" nesta conta e, '
      + 'no quadro "Ligado ao extrato", desfaça o vínculo — a linha volta para a fila do Extrato.';
}

export async function cancelPaymentCascade(paymentId: string, reason: string) {
  const { data: payment } = conferir(await supabase
    .from('payments')
    .select('*')
    .eq('id', paymentId)
    .single(), 'Não consegui ler o pagamento');

  if (!payment) throw new Error('Pagamento não encontrado');

  // Pagamento que veio de uma linha do banco (forma A): o "desfazer aplicação" do banco estorna o que
  // a aplicação criou, devolve saldo/acréscimo/desconto e só solta a linha se ela não pagar mais nada.
  // Se era um pagamento lançado à mão e só ligado ao Pix, ele só desliga — e o estorno segue abaixo.
  if (payment.receivable_id && (payment as { bank_transaction_id?: string | null }).bank_transaction_id) {
    conferir(await supabase.rpc('desfazer_aplicacao' as never, { p_pagamento: paymentId, p_motivo: reason } as never),
      'Não consegui desfazer a aplicação do Pix');
    const { data: depois } = conferir(await supabase.from('payments').select('status').eq('id', paymentId).single(),
      'Não consegui reler o pagamento');
    if ((depois as { status: string } | null)?.status === 'cancelled') {
      await writeAuditLog({
        table_name: 'payments', record_id: paymentId, action: 'cancel',
        previous_value: { status: 'confirmed', amount: payment.amount }, new_value: { status: 'cancelled' }, reason,
      });
      return;
    }
  }

  // O estorno em si (07/10/2026) é a função do banco estornar_pagamento — a mesma do assistente:
  // cancela o pagamento com o motivo, recalcula a conta, desfaz o reembolso de gasto da OS e grava a
  // auditoria NUMA transação. Antes a tela gravava passo a passo pelo navegador: em mês fechado o
  // gatilho da conta recusava o recálculo DEPOIS de o pagamento já estar cancelado — o pagamento
  // ficava estornado e a conta continuava paga.
  // Pagamento que veio do EXTRATO a função recusa: a linha do banco é a prova de que o dinheiro
  // andou. O Pix aplicado numa conta a receber já foi tratado acima (desfazer_aplicacao); o resto
  // (lançamento aprovado do extrato, linha conciliada) tem caminho próprio, que devolve a linha para
  // a fila — a tela diz qual, em vez de cancelar o pagamento e deixar a linha presa à conta.
  const { error } = await supabase.rpc('estornar_pagamento' as never, { p_pagamento: paymentId, p_motivo: reason } as never);
  if (error) {
    if (/veio do extrato/i.test(error.message)) throw new Error(orientacaoDoExtrato(payment));
    throw new Error(`Não consegui estornar o pagamento: ${error.message}`);
  }
}
