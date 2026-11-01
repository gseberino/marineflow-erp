// Lista de bloqueio (Retorno F0b, 06/11/2026): o número que pediu PARAR (tipo opt_out) aparece como
// tal, e desbloqueá-lo pede confirmação — ele voltaria a receber o automático que pediu para parar.
// O spam desbloqueia num clique, como antes. Render de verdade: tsc não pega erro de render.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

const { removido, linhas } = vi.hoisted(() => ({
  removido: [] as string[],
  linhas: [
    { id: 'b1', phone_normalized: '5547900009001', reason: 'Pediu para parar pelo WhatsApp em 06/11/2026 09:12', tipo: 'opt_out' },
    { id: 'b2', phone_normalized: '5547900009002', reason: 'lista de transmissão', tipo: 'spam' },
  ],
}));

vi.mock('@/hooks/use-whatsapp-inbox', async (original) => ({
  ...(await original<Record<string, unknown>>()),
  useBlockedNumbers: () => ({ data: linhas, isLoading: false }),
  useAddBlockedNumber: () => ({ mutateAsync: async () => {}, isPending: false }),
  useRemoveBlockedNumber: () => ({ mutate: (id: string) => removido.push(id) }),
}));

import { BlocklistView } from './WhatsAppLeadsPage';

describe('lista de bloqueio: opt-out × spam', () => {
  beforeEach(() => { removido.length = 0; });

  it('marca quem pediu para parar e só desbloqueia depois de confirmar', async () => {
    render(<BlocklistView />);
    expect(screen.getAllByText('Pediu para parar')).toHaveLength(1);
    const botoes = screen.getAllByRole('button', { name: /Desbloquear/ });
    await userEvent.click(botoes[0]);
    expect(removido).toEqual([]);
    expect(screen.getByText('Desbloquear quem pediu para parar?')).toBeTruthy();
    await userEvent.click(screen.getByRole('button', { name: 'Desbloquear mesmo assim' }));
    expect(removido).toEqual(['b1']);
  });

  it('o spam desbloqueia num clique', async () => {
    render(<BlocklistView />);
    await userEvent.click(screen.getAllByRole('button', { name: /Desbloquear/ })[1]);
    expect(removido).toEqual(['b2']);
    expect(screen.queryByText('Desbloquear quem pediu para parar?')).toBeNull();
  });
});
