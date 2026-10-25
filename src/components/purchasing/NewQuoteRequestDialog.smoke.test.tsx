// Smoke de render da nova cotação aberta de uma OS (revisão da Fase 4, C2, R1 — 25/10/2026). O material que o dono citou
// e não está no orçamento (origem 'dono') não tem linha da OS a que ligar: na cotação, e na OC que sai dela, ele nasceria
// sem vínculo e a falta continuaria. Ele fica fora dos itens a cotar, com o aviso de dizer "comprei" ao assistente.
import { describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import type { PurchaseNeeds } from '@/lib/purchase-needs';

const estado = vi.hoisted(() => ({ needs: null as PurchaseNeeds | null }));

vi.mock('@/hooks/use-purchase-needs', () => ({ fetchPurchaseNeeds: async () => estado.needs }));
vi.mock('@/hooks/use-suppliers', () => ({ useSuppliers: () => ({ data: [] }) }));
vi.mock('@/hooks/use-quote-requests', () => ({ useCreateQuoteRequest: () => ({ mutateAsync: vi.fn(), isPending: false }) }));

import { NewQuoteRequestDialog } from './NewQuoteRequestDialog';

const item = (sourceId: string, origin: 'part' | 'free_text' | 'dono', description: string, shortage: number) => ({
  sourceId, origin, productId: origin === 'part' ? 'p1' : null, description, unit: null, required: shortage, available: 0,
  onOrder: 0, shortage, status: origin === 'part' ? 'missing' as const : 'uncatalogued' as const, unitCost: origin === 'dono' ? 0 : 30,
  ...(origin === 'dono' ? { semPreco: true } : {}),
});

describe('nova cotação a partir da OS', () => {
  it('o material citado pelo dono fica fora dos itens a cotar, com o aviso', async () => {
    const itens = [
      item('sop-1', 'part', 'Fusível MIDI 100A', 2),
      item('sos-1', 'free_text', 'Cabo PP 2x2,5mm', 10),
      item('om-1', 'dono', 'Parafusos inox do suporte', 12),
    ];
    estado.needs = {
      serviceOrderId: 'os-l', items: itens, shortages: itens, shortageCount: 3, estimatedCost: 360, needsPurchase: true, semPreco: 1,
    };
    render(<MemoryRouter><NewQuoteRequestDialog open onOpenChange={() => {}} serviceOrderId="os-l" serviceOrderLabel="OS-00120" /></MemoryRouter>);
    expect(await screen.findByDisplayValue('Fusível MIDI 100A')).toBeTruthy();
    expect(screen.getByDisplayValue('Cabo PP 2x2,5mm')).toBeTruthy();
    expect(screen.queryByDisplayValue('Parafusos inox do suporte')).toBeNull();
    expect(screen.getByText(/O item citado por você ficou fora: ele não está no orçamento\./)).toBeTruthy();
    expect(screen.getByText(/Quando comprar, diga “comprei” ao assistente, ou ponha no orçamento\./)).toBeTruthy();
    expect(screen.getByText('Criar cotação (2)')).toBeTruthy();
  });

  it('sem citado, nenhum aviso (como antes)', async () => {
    const itens = [item('sop-1', 'part', 'Fusível MIDI 100A', 2)];
    estado.needs = { serviceOrderId: 'os-l', items: itens, shortages: itens, shortageCount: 1, estimatedCost: 60, needsPurchase: true };
    render(<MemoryRouter><NewQuoteRequestDialog open onOpenChange={() => {}} serviceOrderId="os-l" serviceOrderLabel="OS-00120" /></MemoryRouter>);
    expect(await screen.findByDisplayValue('Fusível MIDI 100A')).toBeTruthy();
    expect(screen.queryByText(/citado por você/)).toBeNull();
  });
});
