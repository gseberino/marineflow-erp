// O aprendiz de regras só propõe o que o motor casa (frente B, 21/10/2026).
//
// Em 08/10/2026 o aprendiz propôs 103 regras; 18 nunca casariam: ele montava a regra por NOME com o
// supplier_name da despesa, que, nas linhas sem contraparte, é a DESCRIÇÃO do extrato ("PGTO FAT CARTAO C6",
// "JUROS LIMITE CONTA") — e o motor (acharRegra) compara o nome da contraparte, vazio nessas linhas.
// Cada teste abaixo prova pelo próprio motor (montarProposta), não por uma cópia da regra de comparação.
import { describe, it, expect } from "vitest";
import {
  montarProposta, sugerirRegras, type FornecedorConhecido, type PadraoDetectado, type RegraFinanceira, type TransacaoOrfa,
} from "../../supabase/functions/_shared/banking/proposals";
import { nomeDentroDaDescricao } from "../../supabase/functions/_shared/banking/contraparte";

let seq = 0;
const linha = (o: Partial<TransacaoOrfa>): TransacaoOrfa => {
  seq += 1;
  return { id: `tx-${seq}`, transaction_date: "2026-10-01", description: "", amount: 100, transaction_type: "debit", ...o };
};
const decisao = (tx: TransacaoOrfa | null, categoria: string, o: { supplierId?: string | null; supplierName?: string | null; counterpartyName?: string | null } = {}) => ({
  supplierId: o.supplierId ?? null,
  supplierName: o.supplierName ?? (o.supplierId ? null : (o.counterpartyName ?? tx?.counterparty_name ?? tx?.description ?? null)),
  // payables.supplier_name: o que a despesa guardou (na aprovação, a descrição da linha quando não há contraparte).
  counterpartyName: o.counterpartyName ?? (o.supplierId ? null : (tx?.counterparty_name || tx?.description || null)),
  categoria, dreGroup: "despesa_operacional", tx,
});
const comoRegra = (p: PadraoDetectado, id = "nova"): RegraFinanceira => ({
  id, match_type: p.matchType, match_value: p.matchValue, direction: p.direction, set_category: p.setCategory,
  set_dre_group: p.setDreGroup, set_supplier_id: p.setSupplierId, autonomy: "suggest", status: "active",
});
/** O motor aplica a regra proposta nesta linha? (com as regras ativas que já existem) */
const motorAplica = (p: PadraoDetectado, tx: TransacaoOrfa, cadastro: FornecedorConhecido[] = [], ativas: RegraFinanceira[] = []) =>
  montarProposta(tx, cadastro, undefined, [comoRegra(p), ...ativas]).appliedRuleId === "nova";
const semMotor = { regrasAtivas: [] as RegraFinanceira[], fornecedores: [] as FornecedorConhecido[] };

describe("aprendiz de regras: só o que o motor casa", () => {
  it("fatura do C6 sem contraparte vira regra de TEXTO, e o motor a aplica nas três linhas", () => {
    const linhas = [1, 2, 3].map(() => linha({ description: "PGTO FAT CARTAO C6", counterparty_name: null }));
    const p = sugerirRegras(linhas.map((t) => decisao(t, "Pagamento de fatura de cartão")), [], 3, [], semMotor);
    expect(p).toHaveLength(1);
    expect(p[0].matchType).toBe("text");
    for (const t of linhas) expect(motorAplica(p[0], t)).toBe(true);
  });

  it("nenhuma regra proposta é impossível de casar (descrição, nome, posto)", () => {
    const linhas = [
      ...[1, 2, 3].map(() => linha({ description: "JUROS LIMITE CONTA", counterparty_name: null })),
      ...[1, 2, 3].map(() => linha({ description: "POSTO PAULINHO         NAVEGANTES    BRA", counterparty_name: "POSTO PAULINHO", source_type: "credit_card" })),
      ...[1, 2, 3].map(() => linha({ description: "CDB C6 LIM.GARANT.", counterparty_name: null })),
    ];
    const cat = (t: TransacaoOrfa) => /POSTO/.test(t.description) ? "Combustível e deslocamento" : /CDB/.test(t.description) ? "Aplicação financeira" : "Juros e encargos";
    const p = sugerirRegras(linhas.map((t) => decisao(t, cat(t))), [], 3, [], semMotor);
    expect(p).toHaveLength(3);
    for (const padrao of p) {
      const delas = linhas.filter((t) => cat(t) === padrao.setCategory);
      for (const t of delas) expect(motorAplica(padrao, t), `${padrao.matchType}:${padrao.matchValue}`).toBe(true);
    }
  });

  it("o alvo é o nome da contraparte da linha, não o que a despesa guardou", () => {
    // O dono reescreveu a descrição ao aprovar ("Lanche da equipe"); o motor só conhece o nome do extrato.
    const linhas = [1, 2, 3].map(() => linha({ description: "LMGCONFEITARIA ITAJAI BRA", counterparty_name: "LMGCONFEITARIA" }));
    const p = sugerirRegras(linhas.map((t) => decisao(t, "Alimentação de campo", { counterpartyName: "Lanche da equipe" })), [], 3, [], semMotor);
    expect(p.map((x) => `${x.matchType}:${x.matchValue}`)).toEqual(["counterparty:LMGCONFEITARIA"]);
    for (const t of linhas) expect(motorAplica(p[0], t)).toBe(true);
  });

  it("descrição com o nome de alguém não vira regra de texto: 'JOSE' pegaria o 'JOSE CARLOS'", () => {
    const linhas = [1, 2, 3].map(() => linha({ description: "Pix enviado para JOSE CARLOS ABEL", counterparty_name: null }));
    expect(sugerirRegras(linhas.map((t) => decisao(t, "Diárias de freelancers")), [], 3, [], semMotor)).toHaveLength(0);
    const barra = [1, 2, 3].map(() => linha({ description: "Transferência enviada|Gustavo Seberino da Silva", counterparty_name: null }));
    expect(sugerirRegras(barra.map((t) => decisao(t, "Retirada de sócio")), [], 3, [], semMotor)).toHaveLength(0);
  });

  it("não recria a regra arquivada em 20/10: a mesma descrição não volta como regra de texto", () => {
    const arquivada: RegraFinanceira = {
      id: "arq", match_type: "counterparty", match_value: "PGTO FAT CARTAO C6", direction: "debit", autonomy: "suggest", status: "rejected",
    };
    const linhas = [1, 2, 3].map(() => linha({ description: "PGTO FAT CARTAO C6", counterparty_name: null }));
    expect(sugerirRegras(linhas.map((t) => decisao(t, "Pagamento de fatura de cartão")), [arquivada], 3, [], semMotor)).toHaveLength(0);
  });

  it("linha que uma regra ativa já cobre não gera regra repetida", () => {
    const coremma: RegraFinanceira = {
      id: "r-coremma", match_type: "text", match_value: "COREMMA", direction: "debit", autonomy: "suggest", status: "active",
      set_category: "Ferramentas e equipamentos",
    };
    const linhas = [1, 2, 3].map(() => linha({ description: "COREMMA                ITAJAI        BRA", counterparty_name: "COREMMA", source_type: "credit_card" }));
    const p = sugerirRegras(linhas.map((t) => decisao(t, "Ferramentas e equipamentos")), [coremma], 3, [],
      { regrasAtivas: [coremma], fornecedores: [] });
    expect(p).toHaveLength(0);
  });

  it("fornecedor desativado: o motor não reconhece o cadastro, a regra de fornecedor não casaria", () => {
    const desativado: FornecedorConhecido = { id: "f-zeflex", name: "ZEFLEX HIDRAULICA LTDA", cnpj_cpf: "18.758.137/0002-56" };
    const linhas = [1, 2, 3].map(() => linha({ description: "TRANSF ENVIADA PIX", counterparty_name: "ZEFLEX HIDRAULICA LTDA", counterparty_document: "18758137000256" }));
    const decisoes = linhas.map((t) => decisao(t, "Peças e materiais", { supplierId: "f-zeflex", supplierName: "ZEFLEX HIDRAULICA LTDA" }));
    // O cadastro inteiro (com o desativado) serve para o nome; o motor só tem os ATIVOS.
    expect(sugerirRegras(decisoes, [], 3, [desativado], { regrasAtivas: [], fornecedores: [] })).toHaveLength(0);
    // Ativo, a mesma regra casa e é proposta.
    const p = sugerirRegras(decisoes, [], 3, [desativado], { regrasAtivas: [], fornecedores: [desativado] });
    expect(p.map((x) => x.matchType)).toEqual(["supplier"]);
    for (const t of linhas) expect(motorAplica(p[0], t, [desativado])).toBe(true);
  });

  it("não recria a arquivada pela descrição: 'LMSDISTRIBUICAO BRASILIA BRA' não volta como o nome 'LMSDISTRIBUICAO'", () => {
    // Uma das 18 de 20/10/2026: a regra antiga usava a descrição do cartão; a linha tem o nome da loja à parte.
    const arquivada: RegraFinanceira = {
      id: "arq", match_type: "counterparty", match_value: "LMSDISTRIBUICAO        BRASILIA      BRA", direction: "debit",
      autonomy: "suggest", status: "rejected",
    };
    const linhas = [1, 2, 3].map(() => linha({
      description: "LMSDISTRIBUICAO        BRASILIA      BRA", counterparty_name: "LMSDISTRIBUICAO", source_type: "credit_card",
    }));
    const decisoes = linhas.map((t) => decisao(t, "Gasto Pessoal Sócio - Descontar PL", { counterpartyName: t.description }));
    expect(sugerirRegras(decisoes, [arquivada], 3, [], { ...semMotor, recentes: linhas })).toHaveLength(0);
    // Sem a arquivada, a mesma regra sai — e pelo nome, que é o que o motor compara.
    const p = sugerirRegras(decisoes, [], 3, [], { ...semMotor, recentes: linhas });
    expect(p.map((x) => `${x.matchType}:${x.matchValue}`)).toEqual(["counterparty:LMSDISTRIBUICAO"]);
  });

  it("quem sumiu do extrato nos últimos 90 dias não ganha regra (a 'parada' que o dono mandou guardar)", () => {
    // APOLO FILIAL 11: três abastecimentos decididos, nenhum nos últimos 90 dias.
    const antigas = [1, 2, 3].map(() => linha({
      transaction_date: "2026-03-10", description: "APOLO FILIAL 11        ARAQUARI      BRA", counterparty_name: "APOLO FILIAL 11", source_type: "credit_card",
    }));
    const decisoes = antigas.map((t) => decisao(t, "Combustível e deslocamento"));
    const outraLoja = linha({ transaction_date: "2026-10-01", description: "POSTO VIA SETE", counterparty_name: "POSTO VIA SETE" });
    expect(sugerirRegras(decisoes, [], 3, [], { ...semMotor, recentes: [outraLoja] })).toHaveLength(0);
    const voltou = linha({ transaction_date: "2026-10-05", description: "APOLO FILIAL 11        ARAQUARI      BRA", counterparty_name: "APOLO FILIAL 11", source_type: "credit_card" });
    expect(sugerirRegras(decisoes, [], 3, [], { ...semMotor, recentes: [outraLoja, voltou] })).toHaveLength(1);
  });

  it("não briga com regra sua: se tomaria o lugar de uma regra com outra categoria, não propõe (montado)", () => {
    const coremma: RegraFinanceira = {
      id: "r-coremma", match_type: "text", match_value: "COREMMA", direction: "debit", autonomy: "suggest", status: "active",
      set_category: "Ferramentas e equipamentos",
    };
    const loja = (descricao: string) => linha({ description: descricao, counterparty_name: "LOJA DO CAIS" });
    const decisoes = [1, 2, 3].map(() => decisao(loja("LOJA DO CAIS"), "Peças e materiais"));
    const motor = { regrasAtivas: [coremma], fornecedores: [] as FornecedorConhecido[] };
    // Uma compra recente da mesma loja que a sua regra "COREMMA" já classifica como ferramenta: a regra nova a mudaria.
    expect(sugerirRegras(decisoes, [coremma], 3, [], { ...motor, recentes: [loja("LOJA DO CAIS"), loja("LOJA DO CAIS COREMMA")] })).toHaveLength(0);
    expect(sugerirRegras(decisoes, [coremma], 3, [], { ...motor, recentes: [loja("LOJA DO CAIS")] })).toHaveLength(1);
  });

  it("lançamento à mão, sem linha do extrato, não prova que a regra casa", () => {
    const decisoes = [1, 2, 3].map(() => decisao(null, "Combustível e deslocamento", { counterpartyName: "Gasolina da lancha" }));
    expect(sugerirRegras(decisoes, [], 3, [], semMotor)).toHaveLength(0);
  });

  // ── Revisão de 22/10/2026 ─────────────────────────────────────────────────────────────────────────

  it("não briga com o que o dono decidiu em OUTRA linha: 'Juros de atraso' tomaria as do 'cartao PJ' (Tarifas)", () => {
    // A regra de texto casa por "contém": "Juros de atraso" casa também em "Juros de atraso cartao PJ", que o
    // dono lançou como Tarifas — e nenhuma regra ativa cobre essas linhas, então a guarda antiga não via.
    const juros = [1, 2, 3].map(() => linha({ description: "Juros de atraso", counterparty_name: null }));
    const pj = [1, 2, 3].map(() => linha({ description: "Juros de atraso cartao PJ", counterparty_name: null }));
    const decisoes = [...juros.map((t) => decisao(t, "Juros e encargos")), ...pj.map((t) => decisao(t, "Tarifas bancárias"))];
    const p = sugerirRegras(decisoes, [], 3, [], semMotor);
    // Sai só a mais específica, que não toca nas linhas da outra.
    expect(p.map((x) => `${x.matchType}:${x.matchValue}→${x.setCategory}`)).toEqual(["text:Juros de atraso cartao PJ→Tarifas bancárias"]);
    // "Sem exceção" de verdade: nenhuma proposta muda a categoria de uma linha que o dono já decidiu.
    for (const padrao of p) for (const d of decisoes) if (motorAplica(padrao, d.tx!)) expect(d.categoria).toBe(padrao.setCategory);
    // "Outras despesas" não é escolha (é a falta dela): a linha assim lançada não impede a regra.
    const semEscolha = linha({ description: "Juros de atraso cartao PF", counterparty_name: null });
    const q = sugerirRegras([...juros.map((t) => decisao(t, "Juros e encargos")), decisao(semEscolha, "Outras despesas")], [], 3, [], semMotor);
    expect(q.map((x) => `${x.matchType}:${x.matchValue}`)).toEqual(["text:Juros de atraso"]);
  });

  it("duas sugestões do mesmo lote, com categorias diferentes, disputando a mesma linha: sai só a de mais decisões (montado)", () => {
    const posto = [1, 2, 3, 4].map(() => linha({ description: "POSTO SOL", counterparty_name: null }));
    const lanche = [1, 2, 3].map(() => linha({ description: "LANCHES DO PORTO", counterparty_name: null }));
    const decisoes = [...posto.map((t) => decisao(t, "Combustível e deslocamento")), ...lanche.map((t) => decisao(t, "Alimentação de campo"))];
    const recentes = [linha({ description: "POSTO SOL", counterparty_name: null }), linha({ description: "LANCHES DO PORTO", counterparty_name: null })];
    expect(sugerirRegras(decisoes, [], 3, [], { ...semMotor, recentes })).toHaveLength(2);
    // Uma compra recente casa nas duas regras de texto: venceria a criada por último — e as duas nasceriam juntas,
    // com a mesma hora. A de menos decisões espera: aceita a outra, ela é medida contra a regra ativa.
    const disputada = linha({ description: "POSTO SOL LANCHES DO PORTO", counterparty_name: null });
    const p = sugerirRegras(decisoes, [], 3, [], { ...semMotor, recentes: [...recentes, disputada] });
    expect(p.map((x) => `${x.matchValue}→${x.setCategory}`)).toEqual(["POSTO SOL→Combustível e deslocamento"]);
  });

  it("'Compra no débito|LOJA' traz o nome da loja: não vira regra de texto ('POSTO PAULINHO' pegaria o 'POSTO PAULINHO II')", () => {
    // O formato real do Nubank (4 linhas de 18–19/08/2026, sem nome da contraparte).
    expect(nomeDentroDaDescricao("Compra no débito|POSTO PAULINHO")).toBe("POSTO PAULINHO");
    expect(nomeDentroDaDescricao("Compra no débito|MUNDO LED")).toBe("MUNDO LED");
    // O texto depois da barra que não é nome continua de fora (entrada do cartão, real).
    expect(nomeDentroDaDescricao("Valor adicionado na conta por cartão de crédito | Valor adicionado para PIX no Crédito")).toBeNull();
    const linhas = [1, 2, 3].map(() => linha({ description: "Compra no débito|POSTO PAULINHO", counterparty_name: null }));
    expect(sugerirRegras(linhas.map((t) => decisao(t, "Alimentação de campo")), [], 3, [], semMotor)).toHaveLength(0);
  });

  it("uma linha com três despesas (o Pix dividido) conta uma vez só", () => {
    const seguro = linha({ description: "SEGURO NAUTICO MENSAL", counterparty_name: null });
    expect(sugerirRegras([1, 2, 3].map(() => decisao(seguro, "Seguros")), [], 3, [], semMotor)).toHaveLength(0);
    // Três linhas, uma delas dividida em duas despesas: são 3 vezes, não 4.
    const tres = [1, 2, 3].map(() => linha({ description: "SEGURO NAUTICO MENSAL", counterparty_name: null }));
    const p = sugerirRegras([...tres.map((t) => decisao(t, "Seguros")), decisao(tres[0], "Seguros")], [], 3, [], semMotor);
    expect(p.map((x) => x.vezes)).toEqual([3]);
  });

  // ── Segunda revisão de 22/10/2026 ─────────────────────────────────────────────────────────────────

  it("o texto ao dono nomeia o que a regra compara (o nome do extrato), não o que a despesa guardou", () => {
    // 47 das 1.127 despesas sem fornecedor guardam um nome diferente do da linha (SELECT de 22/10/2026), como
    // "PGTO FAT CARTAO C6" na linha do "BANCO C6 S.A.". O dono lê o nome e aprova a regra sobre ele.
    const linhas = [1, 2, 3].map(() => linha({ description: "LMGCONFEITARIA ITAJAI BRA", counterparty_name: "LMGCONFEITARIA" }));
    const p = sugerirRegras(
      linhas.map((t) => decisao(t, "Alimentação de campo", { supplierName: "Lanche da equipe", counterpartyName: "Lanche da equipe" })),
      [], 3, [], semMotor);
    expect(p).toHaveLength(1);
    expect(p[0].reasoning).toContain("despesas de LMGCONFEITARIA foram lançadas como Alimentação de campo");
    expect(p[0].reasoning).not.toContain("Lanche da equipe");
  });

  it("regra que o dono PAUSOU não volta como sugestão (o índice único só cobre ativa e sugerida)", () => {
    const pausada: RegraFinanceira = {
      id: "pausada", match_type: "counterparty", match_value: "LMGCONFEITARIA", direction: "debit", autonomy: "suggest", status: "paused",
      set_category: "Alimentação de campo",
    };
    const linhas = [1, 2, 3].map(() => linha({ description: "LMGCONFEITARIA ITAJAI BRA", counterparty_name: "LMGCONFEITARIA" }));
    expect(sugerirRegras(linhas.map((t) => decisao(t, "Alimentação de campo")), [pausada], 3, [], semMotor)).toHaveLength(0);
    // Nem pelo texto: a pausada pelo nome também barra a regra de texto da mesma descrição.
    const semNome = [1, 2, 3].map(() => linha({ description: "LMGCONFEITARIA", counterparty_name: null }));
    expect(sugerirRegras(semNome.map((t) => decisao(t, "Alimentação de campo")), [pausada], 3, [], semMotor)).toHaveLength(0);
  });

  // ── Revisão final de 22/10/2026 ───────────────────────────────────────────────────────────────────

  it("as 18 arquivadas por nunca casarem ainda barram a versão que casa, e o 'desfazer' da migration não leva a ela (pergunta ao dono)", () => {
    // Estado de hoje, de propósito: liberar a versão que casa é decisão do dono, ainda sem resposta. Se ele disser sim,
    // este teste muda junto com o comentário de textosComRegra (proposals.ts) e o da migration 20261020120000.
    // Uma das 18 do bloco 1 da migration 20261020120000, com o começo da nota que ela tem em produção (SELECT de 22/10/2026).
    const arquivada: RegraFinanceira & { note: string | null } = {
      id: "arq-16af6051", match_type: "counterparty", match_value: "Pagamento de fatura", direction: "debit", autonomy: "suggest",
      status: "rejected", set_category: "Pagamento de fatura de cartão",
      note: "Arquivada em 20/10/2026 (papelada): o alvo aparece nos últimos 90 dias só na descrição do extrato, e a regra por nome compara o nome da contraparte",
    };
    const linhas = [1, 2, 3].map(() => linha({ description: "Pagamento de fatura", counterparty_name: null }));
    const decisoes = linhas.map((t) => decisao(t, "Pagamento de fatura de cartão"));
    const motor = { ...semMotor, recentes: linhas };
    // Sem ela, a versão que casa sai (regra de texto), e o motor a aplica nas três linhas.
    const sem = sugerirRegras(decisoes, [], 3, [], motor);
    expect(sem.map((x) => `${x.matchType}:${x.matchValue}`)).toEqual(["text:Pagamento de fatura"]);
    for (const t of linhas) expect(motorAplica(sem[0], t)).toBe(true);
    // Hoje: a arquivada (que não foi recusa do dono) barra a versão de texto — o aprendiz não sugere nada.
    expect(sugerirRegras(decisoes, [arquivada], 3, [], motor)).toHaveLength(0);
    // O "desfazer" escrito na migration (status = 'proposed', nota apagada) traz de volta a regra por NOME, que o motor
    // não aplica em nenhuma das linhas — e que continua barrando a de texto.
    const desfeita = { ...arquivada, status: "proposed", note: null };
    for (const t of linhas) {
      expect(montarProposta(t, [], undefined, [{ ...desfeita, status: "active" }]).appliedRuleId).not.toBe(desfeita.id);
    }
    expect(sugerirRegras(decisoes, [desfeita], 3, [], motor)).toHaveLength(0);
  });
});
