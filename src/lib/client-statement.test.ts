import { describe, it, expect } from 'vitest';
import { buildClientStatement } from './client-statement';

const ITEMS = [
  { description: 'Sinal — OS-00060', due_date: '2026-07-27', status: 'paid', amount: 18001.04, balance_amount: 0 },
  { description: 'Saldo — OS-00060', due_date: '2026-08-26', status: 'pending', amount: 1998.96, balance_amount: 1998.96 },
  { description: 'OS-00051', due_date: '2026-07-23', status: 'overdue', amount: 1710, balance_amount: 1710 },
  { description: 'Cancelado', due_date: '2026-07-01', status: 'cancelled', amount: 999, balance_amount: 999 },
];

describe('buildClientStatement', () => {
  it('lista lançamentos, ignora cancelados e soma os totais corretos', () => {
    const s = buildClientStatement({ clientName: 'Charline Souza', items: ITEMS });
    expect(s).toContain('Charline'); // só primeiro nome
    expect(s).toContain('Sinal — OS-00060');
    expect(s).toContain('Saldo — OS-00060');
    expect(s).not.toContain('Cancelado'); // cancelado fora
    // total = 18001,04 + 1.998,96 + 1.710 = 21.710,00 ; pago = 18.001,04 ; aberto = 1.998,96 + 1.710 = 3.708,96
    expect(s).toContain('21.710,00');
    expect(s).toContain('18.001,04');
    expect(s).toContain('3.708,96');
  });

  it('inclui Pix só quando há saldo em aberto', () => {
    const comAberto = buildClientStatement({ clientName: 'A', items: ITEMS, pixKey: 'hbr@pix' });
    expect(comAberto).toContain('hbr@pix');
    const soPago = buildClientStatement({
      clientName: 'A', pixKey: 'hbr@pix',
      items: [{ description: 'X', status: 'paid', amount: 100, balance_amount: 0 }],
    });
    expect(soPago).not.toContain('hbr@pix');
  });
});
