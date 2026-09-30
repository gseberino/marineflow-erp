// "Pedir confirmação" (30/09/2026). O que se protege: nada sai sem o segundo clique, o pedido vai
// pela função do banco (que confere agendamento, telefone, opt-out e modo de teste) e o recusado
// aparece com o motivo do banco.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';

const banco = vi.hoisted(() => ({
  chamadas: [] as Array<{ nome: string; args: unknown }>,
  resposta: { data: { ok: true, message: 'Pedido de confirmação enviado a João.' }, error: null } as { data: unknown; error: unknown },
  toasts: [] as string[],
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    rpc: async (nome: string, args: unknown) => { banco.chamadas.push({ nome, args }); return banco.resposta; },
  },
}));
vi.mock('sonner', () => ({
  toast: { success: (m: string) => banco.toasts.push(m), error: (m: string) => banco.toasts.push(`erro: ${m}`) },
}));

import { PedirConfirmacaoButton } from './PedirConfirmacaoButton';

beforeEach(() => {
  banco.chamadas = [];
  banco.toasts = [];
  banco.resposta = { data: { ok: true, message: 'Pedido de confirmação enviado a João.' }, error: null };
});

describe('PedirConfirmacaoButton', () => {
  it('abre a confirmação e só envia no segundo clique, pela função do banco', async () => {
    render(<PedirConfirmacaoButton osId="os-1" />);
    fireEvent.click(screen.getByRole('button', { name: /Pedir confirmação/ }));
    expect(banco.chamadas).toEqual([]);
    fireEvent.click(screen.getByRole('button', { name: 'Enviar pedido' }));
    await waitFor(() => expect(banco.toasts).toContain('Pedido de confirmação enviado a João.'));
    expect(banco.chamadas).toEqual([{ nome: 'pedir_confirmacao_do_agendamento', args: { p_os: 'os-1' } }]);
  });

  it('recusa do banco (opt-out, sem telefone…) aparece com o motivo', async () => {
    banco.resposta = { data: null, error: { message: 'Este cliente pediu para não receber WhatsApp: confirme por telefone.' } };
    render(<PedirConfirmacaoButton osId="os-2" />);
    fireEvent.click(screen.getByRole('button', { name: /Pedir confirmação/ }));
    fireEvent.click(screen.getByRole('button', { name: 'Enviar pedido' }));
    await waitFor(() => expect(banco.toasts).toContain('erro: Este cliente pediu para não receber WhatsApp: confirme por telefone.'));
  });
});
