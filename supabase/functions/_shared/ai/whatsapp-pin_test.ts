import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { hashPin, verifyPin } from "./whatsapp-pin.ts";

Deno.test("hashPin/verifyPin: PIN correto verifica true", async () => {
  const stored = await hashPin("4321");
  assertEquals(await verifyPin("4321", stored), true);
});

Deno.test("hashPin/verifyPin: PIN errado verifica false", async () => {
  const stored = await hashPin("4321");
  assertEquals(await verifyPin("0000", stored), false);
});

Deno.test("hashPin: dois hashes do mesmo PIN são diferentes (salt aleatório)", async () => {
  const a = await hashPin("4321");
  const b = await hashPin("4321");
  assertEquals(a === b, false);
});

Deno.test("verifyPin: valor vazio/nulo nunca verifica true", async () => {
  assertEquals(await verifyPin("4321", null), false);
  assertEquals(await verifyPin("4321", undefined), false);
  assertEquals(await verifyPin("4321", ""), false);
  assertEquals(await verifyPin("4321", "malformado-sem-dois-pontos"), false);
});
