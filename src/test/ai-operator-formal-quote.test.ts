import { describe, expect, it } from "vitest";
// @ts-ignore Vitest resolve .ts
import {
  buildDraftGroundingSnapshotNote,
  buildExternalQuoteFormalizationProposal,
  buildGroundedInformationalResponse,
  determineExternalQuoteInitialStatus,
  evaluateExternalQuoteFormalization,
  mapDraftItemsToExternalQuoteRows,
} from "../../supabase/functions/ai-operator-core/formal-quote.ts";

const baseDraft = {
  id: "draft-raymarine",
  title: "Orcamento: Instalacao Raymarine Axiom 12 no Fly",
  kind: "quote",
  status: "awaiting_info",
  summary: "Instalacao de nova tela no fly.",
  client_id: "client-celio",
  vessel_id: "vessel-dondoka",
  client_name: "CELIO YUDI SHIOKAWA JUNIOR",
  vessel_name: "Dondoka",
  converted_service_order_id: null,
  external_quote_id: null,
  service_order_id: null,
  pending_questions: [
    "Confirmar modelo exato da tela.",
    "Confirmar equipamentos legados.",
    "Confirmar trajeto para deslocamento.",
    "Confirmar disponibilidade para visita tecnica.",
  ],
};

const draftItems = [
  {
    id: "item-service",
    item_kind: "service",
    service_id: null,
    product_id: null,
    description: "Instalacao e configuracao da tela Raymarine",
    notes: "Inclui testes basicos.",
    quantity: 1,
    unit: "servico",
    unit_price: 1200,
    estimated_total: 1200,
    position: 1,
  },
  {
    id: "item-product",
    item_kind: "product",
    service_id: null,
    product_id: "product-known",
    description: "Cabo de alimentacao dimensionado",
    notes: null,
    quantity: 2,
    unit: "un",
    unit_price: 100,
    estimated_total: 200,
    position: 2,
  },
  {
    id: "item-to-quote",
    item_kind: "product_to_quote",
    service_id: null,
    product_id: null,
    description: "Raymarine Axiom 12",
    notes: "A cotar com fornecedor.",
    quantity: 1,
    unit: "un",
    unit_price: null,
    estimated_total: null,
    position: 3,
  },
  {
    id: "item-question",
    item_kind: "pending_question",
    service_id: null,
    product_id: null,
    description: "Confirmar se ha rede NMEA 2000 existente.",
    notes: null,
    quantity: 1,
    unit: "unit",
    unit_price: null,
    estimated_total: null,
    position: 4,
  },
];

describe("AI Operator - grounded draft snapshot", () => {
  it("states the persisted status and supersedes incompatible historic messages", () => {
    const note = buildDraftGroundingSnapshotNote({
      draft: baseDraft,
      itemCount: 12,
      pendingQuestionCount: 4,
      openActionCount: 0,
      formalQuote: null,
      officialServiceOrder: null,
    });

    expect(note).toMatch(/fonte de verdade/i);
    expect(note).toMatch(/Status atual persistido: awaiting_info/i);
    expect(note).toMatch(/nao ha orcamento formal/i);
    expect(note).toMatch(/nao ha Ordem de Servico oficial/i);
    expect(note).toMatch(/mensagens historicas incompatíveis foram supersedidas/i);
    expect(note).not.toMatch(/aprovado pelo cliente/i);
  });

  it("answers informational questions from persisted state instead of historic approval claims", () => {
    const response = buildGroundedInformationalResponse({
      draft: baseDraft,
      itemCount: 12,
      pendingQuestionCount: 4,
      formalQuote: null,
      officialServiceOrder: null,
    });

    expect(response).toMatch(/awaiting_info/);
    expect(response).toMatch(/Ainda nao existe orcamento formal/i);
    expect(response).toMatch(/Nenhuma OS oficial foi criada/i);
    expect(response).toMatch(/4 pergunta/);
    expect(response).not.toMatch(/aprovado pelo cliente/i);
  });
});

describe("AI Operator - external quote formalization policy", () => {
  it("allows an awaiting_info quote draft with linked client, linked vessel and items", () => {
    const result = evaluateExternalQuoteFormalization({
      draft: baseDraft,
      itemCount: draftItems.length,
      existingExternalQuoteId: null,
      latestUserMessage: "Formalize este rascunho como orçamento no ERP.",
    });

    expect(result).toMatchObject({ ok: true });
  });

  it("blocks informational questions before creating a formalization proposal", () => {
    const result = evaluateExternalQuoteFormalization({
      draft: baseDraft,
      itemCount: draftItems.length,
      existingExternalQuoteId: null,
      latestUserMessage: "Qual o procedimento correto para transformar este rascunho em orçamento formal?",
    });

    expect(result).toMatchObject({
      ok: false,
      reason: "informational_request",
    });
  });

  it("blocks duplicate formalization when a quote already exists", () => {
    const result = evaluateExternalQuoteFormalization({
      draft: { ...baseDraft, external_quote_id: "quote-existing" },
      itemCount: draftItems.length,
      existingExternalQuoteId: "quote-existing",
      latestUserMessage: "Formalize este rascunho como orçamento no ERP.",
    });

    expect(result).toMatchObject({
      ok: false,
      reason: "already_formalized",
      existingExternalQuoteId: "quote-existing",
    });
  });

  it("blocks non-quote drafts and quote drafts without entity links", () => {
    expect(
      evaluateExternalQuoteFormalization({
        draft: { ...baseDraft, kind: "diagnosis" },
        itemCount: draftItems.length,
        existingExternalQuoteId: null,
        latestUserMessage: "Formalize este rascunho como orçamento no ERP.",
      })
    ).toMatchObject({ ok: false, reason: "not_quote_draft" });

    expect(
      evaluateExternalQuoteFormalization({
        draft: { ...baseDraft, client_id: null },
        itemCount: draftItems.length,
        existingExternalQuoteId: null,
        latestUserMessage: "Formalize este rascunho como orçamento no ERP.",
      })
    ).toMatchObject({ ok: false, reason: "missing_entity_link" });
  });

  it("selects pending_product when there are items to quote or unanswered questions", () => {
    expect(determineExternalQuoteInitialStatus({ pendingItemCount: 1, pendingQuestionCount: 0 })).toBe(
      "pending_product"
    );
    expect(determineExternalQuoteInitialStatus({ pendingItemCount: 0, pendingQuestionCount: 4 })).toBe(
      "pending_product"
    );
    expect(determineExternalQuoteInitialStatus({ pendingItemCount: 0, pendingQuestionCount: 0 })).toBe("draft");
  });

  it("builds a human confirmation proposal without execution side effects", () => {
    const proposal = buildExternalQuoteFormalizationProposal({
      draft: baseDraft,
      items: draftItems,
    });

    expect(proposal).toMatchObject({
      draft_id: "draft-raymarine",
      client_name: "CELIO YUDI SHIOKAWA JUNIOR",
      vessel_name: "Dondoka",
      item_count: 4,
      pending_item_count: 1,
      pending_questions_count: 4,
      initial_status: "pending_product",
      effects: {
        creates_external_quote: true,
        creates_service_order: false,
        sends_whatsapp: false,
        changes_stock: false,
        changes_financials: false,
        changes_schedule: false,
      },
    });
  });
});

describe("AI Operator - draft items to formal quote mapping", () => {
  it("maps services and products into separate formal quote rows without inventing prices", () => {
    const mapped = mapDraftItemsToExternalQuoteRows(draftItems);

    expect(mapped.services).toHaveLength(1);
    expect(mapped.services[0]).toMatchObject({
      service_name_snapshot: "Instalacao e configuracao da tela Raymarine",
      unit_price_snapshot: 1200,
      line_total: 1200,
    });

    expect(mapped.parts).toHaveLength(2);
    expect(mapped.parts[0]).toMatchObject({
      product_id: "product-known",
      product_name_snapshot: "Cabo de alimentacao dimensionado",
      unit_sale_snapshot: 100,
      line_total_sale: 200,
    });
    expect(mapped.parts[1]).toMatchObject({
      product_id: null,
      product_name_snapshot: "Raymarine Axiom 12",
      unit_sale_snapshot: 0,
      line_total_sale: 0,
    });
    expect(mapped.parts[1].notes).toMatch(/pendente de cotacao/i);
    expect(mapped.nonBillableNotes.join("\n")).toMatch(/Confirmar se ha rede NMEA 2000/i);
    expect(mapped.knownGrandTotal).toBe(1400);
    expect(mapped.pendingItemCount).toBe(1);
  });
});
