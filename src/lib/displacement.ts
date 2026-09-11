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
 * Hora de deslocamento para N técnicos.
 *
 * A tabela configurada vai até 3. Acima disso, EXTRAPOLA pelo passo que a própria
 * configuração descreve: com 90/170/250 o passo é 80 e o 4º técnico entra por 330. É
 * derivado dos números do dono, não escolhido aqui — mas é regra de preço, em produção
 * desde 12/08/2026 como política PROVISÓRIA, e quanto cobrar por técnico adicional
 * continua decisão comercial pendente dele. O que não pode acontecer é 4 pessoas na
 * estrada custarem como 1, que era o efeito de cair em `hourly[1]` quando a faixa não
 * existia. O teto vem das chaves da tabela, não de um 3 fixo, para ela poder crescer
 * sem mexer aqui.
 */
export function hourlyRateFor(rates: TravelRates, technicianCount: number): number {
  const faixas = Object.keys(rates.hourly)
    .map(Number)
    .filter((k) => Number.isFinite(k) && k > 0 && Number.isFinite(rates.hourly[k]))
    .sort((a, b) => a - b);
  if (faixas.length === 0) return DEFAULT_TRAVEL_RATES.hourly[1];

  // Zero ou negativo não existe em campo: alguém sempre vai.
  const n = Math.max(1, Math.trunc(Number(technicianCount) || 1));
  const teto = faixas[faixas.length - 1];
  if (n <= teto) {
    // `??`, não `||`: faixa configurada em 0 é 0, não motivo para trocar de faixa.
    // Buraco na tabela (só 1 e 3 configurados): sobe para a faixa seguinte, nunca desce.
    return rates.hourly[n] ?? rates.hourly[faixas.find((k) => k > n) ?? teto];
  }

  // Uma faixa só não descreve passo nenhum: fica no teto.
  const penultima = faixas.length >= 2 ? faixas[faixas.length - 2] : null;
  const passo = penultima === null
    ? 0
    : (rates.hourly[teto] - rates.hourly[penultima]) / (teto - penultima);
  return rates.hourly[teto] + Math.max(0, passo) * (n - teto);
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
  technicianCount: number,
  rates?: TravelRates
): Promise<{ distance_km: number; cost_per_km: number; total_cost: number }> {
  // A base geográfica só existe em app_settings. As tarifas também ficam lá, mas quem já tem
  // o objeto de tarifas na mão (o formulário da OS) passa o MESMO objeto: a OS grava o
  // `cost_per_km` devolvido aqui, e duas leituras da tabela (cache do app × consulta direta)
  // podem divergir — o km gravado tem de ser o que fechou a conta.
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

  const effectiveRates = rates ?? travelRatesFromSettings(mapa);

  const oneWay = haversine(baseLat, baseLng, marinaLat, marinaLng);
  const distance_km = Math.round(oneWay * 2 * 10) / 10;

  const total_cost = calculateTravelCost({
    distance_km,
    travel_hours: 0,
    technician_count: technicianCount,
    ferry_cost: 0,
    travel_type: 'comercial',
  }, effectiveRates);

  // Nunca um literal aqui: a OS guarda este km para sempre, e ele tem de ser o da conta.
  return { distance_km, cost_per_km: effectiveRates.km_rate, total_cost };
}
