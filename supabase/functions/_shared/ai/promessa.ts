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
