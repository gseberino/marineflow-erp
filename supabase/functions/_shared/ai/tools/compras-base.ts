// Peças comuns das tools de COMPRAS (ordem de compra e cotação) — 07/10/2026.
//
// Moram aqui, e não em purchasing.ts/quotes.ts, porque as duas pontas usam: o número da OC, a
// criação da OC com itens (que até 07/10 deixava OC sem número ou sem itens), e os localizadores
// que deixam o dono falar como fala — "a OC da Victron", "a OC-00012", "a cotação de baterias",
// "a cotação da ORÇ-00080" — em vez de exigir uuid. Nome nunca identifica por parecença: o
// fornecedor é procurado SÓ entre os das OCs/cotação em jogo, pelo nome igual ou cortado
// (escolherPorNome); dois que servem viram pergunta.

import type { Role } from "./registry.ts";
import { escolherPorNome, normal } from "./caixa.ts";
import { localizarOrdem } from "./documentos-pdf.ts";

/** Compras é do admin e do financeiro: é o que as policies de purchase_orders/quote_* deixam. */
export const CARGOS_DE_COMPRAS: Role[] = ["admin", "financial"];

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const SITUACAO_DA_OC: Record<string, string> = {
  draft: "rascunho",
  sent: "enviada ao fornecedor",
  partial: "recebida em parte",
  received: "recebida",
  cancelled: "cancelada",
};

export const SITUACAO_DA_COTACAO: Record<string, string> = { open: "aberta", closed: "fechada", cancelled: "cancelada" };

/**
 * Próximo número de OC, no formato da tela ("OC-00001") — mesmo esquema não-atômico de
 * generatePONumber em src/hooks/use-purchase-orders.ts. Leitura que falha LANÇA: antes caía em
 * OC-00001 e o insert batia na unicidade com uma mensagem que não dizia nada.
 */
// deno-lint-ignore no-explicit-any
export async function generatePONumber(admin: any): Promise<string> {
  const { data, error } = await admin.from("purchase_orders").select("po_number").order("created_at", { ascending: false }).limit(1);
  if (error) throw new Error(`Não consegui ler o último número de OC: ${error.message}`);
  let seq = 1;
  const last = data?.[0]?.po_number;
  if (last) {
    // Aceita o formato antigo 'PO-2026-0001' e o novo 'OC-00001', como a tela.
    const match = String(last).match(/(\d+)$/);
    if (match) seq = parseInt(match[1], 10) + 1;
  }
  return `OC-${String(seq).padStart(5, "0")}`;
}

export type ItemNovoDaOC = { product_id?: string | null; description: string; quantity: number; unit_cost: number };

/**
 * Cria a OC com número e itens — o que a tela faz em useCreatePurchaseOrder. Duas correções
 * (07/10/2026) sobre o que as tools faziam:
 *   · po_number é NOT NULL sem default: create_purchase_order inseria sem ele e falhava sempre;
 *   · o insert dos itens tinha o erro ignorado: a OC ficava de pé, vazia, e o assistente dizia
 *     "criada". Agora, item que não entra desfaz a OC (apaga o cabeçalho; os itens caem juntos
 *     pela FK em cascata) e devolve o erro.
 * Número repetido (duas OCs no mesmo instante — o esquema é não-atômico, como na tela) tenta o
 * próximo, até 3 vezes.
 */
export async function criarOC(
  // deno-lint-ignore no-explicit-any
  db: any,
  // deno-lint-ignore no-explicit-any
  admin: any,
  cabecalho: Record<string, unknown>,
  itens: ItemNovoDaOC[],
): Promise<{ po: { id: string; po_number: string } & Record<string, unknown> } | { erro: string }> {
  // deno-lint-ignore no-explicit-any
  let po: any = null;
  for (let tentativa = 0; tentativa < 3 && !po; tentativa++) {
    let numero: string;
    try {
      numero = await generatePONumber(admin);
    } catch (e) {
      return { erro: e instanceof Error ? e.message : String(e) };
    }
    if (tentativa > 0) numero = numero.replace(/\d+$/, (d) => String(Number(d) + tentativa).padStart(d.length, "0"));
    const { data, error } = await db.from("purchase_orders").insert({ ...cabecalho, po_number: numero }).select().single();
    if (error) {
      if (error.code === "23505" && /po_number/.test(String(error.message ?? "")) && tentativa < 2) continue;
      return { erro: `Não consegui criar a ordem de compra: ${error.message}` };
    }
    po = data;
  }
  if (!po) return { erro: "Não consegui criar a ordem de compra: número repetido três vezes seguidas. Tente de novo." };
  if (itens.length) {
    const { error: itemErr } = await db.from("purchase_order_items").insert(itens.map((it) => ({
      purchase_order_id: po.id,
      product_id: it.product_id ?? null,
      description: it.description,
      quantity: it.quantity,
      unit_cost: it.unit_cost,
    })));
    if (itemErr) {
      const { error: delErr } = await db.from("purchase_orders").delete().eq("id", po.id);
      return {
        erro: `Os itens não entraram na ordem de compra (${itemErr.message}); ${delErr ? `e a ${po.po_number} ficou criada sem itens — apague-a na tela (${delErr.message})` : `a ${po.po_number} foi desfeita`}. Nada foi criado.`,
      };
    }
  }
  return { po };
}

/** Valida e normaliza os itens ditos ({descricao|description, quantidade|quantity, custo_unitario|unit_cost}). */
export function itensDitos(lista: unknown): { itens: ItemNovoDaOC[] } | { erro: string } {
  if (lista == null) return { itens: [] };
  if (!Array.isArray(lista)) return { erro: "Os itens vêm numa lista." };
  const itens: ItemNovoDaOC[] = [];
  for (const [i, bruto] of (lista as Array<Record<string, unknown>>).entries()) {
    const description = String(bruto?.descricao ?? bruto?.description ?? "").trim();
    const quantity = Number(bruto?.quantidade ?? bruto?.quantity ?? 1);
    const unit_cost = Number(bruto?.custo_unitario ?? bruto?.unit_cost ?? 0);
    if (!description) return { erro: `O item ${i + 1} está sem descrição.` };
    if (!Number.isFinite(quantity) || quantity <= 0) return { erro: `A quantidade de "${description}" tem de ser maior que zero.` };
    if (!Number.isFinite(unit_cost) || unit_cost < 0) return { erro: `O custo de "${description}" não pode ser negativo.` };
    const product_id = typeof bruto?.product_id === "string" && UUID_RE.test(bruto.product_id) ? bruto.product_id : null;
    itens.push({ product_id, description, quantity, unit_cost });
  }
  return { itens };
}

// ─── Ordem de compra: achar a OC e os itens dela ──────────────────────────────────────────

export type OC = {
  id: string;
  po_number: string;
  status: string;
  supplier_id: string | null;
  service_order_id: string | null;
  expected_date: string | null;
  notes: string | null;
  total_amount: number | null;
  payable_id: string | null;
  created_at: string | null;
  suppliers?: { name: string; trade_name?: string | null } | null;
  service_orders?: { service_order_number: string } | null;
};

export const CAMPOS_DA_OC =
  "id, po_number, status, supplier_id, service_order_id, expected_date, notes, total_amount, payable_id, created_at, suppliers(name, trade_name), service_orders(service_order_number)";

/** "OC-00012 · Victron (enviada ao fornecedor)" — como a OC aparece numa pergunta. */
export function rotuloDaOC(oc: OC): string {
  const forn = oc.suppliers?.trade_name || oc.suppliers?.name || "sem fornecedor";
  return `${oc.po_number} · ${forn} (${SITUACAO_DA_OC[oc.status] ?? oc.status})`;
}

/**
 * Acha a OC pelo que o dono disse: o número ("OC-00012", "12"), o fornecedor ("a OC da
 * Victron" — só entre as OCs ainda em aberto, a não ser que `situacoes` diga outra coisa) ou a
 * OS/orçamento de origem. Mais de uma que serve → pergunta, com as opções.
 */
export async function localizarOC(
  // deno-lint-ignore no-explicit-any
  admin: any,
  args: { ordem_de_compra?: unknown; fornecedor?: unknown; os?: unknown; po_id?: unknown },
  situacoes: string[] = ["draft", "sent", "partial"],
): Promise<{ oc: OC } | { erro: string; opcoes?: string[] }> {
  const dita = String(args.ordem_de_compra ?? args.po_id ?? "").trim();
  const fornecedor = String(args.fornecedor ?? "").trim();
  const os = String(args.os ?? "").trim();
  const falhou = (e: { message: string }) => ({ erro: `A consulta das ordens de compra falhou (${e.message}). Tente de novo.` });

  if (dita) {
    let q = admin.from("purchase_orders").select(CAMPOS_DA_OC);
    if (UUID_RE.test(dita)) {
      q = q.eq("id", dita);
    } else {
      const digitos = dita.replace(/\D/g, "").replace(/^0+(?=\d)/, "");
      if (!digitos) return { erro: `Não entendi a ordem de compra "${dita}". Use, por exemplo, OC-00012 ou só 12.` };
      q = q.in("po_number", [`OC-${digitos.padStart(5, "0")}`, dita.toUpperCase()]);
    }
    const { data, error } = await q;
    if (error) return falhou(error);
    const achadas = (data ?? []) as OC[];
    if (achadas.length === 1) return { oc: achadas[0] };
    if (achadas.length > 1) return { erro: "Mais de uma OC com esse número. Pergunte qual.", opcoes: achadas.map(rotuloDaOC) };
    return { erro: `Não achei a ordem de compra ${dita}.` };
  }
  if (!fornecedor && !os) return { erro: "Diga qual ordem de compra: o número (OC-00012), o fornecedor ou a OS." };

  let q = admin.from("purchase_orders").select(CAMPOS_DA_OC).in("status", situacoes);
  if (os) {
    const ordem = await localizarOrdem(admin, os);
    if ("erro" in ordem) return { erro: ordem.erro };
    if ("opcoes" in ordem) return { erro: `Há mais de um documento com esse número: ${ordem.opcoes.join(" e ")}. Pergunte qual.`, opcoes: ordem.opcoes };
    q = q.eq("service_order_id", ordem.ordem.id);
  }
  const { data, error } = await q.order("created_at", { ascending: false }).limit(200);
  if (error) return falhou(error);
  let lista = (data ?? []) as OC[];
  if (fornecedor) {
    const nomes = lista.flatMap((oc) => oc.supplier_id
      ? [
        { id: oc.supplier_id, nome: oc.suppliers?.name ?? "" },
        ...(oc.suppliers?.trade_name ? [{ id: oc.supplier_id, nome: oc.suppliers.trade_name }] : []),
      ]
      : []);
    const escolha = escolherPorNome(fornecedor, nomes);
    if ("nenhum" in escolha) {
      return { erro: `Nenhuma ordem de compra ${situacoes.length === 3 ? "em aberto " : ""}é de um fornecedor chamado "${fornecedor}".` };
    }
    const ids = new Set("achado" in escolha ? [escolha.achado.id] : escolha.ambiguo.map((x) => x.id));
    lista = lista.filter((oc) => oc.supplier_id && ids.has(oc.supplier_id));
  }
  if (lista.length === 1) return { oc: lista[0] };
  if (lista.length > 1) return { erro: `Há ${lista.length} ordens de compra que servem. Pergunte qual.`, opcoes: lista.slice(0, 10).map(rotuloDaOC) };
  return { erro: `Não achei ordem de compra ${situacoes.length === 3 ? "em aberto " : ""}para isso.` };
}

export type ItemDaOC = {
  id: string;
  product_id: string | null;
  description: string;
  quantity: number;
  unit_cost: number;
  received_qty: number;
  created_at?: string | null;
  products?: { name: string } | null;
};

/** Os itens da OC na ordem em que foram lançados — é a numeração (1, 2, 3…) que o dono vê. */
// deno-lint-ignore no-explicit-any
export async function lerItensDaOC(admin: any, poId: string): Promise<{ itens: ItemDaOC[] } | { erro: string }> {
  const { data, error } = await admin.from("purchase_order_items")
    .select("id, product_id, description, quantity, unit_cost, received_qty, created_at, products(name)")
    .eq("purchase_order_id", poId)
    .order("created_at", { ascending: true });
  if (error) return { erro: `Não consegui ler os itens da ordem de compra (${error.message}).` };
  const itens = ((data ?? []) as ItemDaOC[]).map((i) => ({
    ...i,
    quantity: Number(i.quantity) || 0,
    unit_cost: Number(i.unit_cost) || 0,
    received_qty: Number(i.received_qty) || 0,
  }));
  return { itens };
}

/** Plural simples: "baterias" acha "Bateria 100Ah", "cabos" acha "Cabo PP". */
function raiz(p: string): string {
  return p.length > 4 ? p.replace(/(es|s)$/, "") : p;
}

/** O texto tem todas as palavras ditas (sem acento, singular/plural). */
export function textoTemPalavras(texto: string, dito: string): boolean {
  const t = ` ${normal(texto)} `;
  const palavras = normal(dito).split(" ").filter((p) => p.length >= 2);
  return palavras.length > 0 && palavras.every((p) => t.includes(` ${raiz(p)}`));
}

/**
 * O item que o dono apontou: pelo número na lista (n), pelo id, ou pela descrição ("as
 * baterias"). Descrição que serve a mais de um item é pergunta.
 */
export function acharItemDaOC(itens: ItemDaOC[], ref: Record<string, unknown>): { item: ItemDaOC; n: number } | { erro: string } {
  const id = String(ref?.po_item_id ?? ref?.item_id ?? "");
  if (id) {
    const i = itens.findIndex((x) => x.id === id);
    return i >= 0 ? { item: itens[i], n: i + 1 } : { erro: "Esse item não é desta ordem de compra." };
  }
  const n = Number(ref?.n ?? ref?.item ?? NaN);
  if (Number.isInteger(n) && n >= 1) {
    return n <= itens.length ? { item: itens[n - 1], n } : { erro: `A ordem de compra tem ${itens.length} itens; não existe o item ${n}.` };
  }
  const desc = String(ref?.descricao ?? ref?.description ?? "").trim();
  if (!desc) return { erro: "Diga qual item: o número dele na lista (n) ou a descrição." };
  const achados = itens.map((x, i) => ({ x, i })).filter(({ x }) => textoTemPalavras(`${x.description} ${x.products?.name ?? ""}`, desc));
  if (achados.length === 1) return { item: achados[0].x, n: achados[0].i + 1 };
  if (achados.length > 1) {
    return { erro: `"${desc}" serve a mais de um item: ${achados.map(({ x, i }) => `${i + 1}. ${x.description}`).join("; ")}. Pergunte qual (pelo número).` };
  }
  return { erro: `Nenhum item da ordem de compra é "${desc}". Itens: ${itens.map((x, i) => `${i + 1}. ${x.description}`).join("; ")}.` };
}

// ─── Cotação: achar a cotação ─────────────────────────────────────────────────────────────

export type Cotacao = {
  id: string;
  code: string;
  status: string;
  service_order_id: string | null;
  sent_supplier_ids: string[] | null;
  notes: string | null;
  created_at: string | null;
  closed_at: string | null;
};

export const CAMPOS_DA_COTACAO = "id, code, status, service_order_id, sent_supplier_ids, notes, created_at, closed_at";

/**
 * Acha a cotação pelo código ("COT-00005", "5"), pelo item ("a cotação de baterias", "do
 * cabo") ou pela OS/orçamento de origem. `situacoes` restringe a busca por item/OS (o código
 * acha sempre). Mais de uma → pergunta.
 */
export async function localizarCotacao(
  // deno-lint-ignore no-explicit-any
  admin: any,
  args: { cotacao?: unknown; quote_request_id?: unknown; code?: unknown; item?: unknown; os?: unknown },
  situacoes: string[] = ["open"],
): Promise<{ cotacao: Cotacao } | { erro: string; opcoes?: string[] }> {
  const dita = String(args.cotacao ?? args.quote_request_id ?? args.code ?? "").trim();
  const item = String(args.item ?? "").trim();
  const os = String(args.os ?? "").trim();
  const falhou = (e: { message: string }) => ({ erro: `A consulta das cotações falhou (${e.message}). Tente de novo.` });

  if (dita) {
    let q = admin.from("quote_requests").select(CAMPOS_DA_COTACAO);
    if (UUID_RE.test(dita)) {
      q = q.eq("id", dita);
    } else {
      const digitos = dita.replace(/\D/g, "").replace(/^0+(?=\d)/, "");
      if (!digitos) return { erro: `Não entendi a cotação "${dita}". Use, por exemplo, COT-00005 ou só 5.` };
      q = q.eq("code", `COT-${digitos.padStart(5, "0")}`);
    }
    const { data, error } = await q.maybeSingle();
    if (error) return falhou(error);
    return data ? { cotacao: data as Cotacao } : { erro: `Não achei a cotação ${dita}.` };
  }
  if (!item && !os) return { erro: "Diga qual cotação: o código (COT-00005), o item cotado ou a OS." };

  let q = admin.from("quote_requests").select(CAMPOS_DA_COTACAO).in("status", situacoes);
  if (os) {
    const ordem = await localizarOrdem(admin, os);
    if ("erro" in ordem) return { erro: ordem.erro };
    if ("opcoes" in ordem) return { erro: `Há mais de um documento com esse número: ${ordem.opcoes.join(" e ")}. Pergunte qual.`, opcoes: ordem.opcoes };
    q = q.eq("service_order_id", ordem.ordem.id);
  }
  const { data, error } = await q.order("created_at", { ascending: false }).limit(200);
  if (error) return falhou(error);
  let lista = (data ?? []) as Cotacao[];
  const resumoDosItens: Record<string, string> = {};
  if (lista.length) {
    const { data: itens, error: itErr } = await admin.from("quote_request_items")
      .select("quote_request_id, description, position").in("quote_request_id", lista.map((c) => c.id));
    if (itErr) return { erro: `Não consegui ler os itens das cotações (${itErr.message}). Tente de novo.` };
    const porCotacao = new Map<string, string[]>();
    for (const it of (itens ?? []) as Array<{ quote_request_id: string; description: string }>) {
      porCotacao.set(it.quote_request_id, [...(porCotacao.get(it.quote_request_id) ?? []), it.description]);
    }
    if (item) lista = lista.filter((c) => (porCotacao.get(c.id) ?? []).some((d) => textoTemPalavras(d, item)));
    for (const c of lista) {
      const ds = porCotacao.get(c.id) ?? [];
      resumoDosItens[c.id] = `${ds.length} ${ds.length === 1 ? "item" : "itens"}: ${ds.slice(0, 3).join(", ")}${ds.length > 3 ? "…" : ""}`;
    }
  }
  const qual = situacoes.length === 1 ? ` ${SITUACAO_DA_COTACAO[situacoes[0]] ?? situacoes[0]}` : "";
  if (lista.length === 1) return { cotacao: lista[0] };
  if (lista.length > 1) {
    return { erro: `Há ${lista.length} cotações${qual} que servem. Pergunte qual.`, opcoes: lista.slice(0, 10).map((c) => `${c.code} (${resumoDosItens[c.id] ?? "sem itens"})`) };
  }
  return { erro: `Não achei cotação${qual} ${item ? `com "${item}"` : "dessa OS"}.` };
}

/**
 * O fornecedor dito, entre os fornecedores EM JOGO (os da cotação, os das OCs): nome igual ou
 * cortado; vários → pergunta; nenhum → diz quem são os possíveis. Aceita o id.
 */
// deno-lint-ignore no-explicit-any
export async function fornecedorEntre(admin: any, dito: unknown, ids: string[]): Promise<{ id: string; nome: string } | { erro: string; opcoes?: string[] }> {
  const d = String(dito ?? "").trim();
  if (!d) return { erro: "Diga qual fornecedor." };
  const unicos = [...new Set(ids.filter(Boolean))];
  if (!unicos.length) return { erro: "Não há fornecedor nenhum nesta cotação." };
  const { data, error } = await admin.from("suppliers").select("id, name, trade_name").in("id", unicos);
  if (error) return { erro: `A consulta dos fornecedores falhou (${error.message}). Tente de novo.` };
  const sups = (data ?? []) as Array<{ id: string; name: string; trade_name: string | null }>;
  if (UUID_RE.test(d)) {
    const s = sups.find((x) => x.id === d);
    return s ? { id: s.id, nome: s.trade_name || s.name } : { erro: "Esse fornecedor não faz parte desta cotação." };
  }
  const nomes = sups.flatMap((s) => [{ id: s.id, nome: s.name }, ...(s.trade_name ? [{ id: s.id, nome: s.trade_name }] : [])]);
  const escolha = escolherPorNome(d, nomes);
  const nomeDe = (id: string) => {
    const s = sups.find((x) => x.id === id)!;
    return s.trade_name || s.name;
  };
  if ("achado" in escolha) return { id: escolha.achado.id, nome: nomeDe(escolha.achado.id) };
  if ("ambiguo" in escolha) {
    const idsAmb = [...new Set(escolha.ambiguo.map((x) => x.id))];
    if (idsAmb.length === 1) return { id: idsAmb[0], nome: nomeDe(idsAmb[0]) };
    return { erro: `Mais de um fornecedor serve para "${d}". Pergunte qual.`, opcoes: idsAmb.map(nomeDe) };
  }
  return { erro: `Nenhum fornecedor desta cotação se chama "${d}". Os da cotação: ${sups.map((s) => s.trade_name || s.name).join(", ")}.` };
}

// ─── Cotação → ordem de compra ────────────────────────────────────────────────────────────

/**
 * Gera a OC de UM fornecedor a partir dos preços dele na cotação e FECHA a cotação — o que a
 * tela faz em useCreatePOsFromQuote ("a decisão foi tomada, o documento cumpriu o papel").
 * Até 07/10/2026 a tool criava a OC e deixava a cotação aberta: ela seguia cobrando resposta
 * (R16/R17) de uma compra já feita.
 *
 * `somenteEscolhidos`: só os preços que o dono escolheu (apply_quote_price marca confirmed).
 * Sem isso, vale o escolhido de cada item e, onde não houver, o preço que o fornecedor deu —
 * é o "fecha com o fornecedor X" da tela (a cesta toda dele).
 */
export async function gerarOCDaCotacao(
  // deno-lint-ignore no-explicit-any
  db: any,
  // deno-lint-ignore no-explicit-any
  admin: any,
  p: { cotacao: Cotacao; supplierId: string; somenteEscolhidos: boolean; expected_date?: unknown; notes?: unknown; userId?: string | null },
): Promise<
  | { po: { id: string; po_number: string }; linhas: Array<ItemNovoDaOC & { subtotal: number }>; total: number; avisoDoFechamento: string | null }
  | { erro: string }
> {
  const { data: resps, error: rErr } = await db.from("quote_responses")
    .select("id, quote_request_item_id, unit_price, confirmed, created_at")
    .eq("quote_request_id", p.cotacao.id)
    .eq("supplier_id", p.supplierId);
  if (rErr) return { erro: `Não consegui ler os preços da cotação (${rErr.message}).` };
  // Um preço por item: o escolhido; senão o mais recente com valor.
  const porItem = new Map<string, { unit_price: number; confirmed: boolean; created_at: string }>();
  for (const r of (resps ?? []) as Array<{ quote_request_item_id: string | null; unit_price: number | null; confirmed: boolean; created_at: string | null }>) {
    if (!r.quote_request_item_id || r.unit_price == null) continue;
    if (p.somenteEscolhidos && !r.confirmed) continue;
    const atual = porItem.get(r.quote_request_item_id);
    const melhor = !atual || (r.confirmed && !atual.confirmed) ||
      (r.confirmed === atual.confirmed && String(r.created_at ?? "") > atual.created_at);
    if (melhor) porItem.set(r.quote_request_item_id, { unit_price: Number(r.unit_price), confirmed: !!r.confirmed, created_at: String(r.created_at ?? "") });
  }
  if (!porItem.size) {
    return {
      erro: p.somenteEscolhidos
        ? "Nenhum preço escolhido desse fornecedor nesta cotação. Escolha antes (apply_quote_price) — ou feche a cotação com ele gerando a OC pelos preços que ele deu."
        : "Esse fornecedor não tem preço registrado nesta cotação — registre os preços dele antes de gerar a OC.",
    };
  }
  const { data: itens, error: iErr } = await db.from("quote_request_items")
    .select("id, product_id, description, quantity, position")
    .in("id", [...porItem.keys()]);
  if (iErr) return { erro: `Não consegui ler os itens da cotação (${iErr.message}).` };
  const linhas = ((itens ?? []) as Array<{ id: string; product_id: string | null; description: string; quantity: number; position: number }>)
    .sort((a, b) => (a.position ?? 0) - (b.position ?? 0))
    .map((it) => {
      const quantity = Number(it.quantity) || 1;
      const unit_cost = porItem.get(it.id)!.unit_price;
      return { product_id: it.product_id ?? null, description: it.description, quantity, unit_cost, subtotal: Math.round(quantity * unit_cost * 100) / 100 };
    });
  if (!linhas.length) return { erro: "Não consegui montar os itens da OC a partir da cotação." };
  const total = Math.round(linhas.reduce((a, l) => a + l.subtotal, 0) * 100) / 100;

  const criada = await criarOC(db, admin, {
    supplier_id: p.supplierId,
    service_order_id: p.cotacao.service_order_id ?? null,
    expected_date: p.expected_date ?? null,
    notes: p.notes ?? `Gerada da cotação ${p.cotacao.code}`,
    status: "draft",
    total_amount: total,
    ...(p.userId ? { created_by: p.userId } : {}),
  }, linhas.map(({ subtotal: _s, ...l }) => l));
  if ("erro" in criada) return { erro: criada.erro };

  const { error: fErr } = await db.from("quote_requests")
    .update({ status: "closed", closed_at: new Date().toISOString() })
    .eq("id", p.cotacao.id);
  return {
    po: criada.po,
    linhas,
    total,
    avisoDoFechamento: fErr ? `A ${criada.po.po_number} foi criada, mas a cotação ${p.cotacao.code} não fechou (${fErr.message}) — feche pela tela.` : null,
  };
}
