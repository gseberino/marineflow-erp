// O sino: leitura que falha não vira "Nenhuma notificação" calada (19/11/2026).
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createElement, type ReactNode } from 'react';
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

vi.mock('@/integrations/supabase/client', async () => ({ supabase: (await import('@/test/banco-falso')).supabaseFalso }));
vi.mock('@/hooks/use-auth', () => ({ useAuth: () => ({ user: { id: 'u1', role: 'admin' } }) }));

import { useNotifications } from './use-notifications';
import { banco, ok, falha, reiniciarBanco } from '@/test/banco-falso';

function montar() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const wrapper = ({ children }: { children: ReactNode }) => createElement(QueryClientProvider, { client: qc }, children);
  return renderHook(() => useNotifications(), { wrapper });
}

beforeEach(() => reiniciarBanco());

describe('useNotifications', () => {
  it('contas em atraso ilegíveis: marca a lista como incompleta', async () => {
    banco.respostas['receivables.select'] = falha('timeout');
    const { result } = montar();
    await waitFor(() => expect(result.current.isLoading).toBe(false));
    await waitFor(() => expect(result.current.incompleto).toBe(true));
  });

  it('lembretes do banco ilegíveis: marca a lista como incompleta', async () => {
    banco.respostas['app_notifications.select'] = falha('timeout');
    const { result } = montar();
    await waitFor(() => expect(result.current.incompleto).toBe(true));
  });

  it('tudo lido: não é incompleta', async () => {
    banco.respostas['receivables.select'] = ok([{ id: 'r1', balance_amount: 10, due_date: '2026-01-01', clients: { name: 'Ana' } }]);
    const { result } = montar();
    await waitFor(() => expect(result.current.notifications.some((n) => n.id === 'overdue:r1')).toBe(true));
    expect(result.current.incompleto).toBe(false);
  });
});
