// Smoke do StatusQuickChange com a porta única (Agenda de Produção, Fase 3, P3 — 24/10/2026): a mudança de status da
// lista vai pela porta (useUpdateServiceOrderStatus, via 'tela'). Quando ela não muda nada ("A OS já começou: não volta
// para aberta."), a tela mostra a frase dela e NÃO diz "Status atualizado"; quando muda, o "Status atualizado" leva a
// frase dela (na conclusão, a saída e as cobranças); a recusa (42501, ok = false) é o aviso de erro com a frase.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { I18nProvider } from '@/i18n';

const h = vi.hoisted(() => ({
  // Fase 3 (P7a): o que a porta aceita pela tela (undefined = sem resposta: tudo, como antes)
  porta: { resposta: undefined as undefined | Record<string, string[]>, carregando: false },
  mudar: vi.fn(),
  toastDaTela: vi.fn(),
  aviso: Object.assign(vi.fn(), { success: vi.fn(), error: vi.fn(), warning: vi.fn() }),
}));

vi.mock('@/hooks/use-service-orders', async (original) => ({
  ...(await original<typeof import('@/hooks/use-service-orders')>()),
  useUpdateServiceOrderStatus: () => ({ mutateAsync: h.mudar, isPending: false }),
  useCancelServiceOrder: () => ({ mutateAsync: vi.fn(), isPending: false }),
  useReopenServiceOrder: () => ({ mutateAsync: vi.fn(), isPending: false }),
}));
vi.mock('@/hooks/use-status-da-porta', async (original) => ({
  ...(await original<typeof import('@/hooks/use-status-da-porta')>()),
  useStatusQueAPortaAceita: () => ({ data: h.porta.resposta, isLoading: h.porta.carregando }),
}));
vi.mock('@/hooks/use-toast', () => ({ useToast: () => ({ toast: h.toastDaTela }) }));
vi.mock('sonner', () => ({ toast: h.aviso }));
vi.mock('@/hooks/use-auth', () => ({ useOptionalAuth: () => ({ user: { id: 'u1', role: 'technician' } }) }));
vi.mock('@/components/CompletionSendDialog', () => ({ CompletionSendDialog: () => null }));
vi.mock('@/components/fiscal/FaturarOsDialog', () => ({ FaturarOsDialog: () => null }));
vi.mock('@/integrations/supabase/client', () => {
  const vazio: any = new Proxy({}, {
    get: (_t, p) => (p === 'then'
      ? (ok: (v: unknown) => unknown) => Promise.resolve({ data: [], error: null }).then(ok)
      : p === 'maybeSingle' ? () => Promise.resolve({ data: null, error: null }) : () => vazio),
  });
  return { supabase: { from: () => vazio } };
});

import { StatusQuickChange } from './StatusQuickChange';

function renderizar(status: 'in_progress' | 'approved' | 'completed' | 'awaiting_client') {
  return render(
    <I18nProvider>
      <StatusQuickChange orderId="os-1" currentStatus={status} />
    </I18nProvider>,
  );
}

async function escolher(user: ReturnType<typeof userEvent.setup>, de: string, para: string) {
  await user.click(screen.getByRole('button', { name: new RegExp(de) }));
  await user.click(await screen.findByRole('menuitem', { name: new RegExp(para) }));
}

beforeEach(() => {
  h.porta.resposta = undefined;
  h.porta.carregando = false;
  h.mudar.mockReset();
  h.toastDaTela.mockReset();
  h.aviso.mockClear();
});

describe('StatusQuickChange — pela porta', () => {
  it('a porta não muda nada: a frase dela num aviso, e nada de "Status atualizado"', async () => {
    const user = userEvent.setup();
    h.mudar.mockResolvedValue({ mudou: false, status: 'in_progress', texto: '', justConverted: false, numero: null,
      semMudanca: 'A OS já começou: não volta para aberta.' });
    renderizar('in_progress');
    await escolher(user, 'Em Andamento', 'Aberta');
    expect(h.mudar).toHaveBeenCalledWith({ id: 'os-1', status: 'open' });
    expect(h.aviso).toHaveBeenCalledWith('A OS já começou: não volta para aberta.');
    expect(h.toastDaTela).not.toHaveBeenCalled();
  });

  it('concluiu: "Status atualizado para Concluída" com a frase da porta (a saída e as cobranças)', async () => {
    const user = userEvent.setup();
    const texto = 'Lenine (OS-00074): concluída — saída qui 29/10 16:30. Cobranças: Entrada 50% R$ 2.280,00 (vence hoje) · Saldo 50% R$ 2.280,00 (vence hoje).';
    h.mudar.mockResolvedValue({ mudou: true, status: 'completed', texto, justConverted: false, numero: null });
    renderizar('in_progress');
    await escolher(user, 'Em Andamento', 'Concluída');
    expect(h.toastDaTela).toHaveBeenCalledWith({ title: 'Status atualizado para "Concluída"', description: texto });
    expect(h.aviso).not.toHaveBeenCalled();
  });

  it('a recusa da porta (o vendedor concluindo) é o aviso de erro com a frase dela', async () => {
    const user = userEvent.setup();
    h.mudar.mockRejectedValue(new Error('Concluir é com o administrador ou o técnico da OS.'));
    renderizar('approved');
    await escolher(user, 'Aprovada', 'Concluída');
    expect(h.toastDaTela).toHaveBeenCalledWith({
      title: 'Erro ao atualizar status', description: 'Concluir é com o administrador ou o técnico da OS.', variant: 'destructive',
    });
  });
});

// Fase 3 (P7a): o menu esconde o que a porta recusa para o cargo e a OS (os_status_da_tela, a mesma regra da porta).
describe('StatusQuickChange — só o que a porta aceita', () => {
  it('em andamento: aparece só o aceito (e Cancelar, que é outro caminho); "Corrigir para Aberta" some', async () => {
    const user = userEvent.setup();
    h.porta.resposta = { 'os-1': ['completed'] };
    renderizar('in_progress');
    await user.click(screen.getByRole('button', { name: /Em Andamento/ }));
    const itens = (await screen.findAllByRole('menuitem')).map((i) => i.textContent);
    expect(itens.some((t) => /Concluída/.test(t ?? ''))).toBe(true);
    expect(itens.some((t) => /Cancelada/.test(t ?? ''))).toBe(true);
    expect(itens.some((t) => /Aberta|Aguardando Peças|Aguardando Cliente/.test(t ?? ''))).toBe(false);
    expect(screen.queryByText(/Corrigir para/)).not.toBeInTheDocument();
  });

  it('aguardando o cliente: "Corrigir para Aberta" some (o cliente não liberou); concluída sem nada: diz que não há o que mudar', async () => {
    const user = userEvent.setup();
    h.porta.resposta = { 'os-1': ['in_progress', 'awaiting_parts', 'completed'] };
    const { unmount } = renderizar('awaiting_client');
    await user.click(screen.getByRole('button', { name: /Aguardando Cliente/ }));
    await screen.findAllByRole('menuitem');
    expect(screen.queryByRole('menuitem', { name: /Aberta/ })).not.toBeInTheDocument();
    expect(screen.getByRole('menuitem', { name: /Em Andamento/ })).toBeInTheDocument();
    unmount();

    h.porta.resposta = { 'os-1': [] };
    renderizar('completed');
    await user.click(screen.getByRole('button', { name: /Concluída/ }));
    expect(await screen.findByText('Nada que você possa mudar nesta OS.')).toBeInTheDocument();
    expect(screen.queryByRole('menuitem', { name: /Faturada/ })).not.toBeInTheDocument();
  });

  it('enquanto confere, só "Conferindo…" (e Cancelar): nada que a porta recusaria fica clicável', async () => {
    const user = userEvent.setup();
    h.porta.carregando = true;
    renderizar('in_progress');
    await user.click(screen.getByRole('button', { name: /Em Andamento/ }));
    expect(await screen.findByText('Conferindo o que dá para mudar…')).toBeInTheDocument();
    expect(screen.queryByRole('menuitem', { name: /Concluída/ })).not.toBeInTheDocument();
    expect(screen.getByRole('menuitem', { name: /Cancelada/ })).toBeInTheDocument();
  });
});
