// Duplicar OS: a despesa que nasceu de um comprovante do WhatsApp (origem_codigo "CMP-…", resposta 2 do
// dono, 11/10/2026) é o custo interno daquela OS — não é composição de outra e não se copia (copiada,
// nasceria faturável e viraria cobrança na OS nova). As lançadas à mão continuam sendo copiadas.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';
import { useDuplicateServiceOrder } from './use-service-orders';

/** O que cada tabela recebeu em insert, na ordem. */
let gravacoes: Record<string, unknown[]> = {};
let fonte: Record<string, unknown> = {};
/** O created_at que o banco devolve no insert da OS nova (porte da via v2, F0: base da gravação em sequência). */
let criadaEm: string | null = null;

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    rpc: async () => ({ data: 42, error: null }),
    from: (tabela: string) => ({
      select: () => ({ eq: () => ({ single: async () => ({ data: fonte, error: null }) }) }),
      insert: (linhas: unknown) => {
        (gravacoes[tabela] ??= []).push(linhas);
        return Object.assign(Promise.resolve({ data: null, error: null }), {
          select: () => ({ single: async () => ({ data: { id: 'nova', ...(criadaEm ? { created_at: criadaEm } : {}) }, error: null }) }),
        });
      },
    }),
  },
}));
vi.mock('sonner', () => ({ toast: Object.assign(vi.fn(), { success: vi.fn(), error: vi.fn() }) }));

const despesa = (o: Record<string, unknown>) => ({
  id: 'e', service_order_id: 'os1', category: 'Combustível e deslocamento', description: 'Gasolina', amount: 62,
  currency: 'BRL', paid_by: 'company', supplier_id: null, notes: null, billable_to_client: true, origem_codigo: null, ...o,
});

beforeEach(() => {
  gravacoes = {};
  criadaEm = null;
  fonte = {
    id: 'os1', service_order_number: 'OS-00112', status: 'completed', priority: 'normal', client_id: 'c1',
    service_order_parts: [], service_order_services: [],
    service_order_expenses: [
      despesa({ id: 'cmp', description: 'Posto Shell', billable_to_client: false, origem_codigo: 'CMP-00124' }),
      despesa({ id: 'manual', description: 'Frete da peça' }),
    ],
  };
});

const wrapper = ({ children }: { children: ReactNode }) => (
  <QueryClientProvider client={new QueryClient({ defaultOptions: { mutations: { retry: false } } })}>{children}</QueryClientProvider>
);

describe('duplicar OS', () => {
  it('copia a despesa lançada à mão e deixa de fora a que nasceu de comprovante', async () => {
    const { result } = renderHook(() => useDuplicateServiceOrder(), { wrapper });
    result.current.mutate({ sourceId: 'os1', mode: 'order' });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    const copiadas = (gravacoes.service_order_expenses ?? []).flat() as Array<Record<string, unknown>>;
    expect(copiadas.map((e) => e.description)).toEqual(['Frete da peça']);
    expect(copiadas[0]).toMatchObject({ service_order_id: 'nova' });
  });

  // Agenda de Produção (revisão da Fase 3, R1): duplicar uma OS já entregue falhava — a cópia levava delivered_at sem
  // check_out_at, e o CHECK so_entrega_depois_da_conclusao (e o gatilho da entrega, também no INSERT) recusavam.
  it('duplicar uma OS já entregue: a cópia não leva a saída nem a entrega', async () => {
    Object.assign(fonte, { check_in_at: '2026-10-20T11:00:00Z', check_out_at: '2026-10-20T20:00:00Z', delivered_at: '2026-10-21T13:00:00Z' });
    const { result } = renderHook(() => useDuplicateServiceOrder(), { wrapper });
    result.current.mutate({ sourceId: 'os1', mode: 'order' });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    const cabecalho = (gravacoes.service_orders ?? [])[0] as Record<string, unknown>;
    for (const campo of ['check_in_at', 'check_out_at', 'delivered_at']) expect(cabecalho, campo).not.toHaveProperty(campo);
    expect(cabecalho).toMatchObject({ status: 'open' });
  });

  // Retorno F3 (P10.3): a cópia não nasceu de um ato no cartão, e levaria a validade antiga da original.
  it('a cópia não leva a origem do retorno nem a validade da original', async () => {
    Object.assign(fonte, { origem: 'retorno_ditado', origem_chave8: '12345678', origem_parceiro_id: 'p1', quote_validity_date: '2026-09-01' });
    const { result } = renderHook(() => useDuplicateServiceOrder(), { wrapper });
    result.current.mutate({ sourceId: 'os1', mode: 'quote' });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    const cabecalho = (gravacoes.service_orders ?? [])[0] as Record<string, unknown>;
    for (const campo of ['origem', 'origem_chave8', 'origem_parceiro_id', 'quote_validity_date']) expect(cabecalho, campo).not.toHaveProperty(campo);
  });

  // Retorno F5 (P12.1): o envio e o desfecho são eventos da original. A cópia que os levasse nasceria "já enviada" (sem os 7
  // dias do envio, sem o gatilho e sem a cadência) e com o motivo do perdido.
  it('a cópia de um orçamento enviado e perdido não leva nenhuma das 7 colunas da F5', async () => {
    const colunasDaF5 = {
      orcamento_enviado_em: '2026-12-08T13:00:00Z', orcamento_enviado_via: 'tela', orcamento_enviado_chave: '00009901',
      motivo_perda: 'preco', motivo_perda_em: '2026-12-16T13:00:00Z', motivo_perda_por: 'tela', motivo_perda_nota: 'achou caro',
    };
    Object.assign(fonte, { status: 'draft', quote_status: 'rejected', ...colunasDaF5 });
    const { result } = renderHook(() => useDuplicateServiceOrder(), { wrapper });
    result.current.mutate({ sourceId: 'os1', mode: 'quote' });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    const cabecalho = (gravacoes.service_orders ?? [])[0] as Record<string, unknown>;
    for (const campo of Object.keys(colunasDaF5)) expect(cabecalho, campo).not.toHaveProperty(campo);
    expect(cabecalho).toMatchObject({ status: 'draft', quote_status: 'draft' });
  });

  // Porte da via v2, F0 (E15): o embutido vem sem ordem e um INSERT só dava o mesmo now() a todas as linhas — a ordem
  // da via (created_at, id) ficava por conta do id, aleatório. A cópia sai na ordem da origem, em sequência a partir do
  // created_at que o BANCO devolveu para a OS nova (não o relógio do navegador).
  it('a cópia sai na ordem da origem (created_at, id), com created_at em sequência a partir do da OS nova', async () => {
    criadaEm = '2026-11-16T18:00:00.123456+00:00';
    const MESMO = '2026-11-10T12:00:00.5+00:00';
    fonte.service_order_services = [
      { id: '9-serv', created_at: MESMO, name_snapshot: 'Teste final' },
      { id: '1-serv', created_at: MESMO, name_snapshot: 'Instalação' },
      { id: '5-serv', created_at: '2026-11-10T11:00:00+00:00', name_snapshot: 'Levantamento' },
    ];
    fonte.service_order_parts = [
      { id: 'b-peca', created_at: MESMO, product_id: 'pB' },
      { id: 'a-peca', created_at: MESMO, product_id: 'pA' },
    ];
    const { result } = renderHook(() => useDuplicateServiceOrder(), { wrapper });
    result.current.mutate({ sourceId: 'os1', mode: 'quote' });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    const servicos = (gravacoes.service_order_services ?? []).flat() as Array<Record<string, unknown>>;
    const pecas = (gravacoes.service_order_parts ?? []).flat() as Array<Record<string, unknown>>;
    expect(servicos.map((s) => [s.name_snapshot, s.created_at])).toEqual([
      ['Levantamento', '2026-11-16T18:00:00.124Z'],
      ['Instalação', '2026-11-16T18:00:00.125Z'],
      ['Teste final', '2026-11-16T18:00:00.126Z'],
    ]);
    expect(pecas.map((p) => [p.product_id, p.created_at])).toEqual([
      ['pA', '2026-11-16T18:00:00.124Z'],
      ['pB', '2026-11-16T18:00:00.125Z'],
    ]);
  });

  // NOVO-historico-05: a cópia levava o total líquido da linha e deixava o desconto dela para trás — a próxima edição
  // recalculava sem ele e o PDF não mostrava o desconto.
  it('a cópia leva o desconto de cada linha junto com o total líquido', async () => {
    fonte.service_order_services = [
      { id: 's1', created_at: '2026-11-10T11:00:00+00:00', name_snapshot: 'Instalação', quantity: 1, unit_price_snapshot: 800,
        line_total: 720, discount_pct: 10, discount_amount: 80 },
    ];
    fonte.service_order_parts = [
      { id: 'p1', created_at: '2026-11-10T11:00:00+00:00', product_id: 'pA', quantity: 2, unit_sale_snapshot: 30,
        line_total_sale: 50, discount_pct: 16.67, discount_amount: 10 },
      { id: 'p2', created_at: '2026-11-10T11:00:01+00:00', product_id: 'pB', quantity: 1, unit_sale_snapshot: 5, line_total_sale: 5 },
    ];
    const { result } = renderHook(() => useDuplicateServiceOrder(), { wrapper });
    result.current.mutate({ sourceId: 'os1', mode: 'quote' });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    const servicos = (gravacoes.service_order_services ?? []).flat() as Array<Record<string, unknown>>;
    const pecas = (gravacoes.service_order_parts ?? []).flat() as Array<Record<string, unknown>>;
    expect(servicos[0]).toMatchObject({ line_total: 720, discount_pct: 10, discount_amount: 80 });
    expect(pecas[0]).toMatchObject({ line_total_sale: 50, discount_pct: 16.67, discount_amount: 10 });
    expect(pecas[1]).toMatchObject({ line_total_sale: 5, discount_pct: 0, discount_amount: 0 });
  });

  it('só despesa de comprovante: nenhuma despesa é gravada na OS nova', async () => {
    fonte.service_order_expenses = [despesa({ id: 'cmp', billable_to_client: false, origem_codigo: 'CMP-00124' })];
    const { result } = renderHook(() => useDuplicateServiceOrder(), { wrapper });
    result.current.mutate({ sourceId: 'os1', mode: 'quote' });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(gravacoes.service_order_expenses).toBeUndefined();
    expect(gravacoes.service_orders).toHaveLength(1);
  });
});
