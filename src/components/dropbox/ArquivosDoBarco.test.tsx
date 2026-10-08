// A aba "Arquivos" da embarcação. O que se protege: lista do índice com a subpasta relativa à
// pasta do barco, o link que abre o arquivo no site do Dropbox, a busca por nome/subpasta e o
// aviso de índice vazio.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const db = vi.hoisted(() => ({ pastas: [] as unknown[], arquivos: [] as unknown[] }));

function encadeia(final: () => unknown) {
  const q: Record<string, unknown> = {};
  for (const m of ['select', 'eq', 'in', 'order']) q[m] = () => q;
  q.limit = async () => ({ data: final(), error: null });
  // pastas_dropbox termina no .eq() (sem limit): o await do próprio objeto resolve.
  q.then = (ok: (v: unknown) => void) => ok({ data: final(), error: null });
  return q;
}

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: (t: string) => encadeia(() => (t === 'pastas_dropbox' ? db.pastas : db.arquivos)),
  },
}));

import { ArquivosDoBarco } from './ArquivosDoBarco';

function montar() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(<QueryClientProvider client={qc}><ArquivosDoBarco vesselId="v1" /></QueryClientProvider>);
}

beforeEach(() => {
  db.pastas = [{ id: 'p1', caminho: '/MANAGEMENT/COMMERCIAL/B2C/0016.013.25_Dona V' }];
  db.arquivos = [
    {
      id: 'a1', nome: '2026-10-08 ORÇ-00112 v1.pdf', extensao: 'pdf', tamanho: 308480, modificado_em: '2026-10-08T03:22:47Z',
      origem: 'sistema', pasta_id: 'p1',
      caminho: "/MANAGEMENT/COMMERCIAL/B2C/0016.013.25_Dona V/1- DOC's/Orçamentos e OS/2026-10-08 ORÇ-00112 v1.pdf",
    },
    {
      id: 'a2', nome: 'Painel Inox.dwg', extensao: 'dwg', tamanho: 41231, modificado_em: '2025-12-22T12:57:16Z',
      origem: 'dono', pasta_id: 'p1',
      caminho: '/MANAGEMENT/COMMERCIAL/B2C/0016.013.25_Dona V/2- ELÉTRICA/2- DWG/Painel Inox.dwg',
    },
  ];
});

describe('ArquivosDoBarco', () => {
  it('lista com a subpasta relativa e o link do Dropbox', async () => {
    montar();
    const link = await screen.findByRole('link', { name: /ORÇ-00112 v1\.pdf/ });
    expect(link.getAttribute('href')).toBe(
      "https://www.dropbox.com/home/MANAGEMENT/COMMERCIAL/B2C/0016.013.25_Dona%20V/1-%20DOC's/Or%C3%A7amentos%20e%20OS?preview=2026-10-08%20OR%C3%87-00112%20v1.pdf",
    );
    expect(screen.getByText(/1- DOC's\/Orçamentos e OS · .* · 301 KB · salvo pelo sistema/)).toBeInTheDocument();
    expect(screen.getByText(/2- ELÉTRICA\/2- DWG/)).toBeInTheDocument();
  });

  it('a busca filtra por nome ou subpasta', async () => {
    montar();
    await screen.findByText(/Painel Inox\.dwg/);
    await userEvent.type(screen.getByLabelText('Procurar arquivo'), 'dwg');
    expect(screen.queryByText(/ORÇ-00112/)).toBeNull();
    expect(screen.getByText(/1 de 2 arquivo/)).toBeInTheDocument();
  });

  it('sem pasta registrada, avisa que o índice ainda não tem nada', async () => {
    db.pastas = [];
    montar();
    expect(await screen.findByText(/Nenhum arquivo deste barco no índice ainda/)).toBeInTheDocument();
  });
});
