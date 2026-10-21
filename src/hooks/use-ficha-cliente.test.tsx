// O saldo em aberto só é consultado para admin e financeiro (a RLS de receivables só deixa esses
// lerem). Para os outros cargos a consulta nem sai.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';

const estado = vi.hoisted(() => ({ cargo: 'admin' as string, tabelas: [] as string[] }));

vi.mock('@/hooks/use-auth', () => ({
  useOptionalAuth: () => ({ user: { role: estado.cargo } }),
}));
vi.mock('@/integrations/supabase/client', () => {
  const linhas = { data: [{ amount: 100, paid_amount: 0, balance_amount: 100, due_date: '2000-01-01', status: 'pending' }], error: null };
  const cadeia: Record<string, unknown> = {};
  for (const m of ['select', 'eq', 'not', 'order', 'limit']) cadeia[m] = () => cadeia;
  cadeia.then = (ok: (v: unknown) => unknown) => Promise.resolve(linhas).then(ok);
  return { supabase: { from: (t: string) => { estado.tabelas.push(t); return cadeia; } } };
});

import { useSaldoEmAberto } from './use-ficha-cliente';

function wrapper({ children }: { children: ReactNode }) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return <QueryClientProvider client={qc}>{children}</QueryClientProvider>;
}

describe('useSaldoEmAberto', () => {
  beforeEach(() => { estado.tabelas = []; });

  it('admin: consulta os recebíveis e resume', async () => {
    estado.cargo = 'admin';
    const { result } = renderHook(() => useSaldoEmAberto('c1'), { wrapper });
    await waitFor(() => expect(result.current.data).toEqual({ emAberto: 100, vencidos: 1, valorVencido: 100 }));
    expect(estado.tabelas).toEqual(['receivables']);
  });

  it.each(['technician', 'seller', 'external_seller'])('%s: a consulta nem sai', async (cargo) => {
    estado.cargo = cargo;
    const { result } = renderHook(() => useSaldoEmAberto('c1'), { wrapper });
    await new Promise((r) => setTimeout(r, 20));
    expect(result.current.fetchStatus).toBe('idle');
    expect(result.current.data).toBeUndefined();
    expect(estado.tabelas).toEqual([]);
  });
});
