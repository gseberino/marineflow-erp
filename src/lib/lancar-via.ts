/**
 * Regras de "Lançar a via": o que o técnico escreveu no papel vira dado da OS.
 *
 * Escolha do dono (01/10/2026): papel no local, e alguém do escritório passa para o
 * MarineFlow. A tela espelha a folha — chegada e saída, feito/parcial/não feito de cada
 * serviço, o relato e o material além do previsto.
 *
 * Campo em branco não muda nada. Lançar não apaga o que já estava nas notas do técnico:
 * o registro novo entra embaixo, com a data, para a história da OS continuar inteira.
 */

export type SituacaoDaVolta = 'feito' | 'parcial' | 'nao_feito';

export interface LancamentoDaVia {
  /** Valor do campo datetime-local (hora local). */
  chegada?: string;
  saida?: string;
  /** Por id da linha de serviço. Situação vazia = não mexer na linha. */
  servicos: Record<string, { situacao?: SituacaoDaVolta | ''; motivo?: string }>;
  relato?: string;
  materialExtra?: string;
}

/** As linhas de serviço que mudam, com o que gravar em cada uma. */
export function linhasParaGravar(l: LancamentoDaVia): Array<{
  id: string; field_status: SituacaoDaVolta; field_status_note: string | null;
}> {
  return Object.entries(l.servicos)
    .filter(([, v]) => !!v.situacao)
    .map(([id, v]) => ({
      id,
      field_status: v.situacao as SituacaoDaVolta,
      field_status_note: v.situacao === 'feito' ? null : (v.motivo || '').trim() || null,
    }));
}

/**
 * O que o papel trouxe, separado por destino. As notas do técnico saem impressas no
 * documento da OS do cliente; o material além do previsto é conversa de margem e vai para
 * as notas internas, que o cliente não vê. Cada parte vem vazia quando o papel não trouxe.
 */
export function registroDaVia(l: LancamentoDaVia, quando: Date): { tecnico: string; interno: string } {
  const relato = (l.relato || '').trim();
  const material = (l.materialExtra || '').trim();
  const data = quando.toLocaleDateString('pt-BR');
  return {
    tecnico: relato ? `[Via lançada em ${data}]\nO que encontrei / pendente / vigiar: ${relato}` : '',
    interno: material ? `[Via lançada em ${data}]\nMaterial além do previsto: ${material}` : '',
  };
}

/** Junta o registro novo embaixo do que já existia, sem perder nada. */
export function juntarNotas(atuais: string | null | undefined, registro: string): string {
  const antes = (atuais || '').trim();
  if (!registro) return antes;
  return antes ? `${antes}\n\n${registro}` : registro;
}

/** Há algo para gravar? O botão Lançar só acende quando sim. */
export function temAlgoParaLancar(l: LancamentoDaVia): boolean {
  return !!(l.chegada || l.saida || (l.relato || '').trim() || (l.materialExtra || '').trim()
    || linhasParaGravar(l).length);
}
