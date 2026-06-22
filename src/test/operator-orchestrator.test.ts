import { describe, it, expect, vi } from "vitest";
import {
  handleOperatorTurn,
  type OperatorDeps,
} from "../../supabase/functions/ai-operator-gateway/orchestrator.ts";
import {
  DEFAULT_POLICY_CONFIG,
  type OutboundAction,
  type PolicyContext,
} from "../../supabase/functions/_shared/outbound-policy/index.ts";

const deps = (over: Partial<OperatorDeps> = {}): OperatorDeps => ({
  policy: { ...DEFAULT_POLICY_CONFIG },
  ...over,
});

describe("orchestrator — invariante de segurança", () => {
  it("NUNCA executa escrita (executedWrite sempre false)", async () => {
    for (const text of [
      "criar orçamento para o cliente João",
      "abrir nova OS para Pedro",
      "buscar cliente Ana",
      "enviar orçamento ao cliente no whatsapp",
      "texto aleatório ambíguo",
    ]) {
      const r = await handleOperatorTurn({ text }, deps());
      expect(r.executedWrite).toBe(false);
    }
  });
});

describe("orchestrator — planos por intenção", () => {
  it("busca → plano read", async () => {
    const r = await handleOperatorTurn({ text: "buscar cliente Ana" }, deps());
    expect(r.plan).toBe("read");
  });

  it("criar orçamento → plano create (não executa)", async () => {
    const r = await handleOperatorTurn(
      { text: "criar orçamento para o cliente João" },
      deps(),
    );
    expect(r.plan).toBe("create");
    expect(r.executedWrite).toBe(false);
  });

  it("send sem detalhes → outbound aguardando dados", async () => {
    const r = await handleOperatorTurn(
      { text: "enviar orçamento ao cliente no whatsapp" },
      deps(),
    );
    expect(r.plan).toBe("outbound");
    expect(r.policyDecision).toBeUndefined();
  });
});

describe("orchestrator — saída passa pelo motor de regras", () => {
  const outboundAction: OutboundAction = {
    type: "send_service_order_link",
    channel: "whatsapp",
    recipient: { phone: "5547999990000", phoneValidated: true, clientId: "c1" },
    content: { text: "Segue seu orçamento." },
    money: { amount: 500 },
    meta: { aiConfidence: 0.95 },
  };
  const outboundContext: PolicyContext = {
    now: new Date("2026-06-15T10:00:00"),
    relationship: "known_client",
    lastSendAt: null,
    isDuplicate: false,
  };

  it("em shadow (default) decide mas não executa", async () => {
    const r = await handleOperatorTurn(
      { text: "enviar orçamento ao cliente", outboundAction, outboundContext },
      deps(),
    );
    expect(r.plan).toBe("outbound");
    expect(r.policyDecision?.shadow).toBe(true);
    // com confirmação do gestor ligada por padrão → needs_approval
    expect(r.policyDecision?.decision).toBe("needs_approval");
    expect(r.executedWrite).toBe(false);
  });
});

describe("orchestrator — fallback LLM só no desconhecido", () => {
  it("intenção clara NÃO chama o LLM (economia de tokens)", async () => {
    const llm = vi.fn(async () => "resposta");
    await handleOperatorTurn({ text: "buscar cliente Ana" }, deps({ llm }));
    expect(llm).not.toHaveBeenCalled();
  });

  it("ambíguo chama o LLM", async () => {
    const llm = vi.fn(async () => "resposta do modelo");
    const r = await handleOperatorTurn(
      { text: "o motor faz um barulho estranho, o que pode ser?" },
      deps({ llm }),
    );
    expect(llm).toHaveBeenCalledOnce();
    expect(r.plan).toBe("llm");
    expect(r.llmText).toBe("resposta do modelo");
  });

  it("ambíguo sem LLM → plano none", async () => {
    const r = await handleOperatorTurn(
      { text: "o motor faz um barulho estranho" },
      deps(),
    );
    expect(r.plan).toBe("none");
  });
});
