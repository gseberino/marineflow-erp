// Retorno rápido, F2 (P5.4): o fato só lê colunas da lista positiva, e nenhuma delas é interna.
// Lê o texto da migration: a lista é a que está lá, entre os marcadores.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { COLUNAS_INTERNAS } from "../pdf/colunas-publicas.ts";

const MIGRATION = new URL("../../../migrations/20261123100200_retorno_f2_fatos.sql", import.meta.url);

async function listaPositiva(): Promise<Record<string, string[]>> {
  const fonte = (await Deno.readTextFile(MIGRATION)).replaceAll("\r\n", "\n");
  const ini = fonte.indexOf("-- lista positiva: início");
  const fim = fonte.indexOf("-- lista positiva: fim");
  assert(ini >= 0 && fim > ini, "os marcadores da lista positiva sumiram da migration");
  const lista: Record<string, string[]> = {};
  let tabela = "";
  for (const linha of fonte.slice(ini, fim).split("\n").slice(1)) {
    const texto = linha.replace(/^--\s*/, "");
    const m = /^(\w+): (.*)$/.exec(texto);
    if (m) tabela = m[1];
    const colunas = (m ? m[2] : texto).split(",").map((c) => c.trim()).filter(Boolean);
    if (tabela) lista[tabela] = [...(lista[tabela] ?? []), ...colunas];
  }
  return lista;
}

Deno.test("a lista positiva lê a migration e traz as tabelas do fato", async () => {
  const lista = await listaPositiva();
  assertEquals(Object.keys(lista).sort(), [
    "agenda_acoes", "agenda_alocacoes", "agenda_cliente_mensagens", "agenda_disponibilidade", "os_material", "os_tarefas",
    "os_tarefas_dia", "service_orders", "vessels",
  ]);
  assert(lista.service_orders.includes("liberado_retirada_em"));
  assert(lista.os_material.includes("previsao_ate"));
});

Deno.test("nenhuma coluna da lista positiva está em COLUNAS_INTERNAS", async () => {
  const lista = await listaPositiva();
  for (const [tabela, colunas] of Object.entries(lista)) {
    const internas = COLUNAS_INTERNAS[tabela] ?? [];
    assertEquals(colunas.filter((c) => internas.includes(c)), [], tabela);
  }
});

Deno.test("a migration não tem select *", async () => {
  const fonte = await Deno.readTextFile(MIGRATION);
  assertEquals(/select\s+\*(?!\s+from\s+(vivas|sem_palavra)\b)/i.test(fonte.replace(/\bm\.\*|\bb\.\*/g, "")), false);
});
