import { useEffect, useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { EntityCombobox } from '@/components/EntityCombobox';
import { Loader2, Trash2 } from 'lucide-react';
import { toast } from 'sonner';
import {
  useSaveAgendaTask,
  useDeleteAgendaTask,
  type AgendaTaskInput,
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
  technician_user_id: string;
  scheduled_start_at: string;
  scheduled_end_at: string | null;
  priority: string;
  status: string;
  location?: string | null;
  client_id?: string | null;
  notes?: string | null;
};

export function AgendaTaskDialog({
  open,
  onOpenChange,
  technicians,
  prefillTechnicianId,
  prefillDate,
  existing,
}: {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  technicians: { id: string; full_name: string }[];
  prefillTechnicianId?: string;
  prefillDate?: string;
  existing?: ExistingTask | null;
}) {
  const save = useSaveAgendaTask();
  const del = useDeleteAgendaTask();
  const { data: clients = [] } = useClients();

  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [technicianId, setTechnicianId] = useState('');
  const [date, setDate] = useState('');
  const [startTime, setStartTime] = useState('09:00');
  const [endTime, setEndTime] = useState('10:00');
  const [priority, setPriority] = useState('normal');
  const [status, setStatus] = useState('pending');
  const [location, setLocation] = useState('');
  const [clientId, setClientId] = useState<string>('');
  const [notes, setNotes] = useState('');

  useEffect(() => {
    if (!open) return;
    if (existing) {
      setTitle(existing.title);
      setDescription(existing.description || '');
      setTechnicianId(existing.technician_user_id);
      const startDate = new Date(existing.scheduled_start_at);
      setDate(toLocalDateInput(startDate));
      setStartTime(toLocalTime(existing.scheduled_start_at, '09:00'));
      setEndTime(toLocalTime(existing.scheduled_end_at, '10:00'));
      setPriority(existing.priority || 'normal');
      setStatus(existing.status || 'pending');
      setLocation(existing.location || '');
      setClientId(existing.client_id || '');
      setNotes(existing.notes || '');
    } else {
      setTitle('');
      setDescription('');
      setTechnicianId(prefillTechnicianId || '');
      setDate(prefillDate || toLocalDateInput(new Date()));
      setStartTime('09:00');
      setEndTime('10:00');
      setPriority('normal');
      setStatus('pending');
      setLocation('');
      setClientId('');
      setNotes('');
    }
  }, [open, existing, prefillTechnicianId, prefillDate]);

  const handleSave = async () => {
    if (!title.trim()) {
      toast.error('Informe um título para a tarefa');
      return;
    }
    if (!technicianId) {
      toast.error('Selecione um técnico');
      return;
    }
    if (!date || !startTime) {
      toast.error('Informe data e hora de início');
      return;
    }
    const startISO = new Date(`${date}T${startTime}:00`).toISOString();
    const endISO = endTime ? new Date(`${date}T${endTime}:00`).toISOString() : null;

    const payload: AgendaTaskInput = {
      id: existing?.id,
      title: title.trim(),
      description: description.trim() || null,
      technician_user_id: technicianId,
      scheduled_start_at: startISO,
      scheduled_end_at: endISO,
      priority,
      status,
      location: location.trim() || null,
      client_id: clientId || null,
      notes: notes.trim() || null,
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
          <DialogTitle>{existing ? 'Editar tarefa' : 'Nova tarefa do técnico'}</DialogTitle>
        </DialogHeader>

        <div className="space-y-4 max-h-[70vh] overflow-y-auto pr-1">
          <div className="space-y-2">
            <Label>Título *</Label>
            <Input
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="Ex.: Buscar peça no fornecedor"
            />
          </div>

          <div className="space-y-2">
            <Label>Descrição</Label>
            <Textarea
              rows={2}
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Detalhes da tarefa"
            />
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div className="space-y-2">
              <Label>Técnico responsável *</Label>
              <EntityCombobox
                value={technicianId}
                onChange={setTechnicianId}
                placeholder="Selecione um técnico"
                options={technicians.map((t) => ({ value: t.id, label: t.full_name }))}
              />
            </div>
            <div className="space-y-2">
              <Label>Cliente (opcional)</Label>
              <EntityCombobox
                value={clientId}
                onChange={setClientId}
                placeholder="Sem cliente"
                options={[
                  { value: '', label: 'Sem cliente' },
                  ...clients.map((c: any) => ({
                    value: c.id,
                    label: c.name,
                  })),
                ]}
              />
            </div>
          </div>

          <div className="grid grid-cols-3 gap-3">
            <div className="space-y-2">
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
              <Input
                value={location}
                onChange={(e) => setLocation(e.target.value)}
                placeholder="Marina, endereço…"
              />
            </div>
          </div>

          <div className="space-y-2">
            <Label>Observações</Label>
            <Textarea rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} />
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
