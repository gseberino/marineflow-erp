import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { ferramentasDoJob } from "./ferramentas-do-job.ts";
import { SO_PELA_REDE } from "../perfil-operacao.ts";
import type { ToolDef } from "../tools/index.ts";

const tool = (name: string, roles?: string[]): ToolDef =>
  ({ name, description: name, input_schema: { type: "object" }, risk: "low", ...(roles ? { roles } : {}), execute: async () => ({}) }) as unknown as ToolDef;

const daRede = [...SO_PELA_REDE][0]!;
const todas = [tool("search_clients"), tool("so_admin", ["admin"]), tool(daRede), tool("comum_fora_da_rede"), tool("get_financial_dre")];

Deno.test("só sobram os nomes que o cargo atual e o canal liberam", () => {
  const r = ferramentasDoJob("technician" as never, ["search_clients", "so_admin", "nao_existe", 42], [], "whatsapp", todas);
  assertEquals(Object.keys(r.toolsByName), ["search_clients"]);
});

Deno.test("rede: só nomes de SO_PELA_REDE, mesmo que o job peça outro", () => {
  const r = ferramentasDoJob("admin" as never, [], [daRede, "comum_fora_da_rede", "so_admin"], "whatsapp", todas);
  assertEquals(Object.keys(r.alcancaveisPelaRede), [daRede]);
});

Deno.test("entrada que não é lista vira nada", () => {
  const r = ferramentasDoJob("admin" as never, "search_clients", { a: 1 }, "whatsapp", todas);
  assertEquals(r, { toolsByName: {}, alcancaveisPelaRede: {} });
});

Deno.test("canal do painel não aplica o corte do WhatsApp", () => {
  const nomes = ["search_clients", "get_financial_dre"];
  assertEquals(Object.keys(ferramentasDoJob("admin" as never, nomes, [], "whatsapp", todas).toolsByName), ["search_clients"]);
  assertEquals(Object.keys(ferramentasDoJob("admin" as never, nomes, [], "panel", todas).toolsByName), nomes);
});
