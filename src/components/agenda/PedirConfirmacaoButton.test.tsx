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
  toast: {
    success: (m: string) => banco.toasts.push(m),
    error: (m: string) => banco.toasts.push(`erro: ${m}`),
    info: (m: string) => banco.toasts.push(`info: ${m}`),
  },
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

// Correção C1 da Fase 5 (27/10/2026): o banco responde na hora o que antes ficava calado até a manhã seguinte (o cliente
// que não escreveu para a HBR, o teto, o caminho antigo fora do horário) e diz quando a confirmação já estava com a agenda
// (já mandada, na fila, indo sair sozinha) — esse aviso é neutro, não "enviado".
describe('PedirConfirmacaoButton (correção C1 da Fase 5)', () => {
  it('a confirmação que já estava com a agenda aparece como aviso neutro, não como enviada', async () => {
    banco.resposta = {
      data: { ok: true, agenda: true, nada_feito: true, message: 'Já mandei a confirmação de qua 04/11 para Flávio (sex 30/10 às 10:00).' },
      error: null,
    };
    render(<PedirConfirmacaoButton osId="os-5" />);
    fireEvent.click(screen.getByRole('button', { name: /Pedir confirmação/ }));
    fireEvent.click(screen.getByRole('button', { name: 'Enviar pedido' }));
    await waitFor(() => expect(banco.toasts).toContain('info: Já mandei a confirmação de qua 04/11 para Flávio (sex 30/10 às 10:00).'));
    expect(banco.toasts.some((t) => !t.startsWith('info: '))).toBe(false);
  });

  it('o clique que aprovou a confirmação que esperava o dono aparece como feito', async () => {
    banco.resposta = { data: { ok: true, agenda: true, aprovou: true, message: 'Mando para Rodrigo amanhã às 09:00.' }, error: null };
    render(<PedirConfirmacaoButton osId="os-6" />);
    fireEvent.click(screen.getByRole('button', { name: /Pedir confirmação/ }));
    fireEvent.click(screen.getByRole('button', { name: 'Enviar pedido' }));
    await waitFor(() => expect(banco.toasts).toContain('Mando para Rodrigo amanhã às 09:00.'));
  });

  it('a recusa no clique (sem conversa, fora do horário no caminho antigo) aparece como erro, com o texto do banco', async () => {
    for (const msg of [
      'Flávio não escreveu para a HBR nos últimos 365 dias: mensagem automática a quem não escreve arrisca o número. Confirme por telefone.',
      'Fora do horário de mensagens ao cliente: peça amanhã a partir das 08:00.',
    ]) {
      banco.toasts = [];
      banco.resposta = { data: null, error: { message: msg } };
      const r = render(<PedirConfirmacaoButton osId="os-7" />);
      fireEvent.click(screen.getByRole('button', { name: /Pedir confirmação/ }));
      fireEvent.click(screen.getByRole('button', { name: 'Enviar pedido' }));
      await waitFor(() => expect(banco.toasts).toContain(`erro: ${msg}`));
      r.unmount();
    }
  });

  it('o diálogo diz que, em teste ou fora das ondas, o pedido só sai no horário; pela agenda, que a recusa vem na hora', () => {
    for (const como of ['agora_em_teste', 'agora_sem_onda'] as const) {
      expect(textoDoPedido(como)).toMatch(/Fora do horário de mensagens ao cliente o pedido não sai/);
    }
    expect(textoDoPedido('agenda')).toMatch(/o aviso diz na hora/);
    expect(textoDoPedido('agenda')).toMatch(/o clique a aprova/);
    // desligado: como em 30/09 (o banco não olha o horário)
    expect(textoDoPedido('agora')).not.toMatch(/Fora do horário/);
  });
});
