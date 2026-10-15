import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { formatoDoResumoNoBanco, lerFormatoDoResumo } from "./formato.ts";

Deno.test("lerFormatoDoResumo: só 'sombra' e 'novo' mudam; o resto é 'antigo'", () => {
  assertEquals(lerFormatoDoResumo("novo"), "novo");
  assertEquals(lerFormatoDoResumo(" Sombra "), "sombra");
  assertEquals(lerFormatoDoResumo('"novo"'), "novo");
  for (const v of [undefined, null, "", "antigo", "NOVO2", "on", 1, {}]) assertEquals(lerFormatoDoResumo(v), "antigo", String(v));
});

function falsoAdmin(r: { data?: unknown; error?: unknown } | Error) {
  return {
    from: () => ({
      select: () => ({
        eq: () => ({
          maybeSingle: () => (r instanceof Error ? Promise.reject(r) : Promise.resolve(r)),
        }),
      }),
    }),
  };
}

Deno.test("formatoDoResumoNoBanco: lê a chave; erro ou ausência = antigo", async () => {
  assertEquals(await formatoDoResumoNoBanco(falsoAdmin({ data: { value: "novo" } })), "novo");
  assertEquals(await formatoDoResumoNoBanco(falsoAdmin({ data: null })), "antigo");
  assertEquals(await formatoDoResumoNoBanco(falsoAdmin({ error: { code: "42501" } })), "antigo");
  assertEquals(await formatoDoResumoNoBanco(falsoAdmin(new Error("rede"))), "antigo");
});
