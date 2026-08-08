/**
 * Quando o salvamento automático NÃO deve agir.
 *
 * Cada regra aqui existe por um motivo concreto, e todas erram para o lado de
 * não gravar — porque o custo de uma gravação indevida num orçamento (valor
 * errado persistido, trigger de recálculo disparado no meio da edição) é maior
 * que o de esperar a pessoa clicar em Salvar.
 *
 * Separado do componente porque é a única parte do autosave que dá para provar
 * sem montar um formulário de 2.500 linhas.
 */
export interface AutosaveState {
  /** Ordem ainda não existe no banco. */
  isNew: boolean;
  /** Faturada ou cancelada — não se escreve mais nela. */
  isLocked: boolean;
  orderId: string | null | undefined;
  clientId: string | null | undefined;
  vesselId: string | null | undefined;
  problemDescription: string | null | undefined;
  /** JSON do que seria gravado agora. */
  assinaturaAtual: string;
  /** JSON do que foi gravado por último, se houve. */
  assinaturaSalva: string | null;
}

export type AutosaveDecision =
  | { salvar: true }
  | { salvar: false; motivo: 'nova' | 'travada' | 'incompleta' | 'sem-mudanca' };

export function decideAutosave(s: AutosaveState): AutosaveDecision {
  // Criar registro é ato deliberado — e o Salvar ainda precisa gravar as peças
  // e serviços de rascunho, que só existem na tela até a ordem nascer.
  if (s.isNew || !s.orderId) return { salvar: false, motivo: 'nova' };

  if (s.isLocked) return { salvar: false, motivo: 'travada' };

  // Obrigatórios ausentes: o salvamento manual recusaria com um aviso, e um
  // aviso a cada campo enquanto a pessoa monta o orçamento seria pior que não
  // ter autosave nenhum.
  if (!s.clientId || !s.vesselId || !s.problemDescription) {
    return { salvar: false, motivo: 'incompleta' };
  }

  // Sem diferença real não se escreve. É isto que impede a tela de gravar só
  // por ter sido aberta, ou por o servidor ter devolvido os mesmos dados.
  if (s.assinaturaAtual === s.assinaturaSalva) {
    return { salvar: false, motivo: 'sem-mudanca' };
  }

  return { salvar: true };
}
