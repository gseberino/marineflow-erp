// A rodada do lembrete antes do vencimento (dono, 26/11/2026: "2. A" — o lembrete pede o "sim" dele). O que se protege:
// nada vai ao cliente; a janela [hoje, hoje + N] pega o que a rodada anterior não perguntou; conta já pedida (mesmo
// vencimento) não é perguntada de novo; o que não passa nas travas fica de fora, com o motivo; o pedido ao dono é uma
// pendência de risco alto com o cartão e o retrato, guardada na conversa, com a referência para o ajuste.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { MAX_LEMBRETES_POR_RODADA, pedirSimAoDono, perguntaDoVencimento, proporLembretesDeVencimento } from "./propor.ts";
import { relogioDoLembreteDeVencimento } from "../_shared/receivables/lembrete-de-vencimento.ts";
import { ambiente, conta, CONTA, flavio, FLAVIO, type Linha } from "../_shared/receivables/lembrete-de-vencimento-banco_test.ts";

relogioDoLembreteDeVencimento.agora = () => new Date("2026-11-26T15:00:00Z");
const HOJE = "2026-11-26";
const id = (n: number) => `44444444-4444-4444-8444-4444444441${String(n).padStart(2, "0")}`;
const semNbsp = (x: unknown) => String(x ?? "").replace(/ /g, " ");

/** O fetch do whatsapp-send (a pergunta ao dono), gravando o que foi mandado. Nada pode ir a cliente aqui. */
async function comEnvio<T>(corpo: (enviados: Linha[]) => Promise<T>): Promise<T> {
  const original = globalThis.fetch;
  const enviados: Linha[] = [];
  globalThis.fetch = ((_url: unknown, init?: RequestInit) => {
    enviados.push(JSON.parse(String(init?.body ?? "{}")));
    return Promise.resolve(new Response(JSON.stringify({ success: true, messageId: "w1" }), { status: 200 }));
  }) as typeof fetch;
  try {
    return await corpo(enviados);
  } finally {
    globalThis.fetch = original;
  }
}

Deno.test("a janela é de hoje até daqui a N dias: vencida, depois da janela, já lembrada, sinal e paga ficam de fora", async () => {
  const db = ambiente({
    receivables: [
      conta({ id: id(1), due_date: "2026-11-26" }),
      conta({ id: id(2), due_date: "2026-11-29" }),
      conta({ id: id(3), due_date: "2026-11-30" }), // depois da janela (N = 3)
      conta({ id: id(4), due_date: "2026-11-25" }), // já venceu: é cobrança
      conta({ id: id(5), due_date: "2026-11-28", reminder_sent_at: "2026-11-01T12:00:00Z" }), // dispensada ao nascer
      conta({ id: id(6), due_date: "2026-11-28", is_deposit: true }),
      conta({ id: id(7), due_date: "2026-11-28", status: "paid", paid_amount: 3292, balance_amount: 0 }),
    ],
  });
  const r = await proporLembretesDeVencimento(db, { hoje: HOJE, diasAntes: 3 });
  assertEquals(r.propostas.map((l) => l.conta.id), [id(1), id(2)]);
  assertEquals(r.pulados, []);
  assertStringIncludes(r.propostas[0].texto, "vence *hoje*");
});

Deno.test("conta já pedida ao dono com o mesmo vencimento não é perguntada de novo; vencimento novo, pedido novo", async () => {
  const pedido = (conta: string, vencimento: string, status = "rejected") => ({
    action_name: "enviar_lembrete_de_vencimento", status, payload: { receivable_id: conta, _retrato: { vencimento } },
  });
  const db = ambiente({
    receivables: [conta({ id: id(1), due_date: "2026-11-28" }), conta({ id: id(2), due_date: "2026-11-29" })],
    ai_operator_pending_actions: [pedido(id(1), "2026-11-28"), pedido(id(2), "2026-11-20", "executed")],
  });
  const r = await proporLembretesDeVencimento(db, { hoje: HOJE, diasAntes: 3 });
  assertEquals(r.propostas.map((l) => l.conta.id), [id(2)]);
  assertEquals(r.jaPedidas, 1);
});

Deno.test("o que não passa nas travas fica de fora com o motivo; no máximo 10 por rodada", async () => {
  const db = ambiente({
    receivables: [conta({ id: id(1) }), conta({ id: id(2), client_id: "outro" })],
    clients: [flavio(), flavio({ id: "outro", name: "Nelson", opt_out_whatsapp: true })],
  });
  const r = await proporLembretesDeVencimento(db, { hoje: HOJE, diasAntes: 3 });
  assertEquals(r.propostas.map((l) => l.conta.id), [id(1)]);
  assertEquals(r.pulados, [{ conta: id(2), motivo: "Este cliente pediu para não receber mensagens no WhatsApp (opt-out)." }]);

  const muitas = ambiente({ receivables: Array.from({ length: 12 }, (_, k) => conta({ id: id(k + 1) })) });
  assertEquals((await proporLembretesDeVencimento(muitas, { hoje: HOJE, diasAntes: 3 })).propostas.length, MAX_LEMBRETES_POR_RODADA);
});

Deno.test("leitura que falha LANÇA: a rodada não pergunta nada", async () => {
  for (const tabela of ["receivables", "ai_operator_pending_actions", "app_settings"]) {
    let lancou = false;
    try {
      await proporLembretesDeVencimento(ambiente({}, [tabela]), { hoje: HOJE, diasAntes: 3 });
    } catch {
      lancou = true;
    }
    assert(lancou, tabela);
  }
});

Deno.test("o pedido ao dono: pendências de risco alto com o cartão e o retrato, a primeira na conversa, a referência no histórico — e nada ao cliente", async () => {
  const db = ambiente({
    receivables: [conta({ id: id(1) }), conta({ id: id(2), due_date: "2026-11-28" })],
    ai_operator_sessions: [{ id: "sessao-1", metadata: { outra: 1 } }],
  });
  const r = await proporLembretesDeVencimento(db, { hoje: HOJE, diasAntes: 3 });
  await comEnvio(async (enviados) => {
    const ids = await pedirSimAoDono(db, { id: "dono-1", phone: "5547999159654" }, "sessao-1", { outra: 1 }, r.propostas,
      { teste: false, conversaLigada: false, agora: new Date("2026-11-26T13:40:00Z") });
    assertEquals(ids.length, 2);
    // a pergunta vai SÓ ao dono
    assertEquals(enviados.map((e) => e.phone), ["5547999159654"]);
    const pergunta = semNbsp(enviados[0].message);
    assertStringIncludes(pergunta, "Lembretes antes do vencimento para aprovar hoje: 2. O primeiro:");
    assertStringIncludes(pergunta, "Posso mandar este lembrete a Flávio da Igreja?");
    assertStringIncludes(pergunta, "Mensagem que vai ao cliente:\nOlá Flávio!");
    assertStringIncludes(pergunta, "Para aprovar, responda: *sim <SEU PIN>*");
  });
  const pend = db.tabelas.ai_operator_pending_actions;
  assertEquals(pend.map((p: Linha) => [p.action_name, p.risk_level, p.status, p.title]), [
    ["enviar_lembrete_de_vencimento", "high", "pending", "Lembrete de vencimento para Flávio da Igreja"],
    ["enviar_lembrete_de_vencimento", "high", "pending", "Lembrete de vencimento para Flávio da Igreja"],
  ]);
  assertEquals(pend[0].payload.receivable_id, id(1));
  assertEquals(pend[0].payload._retrato.vencimento, "2026-11-29");
  assertEquals(pend[0].expires_at, "2026-11-27T13:40:00.000Z");
  assertEquals(db.tabelas.ai_operator_sessions[0].metadata.pending_confirm_action_id, pend[0].id);
  assertEquals(db.tabelas.ai_operator_sessions[0].metadata.outra, 1);
  const historico = db.tabelas.ai_operator_messages.map((m: Linha) => m.content).join("\n");
  assertStringIncludes(historico, `[lembrete de vencimento — enviar_lembrete_de_vencimento: receivable_id=${id(1)}]`);
  assertEquals(db.tabelas.ai_operator_audit[0].event_type, "lembretes_de_vencimento:propostos");
});

Deno.test("a pergunta de um só não tem cabeçalho de leva; no modo de teste avisa", async () => {
  const db = ambiente();
  const [l] = (await proporLembretesDeVencimento(db, { hoje: HOJE, diasAntes: 3 })).propostas;
  const p = perguntaDoVencimento(l, true, 1);
  assert(p.startsWith(`Posso mandar este lembrete a Flávio da Igreja?`), p);
  assertStringIncludes(p, "Modo de teste ligado");
  assertEquals(l.conta.id, CONTA);
  assertEquals(l.conta.client_id, FLAVIO);
});

Deno.test("pedido que venceu sem resposta pergunta de novo no dia seguinte; recusado, executado ou ainda esperando, não", async () => {
  const pedido = (conta: string, status: string, expires_at: string) => ({
    action_name: "enviar_lembrete_de_vencimento", status, expires_at, payload: { receivable_id: conta, _retrato: { vencimento: "2026-11-29" } },
  });
  const db = ambiente({
    receivables: [1, 2, 3, 4, 5].map((n) => conta({ id: id(n) })),
    ai_operator_pending_actions: [
      pedido(id(1), "expired", "2026-11-25T13:40:00Z"),
      pedido(id(2), "pending", "2026-11-25T13:40:00Z"), // venceu e ninguém marcou
      pedido(id(3), "pending", "2026-11-27T13:40:00Z"), // ainda esperando o dono
      pedido(id(4), "rejected", "2026-11-25T13:40:00Z"),
      pedido(id(5), "executed", "2026-11-25T13:40:00Z"),
    ],
  });
  const r = await proporLembretesDeVencimento(db, { hoje: HOJE, diasAntes: 3, agora: new Date("2026-11-26T13:40:00Z") });
  assertEquals(r.propostas.map((l) => l.conta.id), [id(1), id(2)]);
  assertEquals(r.jaPedidas, 3);
});

Deno.test("as pendências da rodada entram num insert só (tudo ou nada)", async () => {
  const db = ambiente({ receivables: [conta({ id: id(1) }), conta({ id: id(2) })], ai_operator_sessions: [{ id: "sessao-1", metadata: {} }] });
  const r = await proporLembretesDeVencimento(db, { hoje: HOJE, diasAntes: 3 });
  await comEnvio(async () => {
    await pedirSimAoDono(db, { id: "dono-1", phone: "5547999159654" }, "sessao-1", {}, r.propostas,
      { teste: false, conversaLigada: false, agora: new Date("2026-11-26T13:40:00Z") });
  });
  const inserts = db.chamadas.insert.filter(([t]: [string]) => t === "ai_operator_pending_actions");
  assertEquals(inserts.length, 1);
  assertEquals((inserts[0][1] as Linha[]).length, 2);
  // insert que falha: nada fica e a rodada lança
  const falha = ambiente({ receivables: [conta({ id: id(1) })] }, ["ai_operator_pending_actions"]);
  let lancou = false;
  try {
    await pedirSimAoDono(falha, { id: "dono-1", phone: "5547999159654" }, "sessao-1", {}, r.propostas.slice(0, 1),
      { teste: false, conversaLigada: false, agora: new Date("2026-11-26T13:40:00Z") });
  } catch {
    lancou = true;
  }
  assert(lancou);
  assertEquals(falha.tabelas.ai_operator_pending_actions ?? [], []);
});
