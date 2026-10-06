import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { montarRelatorioHtml, nomeDoRelatorio } from "./relatorio.ts";

const base = {
  empresa: "HBR Marine",
  titulo: "Despesas — Setembro de 2026",
  periodo: "Período: Setembro de 2026",
  resumo: [{ rotulo: "despesas lançadas", valor: "R$ 1.234,50" }],
  tabelas: [{
    titulo: "Lançamentos",
    colunas: [{ titulo: "Data", tipo: "data" as const }, { titulo: "Fornecedor" }, { titulo: "Valor", tipo: "valor" as const }],
    linhas: [["2026-09-03", "Posto <Paulinho> & Cia", 116.9], ["2026-09-10", null, 1117.6]],
    total: { rotulo: "Total", valor: 1234.5 },
  }],
};

Deno.test("relatório: data e valor no formato brasileiro, total na coluna de valor", () => {
  const html = montarRelatorioHtml({ ...base, geradoEm: new Date("2026-10-06T20:00:00Z") });
  assertStringIncludes(html, "03/09/2026");
  assertStringIncludes(html.replace(/\s/g, " "), "R$ 1.234,50");
  assertStringIncludes(html, "<tfoot>");
  assertStringIncludes(html, "—"); // célula vazia
});

Deno.test("relatório: todo texto passa por escape (nome de fornecedor não vira HTML)", () => {
  const html = montarRelatorioHtml(base);
  assert(!html.includes("<Paulinho>"));
  assertStringIncludes(html, "&lt;Paulinho&gt; &amp; Cia");
});

Deno.test("relatório: tabela vazia diz 'Nada no período' em vez de sumir", () => {
  const html = montarRelatorioHtml({ ...base, tabelas: [{ ...base.tabelas[0], linhas: [], total: undefined }] });
  assertStringIncludes(html, "Nada no período.");
});

Deno.test("nomeDoRelatorio: sem acento nem espaço, com .pdf", () => {
  assertEquals(nomeDoRelatorio(["Despesas", "2026-09-01", "2026-09-30", "Combustível"]), "despesas-2026-09-01-2026-09-30-combustivel.pdf");
  assertEquals(nomeDoRelatorio([]), "relatorio.pdf");
});
