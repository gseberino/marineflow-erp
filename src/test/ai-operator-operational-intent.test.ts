import { describe, expect, it } from "vitest";
// @ts-ignore Vitest resolve .ts
import {
  classifyMessage,
  detectExistingDraftReference,
  detectOperationalIntent,
  buildBootstrapDraft,
} from "../../supabase/functions/ai-operator-core/operational-intent.ts";

describe("AI Operator - operational intent bootstrap", () => {
  it("detects quote intent for a clear Raymarine installation request", () => {
    const result = detectOperationalIntent(
      "Tenho um cliente que precisa de um orçamento para instalação de uma nova tela da Raymarine no fly."
    );

    expect(result).toMatchObject({
      kind: "quote",
      category: "marine_electronics",
      shouldBootstrapDraft: true,
      status: "awaiting_info",
    });
  });

  it("detects diagnosis intent for a technical failure report", () => {
    const result = detectOperationalIntent(
      "Preciso de um diagnóstico para uma passarela Besenzoni com falha intermitente."
    );

    expect(result).toMatchObject({
      kind: "diagnosis",
      shouldBootstrapDraft: true,
      status: "awaiting_info",
    });
  });

  it("does not bootstrap a casual greeting without operational intent", () => {
    const result = detectOperationalIntent("Bom dia, tudo bem?");

    expect(result).toBeNull();
  });

  it("builds an awaiting_info Raymarine bootstrap draft with pending questions and preliminary items", () => {
    const intent = detectOperationalIntent(
      "Tenho um cliente que precisa de um orçamento para instalação de uma nova tela da Raymarine no fly. Considere mão de obra, rede de comunicação auxiliar, cabos necessários, alimentação de energia, deslocamento e verifique se existem equipamentos antigos ou incompatíveis com a nova tela."
    );

    expect(intent).not.toBeNull();
    const draft = buildBootstrapDraft(intent!, {
      message:
        "Tenho um cliente que precisa de um orçamento para instalação de uma nova tela da Raymarine no fly. Considere mão de obra, rede de comunicação auxiliar, cabos necessários, alimentação de energia, deslocamento e verifique se existem equipamentos antigos ou incompatíveis com a nova tela.",
    });

    expect(draft.kind).toBe("quote");
    expect(draft.status).toBe("awaiting_info");
    expect(draft.title).toMatch(/Raymarine/i);
    expect(draft.pending_questions.length).toBeGreaterThan(0);
    expect(draft.items.map((item) => item.item_kind)).toEqual(
      expect.arrayContaining(["service", "displacement", "engineering", "risk"])
    );
  });
});

describe("AI Operator - existing draft reference detection", () => {
  it("flags 'vincule esse rascunho' as operate_on_existing", () => {
    const ref = detectExistingDraftReference(
      "Vincule esse rascunho do orçamento do Célio à embarcação do Andoca."
    );
    expect(ref).not.toBeNull();
    expect(ref?.kind).toBe("link");
    expect(ref?.matched).toEqual(expect.arrayContaining(["link"]));
  });

  it("flags 'aquele orcamento' as operate_on_existing", () => {
    const ref = detectExistingDraftReference("Quero continuar aquele orçamento que fizemos ontem.");
    expect(ref).not.toBeNull();
    expect(ref?.matched).toEqual(expect.arrayContaining(["anaphora"]));
  });

  it("flags 'cancele o rascunho criado errado' as cancel reference", () => {
    const ref = detectExistingDraftReference("Pode cancelar o rascunho criado por engano agora.");
    expect(ref).not.toBeNull();
    expect(ref?.kind).toBe("cancel");
  });

  it("flags 'localize o orcamento do Celio' via ownership pattern", () => {
    const ref = detectExistingDraftReference("Localize o orçamento do Célio para mim.");
    expect(ref).not.toBeNull();
    expect(ref?.matched).toEqual(expect.arrayContaining(["lookup"]));
  });

  it("does not flag a clean new demand", () => {
    const ref = detectExistingDraftReference(
      "Preciso de um orçamento para instalação de uma nova tela Raymarine no fly."
    );
    expect(ref).toBeNull();
  });

  it("does not flag 'crie um rascunho' as existing reference (rascunho token alone)", () => {
    const ref = detectExistingDraftReference("Crie um rascunho para esse caso novo.");
    expect(ref).toBeNull();
  });
});

describe("AI Operator - classifyMessage determinism", () => {
  it("classifies clean operational request as new_demand", () => {
    const result = classifyMessage(
      "Preciso de um orçamento para instalação de uma nova tela Raymarine Axiom 12 no fly."
    );
    expect(result.type).toBe("new_demand");
    if (result.type === "new_demand") {
      expect(result.intent.kind).toBe("quote");
    }
  });

  it("classifies 'vincule o rascunho do Celio a embarcacao Andoca' as operate_on_existing even though it cites 'orcamento'-adjacent terms", () => {
    const result = classifyMessage(
      "Pegue o rascunho do orçamento do Célio e vincule à embarcação do Andoca."
    );
    expect(result.type).toBe("operate_on_existing");
  });

  it("classifies 'cancele o rascunho criado errado' as operate_on_existing", () => {
    const result = classifyMessage("Cancele o rascunho criado errado agora.");
    expect(result.type).toBe("operate_on_existing");
  });

  it("classifies 'continue aquele rascunho da Raymarine' as operate_on_existing", () => {
    const result = classifyMessage("Continue aquele rascunho da Raymarine que estávamos tratando.");
    expect(result.type).toBe("operate_on_existing");
  });

  it("classifies a vague greeting as none", () => {
    const result = classifyMessage("Bom dia! Como vai?");
    expect(result.type).toBe("none");
  });

  it("classifies a message containing both reference verb and orcamento as operate_on_existing (reference wins over bootstrap)", () => {
    const result = classifyMessage(
      "Abra o orçamento que fizemos para o Célio e prepare o vínculo com a embarcação Andoca."
    );
    expect(result.type).toBe("operate_on_existing");
  });

  it("classifies a clear noun-form demand ('nova tela Raymarine') as new_demand", () => {
    const result = classifyMessage(
      "Cliente quer uma nova tela Raymarine Axiom 12 no fly da embarcação para diagnóstico."
    );
    expect(result.type).toBe("new_demand");
  });
});
