// Tools: ORDEM DE COMPRA e COTAÇÃO até o fim — o que a tela faz e o assistente não fazia
// (pedido do dono, aprovado em 07/10/2026).
//
// Ordem de compra (tela: src/v2/pages/PurchaseOrdersV2.tsx e PurchaseOrderDetailV2.tsx; hooks em
// src/hooks/use-purchase-orders.ts):
//   get_purchase_order            → o detalhe com os itens numerados (base para receber em parte)
//   update_purchase_order_status  → o menu de situação: rascunho ↔ enviada, cancelar
//   update_purchase_order         → o diálogo Editar: fornecedor, previsão, observações, itens
//   delete_purchase_order         → Excluir (aqui SÓ rascunho sem nada recebido)
//   (receber, inteira ou em parte, é receive_purchase_order em purchasing.ts — resolverRecebimento
//    abaixo é a conferência que ela faz antes da rotina do banco)
//
// Cotação (tela: src/pages/QuoteRequestDetailPage.tsx; hooks em src/hooks/use-quote-requests.ts):
//   list_quote_requests       → a lista de cotações, por situação, OS, cliente, item, fornecedor
//   close_quote_request       → Fechar (compra direta, com ou sem OC) e Cancelar
//   reopen_quote_request      → Reabrir
//   set_quote_supplier_terms  → frete e desconto por fornecedor (quote_request_supplier_terms)
//
// Mesmas tabelas e mesmos campos da tela. Pelo WhatsApp o assistente grava sem RLS (ctx.admin),
// então o cargo é revalidado em código: admin e financeiro, como as policies de compras.

import { blockTechnician, type Role, type ToolCtx, type ToolDef } from "./registry.ts";
import { dataDita, ehErro } from "./caixa.ts";
import { resolverFornecedorDito } from "./finance-rules.ts";
import { localizarOrdem } from "./documentos-pdf.ts";
import {
  acharItemDaOC,
  CARGOS_DE_COMPRAS,
  type Cotacao,
  fornecedorEntre,
  gerarOCDaCotacao,
  type ItemDaOC,
  itensDitos,
  lerItensDaOC,
  localizarCotacao,
  localizarOC,
  type OC,
  SITUACAO_DA_COTACAO,
  SITUACAO_DA_OC,
  textoTemPalavras,
} from "./compras-base.ts";

const fmtBRL = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });
const brl = (v: unknown) => fmtBRL.format(Number(v) || 0);
const hojeBR = () => new Date(Date.now() - 3 * 3600_000).toISOString().slice(0, 10).split("-").reverse().join("/");

function guarda(ctx: ToolCtx) {
  const b = blockTechnician(ctx);
  if (b) return b;
  return CARGOS_DE_COMPRAS.includes(ctx.userRole as Role) ? null : { error: "Compras é do administrador e do financeiro." };
}

/** Os campos de localizar a OC, iguais em todas as tools de OC. */
const ACHAR_OC = {
  ordem_de_compra: { type: "string", description: "Número da OC (OC-00012, 12) ou o id." },
  fornecedor: { type: "string", description: "Nome do fornecedor, para achar a OC dele ('a OC da Victron')." },
  os: { type: "string", description: "OS/orçamento de origem (OS-00098), para achar a OC dela." },
};

/** Os campos de localizar a cotação, iguais em todas as tools de cotação. */
const ACHAR_COTACAO = {
  cotacao: { type: "string", description: "Código da cotação (COT-00005, 5) ou o id." },
  item: { type: "string", description: "O que foi cotado, para achar a cotação ('baterias', 'cabo')." },
  os: { type: "string", description: "OS/orçamento de origem (ORÇ-00080, OS-00098)." },
};

const comOpcoes = (r: { erro: string; opcoes?: string[] }) => ({ error: r.erro, ...(r.opcoes ? { opcoes: r.opcoes } : {}) });

const itemParaMostrar = (i: ItemDaOC, n: number) => ({
  n,
  descricao: i.description,
  do_catalogo: !!i.product_id,
  pedido: i.quantity,
  recebido: i.received_qty,
  falta: Math.max(0, i.quantity - i.received_qty),
  custo_unitario: i.unit_cost,
  subtotal: Math.round(i.quantity * i.unit_cost * 100) / 100,
});

// ─── Receber (conferência de receive_purchase_order) ──────────────────────────────────────

export type LinhaDoRecebimento = { item: ItemDaOC; n: number; quantidade: number; faltava: number };

/**
 * Confere o recebimento ANTES da rotina do banco (receive_po), que não confere: se o item é da
 * OC, se a OC pode receber, se a quantidade cabe no que falta. E recusa item de texto livre — o
 * movimento de estoque exige produto, e um item assim derruba o recebimento inteiro.
 */
// deno-lint-ignore no-explicit-any
export async function resolverRecebimento(admin: any, args: Record<string, unknown>): Promise<
  { oc: OC; linhas: LinhaDoRecebimento[] } | { erro: string; opcoes?: string[] }
> {
  const achada = await localizarOC(admin, args, ["draft", "sent", "partial"]);
  if ("erro" in achada) return achada;
  const oc = achada.oc;
  if (oc.status === "cancelled") return { erro: `A ${oc.po_number} está cancelada — não recebe.` };
  if (oc.status === "received") return { erro: `A ${oc.po_number} já está toda recebida.` };
  const lidos = await lerItensDaOC(admin, oc.id);
  if ("erro" in lidos) return lidos;
  const itens = lidos.itens;
  if (!itens.length) return { erro: `A ${oc.po_number} não tem itens.` };

  const pedidos: Array<{ ref: Record<string, unknown>; quantidade: number }> = [];
  if (args.receber_tudo === true) {
    for (const it of itens) {
      const falta = it.quantity - it.received_qty;
      if (falta > 0) pedidos.push({ ref: { po_item_id: it.id }, quantidade: falta });
    }
    if (!pedidos.length) return { erro: `Nada falta receber na ${oc.po_number}.` };
  } else if (Array.isArray(args.itens) && args.itens.length) {
    for (const r of args.itens as Array<Record<string, unknown>>) pedidos.push({ ref: r, quantidade: Number(r?.quantidade) });
  } else if (Array.isArray(args.items) && args.items.length) {
    for (const r of args.items as Array<Record<string, unknown>>) pedidos.push({ ref: { po_item_id: r?.po_item_id }, quantidade: Number(r?.received_qty) });
  } else {
    return { erro: "Diga o que chegou: os itens com a quantidade (itens), ou receber_tudo se chegou tudo." };
  }

  // O mesmo item citado duas vezes soma.
  const porItem = new Map<string, LinhaDoRecebimento>();
  for (const p of pedidos) {
    const achado = acharItemDaOC(itens, p.ref);
    if ("erro" in achado) return { erro: achado.erro };
    if (!Number.isFinite(p.quantidade) || p.quantidade <= 0) return { erro: `Diga quantas unidades de "${achado.item.description}" chegaram (maior que zero).` };
    const atual = porItem.get(achado.item.id);
    const faltava = achado.item.quantity - achado.item.received_qty;
    porItem.set(achado.item.id, { item: achado.item, n: achado.n, quantidade: (atual?.quantidade ?? 0) + p.quantidade, faltava });
  }
  const linhas = [...porItem.values()].sort((a, b) => a.n - b.n);
  for (const l of linhas) {
    if (l.faltava <= 0) return { erro: `O item ${l.n} (${l.item.description}) já foi todo recebido.` };
    if (l.quantidade > l.faltava) {
      return { erro: `Do item ${l.n} (${l.item.description}) só faltam ${l.faltava} (pedido ${l.item.quantity}, já recebido ${l.item.received_qty}). Confira a quantidade.` };
    }
  }
  const semProduto = linhas.filter((l) => !l.item.product_id);
  if (semProduto.length) {
    return {
      erro: `${semProduto.map((l) => `"${l.item.description}"`).join(", ")} não ${semProduto.length > 1 ? "são produtos" : "é produto"} do catálogo (item de texto livre): a rotina de recebimento dá entrada no estoque e recusa item sem produto — inclusive o resto do recebimento. Vincule o item a um produto (edite a OC na tela) ou receba os outros itens separadamente.`,
    };
  }
  return { oc, linhas };
}

/** Resumo da confirmação de receive_purchase_order: a OC, o que chega, e o que acontece depois. */
// deno-lint-ignore no-explicit-any
export async function resumirRecebimento(admin: any, args: Record<string, unknown>): Promise<string> {
  const r = await resolverRecebimento(admin, args);
  if ("erro" in r) return `⚠️ ${r.erro}`;
  const { oc, linhas } = r;
  const lidos = await lerItensDaOC(admin, oc.id);
  const completa = !("erro" in lidos) && lidos.itens.every((it) => {
    const l = linhas.find((x) => x.item.id === it.id);
    return it.received_qty + (l?.quantidade ?? 0) >= it.quantity;
  });
  const total = "erro" in lidos ? 0 : lidos.itens.reduce((a, it) => {
    const l = linhas.find((x) => x.item.id === it.id);
    return a + (it.received_qty + (l?.quantidade ?? 0)) * it.unit_cost;
  }, 0);
  const prazo = Number(args.due_days) > 0 ? Number(args.due_days) : 30;
  return [
    `Receber na *${oc.po_number}* — ${oc.suppliers?.trade_name || oc.suppliers?.name || "sem fornecedor"}:`,
    ...linhas.map((l) => `- ${l.quantidade} de ${l.faltava} que faltavam — ${l.n}. ${l.item.description}`),
    "Entra no estoque agora (movimento de compra).",
    completa
      ? (oc.supplier_id ? `Com isso a OC fica COMPLETA: gera conta a pagar de *${brl(total)}*, vencendo em ${prazo} dias.` : "Com isso a OC fica completa (sem fornecedor: não gera conta a pagar).")
      : "A OC fica *recebida em parte*: a conta a pagar só nasce quando tudo chegar.",
  ].join("\n");
}

/** Resumo da confirmação de delete_purchase_order. */
// deno-lint-ignore no-explicit-any
export async function resumirExclusaoDeOC(admin: any, args: Record<string, unknown>): Promise<string> {
  const achada = await localizarOC(admin, args, ["draft"]);
  if ("erro" in achada) return `⚠️ ${achada.erro}`;
  const oc = achada.oc;
  // Uma linha "⚠️" é recusa antes da pendência (RESUMO_QUE_RESOLVE em agent.ts): o dono não
  // aprova uma exclusão que a execução vai recusar.
  if (oc.status !== "draft") return `⚠️ A ${oc.po_number} está ${SITUACAO_DA_OC[oc.status] ?? oc.status}: só rascunho se exclui. Para desistir de uma enviada, cancele.`;
  const lidos = await lerItensDaOC(admin, oc.id);
  if ("erro" in lidos) return `⚠️ ${lidos.erro}`;
  if (lidos.itens.some((i) => i.received_qty > 0)) return `⚠️ A ${oc.po_number} já tem item recebido — não se exclui.`;
  return [
    `EXCLUIR a *${oc.po_number}* — ${oc.suppliers?.trade_name || oc.suppliers?.name || "sem fornecedor"} (${SITUACAO_DA_OC[oc.status] ?? oc.status})`,
    ...lidos.itens.map((i, k) => `- ${k + 1}. ${i.quantity}× ${i.description} — ${brl(i.unit_cost)}`),
    `Total: *${brl(oc.total_amount)}*. Não se desfaz.`,
  ].join("\n");
}

// ─── Cotação: o retrato para a lista ──────────────────────────────────────────────────────

// deno-lint-ignore no-explicit-any
async function lerAoRedor(admin: any, cotacoes: Cotacao[]) {
  const ids = cotacoes.map((c) => c.id);
  const soIds = [...new Set(cotacoes.map((c) => c.service_order_id).filter(Boolean))] as string[];
  const supIds = [...new Set(cotacoes.flatMap((c) => c.sent_supplier_ids ?? []))];
  const [itens, resps, envios, ordens] = await Promise.all([
    admin.from("quote_request_items").select("quote_request_id, position, description, quantity").in("quote_request_id", ids),
    admin.from("quote_responses").select("quote_request_id, supplier_id, unit_price, confirmed").in("quote_request_id", ids),
    admin.from("quote_request_sends").select("quote_request_id, supplier_id").in("quote_request_id", ids),
    soIds.length ? admin.from("service_orders").select("id, service_order_number, client_id, clients(name)").in("id", soIds) : Promise.resolve({ data: [], error: null }),
  ]);
  for (const [r, o] of [[itens, "itens"], [resps, "respostas"], [envios, "envios"], [ordens, "ordens de origem"]] as const) {
    if (r.error) throw new Error(`Não consegui ler ${o} das cotações: ${r.error.message}`);
  }
  const respIds = [...new Set(((resps.data ?? []) as Array<{ supplier_id: string }>).map((r) => r.supplier_id))];
  const todosSup = [...new Set([...supIds, ...respIds])];
  const sups = todosSup.length ? await admin.from("suppliers").select("id, name, trade_name").in("id", todosSup) : { data: [], error: null };
  if (sups.error) throw new Error(`Não consegui ler os fornecedores das cotações: ${sups.error.message}`);
  return {
    itens: (itens.data ?? []) as Array<{ quote_request_id: string; position: number; description: string; quantity: number }>,
    resps: (resps.data ?? []) as Array<{ quote_request_id: string; supplier_id: string; unit_price: number | null; confirmed: boolean }>,
    envios: (envios.data ?? []) as Array<{ quote_request_id: string; supplier_id: string }>,
    ordens: (ordens.data ?? []) as Array<{ id: string; service_order_number: string; client_id: string | null; clients?: { name: string } | null }>,
    sups: (sups.data ?? []) as Array<{ id: string; name: string; trade_name: string | null }>,
  };
}

const SITUACAO_DITA: Record<string, string[]> = {
  aberta: ["open"], abertas: ["open"], open: ["open"],
  fechada: ["closed"], fechadas: ["closed"], closed: ["closed"],
  cancelada: ["cancelled"], canceladas: ["cancelled"], cancelled: ["cancelled"],
  todas: ["open", "closed", "cancelled"], all: ["open", "closed", "cancelled"],
};

const SITUACAO_DA_OC_DITA: Record<string, string> = {
  enviada: "sent", sent: "sent", "enviada ao fornecedor": "sent",
  rascunho: "draft", draft: "draft",
  cancelada: "cancelled", cancelar: "cancelled", cancelled: "cancelled",
};

export const comprasCicloTools: ToolDef[] = [
  // ─── Ordem de compra ────────────────────────────────────────────────────────────────────
  {
    name: "get_purchase_order",
    description:
      "Mostra UMA ordem de compra: fornecedor, situação, previsão, OS de origem e os ITENS NUMERADOS (pedido, recebido, falta, custo). Ache pelo número (OC-00012), pelo fornecedor ('a OC da Victron') ou pela OS. Use antes de receber em parte ou de editar itens, para saber o número de cada item. Só leitura.",
    input_schema: {
      type: "object",
      properties: { ...ACHAR_OC, todas: { type: "boolean", description: "true = procurar também entre recebidas e canceladas (por fornecedor/OS)." } },
    },
    risk: "low",
    roles: CARGOS_DE_COMPRAS,
    async execute(args, ctx) {
      const g = guarda(ctx);
      if (g) return g;
      const achada = await localizarOC(ctx.admin, args, args.todas ? ["draft", "sent", "partial", "received", "cancelled"] : ["draft", "sent", "partial"]);
      if ("erro" in achada) return comOpcoes(achada);
      const oc = achada.oc;
      const lidos = await lerItensDaOC(ctx.admin, oc.id);
      if ("erro" in lidos) return { error: lidos.erro };
      return {
        ordem_de_compra: oc.po_number,
        situacao: SITUACAO_DA_OC[oc.status] ?? oc.status,
        fornecedor: oc.suppliers?.trade_name || oc.suppliers?.name || null,
        os: oc.service_orders?.service_order_number ?? null,
        previsao: oc.expected_date,
        observacoes: oc.notes,
        total: Number(oc.total_amount) || 0,
        conta_a_pagar: oc.payable_id ? "gerada" : "ainda não",
        itens: lidos.itens.map((i, k) => itemParaMostrar(i, k + 1)),
      };
    },
  },
  {
    name: "update_purchase_order_status",
    description:
      "Muda a SITUAÇÃO de uma ordem de compra, como o menu da tela: 'enviada' (mandei o pedido ao fornecedor), 'rascunho' (voltar para editar) ou 'cancelada' (não vai mais comprar; motivo opcional vai nas observações). Ex.: 'marca a OC da Victron como enviada', 'cancela a OC-00012'. Recebida e recebida em parte NÃO se marcam aqui — isso é receive_purchase_order (dá entrada no estoque). OC já recebida (toda ou em parte) não se cancela por aqui.",
    input_schema: {
      type: "object",
      properties: {
        ...ACHAR_OC,
        situacao: { type: "string", enum: ["enviada", "rascunho", "cancelada"], description: "A situação nova." },
        motivo: { type: "string", description: "Por que cancelou (vai nas observações da OC)." },
      },
      required: ["situacao"],
    },
    // Back-office reversível (cancelada volta a rascunho), como o menu da tela: executa direto.
    risk: "low",
    roles: CARGOS_DE_COMPRAS,
    async execute(args, ctx) {
      const g = guarda(ctx);
      if (g) return g;
      const nova = SITUACAO_DA_OC_DITA[String(args.situacao ?? "").trim().toLowerCase()];
      if (!nova) return { error: `Situação "${args.situacao}" não existe. Use enviada, rascunho ou cancelada (recebida é por receive_purchase_order).` };
      // Por fornecedor/OS procura também as canceladas: "volta a OC da Victron para rascunho".
      const achada = await localizarOC(ctx.admin, args, nova === "cancelled" ? ["draft", "sent", "partial"] : ["draft", "sent", "partial", "cancelled"]);
      if ("erro" in achada) return comOpcoes(achada);
      const oc = achada.oc;
      if (oc.status === nova) return { ok: true, ordem_de_compra: oc.po_number, aviso: `A ${oc.po_number} já está ${SITUACAO_DA_OC[nova]}. Nada mudou.` };
      if (oc.status === "received") return { error: `A ${oc.po_number} já foi toda recebida — não muda mais de situação.` };
      if (oc.status === "partial") {
        // O que chegou já entrou no estoque, e a conta a pagar só nasce quando a OC fica completa
        // (receive_po): cancelar agora deixaria o que chegou sem conta a pagar nenhuma.
        return { error: `A ${oc.po_number} já foi recebida em parte: o que chegou está no estoque e a conta a pagar só nasce quando tudo chegar. Cancelar agora deixaria essa compra sem conta a pagar — resolva pela tela (receber o resto, ou ajustar os itens e lançar a conta).` };
      }
      const patch: Record<string, unknown> = { status: nova };
      const motivo = String(args.motivo ?? "").trim();
      if (nova === "cancelled" && motivo) {
        patch.notes = `${oc.notes ? `${oc.notes}\n` : ""}Cancelada em ${hojeBR()}: ${motivo}`;
      }
      // Só muda se ainda estiver como estava: dois pedidos cruzados não se atropelam.
      const { data, error } = await ctx.admin.from("purchase_orders").update(patch).eq("id", oc.id).eq("status", oc.status).select("id");
      if (error) return { error: `Não consegui mudar a situação: ${error.message}` };
      if (!(data ?? []).length) return { error: `A ${oc.po_number} mudou de situação agora há pouco. Confira (get_purchase_order) e peça de novo.` };
      return {
        ok: true,
        ordem_de_compra: oc.po_number,
        fornecedor: oc.suppliers?.trade_name || oc.suppliers?.name || null,
        antes: SITUACAO_DA_OC[oc.status] ?? oc.status,
        agora: SITUACAO_DA_OC[nova],
        ...(nova === "sent" ? { observacao: "Marcada como enviada. O assistente não mandou nada ao fornecedor — isto só registra que o pedido foi feito." } : {}),
      };
    },
  },
  {
    name: "update_purchase_order",
    description:
      "Edita uma ordem de compra em RASCUNHO ou ENVIADA, como o diálogo Editar da tela: trocar o fornecedor (novo_fornecedor), a previsão de chegada (previsao: 'hoje', '25/10', '2026-10-25' ou 'limpar'), as observações, e os itens — adicionar_itens [{descricao, quantidade, custo_unitario}], remover_itens [{n | descricao}] e alterar_itens [{n | descricao, quantidade?, custo_unitario?}] (n = número do item em get_purchase_order). O total recalcula sozinho. Item já recebido não se remove nem fica abaixo do recebido.",
    input_schema: {
      type: "object",
      properties: {
        ...ACHAR_OC,
        novo_fornecedor: { type: "string", description: "Nome (igual ao cadastro) ou id do fornecedor novo." },
        previsao: { type: "string", description: "Previsão de chegada: 'hoje', '25/10', '2026-10-25', ou 'limpar'." },
        observacoes: { type: "string", description: "Observações novas (substituem as de agora; para acrescentar, mande as antigas + a nova)." },
        adicionar_itens: {
          type: "array",
          items: {
            type: "object",
            properties: { descricao: { type: "string" }, quantidade: { type: "number" }, custo_unitario: { type: "number" }, product_id: { type: "string" } },
            required: ["descricao"],
          },
        },
        remover_itens: {
          type: "array",
          items: { type: "object", properties: { n: { type: "number" }, descricao: { type: "string" } } },
        },
        alterar_itens: {
          type: "array",
          items: {
            type: "object",
            properties: { n: { type: "number" }, descricao: { type: "string" }, quantidade: { type: "number" }, custo_unitario: { type: "number" } },
          },
        },
      },
    },
    risk: "low",
    roles: CARGOS_DE_COMPRAS,
    async execute(args, ctx) {
      const g = guarda(ctx);
      if (g) return g;
      const { admin } = ctx;
      const achada = await localizarOC(admin, args, ["draft", "sent"]);
      if ("erro" in achada) return comOpcoes(achada);
      const oc = achada.oc;
      if (oc.status !== "draft" && oc.status !== "sent") {
        return { error: `A ${oc.po_number} está ${SITUACAO_DA_OC[oc.status] ?? oc.status}: só rascunho e enviada se editam (o recebido já está no estoque).` };
      }
      const lidos = await lerItensDaOC(admin, oc.id);
      if ("erro" in lidos) return { error: lidos.erro };
      const itens = lidos.itens;

      // ── Tudo conferido antes de gravar qualquer coisa ──
      const cabecalho: Record<string, unknown> = {};
      const noCabecalho: string[] = [];
      const feito: string[] = [];
      if (args.novo_fornecedor) {
        const f = await resolverFornecedorDito(ctx, String(args.novo_fornecedor));
        if (ehErro(f)) return f;
        cabecalho.supplier_id = f.id;
        noCabecalho.push(`fornecedor → ${f.nome}`);
      }
      if (args.previsao !== undefined && args.previsao !== null && String(args.previsao).trim() !== "") {
        const limpar = /^(limpar|nenhuma|sem|apagar)$/i.test(String(args.previsao).trim());
        const data = limpar ? null : dataDita(args.previsao);
        if (!limpar && !data) return { error: `Não entendi a previsão "${args.previsao}". Use 'hoje', '25/10' ou 2026-10-25.` };
        cabecalho.expected_date = data;
        noCabecalho.push(`previsão → ${data ? data.split("-").reverse().join("/") : "sem previsão"}`);
      }
      if (typeof args.observacoes === "string") {
        cabecalho.notes = args.observacoes.trim() || null;
        noCabecalho.push("observações trocadas");
      }
      const novos = itensDitos(args.adicionar_itens);
      if ("erro" in novos) return { error: novos.erro };
      const remover: ItemDaOC[] = [];
      for (const r of (Array.isArray(args.remover_itens) ? args.remover_itens : []) as Array<Record<string, unknown>>) {
        const a = acharItemDaOC(itens, r);
        if ("erro" in a) return { error: a.erro };
        if (a.item.received_qty > 0) return { error: `O item ${a.n} (${a.item.description}) já teve ${a.item.received_qty} recebido — não se remove.` };
        remover.push(a.item);
      }
      const alterar: Array<{ item: ItemDaOC; patch: Record<string, number> }> = [];
      for (const r of (Array.isArray(args.alterar_itens) ? args.alterar_itens : []) as Array<Record<string, unknown>>) {
        const a = acharItemDaOC(itens, r);
        if ("erro" in a) return { error: a.erro };
        const patch: Record<string, number> = {};
        if (r.quantidade !== undefined && r.quantidade !== null) {
          const q = Number(r.quantidade);
          if (!Number.isFinite(q) || q <= 0) return { error: `A quantidade nova do item ${a.n} tem de ser maior que zero.` };
          if (q < a.item.received_qty) return { error: `O item ${a.n} já teve ${a.item.received_qty} recebido — a quantidade não fica abaixo disso.` };
          patch.quantity = q;
        }
        if (r.custo_unitario !== undefined && r.custo_unitario !== null) {
          const c = Number(r.custo_unitario);
          if (!Number.isFinite(c) || c < 0) return { error: `O custo novo do item ${a.n} não pode ser negativo.` };
          patch.unit_cost = c;
        }
        if (!Object.keys(patch).length) return { error: `Diga o que muda no item ${a.n}: quantidade e/ou custo_unitario.` };
        if (remover.some((x) => x.id === a.item.id)) return { error: `O item ${a.n} está para remover e para alterar ao mesmo tempo.` };
        alterar.push({ item: a.item, patch });
      }
      if (!Object.keys(cabecalho).length && !novos.itens.length && !remover.length && !alterar.length) {
        return { error: "Diga o que muda na OC: fornecedor, previsão, observações ou itens." };
      }

      // ── Grava, na ordem da tela (cabeçalho, depois itens); para no primeiro erro dizendo o que já foi ──
      const parar = (onde: string, e: { message: string }) => ({
        error: `Parei ao ${onde}: ${e.message}.${feito.length ? ` Já ficou gravado: ${feito.join("; ")}.` : " Nada foi gravado."}`,
      });
      if (Object.keys(cabecalho).length) {
        const { error } = await admin.from("purchase_orders").update(cabecalho).eq("id", oc.id);
        if (error) return parar("atualizar o cabeçalho", error);
        feito.push(...noCabecalho);
      }
      if (novos.itens.length) {
        const { error } = await admin.from("purchase_order_items").insert(novos.itens.map((i) => ({ ...i, purchase_order_id: oc.id, received_qty: 0 })));
        if (error) return parar("acrescentar os itens", error);
        feito.push(`${novos.itens.length} item(ns) acrescentado(s)`);
      }
      for (const r of remover) {
        const { error } = await admin.from("purchase_order_items").delete().eq("id", r.id).eq("purchase_order_id", oc.id);
        if (error) return parar(`remover "${r.description}"`, error);
        feito.push(`removido: ${r.description}`);
      }
      for (const a of alterar) {
        const { error } = await admin.from("purchase_order_items").update(a.patch).eq("id", a.item.id).eq("purchase_order_id", oc.id);
        if (error) return parar(`alterar "${a.item.description}"`, error);
        feito.push(`alterado: ${a.item.description}`);
      }

      const depois = await lerItensDaOC(admin, oc.id);
      const itensDepois = "erro" in depois ? null : depois.itens;
      return {
        ok: true,
        ordem_de_compra: oc.po_number,
        alteracoes: feito,
        ...(itensDepois
          ? {
            itens: itensDepois.map((i, k) => itemParaMostrar(i, k + 1)),
            total: Math.round(itensDepois.reduce((a, i) => a + i.quantity * i.unit_cost, 0) * 100) / 100,
          }
          : { aviso: "Gravado, mas não consegui reler os itens para mostrar." }),
        ...(oc.status === "sent" && (novos.itens.length || remover.length || alterar.length)
          ? { observacao: "A OC já estava ENVIADA ao fornecedor: avise-o da mudança (o assistente não manda nada sozinho)." }
          : {}),
      };
    },
  },
  {
    name: "delete_purchase_order",
    description:
      "EXCLUI uma ordem de compra em RASCUNHO (com os itens), como o Excluir da tela. Não se desfaz — pede confirmação. OC enviada, recebida ou cancelada não se exclui: para desistir de uma enviada, cancele (update_purchase_order_status).",
    input_schema: { type: "object", properties: ACHAR_OC },
    risk: "medium",
    roles: CARGOS_DE_COMPRAS,
    async execute(args, ctx) {
      const g = guarda(ctx);
      if (g) return g;
      const { admin } = ctx;
      const achada = await localizarOC(admin, args, ["draft"]);
      if ("erro" in achada) return comOpcoes(achada);
      const oc = achada.oc;
      if (oc.status !== "draft") {
        return { error: `A ${oc.po_number} está ${SITUACAO_DA_OC[oc.status] ?? oc.status}: só rascunho se exclui. Para desistir de uma enviada, cancele.` };
      }
      if (oc.payable_id) return { error: `A ${oc.po_number} tem conta a pagar vinculada — não se exclui.` };
      const lidos = await lerItensDaOC(admin, oc.id);
      if ("erro" in lidos) return { error: lidos.erro };
      if (lidos.itens.some((i) => i.received_qty > 0)) return { error: `A ${oc.po_number} já tem item recebido — não se exclui.` };
      // Só apaga se ainda for rascunho: se alguém a enviou entre o pedido e o "sim", não apaga.
      const { data, error } = await admin.from("purchase_orders").delete().eq("id", oc.id).eq("status", "draft").select("id");
      if (error) return { error: `Não consegui excluir: ${error.message}` };
      if (!(data ?? []).length) return { error: `A ${oc.po_number} mudou de situação desde o pedido — não excluí.` };
      return { ok: true, excluida: oc.po_number, itens_removidos: lidos.itens.length };
    },
  },

  // ─── Cotação ────────────────────────────────────────────────────────────────────────────
  {
    name: "list_quote_requests",
    description:
      "Lista as COTAÇÕES a fornecedores (COT-XXXXX), como a tela de cotações: situação (abertas, fechadas, canceladas ou todas — padrão abertas), e filtra pela OS/orçamento de origem, pelo cliente da OS, por item cotado ('baterias') ou por fornecedor. Mostra itens, fornecedores, quantos responderam e quantos receberam o pedido. Só leitura.",
    input_schema: {
      type: "object",
      properties: {
        situacao: { type: "string", enum: ["abertas", "fechadas", "canceladas", "todas"], description: "Padrão: abertas." },
        os: { type: "string", description: "OS/orçamento de origem (ORÇ-00080, OS-00098)." },
        cliente: { type: "string", description: "Nome do cliente da OS de origem." },
        item: { type: "string", description: "Texto do item cotado ('bateria', 'cabo')." },
        fornecedor: { type: "string", description: "Nome do fornecedor consultado." },
        limite: { type: "number", description: "Máximo de cotações (padrão 20, teto 50)." },
      },
    },
    risk: "low",
    roles: CARGOS_DE_COMPRAS,
    async execute(args, ctx) {
      const g = guarda(ctx);
      if (g) return g;
      const { admin } = ctx;
      const situacoes = SITUACAO_DITA[String(args.situacao ?? "abertas").trim().toLowerCase()];
      if (!situacoes) return { error: `Situação "${args.situacao}" não existe. Use abertas, fechadas, canceladas ou todas.` };
      let q = admin.from("quote_requests").select("id, code, status, service_order_id, sent_supplier_ids, notes, created_at, closed_at").in("status", situacoes);
      if (args.os) {
        const ordem = await localizarOrdem(admin, String(args.os));
        if ("erro" in ordem) return { error: ordem.erro };
        if ("opcoes" in ordem) return { error: `Há mais de um documento com esse número: ${ordem.opcoes.join(" e ")}. Pergunte qual.`, opcoes: ordem.opcoes };
        q = q.eq("service_order_id", ordem.ordem.id);
      }
      const { data, error } = await q.order("created_at", { ascending: false }).limit(200);
      if (error) return { error: `A consulta das cotações falhou (${error.message}). Tente de novo.` };
      let cotacoes = (data ?? []) as Cotacao[];
      if (!cotacoes.length) return { count: 0, results: [], nota: "Nenhuma cotação nessa situação." };
      let ao;
      try {
        ao = await lerAoRedor(admin, cotacoes);
      } catch (e) {
        return { error: e instanceof Error ? e.message : String(e) };
      }
      const ordemPorId = new Map(ao.ordens.map((o) => [o.id, o]));
      const nomeSup = (id: string) => {
        const s = ao.sups.find((x) => x.id === id);
        return s ? (s.trade_name || s.name) : id;
      };
      if (args.cliente) {
        const dito = String(args.cliente);
        cotacoes = cotacoes.filter((c) => {
          const nome = c.service_order_id ? ordemPorId.get(c.service_order_id)?.clients?.name : null;
          return !!nome && textoTemPalavras(nome, dito);
        });
      }
      if (args.item) {
        const dito = String(args.item);
        cotacoes = cotacoes.filter((c) => ao.itens.some((i) => i.quote_request_id === c.id && textoTemPalavras(i.description, dito)));
      }
      if (args.fornecedor) {
        const dito = String(args.fornecedor);
        const ids = new Set(ao.sups.filter((s) => textoTemPalavras(`${s.name} ${s.trade_name ?? ""}`, dito)).map((s) => s.id));
        cotacoes = cotacoes.filter((c) => (c.sent_supplier_ids ?? []).some((id) => ids.has(id)) || ao.resps.some((r) => r.quote_request_id === c.id && ids.has(r.supplier_id)));
      }
      const limite = Math.min(Number(args.limite) || 20, 50);
      const results = cotacoes.slice(0, limite).map((c) => {
        const itens = ao.itens.filter((i) => i.quote_request_id === c.id).sort((a, b) => a.position - b.position);
        const resps = ao.resps.filter((r) => r.quote_request_id === c.id);
        const responderam = [...new Set(resps.filter((r) => r.unit_price != null).map((r) => r.supplier_id))];
        const receberam = [...new Set(ao.envios.filter((e) => e.quote_request_id === c.id).map((e) => e.supplier_id))];
        const ordem = c.service_order_id ? ordemPorId.get(c.service_order_id) : null;
        return {
          quote_request_id: c.id,
          codigo: c.code,
          situacao: SITUACAO_DA_COTACAO[c.status] ?? c.status,
          os: ordem?.service_order_number ?? null,
          cliente: ordem?.clients?.name ?? null,
          itens: itens.map((i) => `${i.position}. ${Number(i.quantity)}× ${i.description}`),
          fornecedores: (c.sent_supplier_ids ?? []).map(nomeSup),
          pedido_enviado_a: receberam.map(nomeSup),
          responderam: responderam.map(nomeSup),
          criada_em: c.created_at,
          fechada_em: c.closed_at,
        };
      });
      return { count: results.length, total_encontrado: cotacoes.length, results };
    },
  },
  {
    name: "close_quote_request",
    description:
      "FECHA ou CANCELA uma cotação, como os botões da tela. acao='fechar' = a compra foi decidida (ex.: 'fecha a cotação do cabo com o fornecedor X sem gerar OC' — compra direta: fechou no WhatsApp, pega no balcão, a nota entra depois); com gerar_oc=true e o fornecedor, gera também a ordem de compra com os preços dele e fecha. acao='cancelar' = não vai comprar por essa cotação ('cancela a cotação de baterias, comprei direto na loja'). Ache a cotação pelo código, pelo item ou pela OS. O fornecedor e o motivo vão nas observações. Reabrir: reopen_quote_request.",
    input_schema: {
      type: "object",
      properties: {
        ...ACHAR_COTACAO,
        acao: { type: "string", enum: ["fechar", "cancelar"], description: "fechar = compra decidida; cancelar = desistiu dessa cotação." },
        fornecedor: { type: "string", description: "Com quem fechou (nome igual ao cadastro ou id). Obrigatório com gerar_oc." },
        motivo: { type: "string", description: "Observação curta ('comprei direto na loja')." },
        gerar_oc: { type: "boolean", description: "true = gerar a ordem de compra com os preços desse fornecedor antes de fechar." },
        previsao: { type: "string", description: "Com gerar_oc: previsão de chegada ('25/10')." },
      },
      required: ["acao"],
    },
    // Reversível (reopen_quote_request): executa direto, como os botões da tela.
    risk: "low",
    roles: CARGOS_DE_COMPRAS,
    async execute(args, ctx) {
      const g = guarda(ctx);
      if (g) return g;
      const { admin, userId } = ctx;
      const acao = String(args.acao ?? "").trim().toLowerCase();
      if (acao !== "fechar" && acao !== "cancelar") return { error: "acao é 'fechar' ou 'cancelar'." };
      if (args.gerar_oc && acao !== "fechar") return { error: "Cotação cancelada não gera ordem de compra. Use acao='fechar' com gerar_oc." };
      const achada = await localizarCotacao(admin, args, ["open"]);
      if ("erro" in achada) return comOpcoes(achada);
      const cot = achada.cotacao;
      if (cot.status !== "open") return { error: `A cotação ${cot.code} já está ${SITUACAO_DA_COTACAO[cot.status] ?? cot.status}. Para mexer de novo, reabra (reopen_quote_request).` };

      let fornecedor: { id: string; nome: string } | null = null;
      if (args.fornecedor) {
        const { data: resps, error } = await admin.from("quote_responses").select("supplier_id").eq("quote_request_id", cot.id);
        if (error) return { error: `A consulta das respostas falhou (${error.message}). Tente de novo.` };
        const ids = [...(cot.sent_supplier_ids ?? []), ...((resps ?? []) as Array<{ supplier_id: string }>).map((r) => r.supplier_id)];
        const f = await fornecedorEntre(admin, args.fornecedor, ids);
        if ("erro" in f) return comOpcoes(f);
        fornecedor = f;
      }
      if (args.gerar_oc) {
        if (!fornecedor) return { error: "Para gerar a ordem de compra, diga com qual fornecedor fechou." };
        let previsao: string | null = null;
        if (args.previsao) {
          previsao = dataDita(args.previsao);
          if (!previsao) return { error: `Não entendi a previsão "${args.previsao}". Use 'hoje', '25/10' ou 2026-10-25.` };
        }
        const gerada = await gerarOCDaCotacao(admin, admin, {
          cotacao: cot,
          supplierId: fornecedor.id,
          somenteEscolhidos: false,
          expected_date: previsao,
          notes: `Gerada da cotação ${cot.code}${args.motivo ? ` — ${String(args.motivo).trim()}` : ""}`,
          userId,
        });
        if ("erro" in gerada) return { error: gerada.erro };
        return {
          ok: true,
          cotacao: cot.code,
          situacao: gerada.avisoDoFechamento ? "aberta" : "fechada",
          ordem_de_compra: gerada.po.po_number,
          fornecedor: fornecedor.nome,
          itens: gerada.linhas.map((l) => ({ descricao: l.description, quantidade: l.quantity, custo_unitario: l.unit_cost })),
          total: gerada.total,
          ...(gerada.avisoDoFechamento ? { aviso: gerada.avisoDoFechamento } : {}),
        };
      }

      // Sem OC: o mesmo patch do useCloseQuoteRequest (situação, closed_at e a nota acrescentada).
      const nota = [
        acao === "fechar" ? `Fechada em ${hojeBR()}${fornecedor ? ` com ${fornecedor.nome}` : ""} (compra direta, sem OC)` : `Cancelada em ${hojeBR()}`,
        String(args.motivo ?? "").trim(),
      ].filter(Boolean).join(": ");
      const patch = {
        status: acao === "fechar" ? "closed" : "cancelled",
        closed_at: new Date().toISOString(),
        notes: cot.notes ? `${cot.notes}\n${nota}` : nota,
      };
      const { data, error } = await admin.from("quote_requests").update(patch).eq("id", cot.id).eq("status", "open").select("id");
      if (error) return { error: `Não consegui ${acao} a cotação: ${error.message}` };
      if (!(data ?? []).length) return { error: `A cotação ${cot.code} mudou de situação agora há pouco. Confira e peça de novo.` };
      return {
        ok: true,
        cotacao: cot.code,
        situacao: acao === "fechar" ? "fechada" : "cancelada",
        ...(fornecedor ? { fornecedor: fornecedor.nome } : {}),
        anotado: nota,
        observacao: acao === "fechar"
          ? "Fechada sem ordem de compra: a compra direta entra depois pela nota (Entrada por XML) ou como conta a pagar."
          : "Cancelada: para de cobrar resposta dos fornecedores. Dá para reabrir.",
      };
    },
  },
  {
    name: "reopen_quote_request",
    description:
      "REABRE uma cotação fechada ou cancelada, como o botão Reabrir da tela (volta a aceitar preço e a aparecer como aberta). Ache pelo código, pelo item ou pela OS.",
    input_schema: { type: "object", properties: ACHAR_COTACAO },
    risk: "low",
    roles: CARGOS_DE_COMPRAS,
    async execute(args, ctx) {
      const g = guarda(ctx);
      if (g) return g;
      const achada = await localizarCotacao(ctx.admin, args, ["closed", "cancelled"]);
      if ("erro" in achada) return comOpcoes(achada);
      const cot = achada.cotacao;
      if (cot.status === "open") return { ok: true, cotacao: cot.code, aviso: `A cotação ${cot.code} já está aberta.` };
      const { error } = await ctx.admin.from("quote_requests").update({ status: "open", closed_at: null }).eq("id", cot.id);
      if (error) return { error: `Não consegui reabrir: ${error.message}` };
      return { ok: true, cotacao: cot.code, antes: SITUACAO_DA_COTACAO[cot.status] ?? cot.status, agora: "aberta" };
    },
  },
  {
    name: "set_quote_supplier_terms",
    description:
      "Grava FRETE e DESCONTO de um fornecedor numa cotação (em R$, para o pacote dele: itens − desconto + frete), como os campos da tela de comparação. Ex.: 'na cotação das baterias a Victron cobra 80 de frete e dá 50 de desconto'. Campo não dito fica como estava.",
    input_schema: {
      type: "object",
      properties: {
        ...ACHAR_COTACAO,
        fornecedor: { type: "string", description: "Fornecedor da cotação (nome ou id)." },
        frete: { type: "number", description: "Frete em R$ (0 = sem frete)." },
        desconto: { type: "number", description: "Desconto em R$ sobre o pacote (0 = sem desconto)." },
      },
      required: ["fornecedor"],
    },
    risk: "low",
    roles: CARGOS_DE_COMPRAS,
    async execute(args, ctx) {
      const g = guarda(ctx);
      if (g) return g;
      const { admin, userId } = ctx;
      if (args.frete == null && args.desconto == null) return { error: "Diga o frete e/ou o desconto." };
      for (const [campo, v] of [["frete", args.frete], ["desconto", args.desconto]] as const) {
        if (v != null && (!Number.isFinite(Number(v)) || Number(v) < 0)) return { error: `O ${campo} tem de ser um valor em reais, zero ou mais.` };
      }
      const achada = await localizarCotacao(admin, args, ["open", "closed"]);
      if ("erro" in achada) return comOpcoes(achada);
      const cot = achada.cotacao;
      const [resps, termos] = await Promise.all([
        admin.from("quote_responses").select("supplier_id, quote_request_item_id, unit_price").eq("quote_request_id", cot.id),
        admin.from("quote_request_supplier_terms").select("supplier_id, freight, discount").eq("quote_request_id", cot.id),
      ]);
      if (resps.error) return { error: `A consulta das respostas falhou (${resps.error.message}). Tente de novo.` };
      if (termos.error) return { error: `A consulta de frete e desconto falhou (${termos.error.message}). Tente de novo.` };
      const ids = [...(cot.sent_supplier_ids ?? []), ...((resps.data ?? []) as Array<{ supplier_id: string }>).map((r) => r.supplier_id)];
      const f = await fornecedorEntre(admin, args.fornecedor, ids);
      if ("erro" in f) return comOpcoes(f);
      const atual = ((termos.data ?? []) as Array<{ supplier_id: string; freight: number; discount: number }>).find((t) => t.supplier_id === f.id);
      const freight = args.frete != null ? Math.max(0, Number(args.frete)) : Number(atual?.freight) || 0;
      const discount = args.desconto != null ? Math.max(0, Number(args.desconto)) : Number(atual?.discount) || 0;
      // O mesmo upsert de useSaveQuoteSupplierTerms.
      const { error } = await admin.from("quote_request_supplier_terms").upsert({
        quote_request_id: cot.id,
        supplier_id: f.id,
        freight,
        discount,
        updated_by: userId || null,
        updated_at: new Date().toISOString(),
      }, { onConflict: "quote_request_id,supplier_id" });
      if (error) return { error: `Não gravei frete/desconto: ${error.message}` };
      // O pacote do fornecedor, pela mesma conta da tela (itens − desconto + frete), quando ele já deu preço.
      const { data: itens, error: itErr } = await admin.from("quote_request_items").select("id, quantity").eq("quote_request_id", cot.id);
      const precos = ((resps.data ?? []) as Array<{ supplier_id: string; quote_request_item_id: string; unit_price: number | null }>)
        .filter((r) => r.supplier_id === f.id && r.unit_price != null);
      const qtd = new Map(((itens ?? []) as Array<{ id: string; quantity: number }>).map((i) => [i.id, Number(i.quantity) || 1]));
      const somaItens = precos.reduce((a, r) => a + Number(r.unit_price) * (qtd.get(r.quote_request_item_id) ?? 1), 0);
      return {
        ok: true,
        cotacao: cot.code,
        fornecedor: f.nome,
        frete: freight,
        desconto: discount,
        ...(!itErr && precos.length
          ? { pacote: Math.round((somaItens - discount + freight) * 100) / 100, itens_com_preco: precos.length }
          : { nota: "Esse fornecedor ainda não tem preço registrado; o pacote aparece quando tiver." }),
      };
    },
  },
];

