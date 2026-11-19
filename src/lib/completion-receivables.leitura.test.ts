// Contas a receber da conclusão: leitura que falha PARA em vez de seguir com "nada" (19/11/2026).
import { beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('@/integrations/supabase/client', async () => ({ supabase: (await import('@/test/banco-falso')).supabaseFalso }));

import { ensureCompletionReceivables } from './completion-receivables';
import { banco, ok, falha, reiniciarBanco, chamadasA } from '@/test/banco-falso';

const OS = {
  id: 'os-1', client_id: 'c1', service_order_number: 'OS-00075', grand_total: 500,
  labor_cost_total: 500, parts_cost_total: 0, operational_cost_total: 0,
  travel_cost_total: 0, subcontract_cost_total: 0, is_travel_billable: true,
  discount_amount: 0, tax_amount: 0, payment_condition_preset_id: 'p1', custom_payment_installments: null,
};
const entrada = { serviceOrderId: 'os-1', completionDate: '2026-11-19' };

beforeEach(() => reiniciarBanco());

describe('ensureCompletionReceivables — leituras que falham', () => {
  it('OS ilegível: lança', async () => {
    banco.respostas['service_orders.select'] = falha('timeout');
    await expect(ensureCompletionReceivables(entrada)).rejects.toThrow(/ler a OS/);
    expect(chamadasA('receivables.insert')).toHaveLength(0);
  });

  it('contas existentes ilegíveis: lança e não cria (seria cobrança em dobro)', async () => {
    banco.respostas['service_orders.select'] = ok(OS);
    banco.respostas['receivables.select'] = falha('timeout');
    await expect(ensureCompletionReceivables(entrada)).rejects.toThrow(/já existem/);
    expect(chamadasA('receivables.insert')).toHaveLength(0);
  });

  it('condição de pagamento ilegível: lança e não cria à vista', async () => {
    banco.respostas['service_orders.select'] = ok(OS);
    banco.respostas['receivables.select'] = ok([]);
    banco.respostas['payment_condition_presets.select'] = falha('timeout');
    await expect(ensureCompletionReceivables(entrada)).rejects.toThrow(/condição de pagamento/);
    expect(chamadasA('receivables.insert')).toHaveLength(0);
  });
});
