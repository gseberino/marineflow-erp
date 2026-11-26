// Cobrar juntas pelo assistente (28/10/2026, Fase 0 do Fechar juntas). O pedido do dono que guia os testes:
//   "Cobra junto o que a MP MOTOR HOMES deve das OS-00045 e OS-00046."
// Em produção (28/10/2026): OS-00045 (R$ 1.650) + OS-00046 (R$ 20) = R$ 1.670 em aberto, vencido desde 22/07. A
// confirmação tem de mostrar cada OS com o saldo, o total e a mensagem EXATA; o cadastro genérico ("Cliente Final"),
// a OS que não começou, o Pix esperando no Extrato, o opt-out e o piso NÃO viram pendência — volta o motivo.
// Rodar com:
//   deno test --allow-all supabase/functions/_shared/ai/tools/cobrar-juntas_test.ts
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  CARGOS_DE_COBRAR_JUNTAS,
  cobrarJuntasTools,
  mensagemDaCobrancaConjunta,
  montarCobrancaConjunta,
  relogioDoCobrarJuntas,
  validarPedidoDeCobrarJuntas,
} from "./cobrar-juntas.ts";
import { problemasDoPedidoDeOS } from "./agrupar-os.ts";
import { allTools, toolsByName } from "./index.ts";
import { buildPendingSummary, executarChamadaDeTool, ressalvaDoResultado, resumoQueRecusa, tituloDaAcao } from "../agent.ts";
import { NEVER_AUTONOMOUS } from "../autonomy-policy.ts";
import { PERFIL_ADMIN, PERFIL_OPERACAO, rodaDiretoPelaRede, SO_PELA_REDE } from "../perfil-operacao.ts";
import { ferramentasDoJob } from "../max/ferramentas-do-job.ts";
import { NOME_DA_FERRAMENTA_EXTRA } from "../ferramenta-extra.ts";
import { FORA_DO_WHATSAPP } from "../channel-scope.ts";
import { PARIDADE_COBRANCA_DO_CLIENTE as PC, PARIDADE_COBRAR_JUNTAS as P } from "../../receivables/cobrar-juntas_paridade.ts";

/** Intl põe espaço sem quebra entre "R$" e o valor. */
const semNbsp = (x: unknown) => String(x ?? "").replace(/ /g, " ");
const UUID_NO_TEXTO = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i;

// 28/10/2026 às 14h em Brasília: dentro do horário do portão, e 22/07 já venceu.
relogioDoCobrarJuntas.agora = () => new Date("2026-10-28T17:00:00Z");

const MP = "8b2c3d4e-1111-4222-8333-444455556666";
const FINAL = "8b2c3d4e-2222-4222-8333-444455556666";
const OUTRO = "8b2c3d4e-3333-4222-8333-444455556666";
const ID_45 = "22222222-2222-4222-8222-222222222045";
const ID_46 = "22222222-2222-4222-8222-222222222046";
const ID_50 = "22222222-2222-4222-8222-222222222050";

// deno-lint-ignore no-explicit-any
type Linha = Record<string, any>;

function ordem(id: string, numero: string, extra: Linha = {}): Linha {
  return {
    id, service_order_number: numero, status: "completed", client_id: MP, merged_into_id: null,
    converted_to_os_at: "2026-06-01T12:00:00+00:00", created_at: "2026-06-01T12:00:00+00:00", ...extra,
  };
}

function osDaMP(): Linha[] {
  return [ordem(ID_45, "OS-00045"), ordem(ID_46, "OS-00046")];
}

function contasDaMP(): Linha[] {
  return [
    { id: "r45s", service_order_id: ID_45, client_id: MP, description: "Sinal OS-00045", amount: 500, paid_amount: 500, balance_amount: 0, status: "paid", due_date: "2026-06-05", is_deposit: true },
    { id: "r45", service_order_id: ID_45, client_id: MP, description: "Saldo OS-00045", amount: 1650, paid_amount: 0, balance_amount: 1650, status: "pending", due_date: "2026-07-22", is_deposit: false },
    { id: "r45c", service_order_id: ID_45, client_id: MP, description: "Antiga", amount: 300, paid_amount: 0, balance_amount: 300, status: "cancelled", due_date: "2026-07-01", is_deposit: false },
    { id: "r46", service_order_id: ID_46, client_id: MP, description: "Saldo OS-00046", amount: 20, paid_amount: 0, balance_amount: 20, status: "pending", due_date: "2026-07-22", is_deposit: false },
  ];
}

function cadastros(): Linha[] {
  return [
    { id: MP, name: "MP MOTOR HOMES", display_name: null, whatsapp: "(47) 99915-9654", phone: null, opt_out_whatsapp: false, generico: false },
    { id: FINAL, name: "Cliente Final", display_name: null, whatsapp: null, phone: null, opt_out_whatsapp: false, generico: true },
    { id: OUTRO, name: "Lenine", display_name: null, whatsapp: "47999990000", phone: null, opt_out_whatsapp: false, generico: false },
  ];
}

function bancoFalso(tabelas: Record<string, Linha[]>, falhas: string[] = []) {
  const chamadas = { insert: [] as [string, Linha][], update: [] as [string, Linha, Linha][], rpc: [] as [string, Linha][] };
  // deno-lint-ignore no-explicit-any
  const db: any = {
    chamadas,
    tabelas,
    // cobrar_juntas_registrar_envio (migration 20270212100000) em memória: cria a cobrança da conta sem nenhuma aberta
    // (nem da OS sem conta) e registra o envio em todas as abertas. A regra de verdade é provada no SQL
    // (supabase/tests/fechar_juntas_cobranca_junto.sql); aqui só o que a tool manda e o que ela diz.
    rpc: (fn: string, args: Linha) => {
      chamadas.rpc.push([fn, args]);
      if (fn !== "cobrar_juntas_registrar_envio") return Promise.resolve({ data: null, error: null });
      if (falhas.includes("rpc")) return Promise.resolve({ data: null, error: { message: "mês fechado" } });
      const aberta = (k: Linha) => k.status !== "paid" && k.status !== "cancelled";
      const cols = (tabelas.collections ??= []);
      let criadas = 0;
      for (const id of args.p_contas as string[]) {
        const conta = (tabelas.receivables ?? []).find((r) => r.id === id);
        if (cols.some((k) => aberta(k) && k.receivable_id === id)) continue;
        if (conta?.service_order_id && cols.some((k) => aberta(k) && !k.receivable_id && k.service_order_id === conta.service_order_id)) continue;
        cols.push({ id: `nova-${id}`, status: "pending", receivable_id: id, service_order_id: conta?.service_order_id, last_auto_sent_at: null });
        criadas++;
      }
      // p_os nulo = o cliente inteiro: as cobranças "da OS sem conta" que recebem o registro são as das OS das contas
      const osDoEnvio = (args.p_os as string[] | null) ?? (args.p_contas as string[])
        .map((id) => (tabelas.receivables ?? []).find((r) => r.id === id)?.service_order_id).filter(Boolean);
      const alvo = cols.filter((k) => aberta(k) && ((args.p_contas as string[]).includes(k.receivable_id) ||
        (!k.receivable_id && osDoEnvio.includes(k.service_order_id))));
      for (const k of alvo) {
        chamadas.insert.push(["collection_contacts", { collection_id: k.id, contact_type: "whatsapp_sent", notes: args.p_nota }]);
        chamadas.update.push(["collections", { status: "sent" }, { id: k.id }]);
        Object.assign(k, { status: "sent", last_auto_sent_at: "2026-10-28T17:00:00Z" });
      }
      return Promise.resolve({ data: { criadas, registradas: alvo.length }, error: null });
    },
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

interface Extra {
  tabelas?: Record<string, Linha[]>;
  falhas?: string[];
}

function ambiente(linhas: Linha[] = osDaMP(), extra: Extra = {}) {
  const tabelas: Record<string, Linha[]> = {
    service_orders: linhas,
    receivables: contasDaMP(),
    clients: cadastros(),
    collections: [
      { id: "col45", status: "pending", receivable_id: "r45", service_order_id: ID_45, last_auto_sent_at: null },
      { id: "col46", status: "pending", receivable_id: null, service_order_id: ID_46, last_auto_sent_at: null },
      { id: "colPaga", status: "paid", receivable_id: "r45s", service_order_id: ID_45, last_auto_sent_at: null },
    ],
    app_settings: [
      { key: "pix_key", value: "12.345.678/0001-90" },
      { key: "company_name", value: "HBR Marine" },
    ],
    finance_review_queue: [],
    app_users: [{ id: "dono-1", full_name: "Gustavo" }],
    ...(extra.tabelas ?? {}),
  };
  const db = bancoFalso(tabelas, extra.falhas);
  const ctx = { sb: db, admin: db, userId: "dono-1", userRole: "admin" as const, jwt: "", appOrigin: "", settings: {} };
  return { db, ctx };
}

const tool = cobrarJuntasTools.find((t) => t.name === "cobrar_juntas")!;
// deno-lint-ignore no-explicit-any
const amb = (ctx: any) => ({ toolsByName, alcancaveisPelaRede: {}, toolCtx: ctx, sessionId: "s1", channel: "whatsapp" as const });
// deno-lint-ignore no-explicit-any
const pendencias = (db: any) => db.chamadas.insert.filter(([t]: [string]) => t === "ai_operator_pending_actions").map(([, v]: [string, Linha]) => v);

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

// deno-lint-ignore no-explicit-any
async function pedir(ctx: any, db: any, input: Record<string, unknown>): Promise<Linha> {
  const r = await executarChamadaDeTool({ name: "cobrar_juntas", input }, amb(ctx));
  // deno-lint-ignore no-explicit-any
  assertEquals((r.toolResult as any).pending, true, JSON.stringify(r.toolResult));
  return pendencias(db).at(-1);
}

// deno-lint-ignore no-explicit-any
async function recusado(ctx: any, db: any, input: Record<string, unknown>): Promise<string> {
  return await comEnvio({ messageId: "m1" }, async (enviados) => {
    const r = await executarChamadaDeTool({ name: "cobrar_juntas", input }, amb(ctx));
    // deno-lint-ignore no-explicit-any
    const res = r.toolResult as any;
    assertEquals(res.pending, undefined, JSON.stringify(res));
    assertEquals(pendencias(db), [], "nada vai para o sino nem pede 'sim'");
    assertEquals(enviados, [], "nada foi enviado");
    return semNbsp(res.error);
  });
}

// ── pré-validação ────────────────────────────────────────────────────────────────────────────

Deno.test("preValidar (sem banco): 2 a 10 OS ou o cliente, só número/id, sem repetida, só admin e financeiro", () => {
  const admin = { userRole: "admin" } as const;
  // uma OS só: o caminho é o cliente inteiro (ou o lembrete da cobrança dela)
  assertStringIncludes(validarPedidoDeCobrarJuntas({ os: ["OS-00045"] }, admin)!.error, "passe só o cliente (cliente_id, de search_clients), sem as OS");
  assertStringIncludes(validarPedidoDeCobrarJuntas({ os: ["OS-00045"] }, admin)!.error, "send_collection_reminder");
  assertStringIncludes(validarPedidoDeCobrarJuntas({ os: Array.from({ length: 11 }, (_, i) => `OS-${i + 1}`) }, admin)!.error, "no máximo 10");
  assertStringIncludes(validarPedidoDeCobrarJuntas({ os: ["OS-00045", "45"] }, admin)!.error, "duas vezes");
  assertStringIncludes(validarPedidoDeCobrarJuntas({ os: ["as da MP", "OS-00046"] }, admin)!.error, "não é número de OS");
  assertStringIncludes(validarPedidoDeCobrarJuntas({}, admin)!.error, "Diga as OS");
  assertStringIncludes(validarPedidoDeCobrarJuntas({ cliente_id: "MP" }, admin)!.error, "search_clients");
  for (const cargo of ["seller", "external_seller", "technician"] as const) {
    assertStringIncludes(validarPedidoDeCobrarJuntas({ os: ["OS-00045", "OS-00046"] }, { userRole: cargo })!.error, "administrador ou financeiro");
  }
  assertEquals(validarPedidoDeCobrarJuntas({ os: "OS-00045, 46" }, { userRole: "financial" }), null);
  assertEquals(validarPedidoDeCobrarJuntas({ cliente_id: MP }, admin), null);
});

// ── a mensagem (pura) ────────────────────────────────────────────────────────────────────────

Deno.test("mensagem: saldo e número da OS em cada linha, Pago = soma do pago parcial, Total − Pago = Em aberto, vencido pela data", () => {
  const msg = semNbsp(mensagemDaCobrancaConjunta({
    cliente: { name: "MP MOTOR HOMES" },
    os: [
      { id: ID_45, numero: "OS-00045", status: "completed", saldo: 600, vencido: true, contas: [
        { id: "a", service_order_id: ID_45, description: "Saldo OS-00045", amount: 1000, paid_amount: 400, balance_amount: 600, status: "partially_paid", due_date: "2026-07-22" },
      ] },
      { id: ID_46, numero: "OS-00046", status: "completed", saldo: 20, vencido: false, contas: [
        { id: "b", service_order_id: ID_46, description: "", amount: 20, paid_amount: 0, balance_amount: 20, status: "pending", due_date: "2026-11-05" },
      ] },
    ],
    pixKey: "chave-pix", hoje: "2026-10-28",
  }));
  // o mesmo texto do "Cobrar juntas" da tela (buildClientStatement com servicoIds)
  assertStringIncludes(msg, "📋 *Cobrança — HBR*\nCliente: MP\nOS: OS-00045, OS-00046\n\n");
  assertStringIncludes(msg, "🔴 Saldo OS-00045 · vence 22/07/2026 · vencido: *R$ 600,00* (de R$ 1.000,00)");
  assertStringIncludes(msg, "🟡 OS-00046 · Lançamento · vence 05/11/2026 · a vencer: *R$ 20,00*");
  assertStringIncludes(msg, "Total: R$ 1.020,00\nPago: R$ 400,00\n*Em aberto: R$ 620,00*");
  assertStringIncludes(msg, "💠 Para pagar por Pix, use a chave: *chave-pix*");
  assertEquals(msg.includes("22/07/2026 · a vencer"), false, "dívida de julho não é 'a vencer'");
});

Deno.test("paridade com a tela: o mesmo caso fixo dá a MESMA mensagem do Cobrar juntas da ficha (buildClientStatement)", async () => {
  // O caso mora em _shared/receivables/cobrar-juntas_paridade.ts e o client-statement.test.ts (vitest) compara o texto da tela
  // com o MESMO esperado: mudou o formato de um lado só, um dos dois acusa.
  const { db } = ambiente(P.os.map((o) => ordem(o.id, o.numero)), {
    tabelas: {
      receivables: P.contas.map((x) => ({ ...x, client_id: MP })),
      app_settings: [{ key: "pix_key", value: P.pixKey }],
    },
  });
  const c = await montarCobrancaConjunta(db, db, { os: P.os.map((o) => o.numero) });
  assert(!("error" in c), JSON.stringify(c));
  assertEquals(c.mensagem, P.esperado);
});

// ── o pedido do dono: OS-00045 + OS-00046 ────────────────────────────────────────────────────

Deno.test("cobrar juntas: a pendência mostra cada OS com o saldo, o total, o número inteiro e a mensagem exata — sem uuid", async () => {
  const { db, ctx } = ambiente();
  const p = await pedir(ctx, db, { os: ["OS-00046", "OS-00045"] });
  assertEquals(p.title, "Cobrar o cliente (WhatsApp)");
  assertEquals(p.action_name, "cobrar_juntas");
  const s = semNbsp(p.summary);
  assertEquals(UUID_NO_TEXTO.test(s), false, s);
  assertStringIncludes(s, "Cobrar juntas *2* OS de *MP MOTOR HOMES* numa mensagem só, pelo WhatsApp *+55 (47) 99915-9654*:");
  assertStringIncludes(s, "- OS-00046 · Concluída · em aberto *R$ 20,00* (vencido)");
  assertStringIncludes(s, "- OS-00045 · Concluída · em aberto *R$ 1.650,00* (vencido)");
  assertStringIncludes(s, "Total em aberto: *R$ 1.670,00*");
  assertStringIncludes(s, "Nada muda nas contas a receber: cada conta continua na sua OS. O envio fica registrado em 2 cobranças.");
  assertStringIncludes(s, "Mensagem que vai ao cliente:\n📋 *Cobrança — HBR*\nCliente: MP\nOS: OS-00045, OS-00046");
  assertStringIncludes(s, "🔴 Saldo OS-00045 · vence 22/07/2026 · vencido: *R$ 1.650,00*\n🔴 Saldo OS-00046 · vence 22/07/2026 · vencido: *R$ 20,00*");
  assertStringIncludes(s, "Total: R$ 1.670,00\nPago: R$ 0,00\n*Em aberto: R$ 1.670,00*");
  // o sinal pago e a conta cancelada não entram
  assertEquals(s.includes("Sinal OS-00045"), false);
  assertEquals(s.includes("Antiga"), false);
  assertStringIncludes(s, "Pedido por: *Gustavo* (Administrador)");
  // o retrato: cliente, telefone, contas com saldo e o total
  assertEquals(p.payload._retrato.cliente, MP);
  assertEquals(p.payload._retrato.telefone, "5547999159654");
  assertEquals(p.payload._retrato.contas, [{ id: "r45", saldo: 1650 }, { id: "r46", saldo: 20 }]);
  assertEquals(p.payload._retrato.total, 1670);
});

Deno.test("o 'sim': envia a mensagem da confirmação ao cadastro e registra o envio só nas cobranças das contas escolhidas", async () => {
  const { db, ctx } = ambiente();
  const p = await pedir(ctx, db, { os: ["OS-00045", "OS-00046"] });
  const mensagemAprovada = String(p.summary).split("Mensagem que vai ao cliente:\n")[1].split("\nPedido por")[0];
  await comEnvio({ messageId: "m1" }, async (enviados) => {
    // deno-lint-ignore no-explicit-any
    const r = await toolsByName["cobrar_juntas"].execute(p.payload, ctx) as any;
    assertEquals(r.ok, true, JSON.stringify(r));
    assertEquals(enviados.length, 1);
    assertEquals(enviados[0].phone, "5547999159654");
    assertEquals(enviados[0].message, mensagemAprovada.trim());
    assertEquals(enviados[0].kind, "text");
    assert(String(enviados[0].dedupe_key).startsWith(`cobrar-juntas:${MP}:2026-10-28:`), enviados[0].dedupe_key);
    assert(!String(enviados[0].dedupe_key).endsWith(":teste"), "fora do modo de teste a chave é a de sempre");
    // registro nas cobranças: a da conta r45 e a da OS-00046 sem conta; a paga não
    const contatos = db.chamadas.insert.filter(([t]: [string]) => t === "collection_contacts").map(([, v]: [string, Linha]) => v.collection_id);
    assertEquals(contatos.sort(), ["col45", "col46"]);
    const col45 = db.tabelas.collections.find((c: Linha) => c.id === "col45");
    assertEquals(col45.status, "sent");
    assert(col45.last_auto_sent_at, "last_auto_sent_at gravado");
    assertEquals(db.tabelas.collections.find((c: Linha) => c.id === "colPaga").status, "paid");
    const log = db.chamadas.insert.filter(([t]: [string]) => t === "ai_comms_log").map(([, v]: [string, Linha]) => v);
    assertEquals(log.map((l: Linha) => l.status), ["sent"]);
    const ressalva = semNbsp(ressalvaDoResultado(r));
    assertStringIncludes(ressalva, "Cobrança conjunta enviada para MP MOTOR HOMES (+55 (47) 99915-9654): OS-00045, OS-00046 — em aberto R$ 1.670,00.");
    assertStringIncludes(ressalva, "Envio registrado em 2 cobranças.");
    assertEquals(ressalva.includes("criada"), false, "as duas contas já tinham cobrança: nada criado");
    // a função do banco recebe o cliente, as contas da mensagem, as OS e quem pediu
    const [[fn, args]] = db.chamadas.rpc;
    assertEquals(fn, "cobrar_juntas_registrar_envio");
    assertEquals([args.p_cliente, [...args.p_contas].sort(), [...args.p_os].sort(), args.p_autor], [MP, ["r45", "r46"], [ID_45, ID_46].sort(), "dono-1"]);
    assertStringIncludes(semNbsp(args.p_nota), "Cobrança conjunta enviada pelo assistente (WhatsApp): OS-00045, OS-00046");
    // nada mais grava: nenhuma conta mexida
    assertEquals(db.chamadas.update.filter(([t]: [string]) => t !== "collections"), []);
  });
});

Deno.test("o 'sim' repetido no mesmo dia: o whatsapp-send reconhece a chave e nada é registrado de novo", async () => {
  const { db, ctx } = ambiente();
  const p = await pedir(ctx, db, { os: ["OS-00045", "OS-00046"] });
  await comEnvio({ deduplicated: true }, async () => {
    // deno-lint-ignore no-explicit-any
    const r = await toolsByName["cobrar_juntas"].execute(p.payload, ctx) as any;
    assertEquals(r.ja_feito, true);
    assertStringIncludes(r.aviso, "já tinha saído hoje");
    assertEquals(db.chamadas.insert.filter(([t]: [string]) => t === "collection_contacts"), []);
  });
});

Deno.test("o 'sim' no modo de teste: a chave ganha ':teste', nada se registra nas cobranças e o dono ouve que foi para o teste", async () => {
  const { db, ctx } = ambiente();
  const p = await pedir(ctx, db, { os: ["OS-00045", "OS-00046"] });
  // A chave que o envio de verdade usa hoje (mesmo pedido, sem o modo de teste, noutro banco).
  const real = await comEnvio({ messageId: "m0" }, async (enviados) => {
    const outro = ambiente();
    await toolsByName["cobrar_juntas"].execute(p.payload, outro.ctx);
    return String(enviados[0].dedupe_key);
  });
  const teste = { ...ctx, settings: { wa_test_mode: "true", wa_test_number: "5547900001111" } };
  await comEnvio({ messageId: "m1" }, async (enviados) => {
    // deno-lint-ignore no-explicit-any
    const r = await toolsByName["cobrar_juntas"].execute(p.payload, teste) as any;
    assertEquals(r.ok, true, JSON.stringify(r));
    assertEquals(enviados.length, 1);
    assertEquals(enviados[0].dedupe_key, `${real}:teste`, "só a marca muda: o envio de verdade no mesmo dia não vira deduplicated");
    assertEquals(db.chamadas.insert.filter(([t]: [string]) => t === "collection_contacts"), [], "sem contato nas cobranças");
    assertEquals(db.chamadas.update.filter(([t]: [string]) => t === "collections"), [], "sem last_auto_sent_at");
    assertEquals(db.tabelas.collections.find((c: Linha) => c.id === "col45").status, "pending");
    assertEquals(r.cobrancas_registradas, 0);
    assertStringIncludes(semNbsp(r.aviso), "foi para o número de TESTE, NÃO para MP MOTOR HOMES");
    assertStringIncludes(r.aviso, "Nada foi registrado nas cobranças");
  });
  // Ligado SEM número de teste a edge não desvia (a mensagem vai ao cliente): chave e registro de sempre.
  const semNumero = ambiente();
  const p2 = await pedir(semNumero.ctx, semNumero.db, { os: ["OS-00045", "OS-00046"] });
  await comEnvio({ messageId: "m2" }, async (enviados) => {
    // deno-lint-ignore no-explicit-any
    const r = await toolsByName["cobrar_juntas"].execute(p2.payload, { ...semNumero.ctx, settings: { wa_test_mode: "true" } }) as any;
    assertEquals(enviados[0].dedupe_key, real);
    assertEquals(r.cobrancas_registradas, 2);
  });
});

// ── o cliente inteiro (25/11/2026): "cobra o Fulano" ─────────────────────────────────────────

const APOLO = "8b2c3d4e-4444-4222-8333-444455556666";
const cadastroDaApolo = (): Linha => ({ id: APOLO, name: "APOLO INDUSTRIA E COMERCIO", display_name: null, whatsapp: "(47) 98888-1234", phone: null, opt_out_whatsapp: false, generico: false });
/** As duas parcelas de nota da Apolo (sem OS), como em produção em 24/11/2026 — aqui com o relógio do arquivo (28/10). */
function parcelasDaApolo(): Linha[] {
  return [
    { id: "p2", service_order_id: null, client_id: APOLO, description: "NF-e 2/25 (parcela 2/3)", amount: 5237.99, paid_amount: 0, balance_amount: 5237.99, status: "pending", due_date: "2026-10-16", is_deposit: false },
    { id: "p3", service_order_id: null, client_id: APOLO, description: "NF-e 2/25 (parcela 3/3)", amount: 5238.02, paid_amount: 0, balance_amount: 5238.02, status: "pending", due_date: "2026-11-13", is_deposit: false },
    { id: "p1", service_order_id: null, client_id: APOLO, description: "NF-e 2/25 (parcela 1/3)", amount: 5237.99, paid_amount: 5237.99, balance_amount: 0, status: "paid", due_date: "2026-09-16", is_deposit: false },
  ];
}
const ambienteDaApolo = (extra: Extra = {}) => ambiente([], {
  ...extra,
  tabelas: { receivables: parcelasDaApolo(), clients: [...cadastros(), cadastroDaApolo()], collections: [], ...(extra.tabelas ?? {}) },
});

Deno.test("pelo cliente, só conta SEM OS (as parcelas de nota): o cartão lista cada conta, a mensagem sai sem a linha 'OS:' e o 'sim' registra com p_os nulo", async () => {
  const { db, ctx } = ambienteDaApolo();
  const p = await pedir(ctx, db, { cliente_id: APOLO });
  const s = semNbsp(p.summary);
  assertEquals(UUID_NO_TEXTO.test(s), false, s);
  assertStringIncludes(s, "Cobrar *APOLO INDUSTRIA E COMERCIO* por tudo que ele tem em aberto (2 contas), numa mensagem só, pelo WhatsApp *+55 (47) 98888-1234*:");
  assertStringIncludes(s, "- Sem OS · NF-e 2/25 (parcela 2/3) · vence 16/10/2026 · em aberto *R$ 5.237,99* (vencido)");
  assertStringIncludes(s, "- Sem OS · NF-e 2/25 (parcela 3/3) · vence 13/11/2026 · em aberto *R$ 5.238,02*\n");
  // parte vencida, parte a vencer: o total diz quanto já venceu
  assertStringIncludes(s, "Total em aberto: *R$ 10.476,01* (vencido: R$ 5.237,99)");
  assertStringIncludes(s, "- Nada muda nas contas a receber. 2 contas não têm cobrança registrada: elas são criadas junto com o envio");
  assertStringIncludes(s, "Mensagem que vai ao cliente:\n📋 *Cobrança — HBR*\nCliente: APOLO\n\n🔴 NF-e 2/25 (parcela 2/3) · vence 16/10/2026 · vencido: *R$ 5.237,99*\n🟡 NF-e 2/25 (parcela 3/3) · vence 13/11/2026 · a vencer: *R$ 5.238,02*");
  assertStringIncludes(s, "Total: R$ 10.476,01\nPago: R$ 0,00\n*Em aberto: R$ 10.476,01*");
  assertEquals(s.includes("OS:"), false, "sem OS, a linha 'OS:' não aparece");
  assertEquals(s.includes("parcela 1/3"), false, "a parcela paga não entra: é cobrança, não extrato");
  assertEquals(p.payload._retrato.contas, [{ id: "p2", saldo: 5237.99 }, { id: "p3", saldo: 5238.02 }]);

  const mensagemAprovada = String(p.summary).split("Mensagem que vai ao cliente:\n")[1].split("\nPedido por")[0];
  await comEnvio({ messageId: "m1" }, async (enviados) => {
    // deno-lint-ignore no-explicit-any
    const r = await toolsByName["cobrar_juntas"].execute(p.payload, ctx) as any;
    assertEquals(r.ok, true, JSON.stringify(r));
    assertEquals(enviados[0].phone, "5547988881234");
    assertEquals(enviados[0].message, mensagemAprovada.trim());
    const [[fn, args]] = db.chamadas.rpc;
    assertEquals(fn, "cobrar_juntas_registrar_envio");
    assertEquals([args.p_cliente, [...args.p_contas].sort(), args.p_os, args.p_autor], [APOLO, ["p2", "p3"], null, "dono-1"]);
    assertStringIncludes(semNbsp(args.p_nota), "Cobrança do cliente enviada pelo assistente (WhatsApp): tudo em aberto (2 contas: 2 sem OS) — em aberto R$ 10.476,01");
    assertEquals([r.cobrancas_criadas, r.cobrancas_registradas], [2, 2], JSON.stringify(r));
    assertStringIncludes(semNbsp(ressalvaDoResultado(r)), "Cobrança enviada para APOLO INDUSTRIA E COMERCIO (+55 (47) 98888-1234): tudo em aberto (2 contas: 2 sem OS) — em aberto R$ 10.476,01. 2 cobranças criadas (em Cobranças).");
  });
});

Deno.test("pelo cliente, UMA OS só e sem cobrança criada (o caso do Sergio): pelas OS recusa; pelo cliente cobra", async () => {
  const so45 = { tabelas: { receivables: contasDaMP().filter((c) => c.service_order_id === ID_45), collections: [] } };
  {
    const { db, ctx } = ambiente([ordem(ID_45, "OS-00045")], so45);
    const e = await recusado(ctx, db, { os: ["OS-00045"] });
    assertStringIncludes(e, "passe só o cliente (cliente_id, de search_clients), sem as OS");
  }
  const { db, ctx } = ambiente([ordem(ID_45, "OS-00045")], so45);
  const p = await pedir(ctx, db, { cliente_id: MP });
  const s = semNbsp(p.summary);
  assertStringIncludes(s, "Cobrar *MP MOTOR HOMES* por tudo que ele tem em aberto (1 conta), numa mensagem só");
  assertStringIncludes(s, "- OS-00045 · Concluída · em aberto *R$ 1.650,00* (vencido)");
  assertStringIncludes(s, "Total em aberto: *R$ 1.650,00*\n");
  assertStringIncludes(s, "1 conta não tem cobrança registrada: ela é criada junto com o envio");
  assertStringIncludes(s, "📋 *Cobrança — HBR*\nCliente: MP\nOS: OS-00045\n\n🔴 Saldo OS-00045 · vence 22/07/2026 · vencido: *R$ 1.650,00*");
  assertEquals(s.includes("Sinal OS-00045"), false, "o sinal pago não entra");
  await comEnvio({ messageId: "m1" }, async () => {
    // deno-lint-ignore no-explicit-any
    const r = await toolsByName["cobrar_juntas"].execute(p.payload, ctx) as any;
    assertEquals([r.ok, r.cobrancas_criadas, r.cobrancas_registradas], [true, 1, 1], JSON.stringify(r));
    assertEquals(db.chamadas.rpc[0][1].p_os, null);
    assertStringIncludes(semNbsp(r.message), "tudo em aberto (1 conta: OS-00045) — em aberto R$ 1.650,00");
  });
});

Deno.test("pelo cliente: entra TUDO em aberto — a conta da OS que não começou (com aviso) e a conta sem OS; a OS sem saldo fica de fora", async () => {
  const linhas = [...osDaMP(), ordem(ID_50, "OS-00050", { status: "scheduled" }), ordem("22222222-2222-4222-8222-222222222051", "OS-00051")];
  const { db, ctx } = ambiente(linhas, {
    tabelas: {
      receivables: [
        ...contasDaMP(),
        { id: "r50", service_order_id: ID_50, client_id: MP, description: "Sinal", amount: 900, paid_amount: 0, balance_amount: 900, status: "pending", due_date: "2026-10-30" },
        { id: "avulsa", service_order_id: null, client_id: MP, description: "Venda de balcão", amount: 80, paid_amount: 30, balance_amount: 50, status: "partially_paid", due_date: "2026-10-01" },
        // conta de OUTRO titular numa OS da MP: não é dívida da MP (cobra-se o titular da conta)
        { id: "deOutro", service_order_id: ID_45, client_id: OUTRO, description: "Parte do Lenine", amount: 70, paid_amount: 0, balance_amount: 70, status: "pending", due_date: "2026-07-22" },
      ],
    },
  });
  const p = await pedir(ctx, db, { cliente_id: MP });
  const s = semNbsp(p.summary);
  assertStringIncludes(s, "Cobrar *MP MOTOR HOMES* por tudo que ele tem em aberto (4 contas)");
  // as contas sem OS primeiro, depois as OS na ordem do número
  assertStringIncludes(s, "- Sem OS · Venda de balcão · vence 01/10/2026 · em aberto *R$ 50,00* (vencido)\n- OS-00045 · Concluída · em aberto *R$ 1.650,00* (vencido)\n- OS-00046 · Concluída · em aberto *R$ 20,00* (vencido)\n- OS-00050 · Agendada · em aberto *R$ 900,00*\n");
  assertStringIncludes(s, "Total em aberto: *R$ 2.620,00* (vencido: R$ 1.720,00)");
  assertStringIncludes(s, "- OS-00050 (Agendada) ainda não foi executada: a conta entra mesmo assim, porque está em aberto.");
  assertStringIncludes(s, "🔴 Venda de balcão · vence 01/10/2026 · vencido: *R$ 50,00* (de R$ 80,00)");
  assertStringIncludes(s, "🟡 OS-00050 · Sinal · vence 30/10/2026 · a vencer: *R$ 900,00*");
  assertStringIncludes(s, "Cliente: MP\nOS: OS-00045, OS-00046, OS-00050\n");
  assertStringIncludes(s, "Total: R$ 2.650,00\nPago: R$ 30,00\n*Em aberto: R$ 2.620,00*");
  assertEquals(s.includes("OS-00051"), false, "a OS sem saldo não entra");
  assertEquals(s.includes("Lenine"), false, "a conta de outro titular não entra");
  // duas OS que não começaram (o caso do César, 25/11/2026: duas "Aguardando cliente" vencidas): o aviso concorda
  db.tabelas.service_orders.find((o: Linha) => o.id === ID_46).status = "awaiting_client";
  const s2 = semNbsp(await buildPendingSummary(ctx.admin, "cobrar_juntas", { cliente_id: MP }, { userId: "dono-1" }));
  assertStringIncludes(s2, "- OS-00046 (Aguardando cliente), OS-00050 (Agendada) ainda não foram executadas: as contas entram mesmo assim, porque estão em aberto.");
  assertEquals(p.payload._retrato.contas.map((x: Linha) => x.id), ["avulsa", "r45", "r46", "r50"]);
});

Deno.test("pelo cliente: conta de OS cancelada ou agrupada em outra fica de fora, com aviso; sobrando só ela, recusa", async () => {
  const linhas = [ordem(ID_45, "OS-00045"), ordem(ID_46, "OS-00046", { status: "cancelled" }), ordem(ID_50, "OS-00050", { status: "completed", merged_into_id: ID_45 })];
  const contas = [
    ...contasDaMP(),
    { id: "r50", service_order_id: ID_50, client_id: MP, description: "Saldo OS-00050", amount: 300, paid_amount: 0, balance_amount: 300, status: "pending", due_date: "2026-08-01" },
  ];
  {
    const { db, ctx } = ambiente(linhas, { tabelas: { receivables: contas } });
    const p = await pedir(ctx, db, { cliente_id: MP });
    const s = semNbsp(p.summary);
    assertStringIncludes(s, "por tudo que ele tem em aberto (1 conta)");
    assertStringIncludes(s, "- Ficou de fora: Saldo OS-00046, R$ 20,00 (OS-00046, cancelada); Saldo OS-00050, R$ 300,00 (OS-00050, agrupada em outra OS) — a OS não vale mais e a conta segue aberta. Confira em Contas a Receber.");
    assertEquals(p.payload._retrato.contas, [{ id: "r45", saldo: 1650 }]);
    assertEquals(String(p.summary).split("Mensagem que vai ao cliente:\n")[1].includes("OS-00046"), false, "a mensagem ao cliente não cita a conta que ficou de fora");
  }
  {
    const { db, ctx } = ambiente(linhas, { tabelas: { receivables: contas.filter((c) => c.service_order_id !== ID_45) } });
    const e = await recusado(ctx, db, { cliente_id: MP });
    assertStringIncludes(e, "MP MOTOR HOMES não tem o que cobrar. Ficou de fora: Saldo OS-00046, R$ 20,00 (OS-00046, cancelada)");
  }
});

Deno.test("pelo cliente: nada vencido avisa que é cobrança antes do vencimento; conta de OS que não se acha recusa", async () => {
  {
    const { db, ctx } = ambienteDaApolo({ tabelas: { receivables: parcelasDaApolo().filter((c) => c.id === "p3") } });
    const p = await pedir(ctx, db, { cliente_id: APOLO });
    const s = semNbsp(p.summary);
    assertStringIncludes(s, "- Nenhuma conta está vencida (a primeira vence em 13/11/2026): é cobrança antes do vencimento.");
    assertStringIncludes(s, "Total em aberto: *R$ 5.238,02* (vencido: R$ 0,00)");
  }
  {
    const { db, ctx } = ambienteDaApolo({ tabelas: { receivables: parcelasDaApolo().map((c) => c.id === "p2" ? { ...c, service_order_id: ID_50 } : c) } });
    const e = await recusado(ctx, db, { cliente_id: APOLO });
    assertStringIncludes(e, "Não achei a OS de uma conta em aberto de APOLO INDUSTRIA E COMERCIO (NF-e 2/25 (parcela 2/3))");
  }
});

Deno.test("pelo cliente: as mesmas travas — genérico, sem conta em aberto, cliente que não existe, entrada esperando, opt-out, piso, sem telefone, conta demais", async () => {
  const fila = [{ suggested_client_id: APOLO, suggested_amount: 5237.99, suggested_date: "2026-10-16", title: "Receita: CREDITO DE BOLETO", status: "pending", kind: "create_receivable" }];
  const casos: Array<{ cliente: string; tabelas?: Record<string, Linha[]>; trecho: string }> = [
    { cliente: FINAL, trecho: "O cadastro Cliente Final é genérico, sem CPF/CNPJ" },
    { cliente: OUTRO, trecho: "Lenine não tem conta em aberto: não há o que cobrar." },
    { cliente: "8b2c3d4e-9999-4222-8333-444455556666", trecho: "Não achei esse cliente no cadastro" },
    { cliente: APOLO, tabelas: { finance_review_queue: fila }, trecho: "Este cliente tem entrada esperando no Extrato (R$ 5237.99 de 2026-10-16): pode ser este pagamento." },
    { cliente: APOLO, tabelas: { clients: [{ ...cadastroDaApolo(), opt_out_whatsapp: true }] }, trecho: "opt-out" },
    { cliente: APOLO, tabelas: { app_settings: [{ key: "collection_min_amount", value: "20000" }] }, trecho: "Cobrança de R$ 10476.01 fica abaixo do piso de R$ 20000" },
    { cliente: APOLO, tabelas: { clients: [{ ...cadastroDaApolo(), whatsapp: null }] }, trecho: "Sem telefone" },
    {
      cliente: APOLO,
      tabelas: { receivables: Array.from({ length: 31 }, (_, i) => ({ ...parcelasDaApolo()[0], id: "p" + String(i).padStart(2, "0") })) },
      trecho: "APOLO INDUSTRIA E COMERCIO tem 31 contas em aberto: é conta demais para uma mensagem só. Cobre pelas OS",
    },
  ];
  for (const c of casos) {
    const { db, ctx } = ambienteDaApolo({ tabelas: c.tabelas });
    const e = await recusado(ctx, db, { cliente_id: c.cliente });
    assertStringIncludes(e, c.trecho, e);
  }
});

Deno.test("pelo cliente: leitura que falha recusa; o 'sim' recusa se apareceu conta nova ou uma conta foi paga depois do pedido", async () => {
  for (const tabela of ["finance_review_queue", "receivables", "clients", "collections", "app_settings"]) {
    const { ctx } = ambienteDaApolo({ falhas: [tabela] });
    const resumo = await buildPendingSummary(ctx.admin, "cobrar_juntas", { cliente_id: APOLO }, { userId: "dono-1" });
    assertStringIncludes(resumo, "⚠️ Não consegui conferir as contas do cliente agora", tabela);
    assert(resumoQueRecusa("cobrar_juntas", resumo), tabela);
  }
  {
    const { db, ctx } = ambienteDaApolo();
    const p = await pedir(ctx, db, { cliente_id: APOLO });
    db.tabelas.receivables.push({ ...parcelasDaApolo()[0], id: "p9", description: "NF-e 2/30", due_date: "2026-10-20" });
    await comEnvio({ messageId: "m1" }, async (enviados) => {
      // deno-lint-ignore no-explicit-any
      const r = await toolsByName["cobrar_juntas"].execute(p.payload, ctx) as any;
      assertStringIncludes(r.error, "Nada foi enviado: as contas em aberto do cliente não são mais as mesmas depois do pedido");
      assertEquals(enviados, []);
    });
  }
  {
    // o banco deu baixa numa parcela entre o pedido e o "sim" (a baixa sozinha do boleto, por exemplo): não cobra a paga
    const { db, ctx } = ambienteDaApolo();
    const p = await pedir(ctx, db, { cliente_id: APOLO });
    Object.assign(db.tabelas.receivables.find((c: Linha) => c.id === "p2"), { paid_amount: 5237.99, balance_amount: 0, status: "paid" });
    await comEnvio({ messageId: "m1" }, async (enviados) => {
      // deno-lint-ignore no-explicit-any
      const r = await toolsByName["cobrar_juntas"].execute(p.payload, ctx) as any;
      assertStringIncludes(r.error, "Nada foi enviado: as contas em aberto do cliente não são mais as mesmas");
      assertEquals(enviados, []);
      assertEquals(db.chamadas.rpc, []);
    });
  }
});

Deno.test("avisos: OS em andamento entra com aviso; lembrete já mandado hoje avisa", async () => {
  const { db, ctx } = ambiente([ordem(ID_45, "OS-00045", { status: "in_progress" }), ordem(ID_46, "OS-00046")], {
    tabelas: {
      collections: [{ id: "col45", status: "sent", receivable_id: "r45", service_order_id: ID_45, last_auto_sent_at: "2026-10-28T12:00:00Z" }],
    },
  });
  const p = await pedir(ctx, db, { os: ["OS-00045", "OS-00046"] });
  const s = semNbsp(p.summary);
  assertStringIncludes(s, "- OS-00045 · Em andamento · em aberto *R$ 1.650,00*");
  assertStringIncludes(s, "OS-00045 ainda está em andamento: entra na cobrança, mas a nota só depois de concluída.");
  assertStringIncludes(s, "Já houve lembrete hoje para OS-00045");
});

Deno.test("sem cobrança nas contas (o caso da MP em produção): a confirmação diz que a cobrança é criada junto, e o 'sim' cria", async () => {
  const { db, ctx } = ambiente(osDaMP(), { tabelas: { collections: [] } });
  const p = await pedir(ctx, db, { os: ["OS-00045", "OS-00046"] });
  assertStringIncludes(semNbsp(p.summary),
    "2 contas não têm cobrança registrada: elas são criadas junto com o envio (aparecem em Cobranças), e o lembrete não repete hoje.");
  await comEnvio({ messageId: "m1" }, async () => {
    // deno-lint-ignore no-explicit-any
    const r = await toolsByName["cobrar_juntas"].execute(p.payload, ctx) as any;
    assertEquals([r.cobrancas_criadas, r.cobrancas_registradas], [2, 2], JSON.stringify(r));
    assertStringIncludes(r.message, "2 cobranças criadas (em Cobranças). Envio registrado em 2 cobranças.");
    assertEquals(db.tabelas.collections.map((k: Linha) => [k.receivable_id, k.status]).sort(), [["r45", "sent"], ["r46", "sent"]]);
  });
});

Deno.test("só a conta sem cobrança ganha uma; a OS com cobrança sem conta não ganha outra", async () => {
  // r45 sem cobrança nenhuma; a OS-00046 tem a "Total" sem conta (col46) — r46 fica sem cobrança própria.
  const { db, ctx } = ambiente(osDaMP(), {
    tabelas: { collections: [{ id: "col46", status: "pending", receivable_id: null, service_order_id: ID_46, last_auto_sent_at: null }] },
  });
  const p = await pedir(ctx, db, { os: ["OS-00045", "OS-00046"] });
  assertStringIncludes(semNbsp(p.summary), "1 conta não tem cobrança registrada: ela é criada junto com o envio");
  await comEnvio({ messageId: "m1" }, async () => {
    // deno-lint-ignore no-explicit-any
    const r = await toolsByName["cobrar_juntas"].execute(p.payload, ctx) as any;
    assertEquals([r.cobrancas_criadas, r.cobrancas_registradas], [1, 2], JSON.stringify(r));
    assertEquals(db.tabelas.collections.filter((k: Linha) => k.receivable_id === "r46"), []);
  });
});

Deno.test("a função do banco falha DEPOIS do envio: a resposta diz que a mensagem saiu e nada foi gravado", async () => {
  const { db, ctx } = ambiente(osDaMP(), { tabelas: { collections: [] }, falhas: ["rpc"] });
  const p = await pedir(ctx, db, { os: ["OS-00045", "OS-00046"] });
  await comEnvio({ messageId: "m1" }, async (enviados) => {
    // deno-lint-ignore no-explicit-any
    const r = await toolsByName["cobrar_juntas"].execute(p.payload, ctx) as any;
    assertEquals(enviados.length, 1);
    assertEquals([r.ok, r.cobrancas_criadas, r.cobrancas_registradas], [true, 0, 0]);
    assertStringIncludes(r.message, "A mensagem foi enviada, mas não consegui criar/registrar a cobrança (mês fechado). Nada foi gravado nas cobranças");
    assertEquals(db.tabelas.collections, []);
  });
});

Deno.test("mensagem que não sai: a função do banco nem é chamada (nenhuma cobrança criada)", async () => {
  const { db, ctx } = ambiente(osDaMP(), { tabelas: { collections: [] } });
  const p = await pedir(ctx, db, { os: ["OS-00045", "OS-00046"] });
  const original = globalThis.fetch;
  globalThis.fetch = (() => Promise.resolve(new Response(JSON.stringify({ error: "provedor fora" }), { status: 502 }))) as typeof fetch;
  try {
    // deno-lint-ignore no-explicit-any
    const r = await toolsByName["cobrar_juntas"].execute(p.payload, ctx) as any;
    assertStringIncludes(String(r.error), "A mensagem não saiu");
    assertEquals(db.chamadas.rpc.filter(([fn]: [string]) => fn === "cobrar_juntas_registrar_envio"), []);
    assertEquals(db.tabelas.collections, []);
  } finally {
    globalThis.fetch = original;
  }
});

// ── recusas sem pendência ────────────────────────────────────────────────────────────────────

Deno.test("recusas claras sem pendência: genérico, conta no genérico, não começou, outro cliente, sem saldo, cancelada, orçamento", async () => {
  const casos: Array<{ linhas?: Linha[]; tabelas?: Record<string, Linha[]>; trechos: string[] }> = [
    {
      linhas: osDaMP().map((o) => ({ ...o, client_id: FINAL })),
      tabelas: { receivables: contasDaMP().map((c) => ({ ...c, client_id: FINAL })) },
      trechos: ['O cadastro Cliente Final é genérico, sem CPF/CNPJ: não entra em cobrança conjunta.'],
    },
    {
      tabelas: { receivables: contasDaMP().map((c) => c.id === "r46" ? { ...c, client_id: FINAL } : c) },
      trechos: ['O cadastro Cliente Final é genérico, sem CPF/CNPJ'],
    },
    {
      linhas: [ordem(ID_45, "OS-00045"), ordem(ID_46, "OS-00046", { status: "scheduled" })],
      trechos: [
        "OS-00046 ainda não começou a ser executada (situação: Agendada)", "use agrupar_os",
        "Se o agrupar_os recusar por ela já ter começado", "proponha cobrar juntas sem ela",
      ],
    },
    // Fronteira (decisão 2 do dono): aguardando peças COM chegada no barco já começou — o agrupar_os recusa, então
    // aqui não se manda para ele (senão o assistente fica em laço entre as duas tools).
    {
      linhas: [ordem(ID_45, "OS-00045"), ordem(ID_46, "OS-00046", { status: "awaiting_parts", check_in_at: "2026-10-20T13:00:00Z" })],
      trechos: ["OS-00046 está Aguardando peças, mas já tem a chegada no barco registrada", "o agrupar_os também não a aceita", "mude a situação da OS para Em andamento"],
    },
    // Conta em nome do pagador (outro cadastro): cobra-se o titular, como a tela — recusa, não só avisa.
    {
      tabelas: { receivables: contasDaMP().map((c) => c.id === "r46" ? { ...c, client_id: OUTRO } : c) },
      trechos: ["A conta da OS-00046 está em nome de Lenine, não de MP MOTOR HOMES.", "Cobrar juntas cobra o titular da conta"],
    },
    {
      linhas: [ordem(ID_45, "OS-00045"), ordem(ID_46, "OS-00046", { client_id: OUTRO })],
      trechos: ["clientes diferentes"],
    },
    {
      tabelas: { receivables: contasDaMP().filter((c) => c.id !== "r46") },
      trechos: ["OS-00046 não tem saldo em aberto.", "Sobra só OS-00045: peça a cobrança pelo cliente (só o cliente_id, sem as OS: entra tudo que ele tem em aberto) ou mande o lembrete da cobrança dela (send_collection_reminder)."],
    },
    {
      linhas: [ordem(ID_45, "OS-00045"), ordem(ID_46, "OS-00046", { status: "cancelled" })],
      trechos: ["OS-00046 está cancelada"],
    },
    {
      linhas: [ordem(ID_45, "OS-00045"), ordem(ID_46, "OS-00046", { status: "cancelled", merged_into_id: ID_50 })],
      trechos: ["OS-00046 foi agrupada em outra OS"],
    },
  ];
  for (const c of casos) {
    const { db, ctx } = ambiente(c.linhas ?? osDaMP(), { tabelas: c.tabelas });
    const e = await recusado(ctx, db, { os: ["OS-00045", "OS-00046"] });
    for (const t of c.trechos) assertStringIncludes(e, t, e);
  }
});

Deno.test("as travas do lembrete: entrada esperando no Extrato, opt-out, abaixo do piso e sem telefone recusam sem pendência", async () => {
  const casos: Array<{ tabelas: Record<string, Linha[]>; trecho: string }> = [
    {
      tabelas: { finance_review_queue: [{ suggested_client_id: MP, suggested_amount: 1670, suggested_date: "2026-10-27", title: "Receita: MP", status: "pending", kind: "create_receivable" }] },
      trecho: "Este cliente tem entrada esperando no Extrato (R$ 1670.00 de 2026-10-27): pode ser este pagamento.",
    },
    { tabelas: { clients: cadastros().map((c) => c.id === MP ? { ...c, opt_out_whatsapp: true } : c) }, trecho: "opt-out" },
    {
      tabelas: { app_settings: [{ key: "collection_min_amount", value: "2000" }] },
      trecho: "Cobrança de R$ 1670.00 fica abaixo do piso de R$ 2000",
    },
    { tabelas: { clients: cadastros().map((c) => c.id === MP ? { ...c, whatsapp: null } : c) }, trecho: "Sem telefone" },
  ];
  for (const c of casos) {
    const { db, ctx } = ambiente(osDaMP(), { tabelas: c.tabelas });
    const e = await recusado(ctx, db, { os: ["OS-00045", "OS-00046"] });
    assertStringIncludes(e, c.trecho, e);
  }
});

Deno.test("leitura que falha recusa (nunca vira 'sem Pix esperando' ou 'nada em aberto')", async () => {
  for (const tabela of ["finance_review_queue", "receivables", "clients", "collections", "app_settings"]) {
    const { ctx } = ambiente(osDaMP(), { falhas: [tabela] });
    const resumo = await buildPendingSummary(ctx.admin, "cobrar_juntas", { os: ["OS-00045", "OS-00046"] }, { userId: "dono-1" });
    assertStringIncludes(resumo, "⚠️ Não consegui conferir as contas das OS agora", tabela);
    assert(resumoQueRecusa("cobrar_juntas", resumo), tabela);
  }
});

// ── o "sim" confere o retrato ────────────────────────────────────────────────────────────────

Deno.test("o 'sim' recusa se o saldo ou o telefone mudaram depois do pedido, ou se a pendência não tem retrato", async () => {
  {
    const { db, ctx } = ambiente();
    const p = await pedir(ctx, db, { os: ["OS-00045", "OS-00046"] });
    Object.assign(db.tabelas.receivables.find((c: Linha) => c.id === "r45"), { paid_amount: 1000, balance_amount: 650, status: "partially_paid" });
    await comEnvio({ messageId: "m1" }, async (enviados) => {
      // deno-lint-ignore no-explicit-any
      const r = await toolsByName["cobrar_juntas"].execute(p.payload, ctx) as any;
      assertStringIncludes(semNbsp(r.error), "Nada foi enviado: o saldo em aberto mudou (era R$ 1.670,00, agora R$ 670,00)");
      assertEquals(enviados, []);
    });
  }
  {
    const { db, ctx } = ambiente();
    const p = await pedir(ctx, db, { os: ["OS-00045", "OS-00046"] });
    db.tabelas.clients.find((c: Linha) => c.id === MP).whatsapp = "47988887777";
    await comEnvio({ messageId: "m1" }, async (enviados) => {
      // deno-lint-ignore no-explicit-any
      const r = await toolsByName["cobrar_juntas"].execute(p.payload, ctx) as any;
      assertStringIncludes(r.error, "o telefone do cadastro do cliente mudou");
      assertEquals(enviados, []);
    });
  }
  {
    const { ctx } = ambiente();
    // deno-lint-ignore no-explicit-any
    const r = await tool.execute({ os: ["OS-00045", "OS-00046"] }, ctx) as any;
    assertStringIncludes(r.error, "não consegui conferir as contas quando o pedido foi feito");
  }
});

Deno.test("o 'sim' fora do horário (22h em Brasília): o portão bloqueia, nada sai e o bloqueio fica no registro", async () => {
  const { db, ctx } = ambiente();
  const p = await pedir(ctx, db, { os: ["OS-00045", "OS-00046"] });
  const antes = relogioDoCobrarJuntas.agora;
  relogioDoCobrarJuntas.agora = () => new Date("2026-10-29T01:00:00Z");
  try {
    await comEnvio({ messageId: "m1" }, async (enviados) => {
      // deno-lint-ignore no-explicit-any
      const r = await toolsByName["cobrar_juntas"].execute(p.payload, ctx) as any;
      assertStringIncludes(r.error, "fora do horário");
      assertEquals(enviados, []);
      const log = db.chamadas.insert.filter(([t]: [string]) => t === "ai_comms_log").map(([, v]: [string, Linha]) => v);
      assertEquals(log.map((l: Linha) => [l.status, l.block_code]), [["blocked", "fora_de_horario"]]);
      assertEquals(db.chamadas.insert.filter(([t]: [string]) => t === "collection_contacts"), []);
    });
  } finally {
    relogioDoCobrarJuntas.agora = antes;
  }
});

Deno.test("cargo no 'sim': a pendência de quem não é admin/financeiro não executa nem pela mão do admin", async () => {
  const { ctx } = ambiente();
  // deno-lint-ignore no-explicit-any
  const r = await tool.execute({ os: ["OS-00045", "OS-00046"], _solicitante: { user_id: "v1", cargo: "seller" }, _retrato: { cliente: MP } }, ctx) as any;
  assertStringIncludes(r.error, "administrador ou financeiro");
});

// ── a fronteira com agrupar_os ───────────────────────────────────────────────────────────────

Deno.test("fronteira: agrupar_os com OS executada aponta cobrar_juntas", () => {
  const os = {
    id: ID_45, service_order_number: "OS-00045", status: "completed", quote_status: "approved", grand_total: 1650,
    created_at: "2026-06-01", updated_at: "2026-06-01", client_id: MP, vessel_id: "v", merged_into_id: null,
    converted_to_os_at: "2026-06-01", signed_at: null, travel_cost_total: 0, travel_distance_km: 0, travel_hours: 0,
    ferry_cost: 0, commission_rate: 0, commissioned_person: null, payment_conditions: null, payment_condition_preset_id: null,
    discount_amount: 0, tax_amount: 0,
  };
  const problemas = problemasDoPedidoDeOS({ origens: [os, { ...os, id: ID_46, service_order_number: "OS-00046" }], principal: os, total: 0 }, null, {});
  assertStringIncludes(problemas.join(" "), "use cobrar_juntas");
});

// ── registro: perfil, política, título, rede ─────────────────────────────────────────────────

Deno.test("registro: risco alto, só admin/financeiro, nunca autônoma, título em português, no perfil de operação e fora do enxuto", async () => {
  assertEquals(tool.risk, "high");
  assertEquals(tool.roles, CARGOS_DE_COBRAR_JUNTAS);
  assertEquals([...CARGOS_DE_COBRAR_JUNTAS].sort(), ["admin", "financial"]);
  assertEquals(tool.gravarSolicitante, true);
  assert(NEVER_AUTONOMOUS.has("cobrar_juntas"));
  assertEquals(tituloDaAcao("cobrar_juntas"), "Cobrar o cliente (WhatsApp)");
  assert(allTools.some((t) => t.name === "cobrar_juntas"));
  assert(PERFIL_OPERACAO.has("cobrar_juntas"));
  assertEquals(PERFIL_ADMIN.has("cobrar_juntas"), false, "no perfil enxuto subiria o teto");
  assertEquals(SO_PELA_REDE.has("cobrar_juntas"), false);
  assertEquals(FORA_DO_WHATSAPP.has("cobrar_juntas"), false, "o dono cobra pelo WhatsApp");
  assertEquals(rodaDiretoPelaRede(tool), false);

  // Como o Claude Max (erp-mcp) monta o turno do admin no perfil enxuto: a ferramenta_extra alcança e vira pendência.
  const job = ferramentasDoJob("admin", [...PERFIL_ADMIN, NOME_DA_FERRAMENTA_EXTRA], allTools.map((t) => t.name), "whatsapp");
  assert(job.alcancaveisPelaRede["cobrar_juntas"], "fora do alcance da ferramenta_extra");
  const tecnico = ferramentasDoJob("technician", [...PERFIL_OPERACAO], [], "whatsapp");
  assertEquals(Object.keys(tecnico.toolsByName).includes("cobrar_juntas"), false);
  const { db, ctx } = ambiente();
  const r = await executarChamadaDeTool({
    name: NOME_DA_FERRAMENTA_EXTRA, input: { nome: "cobrar_juntas", argumentos: { os: ["OS-00045", "OS-00046"] } },
  }, { ...job, toolCtx: ctx, sessionId: "s1", channel: "whatsapp" as const });
  // deno-lint-ignore no-explicit-any
  assertEquals((r.toolResult as any).pending, true, JSON.stringify(r.toolResult));
  assertEquals(pendencias(db)[0].action_name, "cobrar_juntas");
});

// ── consertos da revisão de 25/11/2026 ───────────────────────────────────────────────────────

Deno.test("o retrato guarda o TEXTO: cartão às 20h30 com a conta 'a vencer' e 'sim' no dia seguinte (vencida) não envia", async () => {
  const antes = relogioDoCobrarJuntas.agora;
  try {
    // 13/11 às 20h30 em Brasília: a parcela 3/3 vence hoje — "a vencer"
    relogioDoCobrarJuntas.agora = () => new Date("2026-11-13T23:30:00Z");
    const { db, ctx } = ambienteDaApolo({ tabelas: { receivables: parcelasDaApolo().filter((c) => c.id === "p3") } });
    const p = await pedir(ctx, db, { cliente_id: APOLO });
    assertStringIncludes(semNbsp(p.summary), "🟡 NF-e 2/25 (parcela 3/3) · vence 13/11/2026 · a vencer");
    assertEquals(typeof p.payload._retrato.texto, "string");
    // o "sim" às 8h10 do dia 14: a mesma conta, o mesmo saldo — mas o texto viraria "vencido"
    relogioDoCobrarJuntas.agora = () => new Date("2026-11-14T11:10:00Z");
    await comEnvio({ messageId: "m1" }, async (enviados) => {
      // deno-lint-ignore no-explicit-any
      const r = await toolsByName["cobrar_juntas"].execute(p.payload, ctx) as any;
      assertStringIncludes(r.error, "Nada foi enviado: o texto da mensagem mudou");
      assertEquals(enviados, []);
    });
  } finally {
    relogioDoCobrarJuntas.agora = antes;
  }
});

Deno.test("o retrato guarda o TEXTO: a chave Pix trocada entre o cartão e o 'sim' não envia; retrato antigo (sem texto) segue como antes", async () => {
  const { db, ctx } = ambiente();
  const p = await pedir(ctx, db, { os: ["OS-00045", "OS-00046"] });
  db.tabelas.app_settings.find((s: Linha) => s.key === "pix_key").value = "outra-chave@pix";
  await comEnvio({ messageId: "m1" }, async (enviados) => {
    // deno-lint-ignore no-explicit-any
    const r = await toolsByName["cobrar_juntas"].execute(p.payload, ctx) as any;
    assertStringIncludes(r.error, "o texto da mensagem mudou");
    assertEquals(enviados, []);
  });
  // a pendência de antes do deploy não tem o texto no retrato: compara só o resto, como antes
  const { texto: _fora, ...semTexto } = p.payload._retrato;
  await comEnvio({ messageId: "m1" }, async (enviados) => {
    // deno-lint-ignore no-explicit-any
    const r = await toolsByName["cobrar_juntas"].execute({ ...p.payload, _retrato: semTexto }, ctx) as any;
    assertEquals(r.ok, true, JSON.stringify(r));
    assertEquals(enviados.length, 1);
  });
});

Deno.test("cartão: telefone que parece FIXO ganha a linha de atenção", async () => {
  const { db, ctx } = ambienteDaApolo({ tabelas: { clients: [...cadastros(), { ...cadastroDaApolo(), whatsapp: "(47) 3333-4444" }] } });
  const s = semNbsp((await pedir(ctx, db, { cliente_id: APOLO })).summary);
  assertStringIncludes(s, "- Atenção: o número parece de telefone FIXO (sem WhatsApp, em geral): a mensagem pode não chegar. Confira o cadastro.");
});

Deno.test("com as OS ditas, a recusa da OS que não começou aponta também o caminho pelo cliente (uma vez só)", async () => {
  const { db, ctx } = ambiente([ordem(ID_45, "OS-00045", { status: "scheduled" }), ordem(ID_46, "OS-00046", { status: "awaiting_client" })]);
  const e = await recusado(ctx, db, { os: ["OS-00045", "OS-00046"] });
  assertStringIncludes(e, "Para cobrar sem mexer na OS, peça pelo cliente (só o cliente_id, sem as OS): entra TUDO que ele tem em aberto");
  assertEquals(e.split("Para cobrar sem mexer na OS").length - 1, 1, "uma vez só");
  // cancelada não ganha a frase (não é caso de cobrar pelo cliente)
  const cancelada = ambiente([ordem(ID_45, "OS-00045"), ordem(ID_46, "OS-00046", { status: "cancelled" })]);
  assertEquals((await recusado(cancelada.ctx, cancelada.db, { os: ["OS-00045", "OS-00046"] })).includes("Para cobrar sem mexer na OS"), false);
});

Deno.test("pelo cliente: 30 contas ainda cabem numa mensagem; 31 não", async () => {
  const muitas = (n: number) => Array.from({ length: n }, (_, i) => ({ ...parcelasDaApolo()[0], id: "p" + String(i).padStart(2, "0") }));
  const { db, ctx } = ambienteDaApolo({ tabelas: { receivables: muitas(30) } });
  assertStringIncludes(semNbsp((await pedir(ctx, db, { cliente_id: APOLO })).summary), "por tudo que ele tem em aberto (30 contas)");
});

Deno.test("retrato que falhou na hora da pendência: o cartão vira recusa em vez de pedir um 'sim' que nunca enviaria", async () => {
  const { ctx } = ambienteDaApolo();
  const semRetrato = await buildPendingSummary(ctx.admin, "cobrar_juntas", { cliente_id: APOLO }, { userId: "dono-1", retrato: null });
  assertEquals(semRetrato, "⚠️ Não consegui conferir as contas agora. Nada foi registrado; tente de novo.");
  assert(resumoQueRecusa("cobrar_juntas", semRetrato));
});

Deno.test("ensino: o prompt e as descrições mandam 'cobra o Fulano' ao cliente inteiro e o lembrete a uma cobrança", async () => {
  const fonte = await Deno.readTextFile(new URL("../prompt.ts", import.meta.url));
  for (const trecho of [
    "cobrar_juntas SÓ COM O CLIENTE",
    "LEMBRETE CURTO de UMA cobrança",
    "Para efetivamente cobrar um cliente do plano → cobrar_juntas só com cliente_id",
    "Não use list_pending_collections para saber se ele tem outras contas",
  ]) assertStringIncludes(fonte, trecho);
  assertEquals(fonte.includes("Uma OS só → send_collection_reminder"), false, "o ensino antigo saiu");
  assertEquals(fonte.includes("entram as OS executadas dele com saldo"), false, "o ensino antigo saiu");
  assertStringIncludes(tool.description, "(1) Pelo CLIENTE");
  assertStringIncludes(toolsByName["get_delinquency_plan"].description, "cobrar_juntas só com cliente_id = o client_id do caso");
  assertStringIncludes(toolsByName["send_collection_reminder"].description, "cobrar_juntas");
});

Deno.test("a OS dita que não começou e NÃO tem conta em aberto: a recusa não manda ao caminho pelo cliente (seria outra recusa)", async () => {
  const { db, ctx } = ambiente([ordem(ID_45, "OS-00045"), ordem(ID_46, "OS-00046", { status: "scheduled" })], {
    tabelas: { receivables: contasDaMP().filter((c) => c.service_order_id !== ID_46) },
  });
  const e = await recusado(ctx, db, { os: ["OS-00045", "OS-00046"] });
  assertStringIncludes(e, "OS-00046 ainda não começou a ser executada");
  assertEquals(e.includes("Para cobrar sem mexer na OS"), false, e);
});

Deno.test("paridade com a tela: a cobrança do cliente inteiro dá a MESMA mensagem da cobrança do cliente pela tela (buildClientStatement com cobranca)", async () => {
  // O caso mora em _shared/receivables/cobrar-juntas_paridade.ts e o client-statement.test.ts (vitest) compara o texto da tela
  // (o botão da linha, a aba Cobranças, o Cobrar em lote — 26/11/2026) com o MESMO esperado.
  const { db } = ambiente(PC.os.map((o) => ordem(o.id, o.numero)), {
    tabelas: {
      receivables: PC.contas.map((x) => ({ ...x, client_id: MP })),
      app_settings: [{ key: "pix_key", value: PC.pixKey }],
    },
  });
  const c = await montarCobrancaConjunta(db, db, { cliente_id: MP });
  assert(!("error" in c), JSON.stringify(c));
  assertEquals(c.mensagem, PC.esperado);
});
