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

export function calculateTravelCost(params: {
  distance_km: number;
  travel_hours: number;
  technician_count: number;
  ferry_cost: number;
  travel_type: 'comercial' | 'urgencia' | 'fds_feriado';
}): number {
  const { distance_km, travel_hours, technician_count, ferry_cost, travel_type } = params;
  const KM_RATE = 1.10; // R$/km (ida + volta já incluídos no distance_km)
  const HOURLY_RATES: Record<number, number> = {
    1: 90.00,
    2: 170.00,
    3: 250.00,
  };
  const hourlyRate = HOURLY_RATES[technician_count] || 90.00;
  const MULTIPLIERS: Record<string, number> = {
    comercial: 1.0,
    urgencia: 1.5,
    fds_feriado: 1.3,
  };
  const multiplier = MULTIPLIERS[travel_type] || 1.0;
  const base = (distance_km * KM_RATE) + (travel_hours * hourlyRate) + (ferry_cost || 0);
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
