// Run: deno test supabase/functions/_shared/banking/reenvio_test.ts
//
// O que se protege: o reenvio com código novo não entra em dobro na fila (caso de 29/09/2026,
// quando o banco passou a devolver as duas versões), e a repetição legítima que chega junta
// (vários pedágios iguais no mesmo dia) continua entrando.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { chaveDoConteudo, type LinhaDoExtrato, type LinhaGuardada, separarReenvios } from "./reenvio.ts";

function linha(ref: string, extra: Partial<LinhaDoExtrato> = {}): LinhaDoExtrato {
  return {
    bank_ref_id: ref,
    transaction_date: "2026-07-23",
    amount: 1000,
    transaction_type: "credit",
    description: "Inclusao de Pagamento Ciclo Corrente",
    installment_label: null,
    card_last_digits: "7130",
    provider_account_id: "conta-c6",
    ...extra,
  };
}

function guardada(id: string, ref: string, extra: Partial<LinhaDoExtrato> = {}): LinhaGuardada {
  return { id, ...linha(ref, extra) };
}

const PEDAGIO = { amount: 5.7, transaction_type: "debit", description: "ARTERIS LITORAL SUL", transaction_date: "2026-04-30" };

Deno.test("29/09: o banco devolve as duas versões → a de código novo entra como provável reenvio", () => {
  const antiga = linha("24387dc4");
  const nova = linha("c5b0a67d");
  const r = separarReenvios([antiga, nova], [nova], [guardada("g1", "24387dc4")]);
  assertEquals(r.reais, []);
  assertEquals(r.reenvios, []);
  assertEquals(r.provaveis.map((x) => [x.linha.bank_ref_id, x.igual.id]), [["c5b0a67d", "g1"]]);
});

Deno.test("o banco troca o código e para de mandar o antigo → a guardada passa a usar o novo", () => {
  const nova = linha("c5b0a67d");
  const r = separarReenvios([nova], [nova], [guardada("g1", "24387dc4")]);
  assertEquals(r.reais, []);
  assertEquals(r.provaveis, []);
  assertEquals(r.reenvios.map((x) => [x.linha.bank_ref_id, x.guardada.id]), [["c5b0a67d", "g1"]]);
});

Deno.test("6 pedágios iguais chegando juntos, sem nada igual guardado → os 6 entram", () => {
  const devolvidas = ["p1", "p2", "p3", "p4", "p5", "p6"].map((r) => linha(r, PEDAGIO));
  const r = separarReenvios(devolvidas, devolvidas, []);
  assertEquals(r.reais.length, 6);
  assertEquals(r.reenvios, []);
  assertEquals(r.provaveis, []);
});

Deno.test("os 6 já guardados e devolvidos de novo → nada novo", () => {
  const devolvidas = ["p1", "p2", "p3", "p4", "p5", "p6"].map((r) => linha(r, PEDAGIO));
  const guardadas = ["p1", "p2", "p3", "p4", "p5", "p6"].map((r, i) => guardada(`g${i}`, r, PEDAGIO));
  assertEquals(separarReenvios(devolvidas, [], guardadas), { reais: [], reenvios: [], provaveis: [] });
});

Deno.test("um dos 6 pedágios volta com código novo e o antigo some → reenvio do que sumiu", () => {
  const guardadas = ["p1", "p2", "p3", "p4", "p5", "p6"].map((r, i) => guardada(`g${i}`, r, PEDAGIO));
  const devolvidas = ["p1", "p2", "p3", "p4", "p5", "p6-novo"].map((r) => linha(r, PEDAGIO));
  const r = separarReenvios(devolvidas, [devolvidas[5]], guardadas);
  assertEquals(r.reais, []);
  assertEquals(r.provaveis, []);
  assertEquals(r.reenvios.map((x) => x.guardada.bank_ref_id), ["p6"]);
});

Deno.test("um 7º pedágio igual aparece semanas depois → provável reenvio (volta à fila com um clique)", () => {
  const guardadas = ["p1", "p2", "p3", "p4", "p5", "p6"].map((r, i) => guardada(`g${i}`, r, PEDAGIO));
  const setimo = linha("p7", PEDAGIO);
  const devolvidas = [...["p1", "p2", "p3", "p4", "p5", "p6"].map((r) => linha(r, PEDAGIO)), setimo];
  const r = separarReenvios(devolvidas, [setimo], guardadas);
  assertEquals(r.reais, []);
  assertEquals(r.provaveis.map((x) => x.linha.bank_ref_id), ["p7"]);
});

Deno.test("conteúdo diferente (valor, descrição, conta, parcela, tipo, data) → real", () => {
  const g = [guardada("g1", "antigo")];
  for (const extra of [
    { amount: 1000.01 },
    { description: "Pagamento recebido" },
    { provider_account_id: "conta-nubank" },
    { installment_label: "2/3" },
    { transaction_type: "debit" },
    { transaction_date: "2026-07-24" },
  ]) {
    const nova = linha("novo", extra);
    const r = separarReenvios([linha("antigo"), nova], [nova], g);
    assertEquals([r.reais.length, r.provaveis.length, r.reenvios.length], [1, 0, 0], JSON.stringify(extra));
  }
});

Deno.test("chave ignora espaços e maiúsculas na descrição e o sinal do valor", () => {
  assertEquals(
    chaveDoConteudo(linha("a", { description: "  Inclusao  de Pagamento CICLO Corrente ", amount: -1000 })),
    chaveDoConteudo(linha("b")),
  );
});
