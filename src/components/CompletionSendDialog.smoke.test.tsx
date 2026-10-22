// Smoke de render do prompt de conclusão — garante que abre sem crashar e pré-preenche a mensagem.
import { describe, it, expect, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';
import { CompletionSendDialog } from './CompletionSendDialog';

// O tipo da unidade da OS (para o emoji) vem de service_orders → vessels(asset_type).
const unidade = vi.hoisted(() => ({ tipo: 'Motorhome' as string | null }));
vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    functions: { invoke: async () => ({ error: null }) },
    from: () => ({
      select: () => ({
        eq: () => ({ maybeSingle: async () => ({ data: { vessels: { asset_type: unidade.tipo } }, error: null }) }),
      }),
    }),
  },
}));
vi.mock('@/hooks/use-app-settings', () => ({ useAppSettings: () => ({ data: { pix_key: 'hbr@pix.com' } }) }));

function comConsultas(ui: ReactNode) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(<QueryClientProvider client={qc}>{ui}</QueryClientProvider>);
}

const props = {
  open: true, onOpenChange: () => {}, serviceOrderId: 'so-1', osNumber: 'OS-00060',
  clientName: 'Charline Souza', clientPhone: '(47) 99999-0000', balance: 1998.96, dueDate: '2026-08-26',
};

describe('CompletionSendDialog — smoke', () => {
  it('abre com saldo e pré-preenche a mensagem (valor + vencimento)', () => {
    comConsultas(<CompletionSendDialog {...props} />);
    expect(screen.getByText(/Serviço concluído/i)).toBeTruthy();
    // a mensagem (no textarea) deve citar a OS e o saldo
    const anyTextarea = document.querySelector('textarea');
    expect(anyTextarea?.value).toContain('OS-00060');
    expect(anyTextarea?.value).toContain('1.998,96');
  });

  it('o emoji vem do tipo da unidade da OS: motorhome 🚐, nunca 🚤 (22/10/2026)', async () => {
    unidade.tipo = 'Motorhome';
    comConsultas(<CompletionSendDialog {...props} />);
    await waitFor(() => expect(document.querySelector('textarea')?.value).toContain('Olá Charline! 🚐'));
    expect(document.querySelector('textarea')?.value).not.toContain('🚤');
  });

  it('com o tipo passado por quem abre, não precisa ler', () => {
    comConsultas(<CompletionSendDialog {...props} assetType="Lancha" />);
    expect(document.querySelector('textarea')?.value).toContain('Olá Charline! 🛥️');
  });
});
