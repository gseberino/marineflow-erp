import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

export type CollectionStatus =
  | 'pending' | 'sent' | 'viewed' | 'paid' | 'overdue' | 'disputed' | 'cancelled';

export type CollectionSendMethod = 'pdf' | 'text' | 'text_link';

export type CollectionContactType =
  | 'whatsapp_sent' | 'whatsapp_delivered' | 'whatsapp_read'
  | 'call_made' | 'call_answered' | 'call_no_answer'
  | 'email_sent' | 'manual_note' | 'payment_promised' | 'paid';

export interface Collection {
  id: string;
  created_at: string;
  updated_at: string;
  service_order_id: string | null;
  receivable_id: string | null;
  description: string | null;
  standalone_amount: number | null;
  client_id: string;
  amount: number;
  due_date: string;
  status: CollectionStatus;
  contact_name: string | null;
  phone: string | null;
  contact_whatsapp: string | null;
  send_method: CollectionSendMethod;
  message_template: string | null;
  paid_at: string | null;
  paid_amount: number | null;
  paid_method: string | null;
  payment_confirmed_by: 'manual' | 'whatsapp' | 'auto';
  auto_rule_enabled: boolean;
  rule_days_before: number;
  rule_days_after: number;
  last_auto_sent_at: string | null;
  created_by: string | null;
  notes: string | null;
  client?: { id: string; name: string; whatsapp: string | null; phone: string | null } | null;
  service_order?: { id: string; service_order_number: string } | null;
  last_contact_at?: string | null;
}

export interface CollectionContact {
  id: string;
  created_at: string;
  collection_id: string;
  contact_type: CollectionContactType;
  notes: string | null;
  promised_date: string | null;
  created_by: string | null;
}

export interface CollectionTemplate {
  id: string;
  created_at: string;
  name: string;
  body: string;
  is_default: boolean;
  send_method: CollectionSendMethod;
}

export interface CollectionFilters {
  status?: string;
  client_id?: string;
  date_from?: string;
  date_to?: string;
  amount_min?: number;
  amount_max?: number;
  sort_by?: 'due_date' | 'amount' | 'client' | 'status' | 'created_at';
  sort_dir?: 'asc' | 'desc';
  search?: string;
}

const todayISO = () => new Date().toISOString().slice(0, 10);

export function useMarkOverdueCollections() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async () => {
      const today = todayISO();
      const { data: stale } = await supabase
        .from('collections')
        .select('id')
        .in('status', ['pending', 'sent', 'viewed'])
        .lt('due_date', today);
      if (stale && stale.length > 0) {
        await supabase
          .from('collections')
          .update({ status: 'overdue' })
          .in('id', stale.map(s => s.id));
      }
      return stale?.length ?? 0;
    },
    onSuccess: (count) => {
      if (count > 0) qc.invalidateQueries({ queryKey: ['collections'] });
    },
  });
}

export function useCollections(filters: CollectionFilters = {}) {
  return useQuery({
    queryKey: ['collections', filters],
    queryFn: async () => {
      let q = supabase
        .from('collections')
        .select(`
          *,
          client:clients ( id, name, whatsapp, phone ),
          service_order:service_orders ( id, service_order_number )
        `);

      if (filters.status && filters.status !== 'all') q = q.eq('status', filters.status);
      if (filters.client_id) q = q.eq('client_id', filters.client_id);
      if (filters.date_from) q = q.gte('due_date', filters.date_from);
      if (filters.date_to) q = q.lte('due_date', filters.date_to);
      if (typeof filters.amount_min === 'number') q = q.gte('amount', filters.amount_min);
      if (typeof filters.amount_max === 'number') q = q.lte('amount', filters.amount_max);

      const sortCol = filters.sort_by === 'client'
        ? 'created_at'
        : (filters.sort_by || 'due_date');
      q = q.order(sortCol, { ascending: filters.sort_dir !== 'desc' });

      const { data, error } = await q;
      if (error) throw error;

      let list = (data || []) as unknown as Collection[];

      if (filters.search) {
        const s = filters.search.toLowerCase();
        list = list.filter(c =>
          (c.client?.name || '').toLowerCase().includes(s) ||
          (c.service_order?.service_order_number || '').toLowerCase().includes(s) ||
          (c.description || '').toLowerCase().includes(s)
        );
      }

      if (filters.sort_by === 'client') {
        const dir = filters.sort_dir === 'desc' ? -1 : 1;
        list = [...list].sort((a, b) =>
          dir * (a.client?.name || '')
            .localeCompare(b.client?.name || ''));
      }

      // Fetch last_contact for each (single grouped query)
      if (list.length > 0) {
        const ids = list.map(c => c.id);
        const { data: contacts } = await supabase
          .from('collection_contacts')
          .select('collection_id, created_at')
          .in('collection_id', ids)
          .order('created_at', { ascending: false });
        const lastByColl: Record<string, string> = {};
        for (const row of contacts || []) {
          if (!lastByColl[row.collection_id]) lastByColl[row.collection_id] = row.created_at;
        }
        list = list.map(c => ({ ...c, last_contact_at: lastByColl[c.id] || null }));
      }

      return list;
    },
  });
}

export function useCollectionsByOS(serviceOrderId: string | undefined) {
  return useQuery({
    queryKey: ['collections-by-os', serviceOrderId],
    enabled: !!serviceOrderId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('collections')
        .select('id, amount, due_date, status, description')
        .eq('service_order_id', serviceOrderId!)
        .neq('status', 'cancelled')
        .order('due_date', { ascending: true });
      if (error) throw error;
      return (data || []) as Array<{
        id: string; amount: number; due_date: string; status: CollectionStatus; description: string | null;
      }>;
    },
  });
}

export function useCollection(id: string | undefined) {
  return useQuery({
    queryKey: ['collection', id],
    enabled: !!id,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('collections')
        .select(`
          *,
          client:clients ( * ),
          service_order:service_orders ( id, service_order_number )
        `)
        .eq('id', id!)
        .maybeSingle();
      if (error) throw error;
      return data as unknown as Collection | null;
    },
  });
}

export function useCollectionContacts(collectionId: string | undefined) {
  return useQuery({
    queryKey: ['collection-contacts', collectionId],
    enabled: !!collectionId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('collection_contacts')
        .select('*')
        .eq('collection_id', collectionId!)
        .order('created_at', { ascending: false });
      if (error) throw error;
      return (data || []) as CollectionContact[];
    },
  });
}

export function useCollectionTemplates() {
  return useQuery({
    queryKey: ['collection-templates'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('collection_templates')
        .select('*')
        .order('is_default', { ascending: false })
        .order('name');
      if (error) throw error;
      return (data || []) as CollectionTemplate[];
    },
  });
}

export function useCreateCollection() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (payload: Partial<Collection>) => {
      const { data, error } = await supabase
        .from('collections')
        .insert(payload as never)
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['collections'] });
      toast.success('Cobrança criada');
    },
    onError: (e: any) => toast.error(e.message || 'Erro ao criar'),
  });
}

export function useUpdateCollection() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, patch }: { id: string; patch: Partial<Collection> }) => {
      const { data, error } = await supabase
        .from('collections')
        .update(patch as never)
        .eq('id', id)
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: (_, vars) => {
      qc.invalidateQueries({ queryKey: ['collections'] });
      qc.invalidateQueries({ queryKey: ['collection', vars.id] });
    },
    onError: (e: any) => toast.error(e.message || 'Erro ao atualizar'),
  });
}

export function useCancelCollection() {
  const update = useUpdateCollection();
  return useMutation({
    mutationFn: async (id: string) => {
      return update.mutateAsync({ id, patch: { status: 'cancelled' } });
    },
    onSuccess: () => toast.success('Cobrança cancelada'),
  });
}

export function useAddCollectionContact() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (payload: {
      collection_id: string;
      contact_type: CollectionContactType;
      notes?: string;
      promised_date?: string | null;
    }) => {
      const { data, error } = await supabase
        .from('collection_contacts')
        .insert(payload as never)
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: (_, vars) => {
      qc.invalidateQueries({ queryKey: ['collection-contacts', vars.collection_id] });
      qc.invalidateQueries({ queryKey: ['collections'] });
      toast.success('Contato registrado');
    },
    onError: (e: any) => toast.error(e.message || 'Erro ao registrar contato'),
  });
}

export function useMarkCollectionPaid() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: {
      id: string;
      paid_amount: number;
      paid_method: string;
      payment_date: string;
      confirmed_by: 'manual' | 'whatsapp';
      notes?: string;
    }) => {
      // A conta a receber ligada à cobrança. Leitura que falha PÁRA: seguir sem ela marcaria a
      // cobrança paga sem registrar o pagamento na conta.
      const { data: col, error: erroLeitura } = await supabase
        .from('collections')
        .select('receivable_id')
        .eq('id', input.id)
        .maybeSingle();
      if (erroLeitura) throw erroLeitura;

      // Primeiro o pagamento na conta (07/10/2026): antes a cobrança era marcada paga e o erro do
      // register_payment_and_update_balance era ignorado — mês fechado, valor acima do saldo ou
      // falta de permissão deixavam a cobrança "paga" e a conta devendo. Agora, se o pagamento
      // não entra, nada muda. (O gatilho trg_sync_collection_from_receivable marca a cobrança
      // quando a conta fica paga; o update abaixo grava forma e quem confirmou.)
      if (col?.receivable_id) {
        // Normaliza p_payment_date para DATE (YYYY-MM-DD) — o RPC espera DATE, não TIMESTAMP.
        const paymentDateOnly = input.payment_date.split('T')[0];
        const { error: erroPagamento } = await supabase.rpc('register_payment_and_update_balance', {
          p_receivable_id:    col.receivable_id,
          p_payable_id:       null,
          p_amount:           input.paid_amount,
          p_payment_date:     paymentDateOnly,
          p_payment_method:   input.paid_method,
          p_installments:     1,
          p_card_fee_percent: 0,
          p_net_amount:       input.paid_amount,
          p_notes:            input.notes || `Confirmado via cobrança`,
        });
        if (erroPagamento) throw erroPagamento;
      }

      const { error } = await supabase
        .from('collections')
        .update({
          status: 'paid',
          paid_amount: input.paid_amount,
          paid_method: input.paid_method,
          paid_at: new Date(input.payment_date).toISOString(),
          payment_confirmed_by: input.confirmed_by,
        } as never)
        .eq('id', input.id);
      if (error) throw error;

      // O registro do contato é histórico: se falhar, o pagamento já entrou — avisa, não desfaz.
      const { error: erroContato } = await supabase.from('collection_contacts').insert({
        collection_id: input.id,
        contact_type: 'paid',
        notes: input.notes || `Pago via ${input.paid_method}`,
      } as never);
      if (erroContato) toast.warning(`Pagamento registrado, mas o histórico de contatos não foi gravado (${erroContato.message}).`);
      return true;
    },
    onSuccess: (_, vars) => {
      qc.invalidateQueries({ queryKey: ['collections'] });
      qc.invalidateQueries({ queryKey: ['collection', vars.id] });
      qc.invalidateQueries({ queryKey: ['collection-contacts', vars.id] });
      // Invalida recebíveis e OS para refletir a sincronização
      qc.invalidateQueries({ queryKey: ['receivables'] });
      qc.invalidateQueries({ queryKey: ['service-orders'] });
      toast.success('Cobrança marcada como paga');
    },
    onError: (e: any) => toast.error(e.message || 'Erro ao confirmar pagamento'),
  });
}

// O envio da cobrança no clique (useSendCollectionWhatsApp) saiu em 26/11/2026 (dono: "1. A"): mandava o valor guardado
// na cobrança, a número que podia ser digitado, sem nenhuma trava. Cobrar pela tela é o CobrarClienteDialog
// (src/components/client/CobrarClienteDialog.tsx), com a conferência da ficha.
