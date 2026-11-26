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

  // Nada vai ao cliente daqui (26/11/2026, dono: os envios de cobrança sem trava ganham a conferência da ficha — "1. A" e
  // "2. A"). Até então a geração (botão "Gerar Cobranças", assinatura e faturamento da OS) mandava em segundo plano o
  // modelo de cobrança pelo WhatsApp: sem prévia, sem opt-out, horário, piso nem entrada esperando no Extrato, e sem a
  // regra de uma cobrança por dia. Cobrar é o "Cobrar" da conta em Contas a Receber (CobrarClienteDialog).
  return { created: created.length, skipped: false, failed };
}
