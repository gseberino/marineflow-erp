import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { hashPin, normalizarSimComPin, pinNoTexto, verifyPin } from "./whatsapp-pin.ts";

// Retorno (05/11/2026). O PIN daqui é inventado, com hash gerado no próprio teste.
Deno.test("normalizarSimComPin: a pontuação e o áudio viram a forma de sempre", () => {
  for (const t of ["Sim, 7391.", "Sim. 7391", "🎤 Sim, 7391.", "sim: 7391", "  SIM - 7391!  "]) {
    assertEquals(normalizarSimComPin(t), "sim 7391", t);
  }
});

Deno.test("normalizarSimComPin: só a forma exata; o resto volta igual", () => {
  for (const t of ["sim 7391 reais", "sim, mas 7391", "sim, pode", "sim", "7391", "assim, 7391"]) {
    assertEquals(normalizarSimComPin(t), t);
  }
});

Deno.test("pinNoTexto: acha o PIN solto na frase, inteiro ou com os dígitos separados", async () => {
  const stored = await hashPin("7391");
  for (const t of ["1 7391", "2 B 7391", "manda 7391 por favor", "7 3 9 1", "7.3.9.1", "sim, mas 7391"]) {
    assertEquals(await pinNoTexto(t, stored), true, t);
  }
});

Deno.test("pinNoTexto: número que não é o PIN não dispara", async () => {
  const stored = await hashPin("7391");
  for (const t of ["2 baterias", "custa 7392", "173910", "R$ 500", "", "sem número nenhum"]) {
    assertEquals(await pinNoTexto(t, stored), false, t);
  }
});

Deno.test("pinNoTexto: sem PIN cadastrado, nada dispara", async () => {
  assertEquals(await pinNoTexto("7391", null), false);
  assertEquals(await pinNoTexto("7391", undefined), false);
});

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

// P16: o gatilho _whatsapp_mascarar_pin faz a mesma conta em SQL. Os 3 pares estão também em supabase/tests/pin_mascarar.sql:
// se a conta mudar aqui sem mudar lá, a máscara para de achar o PIN, calada.
Deno.test("verifyPin: o hash é o mesmo que o gatilho da máscara calcula em SQL", async () => {
  const pares = [
    ["sal-a", "7391", "00fe044f96335b6e8cc5890a19455da862d3380e679be60a7a75722a957b33af"],
    ["3f0c2f5e-0000-4000-8000-000000000001", "004821", "01325accc9677860a5f56b2c53656b688c0c032183edcf277650631440aecb4a"],
    ["x", "123", "96d83a375baee82501356c68b3c0bf2133f902e74776e517d205f4e9da5a41ec"],
  ];
  for (const [salt, pin, hash] of pares) {
    assertEquals(await verifyPin(pin, `${salt}:${hash}`), true);
  }
});
