import { supabase } from '@/integrations/supabase/client';

interface GenerateInput {
  serviceOrderId: string;
  approvalDate: string; // ISO date YYYY-MM-DD
  trigger: 'signature' | 'status_change' | 'invoice';
  /** Dispara o WhatsApp de cobrança automaticamente (default true). Na CONCLUSÃO passamos false:
   * o aviso ao cliente é opt-in (CompletionSendDialog), não automático. */
  autoSend?: boolean;
}

interface Installment {
  label: string;
  percent: number;
  days_after_approval: number;
}

export async function generateCollectionsFromOS(
  input: GenerateInput
): Promise<{ created: number; skipped: boolean; failed: number }> {
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
  // Leitura que falha NÃO é "não há cobranças": seguir em frente gerava cobrança em dobro
  // (19/11/2026). Sem saber o que já existe, para e avisa.
  const { data: existing, error: existingErr } = await supabase
    .from('collections')
    .select('id')
    .eq('service_order_id', input.serviceOrderId)
    .neq('status', 'cancelled');
  if (existingErr) {
    throw new Error('Não consegui conferir as cobranças que já existem desta OS — nenhuma cobrança foi gerada. Tente de novo.');
  }
  if (existing && existing.length > 0) {
    return { created: 0, skipped: true, failed: 0 };
  }

  const total = Number((so as any).grand_total || 0);
  if (total <= 0) return { created: 0, skipped: true, failed: 0 };

  // 3. Find payment condition preset
  let installments: Installment[] = [];
  const presetId = (so as any).payment_condition_preset_id;
  if (presetId) {
    // Preset ilegível: sem ele não se sabe se "gerar cobranças" está DESLIGADO nem quais são as
    // parcelas — cair no "total à vista" ignorava auto_generate_collections=false (19/11/2026).
    const { data: preset, error: presetErr } = await supabase
      .from('payment_condition_presets')
      .select('installments, auto_generate_collections')
      .eq('id', presetId)
      .maybeSingle();
    if (presetErr) {
      throw new Error('Não consegui ler a condição de pagamento desta OS — nenhuma cobrança foi gerada. Tente de novo.');
    }

    if ((preset as any)?.auto_generate_collections === false) {
      return { created: 0, skipped: true, failed: 0 };
    }
    const ins = (preset as any)?.installments;
    if (Array.isArray(ins)) installments = ins as Installment[];
  }

  // Fallback: single full-amount collection
  if (installments.length === 0) {
    installments = [{ label: 'Total', percent: 100, days_after_approval: 0 }];
  }

  // 4. Get app settings for auto-rule config
  const { data: settingsRows, error: settingsErr } = await supabase
    .from('app_settings')
    .select('key, value');
  if (settingsErr) {
    throw new Error('Não consegui ler as configurações de cobrança — nenhuma cobrança foi gerada. Tente de novo.');
  }
  const settings: Record<string, string> = {};
  for (const r of settingsRows || []) {
    if (r.key) settings[r.key] = String(r.value || '');
  }
  const autoRuleEnabled = settings['collection_rule_enabled'] === 'true';

  // 5. Create one collection per installment
  const approvalDate = new Date(input.approvalDate);
  const created: string[] = [];
  let failed = 0;

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

    // A parcela que não gravou é CONTADA: quem chamou avisa que faltou, em vez de "geradas".
    if (!collErr && coll) created.push((coll as any).id);
    else failed += 1;
  }

  // 6. Auto-send WhatsApp (fire-and-forget) — só quando autoSend !== false.
  if (created.length > 0 && input.autoSend !== false) {
    void autoSendCollectionWhatsApp(created);
  }

  return { created: created.length, skipped: false, failed };
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

      // Sem as configurações a mensagem sai sem chave Pix/dados de pagamento: não envia.
      const { data: settingsRows, error: settingsErr } = await supabase
        .from('app_settings')
        .select('key, value');
      if (settingsErr) throw settingsErr;
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

      // Envio que falhou não vira "enviada": sem isto a cobrança ficava 'sent' e com contato
      // registrado sem ter saído mensagem nenhuma (19/11/2026).
      const { error: sendErr } = await supabase.functions.invoke('whatsapp-send', {
        body: { phone: normalized, message, context: 'billing', kind: 'text' },
      });
      if (sendErr) throw sendErr;

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
