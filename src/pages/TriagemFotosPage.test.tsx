// Triagem de fotos. O que se protege: as fotos aparecem agrupadas por dia (mais recente primeiro);
// prints ficam escondidos até pedir; abrir o dia mostra a OS sugerida com o porquê; "Mover" manda
// à edge as fotos marcadas, com o dia de cada uma, e a OS escolhida.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const db = vi.hoisted(() => ({ chamadas: [] as Array<Record<string, unknown>> }));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    functions: {
      invoke: async (_n: string, { body }: { body: Record<string, unknown> }) => {
        db.chamadas.push(body);
        if (body.acao === 'listar') {
          return {
            data: {
              pasta: '/Envio da câmera',
              itens: [
                { id: 'id:f1', nome: '2026-09-26 17.44.07.jpg', tamanho: 1, dia: '2026-09-26', hora: '17:44', tipo: 'foto' },
                { id: 'id:f2', nome: '2026-09-26 17.45.21.jpg', tamanho: 1, dia: '2026-09-26', hora: '17:45', tipo: 'foto' },
                { id: 'id:f3', nome: '2026-10-03 13.16.51.png', tamanho: 1, dia: '2026-10-03', hora: '13:16', tipo: 'print' },
                { id: 'id:f4', nome: '2026-09-28 20.58.21.jpg', tamanho: 1, dia: '2026-09-28', hora: '20:58', tipo: 'foto' },
              ],
            },
            error: null,
          };
        }
        if (body.acao === 'sugestoes') {
          return {
            data: { sugestoes: { '2026-09-26': [{ id: 'os1', numero: 'OS-00105', barco: 'Donna V', cliente: 'Acrisio', status: 'in_progress', nota: 6, motivos: ['diária no barco'] }] } },
            error: null,
          };
        }
        if (body.acao === 'miniaturas') return { data: { miniaturas: {} }, error: null };
        if (body.acao === 'mover') return { data: { movidas: 2, falharam: 0, destino: '/x/3- FOTOS/2026-09-26 OS-00105' }, error: null };
        return { data: null, error: null };
      },
    },
    from: () => {
      const q: Record<string, unknown> = {};
      for (const m of ['select', 'neq', 'order']) q[m] = () => q;
      q.limit = async () => ({ data: [], error: null });
      return q;
    },
  },
}));
vi.mock('sonner', () => ({ toast: { success: () => {}, error: () => {}, info: () => {} } }));
vi.mock('@/components/PageHeader', () => ({ PageHeader: ({ title }: { title: string }) => <h1>{title}</h1> }));

import TriagemFotosPage from './TriagemFotosPage';

function montar() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(<QueryClientProvider client={qc}><TriagemFotosPage /></QueryClientProvider>);
}

beforeEach(() => { db.chamadas = []; });

describe('TriagemFotosPage', () => {
  it('agrupa por dia (mais recente primeiro) e esconde os prints', async () => {
    montar();
    const dias = await screen.findAllByRole('button', { expanded: false });
    expect(dias.map((d) => d.textContent)).toEqual([
      expect.stringContaining('28/09/2026'),
      expect.stringContaining('26/09/2026'),
    ]);
    expect(screen.queryByText(/03\/10\/2026/)).toBeNull();
    await userEvent.click(screen.getByLabelText('Mostrar prints de tela'));
    expect(await screen.findByText(/03\/10\/2026/)).toBeInTheDocument();
  });

  it('o dia mostra a OS sugerida com o porquê e move as fotos marcadas para ela', async () => {
    montar();
    const dia = await screen.findByRole('button', { name: /26\/09\/2026/ });
    expect(await within(dia).findByText(/provável: OS-00105 · Donna V/)).toBeInTheDocument();
    await userEvent.click(dia);
    expect(screen.getByText('diária no barco')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: /Mover 2 para OS-00105/ }));
    const mover = db.chamadas.find((c) => c.acao === 'mover');
    expect(mover).toEqual({
      acao: 'mover',
      order_id: 'os1',
      itens: [
        { id: 'id:f1', nome: '2026-09-26 17.44.07.jpg', dia: '2026-09-26' },
        { id: 'id:f2', nome: '2026-09-26 17.45.21.jpg', dia: '2026-09-26' },
      ],
    });
  });
});
