import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { writeAuditLog } from '@/hooks/use-audit-log';
import { cancelServiceOrderCascade, reopenServiceOrder, updateReceivableFromSO } from '@/lib/cascade-updates';

const SO_SELECT = `
  *,
  clients(name, phone, whatsapp),
  vessels(name, manufacturer, model),
  marinas(name, latitude, longitude),
  service_order_technicians(user_id)
`;

const SO_DETAIL_SELECT = `
  *,
  clients(name, phone, whatsapp, email),
  vessels(name, manufacturer, model, current_dock_position),
  marinas(name, latitude, longitude),
  service_order_parts(*, products(*)),
  service_order_services(*, services(name)),
  service_order_technicians(*, app_users(*)),
  time_entries(*, app_users(*)),
  payment_condition_presets(*)
`;

export function useServiceOrders() {
  return useQuery({
    queryKey: ['service-orders'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('service_orders')
        .select(SO_SELECT)
        .order('created_at', { ascending: false });
      if (error) throw error;
      return data;
    },
    staleTime: 30 * 1000,
  });
}

export function useServiceOrder(id: string | undefined) {
  return useQuery({
    queryKey: ['service-orders', id],
    queryFn: async () => {
      if (!id) return null;
      const { data, error } = await supabase
        .from('service_orders')
        .select(SO_DETAIL_SELECT)
        .eq('id', id)
        .maybeSingle();
      if (error) throw error;
      return data;
    },
    enabled: !!id,
    staleTime: 30 * 1000,
  });
}

/**
 * Unified document number generator backed by a PostgreSQL sequence.
 * nextval('document_number_seq') is atomic — safe under concurrent inserts.
 * Prefix: 'ORÇ' for quotes (drafts), 'OS' for orders.
 */
async function nextDocumentNumber(prefix: 'ORÇ' | 'OS'): Promise<string> {
  const { data, error } = await supabase.rpc('next_document_number');
  if (error) throw new Error(`Erro ao gerar número de documento: ${error.message}`);
  return `${prefix}-${String(data as number).padStart(5, '0')}`;
}

// Convenience aliases kept for call-site readability
const generateQuoteNumber = () => nextDocumentNumber('ORÇ');
const generateSONumber = () => nextDocumentNumber('OS');

export function useCreateServiceOrder() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (values: Record<string, any>) => {
      // New records always start as orçamentos (ORÇ-XXXXX).
      // They get an OS-XXXXX number at the moment they graduate from draft
      // via useUpdateServiceOrderStatus (first transition out of 'draft').
      const soNumber = await generateQuoteNumber();
      const payload = { ...values, service_order_number: soNumber };
      const { data, error } = await supabase
        .from('service_orders')
        .insert(payload as any)
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['service-orders'] });
    },
  });
}

export function useUpdateServiceOrder() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, ...values }: { id: string } & Record<string, any>) => {
      // Get previous values for audit
      const { data: prev } = await supabase
        .from('service_orders')
        .select('grand_total, status')
        .eq('id', id)
        .single();

      const { data, error } = await supabase
        .from('service_orders')
        .update(values as any)
        .eq('id', id)
        .select()
        .single();
      if (error) throw error;

      // Always recompute grand_total from the DB after saving.
      // This ensures discount, tax, travel and all line items are reflected
      // correctly in the stored value — used by PDFs, receivables, and reports.
      await recalcTotals(id);

      // Re-read the freshly computed grand_total for cascade logic
      const { data: refreshed } = await supabase
        .from('service_orders')
        .select('grand_total')
        .eq('id', id)
        .single();

      const newGrandTotal = Number(refreshed?.grand_total ?? data.grand_total);

      // Cascade update receivable if grand_total changed
      if (prev && newGrandTotal !== Number(prev.grand_total)) {
        await updateReceivableFromSO(id, newGrandTotal);
      }

      await writeAuditLog({
        table_name: 'service_orders',
        record_id: id,
        action: 'update',
        previous_value: prev,
        new_value: values,
      });

      return data;
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['service-orders'] });
      qc.invalidateQueries({ queryKey: ['service-orders', vars.id] });
      qc.invalidateQueries({ queryKey: ['pdf-data', vars.id] });
      qc.invalidateQueries({ queryKey: ['receivables'] });
      if (vars?.status === 'completed') {
        qc.invalidateQueries({ queryKey: ['products'] });
        qc.invalidateQueries({ queryKey: ['inventory'] });
      }
    },
  });
}

export function useUpdateServiceOrderStatus() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, status }: { id: string; status: string }) => {
      if (status === 'cancelled') {
        throw new Error('Use o botão "Cancelar OS" para cancelar com estorno completo.');
      }

      const updates: Record<string, any> = { status };

      // On first transition out of draft: mark conversion + swap prefix ORÇ→OS
      if (status !== 'draft') {
        const { data: current } = await supabase
          .from('service_orders')
          .select('status, converted_to_os_at, service_order_number, grand_total, original_quote_amount')
          .eq('id', id)
          .single();
        if (current?.status === 'draft' && !current?.converted_to_os_at) {
          updates.converted_to_os_at = new Date().toISOString();
          // Preserva o grand_total do orçamento aprovado para comparação futura (valor orçado vs realizado)
          if (!current?.original_quote_amount && current?.grand_total) {
            updates.original_quote_amount = current.grand_total;
          }
          // Keep the same sequence number — only swap the prefix.
          // ORÇ-00042 → OS-00042 (unified sequence: quote and OS share the counter).
          const currentNum = current.service_order_number ?? '';
          updates.service_order_number = currentNum.startsWith('ORÇ-')
            ? currentNum.replace('ORÇ-', 'OS-')
            : currentNum; // already has OS- prefix (legacy records)
        }
      }

      if (status === 'in_progress') {
        const { data: current } = await supabase
          .from('service_orders')
          .select('check_in_at')
          .eq('id', id)
          .single();
        if (!current?.check_in_at) updates.check_in_at = new Date().toISOString();
      }
      if (status === 'completed') {
        const { data: current } = await supabase
          .from('service_orders')
          .select('check_out_at, grand_total, client_id, service_order_number, vessel_id')
          .eq('id', id)
          .single();
        if (!current?.check_out_at) updates.check_out_at = new Date().toISOString();
        // Auto-generate receivable (only if none exists yet for this SO)
        if (current) {
          const { data: existingRec } = await supabase
            .from('receivables')
            .select('id')
            .eq('service_order_id', id)
            .neq('status', 'cancelled')
            .maybeSingle();

          if (!existingRec) {
            const { data: vessel } = await supabase
              .from('vessels')
              .select('name')
              .eq('id', current.vessel_id)
              .single();
            const today = new Date().toISOString().slice(0, 10);
            const due = new Date(Date.now() + 30 * 86400000).toISOString().slice(0, 10);
            await supabase.from('receivables').insert({
              client_id: current.client_id,
              service_order_id: id,
              description: `OS ${current.service_order_number} - ${vessel?.name || ''}`,
              issue_date: today,
              due_date: due,
              amount: current.grand_total || 0,
              balance_amount: current.grand_total || 0,
              status: 'pending',
            });
          }
        }
      }
      const { data, error } = await supabase
        .from('service_orders')
        .update(updates as any)
        .eq('id', id)
        .select()
        .single();
      if (error) throw error;

      await writeAuditLog({
        table_name: 'service_orders',
        record_id: id,
        action: 'update',
        new_value: { status },
      });

      return data;
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['service-orders'] });
      qc.invalidateQueries({ queryKey: ['service-orders', vars.id] });
      qc.invalidateQueries({ queryKey: ['receivables'] });
    },
  });
}

export function useCancelServiceOrder() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, reason }: { id: string; reason: string }) => {
      return await cancelServiceOrderCascade(id, reason);
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['service-orders'] });
      qc.invalidateQueries({ queryKey: ['receivables'] });
      qc.invalidateQueries({ queryKey: ['payables'] });
      qc.invalidateQueries({ queryKey: ['products'] });
      qc.invalidateQueries({ queryKey: ['payments'] });
      qc.invalidateQueries({ queryKey: ['bank-transactions'] });
    },
  });
}

export function useReopenServiceOrder() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, reason }: { id: string; reason: string }) => {
      await reopenServiceOrder(id, reason);
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['service-orders'] });
      qc.invalidateQueries({ queryKey: ['receivables'] });
      qc.invalidateQueries({ queryKey: ['payments'] });
      qc.invalidateQueries({ queryKey: ['bank-transactions'] });
    },
  });
}

// Parts
export function useServiceOrderParts(serviceOrderId: string | undefined) {
  return useQuery({
    queryKey: ['so-parts', serviceOrderId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('service_order_parts')
        .select('*, products(*)')
        .eq('service_order_id', serviceOrderId!)
        .order('created_at', { ascending: true });
      if (error) throw error;
      return data;
    },
    enabled: !!serviceOrderId,
  });
}

export async function recalcTotals(soId: string) {
  const { data: parts } = await supabase
    .from('service_order_parts')
    .select('line_total_sale')
    .eq('service_order_id', soId);
  const partsCost = (parts || []).reduce((s, p) => s + (p.line_total_sale || 0), 0);

  const { data: serviceLines } = await supabase
    .from('service_order_services')
    .select('line_total')
    .eq('service_order_id', soId);
  const laborCost = (serviceLines || []).reduce((s, l) => s + (l.line_total || 0), 0);

  const { data: te } = await supabase
    .from('time_entries')
    .select('duration_minutes, billable')
    .eq('service_order_id', soId);
  const { data: so } = await supabase
    .from('service_orders')
    .select('travel_cost_total, subcontract_cost_total, discount_amount, tax_amount, operational_cost_total')
    .eq('id', soId)
    .single();

  const billableMinutes = (te || [])
    .filter((e) => e.billable)
    .reduce((s, e) => s + (e.duration_minutes || 0), 0);
  const laborHours = Math.round((billableMinutes / 60) * 100) / 100;

  const grand =
    laborCost +
    partsCost +
    (so?.travel_cost_total || 0) +
    (so?.operational_cost_total || 0) +
    (so?.subcontract_cost_total || 0) -
    (so?.discount_amount || 0) +
    (so?.tax_amount || 0);

  await supabase.from('service_orders').update({
    parts_cost_total: partsCost,
    labor_hours_total: laborHours,
    labor_cost_total: Math.round(laborCost * 100) / 100,
    grand_total: Math.round(grand * 100) / 100,
  }).eq('id', soId);
}

export function useAddServiceOrderPart() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (values: {
      service_order_id: string;
      product_id: string;
      quantity: number;
      unit_cost_snapshot: number;
      unit_sale_snapshot: number;
      notes?: string;
    }) => {
      const line_total_cost = values.quantity * values.unit_cost_snapshot;
      const line_total_sale = values.quantity * values.unit_sale_snapshot;
      const { error } = await supabase.from('service_order_parts').insert({
        ...values,
        line_total_cost,
        line_total_sale,
      });
      if (error) throw error;

      const { data: prod } = await supabase
        .from('products')
        .select('stock_quantity')
        .eq('id', values.product_id)
        .single();
      await supabase
        .from('products')
        .update({ stock_quantity: (prod?.stock_quantity || 0) - values.quantity })
        .eq('id', values.product_id);

      await supabase.from('inventory_movements').insert({
        product_id: values.product_id,
        movement_type: 'service_order_usage',
        quantity_delta: -values.quantity,
        reference_type: 'service_order',
        reference_id: values.service_order_id,
        unit_cost_snapshot: values.unit_cost_snapshot,
      });

      await recalcTotals(values.service_order_id);
      const { data: updatedSO } = await supabase
        .from('service_orders').select('grand_total').eq('id', values.service_order_id).single();
      await updateReceivableFromSO(values.service_order_id, updatedSO?.grand_total || 0);
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['so-parts', vars.service_order_id] });
      qc.invalidateQueries({ queryKey: ['service-orders', vars.service_order_id] });
      qc.invalidateQueries({ queryKey: ['products'] });
      qc.invalidateQueries({ queryKey: ['pdf-data'] });
      qc.invalidateQueries({ queryKey: ['receivables'] });
    },
  });
}

export function useRemoveServiceOrderPart() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (part: {
      id: string;
      service_order_id: string;
      product_id: string;
      quantity: number;
      unit_cost_snapshot: number;
    }) => {
      const { error } = await supabase
        .from('service_order_parts')
        .delete()
        .eq('id', part.id);
      if (error) throw error;

      const { data: prod } = await supabase
        .from('products')
        .select('stock_quantity')
        .eq('id', part.product_id)
        .single();
      await supabase
        .from('products')
        .update({ stock_quantity: (prod?.stock_quantity || 0) + part.quantity })
        .eq('id', part.product_id);

      await supabase.from('inventory_movements').insert({
        product_id: part.product_id,
        movement_type: 'return',
        quantity_delta: part.quantity,
        reference_type: 'service_order',
        reference_id: part.service_order_id,
        unit_cost_snapshot: part.unit_cost_snapshot,
      });

      await writeAuditLog({
        table_name: 'service_order_parts',
        record_id: part.id,
        action: 'reversal',
        previous_value: { product_id: part.product_id, quantity: part.quantity },
        reason: 'Peça removida da OS',
        triggered_by_table: 'service_orders',
        triggered_by_id: part.service_order_id,
      });

      await recalcTotals(part.service_order_id);
      const { data: updatedSO } = await supabase
        .from('service_orders').select('grand_total').eq('id', part.service_order_id).single();
      await updateReceivableFromSO(part.service_order_id, updatedSO?.grand_total || 0);
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['so-parts', vars.service_order_id] });
      qc.invalidateQueries({ queryKey: ['service-orders', vars.service_order_id] });
      qc.invalidateQueries({ queryKey: ['receivables'] });
      qc.invalidateQueries({ queryKey: ['products'] });
      qc.invalidateQueries({ queryKey: ['pdf-data'] });
    },
  });
}

// Time entries
export function useTimeEntries(serviceOrderId: string | undefined) {
  return useQuery({
    queryKey: ['time-entries', serviceOrderId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('time_entries')
        .select('*, app_users!time_entries_technician_user_id_fkey(full_name)')
        .eq('service_order_id', serviceOrderId!)
        .order('started_at', { ascending: true });
      if (error) throw error;
      return data;
    },
    enabled: !!serviceOrderId,
  });
}

export function useAddTimeEntry() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (values: {
      service_order_id: string;
      technician_user_id: string;
      started_at: string;
      ended_at?: string;
      duration_minutes: number;
      billable: boolean;
      notes?: string;
    }) => {
      const { error } = await supabase.from('time_entries').insert(values);
      if (error) throw error;
      await recalcTotals(values.service_order_id);
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['time-entries', vars.service_order_id] });
      qc.invalidateQueries({ queryKey: ['service-orders', vars.service_order_id] });
    },
  });
}

export function useRemoveTimeEntry() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, service_order_id }: { id: string; service_order_id: string }) => {
      const { error } = await supabase.from('time_entries').delete().eq('id', id);
      if (error) throw error;
      await recalcTotals(service_order_id);
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['time-entries', vars.service_order_id] });
      qc.invalidateQueries({ queryKey: ['service-orders', vars.service_order_id] });
    },
  });
}


// Status transitions — OS lifecycle (forward / normal flow)
export const STATUS_TRANSITIONS: Record<string, string[]> = {
  draft:            ['approved', 'scheduled', 'open', 'cancelled'],
  scheduled:        ['open', 'in_progress', 'cancelled'],
  open:             ['in_progress', 'awaiting_parts', 'awaiting_client', 'cancelled'],
  in_progress:      ['awaiting_parts', 'awaiting_client', 'completed', 'cancelled'],
  awaiting_parts:   ['in_progress', 'cancelled'],
  awaiting_client:  ['in_progress', 'completed', 'cancelled'],
  approved:         ['scheduled', 'in_progress', 'completed', 'cancelled'],
  completed:        ['invoiced'],
  invoiced:         [],
  cancelled:        [],
};

// Backward corrections — shown in a separate "Corrigir" section.
// Only includes states that make sense to roll back to (not cancelled/invoiced).
export const STATUS_BACKWARD_TRANSITIONS: Record<string, string[]> = {
  scheduled:        ['draft'],
  open:             ['draft', 'scheduled'],
  in_progress:      ['open'],
  awaiting_parts:   ['open'],
  awaiting_client:  ['open'],
  approved:         ['draft'],
  completed:        ['in_progress', 'awaiting_parts', 'awaiting_client'],
};

// Quote status transitions — orçamento lifecycle (while converted_to_os_at IS NULL)
export const QUOTE_STATUS_TRANSITIONS: Record<string, string[]> = {
  draft:             ['sent', 'awaiting_approval', 'rejected'],
  sent:              ['awaiting_approval', 'rejected'],
  awaiting_approval: ['approved', 'rejected'],
  approved:          ['awaiting_deposit', 'rejected'],
  awaiting_deposit:  ['rejected'],
  rejected:          ['draft'],
};

export function useUpdateQuoteStatus() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, quoteStatus }: { id: string; quoteStatus: string }) => {
      const { data, error } = await supabase
        .from('service_orders')
        .update({ quote_status: quoteStatus } as any)
        .eq('id', id)
        .select()
        .single();
      if (error) throw error;
      await writeAuditLog({
        table_name: 'service_orders',
        record_id: id,
        action: 'update',
        new_value: { quote_status: quoteStatus },
      });
      return data;
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['service-orders'] });
      qc.invalidateQueries({ queryKey: ['service-orders', vars.id] });
    },
  });
}

// Service order services (labor lines)
export function useServiceOrderServices(serviceOrderId: string | undefined) {
  return useQuery({
    queryKey: ['so-services', serviceOrderId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('service_order_services')
        .select('*, services(name)')
        .eq('service_order_id', serviceOrderId!)
        .order('created_at', { ascending: true });
      if (error) throw error;
      return data;
    },
    enabled: !!serviceOrderId,
  });
}

export function useAddServiceOrderService() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (values: {
      service_order_id: string;
      service_id?: string;
      name_snapshot: string;
      description_snapshot?: string;
      billing_unit_snapshot: string;
      quantity: number;
      unit_price_snapshot: number;
      notes?: string;
      technician_user_id?: string | null;
    }) => {
      const line_total = Math.round(values.quantity * values.unit_price_snapshot * 100) / 100;
      const { data, error } = await supabase.from('service_order_services').insert({
        ...values,
        line_total,
      } as any).select('id').single();
      if (error) throw error;
      await recalcTotals(values.service_order_id);
      return data;
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['so-services', vars.service_order_id] });
      qc.invalidateQueries({ queryKey: ['service-orders', vars.service_order_id] });
      qc.invalidateQueries({ queryKey: ['pdf-data'] });
    },
  });
}

export function useRemoveServiceOrderService() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, service_order_id }: { id: string; service_order_id: string }) => {
      const { error } = await supabase
        .from('service_order_services')
        .delete()
        .eq('id', id);
      if (error) throw error;
      await recalcTotals(service_order_id);
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['so-services', vars.service_order_id] });
      qc.invalidateQueries({ queryKey: ['service-orders', vars.service_order_id] });
      qc.invalidateQueries({ queryKey: ['pdf-data'] });
    },
  });
}

export function useDuplicateServiceOrder() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({
      sourceId,
      mode = 'quote',
    }: {
      sourceId: string;
      /** 'quote' → cria como Orçamento (status draft, aparece na aba Orçamentos)
       *  'order' → cria como OS aberta (status open, aparece na aba OS) */
      mode?: 'quote' | 'order';
    }) => {
      // 1. Fetch source with all sub-items
      const { data: source, error: soErr } = await supabase
        .from('service_orders')
        .select(`
          *,
          service_order_parts(*),
          service_order_services(*),
          service_order_expenses(*)
        `)
        .eq('id', sourceId)
        .single();
      if (soErr) throw soErr;

      // 2. Strip runtime/financial/signature fields — copy only composition
      const {
        id, created_at, updated_at, service_order_number,
        scheduled_start_at, scheduled_end_at,
        check_in_at, check_out_at,
        client_signature_url, signed_at, signed_by_name, signed_document_hash,
        requires_resignature, resignature_requested_at,
        share_token,
        payment_status, payment_method, payment_condition_preset_id,
        payment_conditions, card_installments,
        invoicing_status, reopen_reason, reopened_at,
        cancellation_reason, cancelled_at,
        grand_total, labor_cost_total, parts_cost_total,
        operational_cost_total, travel_cost_total,
        subcontract_cost_total, labor_hours_total,
        commissioned_user_id, commission_amount,
        converted_to_os_at,
        quote_status,
        service_order_parts, service_order_services, service_order_expenses,
        ...copyFields
      } = source as any;

      const newNumber = mode === 'order'
        ? await generateSONumber()
        : await generateQuoteNumber();

      const { data: newSO, error: createErr } = await supabase
        .from('service_orders')
        .insert({
          ...copyFields,
          service_order_number: newNumber,
          // 'quote' = fica na aba Orçamentos; 'order' = fica na aba OS
          status: mode === 'order' ? 'open' : 'draft',
          quote_status: mode === 'quote' ? 'draft' : null,
          converted_to_os_at: null,
          priority: source.priority || 'normal',
          discount_amount: source.discount_amount || 0,
          tax_amount: source.tax_amount || 0,
        })
        .select()
        .single();
      if (createErr) throw createErr;

      const newId = (newSO as any).id;

      // 3. Copy services
      if (source.service_order_services?.length > 0) {
        const svcs = source.service_order_services.map((s: any) => ({
          service_order_id: newId,
          service_id: s.service_id,
          name_snapshot: s.name_snapshot,
          description_snapshot: s.description_snapshot,
          billing_unit_snapshot: s.billing_unit_snapshot,
          quantity: s.quantity,
          unit_price_snapshot: s.unit_price_snapshot,
          line_total: s.line_total,
          notes: s.notes,
        }));
        await supabase.from('service_order_services').insert(svcs);
      }

      // 4. Copy parts — NOTE: never deduct stock on a duplicate.
      // Stock is only affected when an OS is actually executed (via StockConfirmationDialog).
      if (source.service_order_parts?.length > 0) {
        const parts = source.service_order_parts.map((p: any) => ({
          service_order_id: newId,
          product_id: p.product_id,
          quantity: p.quantity,
          unit_cost_snapshot: p.unit_cost_snapshot,
          unit_sale_snapshot: p.unit_sale_snapshot,
          line_total_cost: p.line_total_cost,
          line_total_sale: p.line_total_sale,
          currency_snapshot: p.currency_snapshot,
          notes: p.notes,
        }));
        await supabase.from('service_order_parts').insert(parts);
      }

      // 5. Copy expenses (no receipts, no payables)
      if (source.service_order_expenses?.length > 0) {
        const exps = source.service_order_expenses.map((e: any) => ({
          service_order_id: newId,
          category: e.category,
          description: e.description,
          amount: e.amount,
          currency: e.currency || 'BRL',
          expense_date: new Date().toISOString().slice(0, 10),
          paid_by: e.paid_by,
          supplier_id: e.supplier_id || null,
          notes: e.notes || null,
        }));
        await supabase.from('service_order_expenses').insert(exps);
      }

      return newSO;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['service-orders'] });
    },
    onError: (error: any) => {
      console.error('useDuplicateServiceOrder error:', error);
    },
  });
}
