// "Pedir confirmação" (30/09/2026). O que se protege: nada sai sem o segundo clique, o pedido vai
// pela função do banco (que confere agendamento, telefone, opt-out e modo de teste) e o recusado
// aparece com o motivo do banco.
// Agenda de Produção, Fase 5 (P6): o texto do diálogo diz o que acontece de fato — pela agenda (no horário de mensagens
// ao cliente) com a confirmação ligada nas ondas; na hora, como antes, fora disso; os dois quando a tela não lê o modo.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';

const banco = vi.hoisted(() => ({
  chamadas: [] as Array<{ nome: string; args: unknown }>,
  resposta: { data: { ok: true, message: 'Pedido de confirmação enviado a João.' }, error: null } as { data: unknown; error: unknown },
  toasts: [] as string[],
  config: { data: null, error: null } as { data: unknown; error: unknown },
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    rpc: async (nome: string, args: unknown) => { banco.chamadas.push({ nome, args }); return banco.resposta; },
    from: () => ({ select: () => ({ maybeSingle: async () => banco.config }) }),
  },
}));
vi.mock('sonner', () => ({
  toast: { success: (m: string) => banco.toasts.push(m), error: (m: string) => banco.toasts.push(`erro: ${m}`) },
}));

import { PedirConfirmacaoButton, lerComoSaiAConfirmacao, textoDoPedido } from './PedirConfirmacaoButton';

beforeEach(() => {
  banco.chamadas = [];
  banco.toasts = [];
  banco.config = { data: { modo_cliente: 'desligado', cliente_tipos_ligados: [] }, error: null };
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

  it('o diálogo diz o que acontece: pela agenda com a confirmação ligada nas ondas; na hora fora disso', async () => {
    banco.config = { data: { modo_cliente: 'ligado', cliente_tipos_ligados: ['material_chegou', 'confirmar'] }, error: null };
    const a = render(<PedirConfirmacaoButton osId="os-3" />);
    fireEvent.click(screen.getByRole('button', { name: /Pedir confirmação/ }));
    expect(await screen.findByText(/^A confirmação ao cliente agora é da agenda/)).toBeInTheDocument();
    expect(screen.queryByText(/^Vai agora/)).not.toBeInTheDocument();
    expect(banco.chamadas).toEqual([]);
    a.unmount();

    banco.config = { data: { modo_cliente: 'sombra', cliente_tipos_ligados: [] }, error: null };
    render(<PedirConfirmacaoButton osId="os-4" />);
    fireEvent.click(screen.getByRole('button', { name: /Pedir confirmação/ }));
    expect(await screen.findByText(/estão em teste, mas este pedido sai de verdade/)).toBeInTheDocument();
  });

  it('o modo: ligado sem a confirmação nas ondas, desligado, a Fase 5 ausente = na hora; sem linha ou erro = os dois', async () => {
    const db = (r: { data: unknown; error: unknown }) => ({ from: () => ({ select: () => ({ maybeSingle: async () => r }) }) });
    expect(await lerComoSaiAConfirmacao(db({ data: { modo_cliente: 'ligado', cliente_tipos_ligados: ['pronto'] }, error: null })))
      .toBe('agora_sem_onda');
    expect(await lerComoSaiAConfirmacao(db({ data: { modo_cliente: 'desligado', cliente_tipos_ligados: ['confirmar'] }, error: null })))
      .toBe('agora');
    expect(await lerComoSaiAConfirmacao(db({ data: null, error: { code: '42703', message: 'column does not exist' } }))).toBe('agora');
    expect(await lerComoSaiAConfirmacao(db({ data: null, error: { code: 'PGRST205', message: 'not found' } }))).toBe('agora');
    expect(await lerComoSaiAConfirmacao(db({ data: null, error: null }))).toBe('nao_sei');
    expect(await lerComoSaiAConfirmacao(db({ data: null, error: { code: '500', message: 'x' } }))).toBe('nao_sei');
    expect(await lerComoSaiAConfirmacao({})).toBe('nao_sei');
    expect(textoDoPedido('agora')).toMatch(/^Vai agora, pelo WhatsApp da HBR/);
    expect(textoDoPedido('nao_sei')).toMatch(/na hora, ou no próximo horário de mensagens ao cliente/);
  });
});
