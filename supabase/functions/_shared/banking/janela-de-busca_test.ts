import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { inicioDaBusca, mudancasDoProvedor, transacaoMaisRecente } from "./janela-de-busca.ts";

Deno.test("janela: parcela futura guardada não empurra a busca para o futuro (o Nubank de 14/08 a 27/09)", () => {
  // Guardado 13/11 (Coremma 4/4): a busca voltava a começar em 06/11 e não trazia nada de hoje.
  assertEquals(inicioDaBusca("2026-11-13", "2026-09-27", { temCartao: true }), "2026-08-13");
});

Deno.test("janela: cartão volta 45 dias; conta sem cartão, 7; primeira vez ou busca completa, 365", () => {
  assertEquals(inicioDaBusca("2026-09-25", "2026-09-27", { temCartao: true }), "2026-08-11");
  assertEquals(inicioDaBusca("2026-09-25", "2026-09-27"), "2026-09-18");
  assertEquals(inicioDaBusca(null, "2026-09-27"), "2025-09-27");
  assertEquals(inicioDaBusca("2026-09-25", "2026-09-27", { completa: true }), "2025-09-27");
});

Deno.test("mais recente: parcela futura não conta; guardada futura sem nada novo vira hoje", () => {
  assertEquals(transacaoMaisRecente("2026-11-13", ["2026-09-20", "2026-11-13", "2026-10-13"], "2026-09-27"), "2026-09-20");
  assertEquals(transacaoMaisRecente("2026-11-13", [], "2026-09-27"), "2026-09-27");
  assertEquals(transacaoMaisRecente("2026-09-25", ["2026-09-26", "2026-09-10"], "2026-09-27"), "2026-09-26");
  assertEquals(transacaoMaisRecente("2026-09-25", ["2026-09-10"], "2026-09-27"), "2026-09-25");
  assertEquals(transacaoMaisRecente(null, [], "2026-09-27"), null);
});

Deno.test("provedor: pendente vira lançada e ganha fatura e parcela; nunca volta para pendente", () => {
  const atual = { tx_status: "PENDING", bill_id: null, installment_label: null };
  assertEquals(mudancasDoProvedor(atual, { tx_status: "POSTED", bill_id: "b9", installment_label: "2/3" }),
    { tx_status: "POSTED", bill_id: "b9", installment_label: "2/3" });
  assertEquals(mudancasDoProvedor({ tx_status: "POSTED", bill_id: "b9", installment_label: "2/3" },
    { tx_status: "PENDING", bill_id: null, installment_label: null }), {});
  // Nada novo: nada muda.
  assertEquals(mudancasDoProvedor(atual, { tx_status: "PENDING", bill_id: null, installment_label: null }), {});
});
