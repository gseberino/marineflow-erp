// As palavras do secretário (16/10/2026). O que se protege: o agradecimento/cumprimento puro não é "sem resposta"
// (caso real de 15/10: o Nelson, "Bom dia Gustavo! Ótimo 👍", aparecia no fechamento); a pergunta ou o pedido junto
// com o "obrigado" continuam sendo mensagem que espera resposta; áudio/foto não são lidos como agradecimento.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { ehClienteGenerico, pareceSoAgradecimento } from "./palavras.ts";

Deno.test("só agradecimento/cumprimento/confirmação/emoji: os casos reais", () => {
  for (const t of [
    "Bom dia Gustavo! Ótimo 👍", "Obrigado!", "ok", "👍", "🙏🙏", "Valeu, show!", "Blz", "Perfeito, combinado.", "Boa tarde",
    "Obrigada", "Ta bom", "Fechado 🤝", "Beleza, obrigado Gustavo", "Ah ok", "Muito obrigado!!", "👍🏻",
  ]) {
    assertEquals(pareceSoAgradecimento(t), true, t);
  }
});

Deno.test("não é só agradecimento: pergunta, pedido, conteúdo, áudio/foto, vazio", () => {
  for (const t of [
    "Obrigado, e quanto fica?", "Bom dia, consegue vir hoje?", "ok, me manda o orçamento", "Tudo bem?", "Sim, já fechei",
    "Obrigado, amanhã eu levo o barco", "Ok, pode seguir", "Bom dia, preciso de um orçamento", "[audio]", "[image]",
    "🎤 Obrigado", "", null, "...", "Isso o segundo mas tirando o inversor",
  ]) {
    assertEquals(pareceSoAgradecimento(t), false, String(t));
  }
});

Deno.test("cadastro genérico (a regra que veio de secretario-candidatos.ts)", () => {
  assertEquals(ehClienteGenerico("Cliente Final"), true);
  assertEquals(ehClienteGenerico("consumidor final"), true);
  assertEquals(ehClienteGenerico("Miguel"), false);
});
