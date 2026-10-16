// O lote da papelada no fechamento da sexta (secretário, Passo 5) com um banco de mentira: a chave desligada não muda
// NADA (o texto é o mesmo de sem a chave, byte a byte, e o lote nem é lido); a sombra guarda o lote e põe a linha só no
// texto guardado; o "ligado" só vale com a tarde saindo de verdade; o lote que não foi guardado não aparece.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { rodarTurnoDaTarde } from "./secretario-tarde.ts";
import { lerFilaParaOLote, limiteDoLote } from "./secretario-papelada.ts";

type Linha = Record<string, unknown>;
const DONO = { id: "u-dono", phone: "5547999990000" };
const HOJE = "2026-10-16"; // sexta: fechamento + pergunta da semana = o dia do lote
const AS_1730 = new Date("2026-10-16T20:30:00Z");

function falsoAdmin(tabelas: Record<string, Linha[]>, rpcs: Record<string, unknown> = {}) {
  const lidas: string[] = [];
  const chamadas: Array<{ nome: string; args: { p?: Record<string, unknown> } }> = [];
  const admin = {
    from(tabela: string) {
      lidas.push(tabela);
      let linhas = [...(tabelas[tabela] ?? [])];
      let soContagem = false;
      let fatia: [number, number] | null = null;
      const resultado = () => soContagem
        ? { data: null, error: null, count: linhas.length }
        : { data: fatia ? linhas.slice(fatia[0], fatia[1] + 1) : linhas, error: null };
      const q: Record<string, unknown> = {
        select: (_c?: string, o?: { head?: boolean }) => ((soContagem = !!o?.head), q),
        eq: (c: string, v: unknown) => ((linhas = linhas.filter((l) => l[c] === v)), q),
        neq: (c: string, v: unknown) => ((linhas = linhas.filter((l) => l[c] !== v)), q),
        in: (c: string, vs: unknown[]) => ((linhas = linhas.filter((l) => vs.includes(l[c]))), q),
        is: (c: string, v: unknown) => ((linhas = linhas.filter((l) => (l[c] ?? null) === v)), q),
        not: (c: string, op: string, v: unknown) => ((linhas = linhas.filter((l) => !(op === "is" && (l[c] ?? null) === v))), q),
        lt: (c: string, v: string) => ((linhas = linhas.filter((l) => l[c] != null && String(l[c]) < v)), q),
        lte: (c: string, v: string) => ((linhas = linhas.filter((l) => l[c] != null && String(l[c]) <= v)), q),
        gte: (c: string, v: string) => ((linhas = linhas.filter((l) => l[c] != null && String(l[c]) >= v)), q),
        gt: (c: string, v: string) => ((linhas = linhas.filter((l) => l[c] != null && String(l[c]) > v)), q),
        like: () => q,
        or: () => q,
        order: () => q,
        limit: () => q,
        range: (de: number, ate: number) => ((fatia = [de, ate]), q),
        insert: () => Promise.resolve({ data: null, error: null }),
        update: () => ({ eq: () => Promise.resolve({ data: null, error: null }) }),
        maybeSingle: () => Promise.resolve({ data: linhas[0] ?? null, error: null }),
        then: (ok: (r: unknown) => unknown, erro?: (e: unknown) => unknown) => Promise.resolve(resultado()).then(ok, erro),
      };
      return q;
    },
    rpc(nome: string, args: { p?: Record<string, unknown> }) {
      chamadas.push({ nome, args });
      return Promise.resolve({ data: rpcs[nome] ?? null, error: null });
    },
  };
  return { admin, lidas, chamadas };
}

const TX = (id: string, nome: string, doc: string | null = null) => ({ id, counterparty_name: nome, counterparty_document: doc, description: nome, transaction_date: "2026-10-10", amount: 100 });
const FILA = [
  { id: "f-1", kind: "create_payable", status: "pending", title: "Despesa: PGTO FAT CARTAO C6", suggested_amount: 400, suggested_date: "2026-10-06", suggested_category: "Pagamento de fatura de cartão", confidence: 95, applied_rule_id: null, bank_transaction_id: "t-1", related_transaction_id: null, evidencia: null, vinculo_sugerido: null },
  { id: "f-2", kind: "create_payable", status: "pending", title: "Despesa: DEBITO DE CARTAO", suggested_amount: 755, suggested_date: "2026-10-05", suggested_category: "Outras despesas", confidence: 30, applied_rule_id: null, bank_transaction_id: "t-2", related_transaction_id: null, evidencia: null, vinculo_sugerido: null },
  { id: "f-3", kind: "create_receivable", status: "pending", title: "Receita: Pix recebido de NELSON", suggested_amount: 7600, suggested_date: "2026-10-05", suggested_category: "Outras receitas", confidence: 30, applied_rule_id: null, bank_transaction_id: "t-3", related_transaction_id: null, evidencia: null,
    vinculo_sugerido: { principal: { tipo: "existing_payment", rotulo: "Pagamento já lançado: Sinal — ORÇ-00112", jaLancado: true, confianca: 75, diferenca: 0 }, alternativas: [] } },
];
// o histórico do dono: fatura 15 de 15 sem troca
const LOG = Array.from({ length: 15 }, (_, i) => ({
  id: `r-${i}`, acao: "aprovou_proposta", ocorrido_em: `2026-09-2${i % 9}T12:00:00Z`, antes: { categoria_sugerida: "Pagamento de fatura de cartão" },
  depois: { categoria: "Pagamento de fatura de cartão" }, payable_id: `p-${i}`, receivable_id: null, bank_transaction_id: `th-${i}`,
}));

function banco(p: { papelada?: string | null; formato?: string; modo?: "sombra" | "novo" } = {}): Record<string, Linha[]> {
  return {
    app_settings: [
      { key: "fechamento_formato", value: p.formato ?? "sombra" }, { key: "quote_validity_days", value: "3" },
      ...(p.papelada === undefined || p.papelada === null ? [] : [{ key: "papelada_lote", value: p.papelada }]),
    ],
    app_users: [{ id: DONO.id, phone_normalized: DONO.phone, role: "admin", active: true, ai_whatsapp_enabled: true }],
    resumo_tarde: [],
    resumo_manha: [{ id: "m-1", dia: HOJE, phone_normalized: DONO.phone, modo: p.modo ?? "sombra" }],
    resumo_itens: [],
    whatsapp_messages: [],
    whatsapp_perguntas: [],
    ai_operator_sessions: [{ id: "s-1", channel: "whatsapp", external_thread_key: DONO.phone, status: "open", last_activity_at: new Date().toISOString(), metadata: {} }],
    finance_review_queue: FILA,
    bank_transactions: [TX("t-1", "PGTO FAT CARTAO C6"), TX("t-2", "DEBITO DE CARTAO"), TX("t-3", "Pix recebido de NELSON A B SOUZA", "24755150078"),
      ...LOG.map((l, i) => TX(String(l.bank_transaction_id), `BANCO ${i}`))],
    finance_rules: [],
    anotacoes_do_extrato: [],
    payables: [],
    receivables: [],
    reconciliation_log: LOG,
  };
}

const RPCS = {
  whatsapp_esperando_resposta: [],
  resumo_tarde_registrar: { ok: true, novo: true, enviado: false, calado: false },
  papelada_lote_registrar: { ok: true, novo: true, id: "lote-1" },
};

function chamada(chamadas: Array<{ nome: string; args: { p?: Record<string, unknown> } }>, nome: string) {
  return chamadas.find((c) => c.nome === nome)?.args.p ?? null;
}

Deno.test("chave desligada = a sexta de antes, byte a byte: o lote nem é montado nem guardado", async () => {
  const sem = falsoAdmin(banco({ papelada: null }), RPCS);
  await rodarTurnoDaTarde(sem.admin, { agora: AS_1730, pedido: "tarde", dry: false });
  const desl = falsoAdmin(banco({ papelada: "desligado" }), RPCS);
  await rodarTurnoDaTarde(desl.admin, { agora: AS_1730, pedido: "tarde", dry: false });
  const a = chamada(sem.chamadas, "resumo_tarde_registrar")!;
  const b = chamada(desl.chamadas, "resumo_tarde_registrar")!;
  assertEquals(b.texto, a.texto);
  assertEquals(b.escritorio, a.escritorio);
  assertEquals(b.detalhe, a.detalhe);
  assertStringIncludes(String(b.texto), "Escritório:");
  assert(!String(b.texto).includes("Escritório da semana"));
  assertEquals(desl.chamadas.some((c) => c.nome === "papelada_lote_registrar"), false);
  assertEquals(desl.lidas.includes("reconciliation_log"), false);
});

Deno.test("sombra: o lote é montado e GUARDADO como sombra; a linha entra só no texto guardado (que não sai)", async () => {
  const f = falsoAdmin(banco({ papelada: "sombra" }), RPCS);
  const r = await rodarTurnoDaTarde(f.admin, { agora: AS_1730, pedido: "tarde", dry: false });
  const lote = chamada(f.chamadas, "papelada_lote_registrar")!;
  assertEquals([lote.formato, lote.dia, lote.phone], ["sombra", HOJE, DONO.phone]);
  assertEquals((lote.itens as Array<{ id: string }>).map((i) => i.id), ["f-1"]);
  assertEquals((lote.excecoes as Array<{ id: string; codigo: string }>).map((e) => [e.id, e.codigo]), [["f-3", "sinal_ja_lancado"], ["f-2", "sem_loja"]]);
  const tarde = chamada(f.chamadas, "resumo_tarde_registrar")!;
  assertEquals(tarde.enviado, false);
  assertStringIncludes(String(tarde.texto),
    "Escritório da semana: 1 item pronto para um sim só (1 despesa, R$ 400,00) e 2 que precisam de você; uns 5 min. *lote*");
  assert(!String(tarde.texto).includes("Escritório: "));
  assertStringIncludes(String(tarde.escritorio), "Escritório da semana:");
  assertEquals(r.corpo.lote, "novo");
  // o lote foi guardado ANTES da tarde
  assert(f.chamadas.findIndex((c) => c.nome === "papelada_lote_registrar") < f.chamadas.findIndex((c) => c.nome === "resumo_tarde_registrar"));
});

Deno.test("ligado com a tarde em sombra (ou a manhã-sombra): o lote nasce sombra; ligado + tarde enviada = ligado", async () => {
  const f = falsoAdmin(banco({ papelada: "ligado", formato: "sombra" }), RPCS);
  await rodarTurnoDaTarde(f.admin, { agora: AS_1730, pedido: "tarde", dry: false });
  assertEquals(chamada(f.chamadas, "papelada_lote_registrar")!.formato, "sombra");
  const enviada = falsoAdmin(banco({ papelada: "ligado", formato: "ligado", modo: "novo" }), { ...RPCS, resumo_tarde_registrar: { ok: true, novo: true, enviado: true } });
  await rodarTurnoDaTarde(enviada.admin, { agora: AS_1730, pedido: "tarde", dry: false });
  assertEquals(chamada(enviada.chamadas, "papelada_lote_registrar")!.formato, "ligado");
  const tarde = chamada(enviada.chamadas, "resumo_tarde_registrar")!;
  assertEquals(tarde.enviado, true);
  assertStringIncludes(String(tarde.texto), "Escritório da semana:");
});

Deno.test("sombra na chave com a tarde ENVIADA: o lote é guardado (sombra) e a linha NÃO vai para o dono", async () => {
  const f = falsoAdmin(banco({ papelada: "sombra", formato: "ligado", modo: "novo" }), { ...RPCS, resumo_tarde_registrar: { ok: true, novo: true, enviado: true } });
  await rodarTurnoDaTarde(f.admin, { agora: AS_1730, pedido: "tarde", dry: false });
  assertEquals(chamada(f.chamadas, "papelada_lote_registrar")!.formato, "sombra");
  const tarde = chamada(f.chamadas, "resumo_tarde_registrar")!;
  assertStringIncludes(String(tarde.texto), "Escritório:");
  assert(!String(tarde.texto).includes("Escritório da semana"));
});

Deno.test("o lote que não foi guardado não aparece (a linha volta a ser a do escritório)", async () => {
  const f = falsoAdmin(banco({ papelada: "sombra" }), { ...RPCS, papelada_lote_registrar: { ok: false, erro: "item repetido no lote" } });
  const r = await rodarTurnoDaTarde(f.admin, { agora: AS_1730, pedido: "tarde", dry: false });
  const tarde = chamada(f.chamadas, "resumo_tarde_registrar")!;
  assert(!String(tarde.texto).includes("Escritório da semana"));
  assertStringIncludes(String(tarde.texto), "Escritório:");
  assertEquals(r.corpo.lote, "erro:item repetido no lote");
});

Deno.test("quinta (não é o dia do lote): com a chave em sombra, nada do lote", async () => {
  const b = banco({ papelada: "sombra" });
  b.resumo_manha = [{ id: "m-1", dia: "2026-10-15", phone_normalized: DONO.phone, modo: "sombra" }];
  const f = falsoAdmin(b, RPCS);
  await rodarTurnoDaTarde(f.admin, { agora: new Date("2026-10-15T20:30:00Z"), pedido: "tarde", dry: false });
  assertEquals(f.chamadas.some((c) => c.nome === "papelada_lote_registrar"), false);
  assertEquals(f.lidas.includes("reconciliation_log"), false);
});

Deno.test("dry-run da sexta com a chave em sombra: mostra o lote e não grava nada", async () => {
  const f = falsoAdmin(banco({ papelada: "sombra" }), RPCS);
  const r = await rodarTurnoDaTarde(f.admin, { agora: AS_1730, pedido: "tarde", dry: true });
  const lote = r.corpo.lote as { linha: string; itens: unknown[]; fora: unknown[] };
  assertStringIncludes(lote.linha, "1 item pronto para um sim só");
  assertEquals([lote.itens.length, lote.fora.length], [1, 2]);
  assertEquals(f.chamadas.some((c) => c.nome === "papelada_lote_registrar" || c.nome === "resumo_tarde_registrar"), false);
});

Deno.test("coleta: a fila com a linha do banco, a regra, o que já foi lançado e as outras propostas da mesma linha", async () => {
  const b = banco();
  b.payables = [{ bank_transaction_id: "t-1", status: "paid" }];
  const f = falsoAdmin(b);
  const fila = await lerFilaParaOLote(f.admin);
  const f1 = fila.find((l) => l.id === "f-1")!;
  assertEquals([f1.tx_lancada, f1.tx?.counterparty_name, f1.alertas_na_tx, f1.do_comprovante], [true, "PGTO FAT CARTAO C6", 0, false]);
  assertEquals(limiteDoLote({ finance_review_batch_limit: "300" }), 300);
  assertEquals(limiteDoLote({}), 500);
});
