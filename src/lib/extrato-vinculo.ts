// A mesma regra do servidor, na tela: qual vínculo vale para uma linha do Extrato e quando
// a linha não pode ser aprovada sem alguém escolher.
//
// A política mora em supabase/functions/_shared/banking/vinculo.ts (vinculoAutomatico,
// exigeDecisao) e é importada daqui — a tela e o servidor não podem discordar sobre o que
// acontece quando se clica em aprovar.
import {
  exigeDecisao, podeJaEstarLancado, vinculoAutomatico, type OpcaoDeVinculo, type VinculoSugerido,
} from '../../supabase/functions/_shared/banking/vinculo';

export type EscolhaDeVinculo = { id: string } | 'nenhum' | undefined;

/** Todas as opções de uma sugestão, a principal primeiro. */
export function opcoesDoVinculo(v: VinculoSugerido | null | undefined): OpcaoDeVinculo[] {
  return v ? [v.principal, ...(v.alternativas ?? [])] : [];
}

/**
 * O que a aprovação vai usar: a escolha da pessoa; sem escolha, o vínculo automático.
 * `null` = lança novo.
 */
export function vinculoEfetivo(v: VinculoSugerido | null | undefined, escolha: EscolhaDeVinculo): OpcaoDeVinculo | null {
  if (escolha === 'nenhum') return null;
  if (escolha && typeof escolha === 'object') return opcoesDoVinculo(v).find((o) => o.id === escolha.id) ?? null;
  return vinculoAutomatico(v);
}

/**
 * Há vínculo sugerido e ninguém respondeu: não aprova no escuro (decisão do dono, 26/09/2026 —
 * toda sugestão de vínculo é pergunta).
 */
export function precisaDecidir(v: VinculoSugerido | null | undefined, escolha: EscolhaDeVinculo): boolean {
  if (escolha) return false;
  return exigeDecisao(v);
}

export { podeJaEstarLancado };

export {
  osVemDoVinculo, osAnotada, temPerguntaDaOS, temPerguntaDaOC, perguntaDaOSAberta, type LinhaComPerguntas,
} from '../../supabase/functions/_shared/banking/vinculo';
