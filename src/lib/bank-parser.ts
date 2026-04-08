export type BankTransaction = {
  transaction_date: string;
  description: string;
  amount: number;
  transaction_type: 'credit' | 'debit';
  bank_ref_id?: string;
};

export function parseOFX(content: string): BankTransaction[] {
  const results: BankTransaction[] = [];
  const blocks = content.split(/<STMTTRN>/i).slice(1);

  for (const block of blocks) {
    const end = block.indexOf('</STMTTRN>');
    const segment = end >= 0 ? block.substring(0, end) : block;

    const getField = (name: string): string => {
      const regex = new RegExp(`<${name}>([^<\\r\\n]+)`, 'i');
      const match = segment.match(regex);
      return match ? match[1].trim() : '';
    };

    const dateRaw = getField('DTPOSTED');
    const amountRaw = getField('TRNAMT');
    const memo = getField('MEMO') || getField('NAME');
    const fitid = getField('FITID');

    if (!dateRaw || !amountRaw) continue;

    const year = dateRaw.substring(0, 4);
    const month = dateRaw.substring(4, 6);
    const day = dateRaw.substring(6, 8);
    const transaction_date = `${year}-${month}-${day}`;

    const amountNum = parseFloat(amountRaw.replace(',', '.'));
    if (isNaN(amountNum)) continue;

    results.push({
      transaction_date,
      description: memo || 'Sem descrição',
      amount: Math.abs(amountNum),
      transaction_type: amountNum > 0 ? 'credit' : 'debit',
      bank_ref_id: fitid || undefined,
    });
  }

  return results;
}

function parseDate(raw: string): string | null {
  const trimmed = raw.trim();
  // DD/MM/YYYY or DD-MM-YYYY
  let m = trimmed.match(/^(\d{2})[\/\-](\d{2})[\/\-](\d{4})$/);
  if (m) return `${m[3]}-${m[2]}-${m[1]}`;
  // YYYY-MM-DD
  m = trimmed.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (m) return `${m[1]}-${m[2]}-${m[3]}`;
  return null;
}

export function parseCSV(content: string): BankTransaction[] {
  const lines = content.split(/\r?\n/).filter(l => l.trim());
  if (lines.length < 2) return [];

  const delimiter = lines[0].includes(';') ? ';' : ',';
  const headers = lines[0].split(delimiter).map(h => h.trim().toLowerCase().replace(/"/g, ''));

  const dateIdx = headers.findIndex(h => /dat[ea]/.test(h));
  const descIdx = headers.findIndex(h => /descri|memo|histor|lançamento|lancamento/.test(h));
  const creditIdx = headers.findIndex(h => /crédit|credito|credit/.test(h));
  const debitIdx = headers.findIndex(h => /débit|debito|debit/.test(h));
  const amountIdx = headers.findIndex(h => /valor|value|amount|quantia/.test(h));

  if (dateIdx < 0) return [];
  const valueIdx = amountIdx >= 0 ? amountIdx : -1;
  const descFinal = descIdx >= 0 ? descIdx : headers.findIndex((_, i) => i !== dateIdx && i !== valueIdx && i !== creditIdx && i !== debitIdx);

  const results: BankTransaction[] = [];

  for (let i = 1; i < lines.length; i++) {
    const cols = lines[i].split(delimiter).map(c => c.trim().replace(/^"|"$/g, ''));
    const date = parseDate(cols[dateIdx] || '');
    if (!date) continue;

    let amount = 0;
    let type: 'credit' | 'debit' = 'credit';

    if (creditIdx >= 0 && debitIdx >= 0) {
      const cred = parseFloat((cols[creditIdx] || '0').replace(/[^\d,.\-]/g, '').replace(',', '.'));
      const deb = parseFloat((cols[debitIdx] || '0').replace(/[^\d,.\-]/g, '').replace(',', '.'));
      if (!isNaN(cred) && cred > 0) { amount = cred; type = 'credit'; }
      else if (!isNaN(deb) && deb > 0) { amount = deb; type = 'debit'; }
      else continue;
    } else if (valueIdx >= 0) {
      const val = parseFloat((cols[valueIdx] || '0').replace(/[^\d,.\-]/g, '').replace(',', '.'));
      if (isNaN(val) || val === 0) continue;
      amount = Math.abs(val);
      type = val > 0 ? 'credit' : 'debit';
    } else continue;

    results.push({
      transaction_date: date,
      description: (descFinal >= 0 ? cols[descFinal] : '') || 'Sem descrição',
      amount,
      transaction_type: type,
    });
  }

  return results;
}

export function parseFile(content: string, filename: string): BankTransaction[] {
  const ext = filename.toLowerCase().split('.').pop() || '';
  if (ext === 'ofx') return parseOFX(content);
  // .csv, .xls, .xlsx — try CSV (many banks export HTML/CSV as .xls)
  return parseCSV(content);
}
