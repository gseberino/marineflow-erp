// Os comandos novos da tarde (secretário, Passo 3): a revisão respondida de uma vez, a cobrança antiga do dia 1
// e a pergunta da sexta — o que é lido e, principalmente, o que NÃO pode colidir com a confirmação (1/2/sim/
// não), com os comprovantes nem com a pergunta ativa. Spec: spec-secretario-fechamento.md §6.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { lerComandoDoSecretario } from "./comandos.ts";
import { parseConfirmationReply, parseOptionReply } from "../ai/whatsapp-channel.ts";
import { lerComando } from "../comprovantes/respostas.ts";
import { lerNumero, lerSimNao, normalizarResposta, pareceRespostaCurta } from "../whatsapp/pergunta-ativa.ts";

const S = (letra: string) => ({ letra, acao: "adiar", quando: "semana" });
const Q = (letra: string) => ({ letra, acao: "adiar", quando: "15dias" });
const T = (letra: string) => ({ letra, acao: "tirado" });

const COMANDOS: Array<[string, unknown]> = [
  // a revisão de uma vez (o exemplo do texto e as variações de quem digita rápido)
  ["C semana, B tira, G 15 dias", { comando: "lote", itens: [S("C"), T("B"), Q("G")] }],
  ["c semana; b tira; g 15 dias.", { comando: "lote", itens: [S("C"), T("B"), Q("G")] }],
  ["C semana e B tira", { comando: "lote", itens: [S("C"), T("B")] }],
  ["C semana B tira G 15d", { comando: "lote", itens: [S("C"), T("B"), Q("G")] }],
  ["*C* faço esta semana, *G* me lembra em 15 dias", { comando: "lote", itens: [S("C"), Q("G")] }],
  ["C semana\nB tira\nG 15 dias", { comando: "lote", itens: [S("C"), T("B"), Q("G")] }],
  ["tira B, C feito", { comando: "lote", itens: [T("B"), { letra: "C", acao: "feito" }] }],
  ["D não, F amanhã, H segunda-feira", {
    comando: "lote", itens: [{ letra: "D", acao: "nao" }, { letra: "F", acao: "adiar", quando: "amanha" }, { letra: "H", acao: "adiar", quando: "segunda" }],
  }],
  ["G 15 dias", { comando: "lote", itens: [Q("G")] }],
  ["D semana", { comando: "lote", itens: [S("D")] }],
  ["G daqui a 15 dias", { comando: "lote", itens: [Q("G")] }],
  // um par só com ação de antes: o comando de antes (nada muda para quem já usa)
  ["C tira", { comando: "acao", letra: "C", acao: "tirado" }],
  // a cobrança antiga da revisão do mês
  ["F cobrar", { comando: "antiga", letra: "F", acao: "cobrar" }],
  ["g negociar", { comando: "antiga", letra: "G", acao: "negociar" }],
  ["F baixa", { comando: "antiga", letra: "F", acao: "baixa" }],
  ["F dar baixa", { comando: "antiga", letra: "F", acao: "baixa" }],
  // a pergunta da sexta
  ["ajudou", { comando: "semana", resposta: "ajudou" }],
  ["Ajudou!", { comando: "semana", resposta: "ajudou" }],
  ["pouco", { comando: "semana", resposta: "pouco" }],
  ["ajudou pouco", { comando: "semana", resposta: "pouco" }],
  ["atrapalhou", { comando: "semana", resposta: "atrapalhou" }],
  ["a semana ajudou", { comando: "semana", resposta: "ajudou" }],
  ["semana atrapalhou", { comando: "semana", resposta: "atrapalhou" }],
];

Deno.test("lerComandoDoSecretario (Passo 3): lote, cobrança antiga e a pergunta da sexta", () => {
  for (const [texto, esperado] of COMANDOS) assertEquals(lerComandoDoSecretario(texto), esperado, texto);
});

Deno.test("o lote de 5 assuntos passa do antigo limite de 60 caracteres e ainda é lido", () => {
  const t = "C faço esta semana, B tira, G me lembra em 15 dias, Q semana, P daqui a 15 dias";
  assert(t.length > 60);
  assertEquals((lerComandoDoSecretario(t) as { itens: unknown[] }).itens.length, 5);
});

const NAO_SAO_COMANDO = [
  // "15" sozinho é a opção 15 de um menu, não "15 dias"
  "a 15", "G 15", "15 dias", "15",
  // a mesma letra solta com palavra que não é ação; frases
  // ("a semana" sozinho É comando: o item A fica com o dono esta semana — a letra vale como qualquer outra)
  "A e B", "A, B e C feitos", "C semanal", "C semana que vem", "C semana, B", "C semana, cobra esse", "semana",
  "a semana foi boa", "ajudou muito obrigado", "pouco a pouco", "cobra esse", "F cobrar o Lírio", "baixa", "negociar",
  "lote antigo", "pendentes", "pular", "depois",
  // confirmação
  "sim", "não", "1", "2", "ok", "s", "n",
];

Deno.test("lerComandoDoSecretario (Passo 3): o que não é comando continua não sendo", () => {
  for (const t of NAO_SAO_COMANDO) assertEquals(lerComandoDoSecretario(t), null, t);
});

Deno.test("nenhum comando novo é confirmação, opção de menu, comando dos comprovantes nem resposta curta", () => {
  for (const [texto] of COMANDOS) {
    assertEquals(parseConfirmationReply(texto), null, `confirmação: ${texto}`);
    assertEquals(parseOptionReply(texto, 99), null, `opção: ${texto}`);
    assertEquals(lerComando(texto), null, `comprovantes: ${texto}`);
    const n = normalizarResposta(texto);
    assertEquals(lerSimNao(n), null, `sim/não/ok: ${texto}`);
    assertEquals(lerNumero(n, 99), null, `número: ${texto}`);
    assertEquals(pareceRespostaCurta(texto), false, `resposta curta: ${texto}`);
  }
});
