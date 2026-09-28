// Janela da busca de transações no provedor e o que muda numa transação já importada
// (27/09/2026, com o "pode corrigir" do dono).
//
// A busca era "desde a transação mais recente já importada, menos 7 dias". Dois defeitos:
//   · o cartão de crédito traz as parcelas FUTURAS com a data em que caem (Coremma 4/4 em
//     13/11/2026): a "mais recente" virava novembro e a busca seguinte começava em 06/11. O
//     Nubank — cartão E conta PJ — ficou sem importar nada de 14/08 a 27/09/2026;
//   · compra de cartão entra no provedor (ou é lançada pelo banco) até semanas depois da data
//     dela, e 7 dias de sobreposição perdiam essas.
// E a sincronização só INSERIA: a compra que chegava "pendente" ficava pendente para sempre,
// sem a fatura e sem a parcela, mesmo depois de o banco lançá-la — o motor da fila não olha
// pendente, então ela nunca virava proposta.

export const JANELA_INICIAL_DIAS = 365;
/** Sobreposição em cima da última transação conhecida, para pegar lançamento atrasado. */
export const SOBREPOSICAO_DIAS = 7;
/** Cartão: a compra entra no provedor (ou é lançada) até semanas depois da data dela. */
export const SOBREPOSICAO_CARTAO_DIAS = 45;

function menosDias(data: string, dias: number): string {
  const d = new Date(`${data.slice(0, 10)}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() - dias);
  return d.toISOString().slice(0, 10);
}

/** De que data a busca no provedor começa. A última guardada nunca passa de hoje. */
export function inicioDaBusca(
  ultimaGuardada: string | null | undefined,
  hoje: string,
  opcoes: { completa?: boolean; temCartao?: boolean } = {},
): string {
  if (opcoes.completa || !ultimaGuardada) return menosDias(hoje, JANELA_INICIAL_DIAS);
  const ultima = ultimaGuardada.slice(0, 10) > hoje ? hoje : ultimaGuardada.slice(0, 10);
  return menosDias(ultima, opcoes.temCartao ? SOBREPOSICAO_CARTAO_DIAS : SOBREPOSICAO_DIAS);
}

/**
 * A "transação mais recente" que fica guardada: a maior data até hoje entre a guardada e as que
 * chegaram. Parcela futura não conta. Se a guardada era futura (o defeito antigo) e nada chegou
 * até hoje, fica hoje — para a busca seguinte não voltar a começar no futuro.
 */
export function transacaoMaisRecente(guardada: string | null | undefined, datas: string[], hoje: string): string | null {
  const g = guardada ? guardada.slice(0, 10) : null;
  let maior: string | null = g && g <= hoje ? g : null;
  for (const d of datas) {
    const dia = d.slice(0, 10);
    if (dia <= hoje && (!maior || dia > maior)) maior = dia;
  }
  if (!maior && g && g > hoje) return hoje;
  return maior;
}

export interface EstadoDaLinha {
  tx_status: string | null;
  bill_id: string | null;
  installment_label: string | null;
}

/**
 * O que o provedor mudou numa transação já importada: status (pendente → lançada), a fatura e a
 * parcela. Só o que ele manda preenchido e diferente; nunca volta de lançada para pendente. Valor
 * e data ficam de fora de propósito — mudá-los reescreveria em silêncio o que já foi conferido.
 */
export function mudancasDoProvedor(atual: EstadoDaLinha, provedor: EstadoDaLinha): Partial<EstadoDaLinha> {
  const patch: Partial<EstadoDaLinha> = {};
  const status = provedor.tx_status;
  if (status && status !== atual.tx_status && !(status === "PENDING" && atual.tx_status === "POSTED")) {
    patch.tx_status = status;
  }
  if (provedor.bill_id && provedor.bill_id !== atual.bill_id) patch.bill_id = provedor.bill_id;
  if (provedor.installment_label && provedor.installment_label !== atual.installment_label) {
    patch.installment_label = provedor.installment_label;
  }
  return patch;
}
