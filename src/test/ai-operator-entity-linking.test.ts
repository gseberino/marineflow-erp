import { describe, expect, it } from "vitest";
// @ts-ignore Vitest resolve .ts
import {
  buildDraftUpdatePatch,
  draftProtectedAuditEventForOperation,
  evaluateCancelDraft,
  evaluateDraftMutationPolicy,
  isDraftStatusOperationallyMutable,
  isDraftStatusProtected,
  resolveCreateDraftStatus,
  resolveEntityLinkByHumanTerms,
  resolveCreateDraftLinks,
  resolveExplicitDraftEntitySelection,
  resolveLinkProposal,
  resolveMemoryCandidateLinks,
  sanitizeToolEventsForFrontend,
} from "../../supabase/functions/ai-operator-core/entity-linking.ts";

describe("AI Operator - central draft mutability policy", () => {
  it("recognizes draft and awaiting_info as mutable operational statuses", () => {
    for (const status of ["draft", "awaiting_info"]) {
      expect(isDraftStatusOperationallyMutable(status)).toBe(true);
      expect(isDraftStatusProtected(status)).toBe(false);
      for (const operation of ["model_add_draft_item", "model_ask_pending_question", "ui_link_entities"] as const) {
        expect(
          evaluateDraftMutationPolicy({
            draftStatus: status,
            operation,
          })
        ).toMatchObject({ ok: true, currentStatus: status, operation });
      }
    }
  });

  it("recognizes governance and terminal statuses as protected", () => {
    for (const status of ["awaiting_approval", "approved", "rejected", "converted", "cancelled"]) {
      expect(isDraftStatusOperationallyMutable(status)).toBe(false);
      expect(isDraftStatusProtected(status)).toBe(true);
      for (const operation of ["model_add_draft_item", "model_ask_pending_question", "ui_link_entities"] as const) {
        expect(
          evaluateDraftMutationPolicy({
            draftStatus: status,
            operation,
          })
        ).toMatchObject({
          ok: false,
          status: 409,
          reason: "draft_current_status_protected",
          currentStatus: status,
          operation,
        });
      }
    }
  });

  it("does not block read-only resume operations for protected drafts", () => {
    expect(
      evaluateDraftMutationPolicy({
        draftStatus: "approved",
        operation: "resume_draft",
      })
    ).toMatchObject({
      ok: true,
      currentStatus: "approved",
      operation: "resume_draft",
    });
  });

  it("blocks add item, pending question and UI link mutations on protected drafts with auditable events", () => {
    const expectations = [
      ["model_add_draft_item", "model_draft_item_blocked_protected_state"],
      ["model_ask_pending_question", "model_draft_question_blocked_protected_state"],
      ["ui_link_entities", "draft_entity_link_blocked_protected_state"],
    ] as const;

    for (const [operation, eventType] of expectations) {
      expect(
        evaluateDraftMutationPolicy({
          draftStatus: "approved",
          operation,
        })
      ).toMatchObject({
        ok: false,
        status: 409,
        reason: "draft_current_status_protected",
        currentStatus: "approved",
        operation,
      });
      expect(draftProtectedAuditEventForOperation(operation)).toBe(eventType);
    }
  });

  it("keeps register_memory_candidate and propose_action outside direct draft-content mutation", () => {
    for (const operation of ["register_memory_candidate", "propose_action"] as const) {
      expect(
        evaluateDraftMutationPolicy({
          draftStatus: "converted",
          operation,
        })
      ).toMatchObject({
        ok: true,
        currentStatus: "converted",
        operation,
      });
    }
  });
});

describe("AI Operator - explicit entity linking policy", () => {
  it("create_draft downgrades model-provided governance statuses to operational statuses", () => {
    for (const status of ["approved", "rejected", "converted", "cancelled", "awaiting_approval"]) {
      const result = resolveCreateDraftStatus(status, false);
      expect(result.status).toBe("draft");
      expect(result.blockedStatus).toBe(status);
    }
  });

  it("create_draft can only use model-provided operational statuses", () => {
    expect(resolveCreateDraftStatus("draft", true)).toEqual({
      status: "draft",
      blockedStatus: null,
    });
    expect(resolveCreateDraftStatus("awaiting_info", false)).toEqual({
      status: "awaiting_info",
      blockedStatus: null,
    });
    expect(resolveCreateDraftStatus(null, true)).toEqual({
      status: "awaiting_info",
      blockedStatus: null,
    });
  });

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
        status: "draft",
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
    expect(result.blockedStatus).toBeNull();
    expect(result.blockedCurrentStatus).toBeNull();
    expect(result.unexpected).toEqual([
      { field: "client_id", value: "client-visible-but-wrong" },
      { field: "vessel_id", value: "vessel-visible-but-wrong" },
      { field: "service_order_id", value: "so-visible-but-wrong" },
      { field: "converted_service_order_id", value: "so-converted-visible-but-wrong" },
    ]);
  });

  it("update_draft blocks governance statuses while preserving safe content changes", () => {
    for (const status of ["approved", "rejected", "converted", "cancelled", "awaiting_approval"]) {
      const result = buildDraftUpdatePatch(
        {
          title: "Novo titulo seguro",
          status,
          summary: "Resumo seguro",
        },
        {
          client_id: "client-confirmed",
          vessel_id: "vessel-confirmed",
          status: "awaiting_info",
        }
      );

      expect(result.patch).toEqual({
        title: "Novo titulo seguro",
        summary: "Resumo seguro",
      });
      expect(result.blockedStatus).toBe(status);
      expect(result.blockedCurrentStatus).toBeNull();
    }
  });

  it("update_draft allows operational drafts to alternate between draft and awaiting_info", () => {
    expect(
      buildDraftUpdatePatch({ status: "awaiting_info", summary: "Aguardando dado" }, { status: "draft" }).patch
    ).toEqual({
      status: "awaiting_info",
      summary: "Aguardando dado",
    });
    expect(
      buildDraftUpdatePatch({ status: "draft", summary: "Escopo refinado" }, { status: "awaiting_info" }).patch
    ).toEqual({
      status: "draft",
      summary: "Escopo refinado",
    });
  });

  it("update_draft blocks every model mutation when current draft status is protected", () => {
    for (const currentStatus of ["awaiting_approval", "approved", "rejected", "converted", "cancelled"]) {
      const result = buildDraftUpdatePatch(
        {
          title: "Nao pode mudar",
          status: "awaiting_info",
          summary: "Nao pode mudar",
          estimated_total: 12345,
          pending_questions: ["Nao persistir"],
          next_steps: ["Nao persistir"],
          hypotheses: ["Nao persistir"],
        },
        {
          client_id: "client-confirmed",
          vessel_id: "vessel-confirmed",
          status: currentStatus,
        }
      );

      expect(result.patch).toEqual({});
      expect(result.blockedCurrentStatus).toBe(currentStatus);
      expect(result.blockedStatus).toBeNull();
    }
  });

  it("update_draft still reports attempted governance status when current draft is protected", () => {
    const result = buildDraftUpdatePatch(
      {
        status: "converted",
        summary: "Nao pode mudar",
      },
      {
        status: "approved",
      }
    );

    expect(result.patch).toEqual({});
    expect(result.blockedCurrentStatus).toBe("approved");
    expect(result.blockedStatus).toBe("converted");
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

describe("AI Operator - human-term entity link resolution", () => {
  const clientCelio = { id: "client-celio", name: "CELIO YUDI SHIOKAWA JUNIOR", type: "individual" };
  const vesselDondoka = {
    id: "vessel-dondoka",
    name: "Dondoka",
    manufacturer: "Porfino",
    model: "Porfino 35 Fly",
    year: 2012,
    client_id: "client-celio",
  };

  it("creates a proposal from human terms without model-provided UUIDs", () => {
    const result = resolveEntityLinkByHumanTerms({
      draftId: "draft-raymarine",
      draftTitle: "Orcamento: Instalacao Raymarine Axiom 12 no Fly",
      clientQuery: "Celio Yudi Shiokawa Junior",
      vesselQuery: "Dondoka",
      clientCandidates: [clientCelio],
      vesselCandidates: [vesselDondoka],
      rationale: "Usuario pediu vinculo do rascunho ativo.",
    });

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.proposal.client).toEqual({
        id: "client-celio",
        name: "CELIO YUDI SHIOKAWA JUNIOR",
        subtitle: "Cliente individual",
      });
      expect(result.proposal.vessel).toEqual({
        id: "vessel-dondoka",
        name: "Dondoka",
        subtitle: "Porfino 35 Fly",
      });
      expect(result.proposal.compatibility).toEqual({
        status: "already_linked_to_client",
        message: "Esta embarcacao ja esta cadastrada para este cliente.",
      });
      expect(result.persisted).toBe(false);
    }
  });

  it("treats Dondoka linked to Celio as compatible, not a false ownership conflict", () => {
    const result = resolveEntityLinkByHumanTerms({
      draftId: "draft-raymarine",
      draftTitle: "Raymarine",
      clientQuery: "Celio",
      vesselQuery: "Dondoka",
      clientCandidates: [clientCelio],
      vesselCandidates: [vesselDondoka],
    });

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.proposal.compatibility.status).toBe("already_linked_to_client");
    }
  });

  it("blocks a true vessel-client mismatch with a specific reason", () => {
    const result = resolveEntityLinkByHumanTerms({
      draftId: "draft-raymarine",
      draftTitle: "Raymarine",
      clientQuery: "Celio",
      vesselQuery: "Dondoka",
      clientCandidates: [clientCelio],
      vesselCandidates: [{ ...vesselDondoka, client_id: "client-other" }],
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.reason).toBe("vessel_mismatch");
      expect(result.message).toMatch(/nao pertence ao cliente/i);
    }
  });

  it("returns selection candidates instead of guessing when client is ambiguous", () => {
    const result = resolveEntityLinkByHumanTerms({
      draftId: "draft-raymarine",
      draftTitle: "Raymarine",
      clientQuery: "Celio",
      vesselQuery: "Dondoka",
      clientCandidates: [
        clientCelio,
        { id: "client-celio-2", name: "CELIO SHIOKAWA", type: "individual" },
      ],
      vesselCandidates: [vesselDondoka],
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.reason).toBe("client_ambiguous");
      expect(result.clientCandidates).toHaveLength(2);
      expect(result.clientCandidates?.[0]).not.toHaveProperty("cpf_cnpj");
      expect(result.clientCandidates?.[0]).not.toHaveProperty("phone");
    }
  });

  it("rejects sanitized placeholders as invalid references without resolving as UUIDs", () => {
    const result = resolveEntityLinkByHumanTerms({
      draftId: "draft-raymarine",
      draftTitle: "Raymarine",
      clientQuery: "[referencia interna oculta]",
      vesselQuery: "Dondoka",
      clientCandidates: [],
      vesselCandidates: [vesselDondoka],
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.reason).toBe("invalid_reference");
    }
  });
});

describe("AI Operator - frontend tool event minimization", () => {
  it("removes raw UUIDs and personal data from tool_events returned to the browser", () => {
    const sanitized = sanitizeToolEventsForFrontend([
      {
        name: "search_clients",
        args: { query: "Celio", client_id: "11111111-1111-4111-8111-111111111111" },
        result: {
          results: [
            {
              id: "22222222-2222-4222-8222-222222222222",
              full_name_or_company_name: "CELIO YUDI SHIOKAWA JUNIOR",
              cpf_cnpj: "123.456.789-10",
              phone: "(11) 99999-9999",
              whatsapp: "(11) 99999-9999",
              email: "cliente@example.com",
            },
          ],
        },
      },
    ]);

    const serialized = JSON.stringify(sanitized);
    expect(serialized).not.toContain("11111111-1111-4111-8111-111111111111");
    expect(serialized).not.toContain("22222222-2222-4222-8222-222222222222");
    expect(serialized).not.toContain("123.456.789-10");
    expect(serialized).not.toContain("99999-9999");
    expect(serialized).not.toContain("cliente@example.com");
    expect(sanitized).toEqual([
      {
        name: "search_clients",
        blocked: false,
        result_summary: { result_count: 1 },
      },
    ]);
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
