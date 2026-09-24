// Gera os recebíveis de uma OS CONCLUÍDA sem sinal — um título PENDENTE por parcela da condição
// (mesma conta do sinal: categoria × discountRatio), em vez de um único título do total. Deixa o
// financeiro coerente com o fluxo do sinal (aging/cobrança por parcela). Idempotente: não recria se
// já houver recebível (o fluxo do sinal já cria entrada+saldo). Sem condição → cai no total único.
import { supabase } from '@/integrations/supabase/client';
import { depositBaseFromOrder, computeAllInstallments } from '@/lib/quote-deposit';
import { addDays, format, parseISO } from 'date-fns';

interface EnsureInput {
  serviceOrderId: string;
  /** data da conclusão, ISO 'yyyy-MM-dd' (fuso local). */
  completionDate: string;
}

export async function ensureCompletionReceivables(
  input: EnsureInput,
): Promise<{ created: number; skipped: boolean }> {
  const { data: so } = await supabase
    .from('service_orders')
    .select(`
      id, client_id, service_order_number, grand_total,
      labor_cost_total, parts_cost_total, operational_cost_total, travel_cost_total,
      subcontract_cost_total, is_travel_billable, discount_amount, tax_amount,
      payment_condition_preset_id, custom_payment_installments
    `)
    .eq('id', input.serviceOrderId)
    .maybeSingle();
  if (!so) return { created: 0, skipped: true };
  const o = so as any;

  /**
   * Idempotência: se a OS já tem QUALQUER recebível vivo, o financeiro dela já existe.
   *
   * Até 24/09/2026 esta checagem ignorava o sinal ('is_deposit = true'). A intenção era
   * boa — o fluxo do sinal cria entrada E saldo, e a idempotência pegava o saldo. Mas
   * numa condição de 100% na aprovação ("À vista") o sinal cobre o valor inteiro e NÃO
   * existe saldo: nada era encontrado, e esta função gerava o plano todo de novo, pelo
   * valor cheio, em cima de um cliente que já tinha pagado.
   *
   * Medido no dia da correção: três OS com o título em dobro, R$ 2.956,88 sendo cobrados
   * de quem não devia — OS-00073 (Rodrigo), OS-00075 (Lucenira) e OS-00084 (Robson), cada
   * uma com "Sinal — ORÇ-xxx" pago e um gêmeo pendente criado segundos depois.
   *
   * O sinal É recebível da OS. Contá-lo aqui é o que fecha a porta.
   */
  const { data: existing } = await supabase
    .from('receivables')
    .select('id')
    .eq('service_order_id', input.serviceOrderId)
    .neq('status', 'cancelled');
  if (existing && existing.length > 0) return { created: 0, skipped: true };

  // Resolve as parcelas da condição (preset ou custom).
  let installments: any[] | null = null;
  if (o.payment_condition_preset_id) {
    const { data: preset } = await supabase
      .from('payment_condition_presets')
      .select('installments')
      .eq('id', o.payment_condition_preset_id)
      .maybeSingle();
    if (Array.isArray((preset as any)?.installments)) installments = (preset as any).installments;
  }
  if (!installments && Array.isArray(o.custom_payment_installments)) {
    installments = o.custom_payment_installments;
  }

  const b = depositBaseFromOrder(o);
  const rows = computeAllInstallments(b.laborCost, b.partsCost, b.expensesTotal, b.discountRatio, installments);
  const base = parseISO(input.completionDate);

  let toInsert: Record<string, unknown>[];
  if (rows.length > 0) {
    // Um título por parcela. "na entrega" e a entrada vencem na conclusão; "em X dias" em conclusão+X.
    toInsert = rows.map((r) => {
      const due = r.dueBasis === 'delivery' ? input.completionDate : format(addDays(base, r.days || 0), 'yyyy-MM-dd');
      return {
        service_order_id: o.id,
        client_id: o.client_id,
        description: `${r.label} — ${o.service_order_number}`,
        issue_date: input.completionDate,
        due_date: due,
        amount: r.amount,
        balance_amount: r.amount,
        paid_amount: 0,
        status: 'pending',
        is_deposit: false,
        due_on_completion: r.dueBasis === 'delivery',
      };
    });
  } else {
    // Sem condição de parcelamento → título único do total (comportamento anterior).
    const total = Number(o.grand_total || 0);
    if (total <= 0) return { created: 0, skipped: true };
    toInsert = [{
      service_order_id: o.id,
      client_id: o.client_id,
      description: `OS ${o.service_order_number}`,
      issue_date: input.completionDate,
      due_date: format(addDays(base, 30), 'yyyy-MM-dd'),
      amount: total,
      balance_amount: total,
      paid_amount: 0,
      status: 'pending',
      is_deposit: false,
    }];
  }

  const { error } = await supabase.from('receivables').insert(toInsert as never);
  if (error) throw error;
  return { created: toInsert.length, skipped: false };
}
