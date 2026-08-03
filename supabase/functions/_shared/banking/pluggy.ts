// Cliente da API do Pluggy e tradução do extrato para o formato do ERP.
//
// MODELO DE USO: "Meu Pluggy" (conector MeuPluggy, gratuito para dados próprios). A conta
// bancária é conectada pelo titular em meu.pluggy.ai e autorizada na aplicação do
// dashboard; o ERP só consome. Por isso aqui não existe widget de conexão — o que o
// sistema guarda é o `itemId` de cada vínculo, e a leitura é sempre por ele.
//
// A API em si é a mesma da plataforma comercial (api.pluggy.ai): muda o conector e o
// modelo de licença, não o protocolo.

const PLUGGY_API = "https://api.pluggy.ai";

export interface PluggyAccount {
  id: string;
  type: string;
  subtype?: string;
  name: string;
  number?: string;
  balance: number;
}

export interface PluggyTransaction {
  id: string;
  description: string;
  descriptionRaw?: string | null;
  amount: number;
  date: string;
  type: "CREDIT" | "DEBIT";
  balance?: number | null;
  status?: string | null;
  /**
   * Dados de quem está do outro lado. O provedor manda MUITO mais do que só nome e
   * documento — agência, conta, banco (routingNumber/ISPB), forma de pagamento e a
   * mensagem que o pagador escreveu. Ler só dois campos obrigava o gestor a abrir o
   * internet banking para saber de quem era o dinheiro.
   */
  paymentData?: {
    payer?: PluggyParticipante | null;
    receiver?: PluggyParticipante | null;
    paymentMethod?: string | null;
    referenceNumber?: string | null;
    receiverReferenceId?: string | null;
    reason?: string | null;
    authenticationCode?: string | null;
  } | null;
  /** Compra em estabelecimento: é AQUI que vem o nome e o CNPJ da loja. */
  merchant?: {
    name?: string | null;
    businessName?: string | null;
    cnpj?: string | null;
    category?: string | null;
  } | null;
  /** Compra no cartão: parcela atual e total, e os 4 últimos dígitos. */
  creditCardMetadata?: {
    installmentNumber?: number | null;
    totalInstallments?: number | null;
    cardNumber?: string | null;
  } | null;
}

interface PluggyParticipante {
  name?: string | null;
  branchNumber?: string | null;
  accountNumber?: string | null;
  routingNumber?: string | null;
  routingNumberISPB?: string | null;
  documentNumber?: { value?: string | null } | null;
}

/** Linha pronta para entrar em bank_transactions. */
export interface ExtratoRow {
  transaction_date: string;
  description: string;
  amount: number;
  transaction_type: "credit" | "debit";
  bank_ref_id: string;
  pix_end_to_end_id: string | null;
  counterparty_name: string | null;
  counterparty_document: string | null;
  /** Onde o dinheiro foi parar: banco, agência e conta de quem recebeu (ou pagou). */
  counterparty_bank: string | null;
  counterparty_branch: string | null;
  counterparty_account: string | null;
  /** PIX, TED, DOC, BOLETO — muda o que se pode cobrar e como se prova o pagamento. */
  payment_method: string | null;
  /** A mensagem que o pagador escreveu na transferência. */
  payment_reason: string | null;
  /** Nome e CNPJ do estabelecimento, para compra em loja/cartão. */
  merchant_name: string | null;
  merchant_document: string | null;
  /** "3/6" quando é compra parcelada no cartão. */
  installment_label: string | null;
  balance_after: number | null;
  provider: string;
  source_type: "bank" | "credit_card";
}

/** Autentica e devolve a apiKey de curta duração usada no header X-API-KEY. */
export async function pluggyAuth(clientId: string, clientSecret: string): Promise<string> {
  const res = await fetch(`${PLUGGY_API}/auth`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ clientId, clientSecret }),
  });
  if (!res.ok) {
    throw new Error(`Pluggy /auth respondeu ${res.status}: ${(await res.text()).slice(0, 200)}`);
  }
  const { apiKey } = await res.json();
  if (!apiKey) throw new Error("Pluggy /auth não devolveu apiKey");
  return apiKey;
}

async function pluggyGet(apiKey: string, path: string): Promise<any> {
  const res = await fetch(`${PLUGGY_API}${path}`, { headers: { "X-API-KEY": apiKey } });
  if (!res.ok) {
    throw new Error(`Pluggy ${path} respondeu ${res.status}: ${(await res.text()).slice(0, 200)}`);
  }
  return await res.json();
}

/** Estado do vínculo: serve para avisar quando o consentimento caiu. */
export async function fetchItem(apiKey: string, itemId: string): Promise<any> {
  return await pluggyGet(apiKey, `/items/${itemId}`);
}

/**
 * Itens que ESTAS credenciais enxergam.
 *
 * Serve para diagnosticar o 404 mais confuso da integração: o item existe no painel, mas
 * pertence a outra aplicação. Como a mensagem do provedor é só "item not found", sem esta
 * lista a pessoa fica presa achando que copiou o código errado — quando o problema é que
 * as credenciais configuradas são de outra aplicação.
 *
 * Nunca lança: é diagnóstico, e falhar aqui não pode piorar o erro que já aconteceu. Mas
 * devolve o motivo da falha — "não consegui listar" e "não há nenhuma conexão" levam a
 * conclusões opostas, e tratar um como o outro manda a pessoa procurar no lugar errado.
 */
export async function listItems(
  apiKey: string,
): Promise<{ itens: Array<{ id: string; connector: string; status: string }>; erro: string | null }> {
  try {
    const data = await pluggyGet(apiKey, "/items");
    const itens = ((data?.results ?? []) as any[]).map((i) => ({
      id: String(i?.id ?? ""),
      connector: String(i?.connector?.name ?? i?.connector?.institutionUrl ?? "—"),
      status: String(i?.status ?? "—"),
    }));
    return { itens, erro: null };
  } catch (e) {
    return { itens: [], erro: String((e as Error)?.message ?? e).slice(0, 300) };
  }
}

export async function fetchAccounts(apiKey: string, itemId: string): Promise<PluggyAccount[]> {
  const data = await pluggyGet(apiKey, `/accounts?itemId=${encodeURIComponent(itemId)}`);
  return (data?.results ?? []) as PluggyAccount[];
}

/**
 * Transações de uma conta, paginando até o fim.
 *
 * Usa `/v2/transactions`, que navega por cursor: a resposta traz `next` com a URL da
 * página seguinte, e o fim é `next` nulo. A rota antiga por número de página foi
 * descontinuada pelo provedor (responde 410) — e o parâmetro de data também mudou de
 * `from` para `dateFrom`, detalhe fácil de perder porque não dá erro: sem ele a busca
 * simplesmente traz o histórico inteiro toda vez.
 *
 * Paginar até o fim importa: extrato parcial é pior que extrato nenhum, porque some no
 * meio sem avisar e a conciliação passa a mentir sobre o que falta.
 */
export async function fetchTransactions(
  apiKey: string,
  accountId: string,
  from?: string | null,
  maxPages = 40,
): Promise<PluggyTransaction[]> {
  const todas: PluggyTransaction[] = [];
  let after: string | null = null;

  for (let pagina = 0; pagina < maxPages; pagina++) {
    // Sem `pageSize`: a v2 usa páginas de tamanho fixo e recusa o parâmetro com 400.
    const params = new URLSearchParams({ accountId });
    if (from) params.set("dateFrom", from);
    if (after) params.set("after", after);

    const data = await pluggyGet(apiKey, `/v2/transactions?${params.toString()}`);
    const lote = (data?.results ?? []) as PluggyTransaction[];
    todas.push(...lote);

    const next = data?.next;
    if (!next || lote.length === 0) break;

    // `next` vem como URL completa; o que interessa é o cursor dentro dela.
    try {
      after = new URL(String(next), PLUGGY_API).searchParams.get("after");
    } catch {
      after = null;
    }
    if (!after) break;
  }

  return todas;
}

/** Identificador do Pix no SPI: "E" + 31 caracteres. */
const PIX_E2E = /^E\d{20}[A-Za-z0-9]{11}$/;

function somenteDigitos(v: string | null | undefined): string | null {
  const d = (v || "").replace(/\D/g, "");
  return d.length >= 11 ? d : null;
}

/**
 * Traduz uma transação do Pluggy para a linha do extrato do ERP.
 *
 * Duas decisões que evitam erro silencioso:
 *
 * 1. O valor entra sempre POSITIVO e o sentido vai em `transaction_type`. O Pluggy usa
 *    sinal negativo para saída, e misturar as duas convenções faria somas de entrada
 *    subtraírem sem que nada pareça errado.
 *
 * 2. `bank_ref_id` recebe o id da transação no Pluggy, que é estável — é o que impede a
 *    mesma linha de entrar de novo a cada sincronização, já que a janela de busca sempre
 *    se sobrepõe ao que já foi importado.
 */
/**
 * Termos que descrevem a OPERAÇÃO, não quem está do outro lado.
 *
 * Saíram do extrato real. Um histórico que começa por qualquer um deles é o banco narrando
 * o que fez ("transferência enviada", "pagamento de fatura"), e tomar isso por nome de
 * fornecedor encheria o cadastro de "TRANSF ENVIADA PIX".
 */
const HISTORICO_GENERICO =
  /^(TRANSF|TRANSFER|PIX\b|PGTO|PAGAMENTO|FATURA|SALDO|CDB|APLICACAO|RESGATE|TARIFA|IOF|JUROS|MULTA|DARF|TRIBUTO|DAS\b|GPS\b|FGTS|VENDAS|CREDITO|DEBITO|ESTORNO|DEVOLUCAO|COMPRA|SEM DESCRICAO|PAGAMENTO RECEBIDO|VALOR ADICIONADO)/i;

/**
 * Usa o histórico como nome da contraparte quando o banco não informou o nome.
 *
 * POR QUE ISTO EXISTE: em 162 movimentações o banco mandou o CNPJ da contraparte e deixou
 * o campo do nome vazio — nome e documento saem do MESMO objeto no pacote do provedor, e
 * como nunca aparece nome sem documento, dá para afirmar que o campo veio vazio da origem,
 * não que a leitura o perdeu. Em boa parte desses casos o nome está no próprio histórico
 * ("ACRISIO LOPES CANCADO FILHO"), e o mesmo vale para compra em estabelecimento, onde não
 * existe contraparte de Pix mas existe o nome da loja ("PREMEL - ITAJAI").
 *
 * Devolve null quando o histórico é a narração da operação: preencher com "TRANSF ENVIADA
 * PIX" seria trocar um campo vazio honesto por um dado falso, e o vazio pelo menos avisa
 * que ninguém sabe quem é.
 */
export function nomeNoHistorico(descricao?: string | null): string | null {
  const limpo = (descricao || "").trim();
  if (limpo.length < 4) return null;
  // Sem tirar o acento, "Sem descrição" escapa da lista — e esse texto é justamente o
  // fallback que este arquivo escreve quando o banco não manda histórico nenhum, então
  // ele voltaria como se fosse o nome de um fornecedor.
  const semAcento = limpo.normalize("NFD").replace(/[̀-ͯ]/g, "");
  if (HISTORICO_GENERICO.test(semAcento)) return null;
  // Sufixos de terminal de cartão ("PREMEL - ITAJAI  ITAJAI  BRA") não são parte do nome.
  return limpo.replace(/\s{2,}[A-Z\s]{2,}\s+BRA\s*$/i, "").trim().slice(0, 120) || null;
}

export function mapTransaction(
  tx: PluggyTransaction,
  sourceType: "bank" | "credit_card" = "bank",
): ExtratoRow {
  const ehCredito = tx.type === "CREDIT";
  // A contraparte é quem pagou quando entra dinheiro, e quem recebeu quando sai.
  const contraparte = ehCredito ? tx.paymentData?.payer : tx.paymentData?.receiver;

  const referencia = tx.paymentData?.referenceNumber ?? null;
  const ehPix = (tx.paymentData?.paymentMethod ?? "").toUpperCase() === "PIX";

  // O estabelecimento identifica melhor que o histórico quando existe: "NETFLIX
  // ENTRETENIMENTO BRASIL LTDA" contra "EC *NETFLIX SAO PAULO BRA".
  const loja = tx.merchant;
  const parcela = tx.creditCardMetadata;

  return {
    transaction_date: String(tx.date).slice(0, 10),
    description: tx.description || tx.descriptionRaw || "Sem descrição",
    amount: Math.abs(Number(tx.amount) || 0),
    transaction_type: ehCredito ? "credit" : "debit",
    bank_ref_id: tx.id,
    counterparty_bank: contraparte?.routingNumber ?? contraparte?.routingNumberISPB ?? null,
    counterparty_branch: contraparte?.branchNumber ?? null,
    counterparty_account: contraparte?.accountNumber ?? null,
    payment_method: tx.paymentData?.paymentMethod ?? null,
    payment_reason: tx.paymentData?.reason ?? null,
    merchant_name: loja?.businessName ?? loja?.name ?? null,
    merchant_document: somenteDigitos(loja?.cnpj),
    installment_label: parcela?.installmentNumber && parcela?.totalInstallments
      ? `${parcela.installmentNumber}/${parcela.totalInstallments}`
      : null,
    // Só grava como EndToEndId o que tem cara de EndToEndId: outros métodos usam o mesmo
    // campo de referência para números que não identificam nada no SPI.
    pix_end_to_end_id: ehPix && referencia && PIX_E2E.test(referencia) ? referencia : null,
    // Ordem de confiança: quem o banco nomeou > o estabelecimento > o que dá para ler do
    // histórico. Compra em loja não tem contraparte de Pix, mas tem merchant — e era essa
    // a razão de 1.086 lançamentos de cartão ficarem sem identificação nenhuma.
    counterparty_name: contraparte?.name ?? loja?.businessName ?? loja?.name
      ?? nomeNoHistorico(tx.description || tx.descriptionRaw),
    counterparty_document: somenteDigitos(contraparte?.documentNumber?.value)
      ?? somenteDigitos(loja?.cnpj),
    balance_after: tx.balance ?? null,
    provider: "pluggy",
    source_type: sourceType,
  };
}

/** Cartão de crédito não é conta corrente: a fatura entra como origem separada. */
export function accountSourceType(account: PluggyAccount): "bank" | "credit_card" {
  return (account.type || "").toUpperCase() === "CREDIT" ? "credit_card" : "bank";
}
