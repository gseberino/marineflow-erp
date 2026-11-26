// Smoke de render do prompt de conclusão. O aviso ao cliente não leva o saldo nem o Pix (dono, 26/11/2026: "2. A");
// "Cobrar o cliente" abre a conferência da ficha e, fechada, a conclusão termina.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';
import { CompletionSendDialog } from './CompletionSendDialog';

// O tipo da unidade da OS (para o emoji) vem de service_orders → vessels(asset_type).
const { unidade, envios } = vi.hoisted(() => ({
  unidade: { tipo: 'Motorhome' as string | null },
  envios: [] as Array<{ fn: string; body: Record<string, unknown> }>,
}));
vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    functions: {
      invoke: async (fn: string, opts: { body: Record<string, unknown> }) => { envios.push({ fn, body: opts.body }); return { error: null }; },
    },
    from: () => ({
      select: () => ({
        eq: () => ({ maybeSingle: async () => ({ data: { vessels: { asset_type: unidade.tipo } }, error: null }) }),
      }),
    }),
  },
}));
// A conferência da cobrança tem os próprios testes (CobrarClienteDialog.smoke): aqui, só quem ela recebe e o fechar.
vi.mock('@/components/client/CobrarClienteDialog', () => ({
  CobrarClienteDialog: ({ clienteId, onFechar }: { clienteId: string | null; onFechar: () => void }) =>
    clienteId ? <div data-testid="cobrar-cliente">cobrança de {clienteId}<button onClick={onFechar}>fechar a cobrança</button></div> : null,
}));

function comConsultas(ui: ReactNode) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(<QueryClientProvider client={qc}>{ui}</QueryClientProvider>);
}

const props = {
  open: true, onOpenChange: () => {}, serviceOrderId: 'so-1', osNumber: 'OS-00060', clientId: 'cli-1',
  clientName: 'Charline Souza', clientPhone: '(47) 99999-0000', balance: 1998.96,
};
const mensagem = () => document.querySelector('textarea')?.value ?? '';

beforeEach(() => { envios.length = 0; unidade.tipo = 'Motorhome'; });

describe('CompletionSendDialog — smoke', () => {
  it('abre com o saldo para quem conclui; a mensagem ao cliente cita a OS e não o valor nem o Pix', () => {
    comConsultas(<CompletionSendDialog {...props} assetType={null} />);
    expect(screen.getByText(/Serviço concluído/i)).toBeTruthy();
    expect(screen.getByText(/saldo de R\$\s1\.998,96/)).toBeTruthy();
    expect(mensagem()).toContain('OS-00060');
    expect(mensagem()).not.toMatch(/1\.998|R\$|pix|saldo/i);
    expect(screen.getByTestId('conclusao-sem-valor')).toHaveTextContent('O aviso não leva valor nem Pix.');
  });

  it('o emoji vem do tipo da unidade da OS: motorhome 🚐, nunca 🚤 (22/10/2026)', async () => {
    comConsultas(<CompletionSendDialog {...props} />);
    await waitFor(() => expect(mensagem()).toContain('Olá Charline! 🚐'));
    expect(mensagem()).not.toContain('🚤');
  });

  it('com o tipo passado por quem abre, não precisa ler', () => {
    comConsultas(<CompletionSendDialog {...props} assetType="Lancha" />);
    expect(mensagem()).toContain('Olá Charline! 🛥️');
  });

  it('"Cobrar o cliente" esconde o aviso e abre a conferência do cliente da OS; fechada, a conclusão termina', () => {
    const onOpenChange = vi.fn();
    comConsultas(<CompletionSendDialog {...props} assetType={null} onOpenChange={onOpenChange} />);
    expect(screen.queryByTestId('cobrar-cliente')).toBeNull();
    fireEvent.click(screen.getByRole('button', { name: /Cobrar o cliente/ }));
    expect(screen.getByTestId('cobrar-cliente')).toHaveTextContent('cobrança de cli-1');
    expect(screen.queryByText(/Serviço concluído/i)).toBeNull();
    expect(envios).toEqual([]);
    fireEvent.click(screen.getByText('fechar a cobrança'));
    expect(onOpenChange).toHaveBeenCalledWith(false);
  });

  it('enviado o aviso (sem valor), fica o "cobrar o saldo?" com Fechar e Cobrar o cliente', async () => {
    comConsultas(<CompletionSendDialog {...props} assetType={null} />);
    fireEvent.click(screen.getByRole('button', { name: /Enviar ao cliente/ }));
    await waitFor(() => expect(screen.getByText(/Aviso enviado — cobrar o saldo\?/)).toBeTruthy());
    expect(envios).toHaveLength(1);
    expect(envios[0].fn).toBe('whatsapp-send');
    expect(String(envios[0].body.message)).not.toMatch(/1\.998|R\$|pix/i);
    expect(envios[0].body.phone).toBe('5547999990000');
    expect(screen.getByRole('button', { name: /Fechar/ })).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: /Cobrar o cliente/ }));
    expect(screen.getByTestId('cobrar-cliente')).toHaveTextContent('cobrança de cli-1');
  });

  it('OS sem cliente do cadastro: não oferece cobrar e diz o motivo; enviado o aviso, fecha', async () => {
    const onOpenChange = vi.fn();
    comConsultas(<CompletionSendDialog {...props} clientId={null} assetType={null} onOpenChange={onOpenChange} />);
    expect(screen.queryByRole('button', { name: /Cobrar o cliente/ })).toBeNull();
    expect(screen.getByTestId('conclusao-sem-valor')).toHaveTextContent('Esta OS não tem cliente do cadastro');
    fireEvent.click(screen.getByRole('button', { name: /Enviar ao cliente/ }));
    await waitFor(() => expect(onOpenChange).toHaveBeenCalledWith(false));
  });
});
