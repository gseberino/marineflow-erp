// Agrupar OS pelo assistente (28/10/2026). O pedido do dono que guia os testes:
//   "Junta a OS-00100 com a OS-00128 do Giancarlo, da Vitória Star."
// Em produção (27/10/2026): OS-00100 (sinal pago R$ 2.869,50) e OS-00128 (sinal pago R$ 1.000 e saldo de
// R$ 2.839,50 pendente, com cobrança). A confirmação tem de mostrar o dinheiro que passa para a OS nova; OS que
// já começou a ser executada, com nota, de outro barco ou que ainda é orçamento NÃO vira pendência — volta o
// motivo (e, se é orçamento, a tool certa: agrupar_orcamentos).
// Rodar com:
//   deno test --allow-all supabase/functions/_shared/ai/tools/agrupar-os_test.ts
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { agruparOsTools, retratoDoAgrupamentoDeOS, STATUS_QUE_AGRUPAM, validarPedidoDeAgruparOS } from "./agrupar-os.ts";
import { CARGOS_DO_AGRUPAMENTO } from "./agrupar-orcamentos.ts";
import { agrupadoEm, ehOsAgrupada } from "./service-orders.ts";
import { frasesDaOrdemCancelada } from "./whatsapp.ts";
import { allTools, toolsByName } from "./index.ts";
import { buildPendingSummary, executarChamadaDeTool, ressalvaDoResultado, resumoQueRecusa, tituloDaAcao } from "../agent.ts";
import { NEVER_AUTONOMOUS } from "../autonomy-policy.ts";
import { PERFIL_ADMIN, PERFIL_OPERACAO, rodaDiretoPelaRede, SO_PELA_REDE } from "../perfil-operacao.ts";
import { ferramentasDoJob } from "../max/ferramentas-do-job.ts";
import { NOME_DA_FERRAMENTA_EXTRA } from "../ferramenta-extra.ts";
import { FORA_DO_WHATSAPP } from "../channel-scope.ts";

/** Intl põe espaço sem quebra entre "R$" e o valor. */
const semNbsp = (x: unknown) => String(x ?? "").replace(/ /g, " ");
const UUID_NO_TEXTO = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i;
/** Nome de ferramenta/campo (snake_case) num texto que vai DIRETO ao dono. */
const NOME_TECNICO = /\b[a-z]+_[a-z_]+\b/;

const BARCO = "7a1b2c3d-1111-4222-8333-444455556666";
const CLIENTE = "8b2c3d4e-1111-4222-8333-444455556666";
const ID_100 = "22222222-2222-4222-8222-222222222100";
const ID_128 = "22222222-2222-4222-8222-222222222128";
const ID_131 = "22222222-2222-4222-8222-222222222131";
const ID_ORC_100 = "11111111-1111-4111-8111-111111111100";

// deno-lint-ignore no-explicit-any
type Linha = Record<string, any>;

function ordem(id: string, numero: string, extra: Linha = {}): Linha {
  return {
    id, service_order_number: numero, status: "open", quote_status: "approved", grand_total: 0,
    created_at: "2026-10-01T12:00:00+00:00", updated_at: "2026-10-01T12:00:00+00:00",
    client_id: CLIENTE, vessel_id: BARCO, merged_into_id: null, converted_to_os_at: "2026-10-01T12:00:00+00:00", signed_at: null,
    share_token: "tok", travel_cost_total: 0, travel_distance_km: 0, travel_hours: 0, ferry_cost: 0, commission_rate: 0,
    commissioned_person: null, payment_conditions: null, payment_condition_preset_id: null, discount_amount: 0, tax_amount: 0,
    cancellation_reason: null,
    ...extra,
  };
}

/** As duas do Giancarlo (Vitória Star). */
function osDoGiancarlo(): Linha[] {
  return [
    ordem(ID_100, "OS-00100", { grand_total: 5739, created_at: "2026-09-02T13:00:00+00:00", updated_at: "2026-10-20T10:00:00+00:00", commission_rate: 5, commissioned_person: "Marcos" }),
    ordem(ID_128, "OS-00128", { status: "scheduled", grand_total: 3839.5, created_at: "2026-10-10T15:00:00+00:00", updated_at: "2026-10-21T09:00:00+00:00" }),
  ];
}

function recebiveisDoGiancarlo(): Linha[] {
  return [
    { id: "r1", service_order_id: ID_100, description: "Sinal OS-00100", amount: 2869.5, paid_amount: 2869.5, status: "paid", is_deposit: true },
    { id: "r2", service_order_id: ID_128, description: "Sinal OS-00128", amount: 1000, paid_amount: 1000, status: "paid", is_deposit: true },
    { id: "r3", service_order_id: ID_128, description: "Saldo OS-00128", amount: 2839.5, paid_amount: 0, status: "pending", is_deposit: false },
    { id: "r4", service_order_id: ID_128, description: "Antigo", amount: 50, paid_amount: 0, status: "cancelled", is_deposit: false },
  ];
}

const SITUACAO: Record<string, string> = { open: "Aberta", scheduled: "Agendada", in_progress: "Em andamento", approved: "Aprovada" };

/** A resposta de os_para_agrupar para as linhas dadas (o que o banco diria), da mais nova para a mais antiga. */
function leituraDoBanco(linhas: Linha[], motivos: Record<string, string> = {}) {
  const candidatas = linhas.filter((l) => l.status !== "draft" && l.status !== "cancelled" && !l.merged_into_id)
    .sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)));
  return {
    embarcacao: { id: BARCO, nome: "Vitória Star" },
    cliente: { id: CLIENTE, nome: "Giancarlo" },
    os: candidatas.map((l) => ({
      id: l.id, numero: l.service_order_number, status: l.status, criado_em: l.created_at, total: l.grand_total,
      situacao: SITUACAO[l.status] ?? l.status, elegivel: !motivos[l.id], motivo: motivos[l.id] ?? null,
      condicao_pagamento: l.id === ID_100 ? "50% de sinal e o saldo na entrega" : null,
    })),
    fora_da_lista: [] as Linha[],
    agrupados_ativos: [] as Linha[],
  };
}

// deno-lint-ignore no-explicit-any
function bancoFalso(tabelas: Record<string, Linha[]>, rpcs: Record<string, (p: any) => { data?: unknown; error?: { message: string } }> = {}) {
  const chamadas = { rpc: [] as [string, Linha][], insert: [] as [string, Linha][] };
  // deno-lint-ignore no-explicit-any
  const db: any = {
    chamadas,
    tabelas,
    rpc(nome: string, p: Linha) {
      chamadas.rpc.push([nome, p]);
      const r = rpcs[nome]?.(p) ?? {};
      return Promise.resolve({ data: r.data ?? null, error: r.error ?? null });
    },
    from(tabela: string) {
      const filtros: Array<(l: Linha) => boolean> = [];
      const linhas = () => (tabelas[tabela] ?? []).filter((l) => filtros.every((f) => f(l)));
      // deno-lint-ignore no-explicit-any
      const q: any = {
        select: () => q, order: () => q, limit: () => q,
        eq: (c: string, v: unknown) => (filtros.push((l) => l[c] === v), q),
        neq: (c: string, v: unknown) => (filtros.push((l) => l[c] !== v), q),
        in: (c: string, vs: unknown[]) => (filtros.push((l) => vs.includes(l[c])), q),
        is: (c: string, v: unknown) => (filtros.push((l) => (l[c] ?? null) === v), q),
        maybeSingle: () => Promise.resolve({ data: linhas()[0] ?? null, error: null }),
        single: () => Promise.resolve({ data: linhas()[0] ?? null, error: null }),
        // deno-lint-ignore no-explicit-any
        then: (ok: any, ko: any) => Promise.resolve({ data: linhas(), error: null }).then(ok, ko),
        insert: (v: Linha) => {
          chamadas.insert.push([tabela, v]);
          // deno-lint-ignore no-explicit-any
          const r: any = Promise.resolve({ data: null, error: null });
          r.select = () => ({ single: () => Promise.resolve({ data: { id: `novo-${tabela}`, ...v }, error: null }) });
          return r;
        },
      };
      return q;
    },
  };
  return db;
}

interface Extra {
  motivos?: Record<string, string>;
  tabelas?: Record<string, Linha[]>;
  agrupadas?: Linha[];
}

function ambiente(linhas: Linha[], extra: Extra = {}) {
  const tabelas: Record<string, Linha[]> = {
    service_orders: linhas,
    receivables: recebiveisDoGiancarlo(),
    service_order_signatures: [],
    app_users: [{ id: "dono-1", full_name: "Gustavo" }],
    ...(extra.tabelas ?? {}),
  };
  const numeros = (ids: string[]) => ids.map((id) => linhas.find((l) => l.id === id)?.service_order_number);
  const db = bancoFalso(tabelas, {
    // a leitura é feita na hora de cada chamada: reflete o que o teste mexeu nas linhas
    os_para_agrupar: () => ({ data: { ...leituraDoBanco(tabelas.service_orders, extra.motivos), agrupados_ativos: extra.agrupadas ?? [] } }),
    agrupar_os: (p) => ({
      data: {
        service_order_id: ID_131, numero: "OS-00131", agrupamento_id: "g1", origens: numeros(p.p_os), principal: "OS-00100",
        servicos: 5, pecas: 7, recebiveis_movidos: 3, cobrancas_movidas: 1, tarefas_movidas: 1, tecnicos: 2, envios_cancelados: 0,
        total_geral: p.p_total_esperado, comissao: 478.93,
        avisos: [
          "As assinaturas ficaram nas OS originais (OS-00128): a OS-00131 nasce sem assinatura.",
          "Condição de pagamento, contato e comissão vêm da OS-00100 (a principal).",
          "Na hora da nota: uma NFS-e cobre um tomador, um código de serviço e uma competência.",
        ],
      },
    }),
    desagrupar_os: () => ({
      data: { agrupado_id: ID_131, agrupado: "OS-00131", origens: ["OS-00100", "OS-00128"], origens_ids: [ID_100, ID_128],
        registros_devolvidos: 6, envios_cancelados: 0, envios_reativados: 1 },
    }),
  });
  const ctx = { sb: db, admin: db, userId: "dono-1", userRole: "admin" as const, jwt: "", appOrigin: "", settings: { app_public_url: "https://app.exemplo" } };
  return { db, ctx };
}

const tool = (nome: string) => agruparOsTools.find((t) => t.name === nome)!;
// deno-lint-ignore no-explicit-any
const amb = (ctx: any) => ({ toolsByName: toolsByName, alcancaveisPelaRede: {}, toolCtx: ctx, sessionId: "s1", channel: "whatsapp" as const });
// deno-lint-ignore no-explicit-any
const pendencias = (db: any) => db.chamadas.insert.filter(([t]: [string]) => t === "ai_operator_pending_actions").map(([, v]: [string, Linha]) => v);
// deno-lint-ignore no-explicit-any
const rpcsDeEscrita = (db: any) => db.chamadas.rpc.filter(([n]: [string]) => n === "agrupar_os" || n === "desagrupar_os");
/** Pede pela conversa e devolve a pendência criada (ou falha o teste). */
// deno-lint-ignore no-explicit-any
async function pedir(ctx: any, db: any, nome: string, input: Record<string, unknown>): Promise<Linha> {
  const r = await executarChamadaDeTool({ name: nome, input }, amb(ctx));
  // deno-lint-ignore no-explicit-any
  assertEquals((r.toolResult as any).pending, true, JSON.stringify(r.toolResult));
  return pendencias(db).at(-1);
}
// deno-lint-ignore no-explicit-any
async function recusado(ctx: any, db: any, nome: string, input: Record<string, unknown>): Promise<string> {
  const r = await executarChamadaDeTool({ name: nome, input }, amb(ctx));
  // deno-lint-ignore no-explicit-any
  const res = r.toolResult as any;
  assertEquals(res.pending, undefined, JSON.stringify(res));
  assertEquals(pendencias(db), [], "nada vai para o sino nem pede 'sim'");
  assertEquals(rpcsDeEscrita(db), [], "a função de gravar nem foi chamada");
  return semNbsp(res.error);
}

// ── listar ───────────────────────────────────────────────────────────────────────────────────

Deno.test("listar OS: chama os_para_agrupar com quem pede (p_autor) e a instrução não manda apagar execução", async () => {
  const { db, ctx } = ambiente(osDoGiancarlo());
  // deno-lint-ignore no-explicit-any
  const r = await tool("listar_os_para_agrupar").execute({ embarcacao_id: BARCO, cliente_id: CLIENTE }, ctx) as any;
  assertEquals(db.chamadas.rpc, [["os_para_agrupar", { p_vessel_id: BARCO, p_client_id: CLIENTE, p_autor: "dono-1" }]]);
  assertEquals(r.os.length, 2);
  assertStringIncludes(r.instrucao, "chame agrupar_os já");
  assertStringIncludes(r.instrucao, "fora_da_lista");
  assertStringIncludes(r.instrucao, "nunca sugira apagar horas");
});

Deno.test("listar OS: sem id da embarcação não chama o banco; técnico não lista; erro do banco vira a frase", async () => {
  const { db, ctx } = ambiente([]);
  const t = tool("listar_os_para_agrupar");
  // deno-lint-ignore no-explicit-any
  assertStringIncludes((await t.execute({ embarcacao_id: "Vitória Star" }, ctx) as any).error, "search_vessels");
  // deno-lint-ignore no-explicit-any
  assertStringIncludes((await t.execute({ embarcacao_id: BARCO }, { ...ctx, userRole: "technician" }) as any).error, "administrador ou financeiro");
  assertEquals(db.chamadas.rpc.length, 0);
  assertEquals(t.roles, CARGOS_DO_AGRUPAMENTO);
  assertEquals(t.risk, "low");
  ctx.sb.rpc = () => Promise.resolve({ data: null, error: { message: "42501: Só administrador ou financeiro pode agrupar OS." } });
  // deno-lint-ignore no-explicit-any
  assertEquals((await t.execute({ embarcacao_id: BARCO }, ctx) as any).error, "Só administrador ou financeiro pode agrupar OS.");
});

// ── pré-validação ────────────────────────────────────────────────────────────────────────────

Deno.test("preValidar (sem banco): 2 a 10, só número/id ('a última' não), 'OS-00100' e '100' são a mesma, sem técnico", () => {
  const admin = { userRole: "admin" } as const;
  assertStringIncludes(validarPedidoDeAgruparOS({ os: ["OS-00100"] }, admin)!.error, "pelo menos 2");
  assertStringIncludes(validarPedidoDeAgruparOS({ os: Array.from({ length: 11 }, (_, i) => `OS-${i}`) }, admin)!.error, "no máximo 10");
  assertStringIncludes(validarPedidoDeAgruparOS({ os: ["OS-00100", "100"] }, admin)!.error, "duas vezes");
  assertStringIncludes(validarPedidoDeAgruparOS({ os: ["OS-00100", "OS-00128"] }, { userRole: "technician" })!.error, "administrador");
  assertStringIncludes(validarPedidoDeAgruparOS({ os: ["OS-00100", "OS-00128"] }, { userRole: "seller" })!.error, "administrador");
  assertEquals(validarPedidoDeAgruparOS({ os: ["OS-00100", "OS-00128"] }, { userRole: "financial" }), null);
  assertStringIncludes(validarPedidoDeAgruparOS({ os: ["a última", "OS-00128"] }, admin)!.error, "não é número de OS");
  assertStringIncludes(validarPedidoDeAgruparOS({ os: ["OS-00100", "OS-00128"], principal: "a mais antiga" }, admin)!.error, "não é número de OS");
  // ORÇ-00100 e OS-00100 são documentos diferentes: não é repetido (a conferência recusa o orçamento depois)
  assertEquals(validarPedidoDeAgruparOS({ os: ["ORÇ-00100", "OS-00100"] }, admin), null);
  assertEquals(validarPedidoDeAgruparOS({ os: "OS-00100, 128" }, admin), null);
});

// ── o pedido do dono: OS-00100 + OS-00128 ────────────────────────────────────────────────────

Deno.test("agrupar OS: a pendência mostra cada OS, o total, a principal, o dinheiro que passa e os avisos — sem uuid", async () => {
  const { db, ctx } = ambiente(osDoGiancarlo());
  const p = await pedir(ctx, db, "agrupar_os", { os: ["OS-00128", "OS-00100"] });
  assertEquals(p.title, "Agrupar OS em uma só");
  assertEquals(p.action_name, "agrupar_os");
  const s = semNbsp(p.summary);
  assertEquals(UUID_NO_TEXTO.test(s), false, s);
  assertStringIncludes(s, "Agrupar *2* OS de *Giancarlo · Vitória Star* em uma OS NOVA (Aberta, como a principal):");
  // na ordem do banco (mais antiga primeiro), a principal marcada
  assertStringIncludes(s, "- OS-00100 · 02/09/2026 · Aberta · R$ 5.739,00 ← principal\n- OS-00128 · 10/10/2026 · Agendada · R$ 3.839,50");
  assertStringIncludes(s, "Total previsto: *R$ 9.578,50* (a soma das originais)");
  assertStringIncludes(s,
    "Principal: *OS-00100* — dela vêm a situação, a condição de pagamento (50% de sinal e o saldo na entrega), o contato e a " +
      "comissão (5% para Marcos, recalculada sobre o total novo).");
  // o dinheiro com valores (o cancelado não entra)
  assertStringIncludes(s,
    "Passam para a OS nova, sem mudar valor nem situação (total R$ 6.709,00): OS-00100: sinal R$ 2.869,50 (pago) · " +
      "OS-00128: sinal R$ 1.000,00 (pago); Saldo OS-00128 R$ 2.839,50 (em aberto).");
  assertEquals(s.includes("Antigo"), false, "recebível cancelado não passa");
  assertStringIncludes(s, "tarefas manuais pendentes, pedidos de compra e cotações");
  assertStringIncludes(s, "Comissões diferentes");
  assertStringIncludes(s, "Situações diferentes (OS-00100 Aberta; OS-00128 Agendada): a nova nasce com a da principal.");
  assertStringIncludes(s, "uma NFS-e cobre um tomador, um código de serviço e uma competência");
  assertStringIncludes(s, "As originais ficam canceladas como histórico");
  assertStringIncludes(s, "Dá para desagrupar enquanto a nova não começar a ser executada");
  assertStringIncludes(s, "Pedido por: *Gustavo* (Administrador)");
  assertEquals(s.includes("Assinaturas ficam"), false, "nenhuma assinada");
  // o retrato e quem pediu vão no payload; nada foi gravado ainda
  assertEquals(p.payload._retrato.principal, ID_100);
  assertEquals(p.payload._retrato.total, 9578.5);
  assertEquals(p.payload._retrato.recebiveis, 6709);
  assertEquals(p.payload._solicitante.cargo, "admin");
  assertEquals(rpcsDeEscrita(db), []);
  // a leitura foi em nome de quem pede, com as escolhidas em p_incluir
  const leitura = db.chamadas.rpc.find(([n]: [string]) => n === "os_para_agrupar")?.[1];
  assertEquals(leitura.p_autor, "dono-1");
  assertEquals([...leitura.p_incluir].sort(), [ID_100, ID_128]);
});

Deno.test("agrupar OS: OS assinada avisa que a assinatura fica na original (não recusa)", async () => {
  const { db, ctx } = ambiente(osDoGiancarlo(), {
    tabelas: { service_order_signatures: [{ service_order_id: ID_128, superseded_at: null }, { service_order_id: ID_100, superseded_at: "2026-10-01T00:00:00Z" }] },
  });
  const p = await pedir(ctx, db, "agrupar_os", { os: ["OS-00100", "OS-00128"] });
  assertStringIncludes(p.summary, "Assinaturas ficam nas OS originais (OS-00128): o cliente assinou aquele documento. A OS nova nasce sem assinatura");
});

Deno.test("o 'sim': chama agrupar_os com os ids, a principal, a soma do retrato e p_autor; o aviso (que o dono lê) traz o número novo", async () => {
  const { db, ctx } = ambiente(osDoGiancarlo());
  const p = await pedir(ctx, db, "agrupar_os", { os: ["OS-00100", "128"], principal: "OS-00128" });
  // deno-lint-ignore no-explicit-any
  const r = await toolsByName["agrupar_os"].execute(p.payload, ctx) as any;
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(rpcsDeEscrita(db), [["agrupar_os", { p_os: [ID_100, ID_128], p_base: ID_128, p_total_esperado: 9578.5, p_autor: "dono-1" }]]);
  assertEquals(r.numero, "OS-00131");
  assertEquals(r.origens, ["OS-00100", "OS-00128"]);
  assertEquals(r.recebiveis_movidos, 3);
  assertEquals(r.link_interno, `https://app.exemplo/service-orders/${ID_131}`);
  const ressalva = semNbsp(ressalvaDoResultado(r));
  assertStringIncludes(ressalva, "Nova OS OS-00131, com OS-00100, OS-00128 — R$ 9.578,50.");
  assertStringIncludes(ressalva, "3 recebíveis passaram para a nova, sem mudar valor nem situação.");
  assertStringIncludes(ressalva, "As assinaturas ficaram nas OS originais (OS-00128)");
  assertEquals(ressalva.includes("NFS-e"), false, "a regra da nota já estava na confirmação");
  assertEquals(ressalva.includes("Condição de pagamento"), false, "a condição já estava na confirmação");
  assertEquals(r.avisos.length, 3, "o resultado guarda todos os avisos do banco");
  assertEquals(NOME_TECNICO.test(ressalva), false, ressalva);
  assertStringIncludes(r.message, "é só pedir para desagrupar");
  assertEquals(NOME_TECNICO.test(r.message), false, r.message);
});

Deno.test("número sem prefixo é OS: '100' acha a OS-00100 mesmo com um ORÇ-00100 no banco (sem 'Qual deles?')", async () => {
  const { db, ctx } = ambiente([...osDoGiancarlo(), ordem(ID_ORC_100, "ORÇ-00100", { status: "draft", converted_to_os_at: null, quote_status: "draft" })]);
  const p = await pedir(ctx, db, "agrupar_os", { os: ["100", "128"] });
  assertEquals(p.payload._retrato.origens.map((o: Linha) => o.numero), ["OS-00100", "OS-00128"]);
});

// ── recusas sem pendência ────────────────────────────────────────────────────────────────────

Deno.test("recusas claras sem pendência: já começou, nota pela leitura, outra embarcação, já agrupada, cancelada, deslocamento em duas", async () => {
  const casos: Array<{ linhas: Linha[]; motivos?: Record<string, string>; trechos: string[] }> = [
    {
      linhas: [ordem(ID_100, "OS-00100", { status: "in_progress", created_at: "2026-09-02T13:00:00+00:00" }), ordem(ID_128, "OS-00128")],
      trechos: ["OS-00100 já começou a ser executada (situação: Em andamento)", "cada OS executada mantém seu histórico", "Sem ela, sobram menos de 2 OS"],
    },
    {
      linhas: osDoGiancarlo(),
      motivos: { [ID_128]: "OS-00128 já começou a ser executada (hora apontada). Agrupar só junta OS que ainda não começaram; cada OS executada mantém seu histórico." },
      trechos: ["OS-00128 já começou a ser executada (hora apontada). Agrupar só junta OS", "Nunca sugira cancelar nota", "Sem ela, sobram menos de 2 OS"],
    },
    {
      linhas: osDoGiancarlo(), motivos: { [ID_100]: "OS-00100 tem nota fiscal emitida ou na fila. Uma OS com nota, fatura ou comissão não entra num agrupamento: resolva isso antes ou deixe-a de fora." },
      trechos: ["OS-00100 tem nota fiscal emitida ou na fila. Uma OS com nota", "Explique ao dono e proponha deixá-la de fora"],
    },
    {
      linhas: [ordem(ID_100, "OS-00100", { created_at: "2026-09-02T13:00:00+00:00" }), ordem(ID_128, "OS-00128", { vessel_id: "outro-barco" })],
      trechos: ["OS-00128 é de outro cliente ou de outra embarcação"],
    },
    {
      linhas: [ordem(ID_100, "OS-00100", { status: "cancelled", merged_into_id: ID_131 }), ordem(ID_128, "OS-00128"), ordem(ID_131, "OS-00131")],
      trechos: ["OS-00100 já foi agrupada em OS-00131"],
    },
    {
      linhas: [ordem(ID_100, "OS-00100", { status: "cancelled" }), ordem(ID_128, "OS-00128")],
      trechos: ["OS-00100 está cancelada"],
    },
    {
      linhas: [ordem(ID_100, "OS-00100", { travel_cost_total: 80 }), ordem(ID_128, "OS-00128", { ferry_cost: 40 })],
      trechos: ["Mais de uma tem deslocamento ("],
    },
  ];
  for (const c of casos) {
    const { db, ctx } = ambiente(c.linhas, { motivos: c.motivos });
    const r = await executarChamadaDeTool({ name: "agrupar_os", input: { os: ["OS-00100", "OS-00128"] } }, amb(ctx));
    // deno-lint-ignore no-explicit-any
    const res = r.toolResult as any;
    for (const t of c.trechos) assertStringIncludes(String(res.error), t, JSON.stringify(res));
    assertEquals(res.nada_registrado, true, c.trechos[0]);
    assertEquals(pendencias(db), [], c.trechos[0]);
    assertEquals(rpcsDeEscrita(db), [], c.trechos[0]);
  }
});

Deno.test("fronteira: orçamento em agrupar_os aponta agrupar_orcamentos; OS em agrupar_orcamentos aponta agrupar_os", async () => {
  // todos ainda orçamentos
  const orcs = [
    ordem(ID_ORC_100, "ORÇ-00100", { status: "draft", converted_to_os_at: null, quote_status: "draft" }),
    ordem("11111111-1111-4111-8111-111111111101", "ORÇ-00101", { status: "draft", converted_to_os_at: null, quote_status: "draft" }),
  ];
  const a = ambiente(orcs);
  const e1 = await recusado(a.ctx, a.db, "agrupar_os", { os: ["ORÇ-00100", "ORÇ-00101"] });
  assertStringIncludes(e1, "ORÇ-00100, ORÇ-00101 ainda são orçamentos");
  assertStringIncludes(e1, "use agrupar_orcamentos");

  // um orçamento no meio das OS
  const b = ambiente([...osDoGiancarlo(), orcs[0]]);
  const e2 = await recusado(b.ctx, b.db, "agrupar_os", { os: ["OS-00100", "OS-00128", "ORÇ-00100"] });
  assertStringIncludes(e2, "ORÇ-00100 ainda é orçamento (não virou OS): para juntar orçamentos, use agrupar_orcamentos");
  assertStringIncludes(e2, "Sem ela, dá para agrupar OS-00100, OS-00128.");

  // e o contrário: agrupar_orcamentos com OS
  const c = ambiente(osDoGiancarlo());
  const r = await executarChamadaDeTool({ name: "agrupar_orcamentos", input: { orcamentos: ["OS-00100", "OS-00128"] } }, amb(c.ctx));
  // deno-lint-ignore no-explicit-any
  const e3 = String((r.toolResult as any).error);
  assertStringIncludes(e3, "OS-00100 não é mais um orçamento em aberto: já virou OS. Para juntar OS, use agrupar_os");
  assertEquals(pendencias(c.db), []);
});

Deno.test("número que não existe: recusa (sem pendência)", async () => {
  const { db, ctx } = ambiente(osDoGiancarlo());
  const e = await recusado(ctx, db, "agrupar_os", { os: ["OS-00100", "OS-00999"] });
  assertStringIncludes(e, "OS-00999");
});

Deno.test("principal fora da lista recusa sem pendência", async () => {
  const { db, ctx } = ambiente([...osDoGiancarlo(), ordem(ID_131, "OS-00131")]);
  const e = await recusado(ctx, db, "agrupar_os", { os: ["OS-00100", "OS-00128"], principal: "OS-00131" });
  assertStringIncludes(e, "precisa estar entre as OS escolhidas");
});

// ── o "sim" confere o retrato ────────────────────────────────────────────────────────────────

Deno.test("retrato: total ou recebíveis mudaram entre o pedido e o 'sim' → recusa para o dono, sem chamar o banco", async () => {
  const { db, ctx } = ambiente(osDoGiancarlo());
  const p = await pedir(ctx, db, "agrupar_os", { os: ["OS-00100", "OS-00128"] });
  db.tabelas.service_orders.find((l: Linha) => l.id === ID_128).grand_total = 4000;
  // deno-lint-ignore no-explicit-any
  const r = await toolsByName["agrupar_os"].execute(p.payload, ctx) as any;
  assertStringIncludes(semNbsp(r.error), "Nada foi agrupado: o total de OS-00128 mudou (era R$ 3.839,50, agora R$ 4.000,00)");
  assertEquals(NOME_TECNICO.test(r.error), false, r.error);

  db.tabelas.service_orders.find((l: Linha) => l.id === ID_128).grand_total = 3839.5;
  db.tabelas.receivables.push({ id: "r9", service_order_id: ID_100, description: "Saldo", amount: 100, status: "pending" });
  // deno-lint-ignore no-explicit-any
  const r2 = await toolsByName["agrupar_os"].execute(p.payload, ctx) as any;
  assertStringIncludes(semNbsp(r2.error), "os recebíveis das OS mudaram (eram R$ 6.709,00, agora R$ 6.809,00)");
  assertEquals(rpcsDeEscrita(db), []);
});

Deno.test("sem retrato o 'sim' não executa; cargo de quem PEDIU é revalidado", async () => {
  const { db, ctx } = ambiente(osDoGiancarlo());
  // deno-lint-ignore no-explicit-any
  const r = await toolsByName["agrupar_os"].execute({ os: ["OS-00100", "OS-00128"] }, ctx) as any;
  assertStringIncludes(r.error, "Nada foi agrupado: não consegui conferir as OS quando o pedido foi feito");
  // deno-lint-ignore no-explicit-any
  const v = await toolsByName["agrupar_os"].execute({ os: ["OS-00100", "OS-00128"], _solicitante: { user_id: "v1", nome: "V", cargo: "seller" } }, ctx) as any;
  assertStringIncludes(v.error, "administrador ou financeiro");
  assertEquals(rpcsDeEscrita(db), []);
});

Deno.test("dois 'sim' para o mesmo agrupamento: o segundo diz que já está feito, sem gravar de novo", async () => {
  const { db, ctx } = ambiente(osDoGiancarlo());
  const p = await pedir(ctx, db, "agrupar_os", { os: ["OS-00100", "OS-00128"] });
  for (const l of db.tabelas.service_orders) Object.assign(l, { status: "cancelled", merged_into_id: ID_131 });
  db.tabelas.service_orders.push(ordem(ID_131, "OS-00131", { grand_total: 9578.5 }));
  // deno-lint-ignore no-explicit-any
  const r = await toolsByName["agrupar_os"].execute(p.payload, ctx) as any;
  assertEquals(r.ja_feito, true, JSON.stringify(r));
  assertEquals(r.aviso, "Já estava feito: OS-00100, OS-00128 já foram agrupadas em OS-00131; nada novo foi gravado.");
  assertEquals(rpcsDeEscrita(db), []);
});

Deno.test("erro do banco: 'mudaram desde que a tela abriu' vira frase para o dono; regra (22023) passa a frase sem código", async () => {
  const { db, ctx } = ambiente(osDoGiancarlo());
  const p = await pedir(ctx, db, "agrupar_os", { os: ["OS-00100", "OS-00128"] });
  const rpc = db.rpc;
  db.rpc = (nome: string, args: Linha) => nome === "agrupar_os"
    ? Promise.resolve({ data: null, error: { message: "As OS mudaram desde que a tela abriu (soma agora R$ 9.700,00)." } })
    : rpc(nome, args);
  // deno-lint-ignore no-explicit-any
  const r = await toolsByName["agrupar_os"].execute(p.payload, ctx) as any;
  assertEquals(r.error, "Nada foi agrupado: a soma das OS mudou depois do pedido. Peça de novo que eu confiro.");
  db.rpc = (nome: string, args: Linha) => nome === "agrupar_os"
    ? Promise.resolve({ data: null, error: { message: "22023: OS-00128 tem fatura: cancele a fatura antes." } })
    : rpc(nome, args);
  // deno-lint-ignore no-explicit-any
  const r2 = await toolsByName["agrupar_os"].execute(p.payload, ctx) as any;
  assertEquals(r2.error, "OS-00128 tem fatura: cancele a fatura antes.");
});

// ── desagrupar ───────────────────────────────────────────────────────────────────────────────

function ambienteDaAgrupada(opcoes: { ativo?: boolean; tipo?: string; status?: string; agrupadas?: Linha[] } = {}) {
  const ativo = opcoes.ativo ?? true;
  const linhas = [
    ordem(ID_100, "OS-00100", { status: "cancelled", merged_into_id: ativo ? ID_131 : null, cancellation_reason: "Agrupada em OS-00131 (reúne OS-00100, OS-00128)" }),
    ordem(ID_128, "OS-00128", { status: "cancelled", merged_into_id: ativo ? ID_131 : null }),
    ordem(ID_131, "OS-00131", { grand_total: 9578.5, status: opcoes.status ?? "open" }),
  ];
  return ambiente(linhas, {
    tabelas: {
      orcamento_agrupamentos: [{ id: "g1", agrupado_id: ID_131, tipo: opcoes.tipo ?? "os", desfeito_em: ativo ? null : "2026-10-28T15:00:00+00:00" }],
      orcamento_agrupamento_origens: [
        { agrupamento_id: "g1", origem_id: ID_128, numero: "OS-00128", ordem: 2, status_antes: "scheduled", grand_total_antes: 3839.5 },
        { agrupamento_id: "g1", origem_id: ID_100, numero: "OS-00100", ordem: 1, status_antes: "open", grand_total_antes: 5739 },
      ],
    },
    agrupadas: opcoes.agrupadas ?? [{ id: ID_131, numero: "OS-00131", origens: ["OS-00100", "OS-00128"], pode_desagrupar: true, motivo: null }],
  });
}

Deno.test("desagrupar OS: a pendência diz o que volta (situação e total de cada uma) e que o acrescentado não volta; o 'sim' chama desagrupar_os", async () => {
  const { db, ctx } = ambienteDaAgrupada();
  const p = await pedir(ctx, db, "desagrupar_os", { os_agrupada: "OS-00131" });
  assertEquals(p.title, "Desagrupar OS");
  const s = semNbsp(p.summary);
  assertEquals(UUID_NO_TEXTO.test(s), false, s);
  assertStringIncludes(s, "Desagrupar *OS-00131* (R$ 9.578,50):");
  assertStringIncludes(s,
    "Voltam a valer, como estavam antes de agrupar (situação e link do cliente): *OS-00100* (Aberta, R$ 5.739,00), *OS-00128* (Agendada, R$ 3.839,50).");
  assertStringIncludes(s, "voltam cada um para a sua OS de origem");
  assertStringIncludes(s, "OS-00131 fica cancelada como histórico");
  assertStringIncludes(s, "NÃO volta para as originais");

  // deno-lint-ignore no-explicit-any
  const ex = await toolsByName["desagrupar_os"].execute(p.payload, ctx) as any;
  assertEquals(ex.ok, true, JSON.stringify(ex));
  assertEquals(rpcsDeEscrita(db), [["desagrupar_os", { p_agrupado: ID_131, p_autor: "dono-1" }]]);
  const ressalva = ressalvaDoResultado(ex);
  assertEquals(ressalva, " OS-00100, OS-00128 voltaram a valer como estavam; OS-00131 ficou cancelada como histórico. 6 registros ligados voltaram para a sua OS de origem.");
  assertEquals(NOME_TECNICO.test(ressalva), false, ressalva);
});

Deno.test("desagrupar OS pelo número de uma das ORIGINAIS: acha a agrupada e diz isso na confirmação", async () => {
  const { db, ctx } = ambienteDaAgrupada();
  const p = await pedir(ctx, db, "desagrupar_os", { os_agrupada: "OS-00100" });
  assertStringIncludes(p.summary, "OS-00100 está agrupada em OS-00131. Desagrupar *OS-00131*");
  assertEquals(p.payload._retrato.agrupada, ID_131);
});

Deno.test("desagrupar OS: recusas sem pendência — não é agrupada, agrupamento de orçamentos, já começou, leitura diz que não pode", async () => {
  const casos: Array<{ amb: ReturnType<typeof ambienteDaAgrupada>; trecho: string }> = [
    { amb: ambienteDaAgrupada({ ativo: false }), trecho: "OS-00131 não é uma OS agrupada" },
    { amb: ambienteDaAgrupada({ tipo: "orcamento" }), trecho: "use desagrupar_orcamento" },
    { amb: ambienteDaAgrupada({ status: "in_progress" }), trecho: "OS-00131 já começou a ser executada (situação: Em andamento)" },
    {
      amb: ambienteDaAgrupada({ agrupadas: [{ id: ID_131, numero: "OS-00131", pode_desagrupar: false, motivo: "OS-00131 já começou a ser executada (hora apontada): não dá mais para desagrupar. As originais ficam como histórico." }] }),
      trecho: "OS-00131 já começou a ser executada (hora apontada): não dá mais para desagrupar.",
    },
  ];
  for (const c of casos) {
    const e = await recusado(c.amb.ctx, c.amb.db, "desagrupar_os", { os_agrupada: "OS-00131" });
    assertStringIncludes(e, c.trecho);
  }
});

Deno.test("desagrupar_orcamento numa OS agrupada aponta desagrupar_os", async () => {
  const { db, ctx } = ambienteDaAgrupada();
  const r = await executarChamadaDeTool({ name: "desagrupar_orcamento", input: { orcamento: "OS-00131" } }, amb(ctx));
  // deno-lint-ignore no-explicit-any
  assertStringIncludes(String((r.toolResult as any).error), "use desagrupar_os");
  assertEquals(pendencias(db), []);
});

Deno.test("desagrupar OS: mudou depois do pedido → recusa; dois 'sim' → já desfeito; sem retrato não executa", async () => {
  const { db, ctx } = ambienteDaAgrupada();
  const p = await pedir(ctx, db, "desagrupar_os", { os_agrupada: "OS-00131" });
  db.tabelas.service_orders.find((l: Linha) => l.id === ID_131).updated_at = "2026-10-28T18:00:00+00:00";
  // deno-lint-ignore no-explicit-any
  const r = await toolsByName["desagrupar_os"].execute(p.payload, ctx) as any;
  assertEquals(r.error, "Nada foi desfeito: OS-00131 mudou depois do pedido. Peça de novo que eu confiro.");

  db.tabelas.orcamento_agrupamentos[0].desfeito_em = "2026-10-28T19:00:00+00:00";
  // deno-lint-ignore no-explicit-any
  const r2 = await toolsByName["desagrupar_os"].execute(p.payload, ctx) as any;
  assertEquals(r2.aviso, "Já estava desfeito: OS-00131 já tinha sido desagrupada; nada novo foi gravado.");
  // deno-lint-ignore no-explicit-any
  const r3 = await toolsByName["desagrupar_os"].execute({ os_agrupada: "OS-00131" }, ctx) as any;
  assertStringIncludes(r3.error, "Nada foi desfeito: não consegui conferir o agrupamento");
  assertEquals(rpcsDeEscrita(db), []);
});

// ── registro, títulos, autonomia e perfis ────────────────────────────────────────────────────

Deno.test("registro: as três em allTools, títulos em português, escrita nunca autônoma, fora do bloqueio do WhatsApp", () => {
  for (const n of ["listar_os_para_agrupar", "agrupar_os", "desagrupar_os"]) {
    assert(allTools.some((t) => t.name === n), n);
    assertEquals(FORA_DO_WHATSAPP.has(n), false, n);
    assertEquals(tool(n).roles, CARGOS_DO_AGRUPAMENTO, n);
  }
  assertEquals(tituloDaAcao("agrupar_os"), "Agrupar OS em uma só");
  assertEquals(tituloDaAcao("desagrupar_os"), "Desagrupar OS");
  assertEquals(tituloDaAcao("listar_os_para_agrupar"), "Listar OS para agrupar");
  assert(NEVER_AUTONOMOUS.has("agrupar_os"));
  assert(NEVER_AUTONOMOUS.has("desagrupar_os"));
  assertEquals(tool("agrupar_os").risk, "medium");
  assertEquals(tool("desagrupar_os").risk, "medium");
  assertEquals(tool("agrupar_os").gravarSolicitante, true);
  assertEquals(tool("desagrupar_os").gravarSolicitante, true);
  // seção 9 da spec: só as que não começaram
  assertEquals([...STATUS_QUE_AGRUPAM].sort(), ["approved", "awaiting_client", "awaiting_parts", "open", "scheduled"]);
});

Deno.test("resumo do agrupar OS com impedimento: recusa decidida antes da linha 'Pedido por'; leitura que falha também recusa", async () => {
  const { db, ctx } = ambiente(osDoGiancarlo(), { motivos: { [ID_128]: "OS-00128 tem fatura. Uma OS com nota, fatura ou comissão não entra num agrupamento: resolva isso antes ou deixe-a de fora." } });
  const resumo = await buildPendingSummary(ctx.admin, "agrupar_os", { os: ["OS-00100", "OS-00128"] }, { userId: "dono-1" });
  const rec = resumoQueRecusa("agrupar_os", resumo);
  assert(rec, resumo);
  assertStringIncludes(rec.error, "OS-00128 tem fatura. Uma OS com nota");

  db.from = () => {
    throw new Error("conexão caiu");
  };
  const caiu = await buildPendingSummary(ctx.admin, "agrupar_os", { os: ["OS-00100", "OS-00128"] }, { userId: "dono-1" });
  assertStringIncludes(caiu, "⚠️ Não consegui conferir as OS agora (conexão caiu)");
  assert(resumoQueRecusa("agrupar_os", caiu));
});

Deno.test("retrato soma os recebíveis como o banco: cancelado fora, situação nula dentro", async () => {
  const { ctx, db } = ambiente(osDoGiancarlo());
  db.tabelas.receivables.push({ id: "r5", service_order_id: ID_100, description: "Sem situação", amount: 10, paid_amount: 0, status: null });
  const retrato = await retratoDoAgrupamentoDeOS(ctx.admin, { os: ["OS-00100", "OS-00128"] });
  // 2.869,50 + 1.000 + 2.839,50 + 10 (o "Antigo" de 50, cancelado, não passa)
  assertEquals(retrato?.recebiveis, 6719);
});

Deno.test("retrato sem leitura dos recebíveis é null (o 'sim' não executa às cegas)", async () => {
  const { ctx } = ambiente(osDoGiancarlo());
  const from = ctx.admin.from;
  ctx.admin.from = (t: string) => t === "receivables" ? { select: () => ({ in: () => Promise.resolve({ data: null, error: { message: "x" } }) }) } : from(t);
  assertEquals(await retratoDoAgrupamentoDeOS(ctx.admin, { os: ["OS-00100", "OS-00128"] }), null);
});

Deno.test("perfis: no de operação as três; no enxuto do admin nenhuma à vista e as três pela rede — leitura direto, escrita com 'sim'", async () => {
  for (const n of ["listar_os_para_agrupar", "agrupar_os", "desagrupar_os"]) {
    assert(PERFIL_OPERACAO.has(n), n);
    assertEquals(PERFIL_ADMIN.has(n), false, `${n} no perfil enxuto subiria o teto`);
    assertEquals(SO_PELA_REDE.has(n), false, n);
  }
  assertEquals(rodaDiretoPelaRede(tool("listar_os_para_agrupar")), true);
  assertEquals(rodaDiretoPelaRede(tool("agrupar_os")), false);
  assertEquals(rodaDiretoPelaRede(tool("desagrupar_os")), false);

  // Como o Claude Max (erp-mcp) monta o turno do admin no perfil enxuto: só PERFIL_ADMIN + ferramenta_extra à vista.
  const job = ferramentasDoJob("admin", [...PERFIL_ADMIN, NOME_DA_FERRAMENTA_EXTRA], allTools.map((t) => t.name), "whatsapp");
  for (const n of ["listar_os_para_agrupar", "agrupar_os", "desagrupar_os"]) assert(job.alcancaveisPelaRede[n], `${n} fora do alcance da ferramenta_extra`);
  const tecnico = ferramentasDoJob("technician", [...PERFIL_OPERACAO], [], "whatsapp");
  assertEquals(Object.keys(tecnico.toolsByName).filter((n) => n.endsWith("_os") && n.includes("agrupar")), []);

  const { db, ctx } = ambiente(osDoGiancarlo());
  const ambDoAdmin = { ...job, toolCtx: ctx, sessionId: "s1", channel: "whatsapp" as const };
  const lida = await executarChamadaDeTool({
    name: NOME_DA_FERRAMENTA_EXTRA, input: { nome: "listar_os_para_agrupar", argumentos: { embarcacao_id: BARCO } },
  }, ambDoAdmin);
  // deno-lint-ignore no-explicit-any
  assertEquals((lida.toolResult as any).os?.length, 2, JSON.stringify(lida.toolResult));
  const ok = await executarChamadaDeTool({
    name: NOME_DA_FERRAMENTA_EXTRA, input: { nome: "agrupar_os", argumentos: { os: ["OS-00100", "OS-00128"] } },
  }, ambDoAdmin);
  // deno-lint-ignore no-explicit-any
  assertEquals((ok.toolResult as any).pending, true, JSON.stringify(ok.toolResult));
  assertEquals(pendencias(db).length, 1);
  assertEquals(pendencias(db)[0].action_name, "agrupar_os");
});

// ── rótulos de origem agrupada (listagem e envio ao cliente) ─────────────────────────────────

Deno.test("origem de OS agrupada: 'Agrupada em OS-…' é OS agrupada; a de orçamento segue igual", () => {
  const os = { status: "cancelled", cancellation_reason: "Agrupada em OS-00131 (reúne OS-00100, OS-00128)" };
  assertEquals(agrupadoEm(os), "OS-00131");
  assertEquals(ehOsAgrupada(os), true);
  const orc = { status: "cancelled", cancellation_reason: "Agrupado em ORÇ-00121 (reúne ORÇ-00078, ORÇ-00120)" };
  assertEquals(agrupadoEm(orc), "ORÇ-00121");
  assertEquals(ehOsAgrupada(orc), false);
  assertEquals(ehOsAgrupada({ status: "cancelled", cancellation_reason: "cliente desistiu" }), false);
  assertEquals(agrupadoEm({ status: "cancelled", cancellation_reason: "Agrupada em OS-00131." }), "OS-00131");

  const f = frasesDaOrdemCancelada({ service_order_number: "OS-00100", ...os });
  assertEquals(f.aviso, "⚠️ OS-00100 foi agrupada em OS-00131 — o envio será recusado; mande a OS-00131.");
  assertEquals(f.erro, "OS-00100 foi agrupada em OS-00131 e não vale mais sozinha: mande a OS-00131 ao cliente.");
});

Deno.test("list_service_orders: origem de OS agrupada vem como 'OS agrupada', com agrupado_em", async () => {
  const linhas = [
    { id: ID_100, service_order_number: "OS-00100", status: "cancelled", cancellation_reason: "Agrupada em OS-00131 (reúne OS-00100, OS-00128)", grand_total: 1, clients: { name: "G" }, vessels: { name: "V" } },
    { id: "x", service_order_number: "ORÇ-00078", status: "cancelled", cancellation_reason: "Agrupado em ORÇ-00121 (reúne ORÇ-00078)", grand_total: 1, clients: { name: "G" }, vessels: { name: "V" } },
  ];
  // deno-lint-ignore no-explicit-any
  const q: any = { select: () => q, order: () => q, limit: () => q, eq: () => q, neq: () => q, then: (ok: any) => Promise.resolve({ data: linhas, error: null, count: 2 }).then(ok) };
  // deno-lint-ignore no-explicit-any
  const r = await toolsByName["list_service_orders"].execute({}, { sb: { from: () => q }, admin: { from: () => q } } as any) as any;
  // deno-lint-ignore no-explicit-any
  const porNumero = Object.fromEntries((r.results as any[]).map((o) => [o.numero, o]));
  assertEquals(porNumero["OS-00100"].tipo, "OS agrupada");
  assertEquals(porNumero["OS-00100"].agrupado_em, "OS-00131");
  assertEquals(porNumero["ORÇ-00078"].tipo, "Orçamento agrupado");
});
