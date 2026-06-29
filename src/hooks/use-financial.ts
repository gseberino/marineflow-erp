import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import type { BankTransaction } from '@/lib/bank-parser';
import { writeAuditLog } from '@/hooks/use-audit-log';
import { cancelPaymentCascade } from '@/lib/cascade-updates';

export function useReceivables() {
  return useQuery({
    queryKey: ['receivables'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('receivables')
        .select('*, clients!receivables_client_id_fkey(id,name,whatsapp,phone), service_orders!receivables_service_order_id_fkey(id,service_order_number,share_token)')
        .order('due_date', { ascending: true });
      if (error) throw error;
      return data;
    },
  });
}

export function usePayables() {
  return useQuery({
    queryKey: ['payables'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('payables')
        .select('*, suppliers!payables_supplier_id_fkey(name), service_orders!payables_linked_service_order_id_fkey(service_order_number), service_order_expenses!service_order_expenses_linked_payable_id_fkey(receipt_url)')
        .order('due_date', { ascending: true });
      if (error) throw error;
      return data;
    },
  });
}

export function useCreateReceivable() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (rec: {
      client_id: string; description: string; issue_date: string;
      due_date: string; amount: number; currency?: string;
      service_order_id?: string; notes?: string;
      cost_center_id?: string; sub_category?: string;
    }) => {
      const { data, error } = await supabase.from('receivables').insert({
        ...rec, balance_amount: rec.amount, paid_amount: 0, status: 'pending',
      }).select().single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['receivables'] }),
  });
}

export function useCreatePayable() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (p: {
      description: string; issue_date: string; due_date: string;
      amount: number; currency?: string; expense_category?: string;
      supplier_id?: string; name?: string;
      linked_service_order_id?: string; notes?: string;
      origin?: string; bank_transaction_id?: string;
      cost_center_id?: string; sub_category?: string;
    }) => {
      const { data, error } = await supabase.from('payables').insert({
        ...p, balance_amount: p.amount, paid_amount: 0, status: 'pending',
      } as any).select().single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['payables'] }),
  });
}

export function usePayments(receivableId?: string, payableId?: string) {
  return useQuery({
    queryKey: ['payments', receivableId, payableId],
    queryFn: async () => {
      let q = supabase.from('payments').select('*').order('payment_date', { ascending: false });
      if (receivableId) q = q.eq('receivable_id', receivableId);
      if (payableId) q = q.eq('payable_id', payableId);
      const { data, error } = await q;
      if (error) throw error;
      return data;
    },
    enabled: !!(receivableId || payableId),
  });
}

export function useRegisterPayment() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: {
      receivable_id?: string; payable_id?: string;
      payment_date: string; amount: number;
      payment_method: string; installments?: number;
      card_fee_percent?: number; net_amount?: number; notes?: string;
    }) => {
      // Usa exclusivamente a RPC atômica — o fallback manual foi removido pois
      // bypassava a verificação de role adicionada em register_payment_and_update_balance.
      // O RPC está deployado desde 20260508 e protegido desde 20260629.
      const { data: rpcData, error: rpcErr } = await supabase.rpc('register_payment_and_update_balance', {
        p_receivable_id:    input.receivable_id || null,
        p_payable_id:       input.payable_id || null,
        p_amount:           input.amount,
        p_payment_date:     input.payment_date.split('T')[0], // garante formato DATE
        p_payment_method:   input.payment_method,
        p_installments:     input.installments || 1,
        p_card_fee_percent: input.card_fee_percent || 0,
        p_net_amount:       input.net_amount || input.amount,
        p_notes:            input.notes || null,
      });

      if (rpcErr) throw rpcErr;
      if (!(rpcData as any)?.payment_id) throw new Error('RPC não retornou payment_id');

      const paymentId = (rpcData as any).payment_id;

      await writeAuditLog({
        table_name: 'payments',
        record_id: paymentId,
        action: 'update',
        new_value: { amount: input.amount, payment_method: input.payment_method },
      });

      return { id: paymentId };
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['receivables'] });
      qc.invalidateQueries({ queryKey: ['payables'] });
      qc.invalidateQueries({ queryKey: ['payments'] });
      qc.invalidateQueries({ queryKey: ['financial-summary'] });
      // Invalida service-orders para refletir o payment_status atualizado pelo trigger
      qc.invalidateQueries({ queryKey: ['service-orders'] });
    },
  });
}

export function useCancelPayment() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, reason }: { id: string; reason: string }) => {
      await cancelPaymentCascade(id, reason);
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['payments'] });
      qc.invalidateQueries({ queryKey: ['receivables'] });
      qc.invalidateQueries({ queryKey: ['payables'] });
      qc.invalidateQueries({ queryKey: ['bank-transactions'] });
      qc.invalidateQueries({ queryKey: ['financial-summary'] });
      // Invalida service-orders para refletir o payment_status revertido pelo trigger
      qc.invalidateQueries({ queryKey: ['service-orders'] });
    },
  });
}

export function useFinancialSummary() {
  return useQuery({
    queryKey: ['financial-summary'],
    queryFn: async () => {
      const today = new Date().toISOString().split('T')[0];
      const firstOfMonth = `${today.substring(0, 7)}-01`;

      const [recRes, recOverdue, payRes, payOverdue, collectedRes, paidRes] = await Promise.all([
        supabase.from('receivables').select('balance_amount').not('status', 'in', '("paid","cancelled")'),
        supabase.from('receivables').select('balance_amount').not('status', 'in', '("paid","cancelled")').lt('due_date', today),
        supabase.from('payables').select('balance_amount').not('status', 'in', '("paid","cancelled")'),
        supabase.from('payables').select('balance_amount').not('status', 'in', '("paid","cancelled")').lt('due_date', today),
        supabase.from('payments').select('amount').not('receivable_id', 'is', null).eq('status', 'confirmed').gte('payment_date', firstOfMonth),
        supabase.from('payments').select('amount').not('payable_id', 'is', null).eq('status', 'confirmed').gte('payment_date', firstOfMonth),
      ]);

      const sum = (rows: any[] | null) => (rows || []).reduce((s, r) => s + Number(r.balance_amount || r.amount || 0), 0);

      return {
        total_receivable: sum(recRes.data),
        overdue_receivable: sum(recOverdue.data),
        total_payable: sum(payRes.data),
        overdue_payable: sum(payOverdue.data),
        collected_this_month: sum(collectedRes.data),
        paid_this_month: sum(paidRes.data),
      };
    },
  });
}

export function useCashFlow(months: number = 6) {
  return useQuery({
    queryKey: ['cash-flow', months],
    queryFn: async () => {
      const now = new Date();
      const start = new Date(now.getFullYear(), now.getMonth() - months + 1, 1);
      const startStr = start.toISOString().split('T')[0];

      const { data } = await supabase
        .from('payments').select('payment_date, amount, receivable_id, payable_id')
        .eq('status', 'confirmed')
        .gte('payment_date', startStr).order('payment_date');

      const monthMap: Record<string, { inflow: number; outflow: number }> = {};
      for (let i = 0; i < months; i++) {
        const d = new Date(now.getFullYear(), now.getMonth() - months + 1 + i, 1);
        const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
        monthMap[key] = { inflow: 0, outflow: 0 };
      }

      for (const p of data || []) {
        const key = p.payment_date.substring(0, 7);
        if (!monthMap[key]) continue;
        if (p.receivable_id) monthMap[key].inflow += Number(p.amount);
        else monthMap[key].outflow += Number(p.amount);
      }

      const monthNames = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];
      return Object.entries(monthMap).map(([key, v]) => {
        const [y, m] = key.split('-');
        return {
          month: `${monthNames[parseInt(m) - 1]}/${y.slice(2)}`,
          inflow: v.inflow,
          outflow: v.outflow,
          net: v.inflow - v.outflow,
        };
      });
    },
  });
}

export function useBankTransactions() {
  return useQuery({
    queryKey: ['bank-transactions'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('bank_transactions')
        .select('*, service_orders!bank_transactions_reconciled_service_order_id_fkey(service_order_number)')
        .order('transaction_date', { ascending: false });
      if (error) throw error;
      return data;
    },
  });
}

export function useUnignoreBankTransaction() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.from('bank_transactions')
        .update({ reconciled: false, reconciled_payment_id: null, reconciled_service_order_id: null })
        .eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['bank-transactions'] }),
  });
}

export function useImportBankTransactions() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (args: { transactions: BankTransaction[]; source_type?: 'bank' | 'credit_card' }) => {
      const batch_id = crypto.randomUUID();
      const rows = args.transactions.map(t => ({ ...t, import_batch_id: batch_id, reconciled: false, source_type: args.source_type || 'bank' }));
      const { data, error } = await supabase.from('bank_transactions').insert(rows).select();
      if (error) throw error;
      return data;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['bank-transactions'] }),
  });
}

export function useReconcile() {
  const qc = useQueryClient();
  const registerPayment = useRegisterPayment();

  return useMutation({
    mutationFn: async (input: {
      bankTransactionId: string; receivableId?: string; payableId?: string;
      amount: number; paymentMethod?: string;
    }) => {
      // Validate amount against the open balance before registering
      if (input.receivableId || input.payableId) {
        const table = input.receivableId ? 'receivables' : 'payables';
        const parentId = (input.receivableId || input.payableId)!;
        const { data: parent } = await supabase.from(table).select('balance_amount').eq('id', parentId).single();
        const openBalance = Number(parent?.balance_amount || 0);
        if (input.amount > openBalance + 0.005) {
          throw new Error(`Valor R$ ${input.amount.toFixed(2)} excede o saldo em aberto de R$ ${openBalance.toFixed(2)}`);
        }
      }

      const payment = await registerPayment.mutateAsync({
        receivable_id: input.receivableId,
        payable_id: input.payableId,
        payment_date: new Date().toISOString().split('T')[0],
        amount: input.amount,
        payment_method: input.paymentMethod || 'bank_transfer',
      });

      await supabase.from('bank_transactions').update({
        reconciled: true, reconciled_payment_id: payment.id,
      }).eq('id', input.bankTransactionId);

      return payment;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['bank-transactions'] });
      qc.invalidateQueries({ queryKey: ['receivables'] });
      qc.invalidateQueries({ queryKey: ['payables'] });
    },
  });
}

export function useDismissBankTransaction() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.from('bank_transactions')
        .update({ reconciled: true }).eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['bank-transactions'] }),
  });
}

// ─── Aging Report ──────────────────────────────────────────────────────────────

export interface AgingBucket {
  client_id: string;
  client_name: string;
  current: number;    // vence hoje ou no futuro / até 30 dias em atraso
  days_31_60: number;
  days_61_90: number;
  over_90: number;
  total: number;
}

export interface AgingReportData {
  buckets: AgingBucket[];
  totals: { current: number; days_31_60: number; days_61_90: number; over_90: number; total: number };
  generated_at: string;
}

export function useAgingReport() {
  return useQuery({
    queryKey: ['aging-report'],
    queryFn: async (): Promise<AgingReportData> => {
      const today = new Date();
      today.setHours(0, 0, 0, 0);

      const { data, error } = await supabase
        .from('receivables')
        .select('id, amount, balance_amount, due_date, status, client_id, clients!receivables_client_id_fkey(id, name)')
        .in('status', ['pending', 'partially_paid', 'overdue'])
        .gt('balance_amount', 0);
      if (error) throw error;

      const map = new Map<string, AgingBucket>();
      for (const r of data || []) {
        const client = (r as any).clients;
        if (!client) continue;
        const clientId = client.id as string;
        if (!map.has(clientId)) {
          map.set(clientId, {
            client_id: clientId,
            client_name: client.name as string,
            current: 0, days_31_60: 0, days_61_90: 0, over_90: 0, total: 0,
          });
        }
        const bucket = map.get(clientId)!;
        const balance = Number(r.balance_amount || 0);
        const due = new Date(r.due_date);
        due.setHours(0, 0, 0, 0);
        const diffDays = Math.round((today.getTime() - due.getTime()) / 86_400_000);

        bucket.total += balance;
        if (diffDays <= 30)       bucket.current    += balance;
        else if (diffDays <= 60)  bucket.days_31_60 += balance;
        else if (diffDays <= 90)  bucket.days_61_90 += balance;
        else                      bucket.over_90    += balance;
      }

      const buckets = Array.from(map.values()).sort((a, b) => b.over_90 - a.over_90);
      const totals = buckets.reduce(
        (acc, b) => ({
          current:    acc.current    + b.current,
          days_31_60: acc.days_31_60 + b.days_31_60,
          days_61_90: acc.days_61_90 + b.days_61_90,
          over_90:    acc.over_90    + b.over_90,
          total:      acc.total      + b.total,
        }),
        { current: 0, days_31_60: 0, days_61_90: 0, over_90: 0, total: 0 },
      );

      return { buckets, totals, generated_at: new Date().toISOString() };
    },
    staleTime: 5 * 60 * 1000,
  });
}

// ─── Hooks por OS ─────────────────────────────────────────────────────────────

/** Todos os recebíveis não-cancelados de uma OS específica. */
export function useReceivablesByServiceOrder(serviceOrderId?: string) {
  return useQuery({
    queryKey: ['receivables', 'by-so', serviceOrderId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('receivables')
        .select('id, amount, paid_amount, balance_amount, status, due_date, description, is_deposit')
        .eq('service_order_id', serviceOrderId!)
        .neq('status', 'cancelled')
        .order('due_date', { ascending: true });
      if (error) throw error;
      return data ?? [];
    },
    enabled: !!serviceOrderId,
  });
}

/** Histórico de pagamentos confirmados de uma OS (via seus recebíveis). */
export function usePaymentsByServiceOrder(serviceOrderId?: string) {
  return useQuery({
    queryKey: ['payments', 'by-so', serviceOrderId],
    queryFn: async () => {
      // Busca IDs dos recebíveis da OS
      const { data: recs, error: recErr } = await supabase
        .from('receivables')
        .select('id')
        .eq('service_order_id', serviceOrderId!)
        .neq('status', 'cancelled');
      if (recErr) throw recErr;
      if (!recs || recs.length === 0) return [];

      const recIds = recs.map((r) => r.id);
      const { data: payments, error: payErr } = await supabase
        .from('payments')
        .select('id, payment_date, amount, payment_method, installments, net_amount, notes, status')
        .in('receivable_id', recIds)
        .eq('status', 'confirmed')
        .order('payment_date', { ascending: false });
      if (payErr) throw payErr;
      return payments ?? [];
    },
    enabled: !!serviceOrderId,
  });
}
