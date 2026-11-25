// A classe de um erro técnico: o que pode ir para app_error_logs quando uma rotina de IA falha
// (acabamento da leva A do pacote 1, 24/11/2026).
//
// ═══ POR QUE EXISTE ═══
//
// O registro da rotina que falha (V2, falhas-do-assistente.ts) gravava o texto cru do erro, até 300 caracteres. O erro
// do provedor carrega o corpo da resposta (anthropic.ts: `OpenRouter ${status}: ${corpo}`), e o corpo pode devolver um
// trecho do que foi enviado: na recusa de moderação vem o trecho acusado; no 400, o pedaço do pedido que não foi aceito.
// O que a triagem envia é o e-mail (remetente, assunto e corpo); o que a leitura do prazo envia é a frase do fornecedor.
// Esse texto não pode parar no log.
//
// ═══ A REGRA ═══
//
// O que sai daqui é sempre uma frase FIXA, de lista fechada:
//   · o status HTTP, com o nome dele quando é conhecido ("HTTP 402 (sem crédito)"). É também o código que o provedor
//     usa em `error.code`; o corpo da resposta não é lido;
//   · "tempo esgotado", "resposta inválida", "falha de rede", "chave do provedor não configurada";
//   · o tipo do erro, quando é um dos conhecidos ("erro do tipo TypeError");
//   · "erro não classificado", para todo o resto.
// A mensagem do erro NUNCA é copiada, nem em parte: ela só é lida para escolher a frase, e a frase escolhida é uma
// constante deste arquivo. O mesmo vale para o nome do erro (só entra o que está na lista de tipos conhecidos).
//
// Vale nos dois lados: quem falha classifica (triage.ts, casar-fornecedor.ts) e quem grava confere de novo
// (registrarFalhaDeRotina → soAClasseDoErro): texto que não é desta lista vira "erro não classificado" antes de gravar.
// Assim uma rotina nova que passe `String(e)` por engano não leva texto de fora para o log.
//
// Arquivo puro: não importa nada, não lê banco e nunca lança.

/** Nada do erro pôde ser classificado (ou o texto recebido não é desta lista). */
export const ERRO_NAO_CLASSIFICADO = "erro não classificado";
/** A falha chegou sem texto nenhum. Ainda conta (logEdgeError descartaria a mensagem vazia). */
export const FALHA_SEM_ERRO = "falha sem mensagem de erro";
export const TEMPO_ESGOTADO = "tempo esgotado";
export const RESPOSTA_INVALIDA = "resposta inválida";
export const FALHA_DE_REDE = "falha de rede";
export const SEM_CHAVE_DO_PROVEDOR = "chave do provedor não configurada";

const FRASES_FIXAS: ReadonlySet<string> = new Set([
  ERRO_NAO_CLASSIFICADO,
  FALHA_SEM_ERRO,
  TEMPO_ESGOTADO,
  RESPOSTA_INVALIDA,
  FALHA_DE_REDE,
  SEM_CHAVE_DO_PROVEDOR,
]);

/** O nome dos status que o provedor devolve de fato. Status fora daqui sai só com o número ("HTTP 418"). */
const NOME_DO_STATUS: ReadonlyMap<number, string> = new Map([
  [400, "pedido recusado"],
  [401, "credencial recusada"],
  [402, "sem crédito"],
  [403, "recusado pelo provedor"],
  [404, "modelo ou endereço não encontrado"],
  [408, "tempo esgotado"],
  [413, "pedido grande demais"],
  [429, "limite de chamadas"],
  [500, "erro no provedor"],
  [502, "provedor fora do ar"],
  [503, "provedor fora do ar"],
  [504, "tempo esgotado no provedor"],
  [529, "provedor sobrecarregado"],
]);

/** Os nomes de erro que dizem "o tempo acabou" (AbortSignal.timeout, abort, Deno.errors.TimedOut). */
const TIPOS_DE_TEMPO_ESGOTADO: ReadonlySet<string> = new Set(["TimeoutError", "AbortError", "TimedOut"]);
/** A resposta veio e não deu para ler (res.json() com corpo que não é JSON). */
const TIPOS_DE_RESPOSTA_INVALIDA: ReadonlySet<string> = new Set(["SyntaxError", "InvalidData"]);
/** A conexão não fechou (Deno.errors.* e o NetworkError do navegador). */
const TIPOS_DE_REDE: ReadonlySet<string> = new Set([
  "NetworkError", "ConnectionRefused", "ConnectionReset", "ConnectionAborted", "NotConnected", "BrokenPipe",
  "UnexpectedEof", "Http", "NetworkUnreachable",
]);
/** Os tipos que podem ser ditos pelo nome. Nome fora daqui não é copiado: pode ser texto de fora. */
const TIPOS_CONHECIDOS: ReadonlySet<string> = new Set([
  "Error", "TypeError", "RangeError", "ReferenceError", "EvalError", "URIError", "AggregateError", "ClaudeApiError",
]);

function ehStatusHttp(n: unknown): n is number {
  return typeof n === "number" && Number.isInteger(n) && n >= 100 && n <= 599;
}

function classeDoStatus(status: number): string {
  const nome = NOME_DO_STATUS.get(status);
  return nome ? `HTTP ${status} (${nome})` : `HTTP ${status}`;
}

/**
 * A classe do erro: uma frase fixa, nunca a mensagem. Aceita qualquer coisa que tenha sido lançada (erro, texto,
 * objeto, nada) e nunca lança: o que não der para classificar é "erro não classificado".
 */
export function classeDoErro(e: unknown): string {
  try {
    if (e === null || typeof e !== "object") return ERRO_NAO_CLASSIFICADO;
    const erro = e as { status?: unknown; name?: unknown; message?: unknown };
    // ClaudeApiError (anthropic.ts) guarda o status que o provedor respondeu
    if (ehStatusHttp(erro.status)) return classeDoStatus(erro.status);
    const nome = typeof erro.name === "string" ? erro.name : "";
    if (TIPOS_DE_TEMPO_ESGOTADO.has(nome)) return TEMPO_ESGOTADO;
    if (TIPOS_DE_RESPOSTA_INVALIDA.has(nome)) return RESPOSTA_INVALIDA;
    if (TIPOS_DE_REDE.has(nome)) return FALHA_DE_REDE;
    // A mensagem só escolhe a frase; nada dela é copiado.
    const mensagem = typeof erro.message === "string" ? erro.message : "";
    if (mensagem.startsWith("OPENROUTER_API_KEY não configurada")) return SEM_CHAVE_DO_PROVEDOR;
    // o fetch do Deno que não conecta: "TypeError: error sending request for url (…)"
    if (nome === "TypeError" && /^error sending request\b/i.test(mensagem)) return FALHA_DE_REDE;
    return TIPOS_CONHECIDOS.has(nome) ? `erro do tipo ${nome}` : ERRO_NAO_CLASSIFICADO;
  } catch {
    return ERRO_NAO_CLASSIFICADO;
  }
}

/** O texto é, letra por letra, uma das frases que classeDoErro devolve? (lista fechada) */
export function ehClasseDeErro(texto: unknown): texto is string {
  if (typeof texto !== "string") return false;
  if (FRASES_FIXAS.has(texto)) return true;
  const status = /^HTTP (\d{3})(?: |$)/.exec(texto);
  if (status) {
    const n = Number(status[1]);
    return ehStatusHttp(n) && classeDoStatus(n) === texto;
  }
  const tipo = /^erro do tipo ([A-Za-z]+)$/.exec(texto);
  return tipo !== null && TIPOS_CONHECIDOS.has(tipo[1]);
}

/**
 * O que quem grava usa: deixa passar só o que já é uma classe; o resto vira frase fixa. Texto vazio (ou que não é
 * texto) = "falha sem mensagem de erro"; qualquer outro texto = "erro não classificado".
 */
export function soAClasseDoErro(texto: unknown): string {
  if (ehClasseDeErro(texto)) return texto;
  return typeof texto === "string" && texto.trim() !== "" ? ERRO_NAO_CLASSIFICADO : FALHA_SEM_ERRO;
}
