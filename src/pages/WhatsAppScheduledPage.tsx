import { useState, useRef } from 'react';
import { PageHeader } from '@/components/PageHeader';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter,
} from '@/components/ui/dialog';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from '@/components/ui/table';
import { ScrollArea } from '@/components/ui/scroll-area';
import {
  Clock, CheckCircle2, XCircle, AlertCircle, Send, Pencil, Trash2,
  RefreshCw, CalendarClock, Filter, MessageSquare, Plus, Zap,
} from 'lucide-react';
import { format, formatDistanceToNow, isPast } from 'date-fns';
import { ptBR } from 'date-fns/locale';
import {
  useWhatsAppScheduled, useCancelScheduledSend, useDeleteScheduledSend,
  useSendNow, useUpdateScheduledSend, useCreateScheduledSend,
  type ScheduledSend, type ScheduledSendStatus,
} from '@/hooks/use-whatsapp-scheduled';
import { useAuth } from '@/hooks/use-auth';

// ─── helpers ────────────────────────────────────────────────────────────────

function statusConfig(status: string) {
  switch (status) {
    case 'pending':
      return { label: 'Pendente', icon: <Clock className="h-3 w-3" />, variant: 'outline' as const, className: 'text-amber-600 border-amber-200 bg-amber-50' };
    case 'processing':
      return { label: 'Processando', icon: <RefreshCw className="h-3 w-3 animate-spin" />, variant: 'outline' as const, className: 'text-blue-600 border-blue-200 bg-blue-50' };
    case 'sent':
      return { label: 'Enviado', icon: <CheckCircle2 className="h-3 w-3" />, variant: 'outline' as const, className: 'text-green-600 border-green-200 bg-green-50' };
    case 'failed':
      return { label: 'Falhou', icon: <XCircle className="h-3 w-3" />, variant: 'destructive' as const, className: '' };
    case 'cancelled':
      return { label: 'Cancelado', icon: <AlertCircle className="h-3 w-3" />, variant: 'secondary' as const, className: '' };
    default:
      return { label: status, icon: null, variant: 'outline' as const, className: '' };
  }
}

function recurrenceLabel(r: string) {
  const map: Record<string, string> = {
    once: 'Uma vez',
    daily: 'Diário',
    weekly: 'Semanal',
    monthly: 'Mensal',
  };
  return map[r] || r;
}

function sendModeLabel(m: string) {
  const map: Record<string, string> = {
    text: 'Texto',
    link: 'Link (OS)',
    document: 'Documento',
  };
  return map[m] || m;
}

// ─── Reschedule / Edit Dialog ───────────────────────────────────────────────

function EditScheduleDialog({
  job,
  onClose,
}: {
  job: ScheduledSend;
  onClose: () => void;
}) {
  const update = useUpdateScheduledSend();
  const [scheduledAt, setScheduledAt] = useState(
    job.scheduled_at ? job.scheduled_at.slice(0, 16) : ''
  );
  const [message, setMessage] = useState(job.message || '');

  const handleSave = async () => {
    const iso = new Date(scheduledAt).toISOString();
    await update.mutateAsync({ id: job.id, scheduled_at: iso, next_run_at: iso, message });
    onClose();
  };

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Editar Agendamento</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <div>
            <Label>Nova data e hora</Label>
            <Input
              type="datetime-local"
              value={scheduledAt}
              onChange={(e) => setScheduledAt(e.target.value)}
            />
          </div>
          <div>
            <Label>Mensagem</Label>
            <Textarea
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              rows={4}
              className="text-sm"
            />
          </div>
          <div className="text-xs text-muted-foreground bg-muted/50 rounded p-2">
            <strong>Destinatário:</strong> {job.phone}<br />
            <strong>Modo:</strong> {sendModeLabel(job.send_mode)}<br />
            <strong>Recorrência:</strong> {recurrenceLabel(job.recurrence_type)}
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancelar</Button>
          <Button onClick={handleSave} disabled={update.isPending}>
            {update.isPending ? 'Salvando…' : 'Salvar'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// ─── New Schedule Dialog ─────────────────────────────────────────────────────

function NewScheduleDialog({ onClose }: { onClose: () => void }) {
  const { user } = useAuth();
  const create = useCreateScheduledSend();
  const [phone, setPhone] = useState('');
  const [message, setMessage] = useState('');
  const [scheduledAt, setScheduledAt] = useState('');
  const [recurrence, setRecurrence] = useState('once');
  // Ref para ler o valor DOM diretamente — funciona mesmo quando onChange
  // não dispara (ex: preenchimento programático via ferramenta de automação)
  const dateRef = useRef<HTMLInputElement>(null);

  const handleCreate = async () => {
    // Lê do ref como fallback caso o estado React não tenha sido atualizado
    const dateValue = dateRef.current?.value || scheduledAt;
    if (!phone.trim() || !message.trim() || !dateValue) {
      return;
    }
    const iso = new Date(dateValue).toISOString();
    await create.mutateAsync({
      phone: phone.replace(/\D/g, ''),
      message,
      scheduled_at: iso,
      next_run_at: iso,
      recurrence_type: recurrence,
      target_kind: 'manual',
      send_mode: 'text',
      status: 'pending',
      created_by: user?.id,
    });
    onClose();
  };

  // Verifica se já tem data preenchida (estado OU DOM) para habilitar o botão
  const hasDate = !!scheduledAt || !!(dateRef.current?.value);

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Plus className="h-4 w-4" /> Nova Mensagem Agendada
          </DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <div>
            <Label>Telefone (com DDI+DDD)</Label>
            <Input
              placeholder="5547999999999"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
            />
            <p className="text-xs text-muted-foreground mt-1">Ex: 5547999999999 (Brasil: 55 + DDD + número)</p>
          </div>
          <div>
            <Label>Mensagem</Label>
            <Textarea
              placeholder="Olá! Aqui é a HBR Marine..."
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              rows={4}
            />
          </div>
          <div>
            <Label>Data e hora de envio</Label>
            {/* Input nativo com ref para garantir leitura correta do valor DOM */}
            <input
              ref={dateRef}
              type="datetime-local"
              className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
              onChange={(e) => setScheduledAt(e.target.value)}
            />
          </div>
          <div>
            <Label>Recorrência</Label>
            <Select value={recurrence} onValueChange={setRecurrence}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="once">Uma vez</SelectItem>
                <SelectItem value="daily">Diário</SelectItem>
                <SelectItem value="weekly">Semanal</SelectItem>
                <SelectItem value="monthly">Mensal</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancelar</Button>
          <Button onClick={handleCreate} disabled={create.isPending || !phone || !message}>
            {create.isPending ? 'Agendando…' : 'Agendar'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// ─── Main Page ───────────────────────────────────────────────────────────────

export default function WhatsAppScheduledPage() {
  const [statusFilter, setStatusFilter] = useState('all');
  const [editingJob, setEditingJob] = useState<ScheduledSend | null>(null);
  const [deletingId, setDeletingId] = useState<string | null>(null);
  const [cancellingId, setCancellingId] = useState<string | null>(null);
  const [showNew, setShowNew] = useState(false);

  const { data: jobs, isLoading, refetch, isFetching } = useWhatsAppScheduled({
    status: statusFilter,
  });

  const cancelMut = useCancelScheduledSend();
  const deleteMut = useDeleteScheduledSend();
  const sendNow = useSendNow();

  const stats = {
    pending: jobs?.filter((j) => j.status === 'pending').length ?? 0,
    sent: jobs?.filter((j) => j.status === 'sent').length ?? 0,
    failed: jobs?.filter((j) => j.status === 'failed').length ?? 0,
    total: jobs?.length ?? 0,
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader
        title="Agendamentos WhatsApp"
        description="Gerencie mensagens agendadas, recorrências e histórico de envios."
      >
        <div className="flex gap-2">
          <Button variant="outline" size="sm" onClick={() => refetch()} disabled={isFetching}>
            <RefreshCw className={`h-4 w-4 mr-1 ${isFetching ? 'animate-spin' : ''}`} />
            Atualizar
          </Button>
          <Button size="sm" onClick={() => setShowNew(true)}>
            <Plus className="h-4 w-4 mr-1" /> Nova Mensagem
          </Button>
        </div>
      </PageHeader>

      {/* Stats */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <Card className="bg-gradient-to-br from-amber-50 to-transparent border-amber-100">
          <CardContent className="p-5 flex items-center gap-3">
            <div className="p-2 bg-amber-100 rounded-lg">
              <Clock className="h-5 w-5 text-amber-600" />
            </div>
            <div>
              <p className="text-xs text-muted-foreground">Pendentes</p>
              <p className="text-2xl font-bold">{stats.pending}</p>
            </div>
          </CardContent>
        </Card>
        <Card className="bg-gradient-to-br from-green-50 to-transparent border-green-100">
          <CardContent className="p-5 flex items-center gap-3">
            <div className="p-2 bg-green-100 rounded-lg">
              <CheckCircle2 className="h-5 w-5 text-green-600" />
            </div>
            <div>
              <p className="text-xs text-muted-foreground">Enviados</p>
              <p className="text-2xl font-bold">{stats.sent}</p>
            </div>
          </CardContent>
        </Card>
        <Card className="bg-gradient-to-br from-red-50 to-transparent border-red-100">
          <CardContent className="p-5 flex items-center gap-3">
            <div className="p-2 bg-red-100 rounded-lg">
              <XCircle className="h-5 w-5 text-red-600" />
            </div>
            <div>
              <p className="text-xs text-muted-foreground">Falhas</p>
              <p className="text-2xl font-bold">{stats.failed}</p>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-5 flex items-center gap-3">
            <div className="p-2 bg-muted rounded-lg">
              <CalendarClock className="h-5 w-5 text-muted-foreground" />
            </div>
            <div>
              <p className="text-xs text-muted-foreground">Total visível</p>
              <p className="text-2xl font-bold">{stats.total}</p>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Filters */}
      <div className="flex items-center gap-3 bg-muted/30 p-2 rounded-lg">
        <div className="flex items-center gap-1 text-sm text-muted-foreground">
          <Filter className="h-4 w-4" /> Filtrar:
        </div>
        <Select value={statusFilter} onValueChange={setStatusFilter}>
          <SelectTrigger className="w-[180px] h-8 bg-white text-sm">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">Todos os status</SelectItem>
            <SelectItem value="pending">Pendentes</SelectItem>
            <SelectItem value="processing">Processando</SelectItem>
            <SelectItem value="sent">Enviados</SelectItem>
            <SelectItem value="failed">Falhas</SelectItem>
            <SelectItem value="cancelled">Cancelados</SelectItem>
          </SelectContent>
        </Select>
      </div>

      {/* Table */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base flex items-center gap-2">
            <MessageSquare className="h-4 w-4" /> Mensagens Agendadas
          </CardTitle>
        </CardHeader>
        <CardContent>
          <ScrollArea className="h-[55vh]">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="w-[110px]">Status</TableHead>
                  <TableHead className="w-[140px]">Próximo envio</TableHead>
                  <TableHead className="w-[130px] hidden md:table-cell">Destinatário</TableHead>
                  <TableHead>Mensagem</TableHead>
                  <TableHead className="w-[90px] hidden sm:table-cell">Modo</TableHead>
                  <TableHead className="w-[90px] hidden lg:table-cell">Recorrência</TableHead>
                  <TableHead className="w-[130px] text-right">Ações</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {isLoading ? (
                  <TableRow>
                    <TableCell colSpan={7} className="text-center text-muted-foreground py-10">
                      <RefreshCw className="h-5 w-5 animate-spin mx-auto mb-2" />
                      Carregando…
                    </TableCell>
                  </TableRow>
                ) : (jobs || []).length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={7} className="text-center py-16 space-y-2">
                      <CalendarClock className="h-10 w-10 mx-auto text-muted-foreground opacity-20" />
                      <p className="text-muted-foreground text-sm">Nenhum agendamento encontrado.</p>
                    </TableCell>
                  </TableRow>
                ) : (
                  (jobs || []).map((job) => {
                    const sc = statusConfig(job.status);
                    const nextDate = job.next_run_at ? new Date(job.next_run_at) : null;
                    const overdue = nextDate && isPast(nextDate) && job.status === 'pending';

                    return (
                      <TableRow key={job.id} className={overdue ? 'bg-amber-50/50' : ''}>
                        <TableCell>
                          <Badge variant={sc.variant} className={`gap-1 text-xs ${sc.className}`}>
                            {sc.icon}
                            {sc.label}
                          </Badge>
                        </TableCell>
                        <TableCell className="text-xs">
                          {nextDate ? (
                            <div>
                              <div className={`font-medium ${overdue ? 'text-amber-600' : ''}`}>
                                {format(nextDate, 'dd/MM/yy HH:mm')}
                              </div>
                              <div className="text-muted-foreground">
                                {formatDistanceToNow(nextDate, { addSuffix: true, locale: ptBR })}
                              </div>
                            </div>
                          ) : '—'}
                        </TableCell>
                        <TableCell className="hidden md:table-cell">
                          <div className="text-xs font-mono text-muted-foreground">
                            {job.phone}
                          </div>
                        </TableCell>
                        <TableCell>
                          <div className="text-xs max-w-[220px]">
                            <p className="truncate">{job.message}</p>
                            {job.last_error && (
                              <p className="text-red-500 truncate mt-0.5">
                                ⚠ {job.last_error}
                              </p>
                            )}
                          </div>
                        </TableCell>
                        <TableCell className="hidden sm:table-cell text-xs text-muted-foreground">
                          {sendModeLabel(job.send_mode)}
                        </TableCell>
                        <TableCell className="hidden lg:table-cell text-xs text-muted-foreground">
                          {recurrenceLabel(job.recurrence_type)}
                        </TableCell>
                        <TableCell>
                          <div className="flex items-center justify-end gap-1">
                            {job.status === 'pending' && (
                              <>
                                <Button
                                  variant="ghost"
                                  size="icon"
                                  className="h-7 w-7 text-green-600 hover:text-green-700 hover:bg-green-50"
                                  title="Enviar agora"
                                  onClick={() => sendNow.mutate(job.id)}
                                  disabled={sendNow.isPending}
                                >
                                  <Zap className="h-3.5 w-3.5" />
                                </Button>
                                <Button
                                  variant="ghost"
                                  size="icon"
                                  className="h-7 w-7"
                                  title="Editar / Reagendar"
                                  onClick={() => setEditingJob(job)}
                                >
                                  <Pencil className="h-3.5 w-3.5" />
                                </Button>
                                <Button
                                  variant="ghost"
                                  size="icon"
                                  className="h-7 w-7 text-amber-600 hover:text-amber-700"
                                  title="Cancelar agendamento"
                                  onClick={() => setCancellingId(job.id)}
                                >
                                  <XCircle className="h-3.5 w-3.5" />
                                </Button>
                              </>
                            )}
                            {job.status === 'failed' && (
                              <Button
                                variant="ghost"
                                size="icon"
                                className="h-7 w-7 text-blue-600 hover:text-blue-700"
                                title="Tentar novamente"
                                onClick={() => sendNow.mutate(job.id)}
                                disabled={sendNow.isPending}
                              >
                                <RefreshCw className="h-3.5 w-3.5" />
                              </Button>
                            )}
                            {(job.status === 'sent' || job.status === 'cancelled' || job.status === 'failed') && (
                              <Button
                                variant="ghost"
                                size="icon"
                                className="h-7 w-7 text-destructive hover:text-destructive"
                                title="Remover"
                                onClick={() => setDeletingId(job.id)}
                              >
                                <Trash2 className="h-3.5 w-3.5" />
                              </Button>
                            )}
                          </div>
                        </TableCell>
                      </TableRow>
                    );
                  })
                )}
              </TableBody>
            </Table>
          </ScrollArea>
        </CardContent>
      </Card>

      {/* Dialogs */}
      {editingJob && (
        <EditScheduleDialog job={editingJob} onClose={() => setEditingJob(null)} />
      )}

      {showNew && <NewScheduleDialog onClose={() => setShowNew(false)} />}

      <AlertDialog open={!!cancellingId} onOpenChange={(o) => !o && setCancellingId(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Cancelar agendamento?</AlertDialogTitle>
            <AlertDialogDescription>
              A mensagem não será enviada. Você pode removê-la depois.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Voltar</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                if (cancellingId) cancelMut.mutate(cancellingId);
                setCancellingId(null);
              }}
            >
              Cancelar agendamento
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      <AlertDialog open={!!deletingId} onOpenChange={(o) => !o && setDeletingId(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Remover registro?</AlertDialogTitle>
            <AlertDialogDescription>
              Esta ação é permanente e não pode ser desfeita.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Voltar</AlertDialogCancel>
            <AlertDialogAction
              className="bg-destructive hover:bg-destructive/90"
              onClick={() => {
                if (deletingId) deleteMut.mutate(deletingId);
                setDeletingId(null);
              }}
            >
              Remover
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
