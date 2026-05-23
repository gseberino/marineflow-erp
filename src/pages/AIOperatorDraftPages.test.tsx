import { describe, expect, it, vi } from "vitest";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import { AIOperatorDraftCard } from "@/components/ai/AIOperatorDraftCard";
import { AIOperatorLinkProposalCard } from "@/components/ai/AIOperatorLinkProposalCard";
import AIOperatorDraftListPage from "./AIOperatorDraftListPage";
import AIOperatorDraftDetailPage from "./AIOperatorDraftDetailPage";

const draftFixture = {
  id: "6a5a1ba0-789c-403b-a391-8b0fc605e9b7",
  kind: "quote",
  status: "awaiting_info",
  title: "Orcamento: Instalacao Raymarine Axiom 12 no Fly",
  summary: "Escopo preliminar para nova tela no fly.",
  interpreted_intent: "prepare_quote",
  interpreted_category: "marine_electronics",
  estimated_total: null,
  pending_questions: ["Qual e a embarcacao?"],
  next_steps: ["Agendar visita tecnica"],
  hypotheses: ["Pode haver equipamento legado incompativel"],
  created_at: "2026-05-23T09:48:42.140Z",
  updated_at: "2026-05-23T09:48:42.140Z",
  client_id: null,
  vessel_id: null,
  client_name: null,
  vessel_name: null,
  item_count: 12,
};

const draftItemsFixture = [
  {
    id: "item-1",
    draft_id: draftFixture.id,
    item_kind: "service",
    description: "Mao de obra para instalacao",
    notes: "Estimativa inicial",
    quantity: 1,
    unit: "unit",
    estimated_total: 1000,
    position: 1,
  },
  {
    id: "item-2",
    draft_id: draftFixture.id,
    item_kind: "pending_question",
    description: "Qual e a embarcacao?",
    notes: null,
    quantity: 1,
    unit: "unit",
    estimated_total: null,
    position: 2,
  },
];

vi.mock("@/hooks/use-ai-operator-drafts", () => ({
  useAIOperatorDrafts: () => ({
    data: [draftFixture],
    isLoading: false,
    error: null,
  }),
  useAIOperatorDraftDetail: () => ({
    data: {
      draft: draftFixture,
      items: draftItemsFixture,
      pendingActions: [],
      session: {
        id: "session-1",
        created_at: "2026-05-23T09:46:32.344Z",
        last_activity_at: "2026-05-23T09:51:48.384Z",
      },
    },
    isLoading: false,
    error: null,
  }),
  useLinkAIOperatorDraftEntities: () => ({
    mutateAsync: vi.fn(),
    isPending: false,
  }),
  useCancelAIOperatorDraft: () => ({
    mutateAsync: vi.fn(),
    isPending: false,
  }),
}));

vi.mock("@/hooks/use-ai-operator", () => ({
  useAIOperator: () => ({
    sessionId: "session-1",
    display: [],
    loading: false,
    error: null,
    activeDraftId: draftFixture.id,
    activePendingActionId: null,
    messages: [],
    sendMessage: vi.fn(),
    selectDraftCandidate: vi.fn(),
    confirmLinkProposal: vi.fn(),
    rejectLinkProposal: vi.fn(),
    approveAction: vi.fn(),
    rejectAction: vi.fn(),
    reset: vi.fn(),
  }),
}));

vi.mock("@/hooks/use-clients", () => ({
  useClients: () => ({ data: [], isLoading: false }),
}));

vi.mock("@/hooks/use-vessels", () => ({
  useVesselsForClient: () => ({ data: [], isLoading: false }),
}));

vi.mock("@/components/ClientCombobox", () => ({
  ClientCombobox: () => <div>Client combobox mock</div>,
}));

vi.mock("@/components/VesselSelect", () => ({
  VesselSelect: () => <div>Vessel select mock</div>,
}));

vi.mock("@/hooks/use-auth", () => ({
  useAuth: () => ({
    user: { id: "user-1", role: "admin", full_name: "Tester", email: "tester@example.com" },
  }),
}));

function renderWithRouter(ui: React.ReactNode, initialEntries = ["/operator/drafts"]) {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={initialEntries}>{ui}</MemoryRouter>
    </QueryClientProvider>
  );
}

describe("AI Operator draft surfaces", () => {
  it("draft card offers a real navigation path to the persisted detail page with PT label", async () => {
    renderWithRouter(<AIOperatorDraftCard draftId={draftFixture.id} />);

    expect(await screen.findByText(/Orcamento: Instalacao Raymarine Axiom 12 no Fly/i)).toBeInTheDocument();
    expect(screen.getByRole("link", { name: /abrir detalhes do rascunho/i })).toHaveAttribute(
      "href",
      `/operator/drafts/${draftFixture.id}`
    );
    expect(screen.queryByText(draftFixture.id)).not.toBeInTheDocument();
    // PT status label, not raw "awaiting_info".
    expect(screen.getByText(/Aguardando informações/i)).toBeInTheDocument();
  });

  it("list page shows persisted drafts with PT labels and an 'Abrir detalhes' action", async () => {
    renderWithRouter(<AIOperatorDraftListPage />);

    expect(await screen.findByText(/Rascunhos do Operador/i)).toBeInTheDocument();
    expect(screen.getByText(/Orcamento: Instalacao Raymarine Axiom 12 no Fly/i)).toBeInTheDocument();
    expect(screen.getByText(/Rascunho interno do Operador/i)).toBeInTheDocument();
    expect(screen.getByText(/Cliente não vinculado/i)).toBeInTheDocument();
    expect(screen.getByText(/12 itens/i)).toBeInTheDocument();
    expect(screen.getByRole("link", { name: /abrir detalhes/i })).toBeInTheDocument();
    expect(screen.getByText(/Aguardando informações/i)).toBeInTheDocument();
    // Cancel button exists for cancellable status.
    expect(screen.getByRole("button", { name: /cancelar/i })).toBeInTheDocument();
  });

  it("detail page shows internal warning, draft items and 'Continuar com o Operador' button", async () => {
    renderWithRouter(
      <Routes>
        <Route path="/operator/drafts/:id" element={<AIOperatorDraftDetailPage />} />
      </Routes>,
      [`/operator/drafts/${draftFixture.id}`]
    );

    expect(await screen.findByText(/Rascunho interno do Operador/i)).toBeInTheDocument();
    expect(screen.getByText(/ainda não é uma Ordem de Serviço/i)).toBeInTheDocument();
    expect(screen.getByText(/Mao de obra para instalacao/i)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /continuar com o operador/i })).toBeInTheDocument();
    expect(screen.getByText(/Cliente não vinculado/i)).toBeInTheDocument();
    // Cancel button present for awaiting_info draft without open pending actions.
    expect(screen.getByRole("button", { name: /cancelar rascunho/i })).toBeInTheDocument();
  });

  it("link proposal card shows human names, compatibility and no internal ids", () => {
    render(
      <AIOperatorLinkProposalCard
        proposal={{
          draft_id: "6a5a1ba0-789c-403b-a391-8b0fc605e9b7",
          draft_title: "Orcamento Raymarine",
          client: {
            id: "11111111-1111-4111-8111-111111111111",
            name: "CELIO YUDI SHIOKAWA JUNIOR",
            subtitle: "Cliente individual",
          },
          vessel: {
            id: "22222222-2222-4222-8222-222222222222",
            name: "Dondoka",
            subtitle: "Porfino 35 Fly",
          },
          compatibility: {
            status: "already_linked_to_client",
            message: "Esta embarcacao ja esta cadastrada para este cliente.",
          },
          rationale: null,
        }}
        status="pending"
        onConfirm={vi.fn()}
        onReject={vi.fn()}
      />
    );

    expect(screen.getByText(/CELIO YUDI SHIOKAWA JUNIOR/i)).toBeInTheDocument();
    expect(screen.getByText(/Dondoka/i)).toBeInTheDocument();
    expect(screen.getByText(/Esta embarcacao ja esta cadastrada/i)).toBeInTheDocument();
    expect(screen.queryByText(/11111111-1111-4111-8111-111111111111/)).not.toBeInTheDocument();
    expect(screen.queryByText(/22222222-2222-4222-8222-222222222222/)).not.toBeInTheDocument();
  });
});
