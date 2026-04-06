import { useParams, Link } from 'react-router-dom';
import { serviceOrders, getClient, getVessel, getMarina, getUser, getPartsForOrder, getTimeEntriesForOrder, getProduct, users } from '@/data/mock-data';
import { formatCurrency, formatDate, formatDateTime, statusConfig, priorityConfig, serviceTypeLabels } from '@/lib/constants';
import { StatusBadge } from '@/components/StatusBadge';
import { Button } from '@/components/ui/button';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { ArrowLeft, Clock, MapPin, Wrench, DollarSign, Camera, FileText, Play, Square, CheckCircle, Upload } from 'lucide-react';

export default function ServiceOrderDetail() {
  const { id } = useParams<{ id: string }>();
  const order = serviceOrders.find(so => so.id === id);

  if (!order) return (
    <div className="flex flex-col items-center justify-center py-20">
      <p className="text-muted-foreground">Service order not found.</p>
      <Link to="/service-orders" className="text-accent hover:underline mt-2">← Back to list</Link>
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
            <StatusBadge className={sc.className}>{sc.label}</StatusBadge>
            <span className={pc.className + ' text-sm'}>{pc.label} Priority</span>
          </div>
          <p className="text-sm text-muted-foreground mt-1">{serviceTypeLabels[order.service_type]} • {client?.full_name_or_company_name} • {vessel?.boat_name}</p>
        </div>
        <div className="hidden sm:flex gap-2">
          <Button variant="outline" size="sm" className="gap-1"><Play className="h-3 w-3" /> Start Timer</Button>
          <Button variant="outline" size="sm" className="gap-1"><Camera className="h-3 w-3" /> Add Photo</Button>
          <Button size="sm" className="gap-1 bg-accent text-accent-foreground hover:bg-accent/90"><CheckCircle className="h-3 w-3" /> Complete</Button>
        </div>
      </div>

      {/* Mobile quick actions */}
      <div className="grid grid-cols-2 sm:hidden gap-2">
        <Button variant="outline" size="sm" className="gap-1"><Play className="h-3 w-3" /> Start Timer</Button>
        <Button variant="outline" size="sm" className="gap-1"><Camera className="h-3 w-3" /> Add Photo</Button>
        <Button variant="outline" size="sm" className="gap-1"><Upload className="h-3 w-3" /> Add Part</Button>
        <Button size="sm" className="gap-1 bg-accent text-accent-foreground hover:bg-accent/90"><CheckCircle className="h-3 w-3" /> Complete</Button>
      </div>

      <Tabs defaultValue="overview" className="space-y-4">
        <TabsList className="flex-wrap h-auto gap-1">
          <TabsTrigger value="overview">Overview</TabsTrigger>
          <TabsTrigger value="technical">Technical</TabsTrigger>
          <TabsTrigger value="team">Team & Time</TabsTrigger>
          <TabsTrigger value="parts">Parts</TabsTrigger>
          <TabsTrigger value="financial">Financial</TabsTrigger>
          <TabsTrigger value="files">Files</TabsTrigger>
        </TabsList>

        <TabsContent value="overview" className="space-y-4">
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <div className="rounded-xl border bg-card p-5 shadow-sm">
              <h3 className="text-sm font-semibold mb-3">Client & Vessel</h3>
              <InfoRow label="Client" value={client?.full_name_or_company_name} />
              <InfoRow label="Requested By" value={order.requested_by_name} />
              <InfoRow label="Vessel" value={vessel ? `${vessel.boat_name} (${vessel.manufacturer} ${vessel.model})` : undefined} />
              <InfoRow label="Marina" value={marina?.marina_name} />
              <InfoRow label="Dock Position" value={vessel?.current_dock_position} />
            </div>
            <div className="rounded-xl border bg-card p-5 shadow-sm">
              <h3 className="text-sm font-semibold mb-3">Schedule</h3>
              <InfoRow label="Scheduled Start" value={order.scheduled_start_at ? formatDateTime(order.scheduled_start_at) : undefined} />
              <InfoRow label="Scheduled End" value={order.scheduled_end_at ? formatDateTime(order.scheduled_end_at) : undefined} />
              <InfoRow label="Check In" value={order.check_in_at ? formatDateTime(order.check_in_at) : undefined} />
              <InfoRow label="Check Out" value={order.check_out_at ? formatDateTime(order.check_out_at) : undefined} />
              <InfoRow label="Created" value={formatDate(order.created_at)} />
            </div>
          </div>
          <div className="rounded-xl border bg-card p-5 shadow-sm">
            <h3 className="text-sm font-semibold mb-3">Problem Description</h3>
            <p className="text-sm leading-relaxed">{order.problem_description}</p>
          </div>
        </TabsContent>

        <TabsContent value="technical" className="space-y-4">
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <div className="rounded-xl border bg-card p-5 shadow-sm">
              <h3 className="text-sm font-semibold mb-3">Initial Findings</h3>
              <p className="text-sm leading-relaxed text-muted-foreground">{order.initial_findings || 'No findings recorded yet.'}</p>
            </div>
            <div className="rounded-xl border bg-card p-5 shadow-sm">
              <h3 className="text-sm font-semibold mb-3">Diagnosis</h3>
              <p className="text-sm leading-relaxed">{order.diagnosis || 'Pending diagnosis.'}</p>
            </div>
          </div>
          {order.solution_applied && (
            <div className="rounded-xl border bg-card p-5 shadow-sm">
              <h3 className="text-sm font-semibold mb-3">Solution Applied</h3>
              <p className="text-sm leading-relaxed">{order.solution_applied}</p>
            </div>
          )}
        </TabsContent>

        <TabsContent value="team" className="space-y-4">
          <div className="rounded-xl border bg-card p-5 shadow-sm">
            <h3 className="text-sm font-semibold mb-4">Time Entries</h3>
            {timeEntries.length === 0 ? (
              <p className="text-sm text-muted-foreground">No time entries recorded.</p>
            ) : (
              <div className="space-y-3">
                {timeEntries.map(te => {
                  const tech = getUser(te.technician_user_id);
                  return (
                    <div key={te.id} className="flex items-start justify-between p-3 rounded-lg bg-muted/50 border">
                      <div>
                        <p className="text-sm font-medium">{tech?.full_name}</p>
                        <p className="text-xs text-muted-foreground">{te.notes}</p>
                        <p className="text-xs text-muted-foreground mt-1">{formatDateTime(te.started_at)} → {te.ended_at ? formatDateTime(te.ended_at) : 'Running'}</p>
                      </div>
                      <div className="text-right">
                        <p className="text-sm font-semibold">{(te.duration_minutes / 60).toFixed(1)}h</p>
                        <StatusBadge className={te.billable ? 'bg-success/15 text-success' : 'bg-muted text-muted-foreground'}>
                          {te.billable ? 'Billable' : 'Non-billable'}
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
              <h3 className="text-sm font-semibold">Parts Used</h3>
              <Button variant="outline" size="sm" className="gap-1"><Plus className="h-3 w-3" /> Add Part</Button>
            </div>
            {parts.length === 0 ? (
              <p className="text-sm text-muted-foreground p-5">No parts used yet.</p>
            ) : (
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b bg-muted/50">
                    <th className="px-4 py-2 text-left font-medium text-muted-foreground">Product</th>
                    <th className="px-4 py-2 text-center font-medium text-muted-foreground">Qty</th>
                    <th className="px-4 py-2 text-right font-medium text-muted-foreground">Unit Price</th>
                    <th className="px-4 py-2 text-right font-medium text-muted-foreground">Total</th>
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
              <h3 className="text-sm font-semibold mb-3">Cost Breakdown</h3>
              <InfoRow label="Labor" value={`${order.labor_hours_total}h × ${formatCurrency(order.hourly_rate)} = ${formatCurrency(order.labor_cost_total)}`} />
              <InfoRow label="Parts" value={formatCurrency(order.parts_cost_total)} />
              <InfoRow label="Travel" value={formatCurrency(order.travel_cost_total)} />
              <InfoRow label="Subcontract" value={formatCurrency(order.subcontract_cost_total)} />
              <InfoRow label="Discount" value={order.discount_amount > 0 ? `-${formatCurrency(order.discount_amount)}` : '—'} />
              <InfoRow label="Tax" value={formatCurrency(order.tax_amount)} />
              <div className="flex justify-between pt-3 mt-2 border-t-2">
                <span className="font-semibold">Grand Total</span>
                <span className="text-lg font-bold text-accent">{formatCurrency(order.grand_total)}</span>
              </div>
            </div>
            <div className="rounded-xl border bg-card p-5 shadow-sm">
              <h3 className="text-sm font-semibold mb-3">Travel Calculation</h3>
              <InfoRow label="Origin" value="NautiTech Base, Rio de Janeiro" />
              <InfoRow label="Destination" value={marina?.marina_name || '—'} />
              <InfoRow label="Distance" value={`${order.travel_distance_km} km`} />
              <InfoRow label="Rate" value={`${formatCurrency(order.travel_cost_per_km)} / km`} />
              <InfoRow label="Technicians" value={String(order.technician_count_for_travel)} />
              <InfoRow label="Formula" value={`${order.travel_distance_km} × ${order.travel_cost_per_km} × ${order.technician_count_for_travel}`} />
              <div className="flex justify-between pt-3 mt-2 border-t-2">
                <span className="font-semibold">Travel Total</span>
                <span className="font-bold">{formatCurrency(order.travel_cost_total)}</span>
              </div>
            </div>
          </div>
        </TabsContent>

        <TabsContent value="files" className="space-y-4">
          <div className="rounded-xl border bg-card p-5 shadow-sm">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-sm font-semibold">Photos & Documents</h3>
              <Button variant="outline" size="sm" className="gap-1"><Upload className="h-3 w-3" /> Upload</Button>
            </div>
            <div className="flex flex-col items-center justify-center py-12 text-muted-foreground border-2 border-dashed rounded-lg">
              <Camera className="h-8 w-8 mb-2" />
              <p className="text-sm">No files uploaded yet</p>
              <p className="text-xs">Drag and drop or click upload to add photos and documents</p>
            </div>
          </div>
        </TabsContent>
      </Tabs>
    </div>
  );
}

function Plus({ className }: { className?: string }) {
  return <svg className={className} xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12h14"/><path d="M12 5v14"/></svg>;
}
