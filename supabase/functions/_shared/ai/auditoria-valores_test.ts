// Guarda (03/10/2026): todo event_category / actor_kind gravado em ai_operator_audit pelas edge
// functions tem de estar no CHECK da tabela. O confirm_action gravava 'learning' e o insert falhava
// calado — o dono aprovava/recusava com comentário e a auditoria simplesmente não existia.
// Se o CHECK mudar no banco, mude as listas abaixo junto (a migration e este teste andam juntos).
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

const CATEGORIAS = new Set(["info", "security", "data", "channel", "error"]);
const ATORES = new Set(["user", "ai_model", "system", "channel"]);

async function* arquivosTs(dir: string): AsyncGenerator<string> {
  for await (const e of Deno.readDir(dir)) {
    const caminho = `${dir}/${e.name}`;
    if (e.isDirectory) yield* arquivosTs(caminho);
    else if (e.name.endsWith(".ts") && !e.name.endsWith("_test.ts")) yield caminho;
  }
}

/** Todos os literais de string que aparecem no valor de `chave:` (inclui os dois lados de um ternário). */
function literaisDe(fonte: string, chave: string): string[] {
  const achados: string[] = [];
  const re = new RegExp(`${chave}\\s*:\\s*([^,\\n}]+)`, "g");
  for (const m of fonte.matchAll(re)) {
    for (const lit of m[1].matchAll(/"([^"]*)"|'([^']*)'/g)) achados.push(lit[1] ?? lit[2]);
  }
  return achados;
}

const RAIZ = new URL("../../", import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1");

Deno.test("event_category e actor_kind gravados pelas edge functions estão no CHECK de ai_operator_audit", async () => {
  const fora: string[] = [];
  for await (const arquivo of arquivosTs(RAIZ)) {
    const fonte = await Deno.readTextFile(arquivo);
    if (!fonte.includes("ai_operator_audit")) continue;
    for (const v of literaisDe(fonte, "event_category")) if (!CATEGORIAS.has(v)) fora.push(`${arquivo}: event_category "${v}"`);
    for (const v of literaisDe(fonte, "actor_kind")) if (!ATORES.has(v)) fora.push(`${arquivo}: actor_kind "${v}"`);
  }
  assertEquals(fora, []);
});

Deno.test("o leitor de literais pega os dois lados do ternário", () => {
  assertEquals(literaisDe(`event_category: x ? "learning" : "data",`, "event_category"), ["learning", "data"]);
});
