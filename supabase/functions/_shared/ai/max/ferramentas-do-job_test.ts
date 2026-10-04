import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { ferramentasDoJob } from "./ferramentas-do-job.ts";
import { SO_PELA_REDE } from "../perfil-operacao.ts";
import type { ToolDef } from "../tools/index.ts";

const tool = (name: string, roles?: string[]): ToolDef =>
  ({ name, description: name, input_schema: { type: "object" }, risk: "low", ...(roles ? { roles } : {}), execute: async () => ({}) }) as unknown as ToolDef;

const daRede = [...SO_PELA_REDE][0]!;
const todas = [tool("search_clients"), tool("so_admin", ["admin"]), tool(daRede), tool("comum_fora_da_rede")];

Deno.test("só sobram os nomes que o cargo atual e o canal liberam", () => {
  const r = ferramentasDoJob("technician" as never, ["search_clients", "so_admin", "nao_existe", 42], [], todas);
  assertEquals(Object.keys(r.toolsByName), ["search_clients"]);
});

Deno.test("rede: só nomes de SO_PELA_REDE, mesmo que o job peça outro", () => {
  const r = ferramentasDoJob("admin" as never, [], [daRede, "comum_fora_da_rede", "so_admin"], todas);
  assertEquals(Object.keys(r.alcancaveisPelaRede), [daRede]);
});

Deno.test("entrada que não é lista vira nada", () => {
  const r = ferramentasDoJob("admin" as never, "search_clients", { a: 1 }, todas);
  assertEquals(r, { toolsByName: {}, alcancaveisPelaRede: {} });
});
