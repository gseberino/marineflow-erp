import { describe, expect, it } from 'vitest';
import {
  aplicarSituacaoDoMaterial, comItensACaminho, computePurchaseNeeds, descontarReservaDaPropriaOs,
  isPurchasableFreeText, osReservaEstoque, STATUS_QUE_RESERVAM,
  type ComputeInput, type FreeTextInput, type LinhaDeMaterialInput, type PartInput, type PurchaseNeeds,
} from './purchase-needs';

/* Pina a regra de necessidade LÍQUIDA. Se alguém voltar a comparar
   "estoque físico vs quantidade" (ignorando reserva ou o que já está pedido),
   estes testes quebram. */

const P1 = '11111111-1111-1111-1111-111111111111';
const P2 = '22222222-2222-2222-2222-222222222222';

function input(over: Partial<ComputeInput> = {}): ComputeInput {
  return {
    serviceOrderId: 'os-1',
    parts: [],
    freeTextItems: [],
    availability: [],
    onOrder: [],
    ...over,
  };
}

describe('computePurchaseNeeds — peças do catálogo', () => {
  it('não pede nada quando o disponível cobre a quantidade', () => {
    const r = computePurchaseNeeds(input({
      parts: [{ id: 'a', product_id: P1, quantity: 4, product_name: 'Terminal M8' }],
      availability: [{ id: P1, stock_quantity: 9, reserved_quantity: 0 }],
    }));
    expect(r.needsPurchase).toBe(false);
    expect(r.items[0].status).toBe('ok');
    expect(r.items[0].shortage).toBe(0);
    expect(r.items[0].available).toBe(4);
  });

  it('desconta o RESERVADO — estoque físico sozinho não basta', () => {
    // 10 no físico, 9 reservados para outras OS ⇒ só 1 disponível de verdade.
    const r = computePurchaseNeeds(input({
      parts: [{ id: 'a', product_id: P1, quantity: 4, product_name: 'Fusível MIDI' }],
      availability: [{ id: P1, stock_quantity: 10, reserved_quantity: 9 }],
    }));
    expect(r.items[0].available).toBe(1);
    expect(r.items[0].shortage).toBe(3);
    expect(r.items[0].status).toBe('partial');
    expect(r.needsPurchase).toBe(true);
  });

  it('trata reserva maior que o físico como zero disponível (não negativo)', () => {
    const r = computePurchaseNeeds(input({
      parts: [{ id: 'a', product_id: P1, quantity: 2, product_name: 'Cabo' }],
      availability: [{ id: P1, stock_quantity: 1, reserved_quantity: 5 }],
    }));
    expect(r.items[0].available).toBe(0);
    expect(r.items[0].shortage).toBe(2);
    expect(r.items[0].status).toBe('missing');
  });

  it('desconta o que já está em ordem de compra aberta', () => {
    const r = computePurchaseNeeds(input({
      parts: [{ id: 'a', product_id: P1, quantity: 6, product_name: 'Fusível MIDI' }],
      availability: [{ id: P1, stock_quantity: 0, reserved_quantity: 0 }],
      onOrder: [{ product_id: P1, quantity: 6, received_qty: 0 }],
    }));
    expect(r.items[0].onOrder).toBe(6);
    expect(r.items[0].shortage).toBe(0);
    expect(r.items[0].status).toBe('on_order');
    expect(r.needsPurchase).toBe(false);
  });

  it('conta só o SALDO da OC parcialmente recebida', () => {
    const r = computePurchaseNeeds(input({
      parts: [{ id: 'a', product_id: P1, quantity: 6, product_name: 'Fusível MIDI' }],
      availability: [{ id: P1, stock_quantity: 0, reserved_quantity: 0 }],
      onOrder: [{ product_id: P1, quantity: 6, received_qty: 4 }],
    }));
    expect(r.items[0].onOrder).toBe(2);
    expect(r.items[0].shortage).toBe(4);
  });

  it('não promete a mesma peça para duas linhas do mesmo produto', () => {
    // 3 disponíveis, duas linhas de 2 ⇒ a 1ª leva 2, a 2ª leva 1 e falta 1.
    const r = computePurchaseNeeds(input({
      parts: [
        { id: 'a', product_id: P1, quantity: 2, product_name: 'Parafuso' },
        { id: 'b', product_id: P1, quantity: 2, product_name: 'Parafuso' },
      ],
      availability: [{ id: P1, stock_quantity: 3, reserved_quantity: 0 }],
    }));
    expect(r.items[0].shortage).toBe(0);
    expect(r.items[1].available).toBe(1);
    expect(r.items[1].shortage).toBe(1);
  });

  it('produto sem linha de disponibilidade conta como zero disponível', () => {
    const r = computePurchaseNeeds(input({
      parts: [{ id: 'a', product_id: P2, quantity: 3, product_name: 'Item novo' }],
      availability: [],
    }));
    expect(r.items[0].shortage).toBe(3);
    expect(r.items[0].status).toBe('missing');
  });

  it('aceita numeric vindo como string do PostgREST', () => {
    const r = computePurchaseNeeds(input({
      parts: [{ id: 'a', product_id: P1, quantity: '2.500', unit_cost_snapshot: '10.50', product_name: 'Cabo' }],
      availability: [{ id: P1, stock_quantity: '1.000', reserved_quantity: '0' }],
    }));
    expect(r.items[0].required).toBe(2.5);
    expect(r.items[0].shortage).toBe(1.5);
    expect(r.estimatedCost).toBeCloseTo(15.75, 2);
  });
});

describe('computePurchaseNeeds — itens de texto livre', () => {
  const material: FreeTextInput = {
    id: 's1', service_id: null, name_snapshot: 'Cabo 70mm² vermelho',
    billing_unit_snapshot: 'unit', quantity: 3, unit_price_snapshot: 40,
  };

  it('material sem cadastro sempre precisa ser comprado', () => {
    const r = computePurchaseNeeds(input({ freeTextItems: [material] }));
    expect(r.shortageCount).toBe(1);
    expect(r.items[0].status).toBe('uncatalogued');
    expect(r.items[0].shortage).toBe(3);
    expect(r.estimatedCost).toBe(120);
  });

  it('mão de obra e deslocamento NÃO são compra', () => {
    const r = computePurchaseNeeds(input({
      freeTextItems: [
        { ...material, id: 'h', billing_unit_snapshot: 'hour', name_snapshot: 'Hora técnica' },
        { ...material, id: 'v', billing_unit_snapshot: 'visit', name_snapshot: 'Deslocamento' },
      ],
    }));
    expect(r.needsPurchase).toBe(false);
    expect(r.items).toHaveLength(0);
  });

  it('serviço COM cadastro fica fora (é serviço da casa, não material avulso)', () => {
    const r = computePurchaseNeeds(input({
      freeTextItems: [{ ...material, service_id: 'svc-1' }],
    }));
    expect(r.items).toHaveLength(0);
    expect(isPurchasableFreeText({ ...material, service_id: 'svc-1' })).toBe(false);
  });

  /* Caso real da OS-00060: a tela sugeria cotar "Instalação 2x Carregador DC/DC"
     junto com "Cabo 16mm²". Os dois chegam ao banco idênticos — service_id nulo,
     unidade 'unit' —, então a distinção precisa vir classificada de fora. */
  it('mão de obra digitada à mão não vira item de compra', () => {
    const r = computePurchaseNeeds(input({
      freeTextItems: [
        { ...material, id: 'cabo', name_snapshot: 'Cabo elétrico 16mm²', is_material: true },
        { ...material, id: 'instal', name_snapshot: 'Instalação 2x Carregador DC/DC 50A', is_material: false },
      ],
    }));
    expect(r.items).toHaveLength(1);
    expect(r.items[0].description).toBe('Cabo elétrico 16mm²');
    expect(isPurchasableFreeText({ ...material, is_material: false })).toBe(false);
  });

  it('sem classificação, mantém o comportamento antigo (tudo entra)', () => {
    const r = computePurchaseNeeds(input({ freeTextItems: [material] }));
    expect(r.items).toHaveLength(1);
  });

  it('ignora quantidade zero ou negativa', () => {
    const r = computePurchaseNeeds(input({
      freeTextItems: [{ ...material, quantity: 0 }, { ...material, id: 's2', quantity: -1 }],
    }));
    expect(r.items).toHaveLength(0);
  });
});

describe('computePurchaseNeeds — ordenação e agregados', () => {
  it('resolve primeiro o que não tem nada, depois parcial, depois sem cadastro', () => {
    const r = computePurchaseNeeds(input({
      parts: [
        { id: 'parcial', product_id: P1, quantity: 4, product_name: 'Parcial' },
        { id: 'zerado', product_id: P2, quantity: 2, product_name: 'Zerado' },
      ],
      freeTextItems: [{
        id: 'livre', service_id: null, name_snapshot: 'Livre',
        billing_unit_snapshot: 'unit', quantity: 1,
      }],
      availability: [
        { id: P1, stock_quantity: 2, reserved_quantity: 0 },
        { id: P2, stock_quantity: 0, reserved_quantity: 0 },
      ],
    }));
    expect(r.shortages.map(s => s.sourceId)).toEqual(['zerado', 'parcial', 'livre']);
    expect(r.shortageCount).toBe(3);
    expect(r.needsPurchase).toBe(true);
  });

  it('OS sem peça e sem material não gera aviso', () => {
    const r = computePurchaseNeeds(input());
    expect(r.needsPurchase).toBe(false);
    expect(r.shortageCount).toBe(0);
    expect(r.estimatedCost).toBe(0);
  });
});

/* Montagem dos insumos (24/10/2026, Agenda de Produção, Fase 0, P5). A fórmula pura
   continua recebendo "o reservado"; quem monta tira dele a reserva da própria OS. Os
   mesmos números estão em supabase/tests/purchase_needs_reserva_e_a_caminho.sql. */
describe('descontarReservaDaPropriaOs — a reserva da própria OS não conta contra ela', () => {
  const CERBO: PartInput = { id: 'a', product_id: P1, quantity: 1, product_name: 'Cerbo GX' };

  function necessidade(status: string, parts: PartInput[], fisico: number, reservado: number) {
    const availability = descontarReservaDaPropriaOs(
      [{ id: P1, stock_quantity: fisico, reserved_quantity: reservado }], parts, status,
    );
    return computePurchaseNeeds(input({ parts, availability }));
  }

  it('(a) OS aprovada com 1 Cerbo, físico 1 e reservado 1 por ELA MESMA → em estoque', () => {
    const r = necessidade('approved', [CERBO], 1, 1);
    expect(r.items[0].status).toBe('ok');
    expect(r.items[0].available).toBe(1);
    expect(r.needsPurchase).toBe(false);
    // Antes do P5 (reservado inteiro descontado), a mesma OS acusava falta da própria peça.
    const antes = computePurchaseNeeds(input({
      parts: [CERBO], availability: [{ id: P1, stock_quantity: 1, reserved_quantity: 1 }],
    }));
    expect(antes.items[0].status).toBe('missing');
  });

  it('(b) OS aberta não reserva: físico 1 e reservado 1 por OUTRA → sem estoque', () => {
    const r = necessidade('open', [CERBO], 1, 1);
    expect(r.items[0].status).toBe('missing');
    expect(r.items[0].available).toBe(0);
    expect(r.items[0].shortage).toBe(1);
  });

  it('(c) reservado defasado (0) com reserva própria 1 e físico 1 → disponível 1, nunca 2', () => {
    const [a] = descontarReservaDaPropriaOs(
      [{ id: P1, stock_quantity: 1, reserved_quantity: 0 }], [CERBO], 'approved',
    );
    expect(a.reserved_quantity).toBe(0);
    const r = necessidade('approved', [CERBO], 1, 0);
    expect(r.items[0].available).toBe(1);
    expect(r.items[0].status).toBe('ok');
  });

  it('(d) duas linhas do mesmo produto somam a reserva própria', () => {
    const linhas: PartInput[] = [
      { id: 'a', product_id: P1, quantity: 1, product_name: 'Fusível MIDI' },
      { id: 'b', product_id: P1, quantity: 1, product_name: 'Fusível MIDI' },
    ];
    // físico 2, reservado 2 (as duas linhas desta OS) → as duas cobertas.
    const r = necessidade('approved', linhas, 2, 2);
    expect(r.items.map((i) => i.status)).toEqual(['ok', 'ok']);
    expect(r.shortageCount).toBe(0);
    // físico 2, reservado 3 (1 de outra OS) → só 1 disponível: a 1ª linha leva, a 2ª falta.
    const outra = necessidade('approved', linhas, 2, 3);
    expect(outra.items.map((i) => i.status)).toEqual(['ok', 'missing']);
    expect(outra.shortageCount).toBe(1);
  });

  it('numeric como string e produto sem peça na OS não mudam', () => {
    const r = descontarReservaDaPropriaOs(
      [
        { id: P1, stock_quantity: '3.000', reserved_quantity: '2.000' },
        { id: P2, stock_quantity: 5, reserved_quantity: 4 },
      ],
      [{ product_id: P1, quantity: '1.500' }],
      'scheduled',
    );
    expect(r[0].reserved_quantity).toBe(0.5);
    expect(r[1].reserved_quantity).toBe(4);
  });

  it('status que não reserva devolve a disponibilidade como veio', () => {
    for (const status of ['open', 'draft', 'completed', 'invoiced', 'cancelled', undefined, null]) {
      expect(osReservaEstoque(status)).toBe(false);
      const disp = [{ id: P1, stock_quantity: 1, reserved_quantity: 1 }];
      expect(descontarReservaDaPropriaOs(disp, [CERBO], status)).toEqual(disp);
    }
    for (const status of STATUS_QUE_RESERVAM) expect(osReservaEstoque(status)).toBe(true);
  });
});

describe('comItensACaminho — pedido em OC de texto livre da própria OS', () => {
  const COMPRESSOR = {
    purchase_order_item_id: 'poi-1', po_number: 'OC-00004',
    description: 'Compressor 12V de geladeira SS65', quantity: 1, pendente: 1, unit_cost: 0,
  };

  it('(e) acrescenta o item como on_order sem mudar shortageCount, needsPurchase nem estimatedCost', () => {
    const base = computePurchaseNeeds(input({
      parts: [{ id: 'a', product_id: P1, quantity: 2, unit_cost_snapshot: 30, product_name: 'Fusível' }],
      availability: [{ id: P1, stock_quantity: 0, reserved_quantity: 0 }],
    }));
    const r = comItensACaminho(base, [COMPRESSOR]);
    expect(r.items).toHaveLength(2);
    expect(r.items[1]).toEqual({
      sourceId: 'poi-1', origin: 'purchase_order', productId: null,
      description: 'Compressor 12V de geladeira SS65', unit: null, required: 1,
      available: 0, onOrder: 1, shortage: 0, status: 'on_order', unitCost: 0,
      purchaseOrderNumber: 'OC-00004',
    });
    expect(r.shortages).toEqual(base.shortages);
    expect(r.shortageCount).toBe(base.shortageCount);
    expect(r.needsPurchase).toBe(base.needsPurchase);
    expect(r.estimatedCost).toBe(base.estimatedCost);
  });

  it('OS-00104: sem linha de material, o compressor a caminho impede a lista vazia', () => {
    const vazia = computePurchaseNeeds(input());
    const r = comItensACaminho(vazia, [COMPRESSOR]);
    expect(r.needsPurchase).toBe(false);
    expect(r.shortageCount).toBe(0);
    expect(r.items).toHaveLength(1);
    expect(r.items[0].status).toBe('on_order');
  });

  it('linha toda recebida não entra; numeric como string é normalizado', () => {
    const r = comItensACaminho(computePurchaseNeeds(input()), [
      { ...COMPRESSOR, pendente: '0.000' },
      { ...COMPRESSOR, purchase_order_item_id: 'poi-2', quantity: '2.000', pendente: '1.500', unit_cost: '12.50' },
    ]);
    expect(r.items.map((i) => [i.sourceId, i.required, i.onOrder, i.unitCost])).toEqual([['poi-2', 2, 1.5, 12.5]]);
  });

  it('sem linhas, devolve o mesmo objeto', () => {
    const base = computePurchaseNeeds(input());
    expect(comItensACaminho(base, [])).toBe(base);
  });
});

// ── O que o dono informou (Agenda de Produção, Fase 1, P2) ─────────────────────────────────────────
// O MESMO cenário numérico de supabase/tests/agenda_fase1_material.sql (casos B) e de
// src/hooks/use-purchase-needs.test.ts (OS M): Cerbo na mão, 3 de 8 fusíveis na mão, cabo dispensado,
// painel a caminho e o conector (texto livre, 2) comprado.
describe('aplicarSituacaoDoMaterial — o que o dono disse entra na conta', () => {
  const M = {
    cerbo: 'm1', fusivel: 'm2', cabo: 'm3', painel: 'm4', conector: 'm5',
  };
  const bruto = (): PurchaseNeeds => computePurchaseNeeds(input({
    serviceOrderId: 'os-m',
    parts: [
      { id: M.cerbo, product_id: 'p1', quantity: 1, unit_cost_snapshot: 1900, product_name: 'Cerbo' },
      { id: M.fusivel, product_id: 'p2', quantity: 8, unit_cost_snapshot: 25, product_name: 'Fusível' },
      { id: M.cabo, product_id: 'p3', quantity: 1, unit_cost_snapshot: 210, product_name: 'Cabo' },
      { id: M.painel, product_id: 'p4', quantity: 1, unit_cost_snapshot: 1250, product_name: 'Painel' },
    ],
    freeTextItems: [{
      id: M.conector, service_id: null, name_snapshot: 'Conector de cabo de dados AG2',
      billing_unit_snapshot: 'unit', quantity: 2, unit_price_snapshot: 120, is_material: true,
    }],
  }));
  const linha = (over: Partial<LinhaDeMaterialInput>): LinhaDeMaterialInput => ({
    service_order_part_id: null, service_order_service_id: null, purchase_order_item_id: null,
    origem: 'peca', situacao: 'falta', fonte: 'dono', quantidade_necessaria: 1, quantidade_na_mao: 0,
    ...over,
  });
  const DO_DONO: LinhaDeMaterialInput[] = [
    linha({ service_order_part_id: M.cerbo, situacao: 'na_mao', quantidade_na_mao: '1.000' }),
    linha({ service_order_part_id: M.fusivel, quantidade_necessaria: '8.000', quantidade_na_mao: '3.000' }),
    linha({ service_order_part_id: M.cabo, situacao: 'dispensado' }),
    linha({ service_order_part_id: M.painel, situacao: 'a_caminho' }),
    linha({ service_order_service_id: M.conector, origem: 'texto_livre', situacao: 'comprado', quantidade_necessaria: 2 }),
    // A linha que o dono citou (peça embutida) aponta para a mesma linha de serviço e não entra na compra.
    linha({ service_order_service_id: M.conector, origem: 'dono', situacao: 'dispensado', quantidade_necessaria: 4 }),
  ];
  const item = (r: PurchaseNeeds, id: string) => r.items.find((i) => i.sourceId === id);

  it('o bruto do cenário: 5 itens, 5 faltas, custo 3800 (o caso A0 do SQL)', () => {
    const b = bruto();
    expect(b.items).toHaveLength(5);
    expect(b.shortageCount).toBe(5);
    expect(b.estimatedCost).toBe(3800);
  });

  it('sem linhas, ou só com linha que o sistema copiou, devolve o MESMO objeto', () => {
    const b = bruto();
    expect(aplicarSituacaoDoMaterial(b, [])).toBe(b);
    const copiadas = [
      linha({ service_order_part_id: M.cerbo, situacao: 'na_mao', fonte: 'estoque', quantidade_na_mao: 1 }),
      linha({ service_order_part_id: M.painel, situacao: 'a_caminho', fonte: 'oc' }),
      linha({ service_order_part_id: M.fusivel, situacao: 'comprado', fonte: null, quantidade_necessaria: 8 }),
    ];
    expect(aplicarSituacaoDoMaterial(b, copiadas)).toBe(b);
    // Fato que não muda nada (falta sem quantidade na mão) também.
    expect(aplicarSituacaoDoMaterial(b, [linha({ service_order_part_id: M.cerbo })])).toBe(b);
  });

  it('na_mao → ok; parcial 3 de 8 → partial com falta 5; a_caminho e comprado → on_order', () => {
    const r = aplicarSituacaoDoMaterial(bruto(), DO_DONO);
    expect(item(r, M.cerbo)).toMatchObject({ status: 'ok', available: 1, onOrder: 0, shortage: 0, informado: 'na_mao' });
    expect(item(r, M.fusivel)).toMatchObject({ status: 'partial', available: 3, onOrder: 0, shortage: 5, informado: 'parcial' });
    expect(item(r, M.painel)).toMatchObject({ status: 'on_order', available: 0, onOrder: 1, shortage: 0, informado: 'a_caminho' });
    expect(item(r, M.conector)).toMatchObject({ status: 'on_order', available: 0, onOrder: 2, shortage: 0, informado: 'comprado' });
  });

  it('dispensado some de items e de shortages; o cenário fecha com 1 falta e R$ 125 (o caso B6 do SQL)', () => {
    const r = aplicarSituacaoDoMaterial(bruto(), DO_DONO);
    expect(item(r, M.cabo)).toBeUndefined();
    expect(r.items.map((i) => i.sourceId)).toEqual([M.cerbo, M.fusivel, M.painel, M.conector]);
    expect(r.shortages.map((i) => i.sourceId)).toEqual([M.fusivel]);
    expect(r.shortageCount).toBe(1);
    expect(r.estimatedCost).toBe(125);
    expect(r.needsPurchase).toBe(true);
    expect(r.serviceOrderId).toBe('os-m');
  });

  it('parcial 1 de 2 no texto livre: falta 1, continua sem cadastro (o caso B8 do SQL)', () => {
    const linhas = DO_DONO.map((l) => (l.origem === 'texto_livre'
      ? { ...l, situacao: 'falta', quantidade_na_mao: 1 } : l));
    const r = aplicarSituacaoDoMaterial(bruto(), linhas);
    expect(item(r, M.conector)).toMatchObject({ status: 'uncatalogued', available: 1, shortage: 1, informado: 'parcial' });
    expect(r.shortageCount).toBe(2);
    expect(r.estimatedCost).toBe(245);
  });

  it('a quantidade da OS que passou do que o dono disse continua faltando (na mão 1 de 2; comprou 1 de 2)', () => {
    const b = computePurchaseNeeds(input({
      parts: [{ id: 'a', product_id: 'p1', quantity: 2, unit_cost_snapshot: 10, product_name: 'X' }],
    }));
    const naMao = aplicarSituacaoDoMaterial(b, [linha({ service_order_part_id: 'a', situacao: 'na_mao', quantidade_na_mao: 1 })]);
    expect(naMao.items[0]).toMatchObject({ available: 1, shortage: 1, status: 'partial', informado: 'na_mao' });
    const comprou = aplicarSituacaoDoMaterial(b, [linha({ service_order_part_id: 'a', situacao: 'comprado', quantidade_necessaria: 1 })]);
    expect(comprou.items[0]).toMatchObject({ onOrder: 1, shortage: 1, status: 'missing', informado: 'comprado' });
  });

  it('item a caminho por OC de texto livre: na mão → ok, nunca pede compra', () => {
    const b = comItensACaminho(computePurchaseNeeds(input()), [{
      purchase_order_item_id: 'poi-1', po_number: 'OC-00004', description: 'Compressor', quantity: 1, pendente: 1, unit_cost: 0,
    }]);
    const r = aplicarSituacaoDoMaterial(b, [linha({ purchase_order_item_id: 'poi-1', origem: 'oc', situacao: 'na_mao', quantidade_na_mao: 1 })]);
    expect(r.items[0]).toMatchObject({ status: 'ok', available: 1, onOrder: 0, shortage: 0, informado: 'na_mao' });
    expect(r.shortageCount).toBe(0);
    // Dispensado sai até da lista "a caminho".
    expect(aplicarSituacaoDoMaterial(b, [linha({ purchase_order_item_id: 'poi-1', origem: 'oc', situacao: 'dispensado' })]).items).toEqual([]);
  });

  it('shortages em ordem determinística: rank, falta desc, posição original (o caso B9 do SQL)', () => {
    const it_ = (sourceId: string, origin: 'part' | 'free_text', required: number, status: 'missing' | 'uncatalogued', unitCost: number) => ({
      sourceId, origin, productId: origin === 'part' ? `p-${sourceId}` : null, description: sourceId, unit: null,
      required, available: 0, onOrder: 0, shortage: required, status, unitCost,
    });
    const puro: PurchaseNeeds = {
      serviceOrderId: 'os-t',
      items: [it_('x1', 'part', 1, 'missing', 10), it_('x2', 'part', 1, 'missing', 10), it_('x3', 'part', 2, 'missing', 5),
        it_('x4', 'free_text', 3, 'uncatalogued', 1), it_('x5', 'part', 4, 'missing', 2)],
      shortages: [], shortageCount: 5, estimatedCost: 0, needsPurchase: true,
    };
    const r = aplicarSituacaoDoMaterial(puro, [linha({ service_order_part_id: 'x5', quantidade_necessaria: 4, quantidade_na_mao: 1 })]);
    expect(r.shortages.map((s) => s.sourceId)).toEqual(['x3', 'x1', 'x2', 'x5', 'x4']);
    expect(r.estimatedCost).toBe(39);
    expect(r.shortageCount).toBe(5);
    // Mesma entrada, mesma saída.
    expect(aplicarSituacaoDoMaterial(puro, [linha({ service_order_part_id: 'x5', quantidade_necessaria: 4, quantidade_na_mao: 1 })])).toEqual(r);
  });
});
