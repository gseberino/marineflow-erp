// Conciliar criando o lançamento: cada passo confere o erro (19/11/2026). Antes a tela dizia
// "Conciliado" mesmo com a conta, o pagamento ou a marcação do extrato sem gravar.
import { beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('@/integrations/supabase/client', async () => ({ supabase: (await import('@/test/banco-falso')).supabaseFalso }));

import { lancarEConciliar, ConciliacaoIncompleta } from './conciliar-com-lancamento-novo';
import { banco, ok, falha, reiniciarBanco, chamadasA } from '@/test/banco-falso';

const base = {
  tabela: 'receivables' as const,
  conta: { client_id: 'c1', amount: 100, status: 'paid', bank_transaction_id: 'bt1' },
  bankTransactionId: 'bt1', dataDoPagamento: '2026-11-19', valor: 100,
  extratoExtra: { reconciled_service_order_id: 'so1' },
};

beforeEach(() => reiniciarBanco());

describe('lancarEConciliar', () => {
  it('tudo grava: conta → pagamento → extrato conciliado com o pagamento', async () => {
    banco.respostas['receivables.insert'] = ok({ id: 'r1' });
    banco.respostas['payments.insert'] = ok({ id: 'p1' });
    await expect(lancarEConciliar(base)).resolves.toEqual({ contaId: 'r1', pagamentoId: 'p1' });
    expect((chamadasA('payments.insert')[0].valores as Record<string, unknown>).receivable_id).toBe('r1');
    expect(chamadasA('bank_transactions.update')[0].valores).toMatchObject({
      reconciled: true, reconciled_payment_id: 'p1', reconciled_service_order_id: 'so1',
    });
  });

  it('conta não grava: relança o erro original e não segue', async () => {
    banco.respostas['receivables.insert'] = { data: null, error: { message: 'duplicate key 23505' } };
    await expect(lancarEConciliar(base)).rejects.toMatchObject({ message: 'duplicate key 23505' });
    expect(chamadasA('payments.insert')).toHaveLength(0);
    expect(chamadasA('bank_transactions.update')).toHaveLength(0);
  });

  it('pagamento não grava: avisa que a conta ficou e o extrato não foi marcado', async () => {
    banco.respostas['receivables.insert'] = ok({ id: 'r1' });
    banco.respostas['payments.insert'] = falha('rls');
    const erro = await lancarEConciliar(base).catch((e) => e);
    expect(erro).toBeInstanceOf(ConciliacaoIncompleta);
    expect(erro.message).toMatch(/conta a receber foi criada.*pagamento NÃO foi registrado/);
    expect(chamadasA('bank_transactions.update')).toHaveLength(0);
  });

  it('extrato não marca: avisa que conta e pagamento ficaram', async () => {
    banco.respostas['payables.insert'] = ok({ id: 'd1' });
    banco.respostas['payments.insert'] = ok({ id: 'p1' });
    banco.respostas['bank_transactions.update'] = falha('timeout');
    const erro = await lancarEConciliar({ ...base, tabela: 'payables' }).catch((e) => e);
    expect(erro).toBeInstanceOf(ConciliacaoIncompleta);
    expect(erro.message).toMatch(/conta a pagar e o pagamento foram registrados.*NÃO ficou marcada/);
    expect((chamadasA('payments.insert')[0].valores as Record<string, unknown>).payable_id).toBe('d1');
  });
});
