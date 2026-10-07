// Ordem de compra e cotação até o fim (07/10/2026). O que estes testes protegem:
//  1. OS DEFEITOS CONFIRMADOS: OC sem po_number; erro dos itens ignorado (OC vazia "criada");
//     pedido de cotação direto, sem fila e sem quote_request_sends; preço corrigido que duplicava;
//     OC gerada da cotação que deixava a cotação aberta.
//  2. O MESMO QUE A TELA: situação da OC sem 'recebida' (isso é o recebimento, com estoque),
//     edição só de rascunho/enviada, exclusão só de rascunho, fechar/cancelar/reabrir cotação,
//     frete e desconto por upsert.
//  3. RECEBER EM PARTE CERTO: "só 2 das 4 baterias" chega à rotina do banco como 2; mais do que
//     falta, item de outra OC, item de texto livre e OC cancelada são recusados antes.
//  4. LEITURA QUE FALHA não vira "não achei" nem "lista vazia".
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { FakeTime } from "https://deno.land/std@0.224.0/testing/time.ts";
import { comprasCicloTools, resumirExclusaoDeOC, resumirRecebimento } from "./compras-ciclo.ts";
import { purchasingTools } from "./purchasing.ts";
import { quoteTools } from "./quotes.ts";
import { whatsappTools } from "./whatsapp.ts";

type Linha = Record<string, unknown>;
type Erro = { message: string; code?: string };

/** Banco de mentira que filtra e grava de verdade. `falham`: leitura com erro; `falhaEscrita`: escrita com erro. */
function bancoFalso(tabelas: Record<string, Linha[]>, opcoes: { falham?: string[]; falhaEscrita?: Record<string, Erro> } = {}) {
  const escritas: Array<{ tabela: string; op: string; valores: unknown }> = [];
  const rpcs: Array<{ nome: string; args: Record<string, unknown> }> = [];
  let seq = 0;
  const from = (tabela: string) => {
    let op = "select";
    let valores: unknown = null;
    let conflito: string[] = [];
    const filtros: Array<(l: Linha) => boolean> = [];
    let ordem: [string, boolean] | null = null;
    let limite: number | null = null;
    let unico = false;
    const run = () => {
      const linhas = (tabelas[tabela] ??= []);
      if (op === "select") {
        if (opcoes.falham?.includes(tabela)) return { data: null, error: { message: `falha em ${tabela}` } };
        let r = linhas.filter((l) => filtros.every((f) => f(l)));
        if (ordem) {
          const [c, asc] = ordem;
          r = [...r].sort((a, b) => String(a[c] ?? "").localeCompare(String(b[c] ?? "")) * (asc ? 1 : -1));
        }
        if (limite != null) r = r.slice(0, limite);
        return { data: unico ? (r[0] ?? null) : r, error: null };
      }
      const erro = opcoes.falhaEscrita?.[`${tabela}:${op}`] ?? opcoes.falhaEscrita?.[tabela];
      if (erro) return { data: null, error: erro };
      escritas.push({ tabela, op, valores });
      if (op === "insert") {
        const arr = ((Array.isArray(valores) ? valores : [valores]) as Linha[]).map((v) => ({
          id: `${tabela}-${++seq}`,
          created_at: new Date(Date.UTC(2026, 9, 7, 12, 0, seq)).toISOString(),
          ...v,
        }));
        linhas.push(...arr);
        return { data: unico ? arr[0] : arr, error: null };
      }
      if (op === "update") {
        const alvo = linhas.filter((l) => filtros.every((f) => f(l)));
        for (const l of alvo) Object.assign(l, valores);
        return { data: alvo, error: null };
      }
      if (op === "delete") {
        const fora = linhas.filter((l) => filtros.every((f) => f(l)));
        tabelas[tabela] = linhas.filter((l) => !fora.includes(l));
        return { data: fora, error: null };
      }
      if (op === "upsert") {
        const v = valores as Linha;
        const existente = linhas.find((l) => conflito.every((c) => l[c] === v[c]));
        if (existente) Object.assign(existente, v);
        else linhas.push({ ...v });
        return { data: null, error: null };
      }
      return { data: null, error: null };
    };
    // deno-lint-ignore no-explicit-any
    const q: any = {
      select: () => q,
      insert: (v: unknown) => { op = "insert"; valores = v; return q; },
      update: (v: unknown) => { op = "update"; valores = v; return q; },
      delete: () => { op = "delete"; return q; },
      upsert: (v: unknown, o?: { onConflict?: string }) => { op = "upsert"; valores = v; conflito = String(o?.onConflict ?? "").split(","); return q; },
      eq: (c: string, v: unknown) => { filtros.push((l) => l[c] === v); return q; },
      neq: (c: string, v: unknown) => { filtros.push((l) => l[c] !== v); return q; },
      in: (c: string, vs: unknown[]) => { filtros.push((l) => vs.includes(l[c])); return q; },
      order: (c: string, o?: { ascending?: boolean }) => { ordem = [c, o?.ascending !== false]; return q; },
      limit: (n: number) => { limite = n; return q; },
      range: () => q,
      single: () => { unico = true; return q; },
      maybeSingle: () => { unico = true; return q; },
      then: (ok: (v: unknown) => unknown, erro?: (e: unknown) => unknown) => Promise.resolve(run()).then(ok, erro),
    };
    return q;
  };
  const db = {
    from,
    rpc: (nome: string, args: Record<string, unknown>) => {
      rpcs.push({ nome, args });
      return Promise.resolve({ data: { status: "partial", payable_id: null, all_received: false }, error: null });
    },
  };
  return { db, escritas, rpcs, tabelas };
}

const VICTRON = { id: "s-victron", name: "VICTRON ENERGY DISTRIBUIDORA LTDA", trade_name: "Victron", phone: "47 99915-9654", opt_out_whatsapp: false };
const LOJA = { id: "s-loja", name: "LOJA DO CABO", trade_name: null, phone: "4733334444", opt_out_whatsapp: false };
const SEM_ZAP = { id: "s-semzap", name: "FORNECEDOR SEM TELEFONE", trade_name: null, phone: null, opt_out_whatsapp: false };

const ORC80 = { id: "33333333-3333-4333-8333-333333333080", service_order_number: "ORÇ-00080", status: "draft", share_token: "t", updated_at: null, client_id: "c1" };

function ambiente(opcoes: { falham?: string[]; falhaEscrita?: Record<string, Erro> } = {}) {
  return bancoFalso({
    suppliers: [VICTRON, LOJA, SEM_ZAP],
    service_orders: [ORC80],
    purchase_orders: [
      { id: "po-12", po_number: "OC-00012", status: "sent", supplier_id: "s-victron", service_order_id: null, expected_date: null, notes: null, total_amount: 4000, payable_id: null, created_at: "2026-10-01T10:00:00Z", suppliers: { name: VICTRON.name, trade_name: "Victron" }, service_orders: null },
      { id: "po-13", po_number: "OC-00013", status: "draft", supplier_id: "s-loja", service_order_id: null, expected_date: null, notes: null, total_amount: 100, payable_id: null, created_at: "2026-10-02T10:00:00Z", suppliers: { name: LOJA.name, trade_name: null }, service_orders: null },
      { id: "po-14", po_number: "OC-00014", status: "partial", supplier_id: "s-loja", service_order_id: null, expected_date: null, notes: null, total_amount: 300, payable_id: null, created_at: "2026-10-03T10:00:00Z", suppliers: { name: LOJA.name, trade_name: null }, service_orders: null },
    ],
    purchase_order_items: [
      { id: "i-bat", purchase_order_id: "po-12", product_id: "p-bat", description: "Bateria Lítio 100Ah", quantity: 4, unit_cost: 900, received_qty: 0, created_at: "2026-10-01T10:00:01Z" },
      { id: "i-inv", purchase_order_id: "po-12", product_id: "p-inv", description: "Inversor 3000W", quantity: 1, unit_cost: 400, received_qty: 0, created_at: "2026-10-01T10:00:02Z" },
      { id: "i-cabo", purchase_order_id: "po-13", product_id: null, description: "Cabo PP 2x2,5", quantity: 10, unit_cost: 10, received_qty: 0, created_at: "2026-10-02T10:00:01Z" },
      { id: "i-parcial", purchase_order_id: "po-14", product_id: "p-x", description: "Terminal", quantity: 30, unit_cost: 10, received_qty: 10, created_at: "2026-10-03T10:00:01Z" },
    ],
    quote_requests: [
      { id: "q-bat", code: "COT-00005", status: "open", service_order_id: ORC80.id, sent_supplier_ids: ["s-victron", "s-semzap"], notes: null, created_at: "2026-10-01T09:00:00Z", closed_at: null },
      { id: "q-cabo", code: "COT-00006", status: "open", service_order_id: null, sent_supplier_ids: ["s-loja"], notes: "interno", created_at: "2026-10-02T09:00:00Z", closed_at: null },
    ],
    quote_request_items: [
      { id: "qi-1", quote_request_id: "q-bat", position: 1, description: "Bateria Lítio 100Ah", quantity: 2, product_id: "p-bat" },
      { id: "qi-2", quote_request_id: "q-bat", position: 2, description: "Inversor 3000W", quantity: 1, product_id: null },
      { id: "qi-3", quote_request_id: "q-cabo", position: 1, description: "Cabo PP 2x2,5", quantity: 50, product_id: null },
    ],
    quote_responses: [
      { id: "r-1", quote_request_id: "q-bat", supplier_id: "s-victron", quote_request_item_id: "qi-1", unit_price: 950, confirmed: false, created_at: "2026-10-02T09:00:00Z" },
      { id: "r-2", quote_request_id: "q-bat", supplier_id: "s-victron", quote_request_item_id: "qi-2", unit_price: 3000, confirmed: true, created_at: "2026-10-02T09:00:00Z" },
    ],
    quote_request_sends: [],
    quote_request_supplier_terms: [],
    whatsapp_send_queue: [],
    ai_comms_log: [],
  }, opcoes);
}

const ONZE_DA_MANHA = new Date("2026-10-07T14:00:00.000Z");
const todas = [...comprasCicloTools, ...purchasingTools, ...quoteTools, ...whatsappTools];

async function rodar(nome: string, args: Record<string, unknown>, amb = ambiente(), role = "admin", settings: Record<string, string> = { company_name: "HBR Marine" }) {
  const relogio = new FakeTime(ONZE_DA_MANHA);
  try {
    const tool = todas.find((t) => t.name === nome)!;
    const ctx = { sb: amb.db, admin: amb.db, userId: "u-admin", userRole: role, jwt: "", appOrigin: "", settings } as never;
    // deno-lint-ignore no-explicit-any
    return await tool.execute(args, ctx) as any;
  } finally {
    relogio.restore();
  }
}

// ─── Defeitos confirmados ──────────────────────────────────────────────────────────────────
Deno.test("create_purchase_order: preenche po_number (o próximo depois do último) e grava os itens", async () => {
  const amb = ambiente();
  const r = await rodar("create_purchase_order", { supplier_id: "s-loja", items: [{ description: "Cabo", quantity: 5, unit_cost: 12 }] }, amb);
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(r.ordem_de_compra, "OC-00015");
  const po = amb.tabelas.purchase_orders.find((p) => p.po_number === "OC-00015")!;
  assertEquals(po.status, "draft");
  assertEquals(amb.tabelas.purchase_order_items.filter((i) => i.purchase_order_id === po.id).length, 1);
});

Deno.test("create_purchase_order: item que não entra desfaz a OC e diz o erro (antes: OC vazia 'criada')", async () => {
  const amb = ambiente({ falhaEscrita: { "purchase_order_items:insert": { message: "violates check" } } });
  const r = await rodar("create_purchase_order", { supplier_id: "s-loja", items: [{ description: "Cabo", quantity: 5, unit_cost: 12 }] }, amb);
  assertStringIncludes(r.error, "não entraram");
  assertEquals(amb.tabelas.purchase_orders.some((p) => p.po_number === "OC-00015"), false);
});

Deno.test("create_purchase_order_from_so: mesma correção — item que falha não deixa OC nem move a OS", async () => {
  const amb = ambiente({ falhaEscrita: { "purchase_order_items:insert": { message: "fk" } } });
  const r = await rodar("create_purchase_order_from_so", { service_order_id: ORC80.id, product_id: "p-bat", product_name: "Bateria", quantity: 1, unit_cost: 900 }, amb);
  assert(r.error, JSON.stringify(r));
  assertEquals(amb.tabelas.purchase_orders.length, 3);
  assertEquals(amb.escritas.some((e) => e.tabela === "service_orders"), false);
});

Deno.test("create_purchase_order_from_quote: gera a OC com os escolhidos e FECHA a cotação", async () => {
  const amb = ambiente();
  const r = await rodar("create_purchase_order_from_quote", { code: "COT-00005", supplier_id: "s-victron" }, amb);
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(r.ordem_de_compra, "OC-00015");
  assertEquals(r.itens.length, 1); // só o escolhido (confirmed)
  assertEquals(r.cotacao_fechada, true);
  assertEquals(amb.tabelas.quote_requests.find((q) => q.id === "q-bat")!.status, "closed");
});

Deno.test("record_quote_response: corrigir o preço SUBSTITUI (não empilha outra oferta do mesmo fornecedor)", async () => {
  const amb = ambiente();
  const r = await rodar("record_quote_response", { code: "COT-00005", supplier_id: "s-victron", item_position: 1, unit_price: 920, source: "text" }, amb);
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(r.response_id, "r-1");
  const doItem = amb.tabelas.quote_responses.filter((x) => x.quote_request_item_id === "qi-1" && x.supplier_id === "s-victron");
  assertEquals(doItem.length, 1);
  assertEquals(doItem[0].unit_price, 920);
  // Fornecedor que ainda não respondeu aquele item: insere.
  const novo = await rodar("record_quote_response", { code: "COT-00005", supplier_id: "s-semzap", item_position: 1, unit_price: 990 }, amb);
  assertEquals(novo.ok, true);
  assertEquals(amb.tabelas.quote_responses.length, 3);
});

Deno.test("record_quote_response: leitura que falha não vira 'cotação não encontrada'", async () => {
  const r = await rodar("record_quote_response", { code: "COT-00005", supplier_id: "s-victron", item_position: 1, unit_price: 1 }, ambiente({ falham: ["quote_requests"] }));
  assertStringIncludes(r.error, "consulta da cotação falhou");
});

Deno.test("send_supplier_quote_request: vai pela FILA e grava quote_request_sends, como a tela; sem WhatsApp é pulado", async () => {
  const amb = ambiente();
  const r = await rodar("send_supplier_quote_request", { quote_request_id: "COT-00005" }, amb);
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(r.enviados, 1);
  assertEquals(amb.tabelas.whatsapp_send_queue.length, 1);
  const fila = amb.tabelas.whatsapp_send_queue[0];
  assertEquals(fila.phone_normalized, "5547999159654");
  assertEquals(fila.source, "quote_request");
  assertEquals(fila.source_ref_id, "q-bat");
  assertEquals(fila.priority, 2);
  // A mensagem da tela, palavra por palavra.
  assertEquals(fila.message, "Olá, tudo bem? Aqui é da HBR Marine.\nGostaríamos de uma cotação (COT-00005):\n1. 2x Bateria Lítio 100Ah\n2. 1x Inversor 3000W\n\nObrigado!");
  assertEquals(amb.tabelas.quote_request_sends.length, 1);
  assertEquals(amb.tabelas.quote_request_sends[0].queue_id, fila.id);
  assertEquals(amb.tabelas.quote_request_sends[0].supplier_id, "s-victron");
  assert(r.resultados.some((x: { status: string }) => x.status === "sem WhatsApp cadastrado"));
});

Deno.test("send_supplier_quote_request: modo de teste desvia para o número de teste; ligado sem número, recusa", async () => {
  const amb = ambiente();
  const r = await rodar("send_supplier_quote_request", { quote_request_id: "COT-00005" }, amb, "admin", { company_name: "HBR", wa_test_mode: "true", wa_test_number: "5547900001111" });
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(amb.tabelas.whatsapp_send_queue[0].phone_normalized, "5547900001111");
  const sem = await rodar("send_supplier_quote_request", { quote_request_id: "COT-00005" }, ambiente(), "admin", { wa_test_mode: "true" });
  assertStringIncludes(sem.error, "sem número de teste");
});

Deno.test("send_supplier_quote_request: sem cotação é recusado antes da pendência; leitura que falha não envia", async () => {
  const tool = whatsappTools.find((t) => t.name === "send_supplier_quote_request")!;
  assertStringIncludes(tool.preValidar!({ supplier_ids: ["s-loja"], items: [{ description: "x" }] }, {} as never)!.error, "create_quote_request");
  assertEquals(tool.preValidar!({ quote_request_id: "COT-00005" }, {} as never), null);
  const amb = ambiente({ falham: ["quote_request_items"] });
  const r = await rodar("send_supplier_quote_request", { quote_request_id: "COT-00005" }, amb);
  assertStringIncludes(r.error, "itens da cotação falhou");
  assertEquals(amb.tabelas.whatsapp_send_queue.length, 0);
  // Repetido no mesmo dia: o índice único da fila (dedupe_key) recusa → "já enviado hoje".
  const repetido = await rodar("send_supplier_quote_request", { quote_request_id: "COT-00005" }, ambiente({ falhaEscrita: { "whatsapp_send_queue:insert": { message: "duplicate key", code: "23505" } } }));
  assertStringIncludes(repetido.error, "já enviado hoje");
});

// ─── Ordem de compra ───────────────────────────────────────────────────────────────────────
Deno.test("situação: 'marca a OC da Victron como enviada' acha pela marca; recebida não se marca aqui", async () => {
  const amb = ambiente();
  const r = await rodar("update_purchase_order_status", { fornecedor: "Loja do Cabo", situacao: "enviada" }, amb);
  // A Loja tem duas OCs em aberto (rascunho e recebida em parte): pergunta.
  assert(r.error && r.opcoes?.length === 2, JSON.stringify(r));
  const ok = await rodar("update_purchase_order_status", { ordem_de_compra: "13", situacao: "enviada" }, amb);
  assertEquals(ok.ok, true, JSON.stringify(ok));
  assertEquals(amb.tabelas.purchase_orders.find((p) => p.id === "po-13")!.status, "sent");
  const ja = await rodar("update_purchase_order_status", { fornecedor: "Victron", situacao: "enviada" }, amb);
  assertStringIncludes(ja.aviso, "já está");
  const recebida = await rodar("update_purchase_order_status", { ordem_de_compra: "OC-00012", situacao: "recebida" }, amb);
  assertStringIncludes(recebida.error, "receive_purchase_order");
});

Deno.test("situação: cancelar anota o motivo; OC recebida em parte não se cancela (ficaria sem conta a pagar)", async () => {
  const amb = ambiente();
  const r = await rodar("update_purchase_order_status", { ordem_de_compra: "OC-00012", situacao: "cancelada", motivo: "comprei direto na loja" }, amb);
  assertEquals(r.ok, true, JSON.stringify(r));
  const po = amb.tabelas.purchase_orders.find((p) => p.id === "po-12")!;
  assertEquals(po.status, "cancelled");
  assertStringIncludes(String(po.notes), "comprei direto na loja");
  const parcial = await rodar("update_purchase_order_status", { ordem_de_compra: "OC-00014", situacao: "cancelada" }, amb);
  assertStringIncludes(parcial.error, "recebida em parte");
  assertEquals(amb.tabelas.purchase_orders.find((p) => p.id === "po-14")!.status, "partial");
});

Deno.test("editar OC: muda quantidade, acrescenta e remove item; recebida em parte não se edita", async () => {
  const amb = ambiente();
  const r = await rodar("update_purchase_order", {
    ordem_de_compra: "OC-00012",
    previsao: "25/10/2026",
    alterar_itens: [{ descricao: "baterias", quantidade: 6 }],
    adicionar_itens: [{ descricao: "Fusível 200A", quantidade: 2, custo_unitario: 50 }],
    remover_itens: [{ n: 2 }],
  }, amb);
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(amb.tabelas.purchase_orders.find((p) => p.id === "po-12")!.expected_date, "2026-10-25");
  const itens = amb.tabelas.purchase_order_items.filter((i) => i.purchase_order_id === "po-12");
  assertEquals(itens.map((i) => i.description).sort(), ["Bateria Lítio 100Ah", "Fusível 200A"]);
  assertEquals(itens.find((i) => i.id === "i-bat")!.quantity, 6);
  const parcial = await rodar("update_purchase_order", { ordem_de_compra: "OC-00014", observacoes: "x" }, amb);
  assertStringIncludes(parcial.error, "só rascunho e enviada");
});

Deno.test("excluir OC: só rascunho; enviada é recusada", async () => {
  const amb = ambiente();
  const enviada = await rodar("delete_purchase_order", { ordem_de_compra: "OC-00012" }, amb);
  assertStringIncludes(enviada.error, "só rascunho");
  const ok = await rodar("delete_purchase_order", { ordem_de_compra: "OC-00013" }, amb);
  assertEquals(ok.ok, true, JSON.stringify(ok));
  assertEquals(amb.tabelas.purchase_orders.some((p) => p.id === "po-13"), false);
});

Deno.test("receber em parte: 'a OC-00012 chegou incompleta, recebe só 2 das 4 baterias' chega à rotina como 2", async () => {
  const amb = ambiente();
  const r = await rodar("receive_purchase_order", { ordem_de_compra: "OC-00012", itens: [{ descricao: "baterias", quantidade: 2 }] }, amb);
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(amb.rpcs.length, 1);
  assertEquals(amb.rpcs[0].nome, "receive_po");
  assertEquals(amb.rpcs[0].args.p_po_id, "po-12");
  assertEquals(amb.rpcs[0].args.p_items, [{ po_item_id: "i-bat", received_qty: 2 }]);
  assertStringIncludes(r.conta_a_pagar, "quando a OC fica completa");
});

Deno.test("receber: mais do que falta, item de texto livre, OC cancelada e item de outra OC são recusados ANTES da rotina", async () => {
  const amb = ambiente();
  const demais = await rodar("receive_purchase_order", { ordem_de_compra: "OC-00014", itens: [{ n: 1, quantidade: 25 }] }, amb);
  assertStringIncludes(demais.error, "só faltam 20");
  const texto = await rodar("receive_purchase_order", { ordem_de_compra: "OC-00013", receber_tudo: true }, amb);
  assertStringIncludes(texto.error, "texto livre");
  const deOutra = await rodar("receive_purchase_order", { po_id: "po-12", items: [{ po_item_id: "i-cabo", received_qty: 1 }] }, amb);
  assertStringIncludes(deOutra.error, "não é desta ordem de compra");
  amb.tabelas.purchase_orders.find((p) => p.id === "po-12")!.status = "cancelled";
  const cancelada = await rodar("receive_purchase_order", { ordem_de_compra: "OC-00012", receber_tudo: true }, amb);
  assertStringIncludes(cancelada.error, "cancelada");
  assertEquals(amb.rpcs.length, 0);
  const lida = await rodar("receive_purchase_order", { ordem_de_compra: "OC-00012", receber_tudo: true }, ambiente({ falham: ["purchase_order_items"] }));
  assertStringIncludes(lida.error, "Não consegui ler os itens");
});

Deno.test("resumo do recebimento: o que chega, de quanto faltava, e quando nasce a conta a pagar", async () => {
  const amb = ambiente();
  const parcial = await resumirRecebimento(amb.db, { ordem_de_compra: "OC-00012", itens: [{ descricao: "bateria", quantidade: 2 }] });
  assertStringIncludes(parcial, "2 de 4 que faltavam");
  assertStringIncludes(parcial, "recebida em parte");
  const tudo = await resumirRecebimento(amb.db, { ordem_de_compra: "OC-00012", receber_tudo: true });
  assertStringIncludes(tudo, "COMPLETA");
  assertStringIncludes(tudo, "R$");
  const ruim = await resumirRecebimento(amb.db, { ordem_de_compra: "OC-00099", receber_tudo: true });
  assert(ruim.startsWith("⚠️") && !ruim.includes("\n"));
});

Deno.test("compras é do admin e do financeiro: vendedor é recusado mesmo pelo WhatsApp (sem RLS)", async () => {
  const r = await rodar("update_purchase_order_status", { ordem_de_compra: "OC-00013", situacao: "enviada" }, ambiente(), "seller");
  assertStringIncludes(r.error, "administrador e do financeiro");
  const rec = await rodar("receive_purchase_order", { ordem_de_compra: "OC-00012", receber_tudo: true }, ambiente(), "seller");
  assertStringIncludes(rec.error, "administrador e do financeiro");
});

// ─── Cotação ───────────────────────────────────────────────────────────────────────────────
Deno.test("listar cotações: abertas por item; leitura que falha não vira lista vazia", async () => {
  const r = await rodar("list_quote_requests", { item: "baterias" });
  assertEquals(r.count, 1, JSON.stringify(r));
  assertEquals(r.results[0].codigo, "COT-00005");
  assertEquals(r.results[0].os, "ORÇ-00080");
  assertEquals(r.results[0].responderam, ["Victron"]);
  const falha = await rodar("list_quote_requests", {}, ambiente({ falham: ["quote_responses"] }));
  assertStringIncludes(falha.error, "respostas");
});

Deno.test("'cancela a cotação de baterias, comprei direto na loja' → cancelada com o motivo; reabrir volta a aberta", async () => {
  const amb = ambiente();
  const r = await rodar("close_quote_request", { item: "baterias", acao: "cancelar", motivo: "comprei direto na loja" }, amb);
  assertEquals(r.ok, true, JSON.stringify(r));
  const q = amb.tabelas.quote_requests.find((x) => x.id === "q-bat")!;
  assertEquals(q.status, "cancelled");
  assert(q.closed_at);
  assertStringIncludes(String(q.notes), "comprei direto na loja");
  const re = await rodar("reopen_quote_request", { cotacao: "COT-00005" }, amb);
  assertEquals(re.ok, true, JSON.stringify(re));
  assertEquals(q.status, "open");
  assertEquals(q.closed_at, null);
});

Deno.test("'fecha a cotação do cabo com o fornecedor X sem gerar OC' → fechada, fornecedor anotado, nenhuma OC", async () => {
  const amb = ambiente();
  const r = await rodar("close_quote_request", { item: "cabo", acao: "fechar", fornecedor: "Loja do Cabo" }, amb);
  assertEquals(r.ok, true, JSON.stringify(r));
  const q = amb.tabelas.quote_requests.find((x) => x.id === "q-cabo")!;
  assertEquals(q.status, "closed");
  assertStringIncludes(String(q.notes), "interno\nFechada em");
  assertStringIncludes(String(q.notes), "LOJA DO CABO");
  assertEquals(amb.tabelas.purchase_orders.length, 3);
  // Fornecedor que não é da cotação não é aceito por parecença.
  const outro = await rodar("close_quote_request", { cotacao: "COT-00005", acao: "fechar", fornecedor: "Loja" }, amb);
  assertStringIncludes(outro.error, "Nenhum fornecedor desta cotação");
});

Deno.test("fechar com gerar_oc: OC com os preços do fornecedor (escolhido ou não) e cotação fechada", async () => {
  const amb = ambiente();
  const r = await rodar("close_quote_request", { cotacao: "5", acao: "fechar", fornecedor: "Victron", gerar_oc: true }, amb);
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(r.ordem_de_compra, "OC-00015");
  assertEquals(r.itens.length, 2);
  assertEquals(r.total, 2 * 950 + 3000);
  assertEquals(amb.tabelas.quote_requests.find((x) => x.id === "q-bat")!.status, "closed");
});

Deno.test("frete e desconto: upsert por (cotação, fornecedor); campo não dito fica como estava", async () => {
  const amb = ambiente();
  const r = await rodar("set_quote_supplier_terms", { cotacao: "COT-00005", fornecedor: "Victron", frete: 80, desconto: 50 }, amb);
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(r.pacote, 2 * 950 + 3000 - 50 + 80);
  const so = await rodar("set_quote_supplier_terms", { cotacao: "COT-00005", fornecedor: "Victron", frete: 0 }, amb);
  assertEquals(so.ok, true);
  assertEquals(amb.tabelas.quote_request_supplier_terms.length, 1);
  assertEquals(amb.tabelas.quote_request_supplier_terms[0].freight, 0);
  assertEquals(amb.tabelas.quote_request_supplier_terms[0].discount, 50);
  const neg = await rodar("set_quote_supplier_terms", { cotacao: "COT-00005", fornecedor: "Victron", frete: -1 }, amb);
  assertStringIncludes(neg.error, "zero ou mais");
});

Deno.test("resumo da exclusão: rascunho mostra itens e total; enviada vira uma linha ⚠️ (recusa antes do 'sim')", async () => {
  const amb = ambiente();
  const ok = await resumirExclusaoDeOC(amb.db, { ordem_de_compra: "OC-00013" });
  assertStringIncludes(ok, "EXCLUIR a *OC-00013*");
  assertStringIncludes(ok, "Cabo PP 2x2,5");
  const enviada = await resumirExclusaoDeOC(amb.db, { ordem_de_compra: "OC-00012" });
  assert(enviada.startsWith("⚠️") && !enviada.includes("\n"), enviada);
});
