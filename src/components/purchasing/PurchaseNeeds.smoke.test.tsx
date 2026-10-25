// Smoke de render da faixa e do diálogo de compras com o que vem a caminho (Agenda de Produção, Fase 0,
// P5 — 24/10/2026). O caso é a OS-00104 depois das migrations: nada falta comprar, mas o compressor ainda
// está na OC-00004. A faixa não pode sumir e o diálogo não pode dizer "Tudo disponível para executar".
//
// Revisão de 23/10/2026: com a leitura em erro (ex.: o front publicado antes da view v_oc_itens_a_caminho),
// o diálogo dizia "Tudo disponível para executar" e a faixa sumia. Agora os dois dizem que não conferiram.
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { act, fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import type { ReactNode } from 'react';
import type { PurchaseNeeds } from '@/lib/purchase-needs';

const estado = vi.hoisted(() => ({
  needs: undefined as PurchaseNeeds | undefined,
  erro: false,
  refetch: (() => {}) as () => void,
  criarOCs: vi.fn(async (_p: unknown) => {}),
}));

vi.mock('@/hooks/use-purchase-needs', () => ({
  usePurchaseNeeds: () => ({
    data: estado.needs, isLoading: false, isError: estado.erro, isFetching: false, refetch: estado.refetch,
  }),
}));

beforeEach(() => {
  estado.erro = false;
  estado.refetch = () => {};
  estado.criarOCs.mockClear();
});
vi.mock('@/hooks/use-quote-requests', () => ({ useSOLinkedQuotes: () => ({ data: [] }) }));
vi.mock('@/hooks/use-purchase-orders', () => ({
  useCreatePOsFromShortages: () => ({ mutateAsync: estado.criarOCs, isPending: false }),
}));
vi.mock('@/components/purchasing/NewQuoteRequestDialog', () => ({ NewQuoteRequestDialog: () => null }));

import { PurchaseNeedsBanner } from './PurchaseNeedsBanner';
import { PurchaseNeedsDialog } from './PurchaseNeedsDialog';

const OS104: PurchaseNeeds = {
  serviceOrderId: 'os-104',
  items: [{
    sourceId: 'poi-1', origin: 'purchase_order', productId: null, description: 'Compressor 12V de geladeira SS65',
    unit: null, required: 1, available: 0, onOrder: 1, shortage: 0, status: 'on_order', unitCost: 0,
    purchaseOrderNumber: 'OC-00004',
  }],
  shortages: [],
  shortageCount: 0,
  estimatedCost: 0,
  needsPurchase: false,
};

const comRota = (ui: ReactNode) => render(<MemoryRouter>{ui}</MemoryRouter>);

describe('faixa de compras da OS', () => {
  it('nada a comprar mas algo a caminho: a faixa fica e diz a OC', () => {
    estado.needs = OS104;
    comRota(<PurchaseNeedsBanner serviceOrderId="os-104" serviceOrderNumber="OS-00104" status="awaiting_parts" />);
    expect(screen.getByText('1 item a caminho')).toBeTruthy();
    expect(screen.getByText(/pedido na OC-00004, chegou\?/)).toBeTruthy();
    expect(screen.queryByText(/precisa de compra/)).toBeNull();
  });

  it('nada a comprar e nada a caminho: a faixa some (como antes)', () => {
    estado.needs = { ...OS104, items: [] };
    const { container } = comRota(
      <PurchaseNeedsBanner serviceOrderId="os-104" serviceOrderNumber="OS-00104" status="awaiting_parts" />,
    );
    expect(container.textContent).toBe('');
  });

  it('a conta não carregou: a faixa não some, diz que não conferiu e deixa tentar de novo', () => {
    estado.needs = undefined;
    estado.erro = true;
    const refetch = vi.fn();
    estado.refetch = refetch;
    comRota(<PurchaseNeedsBanner serviceOrderId="os-104" serviceOrderNumber="OS-00104" status="awaiting_parts" />);
    expect(screen.getByText('Não consegui conferir as compras desta OS.')).toBeTruthy();
    fireEvent.click(screen.getByText('Tentar de novo'));
    expect(refetch).toHaveBeenCalledTimes(1);
  });
});

describe('diálogo de compras', () => {
  it('não diz "Tudo disponível" com o compressor a caminho; a linha diz a OC e pergunta se chegou', () => {
    estado.needs = OS104;
    comRota(<PurchaseNeedsDialog open onOpenChange={() => {}} serviceOrderId="os-104" serviceOrderNumber="OS-00104" />);
    expect(screen.getByText('Nada a comprar — 1 item a caminho')).toBeTruthy();
    expect(screen.queryByText('Tudo disponível para executar')).toBeNull();
    expect(screen.getByText(/pedido na OC-00004 — chegou\?/)).toBeTruthy();
    expect(screen.queryByText(/disponível 0/)).toBeNull();
  });

  it('sem nada a caminho continua "Tudo disponível para executar"', () => {
    estado.needs = { ...OS104, items: [] };
    comRota(<PurchaseNeedsDialog open onOpenChange={() => {}} serviceOrderId="os-104" serviceOrderNumber="OS-00104" />);
    expect(screen.getByText('Tudo disponível para executar')).toBeTruthy();
  });

  it('a conta não carregou: NÃO diz "Tudo disponível"; diz que não conferiu e deixa tentar de novo', () => {
    estado.needs = undefined;
    estado.erro = true;
    const refetch = vi.fn();
    estado.refetch = refetch;
    comRota(<PurchaseNeedsDialog open onOpenChange={() => {}} serviceOrderId="os-104" serviceOrderNumber="OS-00104" />);
    expect(screen.getByText('Não consegui conferir o estoque')).toBeTruthy();
    expect(screen.queryByText('Tudo disponível para executar')).toBeNull();
    expect(screen.queryByText(/Nenhuma peça em falta/)).toBeNull();
    expect(screen.queryByText(/não tem peça nem material/)).toBeNull();
    fireEvent.click(screen.getByText('Tentar de novo'));
    expect(refetch).toHaveBeenCalledTimes(1);
  });
});

// Agenda de Produção, Fase 4 (P2): o texto livre com OC ligada (um item só: a caminho pela OC, ou já recebido) e o
// material que o dono citou e não está no orçamento (sem preço).
const LIGADO_E_CITADO: PurchaseNeeds = {
  serviceOrderId: 'os-l',
  items: [
    {
      sourceId: 'sos-1', origin: 'free_text', productId: null, description: 'Cabo PP 2x2,5mm', unit: null, required: 10,
      available: 0, onOrder: 10, shortage: 0, status: 'on_order', unitCost: 12, purchaseOrderNumber: 'OC-00020',
    },
    {
      sourceId: 'sos-2', origin: 'free_text', productId: null, description: 'Bomba de porão 12V', unit: null, required: 2,
      available: 2, onOrder: 0, shortage: 0, status: 'ok', unitCost: 300, purchaseOrderNumber: 'OC-00021',
    },
    {
      sourceId: 'om-1', origin: 'dono', productId: null, description: 'Parafusos inox do suporte', unit: null, required: 12,
      available: 0, onOrder: 0, shortage: 12, status: 'uncatalogued', unitCost: 0, semPreco: true,
    },
    {
      sourceId: 'sop-1', origin: 'part', productId: 'p1', description: 'Fusível MIDI 100A', unit: 'un', required: 2,
      available: 0, onOrder: 0, shortage: 2, status: 'missing', unitCost: 30,
    },
  ],
  shortages: [],
  shortageCount: 2,
  estimatedCost: 60,
  needsPurchase: true,
  semPreco: 1,
};
LIGADO_E_CITADO.shortages = [LIGADO_E_CITADO.items[3], LIGADO_E_CITADO.items[2]];

describe('Fase 4 (P2): OC ligada ao texto livre e o material citado pelo dono', () => {
  it('diálogo: o texto livre ligado diz a OC (a caminho ou chegou), sem "disponível"; o citado diz "sem preço"; o custo diz quantos ficaram fora', () => {
    estado.needs = LIGADO_E_CITADO;
    comRota(<PurchaseNeedsDialog open onOpenChange={() => {}} serviceOrderId="os-l" serviceOrderNumber="OS-00120" />);
    expect(screen.getByText('2 itens precisam de compra')).toBeTruthy();
    expect(screen.getByText(/pedido na OC-00020 — chegou\?/)).toBeTruthy();
    expect(screen.getByText(/chegou pela OC-00021/)).toBeTruthy();
    expect(screen.getByText(/citado por você \(sem preço\)/)).toBeTruthy();
    expect(screen.getByText(/Fora 1 item citado por você, sem preço\./)).toBeTruthy();
    // O texto livre ligado não mostra "disponível 0" (diria que falta).
    expect(screen.queryByText(/precisa 10 · disponível/)).toBeNull();
  });

  // Revisão da Fase 4, C2 (R1): o citado não tem linha da OS a que ligar — na OC ele nasceria sem vínculo e com R$ 0, e a
  // falta continuaria (o botão geraria outra OC). Fica fora de "Gerar ordem de compra" e de "Cotar", com o aviso.
  it('diálogo: o citado pelo dono fica fora de "Gerar ordem de compra" e de "Cotar", com o aviso de dizer "comprei"', async () => {
    estado.needs = LIGADO_E_CITADO;
    comRota(<PurchaseNeedsDialog open onOpenChange={() => {}} serviceOrderId="os-l" serviceOrderNumber="OS-00120" />);
    expect(screen.getByText('Cotar 1 item')).toBeTruthy();
    expect(screen.getByText(/O item citado por você fica fora da ordem de compra e da cotação: ele não está no orçamento\./)).toBeTruthy();
    expect(screen.getByText(/Quando comprar, diga “comprei” ao assistente, ou ponha no orçamento\./)).toBeTruthy();
    await act(async () => { fireEvent.click(screen.getByText('Gerar ordem de compra')); });
    expect(estado.criarOCs).toHaveBeenCalledTimes(1);
    const pedido = estado.criarOCs.mock.calls[0][0] as { items: Array<{ description: string; serviceOrderPartId: string | null }> };
    expect(pedido.items.map((i) => i.description)).toEqual(['Fusível MIDI 100A']);
    expect(pedido.items[0].serviceOrderPartId).toBe('sop-1');
  });

  it('diálogo: só o citado em falta — sem "Gerar ordem de compra" nem "Cotar"; o título ainda diz que precisa de compra', () => {
    const so = LIGADO_E_CITADO.items[2];
    estado.needs = { ...LIGADO_E_CITADO, items: [so], shortages: [so], shortageCount: 1, estimatedCost: 0 };
    comRota(<PurchaseNeedsDialog open onOpenChange={() => {}} serviceOrderId="os-l" serviceOrderNumber="OS-00120" />);
    expect(screen.getByText('1 item precisa de compra')).toBeTruthy();
    expect(screen.queryByText('Gerar ordem de compra')).toBeNull();
    expect(screen.queryByText(/^Cotar/)).toBeNull();
    expect(screen.getByText(/O item citado por você fica fora da ordem de compra e da cotação/)).toBeTruthy();
  });

  it('faixa: o citado na lista do que falta diz "citado por você (sem preço)"; o ligado aparece a caminho com a OC', () => {
    estado.needs = LIGADO_E_CITADO;
    comRota(<PurchaseNeedsBanner serviceOrderId="os-l" serviceOrderNumber="OS-00120" status="awaiting_parts" />);
    expect(screen.getByText('2 itens precisam de compra')).toBeTruthy();
    expect(screen.getByText(/citado por você \(sem preço\)/)).toBeTruthy();
    expect(screen.getByText(/pedido na OC-00020, chegou\?/)).toBeTruthy();
  });
});
