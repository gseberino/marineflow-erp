// O hook da via do técnico na tela (porte da via v2, F1): só deixa imprimir com serviços, material e cabeçalho
// carregados (o menu fica desabilitado com "carregando…"), não lê mais a RPC seguranca_da_via (E14) e o aviso antes de
// imprimir não fala de local nem de segurança (E19). Dado sintético.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';

const h = vi.hoisted(() => ({
  servicos: { data: undefined as unknown[] | undefined, isLoading: true },
  materiais: { data: undefined as unknown[] | undefined, isLoading: true },
  passos: { data: undefined as unknown[] | undefined, isLoading: false },
  rpc: vi.fn(),
}));

vi.mock('@/hooks/use-service-steps', () => ({
  useServiceOrderSteps: () => h.passos,
  useRouteMaterials: () => h.materiais,
}));
vi.mock('@/hooks/use-service-orders', () => ({ useServiceOrderServices: () => h.servicos }));
vi.mock('@/hooks/use-service-survey', () => ({ useServiceOrderSurvey: () => ({ data: null }) }));
vi.mock('@/hooks/use-app-settings', () => ({ useAppSettings: () => ({ data: {} }) }));
vi.mock('@/lib/fotos-da-os', () => ({ useLinksDasFotos: () => ({ data: {} }) }));
vi.mock('@/integrations/supabase/client', () => ({
  supabase: { rpc: h.rpc, from: () => ({ select: () => ({ in: async () => ({ data: [], error: null }) }) }) },
}));

import { useViaDoTecnico } from './use-via-do-tecnico';

function embrulho({ children }: { children: ReactNode }) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return <QueryClientProvider client={qc}>{children}</QueryClientProvider>;
}

const CABECALHO = { orderNumber: 'OS-00999', clientName: 'Cliente Sintético', clientPhone: '(47) 99999-0000', scheduledAt: '2026-11-26T11:00:00Z' };

describe('useViaDoTecnico — carregando, faltas e a leitura sem a RPC', () => {
  beforeEach(() => {
    h.servicos = { data: undefined, isLoading: true };
    h.materiais = { data: undefined, isLoading: true };
    h.passos = { data: [], isLoading: false };
    h.rpc.mockReset();
  });

  it('carregando → carregado: espera serviços, material e o cabeçalho da OS', () => {
    const { result, rerender } = renderHook(({ cab }) => useViaDoTecnico('os1', cab), {
      wrapper: embrulho, initialProps: { cab: CABECALHO as Record<string, unknown> },
    });
    expect(result.current.carregando).toBe(true);
    // serviços chegaram, material ainda não
    h.servicos = { data: [{ id: 'l1', name_snapshot: 'Instalação do inversor' }], isLoading: false };
    rerender({ cab: CABECALHO });
    expect(result.current.carregando).toBe(true);
    // material chegou
    h.materiais = { data: [{ id: 'm1', quantity: 1, notes: null, service_order_service_id: null }], isLoading: false };
    rerender({ cab: CABECALHO });
    expect(result.current.carregando).toBe(false);
    // sem o cabeçalho (a OS ainda carregando na tela), não imprime
    rerender({ cab: {} });
    expect(result.current.carregando).toBe(true);
  });

  it('não lê mais seguranca_da_via (E14)', () => {
    h.servicos = { data: [{ id: 'l1', name_snapshot: 'Instalação do inversor' }], isLoading: false };
    h.materiais = { data: [], isLoading: false };
    renderHook(() => useViaDoTecnico('os1', CABECALHO), { wrapper: embrulho });
    expect(h.rpc).not.toHaveBeenCalled();
  });

  it('faltas: sem "local e acesso" nem "segurança"; serviços contam sem a cobrança (4A)', () => {
    h.servicos = { data: [{ id: 'l1', name_snapshot: 'Frete do equipamento' }], isLoading: false };
    h.materiais = { data: [{ id: 'm1', quantity: 1, notes: null, service_order_service_id: null }], isLoading: false };
    const { result } = renderHook(() => useViaDoTecnico('os1', CABECALHO), { wrapper: embrulho });
    expect(result.current.faltas).toEqual(['serviços']);
    h.servicos = { data: [{ id: 'l1', name_snapshot: 'Instalação do inversor' }], isLoading: false };
    const { result: completo } = renderHook(() => useViaDoTecnico('os1', CABECALHO), { wrapper: embrulho });
    expect(completo.current.faltas).toEqual([]);
  });

  it('sem OS (formulário novo), nada a carregar', () => {
    const { result } = renderHook(() => useViaDoTecnico(undefined, {}), { wrapper: embrulho });
    expect(result.current.carregando).toBe(false);
  });
});
