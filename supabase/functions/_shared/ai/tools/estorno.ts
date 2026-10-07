// Estornar um pagamento registrado errado, pela conversa (07/10/2026).
//
// "estorna o pagamento de 800 que lancei na OS-00095, foi duplicado", "desfaz a baixa da conta de
// luz, ainda não paguei". A tela é o "Cancelar (estornar)" do PaymentDialog (cancelPaymentCascade em
// src/lib/cascade-updates.ts): pagamento cancelado com o motivo, conta recalculada, reembolso de gasto
// da OS desfeito, auditoria. Aqui é a função estornar_pagamento (migration 20261007100000), com os
// mesmos efeitos e p_autor — o assistente roda sem sessão, e a tela grava passo a passo pelo
// navegador com a sessão do usuário.
//
// Pagamento que veio do EXTRATO não se estorna: a linha do banco é a prova de que o dinheiro andou.
// O caminho é desfazer a aplicação do Pix (conta a receber) ou a aprovação do lançamento (conta a
// pagar) — a linha volta para a fila do Extrato. A tool diz isso em vez de estornar.
import { lerRetrato, type ToolCtx, type ToolDef } from "./registry.ts";
import { dataDita, ehErro } from "./caixa.ts";
import { mensagemDoBanco } from "./lancamentos.ts";
import {
  alvoDoRetrato, brl, CARGOS_DO_FINANCEIRO, ehUuid, mesmoValor, ordemDita, semAcessoDoFinanceiro, valorDito,
} from "./financeiro-comum.ts";

const CAMPOS = "id, amount, payment_date, payment_method, status, notes, bank_transaction_id, receivable_id, payable_id, " +
  "receivables!payments_receivable_id_fkey(description, amount, paid_amount, clients!receivables_client_id_fkey(name), service_orders!receivables_service_order_id_fkey(service_order_number)), " +
  "payables!payments_payable_id_fkey(description, amount, paid_amount, supplier_name, payees!payables_payee_id_fkey(name), suppliers!payables_supplier_id_fkey(name), service_orders!payables_linked_service_order_id_fkey(service_order_number))";

type Conta = {
  description: string | null; amount: number | string; paid_amount: number | string | null;
  clients?: { name: string } | null; supplier_name?: string | null; payees?: { name: string } | null; suppliers?: { name: string } | null;
  service_orders?: { service_order_number: string } | null;
};
export interface PagamentoLido {
  id: string; amount: number | string; payment_date: string; payment_method: string | null; status: string; notes: string | null;
  bank_transaction_id: string | null; receivable_id: string | null; payable_id: string | null;
  receivables: Conta | null; payables: Conta | null;
}

const dataBr = (iso: string | null | undefined) => (iso ? iso.slice(0, 10).split("-").reverse().join("/") : "—");

/** "R$ 800,00 de 05/10/2026 (pix) · a receber «Sinal — OS-00095» · MP Motor Homes" — numa linha. */
export function rotuloDoPagamento(p: PagamentoLido): string {
  const conta = p.receivables ?? p.payables;
  const quem = p.receivables?.clients?.name ?? p.payables?.payees?.name ?? p.payables?.suppliers?.name ?? p.payables?.supplier_name ?? null;
  return [
    `${brl.format(Number(p.amount))} de ${dataBr(p.payment_date)}${p.payment_method ? ` (${p.payment_method})` : ""}`,
    conta ? `${p.receivable_id ? "a receber" : "a pagar"} «${conta.description ?? "sem descrição"}»` : null,
    conta?.service_orders?.service_order_number ?? null,
    quem,
  ].filter(Boolean).join(" · ");
}

async function linhasDoBanco(cliente: ToolCtx["sb"], ids: string[]): Promise<Set<string> | { error: string }> {
  if (!ids.length) return new Set();
  const { data, error } = await cliente.from("bank_transactions").select("reconciled_payment_id").in("reconciled_payment_id", ids);
  if (error) return { error: `Não consegui conferir o extrato (${mensagemDoBanco(error)}).` };
  return new Set(((data ?? []) as { reconciled_payment_id: string }[]).map((l) => l.reconciled_payment_id));
}

/**
 * O pagamento do pedido: pelo id (retrato da pendência ou pagamento_id), ou pela OS, pela conta
 * (receivable_id / payable_id), pelo valor e pela data. Só os confirmados. Mais de um → as opções,
 * numa linha (vira recusa no resumo, não pendência).
 */
export async function acharPagamento(
  cliente: ToolCtx["sb"], args: Record<string, unknown>,
): Promise<{ pagamento: PagamentoLido; doExtrato: boolean } | { error: string }> {
  const id = alvoDoRetrato(lerRetrato(args), "pagamento_id") ?? (ehUuid(args.pagamento_id) ? String(args.pagamento_id).trim() : null);
  let achados: PagamentoLido[] = [];
  if (id) {
    const { data, error } = await cliente.from("payments").select(CAMPOS).eq("id", id).maybeSingle();
    if (error) return { error: `Não consegui ler o pagamento (${mensagemDoBanco(error)}).` };
    if (!data) return { error: "Pagamento não encontrado." };
    const p = data as PagamentoLido;
    if (p.status !== "confirmed") return { error: `Esse pagamento (${rotuloDoPagamento(p)}) já está estornado.` };
    achados = [p];
  } else {
    const valor = args.valor != null && args.valor !== "" ? valorDito(args.valor) : null;
    const data = args.data ? dataDita(args.data) : null;
    if (args.data && !data) return { error: `Não entendi a data "${String(args.data)}". Use dd/mm, ontem ou hoje.` };
    const receber: string[] = ehUuid(args.receivable_id) ? [String(args.receivable_id)] : [];
    const pagar: string[] = ehUuid(args.payable_id) ? [String(args.payable_id)] : [];
    let rotuloDaOs: string | null = null;
    if (args.os) {
      const o = await ordemDita(cliente, args.os);
      if (ehErro(o)) return o;
      rotuloDaOs = o.ordem.service_order_number;
      const [r, p] = await Promise.all([
        cliente.from("receivables").select("id").eq("service_order_id", o.ordem.id).limit(200),
        cliente.from("payables").select("id").eq("linked_service_order_id", o.ordem.id).limit(200),
      ]);
      if (r.error || p.error) return { error: `Não consegui ler as contas da ${rotuloDaOs} (${mensagemDoBanco(r.error ?? p.error)}).` };
      receber.push(...((r.data ?? []) as { id: string }[]).map((x) => x.id));
      pagar.push(...((p.data ?? []) as { id: string }[]).map((x) => x.id));
      if (!receber.length && !pagar.length) return { error: `A ${rotuloDaOs} não tem contas a receber nem a pagar.` };
    }
    if (!receber.length && !pagar.length && valor == null) {
      return { error: "Diga de qual pagamento: a OS, a conta (de buscar_lancamentos) ou o valor e a data." };
    }
    const base = () => {
      let q = cliente.from("payments").select(CAMPOS).eq("status", "confirmed");
      if (valor != null) q = q.gte("amount", valor - 0.01).lte("amount", valor + 0.01);
      if (data) q = q.eq("payment_date", data);
      return q.order("payment_date", { ascending: false }).limit(30);
    };
    const consultas = [];
    if (receber.length) consultas.push(base().in("receivable_id", receber));
    if (pagar.length) consultas.push(base().in("payable_id", pagar));
    if (!consultas.length) consultas.push(base());
    for (const r of await Promise.all(consultas)) {
      if (r.error) return { error: `Não consegui ler os pagamentos (${mensagemDoBanco(r.error)}). Diga que a consulta falhou.` };
      achados.push(...((r.data ?? []) as PagamentoLido[]));
    }
    achados = achados.filter((p, i) => achados.findIndex((x) => x.id === p.id) === i)
      .filter((p) => valor == null || mesmoValor(p.amount, valor));
    const dito = [rotuloDaOs, valor != null ? brl.format(valor) : null, data ? dataBr(data) : null].filter(Boolean).join(", ") || "esse filtro";
    if (!achados.length) return { error: `Nenhum pagamento confirmado com ${dito}.` };
    if (achados.length > 1) {
      return {
        error: `Há ${achados.length} pagamentos com ${dito}: ${achados.slice(0, 6).map((p) => `${rotuloDoPagamento(p)} [pagamento_id ${p.id}]`).join("; ")}. Pergunte qual.`,
      };
    }
  }
  const p = achados[0];
  const conciliados = await linhasDoBanco(cliente, [p.id]);
  if (ehErro(conciliados)) return conciliados;
  return { pagamento: p, doExtrato: !!p.bank_transaction_id || conciliados.has(p.id) };
}

/** Veio do extrato: o caminho certo, em vez do estorno. */
function orientacaoDoExtrato(p: PagamentoLido): string {
  return p.receivable_id
    ? `Esse pagamento (${rotuloDoPagamento(p)}) veio de um Pix do extrato: não se estorna. Use desfazer_aplicacao_de_pix com payment_id ${p.id} — a conta volta a dever e o Pix volta para a fila do Extrato.`
    : `Esse pagamento (${rotuloDoPagamento(p)}) veio do extrato do banco: não se estorna. Use desfazer_aprovacao_de_lancamento com payable_id ${p.payable_id} — o lançamento volta para a fila do Extrato.`;
}

export async function resumirEstorno(ctx: ToolCtx, args: Record<string, unknown>): Promise<string | null> {
  const r = await acharPagamento(ctx.admin, args);
  if (ehErro(r)) return `⚠️ ${r.error}`;
  if (r.doExtrato) return `⚠️ ${orientacaoDoExtrato(r.pagamento)}`;
  const p = r.pagamento;
  const conta = p.receivables ?? p.payables;
  const pagoAntes = Number(conta?.paid_amount ?? 0);
  const pagoDepois = Math.max(0, Math.round((pagoAntes - Number(p.amount)) * 100) / 100);
  return [
    `Estornar o pagamento: *${rotuloDoPagamento(p)}*`,
    conta ? `- A conta (${brl.format(Number(conta.amount))}) passa de ${brl.format(pagoAntes)} pago para *${brl.format(pagoDepois)}* — volta a dever ${brl.format(Math.max(0, Number(conta.amount) - pagoDepois))}.` : null,
    args.motivo ? `- Motivo: ${String(args.motivo)}` : null,
    "- O pagamento fica registrado como cancelado, com o motivo (não some).",
  ].filter(Boolean).join("\n");
}

export const estornoTools: ToolDef[] = [
  {
    name: "estornar_pagamento",
    description:
      "ESTORNA um pagamento (baixa) registrado errado — o 'Cancelar (estornar)' da tela de pagamentos: o pagamento fica cancelado com o " +
      "motivo e a conta volta a dever. 'estorna o pagamento de 800 que lancei na OS-00095, foi duplicado' (os + valor), 'desfaz a baixa " +
      "da conta de luz, ainda não paguei' (ache a conta com buscar_lancamentos e passe payable_id). Mais de um pagamento → o sistema " +
      "devolve as opções e você pergunta. Pagamento que veio do EXTRATO (Pix aplicado, linha conciliada) não se estorna: a resposta diz " +
      "o caminho (desfazer_aplicacao_de_pix ou desfazer_aprovacao_de_lancamento). Mês fechado recusa. Motivo obrigatório. Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        pagamento_id: { type: "string", description: "O pagamento, quando já se sabe (payment_id de get_os_receivables ou das opções)." },
        os: { type: "string", description: "Número da OS ('OS-00095')." },
        receivable_id: { type: "string", description: "Conta a receber (de buscar_lancamentos / get_os_receivables)." },
        payable_id: { type: "string", description: "Conta a pagar (de buscar_lancamentos)." },
        valor: { type: "number", description: "Valor do pagamento a estornar." },
        data: { type: "string", description: "Data do pagamento ('ontem', dd/mm), se a pessoa disser." },
        motivo: { type: "string", description: "Por que estornar ('duplicado', 'ainda não paguei'). Obrigatório." },
      },
      required: ["motivo"],
    },
    risk: "high",
    roles: CARGOS_DO_FINANCEIRO,
    preValidar(args) {
      if (typeof args?.motivo !== "string" || args.motivo.trim().length < 3) return { error: "Pergunte por que estornar o pagamento (motivo)." };
      if (!args.pagamento_id && !args.os && !args.receivable_id && !args.payable_id && args.valor == null) {
        return { error: "Diga de qual pagamento: a OS, a conta (de buscar_lancamentos) ou o valor e a data." };
      }
      return null;
    },
    // O "sim" é sobre o pagamento que o resumo mostrou: o id vai na pendência.
    retratoDaPendencia: async (args, ctx) => {
      const r = await acharPagamento(ctx.admin, args);
      return ehErro(r) ? null : { pagamento_id: r.pagamento.id };
    },
    async execute(args, ctx) {
      const b = semAcessoDoFinanceiro(ctx);
      if (b) return b;
      const motivo = typeof args.motivo === "string" ? args.motivo.trim() : "";
      if (motivo.length < 3) return { error: "Pergunte por que estornar o pagamento (motivo)." };
      const r = await acharPagamento(ctx.sb, args);
      if (ehErro(r)) return r;
      if (r.doExtrato) return { error: orientacaoDoExtrato(r.pagamento), nada_mudou: true };
      const { data, error } = await ctx.sb.rpc("estornar_pagamento", {
        p_pagamento: r.pagamento.id, p_motivo: motivo, p_autor: ctx.userId || null,
      });
      if (error) return { error: mensagemDoBanco(error) };
      return data;
    },
  },
];
