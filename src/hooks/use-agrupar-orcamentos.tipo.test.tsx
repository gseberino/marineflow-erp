// useAgrupamentoDoOrcamento depois do agrupar OS (28/10/2026): a mesma leitura serve aos dois agrupamentos e
// diz o TIPO pelas origens (origem de orçamento nunca tem converted_to_os_at), quais originais estavam
// assinadas e, na origem de OS, se a agrupada ainda dá para desfazer. O de orçamento segue como era.
import { describe, it, expect, vi } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';

type Linha = Record<string, unknown>;
const banco = vi.hoisted(() => ({
  agrupamentos: [] as Linha[],
  origens: [] as Linha[],
  ordens: [] as Linha[],
}));

vi.mock('@/integrations/supabase/client', () => {
  const tabelas = (t: string): Linha[] =>
    t === 'orcamento_agrupamentos' ? banco.agrupamentos
    : t === 'orcamento_agrupamento_origens' ? banco.origens
    : banco.ordens;
  const consulta = (tabela: string) => {
    const filtros: Array<(l: Linha) => boolean> = [];
    let ordenar: string | null = null;
    const resultado = () => {
      const linhas = tabelas(tabela).filter((l) => filtros.every((f) => f(l)));
      if (ordenar) linhas.sort((a, b) => Number(a[ordenar!]) - Number(b[ordenar!]));
      return linhas;
    };
    const q = {
      select: () => q,
      eq: (c: string, v: unknown) => { filtros.push((l) => l[c] === v); return q; },
      is: (c: string, v: unknown) => { filtros.push((l) => (l[c] ?? null) === v); return q; },
      in: (c: string, vs: unknown[]) => { filtros.push((l) => vs.includes(l[c])); return q; },
      order: (c: string) => { ordenar = c; return q; },
      maybeSingle: async () => ({ data: resultado()[0] ?? null, error: null }),
      then: (ok: (v: unknown) => unknown) => Promise.resolve({ data: resultado(), error: null }).then(ok),
    };
    return q;
  };
  return { supabase: { from: (t: string) => consulta(t) } };
});

import { useAgrupamentoDoOrcamento } from './use-agrupar-orcamentos';

function embrulho({ children }: { children: ReactNode }) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return <QueryClientProvider client={qc}>{children}</QueryClientProvider>;
}

describe('useAgrupamentoDoOrcamento — tipo do agrupamento', () => {
  it('agrupada de OS: tipo os e a assinatura de cada original', async () => {
    banco.agrupamentos = [{ id: 'g1', agrupado_id: 'nova', desfeito_em: null }];
    banco.origens = [
      { agrupamento_id: 'g1', origem_id: 'a', numero: 'OS-00032', ordem: 1 },
      { agrupamento_id: 'g1', origem_id: 'b', numero: 'OS-00033', ordem: 2 },
    ];
    banco.ordens = [
      { id: 'nova', merged_into_id: null, converted_to_os_at: '2026-10-28T10:00:00Z' },
      { id: 'a', converted_to_os_at: '2026-10-01T10:00:00Z', signed_at: null },
      { id: 'b', converted_to_os_at: '2026-10-02T10:00:00Z', signed_at: '2026-10-03T10:00:00Z' },
    ];
    const { result } = renderHook(() => useAgrupamentoDoOrcamento('nova'), { wrapper: embrulho });
    await waitFor(() => expect(result.current.comoAgrupado).not.toBeNull());
    expect(result.current.comoAgrupado).toEqual({
      agrupamentoId: 'g1',
      tipo: 'os',
      origens: [
        { id: 'a', numero: 'OS-00032', assinada: false },
        { id: 'b', numero: 'OS-00033', assinada: true },
      ],
    });
    expect(result.current.comoOrigem).toBeNull();
  });

  it('agrupado de orçamentos (mesmo já convertido em OS): continua tipo orcamento', async () => {
    banco.agrupamentos = [{ id: 'g2', agrupado_id: 'orc', desfeito_em: null }];
    banco.origens = [
      { agrupamento_id: 'g2', origem_id: 'x', numero: 'ORÇ-00001', ordem: 1 },
      { agrupamento_id: 'g2', origem_id: 'y', numero: 'ORÇ-00002', ordem: 2 },
    ];
    banco.ordens = [
      { id: 'orc', merged_into_id: null, converted_to_os_at: '2026-10-20T10:00:00Z' },
      { id: 'x', converted_to_os_at: null, signed_at: null },
      { id: 'y', converted_to_os_at: null, signed_at: null },
    ];
    const { result } = renderHook(() => useAgrupamentoDoOrcamento('orc'), { wrapper: embrulho });
    await waitFor(() => expect(result.current.comoAgrupado).not.toBeNull());
    expect(result.current.comoAgrupado?.tipo).toBe('orcamento');
  });

  it('origem de OS: tipo os, e desfazível enquanto a agrupada não começou nem foi assinada', async () => {
    banco.agrupamentos = [];
    banco.origens = [];
    banco.ordens = [
      { id: 'a', merged_into_id: 'nova', converted_to_os_at: '2026-10-01T10:00:00Z' },
      { id: 'nova', service_order_number: 'OS-00140', status: 'approved', converted_to_os_at: '2026-10-28T10:00:00Z', signed_at: null },
    ];
    const { result } = renderHook(() => useAgrupamentoDoOrcamento('a'), { wrapper: embrulho });
    await waitFor(() => expect(result.current.comoOrigem).not.toBeNull());
    expect(result.current.comoOrigem).toEqual({ agrupadoId: 'nova', agrupadoNumero: 'OS-00140', agrupadoEmAberto: true, tipo: 'os' });
  });

  it('OS antiga sem converted_to_os_at: o motivo "Agrupada em" diz que é de OS (agrupada e origem)', async () => {
    banco.agrupamentos = [{ id: 'g3', agrupado_id: 'nova', desfeito_em: null }];
    banco.origens = [
      { agrupamento_id: 'g3', origem_id: 'v1', numero: 'OS-00032', ordem: 1 },
      { agrupamento_id: 'g3', origem_id: 'v2', numero: 'OS-00033', ordem: 2 },
    ];
    banco.ordens = [
      { id: 'nova', service_order_number: 'OS-00140', status: 'approved', merged_into_id: null, converted_to_os_at: '2026-10-28T10:00:00Z', signed_at: null },
      { id: 'v1', merged_into_id: 'nova', converted_to_os_at: null, cancellation_reason: 'Agrupada em OS-00140 (reúne OS-00032, OS-00033)', signed_at: null },
      { id: 'v2', merged_into_id: 'nova', converted_to_os_at: null, cancellation_reason: 'Agrupada em OS-00140 (reúne OS-00032, OS-00033)', signed_at: null },
    ];
    const agrupada = renderHook(() => useAgrupamentoDoOrcamento('nova'), { wrapper: embrulho });
    await waitFor(() => expect(agrupada.result.current.comoAgrupado).not.toBeNull());
    expect(agrupada.result.current.comoAgrupado?.tipo).toBe('os');
    const origem = renderHook(() => useAgrupamentoDoOrcamento('v1'), { wrapper: embrulho });
    await waitFor(() => expect(origem.result.current.comoOrigem).not.toBeNull());
    expect(origem.result.current.comoOrigem?.tipo).toBe('os');
  });

  it('origem de OS com a agrupada já em execução: não dá mais para desfazer', async () => {
    banco.agrupamentos = [];
    banco.ordens = [
      { id: 'a', merged_into_id: 'nova', converted_to_os_at: '2026-10-01T10:00:00Z' },
      { id: 'nova', service_order_number: 'OS-00140', status: 'in_progress', converted_to_os_at: '2026-10-28T10:00:00Z', signed_at: null },
    ];
    const { result } = renderHook(() => useAgrupamentoDoOrcamento('a'), { wrapper: embrulho });
    await waitFor(() => expect(result.current.comoOrigem).not.toBeNull());
    expect(result.current.comoOrigem?.agrupadoEmAberto).toBe(false);
  });

  it('origem de orçamento: a regra de sempre (rascunho, não convertido, não assinado)', async () => {
    banco.agrupamentos = [];
    banco.ordens = [
      { id: 'x', merged_into_id: 'orc', converted_to_os_at: null },
      { id: 'orc', service_order_number: 'ORÇ-00100', status: 'draft', converted_to_os_at: null, signed_at: null },
    ];
    const { result } = renderHook(() => useAgrupamentoDoOrcamento('x'), { wrapper: embrulho });
    await waitFor(() => expect(result.current.comoOrigem).not.toBeNull());
    expect(result.current.comoOrigem).toEqual({ agrupadoId: 'orc', agrupadoNumero: 'ORÇ-00100', agrupadoEmAberto: true, tipo: 'orcamento' });
  });
});
