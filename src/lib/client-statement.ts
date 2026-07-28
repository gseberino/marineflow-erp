// Extrato financeiro do cliente em texto (para enviar por WhatsApp / copiar). Lista os lançamentos
// (sinal, saldo, faturas) com vencimento e status, e os totais (total / pago / em aberto). Inclui a
// chave Pix quando há saldo em aberto — mesmo seam do completion (depois vira QR/copia-e-cola).
import { format, parseISO, isValid } from 'date-fns';

const brl = (v: number) =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);

function fmtDate(s?: string | null): string {
  if (!s) return '—';
  const d = parseISO(s.slice(0, 10));
  return isValid(d) ? format(d, 'dd/MM/yyyy') : '—';
}

const STATUS_LABEL: Record<string, string> = {
  paid: 'pago',
  overdue: 'vencido',
  pending: 'a vencer',
  partially_paid: 'parcial',
};
const STATUS_ICON: Record<string, string> = {
  paid: '✅',
  overdue: '🔴',
  partially_paid: '🟠',
  pending: '🟡',
};

export interface StatementItem {
  description?: string | null;
  due_date?: string | null;
  status?: string | null;
  amount?: number | null;
  balance_amount?: number | null;
}

export interface ClientStatementInput {
  clientName?: string | null;
  items: StatementItem[];
  /** chave Pix da empresa (Configurações) — incluída quando há saldo em aberto. */
  pixKey?: string | null;
}

/** Monta o extrato do cliente em texto. Ignora lançamentos cancelados. */
export function buildClientStatement({ clientName, items, pixKey }: ClientStatementInput): string {
  const nome = (clientName || '').trim().split(/\s+/)[0] || 'Cliente';
  const active = (items || []).filter((r) => r.status !== 'cancelled');
  const rows = [...active].sort((a, b) => String(a.due_date).localeCompare(String(b.due_date)));

  const lines = rows.map((r) => {
    const st = STATUS_LABEL[r.status || 'pending'] || r.status || '';
    const icon = STATUS_ICON[r.status || 'pending'] || '🟡';
    return `${icon} ${r.description || 'Lançamento'} · vence ${fmtDate(r.due_date)} · ${st}: *${brl(Number(r.amount || 0))}*`;
  });

  const total = active.reduce((s, r) => s + Number(r.amount || 0), 0);
  const paid = active
    .filter((r) => r.status === 'paid')
    .reduce((s, r) => s + Number(r.amount || 0), 0);
  const open = active.reduce(
    (s, r) => (r.status === 'paid' ? s : s + Number(r.balance_amount ?? r.amount ?? 0)),
    0,
  );

  const pixLine = open > 0.009 && pixKey && pixKey.trim() ? `\n\n💠 Para pagar por Pix, use a chave: *${pixKey.trim()}*` : '';

  return (
    `📋 *Extrato financeiro — HBR*\n` +
    `Cliente: ${nome}\n\n` +
    (lines.length ? lines.join('\n') : '_Sem lançamentos._') +
    `\n\nTotal: ${brl(total)}\n` +
    `Pago: ${brl(paid)}\n` +
    `*Em aberto: ${brl(open)}*` +
    pixLine +
    `\n\n_Qualquer dúvida sobre os valores, estamos à disposição._`
  );
}
