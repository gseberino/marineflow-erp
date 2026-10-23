// A montagem da necessidade de compra na tela (Agenda de Produção, Fase 0, P5 — 24/10/2026).
//
// O hook é o espelho de get_os_purchase_needs. O que estes testes protegem:
//  1. o "já pedido" e o que vem a caminho saem da view v_oc_itens_a_caminho — nunca mais de
//     purchase_order_items com a lista de status no código (OC velha e de OS faturada contavam);
//  2. o status da OS é lido e a reserva da PRÓPRIA OS sai do reservado;
//  3. leitura com erro LANÇA (lista vazia diria "nada a comprar"); só a classificação do texto livre
//     mantém o material na conta quando falha;
//  4. os MESMOS números de supabase/tests/purchase_needs_reserva_e_a_caminho.sql (casos A, B, D, E, F2, G);
//  5. a idade (conta_como_ja_pedido) corta só o "já pedido" de catálogo, nunca o que a própria OS espera
//     chegar (revisão de 23/10).
import { beforeEach, describe, expect, it, vi } from 'vitest';

type Linha = Record<string, any>;

const banco = vi.hoisted(() => ({
  tabelas: {} as Record<string, Linha[]>,
  falham: new Set<string>(),
  lidas: [] as string[],
  classificacao: {} as Record<string, boolean>,
  classificacaoFalha: false,
}));

vi.mock('@/integrations/supabase/client', () => {
  const from = (tabela: string) => {
    banco.lidas.push(tabela);
    const filtros: Array<(l: Linha) => boolean> = [];
    const ordens: Array<[string, boolean]> = [];
    let unico = false;
    const resultado = () => {
      if (banco.falham.has(tabela)) return { data: null, error: { message: `falha em ${tabela}` } };
      let r = (banco.tabelas[tabela] ?? []).filter((l) => filtros.every((f) => f(l)));
      for (const [col, asc] of [...ordens].reverse()) {
        r = [...r].sort((a, b) => String(a[col] ?? '').localeCompare(String(b[col] ?? '')) * (asc ? 1 : -1));
      }
      return { data: unico ? (r[0] ?? null) : r, error: null };
    };
    const q: any = {
      select: () => q,
      eq: (c: string, v: unknown) => { filtros.push((l) => l[c] === v); return q; },
      in: (c: string, vs: unknown[]) => { filtros.push((l) => vs.includes(l[c])); return q; },
      is: (c: string, v: unknown) => { filtros.push((l) => (l[c] ?? null) === v); return q; },
      gt: (c: string, v: number) => { filtros.push((l) => Number(l[c]) > v); return q; },
      order: (c: string, o?: { ascending?: boolean }) => { ordens.push([c, o?.ascending !== false]); return q; },
      maybeSingle: () => { unico = true; return q; },
      then: (ok: any, erro: any) => Promise.resolve(resultado()).then(ok, erro),
    };
    return q;
  };
  const rpc = (nome: string, args: { p_textos: string[] }) => {
    if (nome !== 'classify_free_text_materials') throw new Error(`rpc inesperada: ${nome}`);
    if (banco.classificacaoFalha) return Promise.resolve({ data: null, error: { message: 'falhou' } });
    return Promise.resolve({
      data: Object.fromEntries(args.p_textos.map((t) => [t, banco.classificacao[t] ?? true])),
      error: null,
    });
  };
  return { supabase: { from, rpc } };
});

import { fetchPurchaseNeeds } from './use-purchase-needs';

// ── O cenário do teste SQL ──────────────────────────────────────────────────────────────────────
const P1 = 'p1-cerbo';   // físico 1; reservado 1 (pela OS A, aprovada)
const P2 = 'p2-fusivel'; // físico 2; reservado 2 (as duas linhas da OS D, aprovada)
const P3 = 'p3-cabo';    // físico 0; 1 a caminho na única OC viva com produto
const CONVERSAO = 'Conversão do sistema de refrigeração para 12V — Refrigerador TESTE';

function peca(id: string, so: string, produto: string, qtd: number, nome: string, criada: string): Linha {
  return {
    id, service_order_id: so, product_id: produto, quantity: qtd, unit_cost_snapshot: 30,
    products: { name: nome, unit: 'un' }, created_at: criada,
  };
}

function montarBanco() {
  banco.tabelas = {
    service_orders: [
      { id: 'A', status: 'approved' },
      { id: 'B', status: 'open' },
      { id: 'D', status: 'approved' },
      { id: 'E', status: 'open' },
      { id: 'G', status: 'awaiting_parts' },
    ],
    service_order_parts: [
      peca('a1', 'A', P1, 1, 'TESTE P5 — Cerbo GX', '2026-10-24T10:00:00Z'),
      peca('b1', 'B', P1, 1, 'TESTE P5 — Cerbo GX', '2026-10-24T10:00:01Z'),
      peca('d1', 'D', P2, 1, 'TESTE P5 — Fusível MIDI', '2026-10-24T10:00:02Z'),
      peca('d2', 'D', P2, 1, 'TESTE P5 — Fusível MIDI', '2026-10-24T10:00:03Z'),
      peca('e1', 'E', P3, 2, 'TESTE P5 — Cabo 16mm', '2026-10-24T10:00:04Z'),
    ],
    service_order_services: [
      {
        id: 'g1', service_order_id: 'G', service_id: null, name_snapshot: CONVERSAO,
        billing_unit_snapshot: 'unit', quantity: 1, unit_price_snapshot: 2500, created_at: '2026-10-24T10:00:05Z',
      },
    ],
    product_availability: [
      { id: P1, stock_quantity: 1, reserved_quantity: 1 },
      { id: P2, stock_quantity: 2, reserved_quantity: 2 },
      { id: P3, stock_quantity: 0, reserved_quantity: 0 },
    ],
    // O que a VIEW devolve: toda OC draft/sent/partial. A da OS faturada (E1) e a de 61 dias (E2) vêm
    // com conta_como_ja_pedido = false — não abatem a falta, e o hook tem de filtrar isso.
    v_oc_itens_a_caminho: [
      {
        purchase_order_item_id: 'poi-1', po_number: 'OC-TESTE-P5-1', service_order_id: 'F', product_id: P3,
        description: 'TESTE P5 — Cabo 16mm', quantity: 2, received_qty: 0, pendente: 2, unit_cost: 12,
        po_criada_em: '2026-10-24T08:58:00Z', conta_como_ja_pedido: false,
      },
      {
        purchase_order_item_id: 'poi-2', po_number: 'OC-TESTE-P5-2', service_order_id: null, product_id: P3,
        description: 'TESTE P5 — Cabo 16mm', quantity: 2, received_qty: 0, pendente: 2, unit_cost: 12,
        po_criada_em: '2026-08-24T08:59:00Z', conta_como_ja_pedido: false,
      },
      {
        purchase_order_item_id: 'poi-3', po_number: 'OC-TESTE-P5-3', service_order_id: null, product_id: P3,
        description: 'TESTE P5 — Cabo 16mm', quantity: 1, received_qty: 0, pendente: 1, unit_cost: 12,
        po_criada_em: '2026-10-24T09:00:00Z', conta_como_ja_pedido: true,
      },
      {
        purchase_order_item_id: 'poi-4b', po_number: 'OC-TESTE-P5-4', service_order_id: 'E', product_id: null,
        description: 'Suporte TESTE P5 (já chegou)', quantity: 1, received_qty: 1, pendente: 0, unit_cost: 5,
        po_criada_em: '2026-10-24T09:01:00Z', conta_como_ja_pedido: true,
      },
      {
        purchase_order_item_id: 'poi-4a', po_number: 'OC-TESTE-P5-4', service_order_id: 'E', product_id: null,
        description: 'Compressor TESTE P5', quantity: 1, received_qty: 0, pendente: 1, unit_cost: 900,
        po_criada_em: '2026-10-24T09:01:00Z', conta_como_ja_pedido: true,
      },
      {
        purchase_order_item_id: 'poi-6', po_number: 'OC-TESTE-P5-6', service_order_id: 'G', product_id: null,
        description: 'Compressor 12V TESTE', quantity: 1, received_qty: 0, pendente: 1, unit_cost: 0,
        po_criada_em: '2026-10-24T09:02:00Z', conta_como_ja_pedido: true,
      },
    ],
    // Se o hook voltar a ler a tabela crua, o teste acusa (ver "nunca lê purchase_order_items").
    purchase_order_items: [{ product_id: P3, quantity: 50, received_qty: 0, purchase_orders: { status: 'sent' } }],
  };
  banco.classificacao = { [CONVERSAO]: false };
}

beforeEach(() => {
  montarBanco();
  banco.falham = new Set();
  banco.lidas = [];
  banco.classificacaoFalha = false;
});

describe('fetchPurchaseNeeds — reserva própria', () => {
  it('A: OS aprovada com a peça reservada para ela mesma → em estoque', async () => {
    const r = await fetchPurchaseNeeds('A');
    expect(r.items).toHaveLength(1);
    expect(r.items[0]).toMatchObject({ status: 'ok', available: 1, shortage: 0 });
    expect(r.shortageCount).toBe(0);
  });

  it('B: OS aberta (não reserva) com a mesma peça reservada pela A → sem estoque', async () => {
    const r = await fetchPurchaseNeeds('B');
    expect(r.items[0]).toMatchObject({ status: 'missing', available: 0, shortage: 1 });
    expect(r.shortageCount).toBe(1);
  });

  it('D: duas linhas do mesmo produto somam a reserva própria → as duas cobertas', async () => {
    const r = await fetchPurchaseNeeds('D');
    expect(r.items.map((i) => [i.status, i.available])).toEqual([['ok', 1], ['ok', 1]]);
    expect(r.needsPurchase).toBe(false);
  });

  it('o status vem da OS: a mesma OS A, se voltasse a aberta, não devolveria reserva nenhuma', async () => {
    banco.tabelas.service_orders[0].status = 'open';
    const r = await fetchPurchaseNeeds('A');
    expect(r.items[0].status).toBe('missing');
  });
});

describe('fetchPurchaseNeeds — já pedido e a caminho pela view', () => {
  it('E: o já pedido da peça vem da view (1 de 2) e o compressor de texto livre aparece a caminho', async () => {
    const r = await fetchPurchaseNeeds('E');
    const cabo = r.items.find((i) => i.origin === 'part')!;
    expect(cabo).toMatchObject({ onOrder: 1, shortage: 1, status: 'missing' });
    expect(r.shortageCount).toBe(1);
    expect(r.estimatedCost).toBe(30);
    const aCaminho = r.items.filter((i) => i.origin === 'purchase_order');
    expect(aCaminho).toEqual([{
      sourceId: 'poi-4a', origin: 'purchase_order', productId: null, description: 'Compressor TESTE P5',
      unit: null, required: 1, available: 0, onOrder: 1, shortage: 0, status: 'on_order', unitCost: 900,
      purchaseOrderNumber: 'OC-TESTE-P5-4',
    }]);
    // O compressor não entra em shortages nem no custo.
    expect(r.shortages.map((s) => s.sourceId)).toEqual(['e1']);
  });

  it('E1/E2: a OC de OS faturada e a de 61 dias estão na view, mas não abatem a falta da peça', async () => {
    const r = await fetchPurchaseNeeds('E');
    // Sem o filtro de conta_como_ja_pedido o já pedido seria 1 + 2 + 2 e a falta, 0.
    expect(r.items.find((i) => i.origin === 'part')).toMatchObject({ onOrder: 1, shortage: 1 });
  });

  it('F2: texto livre de OC da própria OS com 61 dias continua a caminho (o corte de idade é só do já pedido)', async () => {
    banco.tabelas.v_oc_itens_a_caminho.push({
      purchase_order_item_id: 'poi-7', po_number: 'OC-TESTE-P5-7', service_order_id: 'E', product_id: null,
      description: 'Bomba TESTE P5 (OC de 61 dias)', quantity: 1, received_qty: 0, pendente: 1, unit_cost: 50,
      po_criada_em: '2026-08-24T09:03:00Z', conta_como_ja_pedido: false,
    });
    const r = await fetchPurchaseNeeds('E');
    const aCaminho = r.items.filter((i) => i.origin === 'purchase_order');
    // A ordem é a da CTE: OC mais antiga primeiro.
    expect(aCaminho.map((i) => [i.purchaseOrderNumber, i.description, i.status, i.shortage])).toEqual([
      ['OC-TESTE-P5-7', 'Bomba TESTE P5 (OC de 61 dias)', 'on_order', 0],
      ['OC-TESTE-P5-4', 'Compressor TESTE P5', 'on_order', 0],
    ]);
    // E nada da conta de compra muda.
    expect(r.shortageCount).toBe(1);
    expect(r.estimatedCost).toBe(30);
  });

  it('G (o caso da OS-00104): conversão é serviço, falta 0, e o compressor continua a caminho', async () => {
    const r = await fetchPurchaseNeeds('G');
    expect(r.shortageCount).toBe(0);
    expect(r.needsPurchase).toBe(false);
    expect(r.items).toHaveLength(1);
    expect(r.items[0]).toMatchObject({ origin: 'purchase_order', status: 'on_order', purchaseOrderNumber: 'OC-TESTE-P5-6' });
  });

  it('nunca lê purchase_order_items (o "já pedido" com status no código saiu)', async () => {
    for (const os of ['A', 'B', 'D', 'E', 'G']) await fetchPurchaseNeeds(os);
    expect(banco.lidas).not.toContain('purchase_order_items');
    expect(banco.lidas).toContain('v_oc_itens_a_caminho');
    expect(banco.lidas).toContain('service_orders');
  });
});

describe('fetchPurchaseNeeds — leitura com erro lança', () => {
  for (const tabela of ['service_orders', 'service_order_parts', 'service_order_services', 'product_availability', 'v_oc_itens_a_caminho']) {
    it(`erro em ${tabela} lança (não vira "nada a comprar")`, async () => {
      banco.falham.add(tabela);
      await expect(fetchPurchaseNeeds('E')).rejects.toMatchObject({ message: `falha em ${tabela}` });
    });
  }

  it('erro na classificação do texto livre mantém o material na conta (comportamento documentado)', async () => {
    banco.classificacaoFalha = true;
    const r = await fetchPurchaseNeeds('G');
    expect(r.shortageCount).toBe(1);
    expect(r.items.map((i) => i.origin)).toEqual(['free_text', 'purchase_order']);
  });
});
