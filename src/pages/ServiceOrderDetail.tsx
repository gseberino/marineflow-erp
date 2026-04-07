import { useParams, Link } from 'react-router-dom';
import { useI18n } from '@/i18n';
import { serviceOrders, getClient, getVessel, getMarina, getUser, getPartsForOrder, getTimeEntriesForOrder, getProduct } from '@/data/mock-data';
import { statusConfig, priorityConfig } from '@/lib/constants';
import { StatusBadge } from '@/components/StatusBadge';
import { Button } from '@/components/ui/button';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { ArrowLeft, Clock, MapPin, Wrench, DollarSign, Camera, Play, CheckCircle, Upload, Plus } from 'lucide-react';

export default function ServiceOrderDetail() {
  const { id } = useParams<{ id: string }>();
  const { t, formatCurrency, formatDate, formatDateTime } = useI18n();
  const order = serviceOrders.find(so => so.id === id);

  if (!order) return (
    <div className="flex flex-col items-center justify-center py-20">
      <p className="text-muted-foreground">{t.serviceOrders.notFound}</p>
      <Link to="/service-orders" className="text-accent hover:underline mt-2">{t.serviceOrders.backToList}</Link>
    </div>
  );

  const client = getClient(order.client_id);
  const vessel = getVessel(order.vessel_id);
  const marina = order.marina_id ? getMarina(order.marina_id) : undefined;
  const parts = getPartsForOrder(order.id);
  const timeEntries = getTimeEntriesForOrder(order.id);
  const sc = statusConfig[order.status];
  const pc = priorityConfig[order.priority];

  const InfoRow = ({ label, value }: { label: string; value?: string | number | null }) => (
    <div className="flex justify-between py-2 border-b border-border/50 last:border-0">
      <span className="text-sm text-muted-foreground">{label}</span>
      <span className="text-sm font-medium text-right max-w-[60%]">{value || '—'}</span>
    </div>
  );

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex items-center gap-3">
        <Link to="/service-orders" className="rounded-lg p-1.5 hover:bg-muted transition-colors">
          <ArrowLeft className="h-5 w-5" />
        </Link>
        <div className="flex-1">
          <div className="flex items-center gap-3 flex-wrap">
            <h1 className="text-2xl font-bold">{order.service_order_number}</h1>
            <StatusBadge className={sc.className}>{(t.status as Record<string, string>)[order.status]}</StatusBadge>
            <span className={pc.className + ' text-sm'}>{(t.priority as Record<string, string>)[order.priority]} {t.serviceOrders.prioritySuffix}</span>
          </div>
          <p className="text-sm text-muted-foreground mt-1">{(t.serviceType as Record<string, string>)[order.service_type]} • {client?.full_name_or_company_name} • {vessel?.boat_name}</p>
        </div>
        <div className="hidden sm:flex gap-2">
          <Button variant="outline" size="sm" className="gap-1"><Play className="h-3 w-3" /> {t.serviceOrders.startTimer}</Button>
          <Button variant="outline" size="sm" className="gap-1"><Camera className="h-3 w-3" /> {t.serviceOrders.addPhoto}</Button>
          <Button size="sm" className="gap-1 bg-accent text-accent-foreground hover:bg-accent/90"><CheckCircle className="h-3 w-3" /> {t.serviceOrders.complete}</Button>
        </div>
      </div>

      <div className="grid grid-cols-2 sm:hidden gap-2">
        <Button variant="outline" size="sm" className="gap-1"><Play className="h-3 w-3" /> {t.serviceOrders.startTimer}</Button>
        <Button variant="outline" size="sm" className="gap-1"><Camera className="h-3 w-3" /> {t.serviceOrders.addPhoto}</Button>
        <Button variant="outline" size="sm" className="gap-1"><Upload className="h-3 w-3" /> {t.serviceOrders.addPart}</Button>
        <Button size="sm" className="gap-1 bg-accent text-accent-foreground hover:bg-accent/90"><CheckCircle className="h-3 w-3" /> {t.serviceOrders.complete}</Button>
      </div>

      <Tabs defaultValue="overview" className="space-y-4">
        <TabsList className="flex-wrap h-auto gap-1">
          <TabsTrigger value="overview">{t.serviceOrders.tabOverview}</TabsTrigger>
          <TabsTrigger value="technical">{t.serviceOrders.tabTechnical}</TabsTrigger>
          <TabsTrigger value="team">{t.serviceOrders.tabTeam}</TabsTrigger>
          <TabsTrigger value="parts">{t.serviceOrders.tabParts}</TabsTrigger>
          <TabsTrigger value="financial">{t.serviceOrders.tabFinancial}</TabsTrigger>
          <TabsTrigger value="files">{t.serviceOrders.tabFiles}</TabsTrigger>
        </TabsList>

        <TabsContent value="overview" className="space-y-4">
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <div className="rounded-xl border bg-card p-5 shadow-sm">
              <h3 className="text-sm font-semibold mb-3">{t.serviceOrders.clientAndVessel}</h3>
              <InfoRow label={t.serviceOrders.client} value={client?.full_name_or_company_name} />
              <InfoRow label={t.serviceOrders.requestedBy} value={order.requested_by_name} />
              <InfoRow label={t.serviceOrders.vessel} value={vessel ? `${vessel.boat_name} (${vessel.manufacturer} ${vessel.model})` : undefined} />
              <InfoRow label={t.serviceOrders.marina} value={marina?.marina_name} />
              <InfoRow label={t.serviceOrders.dockPosition} value={vessel?.current_dock_position} />
            </div>
            <div className="rounded-xl border bg-card p-5 shadow-sm">
              <h3 className="text-sm font-semibold mb-3">{t.serviceOrders.schedule}</h3>
              <InfoRow label={t.serviceOrders.scheduledStart} value={order.scheduled_start_at ? formatDateTime(order.scheduled_start_at) : undefined} />
              <InfoRow label={t.serviceOrders.scheduledEnd} value={order.scheduled_end_at ? formatDateTime(order.scheduled_end_at) : undefined} />
              <InfoRow label={t.serviceOrders.checkIn} value={order.check_in_at ? formatDateTime(order.check_in_at) : undefined} />
              <InfoRow label={t.serviceOrders.checkOut} value={order.check_out_at ? formatDateTime(order.check_out_at) : undefined} />
              <InfoRow label={t.common.created} value={formatDate(order.created_at)} />
            </div>
          </div>
          <div className="rounded-xl border bg-card p-5 shadow-sm">
            <h3 className="text-sm font-semibold mb-3">{t.serviceOrders.problemDescription}</h3>
            <p className="text-sm leading-relaxed">{order.problem_description}</p>
          </div>
        </TabsContent>

        <TabsContent value="technical" className="space-y-4">
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <div className="rounded-xl border bg-card p-5 shadow-sm">
              <h3 className="text-sm font-semibold mb-3">{t.serviceOrders.initialFindings}</h3>
              <p className="text-sm leading-relaxed text-muted-foreground">{order.initial_findings || t.serviceOrders.noFindingsYet}</p>
            </div>
            <div className="rounded-xl border bg-card p-5 shadow-sm">
              <h3 className="text-sm font-semibold mb-3">{t.serviceOrders.diagnosis}</h3>
              <p className="text-sm leading-relaxed">{order.diagnosis || t.serviceOrders.pendingDiagnosis}</p>
            </div>
          </div>
          {order.solution_applied && (
            <div className="rounded-xl border bg-card p-5 shadow-sm">
              <h3 className="text-sm font-semibold mb-3">{t.serviceOrders.solutionApplied}</h3>
              <p className="text-sm leading-relaxed">{order.solution_applied}</p>
            </div>
          )}
        </TabsContent>

        <TabsContent value="team" className="space-y-4">
          <div className="rounded-xl border bg-card p-5 shadow-sm">
            <h3 className="text-sm font-semibold mb-4">{t.serviceOrders.timeEntries}</h3>
            {timeEntries.length === 0 ? (
              <p className="text-sm text-muted-foreground">{t.serviceOrders.noTimeEntries}</p>
            ) : (
              <div className="space-y-3">
                {timeEntries.map(te => {
                  const tech = getUser(te.technician_user_id);
                  return (
                    <div key={te.id} className="flex items-start justify-between p-3 rounded-lg bg-muted/50 border">
                      <div>
                        <p className="text-sm font-medium">{tech?.full_name}</p>
                        <p className="text-xs text-muted-foreground">{te.notes}</p>
                        <p className="text-xs text-muted-foreground mt-1">{formatDateTime(te.started_at)} → {te.ended_at ? formatDateTime(te.ended_at) : t.common.loading}</p>
                      </div>
                      <div className="text-right">
                        <p className="text-sm font-semibold">{(te.duration_minutes / 60).toFixed(1)}h</p>
                        <StatusBadge className={te.billable ? 'bg-success/15 text-success' : 'bg-muted text-muted-foreground'}>
                          {te.billable ? t.serviceOrders.billable : t.serviceOrders.nonBillable}
                        </StatusBadge>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        </TabsContent>

        <TabsContent value="parts" className="space-y-4">
          <div className="rounded-xl border bg-card shadow-sm overflow-hidden">
            <div className="p-5 border-b flex items-center justify-between">
              <h3 className="text-sm font-semibold">{t.serviceOrders.partsUsed}</h3>
              <Button variant="outline" size="sm" className="gap-1"><Plus className="h-3 w-3" /> {t.serviceOrders.addPart}</Button>
            </div>
            {parts.length === 0 ? (
              <p className="text-sm text-muted-foreground p-5">{t.serviceOrders.noPartsYet}</p>
            ) : (
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b bg-muted/50">
                    <th className="px-4 py-2 text-left font-medium text-muted-foreground">{t.serviceOrders.product}</th>
                    <th className="px-4 py-2 text-center font-medium text-muted-foreground">{t.serviceOrders.qty}</th>
                    <th className="px-4 py-2 text-right font-medium text-muted-foreground">{t.serviceOrders.unitPrice}</th>
                    <th className="px-4 py-2 text-right font-medium text-muted-foreground">{t.common.total}</th>
                  </tr>
                </thead>
                <tbody>
                  {parts.map(part => {
                    const product = getProduct(part.product_id);
                    return (
                      <tr key={part.id} className="border-b last:border-0">
                        <td className="px-4 py-3">
                          <p className="font-medium">{product?.product_name}</p>
                          {part.notes && <p className="text-xs text-muted-foreground">{part.notes}</p>}
                        </td>
                        <td className="px-4 py-3 text-center">{part.quantity}</td>
                        <td className="px-4 py-3 text-right">{formatCurrency(part.unit_sale_snapshot)}</td>
                        <td className="px-4 py-3 text-right font-semibold">{formatCurrency(part.line_total_sale)}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            )}
          </div>
        </TabsContent>

        <TabsContent value="financial" className="space-y-4">
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <div className="rounded-xl border bg-card p-5 shadow-sm">
              <h3 className="text-sm font-semibold mb-3">{t.serviceOrders.costBreakdown}</h3>
              <InfoRow label={t.serviceOrders.labor} value={`${order.labor_hours_total}h × ${formatCurrency(order.hourly_rate)} = ${formatCurrency(order.labor_cost_total)}`} />
              <InfoRow label={t.serviceOrders.parts} value={formatCurrency(order.parts_cost_total)} />
              <InfoRow label={t.serviceOrders.travel} value={formatCurrency(order.travel_cost_total)} />
              <InfoRow label={t.serviceOrders.subcontract} value={formatCurrency(order.subcontract_cost_total)} />
              <InfoRow label={t.serviceOrders.discount} value={order.discount_amount > 0 ? `-${formatCurrency(order.discount_amount)}` : '—'} />
              <InfoRow label={t.serviceOrders.tax} value={formatCurrency(order.tax_amount)} />
              <div className="flex justify-between pt-3 mt-2 border-t-2">
                <span className="font-semibold">{t.serviceOrders.grandTotal}</span>
                <span className="text-lg font-bold text-accent">{formatCurrency(order.grand_total)}</span>
              </div>
            </div>
            <div className="rounded-xl border bg-card p-5 shadow-sm">
              <h3 className="text-sm font-semibold mb-3">{t.serviceOrders.travelCalculation}</h3>
              <InfoRow label={t.serviceOrders.origin} value="NautiTech Base, Rio de Janeiro" />
              <InfoRow label={t.serviceOrders.destination} value={marina?.marina_name || '—'} />
              <InfoRow label={t.serviceOrders.distance} value={`${order.travel_distance_km} km`} />
              <InfoRow label={t.serviceOrders.rate} value={`${formatCurrency(order.travel_cost_per_km)} / km`} />
              <InfoRow label={t.serviceOrders.technicians} value={String(order.technician_count_for_travel)} />
              <InfoRow label={t.serviceOrders.formula} value={`${order.travel_distance_km} × ${order.travel_cost_per_km} × ${order.technician_count_for_travel}`} />
              <div className="flex justify-between pt-3 mt-2 border-t-2">
                <span className="font-semibold">{t.serviceOrders.travelTotal}</span>
                <span className="font-bold">{formatCurrency(order.travel_cost_total)}</span>
              </div>
            </div>
          </div>
        </TabsContent>

        <TabsContent value="files" className="space-y-4">
          <div className="rounded-xl border bg-card p-5 shadow-sm">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-sm font-semibold">{t.serviceOrders.photosAndDocs}</h3>
              <Button variant="outline" size="sm" className="gap-1"><Upload className="h-3 w-3" /> {t.serviceOrders.upload}</Button>
            </div>
            <div className="flex flex-col items-center justify-center py-12 text-muted-foreground border-2 border-dashed rounded-lg">
              <Camera className="h-8 w-8 mb-2" />
              <p className="text-sm">{t.serviceOrders.noFilesYet}</p>
              <p className="text-xs">{t.serviceOrders.dragAndDrop}</p>
            </div>
          </div>
        </TabsContent>
      </Tabs>
    </div>
  );
}
