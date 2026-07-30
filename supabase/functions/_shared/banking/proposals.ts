// Transforma transação de extrato sem correspondência em proposta de lançamento.
//
// É o miolo do módulo que ataca o problema real do financeiro: quase todo o dinheiro que
// passou pela conta no último ano nunca virou despesa ou receita registrada. Lançar isso à
// mão é inviável — foi por não ser viável que ninguém lançou.
//
// A regra que orienta tudo aqui: PROPOR é barato, ERRAR CALADO é caro. Toda proposta sai
// com o motivo escrito e um grau de confiança honesto; quando o sistema não sabe, ele diz
// que não sabe em vez de chutar uma categoria plausível.

import { normalizeText } from "./matching.ts";

export interface TransacaoOrfa {
  id: string;
  transaction_date: string;
  description: string;
  amount: number;
  transaction_type: "credit" | "debit";
  counterparty_name?: string | null;
  counterparty_document?: string | null;
  source_type?: string | null;
}

export interface FornecedorConhecido {
  id: string;
  name: string;
  /** A coluna no banco é `cnpj_cpf` (nesta ordem) — trocar a ordem devolve undefined calado. */
  cnpj_cpf?: string | null;
  /** Nome fantasia: é ele que costuma aparecer no extrato, não a razão social. */
  trade_name?: string | null;
}

export interface RegraCategoria {
  /** Termos que, se presentes no histórico, indicam a categoria. */
  termos: string[];
  categoria: string;
  dreGroup: string;
  /** Confiança quando a regra bate. Regras específicas valem mais que genéricas. */
  confianca: number;
}

/**
 * Regras de classificação derivadas do extrato real da empresa.
 *
 * Não é uma lista genérica de mercado: cada termo saiu de fornecedor que aparece de fato
 * no histórico. Regra que não corresponde a nada só produziria falso positivo.
 *
 * A ordem importa — a primeira que casar vence —, então o que é inequívoco vem antes do
 * que é genérico.
 */
export const REGRAS_CATEGORIA: RegraCategoria[] = [
  // ── Não operacional: o mais importante, porque errar aqui distorce o resultado ──
  // As variações vieram do extrato: cada banco (e cada lado da operação) escreve a mesma
  // coisa de um jeito. "PAGAMENTO RECEBIDO" é como a fatura aparece pelo lado do cartão.
  { termos: ["PGTO FATURA CARTAO", "PGTO FAT CARTAO", "PAGAMENTO FATURA", "FATURA DE CARTAO", "FATURA CARTAO", "PAGAMENTO RECEBIDO", "SALDO EM ATRASO"], categoria: "Pagamento de fatura de cartão", dreGroup: "nao_operacional", confianca: 95 },
  { termos: ["CDB", "APLICACAO", "RESGATE", "POUPANCA", "INVESTIMENTO"], categoria: "Aplicação financeira", dreGroup: "nao_operacional", confianca: 90 },
  { termos: ["EMPRESTIMO", "FINANCIAMENTO", "AYMORE", "SOC CRED FINANC", "CRED FINANCIAMENTO"], categoria: "Empréstimo e financiamento", dreGroup: "nao_operacional", confianca: 85 },

  // ── Tributos e banco ──
  { termos: ["DARF", "TRIBUTOS FEDERAIS", "DAS ", "SIMPLES NACIONAL", "GPS", "FGTS", "ISS", "IPTU", "IPVA", "MUNICIPIO DE", "PREFEITURA", "RECEITA FEDERAL"], categoria: "Impostos e taxas", dreGroup: "financeiro", confianca: 92 },
  { termos: ["TARIFA", "IOF", "ANUIDADE", "CESTA DE SERVICO", "MANUTENCAO DE CONTA"], categoria: "Tarifas bancárias", dreGroup: "financeiro", confianca: 90 },
  { termos: ["JUROS", "MULTA", "MORA", "ENCARGOS"], categoria: "Juros e encargos", dreGroup: "financeiro", confianca: 80 },

  // ── Custo direto ──
  { termos: ["POSTO", "ABASTECIMENTO", "COMBUSTIVEL", "IPIRANGA", "SHELL", "PETROBRAS", "AGRICOPEL"], categoria: "Combustível e deslocamento", dreGroup: "custo_direto", confianca: 88 },
  { termos: ["MARINE", "NAUTIC", "NAUTICA", "ESTALEIRO", "MOTORES", "PECAS"], categoria: "Peças e materiais", dreGroup: "custo_direto", confianca: 80 },
  { termos: ["CORREIOS", "TRANSPORTADORA", "JADLOG", "FRETE", "SEDEX", "DESPACHANTE"], categoria: "Frete e importação", dreGroup: "custo_direto", confianca: 85 },
  { termos: ["PEDAGIO", "ESTACIONAMENTO", "AUTOPASS", "CONECTCAR", "SEM PARAR", "FERRY", "BALSA", "C6TAG", "ARTERIS", "AUTOPISTA"], categoria: "Pedágio e estacionamento", dreGroup: "custo_direto", confianca: 88 },
  // E-commerce vem ANTES de alimentação de propósito: "MERCADO LIVRE" contém "MERCADO" e
  // seria classificado como supermercado se a ordem fosse a inversa.
  { termos: ["ALIEXPRESS", "SHOPEE", "MERCADO LIVRE", "MERCADOLIVRE", "AMAZON", "MERCADOPAGO"], categoria: "Peças e materiais", dreGroup: "custo_direto", confianca: 70 },
  { termos: ["RESTAURANTE", "LANCHONETE", "PADARIA", "IFOOD", "SUPERMERCADO", "MERCADO", "TICKETEXPRESS"], categoria: "Alimentação de campo", dreGroup: "custo_direto", confianca: 75 },

  // ── Despesa operacional ──
  { termos: ["IMOBILIARIA", "ALUGUEL", "CONDOMINIO", "LOCACAO"], categoria: "Aluguel e condomínio", dreGroup: "despesa_operacional", confianca: 88 },
  { termos: ["CONTABILIDADE", "CONTABIL", "ADVOCACIA", "ADVOGADO", "ASSESSORIA"], categoria: "Contabilidade e assessoria", dreGroup: "despesa_operacional", confianca: 90 },
  { termos: ["TELECOM", "UNIFIQUE", "VIVO", "CLARO", "TIM ", "OI ", "INTERNET", "TELEFONIA"], categoria: "Telefonia e internet", dreGroup: "despesa_operacional", confianca: 88 },
  { termos: ["GOOGLE", "MICROSOFT", "ADOBE", "SOFTWARE", "ASSINATURA", "SUPABASE", "VERCEL", "OPENAI", "ANTHROPIC", "APPLE.COM", "APPLE COM", "CANVA", "DROPBOX"], categoria: "Software e assinaturas", dreGroup: "despesa_operacional", confianca: 85 },
  { termos: ["MECANICA", "OFICINA", "AUTO CENTER", "PNEU", "FUNILARIA"], categoria: "Manutenção de veículo", dreGroup: "despesa_operacional", confianca: 80 },
  { termos: ["ENERGIA", "CELESC", "CEMIG", "COPEL", "LIGHT", "SANEAMENTO", "CASAN", "SABESP", "AGUA"], categoria: "Outras despesas", dreGroup: "despesa_operacional", confianca: 78 },
  { termos: ["SEGURO", "PORTO SEGURO", "SULAMERICA", "BRADESCO SEGUROS"], categoria: "Seguro", dreGroup: "despesa_operacional", confianca: 85 },
  { termos: ["FERRAMENT", "PREMEL", "PARAFUSO", "LEROY", "HOME CENTER", "MATERIAL DE CONSTRUCAO"], categoria: "Ferramentas e equipamentos", dreGroup: "despesa_operacional", confianca: 75 },
  { termos: ["MARKETING", "PUBLICIDADE", "META PLATFORMS", "FACEBOOK", "GOOGLE ADS", "INSTAGRAM"], categoria: "Marketing e publicidade", dreGroup: "despesa_operacional", confianca: 85 },
  { termos: ["SALARIO", "FOLHA", "PRO LABORE", "PROLABORE", "RESCISAO", "FERIAS", "13 SALARIO"], categoria: "Salários e encargos", dreGroup: "despesa_operacional", confianca: 85 },
];

/**
 * O que já se decidiu sobre um fornecedor, para não perguntar duas vezes a mesma coisa.
 *
 * É o que salva o caso mais comum e mais caro do extrato: 86 saídas somando R$ 97 mil cujo
 * histórico é só "TRANSF ENVIADA PIX". Nenhuma regra de texto vai adivinhar isso — o que
 * identifica a despesa é PARA QUEM o dinheiro foi. Sabendo o fornecedor, a categoria vem
 * do que o gestor já decidiu para ele antes.
 */
export interface HistoricoFornecedor {
  categoria: string;
  dreGroup: string;
  /** Quantas vezes esse fornecedor já foi classificado assim. Repetição é evidência. */
  vezes: number;
}

export interface Proposta {
  kind: "create_payable" | "create_receivable";
  bankTransactionId: string;
  title: string;
  reasoning: string;
  confidence: number;
  suggestedAmount: number;
  suggestedDate: string;
  suggestedCategory: string;
  suggestedDescription: string;
  suggestedSupplierId: string | null;
  dreGroup: string;
}

/** Compara nomes ignorando acento, caixa e sufixo societário. */
function mesmoNome(a: string, b: string): boolean {
  const limpa = (s: string) =>
    normalizeText(s)
      .replace(/\b(LTDA|ME|EPP|EIRELI|SA|S A|CIA)\b/g, "")
      .replace(/\s+/g, " ")
      .trim();
  const x = limpa(a);
  const y = limpa(b);
  if (!x || !y) return false;
  return x === y || x.includes(y) || y.includes(x);
}

/**
 * Acha o fornecedor cadastrado correspondente.
 *
 * Documento primeiro: CNPJ é identidade, nome é aproximação. Casar por nome quando há
 * documento disponível seria trocar certeza por palpite.
 */
export function acharFornecedor(
  tx: TransacaoOrfa,
  fornecedores: FornecedorConhecido[],
): { fornecedor: FornecedorConhecido; porDocumento: boolean } | null {
  const doc = (tx.counterparty_document || "").replace(/\D/g, "");
  if (doc.length >= 11) {
    const porDoc = fornecedores.find((f) => (f.cnpj_cpf || "").replace(/\D/g, "") === doc);
    if (porDoc) return { fornecedor: porDoc, porDocumento: true };
  }

  // O extrato traz ora a razão social, ora o nome fantasia — no C6, o fantasia é o mais
  // comum. Procurar só pela razão social perde a maioria dos casos.
  const alvo = tx.counterparty_name || tx.description;
  const porNome = fornecedores.find(
    (f) => mesmoNome(f.name, alvo) || (!!f.trade_name && mesmoNome(f.trade_name, alvo)),
  );
  return porNome ? { fornecedor: porNome, porDocumento: false } : null;
}

/** Classifica pelo histórico. Devolve null quando nenhuma regra bate — sem chute. */
export function classificar(tx: TransacaoOrfa): { categoria: string; dreGroup: string; confianca: number; termo: string } | null {
  const texto = normalizeText(`${tx.description} ${tx.counterparty_name || ""}`);
  for (const regra of REGRAS_CATEGORIA) {
    const termo = regra.termos.find((t) => texto.includes(normalizeText(t).trim()));
    if (termo) {
      return { categoria: regra.categoria, dreGroup: regra.dreGroup, confianca: regra.confianca, termo };
    }
  }
  return null;
}

/**
 * Monta a proposta de lançamento para uma transação órfã.
 *
 * A confiança é composta: a classificação dá a base, e reconhecer o fornecedor pelo
 * documento soma — porque saber DE QUEM é o gasto é metade da classificação correta.
 * Sem categoria reconhecida, a proposta ainda é feita (o lançamento precisa existir), mas
 * com confiança baixa e categoria genérica, para cair na revisão atenta.
 */
export function montarProposta(
  tx: TransacaoOrfa,
  fornecedores: FornecedorConhecido[],
  historico?: Map<string, HistoricoFornecedor>,
): Proposta {
  const ehSaida = tx.transaction_type === "debit";
  const classificacao = classificar(tx);
  const achado = ehSaida ? acharFornecedor(tx, fornecedores) : null;

  const razoes: string[] = [];
  let confianca = classificacao?.confianca ?? 30;

  if (classificacao) {
    razoes.push(`Histórico contém "${classificacao.termo}", que indica ${classificacao.categoria}`);
  } else {
    razoes.push("Nenhuma regra de categoria reconheceu este histórico");
  }

  if (achado) {
    razoes.push(
      achado.porDocumento
        ? `CNPJ/CPF confere com o fornecedor ${achado.fornecedor.name}`
        : `Nome parecido com o fornecedor ${achado.fornecedor.name}`,
    );
    confianca = Math.min(98, confianca + (achado.porDocumento ? 10 : 4));
  }

  // O que o gestor já decidiu para este fornecedor vale mais que uma regra de texto:
  // a regra é um palpite genérico, isto é a prática da própria empresa. Por isso o
  // histórico SOBRESCREVE a classificação por termo quando há repetição.
  const aprendido = achado ? historico?.get(achado.fornecedor.id) : undefined;
  if (aprendido) {
    razoes.push(
      aprendido.vezes === 1
        ? `Da última vez, uma despesa deste fornecedor foi lançada como ${aprendido.categoria}`
        : `Este fornecedor já foi lançado como ${aprendido.categoria} ${aprendido.vezes} vezes`,
    );
    confianca = Math.min(98, Math.max(confianca, 60 + Math.min(25, aprendido.vezes * 5)));
  }

  const nome = tx.counterparty_name || tx.description;
  const categoria = aprendido?.categoria ?? classificacao?.categoria
    ?? (ehSaida ? "Outras despesas" : "Outras receitas");
  const dreGroup = aprendido?.dreGroup ?? classificacao?.dreGroup
    ?? (ehSaida ? "despesa_operacional" : "receita");

  return {
    kind: ehSaida ? "create_payable" : "create_receivable",
    bankTransactionId: tx.id,
    title: `${ehSaida ? "Despesa" : "Receita"}: ${nome}`.slice(0, 160),
    reasoning: razoes.join(" · "),
    confidence: confianca,
    suggestedAmount: tx.amount,
    suggestedDate: tx.transaction_date,
    suggestedCategory: categoria,
    suggestedDescription: nome.slice(0, 200),
    suggestedSupplierId: achado?.fornecedor.id ?? null,
    dreGroup,
  };
}
