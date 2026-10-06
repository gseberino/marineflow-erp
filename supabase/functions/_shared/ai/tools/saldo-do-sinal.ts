// Parcelas do SALDO ao registrar o sinal pelo assistente (06/10/2026).
//
// POR QUE EXISTE: register_deposit_and_convert e approve_quote_full chamavam a RPC sem
// p_balance_installments. A OS convertia, o sinal virava recebível pago, a OS ficava "paga" e o
// restante nunca virava conta a receber — a conclusão também não cria, porque já existe sinal
// (completion-receivables). Caso real: OS-00112, total R$ 10.500, sinal R$ 7.600, R$ 2.900 sumidos.
//
// Mesma regra do "Receber sinal" da tela (RegisterDepositDialog): a condição pré-cadastrada
// manda; sem ela, as parcelas próprias; o cronograma sai da conta única (quote-deposit). Cada
// parcela do saldo vence na entrega (scheduled_end_at, ou o pagamento + 30 dias) ou em
// pagamento + N dias, e "na entrega" se reajusta à conclusão real (due_on_completion).
//
// Diferença deliberada: quando o sinal pago NÃO bate com o da condição (a tela, no modo valor
// fixo, não lança saldo nenhum), o assistente lança UMA parcela com o restante, na entrega —
// saldo que some é dinheiro que ninguém cobra.
import type { ToolCtx } from "./registry.ts";
import { computeSchedule, depositBaseFromOrder, type DepositInstallment } from "../../banking/quote-deposit.ts";

export interface ParcelaDoSaldo {
  description: string;
  amount: number;
  due_date: string;
  due_on_completion: boolean;
}

const round2 = (n: number) => Math.round(n * 100) / 100;

function somaDias(iso: string, dias: number): string {
  const d = new Date(`${iso}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + dias);
  return d.toISOString().slice(0, 10);
}

/** Tolerância para dizer que o sinal pago "é o da condição" (centavos de arredondamento). */
const TOLERANCIA = 1;

/** Monta as parcelas do saldo a partir do orçamento já carregado (puro: testável). */
export function montarParcelasDoSaldo(
  // deno-lint-ignore no-explicit-any
  orcamento: any,
  parcelasDaCondicao: DepositInstallment[] | null,
  sinal: number,
  dataDoSinal: string,
): { parcelas: ParcelaDoSaldo[]; origem: "condicao" | "restante" | "nenhum" } {
  const numero = String(orcamento?.service_order_number ?? "").replace(/^ORÇ-/, "OS-");
  const entrega = orcamento?.scheduled_end_at ? String(orcamento.scheduled_end_at).slice(0, 10) : "";
  const vencimentoNaEntrega = entrega || somaDias(dataDoSinal, 30);

  if (parcelasDaCondicao && parcelasDaCondicao.length > 0) {
    const plano = computeSchedule(orcamento, parcelasDaCondicao);
    if (Math.abs(plano.signalAmount - sinal) <= TOLERANCIA && plano.balance.length > 0) {
      return {
        origem: "condicao",
        parcelas: plano.balance.map((r) => ({
          description: `${r.label} — ${numero}`,
          amount: r.amount,
          due_date: r.dueBasis === "delivery" ? vencimentoNaEntrega : somaDias(dataDoSinal, r.days || 0),
          due_on_completion: r.dueBasis === "delivery",
        })),
      };
    }
  }

  const base = Number(orcamento?.grand_total ?? depositBaseFromOrder(orcamento).base) || 0;
  const restante = round2(base - sinal);
  if (restante <= 0.009) return { origem: "nenhum", parcelas: [] };
  return {
    origem: "restante",
    parcelas: [{ description: `Saldo — ${numero}`, amount: restante, due_date: vencimentoNaEntrega, due_on_completion: true }],
  };
}

/** Lê o orçamento e a condição e devolve as parcelas do saldo (ou o erro da leitura). */
export async function parcelasDoSaldo(
  ctx: ToolCtx,
  serviceOrderId: string,
  sinal: number,
  dataDoSinal: string,
): Promise<{ parcelas: ParcelaDoSaldo[]; origem: "condicao" | "restante" | "nenhum" } | { error: string }> {
  const { data: so, error } = await ctx.admin
    .from("service_orders")
    .select(`service_order_number, scheduled_end_at, grand_total, labor_cost_total, parts_cost_total,
             operational_cost_total, travel_cost_total, is_travel_billable, subcontract_cost_total,
             discount_amount, tax_amount, payment_conditions, payment_condition_preset_id, custom_payment_installments`)
    .eq("id", serviceOrderId)
    .maybeSingle();
  if (error) return { error: `Não consegui ler o orçamento para lançar o saldo: ${error.message}` };
  if (!so) return { error: "Orçamento não encontrado." };

  // Precedência da tela: condição pré-cadastrada (pelo id ou pelo rótulo) > parcelas próprias.
  let parcelas: DepositInstallment[] | null = null;
  // deno-lint-ignore no-explicit-any
  const o = so as any;
  if (o.payment_condition_preset_id || o.payment_conditions) {
    const consulta = ctx.admin.from("payment_condition_presets").select("id, label, installments");
    const { data: presets, error: e2 } = o.payment_condition_preset_id
      ? await consulta.eq("id", o.payment_condition_preset_id)
      : await consulta.eq("label", String(o.payment_conditions));
    if (e2) return { error: `Não consegui ler a condição de pagamento: ${e2.message}` };
    // deno-lint-ignore no-explicit-any
    const p = (presets as any[] | null)?.[0];
    if (Array.isArray(p?.installments)) parcelas = p.installments;
  }
  if (!parcelas && Array.isArray(o.custom_payment_installments) && o.custom_payment_installments.length) {
    parcelas = o.custom_payment_installments;
  }
  return montarParcelasDoSaldo(o, parcelas, sinal, dataDoSinal);
}

/** Frase curta para o resultado da ferramenta. */
export function descreverSaldo(parcelas: ParcelaDoSaldo[]): string {
  if (!parcelas.length) return "Sem saldo a receber: o sinal cobre o total.";
  const brl = (n: number) => n.toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
  const fmtData = (iso: string) => iso.split("-").reverse().join("/");
  return "Saldo lançado como conta a receber: " + parcelas.map((p) =>
    `${brl(p.amount)} ${p.due_on_completion ? "na entrega" : `em ${fmtData(p.due_date)}`}`).join(" + ") + ".";
}
