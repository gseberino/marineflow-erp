import { describe, expect, it } from "vitest";
// @ts-ignore Vitest resolve .ts
import {
  buildDraftUpdatePatch,
  evaluateCancelDraft,
  resolveCreateDraftLinks,
  resolveExplicitDraftEntitySelection,
  resolveLinkProposal,
  resolveMemoryCandidateLinks,
} from "../../supabase/functions/ai-operator-core/entity-linking.ts";

describe("AI Operator - explicit entity linking policy", () => {
  it("create_draft ignores model-provided client_id and vessel_id, even when present", () => {
    const result = resolveCreateDraftLinks(
      {
        kind: "quote",
        title: "Orcamento Raymarine",
        client_id: "client-visible-but-wrong",
        vessel_id: "vessel-visible-but-wrong",
      },
      {
        client_id: "client-confirmed",
        vessel_id: "vessel-confirmed",
      }
    );

    expect(result.links).toEqual({
      client_id: "client-confirmed",
      vessel_id: "vessel-confirmed",
    });
    expect(result.unexpected).toEqual([
      { field: "client_id", value: "client-visible-but-wrong" },
      { field: "vessel_id", value: "vessel-visible-but-wrong" },
    ]);
  });

  it("create_draft can start unlinked when there is no confirmed session context", () => {
    const result = resolveCreateDraftLinks(
      {
        kind: "quote",
        title: "Orcamento Raymarine",
        client_id: "client-visible-but-wrong",
        vessel_id: "vessel-visible-but-wrong",
      },
      null
    );

    expect(result.links).toEqual({
      client_id: null,
      vessel_id: null,
    });
    expect(result.unexpected).toHaveLength(2);
  });

  it("update_draft keeps confirmed links unchanged and strips forbidden entity fields from the patch", () => {
    const result = buildDraftUpdatePatch(
      {
        draft_id: "draft-1",
        title: "Novo titulo",
        status: "awaiting_info",
        summary: "Resumo refinado",
        client_id: "client-visible-but-wrong",
        vessel_id: "vessel-visible-but-wrong",
        service_order_id: "so-visible-but-wrong",
        converted_service_order_id: "so-converted-visible-but-wrong",
      },
      {
        client_id: "client-confirmed",
        vessel_id: "vessel-confirmed",
      }
    );

    expect(result.patch).toEqual({
      title: "Novo titulo",
      status: "awaiting_info",
      summary: "Resumo refinado",
    });
    expect(result.links).toEqual({
      client_id: "client-confirmed",
      vessel_id: "vessel-confirmed",
    });
    expect(result.unexpected).toEqual([
      { field: "client_id", value: "client-visible-but-wrong" },
      { field: "vessel_id", value: "vessel-visible-but-wrong" },
      { field: "service_order_id", value: "so-visible-but-wrong" },
      { field: "converted_service_order_id", value: "so-converted-visible-but-wrong" },
    ]);
  });

  it("register_memory_candidate inherits confirmed draft context instead of model-provided entity ids", () => {
    const result = resolveMemoryCandidateLinks(
      {
        client_id: "client-visible-but-wrong",
        vessel_id: "vessel-visible-but-wrong",
        topic: "electronics",
        title: "Observacao",
        body: "Texto",
      },
      {
        draft: {
          client_id: "client-confirmed-in-draft",
          vessel_id: "vessel-confirmed-in-draft",
        },
        session: {
          client_id: "client-confirmed-in-session",
          vessel_id: "vessel-confirmed-in-session",
        },
      }
    );

    expect(result).toMatchObject({
      client_id: "client-confirmed-in-draft",
      vessel_id: "vessel-confirmed-in-draft",
      scope: "vessel",
    });
    expect(result.unexpected).toEqual([
      { field: "client_id", value: "client-visible-but-wrong" },
      { field: "vessel_id", value: "vessel-visible-but-wrong" },
    ]);
  });

  it("register_memory_candidate falls back to confirmed session context when there is no draft context", () => {
    const result = resolveMemoryCandidateLinks(
      {
        topic: "electronics",
        title: "Observacao",
        body: "Texto",
      },
      {
        draft: null,
        session: {
          client_id: "client-confirmed-in-session",
          vessel_id: null,
        },
      }
    );

    expect(result).toMatchObject({
      client_id: "client-confirmed-in-session",
      vessel_id: null,
      scope: "client",
    });
  });

  it("register_memory_candidate stays unlinked when no confirmed context exists", () => {
    const result = resolveMemoryCandidateLinks(
      {
        client_id: "client-visible-but-wrong",
        vessel_id: "vessel-visible-but-wrong",
        topic: "electronics",
        title: "Observacao",
        body: "Texto",
      },
      {
        draft: null,
        session: null,
      }
    );

    expect(result).toMatchObject({
      client_id: null,
      vessel_id: null,
      scope: "global",
    });
    expect(result.unexpected).toHaveLength(2);
  });

  it("link_draft_entities accepts explicit UI selection when visibility and ownership are valid", () => {
    const result = resolveExplicitDraftEntitySelection({
      requestedClientId: "client-confirmed",
      requestedVesselId: "vessel-confirmed",
      clientVisible: true,
      vesselVisible: true,
      vesselClientId: "client-confirmed",
    });

    expect(result).toEqual({
      ok: true,
      status: 200,
      client_id: "client-confirmed",
      vessel_id: "vessel-confirmed",
    });
  });

  it("link_draft_entities blocks a non-visible entity", () => {
    const result = resolveExplicitDraftEntitySelection({
      requestedClientId: "client-hidden",
      requestedVesselId: null,
      clientVisible: false,
      vesselVisible: true,
      vesselClientId: null,
    });

    expect(result).toEqual({
      ok: false,
      status: 403,
      error: "Cliente nao visivel para o usuario.",
    });
  });

  it("link_draft_entities blocks a vessel that belongs to another client", () => {
    const result = resolveExplicitDraftEntitySelection({
      requestedClientId: "client-a",
      requestedVesselId: "vessel-belongs-to-b",
      clientVisible: true,
      vesselVisible: true,
      vesselClientId: "client-b",
    });

    expect(result).toEqual({
      ok: false,
      status: 400,
      error: "A embarcacao selecionada nao pertence ao cliente informado.",
    });
  });
});

describe("AI Operator - propose_entity_link (proposal only, never persists)", () => {
  it("requires at least one candidate", () => {
    const result = resolveLinkProposal({
      clientId: null,
      vesselId: null,
      clientVisible: true,
      vesselVisible: true,
      vesselBelongsToClient: null,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe("no_candidates");
  });

  it("blocks proposal when client is not visible", () => {
    const result = resolveLinkProposal({
      clientId: "client-hidden",
      vesselId: null,
      clientVisible: false,
      vesselVisible: true,
      vesselBelongsToClient: null,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe("client_invisible");
  });

  it("blocks proposal when vessel is not visible", () => {
    const result = resolveLinkProposal({
      clientId: null,
      vesselId: "vessel-hidden",
      clientVisible: true,
      vesselVisible: false,
      vesselBelongsToClient: null,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe("vessel_invisible");
  });

  it("blocks proposal when vessel does not belong to the proposed client", () => {
    const result = resolveLinkProposal({
      clientId: "client-a",
      vesselId: "vessel-b",
      clientVisible: true,
      vesselVisible: true,
      vesselBelongsToClient: false,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe("vessel_mismatch");
  });

  it("accepts a valid client+vessel proposal", () => {
    const result = resolveLinkProposal({
      clientId: "client-a",
      vesselId: "vessel-a",
      clientVisible: true,
      vesselVisible: true,
      vesselBelongsToClient: true,
    });
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.proposal.client_id).toBe("client-a");
      expect(result.proposal.vessel_id).toBe("vessel-a");
    }
  });

  it("accepts a client-only proposal", () => {
    const result = resolveLinkProposal({
      clientId: "client-a",
      vesselId: null,
      clientVisible: true,
      vesselVisible: true,
      vesselBelongsToClient: null,
    });
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.proposal.client_id).toBe("client-a");
      expect(result.proposal.vessel_id).toBeNull();
    }
  });
});

describe("AI Operator - cancel draft policy", () => {
  it("allows cancel from draft status without pending actions", () => {
    expect(evaluateCancelDraft({ draftStatus: "draft", pendingOpenCount: 0 }).ok).toBe(true);
  });

  it("allows cancel from awaiting_info status without pending actions", () => {
    expect(evaluateCancelDraft({ draftStatus: "awaiting_info", pendingOpenCount: 0 }).ok).toBe(
      true
    );
  });

  it("blocks cancel from approved status", () => {
    const result = evaluateCancelDraft({ draftStatus: "approved", pendingOpenCount: 0 });
    expect(result.ok).toBe(false);
    if (!result.ok && result.reason === "invalid_status") {
      expect(result.currentStatus).toBe("approved");
      expect(result.status).toBe(409);
    }
  });

  it("blocks cancel from rejected/converted/awaiting_approval status", () => {
    for (const status of ["rejected", "converted", "awaiting_approval"]) {
      const result = evaluateCancelDraft({ draftStatus: status, pendingOpenCount: 0 });
      expect(result.ok).toBe(false);
      if (!result.ok && result.reason === "invalid_status") {
        expect(result.currentStatus).toBe(status);
      }
    }
  });

  it("blocks cancel when there is at least one pending action open", () => {
    const result = evaluateCancelDraft({ draftStatus: "draft", pendingOpenCount: 1 });
    expect(result.ok).toBe(false);
    if (!result.ok && result.reason === "pending_actions_open") {
      expect(result.openCount).toBe(1);
      expect(result.status).toBe(409);
    }
  });

  it("returns not_found when status is null", () => {
    const result = evaluateCancelDraft({ draftStatus: null, pendingOpenCount: 0 });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.reason).toBe("not_found");
      expect(result.status).toBe(404);
    }
  });
});
