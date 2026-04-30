import { useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '@/hooks/use-auth';
import { useDashboardData } from '@/hooks/use-dashboard';
import { useI18n } from '@/i18n';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';
import { TrendingUp, TrendingDown, AlertTriangle, CheckCircle, DollarSign, Package, ArrowRight, RefreshCw, Clock, Users, ShoppingCart, Plus } from 'lucide-react';
import { Skeleton } from '@/components/ui/skeleton';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { statusConfig } from '@/lib/constants';
import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

const STATUS_ORDER = ['draft', 'scheduled', 'open', 'in_progress', 'awaiting_parts', 'awaiting_client', 'completed', 'invoiced'];

export default function Dashboard() {
  const { formatCurrency, t, locale } = useI18n();
  const navigate = useNavigate();
  const { user } = useAuth();
  const { data, isLoading, error, refetch } = useDashboardData();
  const statusLabels = t.status as Record<string, string>;

  const hour = new Date().getHours();
  const d = t.dashboard as any;
  const greeting = hour < 12 ? d.greeting.morning
    : hour < 18 ? d.greeting.afternoon
    : d.greeting.evening;
  const weekdays = d.weekdays as string[];
  const today = new Date();
  const dateStr = `${weekdays[today.getDay()]}, ${today.toLocaleDateString(
    locale === 'pt-BR' ? 'pt-BR' : 'en-US',
    { day: 'numeric', month: 'long', year: 'numeric' }
  )}`;

  if (user?.role === 'external_seller') {
    return <ExternalSellerDashboard greeting={greeting} dateStr={dateStr} />;
  }

  if (error) {
    // ... existing error view ...
  }

  if (isLoading) {
    // ... existing loading view ...
  }

  // ... (keeping the rest of the existing dashboard for staff/admin) ...
}

function ExternalSellerDashboard({ greeting, dateStr }: { greeting: string, dateStr: string }) {
  const navigate = useNavigate();
  const { user } = useAuth();
  const { formatCurrency } = useI18n();

  // Fetch external seller specific stats
  const { data: stats, isLoading } = useQuery({
    queryKey: ['external-seller-stats', user?.id],
    queryFn: async () => {
      const { data: quotes } = await supabase
        .from('external_quotes')
        .select('status, grand_total')
        .eq('created_by', user?.id);
      
      const { count: leadsCount } = await supabase
        .from('external_quote_leads')
        .select('*', { count: 'exact', head: true })
        .eq('created_by', user?.id);

      const approved = quotes?.filter(q => q.status === 'approved') || [];
      const pending = quotes?.filter(q => q.status === 'pending_approval') || [];
      
      return {
        totalApproved: approved.reduce((s, q) => s + (q.grand_total || 0), 0),
        approvedCount: approved.length,
        pendingCount: pending.length,
        leadsCount: leadsCount || 0
      };
    },
    enabled: !!user?.id
  });

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex items-start justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">{greeting}, {user?.full_name?.split(' ')[0]}</h1>
          <p className="text-sm text-muted-foreground mt-0.5">{dateStr}</p>
        </div>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <KPIBox
          title="Vendas Aprovadas"
          value={formatCurrency(stats?.totalApproved || 0)}
          icon={<TrendingUp className="h-5 w-5 text-emerald-600" />}
          iconBg="bg-emerald-100 dark:bg-emerald-900/30"
          subtext={`${stats?.approvedCount || 0} orçamentos aprovados`}
        />
        <KPIBox
          title="Aguardando Aprovação"
          value={String(stats?.pendingCount || 0)}
          icon={<Clock className="h-5 w-5 text-amber-600" />}
          iconBg="bg-amber-100 dark:bg-amber-900/30"
          onClick={() => navigate('/external-quotes')}
        />
        <KPIBox
          title="Meus Prospectos"
          value={String(stats?.leadsCount || 0)}
          icon={<Users className="h-5 w-5 text-blue-600" />}
          iconBg="bg-blue-100 dark:bg-blue-900/30"
          onClick={() => navigate('/external-quotes/leads')}
        />
        <KPIBox
          title="Produtos no Catálogo"
          value="Ver todos"
          icon={<Package className="h-5 w-5 text-purple-600" />}
          iconBg="bg-purple-100 dark:bg-purple-900/30"
          onClick={() => navigate('/external-quotes/catalog')}
        />
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <Card className="p-6 space-y-4">
          <h3 className="font-bold flex items-center gap-2">
            <ShoppingCart className="h-5 w-5 text-primary" /> Atalhos Rápidos
          </h3>
          <div className="grid grid-cols-1 gap-2">
            <Button onClick={() => navigate('/external-quotes/new')} className="w-full justify-start gap-2 h-12 text-base">
              <Plus className="h-5 w-5" /> Criar Novo Orçamento
            </Button>
            <Button variant="outline" onClick={() => navigate('/external-quotes/leads')} className="w-full justify-start gap-2 h-12 text-base">
              <Users className="h-5 w-5" /> Gerenciar Prospectos
            </Button>
          </div>
        </Card>

        <Card className="p-6 bg-primary text-primary-foreground">
          <h3 className="font-bold text-lg mb-2">Dica de Venda</h3>
          <p className="text-sm opacity-90">
            Mantenha seus prospectos sempre atualizados. Leads com informações completas de embarcação têm 40% mais chance de aprovação.
          </p>
          <div className="mt-4 pt-4 border-t border-primary-foreground/20">
            <Button variant="secondary" size="sm" onClick={() => navigate('/external-quotes/catalog')} className="w-full">
              Ver Catálogo de Produtos
            </Button>
          </div>
        </Card>
      </div>
    </div>
  );
}

  if (!data) {
    return (
      <div className="flex flex-col items-center justify-center py-20 gap-4">
        <p className="text-sm text-muted-foreground">Sem dados disponíveis.</p>
        <Button onClick={() => refetch()} variant="outline" size="sm">
          <RefreshCw className="h-4 w-4 mr-2" /> Recarregar
        </Button>
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
              className={`inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-medium transition-opacity hover:opacity-80 ${statusConfig[status as keyof typeof statusConfig]?.className || 'bg-muted text-muted-foreground'}`}
            >
              {statusLabels[status] || status}: {count}
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
                    <span className={`text-xs rounded-full px-2 py-0.5 font-medium ${statusConfig[so.status as keyof typeof statusConfig]?.className || 'bg-muted text-muted-foreground'}`}>
                      {statusLabels[so.status] || so.status}
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
            <div className="overflow-x-auto scrollbar-thin">
              <table className="w-full text-sm min-w-[600px]">
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
                        <span className={`inline-flex rounded-full px-2 py-0.5 text-xs font-medium ${statusConfig[so.status as keyof typeof statusConfig]?.className || 'bg-muted text-muted-foreground'}`}>
                          {statusLabels[so.status] || so.status}
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
