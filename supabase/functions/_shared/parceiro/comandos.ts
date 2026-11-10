// Retorno rápido, F4 (P11.1): o leitor fechado das palavras do dono para o parceiro. Puro, sem banco.
//
// Molde: _shared/retorno/comandos.ts. Lê só a FORMA da frase; quem decide se é comando é a camada (camada.ts): o autor tem
// de ser o dono e, em *N tira L* e *N sabe L*, o cartão do parceiro tem de estar vivo.
//
// Palavra fechada, nunca nome de cliente nem frase livre. *parceiro 74* acha a OS pelo NÚMERO inteiro (74, OS-00074,
// ORC-00107 → ORÇ-00107), nunca pelo nome. A palavra antes do número é só a sigla do parceiro: o banco a compara com
// parceiros.sigla (parceiro_cartao_abrir_os), nunca com clients.
//
// O que age e vem como pergunta é conversa ("parceiro?" segue ao modelo, como manda a matriz 7.2).
//
// As letras do cartão (*1 A*, *só 2*, *não 2*, *ver 1*, *resolvido 1*) NÃO são lidas aqui: são as do leitor da F2
// (lerComandoDoRetorno). A camada é que decide de qual cartão elas são.
//
// Reverter: tirar a chamada de camadaDoParceiro do ai-agent e a marca do webhook. Este arquivo não tem efeito sozinho.

import { normalizarComando } from "../secretario/comandos.ts";

export type ComandoDoParceiro =
  | { comando: "parceiro" } // abre ou reapresenta
  | { comando: "parceiro_os"; sigla: string | null; numero: string } // "parceiro 74", "parceiro os-00074", "parceiro mp 74"
  | { comando: "tira_linha"; n: number; linha: number } // "1 tira 2"
  | { comando: "sabe"; n: number; linha: number }; // "1 sabe 2"

/** Acima disto não é palavra: a mais longa é "parceiro fortro orc-00107". */
const TEXTO_MAX = 80;

/** Palavras que nunca são sigla: "parceiro os 74" e "parceiro do 74" não são palavra do dono. */
const NAO_E_SIGLA: ReadonlySet<string> = new Set([
  "os", "orc", "orcamento", "o", "a", "da", "do", "de", "dos", "das", "no", "na", "pra", "para", "com", "ver", "numero", "n",
]);

/** Molde de terminaEmPergunta da F2: o que age, dito como pergunta, é conversa. */
function terminaEmPergunta(texto: string): boolean {
  const fim = /[\s.!?,;:"'“”‘’«»]+$/u.exec(String(texto ?? "").replace(/[*_~]/g, "").trim());
  return fim !== null && fim[0].includes("?");
}

const RE_PARCEIRO_OS = /^parceiro(?: ([a-z]{2,15}))? (?:(os|orc)-?(\d{1,8})|(\d{1,8}))$/;
const RE_LINHA = /^([1-3]) (tira|sabe) ([1-9]\d?)$/;

/** O número como o banco o compara: "74", "OS-00074" ou "ORÇ-00107" (ORC vira ORÇ, como na P9). */
function numeroDaOs(prefixo: string | undefined, digitos: string): string {
  if (!prefixo) return digitos;
  return `${prefixo === "orc" ? "ORÇ" : "OS"}-${digitos}`;
}

/** O comando, ou null (não é palavra do parceiro: segue como sempre). */
export function lerComandoDoParceiro(texto: string): ComandoDoParceiro | null {
  const original = String(texto ?? "");
  if (original.length > TEXTO_MAX) return null;
  const t = normalizarComando(original);
  if (!t) return null;
  if (terminaEmPergunta(original)) return null;

  if (t === "parceiro" || t === "ver parceiro") return { comando: "parceiro" };

  let m = RE_PARCEIRO_OS.exec(t);
  if (m) {
    const sigla = m[1] ?? null;
    if (sigla !== null && NAO_E_SIGLA.has(sigla)) return null;
    return { comando: "parceiro_os", sigla, numero: m[4] ?? numeroDaOs(m[2], m[3]) };
  }

  m = RE_LINHA.exec(t);
  if (m) {
    const n = Number(m[1]);
    const linha = Number(m[3]);
    return m[2] === "tira" ? { comando: "tira_linha", n, linha } : { comando: "sabe", n, linha };
  }
  return null;
}

/** As formas fixas, para a matriz de colisão das outras camadas. */
export function frasesDoParceiro(): string[] {
  return [
    "parceiro", "ver parceiro", "parceiro 74", "parceiro os-00074", "parceiro orc-00107", "parceiro mp 74", "parceiro fortro 74",
    "1 tira 2", "2 tira 1", "3 tira 14", "1 sabe 2", "2 sabe 1", "3 sabe 14",
  ];
}
