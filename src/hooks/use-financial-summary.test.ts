// O resumo do Financeiro (A receber, A pagar, Entrou/Saiu no mês): uma falha ao ler o extrato
// apaga só os números do extrato (conferência de 27/09/2026 — derrubava o resumo inteiro, e
// Contas a Receber mostrava A receber R$ 0,00 sem aviso).
import { describe, it, expect, vi } from 'vitest';
import { createElement, type ReactNode } from 'react';
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const { carregar } = vi.hoisted(() => ({ carregar: vi.fn() }));

vi.mock('@/integrations/supabase/client', () => {
  const builder = (tabela: string): any => {
    const o: any = {};
    for (const k of ['select', 'not', 'lt', 'gt', 'gte', 'lte', 'eq', 'in', 'order', 'limit']) o[k] = () => o;
    const dados = tabela === 'receivables' ? [{ balance_amount: 1200 }, { balance_amount: 300 }] : [];
    o.then = (ok: any, erro: any) => Promise.resolve({ data: dados, error: null }).then(ok, erro);
    return o;
  };
  return { supabase: { from: (t: string) => builder(t) } };
});

vi.mock('@/hooks/use-fluxo-de-caixa', () => ({
  carregarFluxoDeCaixa: carregar,
  chaveDoFluxo: (n: number) => ['fluxo-de-caixa', n, 'atual'],
}));

import { useFinancialSummary } from './use-financial';

function renderResumo() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const wrapper = ({ children }: { children: ReactNode }) => createElement(QueryClientProvider, { client: qc }, children);
  return renderHook(() => useFinancialSummary(), { wrapper });
}

describe('resumo do Financeiro e o extrato', () => {
  it('falha do extrato (ex.: a função da raiz ainda não existe) não zera A receber', async () => {
    carregar.mockReset();
    carregar.mockRejectedValue(new Error('Could not find the function public.raiz_do_cnpj_da_empresa'));
    const { result } = renderResumo();
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(result.current.data).toMatchObject({
      total_receivable: 1500,
      entrou_no_mes: null,
      saiu_no_mes: null,
      erro_do_extrato: 'Could not find the function public.raiz_do_cnpj_da_empresa',
    });
  });

  it('com o extrato lido, os números do mês vêm dele', async () => {
    carregar.mockReset();
    carregar.mockResolvedValue({
      meses: [{ mes: '2026-09', entrou: 12367.99, saiu: 8873.35, liquido: 3494.64, quantidade: 33,
        transferencias: { entrou: 0, saiu: 153 }, creditoDoCartao: { entrou: 0, saiu: 0 } }],
      total: {}, deFora: {},
    });
    const { result } = renderResumo();
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(result.current.data).toMatchObject({ entrou_no_mes: 12367.99, saiu_no_mes: 8873.35, erro_do_extrato: null });
  });
});
