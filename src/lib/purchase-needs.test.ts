import { describe, expect, it } from 'vitest';
import {
  comItensACaminho, computePurchaseNeeds, descontarReservaDaPropriaOs, isPurchasableFreeText,
  osReservaEstoque, STATUS_QUE_RESERVAM,
  type ComputeInput, type FreeTextInput, type PartInput,
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
