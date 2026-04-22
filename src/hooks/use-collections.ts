import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { normalizePhoneE164 } from '@/lib/masks';

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
  contact_phone: string | null;
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
  client?: { id: string; full_name_or_company_name: string; whatsapp: string | null; phone: string | null } | null;
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

export function useCollections(filters: CollectionFilters = {}) {
  const qc = useQueryClient();
  return useQuery({
    queryKey: ['collections', filters],
    queryFn: async () => {
      // Auto-mark overdue first
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

      let q = supabase
        .from('collections')
        .select(`
          *,
          client:clients ( id, full_name_or_company_name, whatsapp, phone ),
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
          (c.client?.full_name_or_company_name || '').toLowerCase().includes(s) ||
          (c.service_order?.service_order_number || '').toLowerCase().includes(s) ||
          (c.description || '').toLowerCase().includes(s)
        );
      }

      if (filters.sort_by === 'client') {
        const dir = filters.sort_dir === 'desc' ? -1 : 1;
        list = [...list].sort((a, b) =>
          dir * (a.client?.full_name_or_company_name || '')
            .localeCompare(b.client?.full_name_or_company_name || ''));
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

      // Invalidate related cache if we updated overdues
      if (stale && stale.length > 0) {
        qc.invalidateQueries({ queryKey: ['collection'] });
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
      await supabase.from('collection_contacts').insert({
        collection_id: input.id,
        contact_type: 'paid',
        notes: input.notes || `Pago via ${input.paid_method}`,
      } as never);
      return true;
    },
    onSuccess: (_, vars) => {
      qc.invalidateQueries({ queryKey: ['collections'] });
      qc.invalidateQueries({ queryKey: ['collection', vars.id] });
      qc.invalidateQueries({ queryKey: ['collection-contacts', vars.id] });
      toast.success('Cobrança marcada como paga');
    },
    onError: (e: any) => toast.error(e.message || 'Erro ao confirmar pagamento'),
  });
}

// ----- Z-API send -----
function fmtBRL(v: number) {
  return v.toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}
function fmtDateBR(iso: string) {
  const [y, m, d] = iso.split('T')[0].split('-');
  return `${d}/${m}/${y}`;
}

export function renderTemplate(
  body: string,
  ctx: { nome: string; numero_os: string; valor: number; vencimento: string; pix: string; empresa: string },
) {
  // Aceita {chave} e {{chave}} (retro-compatível) e expõe aliases amigáveis
  // (cliente, os) iguais aos usados em SendViaZAPIDialog/TEMPLATE_VARIABLES.
  const replacements: Record<string, string> = {
    nome: ctx.nome,
    numero_os: ctx.numero_os,
    valor: fmtBRL(ctx.valor),
    vencimento: fmtDateBR(ctx.vencimento),
    pix: ctx.pix,
    empresa: ctx.empresa,
    cliente: ctx.nome,
    os: ctx.numero_os,
  };
  const sub = (key: string) =>
    replacements[key] !== undefined ? replacements[key] : `{${key}}`;
  return body
    .replace(/\{\{\s*(\w+)\s*\}\}/g, (_m, key) => sub(key))
    .replace(/\{(\w+)\}/g, (_m, key) => sub(key));
}

async function getAppSettings() {
  const { data } = await supabase.from('app_settings').select('key, value');
  const map: Record<string, string> = {};
  for (const r of data || []) if (r.key) map[r.key] = String(r.value || '');
  return map;
}

async function invokeWhatsAppSend(body: Record<string, unknown>) {
  const { data, error } = await supabase.functions.invoke('whatsapp-send', { body });
  if (error) throw new Error(error.message || 'Falha no envio');
  if ((data as any)?.error) throw new Error((data as any).error);
  return data;
}

export function useSendCollectionWhatsApp() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: {
      collection: Collection;
      template?: CollectionTemplate;
      overrideMethod?: CollectionSendMethod;
      pdfUrl?: string;
      pdfFilename?: string;
      paymentMethod?: string;
      cardInstallments?: number;
    }) => {
      const c = input.collection;
      const phoneRaw = c.contact_whatsapp || c.contact_phone || c.client?.whatsapp || c.client?.phone || '';
      const phone = normalizePhoneE164(phoneRaw, '55');
      if (!phone || phone.length < 10) throw new Error('Telefone inválido');

      const settings = await getAppSettings();

      // Resolve payment method: explicit override > linked OS lookup
      let paymentMethod = input.paymentMethod;
      let cardInstallments = input.cardInstallments;
      if (!paymentMethod && c.service_order_id) {
        const { data: so } = await supabase
          .from('service_orders')
          .select('payment_method, card_installments')
          .eq('id', c.service_order_id)
          .maybeSingle();
        paymentMethod = (so as any)?.payment_method || undefined;
        cardInstallments = (so as any)?.card_installments || undefined;
      }

      const body = c.message_template || input.template?.body
        || 'Olá, {{nome}}! Lembrete da fatura {{numero_os}} de R$ {{valor}} venc. {{vencimento}}.';

      const { buildCollectionMessage } = await import('@/lib/collection-message');
      const message = buildCollectionMessage({
        template: body,
        renderTemplate,
        collection: c,
        paymentMethod,
        cardInstallments,
        settings,
      });

      const method = input.overrideMethod || c.send_method || 'text_link';
      const tryOrder: CollectionSendMethod[] = method === 'pdf'
        ? ['pdf', 'text_link', 'text']
        : method === 'text_link' ? ['text_link', 'text'] : ['text'];

      let lastErr: any = null;
      for (const m of tryOrder) {
        try {
          if (m === 'pdf' && input.pdfUrl) {
            await invokeWhatsAppSend({
              phone,
              message,
              context: 'billing',
              kind: 'document',
              document_url: input.pdfUrl,
              document_filename: input.pdfFilename || 'cobranca.pdf',
              document_caption: message,
            });
          } else if (m === 'text_link') {
            await invokeWhatsAppSend({
              phone,
              message,
              context: 'billing',
              kind: 'text',
            });
          } else {
            await invokeWhatsAppSend({ phone, message, context: 'billing', kind: 'text' });
          }
          // success
          await supabase.from('collection_contacts').insert({
            collection_id: c.id,
            contact_type: 'whatsapp_sent',
            notes: `Enviado via ${m}`,
          } as never);
          await supabase.from('collections').update({
            status: c.status === 'paid' ? 'paid' : 'sent',
          } as never).eq('id', c.id);
          return { success: true, method: m };
        } catch (err) {
          lastErr = err;
        }
      }
      throw lastErr || new Error('Falha no envio');
    },
    onSuccess: (_, vars) => {
      qc.invalidateQueries({ queryKey: ['collections'] });
      qc.invalidateQueries({ queryKey: ['collection', vars.collection.id] });
      qc.invalidateQueries({ queryKey: ['collection-contacts', vars.collection.id] });
      toast.success('Cobrança enviada por WhatsApp');
    },
    onError: (e: any) => toast.error(e.message || 'Falha no envio'),
  });
}
