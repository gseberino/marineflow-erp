// A previsão de caixa (useCashForecast) e o que ela conta como entrada das contas a receber (cobrança, fatia 6 —
// 27/11/2026). Casos do dado real do dia: Nelson (Pix maior que a conta, no Extrato), César (5.000 de 8.178,60 no
// Extrato), Lírio (vencida há 128 dias), Rodrigo (vence 19/12). Antes, as três vencidas entravam inteiras nesta semana.
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';

const { tabelas, extrato } = vi.hoisted(() => ({
  tabelas: {} as Record<string, unknown[]>,
  extrato: { ler: (async () => []) as () => Promise<unknown[]> },
}));

// Cada consulta devolve a tabela inteira: os filtros são do banco; aqui só a regra da previsão importa.
vi.mock('@/integrations/supabase/client', () => {
  const consulta = (tabela: string) => {
    const resposta = () => ({ data: tabelas[tabela] ?? [], error: null });
    const q: Record<string, unknown> = {};
    for (const m of ['select', 'not', 'lte', 'gte', 'eq', 'neq', 'in', 'order', 'range', 'is']) q[m] = () => q;
    q.maybeSingle = async () => ({ data: null, error: null });
    q.then = (ok: (v: unknown) => unknown, falha?: (e: unknown) => unknown) => Promise.resolve(resposta()).then(ok, falha);
    return q;
  };
  return { supabase: { from: consulta } };
});
vi.mock('@/lib/previsao-de-caixa', async (original) => ({
  ...(await original<typeof import('@/lib/previsao-de-caixa')>()),
  lerDinheiroEsperando: () => extrato.ler(),
}));

import { useCashForecast } from './use-financial';

const conta = (id: string, client_id: string, due_date: string, balance_amount: number) => ({ id, client_id, due_date, balance_amount });

function previsao() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const envolve = ({ children }: { children: ReactNode }) => <QueryClientProvider client={qc}>{children}</QueryClientProvider>;
  return renderHook(() => useCashForecast(8), { wrapper: envolve });
}

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(new Date('2026-11-27T12:00:00-03:00'));
  for (const k of Object.keys(tabelas)) delete tabelas[k];
  tabelas.receivables = [
    conta('nelson-1', 'nelson', '2026-11-14', 2110.06),
    conta('cesar-1', 'cesar', '2026-11-17', 8178.6),
    conta('lirio-1', 'lirio', '2026-07-22', 756),
    conta('rodrigo-1', 'rodrigo', '2026-12-19', 628.9),
  ];
  extrato.ler = async () => [
    { clienteId: 'nelson', valor: 2800, data: '2026-11-13', titulo: 'Pix Nelson', contaId: 'nelson-1', pelaConta: true },
    { clienteId: 'cesar', valor: 5000, data: '2026-11-18', titulo: 'Pix César', contaId: null, pelaConta: false },
  ];
});
afterEach(() => { vi.useRealTimers(); });

describe('useCashForecast — o que entra das contas a receber', () => {
  it('o dinheiro já no banco e o vencido há mais de 90 dias saem das entradas e ficam à parte', async () => {
    const { result } = previsao();
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    const r = result.current.data!;
    // esta semana: só o que falta do César (8.178,60 − 5.000,00); antes eram 2.110,06 + 8.178,60 + 756,00 = 11.044,66
    expect(r.weeks[0].entradas).toBe(3178.6);
    expect(r.weeks[0].contemAtrasados).toBe(true);
    // o Rodrigo entra na semana de 19/12, inteiro
    expect(r.weeks.find((w) => w.inicio === '2026-12-14')?.entradas).toBe(628.9);
    expect(r.totalEntradas).toBeCloseTo(3807.5, 2);
    expect(r.extras.aReceber).toEqual({ noBanco: { total: 7110.06, contas: 2 }, antigas: { total: 756, contas: 1 } });
    expect(r.extras.avisos.join(' ')).not.toContain('Extrato');
  });

  it('o Extrato que não se lê não derruba a previsão: conta a conta inteira, com o aviso; o vencido antigo segue fora', async () => {
    extrato.ler = async () => { throw new Error('permissão negada'); };
    const { result } = previsao();
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    const r = result.current.data!;
    expect(r.weeks[0].entradas).toBe(10288.66);
    expect(r.extras.aReceber).toEqual({ noBanco: { total: 0, contas: 0 }, antigas: { total: 756, contas: 1 } });
    expect(r.extras.avisos).toContain(
      'Não consegui ler as entradas que esperam no Extrato (permissão negada): o que já entrou no banco pode estar contado de novo nas entradas.',
    );
  });
});
