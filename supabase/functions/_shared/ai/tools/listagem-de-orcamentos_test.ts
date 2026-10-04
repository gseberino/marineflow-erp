// list_service_orders (03/10/2026): "rascunho" é orçamento não enviado, não a fase inteira; o total
// real vem ao lado da lista; "o maior" ordena por valor. Caso real: o assistente respondeu "50
// orçamentos em rascunho, o maior é o ORÇ-00099" — eram 51 na fase (44 recusados), 2 em rascunho,
// e o ORÇ-00099 estava recusado.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { filtroDaListagem, serviceOrderTools } from "./service-orders.ts";

Deno.test("filtro: 'rascunho' é situação (não enviado), pela situação ou pelo status", () => {
  assertEquals(filtroDaListagem({ quote_status: "rascunho" }), { limite: 20, ordem: "recentes", fase: "orcamento", situacao: "draft" });
  assertEquals(filtroDaListagem({ status: "rascunho" }), { limite: 20, ordem: "recentes", fase: "orcamento", situacao: "draft" });
  assertEquals(filtroDaListagem({ quote_status: "recusados".slice(0, 8) /* "recusado" */ }).situacao, "rejected");
  assertEquals(filtroDaListagem({ quote_status: "awaiting_approval" }).situacao, "awaiting_approval");
});

Deno.test("filtro: fase sem situação continua sendo a fase inteira; situação manda sobre is_quote=false", () => {
  assertEquals(filtroDaListagem({ is_quote: true }), { limite: 20, ordem: "recentes", fase: "orcamento" });
  assertEquals(filtroDaListagem({ is_quote: false }), { limite: 20, ordem: "recentes", fase: "os" });
  assertEquals(filtroDaListagem({ is_quote: false, quote_status: "draft" }).fase, "orcamento");
  assertEquals(filtroDaListagem({ status: "em andamento" }), { limite: 20, ordem: "recentes", status: "in_progress" });
});

Deno.test("filtro: limite entre 1 e 50 e ordem por valor", () => {
  assertEquals(filtroDaListagem({ limit: 500 }).limite, 50);
  assertEquals(filtroDaListagem({ limit: -3 }).limite, 1);
  assertEquals(filtroDaListagem({ order_by: "maior_valor" }).ordem, "maior_valor");
  assertEquals(filtroDaListagem({ order_by: "qualquer" }).ordem, "recentes");
});

function sbFalso(linhas: unknown[], count: number | null) {
  const chamadas: unknown[][] = [];
  const b: Record<string, unknown> = {};
  for (const m of ["select", "order", "limit", "eq", "neq"]) {
    b[m] = (...args: unknown[]) => {
      chamadas.push([m, ...args]);
      return b;
    };
  }
  b.then = (ok: (v: unknown) => unknown) => Promise.resolve({ data: linhas, error: null, count }).then(ok);
  return { sb: { from: (t: string) => (chamadas.push(["from", t]), b) }, chamadas };
}

const listar = serviceOrderTools.find((t) => t.name === "list_service_orders")!;
const linha = (numero: string, quote_status: string, total: number) => ({
  id: numero, service_order_number: numero, status: "draft", quote_status, grand_total: total,
  payment_status: null, scheduled_start_at: null, created_at: "2026-10-01", clients: { name: "Cliente" }, vessels: { name: "Lancha" },
});

Deno.test("execução: rascunho filtra a fase E a situação, pede a contagem exata e traz a situação de cada um", async () => {
  const { sb, chamadas } = sbFalso([linha("ORÇ-00106", "draft", 29610.84), linha("ORÇ-00111", "draft", 4254.69)], 2);
  const r = await listar.execute({ quote_status: "draft", order_by: "maior_valor" }, { sb } as never) as Record<string, any>;
  assertEquals(chamadas.filter((c) => c[0] === "eq"), [["eq", "status", "draft"], ["eq", "quote_status", "draft"]]);
  assertEquals((chamadas.find((c) => c[0] === "select") as unknown[])[2], { count: "exact" });
  assertEquals(chamadas.find((c) => c[0] === "order"), ["order", "grand_total", { ascending: false, nullsFirst: false }]);
  assertEquals(r.total, 2);
  assertEquals(r.aviso, undefined);
  assertEquals(r.results[0].numero, "ORÇ-00106");
  assertEquals(r.results[0].situacao, "Rascunho (não enviado)");
});

Deno.test("execução: lista cortada avisa o total real e marca os recusados", async () => {
  const { sb } = sbFalso([linha("ORÇ-00099", "rejected", 72948.13)], 51);
  const r = await listar.execute({ is_quote: true, limit: 1 }, { sb } as never) as Record<string, any>;
  assertEquals(r.total, 51);
  assertEquals(r.mostrando, 1);
  assertEquals(r.aviso, "Lista cortada: mostrando 1 de 51. O total real é 51.");
  assertEquals(r.results[0].situacao, "Recusado");
});
