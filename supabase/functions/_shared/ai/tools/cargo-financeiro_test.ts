// MF-AUD-031/032 + decisão #3 do dono (09/08/2026): o cargo técnico não enxerga nada
// financeiro — nem pela RLS do banco, nem pelas tools do agente.
//
// Este teste é de GUARDA, não de comportamento: ele lê os arquivos de tools e falha se
// alguém acrescentar uma tool que toque tabela financeira sem barreira de cargo. É o que
// impede a classe de voltar — o conjunto saltou de 63 para 188 tools em três semanas, e
// revisar isso a olho não escala.

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { dirname, fromFileUrl } from "https://deno.land/std@0.224.0/path/mod.ts";

// fromFileUrl e não `new URL(...).pathname`: o caminho deste repo tem espaço
// ("Claude Code"), que vira %20 na URL e quebra a leitura do diretório.
const DIR = dirname(fromFileUrl(import.meta.url));
const TABELAS_FINANCEIRAS = ["payments", "receivables", "payables", "invoices", "bank_transactions"];

/** Uma tool é um objeto do array, e cada objeto começa numa linha que é exatamente "  {". */
function lerTools(): Array<{ arquivo: string; nome: string; corpo: string }> {
  const tools: Array<{ arquivo: string; nome: string; corpo: string }> = [];
  for (const entrada of Deno.readDirSync(DIR)) {
    if (!entrada.isFile || !entrada.name.endsWith(".ts")) continue;
    if (entrada.name.includes("_test") || entrada.name === "registry.ts" || entrada.name === "index.ts") continue;

    const linhas = Deno.readTextFileSync(`${DIR}/${entrada.name}`).split("\n");
    const inicios: number[] = [];
    linhas.forEach((l, i) => { if (/^ {2}\{\s*$/.test(l)) inicios.push(i); });

    inicios.forEach((ini, k) => {
      const fim = k + 1 < inicios.length ? inicios[k + 1] : linhas.length;
      const corpo = linhas.slice(ini, fim).join("\n");
      const nome = corpo.match(/^\s{4}name:\s*"([a-z_0-9]+)"/m)?.[1];
      // Só objetos que declaram `risk` são definições de tool.
      if (nome && /^\s{4}risk:\s*"/m.test(corpo)) tools.push({ arquivo: entrada.name, nome, corpo });
    });
  }
  return tools;
}

/** As três formas legítimas de barrar o técnico, todas já usadas no código. */
function temBarreiraDeCargo(corpo: string): boolean {
  return /^\s{4}roles:/m.test(corpo)              // filtra a tool por cargo antes de oferecê-la
    || /blockTechnician\(/.test(corpo)            // revalida dentro do execute
    || /podeVerFinanceiro\(/.test(corpo)          // omite só o bloco financeiro da resposta
    || /userRole\s*===/.test(corpo);              // checagem explícita de cargo
}

Deno.test("o inventário de tools é lido corretamente (protege o próprio teste)", () => {
  const tools = lerTools();
  // Se a delimitação quebrar, o teste viraria um no-op silencioso — que é pior que falhar.
  if (tools.length < 150) throw new Error(`Só ${tools.length} tools lidas; a delimitação quebrou.`);
});

Deno.test("nenhuma tool toca tabela financeira sem barreira de cargo", () => {
  const infratoras = lerTools()
    .filter((t) => TABELAS_FINANCEIRAS.some((tab) => new RegExp(`["'\`]${tab}["'\`]`).test(t.corpo)))
    .filter((t) => !temBarreiraDeCargo(t.corpo))
    .map((t) => `${t.arquivo}:${t.nome}`);

  assertEquals(
    infratoras,
    [],
    `Tool financeira sem barreira de cargo (decisão #3 do dono): ${infratoras.join(", ")}.\n` +
      "Use roles: NON_TECHNICIAN_ROLES + blockTechnician(ctx), ou podeVerFinanceiro(ctx) " +
      "quando só o bloco financeiro da resposta precisa sumir.",
  );
});

Deno.test("adjust_inventory continua com gate de aprovação e autoria", () => {
  const tool = lerTools().find((t) => t.nome === "adjust_inventory");
  if (!tool) throw new Error("adjust_inventory sumiu — se foi renomeada, atualize este teste.");

  // Escrita destrutiva de estoque não pode voltar a executar direto.
  assertEquals(/^\s{4}risk:\s*"high"/m.test(tool.corpo), true, "adjust_inventory precisa ser risk: high");
  assertEquals(temBarreiraDeCargo(tool.corpo), true, "adjust_inventory precisa barrar por cargo");
  // Movimento sem autor é indistinguível de movimento do sistema.
  assertEquals(/created_by:\s*userId/.test(tool.corpo), true, "o movimento precisa gravar created_by");
});
