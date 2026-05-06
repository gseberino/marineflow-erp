import { useCallback, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useQueryClient } from '@tanstack/react-query';
import type { AIContext } from '@/lib/ai-context';

export type ChatMessage =
  | { role: 'user'; content: string }
  | { role: 'assistant'; content: string; tool_calls?: any[] }
  | { role: 'tool'; tool_call_id: string; content: string };

export type Proposal = {
  action: string;
  title: string;
  summary_markdown: string;
  payload: any;
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
          body: { messages: limitedMsgs, context },
        });
        if (error) throw error;
        if ((data as any)?.error) throw new Error((data as any).error);

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
    [context, invalidateAll]
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

  const confirmProposal = useCallback(async () => {
    if (!activeProposal) return;
    setDisplay((d) =>
      d.map((it, i) => (i === activeProposal.idx && it.kind === 'proposal' ? { ...it, status: 'confirmed' } : it))
    );
    const userMsg: ChatMessage = {
      role: 'user',
      content: `Confirmado pelo usuário. Execute a action "${activeProposal.proposal.action}" agora com o payload já apresentado.`,
    };
    const next = [...messages, userMsg];
    setActiveProposal(null);
    await callAgent(next);
  }, [activeProposal, messages, callAgent]);

  const cancelProposal = useCallback(async () => {
    if (!activeProposal) return;
    setDisplay((d) =>
      d.map((it, i) => (i === activeProposal.idx && it.kind === 'proposal' ? { ...it, status: 'cancelled' } : it))
    );
    const userMsg: ChatMessage = {
      role: 'user',
      content: 'Cancelei a ação. Não execute. Aguarde nova instrução.',
    };
    const next = [...messages, userMsg];
    setActiveProposal(null);
    await callAgent(next);
  }, [activeProposal, messages, callAgent]);

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
    const messageText = value === '__refine__'
      ? 'Quero refinar a busca — me peça mais detalhes para encontrar o registro correto.'
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
  }, []);

  return { display, loading, loadingMsg, error, activeProposal, activeOptions, sendMessage, confirmProposal, cancelProposal, selectOption, reset };
}
