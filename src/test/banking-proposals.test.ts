// Proposta de lançamento a partir de transação órfã do extrato.
//
// Este é o ponto onde o sistema começa a escrever no financeiro, então cada regra aqui é
// uma decisão contábil. Os casos abaixo saíram do extrato real da empresa.
import { describe, it, expect } from "vitest";
import {
  classificar, acharFornecedor, montarProposta,
  type TransacaoOrfa, type FornecedorConhecido, type HistoricoFornecedor,
} from "../../supabase/functions/_shared/banking/proposals";

const tx = (o: Partial<TransacaoOrfa> = {}): TransacaoOrfa => ({
  id: "tx-1",
  transaction_date: "2026-07-20",
  description: "COMPRA GENERICA",
  amount: 350,
  transaction_type: "debit",
  ...o,
});

const fornecedores: FornecedorConhecido[] = [
  { id: "f-marine", name: "MARINE EXPRESS COMERCIAL IMPORTADORA E EXPORTADORA LTDA", cnpj_cpf: "68.904.101/0001-20" },
  { id: "f-contab", name: "SR Contabilidade", cnpj_cpf: null },
  // Razão social que ninguém escreve no extrato; o que aparece é o fantasia.
  { id: "f-kamell", name: "KAMELL COMERCIO GLOBAL LTDA", cnpj_cpf: null, trade_name: "KAMELL" },
];

describe("classificação por histórico", () => {
  it("reconhece pagamento de fatura como NÃO operacional", () => {
    // O caso mais importante: a despesa está nos itens da fatura. Lançar a fatura como
    // despesa contaria tudo duas vezes.
    const r = classificar(tx({ description: "PGTO FATURA CARTAO C6" }));
    expect(r?.categoria).toBe("Pagamento de fatura de cartão");
    expect(r?.dreGroup).toBe("nao_operacional");
  });

  it("reconhece as outras formas de escrever a mesma fatura", () => {
    // Todas saíram do extrato real: o mesmo fato escrito de três jeitos, inclusive pelo
    // lado do cartão ("PAGAMENTO RECEBIDO"). Faltava a mais comum, com 23 ocorrências.
    for (const d of ['FATURA DE CARTAO', 'PAGAMENTO RECEBIDO', 'SALDO EM ATRASO']) {
      expect(classificar(tx({ description: d }))?.dreGroup).toBe('nao_operacional');
    }
  });

  it("não confunde marketplace com supermercado", () => {
    // "MERCADO LIVRE" contém "MERCADO": sem a ordem certa das regras, compra de peça
    // viraria alimentação.
    expect(classificar(tx({ description: "MERCADO LIVRE*COMPRA" }))?.categoria).toBe("Peças e materiais");
    expect(classificar(tx({ description: "SUPERMERCADO ANGELONI" }))?.categoria).toBe("Alimentação de campo");
  });

  it("reconhece taxa municipal como imposto", () => {
    expect(classificar(tx({ description: "MUNICIPIO DE ITAJAI" }))?.categoria).toBe("Impostos e taxas");
  });

  it("reconhece aplicação financeira como não operacional", () => {
    expect(classificar(tx({ description: "CDB C6 LIM.GARANT." }))?.dreGroup).toBe("nao_operacional");
  });

  it("reconhece tributo", () => {
    const r = classificar(tx({ description: "TRIBUTOS FEDERAIS DARF NUMERADO" }));
    expect(r?.categoria).toBe("Impostos e taxas");
    expect(r?.dreGroup).toBe("financeiro");
  });

  it("reconhece combustível pelo posto", () => {
    expect(classificar(tx({ description: "C6 ABASTECIMENTO-POSTO AGRICOPEL LTDA" }))?.categoria)
      .toBe("Combustível e deslocamento");
  });

  it("reconhece fornecedor náutico como peças", () => {
    expect(classificar(tx({ description: "MARINE EXPRESS COMERCIAL IMPOR" }))?.categoria)
      .toBe("Peças e materiais");
  });

  it("reconhece aluguel e contabilidade", () => {
    expect(classificar(tx({ description: "MAY IMOBILIARIA LTDA" }))?.categoria).toBe("Aluguel e condomínio");
    expect(classificar(tx({ description: "SR CONTABILIDADE LTDA" }))?.categoria).toBe("Contabilidade e assessoria");
  });

  it("devolve nulo quando não reconhece — sem chute", () => {
    // Preferir "não sei" a inventar categoria plausível: categoria errada silenciosa é
    // pior que campo vazio, porque ninguém revisa o que parece certo.
    expect(classificar(tx({ description: "XPTO 4471 QWERTY" }))).toBeNull();
  });
});

describe("identificação do fornecedor", () => {
  it("casa por documento, que é identidade", () => {
    const r = acharFornecedor(tx({ counterparty_document: "68904101000120" }), fornecedores);
    expect(r?.fornecedor.id).toBe("f-marine");
    expect(r?.porDocumento).toBe(true);
  });

  it("casa por nome ignorando sufixo societário", () => {
    const r = acharFornecedor(tx({ counterparty_name: "SR CONTABILIDADE LTDA" }), fornecedores);
    expect(r?.fornecedor.id).toBe("f-contab");
    expect(r?.porDocumento).toBe(false);
  });

  it("não inventa fornecedor quando não há correspondência", () => {
    expect(acharFornecedor(tx({ counterparty_name: "EMPRESA DESCONHECIDA" }), fornecedores)).toBeNull();
  });
});

describe("montagem da proposta", () => {
  it("propõe despesa para saída, com motivo escrito", () => {
    const p = montarProposta(
      tx({ description: "TRANSF ENVIADA PIX", counterparty_name: "MARINE EXPRESS COMERCIAL IMPORTADORA E EXPORTADORA LTDA", counterparty_document: "68904101000120", amount: 5000 }),
      fornecedores,
    );
    expect(p.kind).toBe("create_payable");
    expect(p.suggestedSupplierId).toBe("f-marine");
    expect(p.suggestedAmount).toBe(5000);
    expect(p.reasoning).toContain("CNPJ/CPF confere");
  });

  it("propõe receita para entrada", () => {
    const p = montarProposta(tx({ transaction_type: "credit", description: "PIX RECEBIDO CLIENTE" }), fornecedores);
    expect(p.kind).toBe("create_receivable");
    expect(p.dreGroup).toBe("receita");
  });

  it("reconhecer o fornecedor pelo documento aumenta a confiança", () => {
    const semDoc = montarProposta(tx({ description: "MARINE EXPRESS COMERCIAL IMPOR" }), fornecedores);
    const comDoc = montarProposta(
      tx({ description: "MARINE EXPRESS COMERCIAL IMPOR", counterparty_document: "68904101000120" }),
      fornecedores,
    );
    expect(comDoc.confidence).toBeGreaterThan(semDoc.confidence);
  });

  it("ainda propõe quando não reconhece a categoria, mas com confiança baixa", () => {
    // O lançamento precisa existir de todo jeito — o que muda é o cuidado na revisão.
    const p = montarProposta(tx({ description: "XPTO 4471 QWERTY" }), fornecedores);
    expect(p.suggestedCategory).toBe("Outras despesas");
    expect(p.confidence).toBeLessThan(50);
    expect(p.reasoning).toContain("Nenhuma regra");
  });

  it("usa o que o gestor já decidiu para aquele fornecedor", () => {
    // O caso que mais pesa no extrato real: 86 saídas somando R$ 97 mil cujo histórico é
    // só "TRANSF ENVIADA PIX". Só o fornecedor identifica a despesa.
    const historico = new Map<string, HistoricoFornecedor>([
      ['f-marine', { categoria: 'Frete e importação', dreGroup: 'custo_direto', vezes: 6 }],
    ]);
    const p = montarProposta(
      tx({ description: "TRANSF ENVIADA PIX", counterparty_document: "68904101000120" }),
      fornecedores, historico,
    );
    expect(p.suggestedCategory).toBe("Frete e importação");
    expect(p.reasoning).toContain("6 vezes");
  });

  it("a prática da empresa vence a regra genérica de texto", () => {
    // "MARINE" cairia em Peças pela regra. Se a empresa sempre lançou aquele fornecedor
    // como Frete, é Frete — a regra é palpite, o histórico é o que de fato acontece.
    const historico = new Map<string, HistoricoFornecedor>([
      ['f-marine', { categoria: 'Frete e importação', dreGroup: 'custo_direto', vezes: 4 }],
    ]);
    const semHistorico = montarProposta(tx({ description: "MARINE EXPRESS COMERCIAL IMPOR", counterparty_document: "68904101000120" }), fornecedores);
    const comHistorico = montarProposta(tx({ description: "MARINE EXPRESS COMERCIAL IMPOR", counterparty_document: "68904101000120" }), fornecedores, historico);
    expect(semHistorico.suggestedCategory).toBe("Peças e materiais");
    expect(comHistorico.suggestedCategory).toBe("Frete e importação");
  });

  it("casa o fornecedor pelo nome fantasia, que é o que o extrato traz", () => {
    const p = montarProposta(tx({ description: "KAMELL COMERCIO GLOBAL LTDA" }), fornecedores);
    expect(p.suggestedSupplierId).toBe("f-kamell");
  });

  it("nunca ultrapassa o teto de confiança", () => {
    const p = montarProposta(
      tx({ description: "PGTO FATURA CARTAO C6", counterparty_document: "68904101000120" }),
      fornecedores,
    );
    expect(p.confidence).toBeLessThanOrEqual(98);
  });
});
