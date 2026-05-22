import { useCallback, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type { AIContext } from '@/lib/ai-context';

// Hook que conversa com a edge function `ai-operator-core` (núcleo seguro
// do MarineFlow AI Operator). Diferente do `use-ai-agent` legacy, este hook:
//   * Persiste a sessão no banco (session_id é mantido entre chamadas).
//   * Suporta retorno de `draft_id` (rascunho operacional criado pelo modelo).
//   * Suporta retorno de `pending_action` (ação sensível aguardando aprovação
//     com classificação de risco vinda do backend, não do prompt).
//
// O hook NÃO toca em flows do `use-ai-agent` original.

export type OperatorChatMessage =
  | { role: 'user'; content: string }
  | { role: 'assistant'; content: string }
  | { role: 'tool'; tool_call_id: string; content: string };

export type OperatorPendingAction = {
  id: string;
  action: string;
  risk_level: 'low' | 'medium' | 'high' | 'critical';
  risk_reason: string;
  title: string;
  summary_markdown: string;
  payload: any;
};

export type OperatorDisplayItem =
  | { kind: 'message'; role: 'user' | 'assistant'; content: string }
  | { kind: 'draft_ref'; draftId: string }
  | { kind: 'pending_action'; action: OperatorPendingAction; status: 'pending' | 'approved' | 'rejected' };

export function useAIOperator(context: AIContext) {
  const [sessionId, setSessionId] = useState<string | null>(null);
  const [messages, setMessages] = useState<OperatorChatMessage[]>([]);
  const [display, setDisplay] = useState<OperatorDisplayItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [activeDraftId, setActiveDraftId] = useState<string | null>(null);
  const [activePendingActionId, setActivePendingActionId] = useState<string | null>(null);

  const sendMessage = useCallback(
    async (text: string) => {
      const userMsg: OperatorChatMessage = { role: 'user', content: text };
      const nextMsgs = [...messages, userMsg];
      setMessages(nextMsgs);
      setDisplay((d) => [...d, { kind: 'message', role: 'user', content: text }]);
      setLoading(true);
      setError(null);
      try {
        const { data, error: invokeErr } = await supabase.functions.invoke('ai-operator-core', {
          body: {
            action: 'chat',
            session_id: sessionId,
            channel: 'web',
            context,
            messages: nextMsgs,
          },
        });
        if (invokeErr) throw invokeErr;
        if ((data as any)?.error) throw new Error((data as any).error);

        const respSession = (data as any).session_id as string | null;
        if (respSession && respSession !== sessionId) setSessionId(respSession);

        const reply = (data as any).message?.content as string | undefined;
        if (reply) {
          setMessages((m) => [...m, { role: 'assistant', content: reply }]);
          setDisplay((d) => [...d, { kind: 'message', role: 'assistant', content: reply }]);
        }

        const draftId = (data as any).draft_id as string | null;
        if (draftId) {
          setActiveDraftId(draftId);
          setDisplay((d) => [...d, { kind: 'draft_ref', draftId }]);
        }

        const pa = (data as any).pending_action as OperatorPendingAction | null;
        if (pa) {
          setActivePendingActionId(pa.id);
          setDisplay((d) => [...d, { kind: 'pending_action', action: pa, status: 'pending' }]);
        }
      } catch (e: any) {
        const msg = e?.message || 'Erro no operador';
        setError(msg);
        setDisplay((d) => [...d, { kind: 'message', role: 'assistant', content: `❌ ${msg}` }]);
      } finally {
        setLoading(false);
      }
    },
    [messages, sessionId, context]
  );

  const approveAction = useCallback(
    async (pendingActionId: string) => {
      setLoading(true);
      try {
        const { data, error: invokeErr } = await supabase.functions.invoke('ai-operator-core', {
          body: { action: 'approve_action', pending_action_id: pendingActionId },
        });
        if (invokeErr) throw invokeErr;
        if ((data as any)?.error) throw new Error((data as any).error);
        setDisplay((d) =>
          d.map((it) =>
            it.kind === 'pending_action' && it.action.id === pendingActionId
              ? { ...it, status: 'approved' as const }
              : it
          )
        );
        setActivePendingActionId(null);
      } catch (e: any) {
        setError(e?.message || 'Falha ao aprovar ação');
      } finally {
        setLoading(false);
      }
    },
    []
  );

  const rejectAction = useCallback(async (pendingActionId: string) => {
    setLoading(true);
    try {
      const { data, error: invokeErr } = await supabase.functions.invoke('ai-operator-core', {
        body: { action: 'reject_action', pending_action_id: pendingActionId },
      });
      if (invokeErr) throw invokeErr;
      if ((data as any)?.error) throw new Error((data as any).error);
      setDisplay((d) =>
        d.map((it) =>
          it.kind === 'pending_action' && it.action.id === pendingActionId
            ? { ...it, status: 'rejected' as const }
            : it
        )
      );
      setActivePendingActionId(null);
    } catch (e: any) {
      setError(e?.message || 'Falha ao rejeitar ação');
    } finally {
      setLoading(false);
    }
  }, []);

  const reset = useCallback(() => {
    setSessionId(null);
    setMessages([]);
    setDisplay([]);
    setActiveDraftId(null);
    setActivePendingActionId(null);
    setError(null);
  }, []);

  return {
    sessionId,
    display,
    loading,
    error,
    activeDraftId,
    activePendingActionId,
    sendMessage,
    approveAction,
    rejectAction,
    reset,
  };
}
