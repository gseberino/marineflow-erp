// A OC gerada da cotação copia o vínculo de linha (Agenda de Produção, Fase 4, P2 — 25/10/2026).
//
// A cotação já sabia de qual linha da OS cada item é (quote_request_items.service_order_part_id /
// service_order_service_id); a OC perdia. Agora useCreatePOsFromQuote lê os dois ANTES de criar qualquer OC e os grava
// na linha da OC (a peça vence; no máximo um, o CHECK poi_um_vinculo_de_linha). O que estes testes protegem:
//  1. o vínculo copiado por item, em cada OC (uma por fornecedor);
//  2. o item sem vínculo nasce como antes (sem as chaves: grava também antes da migration 20261027100000);
//  3. a leitura dos vínculos que falha não cria OC nenhuma;
//  4. o banco sem as colunas do vínculo (a tela antes da migration: PGRST204) grava a OC sem ele (revisão C2, R4).
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createElement, type ReactNode } from 'react';
import { renderHook } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const h = vi.hoisted(() => {
  const estado = {
    itensDaCotacao: [] as Array<Record<string, unknown>>,
    falhaNosItens: false,
    errosNosItensDaOc: [] as Array<{ message: string; code?: string }>,
    chamadas: [] as { tabela: string; ops: any[][] }[],
    seq: 0,
  };
  const builder = (tabela: string): any => {
    const reg = { tabela, ops: [] as any[][] };
    estado.chamadas.push(reg);
    const o: any = {};
    for (const k of ['select', 'eq', 'in', 'order', 'limit', 'update', 'insert']) {
      o[k] = (...args: any[]) => { reg.ops.push([k, ...args]); return o; };
    }
    o.single = async () => {
      estado.seq += 1;
      return { data: { id: `po-${estado.seq}`, po_number: `OC-0002${estado.seq}` }, error: null };
    };
    o.then = (ok: any, erro: any) => {
      if (tabela === 'purchase_order_items' && reg.ops.some((op) => op[0] === 'insert') && estado.errosNosItensDaOc.length) {
        return Promise.resolve({ data: null, error: estado.errosNosItensDaOc.shift() }).then(ok, erro);
      }
      if (tabela === 'quote_request_items') {
        return Promise.resolve(estado.falhaNosItens
          ? { data: null, error: { message: 'falha nos itens da cotação' } }
          : { data: estado.itensDaCotacao, error: null }).then(ok, erro);
      }
      if (tabela === 'purchase_orders') return Promise.resolve({ data: [{ po_number: 'OC-00020' }], error: null }).then(ok, erro);
      return Promise.resolve({ data: null, error: null }).then(ok, erro);
    };
    return o;
  };
  const toast = { success: vi.fn(), warning: vi.fn(), error: vi.fn() };
  return { estado, builder, toast };
});

vi.mock('@/integrations/supabase/client', () => ({ supabase: { from: (t: string) => h.builder(t), rpc: vi.fn() } }));
vi.mock('sonner', () => ({ toast: h.toast }));

import { useCreatePOsFromQuote, type BasketChoice } from './use-quote-requests';

function wrapper({ children }: { children: ReactNode }) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
  return createElement(QueryClientProvider, { client: qc }, children);
}

const linhasDaOc = () => h.estado.chamadas
  .filter((c) => c.tabela === 'purchase_order_items')
  .flatMap((c) => c.ops.filter((op) => op[0] === 'insert').flatMap((op) => op[1] as any[]));

const escolha = (itemId: string, supplierId: string, description: string, productId: string | null = null): BasketChoice => ({
  itemId, supplierId, description, quantity: 1, unitPrice: 10, productId,
});

beforeEach(() => {
  h.estado.chamadas.length = 0;
  h.estado.seq = 0;
  h.estado.falhaNosItens = false;
  h.estado.errosNosItensDaOc = [];
  h.estado.itensDaCotacao = [
    { id: 'qi-1', service_order_part_id: 'sop-1', service_order_service_id: null },
    { id: 'qi-2', service_order_part_id: null, service_order_service_id: 'sos-2' },
    { id: 'qi-3', service_order_part_id: null, service_order_service_id: null },
  ];
  h.toast.success.mockClear();
  h.toast.error.mockClear();
});

describe('useCreatePOsFromQuote — o vínculo de linha copiado da cotação', () => {
  it('cada linha da OC leva a linha da OS do item da cotação; sem vínculo, a linha de antes', async () => {
    const { result } = renderHook(() => useCreatePOsFromQuote(), { wrapper });
    await result.current.mutateAsync({
      quoteRequestId: 'q-1', quoteCode: 'COT-00005', serviceOrderId: 'os-1',
      choices: [
        escolha('qi-1', 's-victron', 'Bateria Lítio 100Ah', 'p-bat'),
        escolha('qi-2', 's-loja', 'Cabo PP 2x2,5'),
        escolha('qi-3', 's-loja', 'Fita isolante'),
      ],
    });
    // Os vínculos lidos de uma vez, pelos itens escolhidos, antes de qualquer OC.
    const leitura = h.estado.chamadas.find((c) => c.tabela === 'quote_request_items')!;
    expect(leitura.ops).toEqual([
      ['select', 'id, service_order_part_id, service_order_service_id'],
      ['in', 'id', ['qi-1', 'qi-2', 'qi-3']],
    ]);
    expect(h.estado.chamadas.findIndex((c) => c.tabela === 'quote_request_items'))
      .toBeLessThan(h.estado.chamadas.findIndex((c) => c.tabela === 'purchase_order_items'));
    expect(linhasDaOc().map((l) => [l.description, l.service_order_part_id ?? null, l.service_order_service_id ?? null])).toEqual([
      ['Bateria Lítio 100Ah', 'sop-1', null],
      ['Cabo PP 2x2,5', null, 'sos-2'],
      ['Fita isolante', null, null],
    ]);
    const semVinculo = linhasDaOc().find((l) => l.description === 'Fita isolante')!;
    expect('service_order_part_id' in semVinculo || 'service_order_service_id' in semVinculo).toBe(false);
  });

  it('a leitura dos vínculos falha: nenhuma OC é criada (o erro aparece)', async () => {
    h.estado.falhaNosItens = true;
    const { result } = renderHook(() => useCreatePOsFromQuote(), { wrapper });
    await expect(result.current.mutateAsync({
      quoteRequestId: 'q-1', quoteCode: 'COT-00005', serviceOrderId: 'os-1',
      choices: [escolha('qi-1', 's-victron', 'Bateria Lítio 100Ah', 'p-bat')],
    })).rejects.toMatchObject({ message: 'falha nos itens da cotação' });
    expect(h.estado.chamadas.some((c) => c.tabela === 'purchase_orders' && c.ops.some((op) => op[0] === 'insert'))).toBe(false);
    expect(linhasDaOc()).toEqual([]);
  });

  it('o banco sem as colunas do vínculo (PGRST204): a OC sai, com as linhas gravadas de novo sem as chaves de vínculo', async () => {
    h.estado.errosNosItensDaOc = [{ code: 'PGRST204', message: "Could not find the 'service_order_part_id' column of 'purchase_order_items' in the schema cache" }];
    const { result } = renderHook(() => useCreatePOsFromQuote(), { wrapper });
    await result.current.mutateAsync({
      quoteRequestId: 'q-1', quoteCode: 'COT-00005', serviceOrderId: 'os-1',
      choices: [escolha('qi-1', 's-victron', 'Bateria Lítio 100Ah', 'p-bat')],
    });
    const inserts = h.estado.chamadas.filter((c) => c.tabela === 'purchase_order_items')
      .map((c) => c.ops.filter((op) => op[0] === 'insert').flatMap((op) => op[1] as any[])).filter((l) => l.length);
    expect(inserts).toHaveLength(2);
    expect(inserts[0][0].service_order_part_id).toBe('sop-1');
    expect(inserts[1].map((l) => l.description)).toEqual(['Bateria Lítio 100Ah']);
    expect('service_order_part_id' in inserts[1][0]).toBe(false);
    expect(h.toast.success).toHaveBeenCalled();
  });
});
