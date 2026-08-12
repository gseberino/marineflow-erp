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
// O que ela tem de errado hoje está registrado como NOVO-024.
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { calculateTravelCost, travelRatesFromSettings, hourlyRateFor, DEFAULT_TRAVEL_RATES } from './displacement';

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

  // [NOVO-016a] CORRIGIDO. A tabela vai até 3 técnicos; o código fazia
  // `rates.hourly[4] || rates.hourly[1]` e caía na tarifa de UM. Quatro pessoas na estrada
  // custavam menos que três, e o número de técnicos é campo livre na tela.
  it('[NOVO-016] 4 técnicos custam MAIS que 3, extrapolando o passo da configuração', () => {
    const params = { distance_km: 0, travel_hours: 1, ferry_cost: 0, travel_type: 'comercial' as const };
    const um = calculateTravelCost({ ...params, technician_count: 1 });
    const tres = calculateTravelCost({ ...params, technician_count: 3 });
    const quatro = calculateTravelCost({ ...params, technician_count: 4 });

    expect(um).toBe(90);
    expect(tres).toBe(250);
    // 90/170/250 descreve um passo de 80 — o 4º técnico entra por 330, derivado dos números
    // configurados, não escolhido à mão.
    expect(quatro).toBe(330);
    expect(quatro).toBeGreaterThan(tres);
  });

  it('[NOVO-016] a extrapolação segue crescendo, sem degrau nem teto', () => {
    const params = { distance_km: 0, travel_hours: 1, ferry_cost: 0, travel_type: 'comercial' as const };
    const custos = [1, 2, 3, 4, 5, 6].map((n) =>
      calculateTravelCost({ ...params, technician_count: n }));
    for (let i = 1; i < custos.length; i++) {
      expect(custos[i], `${i + 1} técnicos não pode custar menos que ${i}`)
        .toBeGreaterThan(custos[i - 1]);
    }
    expect(custos).toEqual([90, 170, 250, 330, 410, 490]);
  });

  it('[NOVO-016] o passo vem da configuração da empresa, não de constante no código', () => {
    // Faixas dobradas: o 4º técnico tem de dobrar junto.
    const rates = travelRatesFromSettings({
      travel_hourly_1: '180', travel_hourly_2: '340', travel_hourly_3: '500',
    });
    const params = { distance_km: 0, travel_hours: 1, ferry_cost: 0, travel_type: 'comercial' as const };
    expect(calculateTravelCost({ ...params, technician_count: 3 }, rates)).toBe(500);
    expect(calculateTravelCost({ ...params, technician_count: 4 }, rates)).toBe(660);
  });

  it('[NOVO-016] contagem zerada ou negativa vira 1 técnico — alguém sempre vai', () => {
    const params = { distance_km: 0, travel_hours: 1, ferry_cost: 0, travel_type: 'comercial' as const };
    expect(calculateTravelCost({ ...params, technician_count: 0 })).toBe(90);
    expect(calculateTravelCost({ ...params, technician_count: -2 })).toBe(90);
  });

  it('[NOVO-016] hourlyRateFor sozinha: faixa exata, extrapolação e borda', () => {
    expect(hourlyRateFor(DEFAULT_TRAVEL_RATES, 2)).toBe(170);
    expect(hourlyRateFor(DEFAULT_TRAVEL_RATES, 4)).toBe(330);
    expect(hourlyRateFor(DEFAULT_TRAVEL_RATES, 1.7)).toBe(90);  // trunca
    // Uma faixa só: sem passo a derivar, N técnicos custam N vezes — o mais conservador.
    const umaFaixa = { ...DEFAULT_TRAVEL_RATES, hourly: { 1: 100 } };
    expect(hourlyRateFor(umaFaixa, 3)).toBe(300);
  });
});

describe('[NOVO-016b] calculateDisplacement usa a tarifa configurada, não a do código', () => {
  // Esta função consulta `app_settings`. O mock devolve o que a EMPRESA configurou; se o
  // cálculo ignorar isso e usar DEFAULT_TRAVEL_RATES, os números abaixo não fecham.
  //
  // O defeito era duplo: a consulta só pedia lat/lng, e o cálculo era chamado sem o segundo
  // argumento. Quem tivesse ajustado o km para R$ 1,80 continuava orçando a R$ 1,10, e a tela
  // gravava essa tarifa fantasma em `travel_cost_per_km` na OS.
  const configurado = [
    { key: 'travel_base_lat', value: '-26.9078' },
    { key: 'travel_base_lng', value: '-48.6728' },
    { key: 'travel_km_rate', value: '2.00' },
    { key: 'travel_hourly_1', value: '180' },
    { key: 'travel_hourly_2', value: '340' },
    { key: 'travel_hourly_3', value: '500' },
  ];

  beforeEach(() => {
    vi.resetModules();
    vi.doMock('@/integrations/supabase/client', () => ({
      supabase: {
        from: () => ({ select: () => ({ in: () => Promise.resolve({ data: configurado }) }) }),
      },
    }));
  });

  afterEach(() => vi.doUnmock('@/integrations/supabase/client'));

  it('devolve o km da configuração, não o 1.10 que estava fixo no return', async () => {
    const { calculateDisplacement } = await import('./displacement');
    // Mesma coordenada da base: distância zero isola a tarifa do resto do cálculo.
    const r = await calculateDisplacement(-26.9078, -48.6728, 1);
    expect(r.cost_per_km).toBe(2);
    expect(r.distance_km).toBe(0);
  });

  it('o total usa a tarifa por km configurada', async () => {
    const { calculateDisplacement } = await import('./displacement');
    const r = await calculateDisplacement(-27.0, -48.6728, 1);
    // travel_hours é 0 aqui, então o total é só distância × km configurado (R$ 2,00).
    expect(r.total_cost).toBeCloseTo(r.distance_km * 2, 2);
    // Com o defeito, seria distance × 1.10 — a asserção abaixo é a que pega a regressão.
    expect(r.total_cost).not.toBeCloseTo(r.distance_km * 1.1, 2);
  });
});
