import { describe, it, expect } from "vitest";
import {
  scoreCandidate,
  suggestMatches,
  pickAutoApply,
  effectiveTolerance,
  nameOverlap,
  normalizeText,
} from "../../supabase/functions/_shared/banking/matching";
import {
  DEFAULT_MATCH_OPTIONS,
  type BankTx,
  type Candidate,
} from "../../supabase/functions/_shared/banking/types";

const tx = (over: Partial<BankTx> = {}): BankTx => ({
  id: "tx-1",
  transaction_date: "2026-07-15",
  description: "PIX RECEBIDO",
  amount: 6000,
  transaction_type: "credit",
  ...over,
});

const cand = (over: Partial<Candidate> = {}): Candidate => ({
  kind: "receivable",
  id: "c-1",
  label: "Conta a receber",
  amount: 6000,
  direction: "credit",
  dueDate: "2026-07-15",
  ...over,
});

describe("normalização de texto", () => {
  it("remove acentos e pontuação", () => {
    expect(normalizeText("Marina do Sol Ltda.")).toBe("MARINA DO SOL LTDA");
    expect(normalizeText("SERVIÇOS NÁUTICOS")).toBe("SERVICOS NAUTICOS");
    expect(normalizeText("ORÇ-00042")).toBe("ORC 00042");
  });
});

describe("tolerância dupla", () => {
  it("usa o percentual quando ele é menor que o teto", () => {
    // 2% de R$ 1.000 = R$ 20, menor que o teto de R$ 50
    expect(effectiveTolerance(1000, DEFAULT_MATCH_OPTIONS)).toBe(20);
  });

  it("usa o teto absoluto em valores altos", () => {
    // 2% de R$ 20.000 seriam R$ 400 de folga — o teto corta em R$ 50
    expect(effectiveTolerance(20000, DEFAULT_MATCH_OPTIONS)).toBe(50);
  });
});

describe("camada de certeza", () => {
  it("casa pelo identificador do Pix e libera conciliação automática", () => {
    const e2e = "E12345678202607151230ABCDEFGHIJK";
    const s = scoreCandidate(
      tx({ pix_end_to_end_id: e2e, amount: 999 }),
      cand({ pixEndToEndId: e2e, amount: 6000 }),
    );
    expect(s?.tier).toBe("certain");
    expect(s?.autoApply).toBe(true);
    expect(s?.score).toBe(100);
  });

  it("casa por CNPJ do pagador somado a valor exato", () => {
    const s = scoreCandidate(
      tx({ counterparty_document: "12345678000190" }),
      cand({ clientDocument: "12.345.678/0001-90", clientName: "Marina do Sol" }),
    );
    expect(s?.tier).toBe("certain");
    expect(s?.autoApply).toBe(true);
  });

  it("não vira certeza quando o CNPJ bate mas o valor não", () => {
    const s = scoreCandidate(
      tx({ counterparty_document: "12345678000190", amount: 5500 }),
      cand({ clientDocument: "12345678000190", clientName: "Marina do Sol" }),
    );
    expect(s?.autoApply).toBe(false);
    expect(s?.tier).not.toBe("certain");
  });
});

describe("sentido do dinheiro", () => {
  it("não compara entrada com conta a pagar", () => {
    const s = scoreCandidate(tx({ transaction_type: "credit" }), cand({ direction: "debit" }));
    expect(s).toBeNull();
  });
});

describe("pontuação por valor", () => {
  it("descarta candidato com valor muito distante", () => {
    expect(scoreCandidate(tx({ amount: 6000 }), cand({ amount: 1000 }))).toBeNull();
  });

  it("aceita diferença dentro da tolerância e reporta o valor", () => {
    const s = scoreCandidate(tx({ amount: 5970 }), cand({ amount: 6000 }));
    expect(s).not.toBeNull();
    expect(s!.difference).toBe(-30);
    expect(s!.reasons.some((r) => r.signal === "valor")).toBe(true);
  });

  it("relata quando entrou mais do que o esperado (possível juros)", () => {
    const s = scoreCandidate(tx({ amount: 6120 }), cand({ amount: 6000 }));
    expect(s!.difference).toBe(120);
    expect(s!.reasons.find((r) => r.signal === "valor")!.detail).toContain("a mais");
  });
});

describe("nome do cliente no histórico", () => {
  it("reconhece o nome ignorando sufixo societário", () => {
    expect(nameOverlap("Marina do Sol LTDA", "PIX RECEBIDO MARINA DO SOL")).toBe(1);
  });

  it("dá zero quando nada do nome aparece", () => {
    expect(nameOverlap("Marina do Sol", "PIX RECEBIDO JOAO SILVA")).toBe(0);
  });

  it("pontua parcialmente quando só parte do nome aparece", () => {
    const overlap = nameOverlap("Estaleiro Costa Verde", "TED ESTALEIRO COSTA");
    expect(overlap).toBeGreaterThan(0);
    expect(overlap).toBeLessThan(1);
  });
});

describe("referência do documento", () => {
  it("dá bônus quando o número do orçamento aparece no histórico", () => {
    const comRef = scoreCandidate(
      tx({ description: "PIX RECEBIDO REF ORC-00042" }),
      cand({ documentNumber: "ORÇ-00042" }),
    );
    const semRef = scoreCandidate(tx({ description: "PIX RECEBIDO" }), cand({ documentNumber: "ORÇ-00042" }));
    expect(comRef!.score).toBeGreaterThan(semRef!.score);
    expect(comRef!.reasons.some((r) => r.signal === "referencia")).toBe(true);
  });
});

describe("sinal de orçamento (sem vencimento)", () => {
  const sinal = cand({
    kind: "quote_deposit",
    label: "Sinal do ORÇ-00042",
    amount: 6000,
    dueDate: null,
    referenceDate: "2026-07-10",
    documentNumber: "ORÇ-00042",
    clientName: "Marina do Sol",
    convertsQuote: true,
  });

  it("encontra o sinal pago poucos dias após a proposta", () => {
    const s = scoreCandidate(tx({ amount: 6000, transaction_date: "2026-07-15" }), sinal);
    expect(s).not.toBeNull();
    expect(s!.candidate.kind).toBe("quote_deposit");
    expect(s!.candidate.convertsQuote).toBe(true);
  });

  it("ignora proposta antiga demais", () => {
    const s = scoreCandidate(
      tx({ amount: 6000, transaction_date: "2026-12-01" }),
      { ...sinal, referenceDate: "2026-01-01" },
    );
    expect(s).toBeNull();
  });

  it("ignora pagamento anterior à proposta", () => {
    const s = scoreCandidate(tx({ amount: 6000, transaction_date: "2026-07-01" }), sinal);
    expect(s).toBeNull();
  });
});

describe("cenário real do sistema (orçamentos em produção em 27/07/2026)", () => {
  // Os três orçamentos que hoje aguardam resposta do cliente, com o sinal esperado
  // calculado pelo percentual global de 30%. Este é exatamente o caso que a tela
  // antiga não encontrava, porque orçamento não entrava na lista de candidatos.
  const orcamentos: Candidate[] = [
    {
      kind: "quote_deposit", id: "orc-70", label: "Sinal do ORÇ-00070", amount: 1596.41,
      direction: "credit", dueDate: null, referenceDate: "2026-07-25",
      clientName: "Rodrigo", documentNumber: "ORÇ-00070", convertsQuote: true,
    },
    {
      kind: "quote_deposit", id: "orc-69", label: "Sinal do ORÇ-00069", amount: 2702.70,
      direction: "credit", dueDate: null, referenceDate: "2026-07-24",
      clientName: "Vanderlei Andrade", clientDocument: "02837819980",
      documentNumber: "ORÇ-00069", convertsQuote: true,
    },
    {
      kind: "quote_deposit", id: "orc-61", label: "Sinal do ORÇ-00061", amount: 1692.00,
      direction: "credit", dueDate: null, referenceDate: "2026-07-17",
      clientName: "João Luiz Hang", documentNumber: "ORÇ-00061", convertsQuote: true,
    },
  ];

  it("encontra o sinal do ORÇ-00070 por valor e data", () => {
    const out = suggestMatches(
      tx({ amount: 1596.41, transaction_date: "2026-07-27", description: "PIX RECEBIDO RODRIGO" }),
      orcamentos,
    );
    expect(out[0].candidate.documentNumber).toBe("ORÇ-00070");
    expect(out[0].candidate.convertsQuote).toBe(true);
  });

  it("concilia sozinho quando o CPF do pagador confere e o valor é exato", () => {
    const out = suggestMatches(
      tx({ amount: 2702.70, transaction_date: "2026-07-27", counterparty_document: "028.378.199-80" }),
      orcamentos,
    );
    expect(pickAutoApply(out)?.candidate.documentNumber).toBe("ORÇ-00069");
  });

  it("não confunde orçamentos de valores próximos", () => {
    // 1.596,41 e 1.692,00 diferem em R$ 95,59 — acima da tolerância de R$ 50.
    const out = suggestMatches(tx({ amount: 1692.0, transaction_date: "2026-07-27" }), orcamentos);
    expect(out[0].candidate.documentNumber).toBe("ORÇ-00061");
    expect(out[0].score).toBeGreaterThan(out[1]?.score ?? 0);
  });
});

describe("ordenação e aplicação automática", () => {
  it("ordena o mais provável primeiro", () => {
    const out = suggestMatches(tx({ amount: 6000, description: "PIX MARINA DO SOL" }), [
      cand({ id: "fraco", amount: 5200, clientName: "Outro Cliente", dueDate: "2026-06-01" }),
      cand({ id: "forte", amount: 6000, clientName: "Marina do Sol", dueDate: "2026-07-15" }),
    ]);
    expect(out[0].candidate.id).toBe("forte");
  });

  it("não aplica sozinho quando dois candidatos são igualmente certos", () => {
    const t = tx({ counterparty_document: "12345678000190", amount: 6000 });
    const empate = suggestMatches(t, [
      cand({ id: "a", clientDocument: "12345678000190" }),
      cand({ id: "b", clientDocument: "12345678000190" }),
    ]);
    expect(empate.filter((s) => s.autoApply)).toHaveLength(2);
    expect(pickAutoApply(empate)).toBeNull();
  });

  it("aplica sozinho quando há uma única certeza", () => {
    const t = tx({ counterparty_document: "12345678000190", amount: 6000 });
    const out = suggestMatches(t, [
      cand({ id: "certo", clientDocument: "12345678000190" }),
      cand({ id: "duvidoso", amount: 5800, clientName: "Outro" }),
    ]);
    expect(pickAutoApply(out)?.candidate.id).toBe("certo");
  });

  it("devolve lista vazia quando nada é plausível", () => {
    expect(suggestMatches(tx({ amount: 6000 }), [cand({ amount: 50 })])).toHaveLength(0);
  });
});
