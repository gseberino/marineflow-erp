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

export function calculateTravelCost(params: {
  distance_km: number;
  travel_hours: number;
  technician_count: number;
  ferry_cost: number;
  travel_type: 'comercial' | 'urgencia' | 'fds_feriado';
}, rates: TravelRates = DEFAULT_TRAVEL_RATES): number {
  const { distance_km, travel_hours, technician_count, ferry_cost, travel_type } = params;
  const hourlyRate = rates.hourly[technician_count] || rates.hourly[1];
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
  const { data: settings } = await supabase
    .from('app_settings')
    .select('key, value')
    .in('key', ['travel_base_lat', 'travel_base_lng']);

  const get = (key: string) => settings?.find((s) => s.key === key)?.value;
  const baseLat = parseFloat(get('travel_base_lat') || '-26.9078');
  const baseLng = parseFloat(get('travel_base_lng') || '-48.6728');

  const oneWay = haversine(baseLat, baseLng, marinaLat, marinaLng);
  const distance_km = Math.round(oneWay * 2 * 10) / 10;

  const total_cost = calculateTravelCost({
    distance_km,
    travel_hours: 0,
    technician_count: technicianCount,
    ferry_cost: 0,
    travel_type: 'comercial',
  });

  return { distance_km, cost_per_km: 1.10, total_cost };
}
