import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { normalizeWhatsappPhone, isUsableWhatsappPhone } from '@/lib/ai-whatsapp';

/**
 * Cotações a fornecedores (COT-XXXXX).
 *
 * O módulo nasceu em 21/07/2026 com 7 ferramentas de IA e NENHUMA tela — o dono só
 * conseguia cotar conversando com o agente, e as respostas que chegavam pelo WhatsApp
 * não tinham onde ser registradas. Estes hooks dão ao humano o mesmo poder que o
 * agente já tinha, usando exatamente as mesmas tabelas.
 */

export type QuoteRequestStatus = 'open' | 'closed' | 'cancelled';
export type QuoteResponseSource = 'text' | 'audio' | 'pdf' | 'image' | 'manual';

export interface QuoteRequestItem {
  id: string;
  quote_request_id: string;
  product_id: string | null;
  description: string;
  quantity: number;
  service_order_part_id: string | null;
  service_order_service_id: string | null;
  position: number;
}

export interface QuoteResponse {
  id: string;
  quote_request_id: string;
  supplier_id: string;
  quote_request_item_id: string | null;
  unit_price: number | null;
  lead_time_days: number | null;
  source: QuoteResponseSource;
  source_excerpt: string | null;
  confirmed: boolean;
  created_at: string;
}

export interface QuoteRequest {
  id: string;
  code: string;
  service_order_id: string | null;
  status: QuoteRequestStatus;
  sent_supplier_ids: string[];
  notes: string | null;
  created_at: string;
  updated_at: string;
  closed_at: string | null;
  service_orders?: { service_order_number: string; clients?: { name: string } | null } | null;
  quote_request_items?: QuoteRequestItem[];
  quote_responses?: QuoteResponse[];
}

const LIST_SELECT = `
  id, code, service_order_id, status, sent_supplier_ids, notes,
  created_at, updated_at, closed_at,
  service_orders(service_order_number, clients(name)),
  quote_request_items(id, position, description, quantity, product_id),
  quote_responses(id, supplier_id, quote_request_item_id, unit_price, lead_time_days, confirmed, source)
`;

const DETAIL_SELECT = `
  id, code, service_order_id, status, sent_supplier_ids, notes,
  created_at, updated_at, closed_at,
  service_orders(service_order_number, clients(name)),
  quote_request_items(*),
  quote_responses(*)
`;

/** Mesma numeração não-atômica das ferramentas do agente (operador único). */
async function generateQuoteCode(): Promise<string> {
  const { data } = await supabase
    .from('quote_requests')
    .select('code')
    .order('created_at', { ascending: false })
    .limit(1);
  let seq = 1;
  const last = (data as any)?.[0]?.code;
  if (last) {
    const m = String(last).match(/(\d+)$/);
    if (m) seq = parseInt(m[1], 10) + 1;
  }
  return `COT-${String(seq).padStart(5, '0')}`;
}

// ── Leitura ───────────────────────────────────────────────────────────────────

export function useQuoteRequests(filters?: { status?: string }) {
  return useQuery({
    queryKey: ['quote-requests', filters],
    queryFn: async () => {
      let q = supabase
        .from('quote_requests')
        .select(LIST_SELECT)
        .order('created_at', { ascending: false });
      if (filters?.status && filters.status !== 'all') q = q.eq('status', filters.status);
      const { data, error } = await q;
      if (error) throw error;
      return (data ?? []) as unknown as QuoteRequest[];
    },
    staleTime: 30_000,
  });
}

export function useQuoteRequest(id: string | undefined) {
  return useQuery({
    queryKey: ['quote-requests', id],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('quote_requests')
        .select(DETAIL_SELECT)
        .eq('id', id!)
        .maybeSingle();
      if (error) throw error;
      return data as unknown as QuoteRequest | null;
    },
    enabled: !!id,
  });
}

/** Cotações ligadas a uma OS — alimenta a faixa e a seção "Compras vinculadas". */
export function useSOLinkedQuotes(serviceOrderId: string | undefined) {
  return useQuery({
    queryKey: ['quote-requests', 'by-so', serviceOrderId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('quote_requests')
        .select(LIST_SELECT)
        .eq('service_order_id', serviceOrderId!)
        .order('created_at', { ascending: false });
      if (error) throw error;
      return (data ?? []) as unknown as QuoteRequest[];
    },
    enabled: !!serviceOrderId,
    staleTime: 30_000,
  });
}

// ── Escrita ───────────────────────────────────────────────────────────────────

export interface NewQuoteItem {
  description: string;
  quantity: number;
  product_id?: string | null;
  service_order_part_id?: string | null;
  service_order_service_id?: string | null;
}

export function useCreateQuoteRequest() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (params: {
      items: NewQuoteItem[];
      serviceOrderId?: string | null;
      supplierIds?: string[];
      notes?: string | null;
    }) => {
      if (!params.items.length) throw new Error('Informe ao menos um item para cotar.');
      const code = await generateQuoteCode();
      const { data: req, error } = await supabase
        .from('quote_requests')
        .insert({
          code,
          service_order_id: params.serviceOrderId ?? null,
          sent_supplier_ids: params.supplierIds ?? [],
          notes: params.notes ?? null,
          status: 'open',
        } as any)
        .select()
        .single();
      if (error) throw error;

      // position é o número que o fornecedor vê na mensagem ("1 - R$ 850")
      const rows = params.items.map((it, idx) => ({
        quote_request_id: (req as any).id,
        product_id: it.product_id ?? null,
        description: it.description,
        quantity: it.quantity,
        service_order_part_id: it.service_order_part_id ?? null,
        service_order_service_id: it.service_order_service_id ?? null,
        position: idx + 1,
      }));
      const { error: itemsErr } = await supabase.from('quote_request_items').insert(rows as any);
      if (itemsErr) throw itemsErr;

      return req as any;
    },
    onSuccess: (req) => {
      qc.invalidateQueries({ queryKey: ['quote-requests'] });
      qc.invalidateQueries({ queryKey: ['purchase-needs'] });
      toast.success(`Cotação ${req.code} criada`);
    },
    onError: (e: any) => toast.error(e.message || 'Erro ao criar cotação'),
  });
}

/** Registra (ou corrige) o preço de um item para um fornecedor. */
export function useRecordQuoteResponse() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (params: {
      quoteRequestId: string;
      supplierId: string;
      itemId: string;
      unitPrice: number | null;
      leadTimeDays?: number | null;
      sourceExcerpt?: string | null;
    }) => {
      // Uma resposta por (cotação, fornecedor, item): reenvio de preço CORRIGE,
      // não empilha — senão o comparativo mostraria duas ofertas do mesmo fornecedor.
      const { data: existing } = await supabase
        .from('quote_responses')
        .select('id')
        .eq('quote_request_id', params.quoteRequestId)
        .eq('supplier_id', params.supplierId)
        .eq('quote_request_item_id', params.itemId)
        .maybeSingle();

      const payload = {
        quote_request_id: params.quoteRequestId,
        supplier_id: params.supplierId,
        quote_request_item_id: params.itemId,
        unit_price: params.unitPrice,
        lead_time_days: params.leadTimeDays ?? null,
        source: 'manual' as const,
        source_excerpt: params.sourceExcerpt ?? null,
      };

      if (existing) {
        const { error } = await supabase
          .from('quote_responses')
          .update(payload as any)
          .eq('id', (existing as any).id);
        if (error) throw error;
        return (existing as any).id as string;
      }
      const { data, error } = await supabase
        .from('quote_responses')
        .insert(payload as any)
        .select('id')
        .single();
      if (error) throw error;
      return (data as any).id as string;
    },
    onSuccess: (_d, v) => {
      qc.invalidateQueries({ queryKey: ['quote-requests', v.quoteRequestId] });
      qc.invalidateQueries({ queryKey: ['quote-requests'] });
    },
    onError: (e: any) => toast.error(e.message || 'Erro ao registrar resposta'),
  });
}

/**
 * ENVIA a cotação aos fornecedores consultados — o passo que não existia em tela.
 *
 * Até 03/08/2026 a cotação era criada aqui e o envio só acontecia pela ferramenta do
 * agente. Como `sent_supplier_ids` é preenchido na CRIAÇÃO com quem foi apenas
 * selecionado, o sistema exibia "enviada a 2 fornecedores" para pedidos que nunca
 * saíram: as três cotações de produção ficaram 11 dias assim, e a regra R16/R17
 * cobrava resposta de quem jamais foi perguntado.
 *
 * Vai pela FILA (whatsapp_send_queue), não por envio direto, por dois motivos: o
 * worker já roda a cada minuto com repetição automática, e a mensagem sobrevive ao
 * WhatsApp estar fora do ar — sai sozinha quando voltar, em vez de se perder.
 *
 * A mensagem é idêntica à do agente (`send_supplier_quote_request`) de propósito: o
 * fornecedor não deve receber dois formatos diferentes conforme quem disparou. Por
 * isso `notes` da cotação NÃO vai junto — é anotação interna, e descrever a aplicação
 * confunde quem atende.
 */
export function useSendQuoteRequest() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ quoteRequestId }: { quoteRequestId: string }) => {
      const { data: req, error: reqErr } = await supabase
        .from('quote_requests')
        .select('id, code, sent_supplier_ids')
        .eq('id', quoteRequestId)
        .single();
      if (reqErr) throw reqErr;

      const supplierIds: string[] = ((req as any).sent_supplier_ids ?? []) as string[];
      if (!supplierIds.length) throw new Error('Escolha ao menos um fornecedor antes de enviar.');

      const { data: items, error: itErr } = await supabase
        .from('quote_request_items')
        .select('position, description, quantity')
        .eq('quote_request_id', quoteRequestId)
        .order('position', { ascending: true });
      if (itErr) throw itErr;
      if (!items?.length) throw new Error('Esta cotação não tem itens para enviar.');

      const [{ data: suppliers, error: supErr }, { data: settings }] = await Promise.all([
        supabase.from('suppliers').select('id, name, trade_name, phone, opt_out_whatsapp').in('id', supplierIds),
        supabase.from('app_settings').select('key, value')
          .in('key', ['company_name', 'wa_test_mode', 'wa_test_number', 'zapi_test_mode', 'zapi_test_number']),
      ]);
      if (supErr) throw supErr;

      const cfg = Object.fromEntries((settings || []).map((s: any) => [s.key, s.value]));
      const company = cfg['company_name'] || 'nossa empresa';
      // Mesmo respeito ao modo de teste que o OnMyWayButton: se ligado, tudo vai para
      // o número de teste — senão um teste dispara mensagem a fornecedor de verdade.
      const testMode = (cfg['wa_test_mode'] ?? cfg['zapi_test_mode']) === 'true';
      const testNumber = String(cfg['wa_test_number'] ?? cfg['zapi_test_number'] ?? '').replace(/\D/g, '');
      if (testMode && !testNumber) throw new Error('Modo de teste ativo sem número de teste configurado.');

      const itemLines = (items as any[])
        .map((it, i) => `${it.position ?? i + 1}. ${it.quantity ? `${it.quantity}x ` : ''}${it.description ?? ''}`.trimEnd())
        .join('\n');
      const message =
        `Olá, tudo bem? Aqui é da ${company}.\n` +
        `Gostaríamos de uma cotação (${(req as any).code}):\n${itemLines}\n\n` +
        `Obrigado!`;

      const { data: auth } = await supabase.auth.getUser();
      const enviados: string[] = [];
      const pulados: Array<{ fornecedor: string; motivo: string }> = [];

      for (const sid of supplierIds) {
        const sup = (suppliers || []).find((s: any) => s.id === sid) as any;
        const nome = sup?.trade_name || sup?.name || 'Fornecedor';
        if (!sup) { pulados.push({ fornecedor: nome, motivo: 'não encontrado' }); continue; }
        if (sup.opt_out_whatsapp) { pulados.push({ fornecedor: nome, motivo: 'pediu para não receber' }); continue; }

        const phone = normalizeWhatsappPhone(sup.phone || '');
        if (!isUsableWhatsappPhone(phone)) {
          pulados.push({ fornecedor: nome, motivo: sup.phone ? 'telefone inválido' : 'sem WhatsApp cadastrado' });
          continue;
        }

        const { data: queued, error: qErr } = await supabase
          .from('whatsapp_send_queue')
          .insert({
            phone_normalized: testMode ? testNumber : phone,
            message,
            source: 'quote_request',
            source_ref_id: quoteRequestId,
            priority: 2,
          } as any)
          .select('id')
          .single();
        if (qErr) { pulados.push({ fornecedor: nome, motivo: qErr.message }); continue; }

        const { error: sendErr } = await supabase.from('quote_request_sends').insert({
          quote_request_id: quoteRequestId,
          supplier_id: sid,
          phone_normalized: testMode ? testNumber : phone,
          queue_id: (queued as any).id,
          created_by: auth?.user?.id ?? null,
        } as any);
        if (sendErr) { pulados.push({ fornecedor: nome, motivo: sendErr.message }); continue; }

        enviados.push(nome);
      }

      if (!enviados.length) {
        throw new Error(
          pulados.length
            ? `Nenhum envio saiu. ${pulados.map((p) => `${p.fornecedor}: ${p.motivo}`).join(' · ')}`
            : 'Nenhum envio saiu.',
        );
      }
      return { enviados, pulados, testMode };
    },
    onSuccess: (r, v) => {
      const base = `Cotação enviada para ${r.enviados.length} fornecedor(es)`;
      toast.success(r.testMode ? `${base} — modo de teste, foi para o número de teste` : base);
      if (r.pulados.length) {
        toast.warning(`Não saiu para: ${r.pulados.map((p) => `${p.fornecedor} (${p.motivo})`).join(' · ')}`);
      }
      qc.invalidateQueries({ queryKey: ['quote-requests', v.quoteRequestId] });
      qc.invalidateQueries({ queryKey: ['quote-request-sends', v.quoteRequestId] });
      qc.invalidateQueries({ queryKey: ['quote-requests'] });
    },
    onError: (e: any) => toast.error(e.message || 'Erro ao enviar a cotação'),
  });
}

/** Envios já feitos desta cotação, com o estado real vindo da fila. */
export function useQuoteRequestSends(quoteRequestId: string | undefined) {
  return useQuery({
    queryKey: ['quote-request-sends', quoteRequestId],
    enabled: !!quoteRequestId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('quote_request_sends')
        .select('id, supplier_id, phone_normalized, created_at, queue_id, whatsapp_send_queue(status, failed_reason, sent_at)')
        .eq('quote_request_id', quoteRequestId!)
        .order('created_at', { ascending: false });
      if (error) throw error;
      return (data ?? []) as any[];
    },
    staleTime: 15_000,
  });
}

/** Garante que o fornecedor consta como consultado (quem responde sem ter sido chamado). */
export function useAddQuoteSupplier() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ quoteRequestId, supplierId }: { quoteRequestId: string; supplierId: string }) => {
      const { data: req, error: readErr } = await supabase
        .from('quote_requests')
        .select('sent_supplier_ids')
        .eq('id', quoteRequestId)
        .single();
      if (readErr) throw readErr;
      const current: string[] = ((req as any).sent_supplier_ids ?? []) as string[];
      if (current.includes(supplierId)) return current;
      const next = [...current, supplierId];
      const { error } = await supabase
        .from('quote_requests')
        .update({ sent_supplier_ids: next } as any)
        .eq('id', quoteRequestId);
      if (error) throw error;
      return next;
    },
    onSuccess: (_d, v) => qc.invalidateQueries({ queryKey: ['quote-requests', v.quoteRequestId] }),
    onError: (e: any) => toast.error(e.message || 'Erro ao incluir fornecedor'),
  });
}

/**
 * Devolve o custo cotado ao item do orçamento.
 *
 * A distinção abaixo é deliberada e importa:
 *
 *   • PEÇA do catálogo tem custo e venda separados. Gravar o custo cotado altera a
 *     MARGEM e não altera um centavo do que o cliente paga (recalcTotals soma
 *     line_total_sale, não line_total_cost). É seguro e não pede confirmação.
 *
 *   • MATERIAL AVULSO (serviço sem cadastro) só tem unit_price_snapshot, que é o
 *     preço AO CLIENTE. Gravar o custo do fornecedor ali venderia a peça pelo preço
 *     de compra, sem margem, e mudaria o total do orçamento. Por isso exige
 *     asSalePrice: true — a tela pede confirmação explícita antes.
 */
export function useApplyQuotePrice() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (params: {
      itemId: string;
      unitPrice: number;
      serviceOrderPartId?: string | null;
      serviceOrderServiceId?: string | null;
      serviceOrderId?: string | null;
      /** obrigatório para material avulso: confirma que o valor vira preço de venda */
      asSalePrice?: boolean;
    }) => {
      if (params.serviceOrderPartId) {
        const { data: part, error: readErr } = await supabase
          .from('service_order_parts')
          .select('quantity')
          .eq('id', params.serviceOrderPartId)
          .single();
        if (readErr) throw readErr;
        const qty = Number((part as any).quantity) || 0;
        const { error } = await supabase
          .from('service_order_parts')
          .update({
            unit_cost_snapshot: params.unitPrice,
            line_total_cost: params.unitPrice * qty,
          } as any)
          .eq('id', params.serviceOrderPartId);
        if (error) throw error;
        return { changedSalePrice: false };
      }

      if (params.serviceOrderServiceId) {
        if (!params.asSalePrice) {
          throw new Error(
            'Este item não tem campo de custo separado — o valor entraria como preço ao cliente. Confirme na tela para aplicar.',
          );
        }
        const { data: svc, error: readErr } = await supabase
          .from('service_order_services')
          .select('quantity')
          .eq('id', params.serviceOrderServiceId)
          .single();
        if (readErr) throw readErr;
        const qty = Number((svc as any).quantity) || 0;
        const { error } = await supabase
          .from('service_order_services')
          .update({
            unit_price_snapshot: params.unitPrice,
            line_total: params.unitPrice * qty,
          } as any)
          .eq('id', params.serviceOrderServiceId);
        if (error) throw error;

        // Só aqui o total da OS muda de verdade, então só aqui recalcula.
        if (params.serviceOrderId) {
          const { recalcTotals } = await import('@/hooks/use-service-orders');
          await recalcTotals(params.serviceOrderId);
        }
        return { changedSalePrice: true };
      }

      throw new Error('Este item não veio de um orçamento — não há linha para atualizar.');
    },
    onSuccess: (result, v) => {
      qc.invalidateQueries({ queryKey: ['quote-requests'] });
      qc.invalidateQueries({ queryKey: ['service-orders'] });
      qc.invalidateQueries({ queryKey: ['purchase-needs'] });
      if (v.serviceOrderId) qc.invalidateQueries({ queryKey: ['service-orders', v.serviceOrderId] });
      toast.success(
        result.changedSalePrice
          ? 'Preço aplicado no orçamento (valor ao cliente atualizado)'
          : 'Custo aplicado no orçamento — margem recalculada',
      );
    },
    onError: (e: any) => toast.error(e.message || 'Erro ao aplicar o custo'),
  });
}

export interface BasketChoice {
  itemId: string;
  supplierId: string;
  description: string;
  quantity: number;
  unitPrice: number;
  productId: string | null;
}

/**
 * Gera uma ordem de compra por fornecedor a partir da cesta escolhida.
 * Itens sem produto no catálogo entram pela descrição (purchase_order_items.product_id
 * é opcional justamente para isso).
 */
export function useCreatePOsFromQuote() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (params: {
      quoteRequestId: string;
      quoteCode: string;
      serviceOrderId?: string | null;
      choices: BasketChoice[];
    }) => {
      if (!params.choices.length) throw new Error('Escolha ao menos um item antes de gerar a compra.');

      const bySupplier = new Map<string, BasketChoice[]>();
      for (const c of params.choices) {
        const list = bySupplier.get(c.supplierId) ?? [];
        list.push(c);
        bySupplier.set(c.supplierId, list);
      }

      const { generatePONumber } = await import('@/hooks/use-purchase-orders');
      const created: { id: string; po_number: string }[] = [];

      for (const [supplierId, choices] of bySupplier) {
        const poNumber = await generatePONumber();
        const { data: po, error } = await supabase
          .from('purchase_orders')
          .insert({
            po_number: poNumber,
            supplier_id: supplierId,
            service_order_id: params.serviceOrderId ?? null,
            status: 'draft',
            notes: `Gerada da cotação ${params.quoteCode}`,
          } as any)
          .select('id, po_number')
          .single();
        if (error) throw error;

        const rows = choices.map(c => ({
          purchase_order_id: (po as any).id,
          product_id: c.productId,
          description: c.description,
          quantity: c.quantity,
          unit_cost: c.unitPrice,
        }));
        const { error: itemsErr } = await supabase.from('purchase_order_items').insert(rows as any);
        if (itemsErr) throw itemsErr;

        created.push(po as any);
      }

      // Fecha a cotação: a decisão foi tomada, o documento cumpriu o papel.
      await supabase
        .from('quote_requests')
        .update({ status: 'closed', closed_at: new Date().toISOString() } as any)
        .eq('id', params.quoteRequestId);

      return created;
    },
    onSuccess: (created) => {
      qc.invalidateQueries({ queryKey: ['quote-requests'] });
      qc.invalidateQueries({ queryKey: ['purchase-orders'] });
      qc.invalidateQueries({ queryKey: ['purchase-needs'] });
      const nums = created.map(p => p.po_number).join(', ');
      toast.success(created.length > 1 ? `Ordens de compra criadas: ${nums}` : `Ordem de compra ${nums} criada`);
    },
    onError: (e: any) => toast.error(e.message || 'Erro ao gerar a ordem de compra'),
  });
}

/**
 * Fecha a cotação sem gerar ordem de compra — a compra direta que o dono pediu:
 * fechou no WhatsApp, vai pegar no balcão, a nota entra depois pelo XML.
 */
export function useCloseQuoteRequest() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, cancel = false, note }: { id: string; cancel?: boolean; note?: string }) => {
      const patch: Record<string, any> = {
        status: cancel ? 'cancelled' : 'closed',
        closed_at: new Date().toISOString(),
      };
      if (note) {
        const { data: cur } = await supabase.from('quote_requests').select('notes').eq('id', id).single();
        const prev = (cur as any)?.notes;
        patch.notes = prev ? `${prev}\n${note}` : note;
      }
      const { error } = await supabase.from('quote_requests').update(patch as any).eq('id', id);
      if (error) throw error;
    },
    onSuccess: (_d, v) => {
      qc.invalidateQueries({ queryKey: ['quote-requests'] });
      qc.invalidateQueries({ queryKey: ['purchase-needs'] });
      toast.success(v.cancel ? 'Cotação cancelada' : 'Cotação fechada');
    },
    onError: (e: any) => toast.error(e.message || 'Erro ao fechar a cotação'),
  });
}

export function useReopenQuoteRequest() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase
        .from('quote_requests')
        .update({ status: 'open', closed_at: null } as any)
        .eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['quote-requests'] });
      toast.success('Cotação reaberta');
    },
    onError: (e: any) => toast.error(e.message || 'Erro ao reabrir'),
  });
}

export const QUOTE_STATUS_LABELS: Record<QuoteRequestStatus, string> = {
  open: 'Aberta',
  closed: 'Fechada',
  cancelled: 'Cancelada',
};
