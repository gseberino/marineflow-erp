// Gravação das transações do extrato em lotes (06/10/2026, inventário).
//
// O banking-sync inseria de 200 em 200 e, se o lote falhava, lançava o erro: UMA linha com
// problema (um campo fora do formato, uma linha que outra sincronização gravou no meio) derrubava
// as outras 199 e a sincronização inteira saía como erro. Agora o lote que falha é refeito linha
// a linha: as boas entram, a repetida conta como "já existia" e só a ruim fica de fora — com o
// motivo, para aparecer na mensagem da sincronização.

export const TAMANHO_DO_LOTE = 200;

export interface ErroDoBanco {
  code?: string;
  message?: string;
}

export interface ResultadoDaGravacao {
  gravadas: number;
  /** Já estavam gravadas (violação do índice único) — chegaram entre a conferência e o insert. */
  jaExistiam: number;
  falhas: { bank_ref_id: string; erro: string }[];
}

/** 23505 = unique_violation: a linha já está no banco. */
const ehRepetida = (e: ErroDoBanco) => e.code === "23505";

export async function gravarEmLotes<T extends { bank_ref_id: string }>(
  linhas: T[],
  inserir: (lote: T[]) => Promise<{ error: ErroDoBanco | null }>,
  tamanho = TAMANHO_DO_LOTE,
): Promise<ResultadoDaGravacao> {
  const r: ResultadoDaGravacao = { gravadas: 0, jaExistiam: 0, falhas: [] };
  for (let i = 0; i < linhas.length; i += tamanho) {
    const lote = linhas.slice(i, i + tamanho);
    const { error } = await inserir(lote);
    if (!error) {
      r.gravadas += lote.length;
      continue;
    }
    for (const linha of lote) {
      const { error: e } = await inserir([linha]);
      if (!e) r.gravadas++;
      else if (ehRepetida(e)) r.jaExistiam++;
      else r.falhas.push({ bank_ref_id: linha.bank_ref_id, erro: String(e.message ?? e.code ?? "erro desconhecido").slice(0, 200) });
    }
  }
  return r;
}

/** Trecho da mensagem da sincronização sobre o que não entrou. */
export function avisoDeFalhas(falhas: ResultadoDaGravacao["falhas"]): string | null {
  if (falhas.length === 0) return null;
  return `${falhas.length} não gravada(s) (${falhas[0].erro}) — a próxima sincronização tenta de novo`;
}
