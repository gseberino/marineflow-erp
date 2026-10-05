// Condição de pagamento de um orçamento/OS JÁ EXISTENTE (05/10/2026).
//
// POR QUE EXISTE: o assistente só preenchia a condição ao CRIAR o orçamento. Pedido do dono no
// ORÇ-00112 (Nelson): "sinal só dos materiais, saldo da mão de obra na conclusão" — sem ferramenta,
// o texto foi parar nas Observações para impressão, o PDF não mostrou a programação de pagamento e
// o resumo de valores calcularia o sinal pela condição padrão (100% materiais + 50% mão de obra).
//
// Grava os MESMOS três campos que o seletor da tela (financial-section.tsx): a condição pronta
// (payment_condition_preset_id + payment_conditions = rótulo) OU parcelas próprias
// (custom_payment_installments, "Personalizado") OU só um texto livre. Sinal e saldo saem da conta
// única (quote-deposit) — a mesma do formulário, do PDF e do "Receber sinal".
//
// IA pensa, sistema preenche: o modelo diz QUAL condição (ou os percentuais); os valores em reais
// quem calcula é a conta, e a resposta devolve o sinal e o saldo para ele repetir ao dono.
import { blockTechnician, NON_TECHNICIAN_ROLES, type ToolDef } from "./registry.ts";
import { computeSchedule, type DepositInstallment } from "../../banking/quote-deposit.ts";
import { fmtCurrency } from "../../pdf/documento.ts";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** "100% Materiais na aprovação  + Serviço…" e "100% materiais na aprovação + serviço…" são a mesma. */
export function normalizarRotulo(t: unknown): string {
  return String(t ?? "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/\s+/g, " ").trim();
}

interface Preset {
  id: string;
  label: string;
  installments: DepositInstallment[] | null;
}

/**
 * A condição pronta pelo rótulo. As condições cadastradas têm DUPLICATAS (05/10/2026: "À vista",
 * "50% de sinal + 50% na entrega", "30 dias após conclusão"… duas vezes, uma delas sem parcelas):
 * entre as de mesmo rótulo, vale a que TEM parcelas — é a que gera a programação de pagamento.
 */
export function acharPreset(presets: Preset[], rotulo: unknown): Preset | null {
  const alvo = normalizarRotulo(rotulo);
  if (!alvo) return null;
  const iguais = presets.filter((p) => normalizarRotulo(p.label) === alvo);
  return iguais.find((p) => Array.isArray(p.installments) && p.installments.length > 0) ?? iguais[0] ?? null;
}

/** Os rótulos distintos, para o modelo oferecer quando o pedido não casa com nenhum. */
export function rotulosDistintos(presets: Preset[]): string[] {
  const vistos = new Map<string, string>();
  for (const p of presets) if (!vistos.has(normalizarRotulo(p.label))) vistos.set(normalizarRotulo(p.label), p.label);
  return [...vistos.values()];
}

const QUANDO = ["aprovacao", "entrega", "prazo"] as const;
type Quando = typeof QUANDO[number];

/** As parcelas que o modelo descreveu, no formato que a tela grava. null = inválidas (com o motivo). */
export function parcelasDoPedido(bruto: unknown): { parcelas: DepositInstallment[] } | { error: string } {
  if (!Array.isArray(bruto) || bruto.length === 0) return { error: "Informe ao menos uma parcela." };
  if (bruto.length > 12) return { error: "No máximo 12 parcelas." };
  const parcelas: DepositInstallment[] = [];
  for (const [i, r] of bruto.entries()) {
    const p = (r ?? {}) as Record<string, unknown>;
    const quando = String(p.quando ?? "").trim().toLowerCase() as Quando;
    if (!QUANDO.includes(quando)) return { error: `Parcela ${i + 1}: 'quando' deve ser aprovacao, entrega ou prazo.` };
    const pct = (v: unknown) => (v === undefined || v === null || v === "" ? 0 : Number(v));
    const servicos = pct(p.mao_de_obra_pct), pecas = pct(p.materiais_pct), despesas = pct(p.despesas_pct);
    for (const [nome, v] of [["mao_de_obra_pct", servicos], ["materiais_pct", pecas], ["despesas_pct", despesas]] as const) {
      if (!Number.isFinite(v) || v < 0 || v > 100) return { error: `Parcela ${i + 1}: ${nome} deve estar entre 0 e 100.` };
    }
    const dias = quando === "prazo" ? Number(p.dias ?? 0) : 0;
    if (quando === "prazo" && (!Number.isFinite(dias) || dias <= 0)) {
      return { error: `Parcela ${i + 1}: com quando='prazo', informe 'dias' (dias após a aprovação).` };
    }
    parcelas.push({
      label: String(p.rotulo ?? "").trim() || (quando === "aprovacao" ? "Sinal" : quando === "entrega" ? "Saldo na entrega" : `Parcela ${i + 1}`),
      services_pct: servicos,
      parts_pct: pecas,
      expenses_pct: despesas,
      days_after_approval: dias,
      tipo: quando,
    });
  }
  // Cada categoria tem de fechar 100% somando as parcelas — senão parte do orçamento nunca é cobrada
  // (ou é cobrada duas vezes). A tela deixa o editor livre; o assistente não pode errar a conta.
  for (const [campo, nome] of [["services_pct", "mão de obra"], ["parts_pct", "materiais"], ["expenses_pct", "despesas"]] as const) {
    const soma = parcelas.reduce((s, p) => s + Number(p[campo] ?? 0), 0);
    if (soma > 100.001) return { error: `A soma das parcelas de ${nome} dá ${soma}% — passa de 100%.` };
  }
  return { parcelas };
}

/** O texto que vai no campo de condição quando são parcelas próprias, sem o dono escrever. */
export function descreverParcelas(parcelas: DepositInstallment[]): string {
  return parcelas.map((p) => {
    const partes: string[] = [];
    if (Number(p.parts_pct) > 0) partes.push(`${p.parts_pct}% materiais`);
    if (Number(p.services_pct) > 0) partes.push(`${p.services_pct}% mão de obra`);
    if (Number(p.expenses_pct) > 0) partes.push(`${p.expenses_pct}% despesas`);
    const quando = p.tipo === "aprovacao" ? "na aprovação" : p.tipo === "entrega" ? "na entrega" : `em ${p.days_after_approval} dias`;
    return `${partes.join(" + ") || "0%"} ${quando}`;
  }).join(" · ");
}

export const condicaoPagamentoTools: ToolDef[] = [
  {
    name: "definir_condicao_pagamento",
    description:
      "Define ou troca a CONDIÇÃO DE PAGAMENTO de um orçamento/OS que JÁ EXISTE (o campo próprio, que sai na programação de pagamento do PDF e no resumo de valores) e devolve o sinal e o saldo já calculados. " +
      "Três jeitos, use UM: (1) condicao = rótulo de uma condição pronta (ex.: '100% Materiais na aprovação + Serviço na entrega', '50% mão de obra + 100% materiais antecipados', '50% de sinal + 50% na entrega', 'À vista'); " +
      "(2) parcelas = percentuais por categoria quando nenhuma pronta serve (cada categoria deve somar 100% entre as parcelas); (3) só texto, para condição sem parcelas ('Faturado mensalmente'). " +
      "NÃO use observações/extra_notes para condição de pagamento. Os valores em reais quem calcula é o sistema: repita ao usuário o sinal e o saldo que a ferramenta devolver.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string", description: "UUID ou número (ORÇ-00112 / OS-00045)." },
        condicao: { type: "string", description: "Rótulo de uma condição pronta (as cadastradas em Configurações)." },
        parcelas: {
          type: "array",
          description: "Parcelas próprias, quando nenhuma condição pronta serve.",
          items: {
            type: "object",
            properties: {
              rotulo: { type: "string", description: "Ex.: 'Sinal', 'Saldo na entrega'." },
              quando: { type: "string", enum: ["aprovacao", "entrega", "prazo"], description: "aprovacao = sinal; entrega = na conclusão; prazo = N dias após a aprovação." },
              dias: { type: "number", description: "Só com quando='prazo'." },
              materiais_pct: { type: "number", description: "% dos materiais/peças nesta parcela (0–100)." },
              mao_de_obra_pct: { type: "number", description: "% da mão de obra nesta parcela (0–100)." },
              despesas_pct: { type: "number", description: "% das despesas/deslocamento nesta parcela (0–100)." },
            },
            required: ["quando"],
          },
        },
        texto: { type: "string", description: "Texto da condição. Sozinho = condição só em texto (sem parcelas). Com parcelas = como a condição aparece escrita (opcional)." },
      },
      required: ["service_order_id"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { sb } = ctx;
      const usados = [args.condicao, args.parcelas, !args.condicao && !args.parcelas ? args.texto : null].filter((v) => v !== undefined && v !== null && v !== "").length;
      if (usados !== 1 || (args.condicao && args.parcelas)) {
        return { error: "Use UM jeito: condicao (pronta), parcelas (próprias) ou só texto." };
      }

      const id = String(args.service_order_id ?? "");
      let q = sb.from("service_orders").select(
        "id, service_order_number, status, signed_at, grand_total, labor_cost_total, parts_cost_total, operational_cost_total, travel_cost_total, is_travel_billable, subcontract_cost_total, discount_amount, tax_amount, payment_conditions, payment_condition_preset_id, custom_payment_installments",
      );
      q = UUID_RE.test(id) ? q.eq("id", id) : q.eq("service_order_number", id);
      const { data: so, error: soErr } = await q.maybeSingle();
      if (soErr) throw soErr;
      if (!so) return { error: `Orçamento/OS não encontrado: "${id}".` };
      if (so.status === "cancelled") return { error: `${so.service_order_number} está cancelado(a): não se muda a condição.` };
      if (so.status === "invoiced") return { error: `${so.service_order_number} já foi faturado(a): a condição não muda mais.` };

      let update: Record<string, unknown>;
      let parcelas: DepositInstallment[] | null = null;
      let rotulo: string;
      if (args.condicao) {
        const { data: presets, error } = await sb.from("payment_condition_presets").select("id, label, installments");
        if (error) throw error;
        const preset = acharPreset((presets ?? []) as Preset[], args.condicao);
        if (!preset) {
          return {
            error: `Não há condição pronta chamada "${args.condicao}".`,
            condicoes_prontas: rotulosDistintos((presets ?? []) as Preset[]),
            orientacao: "Ofereça as condições prontas, ou monte com 'parcelas' se nenhuma servir.",
          };
        }
        parcelas = Array.isArray(preset.installments) && preset.installments.length > 0 ? preset.installments : null;
        rotulo = preset.label;
        update = { payment_condition_preset_id: preset.id, payment_conditions: preset.label, custom_payment_installments: null };
      } else if (args.parcelas) {
        const lidas = parcelasDoPedido(args.parcelas);
        if ("error" in lidas) return lidas;
        parcelas = lidas.parcelas;
        rotulo = typeof args.texto === "string" && args.texto.trim() ? args.texto.trim() : descreverParcelas(parcelas);
        update = { payment_condition_preset_id: null, payment_conditions: rotulo, custom_payment_installments: parcelas };
      } else {
        rotulo = String(args.texto).trim();
        if (rotulo.length > 300) return { error: "Texto da condição longo demais (máximo 300 caracteres)." };
        update = { payment_condition_preset_id: null, payment_conditions: rotulo, custom_payment_installments: null };
      }

      const antes = so.payment_conditions || null;
      const { error: upErr } = await sb.from("service_orders").update(update).eq("id", so.id);
      if (upErr) throw upErr;

      const plano = parcelas ? computeSchedule(so, parcelas) : null;
      const total = Number(so.grand_total) || 0;
      const coberto = plano ? Math.round((plano.signalAmount + plano.balanceTotal) * 100) / 100 : null;
      const avisos: string[] = [];
      if (plano && coberto !== null && Math.abs(coberto - total) > 0.05) {
        avisos.push(`As parcelas somam ${fmtCurrency(coberto)}, mas o total é ${fmtCurrency(total)}: alguma categoria não chega a 100% (confira despesas/deslocamento).`);
      }
      if (so.signed_at) avisos.push("O orçamento estava ASSINADO: com a condição nova, o cliente precisa assinar de novo.");
      return {
        ok: true,
        documento: so.service_order_number,
        condicao: rotulo,
        condicao_anterior: antes,
        total: fmtCurrency(total),
        ...(plano
          ? {
            sinal: fmtCurrency(plano.signalAmount),
            saldo: plano.balance.map((b) => ({
              parcela: b.label,
              valor: fmtCurrency(b.amount),
              quando: b.dueBasis === "delivery" ? "na entrega" : b.days <= 0 ? "na aprovação" : `em ${b.days} dias`,
            })),
          }
          : { observacao: "Condição só em texto: sem programação de parcelas no PDF." }),
        ...(avisos.length ? { avisos } : {}),
        orientacao: "Repita ao usuário o sinal e o saldo acima (são os valores do PDF). Se havia condição escrita nas observações, ofereça tirá-la de lá.",
      };
    },
  },
];
