import { describe, it, expect } from "vitest";
import { buildEmissionItem, type EmissionDraftItem } from "../lib/fiscal-emission-item";

const base: EmissionDraftItem = {
  code: "CERBO", name: "CENTRAL CERBO GX", ncm: "85176900", cfop: "6202", unit: "PC",
  quantity: 1, unit_price: 2147.74,
  origin: 2, icms_rate: 0, pis_rate: 0, cofins_rate: 0, ipi_rate: 0,
};

describe("buildEmissionItem", () => {
  // Regressão do bug: buildEmissionBody lia it.otherExpenses (typo) em vez de
  // it.other_expenses, então o IPI/vOutro ia sempre 0 e o total da devolução saía
  // menor (parecendo desconto). O type-check não roda no build → este teste é a rede.
  it("envia other_expenses (vOutro/IPI) do campo correto", () => {
    const r = buildEmissionItem({ ...base, other_expenses: 209.40 });
    expect(r.other_expenses).toBe(209.40);
  });

  it("omite/zera other_expenses quando ausente", () => {
    expect(buildEmissionItem(base).other_expenses).toBe(0);
  });

  it("envia o desconto (vDesc) por item", () => {
    expect(buildEmissionItem({ ...base, discount: 51 }).discount).toBe(51);
    expect(buildEmissionItem(base).discount).toBe(0);
  });

  it("mapeia referencedKey/referencedItemNumber → referenced_key/referenced_item", () => {
    const r = buildEmissionItem({ ...base, referencedKey: "42260750057049000159550020000000191870891237", referencedItemNumber: 5 });
    expect(r.referenced_key).toBe("42260750057049000159550020000000191870891237");
    expect(r.referenced_item).toBe(5);
  });

  it("preserva NCM/CFOP/CSOSN/origem/alíquotas e valor unitário", () => {
    const r = buildEmissionItem({ ...base, csosn: "900", unit_price: 100, quantity: 3 });
    expect(r.ncm).toBe("85176900");
    expect(r.cfop).toBe("6202");
    expect(r.csosn).toBe("900");
    expect(r.origin).toBe(2);
    expect(r.unit_price).toBe(100);
    expect(r.quantity).toBe(3);
  });
});
