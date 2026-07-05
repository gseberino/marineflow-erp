import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useQueryClient } from '@tanstack/react-query';
import type { AIContext } from '@/lib/ai-context';

const SESSION_STORAGE_KEY = 'ai_session_id';

export type ChatMessage =
  | { role: 'user'; content: string }
  | { role: 'assistant'; content: string; tool_calls?: any[] }
  | { role: 'tool'; tool_call_id: string; content: string };

export type Proposal = {
  pending_action_id: string;
  title: string;
  summary_markdown: string;
  risk_level: 'medium' | 'high';
};

export type OptionItem = { label: string; value: string };

export type OptionsData = {
  question: string;
  options: OptionItem[];
};

export type DisplayItem =
  | { kind: 'message'; role: 'user' | 'assistant'; content: string }
  | { kind: 'proposal'; proposal: Proposal; status: 'pending' | 'confirmed' | 'cancelled' }
  | { kind: 'options'; data: OptionsData; status: 'pending' | 'selected'; selectedValue?: string }
  | { kind: 'tool_summary'; text: string };

export function useAIAgent(context: AIContext) {
  const qc = useQueryClient();
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [display, setDisplay] = useState<DisplayItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [loadingMsg, setLoadingMsg] = useState<string>('');
  const [activeProposal, setActiveProposal] = useState<{ idx: number; proposal: Proposal } | null>(null);
  const [activeOptions, setActiveOptions] = useState<{ idx: number; data: OptionsData } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [sessionId, setSessionId] = useState<string | null>(() => {
    try {
      return localStorage.getItem(SESSION_STORAGE_KEY);
    } catch {
      return null;
    }
  });

  // Carrega o histórico salvo (Fase 2) ao montar o widget, se já existir uma sessão.
  useEffect(() => {
    if (!sessionId) return;
    let cancelled = false;
    (async () => {
      const { data, error: histError } = await supabase.functions.invoke('ai-agent', {
        body: { type: 'load_history', session_id: sessionId },
      });
      if (cancelled || histError) return;
      const loaded = (data as any)?.messages as ChatMessage[] | undefined;
      if (!(data as any)?.session_id) {
        // Sessão não encontrada/não é mais do usuário — começa do zero silenciosamente.
        try { localStorage.removeItem(SESSION_STORAGE_KEY); } catch { /* ignore */ }
        setSessionId(null);
        return;
      }
      if (loaded && loaded.length > 0) {
        setMessages(loaded);
        setDisplay(
          loaded
            .filter((m): m is Extract<ChatMessage, { role: 'user' | 'assistant' }> => m.role === 'user' || m.role === 'assistant')
            .filter((m) => m.content)
            .map((m) => ({ kind: 'message' as const, role: m.role, content: m.content }))
        );
      }
    })();
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const invalidateAll = useCallback(() => {
    ['clients', 'vessels', 'products', 'service-orders', 'agenda', 'collections'].forEach((k) =>
      qc.invalidateQueries({ queryKey: [k] })
    );
  }, [qc]);

  const callAgent = useCallback(
    async (msgs: ChatMessage[]) => {
      setLoading(true);
      setError(null);
      setLoadingMsg('Consultando dados...');
      const progressTimer = setTimeout(() => setLoadingMsg('Processando...'), 2000);
      const progressTimer2 = setTimeout(() => setLoadingMsg('Quase lá...'), 5000);
      try {
        const limitedMsgs = msgs.length > 30 ? msgs.slice(msgs.length - 30) : msgs;
        const { data, error } = await supabase.functions.invoke('ai-agent', {
          body: { messages: limitedMsgs, context, session_id: sessionId },
        });
        if (error) {
          // Tenta extrair mensagem amigável do body da edge function (ex: créditos esgotados)
          const rawBody = (error as any)?.context?.responseBody ?? '';
          if (rawBody) {
            try { throw new Error(JSON.parse(rawBody).error || rawBody); } catch (parseErr: any) { if (parseErr?.message !== rawBody) throw parseErr; throw new Error(rawBody); }
          }
          throw error;
        }
        if ((data as any)?.error) throw new Error((data as any).error);

        // Guarda o session_id retornado (Fase 2) para as próximas chamadas e para
        // reabrir o widget mais tarde com o histórico ainda disponível.
        const returnedSessionId = (data as any)?.session_id as string | undefined;
        if (returnedSessionId && returnedSessionId !== sessionId) {
          setSessionId(returnedSessionId);
          try { localStorage.setItem(SESSION_STORAGE_KEY, returnedSessionId); } catch { /* ignore */ }
        }

        // Atualiza histórico oficial — usa updated_messages se vier (caso de proposal)
        const updated = (data as any).updated_messages as ChatMessage[] | undefined;
        const finalMsgs = updated ? updated : [...msgs, (data as any).message];
        setMessages(finalMsgs);

        if ((data as any).proposal) {
          const proposal = (data as any).proposal as Proposal;
          setDisplay((d) => {
            const next = [...d];
            const idx = next.length;
            next.push({ kind: 'proposal', proposal, status: 'pending' });
            setActiveProposal({ idx, proposal });
            return next;
          });
        } else if ((data as any).options) {
          const optionsData = (data as any).options as OptionsData;
          setDisplay((d) => {
            const next = [...d];
            const idx = next.length;
            next.push({ kind: 'options', data: optionsData, status: 'pending' });
            setActiveOptions({ idx, data: optionsData });
            return next;
          });
        } else {
          const content = (data as any).message?.content || '';
          if (content) setDisplay((d) => [...d, { kind: 'message', role: 'assistant', content }]);
          // Se houve tool_events sem proposal, ações de escrita aconteceram → invalida
          if (Array.isArray((data as any).tool_events) && (data as any).tool_events.some((e: any) => /^(create|update|apply|add|send)_/.test(e.name))) {
            invalidateAll();
          }
        }
      } catch (e: any) {
        const msg = e?.message || 'Erro no agente';
        setError(msg);
        setDisplay((d) => [...d, { kind: 'message', role: 'assistant', content: `❌ ${msg}` }]);
      } finally {
        clearTimeout(progressTimer);
        clearTimeout(progressTimer2);
        setLoadingMsg('');
        setLoading(false);
      }
    },
    [context, invalidateAll, sessionId]
  );

  const sendMessage = useCallback(
    async (text: string) => {
      const userMsg: ChatMessage = { role: 'user', content: text };
      setDisplay((d) => [...d, { kind: 'message', role: 'user', content: text }]);
      const next = [...messages, userMsg];
      await callAgent(next);
    },
    [messages, callAgent]
  );

  // Fase 3: confirmação/rejeição é determinística — o servidor executa (ou não) a tool
  // com o payload já gravado em ai_operator_pending_actions, SEM chamar o LLM de novo.
  const callConfirmAction = useCallback(
    async (pendingActionId: string, decision: 'approve' | 'reject') => {
      setLoading(true);
      setError(null);
      try {
        const { data, error } = await supabase.functions.invoke('ai-agent', {
          body: { type: 'confirm_action', pending_action_id: pendingActionId, decision },
        });
        if (error) {
          const rawBody = (error as any)?.context?.responseBody ?? '';
          if (rawBody) {
            try { throw new Error(JSON.parse(rawBody).error || rawBody); } catch (parseErr: any) { if (parseErr?.message !== rawBody) throw parseErr; throw new Error(rawBody); }
          }
          throw error;
        }
        if ((data as any)?.error) throw new Error((data as any).error);
        const content = (data as any).message?.content || '';
        if (content) setDisplay((d) => [...d, { kind: 'message', role: 'assistant', content }]);
        if (decision === 'approve') invalidateAll(); // a tool real pode ter mudado dados
      } catch (e: any) {
        const msg = e?.message || 'Erro ao processar a decisão';
        setError(msg);
        setDisplay((d) => [...d, { kind: 'message', role: 'assistant', content: `❌ ${msg}` }]);
      } finally {
        setLoading(false);
      }
    },
    [invalidateAll]
  );

  const confirmProposal = useCallback(async () => {
    if (!activeProposal) return;
    const proposalIdx = activeProposal.idx;
    const pendingActionId = activeProposal.proposal.pending_action_id;
    setDisplay((d) =>
      d.map((it, i) => (i === proposalIdx && it.kind === 'proposal' ? { ...it, status: 'confirmed' } : it))
    );
    setActiveProposal(null);
    await callConfirmAction(pendingActionId, 'approve');
    setDisplay((d) =>
      d.map((it, i) => (i === proposalIdx && it.kind === 'proposal' ? { ...it, status: 'executed' as any } : it))
    );
  }, [activeProposal, callConfirmAction]);

  const cancelProposal = useCallback(async () => {
    if (!activeProposal) return;
    const proposalIdx = activeProposal.idx;
    const pendingActionId = activeProposal.proposal.pending_action_id;
    setDisplay((d) =>
      d.map((it, i) => (i === proposalIdx && it.kind === 'proposal' ? { ...it, status: 'cancelled' } : it))
    );
    setActiveProposal(null);
    await callConfirmAction(pendingActionId, 'reject');
  }, [activeProposal, callConfirmAction]);

  const selectOption = useCallback(async (value: string, label: string) => {
    if (!activeOptions) return;
    // Mark option as selected in display
    setDisplay((d) =>
      d.map((it, i) =>
        i === activeOptions.idx && it.kind === 'options'
          ? { ...it, status: 'selected' as const, selectedValue: value }
          : it
      )
    );
    setActiveOptions(null);

    // __refine__ = user wants to narrow search with more details
    // For UUIDs: include both label and ID so agent uses correct UUID in next action
    const isUUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
    const messageText = value === '__refine__'
      ? 'Quero refinar a busca — me peça mais detalhes para encontrar o registro correto.'
      : isUUID
        ? `${label} (id: ${value})`
        : label;

    const userMsg: ChatMessage = { role: 'user', content: messageText };
    setDisplay((d) => [...d, { kind: 'message', role: 'user', content: messageText }]);
    const next = [...messages, userMsg];
    await callAgent(next);
  }, [activeOptions, messages, callAgent]);

  const reset = useCallback(() => {
    setMessages([]);
    setDisplay([]);
    setActiveProposal(null);
    setActiveOptions(null);
    setError(null);
    setSessionId(null);
    try { localStorage.removeItem(SESSION_STORAGE_KEY); } catch { /* ignore */ }
  }, []);

  return { display, loading, loadingMsg, error, activeProposal, activeOptions, sendMessage, confirmProposal, cancelProposal, selectOption, reset };
}
