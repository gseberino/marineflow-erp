// Smoke de render da faixa e do diálogo de compras com o que vem a caminho (Agenda de Produção, Fase 0,
// P5 — 24/10/2026). O caso é a OS-00104 depois das migrations: nada falta comprar, mas o compressor ainda
// está na OC-00004. A faixa não pode sumir e o diálogo não pode dizer "Tudo disponível para executar".
//
// Revisão de 23/10/2026: com a leitura em erro (ex.: o front publicado antes da view v_oc_itens_a_caminho),
// o diálogo dizia "Tudo disponível para executar" e a faixa sumia. Agora os dois dizem que não conferiram.
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import type { ReactNode } from 'react';
import type { PurchaseNeeds } from '@/lib/purchase-needs';

const estado = vi.hoisted(() => ({
  needs: undefined as PurchaseNeeds | undefined,
  erro: false,
  refetch: (() => {}) as () => void,
}));

vi.mock('@/hooks/use-purchase-needs', () => ({
  usePurchaseNeeds: () => ({
    data: estado.needs, isLoading: false, isError: estado.erro, isFetching: false, refetch: estado.refetch,
  }),
}));

beforeEach(() => {
  estado.erro = false;
  estado.refetch = () => {};
});
vi.mock('@/hooks/use-quote-requests', () => ({ useSOLinkedQuotes: () => ({ data: [] }) }));
vi.mock('@/hooks/use-purchase-orders', () => ({
  useCreatePOsFromShortages: () => ({ mutateAsync: async () => {}, isPending: false }),
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
