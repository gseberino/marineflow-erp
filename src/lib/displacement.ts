import { supabase } from '@/integrations/supabase/client';

function toRad(deg: number) {
  return (deg * Math.PI) / 180;
}

function haversine(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

export interface TravelRates {
  km_rate: number;
  hourly: Record<number, number>; // por número de técnicos
  urgency_mult: number;
  weekend_mult: number;
}

export const DEFAULT_TRAVEL_RATES: TravelRates = {
  km_rate: 1.10,
  hourly: { 1: 90.00, 2: 170.00, 3: 250.00 },
  urgency_mult: 1.5,
  weekend_mult: 1.3,
};

/** Constrói TravelRates a partir do mapa de app_settings (com fallback para defaults). */
export function travelRatesFromSettings(s?: Record<string, string>): TravelRates {
  if (!s) return DEFAULT_TRAVEL_RATES;
  const num = (k: string, d: number) => {
    const v = Number(s[k]);
    return Number.isFinite(v) && v > 0 ? v : d;
  };
  return {
    km_rate: num('travel_km_rate', DEFAULT_TRAVEL_RATES.km_rate),
    hourly: {
      1: num('travel_hourly_1', DEFAULT_TRAVEL_RATES.hourly[1]),
      2: num('travel_hourly_2', DEFAULT_TRAVEL_RATES.hourly[2]),
      3: num('travel_hourly_3', DEFAULT_TRAVEL_RATES.hourly[3]),
    },
    urgency_mult: num('travel_urgency_mult', DEFAULT_TRAVEL_RATES.urgency_mult),
    weekend_mult: num('travel_weekend_mult', DEFAULT_TRAVEL_RATES.weekend_mult),
  };
}

/**
 * Hora de deslocamento para N técnicos. [NOVO-016a]
 *
 * A tabela configurada tem três faixas (1, 2 e 3 técnicos). O código anterior fazia
 * `rates.hourly[technician_count] || rates.hourly[1]`: com 4 técnicos a busca dava
 * `undefined` e caía no valor de UM — quatro pessoas na estrada custando como uma, e o
 * orçamento saía barato sem ninguém perceber que faltava dinheiro ali.
 *
 * Acima da última faixa, EXTRAPOLA pelo passo que a própria configuração descreve, em vez de
 * inventar um preço: com 90/170/250, o passo é 80 e o 4º técnico entra por 330. Se a empresa
 * mudar as faixas, o passo muda junto. É derivado dos números do dono, não escolhido por mim
 * — mas é uma regra de preço, e está registrada no livro para confirmação.
 */
export function hourlyRateFor(rates: TravelRates, technicianCount: number): number {
  // Zero ou negativo não existe em campo: alguém sempre vai. Trata como um técnico.
  const n = Math.max(1, Math.trunc(Number(technicianCount) || 1));

  const direto = rates.hourly[n];
  if (Number.isFinite(direto) && direto > 0) return direto;

  const faixas = Object.keys(rates.hourly)
    .map(Number)
    .filter((k) => Number.isFinite(k) && k > 0 && Number.isFinite(rates.hourly[k]))
    .sort((a, b) => a - b);
  if (faixas.length === 0) return DEFAULT_TRAVEL_RATES.hourly[1];

  const maior = faixas[faixas.length - 1];
  // Abaixo da menor faixa configurada (buraco no meio da tabela): usa a menor.
  if (n < maior) {
    const acima = faixas.find((k) => k > n);
    return rates.hourly[acima ?? maior];
  }

  // Passo entre as duas últimas faixas. Com uma faixa só, não há passo a derivar: o valor
  // por técnico é o próprio, e N técnicos custam N vezes — que é o mais conservador.
  const passo = faixas.length >= 2
    ? rates.hourly[maior] - rates.hourly[faixas[faixas.length - 2]]
    : rates.hourly[maior];
  return rates.hourly[maior] + (n - maior) * passo;
}

export function calculateTravelCost(params: {
  distance_km: number;
  travel_hours: number;
  technician_count: number;
  ferry_cost: number;
  travel_type: 'comercial' | 'urgencia' | 'fds_feriado';
}, rates: TravelRates = DEFAULT_TRAVEL_RATES): number {
  const { distance_km, travel_hours, technician_count, ferry_cost, travel_type } = params;
  const hourlyRate = hourlyRateFor(rates, technician_count);
  const multiplier =
    travel_type === 'urgencia' ? rates.urgency_mult
    : travel_type === 'fds_feriado' ? rates.weekend_mult
    : 1.0;
  const base = (distance_km * rates.km_rate) + (travel_hours * hourlyRate) + (ferry_cost || 0);
  return Math.round(base * multiplier * 100) / 100;
}

export async function calculateDisplacement(
  marinaLat: number,
  marinaLng: number,
  technicianCount: number
): Promise<{ distance_km: number; cost_per_km: number; total_cost: number }> {
  // [NOVO-016b] Lê TAMBÉM as tarifas, não só a base geográfica.
  //
  // Antes, esta consulta trazia apenas lat/lng e o cálculo era chamado sem o segundo
  // argumento — ou seja, com DEFAULT_TRAVEL_RATES. O botão "calcular deslocamento" da OS
  // ignorava, em silêncio, a tarifa que a empresa configurou em Settings: quem tivesse
  // ajustado o km para R$ 1,80 continuava orçando a R$ 1,10, e a tela não dava nenhum sinal
  // de estar usando outro número.
  const { data: settings } = await supabase
    .from('app_settings')
    .select('key, value')
    .in('key', [
      'travel_base_lat', 'travel_base_lng',
      'travel_km_rate', 'travel_hourly_1', 'travel_hourly_2', 'travel_hourly_3',
      'travel_urgency_mult', 'travel_weekend_mult',
    ]);

  const mapa: Record<string, string> = {};
  for (const s of settings ?? []) mapa[s.key] = s.value;

  const get = (key: string) => mapa[key];
  const baseLat = parseFloat(get('travel_base_lat') || '-26.9078');
  const baseLng = parseFloat(get('travel_base_lng') || '-48.6728');

  const rates = travelRatesFromSettings(mapa);

  const oneWay = haversine(baseLat, baseLng, marinaLat, marinaLng);
  const distance_km = Math.round(oneWay * 2 * 10) / 10;

  const total_cost = calculateTravelCost({
    distance_km,
    travel_hours: 0,
    technician_count: technicianCount,
    ferry_cost: 0,
    travel_type: 'comercial',
  }, rates);

  // O km devolvido é o CONFIGURADO. Era 1.10 fixo — a tela gravava esse número em
  // `travel_cost_per_km` na OS, então o orçamento guardava para sempre uma tarifa que a
  // empresa talvez nunca tenha usado.
  return { distance_km, cost_per_km: rates.km_rate, total_cost };
}
