import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Moon, Sun, ExternalLink, MessageCircle, MoreHorizontal } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useI18n } from '@/i18n';
import { Button } from '@/components/ui/button';
import { PageShell } from '@/v2/components/PageShell';
import { KPIStat } from '@/v2/components/KPIStat';
import { StatusChip, type StatusTone } from '@/v2/components/StatusChip';
import { serviceOrderStatusTone, priorityTone } from '@/v2/status-map';
import { EntityCard } from '@/v2/components/EntityCard';
import { DataTable, type DataColumn, type Density } from '@/v2/components/DataTable';
import '@/v2/tokens.css';

/* ─────────────────────────────────────────────────────────────────────────────
   MarineFlow v2 — Preview do kit (Fase 0)
   Direção aprovada 23/07/2026: "Estaleiro Claro" (light) + "Ponte de Comando" (dark).
   SOMENTE LEITURA: nenhuma mutação; dados reais apenas para calibrar densidade.
──────────────────────────────────────────────────────────────────────────── */

type PreviewSO = {
  id: string;
  service_order_number: string;
  status: string;
  priority: string | null;
  service_type: string | null;
  grand_total: number | null;
  scheduled_start_at: string | null;
  clients: { name: string } | null;
  vessels: { name: string } | null;
};

export default function DesignPreviewV2() {
  const [mode, setMode] = useState<'light' | 'dark'>('light');
  const [density, setDensity] = useState<Density>('regular');
  const { formatCurrency, formatDate, t } = useI18n();
  const statusLabels = t.status as Record<string, string>;

  const { data: orders = [], isLoading } = useQuery({
    queryKey: ['v2-preview-service-orders'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('service_orders')
        .select('id, service_order_number, status, priority, service_type, grand_total, scheduled_start_at, clients(name), vessels(name)')
        .neq('status', 'draft')
        .order('created_at', { ascending: false })
        .limit(8);
      if (error) throw error;
      return (data ?? []) as unknown as PreviewSO[];
    },
    staleTime: 60_000,
  });

  const columns: DataColumn<PreviewSO>[] = [
    {
      key: 'number',
      header: 'OS',
      minWidth: 120,
      priority: 0,
      render: (so) => <span className="font-bold text-accent">{so.service_order_number}</span>,
    },
    {
      key: 'client',
      header: 'Cliente · Embarcação',
      minWidth: 220,
      priority: 1,
      detailLabel: 'Cliente',
      render: (so) => (
        <span className="block leading-tight">
          <span className="block truncate font-semibold">{so.clients?.name || '—'}</span>
          <span className="block truncate text-xs text-muted-foreground">
            {[so.vessels?.name, so.service_type].filter(Boolean).join(' · ') || '—'}
          </span>
        </span>
      ),
    },
    {
      key: 'status',
      header: 'Status',
      minWidth: 170,
      priority: 2,
      detailLabel: 'Status',
      render: (so) => (
        <span className="inline-flex flex-wrap items-center gap-1">
          <StatusChip dot tone={serviceOrderStatusTone[so.status] ?? 'neutral'}>
            {statusLabels[so.status] ?? so.status}
          </StatusChip>
          {(so.priority === 'urgent' || so.priority === 'high') && (
            <StatusChip tone={priorityTone[so.priority]}>
              {(t.priority as Record<string, string>)[so.priority] ?? so.priority}
            </StatusChip>
          )}
        </span>
      ),
    },
    {
      key: 'scheduled',
      header: 'Agendada',
      minWidth: 110,
      priority: 3,
      detailLabel: 'Agendada',
      render: (so) => (so.scheduled_start_at ? formatDate(so.scheduled_start_at) : '—'),
    },
    {
      key: 'total',
      header: 'Total',
      minWidth: 120,
      priority: 2,
      align: 'right',
      detailLabel: 'Total',
      render: (so) => <span className="font-semibold">{formatCurrency(so.grand_total || 0)}</span>,
    },
  ];

  const chipTones: StatusTone[] = ['info', 'success', 'warning', 'critical', 'neutral'];

  return (
    <div className="themev2 min-h-screen bg-background text-foreground transition-colors" data-mode={mode}>
      <div className="mx-auto max-w-5xl space-y-10 px-4 py-8 lg:px-8">
        {/* Barra do preview */}
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-lg border bg-card px-4 py-3">
          <div>
            <p className="text-sm font-bold">MarineFlow v2 — Preview do kit (Fase 0)</p>
            <p className="text-xs text-muted-foreground">
              Somente leitura · dados reais · direção aprovada: Estaleiro Claro ☀ + Ponte de Comando 🌙
            </p>
          </div>
          <div className="flex items-center gap-2">
            <Button
              variant={mode === 'light' ? 'default' : 'outline'}
              size="sm"
              onClick={() => setMode('light')}
              className="gap-1.5"
            >
              <Sun className="h-4 w-4" /> Claro
            </Button>
            <Button
              variant={mode === 'dark' ? 'default' : 'outline'}
              size="sm"
              onClick={() => setMode('dark')}
              className="gap-1.5"
            >
              <Moon className="h-4 w-4" /> Escuro
            </Button>
          </div>
        </div>

        {/* PageShell + KPIStat */}
        <PageShell
          breadcrumb={[{ label: 'Operacional', to: '/' }, { label: 'Ordens de Serviço' }]}
          title="Ordens de Serviço"
          count={orders.length}
          actions={<Button className="gap-1.5">+ Nova OS</Button>}
        >
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <KPIStat label="Recebido no mês" value={formatCurrency(86400)} hint="▲ 12% vs mês anterior" tone="success" />
            <KPIStat label="A receber" value={formatCurrency(42150)} hint={`${formatCurrency(8420)} vencidos`} tone="critical" onClick={() => {}} />
            <KPIStat label="A pagar" value={formatCurrency(27900)} hint="próx. 30 dias" />
            <KPIStat label="OS concluídas no mês" value="18" hint={formatCurrency(61300) + ' faturados'} />
          </div>

          {/* Controle de densidade do preview */}
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Densidade</span>
            {(['compact', 'regular', 'relaxed'] as Density[]).map((d) => (
              <Button
                key={d}
                size="sm"
                variant={density === d ? 'secondary' : 'ghost'}
                onClick={() => setDensity(d)}
              >
                {d === 'compact' ? 'Compacta' : d === 'regular' ? 'Normal' : 'Confortável'}
              </Button>
            ))}
            <span className="ml-auto text-xs text-muted-foreground">
              Estreite a janela: as colunas que não cabem vão para a linha expansível ▸ — nada rola para o lado.
            </span>
          </div>

          {/* DataTable universal com dados reais (read-only) */}
          <DataTable
            rows={orders}
            rowKey={(so) => so.id}
            columns={columns}
            density={density}
            selectable
            isLoading={isLoading}
            rowActions={() => (
              <>
                <Button variant="ghost" size="icon" className="h-8 w-8" aria-label="Enviar por WhatsApp" title="Enviar por WhatsApp">
                  <MessageCircle className="h-4 w-4" />
                </Button>
                <Button variant="ghost" size="icon" className="h-8 w-8" aria-label="Abrir" title="Abrir">
                  <ExternalLink className="h-4 w-4" />
                </Button>
                <Button variant="ghost" size="icon" className="h-8 w-8" aria-label="Mais ações" title="Mais ações">
                  <MoreHorizontal className="h-4 w-4" />
                </Button>
              </>
            )}
            bulkBar={(keys, clear) => (
              <>
                <span className="font-semibold">{keys.length} selecionada{keys.length > 1 ? 's' : ''}</span>
                <Button size="sm" variant="secondary">Baixar PDF</Button>
                <Button size="sm" variant="secondary">Enviar WhatsApp</Button>
                <button className="ml-auto text-xs underline-offset-2 hover:underline" onClick={clear}>
                  Cancelar seleção
                </button>
              </>
            )}
          />
        </PageShell>

        {/* EntityCard — padrão mobile */}
        <section className="space-y-3">
          <h2 className="text-lg font-bold tracking-tight">EntityCard — padrão mobile (abaixo de md)</h2>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {orders.slice(0, 3).map((so) => (
              <EntityCard
                key={so.id}
                id={so.service_order_number}
                severity={so.priority === 'urgent' ? 'critical' : serviceOrderStatusTone[so.status] ?? 'neutral'}
                badge={
                  <StatusChip tone={serviceOrderStatusTone[so.status] ?? 'neutral'}>
                    {statusLabels[so.status] ?? so.status}
                  </StatusChip>
                }
                title={so.clients?.name || '—'}
                lines={[
                  [so.vessels?.name, so.service_type].filter(Boolean).join(' · ') || '—',
                  so.scheduled_start_at ? formatDate(so.scheduled_start_at) : 'Sem agendamento',
                ]}
                actions={
                  <>
                    <Button className="flex-1">Abrir OS</Button>
                    <Button variant="outline" size="icon" aria-label="Enviar por WhatsApp" className="h-11 w-11">
                      <MessageCircle className="h-4 w-4" />
                    </Button>
                  </>
                }
              />
            ))}
          </div>
        </section>

        {/* Galeria de StatusChip */}
        <section className="space-y-3">
          <h2 className="text-lg font-bold tracking-tight">StatusChip — mapa semântico único</h2>
          <div className="flex flex-wrap gap-2 rounded-lg border bg-card p-4">
            {chipTones.map((tone) => (
              <StatusChip key={tone} dot tone={tone}>
                {tone === 'info' ? 'Em andamento' : tone === 'success' ? 'Concluída · Pago' : tone === 'warning' ? 'Aguard. peças' : tone === 'critical' ? 'Vencido · 8d' : 'Rascunho'}
              </StatusChip>
            ))}
          </div>
        </section>
      </div>
    </div>
  );
}
