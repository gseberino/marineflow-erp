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
import { categoriaPorMcc } from "./mcc.ts";

export interface TransacaoOrfa {
  id: string;
  transaction_date: string;
  description: string;
  amount: number;
  transaction_type: "credit" | "debit";
  counterparty_name?: string | null;
  counterparty_document?: string | null;
  source_type?: string | null;
  /** MCC do estabelecimento (ISO 18245) — classificação determinística no cartão. */
  payee_mcc?: string | null;
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
 * As mesmas regras, com os termos já normalizados — uma vez só, na carga do módulo.
 *
 * Normalizar 180 termos constantes DENTRO do laço custava 180 normalizações por transação.
 * Num mutirão de 1.330 saídas isso vira 240 mil chamadas de `normalizeText` (que faz NFD +
 * três expressões regulares cada) e derruba a função pelo limite de CPU — o erro 546 que
 * aparecia como "Edge Function returned a non-2xx status code". Termo constante se
 * normaliza uma vez.
 *
 * `palavraInteira` preserva o que o espaço no fim do termo queria dizer. "DAS ", "TIM " e
 * "OI " foram escritos assim de propósito, para exigir a palavra inteira — mas
 * `normalizeText` apara os extremos e a exigência sumia: "DAS" casava dentro de "VENDAS" e
 * "OI" dentro de "POIS", classificando como imposto ou telefonia o que não é nem um nem
 * outro. Guardar a exigência à parte é o que faz a lista dizer o que ela sempre quis dizer.
 */
const REGRAS_NORMALIZADAS = REGRAS_CATEGORIA.map((regra) => ({
  regra,
  termos: regra.termos.map((t) => ({
    rotulo: t.trim(),
    valor: normalizeText(t),
    palavraInteira: /\s$/.test(t),
  })).filter((t) => t.valor.length > 0),
}));

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
  /** Cadastro, para a regra de fornecedor reconhecer o nome dele no extrato. */
  fornecedores?: FornecedorConhecido[] | IndiceFornecedores,
): RegraFinanceira | null {
  const doc = (tx.counterparty_document || "").replace(/\D/g, "");
  const texto = normalizeText(`${tx.description} ${tx.counterparty_name || ""}`);
  const nome = normalizeText(tx.counterparty_name || "");
  const tokensDoTexto = new Set(texto.split(" ").filter(Boolean));

  const serve = (r: RegraFinanceira): boolean => {
    if (r.status !== "active") return false;
    if (r.direction !== "any" && r.direction !== tx.transaction_type) return false;
    if (r.min_amount != null && tx.amount < Number(r.min_amount)) return false;
    if (r.max_amount != null && tx.amount > Number(r.max_amount)) return false;
    return true;
  };

  /**
   * A regra de fornecedor reconhece o fornecedor pelo NOME dele, não só pelo cadastro
   * resolvido.
   *
   * Quem escreve "compras na PREMEL são peças" está falando de um lugar, não de um uuid.
   * Mas o cartão escreve "PREMEL - ITAJAI" e a razão social é "PREMEL MAT. ELETRICOS
   * LTDA": nenhum dos dois contém o outro, então a resolução automática não liga os dois e
   * a regra que o gestor criou a dedo simplesmente não valia para as compras que ele tinha
   * na frente. O elo é a palavra que identifica — a primeira do nome.
   *
   * Aqui a permissividade é justificada porque a instrução é EXPLÍCITA: o gestor apontou
   * este fornecedor. A resolução automática, que ninguém pediu, continua exigente.
   */
  const cadastro = fornecedores ? obterIndice(fornecedores) : null;
  const regraDeFornecedorCasa = (r: RegraFinanceira): boolean => {
    if (r.match_type !== "supplier") return false;
    if (fornecedorId && r.match_value === fornecedorId) return true;
    if (!cadastro) return false;

    const f = cadastro.porNome.find((e) => e.fornecedor.id === r.match_value);
    if (!f) return false;

    // Documento do fornecedor no extrato: identidade, sem discussão.
    const docF = (f.fornecedor.cnpj_cpf || "").replace(/\D/g, "");
    if (doc.length >= 11 && docF === doc) return true;

    for (const candidato of [f.nome, f.fantasia]) {
      if (!candidato) continue;
      if (mesmoNomeLimpo(candidato, limparNome(tx.counterparty_name || tx.description))) return true;
      // Palavra-cabeça do nome do fornecedor presente no histórico. Exige 4 letras para
      // não deixar um "SUL" ou "MAR" arrastar meia fatura junto.
      const cabeca = candidato.split(" ")[0];
      if (cabeca.length >= 4 && tokensDoTexto.has(cabeca)) return true;
    }
    return false;
  };

  const ordem: Array<(r: RegraFinanceira) => boolean> = [
    (r) => r.match_type === "document" && doc.length >= 11 && r.match_value.replace(/\D/g, "") === doc,
    regraDeFornecedorCasa,
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

/** Nome sem acento, caixa nem sufixo societário — a forma comparável de um nome. */
function limparNome(s: string): string {
  return normalizeText(s)
    .replace(/\b(LTDA|ME|EPP|EIRELI|SA|S A|CIA)\b/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * Compara nomes ignorando acento, caixa e sufixo societário.
 *
 * A CONTENÇÃO É ANCORADA, e isso não é rigor gratuito: a versão que aceitava qualquer
 * substring atribuiu 160 despesas ao fornecedor errado. O cadastro da Coremma tinha nome
 * fantasia "Itajai" — a CIDADE —, e "ITAJAI" é substring de todo estabelecimento de Itajaí
 * que aparece na fatura. "PREMEL - ITAJAI" virou Coremma; com o fornecedor errado veio o
 * histórico aprendido dele, que sobrepôs a classificação certa. Um dado de cadastro ruim
 * contaminou o resultado inteiro sem uma linha de erro em lugar nenhum.
 *
 * Palavra única só casa quando é a CABEÇA do nome, porque é assim que nome de empresa
 * funciona: o que identifica vem primeiro e o resto qualifica. "KAMELL" casa com "KAMELL
 * COMERCIO GLOBAL"; "ITAJAI" não casa com "PREMEL ITAJAI".
 */
function mesmoNomeLimpo(x: string, y: string): boolean {
  if (!x || !y) return false;
  if (x === y) return true;

  const [curto, longo] = x.length <= y.length ? [x, y] : [y, x];
  if (!longo.includes(curto)) return false;

  // Nome composto contido no outro é evidência forte — e é o caso do extrato que corta
  // ("MARINE EXPRESS COMERCIAL IMPOR" dentro da razão social inteira).
  if (curto.includes(" ")) return true;

  return curto.length >= 3 && longo.startsWith(`${curto} `);
}

/**
 * Cadastro de fornecedores com os nomes já preparados para comparação.
 *
 * Existe pelo mesmo motivo das regras normalizadas: comparar uma transação com 530
 * fornecedores limpando o nome dos dois lados A CADA comparação são 560 mil limpezas num
 * mutirão de 1.330 saídas — trabalho que estoura o limite de CPU da função. O cadastro não
 * muda durante a varredura, então se prepara uma vez.
 */
export interface IndiceFornecedores {
  porDocumento: Map<string, FornecedorConhecido>;
  porNome: Array<{ fornecedor: FornecedorConhecido; nome: string; fantasia: string }>;
}

export function indexarFornecedores(fornecedores: FornecedorConhecido[]): IndiceFornecedores {
  const porDocumento = new Map<string, FornecedorConhecido>();
  const porNome: IndiceFornecedores["porNome"] = [];
  for (const f of fornecedores) {
    const doc = (f.cnpj_cpf || "").replace(/\D/g, "");
    // Primeiro cadastro vence, como fazia o `find` original: dois fornecedores com o mesmo
    // CNPJ é erro de cadastro, e trocar qual deles ganha mudaria a classificação sem aviso.
    if (doc.length >= 11 && !porDocumento.has(doc)) porDocumento.set(doc, f);
    porNome.push({
      fornecedor: f,
      nome: limparNome(f.name || ""),
      fantasia: f.trade_name ? limparNome(f.trade_name) : "",
    });
  }
  return { porDocumento, porNome };
}

/**
 * Índice já montado para este array. Chaveado pelo próprio array (WeakMap), então quem
 * continua passando a lista crua — os testes, e qualquer chamador futuro — ganha o ganho de
 * desempenho sem mudar uma linha, e o índice é liberado junto com a lista.
 */
const INDICE_POR_LISTA = new WeakMap<FornecedorConhecido[], IndiceFornecedores>();

function obterIndice(f: FornecedorConhecido[] | IndiceFornecedores): IndiceFornecedores {
  if (!Array.isArray(f)) return f;
  const pronto = INDICE_POR_LISTA.get(f);
  if (pronto) return pronto;
  const novo = indexarFornecedores(f);
  INDICE_POR_LISTA.set(f, novo);
  return novo;
}

/**
 * Acha o fornecedor cadastrado correspondente.
 *
 * Documento primeiro: CNPJ é identidade, nome é aproximação. Casar por nome quando há
 * documento disponível seria trocar certeza por palpite.
 */
export function acharFornecedor(
  tx: TransacaoOrfa,
  fornecedores: FornecedorConhecido[] | IndiceFornecedores,
): { fornecedor: FornecedorConhecido; porDocumento: boolean } | null {
  const indice = obterIndice(fornecedores);

  const doc = (tx.counterparty_document || "").replace(/\D/g, "");
  if (doc.length >= 11) {
    const porDoc = indice.porDocumento.get(doc);
    if (porDoc) return { fornecedor: porDoc, porDocumento: true };
  }

  // O extrato traz ora a razão social, ora o nome fantasia — no C6, o fantasia é o mais
  // comum. Procurar só pela razão social perde a maioria dos casos.
  const alvo = limparNome(tx.counterparty_name || tx.description);
  if (!alvo) return null;
  const achado = indice.porNome.find(
    (e) => mesmoNomeLimpo(e.nome, alvo) || mesmoNomeLimpo(e.fantasia, alvo),
  );
  return achado ? { fornecedor: achado.fornecedor, porDocumento: false } : null;
}

/** Classifica pelo histórico. Devolve null quando nenhuma regra bate — sem chute. */
export function classificar(tx: TransacaoOrfa): { categoria: string; dreGroup: string; confianca: number; termo: string } | null {
  const texto = normalizeText(`${tx.description} ${tx.counterparty_name || ""}`);
  const cercado = ` ${texto} `;
  for (const { regra, termos } of REGRAS_NORMALIZADAS) {
    const termo = termos.find((t) =>
      t.palavraInteira ? cercado.includes(` ${t.valor} `) : texto.includes(t.valor),
    );
    if (termo) {
      return {
        categoria: regra.categoria,
        dreGroup: regra.dreGroup,
        confianca: regra.confianca,
        termo: termo.rotulo,
      };
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
/** Caixa alta, sem acento e sem pontuação: a chave de quem recebeu, no extrato. */
export function chaveDoRecebedor(tx: TransacaoOrfa): string {
  return normalizeText(tx.counterparty_name || tx.description || "");
}

export function montarProposta(
  tx: TransacaoOrfa,
  fornecedores: FornecedorConhecido[] | IndiceFornecedores,
  historico?: Map<string, HistoricoFornecedor>,
  regras: RegraFinanceira[] = [],
  /**
   * O que já se decidiu para cada NOME do extrato.
   *
   * O histórico por fornecedor só alcança quem está cadastrado, e a fatura de cartão é
   * quase toda de estabelecimentos que nunca serão fornecedor — LMGCONFEITARIA, EC
   * *INOHOUSE, SPG*DEPARTAMENTO. Eram justamente eles que caíam em "Outras despesas" para
   * sempre: o gestor classificava a mesma padaria pela décima vez e o sistema não
   * aprendia nada, porque não tinha onde guardar o que aprendeu.
   */
  historicoPorNome?: Map<string, HistoricoFornecedor>,
): Proposta {
  const ehSaida = tx.transaction_type === "debit";
  // A lista de termos de `classificar` é 100% de DESPESA — não há uma única categoria de
  // receita nela. Aplicá-la a uma entrada devolveria, por exemplo, "Peças e materiais /
  // custo_direto" para um recebimento, e isso entra direto no DRE com cara de certeza.
  // Entrada fica com "Outras receitas" até uma REGRA sua dizer outra coisa: regra tem
  // direção e é instrução, não palpite.
  const classificacao = ehSaida ? classificar(tx) : null;
  const achado = ehSaida ? acharFornecedor(tx, fornecedores) : null;

  /**
   * MCC: o que a bandeira diz que o estabelecimento é.
   *
   * Vem atribuído no credenciamento e viaja em toda compra no cartão — 5812 é restaurante
   * em qualquer adquirente do mundo. Não depende de como a maquininha escreve o nome, o
   * que é justamente onde a leitura por texto falha: "MP *GTEKENERGIASU" e "EC *INOHOUSE"
   * não contêm palavra nenhuma do plano de contas, mas carregam MCC.
   *
   * Vale mais que regra de texto e que histórico aprendido, e menos que a regra do gestor:
   * é um fato sobre o estabelecimento, não uma dedução — mas quem manda continua sendo
   * quem escreveu a instrução.
   */
  const porMcc = categoriaPorMcc(tx.payee_mcc);

  const razoes: string[] = [];
  let confianca = classificacao?.confianca ?? 30;

  if (porMcc) {
    razoes.push(`Estabelecimento classificado pela bandeira como ${porMcc.rotulo} (MCC ${tx.payee_mcc})`);
    confianca = 90;
  } else if (classificacao) {
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
  const porFornecedor = achado ? historico?.get(achado.fornecedor.id) : undefined;
  // Fornecedor cadastrado vale mais que nome de extrato: é identidade contra aproximação.
  const porNome = historicoPorNome?.get(chaveDoRecebedor(tx));
  // MAS SÓ PARA SAÍDA. Esta memória é construída lendo `payables` — é histórico de DESPESA,
  // e nada mais. Enquanto entrada nunca chegava aqui isso era inofensivo; agora que chega,
  // uma empresa de quem compramos E que também nos paga faria a receita herdar
  // "Peças e materiais / custo_direto". Categoria errada com cara de certeza ninguém revisa,
  // e o estrago apareceria direto no DRE. Entrada cai para a classificação por texto e, sem
  // ela, para "Outras receitas" — que é um "não sei" honesto.
  const aprendido = ehSaida ? (porFornecedor ?? porNome) : undefined;
  if (aprendido) {
    const quem = porFornecedor ? "Este fornecedor" : "Este estabelecimento";
    razoes.push(
      aprendido.vezes === 1
        ? `Da última vez, uma despesa de ${porFornecedor ? "deste fornecedor" : "aqui"} foi lançada como ${aprendido.categoria}`
        : `${quem} já foi lançado como ${aprendido.categoria} ${aprendido.vezes} vezes`,
    );
    confianca = Math.min(98, Math.max(confianca, 60 + Math.min(25, aprendido.vezes * 5)));
  }

  const nome = tx.counterparty_name || tx.description;
  // Ordem da evidência: fato da bandeira (MCC) > prática da casa (histórico) > palpite de
  // texto. Antes o histórico vinha primeiro, e um fornecedor mal classificado uma vez
  // sobrepunha o que a bandeira afirma sobre o estabelecimento.
  let categoria = porMcc?.categoria ?? aprendido?.categoria ?? classificacao?.categoria
    ?? (ehSaida ? "Outras despesas" : "Outras receitas");
  let dreGroup = porMcc?.dreGroup ?? aprendido?.dreGroup ?? classificacao?.dreGroup
    ?? (ehSaida ? "despesa_operacional" : "receita");
  let fornecedorId = achado?.fornecedor.id ?? null;

  // A regra do gestor vem POR ÚLTIMO e vence tudo, de propósito: ela não é mais um palpite
  // a ser ponderado, é uma instrução. Quem escreveu "PIX para Fulano é pró-labore" não
  // quer que uma regra de texto genérica discorde disso.
  const regra = acharRegra(tx, regras, fornecedorId, fornecedores);
  if (regra) {
    if (regra.set_category) categoria = regra.set_category;
    if (regra.set_dre_group) dreGroup = regra.set_dre_group;
    if (regra.set_supplier_id) fornecedorId = regra.set_supplier_id;
    // Regra de fornecedor também diz DE QUEM é a despesa, não só o que ela é. Sem isto a
    // compra continuaria atribuída a quem a resolução automática errou — e o custo por
    // fornecedor seguiria mentindo mesmo com a categoria já corrigida.
    else if (regra.match_type === "supplier") fornecedorId = regra.match_value;
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
