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

/** Uma regra que o gestor ensinou (ou que a IA propôs e ele aceitou). */
export interface RegraFinanceira {
  id: string;
  match_type: "document" | "supplier" | "counterparty" | "text";
  match_value: string;
  direction: "debit" | "credit" | "any";
  min_amount?: number | null;
  max_amount?: number | null;
  set_category?: string | null;
  set_dre_group?: string | null;
  set_supplier_id?: string | null;
  autonomy: "suggest" | "apply";
  status: string;
}

/**
 * Acha a regra que reconhece esta transação, da mais específica para a mais genérica.
 *
 * A ordem NÃO é a de cadastro: é a da força da evidência. Documento é identidade e não se
 * confunde; texto é aproximação e casa demais. Se a regra por texto viesse antes, um
 * "PIX" qualquer sequestraria a classificação de um fornecedor que o gestor configurou
 * a dedo.
 */
export function acharRegra(
  tx: TransacaoOrfa,
  regras: RegraFinanceira[],
  fornecedorId?: string | null,
): RegraFinanceira | null {
  const doc = (tx.counterparty_document || "").replace(/\D/g, "");
  const texto = normalizeText(`${tx.description} ${tx.counterparty_name || ""}`);
  const nome = normalizeText(tx.counterparty_name || "");

  const serve = (r: RegraFinanceira): boolean => {
    if (r.status !== "active") return false;
    if (r.direction !== "any" && r.direction !== tx.transaction_type) return false;
    if (r.min_amount != null && tx.amount < Number(r.min_amount)) return false;
    if (r.max_amount != null && tx.amount > Number(r.max_amount)) return false;
    return true;
  };

  const ordem: Array<(r: RegraFinanceira) => boolean> = [
    (r) => r.match_type === "document" && doc.length >= 11 && r.match_value.replace(/\D/g, "") === doc,
    (r) => r.match_type === "supplier" && !!fornecedorId && r.match_value === fornecedorId,
    (r) => r.match_type === "counterparty" && !!nome && normalizeText(r.match_value) === nome,
    (r) => r.match_type === "text" && texto.includes(normalizeText(r.match_value).trim()),
  ];

  for (const casa of ordem) {
    const achada = regras.find((r) => serve(r) && casa(r));
    if (achada) return achada;
  }
  return null;
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
  /** Regra que classificou — permite auditar a regra pelo resultado dela. */
  appliedRuleId: string | null;
  /** A regra tem autonomia para lançar sozinha (o gestor conferiu ao criá-la). */
  autoAplicavel: boolean;
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
  regras: RegraFinanceira[] = [],
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
  let categoria = aprendido?.categoria ?? classificacao?.categoria
    ?? (ehSaida ? "Outras despesas" : "Outras receitas");
  let dreGroup = aprendido?.dreGroup ?? classificacao?.dreGroup
    ?? (ehSaida ? "despesa_operacional" : "receita");
  let fornecedorId = achado?.fornecedor.id ?? null;

  // A regra do gestor vem POR ÚLTIMO e vence tudo, de propósito: ela não é mais um palpite
  // a ser ponderado, é uma instrução. Quem escreveu "PIX para Fulano é pró-labore" não
  // quer que uma regra de texto genérica discorde disso.
  const regra = acharRegra(tx, regras, fornecedorId);
  if (regra) {
    if (regra.set_category) categoria = regra.set_category;
    if (regra.set_dre_group) dreGroup = regra.set_dre_group;
    if (regra.set_supplier_id) fornecedorId = regra.set_supplier_id;
    razoes.length = 0;   // o motivo passa a ser a regra; o resto virou ruído
    razoes.push(`Regra sua: ${descreverRegra(regra)}`);
    confianca = regra.autonomy === "apply" ? 99 : 95;
  }

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
    suggestedSupplierId: fornecedorId,
    dreGroup,
    appliedRuleId: regra?.id ?? null,
    autoAplicavel: regra?.autonomy === "apply",
  };
}

/** Uma repetição que o sistema notou e acha que merece virar regra. */
export interface PadraoDetectado {
  matchType: RegraFinanceira["match_type"];
  matchValue: string;
  direction: RegraFinanceira["direction"];
  setCategory: string;
  setDreGroup: string;
  setSupplierId: string | null;
  vezes: number;
  reasoning: string;
}

/**
 * Olha o que o gestor já decidiu e propõe virar regra o que se repetiu.
 *
 * A proposta NASCE inerte (`status: 'proposed'`, autonomia `suggest`): o sistema percebeu
 * um padrão, não recebeu uma ordem. Transformar observação em regra ativa sem alguém olhar
 * é como deixar o sistema escrever as próprias instruções — se ele classificou errado três
 * vezes, viraria regra classificar errado para sempre.
 *
 * Exige UNANIMIDADE, não maioria: se o mesmo fornecedor já recebeu duas categorias
 * diferentes, a decisão depende de algo que o histórico não mostra, e propor uma delas
 * seria escolher no lugar de quem sabe.
 */
export function sugerirRegras(
  decisoes: Array<{
    supplierId: string | null;
    supplierName?: string | null;
    counterpartyName?: string | null;
    categoria: string;
    dreGroup: string;
  }>,
  regrasExistentes: RegraFinanceira[],
  minimo = 3,
): PadraoDetectado[] {
  const porAlvo = new Map<string, {
    matchType: RegraFinanceira["match_type"];
    matchValue: string;
    rotulo: string;
    supplierId: string | null;
    categorias: Map<string, { dreGroup: string; vezes: number }>;
  }>();

  for (const d of decisoes) {
    if (!d.categoria || d.categoria === "Outras despesas") continue;

    // Fornecedor cadastrado é alvo melhor que nome solto: sobrevive a mudança de razão
    // social e a variações de escrita no extrato.
    const chave = d.supplierId
      ? `supplier:${d.supplierId}`
      : d.counterpartyName
        ? `counterparty:${normalizeText(d.counterpartyName)}`
        : null;
    if (!chave) continue;

    const entrada = porAlvo.get(chave) ?? {
      matchType: (d.supplierId ? "supplier" : "counterparty") as RegraFinanceira["match_type"],
      matchValue: d.supplierId ?? String(d.counterpartyName),
      rotulo: d.supplierName || d.counterpartyName || "este fornecedor",
      supplierId: d.supplierId,
      categorias: new Map<string, { dreGroup: string; vezes: number }>(),
    };
    const atual = entrada.categorias.get(d.categoria) ?? { dreGroup: d.dreGroup, vezes: 0 };
    atual.vezes += 1;
    entrada.categorias.set(d.categoria, atual);
    porAlvo.set(chave, entrada);
  }

  const jaTemRegra = new Set(
    regrasExistentes
      .filter((r) => r.status === "active" || r.status === "proposed" || r.status === "rejected")
      .map((r) => `${r.match_type}:${normalizeText(r.match_value)}`),
  );

  const padroes: PadraoDetectado[] = [];
  for (const alvo of porAlvo.values()) {
    if (alvo.categorias.size !== 1) continue;                     // sem unanimidade, não opina
    const [categoria, dados] = [...alvo.categorias.entries()][0];
    if (dados.vezes < minimo) continue;
    if (jaTemRegra.has(`${alvo.matchType}:${normalizeText(alvo.matchValue)}`)) continue;

    padroes.push({
      matchType: alvo.matchType,
      matchValue: alvo.matchValue,
      direction: "debit",
      setCategory: categoria,
      setDreGroup: dados.dreGroup,
      setSupplierId: alvo.supplierId,
      vezes: dados.vezes,
      reasoning: `As últimas ${dados.vezes} despesas de ${alvo.rotulo} foram lançadas como ${categoria}, sem exceção. Criar a regra evita repetir essa escolha toda vez.`,
    });
  }

  return padroes.sort((a, b) => b.vezes - a.vezes);
}

/** Frase curta que explica a regra para quem a lê na fila — e para quem vai revisá-la. */
export function descreverRegra(r: RegraFinanceira): string {
  const alvo = r.match_type === "document"
    ? `quem tem o CNPJ/CPF ${r.match_value}`
    : r.match_type === "supplier"
      ? "este fornecedor"
      : r.match_type === "counterparty"
        ? `pagamentos para "${r.match_value}"`
        : `histórico contendo "${r.match_value}"`;

  const faixa = r.min_amount != null && r.max_amount != null
    ? ` entre R$ ${r.min_amount} e R$ ${r.max_amount}`
    : r.min_amount != null
      ? ` acima de R$ ${r.min_amount}`
      : r.max_amount != null
        ? ` até R$ ${r.max_amount}`
        : "";

  return `${alvo}${faixa} é sempre ${r.set_category ?? "classificado por esta regra"}`;
}
