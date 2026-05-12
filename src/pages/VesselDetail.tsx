import { useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { useI18n } from '@/i18n';
import { useVessel } from '@/hooks/use-vessels';
import { statusConfig } from '@/lib/constants';
import { StatusBadge } from '@/components/StatusBadge';
import { Skeleton } from '@/components/ui/skeleton';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Button } from '@/components/ui/button';
import { ArrowLeft, Ship, Anchor, Battery, Radio, Zap, Edit } from 'lucide-react';
import { VesselFormDialog } from '@/components/VesselFormDialog';
import { RecordHistory } from '@/components/RecordHistory';
import { supabase } from '@/integrations/supabase/client';
import { useQuery } from '@tanstack/react-query';

export default function VesselDetail() {
  const { id } = useParams<{ id: string }>();
  const { t, formatCurrency, formatDate } = useI18n();
  const { data: vessel, isLoading } = useVessel(id);
  const [editOpen, setEditOpen] = useState(false);

  const { data: orders } = useQuery({
    queryKey: ['service-orders', 'vessel', id],
    queryFn: async () => {
      if (!id) return [];
      const { data, error } = await supabase
        .from('service_orders')
        .select('*, service_order_parts(id, products(product_name), quantity, warranty_days), service_order_services(id, name_snapshot, quantity, warranty_days)')
        .eq('vessel_id', id)
        .order('created_at', { ascending: false });
      if (error) throw error;
      return data;
    },
    enabled: !!id,
  });

  if (isLoading) return (
    <div className="space-y-6">
      <Skeleton className="h-10 w-64" />
      <Skeleton className="h-64 rounded-xl" />
    </div>
  );

  if (!vessel) return (
    <div className="py-20 text-center text-muted-foreground">
      {t.vessels.notFound} <Link to="/vessels" className="text-accent hover:underline">← {t.common.back}</Link>
    </div>
  );

  const clientName = (vessel as any).clients?.name ?? '—';
  const marinaName = (vessel as any).marinas?.name;

  const InfoRow = ({ label, value }: { label: string; value?: string | number | null }) => (
    <div className="flex justify-between py-2 border-b border-border/50 last:border-0">
      <span className="text-sm text-muted-foreground">{label}</span>
      <span className="text-sm font-medium text-right max-w-[60%]">{value || '—'}</span>
    </div>
  );

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex items-center gap-3">
        <Link to="/vessels" className="rounded-lg p-1.5 hover:bg-muted transition-colors"><ArrowLeft className="h-5 w-5" /></Link>
        <div className="flex-1">
          <h1 className="text-2xl font-bold flex items-center gap-2"><Ship className="h-6 w-6 text-accent" />{vessel.boat_name}</h1>
          <p className="text-sm text-muted-foreground">
            {vessel.manufacturer} {vessel.model} {vessel.year ? `(${vessel.year})` : ''} • {vessel.length_feet ? `${vessel.length_feet} ft` : ''} • {t.vessels.owner}: {clientName}
          </p>
        </div>
        <Button variant="outline" size="sm" onClick={() => setEditOpen(true)}>
          <Edit className="h-4 w-4 mr-1" /> {t.common.edit}
        </Button>
      </div>

      <Tabs defaultValue="overview">
        <TabsList>
          <TabsTrigger value="overview">{t.common.overview}</TabsTrigger>
          <TabsTrigger value="technical">{t.vessels.technicalProfile}</TabsTrigger>
          <TabsTrigger value="history">{t.vessels.serviceHistory}</TabsTrigger>
          <TabsTrigger value="audit">Histórico de Edições</TabsTrigger>
        </TabsList>

        <TabsContent value="overview" className="mt-4 grid grid-cols-1 lg:grid-cols-2 gap-4">
          <div className="rounded-xl border bg-card p-5 shadow-sm">
            <h3 className="text-sm font-semibold mb-3 flex items-center gap-2"><Ship className="h-4 w-4" /> {t.vessels.hullAndSpecs}</h3>
            <InfoRow label={t.vessels.hullId} value={vessel.hull_id_or_registration} />
            <InfoRow label={t.vessels.length} value={vessel.length_feet ? `${vessel.length_feet} ft` : undefined} />
            <InfoRow label={t.vessels.beam} value={vessel.beam_feet ? `${vessel.beam_feet} ft` : undefined} />
            <InfoRow label={t.vessels.draft} value={vessel.draft_feet ? `${vessel.draft_feet} ft` : undefined} />
            <InfoRow label={t.vessels.propulsion} value={vessel.propulsion_type} />
          </div>
          <div className="rounded-xl border bg-card p-5 shadow-sm">
            <h3 className="text-sm font-semibold mb-3 flex items-center gap-2"><Anchor className="h-4 w-4" /> {t.vessels.location}</h3>
            <InfoRow label={t.serviceOrders.marina} value={marinaName} />
            <InfoRow label={t.serviceOrders.dockPosition} value={vessel.current_dock_position} />
            <InfoRow label={t.vessels.owner} value={clientName} />
            <InfoRow label={t.vessels.shorePower} value={vessel.shore_power_type} />
          </div>
        </TabsContent>

        <TabsContent value="technical" className="mt-4 space-y-4">
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <div className="rounded-xl border bg-card p-5 shadow-sm">
              <h3 className="text-sm font-semibold mb-3 flex items-center gap-2"><Zap className="h-4 w-4" /> {t.vessels.engines}</h3>
              <InfoRow label={t.common.type} value={vessel.engine_type} />
              <InfoRow label={t.products.brand} value={vessel.engine_brand} />
              <InfoRow label={t.vessels.model} value={vessel.engine_model} />
              <InfoRow label={t.serviceOrders.qty} value={vessel.engine_quantity} />
            </div>
            <div className="rounded-xl border bg-card p-5 shadow-sm">
              <h3 className="text-sm font-semibold mb-3 flex items-center gap-2"><Battery className="h-4 w-4" /> {t.vessels.powerSystems}</h3>
              <InfoRow label={t.vessels.batteryBank} value={vessel.battery_bank_summary} />
              <InfoRow label={t.vessels.inverterCharger} value={vessel.inverter_charger_summary} />
              <InfoRow label={t.vessels.shorePower} value={vessel.shore_power_type} />
            </div>
          </div>
          <div className="rounded-xl border bg-card p-5 shadow-sm">
            <h3 className="text-sm font-semibold mb-3 flex items-center gap-2"><Radio className="h-4 w-4" /> {t.vessels.navigationElectronics}</h3>
            <p className="text-sm leading-relaxed">{vessel.navigation_electronics_summary || t.vessels.noNavElectronics}</p>
          </div>
          {vessel.electrical_system_notes && (
            <div className="rounded-xl border bg-card p-5 shadow-sm">
              <h3 className="text-sm font-semibold mb-3">{t.vessels.electricalSystemNotes}</h3>
              <p className="text-sm leading-relaxed text-muted-foreground">{vessel.electrical_system_notes}</p>
            </div>
          )}
        </TabsContent>

        <TabsContent value="history" className="mt-4">
          {orders && orders.length > 0 && (
            <div className="flex gap-4 mb-4 text-sm">
              <div className="rounded-lg border bg-card px-4 py-2">
                <span className="text-muted-foreground">OS: </span>
                <strong>{orders.length}</strong>
              </div>
              <div className="rounded-lg border bg-card px-4 py-2">
                <span className="text-muted-foreground">Total gasto: </span>
                <strong>{formatCurrency(orders.reduce((s, o: any) => s + (o.grand_total ?? 0), 0))}</strong>
              </div>
              <div className="rounded-lg border bg-card px-4 py-2">
                <span className="text-muted-foreground">Concluídas: </span>
                <strong>{orders.filter((o: any) => o.status === 'completed').length}</strong>
              </div>
            </div>
          )}
          <div className="space-y-8 pl-4 border-l-2 border-border/50 relative py-4">
            {(!orders || orders.length === 0) && (
              <div className="text-center py-12 text-muted-foreground bg-card rounded-xl border border-dashed">
                {t.vessels.noServiceHistory}
              </div>
            )}
            {(orders ?? []).map((o: any) => (
              <div key={o.id} className="relative pl-6">
                {/* Timeline dot */}
                <div className="absolute -left-[29px] top-1 h-4 w-4 rounded-full border-4 border-background bg-accent ring-1 ring-border/50" />
                
                <div className="bg-card border rounded-xl p-5 shadow-sm transition-all hover:shadow-md">
                  <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 mb-4 border-b pb-3">
                    <div>
                      <Link to={`/service-orders/${o.id}`} className="text-lg font-bold text-accent hover:underline flex items-center gap-2">
                        {o.service_order_number}
                        {o.service_type && (
                          <span className="text-xs font-normal px-2 py-0.5 bg-muted rounded-full text-foreground">
                            {(t.serviceType as Record<string, string>)[o.service_type] ?? o.service_type}
                          </span>
                        )}
                      </Link>
                      <p className="text-xs text-muted-foreground mt-1 font-medium">{formatDate(o.created_at)}</p>
                    </div>
                    <div className="flex items-center gap-3">
                      <StatusBadge className={statusConfig[o.status as keyof typeof statusConfig]?.className ?? ''}>
                        {(t.status as Record<string, string>)[o.status] ?? o.status}
                      </StatusBadge>
                      <div className="text-right">
                        <p className="text-sm font-bold">{formatCurrency(o.grand_total ?? 0)}</p>
                      </div>
                    </div>
                  </div>

                  {o.problem_description && (
                    <div className="mb-4">
                      <p className="text-sm text-muted-foreground leading-relaxed">{o.problem_description}</p>
                    </div>
                  )}

                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    {/* Services */}
                    {o.service_order_services && o.service_order_services.length > 0 && (
                      <div className="bg-muted/30 rounded-lg p-3 border border-border/50">
                        <h4 className="text-xs font-semibold mb-2 flex items-center gap-1.5">
                          <Zap className="h-3.5 w-3.5" /> Serviços Realizados ({o.service_order_services.length})
                        </h4>
                        <ul className="space-y-1.5">
                          {o.service_order_services.map((s: any) => (
                            <li key={s.id} className="text-xs text-muted-foreground flex justify-between items-start">
                              <div className="min-w-0 pr-2">
                                <span className="block truncate">• {s.name_snapshot}</span>
                                {s.warranty_days > 0 && (
                                  <span className="text-[9px] text-accent font-semibold flex items-center gap-0.5">
                                    <Zap className="h-2 w-2" /> Garantia: {s.warranty_days} dias
                                  </span>
                                )}
                              </div>
                              <span className="shrink-0 font-medium">x{s.quantity}</span>
                            </li>
                          ))}
                        </ul>
                      </div>
                    )}
                    
                    {/* Parts */}
                    {o.service_order_parts && o.service_order_parts.length > 0 && (
                      <div className="bg-muted/30 rounded-lg p-3 border border-border/50">
                        <h4 className="text-xs font-semibold mb-2 flex items-center gap-1.5">
                          <Anchor className="h-3.5 w-3.5" /> Peças Trocadas ({o.service_order_parts.length})
                        </h4>
                        <ul className="space-y-1.5">
                          {o.service_order_parts.map((p: any) => (
                            <li key={p.id} className="text-xs text-muted-foreground flex justify-between items-start">
                              <div className="min-w-0 pr-2">
                                <span className="block truncate">• {p.products?.product_name || 'Produto sem nome'}</span>
                                {p.warranty_days > 0 && (
                                  <span className="text-[9px] text-accent font-semibold flex items-center gap-0.5">
                                    <Anchor className="h-2 w-2" /> Garantia: {p.warranty_days} dias
                                  </span>
                                )}
                              </div>
                              <span className="shrink-0 font-medium">x{p.quantity}</span>
                            </li>
                          ))}
                        </ul>
                      </div>
                    )}
                  </div>

                  {(!o.service_order_services?.length && !o.service_order_parts?.length && !o.problem_description) && (
                    <p className="text-xs text-muted-foreground italic">Nenhum detalhe adicional registrado nesta OS.</p>
                  )}
                </div>
              </div>
            ))}
          </div>
        </TabsContent>
        <TabsContent value="audit" className="mt-4">
          <div className="rounded-xl border bg-card shadow-sm p-4">
            <RecordHistory tableName="vessels" recordId={id} />
          </div>
        </TabsContent>
      </Tabs>

      <VesselFormDialog open={editOpen} onOpenChange={setEditOpen} vessel={vessel} />
    </div>
  );
}
