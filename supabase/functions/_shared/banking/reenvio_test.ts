// Run: deno test supabase/functions/_shared/banking/reenvio_test.ts
//
// O que se protege: o reenvio com código novo não entra em dobro (caso de 29/09/2026), e a
// repetição legítima (vários pedágios iguais no mesmo dia) continua entrando.
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

Deno.test("29/09: o banco devolve a mesma transação com código novo → reenvio, não linha nova", () => {
  const nova = linha("c5b0a67d");
  const r = separarReenvios([nova], [nova], [guardada("g1", "24387dc4")]);
  assertEquals(r.reais, []);
  assertEquals(r.reenvios.map((x) => [x.linha.bank_ref_id, x.guardada.id]), [["c5b0a67d", "g1"]]);
});

Deno.test("mesmo conteúdo, mas o banco devolve as duas → a nova é real", () => {
  const antiga = linha("24387dc4");
  const nova = linha("c5b0a67d");
  const r = separarReenvios([antiga, nova], [nova], [guardada("g1", "24387dc4")]);
  assertEquals(r.reais.map((l) => l.bank_ref_id), ["c5b0a67d"]);
  assertEquals(r.reenvios, []);
});

Deno.test("6 pedágios iguais: todos guardados e devolvidos → nada novo; um 7º → 1 real", () => {
  const pedagio = { amount: 5.7, transaction_type: "debit", description: "ARTERIS LITORAL SUL", transaction_date: "2026-04-30" };
  const refs = ["p1", "p2", "p3", "p4", "p5", "p6"];
  const devolvidas = refs.map((r) => linha(r, pedagio));
  const guardadas = refs.map((r, i) => guardada(`g${i}`, r, pedagio));
  assertEquals(separarReenvios(devolvidas, [], guardadas), { reais: [], reenvios: [] });

  const setimo = linha("p7", pedagio);
  const r = separarReenvios([...devolvidas, setimo], [setimo], guardadas);
  assertEquals(r.reais.map((l) => l.bank_ref_id), ["p7"]);
  assertEquals(r.reenvios, []);
});

Deno.test("um dos 6 pedágios volta com código novo → reenvio ligado ao que sumiu da busca", () => {
  const pedagio = { amount: 5.7, transaction_type: "debit", description: "ARTERIS LITORAL SUL", transaction_date: "2026-04-30" };
  const guardadas = ["p1", "p2", "p3", "p4", "p5", "p6"].map((r, i) => guardada(`g${i}`, r, pedagio));
  const devolvidas = ["p1", "p2", "p3", "p4", "p5", "p6-novo"].map((r) => linha(r, pedagio));
  const nova = devolvidas[5];
  const r = separarReenvios(devolvidas, [nova], guardadas);
  assertEquals(r.reais, []);
  assertEquals(r.reenvios.map((x) => x.guardada.bank_ref_id), ["p6"]);
});

Deno.test("conteúdo diferente (valor, descrição, conta, parcela, tipo) → real", () => {
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
    assertEquals(separarReenvios([nova], [nova], g).reais.length, 1, JSON.stringify(extra));
  }
});

Deno.test("chave ignora espaços e maiúsculas na descrição e o sinal do valor", () => {
  assertEquals(
    chaveDoConteudo(linha("a", { description: "  Inclusao  de Pagamento CICLO Corrente " , amount: -1000 })),
    chaveDoConteudo(linha("b")),
  );
});
