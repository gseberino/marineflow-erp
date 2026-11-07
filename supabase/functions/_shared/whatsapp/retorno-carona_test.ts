// Retorno rápido, F2 (P11.3): a carona do retorno, com banco falso.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { caronaDoRetorno } from "./retorno-carona.ts";

const banco = (data: unknown, error: unknown = null) => ({
  chamadas: 0,
  rpc(_fn: string, _p: unknown) {
    this.chamadas++;
    return Promise.resolve({ data, error });
  },
});
const TEXTO = "Retorno: 2 esperando (Rodrigo, desde 09:12) · *retorno*";

Deno.test("carona: devolve o texto pronto do banco", async () => {
  assertEquals(await caronaDoRetorno(banco({ texto: TEXTO }), "dono", {}), TEXTO);
});

Deno.test("carona: turno com cartão de sim, opções, fluxo ou erro não pergunta ao banco", async () => {
  for (const turno of [{ proposal: {} }, { options: [] }, { fluxo: {} }, { error: "x" }]) {
    const b = banco({ texto: TEXTO });
    assertEquals(await caronaDoRetorno(b, "dono", turno), null);
    assertEquals(b.chamadas, 0);
  }
});

Deno.test("carona: erro do banco, resposta vazia ou texto fora do formato = sem carona; nunca lança", async () => {
  assertEquals(await caronaDoRetorno(banco(null, { code: "PGRST202" }), "dono", {}), null);
  assertEquals(await caronaDoRetorno(banco(null), "dono", {}), null);
  assertEquals(await caronaDoRetorno(banco({ texto: "outra coisa" }), "dono", {}), null);
  assertEquals(await caronaDoRetorno({ rpc: () => Promise.reject(new Error("rede")) }, "dono", {}), null);
  assertEquals(await caronaDoRetorno(banco({ texto: TEXTO }), "", {}), null);
});
