// A outra perna da transferência (pedido do dono, 28/09/2026): a linha diz "saiu da X, entrou
// na Y". A leitura é à parte e pode falhar sem derrubar a fila — a linha só perde o destino.
import { describe, it, expect, vi } from 'vitest';
import { createElement, type ReactNode } from 'react';
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider, QueryObserver } from '@tanstack/react-query';
import { toast } from 'sonner';
import { idsDasOutrasPernas, juntarOutraPerna, useGerarPropostas, type PropostaFinanceira } from './use-finance-review';

// O que a varredura devolve quando baixa um recebimento pelo boleto (24/11/2026): o aviso manda olhar o cartão.
const { AVISO_DA_VARREDURA } = vi.hoisted(() => ({
  AVISO_DA_VARREDURA: '0 proposta(s) para revisar · 1 recebimento baixado pelo boleto — veja em "Lançados sozinhos"',
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    functions: { invoke: async () => ({ data: { ok: true, criadas: 0, message: AVISO_DA_VARREDURA, restantes: 0 }, error: null }) },
  },
}));
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn(), loading: vi.fn(), dismiss: vi.fn() } }));

const proposta = (id: string, kind: string, related: string | null) =>
  ({ id, kind, related_transaction_id: related }) as unknown as PropostaFinanceira;

describe('outra perna da transferência', () => {
  it('pede só as pernas das transferências, sem repetir', () => {
    const fila = [
      proposta('a', 'internal_transfer', 't2'),
      proposta('b', 'internal_transfer', 't2'),
      proposta('c', 'internal_transfer', 't9'),
      proposta('d', 'create_payable', 't7'),
      proposta('e', 'internal_transfer', null),
    ];
    expect(idsDasOutrasPernas(fila)).toEqual(['t2', 't9']);
  });

  it('pendura a perna lida; a que não veio fica sem destino; outras linhas não mudam', () => {
    const fila = [
      proposta('a', 'internal_transfer', 't2'),
      proposta('c', 'internal_transfer', 't9'),
      proposta('d', 'create_payable', 't7'),
    ];
    juntarOutraPerna(fila, [
      { id: 't2', source_type: 'bank', card_last_digits: null, bank_connection_id: 'nu', transaction_type: 'credit' },
      { id: 't7', source_type: 'bank', card_last_digits: null, bank_connection_id: 'c6', transaction_type: 'debit' },
    ]);
    expect(fila[0].outra_perna).toMatchObject({ bank_connection_id: 'nu', transaction_type: 'credit' });
    expect(fila[1].outra_perna).toBeNull();
    expect(fila[2].outra_perna).toBeUndefined();
  });
});

// 24/11/2026: o botão "Analisar" mostrava `veja em "Lançados sozinhos"` e recarregava só a fila. O cartão fica montado
// logo acima do botão, e o cliente de consultas não recarrega ao voltar o foco: a contagem antiga ficava ali, sem o
// item e sem o Desfazer, até o dono sair da tela e voltar.
describe('useGerarPropostas: depois da varredura, o cartão "Lançados sozinhos" recarrega', () => {
  it('recarrega o cartão que o aviso manda olhar, a fila e as contas que a varredura pode ter baixado', async () => {
    // Dado "fresco" por um minuto e sem recarga por foco, como na tela: só uma invalidação faz buscar de novo.
    const qc = new QueryClient({ defaultOptions: { queries: { staleTime: 60_000, refetchOnWindowFocus: false, retry: false } } });
    const buscas = { fila: 0, sozinhos: 0, receber: 0, pagar: 0 };
    // Consultas montadas (com observador ativo), como o cartão e a caixa de entrada lado a lado.
    const montar = (queryKey: string[], qual: keyof typeof buscas) =>
      new QueryObserver(qc, { queryKey, queryFn: async () => { buscas[qual] += 1; return []; } }).subscribe(() => {});
    const desmontar = [
      montar(['finance-review-queue', 'pending'], 'fila'), montar(['lancados-sozinhos'], 'sozinhos'),
      montar(['receivables'], 'receber'), montar(['payables'], 'pagar'),
    ];
    await waitFor(() => expect(buscas).toEqual({ fila: 1, sozinhos: 1, receber: 1, pagar: 1 }));

    const wrapper = ({ children }: { children: ReactNode }) => createElement(QueryClientProvider, { client: qc }, children);
    const { result } = renderHook(() => useGerarPropostas(), { wrapper });
    await result.current.mutateAsync(false);

    await waitFor(() => expect(buscas.sozinhos).toBe(2));
    expect(toast.success).toHaveBeenCalledWith(AVISO_DA_VARREDURA);
    expect(buscas.fila).toBeGreaterThan(1);
    expect(buscas.receber).toBe(2);
    expect(buscas.pagar).toBe(2);
    desmontar.forEach((parar) => parar());
  });
});
