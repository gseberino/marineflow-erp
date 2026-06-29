import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

export interface WhatsAppSendLogEntry {
  id: string;
  record_id: string;
  changed_at: string;
  changed_by: string;
  reason: string | null;
  new_value: any;
  success: boolean;
}

/**
 * Última tentativa de envio via WhatsApp por OS (mapa: service_order_id -> entry).
 */
export function useWhatsAppSendStatusMap(serviceOrderIds: string[]) {
  const idsKey = [...serviceOrderIds].sort().join(',');
  return useQuery({
    queryKey: ['whatsapp-send-status', idsKey],
    enabled: serviceOrderIds.length > 0,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('audit_log')
        .select('id, record_id, changed_at, changed_by, reason, new_value')
        .eq('table_name', 'service_orders')
        .eq('action', 'whatsapp_send_api')
        .in('record_id', serviceOrderIds)
        .order('changed_at', { ascending: false });

      if (error) throw error;

      const map = new Map<string, WhatsAppSendLogEntry>();
      for (const row of data || []) {
        if (!map.has(row.record_id)) {
          const nv: any = row.new_value || {};
          const providerResult = nv?.provider_result;
          const success = providerResult != null
            ? providerResult.ok === true
            : (nv?.http_status >= 200 && nv?.http_status < 300 && !nv?.zapi_response?.error);
          map.set(row.record_id, { ...row, success } as WhatsAppSendLogEntry);
        }
      }
      return map;
    },
    staleTime: 30_000,
  });
}

/**
 * Histórico completo (todas as tentativas) de uma OS específica.
 */
export function useWhatsAppSendHistory(serviceOrderId: string | null) {
  return useQuery({
    queryKey: ['whatsapp-send-history', serviceOrderId],
    enabled: !!serviceOrderId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('audit_log')
        .select('id, record_id, changed_at, changed_by, reason, new_value')
        .eq('table_name', 'service_orders')
        .eq('action', 'whatsapp_send_api')
        .eq('record_id', serviceOrderId!)
        .order('changed_at', { ascending: false });
      if (error) throw error;
      return (data || []).map((row): WhatsAppSendLogEntry => {
        const nv: any = row.new_value || {};
        const providerResult = nv?.provider_result;
        const success = providerResult != null
          ? providerResult.ok === true
          : (nv?.http_status >= 200 && nv?.http_status < 300 && !nv?.zapi_response?.error);
        return { ...row, success } as WhatsAppSendLogEntry;
      });
    },
  });
}
