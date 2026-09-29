// Contas a Pagar › Em aberto: o que a empresa ainda deve pagar.
//
// Saiu de dentro de FinancialV2 (26/09/2026) quando cada assunto do Financeiro ganhou a sua
// tela. O comportamento é o mesmo: abre no que está em aberto, "Mostrar as já pagas" a um
// clique, filtros, agrupamento, CSV e as ações de linha (Pagar à vista, o resto no menu).
import { useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Ban, Download, DollarSign, Paperclip, Pencil, Plus, Undo2 } from 'lucide-react';
import { useI18n } from '@/i18n';
import { usePayables } from '@/hooks/use-financial';
import { exportToCSV } from '@/lib/export';
import { comoDiaLocal, diasAte } from '@/lib/dia';
import { origemDoDinheiro, type ContaDaHBR, type LinhaDeOrigem } from '@/lib/origem-do-dinheiro';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';
import { FinancialFilterPanel, applyFilters, defaultFilters, type FinancialFilters } from '@/components/FinancialFilterPanel';
import { PaymentDialog } from '@/components/PaymentDialog';
import { CorrigirLancamentoDialog } from '@/components/CorrigirLancamentoDialog';
import { DesfazerOuCancelarDialog, type AcaoNoLancamento } from '@/components/DesfazerOuCancelarDialog';
import { AcoesDaLinha, type AcaoDaLinha } from '@/components/AcoesDaLinha';
import { LinkDoArquivo } from '@/lib/arquivo-privado';
import { StatusChip, type StatusTone } from '@/v2/components/StatusChip';
import { DataTable, type DataColumn, type SortState } from '@/v2/components/DataTable';

type PayableRow = {
  id: string;
  description: string;
  name?: string | null;
  amount: number | null;
  paid_amount?: number | null;
  balance_amount?: number | null;
  status?: string | null;
  due_date: string;
  notes?: string | null;
  expense_category?: string | null;
  origin?: string | null;
  receipt_url?: string | null;
  linked_service_order_id?: string | null;
  issue_date?: string | null;
  bank_transaction_id?: string | null;
  supplier_id?: string | null;
  payee_id?: string | null;
  cost_center_id?: string | null;
  suppliers?: { name?: string } | null;
  service_orders?: { service_order_number?: string } | null;
  service_order_expenses?: { receipt_url?: string | null }[] | null;
  /** A linha do banco que pagou: de qual conta ou cartão saiu. */
  bank_transactions?: (LinhaDeOrigem & { bank_connections?: ContaDaHBR | null }) | null;
};

/** "Conta C6", "Cartão Nubank final 4922"… — null enquanto nada saiu do banco. */
const deOndeSaiu = (p: PayableRow) => origemDoDinheiro(p.bank_transactions, p.bank_transactions?.bank_connections);

/** Situações de uma conta que ainda se deve — o recorte com que Contas a Pagar abre. */
const STATUS_EM_ABERTO = ['pending', 'partially_paid', 'overdue'];

// Vencimento é um dia do calendário (src/lib/dia.ts): a conta que vence hoje não está em atraso.
const isOverdue = (p: PayableRow) => p.status !== 'paid' && p.status !== 'cancelled' && !!p.due_date && diasAte(p.due_date) < 0;

function statusView(p: PayableRow): { label: string; tone: StatusTone } {
  if (isOverdue(p)) return { label: 'Em atraso', tone: 'critical' };
  if (p.status === 'paid') return { label: 'Pago', tone: 'success' };
  if (p.status === 'partially_paid') return { label: 'Parcial', tone: 'warning' };
  if (p.status === 'cancelled') return { label: 'Cancelado', tone: 'neutral' };
  return { label: 'Em aberto', tone: 'neutral' };
}

function dueAlert(p: PayableRow): { label: string; tone: StatusTone } | null {
  if (p.status === 'paid' || p.status === 'cancelled') return null;
  if (!p.due_date) return null;
  const diff = diasAte(p.due_date);
  if (diff < 0) return { label: `${Math.abs(diff)}d em atraso`, tone: 'critical' };
  if (diff === 0) return { label: 'Vence hoje', tone: 'critical' };
  if (diff <= 7) return { label: `Vence em ${diff}d`, tone: 'warning' };
  return null;
}

const originView = (origin: string | null | undefined): { label: string; tone: StatusTone } => {
  switch (origin) {
    case 'service_order_expense': return { label: 'Despesa de OS', tone: 'info' };
    case 'bank_reconciliation': return { label: 'Conciliação', tone: 'info' };
    default: return { label: 'Manual', tone: 'neutral' };
  }
};

type GroupBy = 'none' | 'category' | 'supplier' | 'month';

function groupPayables(payables: PayableRow[], groupBy: GroupBy): Record<string, PayableRow[]> {
  if (groupBy === 'none') return { Todos: payables };
  const groups: Record<string, PayableRow[]> = {};
  const keyOf = (p: PayableRow) => {
    if (groupBy === 'category') return p.expense_category || 'Sem categoria';
    if (groupBy === 'supplier') return p.suppliers?.name || p.name || 'Sem fornecedor';
    return p.due_date ? comoDiaLocal(p.due_date).toLocaleDateString('pt-BR', { month: 'long', year: 'numeric' }) : 'Sem vencimento';
  };
  for (const p of payables) {
    const k = keyOf(p);
    (groups[k] ??= []).push(p);
  }
  return groups;
}

export function ContasAPagarLista({ onNovaConta }: {
  /** "Nova conta a pagar" abre o "+ Lançar" da tela, já em despesa a pagar depois. */
  onNovaConta: () => void;
}) {
  const { t, formatCurrency, formatDate } = useI18n();
  const navigate = useNavigate();
  const { data: payData, isLoading: loadingPay, error: payError } = usePayables();
  const payables = useMemo(() => (payData ?? []) as unknown as PayableRow[], [payData]);

  // D6/F5: contas a pagar abre em "em aberto" (pendente, parcial, vencida). 1.675 das 1.679 contas
  // estão pagas; abrir com tudo obrigava a filtrar antes de qualquer trabalho. "Pago" continua
  // a um clique no painel de filtros.
  const [payFilters, setPayFilters] = useState<FinancialFilters>({ ...defaultFilters, status: STATUS_EM_ABERTO });
  const [payOsSearch, setPayOsSearch] = useState('');
  const [groupBy, setGroupBy] = useState<GroupBy>('none');
  const [paySort, setPaySort] = useState<SortState>({ key: 'due_date', dir: 'asc' });
  const [paymentTarget, setPaymentTarget] = useState<PayableRow | null>(null);
  const [editingPayable, setEditingPayable] = useState<PayableRow | null>(null);
  // Desfazer e cancelar pedem confirmação com motivo — ver DesfazerOuCancelarDialog.
  const [acaoNaConta, setAcaoNaConta] = useState<{ acao: AcaoNoLancamento; conta: PayableRow } | null>(null);

  /**
   * "Contas a pagar" mostra o que se DEVE, não o histórico de despesa.
   *
   * A lista trazia as 1.663 despesas já quitadas junto com as 4 obrigações em aberto —
   * quase quatrocentas vindas de compra no cartão, cada uma parecendo uma conta a pagar.
   * Não são: a compra está paga do ponto de vista do gestor, e quem ele deve é o banco,
   * pela FATURA. O histórico continua alcançável — é o botão "Mostrar já pagas".
   */
  const [mostrarPagas, setMostrarPagas] = useState(false);

  /**
   * As ações de uma conta a pagar, em qualquer situação — inclusive paga. Pagar fica à vista
   * porque é o uso de todo dia; o resto vai para o menu, e o cancelamento por último.
   */
  const acoesDaConta = (p: PayableRow): { rapidas: AcaoDaLinha[]; menu: AcaoDaLinha[] } => {
    const viva = p.status !== 'cancelled';
    const emAberto = viva && p.status !== 'paid';
    return {
      rapidas: emAberto ? [{ texto: 'Pagar', icone: DollarSign, titulo: 'Registrar pagamento', onClick: () => setPaymentTarget(p) }] : [],
      menu: [
        ...(viva ? [{ texto: 'Corrigir', icone: Pencil, titulo: 'Fornecedor, categoria, OS, datas, valor', onClick: () => setEditingPayable(p) }] : []),
        ...(viva && p.bank_transaction_id
          ? [{ texto: 'Desfazer aprovação', icone: Undo2, titulo: 'A linha do extrato volta para a fila', onClick: () => setAcaoNaConta({ acao: 'desfazer', conta: p }) }]
          : []),
        ...(viva ? [{ texto: 'Cancelar lançamento', icone: Ban, perigo: true, onClick: () => setAcaoNaConta({ acao: 'cancelar', conta: p }) }] : []),
      ],
    };
  };

  const filteredPayables = useMemo(() => {
    const base = (applyFilters(payables as never[], payFilters, 'payable') as unknown as PayableRow[])
      .filter((p) => mostrarPagas || (p.status !== 'paid' && p.status !== 'cancelled'))
      .filter((p) => !payOsSearch || p.service_orders?.service_order_number?.toLowerCase().includes(payOsSearch.toLowerCase()));
    return [...base].sort((a, b) => {
      const val = (p: PayableRow) =>
        ['amount', 'balance_amount', 'paid_amount'].includes(paySort.key)
          ? Number((p as Record<string, unknown>)[paySort.key] ?? 0)
          : String((p as Record<string, unknown>)[paySort.key] ?? '');
      const av = val(a);
      const bv = val(b);
      if (av < bv) return paySort.dir === 'asc' ? -1 : 1;
      if (av > bv) return paySort.dir === 'asc' ? 1 : -1;
      return 0;
    });
  }, [payables, payFilters, payOsSearch, paySort, mostrarPagas]);

  const pagasEscondidas = useMemo(
    // Só as pagas: é o que o botão passa a mostrar (cancelada não é despesa).
    () => payables.filter((p) => p.status === 'paid').length,
    [payables],
  );

  const payTotalBalance = filteredPayables.filter((p) => p.status !== 'paid' && p.status !== 'cancelled').reduce((s, p) => s + Number(p.balance_amount ?? 0), 0);
  const payTotalPaid = filteredPayables.reduce((s, p) => s + Number(p.paid_amount ?? 0), 0);
  const payTotalAmount = filteredPayables.reduce((s, p) => s + Number(p.amount ?? 0), 0);
  const grouped = useMemo(() => groupPayables(filteredPayables, groupBy), [filteredPayables, groupBy]);

  const handlePaySort = (key: string) => {
    setPaySort((prev) => (prev.key === key ? { key, dir: prev.dir === 'asc' ? 'desc' : 'asc' } : { key, dir: key === 'due_date' ? 'asc' : 'desc' }));
  };

  const payColumns: DataColumn<PayableRow>[] = [
    {
      key: 'due_date', header: t.financial.dueDate, minWidth: 126, priority: 0, sortable: true,
      render: (p) => {
        const alert = dueAlert(p);
        return (
          <span className="block leading-tight">
            <span className="block">{formatDate(p.due_date)}</span>
            {alert && <StatusChip tone={alert.tone} className="mt-0.5">{alert.label}</StatusChip>}
          </span>
        );
      },
    },
    {
      key: 'who', header: 'Fornecedor · Descrição', minWidth: 225, priority: 1, detailLabel: 'Fornecedor',
      render: (p) => (
        <span className="block leading-tight">
          <span className="block truncate font-semibold">{p.suppliers?.name || p.name || '—'}</span>
          <span className="block truncate text-xs text-muted-foreground" title={p.notes ?? undefined}>{p.description}</span>
        </span>
      ),
    },
    {
      key: 'status', header: t.common.status, minWidth: 110, priority: 2, detailLabel: 'Status',
      render: (p) => {
        const s = statusView(p);
        return <StatusChip dot tone={s.tone}>{s.label}</StatusChip>;
      },
    },
    {
      key: 'balance_amount', header: t.common.balance, minWidth: 116, priority: 2, align: 'right', sortable: true, detailLabel: 'Saldo',
      render: (p) => <span className="font-semibold">{formatCurrency(Number(p.balance_amount ?? 0))}</span>,
    },
    {
      key: 'category', header: 'Categoria', minWidth: 128, priority: 3, detailLabel: 'Categoria',
      render: (p) => (p.expense_category ? <StatusChip tone="neutral">{p.expense_category}</StatusChip> : <span className="text-muted-foreground">—</span>),
    },
    {
      key: 'os', header: 'OS', minWidth: 100, priority: 4, detailLabel: 'OS',
      render: (p) =>
        p.service_orders?.service_order_number ? (
          <button
            type="button"
            className="font-semibold text-accent underline-offset-2 hover:underline"
            onClick={(e) => { e.stopPropagation(); if (p.linked_service_order_id) navigate(`/v2/service-orders/${p.linked_service_order_id}`); }}
          >
            {p.service_orders.service_order_number}
          </button>
        ) : (
          <span className="text-muted-foreground">—</span>
        ),
    },
    {
      key: 'amount', header: t.common.total, minWidth: 112, priority: 4, align: 'right', sortable: true, detailLabel: 'Valor',
      render: (p) => formatCurrency(Number(p.amount ?? 0)),
    },
    {
      key: 'paid_amount', header: 'Pago', minWidth: 108, priority: 5, align: 'right', sortable: true, detailLabel: 'Pago',
      render: (p) => (
        <span className={Number(p.paid_amount) > 0 ? 'text-success' : 'text-muted-foreground'}>{formatCurrency(Number(p.paid_amount ?? 0))}</span>
      ),
    },
    {
      key: 'origin', header: 'Origem', minWidth: 118, priority: 5, detailLabel: 'Origem',
      // Como a conta nasceu e, quando já saiu do banco, de qual conta ou cartão (28/09/2026).
      render: (p) => {
        const o = originView(p.origin);
        const deOnde = deOndeSaiu(p);
        return (
          <span className="block leading-tight">
            <StatusChip tone={o.tone}>{o.label}</StatusChip>
            {deOnde && <span className="mt-0.5 block text-xs text-muted-foreground">{deOnde}</span>}
          </span>
        );
      },
    },
    {
      key: 'receipt', header: 'Comprovante', minWidth: 104, priority: 6, detailLabel: 'Comprovante',
      render: (p) => {
        const soeReceipt = p.service_order_expenses?.find?.((e) => e?.receipt_url)?.receipt_url;
        const url = soeReceipt || p.receipt_url;
        if (!url) return <span className="text-muted-foreground">—</span>;
        // Bucket privado: o link temporário é gerado no clique (LinkDoArquivo já para o clique na linha).
        return (
          <LinkDoArquivo
            bucket="expense-receipts" valor={url} title="Ver comprovante"
            className="inline-flex items-center gap-1 text-accent underline-offset-2 hover:underline"
          >
            <Paperclip className="h-4 w-4" /> Ver
          </LinkDoArquivo>
        );
      },
    },
  ];

  const payTable = (rows: PayableRow[]) => (
    <DataTable<PayableRow>
      rows={rows}
      rowKey={(p) => p.id}
      columns={payColumns}
      sort={paySort}
      onSort={handlePaySort}
      emptyMessage={t.common.noResults}
      rowClassName={(p) => (isOverdue(p) ? 'bg-destructive/5' : undefined)}
      rowActions={(p) => {
        const { rapidas, menu } = acoesDaConta(p);
        return <AcoesDaLinha rotulo={p.description} rapidas={rapidas} menu={menu} tituloDoMenu={p.suppliers?.name || p.name || undefined} />;
      }}
    />
  );

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        {/* A lista é de obrigação VIVA. Despesa já quitada — inclusive as centenas de compras
            no cartão — é história, e história se lê no resultado. Fica a um clique. */}
        <div className="flex flex-wrap items-center gap-2">
          {pagasEscondidas > 0 && (
            <Button size="sm" variant={mostrarPagas ? 'secondary' : 'ghost'}
              // O filtro de situação abre em "em aberto"; sem soltá-lo junto, o botão tirava
              // uma trava e a outra continuava escondendo tudo o que foi pago.
              onClick={() => {
                const novo = !mostrarPagas;
                setMostrarPagas(novo);
                setPayFilters((f) => ({ ...f, status: novo ? [...STATUS_EM_ABERTO, 'paid'] : STATUS_EM_ABERTO }));
              }}>
              {mostrarPagas ? 'Só o que está em aberto' : `Mostrar as ${pagasEscondidas} já pagas`}
            </Button>
          )}
          {/* O que já saiu, com a categoria de cada gasto, mora em Despesas. */}
          <Button size="sm" variant="link" className="h-8 px-1 text-xs" onClick={() => navigate('/v2/financial/despesas')}>
            Ver o que já saiu (Despesas)
          </Button>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button
            variant="outline" size="sm" className="gap-1.5"
            onClick={() =>
              exportToCSV(filteredPayables as never[], 'pagaveis', [
                { key: 'description', label: 'Descrição' },
                { key: 'amount', label: 'Valor', format: (v: number | null) => Number(v || 0).toFixed(2).replace('.', ',') },
                { key: 'due_date', label: 'Vencimento', format: (v: string | null) => (v ? comoDiaLocal(v).toLocaleDateString('pt-BR') : '') },
                { key: 'status', label: 'Status' },
                { key: 'name', label: 'Fornecedor' },
                {
                  key: 'bank_transactions', label: 'De onde saiu',
                  format: (bt: PayableRow['bank_transactions']) => origemDoDinheiro(bt, bt?.bank_connections) ?? '',
                },
              ] as never)
            }
          >
            <Download className="h-4 w-4" /> Exportar CSV
          </Button>
          <Button size="sm" className="gap-1.5" onClick={onNovaConta}>
            <Plus className="h-4 w-4" /> Nova conta a pagar
          </Button>
        </div>
      </div>

      <FinancialFilterPanel type="payable" filters={payFilters} onChange={setPayFilters} />
      <div className="flex flex-wrap items-center gap-3">
        <Input
          placeholder="Filtrar por número da OS"
          value={payOsSearch}
          onChange={(e) => setPayOsSearch(e.target.value)}
          className="h-9 w-full sm:w-64"
        />
        <div className="flex flex-wrap items-center gap-1">
          <span className="text-sm text-muted-foreground">{t.financial.groupBy}:</span>
          {([
            { v: 'none', l: t.financial.groupByNone },
            { v: 'category', l: t.financial.groupByCategory },
            { v: 'supplier', l: t.financial.groupBySupplier },
            { v: 'month', l: t.financial.groupByMonth },
          ] as { v: GroupBy; l: string }[]).map(({ v, l }) => (
            <Button key={v} size="sm" variant={groupBy === v ? 'secondary' : 'ghost'} onClick={() => setGroupBy(v)}>{l}</Button>
          ))}
        </div>
      </div>

      {payError ? (
        // Lista vazia com erro escondido parece "não devo nada" — o erro tem de aparecer.
        <div className="rounded-lg border border-destructive/40 bg-destructive/5 p-4 text-sm text-destructive">
          Erro ao carregar as contas a pagar: {(payError as Error).message || 'verifique sua conexão.'}
        </div>
      ) : loadingPay ? (
        <Skeleton className="h-64 w-full rounded-lg" />
      ) : groupBy === 'none' ? (
        <div className="hidden md:block">
          {payTable(filteredPayables)}
          <div className="mt-2 flex flex-wrap items-center justify-between gap-2 rounded-lg border bg-muted/40 px-4 py-2 text-sm">
            <span className="font-medium">{t.common.total}: {filteredPayables.length} itens</span>
            <span className="flex flex-wrap gap-4 tabular-nums">
              <span>Valor: <b>{formatCurrency(payTotalAmount)}</b></span>
              <span className="text-success">Pago: <b>{formatCurrency(payTotalPaid)}</b></span>
              <span>Saldo: <b>{formatCurrency(payTotalBalance)}</b></span>
            </span>
          </div>
        </div>
      ) : (
        <div className="hidden space-y-3 md:block">
          {Object.entries(grouped).map(([groupName, items]) => {
            const groupBalance = items.filter((p) => p.status !== 'paid' && p.status !== 'cancelled').reduce((s, p) => s + Number(p.balance_amount ?? 0), 0);
            return (
              <Collapsible key={groupName} defaultOpen>
                <CollapsibleTrigger className="flex w-full items-center justify-between rounded-lg border bg-card p-3 hover:bg-muted/50">
                  <span className="font-semibold">{groupName} <span className="font-normal text-muted-foreground">({items.length})</span></span>
                  <span className="font-semibold tabular-nums">{t.financial.subtotal}: {formatCurrency(groupBalance)}</span>
                </CollapsibleTrigger>
                <CollapsibleContent className="pt-2">{payTable(items)}</CollapsibleContent>
              </Collapsible>
            );
          })}
        </div>
      )}

      {/* Celular: lista compacta de contas */}
      {!loadingPay && !payError && (
        <div className="space-y-2.5 md:hidden">
          {filteredPayables.length === 0 && <p className="py-6 text-center text-sm text-muted-foreground">{t.common.noResults}</p>}
          {filteredPayables.map((p) => {
            const s = statusView(p);
            const alert = dueAlert(p);
            return (
              <div key={p.id} className={`rounded-lg border border-l-[3px] bg-card p-3.5 shadow-sm ${s.tone === 'critical' ? 'border-l-destructive' : s.tone === 'success' ? 'border-l-success' : 'border-l-transparent'}`}>
                <div className="flex items-center justify-between gap-2">
                  <span className="min-w-0 truncate text-sm font-bold">{p.suppliers?.name || p.name || p.description}</span>
                  <StatusChip tone={s.tone}>{s.label}</StatusChip>
                </div>
                <p className="truncate text-sm text-muted-foreground">{p.description}</p>
                <p className="text-sm text-muted-foreground">
                  {formatDate(p.due_date)}{alert ? ` · ${alert.label}` : ''} · <b className="text-foreground">{formatCurrency(Number(p.balance_amount ?? 0))}</b>
                </p>
                {deOndeSaiu(p) && <p className="text-xs text-muted-foreground">Saiu de: {deOndeSaiu(p)}</p>}
                {p.status !== 'cancelled' && (
                  <div className="mt-3 flex items-center gap-2">
                    {p.status !== 'paid' && (
                      <Button className="min-h-11 flex-1" onClick={() => setPaymentTarget(p)}>{t.financial.registerPayment}</Button>
                    )}
                    <AcoesDaLinha rotulo={p.description} menu={acoesDaConta(p).menu} className={p.status === 'paid' ? 'ml-auto' : undefined} />
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}

      {paymentTarget && (
        <PaymentDialog
          open={!!paymentTarget}
          onOpenChange={() => setPaymentTarget(null)}
          payable={paymentTarget as never}
        />
      )}
      {/* Corrigir serve para qualquer conta, inclusive paga, e passa pelo caminho único
          (trilha, mês fechado, valor do banco travado). Criar é pelo "+ Lançar". */}
      {editingPayable && (
        <CorrigirLancamentoDialog
          tipo="payable"
          lancamento={editingPayable as never}
          onFechar={() => setEditingPayable(null)}
        />
      )}
      <DesfazerOuCancelarDialog
        tipo="payable"
        acao={acaoNaConta?.acao ?? null}
        lancamento={acaoNaConta?.conta ?? null}
        onFechar={() => setAcaoNaConta(null)}
      />
    </div>
  );
}
