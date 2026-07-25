import { describe, it, expect } from "vitest";
import {
  computeDraftTotal,
  computeDraftMeta,
  normalizeDraftState,
  natureLabel,
  type FiscalDraftState,
} from "../lib/fiscal-draft-state";

const state = (over: Partial<FiscalDraftState> = {}): FiscalDraftState =>
  normalizeDraftState({ recipientName: "Kamell Ltda", natureOfOperation: "devolucao", ...over });

describe("computeDraftTotal", () => {
  it("soma qtd×unitário − desconto + outras despesas (vProd − vDesc + vOutro)", () => {
    const total = computeDraftTotal([
      { quantity: 1, unit_price: 2147.74, discount: 0, other_expenses: 209.4 },
    ]);
    expect(total).toBeCloseTo(2357.14, 2);
  });

  it("tolera itens/campos ausentes sem quebrar", () => {
    expect(computeDraftTotal(undefined)).toBe(0);
    expect(computeDraftTotal([{}, { quantity: 2, unit_price: 10 }])).toBe(20);
  });
});

describe("computeDraftMeta", () => {
  it("usa label custom quando informado", () => {
    expect(computeDraftMeta(state(), "Meu rascunho").label).toBe("Meu rascunho");
  });

  it("cai para 'destinatário · natureza' quando label vazio", () => {
    expect(computeDraftMeta(state()).label).toBe("Kamell Ltda · Devolução");
  });

  it("desnormaliza recipiente/natureza/total para a lista", () => {
    const m = computeDraftMeta(
      state({ items: [{ quantity: 1, unit_price: 100, discount: 0, other_expenses: 0 }] }),
    );
    expect(m.recipient_name).toBe("Kamell Ltda");
    expect(m.nature_of_operation).toBe("devolucao");
    expect(m.total_amount).toBe(100);
  });
});

describe("normalizeDraftState", () => {
  it("preenche defaults para form_state vazio/inválido (schema drift)", () => {
    const s = normalizeDraftState(null);
    expect(s.natureOfOperation).toBe("venda");
    expect(s.paymentMethod).toBe("01");
    expect(s.recipientIeIndicator).toBe(9);
    expect(s.consumerFinal).toBe(true);
    expect(s.payMode).toBe("avista");
    expect(s.items).toEqual([]);
  });

  it("preserva os campos presentes", () => {
    const s = normalizeDraftState({ recipientName: "X", payMode: "parcelado", payN: 6, items: [{ quantity: 1 }] });
    expect(s.recipientName).toBe("X");
    expect(s.payMode).toBe("parcelado");
    expect(s.payN).toBe(6);
    expect(s.items).toHaveLength(1);
  });

  it("nunca lança para entradas malformadas", () => {
    expect(() => normalizeDraftState("lixo")).not.toThrow();
    expect(() => normalizeDraftState(123)).not.toThrow();
    expect(normalizeDraftState({ items: "nao-array" }).items).toEqual([]);
  });
});

describe("natureLabel", () => {
  it("traduz naturezas conhecidas e devolve a chave crua para desconhecidas", () => {
    expect(natureLabel("venda")).toBe("Venda");
    expect(natureLabel("devolucao")).toBe("Devolução");
    expect(natureLabel("xyz")).toBe("xyz");
    expect(natureLabel(undefined)).toBe("NF-e");
  });
});
