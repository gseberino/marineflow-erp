// Smoke do StatusQuickChange com a porta única (Agenda de Produção, Fase 3, P3 — 24/10/2026): a mudança de status da
// lista vai pela porta (useUpdateServiceOrderStatus, via 'tela'). Quando ela não muda nada ("A OS já começou: não volta
// para aberta."), a tela mostra a frase dela e NÃO diz "Status atualizado"; quando muda, o "Status atualizado" leva a
// frase dela (na conclusão, a saída e as cobranças); a recusa (42501, ok = false) é o aviso de erro com a frase.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { I18nProvider } from '@/i18n';

const h = vi.hoisted(() => ({
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

function renderizar(status: 'in_progress' | 'approved') {
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
