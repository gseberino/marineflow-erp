import { describe, it, expect } from "vitest";
import {
  buildNfeDraftPayload,
  buildItemTaxes,
  validateNfeDraftInput,
  DEFAULT_CFOP,
  computeCfop,
  findNatureOfOperation,
  NATURE_OF_OPERATION_OPTIONS,
  type BuildNfePayloadInput,
  type NfeItemInput,
} from "../../supabase/functions/_shared/fiscal/payload-builder";

function makeInput(overrides: Partial<BuildNfePayloadInput> = {}): BuildNfePayloadInput {
  return {
    recipient: {
      name: "Cliente Exemplo Ltda",
      document: "98.765.432/0001-10",
      email: "cliente@exemplo.com",
      address: {
        street: "Avenida Paraná",
        number: "1000",
        district: "Batel",
        cityName: "Curitiba",
        cityCode: "4106902",
        stateCode: "PR",
        postalCode: "80000-000",
      },
    },
    items: [
      { code: "SKU-1", name: "Produto A", ncm: "85176259", cfop: "5102", unit: "UN", quantity: 2, unitPrice: 150.5 },
    ],
    paymentMethod: "01",
    ...overrides,
  };
}

describe("buildNfeDraftPayload", () => {
  it("monta o payload com CPF/CNPJ e CEP só com dígitos", () => {
    const payload = buildNfeDraftPayload(makeInput()) as any;
    expect(payload.recipient.document).toBe("98765432000110");
    expect(payload.recipient.address.postal_code).toBe("80000000");
    expect(payload.nature_operation).toBe("Venda de mercadoria");
    expect(payload.operation_type).toBe("saida");
  });

  it("calcula consumer_final automaticamente por CPF (11 dígitos) vs CNPJ", () => {
    const cpfPayload = buildNfeDraftPayload(
      makeInput({ recipient: { ...makeInput().recipient, document: "123.456.789-09" } }),
    ) as any;
    expect(cpfPayload.consumer_final).toBe(true);

    const cnpjPayload = buildNfeDraftPayload(makeInput()) as any;
    expect(cnpjPayload.consumer_final).toBe(false);
  });

  it("respeita consumerFinal explícito quando informado", () => {
    const payload = buildNfeDraftPayload(makeInput({ consumerFinal: true })) as any;
    expect(payload.consumer_final).toBe(true);
  });

  it("usa CFOP padrão quando o item não informa", () => {
    const input = makeInput({
      items: [{ code: "X", name: "Item sem CFOP", ncm: "12345678", quantity: 1, unitPrice: 10 }],
    });
    const payload = buildNfeDraftPayload(input) as any;
    expect(payload.items[0].cfop).toBe(DEFAULT_CFOP);
    expect(payload.items[0].unit).toBe("UN");
  });

  it("soma quantidade*preço de todos os itens no pagamento", () => {
    const input = makeInput({
      items: [
        { code: "A", name: "Item A", ncm: "11111111", cfop: "5102", quantity: 2, unitPrice: 10 },
        { code: "B", name: "Item B", ncm: "22222222", cfop: "5102", quantity: 1, unitPrice: 5.555 },
      ],
    });
    const payload = buildNfeDraftPayload(input) as any;
    // 2*10 + 1*5.555 = 25.555 -> arredondado para 25.56
    expect(payload.payments[0].amount).toBe(25.56);
    expect(payload.payments[0].method).toBe("01");
  });

  it("usa número 'S/N' quando o endereço não informa número", () => {
    const input = makeInput();
    input.recipient.address.number = "";
    const payload = buildNfeDraftPayload(input) as any;
    expect(payload.recipient.address.number).toBe("S/N");
  });
});

describe("validateNfeDraftInput", () => {
  it("não retorna erros para um input completo e válido", () => {
    expect(validateNfeDraftInput(makeInput())).toEqual([]);
  });

  it("aponta campos obrigatórios do destinatário ausentes", () => {
    const input = makeInput();
    input.recipient.name = "";
    input.recipient.document = "";
    input.recipient.address.cityCode = "";
    const errors = validateNfeDraftInput(input);
    expect(errors).toContain("Nome do destinatário é obrigatório.");
    expect(errors).toContain("CPF/CNPJ do destinatário é obrigatório.");
    expect(errors.some((e) => e.includes("Código IBGE"))).toBe(true);
  });

  it("rejeita CPF/CNPJ com quantidade de dígitos inválida (nem 11 nem 14)", () => {
    const input = makeInput();
    input.recipient.document = "123"; // typo/garbage — antes passava por só checar "tem dígito"
    const errors = validateNfeDraftInput(input);
    expect(errors).toContain("CPF/CNPJ do destinatário deve ter 11 (CPF) ou 14 (CNPJ) dígitos.");
  });

  it("aceita CPF (11 dígitos) e CNPJ (14 dígitos) válidos quanto ao tamanho", () => {
    const cpfInput = makeInput({ recipient: { ...makeInput().recipient, document: "12345678909" } });
    expect(validateNfeDraftInput(cpfInput)).toEqual([]);

    const cnpjInput = makeInput(); // fixture já usa CNPJ de 14 dígitos
    expect(validateNfeDraftInput(cnpjInput)).toEqual([]);
  });

  it("exige ao menos um item e valida quantidade/valor/NCM por item", () => {
    expect(validateNfeDraftInput(makeInput({ items: [] }))).toContain("Adicione pelo menos um item.");

    const errors = validateNfeDraftInput(
      makeInput({ items: [{ code: "X", name: "", ncm: "", quantity: 0, unitPrice: 0 }] }),
    );
    expect(errors).toContain("Item 1: descrição é obrigatória.");
    expect(errors).toContain("Item 1: NCM é obrigatório.");
    expect(errors).toContain("Item 1: quantidade deve ser maior que zero.");
    expect(errors).toContain("Item 1: valor unitário deve ser maior que zero.");
  });

  it("exige forma de pagamento", () => {
    const errors = validateNfeDraftInput(makeInput({ paymentMethod: "" }));
    expect(errors).toContain("Forma de pagamento é obrigatória.");
  });
});

describe("computeCfop", () => {
  it("usa prefixo 5 (saída, mesmo estado) quando UF emitente e destinatário coincidem", () => {
    expect(computeCfop("102", "saida", "SC", "SC")).toBe("5102");
  });

  it("usa prefixo 6 (saída, interestadual) quando as UFs divergem", () => {
    expect(computeCfop("102", "saida", "SC", "SP")).toBe("6102");
  });

  it("usa prefixo 1 (entrada, mesmo estado) e 2 (entrada, interestadual)", () => {
    expect(computeCfop("202", "entrada", "SC", "SC")).toBe("1202");
    expect(computeCfop("202", "entrada", "SC", "SP")).toBe("2202");
  });

  it("é case-insensitive e tolera espaços na UF", () => {
    expect(computeCfop("102", "saida", " sc ", "Sc")).toBe("5102");
  });

  it("assume interestadual (mais conservador) quando alguma UF está ausente", () => {
    expect(computeCfop("102", "saida", null, "SC")).toBe("6102");
    expect(computeCfop("102", "saida", "SC", undefined)).toBe("6102");
    expect(computeCfop("202", "entrada", null, null)).toBe("2202");
  });
});

describe("findNatureOfOperation / NATURE_OF_OPERATION_OPTIONS", () => {
  it("resolve pelo value exato", () => {
    const found = findNatureOfOperation("devolucao_compra");
    expect(found.natureOperation).toBe("Devolução de compra");
    expect(found.baseCfopCode).toBe("202");
    expect(found.operationType).toBe("saida");
  });

  it("cai em 'venda' (primeira opção) para value desconhecido ou ausente", () => {
    expect(findNatureOfOperation("algo-inexistente").value).toBe("venda");
    expect(findNatureOfOperation(undefined).value).toBe("venda");
    expect(findNatureOfOperation(null).value).toBe("venda");
  });

  it("devolução ao fornecedor e devolução do cliente usam o mesmo CFOP-base (202), só muda entrada/saída", () => {
    const aoFornecedor = findNatureOfOperation("devolucao_compra");
    const doCliente = findNatureOfOperation("devolucao_venda");
    expect(aoFornecedor.baseCfopCode).toBe(doCliente.baseCfopCode);
    expect(aoFornecedor.operationType).toBe("saida");
    expect(doCliente.operationType).toBe("entrada");
  });

  it("toda opção tem um label, natureOperation e baseCfopCode não vazios", () => {
    for (const opt of NATURE_OF_OPERATION_OPTIONS) {
      expect(opt.label.length).toBeGreaterThan(0);
      expect(opt.natureOperation.length).toBeGreaterThan(0);
      expect(opt.baseCfopCode).toMatch(/^\d{3}$/);
    }
  });
});

describe("buildNfeDraftPayload — operationType", () => {
  it("usa 'saida' por padrão quando operationType não é informado", () => {
    const payload = buildNfeDraftPayload(makeInput()) as any;
    expect(payload.operation_type).toBe("saida");
  });

  it("propaga operationType='entrada' quando informado (devolução recebida do cliente)", () => {
    const payload = buildNfeDraftPayload(makeInput({ operationType: "entrada" })) as any;
    expect(payload.operation_type).toBe("entrada");
  });
});

describe("buildItemTaxes", () => {
  const base: NfeItemInput = { code: "X", name: "P", ncm: "85369090", quantity: 1, unitPrice: 10 };

  it("retorna undefined quando não há CSOSN (mantém compat com fluxo antigo)", () => {
    expect(buildItemTaxes(base)).toBeUndefined();
  });

  it("monta icms/pis/cofins no formato da Contora", () => {
    const t = buildItemTaxes({ ...base, csosn: "102", origin: 0, icmsRate: 0, pisCst: "49", pisRate: 0, cofinsCst: "49", cofinsRate: 0 }) as any;
    expect(t.icms).toEqual({ code: "102", origin: 0, aliquot: 0 });
    expect(t.pis).toEqual({ code: "49", aliquot: 0 });
    expect(t.cofins).toEqual({ code: "49", aliquot: 0 });
    expect(t.ipi).toBeUndefined();
  });

  it("inclui ipi só quando a alíquota é maior que zero", () => {
    const t = buildItemTaxes({ ...base, csosn: "500", ipiRate: 5 }) as any;
    expect(t.ipi).toEqual({ code: "99", aliquot: 5 });
  });

  it("usa CST '49' de PIS/COFINS por padrão quando não informado (valor com que a 1ª NF-e autorizou)", () => {
    const t = buildItemTaxes({ ...base, csosn: "400" }) as any;
    expect(t.pis.code).toBe("49");
    expect(t.cofins.code).toBe("49");
  });
});

describe("buildNfeDraftPayload — purpose / IE / infCpl / devolução", () => {
  it("purpose default = 1 (normal) e propaga 4 (devolução)", () => {
    expect((buildNfeDraftPayload(makeInput()) as any).purpose).toBe(1);
    expect((buildNfeDraftPayload(makeInput({ purpose: 4 })) as any).purpose).toBe(4);
  });

  it("indicador de IE default 9; envia state_registration só quando contribuinte (1) com IE", () => {
    const semIE = buildNfeDraftPayload(makeInput()) as any;
    expect(semIE.recipient.state_registration_indicator).toBe(9);
    expect(semIE.recipient.state_registration).toBeUndefined();

    const contrib = buildNfeDraftPayload(
      makeInput({ recipient: { ...makeInput().recipient, stateRegistrationIndicator: 1, stateRegistration: "123.456.789" } }),
    ) as any;
    expect(contrib.recipient.state_registration_indicator).toBe(1);
    expect(contrib.recipient.state_registration).toBe("123456789");
  });

  it("propaga presence_indicator e additional_info quando informados", () => {
    const p = buildNfeDraftPayload(makeInput({ presenceIndicator: 9, additionalInfo: "  Simples Nacional  " })) as any;
    expect(p.presence_indicator).toBe(9);
    expect(p.additional_info).toBe("Simples Nacional");
  });

  it("envia referenced_access_keys só quando há chave (devolução)", () => {
    expect((buildNfeDraftPayload(makeInput()) as any).referenced_access_keys).toBeUndefined();
    const p = buildNfeDraftPayload(makeInput({ referencedAccessKey: "4226 0550 0570 4900 0159 5500 1000 0001 1113 8202 6000" })) as any;
    expect(p.referenced_access_keys).toEqual(["42260550057049000159550010000001111382026000"]);
  });

  it("monta taxes no item quando o item traz CSOSN", () => {
    const input = makeInput({
      items: [{ code: "A", name: "Item", ncm: "85369090", cfop: "5102", quantity: 1, unitPrice: 10, csosn: "102", origin: 0, pisRate: 0, cofinsRate: 0 }],
    });
    const payload = buildNfeDraftPayload(input) as any;
    expect(payload.items[0].taxes.icms.code).toBe("102");
  });
});

describe("buildNfeDraftPayload — sanitização de campos (leiaute 4.00)", () => {
  it("envia cEAN/cEANTrib: GTIN válido do barcode, senão 'SEM GTIN'", () => {
    const comGtin = buildNfeDraftPayload(makeInput({
      items: [{ code: "A", name: "Item", ncm: "85369090", cfop: "5102", quantity: 1, unitPrice: 10, barcode: "7891234567895" }],
    })) as any;
    expect(comGtin.items[0].cean).toBe("7891234567895");
    expect(comGtin.items[0].cean_trib).toBe("7891234567895");

    const semGtin = buildNfeDraftPayload(makeInput()) as any; // fixture sem barcode
    expect(semGtin.items[0].cean).toBe("SEM GTIN");
  });

  it("trunca nome do destinatário em 60 e descrição do item em 120", () => {
    const p = buildNfeDraftPayload(makeInput({
      recipient: { ...makeInput().recipient, name: "X".repeat(80) },
      items: [{ code: "A", name: "Y".repeat(140), ncm: "85369090", cfop: "5102", quantity: 1, unitPrice: 10 }],
    })) as any;
    expect(p.recipient.name.length).toBe(60);
    expect(p.items[0].name.length).toBe(120);
  });

  it("apara espaços e colapsa espaços internos nos textos", () => {
    const p = buildNfeDraftPayload(makeInput({
      items: [{ code: "  A  ", name: "Item   com   espaços ", ncm: "85369090", cfop: "5102", quantity: 1, unitPrice: 10 }],
    })) as any;
    expect(p.items[0].name).toBe("Item com espaços");
    expect(p.items[0].code).toBe("A");
  });

  it("trunca a unidade comercial em 6 caracteres", () => {
    const p = buildNfeDraftPayload(makeInput({
      items: [{ code: "A", name: "Item", ncm: "85369090", cfop: "5102", unit: "UNIDADE", quantity: 1, unitPrice: 10 }],
    })) as any;
    expect(p.items[0].unit).toBe("UNIDAD"); // 6 chars
  });
});

describe("buildNfeDraftPayload — sem pagamento (devolução/remessa)", () => {
  it("força tPag=90 (Sem Pagamento) e valor 0 quando noPayment=true", () => {
    const p = buildNfeDraftPayload(makeInput({ noPayment: true, paymentMethod: "17" })) as any;
    expect(p.payments).toEqual([{ method: "90", amount: 0 }]);
  });

  it("mantém a forma de pagamento e o total quando é venda (noPayment ausente)", () => {
    const p = buildNfeDraftPayload(makeInput({ paymentMethod: "17" })) as any;
    expect(p.payments[0].method).toBe("17");
    expect(p.payments[0].amount).toBeGreaterThan(0);
  });
});

describe("NATURE_OF_OPERATION_OPTIONS — hasPayment", () => {
  it("só a venda tem pagamento; devolução e remessas são Sem Pagamento", () => {
    expect(findNatureOfOperation("venda").hasPayment).toBe(true);
    for (const v of ["devolucao_compra", "devolucao_venda", "remessa_conserto", "remessa_bonificacao", "remessa_demonstracao"]) {
      expect(findNatureOfOperation(v).hasPayment).toBe(false);
    }
  });
});

describe("buildNfeDraftPayload — referência por item (devolução VC02-14)", () => {
  it("monta referenced_document {access_key,item} por item quando informado", () => {
    const p = buildNfeDraftPayload(makeInput({
      purpose: 4,
      items: [{
        code: "A", name: "Item", ncm: "85369090", cfop: "1202", quantity: 1, unitPrice: 10,
        referencedKey: "4226 0750 0570 4900 0159 5500 2000 0000 0117 3735 9835", referencedItemNumber: 1,
      }],
    })) as any;
    expect(p.items[0].referenced_document).toEqual({
      access_key: "42260750057049000159550020000000011737359835", item: 1,
    });
  });

  it("agrega as chaves por item em referenced_access_keys (nível da nota)", () => {
    const p = buildNfeDraftPayload(makeInput({
      items: [
        { code: "A", name: "A", ncm: "85369090", cfop: "1202", quantity: 1, unitPrice: 10, referencedKey: "42260750057049000159550020000000011737359835", referencedItemNumber: 1 },
        { code: "B", name: "B", ncm: "85369090", cfop: "1202", quantity: 1, unitPrice: 5, referencedKey: "42260750057049000159550020000000011737359835", referencedItemNumber: 2 },
      ],
    })) as any;
    expect(p.referenced_access_keys).toEqual(["42260750057049000159550020000000011737359835"]);
  });

  it("não inclui referenced_document quando falta chave ou nItem", () => {
    const p = buildNfeDraftPayload(makeInput({
      items: [{ code: "A", name: "Item", ncm: "85369090", cfop: "5102", quantity: 1, unitPrice: 10 }],
    })) as any;
    expect(p.items[0].referenced_document).toBeUndefined();
    expect(p.referenced_access_keys).toBeUndefined();
  });
});

describe("validateNfeDraftInput — NCM/CFOP/CEP", () => {
  it("rejeita NCM que não tem 8 dígitos", () => {
    const errors = validateNfeDraftInput(makeInput({
      items: [{ code: "A", name: "Item", ncm: "8536909", cfop: "5102", quantity: 1, unitPrice: 10 }],
    }));
    expect(errors).toContain("Item 1: NCM deve ter 8 dígitos.");
  });

  it("rejeita CFOP que não tem 4 dígitos", () => {
    const errors = validateNfeDraftInput(makeInput({
      items: [{ code: "A", name: "Item", ncm: "85369090", cfop: "510", quantity: 1, unitPrice: 10 }],
    }));
    expect(errors).toContain("Item 1: CFOP deve ter 4 dígitos.");
  });

  it("rejeita CEP que não tem 8 dígitos", () => {
    const input = makeInput();
    input.recipient.address.postalCode = "8000000"; // 7 dígitos
    expect(validateNfeDraftInput(input)).toContain("CEP deve ter 8 dígitos.");
  });
});

describe("validateNfeDraftInput — IE do contribuinte", () => {
  it("exige IE quando indicador de IE = 1 e não há IE", () => {
    const input = makeInput({ recipient: { ...makeInput().recipient, stateRegistrationIndicator: 1, stateRegistration: "" } });
    expect(validateNfeDraftInput(input)).toContain(
      "Inscrição Estadual do destinatário é obrigatória quando ele é contribuinte do ICMS (indicador 1).",
    );
  });

  it("não exige IE para não contribuinte (9) nem isento (2)", () => {
    expect(validateNfeDraftInput(makeInput({ recipient: { ...makeInput().recipient, stateRegistrationIndicator: 9 } }))).toEqual([]);
    expect(validateNfeDraftInput(makeInput({ recipient: { ...makeInput().recipient, stateRegistrationIndicator: 2 } }))).toEqual([]);
  });
});

describe("buildNfeDraftPayload — cobrança (cobr = fatura + duplicatas)", () => {
  // total do makeInput padrão = 2 × 150.50 = 301.00
  const future = (days: number) => new Date(Date.now() + days * 86400000).toISOString().slice(0, 10);

  it("monta billing (fatura + duplicatas) e pag Duplicata Mercantil (14) quando há parcelas", () => {
    const p = buildNfeDraftPayload(makeInput({
      installments: [
        { dueDate: future(30), amount: 150.5 },
        { dueDate: future(60), amount: 150.5 },
      ],
    })) as any;
    expect(p.billing.invoice).toEqual({ number: "1", original_amount: 301, discount_amount: 0, net_amount: 301 });
    expect(p.billing.installments).toEqual([
      { number: "001", due_date: future(30), amount: 150.5 },
      { number: "002", due_date: future(60), amount: 150.5 },
    ]);
    // pag: método 14 (Duplicata Mercantil), a prazo (indicator 1), somando net_amount.
    expect(p.payments).toEqual([{ method: "14", indicator: 1, amount: 301 }]);
  });

  it("fatura reflete o desconto por item: original = bruto+despesas, desconto = vDesc, líquido = vNF", () => {
    // 1 item: 2 × 150.50 = 301 bruto; desconto 51 → vNF 250.
    const p = buildNfeDraftPayload(makeInput({
      items: [{ code: "SKU-1", name: "Produto A", ncm: "85176259", cfop: "5102", unit: "UN", quantity: 2, unitPrice: 150.5, discount: 51 }],
      installments: [
        { dueDate: future(30), amount: 125 },
        { dueDate: future(60), amount: 125 },
      ],
    })) as any;
    expect(p.billing.invoice).toEqual({ number: "1", original_amount: 301, discount_amount: 51, net_amount: 250 });
    // Regra da Contora: net_amount = original_amount − discount_amount.
    expect(p.billing.invoice.net_amount).toBe(p.billing.invoice.original_amount - p.billing.invoice.discount_amount);
    // Soma das duplicatas e do pagamento (14) = net_amount.
    const soma = p.billing.installments.reduce((s: number, d: any) => s + d.amount, 0);
    expect(Math.round(soma * 100) / 100).toBe(250);
    expect(p.payments).toEqual([{ method: "14", indicator: 1, amount: 250 }]);
  });

  it("a soma das duplicatas bate EXATAMENTE com o net_amount (ajuste de centavos na última)", () => {
    // 301.00 / 3 = 100.333… → 100.33 + 100.33 + 100.34
    const p = buildNfeDraftPayload(makeInput({
      installments: [
        { dueDate: future(30), amount: 100.33 },
        { dueDate: future(60), amount: 100.33 },
        { dueDate: future(90), amount: 100.33 },
      ],
    })) as any;
    const soma = p.billing.installments.reduce((s: number, d: any) => s + d.amount, 0);
    expect(Math.round(soma * 100) / 100).toBe(301);
    expect(p.billing.installments[2].amount).toBe(100.34);
  });

  it("à vista (sem installments) mantém pagamento único e NÃO gera billing", () => {
    const p = buildNfeDraftPayload(makeInput({ paymentMethod: "17" })) as any;
    expect(p.billing).toBeUndefined();
    expect(p.payments).toEqual([{ method: "17", amount: 301 }]);
  });

  it("devolução/remessa (noPayment) ignora parcelas e força tPag=90", () => {
    const p = buildNfeDraftPayload(makeInput({
      noPayment: true,
      installments: [{ dueDate: future(30), amount: 301 }],
    })) as any;
    expect(p.billing).toBeUndefined();
    expect(p.payments).toEqual([{ method: "90", amount: 0 }]);
  });

  it("respeita invoiceNumber (nFat) quando informado", () => {
    const p = buildNfeDraftPayload(makeInput({
      invoiceNumber: "FAT-000214",
      installments: [{ dueDate: future(30), amount: 301 }],
    })) as any;
    expect(p.billing.invoice.number).toBe("FAT-000214");
  });
});

describe("validateNfeDraftInput — parcelas (duplicatas)", () => {
  // A validação compara com "hoje" no fuso de Brasília (UTC-3). Os helpers
  // precisam usar a MESMA referência, senão o teste vira uma bomba-relógio:
  // calculando em UTC, "ontem" e "hoje" se cruzam entre 21h e 24h locais.
  const brDate = (offsetDays: number) =>
    new Date(Date.now() - 3 * 60 * 60 * 1000 + offsetDays * 86400000).toISOString().slice(0, 10);
  const future = (days: number) => brDate(days);
  const past = (days: number) => brDate(-days);

  it("aceita parcelas válidas (crescentes, futuras, valor > 0)", () => {
    const errors = validateNfeDraftInput(makeInput({
      installments: [
        { dueDate: future(30), amount: 150.5 },
        { dueDate: future(60), amount: 150.5 },
      ],
    }));
    expect(errors).toEqual([]);
  });

  it("rejeita vencimento anterior à emissão", () => {
    const errors = validateNfeDraftInput(makeInput({ installments: [{ dueDate: past(1), amount: 301 }] }));
    expect(errors.some((e) => e.includes("anterior à data de emissão"))).toBe(true);
  });

  it("rejeita vencimentos fora de ordem crescente", () => {
    const errors = validateNfeDraftInput(makeInput({
      installments: [
        { dueDate: future(60), amount: 150.5 },
        { dueDate: future(30), amount: 150.5 },
      ],
    }));
    expect(errors.some((e) => e.includes("ordem crescente"))).toBe(true);
  });

  it("rejeita parcela com valor <= 0", () => {
    const errors = validateNfeDraftInput(makeInput({ installments: [{ dueDate: future(30), amount: 0 }] }));
    expect(errors.some((e) => e.includes("valor deve ser maior que zero"))).toBe(true);
  });

  it("rejeita mais de 120 parcelas", () => {
    const many = Array.from({ length: 121 }, (_, i) => ({ dueDate: future(30 + i), amount: 1 }));
    const errors = validateNfeDraftInput(makeInput({ installments: many }));
    expect(errors).toContain("Máximo de 120 parcelas (duplicatas).");
  });
});

describe("validateNfeDraftInput — fuso na data de vencimento", () => {
  it("aceita vencimento para HOJE no fuso de Brasília (a edge roda em UTC)", () => {
    // A edge function roda em UTC. Usando a data UTC, uma emissão feita depois
    // das 21h (quando o UTC já virou o dia seguinte) recusaria por engano um
    // vencimento para hoje. Este caso trava essa regressão.
    const hojeBrasilia = new Date(Date.now() - 3 * 60 * 60 * 1000).toISOString().slice(0, 10);
    const errors = validateNfeDraftInput(makeInput({ installments: [{ dueDate: hojeBrasilia, amount: 301 }] }));
    expect(errors).toEqual([]);
  });
});

describe("buildNfeDraftPayload — pedido de compra do cliente (grupo compra)", () => {
  it("envia purchase.order (→ compra/xPed) quando informado", () => {
    const p = buildNfeDraftPayload(makeInput({ purchaseOrder: "OC-05447" })) as any;
    expect(p.purchase).toEqual({ order: "OC-05447" });
  });

  it("omite o grupo quando não há pedido", () => {
    expect((buildNfeDraftPayload(makeInput()) as any).purchase).toBeUndefined();
    expect((buildNfeDraftPayload(makeInput({ purchaseOrder: "   " })) as any).purchase).toBeUndefined();
  });

  it("respeita o limite de 60 do compra/xPed", () => {
    const p = buildNfeDraftPayload(makeInput({ purchaseOrder: "X".repeat(80) })) as any;
    expect(p.purchase.order.length).toBe(60);
  });
});

describe("buildNfeDraftPayload — desconto por item (vDesc)", () => {
  // makeInput padrão: 1 item, 2 × 150,50 = 301,00 bruto.
  it("emite discount no item e abate do total (payment = líquido)", () => {
    const p = buildNfeDraftPayload(makeInput({
      items: [{ code: "A", name: "Item", ncm: "85176259", cfop: "5102", quantity: 2, unitPrice: 150.5, discount: 50.98 }],
      paymentMethod: "17",
    })) as any;
    expect(p.items[0].discount).toBe(50.98);
    // 301,00 − 50,98 = 250,02
    expect(p.payments[0].amount).toBe(250.02);
  });

  it("desconto reflete no net_amount das duplicatas (parcelado)", () => {
    const future = (d: number) => new Date(Date.now() - 3 * 3600e3 + d * 86400e3).toISOString().slice(0, 10);
    const p = buildNfeDraftPayload(makeInput({
      items: [{ code: "A", name: "Item", ncm: "85176259", cfop: "5102", quantity: 2, unitPrice: 150.5, discount: 50.98 }],
      installments: [{ dueDate: future(30), amount: 125.01 }, { dueDate: future(60), amount: 125.01 }],
    })) as any;
    expect(p.billing.invoice.net_amount).toBe(250.02);
    expect(p.payments[0].amount).toBe(250.02); // method 14 soma o líquido
  });

  it("não emite discount quando é zero/ausente", () => {
    const p = buildNfeDraftPayload(makeInput()) as any;
    expect(p.items[0].discount).toBeUndefined();
    expect(p.payments[0].amount).toBe(301);
  });

  it("valida desconto maior que o valor do item", () => {
    const errors = validateNfeDraftInput(makeInput({
      items: [{ code: "A", name: "Item", ncm: "85176259", cfop: "5102", quantity: 1, unitPrice: 100, discount: 150 }],
    }));
    expect(errors.some((e) => e.includes("maior que o valor do item"))).toBe(true);
  });
});

describe("buildNfeDraftPayload — despesas acessórias (vOutro)", () => {
  it("emite other_expenses e SOMA ao total (exemplo da Contora)", () => {
    // Contora: vProd 1000, vOutro 50 -> vNF 1050 (devolução).
    const p = buildNfeDraftPayload(makeInput({
      natureOperation: "Devolução de compra", purpose: 4, noPayment: true,
      items: [{ code: "LP-28", name: "TOMADA", ncm: "85369090", cfop: "5202",
        quantity: 10, unitPrice: 100, otherExpenses: 50 }],
    })) as any;
    expect(p.items[0].other_expenses).toBe(50);
    // noPayment (devolução) → tPag 90 amount 0; o vOutro entra no valor dos itens.
    expect(p.payments).toEqual([{ method: "90", amount: 0 }]);
  });

  it("vNF = vProd − vDesc + vOutro no pagamento (venda com IPI em despesas)", () => {
    const p = buildNfeDraftPayload(makeInput({
      items: [{ code: "A", name: "Item", ncm: "85176259", cfop: "5102",
        quantity: 1, unitPrice: 1000, discount: 100, otherExpenses: 80 }],
      paymentMethod: "17",
    })) as any;
    // 1000 − 100 + 80 = 980
    expect(p.payments[0].amount).toBe(980);
  });

  it("devolução Kamell: IPI da compra em other_expenses (NF 40.480 item 1)", () => {
    // Item real: vProd 1699,25, vDesc 50,98, vIPI 214,28 → vNF = 1862,55.
    const p = buildNfeDraftPayload(makeInput({
      natureOperation: "Devolução de compra", purpose: 4, noPayment: true,
      items: [{ code: "2391", name: "ECRA TOUCH", ncm: "85285900", cfop: "6202",
        quantity: 1, unitPrice: 1699.25, discount: 50.98, otherExpenses: 214.28 }],
    })) as any;
    expect(p.items[0].discount).toBe(50.98);
    expect(p.items[0].other_expenses).toBe(214.28);
  });

  it("não emite other_expenses quando é zero/ausente", () => {
    const p = buildNfeDraftPayload(makeInput()) as any;
    expect(p.items[0].other_expenses).toBeUndefined();
  });

  it("valida despesas acessórias negativas", () => {
    const errors = validateNfeDraftInput(makeInput({
      items: [{ code: "A", name: "Item", ncm: "85176259", cfop: "5102", quantity: 1, unitPrice: 100, otherExpenses: -5 }],
    }));
    expect(errors.some((e) => e.includes("despesas acessórias não podem ser negativas"))).toBe(true);
  });
});
