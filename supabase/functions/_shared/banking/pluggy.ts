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
  paymentData?: {
    payer?: { name?: string | null; documentNumber?: { value?: string | null } | null } | null;
    receiver?: { name?: string | null; documentNumber?: { value?: string | null } | null } | null;
    paymentMethod?: string | null;
    referenceNumber?: string | null;
    reason?: string | null;
  } | null;
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

export async function fetchAccounts(apiKey: string, itemId: string): Promise<PluggyAccount[]> {
  const data = await pluggyGet(apiKey, `/accounts?itemId=${encodeURIComponent(itemId)}`);
  return (data?.results ?? []) as PluggyAccount[];
}

/**
 * Transações de uma conta. Pagina até o fim porque extrato parcial é pior que nenhum:
 * some no meio sem avisar e a conciliação passa a mentir sobre o que falta.
 */
export async function fetchTransactions(
  apiKey: string,
  accountId: string,
  from?: string | null,
  maxPages = 20,
): Promise<PluggyTransaction[]> {
  const todas: PluggyTransaction[] = [];
  for (let page = 1; page <= maxPages; page++) {
    const params = new URLSearchParams({
      accountId,
      page: String(page),
      pageSize: "200",
    });
    if (from) params.set("from", from);
    const data = await pluggyGet(apiKey, `/transactions?${params.toString()}`);
    const lote = (data?.results ?? []) as PluggyTransaction[];
    todas.push(...lote);
    const totalPages = Number(data?.totalPages ?? 1);
    if (page >= totalPages || lote.length === 0) break;
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
export function mapTransaction(
  tx: PluggyTransaction,
  sourceType: "bank" | "credit_card" = "bank",
): ExtratoRow {
  const ehCredito = tx.type === "CREDIT";
  // A contraparte é quem pagou quando entra dinheiro, e quem recebeu quando sai.
  const contraparte = ehCredito ? tx.paymentData?.payer : tx.paymentData?.receiver;

  const referencia = tx.paymentData?.referenceNumber ?? null;
  const ehPix = (tx.paymentData?.paymentMethod ?? "").toUpperCase() === "PIX";

  return {
    transaction_date: String(tx.date).slice(0, 10),
    description: tx.description || tx.descriptionRaw || "Sem descrição",
    amount: Math.abs(Number(tx.amount) || 0),
    transaction_type: ehCredito ? "credit" : "debit",
    bank_ref_id: tx.id,
    // Só grava como EndToEndId o que tem cara de EndToEndId: outros métodos usam o mesmo
    // campo de referência para números que não identificam nada no SPI.
    pix_end_to_end_id: ehPix && referencia && PIX_E2E.test(referencia) ? referencia : null,
    counterparty_name: contraparte?.name ?? null,
    counterparty_document: somenteDigitos(contraparte?.documentNumber?.value),
    balance_after: tx.balance ?? null,
    provider: "pluggy",
    source_type: sourceType,
  };
}

/** Cartão de crédito não é conta corrente: a fatura entra como origem separada. */
export function accountSourceType(account: PluggyAccount): "bank" | "credit_card" {
  return (account.type || "").toUpperCase() === "CREDIT" ? "credit_card" : "bank";
}
