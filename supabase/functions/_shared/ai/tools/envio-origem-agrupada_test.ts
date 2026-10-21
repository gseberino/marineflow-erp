// Envio de um orçamento que foi agrupado (20/10/2026): a origem fica cancelada, sem link. Antes o
// assistente dizia só "está CANCELADA — mude o status na tela", o que mandaria o dono reabrir um
// histórico; agora aponta o orçamento que vale (o agrupado).
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { frasesDaOrdemCancelada } from "./whatsapp.ts";

Deno.test("origem agrupada: aviso e erro apontam o orçamento agrupado", () => {
  const f = frasesDaOrdemCancelada({
    service_order_number: "ORÇ-00096",
    status: "cancelled",
    cancellation_reason: "Agrupado em ORÇ-00125 (reúne ORÇ-00078, ORÇ-00096)",
  });
  assertStringIncludes(f.aviso, "ORÇ-00096 foi agrupado em ORÇ-00125");
  assertStringIncludes(f.aviso, "mande o ORÇ-00125");
  assertEquals(f.erro, "ORÇ-00096 foi agrupado em ORÇ-00125 e não vale mais sozinho: mande o ORÇ-00125 ao cliente.");
});

Deno.test("cancelada comum: segue a frase de sempre", () => {
  const f = frasesDaOrdemCancelada({ service_order_number: "OS-00060", status: "cancelled", cancellation_reason: "Cliente desistiu" });
  assertEquals(f.aviso, "⚠️ A ordem está CANCELADA — o envio será recusado.");
  assertStringIncludes(f.erro, "A ordem OS-00060 está CANCELADA");
});
