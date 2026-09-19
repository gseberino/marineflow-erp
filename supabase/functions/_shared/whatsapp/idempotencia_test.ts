// Run: deno test supabase/functions/_shared/whatsapp/idempotencia_test.ts
import { assert, assertEquals, assertNotEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { chaveDeEnvio, diaLocal, hashCurto, liberarEnvio, reservarEnvio } from "./idempotencia.ts";

Deno.test("hashCurto é determinístico e muda com o texto", () => {
  assertEquals(hashCurto("Olá, tudo bem?"), hashCurto("Olá, tudo bem?"));
  assertNotEquals(hashCurto("Olá, tudo bem?"), hashCurto("Olá, tudo bem!"));
  assert(/^[0-9a-z]+$/.test(hashCurto("qualquer coisa")));
});

Deno.test("chaveDeEnvio descarta partes vazias, troca espaço por _ e limita o tamanho", () => {
  assertEquals(chaveDeEnvio("cobranca", "abc-1", null, undefined, "", "2026-09-19"), "cobranca:abc-1:2026-09-19");
  assertEquals(chaveDeEnvio("os link", 42), "os_link:42");
  assert(chaveDeEnvio("x".repeat(500)).length <= 200);
});

Deno.test("diaLocal usa o fuso de Brasília (UTC 02:00 ainda é o dia anterior)", () => {
  // 02:00Z de 20/09 = 23:00 de 19/09 em Brasília (UTC-3).
  assertEquals(diaLocal(new Date("2026-09-20T02:00:00Z")), "2026-09-19");
  assertEquals(diaLocal(new Date("2026-09-20T12:00:00Z")), "2026-09-20");
});

// Cliente falso: guarda as chaves num Set e responde 23505 na repetida.
function clienteFalso() {
  const chaves = new Set<string>();
  const tabela = {
    insert: (row: { chave: string }) => {
      if (chaves.has(row.chave)) return Promise.resolve({ error: { code: "23505", message: "dup" } });
      chaves.add(row.chave);
      return Promise.resolve({ error: null });
    },
    delete: () => ({ eq: (_c: string, v: string) => { chaves.delete(v); return Promise.resolve({ error: null }); } }),
  };
  return { chaves, from: (_t: string) => tabela };
}

Deno.test("reservarEnvio: primeira vez é nova, repetida é repetida, liberar reabre", async () => {
  const db = clienteFalso();
  assertEquals(await reservarEnvio(db, "cobranca:1:2026-09-19"), "nova");
  assertEquals(await reservarEnvio(db, "cobranca:1:2026-09-19"), "repetida");
  await liberarEnvio(db, "cobranca:1:2026-09-19");
  assertEquals(await reservarEnvio(db, "cobranca:1:2026-09-19"), "nova");
});

Deno.test("reservarEnvio: erro de banco não bloqueia o envio (fail open)", async () => {
  const db = { from: () => ({ insert: () => Promise.resolve({ error: { code: "57P01", message: "down" } }) }) };
  assertEquals(await reservarEnvio(db, "x"), "erro");
});
