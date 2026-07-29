// Tradução do extrato do Pluggy para o formato do ERP.
//
// É o ponto onde um erro passa despercebido: o dado chega, entra no banco, e só aparece
// como número errado no financeiro semanas depois. Por isso as convenções (sinal do valor,
// quem é a contraparte, o que conta como Pix) estão travadas por teste.
import { describe, it, expect } from "vitest";
import {
  mapTransaction,
  accountSourceType,
  type PluggyTransaction,
} from "../../supabase/functions/_shared/banking/pluggy";

const base: PluggyTransaction = {
  id: "tx-pluggy-1",
  description: "PIX RECEBIDO",
  amount: 1500,
  date: "2026-07-20T10:30:00.000Z",
  type: "CREDIT",
};

describe("mapeamento de transação", () => {
  it("traz data, valor e descrição", () => {
    const r = mapTransaction(base);
    expect(r.transaction_date).toBe("2026-07-20");
    expect(r.amount).toBe(1500);
    expect(r.description).toBe("PIX RECEBIDO");
    expect(r.transaction_type).toBe("credit");
  });

  it("guarda o id do provedor como chave de deduplicação", () => {
    // A janela de sincronização sempre se sobrepõe ao que já veio; sem esta chave o
    // extrato duplicaria a cada rodada.
    expect(mapTransaction(base).bank_ref_id).toBe("tx-pluggy-1");
  });

  it("converte saída para valor positivo com tipo débito", () => {
    // O Pluggy usa sinal negativo para saída; o ERP separa valor e sentido. Misturar as
    // duas convenções faria soma de entradas subtrair sem nada parecer errado.
    const r = mapTransaction({ ...base, amount: -289.9, type: "DEBIT", description: "TARIFA" });
    expect(r.amount).toBe(289.9);
    expect(r.transaction_type).toBe("debit");
  });

  it("usa a descrição bruta quando não há descrição tratada", () => {
    const r = mapTransaction({ ...base, description: "", descriptionRaw: "TED 12345 FULANO" });
    expect(r.description).toBe("TED 12345 FULANO");
  });

  it("cai num rótulo neutro quando não há descrição nenhuma", () => {
    const r = mapTransaction({ ...base, description: "", descriptionRaw: null });
    expect(r.description).toBe("Sem descrição");
  });
});

describe("contraparte", () => {
  it("na entrada, é quem pagou", () => {
    const r = mapTransaction({
      ...base,
      type: "CREDIT",
      paymentData: {
        payer: { name: "Marina do Sol", documentNumber: { value: "12.345.678/0001-90" } },
        receiver: { name: "HBR Boats", documentNumber: { value: "99999999000199" } },
        paymentMethod: "PIX",
      },
    });
    expect(r.counterparty_name).toBe("Marina do Sol");
    expect(r.counterparty_document).toBe("12345678000190");
  });

  it("na saída, é quem recebeu", () => {
    const r = mapTransaction({
      ...base,
      type: "DEBIT",
      amount: -500,
      paymentData: {
        payer: { name: "HBR Boats" },
        receiver: { name: "Fornecedor XYZ", documentNumber: { value: "11.222.333/0001-44" } },
        paymentMethod: "TED",
      },
    });
    expect(r.counterparty_name).toBe("Fornecedor XYZ");
    expect(r.counterparty_document).toBe("11222333000144");
  });

  it("ignora documento curto demais para ser CPF ou CNPJ", () => {
    const r = mapTransaction({
      ...base,
      paymentData: { payer: { name: "X", documentNumber: { value: "123" } }, paymentMethod: "PIX" },
    });
    expect(r.counterparty_document).toBeNull();
  });
});

describe("identificação do Pix", () => {
  const e2e = "E12345678202607201030ABCDEFGHIJK";

  it("grava o EndToEndId quando o método é Pix e a referência tem o formato do SPI", () => {
    const r = mapTransaction({
      ...base,
      paymentData: { paymentMethod: "PIX", referenceNumber: e2e },
    });
    expect(r.pix_end_to_end_id).toBe(e2e);
  });

  it("não grava referência de TED como se fosse Pix", () => {
    const r = mapTransaction({
      ...base,
      paymentData: { paymentMethod: "TED", referenceNumber: "123456" },
    });
    expect(r.pix_end_to_end_id).toBeNull();
  });

  it("descarta referência que não tem formato de EndToEndId", () => {
    // Alguns bancos preenchem referenceNumber com um número interno mesmo em Pix.
    const r = mapTransaction({
      ...base,
      paymentData: { paymentMethod: "PIX", referenceNumber: "987654" },
    });
    expect(r.pix_end_to_end_id).toBeNull();
  });
});

describe("origem da conta", () => {
  it("separa fatura de cartão de conta corrente", () => {
    expect(accountSourceType({ id: "a", type: "CREDIT", name: "Cartão", balance: 0 })).toBe("credit_card");
    expect(accountSourceType({ id: "b", type: "BANK", name: "Conta", balance: 0 })).toBe("bank");
  });
});
