// Retorno rápido, F2 (P2): o leitor fechado das palavras do dono. Puro, sem banco.
//
// Molde: lerComandoDaAgenda. Lê só a FORMA da frase. Quem decide se é comando é a camada (camada.ts): a letra tem de
// existir no item, o cartão tem de estar vivo e o autor tem de ser o dono. O que age e vem como pergunta é conversa.
//
// Nunca lê: "sim N" (colide com *sim <PIN>*), "1", "2", "3" sozinhos, nem "1: …". As letras seguem o alfabeto do plano,
// sem E, I, N, O, S: "1 s", "2 n", "1 e", "1 o" não são comando.
//
// O PIN só vale depois da palavra *sim*. "3 b 500", "só 3 300" e "1 A 7391" não são comando: não gastam tentativa, e, se
// o número for mesmo o PIN, a guarda do turno segura antes do modelo.
//
// Reverter: tirar a chamada de camadaDoRetorno do ai-agent. Este arquivo não tem efeito sozinho.

import { normalizarComando } from "../secretario/comandos.ts";

export type ComandoDoRetorno =
  | { comando: "retorno" }
  | { comando: "pessoal"; n: number | null }
  | { comando: "pessoal_desfaz" }
  // (08/11/2026, cartão F1-10) o dono resolveu fora do WhatsApp. Só com número: "resolvido" sozinho é do Secretário.
  | { comando: "resolvido"; n: number }
  | { comando: "fora_ate"; dia: string }
  // Retorno F4 (P11.1): "patio" é o único acréscimo da F4 a este leitor (retorno_dito grava retorno_config.segura_patio)
  | { comando: "segura"; alvo: "recibos" | "tudo" | "patio" }
  | { comando: "solta"; alvo: "recibos" | "tudo" | "patio" }
  | { comando: "libera"; alvo: string; desfaz: boolean }
  | { comando: "errado"; letra: string }
  // só com cartão vivo (a camada confere):
  | { comando: "escolher"; n: number; letra: string; resto: string | null; pin: string | null }
  | { comando: "ditar"; n: number; texto: string }
  | { comando: "so"; ns: number[]; pin: string | null }
  | { comando: "sem"; ns: number[]; pin: string | null }
  | { comando: "tirar"; ns: number[] }
  | { comando: "ver"; n: number };

/** Acima disto não é palavra: o ditado aceita 1.000 caracteres, e a folga cobre o "dita 2:" e a mensagem de recusa. */
const TEXTO_MAX = 1100;

/** Do "Mandei sozinho hoje". De trás para a frente, para não bater com as letras do Secretário. */
export const LETRAS_DO_RETORNO = ["Z", "Y", "X", "W", "V"] as const;

const CONECTIVOS_DO_ALVO = new Set(["de", "do", "da", "dos", "das", "no", "na", "nos", "nas", "em", "pra", "para", "com", "por", "que"]);

/** A lista NAO_E_ALVO da agenda (que não é exportada; o teste compara) mais as palavras do dinheiro e do tempo. */
export const NAO_E_ALVO_DO_LIBERA: ReadonlySet<string> = new Set([
  "isso", "isto", "aquilo", "tudo", "ai", "agrupamento", "agrupar", "baixa", "pix", "pagamento", "pagamentos", "lancamento",
  "lancamentos", "estorno", "envio", "conta", "contas", "cobranca", "nota", "compra", "pedido", "orcamento", "item", "tarefa",
  "lembrete", "despesa", "recebimento", "transferencia", "mensagem", "diaria",
  "sinal", "saldo", "boleto", "fatura", "nf", "nfe", "nfse", "recibo", "acesso", "todos", "todas", "ele", "ela", "eles",
  "agora", "hoje", "amanha", "depois", "pro", "aqui", "la",
]);

const ALVO_MAX_PALAVRAS = 3;

/** Molde de terminaEmPergunta da agenda: o que age, dito como pergunta, é conversa. */
function terminaEmPergunta(texto: string): boolean {
  const fim = /[\s.!?,;:"'“”‘’«»]+$/u.exec(String(texto ?? "").replace(/[*_~]/g, "").trim());
  return fim !== null && fim[0].includes("?");
}

/** "1 e 3", "1, 3", "1 3" → [1, 3]. Sem repetir; null quando repete ou tem número fora de 1 a 3. */
function lerLista(lista: string): number[] | null {
  const ns = lista.split(/, ?| e | /).filter((p) => p !== "").map(Number);
  if (ns.length === 0 || ns.some((n) => !Number.isInteger(n) || n < 1 || n > 3)) return null;
  return new Set(ns).size === ns.length ? ns : null;
}

const LISTA = "[1-3](?:(?:, ?| e | )[1-3])*";

const RE_ESCOLHER = /^([1-3]) ([a-df-hj-mp-rt-z])(?: sim (\d{3,8}))?$/;
const RE_ESCOLHER_DATA = /^([1-3]) c (.{2,30})$/;
const RE_SO = new RegExp(`^so (${LISTA})(?: sim (\\d{3,8}))?$`);
const RE_SIM_SEM = new RegExp(`^sim sem (${LISTA})$`);
const RE_SIM_PIN_SEM = new RegExp(`^sim (\\d{3,8}) sem (${LISTA})$`);
const RE_TIRAR = new RegExp(`^nao (${LISTA})$`);

/** O texto do ditado sai do ORIGINAL: a normalização tira acento e maiúscula, e o texto vai ao cliente como foi dito. */
const RE_DITA_ORIGINAL = /^\s*🎤?\s*\*?dita\*?\s+[1-3]\s*[:,.\-–]?\s*/iu;

function alvoDoLibera(resto: string): { alvo: string; desfaz: boolean } | null {
  let alvo = resto.trim();
  const desfaz = alvo.endsWith(" nao");
  if (desfaz) alvo = alvo.slice(0, -" nao".length).trim();
  alvo = alvo.replace(/^(?:o|a|do|da) /, "");
  const palavras = alvo.split(" ").filter(Boolean);
  if (palavras.length === 0 || palavras.length > ALVO_MAX_PALAVRAS) return null;
  if (palavras.some((p) => p === "nao" || CONECTIVOS_DO_ALVO.has(p) || NAO_E_ALVO_DO_LIBERA.has(p))) return null;
  if (alvo.replace(/ /g, "").length < 2) return null;
  return { alvo, desfaz };
}

/** "3 c 7391" e "3 c dia 14 sim 7391" não são data: o número seguiria ao banco como o dia dito. Vão à guarda do turno. */
function restoPodeSerPin(resto: string): boolean {
  return /^\d{3,8}$/.test(resto) || /(?:^| )sim(?: |$)/.test(resto);
}

/** O comando, ou null (não é palavra do retorno: segue como sempre). */
export function lerComandoDoRetorno(texto: string): ComandoDoRetorno | null {
  const original = String(texto ?? "");
  if (original.length > TEXTO_MAX) return null;
  const t = normalizarComando(original);
  if (!t) return null;
  const pergunta = terminaEmPergunta(original);

  // As de ver valem com "?".
  if (t === "retorno" || t === "ver retorno") return { comando: "retorno" };
  let m = /^ver ([1-3])$/.exec(t);
  if (m) return { comando: "ver", n: Number(m[1]) };

  // O ditado é texto livre: uma frase ditada pode terminar em "?", e continua ditado.
  m = /^dita ([1-3])\b/.exec(t);
  if (m) return { comando: "ditar", n: Number(m[1]), texto: original.replace(RE_DITA_ORIGINAL, "").trim() };

  if (pergunta) return null;

  if (t === "pessoal") return { comando: "pessoal", n: null };
  if (t === "pessoal nao") return { comando: "pessoal_desfaz" };
  m = /^pessoal ([1-3])$/.exec(t) ?? /^([1-3]) pessoal$/.exec(t);
  if (m) return { comando: "pessoal", n: Number(m[1]) };

  m = /^resolvido ([1-3])$/.exec(t) ?? /^([1-3]) resolvido$/.exec(t);
  if (m) return { comando: "resolvido", n: Number(m[1]) };

  m = /^fora ate (.{2,30})$/.exec(t);
  if (m) return { comando: "fora_ate", dia: m[1] };

  m = /^(segura|solta) (recibos|tudo|patio)$/.exec(t);
  if (m) return { comando: m[1] as "segura" | "solta", alvo: m[2] as "recibos" | "tudo" | "patio" };

  m = /^libera (.{2,40})$/.exec(t);
  if (m) {
    const lido = alvoDoLibera(m[1]);
    return lido ? { comando: "libera", alvo: lido.alvo, desfaz: lido.desfaz } : null;
  }

  m = /^errado ([zyxwv])$/.exec(t);
  if (m) return { comando: "errado", letra: m[1].toUpperCase() };

  m = RE_ESCOLHER.exec(t);
  if (m) return { comando: "escolher", n: Number(m[1]), letra: m[2].toUpperCase(), resto: null, pin: m[3] ?? null };
  m = RE_ESCOLHER_DATA.exec(t);
  if (m) {
    return restoPodeSerPin(m[2]) ? null : { comando: "escolher", n: Number(m[1]), letra: "C", resto: m[2], pin: null };
  }

  m = RE_SO.exec(t);
  if (m) {
    const ns = lerLista(m[1]);
    return ns ? { comando: "so", ns, pin: m[2] ?? null } : null;
  }
  m = RE_SIM_SEM.exec(t);
  if (m) {
    const ns = lerLista(m[1]);
    return ns ? { comando: "sem", ns, pin: null } : null;
  }
  m = RE_SIM_PIN_SEM.exec(t);
  if (m) {
    const ns = lerLista(m[2]);
    return ns ? { comando: "sem", ns, pin: m[1] } : null;
  }
  m = RE_TIRAR.exec(t);
  if (m) {
    const ns = lerLista(m[1]);
    return ns ? { comando: "tirar", ns } : null;
  }
  return null;
}

/** Os comandos que só existem com cartão vivo. *pessoal* sem número não é: vale com um caso só na lista. */
export function ehComandoDeCartao(c: ComandoDoRetorno): boolean {
  switch (c.comando) {
    case "escolher":
    case "ditar":
    case "so":
    case "sem":
    case "tirar":
    case "ver":
    case "resolvido":
      return true;
    case "pessoal":
      return c.n !== null;
    default:
      return false;
  }
}

/** As formas fixas, para a matriz de colisão das outras camadas. */
export function frasesDoRetorno(): string[] {
  return [
    "retorno", "ver retorno", "pessoal", "pessoal 1", "pessoal 2", "pessoal 3", "1 pessoal", "2 pessoal", "3 pessoal",
    "pessoal nao", "segura recibos", "solta recibos", "segura tudo", "solta tudo", "segura patio", "solta patio",
    "errado z", "errado y", "errado x",
    "errado w", "errado v", "ver 1", "ver 2", "ver 3",
    "resolvido 1", "resolvido 2", "resolvido 3", "1 resolvido", "2 resolvido", "3 resolvido",
  ];
}
