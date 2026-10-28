import { describe, it, expect } from 'vitest';
import { buildClientStatement } from './client-statement';
import { PARIDADE_COBRAR_JUNTAS as P } from '../../supabase/functions/_shared/receivables/cobrar-juntas_paridade';

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

// "Cobrar juntas" (Fase 0, 28/10/2026). Caso medido: MP MOTOR HOMES, OS-00045 (R$ 1.650) + OS-00046
// (R$ 20 de saldo, R$ 30 já pagos) = R$ 1.670 em aberto, vencido desde 22/07. A mensagem antiga dizia
// "Pago R$ 0", mostrava o valor cheio de cada conta e chamava de "a vencer".
const MP = [
  { service_order_id: 'os45', numero_os: 'OS-00045', description: 'Sinal', status: 'paid', amount: 500, paid_amount: 500, balance_amount: 0, due_date: '2026-06-01' },
  { service_order_id: 'os45', numero_os: 'OS-00045', description: 'Saldo', status: 'pending', amount: 1650, paid_amount: 0, balance_amount: 1650, due_date: '2026-07-22' },
  { service_order_id: 'os46', numero_os: 'OS-00046', description: 'Saldo', status: 'partially_paid', amount: 50, paid_amount: 30, balance_amount: 20, due_date: '2026-07-22' },
  { service_order_id: 'os46', numero_os: 'OS-00046', description: 'Anulada', status: 'cancelled', amount: 999, paid_amount: 0, balance_amount: 999, due_date: '2026-07-01' },
  { service_order_id: 'os99', numero_os: 'OS-00099', description: 'Outra OS', status: 'pending', amount: 300, paid_amount: 0, balance_amount: 300, due_date: '2026-11-30' },
];

describe('buildClientStatement — números certos', () => {
  it('cada linha mostra o saldo; Pago soma o pago parcial; Total − Pago = Em aberto', () => {
    const s = buildClientStatement({ clientName: 'MP Motor Homes', items: MP, hoje: '2026-10-28' });
    // A linha da OS-00046 mostra o saldo (R$ 20) como valor, e o cheio (R$ 50) só entre parênteses.
    expect(s).toMatch(/OS-00046 · Saldo · vence 22\/07\/2026 · vencido: \*R\$\s20,00\* \(de R\$\s50,00\)/);
    // Total 500 + 1650 + 50 + 300 = 2.500 ; Pago 500 + 30 = 530 ; Em aberto 1650 + 20 + 300 = 1.970.
    expect(s).toMatch(/Total: R\$\s2\.500,00/);
    expect(s).toMatch(/Pago: R\$\s530,00/);
    expect(s).toMatch(/Em aberto: R\$\s1\.970,00/);
    expect(s).not.toContain('Anulada');
  });

  it('"vencido" é calculado pela data, mesmo com status pending', () => {
    const s = buildClientStatement({ clientName: 'MP', items: MP, hoje: '2026-10-28' });
    expect(s).toMatch(/OS-00045 · Saldo · vence 22\/07\/2026 · vencido/);
    expect(s).toMatch(/OS-00099 · Outra OS · vence 30\/11\/2026 · a vencer/);
    const antes = buildClientStatement({ clientName: 'MP', items: MP, hoje: '2026-07-01' });
    expect(antes).toMatch(/OS-00045 · Saldo · vence 22\/07\/2026 · a vencer/);
  });

  it('filtro por OS: só as contas abertas das OS escolhidas, sem o sinal já pago', () => {
    const s = buildClientStatement({ clientName: 'MP', items: MP, servicoIds: ['os45', 'os46'], pixKey: 'hbr@pix', hoje: '2026-10-28' });
    expect(s).toContain('Cobrança — HBR');
    expect(s).toContain('OS: OS-00045, OS-00046');
    expect(s).not.toContain('Sinal');
    expect(s).not.toContain('OS-00099');
    // Total 1650 + 50 = 1.700 ; Pago 30 ; Em aberto 1.670 (o número da MP medido em produção).
    expect(s).toMatch(/Total: R\$\s1\.700,00/);
    expect(s).toMatch(/Pago: R\$\s30,00/);
    expect(s).toMatch(/Em aberto: R\$\s1\.670,00/);
    expect(s).toContain('hbr@pix');
  });

  it('filtro sem nada em aberto não inventa linha nem Pix', () => {
    const s = buildClientStatement({ clientName: 'MP', items: MP, servicoIds: ['os-inexistente'], pixKey: 'hbr@pix' });
    expect(s).toContain('_Sem lançamentos._');
    expect(s).not.toContain('hbr@pix');
  });

  it('paridade com o assistente: o mesmo caso fixo dá a MESMA mensagem da tool cobrar_juntas', () => {
    // Conta de outra OS do cliente, não escolhida: não entra (o diálogo passa todas as contas da ficha).
    const outra = { id: 'p99', service_order_id: 'os-99', numero_os: 'OS-00099', description: 'Outra', amount: 70, paid_amount: 0, balance_amount: 70, status: 'pending', due_date: '2026-08-01' };
    const s = buildClientStatement({
      clientName: P.clienteNome, items: [...P.contas, outra], pixKey: P.pixKey, hoje: P.hoje,
      servicoIds: P.os.map((o) => o.id),
    });
    expect(s).toBe(P.esperado);
  });
});
