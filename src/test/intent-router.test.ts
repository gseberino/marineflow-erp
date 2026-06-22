import { describe, it, expect } from "vitest";
import { routeIntent } from "../../supabase/functions/ai-operator-gateway/intent-router.ts";

describe("intent-router — back-office (resolve sem LLM)", () => {
  it("criar orçamento para cliente", () => {
    const r = routeIntent("Criar orçamento para o cliente João Marina Azul");
    expect(r.kind).toBe("create_quote");
    expect(r.confidence).toBeGreaterThanOrEqual(0.8);
    expect(r.params.client).toContain("joao");
  });

  it("orçamento sem acento também casa", () => {
    const r = routeIntent("monte um orcamento novo");
    expect(r.kind).toBe("create_quote");
  });

  it("abrir nova OS", () => {
    const r = routeIntent("abrir uma nova OS para o cliente Pedro");
    expect(r.kind).toBe("create_service_order");
    expect(r.params.client).toContain("pedro");
  });

  it("buscar cliente", () => {
    const r = routeIntent("buscar cliente Ana Paula");
    expect(r.kind).toBe("search_client");
    expect(r.params.query).toContain("ana");
  });

  it("localizar embarcação", () => {
    const r = routeIntent("localizar embarcação Esmeralda");
    expect(r.kind).toBe("search_vessel");
  });

  it("buscar produto", () => {
    const r = routeIntent("procurar produto bateria 100ah");
    expect(r.kind).toBe("search_product");
  });
});

describe("intent-router — saída (vai pro motor de regras)", () => {
  it("enviar orçamento ao cliente", () => {
    const r = routeIntent("envie o orçamento para o cliente no whatsapp");
    expect(r.kind).toBe("send_to_client");
    expect(r.confidence).toBeGreaterThanOrEqual(0.8);
  });

  it("mandar cobrança", () => {
    const r = routeIntent("mandar cobrança via whatsapp");
    expect(r.kind).toBe("send_to_client");
  });
});

describe("intent-router — escala para o LLM", () => {
  it("texto ambíguo → unknown", () => {
    const r = routeIntent("o cliente reclamou que o motor faz um barulho estranho, o que pode ser?");
    expect(r.kind).toBe("unknown");
    expect(r.confidence).toBe(0);
  });

  it("vazio → unknown", () => {
    expect(routeIntent("   ").kind).toBe("unknown");
  });
});
