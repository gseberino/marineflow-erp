// O "Entrou no mês" do painel inicial: pelo extrato e comparado com o MESMO trecho do mês
// anterior (revisão de 27/09/2026).
import { describe, it, expect, vi } from 'vitest';

vi.mock('@/integrations/supabase/client', () => ({ supabase: {} }));

import { entrouNoMesPeloExtrato } from './use-dashboard';
import type { LinhaDoFluxo } from '@/lib/fluxo-de-caixa';

const entrada = (id: string, data: string, valor: number, extra: Partial<LinhaDoFluxo> = {}): LinhaDoFluxo => ({
  id, transaction_date: data, amount: valor, transaction_type: 'credit', source_type: 'bank',
  provider: 'pluggy', bank_connection_id: 'c6', dismissed_kind: null, tx_status: 'POSTED', ...extra,
});

describe('Entrou no mês do painel', () => {
  it('compara com o mês anterior só até o mesmo dia', () => {
    const r = entrouNoMesPeloExtrato([
      entrada('a', '2026-09-03', 1000),
      entrada('b', '2026-08-02', 700),
      entrada('c', '2026-08-20', 5000), // depois do dia 10 de agosto: não entra na comparação
    ], '2026-09-10');
    expect(r).toEqual({ esteMes: 1000, mesmoTrechoDoAnterior: 700 });
  });

  it('dia 31 compara com o último dia de um mês mais curto', () => {
    const r = entrouNoMesPeloExtrato([
      entrada('a', '2026-02-28', 300),
      entrada('b', '2026-03-31', 400),
    ], '2026-03-31');
    expect(r).toEqual({ esteMes: 400, mesmoTrechoDoAnterior: 300 });
  });

  it('usa a regra do extrato: duplicata e transferência pareada não entram', () => {
    const r = entrouNoMesPeloExtrato([
      entrada('a', '2026-09-03', 1000),
      entrada('d', '2026-09-03', 1000, { dismissed_kind: 'duplicata' }),
      entrada('t1', '2026-09-04', 2900, { dismissed_kind: 'transferencia', bank_connection_id: 'nubank' }),
      { ...entrada('t2', '2026-09-04', 2900, { dismissed_kind: 'transferencia' }), transaction_type: 'debit' },
    ], '2026-09-10');
    expect(r.esteMes).toBe(1000);
  });

  it('janeiro compara com dezembro do ano anterior', () => {
    const r = entrouNoMesPeloExtrato([entrada('a', '2025-12-05', 90), entrada('b', '2026-01-04', 10)], '2026-01-05');
    expect(r).toEqual({ esteMes: 10, mesmoTrechoDoAnterior: 90 });
  });
});
