import { useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { ArrowRight, CheckCircle2, Download } from 'lucide-react';
import { toast } from 'sonner';
import { useI18n } from '@/i18n';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { PageShell } from '@/v2/components/PageShell';
import { KPIStat } from '@/v2/components/KPIStat';
import { StatusChip, type StatusTone } from '@/v2/components/StatusChip';
import { EntityCard } from '@/v2/components/EntityCard';
import { DataTable, type DataColumn, type SortState } from '@/v2/components/DataTable';
import { V2Shell } from '@/v2/components/V2Shell';
import '@/v2/tokens.css';

/* Onda B · Comissões v2 — paridade com CommissionsPage v1: aprovar gera a
   conta a pagar (mesma mutação), KPIs, busca/filtro, CSV. */

type CommissionRow = {
  id: string;
  amount: number;
  percentage?: number | null;
  status: string;
  created_at: string;
  app_users?: { full_name?: string } | null;
  service_orders?: { service_order_number?: string; grand_total?: number | null; status?: string } | null;
};

const STATUS_VIEW: Record<string, { label: string; tone: StatusTone }> = {
  pending: { label: 'Pendente', tone: 'warning' },
  approved: { label: 'Aprovado', tone: 'info' },
  paid: { label: 'Pago', tone: 'success' },
};

export default function CommissionsV2() {
  const { formatCurrency, formatDate } = useI18n();
  const qc = useQueryClient();
  const [searchTerm, setSearchTerm] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');
  const [sort, setSort] = useState<SortState>({ key: 'created_at', dir: 'desc' });

  const { data: commissions, isLoading } = useQuery({
    queryKey: ['commissions'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('commissions')
        .select('*, app_users(full_name), service_orders(service_order_number, grand_total, status)')
        .order('created_at', { ascending: false });
      if (error) throw error;
      return data as unknown as CommissionRow[];
    },
  });

  const approveMutation = useMutation({
    mutationFn: async (commission: CommissionRow) => {
      const { data: payable, error: payErr } = await supabase.from('payables').insert({
        description: `Comissão OS #${commission.service_orders?.service_order_number} - ${commission.app_users?.full_name}`,
        amount: commission.amount,
        balance_amount: commission.amount,
        issue_date: new Date().toISOString().split('T')[0],
        due_date: new Date().toISOString().split('T')[0],
        expense_category: 'Comissões',
        status: 'pending',
        origin: 'commission',
      }).select().single();
      if (payErr) throw payErr;
      const { error: updErr } = await supabase
        .from('commissions')
        .update({ status: 'approved', payable_id: payable.id })
        .eq('id', commission.id);
      if (updErr) throw updErr;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['commissions'] });
      qc.invalidateQueries({ queryKey: ['payables'] });
      toast.success('Comissão aprovada e enviada para o financeiro!');
    },
    onError: (e) => toast.error(e instanceof Error ? e.message : 'Erro ao aprovar comissão'),
  });

  const filtered = useMemo(() => {
    let list = commissions || [];
    if (statusFilter !== 'all') list = list.filter((c) => c.status === statusFilter);
    if (searchTerm) {
      list = list.filter((c) =>
        c.app_users?.full_name?.toLowerCase().includes(searchTerm.toLowerCase()) ||
        c.service_orders?.service_order_number?.toLowerCase().includes(searchTerm.toLowerCase()),
      );
    }
    return [...list].sort((a, b) => {
      const val = (c: CommissionRow) => {
        if (sort.key === 'amount') return Number(c.amount);
        if (sort.key === 'name') return c.app_users?.full_name || '';
        if (sort.key === 'os_total') return Number(c.service_orders?.grand_total || 0);
        return c.created_at;
      };
      const av = val(a);
      const bv = val(b);
      if (av < bv) return sort.dir === 'asc' ? -1 : 1;
      if (av > bv) return sort.dir === 'asc' ? 1 : -1;
      return 0;
    });
  }, [commissions, searchTerm, statusFilter, sort]);

  const stats = {
    pending: commissions?.filter((c) => c.status === 'pending').reduce((s, c) => s + Number(c.amount), 0) || 0,
    approved: commissions?.filter((c) => c.status === 'approved').reduce((s, c) => s + Number(c.amount), 0) || 0,
    totalCount: commissions?.length || 0,
  };

  const handleSort = (key: string) => {
    setSort((prev) => (prev.key === key ? { key, dir: prev.dir === 'asc' ? 'desc' : 'asc' } : { key, dir: 'desc' }));
  };

  const exportCsv = () => {
    const rows = filtered.map((c) => ({
      'Técnico/Vendedor': c.app_users?.full_name || '—',
      OS: c.service_orders?.service_order_number || '—',
      'Valor OS': Number(c.service_orders?.grand_total || 0).toFixed(2),
      'Comissão %': c.percentage ?? '',
      'Valor Comissão': Number(c.amount || 0).toFixed(2),
      Status: c.status,
      Data: c.created_at ? new Date(c.created_at).toLocaleDateString('pt-BR') : '',
    }));
    if (!rows.length) return;
    const csv = [Object.keys(rows[0]).join(','), ...rows.map((r) => Object.values(r).map((v) => `"${String(v ?? '').replace(/"/g, '""')}"`).join(','))].join('\n');
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8;' }));
    a.download = 'comissoes.csv';
    a.click();
  };

  const approveAction = (c: CommissionRow) =>
    c.status === 'pending' ? (
      <Button size="sm" className="gap-1" disabled={approveMutation.isPending} onClick={() => approveMutation.mutate(c)}>
        Aprovar <ArrowRight className="h-3.5 w-3.5" />
      </Button>
    ) : c.status === 'approved' ? (
      <span className="inline-flex items-center gap-1 text-xs font-medium text-info">
        <CheckCircle2 className="h-3.5 w-3.5" /> No Contas a Pagar
      </span>
    ) : null;

  const columns: DataColumn<CommissionRow>[] = [
    {
      key: 'name', header: 'Técnico / Vendedor', minWidth: 180, priority: 0, sortable: true,
      render: (c) => <span className="block truncate font-semibold">{c.app_users?.full_name || '—'}</span>,
    },
    {
      key: 'created_at', header: 'OS Ref.', minWidth: 130, priority: 1, sortable: true, detailLabel: 'OS',
      render: (c) => (
        <span className="block leading-tight">
          <span className="block font-semibold text-accent">{c.service_orders?.service_order_number || '—'}</span>
          <span className="block text-xs text-muted-foreground">{formatDate(c.created_at)}</span>
        </span>
      ),
    },
    {
      key: 'amount', header: 'Comissão', minWidth: 132, priority: 1, align: 'right', sortable: true, detailLabel: 'Comissão',
      render: (c) => (
        <span className="block leading-tight">
          <span className="block font-bold text-success">{formatCurrency(c.amount)}</span>
          {c.percentage != null && <span className="block text-xs font-normal text-muted-foreground">{c.percentage}% do lucro</span>}
        </span>
      ),
    },
    {
      key: 'status', header: 'Status', minWidth: 104, priority: 2, detailLabel: 'Status',
      render: (c) => {
        const s = STATUS_VIEW[c.status] ?? { label: c.status, tone: 'neutral' as StatusTone };
        return <StatusChip dot tone={s.tone}>{s.label}</StatusChip>;
      },
    },
    {
      key: 'os_total', header: 'Valor OS', minWidth: 116, priority: 3, align: 'right', sortable: true, detailLabel: 'Valor OS',
      render: (c) => <span className="text-muted-foreground">{formatCurrency(c.service_orders?.grand_total || 0)}</span>,
    },
  ];

  return (
    <V2Shell>
      <PageShell
        breadcrumb={[{ label: 'Financeiro', to: '/v2/financial' }, { label: 'Comissões' }]}
        title="Gestão de Comissões"
        count={stats.totalCount}
        description="Controle e aprove os pagamentos de técnicos e vendedores com base no lucro real das OS."
        actions={
          <Button variant="outline" size="sm" className="gap-1.5" onClick={exportCsv}>
            <Download className="h-4 w-4" /> Exportar CSV
          </Button>
        }
      >
        <div className="grid grid-cols-1 gap-3 md:grid-cols-3">
          <KPIStat label="Aguardando aprovação" value={formatCurrency(stats.pending)} tone={stats.pending > 0 ? 'warning' : 'success'} />
          <KPIStat label="Aprovado (no financeiro)" value={formatCurrency(stats.approved)} tone="info" />
          <KPIStat label="Total de lançamentos" value={String(stats.totalCount)} />
        </div>

        <div className="flex flex-col gap-3 sm:flex-row">
          <Input
            placeholder="Buscar técnico ou OS…"
            className="h-9 flex-1"
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
          />
          <Select value={statusFilter} onValueChange={setStatusFilter}>
            <SelectTrigger className="h-9 w-full sm:w-44"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="all">Todos os status</SelectItem>
              <SelectItem value="pending">Pendente</SelectItem>
              <SelectItem value="approved">Aprovado</SelectItem>
              <SelectItem value="paid">Pago</SelectItem>
            </SelectContent>
          </Select>
        </div>

        <div className="hidden md:block">
          <DataTable<CommissionRow>
            rows={filtered}
            rowKey={(c) => c.id}
            columns={columns}
            sort={sort}
            onSort={handleSort}
            isLoading={isLoading}
            emptyMessage="Nenhuma comissão encontrada."
            rowActions={(c) => approveAction(c)}
          />
        </div>
        <div className="space-y-2.5 md:hidden">
          {filtered.map((c) => {
            const s = STATUS_VIEW[c.status] ?? { label: c.status, tone: 'neutral' as StatusTone };
            return (
              <EntityCard
                key={c.id}
                id={c.service_orders?.service_order_number || '—'}
                severity={s.tone}
                badge={<StatusChip tone={s.tone}>{s.label}</StatusChip>}
                title={c.app_users?.full_name || '—'}
                lines={[
                  `${formatCurrency(c.amount)}${c.percentage != null ? ` · ${c.percentage}% do lucro` : ''}`,
                  `OS ${formatCurrency(c.service_orders?.grand_total || 0)} · ${formatDate(c.created_at)}`,
                ]}
                actions={c.status === 'pending' ? (
                  <Button className="flex-1 gap-1" disabled={approveMutation.isPending} onClick={() => approveMutation.mutate(c)}>
                    Aprovar <ArrowRight className="h-4 w-4" />
                  </Button>
                ) : undefined}
              />
            );
          })}
        </div>
      </PageShell>
    </V2Shell>
  );
}
