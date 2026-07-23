// Cadência Inteligente (módulo D). Pesquisa B2B: ~6 toques em ~3 semanas, os primeiros mais
// próximos (1–2 dias) e depois espaçados (3–4 dias); NUNCA repetir a mesma mensagem; teto de
// toques (além dele, cai a resposta e sobe a irritação). Função PURA e testável.

export const MAX_TOQUES = 6;

/** Espaçamento mínimo (em dias) ANTES do próximo toque, dado quantos já foram dados. */
export function espacamentoMinimoDias(toquesJaDados: number): number {
  // toque 1→2 e 2→3: 2 dias; depois: 4 dias.
  return toquesJaDados <= 2 ? 2 : 4;
}

export interface DecisaoToque {
  permitido: boolean;
  motivo: string;
  /** Quando permitido no futuro, a partir de quando (ISO). */
  esperarAte?: string;
}

/**
 * Decide se pode dar mais um toque agora.
 * @param toquesJaDados quantas mensagens desta cadência já foram enviadas.
 * @param ultimoToqueEm ISO da última; ausente = nunca tocou (pode).
 */
export function podeTocarAgora(toquesJaDados: number, ultimoToqueEm?: string | null, agora: Date = new Date()): DecisaoToque {
  if (toquesJaDados >= MAX_TOQUES) {
    return { permitido: false, motivo: `Teto de ${MAX_TOQUES} toques atingido — pare de insistir (vira ruído) e proponha outra abordagem ao dono.` };
  }
  if (!ultimoToqueEm) {
    return { permitido: true, motivo: "Primeiro toque." };
  }
  const ultimo = new Date(ultimoToqueEm);
  if (isNaN(ultimo.getTime())) return { permitido: true, motivo: "Sem data válida do último toque." };
  const dias = (agora.getTime() - ultimo.getTime()) / 86400000;
  const minimo = espacamentoMinimoDias(toquesJaDados);
  if (dias < minimo) {
    const esperarAte = new Date(ultimo.getTime() + minimo * 86400000).toISOString();
    return { permitido: false, motivo: `Muito cedo: último toque há ${dias.toFixed(1)}d; espere ${minimo}d entre toques.`, esperarAte };
  }
  return { permitido: true, motivo: `OK: ${dias.toFixed(1)}d desde o último (mínimo ${minimo}d). Traga um gancho NOVO, não repita.` };
}
