// Leituras que falham na cotação não seguem como se tivessem lido "nada" (19/11/2026).
//  1. Enviar a cotação: o modo de teste do WhatsApp ilegível NÃO envia ao fornecedor.
//  2. Fechar com nota: as anotações ilegíveis NÃO são sobrescritas pela nota nova.
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createElement, type ReactNode } from 'react';
import { renderHook } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

vi.mock('@/integrations/supabase/client', async () => ({ supabase: (await import('@/test/banco-falso')).supabaseFalso }));
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn(), info: vi.fn() } }));

import { useSendQuoteRequest, useCloseQuoteRequest } from './use-quote-requests';
import { banco, ok, falha, reiniciarBanco, chamadasA } from '@/test/banco-falso';

function embrulho() {
  const qc = new QueryClient({ defaultOptions: { mutations: { retry: false }, queries: { retry: false } } });
  return ({ children }: { children: ReactNode }) => createElement(QueryClientProvider, { client: qc }, children);
}

beforeEach(() => reiniciarBanco());

describe('useSendQuoteRequest — modo de teste ilegível', () => {
  it('falha na leitura de app_settings: nada entra na fila do WhatsApp', async () => {
    banco.respostas['quote_requests.select'] = ok({ id: 'q1', code: 'COT-00001', sent_supplier_ids: ['s1'] });
    banco.respostas['quote_request_items.select'] = ok([{ position: 1, description: 'Bomba', quantity: 1 }]);
    banco.respostas['suppliers.select'] = ok([{ id: 's1', name: 'Fornecedor', phone: '5521999990000' }]);
    banco.respostas['app_settings.select'] = falha('timeout');
    const { result } = renderHook(() => useSendQuoteRequest(), { wrapper: embrulho() });
    await expect(result.current.mutateAsync({ quoteRequestId: 'q1' })).rejects.toThrow(/modo de teste/);
    expect(chamadasA('whatsapp_send_queue.insert')).toHaveLength(0);
  });
});

describe('useCloseQuoteRequest — anotações ilegíveis', () => {
  it('falha ao ler as notas: não grava (a nota antiga não é apagada)', async () => {
    banco.respostas['quote_requests.select'] = falha('timeout');
    const { result } = renderHook(() => useCloseQuoteRequest(), { wrapper: embrulho() });
    await expect(result.current.mutateAsync({ id: 'q1', note: 'comprado no balcão' })).rejects.toThrow(/anotações/);
    expect(chamadasA('quote_requests.update')).toHaveLength(0);
  });

  it('leitura ok: a nota nova entra depois da antiga', async () => {
    banco.respostas['quote_requests.select'] = ok({ notes: 'nota antiga' });
    const { result } = renderHook(() => useCloseQuoteRequest(), { wrapper: embrulho() });
    await result.current.mutateAsync({ id: 'q1', note: 'nova' });
    const upd = chamadasA('quote_requests.update');
    expect(upd).toHaveLength(1);
    expect((upd[0].valores as { notes: string }).notes).toBe('nota antiga\nnova');
  });
});
