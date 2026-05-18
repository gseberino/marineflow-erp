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

export type ProposalStatus = 'pending' | 'confirmed' | 'cancelled' | 'executed' | 'partial' | 'failed';

export type DisplayItem =
  | { kind: 'message'; role: 'user' | 'assistant'; content: string }
  | { kind: 'proposal'; proposal: Proposal; status: ProposalStatus; resultMessage?: string }
  | { kind: 'options'; data: OptionsData; status: 'pending' | 'selected'; selectedValue?: string }
  | { kind: 'tool_summary'; text: string };

type ToolClassification =
  | { kind: 'success'; summary?: string }
  | { kind: 'partial'; message: string }
  | { kind: 'failed'; message: string }
  | { kind: 'unknown' };

const WRITE_TOOL_RE = /^(create|update|apply|add|send|cancel|adjust|schedule)_/;

function formatCurrencyBRL(v: number): string {
  return new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);
}

function classifyToolResult(events: any[], proposalAction: string): ToolClassification {
  if (!Array.isArray(events) || events.length === 0) return { kind: 'unknown' };
  // Considera apenas eventos de tools de escrita (não propose_action/present_options/searches).
  const writes = events.filter((e) => WRITE_TOOL_RE.test(String(e?.name || '')));
  if (writes.length === 0) return { kind: 'unknown' };
  // Pega o evento que corresponde ao proposalAction (ou seu plural), com fallback ao último write.
  const matchesAction = (name: string) =>
    name === proposalAction ||
    name === `${proposalAction}s` ||
    (proposalAction === 'add_service_to_order' && name === 'add_services_to_order');
  const last = writes.filter((e) => matchesAction(String(e.name))).pop() || writes[writes.length - 1];
  const r = last?.result || {};

  // 1) Contadores são fonte mais específica que ok/error — checar primeiro.
  const created = typeof r.created_count === 'number' ? r.created_count : null;
  const failedCount = typeof r.failed_count === 'number' ? r.failed_count : null;
  if (created !== null && failedCount !== null) {
    const detail = Array.isArray(r.failed) && r.failed.length
      ? r.failed.map((f: any) => `• ${f.service_name || f.index}: ${f.error}`).join('\n')
      : '';
    if (created === 0 && failedCount > 0) {
      const baseMsg = `Nenhum item foi inserido.${detail ? '\n' + detail : ''}`;
      const errMsg = r.error ? `${r.error}\n${baseMsg}` : baseMsg;
      return { kind: 'failed', message: errMsg };
    }
    if (failedCount > 0) {
      return {
        kind: 'partial',
        message: `${created} criados, ${failedCount} falharam.${detail ? '\n' + detail : ''}`,
      };
    }
    // created > 0 && failed_count === 0
    const total = typeof r.total_added === 'number' ? r.total_added : null;
    return {
      kind: 'success',
      summary: total !== null
        ? `${created} serviço(s) adicionado(s) — Total: ${formatCurrencyBRL(total)}`
        : `${created} item(ns) adicionado(s)`,
    };
  }

  // 2) Sem contadores: erro explícito ou ok=false → failed.
  if (r.error) return { kind: 'failed', message: String(r.error) };
  if (r.ok === false) return { kind: 'failed', message: String(r.message || 'Falha reportada pela tool') };

  // 3) ok=true sem contadores → success simples.
  if (r.ok === true) return { kind: 'success' };
  return { kind: 'unknown' };
}

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
    [
      'clients',
      'vessels',
      'products',
      'service-orders',
      'agenda',
      'collections',
      'so-services',
      'so-parts',
      'pdf-data',
      'receivables',
      'payables',
      'time-entries',
    ].forEach((k) => qc.invalidateQueries({ queryKey: [k] }));
    if (context?.entityType === 'service_order' && context.entityId) {
      qc.invalidateQueries({ queryKey: ['so-services', context.entityId] });
      qc.invalidateQueries({ queryKey: ['so-parts', context.entityId] });
      qc.invalidateQueries({ queryKey: ['service-orders', context.entityId] });
    }
  }, [qc, context]);

  const callAgent = useCallback(
    async (msgs: ChatMessage[]): Promise<{ toolEvents: any[]; ok: boolean }> => {
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
        if (error) {
          // Tenta extrair mensagem amigável do body da edge function (ex: créditos esgotados)
          const rawBody = (error as any)?.context?.responseBody ?? '';
          if (rawBody) {
            try { throw new Error(JSON.parse(rawBody).error || rawBody); } catch (parseErr: any) { if (parseErr?.message !== rawBody) throw parseErr; throw new Error(rawBody); }
          }
          throw error;
        }
        if ((data as any)?.error) throw new Error((data as any).error);

        // Atualiza histórico oficial — usa updated_messages se vier (caso de proposal)
        const updated = (data as any).updated_messages as ChatMessage[] | undefined;
        const finalMsgs = updated ? updated : [...msgs, (data as any).message];
        setMessages(finalMsgs);

        const toolEvents: any[] = Array.isArray((data as any).tool_events) ? (data as any).tool_events : [];

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
          // Se houve tool_events de escrita, invalida queries (independente do texto do modelo)
          if (toolEvents.some((e: any) => WRITE_TOOL_RE.test(String(e?.name || '')))) {
            invalidateAll();
          }
        }
        return { toolEvents, ok: true };
      } catch (e: any) {
        const msg = e?.message || 'Erro no agente';
        setError(msg);
        setDisplay((d) => [...d, { kind: 'message', role: 'assistant', content: `❌ ${msg}` }]);
        return { toolEvents: [], ok: false };
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
    const proposalIdx = activeProposal.idx;
    const proposalAction = activeProposal.proposal.action;
    const proposalPayload = activeProposal.proposal.payload;
    setDisplay((d) =>
      d.map((it, i) => (i === proposalIdx && it.kind === 'proposal' ? { ...it, status: 'confirmed' } : it))
    );
    // Envia payload explicitamente para o agente não precisar reconstruir da memória
    const userMsg: ChatMessage = {
      role: 'user',
      content: `Confirmado pelo usuário. Execute a action "${proposalAction}" agora com este payload exato (use os IDs exatamente como estão): ${JSON.stringify(proposalPayload)}`,
    };
    const next = [...messages, userMsg];
    setActiveProposal(null);
    const { toolEvents, ok } = await callAgent(next);
    // Status final é DETERMINADO pelos tool_events da tool real, não pela mensagem livre do modelo.
    const classification: ToolClassification = ok
      ? classifyToolResult(toolEvents, proposalAction)
      : { kind: 'failed', message: 'Erro de comunicação com o agente.' };
    setDisplay((d) =>
      d.map((it, i) => {
        if (i !== proposalIdx || it.kind !== 'proposal') return it;
        if (classification.kind === 'success') {
          return { ...it, status: 'executed', resultMessage: classification.summary };
        }
        if (classification.kind === 'partial') {
          return { ...it, status: 'partial', resultMessage: classification.message };
        }
        if (classification.kind === 'failed') {
          return { ...it, status: 'failed', resultMessage: classification.message };
        }
        // unknown → mantém 'confirmed' como neutro (não afirma sucesso indevido)
        return { ...it, status: 'executed' };
      })
    );
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
  }, []);

  return { display, loading, loadingMsg, error, activeProposal, activeOptions, sendMessage, confirmProposal, cancelProposal, selectOption, reset };
}
