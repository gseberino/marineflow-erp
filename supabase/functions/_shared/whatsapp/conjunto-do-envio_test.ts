import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { orcamentosQueValem, outrosOrcamentosDoConjunto } from "./conjunto-do-envio.ts";

const A = "00000000-0000-4000-8000-00000000000a";
const B = "00000000-0000-4000-8000-00000000000b";
const C = "00000000-0000-4000-8000-00000000000c";
const X = "00000000-0000-4000-8000-0000000000ff";

Deno.test("orcamentosQueValem: só os do conjunto, sem repetir e sem o principal", () => {
  assertEquals(orcamentosQueValem(A, [B, B, X, A, C], [A, B, C]), [B, C]);
  assertEquals(orcamentosQueValem(A, [], [A, B]), []);
});

function falso(tabelas: { meu: unknown; itens: unknown; erro?: boolean }) {
  let chamada = 0;
  return {
    from: (_t: string) => {
      chamada++;
      const minha = chamada;
      const q: any = {
        select: () => q,
        eq: () => q,
        maybeSingle: async () => ({ data: tabelas.meu, error: tabelas.erro ? { message: "x" } : null }),
        then: (ok: (v: unknown) => unknown) => ok({ data: minha === 2 ? tabelas.itens : null, error: null }),
      };
      return q;
    },
  };
}

Deno.test("outrosOrcamentosDoConjunto: lê o conjunto ativo e filtra", async () => {
  const db = falso({ meu: { conjunto_id: "c1" }, itens: [{ service_order_id: A }, { service_order_id: B }] });
  assertEquals(await outrosOrcamentosDoConjunto(db, A, [B, X]), [B]);
});

Deno.test("outrosOrcamentosDoConjunto: sem pedido, sem conjunto ou com erro = nada", async () => {
  assertEquals(await outrosOrcamentosDoConjunto(falso({ meu: null, itens: [] }), A, []), []);
  assertEquals(await outrosOrcamentosDoConjunto(falso({ meu: null, itens: [] }), A, [B]), []);
  assertEquals(await outrosOrcamentosDoConjunto(falso({ meu: { conjunto_id: "c1" }, itens: [], erro: true }), A, [B]), []);
});
