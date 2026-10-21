// A recusa da fila que FICA, a entrada recusada que sai da fila do banco e o desfazer com ids de proposta
// (spec-papelada-fix.md, A1, A2 e A4). Banco falso em memória (aplica os filtros e o índice único
// "uma pendente por linha e tipo"), sem rede.
// Rodar com:
//   deno test --allow-all --no-check --node-modules-dir=none supabase/functions/finance-review/recusa_test.ts
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  lerRecusas, linhaMudou, motivoDaRecusa, PREFIXO_DA_RECUSA, propostasAReabrir, reabrirPropostas, recusaQueVale,
  recusarPropostas, recusasPorLinha, tipoDaProposta, type PropostaDaLinha,
} from "./recusa.ts";

// deno-lint-ignore no-explicit-any
type Qualquer = any;

/** Banco falso: tabelas em memória; select/update com eq/neq/in/is/not/limit; o índice único da fila. */
function bancoFalso(tabelas: Record<string, Qualquer[]>, falhar: Record<string, { message: string }> = {}) {
  const chamadas: Array<{ tabela: string; op: string; valores?: Qualquer; n: number }> = [];
  const indiceDaFila = () => {
    const vistos = new Set<string>();
    for (const r of tabelas.finance_review_queue ?? []) {
      if (r.status !== "pending" || !r.bank_transaction_id) continue;
      const k = `${r.bank_transaction_id}|${r.kind}`;
      if (vistos.has(k)) return false;
      vistos.add(k);
    }
    return true;
  };
  function from(tabela: string) {
    const filtros: Array<(r: Qualquer) => boolean> = [];
    let op: "select" | "update" = "select";
    let valores: Qualquer = null;
    let devolver = false;
    let limite = Infinity;
    const executar = () => {
      const chave = `${tabela}:${op}`;
      if (falhar[chave]) return Promise.resolve({ data: null, error: falhar[chave] });
      const linhas = (tabelas[tabela] ??= []);
      const alvo = linhas.filter((r) => filtros.every((f) => f(r)));
      if (op === "update") {
        const antes = alvo.map((r) => ({ ...r }));
        for (const r of alvo) Object.assign(r, valores);
        if (tabela === "finance_review_queue" && !indiceDaFila()) {
          alvo.forEach((r, i) => Object.assign(r, antes[i]));
          return Promise.resolve({
            data: null,
            error: { code: "23505", message: 'duplicate key value violates unique constraint "finance_review_uma_por_transacao"' },
          });
        }
        chamadas.push({ tabela, op, valores, n: alvo.length });
        return Promise.resolve({ data: devolver ? alvo.map((r) => ({ ...r })) : null, error: null });
      }
      chamadas.push({ tabela, op, n: alvo.length });
      return Promise.resolve({ data: alvo.slice(0, limite).map((r) => ({ ...r })), error: null });
    };
    const b: Qualquer = {
      select() { if (op === "update") devolver = true; return b; },
      update(v: Qualquer) { op = "update"; valores = v; return b; },
      eq(c: string, v: unknown) { filtros.push((r) => r[c] === v); return b; },
      neq(c: string, v: unknown) { filtros.push((r) => r[c] !== v); return b; },
      in(c: string, vs: unknown[]) { filtros.push((r) => vs.includes(r[c])); return b; },
      is(c: string, v: unknown) { filtros.push((r) => (r[c] ?? null) === v); return b; },
      not(c: string, _op: string, v: unknown) { filtros.push((r) => (r[c] ?? null) !== v); return b; },
      limit(n: number) { limite = n; return b; },
      order() { return b; },
      then(ok: Qualquer, erro: Qualquer) { return executar().then(ok, erro); },
    };
    return b;
  }
  return { admin: { from }, tabelas, chamadas };
}

// ── O caso real (produção, 20/10/2026): as 6 entradas antigas já recusadas — 4 estornos de pedágio
// (recusados em 20/09 e de novo em 26/09, depois que o mutirão de 26/09 as propôs outra vez), o Pix de
// R$ 1.000 (recusado em 26/09 e 28/09) e os R$ 0,35 do cheque especial (recusado em 26/09).
const ARTERIS_1 = "c40b8d03-82b5-459d-b979-790537551de7";
const ARTERIS_2 = "14bce45c-d889-44df-aa48-ba7a099e8a9b";
const ARTERIS_3 = "34cc3028-eb49-430e-b4e2-5654b87bdca5";
const ARTERIS_4 = "59777142-d985-4a53-954d-5f0c0dacb75d";
const PIX_1000 = "16e364db-99da-4a29-80a0-224e30387b72";
const CHEQUE = "eb1c966c-b2a0-4e1f-82e0-494b0fb907ad";

const LINHAS_REAIS = [
  { id: ARTERIS_1, transaction_date: "2025-09-19", amount: 11.40, transaction_type: "credit", description: "AXK4J38-ARTERIS LITORAL SUL  BR101 793 N" },
  { id: ARTERIS_2, transaction_date: "2025-11-25", amount: 11.40, transaction_type: "credit", description: "AXK4J38-ARTERIS LITORAL SUL  BR101 793 S" },
  { id: ARTERIS_3, transaction_date: "2026-02-20", amount: 11.40, transaction_type: "credit", description: "AXK4J38-ARTERIS LITORAL SUL  BR101 1574" },
  { id: ARTERIS_4, transaction_date: "2026-03-20", amount: 11.40, transaction_type: "credit", description: "AXK4J38-ARTERIS LITORAL SUL  BR101 1574" },
  { id: PIX_1000, transaction_date: "2026-04-10", amount: 1000, transaction_type: "credit", description: "Pix recebido (pessoa física)" },
  { id: CHEQUE, transaction_date: "2026-04-23", amount: 0.35, transaction_type: "credit", description: "CHEQUE ESPECIAL" },
];

let seq = 0;
const uuid = () => `00000000-0000-4000-8000-${String(++seq).padStart(12, "0")}`;

function proposta(tx: Qualquer, status: string, criada: string, extra: Partial<PropostaDaLinha> = {}): Qualquer {
  return {
    id: uuid(), kind: "create_receivable", status, bank_transaction_id: tx.id, related_transaction_id: null,
    created_at: criada, decided_at: status === "pending" ? null : criada, decided_by: null, decision_note: null,
    suggested_amount: tx.amount, suggested_date: tx.transaction_date, title: `Receita: ${tx.description}`, ...extra,
  };
}

function filaReal(): Qualquer[] {
  const fila: Qualquer[] = [];
  for (const tx of LINHAS_REAIS.slice(0, 5)) {
    fila.push(proposta(tx, "rejected", "2026-08-10T01:00:00Z"));
    fila.push(proposta(tx, "rejected", "2026-09-26T16:00:00Z"));
  }
  fila.push(proposta(LINHAS_REAIS[5], "rejected", "2026-09-26T16:00:00Z"));
  return fila;
}

/** A decisão do gerar para uma linha livre (não pendente, não lançada): fica fora pela recusa? */
function ficaForaPelaRecusa(recusas: Map<string, Qualquer>, tx: Qualquer, ehPar = false, cnpj = "") {
  return !!recusaQueVale(recusas.get(tx.id), tipoDaProposta(tx, ehPar, cnpj), tx);
}

Deno.test("A1 caso real: as 6 entradas antigas recusadas não nascem de novo (a linha não mudou)", async () => {
  const { admin } = bancoFalso({ finance_review_queue: filaReal() });
  const recusas = await lerRecusas(admin, LINHAS_REAIS.map((t) => t.id));
  assertEquals(recusas.size, 6);
  for (const tx of LINHAS_REAIS) assert(ficaForaPelaRecusa(recusas, tx), `${tx.description} voltaria`);
});

Deno.test("A1: a linha que mudou de verdade (outro valor ou outra data) volta a ser proposta", async () => {
  const { admin } = bancoFalso({ finance_review_queue: filaReal() });
  const recusas = await lerRecusas(admin, LINHAS_REAIS.map((t) => t.id));
  assert(!ficaForaPelaRecusa(recusas, { ...LINHAS_REAIS[4], amount: 1000.5 }));
  assert(!ficaForaPelaRecusa(recusas, { ...LINHAS_REAIS[0], transaction_date: "2025-09-20" }));
});

Deno.test("A1: outro tipo de proposta para a mesma linha é fato novo (virou transferência)", async () => {
  const { admin } = bancoFalso({ finance_review_queue: filaReal() });
  const recusas = await lerRecusas(admin, [PIX_1000]);
  assert(!ficaForaPelaRecusa(recusas, LINHAS_REAIS[4], true));
  assertEquals(tipoDaProposta({ transaction_type: "credit", counterparty_document: "12.345.678/0001-90" }, false, "12345678000190"), "internal_transfer");
  assertEquals(tipoDaProposta({ transaction_type: "debit" }, false, ""), "create_payable");
  assertEquals(tipoDaProposta({ transaction_type: "credit" }, false, ""), "create_receivable");
});

Deno.test("A1: só a ÚLTIMA proposta da linha + tipo decide — recusa seguida de aprovação não segura", () => {
  const tx = { id: uuid(), transaction_date: "2026-07-26", amount: 80, transaction_type: "debit", description: "TICKETEXPRESS" };
  const fila = [
    proposta(tx, "rejected", "2026-07-29T10:00:00Z", { kind: "internal_transfer" }),
    proposta(tx, "rejected", "2026-07-29T11:00:00Z", { kind: "internal_transfer" }),
    proposta(tx, "approved", "2026-07-31T10:00:00Z", { kind: "internal_transfer" }),
  ];
  assertEquals(recusasPorLinha(fila).size, 0);
  // e o aviso do vigia nunca conta como recusa da linha
  const aviso = { ...proposta(tx, "rejected", "2026-08-01T10:00:00Z"), kind: "anomaly" };
  assertEquals(recusasPorLinha([aviso]).size, 0);
  // a pendente mais nova também não é recusa (o gerar já pula pela fila)
  assertEquals(recusasPorLinha([proposta(tx, "rejected", "2026-08-01T10:00:00Z"), proposta(tx, "pending", "2026-08-02T10:00:00Z")]).size, 0);
});

Deno.test("A1: compra parcelada recusada — o valor da proposta é o total, então só a data conta", () => {
  const r = { id: "r", kind: "create_payable", suggested_date: "2026-09-18", suggested_amount: 287.64, title: "Despesa: MERCADOLIVRE (2x)", decided_at: null };
  assert(!linhaMudou(r, { transaction_date: "2026-09-18", amount: 143.82 }));
  assert(linhaMudou(r, { transaction_date: "2026-09-19", amount: 143.82 }));
  // sem data na proposta, vale o valor
  assert(linhaMudou({ ...r, title: "Despesa: X", suggested_date: null }, { transaction_date: "2026-09-18", amount: 1 }));
  assert(!linhaMudou({ ...r, title: "Despesa: X", suggested_date: null }, { transaction_date: "2026-09-18", amount: 287.64 }));
});

Deno.test("A1: lerRecusas lê em pedaços de 150 e ignora id que não é uuid", async () => {
  const fila: Qualquer[] = [];
  const txs = Array.from({ length: 320 }, (_, i) => ({ id: uuid(), transaction_date: "2026-10-01", amount: i + 1, description: "x" }));
  for (const tx of txs) fila.push({ ...proposta(tx, "rejected", "2026-10-02T00:00:00Z"), kind: "create_payable" });
  const banco = bancoFalso({ finance_review_queue: fila });
  const recusas = await lerRecusas(banco.admin, [...txs.map((t) => t.id), "nao-e-uuid"]);
  assertEquals(recusas.size, 320);
  assertEquals(banco.chamadas.filter((c) => c.tabela === "finance_review_queue").length, 3);
});

// ── A2: recusar uma ENTRADA tira a linha do banco da fila (o caminho de sempre das linhas sem lançamento).
function cenarioDeRecusa() {
  const entrada = { id: uuid(), transaction_type: "credit", reconciled: false, dismissed_reason: null, dismissed_kind: null, dismissed_at: null, dismissed_by: null, amount: 11.40 };
  const saida = { id: uuid(), transaction_type: "debit", reconciled: false, dismissed_reason: null, dismissed_kind: null, dismissed_at: null, dismissed_by: null, amount: 50 };
  const conciliada = { id: uuid(), transaction_type: "credit", reconciled: true, dismissed_reason: null, dismissed_kind: null, dismissed_at: null, dismissed_by: null, amount: 70 };
  const pE = { id: uuid(), kind: "create_receivable", status: "pending", bank_transaction_id: entrada.id, title: "Receita: ARTERIS", suggested_amount: 11.40, created_at: "2026-10-01" };
  const pS = { id: uuid(), kind: "create_payable", status: "pending", bank_transaction_id: saida.id, title: "Despesa: X", suggested_amount: 50, created_at: "2026-10-01" };
  const pC = { id: uuid(), kind: "create_receivable", status: "pending", bank_transaction_id: conciliada.id, title: "Receita: Y", suggested_amount: 70, created_at: "2026-10-01" };
  const pJa = { id: uuid(), kind: "create_payable", status: "approved", bank_transaction_id: null, title: "Já decidida", suggested_amount: 1, created_at: "2026-10-01" };
  return { entrada, saida, conciliada, pE, pS, pC, pJa };
}

Deno.test("A2: recusar a entrada marca a linha (manual, 'Recusada na fila: …', quem e quando) e anota 'ignorou'", async () => {
  const c = cenarioDeRecusa();
  const banco = bancoFalso({ finance_review_queue: [c.pE, c.pS, c.pC, c.pJa], bank_transactions: [c.entrada, c.saida, c.conciliada] });
  const anotacoes: Qualquer[] = [];
  const r = await recusarPropostas(banco.admin, [c.pE.id, c.pS.id, c.pC.id, c.pJa.id], "dono", "estorno de pedágio, não é receita",
    async (reg) => { anotacoes.push(reg); });
  assertEquals(r.status, 200);
  assertEquals(r.corpo.recusadas, 3);
  assertEquals(r.corpo.entradas_fora_da_fila, 1);
  assertStringIncludes(String(r.corpo.message), "Fora da fila");
  assertStringIncludes(String(r.corpo.message), "1 já não estava(m) pendente(s)");
  assertEquals(c.entrada.reconciled, true);
  assertEquals(c.entrada.dismissed_kind, "manual");
  assertEquals(c.entrada.dismissed_reason, "Recusada na fila: estorno de pedágio, não é receita");
  assertEquals(c.entrada.dismissed_by, "dono");
  assert(c.entrada.dismissed_at);
  // a SAÍDA recusada não é marcada (a despesa existe e não está lançada)
  assertEquals([c.saida.reconciled, c.saida.dismissed_kind], [false, null]);
  // a linha que outro caminho já conciliou não é tocada
  assertEquals([c.conciliada.reconciled, c.conciliada.dismissed_kind], [true, null]);
  assertEquals(anotacoes.length, 1);
  assertEquals([anotacoes[0].acao, anotacoes[0].bank_transaction_id], ["ignorou", c.entrada.id]);
  assertEquals([c.pE.status, c.pS.status, c.pC.status], ["rejected", "rejected", "rejected"]);
});

Deno.test("A2: sem nota, o motivo diz 'não é receita a lançar'; falha ao marcar vira aviso, a recusa fica", async () => {
  assertEquals(motivoDaRecusa(null), `${PREFIXO_DA_RECUSA}: não é receita a lançar`);
  const c = cenarioDeRecusa();
  const banco = bancoFalso({ finance_review_queue: [c.pE], bank_transactions: [c.entrada] },
    { "bank_transactions:update": { message: "sem permissão" } });
  const r = await recusarPropostas(banco.admin, [c.pE.id], "dono", null, async () => {});
  assertEquals([r.corpo.ok, r.corpo.recusadas, r.corpo.entradas_fora_da_fila], [false, 1, 0]);
  assertStringIncludes(String(r.corpo.message), "não saiu da fila");
  assertEquals(c.pE.status, "rejected");
});

Deno.test("A2: lista vazia é 400", async () => {
  const banco = bancoFalso({});
  assertEquals((await recusarPropostas(banco.admin, [], "dono", null, async () => {})).status, 400);
});

// ── A4: desfazer com ids de PROPOSTA.
function depsFalsas(lancada: Record<string, string> = {}) {
  const undismiss: string[][] = [];
  const anotacoes: Qualquer[] = [];
  return {
    undismiss, anotacoes,
    deps: {
      anotar: async (reg: Qualquer) => { anotacoes.push(reg); },
      lancamentoDaTransacao: async (tx: string) => lancada[tx] ?? null,
      desfazerIgnorada: async (txIds: string[]) => {
        undismiss.push(txIds);
        return { ok: true, transacoes: txIds.length, propostas_reabertas: txIds.length, message: `${txIds.length} transação(ões) de volta à fila` };
      },
    },
  };
}

Deno.test("A4: a entrada recusada (linha em Fora da fila) volta pelo undismiss — com o id da LINHA, não o da proposta", async () => {
  const c = cenarioDeRecusa();
  Object.assign(c.entrada, { reconciled: true, dismissed_kind: "manual", dismissed_reason: "Recusada na fila: x" });
  Object.assign(c.pE, { status: "rejected" });
  const banco = bancoFalso({ finance_review_queue: [c.pE], bank_transactions: [c.entrada] });
  const f = depsFalsas();
  const r = await reabrirPropostas(banco.admin, [c.pE.id], "dono", f.deps);
  assertEquals(f.undismiss, [[c.entrada.id]]);
  assertEquals([r.corpo.ok, r.corpo.linhas_de_volta, r.corpo.reabertas], [true, 1, 1]);
});

Deno.test("A4: a transferência aprovada (as duas pernas fora da fila) também volta pelo undismiss", async () => {
  const saida = { id: uuid(), reconciled: true, dismissed_kind: "transferencia", dismissed_reason: "Transferência entre contas próprias" };
  const p = { id: uuid(), kind: "internal_transfer", status: "approved", bank_transaction_id: saida.id, title: "Transferência entre contas" };
  const banco = bancoFalso({ finance_review_queue: [p], bank_transactions: [saida] });
  const f = depsFalsas();
  await reabrirPropostas(banco.admin, [p.id], "dono", f.deps);
  assertEquals(f.undismiss, [[saida.id]]);
});

Deno.test("A4: a SAÍDA recusada (linha livre) reabre a proposta e anota 'devolveu'", async () => {
  const c = cenarioDeRecusa();
  Object.assign(c.pS, { status: "rejected", decided_by: "dono", decided_at: "2026-10-02" });
  const banco = bancoFalso({ finance_review_queue: [c.pS], bank_transactions: [c.saida] });
  const f = depsFalsas();
  const r = await reabrirPropostas(banco.admin, [c.pS.id], "dono", f.deps);
  assertEquals([r.corpo.ok, r.corpo.reabertas], [true, 1]);
  assertEquals((c.pS as Qualquer).status, "pending");
  assertEquals([(c.pS as Qualquer).decided_by, (c.pS as Qualquer).decided_at], [null, null]);
  assertStringIncludes(String((c.pS as Qualquer).decision_note), "Recusa desfeita em");
  assertEquals(f.undismiss.length, 0);
  assertEquals(f.anotacoes[0].acao, "devolveu");
});

Deno.test("A4: não reabre o que mudou — lançada, outra pendente, conciliada; aprovada aponta o desfazer certo", async () => {
  const c = cenarioDeRecusa();
  const livre2 = { id: uuid(), transaction_type: "debit", reconciled: false, dismissed_reason: null, dismissed_kind: null };
  const livre3 = { id: uuid(), transaction_type: "debit", reconciled: false, dismissed_reason: null, dismissed_kind: null };
  const conciliada = { id: uuid(), transaction_type: "debit", reconciled: true, dismissed_reason: null, dismissed_kind: null };
  const recusadaLancada = { id: uuid(), kind: "create_payable", status: "rejected", bank_transaction_id: livre2.id, title: "Lançada à mão" };
  const recusadaComOutra = { id: uuid(), kind: "create_payable", status: "rejected", bank_transaction_id: livre3.id, title: "Tem outra" };
  const outraPendente = { id: uuid(), kind: "create_payable", status: "pending", bank_transaction_id: livre3.id, title: "A nova" };
  const recusadaConciliada = { id: uuid(), kind: "create_payable", status: "rejected", bank_transaction_id: conciliada.id, title: "Conciliada" };
  const aprovada = { id: uuid(), kind: "create_payable", status: "approved", bank_transaction_id: c.saida.id, title: "Aprovada" };
  const banco = bancoFalso({
    finance_review_queue: [recusadaLancada, recusadaComOutra, outraPendente, recusadaConciliada, aprovada],
    bank_transactions: [livre2, livre3, conciliada, c.saida],
  });
  const f = depsFalsas({ [livre2.id]: 'despesa "Peças" (Peças e materiais)' });
  const desconhecida = uuid();
  const r = await reabrirPropostas(banco.admin,
    [recusadaLancada.id, recusadaComOutra.id, recusadaConciliada.id, aprovada.id, outraPendente.id, desconhecida], "dono", f.deps);
  const falhas = (r.corpo.falhas as string[]).join(" | ");
  assertEquals([r.corpo.ok, r.corpo.reabertas], [false, 0]);
  assertStringIncludes(falhas, "já foi lançada como despesa");
  assertStringIncludes(falhas, "já há outra proposta pendente desta linha");
  assertStringIncludes(falhas, "já foi conciliada por outro caminho");
  assertStringIncludes(falhas, "desfazer_aprovacao_de_lancamento");
  assertStringIncludes(falhas, "já está na fila");
  assertStringIncludes(falhas, "não está na caixa de entrada");
  assertEquals([recusadaLancada.status, recusadaComOutra.status, recusadaConciliada.status], ["rejected", "rejected", "rejected"]);
});

Deno.test("A4: o aviso do vigia descartado volta para a lista", async () => {
  const aviso = { id: uuid(), kind: "anomaly", status: "rejected", bank_transaction_id: null, title: "Possível duplicidade" };
  const banco = bancoFalso({ finance_review_queue: [aviso] });
  const r = await reabrirPropostas(banco.admin, [aviso.id], "dono", depsFalsas().deps);
  assertEquals([r.corpo.reabertas, aviso.status], [1, "pending"]);
});

Deno.test("A4: sem id de proposta válido é 400 (o modelo mandou outra coisa)", async () => {
  const banco = bancoFalso({});
  assertEquals((await reabrirPropostas(banco.admin, ["abc"], "dono", depsFalsas().deps)).status, 400);
});

// ── O undismiss reabre só a ÚLTIMA proposta de cada linha + tipo (os estornos recusados duas vezes).
Deno.test("undismiss: linha recusada duas vezes reabre só a última; reabrir as duas estoura o índice", async () => {
  const fila = filaReal().filter((p) => p.bank_transaction_id === ARTERIS_1);
  assertEquals(fila.length, 2);
  const escolhidas = propostasAReabrir(fila);
  assertEquals(escolhidas, [fila[1].id]);
  const banco = bancoFalso({ finance_review_queue: fila });
  const todas = await banco.admin.from("finance_review_queue").update({ status: "pending" }).in("id", fila.map((p) => p.id));
  assertEquals(todas.error?.code, "23505");
  const so = await banco.admin.from("finance_review_queue").update({ status: "pending" }).in("id", escolhidas);
  assertEquals(so.error, null);
});

Deno.test("undismiss: transferência recusada, recusada e aprovada reabre a aprovada; aviso do vigia não volta", () => {
  const tx = { id: uuid(), transaction_date: "2026-07-26", amount: 80, description: "TICKETEXPRESS" };
  const fila = [
    proposta(tx, "rejected", "2026-07-29T10:00:00Z", { kind: "internal_transfer" }),
    proposta(tx, "rejected", "2026-07-29T11:00:00Z", { kind: "internal_transfer" }),
    proposta(tx, "approved", "2026-07-31T10:00:00Z", { kind: "internal_transfer" }),
    { ...proposta(tx, "approved", "2026-08-01T10:00:00Z"), kind: "anomaly", bank_transaction_id: null },
  ];
  assertEquals(propostasAReabrir(fila), [fila[2].id]);
});
