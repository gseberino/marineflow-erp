import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

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

// Upsert a single key in app_settings
export function useUpdateAppSetting() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ key, value }: { key: string; value: string }) => {
      const { error } = await supabase
        .from('app_settings')
        .upsert({ key, value }, { onConflict: 'key' });
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['app-settings'] });
    },
    onError: (e: any) => toast.error(e?.message || 'Falha ao salvar configuração.'),
  });
}

// Batch upsert multiple settings at once
export function useUpdateAppSettings() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (entries: Record<string, string>) => {
      const rows = Object.entries(entries).map(([key, value]) => ({ key, value }));
      const { error } = await supabase
        .from('app_settings')
        .upsert(rows, { onConflict: 'key' });
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['app-settings'] });
      toast.success('Configurações salvas.');
    },
    onError: (e: any) => toast.error(e?.message || 'Falha ao salvar configurações.'),
  });
}
