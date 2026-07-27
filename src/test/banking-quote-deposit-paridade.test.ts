// Guarda de paridade entre as duas implementações do cálculo de sinal.
//
// O frontend usa `src/lib/quote-deposit.ts` e as edge functions usam o espelho em
// `_shared/banking/quote-deposit.ts`, porque Vite e Deno não compartilham módulos aqui.
// Espelho que diverge em silêncio já causou um bug real neste sistema (o PDF e o botão
// "Receber sinal" mostravam valores diferentes para a mesma condição). Este teste roda as
// duas implementações com as mesmas entradas e falha se elas discordarem.

import { describe, it, expect } from "vitest";
import {
  depositBaseFromOrder as baseFront,
  depositAmountFromPcts as amountFront,
  signalPctsFromInstallments as pctsFront,
  type DepositInstallment,
  type DepositOrderLike,
} from "@/lib/quote-deposit";
import {
  depositBaseFromOrder as baseEdge,
  depositAmountFromPcts as amountEdge,
  signalPctsFromInstallments as pctsEdge,
  expectedDepositAmount,
  expectedBalanceAmount,
} from "../../supabase/functions/_shared/banking/quote-deposit";

const ordens: DepositOrderLike[] = [
  // Orçamento real do sistema (ORÇ-00069): tem imposto, sem desconto.
  { labor_cost_total: 5600, parts_cost_total: 2005.40, tax_amount: 1403.59 },
  // Real (ORÇ-00061): tem desconto, só mão de obra.
  { labor_cost_total: 5860, parts_cost_total: 0, discount_amount: 220 },
  // Real (ORÇ-00070): mão de obra + peças, sem desconto nem imposto.
  { labor_cost_total: 1685, parts_cost_total: 3636.36 },
  // Com despesas e deslocamento não faturável.
  {
    labor_cost_total: 1000, parts_cost_total: 500, operational_cost_total: 200,
    travel_cost_total: 300, is_travel_billable: false, subcontract_cost_total: 100,
    discount_amount: 150, tax_amount: 50,
  },
  // Orçamento zerado (divisão por zero no discountRatio).
  { labor_cost_total: 0, parts_cost_total: 0 },
];

const condicoes: (DepositInstallment[] | null)[] = [
  null,
  [{ tipo: "aprovacao", services_pct: 50, parts_pct: 100, expenses_pct: 0 }],
  [{ days_after_approval: 0, percent: 30 }],
  [{ tipo: "entrega", services_pct: 100, parts_pct: 100 }], // sem parcela de sinal
  [{ tipo: "aprovacao", services_pct: 0, parts_pct: 0, expenses_pct: 0 }], // sinal zerado
];

describe("paridade frontend × edge function", () => {
  it("deriva a mesma base e o mesmo discountRatio", () => {
    for (const ordem of ordens) {
      expect(baseEdge(ordem)).toEqual(baseFront(ordem));
    }
  });

  it("calcula o mesmo valor de parcela", () => {
    for (const ordem of ordens) {
      const b = baseFront(ordem);
      for (const [svc, parts, exp] of [[50, 100, 0], [30, 30, 30], [100, 0, 50]]) {
        expect(amountEdge(b.laborCost, b.partsCost, b.expensesTotal, b.discountRatio, svc, parts, exp))
          .toBe(amountFront(b.laborCost, b.partsCost, b.expensesTotal, b.discountRatio, svc, parts, exp));
      }
    }
  });

  it("extrai a mesma parcela de sinal das condições de pagamento", () => {
    for (const cond of condicoes) {
      expect(pctsEdge(cond)).toEqual(pctsFront(cond));
    }
  });
});

describe("sinal esperado (usado pela conciliação)", () => {
  it("prefere a condição de pagamento quando ela define entrada", () => {
    const r = expectedDepositAmount(
      { labor_cost_total: 1000, parts_cost_total: 1000, grand_total: 2000 },
      [{ tipo: "aprovacao", services_pct: 50, parts_pct: 50 }],
      30,
    );
    expect(r).toEqual({ amount: 1000, source: "condicao" });
  });

  it("sem condição, usa a condição padrão da casa (100% materiais + 50% mão de obra)", () => {
    // Mão de obra 1.000 e peças 2.000 → sinal = 500 + 2.000 = 2.500.
    const r = expectedDepositAmount(
      { labor_cost_total: 1000, parts_cost_total: 2000, grand_total: 3000 },
      null,
      30,
    );
    expect(r).toEqual({ amount: 2500, source: "padrao" });
  });

  it("cai na condição padrão quando todas as parcelas são a prazo", () => {
    const r = expectedDepositAmount(
      { labor_cost_total: 1000, grand_total: 1000 },
      [{ tipo: "prazo", days_after_approval: 30, services_pct: 100, parts_pct: 100 }],
      30,
    );
    expect(r?.source).toBe("padrao");
  });

  it("parcela de entrega no dia 0 não é sinal", () => {
    // "Vence na entrega" é diferente de "vence na aprovação", mesmo com days=0. Sem essa
    // distinção o motor esperaria o valor da entrega como se fosse o sinal.
    const r = expectedDepositAmount(
      { labor_cost_total: 1000, parts_cost_total: 500, grand_total: 1500 },
      [{ tipo: "entrega", services_pct: 100, parts_pct: 100 }],
      30,
    );
    expect(r?.source).toBe("padrao"); // cai na condição padrão, não na parcela de entrega
  });

  it("devolve nulo quando não há como estimar", () => {
    expect(expectedDepositAmount({ grand_total: 0 }, null, 30)).toBeNull();
  });
});

describe("orçamentos reais com condição de pagamento (regressão)", () => {
  // A primeira versão da conciliação lia só `custom_payment_installments` e ignorava a
  // condição PRÉ-CADASTRADA, caindo no percentual padrão. O valor sugerido saía muito
  // longe do que o cliente combinou: no ORÇ-00069 dava R$ 2.702,70 em vez de R$ 5.692,25,
  // e na OS-00060 dava R$ 6.000 em vez de R$ 18.001,04. Estes casos travam a regressão.
  const condicao5050 = [
    { tipo: "aprovacao" as const, label: "Sinal", services_pct: 50, parts_pct: 100, expenses_pct: 100, days_after_approval: 0 },
    { tipo: "entrega" as const, label: "Saldo", services_pct: 50, parts_pct: 0, expenses_pct: 0, days_after_approval: 0 },
  ];

  it("ORÇ-00069: sinal é o da condição, não 30% do total", () => {
    const r = expectedDepositAmount(
      { labor_cost_total: 5600, parts_cost_total: 2005.40, tax_amount: 1403.59, grand_total: 9008.99 },
      condicao5050,
      30,
    );
    expect(r?.source).toBe("condicao");
    expect(r?.amount).toBeCloseTo(5692.25, 1);
  });

  it("OS-00060: bate com o valor que o orçamento mostra ao cliente", () => {
    const r = expectedDepositAmount(
      { labor_cost_total: 4110, parts_cost_total: 16450.67, discount_amount: 560.67, grand_total: 20000 },
      condicao5050,
      30,
    );
    expect(r?.source).toBe("condicao");
    expect(r?.amount).toBeCloseTo(18001.04, 1);
  });

  it("ORÇ-00070 sem condição própria: aplica a regra padrão da casa", () => {
    // Mão de obra 1.685 (50% = 842,50) + peças 3.636,36 (100%) = 4.478,86.
    // Antes o motor sugeria R$ 1.596,41 (30% liso), que não corresponde a nada praticado.
    const r = expectedDepositAmount(
      { labor_cost_total: 1685, parts_cost_total: 3636.36, grand_total: 5321.36 },
      null,
      30,
    );
    expect(r?.source).toBe("padrao");
    expect(r?.amount).toBeCloseTo(4478.86, 2);
  });

  it("saldo da entrega é o que sobra do sinal (os 50% restantes de mão de obra)", () => {
    const ordem = { labor_cost_total: 1685, parts_cost_total: 3636.36, grand_total: 5321.36 };
    const sinal = expectedDepositAmount(ordem, null, 30)!;
    expect(expectedBalanceAmount(ordem, sinal.amount)).toBeCloseTo(842.50, 2);
  });
});
