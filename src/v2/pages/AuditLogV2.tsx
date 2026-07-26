import { useMemo, useState } from 'react';
import { X } from 'lucide-react';
import { useI18n } from '@/i18n';
import { useAuditLog } from '@/hooks/use-audit-log';
import { useAppUsers } from '@/hooks/use-app-users';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Skeleton } from '@/components/ui/skeleton';
import { PageShell } from '@/v2/components/PageShell';
import { StatusChip, type StatusTone } from '@/v2/components/StatusChip';
import { DataTable, type DataColumn } from '@/v2/components/DataTable';
import { V2Shell } from '@/v2/components/V2Shell';
import '@/v2/tokens.css';

/* Onda B · Auditoria v2 — paridade com AuditLogPage v1: filtros, resumo
   humano da mudança e diff antes/depois na linha expansível (renderExpanded
   da DataTable). Cores de ação e do diff agora por token. */

const TABLE_OPTIONS = ['service_orders', 'receivables', 'payables', 'payments', 'bank_transactions', 'service_order_parts'] as const;
const ACTION_OPTIONS = ['update', 'cancel', 'reopen', 'reversal', 'cascade_update'] as const;

const ACTION_TONE: Record<string, StatusTone> = {
  update: 'info',
  cancel: 'critical',
  reopen: 'warning',
  reversal: 'info',
  cascade_update: 'neutral',
};

const FIELD_MAP: Record<string, string> = {
  status: 'Status', grand_total: 'Valor Total', service_order_number: 'Nº OS',
  discount_amount: 'Desconto', scheduled_start_at: 'Início', scheduled_end_at: 'Fim',
  problem_description: 'Problema', quantity: 'Quantidade', unit_price_snapshot: 'Preço',
  amount: 'Valor (R$)', due_date: 'Vencimento', description: 'Descrição', contact_name: 'Contato',
  line_total: 'Total da Linha', labor_cost_total: 'Total de Serviços', parts_cost_total: 'Total de Peças',
  product_id: 'ID do Produto', service_id: 'ID do Serviço',
};

const STATUS_MAP: Record<string, string> = {
  draft: 'Rascunho', approved: 'Aprovada', scheduled: 'Agendada', in_progress: 'Em Andamento',
  completed: 'Concluída', cancelled: 'Cancelada', invoiced: 'Faturada',
  pending: 'Pendente', overdue: 'Atrasada', paid: 'Pago',
};

type AuditRow = {
  id: string;
  changed_at: string;
  table_name: string;
  action: string;
  changed_by?: string | null;
  reason?: string | null;
  record_id?: string | null;
  triggered_by_table?: string | null;
  previous_value?: Record<string, unknown> | null;
  new_value?: Record<string, unknown> | null;
};

const IGNORE_KEYS = new Set(['updated_at', 'created_at', 'id', 'client_id', 'vessel_id']);

function formatValue(k: string, val: unknown): string {
  if (val === null || val === undefined) return '—';
  if (k === 'status' && typeof val === 'string' && STATUS_MAP[val]) return STATUS_MAP[val];
  if (typeof val === 'number' && (k.includes('amount') || k.includes('cost') || k.includes('total') || k.includes('price'))) {
    return new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(val);
  }
  if (typeof val === 'string' && /^\d{4}-\d{2}-\d{2}T/.test(val)) {
    return new Date(val).toLocaleString('pt-BR');
  }
  return JSON.stringify(val);
}

function changedKeysOf(prev: AuditRow['previous_value'], next: AuditRow['new_value']): string[] {
  const all = [...new Set([...Object.keys(prev || {}), ...Object.keys(next || {})])];
  return all.filter((k) => !IGNORE_KEYS.has(k) && JSON.stringify(prev?.[k]) !== JSON.stringify(next?.[k]));
}

function humanSummary(prev: AuditRow['previous_value'], next: AuditRow['new_value']): string {
  const changed = changedKeysOf(prev, next);
  if (!changed.length) return '';
  return changed.slice(0, 3)
    .map((k) => `${FIELD_MAP[k] || k}: ${formatValue(k, prev?.[k])} → ${formatValue(k, next?.[k])}`)
    .join(' · ') + (changed.length > 3 ? ` (+${changed.length - 3})` : '');
}

export default function AuditLogV2() {
  const { t } = useI18n();
  const auditT = t.auditLog as unknown as Record<string, string> & { tables: Record<string, string>; actions: Record<string, string> };
  const tablesMap = auditT.tables;
  const actionsMap = auditT.actions;

  const [tableFilter, setTableFilter] = useState('');
  const [actionFilter, setActionFilter] = useState('');
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [recordSearch, setRecordSearch] = useState('');

  const { data: usersData } = useAppUsers();
  const userMap = useMemo(() => {
    const m: Record<string, string> = {};
    ((usersData || []) as { id: string; full_name?: string; email?: string }[]).forEach((u) => {
      m[u.id] = u.full_name || u.email || u.id;
    });
    return m;
  }, [usersData]);

  const { data: logs, isLoading } = useAuditLog({
    table_name: tableFilter || undefined,
    action: actionFilter || undefined,
    dateFrom: dateFrom || undefined,
    dateTo: dateTo ? `${dateTo}T23:59:59` : undefined,
  });

  const visibleLogs = useMemo(() => {
    const list = (logs || []) as unknown as AuditRow[];
    if (!recordSearch.trim()) return list;
    const q = recordSearch.toLowerCase();
    return list.filter((l) =>
      l.record_id?.toLowerCase().includes(q) ||
      JSON.stringify(l.new_value)?.toLowerCase().includes(q) ||
      JSON.stringify(l.previous_value)?.toLowerCase().includes(q),
    );
  }, [logs, recordSearch]);

  const hasFilters = tableFilter || actionFilter || dateFrom || dateTo || recordSearch;
  const clearFilters = () => { setTableFilter(''); setActionFilter(''); setDateFrom(''); setDateTo(''); setRecordSearch(''); };

  const renderDiff = (log: AuditRow) => {
    const changed = changedKeysOf(log.previous_value, log.new_value);
    return (
      <div className="space-y-2">
        <div className="text-xs text-muted-foreground">
          ID: <code className="rounded bg-muted px-1">{log.record_id}</code>
          {log.triggered_by_table && <span className="ml-3">Trigger: {tablesMap[log.triggered_by_table] || log.triggered_by_table}</span>}
        </div>
        {changed.length === 0 ? (
          <span className="text-xs text-muted-foreground">{auditT.noChanges}</span>
        ) : (
          <div className="grid grid-cols-1 gap-4 text-xs sm:grid-cols-2">
            <div className="space-y-1">
              <p className="font-semibold text-destructive">{auditT.before}</p>
              {changed.map((k) => (
                <div key={k} className="flex items-center justify-between gap-2 rounded bg-destructive/5 px-2 py-1">
                  <span className="font-medium text-muted-foreground">{FIELD_MAP[k] || k}:</span>
                  <span className="truncate font-mono">{formatValue(k, log.previous_value?.[k])}</span>
                </div>
              ))}
            </div>
            <div className="space-y-1">
              <p className="font-semibold text-success">{auditT.after}</p>
              {changed.map((k) => (
                <div key={k} className="flex items-center justify-between gap-2 rounded bg-success/10 px-2 py-1">
                  <span className="font-medium text-muted-foreground">{FIELD_MAP[k] || k}:</span>
                  <span className="truncate font-mono text-success">{formatValue(k, log.new_value?.[k])}</span>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    );
  };

  const columns: DataColumn<AuditRow>[] = [
    {
      key: 'changed_at', header: t.common.date, minWidth: 128, priority: 0,
      render: (l) => (
        <span className="text-muted-foreground tabular-nums">
          {new Date(l.changed_at).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' })}
        </span>
      ),
    },
    {
      key: 'summary', header: auditT.reason, minWidth: 260, priority: 1,
      render: (l) => (
        <span className="block truncate text-muted-foreground">
          {humanSummary(l.previous_value, l.new_value) || l.reason || '—'}
        </span>
      ),
    },
    {
      key: 'action', header: auditT.action, minWidth: 110, priority: 2, detailLabel: 'Ação',
      render: (l) => (
        <StatusChip tone={ACTION_TONE[l.action] ?? 'neutral'}>{actionsMap[l.action] || l.action}</StatusChip>
      ),
    },
    {
      key: 'table', header: auditT.table, minWidth: 130, priority: 3, detailLabel: 'Tabela',
      render: (l) => <StatusChip tone="neutral">{tablesMap[l.table_name] || l.table_name}</StatusChip>,
    },
    {
      key: 'user', header: auditT.changedBy, minWidth: 140, priority: 4, detailLabel: 'Por',
      render: (l) => <span className="truncate">{userMap[l.changed_by ?? ''] || l.changed_by?.slice(0, 8) || '—'}</span>,
    },
  ];

  return (
    <V2Shell>
      <PageShell
        breadcrumb={[{ label: 'Sistema' }, { label: auditT.title }]}
        title={auditT.title}
        count={visibleLogs.length}
        description={auditT.description}
      >
        <div className="flex flex-wrap items-end gap-3">
          <div className="w-full sm:w-44">
            <Select value={tableFilter || undefined} onValueChange={setTableFilter}>
              <SelectTrigger className="h-9"><SelectValue placeholder={auditT.table} /></SelectTrigger>
              <SelectContent>
                {TABLE_OPTIONS.map((tb) => <SelectItem key={tb} value={tb}>{tablesMap[tb] || tb}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div className="w-full sm:w-44">
            <Select value={actionFilter || undefined} onValueChange={setActionFilter}>
              <SelectTrigger className="h-9"><SelectValue placeholder={auditT.action} /></SelectTrigger>
              <SelectContent>
                {ACTION_OPTIONS.map((a) => <SelectItem key={a} value={a}>{actionsMap[a] || a}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <Input type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} className="h-9 w-full sm:w-40" />
          <Input type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} className="h-9 w-full sm:w-40" />
          <Input value={recordSearch} onChange={(e) => setRecordSearch(e.target.value)} className="h-9 w-full sm:w-48" placeholder="Buscar por nº OS ou ID…" />
          {hasFilters && (
            <Button variant="ghost" size="sm" onClick={clearFilters} className="gap-1">
              <X className="h-4 w-4" /> {t.financial.clearFilters}
            </Button>
          )}
        </div>

        {isLoading ? (
          <div className="space-y-2">{Array.from({ length: 5 }).map((_, i) => <Skeleton key={i} className="h-12 w-full" />)}</div>
        ) : (
          <>
            <div className="hidden md:block">
              <DataTable<AuditRow>
                rows={visibleLogs}
                rowKey={(l) => l.id}
                columns={columns}
                density="compact"
                emptyMessage={auditT.noChanges}
                renderExpanded={renderDiff}
              />
            </div>
            <div className="space-y-2.5 md:hidden">
              {visibleLogs.slice(0, 50).map((l) => (
                <details key={l.id} className="rounded-lg border bg-card p-3.5 shadow-sm">
                  <summary className="cursor-pointer list-none">
                    <span className="flex items-center justify-between gap-2">
                      <span className="text-xs text-muted-foreground tabular-nums">
                        {new Date(l.changed_at).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' })}
                      </span>
                      <StatusChip tone={ACTION_TONE[l.action] ?? 'neutral'}>{actionsMap[l.action] || l.action}</StatusChip>
                    </span>
                    <span className="mt-1 block text-sm">{humanSummary(l.previous_value, l.new_value) || l.reason || '—'}</span>
                  </summary>
                  <div className="mt-3 border-t pt-3">{renderDiff(l)}</div>
                </details>
              ))}
              {visibleLogs.length === 0 && (
                <p className="rounded-lg border bg-card p-8 text-center text-sm text-muted-foreground">{auditT.noChanges}</p>
              )}
            </div>
          </>
        )}
      </PageShell>
    </V2Shell>
  );
}
