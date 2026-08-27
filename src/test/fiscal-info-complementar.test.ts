// [NOVO-fiscal-03] O quadro "INFORMAÇÕES COMPLEMENTARES" saía vazio nas duas notas.
//
// O rateio do desconto NÃO é testado aqui: ele mora em `rateio-desconto.ts` e é
// coberto por `fiscal-rateio-desconto.test.ts`, escrito noutra sessão para o
// mesmo incidente. Este arquivo cobre só o vínculo legível com a OS.
import { describe, it, expect } from "vitest";
import {
  montarInfoComplementar,
  referenciaCurtaDaOs,
} from "../../supabase/functions/_shared/fiscal/info-complementar";

describe("montarInfoComplementar (NF-e / infCpl)", () => {
  it("amarra a nota à OS e explica o desconto", () => {
    const t = montarInfoComplementar({ osNumero: "OS-00075", descontoAplicado: 60.56 });
    expect(t).toContain("OS-00075");
    // Separador decimal vírgula: quem lê a nota é brasileiro.
    expect(t).toContain("R$ 60,56");
  });

  it("sem nada a dizer, devolve null em vez de texto vazio", () => {
    // Quadro ausente é melhor que quadro em branco.
    expect(montarInfoComplementar({})).toBeNull();
    expect(montarInfoComplementar({ descontoAplicado: 0 })).toBeNull();
  });

  it("o pedido do cliente entra quando existe, e só então", () => {
    expect(montarInfoComplementar({ osNumero: "OS-1", pedidoCliente: "PC-99" })).toContain("PC-99");
    expect(montarInfoComplementar({ osNumero: "OS-1" })).not.toContain("Pedido");
  });

  // O que a nota afirma vincula a empresa: inventar cláusula em nome do dono
  // não é decisão de código.
  it("não inventa garantia, prazo nem condição de pagamento", () => {
    const t = montarInfoComplementar({ osNumero: "OS-1", descontoAplicado: 10 }) ?? "";
    expect(t.toLowerCase()).not.toMatch(/garantia|prazo|vencimento|parcela/);
  });
});

describe("referenciaCurtaDaOs (NFS-e / discriminação)", () => {
  it("é curta porque disputa os 500 caracteres da discriminação", () => {
    const r = referenciaCurtaDaOs("OS-00075") ?? "";
    expect(r).toBe("Ref. OS OS-00075");
    expect(r.length).toBeLessThan(30);
  });

  it("sem número de OS não inventa referência", () => {
    expect(referenciaCurtaDaOs(null)).toBeNull();
    expect(referenciaCurtaDaOs("   ")).toBeNull();
  });

  // A regra que o corte da ponte tem que respeitar: numa OS com muitos serviços,
  // o slice(0,500) cortaria justamente o vínculo com o trabalho. Este teste
  // reproduz a montagem da ponte para travar esse comportamento.
  it("sobrevive ao corte de 500 caracteres quando a lista é enorme", () => {
    const listaEnorme = Array.from({ length: 80 }, (_, i) => `Serviço número ${i}`).join("; ");
    expect(listaEnorme.length).toBeGreaterThan(500);

    const refOs = referenciaCurtaDaOs("OS-00075")!;
    const descricao = `${listaEnorme.slice(0, Math.max(0, 500 - refOs.length - 2))}; ${refOs}`;

    expect(descricao.length).toBeLessThanOrEqual(500);
    expect(descricao).toContain("OS-00075");
    expect(descricao.endsWith(refOs)).toBe(true);
  });
});
