// Cobertura do cálculo de deslocamento — módulo sem teste até agora.
//
// Deslocamento é dinheiro que entra em toda OS de campo, e a conta tem três partes que se
// multiplicam: quilometragem, hora de equipe e multiplicador de urgência/fim de semana. Um
// erro aqui não aparece como erro — aparece como uma OS que fechou por menos do que custou.
//
// `calculateDisplacement` não é testada aqui: ela consulta `app_settings` no Supabase. E o que
// ela tem de próprio — a haversine e o × 2 da ida e volta — fica DESCOBERTO, o que precisa ser
// dito em voz alta: trocar o raio da Terra, inverter lat/lng ou perder o × 2 não quebra teste
// nenhum, e a distância errada vai direto para travel_distance_km e travel_cost_total da OS.
// O que ela tem de errado hoje está registrado como NOVO-016.
import { describe, it, expect } from 'vitest';
import { calculateTravelCost, travelRatesFromSettings, DEFAULT_TRAVEL_RATES } from './displacement';

describe('travelRatesFromSettings — o que a empresa configurou vale sobre o padrão', () => {
  it('sem settings, usa os padrões de fábrica', () => {
    expect(travelRatesFromSettings(undefined)).toEqual(DEFAULT_TRAVEL_RATES);
    expect(travelRatesFromSettings({})).toEqual(DEFAULT_TRAVEL_RATES);
  });

  it('lê cada tarifa da chave correspondente', () => {
    const rates = travelRatesFromSettings({
      travel_km_rate: '2.50',
      travel_hourly_1: '120',
      travel_hourly_2: '220',
      travel_hourly_3: '300',
      travel_urgency_mult: '2',
      travel_weekend_mult: '1.6',
    });
    expect(rates.km_rate).toBe(2.5);
    expect(rates.hourly[1]).toBe(120);
    expect(rates.hourly[2]).toBe(220);
    expect(rates.hourly[3]).toBe(300);
    expect(rates.urgency_mult).toBe(2);
    expect(rates.weekend_mult).toBe(1.6);
  });

  it('valor inválido ou zerado cai no padrão em vez de zerar a cobrança', () => {
    // Um `travel_km_rate: ''` gravado por engano faria toda viagem sair de graça se o código
    // aceitasse o valor. Aqui ele volta para 1,10.
    const rates = travelRatesFromSettings({
      travel_km_rate: '',
      travel_hourly_1: 'abc',
      travel_hourly_2: '0',
      travel_urgency_mult: '-3',
    });
    expect(rates.km_rate).toBe(DEFAULT_TRAVEL_RATES.km_rate);
    expect(rates.hourly[1]).toBe(DEFAULT_TRAVEL_RATES.hourly[1]);
    expect(rates.hourly[2]).toBe(DEFAULT_TRAVEL_RATES.hourly[2]);
    expect(rates.urgency_mult).toBe(DEFAULT_TRAVEL_RATES.urgency_mult);
  });

  it('aceita vírgula? não — número em pt-BR vira NaN e cai no padrão', () => {
    // Documenta o comportamento de hoje: quem gravar "2,50" na configuração recebe 1,10
    // silenciosamente. A tela usa <input type="number">, então grava ponto — mas quem
    // escrever direto no banco precisa saber.
    expect(travelRatesFromSettings({ travel_km_rate: '2,50' }).km_rate).toBe(DEFAULT_TRAVEL_RATES.km_rate);
  });
});

describe('calculateTravelCost — a conta que vai para a OS', () => {
  it('caso comercial: km × tarifa + horas × tarifa da equipe + balsa', () => {
    // 100 km × 1,10 = 110 · 2 h × 170 (2 técnicos) = 340 · balsa 50 → 500
    const custo = calculateTravelCost({
      distance_km: 100, travel_hours: 2, technician_count: 2,
      ferry_cost: 50, travel_type: 'comercial',
    });
    expect(custo).toBe(500);
  });

  it('urgência multiplica o TOTAL, inclusive a balsa', () => {
    // É uma escolha do negócio e vale registrar: o multiplicador não incide só sobre a mão
    // de obra — pega quilometragem e pedágio/balsa junto.
    const base = calculateTravelCost({
      distance_km: 100, travel_hours: 2, technician_count: 2, ferry_cost: 50, travel_type: 'comercial',
    });
    const urgente = calculateTravelCost({
      distance_km: 100, travel_hours: 2, technician_count: 2, ferry_cost: 50, travel_type: 'urgencia',
    });
    expect(urgente).toBe(Math.round(base * 1.5 * 100) / 100);
    expect(urgente).toBe(750);
  });

  it('fim de semana/feriado usa o multiplicador próprio', () => {
    const fds = calculateTravelCost({
      distance_km: 100, travel_hours: 2, technician_count: 2, ferry_cost: 50, travel_type: 'fds_feriado',
    });
    expect(fds).toBe(650); // 500 × 1,3
  });

  it('a tarifa por hora muda com o número de técnicos', () => {
    const params = { distance_km: 0, travel_hours: 1, ferry_cost: 0, travel_type: 'comercial' as const };
    expect(calculateTravelCost({ ...params, technician_count: 1 })).toBe(90);
    expect(calculateTravelCost({ ...params, technician_count: 2 })).toBe(170);
    expect(calculateTravelCost({ ...params, technician_count: 3 })).toBe(250);
  });

  it('respeita as tarifas da empresa quando são passadas', () => {
    const rates = travelRatesFromSettings({ travel_km_rate: '3.50', travel_hourly_1: '120' });
    const custo = calculateTravelCost({
      distance_km: 10, travel_hours: 1, technician_count: 1, ferry_cost: 0, travel_type: 'comercial',
    }, rates);
    expect(custo).toBe(155); // 10 × 3,50 + 120
  });

  it('viagem zerada custa zero — não inventa mínimo', () => {
    expect(calculateTravelCost({
      distance_km: 0, travel_hours: 0, technician_count: 1, ferry_cost: 0, travel_type: 'comercial',
    })).toBe(0);
  });

  it('ferry_cost ausente não contamina a soma com NaN', () => {
    const custo = calculateTravelCost({
      distance_km: 10, travel_hours: 0, technician_count: 1,
      ferry_cost: undefined as unknown as number, travel_type: 'comercial',
    });
    expect(custo).toBe(11);
    expect(Number.isFinite(custo)).toBe(true);
  });

  it('sai arredondado em centavos', () => {
    const custo = calculateTravelCost({
      distance_km: 33.3, travel_hours: 1.5, technician_count: 3, ferry_cost: 12.37, travel_type: 'urgencia',
    });
    expect(String(custo).split('.')[1]?.length ?? 0).toBeLessThanOrEqual(2);
  });

  // ⚠️ NOVO-016 — comportamento surpreendente, registrado em audit/novos-achados.md.
  // A tabela de hora vai até 3 técnicos; com 4 o código faz `rates.hourly[4] || rates.hourly[1]`
  // e cai na tarifa de UM técnico. Quatro técnicos custam menos que três — e o número de
  // técnicos é campo livre na tela.
  it('[NOVO-016] com 4 técnicos, a hora despenca para a tarifa de 1 técnico', () => {
    const params = { distance_km: 0, travel_hours: 1, ferry_cost: 0, travel_type: 'comercial' as const };
    const tres = calculateTravelCost({ ...params, technician_count: 3 });
    const quatro = calculateTravelCost({ ...params, technician_count: 4 });
    expect(tres).toBe(250);
    expect(quatro).toBe(90);          // comportamento de HOJE
    expect(quatro).toBeLessThan(tres); // ...e é justamente o que não deveria ser
  });

  it('[NOVO-016] contagem zerada ou negativa também cai na tarifa de 1 técnico', () => {
    const params = { distance_km: 0, travel_hours: 1, ferry_cost: 0, travel_type: 'comercial' as const };
    expect(calculateTravelCost({ ...params, technician_count: 0 })).toBe(90);
    expect(calculateTravelCost({ ...params, technician_count: -2 })).toBe(90);
  });
});
