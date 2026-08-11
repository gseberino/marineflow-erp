// [MF-AUD-009] Redistribuição dos recebíveis quando o total da OS muda.
//
// ═══ POR QUE ISTO VIROU MÓDULO PURO ═══
//
// A regra existia só dentro de `updateReceivableFromSO`, no frontend, misturada com as
// chamadas ao banco. O agente de IA altera a mesma OS por outro caminho (a RPC
// `recalc_so_totals`), que atualiza `service_orders` e mais nada — nenhuma cascata, nenhuma
// checagem do piso. Resultado: o agente muda o valor da OS e o título a receber fica com o
// valor antigo, sem erro nenhum. Pior, dá para derrubar o total ABAIXO do que o cliente já
// pagou — cenário que a tela bloqueia de propósito.
//
// Separar a aritmética do acesso ao banco é o que permite os dois caminhos usarem a MESMA
// regra. Sem isso, corrigir o agente significaria escrever a fórmula uma segunda vez, e duas
// fórmulas de dinheiro divergem — é literalmente o bug que originou a lib `quote-deposit`.
//
// ⚠ Este é o ESPELHO do lado das edge functions. O original vive em
// `src/lib/receivable-redistribution.ts` (Vite e Deno não compartilham módulo aqui) e um
// teste de paridade roda os dois com as mesmas entradas e falha se discordarem.

export interface RecebivelParaRedistribuir {
  id: string;
  amount: number | null;
  paid_amount?: number | null;
  status?: string | null;
}

export interface AlteracaoDeRecebivel {
  id: string;
  amount: number;
  balance_amount: number;
  status: 'paid' | 'partially_paid' | 'pending';
  anterior: { amount: number; balance_amount: number; status: string | null };
}

export interface ResultadoDaRedistribuicao {
  /** true = nada deve ser gravado; o novo total ficaria abaixo do já pago. */
  bloqueado: boolean;
  motivo?: string;
  totalPago: number;
  alteracoes: AlteracaoDeRecebivel[];
}

const centavos = (n: number) => Math.round(n * 100) / 100;

/**
 * O que gravar em cada recebível quando o total da OS passa a ser `novoTotal`.
 *
 * Não toca no banco: devolve a intenção. Quem chama grava — e é o que torna a regra testável
 * e compartilhável entre a tela e o agente.
 *
 * Três invariantes, cada uma protegendo um jeito diferente de perder dinheiro:
 *
 *   1. **Piso agregado.** Se o novo total for menor que a soma já paga, BLOQUEIA. Reduzir a OS
 *      abaixo do que o cliente pagou criaria um saldo negativo — na prática, uma devolução que
 *      ninguém decidiu fazer.
 *   2. **Recebível quitado não encolhe.** Título já pago é fato consumado; redimensioná-lo
 *      reescreveria história e desencontraria o financeiro do extrato.
 *   3. **Piso individual.** Mesmo com a soma dentro do limite, nenhum título isolado cai
 *      abaixo do que já foi pago NELE — senão o saldo daquele título fica negativo enquanto o
 *      agregado parece saudável.
 */
export function redistribuirRecebiveis(
  recebiveis: RecebivelParaRedistribuir[],
  novoTotal: number,
): ResultadoDaRedistribuicao {
  const ativos = (recebiveis ?? []).filter((r) => r.status !== 'cancelled');
  const totalPago = ativos.reduce((s, r) => s + Number(r.paid_amount || 0), 0);

  if (ativos.length === 0) {
    return { bloqueado: false, totalPago: 0, alteracoes: [] };
  }

  // A tolerância de 1 centavo existe porque o total da OS vem de somas com arredondamento;
  // sem ela, um resíduo de fração bloquearia alteração legítima.
  if (novoTotal < totalPago - 0.01) {
    return {
      bloqueado: true,
      motivo:
        `O novo total (R$ ${novoTotal.toFixed(2)}) ficaria abaixo do valor já pago pelo `
        + `cliente (R$ ${totalPago.toFixed(2)}). A alteração foi bloqueada — revise antes de continuar.`,
      totalPago,
      alteracoes: [],
    };
  }

  const quitados = ativos.filter((r) => r.status === 'paid');
  const pendentes = ativos.filter((r) => r.status !== 'paid');
  if (pendentes.length === 0) return { bloqueado: false, totalPago, alteracoes: [] };

  const totalQuitado = quitados.reduce((s, r) => s + Number(r.amount || 0), 0);
  const sobraParaPendentes = Math.max(0, novoTotal - totalQuitado);
  const totalPendenteAntigo = pendentes.reduce((s, r) => s + Number(r.amount || 0), 0);

  return {
    bloqueado: false,
    totalPago,
    alteracoes: pendentes.map((rec) => {
      // Sem base anterior (todos zerados), divide igual — proporção de zero não existe.
      const fatia = totalPendenteAntigo > 0
        ? Number(rec.amount || 0) / totalPendenteAntigo
        : 1 / pendentes.length;

      const pago = Number(rec.paid_amount || 0);
      const amount = Math.max(pago, centavos(sobraParaPendentes * fatia));
      const balance = Math.max(0, centavos(amount - pago));
      const status = pago >= amount ? 'paid' : pago > 0 ? 'partially_paid' : 'pending';

      return {
        id: rec.id,
        amount,
        balance_amount: balance,
        status: status as AlteracaoDeRecebivel['status'],
        anterior: {
          amount: Number(rec.amount || 0),
          balance_amount: Math.max(0, Number(rec.amount || 0) - pago),
          status: rec.status ?? null,
        },
      };
    }),
  };
}
