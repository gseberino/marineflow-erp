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

export type OperatorDraftCandidate = {
  id: string;
  title: string | null;
  kind: string;
  status: string;
  summary: string | null;
  client_name: string | null;
  vessel_name: string | null;
  updated_at: string;
};

export type OperatorLinkProposal = {
  draft_id: string;
  draft_title: string | null;
  client: { id: string; name: string | null; subtitle?: string | null } | null;
  vessel: { id: string; name: string | null; subtitle?: string | null } | null;
  client_candidates?: { id: string; name: string | null; subtitle?: string | null }[];
  vessel_candidates?: { id: string; name: string | null; subtitle?: string | null }[];
  compatibility?: { status: string; message: string };
  rationale: string | null;
};

export type OperatorQuoteProposal = {
  draft_id: string;
  draft_title: string | null;
  client_name: string | null;
  vessel_name: string | null;
  item_count: number;
  service_count: number;
  part_count: number;
  pending_item_count: number;
  pending_questions_count: number;
  known_total: number;
  initial_status: "draft" | "pending_product";
  effects: {
    creates_external_quote: true;
    creates_service_order: false;
    sends_whatsapp: false;
    changes_stock: false;
    changes_financials: false;
    changes_schedule: false;
  };
};

export type OperatorDisplayItem =
  | { kind: "message"; role: "user" | "assistant"; content: string }
  | { kind: "draft_ref"; draftId: string }
  | { kind: "pending_action"; action: OperatorPendingAction; status: "pending" | "approved" | "rejected" }
  | {
      kind: "draft_selection";
      candidates: OperatorDraftCandidate[];
      status: "pending" | "resolved";
      selectedDraftId?: string | null;
    }
  | {
      kind: "link_proposal";
      proposal: OperatorLinkProposal;
      status: "pending" | "confirmed" | "rejected";
    }
  | {
      kind: "quote_proposal";
      proposal: OperatorQuoteProposal;
      status: "pending" | "created" | "rejected";
      externalQuote?: { id: string; quote_number: string | null; status: string | null; path: string } | null;
    };

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

  const invokeChat = useCallback(
    async (body: Record<string, unknown>) => {
      setLoading(true);
      setError(null);
      try {
        const { data, error: invokeErr } = await supabase.functions.invoke("ai-operator-core", { body });
        if (invokeErr) {
          const rawBody = (invokeErr as any)?.context?.responseBody ?? '';
          if (rawBody) {
            try {
              const parsed = JSON.parse(rawBody);
              throw new Error(parsed.error || rawBody);
            } catch (parseErr: any) {
              if (parseErr?.message !== rawBody) throw parseErr;
              throw new Error(rawBody);
            }
          }
          throw invokeErr;
        }
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

        const candidates = (data as any).draft_candidates as OperatorDraftCandidate[] | null;
        if (Array.isArray(candidates) && candidates.length > 0) {
          setDisplay((current) => [
            ...current,
            { kind: "draft_selection", candidates, status: "pending" },
          ]);
        }

        const proposedLink = (data as any).proposed_link as OperatorLinkProposal | null;
        if (proposedLink) {
          setDisplay((current) => [
            ...current,
            { kind: "link_proposal", proposal: proposedLink, status: "pending" },
          ]);
        }

        const quoteProposal = (data as any).quote_proposal as OperatorQuoteProposal | null;
        if (quoteProposal) {
          setDisplay((current) => [
            ...current,
            { kind: "quote_proposal", proposal: quoteProposal, status: "pending" },
          ]);
        }

        const pa = (data as any).pending_action as OperatorPendingAction | null;
        if (pa) {
          setActivePendingActionId(pa.id);
          setDisplay((current) => [...current, { kind: "pending_action", action: pa, status: "pending" }]);
        }

        return data;
      } catch (e: any) {
        const msg = e?.message || "Erro no operador";
        setError(msg);
        setDisplay((current) => [...current, { kind: "message", role: "assistant", content: `Erro: ${msg}` }]);
        return null;
      } finally {
        setLoading(false);
      }
    },
    [sessionId]
  );

  const sendMessage = useCallback(
    async (text: string, opts?: { draftId?: string | null }) => {
      const userMsg: OperatorChatMessage = { role: "user", content: text };
      setMessages((current) => [...current, userMsg]);
      setDisplay((current) => [...current, { kind: "message", role: "user", content: text }]);
      await invokeChat({
        action: "chat",
        session_id: sessionId,
        channel: "web",
        context: JSON.parse(serializedContext),
        message: text,
        draft_id: opts?.draftId ?? activeDraftId,
      });
    },
    [activeDraftId, invokeChat, serializedContext, sessionId]
  );

  // Seleção humana de um draft candidato apresentado pelo backend.
  // FLUXO SEGURO: primeiro chama resume_draft para obter o session_id
  // ORIGINAL autorizado pelo backend (validado via RLS + ownership).
  // Nunca usa o session_id atual do widget para o draft de outra sessão.
  const selectDraftCandidate = useCallback(
    async (candidate: OperatorDraftCandidate) => {
      setDisplay((current) =>
        current.map((item) =>
          item.kind === "draft_selection" && item.status === "pending"
            ? { ...item, status: "resolved" as const, selectedDraftId: candidate.id }
            : item
        )
      );

      // Passo 1: obter session_id autorizado para o draft selecionado.
      // O backend valida ownership (visibilidade RLS + sessionBelongsTo admin)
      // e devolve o session_id ORIGINAL — nunca o session_id atual do widget.
      setLoading(true);
      setError(null);
      let authorizedSessionId = "";
      let authorizedDraftId = "";
      try {
        const { data: resumeData, error: resumeErr } = await supabase.functions.invoke(
          "ai-operator-core",
          { body: { action: "resume_draft", draft_id: candidate.id } }
        );
        if (resumeErr) throw resumeErr;
        if ((resumeData as any)?.error) throw new Error((resumeData as any).error);
        authorizedSessionId = (resumeData as any).session_id as string;
        authorizedDraftId = (resumeData as any).draft_id as string;
        setSessionId(authorizedSessionId);
        setActiveDraftId(authorizedDraftId);
      } catch (e: any) {
        const msg = e?.message || "Erro ao retomar rascunho";
        setError(msg);
        setDisplay((current) => [
          ...current,
          { kind: "message", role: "assistant", content: `Erro: ${msg}` },
        ]);
        setLoading(false);
        return;
      }

      // Passo 2: enviar mensagem de continuação usando os identificadores
      // autorizados. invokeChat gerencia loading e display a partir daqui.
      const followUpText = `Rascunho selecionado: ${candidate.title ?? "(sem titulo)"}. Apresente o estado atual e aguarde instrucoes.`;
      setMessages((current) => [...current, { role: "user", content: followUpText }]);
      setDisplay((current) => [...current, { kind: "message", role: "user", content: followUpText }]);
      await invokeChat({
        action: "chat",
        session_id: authorizedSessionId,
        channel: "web",
        context: JSON.parse(serializedContext),
        message: followUpText,
        draft_id: authorizedDraftId,
      });
    },
    [invokeChat, serializedContext]
  );

  // Confirmação humana de uma proposta de vínculo. Chama o endpoint seguro
  // link_draft_entities com IDs vindos do payload estruturado (não do texto).
  const confirmLinkProposal = useCallback(
    async (proposal: OperatorLinkProposal) => {
      setLoading(true);
      setError(null);
      try {
        const { data, error: invokeErr } = await supabase.functions.invoke("ai-operator-core", {
          body: {
            action: "link_draft_entities",
            draft_id: proposal.draft_id,
            client_id: proposal.client?.id ?? null,
            vessel_id: proposal.vessel?.id ?? null,
          },
        });
        if (invokeErr) throw invokeErr;
        if ((data as any)?.error) throw new Error((data as any).error);
        setDisplay((current) =>
          current.map((item) =>
            item.kind === "link_proposal" && item.proposal.draft_id === proposal.draft_id && item.status === "pending"
              ? { ...item, status: "confirmed" as const }
              : item
          )
        );
        const confirmed = [
          proposal.client?.name ? `cliente ${proposal.client.name}` : null,
          proposal.vessel?.name ? `embarcacao ${proposal.vessel.name}` : null,
        ]
          .filter(Boolean)
          .join(" e ");
        const confirmMsg = `Vinculo confirmado: ${confirmed || "atualizado"} no rascunho ativo.`;
        setMessages((current) => [...current, { role: "assistant", content: confirmMsg }]);
        setDisplay((current) => [
          ...current,
          { kind: "message", role: "assistant", content: confirmMsg },
        ]);
      } catch (e: any) {
        setError(e?.message || "Falha ao confirmar vinculo");
      } finally {
        setLoading(false);
      }
    },
    []
  );

  const rejectLinkProposal = useCallback((draftId: string) => {
    setDisplay((current) =>
      current.map((item) =>
        item.kind === "link_proposal" && item.proposal.draft_id === draftId && item.status === "pending"
          ? { ...item, status: "rejected" as const }
          : item
      )
    );
  }, []);

  const confirmQuoteProposal = useCallback(async (proposal: OperatorQuoteProposal) => {
    setLoading(true);
    setError(null);
    try {
      const { data, error: invokeErr } = await supabase.functions.invoke("ai-operator-core", {
        body: {
          action: "create_external_quote_from_draft",
          draft_id: proposal.draft_id,
        },
      });
      if (invokeErr) throw invokeErr;
      if ((data as any)?.error) throw new Error((data as any).error);
      const externalQuote = (data as any).external_quote ?? null;
      setDisplay((current) =>
        current.map((item) =>
          item.kind === "quote_proposal" && item.proposal.draft_id === proposal.draft_id && item.status === "pending"
            ? { ...item, status: "created" as const, externalQuote }
            : item
        )
      );
      const quoteNumber = externalQuote?.quote_number ? ` ${externalQuote.quote_number}` : "";
      const confirmMsg = `Orcamento formal${quoteNumber} criado no ERP. Nenhuma OS foi criada.`;
      setMessages((current) => [...current, { role: "assistant", content: confirmMsg }]);
      setDisplay((current) => [
        ...current,
        { kind: "message", role: "assistant", content: confirmMsg },
      ]);
    } catch (e: any) {
      const msg = e?.message || "Falha ao criar orcamento formal";
      setError(msg);
      setDisplay((current) => [...current, { kind: "message", role: "assistant", content: `Erro: ${msg}` }]);
    } finally {
      setLoading(false);
    }
  }, []);

  const rejectQuoteProposal = useCallback((draftId: string) => {
    setDisplay((current) =>
      current.map((item) =>
        item.kind === "quote_proposal" && item.proposal.draft_id === draftId && item.status === "pending"
          ? { ...item, status: "rejected" as const }
          : item
      )
    );
  }, []);

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
    selectDraftCandidate,
    confirmLinkProposal,
    rejectLinkProposal,
    confirmQuoteProposal,
    rejectQuoteProposal,
    approveAction,
    rejectAction,
    reset,
  };
}
