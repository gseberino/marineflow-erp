// Retorno F5 (P12.1): marcar perdido pela tela sempre leva o motivo (3.4: "rejeitado" = perdido, e sempre tem motivo).
// Sem motivo, o gancho lança antes de chamar o banco; com ele, o update leva o motivo, quem marcou ('tela') e a nota, e o
// registro de auditoria leva o motivo. As outras transições são as de antes.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';
import { useUpdateQuoteStatus } from './use-service-orders';

const banco = vi.hoisted(() => ({ updates: [] as unknown[], auditoria: [] as unknown[] }));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: () => ({
      update: (v: unknown) => {
        banco.updates.push(v);
        return { eq: () => ({ select: () => ({ single: async () => ({ data: { id: 'so-1' }, error: null }) }) }) };
      },
    }),
  },
}));
vi.mock('@/hooks/use-audit-log', () => ({ writeAuditLog: async (v: unknown) => { banco.auditoria.push(v); } }));

const wrapper = ({ children }: { children: ReactNode }) => (
  <QueryClientProvider client={new QueryClient({ defaultOptions: { mutations: { retry: false } } })}>{children}</QueryClientProvider>
);

beforeEach(() => {
  banco.updates.length = 0;
  banco.auditoria.length = 0;
});

describe('useUpdateQuoteStatus com o motivo da perda (F5)', () => {
  it('rejected sem motivo lança antes de chamar o banco', async () => {
    const { result } = renderHook(() => useUpdateQuoteStatus(), { wrapper });
    await expect(result.current.mutateAsync({ id: 'so-1', quoteStatus: 'rejected' })).rejects.toThrow(/motivo/i);
    await expect(result.current.mutateAsync({ id: 'so-1', quoteStatus: 'rejected', motivoPerda: 'sem_motivo_antigo' })).rejects.toThrow(/motivo/i);
    expect(banco.updates).toEqual([]);
  });

  it('rejected com motivo grava o motivo, quem marcou (tela) e a nota; a auditoria leva o motivo', async () => {
    const { result } = renderHook(() => useUpdateQuoteStatus(), { wrapper });
    await result.current.mutateAsync({ id: 'so-1', quoteStatus: 'rejected', motivoPerda: 'fechou_com_outro', notaPerda: '  fechou com a concorrente  ' });
    expect(banco.updates).toEqual([{
      quote_status: 'rejected', motivo_perda: 'fechou_com_outro', motivo_perda_por: 'tela', motivo_perda_nota: 'fechou com a concorrente',
    }]);
    expect(banco.auditoria[0]).toMatchObject({ new_value: { quote_status: 'rejected', motivo_perda: 'fechou_com_outro' } });
    // sem nota: nula; nota acima de 200 caracteres é cortada
    await result.current.mutateAsync({ id: 'so-1', quoteStatus: 'rejected', motivoPerda: 'preco' });
    expect(banco.updates[1]).toEqual({ quote_status: 'rejected', motivo_perda: 'preco', motivo_perda_por: 'tela', motivo_perda_nota: null });
    await result.current.mutateAsync({ id: 'so-1', quoteStatus: 'rejected', motivoPerda: 'outro', notaPerda: 'x'.repeat(300) });
    expect(String((banco.updates[2] as Record<string, unknown>).motivo_perda_nota).length).toBe(200);
  });

  it('as outras transições são as de antes: só o status, e a auditoria de sempre', async () => {
    const { result } = renderHook(() => useUpdateQuoteStatus(), { wrapper });
    await result.current.mutateAsync({ id: 'so-1', quoteStatus: 'sent' });
    await result.current.mutateAsync({ id: 'so-1', quoteStatus: 'draft', motivoPerda: 'preco' });
    expect(banco.updates).toEqual([{ quote_status: 'sent' }, { quote_status: 'draft' }]);
    expect(banco.auditoria[0]).toMatchObject({ new_value: { quote_status: 'sent' } });
  });
});
