import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  contatoEncerrou, conversaEncerradaPeloContato, MOTIVO_CONTATO_ENCERROU, ULTIMAS_RECEBIDAS,
} from "./contato-encerrou.ts";

// Frases reais do WhatsApp (conversa do Miguel, 06 e 07/10/2026) e de outros contatos.
const MIGUEL_1415 = "André você demora muito pra responder e por isso acabei fechando com outra empresa. Obrigado";

Deno.test("contatoEncerrou: a frase do Miguel de 07/10 14:15 encerra", () => {
  assert(contatoEncerrou(MIGUEL_1415));
});

Deno.test("contatoEncerrou: frases que NÃO são desistência ficam de fora", () => {
  for (const t of [
    "Sim, já fechei",
    "a outra é composta por:",
    "Tenho em análise 2 propostas",
    "Não trabalho mais lá faz alguns anos",
    "esse nao vou ter amigo",
    "vou fechar com vocês",
    "não preciso mais do que 2 baterias",
    "desisti de ir hoje",
    // Áudio real do Miguel de 07/10 09:02 — "fechar" e "outras" longe um do outro.
    "🎤 Olá, Gustavo. Vamos deixar isto da câmera para depois, porque eu preciso de fechar a solução completa hoje, ou consigo, ou com outras hipóteses que eu tenho.",
    "",
    // Revisão de 15/10: ameaça de ir embora e impaciência são quem MAIS pede resposta.
    "Se não me responderem hoje vou fechar com outra empresa",
    "Vamos fechar com outra se o preço não baixar",
    "não quero mais esperar, quando vocês vêm?",
    // Áudio real de 25/07/2026 (pescaria).
    "🎤 tem dia que eu não trago nada porque não preciso mais de peixe, se ele está cheio de peixe que nem tem para se trazer",
    "resolvi o problema com outro cabo, mas a bomba ainda não liga",
    "fiz a instalação com outra peça",
    // Pergunta depois da frase, na mesma mensagem: comprou só a peça e quer o serviço.
    "Comprei a peça com outro fornecedor, vocês instalam?",
    "Comprei a bateria com outro fornecedor. Vocês conseguem instalar amanhã?",
    "Fiz o pix com outra conta, pode conferir?",
    "não preciso mais do orçamento?",
  ]) {
    assertEquals(contatoEncerrou(t), false, `não deveria encerrar: "${t}"`);
  }
  assertEquals(contatoEncerrou(null), false);
  assertEquals(contatoEncerrou(undefined), false);
});

Deno.test("contatoEncerrou: desistência dita com outras palavras encerra", () => {
  for (const t of [
    "não tenho mais interesse",
    "desisti do orçamento",
    "NÃO QUEREMOS MAIS, obrigado",
    "Contratei com outro fornecedor",
    "optamos com a concorrente",
    "Já fechei com outra oficina",
    "não quero mais o orçamento",
    "não preciso mais do serviço, obrigado",
    "não quero mais não",
    // Quem escreveu foi o dono, contando o caso (07/10 14:51) — a frase em si é de quem já fechou.
    "🎤 O Miguel respondeu que fechou com outro, mas eu acredito que ele pode não ter fechado ainda.",
  ]) {
    assert(contatoEncerrou(t), `deveria encerrar: "${t}"`);
  }
});

Deno.test("conversaEncerradaPeloContato: a lista do Miguel (mais recente primeiro) encerra", () => {
  assert(conversaEncerradaPeloContato(["Sim, já fechei", "[conteúdo vazio]", MIGUEL_1415, "🎤 Olá, Gustavo."]));
});

Deno.test("conversaEncerradaPeloContato: olha só as 5 mais recentes", () => {
  assertEquals(ULTIMAS_RECEBIDAS, 5);
  const seis = ["oi", "tudo bem", "e aí", "alô", "bom dia", MIGUEL_1415];
  assertEquals(conversaEncerradaPeloContato(seis), false, "a 6ª mais recente fica fora da janela");
  assertEquals(conversaEncerradaPeloContato(seis.slice(1)), true, "a 5ª ainda conta");
  assertEquals(conversaEncerradaPeloContato([]), false);
  assertEquals(conversaEncerradaPeloContato([null, undefined, "ok"]), false);
});

Deno.test("conversaEncerradaPeloContato: pergunta depois da desistência reabre (revisão de 15/10)", () => {
  assertEquals(conversaEncerradaPeloContato(["pensando bem, quando vocês podem vir?", "não quero mais o orçamento"]), false);
  // Pergunta ANTES da desistência não reabre: o que vale é o que veio depois.
  assert(conversaEncerradaPeloContato(["Sim, já fechei", MIGUEL_1415, "vocês fazem câmera também?"]));
});

Deno.test("MOTIVO_CONTATO_ENCERROU: texto em português, sem jargão", () => {
  assertEquals(MOTIVO_CONTATO_ENCERROU, "contato encerrou (fechou com outra empresa ou desistiu)");
});
