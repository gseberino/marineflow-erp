// Cascatas de dinheiro da OS e do pagamento (inventário de 03/10/2026: módulo sem nenhum teste).
//
// O que se protege: erro do banco no meio de uma cascata pára e avisa (antes cada gravação era um
// await sem conferir); cancelar a OS é só a função atômica do banco (o caminho antigo, passo a passo,
// soltava o Pix de duas contas); reabrir não estorna pagamento que veio do extrato; estornar um
// pagamento de Pix passa pelo "desfazer aplicação" da forma A.
import { describe, it, expect, vi, beforeEach } from 'vitest';

type Resposta = { data: unknown; error: { message: string } | null };

const banco = vi.hoisted(() => ({
  /** Resposta por "tabela.operação" (select/update/insert) ou "rpc.nome". */
  respostas: {} as Record<string, Resposta | Resposta[]>,
  chamadas: [] as Array<{ alvo: string; op: string; valores?: unknown; filtros: unknown[][] }>,
}));

function responder(chave: string): Resposta {
  const r = banco.respostas[chave];
  if (Array.isArray(r)) return r.length > 1 ? r.shift()! : r[0];
  return r ?? { data: null, error: null };
}

vi.mock('@/integrations/supabase/client', () => {
  const consulta = (tabela: string) => {
    const registro = { alvo: tabela, op: 'select', valores: undefined as unknown, filtros: [] as unknown[][] };
    // deno-lint-ignore no-explicit-any
    const q: any = {};
    for (const m of ['select', 'eq', 'not', 'in', 'neq', 'limit', 'order']) {
      q[m] = (...a: unknown[]) => { if (m !== 'select' || registro.op === 'select') registro.filtros.push([m, ...a]); return q; };
    }
    q.update = (v: unknown) => { registro.op = 'update'; registro.valores = v; return q; };
    q.insert = (v: unknown) => { registro.op = 'insert'; registro.valores = v; return q; };
    q.single = () => q;
    q.maybeSingle = () => q;
    // deno-lint-ignore no-explicit-any
    q.then = (ok: any, erro: any) => {
      banco.chamadas.push(registro);
      return Promise.resolve(responder(`${tabela}.${registro.op}`)).then(ok, erro);
    };
    return q;
  };
  return {
    supabase: {
      from: (t: string) => consulta(t),
      rpc: (nome: string, args: unknown) => {
        banco.chamadas.push({ alvo: `rpc.${nome}`, op: 'rpc', valores: args, filtros: [] });
        return Promise.resolve(responder(`rpc.${nome}`));
      },
    },
  };
});
vi.mock('@/hooks/use-audit-log', () => ({ writeAuditLog: vi.fn(async () => undefined) }));

import {
  cancelPaymentCascade, cancelServiceOrderCascade, recalcReceivableBalance, reopenServiceOrder, updateReceivableFromSO,
  GrandTotalBelowPaidError,
} from './cascade-updates';

const ok = (data: unknown): Resposta => ({ data, error: null });
const falha = (message: string): Resposta => ({ data: null, error: { message } });
const gravacoes = (alvo: string) => banco.chamadas.filter((c) => c.alvo === alvo && (c.op === 'update' || c.op === 'insert'));

beforeEach(() => {
  banco.respostas = {};
  banco.chamadas = [];
});

describe('cancelServiceOrderCascade', () => {
  it('usa a função atômica do banco e devolve o que ela fez', async () => {
    banco.respostas['rpc.cancel_service_order_cascade'] = ok({
      success: true, parts_restored: 0, receivables_cancelled: 2, payments_cancelled: 1, collections_cancelled: 0, deposit_paid: 500,
    });
    const r = await cancelServiceOrderCascade('os1', 'cliente desistiu');
    expect(r).toEqual({ parts_restored: 0, receivables_cancelled: 2, payments_cancelled: 1, collections_cancelled: 0, deposit_paid: 500 });
  });

  it('se a função falha, falha o cancelamento — sem o caminho antigo passo a passo', async () => {
    banco.respostas['rpc.cancel_service_order_cascade'] = falha('timeout');
    await expect(cancelServiceOrderCascade('os1', 'x')).rejects.toThrow('Não consegui cancelar a OS: timeout');
    // Nada foi gravado pelo navegador.
    expect(banco.chamadas.filter((c) => c.op !== 'rpc')).toEqual([]);
  });
});

describe('updateReceivableFromSO', () => {
  it('lê as contas com erro conferido e grava a redistribuição', async () => {
    banco.respostas['receivables.select'] = ok([
      { id: 'r1', amount: 1000, paid_amount: 0, balance_amount: 1000, status: 'pending', is_deposit: false, due_date: '2026-10-10' },
    ]);
    await updateReceivableFromSO('os1', 1200);
    expect(gravacoes('receivables')[0].valores).toMatchObject({ amount: 1200 });
  });

  it('leitura que falha pára (não segue como se a OS não tivesse contas)', async () => {
    banco.respostas['receivables.select'] = falha('permission denied');
    await expect(updateReceivableFromSO('os1', 1200)).rejects.toThrow('Não consegui ler as contas da OS');
  });

  it('gravação que falha pára no meio e avisa', async () => {
    banco.respostas['receivables.select'] = ok([
      { id: 'r1', amount: 1000, paid_amount: 0, balance_amount: 1000, status: 'pending', is_deposit: false, due_date: '2026-10-10' },
    ]);
    banco.respostas['receivables.update'] = falha('mês fechado');
    await expect(updateReceivableFromSO('os1', 1200)).rejects.toThrow('Não consegui atualizar a conta da OS: mês fechado');
  });

  it('total abaixo do que já foi pago continua bloqueado', async () => {
    banco.respostas['receivables.select'] = ok([
      { id: 'r1', amount: 1000, paid_amount: 1000, balance_amount: 0, status: 'paid', is_deposit: false, due_date: '2026-10-10' },
    ]);
    await expect(updateReceivableFromSO('os1', 500)).rejects.toBeInstanceOf(GrandTotalBelowPaidError);
  });
});

describe('reopenServiceOrder', () => {
  it('recusa reabrir quando há pagamento que veio do extrato (forma A)', async () => {
    banco.respostas['service_orders.select'] = ok({ status: 'invoiced' });
    banco.respostas['receivables.select'] = ok([{ id: 'r1', amount: 1000, paid_amount: 1000, status: 'paid' }]);
    banco.respostas['payments.select'] = ok([{ id: 'p1' }]);
    await expect(reopenServiceOrder('os1', 'ajuste')).rejects.toThrow(/veio do extrato/);
    expect(gravacoes('payments')).toEqual([]);
    expect(gravacoes('bank_transactions')).toEqual([]);
  });

  it('sem pagamento do extrato: estorna os pagamentos à mão e reabre, sem tocar em linha do banco', async () => {
    banco.respostas['service_orders.select'] = ok({ status: 'completed' });
    banco.respostas['receivables.select'] = ok([{ id: 'r1', amount: 1000, paid_amount: 1000, status: 'paid' }]);
    banco.respostas['payments.select'] = [ok([]), ok([{ id: 'p1', amount: 1000 }])];
    await reopenServiceOrder('os1', 'ajuste');
    expect(gravacoes('payments')[0].valores).toMatchObject({ status: 'cancelled' });
    expect(gravacoes('receivables')[0].valores).toMatchObject({ status: 'pending', paid_amount: 0 });
    expect(gravacoes('service_orders')[0].valores).toMatchObject({ status: 'completed' });
    expect(gravacoes('bank_transactions')).toEqual([]);
  });

  it('só reabre OS faturada ou concluída', async () => {
    banco.respostas['service_orders.select'] = ok({ status: 'open' });
    await expect(reopenServiceOrder('os1', 'x')).rejects.toThrow('Só é possível reabrir');
  });
});

describe('cancelPaymentCascade', () => {
  it('pagamento de Pix: passa pelo desfazer_aplicacao do banco e não solta a linha à mão', async () => {
    banco.respostas['payments.select'] = [
      ok({ id: 'p1', amount: 2520, receivable_id: 'r77', payable_id: null, bank_transaction_id: 'btL' }),
      ok({ status: 'cancelled' }),
    ];
    banco.respostas['rpc.desfazer_aplicacao'] = ok({ ok: true });
    await cancelPaymentCascade('p1', 'estorno');
    expect(banco.chamadas.some((c) => c.alvo === 'rpc.desfazer_aplicacao')).toBe(true);
    expect(gravacoes('bank_transactions')).toEqual([]);
    expect(gravacoes('payments')).toEqual([]);
  });

  it('pagamento à mão ligado ao Pix: o banco só desliga, e o estorno segue', async () => {
    banco.respostas['payments.select'] = [
      ok({ id: 'p1', amount: 500, receivable_id: 'r1', payable_id: null, bank_transaction_id: 'bt1' }),
      ok({ status: 'confirmed' }),
      ok([]),
    ];
    banco.respostas['rpc.desfazer_aplicacao'] = ok({ ok: true });
    banco.respostas['receivables.select'] = ok({ amount: 500 });
    await cancelPaymentCascade('p1', 'estorno');
    expect(gravacoes('payments')[0].valores).toMatchObject({ status: 'cancelled' });
    expect(gravacoes('receivables')[0].valores).toMatchObject({ status: 'pending', paid_amount: 0, balance_amount: 500 });
  });

  it('erro do desfazer_aplicacao pára o estorno', async () => {
    banco.respostas['payments.select'] = ok({ id: 'p1', amount: 500, receivable_id: 'r1', payable_id: null, bank_transaction_id: 'bt1' });
    banco.respostas['rpc.desfazer_aplicacao'] = falha('O mês 09/2026 está fechado');
    await expect(cancelPaymentCascade('p1', 'x')).rejects.toThrow('O mês 09/2026 está fechado');
    expect(gravacoes('payments')).toEqual([]);
  });
});

describe('recalcReceivableBalance', () => {
  it('pago, parcial e pendente pelo que foi pago de verdade', async () => {
    banco.respostas['payments.select'] = ok([{ amount: 300 }, { amount: 200 }]);
    banco.respostas['receivables.select'] = ok({ amount: 1000 });
    await recalcReceivableBalance('r1');
    expect(gravacoes('receivables')[0].valores).toEqual({ paid_amount: 500, balance_amount: 500, status: 'partially_paid' });
  });
});
