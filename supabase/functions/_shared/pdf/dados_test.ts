import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { despesasDoCliente, faltaAColunaDoComprovante, seletorSemOrigem } from "./dados.ts";
import { DESPESA_PUBLICA } from "./colunas-publicas.ts";

/* O documento do cliente (PDF, portal, anexo do WhatsApp) — ajustes do dono, 11/10/2026: o que foi
   lançado na OS à mão ou pelo assistente aparece como sempre apareceu (pagas pela empresa); a
   despesa que nasceu de comprovante (custo interno, origem_codigo = "CMP-…") nunca aparece. */

const linha = (paid_by: string, extra: Record<string, unknown> = {}) => ({
  category: "Combustível e deslocamento", description: "x", amount: 62, paid_by, ...extra,
});

Deno.test("documento do cliente: o manual aparece como hoje; o que nasceu de comprovante some", () => {
  const manual = linha("company");
  const manualInterna = linha("company", { billable_to_client: false }); // "Interno" lançada à mão: como hoje, aparece
  const doTecnico = linha("technician");
  const doComprovante = linha("company", { origem_codigo: "CMP-00124" });
  const doComprovantePagaPeloTecnico = linha("technician", { origem_codigo: "CMP-00130" });
  assertEquals(
    despesasDoCliente([manual, manualInterna, doTecnico, doComprovante, doComprovantePagaPeloTecnico]),
    [manual, manualInterna],
  );
});

Deno.test("documento do cliente: sem a coluna (o link público, em que o anon nem recebe a linha do comprovante) conta como manual; vazio não quebra", () => {
  const semColuna = linha("company");
  assertEquals(despesasDoCliente([semColuna, null]), [semColuna]);
  assertEquals(despesasDoCliente([linha("company", { origem_codigo: null })]).length, 1);
  assertEquals(despesasDoCliente(null), []);
  assertEquals(despesasDoCliente(undefined), []);
});

Deno.test("as leituras do PDF: a interna pede origem_codigo; a do anon não (a coluna é fechada a ele)", () => {
  assertEquals(DESPESA_PUBLICA, "category, description, amount, paid_by");
  assert(!DESPESA_PUBLICA.includes("origem_codigo"));
  const fonte = Deno.readTextFileSync(new URL("./dados.ts", import.meta.url));
  assertStringIncludes(fonte, "service_order_expenses(category, description, amount, paid_by, origem_codigo)");
  assertStringIncludes(fonte, "expenses: despesasDoCliente((so as any).service_order_expenses)");
  // o critério "só cobradas" (billable_to_client) do commit revertido não volta
  assertEquals(/billable_to_client/.test(fonte.replace(/\/\/.*$|\/\*[\s\S]*?\*\//gm, "")), false);
});

// Revisão dos ajustes (11/10/2026): a tela ou a edge publicada antes da migration 20261011203000 não derruba o
// PDF de toda OS — só o erro da coluna nova faz o seletor interno ser pedido de novo sem ela.
Deno.test("as leituras do PDF: sem a coluna origem_codigo (migration ainda não aplicada), pede de novo sem ela; outro erro derruba", () => {
  const sel = "*, service_order_expenses(category, description, amount, paid_by, origem_codigo), payment_condition_presets(label)";
  assertEquals(seletorSemOrigem(sel), "*, service_order_expenses(category, description, amount, paid_by), payment_condition_presets(label)");
  assertEquals(faltaAColunaDoComprovante({ code: "42703", message: "column service_order_expenses_1.origem_codigo does not exist" }), true);
  assertEquals(faltaAColunaDoComprovante({ code: "PGRST116", message: "JSON object requested, multiple (or no) rows returned" }), false);
  assertEquals(faltaAColunaDoComprovante(null), false);
  const fonte = Deno.readTextFileSync(new URL("./dados.ts", import.meta.url));
  // só a leitura interna tenta de novo (a pública nunca pede a coluna)
  assertStringIncludes(fonte, "soPrimeiro.error && !opcoes.publico && faltaAColunaDoComprovante(soPrimeiro.error)");
});
