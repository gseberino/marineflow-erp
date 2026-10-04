import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { AVISO_DE_INTERRUPCAO, responderMcp, type ServidorDoTurno } from "./mcp.ts";

function servidor(resultado: unknown, interrompe = false) {
  const chamadas: Array<{ nome: string; args: unknown }> = [];
  const srv: ServidorDoTurno = {
    listar: () => [{ name: "search_clients", description: "Busca clientes", input_schema: { type: "object", properties: { query: { type: "string" } } } }],
    chamar: async (nome, args) => {
      chamadas.push({ nome, args });
      return { resultado, interrompe };
    },
  };
  return { srv, chamadas };
}

Deno.test("initialize ecoa a versão do protocolo pedida e anuncia só ferramentas", async () => {
  const { srv } = servidor(null);
  const r = await responderMcp({ jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-06-18" } }, srv);
  assertEquals(r, {
    jsonrpc: "2.0",
    id: 1,
    result: { protocolVersion: "2025-06-18", capabilities: { tools: { listChanged: false } }, serverInfo: { name: "marineflow-erp", version: "1.0.0" } },
  });
});

Deno.test("notificação não tem resposta (HTTP 202)", async () => {
  const { srv } = servidor(null);
  assertEquals(await responderMcp({ jsonrpc: "2.0", method: "notifications/initialized" }, srv), null);
});

Deno.test("tools/list traduz input_schema para inputSchema", async () => {
  const { srv } = servidor(null);
  const r = await responderMcp({ jsonrpc: "2.0", id: "a", method: "tools/list" }, srv) as any;
  assertEquals(r.result.tools, [{ name: "search_clients", description: "Busca clientes", inputSchema: { type: "object", properties: { query: { type: "string" } } } }]);
});

Deno.test("tools/call executa e devolve o resultado em texto; erro da tool vira isError", async () => {
  const ok = servidor({ results: [{ id: "c1" }] });
  const r1 = await responderMcp({ jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: "search_clients", arguments: { query: "Lenine" } } }, ok.srv) as any;
  assertEquals(ok.chamadas, [{ nome: "search_clients", args: { query: "Lenine" } }]);
  assertEquals(r1.result, { content: [{ type: "text", text: '{"results":[{"id":"c1"}]}' }], isError: false });

  const falha = servidor({ error: "Tool desconhecida: rm_rf" });
  const r2 = await responderMcp({ jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "rm_rf" } }, falha.srv) as any;
  assertEquals(r2.result.isError, true);
  assertEquals(falha.chamadas[0].args, {});
});

Deno.test("pendência criada: o resultado leva o aviso para o modelo parar", async () => {
  const { srv } = servidor({ pending: true, pending_action_id: "p1" }, true);
  const r = await responderMcp({ jsonrpc: "2.0", id: 4, method: "tools/call", params: { name: "send_whatsapp_message", arguments: {} } }, srv) as any;
  assertEquals(r.result.content.length, 2);
  assertStringIncludes(r.result.content[1].text, "TURNO ENCERRADO");
  assertEquals(r.result.content[1].text, AVISO_DE_INTERRUPCAO);
});

Deno.test("método desconhecido, requisição inválida e tools/call sem nome", async () => {
  const { srv } = servidor(null);
  assertEquals((await responderMcp({ jsonrpc: "2.0", id: 5, method: "resources/list" }, srv) as any).error.code, -32601);
  assertEquals((await responderMcp({ id: 6, method: "ping" }, srv) as any).error.code, -32600);
  assertEquals((await responderMcp([{ jsonrpc: "2.0", id: 7, method: "ping" }], srv) as any).error.code, -32600);
  assertEquals((await responderMcp({ jsonrpc: "2.0", id: 8, method: "tools/call", params: {} }, srv) as any).error.code, -32602);
  assertEquals(await responderMcp({ jsonrpc: "2.0", id: 9, method: "ping" }, srv), { jsonrpc: "2.0", id: 9, result: {} });
});
