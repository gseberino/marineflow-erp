// Gera os recebíveis de uma OS CONCLUÍDA sem sinal — um título PENDENTE por parcela da condição
// (mesma conta do sinal: categoria × discountRatio), em vez de um único título do total. Deixa o
// financeiro coerente com o fluxo do sinal (aging/cobrança por parcela). Idempotente: não recria se
// já houver recebível (o fluxo do sinal já cria entrada+saldo). Sem condição → cai no total único.
//
// Agenda de Produção, Fase 3 (P2): a regra mora em recebiveisDaConclusao (pura, sem banco), e o banco tem o
// espelho dela, _os_recebiveis_da_conclusao (migration 20261026100100), que a porta única de status usa ao
// concluir. As duas são provadas iguais caso a caso: completion-receivables.paridade.test.ts (aqui) e
// supabase/tests/agenda_fase3_recebiveis.sql (lá), sobre o mesmo scripts/bancada-agenda/recebiveis-casos.json.
// Mudar a regra aqui sem mudar lá (ou o contrário) reprova os dois.
//
// Fase 3 (P3): a tela conclui pela porta (useUpdateServiceOrderStatus → os_transicionar_status, via 'tela'). Este arquivo
// é o espelho da porta (_os_recebiveis_da_conclusao) e só é chamado pelo plano B (statusPelaTelaSemAPorta, com a migration
// 20261026100100 ainda não aplicada) e pelos testes de paridade: ensureCompletionReceivables sai com o plano B.
import { supabase } from '@/integrations/supabase/client';
import {
  depositBaseFromOrder,
  computeAllInstallments,
  type DepositInstallment,
  type DepositOrderLike,
} from '@/lib/quote-deposit';
import { addDays, format, parseISO } from 'date-fns';

interface EnsureInput {
  serviceOrderId: string;
  /** data da conclusão, ISO 'yyyy-MM-dd' (fuso local). */
  completionDate: string;
}

/** O que a regra lê da OS: os totais de depositBaseFromOrder, o total e o número. */
export interface OsDaConclusao extends DepositOrderLike {
  service_order_number: string;
  grand_total?: number | null;
}

/** Um recebível que a conclusão lança (os campos que mudam de OS para OS). */
export interface LinhaDaConclusao {
  description: string;
  issue_date: string;
  due_date: string;
  amount: number;
  due_on_completion: boolean;
}

/**
 * Por que a conclusão lança o que lança:
 *   ja_tem       — a OS já tem recebível vivo (o sinal conta): nada nasce;
 *   parcelas     — um título por parcela da condição com valor;
 *   titulo_unico — sem parcela com valor: um título do total, em 30 dias;
 *   total_zero   — sem parcela com valor e o total da OS é zero: nada nasce.
 */
export type MotivoDaConclusao = 'ja_tem' | 'parcelas' | 'titulo_unico' | 'total_zero';

export interface RecebiveisDaConclusao {
  motivo: MotivoDaConclusao;
  linhas: LinhaDaConclusao[];
}

/** As parcelas da condição: as do preset, se forem lista; senão as personalizadas da OS, se forem lista; senão nenhuma. */
export function parcelasDaCondicao(doPreset: unknown, personalizadas: unknown): DepositInstallment[] | null {
  if (Array.isArray(doPreset)) return doPreset as DepositInstallment[];
  if (Array.isArray(personalizadas)) return personalizadas as DepositInstallment[];
  return null;
}

/**
 * A regra dos recebíveis da conclusão, sem banco. `existentes` são os recebíveis que a OS já tem (só o status importa:
 * qualquer um fora de 'cancelled' — o sinal incluído — é o financeiro dela; status nulo não conta, como o `.neq` do
 * PostgREST). `data` é o dia da conclusão ('yyyy-MM-dd').
 */
export function recebiveisDaConclusao(
  o: OsDaConclusao,
  parcelas: DepositInstallment[] | null | undefined,
  data: string,
  existentes: ReadonlyArray<{ status?: string | null }> = [],
): RecebiveisDaConclusao {
  if (existentes.some((r) => r.status != null && r.status !== 'cancelled')) return { motivo: 'ja_tem', linhas: [] };

  const b = depositBaseFromOrder(o);
  const rows = computeAllInstallments(b.laborCost, b.partsCost, b.expensesTotal, b.discountRatio, parcelas);
  const base = parseISO(data);

  if (rows.length > 0) {
    // Um título por parcela. "na entrega" e a entrada vencem na conclusão; "em X dias" em conclusão+X.
    return {
      motivo: 'parcelas',
      linhas: rows.map((r) => ({
        description: `${r.label} — ${o.service_order_number}`,
        issue_date: data,
        due_date: r.dueBasis === 'delivery' ? data : format(addDays(base, r.days || 0), 'yyyy-MM-dd'),
        amount: r.amount,
        due_on_completion: r.dueBasis === 'delivery',
      })),
    };
  }

  // Sem condição de parcelamento → título único do total (comportamento anterior).
  // O número já vem com o prefixo ("OS-00075"/"ORÇ-00112"): sem "OS " na frente, que
  // gravava "OS OS-00075" na descrição do recebível.
  const total = Number(o.grand_total || 0);
  if (total <= 0) return { motivo: 'total_zero', linhas: [] };
  return {
    motivo: 'titulo_unico',
    linhas: [{
      description: o.service_order_number,
      issue_date: data,
      due_date: format(addDays(base, 30), 'yyyy-MM-dd'),
      amount: total,
      due_on_completion: false,
    }],
  };
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
  let doPreset: unknown = null;
  if (o.payment_condition_preset_id) {
    const { data: preset } = await supabase
      .from('payment_condition_presets')
      .select('installments')
      .eq('id', o.payment_condition_preset_id)
      .maybeSingle();
    doPreset = (preset as any)?.installments;
  }
  const installments = parcelasDaCondicao(doPreset, o.custom_payment_installments);

  const r = recebiveisDaConclusao(o, installments, input.completionDate);
  if (r.linhas.length === 0) return { created: 0, skipped: true };

  const toInsert: Record<string, unknown>[] = r.linhas.map((l) => ({
    service_order_id: o.id,
    client_id: o.client_id,
    description: l.description,
    issue_date: l.issue_date,
    due_date: l.due_date,
    amount: l.amount,
    balance_amount: l.amount,
    paid_amount: 0,
    status: 'pending',
    is_deposit: false,
    // O título único sempre foi inserido sem a coluna (o padrão do banco é false): a carga continua a mesma.
    ...(r.motivo === 'parcelas' ? { due_on_completion: l.due_on_completion } : {}),
  }));

  const { error } = await supabase.from('receivables').insert(toInsert as never);
  if (error) throw error;
  return { created: toInsert.length, skipped: false };
}
