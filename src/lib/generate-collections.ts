import { supabase } from '@/integrations/supabase/client';
import { computeSchedule } from '@/lib/quote-deposit';

interface GenerateInput {
  serviceOrderId: string;
  approvalDate: string; // ISO date YYYY-MM-DD
  trigger: 'signature' | 'status_change' | 'invoice';
}

interface Installment {
  label: string;
  percent: number;
  days_after_approval: number;
}

export async function generateCollectionsFromOS(
  input: GenerateInput
): Promise<{ created: number; skipped: boolean }> {
  // 1. Fetch the service order with client and payment condition
  const { data: so, error: soErr } = await supabase
    .from('service_orders')
    .select(`
      id, grand_total, payment_conditions, client_id, signed_at,
      payment_condition_preset_id,
      clients(id, name, phone, whatsapp)
    `)
    .eq('id', input.serviceOrderId)
    .single();
  if (soErr || !so) throw soErr || new Error('OS não encontrada');

  // 2. Skip if collections already exist (non-cancelled)
  const { data: existing } = await supabase
    .from('collections')
    .select('id')
    .eq('service_order_id', input.serviceOrderId)
    .neq('status', 'cancelled');
  if (existing && existing.length > 0) {
    return { created: 0, skipped: true };
  }

  const total = Number((so as any).grand_total || 0);
  if (total <= 0) return { created: 0, skipped: true };

  // 3. Find payment condition preset
  let installments: Installment[] = [];
  const presetId = (so as any).payment_condition_preset_id;
  if (presetId) {
    const { data: preset } = await supabase
      .from('payment_condition_presets')
      .select('installments, auto_generate_collections')
      .eq('id', presetId)
      .maybeSingle();

    if ((preset as any)?.auto_generate_collections === false) {
      return { created: 0, skipped: true };
    }
    const ins = (preset as any)?.installments;
    if (Array.isArray(ins)) installments = ins as Installment[];
  }

  // Fallback: single full-amount collection
  if (installments.length === 0) {
    installments = [{ label: 'Total', percent: 100, days_after_approval: 0 }];
  }

  // 4. Get app settings for auto-rule config
  const { data: settingsRows } = await supabase
    .from('app_settings')
    .select('key, value');
  const settings: Record<string, string> = {};
  for (const r of settingsRows || []) {
    if (r.key) settings[r.key] = String(r.value || '');
  }
  const autoRuleEnabled = settings['collection_rule_enabled'] === 'true';

  // 5. Create one collection per installment
  const approvalDate = new Date(input.approvalDate);
  const created: string[] = [];

  for (const inst of installments) {
    const amount = Math.round((total * inst.percent / 100) * 100) / 100;
    if (amount <= 0) continue;

    const dueDate = new Date(approvalDate);
    dueDate.setDate(dueDate.getDate() + (inst.days_after_approval || 0));
    const dueDateISO = dueDate.toISOString().slice(0, 10);

    const client = (so as any).clients;
    const { data: coll, error: collErr } = await supabase
      .from('collections')
      .insert({
        service_order_id: (so as any).id,
        client_id: (so as any).client_id,
        amount,
        due_date: dueDateISO,
        status: 'pending',
        description: inst.label,
        contact_name: client?.name || null,
        phone: client?.phone || null,
        contact_whatsapp: client?.whatsapp || null,
        auto_rule_enabled: autoRuleEnabled,
      } as never)
      .select('id')
      .single();

    if (!collErr && coll) created.push((coll as any).id);
  }

  // 6. Auto-send WhatsApp (fire-and-forget)
  if (created.length > 0) {
    void autoSendCollectionWhatsApp(created);
  }

  return { created: created.length, skipped: false };
}

async function autoSendCollectionWhatsApp(collectionIds: string[]) {
  for (const id of collectionIds) {
    try {
      const { data: coll } = await supabase
        .from('collections')
        .select(`
          *,
          client:clients(name, phone, whatsapp),
          service_order:service_orders(service_order_number, payment_method, card_installments)
        `)
        .eq('id', id)
        .single();

      if (!coll) continue;
      const c: any = coll;

      const phone =
        c.contact_whatsapp ||
        c.phone ||
        c.client?.whatsapp ||
        c.client?.phone ||
        '';
      if (!phone) continue;

      const { data: templates } = await supabase
        .from('collection_templates')
        .select('*')
        .eq('is_default', true)
        .limit(1);
      const template = templates?.[0];
      if (!template) continue;

      const { data: settingsRows } = await supabase
        .from('app_settings')
        .select('key, value');
      const settings: Record<string, string> = {};
      for (const r of settingsRows || []) {
        if (r.key) settings[r.key] = String(r.value || '');
      }

      const digits = phone.replace(/\D/g, '');
      const normalized = digits.startsWith('55') ? digits : `55${digits}`;

      const { renderTemplate } = await import('@/hooks/use-collections');
      const { buildCollectionMessage } = await import('@/lib/collection-message');
      const message = buildCollectionMessage({
        template: template.body,
        renderTemplate,
        collection: c,
        paymentMethod: c.service_order?.payment_method,
        cardInstallments: c.service_order?.card_installments,
        settings,
      });

      await supabase.functions.invoke('whatsapp-send', {
        body: { phone: normalized, message, context: 'billing', kind: 'text' },
      });

      await supabase.from('collection_contacts').insert({
        collection_id: id,
        contact_type: 'whatsapp_sent',
        notes: 'Enviado automaticamente após aprovação',
      } as never);

      await supabase
        .from('collections')
        .update({ status: 'sent' } as never)
        .eq('id', id);
    } catch (err) {
      console.error('Auto WhatsApp failed for collection', id, err);
    }
  }
}

/**
 * Gera as cobranças do SALDO ao registrar o SINAL de um orçamento — sem disparar WhatsApp
 * (diferente de generateCollectionsFromOS, usada em concluída/faturada, que envia).
 *
 * Diferenças de propósito:
 *  - exclui a parcela de ENTRADA (já quitada no sinal) — cria só as parcelas futuras;
 *  - usa a MESMA conta do sinal (categoria × discountRatio via computeSchedule), então os valores
 *    batem com o orçamento/PDF, em vez de percent × grand_total;
 *  - é idempotente (não recria se já houver cobranças não-canceladas para a OS);
 *  - respeita auto_generate_collections=false do preset.
 */
export async function generateBalanceCollections(
  input: { serviceOrderId: string; approvalDate: string },
): Promise<{ created: number; skipped: boolean }> {
  const { data: so, error: soErr } = await supabase
    .from('service_orders')
    .select(`
      id, client_id,
      labor_cost_total, parts_cost_total, operational_cost_total, travel_cost_total,
      subcontract_cost_total, is_travel_billable, discount_amount, tax_amount,
      payment_condition_preset_id, custom_payment_installments,
      clients(id, name, phone, whatsapp)
    `)
    .eq('id', input.serviceOrderId)
    .single();
  if (soErr || !so) throw soErr || new Error('OS não encontrada');
  const o = so as any;

  // Idempotência: não recria se já existem cobranças (não canceladas) para esta OS.
  const { data: existing } = await supabase
    .from('collections')
    .select('id')
    .eq('service_order_id', input.serviceOrderId)
    .neq('status', 'cancelled');
  if (existing && existing.length > 0) return { created: 0, skipped: true };

  // Resolve as parcelas da condição: preset (se auto_generate_collections != false) ou custom.
  let installments: any[] | null = null;
  if (o.payment_condition_preset_id) {
    const { data: preset } = await supabase
      .from('payment_condition_presets')
      .select('installments, auto_generate_collections')
      .eq('id', o.payment_condition_preset_id)
      .maybeSingle();
    if ((preset as any)?.auto_generate_collections === false) return { created: 0, skipped: true };
    if (Array.isArray((preset as any)?.installments)) installments = (preset as any).installments;
  }
  if (!installments && Array.isArray(o.custom_payment_installments)) {
    installments = o.custom_payment_installments;
  }

  const schedule = computeSchedule(o, installments);
  if (schedule.balance.length === 0) return { created: 0, skipped: false };

  const { data: settingsRows } = await supabase.from('app_settings').select('key, value');
  const settings: Record<string, string> = {};
  for (const r of settingsRows || []) if (r.key) settings[r.key] = String(r.value || '');
  const autoRuleEnabled = settings['collection_rule_enabled'] === 'true';

  const approval = new Date(input.approvalDate);
  const client = o.clients;
  let created = 0;
  for (const row of schedule.balance) {
    const due = new Date(approval);
    due.setDate(due.getDate() + (row.days || 0));
    const { error: collErr } = await supabase
      .from('collections')
      .insert({
        service_order_id: o.id,
        client_id: o.client_id,
        amount: row.amount,
        due_date: due.toISOString().slice(0, 10),
        status: 'pending',
        description: row.label,
        contact_name: client?.name || null,
        phone: client?.phone || null,
        contact_whatsapp: client?.whatsapp || null,
        auto_rule_enabled: autoRuleEnabled,
      } as never);
    if (!collErr) created++;
  }
  // Sem auto-envio de WhatsApp: as cobranças ficam PENDENTES para envio manual/quando decidir.
  return { created, skipped: false };
}
