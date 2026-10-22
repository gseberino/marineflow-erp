import { useState, useEffect } from 'react';
import { useI18n } from '@/i18n';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Select, SelectContent, SelectGroup, SelectItem, SelectLabel, SelectTrigger, SelectValue } from '@/components/ui/select';
import { EntityCombobox } from '@/components/EntityCombobox';
import { useCreateVessel, useUpdateVessel } from '@/hooks/use-vessels';
import { useClients } from '@/hooks/use-clients';
import { useMarinas } from '@/hooks/use-marinas';
import { useVesselContacts, useCreateVesselContact, VESSEL_CONTACT_ROLES } from '@/hooks/use-vessel-contacts';
import { Badge } from '@/components/ui/badge';
import { Plus, Trash2 } from 'lucide-react';
import { toast } from 'sonner';
import type { Tables, TablesInsert } from '@/integrations/supabase/types';
import { maskPhone } from '@/lib/masks';
import {
  TIPOS_DE_UNIDADE, camposDoTipo, metrosParaPes, pesParaMetros, rotuloDaIdentificacao, tipoDoSeletor, unidadeNaFrase,
} from '@/lib/unidade';

type Vessel = Tables<'vessels'>;

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  vessel?: Vessel | null;
  initialClientId?: string;
  onCreated?: (vessel: { id: string; name: string; marina_id?: string | null; access_notes?: string | null }) => void;
}

const empty: TablesInsert<'vessels'> = {
  client_id: '',
  name: '',
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
  asset_type: '',
  access_notes: '',
};

export function VesselFormDialog({ open, onOpenChange, vessel, initialClientId, onCreated }: Props) {
  const { t } = useI18n();
  const create = useCreateVessel();
  const update = useUpdateVessel();
  const { data: clients } = useClients();
  const { data: marinas } = useMarinas();
  const [form, setForm] = useState<TablesInsert<'vessels'>>(empty);
  // Comprimento em metros (veículo) como foi digitado. null = ninguém mexeu: mostra o que está
  // gravado em pés, convertido, e o length_feet segue o mesmo — abrir e salvar não regrava a medida.
  const [metrosDigitados, setMetrosDigitados] = useState<string | null>(null);
  const isEdit = !!vessel;

  useEffect(() => {
    if (vessel) {
      setForm({
        client_id: vessel.client_id,
        name: vessel.name ?? '',
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
        // O valor do seletor: "Jet Ski" antigo aparece como "Moto aquática" (e grava assim se salvar);
        // "Outro" sem grupo fica vazio, para escolher (decisão do dono, 22/10/2026).
        asset_type: tipoDoSeletor(vessel.asset_type),
        access_notes: vessel.access_notes ?? '',
      });
    } else {
      setForm({ ...empty, client_id: initialClientId || '' });
    }
    setMetrosDigitados(null);
  }, [vessel, open, initialClientId]);

  const set = (key: string, value: any) => setForm(prev => ({ ...prev, [key]: value }));

  // Os campos pelo tipo escolhido (dono, 22/10/2026: "ajustar conforme cada tipo"). Os que somem
  // só deixam de aparecer: o que já está gravado neles volta igual ao salvar.
  const campos = camposDoTipo(form.asset_type);
  // Tipo gravado que a lista não tem: vira opção, senão o campo aparece vazio. Sai do cadastro (e
  // não do formulário) para a opção já existir quando o valor chega — o select escondido do Radix
  // devolve '' para valor sem opção, e isso apagava o tipo ao abrir.
  const tipoGravado = tipoDoSeletor(vessel?.asset_type);
  const tipoForaDaLista = tipoGravado && !TIPOS_DE_UNIDADE.some(g => g.tipos.some(x => x.valor === tipoGravado)) ? tipoGravado : null;
  const pesGravados = form.length_feet == null ? NaN : Number(form.length_feet);
  const comprimentoEmMetros = metrosDigitados ?? (Number.isFinite(pesGravados) ? String(pesParaMetros(pesGravados)) : '');
  const mudarMetros = (texto: string) => {
    setMetrosDigitados(texto);
    const n = Number(texto.replace(',', '.'));
    // null, não undefined: undefined some do PATCH e a medida antiga ficava no banco.
    set('length_feet', texto.trim() && Number.isFinite(n) ? metrosParaPes(n) : null);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.asset_type) {
      toast.error('Escolha o tipo (lancha, motorhome, trailer…).');
      return;
    }
    try {
      const selectedMarina = marinas?.find(m => m.id === form.marina_id);
      const payload = {
        ...form,
        current_marina_name_snapshot: selectedMarina?.name ?? null,
      };
      if (isEdit && vessel) {
        await update.mutateAsync({ id: vessel.id, ...payload });
        toast.success(t.vessels.updateSuccess);
      } else {
        const result = await create.mutateAsync(payload);
        toast.success(t.vessels.createSuccess);
        if (onCreated && result) {
          // O local e acesso vai junto: a OS o sugere no campo dela, como faz ao escolher o barco.
          onCreated({ id: result.id, name: result.name, marina_id: result.marina_id, access_notes: result.access_notes });
        }
      }
      onOpenChange(false);
    } catch (err: any) {
      const msg = err?.message || err?.details
        || 'Erro ao salvar o cadastro.';
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
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div className="col-span-2 sm:col-span-1">
              <Label htmlFor="cadastro-tipo">Tipo *</Label>
              {/* Sem tipo pré-escolhido: o padrão "Lancha" transformava van e picape em
                  lancha (HOMEBUS, Iveco e Hilux, achados em 01/10/2026). A lista vem da regra única,
                  por grupo (decisão do dono, 22/10/2026); a dica ("inclui van convertida") só aparece
                  dentro da lista — o campo fechado mostra o tipo sozinho. */}
              <Select
                value={form.asset_type || undefined}
                // '' nunca é escolha de quem usa (é o select escondido do Radix sem a opção): ignora.
                onValueChange={v => { if (!v) return; set('asset_type', v); setMetrosDigitados(null); }}
              >
                <SelectTrigger id="cadastro-tipo" aria-label="Tipo">
                  <SelectValue placeholder="Escolha o tipo">{form.asset_type}</SelectValue>
                </SelectTrigger>
                <SelectContent>
                  {tipoForaDaLista && (
                    <SelectGroup>
                      <SelectLabel>Cadastrado como</SelectLabel>
                      <SelectItem value={tipoForaDaLista}>{tipoForaDaLista}</SelectItem>
                    </SelectGroup>
                  )}
                  {TIPOS_DE_UNIDADE.map(g => (
                    <SelectGroup key={g.grupo}>
                      <SelectLabel>{g.grupo}</SelectLabel>
                      {g.tipos.map(x => (
                        <SelectItem key={x.valor} value={x.valor} textValue={x.valor}>
                          {x.valor}
                          {x.dica && <span className="text-muted-foreground"> — {x.dica}</span>}
                        </SelectItem>
                      ))}
                    </SelectGroup>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="col-span-2 sm:col-span-1">
              <Label>Nome ou identificação *</Label>
              <Input required value={form.name ?? ''} onChange={e => set('name', e.target.value)} />
            </div>
            <div className="col-span-2">
              <Label>{t.vessels.selectClient} *</Label>
              <EntityCombobox
                value={form.client_id}
                onChange={v => set('client_id', v)}
                placeholder={t.vessels.selectClient}
                options={activeClients.map(c => ({
                  value: c.id,
                  label: c.name,
                  description: c.cpf_cnpj || undefined,
                  searchTerms: [c.cpf_cnpj || '', c.email || ''],
                }))}
              />
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
              <Input type="number" value={form.year ?? ''} onChange={e => set('year', e.target.value ? Number(e.target.value) : null)} />
            </div>
            <div>
              {/* Pelo tipo escolhido: placa (motorhome, trailer, camper), inscrição (barco), nº de série. */}
              <Label>{rotuloDaIdentificacao(form.asset_type)}</Label>
              <Input value={form.hull_id_or_registration ?? ''} onChange={e => set('hull_id_or_registration', e.target.value)} />
            </div>
            {/* O banco guarda em pés (length_feet). Barco digita em pés; veículo em metros, convertido
                ao salvar; equipamento não tem comprimento. */}
            {campos.comprimento === 'pes' && (
              <div>
                <Label htmlFor="cadastro-comprimento">{t.vessels.length} (pés)</Label>
                <Input id="cadastro-comprimento" type="number" step="0.01" value={form.length_feet ?? ''} onChange={e => set('length_feet', e.target.value ? Number(e.target.value) : null)} />
              </div>
            )}
            {campos.comprimento === 'metros' && (
              <div>
                <Label htmlFor="cadastro-comprimento">{t.vessels.length} (m)</Label>
                <Input id="cadastro-comprimento" type="number" step="0.01" min={0} value={comprimentoEmMetros} onChange={e => mudarMetros(e.target.value)} />
              </div>
            )}
            {campos.nauticos && (
              <>
                <div>
                  <Label htmlFor="cadastro-boca">{t.vessels.beam} (pés)</Label>
                  <Input id="cadastro-boca" type="number" step="0.01" value={form.beam_feet ?? ''} onChange={e => set('beam_feet', e.target.value ? Number(e.target.value) : null)} />
                </div>
                <div>
                  <Label htmlFor="cadastro-calado">{t.vessels.draft} (pés)</Label>
                  <Input id="cadastro-calado" type="number" step="0.01" value={form.draft_feet ?? ''} onChange={e => set('draft_feet', e.target.value ? Number(e.target.value) : null)} />
                </div>
              </>
            )}
            {campos.motores && (
              <>
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
              </>
            )}
            {campos.nauticos && (
              <div>
                <Label htmlFor="cadastro-propulsao">{t.vessels.propulsionType}</Label>
                <Input id="cadastro-propulsao" value={form.propulsion_type ?? ''} onChange={e => set('propulsion_type', e.target.value)} />
              </div>
            )}
            <div>
              {/* "Energia de cais" no barco; "Energia externa (tomada ou camping)" no veículo. */}
              <Label htmlFor="cadastro-energia">{campos.rotuloEnergiaExterna}</Label>
              <Input id="cadastro-energia" value={form.shore_power_type ?? ''} onChange={e => set('shore_power_type', e.target.value)} />
            </div>
            <div className="col-span-2">
              {/* "Marina" no barco; "Onde fica" no veículo e no equipamento. */}
              <Label>{campos.rotuloOndeFica}</Label>
              <EntityCombobox
                value={form.marina_id ?? ''}
                onChange={v => set('marina_id', v || null)}
                placeholder={campos.nauticos ? t.vessels.selectMarina : 'Selecionar local'}
                options={[
                  { value: '', label: '—' },
                  ...activeMarinas.map(m => ({
                    value: m.id,
                    label: m.name,
                    description: m.city || undefined,
                  })),
                ]}
              />
            </div>
            {campos.nauticos && (
              <div>
                <Label htmlFor="cadastro-pier">{t.vessels.dockPosition}</Label>
                <Input id="cadastro-pier" value={form.current_dock_position ?? ''} onChange={e => set('current_dock_position', e.target.value)} />
              </div>
            )}
            {/* Sugerido em cada OS nova deste veículo e impresso na via do técnico. */}
            <div className="col-span-2">
              <Label htmlFor="veiculo-acesso">Local e acesso</Label>
              <Textarea
                id="veiculo-acesso"
                value={form.access_notes ?? ''}
                onChange={e => set('access_notes', e.target.value)}
                placeholder="Onde fica guardado, como entrar, onde está a chave, portaria, horário"
              />
              <p className="mt-1 text-xs text-muted-foreground">Vem sugerido em cada OS nova e sai na via do técnico.</p>
            </div>
            <div className="col-span-2">
              <Label>{t.vessels.batteryBank}</Label>
              <Textarea value={form.battery_bank_summary ?? ''} onChange={e => set('battery_bank_summary', e.target.value)} />
            </div>
            <div className="col-span-2">
              <Label>{t.vessels.inverterCharger}</Label>
              <Textarea value={form.inverter_charger_summary ?? ''} onChange={e => set('inverter_charger_summary', e.target.value)} />
            </div>
            {campos.nauticos && (
              <div className="col-span-2">
                <Label htmlFor="cadastro-eletronica">{t.vessels.navigationElectronics}</Label>
                <Textarea id="cadastro-eletronica" value={form.navigation_electronics_summary ?? ''} onChange={e => set('navigation_electronics_summary', e.target.value)} />
              </div>
            )}
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
          {isEdit && vessel && <VesselContactsSection vesselId={vessel.id} tipo={form.asset_type} />}

          <div className="flex justify-end gap-2 pt-2">
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>{t.common.cancel}</Button>
            <Button type="submit" disabled={isPending}>{t.common.save}</Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}

function VesselContactsSection({ vesselId, tipo }: { vesselId: string; tipo?: string | null }) {
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
        {/* "Contatos do motorhome", "Contatos da lancha"; sem tipo, o termo geral. */}
        <Label className="text-sm font-semibold">Contatos {unidadeNaFrase({ asset_type: tipo }, 'de')}</Label>
        <Button type="button" variant="outline" size="sm" onClick={() => setShowForm(!showForm)} className="gap-1">
          <Plus className="h-3 w-3" /> Contato
        </Button>
      </div>

      {showForm && (
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 p-3 rounded-lg border bg-muted/30">
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
