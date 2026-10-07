/**
 * A conta a receber que a cobrança da OS cobra (07/10/2026).
 *
 * A tela de Nova Cobrança lia a conta da OS só para sugerir valor e vencimento, mas não gravava
 * o vínculo (collections.receivable_id). Sem ele, o gatilho que marca a cobrança como paga quando
 * a conta é paga (sync_collection_from_receivable) não tinha o que marcar — e a régua podia lembrar
 * quem já pagou. A regra é a do assistente (criar_cobranca, _shared/ai/tools/cobrancas.ts):
 *  · uma conta em aberto → é ela;
 *  · várias → a pessoa escolhe a parcela (o valor dito desempata, se bater com um saldo só);
 *  · todas pagas → não há o que cobrar;
 *  · a OS sem conta a receber → a cobrança fica sem vínculo (como a avulsa).
 */

export interface RecebivelDaOS {
  id: string;
  description: string | null;
  amount: number | string;
  balance_amount: number | string | null;
  due_date: string | null;
  status: string;
}

export const SITUACOES_EM_ABERTO = ['pending', 'partially_paid', 'overdue'];

export const saldoDoRecebivel = (r: RecebivelDaOS) => Number(r.balance_amount ?? r.amount);

export type EscolhaDoRecebivel =
  | { tipo: 'sem_conta' }
  | { tipo: 'pagas' }
  | { tipo: 'uma'; recebivel: RecebivelDaOS }
  | { tipo: 'escolher'; abertas: RecebivelDaOS[]; recebivel: RecebivelDaOS | null };

/** As contas da OS (sem as canceladas) → qual a cobrança liga, ou o que perguntar. */
export function escolherRecebivel(contas: RecebivelDaOS[], escolhidoId?: string | null): EscolhaDoRecebivel {
  const vivas = contas.filter((r) => r.status !== 'cancelled');
  const abertas = vivas.filter((r) => SITUACOES_EM_ABERTO.includes(r.status));
  if (abertas.length === 1) return { tipo: 'uma', recebivel: abertas[0] };
  if (abertas.length > 1) {
    return { tipo: 'escolher', abertas, recebivel: abertas.find((r) => r.id === escolhidoId) ?? null };
  }
  return vivas.length ? { tipo: 'pagas' } : { tipo: 'sem_conta' };
}

/** O recebível escolhido (ou nenhum, quando a OS não tem conta); null em 'escolher' sem escolha. */
export function recebivelDaEscolha(e: EscolhaDoRecebivel): RecebivelDaOS | null {
  return e.tipo === 'uma' || e.tipo === 'escolher' ? e.recebivel : null;
}
