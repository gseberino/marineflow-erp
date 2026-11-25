// A classe do erro técnico (acabamento da leva A do pacote 1, 24/11/2026). O que se protege: o que vai para
// app_error_logs quando uma rotina de IA falha é uma frase fixa, de lista fechada. A mensagem do erro, o corpo da
// resposta do provedor e o nome do erro nunca são copiados, nem em parte: o provedor pode devolver neles um trecho do
// e-mail ou da mensagem que foi enviada para ler.
// Rodar com:
//   deno test --allow-all --no-check --node-modules-dir=none supabase/functions/_shared/ai/classe-do-erro_test.ts
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { ClaudeApiError } from "./anthropic.ts";
import {
  classeDoErro,
  ehClasseDeErro,
  ERRO_NAO_CLASSIFICADO,
  FALHA_SEM_ERRO,
  SEM_CREDITO_NO_PROVEDOR,
  soAClasseDoErro,
} from "./classe-do-erro.ts";

/** Texto de fora (inventado) que um erro do provedor pode devolver: remetente, assunto e corpo de um e-mail. */
const DE_FORA = "De: Maria Segredo <maria.segredo@cliente-inventado.com.br> Assunto: Proposta confidencial do veleiro Albatroz. " +
  "O valor combinado é R$ 48.750,00 e a senha do portão é 4471.";
const TRECHOS = ["Maria", "Segredo", "maria.segredo", "cliente-inventado", "confidencial", "Albatroz", "48.750", "4471", "senha"];

/** O corpo de uma recusa de moderação, como o provedor devolve: o trecho acusado vem dentro. */
const corpoDaRecusa = (status: number) =>
  JSON.stringify({ error: { code: status, message: "Input flagged", metadata: { reasons: ["harassment"], flagged_input: DE_FORA } } });

function nomeado(nome: string, mensagem: string): Error {
  const e = new Error(mensagem);
  e.name = nome;
  return e;
}

Deno.test("classeDoErro: o erro do provedor vira o status HTTP com o nome dele, sem o corpo da resposta", () => {
  const casos: Array<[number, string]> = [
    [400, "HTTP 400 (pedido recusado)"],
    [401, "HTTP 401 (credencial recusada)"],
    [402, "HTTP 402 (sem crédito)"],
    [403, "HTTP 403 (recusado pelo provedor)"],
    [404, "HTTP 404 (modelo ou endereço não encontrado)"],
    [408, "HTTP 408 (tempo esgotado)"],
    [413, "HTTP 413 (pedido grande demais)"],
    [429, "HTTP 429 (limite de chamadas)"],
    [500, "HTTP 500 (erro no provedor)"],
    [502, "HTTP 502 (provedor fora do ar)"],
    [503, "HTTP 503 (provedor fora do ar)"],
    [504, "HTTP 504 (tempo esgotado no provedor)"],
    [529, "HTTP 529 (provedor sobrecarregado)"],
    // status sem nome na lista: só o número
    [418, "HTTP 418"],
    [451, "HTTP 451"],
  ];
  for (const [status, esperado] of casos) {
    assertEquals(classeDoErro(new ClaudeApiError(status, `OpenRouter ${status}: ${corpoDaRecusa(status)}`)), esperado);
  }
  // a mensagem que o anthropic.ts monta para o saldo zerado
  assertEquals(
    classeDoErro(new ClaudeApiError(402, `OpenRouter 402 (créditos insuficientes na conta): ${corpoDaRecusa(402)}`)),
    "HTTP 402 (sem crédito)",
  );
  // status que não é status não entra como número: cai no tipo do erro
  for (const torto of [0, 99, 600, 402.5, NaN, "402", null]) {
    const e = Object.assign(new ClaudeApiError(402, DE_FORA), { status: torto });
    assertEquals(classeDoErro(e), "erro do tipo ClaudeApiError", String(torto));
  }
});

Deno.test("classeDoErro: tempo esgotado, resposta inválida, falha de rede e chave ausente têm frase própria", () => {
  assertEquals(classeDoErro(nomeado("TimeoutError", `Signal timed out. ${DE_FORA}`)), "tempo esgotado");
  assertEquals(classeDoErro(nomeado("AbortError", "The signal has been aborted")), "tempo esgotado");
  assertEquals(classeDoErro(new DOMException("Signal timed out.", "TimeoutError")), "tempo esgotado");
  assertEquals(classeDoErro(new SyntaxError(`Unexpected token '<', "${DE_FORA}" is not valid JSON`)), "resposta inválida");
  assertEquals(classeDoErro(new TypeError("error sending request for url (https://openrouter.ai/api/v1/chat/completions): client error (Connect)")), "falha de rede");
  assertEquals(classeDoErro(nomeado("ConnectionReset", "Connection reset by peer")), "falha de rede");
  assertEquals(classeDoErro(new Error("OPENROUTER_API_KEY não configurada no Supabase")), "chave do provedor não configurada");
  // O TypeError que não é de rede (defeito de código) e o erro comum: só o tipo
  assertEquals(classeDoErro(new TypeError(`Cannot read properties of undefined (reading '${DE_FORA}')`)), "erro do tipo TypeError");
  assertEquals(classeDoErro(new Error(DE_FORA)), "erro do tipo Error");
  assertEquals(classeDoErro(new RangeError(DE_FORA)), "erro do tipo RangeError");
});

Deno.test("classeDoErro: o que não é erro conhecido é 'erro não classificado', e nada estranho lança", () => {
  const hostil = new Proxy({}, { get() { throw new Error(DE_FORA); } });
  const estranhos: unknown[] = [
    undefined, null, "", DE_FORA, 402, true, [], [DE_FORA], {}, { message: DE_FORA }, { name: DE_FORA, message: DE_FORA },
    // o nome do erro também pode ser texto de fora: só entra o que está na lista de tipos conhecidos
    nomeado(DE_FORA, DE_FORA), nomeado("Albatroz", "x"), nomeado("", DE_FORA),
    hostil,
  ];
  for (const e of estranhos) assertEquals(classeDoErro(e), ERRO_NAO_CLASSIFICADO);
});

Deno.test("classeDoErro: nada do texto do erro aparece na classe, e toda classe é da lista fechada", () => {
  const erros: unknown[] = [
    ...[400, 401, 402, 403, 404, 408, 413, 418, 429, 500, 502, 503, 504, 529].map((s) => new ClaudeApiError(s, `OpenRouter ${s}: ${corpoDaRecusa(s)}`)),
    new Error(DE_FORA), new TypeError(DE_FORA), new SyntaxError(DE_FORA), new RangeError(DE_FORA),
    nomeado("TimeoutError", DE_FORA), nomeado("ConnectionReset", DE_FORA), nomeado(DE_FORA, DE_FORA),
    new TypeError(`error sending request for url (https://x/${DE_FORA})`),
    new Error(`OPENROUTER_API_KEY não configurada ${DE_FORA}`),
    DE_FORA, { message: DE_FORA }, [DE_FORA], null, undefined,
  ];
  for (const e of erros) {
    const classe = classeDoErro(e);
    assert(ehClasseDeErro(classe), `fora da lista: ${classe}`);
    assert(classe.length <= 60, `comprida demais: ${classe}`);
    for (const trecho of TRECHOS) assert(!classe.includes(trecho), `"${trecho}" apareceu em: ${classe}`);
    // quem grava deixa a classe passar como está
    assertEquals(soAClasseDoErro(classe), classe);
  }
});

Deno.test("ehClasseDeErro: só a frase exata passa; texto cru de erro, ou classe com texto colado, não", () => {
  for (const classe of [
    "HTTP 402 (sem crédito)", "HTTP 418", "tempo esgotado", "resposta inválida", "falha de rede", "chave do provedor não configurada",
    "erro do tipo Error", "erro do tipo ClaudeApiError", ERRO_NAO_CLASSIFICADO, FALHA_SEM_ERRO,
  ]) {
    assertEquals(ehClasseDeErro(classe), true, classe);
  }
  for (const fora of [
    // como o registro era antes: o texto cru do erro
    "ClaudeApiError: OpenRouter 402 (créditos insuficientes na conta)",
    `ClaudeApiError: OpenRouter 403: ${corpoDaRecusa(403)}`,
    "Error: OpenRouter 402 (créditos insuficientes na conta)",
    // classe com texto de fora colado, antes ou depois
    `HTTP 402 (sem crédito) ${DE_FORA}`, `HTTP 402 (${DE_FORA})`, "HTTP 402 (sem crédito)\nAssunto: Albatroz", `${DE_FORA} HTTP 402 (sem crédito)`,
    "HTTP 402", "HTTP 418 (sou um bule)", "HTTP 999", "HTTP 40", "HTTP 4020", "http 402 (sem crédito)",
    "erro do tipo Albatroz", `erro do tipo Error ${DE_FORA}`, "erro do tipo ", "tempo esgotado.", " tempo esgotado",
    "o modelo não respondeu", "", "   ", DE_FORA,
    null, undefined, 402, {}, ["tempo esgotado"],
  ]) {
    assertEquals(ehClasseDeErro(fora), false, String(fora));
  }
});

// (Fecho da leva A, 24/11/2026) A manhã deixa a falta de crédito fora da frase "IA que falhou desde ontem" (decisão do
// dono de 24/11/2026) e a reconhece por esta frase. O que se protege: ela é a mesma que o 402 grava, e nenhum outro
// status divide a linha do log com ela. log_app_error agrupa pelo texto em minúsculas e sem os números: se outro
// status ganhasse o nome "sem crédito", as falhas dele cairiam na linha do 402 e sumiriam da manhã junto.
Deno.test("SEM_CREDITO_NO_PROVEDOR: é a classe do 402, e nenhum outro status cai na mesma linha do log", () => {
  assertEquals(SEM_CREDITO_NO_PROVEDOR, "HTTP 402 (sem crédito)");
  assertEquals(classeDoErro(new ClaudeApiError(402, `OpenRouter 402 (créditos insuficientes na conta): ${corpoDaRecusa(402)}`)), SEM_CREDITO_NO_PROVEDOR);
  assertEquals(ehClasseDeErro(SEM_CREDITO_NO_PROVEDOR), true);
  assertEquals(soAClasseDoErro(SEM_CREDITO_NO_PROVEDOR), SEM_CREDITO_NO_PROVEDOR);
  // como a impressão digital de log_app_error lê o texto (migration 20260722180000)
  const semOsNumeros = (texto: string) => texto.toLowerCase().replace(/\d+/g, "#");
  const naMesmaLinha: number[] = [];
  for (let status = 100; status <= 599; status++) {
    if (semOsNumeros(classeDoErro(new ClaudeApiError(status, "x"))) === semOsNumeros(SEM_CREDITO_NO_PROVEDOR)) naMesmaLinha.push(status);
  }
  assertEquals(naMesmaLinha, [402]);
  // as frases que não são de status também não
  for (const outra of [ERRO_NAO_CLASSIFICADO, FALHA_SEM_ERRO, "tempo esgotado", "resposta inválida", "falha de rede", "chave do provedor não configurada", "erro do tipo Error"]) {
    assert(semOsNumeros(outra) !== semOsNumeros(SEM_CREDITO_NO_PROVEDOR), outra);
  }
});

Deno.test("soAClasseDoErro: texto que não é classe vira frase fixa antes de gravar; vazio ainda conta como falha", () => {
  assertEquals(soAClasseDoErro("HTTP 429 (limite de chamadas)"), "HTTP 429 (limite de chamadas)");
  for (const cru of [
    "ClaudeApiError: OpenRouter 402 (créditos insuficientes na conta)",
    `ClaudeApiError: OpenRouter 403: ${corpoDaRecusa(403)}`,
    DE_FORA, `HTTP 402 (sem crédito) ${DE_FORA}`, "o modelo não respondeu",
  ]) {
    assertEquals(soAClasseDoErro(cru), ERRO_NAO_CLASSIFICADO, cru);
  }
  for (const vazio of ["", "   ", "\n", undefined, null, 0, {}, new Error(DE_FORA)]) {
    assertEquals(soAClasseDoErro(vazio), FALHA_SEM_ERRO, String(vazio));
  }
});
