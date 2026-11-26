// A tool enviar_lembrete_de_vencimento (dono, 26/11/2026: "2. A"): o "sim" do dono no lembrete ANTES do vencimento. O que se
// protege: o pedido vira pendência com o cartão e o retrato; sem retrato, de outro cargo ou com algo mudado, nada sai; o
// portão de horário barra; o envio usa a chave de antes e marca a conta; o modo de teste não marca nada; nunca autônoma.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { toolsByName } from "./index.ts";
import { buildPendingSummary, executarChamadaDeTool, resumoQueRecusa, tituloDaAcao } from "../agent.ts";
import { NEVER_AUTONOMOUS } from "../autonomy-policy.ts";
import { PERFIL_ADMIN, PERFIL_OPERACAO, SO_PELA_REDE } from "../perfil-operacao.ts";
import { relogioDoLembreteDeVencimento } from "../../receivables/lembrete-de-vencimento.ts";
import { ambiente, conta, CONTA, type Linha } from "../../receivables/lembrete-de-vencimento-banco_test.ts";

// 26/11/2026 às 12h em Brasília: dentro do horário de mensagem ao cliente.
relogioDoLembreteDeVencimento.agora = () => new Date("2026-11-26T15:00:00Z");

const tool = toolsByName["enviar_lembrete_de_vencimento"];
const semNbsp = (x: unknown) => String(x ?? "").replace(/ /g, " ");
// deno-lint-ignore no-explicit-any
const contexto = (db: any, extra: Linha = {}) => ({ sb: db, admin: db, userId: "dono-1", userRole: "admin" as const, jwt: "", appOrigin: "", settings: {}, ...extra });
// deno-lint-ignore no-explicit-any
const amb = (ctx: any) => ({ toolsByName, alcancaveisPelaRede: {}, toolCtx: ctx, sessionId: "s1", channel: "whatsapp" as const });

/** O fetch do whatsapp-send, gravando o que foi mandado. */
async function comEnvio<T>(resposta: Linha, corpo: (enviados: Linha[]) => Promise<T>, status = 200): Promise<T> {
  const original = globalThis.fetch;
  const enviados: Linha[] = [];
  globalThis.fetch = ((_url: unknown, init?: RequestInit) => {
    enviados.push(JSON.parse(String(init?.body ?? "{}")));
    return Promise.resolve(new Response(JSON.stringify(resposta), { status }));
  }) as typeof fetch;
  try {
    return await corpo(enviados);
  } finally {
    globalThis.fetch = original;
  }
}

/** O pedido do modelo: vira pendência; volta o que foi gravado (título, resumo e payload com o retrato). */
// deno-lint-ignore no-explicit-any
async function pedir(db: any, input: Linha = { receivable_id: CONTA }): Promise<Linha> {
  const r = await executarChamadaDeTool({ name: "enviar_lembrete_de_vencimento", input }, amb(contexto(db)));
  // deno-lint-ignore no-explicit-any
  assertEquals((r.toolResult as any).pending, true, JSON.stringify(r.toolResult));
  // deno-lint-ignore no-explicit-any
  return db.chamadas.insert.filter(([t]: [string]) => t === "ai_operator_pending_actions").map(([, v]: [string, Linha]) => v).at(-1);
}

Deno.test("registrada: risco alto (o modelo sempre vê, fora do teto dos perfis), só admin e financeiro, nunca autônoma, com título", () => {
  assert(tool, "a tool existe");
  assertEquals(tool.risk, "high");
  assertEquals(tool.roles, ["admin", "financial"]);
  assert(NEVER_AUTONOMOUS.has("enviar_lembrete_de_vencimento"));
  // risco alto entra sempre na lista do modelo (agent.ts): nem perfil (no teto de 113) nem a rede
  assert(!SO_PELA_REDE.has("enviar_lembrete_de_vencimento"));
  assert(!PERFIL_OPERACAO.has("enviar_lembrete_de_vencimento") && !PERFIL_ADMIN.has("enviar_lembrete_de_vencimento"));
  assertEquals(tituloDaAcao("enviar_lembrete_de_vencimento"), "Lembrete antes do vencimento (WhatsApp)");
});

Deno.test("o pedido vira pendência com o cartão (quem, número, conta, mensagem exata) e o retrato", async () => {
  const db = ambiente();
  const p = await pedir(db);
  const s = semNbsp(p.summary);
  assertStringIncludes(s, "Lembrete ANTES do vencimento para *Flávio da Igreja* — WhatsApp +55 (47) 99999-0001");
  assertStringIncludes(s, "Conta: Saldo — OS-00134 · *R$ 3.292,00* · vence 29/11/2026 (em 3 dias)");
  assertStringIncludes(s, "Mensagem que vai ao cliente:\nOlá Flávio! 👋 Lembramos que o pagamento de *R$ 3.292,00*");
  assertEquals(p.payload._retrato.conta, CONTA);
  assertEquals(p.payload._retrato.vencimento, "2026-11-29");
  assertEquals(p.risk_level, "high");
});

Deno.test("trava vira recusa sem pendência ('⚠️' numa linha); retrato que falhou também", async () => {
  const db = ambiente({ receivables: [conta({ due_date: "2026-11-20" })] });
  const s = await buildPendingSummary(db, "enviar_lembrete_de_vencimento", { receivable_id: CONTA }, { userId: "dono-1" });
  assertStringIncludes(s, "⚠️ Esta conta já venceu (20/11/2026)");
  assert(resumoQueRecusa("enviar_lembrete_de_vencimento", s));
  const semRetrato = await buildPendingSummary(ambiente(), "enviar_lembrete_de_vencimento", { receivable_id: CONTA }, { userId: "dono-1", retrato: null });
  assertEquals(semRetrato, "⚠️ Não consegui conferir a conta agora. Nada foi enviado; tente de novo.");
  const falha = await buildPendingSummary(ambiente({}, ["clients"]), "enviar_lembrete_de_vencimento", { receivable_id: CONTA }, { userId: "dono-1" });
  assertStringIncludes(falha, "⚠️ Não consegui conferir a conta agora (Não consegui ler o cadastro do cliente");
});

Deno.test("o 'sim' manda o texto do cartão com a chave de antes, ao número do cadastro, e marca a conta", async () => {
  const db = ambiente();
  const p = await pedir(db);
  await comEnvio({ success: true, messageId: "m1" }, async (enviados) => {
    // deno-lint-ignore no-explicit-any
    const r = await tool.execute(p.payload, contexto(db)) as any;
    assertEquals(r.ok, true, JSON.stringify(r));
    assertEquals(enviados.length, 1);
    assertEquals(enviados[0].phone, "5547999990001");
    assertEquals(enviados[0].dedupe_key, `lembrete-recebivel:${CONTA}:2026-11-29`);
    assertEquals(semNbsp(enviados[0].message), semNbsp(p.payload._retrato.texto));
  });
  assertEquals(db.tabelas.receivables[0].reminder_sent_at, "2026-11-26T15:00:00.000Z");
  const marca = db.chamadas.update.find(([t]: [string]) => t === "receivables");
  assertEquals(marca[2], [["eq", "id", CONTA], ["is", "reminder_sent_at", null]]);
});

Deno.test("nada sai: sem retrato, cargo que não é admin/financeiro, ou algo mudou depois do pedido", async () => {
  const db = ambiente();
  const p = await pedir(db);
  await comEnvio({ success: true }, async (enviados) => {
    // deno-lint-ignore no-explicit-any
    const semRetrato = await tool.execute({ receivable_id: CONTA }, contexto(db)) as any;
    assertStringIncludes(semRetrato.error, "não guardou o que você aprovou");
    // deno-lint-ignore no-explicit-any
    const vendedor = await tool.execute(p.payload, contexto(db, { userRole: "seller" })) as any;
    assertStringIncludes(vendedor.error, "Só administrador ou financeiro");
    // o cliente pagou um pedaço entre a pergunta e o "sim"
    Object.assign(db.tabelas.receivables[0], { paid_amount: 1000, balance_amount: 2292, status: "partially_paid" });
    // deno-lint-ignore no-explicit-any
    const mudou = await tool.execute(p.payload, contexto(db)) as any;
    assertStringIncludes(semNbsp(mudou.error), "o valor mudou (era R$ 3.292,00, agora R$ 2.292,00) depois do pedido");
    // pagou tudo: a trava diz por quê
    Object.assign(db.tabelas.receivables[0], { paid_amount: 3292, balance_amount: 0, status: "paid" });
    // deno-lint-ignore no-explicit-any
    const paga = await tool.execute(p.payload, contexto(db)) as any;
    assertStringIncludes(paga.error, "Nada foi enviado: Esta conta já está paga");
    assertEquals(enviados, []);
  });
  assertEquals(db.tabelas.receivables[0].reminder_sent_at, null);
});

Deno.test("fora do horário o portão barra; no modo de teste vai ao número de teste, com ':teste', sem marcar a conta", async () => {
  {
    const db = ambiente();
    const p = await pedir(db);
    const antes = relogioDoLembreteDeVencimento.agora;
    relogioDoLembreteDeVencimento.agora = () => new Date("2026-11-27T01:00:00Z"); // 26/11 às 22h em Brasília
    try {
      await comEnvio({ success: true }, async (enviados) => {
        // deno-lint-ignore no-explicit-any
        const r = await tool.execute(p.payload, contexto(db)) as any;
        assertEquals(enviados, []);
        assert(r.error, JSON.stringify(r));
      });
    } finally {
      relogioDoLembreteDeVencimento.agora = antes;
    }
  }
  {
    const db = ambiente();
    const p = await pedir(db);
    await comEnvio({ success: true, messageId: "m1" }, async (enviados) => {
      // deno-lint-ignore no-explicit-any
      const r = await tool.execute(p.payload, contexto(db, { settings: { wa_test_mode: "true", wa_test_number: "5547900000000" } })) as any;
      assertEquals(enviados[0].dedupe_key, `lembrete-recebivel:${CONTA}:2026-11-29:teste`);
      assertStringIncludes(r.aviso, "número de TESTE");
    });
    assertEquals(db.tabelas.receivables[0].reminder_sent_at, null);
  }
});

Deno.test("WhatsApp recusou: não marca a conta (a rotina pode pedir de novo)", async () => {
  const db = ambiente();
  const p = await pedir(db);
  await comEnvio({ error: "Número sem WhatsApp" }, async () => {
    // deno-lint-ignore no-explicit-any
    const r = await tool.execute(p.payload, contexto(db)) as any;
    assert(r.error, JSON.stringify(r));
  }, 422);
  assertEquals(db.tabelas.receivables[0].reminder_sent_at, null);
});
