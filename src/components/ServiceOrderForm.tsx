import { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { useI18n } from '@/i18n';
import { useClients } from '@/hooks/use-clients';
import { useVessels } from '@/hooks/use-vessels';
import { useMarinas } from '@/hooks/use-marinas';
import { useProducts } from '@/hooks/use-products';
import {
  useCreateServiceOrder,
  useUpdateServiceOrder,
  useUpdateServiceOrderStatus,
  useServiceOrderParts,
  useAddServiceOrderPart,
  useRemoveServiceOrderPart,
  useTimeEntries,
  useAddTimeEntry,
  useRemoveTimeEntry,
  useAppUsers,
  STATUS_TRANSITIONS,
} from '@/hooks/use-service-orders';
import { calculateDisplacement } from '@/lib/displacement';
import { statusConfig, priorityConfig } from '@/lib/constants';
import { StatusBadge } from '@/components/StatusBadge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Skeleton } from '@/components/ui/skeleton';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { ArrowLeft, Plus, Trash2, RefreshCw, AlertTriangle, Calculator } from 'lucide-react';
import { toast } from 'sonner';

interface Props {
  orderId?: string;
  orderData?: any;
  isLoading?: boolean;
}

const SERVICE_TYPES = [
  'diagnosis', 'repair', 'installation', 'preventive_maintenance',
  'consulting', 'engineering_project', 'commissioning', 'inspection',
] as const;

const PRIORITIES = ['low', 'normal', 'high', 'urgent'] as const;
const STATUSES = [
  'draft', 'scheduled', 'open', 'in_progress', 'awaiting_parts',
  'awaiting_client', 'completed', 'invoiced', 'cancelled',
] as const;

export function ServiceOrderForm({ orderId, orderData, isLoading }: Props) {
  const navigate = useNavigate();
  const { t, formatCurrency, formatDateTime } = useI18n();
  const isNew = !orderId;

  const { data: clients } = useClients();
  const { data: allVessels } = useVessels();
  const { data: marinas } = useMarinas();
  const { data: products } = useProducts();
  const { data: appUsers } = useAppUsers();

  const createSO = useCreateServiceOrder();
  const updateSO = useUpdateServiceOrder();
  const updateStatus = useUpdateServiceOrderStatus();

  const { data: parts } = useServiceOrderParts(orderId);
  const addPart = useAddServiceOrderPart();
  const removePart = useRemoveServiceOrderPart();

  const { data: timeEntries } = useTimeEntries(orderId);
  const addTime = useAddTimeEntry();
  const removeTime = useRemoveTimeEntry();

  // Form state
  const [form, setForm] = useState<Record<string, any>>({
    status: 'draft',
    priority: 'normal',
    service_type: 'repair',
    client_id: '',
    vessel_id: '',
    marina_id: '',
    requested_by_name: '',
    scheduled_start_at: '',
    scheduled_end_at: '',
    problem_description: '',
    initial_findings: '',
    diagnosis: '',
    solution_applied: '',
    technician_notes: '',
    internal_notes: '',
    customer_visible_report: '',
    hourly_rate: 150,
    estimated_hours: 0,
    travel_distance_km: 0,
    travel_cost_per_km: 3.5,
    technician_count_for_travel: 1,
    travel_cost_total: 0,
    discount_amount: 0,
    tax_amount: 0,
    subcontract_cost_total: 0,
  });

  const [manualTravel, setManualTravel] = useState(false);
  const [selectedTechnicians, setSelectedTechnicians] = useState<string[]>([]);

  // Part form
  const [partForm, setPartForm] = useState({ product_id: '', quantity: 1, unit_cost: 0, unit_sale: 0 });
  const [showPartForm, setShowPartForm] = useState(false);

  // Time form
  const [timeForm, setTimeForm] = useState({
    technician_user_id: '', started_at: '', ended_at: '', duration_minutes: 0, billable: true, notes: '',
  });
  const [showTimeForm, setShowTimeForm] = useState(false);

  // Card fee
  const [cardFee, setCardFee] = useState(3.5);

  useEffect(() => {
    if (orderData) {
      const d = orderData;
      setForm({
        status: d.status || 'draft',
        priority: d.priority || 'normal',
        service_type: d.service_type || 'repair',
        client_id: d.client_id || '',
        vessel_id: d.vessel_id || '',
        marina_id: d.marina_id || '',
        requested_by_name: d.requested_by_name || '',
        scheduled_start_at: d.scheduled_start_at ? d.scheduled_start_at.slice(0, 16) : '',
        scheduled_end_at: d.scheduled_end_at ? d.scheduled_end_at.slice(0, 16) : '',
        problem_description: d.problem_description || '',
        initial_findings: d.initial_findings || '',
        diagnosis: d.diagnosis || '',
        solution_applied: d.solution_applied || '',
        technician_notes: d.technician_notes || '',
        internal_notes: d.internal_notes || '',
        customer_visible_report: d.customer_visible_report || '',
        hourly_rate: d.hourly_rate || 150,
        estimated_hours: d.estimated_hours || 0,
        travel_distance_km: d.travel_distance_km || 0,
        travel_cost_per_km: d.travel_cost_per_km || 3.5,
        technician_count_for_travel: d.technician_count_for_travel || 1,
        travel_cost_total: d.travel_cost_total || 0,
        discount_amount: d.discount_amount || 0,
        tax_amount: d.tax_amount || 0,
        subcontract_cost_total: d.subcontract_cost_total || 0,
      });
      if (d.service_order_technicians) {
        setSelectedTechnicians(d.service_order_technicians.map((t: any) => t.user_id));
      }
    }
  }, [orderData]);

  // Load card fee
  useEffect(() => {
    (async () => {
      const { supabase } = await import('@/integrations/supabase/client');
      const { data } = await supabase
        .from('app_settings')
        .select('value')
        .eq('key', 'card_fee_percent')
        .maybeSingle();
      if (data) setCardFee(parseFloat(data.value) || 3.5);
    })();
  }, []);

  const set = (field: string, value: any) => setForm((p) => ({ ...p, [field]: value }));

  // Filter vessels by client
  const clientVessels = allVessels?.filter((v) => v.client_id === form.client_id) || [];

  // Auto-select single vessel
  useEffect(() => {
    if (form.client_id && clientVessels.length === 1 && !form.vessel_id) {
      set('vessel_id', clientVessels[0].id);
      if (clientVessels[0].marina_id) set('marina_id', clientVessels[0].marina_id);
    }
  }, [form.client_id, clientVessels.length]);

  // Auto displacement
  const runDisplacement = useCallback(async () => {
    const marina = marinas?.find((m) => m.id === form.marina_id);
    if (!marina?.latitude || !marina?.longitude) return;
    try {
      const result = await calculateDisplacement(
        Number(marina.latitude),
        Number(marina.longitude),
        form.technician_count_for_travel
      );
      set('travel_distance_km', result.distance_km);
      set('travel_cost_per_km', result.cost_per_km);
      set('travel_cost_total', result.total_cost);
    } catch (e) {
      console.error('Displacement calc failed', e);
    }
  }, [form.marina_id, form.technician_count_for_travel, marinas]);

  // Financial summary
  const laborCost = orderData?.labor_cost_total || 0;
  const partsCost = orderData?.parts_cost_total || 0;
  const subtotal = laborCost + partsCost + form.travel_cost_total + form.subcontract_cost_total;
  const grandTotal = subtotal - form.discount_amount + form.tax_amount;
  const cardTotal = grandTotal / (1 - cardFee / 100);

  const handleSave = async () => {
    if (!form.client_id || !form.vessel_id || !form.problem_description) {
      toast.error('Preencha cliente, embarcação e descrição do problema');
      return;
    }
    try {
      if (isNew) {
        const result = await createSO.mutateAsync(form);
        // Save technicians
        if (selectedTechnicians.length > 0) {
          const { supabase } = await import('@/integrations/supabase/client');
          await supabase.from('service_order_technicians').insert(
            selectedTechnicians.map((uid) => ({
              service_order_id: result.id,
              user_id: uid,
            }))
          );
        }
        toast.success('Ordem de serviço criada com sucesso');
        navigate(`/service-orders/${result.id}`);
      } else {
        await updateSO.mutateAsync({ id: orderId!, ...form });
        // Update technicians
        const { supabase } = await import('@/integrations/supabase/client');
        await supabase.from('service_order_technicians').delete().eq('service_order_id', orderId!);
        if (selectedTechnicians.length > 0) {
          await supabase.from('service_order_technicians').insert(
            selectedTechnicians.map((uid) => ({
              service_order_id: orderId!,
              user_id: uid,
            }))
          );
        }
        toast.success('Ordem de serviço atualizada');
      }
    } catch (e: any) {
      toast.error(e.message || 'Erro ao salvar');
    }
  };

  const handleStatusChange = async (newStatus: string) => {
    if (!orderId) return;
    try {
      await updateStatus.mutateAsync({ id: orderId, status: newStatus });
      toast.success(`Status alterado para ${(t.status as Record<string, string>)[newStatus]}`);
    } catch (e: any) {
      toast.error(e.message || 'Erro ao alterar status');
    }
  };

  const handleAddPart = async () => {
    if (!orderId || !partForm.product_id || partForm.quantity <= 0) return;
    try {
      await addPart.mutateAsync({
        service_order_id: orderId,
        product_id: partForm.product_id,
        quantity: partForm.quantity,
        unit_cost_snapshot: partForm.unit_cost,
        unit_sale_snapshot: partForm.unit_sale,
      });
      setPartForm({ product_id: '', quantity: 1, unit_cost: 0, unit_sale: 0 });
      setShowPartForm(false);
      toast.success('Peça adicionada');
    } catch (e: any) {
      toast.error(e.message || 'Erro ao adicionar peça');
    }
  };

  const handleAddTime = async () => {
    if (!orderId || !timeForm.technician_user_id || !timeForm.started_at) return;
    try {
      await addTime.mutateAsync({
        service_order_id: orderId,
        ...timeForm,
        ended_at: timeForm.ended_at || undefined,
      });
      setTimeForm({ technician_user_id: '', started_at: '', ended_at: '', duration_minutes: 0, billable: true, notes: '' });
      setShowTimeForm(false);
      toast.success('Registro de tempo adicionado');
    } catch (e: any) {
      toast.error(e.message || 'Erro ao registrar tempo');
    }
  };

  // Compute duration from start/end
  useEffect(() => {
    if (timeForm.started_at && timeForm.ended_at) {
      const start = new Date(timeForm.started_at).getTime();
      const end = new Date(timeForm.ended_at).getTime();
      if (end > start) {
        setTimeForm((p) => ({ ...p, duration_minutes: Math.round((end - start) / 60000) }));
      }
    }
  }, [timeForm.started_at, timeForm.ended_at]);

  if (isLoading) return <div className="space-y-4">{Array.from({ length: 6 }).map((_, i) => <Skeleton key={i} className="h-20 w-full" />)}</div>;

  const currentStatus = form.status;
  const validTransitions = STATUS_TRANSITIONS[currentStatus] || [];
  const marina = marinas?.find((m) => m.id === form.marina_id);

  return (
    <div className="space-y-6 animate-fade-in max-w-5xl">
      {/* Header */}
      <div className="flex items-center gap-3 flex-wrap">
        <Button variant="ghost" size="icon" onClick={() => navigate('/service-orders')}>
          <ArrowLeft className="h-5 w-5" />
        </Button>
        <div className="flex-1">
          <h1 className="text-2xl font-bold">
            {isNew ? t.serviceOrders.newOrder : orderData?.service_order_number}
          </h1>
          {!isNew && (
            <div className="flex items-center gap-2 mt-1">
              <StatusBadge className={statusConfig[currentStatus]?.className || ''}>
                {(t.status as Record<string, string>)[currentStatus]}
              </StatusBadge>
              <span className={priorityConfig[form.priority]?.className || ''}>
                {(t.priority as Record<string, string>)[form.priority]}
              </span>
            </div>
          )}
        </div>
        <div className="flex gap-2">
          {!isNew && validTransitions.length > 0 && (
            <Select onValueChange={handleStatusChange}>
              <SelectTrigger className="w-[180px]">
                <SelectValue placeholder={t.serviceOrders.alterStatus || 'Alterar Status'} />
              </SelectTrigger>
              <SelectContent>
                {validTransitions.map((s) => (
                  <SelectItem key={s} value={s}>
                    {(t.status as Record<string, string>)[s]}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          )}
          <Button onClick={handleSave} disabled={createSO.isPending || updateSO.isPending}
            className="bg-accent text-accent-foreground hover:bg-accent/90">
            {t.common.save}
          </Button>
        </div>
      </div>

      {/* A - Identification */}
      <section className="rounded-xl border bg-card p-5 shadow-sm space-y-4">
        <h2 className="font-semibold text-sm">{t.serviceOrders.tabOverview}</h2>
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <div>
            <Label>{t.common.status}</Label>
            <Select value={form.status} onValueChange={(v) => set('status', v)} disabled={!isNew}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {STATUSES.map((s) => (
                  <SelectItem key={s} value={s}>{(t.status as Record<string, string>)[s]}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div>
            <Label>{t.serviceOrders.priority}</Label>
            <Select value={form.priority} onValueChange={(v) => set('priority', v)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {PRIORITIES.map((p) => (
                  <SelectItem key={p} value={p}>{(t.priority as Record<string, string>)[p]}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div>
            <Label>{t.common.type}</Label>
            <Select value={form.service_type} onValueChange={(v) => set('service_type', v)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {SERVICE_TYPES.map((st) => (
                  <SelectItem key={st} value={st}>{(t.serviceType as Record<string, string>)[st]}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        </div>
      </section>

      {/* B - Client & Vessel */}
      <section className="rounded-xl border bg-card p-5 shadow-sm space-y-4">
        <h2 className="font-semibold text-sm">{t.serviceOrders.clientAndVessel}</h2>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div>
            <Label>{t.serviceOrders.client} *</Label>
            <Select value={form.client_id} onValueChange={(v) => { set('client_id', v); set('vessel_id', ''); }}>
              <SelectTrigger><SelectValue placeholder={t.vessels.selectClient} /></SelectTrigger>
              <SelectContent>
                {clients?.filter((c) => c.active).map((c) => (
                  <SelectItem key={c.id} value={c.id}>{c.full_name_or_company_name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div>
            <Label>{t.serviceOrders.vessel} *</Label>
            <Select value={form.vessel_id} onValueChange={(v) => {
              set('vessel_id', v);
              const vessel = allVessels?.find((vv) => vv.id === v);
              if (vessel?.marina_id) set('marina_id', vessel.marina_id);
            }} disabled={!form.client_id}>
              <SelectTrigger><SelectValue placeholder={t.vessels.selectMarina || 'Selecionar embarcação'} /></SelectTrigger>
              <SelectContent>
                {clientVessels.filter((v) => v.active).map((v) => (
                  <SelectItem key={v.id} value={v.id}>{v.boat_name} {v.manufacturer ? `(${v.manufacturer})` : ''}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div>
            <Label>{t.serviceOrders.marina}</Label>
            <Select value={form.marina_id || 'none'} onValueChange={(v) => set('marina_id', v === 'none' ? '' : v)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="none">—</SelectItem>
                {marinas?.filter((m) => m.active).map((m) => (
                  <SelectItem key={m.id} value={m.id}>{m.marina_name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div>
            <Label>{t.serviceOrders.requestedBy}</Label>
            <Input value={form.requested_by_name} onChange={(e) => set('requested_by_name', e.target.value)} />
          </div>
        </div>
      </section>

      {/* C - Scheduling */}
      <section className="rounded-xl border bg-card p-5 shadow-sm space-y-4">
        <h2 className="font-semibold text-sm">{t.serviceOrders.schedule}</h2>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div>
            <Label>{t.serviceOrders.scheduledStart}</Label>
            <Input type="datetime-local" value={form.scheduled_start_at} onChange={(e) => set('scheduled_start_at', e.target.value)} />
          </div>
          <div>
            <Label>{t.serviceOrders.scheduledEnd}</Label>
            <Input type="datetime-local" value={form.scheduled_end_at} onChange={(e) => set('scheduled_end_at', e.target.value)} />
          </div>
        </div>
        {/* Technicians */}
        <div>
          <Label>{t.serviceOrders.technicians}</Label>
          <div className="flex flex-wrap gap-2 mt-1">
            {appUsers?.map((u) => (
              <label key={u.id} className="flex items-center gap-1.5 text-sm border rounded-lg px-3 py-1.5 cursor-pointer hover:bg-muted transition-colors">
                <input
                  type="checkbox"
                  checked={selectedTechnicians.includes(u.id)}
                  onChange={(e) => {
                    const next = e.target.checked
                      ? [...selectedTechnicians, u.id]
                      : selectedTechnicians.filter((id) => id !== u.id);
                    setSelectedTechnicians(next);
                    set('technician_count_for_travel', next.length || 1);
                  }}
                />
                {u.full_name}
              </label>
            ))}
          </div>
        </div>
      </section>

      {/* D - Problem & Technical */}
      <section className="rounded-xl border bg-card p-5 shadow-sm space-y-4">
        <h2 className="font-semibold text-sm">{t.serviceOrders.problemDescription}</h2>
        <div>
          <Label>{t.serviceOrders.problemDescription} *</Label>
          <Textarea value={form.problem_description} onChange={(e) => set('problem_description', e.target.value)} rows={3} />
        </div>
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <div>
            <Label>{t.serviceOrders.initialFindings}</Label>
            <Textarea value={form.initial_findings} onChange={(e) => set('initial_findings', e.target.value)} rows={2} />
          </div>
          <div>
            <Label>{t.serviceOrders.diagnosis}</Label>
            <Textarea value={form.diagnosis} onChange={(e) => set('diagnosis', e.target.value)} rows={2} />
          </div>
          <div>
            <Label>{t.serviceOrders.solutionApplied}</Label>
            <Textarea value={form.solution_applied} onChange={(e) => set('solution_applied', e.target.value)} rows={2} />
          </div>
          <div>
            <Label>{t.serviceOrders.technicianNotes || 'Notas do Técnico'}</Label>
            <Textarea value={form.technician_notes} onChange={(e) => set('technician_notes', e.target.value)} rows={2} />
          </div>
        </div>
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <div>
            <Label>{t.serviceOrders.internalNotes || 'Notas Internas'}</Label>
            <Textarea value={form.internal_notes} onChange={(e) => set('internal_notes', e.target.value)} rows={2} />
          </div>
          <div>
            <Label>{t.serviceOrders.customerReport || 'Relatório para o Cliente'}</Label>
            <Textarea value={form.customer_visible_report} onChange={(e) => set('customer_visible_report', e.target.value)} rows={2} />
          </div>
        </div>
      </section>

      {/* E - Labor & Displacement */}
      <section className="rounded-xl border bg-card p-5 shadow-sm space-y-4">
        <h2 className="font-semibold text-sm">{t.serviceOrders.labor}</h2>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div>
            <Label>{t.serviceOrders.hourlyRate || 'Valor Hora (R$)'}</Label>
            <Input type="number" value={form.hourly_rate} onChange={(e) => set('hourly_rate', parseFloat(e.target.value) || 0)} />
          </div>
          <div>
            <Label>{t.serviceOrders.estimatedHours || 'Horas Estimadas'}</Label>
            <Input type="number" value={form.estimated_hours} onChange={(e) => set('estimated_hours', parseFloat(e.target.value) || 0)} />
          </div>
        </div>

        {/* Displacement card */}
        <div className="rounded-lg border p-4 bg-muted/30 space-y-3">
          <div className="flex items-center justify-between">
            <h3 className="text-sm font-medium">{t.serviceOrders.travelCalculation}</h3>
            <div className="flex gap-2">
              <Button variant="outline" size="sm" onClick={runDisplacement} className="gap-1">
                <RefreshCw className="h-3 w-3" /> {t.serviceOrders.recalculate || 'Recalcular'}
              </Button>
              <label className="flex items-center gap-1.5 text-xs">
                <Switch checked={manualTravel} onCheckedChange={setManualTravel} />
                {t.serviceOrders.manualOverride || 'Ajuste manual'}
              </label>
            </div>
          </div>
          {!marina?.latitude && form.marina_id && (
            <div className="flex items-center gap-2 text-xs text-warning">
              <AlertTriangle className="h-3.5 w-3.5" />
              {t.serviceOrders.noCoordinates || 'Marina sem coordenadas — preencha a localização da marina para calcular automaticamente'}
            </div>
          )}
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 text-sm">
            <div>
              <span className="text-muted-foreground">{t.serviceOrders.distance}</span>
              <p className="font-medium">{form.travel_distance_km} km</p>
            </div>
            <div>
              <span className="text-muted-foreground">{t.serviceOrders.rate}</span>
              <p className="font-medium">{formatCurrency(form.travel_cost_per_km)}/km</p>
            </div>
            <div>
              <span className="text-muted-foreground">{t.serviceOrders.technicians}</span>
              <p className="font-medium">{form.technician_count_for_travel}</p>
            </div>
            <div>
              <span className="text-muted-foreground">{t.serviceOrders.travelTotal}</span>
              {manualTravel ? (
                <Input type="number" value={form.travel_cost_total}
                  onChange={(e) => set('travel_cost_total', parseFloat(e.target.value) || 0)}
                  className="h-7 text-sm" />
              ) : (
                <p className="font-bold">{formatCurrency(form.travel_cost_total)}</p>
              )}
            </div>
          </div>
        </div>
      </section>

      {/* F - Parts (edit only) */}
      {!isNew && (
        <section className="rounded-xl border bg-card shadow-sm overflow-hidden">
          <div className="p-5 border-b flex items-center justify-between">
            <h2 className="font-semibold text-sm">{t.serviceOrders.partsUsed}</h2>
            <Button variant="outline" size="sm" className="gap-1" onClick={() => setShowPartForm(!showPartForm)}>
              <Plus className="h-3 w-3" /> {t.serviceOrders.addPart}
            </Button>
          </div>
          {showPartForm && (
            <div className="p-4 border-b bg-muted/30 space-y-3">
              <div className="grid grid-cols-1 sm:grid-cols-4 gap-3">
                <div className="sm:col-span-2">
                  <Label>{t.serviceOrders.product}</Label>
                  <Select value={partForm.product_id} onValueChange={(v) => {
                    const prod = products?.find((p) => p.id === v);
                    setPartForm({
                      ...partForm, product_id: v,
                      unit_cost: prod?.cost_price || 0,
                      unit_sale: prod?.sale_price || 0,
                    });
                  }}>
                    <SelectTrigger><SelectValue placeholder="Selecionar produto" /></SelectTrigger>
                    <SelectContent>
                      {products?.filter((p) => p.active).map((p) => (
                        <SelectItem key={p.id} value={p.id}>
                          {p.product_name} (estoque: {p.stock_quantity})
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div>
                  <Label>{t.serviceOrders.qty}</Label>
                  <Input type="number" min={1} value={partForm.quantity}
                    onChange={(e) => setPartForm({ ...partForm, quantity: parseInt(e.target.value) || 1 })} />
                </div>
                <div>
                  <Label>{t.serviceOrders.unitPrice}</Label>
                  <Input type="number" value={partForm.unit_sale}
                    onChange={(e) => setPartForm({ ...partForm, unit_sale: parseFloat(e.target.value) || 0 })} />
                </div>
              </div>
              <div className="flex gap-2">
                <Button size="sm" onClick={handleAddPart} disabled={addPart.isPending}>{t.common.save}</Button>
                <Button size="sm" variant="outline" onClick={() => setShowPartForm(false)}>{t.common.cancel}</Button>
              </div>
            </div>
          )}
          {(!parts || parts.length === 0) ? (
            <p className="text-sm text-muted-foreground p-5">{t.serviceOrders.noPartsYet}</p>
          ) : (
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b bg-muted/50">
                  <th className="px-4 py-2 text-left font-medium text-muted-foreground">{t.serviceOrders.product}</th>
                  <th className="px-4 py-2 text-center font-medium text-muted-foreground">{t.serviceOrders.qty}</th>
                  <th className="px-4 py-2 text-right font-medium text-muted-foreground">{t.serviceOrders.unitPrice}</th>
                  <th className="px-4 py-2 text-right font-medium text-muted-foreground">{t.common.total}</th>
                  <th className="px-4 py-2 w-10"></th>
                </tr>
              </thead>
              <tbody>
                {parts.map((p: any) => (
                  <tr key={p.id} className="border-b last:border-0">
                    <td className="px-4 py-3 font-medium">{p.products?.product_name}</td>
                    <td className="px-4 py-3 text-center">{p.quantity}</td>
                    <td className="px-4 py-3 text-right">{formatCurrency(p.unit_sale_snapshot)}</td>
                    <td className="px-4 py-3 text-right font-semibold">{formatCurrency(p.line_total_sale)}</td>
                    <td className="px-4 py-3">
                      <Button variant="ghost" size="icon" className="h-7 w-7 text-destructive"
                        onClick={() => removePart.mutate({
                          id: p.id, service_order_id: orderId!, product_id: p.product_id,
                          quantity: p.quantity, unit_cost_snapshot: p.unit_cost_snapshot,
                        })}>
                        <Trash2 className="h-3.5 w-3.5" />
                      </Button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </section>
      )}

      {/* G - Time Entries (edit only) */}
      {!isNew && (
        <section className="rounded-xl border bg-card shadow-sm overflow-hidden">
          <div className="p-5 border-b flex items-center justify-between">
            <h2 className="font-semibold text-sm">{t.serviceOrders.timeEntries}</h2>
            <Button variant="outline" size="sm" className="gap-1" onClick={() => setShowTimeForm(!showTimeForm)}>
              <Plus className="h-3 w-3" /> {t.serviceOrders.addTimeEntry || 'Registrar Horas'}
            </Button>
          </div>
          {showTimeForm && (
            <div className="p-4 border-b bg-muted/30 space-y-3">
              <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                <div>
                  <Label>{t.serviceOrders.technicians}</Label>
                  <Select value={timeForm.technician_user_id}
                    onValueChange={(v) => setTimeForm({ ...timeForm, technician_user_id: v })}>
                    <SelectTrigger><SelectValue placeholder="Selecionar técnico" /></SelectTrigger>
                    <SelectContent>
                      {appUsers?.map((u) => (
                        <SelectItem key={u.id} value={u.id}>{u.full_name}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div>
                  <Label>{t.serviceOrders.scheduledStart}</Label>
                  <Input type="datetime-local" value={timeForm.started_at}
                    onChange={(e) => setTimeForm({ ...timeForm, started_at: e.target.value })} />
                </div>
                <div>
                  <Label>{t.serviceOrders.scheduledEnd}</Label>
                  <Input type="datetime-local" value={timeForm.ended_at}
                    onChange={(e) => setTimeForm({ ...timeForm, ended_at: e.target.value })} />
                </div>
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                <div>
                  <Label>Duração (min)</Label>
                  <Input type="number" value={timeForm.duration_minutes}
                    onChange={(e) => setTimeForm({ ...timeForm, duration_minutes: parseInt(e.target.value) || 0 })} />
                </div>
                <div className="flex items-end gap-2">
                  <label className="flex items-center gap-1.5 text-sm">
                    <Switch checked={timeForm.billable}
                      onCheckedChange={(v) => setTimeForm({ ...timeForm, billable: v })} />
                    {t.serviceOrders.billable}
                  </label>
                </div>
                <div>
                  <Label>{t.common.notes}</Label>
                  <Input value={timeForm.notes}
                    onChange={(e) => setTimeForm({ ...timeForm, notes: e.target.value })} />
                </div>
              </div>
              <div className="flex gap-2">
                <Button size="sm" onClick={handleAddTime} disabled={addTime.isPending}>{t.common.save}</Button>
                <Button size="sm" variant="outline" onClick={() => setShowTimeForm(false)}>{t.common.cancel}</Button>
              </div>
            </div>
          )}
          {(!timeEntries || timeEntries.length === 0) ? (
            <p className="text-sm text-muted-foreground p-5">{t.serviceOrders.noTimeEntries}</p>
          ) : (
            <div className="divide-y">
              {timeEntries.map((te: any) => (
                <div key={te.id} className="flex items-start justify-between p-4">
                  <div>
                    <p className="text-sm font-medium">{te.app_users?.full_name}</p>
                    {te.notes && <p className="text-xs text-muted-foreground">{te.notes}</p>}
                    <p className="text-xs text-muted-foreground mt-1">
                      {formatDateTime(te.started_at)} → {te.ended_at ? formatDateTime(te.ended_at) : '...'}
                    </p>
                  </div>
                  <div className="flex items-center gap-3">
                    <div className="text-right">
                      <p className="text-sm font-semibold">{((te.duration_minutes || 0) / 60).toFixed(1)}h</p>
                      <StatusBadge className={te.billable ? 'bg-success/15 text-success' : 'bg-muted text-muted-foreground'}>
                        {te.billable ? t.serviceOrders.billable : t.serviceOrders.nonBillable}
                      </StatusBadge>
                    </div>
                    <Button variant="ghost" size="icon" className="h-7 w-7 text-destructive"
                      onClick={() => removeTime.mutate({ id: te.id, service_order_id: orderId! })}>
                      <Trash2 className="h-3.5 w-3.5" />
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </section>
      )}

      {/* H - Financial Summary */}
      <section className="rounded-xl border bg-card p-5 shadow-sm space-y-4">
        <h2 className="font-semibold text-sm">{t.serviceOrders.costBreakdown}</h2>
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <div className="space-y-2">
            <div className="flex justify-between text-sm">
              <span className="text-muted-foreground">{t.serviceOrders.labor}</span>
              <span>{formatCurrency(laborCost)}</span>
            </div>
            <div className="flex justify-between text-sm">
              <span className="text-muted-foreground">{t.serviceOrders.parts}</span>
              <span>{formatCurrency(partsCost)}</span>
            </div>
            <div className="flex justify-between text-sm">
              <span className="text-muted-foreground">{t.serviceOrders.travel}</span>
              <span>{formatCurrency(form.travel_cost_total)}</span>
            </div>
            <div className="flex justify-between text-sm">
              <span className="text-muted-foreground">{t.serviceOrders.subcontract}</span>
              <Input type="number" className="w-28 h-7 text-right text-sm" value={form.subcontract_cost_total}
                onChange={(e) => set('subcontract_cost_total', parseFloat(e.target.value) || 0)} />
            </div>
            <div className="flex justify-between text-sm items-center">
              <span className="text-muted-foreground">{t.serviceOrders.discount}</span>
              <Input type="number" className="w-28 h-7 text-right text-sm" value={form.discount_amount}
                onChange={(e) => set('discount_amount', parseFloat(e.target.value) || 0)} />
            </div>
            <div className="flex justify-between text-sm items-center">
              <span className="text-muted-foreground">{t.serviceOrders.tax}</span>
              <Input type="number" className="w-28 h-7 text-right text-sm" value={form.tax_amount}
                onChange={(e) => set('tax_amount', parseFloat(e.target.value) || 0)} />
            </div>
            <div className="flex justify-between pt-3 border-t-2">
              <span className="font-bold text-lg">{t.serviceOrders.grandTotal}</span>
              <span className="font-bold text-lg text-accent">{formatCurrency(grandTotal)}</span>
            </div>
          </div>

          {/* Payment info */}
          <div className="space-y-3">
            <div className="rounded-lg border p-3 bg-muted/30">
              <div className="flex items-center gap-2 mb-1">
                <Calculator className="h-4 w-4 text-muted-foreground" />
                <span className="text-sm font-medium">PIX</span>
              </div>
              <p className="text-sm">{formatCurrency(grandTotal)}</p>
            </div>
            <div className="rounded-lg border p-3 bg-muted/30">
              <div className="flex items-center gap-2 mb-1">
                <Calculator className="h-4 w-4 text-muted-foreground" />
                <span className="text-sm font-medium">{t.serviceOrders.paymentMethodCard || 'Cartão de Crédito'}</span>
              </div>
              <p className="text-sm">
                {t.serviceOrders.cardTotalNote || 'Valor a cobrar'}: <span className="font-semibold">{formatCurrency(cardTotal)}</span>
              </p>
              <p className="text-xs text-muted-foreground">
                {t.serviceOrders.cardFeeNote || 'Taxa estimada'}: {formatCurrency(cardTotal - grandTotal)} ({cardFee}%)
              </p>
            </div>
          </div>
        </div>
      </section>
    </div>
  );
}
