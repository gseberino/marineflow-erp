// Histórico de documentos pelo assistente (16/11/2026): consultar_historico_documento e restaurar_documento.
// O que guia os testes:
//   - leitura que falha NUNCA vira "sem alterações" (o erro vai inteiro ao modelo);
//   - restaurar sempre pede o "sim", e a simulação que falha ou não muda nada é recusa sem pendência;
//   - o "sim" leva o hash da simulação (p_conferir_hash) e quem pediu (p_autor), e as parcelas são reajustadas depois.
// Rodar com:
//   deno test --allow-all --no-check --node-modules-dir=none supabase/functions/_shared/ai/tools/historico-documento_test.ts
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  alteracoesParaOModelo, CARGOS_DO_HISTORICO, historicoDocumentoTools, linhaDoEvento, pedidoDeRestaurar, resumirRestauracao,
} from "./historico-documento.ts";
import { allTools, toolsByName } from "./index.ts";
import { buildPendingSummary, executarChamadaDeTool, resumoQueRecusa, tituloDaAcao } from "../agent.ts";
import { NEVER_AUTONOMOUS } from "../autonomy-policy.ts";
import { PERFIL_ADMIN, PERFIL_OPERACAO, rodaDiretoPelaRede, SO_PELA_REDE } from "../perfil-operacao.ts";
import { FORA_DO_WHATSAPP } from "../channel-scope.ts";

type Linha = Record<string, any>;

const OS_ID = "0b0b0b0b-0000-4000-8000-000000000112";
const EV1 = "aaaaaaaa-0000-4000-8000-000000000001";
const EV2 = "aaaaaaaa-0000-4000-8000-000000000002";
const EV3 = "aaaaaaaa-0000-4000-8000-000000000003";

/** O que documento_historico devolve (modo alteracoes), como o banco formata. */
function historicoDoBanco(): Linha {
  return {
    documento: { tipo: "os", numero: "ORÇ-00112", id: OS_ID },
    modo: "alteracoes",
    total_de_eventos: 25,
    aviso: "Mostrando os 20 eventos mais recentes de 25. Peça com \"desde\"/\"ate\" ou um limite maior para ver mais.",
    eventos: [
      {
        quando: "16/11/2026 14:22", quando_iso: "2026-11-16T17:22:00Z", quem: "Gustavo", por_onde: "tela",
        itens: [
          {
            item: "Peça: Bomba", acao: "alterado", motivo: null, registro_id: EV1, desfazivel: true,
            mudancas: [{ campo: "Quantidade", antes: "2", depois: "3", calculado: false }],
          },
          {
            item: "Documento", acao: "alterado", motivo: null, registro_id: EV2, desfazivel: true,
            mudancas: [
              { campo: "Desconto", antes: "R$ 0,00", depois: "R$ 50,00", calculado: false },
              { campo: "Total", antes: "R$ 1.200,00", depois: "R$ 1.150,00", calculado: true },
            ],
          },
        ],
      },
      {
        quando: "15/11/2026 09:10", quando_iso: "2026-11-15T12:10:00Z", quem: "Gustavo", por_onde: "assistente (WhatsApp)",
        desfazivel: false,
        itens: [{ item: "Versão 2 (enviado)", acao: "versão guardada", mudancas: [], motivo: null, registro_id: EV3, desfazivel: false }],
      },
    ],
  };
}

/** O que documento_restaurar devolve na simulação. */
function simulacao(extra: Linha = {}): Linha {
  return {
    documento: "ORÇ-00112",
    documento_id: OS_ID,
    o_que_muda: {
      cabecalho: [
        { campo: "Desconto", antes: "R$ 50,00", depois: "R$ 0,00", calculado: false },
        { campo: "Total", antes: "R$ 1.150,00", depois: "R$ 1.200,00", calculado: true },
      ],
      itens_incluidos: [{ item: "Serviço: Revisão", quantidade: 1, total: "R$ 100,00" }],
      itens_removidos: [{ item: "Peça: Filtro", quantidade: 2, total: "R$ 80,00" }],
      itens_alterados: [{ item: "Peça: Bomba", mudancas: [{ campo: "Quantidade", antes: "3", depois: "2", calculado: false }] }],
      sem_diferenca: false,
    },
    nao_desfeito: [{ item: "Peça: Cabo", campo: "Preço", motivo: "mudou de novo depois" }],
    avisos: [{
      item: "Peça: Filtro",
      aviso: "sai do documento e leva junto: item de pedido de compra PC-00007 (isso não volta numa restauração futura)",
    }],
    total_antes: "R$ 1.150,00",
    total_depois: "R$ 1.200,00",
    pede_nova_assinatura: true,
    hash_do_documento: "hash-da-simulacao",
    simulacao: true,
    restaurado: false,
    ...extra,
  };
}

function bancoFalso(tabelas: Record<string, Linha[]>, rpcs: Record<string, (p: any) => { data?: unknown; error?: { message: string } }> = {}) {
  const chamadas = { rpc: [] as [string, any][], insert: [] as [string, any][], update: [] as [string, any, any][] };
  const db: any = {
    chamadas,
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
        maybeSingle: () => Promise.resolve({ data: linhas()[0] ?? null, error: null }),
        single: () => Promise.resolve({ data: linhas()[0] ?? null, error: null }),
        then: (ok: any, ko: any) => Promise.resolve({ data: linhas(), error: null }).then(ok, ko),
        insert: (v: Linha) => {
          chamadas.insert.push([tabela, v]);
          const r: any = Promise.resolve({ data: null, error: null });
          r.select = () => ({ single: () => Promise.resolve({ data: { id: `novo-${tabela}`, ...v }, error: null }) });
          return r;
        },
        update: (v: Linha) => ({
          eq: (c: string, id: unknown) => {
            chamadas.update.push([tabela, v, id]);
            return Promise.resolve({ data: null, error: null });
          },
        }),
      };
      return q;
    },
  };
  return db;
}

function ambiente(rpcs: Record<string, (p: any) => { data?: unknown; error?: { message: string } }> = {}, cargo = "admin") {
  const db = bancoFalso({
    app_users: [{ id: "dono-1", full_name: "Gustavo" }],
    service_orders: [{ id: OS_ID, service_order_number: "ORÇ-00112", grand_total: 1200 }],
    receivables: [{ id: "rec-1", service_order_id: OS_ID, amount: 1150, paid_amount: 0, status: "pending" }],
  }, {
    documento_historico: () => ({ data: historicoDoBanco() }),
    documento_restaurar: (p) => ({ data: p.p_simular ? simulacao() : { ...simulacao(), simulacao: false, restaurado: true, versao_nova: 4 } }),
    ...rpcs,
  });
  const ctx = { sb: db, admin: db, userId: "dono-1", userRole: cargo as any, jwt: "", appOrigin: "", settings: {} };
  return { db, ctx };
}

const tool = (nome: string) => historicoDocumentoTools.find((t) => t.name === nome)!;
const amb = (ctx: any) => ({ toolsByName, alcancaveisPelaRede: {}, toolCtx: ctx, sessionId: "s1", channel: "whatsapp" as const });
const pendencias = (db: any) => db.chamadas.insert.filter(([t]: [string]) => t === "ai_operator_pending_actions").map(([, v]: [string, Linha]) => v);
const rpcs = (db: any, nome: string) => db.chamadas.rpc.filter(([n]: [string]) => n === nome).map(([, p]: [string, Linha]) => p);
/** "não houve alteração" dito de qualquer jeito. */
const SEM_ALTERACAO = /sem altera|nenhuma altera|não houve|nao houve/i;

// ── revisões do documento (Rev. N impressa no PDF, 17/11/2026) ───────────────────────────────

Deno.test("revisoes: pede documento_revisoes pelo número, devolve o que o banco disse e a instrução de comparar", async () => {
  const doBanco = { documento: "ORÇ-00112", tipo_atual: "orçamento", revisoes: [{ revisao: 2, versao_do_historico: 5 }], mudou_desde_a_ultima: true };
  const { db, ctx } = ambiente({ documento_revisoes: () => ({ data: doBanco }) });
  const r = await tool("consultar_historico_documento").execute({ documento: "ORÇ-00112", modo: "revisoes" }, ctx) as any;
  assertEquals(rpcs(db, "documento_revisoes"), [{ p_ref: "ORÇ-00112" }]);
  assertEquals(rpcs(db, "documento_historico"), [], "revisão não passa pelo histórico de alterações");
  assertEquals(r.revisoes, doBanco.revisoes);
  assertEquals(r.mudou_desde_a_ultima, true);
  assertStringIncludes(r.instrucao, "versao_do_historico");
});

Deno.test("conferir_codigo: o código vai inteiro; falha de leitura nunca vira 'não há revisão'", async () => {
  const { db, ctx } = ambiente({ documento_revisao_conferir: () => ({ data: { achou: true, documentos: [] } }) });
  const r = await tool("consultar_historico_documento").execute({ documento: "7F3A-21C9", modo: "conferir_codigo" }, ctx) as any;
  assertEquals(rpcs(db, "documento_revisao_conferir"), [{ p_codigo: "7F3A-21C9" }]);
  assertEquals(r.achou, true);
  const falha = ambiente({ documento_revisoes: () => ({ error: { message: "function does not exist" } }) });
  const f = await tool("consultar_historico_documento").execute({ documento: "ORÇ-00112", modo: "revisoes" }, falha.ctx) as any;
  assertStringIncludes(f.error, "Não consegui ler as revisões");
  assertStringIncludes(f.instrucao, "FALHOU");
  // revisão só existe para orçamento/OS
  const compra = await tool("consultar_historico_documento").execute({ documento: "PC-1", tipo: "compra", modo: "revisoes" }, ctx) as any;
  assertStringIncludes(compra.error, "só existe para orçamento/OS");
});

// ── consultar ────────────────────────────────────────────────────────────────────────────────

Deno.test("consultar: chama documento_historico com o pedido e devolve uma linha por evento, os registro_ids e o aviso de corte", async () => {
  const { db, ctx } = ambiente();
  const r = await tool("consultar_historico_documento").execute({ documento: "ORÇ-00112" }, ctx) as any;
  assertEquals(rpcs(db, "documento_historico"), [{
    p_tipo: "os", p_ref: "ORÇ-00112", p_modo: "alteracoes", p_versao: null, p_versao_b: null, p_desde: null, p_ate: null, p_limite: 20,
  }]);
  assertEquals(r.linhas, [
    "16/11/2026 14:22 · Gustavo (tela): Peça: Bomba — Quantidade 2 → 3; Documento — Desconto R$ 0,00 → R$ 50,00 · " +
    "Total recalculado R$ 1.200,00 → R$ 1.150,00",
    "15/11/2026 09:10 · Gustavo (assistente (WhatsApp)): Versão 2 (enviado) versão guardada",
  ]);
  assertEquals(r.registro_ids, [[EV1, EV2], []], "a versão guardada não se desfaz: o evento fica com a lista vazia");
  assertStringIncludes(r.aviso, "Mostrando os 20 eventos mais recentes de 25");
  assertEquals(r.total_de_eventos, 25);
  assertEquals(r.documento.numero, "ORÇ-00112");
  assertEquals("eventos" in r, false, "o evento inteiro custaria tokens: só as linhas e os ids");
  assertStringIncludes(r.instrucao, "restaurar_documento");
});

Deno.test("consultar: só a data é o dia inteiro de Brasília (desde 00:00, ate 23:59:59.999); data e hora passam como vieram", async () => {
  const { db, ctx } = ambiente();
  const t = tool("consultar_historico_documento");
  await t.execute({ documento: "ORÇ-00112", desde: "2026-11-16", ate: "2026-11-16" }, ctx);
  await t.execute({ documento: "ORÇ-00112", desde: "2026-11-16T14:00:00-03:00", ate: "2026-11-16T15:30:00Z" }, ctx);
  const [dia, hora] = rpcs(db, "documento_historico");
  assertEquals([dia.p_desde, dia.p_ate], ["2026-11-16T00:00:00-03:00", "2026-11-16T23:59:59.999-03:00"]);
  assertEquals([hora.p_desde, hora.p_ate], ["2026-11-16T14:00:00-03:00", "2026-11-16T15:30:00Z"]);
  // data impossível continua erro, e o exemplo explica o dia inteiro
  const r = await t.execute({ documento: "ORÇ-00112", ate: "2026-13-45" }, ctx) as any;
  assertStringIncludes(r.error, "2026-11-16 = o dia inteiro de Brasília");
  assertEquals(rpcs(db, "documento_historico").length, 2);
});

Deno.test("consultar: registro_ids só com o que se desfaz; evento sem nada desfazível vem vazio e a instrução explica", () => {
  const r = alteracoesParaOModelo({
    documento: { numero: "ORÇ-00112" }, total_de_eventos: 2, aviso: null,
    eventos: [
      {
        quando: "16/11/2026 14:22", quem: "Ana", por_onde: "tela", desfazivel: true,
        itens: [
          { item: "Peça: Bomba", acao: "alterado", registro_id: EV1, desfazivel: true, mudancas: [{ campo: "Quantidade", antes: "2", depois: "3" }] },
          { item: "Documento", acao: "alterado", registro_id: EV2, desfazivel: false, mudancas: [{ campo: "Situação", antes: "Rascunho", depois: "Enviado" }] },
        ],
      },
      {
        quando: "15/11/2026 09:10", quem: "registro antigo", desfazivel: false,
        // sem o campo desfazivel (registro antigo): não vai
        itens: [{ item: "Documento", acao: "alterado", registro_id: EV3, mudancas: [{ campo: "Desconto", antes: "R$ 0,00", depois: "R$ 5,00" }] }],
      },
    ],
  }, "os") as any;
  assertEquals(r.registro_ids, [[EV1], []]);
  assertStringIncludes(r.instrucao, "registro_ids vazio NÃO se desfaz");
  assertStringIncludes(r.instrucao, "versão");
});

Deno.test("consultar: erro do banco vira { error } com a frase do banco — nunca 'sem alterações'", async () => {
  const { ctx } = ambiente({ documento_historico: () => ({ error: { message: "Documento não encontrado: os ORÇ-00999." } }) });
  const r = await tool("consultar_historico_documento").execute({ documento: "ORÇ-00999" }, ctx) as any;
  assertStringIncludes(r.error, "Não consegui ler o histórico de ORÇ-00999: Documento não encontrado: os ORÇ-00999.");
  assertStringIncludes(r.instrucao, "Nunca diga que não houve alterações");
  assertEquals(r.linhas, undefined);
  assertEquals(SEM_ALTERACAO.test(r.error), false);
  // cargo (42501) sem o prefixo técnico
  const { ctx: c2 } = ambiente({ documento_historico: () => ({ error: { message: "42501: O histórico de documentos é só para administrador e financeiro." } }) });
  const r2 = await tool("consultar_historico_documento").execute({ documento: "ORÇ-00112" }, c2) as any;
  assertEquals(r2.error, "Não consegui ler o histórico de ORÇ-00112: O histórico de documentos é só para administrador e financeiro.");
});

Deno.test("consultar: o banco sem resposta (data nula, sem erro) também é falha, não 'sem alterações'", async () => {
  const { ctx } = ambiente({ documento_historico: () => ({ data: null }) });
  const r = await tool("consultar_historico_documento").execute({ documento: "ORÇ-00112" }, ctx) as any;
  assertStringIncludes(r.error, "o banco não devolveu nada");
  assertEquals(r.linhas, undefined);
});

Deno.test("consultar: leitura certa e vazia diz que não há alteração NO PERÍODO (é a única vez que pode dizer)", () => {
  const r = alteracoesParaOModelo({ documento: { numero: "ORÇ-00112" }, total_de_eventos: 0, aviso: null, eventos: [] }, "os") as any;
  assertEquals(r.linhas, []);
  assertEquals(r.registro_ids, []);
  assertStringIncludes(r.instrucao, "A leitura deu certo");
});

Deno.test("consultar: técnico e vendedor não leem; nada vai ao banco", async () => {
  for (const cargo of ["technician", "seller", "external_seller"]) {
    const { db, ctx } = ambiente({}, cargo);
    const r = await tool("consultar_historico_documento").execute({ documento: "ORÇ-00112" }, ctx) as any;
    assertStringIncludes(r.error, "administrador e financeiro");
    assertEquals(db.chamadas.rpc, []);
  }
  const { ctx } = ambiente({}, "financial");
  assertEquals(Array.isArray((await tool("consultar_historico_documento").execute({ documento: "ORÇ-00112" }, ctx) as any).linhas), true);
});

Deno.test("consultar: tipo e modo fora da lista, comparar sem versão e data torta voltam erro sem chamar o banco", async () => {
  const { db, ctx } = ambiente();
  const t = tool("consultar_historico_documento");
  assertStringIncludes((await t.execute({ documento: "x", tipo: "fatura" }, ctx) as any).error, "não existe");
  assertStringIncludes((await t.execute({ documento: "x", modo: "tudo" }, ctx) as any).error, "não existe");
  assertStringIncludes((await t.execute({ documento: "ORÇ-00112", modo: "comparar" }, ctx) as any).error, "diga a versão");
  assertStringIncludes((await t.execute({ documento: "ORÇ-00112", desde: "ontem" }, ctx) as any).error, "ISO");
  assertStringIncludes((await t.execute({ documento: "ORÇ-00112", versao: 1.5, modo: "ver_versao" }, ctx) as any).error, "inteiro");
  assertStringIncludes((await t.execute({ documento: "  " }, ctx) as any).error, "qual documento");
  assertEquals(db.chamadas.rpc, []);
});

Deno.test("consultar: os outros modos devolvem o que o banco formatou; cadastro não traz registro_ids (só OS se restaura)", async () => {
  const comparacao = { documento: { numero: "ORÇ-00112" }, modo: "comparar", de: "v2", para: "estado atual", diferencas: { sem_diferenca: true } };
  const { db, ctx } = ambiente({ documento_historico: (p) => ({ data: p.p_modo === "comparar" ? comparacao : historicoDoBanco() }) });
  const t = tool("consultar_historico_documento");
  assertEquals(await t.execute({ documento: "ORÇ-00112", modo: "comparar", versao: 2, limite: 500 }, ctx), comparacao);
  assertEquals(rpcs(db, "documento_historico")[0].p_versao, 2);
  assertEquals(rpcs(db, "documento_historico")[0].p_limite, 100);
  const r = await t.execute({ documento: "Rodrigo", tipo: "cliente" }, ctx) as any;
  assertEquals(r.registro_ids, undefined);
  assertEquals(r.instrucao.includes("restaurar_documento"), false);
});

Deno.test("linha do evento: inclusão mostra o que entrou; motivo aparece; só recálculo não some", () => {
  assertEquals(linhaDoEvento({
    quando: "16/11/2026 10:00", quem: "Ana", por_onde: "assistente (painel)",
    itens: [{ item: "Serviço: Revisão", acao: "incluído", mudancas: [{ campo: "Quantidade", antes: null, depois: "1" }], motivo: "pedido do cliente" }],
  }), "16/11/2026 10:00 · Ana (assistente (painel)): Serviço: Revisão incluído (Quantidade 1) (motivo: pedido do cliente)");
  assertEquals(linhaDoEvento({
    quando: "16/11/2026 10:01", quem: "sistema", itens: [{ item: "Documento", acao: "alterado", mudancas: [{ campo: "Total", antes: "R$ 1,00", depois: "R$ 2,00", calculado: true }] }],
  }), "16/11/2026 10:01 · sistema: só recálculo do sistema · Total recalculado R$ 1,00 → R$ 2,00");
});

// ── restaurar: pedido ────────────────────────────────────────────────────────────────────────

Deno.test("restaurar (preValidar, sem banco): documento, versão OU eventos, registro_id de verdade, só admin e financeiro", () => {
  const t = tool("restaurar_documento");
  const admin = { userRole: "admin" } as any;
  assertStringIncludes(t.preValidar!({ versao: 2 }, admin)!.error, "qual orçamento/OS");
  assertStringIncludes(t.preValidar!({ documento: "ORÇ-00112" }, admin)!.error, "UMA coisa");
  assertStringIncludes(t.preValidar!({ documento: "ORÇ-00112", versao: 2, eventos: [EV1] }, admin)!.error, "UMA coisa");
  assertStringIncludes(t.preValidar!({ documento: "ORÇ-00112", eventos: ["o da bomba"] }, admin)!.error, "não é um registro_id");
  assertStringIncludes(t.preValidar!({ documento: "ORÇ-00112", versao: 0 }, admin)!.error, "inteiro");
  assertStringIncludes(t.preValidar!({ documento: "ORÇ-00112", versao: 2 }, { userRole: "technician" } as any)!.error, "administrador e financeiro");
  assertStringIncludes(t.preValidar!({ documento: "ORÇ-00112", versao: 2 }, { userRole: "seller" } as any)!.error, "administrador e financeiro");
  assertEquals(t.preValidar!({ documento: "ORÇ-00112", versao: 2 }, { userRole: "financial" } as any), null);
  assertEquals(t.preValidar!({ documento: "ORÇ-00112", eventos: [EV1, EV2] }, admin), null);
  // repetido some; maiúscula normaliza
  assertEquals((pedidoDeRestaurar({ documento: "ORÇ-00112", eventos: [EV1, EV1.toUpperCase()] }) as any).eventos, [EV1]);
});

Deno.test("restaurar: a simulação que FALHA é recusa — sem pendência, com a frase do banco (p_simular e p_autor de quem pede)", async () => {
  const { db, ctx } = ambiente({
    documento_restaurar: () => ({ error: { message: "P0001: OS-00045 está Concluída: só documento em aberto pode ser restaurado." } }),
  });
  const r = await executarChamadaDeTool({ name: "restaurar_documento", input: { documento: "OS-00045", versao: 2 } }, amb(ctx));
  const res = r.toolResult as any;
  assertEquals(pendencias(db), [], "nada vai para o sino nem pede 'sim'");
  assertEquals(r.proposal, undefined);
  assertEquals(res.nada_registrado, true);
  assertStringIncludes(res.error, "Não dá para restaurar OS-00045: OS-00045 está Concluída: só documento em aberto pode ser restaurado. Nada foi alterado.");
  const chamadas = rpcs(db, "documento_restaurar");
  assert(chamadas.length >= 1);
  for (const p of chamadas) {
    assertEquals(p.p_simular, true, "antes do 'sim' só simula");
    assertEquals(p.p_autor, "dono-1");
  }
});

Deno.test("restaurar: nada mudaria (já está assim) também é recusa sem pendência", async () => {
  const { db, ctx } = ambiente({
    documento_restaurar: () => ({ data: simulacao({ o_que_muda: { cabecalho: [], itens_incluidos: [], itens_removidos: [], itens_alterados: [], sem_diferenca: true } }) }),
  });
  const r = await executarChamadaDeTool({ name: "restaurar_documento", input: { documento: "ORÇ-00112", eventos: [EV1] } }, amb(ctx));
  assertStringIncludes((r.toolResult as any).error, "Nada mudaria em ORÇ-00112");
  assertEquals(pendencias(db), []);
});

Deno.test("restaurar: simulação certa vira UMA pendência com o que muda, o total, a assinatura e o que não se desfaz — e o hash guardado", async () => {
  const { db, ctx } = ambiente();
  const r = await executarChamadaDeTool(
    { name: "restaurar_documento", input: { documento: "ORÇ-00112", versao: 2, motivo: "cliente desistiu do desconto" } },
    amb(ctx),
  );
  assertEquals((r.toolResult as any).pending, true, JSON.stringify(r.toolResult));
  const [p] = pendencias(db);
  assertEquals(p.action_name, "restaurar_documento");
  assertEquals(p.risk_level, "high");
  assertEquals(p.title, "Restaurar orçamento/OS (desfazer ou voltar versão)");
  assertEquals(p.payload._retrato.hash_do_documento, "hash-da-simulacao");
  assertEquals(p.payload._solicitante.user_id, "dono-1");
  const s = String(p.summary);
  assertStringIncludes(s, "Restaurar *ORÇ-00112*: voltar para a versão 2.");
  assertStringIncludes(s, "Motivo: cliente desistiu do desconto");
  assertStringIncludes(s, "- Desconto R$ 50,00 → R$ 0,00");
  assertStringIncludes(s, "- Total R$ 1.150,00 → R$ 1.200,00 (recalculado)");
  assertStringIncludes(s, "- Volta: Serviço: Revisão (1 un., R$ 100,00)");
  assertStringIncludes(s, "- Sai: Peça: Filtro (2 un., R$ 80,00)");
  assertStringIncludes(s, "- Peça: Bomba: Quantidade 3 → 2");
  assertStringIncludes(s, "Total: *R$ 1.150,00* → *R$ 1.200,00*");
  assertStringIncludes(s, "O cliente terá de assinar de novo");
  assertStringIncludes(s, "- Peça: Cabo (Preço): mudou de novo depois");
  // o que sai e arrasta junto (pedido de compra) aparece destacado antes do "sim"
  assertStringIncludes(s, "⚠️ *Atenção:*\n- Peça: Filtro: sai do documento e leva junto: item de pedido de compra PC-00007");
  assertStringIncludes(s, "Pedido por: *Gustavo*");
  // o retrato e o resumo vêm da MESMA simulação (uma transação só, e o hash é o da simulação que o dono leu)
  assertEquals(rpcs(db, "documento_restaurar").length, 1);
  assertEquals(rpcs(db, "documento_restaurar")[0], {
    p_ref: "ORÇ-00112", p_versao: 2, p_eventos: null, p_motivo: "cliente desistiu do desconto",
    p_simular: true, p_conferir_hash: null, p_autor: "dono-1",
  });
});

Deno.test("restaurar (resumo): erro inesperado vira uma linha ⚠️ que o agente trata como recusa", async () => {
  const quebrado = { rpc: () => Promise.reject(new Error("rede caiu")) };
  const resumo = await buildPendingSummary(quebrado, "restaurar_documento", { documento: "ORÇ-00112", versao: 2 }, { userId: "dono-1" });
  assertEquals(resumo, "⚠️ Não consegui simular a restauração agora (rede caiu). Nada foi alterado; tente de novo.");
  assertEquals(resumoQueRecusa("restaurar_documento", resumo)?.nada_registrado, true);
  // argumento torto também recusa no resumo, numa linha (o preValidar já teria barrado; o resumo não confia)
  const torto = await resumirRestauracao(quebrado, { documento: "ORÇ-00112" }, "dono-1");
  assertEquals(resumoQueRecusa("restaurar_documento", torto)?.nada_registrado, true);
});

// ── restaurar: o "sim" ───────────────────────────────────────────────────────────────────────

Deno.test("restaurar (execute): passa p_simular=false, o hash guardado e quem pediu; depois reajusta as parcelas", async () => {
  const { db, ctx } = ambiente();
  const payload = {
    documento: "ORÇ-00112", versao: 2, motivo: "voltar",
    _retrato: { hash_do_documento: "hash-da-simulacao" },
    _solicitante: { user_id: "dono-1", nome: "Gustavo", cargo: "admin" },
  };
  const r = await tool("restaurar_documento").execute(payload, ctx) as any;
  assertEquals(rpcs(db, "documento_restaurar"), [{
    p_ref: "ORÇ-00112", p_versao: 2, p_eventos: null, p_motivo: "voltar",
    p_simular: false, p_conferir_hash: "hash-da-simulacao", p_autor: "dono-1",
  }]);
  // a cascata: recalcula (a RPC de sempre) e redistribui a parcela pendente para o total novo
  assertEquals(rpcs(db, "recalc_so_totals"), [{ so_id: OS_ID }]);
  const parcela = db.chamadas.update.find(([t]: [string]) => t === "receivables");
  assert(parcela, "a parcela não foi reajustada");
  assertEquals(parcela[1].amount, 1200);
  assertEquals(r.ok, true);
  assertEquals(r.restaurado, true);
  assertEquals(r.versao_nova, 4);
  assertStringIncludes(r.aviso, "ORÇ-00112 restaurado: total R$ 1.150,00 → R$ 1.200,00. Guardado como versão 4.");
  assertStringIncludes(r.aviso, "O cliente terá de assinar de novo.");
  assertStringIncludes(r.aviso, "Atenção: Peça: Filtro sai do documento e leva junto: item de pedido de compra PC-00007");
  assertStringIncludes(r.aviso, "parcelas a receber foram reajustadas");
  assertEquals(r.avisos.length, 1);
});

Deno.test("restaurar (execute): a cascata usa o documento_id da função, não o número", async () => {
  const OUTRA = "0b0b0b0b-0000-4000-8000-000000000999";
  const { db, ctx } = ambiente({
    documento_restaurar: () => ({ data: { ...simulacao({ documento_id: OUTRA }), simulacao: false, restaurado: true, versao_nova: 4 } }),
  });
  await tool("restaurar_documento").execute({ documento: "ORÇ-00112", versao: 2, _retrato: { hash_do_documento: "h" } }, ctx);
  assertEquals(rpcs(db, "recalc_so_totals"), [{ so_id: OUTRA }]);
});

Deno.test("restaurar (execute): sem o retrato não restaura às cegas; erro do banco diz que nada foi restaurado", async () => {
  const { db, ctx } = ambiente();
  const sem = await tool("restaurar_documento").execute({ documento: "ORÇ-00112", versao: 2 }, ctx) as any;
  assertStringIncludes(sem.error, "não guardou o retrato");
  assertEquals(db.chamadas.rpc, []);

  const { ctx: c2 } = ambiente({
    documento_restaurar: () => ({ error: { message: "P0001: ORÇ-00112 mudou depois do pedido de restauração. Consulte de novo antes de restaurar." } }),
  });
  const r = await tool("restaurar_documento").execute({ documento: "ORÇ-00112", versao: 2, _retrato: { hash_do_documento: "h" } }, c2) as any;
  assertEquals(r.error, "Nada foi restaurado: ORÇ-00112 mudou depois do pedido de restauração. Consulte de novo antes de restaurar.");
});

Deno.test("restaurar (execute): o cargo de quem PEDIU conta — o admin não lava o pedido do técnico", async () => {
  const { db, ctx } = ambiente();
  const r = await tool("restaurar_documento").execute({
    documento: "ORÇ-00112", versao: 2, _retrato: { hash_do_documento: "h" },
    _solicitante: { user_id: "tec-1", nome: "Técnico", cargo: "technician" },
  }, ctx) as any;
  assertStringIncludes(r.error, "administrador e financeiro");
  assertEquals(db.chamadas.rpc, []);
});

Deno.test("restaurar (execute): parcelas que não se reajustam aparecem no aviso (nunca em silêncio)", async () => {
  // a cascata lança (ex.: leitura quebrada)
  const { ctx } = ambiente({ recalc_so_totals: () => ({}) });
  ctx.sb.from = (t: string) => {
    if (t === "service_orders") return { select: () => ({ eq: () => ({ maybeSingle: () => Promise.reject(new Error("sem permissão")) }) }) };
    throw new Error(`tabela inesperada ${t}`);
  };
  const r = await tool("restaurar_documento").execute({ documento: "ORÇ-00112", versao: 2, _retrato: { hash_do_documento: "h" } }, ctx) as any;
  assertEquals(r.restaurado, true);
  assertStringIncludes(r.aviso, "parcelas a receber NÃO foram reajustadas (sem permissão)");

  // a função não devolveu o id (e o pedido foi pelo número): não adivinha
  const { ctx: c2 } = ambiente({
    documento_restaurar: () => ({ data: { ...simulacao({ documento_id: null }), simulacao: false, restaurado: true } }),
  });
  const r2 = await tool("restaurar_documento").execute({ documento: "ORÇ-00112", versao: 2, _retrato: { hash_do_documento: "h" } }, c2) as any;
  assertStringIncludes(r2.aviso, "parcelas a receber NÃO foram reajustadas (o banco não devolveu o id de ORÇ-00112)");
});

Deno.test("restaurar (execute): gravação de parcela que falha NÃO vira 'nenhuma parcela precisou mudar'", async () => {
  const { ctx } = ambiente();
  const fromOriginal = ctx.sb.from.bind(ctx.sb);
  ctx.sb.from = (t: string) => {
    const q = fromOriginal(t);
    if (t === "receivables") q.update = () => ({ eq: () => Promise.resolve({ data: null, error: { message: "permission denied" } }) });
    return q;
  };
  const r = await tool("restaurar_documento").execute({ documento: "ORÇ-00112", versao: 2, _retrato: { hash_do_documento: "h" } }, ctx) as any;
  assertEquals(r.restaurado, true);
  assertEquals(/precisou mudar/.test(r.aviso), false, r.aviso);
  assertStringIncludes(r.aviso, "1 parcela a receber NÃO foi reajustada (a gravação falhou): confira o financeiro de ORÇ-00112.");
});

// ── registro e ensino ────────────────────────────────────────────────────────────────────────

Deno.test("registro: as duas estão em allTools; consultar roda direto pela rede; restaurar é alto, nunca autônomo e fica no WhatsApp", () => {
  const nomes = new Set(allTools.map((t) => t.name));
  assert(nomes.has("consultar_historico_documento") && nomes.has("restaurar_documento"));
  const consultar = tool("consultar_historico_documento");
  const restaurar = tool("restaurar_documento");
  assertEquals(consultar.risk, "low");
  assertEquals(restaurar.risk, "high");
  assertEquals(consultar.roles, CARGOS_DO_HISTORICO);
  assertEquals(restaurar.roles, CARGOS_DO_HISTORICO);
  assertEquals(SO_PELA_REDE.has("consultar_historico_documento"), true);
  assertEquals(rodaDiretoPelaRede(consultar), true);
  assertEquals(NEVER_AUTONOMOUS.has("restaurar_documento"), true);
  assertEquals(restaurar.gravarSolicitante, true);
  for (const n of ["consultar_historico_documento", "restaurar_documento"]) {
    assertEquals(FORA_DO_WHATSAPP.has(n), false, `${n} fora do WhatsApp`);
    assertEquals(PERFIL_ADMIN.has(n), false, `${n} no teto do admin`);
    assertEquals(PERFIL_OPERACAO.has(n), false, `${n} no perfil`);
  }
  assertEquals(tituloDaAcao("restaurar_documento"), "Restaurar orçamento/OS (desfazer ou voltar versão)");
  assertEquals(tituloDaAcao("consultar_historico_documento"), "Ver o histórico do documento");
});
