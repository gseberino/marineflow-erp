import { useParams, Link } from 'react-router-dom';
import { useI18n } from '@/i18n';
import { vessels, getClient, getMarina, getServiceOrdersForVessel } from '@/data/mock-data';
import { statusConfig } from '@/lib/constants';
import { StatusBadge } from '@/components/StatusBadge';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { ArrowLeft, Ship, Anchor, Battery, Radio, Zap } from 'lucide-react';

export default function VesselDetail() {
  const { id } = useParams<{ id: string }>();
  const { t, formatCurrency, formatDate } = useI18n();
  const vessel = vessels.find(v => v.id === id);
  if (!vessel) return <div className="py-20 text-center text-muted-foreground">{t.vessels.notFound} <Link to="/vessels" className="text-accent hover:underline">← {t.common.back}</Link></div>;

  const client = getClient(vessel.client_id);
  const marina = vessel.marina_id ? getMarina(vessel.marina_id) : undefined;
  const orders = getServiceOrdersForVessel(vessel.id);

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
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2"><Ship className="h-6 w-6 text-accent" />{vessel.boat_name}</h1>
          <p className="text-sm text-muted-foreground">{vessel.manufacturer} {vessel.model} ({vessel.year}) • {vessel.length_feet} ft • {t.vessels.owner}: {client?.full_name_or_company_name}</p>
        </div>
      </div>

      <Tabs defaultValue="overview">
        <TabsList>
          <TabsTrigger value="overview">{t.common.overview}</TabsTrigger>
          <TabsTrigger value="technical">{t.vessels.technicalProfile}</TabsTrigger>
          <TabsTrigger value="history">{t.vessels.serviceHistory}</TabsTrigger>
        </TabsList>

        <TabsContent value="overview" className="mt-4 grid grid-cols-1 lg:grid-cols-2 gap-4">
          <div className="rounded-xl border bg-card p-5 shadow-sm">
            <h3 className="text-sm font-semibold mb-3 flex items-center gap-2"><Ship className="h-4 w-4" /> {t.vessels.hullAndSpecs}</h3>
            <InfoRow label={t.vessels.hullId} value={vessel.hull_id_or_registration} />
            <InfoRow label={t.vessels.length} value={`${vessel.length_feet} ft`} />
            <InfoRow label={t.vessels.beam} value={vessel.beam_feet ? `${vessel.beam_feet} ft` : undefined} />
            <InfoRow label={t.vessels.draft} value={vessel.draft_feet ? `${vessel.draft_feet} ft` : undefined} />
            <InfoRow label={t.vessels.propulsion} value={vessel.propulsion_type} />
          </div>
          <div className="rounded-xl border bg-card p-5 shadow-sm">
            <h3 className="text-sm font-semibold mb-3 flex items-center gap-2"><Anchor className="h-4 w-4" /> {t.vessels.location}</h3>
            <InfoRow label={t.serviceOrders.marina} value={marina?.marina_name} />
            <InfoRow label={t.serviceOrders.dockPosition} value={vessel.current_dock_position} />
            <InfoRow label={t.vessels.owner} value={client?.full_name_or_company_name} />
            <InfoRow label={t.vessels.shorePower} value={vessel.shore_power_type} />
          </div>
        </TabsContent>

        <TabsContent value="technical" className="mt-4 space-y-4">
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <div className="rounded-xl border bg-card p-5 shadow-sm">
              <h3 className="text-sm font-semibold mb-3 flex items-center gap-2"><Zap className="h-4 w-4" /> {t.vessels.engines}</h3>
              <InfoRow label={t.common.type} value={vessel.engine_type} />
              <InfoRow label={t.products.brand} value={vessel.engine_brand} />
              <InfoRow label="Model" value={vessel.engine_model} />
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
          <div className="rounded-xl border bg-card shadow-sm overflow-hidden">
            <table className="w-full text-sm">
              <thead><tr className="border-b bg-muted/50">
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.serviceOrders.orderNumber}</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.common.date}</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.common.type}</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.common.status}</th>
                <th className="px-4 py-3 text-right font-medium text-muted-foreground">{t.common.total}</th>
              </tr></thead>
              <tbody>
                {orders.map(o => (
                  <tr key={o.id} className="border-b last:border-0 hover:bg-muted/30">
                    <td className="px-4 py-3"><Link to={`/service-orders/${o.id}`} className="text-accent hover:underline">{o.service_order_number}</Link></td>
                    <td className="px-4 py-3 text-muted-foreground">{formatDate(o.created_at)}</td>
                    <td className="px-4 py-3 text-muted-foreground">{(t.serviceType as Record<string, string>)[o.service_type]}</td>
                    <td className="px-4 py-3"><StatusBadge className={statusConfig[o.status].className}>{(t.status as Record<string, string>)[o.status]}</StatusBadge></td>
                    <td className="px-4 py-3 text-right font-medium">{formatCurrency(o.grand_total)}</td>
                  </tr>
                ))}
                {orders.length === 0 && <tr><td colSpan={5} className="px-4 py-8 text-center text-muted-foreground">{t.vessels.noServiceHistory}</td></tr>}
              </tbody>
            </table>
          </div>
        </TabsContent>
      </Tabs>
    </div>
  );
}
