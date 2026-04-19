import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

export function useAppSettings() {
  return useQuery({
    queryKey: ['app-settings'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('app_settings')
        .select('key, value');
      if (error) throw error;
      const map: Record<string, string> = {};
      for (const row of data || []) {
        if (row.key) map[row.key] = String(row.value || '');
      }
      return map;
    },
    staleTime: 10 * 60 * 1000, // 10 min — settings rarely change
  });
}

// Convenience getter
export function useAppSetting(key: string, fallback = ''): string {
  const { data } = useAppSettings();
  return data?.[key] || fallback;
}
