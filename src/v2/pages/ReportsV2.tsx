import { useState, type ReactNode } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import {
  AlertTriangle, BarChart3, DollarSign, Download, Loader2, Package, Percent,
  RefreshCw, TrendingUp, Users,
} from 'lucide-react';
import {
  Bar, BarChart, CartesianGrid, Cell, Legend, Pie, PieChart,
  ResponsiveContainer, Tooltip, XAxis, YAxis,
} from 'recharts';
import { useI18n } from '@/i18n';
import {
  useRevenueReport, useOsPerformanceReport, usePartsUsageReport,
  useTechnicianProductivityReport, useProfitabilityReport,
} from '@/hooks/use-reports';
import { AIConsultantDashboard } from '@/components/AIConsultantDashboard';
import { Button } from '@/components/ui/button';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { PageShell } from '@/v2/components/PageShell';
import { KPIStat } from '@/v2/components/KPIStat';
import { StatusChip } from '@/v2/components/StatusChip';
import { DataTable, type DataColumn } from '@/v2/components/DataTable';
import { V2Shell } from '@/v2/components/V2Shell';
import '@/v2/tokens.css';

/* Onda B · Relatórios v2 — paridade com ReportsPage v1 (5 abas + consultor IA),
   gráficos nas cores de token (--chart-1..5), tabelas na DataTable (zero
   scroll lateral também nos relatórios), aba na URL (?tab=). */

const CHART_TOKENS = [
  'hsl(var(--chart-1))', 'hsl(var(--chart-2))', 'hsl(var(--chart-3))',
  'hsl(var(--chart-4))', 'hsl(var(--chart-5))',
];

function exportCSV(filename: string, rows: Record<string, unknown>[]) {
  if (!rows.length) return;
  const headers = Object.keys(rows[0]);
  const escape = (v: unknown) => {
    const s = v == null ? '' : String(v);
    return s.includes(',') || s.includes('"') || s.includes('\n') ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const csv = [headers.join(','), ...rows.map((r) => headers.map((h) => escape(r[h])).join(','))].join('\n');
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8;' }));
  a.download = filename;
  a.click();
}

function ChartCard({ title, action, children }: { title: string; action?: ReactNode; children: ReactNode }) {
  return (
    <div className="overflow-hidden rounded-lg border bg-card p-4">
      <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
        <h3 className="text-sm font-bold">{title}</h3>
        {action}
      </div>
      {children}
    </div>
  );
}

const LoadingBlock = () => (
  <div className="flex items-center justify-center py-12 text-muted-foreground">
    <Loader2 className="mr-2 h-5 w-5 animate-spin" /> Carregando…
  </div>
);

const ErrorBlock = ({ onRetry }: { onRetry?: () => void }) => (
  <div className="flex flex-col items-center justify-center gap-3 py-12 text-center">
    <AlertTriangle className="h-8 w-8 text-destructive" />
    <p className="text-sm text-muted-foreground">Erro ao carregar relatório.</p>
    {onRetry && (
      <Button variant="outline" size="sm" onClick={onRetry} className="gap-1.5">
        <RefreshCw className="h-4 w-4" /> Tentar novamente
      </Button>
    )}
  </div>
);

function PeriodSelect({ value, onChange, max = 365 }: { value: string; onChange: (v: string) => void; max?: number }) {
  return (
    <div className="flex justify-end">
      <Select value={value} onValueChange={onChange}>
        <SelectTrigger className="h-9 w-44"><SelectValue /></SelectTrigger>
        <SelectContent>
          <SelectItem value="30">Últimos 30 dias</SelectItem>
          <SelectItem value="90">Últimos 90 dias</SelectItem>
          <SelectItem value="180">Últimos 180 dias</SelectItem>
          {max >= 365 && <SelectItem value="365">Últimos 365 dias</SelectItem>}
        </SelectContent>
      </Select>
    </div>
  );
}

const axisTick = { fontSize: 11, fill: 'hsl(var(--muted-foreground))' };

/* ── Receita ── */
function RevenueTab() {
  const { formatCurrency } = useI18n();
  const [period, setPeriod] = useState('30');
  const { data, isLoading, error, refetch } = useRevenueReport(Number(period));

  type ClientRow = { name: string; revenue: number };
  const cols: DataColumn<ClientRow & { i: number }>[] = [
    { key: 'i', header: '#', minWidth: 44, priority: 2, render: (r) => <span className="text-muted-foreground tabular-nums">{r.i + 1}</span> },
    { key: 'name', header: 'Cliente', minWidth: 200, priority: 0, render: (r) => <span className="truncate font-semibold">{r.name}</span> },
    { key: 'revenue', header: 'Receita', minWidth: 130, priority: 1, align: 'right', render: (r) => <span className="font-semibold">{formatCurrency(r.revenue)}</span> },
  ];

  return (
    <div className="space-y-4">
      <PeriodSelect value={period} onChange={setPeriod} />
      {isLoading ? <LoadingBlock /> : error ? <ErrorBlock onRetry={() => refetch()} /> : !data ? <LoadingBlock /> : (
        <>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <KPIStat label="Total recebido" value={formatCurrency(data.totalReceived)} tone="success" />
            <KPIStat label="Ticket médio (OS concluída)" value={formatCurrency(data.avgTicket)} />
            <KPIStat label="OS faturadas" value={String(data.invoicedCount)} />
            <KPIStat label="Margem estimada" value={formatCurrency(data.margin)} tone="success" />
          </div>
          <ChartCard title="Receita por mês (últimos 6 meses)">
            <ResponsiveContainer width="100%" height={240}>
              <BarChart data={data.monthlyRevenue}>
                <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" vertical={false} />
                <XAxis dataKey="month" tick={axisTick} axisLine={false} tickLine={false} />
                <YAxis tick={axisTick} tickFormatter={(v: number) => `${(v / 1000).toFixed(0)}k`} width={40} axisLine={false} tickLine={false} />
                <Tooltip formatter={(v: number) => formatCurrency(v)} cursor={{ fill: 'hsl(var(--muted))' }} />
                <Bar dataKey="value" fill="hsl(var(--chart-1))" radius={[3, 3, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </ChartCard>
          <ChartCard title="Top 10 clientes por receita">
            <DataTable
              rows={data.topClients.map((c: ClientRow, i: number) => ({ ...c, i }))}
              rowKey={(r) => r.name + r.i}
              columns={cols}
              density="compact"
              emptyMessage="Sem dados no período"
            />
          </ChartCard>
        </>
      )}
    </div>
  );
}

/* ── Performance ── */
function PerformanceTab() {
  const navigate = useNavigate();
  const { data, isLoading, error, refetch } = useOsPerformanceReport();
  if (isLoading) return <LoadingBlock />;
  if (error) return <ErrorBlock onRetry={() => refetch()} />;
  if (!data) return <LoadingBlock />;

  type StaleRow = { id: string; number: string; client: string; status: string; days_since: number };
  const staleCols: DataColumn<StaleRow>[] = [
    { key: 'number', header: 'OS', minWidth: 110, priority: 0, render: (o) => <span className="font-semibold text-accent">{o.number}</span> },
    { key: 'client', header: 'Cliente', minWidth: 180, priority: 1, render: (o) => <span className="truncate">{o.client}</span> },
    { key: 'status', header: 'Status', minWidth: 120, priority: 2, render: (o) => <StatusChip tone="neutral">{o.status}</StatusChip> },
    { key: 'days', header: 'Dias parada', minWidth: 100, priority: 1, align: 'right', render: (o) => <span className="font-semibold text-warning tabular-nums">{o.days_since}d</span> },
  ];

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <KPIStat label="OS abertas" value={String(data.openCount)} hint={`${data.completedCount} concluídas`} />
        <KPIStat label="Tempo médio de conclusão" value={`${data.avgCompletionHours.toFixed(1)}h`} />
        <KPIStat label="Taxa de conversão" value={`${data.conversionRate.toFixed(0)}%`} hint="Orçamento → Aprovado" tone="success" />
        <KPIStat label="OS em atraso" value={String(data.overdueCount)} tone={data.overdueCount > 0 ? 'critical' : 'success'} />
      </div>
      <ChartCard title="Distribuição por status">
        <ResponsiveContainer width="100%" height={260}>
          <PieChart>
            <Pie
              data={data.statusDistribution}
              cx="50%" cy="50%" innerRadius={60} outerRadius={95} dataKey="value"
              stroke="hsl(var(--card))" strokeWidth={2}
            >
              {data.statusDistribution.map((_: unknown, i: number) => (
                <Cell key={i} fill={CHART_TOKENS[i % CHART_TOKENS.length]} />
              ))}
            </Pie>
            <Tooltip />
            <Legend wrapperStyle={{ fontSize: 12 }} />
          </PieChart>
        </ResponsiveContainer>
      </ChartCard>
      <ChartCard title="OS abertas há mais de 7 dias sem atualização">
        <DataTable
          rows={data.staleOrders as StaleRow[]}
          rowKey={(o) => o.id}
          columns={staleCols}
          density="compact"
          onRowClick={(o) => navigate(`/v2/service-orders/${o.id}`)}
          emptyMessage="Nenhuma OS parada 🎉"
        />
      </ChartCard>
    </div>
  );
}

/* ── Peças ── */
function PartsTab() {
  const { formatCurrency } = useI18n();
  const [period, setPeriod] = useState('30');
  const { data, isLoading, error, refetch } = usePartsUsageReport(Number(period));

  type PartRow = { name: string; qty: number; revenue: number; avg_price: number };
  const cols: DataColumn<PartRow & { i: number }>[] = [
    { key: 'name', header: 'Peça', minWidth: 220, priority: 0, render: (r) => <span className="truncate font-semibold">{r.name}</span> },
    { key: 'qty', header: 'Qtd. usada', minWidth: 100, priority: 1, align: 'right', render: (r) => <span className="tabular-nums">{r.qty}</span> },
    { key: 'revenue', header: 'Receita', minWidth: 120, priority: 1, align: 'right', render: (r) => <span className="font-semibold">{formatCurrency(r.revenue)}</span> },
    { key: 'avg', header: 'Preço médio', minWidth: 116, priority: 2, align: 'right', detailLabel: 'Preço médio', render: (r) => <span className="text-muted-foreground">{formatCurrency(r.avg_price)}</span> },
  ];

  return (
    <div className="space-y-4">
      <PeriodSelect value={period} onChange={setPeriod} max={180} />
      {isLoading ? <LoadingBlock /> : error ? <ErrorBlock onRetry={() => refetch()} /> : !data ? <LoadingBlock /> : (
        <>
          <ChartCard title="Top 10 peças por quantidade">
            <ResponsiveContainer width="100%" height={300}>
              <BarChart data={data.top10} layout="vertical" margin={{ left: 24 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" horizontal={false} />
                <XAxis type="number" tick={axisTick} axisLine={false} tickLine={false} />
                <YAxis type="category" dataKey="name" tick={axisTick} width={130} axisLine={false} tickLine={false} />
                <Tooltip cursor={{ fill: 'hsl(var(--muted))' }} />
                <Bar dataKey="qty" fill="hsl(var(--chart-3))" radius={[0, 3, 3, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </ChartCard>
          <ChartCard title="Top 20 peças (detalhado)">
            <DataTable
              rows={(data.rows as PartRow[]).map((r, i) => ({ ...r, i }))}
              rowKey={(r) => r.name + r.i}
              columns={cols}
              density="compact"
              emptyMessage="Sem dados no período"
            />
          </ChartCard>
        </>
      )}
    </div>
  );
}

/* ── Técnicos ── */
function TechniciansTab() {
  const { formatCurrency } = useI18n();
  const { data, isLoading, error, refetch } = useTechnicianProductivityReport();
  if (isLoading) return <LoadingBlock />;
  if (error) return <ErrorBlock onRetry={() => refetch()} />;
  if (!data) return <LoadingBlock />;

  type TechRow = { name: string; os_count: number; hours: number; avg_per_os: number; revenue: number; profit: number };
  const cols: DataColumn<TechRow>[] = [
    { key: 'name', header: 'Técnico', minWidth: 160, priority: 0, render: (r) => <span className="truncate font-semibold">{r.name}</span> },
    { key: 'os', header: 'OS concluídas', minWidth: 110, priority: 1, align: 'right', render: (r) => <span className="tabular-nums">{r.os_count}</span> },
    { key: 'revenue', header: 'Receita gerada', minWidth: 130, priority: 1, align: 'right', render: (r) => formatCurrency(r.revenue) },
    { key: 'profit', header: 'Lucro líquido', minWidth: 130, priority: 1, align: 'right', render: (r) => <span className="font-bold text-success">{formatCurrency(r.profit)}</span> },
    { key: 'hours', header: 'Horas', minWidth: 90, priority: 3, align: 'right', detailLabel: 'Horas', render: (r) => <span className="tabular-nums">{r.hours}h</span> },
    { key: 'avg', header: 'Média h/OS', minWidth: 100, priority: 3, align: 'right', detailLabel: 'Média h/OS', render: (r) => <span className="tabular-nums">{r.avg_per_os}h</span> },
  ];

  return (
    <div className="space-y-4">
      <ChartCard title="OS concluídas por técnico">
        <ResponsiveContainer width="100%" height={260}>
          <BarChart data={data.rows}>
            <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" vertical={false} />
            <XAxis dataKey="name" tick={axisTick} axisLine={false} tickLine={false} />
            <YAxis tick={axisTick} width={32} axisLine={false} tickLine={false} />
            <Tooltip cursor={{ fill: 'hsl(var(--muted))' }} />
            <Bar dataKey="os_count" fill="hsl(var(--chart-2))" radius={[3, 3, 0, 0]} />
          </BarChart>
        </ResponsiveContainer>
      </ChartCard>
      <ChartCard
        title="Produtividade detalhada"
        action={
          <Button
            size="sm" variant="outline" className="gap-1.5"
            onClick={() => exportCSV('tecnicos.csv', (data.rows as TechRow[]).map((r) => ({
              'Técnico': r.name, 'OS Concluídas': r.os_count, Horas: r.hours,
              'Média h/OS': r.avg_per_os, Receita: r.revenue, 'Lucro Líquido': r.profit,
            })))}
          >
            <Download className="h-4 w-4" /> CSV
          </Button>
        }
      >
        <DataTable rows={data.rows as TechRow[]} rowKey={(r) => r.name} columns={cols} density="compact" emptyMessage="Sem dados" />
      </ChartCard>
    </div>
  );
}

/* ── Lucratividade ── */
function ProfitabilityTab() {
  const { formatCurrency } = useI18n();
  const navigate = useNavigate();
  const [period, setPeriod] = useState('30');
  const { data, isLoading, error, refetch } = useProfitabilityReport(Number(period));

  type ProfitRow = { id: string; number: string; client: string; revenue: number; cost: number; profit: number; margin: number };
  const cols: DataColumn<ProfitRow>[] = [
    {
      key: 'number', header: 'OS / Cliente', minWidth: 190, priority: 0,
      render: (r) => (
        <span className="block leading-tight">
          <span className="block font-semibold text-accent">{r.number}</span>
          <span className="block truncate text-xs text-muted-foreground">{r.client}</span>
        </span>
      ),
    },
    { key: 'revenue', header: 'Faturamento', minWidth: 120, priority: 1, align: 'right', render: (r) => formatCurrency(r.revenue) },
    { key: 'profit', header: 'Lucro líquido', minWidth: 124, priority: 1, align: 'right', render: (r) => <span className="font-bold text-success">{formatCurrency(r.profit)}</span> },
    {
      key: 'margin', header: 'Margem', minWidth: 96, priority: 2, align: 'right',
      render: (r) => <StatusChip tone={(r.margin || 0) > 30 ? 'success' : 'warning'}>{(r.margin || 0).toFixed(1)}%</StatusChip>,
    },
    { key: 'cost', header: 'Custo total', minWidth: 116, priority: 3, align: 'right', detailLabel: 'Custo', render: (r) => <span className="text-destructive">{formatCurrency(r.cost)}</span> },
  ];

  const d = data as (typeof data & { totalRevenue?: number; totalProfit?: number; avgMargin?: number; topOS?: ProfitRow[]; rows?: ProfitRow[] }) | undefined;

  return (
    <div className="space-y-4">
      <PeriodSelect value={period} onChange={setPeriod} max={180} />
      {isLoading ? <LoadingBlock /> : error ? <ErrorBlock onRetry={() => refetch()} /> : !d?.rows ? <LoadingBlock /> : (
        <>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
            <KPIStat label="Faturamento total" value={formatCurrency(d.totalRevenue || 0)} />
            <KPIStat label="Lucro bruto real" value={formatCurrency(d.totalProfit || 0)} tone="success" />
            <KPIStat label="Margem média" value={`${(d.avgMargin || 0).toFixed(1)}%`} />
          </div>
          <ChartCard title="Lucro vs custo por OS (Top 10)">
            <ResponsiveContainer width="100%" height={300}>
              <BarChart data={(d.topOS || []).slice(0, 10)} layout="vertical" margin={{ left: 24 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" horizontal={false} />
                <XAxis type="number" tick={axisTick} tickFormatter={(v: number) => `${(v / 1000).toFixed(0)}k`} axisLine={false} tickLine={false} />
                <YAxis type="category" dataKey="number" tick={axisTick} width={92} axisLine={false} tickLine={false} />
                <Tooltip formatter={(v: number) => formatCurrency(v)} cursor={{ fill: 'hsl(var(--muted))' }} />
                <Legend wrapperStyle={{ fontSize: 12 }} />
                <Bar dataKey="profit" name="Lucro" stackId="a" fill="hsl(var(--chart-4))" />
                <Bar dataKey="cost" name="Custo total" stackId="a" fill="hsl(var(--chart-5))" radius={[0, 3, 3, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </ChartCard>
          <ChartCard
            title="Detalhamento de lucratividade por OS"
            action={
              <Button
                size="sm" variant="outline" className="gap-1.5"
                onClick={() => exportCSV('lucratividade.csv', (d.rows || []).map((r) => ({
                  OS: r.number, Cliente: r.client, Faturamento: r.revenue,
                  'Custo Total': r.cost, 'Lucro Líquido': r.profit, 'Margem %': r.margin,
                })))}
              >
                <Download className="h-4 w-4" /> CSV
              </Button>
            }
          >
            <DataTable
              rows={d.rows}
              rowKey={(r) => r.id}
              columns={cols}
              density="compact"
              onRowClick={(r) => navigate(`/v2/service-orders/${r.id}`)}
              emptyMessage="Sem dados no período"
            />
          </ChartCard>
        </>
      )}
    </div>
  );
}

export default function ReportsV2() {
  const { t } = useI18n();
  const [searchParams, setSearchParams] = useSearchParams();
  const tab = searchParams.get('tab') || 'revenue';
  const setTab = (v: string) => setSearchParams((prev) => { prev.set('tab', v); return prev; }, { replace: true });

  const { data: dataProfitability } = useProfitabilityReport(30);
  const { data: dataPerformance } = useOsPerformanceReport();

  return (
    <V2Shell>
      <PageShell
        breadcrumb={[{ label: 'Financeiro', to: '/v2/financial' }, { label: t.reports.title }]}
        title={t.reports.title}
        description={t.reports.description}
      >
        <AIConsultantDashboard
          data={{
            profitability: (dataProfitability as { rows?: unknown[] } | undefined)?.rows || [],
            performance: dataPerformance || {},
          }}
        />
        <Tabs value={tab} onValueChange={setTab} className="space-y-4">
          <TabsList className="flex h-auto w-full flex-wrap justify-start">
            <TabsTrigger value="revenue" className="gap-1.5"><DollarSign className="h-4 w-4" />Receita</TabsTrigger>
            <TabsTrigger value="performance" className="gap-1.5"><BarChart3 className="h-4 w-4" />Performance</TabsTrigger>
            <TabsTrigger value="parts" className="gap-1.5"><Package className="h-4 w-4" />Peças</TabsTrigger>
            <TabsTrigger value="technicians" className="gap-1.5"><Users className="h-4 w-4" />Técnicos</TabsTrigger>
            <TabsTrigger value="profitability" className="gap-1.5"><TrendingUp className="h-4 w-4" />Lucratividade</TabsTrigger>
          </TabsList>
          <TabsContent value="revenue"><RevenueTab /></TabsContent>
          <TabsContent value="performance"><PerformanceTab /></TabsContent>
          <TabsContent value="parts"><PartsTab /></TabsContent>
          <TabsContent value="technicians"><TechniciansTab /></TabsContent>
          <TabsContent value="profitability"><ProfitabilityTab /></TabsContent>
        </Tabs>
      </PageShell>
    </V2Shell>
  );
}
