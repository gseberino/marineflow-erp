import { useEffect, useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Checkbox } from '@/components/ui/checkbox';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { EntityCombobox } from '@/components/EntityCombobox';
import { Loader2, Trash2, Plus, X, ListChecks, CalendarClock } from 'lucide-react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import {
  useSaveAgendaTask,
  useDeleteAgendaTask,
  useActiveUsers,
  useTaskReminders,
  type AgendaTaskInput,
  type RelatedEntityType,
  type ReminderInput,
} from '@/hooks/use-agenda';
import { useClients } from '@/hooks/use-clients';

function toLocalDateInput(d: Date) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}
function toLocalTime(iso: string | null | undefined, fallback: string) {
  if (!iso) return fallback;
  const d = new Date(iso);
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
}

export type ExistingTask = {
  id: string;
  title: string;
  description?: string | null;
  kind?: string;
  assignee_user_id: string | null;
  scheduled_start_at: string | null;
  scheduled_end_at: string | null;
  due_at?: string | null;
  priority: string;
  status: string;
  location?: string | null;
  client_id?: string | null;
  notes?: string | null;
  is_private?: boolean;
  related_entity_type?: string | null;
  related_entity_id?: string | null;
  checklist?: { text: string; done: boolean }[];
};

type ChecklistItem = { text: string; done: boolean };

const REMINDER_PRESETS: { key: string; label: string; compute: (anchorISO: string) => string }[] = [
  { key: '30m', label: '30 min antes', compute: (a) => new Date(new Date(a).getTime() - 30 * 60000).toISOString() },
  { key: '2h', label: '2 h antes', compute: (a) => new Date(new Date(a).getTime() - 120 * 60000).toISOString() },
  { key: '1d', label: '1 dia antes', compute: (a) => new Date(new Date(a).getTime() - 24 * 3600000).toISOString() },
];

// Entidades vinculáveis pelo dialog (as demais chegam via motor/IA e só são exibidas)
const LINKABLE: { value: RelatedEntityType | ''; label: string }[] = [
  { value: '', label: 'Sem vínculo' },
  { value: 'service_order', label: 'Ordem de serviço' },
  { value: 'external_quote', label: 'Orçamento externo' },
  { value: 'client', label: 'Cliente' },
  { value: 'purchase_order', label: 'Ordem de compra' },
];

function useEntityOptions(type: RelatedEntityType | '') {
  const [options, setOptions] = useState<{ value: string; label: string }[]>([]);
  useEffect(() => {
    let cancelled = false;
    async function load() {
      if (!type) { setOptions([]); return; }
      let rows: { value: string; label: string }[] = [];
      if (type === 'service_order') {
        const { data } = await supabase
          .from('service_orders')
          .select('id, service_order_number, clients(name)')
          .neq('status', 'cancelled')
          .order('created_at', { ascending: false })
          .limit(200);
        rows = (data || []).map((o: any) => ({ value: o.id, label: `${o.service_order_number} — ${o.clients?.name || '—'}` }));
      } else if (type === 'external_quote') {
        const { data } = await supabase
          .from('external_quotes')
          .select('id, quote_number, status')
          .order('created_at', { ascending: false })
          .limit(200);
        rows = (data || []).map((q: any) => ({ value: q.id, label: q.quote_number }));
      } else if (type === 'client') {
        const { data } = await supabase
          .from('clients')
          .select('id, name')
          .order('name')
          .limit(500);
        rows = (data || []).map((c: any) => ({ value: c.id, label: c.name }));
      } else if (type === 'purchase_order') {
        const { data } = await supabase
          .from('purchase_orders')
          .select('id, po_number, status')
          .order('created_at', { ascending: false })
          .limit(200);
        rows = (data || []).map((p: any) => ({ value: p.id, label: p.po_number }));
      }
      if (!cancelled) setOptions(rows);
    }
    load();
    return () => { cancelled = true; };
  }, [type]);
  return options;
}

export function AgendaTaskDialog({
  open,
  onOpenChange,
  prefillTechnicianId,
  prefillDate,
  existing,
  prefillEntity,
}: {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  /** compat: chamadas antigas passavam a lista de técnicos — não é mais usada */
  technicians?: { id: string; full_name: string }[];
  prefillTechnicianId?: string;
  prefillDate?: string;
  existing?: ExistingTask | null;
  prefillEntity?: { type: RelatedEntityType; id: string } | null;
}) {
  const save = useSaveAgendaTask();
  const del = useDeleteAgendaTask();
  const { data: users = [] } = useActiveUsers();
  const { data: clients = [] } = useClients();
  const { data: existingReminders = [] } = useTaskReminders(existing?.id);

  const [kind, setKind] = useState<'task' | 'appointment'>('task');
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [assigneeId, setAssigneeId] = useState('');
  const [date, setDate] = useState('');
  const [startTime, setStartTime] = useState('09:00');
  const [endTime, setEndTime] = useState('10:00');
  const [dueDate, setDueDate] = useState('');
  const [priority, setPriority] = useState('normal');
  const [status, setStatus] = useState('pending');
  const [location, setLocation] = useState('');
  const [clientId, setClientId] = useState<string>('');
  const [notes, setNotes] = useState('');
  const [isPrivate, setIsPrivate] = useState(false);
  const [entityType, setEntityType] = useState<RelatedEntityType | ''>('');
  const [entityId, setEntityId] = useState('');
  const [checklist, setChecklist] = useState<ChecklistItem[]>([]);
  const [newItem, setNewItem] = useState('');
  const [reminderKeys, setReminderKeys] = useState<string[]>([]);

  const entityOptions = useEntityOptions(entityType);

  useEffect(() => {
    if (!open) return;
    if (existing) {
      setKind((existing.kind as any) || (existing.scheduled_start_at ? 'appointment' : 'task'));
      setTitle(existing.title);
      setDescription(existing.description || '');
      setAssigneeId(existing.assignee_user_id || '');
      const startDate = existing.scheduled_start_at ? new Date(existing.scheduled_start_at) : null;
      setDate(startDate ? toLocalDateInput(startDate) : (prefillDate || toLocalDateInput(new Date())));
      setStartTime(toLocalTime(existing.scheduled_start_at, '09:00'));
      setEndTime(toLocalTime(existing.scheduled_end_at, '10:00'));
      setDueDate(existing.due_at ? toLocalDateInput(new Date(existing.due_at)) : '');
      setPriority(existing.priority || 'normal');
      setStatus(existing.status || 'pending');
      setLocation(existing.location || '');
      setClientId(existing.client_id || '');
      setNotes(existing.notes || '');
      setIsPrivate(!!existing.is_private);
      setEntityType((existing.related_entity_type as any) || '');
      setEntityId(existing.related_entity_id || '');
      setChecklist(Array.isArray(existing.checklist) ? existing.checklist : []);
      setReminderKeys([]); // presets não são re-derivados; lembretes existentes ficam
    } else {
      setKind('task');
      setTitle('');
      setDescription('');
      setAssigneeId(prefillTechnicianId || '');
      setDate(prefillDate || toLocalDateInput(new Date()));
      setStartTime('09:00');
      setEndTime('10:00');
      setDueDate(prefillDate || toLocalDateInput(new Date()));
      setPriority('normal');
      setStatus('pending');
      setLocation('');
      setClientId('');
      setNotes('');
      setIsPrivate(false);
      setEntityType(prefillEntity?.type || '');
      setEntityId(prefillEntity?.id || '');
      setChecklist([]);
      setReminderKeys([]);
    }
    setNewItem('');
  }, [open, existing, prefillTechnicianId, prefillDate, prefillEntity]);

  const handleSave = async () => {
    if (!title.trim()) {
      toast.error('Informe um título para a tarefa');
      return;
    }
    if (kind === 'appointment' && (!date || !startTime)) {
      toast.error('Compromisso precisa de data e hora de início');
      return;
    }

    const startISO = kind === 'appointment' && date && startTime
      ? new Date(`${date}T${startTime}:00`).toISOString() : null;
    const endISO = kind === 'appointment' && date && endTime
      ? new Date(`${date}T${endTime}:00`).toISOString() : null;
    const dueISO = kind === 'task' && dueDate
      ? new Date(`${dueDate}T08:00:00`).toISOString() : null;

    // Lembretes: presets ancoram no início do compromisso ou no due (08h)
    const anchor = startISO || dueISO;
    let reminders: ReminderInput[] | undefined;
    if (reminderKeys.length > 0 && anchor) {
      reminders = reminderKeys
        .map((k) => REMINDER_PRESETS.find((p) => p.key === k))
        .filter(Boolean)
        .map((p) => ({ remind_at: p!.compute(anchor), channel: 'app' as const }))
        .filter((r) => new Date(r.remind_at) > new Date());
    }

    const payload: AgendaTaskInput = {
      id: existing?.id,
      title: title.trim(),
      description: description.trim() || null,
      kind,
      assignee_user_id: assigneeId || null,
      scheduled_start_at: startISO,
      scheduled_end_at: endISO,
      due_at: dueISO,
      priority,
      status,
      location: location.trim() || null,
      client_id: clientId || null,
      notes: notes.trim() || null,
      is_private: isPrivate,
      related_entity_type: entityType || null,
      related_entity_id: entityType && entityId ? entityId : null,
      checklist,
      reminders,
    };

    try {
      await save.mutateAsync(payload);
      toast.success(existing ? 'Tarefa atualizada' : 'Tarefa criada');
      onOpenChange(false);
    } catch (e: any) {
      toast.error(e?.message || 'Erro ao salvar tarefa');
    }
  };

  const handleDelete = async () => {
    if (!existing?.id) return;
    if (!confirm('Excluir esta tarefa?')) return;
    try {
      await del.mutateAsync(existing.id);
      toast.success('Tarefa excluída');
      onOpenChange(false);
    } catch (e: any) {
      toast.error(e?.message || 'Erro ao excluir');
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle>{existing ? 'Editar tarefa' : 'Nova tarefa'}</DialogTitle>
        </DialogHeader>

        <div className="space-y-4 max-h-[70vh] overflow-y-auto pr-1">
          <div className="flex items-center gap-1 rounded-md border p-1 w-fit">
            <Button size="sm" type="button" variant={kind === 'task' ? 'default' : 'ghost'} onClick={() => setKind('task')}>
              <ListChecks className="h-4 w-4 mr-1" /> Tarefa
            </Button>
            <Button size="sm" type="button" variant={kind === 'appointment' ? 'default' : 'ghost'} onClick={() => setKind('appointment')}>
              <CalendarClock className="h-4 w-4 mr-1" /> Compromisso
            </Button>
          </div>

          <div className="space-y-2">
            <Label>Título *</Label>
            <Input
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder={kind === 'task' ? 'Ex.: Cobrar entrega da bomba d’água' : 'Ex.: Visita técnica na marina'}
            />
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div className="space-y-2">
              <Label>Responsável</Label>
              <EntityCombobox
                value={assigneeId}
                onChange={setAssigneeId}
                placeholder="Sem responsável"
                options={[
                  { value: '', label: 'Sem responsável' },
                  ...users.map((u: any) => ({ value: u.id, label: u.full_name })),
                ]}
              />
            </div>
            {kind === 'task' ? (
              <div className="space-y-2">
                <Label>Prazo (vencimento)</Label>
                <Input type="date" value={dueDate} onChange={(e) => setDueDate(e.target.value)} />
              </div>
            ) : (
              <div className="grid grid-cols-3 gap-2">
                <div className="space-y-2 col-span-1">
                  <Label>Data *</Label>
                  <Input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
                </div>
                <div className="space-y-2">
                  <Label>Início *</Label>
                  <Input type="time" value={startTime} onChange={(e) => setStartTime(e.target.value)} />
                </div>
                <div className="space-y-2">
                  <Label>Fim</Label>
                  <Input type="time" value={endTime} onChange={(e) => setEndTime(e.target.value)} />
                </div>
              </div>
            )}
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div className="space-y-2">
              <Label>Vincular a</Label>
              <div className="grid grid-cols-2 gap-2">
                <Select value={entityType || 'none'} onValueChange={(v) => { setEntityType(v === 'none' ? '' : (v as RelatedEntityType)); setEntityId(''); }}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {LINKABLE.map((o) => (
                      <SelectItem key={o.value || 'none'} value={o.value || 'none'}>{o.label}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                {entityType && (
                  <EntityCombobox
                    value={entityId}
                    onChange={setEntityId}
                    placeholder="Selecionar…"
                    options={entityOptions}
                  />
                )}
              </div>
            </div>
            <div className="space-y-2">
              <Label>Cliente (opcional)</Label>
              <EntityCombobox
                value={clientId}
                onChange={setClientId}
                placeholder="Sem cliente"
                options={[
                  { value: '', label: 'Sem cliente' },
                  ...clients.map((c: any) => ({ value: c.id, label: c.name })),
                ]}
              />
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            <div className="space-y-2">
              <Label>Prioridade</Label>
              <Select value={priority} onValueChange={setPriority}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="low">Baixa</SelectItem>
                  <SelectItem value="normal">Normal</SelectItem>
                  <SelectItem value="high">Alta</SelectItem>
                  <SelectItem value="urgent">Urgente</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label>Status</Label>
              <Select value={status} onValueChange={setStatus}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="pending">Pendente</SelectItem>
                  <SelectItem value="in_progress">Em andamento</SelectItem>
                  <SelectItem value="done">Concluída</SelectItem>
                  <SelectItem value="cancelled">Cancelada</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label>Local</Label>
              <Input value={location} onChange={(e) => setLocation(e.target.value)} placeholder="Marina, endereço…" />
            </div>
          </div>

          <div className="space-y-2">
            <Label>Checklist</Label>
            <div className="space-y-1.5">
              {checklist.map((item, i) => (
                <div key={i} className="flex items-center gap-2">
                  <Checkbox
                    checked={item.done}
                    onCheckedChange={(v) => setChecklist((c) => c.map((x, j) => j === i ? { ...x, done: v === true } : x))}
                  />
                  <span className={item.done ? 'text-sm line-through text-muted-foreground flex-1' : 'text-sm flex-1'}>
                    {item.text}
                  </span>
                  <Button type="button" size="icon" variant="ghost" className="h-6 w-6"
                    onClick={() => setChecklist((c) => c.filter((_, j) => j !== i))}>
                    <X className="h-3.5 w-3.5" />
                  </Button>
                </div>
              ))}
              <div className="flex items-center gap-2">
                <Input
                  value={newItem}
                  onChange={(e) => setNewItem(e.target.value)}
                  placeholder="Novo item…"
                  className="h-8"
                  onKeyDown={(e) => {
                    if (e.key === 'Enter' && newItem.trim()) {
                      e.preventDefault();
                      setChecklist((c) => [...c, { text: newItem.trim(), done: false }]);
                      setNewItem('');
                    }
                  }}
                />
                <Button type="button" size="icon" variant="outline" className="h-8 w-8" disabled={!newItem.trim()}
                  onClick={() => { setChecklist((c) => [...c, { text: newItem.trim(), done: false }]); setNewItem(''); }}>
                  <Plus className="h-4 w-4" />
                </Button>
              </div>
            </div>
          </div>

          <div className="space-y-2">
            <Label>Lembrete (no app)</Label>
            <div className="flex flex-wrap gap-2">
              {REMINDER_PRESETS.map((p) => {
                const active = reminderKeys.includes(p.key);
                return (
                  <Button key={p.key} type="button" size="sm" variant={active ? 'default' : 'outline'}
                    onClick={() => setReminderKeys((ks) => active ? ks.filter((k) => k !== p.key) : [...ks, p.key])}>
                    {p.label}
                  </Button>
                );
              })}
              {existing && existingReminders.length > 0 && (
                <span className="text-xs text-muted-foreground self-center">
                  {existingReminders.length} lembrete(s) já agendado(s)
                </span>
              )}
            </div>
            <p className="text-[11px] text-muted-foreground">
              {kind === 'appointment' ? 'Relativo ao início do compromisso.' : 'Relativo ao prazo (8h da manhã do vencimento).'}
              {' '}Selecionar presets substitui os lembretes anteriores.
            </p>
          </div>

          <div className="flex items-center justify-between rounded-md border px-3 py-2">
            <div>
              <Label className="text-sm">Tarefa privada</Label>
              <p className="text-[11px] text-muted-foreground">Visível só para você, o responsável e admins.</p>
            </div>
            <Switch checked={isPrivate} onCheckedChange={setIsPrivate} />
          </div>

          <div className="space-y-2">
            <Label>Observações</Label>
            <Textarea rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} />
          </div>

          <div className="space-y-2">
            <Label>Descrição</Label>
            <Textarea rows={2} value={description} onChange={(e) => setDescription(e.target.value)} placeholder="Detalhes da tarefa" />
          </div>
        </div>

        <DialogFooter className="gap-2 sm:justify-between">
          <div>
            {existing && (
              <Button
                variant="outline"
                onClick={handleDelete}
                disabled={del.isPending}
                className="text-destructive hover:text-destructive"
              >
                <Trash2 className="h-4 w-4 mr-1" /> Excluir
              </Button>
            )}
          </div>
          <div className="flex gap-2">
            <Button variant="outline" onClick={() => onOpenChange(false)}>Cancelar</Button>
            <Button onClick={handleSave} disabled={save.isPending}>
              {save.isPending && <Loader2 className="h-4 w-4 animate-spin mr-1" />}
              {existing ? 'Salvar alterações' : 'Criar tarefa'}
            </Button>
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
