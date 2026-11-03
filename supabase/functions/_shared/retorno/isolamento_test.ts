// O retorno não puxa o assistente para dentro (P10, F1, 16/11/2026; plano J.1).
//
// A edge retorno-recibos e a pasta _shared/retorno/ ficam FORA da pasta congelada _shared/ai/: a 7b
// da agenda está mudando aquilo, e publicar o retorno não pode publicar junto as ferramentas do
// assistente (_shared/ai/tools/, _shared/ai/registry.ts) nem o motor da agenda (_shared/agenda/).
// Dois portões:
//  1. nenhum .ts de _shared/retorno/ ou de retorno-recibos/ importa DIRETO de _shared/ai/ (lido do
//     texto: `from "…"`, `import "…"`, `import("…")`, relativo ou absoluto);
//  2. o grafo inteiro de retorno-recibos/index.ts (deno info --json, o mesmo resolvedor do deploy) não
//     tem nenhum módulo sob _shared/ai/tools/, _shared/ai/registry.ts ou _shared/agenda/.
// Falha fechado: deno info que não roda, JSON que não se lê, módulo local com erro de resolução ou
// grafo que não contém a própria raiz reprovam. Erro de módulo remoto não reprova: módulo remoto não
// importa arquivo local, então não esconde nada daqui.
// O validador (validador.ts) não importa nada: o grafo dele é ele mesmo.
//
// Enquanto a pasta retorno-recibos/ não existe (a P11 é da onda 2), o portão 2 aparece como
// "ignored" no deno test; com a pasta criada e sem index.ts, reprova.
//
// Exige --allow-read --allow-run (o test:edge roda com --allow-all).
// Reverter: apagar este arquivo.

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { dirname, fromFileUrl, join, resolve, toFileUrl } from "https://deno.land/std@0.224.0/path/mod.ts";

const AQUI = dirname(fromFileUrl(import.meta.url)); // supabase/functions/_shared/retorno
const FUNCOES = resolve(AQUI, "..", ".."); // supabase/functions
const RAIZ = resolve(FUNCOES, "..", ".."); // o repositório
const DIR_RETORNO = join(FUNCOES, "_shared", "retorno");
const DIR_RECIBOS = join(FUNCOES, "retorno-recibos");
const ENTRADA_RECIBOS = join(DIR_RECIBOS, "index.ts");

/** Caminho absoluto em forma comparável: barras "/" e minúsculas (o Windows não diferencia caixa). */
function comparavel(caminho: string): string {
  return resolve(caminho).replaceAll("\\", "/").toLowerCase();
}

const AI = comparavel(join(FUNCOES, "_shared", "ai"));
const AI_TOOLS = comparavel(join(FUNCOES, "_shared", "ai", "tools"));
const AI_REGISTRY = comparavel(join(FUNCOES, "_shared", "ai", "registry.ts"));
const AGENDA = comparavel(join(FUNCOES, "_shared", "agenda"));

function dentroDe(caminho: string, pasta: string): boolean {
  return caminho === pasta || caminho.startsWith(pasta + "/");
}

/** Proibido no grafo da edge (J.1). `_shared/agenda-dia.ts` não é `_shared/agenda/`. */
function proibidoNoGrafo(caminhoComparavel: string): boolean {
  return dentroDe(caminhoComparavel, AI_TOOLS) || caminhoComparavel === AI_REGISTRY ||
    dentroDe(caminhoComparavel, AGENDA);
}

/** Todos os especificadores importados por um fonte: estático, reexportação, só efeito e dinâmico. */
function importsDe(fonte: string): string[] {
  const achados: string[] = [];
  const padroes = [
    /\bfrom\s*["']([^"']+)["']/g,
    /\bimport\s*["']([^"']+)["']/g,
    /\bimport\s*\(\s*["']([^"']+)["']\s*\)/g,
  ];
  for (const p of padroes) for (const m of fonte.matchAll(p)) achados.push(m[1]);
  return achados;
}

/** O import aponta para _shared/ai/? Relativo e file: pelo caminho; remoto ou nu pelo texto. */
function apontaParaAi(arquivo: string, especificador: string): boolean {
  let alvo: string | null = null;
  if (especificador.startsWith("./") || especificador.startsWith("../")) {
    alvo = resolve(dirname(arquivo), especificador);
  } else if (especificador.startsWith("file:")) {
    alvo = fromFileUrl(especificador);
  } else if (especificador.startsWith("/")) {
    alvo = especificador;
  }
  if (alvo !== null) return dentroDe(comparavel(alvo), AI);
  return especificador.replaceAll("\\", "/").toLowerCase().includes("_shared/ai/");
}

function existe(caminho: string): boolean {
  try {
    Deno.statSync(caminho);
    return true;
  } catch {
    return false;
  }
}

/** Todo arquivo de código (.ts, .tsx, .mts, .js, .mjs) de uma pasta, recursivo; pasta ausente = nenhum. */
function arquivosDeCodigo(pasta: string): string[] {
  if (!existe(pasta)) return [];
  const r: string[] = [];
  for (const e of Deno.readDirSync(pasta)) {
    const caminho = join(pasta, e.name);
    if (e.isDirectory) r.push(...arquivosDeCodigo(caminho));
    else if (e.isFile && /\.(ts|tsx|mts|js|mjs)$/.test(e.name)) r.push(caminho);
  }
  return r;
}

interface DependenciaDoGrafo {
  specifier: string;
  code?: { specifier?: string };
  type?: { specifier?: string };
}

interface ModuloDoGrafo {
  specifier: string;
  kind?: string;
  error?: string;
  dependencies?: DependenciaDoGrafo[];
}

interface Grafo {
  raiz: string; // especificador da entrada, como o deno info o devolve
  modulos: ModuloDoGrafo[];
  redirects: Record<string, string>;
}

/** O grafo de módulos de uma entrada, pelo deno info --json (o mesmo resolvedor do deno check do CI). */
async function grafoDe(entrada: string): Promise<Grafo> {
  // A entrada vai como URL file://: um caminho "D:\…" cru o deno info lê como URL de esquema "d:" e
  // devolve um módulo "external", sem grafo nenhum. --no-lock: o teste só lê; sem ele, o deno info
  // na raiz reescreve o deno.lock com as dependências npm do front.
  const url = toFileUrl(resolve(entrada)).href;
  const saida = await new Deno.Command(Deno.execPath(), {
    args: ["info", "--json", "--no-lock", "--node-modules-dir=none", url],
    cwd: RAIZ,
    stdout: "piped",
    stderr: "piped",
  }).output();
  const erro = new TextDecoder().decode(saida.stderr);
  assert(saida.success, `deno info falhou para ${entrada}: ${erro}`);
  const json = JSON.parse(new TextDecoder().decode(saida.stdout)) as {
    roots?: string[];
    modules?: ModuloDoGrafo[];
    redirects?: Record<string, string>;
  };
  assert(Array.isArray(json.modules), "deno info sem a lista de módulos");
  assert(Array.isArray(json.roots) && json.roots.length === 1, "deno info sem a raiz");
  const modulos = json.modules;
  const raiz = json.roots[0];
  // Sem a raiz carregada como módulo local, a lista não prova nada.
  const daRaiz = modulos.find((m) => m.specifier === raiz);
  assert(
    raiz.startsWith("file:") && comparavel(fromFileUrl(raiz)) === comparavel(entrada) && daRaiz !== undefined &&
      daRaiz.kind !== "external" && !daRaiz.error,
    `o grafo de ${entrada} não contém a própria entrada como módulo local: ${JSON.stringify(daRaiz)}`,
  );
  const locaisComErro = modulos.filter((m) => m.specifier.startsWith("file:") && m.error);
  assertEquals(locaisComErro.map((m) => `${m.specifier}: ${m.error}`), [], "módulo local com erro de resolução");
  return { raiz, modulos, redirects: json.redirects ?? {} };
}

/**
 * Todo módulo LOCAL do grafo que é proibido. Conta a lista inteira, inclusive o que só o tsconfig da
 * raiz acrescenta (os "types" do front): olhar mais do que o necessário só pode reprovar a mais.
 */
function proibidosDoGrafo(grafo: Grafo): string[] {
  return grafo.modulos
    .filter((m) => m.specifier.startsWith("file:"))
    .map((m) => comparavel(fromFileUrl(m.specifier)))
    .filter(proibidoNoGrafo);
}

/** Os módulos que a entrada alcança pelas próprias dependências (seguindo os redirecionamentos). */
function alcancaveis(grafo: Grafo): Set<string> {
  const porEspecificador = new Map(grafo.modulos.map((m) => [m.specifier, m]));
  const vistos = new Set<string>();
  const fila = [grafo.raiz];
  while (fila.length > 0) {
    let s = fila.pop() as string;
    for (let i = 0; i < 20 && grafo.redirects[s]; i++) s = grafo.redirects[s];
    if (vistos.has(s)) continue;
    vistos.add(s);
    for (const d of porEspecificador.get(s)?.dependencies ?? []) {
      if (d.code?.specifier) fila.push(d.code.specifier);
      if (d.type?.specifier) fila.push(d.type.specifier);
    }
  }
  return vistos;
}

// ─── O próprio verificador (para não passar por não enxergar nada) ───────────────────────────────

Deno.test("isolamento: o extrator de imports e os classificadores enxergam o que devem", () => {
  // As aspas vêm de variável: este arquivo também é lido pelo portão 1, e um from seguido do
  // caminho de ../ai entre aspas, escrito literalmente aqui, seria um import de verdade para ele.
  const q = '"';
  const fonte = [
    `import { a } from ${q}../ai/tools/clients.ts${q};`,
    `import type { B } from ${q}./validador.ts${q};`,
    `export { c } from ${q}../ai/registry.ts${q};`,
    `import ${q}../ai/efeito.ts${q};`,
    `const d = await import(${q}../agenda/executar.ts${q});`,
    `import {\n  e,\n  f,\n} from ${q}https://deno.land/std@0.224.0/assert/mod.ts${q};`,
  ].join("\n");
  assertEquals(importsDe(fonte), [
    "../ai/tools/clients.ts",
    "./validador.ts",
    "../ai/registry.ts",
    "https://deno.land/std@0.224.0/assert/mod.ts",
    "../ai/efeito.ts",
    "../agenda/executar.ts",
  ]);

  const arquivo = join(DIR_RETORNO, "qualquer.ts");
  assert(apontaParaAi(arquivo, "../ai/tools/clients.ts"));
  assert(apontaParaAi(arquivo, "../AI/phone.ts"), "caixa diferente é o mesmo caminho no Windows");
  assert(apontaParaAi(join(DIR_RECIBOS, "index.ts"), "../_shared/ai/phone.ts"));
  assert(apontaParaAi(arquivo, "https://exemplo.org/supabase/functions/_shared/ai/x.ts"));
  assert(!apontaParaAi(arquivo, "./validador.ts"));
  assert(!apontaParaAi(arquivo, "../whatsapp/normalize.ts"));
  assert(!apontaParaAi(arquivo, "../aiz/x.ts"), "pasta de nome parecido não é _shared/ai/");

  assert(proibidoNoGrafo(comparavel(join(FUNCOES, "_shared", "ai", "tools", "clients.ts"))));
  assert(proibidoNoGrafo(comparavel(join(FUNCOES, "_shared", "ai", "registry.ts"))));
  assert(proibidoNoGrafo(comparavel(join(FUNCOES, "_shared", "agenda", "executar.ts"))));
  assert(!proibidoNoGrafo(comparavel(join(FUNCOES, "_shared", "agenda-dia.ts"))));
  assert(!proibidoNoGrafo(comparavel(join(FUNCOES, "_shared", "ai", "phone.ts"))), "J.1 só proíbe tools/ e registry.ts no grafo");
  assert(!proibidoNoGrafo(comparavel(join(FUNCOES, "_shared", "cors.ts"))));

  // proibidosDoGrafo olha a lista inteira; alcancaveis segue dependências e redirecionamentos.
  const url = (...p: string[]) => toFileUrl(join(FUNCOES, ...p)).href;
  const grafo: Grafo = {
    raiz: url("retorno-recibos", "index.ts"),
    modulos: [
      { specifier: url("retorno-recibos", "index.ts"), dependencies: [{ specifier: "./rodada.ts", code: { specifier: url("retorno-recibos", "rodada.ts") } }] },
      { specifier: url("retorno-recibos", "rodada.ts"), dependencies: [{ specifier: "x", type: { specifier: "https://a/x" } }] },
      { specifier: "https://b/x" },
      { specifier: url("_shared", "agenda", "executar.ts") }, // fora do alcance da raiz, mas na lista
    ],
    redirects: { "https://a/x": "https://b/x" },
  };
  assertEquals(proibidosDoGrafo(grafo), [comparavel(join(FUNCOES, "_shared", "agenda", "executar.ts"))]);
  assertEquals([...alcancaveis(grafo)].sort(), [url("retorno-recibos", "index.ts"), url("retorno-recibos", "rodada.ts"), "https://b/x"].sort());
});

// ─── Portão 1: imports diretos ───────────────────────────────────────────────────────────────────

Deno.test("isolamento: nada em _shared/retorno/ nem em retorno-recibos/ importa _shared/ai/", () => {
  const arquivos = [...arquivosDeCodigo(DIR_RETORNO), ...arquivosDeCodigo(DIR_RECIBOS)];
  assert(
    arquivos.some((a) => comparavel(a) === comparavel(join(DIR_RETORNO, "validador.ts"))),
    "a varredura não achou o validador: o portão estaria olhando a pasta errada",
  );
  const violacoes: string[] = [];
  for (const arquivo of arquivos) {
    for (const especificador of importsDe(Deno.readTextFileSync(arquivo))) {
      if (apontaParaAi(arquivo, especificador)) violacoes.push(`${arquivo} → ${especificador}`);
    }
  }
  assertEquals(violacoes, []);
});

Deno.test("isolamento: o validador não importa nada (o grafo dele é ele mesmo)", async () => {
  const validador = join(DIR_RETORNO, "validador.ts");
  assertEquals(importsDe(Deno.readTextFileSync(validador)), []);
  const grafo = await grafoDe(validador);
  assertEquals([...alcancaveis(grafo)], [grafo.raiz], "o validador alcança outros módulos");
  assertEquals(proibidosDoGrafo(grafo), []);
});

// ─── Portão 2: o grafo inteiro da edge ───────────────────────────────────────────────────────────

Deno.test({
  name: "isolamento: o grafo de retorno-recibos/index.ts não tem _shared/ai/tools/, _shared/ai/registry.ts nem _shared/agenda/ (J.1)",
  ignore: !existe(DIR_RECIBOS),
  async fn() {
    assert(existe(ENTRADA_RECIBOS), `a pasta ${DIR_RECIBOS} existe, mas sem index.ts: não há o que provar`);
    const grafo = await grafoDe(ENTRADA_RECIBOS);
    assertEquals(proibidosDoGrafo(grafo), []);
  },
});

Deno.test("isolamento: o grafo de cada módulo de _shared/retorno/ também fica fora de tools/, registry.ts e _shared/agenda/", async () => {
  const modulos = arquivosDeCodigo(DIR_RETORNO).filter((a) => !/_test\.(ts|tsx|mts|js|mjs)$/.test(a));
  assert(modulos.length >= 1);
  for (const modulo of modulos) {
    assertEquals(proibidosDoGrafo(await grafoDe(modulo)), [], modulo);
  }
});
