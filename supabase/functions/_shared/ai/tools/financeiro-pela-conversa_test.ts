// Financeiro pela conversa (07/10/2026): o que só a tela fazia — anotação de Pix que espera o banco,
// estorno de pagamento, cobrança formal e favorecido. O que se fixa aqui: como o pedido dito vira o
// alvo certo (ou a pergunta), o que vai para o banco (mesmos campos da tela, p_autor nas funções que
// conferem quem pede) e que leitura que falha vira "a consulta falhou", nunca "não há".
// Rodar com:
//   deno test --allow-all supabase/functions/_shared/ai/tools/financeiro-pela-conversa_test.ts
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { anotacaoTools, resumirAnotacao } from "./anotacoes.ts";
import { estornoTools, resumirEstorno } from "./estorno.ts";
import { cobrancaTools, registrarEnvioDaCobranca, resumirCobranca } from "./cobrancas.ts";
import { contaAPagarDita, favorecidoTools, marcarPausa, resumirFavorecido, tipoDaChave, tirarPausa } from "./favorecidos.ts";
import { casaNome, dataFuturaDita } from "./financeiro-comum.ts";
import { financialTools } from "./financial.ts";
import { NEVER_AUTONOMOUS } from "../autonomy-policy.ts";
import { CHAVE_DO_RETRATO } from "./registry.ts";
import { hojeEmBrasilia, somarDias } from "../../banking/fluxo-de-caixa.ts";

/** Datas relativas a hoje: o que se testa é "há quantos dias", não o calendário do dia do teste. */
const DIAS = (n: number) => somarDias(hojeEmBrasilia(), n);

// ── Banco falso: tabelas por nome, filtros encadeados, escritas registradas ──────────────────────

type Linha = Record<string, any>;
type Escrita = { tabela: string; op: "update" | "insert"; valores: Linha; ids: string[] };

function banco(tabelas: Record<string, Linha[]>, opcoes: { falha?: string[]; rpc?: Record<string, { data?: unknown; error?: { message: string } }> } = {}) {
  const escritas: Escrita[] = [];
  const rpcs: Array<{ n: string; a: Linha }> = [];
  const from = (tabela: string) => {
    const filtros: Array<(l: Linha) => boolean> = [];
    let op: "select" | "update" | "insert" = "select";
    let valores: Linha = {};
    let limite = Infinity;
    const linhas = () => (tabelas[tabela] ?? []).filter((l) => filtros.every((f) => f(l)));
    const resultado = () => {
      if (opcoes.falha?.includes(tabela)) return { data: null, error: { message: `falhou ${tabela}` } };
      if (op === "insert") {
        const nova = { id: `novo-${tabela}-${escritas.length}`, ...valores };
        escritas.push({ tabela, op, valores, ids: [nova.id] });
        return { data: [nova], error: null };
      }
      const alvo = linhas();
      if (op === "update") {
        escritas.push({ tabela, op, valores, ids: alvo.map((l) => l.id) });
        for (const l of alvo) Object.assign(l, valores);
      }
      return { data: alvo.slice(0, limite), error: null };
    };
    const q: any = {
      select: () => q, order: () => q, range: () => q,
      limit: (n: number) => { limite = n; return q; },
      eq: (c: string, v: unknown) => { filtros.push((l) => l[c] === v); return q; },
      neq: (c: string, v: unknown) => { filtros.push((l) => l[c] !== v); return q; },
      in: (c: string, vs: unknown[]) => { filtros.push((l) => vs.includes(l[c])); return q; },
      gte: (c: string, v: any) => { filtros.push((l) => l[c] >= v); return q; },
      lte: (c: string, v: any) => { filtros.push((l) => l[c] <= v); return q; },
      lt: (c: string, v: any) => { filtros.push((l) => l[c] < v); return q; },
      not: (c: string, o: string, v: unknown) => { filtros.push((l) => (o === "is" && v === null ? l[c] != null : true)); return q; },
      ilike: (c: string, p: string) => { const t = p.replaceAll("%", "").toLowerCase(); filtros.push((l) => String(l[c] ?? "").toLowerCase().includes(t)); return q; },
      update: (v: Linha) => { op = "update"; valores = v; return q; },
      insert: (v: Linha) => { op = "insert"; valores = v; return q; },
      maybeSingle: () => { const r = resultado(); return Promise.resolve({ data: r.data?.[0] ?? null, error: r.error }); },
      single: () => { const r = resultado(); return Promise.resolve({ data: r.data?.[0] ?? null, error: r.error }); },
      then: (ok: any, ko: any) => Promise.resolve(resultado()).then(ok, ko),
    };
    return q;
  };
  const rpc = (n: string, a: Linha) => {
    rpcs.push({ n, a });
    const r = opcoes.rpc?.[n] ?? { data: { ok: true, message: `${n} feito` } };
    return Promise.resolve({ data: r.data ?? null, error: r.error ?? null });
  };
  return { from, rpc, escritas, rpcs };
}

function ctx(db: ReturnType<typeof banco>, cargo = "admin") {
  return { sb: db, admin: db, userId: "u-dono", userRole: cargo as any, jwt: "", appOrigin: "", settings: {} };
}

const sem = (s: unknown) => String(s).replace(/ /g, " ");
const tool = (lista: { name: string }[], nome: string) => lista.find((t) => t.name === nome)! as any;

// ── Peças comuns ──────────────────────────────────────────────────────────────────────────────────

Deno.test("data para a frente: sexta, dia 20, amanhã, dd/mm", () => {
  const quarta = new Date("2026-10-07T15:00:00Z"); // quarta, 12h em Brasília
  assertEquals(dataFuturaDita("sexta", quarta), "2026-10-09");
  assertEquals(dataFuturaDita("sexta-feira", quarta), "2026-10-09");
  assertEquals(dataFuturaDita("quarta", quarta), "2026-10-07");
  assertEquals(dataFuturaDita("dia 20", quarta), "2026-10-20");
  assertEquals(dataFuturaDita("dia 5", quarta), "2026-11-05");
  assertEquals(dataFuturaDita("amanhã", quarta), "2026-10-08");
  assertEquals(dataFuturaDita("10/11", quarta), "2026-11-10");
  assertEquals(dataFuturaDita("semana que vem", quarta), null);
});

Deno.test("nome igual ou cortado identifica; parecido não", () => {
  assert(casaNome("eliane", "Eliane Souza"));
  assert(casaNome("Flávio", "FLAVIO RODRIGUES"));
  assert(!casaNome("elaine", "Eliane Souza"));
  assert(!casaNome("", "Eliane"));
});

// ── 1. Anotações de Pix que esperam o banco ──────────────────────────────────────────────────────

function anotacoes(falha = false) {
  return banco({
    anotacoes_do_extrato: [
      { id: "an-eli", sentido: "debit", valor: 493, data_prevista: DIAS(-2), data_exata: false, nome: "Eliane", categoria: "Alimentação de campo",
        descricao: null, status: "aguardando", criada_em: "2026-10-05T12:00:00Z", suppliers: null, payees: null, clients: null, service_orders: null },
      { id: "an-tsd", sentido: "debit", valor: 1500, data_prevista: DIAS(-17), data_exata: true, nome: null, categoria: "Peças e materiais",
        descricao: null, status: "aguardando", criada_em: "2026-09-20T12:00:00Z", suppliers: { name: "TSD Distribuidora" }, payees: null, clients: null, service_orders: null },
      { id: "an-eli2", sentido: "debit", valor: 80, data_prevista: DIAS(-1), data_exata: false, nome: "Eliane", categoria: "Alimentação de campo",
        descricao: null, status: "aguardando", criada_em: "2026-10-06T12:00:00Z", suppliers: null, payees: null, clients: null, service_orders: null },
    ],
    financial_categories: [{ name: "Alimentação de campo", type: "payable", active: true }, { name: "Peças e materiais", type: "payable", active: true }],
  }, { falha: falha ? ["anotacoes_do_extrato"] : [], rpc: { corrigir_anotacao: { data: { ok: true, corrigida: true, message: "Anotado." } } } });
}

Deno.test("anotações: lista as que esperam, com quem, valor e há quantos dias; parada há mais de uma semana", async () => {
  const db = anotacoes();
  const r = await tool(anotacaoTools, "listar_anotacoes_do_extrato").execute({}, ctx(db));
  assertEquals(r.total, 3);
  assertEquals(r.anotacoes.find((a: any) => a.anotacao_id === "an-tsd").quem, "TSD Distribuidora");
  const paradas = await tool(anotacaoTools, "listar_anotacoes_do_extrato").execute({ parada_ha_mais_de_dias: 7 }, ctx(db));
  assertEquals(paradas.anotacoes.map((a: any) => a.anotacao_id), ["an-tsd"]);
  assertStringIncludes(paradas.anotacoes[0].aviso, "confira se o Pix saiu");
});

Deno.test("anotações: leitura que falha diz que falhou — nunca 'nenhuma anotação'", async () => {
  const r = await tool(anotacaoTools, "listar_anotacoes_do_extrato").execute({}, ctx(anotacoes(true)));
  assertStringIncludes(r.error, "consulta falhou");
});

Deno.test("cancela a anotação dos 493 da Eliane: acha por nome e valor e grava status, hora e motivo", async () => {
  const db = anotacoes();
  const r = await tool(anotacaoTools, "alterar_anotacao_do_extrato").execute(
    { acao: "cancelar", quem: "eliane", valor: 493, motivo: "paguei em dinheiro" }, ctx(db));
  assertEquals(r.ok, true);
  const w = db.escritas.find((e) => e.tabela === "anotacoes_do_extrato")!;
  assertEquals(w.ids, ["an-eli"]);
  assertEquals(w.valores.status, "cancelada");
  assertEquals(w.valores.motivo_cancelamento, "paguei em dinheiro");
  assert(w.valores.cancelada_em);
});

Deno.test("anotação ambígua (duas da Eliane) vira pergunta com as opções, sem gravar", async () => {
  const db = anotacoes();
  const r = await tool(anotacaoTools, "alterar_anotacao_do_extrato").execute({ acao: "cancelar", quem: "Eliane" }, ctx(db));
  assertStringIncludes(sem(r.error), "Há 2 anotações");
  assertStringIncludes(sem(r.error), "R$ 493,00");
  assertEquals(db.escritas, []);
  // No resumo, a pergunta é UMA linha "⚠️": o agente recusa em vez de criar a pendência.
  const resumo = String(await resumirAnotacao(ctx(db) as never, { acao: "cancelar", quem: "Eliane" }));
  assert(resumo.startsWith("⚠️") && !resumo.includes("\n"));
});

Deno.test("a de 1.500 para a TSD era 1.050: corrige pela função do banco, com p_autor", async () => {
  const db = anotacoes();
  const args = { acao: "corrigir", quem: "TSD", valor: 1500, novo_valor: 1050 };
  const resumo = sem(await resumirAnotacao(ctx(db) as never, args));
  assertStringIncludes(resumo, "R$ 1.500,00 → *R$ 1.050,00*");
  await tool(anotacaoTools, "alterar_anotacao_do_extrato").execute(args, ctx(db));
  assertEquals(db.rpcs[0].n, "corrigir_anotacao");
  assertEquals(db.rpcs[0].a.p_anotacao, "an-tsd");
  assertEquals(db.rpcs[0].a.p_valor, 1050);
  assertEquals(db.rpcs[0].a.p_autor, "u-dono");
});

Deno.test("anotação: o retrato da pendência fixa a anotação que o dono viu", async () => {
  const db = anotacoes();
  const t = tool(anotacaoTools, "alterar_anotacao_do_extrato");
  const retrato = await t.retratoDaPendencia({ acao: "cancelar", quem: "TSD" }, ctx(db));
  assertEquals(retrato, { anotacao_id: "an-tsd" });
  // Mesmo que o nome dito agora achasse outra, vale o retrato.
  await t.execute({ acao: "cancelar", quem: "Eliane", [CHAVE_DO_RETRATO]: retrato }, ctx(db));
  assertEquals(db.escritas[0].ids, ["an-tsd"]);
  assertEquals(t.preValidar({ acao: "corrigir", quem: "TSD" }, {})?.error, "Diga o que corrigir: novo_valor, nova_categoria ou nova_data.");
});

// ── 2. Estorno de pagamento ──────────────────────────────────────────────────────────────────────

function pagamentos(opcoes: { falha?: string[]; doExtrato?: boolean } = {}) {
  return banco({
    service_orders: [{ id: "os95", service_order_number: "OS-00095", client_id: "c1", grand_total: 1600, status: "in_service" }],
    receivables: [{ id: "r95", service_order_id: "os95" }],
    payables: [{ id: "p-luz", linked_service_order_id: null }],
    payments: [
      { id: "pg1", amount: 800, payment_date: "2026-10-01", payment_method: "pix", status: "confirmed", receivable_id: "r95", payable_id: null,
        bank_transaction_id: opcoes.doExtrato ? "bt1" : null,
        receivables: { description: "Sinal — OS-00095", amount: 1600, paid_amount: 1600, clients: { name: "MP Motor Homes" }, service_orders: { service_order_number: "OS-00095" } }, payables: null },
      { id: "pg2", amount: 800, payment_date: "2026-10-02", payment_method: "pix", status: "confirmed", receivable_id: "r95", payable_id: null, bank_transaction_id: null,
        receivables: { description: "Sinal — OS-00095", amount: 1600, paid_amount: 1600, clients: { name: "MP Motor Homes" }, service_orders: { service_order_number: "OS-00095" } }, payables: null },
      { id: "pg-luz", amount: 312.4, payment_date: "2026-10-03", payment_method: "boleto", status: "confirmed", receivable_id: null, payable_id: "p-luz", bank_transaction_id: null,
        receivables: null, payables: { description: "Conta de luz", amount: 312.4, paid_amount: 312.4, supplier_name: "CELESC", service_orders: null } },
    ],
    bank_transactions: [],
  }, { falha: opcoes.falha, rpc: { estornar_pagamento: { data: { ok: true, message: "Estornei o pagamento de R$ 312,40." } } } });
}

Deno.test("estorno: risco alto, nunca autônomo, motivo obrigatório", () => {
  const t = tool(estornoTools, "estornar_pagamento");
  assertEquals(t.risk, "high");
  assert(NEVER_AUTONOMOUS.has("estornar_pagamento"));
  assertStringIncludes(t.preValidar({ payable_id: "x" }, {}).error, "motivo");
});

Deno.test("desfaz a baixa da conta de luz: acha o pagamento e estorna pela função, com p_autor", async () => {
  const db = pagamentos();
  const r = await tool(estornoTools, "estornar_pagamento").execute({ valor: 312.4, motivo: "ainda não paguei" }, ctx(db));
  assertEquals(r.ok, true);
  assertEquals(db.rpcs[0].n, "estornar_pagamento");
  assertEquals(db.rpcs[0].a.p_pagamento, "pg-luz");
  assertEquals(db.rpcs[0].a.p_autor, "u-dono");
  assertEquals(db.rpcs[0].a.p_motivo, "ainda não paguei");
});

Deno.test("estorno na OS-00095 com dois pagamentos de 800: pergunta qual, sem estornar", async () => {
  const db = pagamentos();
  const r = await tool(estornoTools, "estornar_pagamento").execute({ os: "OS-00095", valor: 800, motivo: "duplicado" }, ctx(db));
  assertStringIncludes(r.error, "Há 2 pagamentos");
  assertStringIncludes(r.error, "pagamento_id pg2");
  assertEquals(db.rpcs, []);
  const comData = await tool(estornoTools, "estornar_pagamento").execute({ os: "OS-00095", valor: 800, data: "02/10/2026", motivo: "duplicado" }, ctx(db));
  assertEquals(comData.ok, true);
  assertEquals(db.rpcs[0].a.p_pagamento, "pg2");
  const resumo = sem(await resumirEstorno(ctx(db) as never, { os: "OS-00095", valor: 800, data: "02/10/2026", motivo: "duplicado" }));
  assertStringIncludes(resumo, "R$ 1.600,00 pago para *R$ 800,00*");
});

Deno.test("pagamento que veio do extrato não se estorna: diz o caminho", async () => {
  const db2 = pagamentos({ doExtrato: true });
  const r2 = await tool(estornoTools, "estornar_pagamento").execute({ os: "OS-00095", valor: 800, data: "01/10/2026", motivo: "duplicado" }, ctx(db2));
  assertStringIncludes(r2.error, "desfazer_aplicacao_de_pix");
  assertEquals(db2.rpcs, []);
});

Deno.test("estorno: leitura que falha diz que falhou", async () => {
  const r = await tool(estornoTools, "estornar_pagamento").execute({ valor: 800, motivo: "duplicado" }, ctx(pagamentos({ falha: ["payments"] })));
  assertStringIncludes(r.error, "consulta falhou");
});

// ── 3. Cobrança formal ──────────────────────────────────────────────────────────────────────────

function cobrancas(opcoes: { duasParcelas?: boolean; jaCobrada?: boolean; falha?: string[] } = {}) {
  return banco({
    service_orders: [{ id: "os112", service_order_number: "OS-00112", client_id: "c-mp", grand_total: 10500, status: "in_service" }],
    receivables: [
      { id: "r-sinal", service_order_id: "os112", description: "Sinal — OS-00112", amount: 7600, balance_amount: 0, due_date: "2026-10-01", status: "paid" },
      { id: "r-saldo", service_order_id: "os112", description: "Saldo — OS-00112", amount: 2900, balance_amount: 2900, due_date: "2026-11-05", status: "pending" },
      ...(opcoes.duasParcelas ? [{ id: "r-extra", service_order_id: "os112", description: "Extra", amount: 500, balance_amount: 500, due_date: "2026-11-10", status: "pending" }] : []),
    ],
    clients: [
      { id: "c-mp", name: "MP Motor Homes", phone: "4733330000", whatsapp: "47999990000" },
      { id: "c-fla", name: "Flávio Rodrigues", phone: null, whatsapp: "47988887777" },
    ],
    collection_templates: [{ name: "Padrão", body: "Olá {{nome}}", send_method: "text_link", is_default: true }],
    collections: [
      { id: "col-fla", client_id: "c-fla", service_order_id: null, receivable_id: null, description: "Conserto do guincho", amount: 500, due_date: "2026-10-01",
        status: "overdue", contact_name: "Flávio", phone: null, contact_whatsapp: "47988887777", notes: null,
        clients: { name: "Flávio Rodrigues", phone: null, whatsapp: "47988887777" }, service_orders: null },
      ...(opcoes.jaCobrada ? [{ id: "col-mp", client_id: "c-mp", service_order_id: "os112", receivable_id: "r-saldo", description: null, amount: 2900, due_date: "2026-10-20",
        status: "sent", contact_name: "MP", phone: null, contact_whatsapp: null, notes: null, clients: { name: "MP Motor Homes" }, service_orders: { service_order_number: "OS-00112" } }] : []),
    ],
    collection_contacts: [
      { collection_id: "col-fla", contact_type: "payment_promised", promised_date: DIAS(-4), created_at: "2026-10-01T10:00:00Z" },
    ],
  }, { falha: opcoes.falha });
}

Deno.test("cria cobrança de 2.900 da OS-00112, vence dia 20: ligada à conta a receber em aberto, contato do cadastro", async () => {
  const db = cobrancas();
  const args = { os: "OS-00112", valor: 2900, vencimento: "20/10/2026" };
  const resumo = sem(await resumirCobranca(ctx(db) as never, "criar_cobranca", args));
  assertStringIncludes(resumo, "MP Motor Homes");
  assertStringIncludes(resumo, "Saldo — OS-00112");
  const r = await tool(cobrancaTools, "criar_cobranca").execute(args, ctx(db));
  assertEquals(r.ok, true);
  const w = db.escritas.find((e) => e.tabela === "collections")!.valores;
  assertEquals(w.receivable_id, "r-saldo");
  assertEquals(w.service_order_id, "os112");
  assertEquals(w.amount, 2900);
  assertEquals(w.due_date, "2026-10-20");
  assertEquals(w.contact_whatsapp, "47999990000");
  assertEquals(w.status, "pending");
  assertEquals(w.created_by, "u-dono");
  assertEquals(w.standalone_amount, null);
});

Deno.test("cobrança da OS com duas parcelas e sem valor que decida: pergunta qual; já cobrada: recusa", async () => {
  const r = await tool(cobrancaTools, "criar_cobranca").execute({ os: "112", vencimento: "20/10/2026" }, ctx(cobrancas({ duasParcelas: true })));
  assertStringIncludes(r.error, "2 parcelas em aberto");
  const r2 = await tool(cobrancaTools, "criar_cobranca").execute({ os: "OS-00112" }, ctx(cobrancas({ jaCobrada: true })));
  assertStringIncludes(r2.error, "Já existe cobrança aberta");
});

Deno.test("liguei para o Flávio, ele prometeu pagar sexta: contato 'prometeu pagar' com a data", async () => {
  const db = cobrancas();
  const r = await tool(cobrancaTools, "registrar_contato_de_cobranca").execute(
    { cliente: "Flávio", tipo: "prometeu_pagar", prometeu_em: "30/10/2026", observacao: "vai pagar no Pix" }, ctx(db));
  assertEquals(r.ok, true);
  const w = db.escritas.find((e) => e.tabela === "collection_contacts")!.valores;
  assertEquals(w.collection_id, "col-fla");
  assertEquals(w.contact_type, "payment_promised");
  assertEquals(w.promised_date, "2026-10-30");
  assertEquals(w.created_by, "u-dono");
  assertStringIncludes(tool(cobrancaTools, "registrar_contato_de_cobranca").preValidar({ tipo: "prometeu_pagar" }, {}).error, "quando");
});

Deno.test("cancela a cobrança com motivo: situação e observação; 'paga' não se marca por aqui", async () => {
  const db = cobrancas();
  const r = await tool(cobrancaTools, "alterar_cobranca").execute({ cliente: "Flávio", situacao: "cancelada", motivo: "acertou comigo" }, ctx(db));
  assertEquals(r.ok, true);
  const w = db.escritas.find((e) => e.tabela === "collections")!.valores;
  assertEquals(w.status, "cancelled");
  assertStringIncludes(w.notes, "acertou comigo");
  assert(tool(cobrancaTools, "alterar_cobranca").preValidar({ cliente: "Flávio", situacao: "paga" }, {}));
});

Deno.test("list_pending_collections: traz enviada/vencida/em disputa e as promessas vencidas", async () => {
  const db = cobrancas();
  const t = tool(financialTools, "list_pending_collections");
  const todas = await t.execute({}, ctx(db));
  assertEquals(todas.results.map((c: any) => c.id), ["col-fla"]);
  const vencidas = await t.execute({ promessas: "vencidas" }, ctx(db));
  assertEquals(vencidas.results[0].prometeu_pagar_em, DIAS(-4));
  assertEquals(vencidas.results[0].promessa_vencida, true);
  assertEquals(vencidas.results[0].cliente, "Flávio Rodrigues");
  let erro = "";
  try { await t.execute({}, ctx(cobrancas({ falha: ["collection_contacts"] }))); } catch (e) { erro = String(e); }
  assertStringIncludes(erro, "promessas");
});

Deno.test("lembrete enviado entra no histórico e a cobrança fica 'enviada' (paga continua paga)", async () => {
  const db = cobrancas();
  const aviso = await registrarEnvioDaCobranca(db, { id: "col-fla", status: "overdue" }, "u-dono", "Lembrete enviado");
  assertEquals(aviso, null);
  assertEquals(db.escritas.find((e) => e.tabela === "collection_contacts")!.valores.contact_type, "whatsapp_sent");
  assertEquals(db.escritas.find((e) => e.tabela === "collections")!.valores.status, "sent");
  const db2 = cobrancas();
  await registrarEnvioDaCobranca(db2, { id: "col-fla", status: "paid" }, null, "x");
  assertEquals(db2.escritas.find((e) => e.tabela === "collections")!.valores.status, "paid");
});

// ── 5. Favorecido ───────────────────────────────────────────────────────────────────────────────

function favorecidos() {
  return banco({
    payees: [
      { id: "p-eli", name: "Eliane Souza", kind: "prestador", document: null, phone: null, email: null, pix_key: "eliane@x.com", pix_key_type: "email",
        bank_name: null, bank_branch: null, bank_account: null, account_type: null, default_category: "Alimentação de campo", active: true, notes: null },
      { id: "p-alex", name: "Alex Gonçalves Machado", kind: "socio", document: "54834240000110", phone: null, email: null, pix_key: null, pix_key_type: null,
        bank_name: null, bank_branch: null, bank_account: null, account_type: null, default_category: "Distrato de ex-sócio", active: true, notes: null },
    ],
    suppliers: [{ id: "f-tsd", name: "TSD Distribuidora", trade_name: "TSD" }],
    financial_categories: [{ name: "Alimentação de campo", type: "payable", active: true }],
    finance_rules: [
      { id: "fr-doc", match_type: "document", match_value: "54834240000110", set_category: "Distrato de ex-sócio", status: "active", note: null },
      { id: "fr-nome", match_type: "counterparty", match_value: "54.834.240 ALEX GONCALVES MACHADO", set_category: "Distrato de ex-sócio", status: "active", note: null },
      { id: "fr-outra", match_type: "counterparty", match_value: "POSTO PAULINHO", set_category: "Combustível", status: "active", note: null },
    ],
    service_orders: [],
  });
}

Deno.test("troca o Pix da Eliane para o telefone: os mesmos campos da tela, com o tipo da chave", async () => {
  const db = favorecidos();
  const args = { favorecido: "Eliane", chave_pix: "11987654321", tipo_chave_pix: "telefone" };
  const resumo = sem(await resumirFavorecido(ctx(db) as never, args));
  assertStringIncludes(resumo, "eliane@x.com → *11987654321*");
  const r = await tool(favorecidoTools, "alterar_favorecido").execute(args, ctx(db));
  assertEquals(r.ok, true);
  const w = db.escritas.find((e) => e.tabela === "payees")!;
  assertEquals(w.ids, ["p-eli"]);
  assertEquals(w.valores, { pix_key: "11987654321", pix_key_type: "telefone" });
  assertEquals(typeof tipoDaChave("11987654321"), "object", "11 dígitos sem tipo é pergunta");
  assertEquals(tipoDaChave("+5511987654321"), "telefone");
  assertEquals(tipoDaChave("a@b.com"), "email");
});

Deno.test("desativa o Alex: pausa as regras pelo CPF/CNPJ e pelo nome completo; reativar devolve", async () => {
  const db = favorecidos();
  const resumo = sem(await resumirFavorecido(ctx(db) as never, { favorecido: "Alex", ativo: false }));
  assertStringIncludes(resumo, "Pausa 2 regra(s)");
  const r = await tool(favorecidoTools, "alterar_favorecido").execute({ favorecido: "Alex", ativo: false }, ctx(db));
  assertEquals(r.ok, true);
  const pausadas = db.escritas.filter((e) => e.tabela === "finance_rules");
  assertEquals(pausadas.map((e) => e.ids[0]).sort(), ["fr-doc", "fr-nome"]);
  assertEquals(pausadas[0].valores.status, "paused");
  assertStringIncludes(pausadas[0].valores.note, "fav:p-alex]");
  // Reativar: só as que a desativação pausou, com a situação de antes, e a nota limpa.
  const r2 = await tool(favorecidoTools, "alterar_favorecido").execute({ favorecido: "Alex", ativo: true }, ctx(db));
  assertEquals(r2.ok, true);
  const voltaram = db.escritas.filter((e) => e.tabela === "finance_rules").slice(2);
  assertEquals(voltaram.map((e) => e.valores), [{ status: "active", note: null }, { status: "active", note: null }]);
});

Deno.test("marca de pausa: guarda a situação de antes e sai inteira na volta", () => {
  const nota = marcarPausa("regra do dono", { id: "p1", name: "Fulano" }, "proposed", "07/10/2026");
  assertEquals(tirarPausa(nota, "p1"), { status: "proposed", note: "regra do dono" });
  assertEquals(tirarPausa("sem marca", "p1"), { status: "active", note: "sem marca" });
});

Deno.test("conta a pagar de 300 para a Eliane, vence dia 10, alimentação: favorecido e categoria resolvidos", async () => {
  const db = favorecidos();
  const r = await contaAPagarDita(ctx(db) as never, { amount: 300, description: "Refeições", favorecido: "Eliane", due_date: "10/11/2026", expense_category: "alimentação" });
  if ("error" in r) throw new Error(r.error);
  assertEquals(r.linha.payee_id, "p-eli");
  assertEquals(r.linha.expense_category, "Alimentação de campo");
  assertEquals(r.linha.due_date, "2026-11-10");
  assertEquals(r.linha.balance_amount, 300);
  // Sem cadastro: vai com o nome, sem favorecido.
  const livre = await contaAPagarDita(ctx(db) as never, { amount: 50, description: "Marmita", favorecido: "Dona Maria", due_date: "10/11/2026" });
  if ("error" in livre) throw new Error(livre.error);
  assertEquals(livre.linha.supplier_name, "Dona Maria");
  assertEquals(livre.linha.payee_id, null);
  // create_payable grava a linha resolvida (não os argumentos crus).
  await tool(financialTools, "create_payable").execute({ amount: 300, description: "Refeições", favorecido: "Eliane", due_date: "10/11/2026" }, ctx(db));
  const w = db.escritas.find((e) => e.tabela === "payables")!.valores;
  assertEquals(w.payee_id, "p-eli");
  assertEquals("favorecido" in w, false);
});

Deno.test("as ferramentas novas pedem confirmação, menos a lista; só gestor mexe em favorecido e anotação", async () => {
  for (const [lista, nome] of [[anotacaoTools, "alterar_anotacao_do_extrato"], [cobrancaTools, "criar_cobranca"], [cobrancaTools, "registrar_contato_de_cobranca"],
    [cobrancaTools, "alterar_cobranca"], [favorecidoTools, "alterar_favorecido"]] as const) {
    assertEquals(tool(lista as never, nome).risk, "medium", nome);
  }
  assertEquals(tool(anotacaoTools, "listar_anotacoes_do_extrato").risk, "low");
  const vendedor = await tool(favorecidoTools, "alterar_favorecido").execute({ favorecido: "Eliane", telefone: "1" }, ctx(favorecidos(), "seller"));
  assertStringIncludes(vendedor.error, "administrador ou financeiro");
  const tecnico = await tool(cobrancaTools, "criar_cobranca").execute({ os: "112" }, ctx(cobrancas(), "technician"));
  assert(tecnico.error);
});
