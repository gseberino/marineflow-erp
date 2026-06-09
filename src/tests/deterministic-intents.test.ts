import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
// @ts-ignore Vitest resolve .ts
import {
  detectSOQueryIntent,
  formatSODeterministicResponse,
  tryFastPathResponse,
} from "../../supabase/functions/ai-agent/deterministic-intents.ts";
// @ts-ignore Vitest resolve .ts
import { classifyAIProviderError } from "../../supabase/functions/_shared/ai-error.ts";

// ---------------------------------------------------------------------------
// Mock Supabase builder
// ---------------------------------------------------------------------------
function makeMockSb(tableData: Record<string, any>) {
  return {
    from: (table: string) => {
      const chain: any = {
        select: () => chain,
        eq: () => chain,
        maybeSingle: vi.fn().mockResolvedValue({
          data: tableData[table] ?? null,
          error: null,
        }),
        then: (resolve: any, reject?: any) =>
          Promise.resolve({ data: tableData[table] ?? [], error: null }).then(
            resolve,
            reject
          ),
        catch: (reject: any) =>
          Promise.resolve({ data: tableData[table] ?? [], error: null }).catch(
            reject
          ),
      };
      return chain;
    },
  };
}

const MOCK_SO = {
  id: "so-uuid-1",
  service_order_number: "OS-2026-001",
  status: "draft",
  grand_total: 1500,
  discount_amount: 0,
  clients: { full_name_or_company_name: "João Silva" },
  vessels: { boat_name: "Esmeralda" },
};

const MOCK_SERVICES = [
  {
    service_name_snapshot: "Troca de bateria",
    quantity: 1,
    unit_price_snapshot: 1500,
    line_total: 1500,
  },
];

const MOCK_PARTS = [
  {
    products: { product_name: "Bateria 100Ah" },
    quantity: 1,
    line_total_sale: 800,
  },
];

// ---------------------------------------------------------------------------
// detectSOQueryIntent — pattern matching
// ---------------------------------------------------------------------------
describe("detectSOQueryIntent", () => {
  it("returns so_total for 'qual o valor desta OS?'", () => {
    expect(
      detectSOQueryIntent("qual o valor desta OS?", "service_order", "uuid-1")
    ).toBe("so_total");
  });

  it("returns so_total for 'qual o total?'", () => {
    expect(
      detectSOQueryIntent("qual o total?", "service_order", "uuid-1")
    ).toBe("so_total");
  });

  it("returns so_total for 'qual o preço?'", () => {
    expect(
      detectSOQueryIntent("qual o preço?", "service_order", "uuid-1")
    ).toBe("so_total");
  });

  it("returns so_status for 'qual o status desta OS?'", () => {
    expect(
      detectSOQueryIntent("qual o status desta OS?", "service_order", "uuid-1")
    ).toBe("so_status");
  });

  it("returns so_status for 'qual o estado desta OS?'", () => {
    expect(
      detectSOQueryIntent("qual o estado desta OS?", "service_order", "uuid-1")
    ).toBe("so_status");
  });

  it("returns so_client for 'qual o cliente desta OS?'", () => {
    expect(
      detectSOQueryIntent("qual o cliente desta OS?", "service_order", "uuid-1")
    ).toBe("so_client");
  });

  it("returns so_items for 'quais os itens desta OS?'", () => {
    expect(
      detectSOQueryIntent("quais os itens desta OS?", "service_order", "uuid-1")
    ).toBe("so_items");
  });

  it("returns so_items for 'quais as peças?'", () => {
    expect(
      detectSOQueryIntent("quais as peças?", "service_order", "uuid-1")
    ).toBe("so_items");
  });

  it("returns so_items for 'quais os serviços?'", () => {
    expect(
      detectSOQueryIntent("quais os serviços?", "service_order", "uuid-1")
    ).toBe("so_items");
  });

  it("returns so_vessel for 'qual a embarcação desta OS?'", () => {
    expect(
      detectSOQueryIntent(
        "qual a embarcação desta OS?",
        "service_order",
        "uuid-1"
      )
    ).toBe("so_vessel");
  });

  it("returns so_vessel for 'qual o barco?'", () => {
    expect(
      detectSOQueryIntent("qual o barco?", "service_order", "uuid-1")
    ).toBe("so_vessel");
  });

  // --- null cases ---

  it("returns null when entityId is absent — leaves disambiguation to AI", () => {
    expect(
      detectSOQueryIntent("qual o valor desta OS?", "service_order", null)
    ).toBeNull();
  });

  it("returns null when entityId is undefined", () => {
    expect(
      detectSOQueryIntent("qual o valor desta OS?", "service_order", undefined)
    ).toBeNull();
  });

  it("returns null when entityType is not service_order", () => {
    expect(
      detectSOQueryIntent("qual o valor desta OS?", "client", "uuid-1")
    ).toBeNull();
  });

  it("returns null for message with write verb 'crie'", () => {
    expect(
      detectSOQueryIntent(
        "crie uma OS com valor de 1500",
        "service_order",
        "uuid-1"
      )
    ).toBeNull();
  });

  it("returns null for message with write verb 'adicione'", () => {
    expect(
      detectSOQueryIntent(
        "adicione um serviço de R$ 200 e qual o valor?",
        "service_order",
        "uuid-1"
      )
    ).toBeNull();
  });

  it("returns null when message exceeds 200 characters", () => {
    const long = "qual o valor desta OS? ".repeat(12);
    expect(
      detectSOQueryIntent(long, "service_order", "uuid-1")
    ).toBeNull();
  });

  it("returns null when message references an explicit OS number", () => {
    expect(
      detectSOQueryIntent(
        "qual o valor da OS-2026-123?",
        "service_order",
        "uuid-1"
      )
    ).toBeNull();
  });

  it("returns null for unrecognized pattern (greeting)", () => {
    expect(
      detectSOQueryIntent("bom dia", "service_order", "uuid-1")
    ).toBeNull();
  });

  it("returns null for generic question not about SO fields", () => {
    expect(
      detectSOQueryIntent(
        "quanto tempo leva para concluir?",
        "service_order",
        "uuid-1"
      )
    ).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// formatSODeterministicResponse — output formatting
// ---------------------------------------------------------------------------
describe("formatSODeterministicResponse", () => {
  const soDataWithServices = {
    service_order: {
      service_order_number: "OS-2026-001",
      status: "draft",
      grand_total: 1500,
      discount_amount: 0,
      cliente: "João Silva",
      embarcacao: "Esmeralda",
    },
    parts: [] as any[],
    services: [
      {
        servico: "Troca de bateria",
        quantidade: 1,
        preco_unitario: 1500,
        total: 1500,
      },
    ],
  };

  it("formats so_total with service total — includes OS number, client, vessel, and Total row", () => {
    const result = formatSODeterministicResponse("so_total", soDataWithServices);
    expect(result).toContain("OS-2026-001");
    expect(result).toContain("João Silva");
    expect(result).toContain("Esmeralda");
    expect(result).toContain("Total");
    expect(result).toContain("Serviços");
  });

  it("formats so_total — does not include Peças row when parts are empty", () => {
    const result = formatSODeterministicResponse("so_total", soDataWithServices);
    expect(result).not.toContain("| Peças |");
  });

  it("formats so_total — includes Desconto row when discount > 0", () => {
    const withDiscount = {
      ...soDataWithServices,
      service_order: { ...soDataWithServices.service_order, discount_amount: 100 },
    };
    const result = formatSODeterministicResponse("so_total", withDiscount);
    expect(result).toContain("Desconto");
  });

  it("formats so_status with Portuguese label for 'draft'", () => {
    const result = formatSODeterministicResponse("so_status", soDataWithServices);
    expect(result).toContain("OS-2026-001");
    expect(result).toContain("Rascunho");
  });

  it("formats so_status for each known status code", () => {
    const statuses: Record<string, string> = {
      open: "Aberta",
      in_progress: "Em andamento",
      completed: "Concluída",
      cancelled: "Cancelada",
    };
    for (const [code, label] of Object.entries(statuses)) {
      const data = {
        ...soDataWithServices,
        service_order: { ...soDataWithServices.service_order, status: code },
      };
      expect(formatSODeterministicResponse("so_status", data)).toContain(label);
    }
  });

  it("formats so_client with client name", () => {
    const result = formatSODeterministicResponse("so_client", soDataWithServices);
    expect(result).toContain("OS-2026-001");
    expect(result).toContain("João Silva");
  });

  it("formats so_items with service list", () => {
    const result = formatSODeterministicResponse("so_items", soDataWithServices);
    expect(result).toContain("Troca de bateria");
    expect(result).toContain("Serviços");
  });

  it("formats so_items with parts list", () => {
    const withParts = {
      ...soDataWithServices,
      parts: [{ produto: "Bateria 100Ah", quantidade: 1, total: 800 }],
    };
    const result = formatSODeterministicResponse("so_items", withParts);
    expect(result).toContain("Bateria 100Ah");
    expect(result).toContain("Peças");
  });

  it("formats so_items — returns empty message when no items", () => {
    const empty = {
      service_order: { service_order_number: "OS-2026-002" },
      parts: [] as any[],
      services: [] as any[],
    };
    const result = formatSODeterministicResponse("so_items", empty);
    expect(result).toContain("não possui itens");
  });

  it("formats so_vessel with vessel name", () => {
    const result = formatSODeterministicResponse("so_vessel", soDataWithServices);
    expect(result).toContain("OS-2026-001");
    expect(result).toContain("Esmeralda");
  });
});

// ---------------------------------------------------------------------------
// tryFastPathResponse — provider call guard
// ---------------------------------------------------------------------------
describe("tryFastPathResponse — no provider call when fast-path resolves", () => {
  let fetchSpy: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    fetchSpy = vi.fn();
    vi.stubGlobal("fetch", fetchSpy);
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("returns formatted string and does NOT call fetch for 'qual o valor'", async () => {
    const sb = makeMockSb({
      service_orders: MOCK_SO,
      service_order_parts: [],
      service_order_services: MOCK_SERVICES,
    });
    const incoming = [{ role: "user", content: "qual o valor desta OS?" }];
    const context = { entityType: "service_order", entityId: "so-uuid-1" };

    const result = await tryFastPathResponse(incoming, context, sb);

    expect(result).not.toBeNull();
    expect(result).toContain("OS-2026-001");
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("includes client and vessel in the total response", async () => {
    const sb = makeMockSb({
      service_orders: MOCK_SO,
      service_order_parts: [],
      service_order_services: MOCK_SERVICES,
    });
    const result = await tryFastPathResponse(
      [{ role: "user", content: "qual o total?" }],
      { entityType: "service_order", entityId: "so-uuid-1" },
      sb
    );
    expect(result).toContain("João Silva");
    expect(result).toContain("Esmeralda");
  });

  it("returns null when entityId is absent — no fast-path, no provider call", async () => {
    const sb = makeMockSb({ service_orders: MOCK_SO });
    const incoming = [{ role: "user", content: "qual o valor desta OS?" }];
    const context = { entityType: "service_order" }; // no entityId

    const result = await tryFastPathResponse(incoming, context, sb);

    expect(result).toBeNull();
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("returns null for write command — fast-path skipped, Gemini path not blocked", async () => {
    const sb = makeMockSb({ service_orders: MOCK_SO });
    const incoming = [
      { role: "user", content: "crie um novo orçamento para o João" },
    ];
    const context = { entityType: "service_order", entityId: "so-uuid-1" };

    const result = await tryFastPathResponse(incoming, context, sb);

    expect(result).toBeNull();
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("handles so_status query correctly", async () => {
    const sb = makeMockSb({
      service_orders: MOCK_SO,
      service_order_parts: [],
      service_order_services: [],
    });
    const result = await tryFastPathResponse(
      [{ role: "user", content: "qual o status desta OS?" }],
      { entityType: "service_order", entityId: "so-uuid-1" },
      sb
    );
    expect(result).not.toBeNull();
    expect(result).toContain("Rascunho");
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("returns null when DB returns no OS — falls through to Gemini", async () => {
    const sb = makeMockSb({ service_orders: null });
    const result = await tryFastPathResponse(
      [{ role: "user", content: "qual o valor desta OS?" }],
      { entityType: "service_order", entityId: "so-uuid-1" },
      sb
    );
    expect(result).toBeNull();
  });

  it("uses last user message from conversation history", async () => {
    const sb = makeMockSb({
      service_orders: MOCK_SO,
      service_order_parts: MOCK_PARTS,
      service_order_services: [],
    });
    const incoming = [
      { role: "user", content: "oi" },
      { role: "assistant", content: "Olá! Como posso ajudar?" },
      { role: "user", content: "quais as peças desta OS?" },
    ];
    const result = await tryFastPathResponse(
      incoming,
      { entityType: "service_order", entityId: "so-uuid-1" },
      sb
    );
    expect(result).not.toBeNull();
    expect(result).toContain("Bateria 100Ah");
    expect(fetchSpy).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// Rate limit classification still correct (regression guard)
// ---------------------------------------------------------------------------
describe("rate limit classification — regression guard", () => {
  it("classifies 429 as rate_limit", () => {
    expect(classifyAIProviderError(429, "")).toBe("rate_limit");
  });

  it("classifies 429 with body as rate_limit", () => {
    expect(classifyAIProviderError(429, "rate limit exceeded")).toBe("rate_limit");
  });

  it("rate_limit is distinct from provider_overloaded", () => {
    expect(classifyAIProviderError(429, "")).not.toBe("provider_overloaded");
    expect(classifyAIProviderError(503, "overloaded")).not.toBe("rate_limit");
  });
});
