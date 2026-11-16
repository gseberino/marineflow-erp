import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { cabecalhosDoHistorico } from "./historico-ator.ts";

Deno.test("cabeçalhos do histórico: autor uuid vai junto da origem", () => {
  assertEquals(cabecalhosDoHistorico("707ceaf2-462c-429d-90a5-f7cedbb097cb", "assistente_whatsapp"), {
    "x-mf-origem": "assistente_whatsapp",
    "x-mf-ator": "707ceaf2-462c-429d-90a5-f7cedbb097cb",
  });
});

Deno.test("cabeçalhos do histórico: sem autor (ou autor que não é uuid) só a origem", () => {
  assertEquals(cabecalhosDoHistorico(null, "servidor"), { "x-mf-origem": "servidor" });
  assertEquals(cabecalhosDoHistorico("Gustavo", "assistente_max"), { "x-mf-origem": "assistente_max" });
});
