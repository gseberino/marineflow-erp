import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

export type AIOperatorDraftListItem = {
  id: string;
  session_id: string | null;
  kind: string;
  status: string;
  title: string | null;
  summary: string | null;
  interpreted_intent: string | null;
  interpreted_category: string | null;
  estimated_total: number | null;
  pending_questions: string[];
  next_steps: string[];
  hypotheses: string[];
  created_at: string;
  updated_at: string;
  client_id: string | null;
  vessel_id: string | null;
  client_name: string | null;
  vessel_name: string | null;
  item_count: number;
};

export type AIOperatorDraftItem = {
  id: string;
  draft_id: string;
  item_kind: string;
  description: string;
  notes: string | null;
  quantity: number | null;
  unit: string | null;
  unit_price: number | null;
  estimated_total: number | null;
  confidence: string | null;
  position: number | null;
};

export type AIOperatorDraftDetail = {
  draft: AIOperatorDraftListItem;
  items: AIOperatorDraftItem[];
  pendingActions: Array<{ id: string; status: string; action_name: string; title: string | null }>;
  session: {
    id: string;
    created_at: string;
    last_activity_at: string;
  } | null;
};

function asStringArray(value: unknown) {
  return Array.isArray(value) ? value.filter((entry): entry is string => typeof entry === "string") : [];
}

export function useAIOperatorDrafts() {
  return useQuery({
    queryKey: ["ai-operator-drafts"],
    queryFn: async () => {
      const { data: drafts, error } = await supabase
        .from("ai_operator_drafts")
        .select(
          "id, session_id, kind, status, title, summary, interpreted_intent, interpreted_category, estimated_total, pending_questions, next_steps, hypotheses, created_at, updated_at, client_id, vessel_id, clients(full_name_or_company_name), vessels(boat_name)"
        )
        .order("updated_at", { ascending: false });
      if (error) throw error;

      const draftIds = (drafts || []).map((draft: any) => draft.id);
      const { data: itemRows, error: itemError } = draftIds.length
        ? await supabase.from("ai_operator_draft_items").select("draft_id").in("draft_id", draftIds)
        : { data: [], error: null };
      if (itemError) throw itemError;

      const itemCountMap = new Map<string, number>();
      for (const row of itemRows || []) {
        const current = itemCountMap.get((row as any).draft_id) || 0;
        itemCountMap.set((row as any).draft_id, current + 1);
      }

      return (drafts || []).map((draft: any) => ({
        id: draft.id,
        session_id: draft.session_id,
        kind: draft.kind,
        status: draft.status,
        title: draft.title,
        summary: draft.summary,
        interpreted_intent: draft.interpreted_intent,
        interpreted_category: draft.interpreted_category,
        estimated_total: draft.estimated_total,
        pending_questions: asStringArray(draft.pending_questions),
        next_steps: asStringArray(draft.next_steps),
        hypotheses: asStringArray(draft.hypotheses),
        created_at: draft.created_at,
        updated_at: draft.updated_at,
        client_id: draft.client_id,
        vessel_id: draft.vessel_id,
        client_name: draft.clients?.full_name_or_company_name ?? null,
        vessel_name: draft.vessels?.boat_name ?? null,
        item_count: itemCountMap.get(draft.id) || 0,
      })) as AIOperatorDraftListItem[];
    },
    staleTime: 30 * 1000,
  });
}

export function useAIOperatorDraftDetail(draftId: string | undefined) {
  return useQuery({
    queryKey: ["ai-operator-drafts", draftId],
    enabled: !!draftId,
    queryFn: async () => {
      const { data: draft, error } = await supabase
        .from("ai_operator_drafts")
        .select(
          "id, session_id, kind, status, title, summary, interpreted_intent, interpreted_category, estimated_total, pending_questions, next_steps, hypotheses, created_at, updated_at, client_id, vessel_id, clients(full_name_or_company_name), vessels(boat_name)"
        )
        .eq("id", draftId)
        .maybeSingle();
      if (error) throw error;
      if (!draft) throw new Error("Rascunho nao encontrado");

      const [{ data: items, error: itemsError }, { data: pendingActions, error: pendingError }, sessionResult] =
        await Promise.all([
          supabase.from("ai_operator_draft_items").select("*").eq("draft_id", draftId).order("position"),
          supabase
            .from("ai_operator_pending_actions")
            .select("id, status, action_name, title")
            .eq("draft_id", draftId)
            .order("created_at", { ascending: false }),
          draft.session_id
            ? supabase
                .from("ai_operator_sessions")
                .select("id, created_at, last_activity_at")
                .eq("id", draft.session_id)
                .maybeSingle()
            : Promise.resolve({ data: null, error: null }),
        ]);

      if (itemsError) throw itemsError;
      if (pendingError) throw pendingError;
      if (sessionResult.error) throw sessionResult.error;

      return {
        draft: {
          id: draft.id,
          session_id: draft.session_id,
          kind: draft.kind,
          status: draft.status,
          title: draft.title,
          summary: draft.summary,
          interpreted_intent: draft.interpreted_intent,
          interpreted_category: draft.interpreted_category,
          estimated_total: draft.estimated_total,
          pending_questions: asStringArray(draft.pending_questions),
          next_steps: asStringArray(draft.next_steps),
          hypotheses: asStringArray(draft.hypotheses),
          created_at: draft.created_at,
          updated_at: draft.updated_at,
          client_id: draft.client_id,
          vessel_id: draft.vessel_id,
          client_name: draft.clients?.full_name_or_company_name ?? null,
          vessel_name: draft.vessels?.boat_name ?? null,
          item_count: (items || []).length,
        },
        items: (items || []) as AIOperatorDraftItem[],
        pendingActions: (pendingActions || []) as AIOperatorDraftDetail["pendingActions"],
        session: sessionResult.data,
      } as AIOperatorDraftDetail;
    },
    staleTime: 30 * 1000,
  });
}

export function useLinkAIOperatorDraftEntities() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (input: {
      draftId: string;
      clientId: string | null;
      vesselId: string | null;
    }) => {
      const { data, error } = await supabase.functions.invoke("ai-operator-core", {
        body: {
          action: "link_draft_entities",
          draft_id: input.draftId,
          client_id: input.clientId,
          vessel_id: input.vesselId,
        },
      });
      if (error) throw error;
      if ((data as any)?.error) throw new Error((data as any).error);
      return data;
    },
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ["ai-operator-drafts"] });
      queryClient.invalidateQueries({ queryKey: ["ai-operator-drafts", variables.draftId] });
    },
  });
}
