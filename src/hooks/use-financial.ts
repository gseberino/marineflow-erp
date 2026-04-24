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
        .select('*, clients!receivables_client_id_fkey(id,full_name_or_company_name,whatsapp,phone), service_orders!receivables_service_order_id_fkey(id,service_order_number,share_token)')
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
        .select('*, suppliers!payables_supplier_id_fkey(supplier_name), service_orders!payables_linked_service_order_id_fkey(service_order_number), service_order_expenses!service_order_expenses_linked_payable_id_fkey(receipt_url)')
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
      supplier_id?: string; supplier_name?: string;
      linked_service_order_id?: string; notes?: string;
      origin?: string; bank_transaction_id?: string;
    }) => {
      const { data, error } = await supabase.from('payables').insert({
        ...p, balance_amount: p.amount, paid_amount: 0, status: 'pending',
      }).select().single();
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
      const { data: payment, error: pErr } = await supabase
        .from('payments').insert({ ...input, status: 'confirmed' }).select().single();
      if (pErr) throw pErr;

      // Recalc parent
      const table = input.receivable_id ? 'receivables' : 'payables';
      const parentId = input.receivable_id || input.payable_id!;
      const fk = input.receivable_id ? 'receivable_id' : 'payable_id';

      const { data: payments } = await supabase
        .from('payments').select('amount').eq(fk, parentId).eq('status', 'confirmed');
      const totalPaid = (payments || []).reduce((s, p) => s + Number(p.amount), 0);

      const { data: parent } = await supabase
        .from(table).select('amount').eq('id', parentId).single();
      const originalAmount = Number(parent?.amount || 0);
      const balance = Math.max(0, originalAmount - totalPaid);
      const status = totalPaid >= originalAmount ? 'paid' : totalPaid > 0 ? 'partially_paid' : 'pending';

      await supabase.from(table).update({
        paid_amount: totalPaid, balance_amount: balance, status,
      }).eq('id', parentId);

      await writeAuditLog({
        table_name: 'payments',
        record_id: payment.id,
        action: 'update',
        new_value: { amount: input.amount, payment_method: input.payment_method },
      });

      return payment;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['receivables'] });
      qc.invalidateQueries({ queryKey: ['payables'] });
      qc.invalidateQueries({ queryKey: ['payments'] });
      qc.invalidateQueries({ queryKey: ['financial-summary'] });
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
