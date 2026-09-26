// Saldo de cada conta: banco pelo que o banco informou; Caixa pela base + lançado.
import { describe, it, expect } from 'vitest';
import { montarSaldos } from './use-saldo-das-contas';

const conexoes = [
  { id: 'c6', label: 'C6 - Conta PJ HBR', provider: 'pluggy', active: true, saldo_base: 5950.51 },
  { id: 'nu', label: 'Nubank PJ HBR', provider: 'pluggy', active: true, saldo_base: 0.89 },
  { id: 'cx', label: 'Caixa (dinheiro)', provider: 'caixa', active: true, saldo_base: 0 },
  { id: 'velha', label: 'Conta desativada', provider: 'pluggy', active: false, saldo_base: 0 },
];

describe('montarSaldos', () => {
  it('banco usa a ÚLTIMA conferência; Caixa soma as linhas; desativada não entra', () => {
    const r = montarSaldos(conexoes, [
      { bank_connection_id: 'c6', conferido_em: '2026-09-25T09:00:00Z', saldo_do_provedor: 1386.61, diferenca: -11553.7, fecha: false },
      { bank_connection_id: 'c6', conferido_em: '2026-09-25T21:00:14Z', saldo_do_provedor: 3246.61, diferenca: 0, fecha: true },
    ], [
      { amount: 100, transaction_type: 'debit', tx_status: null, dismissed_kind: null },
    ]);
    const c6 = r.contas.find((c) => c.id === 'c6')!;
    expect(c6.saldo).toBe(3246.61);
    expect(c6.confere).toBe(true);
    const nu = r.contas.find((c) => c.id === 'nu')!;
    expect(nu.saldo).toBeNull();
    expect(nu.confere).toBeNull();
    const cx = r.contas.find((c) => c.id === 'cx')!;
    expect(cx.saldo).toBe(-100);
    expect(cx.contado).toBe(false);
    expect(r.contas.map((c) => c.id)).toEqual(['c6', 'nu', 'cx']);
    expect(r.disponivel).toBe(3146.61);
  });

  it('a contagem conta no saldo do Caixa e marca como contado; duplicata e pendente não', () => {
    const r = montarSaldos(conexoes, [], [
      { amount: 100, transaction_type: 'debit', tx_status: null, dismissed_kind: null },
      { amount: 740, transaction_type: 'credit', tx_status: null, dismissed_kind: 'ajuste_caixa' },
      { amount: 50, transaction_type: 'debit', tx_status: null, dismissed_kind: 'duplicata' },
      { amount: 30, transaction_type: 'debit', tx_status: 'PENDING', dismissed_kind: null },
    ]);
    const cx = r.contas.find((c) => c.id === 'cx')!;
    expect(cx.saldo).toBe(640);
    expect(cx.contado).toBe(true);
  });

  it('contagem que bateu (sem linha de ajuste) também conta como contado', () => {
    const r = montarSaldos(conexoes, [], [], true);
    expect(r.contas.find((c) => c.id === 'cx')!.contado).toBe(true);
  });
});
