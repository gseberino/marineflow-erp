// Promessa do dono numa conversa ("te mando amanhã", "vou ver e te retorno") — e QUANDO lembrar.
// (06/10/2026, plans/marineflow-acompanhar-conversa.md)
//
// Por padrão de texto, sem IA: roda a cada 15 min sobre o que o dono mandou, custo zero. Erra para
// o lado de NÃO detectar — um lembrete a menos é melhor que um lembrete falso a cada "vou ver".
// O lembrete é único e o dono encerra com uma palavra, então um falso positivo custa pouco.

const BRASILIA_MS = 3 * 60 * 60 * 1000;

/** Sem acento, minúsculo, espaços simples. */
function normalizar(t: string): string {
  return t.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/\s+/g, " ").trim();
}

const VERBOS_DE_ENTREGA = "mando|envio|passo|retorno|ligo|aviso|falo|confirmo|chamo|respondo|atualizo|encaminho";
const PADROES: RegExp[] = [
  // "te mando", "lhe envio", "te retorno"
  new RegExp(`\\b(te|lhe)\\s+(${VERBOS_DE_ENTREGA})\\b`),
  // "vou mandar", "vou te passar", "vou ver", "vou providenciar o orçamento"
  /\bvou\s+(te\s+|lhe\s+)?(mandar|enviar|passar|ver|verificar|confirmar|retornar|ligar|avisar|providenciar|orcar|fazer o orcamento|levantar|checar|conferir|cotar|encaminhar)\b/,
  // "amanhã mando", "segunda envio", "mais tarde passo"
  new RegExp(`\\b(ja ja|daqui a pouco|mais tarde|amanha|segunda|terca|quarta|quinta|sexta|sabado)\\b[^.!?\\n]{0,40}\\b(${VERBOS_DE_ENTREGA})\\b`),
  // "assim que chegar te aviso", "assim que tiver retorno"
  /\bassim que\b[^.!?\n]{0,60}\b(aviso|mando|falo|retorno|envio|passo)\b/,
  /\bdeixa comigo\b/,
  /\bfico de (te |lhe )?(mandar|enviar|passar|ver|verificar|retornar)\b/,
];

const DIAS = ["domingo", "segunda", "terca", "quarta", "quinta", "sexta", "sabado"];

/** Hora de Brasília (0-23) e dia da semana (0=domingo) de um instante. */
function emBrasilia(ms: number): { hora: number; dia: number } {
  const d = new Date(ms - BRASILIA_MS);
  return { hora: d.getUTCHours(), dia: d.getUTCDay() };
}

/** 09:00 de Brasília do dia (em Brasília) de `ms` + `dias`. */
function noveHoras(ms: number, dias: number): number {
  const d = new Date(ms - BRASILIA_MS);
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() + dias, 9, 0, 0) + BRASILIA_MS;
}

/**
 * Leva um instante para dentro da janela de aviso (8h–20h, seg–sáb). Fora dela: 09:00 do próximo dia
 * útil. Domingo vira segunda.
 */
export function dentroDaJanela(ms: number): number {
  let alvo = ms;
  for (let i = 0; i < 8; i++) {
    const { hora, dia } = emBrasilia(alvo);
    if (dia === 0) { alvo = noveHoras(alvo, 1); continue; }
    if (hora < 8) { alvo = noveHoras(alvo, 0); continue; }
    if (hora >= 20) { alvo = noveHoras(alvo, 1); continue; }
    return alvo;
  }
  return alvo;
}

/** Quando lembrar da promessa, a partir do que foi escrito e de quando foi mandado. */
export function quandoLembrar(texto: string, enviadaEm: Date): Date {
  const t = normalizar(texto);
  const base = enviadaEm.getTime();
  if (/\bamanha\b/.test(t)) return new Date(dentroDaJanela(noveHoras(base, 1)));
  for (let i = 1; i <= 6; i++) {
    if (new RegExp(`\\b${DIAS[i]}\\b`).test(t)) {
      const hoje = emBrasilia(base).dia;
      const faltam = ((i - hoje + 7) % 7) || 7;
      return new Date(dentroDaJanela(noveHoras(base, faltam)));
    }
  }
  if (/\b(hoje|mais tarde|daqui a pouco|ja ja|em instantes|logo mais)\b/.test(t)) {
    return new Date(dentroDaJanela(base + 3 * 60 * 60 * 1000));
  }
  return new Date(dentroDaJanela(base + 24 * 60 * 60 * 1000));
}

/**
 * A promessa numa mensagem do dono: o trecho (a frase que promete) e quando lembrar. null = não é
 * promessa. Pergunta ("te mando amanhã?") não conta.
 */
export function detectarPromessa(texto: string | null | undefined, enviadaEm: Date): { trecho: string; quando: Date } | null {
  const bruto = String(texto ?? "").trim();
  if (!bruto || bruto.length > 2000) return null;
  // Mídia sem texto, ou mensagem automática de envio de documento.
  if (/^\[(audio|image|video|document|sticker)\]$/i.test(bruto)) return null;
  const frases = bruto.split(/(?<=[.!?\n])\s*/).map((f) => f.trim()).filter(Boolean);
  for (const frase of frases) {
    if (frase.endsWith("?")) continue;
    const n = normalizar(frase);
    if (PADROES.some((p) => p.test(n))) {
      return { trecho: frase.length > 200 ? `${frase.slice(0, 200)}…` : frase, quando: quandoLembrar(bruto, enviadaEm) };
    }
  }
  return null;
}

// ── O prazo do FORNECEDOR na conversa (Agenda de Produção, Fase 4, P4 — 25/10/2026) ─────────────────────────────
// spec-fase4 §5.4.1. Por padrão de texto, sem IA, como a promessa do dono: acha o que o fornecedor (ou a HBR, na mesma
// conversa) disse sobre a entrega — "Já foi coletado", "chega aqui amanhã", "5 dias úteis", "Recebeu o compressor?",
// "vai atrasar, só chega sexta" — e devolve só a EXPRESSÃO dita ("amanhã", "dia 14", "5 dias úteis"). Quem converte a
// expressão em data é o banco (material_sinal_registrar → agenda_data_dita, com o dia da mensagem em Brasília); nada
// aqui calcula data. Erra para o lado de NÃO detectar: uma previsão a menos é melhor que uma falsa (o detector só liga
// medido, com a precisão mínima de agenda_config).
//
// Regras (por frase, sem acento e minúsculo):
//   · frase que termina em "?" não conta, menos a pergunta "recebeu/chegou?" do fornecedor (perguntou_chegou);
//   · frase de dinheiro (boleto, pagamento, Pix, R$…) nunca é prazo de material: a Kamell só cobra pelo WhatsApp;
//   · negação antes do verbo, na mesma oração ("não chega amanhã", "ainda não foi coletado") = nada; o futuro do
//     despacho ("vai ser despachado") também;
//   · condicional = a frase tem "se", "caso" ou "desde que" ("chega aqui amanhã se eles retirarem hoje");
//   · numa mensagem com mais de um achado vale o de mais informação: atraso com data, chegada, prazo, atraso sem data,
//     despacho, a pergunta "recebeu?".

export type TipoDoPrazo = "despacho" | "chegada" | "prazo" | "perguntou_chegou" | "atraso";

export interface PrazoDoFornecedor {
  tipo: TipoDoPrazo;
  /** A expressão de data como foi dita ("amanhã", "dia 14", "3 a 5 dias úteis"); null = a data é a da mensagem. */
  expressao: string | null;
  condicional: boolean;
  /** A frase da mensagem, como foi escrita (até 200 caracteres). */
  trecho: string;
}

const DIA_DA_SEMANA = "(?:segunda|terca|quarta|quinta|sexta)(?:[- ]feira)?|sabado|domingo";
/** Uma data dita, já sem acento: "amanha", "sexta", "dia 14", "14/10", "semana que vem". */
const UMA_DATA = "(?:depois de amanha|amanha|hoje|semana que vem|proxima semana|(?:proxima |proximo )?(?:" + DIA_DA_SEMANA +
  ")(?: que vem| da semana que vem)?|\\d{1,2}/\\d{1,2}(?:/\\d{2,4})?|dia \\d{1,2}(?:/\\d{1,2})?)";
/** A data dita, com "até" (a faixa a partir do dia da mensagem) e a segunda data da faixa ("sexta ou sábado"). */
const DATA = "((?:ate )?" + UMA_DATA + "(?: (?:ou|a|e) (?:(?:na|no|o|a) )?" + UMA_DATA + ")?)";
/** O que vem entre o verbo e a data e não entra na expressão. */
const ANTES_DA_DATA = "(?:(?:para|pra|na|no|nesta|nessa|neste|nesse|esta|essa|este|esse|em) )?";

const CHEGADA: RegExp[] = [
  new RegExp("\\bcheg(?:a|am|ara|arao)(?: (?:aqui|ai|la|pra voce|para voce))? " + ANTES_DA_DATA + DATA),
  new RegExp("\\bentreg(?:a|ar|amos|arei|aremos|am)(?: (?:prevista|programada|agendada))?(?: (?:aqui|ai))? " + ANTES_DA_DATA + DATA),
  new RegExp("\\bprevisao de (?:chegada|entrega)[: ]+(?:(?:e|eh|fica|para|pra) )?" + ANTES_DA_DATA + DATA),
  new RegExp("\\b(?:deve(?:ra|m)?|vai|vao) chegar(?: (?:aqui|ai|la))? " + ANTES_DA_DATA + DATA),
  new RegExp("\\bchegar (?:(?:aqui|ai|la) )?(ate " + UMA_DATA + ")"),
];

const DESPACHO: RegExp[] = [
  /\b(?:ja )?foi coletad[oa]s?\b/,
  /\bcoletaram\b/,
  /\bdespachad[oa]s?\b/,
  /\bfoi postad[oa]s?\b/,
  /\bpostei\b/,
  /\bsaiu (?:hoje )?(?:pela|na|com a) transportadora\b/,
  /\benviad[oa]s? hoje\b/,
  /\bnota emitida e (?:ja )?(?:enviad|despachad)/,
];

const NUMERO = "(\\d{1,2}|um|uma|dois|duas|tres|quatro|cinco|seis|sete|oito|nove|dez)";
const PRAZO: Array<{ re: RegExp; unidade?: "uteis" }> = [
  { re: new RegExp("\\b" + NUMERO + "(?: (?:a|ou) " + NUMERO + ")? dias? (?:uteis|util)\\b"), unidade: "uteis" },
  { re: new RegExp("\\bprazo (?:de |e de |eh de |e )?" + NUMERO + "(?: (?:a|ou) " + NUMERO + ")? dias?(?: (uteis|util|corridos))?\\b") },
  { re: new RegExp("\\bem " + NUMERO + "(?: (?:a|ou) " + NUMERO + ")? dias(?: (uteis|corridos))?\\b") },
];

const ATRASO: RegExp[] = [
  /\bvai atrasar\b/,
  /\batrasou\b/,
  /\bvai ter (?:um )?atraso\b/,
  /\bso (?:vai )?cheg(?:a|ar|ara)\b/,
  /\bnao vai (?:dar|conseguir) (?:pra |para )?(?:entregar|enviar|mandar|despachar|chegar|sair|coletar)\b/,
  /\bnao vai dar (?:pra |para )?(?:hoje|amanha)\b/,
];

/** Frase de dinheiro: nunca é prazo de material (a cobrança do boleto, o comprovante, o Pix). */
const DINHEIRO =
  /\b(?:boletos?|pagamentos?|pagar|paguei|pago|pix|faturas?|parcelas?|cobrancas?|vencimento|vence|comprovantes?|transferencias?|depositos?|reais)\b|r\$/;
/** O que a pergunta "recebeu?" pode estar perguntando e não é material. */
const NAO_E_MATERIAL =
  /\b(?:e-?mail|mensage(?:m|ns)|msg|orcamentos?|propostas?|cotac(?:ao|oes)|audios?|fotos?|arquivos?|pdf|links?|documentos?|notas?|nf|nfe|contratos?|planilhas?)\b/;
const RECEBEU = /\b(?:recebeu|recebeste|receberam|recebido|chegou|chegaram)\b/;
const NEGACAO = /\b(?:nao|nunca|sem)\b/;
const FUTURO_DO_DESPACHO = /\b(?:nao|nunca|vai|vao|sera|serao|vamos|vou|iremos|assim que|quando|antes de|precisa|preciso|se)\b/;
const CONDICIONAL = /\b(?:se|caso|desde que)\b/;
const POR_EXTENSO: Record<string, number> = {
  um: 1, uma: 1, dois: 2, duas: 2, tres: 3, quatro: 4, cinco: 5, seis: 6, sete: 7, oito: 8, nove: 9, dez: 10,
};
const ACENTOS_DA_DATA: Array<[RegExp, string]> = [
  [/\bamanha\b/g, "amanhã"], [/\bterca\b/g, "terça"], [/\bsabado\b/g, "sábado"], [/\bate\b/g, "até"],
  [/\bproxima\b/g, "próxima"], [/\bproximo\b/g, "próximo"],
];

/** A expressão de data para guardar: com os acentos de volta e sem o "no"/"na" do meio da faixa ("sexta ou sábado"). */
function expressaoDaData(bruta: string): string {
  let e = bruta.replace(/ (ou|a|e) (?:na|no|o|a) /, " $1 ").trim();
  for (const [re, com] of ACENTOS_DA_DATA) e = e.replace(re, com);
  return e;
}

function numeroDito(n: string | undefined): number | null {
  if (!n) return null;
  const v = /^\d+$/.test(n) ? Number(n) : POR_EXTENSO[n];
  return v !== undefined && Number.isFinite(v) && v > 0 ? v : null;
}

/** O pedaço da frase antes da posição, desde a última vírgula ou "mas" (onde a negação e o futuro valem). */
function antesNaMesmaOracao(frase: string, pos: number): string {
  const antes = frase.slice(0, pos);
  const corte = Math.max(antes.lastIndexOf(","), antes.lastIndexOf(";"), antes.lastIndexOf(" mas "));
  return corte >= 0 ? antes.slice(corte + 1) : antes;
}

interface Achado {
  tipo: TipoDoPrazo;
  expressao: string | null;
  prioridade: number;
}

/** O achado de UMA frase (já sem acento e minúscula), ou null. */
function achadoDaFrase(n: string, pergunta: boolean, direcao: "recebida" | "enviada"): Achado | null {
  if (DINHEIRO.test(n)) return null;
  if (pergunta) {
    // Só a pergunta do fornecedor "Recebeu o compressor?" / "Chegou?" (e não "Chegou a ver o orçamento?").
    if (direcao !== "recebida" || !RECEBEU.test(n)) return null;
    if (/\bchegou a [a-z]+r\b/.test(n) || NAO_E_MATERIAL.test(n)) return null;
    return { tipo: "perguntou_chegou", expressao: null, prioridade: 1 };
  }
  // 1. atraso (com a data nova, se disse: "só vai chegar dia 20", "atrasou, chega sexta")
  for (const re of ATRASO) {
    const m = re.exec(n);
    if (!m) continue;
    const resto = n.slice(m.index + m[0].length);
    const datas = [...resto.matchAll(new RegExp("(?:^|\\s)" + ANTES_DA_DATA + DATA, "g"))]
      .map((x) => x[1])
      .filter((d) => d !== "hoje");
    if (datas.length) return { tipo: "atraso", expressao: expressaoDaData(datas[0]), prioridade: 6 };
    return { tipo: "atraso", expressao: null, prioridade: 3 };
  }
  // 2. chegada com data
  for (const re of CHEGADA) {
    const m = re.exec(n);
    if (!m) continue;
    if (NEGACAO.test(antesNaMesmaOracao(n, m.index))) return null;
    return { tipo: "chegada", expressao: expressaoDaData(m[1]), prioridade: 5 };
  }
  // 3. prazo em dias ("5 dias úteis", "3 a 5 dias úteis", "prazo de 5 dias")
  for (const { re, unidade } of PRAZO) {
    const m = re.exec(n);
    if (!m) continue;
    if (NEGACAO.test(antesNaMesmaOracao(n, m.index))) return null;
    const a = numeroDito(m[1]);
    const b = numeroDito(m[2]);
    if (a === null) continue;
    const un = unidade ?? (m[3] === "corridos" ? "corridos" : m[3] ? "uteis" : null);
    const faixa = b !== null && b !== a ? `${Math.min(a, b)} a ${Math.max(a, b)}` : String(a);
    const varios = Math.max(a, b ?? a) > 1;
    const sufixo = un === "uteis"
      ? (varios ? "dias úteis" : "dia útil")
      : un === "corridos" ? "dias corridos" : varios ? "dias" : "dia";
    return { tipo: "prazo", expressao: `${faixa} ${sufixo}`, prioridade: 4 };
  }
  // 4. despacho ("Já foi coletado"): a data é a da mensagem
  for (const re of DESPACHO) {
    const m = re.exec(n);
    if (!m) continue;
    if (FUTURO_DO_DESPACHO.test(antesNaMesmaOracao(n, m.index))) return null;
    return { tipo: "despacho", expressao: null, prioridade: 2 };
  }
  return null;
}

/**
 * O prazo de entrega numa mensagem da conversa com o fornecedor: o tipo, a expressão de data dita (sem converter), se
 * depende de uma condição e a frase. null = nada sobre a entrega. `direcao` = quem escreveu: o fornecedor (recebida) ou
 * a HBR (enviada); a pergunta "recebeu?" só vale do fornecedor. `_enviadaEm` não entra na conta (a data sai do banco,
 * com o dia da mensagem em Brasília): fica na assinatura para o chamador dizer de quando é a mensagem, como na promessa.
 */
export function detectarPrazoDeFornecedor(
  texto: string | null | undefined,
  _enviadaEm: Date,
  direcao: "recebida" | "enviada",
): PrazoDoFornecedor | null {
  const bruto = String(texto ?? "").trim();
  if (!bruto || bruto.length > 4000) return null;
  // Mídia sem texto ("[document]", "[audio]") e o conteúdo vazio do webhook.
  if (/^\[(?:audio|image|imagem|video|document|documento|sticker|conte[uú]do vazio)\]\s*$/i.test(bruto)) return null;
  const frases = bruto.split(/(?<=[.!?\n])\s*/).map((f) => f.trim()).filter(Boolean);
  let melhor: (Achado & { frase: string }) | null = null;
  for (const frase of frases) {
    const n = normalizar(frase).replace(/["“”]/g, "");
    const a = achadoDaFrase(n, frase.endsWith("?"), direcao);
    if (a && (!melhor || a.prioridade > melhor.prioridade)) melhor = { ...a, frase };
  }
  if (!melhor) return null;
  return {
    tipo: melhor.tipo,
    expressao: melhor.expressao,
    condicional: melhor.tipo !== "perguntou_chegou" && CONDICIONAL.test(normalizar(melhor.frase)),
    trecho: melhor.frase.length > 200 ? `${melhor.frase.slice(0, 200)}…` : melhor.frase,
  };
}
