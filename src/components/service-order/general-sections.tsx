/* Seções A-D da OS — Identificação, Cliente & Embarcação, Agendamento+Técnicos,
   Problema & Técnico — extraídas 1:1 do ServiceOrderForm (Fase 3, passo 6). */
import { Camera, ChevronDown, Sparkles } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Textarea } from '@/components/ui/textarea';
import { ClientCombobox } from '@/components/ClientCombobox';
import { VesselSelect } from '@/components/VesselSelect';
import { EntityCombobox } from '@/components/EntityCombobox';
import { ServiceOrderPhotos } from '@/components/ServiceOrderPhotos';
import { VESSEL_CONTACT_ROLES } from '@/hooks/use-vessel-contacts';
import { useI18n } from '@/i18n';
import type { Dispatch, SetStateAction } from 'react';

const SERVICE_TYPES = [
  'diagnosis', 'repair', 'installation', 'preventive_maintenance',
  'consulting', 'engineering_project', 'commissioning', 'inspection',
] as const;

const PRIORITIES = ['low', 'normal', 'high', 'urgent'] as const;
const STATUSES = [
  'draft', 'scheduled', 'open', 'in_progress', 'awaiting_parts',
  'awaiting_client', 'approved', 'completed', 'invoiced', 'cancelled',
] as const;

interface GeneralSectionsProps {
  isNew: boolean;
  isLocked: boolean;
  orderData: any;
  form: Record<string, any>;
  set: (field: string, value: any) => void;
  setForm: Dispatch<SetStateAction<Record<string, any>>>;
  clients: any[] | undefined;
  allVessels: any[] | undefined;
  clientVessels: any[] | undefined;
  marinas: any[] | undefined;
  appUsers: any[] | undefined;
  vesselContacts: any[] | undefined;
  selectedTechnicians: string[];
  setSelectedTechnicians: Dispatch<SetStateAction<string[]>>;
  setQuickMarinaOpen: Dispatch<SetStateAction<boolean>>;
  setQuickMarinaName: Dispatch<SetStateAction<string>>;
  isOptimizing: boolean;
  optimizeText: (...args: any[]) => any;
  /** Lê a descrição e devolve o levantamento meio pronto. Opcional: sem isso a
      seção segue funcionando como antes, só com o reescrever. */
  onAnalisarDescricao?: (texto: string) => void;
  analisandoDescricao?: boolean;
}

export function GeneralSections(props: GeneralSectionsProps) {
  const {
    isNew, isLocked, orderData, form, set, setForm,
    clients, allVessels, clientVessels, marinas, appUsers, vesselContacts,
    selectedTechnicians, setSelectedTechnicians,
    setQuickMarinaOpen, setQuickMarinaName,
    isOptimizing, optimizeText, onAnalisarDescricao, analisandoDescricao,
  } = props;
  const { t, formatCurrency } = useI18n();

  return (
    <>
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
            <ClientCombobox
              value={form.client_id}
              onChange={(clientId) => {
                set('client_id', clientId);
                set('vessel_id', '');
                set('requested_by_contact_id', '');
                set('requested_by_name', '');
              }}
              clients={clients}
              disabled={isLocked}
            />
          </div>
          <div>
            <Label>{t.serviceOrders.vessel} *</Label>
            <VesselSelect
              value={form.vessel_id}
              clientId={form.client_id}
              vessels={clientVessels}
              disabled={!form.client_id || isLocked}
              onChange={(vesselId) => {
                set('vessel_id', vesselId);
                set('requested_by_contact_id', '');
                const vessel = allVessels?.find(v => v.id === vesselId);
                if (vessel?.marina_id) set('marina_id', vessel.marina_id);
              }}
              onVesselCreated={(vessel) => {
                set('vessel_id', vessel.id);
                if (vessel.marina_id) set('marina_id', vessel.marina_id);
              }}
            />
          </div>
          <div>
            <Label>{t.serviceOrders.marina}</Label>
            <EntityCombobox
              value={form.marina_id}
              onChange={(v) => set('marina_id', v)}
              options={(marinas || []).filter((m) => m.active).map((m) => ({
                value: m.id,
                label: m.name,
                description: m.city || undefined,
              }))}
              placeholder="—"
              onCreate={(typed) => {
                setQuickMarinaName(typed);
                setQuickMarinaOpen(true);
              }}
              createLabel="+ Cadastrar nova marina"
            />
          </div>
          <div>
            <Label>{t.serviceOrders.requestedBy}</Label>
            {vesselContacts && vesselContacts.length > 0 ? (
              <Select
                value={form.requested_by_contact_id || 'none'}
                onValueChange={(v) => {
                  const contact = vesselContacts.find(c => c.id === v);
                  setForm(f => ({
                    ...f,
                    requested_by_contact_id: v === 'none' ? '' : v,
                    requested_by_name: contact?.full_name || '',
                  }));
                }}
                disabled={isLocked}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Selecionar contato" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">—</SelectItem>
                  {vesselContacts.map(c => (
                    <SelectItem key={c.id} value={c.id}>
                      <span className="flex items-center gap-1">
                        {c.full_name}
                        <span className="text-xs text-muted-foreground">
                          ({VESSEL_CONTACT_ROLES.find(r => r.value === c.role)?.label || c.role})
                        </span>
                      </span>
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            ) : (
              <div>
                <Input
                  value={form.requested_by_name}
                  onChange={e => set('requested_by_name', e.target.value)}
                  placeholder="Nome do solicitante"
                  disabled={isLocked}
                />
                {form.vessel_id && (
                  <p className="text-xs text-muted-foreground mt-1">
                    Cadastre contatos na embarcação para aparecerem aqui
                  </p>
                )}
              </div>
            )}
          </div>

          {/* Pedido do cliente: viaja até a NF-e ao faturar e sai no início das
              informações complementares da nota. */}
          <div>
            <Label>Ordem de compra do cliente</Label>
            <Input
              value={form.customer_po_number}
              onChange={e => set('customer_po_number', e.target.value)}
              placeholder="Ex.: 05447"
              maxLength={15}
              disabled={isLocked}
            />
            <p className="text-xs text-muted-foreground mt-1">
              Sai na NF-e ao faturar
            </p>
          </div>

          <div>
            <Label>Comprador</Label>
            <Input
              value={form.customer_buyer_name}
              onChange={e => set('customer_buyer_name', e.target.value)}
              placeholder="Ex.: Everton"
              disabled={isLocked}
            />
            <p className="text-xs text-muted-foreground mt-1">
              Em branco, usa o solicitante
            </p>
          </div>
        </div>
      </section>

      {/* C - Scheduling + Technicians (merged) */}
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
            {(appUsers || []).filter((u: any) =>
              u.id && u.id.trim() !== '' &&
              ['admin', 'technician', 'seller'].includes(u.role)
            ).map((u) => (
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

      {/* D - Problem & Technical (compact with collapsible) */}
      <section className="rounded-xl border bg-card p-5 shadow-sm space-y-4">
        <div className="flex items-center justify-between">
          <h2 className="font-semibold text-sm">{t.serviceOrders.problemDescription}</h2>
        </div>
        <div>
          <div className="flex items-center justify-between mb-1">
            <Label>{t.serviceOrders.problemDescription} *</Label>
            <div className="flex items-center gap-1">
              {/* Analisar vem primeiro porque é o que rende: reescrever deixa o
                  texto mais bonito, analisar transforma o texto em levantamento
                  meio pronto. O texto já diz o verbo, o sistema e metade das
                  respostas — até aqui ninguém lia. */}
              {onAnalisarDescricao && (
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  className="h-6 px-2 text-xs text-primary hover:text-primary hover:bg-primary/10"
                  onClick={() => onAnalisarDescricao(form.problem_description)}
                  disabled={analisandoDescricao || !form.problem_description || isLocked}
                >
                  <Sparkles className="h-3 w-3 mr-1" />
                  {analisandoDescricao ? 'Lendo…' : 'Analisar'}
                </Button>
              )}
              <Button
                type="button"
                variant="ghost"
                size="sm"
                className="h-6 px-2 text-xs text-muted-foreground hover:bg-muted"
                title="Reescrever o texto de forma mais técnica"
                onClick={async () => {
                  const optimized = await optimizeText(form.problem_description);
                  if (optimized) set('problem_description', optimized);
                }}
                disabled={isOptimizing || !form.problem_description || isLocked}
              >
                Reescrever
              </Button>
            </div>
          </div>
          <Textarea value={form.problem_description} onChange={(e) => set('problem_description', e.target.value)} rows={3} disabled={isLocked} />
        </div>
        <Collapsible>
          <CollapsibleTrigger asChild>
            <button type="button" className="flex items-center gap-2 text-sm font-medium text-muted-foreground hover:text-foreground transition-colors w-full text-left">
              <ChevronDown className="h-3.5 w-3.5 transition-transform [[data-state=open]>&]:rotate-180" />
              Observações para impressão (PDF)
            </button>
          </CollapsibleTrigger>
          <CollapsibleContent className="pt-2">
            <Textarea
              value={form.extra_notes || ''}
              onChange={e => set('extra_notes', e.target.value)}
              placeholder="Informações específicas para este cliente, condições especiais, garantias, prazos..."
              rows={2}
              disabled={isLocked}
            />
          </CollapsibleContent>
        </Collapsible>

        {/* Photos (Only if editing existing OS) */}
        {orderData?.id && (
          <Collapsible>
            <CollapsibleTrigger asChild>
              <button type="button" className="flex items-center gap-2 text-sm font-medium text-muted-foreground hover:text-foreground transition-colors w-full text-left">
                <ChevronDown className="h-3.5 w-3.5 transition-transform [[data-state=open]>&]:rotate-180" />
                <Camera className="h-3.5 w-3.5" />
                Fotos da OS
              </button>
            </CollapsibleTrigger>
            <CollapsibleContent className="pt-3">
              <ServiceOrderPhotos serviceOrderId={orderData.id} />
            </CollapsibleContent>
          </Collapsible>
        )}
      </section>
    </>
  );
}
