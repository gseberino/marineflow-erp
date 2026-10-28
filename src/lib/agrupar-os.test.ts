import { describe, it, expect } from 'vitest';
import {
  MAX_AGRUPAR,
  MIN_AGRUPAR,
  STATUS_AGRUPAVEIS_OS,
  avisosDaOsNova,
  desagrupavelPeloBanco,
  diferencasEntreOs,
  leituraDoBanco,
  motivoForaDoAgrupamentoOs,
  origemAgrupadaDeOs,
  osAgrupadaDesagrupavel,
  resumoDosRecebiveis,
  rotuloDoRecebivel,
  type CandidataOs,
  type RecebivelDaPrevia,
} from './agrupar-os';
import { diferencasEntreOrcamentos, ehRecusaDeAgrupamento } from './agrupar-orcamentos';

function os(over: Partial<CandidataOs> = {}): CandidataOs {
  return {
    id: 'a', service_order_number: 'OS-00100', status: 'open', quote_status: 'approved', grand_total: 100,
    created_at: '2026-10-01T12:00:00+00:00', client_id: 'cli-1', vessel_id: 'ves-1', signed_at: null,
    converted_to_os_at: '2026-10-01T13:00:00+00:00', merged_into_id: null, discount_amount: 0, tax_amount: 0,
    commission_rate: 0, commissioned_user_id: null, commissioned_person: null, payment_condition_preset_id: null,
    payment_conditions: null, travel_cost_total: 0, problem_description: null, scheduled_start_at: null,
    card_fee_passthrough_enabled: false, operational_cost_total: 0,
    ...over,
  };
}

function rec(over: Partial<RecebivelDaPrevia> = {}): RecebivelDaPrevia {
  return {
    id: 'r', service_order_id: 'a', description: 'Sinal', amount: 100, paid_amount: 0, status: 'pending',
    is_deposit: false, due_date: '2026-11-01', ...over,
  };
}

describe('limites e situações', () => {
  it('2 a 10 OS, como orçamento', () => {
    expect(MIN_AGRUPAR).toBe(2);
    expect(MAX_AGRUPAR).toBe(10);
  });
  it('só as situações de OS que ainda não começou (seção 9)', () => {
    expect([...STATUS_AGRUPAVEIS_OS].sort()).toEqual(['approved', 'awaiting_client', 'awaiting_parts', 'open', 'scheduled']);
  });
});

describe('motivoForaDoAgrupamentoOs', () => {
  it('OS que ainda não começou pode', () => {
    for (const status of STATUS_AGRUPAVEIS_OS) expect(motivoForaDoAgrupamentoOs(os({ status }))).toBeNull();
  });
  it('assinada pode (a assinatura fica na original)', () => {
    expect(motivoForaDoAgrupamentoOs(os({ signed_at: '2026-10-02T10:00:00+00:00' }))).toBeNull();
  });
  it('já executada fica de fora, com a situação dita', () => {
    expect(motivoForaDoAgrupamentoOs(os({ status: 'in_progress' }))).toBe('Em execução');
    expect(motivoForaDoAgrupamentoOs(os({ status: 'completed' }))).toBe('Concluída');
    expect(motivoForaDoAgrupamentoOs(os({ status: 'invoiced' }))).toBe('Faturada');
  });
  it('Já agrupada vence o "cancelada" que o agrupamento deixa na origem', () => {
    expect(motivoForaDoAgrupamentoOs(os({ merged_into_id: 'nova', status: 'cancelled' }))).toBe('Já agrupada');
    expect(motivoForaDoAgrupamentoOs(os({ status: 'cancelled' }))).toBe('Cancelada');
  });
  it('orçamento não entra aqui (tem o agrupar dele)', () => {
    expect(motivoForaDoAgrupamentoOs(os({ converted_to_os_at: null, status: 'draft' }))).toBe('Ainda é orçamento');
  });
  it('OS antiga sem converted_to_os_at entra, como no banco (fora de rascunho é OS)', () => {
    expect(motivoForaDoAgrupamentoOs(os({ converted_to_os_at: null, status: 'open' }))).toBeNull();
  });
  it('despesa lançada e repasse da taxa do cartão', () => {
    expect(motivoForaDoAgrupamentoOs(os({ operational_cost_total: 35.5 }))).toBe('Já tem despesa');
    expect(motivoForaDoAgrupamentoOs(os({ operational_cost_total: 0.001 }))).toBeNull();
    expect(motivoForaDoAgrupamentoOs(os({ card_fee_passthrough_enabled: true }))).toBe('Repassa a taxa do cartão');
  });
});

describe('origemAgrupadaDeOs', () => {
  it('OS: tem converted_to_os_at ou, antiga sem ele, o motivo "Agrupada em" do agrupar_os', () => {
    expect(origemAgrupadaDeOs({ converted_to_os_at: '2026-10-01T13:00:00Z', cancellation_reason: 'Agrupada em OS-00131 (reúne …)' })).toBe(true);
    expect(origemAgrupadaDeOs({ converted_to_os_at: null, cancellation_reason: 'Agrupada em OS-00131 (reúne OS-00032, OS-00033)' })).toBe(true);
  });
  it('orçamento: sem converted_to_os_at e com o motivo "Agrupado em"', () => {
    expect(origemAgrupadaDeOs({ converted_to_os_at: null, cancellation_reason: 'Agrupado em ORÇ-00125 (reúne ORÇ-00100, ORÇ-00101)' })).toBe(false);
    expect(origemAgrupadaDeOs({ converted_to_os_at: null })).toBe(false);
    expect(origemAgrupadaDeOs(null)).toBe(false);
  });
});

describe('osAgrupadaDesagrupavel', () => {
  it('enquanto a agrupada não começou e o cliente não a assinou', () => {
    expect(osAgrupadaDesagrupavel({ status: 'approved' })).toBe(true);
    expect(osAgrupadaDesagrupavel({ status: 'scheduled', signed_at: null })).toBe(true);
    expect(osAgrupadaDesagrupavel({ status: 'in_progress' })).toBe(false);
    expect(osAgrupadaDesagrupavel({ status: 'completed' })).toBe(false);
    expect(osAgrupadaDesagrupavel({ status: 'cancelled' })).toBe(false);
    expect(osAgrupadaDesagrupavel({ status: 'approved', signed_at: '2026-10-28T10:00:00Z' })).toBe(false);
    expect(osAgrupadaDesagrupavel(null)).toBe(false);
  });
});

describe('desagrupavelPeloBanco (os_para_agrupar → agrupados_ativos)', () => {
  const leitura = {
    agrupados_ativos: [
      { id: 'g1', numero: 'OS-00131', pode_desagrupar: false, motivo: 'OS-00131 já começou a ser executada (hora apontada): não dá mais para desagrupar. As originais ficam como histórico.' },
      { id: 'g2', numero: 'OS-00132', pode_desagrupar: true, motivo: null },
    ],
  };
  it('a régua é a do banco: agrupada aberta com hora apontada não desagrupa, e diz por quê', () => {
    expect(desagrupavelPeloBanco(leitura, 'g1')).toEqual({ podeDesagrupar: false, motivo: expect.stringMatching(/hora apontada/) });
    expect(desagrupavelPeloBanco(leitura, 'g2')).toEqual({ podeDesagrupar: true, motivo: null });
  });
  it('sem a agrupada na lista ou com forma errada: null (a tela usa o palpite pela situação)', () => {
    expect(desagrupavelPeloBanco(leitura, 'outra')).toBeNull();
    expect(desagrupavelPeloBanco(null, 'g1')).toBeNull();
    expect(desagrupavelPeloBanco({ agrupados_ativos: 'x' }, 'g1')).toBeNull();
    expect(desagrupavelPeloBanco({ agrupados_ativos: [{ id: 'g1', pode_desagrupar: 'sim' }] }, 'g1')).toBeNull();
  });
});

describe('leituraDoBanco (os_para_agrupar)', () => {
  it('lê id, elegível e a frase do banco; ignora o que não tem forma', () => {
    const m = leituraDoBanco({
      os: [
        { id: 'a', elegivel: true, motivo: null },
        { id: 'b', elegivel: false, motivo: 'OS-00033 tem comissão lançada. Uma OS com nota, fatura ou comissão não entra num agrupamento.' },
        { id: 'c', elegivel: false, motivo: '  ' },
        { numero: 'sem id', elegivel: true },
        { id: 'd' },
      ],
    });
    expect([...m.keys()]).toEqual(['a', 'b', 'c']);
    expect(m.get('a')).toEqual({ elegivel: true, motivo: null });
    expect(m.get('b')?.motivo).toMatch(/^OS-00033 tem comissão lançada/);
    expect(m.get('c')).toEqual({ elegivel: false, motivo: null });
  });
  it('resposta estranha vira mapa vazio', () => {
    expect(leituraDoBanco(null).size).toBe(0);
    expect(leituraDoBanco({ os: 'x' }).size).toBe(0);
    expect(leituraDoBanco([]).size).toBe(0);
  });
});

describe('diferencasEntreOs', () => {
  it('nada a avisar com OS iguais', () => {
    expect(diferencasEntreOs([os({ id: 'a' }), os({ id: 'b', service_order_number: 'OS-00128' })])).toEqual([]);
  });
  it('as frases falam de OS, no feminino', () => {
    const avisos = diferencasEntreOs([
      os({ id: 'a', discount_amount: 10, travel_cost_total: 80, payment_conditions: 'À vista' }),
      os({ id: 'b', service_order_number: 'OS-00128', created_at: '2026-10-02T12:00:00+00:00', travel_cost_total: 50, tax_amount: 5 }),
    ]);
    expect(avisos).toContain('Condições de pagamento diferentes entre as OS. Vale a do principal.');
    expect(avisos.find((a) => a.startsWith('Desconto'))).toMatch(
      /^Desconto no cabeçalho em OS-00100: na agrupada vira um desconto só de R\$\s10,00, sobre a OS inteira \(não mais sobre os itens de cada uma\)\.$/,
    );
    expect(avisos.find((a) => a.startsWith('Imposto'))).toMatch(/na agrupada vira um valor só de R\$\s5,00, sobre a OS inteira\.$/);
    expect(avisos).toContain(
      'Mais de uma OS tem deslocamento (OS-00100, OS-00128). Deixe o deslocamento em uma só antes de agrupar, para não cobrar a viagem duas vezes.',
    );
  });
  it('a generalização não mexeu nas frases de orçamento', () => {
    const a = os({ id: 'a', service_order_number: 'ORÇ-00001', discount_amount: 10, travel_cost_total: 1 });
    const b = os({ id: 'b', service_order_number: 'ORÇ-00002', created_at: '2026-10-02T12:00:00+00:00', travel_cost_total: 1, payment_conditions: 'x' });
    const avisos = diferencasEntreOrcamentos([a, b]);
    expect(avisos).toContain('Condições de pagamento diferentes entre os orçamentos. Vale a do principal.');
    expect(avisos.some((x) => /no agrupado vira um desconto só de .*, sobre o orçamento inteiro \(não mais sobre os itens de cada um\)\.$/.test(x))).toBe(true);
    expect(avisos.some((x) => x.startsWith('Mais de um orçamento tem deslocamento (ORÇ-00001, ORÇ-00002).'))).toBe(true);
  });
});

describe('avisosDaOsNova', () => {
  it('sempre lembra a regra da NFS-e', () => {
    const avisos = avisosDaOsNova([os({ id: 'a' }), os({ id: 'b' })]);
    expect(avisos).toHaveLength(1);
    expect(avisos[0]).toMatch(/^Nota fiscal: uma NFS-e cobre um tomador, um código de serviço e uma competência\./);
  });
  it('uma assinada: a assinatura fica nela', () => {
    const avisos = avisosDaOsNova([os({ id: 'a' }), os({ id: 'b', service_order_number: 'OS-00033', signed_at: '2026-10-05T10:00:00Z' })]);
    expect(avisos[0]).toBe(
      'OS-00033 foi assinada pelo cliente: a assinatura fica nela, como histórico. A OS nova nasce sem assinatura; se precisar, peça uma nova ao cliente.',
    );
  });
  it('várias assinadas: no plural', () => {
    const avisos = avisosDaOsNova([
      os({ id: 'a', service_order_number: 'OS-00032', signed_at: '2026-10-05T10:00:00Z' }),
      os({ id: 'b', service_order_number: 'OS-00033', signed_at: '2026-10-05T10:00:00Z' }),
    ]);
    expect(avisos[0]).toMatch(/^OS-00032, OS-00033 foram assinadas pelo cliente: as assinaturas ficam nas OS originais/);
  });
  it('com menos de duas não avisa nada', () => {
    expect(avisosDaOsNova([os()])).toEqual([]);
  });
  it('situações diferentes: a nova fica com a da principal', () => {
    const avisos = avisosDaOsNova([os({ id: 'a', status: 'approved' }), os({ id: 'b', status: 'scheduled' })], 'a');
    expect(avisos).toContain('As OS estão em situações diferentes: a OS nova fica com a situação da principal (OS-00100).');
    // sem principal conhecida, não arrisca dizer qual
    expect(avisosDaOsNova([os({ id: 'a', status: 'approved' }), os({ id: 'b', status: 'scheduled' })]).some((x) => x.startsWith('As OS estão'))).toBe(false);
  });
  it('atendimento marcado em outra data: confira a agenda', () => {
    const avisos = avisosDaOsNova([
      os({ id: 'a', scheduled_start_at: '2026-11-03T13:00:00Z' }),
      os({ id: 'b', service_order_number: 'OS-00128', scheduled_start_at: '2026-11-05T17:30:00Z' }),
      os({ id: 'c', service_order_number: 'OS-00129', scheduled_start_at: '2026-11-03T13:00:00Z' }),
    ], 'a');
    expect(avisos).toContain(
      'Tem atendimento marcado em outra data: OS-00128 (05/11/2026, 14:30). A OS nova fica com a data da principal (OS-00100): confira a agenda.',
    );
  });
});

describe('recebíveis que acompanham', () => {
  it('soma em centavos e ignora o cancelado', () => {
    const r = resumoDosRecebiveis([
      rec({ id: '1', amount: 2869.5, paid_amount: 2869.5, status: 'paid', is_deposit: true }),
      rec({ id: '2', amount: 1000, paid_amount: 1000, status: 'paid', is_deposit: true }),
      rec({ id: '3', amount: 2839.5, paid_amount: 0, status: 'pending' }),
      rec({ id: '4', amount: 999, status: 'cancelled' }),
      rec({ id: '5', amount: 0.1, paid_amount: 0.2, status: 'partial' }),
    ]);
    expect(r).toEqual({ quantidade: 4, total: 6709.1, recebido: 3869.6, emAberto: 2839.5 });
  });
  it('rótulo diz o tipo, o valor e a situação', () => {
    expect(rotuloDoRecebivel(rec({ amount: 1000, paid_amount: 1000, status: 'paid', is_deposit: true }))).toMatch(/^Sinal de R\$\s1\.000,00 · pago$/);
    expect(rotuloDoRecebivel(rec({ amount: 2839.5 }))).toMatch(/^Conta a receber de R\$\s2\.839,50 · em aberto$/);
    expect(rotuloDoRecebivel(rec({ amount: 500, paid_amount: 200, status: 'partial' }))).toMatch(/· R\$\s200,00 recebido$/);
    expect(rotuloDoRecebivel(rec({ amount: 500, status: 'overdue' }))).toMatch(/· vencido$/);
  });
});

describe('ehRecusaDeAgrupamento (orçamento e OS)', () => {
  it('reconhece as frases das duas guardas, nos dois gêneros', () => {
    expect(ehRecusaDeAgrupamento({ message: 'ORÇ-00001 foi agrupado em ORÇ-00100: ...' })).toBe(true);
    expect(ehRecusaDeAgrupamento({ message: 'OS-00100 foi agrupada em OS-00140: ...' })).toBe(true);
    expect(ehRecusaDeAgrupamento({ message: 'ORÇ-00100 foi desagrupado: ...' })).toBe(true);
    expect(ehRecusaDeAgrupamento({ message: 'OS-00140 foi desagrupada: ...' })).toBe(true);
    expect(ehRecusaDeAgrupamento({ message: 'permission denied' })).toBe(false);
    expect(ehRecusaDeAgrupamento(null)).toBe(false);
  });
});
