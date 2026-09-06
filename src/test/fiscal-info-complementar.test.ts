// [NOVO-fiscal-03/04] O vínculo legível com a OS, e os campos que a Contora
// criou em 06/09/2026 a pedido nosso: desconto incondicionado e informações
// complementares na NFS-e.
//
// O rateio do desconto NÃO é testado aqui: mora em `rateio-desconto.ts` e é
// coberto por `fiscal-rateio-desconto.test.ts`.
import { describe, it, expect } from "vitest";
import { montarInfoComplementar } from "../../supabase/functions/_shared/fiscal/info-complementar";
import {
  buildNfseDraftPayload,
  validateNfseDraftInput,
  NFSE_INFO_COMPL_MAX,
} from "../../supabase/functions/_shared/fiscal/nfse-payload-builder";

describe("montarInfoComplementar", () => {
  it("amarra a nota à OS", () => {
    expect(montarInfoComplementar({ osNumero: "OS-00075" })).toContain("OS-00075");
  });

  it("sem nada a dizer, devolve null em vez de texto vazio", () => {
    // Quadro ausente é melhor que quadro em branco.
    expect(montarInfoComplementar({})).toBeNull();
    expect(montarInfoComplementar({ osNumero: "  " })).toBeNull();
  });

  it("o pedido do cliente entra quando existe, e só então", () => {
    expect(montarInfoComplementar({ osNumero: "OS-1", pedidoCliente: "PC-99" })).toContain("PC-99");
    expect(montarInfoComplementar({ osNumero: "OS-1" })).not.toContain("Pedido");
  });

  // O que a nota afirma vincula a empresa: inventar cláusula em nome do dono não
  // é decisão de código.
  it("não inventa garantia, prazo nem condição de pagamento", () => {
    const t = montarInfoComplementar({ osNumero: "OS-1", pedidoCliente: "PC-1" }) ?? "";
    expect(t.toLowerCase()).not.toMatch(/garantia|prazo|vencimento|parcela/);
  });

  // O desconto tem campo próprio nos dois documentos desde 06/09/2026. Repetir
  // por extenso faria o tomador ler o mesmo abatimento duas vezes.
  it("não repete o desconto, que agora tem campo próprio", () => {
    const t = montarInfoComplementar({ osNumero: "OS-00075" }) ?? "";
    expect(t.toLowerCase()).not.toContain("desconto");
  });
});

const baseValida = {
  standard: "nacional" as const,
  service: {
    description: "Instalação elétrica",
    nationalTaxCode: "140101",
    cnae: "3317102",
    issRate: 3,
    issWithheld: false,
  },
  taker: {
    name: "Cliente Teste",
    document: "12345678000190",
    address: {
      street: "Rua Um",
      number: "10",
      district: "Centro",
      cityCode: "4208203",
      stateCode: "SC",
      postalCode: "88300000",
    },
  },
  amounts: { serviceAmount: 1000 },
};

describe("NFS-e: desconto incondicionado (vDescIncond)", () => {
  // O caso REAL: a OS-00075 tinha 538,33 de serviço com 169,78 de desconto
  // rateado. Até 06/09/2026 mandávamos 368,55 como "valor do serviço" e o
  // desconto ficava invisível na nota.
  it("a OS-00075 sai com o BRUTO e o desconto em campo próprio", () => {
    const p = buildNfseDraftPayload({
      ...baseValida,
      amounts: { serviceAmount: 538.33, unconditionalDiscount: 169.78 },
    }) as Record<string, any>;

    expect(p.amounts.service_amount).toBe(538.33);
    expect(p.amounts.unconditional_discount).toBe(169.78);
    // O líquido NÃO vai: quem calcula é o Ambiente Nacional. Mandar 368,55
    // junto com o desconto descontaria duas vezes.
    expect(p.amounts).not.toHaveProperty("net_amount");
  });

  it("sem desconto, o payload não ganha campo nenhum a mais", () => {
    const p = buildNfseDraftPayload(baseValida) as Record<string, any>;
    expect(p.amounts).not.toHaveProperty("unconditional_discount");
    expect(p.amounts).not.toHaveProperty("conditional_discount");
  });

  it("o líquido só aparece quando alguém o afirma", () => {
    const p = buildNfseDraftPayload({
      ...baseValida,
      amounts: { serviceAmount: 1000, netAmount: 1000 },
    }) as Record<string, any>;
    expect(p.amounts.net_amount).toBe(1000);
  });
});

describe("NFS-e: o que o validador barra antes de gastar cota", () => {
  // O engano mais caro: abater o desconto do bruto E ainda declarar o desconto.
  it("pega o desconto contado duas vezes", () => {
    const erros = validateNfseDraftInput({
      ...baseValida,
      amounts: { serviceAmount: 538.33, unconditionalDiscount: 169.78, netAmount: 368.55 - 169.78 },
    });
    expect(erros.join(" ")).toMatch(/duas vezes/);
  });

  it("aceita o líquido quando ele bate com a conta", () => {
    const erros = validateNfseDraftInput({
      ...baseValida,
      amounts: { serviceAmount: 538.33, unconditionalDiscount: 169.78, netAmount: 368.55 },
    });
    expect(erros).toEqual([]);
  });

  it("desconto maior que o serviço não passa", () => {
    const erros = validateNfseDraftInput({
      ...baseValida,
      amounts: { serviceAmount: 100, unconditionalDiscount: 150 },
    });
    expect(erros.join(" ")).toMatch(/não pode passar do valor do serviço/);
  });

  it("desconto negativo não passa", () => {
    const erros = validateNfseDraftInput({
      ...baseValida,
      amounts: { serviceAmount: 100, unconditionalDiscount: -1 },
    });
    expect(erros.join(" ")).toMatch(/não pode ser negativo/);
  });

  // E0441: a Sefin recusa dedução para ME/EPP do Simples quando o município
  // parametriza assim o código — é o caso do 14.01 em Itajaí. Confirmado em
  // homologação pela Contora.
  it("avisa da E0441 antes de a Sefin recusar a dedução", () => {
    const erros = validateNfseDraftInput({
      ...baseValida,
      amounts: { serviceAmount: 1000, deductions: 100 },
    });
    expect(erros.join(" ")).toMatch(/E0441/);
  });

  // A NFS-e não transporta retenção federal: o valor seria descartado sem
  // aparecer na nota, e desde 06/09/2026 a Contora recusa.
  it("barra retenção federal com valor, aceita zerada", () => {
    const comValor = validateNfseDraftInput({
      ...baseValida,
      amounts: { serviceAmount: 1000, pisAmount: 10 },
    });
    expect(comValor.join(" ")).toMatch(/PIS/);

    // Zerados continuam válidos — é o que o payload de hoje manda.
    const zerado = validateNfseDraftInput({
      ...baseValida,
      amounts: { serviceAmount: 1000, pisAmount: 0, cofinsAmount: 0, csllAmount: 0 },
    });
    expect(zerado).toEqual([]);
  });

  // Recusar, não cortar: nota autorizada com informação pela metade esconde o
  // erro e mantém o dano.
  it("recusa informação complementar acima do limite em vez de truncar", () => {
    const longo = "x".repeat(NFSE_INFO_COMPL_MAX + 1);
    const erros = validateNfseDraftInput({
      ...baseValida,
      service: { ...baseValida.service, additionalInfo: longo },
    });
    expect(erros.join(" ")).toMatch(/limite é 2000/);

    const p = buildNfseDraftPayload({
      ...baseValida,
      service: { ...baseValida.service, additionalInfo: "Ref. Ordem de Serviço OS-00075." },
    }) as Record<string, any>;
    expect(p.service.additional_info).toBe("Ref. Ordem de Serviço OS-00075.");
  });
});
