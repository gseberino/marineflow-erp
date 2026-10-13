// Prospecção ativa: o orçamento parado é citado pelo número, que já traz o prefixo ("ORÇ-00112").
// Até 12/10/2026 a tela punha "OS #" na frente: o cartão dizia "OS #ORÇ-00112", o pedido à IA
// "um orçamento (OS #ORÇ-00112)" e o rascunho que vai AO CLIENTE "o orçamento da sua OS #ORÇ-00112".
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';

const banco = vi.hoisted(() => ({
  pedidosAIA: [] as Array<{ nome: string; body: { messages: { content: string }[] } }>,
  orcamento: {
    id: 'so-1',
    service_order_number: 'ORÇ-00112',
    status: 'draft',
    grand_total: 1500,
    created_at: '2026-10-01T12:00:00Z',
    clients: { name: 'Ana Souza', phone: '5547999990000', whatsapp: null },
  },
}));

vi.mock('@/integrations/supabase/client', () => {
  const q: Record<string, unknown> = {};
  for (const m of ['select', 'eq', 'lte', 'order']) q[m] = () => q;
  q.limit = async () => ({ data: [banco.orcamento], error: null });
  return {
    supabase: {
      from: () => q,
      functions: {
        // A IA falha: o rascunho que fica é o de reserva da própria tela.
        invoke: async (nome: string, opcoes: { body: { messages: { content: string }[] } }) => {
          banco.pedidosAIA.push({ nome, body: opcoes.body });
          return { data: null, error: new Error('fora do ar') };
        },
      },
    },
  };
});
vi.mock('@/hooks/use-whatsapp-inbox', () => ({
  useSendWhatsAppText: () => ({ mutateAsync: async () => {}, isPending: false }),
}));
vi.mock('@/components/agenda/RevisoesPreventivas', () => ({ RevisoesPreventivas: () => null }));
vi.mock('sonner', () => ({ toast: { success: () => {}, error: () => {} } }));

import ActiveProspectingPage from './ActiveProspectingPage';

beforeEach(() => {
  banco.pedidosAIA = [];
  vi.spyOn(console, 'error').mockImplementation(() => {});
});

describe('ActiveProspectingPage — número do orçamento sem "OS #" na frente', () => {
  it('o cartão mostra o número como vem', async () => {
    render(<ActiveProspectingPage />);
    expect(await screen.findByText('ORÇ-00112')).toBeInTheDocument();
    expect(screen.queryByText(/OS #/)).toBeNull();
  });

  it('o pedido à IA e o rascunho ao cliente citam "ORÇ-00112" sem "OS #"', async () => {
    render(<ActiveProspectingPage />);
    fireEvent.click(await screen.findByRole('button', { name: /Criar Abordagem com IA/ }));

    await waitFor(() => expect(banco.pedidosAIA).toHaveLength(1));
    const pedido = banco.pedidosAIA[0].body.messages[0].content;
    expect(pedido).toContain('um orçamento (ORÇ-00112) de');
    expect(pedido).not.toContain('OS #');

    const rascunho = (await screen.findByRole('textbox')) as HTMLTextAreaElement;
    await waitFor(() => expect(rascunho.value).toContain('o seu orçamento ORÇ-00112.'));
    expect(rascunho.value).not.toContain('OS #');
  });
});
