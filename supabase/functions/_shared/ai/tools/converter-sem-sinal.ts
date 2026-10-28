// converter_sem_sinal — orçamento vira OS SEM sinal, com o valor inteiro na conclusão (27/10/2026).
//
// Paridade com a tela (src/components/ConverterSemSinal.tsx): mesma condição (fonte única em
// _shared/banking/condicao-na-conclusao.ts), mesma ordem — condição + orçamento aprovado, depois a
// conversão — e o MESMO número: ORÇ-00042 vira OS-00042, como faz useUpdateServiceOrderStatus. (A
// update_service_order_status do assistente puxa um número novo da sequência; aqui não.)
//
// Risco médio: troca a condição de pagamento e compromete o serviço, então pede o "sim". O retrato
// guarda o total que o dono viu; se o orçamento mudar até o "sim", a execução recusa.

import { blockTechnician, lerRetrato, NON_TECHNICIAN_ROLES, type ToolDef } from "./registry.ts";
import { condicaoTudoNaConclusao } from "../../banking/condicao-na-conclusao.ts";
import { fmtCurrency } from "../../pdf/documento.ts";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const COLUNAS = "id, service_order_number, status, quote_status, converted_to_os_at, grand_total, original_quote_amount, signed_at, payment_conditions";

type Orcamento = {
  id: string;
  service_order_number: string | null;
  status: string;
  quote_status: string | null;
  converted_to_os_at: string | null;
  grand_total: number | null;
  original_quote_amount: number | null;
  signed_at: string | null;
  payment_conditions: string | null;
};

// deno-lint-ignore no-explicit-any
async function lerOrcamento(sb: any, ref: string): Promise<Orcamento | null> {
  let q = sb.from("service_orders").select(COLUNAS);
  q = UUID_RE.test(ref) ? q.eq("id", ref) : q.eq("service_order_number", ref);
  const { data, error } = await q.maybeSingle();
  if (error) throw error;
  return (data as Orcamento | null) ?? null;
}

/** Recusa o que não é orçamento convertível. null = pode converter. */
export function recusaParaConverter(o: Orcamento): { error: string } | null {
  const n = o.service_order_number ?? "O orçamento";
  if (o.converted_to_os_at || o.status !== "draft") return { error: `${n} já é OS — não há o que converter.` };
  if (o.quote_status === "rejected") {
    return { error: `${n} está Reprovado. Volte para "Em elaboração" (update_quote_status → draft) antes de converter.` };
  }
  return null;
}

/** ORÇ-00042 → OS-00042 (sequência única: orçamento e OS dividem o contador). */
export function numeroDaOS(numero: string | null): string | null {
  if (!numero) return numero;
  return numero.startsWith("ORÇ-") ? numero.replace("ORÇ-", "OS-") : numero;
}

export const converterSemSinalTools: ToolDef[] = [
  {
    name: "converter_sem_sinal",
    description:
      "Converte um ORÇAMENTO em OS SEM sinal: o cliente paga o valor inteiro na CONCLUSÃO do serviço (ex.: orçamento adicional de quem já tem serviço em andamento, 'acerta tudo no final', 'pode tocar sem entrada'). " +
      "Numa ação só: troca a condição de pagamento para '100% na entrega', marca o orçamento como aprovado e converte (ORÇ-00042 vira OS-00042). A conta a receber nasce na conclusão, vencendo no dia. " +
      "NÃO use quando houver sinal: sinal já pago → register_deposit_and_convert; sinal a cobrar → siga o playbook de aprovação. Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string", description: "UUID ou número do orçamento (ORÇ-00112)." },
      },
      required: ["service_order_id"],
    },
    risk: "medium",
    roles: NON_TECHNICIAN_ROLES,
    preValidar(args, ctx) {
      if (ctx.userRole === "technician") return { error: "Cargo não autorizado para esta ação." };
      if (!String(args?.service_order_id ?? "").trim()) return { error: "Diga qual orçamento converter (o número ORÇ)." };
      return null;
    },
    async retratoDaPendencia(args, ctx) {
      const o = await lerOrcamento(ctx.sb, String(args.service_order_id ?? "").trim());
      if (!o) return null;
      return { id: o.id, numero: o.service_order_number, total: Number(o.grand_total) || 0 };
    },
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { sb } = ctx;
      const ref = String(args.service_order_id ?? "").trim();
      const o = await lerOrcamento(sb, ref);
      if (!o) return { error: `Orçamento não encontrado: "${ref}".` };
      const recusa = recusaParaConverter(o);
      if (recusa) return recusa;

      // O "sim" foi sobre este orçamento com este total.
      const retrato = lerRetrato(args);
      const total = Number(o.grand_total) || 0;
      if (retrato && (retrato.id !== o.id || Math.abs(Number(retrato.total) - total) > 0.009)) {
        return {
          error: `${o.service_order_number} mudou desde o pedido (total era ${fmtCurrency(Number(retrato.total) || 0)}, agora ${fmtCurrency(total)}). Nada foi convertido — confirme de novo com o valor atual.`,
        };
      }

      const { data: presets, error: pErr } = await sb.from("payment_condition_presets").select("id, label, installments").eq("active", true);
      if (pErr) throw pErr;
      const condicao = condicaoTudoNaConclusao(presets ?? []);

      const { error: cErr } = await sb
        .from("service_orders")
        .update({ ...condicao, quote_status: "approved" })
        .eq("id", o.id);
      if (cErr) throw cErr;

      const numero = numeroDaOS(o.service_order_number);
      const { data: os, error: sErr } = await sb
        .from("service_orders")
        .update({
          status: "approved",
          converted_to_os_at: new Date().toISOString(),
          service_order_number: numero,
          ...(o.original_quote_amount ? {} : { original_quote_amount: o.grand_total }),
        })
        .eq("id", o.id)
        .eq("status", "draft")
        .is("converted_to_os_at", null)
        .select("id, service_order_number, status")
        .maybeSingle();
      if (sErr) throw sErr;
      if (!os) {
        return {
          error: `A condição de ${o.service_order_number} foi trocada para "${condicao.payment_conditions}", mas a conversão não aconteceu (alguém converteu ao mesmo tempo?). Confira na tela.`,
        };
      }

      const avisos: string[] = [];
      if (o.signed_at) avisos.push("O orçamento estava ASSINADO com outra condição: o cliente precisa assinar de novo.");
      return {
        ok: true,
        documento: os.service_order_number,
        orcamento_era: o.service_order_number,
        condicao: condicao.payment_conditions,
        condicao_anterior: o.payment_conditions || null,
        total: fmtCurrency(total),
        quando_paga: "Valor inteiro na conclusão do serviço (a conta a receber nasce ao concluir).",
        ...(avisos.length ? { avisos } : {}),
      };
    },
  },
];
