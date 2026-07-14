import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/use-auth';
import { useQueryClient } from '@tanstack/react-query';

export type PendingRisk = 'low' | 'medium' | 'high' | 'critical';

export interface PendingAction {
  id: string;
  action_name: string;
  risk_level: PendingRisk;
  title: string | null;
  summary: string | null;
  status: string;
  requested_by_user_id: string | null;
  created_at: string;
  expires_at: string | null;
}

/**
 * Pendências de aprovação do AI Operator (ai_operator_pending_actions) do usuário atual,
 * em tempo real. A RLS já limita a quem pode ver (dono da pendência/sessão ou admin), então
 * aqui só filtramos status='pending'. Aprovar/rejeitar vai pela edge function ai-agent
 * (type: confirm_action) — execução determinística, sem passar pelo LLM.
 *
 * Cobre também as pendências criadas pelo canal WhatsApp e (futuramente) pelas rotinas —
 * elas aparecem aqui no painel automaticamente.
 */
export function usePendingActions() {
  const { user } = useAuth();
  const qc = useQueryClient();
  const [items, setItems] = useState<PendingAction[]>([]);
  const [loading, setLoading] = useState(false);
  const [actingId, setActingId] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    if (!user) return;
    const { data } = await supabase
      .from('ai_operator_pending_actions')
      .select('id, action_name, risk_level, title, summary, status, requested_by_user_id, created_at, expires_at')
      .eq('status', 'pending')
      .order('created_at', { ascending: false })
      .limit(50);
    setItems((data as PendingAction[]) || []);
  }, [user]);

  useEffect(() => { refresh(); }, [refresh]);

  // Realtime: qualquer INSERT/UPDATE na tabela recarrega a lista (a RLS filtra o que o
  // usuário pode ver na consulta; o evento em si serve só de gatilho).
  useEffect(() => {
    if (!user) return;
    const channel = supabase
      .channel('ai-pending-actions')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'ai_operator_pending_actions' }, () => refresh())
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [user, refresh]);

  const decide = useCallback(
    async (pendingActionId: string, decision: 'approve' | 'reject'): Promise<{ ok: boolean; error?: string }> => {
      setActingId(pendingActionId);
      try {
        const { data, error } = await supabase.functions.invoke('ai-agent', {
          body: { type: 'confirm_action', pending_action_id: pendingActionId, decision },
        });
        if (error) {
          const rawBody = (error as any)?.context?.responseBody ?? '';
          let msg = error.message;
          if (rawBody) { try { msg = JSON.parse(rawBody).error || rawBody; } catch { msg = rawBody; } }
          throw new Error(msg);
        }
        if ((data as any)?.error) throw new Error((data as any).error);
        // Remove otimista + revalida dados de negócio que a ação possa ter mudado.
        setItems((prev) => prev.filter((p) => p.id !== pendingActionId));
        if (decision === 'approve') {
          ['service-orders', 'receivables', 'payables', 'payments', 'purchase-orders', 'products', 'inventory']
            .forEach((k) => qc.invalidateQueries({ queryKey: [k] }));
        }
        return { ok: true };
      } catch (e: any) {
        return { ok: false, error: e?.message || 'Falha ao processar a decisão' };
      } finally {
        setActingId(null);
        setLoading(false);
      }
    },
    [qc],
  );

  return {
    items,
    count: items.length,
    loading,
    actingId,
    refresh,
    approve: (id: string) => decide(id, 'approve'),
    reject: (id: string) => decide(id, 'reject'),
  };
}
