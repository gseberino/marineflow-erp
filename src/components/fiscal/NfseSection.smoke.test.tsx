// [F-NFSE-01] Smoke de render da seção de NFS-e.
//
// O que se testa aqui não é layout: é que a tela NÃO deixa emitir antes do pré-voo verde.
// Cada emissão consome numeração fiscal que não volta, e a NFS-e tem dois caminhos cuja
// escolha é do município — um botão aceso cedo demais custa nota.
import { describe, it, expect, vi, afterEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { NfseSection } from './NfseSection';

const { estado, emitirMock, cancelarMock } = vi.hoisted(() => ({
  emitirMock: vi.fn(),
  cancelarMock: vi.fn(),
  estado: {
    health: {
      pronto: false,
      contora: { ready: false, standard: 'nacional', city_name: 'Itajaí', certificate_ok: true, pending: [] },
      pendencias_locais: [
        'Falta o percentual total de tributos do Simples (nfse_total_tax_rate_sn). [E0712]',
      ],
      divergencia_de_padrao: null as string | null,
    },
    documentos: [] as unknown[],
  },
}));

vi.mock('@/hooks/use-nfse', async (importOriginal) => {
  const real = await importOriginal<typeof import('@/hooks/use-nfse')>();
  return {
    ...real,
    useNfseHealth: () => ({ data: estado.health, isLoading: false, error: null }),
    useNfseDocumentos: () => ({ data: estado.documentos, isLoading: false, error: null }),
    useEmitirNfse: () => ({ mutate: emitirMock, isPending: false }),
    useCancelarNfse: () => ({ mutate: cancelarMock, isPending: false }),
    useAtualizarStatusNfse: () => ({ mutate: vi.fn(), isPending: false }),
    useArtefatoNfse: () => ({ mutate: vi.fn(), isPending: false }),
  };
});

function renderSecao(serviceOrderId: string | null = 'os-1') {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider><NfseSection serviceOrderId={serviceOrderId} /></I18nProvider>
    </QueryClientProvider>,
  );
}

describe('seção de NFS-e', () => {
  afterEach(() => {
    emitirMock.mockClear();
    estado.health.pronto = false;
    estado.documentos = [];
    estado.health.divergencia_de_padrao = null;
  });

  it('abre com conteúdo, não em branco', async () => {
    renderSecao();
    expect(await screen.findByText(/NFS-e — Nota Fiscal de Serviço/)).toBeInTheDocument();
  });

  it('diz que peça continua na NF-e', async () => {
    // A separação que o gestor precisa enxergar: são documentos diferentes.
    renderSecao();
    expect(await screen.findByText(/peças da OS continuam na NF-e/)).toBeInTheDocument();
  });

  it('NÃO oferece emitir enquanto o pré-voo não está verde', async () => {
    // A regra mais importante desta tela.
    renderSecao();
    await screen.findByText(/Ainda não dá para emitir/);
    expect(screen.queryByRole('button', { name: /Emitir NFS-e da OS/ })).not.toBeInTheDocument();
  });

  it('mostra a pendência com o código da rejeição que ela evita', async () => {
    renderSecao();
    expect(await screen.findByText(/E0712/)).toBeInTheDocument();
  });

  it('libera o botão quando o pré-voo fica verde', async () => {
    estado.health.pronto = true;
    renderSecao();
    const botao = await screen.findByRole('button', { name: /Emitir NFS-e da OS/ });
    expect(botao).toBeEnabled();
  });

  it('sem OS não emite, mesmo com pré-voo verde', async () => {
    estado.health.pronto = true;
    renderSecao(null);
    expect(await screen.findByRole('button', { name: /Emitir NFS-e da OS/ })).toBeDisabled();
  });

  it('mostra divergência de padrão sem corrigir sozinho', async () => {
    // Qual padrão vale é decisão fiscal; o sistema alinhar sozinho esconderia o que precisa
    // ser conferido.
    estado.health.divergencia_de_padrao = 'A Contora diz "municipal", o cadastro diz "nacional".';
    renderSecao();
    expect(await screen.findByText(/decisão fiscal/)).toBeInTheDocument();
  });

  it('a justificativa de cancelamento respeita a faixa 15–255', async () => {
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    estado.health.pronto = true;
    estado.documentos = [{
      id: 'd1', number: 1, series: 1, status: 'authorized', environment: 'homologacao',
      status_message: null, created_at: '2026-08-10T10:00:00Z', origin_id: 'os-1',
    }];
    renderSecao();

    await user.click(await screen.findByRole('button', { name: /Cancelar/ }));
    const acao = await screen.findByRole('button', { name: /Cancelar a nota/ });
    expect(acao).toBeDisabled(); // vazio

    await user.type(screen.getByRole('textbox'), 'curto');
    expect(acao).toBeDisabled(); // abaixo de 15

    await user.type(screen.getByRole('textbox'), ' mas agora ficou grande o bastante');
    expect(acao).toBeEnabled();
  });
});
