import { useMemo } from 'react';
import { Link, Navigate, useNavigate } from 'react-router-dom';
import { AlertTriangle, ArrowRight, CalendarDays, CheckCircle2, Package, RefreshCw } from 'lucide-react';
import { Bar, BarChart, CartesianGrid, Cell, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { useI18n } from '@/i18n';
import { useAuth } from '@/hooks/use-auth';
import { useDashboardData } from '@/hooks/use-dashboard';
import { useServiceOrders } from '@/hooks/use-service-orders';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { PageShell } from '@/v2/components/PageShell';
import { KPIStat } from '@/v2/components/KPIStat';
import { StatusChip, type StatusTone } from '@/v2/components/StatusChip';
import { EntityCard } from '@/v2/components/EntityCard';
import { DataTable, type DataColumn } from '@/v2/components/DataTable';
import { serviceOrderStatusTone } from '@/v2/status-map';
import { V2Shell } from '@/v2/components/V2Shell';
import '@/v2/tokens.css';

/* ─────────────────────────────────────────────────────────────────────────────
   Fase 1 · Dashboard v2 — responde "o que precisa de mim agora?"
   - Fila única "Precisa de você hoje" (recebíveis vencidos, estoque baixo,
     OS urgente) com o botão da ação em cada item — mata a duplicação do v1
     (banner vermelho + card Alertas com 2 queries).
   - KPIs clicáveis levam à lista já filtrada (Recebíveis v2).
   - Papel technician vê "Minhas OS de hoje" no lugar dos KPIs financeiros.
   Rota /v2/dashboard — o Dashboard v1 em "/" permanece intacto.
──────────────────────────────────────────────────────────────────────────── */

type QueueItem = {
  key: string;
  tone: StatusTone;
  text: React.ReactNode;
  actionLabel: string;
  onAction: () => void;
};

type UpcomingSO = {
  id: string;
  service_order_number: string;
  status: string;
  priority?: string | null;
  scheduled_start_at?: string | null;
  grand_total?: number | null;
  clients?: { name?: string } | null;
  vessels?: { name?: string } | null;
  service_order_technicians?: { user_id: string }[] | null;
};

export default function DashboardV2() {
  const { t, formatCurrency, locale } = useI18n();
  const navigate = useNavigate();
  const { user } = useAuth();
  const { data, isLoading, error, refetch } = useDashboardData();
  const statusLabels = t.status as Record<string, string>;

  const hour = new Date().getHours();
  const d = t.dashboard as { greeting: Record<string, string>; weekdays: string[] };
  const greeting = hour < 12 ? d.greeting.morning : hour < 18 ? d.greeting.afternoon : d.greeting.evening;
  const today = new Date();
  const dateStr = `${d.weekdays[today.getDay()]}, ${today.toLocaleDateString(
    locale === 'pt-BR' ? 'pt-BR' : 'en-US',
    { day: 'numeric', month: 'long', year: 'numeric' },
  )}`;

  const isTechnician = user?.role === 'technician';

  // Vendedor externo sem acesso estendido: o dashboard dele vive na v1 ("/")
  const visibleAreas = (user?.metadata as { visible_areas?: string[] } | null)?.visible_areas;
  const legacyAreas = user?.department ? user.department.split(',').map((s) => s.trim()) : [];
  const allowedGroups = visibleAreas || legacyAreas;
  const hasExtendedAccess =
    allowedGroups.includes('operacional') || allowedGroups.includes('financeiro') || allowedGroups.includes('cadastros');
  if (user?.role === 'external_seller' && !hasExtendedAccess) {
    return <Navigate to="/" replace />;
  }

  if (error) {
    return (
      <V2Shell>
        <div className="flex flex-col items-center justify-center gap-4 py-20">
          <AlertTriangle className="h-10 w-10 text-destructive" />
          <p className="text-sm text-muted-foreground">Erro ao carregar dados. Tente novamente.</p>
          <Button onClick={() => refetch()} variant="outline" size="sm" className="gap-1.5">
            <RefreshCw className="h-4 w-4" /> Tentar novamente
          </Button>
        </div>
      </V2Shell>
    );
  }

  return (
    <V2Shell>
      <PageShell
        title={`${greeting}${user?.full_name ? `, ${user.full_name.split(' ')[0]}` : ''}!`}
        description={dateStr}
        actions={
          <Button variant="ghost" size="sm" onClick={() => refetch()} className="gap-1.5 text-muted-foreground">
            <RefreshCw className="h-4 w-4" /> Atualizar
          </Button>
        }
      >
        {isLoading || !data ? (
          <div className="space-y-4">
            <Skeleton className="h-28 w-full rounded-lg" />
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
              {[1, 2, 3, 4].map((i) => <Skeleton key={i} className="h-24 rounded-lg" />)}
            </div>
            <Skeleton className="h-64 w-full rounded-lg" />
          </div>
        ) : isTechnician ? (
          <TechnicianHome />
        ) : (
          <AdminHome data={data} navigate={navigate} formatCurrency={formatCurrency} statusLabels={statusLabels} />
        )}
      </PageShell>
    </V2Shell>
  );
}

/* ── Home do administrador/financeiro/vendedor ─────────────────────────────── */

function AdminHome({
  data, navigate, formatCurrency, statusLabels,
}: {
  data: NonNullable<ReturnType<typeof useDashboardData>['data']>;
  navigate: ReturnType<typeof useNavigate>;
  formatCurrency: (v: number) => string;
  statusLabels: Record<string, string>;
}) {
  const {
    totalReceivable, totalPayable, collectedThisMonth, revenueGrowth,
    overdueReceivables, openOrders, completedThisMonth,
    completedThisMonthValue, upcomingOrders, revenueChart, lowStock,
  } = data;

  // O hook v1 não exclui rascunhos — sem isto, orçamentos apareceriam como
  // "OS em andamento" (bug herdado do Dashboard v1; corrigido aqui no v2).
  const openReal = (openOrders as UpcomingSO[]).filter((so) => so.status !== 'draft');

  const queue: QueueItem[] = [];
  if (overdueReceivables > 0) {
    queue.push({
      key: 'overdue',
      tone: 'critical',
      text: <><b>{formatCurrency(overdueReceivables)} em recebíveis vencidos</b></>,
      actionLabel: 'Cobrar',
      onAction: () => navigate('/v2/receivables?view=overdue'),
    });
  }
  if (lowStock.length > 0) {
    queue.push({
      key: 'stock',
      tone: 'warning',
      text: (
        <>
          <b>{lowStock.length} produto{lowStock.length > 1 ? 's' : ''} abaixo do estoque mínimo</b>
          {' · '}
          <span className="text-muted-foreground">
            {(lowStock as { name: string }[]).slice(0, 2).map((p) => p.name).join(', ')}
            {lowStock.length > 2 ? '…' : ''}
          </span>
        </>
      ),
      actionLabel: 'Repor',
      onAction: () => navigate('/inventory'),
    });
  }
  const urgentToday = (upcomingOrders as UpcomingSO[]).find(
    (so) => so.priority === 'urgent' && so.scheduled_start_at && new Date(so.scheduled_start_at).toDateString() === new Date().toDateString(),
  );
  if (urgentToday) {
    queue.push({
      key: 'urgent',
      tone: 'warning',
      text: (
        <>
          <b>{urgentToday.service_order_number} urgente agendada para hoje</b>
          {' · '}
          <span className="text-muted-foreground">{urgentToday.clients?.name}</span>
        </>
      ),
      actionLabel: 'Abrir',
      onAction: () => navigate(`/v2/service-orders/${urgentToday.id}`),
    });
  }

  const queueTone: Record<StatusTone, string> = {
    critical: 'border-l-destructive',
    warning: 'border-l-warning',
    info: 'border-l-info',
    success: 'border-l-success',
    neutral: 'border-l-transparent',
  };

  const chartTotal = revenueChart.reduce((s: number, r: { revenue: number }) => s + r.revenue, 0);

  const openColumns: DataColumn<UpcomingSO>[] = [
    {
      key: 'number', header: 'OS', minWidth: 110, priority: 0,
      render: (so) => <span className="font-bold text-accent">{so.service_order_number}</span>,
    },
    {
      key: 'client', header: 'Cliente · Embarcação', minWidth: 200, priority: 1,
      render: (so) => (
        <span className="block leading-tight">
          <span className="block truncate font-semibold">{so.clients?.name || '—'}</span>
          <span className="block truncate text-xs text-muted-foreground">{so.vessels?.name || '—'}</span>
        </span>
      ),
    },
    {
      key: 'status', header: 'Status', minWidth: 140, priority: 2, detailLabel: 'Status',
      render: (so) => (
        <StatusChip dot tone={serviceOrderStatusTone[so.status] ?? 'neutral'}>
          {statusLabels[so.status] ?? so.status}
        </StatusChip>
      ),
    },
    {
      key: 'total', header: 'Valor', minWidth: 112, priority: 2, align: 'right', detailLabel: 'Valor',
      render: (so) => <span className="font-semibold">{formatCurrency(so.grand_total || 0)}</span>,
    },
  ];

  return (
    <>
      {/* Fila única acionável — substitui banner + card Alertas duplicados do v1 */}
      <section className="overflow-hidden rounded-lg border bg-card">
        <div className="flex items-center justify-between border-b px-4 py-2.5">
          <h2 className="text-sm font-bold">Precisa de você hoje · {queue.length}</h2>
        </div>
        {queue.length === 0 ? (
          <p className="flex items-center gap-2 px-4 py-4 text-sm font-medium text-success">
            <CheckCircle2 className="h-4 w-4" /> Tudo em dia — nenhuma pendência crítica.
          </p>
        ) : (
          queue.map((item) => (
            <div
              key={item.key}
              className={`flex items-center justify-between gap-3 border-b border-l-[3px] px-4 py-2.5 text-sm last:border-b-0 ${queueTone[item.tone]}`}
            >
              <span className="min-w-0 truncate">{item.text}</span>
              <Button variant="outline" size="sm" className="shrink-0" onClick={item.onAction}>
                {item.actionLabel}
              </Button>
            </div>
          ))
        )}
      </section>

      {/* KPIs clicáveis */}
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <KPIStat
          label="Recebido no mês"
          value={formatCurrency(collectedThisMonth)}
          hint={revenueGrowth !== null ? `${revenueGrowth >= 0 ? '▲' : '▼'} ${Math.abs(revenueGrowth)}% vs mês anterior` : undefined}
          tone={revenueGrowth !== null && revenueGrowth < 0 ? 'critical' : 'success'}
        />
        <KPIStat
          label="A receber"
          value={formatCurrency(totalReceivable)}
          hint={overdueReceivables > 0 ? `${formatCurrency(overdueReceivables)} vencidos` : 'sem atrasos'}
          tone={overdueReceivables > 0 ? 'critical' : 'success'}
          onClick={() => navigate('/v2/receivables')}
        />
        <KPIStat
          label="A pagar"
          value={formatCurrency(totalPayable)}
          onClick={() => navigate('/financial?tab=payables')}
        />
        <KPIStat
          label="OS concluídas no mês"
          value={String(completedThisMonth)}
          hint={`${formatCurrency(completedThisMonthValue)} faturados`}
        />
      </div>

      {/* Gráfico + próximos 7 dias */}
      <div className="grid grid-cols-1 gap-3 lg:grid-cols-5">
        <div className="rounded-lg border bg-card p-4 lg:col-span-3">
          <h3 className="mb-3 text-sm font-bold">Receita — últimos 6 meses</h3>
          {revenueChart.some((r: { revenue: number }) => r.revenue > 0) ? (
            <>
              <ResponsiveContainer width="100%" height={200}>
                <BarChart data={revenueChart}>
                  <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" vertical={false} />
                  <XAxis dataKey="month" tick={{ fontSize: 12, fill: 'hsl(var(--muted-foreground))' }} axisLine={false} tickLine={false} />
                  <YAxis tickFormatter={(v: number) => `${(v / 1000).toFixed(0)}k`} tick={{ fontSize: 12, fill: 'hsl(var(--muted-foreground))' }} axisLine={false} tickLine={false} width={36} />
                  <Tooltip formatter={(v: number) => formatCurrency(v)} cursor={{ fill: 'hsl(var(--muted))' }} />
                  <Bar dataKey="revenue" radius={[3, 3, 0, 0]}>
                    {revenueChart.map((_: unknown, i: number) => (
                      <Cell key={i} fill={i === revenueChart.length - 1 ? 'hsl(var(--primary))' : 'hsl(var(--primary) / 0.35)'} />
                    ))}
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
              <p className="mt-1 text-xs text-muted-foreground">
                Total no período: <span className="font-semibold text-foreground tabular-nums">{formatCurrency(chartTotal)}</span>
              </p>
            </>
          ) : (
            <p className="py-16 text-center text-sm text-muted-foreground">Nenhuma receita registrada no período.</p>
          )}
        </div>

        <div className="rounded-lg border bg-card lg:col-span-2">
          <div className="flex items-center justify-between border-b px-4 py-2.5">
            <h3 className="text-sm font-bold">Próximos 7 dias</h3>
            <Link to="/agenda" className="flex items-center gap-1 text-xs font-medium text-accent hover:underline">
              Agenda <ArrowRight className="h-3 w-3" />
            </Link>
          </div>
          {(upcomingOrders as UpcomingSO[]).length === 0 ? (
            <p className="p-5 text-center text-sm text-muted-foreground">Nenhuma OS agendada</p>
          ) : (
            (upcomingOrders as UpcomingSO[]).map((so) => (
              <button
                key={so.id}
                type="button"
                onClick={() => navigate(`/v2/service-orders/${so.id}`)}
                className="flex w-full items-center justify-between gap-2 border-b px-4 py-2.5 text-left text-sm transition-colors last:border-0 hover:bg-muted/40"
              >
                <span className="min-w-0 truncate">
                  <b className="text-accent">{so.service_order_number}</b>
                  <span className="text-muted-foreground"> · {so.clients?.name || '—'}</span>
                </span>
                <span className="shrink-0 text-xs text-muted-foreground">
                  {so.scheduled_start_at
                    ? new Date(so.scheduled_start_at).toLocaleDateString('pt-BR', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })
                    : '—'}
                </span>
              </button>
            ))
          )}
        </div>
      </div>

      {/* OS em andamento */}
      <section className="space-y-2">
        <div className="flex items-center justify-between">
          <h3 className="text-sm font-bold">OS em andamento ({openReal.length})</h3>
          <Link to="/v2/service-orders" className="flex items-center gap-1 text-xs font-medium text-accent hover:underline">
            Ver todas <ArrowRight className="h-3 w-3" />
          </Link>
        </div>
        <div className="hidden md:block">
          <DataTable<UpcomingSO>
            rows={openReal}
            rowKey={(so) => so.id}
            columns={openColumns}
            density="compact"
            onRowClick={(so) => navigate(`/v2/service-orders/${so.id}`)}
            emptyMessage="Nenhuma OS em aberto"
          />
        </div>
        <div className="space-y-2.5 md:hidden">
          {openReal.map((so) => (
            <EntityCard
              key={so.id}
              id={so.service_order_number}
              severity={serviceOrderStatusTone[so.status] ?? 'neutral'}
              badge={<StatusChip tone={serviceOrderStatusTone[so.status] ?? 'neutral'}>{statusLabels[so.status] ?? so.status}</StatusChip>}
              title={so.clients?.name || '—'}
              lines={[so.vessels?.name || '—', formatCurrency(so.grand_total || 0)]}
              onClick={() => navigate(`/v2/service-orders/${so.id}`)}
            />
          ))}
        </div>
      </section>
    </>
  );
}

/* ── Home do técnico: "Minhas OS de hoje" ──────────────────────────────────── */

function TechnicianHome() {
  const { t, formatCurrency, formatDate } = useI18n();
  const { user } = useAuth();
  const navigate = useNavigate();
  const { data, isLoading } = useServiceOrders();
  const statusLabels = t.status as Record<string, string>;

  const mine = useMemo(() => {
    const active = ['scheduled', 'open', 'in_progress', 'awaiting_parts', 'awaiting_client', 'approved'];
    const list = ((data ?? []) as unknown as UpcomingSO[])
      .filter((so) => active.includes(so.status))
      .filter((so) => (so.service_order_technicians ?? []).some((x) => x.user_id === user?.id));
    return [...list].sort((a, b) => (a.scheduled_start_at ?? '9999') < (b.scheduled_start_at ?? '9999') ? -1 : 1);
  }, [data, user?.id]);

  const todayList = mine.filter(
    (so) => so.scheduled_start_at && new Date(so.scheduled_start_at).toDateString() === new Date().toDateString(),
  );
  const rest = mine.filter((so) => !todayList.includes(so));

  if (isLoading) {
    return <div className="space-y-2.5">{[1, 2, 3].map((i) => <Skeleton key={i} className="h-28 rounded-lg" />)}</div>;
  }

  const renderCard = (so: UpcomingSO) => (
    <EntityCard
      key={so.id}
      id={so.service_order_number}
      severity={so.priority === 'urgent' ? 'critical' : (serviceOrderStatusTone[so.status] ?? 'neutral')}
      badge={
        <>
          <StatusChip tone={serviceOrderStatusTone[so.status] ?? 'neutral'}>{statusLabels[so.status] ?? so.status}</StatusChip>
          {so.priority === 'urgent' && <StatusChip tone="critical">{(t.priority as Record<string, string>).urgent}</StatusChip>}
        </>
      }
      title={so.clients?.name || '—'}
      lines={[
        so.vessels?.name || '—',
        so.scheduled_start_at
          ? new Date(so.scheduled_start_at).toLocaleDateString('pt-BR', { weekday: 'short', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })
          : `Sem agendamento · ${formatCurrency(so.grand_total || 0)}`,
      ]}
      actions={<Button className="flex-1" onClick={() => navigate(`/v2/service-orders/${so.id}`)}>Abrir OS</Button>}
    />
  );

  return (
    <>
      <section className="space-y-2.5">
        <h2 className="flex items-center gap-2 text-sm font-bold">
          <CalendarDays className="h-4 w-4 text-primary" /> Minhas OS de hoje
          <span className="text-muted-foreground tabular-nums">{todayList.length}</span>
        </h2>
        {todayList.length === 0 ? (
          <p className="rounded-lg border bg-card p-6 text-center text-sm text-muted-foreground">
            Nenhuma OS agendada para hoje. {formatDate(new Date().toISOString())}
          </p>
        ) : (
          <div className="grid grid-cols-1 gap-2.5 sm:grid-cols-2 lg:grid-cols-3">{todayList.map(renderCard)}</div>
        )}
      </section>
      {rest.length > 0 && (
        <section className="space-y-2.5">
          <h2 className="flex items-center gap-2 text-sm font-bold">
            <Package className="h-4 w-4 text-muted-foreground" /> Próximas atribuídas a mim
            <span className="text-muted-foreground tabular-nums">{rest.length}</span>
          </h2>
          <div className="grid grid-cols-1 gap-2.5 sm:grid-cols-2 lg:grid-cols-3">{rest.slice(0, 9).map(renderCard)}</div>
        </section>
      )}
      <Link to="/agenda" className="inline-flex items-center gap-1 text-sm font-medium text-accent hover:underline">
        Ver agenda completa <ArrowRight className="h-3.5 w-3.5" />
      </Link>
    </>
  );
}
