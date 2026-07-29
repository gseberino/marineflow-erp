import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

export interface BankConnection {
  id: string;
  provider: string;
  external_id: string;
  label: string;
  institution: string | null;
  account_kind: 'bank' | 'credit_card';
  active: boolean;
  last_synced_at: string | null;
  last_sync_status: 'ok' | 'error' | 'never' | null;
  last_sync_message: string | null;
  last_sync_imported: number | null;
  last_transaction_date: string | null;
}

export interface SyncResult {
  ok: boolean;
  message: string;
  resultados: Array<{
    conexao: string;
    status: 'ok' | 'error';
    mensagem: string;
    importadas: number;
    ja_existiam?: number;
  }>;
}

export function useBankConnections() {
  return useQuery({
    queryKey: ['bank-connections'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('bank_connections')
        .select('*')
        .order('created_at');
      if (error) throw error;
      return (data || []) as unknown as BankConnection[];
    },
  });
}

export function useSaveBankConnection() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: {
      id?: string;
      external_id: string;
      label: string;
      institution?: string | null;
      account_kind?: 'bank' | 'credit_card';
      active?: boolean;
    }) => {
      const payload = {
        provider: 'pluggy',
        external_id: input.external_id.trim(),
        label: input.label.trim(),
        institution: input.institution ?? null,
        account_kind: input.account_kind ?? 'bank',
        active: input.active ?? true,
      };
      const query = input.id
        ? supabase.from('bank_connections').update(payload).eq('id', input.id)
        : supabase.from('bank_connections').insert(payload);
      const { error } = await query;
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['bank-connections'] }),
  });
}

export function useDeleteBankConnection() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.from('bank_connections').delete().eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['bank-connections'] }),
  });
}

/**
 * Dispara a busca do extrato. Devolve a mensagem real quando a função recusa —
 * `functions.invoke` sozinho só diz "non-2xx status code", e o motivo (consentimento
 * caído, credencial ausente) fica escondido no corpo.
 */
export interface PluggyItemDisponivel {
  id: string;
  connector: string;
  status: string;
  ja_cadastrado: boolean;
}

/**
 * Lista as conexões que as credenciais configuradas enxergam.
 *
 * O Item ID não existe em lugar nenhum do banco — só no painel do provedor — e copiar o
 * de uma aplicação diferente daquela que gerou as credenciais dá um "item não encontrado"
 * que parece erro de digitação. Perguntar ao próprio provedor o que ele vê resolve isso
 * sem tentativa e erro.
 */
export function useListPluggyItems() {
  return useMutation({
    mutationFn: async () => {
      const { data, error } = await supabase.functions.invoke('banking-sync', {
        body: { action: 'list_items' },
      });
      if (error) {
        const resposta = (error as any)?.context as Response | undefined;
        if (resposta && typeof resposta.json === 'function') {
          try {
            const corpo = await resposta.json();
            if (corpo?.error) {
              throw new Error(corpo.detail ? `${corpo.error}: ${corpo.detail}` : String(corpo.error));
            }
          } catch (e) {
            if (e instanceof Error && !e.message.includes('non-2xx')) throw e;
          }
        }
        throw error;
      }
      return {
        itens: ((data as any)?.itens ?? []) as PluggyItemDisponivel[],
        clientIdPrefixo: String((data as any)?.client_id_prefixo ?? ''),
      };
    },
  });
}

export function useSyncBank() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: { connectionId?: string; full?: boolean } = {}) => {
      const { data, error } = await supabase.functions.invoke('banking-sync', {
        body: { connection_id: input.connectionId, full: input.full },
      });
      if (error) {
        const resposta = (error as any)?.context as Response | undefined;
        if (resposta && typeof resposta.json === 'function') {
          try {
            const corpo = await resposta.json();
            if (corpo?.error) {
              throw new Error(corpo.detail ? `${corpo.error}: ${corpo.detail}` : String(corpo.error));
            }
          } catch (e) {
            if (e instanceof Error && !e.message.includes('non-2xx')) throw e;
          }
        }
        throw error;
      }
      if ((data as any)?.error) throw new Error((data as any).error);
      return data as SyncResult;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['bank-connections'] });
      qc.invalidateQueries({ queryKey: ['bank-transactions'] });
      qc.invalidateQueries({ queryKey: ['reconcile-suggestions'] });
      qc.invalidateQueries({ queryKey: ['reconciliation-health'] });
    },
  });
}
