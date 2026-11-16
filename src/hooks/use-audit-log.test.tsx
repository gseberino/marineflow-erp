// A listagem genérica de auditoria e o histórico curto de um registro diante das linhas do histórico de documentos
// (16/11/2026): a linha 'versao' guarda o documento inteiro em new_value — a listagem sem filtro a deixa de fora, o filtro
// explícito por 'versao' ainda traz, e o histórico curto não baixa previous_value/new_value.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';

const h = vi.hoisted(() => ({ chamadas: [] as Array<[string, unknown[]]> }));

vi.mock('@/integrations/supabase/client', () => {
  const q: Record<string, unknown> = {};
  for (const m of ['select', 'order', 'limit', 'eq', 'neq', 'gte', 'lte']) {
    q[m] = (...a: unknown[]) => { h.chamadas.push([m, a]); return q; };
  }
  q.then = (ok: (v: unknown) => unknown) => Promise.resolve({ data: [], error: null }).then(ok);
  return { supabase: { from: (t: string) => { h.chamadas.push(['from', [t]]); return q; } } };
});
vi.mock('@/lib/diagnostics', () => ({ logError: vi.fn() }));

import { useAuditLog, useRecordHistory } from './use-audit-log';

function envolver() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return ({ children }: { children: ReactNode }) => <QueryClientProvider client={qc}>{children}</QueryClientProvider>;
}

beforeEach(() => { h.chamadas = []; });

describe('useAuditLog e a linha versao', () => {
  it('sem filtro de ação: deixa a versao de fora', async () => {
    const { result } = renderHook(() => useAuditLog({}), { wrapper: envolver() });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(h.chamadas).toContainEqual(['neq', ['action', 'versao']]);
    expect(h.chamadas.some(([m, a]) => m === 'eq' && a[0] === 'action')).toBe(false);
  });

  it('filtro explícito por versao (ou outra ação): traz o que foi pedido, sem o neq', async () => {
    for (const acao of ['versao', 'insert']) {
      h.chamadas = [];
      const { result } = renderHook(() => useAuditLog({ action: acao }), { wrapper: envolver() });
      await waitFor(() => expect(result.current.isSuccess).toBe(true));
      expect(h.chamadas).toContainEqual(['eq', ['action', acao]]);
      expect(h.chamadas.some(([m]) => m === 'neq')).toBe(false);
    }
  });

  it('histórico curto de um registro: sem previous_value/new_value', async () => {
    const { result } = renderHook(() => useRecordHistory('clients', 'c1'), { wrapper: envolver() });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    const select = h.chamadas.find(([m]) => m === 'select');
    expect(String(select?.[1][0])).not.toMatch(/\*|new_value|previous_value/);
    expect(String(select?.[1][0])).toMatch(/action/);
  });
});
