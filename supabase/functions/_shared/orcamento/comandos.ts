// Retorno rápido, F5 (P10.1): o leitor fechado das palavras do dono sobre o orçamento enviado. Puro, sem banco.
//
// Molde: _shared/retorno/comandos.ts e _shared/parceiro/comandos.ts. Lê só a FORMA da frase; quem decide se é comando é a
// camada (camada.ts): o autor tem de ser o dono, e o banco (orcamento_dito) confere de novo e acha a ordem pelo NÚMERO
// (ORÇ-nnnnn ou OS-nnnnn), nunca pelo nome.
//
//   *segura 151* / *solta 151*     (também "segura orc 151", "segura orç-00151", "segura orcamento 151")
//   *segura orcamentos* / *solta orcamentos*
//   *motivo 151 B*                  (A sumiu, B fechou com outro, C desistiu, D preço, F prazo, G outro; ou a palavra)
//
// Regras (P10.1): o número tem de 2 a 5 dígitos (os zeros à esquerda caem): "segura 1" não é comando, porque com 1 dígito o
// dono pode estar falando do item 1 do cartão. Frase terminada em "?" não é comando. Acima de 60 caracteres, não lê. Letra
// fora de A, B, C, D, F e G não é motivo (sem E, como no alfabeto do Secretário). No motivo, a palavra vale tanto quanto a
// letra (LETRA_DA_PALAVRA): ela evita a confusão com as letras do dia do Secretário e com o *1 B* do aceite. Nunca há PIN
// aqui: "motivo 151 b sim 7391" não é palavra.
//
// Reverter: tirar a chamada de camadaDoOrcamento do ai-agent e a marca do webhook. Este arquivo não tem efeito sozinho.

import { normalizarComando } from "../secretario/comandos.ts";

/** sumiu, fechou com outro, desistiu, preço, prazo, outro (3.4). */
export type LetraDoMotivo = "A" | "B" | "C" | "D" | "F" | "G";

export type ComandoDoOrcamento =
  | { comando: "segura"; numero: number } // "segura 151", "segura orc 151", "segura orç-00151", "segura orcamento 151"
  | { comando: "solta"; numero: number }
  | { comando: "segura_todos" } // "segura orcamentos", "segura orçamentos"
  | { comando: "solta_todos" }
  | { comando: "motivo"; numero: number; letra: LetraDoMotivo }; // "motivo 151 b", "motivo orc 151 b", "motivo 151 preco"

/** A lista fechada de service_orders.motivo_perda que o dono escolhe (sem_motivo_antigo é só da migration de dado). */
export const MOTIVO_DA_LETRA: Record<LetraDoMotivo, string> = {
  A: "sumiu",
  B: "fechou_com_outro",
  C: "desistiu",
  D: "preco",
  F: "prazo",
  G: "outro",
};

/** A palavra no lugar da letra, já sem acento e minúscula (como normalizarComando a deixa). */
export const LETRA_DA_PALAVRA: Record<string, LetraDoMotivo> = {
  "sumiu": "A",
  "outra empresa": "B",
  "fechou com outro": "B",
  "desistiu": "C",
  "preco": "D",
  "prazo": "F",
  "outro": "G",
};

/** Acima disto não é palavra: a mais longa é "motivo orcamento orc-00151 fechou com outro". */
const TEXTO_MAX = 60;

/** Molde de terminaEmPergunta da F2: o que age, dito como pergunta, é conversa. */
function terminaEmPergunta(texto: string): boolean {
  const fim = /[\s.!?,;:"'“”‘’«»]+$/u.exec(String(texto ?? "").replace(/[*_~]/g, "").trim());
  return fim !== null && fim[0].includes("?");
}

/** "151", "orc 151", "orc-00151", "orc00151", "orcamento 151", "orcamento orc-00151": o número, 2 a 5 dígitos. */
const NUMERO = "(?:orcamento )?(?:orc ?-? ?)?(\\d{2,5})";
const RE_SEGURA = new RegExp(`^(segura|solta) ${NUMERO}$`);
const RE_TODOS = /^(segura|solta) orcamentos$/;
const RE_MOTIVO = new RegExp(`^motivo ${NUMERO} (.{1,30})$`);

/** "00151" → 151. Zero (ou só zeros) não é número de orçamento. */
function numeroDe(digitos: string): number | null {
  const n = Number(digitos);
  return Number.isInteger(n) && n > 0 ? n : null;
}

function letraDe(resto: string): LetraDoMotivo | null {
  const r = resto.trim();
  if (/^[a-z]$/.test(r)) {
    const l = r.toUpperCase();
    return l in MOTIVO_DA_LETRA ? (l as LetraDoMotivo) : null;
  }
  return LETRA_DA_PALAVRA[r] ?? null;
}

/** O comando, ou null (não é palavra do orçamento: segue como sempre). */
export function lerComandoDoOrcamento(texto: string): ComandoDoOrcamento | null {
  const original = String(texto ?? "");
  if (original.length > TEXTO_MAX) return null;
  const t = normalizarComando(original);
  if (!t) return null;
  if (terminaEmPergunta(original)) return null;

  let m = RE_TODOS.exec(t);
  if (m) return m[1] === "segura" ? { comando: "segura_todos" } : { comando: "solta_todos" };

  m = RE_SEGURA.exec(t);
  if (m) {
    const numero = numeroDe(m[2]);
    if (numero === null) return null;
    return m[1] === "segura" ? { comando: "segura", numero } : { comando: "solta", numero };
  }

  m = RE_MOTIVO.exec(t);
  if (m) {
    const numero = numeroDe(m[1]);
    const letra = letraDe(m[2]);
    if (numero === null || letra === null) return null;
    return { comando: "motivo", numero, letra };
  }
  return null;
}

/** As formas fixas, para a matriz de colisão das outras camadas. */
export function frasesDoOrcamento(): string[] {
  return [
    "segura 151", "solta 151", "segura orc 151", "segura orc-00151", "segura orcamento 151", "solta orc-00151",
    "segura orcamentos", "solta orcamentos",
    "motivo 151 a", "motivo 151 b", "motivo 151 c", "motivo 151 d", "motivo 151 f", "motivo 151 g", "motivo orc 151 b",
    "motivo 151 preco", "motivo 151 prazo", "motivo 151 desistiu", "motivo 151 sumiu", "motivo 151 outro",
    "motivo 151 outra empresa", "motivo 151 fechou com outro",
  ];
}
