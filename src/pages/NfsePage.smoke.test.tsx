// [NFSE-PAGE] Smoke de render da página de Notas de Serviço.
//
// O que se testa: (1) a página abre com conteúdo e com a seção de NFS-e dentro,
// (2) o botão "Faturar OS" fica desarmado sem OS escolhida (abrir o assistente sem
// alvo emitiria contra null), (3) produção grita, (4) a avulsa abre com o fluxo de
// conferência — o passo que impede emissão real sem leitura.
import { describe, it, expect, vi, afterEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import NfsePage from './NfsePage';

const { estado } = vi.hoisted(() => ({
  estado: {
    ambiente: 'homologacao' as 'homologacao' | 'producao',
  },
}));

vi.mock('@/hooks/use-nfse', async (importOriginal) => {
  const real = await importOriginal<typeof import('@/hooks/use-nfse')>();
  return {
    ...real,
    useAmbienteFiscal: () => ({ data: estado.ambiente, isLoading: false }),
    useNfseHealth: () => ({
      data: { pronto: true, pendencias_locais: [], contora: { pending: [] } },
      isLoading: false,
      error: null,
    }),
    useNfseDocumentos: () => ({ data: [], isLoading: false, error: null }),
    useEmitirNfse: () => ({ mutate: vi.fn(), mutateAsync: vi.fn(), isPending: false }),
    useCancelarNfse: () => ({ mutate: vi.fn(), isPending: false }),
    useAtualizarStatusNfse: () => ({ mutate: vi.fn(), isPending: false }),
    useArtefatoNfse: () => ({ mutate: vi.fn(), isPending: false }),
    useEmitirNfseAvulsa: () => ({ mutateAsync: vi.fn(), isPending: false }),
  };
});

vi.mock('@/hooks/use-service-orders', async (importOriginal) => {
  const real = await importOriginal<typeof import('@/hooks/use-service-orders')>();
  return {
    ...real,
    useServiceOrders: () => ({
      data: [
        { id: 'os-1', service_order_number: 'OS-00001', status: 'completed', created_at: '2026-08-01', clients: { name: 'Cliente Teste' } },
      ],
      isLoading: false,
    }),
  };
});

vi.mock('@/hooks/use-clients', () => ({
  useClients: () => ({ data: [], isLoading: false }),
}));

vi.mock('@/hooks/use-service-fiscal', async (importOriginal) => {
  const real = await importOriginal<typeof import('@/hooks/use-service-fiscal')>();
  return {
    ...real,
    useServiceFiscalVerbs: () => ({ data: [], isLoading: false }),
  };
});

vi.mock('@/hooks/use-faturar-os', async (importOriginal) => {
  const real = await importOriginal<typeof import('@/hooks/use-faturar-os')>();
  return {
    ...real,
    useBillingPreflight: () => ({ data: null, isLoading: true, isFetching: false, error: null, refetch: vi.fn() }),
    useEmitirNfeDaOs: () => ({ mutateAsync: vi.fn(), isPending: false }),
  };
});

function renderPagina() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <MemoryRouter>
      <QueryClientProvider client={qc}>
        <I18nProvider><NfsePage /></I18nProvider>
      </QueryClientProvider>
    </MemoryRouter>,
  );
}

describe('página de Notas de Serviço', () => {
  afterEach(() => {
    estado.ambiente = 'homologacao';
  });

  it('abre com o título e a seção de NFS-e dentro', async () => {
    renderPagina();
    expect(await screen.findByText('Notas de Serviço (NFS-e)')).toBeInTheDocument();
    expect(screen.getByText(/NFS-e — Nota Fiscal de Serviço/)).toBeInTheDocument();
  });

  it('"Faturar OS" fica desarmado sem OS escolhida', async () => {
    renderPagina();
    expect(await screen.findByRole('button', { name: /Faturar OS \(NFS-e \+ NF-e\)/ })).toBeDisabled();
  });

  it('em homologação não grita produção', async () => {
    renderPagina();
    await screen.findByText('Notas de Serviço (NFS-e)');
    expect(screen.queryByText(/notas reais/)).not.toBeInTheDocument();
  });

  it('em produção grita', async () => {
    estado.ambiente = 'producao';
    renderPagina();
    expect(await screen.findByText(/as emissões desta página são notas reais/)).toBeInTheDocument();
  });

  it('a avulsa abre e exige conferência antes de emitir', async () => {
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    renderPagina();
    await user.click(await screen.findByRole('button', { name: /NFS-e avulsa/ }));
    expect(await screen.findByText(/Serviço que não virou OS/)).toBeInTheDocument();
    // Sem preencher nada, o caminho para a emissão fica travado no passo de conferência.
    expect(screen.getByRole('button', { name: /Conferir antes de emitir/ })).toBeDisabled();
    expect(screen.queryByRole('button', { name: /Emitir/ })).not.toBeInTheDocument();
  });
});
