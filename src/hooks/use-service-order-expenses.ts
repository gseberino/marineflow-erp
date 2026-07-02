import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { computeCardFeeAmount } from '@/hooks/use-service-orders';

async function recalcExpenseTotals(soId: string) {
  const { data: expenses } = await supabase
    .from('service_order_expenses')
    .select('amount, billable_to_client')
    .eq('service_order_id', soId);
  // Só despesas faturáveis entram no custo repassado ao cliente (Onda 1D).
  // Despesas internas continuam salvas na tabela para controle de margem/reembolso.
  const opCost = (expenses || [])
    .filter((e) => e.billable_to_client !== false)
    .reduce((s, e) => s + Number(e.amount), 0);

  const { data: so } = await supabase
    .from('service_orders')
    .select('labor_cost_total, parts_cost_total, travel_cost_total, is_travel_billable, subcontract_cost_total, discount_amount, tax_amount, card_fee_passthrough_enabled, card_installments')
    .eq('id', soId)
    .single();

  const travelCost = so?.is_travel_billable !== false ? (so?.travel_cost_total || 0) : 0;

  const base =
    (so?.labor_cost_total || 0) +
    (so?.parts_cost_total || 0) +
    travelCost +
    opCost +
    (so?.subcontract_cost_total || 0) -
    (so?.discount_amount || 0) +
    (so?.tax_amount || 0);

  // Onda 1C: repasse da taxa de cartão ao cliente, aplicado por cima do valor já ajustado.
  const cardFeeAmount = await computeCardFeeAmount(base, so?.card_fee_passthrough_enabled, so?.card_installments);
  const grand = base + cardFeeAmount;

  await supabase.from('service_orders').update({
    operational_cost_total: Math.round(opCost * 100) / 100,
    card_fee_amount: cardFeeAmount,
    grand_total: Math.round(grand * 100) / 100,
  }).eq('id', soId);
}

export function useServiceOrderExpenses(serviceOrderId: string | undefined) {
  return useQuery({
    queryKey: ['so-expenses', serviceOrderId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('service_order_expenses')
        .select('*, app_users!service_order_expenses_technician_user_id_fkey(full_name), suppliers!service_order_expenses_supplier_id_fkey(name)')
        .eq('service_order_id', serviceOrderId!)
        .order('expense_date', { ascending: true });
      if (error) throw error;
      return data;
    },
    enabled: !!serviceOrderId,
  });
}

export function useAddServiceOrderExpense() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (expense: {
      service_order_id: string;
      category: string;
      description: string;
      amount: number;
      currency?: string;
      expense_date: string;
      paid_by: 'company' | 'technician';
      technician_user_id?: string;
      receipt_url?: string;
      receipt_storage_path?: string;
      supplier_id?: string;
      notes?: string;
      also_create_payable?: boolean;
      billable_to_client?: boolean;
    }) => {
      const { also_create_payable, ...insertData } = expense;

      const { data: inserted, error } = await supabase
        .from('service_order_expenses')
        .insert(insertData)
        .select()
        .single();
      if (error) throw error;

      if (also_create_payable) {
        const { data: payable } = await supabase.from('payables').insert({
          description: expense.description,
          expense_category: expense.category,
          amount: expense.amount,
          currency: expense.currency || 'BRL',
          issue_date: expense.expense_date,
          due_date: expense.expense_date,
          linked_service_order_id: expense.service_order_id,
          status: 'pending',
          balance_amount: expense.amount,
          paid_amount: 0,
          origin: 'service_order_expense',
        }).select().single();

        if (payable) {
          await supabase.from('service_order_expenses')
            .update({ linked_payable_id: payable.id })
            .eq('id', inserted.id);
        }
      }

      await recalcExpenseTotals(expense.service_order_id);
      return inserted;
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['so-expenses', vars.service_order_id] });
      qc.invalidateQueries({ queryKey: ['service-orders', vars.service_order_id] });
      qc.invalidateQueries({ queryKey: ['payables'] });
    },
  });
}

export function useUpdateServiceOrderExpense() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({
      id,
      service_order_id,
      ...updates
    }: {
      id: string;
      service_order_id: string;
      category?: string;
      description?: string;
      amount?: number;
      currency?: string;
      expense_date?: string;
      paid_by?: string;
      technician_user_id?: string | null;
      receipt_url?: string | null;
      receipt_storage_path?: string | null;
      supplier_id?: string | null;
      notes?: string | null;
      billable_to_client?: boolean;
    }) => {
      const { data, error } = await supabase
        .from('service_order_expenses')
        .update(updates)
        .eq('id', id)
        .select()
        .single();
      if (error) throw error;
      await recalcExpenseTotals(service_order_id);
      return data;
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['so-expenses', vars.service_order_id] });
      qc.invalidateQueries({ queryKey: ['service-orders', vars.service_order_id] });
    },
    onError: (error: any) => {
      console.error('useUpdateServiceOrderExpense error:', error);
    },
  });
}

export function useRemoveServiceOrderExpense() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, service_order_id }: { id: string; service_order_id: string }) => {
      const { error } = await supabase
        .from('service_order_expenses')
        .delete()
        .eq('id', id);
      if (error) throw error;
      await recalcExpenseTotals(service_order_id);
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['so-expenses', vars.service_order_id] });
      qc.invalidateQueries({ queryKey: ['service-orders', vars.service_order_id] });
    },
  });
}

export function useMarkExpenseReimbursed() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ expenseId, paymentId }: { expenseId: string; paymentId?: string }) => {
      const { error } = await supabase.from('service_order_expenses').update({
        reimbursed: true,
        reimbursed_at: new Date().toISOString(),
        reimbursed_payment_id: paymentId || null,
      }).eq('id', expenseId);
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['so-expenses'] });
      qc.invalidateQueries({ queryKey: ['pending-reimbursements'] });
    },
  });
}

export function usePendingReimbursements() {
  return useQuery({
    queryKey: ['pending-reimbursements'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('service_order_expenses')
        .select('*, app_users!service_order_expenses_technician_user_id_fkey(full_name), service_orders!service_order_expenses_service_order_id_fkey(service_order_number)')
        .eq('paid_by', 'technician')
        .eq('reimbursed', false)
        .order('expense_date', { ascending: true });
      if (error) throw error;
      return data;
    },
  });
}
