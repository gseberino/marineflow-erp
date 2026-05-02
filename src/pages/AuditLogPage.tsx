import { useState } from 'react';
import { useI18n } from '@/i18n';
import { useAuditLog } from '@/hooks/use-audit-log';
import { PageHeader } from '@/components/PageHeader';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';
import { ChevronDown, X } from 'lucide-react';

const TABLE_OPTIONS = ['service_orders', 'receivables', 'payables', 'payments', 'bank_transactions', 'service_order_parts'] as const;
const ACTION_OPTIONS = ['update', 'cancel', 'reopen', 'reversal', 'cascade_update'] as const;

const ACTION_COLORS: Record<string, string> = {
  update: 'bg-blue-100 text-blue-700',
  cancel: 'bg-destructive/10 text-destructive',
  reopen: 'bg-amber-100 text-amber-700',
  reversal: 'bg-purple-100 text-purple-700',
  cascade_update: 'bg-muted text-muted-foreground',
};

export default function AuditLogPage() {
  const { t } = useI18n();
  const [tableFilter, setTableFilter] = useState('');
  const [actionFilter, setActionFilter] = useState('');
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [expandedRow, setExpandedRow] = useState<string | null>(null);

  const auditT = t.auditLog as any;
  const tablesMap = auditT.tables as Record<string, string>;
  const actionsMap = auditT.actions as Record<string, string>;

  const { data: logs, isLoading } = useAuditLog({
    table_name: tableFilter || undefined,
    action: actionFilter || undefined,
    dateFrom: dateFrom || undefined,
    dateTo: dateTo ? `${dateTo}T23:59:59` : undefined,
  });

  const clearFilters = () => {
    setTableFilter('');
    setActionFilter('');
    setDateFrom('');
    setDateTo('');
  };

  const hasFilters = tableFilter || actionFilter || dateFrom || dateTo;

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
    pending: 'Pendente', overdue: 'Atrasada', paid: 'Pago'
  };

  const formatValue = (k: string, val: any) => {
    if (val === null || val === undefined) return '—';
    if (k === 'status' && STATUS_MAP[val]) return STATUS_MAP[val];
    if (typeof val === 'number' && (k.includes('amount') || k.includes('cost') || k.includes('total') || k.includes('price'))) {
      return new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(val);
    }
    if (typeof val === 'string' && val.match(/^\d{4}-\d{2}-\d{2}T/)) {
      return new Date(val).toLocaleString('pt-BR');
    }
    return JSON.stringify(val);
  };

  const renderDiff = (prev: any, next: any) => {
    if (!prev && !next) return <span className="text-muted-foreground text-xs">—</span>;
    const allKeys = new Set([
      ...Object.keys(prev || {}),
      ...Object.keys(next || {}),
    ]);
    const changedKeys = Array.from(allKeys).filter(k => {
      // ignore technical keys
      if (k === 'updated_at' || k === 'created_at' || k === 'id' || k === 'client_id' || k === 'vessel_id') return false;
      return JSON.stringify(prev?.[k]) !== JSON.stringify(next?.[k]);
    });
    if (changedKeys.length === 0) return <span className="text-muted-foreground text-xs">{auditT.noChanges}</span>;

    return (
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 text-xs">
        <div className="space-y-1">
          <p className="font-semibold text-destructive">{auditT.before}</p>
          {changedKeys.map(k => (
            <div key={k} className="bg-destructive/5 rounded px-2 py-1 flex justify-between items-center">
              <span className="font-medium text-muted-foreground">{FIELD_MAP[k] || k}:</span>
              <span className="font-mono">{formatValue(k, prev?.[k])}</span>
            </div>
          ))}
        </div>
        <div className="space-y-1">
          <p className="font-semibold text-emerald-600">{auditT.after}</p>
          {changedKeys.map(k => (
            <div key={k} className="bg-emerald-50 rounded px-2 py-1 flex justify-between items-center">
              <span className="font-medium text-muted-foreground">{FIELD_MAP[k] || k}:</span>
              <span className="font-mono text-emerald-800">{formatValue(k, next?.[k])}</span>
            </div>
          ))}
        </div>
      </div>
    );
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader title={auditT.title} description={auditT.description} />

      {/* Filters */}
      <div className="flex flex-wrap gap-3 items-end">
        <div className="w-48">
          <Select value={tableFilter} onValueChange={setTableFilter}>
            <SelectTrigger><SelectValue placeholder={auditT.table} /></SelectTrigger>
            <SelectContent>
              {TABLE_OPTIONS.map(t => (
                <SelectItem key={t} value={t}>{tablesMap[t] || t}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div className="w-48">
          <Select value={actionFilter} onValueChange={setActionFilter}>
            <SelectTrigger><SelectValue placeholder={auditT.action} /></SelectTrigger>
            <SelectContent>
              {ACTION_OPTIONS.map(a => (
                <SelectItem key={a} value={a}>{actionsMap[a] || a}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <Input type="date" value={dateFrom} onChange={e => setDateFrom(e.target.value)} className="w-40" placeholder={t.financial.dateFrom} />
        <Input type="date" value={dateTo} onChange={e => setDateTo(e.target.value)} className="w-40" placeholder={t.financial.dateTo} />
        {hasFilters && (
          <Button variant="ghost" size="sm" onClick={clearFilters}>
            <X className="h-4 w-4 mr-1" /> {t.financial.clearFilters}
          </Button>
        )}
      </div>

      {/* Table */}
      {isLoading ? (
        <div className="space-y-2">{Array.from({ length: 5 }).map((_, i) => <Skeleton key={i} className="h-12 w-full" />)}</div>
      ) : !logs || logs.length === 0 ? (
        <div className="text-center py-12 text-muted-foreground">{auditT.noChanges}</div>
      ) : (
        <div className="rounded-xl border bg-card shadow-sm overflow-hidden">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="w-40">{t.common.date}</TableHead>
                <TableHead>{auditT.table}</TableHead>
                <TableHead>{auditT.action}</TableHead>
                <TableHead>{auditT.changedBy}</TableHead>
                <TableHead>{auditT.reason}</TableHead>
                <TableHead className="w-20">{auditT.details}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {logs.map((log: any) => (
                <Collapsible key={log.id} open={expandedRow === log.id} onOpenChange={(open) => setExpandedRow(open ? log.id : null)} asChild>
                  <>
                    <CollapsibleTrigger asChild>
                      <TableRow className="cursor-pointer hover:bg-muted/50">
                        <TableCell className="text-sm">
                          {new Date(log.changed_at).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' })}
                        </TableCell>
                        <TableCell>
                          <Badge variant="outline" className="text-xs">
                            {tablesMap[log.table_name] || log.table_name}
                          </Badge>
                        </TableCell>
                        <TableCell>
                          <span className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold ${ACTION_COLORS[log.action] || ''}`}>
                            {actionsMap[log.action] || log.action}
                          </span>
                        </TableCell>
                        <TableCell className="text-sm">{log.changed_by}</TableCell>
                        <TableCell className="text-sm text-muted-foreground max-w-[200px] truncate">{log.reason || '—'}</TableCell>
                        <TableCell>
                          <ChevronDown className={`h-4 w-4 transition-transform ${expandedRow === log.id ? 'rotate-180' : ''}`} />
                        </TableCell>
                      </TableRow>
                    </CollapsibleTrigger>
                    <CollapsibleContent asChild>
                      <TableRow>
                        <TableCell colSpan={6} className="bg-muted/30 p-4">
                          <div className="text-xs text-muted-foreground mb-2">
                            ID: <code className="bg-muted px-1 rounded">{log.record_id}</code>
                            {log.triggered_by_table && (
                              <span className="ml-3">
                                Trigger: {tablesMap[log.triggered_by_table] || log.triggered_by_table}
                              </span>
                            )}
                          </div>
                          {renderDiff(log.previous_value, log.new_value)}
                        </TableCell>
                      </TableRow>
                    </CollapsibleContent>
                  </>
                </Collapsible>
              ))}
            </TableBody>
          </Table>
        </div>
      )}
    </div>
  );
}
