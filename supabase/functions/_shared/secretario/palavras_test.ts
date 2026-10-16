// As palavras do secretário (16/10/2026). O que se protege: o agradecimento/cumprimento puro não é "sem resposta"
// (caso real de 15/10: o Nelson, "Bom dia Gustavo! Ótimo 👍", aparecia no fechamento); a pergunta ou o pedido junto
// com o "obrigado" continuam sendo mensagem que espera resposta; áudio/foto não são lidos como agradecimento.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { ehClienteGenerico, PEDE_PRECO, pareceSoAgradecimento } from "./palavras.ts";
import { paraBusca } from "./base.ts";

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

Deno.test("16/10: o fornecedor que avisa ('passar o valor do frete') não está pedindo preço; quem pede, sim", () => {
  const pede = (t: string) => PEDE_PRECO.test(paraBusca(t));
  // o caso real (Jaison, fornecedor sem cadastro, 15/10 14:03): virou o B da manhã-sombra de 16/10
  assertEquals(pede("O PIX pode ser feito após a expedição finalizar e passar o valor do frete"), false);
  assertEquals(pede("vou mandar o orçamento amanhã"), false);
  for (const t of ["Pode me passar o orçamento por favor", "Consegue me passar o valor?", "pode mandar o orçamento", "me manda o orçamento", "passa o valor", "tem como enviar a cotação?", "por favor fazer o orçamento"]) {
    assertEquals(pede(t), true, t);
  }
});

Deno.test("16/10: o contato que encerra dizendo que ELE vai agir não está sem resposta; 'fico no aguardo' está", () => {
  for (const t of ["Perfeito, vou dar sequencia", "Pode deixar comigo!", "ok, assim que sair te aviso", "Beleza, já vou providenciar", "Certo, te retorno"]) {
    assertEquals(pareceSoAgradecimento(t), true, t);
  }
  for (const t of ["Claro, fico no seu aguardo meu amigo", "Aguardo seu retorno", "Perfeito, vou dar sequencia. Qual o valor do frete?", "vou dar sequencia?", "Pode deixar o barco aqui amanhã"]) {
    assertEquals(pareceSoAgradecimento(t), false, t);
  }
});
