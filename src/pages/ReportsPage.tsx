import { useState } from 'react';
import { Link } from 'react-router-dom';
import { PageHeader } from '@/components/PageHeader';
import { KPICard } from '@/components/KPICard';
import { AIConsultantDashboard } from '@/components/AIConsultantDashboard';
import { useI18n } from '@/i18n';
import {
  useRevenueReport,
  useOsPerformanceReport,
  usePartsUsageReport,
  useTechnicianProductivityReport,
  useProfitabilityReport,
} from '@/hooks/use-reports';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { StatusBadge } from '@/components/StatusBadge';
import { Badge } from '@/components/ui/badge';
import {
  BarChart3, Clock, Wrench, DollarSign, TrendingUp, FileCheck,
  AlertTriangle, Percent, Users, Package, Loader2, RefreshCw, Download,
} from 'lucide-react';

// ── CSV export utility ──────────────────────────────────────
function exportCSV(filename: string, rows: Record<string, any>[]) {
  if (!rows.length) return;
  const headers = Object.keys(rows[0]);
  const escape = (v: any) => {
    const s = v == null ? '' : String(v);
    return s.includes(',') || s.includes('"') || s.includes('\n') ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const csv = [headers.join(','), ...rows.map(r => headers.map(h => escape(r[h])).join(','))].join('\n');
  const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url; a.download = filename; a.click();
  URL.revokeObjectURL(url);
}
import { Button } from '@/components/ui/button';
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer,
  PieChart, Pie, Cell, Legend,
} from 'recharts';

const COLORS = [
  'hsl(210,60%,25%)', 'hsl(174,60%,35%)', 'hsl(38,92%,50%)',
  'hsl(152,60%,40%)', 'hsl(0,72%,51%)', 'hsl(215,12%,50%)', 'hsl(280,50%,45%)',
];

function ChartCard({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="rounded-xl border bg-card p-5 shadow-sm">
      <h3 className="text-sm font-semibold mb-4">{title}</h3>
      {children}
    </div>
  );
}

function LoadingBlock() {
  return (
    <div className="flex items-center justify-center py-12 text-muted-foreground">
      <Loader2 className="h-5 w-5 animate-spin mr-2" /> Carregando...
    </div>
  );
}

function ErrorBlock({ onRetry }: { onRetry?: () => void }) {
  return (
    <div className="flex flex-col items-center justify-center py-12 gap-3 text-center">
      <AlertTriangle className="h-8 w-8 text-destructive" />
      <p className="text-sm text-muted-foreground">Erro ao carregar relatório.</p>
      {onRetry && (
        <Button variant="outline" size="sm" onClick={onRetry}>
          <RefreshCw className="h-4 w-4 mr-2" /> Tentar novamente
        </Button>
      )}
    </div>
  );
}

// =============== TAB 1: REVENUE ===============
function RevenueTab() {
  const { formatCurrency } = useI18n();
  const [period, setPeriod] = useState('30');
  const { data, isLoading, error, refetch } = useRevenueReport(Number(period));

  return (
    <div className="space-y-6">
      <div className="flex justify-end">
        <Select value={period} onValueChange={setPeriod}>
          <SelectTrigger className="w-48"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="30">Últimos 30 dias</SelectItem>
            <SelectItem value="90">Últimos 90 dias</SelectItem>
            <SelectItem value="180">Últimos 180 dias</SelectItem>
            <SelectItem value="365">Últimos 365 dias</SelectItem>
          </SelectContent>
        </Select>
      </div>

      {isLoading ? <LoadingBlock /> : error ? <ErrorBlock onRetry={() => refetch()} /> : !data ? <LoadingBlock /> : (
        <>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
            <KPICard title="Total recebido" value={formatCurrency(data.totalReceived)} icon={DollarSign} />
            <KPICard title="Ticket médio (OS concluída)" value={formatCurrency(data.avgTicket)} icon={BarChart3} />
            <KPICard title="OS faturadas" value={String(data.invoicedCount)} icon={FileCheck} />
            <KPICard title="Margem estimada" value={formatCurrency(data.margin)} icon={TrendingUp} />
          </div>

          <ChartCard title="Receita por mês (últimos 6 meses)">
            <ResponsiveContainer width="100%" height={260}>
              <BarChart data={data.monthlyRevenue}>
                <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
                <XAxis dataKey="month" className="text-xs" />
                <YAxis className="text-xs" tickFormatter={v => formatCurrency(v).replace(/[^\d.,KkMm-]/g, '')} />
                <Tooltip formatter={(v: number) => formatCurrency(v)} />
                <Bar dataKey="value" fill="hsl(210,60%,25%)" radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </ChartCard>

          <ChartCard title="Top 10 clientes por receita">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>#</TableHead>
                  <TableHead>Cliente</TableHead>
                  <TableHead className="text-right">Receita</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {data.topClients.length === 0 ? (
                  <TableRow><TableCell colSpan={3} className="text-center text-muted-foreground py-8">Sem dados no período</TableCell></TableRow>
                ) : data.topClients.map((c, i) => (
                  <TableRow key={c.name + i}>
                    <TableCell className="text-muted-foreground">{i + 1}</TableCell>
                    <TableCell className="font-medium">{c.name}</TableCell>
                    <TableCell className="text-right font-mono">{formatCurrency(c.revenue)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </ChartCard>
        </>
      )}
    </div>
  );
}

// =============== TAB 2: OS PERFORMANCE ===============
function PerformanceTab() {
  const { data, isLoading, error, refetch } = useOsPerformanceReport();

  if (isLoading) return <LoadingBlock />;
  if (error) return <ErrorBlock onRetry={() => refetch()} />;
  if (!data) return <LoadingBlock />;

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <KPICard title="OS abertas" value={String(data.openCount)} subtitle={`${data.completedCount} concluídas`} icon={Wrench} />
        <KPICard title="Tempo médio de conclusão" value={`${data.avgCompletionHours.toFixed(1)}h`} icon={Clock} />
        <KPICard title="Taxa de conversão" value={`${data.conversionRate.toFixed(0)}%`} subtitle="Orçamento → Aprovado" icon={Percent} />
        <KPICard title="OS em atraso" value={String(data.overdueCount)} icon={AlertTriangle} />
      </div>

      <ChartCard title="Distribuição por status">
        <ResponsiveContainer width="100%" height={260}>
          <PieChart>
            <Pie
              data={data.statusDistribution}
              cx="50%" cy="50%"
              innerRadius={60} outerRadius={100}
              dataKey="value"
              label={({ name, value }) => `${name} (${value})`}
            >
              {data.statusDistribution.map((_, i) => <Cell key={i} fill={COLORS[i % COLORS.length]} />)}
            </Pie>
            <Tooltip />
            <Legend />
          </PieChart>
        </ResponsiveContainer>
      </ChartCard>

      <ChartCard title="OS abertas há mais de 7 dias sem atualização">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>OS</TableHead>
              <TableHead>Cliente</TableHead>
              <TableHead>Status</TableHead>
              <TableHead className="text-right">Dias parada</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {data.staleOrders.length === 0 ? (
              <TableRow><TableCell colSpan={4} className="text-center text-muted-foreground py-8">Nenhuma OS parada 🎉</TableCell></TableRow>
            ) : data.staleOrders.map(o => (
              <TableRow key={o.id}>
                <TableCell>
                  <Link to={`/service-orders/${o.id}`} className="font-medium text-primary hover:underline">
                    {o.number}
                  </Link>
                </TableCell>
                <TableCell>{o.client}</TableCell>
                <TableCell><StatusBadge className="bg-muted text-foreground">{o.status}</StatusBadge></TableCell>
                <TableCell className="text-right font-mono">{o.days_since}d</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </ChartCard>
    </div>
  );
}

// =============== TAB 3: PARTS USAGE ===============
function PartsTab() {
  const { formatCurrency } = useI18n();
  const [period, setPeriod] = useState('30');
  const { data, isLoading, error, refetch } = usePartsUsageReport(Number(period));

  return (
    <div className="space-y-6">
      <div className="flex justify-end">
        <Select value={period} onValueChange={setPeriod}>
          <SelectTrigger className="w-48"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="30">Últimos 30 dias</SelectItem>
            <SelectItem value="90">Últimos 90 dias</SelectItem>
            <SelectItem value="180">Últimos 180 dias</SelectItem>
          </SelectContent>
        </Select>
      </div>

      {isLoading ? <LoadingBlock /> : error ? <ErrorBlock onRetry={() => refetch()} /> : !data ? <LoadingBlock /> : (
        <>
          <ChartCard title="Top 10 peças por quantidade">
            <ResponsiveContainer width="100%" height={320}>
              <BarChart data={data.top10} layout="vertical" margin={{ left: 30 }}>
                <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
                <XAxis type="number" className="text-xs" />
                <YAxis type="category" dataKey="name" className="text-xs" width={140} />
                <Tooltip />
                <Bar dataKey="qty" fill="hsl(174,60%,35%)" radius={[0, 4, 4, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </ChartCard>

          <ChartCard title="Top 20 peças (detalhado)">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Peça</TableHead>
                  <TableHead className="text-right">Qtd. usada</TableHead>
                  <TableHead className="text-right">Receita</TableHead>
                  <TableHead className="text-right">Preço médio</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {data.rows.length === 0 ? (
                  <TableRow><TableCell colSpan={4} className="text-center text-muted-foreground py-8">Sem dados no período</TableCell></TableRow>
                ) : data.rows.map((r, i) => (
                  <TableRow key={r.name + i}>
                    <TableCell className="font-medium">{r.name}</TableCell>
                    <TableCell className="text-right font-mono">{r.qty}</TableCell>
                    <TableCell className="text-right font-mono">{formatCurrency(r.revenue)}</TableCell>
                    <TableCell className="text-right font-mono">{formatCurrency(r.avg_price)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </ChartCard>
        </>
      )}
    </div>
  );
}

// =============== TAB 4: TECHNICIAN PRODUCTIVITY ===============
function TechniciansTab() {
  const { formatCurrency } = useI18n();
  const { data, isLoading, error, refetch } = useTechnicianProductivityReport();

  if (isLoading) return <LoadingBlock />;
  if (error) return <ErrorBlock onRetry={() => refetch()} />;
  if (!data) return <LoadingBlock />;

  return (
    <div className="space-y-6">
      <ChartCard title="OS concluídas por técnico">
        <ResponsiveContainer width="100%" height={280}>
          <BarChart data={data.rows}>
            <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
            <XAxis dataKey="name" className="text-xs" />
            <YAxis className="text-xs" />
            <Tooltip />
            <Bar dataKey="os_count" fill="hsl(210,60%,25%)" radius={[4, 4, 0, 0]} />
          </BarChart>
        </ResponsiveContainer>
      </ChartCard>

      <ChartCard title="Produtividade detalhada">
        <div className="flex justify-end mb-3">
          <Button size="sm" variant="outline" className="gap-2 h-7 text-xs"
            onClick={() => exportCSV('tecnicos.csv', data.rows.map((r: any) => ({
              Técnico: r.name, 'OS Concluídas': r.os_count, 'Horas': r.hours,
              'Média h/OS': r.avg_per_os, 'Receita': r.revenue, 'Lucro Líquido': r.profit,
            })))}
          >
            <Download className="h-3 w-3" /> Exportar CSV
          </Button>
        </div>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Técnico</TableHead>
              <TableHead className="text-right">OS concluídas</TableHead>
              <TableHead className="text-right hidden sm:table-cell">Horas</TableHead>
              <TableHead className="text-right hidden sm:table-cell">Média h/OS</TableHead>
              <TableHead className="text-right">Receita gerada</TableHead>
              <TableHead className="text-right text-emerald-600">Lucro Líquido</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {data.rows.length === 0 ? (
              <TableRow><TableCell colSpan={5} className="text-center text-muted-foreground py-8">Sem dados</TableCell></TableRow>
            ) : data.rows.map(r => (
              <TableRow key={r.name}>
                <TableCell className="font-medium">{r.name}</TableCell>
                <TableCell className="text-right font-mono">{r.os_count}</TableCell>
                <TableCell className="text-right font-mono hidden sm:table-cell">{r.hours}h</TableCell>
                <TableCell className="text-right font-mono hidden sm:table-cell">{r.avg_per_os}h</TableCell>
                <TableCell className="text-right font-mono">{formatCurrency(r.revenue)}</TableCell>
                <TableCell className="text-right font-mono font-bold text-emerald-600">{formatCurrency(r.profit)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </ChartCard>
    </div>
  );
}

// =============== TAB 5: REAL PROFITABILITY ===============
function ProfitabilityTab() {
  const { formatCurrency } = useI18n();
  const [period, setPeriod] = useState('30');
  const { data: rawData, isLoading, error, refetch } = (useProfitabilityReport as any)(Number(period));
  const data = rawData as any;

  return (
    <div className="space-y-6">
      <div className="flex justify-end">
        <Select value={period} onValueChange={setPeriod}>
          <SelectTrigger className="w-48"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="30">Últimos 30 dias</SelectItem>
            <SelectItem value="90">Últimos 90 dias</SelectItem>
            <SelectItem value="180">Últimos 180 dias</SelectItem>
          </SelectContent>
        </Select>
      </div>

      {isLoading ? <LoadingBlock /> : error ? <ErrorBlock onRetry={() => refetch()} /> : !data || !data.rows ? <LoadingBlock /> : (
        <>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            <KPICard title="Faturamento Total" value={formatCurrency(data.totalRevenue)} icon={DollarSign} />
            <KPICard title="Lucro Bruto Real" value={formatCurrency(data.totalProfit)} icon={TrendingUp} className="border-emerald-200 bg-emerald-50/20" />
            <KPICard title="Margem Média" value={`${(data.avgMargin || 0).toFixed(1)}%`} icon={Percent} />
          </div>

          <ChartCard title="Lucro vs Custo por OS (Top 10)">
            <ResponsiveContainer width="100%" height={320}>
              <BarChart data={(data.topOS || []).slice(0, 10)} layout="vertical" margin={{ left: 30 }}>
                <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
                <XAxis type="number" className="text-xs" tickFormatter={v => formatCurrency(v).replace(/[^\d.,]/g, '')} />
                <YAxis type="category" dataKey="number" className="text-xs" width={100} />
                <Tooltip formatter={(v: number) => formatCurrency(v)} />
                <Legend />
                <Bar dataKey="profit" name="Lucro" fill="hsl(152,60%,40%)" stackId="a" radius={[0, 0, 0, 0]} />
                <Bar dataKey="cost" name="Custo Total" fill="hsl(0,72%,51%)" stackId="a" radius={[0, 4, 4, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </ChartCard>

          <ChartCard title="Detalhamento de Lucratividade por OS">
            <div className="flex justify-end mb-3">
              <Button size="sm" variant="outline" className="gap-2 h-7 text-xs"
                onClick={() => exportCSV('lucratividade.csv', data.rows.map((r: any) => ({
                  OS: r.number, Cliente: r.client, Faturamento: r.revenue,
                  'Custo Total': r.cost, 'Lucro Líquido': r.profit, 'Margem %': r.margin,
                })))}
              >
                <Download className="h-3 w-3" /> Exportar CSV
              </Button>
            </div>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>OS / Cliente</TableHead>
                  <TableHead className="text-right">Faturamento</TableHead>
                  <TableHead className="text-right hidden sm:table-cell">Custo Total</TableHead>
                  <TableHead className="text-right">Lucro Líquido</TableHead>
                  <TableHead className="text-right">Margem</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {data.rows.length === 0 ? (
                  <TableRow><TableCell colSpan={5} className="text-center text-muted-foreground py-8">Sem dados no período</TableCell></TableRow>
                ) : data.rows.map((r, i) => (
                  <TableRow key={r.id}>
                    <TableCell>
                      <Link to={`/service-orders/${r.id}`} className="font-medium text-primary hover:underline">{r.number}</Link>
                      <span className="block text-[10px] text-muted-foreground truncate max-w-[200px]">{r.client}</span>
                    </TableCell>
                    <TableCell className="text-right font-mono">{formatCurrency(r.revenue)}</TableCell>
                    <TableCell className="text-right font-mono text-destructive hidden sm:table-cell">{formatCurrency(r.cost)}</TableCell>
                    <TableCell className="text-right font-mono font-bold text-emerald-600">{formatCurrency(r.profit)}</TableCell>
                    <TableCell className="text-right font-mono">
                      <Badge variant="outline" className={r.margin > 30 ? 'bg-emerald-50 text-emerald-700' : 'bg-amber-50 text-amber-700'}>
                        {r.margin.toFixed(1)}%
                      </Badge>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </ChartCard>
        </>
      )}
    </div>
  );
}

// =============== MAIN PAGE ===============
export default function ReportsPage() {
  const { t } = useI18n();
  const { data: dataProfitability } = useProfitabilityReport(30);
  const { data: dataPerformance } = useOsPerformanceReport();

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader title={t.reports.title} description={t.reports.description} />

      <AIConsultantDashboard 
        data={{
          profitability: dataProfitability?.rows || [],
          performance: dataPerformance || {}
        }} 
      />

      <Tabs defaultValue="revenue" className="space-y-6">
        <TabsList className="grid w-full grid-cols-2 lg:grid-cols-4 h-auto">
          <TabsTrigger value="revenue" className="gap-2"><DollarSign className="h-4 w-4" />Receita</TabsTrigger>
          <TabsTrigger value="performance" className="gap-2"><BarChart3 className="h-4 w-4" />Performance</TabsTrigger>
          <TabsTrigger value="parts" className="gap-2"><Package className="h-4 w-4" />Peças</TabsTrigger>
          <TabsTrigger value="technicians" className="gap-2"><Users className="h-4 w-4" />Técnicos</TabsTrigger>
          <TabsTrigger value="profitability" className="gap-2"><TrendingUp className="h-4 w-4 text-emerald-500" />Lucratividade</TabsTrigger>
        </TabsList>

        <TabsContent value="revenue"><RevenueTab /></TabsContent>
        <TabsContent value="performance"><PerformanceTab /></TabsContent>
        <TabsContent value="parts"><PartsTab /></TabsContent>
        <TabsContent value="technicians"><TechniciansTab /></TabsContent>
        <TabsContent value="profitability"><ProfitabilityTab /></TabsContent>
      </Tabs>
    </div>
  );
}
