import { describe, it, expect } from "vitest";
import {
  cleanText,
  resolveGtin,
  isValidNcm,
  isValidCfop,
  isValidCep,
  roundTo,
  NFE_LIMITS,
} from "../../supabase/functions/_shared/fiscal/nfe-sanitize";

describe("cleanText", () => {
  it("apara pontas e colapsa espaços internos", () => {
    expect(cleanText("  Rua   das   Flores  ", 60)).toBe("Rua das Flores");
  });

  it("remove quebras de linha e tabs (viram espaço único)", () => {
    expect(cleanText("Linha1\n\tLinha2", 60)).toBe("Linha1 Linha2");
  });

  it("trunca no tamanho máximo e apara a sobra", () => {
    const s = "A".repeat(130);
    expect(cleanText(s, NFE_LIMITS.itemName).length).toBe(120);
  });

  it("trata null/undefined como vazio", () => {
    expect(cleanText(null, 60)).toBe("");
    expect(cleanText(undefined, 60)).toBe("");
  });

  it("preserva acentos (NF-e é UTF-8)", () => {
    expect(cleanText("São João da Boa Vista", 60)).toBe("São João da Boa Vista");
  });
});

describe("resolveGtin", () => {
  it("aceita GTIN de 8/12/13/14 dígitos", () => {
    expect(resolveGtin("7891234567895")).toBe("7891234567895"); // 13
    expect(resolveGtin("12345678")).toBe("12345678"); // 8
  });

  it("vira 'SEM GTIN' quando vazio ou tamanho inválido", () => {
    expect(resolveGtin("")).toBe("SEM GTIN");
    expect(resolveGtin(null)).toBe("SEM GTIN");
    expect(resolveGtin("123")).toBe("SEM GTIN"); // 3 dígitos
    expect(resolveGtin("LP-28-C02PE-3")).toBe("SEM GTIN"); // SKU, não é GTIN
  });

  it("extrai só os dígitos antes de validar o tamanho", () => {
    expect(resolveGtin("789-1234-567895")).toBe("7891234567895");
  });
});

describe("validadores NCM/CFOP/CEP", () => {
  it("NCM válido tem 8 dígitos", () => {
    expect(isValidNcm("85369090")).toBe(true);
    expect(isValidNcm("8536909")).toBe(false); // 7
    expect(isValidNcm("")).toBe(false);
  });

  it("CFOP válido tem 4 dígitos", () => {
    expect(isValidCfop("5102")).toBe(true);
    expect(isValidCfop("510")).toBe(false);
    expect(isValidCfop("51022")).toBe(false);
  });

  it("CEP válido tem 8 dígitos", () => {
    expect(isValidCep("89294-000")).toBe(true);
    expect(isValidCep("8929400")).toBe(false);
  });
});

describe("roundTo", () => {
  it("arredonda para o número de casas pedido", () => {
    expect(roundTo(1.23456, 4)).toBe(1.2346);
    expect(roundTo(270, 2)).toBe(270);
    expect(roundTo(0.1 + 0.2, 2)).toBe(0.3); // corrige ruído de float
  });

  it("retorna 0 para valores não finitos", () => {
    expect(roundTo(NaN, 2)).toBe(0);
    expect(roundTo(Infinity, 2)).toBe(0);
  });
});
