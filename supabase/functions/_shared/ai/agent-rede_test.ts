// Rede de segurança do perfil de tools (agent.ts, 26/09/2026).
//
// O caso real: em 25/09 o dono pediu "me manda o PDF do orçamento", o prompt ensinava
// send_document_pdf_to_self, o perfil a escondia, e o modelo recebeu "Tool desconhecida".
// Estes testes provam que a rede alcança o que o prompt ensina (SO_PELA_REDE) SEM furar cargo
// nem canal — e que ela NÃO alcança nada além disso: vários `roles` são frouxos, e a rede não
// pode devolver a vendedor/técnico o que o perfil escondia.
// Rodar com:
//   deno test --allow-all supabase/functions/_shared/ai/agent-rede_test.ts
import { assert, assertEquals, assertExists, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { runAgentLoop, validarArgumentosDaTool } from "./agent.ts";
import { NEVER_AUTONOMOUS } from "./autonomy-policy.ts";
import { filtrarPorCanal } from "./channel-scope.ts";
import { ESCRITAS_VERIFICADAS_DA_REDE, PERFIL_OPERACAO, SO_PELA_REDE } from "./perfil-operacao.ts";
import { allTools, type Role, type ToolDef } from "./tools/index.ts";

Deno.env.set("OPENROUTER_API_KEY", "test-key-not-real");

// ---------- mesmo mock de fetch/OpenRouter de agent_test.ts ----------
type Resp = { status: number; body: unknown };
function mockFetchSequence(responses: Resp[]) {
  let i = 0;
  const calls: Array<{ url: string; init?: RequestInit }> = [];
  const fetchStub: typeof globalThis.fetch = (input, init) => {
    calls.push({ url: typeof input === "string" ? input : (input as Request).url, init });
    const r = responses[Math.min(i, responses.length - 1)];
    i++;
    return Promise.resolve(new Response(JSON.stringify(r.body), { status: r.status, headers: { "Content-Type": "application/json" } }));
  };
  return { fetchStub, calls };
}

function withFetch<T>(stub: typeof globalThis.fetch, fn: () => Promise<T>): Promise<T> {
  const original = globalThis.fetch;
  globalThis.fetch = stub;
  return fn().finally(() => {
    globalThis.fetch = original;
  });
}

/** Resposta do modelo no formato OpenAI-shape que o OpenRouter devolve. */
function chamaTool(name: string, input: unknown, id = "toolu_1"): Resp {
  return {
    status: 200,
    body: {
      id: "gen_test",
      choices: [{
        message: { role: "assistant", content: null, tool_calls: [{ id, type: "function", function: { name, arguments: JSON.stringify(input) } }] },
        finish_reason: "tool_calls",
      }],
      usage: { prompt_tokens: 100, completion_tokens: 20, prompt_tokens_details: { cached_tokens: 0, cache_write_tokens: 0 } },
    },
  };
}
function respondeTexto(text: string): Resp {
  return {
    status: 200,
    body: {
      id: "gen_test",
      choices: [{ message: { role: "assistant", content: text }, finish_reason: "stop" }],
      usage: { prompt_tokens: 100, completion_tokens: 20, prompt_tokens_details: { cached_tokens: 0, cache_write_tokens: 0 } },
    },
  };
}

/** Nomes das tools que o modelo recebeu na chamada n (0 = primeira). */
function toolsEnviadas(calls: Array<{ init?: RequestInit }>, n = 0): string[] {
  const body = JSON.parse(String(calls[n].init?.body ?? "{}"));
  return ((body.tools ?? []) as Array<{ function: { name: string } }>).map((t) => t.function.name);
}

// ---------- fake do client service-role, com o perfil 'operacao' LIGADO ----------
function fakeAdmin() {
  const auditRows: any[] = [];
  const pendingRows: any[] = [];
  let seq = 0;
  const admin = {
    from(table: string) {
      return {
        select() {
          // app_settings: o liga/desliga do perfil. Qualquer outra tabela não é consultável
          // aqui — uma tool real que tente ler cai no catch do loop, como erro de execução.
          return { in: async () => ({ data: table === "app_settings" ? [{ key: "ai_tool_profile", value: "operacao" }] : [], error: null }) };
        },
        insert(row: any) {
          if (table === "ai_operator_audit") auditRows.push(row);
          if (table === "ai_operator_pending_actions") pendingRows.push(row);
          const id = `pending-${++seq}`;
          return {
            select: () => ({ single: async () => ({ data: { id, title: row.title, summary: row.summary, risk_level: row.risk_level }, error: null }) }),
            then: (resolve: (v: unknown) => void) => resolve({ data: null, error: null }),
          };
        },
      };
    },
  };
  return { admin, auditRows, pendingRows };
}

function montar(opts: { tools: ToolDef[]; role?: Role; settings?: Record<string, string>; channel?: "panel" | "whatsapp"; pedido?: string }) {
  const { admin, auditRows, pendingRows } = fakeAdmin();
  const params = {
    system: [{ type: "text" as const, text: "teste" }],
    sessionId: "sessao-rede",
    channel: opts.channel ?? "panel",
    tools: opts.tools,
    messages: [{ role: "user" as const, content: [{ type: "text" as const, text: opts.pedido ?? "oi" }] }],
    toolCtx: { sb: {}, admin, userId: "u1", userRole: opts.role ?? "admin", jwt: "jwt", appOrigin: "", settings: opts.settings ?? {} },
  };
  return { params, auditRows, pendingRows };
}

/** Mesmo filtro de cargo do ai-agent/index.ts (painel e WhatsApp). */
function porCargo(role: Role): ToolDef[] {
  return allTools.filter((t) => !t.roles || t.roles.includes(role));
}

/** Só as marcas da rede na auditoria. */
function marcasDaRede(auditRows: any[]): Array<{ tool: string; desfecho: string }> {
  return auditRows
    .filter((a) => String(a.event_type).startsWith("fora_do_perfil:"))
    .map((a) => ({ tool: String(a.event_type).slice("fora_do_perfil:".length), desfecho: a.payload.desfecho }));
}

// ---------- tools REAIS de SO_PELA_REDE, com o execute trocado por um registro ----------
// Nome, esquema, risco e cargos são os de verdade — só o execute é falso (o banco é fake).
const porNomeReal = new Map(allTools.map((t) => [t.name, t]));
let execucoes: string[] = [];

function comExecuteFalso(nome: string, resposta: (args: Record<string, unknown>) => unknown = () => ({ ok: true })): ToolDef {
  const real = porNomeReal.get(nome);
  if (!real) throw new Error(`${nome} não existe em allTools`);
  return {
    ...real,
    async execute(args) {
      execucoes.push(nome);
      return await resposta(args);
    },
  };
}

const LEITURA = "get_comms_log"; // leitura, risco low
const ESCRITA_VERIFICADA = "interpret_customer_reply"; // escrita de baixo impacto verificada, risco low
const ESCRITA_MEDIA = "remove_service_order_expense"; // escrita de risco medium
const ESCRITA_MEDIA_AUTONOMIZAVEL = "remove_service_order_step"; // medium e fora de NEVER_AUTONOMOUS
const COM_ESQUEMA = "list_entity_notes"; // obrigatórios e enum, para a validação de argumentos

// ---------- tool SINTÉTICA de escrita, FORA do perfil e FORA de SO_PELA_REDE ----------
const escritaSintetica: ToolDef = {
  name: "update_rede_teste",
  description: "escrita sintética: o computeRisk diz que é low",
  input_schema: { type: "object", properties: { id: { type: "string" } }, required: ["id"] },
  risk: "medium",
  computeRisk: () => "low",
  async execute() {
    execucoes.push("update_rede_teste");
    return { ok: true };
  },
};

Deno.test("rede: premissas — as tools usadas aqui estão onde os testes supõem", () => {
  for (const n of [LEITURA, ESCRITA_VERIFICADA, ESCRITA_MEDIA, ESCRITA_MEDIA_AUTONOMIZAVEL, COM_ESQUEMA]) {
    assertEquals(SO_PELA_REDE.has(n), true, `${n} fora de SO_PELA_REDE`);
    assertEquals(PERFIL_OPERACAO.has(n), false, `${n} está no perfil`);
  }
  assertEquals(porNomeReal.get(LEITURA)!.risk, "low");
  assertEquals(porNomeReal.get(ESCRITA_VERIFICADA)!.risk, "low");
  assertEquals(ESCRITA_VERIFICADA in ESCRITAS_VERIFICADAS_DA_REDE, true);
  assertEquals(porNomeReal.get(ESCRITA_MEDIA)!.risk, "medium");
  assertEquals(porNomeReal.get(ESCRITA_MEDIA_AUTONOMIZAVEL)!.risk, "medium");
  assertEquals(NEVER_AUTONOMOUS.has(ESCRITA_MEDIA_AUTONOMIZAVEL), false);
  assertEquals(SO_PELA_REDE.has(escritaSintetica.name), false);
  assertEquals(PERFIL_OPERACAO.has(escritaSintetica.name), false);
});

Deno.test("rede: leitura de SO_PELA_REDE roda direto e deixa a marca fora_do_perfil", async () => {
  execucoes = [];
  const { params, auditRows, pendingRows } = montar({ tools: [comExecuteFalso(LEITURA, (a) => ({ lido: a.entity_id }))] });
  const { fetchStub, calls } = mockFetchSequence([chamaTool(LEITURA, { entity_id: "c1" }), respondeTexto("feito")]);
  const r = await withFetch(fetchStub, () => runAgentLoop(params));
  // Escondida do modelo (não foi no bloco de tools) e mesmo assim alcançada.
  assertEquals(toolsEnviadas(calls).includes(LEITURA), false);
  assertEquals(execucoes, [LEITURA]);
  assertEquals(r.toolEvents[0].result, { lido: "c1" });
  assertEquals(pendingRows.length, 0);
  assertEquals(auditRows.map((a) => a.event_type), [`tool:${LEITURA}`, `fora_do_perfil:${LEITURA}`]);
  assertEquals(marcasDaRede(auditRows), [{ tool: LEITURA, desfecho: "executada" }]);
  assertEquals(r.message.content, "feito");
});

Deno.test("rede: escrita de baixo impacto verificada roda direto — o turno segue e a resposta chega no WhatsApp", async () => {
  // Antes virava pendência: o turno parava na proposta e, no WhatsApp, a resposta do modelo sumia.
  execucoes = [];
  const { params, auditRows, pendingRows } = montar({
    tools: [comExecuteFalso(ESCRITA_VERIFICADA, () => ({ intencao: "disputa" }))],
    channel: "whatsapp",
  });
  const { fetchStub } = mockFetchSequence([
    chamaTool(ESCRITA_VERIFICADA, { text: "já paguei semana passada", entity_kind: "client", entity_id: "c1" }),
    respondeTexto("Ele diz que já pagou — não reenvio a cobrança e te passo o caso."),
  ]);
  const r = await withFetch(fetchStub, () => runAgentLoop(params));
  assertEquals(execucoes, [ESCRITA_VERIFICADA]);
  assertEquals(r.proposal, undefined);
  assertEquals(pendingRows.length, 0);
  assertEquals(r.message.content, "Ele diz que já pagou — não reenvio a cobrança e te passo o caso.");
  assertEquals(auditRows.map((a) => a.event_type), [`tool:${ESCRITA_VERIFICADA}`, `fora_do_perfil:${ESCRITA_VERIFICADA}`]);
  assertEquals(marcasDaRede(auditRows), [{ tool: ESCRITA_VERIFICADA, desfecho: "executada" }]);
});

Deno.test("rede: escrita de risco medium de SO_PELA_REDE vira pendência e NÃO executa", async () => {
  execucoes = [];
  const { params, auditRows, pendingRows } = montar({ tools: [comExecuteFalso(ESCRITA_MEDIA)] });
  const { fetchStub } = mockFetchSequence([chamaTool(ESCRITA_MEDIA, { expense_id: "x1" })]);
  const r = await withFetch(fetchStub, () => runAgentLoop(params));
  assertEquals(execucoes, []);
  assertExists(r.proposal);
  assertEquals(r.proposal?.risk_level, "medium");
  assertEquals(pendingRows.length, 1);
  assertEquals(pendingRows[0].action_name, ESCRITA_MEDIA);
  assertEquals(pendingRows[0].payload, { expense_id: "x1" });
  assertEquals(auditRows.map((a) => a.event_type), [`pending_action:${ESCRITA_MEDIA}`, `fora_do_perfil:${ESCRITA_MEDIA}`]);
  assertEquals(marcasDaRede(auditRows), [{ tool: ESCRITA_MEDIA, desfecho: "pendencia" }]);
});

Deno.test("rede: autonomia concedida não dispensa a confirmação pela rede (mas vale com a tool à vista)", async () => {
  const settings = { [`ai_autonomy_${ESCRITA_MEDIA_AUTONOMIZAVEL}`]: "auto" };

  // Pela rede: pendência, mesmo com autonomia.
  execucoes = [];
  const pelaRede = montar({ tools: [comExecuteFalso(ESCRITA_MEDIA_AUTONOMIZAVEL)], settings });
  const s1 = mockFetchSequence([chamaTool(ESCRITA_MEDIA_AUTONOMIZAVEL, { step_id: "p1" })]);
  const r1 = await withFetch(s1.fetchStub, () => runAgentLoop(pelaRede.params));
  assertEquals(execucoes, []);
  assertEquals(pelaRede.pendingRows.length, 1);
  assertExists(r1.proposal);

  // Controle: o nome no pedido põe a tool à vista → a autonomia vale e ela roda sozinha.
  execucoes = [];
  const aVista = montar({ tools: [comExecuteFalso(ESCRITA_MEDIA_AUTONOMIZAVEL)], settings, pedido: `use a ${ESCRITA_MEDIA_AUTONOMIZAVEL} no p1` });
  const s2 = mockFetchSequence([chamaTool(ESCRITA_MEDIA_AUTONOMIZAVEL, { step_id: "p1" }), respondeTexto("feito")]);
  await withFetch(s2.fetchStub, () => runAgentLoop(aVista.params));
  assertEquals(toolsEnviadas(s2.calls).includes(ESCRITA_MEDIA_AUTONOMIZAVEL), true);
  assertEquals(execucoes, [ESCRITA_MEDIA_AUTONOMIZAVEL]);
  assertEquals(aVista.pendingRows.length, 0);
});

Deno.test("rede: escrita sintética com computeRisk 'low' FORA de SO_PELA_REDE não roda — é 'Tool desconhecida'", async () => {
  // Liberada por cargo e canal (está em params.tools), escondida pelo perfil, e parece inofensiva
  // pelo computeRisk. Nada disso a põe na rede: só SO_PELA_REDE entra.
  for (const risk of ["low", "medium"] as const) {
    execucoes = [];
    const { params, auditRows, pendingRows } = montar({ tools: [{ ...escritaSintetica, risk }] });
    const { fetchStub } = mockFetchSequence([chamaTool(escritaSintetica.name, { id: "x1" }), respondeTexto("ok")]);
    const r = await withFetch(fetchStub, () => runAgentLoop(params));
    assertEquals(r.toolEvents[0].result, { error: `Tool desconhecida: ${escritaSintetica.name}` }, `risk ${risk}`);
    assertEquals(execucoes, [], `risk ${risk}`);
    assertEquals(pendingRows.length, 0, `risk ${risk}`);
    assertEquals(auditRows.length, 0, `risk ${risk}`);
  }

  // Controle: a mesma tool À VISTA (nome no pedido) roda direto pelo computeRisk — então o que a
  // barrou acima foi o limite da rede, não outra coisa.
  execucoes = [];
  const aVista = montar({ tools: [escritaSintetica], pedido: `usa a ${escritaSintetica.name} no x1` });
  const s = mockFetchSequence([chamaTool(escritaSintetica.name, { id: "x1" }), respondeTexto("ok")]);
  await withFetch(s.fetchStub, () => runAgentLoop(aVista.params));
  assertEquals(execucoes, [escritaSintetica.name]);
});

Deno.test("rede: em SO_PELA_REDE, declarada medium e rebaixada a low pelo computeRisk, pede confirmação", async () => {
  // Pela rede vale o risco que a tool DECLARA e o que ela CALCULA — os dois têm de ser low.
  execucoes = [];
  const rebaixada: ToolDef = { ...comExecuteFalso(ESCRITA_VERIFICADA), risk: "medium", computeRisk: () => "low" };
  const { params, pendingRows } = montar({ tools: [rebaixada] });
  const { fetchStub } = mockFetchSequence([chamaTool(ESCRITA_VERIFICADA, { text: "ok, pode mandar o pix" })]);
  const r = await withFetch(fetchStub, () => runAgentLoop(params));
  assertEquals(execucoes, []);
  assertEquals(pendingRows.length, 1);
  assertEquals(r.proposal?.risk_level, "medium");
});

Deno.test("rede: argumento inválido volta com o input_schema, nada roda, e a segunda tentativa certa executa", async () => {
  execucoes = [];
  const tool = comExecuteFalso(COM_ESQUEMA, (a) => ({ notas_de: a.entity_id }));
  const { params, auditRows } = montar({ tools: [tool] });
  const { fetchStub, calls } = mockFetchSequence([
    chamaTool(COM_ESQUEMA, { scope: "boat", extra: 1 }, "toolu_a"),
    chamaTool(COM_ESQUEMA, { scope: "client", entity_id: "c1" }, "toolu_b"),
    respondeTexto("pronto"),
  ]);
  const r = await withFetch(fetchStub, () => runAgentLoop(params));
  assertEquals(calls.length, 3);
  const erro = r.toolEvents[0].result as { error: string; input_schema: unknown; instruction: string };
  assertStringIncludes(erro.error, "falta o campo obrigatório 'entity_id'");
  assertStringIncludes(erro.error, "'scope' aceita só: client, vessel, supplier");
  assertStringIncludes(erro.error, "o campo 'extra' não existe");
  assertEquals(erro.input_schema, tool.input_schema);
  // A primeira não executou; a segunda, com os argumentos certos, sim.
  assertEquals(execucoes, [COM_ESQUEMA]);
  assertEquals(r.toolEvents[1].result, { notas_de: "c1" });
  assertEquals(marcasDaRede(auditRows).map((m) => m.desfecho), ["argumentos_invalidos", "executada"]);
});

Deno.test("rede: tool que rodou mas devolveu { error } (ou lançou) fica como 'falha_na_execucao', não 'executada'", async () => {
  const falhas: Array<[string, () => unknown]> = [
    ["devolve error", () => ({ error: "sem acesso ao histórico" })],
    ["lança", () => {
      throw new Error("conexão caiu");
    }],
  ];
  for (const [caso, resposta] of falhas) {
    execucoes = [];
    const { params, auditRows } = montar({ tools: [comExecuteFalso(LEITURA, resposta)] });
    const { fetchStub } = mockFetchSequence([chamaTool(LEITURA, {}), respondeTexto("não consegui")]);
    const r = await withFetch(fetchStub, () => runAgentLoop(params));
    assertEquals(execucoes, [LEITURA], caso);
    assert(String((r.toolEvents[0].result as { error?: string }).error ?? "").length > 0, caso);
    assertEquals(marcasDaRede(auditRows), [{ tool: LEITURA, desfecho: "falha_na_execucao" }], caso);
  }
});

Deno.test("rede: tool que não existe continua 'Tool desconhecida' e não deixa marca", async () => {
  const { params, auditRows, pendingRows } = montar({ tools: [comExecuteFalso(LEITURA)] });
  const { fetchStub } = mockFetchSequence([chamaTool("nao_existe_em_lugar_nenhum", {}), respondeTexto("ok")]);
  const r = await withFetch(fetchStub, () => runAgentLoop(params));
  assertEquals(r.toolEvents[0].result, { error: "Tool desconhecida: nao_existe_em_lugar_nenhum" });
  assertEquals(auditRows.length, 0);
  assertEquals(pendingRows.length, 0);
});

Deno.test("rede limitada a SO_PELA_REDE: role frouxo não devolve a vendedor/técnico o que o perfil escondia", async () => {
  // Listas REAIS, com o mesmo filtro de cargo do ai-agent. Em todos os casos o cargo LIBERA a
  // tool (roles ausente ou largo demais), o perfil a esconde, e ela não está em SO_PELA_REDE.
  const casos: Array<{ role: Role; tool: string; args: Record<string, unknown> }> = [
    { role: "external_seller", tool: "get_technician_commissions", args: {} },
    { role: "technician", tool: "create_purchase_order", args: { supplier_id: "s1" } },
    { role: "technician", tool: "list_unidentified_contacts", args: {} },
    // Nem o admin: fora do perfil e de SO_PELA_REDE, só pelo nome no pedido.
    { role: "admin", tool: "get_financial_dre", args: { year: 2026, month: 9 } },
  ];
  for (const c of casos) {
    const rotulo = `${c.role} × ${c.tool}`;
    const tools = porCargo(c.role);
    assertEquals(tools.some((t) => t.name === c.tool), true, `${rotulo}: o cargo não libera — premissa quebrou`);
    assertEquals(PERFIL_OPERACAO.has(c.tool), false, rotulo);
    assertEquals(SO_PELA_REDE.has(c.tool), false, rotulo);

    const { params, auditRows, pendingRows } = montar({ tools, role: c.role });
    const { fetchStub } = mockFetchSequence([chamaTool(c.tool, c.args), respondeTexto("ok")]);
    const r = await withFetch(fetchStub, () => runAgentLoop(params));
    assertEquals(r.toolEvents[0].result, { error: `Tool desconhecida: ${c.tool}` }, rotulo);
    assertEquals(pendingRows.length, 0, rotulo);
    assertEquals(auditRows.length, 0, rotulo);
  }
});

Deno.test("rede: de SO_PELA_REDE, alcança só o que o cargo libera (técnico: passo do roteiro sim, memória não)", async () => {
  const REORDENAR = "reorder_service_order_step"; // sem roles
  const MEMORIA = "remember_about_entity"; // NON_TECHNICIAN_ROLES
  assertEquals(SO_PELA_REDE.has(REORDENAR) && SO_PELA_REDE.has(MEMORIA), true);
  const tools = porCargo("technician").map((t) => (t.name === REORDENAR ? comExecuteFalso(REORDENAR) : t));
  assertEquals(tools.some((t) => t.name === MEMORIA), false);

  execucoes = [];
  const a = montar({ tools, role: "technician" });
  const sa = mockFetchSequence([chamaTool(REORDENAR, { step_id: "p1", direction: "up" }), respondeTexto("feito")]);
  await withFetch(sa.fetchStub, () => runAgentLoop(a.params));
  assertEquals(execucoes, [REORDENAR]);
  assertEquals(marcasDaRede(a.auditRows), [{ tool: REORDENAR, desfecho: "executada" }]);

  const b = montar({ tools, role: "technician" });
  const sb = mockFetchSequence([chamaTool(MEMORIA, { scope: "client", entity_id: "c1", title: "t", body: "b" }), respondeTexto("ok")]);
  const rb = await withFetch(sb.fetchStub, () => runAgentLoop(b.params));
  assertEquals(rb.toolEvents[0].result, { error: `Tool desconhecida: ${MEMORIA}` });
  assertEquals(b.auditRows.length, 0);
  assertEquals(b.pendingRows.length, 0);
});

Deno.test("rede: técnico NÃO alcança tool financeira — nem a escondida pelo perfil, nem a que o perfil lista", async () => {
  // Lista real, com o mesmo filtro de cargo do ai-agent. get_financial_dre está fora do perfil;
  // lancar_no_caixa está no perfil — as duas são só de quem não é técnico.
  const tools = porCargo("technician");
  assertEquals(tools.some((t) => t.name === "get_financial_dre"), false);
  for (const nome of ["get_financial_dre", "lancar_no_caixa"]) {
    const { params, auditRows, pendingRows } = montar({ tools, role: "technician" });
    const { fetchStub } = mockFetchSequence([chamaTool(nome, { year: 2026, month: 9, valor: 10 }), respondeTexto("ok")]);
    const r = await withFetch(fetchStub, () => runAgentLoop(params));
    assertEquals(r.toolEvents[0].result, { error: `Tool desconhecida: ${nome}` }, nome);
    assertEquals(pendingRows.length, 0, nome);
    assertEquals(marcasDaRede(auditRows).length, 0, nome);
  }
});

Deno.test("rede: tool FORA_DO_WHATSAPP de SO_PELA_REDE não é alcançada no WhatsApp (no painel é)", async () => {
  const CONFIG = "get_autonomy_settings"; // SO_PELA_REDE e FORA_DO_WHATSAPP, sem roles
  assertEquals(SO_PELA_REDE.has(CONFIG), true);
  const doAdmin = porCargo("admin").map((t) => (t.name === CONFIG ? comExecuteFalso(CONFIG, () => ({ liberadas: [] })) : t));

  // Mesma ordem do ai-agent no WhatsApp: cargo, depois canal.
  execucoes = [];
  const noWhatsapp = filtrarPorCanal(doAdmin, "whatsapp");
  assertEquals(noWhatsapp.some((t) => t.name === CONFIG), false);
  const w = montar({ tools: noWhatsapp, channel: "whatsapp" });
  const sw = mockFetchSequence([chamaTool(CONFIG, {}), respondeTexto("ok")]);
  const rw = await withFetch(sw.fetchStub, () => runAgentLoop(w.params));
  assertEquals(rw.toolEvents[0].result, { error: `Tool desconhecida: ${CONFIG}` });
  assertEquals(w.auditRows.length, 0);
  assertEquals(execucoes, []);

  // Controle: no painel o admin alcança pela rede (é leitura; a marca prova que passou por ela).
  const p = montar({ tools: doAdmin, channel: "panel" });
  const sp = mockFetchSequence([chamaTool(CONFIG, {}), respondeTexto("ok")]);
  await withFetch(sp.fetchStub, () => runAgentLoop(p.params));
  assertEquals(toolsEnviadas(sp.calls).includes(CONFIG), false);
  assertEquals(execucoes, [CONFIG]);
  assertEquals(marcasDaRede(p.auditRows), [{ tool: CONFIG, desfecho: "executada" }]);
});

Deno.test("dado real (26/09 00:00 UTC, WhatsApp, admin): a chamada que deu 'Tool desconhecida' agora é aceita", () => {
  // Único 'Tool desconhecida' da história (SELECT em ai_operator_messages): "Me envia o
  // orçamento 108 em PDF." → send_document_pdf_to_self com estes argumentos, exatamente.
  const argsReais = { documento: "108", tipo: "orcamento" };
  const noWhatsapp = filtrarPorCanal(porCargo("admin"), "whatsapp");
  const tool = noWhatsapp.find((t) => t.name === "send_document_pdf_to_self");
  assertExists(tool, "a tool tem de estar liberada para admin no WhatsApp");
  assertEquals(validarArgumentosDaTool(tool.input_schema, argsReais), []);
  // Está no PERFIL (não na rede): vai à vista do modelo e roda sem confirmação, como o prompt
  // promete ("Não pede confirmação").
  assertEquals(PERFIL_OPERACAO.has("send_document_pdf_to_self"), true);
  assertEquals(SO_PELA_REDE.has("send_document_pdf_to_self"), false);
});

Deno.test("validarArgumentosDaTool: casos de borda", () => {
  const schema = { type: "object", properties: { a: { type: "string" }, lista: { type: "array", items: { type: "string", enum: ["x", "y"] } } }, required: ["a"] };
  assertEquals(validarArgumentosDaTool(schema, { a: "1" }), []);
  assertEquals(validarArgumentosDaTool(schema, { a: "1", lista: ["x", "y"] }), []);
  assertEquals(validarArgumentosDaTool(schema, { a: "1", lista: ["z"] }), ["'lista' aceita só: x, y"]);
  assertEquals(validarArgumentosDaTool(schema, { a: "" }), ["falta o campo obrigatório 'a'"]);
  assertEquals(validarArgumentosDaTool(schema, null).length, 1);
  assertEquals(validarArgumentosDaTool(schema, ["a"]).length, 1);
  // Opcional ausente ou nulo não é problema.
  assertEquals(validarArgumentosDaTool({ type: "object", properties: { b: { type: "string", enum: ["p"] } } }, { b: null }), []);
});

Deno.test("validarArgumentosDaTool: nenhum schema real de allTools recusa uma chamada mínima válida", () => {
  // Rejeitar demais custa tanto quanto aceitar errado: com só os obrigatórios preenchidos (e o
  // primeiro valor do enum, quando houver), toda tool real tem de passar.
  for (const t of allTools) {
    const s = t.input_schema as { properties?: Record<string, { enum?: unknown[] }>; required?: string[] };
    const args: Record<string, unknown> = {};
    for (const campo of s.required ?? []) args[campo] = s.properties?.[campo]?.enum?.[0] ?? "valor";
    assertEquals(validarArgumentosDaTool(t.input_schema, args), [], t.name);
  }
});
