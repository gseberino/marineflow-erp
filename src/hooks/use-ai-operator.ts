import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import type { AIContext } from "@/lib/ai-context";
import { sanitizeOperatorText } from "@/lib/ai-operator-display";

export type OperatorChatMessage =
  | { role: "user"; content: string }
  | { role: "assistant"; content: string }
  | { role: "tool"; tool_call_id: string; content: string };

export type OperatorPendingAction = {
  id: string;
  action: string;
  risk_level: "low" | "medium" | "high" | "critical";
  risk_reason: string;
  title: string;
  summary_markdown: string;
  payload: any;
};

export type OperatorDisplayItem =
  | { kind: "message"; role: "user" | "assistant"; content: string }
  | { kind: "draft_ref"; draftId: string }
  | { kind: "pending_action"; action: OperatorPendingAction; status: "pending" | "approved" | "rejected" };

export function useAIOperator(
  context: AIContext,
  options?: { initialSessionId?: string | null; initialDraftId?: string | null }
) {
  const [sessionId, setSessionId] = useState<string | null>(options?.initialSessionId ?? null);
  const [messages, setMessages] = useState<OperatorChatMessage[]>([]);
  const [display, setDisplay] = useState<OperatorDisplayItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [activeDraftId, setActiveDraftId] = useState<string | null>(options?.initialDraftId ?? null);
  const [activePendingActionId, setActivePendingActionId] = useState<string | null>(null);
  const hydratedSessionRef = useRef<string | null>(null);

  const serializedContext = useMemo(() => JSON.stringify(context), [context]);

  useEffect(() => {
    if (options?.initialSessionId && sessionId !== options.initialSessionId) {
      setSessionId(options.initialSessionId);
    }
  }, [options?.initialSessionId, sessionId]);

  useEffect(() => {
    if (options?.initialDraftId && activeDraftId !== options.initialDraftId) {
      setActiveDraftId(options.initialDraftId);
    }
  }, [options?.initialDraftId, activeDraftId]);

  useEffect(() => {
    if (!options?.initialSessionId || !sessionId || sessionId !== options.initialSessionId) return;
    if (hydratedSessionRef.current === sessionId) return;

    let cancelled = false;
    async function hydrateExistingConversation() {
      const { data, error: loadError } = await supabase
        .from("ai_operator_messages")
        .select("role, content")
        .eq("session_id", sessionId)
        .order("created_at");
      if (cancelled || loadError) return;

      const hydratedMessages = (data || []).flatMap((message: any) => {
        if ((message.role !== "user" && message.role !== "assistant") || !message.content) return [];
        return [{ role: message.role, content: String(message.content) } as OperatorChatMessage];
      });

      setMessages(hydratedMessages);
      setDisplay(
        hydratedMessages.map((message) => ({
          kind: "message" as const,
          role: message.role,
          content: sanitizeOperatorText(message.content),
        }))
      );
      hydratedSessionRef.current = sessionId;
    }

    hydrateExistingConversation();
    return () => {
      cancelled = true;
    };
  }, [options?.initialSessionId, sessionId]);

  useEffect(() => {
    if (!activeDraftId) return;
    setDisplay((current) => {
      if (current.some((item) => item.kind === "draft_ref" && item.draftId === activeDraftId)) return current;
      return [...current, { kind: "draft_ref", draftId: activeDraftId }];
    });
  }, [activeDraftId]);

  const sendMessage = useCallback(
    async (text: string) => {
      const userMsg: OperatorChatMessage = { role: "user", content: text };
      setMessages((current) => [...current, userMsg]);
      setDisplay((current) => [...current, { kind: "message", role: "user", content: text }]);
      setLoading(true);
      setError(null);
      try {
        const { data, error: invokeErr } = await supabase.functions.invoke("ai-operator-core", {
          body: {
            action: "chat",
            session_id: sessionId,
            channel: "web",
            context: JSON.parse(serializedContext),
            message: text,
            draft_id: activeDraftId,
          },
        });
        if (invokeErr) throw invokeErr;
        if ((data as any)?.error) throw new Error((data as any).error);

        const respSession = (data as any).session_id as string | null;
        if (respSession && respSession !== sessionId) setSessionId(respSession);

        const reply = (data as any).message?.content as string | undefined;
        if (reply) {
          const safeReply = sanitizeOperatorText(reply);
          setMessages((current) => [...current, { role: "assistant", content: safeReply }]);
          setDisplay((current) => [...current, { kind: "message", role: "assistant", content: safeReply }]);
        }

        const draftId = (data as any).draft_id as string | null;
        if (draftId) setActiveDraftId(draftId);

        const pa = (data as any).pending_action as OperatorPendingAction | null;
        if (pa) {
          setActivePendingActionId(pa.id);
          setDisplay((current) => [...current, { kind: "pending_action", action: pa, status: "pending" }]);
        }
      } catch (e: any) {
        const msg = e?.message || "Erro no operador";
        setError(msg);
        setDisplay((current) => [...current, { kind: "message", role: "assistant", content: `Erro: ${msg}` }]);
      } finally {
        setLoading(false);
      }
    },
    [activeDraftId, serializedContext, sessionId]
  );

  const approveAction = useCallback(async (pendingActionId: string) => {
    setLoading(true);
    try {
      const { data, error: invokeErr } = await supabase.functions.invoke("ai-operator-core", {
        body: { action: "approve_action", pending_action_id: pendingActionId },
      });
      if (invokeErr) throw invokeErr;
      if ((data as any)?.error) throw new Error((data as any).error);
      setDisplay((current) =>
        current.map((item) =>
          item.kind === "pending_action" && item.action.id === pendingActionId
            ? { ...item, status: "approved" as const }
            : item
        )
      );
      setActivePendingActionId(null);
    } catch (e: any) {
      setError(e?.message || "Falha ao aprovar acao");
    } finally {
      setLoading(false);
    }
  }, []);

  const rejectAction = useCallback(async (pendingActionId: string) => {
    setLoading(true);
    try {
      const { data, error: invokeErr } = await supabase.functions.invoke("ai-operator-core", {
        body: { action: "reject_action", pending_action_id: pendingActionId },
      });
      if (invokeErr) throw invokeErr;
      if ((data as any)?.error) throw new Error((data as any).error);
      setDisplay((current) =>
        current.map((item) =>
          item.kind === "pending_action" && item.action.id === pendingActionId
            ? { ...item, status: "rejected" as const }
            : item
        )
      );
      setActivePendingActionId(null);
    } catch (e: any) {
      setError(e?.message || "Falha ao rejeitar acao");
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
    hydratedSessionRef.current = null;
  }, []);

  return {
    sessionId,
    display,
    loading,
    error,
    activeDraftId,
    activePendingActionId,
    messages,
    sendMessage,
    approveAction,
    rejectAction,
    reset,
  };
}
