// A fila de envio do WhatsApp tinha cinco botões iguais lado a lado, e os dois "Limpar"
// apagavam mensagens da fila num clique, sem confirmação. O que se protege aqui: à vista só
// o que é seguro clicar por engano; apagar exige um "sim"; e o número que o botão mostra é o
// número que ele apaga (antes contava só a última hora e apagava todas as falhas).
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const db = vi.hoisted(() => ({
  apagados: [] as string[],
  porStatus: { pending: 3, sending: 0, sent: 0, failed: 7 } as Record<string, number>,
  falhasNaUltimaHora: 0,
}));

vi.mock('@/integrations/supabase/client', () => {
  type Estado = { op?: string; head?: boolean; filtros: Record<string, unknown> };
  function responder(tabela: string, e: Estado) {
    if (tabela === 'app_settings') return { data: [], error: null };
    if (e.op === 'delete') { db.apagados.push(String(e.filtros.status)); return { error: null }; }
    if (e.head) {
      const status = String(e.filtros.status);
      if (status === 'failed' && e.filtros.gte) return { count: db.falhasNaUltimaHora, error: null };
      return { count: db.porStatus[status] ?? 0, error: null };
    }
    return { data: [], error: null };
  }
  function consulta(tabela: string) {
    const e: Estado = { filtros: {} };
    const q: Record<string, unknown> = {
      select: (_c: string, o?: { head?: boolean }) => { e.op = 'select'; e.head = o?.head; return q; },
      in: () => q, order: () => q, limit: () => q,
      eq: (c: string, v: unknown) => { e.filtros[c] = v; return q; },
      gte: (c: string) => { e.filtros.gte = c; return q; },
      delete: () => { e.op = 'delete'; return q; },
      upsert: () => Promise.resolve({ error: null }),
      then: (ok: (v: unknown) => unknown, erro: (r: unknown) => unknown) =>
        Promise.resolve(responder(tabela, e)).then(ok, erro),
    };
    return q;
  }
  return {
    supabase: {
      from: consulta,
      functions: { invoke: async () => ({ data: { processed: 0 }, error: null }) },
    },
  };
});
vi.mock('@/hooks/use-toast', () => ({ toast: () => {} }));

import { WhatsAppQueuePanel } from './WhatsAppQueuePanel';

function montar() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(<QueryClientProvider client={qc}><WhatsAppQueuePanel /></QueryClientProvider>);
}

async function abrirMenu(user: ReturnType<typeof userEvent.setup>) {
  await user.click(await screen.findByRole('button', { name: /mais ações para a fila de envio do whatsapp/i }));
}

beforeEach(() => {
  db.apagados = [];
  db.porStatus = { pending: 3, sending: 0, sent: 0, failed: 7 };
  db.falhasNaUltimaHora = 0;
});

describe('fila de envio do WhatsApp', () => {
  it('à vista só salvar e processar; atualizar e apagar esperam no menu', async () => {
    montar();
    expect(await screen.findByRole('button', { name: 'Salvar limites' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Processar fila agora/ })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Limpar|Apagar/ })).not.toBeInTheDocument();
  });

  it('apagar as que aguardam pede confirmação e só apaga depois do sim', async () => {
    const user = userEvent.setup();
    montar();
    await abrirMenu(user);
    await user.click(await screen.findByRole('menuitem', { name: 'Apagar as que aguardam (3)' }));
    expect(await screen.findByText('Apagar 3 mensagens que aguardam envio?')).toBeInTheDocument();
    expect(db.apagados).toEqual([]);

    await user.click(screen.getByRole('button', { name: 'Apagar' }));
    await vi.waitFor(() => expect(db.apagados).toEqual(['pending']));
  });

  it('voltar não apaga nada', async () => {
    const user = userEvent.setup();
    montar();
    await abrirMenu(user);
    await user.click(await screen.findByRole('menuitem', { name: 'Apagar as que aguardam (3)' }));
    await user.click(await screen.findByRole('button', { name: 'Voltar' }));
    expect(screen.queryByText(/que aguardam envio\?/)).not.toBeInTheDocument();
    expect(db.apagados).toEqual([]);
  });

  it('as falhas antigas contam: o botão mostra o que de fato apaga', async () => {
    // Nenhuma falha na última hora, 7 no total: antes o botão ficava apagado e, quando
    // acendia, apagava as 7 mostrando só as da hora.
    const user = userEvent.setup();
    montar();
    await abrirMenu(user);
    const item = await screen.findByRole('menuitem', { name: 'Apagar as que falharam (7)' });
    expect(item).not.toHaveAttribute('data-disabled');
    await user.click(item);
    expect(await screen.findByText('Apagar 7 mensagens que falharam?')).toBeInTheDocument();
  });

  it('sem nada aguardando, apagar fica desabilitado', async () => {
    db.porStatus.pending = 0;
    const user = userEvent.setup();
    montar();
    await abrirMenu(user);
    expect(await screen.findByRole('menuitem', { name: 'Apagar as que aguardam (0)' })).toHaveAttribute('data-disabled');
  });
});
