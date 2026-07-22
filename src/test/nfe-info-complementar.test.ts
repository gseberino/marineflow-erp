import { describe, it, expect } from "vitest";
import {
  BLOCK_SEPARATOR,
  SIMPLES_INFO_NOTE,
  composeAdditionalInfo,
  normalizeAdditionalInfo,
  stripInvalidIcmsCreditClaim,
  stripManagedBlocks,
  stripPurchaseBlock,
  START_CONTENT_ON_NEW_LINE,
} from "../lib/nfe-info-complementar";

// O infCpl comeca com o separador para desgrudar o conteudo do rotulo
// "Inf. Contribuinte:" que o DANFE da Contora imprime. Os testes comparam pelo
// helper para nao quebrarem se esse comportamento for ligado/desligado.
const comLead = (texto: string) => (START_CONTENT_ON_NEW_LINE ? BLOCK_SEPARATOR + texto : texto);

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
    expect(out).toBe(comLead(SIMPLES_INFO_NOTE));
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
    expect(out).toBe(comLead("Referente a Ordem de Compra N. 05447. Comprador: Everton" + BLOCK_SEPARATOR + SIMPLES_INFO_NOTE));
  });

  it("não apaga um 'Comprador:' escrito pelo usuário quando não há campo estruturado", () => {
    const out = normalizeAdditionalInfo("Comprador: Everton");
    expect(out).toBe(comLead("Comprador: Everton" + BLOCK_SEPARATOR + SIMPLES_INFO_NOTE));
  });

  it("devolve a declaração obrigatória quando o texto vem vazio/nulo", () => {
    expect(normalizeAdditionalInfo("")).toBe(comLead(SIMPLES_INFO_NOTE));
    expect(normalizeAdditionalInfo(null)).toBe(comLead(SIMPLES_INFO_NOTE));
    expect(normalizeAdditionalInfo(undefined)).toBe(comLead(SIMPLES_INFO_NOTE));
  });

  it("a declaração padrão NÃO afirma crédito de ICMS (só a vedação de IPI)", () => {
    expect(SIMPLES_INFO_NOTE).toMatch(/não gera direito a crédito fiscal de IPI/i);
    expect(SIMPLES_INFO_NOTE).not.toMatch(/cr[ée]dito de ICMS/i);
  });
});

describe("composeAdditionalInfo — ordem por contrato", () => {
  it("põe pedido/comprador PRIMEIRO e a declaração do Simples POR ÚLTIMO", () => {
    const out = composeAdditionalInfo({
      purchaseOrder: "05447",
      buyer: "Everton",
      freeText: "Referente a entrega parcial.",
    });
    expect(out).toBe(comLead("Pedido de Compra: 05447 - Comprador: Everton" + BLOCK_SEPARATOR +
      "Referente a entrega parcial." + BLOCK_SEPARATOR + SIMPLES_INFO_NOTE));
    // a ordem é o ponto central do pedido do usuário
    expect(out.indexOf("Pedido de Compra")).toBeLessThan(out.indexOf("Referente a entrega"));
    expect(out.indexOf("Referente a entrega")).toBeLessThan(out.indexOf("Documento emitido"));
  });

  it("omite as partes não preenchidas", () => {
    expect(composeAdditionalInfo({ purchaseOrder: "05447" }))
      .toBe(comLead("Pedido de Compra: 05447" + BLOCK_SEPARATOR + SIMPLES_INFO_NOTE));
    expect(composeAdditionalInfo({ buyer: "Everton" }))
      .toBe(comLead("Comprador: Everton" + BLOCK_SEPARATOR + SIMPLES_INFO_NOTE));
    expect(composeAdditionalInfo({})).toBe(comLead(SIMPLES_INFO_NOTE));
    expect(composeAdditionalInfo({ purchaseOrder: "   ", buyer: "  " })).toBe(comLead(SIMPLES_INFO_NOTE));
  });

  it("NÃO duplica o bloco de pedido ao recompor (duplicar/reemitir)", () => {
    const primeira = composeAdditionalInfo({ purchaseOrder: "05447", buyer: "Everton", freeText: "Entrega parcial." });
    const segunda = composeAdditionalInfo({ purchaseOrder: "05447", buyer: "Everton", freeText: primeira });
    expect(segunda).toBe(primeira);
    expect(segunda.match(/Pedido de Compra/gi)?.length).toBe(1);
    expect(segunda.match(/Comprador:/gi)?.length).toBe(1);
    expect(segunda.match(/Documento emitido por/gi)?.length).toBe(1);
  });

  it("limpa a frase inválida de crédito de ICMS vinda de nota antiga", () => {
    const legado =
      "Referente a Ordem de Compra N. 05447. Comprador: Everton. " +
      "Documento emitido por optante do Simples Nacional. Não gera direito a crédito fiscal de IPI. " +
      "Permite o aproveitamento do crédito de ICMS conforme a legislação (art. 23 da LC 123/2006).";
    const out = composeAdditionalInfo({ purchaseOrder: "05447", buyer: "Everton", freeText: legado });
    expect(out).not.toMatch(/aproveitamento do cr[ée]dito de ICMS/i);
    expect(out.match(/Documento emitido por/gi)?.length).toBe(1);
    expect(out.startsWith(comLead("Pedido de Compra: 05447 - Comprador: Everton"))).toBe(true);
  });

  it("nunca usa quebra de linha (infCpl não aceita CR/LF — Rejeição 215/588)", () => {
    const out = composeAdditionalInfo({
      purchaseOrder: "05447", buyer: "Everton", freeText: "Linha 1\nLinha 2",
    });
    expect(BLOCK_SEPARATOR).not.toMatch(/[\r\n\t]/);
    expect(out).not.toMatch(/[\r\n]/);
  });
});

describe("stripManagedBlocks / stripPurchaseBlock", () => {
  it("stripManagedBlocks devolve só o texto do usuário (para o campo editável)", () => {
    const composto = composeAdditionalInfo({ purchaseOrder: "05447", freeText: "Entrega parcial." });
    const livre = stripManagedBlocks(composto);
    expect(livre).not.toContain("Documento emitido por");
    expect(livre).toContain("Entrega parcial.");
    expect(livre).toContain("Pedido de Compra: 05447"); // ainda visível p/ o usuário
  });

  it("stripPurchaseBlock remove o bloco de pedido sem deixar separador órfão", () => {
    const composto = composeAdditionalInfo({ purchaseOrder: "05447", buyer: "Everton", freeText: "Entrega parcial." });
    const semPedido = stripPurchaseBlock(composto);
    expect(semPedido).not.toMatch(/Pedido de Compra/i);
    expect(semPedido.startsWith("Entrega parcial.")).toBe(true);
    expect(semPedido).not.toMatch(/^\s*\|/);
    expect(semPedido).not.toMatch(/\|\s*\|/);
  });
});

describe("separador de blocos — comportamento confirmado pela Contora", () => {
  it("usa ';' (vira quebra de linha no DANFE) e NUNCA '|' (sai impresso literal)", () => {
    expect(BLOCK_SEPARATOR.trim()).toBe(";");
    const out = composeAdditionalInfo({ purchaseOrder: "05447", freeText: "Entrega parcial." });
    expect(out).not.toContain("|");
    expect(out).toBe(comLead("Pedido de Compra: 05447; Entrega parcial.; " + SIMPLES_INFO_NOTE));
  });

  it("converte quebra digitada pelo usuário em separador (vira linha no DANFE, sem CR/LF no XML)", () => {
    const out = composeAdditionalInfo({ freeText: "Linha 1\nLinha 2\r\nLinha 3" });
    expect(out).not.toMatch(/[\r\n\t]/); // infCpl não aceita char de controle
    expect(out).toBe(comLead("Linha 1; Linha 2; Linha 3; " + SIMPLES_INFO_NOTE));
  });

  it("não deixa separadores em sequência quando o usuário pula linhas em branco", () => {
    const out = composeAdditionalInfo({ freeText: "Linha 1\n\n\nLinha 2" });
    expect(out).toBe(comLead("Linha 1; Linha 2; " + SIMPLES_INFO_NOTE));
    expect(out).not.toMatch(/;\s*;/);
  });

  it("ainda entende o delimitador '|' de notas gravadas antes da confirmação", () => {
    const legado = "Pedido de Compra: 05447 - Comprador: Everton | Entrega parcial. | " + SIMPLES_INFO_NOTE;
    const out = composeAdditionalInfo({ purchaseOrder: "05447", buyer: "Everton", freeText: legado });
    expect(out.match(/Pedido de Compra/gi)?.length).toBe(1);
    expect(out.match(/Documento emitido por/gi)?.length).toBe(1);
    expect(out).toBe(comLead("Pedido de Compra: 05447 - Comprador: Everton; Entrega parcial.; " + SIMPLES_INFO_NOTE));
  });
});

describe("rótulo 'Inf. Contribuinte:' do DANFE da Contora", () => {
  it("o texto que ENVIAMOS nunca contém o rótulo (ele é do renderizador deles)", () => {
    const out = composeAdditionalInfo({ purchaseOrder: "05447", buyer: "Everton" });
    expect(out).not.toMatch(/Inf\.\s*Contribuinte/i);
    expect(out).not.toMatch(/Inf\.\s*Fisco/i);
  });

  // A Contora suprimiu o prefixo para o CNPJ da HBR, então o paliativo do ";"
  // inicial saiu de cena — eles recomendaram enviar o conteúdo direto.
  it("não começa mais com separador (prefixo removido pela Contora)", () => {
    const out = composeAdditionalInfo({ purchaseOrder: "05447" });
    expect(START_CONTENT_ON_NEW_LINE).toBe(false);
    expect(out.startsWith(BLOCK_SEPARATOR)).toBe(false);
    expect(out.startsWith("Pedido de Compra: 05447")).toBe(true);
  });

  it("não deixa separador órfão nas pontas ao recompor um texto já composto", () => {
    const primeira = composeAdditionalInfo({ purchaseOrder: "05447", freeText: "Entrega parcial." });
    const segunda = composeAdditionalInfo({ purchaseOrder: "05447", freeText: primeira });
    expect(segunda).toBe(primeira);
    expect(segunda).not.toMatch(/^;/);
    expect(segunda).not.toMatch(/;\s*$/);
  });
});
