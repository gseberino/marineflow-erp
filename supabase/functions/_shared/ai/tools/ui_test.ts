// optimize_text (22/10/2026): a HBR atende barco E motorhome/trailer — o rótulo do texto reescrito
// não pode dizer "náutico"/"em embarcação" para tudo, e o modelo não troca motorhome por barco.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { CONTEXT_LABELS } from "./ui.ts";

Deno.test("rótulos do optimize_text servem a barco e a veículo", () => {
  assertEquals(CONTEXT_LABELS.problem_description, "descrição de problema técnico em embarcação ou veículo");
  assertEquals(CONTEXT_LABELS.service_notes, "observações de serviço técnico");
  for (const r of Object.values(CONTEXT_LABELS)) assert(!/n[áa]utic/i.test(r), r);
});

Deno.test("o pedido de reescrita manda manter o tipo da unidade", async () => {
  const fonte = await Deno.readTextFile(new URL("./ui.ts", import.meta.url));
  assertStringIncludes(fonte, "nunca chame motorhome, trailer ou camper de barco");
  assert(!fonte.includes("comunicação técnica náutica"));
});
