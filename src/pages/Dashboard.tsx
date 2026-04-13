import { useDashboardData } from '@/hooks/use-dashboard';
import { useI18n } from '@/i18n';
import { useNavigate } from 'react-router-dom';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';
import { TrendingUp, TrendingDown, AlertTriangle, CheckCircle, DollarSign, Package, ArrowRight, RefreshCw } from 'lucide-react';
import { Skeleton } from '@/components/ui/skeleton';
import { Button } from '@/components/ui/button';

const STATUS_LABELS: Record<string, string> = {
  draft: 'Rascunho', scheduled: 'Agendada', open: 'Aberta',
  in_progress: 'Em andamento', awaiting_parts: 'Aguard. Peças',
  awaiting_client: 'Aguard. Cliente', completed: 'Concluída', invoiced: 'Faturada',
};

const STATUS_COLORS: Record<string, string> = {
  draft: 'bg-muted text-muted-foreground',
  scheduled: 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400',
  open: 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400',
  in_progress: 'bg-primary/10 text-primary',
  awaiting_parts: 'bg-orange-100 text-orange-700 dark:bg-orange-900/30 dark:text-orange-400',
  awaiting_client: 'bg-purple-100 text-purple-700 dark:bg-purple-900/30 dark:text-purple-400',
  completed: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400',
  invoiced: 'bg-teal-100 text-teal-700 dark:bg-teal-900/30 dark:text-teal-400',
};

const STATUS_ORDER = ['draft', 'scheduled', 'open', 'in_progress', 'awaiting_parts', 'awaiting_client', 'completed', 'invoiced'];

export default function Dashboard() {
  const { formatCurrency } = useI18n();
  const navigate = useNavigate();
  const { data, isLoading, error, refetch } = useDashboardData();

  const hour = new Date().getHours();
  const greeting = hour < 12 ? 'Bom dia' : hour < 18 ? 'Boa tarde' : 'Boa noite';
  const weekdays = ['Domingo', 'Segunda-feira', 'Terça-feira', 'Quarta-feira', 'Quinta-feira', 'Sexta-feira', 'Sábado'];
  const today = new Date();
  const dateStr = `${weekdays[today.getDay()]}, ${today.toLocaleDateString('pt-BR', { day: 'numeric', month: 'long', year: 'numeric' })}`;

  if (error) {
    return (
      <div className="flex flex-col items-center justify-center py-20 gap-4">
        <AlertTriangle className="h-10 w-10 text-destructive" />
        <p className="text-sm text-muted-foreground">Erro ao carregar dados. Tente novamente.</p>
        <Button onClick={() => refetch()} variant="outline" size="sm">
          <RefreshCw className="h-4 w-4 mr-2" /> Tentar novamente
        </Button>
      </div>
    );
  }

  if (isLoading || !data) {
    return (
      <div className="space-y-6 animate-fade-in">
        <div className="space-y-1">
          <Skeleton className="h-8 w-64" />
          <Skeleton className="h-4 w-48" />
        </div>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          {[1, 2, 3, 4].map(i => <Skeleton key={i} className="h-28 rounded-xl" />)}
        </div>
        <Skeleton className="h-10 rounded-xl" />
        <div className="grid grid-cols-1 lg:grid-cols-5 gap-6">
          <Skeleton className="lg:col-span-3 h-64 rounded-xl" />
          <Skeleton className="lg:col-span-2 h-64 rounded-xl" />
        </div>
        <div className="grid grid-cols-1 lg:grid-cols-5 gap-6">
          <Skeleton className="lg:col-span-3 h-64 rounded-xl" />
          <Skeleton className="lg:col-span-2 h-64 rounded-xl" />
        </div>
      </div>
    );
  }

  const { totalReceivable, totalPayable, collectedThisMonth, collectedLastMonth, revenueGrowth,
    overdueReceivables, openOrders, openOrdersCount, statusCounts, completedThisMonth,
    completedThisMonthValue, upcomingOrders, revenueChart, lowStock } = data;

  const chartTotal = revenueChart.reduce((s, r) => s + r.revenue, 0);

  return (
    <div className="space-y-6 animate-fade-in">
      {/* Header */}
      <div className="flex items-start justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">{greeting}, MarineFlow</h1>
          <p className="text-sm text-muted-foreground mt-0.5">{dateStr}</p>
        </div>
        <Button variant="ghost" size="sm" onClick={() => refetch()} className="text-muted-foreground">
          <RefreshCw className="h-4 w-4 mr-1.5" /> Atualizar
        </Button>
      </div>

      {/* ROW 1 — Financial KPIs */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <KPIBox
          title="Recebido este mês"
          value={formatCurrency(collectedThisMonth)}
          icon={<TrendingUp className="h-5 w-5 text-emerald-600" />}
          iconBg="bg-emerald-100 dark:bg-emerald-900/30"
          badge={revenueGrowth !== null ? (
            <span className={`text-xs font-medium ${revenueGrowth >= 0 ? 'text-emerald-600' : 'text-destructive'}`}>
              {revenueGrowth >= 0 ? '↑' : '↓'} {Math.abs(revenueGrowth)}% vs mês anterior
            </span>
          ) : undefined}
          subtext={`vs ${formatCurrency(collectedLastMonth)} no mês anterior`}
        />
        <KPIBox
          title="A Receber"
          value={formatCurrency(totalReceivable)}
          icon={<DollarSign className="h-5 w-5 text-amber-600" />}
          iconBg="bg-amber-100 dark:bg-amber-900/30"
          badge={overdueReceivables > 0 ? (
            <span className="text-xs font-medium text-destructive">
              {formatCurrency(overdueReceivables)} em atraso
            </span>
          ) : undefined}
          onClick={() => navigate('/financial?tab=receivables')}
        />
        <KPIBox
          title="A Pagar"
          value={formatCurrency(totalPayable)}
          icon={<DollarSign className="h-5 w-5 text-blue-600" />}
          iconBg="bg-blue-100 dark:bg-blue-900/30"
          onClick={() => navigate('/financial?tab=payables')}
        />
        <KPIBox
          title="OS Concluídas este mês"
          value={String(completedThisMonth)}
          icon={<CheckCircle className="h-5 w-5 text-emerald-600" />}
          iconBg="bg-emerald-100 dark:bg-emerald-900/30"
          subtext={`Total: ${formatCurrency(completedThisMonthValue)}`}
        />
      </div>

      {/* ROW 2 — Status strip */}
      <div className="flex flex-wrap gap-2">
        {STATUS_ORDER.map(status => {
          const count = statusCounts[status] || 0;
          if (count === 0) return null;
          return (
            <button
              key={status}
              onClick={() => navigate(`/service-orders?status=${status}`)}
              className={`inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-medium transition-opacity hover:opacity-80 ${STATUS_COLORS[status]}`}
            >
              {STATUS_LABELS[status]}: {count}
            </button>
          );
        })}
        {Object.keys(statusCounts).length === 0 && (
          <p className="text-xs text-muted-foreground">Nenhuma OS registrada.</p>
        )}
      </div>

      {/* ROW 3 — Chart + Upcoming */}
      <div className="grid grid-cols-1 lg:grid-cols-5 gap-6">
        <div className="lg:col-span-3 rounded-xl border bg-card p-5 shadow-sm">
          <h3 className="text-sm font-semibold mb-4">Receita — últimos 6 meses</h3>
          {revenueChart.some(r => r.revenue > 0) ? (
            <>
              <ResponsiveContainer width="100%" height={220}>
                <BarChart data={revenueChart}>
                  <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
                  <XAxis dataKey="month" tick={{ fontSize: 12 }} className="fill-muted-foreground" />
                  <YAxis tickFormatter={v => `R$ ${(v / 1000).toFixed(0)}k`} tick={{ fontSize: 12 }} className="fill-muted-foreground" />
                  <Tooltip formatter={(v: number) => formatCurrency(v)} labelFormatter={l => l} />
                  <Bar dataKey="revenue" fill="hsl(var(--accent))" radius={[4, 4, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
              <p className="text-xs text-muted-foreground mt-2">
                Total no período: <span className="font-medium text-foreground">{formatCurrency(chartTotal)}</span>
              </p>
            </>
          ) : (
            <p className="text-sm text-muted-foreground py-16 text-center">Nenhuma receita registrada no período.</p>
          )}
        </div>

        <div className="lg:col-span-2 rounded-xl border bg-card shadow-sm">
          <div className="flex items-center justify-between p-5 border-b">
            <h3 className="text-sm font-semibold">Próximos 7 dias</h3>
          </div>
          <div className="divide-y">
            {upcomingOrders.length === 0 ? (
              <p className="text-sm text-muted-foreground p-5 text-center">Nenhuma OS agendada</p>
            ) : (
              upcomingOrders.map((so: any) => (
                <button
                  key={so.id}
                  onClick={() => navigate(`/service-orders/${so.id}`)}
                  className="block w-full text-left p-4 hover:bg-muted/30 transition-colors"
                >
                  <div className="flex items-center justify-between">
                    <span className="text-sm font-medium text-accent">{so.service_order_number}</span>
                    <span className={`text-xs rounded-full px-2 py-0.5 font-medium ${STATUS_COLORS[so.status] || ''}`}>
                      {STATUS_LABELS[so.status] || so.status}
                    </span>
                  </div>
                  <p className="text-xs text-muted-foreground mt-1">
                    {so.clients?.full_name_or_company_name} · {so.vessels?.boat_name}
                  </p>
                  {so.scheduled_start_at && (
                    <p className="text-xs text-muted-foreground">
                      {new Date(so.scheduled_start_at).toLocaleDateString('pt-BR', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })}
                    </p>
                  )}
                </button>
              ))
            )}
          </div>
        </div>
      </div>

      {/* ROW 4 — Open orders + Alerts */}
      <div className="grid grid-cols-1 lg:grid-cols-5 gap-6">
        <div className="lg:col-span-3 rounded-xl border bg-card shadow-sm">
          <div className="flex items-center justify-between p-5 border-b">
            <h3 className="text-sm font-semibold">OS em andamento ({openOrdersCount})</h3>
            <button onClick={() => navigate('/service-orders')} className="text-xs font-medium text-accent hover:underline flex items-center gap-1">
              Ver todas <ArrowRight className="h-3 w-3" />
            </button>
          </div>
          {openOrders.length === 0 ? (
            <p className="text-sm text-muted-foreground p-8 text-center">Nenhuma OS em aberto</p>
          ) : (
            <div className="overflow-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b">
                    <th className="px-4 py-2 text-left font-medium text-muted-foreground">OS</th>
                    <th className="px-4 py-2 text-left font-medium text-muted-foreground">Cliente</th>
                    <th className="px-4 py-2 text-left font-medium text-muted-foreground hidden md:table-cell">Embarcação</th>
                    <th className="px-4 py-2 text-left font-medium text-muted-foreground">Status</th>
                    <th className="px-4 py-2 text-right font-medium text-muted-foreground">Valor</th>
                  </tr>
                </thead>
                <tbody>
                  {openOrders.map((so: any) => (
                    <tr
                      key={so.id}
                      onClick={() => navigate(`/service-orders/${so.id}`)}
                      className="border-b hover:bg-muted/30 transition-colors cursor-pointer"
                    >
                      <td className="px-4 py-2.5 font-medium text-accent">{so.service_order_number}</td>
                      <td className="px-4 py-2.5 text-muted-foreground">{so.clients?.full_name_or_company_name || '—'}</td>
                      <td className="px-4 py-2.5 text-muted-foreground hidden md:table-cell">{so.vessels?.boat_name || '—'}</td>
                      <td className="px-4 py-2.5">
                        <span className={`inline-flex rounded-full px-2 py-0.5 text-xs font-medium ${STATUS_COLORS[so.status] || ''}`}>
                          {STATUS_LABELS[so.status] || so.status}
                        </span>
                      </td>
                      <td className="px-4 py-2.5 text-right font-medium">{formatCurrency(so.grand_total || 0)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>

        <div className="lg:col-span-2 rounded-xl border bg-card shadow-sm p-5 space-y-5">
          <h3 className="text-sm font-semibold">Alertas</h3>

          {/* Low stock */}
          <div className="space-y-2">
            <div className="flex items-center gap-2 text-xs font-medium text-muted-foreground">
              <Package className="h-3.5 w-3.5" /> Estoque abaixo do mínimo
            </div>
            {lowStock.length > 0 ? (
              <>
                {lowStock.map((p: any) => (
                  <div key={p.id} className="flex items-center justify-between rounded-lg border border-destructive/20 bg-destructive/5 px-3 py-2">
                    <div>
                      <p className="text-xs font-medium">{p.product_name}</p>
                      <p className="text-xs text-muted-foreground">{p.category || 'Sem categoria'}</p>
                    </div>
                    <div className="text-right">
                      <p className="text-xs font-medium text-destructive">{p.stock_quantity ?? 0} / {p.minimum_stock}</p>
                    </div>
                  </div>
                ))}
                <button onClick={() => navigate('/inventory')} className="text-xs font-medium text-accent hover:underline flex items-center gap-1">
                  Ver estoque <ArrowRight className="h-3 w-3" />
                </button>
              </>
            ) : (
              <p className="text-xs text-emerald-600 font-medium">✓ Estoque normalizado</p>
            )}
          </div>

          {/* Overdue receivables */}
          <div className="space-y-2">
            <div className="flex items-center gap-2 text-xs font-medium text-muted-foreground">
              <AlertTriangle className="h-3.5 w-3.5" /> Recebíveis em atraso
            </div>
            {overdueReceivables > 0 ? (
              <>
                <div className="rounded-lg border border-destructive/20 bg-destructive/5 px-3 py-2">
                  <p className="text-xs font-medium text-destructive">{formatCurrency(overdueReceivables)} em atraso</p>
                </div>
                <button onClick={() => navigate('/financial?tab=receivables')} className="text-xs font-medium text-accent hover:underline flex items-center gap-1">
                  Ver recebíveis <ArrowRight className="h-3 w-3" />
                </button>
              </>
            ) : (
              <p className="text-xs text-emerald-600 font-medium">✓ Sem recebíveis em atraso</p>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

/* KPI Card component */
function KPIBox({ title, value, icon, iconBg, badge, subtext, onClick }: {
  title: string;
  value: string;
  icon: React.ReactNode;
  iconBg: string;
  badge?: React.ReactNode;
  subtext?: string;
  onClick?: () => void;
}) {
  const Wrapper = onClick ? 'button' : 'div';
  return (
    <Wrapper
      onClick={onClick}
      className={`rounded-xl border bg-card p-5 shadow-sm text-left transition-colors ${onClick ? 'hover:bg-muted/30 cursor-pointer' : ''}`}
    >
      <div className="flex items-start justify-between">
        <div className="space-y-1 min-w-0">
          <p className="text-sm font-medium text-muted-foreground truncate">{title}</p>
          <p className="text-2xl font-bold tracking-tight">{value}</p>
          {badge}
          {subtext && <p className="text-xs text-muted-foreground">{subtext}</p>}
        </div>
        <div className={`rounded-lg p-2.5 ${iconBg}`}>
          {icon}
        </div>
      </div>
    </Wrapper>
  );
}
