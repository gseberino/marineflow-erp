// Tradução do extrato do Pluggy para o formato do ERP.
//
// É o ponto onde um erro passa despercebido: o dado chega, entra no banco, e só aparece
// como número errado no financeiro semanas depois. Por isso as convenções (sinal do valor,
// quem é a contraparte, o que conta como Pix) estão travadas por teste.
import { describe, it, expect } from "vitest";
import {
  mapTransaction, motivoDeCreditoEmCartao,
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

describe('dados de identificação que o provedor manda e o código descartava', () => {
  // O gestor reclamou de ter que abrir o internet banking para saber de quem era o
  // lançamento. A causa era o tipo TypeScript declarar só nome e documento dentro de
  // payer/receiver — o JSON chegava inteiro e o código lia dois campos.
  const base = {
    id: 'tx-1', description: 'TRANSF ENVIADA PIX', amount: 5000,
    date: '2026-07-20T00:00:00Z', type: 'DEBIT' as const,
  };

  it('guarda banco, agência e conta de quem recebeu', () => {
    const r = mapTransaction({
      ...base,
      paymentData: {
        receiver: {
          name: 'MARINE EXPRESS LTDA',
          branchNumber: '0001', accountNumber: '12345-6',
          routingNumber: '336', routingNumberISPB: '31872495',
          documentNumber: { value: '68.904.101/0001-20' },
        },
        paymentMethod: 'PIX',
        reason: 'Pagamento peças OS-00060',
      },
    } as never);

    expect(r.counterparty_bank).toBe('336');
    expect(r.counterparty_branch).toBe('0001');
    expect(r.counterparty_account).toBe('12345-6');
    expect(r.payment_method).toBe('PIX');
    // A mensagem do pagador costuma dizer a que a despesa se refere.
    expect(r.payment_reason).toBe('Pagamento peças OS-00060');
  });

  it('identifica compra em loja pelo estabelecimento', () => {
    // Compra em estabelecimento não tem contraparte de Pix, tem merchant — era por isso
    // que 1.086 lançamentos de cartão ficavam sem identificação nenhuma.
    const r = mapTransaction({
      ...base,
      description: 'EC *NETFLIX SAO PAULO BRA',
      merchant: {
        name: 'Netflix', businessName: 'NETFLIX ENTRETENIMENTO BRASIL LTDA.',
        cnpj: '13.590.585/0001-99', category: 'Video Streaming',
      },
    } as never, 'credit_card');

    expect(r.merchant_name).toBe('NETFLIX ENTRETENIMENTO BRASIL LTDA.');
    expect(r.merchant_document).toBe('13590585000199');
    // A razão social identifica melhor que o histórico do terminal.
    expect(r.counterparty_name).toBe('NETFLIX ENTRETENIMENTO BRASIL LTDA.');
    expect(r.counterparty_document).toBe('13590585000199');
  });

  it('quem o banco nomeou tem precedência sobre o estabelecimento', () => {
    const r = mapTransaction({
      ...base,
      paymentData: { receiver: { name: 'FORNECEDOR REAL', documentNumber: { value: '68904101000120' } } },
      merchant: { businessName: 'ADQUIRENTE INTERMEDIARIA', cnpj: '00000000000191' },
    } as never);
    expect(r.counterparty_name).toBe('FORNECEDOR REAL');
    expect(r.counterparty_document).toBe('68904101000120');
  });

  it('registra a parcela da compra no cartão', () => {
    const r = mapTransaction({
      ...base,
      creditCardMetadata: { installmentNumber: 3, totalInstallments: 6, cardNumber: '1234' },
    } as never, 'credit_card');
    expect(r.installment_label).toBe('3/6');
  });

  it('não inventa campo quando o provedor não manda', () => {
    const r = mapTransaction(base as never);
    expect(r.counterparty_bank).toBeNull();
    expect(r.merchant_name).toBeNull();
    expect(r.installment_label).toBeNull();
    expect(r.payment_reason).toBeNull();
  });
});

describe('crédito em cartão nunca é receita', () => {
  // O usuário achou olhando "PAGAMENTO RECEBIDO": 121 lançamentos, R$ 105.672, esperando
  // na fila prontos para virar receita falsa. São a outra perna do pagamento da fatura —
  // o mesmo dinheiro que já sai da conta corrente.
  it('pagamento da fatura sai da fila com o motivo escrito', () => {
    const m = motivoDeCreditoEmCartao('credit_card', 'credit', 'PAGAMENTO RECEBIDO');
    expect(m).toContain('já está contada na conta corrente');
  });

  it('estorno de compra abate despesa, não vira receita', () => {
    expect(motivoDeCreditoEmCartao('credit_card', 'credit', 'CREDITO DE "MERCADOLIVRE*7PRODUTOS'))
      .toContain('Estorno');
  });

  it('ajuste do banco também não é receita', () => {
    for (const d of ['CREDITO DE ATRASO', 'ENCERRAMENTO DE DIVIDA', 'CREDITO DE ROTATIVO']) {
      expect(motivoDeCreditoEmCartao('credit_card', 'credit', d)).toBeTruthy();
    }
  });

  it('NÃO mexe em entrada de conta corrente — ali receita existe', () => {
    // A regra vale pela ORIGEM. Um Pix recebido na conta é receita de verdade e não pode
    // sair da fila por engano.
    expect(motivoDeCreditoEmCartao('bank', 'credit', 'PIX RECEBIDO DE CLIENTE')).toBeNull();
  });

  it('NÃO mexe em despesa de cartão — a compra continua sendo despesa', () => {
    expect(motivoDeCreditoEmCartao('credit_card', 'debit', 'MERCADOLIVRE*COMPRA')).toBeNull();
  });
});
