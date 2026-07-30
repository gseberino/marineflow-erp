import { describe, expect, it } from 'vitest';
import {
  computePurchaseNeeds, isPurchasableFreeText,
  type ComputeInput, type FreeTextInput,
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
