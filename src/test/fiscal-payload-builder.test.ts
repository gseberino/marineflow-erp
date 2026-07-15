import { describe, it, expect } from "vitest";
import {
  buildNfeDraftPayload,
  validateNfeDraftInput,
  DEFAULT_CFOP,
  type BuildNfePayloadInput,
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
