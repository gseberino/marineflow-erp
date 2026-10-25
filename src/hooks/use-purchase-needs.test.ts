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
//     chegar (revisão de 23/10);
//  6. (Fase 1, P2) a 5ª leitura, os_material: o que o dono disse entra na conta DEPOIS de comItensACaminho,
//     com os MESMOS números de supabase/tests/agenda_fase1_material.sql (OS M, casos B); erro lança.
//  7. (Fase 4, P2) a 6ª leitura, as linhas de OC desta OS ligadas a uma linha de serviço (purchase_order_items, com a
//     OC embutida; fora de cancelada): o texto livre com OC ligada vira UM item, com os MESMOS números do caso L de
//     purchase_needs_reserva_e_a_caminho.sql; o material citado pelo dono entra sem preço (caso O); a coluna ausente
//     (42703, o front antes da migration) é "sem vínculo"; outro erro lança.
import { beforeEach, describe, expect, it, vi } from 'vitest';

type Linha = Record<string, any>;

const banco = vi.hoisted(() => ({
  tabelas: {} as Record<string, Linha[]>,
  falham: new Set<string>(),
  /** erro com código por tabela (o que o PostgREST devolve de verdade: PGRST205 = a tabela não existe) */
  erros: {} as Record<string, { code: string; message: string }>,
  lidas: [] as string[],
  /** cada leitura com os filtros que levou ("eq purchase_orders.service_order_id L", "not service_order_service_id is null") */
  consultas: [] as Array<{ tabela: string; filtros: string[] }>,
  classificacao: {} as Record<string, boolean>,
  classificacaoFalha: false,
}));

vi.mock('@/integrations/supabase/client', () => {
  /** "purchase_orders.status" lê o embed (como o PostgREST faz com o filtro na tabela embutida). */
  const campo = (l: Linha, c: string) => c.split('.').reduce<any>((v, k) => (v == null ? v : v[k]), l);
  const from = (tabela: string) => {
    banco.lidas.push(tabela);
    const consulta = { tabela, filtros: [] as string[] };
    banco.consultas.push(consulta);
    const filtros: Array<(l: Linha) => boolean> = [];
    const ordens: Array<[string, boolean]> = [];
    let unico = false;
    const resultado = () => {
      if (banco.falham.has(tabela)) return { data: null, error: { message: `falha em ${tabela}` } };
      if (banco.erros[tabela]) return { data: null, error: banco.erros[tabela] };
      let r = (banco.tabelas[tabela] ?? []).filter((l) => filtros.every((f) => f(l)));
      for (const [col, asc] of [...ordens].reverse()) {
        r = [...r].sort((a, b) => String(a[col] ?? '').localeCompare(String(b[col] ?? '')) * (asc ? 1 : -1));
      }
      return { data: unico ? (r[0] ?? null) : r, error: null };
    };
    const q: any = {
      select: () => q,
      eq: (c: string, v: unknown) => { consulta.filtros.push(`eq ${c} ${v}`); filtros.push((l) => campo(l, c) === v); return q; },
      neq: (c: string, v: unknown) => { consulta.filtros.push(`neq ${c} ${v}`); filtros.push((l) => campo(l, c) !== v); return q; },
      not: (c: string, op: string, v: unknown) => {
        consulta.filtros.push(`not ${c} ${op} ${v}`);
        if (op !== 'is') throw new Error(`not ${op} não simulado`);
        filtros.push((l) => (campo(l, c) ?? null) !== v);
        return q;
      },
      in: (c: string, vs: unknown[]) => { filtros.push((l) => vs.includes(campo(l, c))); return q; },
      is: (c: string, v: unknown) => { filtros.push((l) => (campo(l, c) ?? null) === v); return q; },
      gt: (c: string, v: number) => { filtros.push((l) => Number(campo(l, c)) > v); return q; },
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

function material(id: string, so: string, over: Linha): Linha {
  return {
    id, service_order_id: so, service_order_part_id: null, service_order_service_id: null, purchase_order_item_id: null,
    origem: 'peca', situacao: 'falta', fonte: 'dono', quantidade_necessaria: '1.000', quantidade_na_mao: '0.000',
    ...over,
  };
}

// A OS L (Fase 4, P2): o caso L de purchase_needs_reserva_e_a_caminho.sql — uma linha de OC ligada, com a OC embutida
// como o PostgREST devolve no purchase_orders!inner.
const CONVERSAO_L = 'Conversão do sistema de refrigeração para 12V — TESTE L';
function ligadaL(id: string, linha: string, numero: string, status: string, minuto: number, qtd: string, recebido: string): Linha {
  return {
    id, product_id: null, quantity: qtd, received_qty: recebido, service_order_service_id: linha,
    purchase_orders: { po_number: numero, status, service_order_id: 'L', created_at: `2026-10-25T10:0${minuto}:00+00:00` },
  };
}
function livreL(id: string, nome: string, qtd: number, preco: number, segundo: number): Linha {
  return {
    id, service_order_id: 'L', service_id: null, name_snapshot: nome, billing_unit_snapshot: 'unit', quantity: qtd,
    unit_price_snapshot: preco, created_at: `2026-10-25T09:00:0${segundo}Z`,
  };
}
function aCaminhoL(id: string, numero: string, descricao: string, qtd: number, pendente: number, custo: number, minuto: number): Linha {
  return {
    purchase_order_item_id: id, po_number: numero, service_order_id: 'L', product_id: null, description: descricao,
    quantity: qtd, received_qty: qtd - pendente, pendente, unit_cost: custo, po_criada_em: `2026-10-25T10:0${minuto}:00+00:00`,
    conta_como_ja_pedido: true,
  };
}
// A OS O (Fase 4, P2): o caso O — o material citado pelo dono, com os ids em ordem (a conta lê por id).
function donoO(n: number, descricao: string, qtd: string, situacao: string, naMao = '0.000'): Linha {
  return material(`f5000000-0000-4000-8000-00000000000${n}`, 'O', {
    descricao, origem: 'dono', situacao, quantidade_necessaria: qtd, quantidade_na_mao: naMao,
  });
}

function montarBanco() {
  banco.tabelas = {
    service_orders: [
      { id: 'A', status: 'approved' },
      { id: 'B', status: 'open' },
      { id: 'D', status: 'approved' },
      { id: 'E', status: 'open' },
      { id: 'G', status: 'awaiting_parts' },
      { id: 'M', status: 'open' },
      { id: 'L', status: 'awaiting_parts' },
      { id: 'O', status: 'open' },
    ],
    service_order_parts: [
      peca('a1', 'A', P1, 1, 'TESTE P5 — Cerbo GX', '2026-10-24T10:00:00Z'),
      peca('b1', 'B', P1, 1, 'TESTE P5 — Cerbo GX', '2026-10-24T10:00:01Z'),
      peca('d1', 'D', P2, 1, 'TESTE P5 — Fusível MIDI', '2026-10-24T10:00:02Z'),
      peca('d2', 'D', P2, 1, 'TESTE P5 — Fusível MIDI', '2026-10-24T10:00:03Z'),
      peca('e1', 'E', P3, 2, 'TESTE P5 — Cabo 16mm', '2026-10-24T10:00:04Z'),
      // OS M: o cenário de agenda_fase1_material.sql.
      { ...peca('m1', 'M', 'pm1', 1, 'TESTE AG2 — Cerbo', '2026-10-24T11:00:00Z'), unit_cost_snapshot: 1900 },
      { ...peca('m2', 'M', 'pm2', 8, 'TESTE AG2 — Fusível', '2026-10-24T11:00:01Z'), unit_cost_snapshot: 25 },
      { ...peca('m3', 'M', 'pm3', 1, 'TESTE AG2 — Cabo', '2026-10-24T11:00:02Z'), unit_cost_snapshot: 210 },
      { ...peca('m4', 'M', 'pm4', 1, 'TESTE AG2 — Painel', '2026-10-24T11:00:03Z'), unit_cost_snapshot: 1250 },
      { ...peca('o1', 'O', 'p-o', 1, 'TESTE P5 — Cabo O', '2026-10-25T11:00:00Z'), unit_cost_snapshot: 100 },
    ],
    service_order_services: [
      {
        id: 'g1', service_order_id: 'G', service_id: null, name_snapshot: CONVERSAO,
        billing_unit_snapshot: 'unit', quantity: 1, unit_price_snapshot: 2500, created_at: '2026-10-24T10:00:05Z',
      },
      {
        id: 'm5', service_order_id: 'M', service_id: null, name_snapshot: 'Conector de cabo de dados AG2',
        billing_unit_snapshot: 'unit', quantity: 2, unit_price_snapshot: 120, created_at: '2026-10-24T11:00:04Z',
      },
      livreL('l1', 'Cabo PP 2x2,5mm (caso L)', 10, 12, 1),
      livreL('l2', 'Terminal olhal 6mm (caso L)', 4, 3, 2),
      livreL('l3', CONVERSAO_L, 1, 2500, 3),
      livreL('l4', 'Bomba de porão 12V (caso L)', 2, 300, 4),
      livreL('l5', 'Fusível MIDI 100A (caso L)', 3, 40, 5),
    ],
    product_availability: [
      { id: P1, stock_quantity: 1, reserved_quantity: 1 },
      { id: P2, stock_quantity: 2, reserved_quantity: 2 },
      { id: P3, stock_quantity: 0, reserved_quantity: 0 },
      ...['pm1', 'pm2', 'pm3', 'pm4', 'p-o'].map((id) => ({ id, stock_quantity: 0, reserved_quantity: 0 })),
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
      // OS L: a view só traz as OCs abertas (a L4 recebida e a L5 cancelada não); a L6 é sem vínculo.
      aCaminhoL('i-l1', 'OC-TESTE-P5-L1', 'Cabo PP 2x2,5mm', 6, 6, 12, 1),
      aCaminhoL('i-l2', 'OC-TESTE-P5-L2', 'Terminal olhal 6mm', 4, 3, 3, 2),
      aCaminhoL('i-l3', 'OC-TESTE-P5-L3', 'Compressor TESTE L', 1, 1, 0, 3),
      aCaminhoL('i-l6', 'OC-TESTE-P5-L6', 'Suporte TESTE L', 1, 1, 5, 6),
    ],
    // Se o hook voltar a ler a tabela crua para o "já pedido", o teste acusa (ver "o já pedido não vem de
    // purchase_order_items"): a 1ª linha é uma OC enviada de 50 cabos, sem vínculo de linha. As outras são as linhas
    // ligadas da OS L (Fase 4, P2) — o caso L de purchase_needs_reserva_e_a_caminho.sql —, com a OC embutida.
    purchase_order_items: [
      { id: 'poi-armadilha', product_id: P3, quantity: 50, received_qty: 0, service_order_service_id: null,
        purchase_orders: { po_number: 'OC-ARMADILHA', status: 'sent', service_order_id: 'E', created_at: '2026-10-24T08:00:00+00:00' } },
      ligadaL('i-l1', 'l1', 'OC-TESTE-P5-L1', 'sent', 1, '6.000', '0.000'),
      ligadaL('i-l2', 'l2', 'OC-TESTE-P5-L2', 'partial', 2, '4.000', '1.000'),
      ligadaL('i-l3', 'l3', 'OC-TESTE-P5-L3', 'draft', 3, '1.000', '0.000'),
      ligadaL('i-l4', 'l4', 'OC-TESTE-P5-L4', 'received', 4, '2.000', '0.000'),
      ligadaL('i-l5', 'l1', 'OC-TESTE-P5-L5', 'cancelled', 5, '5.000', '0.000'),
    ],
    // O que o PostgREST devolve de os_material (numeric como string). As linhas da OS M são as do dono;
    // a da OS A foi copiada pela sincronização (fonte estoque) e não muda nada.
    os_material: [
      material('om1', 'M', { service_order_part_id: 'm1', situacao: 'na_mao', quantidade_necessaria: '1.000', quantidade_na_mao: '1.000' }),
      material('om2', 'M', { service_order_part_id: 'm2', quantidade_necessaria: '8.000', quantidade_na_mao: '3.000' }),
      material('om3', 'M', { service_order_part_id: 'm3', situacao: 'dispensado' }),
      material('om4', 'M', { service_order_part_id: 'm4', situacao: 'a_caminho' }),
      material('om5', 'M', { service_order_service_id: 'm5', origem: 'texto_livre', situacao: 'comprado', quantidade_necessaria: '2.000' }),
      material('om6', 'M', { service_order_service_id: 'm5', origem: 'dono', situacao: 'dispensado', quantidade_necessaria: '4.000' }),
      material('oa1', 'A', { service_order_part_id: 'a1', situacao: 'na_mao', fonte: 'estoque', quantidade_na_mao: '1.000' }),
      donoO(1, 'Parafuso inox M6 (citado)', '8.000', 'falta'),
      donoO(2, 'Abraçadeira (citada)', '2.000', 'comprado'),
      donoO(3, 'Fita de autofusão (citada)', '3.000', 'a_caminho', '1.000'),
      donoO(4, 'Graxa (citada)', '1.000', 'dispensado'),
      donoO(5, 'Silicone (citado)', '1.000', 'na_mao', '1.000'),
      donoO(6, 'Lixa (citada)', '5.000', 'falta', '2.000'),
    ],
  };
  banco.classificacao = { [CONVERSAO]: false, [CONVERSAO_L]: false };
}

beforeEach(() => {
  montarBanco();
  banco.falham = new Set();
  banco.erros = {};
  banco.lidas = [];
  banco.consultas = [];
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

  it('o já pedido não vem de purchase_order_items: a única leitura dela é a das linhas ligadas desta OS (Fase 4)', async () => {
    for (const os of ['A', 'B', 'D', 'E', 'G']) await fetchPurchaseNeeds(os);
    expect(banco.lidas).toContain('v_oc_itens_a_caminho');
    expect(banco.lidas).toContain('service_orders');
    const leituras = banco.consultas.filter((c) => c.tabela === 'purchase_order_items');
    expect(leituras).toHaveLength(5);
    for (const c of leituras) {
      expect(c.filtros).toContain('not service_order_service_id is null');
      expect(c.filtros).toContain('neq purchase_orders.status cancelled');
      expect(c.filtros.some((f) => f.startsWith('eq purchase_orders.service_order_id '))).toBe(true);
    }
    // A armadilha (OC de 50 cabos sem vínculo, da OS E) não entrou: o cabo da E segue com 1 já pedido.
    const r = await fetchPurchaseNeeds('E');
    expect(r.items.find((i) => i.origin === 'part')).toMatchObject({ onOrder: 1, shortage: 1 });
  });
});

describe('fetchPurchaseNeeds — a OC ligada e o material citado (Fase 4, P2)', () => {
  it('OS L: os MESMOS números do caso L de purchase_needs_reserva_e_a_caminho.sql (L1, L2)', async () => {
    const r = await fetchPurchaseNeeds('L');
    expect(r.items.map((i) => [i.sourceId, i.origin, i.status, i.available, i.onOrder, i.shortage, i.purchaseOrderNumber ?? null])).toEqual([
      ['l1', 'free_text', 'uncatalogued', 0, 6, 4, 'OC-TESTE-P5-L1'],
      ['l2', 'free_text', 'on_order', 1, 3, 0, 'OC-TESTE-P5-L2'],
      ['l4', 'free_text', 'ok', 2, 0, 0, 'OC-TESTE-P5-L4'],
      ['l5', 'free_text', 'uncatalogued', 0, 0, 3, null],
      ['i-l3', 'purchase_order', 'on_order', 0, 1, 0, 'OC-TESTE-P5-L3'],
      ['i-l6', 'purchase_order', 'on_order', 0, 1, 0, 'OC-TESTE-P5-L6'],
    ]);
    expect(r.shortages.map((s) => s.sourceId)).toEqual(['l1', 'l5']);
    expect(r.shortageCount).toBe(2);
    expect(r.estimatedCost).toBe(168);
  });

  it('OS O: os MESMOS números do caso O (O1, O2): o material citado no fim, sem preço; semPreco 2', async () => {
    const r = await fetchPurchaseNeeds('O');
    const id = (n: number) => `f5000000-0000-4000-8000-00000000000${n}`;
    expect(r.items.map((i) => [i.sourceId, i.origin, i.status, i.available, i.onOrder, i.shortage, i.unitCost])).toEqual([
      ['o1', 'part', 'missing', 0, 0, 1, 100],
      [id(1), 'dono', 'uncatalogued', 0, 0, 8, 0],
      [id(2), 'dono', 'on_order', 0, 2, 0, 0],
      [id(3), 'dono', 'on_order', 1, 2, 0, 0],
      [id(6), 'dono', 'uncatalogued', 2, 0, 3, 0],
    ]);
    expect(r.items.find((i) => i.sourceId === id(1))).toMatchObject({ description: 'Parafuso inox M6 (citado)', semPreco: true });
    expect(r.shortages.map((s) => s.sourceId)).toEqual(['o1', id(1), id(6)]);
    expect(r.shortageCount).toBe(3);
    expect(r.estimatedCost).toBe(100);
    expect(r.semPreco).toBe(2);
  });

  it('o vínculo ainda não existe (42703, o front publicado antes da migration): a conta de antes, sem vínculo', async () => {
    banco.erros = { purchase_order_items: { code: '42703', message: 'column purchase_order_items.service_order_service_id does not exist' } };
    const r = await fetchPurchaseNeeds('L');
    // Sem o vínculo: os 4 textos livres pedem compra inteiros e as 4 linhas da view ficam a caminho, como antes.
    expect(r.shortageCount).toBe(4);
    expect(r.items.filter((i) => i.origin === 'purchase_order').map((i) => i.sourceId)).toEqual(['i-l1', 'i-l2', 'i-l3', 'i-l6']);
  });

  it('as linhas ligadas com outro erro (permissão, rede, timeout) lançam', async () => {
    for (const code of ['42501', '57014', 'PGRST301']) {
      banco.erros = { purchase_order_items: { code, message: `falha ${code}` } };
      await expect(fetchPurchaseNeeds('L'), code).rejects.toMatchObject({ code });
    }
  });
});

describe('fetchPurchaseNeeds — leitura com erro lança', () => {
  for (const tabela of ['service_orders', 'service_order_parts', 'service_order_services', 'product_availability', 'v_oc_itens_a_caminho', 'os_material', 'purchase_order_items']) {
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

describe('fetchPurchaseNeeds — o que o dono disse (os_material, Fase 1)', () => {
  it('OS M: os MESMOS números de agenda_fase1_material.sql (B1–B6)', async () => {
    const r = await fetchPurchaseNeeds('M');
    expect(r.items.map((i) => [i.sourceId, i.status, i.available, i.onOrder, i.shortage, i.informado])).toEqual([
      ['m1', 'ok', 1, 0, 0, 'na_mao'],
      ['m2', 'partial', 3, 0, 5, 'parcial'],
      ['m4', 'on_order', 0, 1, 0, 'a_caminho'],
      ['m5', 'on_order', 0, 2, 0, 'comprado'],
    ]);
    expect(r.shortages.map((s) => s.sourceId)).toEqual(['m2']);
    expect(r.shortageCount).toBe(1);
    expect(r.estimatedCost).toBe(125);
    expect(r.needsPurchase).toBe(true);
  });

  it('lê os_material da própria OS e a linha copiada pelo sistema não muda a conta (OS A)', async () => {
    const r = await fetchPurchaseNeeds('A');
    expect(banco.lidas).toContain('os_material');
    expect(r.items[0]).toMatchObject({ status: 'ok', available: 1, shortage: 0 });
    expect(r.items[0].informado).toBeUndefined();
  });

  it('aplica DEPOIS do que vem a caminho: o dono diz que o compressor chegou (OS G)', async () => {
    banco.tabelas.os_material.push(material('og1', 'G', {
      purchase_order_item_id: 'poi-6', origem: 'oc', situacao: 'na_mao', quantidade_na_mao: '1.000',
    }));
    const r = await fetchPurchaseNeeds('G');
    expect(r.items.find((i) => i.origin === 'purchase_order')).toMatchObject({
      status: 'ok', available: 1, onOrder: 0, shortage: 0, informado: 'na_mao', purchaseOrderNumber: 'OC-TESTE-P5-6',
    });
  });

  it('os_material ainda não existe (front publicado antes da migration): a conta bruta, como a RPC no ar', async () => {
    for (const code of ['PGRST205', '42P01']) {
      banco.erros = { os_material: { code, message: "Could not find the table 'public.os_material' in the schema cache" } };
      const r = await fetchPurchaseNeeds('M');
      expect(r.shortageCount, code).toBe(5);
      expect(r.estimatedCost, code).toBe(3800);
      expect(r.items.some((i) => i.informado), code).toBe(false);
    }
  });

  it('os_material com outro erro (permissão, rede, timeout) continua lançando', async () => {
    for (const code of ['42501', '57014', 'PGRST301']) {
      banco.erros = { os_material: { code, message: `falha ${code}` } };
      await expect(fetchPurchaseNeeds('M'), code).rejects.toMatchObject({ code });
    }
  });

  it('sem linha de material (ou técnico, que não lê os_material): a conta bruta, igual à de antes', async () => {
    banco.tabelas.os_material = [];
    const r = await fetchPurchaseNeeds('M');
    expect(r.shortageCount).toBe(5);
    expect(r.estimatedCost).toBe(3800);
    expect(r.items.some((i) => i.informado)).toBe(false);
  });
});
