// "Agrupar" único (decisão 4B, 18/11/2026): render de verdade (tsc/build não pegam TDZ) e a escolha que a janela
// oferece — só pergunta "juntar de vez" quando a fusão também é possível; senão vai ao conjunto e diz por quê.
import { describe, expect, it, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const rpc = vi.fn();
vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc: (...a: unknown[]) => rpc(...a) } }));
vi.mock('sonner', () => ({ toast: { success: vi.fn(), info: vi.fn(), error: vi.fn() } }));

import { AgruparDialog } from './AgruparDialog';

const doc = (p: Record<string, unknown>) => ({
  tipo: 'os', status: 'awaiting_client', quote_status: 'approved', grand_total: 1000, criado_em: '2026-11-01',
  motivo: null, motivo_juntar: null, ...p,
});

function abrir(leitura: unknown, props: Partial<React.ComponentProps<typeof AgruparDialog>> = {}) {
  rpc.mockImplementation(async (nome: string) => {
    if (nome === 'documentos_para_conjunto') return { data: leitura, error: null };
    if (nome === 'agrupar_para_cliente') {
      return { data: { ok: true, conjunto_id: 'c1', nome: 'OS-00104 + OS-00134', avisos: [], conjunto: null }, error: null };
    }
    return { data: null, error: null };
  });
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const onJuntarDeVez = vi.fn();
  const onFechar = vi.fn();
  render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <AgruparDialog aberto onFechar={onFechar} documentoId="a" onJuntarDeVez={onJuntarDeVez} {...props} />
      </MemoryRouter>
    </QueryClientProvider>,
  );
  return { onJuntarDeVez, onFechar };
}

beforeEach(() => rpc.mockReset());

describe('AgruparDialog', () => {
  it('OS com chegada no barco: só apresentar junto, diz por quê, e grava o conjunto', async () => {
    const { onFechar } = abrir({
      documento: doc({ id: 'a', numero: 'OS-00104', motivo_juntar: 'OS-00104 já começou a ser executada (chegada no barco registrada).' }),
      candidatos: [doc({ id: 'b', numero: 'OS-00134' }), doc({ id: 'z', numero: 'OS-00099', motivo: 'OS-00099 está cancelado.' })],
    }, { preSelecionados: ['b'] });
    expect(await screen.findByText('OS-00104')).toBeInTheDocument();
    expect(screen.queryByText('Juntar de vez')).not.toBeInTheDocument();
    expect(screen.getByText(/Juntar de vez não é possível aqui: OS-00104 já começou/)).toBeInTheDocument();
    expect(screen.getByText('OS-00099 está cancelado.')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Agrupar' }));
    await waitFor(() => expect(rpc).toHaveBeenCalledWith('agrupar_para_cliente', { p_ids: ['a', 'b'], p_principal: 'a' }));
    expect(onFechar).toHaveBeenCalled();
  });

  it('todas fundíveis: oferece as duas; "Juntar de vez" entrega ao diálogo de sempre', async () => {
    const { onJuntarDeVez } = abrir({
      documento: doc({ id: 'a', numero: 'OS-00100' }),
      candidatos: [doc({ id: 'b', numero: 'OS-00128' })],
    }, { preSelecionados: ['b'] });
    expect(await screen.findByText('Juntar de vez')).toBeInTheDocument();
    expect(screen.getByText('Apresentar junto')).toBeInTheDocument();
    await userEvent.click(screen.getByText('Juntar de vez'));
    await userEvent.click(screen.getByRole('button', { name: 'Continuar' }));
    expect(onJuntarDeVez).toHaveBeenCalledWith('os', ['a', 'b'], 'a');
    expect(rpc).not.toHaveBeenCalledWith('agrupar_para_cliente', expect.anything());
  });

  it('ORÇ + OS: mistura sem oferecer fusão', async () => {
    abrir({
      documento: doc({ id: 'a', numero: 'OS-00104' }),
      candidatos: [doc({ id: 'b', numero: 'ORÇ-00140', tipo: 'orcamento', status: 'draft', quote_status: 'draft' })],
    }, { preSelecionados: ['b'] });
    expect(await screen.findByText('ORÇ-00140')).toBeInTheDocument();
    expect(screen.queryByText('Juntar de vez')).not.toBeInTheDocument();
    expect(screen.getByText(/mesmo tipo/)).toBeInTheDocument();
  });

  it('sem outro documento: diz que não há e não deixa agrupar', async () => {
    abrir({ documento: doc({ id: 'a', numero: 'OS-00104' }), candidatos: [] });
    expect(await screen.findByText(/Não há outro orçamento ou OS/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Agrupar' })).toBeDisabled();
  });
});
