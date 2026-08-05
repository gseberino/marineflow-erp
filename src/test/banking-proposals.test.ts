// Proposta de lançamento a partir de transação órfã do extrato.
//
// Este é o ponto onde o sistema começa a escrever no financeiro, então cada regra aqui é
// uma decisão contábil. Os casos abaixo saíram do extrato real da empresa.
import { describe, it, expect } from "vitest";
import {
  classificar, acharFornecedor, indexarFornecedores, montarProposta,
  sugerirRegras,
  type TransacaoOrfa, type FornecedorConhecido, type HistoricoFornecedor, type RegraFinanceira,
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

  it("termo com espaço no fim exige palavra inteira", () => {
    // "DAS ", "TIM " e "OI " foram escritos com espaço justamente para não casarem dentro
    // de outra palavra. A normalização apagava o espaço e a exigência sumia: "VENDAS"
    // virava imposto e "POIS" virava telefonia — categoria errada em silêncio, que é o
    // erro mais caro deste módulo porque ninguém revisa o que parece certo.
    expect(classificar(tx({ description: "VENDAS ONLINE MARKETPLACE" }))?.categoria)
      .not.toBe("Impostos e taxas");
    expect(classificar(tx({ description: "PAGAMENTO DAS 07/2026" }))?.categoria)
      .toBe("Impostos e taxas");
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

  it("cidade no campo de nome fantasia não sequestra o fornecedor", () => {
    // Caso real, e caro: o cadastro da Coremma tinha nome fantasia "Itajai" — a CIDADE.
    // Como o casamento aceitava qualquer substring, todo estabelecimento de Itajaí na
    // fatura virou Coremma: 160 despesas atribuídas ao fornecedor errado, e com elas o
    // histórico aprendido do errado sobrepondo a classificação certa.
    const comCidade: FornecedorConhecido[] = [
      { id: "f-coremma", name: "Coremma Ltda", cnpj_cpf: null, trade_name: "Itajai" },
      { id: "f-premel", name: "PREMEL MAT. ELETRICOS LTDA", cnpj_cpf: "00.725.876/0008-71" },
    ];
    expect(acharFornecedor(tx({ counterparty_name: "PREMEL - ITAJAI" }), comCidade)).toBeNull();
    // E o que é de fato a Coremma continua sendo reconhecido.
    expect(acharFornecedor(tx({ counterparty_name: "COREMMA LTDA" }), comCidade)?.fornecedor.id)
      .toBe("f-coremma");
  });

  it("palavra única casa quando é a cabeça do nome, não no meio", () => {
    expect(acharFornecedor(tx({ counterparty_name: "KAMELL COMERCIO GLOBAL LTDA" }), fornecedores)?.fornecedor.id)
      .toBe("f-kamell");
    // "MELL" está dentro de "KAMELL", mas não identifica ninguém.
    expect(acharFornecedor(
      tx({ counterparty_name: "LOJA MELL" }),
      [{ id: "f-x", name: "MELL", cnpj_cpf: null }],
    )).toBeNull();
  });

  it("índice pronto acha o mesmo que a lista crua", () => {
    // O mutirão do histórico passa o índice para não limpar 530 nomes a cada transação —
    // é o que impede a função de morrer por limite de CPU. Se o índice respondesse
    // diferente da lista, a economia teria custado a classificação.
    const indice = indexarFornecedores(fornecedores);
    for (const t of [
      tx({ counterparty_document: "68904101000120" }),
      tx({ counterparty_name: "SR CONTABILIDADE LTDA" }),
      tx({ counterparty_name: "KAMELL" }),
      tx({ counterparty_name: "EMPRESA DESCONHECIDA" }),
    ]) {
      expect(acharFornecedor(t, indice)).toEqual(acharFornecedor(t, fornecedores));
    }
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

describe("regras que o gestor ensina", () => {
  const regra = (o: Partial<RegraFinanceira> = {}): RegraFinanceira => ({
    id: "r1", match_type: "counterparty", match_value: "GUSTAVO SEBERINO DA SILVA",
    direction: "debit", autonomy: "suggest", status: "active",
    set_category: "Pró-labore e retiradas", set_dre_group: "nao_operacional",
    ...o,
  });

  it("a instrução do gestor vence a dedução do sistema", () => {
    // "PIX para Gustavo Seberino" seria Outras despesas pela regra de texto. A instrução
    // explícita não é mais um palpite a ser ponderado — é uma ordem.
    const p = montarProposta(
      tx({ description: "TRANSF ENVIADA PIX", counterparty_name: "GUSTAVO SEBERINO DA SILVA" }),
      fornecedores, undefined, [regra()],
    );
    expect(p.suggestedCategory).toBe("Pró-labore e retiradas");
    expect(p.dreGroup).toBe("nao_operacional");
    expect(p.reasoning).toContain("Regra sua");
    expect(p.appliedRuleId).toBe("r1");
  });

  it("regra por documento ganha de regra por texto", () => {
    // CNPJ é identidade; texto casa demais. Se a ordem fosse a de cadastro, um "PIX"
    // genérico sequestraria a classificação de um fornecedor configurado a dedo.
    const porTexto = regra({ id: "r-texto", match_type: "text", match_value: "PIX", set_category: "Errada" });
    const porDoc = regra({ id: "r-doc", match_type: "document", match_value: "68.904.101/0001-20", set_category: "Certa" });
    const p = montarProposta(
      tx({ description: "TRANSF ENVIADA PIX", counterparty_document: "68904101000120" }),
      fornecedores, undefined, [porTexto, porDoc],
    );
    expect(p.suggestedCategory).toBe("Certa");
  });

  it("regra de fornecedor alcança o nome que o cartão escreve", () => {
    // O que o gestor quis dizer: "compras na PREMEL são peças e materiais". O que o
    // sistema via: um uuid que a resolução automática nunca ligava a "PREMEL - ITAJAI",
    // porque nem a razão social contém esse texto nem o contrário. A regra existia,
    // estava ativa, e não valia justamente para as compras que ele tinha na frente.
    const cadastro: FornecedorConhecido[] = [
      { id: "f-premel", name: "PREMEL MAT. ELETRICOS LTDA", cnpj_cpf: "00.725.876/0008-71" },
    ];
    const r = regra({
      id: "r-premel", match_type: "supplier", match_value: "f-premel",
      set_category: "Peças e materiais", set_dre_group: "custo_direto", set_supplier_id: null,
    });
    const p = montarProposta(
      tx({ description: "PREMEL - ITAJAI        ITAJAI        BRA", counterparty_name: "PREMEL - ITAJAI" }),
      cadastro, undefined, [r],
    );
    expect(p.suggestedCategory).toBe("Peças e materiais");
    expect(p.appliedRuleId).toBe("r-premel");
    // E diz de QUEM é a despesa: sem isso o custo por fornecedor seguiria errado.
    expect(p.suggestedSupplierId).toBe("f-premel");
  });

  it("cabeça curta demais não arrasta meia fatura", () => {
    const cadastro: FornecedorConhecido[] = [{ id: "f-sul", name: "SUL Comercio", cnpj_cpf: null }];
    const r = regra({ id: "r-sul", match_type: "supplier", match_value: "f-sul", set_category: "Errada" });
    const p = montarProposta(
      tx({ description: "POSTO SUL NAVEGANTES", counterparty_name: "POSTO SUL" }),
      cadastro, undefined, [r],
    );
    expect(p.appliedRuleId).toBeNull();
  });

  it("respeita a faixa de valor da regra", () => {
    const r = regra({ match_type: "text", match_value: "MARINE", min_amount: 1000, set_category: "Investimento" });
    const pequena = montarProposta(tx({ description: "MARINE EXPRESS", amount: 300 }), fornecedores, undefined, [r]);
    const grande = montarProposta(tx({ description: "MARINE EXPRESS", amount: 5000 }), fornecedores, undefined, [r]);
    expect(pequena.suggestedCategory).toBe("Peças e materiais");   // caiu na regra genérica
    expect(grande.suggestedCategory).toBe("Investimento");
  });

  it("regra pausada não vale", () => {
    const p = montarProposta(
      tx({ description: "TRANSF ENVIADA PIX", counterparty_name: "GUSTAVO SEBERINO DA SILVA" }),
      fornecedores, undefined, [regra({ status: "paused" })],
    );
    expect(p.suggestedCategory).toBe("Outras despesas");
  });

  it("regra de saída não classifica entrada", () => {
    const p = montarProposta(
      tx({ transaction_type: "credit", counterparty_name: "GUSTAVO SEBERINO DA SILVA" }),
      fornecedores, undefined, [regra()],
    );
    expect(p.suggestedCategory).not.toBe("Pró-labore e retiradas");
  });

  it("só a regra com autonomia lança sozinha", () => {
    const comum = montarProposta(tx({ counterparty_name: "GUSTAVO SEBERINO DA SILVA" }), fornecedores, undefined, [regra()]);
    const autonoma = montarProposta(tx({ counterparty_name: "GUSTAVO SEBERINO DA SILVA" }), fornecedores, undefined, [regra({ autonomy: "apply" })]);
    expect(comum.autoAplicavel).toBe(false);
    expect(autonoma.autoAplicavel).toBe(true);
  });
});

describe("regras que a IA propõe", () => {
  const d = (supplierId: string | null, categoria: string, counterpartyName?: string) =>
    ({ supplierId, categoria, dreGroup: "custo_direto", counterpartyName, supplierName: "Marine Express" });

  it("propõe quando o gestor repetiu a mesma escolha", () => {
    const p = sugerirRegras([d("f1", "Frete e importação"), d("f1", "Frete e importação"), d("f1", "Frete e importação")], []);
    expect(p).toHaveLength(1);
    expect(p[0].setCategory).toBe("Frete e importação");
    expect(p[0].reasoning).toContain("3 despesas");
  });

  it("cala quando o mesmo fornecedor teve categorias diferentes", () => {
    // Sem unanimidade, a escolha depende de algo que o histórico não mostra. Propor uma
    // delas seria decidir no lugar de quem sabe.
    const p = sugerirRegras([d("f1", "Frete e importação"), d("f1", "Frete e importação"), d("f1", "Peças e materiais")], []);
    expect(p).toHaveLength(0);
  });

  it("não insiste em regra que já existe ou que foi recusada", () => {
    const decisoes = [d("f1", "Frete e importação"), d("f1", "Frete e importação"), d("f1", "Frete e importação")];
    const recusada: RegraFinanceira = {
      id: "r1", match_type: "supplier", match_value: "f1", direction: "debit",
      autonomy: "suggest", status: "rejected",
    };
    expect(sugerirRegras(decisoes, [recusada])).toHaveLength(0);
  });

  it("não propõe com poucas repetições", () => {
    expect(sugerirRegras([d("f1", "Frete e importação"), d("f1", "Frete e importação")], [])).toHaveLength(0);
  });

  it("usa o nome da contraparte quando não há fornecedor cadastrado", () => {
    const p = sugerirRegras([
      d(null, "Pró-labore e retiradas", "GUSTAVO SEBERINO"),
      d(null, "Pró-labore e retiradas", "GUSTAVO SEBERINO"),
      d(null, "Pró-labore e retiradas", "GUSTAVO SEBERINO"),
    ], []);
    expect(p[0].matchType).toBe("counterparty");
    expect(p[0].matchValue).toBe("GUSTAVO SEBERINO");
  });
});
