import { describe, it, expect } from "vitest";
import { buildEspelhoHtml, type EspelhoEmitter } from "../lib/danfe-espelho";

const emitter: EspelhoEmitter = {
  legal_name: "HBR Comercio Ltda",
  cnpj: "50057049000159",
  state_registration: "082745",
  tax_regime: "simples",
  crt: 1,
  street: "Rua das Embarcacoes",
  number: "10",
  district: "Centro",
  city_name: "Vitoria",
  state_code: "ES",
  postal_code: "29000000",
};

function makePayload(overrides: Record<string, any> = {}) {
  return {
    nature_operation: "Venda de mercadoria",
    operation_type: "saida",
    purpose: 1,
    consumer_final: false,
    recipient: {
      name: "Cliente Exemplo Ltda",
      document: "98765432000110",
      state_registration_indicator: 1,
      state_registration: "1234567",
      address: {
        street: "Avenida Parana", number: "1000", district: "Batel",
        city_name: "Curitiba", city_code: "4106902", state_code: "PR", postal_code: "80000000",
      },
    },
    items: [
      {
        code: "SKU-1", name: "Produto A", ncm: "85176259", cfop: "5102", unit: "UN",
        quantity: 2, unit_price: 150.5,
        taxes: {
          icms: { code: "102", origin: 0, aliquot: 0 },
          pis: { code: "49", aliquot: 0 },
          cofins: { code: "49", aliquot: 0 },
        },
      },
    ],
    payments: [{ method: "01", amount: 301 }],
    ...overrides,
  };
}

const parcelado = {
  payments: [{ method: "14", indicator: 1, amount: 301 }],
  billing: {
    invoice: { number: "1", original_amount: 301, discount_amount: 0, net_amount: 301 },
    installments: [
      { number: "001", due_date: "2026-08-20", amount: 150.5 },
      { number: "002", due_date: "2026-09-20", amount: 150.5 },
    ],
  },
};

describe("buildEspelhoHtml", () => {
  it("marca claramente que é pré-visualização SEM VALOR FISCAL", () => {
    const html = buildEspelhoHtml(makePayload(), emitter);
    expect(html).toContain("SEM VALOR FISCAL");
    expect(html).toContain("ESPELHO");
    // Deixa explícito que só a autorização da SEFAZ dá valor fiscal.
    expect(html).toMatch(/autorizada pela SEFAZ/i);
  });

  it("renderiza emitente, destinatário e itens com impostos resolvidos", () => {
    const html = buildEspelhoHtml(makePayload(), emitter);
    expect(html).toContain("HBR Comercio Ltda");
    expect(html).toContain("50.057.049/0001-59"); // CNPJ mascarado
    expect(html).toContain("Cliente Exemplo Ltda");
    expect(html).toContain("98.765.432/0001-10");
    expect(html).toContain("Produto A");
    expect(html).toContain("85176259"); // NCM
    expect(html).toContain("5102"); // CFOP
    expect(html).toContain("CSOSN 102");
    expect(html).toContain("301,00"); // total do item (2 × 150,50)
  });

  it("mostra o quadro Fatura/Duplicatas quando a venda é parcelada", () => {
    const html = buildEspelhoHtml(makePayload(parcelado), emitter);
    expect(html).toContain("Fatura / Duplicatas");
    expect(html).toContain("001");
    expect(html).toContain("002");
    expect(html).toContain("14 — Duplicata Mercantil");
  });

  it("formata o vencimento sem deslocar o dia (bug clássico de fuso)", () => {
    const html = buildEspelhoHtml(makePayload(parcelado), emitter);
    expect(html).toContain("20/08/2026");
    expect(html).toContain("20/09/2026");
    expect(html).not.toContain("19/08/2026");
  });

  it("não mostra o quadro de cobrança quando é à vista (sem billing)", () => {
    const html = buildEspelhoHtml(makePayload(), emitter);
    expect(html).not.toContain("Fatura / Duplicatas");
    expect(html).toContain("01 — Dinheiro");
  });

  it("escapa HTML dos dados (a página é aberta numa aba — nada de injeção)", () => {
    const html = buildEspelhoHtml(
      makePayload({
        recipient: {
          ...makePayload().recipient,
          name: '<script>alert("x")</script>',
        },
      }),
      emitter,
    );
    expect(html).not.toContain("<script>alert");
    expect(html).toContain("&lt;script&gt;");
  });

  it("informa o ambiente de emissão", () => {
    const html = buildEspelhoHtml(makePayload(), emitter, { environment: "producao" });
    expect(html).toContain("PRODUÇÃO");
  });

  it("mostra o número/série previstos quando informados", () => {
    const html = buildEspelhoHtml(makePayload(), emitter, { number: 16, series: 2, environment: "producao" });
    expect(html).toContain("NF-e nº 16");
    expect(html).toContain("série 2");
    expect(html).toContain("previsto"); // deixa claro que a reserva é na emissão
  });

  it("NÃO imprime o rótulo 'Inf. Contribuinte:' (a Contora o suprimiu p/ a HBR)", () => {
    // O espelho tem que espelhar a DANFE: como o renderizador deles deixou de
    // prefixar o quadro, manter o rótulo aqui recriaria a divergência.
    const html = buildEspelhoHtml(
      makePayload({ additional_info: "Referente a Ordem de Compra N. 05447." }),
      emitter,
    );
    expect(html).not.toContain("Inf. Contribuinte:");
    expect(html).toContain("Referente a Ordem de Compra N. 05447.");
    expect(html).toContain("Informações complementares"); // o título do quadro fica
  });

  it("não quebra com payload mínimo (sem itens, sem impostos, sem endereço)", () => {
    const html = buildEspelhoHtml({ items: [] }, {});
    expect(html).toContain("SEM VALOR FISCAL");
    expect(html).toContain("Nenhum item");
  });
});

describe("buildEspelhoHtml — infCpl igual ao DANFE", () => {
  const emitterMin = {};

  it("converte ';' em quebra de linha, como o DANFE da Contora faz", () => {
    const html = buildEspelhoHtml(
      { items: [], additional_info: "Pedido de Compra: 05447; Entrega parcial.; Documento emitido por ME ou EPP." },
      emitterMin,
    );
    expect(html).toContain("Pedido de Compra: 05447<br>Entrega parcial.<br>Documento emitido por ME ou EPP.");
  });

  it("o quadro começa direto pelo conteúdo, sem rótulo", () => {
    const html = buildEspelhoHtml({ items: [], additional_info: "Pedido de Compra: 05447" }, emitterMin);
    expect(html).not.toContain("Inf. Contribuinte:");
    expect(html).toContain("Pedido de Compra: 05447");
  });

  it("continua escapando HTML depois da conversão", () => {
    const html = buildEspelhoHtml({ items: [], additional_info: "<script>x</script>; ok" }, emitterMin);
    expect(html).not.toContain("<script>x");
    expect(html).toContain("&lt;script&gt;");
  });
});

describe("buildEspelhoHtml — desconto por item", () => {
  it("mostra o bruto, o desconto somado e o total líquido", () => {
    const html = buildEspelhoHtml({
      items: [{ code: "A", name: "Item", ncm: "1", cfop: "5102", quantity: 2, unit_price: 150.5, discount: 50.98 }],
      payments: [{ method: "17", amount: 250.02 }],
    }, {});
    expect(html).toContain("301,00"); // total dos produtos (bruto)
    expect(html).toContain("50,98");  // desconto
    expect(html).toContain("250,02"); // total da nota (líquido)
  });
});

describe("buildEspelhoHtml — despesas acessórias (vOutro)", () => {
  it("mostra as despesas acessórias e as soma no total", () => {
    const html = buildEspelhoHtml({
      items: [{ code: "A", name: "Item", ncm: "1", cfop: "6202", quantity: 1, unit_price: 1699.25, discount: 50.98, other_expenses: 214.28 }],
      payments: [{ method: "90", amount: 0 }],
    }, {});
    expect(html).toContain("Despesas acessórias");
    expect(html).toContain("214,28");
    // total da nota = 1699,25 − 50,98 + 214,28 = 1862,55
    expect(html).toContain("1.862,55");
  });
});
