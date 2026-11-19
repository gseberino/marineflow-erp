import { supabase } from '@/integrations/supabase/client';

/**
 * Concilia uma linha do extrato criando o lançamento dela: conta já quitada → pagamento →
 * linha do extrato marcada como conciliada.
 *
 * São três gravações separadas e, até 19/11/2026, nenhuma conferia o erro: a tela dizia
 * "Conciliado" mesmo quando a conta não tinha nascido, ou quando o pagamento falhava e a linha
 * do extrato ficava pendente. Agora cada passo confere o erro e, se um falha no meio, a mensagem
 * diz o que FICOU feito e o que NÃO — sem apagar nada (o arquivo não tem caminho de desfazer
 * pagamento, e apagar às cegas no financeiro é pior que avisar).
 *
 * Erro no PRIMEIRO passo é relançado como veio (nada foi gravado): quem chama já traduz o
 * 23505 de "esta transação já virou lançamento".
 */
export class ConciliacaoIncompleta extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ConciliacaoIncompleta';
  }
}

export interface LancamentoNovo {
  tabela: 'receivables' | 'payables';
  /** A conta, já quitada (status 'paid'), com bank_transaction_id. */
  conta: Record<string, unknown>;
  bankTransactionId: string;
  dataDoPagamento: string;
  valor: number;
  /** Campos a mais na linha do extrato (ex.: reconciled_service_order_id). */
  extratoExtra?: Record<string, unknown>;
}

export async function lancarEConciliar(l: LancamentoNovo): Promise<{ contaId: string; pagamentoId: string }> {
  const ehReceber = l.tabela === 'receivables';
  const nomeDaConta = ehReceber ? 'A conta a receber' : 'A conta a pagar';
  const ondeVer = ehReceber ? 'Contas a receber' : 'Contas a pagar';

  const { data: conta, error: contaErr } = await supabase
    .from(l.tabela).insert(l.conta as never).select().single();
  if (contaErr) throw contaErr;
  if (!conta) throw new Error('O banco não devolveu a conta criada — nada foi conciliado. Tente de novo.');
  const contaId = (conta as { id: string }).id;

  const { data: pagamento, error: pagErr } = await supabase.from('payments').insert({
    ...(ehReceber ? { receivable_id: contaId } : { payable_id: contaId }),
    payment_date: l.dataDoPagamento,
    amount: l.valor,
    payment_method: 'bank_transfer',
  } as never).select().single();
  if (pagErr || !pagamento) {
    throw new ConciliacaoIncompleta(
      `${nomeDaConta} foi criada já quitada, mas o pagamento NÃO foi registrado e a linha do extrato continua pendente. ` +
      `Confira essa conta em ${ondeVer} antes de tentar de novo.`,
    );
  }
  const pagamentoId = (pagamento as { id: string }).id;

  const { error: extratoErr } = await supabase.from('bank_transactions').update({
    reconciled: true, reconciled_payment_id: pagamentoId, ...(l.extratoExtra ?? {}),
  } as never).eq('id', l.bankTransactionId);
  if (extratoErr) {
    throw new ConciliacaoIncompleta(
      `${nomeDaConta} e o pagamento foram registrados, mas a linha do extrato NÃO ficou marcada como conciliada. ` +
      `Abra a linha de novo e vincule à conta que acabou de ser criada (em ${ondeVer}).`,
    );
  }
  return { contaId, pagamentoId };
}
