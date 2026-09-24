import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { logError } from '@/lib/diagnostics';

/**
 * As ações que a auditoria aceita.
 *
 * É a mesma lista do CHECK `audit_log_action_check` no banco, e as duas têm que andar
 * juntas: o banco recusa o que não está lá, então um valor novo aqui sem a migration
 * correspondente vira linha perdida. O teste `src/test/audit-log-acoes.test.ts` compara
 * as duas listas e falha quando uma anda sem a outra.
 */
export type AuditAction =
  | 'update' | 'cancel' | 'reopen' | 'reversal' | 'cascade_update' | 'client_signature'
  | 'whatsapp_send' | 'whatsapp_send_api' | 'whatsapp_received' | 'whatsapp_preview'
  | 'whatsapp_send_open' | 'whatsapp_unread_reminder_enqueued'
  | 'lead_created' | 'lead_matched' | 'lead_converted'
  | 'import_xml' | 'confirm_import' | 'revert_import';

export async function writeAuditLog(entry: {
  table_name: string;
  record_id: string;
  action: AuditAction;
  changed_by?: string;
  previous_value?: any;
  new_value?: any;
  reason?: string;
  triggered_by_table?: string;
  triggered_by_id?: string;
}): Promise<void> {
  try {
    const { error } = await supabase.from('audit_log').insert({
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
    // O `insert` do supabase-js DEVOLVE o erro, não o lança — então o `catch` abaixo
    // nunca via nada, e seis ações recusadas pelo CHECK sumiram sem deixar rastro
    // nenhum durante meses. Falhar aqui continua não podendo derrubar a operação do
    // usuário, mas tem que aparecer em algum lugar.
    if (error) {
      void logError({
        message: `Auditoria recusada (${entry.action} em ${entry.table_name}): ${error.message}`,
        action: 'audit_log',
        level: 'warn',
        details: { acao: entry.action, tabela: entry.table_name, codigo: error.code },
      });
    }
  } catch (e) {
    // Rede fora do ar, por exemplo. Auditoria nunca derruba o fluxo principal.
    void logError({
      message: `Auditoria não gravada (${entry.action} em ${entry.table_name})`,
      action: 'audit_log', level: 'warn', error: e,
    });
  }
}

export function useAuditLog(filters?: {
  table_name?: string;
  action?: string;
  dateFrom?: string;
  dateTo?: string;
  record_id?: string;
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
      if (filters?.record_id) q = q.eq('record_id', filters.record_id);
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
