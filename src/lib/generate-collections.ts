import { supabase } from '@/integrations/supabase/client';

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
      clients(id, full_name_or_company_name, phone, whatsapp)
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
        contact_name: client?.full_name_or_company_name || null,
        contact_phone: client?.phone || null,
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
          client:clients(full_name_or_company_name, phone, whatsapp),
          service_order:service_orders(service_order_number, payment_method, card_installments)
        `)
        .eq('id', id)
        .single();

      if (!coll) continue;
      const c: any = coll;

      const phone =
        c.contact_whatsapp ||
        c.contact_phone ||
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
      const message = renderTemplate(template.body, {
        nome: c.contact_name || c.client?.full_name_or_company_name || 'Cliente',
        numero_os: c.service_order?.service_order_number || 'Avulso',
        valor: Number(c.amount),
        vencimento: c.due_date,
        pix: settings['pix_key'] || settings['company_pix'] || '',
        empresa: settings['company_name'] || 'HBR Marine',
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
