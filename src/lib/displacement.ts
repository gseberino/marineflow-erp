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

export async function calculateDisplacement(
  marinaLat: number,
  marinaLng: number,
  technicianCount: number
): Promise<{ distance_km: number; cost_per_km: number; total_cost: number }> {
  const { data: settings } = await supabase
    .from('app_settings')
    .select('key, value')
    .in('key', ['travel_base_lat', 'travel_base_lng', 'travel_cost_per_km']);

  const get = (key: string) => settings?.find((s) => s.key === key)?.value;
  const baseLat = parseFloat(get('travel_base_lat') || '-26.9078');
  const baseLng = parseFloat(get('travel_base_lng') || '-48.6728');
  const costPerKm = parseFloat(get('travel_cost_per_km') || '3.50');

  const oneWay = haversine(baseLat, baseLng, marinaLat, marinaLng);
  const distance_km = Math.round(oneWay * 2 * 10) / 10; // round trip, 1 decimal
  const total_cost = Math.round(distance_km * costPerKm * technicianCount * 100) / 100;

  return { distance_km, cost_per_km: costPerKm, total_cost };
}
