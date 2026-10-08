// Os botões da pasta no Dropbox. O que se protege: só o admin vê; com pasta, o botão abre o link
// do site com o caminho codificado e o número do projeto; sem pasta, "Criar" pede à fila (motivo
// pasta) e chama o worker; o "Salvar PDF agora" do menu pede motivo manual da ordem.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { DropdownMenu, DropdownMenuContent, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';

const db = vi.hoisted(() => ({
  cargo: 'admin',
  pasta: null as null | { caminho: string; codigo_projeto: string | null },
  inseridos: [] as Array<Record<string, unknown>>,
  invocou: 0,
}));

function consulta(resultado: () => unknown) {
  const q: Record<string, unknown> = {};
  for (const m of ['select', 'eq', 'order']) q[m] = () => q;
  q.limit = async () => ({ data: resultado(), error: null });
  return q;
}

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: (tabela: string) => {
      if (tabela === 'pastas_dropbox') return consulta(() => (db.pasta ? [db.pasta] : []));
      return {
        insert: (linha: Record<string, unknown>) => {
          db.inseridos.push(linha);
          return { select: () => ({ maybeSingle: async () => ({ data: { id: 'e1' }, error: null }) }) };
        },
      };
    },
    functions: {
      invoke: async () => {
        db.invocou++;
        return { data: { ok: true, processados: 1, relatorio: [{ id: 'e1', status: 'feito', resultado: 'pasta criada' }] }, error: null };
      },
    },
  },
}));
vi.mock('@/hooks/use-auth', () => ({ useAuth: () => ({ user: { id: 'u1', role: db.cargo } }) }));
vi.mock('sonner', () => ({ toast: { success: () => {}, error: () => {}, info: () => {} } }));

import { AcoesDropboxDaOrdem, PastaDoBarcoBotao } from './PastaNoDropbox';

function montar(ui: React.ReactNode) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(<QueryClientProvider client={qc}>{ui}</QueryClientProvider>);
}

beforeEach(() => {
  db.cargo = 'admin';
  db.pasta = null;
  db.inseridos = [];
  db.invocou = 0;
});

describe('PastaDoBarcoBotao', () => {
  it('com pasta: abre o link do Dropbox e mostra o número do projeto', async () => {
    db.pasta = { caminho: '/MANAGEMENT/COMMERCIAL/B2C/0016.013.25_Dona V', codigo_projeto: '0016.013.25' };
    montar(<PastaDoBarcoBotao vesselId="v1" />);
    const link = await screen.findByRole('link', { name: /Pasta 0016\.013\.25/ });
    expect(link).toHaveAttribute('href', 'https://www.dropbox.com/home/MANAGEMENT/COMMERCIAL/B2C/0016.013.25_Dona%20V');
  });

  it('sem pasta: Criar pede à fila com motivo pasta e chama o worker', async () => {
    montar(<PastaDoBarcoBotao vesselId="v1" />);
    await userEvent.click(await screen.findByRole('button', { name: /Criar pasta no Dropbox/ }));
    expect(db.inseridos).toEqual([{ order_id: null, vessel_id: 'v1', motivo: 'pasta' }]);
    expect(db.invocou).toBe(1);
  });

  it('quem não é admin não vê nada', () => {
    db.cargo = 'technician';
    const { container } = montar(<PastaDoBarcoBotao vesselId="v1" />);
    expect(container).toBeEmptyDOMElement();
  });
});

describe('AcoesDropboxDaOrdem', () => {
  it('Salvar PDF agora pede motivo manual da ordem', async () => {
    db.pasta = { caminho: '/HBR-Testes/B2C/0026.007.26_Madu_I', codigo_projeto: '0026.007.26' };
    montar(
      <DropdownMenu open>
        <DropdownMenuTrigger>Ações</DropdownMenuTrigger>
        <DropdownMenuContent>
          <AcoesDropboxDaOrdem orderId="o1" vesselId="v1" />
        </DropdownMenuContent>
      </DropdownMenu>,
    );
    expect(await screen.findByText(/Abrir pasta no Dropbox/)).toBeInTheDocument();
    await userEvent.click(screen.getByText(/Salvar PDF no Dropbox agora/));
    expect(db.inseridos).toEqual([{ order_id: 'o1', vessel_id: null, motivo: 'manual' }]);
    expect(db.invocou).toBe(1);
  });
});
