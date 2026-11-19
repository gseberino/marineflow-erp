// Despesas da OS: leitura que falha não grava operational_cost_total = 0 (19/11/2026).
import { beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('@/integrations/supabase/client', async () => ({ supabase: (await import('@/test/banco-falso')).supabaseFalso }));
const recalcTotals = vi.hoisted(() => vi.fn(async (_id: string) => {}));
vi.mock('@/hooks/use-service-orders', () => ({ recalcTotals: (id: string) => recalcTotals(id) }));

import { recalcExpenseTotals } from './use-service-order-expenses';
import { banco, ok, falha, reiniciarBanco, chamadasA } from '@/test/banco-falso';

beforeEach(() => { reiniciarBanco(); recalcTotals.mockClear(); });

describe('recalcExpenseTotals', () => {
  it('leitura das despesas falha: lança e não grava custo zero', async () => {
    banco.respostas['service_order_expenses.select'] = falha('timeout');
    await expect(recalcExpenseTotals('so1')).rejects.toThrow(/despesas da OS/);
    expect(chamadasA('service_orders.update')).toHaveLength(0);
    expect(recalcTotals).not.toHaveBeenCalled();
  });

  it('só as faturáveis entram no custo operacional', async () => {
    banco.respostas['service_order_expenses.select'] = ok([
      { amount: 100, billable_to_client: true },
      { amount: 40.5, billable_to_client: null },
      { amount: 999, billable_to_client: false },
    ]);
    await recalcExpenseTotals('so1');
    expect(chamadasA('service_orders.update')[0].valores).toEqual({ operational_cost_total: 140.5 });
    expect(recalcTotals).toHaveBeenCalledWith('so1');
  });

  it('gravação do custo falha: lança e não recalcula o total', async () => {
    banco.respostas['service_order_expenses.select'] = ok([]);
    banco.respostas['service_orders.update'] = falha('rls');
    await expect(recalcExpenseTotals('so1')).rejects.toThrow(/custo operacional/);
    expect(recalcTotals).not.toHaveBeenCalled();
  });
});
