// Rede de segurança do perfil de tools (agent.ts, 26/09/2026).
//
// O caso real: em 25/09 o dono pediu "me manda o PDF do orçamento", o prompt ensinava
// send_document_pdf_to_self, o perfil a escondia, e o modelo recebeu "Tool desconhecida".
// Estes testes provam que a rede alcança o que o prompt ensina SEM furar cargo nem canal.
// Rodar com:
//   deno test --allow-all supabase/functions/_shared/ai/agent-rede_test.ts
import { assert, assertEquals, assertExists, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { ehLeituraPeloNome, runAgentLoop, validarArgumentosDaTool } from "./agent.ts";
import { filtrarPorCanal } from "./channel-scope.ts";
import { PERFIL_OPERACAO } from "./perfil-operacao.ts";
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

// ---------- tools sintéticas, todas FORA do perfil ----------
let execucoes: string[] = [];
const leitura: ToolDef = {
  name: "get_rede_teste",
  description: "leitura de teste",
  input_schema: { type: "object", properties: { foo: { type: "string" }, modo: { type: "string", enum: ["a", "b"] } }, required: ["foo"] },
  risk: "low",
  async execute(args) {
    execucoes.push("get_rede_teste");
    return { lido: args.foo };
  },
};
const escrita: ToolDef = {
  name: "update_rede_teste",
  description: "escrita de teste, risco baixo",
  input_schema: { type: "object", properties: { id: { type: "string" } }, required: ["id"] },
  risk: "low",
  async execute() {
    execucoes.push("update_rede_teste");
    return { ok: true };
  },
};
const escritaMedia: ToolDef = {
  name: "remove_rede_teste",
  description: "escrita de teste, risco médio",
  input_schema: { type: "object", properties: { id: { type: "string" } }, required: ["id"] },
  risk: "medium",
  async execute() {
    execucoes.push("remove_rede_teste");
    return { removido: true };
  },
};

Deno.test("rede: as tools de teste estão mesmo fora do perfil (premissa dos testes abaixo)", () => {
  for (const t of [leitura, escrita, escritaMedia]) assertEquals(PERFIL_OPERACAO.has(t.name), false, t.name);
  assertEquals(ehLeituraPeloNome("get_x"), true);
  assertEquals(ehLeituraPeloNome("list_x"), true);
  assertEquals(ehLeituraPeloNome("read_x"), true);
  assertEquals(ehLeituraPeloNome("check_x"), true);
  assertEquals(ehLeituraPeloNome("search_x"), true);
  assertEquals(ehLeituraPeloNome("update_x"), false);
  assertEquals(ehLeituraPeloNome("interpret_customer_reply"), false);
});

Deno.test("rede: leitura fora do perfil roda direto e deixa a marca fora_do_perfil", async () => {
  execucoes = [];
  const { params, auditRows, pendingRows } = montar({ tools: [leitura] });
  const { fetchStub, calls } = mockFetchSequence([chamaTool("get_rede_teste", { foo: "bar" }), respondeTexto("feito")]);
  const r = await withFetch(fetchStub, () => runAgentLoop(params));
  // Escondida do modelo (não foi no bloco de tools) e mesmo assim alcançada.
  assertEquals(toolsEnviadas(calls).includes("get_rede_teste"), false);
  assertEquals(execucoes, ["get_rede_teste"]);
  assertEquals(r.toolEvents[0].result, { lido: "bar" });
  assertEquals(pendingRows.length, 0);
  assertEquals(auditRows.map((a) => a.event_type), ["tool:get_rede_teste", "fora_do_perfil:get_rede_teste"]);
  assertEquals(auditRows[1].payload.desfecho, "executada");
  assertEquals(r.message.content, "feito");
});

Deno.test("rede: escrita fora do perfil vira pendência (risco sobe de low para medium) e NÃO executa", async () => {
  execucoes = [];
  const { params, auditRows, pendingRows } = montar({ tools: [escrita] });
  const { fetchStub } = mockFetchSequence([chamaTool("update_rede_teste", { id: "x1" })]);
  const r = await withFetch(fetchStub, () => runAgentLoop(params));
  assertEquals(execucoes, []);
  assertExists(r.proposal);
  assertEquals(r.proposal?.risk_level, "medium");
  assertEquals(pendingRows.length, 1);
  assertEquals(pendingRows[0].action_name, "update_rede_teste");
  assertEquals(pendingRows[0].payload, { id: "x1" });
  assertEquals(auditRows.map((a) => a.event_type), ["pending_action:update_rede_teste", "fora_do_perfil:update_rede_teste"]);
  assertEquals(auditRows[1].payload.desfecho, "pendencia");
});

Deno.test("rede: autonomia concedida não dispensa a confirmação pela rede (mas vale com a tool à vista)", async () => {
  const settings = { ai_autonomy_remove_rede_teste: "auto" };

  // Pela rede: pendência, mesmo com autonomia.
  execucoes = [];
  const pelaRede = montar({ tools: [escritaMedia], settings });
  const s1 = mockFetchSequence([chamaTool("remove_rede_teste", { id: "x1" })]);
  const r1 = await withFetch(s1.fetchStub, () => runAgentLoop(pelaRede.params));
  assertEquals(execucoes, []);
  assertEquals(pelaRede.pendingRows.length, 1);
  assertExists(r1.proposal);

  // Controle: o nome no pedido põe a tool à vista → a autonomia vale e ela roda sozinha.
  execucoes = [];
  const aVista = montar({ tools: [escritaMedia], settings, pedido: "use a remove_rede_teste no x1" });
  const s2 = mockFetchSequence([chamaTool("remove_rede_teste", { id: "x1" }), respondeTexto("feito")]);
  await withFetch(s2.fetchStub, () => runAgentLoop(aVista.params));
  assertEquals(toolsEnviadas(s2.calls).includes("remove_rede_teste"), true);
  assertEquals(execucoes, ["remove_rede_teste"]);
  assertEquals(aVista.pendingRows.length, 0);
});

Deno.test("rede: argumento inválido volta com o input_schema, nada roda, e a segunda tentativa certa executa", async () => {
  execucoes = [];
  const { params, auditRows } = montar({ tools: [leitura] });
  const { fetchStub, calls } = mockFetchSequence([
    chamaTool("get_rede_teste", { modo: "c", extra: 1 }, "toolu_a"),
    chamaTool("get_rede_teste", { foo: "bar", modo: "a" }, "toolu_b"),
    respondeTexto("pronto"),
  ]);
  const r = await withFetch(fetchStub, () => runAgentLoop(params));
  assertEquals(calls.length, 3);
  const erro = r.toolEvents[0].result as { error: string; input_schema: unknown; instruction: string };
  assertStringIncludes(erro.error, "falta o campo obrigatório 'foo'");
  assertStringIncludes(erro.error, "'modo' aceita só: a, b");
  assertStringIncludes(erro.error, "o campo 'extra' não existe");
  assertEquals(erro.input_schema, leitura.input_schema);
  // A primeira não executou; a segunda, com os argumentos certos, sim.
  assertEquals(execucoes, ["get_rede_teste"]);
  assertEquals(r.toolEvents[1].result, { lido: "bar" });
  const marcas = auditRows.filter((a) => a.event_type === "fora_do_perfil:get_rede_teste").map((a) => a.payload.desfecho);
  assertEquals(marcas, ["argumentos_invalidos", "executada"]);
});

Deno.test("rede: tool que não existe continua 'Tool desconhecida' e não deixa marca", async () => {
  const { params, auditRows, pendingRows } = montar({ tools: [leitura] });
  const { fetchStub } = mockFetchSequence([chamaTool("nao_existe_em_lugar_nenhum", {}), respondeTexto("ok")]);
  const r = await withFetch(fetchStub, () => runAgentLoop(params));
  assertEquals(r.toolEvents[0].result, { error: "Tool desconhecida: nao_existe_em_lugar_nenhum" });
  assertEquals(auditRows.length, 0);
  assertEquals(pendingRows.length, 0);
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
    assertEquals(auditRows.filter((a) => String(a.event_type).startsWith("fora_do_perfil:")).length, 0, nome);
  }
});

Deno.test("rede: tool FORA_DO_WHATSAPP não é alcançada no WhatsApp (no painel é)", async () => {
  // Mesma ordem do ai-agent no WhatsApp: cargo, depois canal.
  const noWhatsapp = filtrarPorCanal(porCargo("admin"), "whatsapp");
  assertEquals(noWhatsapp.some((t) => t.name === "get_financial_dre"), false);
  const w = montar({ tools: noWhatsapp, channel: "whatsapp" });
  const sw = mockFetchSequence([chamaTool("get_financial_dre", { year: 2026, month: 9 }), respondeTexto("ok")]);
  const rw = await withFetch(sw.fetchStub, () => runAgentLoop(w.params));
  assertEquals(rw.toolEvents[0].result, { error: "Tool desconhecida: get_financial_dre" });
  assertEquals(w.auditRows.length, 0);

  // Controle: no painel o admin alcança pela rede (é leitura; a marca prova que passou por ela).
  const p = montar({ tools: porCargo("admin"), channel: "panel" });
  const sp = mockFetchSequence([chamaTool("get_financial_dre", { year: 2026, month: 9 }), respondeTexto("ok")]);
  const rp = await withFetch(sp.fetchStub, () => runAgentLoop(p.params));
  assertEquals(toolsEnviadas(sp.calls).includes("get_financial_dre"), false);
  assert(!String((rp.toolEvents[0].result as { error?: string }).error ?? "").includes("Tool desconhecida"));
  assertEquals(p.auditRows.some((a) => a.event_type === "fora_do_perfil:get_financial_dre"), true);
});

Deno.test("dado real (26/09 00:00 UTC, WhatsApp, admin): a chamada que deu 'Tool desconhecida' agora é aceita", () => {
  // Único 'Tool desconhecida' da história (SELECT em ai_operator_messages): "Me envia o
  // orçamento 108 em PDF." → send_document_pdf_to_self com estes argumentos, exatamente.
  const argsReais = { documento: "108", tipo: "orcamento" };
  const noWhatsapp = filtrarPorCanal(porCargo("admin"), "whatsapp");
  const tool = noWhatsapp.find((t) => t.name === "send_document_pdf_to_self");
  assertExists(tool, "a tool tem de estar liberada para admin no WhatsApp");
  assertEquals(validarArgumentosDaTool(tool.input_schema, argsReais), []);
  // Está no perfil: vai à vista do modelo e roda sem confirmação, como o prompt promete
  // ("Não pede confirmação"). Pela rede ela viraria pendência, por não ser leitura pelo nome.
  assertEquals(PERFIL_OPERACAO.has("send_document_pdf_to_self"), true);
  assertEquals(ehLeituraPeloNome("send_document_pdf_to_self"), false);
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
