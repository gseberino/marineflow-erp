// A lista de NFS-e mostrava número, status e a data de CRIAÇÃO da linha — e nada mais.
// Faltava o que se usa para achar uma nota (o tomador) e o valor, que nem vinha do banco:
// a consulta não trazia `request_payload`.
//
// O caso da NFS-e 1/4 é real: emitida 27/08 às 22h22, gravada como "2026-08-28T01:22Z".
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const { docsMock, healthMock } = vi.hoisted(() => ({
  docsMock: vi.fn(),
  healthMock: vi.fn(),
}));

vi.mock('@/hooks/use-nfse', async (importOriginal) => {
  const real = await importOriginal<typeof import('@/hooks/use-nfse')>();
  return {
    ...real,
    useNfseHealth: healthMock,
    useNfseDocumentos: docsMock,
    useEmitirNfse: () => ({ mutate: vi.fn(), isPending: false }),
    useCancelarNfse: () => ({ mutate: vi.fn(), isPending: false }),
    useArtefatoNfse: () => ({ mutate: vi.fn(), isPending: false }),
    useAtualizarStatusNfse: () => ({ mutate: vi.fn(), isPending: false }),
  };
});

vi.mock('@/hooks/use-faturar-os', () => ({ atualizarInvoicingStatus: vi.fn() }));

import { I18nProvider } from '@/i18n';
import { NfseSection } from './NfseSection';

/** NFS-e 1/4, como ela existe no banco: valor em `amounts`, data real em `latest_event`. */
const NOTA = {
  id: 'n1',
  number: 4,
  series: 1,
  status: 'authorized',
  environment: 'producao',
  status_message: null,
  created_at: '2026-08-28T01:22:27Z',
  origin_id: null,
  authorized_at: null,
  document_type: 'nfse',
  provider_status: {
    nfse_number: '4',
    display_number: '4',
    latest_event: { status: 'authorized', created_at: '2026-08-27T22:22:27-03:00' },
  },
  request_payload: {
    taker: { name: 'LUCENIRA MARIA DE MELO', document: '12345678900' },
    service: { description: 'Instalação de carregador; Instalação de fogão' },
    amounts: { net_amount: 2431.83, service_amount: 2500 },
  },
};

function montar(docs: unknown[]) {
  docsMock.mockReturnValue({ data: docs, isLoading: false, error: null });
  healthMock.mockReturnValue({
    data: { pronto: true, pendencias: [] }, isLoading: false, error: null,
  });
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider><NfseSection /></I18nProvider>
    </QueryClientProvider>,
  );
}

describe('lista de NFS-e', () => {
  it('mostra o tomador — era o dado que faltava para achar a nota', async () => {
    montar([NOTA]);
    expect(await screen.findByText('LUCENIRA MARIA DE MELO')).toBeInTheDocument();
  });

  it('mostra o valor: a consulta nem trazia o payload, então era sempre vazio', async () => {
    montar([NOTA]);
    // Líquido, não o bruto de 2.500 — é o que o tomador deve.
    expect(await screen.findByText(/2\.431,83/)).toBeInTheDocument();
  });

  it('data da nota, não a da linha em UTC — a diferença era de um dia inteiro', async () => {
    montar([NOTA]);
    // created_at em UTC cairia em 28/08; a nota é de 27/08.
    expect(await screen.findByText(/27\/08\/2026/)).toBeInTheDocument();
    expect(screen.queryByText(/28\/08\/2026/)).not.toBeInTheDocument();
  });

  it('situação em português, não o código cru do banco', async () => {
    montar([NOTA]);
    expect(await screen.findByText('Autorizada')).toBeInTheDocument();
    expect(screen.queryByText('authorized')).not.toBeInTheDocument();
  });

  it('cancelar sai de vista: só o PDF fica à mão, o resto no menu', async () => {
    const user = userEvent.setup();
    montar([NOTA]);
    await screen.findByText('LUCENIRA MARIA DE MELO');
    // A ação destrutiva não fica solta ao lado de "baixar PDF".
    expect(screen.queryByText(/Cancelar NFS-e/i)).not.toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: /mais ações para nfs-e 4/i }));
    expect(await screen.findByText(/Cancelar NFS-e/i)).toBeInTheDocument();
    expect(screen.getByText(/Baixar XML do RPS/i)).toBeInTheDocument();
  });

  it('nota sem tomador não quebra a linha, e diz que não sabe', async () => {
    montar([{ ...NOTA, id: 'n2', request_payload: { amounts: { service_amount: 100 } } }]);
    expect(await screen.findByText(/Tomador não identificado/i)).toBeInTheDocument();
  });
});
