// [FATURAR-OS] Smoke de render do assistente "Faturar OS".
//
// O que se testa não é layout: é que (1) o checklist aparece ANTES de qualquer botão de
// emissão valer, (2) documento que não se aplica é dito em voz alta em vez de sumir,
// (3) pendência vem com o nome do serviço que falta cadastrar, e (4) nota já emitida
// desarma o botão — um retry não pode virar segunda nota.
import { describe, it, expect, vi, afterEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { FaturarOsDialog } from './FaturarOsDialog';
import type { BillingPreflight } from '@/hooks/use-faturar-os';

const { estado, emitirNfseMock, emitirNfeMock } = vi.hoisted(() => ({
  emitirNfseMock: vi.fn(),
  emitirNfeMock: vi.fn(),
  estado: {
    preflight: null as BillingPreflight | null,
    healthPronto: true,
  },
}));

function preflightBase(): BillingPreflight {
  return {
    os: { id: 'os-1', numero: 'OS-00099', status: 'completed', invoicing_status: null, grand_total: 3500 },
    ambiente: 'homologacao',
    nfse: {
      aplicavel: true,
      pronto: true,
      resumo: { servicos_na_nota: 2, total_servicos: 2000, codigo_de_tributacao: '140101', origem_do_codigo: 'verbo' },
    },
    nfe: {
      aplicavel: true,
      pronto: true,
      resumo: { pecas_na_nota: 3, total_pecas: 1500, itens_ignorados_sem_cadastro: 0 },
    },
    documentos: [],
  };
}

// Os verbos fiscais alimentam o seletor da linha avulsa. Referência ESTÁVEL:
// objeto novo a cada chamada põe os efeitos do diálogo em laço.
vi.mock('@/hooks/use-service-fiscal', async (importOriginal) => {
  const real = await importOriginal<typeof import('@/hooks/use-service-fiscal')>();
  const verbos = {
    data: [
      { verb_slug: 'instalacao', name: 'Instalação', default_national_tax_code: '140101' },
      // Verbo SEM código não pode ser oferecido: herdar dele não produziria nota.
      { verb_slug: 'logistica', name: 'Logística', default_national_tax_code: null },
    ],
  };
  return { ...real, useServiceFiscalVerbs: () => verbos };
});

vi.mock('@/hooks/use-faturar-os', async (importOriginal) => {
  const real = await importOriginal<typeof import('@/hooks/use-faturar-os')>();
  const gravarVerbo = { mutate: vi.fn(), isPending: false };
  return {
    ...real,
    useBillingPreflight: () => ({
      data: estado.preflight,
      isLoading: estado.preflight === null,
      isFetching: false,
      error: null,
      refetch: vi.fn(),
    }),
    useEmitirNfeDaOs: () => ({ mutateAsync: emitirNfeMock, isPending: false }),
    useSetLineFiscalVerb: () => gravarVerbo,
    atualizarInvoicingStatus: vi.fn(),
  };
});

// Os popups de cadastro são árvores pesadas (hooks próprios de produtos/serviços) — aqui
// interessa só SE o assistente os abre; stubs mantêm o smoke rápido e isolado.
vi.mock('@/components/ServiceFormDialog', () => ({
  ServiceFormDialog: ({ open }: { open: boolean }) => (open ? <div data-testid="popup-servico" /> : null),
}));
vi.mock('@/components/ProductFormDialog', () => ({
  ProductFormDialog: ({ open }: { open: boolean }) => (open ? <div data-testid="popup-produto" /> : null),
}));

vi.mock('@/hooks/use-nfse', async (importOriginal) => {
  const real = await importOriginal<typeof import('@/hooks/use-nfse')>();
  return {
    ...real,
    useNfseHealth: () => ({
      data: { pronto: estado.healthPronto, pendencias_locais: [], contora: { pending: [] } },
      isLoading: false,
      error: null,
    }),
    useEmitirNfse: () => ({ mutateAsync: emitirNfseMock, isPending: false }),
  };
});

function renderDialog() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <MemoryRouter>
      <QueryClientProvider client={qc}>
        <I18nProvider>
          <FaturarOsDialog open onOpenChange={() => {}} serviceOrderId="os-1" orderNumber="OS-00099" />
        </I18nProvider>
      </QueryClientProvider>
    </MemoryRouter>,
  );
}

describe('assistente Faturar OS', () => {
  afterEach(() => {
    emitirNfseMock.mockClear();
    emitirNfeMock.mockClear();
    estado.preflight = null;
    estado.healthPronto = true;
  });

  it('abre com os dois cartões e explica a separação serviço×peça', async () => {
    estado.preflight = preflightBase();
    renderDialog();
    expect(await screen.findByText(/Faturar OS OS-00099/)).toBeInTheDocument();
    expect(screen.getByText(/NFS-e — serviços/)).toBeInTheDocument();
    expect(screen.getByText(/NF-e — peças/)).toBeInTheDocument();
    expect(screen.getByText(/dois documentos/)).toBeInTheDocument();
  });

  it('com tudo pronto, o botão único oferece os DOIS documentos', async () => {
    estado.preflight = preflightBase();
    renderDialog();
    const botao = await screen.findByRole('button', { name: /Emitir NFS-e \+ NF-e/ });
    expect(botao).toBeEnabled();
  });

  it('documento que não se aplica é dito, não escondido', async () => {
    const p = preflightBase();
    p.nfe = { aplicavel: false, pronto: false, motivo: 'A OS não tem peças de catálogo.' };
    estado.preflight = p;
    renderDialog();
    expect(await screen.findByText(/não se aplica/)).toBeInTheDocument();
    expect(screen.getByText(/não tem peças de catálogo/)).toBeInTheDocument();
    // E o botão passa a oferecer só o que existe.
    expect(screen.getByRole('button', { name: /^Emitir NFS-e$/ })).toBeEnabled();
  });

  it('pendência de cadastro lista QUAIS serviços faltam', async () => {
    const p = preflightBase();
    p.nfse = {
      aplicavel: true,
      pronto: false,
      erro: 'Serviço sem cadastro fiscal: "Instalação LiFePO4".',
      details: { servicos_sem_cadastro: ['Instalação LiFePO4'] },
    };
    estado.preflight = p;
    renderDialog();
    expect(await screen.findByText(/Serviço sem cadastro fiscal/)).toBeInTheDocument();
    expect(screen.getByText('Instalação LiFePO4')).toBeInTheDocument();
  });

  // O caminho do CATÁLOGO: tem cadastro para abrir, então abre o cadastro.
  // O caminho da LINHA DIGITADA À MÃO: não tem cadastro nenhum, então o verbo
  // fiscal vai na própria linha — ali mesmo, sem sair do assistente.
  //
  // Antes desta versão o segundo caso recebia só o texto "linha avulsa —
  // vincule ao catálogo na OS", e vincular não existia em lugar nenhum do
  // sistema: 33 linhas em 10 ordens presas, R$ 2.525 sem virar nota.
  it('pendência ACIONÁVEL: catálogo abre o cadastro; linha avulsa regulariza aqui', async () => {
    const p = preflightBase();
    p.nfse = {
      aplicavel: true,
      pronto: false,
      erro: 'Serviço sem cadastro fiscal.',
      details: {
        servicos_pendentes: [
          { service_id: 'svc-1', name: 'Instalação LiFePO4' },
          { service_id: null, line_id: 'linha-1', name: 'Linha digitada à mão' },
        ],
      },
    };
    estado.preflight = p;
    renderDialog();
    expect(await screen.findByRole('button', { name: /Corrigir cadastro/ })).toBeInTheDocument();
    // A linha avulsa ganha o seletor de tipo e o Aplicar — não um texto morto.
    expect(screen.getByText(/Tipo de serviço/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Aplicar/ })).toBeInTheDocument();
    expect(screen.queryByText(/vincule ao catálogo/)).not.toBeInTheDocument();
  });

  // Edge antigo (sem `line_id`): a tela não pode oferecer um controle que não
  // gravaria nada. Degrada para texto, e o texto diz o que fazer.
  it('sem line_id, degrada para texto em vez de oferecer um botão morto', async () => {
    const p = preflightBase();
    p.nfse = {
      aplicavel: true,
      pronto: false,
      erro: 'Serviço sem cadastro fiscal.',
      details: { servicos_pendentes: [{ service_id: null, name: 'Linha antiga' }] },
    };
    estado.preflight = p;
    renderDialog();
    expect(await screen.findByText(/atualize o sistema para regularizar/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Aplicar/ })).not.toBeInTheDocument();
  });

  it('produto com NCM pendente ganha "Corrigir cadastro" no cartão da NF-e', async () => {
    const p = preflightBase();
    p.nfe = {
      aplicavel: true,
      pronto: false,
      erro: 'NCM obrigatório.',
      details: { produtos_pendentes: [{ product_id: 'prod-1', name: 'Bateria LiFePO4 100Ah', faltas: ['NCM (8 dígitos)'] }] },
    };
    estado.preflight = p;
    renderDialog();
    expect(await screen.findByText(/Produtos com cadastro fiscal incompleto/)).toBeInTheDocument();
    expect(screen.getByText(/Bateria LiFePO4 100Ah/)).toBeInTheDocument();
    expect(screen.getAllByRole('button', { name: /Corrigir cadastro/ }).length).toBeGreaterThan(0);
  });

  it('NFS-e não emite com a conta da Contora sem verde, mesmo com payload pronto', async () => {
    estado.preflight = preflightBase();
    estado.healthPronto = false;
    renderDialog();
    // Sobra só a NF-e no botão — a NFS-e fica retida pelo pré-voo da conta.
    expect(await screen.findByRole('button', { name: /^Emitir NF-e$/ })).toBeEnabled();
  });

  it('nota viva já emitida desarma a emissão daquele documento', async () => {
    const p = preflightBase();
    p.documentos = [{
      id: 'd1', document_type: 'nfse', status: 'authorized', number: 7, series: 1,
      environment: 'homologacao', status_message: null, created_at: '2026-08-13T10:00:00Z',
    }];
    estado.preflight = p;
    renderDialog();
    expect(await screen.findByText(/emitida — nº 7/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /^Emitir NF-e$/ })).toBeEnabled();
  });

  it('produção grita, homologação não', async () => {
    const p = preflightBase();
    p.ambiente = 'producao';
    estado.preflight = p;
    renderDialog();
    expect(await screen.findByText(/PRODUÇÃO — os documentos emitidos aqui são notas reais/)).toBeInTheDocument();
  });
});
