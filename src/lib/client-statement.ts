// Extrato financeiro do cliente em texto (para enviar por WhatsApp / copiar). Lista os lançamentos
// (sinal, saldo, faturas) com vencimento e status, e os totais (total / pago / em aberto). Inclui a
// chave Pix quando há saldo em aberto — mesmo seam do completion (depois vira QR/copia-e-cola).
//
// "Cobrar juntas" (Fase 0, 28/10/2026) é este mesmo extrato filtrado pelas OS escolhidas
// (`servicoIds`): só as contas abertas delas, cada linha com o número da OS e o SALDO.
// Os números seguem a regra única de _shared/receivables/cobrar-juntas.ts (a mesma da ficha):
// antes, cada linha mostrava o valor cheio, "Pago" ignorava o pago parcial e uma conta
// 'pending' de julho aparecia como "a vencer" (o banco nunca grava 'overdue').
import { format, parseISO, isValid } from 'date-fns';
import {
  contaVencida, hojeLocal, pagoDaConta, saldoDaConta,
} from '../../supabase/functions/_shared/receivables/cobrar-juntas';

const brl = (v: number) =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);

function fmtDate(s?: string | null): string {
  if (!s) return '—';
  const d = parseISO(s.slice(0, 10));
  return isValid(d) ? format(d, 'dd/MM/yyyy') : '—';
}

type Situacao = 'paid' | 'overdue' | 'partially_paid' | 'pending';
const STATUS_LABEL: Record<Situacao, string> = {
  paid: 'pago',
  overdue: 'vencido',
  pending: 'a vencer',
  partially_paid: 'parcial',
};
const STATUS_ICON: Record<Situacao, string> = {
  paid: '✅',
  overdue: '🔴',
  partially_paid: '🟠',
  pending: '🟡',
};

export interface StatementItem {
  /** Desempate da ordem (mesma OS e mesmo vencimento), como a tool cobrar_juntas. */
  id?: string | null;
  description?: string | null;
  due_date?: string | null;
  status?: string | null;
  amount?: number | null;
  paid_amount?: number | null;
  balance_amount?: number | null;
  service_order_id?: string | null;
  /** Número da OS da conta ("OS-00045"), mostrado na linha. */
  numero_os?: string | null;
}

export interface ClientStatementInput {
  clientName?: string | null;
  items: StatementItem[];
  /** chave Pix da empresa (Configurações) — incluída quando há saldo em aberto. */
  pixKey?: string | null;
  /**
   * "Cobrar juntas": só as contas destas OS, e só as que têm saldo (sinal já pago fica fora).
   * Ausente = extrato completo do cliente.
   */
  servicoIds?: string[];
  /** Hoje (YYYY-MM-DD), para "vencido". Padrão: a data local. */
  hoje?: string;
}

/** A situação calculada: paga, vencida pela data, parcial ou a vencer. */
function situacaoDa(r: StatementItem, hoje: string): Situacao {
  if (saldoDaConta(r) <= 0) return 'paid';
  if (contaVencida({ id: '', ...r }, hoje)) return 'overdue';
  return pagoDaConta(r) > 0.009 ? 'partially_paid' : 'pending';
}

function rotuloDa(r: StatementItem): string {
  const desc = (r.description || '').trim() || 'Lançamento';
  const os = (r.numero_os || '').trim();
  return os && !desc.includes(os) ? `${os} · ${desc}` : desc;
}

const cent = (v: number) => Math.round(v * 100) / 100;

/** Monta o extrato do cliente em texto. Ignora lançamentos cancelados. */
export function buildClientStatement({ clientName, items, pixKey, servicoIds, hoje = hojeLocal() }: ClientStatementInput): string {
  const nome = (clientName || '').trim().split(/\s+/)[0] || 'Cliente';
  const filtrarOs = Array.isArray(servicoIds);
  const escolhidas = new Set(servicoIds ?? []);
  const active = (items || []).filter((r) => {
    if (r.status === 'cancelled') return false;
    if (!filtrarOs) return true;
    return !!r.service_order_id && escolhidas.has(r.service_order_id) && saldoDaConta(r) > 0;
  });
  const rows = [...active].sort((a, b) =>
    String(a.numero_os ?? '').localeCompare(String(b.numero_os ?? ''))
    || String(a.due_date ?? '').localeCompare(String(b.due_date ?? ''))
    || String(a.id ?? '').localeCompare(String(b.id ?? '')));

  const lines = rows.map((r) => {
    const sit = situacaoDa(r, hoje);
    const pago = pagoDaConta(r);
    const valor = sit === 'paid'
      ? `*${brl(pago || Number(r.amount || 0))}*`
      : `*${brl(saldoDaConta(r))}*${pago > 0.009 ? ` (de ${brl(Number(r.amount || 0))})` : ''}`;
    return `${STATUS_ICON[sit]} ${rotuloDa(r)} · vence ${fmtDate(r.due_date)} · ${STATUS_LABEL[sit]}: ${valor}`;
  });

  // Total − Pago = Em aberto, conta a conta (amount = pago + saldo).
  const total = cent(active.reduce((s, r) => s + Number(r.amount || 0), 0));
  const paid = cent(active.reduce((s, r) => s + pagoDaConta(r), 0));
  const open = cent(active.reduce((s, r) => s + saldoDaConta(r), 0));

  const pixLine = open > 0.009 && pixKey && pixKey.trim() ? `\n\n💠 Para pagar por Pix, use a chave: *${pixKey.trim()}*` : '';

  const numeros = [...new Set(rows.map((r) => (r.numero_os || '').trim()).filter(Boolean))];
  const cabecalho = filtrarOs
    ? `📋 *Cobrança — HBR*\nCliente: ${nome}${numeros.length ? `\nOS: ${numeros.join(', ')}` : ''}\n\n`
    : `📋 *Extrato financeiro — HBR*\nCliente: ${nome}\n\n`;

  return (
    cabecalho +
    (lines.length ? lines.join('\n') : '_Sem lançamentos._') +
    `\n\nTotal: ${brl(total)}\n` +
    `Pago: ${brl(paid)}\n` +
    `*Em aberto: ${brl(open)}*` +
    pixLine +
    `\n\n_Qualquer dúvida sobre os valores, estamos à disposição._`
  );
}
