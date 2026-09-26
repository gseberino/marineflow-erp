// "É este?" — a parcela da nota que parece já ter saído pelo banco é PERGUNTA, nunca ligação
// automática (decisão do dono de 26/09/2026: "o sistema deve sempre questionar").
import { describe, it, expect, vi, afterEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { PerguntasDaNota, parcelasComPergunta, type ParcelaDaImportacao } from './PerguntasDaNota';

const { rpcMock, estado } = vi.hoisted(() => ({
  rpcMock: vi.fn(async () => ({ data: { ok: true }, error: null as { message: string } | null })),
  /** Situação das parcelas no banco, como a janela confere ao abrir. */
  estado: { status: { p1: 'pending', p2: 'pending' } as Record<string, string> },
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: () => ({
      select: () => ({
        in: async (_col: string, ids: string[]) => ({
          data: ids.map((id) => ({ id, status: estado.status[id] ?? 'paid' })), error: null,
        }),
      }),
    }),
    rpc: rpcMock,
  },
}));

const parcelas: ParcelaDaImportacao[] = [
  {
    parcela: 1, valor: 1500, vencimento: '2026-09-22', payable_id: 'p1', como: 'a_pagar',
    candidatos: [{ payable_id: 'pix-tsd', data: '2026-09-22', valor: 1500, descricao: 'TSD LOGISTICA' }],
  },
  { parcela: 2, valor: 785.07, vencimento: '2026-10-20', payable_id: 'p2', como: 'a_pagar', candidatos: [] },
  { parcela: 0, valor: 400, vencimento: '2026-09-01', payable_id: 'p3', como: 'credito_do_fornecedor', candidatos: [] },
];

function abrir(onFechar = vi.fn()) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={qc}>
      <I18nProvider><PerguntasDaNota nota="132181" parcelas={parcelas} onFechar={onFechar} /></I18nProvider>
    </QueryClientProvider>,
  );
  return onFechar;
}

describe('perguntas da nota importada', () => {
  afterEach(() => { rpcMock.mockClear(); estado.status = { p1: 'pending', p2: 'pending' }; });

  it('só pergunta pela parcela que tem pagamento parecido', () => {
    expect(parcelasComPergunta(parcelas).map((p) => p.payable_id)).toEqual(['p1']);
    expect(parcelasComPergunta(undefined)).toEqual([]);
  });

  it('"É este" liga pelo servidor — e só ele liga', async () => {
    const user = userEvent.setup();
    abrir();
    expect(await screen.findByText(/Parcela 1/)).toBeInTheDocument();
    expect(screen.queryByText(/Parcela 2/)).not.toBeInTheDocument();
    expect(rpcMock).not.toHaveBeenCalled();
    await user.click(screen.getByRole('button', { name: 'É este' }));
    expect(rpcMock).toHaveBeenCalledWith('ligar_parcela_ao_pagamento', { p_parcela: 'p1', p_pagamento: 'pix-tsd' });
    expect(await screen.findByText(/Ligada ao pagamento/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Concluir' })).toBeInTheDocument();
  });

  it('"Não é nenhum destes" deixa a parcela a pagar, sem chamar o servidor', async () => {
    const user = userEvent.setup();
    abrir();
    await user.click(await screen.findByRole('button', { name: 'Não é nenhum destes' }));
    expect(screen.getByText(/Continua a pagar/)).toBeInTheDocument();
    expect(rpcMock).not.toHaveBeenCalled();
  });

  it('reaberta depois, não pergunta pela parcela que já não está a pagar', async () => {
    estado.status = { p1: 'paid', p2: 'pending' };
    abrir();
    expect(await screen.findByText(/Nenhuma parcela desta nota tem pergunta aberta/)).toBeInTheDocument();
  });

  it('recusa do servidor aparece e nada muda', async () => {
    rpcMock.mockResolvedValueOnce({ data: null, error: { message: 'P0001: Este pagamento não está livre para ser ligado a uma nota — nada foi ligado.' } });
    const user = userEvent.setup();
    abrir();
    await user.click(await screen.findByRole('button', { name: 'É este' }));
    expect(screen.queryByText(/Ligada ao pagamento/)).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Responder depois' })).toBeInTheDocument();
  });
});
