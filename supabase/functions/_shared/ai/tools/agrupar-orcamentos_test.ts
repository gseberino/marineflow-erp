// Agrupar orçamentos pelo assistente (15/10/2026). O pedido do dono que guia os testes:
//   "Agrupe os 3 últimos orçamentos do Rodrigo, do motorhome VW Delivery."
// Os 3 últimos dele em produção (15/10/2026): ORÇ-00120 (Em elaboração), ORÇ-00096 (Reprovado em 22/09) e
// ORÇ-00078 (Em elaboração). O assistente tem de PERGUNTAR sobre o ORÇ-00096 (do que se trata, o total, desde
// quando, se ele entra) — nada de pendência; "entra" vira UMA confirmação que mostra a saída de Reprovado, e
// ele só sai de Reprovado no "sim", junto com o agrupamento; "fica de fora" vira a confirmação sem ele.
// Rodar com:
//   deno test --allow-all supabase/functions/_shared/ai/tools/agrupar-orcamentos_test.ts
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  agruparOrcamentosTools, CARGOS_DO_AGRUPAMENTO, perguntaDoReprovado, referenciasDosOrcamentos, retratoDoAgrupamento,
  validarPedidoDeAgrupar,
} from "./agrupar-orcamentos.ts";
import { agrupadoEm } from "./service-orders.ts";
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

const BARCO = "57bfa77c-872b-43e0-b9b2-18b42434ff08";
const CLIENTE = "d2e26251-8bde-4432-ae7f-de7053ad1309";
const ID_120 = "11111111-1111-4111-8111-111111111120";
const ID_096 = "11111111-1111-4111-8111-111111111096";
const ID_078 = "11111111-1111-4111-8111-111111111078";
const ID_121 = "11111111-1111-4111-8111-111111111121";

type Linha = Record<string, any>;

function orcamento(id: string, numero: string, extra: Linha = {}): Linha {
  return {
    id, service_order_number: numero, status: "draft", quote_status: "draft", grand_total: 0,
    created_at: "2026-10-15T12:00:00+00:00", updated_at: "2026-10-15T12:00:00+00:00",
    client_id: CLIENTE, vessel_id: BARCO, merged_into_id: null, converted_to_os_at: null, share_token: "tok",
    travel_cost_total: 0, travel_distance_km: 0, travel_hours: 0, ferry_cost: 0, commission_rate: 0,
    commissioned_person: null, payment_conditions: null, payment_condition_preset_id: null, discount_amount: 0, tax_amount: 0,
    ...extra,
  };
}

/** Os 3 últimos do Rodrigo (o ORÇ-00096 reprovado). */
function orcamentosDoRodrigo(): Linha[] {
  return [
    orcamento(ID_120, "ORÇ-00120", { grand_total: 1455.51, created_at: "2026-10-15T13:00:00+00:00", updated_at: "2026-10-15T13:05:00+00:00" }),
    orcamento(ID_096, "ORÇ-00096", {
      grand_total: 628.9, quote_status: "rejected", created_at: "2026-09-11T14:00:00+00:00", updated_at: "2026-10-15T18:07:00+00:00",
      problem_description: "Atendimento emergencial a bordo",
    }),
    orcamento(ID_078, "ORÇ-00078", {
      grand_total: 3693.29, created_at: "2026-08-13T15:00:00+00:00", updated_at: "2026-08-20T09:00:00+00:00", commission_rate: 3,
      payment_condition_preset_id: "pc-1",
    }),
  ];
}

const SITUACAO: Record<string, string> = { draft: "Em elaboração", rejected: "Reprovado", approved: "Aprovado", awaiting_deposit: "Aguardando sinal" };

/** A resposta de orcamentos_para_agrupar para as linhas dadas (o que o banco diria), do mais novo para o mais antigo. */
function leituraDoBanco(linhas: Linha[], motivos: Record<string, string> = {}, impedimentos: Record<string, string> = {}) {
  const abertos = linhas.filter((l) => l.status === "draft" && !l.merged_into_id && !l.converted_to_os_at)
    .sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)));
  return {
    embarcacao: { id: BARCO, nome: "MH Overlander - VW Delivery" },
    cliente: { id: CLIENTE, nome: "Rodrigo" },
    orcamentos: abertos.map((l) => ({
      id: l.id, numero: l.service_order_number, quote_status: l.quote_status, criado_em: l.created_at,
      data: new Date(l.created_at).toLocaleDateString("pt-BR", { timeZone: "America/Sao_Paulo" }),
      total: l.grand_total, situacao: SITUACAO[l.quote_status] ?? l.quote_status,
      reprovado: l.quote_status === "rejected",
      reprovado_em: l.quote_status === "rejected" ? "2026-09-22T13:00:00+00:00" : null,
      elegivel: l.quote_status !== "rejected" && !motivos[l.id],
      motivo: l.quote_status === "rejected" ? "reprovado pelo cliente (desistência)" : motivos[l.id] ?? null,
      impedimento_se_voltar: l.quote_status === "rejected" ? impedimentos[l.id] ?? null : null,
      resumo: l.problem_description ?? null,
      condicao_pagamento: l.payment_condition_preset_id ? "50% mão de obra + 100% materiais antecipados" : null,
    })),
    fora_da_lista: [] as Linha[],
    agrupados_ativos: [] as Linha[],
  };
}

function bancoFalso(tabelas: Record<string, Linha[]>, rpcs: Record<string, (p: any) => { data?: unknown; error?: { message: string } }> = {}) {
  const chamadas = { rpc: [] as [string, any][], insert: [] as [string, any][] };
  const db: any = {
    chamadas,
    tabelas,
    rpc(nome: string, p: any) {
      chamadas.rpc.push([nome, p]);
      const r = rpcs[nome]?.(p) ?? {};
      return Promise.resolve({ data: r.data ?? null, error: r.error ?? null });
    },
    from(tabela: string) {
      const filtros: Array<(l: Linha) => boolean> = [];
      const linhas = () => (tabelas[tabela] ?? []).filter((l) => filtros.every((f) => f(l)));
      const q: any = {
        select: () => q, order: () => q, limit: () => q,
        eq: (c: string, v: unknown) => (filtros.push((l) => l[c] === v), q),
        neq: (c: string, v: unknown) => (filtros.push((l) => l[c] !== v), q),
        in: (c: string, vs: unknown[]) => (filtros.push((l) => vs.includes(l[c])), q),
        is: (c: string, v: unknown) => (filtros.push((l) => (l[c] ?? null) === v), q),
        maybeSingle: () => Promise.resolve({ data: linhas()[0] ?? null, error: null }),
        single: () => Promise.resolve({ data: linhas()[0] ?? null, error: null }),
        then: (ok: any, ko: any) => Promise.resolve({ data: linhas(), error: null }).then(ok, ko),
        insert: (v: Linha) => {
          chamadas.insert.push([tabela, v]);
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
  impedimentos?: Record<string, string>;
  tabelas?: Record<string, Linha[]>;
  agrupados?: Linha[];
}

function ambiente(linhas: Linha[], extra: Extra = {}) {
  const tabelas: Record<string, Linha[]> = {
    service_orders: linhas,
    app_users: [{ id: "dono-1", full_name: "Gustavo" }],
    ...(extra.tabelas ?? {}),
  };
  // os números na ordem dos ids recebidos (a do banco: mais antigo primeiro)
  const numeros = (ids: string[]) => ids.map((id) => linhas.find((l) => l.id === id)?.service_order_number);
  const resultadoDoAgrupar = (p: any, reabertos: string[] = []) => ({
    data: {
      service_order_id: ID_121, numero: "ORÇ-00121", principal: "ORÇ-00078", total_geral: p.p_total_esperado, comissao: 154.46,
      origens: numeros(p.p_orcamentos), servicos: 4, pecas: 6, envios_cancelados: 0, ...(reabertos.length ? { reabertos } : {}),
    },
  });
  const db = bancoFalso(tabelas, {
    // a leitura é feita na hora de cada chamada: reflete o que o teste mexeu nas linhas
    orcamentos_para_agrupar: () => ({
      data: { ...leituraDoBanco(tabelas.service_orders, extra.motivos, extra.impedimentos), agrupados_ativos: extra.agrupados ?? [] },
    }),
    agrupar_orcamentos: (p) => resultadoDoAgrupar(p),
    agrupar_orcamentos_reabrindo: (p) => resultadoDoAgrupar(p, numeros(p.p_reabrir) as string[]),
    desagrupar_orcamentos: () => ({ data: { agrupado: "ORÇ-00121", origens: ["ORÇ-00078", "ORÇ-00120"], envios_cancelados: 0 } }),
  });
  const ctx = { sb: db, admin: db, userId: "dono-1", userRole: "admin" as const, jwt: "", appOrigin: "", settings: { app_public_url: "https://app.exemplo" } };
  return { db, ctx };
}

const tool = (nome: string) => agruparOrcamentosTools.find((t) => t.name === nome)!;
const amb = (ctx: any) => ({ toolsByName: toolsByName, alcancaveisPelaRede: {}, toolCtx: ctx, sessionId: "s1", channel: "whatsapp" as const });
const pendencias = (db: any) => db.chamadas.insert.filter(([t]: [string]) => t === "ai_operator_pending_actions").map(([, v]: [string, Linha]) => v);
const rpcsDeEscrita = (db: any) =>
  db.chamadas.rpc.filter(([n]: [string]) => n === "agrupar_orcamentos" || n === "agrupar_orcamentos_reabrindo" || n === "desagrupar_orcamentos");
/** Pede pela conversa e devolve a pendência criada (ou falha o teste). */
async function pedir(ctx: any, db: any, nome: string, input: Record<string, unknown>): Promise<Linha> {
  const r = await executarChamadaDeTool({ name: nome, input }, amb(ctx));
  assertEquals((r.toolResult as any).pending, true, JSON.stringify(r.toolResult));
  return pendencias(db).at(-1);
}

// ── listar ───────────────────────────────────────────────────────────────────────────────────

Deno.test("listar: chama a leitura com quem pede (p_autor) e a instrução conta os reprovados e não reabre antes do 'sim'", async () => {
  const { db, ctx } = ambiente(orcamentosDoRodrigo());
  const r = await tool("listar_orcamentos_para_agrupar").execute({ embarcacao_id: BARCO, cliente_id: CLIENTE }, ctx) as any;
  assertEquals(db.chamadas.rpc, [["orcamentos_para_agrupar", { p_vessel_id: BARCO, p_client_id: CLIENTE, p_autor: "dono-1" }]]);
  assertEquals(r.orcamentos.length, 3);
  assertStringIncludes(r.instrucao, "contando os reprovados");
  assertStringIncludes(r.instrucao, "voltar_para_em_elaboracao");
  assertStringIncludes(r.instrucao, "não pergunte antes");
  assertStringIncludes(r.instrucao, "fora_da_lista");
  assertEquals(r.instrucao.includes("update_quote_status"), false, "reabrir antes do 'sim' mudaria a situação sem confirmação");
});

Deno.test("listar: sem id da embarcação não chama o banco; técnico não lista", async () => {
  const { db, ctx } = ambiente([]);
  const t = tool("listar_orcamentos_para_agrupar");
  assertStringIncludes((await t.execute({ embarcacao_id: "VW Delivery" }, ctx) as any).error, "search_vessels");
  assertStringIncludes((await t.execute({ embarcacao_id: BARCO }, { ...ctx, userRole: "technician" }) as any).error, "administrador ou financeiro");
  assertEquals(db.chamadas.rpc.length, 0);
  assertEquals(t.roles, CARGOS_DO_AGRUPAMENTO);
  assertEquals(t.risk, "low");
});

Deno.test("listar: erro do banco vira a frase do banco, sem prefixo técnico", async () => {
  const { ctx } = ambiente([]);
  ctx.sb.rpc = () => Promise.resolve({ data: null, error: { message: "42501: Só administrador ou financeiro pode agrupar orçamentos." } });
  const r = await tool("listar_orcamentos_para_agrupar").execute({ embarcacao_id: BARCO }, ctx) as any;
  assertEquals(r.error, "Só administrador ou financeiro pode agrupar orçamentos.");
});

// ── pré-validação ────────────────────────────────────────────────────────────────────────────

Deno.test("preValidar (sem banco): 2 a 10, só número/id ('último' não), sem repetido, sem técnico", () => {
  const admin = { userRole: "admin" } as const;
  assertStringIncludes(validarPedidoDeAgrupar({ orcamentos: ["ORÇ-00120"] }, admin)!.error, "pelo menos 2");
  assertStringIncludes(validarPedidoDeAgrupar({ orcamentos: Array.from({ length: 11 }, (_, i) => `ORÇ-${i}`) }, admin)!.error, "no máximo 10");
  assertStringIncludes(validarPedidoDeAgrupar({ orcamentos: ["ORÇ-00120", "orc 120"] }, admin)!.error, "duas vezes");
  assertStringIncludes(validarPedidoDeAgrupar({ orcamentos: ["ORÇ-00120", "ORÇ-00078"] }, { userRole: "technician" })!.error, "administrador");
  assertStringIncludes(validarPedidoDeAgrupar({ orcamentos: ["ORÇ-00120", "ORÇ-00078"] }, { userRole: "seller" })!.error, "administrador");
  assertEquals(validarPedidoDeAgrupar({ orcamentos: ["ORÇ-00120", "ORÇ-00078"] }, { userRole: "financial" }), null);
  // "último" resolveria para o documento mais recente de QUALQUER cliente
  assertStringIncludes(validarPedidoDeAgrupar({ orcamentos: ["último", "ORÇ-00078"] }, admin)!.error, "não é número de orçamento");
  assertStringIncludes(validarPedidoDeAgrupar({ orcamentos: ["ORÇ-00120", "ORÇ-00078"], principal: "o mais antigo" }, admin)!.error,
    "não é número de orçamento");
  assertStringIncludes(validarPedidoDeAgrupar({ orcamentos: ["ORÇ-00120", "ORÇ-00096"], voltar_para_em_elaboracao: ["o reprovado"] }, admin)!.error,
    "não é número de orçamento");
  assertEquals(validarPedidoDeAgrupar({ orcamentos: ["120", ID_078], principal: "orc 78", voltar_para_em_elaboracao: "ORÇ-00120" }, admin), null);
  // texto com vírgula também serve
  assertEquals(referenciasDosOrcamentos("ORÇ-00120, ORÇ-00078"), ["ORÇ-00120", "ORÇ-00078"]);
});

Deno.test("número que existe como ORÇ e como OS: recusa perguntando qual (sem pendência)", async () => {
  const { db, ctx } = ambiente([...orcamentosDoRodrigo(), orcamento("22222222-2222-4222-8222-222222222120", "OS-00120", { status: "open" })]);
  const r = await executarChamadaDeTool({ name: "agrupar_orcamentos", input: { orcamentos: ["120", "ORÇ-00078"] } }, amb(ctx));
  assertStringIncludes(String((r.toolResult as any).error), "Qual deles?");
  assertEquals(pendencias(db), []);
});

// ── o pedido do dono: os 3 últimos, com um reprovado ─────────────────────────────────────────

Deno.test("'os 3 últimos do Rodrigo' com o ORÇ-00096 reprovado: NÃO vira pendência — volta a pergunta (do que se trata, total, desde quando, entra?)", async () => {
  const { db, ctx } = ambiente(orcamentosDoRodrigo());
  const r = await executarChamadaDeTool(
    { name: "agrupar_orcamentos", input: { orcamentos: ["ORÇ-00120", "ORÇ-00096", "ORÇ-00078"] } },
    amb(ctx),
  );
  const res = r.toolResult as any;
  assertEquals(pendencias(db), [], "nada vai para o sino nem pede 'sim'");
  assertEquals(r.proposal, undefined);
  assertEquals(res.nada_registrado, true);
  const e = semNbsp(res.error);
  assertStringIncludes(e, "ORÇ-00096 (Atendimento emergencial a bordo, R$ 628,90) está reprovado desde 22/09");
  assertStringIncludes(e, "pergunte ao dono se ele entra no agrupamento");
  assertStringIncludes(e, "voltar_para_em_elaboracao");
  assertStringIncludes(e, "Resposta que não escolhe");
  assertStringIncludes(e, "dá para agrupar ORÇ-00078, ORÇ-00120");
  assertEquals(e.includes("update_quote_status"), false);
  assertEquals(rpcsDeEscrita(db), [], "a função de agrupar nem foi chamada");
  // a leitura foi em nome de quem pede, com os escolhidos em p_incluir (conferidos mesmo fora dos 20)
  const leitura = db.chamadas.rpc.find(([n]: [string]) => n === "orcamentos_para_agrupar")?.[1];
  assertEquals(leitura.p_autor, "dono-1");
  assertEquals([...leitura.p_incluir].sort(), [ID_078, ID_096, ID_120]);
});

Deno.test("a pergunta do reprovado: do que se trata, total, desde quando; sem data registrada diz que não foi registrada", () => {
  assertEquals(semNbsp(perguntaDoReprovado({ numero: "ORÇ-00096", resumo: "Troca da bomba", total: 628.9, reprovadoEm: "2026-09-22T13:00:00+00:00" })),
    "ORÇ-00096 (Troca da bomba, R$ 628,90) está reprovado desde 22/09. Antes de gravar qualquer coisa, pergunte ao dono se ele " +
      "entra no agrupamento (o cliente voltou atrás?), dizendo do que se trata. Entra: chame agrupar_orcamentos de novo com ORÇ-00096 " +
      "também em voltar_para_em_elaboracao — ele só sai de Reprovado no \"sim\" da confirmação. Fica de fora: agrupe só os outros. " +
      "Resposta que não escolhe (\"sim\", \"ok\"): pergunte de novo.");
  assertStringIncludes(perguntaDoReprovado({ numero: "ORÇ-00072", reprovadoEm: null }), "ORÇ-00072 está reprovado (a data da reprovação não foi registrada)");
});

Deno.test("'entra': a confirmação mostra 'Reprovado → volta para Em elaboração e entra' e nada muda antes do 'sim'; o 'sim' reabre e agrupa juntos", async () => {
  const { db, ctx } = ambiente(orcamentosDoRodrigo());
  const p = await pedir(ctx, db, "agrupar_orcamentos", {
    orcamentos: ["ORÇ-00120", "ORÇ-00096", "ORÇ-00078"], voltar_para_em_elaboracao: ["ORÇ-00096"],
  });
  const s = semNbsp(p.summary);
  assertEquals(UUID_NO_TEXTO.test(s), false, s);
  assertStringIncludes(s, "Agrupar *3* orçamentos de *Rodrigo · MH Overlander - VW Delivery* em um orçamento NOVO (Em elaboração):");
  assertStringIncludes(s,
    "- ORÇ-00078 · 13/08/2026 · Em elaboração · R$ 3.693,29 ← principal\n" +
      "- ORÇ-00096 · 11/09/2026 · Reprovado → volta para Em elaboração e entra · R$ 628,90\n" +
      "- ORÇ-00120 · 15/10/2026 · Em elaboração · R$ 1.455,51");
  assertStringIncludes(s, "Total previsto: *R$ 5.777,70*");
  assertStringIncludes(s, "ORÇ-00096 sai de Reprovado só com este \"sim\"; se desagrupar depois, volta como Reprovado.");
  assertEquals(p.payload._retrato.reabrir, [ID_096]);
  assertEquals(rpcsDeEscrita(db), []);
  assertEquals(db.tabelas.service_orders.find((l: Linha) => l.id === ID_096).quote_status, "rejected", "nada mudou antes do 'sim'");

  const r = await toolsByName["agrupar_orcamentos"].execute(p.payload, ctx) as any;
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(rpcsDeEscrita(db), [["agrupar_orcamentos_reabrindo", {
    p_orcamentos: [ID_078, ID_096, ID_120], p_base: ID_078, p_total_esperado: 5777.7, p_autor: "dono-1", p_reabrir: [ID_096],
  }]]);
  assertEquals(r.reabertos, ["ORÇ-00096"]);
  assertStringIncludes(semNbsp(r.aviso), "Novo orçamento ORÇ-00121, com ORÇ-00078, ORÇ-00096, ORÇ-00120 — R$ 5.777,70.");
  assertStringIncludes(r.aviso, "ORÇ-00096 saiu de Reprovado e entrou.");
});

Deno.test("reprovado que nem voltando pode entrar (impedimento_se_voltar): recusa sem oferecer incluí-lo, mesmo com voltar_para_em_elaboracao", async () => {
  const { db, ctx } = ambiente(orcamentosDoRodrigo(), { impedimentos: { [ID_096]: "assinado pelo cliente" } });
  for (const input of [
    { orcamentos: ["ORÇ-00120", "ORÇ-00096", "ORÇ-00078"] },
    { orcamentos: ["ORÇ-00120", "ORÇ-00096", "ORÇ-00078"], voltar_para_em_elaboracao: ["ORÇ-00096"] },
  ]) {
    const r = await executarChamadaDeTool({ name: "agrupar_orcamentos", input }, amb(ctx));
    const e = String((r.toolResult as any).error);
    assertStringIncludes(e, "ORÇ-00096 está reprovado e, mesmo voltando para Em elaboração, não pode entrar: assinado pelo cliente");
    assertStringIncludes(e, "não ofereça incluí-lo");
    assertStringIncludes(e, "dá para agrupar ORÇ-00078, ORÇ-00120");
  }
  assertEquals(pendencias(db), []);
});

Deno.test("'fica de fora' (ou o modelo pulou o reprovado): a confirmação mostra o ORÇ-00096 como 'Fica de fora'", async () => {
  const { db, ctx } = ambiente(orcamentosDoRodrigo());
  const p = await pedir(ctx, db, "agrupar_orcamentos", { orcamentos: ["ORÇ-00120", "ORÇ-00078"] });
  const s = semNbsp(p.summary);
  assertStringIncludes(s, "- ORÇ-00120 · 15/10/2026 · Em elaboração · R$ 1.455,51\n- Fica de fora: ORÇ-00096 · 11/09/2026 · Reprovado · R$ 628,90");
  assertStringIncludes(s, "Total previsto: *R$ 5.148,80*");
  assertEquals(rpcsDeEscrita(db), []);
});

// ── sem reprovado: pendência com a lista resolvida e o "sim" chama o banco ───────────────────

Deno.test("sem reprovado: a pendência mostra número, data, situação, total, principal e avisos — sem uuid", async () => {
  const linhas = orcamentosDoRodrigo().filter((l) => l.id !== ID_096);
  const { db, ctx } = ambiente(linhas);
  const p = await pedir(ctx, db, "agrupar_orcamentos", { orcamentos: ["ORÇ-00120", "ORÇ-00078"] });
  assertEquals(p.title, "Agrupar orçamentos em um só");
  assertEquals(p.action_name, "agrupar_orcamentos");
  const s = semNbsp(p.summary);
  assertEquals(UUID_NO_TEXTO.test(s), false, s);
  assertStringIncludes(s, "Agrupar *2* orçamentos de *Rodrigo · MH Overlander - VW Delivery*");
  // na ordem do banco (mais antigo primeiro), o principal marcado
  assertStringIncludes(s, "- ORÇ-00078 · 13/08/2026 · Em elaboração · R$ 3.693,29 ← principal\n- ORÇ-00120 · 15/10/2026 · Em elaboração · R$ 1.455,51");
  assertEquals(s.includes("Fica de fora"), false);
  assertStringIncludes(s, "Total previsto: *R$ 5.148,80*");
  assertStringIncludes(s,
    "Principal: *ORÇ-00078* — dele vêm a condição de pagamento (50% mão de obra + 100% materiais antecipados), o contato e a " +
      "comissão (3%, recalculada sobre o total novo).");
  assertStringIncludes(s, "Preços mantidos");
  assertStringIncludes(s, "Comissões diferentes");
  assertStringIncludes(s, "cancelados como histórico, com o link do cliente desligado");
  assertStringIncludes(s, "Dá para desagrupar enquanto o novo não virar OS");
  assertStringIncludes(s, "Pedido por: *Gustavo* (Administrador)");
  // o retrato e quem pediu vão no payload; nada foi gravado ainda
  assertEquals(p.payload._retrato.principal, ID_078);
  assertEquals(p.payload._retrato.total, 5148.8);
  assertEquals(p.payload._solicitante.cargo, "admin");
  assertEquals(rpcsDeEscrita(db), []);
});

Deno.test("origem já aprovada pelo cliente: a confirmação avisa que o novo precisa de nova aprovação", async () => {
  const linhas = orcamentosDoRodrigo().filter((l) => l.id !== ID_096);
  linhas[0].quote_status = "approved";
  const { db, ctx } = ambiente(linhas);
  const p = await pedir(ctx, db, "agrupar_orcamentos", { orcamentos: ["ORÇ-00120", "ORÇ-00078"] });
  assertStringIncludes(p.summary, "- ORÇ-00120 (Aprovado) já tinha o aceite do cliente: o orçamento novo nasce Em elaboração e precisa ser aprovado de novo.");
});

Deno.test("o 'sim': chama agrupar_orcamentos com os ids, o principal, a soma do retrato e p_autor; o aviso (que o dono lê) traz o número novo", async () => {
  const linhas = orcamentosDoRodrigo().filter((l) => l.id !== ID_096);
  const { db, ctx } = ambiente(linhas);
  const p = await pedir(ctx, db, "agrupar_orcamentos", { orcamentos: ["ORÇ-00120", "ORÇ-00078"] });
  const r = await toolsByName["agrupar_orcamentos"].execute(p.payload, ctx) as any;
  assertEquals(r.ok, true, JSON.stringify(r));
  const chamadas = rpcsDeEscrita(db);
  assertEquals(chamadas.length, 1);
  assertEquals(chamadas[0], ["agrupar_orcamentos", { p_orcamentos: [ID_078, ID_120], p_base: ID_078, p_total_esperado: 5148.8, p_autor: "dono-1" }]);
  assertEquals(r.numero, "ORÇ-00121");
  assertEquals(r.origens, ["ORÇ-00078", "ORÇ-00120"]);
  assertEquals(r.link_interno, `https://app.exemplo/service-orders/${ID_121}`);
  // o "✅ … executado." do sino e do WhatsApp mostra a ressalva (aviso): é ali que o dono lê o número novo
  const ressalva = semNbsp(ressalvaDoResultado(r));
  assertStringIncludes(ressalva, "Novo orçamento ORÇ-00121, com ORÇ-00078, ORÇ-00120 — R$ 5.148,80.");
  assertEquals(NOME_TECNICO.test(ressalva), false, ressalva);
  assertStringIncludes(r.message, "é só pedir para desagrupar");
  assertEquals(NOME_TECNICO.test(r.message), false, r.message);
});

Deno.test("principal escolhido pelo número vai em p_base; principal fora da lista recusa sem pendência", async () => {
  const linhas = orcamentosDoRodrigo().filter((l) => l.id !== ID_096);
  const { db, ctx } = ambiente(linhas);
  const p = await pedir(ctx, db, "agrupar_orcamentos", { orcamentos: ["ORÇ-00120", "ORÇ-00078"], principal: "ORÇ-00120" });
  const r = await toolsByName["agrupar_orcamentos"].execute(p.payload, ctx) as any;
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(rpcsDeEscrita(db)[0][1].p_base, ID_120);

  const fora = ambiente([...linhas, orcamento(ID_096, "ORÇ-00096")]);
  const res = await executarChamadaDeTool(
    { name: "agrupar_orcamentos", input: { orcamentos: ["ORÇ-00120", "ORÇ-00078"], principal: "ORÇ-00096" } }, amb(fora.ctx));
  assertStringIncludes((res.toolResult as any).error, "precisa estar entre os orçamentos escolhidos");
  assertEquals(pendencias(fora.db), []);
});

Deno.test("retrato: algo mudou entre o pedido e o 'sim' → recusa para o dono (sem nome de ferramenta), sem chamar o banco", async () => {
  const linhas = orcamentosDoRodrigo().filter((l) => l.id !== ID_096);
  const { db, ctx } = ambiente(linhas);
  const p = await pedir(ctx, db, "agrupar_orcamentos", { orcamentos: ["ORÇ-00120", "ORÇ-00078"] });
  // alguém mexeu no ORÇ-00078 depois do pedido
  db.tabelas.service_orders.find((l: Linha) => l.id === ID_078).grand_total = 3800;
  const r = await toolsByName["agrupar_orcamentos"].execute(p.payload, ctx) as any;
  assertStringIncludes(r.error, "Nada foi agrupado");
  assertStringIncludes(semNbsp(r.error), "o total de ORÇ-00078 mudou (era R$ 3.693,29, agora R$ 3.800,00)");
  assertStringIncludes(r.error, "Peça de novo que eu confiro");
  assertEquals(NOME_TECNICO.test(r.error), false, r.error);
  assertEquals(rpcsDeEscrita(db), []);

  // e se virou reprovado depois do pedido, também recusa (mudou de situação)
  db.tabelas.service_orders.find((l: Linha) => l.id === ID_078).grand_total = 3693.29;
  db.tabelas.service_orders.find((l: Linha) => l.id === ID_120).quote_status = "rejected";
  const r2 = await toolsByName["agrupar_orcamentos"].execute(p.payload, ctx) as any;
  assertStringIncludes(r2.error, "ORÇ-00120 mudou de situação");
  assertEquals(rpcsDeEscrita(db), []);
});

Deno.test("sem retrato (não deu para tirar quando o pedido nasceu): o 'sim' não executa", async () => {
  const { db, ctx } = ambiente(orcamentosDoRodrigo().filter((l) => l.id !== ID_096));
  const r = await toolsByName["agrupar_orcamentos"].execute({ orcamentos: ["ORÇ-00120", "ORÇ-00078"] }, ctx) as any;
  assertStringIncludes(r.error, "Nada foi agrupado: não consegui conferir os orçamentos quando o pedido foi feito");
  assertEquals(rpcsDeEscrita(db), []);
});

Deno.test("execução com reprovado sem 'entra': recusa para o dono, sem nome de ferramenta e sem chamar o banco", async () => {
  const { db, ctx } = ambiente(orcamentosDoRodrigo());
  const args = { orcamentos: ["ORÇ-00120", "ORÇ-00096"] };
  const retrato = await retratoDoAgrupamento(ctx.admin, args);
  const r = await toolsByName["agrupar_orcamentos"].execute({ ...args, _retrato: retrato }, ctx) as any;
  assertEquals(r.error, "Nada foi agrupado: ORÇ-00096 está reprovado. Diga se ele entra ou fica de fora e eu refaço o pedido.");
  assertEquals(rpcsDeEscrita(db), []);
});

Deno.test("dois 'sim' para o mesmo agrupamento: o segundo diz que já está feito, sem gravar de novo", async () => {
  const linhas = orcamentosDoRodrigo().filter((l) => l.id !== ID_096);
  const { db, ctx } = ambiente(linhas);
  const p = await pedir(ctx, db, "agrupar_orcamentos", { orcamentos: ["ORÇ-00120", "ORÇ-00078"] });
  // o primeiro "sim" (por outra pendência) já agrupou
  for (const l of db.tabelas.service_orders) Object.assign(l, { status: "cancelled", merged_into_id: ID_121 });
  db.tabelas.service_orders.push(orcamento(ID_121, "ORÇ-00121", { grand_total: 5148.8 }));
  const r = await toolsByName["agrupar_orcamentos"].execute(p.payload, ctx) as any;
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(r.ja_feito, true);
  assertEquals(r.aviso, "Já estava feito: ORÇ-00078, ORÇ-00120 já foram agrupados em ORÇ-00121; nada novo foi gravado.");
  assertEquals(rpcsDeEscrita(db), []);
});

Deno.test("erro do banco 'a tela abriu' vira frase para o dono", async () => {
  const linhas = orcamentosDoRodrigo().filter((l) => l.id !== ID_096);
  const { db, ctx } = ambiente(linhas);
  const p = await pedir(ctx, db, "agrupar_orcamentos", { orcamentos: ["ORÇ-00120", "ORÇ-00078"] });
  const rpc = db.rpc;
  db.rpc = (nome: string, args: any) => nome === "agrupar_orcamentos"
    ? Promise.resolve({ data: null, error: { message: "Os orçamentos mudaram desde que a tela abriu (soma agora R$ 5.200,00). Feche e abra o agrupamento de novo." } })
    : rpc(nome, args);
  const r = await toolsByName["agrupar_orcamentos"].execute(p.payload, ctx) as any;
  assertEquals(r.error, "Nada foi agrupado: a soma dos orçamentos mudou depois do pedido. Peça de novo que eu confiro.");
});

Deno.test("o 'sim' revalida o cargo de quem PEDIU: pedido do vendedor aprovado pelo admin não agrupa", async () => {
  const linhas = orcamentosDoRodrigo().filter((l) => l.id !== ID_096);
  const { db, ctx } = ambiente(linhas);
  const r = await toolsByName["agrupar_orcamentos"].execute(
    { orcamentos: ["ORÇ-00120", "ORÇ-00078"], _solicitante: { user_id: "v1", nome: "Vendedor", cargo: "seller" } }, ctx) as any;
  assertStringIncludes(r.error, "administrador ou financeiro");
  assertEquals(rpcsDeEscrita(db), []);
});

Deno.test("recusas claras sem pendência: inelegível pela leitura, outra embarcação, já agrupado, já virou OS, dois deslocamentos", async () => {
  const casos: Array<{ linhas: Linha[]; refs: string[]; motivos?: Record<string, string>; trecho: string }> = [
    {
      linhas: orcamentosDoRodrigo().filter((l) => l.id !== ID_096), refs: ["ORÇ-00120", "ORÇ-00078"],
      motivos: { [ID_120]: "ligado a: conta a receber/sinal" },
      trecho: "ORÇ-00120 não pode entrar no agrupamento: ligado a: conta a receber/sinal",
    },
    {
      linhas: [orcamento(ID_120, "ORÇ-00120", { vessel_id: "outro-barco" }), orcamento(ID_078, "ORÇ-00078", { created_at: "2026-08-13T15:00:00+00:00" })],
      refs: ["ORÇ-00120", "ORÇ-00078"], trecho: "ORÇ-00120 é de outro cliente ou de outra embarcação",
    },
    {
      linhas: [orcamento(ID_120, "ORÇ-00120", { status: "cancelled", merged_into_id: ID_121 }), orcamento(ID_078, "ORÇ-00078"),
        orcamento(ID_121, "ORÇ-00121")],
      refs: ["ORÇ-00120", "ORÇ-00078"], trecho: "ORÇ-00120 já foi agrupado em ORÇ-00121",
    },
    {
      linhas: [orcamento(ID_120, "ORÇ-00120", { status: "open", converted_to_os_at: "2026-10-15T14:00:00+00:00" }), orcamento(ID_078, "ORÇ-00078")],
      refs: ["ORÇ-00120", "ORÇ-00078"], trecho: "ORÇ-00120 não é mais um orçamento em aberto",
    },
    {
      linhas: [orcamento(ID_120, "ORÇ-00120", { travel_cost_total: 80 }), orcamento(ID_078, "ORÇ-00078", { travel_distance_km: 15 })],
      refs: ["ORÇ-00120", "ORÇ-00078"], trecho: "Mais de um tem deslocamento (",
    },
  ];
  for (const c of casos) {
    const { db, ctx } = ambiente(c.linhas, { motivos: c.motivos });
    const r = await executarChamadaDeTool({ name: "agrupar_orcamentos", input: { orcamentos: c.refs } }, amb(ctx));
    const res = r.toolResult as any;
    assertStringIncludes(String(res.error), c.trecho, JSON.stringify(res));
    assertEquals(res.nada_registrado, true, c.trecho);
    assertEquals(pendencias(db), [], c.trecho);
    assertEquals(rpcsDeEscrita(db), [], c.trecho);
  }
});

Deno.test("número que não existe: recusa (sem pendência)", async () => {
  const { db, ctx } = ambiente(orcamentosDoRodrigo());
  const r = await executarChamadaDeTool({ name: "agrupar_orcamentos", input: { orcamentos: ["ORÇ-00120", "ORÇ-00999"] } }, amb(ctx));
  assertStringIncludes(String((r.toolResult as any).error), "ORÇ-00999");
  assertEquals(pendencias(db), []);
});

// ── desagrupar ───────────────────────────────────────────────────────────────────────────────

function ambienteDoAgrupado(ativo = true) {
  const linhas = [
    orcamento(ID_078, "ORÇ-00078", { status: "cancelled", merged_into_id: ativo ? ID_121 : null }),
    orcamento(ID_120, "ORÇ-00120", { status: "cancelled", merged_into_id: ativo ? ID_121 : null }),
    orcamento(ID_121, "ORÇ-00121", { grand_total: 5148.8 }),
  ];
  return ambiente(linhas, {
    tabelas: {
      orcamento_agrupamentos: [{ id: "g1", agrupado_id: ID_121, desfeito_em: ativo ? null : "2026-10-15T15:00:00+00:00" }],
      orcamento_agrupamento_origens: [
        { agrupamento_id: "g1", origem_id: ID_120, numero: "ORÇ-00120", ordem: 2, quote_status_antes: "rejected", grand_total_antes: 1455.51 },
        { agrupamento_id: "g1", origem_id: ID_078, numero: "ORÇ-00078", ordem: 1, quote_status_antes: "draft", grand_total_antes: 3693.29 },
      ],
    },
    agrupados: [{ id: ID_121, numero: "ORÇ-00121", origens: ["ORÇ-00078", "ORÇ-00120"], pode_desagrupar: true, motivo: null }],
  });
}

Deno.test("desagrupar: a pendência diz o que volta (com situação e total de cada um) e que as edições não voltam; o 'sim' chama desagrupar_orcamentos", async () => {
  const { db, ctx } = ambienteDoAgrupado();
  const p = await pedir(ctx, db, "desagrupar_orcamento", { orcamento: "ORÇ-00121" });
  assertEquals(p.title, "Desagrupar orçamento");
  const s = semNbsp(p.summary);
  assertEquals(UUID_NO_TEXTO.test(s), false, s);
  assertStringIncludes(s, "Desagrupar *ORÇ-00121* (R$ 5.148,80):");
  assertStringIncludes(s,
    "Voltam a valer, como estavam antes de agrupar (situação e link do cliente): *ORÇ-00078* (Em elaboração, R$ 3.693,29), " +
      "*ORÇ-00120* (Reprovado, R$ 1.455,51).");
  assertStringIncludes(s, "ORÇ-00121 fica cancelado como histórico");
  assertStringIncludes(s, "NÃO volta para os originais");

  const ex = await toolsByName["desagrupar_orcamento"].execute(p.payload, ctx) as any;
  assertEquals(ex.ok, true, JSON.stringify(ex));
  assertEquals(rpcsDeEscrita(db), [["desagrupar_orcamentos", { p_agrupado: ID_121, p_autor: "dono-1" }]]);
  assertEquals(ressalvaDoResultado(ex), " ORÇ-00078, ORÇ-00120 voltaram a valer como estavam; ORÇ-00121 ficou cancelado como histórico.");
});

Deno.test("desagrupar pelo número de um dos ORIGINAIS: acha o agrupado e diz isso na confirmação", async () => {
  const { db, ctx } = ambienteDoAgrupado();
  const p = await pedir(ctx, db, "desagrupar_orcamento", { orcamento: "ORÇ-00120" });
  assertStringIncludes(p.summary, "ORÇ-00120 está agrupado em ORÇ-00121. Desagrupar *ORÇ-00121*");
  assertEquals(p.payload._retrato.agrupado, ID_121);
  const ex = await toolsByName["desagrupar_orcamento"].execute(p.payload, ctx) as any;
  assertEquals(ex.ok, true, JSON.stringify(ex));
  assertEquals(rpcsDeEscrita(db), [["desagrupar_orcamentos", { p_agrupado: ID_121, p_autor: "dono-1" }]]);
});

Deno.test("desagrupar o que não é agrupado (ou já foi desfeito): recusa sem pendência", async () => {
  const { db, ctx } = ambienteDoAgrupado(false);
  const r = await executarChamadaDeTool({ name: "desagrupar_orcamento", input: { orcamento: "ORÇ-00121" } }, amb(ctx));
  assertStringIncludes(String((r.toolResult as any).error), "ORÇ-00121 não é um orçamento agrupado");
  assertEquals(pendencias(db), []);
  assertEquals(rpcsDeEscrita(db), []);
});

Deno.test("desagrupar: o agrupado mudou depois do pedido → recusa para o dono, sem chamar o banco", async () => {
  const { db, ctx } = ambienteDoAgrupado();
  const p = await pedir(ctx, db, "desagrupar_orcamento", { orcamento: "ORÇ-00121" });
  db.tabelas.service_orders.find((l: Linha) => l.id === ID_121).updated_at = "2026-10-15T18:00:00+00:00";
  const r = await toolsByName["desagrupar_orcamento"].execute(p.payload, ctx) as any;
  assertEquals(r.error, "Nada foi desfeito: ORÇ-00121 mudou depois do pedido. Peça de novo que eu confiro.");
  assertEquals(rpcsDeEscrita(db), []);
});

Deno.test("desagrupar: dois 'sim' — o segundo diz que já estava desfeito; sem retrato não executa", async () => {
  const { db, ctx } = ambienteDoAgrupado();
  const p = await pedir(ctx, db, "desagrupar_orcamento", { orcamento: "ORÇ-00120" });
  db.tabelas.orcamento_agrupamentos[0].desfeito_em = "2026-10-15T19:00:00+00:00";
  for (const l of db.tabelas.service_orders) if (l.merged_into_id) Object.assign(l, { merged_into_id: null, status: "draft" });
  const r = await toolsByName["desagrupar_orcamento"].execute(p.payload, ctx) as any;
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(r.aviso, "Já estava desfeito: ORÇ-00121 já tinha sido desagrupado; nada novo foi gravado.");
  const semRetrato = await toolsByName["desagrupar_orcamento"].execute({ orcamento: "ORÇ-00121" }, ctx) as any;
  assertStringIncludes(semRetrato.error, "Nada foi desfeito: não consegui conferir o agrupamento");
  assertEquals(rpcsDeEscrita(db), []);
});

// ── registro, títulos, autonomia e perfis ────────────────────────────────────────────────────

Deno.test("registro: as três em allTools, títulos em português, escrita nunca autônoma, fora do bloqueio do WhatsApp", () => {
  for (const n of ["listar_orcamentos_para_agrupar", "agrupar_orcamentos", "desagrupar_orcamento"]) {
    assert(allTools.some((t) => t.name === n), n);
    assertEquals(FORA_DO_WHATSAPP.has(n), false, n);
  }
  assertEquals(tituloDaAcao("agrupar_orcamentos"), "Agrupar orçamentos em um só");
  assertEquals(tituloDaAcao("desagrupar_orcamento"), "Desagrupar orçamento");
  assertEquals(tituloDaAcao("listar_orcamentos_para_agrupar"), "Listar orçamentos para agrupar");
  assert(NEVER_AUTONOMOUS.has("agrupar_orcamentos"));
  assert(NEVER_AUTONOMOUS.has("desagrupar_orcamento"));
  assertEquals(tool("agrupar_orcamentos").risk, "medium");
  assertEquals(tool("desagrupar_orcamento").risk, "medium");
  assertEquals(tool("agrupar_orcamentos").gravarSolicitante, true);
  assertEquals(tool("desagrupar_orcamento").gravarSolicitante, true);
  // o flag antigo saiu: incluir reprovado é voltar_para_em_elaboracao (só no "sim")
  const props = (tool("agrupar_orcamentos").input_schema as any).properties;
  assertEquals("incluir_reprovados_confirmado" in props, false);
  assert("voltar_para_em_elaboracao" in props);
});

Deno.test("resumo do agrupar com reprovado: recusa decidida antes da linha 'Pedido por'", async () => {
  const { db, ctx } = ambiente(orcamentosDoRodrigo());
  const resumo = await buildPendingSummary(ctx.admin, "agrupar_orcamentos",
    { orcamentos: ["ORÇ-00120", "ORÇ-00096", "ORÇ-00078"] }, { userId: "dono-1" });
  const recusa = resumoQueRecusa("agrupar_orcamentos", resumo);
  assert(recusa, resumo);
  assertStringIncludes(recusa.error, "ORÇ-00096 (Atendimento emergencial a bordo");
  assertEquals(rpcsDeEscrita(db), []);
});

Deno.test("perfis: no de operação as três; no enxuto do admin nenhuma à vista (teto) e as três pela rede — leitura direto, escrita com 'sim'", async () => {
  for (const n of ["listar_orcamentos_para_agrupar", "agrupar_orcamentos", "desagrupar_orcamento"]) {
    assert(PERFIL_OPERACAO.has(n), n);
    assertEquals(PERFIL_ADMIN.has(n), false, `${n} no perfil enxuto subiria o teto`);
    assertEquals(SO_PELA_REDE.has(n), false, n);
  }
  assertEquals(rodaDiretoPelaRede(tool("listar_orcamentos_para_agrupar")), true);
  assertEquals(rodaDiretoPelaRede(tool("agrupar_orcamentos")), false);

  // Como o Claude Max (erp-mcp) monta o turno do admin no perfil enxuto: só PERFIL_ADMIN + ferramenta_extra à vista.
  const job = ferramentasDoJob("admin", [...PERFIL_ADMIN, NOME_DA_FERRAMENTA_EXTRA], allTools.map((t) => t.name), "whatsapp");
  for (const n of ["listar_orcamentos_para_agrupar", "agrupar_orcamentos", "desagrupar_orcamento"]) {
    assert(job.alcancaveisPelaRede[n], `${n} fora do alcance da ferramenta_extra`);
  }
  // E o financeiro, no perfil de operação, também vê as três (o técnico não: cargo).
  const tecnico = ferramentasDoJob("technician", [...PERFIL_OPERACAO], [], "whatsapp");
  assertEquals(Object.keys(tecnico.toolsByName).filter((n) => n.includes("agrupar")), []);

  // Pela ferramenta_extra: a leitura roda direto…
  const linhas = orcamentosDoRodrigo();
  const { db, ctx } = ambiente(linhas);
  const ambDoAdmin = { ...job, toolCtx: ctx, sessionId: "s1", channel: "whatsapp" as const };
  const lida = await executarChamadaDeTool({
    name: NOME_DA_FERRAMENTA_EXTRA, input: { nome: "listar_orcamentos_para_agrupar", argumentos: { embarcacao_id: BARCO } },
  }, ambDoAdmin);
  assertEquals((lida.toolResult as any).orcamentos?.length, 3, JSON.stringify(lida.toolResult));
  // …e o agrupar com o reprovado devolve a pergunta, sem pendência.
  const pedida = await executarChamadaDeTool({
    name: NOME_DA_FERRAMENTA_EXTRA, input: { nome: "agrupar_orcamentos", argumentos: { orcamentos: ["ORÇ-00120", "ORÇ-00096", "ORÇ-00078"] } },
  }, ambDoAdmin);
  assertStringIncludes(String((pedida.toolResult as any).error), "pergunte ao dono se ele entra");
  assertEquals(pendencias(db), []);
  // "entra": vira UMA pendência (o "sim" no sino/WhatsApp executa por toolsByName, com qualquer perfil)
  const ok = await executarChamadaDeTool({
    name: NOME_DA_FERRAMENTA_EXTRA,
    input: { nome: "agrupar_orcamentos", argumentos: { orcamentos: ["ORÇ-00120", "ORÇ-00096", "ORÇ-00078"], voltar_para_em_elaboracao: ["ORÇ-00096"] } },
  }, ambDoAdmin);
  assertEquals((ok.toolResult as any).pending, true, JSON.stringify(ok.toolResult));
  assertEquals(pendencias(db).length, 1);
  assertEquals(pendencias(db)[0].action_name, "agrupar_orcamentos");
});

Deno.test("list_service_orders: origem agrupada é 'Orçamento agrupado' (pelo motivo gravado), não OS", () => {
  assertEquals(agrupadoEm({ status: "cancelled", cancellation_reason: "Agrupado em ORÇ-00121 (reúne ORÇ-00078, ORÇ-00120)" }), "ORÇ-00121");
  assertEquals(agrupadoEm({ status: "cancelled", cancellation_reason: "cliente desistiu" }), undefined);
  assertEquals(agrupadoEm({ status: "draft", cancellation_reason: "Agrupado em ORÇ-00121" }), undefined);
});
