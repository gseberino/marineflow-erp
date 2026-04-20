import { useState, useEffect } from 'react';
import { useI18n } from '@/i18n';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useCreateVessel, useUpdateVessel } from '@/hooks/use-vessels';
import { useClients } from '@/hooks/use-clients';
import { useMarinas } from '@/hooks/use-marinas';
import { useVesselContacts, useCreateVesselContact, VESSEL_CONTACT_ROLES } from '@/hooks/use-vessel-contacts';
import { Badge } from '@/components/ui/badge';
import { Plus, Trash2 } from 'lucide-react';
import { toast } from 'sonner';
import type { Tables, TablesInsert } from '@/integrations/supabase/types';
import { maskPhone } from '@/lib/masks';

type Vessel = Tables<'vessels'>;

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  vessel?: Vessel | null;
  initialClientId?: string;
  onCreated?: (vessel: { id: string; boat_name: string; marina_id?: string | null }) => void;
}

const empty: TablesInsert<'vessels'> = {
  client_id: '',
  boat_name: '',
  manufacturer: '',
  model: '',
  year: undefined,
  hull_id_or_registration: '',
  length_feet: undefined,
  beam_feet: undefined,
  draft_feet: undefined,
  engine_type: '',
  engine_brand: '',
  engine_model: '',
  engine_quantity: 1,
  propulsion_type: '',
  shore_power_type: '',
  battery_bank_summary: '',
  inverter_charger_summary: '',
  navigation_electronics_summary: '',
  electrical_system_notes: '',
  current_dock_position: '',
  marina_id: undefined,
  active: true,
};

export function VesselFormDialog({ open, onOpenChange, vessel, initialClientId, onCreated }: Props) {
  const { t } = useI18n();
  const create = useCreateVessel();
  const update = useUpdateVessel();
  const { data: clients } = useClients();
  const { data: marinas } = useMarinas();
  const [form, setForm] = useState<TablesInsert<'vessels'>>(empty);
  const isEdit = !!vessel;

  useEffect(() => {
    if (vessel) {
      setForm({
        client_id: vessel.client_id,
        boat_name: vessel.boat_name,
        manufacturer: vessel.manufacturer ?? '',
        model: vessel.model ?? '',
        year: vessel.year ?? undefined,
        hull_id_or_registration: vessel.hull_id_or_registration ?? '',
        length_feet: vessel.length_feet ?? undefined,
        beam_feet: vessel.beam_feet ?? undefined,
        draft_feet: vessel.draft_feet ?? undefined,
        engine_type: vessel.engine_type ?? '',
        engine_brand: vessel.engine_brand ?? '',
        engine_model: vessel.engine_model ?? '',
        engine_quantity: vessel.engine_quantity ?? 1,
        propulsion_type: vessel.propulsion_type ?? '',
        shore_power_type: vessel.shore_power_type ?? '',
        battery_bank_summary: vessel.battery_bank_summary ?? '',
        inverter_charger_summary: vessel.inverter_charger_summary ?? '',
        navigation_electronics_summary: vessel.navigation_electronics_summary ?? '',
        electrical_system_notes: vessel.electrical_system_notes ?? '',
        current_dock_position: vessel.current_dock_position ?? '',
        marina_id: vessel.marina_id ?? undefined,
        active: vessel.active,
      });
    } else {
      setForm({ ...empty, client_id: initialClientId || '' });
    }
  }, [vessel, open, initialClientId]);

  const set = (key: string, value: any) => setForm(prev => ({ ...prev, [key]: value }));

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const selectedMarina = marinas?.find(m => m.id === form.marina_id);
      const payload = {
        ...form,
        current_marina_name_snapshot: selectedMarina?.marina_name ?? null,
      };
      if (isEdit && vessel) {
        await update.mutateAsync({ id: vessel.id, ...payload });
        toast.success(t.vessels.updateSuccess);
      } else {
        const result = await create.mutateAsync(payload);
        toast.success(t.vessels.createSuccess);
        if (onCreated && result) {
          onCreated({ id: result.id, boat_name: result.boat_name, marina_id: result.marina_id });
        }
      }
      onOpenChange(false);
    } catch (err: any) {
      const msg = err?.message || err?.details
        || 'Erro ao salvar embarcação.';
      toast.error(msg);
      console.error('VesselFormDialog error:', err);
    }
  };

  const isPending = create.isPending || update.isPending;
  const activeClients = clients?.filter(c => c.active) ?? [];
  const activeMarinas = marinas?.filter(m => m.active) ?? [];

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{isEdit ? t.vessels.editVessel : t.vessels.newVessel}</DialogTitle>
        </DialogHeader>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <div className="col-span-2">
              <Label>{t.vessels.selectClient} *</Label>
              <Select value={form.client_id} onValueChange={v => set('client_id', v)} required>
                <SelectTrigger><SelectValue placeholder={t.vessels.selectClient} /></SelectTrigger>
                <SelectContent>
                  {activeClients.map(c => (
                    <SelectItem key={c.id} value={c.id}>{c.full_name_or_company_name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="col-span-2">
              <Label>{t.vessels.boatName} *</Label>
              <Input required value={form.boat_name} onChange={e => set('boat_name', e.target.value)} />
            </div>
            <div>
              <Label>{t.vessels.manufacturer}</Label>
              <Input value={form.manufacturer ?? ''} onChange={e => set('manufacturer', e.target.value)} />
            </div>
            <div>
              <Label>{t.vessels.model}</Label>
              <Input value={form.model ?? ''} onChange={e => set('model', e.target.value)} />
            </div>
            <div>
              <Label>{t.vessels.year}</Label>
              <Input type="number" value={form.year ?? ''} onChange={e => set('year', e.target.value ? Number(e.target.value) : undefined)} />
            </div>
            <div>
              <Label>{t.vessels.hullId}</Label>
              <Input value={form.hull_id_or_registration ?? ''} onChange={e => set('hull_id_or_registration', e.target.value)} />
            </div>
            <div>
              <Label>{t.vessels.length} (ft)</Label>
              <Input type="number" step="0.01" value={form.length_feet ?? ''} onChange={e => set('length_feet', e.target.value ? Number(e.target.value) : undefined)} />
            </div>
            <div>
              <Label>{t.vessels.beam} (ft)</Label>
              <Input type="number" step="0.01" value={form.beam_feet ?? ''} onChange={e => set('beam_feet', e.target.value ? Number(e.target.value) : undefined)} />
            </div>
            <div>
              <Label>{t.vessels.draft} (ft)</Label>
              <Input type="number" step="0.01" value={form.draft_feet ?? ''} onChange={e => set('draft_feet', e.target.value ? Number(e.target.value) : undefined)} />
            </div>
            <div>
              <Label>{t.vessels.engineType}</Label>
              <Input value={form.engine_type ?? ''} onChange={e => set('engine_type', e.target.value)} />
            </div>
            <div>
              <Label>{t.vessels.engineBrand}</Label>
              <Input value={form.engine_brand ?? ''} onChange={e => set('engine_brand', e.target.value)} />
            </div>
            <div>
              <Label>{t.vessels.engineModel}</Label>
              <Input value={form.engine_model ?? ''} onChange={e => set('engine_model', e.target.value)} />
            </div>
            <div>
              <Label>{t.vessels.engineQuantity}</Label>
              <Input type="number" min={1} value={form.engine_quantity ?? 1} onChange={e => set('engine_quantity', Number(e.target.value))} />
            </div>
            <div>
              <Label>{t.vessels.propulsionType}</Label>
              <Input value={form.propulsion_type ?? ''} onChange={e => set('propulsion_type', e.target.value)} />
            </div>
            <div>
              <Label>{t.vessels.shorePower}</Label>
              <Input value={form.shore_power_type ?? ''} onChange={e => set('shore_power_type', e.target.value)} />
            </div>
            <div className="col-span-2">
              <Label>{t.vessels.selectMarina}</Label>
              <Select value={form.marina_id ?? 'none'} onValueChange={v => set('marina_id', v === 'none' ? null : v)}>
                <SelectTrigger><SelectValue placeholder={t.vessels.selectMarina} /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">—</SelectItem>
                  {activeMarinas.map(m => (
                    <SelectItem key={m.id} value={m.id}>{m.marina_name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label>{t.vessels.dockPosition}</Label>
              <Input value={form.current_dock_position ?? ''} onChange={e => set('current_dock_position', e.target.value)} />
            </div>
            <div className="col-span-2">
              <Label>{t.vessels.batteryBank}</Label>
              <Textarea value={form.battery_bank_summary ?? ''} onChange={e => set('battery_bank_summary', e.target.value)} />
            </div>
            <div className="col-span-2">
              <Label>{t.vessels.inverterCharger}</Label>
              <Textarea value={form.inverter_charger_summary ?? ''} onChange={e => set('inverter_charger_summary', e.target.value)} />
            </div>
            <div className="col-span-2">
              <Label>{t.vessels.navigationElectronics}</Label>
              <Textarea value={form.navigation_electronics_summary ?? ''} onChange={e => set('navigation_electronics_summary', e.target.value)} />
            </div>
            <div className="col-span-2">
              <Label>{t.vessels.electricalSystemNotes}</Label>
              <Textarea value={form.electrical_system_notes ?? ''} onChange={e => set('electrical_system_notes', e.target.value)} />
            </div>
            <div className="flex items-center gap-2 col-span-2">
              <Switch checked={form.active ?? true} onCheckedChange={v => set('active', v)} />
              <Label>{t.common.active}</Label>
            </div>
          </div>

          {/* Vessel Contacts - only when editing */}
          {isEdit && vessel && <VesselContactsSection vesselId={vessel.id} />}

          <div className="flex justify-end gap-2 pt-2">
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>{t.common.cancel}</Button>
            <Button type="submit" disabled={isPending}>{t.common.save}</Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}

function VesselContactsSection({ vesselId }: { vesselId: string }) {
  const { data: contacts, isLoading } = useVesselContacts(vesselId);
  const createContact = useCreateVesselContact();
  const [showForm, setShowForm] = useState(false);
  const [contactForm, setContactForm] = useState({
    full_name: '', role: 'owner', phone: '', email: '',
  });

  const handleAdd = async () => {
    if (!contactForm.full_name) {
      toast.error('Nome é obrigatório');
      return;
    }
    try {
      await createContact.mutateAsync({
        vessel_id: vesselId,
        full_name: contactForm.full_name,
        role: contactForm.role,
        phone: contactForm.phone || undefined,
        email: contactForm.email || undefined,
      });
      setContactForm({ full_name: '', role: 'owner', phone: '', email: '' });
      setShowForm(false);
      toast.success('Contato adicionado');
    } catch (e: any) {
      toast.error(e.message || 'Erro');
    }
  };

  return (
    <div className="col-span-2 border-t pt-4 space-y-3">
      <div className="flex items-center justify-between">
        <Label className="text-sm font-semibold">Contatos da Embarcação</Label>
        <Button type="button" variant="outline" size="sm" onClick={() => setShowForm(!showForm)} className="gap-1">
          <Plus className="h-3 w-3" /> Contato
        </Button>
      </div>

      {showForm && (
        <div className="grid grid-cols-2 gap-3 p-3 rounded-lg border bg-muted/30">
          <div>
            <Label className="text-xs">Nome *</Label>
            <Input value={contactForm.full_name} onChange={e => setContactForm(p => ({ ...p, full_name: e.target.value }))} />
          </div>
          <div>
            <Label className="text-xs">Função</Label>
            <Select value={contactForm.role} onValueChange={v => setContactForm(p => ({ ...p, role: v }))}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {VESSEL_CONTACT_ROLES.map(r => (
                  <SelectItem key={r.value} value={r.value}>{r.label}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div>
            <Label className="text-xs">Telefone</Label>
            <Input value={contactForm.phone} onChange={e => setContactForm(p => ({ ...p, phone: maskPhone(e.target.value) }))} placeholder="(47) 99999-9999" maxLength={15} />
          </div>
          <div>
            <Label className="text-xs">Email</Label>
            <Input type="email" value={contactForm.email} onChange={e => setContactForm(p => ({ ...p, email: e.target.value }))} />
          </div>
          <div className="col-span-2 flex gap-2">
            <Button type="button" size="sm" onClick={handleAdd} disabled={createContact.isPending}>Salvar</Button>
            <Button type="button" size="sm" variant="outline" onClick={() => setShowForm(false)}>Cancelar</Button>
          </div>
        </div>
      )}

      {isLoading ? (
        <p className="text-sm text-muted-foreground">Carregando...</p>
      ) : contacts && contacts.length > 0 ? (
        <div className="space-y-1">
          {contacts.map(c => (
            <div key={c.id} className="flex items-center gap-2 text-sm py-1.5 px-2 rounded hover:bg-muted/50">
              <span className="font-medium">{c.full_name}</span>
              <Badge variant="secondary" className="text-xs">
                {VESSEL_CONTACT_ROLES.find(r => r.value === c.role)?.label || c.role}
              </Badge>
              {c.phone && <span className="text-muted-foreground text-xs">{c.phone}</span>}
              {c.email && <span className="text-muted-foreground text-xs">{c.email}</span>}
            </div>
          ))}
        </div>
      ) : (
        <p className="text-sm text-muted-foreground">Nenhum contato cadastrado</p>
      )}
    </div>
  );
}
