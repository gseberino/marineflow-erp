// [F-DESC-01] O desconto da ORDEM chegando aos documentos fiscais.
//
// O caso que originou tudo está travado aqui como primeiro teste: a NFS-e nº 2
// da OS-00075 saiu em produção com R$ 538,33 para uma ordem de R$ 500,00,
// porque a ponte somava os `line_total` e nunca lia o `discount_amount`. O dono
// cancelou a nota; este arquivo existe para que não haja uma segunda.
import { describe, it, expect } from "vitest";
import {
  repartirDescontoDaOrdem,
  distribuirDescontoNosItens,
} from "../../supabase/functions/_shared/fiscal/desconto-da-ordem";
import { montarInfoComplementar } from "../../supabase/functions/_shared/fiscal/info-complementar";

describe("repartirDescontoDaOrdem", () => {
  // Os números REAIS da OS-00075, conferidos no banco em 27/08/2026.
  it("a OS-00075: as duas notas passam a somar o que o cliente deve", () => {
    const r = repartirDescontoDaOrdem({
      subtotalServicos: 538.33,
      subtotalPecas: 192.01,
      despesas: 0,
      desconto: 230.34,
    });

    expect(r.criterio).toBe("proporcional");
    expect(r.servicosLiquido).toBe(368.55);
    expect(r.pecasLiquido).toBe(131.45);

    // O que a nota errada custou: 538,33 − 368,55 de receita a mais.
    expect(r.descontoServicos).toBe(169.78);

    // E o essencial: as duas notas somam o total da OS, nem um centavo a mais.
    expect(r.servicosLiquido + r.pecasLiquido).toBeCloseTo(500.0, 2);
  });

  // A garantia de que nada que já saía certo muda de valor.
  it("sem desconto, os valores passam intactos", () => {
    const r = repartirDescontoDaOrdem({ subtotalServicos: 1000, subtotalPecas: 500, desconto: 0 });
    expect(r.criterio).toBe("sem_desconto");
    expect(r.servicosLiquido).toBe(1000);
    expect(r.pecasLiquido).toBe(500);
    expect(r.descontoServicos).toBe(0);
  });

  // Quando alguém disse de ONDE o desconto saiu, o código não adivinha diferente.
  it("percentual por seção manda sobre a proporção", () => {
    const r = repartirDescontoDaOrdem({
      subtotalServicos: 1000,
      subtotalPecas: 500,
      desconto: 100,
      descontoServicosPct: 10,
      descontoPecasPct: 0,
    });
    expect(r.criterio).toBe("por_secao");
    expect(r.descontoServicos).toBe(100);
    expect(r.descontoPecas).toBe(0);
    expect(r.servicosLiquido).toBe(900);
    expect(r.pecasLiquido).toBe(500);
  });

  // As despesas entram na BASE, então diluem o desconto — e a soma das notas
  // fica menor que o total da OS, porque deslocamento não vira nota.
  it("despesas diluem o desconto e não viram nota", () => {
    const r = repartirDescontoDaOrdem({
      subtotalServicos: 500,
      subtotalPecas: 300,
      despesas: 200,
      desconto: 100,
    });
    // razao = 1 − 100/1000 = 0,9
    expect(r.servicosLiquido).toBe(450);
    expect(r.pecasLiquido).toBe(270);
  });

  // Dado incoerente não pode virar valor negativo em documento fiscal.
  it("desconto maior que a base zera, não fica negativo", () => {
    const r = repartirDescontoDaOrdem({ subtotalServicos: 100, subtotalPecas: 0, desconto: 500 });
    expect(r.servicosLiquido).toBe(0);
    expect(r.servicosLiquido).toBeGreaterThanOrEqual(0);
  });

  it("OS só de serviço absorve o desconto inteiro", () => {
    const r = repartirDescontoDaOrdem({ subtotalServicos: 1000, subtotalPecas: 0, desconto: 250 });
    expect(r.servicosLiquido).toBe(750);
    expect(r.pecasLiquido).toBe(0);
    expect(r.descontoPecas).toBe(0);
  });
});

describe("distribuirDescontoNosItens", () => {
  it("a soma bate EXATAMENTE com o desconto pedido", () => {
    const d = distribuirDescontoNosItens([75.46, 32.96, 83.59], 60.56);
    expect(d.reduce((a, b) => a + b, 0)).toBeCloseTo(60.56, 2);
  });

  // O resíduo do arredondamento vai para o item de MAIOR valor. Somá-lo no item
  // mais barato pode produzir vDesc > vProd, que a SEFAZ rejeita.
  it("nenhum item recebe desconto maior que o próprio valor", () => {
    const valores = [0.01, 0.01, 1000];
    const d = distribuirDescontoNosItens(valores, 999);
    d.forEach((desc, i) => expect(desc).toBeLessThanOrEqual(valores[i]));
    expect(d.reduce((a, b) => a + b, 0)).toBeCloseTo(999, 2);
  });

  it("terço indivisível não perde nem inventa centavo", () => {
    const d = distribuirDescontoNosItens([100, 100, 100], 100);
    expect(d.reduce((a, b) => a + b, 0)).toBeCloseTo(100, 2);
  });

  it("sem desconto, ninguém recebe nada", () => {
    expect(distribuirDescontoNosItens([10, 20], 0)).toEqual([0, 0]);
  });
});

// [F-DESC-03] O quadro "INFORMAÇÕES COMPLEMENTARES" saía vazio nas duas notas.
describe("montarInfoComplementar", () => {
  it("amarra a nota à OS e explica o desconto", () => {
    const t = montarInfoComplementar({
      osNumero: "OS-00075",
      descontoDaOrdem: 169.78,
      rotuloDesconto: "serviços",
    });
    expect(t).toContain("OS-00075");
    // O separador decimal é vírgula: quem lê a nota é brasileiro.
    expect(t).toContain("R$ 169,78");
  });

  it("sem nada a dizer, devolve null em vez de texto vazio", () => {
    // Quadro ausente é melhor que quadro em branco.
    expect(montarInfoComplementar({})).toBeNull();
    expect(montarInfoComplementar({ descontoDaOrdem: 0 })).toBeNull();
  });

  it("o pedido do cliente entra quando existe, e só então", () => {
    expect(montarInfoComplementar({ osNumero: "OS-1", pedidoCliente: "PC-99" })).toContain("PC-99");
    expect(montarInfoComplementar({ osNumero: "OS-1" })).not.toContain("Pedido");
  });

  // Nada de garantia, prazo ou condição de pagamento: o que a nota afirma
  // vincula a empresa, e isso é decisão do dono, não do código.
  it("não inventa cláusula em nome da empresa", () => {
    const t = montarInfoComplementar({ osNumero: "OS-1", descontoDaOrdem: 10 }) ?? "";
    expect(t.toLowerCase()).not.toMatch(/garantia|prazo|dias|vencimento/);
  });
});
