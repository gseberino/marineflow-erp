// O lembrete individual de cobrança pelo assistente (send_collection_reminder), conserto de 25/11/2026. O pedido do dono
// que guia os testes:
//   "Manda o lembrete da cobrança do João."
// A cobrança guarda R$ 2.000,00 com vencimento em 10/07; a conta a receber dela teve um pagamento parcial e a data
// mudou: hoje deve R$ 1.650,00, vencida em 22/07. O cliente tem de receber o valor e o vencimento da CONTA, com a data em
// dd/mm/aaaa, e o cartão do "sim" tem de mostrar o número inteiro, o valor conferido, o que a cobrança guardava e a
// mensagem EXATA. Cobrança ou conta paga, piso, entrada esperando no Extrato, opt-out, cadastro genérico e telefone
// NÃO viram pendência — volta o motivo.
// Rodar com:
//   deno test --allow-all --no-check --node-modules-dir=none supabase/functions/_shared/ai/tools/lembrete-de-cobranca_test.ts
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  dataDoLembrete,
  divergenciasDoLembrete,
  mensagemDoLembrete,
  montarLembreteDeCobranca,
  prazoDoLembrete,
  relogioDoLembrete,
  SEM_RETRATO_DO_LEMBRETE,
} from "./lembrete-de-cobranca.ts";
import { allTools, toolsByName } from "./index.ts";
import { buildPendingSummary, executarChamadaDeTool, resumoQueRecusa, tituloDaAcao } from "../agent.ts";
import { NEVER_AUTONOMOUS } from "../autonomy-policy.ts";

/** Intl põe espaço sem quebra entre "R$" e o valor. */
const semNbsp = (x: unknown) => String(x ?? "").replace(/ /g, " ");
const UUID_NO_TEXTO = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i;

// 25/11/2026 às 14h em Brasília: dentro do horário do portão (8h–20h), e 22/07 venceu há 126 dias.
relogioDoLembrete.agora = () => new Date("2026-11-25T17:00:00Z");

const JOAO = "7a1b2c3d-1111-4222-8333-444455556666";
const FINAL = "7a1b2c3d-2222-4222-8333-444455556666";
const COL = "33333333-3333-4333-8333-333333333001";
const CONTA = "44444444-4444-4444-8444-444444444001";
const NUMERO = "5547999990001";
const TEXTO_PADRAO = "Olá João, lembrete amigável: você possui um valor de R$ 1.650,00 com vencimento em 22/07/2026. Qualquer dúvida estamos à disposição.";

// deno-lint-ignore no-explicit-any
type Linha = Record<string, any>;

/** A cobrança como nasceu: R$ 2.000,00, vencimento 10/07 — os dois já desmentidos pela conta. */
function cobranca(extra: Linha = {}): Linha {
  return {
    id: COL, amount: 2000, due_date: "2026-07-10", contact_whatsapp: null, phone: null, contact_name: null, client_id: JOAO,
    description: "Saldo OS-00045", status: "pending", receivable_id: CONTA, service_order_id: null, last_auto_sent_at: null, ...extra,
  };
}

/** A conta a receber de hoje: pagamento parcial de R$ 350,00 e o vencimento em 22/07. */
function conta(extra: Linha = {}): Linha {
  return { id: CONTA, client_id: JOAO, amount: 2000, paid_amount: 350, balance_amount: 1650, status: "partially_paid", due_date: "2026-07-22", ...extra };
}

function cadastros(): Linha[] {
  return [
    { id: JOAO, name: "João Pereira", display_name: null, whatsapp: "(47) 99999-0001", phone: null, opt_out_whatsapp: false, generico: false },
    { id: FINAL, name: "Cliente Final", display_name: null, whatsapp: "(47) 99999-0002", phone: null, opt_out_whatsapp: false, generico: true },
  ];
}

function bancoFalso(tabelas: Record<string, Linha[]>, falhas: string[] = []) {
  const chamadas = { insert: [] as [string, Linha][], update: [] as [string, Linha, Linha][] };
  // deno-lint-ignore no-explicit-any
  const db: any = {
    chamadas,
    tabelas,
    rpc: () => Promise.resolve({ data: null, error: null }),
    from(tabela: string) {
      const filtros: Array<(l: Linha) => boolean> = [];
      const erro = falhas.includes(tabela) ? { message: `${tabela} fora do ar` } : null;
      const linhas = () => (tabelas[tabela] ?? []).filter((l) => filtros.every((f) => f(l)));
      // deno-lint-ignore no-explicit-any
      const q: any = {
        select: () => q, order: () => q, limit: () => q, range: () => q,
        eq: (c: string, v: unknown) => (filtros.push((l) => l[c] === v), q),
        neq: (c: string, v: unknown) => (filtros.push((l) => l[c] !== v), q),
        in: (c: string, vs: unknown[]) => (filtros.push((l) => vs.includes(l[c])), q),
        is: (c: string, v: unknown) => (filtros.push((l) => (l[c] ?? null) === v), q),
        maybeSingle: () => Promise.resolve({ data: erro ? null : linhas()[0] ?? null, error: erro }),
        single: () => Promise.resolve({ data: erro ? null : linhas()[0] ?? null, error: erro }),
        // deno-lint-ignore no-explicit-any
        then: (ok: any, ko: any) => Promise.resolve({ data: erro ? null : linhas(), error: erro }).then(ok, ko),
        insert: (v: Linha) => {
          chamadas.insert.push([tabela, v]);
          // deno-lint-ignore no-explicit-any
          const r: any = Promise.resolve({ data: null, error: null });
          r.select = () => ({ single: () => Promise.resolve({ data: { id: `novo-${tabela}`, ...v }, error: null }) });
          return r;
        },
        update: (v: Linha) => ({
          eq: (c: string, val: unknown) => {
            chamadas.update.push([tabela, v, { [c]: val }]);
            for (const l of tabelas[tabela] ?? []) if (l[c] === val) Object.assign(l, v);
            return Promise.resolve({ data: null, error: null });
          },
        }),
      };
      return q;
    },
  };
  return db;
}

function ambiente(tabelas: Record<string, Linha[]> = {}, falhas: string[] = []) {
  const db = bancoFalso({
    collections: [cobranca()],
    receivables: [conta()],
    clients: cadastros(),
    app_settings: [],
    finance_review_queue: [],
    app_users: [{ id: "dono-1", full_name: "Gustavo" }],
    ...tabelas,
  }, falhas);
  const ctx = { sb: db, admin: db, userId: "dono-1", userRole: "admin" as const, jwt: "", appOrigin: "", settings: {} };
  return { db, ctx };
}

const tool = toolsByName["send_collection_reminder"];
// deno-lint-ignore no-explicit-any
const amb = (ctx: any) => ({ toolsByName, alcancaveisPelaRede: {}, toolCtx: ctx, sessionId: "s1", channel: "whatsapp" as const });
// deno-lint-ignore no-explicit-any
const pendencias = (db: any) => db.chamadas.insert.filter(([t]: [string]) => t === "ai_operator_pending_actions").map(([, v]: [string, Linha]) => v);
// deno-lint-ignore no-explicit-any
const inseridos = (db: any, tabela: string) => db.chamadas.insert.filter(([t]: [string]) => t === tabela).map(([, v]: [string, Linha]) => v);
/** O texto que o cartão mostrou depois de "Mensagem que vai ao cliente:". */
const textoDoCartao = (resumo: unknown) => String(resumo).split("Mensagem que vai ao cliente:\n")[1];

/** O fetch do whatsapp-send, gravando o que foi mandado. */
async function comEnvio<T>(resposta: Linha, corpo: (enviados: Linha[]) => Promise<T>): Promise<T> {
  const original = globalThis.fetch;
  const enviados: Linha[] = [];
  globalThis.fetch = ((_url: unknown, init?: RequestInit) => {
    enviados.push(JSON.parse(String(init?.body ?? "{}")));
    return Promise.resolve(new Response(JSON.stringify(resposta), { status: 200 }));
  }) as typeof fetch;
  try {
    return await corpo(enviados);
  } finally {
    globalThis.fetch = original;
  }
}

/** O pedido do modelo: vira pendência, e volta o que foi gravado (título, resumo e payload com o retrato). */
// deno-lint-ignore no-explicit-any
async function pedir(ctx: any, db: any, input: Record<string, unknown> = { collection_id: COL }): Promise<Linha> {
  const r = await executarChamadaDeTool({ name: "send_collection_reminder", input }, amb(ctx));
  // deno-lint-ignore no-explicit-any
  assertEquals((r.toolResult as any).pending, true, JSON.stringify(r.toolResult));
  return pendencias(db).at(-1);
}

/** O pedido que NÃO vira pendência: volta o motivo, nada vai para o sino e nada é enviado. */
// deno-lint-ignore no-explicit-any
async function recusado(ctx: any, db: any, input: Record<string, unknown> = { collection_id: COL }): Promise<string> {
  return await comEnvio({ messageId: "m1" }, async (enviados) => {
    const r = await executarChamadaDeTool({ name: "send_collection_reminder", input }, amb(ctx));
    // deno-lint-ignore no-explicit-any
    const res = r.toolResult as any;
    assertEquals(res.pending, undefined, JSON.stringify(res));
    assertEquals(res.nada_registrado, true, JSON.stringify(res));
    assertEquals(pendencias(db), [], "nada vai para o sino nem pede 'sim'");
    assertEquals(enviados, [], "nada foi enviado");
    return semNbsp(res.error);
  });
}

// ── as partes puras ──────────────────────────────────────────────────────────────────────────

Deno.test("texto padrão: o mesmo de sempre, com a data em dd/mm/aaaa (antes saía em ISO)", () => {
  assertEquals(semNbsp(mensagemDoLembrete({ nome: "João", valor: 1650, vencimento: "2026-07-22" })), TEXTO_PADRAO);
  assertEquals(
    semNbsp(mensagemDoLembrete({ nome: "", valor: 20, vencimento: "2026-12-05" })),
    "Olá, lembrete amigável: você possui um valor de R$ 20,00 com vencimento em 05/12/2026. Qualquer dúvida estamos à disposição.",
  );
  assertEquals(dataDoLembrete("2026-07-22"), "22/07/2026");
  assertEquals(dataDoLembrete("2026-07-22T03:00:00+00:00"), "22/07/2026", "data não passa por fuso");
  assertEquals(dataDoLembrete(null), "");
});

Deno.test("prazo: dias de atraso, vence hoje e vence em N dias, pela data", () => {
  assertEquals(prazoDoLembrete("2026-07-22", "2026-11-25"), "vencido há 126 dias");
  assertEquals(prazoDoLembrete("2026-11-24", "2026-11-25"), "vencido há 1 dia");
  assertEquals(prazoDoLembrete("2026-11-25", "2026-11-25"), "vence hoje");
  assertEquals(prazoDoLembrete("2026-11-26", "2026-11-25"), "vence em 1 dia");
  assertEquals(prazoDoLembrete("2026-12-05", "2026-11-25"), "vence em 10 dias");
  assertEquals(prazoDoLembrete("", "2026-11-25"), "");
});

Deno.test("divergência: só quando a cobrança tem conta e os centavos ou a data não batem", () => {
  const igual = { cobranca: cobranca({ amount: 1650, due_date: "2026-07-22" }), conta: conta(), valor: 1650, vencimento: "2026-07-22" };
  // deno-lint-ignore no-explicit-any
  assertEquals(divergenciasDoLembrete(igual as any), []);
  // deno-lint-ignore no-explicit-any
  assertEquals(divergenciasDoLembrete({ cobranca: cobranca(), conta: null, valor: 2000, vencimento: "2026-07-10" } as any), []);
  // deno-lint-ignore no-explicit-any
  assertEquals(divergenciasDoLembrete({ cobranca: cobranca(), conta: conta(), valor: 1650, vencimento: "2026-07-22" } as any).map(semNbsp), [
    "A cobrança guardava R$ 2.000,00; a conta hoje é R$ 1.650,00.",
    "A cobrança guardava vencimento em 10/07/2026; a conta vence em 22/07/2026.",
  ]);
});

// ── o valor e o vencimento vêm da conta ──────────────────────────────────────────────────────

Deno.test("o valor e o vencimento são os da CONTA a receber (saldo de hoje), não os que a cobrança guardava", async () => {
  const { db } = ambiente();
  const l = await montarLembreteDeCobranca(db, db, { collection_id: COL });
  assert(!("error" in l), JSON.stringify(l));
  assertEquals([l.valor, l.vencimento, l.telefone], [1650, "2026-07-22", NUMERO]);
  const msg = semNbsp(l.mensagem);
  assertEquals(msg, TEXTO_PADRAO);
  assertEquals(msg.includes("2.000"), false, "o valor antigo da cobrança não vai ao cliente");
  assertEquals(/\d{4}-\d{2}-\d{2}/.test(msg), false, "nenhuma data em ISO no texto");
  assertEquals(msg.includes("10/07"), false, "o vencimento antigo da cobrança não vai ao cliente");
});

Deno.test("conta sem balance_amount (dado antigo): o saldo sai de amount − paid_amount, pela regra saldoDaConta", async () => {
  const { db } = ambiente({ receivables: [conta({ balance_amount: null, paid_amount: 500 })] });
  const l = await montarLembreteDeCobranca(db, db, { collection_id: COL });
  assert(!("error" in l), JSON.stringify(l));
  assertEquals(l.valor, 1500);
});

// ── o cartão do "sim" ────────────────────────────────────────────────────────────────────────

Deno.test("o cartão: cliente, número inteiro, valor conferido, vencimento com os dias de atraso, a divergência e o texto exato — sem uuid", async () => {
  const { db, ctx } = ambiente();
  const p = await pedir(ctx, db);
  assertEquals(p.title, "Enviar lembrete de cobrança");
  assertEquals(p.action_name, "send_collection_reminder");
  assertEquals(p.risk_level, "high");
  const s = semNbsp(p.summary);
  assertEquals(UUID_NO_TEXTO.test(s), false, s);
  assertEquals(s.split("\n"), [
    "Lembrete de cobrança para *João Pereira*, pelo WhatsApp *+55 (47) 99999-0001*:",
    "- Valor: *R$ 1.650,00* (o saldo da conta a receber hoje)",
    "- Vencimento: 22/07/2026 (vencido há 126 dias)",
    "- A cobrança guardava R$ 2.000,00; a conta hoje é R$ 1.650,00.",
    "- A cobrança guardava vencimento em 10/07/2026; a conta vence em 22/07/2026.",
    "Mensagem que vai ao cliente:",
    TEXTO_PADRAO,
  ]);
  // o retrato: a cobrança, o telefone de destino, o valor, o vencimento e o texto
  assertEquals(p.payload.collection_id, COL);
  assertEquals({ ...p.payload._retrato, texto: semNbsp(p.payload._retrato.texto) }, {
    cobranca: COL, telefone: NUMERO, valor: 1650, vencimento: "2026-07-22", texto: TEXTO_PADRAO,
  });
});

Deno.test("o cartão sem divergência e a vencer: nenhuma linha de 'a cobrança guardava', e 'vence em N dias'", async () => {
  const { db, ctx } = ambiente({
    collections: [cobranca({ amount: 900, due_date: "2026-12-05" })],
    receivables: [conta({ amount: 900, paid_amount: 0, balance_amount: 900, status: "pending", due_date: "2026-12-05" })],
  });
  const s = semNbsp((await pedir(ctx, db)).summary);
  assertStringIncludes(s, "- Valor: *R$ 900,00* (o saldo da conta a receber hoje)\n- Vencimento: 05/12/2026 (vence em 10 dias)\nMensagem que vai ao cliente:\n");
  assertEquals(s.includes("guardava"), false, s);
});

Deno.test("o modelo não escolhe o retrato: o que vier em _retrato nos argumentos é trocado pelo lido do banco", async () => {
  const { db, ctx } = ambiente();
  const p = await pedir(ctx, db, { collection_id: COL, _retrato: { cobranca: COL, telefone: "5547900000000", valor: 1, vencimento: "2030-01-01", texto: "x" } });
  assertEquals([p.payload._retrato.telefone, p.payload._retrato.valor], [NUMERO, 1650]);
});

// ── o "sim" ──────────────────────────────────────────────────────────────────────────────────

Deno.test("o 'sim': envia EXATAMENTE o texto do cartão ao número do cartão e registra o envio na cobrança", async () => {
  const { db, ctx } = ambiente();
  const p = await pedir(ctx, db);
  await comEnvio({ messageId: "m1" }, async (enviados) => {
    // deno-lint-ignore no-explicit-any
    const r = await tool.execute(p.payload, ctx) as any;
    assertEquals(r.ok, true, JSON.stringify(r));
    assertEquals(enviados.length, 1);
    assertEquals(enviados[0].phone, NUMERO);
    assertEquals(enviados[0].message, textoDoCartao(p.summary), "o que vai ao cliente é o que o dono leu");
    assertEquals(enviados[0].kind, "text");
    // a chave do dia continua a mesma: cobrança + dia em Brasília
    assertEquals(enviados[0].dedupe_key, `cobranca:${COL}:2026-11-25`);
    // o registro do envio, como sempre: contato 'whatsapp_sent', situação 'enviada' e o registro de comunicação
    assertEquals(inseridos(db, "collection_contacts").map((c: Linha) => [c.collection_id, c.contact_type, c.notes]), [
      [COL, "whatsapp_sent", "Lembrete enviado pelo assistente (WhatsApp)"],
    ]);
    const col = db.tabelas.collections[0];
    assertEquals(col.status, "sent");
    assert(col.last_auto_sent_at, "last_auto_sent_at gravado");
    assertEquals(inseridos(db, "ai_comms_log").map((l: Linha) => [l.tipo, l.status, l.phone, l.entity_id]), [["cobranca", "sent", NUMERO, JOAO]]);
    // o lembrete não mexe em valor nenhum: nem na conta, nem no valor que a cobrança guarda
    assertEquals(db.chamadas.update.filter(([t]: [string]) => t !== "collections"), []);
    assertEquals([col.amount, col.due_date], [2000, "2026-07-10"]);
  });
});

Deno.test("o 'sim' repetido no mesmo dia: o whatsapp-send reconhece a chave e nada é registrado de novo na cobrança", async () => {
  const { db, ctx } = ambiente();
  const p = await pedir(ctx, db);
  await comEnvio({ deduplicated: true }, async () => {
    // deno-lint-ignore no-explicit-any
    const r = await tool.execute(p.payload, ctx) as any;
    assertEquals(r.deduplicated, true);
    assertEquals(inseridos(db, "collection_contacts"), []);
    assertEquals(db.tabelas.collections[0].status, "pending");
  });
});

Deno.test("custom_message é o texto inteiro: o cartão mostra a frase e o valor conferido, e o 'sim' envia a frase", async () => {
  const frase = "João, bom dia! Passando para lembrar do saldo da OS-00045.\nQualquer coisa me chama.";
  const { db, ctx } = ambiente();
  const p = await pedir(ctx, db, { collection_id: COL, custom_message: `  ${frase}\n` });
  const s = semNbsp(p.summary);
  assertStringIncludes(s, "- Valor: *R$ 1.650,00* (o saldo da conta a receber hoje)");
  assertStringIncludes(s, "- A cobrança guardava R$ 2.000,00; a conta hoje é R$ 1.650,00.");
  assertEquals(textoDoCartao(p.summary), frase);
  assertEquals(s.includes("lembrete amigável"), false, "o texto padrão não entra junto");
  assertEquals(p.payload._retrato.texto, frase);
  await comEnvio({ messageId: "m1" }, async (enviados) => {
    // deno-lint-ignore no-explicit-any
    const r = await tool.execute(p.payload, ctx) as any;
    assertEquals(r.ok, true, JSON.stringify(r));
    assertEquals(enviados.map((e) => [e.phone, e.message]), [[NUMERO, frase]]);
  });
});

Deno.test("o destino continua na ordem de sempre: o contato da cobrança vem antes do cadastro, e o nome é o do contato", async () => {
  const { db, ctx } = ambiente({ collections: [cobranca({ contact_whatsapp: "47 98888-7777", contact_name: "Marta" })] });
  const p = await pedir(ctx, db);
  const s = semNbsp(p.summary);
  assertStringIncludes(s, "Lembrete de cobrança para *João Pereira*, pelo WhatsApp *+55 (47) 98888-7777*:");
  assertStringIncludes(s, "Olá Marta, lembrete amigável: você possui um valor de R$ 1.650,00 com vencimento em 22/07/2026.");
  await comEnvio({ messageId: "m1" }, async (enviados) => {
    await tool.execute(p.payload, ctx);
    assertEquals(enviados.map((e) => e.phone), ["5547988887777"]);
  });
  // o apelido do cadastro (display_name) continua vindo antes do nome do contato
  const apelido = ambiente({
    collections: [cobranca({ contact_name: "Marta" })],
    clients: cadastros().map((c) => c.id === JOAO ? { ...c, display_name: "Seu João" } : c),
  });
  assertStringIncludes(semNbsp((await pedir(apelido.ctx, apelido.db)).summary), "Olá Seu João, lembrete amigável");
});

// ── cobrança sem conta ───────────────────────────────────────────────────────────────────────

Deno.test("cobrança SEM conta a receber (avulsa): segue com o valor e o vencimento da própria cobrança, e o cartão diz isso", async () => {
  const { db, ctx } = ambiente({ collections: [cobranca({ receivable_id: null })], receivables: [] });
  const p = await pedir(ctx, db);
  const texto = "Olá João, lembrete amigável: você possui um valor de R$ 2.000,00 com vencimento em 10/07/2026. Qualquer dúvida estamos à disposição.";
  assertEquals(semNbsp(p.summary).split("\n"), [
    "Lembrete de cobrança para *João Pereira*, pelo WhatsApp *+55 (47) 99999-0001*:",
    "- Valor: *R$ 2.000,00* (o valor da cobrança; ela não tem conta a receber ligada)",
    "- Vencimento: 10/07/2026 (vencido há 138 dias)",
    "Mensagem que vai ao cliente:",
    texto,
  ]);
  assertEquals([p.payload._retrato.valor, p.payload._retrato.vencimento], [2000, "2026-07-10"]);
  await comEnvio({ messageId: "m1" }, async (enviados) => {
    // deno-lint-ignore no-explicit-any
    const r = await tool.execute(p.payload, ctx) as any;
    assertEquals(r.ok, true, JSON.stringify(r));
    assertEquals(enviados.map((e) => semNbsp(e.message)), [texto]);
  });
  // e o piso dela compara com o valor da cobrança, como sempre
  const abaixo = ambiente({ collections: [cobranca({ receivable_id: null, amount: 40 })], receivables: [], app_settings: [{ key: "collection_min_amount", value: "50" }] });
  assertStringIncludes(await recusado(abaixo.ctx, abaixo.db), "Cobrança de R$ 40.00 fica abaixo do piso de R$ 50");
});

// ── travas: uma linha "⚠️", sem pendência ────────────────────────────────────────────────────

Deno.test("conta paga, cancelada ou sem saldo: recusa clara, sem pendência e sem envio (a cobrança ainda dizia 'pendente')", async () => {
  const casos: Array<{ conta: Linha; trecho: string }> = [
    { conta: conta({ status: "paid", paid_amount: 2000, balance_amount: 0 }), trecho: "A conta desta cobrança já está paga: não mando lembrete." },
    { conta: conta({ status: "cancelled" }), trecho: "A conta desta cobrança já está cancelada: não mando lembrete." },
    { conta: conta({ status: "partially_paid", paid_amount: 2000, balance_amount: 0 }), trecho: "A conta desta cobrança não tem mais saldo em aberto: não mando lembrete." },
  ];
  for (const c of casos) {
    const { db, ctx } = ambiente({ receivables: [c.conta] });
    assertEquals(await recusado(ctx, db), c.trecho);
  }
  // a conta que sumiu: sem ela não há valor conferido, então também não manda
  const semConta = ambiente({ receivables: [] });
  assertStringIncludes(await recusado(semConta.ctx, semConta.db), "Não achei a conta a receber desta cobrança");
});

Deno.test("piso de materialidade: compara com o SALDO da conta, não com o valor que a cobrança guardava", async () => {
  // a cobrança guarda R$ 2.000 (acima do piso), mas a conta hoje deve R$ 1.650: abaixo do piso de R$ 1.800, não cobra
  const abaixo = ambiente({ app_settings: [{ key: "collection_min_amount", value: "1800" }] });
  assertStringIncludes(await recusado(abaixo.ctx, abaixo.db), "Cobrança de R$ 1650.00 fica abaixo do piso de R$ 1800 (Configurações): só listar, não cobrar por WhatsApp.");
  // o contrário: a cobrança guarda R$ 100 (abaixo do piso), mas a conta deve R$ 1.650 — passa
  const acima = ambiente({ collections: [cobranca({ amount: 100 })], app_settings: [{ key: "collection_min_amount", value: "1000" }] });
  assertStringIncludes(semNbsp((await pedir(acima.ctx, acima.db)).summary), "- A cobrança guardava R$ 100,00; a conta hoje é R$ 1.650,00.");
});

Deno.test("as travas de sempre viram '⚠️' e não pendência: paga, cancelada, entrada no Extrato, opt-out, genérico, telefone, não achada", async () => {
  const casos: Array<{ tabelas: Record<string, Linha[]>; input?: Record<string, unknown>; trecho: string }> = [
    { tabelas: { collections: [cobranca({ status: "paid" })] }, trecho: "Esta cobrança está paga: não mando lembrete." },
    { tabelas: { collections: [cobranca({ status: "cancelled" })] }, trecho: "Esta cobrança está cancelada: não mando lembrete." },
    {
      tabelas: { finance_review_queue: [{ suggested_client_id: JOAO, suggested_amount: 1650, suggested_date: "2026-11-24", title: "Receita: JOAO", status: "pending", kind: "create_receivable" }] },
      trecho: "Este cliente tem entrada esperando no Extrato (R$ 1650.00 de 2026-11-24): pode ser este pagamento.",
    },
    { tabelas: { clients: cadastros().map((c) => c.id === JOAO ? { ...c, opt_out_whatsapp: true } : c) }, trecho: "opt-out" },
    { tabelas: { collections: [cobranca({ client_id: FINAL })], receivables: [conta({ client_id: FINAL })] }, trecho: 'cadastro genérico "Cliente Final"' },
    { tabelas: { clients: cadastros().map((c) => c.id === JOAO ? { ...c, whatsapp: null } : c) }, trecho: "Sem telefone para enviar o lembrete." },
    { tabelas: { clients: cadastros().map((c) => c.id === JOAO ? { ...c, whatsapp: "9999-0001" } : c) }, trecho: 'O telefone do cadastro do cliente ("9999-0001") não é um número de WhatsApp válido' },
    { tabelas: { clients: [] }, trecho: "Não achei o cadastro do cliente desta cobrança" },
    { tabelas: { collections: [] }, trecho: "Cobrança não encontrada. Passe o id da cobrança (list_pending_collections)" },
    { tabelas: {}, input: { collection_id: "OS-00045" }, trecho: "Cobrança não encontrada." },
  ];
  for (const c of casos) {
    const { db, ctx } = ambiente(c.tabelas);
    const e = await recusado(ctx, db, c.input);
    assertStringIncludes(e, c.trecho, e);
  }
});

Deno.test("cadastro genérico COM contato próprio na cobrança não é barrado (o destino é o contato, não o telefone do genérico)", async () => {
  const { db, ctx } = ambiente({
    collections: [cobranca({ client_id: FINAL, contact_whatsapp: "5547988887777", contact_name: "Marta" })],
    receivables: [conta({ client_id: FINAL })],
  });
  assertStringIncludes(semNbsp((await pedir(ctx, db)).summary), "pelo WhatsApp *+55 (47) 98888-7777*:");
});

Deno.test("leitura que falha recusa (nunca vira 'sem piso', 'sem opt-out' ou 'sem entrada esperando')", async () => {
  for (const tabela of ["collections", "receivables", "app_settings", "finance_review_queue", "clients"]) {
    const { db, ctx } = ambiente({}, [tabela]);
    const resumo = await buildPendingSummary(ctx.admin, "send_collection_reminder", { collection_id: COL }, { userId: "dono-1" });
    assertStringIncludes(resumo, "⚠️ Não consegui conferir a cobrança agora", tabela);
    assertStringIncludes(resumo, "Nada foi enviado", tabela);
    assert(resumoQueRecusa("send_collection_reminder", resumo), tabela);
    // e pelo caminho inteiro: nada no sino
    const e = await recusado(ctx, db);
    assertStringIncludes(e, "Não consegui conferir a cobrança agora", tabela);
  }
});

// ── o "sim" confere o retrato ────────────────────────────────────────────────────────────────

Deno.test("mudou depois do pedido (valor, vencimento, telefone ou texto): o 'sim' não envia e diz o que mudou", async () => {
  // deno-lint-ignore no-explicit-any
  const casos: Array<{ mexe: (db: any) => void; trecho: string }> = [
    {
      mexe: (db) => Object.assign(db.tabelas.receivables[0], { paid_amount: 1350, balance_amount: 650 }),
      trecho: "Nada foi enviado: o valor mudou (era R$ 1.650,00, agora R$ 650,00) depois do pedido. Peça de novo que eu confiro e mostro a mensagem atualizada.",
    },
    {
      mexe: (db) => Object.assign(db.tabelas.receivables[0], { due_date: "2026-12-10" }),
      trecho: "Nada foi enviado: o vencimento mudou (era 22/07/2026, agora 10/12/2026) depois do pedido.",
    },
    {
      mexe: (db) => Object.assign(db.tabelas.clients[0], { whatsapp: "47988887777" }),
      trecho: "Nada foi enviado: o telefone de destino mudou depois do pedido.",
    },
    {
      mexe: (db) => Object.assign(db.tabelas.clients[0], { display_name: "Seu João" }),
      trecho: "Nada foi enviado: o texto da mensagem mudou depois do pedido.",
    },
  ];
  for (const c of casos) {
    const { db, ctx } = ambiente();
    const p = await pedir(ctx, db);
    c.mexe(db);
    await comEnvio({ messageId: "m1" }, async (enviados) => {
      // deno-lint-ignore no-explicit-any
      const r = await tool.execute(p.payload, ctx) as any;
      assertStringIncludes(semNbsp(r.error), c.trecho);
      assertEquals(r.nada_enviado, true);
      assertEquals(enviados, [], c.trecho);
      assertEquals(inseridos(db, "collection_contacts"), [], "nada registrado na cobrança");
    });
  }
});

Deno.test("a situação mudou depois do pedido (conta paga, cobrança cancelada, entrada no Extrato, opt-out): o 'sim' não envia", async () => {
  // deno-lint-ignore no-explicit-any
  const casos: Array<{ mexe: (db: any) => void; trecho: string }> = [
    { mexe: (db) => Object.assign(db.tabelas.receivables[0], { status: "paid", paid_amount: 2000, balance_amount: 0 }), trecho: "A conta desta cobrança já está paga" },
    { mexe: (db) => Object.assign(db.tabelas.collections[0], { status: "cancelled" }), trecho: "Esta cobrança está cancelada" },
    {
      mexe: (db) => db.tabelas.finance_review_queue.push({ suggested_client_id: JOAO, suggested_amount: 1650, suggested_date: "2026-11-25", title: "Receita: JOAO", status: "pending", kind: "create_receivable" }),
      trecho: "Este cliente tem entrada esperando no Extrato",
    },
    { mexe: (db) => Object.assign(db.tabelas.clients[0], { opt_out_whatsapp: true }), trecho: "opt-out" },
  ];
  for (const c of casos) {
    const { db, ctx } = ambiente();
    const p = await pedir(ctx, db);
    c.mexe(db);
    await comEnvio({ messageId: "m1" }, async (enviados) => {
      // deno-lint-ignore no-explicit-any
      const r = await tool.execute(p.payload, ctx) as any;
      assertStringIncludes(r.error, c.trecho);
      assertEquals(r.nada_enviado, true);
      assertEquals(enviados, [], c.trecho);
    });
  }
});

Deno.test("sem retrato (pendência antiga ou chamada direta) não envia; leitura que falha no 'sim' também não", async () => {
  const { db, ctx } = ambiente();
  await comEnvio({ messageId: "m1" }, async (enviados) => {
    // deno-lint-ignore no-explicit-any
    const r = await tool.execute({ collection_id: COL }, ctx) as any;
    assertEquals(r.error, SEM_RETRATO_DO_LEMBRETE);
    assertEquals(r.nada_enviado, true);
    assertEquals(enviados, []);
  });
  const p = await pedir(ctx, db);
  const fora = ambiente({}, ["receivables"]);
  await comEnvio({ messageId: "m1" }, async (enviados) => {
    // deno-lint-ignore no-explicit-any
    const r = await tool.execute(p.payload, fora.ctx) as any;
    assertStringIncludes(r.error, "Nada foi enviado: não consegui conferir a cobrança agora (Não consegui ler a conta a receber da cobrança: receivables fora do ar)");
    assertEquals(enviados, []);
  });
});

Deno.test("o 'sim' fora do horário (22h em Brasília): o portão bloqueia, nada sai e o bloqueio fica no registro", async () => {
  const { db, ctx } = ambiente();
  const p = await pedir(ctx, db);
  const antes = relogioDoLembrete.agora;
  relogioDoLembrete.agora = () => new Date("2026-11-26T01:00:00Z");
  try {
    await comEnvio({ messageId: "m1" }, async (enviados) => {
      // deno-lint-ignore no-explicit-any
      const r = await tool.execute(p.payload, ctx) as any;
      assertStringIncludes(r.error, "fora do horário");
      assertEquals(enviados, []);
      assertEquals(inseridos(db, "ai_comms_log").map((l: Linha) => [l.status, l.block_code]), [["blocked", "fora_de_horario"]]);
      assertEquals(inseridos(db, "collection_contacts"), []);
    });
  } finally {
    relogioDoLembrete.agora = antes;
  }
});

Deno.test("técnico não cobra: nem pelo 'sim' de uma pendência", async () => {
  const { ctx } = ambiente();
  // deno-lint-ignore no-explicit-any
  const r = await tool.execute({ collection_id: COL, _retrato: { cobranca: COL } }, { ...ctx, userRole: "technician" }) as any;
  assert(r.error, JSON.stringify(r));
  assertEquals(String(r.error).includes("conferir a cobrança"), false, "barrado pelo cargo, antes de qualquer leitura");
});

// ── registro ─────────────────────────────────────────────────────────────────────────────────

Deno.test("registro: risco alto, nunca autônoma, com retrato, título em português e a descrição que ensina", () => {
  assertEquals(tool.risk, "high");
  assert(NEVER_AUTONOMOUS.has("send_collection_reminder"));
  assert(typeof tool.retratoDaPendencia === "function");
  assertEquals(tituloDaAcao("send_collection_reminder"), "Enviar lembrete de cobrança");
  assert(allTools.some((t) => t.name === "send_collection_reminder"));
  assert(resumoQueRecusa("send_collection_reminder", "⚠️ Esta cobrança está paga: não mando lembrete."), "trava do resumo é recusa");
  assertEquals(resumoQueRecusa("send_collection_reminder", "Lembrete de cobrança para *João*\n- Valor"), null);
  for (const trecho of ["CONTA A RECEBER", "não pergunte antes", "mensagem exata", "cobrar_juntas", "custom_message"]) {
    assertStringIncludes(tool.description, trecho);
  }
  assertEquals((tool.input_schema as { required?: string[] }).required, ["collection_id"]);
});

// ── consertos da revisão de 25/11/2026 ───────────────────────────────────────────────────────

Deno.test("cadastro genérico com o telefone do cadastro COPIADO na cobrança (o que Gerar Cobranças faz): recusa; com outro número, passa", async () => {
  // a cobrança nasceu com o telefone do "Cliente Final" copiado como contato
  const copiado = ambiente({
    collections: [cobranca({ client_id: FINAL, contact_whatsapp: "47 99999-0002", phone: null, contact_name: "Cliente Final" })],
    receivables: [conta({ client_id: FINAL })],
  });
  assertStringIncludes(await recusado(copiado.ctx, copiado.db), 'cadastro genérico "Cliente Final"');
  // só o phone copiado (sem whatsapp na cobrança) também
  const soPhone = ambiente({
    collections: [cobranca({ client_id: FINAL, contact_whatsapp: null, phone: "5547999990002" })],
    receivables: [conta({ client_id: FINAL })],
  });
  assertStringIncludes(await recusado(soPhone.ctx, soPhone.db), 'cadastro genérico "Cliente Final"');
});

Deno.test("a saudação usa o primeiro nome do cliente, não o rótulo copiado na cobrança ('Nelson - S.I. 7.8')", async () => {
  const { db, ctx } = ambiente({
    collections: [cobranca({ contact_whatsapp: "(47) 99999-0001", contact_name: "Nelson - S.I. 7.8" })],
    clients: cadastros().map((c) => c.id === JOAO ? { ...c, name: "Nelson Ribeiro" } : c),
  });
  const s = semNbsp((await pedir(ctx, db)).summary);
  assertStringIncludes(s, "Olá Nelson, lembrete amigável");
  assertEquals(s.includes("S.I. 7.8"), false, s);
});

Deno.test("cartão: a frase do dono cita um valor que não é o saldo de hoje — linha de atenção (não recusa)", async () => {
  const { db, ctx } = ambiente();
  const p = await pedir(ctx, db, { collection_id: COL, custom_message: "João, lembrando do saldo de R$ 2.000,00 da OS-00045." });
  const s = semNbsp(p.summary);
  assertStringIncludes(s, "- Atenção: a frase cita R$ 2.000,00; o saldo da conta hoje é R$ 1.650,00. Confira antes de aprovar.");
  // citando o valor certo (com outro junto), nenhuma linha
  const certo = ambiente();
  const s2 = semNbsp((await pedir(certo.ctx, certo.db, { collection_id: COL, custom_message: "Da parcela de R$ 2.000,00, faltam R$ 1.650,00." })).summary);
  assertEquals(s2.includes("Atenção: a frase cita"), false, s2);
});

Deno.test("cartão: o cliente tem outras contas em aberto — o lembrete avisa que é só desta e aponta a cobrança do cliente", async () => {
  const outra = { id: "outra-conta", client_id: JOAO, amount: 430, paid_amount: 0, balance_amount: 430, status: "pending", due_date: "2026-11-16" };
  const paga = { id: "paga", client_id: JOAO, amount: 900, paid_amount: 900, balance_amount: 0, status: "paid", due_date: "2026-10-01" };
  const { db, ctx } = ambiente({ receivables: [conta(), outra, paga] });
  const s = semNbsp((await pedir(ctx, db)).summary);
  assertStringIncludes(s, '- Este lembrete é só desta conta: o cliente tem mais 1 conta em aberto (R$ 430,00). Para cobrar tudo numa mensagem só, peça a cobrança do cliente ("cobra o Fulano").');
});

Deno.test("cartão: outra cobrança do cliente já saiu hoje — avisa que ele vai receber outra mensagem no mesmo dia", async () => {
  const hoje = "2026-11-25T13:00:00Z";
  const outra = cobranca({ id: "33333333-3333-4333-8333-333333333009", receivable_id: null, last_auto_sent_at: hoje, status: "sent" });
  const { db, ctx } = ambiente({ collections: [cobranca(), outra] });
  assertStringIncludes(semNbsp((await pedir(ctx, db)).summary), "- Já houve cobrança para este cliente hoje: ele vai receber outra mensagem no mesmo dia.");
  // a própria cobrança mandada ontem não avisa
  const ontem = ambiente({ collections: [cobranca({ last_auto_sent_at: "2026-11-24T13:00:00Z" })] });
  assertEquals(semNbsp((await pedir(ontem.ctx, ontem.db)).summary).includes("Já houve cobrança"), false);
});

Deno.test("cartão: número que parece telefone FIXO ganha a linha de atenção", async () => {
  const { db, ctx } = ambiente({ clients: cadastros().map((c) => c.id === JOAO ? { ...c, whatsapp: "(47) 3333-4444" } : c) });
  const s = semNbsp((await pedir(ctx, db)).summary);
  assertStringIncludes(s, "pelo WhatsApp *+55 (47) 3333-4444*:");
  assertStringIncludes(s, "- Atenção: o número parece de telefone FIXO (sem WhatsApp, em geral): a mensagem pode não chegar. Confira o cadastro.");
});

Deno.test("modo de teste: a chave ganha ':teste', nada se registra na cobrança e a resposta diz que foi para o teste", async () => {
  const { db, ctx } = ambiente();
  const p = await pedir(ctx, db);
  await comEnvio({ messageId: "m1" }, async (enviados) => {
    // deno-lint-ignore no-explicit-any
    const r = await tool.execute(p.payload, { ...ctx, settings: { wa_test_mode: "true", wa_test_number: "5547900000000" } }) as any;
    assertEquals(enviados.length, 1);
    assertEquals(enviados[0].dedupe_key, `cobranca:${COL}:2026-11-25:teste`);
    assertEquals(inseridos(db, "collection_contacts"), [], "nada registrado na cobrança");
    assertEquals(db.tabelas.collections[0].status, "pending");
    assertStringIncludes(r.message, "foi para o número de TESTE, NÃO para o cliente");
  });
});

Deno.test("cargo: só administrador e financeiro — o vendedor nem vê a tool, e a pendência antiga dele não envia", async () => {
  assertEquals([...(tool.roles ?? [])].sort(), ["admin", "financial"]);
  const { ctx } = ambiente();
  for (const cargo of ["seller", "external_seller"]) {
    await comEnvio({ messageId: "m1" }, async (enviados) => {
      // deno-lint-ignore no-explicit-any
      const r = await tool.execute({ collection_id: COL, _retrato: { cobranca: COL } }, { ...ctx, userRole: cargo }) as any;
      assertEquals(r.error, "Só administrador ou financeiro envia lembrete de cobrança.");
      assertEquals(enviados, []);
    });
  }
});

Deno.test("retrato que falhou na hora da pendência: o cartão vira recusa em vez de pedir um 'sim' que nunca enviaria", async () => {
  const { ctx } = ambiente();
  const comRetrato = await buildPendingSummary(ctx.admin, "send_collection_reminder", { collection_id: COL }, { userId: "dono-1", retrato: { cobranca: COL } });
  assertStringIncludes(comRetrato, "Lembrete de cobrança para");
  const semRetrato = await buildPendingSummary(ctx.admin, "send_collection_reminder", { collection_id: COL }, { userId: "dono-1", retrato: null });
  assertEquals(semRetrato, "⚠️ Não consegui conferir a cobrança agora. Nada foi enviado; tente de novo.");
  assert(resumoQueRecusa("send_collection_reminder", semRetrato));
});

Deno.test("o texto do lembrete não volta com aviso de estilo por causa da data (dd/mm/aaaa não é jargão)", async () => {
  const { db, ctx } = ambiente();
  const p = await pedir(ctx, db);
  await comEnvio({ messageId: "m1" }, async () => {
    // deno-lint-ignore no-explicit-any
    const r = await tool.execute(p.payload, ctx) as any;
    assertEquals(r.ok, true, JSON.stringify(r));
    assertEquals(r.avisos_estilo, undefined, JSON.stringify(r.avisos_estilo));
  });
});

Deno.test("a lista de cargos da tool (literal, por causa do import circular) é a mesma de CARGOS_DO_LEMBRETE", async () => {
  const { CARGOS_DO_LEMBRETE } = await import("./lembrete-de-cobranca.ts");
  assertEquals([...(tool.roles ?? [])].sort(), [...CARGOS_DO_LEMBRETE].sort());
});

// ── conferência final de 25/11/2026 ──────────────────────────────────────────────────────────

Deno.test("modo de teste com o 'sim' repetido: diz que NÃO reenviou (não que foi agora) e não grava outro envio", async () => {
  const { db, ctx } = ambiente();
  const p = await pedir(ctx, db);
  await comEnvio({ deduplicated: true }, async () => {
    // deno-lint-ignore no-explicit-any
    const r = await tool.execute(p.payload, { ...ctx, settings: { wa_test_mode: "true", wa_test_number: "5547900000000" } }) as any;
    assertStringIncludes(r.message, "já tinha saído hoje para o número de TESTE");
    assertEquals(String(r.message).includes("foi para o número de TESTE"), false);
    assertEquals(inseridos(db, "ai_comms_log"), []);
    assertEquals(inseridos(db, "collection_contacts"), []);
  });
});

Deno.test("saudação de contato PRÓPRIO com rótulo ('Marta Souza - financeiro'): só o primeiro nome", async () => {
  const { db, ctx } = ambiente({ collections: [cobranca({ contact_whatsapp: "47 98888-7777", contact_name: "Marta Souza - financeiro" })] });
  const s = semNbsp((await pedir(ctx, db)).summary);
  assertStringIncludes(s, "Olá Marta, lembrete amigável");
  assertEquals(textoDoCartao(s).includes("Souza") || textoDoCartao(s).includes("financeiro"), false, s);
});

Deno.test("cobrança sem cliente (client_id nulo) com contato próprio: saudação pelo primeiro nome do contato", async () => {
  const { db, ctx } = ambiente({ collections: [cobranca({ client_id: null, contact_whatsapp: "47 98888-7777", contact_name: "Marta Souza" })] });
  const s = semNbsp((await pedir(ctx, db)).summary);
  assertStringIncludes(s, "Olá Marta, lembrete amigável");
});

Deno.test("o lembrete DESTA cobrança já saiu hoje por aqui (chave do dia concluída): recusa, não promete outra mensagem", async () => {
  const chave = `cobranca:${COL}:2026-11-25`;
  const { db, ctx } = ambiente({
    collections: [cobranca({ last_auto_sent_at: "2026-11-25T13:00:00Z", status: "sent" })],
    whatsapp_send_idempotencia: [{ chave, concluido_em: "2026-11-25T13:00:01Z" }],
  });
  assertStringIncludes(await recusado(ctx, db), "O lembrete desta cobrança já saiu hoje: o mesmo lembrete não sai duas vezes no dia.");
  // a reserva de ONTEM não barra
  const ontem = ambiente({ whatsapp_send_idempotencia: [{ chave: `cobranca:${COL}:2026-11-24`, concluido_em: "2026-11-24T13:00:01Z" }] });
  await pedir(ontem.ctx, ontem.db);
});

Deno.test("'outras contas' não conta a conta de OS cancelada ou agrupada (o 'cobra o Fulano' a deixaria de fora)", async () => {
  const OS_CANC = "55555555-5555-4555-8555-555555555001";
  const OS_BOA = "55555555-5555-4555-8555-555555555002";
  const { db, ctx } = ambiente({
    receivables: [
      conta(),
      { id: "da-cancelada", client_id: JOAO, service_order_id: OS_CANC, amount: 800, paid_amount: 0, balance_amount: 800, status: "pending", due_date: "2026-11-01" },
      { id: "da-boa", client_id: JOAO, service_order_id: OS_BOA, amount: 430, paid_amount: 0, balance_amount: 430, status: "pending", due_date: "2026-11-16" },
    ],
    service_orders: [{ id: OS_CANC, status: "cancelled", merged_into_id: null }, { id: OS_BOA, status: "invoiced", merged_into_id: null }],
  });
  const s = semNbsp((await pedir(ctx, db)).summary);
  assertStringIncludes(s, "o cliente tem mais 1 conta em aberto (R$ 430,00)");
});

Deno.test("a frase do dono: data que não é o vencimento, valor em 'R$1650.00' e cobrança sem conta", async () => {
  const data = ambiente();
  const s = semNbsp((await pedir(data.ctx, data.db, { collection_id: COL, custom_message: "João, o pagamento venceu em 10/07/2026." })).summary);
  assertStringIncludes(s, "- Atenção: a frase cita 10/07/2026; a conta vence em 22/07/2026. Confira antes de aprovar.");
  const ponto = ambiente();
  const s2 = semNbsp((await pedir(ponto.ctx, ponto.db, { collection_id: COL, custom_message: "João, faltam R$1650.00 do saldo." })).summary);
  assertEquals(s2.includes("Atenção: a frase cita"), false, s2);
  const semConta = ambiente({ collections: [cobranca({ receivable_id: null })], receivables: [] });
  const s3 = semNbsp((await pedir(semConta.ctx, semConta.db, { collection_id: COL, custom_message: "João, são R$ 900,00." })).summary);
  assertStringIncludes(s3, "- Atenção: a frase cita R$ 900,00; o valor da cobrança é R$ 2.000,00. Confira antes de aprovar.");
});
