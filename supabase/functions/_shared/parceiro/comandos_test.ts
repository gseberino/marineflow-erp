// Retorno rápido, F4 (P11.3): o leitor das palavras do dono para o parceiro, contra a matriz 7.2 da spec.
//
// Fica em _shared/parceiro/ e não importa _shared/ai/ (isolamento_test.ts varre esta pasta, testes inclusive). A matriz
// contra os leitores do assistente (confirmação, opção, PDF) mora em _shared/whatsapp/retorno-comandos_test.ts.
// Frases e números inventados: nenhuma vem de whatsapp_messages nem de ai_operator_messages.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { type ComandoDoParceiro, frasesDoParceiro, lerComandoDoParceiro } from "./comandos.ts";
import { lerComandoDoRetorno } from "../retorno/comandos.ts";
import { lerComandoDoSecretario } from "../secretario/comandos.ts";

const TABELA: Array<[string, ComandoDoParceiro]> = [
  ["parceiro", { comando: "parceiro" }],
  ["Parceiro", { comando: "parceiro" }],
  ["*parceiro*", { comando: "parceiro" }],
  ["🎤 Parceiro.", { comando: "parceiro" }],
  ["ver parceiro", { comando: "parceiro" }],
  ["parceiro 74", { comando: "parceiro_os", sigla: null, numero: "74" }],
  ["parceiro os-00074", { comando: "parceiro_os", sigla: null, numero: "OS-00074" }],
  ["Parceiro OS-00074", { comando: "parceiro_os", sigla: null, numero: "OS-00074" }],
  ["parceiro orc-00107", { comando: "parceiro_os", sigla: null, numero: "ORÇ-00107" }],
  ["parceiro ORÇ-00107", { comando: "parceiro_os", sigla: null, numero: "ORÇ-00107" }],
  ["parceiro os00074", { comando: "parceiro_os", sigla: null, numero: "OS-00074" }],
  ["parceiro mp 74", { comando: "parceiro_os", sigla: "mp", numero: "74" }],
  ["parceiro MP OS-00074", { comando: "parceiro_os", sigla: "mp", numero: "OS-00074" }],
  ["parceiro fortro 74", { comando: "parceiro_os", sigla: "fortro", numero: "74" }],
  ["parceiro Förtro 74", { comando: "parceiro_os", sigla: "fortro", numero: "74" }],
  ["1 tira 2", { comando: "tira_linha", n: 1, linha: 2 }],
  ["2 tira 1", { comando: "tira_linha", n: 2, linha: 1 }],
  ["1 tira 14", { comando: "tira_linha", n: 1, linha: 14 }],
  ["1 sabe 2", { comando: "sabe", n: 1, linha: 2 }],
  ["2 sabe 1", { comando: "sabe", n: 2, linha: 1 }],
  ["*1 sabe 2*.", { comando: "sabe", n: 1, linha: 2 }],
];

// A conversa tem de continuar conversa: nome de cliente, frase livre, pergunta e as palavras da matriz que não existem.
const CONVERSA = [
  "parceiro?", "parceiro 74?", "1 tira 2?", "1 sabe 2?", "o parceiro ligou", "parceiro da MP", "parceiro do João", "parceiro João",
  "parceiro os 74", "parceiro orc 107", "parceiro 74 75", "parceiro 1234567890", "parceiro 0x74", "parceiros",
  "parceria", "pátio", "patio", "ver pátio", "segura pátio", "pausa mp", "pausar mp", "volta mp", "vinculos", "painel", "repassa 1",
  "não mp", "nao mp", "manda o pdf do 1 pra mp", "pdf pra mp", "1 tira", "tira 2", "1 tira a 2", "4 tira 2", "0 tira 1", "1 tira 0",
  "1 sabe", "sabe 2", "1 sabe 2 sim 7391", "1 tira 2 sim 4321", "o 1 tira 2", "1 tira 100", "1 sabe que sim", "", "   ",
];

Deno.test("lerComandoDoParceiro: cada linha da matriz 7.2, com acento, maiúscula, negrito, ponto e 🎤", () => {
  for (const [t, esperado] of TABELA) assertEquals(lerComandoDoParceiro(t), esperado, t);
});

Deno.test("lerComandoDoParceiro: nome de cliente, frase livre e pergunta continuam conversa", () => {
  for (const t of CONVERSA) assertEquals(lerComandoDoParceiro(t), null, JSON.stringify(t));
});

Deno.test("lerComandoDoParceiro: o número é inteiro, nunca pedaço de frase, e ORC vira ORÇ", () => {
  assertEquals(lerComandoDoParceiro("parceiro orc-107"), { comando: "parceiro_os", sigla: null, numero: "ORÇ-107" });
  assertEquals(lerComandoDoParceiro("parceiro 00074"), { comando: "parceiro_os", sigla: null, numero: "00074" });
  assertEquals(lerComandoDoParceiro("parceiro 74 do joão"), null);
  assertEquals(lerComandoDoParceiro("parceiro do 74"), null);
  // A palavra antes do número é só sigla: o banco a compara com parceiros.sigla, nunca com clients. Um nome ali dá
  // "Não achei esse parceiro." (parceiro_cartao_abrir_os), e nenhuma OS é achada pelo nome.
  assertEquals(lerComandoDoParceiro("parceiro joao 74"), { comando: "parceiro_os", sigla: "joao", numero: "74" });
});

Deno.test("lerComandoDoParceiro: texto longo não é palavra", () => {
  assertEquals(lerComandoDoParceiro(`parceiro ${"a".repeat(300)}`), null);
});

Deno.test("as formas fixas do parceiro não são lidas pelo retorno nem pelo Secretário, e o inverso", () => {
  const formas = frasesDoParceiro();
  assertEquals(formas.length >= 10, true);
  for (const f of [...formas, ...formas.map((x) => `*${x}*`), ...formas.map((x) => `${x[0].toUpperCase()}${x.slice(1)}.`)]) {
    assertEquals(lerComandoDoRetorno(f), null, `retorno: ${f}`);
    assertEquals(lerComandoDoSecretario(f), null, `secretário: ${f}`);
    assertEquals(lerComandoDoParceiro(f) !== null, true, `o próprio leitor: ${f}`);
  }
  // O leitor da F2 continua com as dele: o *1 A* do cartão do parceiro é lido por lá (camada.ts decide o dono do cartão).
  for (const t of ["1 a", "1 b", "1 c", "1 r", "3 r", "1 p", "1 t", "1 v", "só 2", "não 2", "ver 2", "resolvido 2", "retorno"]) {
    assertEquals(lerComandoDoParceiro(t), null, t);
  }
});
