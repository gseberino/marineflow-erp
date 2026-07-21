import { describe, it, expect } from "vitest";
import {
  SIMPLES_INFO_NOTE,
  normalizeAdditionalInfo,
  stripInvalidIcmsCreditClaim,
} from "../lib/nfe-info-complementar";

// Texto EXATO que o sistema gravava antes da correção (commit 9a3886d) e que
// reapareceu numa nota real por ter sido reaproveitado ao duplicar/reemitir.
const LEGADO =
  "Documento emitido por optante do Simples Nacional. Não gera direito a crédito fiscal de IPI. " +
  "Permite o aproveitamento do crédito de ICMS conforme a legislação (art. 23 da LC 123/2006).";

const NOTA_REAL =
  "Referente a Ordem de Compra N. 05447. Comprador: Everton " + LEGADO;

describe("stripInvalidIcmsCreditClaim", () => {
  it("remove a frase de crédito de ICMS (inválida com CSOSN 102)", () => {
    const out = stripInvalidIcmsCreditClaim(LEGADO);
    expect(out).not.toMatch(/aproveitamento do cr[ée]dito de ICMS/i);
    // não pode sobrar lixo do "(art. 23 da LC 123/2006)."
    expect(out).not.toContain("123/2006");
    expect(out).not.toContain(")");
    expect(out).toBe("Documento emitido por optante do Simples Nacional. Não gera direito a crédito fiscal de IPI.");
  });

  it("preserva o texto livre do usuário (ordem de compra, comprador)", () => {
    const out = stripInvalidIcmsCreditClaim(NOTA_REAL);
    expect(out).toContain("Ordem de Compra N. 05447");
    expect(out).toContain("Comprador: Everton");
    expect(out).not.toMatch(/aproveitamento do cr[ée]dito de ICMS/i);
  });

  it("não altera um texto que já está correto", () => {
    expect(stripInvalidIcmsCreditClaim(SIMPLES_INFO_NOTE)).toBe(SIMPLES_INFO_NOTE);
  });
});

describe("normalizeAdditionalInfo", () => {
  it("limpa a frase inválida e mantém a declaração obrigatória do Simples", () => {
    const out = normalizeAdditionalInfo(NOTA_REAL);
    expect(out).not.toMatch(/aproveitamento do cr[ée]dito de ICMS/i);
    expect(out).toMatch(/optante\s+(pelo\s+)?Simples\s+Nacional/i);
    expect(out).toContain("Ordem de Compra N. 05447");
  });

  it("acrescenta a declaração obrigatória quando falta (ex.: devolução)", () => {
    const out = normalizeAdditionalInfo("Devolução referente à NF-e nº 15, série 2.");
    expect(out).toContain("Devolução referente à NF-e nº 15, série 2.");
    expect(out).toContain(SIMPLES_INFO_NOTE);
  });

  it("não duplica a declaração quando ela já existe", () => {
    const out = normalizeAdditionalInfo(SIMPLES_INFO_NOTE);
    expect(out).toBe(SIMPLES_INFO_NOTE);
    expect(out.match(/optante/gi)?.length).toBe(1);
  });

  // Regressão real: a redação ANTIGA diz "optante DO Simples Nacional" e a nova
  // "ME ou EPP optante PELO". A checagem de presença só cobria "pelo", então a
  // declaração era anexada e saía DUPLICADA na nota.
  it("não duplica quando o texto traz a redação ANTIGA (optante DO Simples)", () => {
    const out = normalizeAdditionalInfo(NOTA_REAL);
    expect(out.match(/Documento emitido por/gi)?.length).toBe(1);
    expect(out.match(/cr[ée]dito fiscal de IPI/gi)?.length).toBe(1);
    expect(out).not.toMatch(/optante\s+do\s+Simples/i); // redação antiga some
    expect(out).toContain(SIMPLES_INFO_NOTE); // fica só a canônica
    expect(out).toContain("Ordem de Compra N. 05447");
  });

  it("colapsa um texto que JÁ saiu duplicado (as duas redações juntas)", () => {
    const duplicado =
      "Referente a Ordem de Compra N. 05447. Comprador: Everton " +
      "Documento emitido por optante do Simples Nacional. Não gera direito a crédito fiscal de IPI. " +
      "Documento emitido por ME ou EPP optante pelo Simples Nacional. Não gera direito a crédito fiscal de IPI.";
    const out = normalizeAdditionalInfo(duplicado);
    expect(out.match(/Documento emitido por/gi)?.length).toBe(1);
    expect(out.match(/cr[ée]dito fiscal de IPI/gi)?.length).toBe(1);
    expect(out).toBe(
      "Referente a Ordem de Compra N. 05447. Comprador: Everton. " + SIMPLES_INFO_NOTE,
    );
  });

  it("separa com ponto quando o texto do usuário não termina em pontuação", () => {
    const out = normalizeAdditionalInfo("Comprador: Everton");
    expect(out).toBe("Comprador: Everton. " + SIMPLES_INFO_NOTE);
  });

  it("devolve a declaração obrigatória quando o texto vem vazio/nulo", () => {
    expect(normalizeAdditionalInfo("")).toBe(SIMPLES_INFO_NOTE);
    expect(normalizeAdditionalInfo(null)).toBe(SIMPLES_INFO_NOTE);
    expect(normalizeAdditionalInfo(undefined)).toBe(SIMPLES_INFO_NOTE);
  });

  it("a declaração padrão NÃO afirma crédito de ICMS (só a vedação de IPI)", () => {
    expect(SIMPLES_INFO_NOTE).toMatch(/não gera direito a crédito fiscal de IPI/i);
    expect(SIMPLES_INFO_NOTE).not.toMatch(/cr[ée]dito de ICMS/i);
  });
});
