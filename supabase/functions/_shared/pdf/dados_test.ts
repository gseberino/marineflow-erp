import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { despesasDoCliente } from "./dados.ts";
import { DESPESA_PUBLICA } from "./colunas-publicas.ts";

/* O documento do cliente (PDF, portal, anexo do WhatsApp) lista a despesa que ele paga — a mesma
   regra do total da OS (11/10/2026). A F2 dos comprovantes grava custo da HBR e "cobrar à parte"
   como despesa NÃO faturável (antes elas sairiam no documento como cobradas) e a faturável paga
   pelo técnico (antes ela entrava no total sem aparecer na lista). */

const linha = (paid_by: string, billable_to_client?: boolean) => ({
  category: "travel", description: "x", amount: 62, paid_by,
  ...(billable_to_client === undefined ? {} : { billable_to_client }),
});

Deno.test("documento do cliente: só a despesa cobrada dele, quem quer que tenha pagado", () => {
  const cobrada = linha("company", true);
  const custoDaHbr = linha("company", false);
  const doTecnicoCobrada = linha("technician", true);
  const doTecnicoNaoCobrada = linha("technician", false);
  assertEquals(despesasDoCliente([cobrada, custoDaHbr, doTecnicoCobrada, doTecnicoNaoCobrada]), [cobrada, doTecnicoCobrada]);
});

Deno.test("documento do cliente: sem a coluna (seletor antigo) conta como cobrada; vazio não quebra", () => {
  const semColuna = linha("company");
  assertEquals(despesasDoCliente([semColuna, null]), [semColuna]);
  assertEquals(despesasDoCliente(null), []);
  assertEquals(despesasDoCliente(undefined), []);
});

Deno.test("as duas leituras do PDF pedem billable_to_client (portal pelo anon e a interna)", () => {
  assertStringIncludes(DESPESA_PUBLICA, "billable_to_client");
  const fonte = Deno.readTextFileSync(new URL("./dados.ts", import.meta.url));
  assertStringIncludes(fonte, "service_order_expenses(category, description, amount, paid_by, billable_to_client)");
  assertEquals(/\.filter\(\(e: any\) => e\.paid_by === 'company'\)/.test(fonte), false, "o filtro antigo, só por paid_by, voltou");
});
