import { describe, it, expect } from 'vitest';
import {
  MAX_AGRUPAR,
  MIN_AGRUPAR,
  diferencasEntreOrcamentos,
  ehRecusaDeAgrupamento,
  mesmoClienteEEmbarcacao,
  motivoForaDoAgrupamento,
  principalPadrao,
  somaDosTotais,
  type CandidatoAgrupar,
} from './agrupar-orcamentos';

function orc(over: Partial<CandidatoAgrupar> = {}): CandidatoAgrupar {
  return {
    id: 'a', service_order_number: 'ORÇ-00001', status: 'draft', quote_status: 'draft', grand_total: 100,
    created_at: '2026-10-01T12:00:00+00:00', client_id: 'cli-1', vessel_id: 'ves-1', signed_at: null,
    converted_to_os_at: null, merged_into_id: null, discount_amount: 0, tax_amount: 0, commission_rate: 0,
    commissioned_user_id: null, commissioned_person: null, payment_condition_preset_id: null,
    payment_conditions: null, travel_cost_total: 0, problem_description: null,
    ...over,
  };
}

describe('limites', () => {
  it('2 a 10 orçamentos, como o banco', () => {
    expect(MIN_AGRUPAR).toBe(2);
    expect(MAX_AGRUPAR).toBe(10);
  });
});

describe('motivoForaDoAgrupamento', () => {
  it('orçamento em aberto pode', () => {
    expect(motivoForaDoAgrupamento(orc())).toBeNull();
    expect(motivoForaDoAgrupamento(orc({ quote_status: 'sent' }))).toBeNull();
    expect(motivoForaDoAgrupamento(orc({ quote_status: null }))).toBeNull();
  });
  it('Reprovado', () => {
    expect(motivoForaDoAgrupamento(orc({ quote_status: 'rejected' }))).toBe('Reprovado');
  });
  it('Assinado pelo cliente', () => {
    expect(motivoForaDoAgrupamento(orc({ signed_at: '2026-10-02T10:00:00+00:00' }))).toBe('Assinado pelo cliente');
  });
  it('Já virou OS (pela data de conversão ou pela situação)', () => {
    expect(motivoForaDoAgrupamento(orc({ converted_to_os_at: '2026-10-03T10:00:00+00:00', status: 'open' }))).toBe('Já virou OS');
    expect(motivoForaDoAgrupamento(orc({ status: 'in_progress' }))).toBe('Já virou OS');
  });
  it('Já agrupado vence o "cancelado" que o agrupamento deixa na origem', () => {
    expect(motivoForaDoAgrupamento(orc({ merged_into_id: 'novo', status: 'cancelled' }))).toBe('Já agrupado');
  });
  it('cancelado à mão', () => {
    expect(motivoForaDoAgrupamento(orc({ status: 'cancelled' }))).toBe('Cancelado');
  });
});

describe('somaDosTotais', () => {
  it('soma em centavos', () => {
    expect(somaDosTotais([{ grand_total: 0.1 }, { grand_total: 0.2 }])).toBe(0.3);
    expect(somaDosTotais([{ grand_total: 1234.56 }, { grand_total: 0.01 }, { grand_total: null }])).toBe(1234.57);
    expect(somaDosTotais([])).toBe(0);
  });
});

describe('mesmoClienteEEmbarcacao', () => {
  it('mesmo cliente e mesma embarcação', () => {
    expect(mesmoClienteEEmbarcacao([orc(), orc({ id: 'b' })])).toBe(true);
    expect(mesmoClienteEEmbarcacao([])).toBe(true);
  });
  it('outro cliente ou outra embarcação não', () => {
    expect(mesmoClienteEEmbarcacao([orc(), orc({ client_id: 'cli-2' })])).toBe(false);
    expect(mesmoClienteEEmbarcacao([orc(), orc({ vessel_id: 'ves-2' })])).toBe(false);
  });
});

describe('diferencasEntreOrcamentos', () => {
  const a = orc({ id: 'a', service_order_number: 'ORÇ-00001', created_at: '2026-10-01T12:00:00+00:00' });
  const b = orc({ id: 'b', service_order_number: 'ORÇ-00002', created_at: '2026-10-02T12:00:00+00:00' });

  it('iguais: nada a avisar', () => {
    expect(diferencasEntreOrcamentos([a, b])).toEqual([]);
    expect(diferencasEntreOrcamentos([a])).toEqual([]);
  });

  it('comissões diferentes, com o que cada um tem', () => {
    const [aviso] = diferencasEntreOrcamentos([{ ...b, commission_rate: 5, commissioned_person: 'Felipe' }, a]);
    expect(aviso).toMatch(/^Comissões diferentes: ORÇ-00001 sem comissão; ORÇ-00002 5% \(Felipe\)\./);
    expect(aviso).toMatch(/Vale a do principal, recalculada sobre o total novo\./);
  });

  it('condições de pagamento diferentes', () => {
    const avisos = diferencasEntreOrcamentos([a, { ...b, payment_conditions: '50% na aprovação' }]);
    expect(avisos).toEqual(['Condições de pagamento diferentes entre os orçamentos. Vale a do principal.']);
    // espaço e maiúscula não contam como diferença
    expect(
      diferencasEntreOrcamentos([
        { ...a, payment_conditions: '50% na aprovação' },
        { ...b, payment_conditions: ' 50%  NA aprovação ' },
      ]),
    ).toEqual([]);
  });

  it('desconto e imposto no cabeçalho passam a valer sobre o todo', () => {
    const avisos = diferencasEntreOrcamentos([{ ...a, discount_amount: 50 }, { ...b, discount_amount: 25.5, tax_amount: 10 }]);
    expect(avisos[0]).toMatch(/^Desconto no cabeçalho em ORÇ-00001, ORÇ-00002: no agrupado vira um desconto só de R\$\s75,50/);
    expect(avisos[1]).toMatch(/^Imposto no cabeçalho em ORÇ-00002: no agrupado vira um valor só de R\$\s10,00/);
  });

  it('mais de um com deslocamento', () => {
    expect(diferencasEntreOrcamentos([{ ...a, travel_cost_total: 300 }, b])).toEqual([]);
    const [aviso] = diferencasEntreOrcamentos([{ ...a, travel_cost_total: 300 }, { ...b, travel_cost_total: 120 }]);
    expect(aviso).toMatch(/^Mais de um orçamento tem deslocamento \(ORÇ-00001, ORÇ-00002\)/);
  });
});

describe('principalPadrao', () => {
  it('o mais antigo; empate pelo id, como o banco', () => {
    expect(
      principalPadrao([
        orc({ id: 'c', created_at: '2026-10-03T12:00:00+00:00' }),
        orc({ id: 'b', created_at: '2026-10-01T12:00:00+00:00' }),
        orc({ id: 'a', created_at: '2026-10-01T12:00:00+00:00' }),
      ]),
    ).toBe('a');
    expect(principalPadrao([])).toBe('');
  });
});

describe('ehRecusaDeAgrupamento', () => {
  it('reconhece as frases das guardas do banco (origem agrupada, agrupado desfeito)', () => {
    expect(ehRecusaDeAgrupamento({
      code: '42501',
      message: 'Este orçamento foi agrupado em ORÇ-00091 e não pode mais mudar de situação, link, cliente ou embarcação. Para mexer nele, desagrupe ORÇ-00091.',
    })).toBe(true);
    expect(ehRecusaDeAgrupamento(new Error(
      'Este orçamento foi desagrupado (os originais ORÇ-00089, ORÇ-00090 voltaram a valer) e fica como histórico: não pode ser reaberto.',
    ))).toBe(true);
  });

  it('42501 de outra origem (permissão) não conta; nulo não quebra', () => {
    expect(ehRecusaDeAgrupamento({ code: '42501', message: 'new row violates row-level security policy' })).toBe(false);
    expect(ehRecusaDeAgrupamento(null)).toBe(false);
    expect(ehRecusaDeAgrupamento(undefined)).toBe(false);
  });
});
