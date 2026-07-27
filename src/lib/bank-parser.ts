export type BankTransaction = {
  transaction_date: string;
  description: string;
  amount: number;
  transaction_type: 'credit' | 'debit';
  bank_ref_id?: string;
  pix_end_to_end_id?: string;
  counterparty_name?: string;
  counterparty_document?: string;
};

/**
 * Decodifica o arquivo de extrato respeitando o encoding do banco.
 *
 * Bancos brasileiros exportam OFX em ISO-8859-1/Windows-1252 com a mesma frequência
 * que em UTF-8, e ler Latin-1 como UTF-8 corrompe todo acento ("TRANSFERÊNCIA" vira
 * "TRANSFER<caractere inválido>NCIA"). Em vez de confiar no header declarado (que
 * vários bancos preenchem errado), tenta UTF-8 estrito: se falhar, é Latin-1.
 */
export function decodeStatementFile(buffer: ArrayBuffer): string {
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(buffer);
  } catch {
    return new TextDecoder('windows-1252').decode(buffer);
  }
}

const XML_ENTITIES: Record<string, string> = {
  '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&apos;': "'", '&#39;': "'",
};

function decodeEntities(text: string): string {
  return text.replace(/&(?:amp|lt|gt|quot|apos|#39);/g, (m) => XML_ENTITIES[m] ?? m);
}

/**
 * EndToEndId do Pix: "E" + ISPB (8 dígitos) + data/hora (12 dígitos) + 11 alfanuméricos.
 * É o identificador único da transação no SPI — o casamento mais forte que existe
 * entre uma linha do extrato e uma cobrança emitida.
 */
const PIX_E2E_REGEX = /\bE\d{20}[A-Za-z0-9]{11}\b/;
const CNPJ_REGEX = /\b\d{2}\.?\d{3}\.?\d{3}\/?\d{4}-?\d{2}\b/;
const CPF_REGEX = /\b\d{3}\.?\d{3}\.?\d{3}-?\d{2}\b/;

function onlyDigits(value: string): string {
  return value.replace(/\D/g, '');
}

/**
 * Converte valor monetário para número aceitando as duas convenções que aparecem
 * em extratos: brasileira ("1.450,00") e internacional ("1,450.00").
 *
 * Distingue pela posição: o separador decimal é sempre o ÚLTIMO a aparecer. Tratar
 * o ponto como decimal sem essa checagem transforma R$ 1.450,00 em R$ 1,45 —
 * silenciosamente, porque o resultado continua sendo um número válido.
 */
export function parseAmount(raw: string): number {
  const cleaned = (raw || '').replace(/[^\d,.\-]/g, '');
  if (!cleaned) return NaN;
  const lastComma = cleaned.lastIndexOf(',');
  const lastDot = cleaned.lastIndexOf('.');
  const normalized = lastComma > lastDot
    ? cleaned.replace(/\./g, '').replace(',', '.')  // milhar com ponto, decimal com vírgula
    : cleaned.replace(/,/g, '');                    // milhar com vírgula, decimal com ponto
  return parseFloat(normalized);
}

/** Extrai CNPJ (preferido) ou CPF do texto livre do lançamento. */
function extractDocument(text: string): string | undefined {
  const cnpj = text.match(CNPJ_REGEX);
  if (cnpj) return onlyDigits(cnpj[0]);
  const cpf = text.match(CPF_REGEX);
  if (cpf && onlyDigits(cpf[0]).length === 11) return onlyDigits(cpf[0]);
  return undefined;
}

/** Converte DTPOSTED (YYYYMMDD, podendo vir com hora e fuso) para YYYY-MM-DD. */
function parseOFXDate(raw: string): string | null {
  const digits = raw.trim().replace(/\[.*$/, '');
  if (digits.length < 8) return null;
  const year = digits.substring(0, 4);
  const month = digits.substring(4, 6);
  const day = digits.substring(6, 8);
  if (!/^\d{4}$/.test(year) || !/^\d{2}$/.test(month) || !/^\d{2}$/.test(day)) return null;
  return `${year}-${month}-${day}`;
}

export function parseOFX(content: string): BankTransaction[] {
  const results: BankTransaction[] = [];
  const blocks = content.split(/<STMTTRN>/i).slice(1);

  for (const block of blocks) {
    const end = block.search(/<\/STMTTRN>/i);
    const segment = end >= 0 ? block.substring(0, end) : block;

    const getField = (name: string): string => {
      // Serve tanto para OFX SGML (<TAG>valor, sem fechamento) quanto XML
      // (<TAG>valor</TAG>): em ambos o valor termina no próximo '<' ou quebra de linha.
      const match = segment.match(new RegExp(`<${name}>([^<\\r\\n]*)`, 'i'));
      return match ? decodeEntities(match[1].trim()) : '';
    };

    const transaction_date = parseOFXDate(getField('DTPOSTED'));
    const amountRaw = getField('TRNAMT');
    if (!transaction_date || !amountRaw) continue;

    // Bancos usam vírgula ou ponto como separador decimal; o sinal define o tipo.
    const amountNum = parseAmount(amountRaw);
    if (isNaN(amountNum) || amountNum === 0) continue;

    const memo = getField('MEMO');
    const name = getField('NAME');
    const fullText = [memo, name].filter(Boolean).join(' ');
    // TRNTYPE é a intenção declarada pelo banco; o sinal do valor é a verdade
    // contábil. Quando divergem (alguns bancos mandam DEBIT com valor positivo),
    // o sinal vence, exceto quando o próprio TRNTYPE é explícito.
    const trnType = getField('TRNTYPE').toUpperCase();
    const isDebitType = trnType === 'DEBIT' || trnType === 'PAYMENT' || trnType === 'FEE';
    const isCreditType = trnType === 'CREDIT' || trnType === 'DEP' || trnType === 'DIRECTDEP';

    let transaction_type: 'credit' | 'debit' = amountNum > 0 ? 'credit' : 'debit';
    if (amountNum > 0 && isDebitType) transaction_type = 'debit';
    if (amountNum < 0 && isCreditType) transaction_type = 'credit';

    const e2e = fullText.match(PIX_E2E_REGEX);
    const fitid = getField('FITID');

    results.push({
      transaction_date,
      description: memo || name || 'Sem descrição',
      amount: Math.abs(amountNum),
      transaction_type,
      bank_ref_id: fitid || undefined,
      pix_end_to_end_id: e2e ? e2e[0] : undefined,
      counterparty_name: name && name !== memo ? name : undefined,
      counterparty_document: extractDocument(fullText),
    });
  }

  return results;
}

function parseDate(raw: string): string | null {
  const trimmed = raw.trim();
  // DD/MM/YYYY ou DD-MM-YYYY
  let m = trimmed.match(/^(\d{2})[\/\-](\d{2})[\/\-](\d{4})$/);
  if (m) return `${m[3]}-${m[2]}-${m[1]}`;
  // YYYY-MM-DD
  m = trimmed.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (m) return `${m[1]}-${m[2]}-${m[3]}`;
  return null;
}

/**
 * Divide uma linha de CSV respeitando aspas: descrições de lançamento com vírgula
 * ("PAGAMENTO, PARCELA 2") são comuns e um split direto no delimitador deslocaria
 * todas as colunas seguintes, corrompendo data e valor sem erro aparente.
 */
function splitCSVLine(line: string, delimiter: string): string[] {
  const out: string[] = [];
  let current = '';
  let inQuotes = false;

  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === '"') {
      if (inQuotes && line[i + 1] === '"') { current += '"'; i++; }  // aspas escapadas
      else inQuotes = !inQuotes;
    } else if (ch === delimiter && !inQuotes) {
      out.push(current);
      current = '';
    } else {
      current += ch;
    }
  }
  out.push(current);
  return out.map(c => c.trim());
}

export function parseCSV(content: string): BankTransaction[] {
  const lines = content.split(/\r?\n/).filter(l => l.trim());
  if (lines.length < 2) return [];

  const delimiter = lines[0].includes(';') ? ';' : ',';
  const headers = splitCSVLine(lines[0], delimiter).map(h => h.toLowerCase().replace(/"/g, ''));

  const dateIdx = headers.findIndex(h => /dat[ea]/.test(h));
  const descIdx = headers.findIndex(h => /descri|memo|histor|lançamento|lancamento/.test(h));
  const creditIdx = headers.findIndex(h => /crédit|credito|credit/.test(h));
  const debitIdx = headers.findIndex(h => /débit|debito|debit/.test(h));
  const amountIdx = headers.findIndex(h => /valor|value|amount|quantia/.test(h));
  const idIdx = headers.findIndex(h => /identificador|id da transa|transaction.?id|fitid/.test(h));

  if (dateIdx < 0) return [];
  const valueIdx = amountIdx >= 0 ? amountIdx : -1;
  const descFinal = descIdx >= 0 ? descIdx : headers.findIndex((_, i) => i !== dateIdx && i !== valueIdx && i !== creditIdx && i !== debitIdx);

  const results: BankTransaction[] = [];

  for (let i = 1; i < lines.length; i++) {
    const cols = splitCSVLine(lines[i], delimiter);
    const date = parseDate(cols[dateIdx] || '');
    if (!date) continue;

    let amount = 0;
    let type: 'credit' | 'debit' = 'credit';

    if (creditIdx >= 0 && debitIdx >= 0) {
      const cred = parseAmount(cols[creditIdx] || '0');
      const deb = parseAmount(cols[debitIdx] || '0');
      if (!isNaN(cred) && cred > 0) { amount = cred; type = 'credit'; }
      else if (!isNaN(deb) && deb > 0) { amount = deb; type = 'debit'; }
      else continue;
    } else if (valueIdx >= 0) {
      const val = parseAmount(cols[valueIdx] || '0');
      if (isNaN(val) || val === 0) continue;
      amount = Math.abs(val);
      type = val > 0 ? 'credit' : 'debit';
    } else continue;

    const description = (descFinal >= 0 ? cols[descFinal] : '') || 'Sem descrição';
    // Nubank e outros exportam CSV com coluna de identificador — quando existe,
    // o CSV também ganha dedupe; sem ela, a importação de CSV segue sem proteção.
    const rowId = idIdx >= 0 ? (cols[idIdx] || '').trim() : '';
    const e2e = description.match(PIX_E2E_REGEX);

    results.push({
      transaction_date: date,
      description,
      amount,
      transaction_type: type,
      bank_ref_id: rowId || undefined,
      pix_end_to_end_id: e2e ? e2e[0] : undefined,
      counterparty_document: extractDocument(description),
    });
  }

  return results;
}

export function detectFileSource(filename: string, content: string): 'bank' | 'credit_card' {
  const fn = filename.toLowerCase();
  if (/fatura|cartao|cartão|card|credit/.test(fn)) return 'credit_card';
  if (/<ACCTTYPE>CREDITLINE/i.test(content) || /<CREDITCARDMSGSRSV1/i.test(content)) return 'credit_card';
  return 'bank';
}

/**
 * Remove repetições dentro do próprio arquivo (bancos às vezes repetem o mesmo
 * lançamento no OFX). Linhas sem identificador não são tocadas: sem FITID não há
 * como afirmar que duas linhas iguais não são duas transações de fato iguais.
 */
export function dedupeByRef(transactions: BankTransaction[]): BankTransaction[] {
  const seen = new Set<string>();
  return transactions.filter(t => {
    if (!t.bank_ref_id) return true;
    if (seen.has(t.bank_ref_id)) return false;
    seen.add(t.bank_ref_id);
    return true;
  });
}

export function parseFile(content: string, filename: string): { transactions: BankTransaction[]; source_type: 'bank' | 'credit_card' } {
  const ext = filename.toLowerCase().split('.').pop() || '';
  const source_type = detectFileSource(filename, content);
  const transactions = ext === 'ofx' ? parseOFX(content) : parseCSV(content);
  return { transactions: dedupeByRef(transactions), source_type };
}
