import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

export async function writeAuditLog(entry: {
  table_name: string;
  record_id: string;
  action: 'update' | 'cancel' | 'reopen' | 'reversal' | 'cascade_update';
  changed_by?: string;
  previous_value?: any;
  new_value?: any;
  reason?: string;
  triggered_by_table?: string;
  triggered_by_id?: string;
}): Promise<void> {
  try {
    await supabase.from('audit_log').insert({
      table_name: entry.table_name,
      record_id: entry.record_id,
      action: entry.action,
      changed_by: entry.changed_by || 'sistema',
      previous_value: entry.previous_value || null,
      new_value: entry.new_value || null,
      reason: entry.reason || null,
      triggered_by_table: entry.triggered_by_table || null,
      triggered_by_id: entry.triggered_by_id || null,
    });
  } catch {
    // Audit log failure should never break main flow
  }
}

export function useAuditLog(filters?: {
  table_name?: string;
  action?: string;
  dateFrom?: string;
  dateTo?: string;
}) {
  return useQuery({
    queryKey: ['audit-log', filters],
    queryFn: async () => {
      let q = supabase
        .from('audit_log')
        .select('*')
        .order('changed_at', { ascending: false })
        .limit(500);
      if (filters?.table_name) q = q.eq('table_name', filters.table_name);
      if (filters?.action) q = q.eq('action', filters.action);
      if (filters?.dateFrom) q = q.gte('changed_at', filters.dateFrom);
      if (filters?.dateTo) q = q.lte('changed_at', filters.dateTo);
      const { data, error } = await q;
      if (error) throw error;
      return data;
    },
  });
}

export function useRecordHistory(tableName: string, recordId: string | undefined) {
  return useQuery({
    queryKey: ['audit-log', tableName, recordId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('audit_log')
        .select('*')
        .eq('table_name', tableName)
        .eq('record_id', recordId!)
        .order('changed_at', { ascending: false });
      if (error) throw error;
      return data;
    },
    enabled: !!recordId,
  });
}
