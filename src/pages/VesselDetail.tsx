import { useParams, Link } from 'react-router-dom';
import { vessels, getClient, getMarina, getServiceOrdersForVessel } from '@/data/mock-data';
import { formatCurrency, formatDate, statusConfig, serviceTypeLabels } from '@/lib/constants';
import { StatusBadge } from '@/components/StatusBadge';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { ArrowLeft, Ship, Anchor, Battery, Radio, Zap } from 'lucide-react';

export default function VesselDetail() {
  const { id } = useParams<{ id: string }>();
  const vessel = vessels.find(v => v.id === id);
  if (!vessel) return <div className="py-20 text-center text-muted-foreground">Vessel not found. <Link to="/vessels" className="text-accent hover:underline">← Back</Link></div>;

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
          <p className="text-sm text-muted-foreground">{vessel.manufacturer} {vessel.model} ({vessel.year}) • {vessel.length_feet} ft • Owner: {client?.full_name_or_company_name}</p>
        </div>
      </div>

      <Tabs defaultValue="overview">
        <TabsList><TabsTrigger value="overview">Overview</TabsTrigger><TabsTrigger value="technical">Technical Profile</TabsTrigger><TabsTrigger value="history">Service History</TabsTrigger></TabsList>

        <TabsContent value="overview" className="mt-4 grid grid-cols-1 lg:grid-cols-2 gap-4">
          <div className="rounded-xl border bg-card p-5 shadow-sm">
            <h3 className="text-sm font-semibold mb-3 flex items-center gap-2"><Ship className="h-4 w-4" /> Hull & Specs</h3>
            <InfoRow label="Hull ID / Registration" value={vessel.hull_id_or_registration} />
            <InfoRow label="Length" value={`${vessel.length_feet} ft`} />
            <InfoRow label="Beam" value={vessel.beam_feet ? `${vessel.beam_feet} ft` : undefined} />
            <InfoRow label="Draft" value={vessel.draft_feet ? `${vessel.draft_feet} ft` : undefined} />
            <InfoRow label="Propulsion" value={vessel.propulsion_type} />
          </div>
          <div className="rounded-xl border bg-card p-5 shadow-sm">
            <h3 className="text-sm font-semibold mb-3 flex items-center gap-2"><Anchor className="h-4 w-4" /> Location</h3>
            <InfoRow label="Marina" value={marina?.marina_name} />
            <InfoRow label="Dock Position" value={vessel.current_dock_position} />
            <InfoRow label="Owner" value={client?.full_name_or_company_name} />
            <InfoRow label="Shore Power" value={vessel.shore_power_type} />
          </div>
        </TabsContent>

        <TabsContent value="technical" className="mt-4 space-y-4">
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <div className="rounded-xl border bg-card p-5 shadow-sm">
              <h3 className="text-sm font-semibold mb-3 flex items-center gap-2"><Zap className="h-4 w-4" /> Engines</h3>
              <InfoRow label="Type" value={vessel.engine_type} />
              <InfoRow label="Brand" value={vessel.engine_brand} />
              <InfoRow label="Model" value={vessel.engine_model} />
              <InfoRow label="Quantity" value={vessel.engine_quantity} />
            </div>
            <div className="rounded-xl border bg-card p-5 shadow-sm">
              <h3 className="text-sm font-semibold mb-3 flex items-center gap-2"><Battery className="h-4 w-4" /> Power Systems</h3>
              <InfoRow label="Battery Bank" value={vessel.battery_bank_summary} />
              <InfoRow label="Inverter / Charger" value={vessel.inverter_charger_summary} />
              <InfoRow label="Shore Power" value={vessel.shore_power_type} />
            </div>
          </div>
          <div className="rounded-xl border bg-card p-5 shadow-sm">
            <h3 className="text-sm font-semibold mb-3 flex items-center gap-2"><Radio className="h-4 w-4" /> Navigation Electronics</h3>
            <p className="text-sm leading-relaxed">{vessel.navigation_electronics_summary || 'No navigation electronics documented.'}</p>
          </div>
          {vessel.electrical_system_notes && (
            <div className="rounded-xl border bg-card p-5 shadow-sm">
              <h3 className="text-sm font-semibold mb-3">Electrical System Notes</h3>
              <p className="text-sm leading-relaxed text-muted-foreground">{vessel.electrical_system_notes}</p>
            </div>
          )}
        </TabsContent>

        <TabsContent value="history" className="mt-4">
          <div className="rounded-xl border bg-card shadow-sm overflow-hidden">
            <table className="w-full text-sm">
              <thead><tr className="border-b bg-muted/50">
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">Order #</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">Date</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">Type</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">Status</th>
                <th className="px-4 py-3 text-right font-medium text-muted-foreground">Total</th>
              </tr></thead>
              <tbody>
                {orders.map(o => (
                  <tr key={o.id} className="border-b last:border-0 hover:bg-muted/30">
                    <td className="px-4 py-3"><Link to={`/service-orders/${o.id}`} className="text-accent hover:underline">{o.service_order_number}</Link></td>
                    <td className="px-4 py-3 text-muted-foreground">{formatDate(o.created_at)}</td>
                    <td className="px-4 py-3 text-muted-foreground">{serviceTypeLabels[o.service_type]}</td>
                    <td className="px-4 py-3"><StatusBadge className={statusConfig[o.status].className}>{statusConfig[o.status].label}</StatusBadge></td>
                    <td className="px-4 py-3 text-right font-medium">{formatCurrency(o.grand_total)}</td>
                  </tr>
                ))}
                {orders.length === 0 && <tr><td colSpan={5} className="px-4 py-8 text-center text-muted-foreground">No service history.</td></tr>}
              </tbody>
            </table>
          </div>
        </TabsContent>
      </Tabs>
    </div>
  );
}
