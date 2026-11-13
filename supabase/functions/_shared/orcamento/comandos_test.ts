// Retorno rápido, F5 (P10.3): o leitor das palavras do dono sobre o orçamento, contra a matriz 7.2 da spec.
//
// Fica em _shared/orcamento/ e não importa _shared/ai/ (isolamento_test.ts varre esta pasta, testes inclusive). A matriz
// contra os leitores do assistente (confirmação, opção, PDF, comprovante) mora em _shared/whatsapp/orcamento-comandos_test.ts.
// Frases e números inventados: nenhuma vem de whatsapp_messages nem de ai_operator_messages.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  type ComandoDoOrcamento,
  frasesDoOrcamento,
  LETRA_DA_PALAVRA,
  lerComandoDoOrcamento,
  MOTIVO_DA_LETRA,
} from "./comandos.ts";
import { lerComandoDoRetorno } from "../retorno/comandos.ts";
import { lerComandoDoParceiro } from "../parceiro/comandos.ts";
import { lerComandoDoSecretario } from "../secretario/comandos.ts";

const TABELA: Array<[string, ComandoDoOrcamento]> = [
  // *segura N* e *solta N*: o número do orçamento, com ou sem a sigla, com os zeros à esquerda
  ["segura 151", { comando: "segura", numero: 151 }],
  ["Segura 151.", { comando: "segura", numero: 151 }],
  ["*segura 151*", { comando: "segura", numero: 151 }],
  ["🎤 Segura 151.", { comando: "segura", numero: 151 }],
  ["segura orc 151", { comando: "segura", numero: 151 }],
  ["segura orç 151", { comando: "segura", numero: 151 }],
  ["segura orç-00151", { comando: "segura", numero: 151 }],
  ["Segura ORÇ-00151", { comando: "segura", numero: 151 }],
  ["segura ORC-00151", { comando: "segura", numero: 151 }],
  ["segura orc00151", { comando: "segura", numero: 151 }],
  ["segura orcamento 151", { comando: "segura", numero: 151 }],
  ["segura orçamento 151", { comando: "segura", numero: 151 }],
  ["segura 00151", { comando: "segura", numero: 151 }],
  ["segura 12", { comando: "segura", numero: 12 }],
  ["segura 12345", { comando: "segura", numero: 12345 }],
  ["solta 151", { comando: "solta", numero: 151 }],
  ["Solta ORÇ-00151.", { comando: "solta", numero: 151 }],
  ["solta orcamento 151", { comando: "solta", numero: 151 }],
  // todos
  ["segura orcamentos", { comando: "segura_todos" }],
  ["segura orçamentos", { comando: "segura_todos" }],
  ["Segura Orçamentos.", { comando: "segura_todos" }],
  ["solta orcamentos", { comando: "solta_todos" }],
  ["solta orçamentos", { comando: "solta_todos" }],
  // *motivo N <letra>*: A sumiu, B fechou com outro, C desistiu, D preço, F prazo, G outro
  ["motivo 151 a", { comando: "motivo", numero: 151, letra: "A" }],
  ["motivo 151 b", { comando: "motivo", numero: 151, letra: "B" }],
  ["motivo 151 B", { comando: "motivo", numero: 151, letra: "B" }],
  ["Motivo 151 C.", { comando: "motivo", numero: 151, letra: "C" }],
  ["motivo 151 d", { comando: "motivo", numero: 151, letra: "D" }],
  ["motivo 151 f", { comando: "motivo", numero: 151, letra: "F" }],
  ["motivo 151 g", { comando: "motivo", numero: 151, letra: "G" }],
  ["motivo orc 151 b", { comando: "motivo", numero: 151, letra: "B" }],
  ["motivo ORÇ-00151 b", { comando: "motivo", numero: 151, letra: "B" }],
  ["*motivo 151 B*", { comando: "motivo", numero: 151, letra: "B" }],
  // a palavra vale a letra
  ["motivo 151 preco", { comando: "motivo", numero: 151, letra: "D" }],
  ["motivo 151 preço", { comando: "motivo", numero: 151, letra: "D" }],
  ["motivo 151 prazo", { comando: "motivo", numero: 151, letra: "F" }],
  ["motivo 151 desistiu", { comando: "motivo", numero: 151, letra: "C" }],
  ["motivo 151 sumiu", { comando: "motivo", numero: 151, letra: "A" }],
  ["motivo 151 outro", { comando: "motivo", numero: 151, letra: "G" }],
  ["motivo 151 outra empresa", { comando: "motivo", numero: 151, letra: "B" }],
  ["motivo 151 fechou com outro", { comando: "motivo", numero: 151, letra: "B" }],
  ["Motivo ORÇ-00151 Outra empresa.", { comando: "motivo", numero: 151, letra: "B" }],
];

// A conversa continua conversa: as linhas "não lê" da matriz 7.2 e as perguntas.
const CONVERSA = [
  // 1 dígito pode ser o item 1 do cartão; sem número, não é comando
  "segura 1", "segura", "solta", "solta 1", "segura 0", "segura orc 1", "motivo 1 b",
  // A é a letra do dia do Secretário; "151 b" sem palavra na frente vira armadilha
  "segura a", "solta a", "151 b", "151", "b",
  // letra fora de A, B, C, D, F e G não é motivo
  "motivo 151 e", "motivo 151 h", "motivo 151 i", "motivo 151 z", "motivo 151", "motivo b", "motivo", "motivo 151 b c",
  "motivo 151 caro", "motivo 151 fechou", "motivo 151 b sim 7391",
  // pergunta é conversa
  "segura 151?", "solta 151?", "segura orcamentos?", "motivo 151 b?", "motivo 151 preço?",
  // número grande demais ou em frase
  "segura 123456", "segura 151 do joão", "segura o 151 por favor", "segura 151 e 152", "segura 151 152",
  // as palavras das outras camadas
  "segura cliente", "segura cliente Ana", "segura recibos", "segura tudo", "segura patio", "segura pátio", "solta tudo",
  "orcamentos", "orçamentos", "lista orcamentos", "segura orcamento", "solta orcamento",
  "1 a", "1 b", "1 c", "1 d", "1 a sim 7391", "nao 1", "não 1", "ver 1", "resolvido 1", "enviado 1", "dita 1 pode ser",
  "errado z", "retorno", "parceiro", "parceiro 151", "", "   ",
];

Deno.test("lerComandoDoOrcamento: cada linha que casa da matriz 7.2, com acento, maiúscula, negrito, ponto e 🎤", () => {
  for (const [t, esperado] of TABELA) assertEquals(lerComandoDoOrcamento(t), esperado, t);
});

Deno.test("lerComandoDoOrcamento: as linhas que não leem da matriz 7.2 e a pergunta continuam conversa", () => {
  for (const t of CONVERSA) assertEquals(lerComandoDoOrcamento(t), null, JSON.stringify(t));
});

Deno.test("lerComandoDoOrcamento: acima de 60 caracteres não lê", () => {
  const longo = `segura 151${" ".repeat(60)}`;
  assert(longo.length > 60);
  assertEquals(lerComandoDoOrcamento(longo), null);
  assertEquals(lerComandoDoOrcamento(`motivo 151 ${"b".padStart(55, " ")}`), null);
  // até 60, lê
  const curto = `segura 151${" ".repeat(50)}`;
  assertEquals(curto.length, 60);
  assertEquals(lerComandoDoOrcamento(curto), { comando: "segura", numero: 151 });
});

Deno.test("MOTIVO_DA_LETRA e LETRA_DA_PALAVRA: a lista fechada da 3.4, sem E, e cada palavra cai na letra do sentido", () => {
  assertEquals(MOTIVO_DA_LETRA, {
    A: "sumiu", B: "fechou_com_outro", C: "desistiu", D: "preco", F: "prazo", G: "outro",
  });
  assertEquals(Object.keys(MOTIVO_DA_LETRA).sort(), ["A", "B", "C", "D", "F", "G"]);
  assertEquals(LETRA_DA_PALAVRA["sumiu"], "A");
  assertEquals(LETRA_DA_PALAVRA["outra empresa"], "B");
  assertEquals(LETRA_DA_PALAVRA["fechou com outro"], "B");
  assertEquals(LETRA_DA_PALAVRA["desistiu"], "C");
  assertEquals(LETRA_DA_PALAVRA["preco"], "D");
  assertEquals(LETRA_DA_PALAVRA["prazo"], "F");
  assertEquals(LETRA_DA_PALAVRA["outro"], "G");
  // sem_motivo_antigo é só da migration de dado: nenhuma letra nem palavra o dá
  assert(!Object.values(MOTIVO_DA_LETRA).includes("sem_motivo_antigo"));
  // as palavras são sem acento (o leitor compara depois de normalizar)
  for (const p of Object.keys(LETRA_DA_PALAVRA)) assertEquals(p, p.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase(), p);
});

Deno.test("as formas fixas do orçamento casam no próprio leitor e em nenhum leitor do retorno, do parceiro ou do Secretário", () => {
  const formas = frasesDoOrcamento();
  assert(formas.length >= 10);
  for (const f of [...formas, ...formas.map((x) => `*${x}*`), ...formas.map((x) => `${x[0].toUpperCase()}${x.slice(1)}.`)]) {
    assert(lerComandoDoOrcamento(f) !== null, `o próprio leitor: ${f}`);
    assertEquals(lerComandoDoRetorno(f), null, `retorno: ${f}`);
    assertEquals(lerComandoDoParceiro(f), null, `parceiro: ${f}`);
    assertEquals(lerComandoDoSecretario(f), null, `secretário: ${f}`);
  }
  // o inverso: as palavras do retorno (as letras do aceite inclusive) e do parceiro não são lidas aqui
  for (const t of ["1 a", "1 b", "1 c", "1 d", "nao 1", "ver 1", "resolvido 1", "segura recibos", "segura tudo", "segura patio", "parceiro 74"]) {
    assertEquals(lerComandoDoOrcamento(t), null, t);
  }
});
