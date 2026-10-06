// Resumo que é recusa não vira pendência (06/10/2026). Caso real: "Não achei 'Eliane Huberti'.
// Cadastre antes" virou pendência, e o modelo disse "preparei, falta a sua confirmação".
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { resumoQueRecusa } from "./agent.ts";

Deno.test("linha única ⚠️ das tools de caixa/anotação é recusa; o resto vira pendência", () => {
  assertEquals(resumoQueRecusa("anotar_transacao_do_banco", "⚠️ Qual \"João\"? João Silva; João Pedro"), { error: "Qual \"João\"? João Silva; João Pedro", nada_registrado: true });
  assertEquals(resumoQueRecusa("lancar_no_caixa", "⚠️ O que foi? (ex.: almoço da equipe)")?.error, "O que foi? (ex.: almoço da equipe)");
  // Resumo de verdade, com aviso dentro: é pendência.
  assertEquals(resumoQueRecusa("anotar_transacao_do_banco", "- Quando chegar…\n- ⚠️ sem documento"), null);
  // Outra tool: não se aplica.
  assertEquals(resumoQueRecusa("send_service_order_link", "⚠️ algo"), null);
});
