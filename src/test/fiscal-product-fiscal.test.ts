import { describe, it, expect } from "vitest";
import {
  resolveProductFiscal,
  type CategoryFiscalDefaults,
  type GlobalFiscalDefaults,
  type ProductFiscalInput,
} from "../../supabase/functions/_shared/fiscal/product-fiscal";

const GLOBAL: GlobalFiscalDefaults = {
  default_csosn: "102",
  default_fiscal_origin: 0,
  default_icms_rate: 0,
  default_ipi_rate: 0,
  default_pis_rate: 0,
  default_cofins_rate: 0,
  default_pis_cst: "49",
  default_cofins_cst: "49",
};

const CATEGORY: CategoryFiscalDefaults = {
  default_ncm: "84213100",
  default_csosn: "500",
  default_fiscal_origin: 1,
  default_icms_rate: 12,
  default_pis_rate: 1.65,
  default_cofins_rate: 7.6,
};

describe("resolveProductFiscal", () => {
  it("modo global (use_global_fiscal=true): usa categoria antes do global", () => {
    const p: ProductFiscalInput = { ncm: "85369090", csosn: "400", fiscal_origin: 0, use_global_fiscal: true };
    const r = resolveProductFiscal(p, CATEGORY, GLOBAL);
    expect(r.csosn).toBe("500"); // da categoria, não o "400" do produto
    expect(r.origin).toBe(1);
    expect(r.icmsRate).toBe(12);
    expect(r.pisRate).toBe(1.65);
    expect(r.cofinsRate).toBe(7.6);
  });

  it("modo global sem categoria: cai no default global", () => {
    const p: ProductFiscalInput = { ncm: "85369090", use_global_fiscal: true };
    const r = resolveProductFiscal(p, null, GLOBAL);
    expect(r.csosn).toBe("102");
    expect(r.origin).toBe(0);
  });

  it("modo personalizado (use_global_fiscal=false): usa os valores do próprio produto", () => {
    const p: ProductFiscalInput = {
      ncm: "85369090", csosn: "101", fiscal_origin: 3,
      icms_rate: 4, pis_rate: 0.65, cofins_rate: 3, use_global_fiscal: false,
    };
    const r = resolveProductFiscal(p, CATEGORY, GLOBAL);
    expect(r.csosn).toBe("101");
    expect(r.origin).toBe(3);
    expect(r.icmsRate).toBe(4);
    expect(r.pisRate).toBe(0.65);
    expect(r.cofinsRate).toBe(3);
  });

  it("NCM do produto tem precedência sobre o default da categoria", () => {
    const p: ProductFiscalInput = { ncm: "85369090", use_global_fiscal: true };
    expect(resolveProductFiscal(p, CATEGORY, GLOBAL).ncm).toBe("85369090");
  });

  it("NCM cai no default da categoria quando o produto não tem", () => {
    const p: ProductFiscalInput = { ncm: "", use_global_fiscal: true };
    expect(resolveProductFiscal(p, CATEGORY, GLOBAL).ncm).toBe("84213100");
  });

  it("CST de PIS/COFINS vem do global (com fallback '49')", () => {
    expect(resolveProductFiscal({ use_global_fiscal: true }, null, GLOBAL).pisCst).toBe("49");
    expect(resolveProductFiscal({ use_global_fiscal: true }, null, {}).pisCst).toBe("49");
    expect(resolveProductFiscal({ use_global_fiscal: true }, null, { default_pis_cst: "01" }).pisCst).toBe("01");
  });

  it("fallbacks seguros quando tudo está vazio (csosn 400 / origem 0)", () => {
    const r = resolveProductFiscal(null, null, null);
    expect(r.csosn).toBe("400");
    expect(r.origin).toBe(0);
    expect(r.icmsRate).toBe(0);
    expect(r.ncm).toBe("");
  });

  it("trata string vazia como ausente na cadeia (não deixa csosn='')", () => {
    const p: ProductFiscalInput = { csosn: "", use_global_fiscal: false };
    expect(resolveProductFiscal(p, null, null).csosn).toBe("400");
  });
});
