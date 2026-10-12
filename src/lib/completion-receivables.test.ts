// A OS concluída não pode cobrar de novo o que o sinal já quitou.
//
// Caso real, medido em 24/09/2026: três OS com título em dobro e R$ 2.956,88 sendo
// cobrados de quem não devia. Em todas, a condição era 100% na aprovação ("À vista"): o
// cliente pagava o sinal — que cobre o valor inteiro — e segundos depois nascia um gêmeo
// pendente pelo mesmo valor.
//
// A causa era a checagem de idempotência ignorar o sinal (`is_deposit = true`). Com saldo
// ela funcionava (o saldo é não-depósito e era encontrado); sem saldo, não encontrava nada
// e gerava o plano todo outra vez.
import { describe, it, expect, vi, beforeEach } from 'vitest';

const { fromMock, inserted } = vi.hoisted(() => ({
  fromMock: vi.fn(),
  inserted: [] as unknown[],
}));

vi.mock('@/integrations/supabase/client', () => ({ supabase: { from: fromMock } }));

import { ensureCompletionReceivables } from './completion-receivables';

/** A OS de 500 reais com condição "À vista" — o formato da OS-00075. */
const OS = {
  id: 'os-1', client_id: 'c1', service_order_number: 'OS-00075', grand_total: 500,
  labor_cost_total: 500, parts_cost_total: 0, operational_cost_total: 0,
  travel_cost_total: 0, subcontract_cost_total: 0, is_travel_billable: true,
  discount_amount: 0, tax_amount: 0,
  payment_condition_preset_id: 'p-avista', custom_payment_installments: null,
};

const PRESET_AVISTA = {
  installments: [
    { label: 'À vista', services_pct: 100, parts_pct: 100, expenses_pct: 100, days_after_approval: 0, tipo: 'aprovacao' },
  ],
};

/**
 * Um supabase de mentira, com só o que esta função usa. `recebiveis` é o que a consulta de
 * idempotência devolve — é a variável do teste.
 */
function montarSupabase(recebiveis: unknown[], os: Record<string, unknown> = OS) {
  inserted.length = 0;
  fromMock.mockImplementation((tabela: string) => {
    if (tabela === 'service_orders') {
      const q: any = {};
      for (const k of ['select', 'eq']) q[k] = () => q;
      q.maybeSingle = () => Promise.resolve({ data: os });
      return q;
    }
    if (tabela === 'payment_condition_presets') {
      const q: any = {};
      for (const k of ['select', 'eq']) q[k] = () => q;
      q.maybeSingle = () => Promise.resolve({ data: PRESET_AVISTA });
      return q;
    }
    // receivables
    const q: any = {};
    for (const k of ['select', 'eq', 'neq']) q[k] = () => q;
    q.then = (res: any) => Promise.resolve({ data: recebiveis, error: null }).then(res);
    q.insert = (linhas: unknown[]) => {
      inserted.push(...(Array.isArray(linhas) ? linhas : [linhas]));
      return Promise.resolve({ error: null });
    };
    return q;
  });
}

beforeEach(() => fromMock.mockReset());

describe('recebíveis da OS concluída', () => {
  it('sinal pago que cobre tudo NÃO gera um segundo título', async () => {
    // Exatamente a OS-00075: só o "Sinal — ORÇ-00075", pago, e nenhum saldo.
    montarSupabase([{ id: 'r-sinal' }]);
    const r = await ensureCompletionReceivables({ serviceOrderId: 'os-1', completionDate: '2026-08-13' });
    expect(r).toEqual({ created: 0, skipped: true });
    expect(inserted).toHaveLength(0);
  });

  it('OS sem recebível nenhum gera o plano, como antes', async () => {
    montarSupabase([]);
    const r = await ensureCompletionReceivables({ serviceOrderId: 'os-1', completionDate: '2026-08-13' });
    expect(r.created).toBe(1);
    expect((inserted[0] as Record<string, unknown>).amount).toBe(500);
  });

  it('título cancelado não conta como financeiro existente', async () => {
    // A consulta filtra status <> 'cancelled'; se sobrou só lixo cancelado, o plano nasce.
    montarSupabase([]);
    const r = await ensureCompletionReceivables({ serviceOrderId: 'os-1', completionDate: '2026-08-13' });
    expect(r.created).toBe(1);
  });
});

describe('descrição do título único (OS sem condição de parcelamento)', () => {
  // O número já vem com o prefixo ("OS-00075"). Até 11/10/2026 a descrição era
  // `OS ${número}` e gravava "OS OS-00075" no recebível (1 caso deste código no banco).
  const SEM_CONDICAO = { ...OS, payment_condition_preset_id: null, custom_payment_installments: null };

  it('é o número da OS, sem "OS " repetido', async () => {
    montarSupabase([], SEM_CONDICAO);
    const r = await ensureCompletionReceivables({ serviceOrderId: 'os-1', completionDate: '2026-08-13' });
    expect(r).toEqual({ created: 1, skipped: false });
    const titulo = inserted[0] as Record<string, unknown>;
    expect(titulo.description).toBe('OS-00075');
    expect(String(titulo.description)).not.toContain('OS OS-');
    expect(titulo.amount).toBe(500);
  });

  it('orçamento virado OS mantém o próprio prefixo (ORÇ-)', async () => {
    montarSupabase([], { ...SEM_CONDICAO, service_order_number: 'ORÇ-00112' });
    await ensureCompletionReceivables({ serviceOrderId: 'os-1', completionDate: '2026-08-13' });
    expect((inserted[0] as Record<string, unknown>).description).toBe('ORÇ-00112');
  });
});
