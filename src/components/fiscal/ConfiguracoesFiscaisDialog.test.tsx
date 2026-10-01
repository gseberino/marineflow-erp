// "Configurar empresa emissora" (D33, 01/10/2026). O que se protege: o formulário abre com o
// cadastro; sem UF não salva; o que vai ao banco é a conversão testada (NFS-e vazia → null);
// "Cancelar" e "Enviar teste" voltam para a tela.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const banco = vi.hoisted(() => ({
  updates: [] as Array<{ payload: Record<string, unknown>; id: unknown }>,
  toasts: [] as string[],
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: () => ({
      update: (payload: Record<string, unknown>) => ({
        eq: async (_c: string, id: unknown) => { banco.updates.push({ payload, id }); return { error: null }; },
      }),
      insert: async () => ({ error: null }),
    }),
    rpc: async () => ({ error: null }),
    functions: { invoke: async () => ({ data: null, error: null }) },
  },
}));
vi.mock('sonner', () => ({
  toast: {
    success: (m: string) => banco.toasts.push(m),
    error: (m: string) => banco.toasts.push(`erro: ${m}`),
    warning: (m: string) => banco.toasts.push(`aviso: ${m}`),
    loading: () => 't1',
  },
}));

import { ConfiguracoesFiscaisDialog } from './ConfiguracoesFiscaisDialog';

const empresa = {
  id: 'cfs-1', legal_name: 'HBR MARINE SOLUTIONS LTDA', trade_name: 'HBR', cnpj: '12345678000199',
  state_code: 'SC', tax_regime: 'simples', crt: 1, nfe_series_producao: 2,
  ibge_city_code: '', nfse_total_tax_rate_sn: null, nfse_default_series: 1,
};

function montar(company: unknown, extras: { onClose?: () => void; onTestarEmail?: () => void } = {}) {
  render(
    <QueryClientProvider client={new QueryClient()}>
      <ConfiguracoesFiscaisDialog company={company} onClose={extras.onClose ?? (() => {})} onTestarEmail={extras.onTestarEmail ?? (() => {})} />
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  banco.updates = [];
  banco.toasts = [];
});

describe('ConfiguracoesFiscaisDialog', () => {
  it('abre com o cadastro e salva a conversão para o banco', async () => {
    const onClose = vi.fn();
    montar(empresa, { onClose });
    expect(screen.getByDisplayValue('HBR MARINE SOLUTIONS LTDA')).toBeTruthy();
    fireEvent.change(screen.getByDisplayValue('HBR'), { target: { value: 'HBR Marine' } });
    fireEvent.click(screen.getByRole('button', { name: 'Salvar' }));
    await waitFor(() => expect(onClose).toHaveBeenCalled());
    expect(banco.updates).toHaveLength(1);
    expect(banco.updates[0].id).toBe('cfs-1');
    expect(banco.updates[0].payload).toMatchObject({
      trade_name: 'HBR Marine', state_code: 'SC', nfe_series_producao: 2,
      ibge_city_code: null, nfse_total_tax_rate_sn: null, nfse_default_series: 1,
    });
    expect(banco.toasts).toContain('Dados fiscais da empresa salvos.');
  });

  it('sem UF não salva', () => {
    montar({ ...empresa, state_code: '' });
    fireEvent.click(screen.getByRole('button', { name: 'Salvar' }));
    expect(banco.updates).toEqual([]);
    expect(banco.toasts[0]).toMatch(/Selecione a UF da empresa/);
  });

  it('Cancelar e Enviar teste voltam para a tela', () => {
    const onClose = vi.fn();
    const onTestarEmail = vi.fn();
    montar(empresa, { onClose, onTestarEmail });
    fireEvent.click(screen.getByRole('button', { name: /Enviar teste/ }));
    expect(onTestarEmail).toHaveBeenCalledTimes(1);
    fireEvent.click(screen.getByRole('button', { name: 'Cancelar' }));
    expect(onClose).toHaveBeenCalled();
  });
});
