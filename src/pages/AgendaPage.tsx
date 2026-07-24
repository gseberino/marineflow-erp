import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { PageHeader } from '@/components/PageHeader';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { StatusBadge } from '@/components/StatusBadge';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { EntityCombobox } from '@/components/EntityCombobox';
import { ChevronLeft, ChevronRight, CalendarDays, Plus, Loader2, ListChecks, Briefcase, Download, Zap } from 'lucide-react';
import { parseQuickTask } from '@/lib/quick-task-parser';
import { cn } from '@/lib/utils';
import {
  useAgendaOrders,
  useAgendaTasks,
  useTechnicians,
  useActiveUsers,
  useLiveTasks,
  useCompletedTasks,
  useCompleteTask,
  useRescheduleTask,
  useSchedulableOrders,
  useQuickSchedule,
  useSaveAgendaTask,
} from '@/hooks/use-agenda';
import { TaskCard } from '@/components/agenda/TaskCard';
import { AgendaTaskDialog, type ExistingTask } from '@/components/AgendaTaskDialog';
import { FocusMode } from '@/components/agenda/FocusMode';
import { OnMyWayButton } from '@/components/agenda/OnMyWayButton';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { toast } from 'sonner';
import { useI18n } from '@/i18n';
import { statusConfig } from '@/lib/constants';
import { FilterPresets } from '@/components/FilterPresets';

type ViewMode = 'today' | 'week' | 'month' | 'done';

function startOfWeek(d: Date): Date {
  const date = new Date(d);
  date.setHours(0, 0, 0, 0);
  const day = date.getDay();
  const diff = day === 0 ? -6 : 1 - day;
  date.setDate(date.getDate() + diff);
  return date;
}
function addDays(d: Date, n: number): Date {
  const x = new Date(d);
  x.setDate(x.getDate() + n);
  return x;
}
function startOfMonth(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), 1);
}
function endOfMonth(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth() + 1, 0, 23, 59, 59, 999);
}
function sameDay(a: Date, b: Date): boolean {
  return a.getFullYear() === b.getFullYear()
    && a.getMonth() === b.getMonth()
    && a.getDate() === b.getDate();
}
function fmtTime(iso: string | null): string {
  if (!iso) return '';
  const d = new Date(iso);
  return d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
}
function toLocalDateInput(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

const TASK_PRIORITY_CLASSES: Record<string, string> = {
  low: 'bg-muted text-muted-foreground border border-border',
  normal: 'bg-secondary text-secondary-foreground border border-border',
  high: 'bg-amber-500/15 text-amber-700 border border-amber-500/30 dark:text-amber-400',
  urgent: 'bg-destructive/15 text-destructive border border-destructive/30',
};

export default function AgendaPage() {
  const navigate = useNavigate();
  const [view, setView] = useState<ViewMode>('today');
  const [cursor, setCursor] = useState(() => new Date());
  const [selectedDay, setSelectedDay] = useState<Date | null>(null);

  const [osDialogOpen, setOsDialogOpen] = useState(false);
  const [taskDialogOpen, setTaskDialogOpen] = useState(false);
  const [editingTask, setEditingTask] = useState<ExistingTask | null>(null);
  const [prefill, setPrefill] = useState<{ technicianId?: string; date?: string }>({});
  const [techFilter, setTechFilter] = useState<string>('all');
  const [prioFilter, setPrioFilter] = useState<string>('all');
  const [sourceFilter, setSourceFilter] = useState<string>('all');
  const [doneDays, setDoneDays] = useState<number>(30);

  const range = useMemo(() => {
    if (view === 'today') {
      const from = new Date();
      from.setHours(0, 0, 0, 0);
      return { from, to: addDays(from, 1) };
    }
    if (view === 'week') {
      const from = startOfWeek(cursor);
      const to = addDays(from, 7);
      return { from, to };
    }
    const from = startOfMonth(cursor);
    const to = addDays(endOfMonth(cursor), 1);
    return { from, to };
  }, [view, cursor]);

  const { data: orders = [], isLoading: loadingOrders, error: ordersError } = useAgendaOrders(
    range.from.toISOString(),
    range.to.toISOString(),
  );
  const { data: tasks = [], isLoading: loadingTasks } = useAgendaTasks(
    range.from.toISOString(),
    range.to.toISOString(),
  );
  const { data: technicians = [] } = useTechnicians();
  const { data: activeUsers = [] } = useActiveUsers();
  const { data: liveTasks = [], isLoading: loadingLive } = useLiveTasks();
  const { data: doneTasks = [], isLoading: loadingDone } = useCompletedTasks(doneDays);
  const completeTask = useCompleteTask();
  const reschedule = useRescheduleTask();
  const saveTask = useSaveAgendaTask();
  const [quickText, setQuickText] = useState('');
  const [scheduleOsId, setScheduleOsId] = useState<string | undefined>(undefined);
  const [focusOpen, setFocusOpen] = useState(false);

  // Fila do modo foco: atrasadas → hoje → sem data; prioridade dentro de cada grupo
  const focusQueue = useMemo(() => {
    const now = new Date();
    const startToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const endToday = new Date(startToday.getTime() + 86400000);
    const prioRank: Record<string, number> = { urgent: 0, high: 1, normal: 2, low: 3 };
    const anchor = (t: any) => t.due_at || t.scheduled_start_at;
    const group = (t: any) => {
      const a = anchor(t);
      if (a && new Date(a) < startToday) return 0;
      if (a && new Date(a) < endToday) return 1;
      if (!a) return 2;
      return 3; // futuras ficam fora
    };
    return applyTaskFilters(liveTasks || [])
      .filter((t: any) => group(t) < 3 && (!t.snoozed_until || new Date(t.snoozed_until) <= now))
      .sort((a: any, b: any) => group(a) - group(b)
        || (prioRank[a.priority] ?? 2) - (prioRank[b.priority] ?? 2));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [liveTasks, techFilter, prioFilter, sourceFilter]);

  // Captura em 3 segundos (padrão Todoist): "amanhã 14h ligar pro João"
  const handleQuickAdd = async () => {
    const parsed = parseQuickTask(quickText);
    if (!parsed.title) { toast.error('Escreva o que precisa ser feito'); return; }
    const dateStr = parsed.date ? toLocalDateInput(parsed.date) : null;
    try {
      const res: any = await saveTask.mutateAsync({
        title: parsed.title,
        kind: parsed.time ? 'appointment' : 'task',
        priority: parsed.priority ?? 'normal',
        scheduled_start_at: parsed.time && dateStr ? new Date(`${dateStr}T${parsed.time}:00`).toISOString() : null,
        scheduled_end_at: parsed.time && dateStr
          ? new Date(new Date(`${dateStr}T${parsed.time}:00`).getTime() + 3600000).toISOString() : null,
        due_at: !parsed.time && dateStr ? new Date(`${dateStr}T08:00:00`).toISOString() : null,
        assignee_user_id: null,
      });
      toast.success(parsed.date
        ? `Criada: "${parsed.title}" — ${parsed.date.toLocaleDateString('pt-BR')}${parsed.time ? ` ${parsed.time}` : ''}`
        : `Criada: "${parsed.title}" (sem data)`);
      if (res?.warning) toast.warning(res.warning);
      setQuickText('');
    } catch (e: any) {
      toast.error(e?.message || 'Erro ao criar tarefa');
    }
  };

  // Export CSV da visão atual (Hoje = vivas filtradas; Concluídas = período filtrado)
  const handleExportCsv = () => {
    const rows = view === 'done' ? applyTaskFilters(doneTasks || []) : applyTaskFilters(liveTasks || []);
    const esc = (v: any) => `"${String(v ?? '').replace(/"/g, '""')}"`;
    const csv = [
      ['titulo', 'tipo', 'status', 'prioridade', 'responsavel', 'prazo', 'inicio', 'fim', 'origem', 'vinculo', 'concluida_em', 'cliente'].join(';'),
      ...rows.map((t: any) => [
        esc(t.title), esc(t.kind), esc(t.status), esc(t.priority),
        esc(t.app_users?.full_name), esc(t.due_at), esc(t.scheduled_start_at), esc(t.scheduled_end_at),
        esc(t.source), esc(t.related_entity_type), esc(t.completed_at), esc(t.clients?.name),
      ].join(';')),
    ].join('\n');
    const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `tarefas-${view}-${toLocalDateInput(new Date())}.csv`;
    a.click();
    URL.revokeObjectURL(a.href);
  };

  const handleTaskDrop = (task: any, technicianId: string, dateKey: string) => {
    reschedule.mutate(
      { task, dateKey, assigneeId: technicianId === '__unassigned__' ? null : technicianId },
      {
        onSuccess: () => toast.success('Tarefa movida'),
        onError: (e: any) => toast.error(e?.message || 'Erro ao mover tarefa'),
      },
    );
  };

  const isLoading = view === 'today' ? (loadingOrders || loadingLive)
    : view === 'done' ? loadingDone
    : (loadingOrders || loadingTasks);

  // Filtro de pessoa/prioridade/origem aplicável a qualquer lista de tarefas
  const applyTaskFilters = (list: any[]) => list.filter((t: any) => {
    if (techFilter === '__none__' && t.assignee_user_id) return false;
    if (techFilter !== 'all' && techFilter !== '__none__' && t.assignee_user_id !== techFilter) return false;
    if (prioFilter !== 'all' && t.priority !== prioFilter) return false;
    if (sourceFilter !== 'all' && t.source !== sourceFilter) return false;
    return true;
  });

  const filteredOrders = useMemo(() => (
    techFilter === 'all'
      ? orders
      : (orders || []).filter((o: any) =>
          (o.service_order_technicians || []).some((t: any) => t.user_id === techFilter)
        )
  ), [orders, techFilter]);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const filteredTasks = useMemo(() => applyTaskFilters(tasks || []), [tasks, techFilter, prioFilter, sourceFilter]);

  const handleNav = (delta: number) => {
    if (view === 'week') setCursor(addDays(cursor, delta * 7));
    else setCursor(new Date(cursor.getFullYear(), cursor.getMonth() + delta, 1));
  };

  const openQuickSchedule = (technicianId?: string, date?: Date) => {
    setPrefill({
      technicianId,
      date: date ? toLocalDateInput(date) : toLocalDateInput(new Date()),
    });
    setOsDialogOpen(true);
  };

  const openTaskDialog = (technicianId?: string, date?: Date, existing?: ExistingTask | null) => {
    setEditingTask(existing || null);
    setPrefill({
      technicianId,
      date: date ? toLocalDateInput(date) : toLocalDateInput(new Date()),
    });
    setTaskDialogOpen(true);
  };

  return (
    <div className="space-y-4">
      <PageHeader
        title="Agenda"
        description="Programação de OS e tarefas dos técnicos"
      >
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button>
              <Plus className="h-4 w-4" /> Agendar
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem onClick={() => openQuickSchedule()}>
              <Briefcase className="h-4 w-4 mr-2" /> Ordem de serviço
            </DropdownMenuItem>
            <DropdownMenuItem onClick={() => openTaskDialog()}>
              <ListChecks className="h-4 w-4 mr-2" /> Tarefa do técnico
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </PageHeader>

      <Card className="p-4 space-y-4 overflow-hidden">
        <div className="flex items-center gap-2">
          <Zap className="h-4 w-4 text-primary shrink-0" />
          <Input
            value={quickText}
            onChange={(e) => setQuickText(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter' && !saveTask.isPending) handleQuickAdd(); }}
            placeholder='Tarefa rápida: "amanhã 14h ligar pro João", "sexta cobrar marina", "urgente revisar orçamento"…'
            className="h-9"
          />
          <Button size="sm" onClick={handleQuickAdd} disabled={saveTask.isPending || !quickText.trim()}>
            {saveTask.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Criar'}
          </Button>
          <Button size="sm" variant="outline" onClick={handleExportCsv} title="Exportar CSV da visão atual">
            <Download className="h-4 w-4" />
          </Button>
          <Button size="sm" variant="outline" onClick={() => setFocusOpen(true)}
            disabled={focusQueue.length === 0} title="Uma tarefa por vez, em sequência">
            🎯 Foco{focusQueue.length > 0 ? ` (${focusQueue.length})` : ''}
          </Button>
        </div>

        <div className="flex flex-wrap items-center justify-between gap-2">
          <div className="flex items-center gap-1 rounded-md border p-1">
            <Button size="sm" variant={view === 'today' ? 'default' : 'ghost'} onClick={() => setView('today')}>
              Hoje
            </Button>
            <Button size="sm" variant={view === 'week' ? 'default' : 'ghost'} onClick={() => setView('week')}>
              Semana
            </Button>
            <Button size="sm" variant={view === 'month' ? 'default' : 'ghost'} onClick={() => setView('month')}>
              Mês
            </Button>
            <Button size="sm" variant={view === 'done' ? 'default' : 'ghost'} onClick={() => setView('done')}>
              Concluídas
            </Button>
          </div>

          <div className="flex items-center gap-2 flex-wrap">
            {view === 'done' && (
              <Select value={String(doneDays)} onValueChange={(v) => setDoneDays(Number(v))}>
                <SelectTrigger className="w-[130px]">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="7">Últimos 7 dias</SelectItem>
                  <SelectItem value="30">Últimos 30 dias</SelectItem>
                  <SelectItem value="90">Últimos 90 dias</SelectItem>
                </SelectContent>
              </Select>
            )}
            {view !== 'today' && view !== 'done' && (
              <>
                <Button size="sm" variant="outline" onClick={() => handleNav(-1)}>
                  <ChevronLeft className="h-4 w-4" />
                  <span className="hidden sm:inline">{view === 'week' ? 'Semana anterior' : 'Mês anterior'}</span>
                </Button>
                <Button size="sm" variant="outline" onClick={() => setCursor(new Date())}>Hoje</Button>
                <Button size="sm" variant="outline" onClick={() => handleNav(1)}>
                  <span className="hidden sm:inline">{view === 'week' ? 'Semana seguinte' : 'Mês seguinte'}</span>
                  <ChevronRight className="h-4 w-4" />
                </Button>
              </>
            )}
            <Select value={techFilter} onValueChange={setTechFilter}>
              <SelectTrigger className="w-full sm:w-[170px]">
                <SelectValue placeholder="Filtrar por pessoa" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">Todas as pessoas</SelectItem>
                <SelectItem value="__none__">Sem responsável</SelectItem>
                {activeUsers.map((u: any) => (
                  <SelectItem key={u.id} value={u.id}>{u.full_name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Select value={prioFilter} onValueChange={setPrioFilter}>
              <SelectTrigger className="w-[130px]">
                <SelectValue placeholder="Prioridade" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">Prioridade: todas</SelectItem>
                <SelectItem value="urgent">Urgente</SelectItem>
                <SelectItem value="high">Alta</SelectItem>
                <SelectItem value="normal">Normal</SelectItem>
                <SelectItem value="low">Baixa</SelectItem>
              </SelectContent>
            </Select>
            <Select value={sourceFilter} onValueChange={setSourceFilter}>
              <SelectTrigger className="w-[130px]">
                <SelectValue placeholder="Origem" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">Origem: todas</SelectItem>
                <SelectItem value="manual">Manual</SelectItem>
                <SelectItem value="ai">IA</SelectItem>
                <SelectItem value="automation">Automação</SelectItem>
                <SelectItem value="recurrence">Recorrência</SelectItem>
              </SelectContent>
            </Select>
            <FilterPresets
              filterType="agenda"
              currentConfig={{ view, techFilter, prioFilter, sourceFilter, doneDays }}
              hasActiveFilters={techFilter !== 'all' || prioFilter !== 'all' || sourceFilter !== 'all' || view !== 'today'}
              onApply={(c: any) => {
                if (c.view) setView(c.view);
                setTechFilter(c.techFilter ?? 'all');
                setPrioFilter(c.prioFilter ?? 'all');
                setSourceFilter(c.sourceFilter ?? 'all');
                if (c.doneDays) setDoneDays(c.doneDays);
              }}
            />
          </div>
        </div>

        {ordersError ? (
          <div className="py-8 text-center text-sm text-destructive">
            Erro ao carregar agenda. Tente recarregar a página.
          </div>
        ) : isLoading ? (
          <div className="flex items-center justify-center py-12 text-muted-foreground">
            <Loader2 className="h-5 w-5 animate-spin" />
          </div>
        ) : view === 'today' ? (
          <TodayView
            orders={filteredOrders}
            tasks={applyTaskFilters(liveTasks || [])}
            onOrderClick={(id) => navigate(`/service-orders/${id}`)}
            onTaskClick={(t) => openTaskDialog(undefined, undefined, t)}
            onToggleDone={(id, done) =>
              completeTask.mutate({ id, done }, { onError: (e: any) => toast.error(e?.message || 'Erro ao concluir') })}
            onScheduleOs={(t) => { setScheduleOsId(t.related_entity_id); setOsDialogOpen(true); }}
          />
        ) : view === 'done' ? (
          <DoneView
            tasks={applyTaskFilters(doneTasks || [])}
            days={doneDays}
            onTaskClick={(t) => openTaskDialog(undefined, undefined, t)}
            onToggleDone={(id, done) =>
              completeTask.mutate({ id, done }, { onError: (e: any) => toast.error(e?.message || 'Erro') })}
          />
        ) : view === 'week' ? (
          <WeekView
            weekStart={range.from}
            orders={filteredOrders}
            tasks={filteredTasks}
            technicians={technicians}
            onCardClick={(id) => navigate(`/service-orders/${id}`)}
            onCellClick={openTaskDialog}
            onTaskClick={(t) => openTaskDialog(undefined, undefined, t)}
            onTaskDrop={handleTaskDrop}
          />
        ) : (
          <MonthView
            cursor={cursor}
            orders={filteredOrders}
            tasks={filteredTasks}
            selectedDay={selectedDay}
            onSelectDay={setSelectedDay}
            onCardClick={(id) => navigate(`/service-orders/${id}`)}
            onTaskClick={(t) => openTaskDialog(undefined, undefined, t)}
          />
        )}
      </Card>

      <QuickScheduleDialog
        open={osDialogOpen}
        onOpenChange={(v) => { setOsDialogOpen(v); if (!v) setScheduleOsId(undefined); }}
        technicians={technicians}
        prefillTechnicianId={prefill.technicianId}
        prefillDate={prefill.date}
        prefillOrderId={scheduleOsId}
      />

      <FocusMode open={focusOpen} onOpenChange={setFocusOpen} tasks={focusQueue} />

      <AgendaTaskDialog
        open={taskDialogOpen}
        onOpenChange={(v) => { setTaskDialogOpen(v); if (!v) setEditingTask(null); }}
        technicians={technicians}
        prefillTechnicianId={prefill.technicianId}
        prefillDate={prefill.date}
        existing={editingTask}
      />
    </div>
  );
}

// ============================================================
// DONE VIEW — o que foi feito no período (estatística e análise)
// ============================================================
function DoneView({
  tasks, days, onTaskClick, onToggleDone,
}: {
  tasks: any[];
  days: number;
  onTaskClick: (task: any) => void;
  onToggleDone: (id: string, done: boolean) => void;
}) {
  const auto = tasks.filter((t: any) => !t.completed_by);
  const manual = tasks.filter((t: any) => t.completed_by);

  const byPerson = new Map<string, number>();
  for (const t of manual) {
    const nome = t.completed_by_user?.full_name || 'Alguém';
    byPerson.set(nome, (byPerson.get(nome) || 0) + 1);
  }
  const bySource = new Map<string, number>();
  for (const t of tasks) bySource.set(t.source, (bySource.get(t.source) || 0) + 1);

  let avgHours: number | null = null;
  const withTimes = tasks.filter((t: any) => t.completed_at && t.created_at);
  if (withTimes.length > 0) {
    const sum = withTimes.reduce((s: number, t: any) =>
      s + (new Date(t.completed_at).getTime() - new Date(t.created_at).getTime()) / 3600000, 0);
    avgHours = Math.round((sum / withTimes.length) * 10) / 10;
  }

  const SOURCE_LABEL: Record<string, string> = {
    manual: 'Manual', ai: 'IA', automation: 'Automação', recurrence: 'Recorrência',
  };

  const fmtDone = (iso: string) =>
    new Date(iso).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });

  // Agrupar por dia de conclusão
  const byDay = new Map<string, any[]>();
  for (const t of tasks) {
    const k = new Date(t.completed_at).toLocaleDateString('pt-BR', { weekday: 'long', day: 'numeric', month: 'long' });
    if (!byDay.has(k)) byDay.set(k, []);
    byDay.get(k)!.push(t);
  }

  return (
    <div className="space-y-5 max-w-3xl">
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <Card className="p-3">
          <p className="text-2xl font-bold tabular-nums">{tasks.length}</p>
          <p className="text-xs text-muted-foreground">concluídas em {days} dias</p>
        </Card>
        <Card className="p-3">
          <p className="text-2xl font-bold tabular-nums">{auto.length}</p>
          <p className="text-xs text-muted-foreground">resolvidas sozinhas (auto)</p>
        </Card>
        <Card className="p-3">
          <p className="text-2xl font-bold tabular-nums">{manual.length}</p>
          <p className="text-xs text-muted-foreground">concluídas por pessoas</p>
        </Card>
        <Card className="p-3">
          <p className="text-2xl font-bold tabular-nums">{avgHours ?? '—'}</p>
          <p className="text-xs text-muted-foreground">horas médias até concluir</p>
        </Card>
      </div>

      {(byPerson.size > 0 || bySource.size > 0) && (
        <div className="flex flex-wrap gap-2 text-xs">
          {Array.from(byPerson.entries()).map(([nome, n]) => (
            <span key={nome} className="rounded-full bg-primary/10 text-primary px-2.5 py-1 font-medium">
              {nome}: {n}
            </span>
          ))}
          {Array.from(bySource.entries()).map(([s, n]) => (
            <span key={s} className="rounded-full bg-secondary text-secondary-foreground px-2.5 py-1">
              {SOURCE_LABEL[s] || s}: {n}
            </span>
          ))}
        </div>
      )}

      {tasks.length === 0 && (
        <p className="text-sm text-muted-foreground py-6 text-center">
          Nada concluído no período selecionado.
        </p>
      )}

      {Array.from(byDay.entries()).map(([dia, dayTasks]) => (
        <div key={dia} className="space-y-1.5">
          <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">{dia}</p>
          {dayTasks.map((t: any) => (
            <div
              key={t.id}
              onClick={() => onTaskClick(t)}
              className="group flex items-start gap-2.5 rounded-md border bg-card px-3 py-2 cursor-pointer hover:bg-muted/40 transition-colors"
            >
              <span onClick={(e) => e.stopPropagation()} className="pt-0.5">
                <input
                  type="checkbox"
                  checked
                  onChange={() => onToggleDone(t.id, false)}
                  className="h-4 w-4 accent-primary cursor-pointer"
                  title="Reabrir tarefa"
                />
              </span>
              <div className="min-w-0 flex-1">
                <p className="text-sm font-medium leading-snug line-through opacity-70">{t.title}</p>
                <p className="text-[11px] text-muted-foreground mt-0.5">
                  {fmtDone(t.completed_at)}
                  {t.completed_by_user?.full_name
                    ? ` · por ${t.completed_by_user.full_name.split(' ')[0]}`
                    : ' · resolvida automaticamente'}
                  {' · '}{SOURCE_LABEL[t.source] || t.source}
                  {t.app_users?.full_name ? ` · resp.: ${t.app_users.full_name.split(' ')[0]}` : ''}
                </p>
              </div>
            </div>
          ))}
        </div>
      ))}
    </div>
  );
}

// ============================================================
// TODAY VIEW — atrasadas / hoje / sem data (default da página)
// ============================================================
function TodayView({
  orders, tasks, onOrderClick, onTaskClick, onToggleDone, onScheduleOs,
}: {
  orders: any[];
  tasks: any[];
  onOrderClick: (id: string) => void;
  onTaskClick: (task: any) => void;
  onToggleDone: (id: string, done: boolean) => void;
  onScheduleOs?: (task: any) => void;
}) {
  const now = new Date();
  const startToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const endToday = addDays(startToday, 1);

  const notSnoozed = (t: any) => !t.snoozed_until || new Date(t.snoozed_until) <= now;

  const overdue = tasks.filter((t: any) => {
    if (!notSnoozed(t)) return false;
    const anchor = t.due_at || t.scheduled_start_at;
    return anchor && new Date(anchor) < startToday;
  });
  const todayTasks = tasks.filter((t: any) => {
    if (!notSnoozed(t) || overdue.includes(t)) return false;
    const anchor = t.due_at || t.scheduled_start_at;
    return anchor && new Date(anchor) >= startToday && new Date(anchor) < endToday;
  }).sort((a: any, b: any) => {
    const av = a.scheduled_start_at || a.due_at, bv = b.scheduled_start_at || b.due_at;
    return new Date(av).getTime() - new Date(bv).getTime();
  });
  const noDate = tasks.filter((t: any) => !t.due_at && !t.scheduled_start_at && notSnoozed(t));
  const snoozed = tasks.filter((t: any) => !notSnoozed(t));

  const Section = ({ label, count, tone, children }: any) => (
    <div className="space-y-1.5">
      <div className="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide">
        <span className={tone}>{label}</span>
        <span className="rounded-full bg-muted px-2 py-0.5 text-[10px] text-muted-foreground">{count}</span>
      </div>
      {children}
    </div>
  );

  return (
    <div className="space-y-5 max-w-3xl">
      {orders.length > 0 && (
        <Section label="OS de hoje" count={orders.length} tone="text-primary">
          {orders.map((o: any) => (
            <div
              key={o.id}
              onClick={() => onOrderClick(o.id)}
              className={cn(
                'flex items-center gap-3 rounded-md p-2 text-sm cursor-pointer hover:ring-1 hover:ring-primary transition-all',
                statusConfig[o.status as keyof typeof statusConfig]?.className || 'bg-muted text-muted-foreground',
              )}
            >
              <Briefcase className="h-4 w-4 shrink-0" />
              <span className="font-mono text-xs opacity-70">{o.service_order_number}</span>
              <span className="font-medium truncate flex-1">{o.clients?.name || '—'}</span>
              <OnMyWayButton order={o} />
              {o.scheduled_start_at && <span className="text-xs font-semibold">{fmtTime(o.scheduled_start_at)}</span>}
            </div>
          ))}
        </Section>
      )}

      {overdue.length > 0 && (
        <Section label="Atrasadas" count={overdue.length} tone="text-destructive">
          {overdue.map((t: any) => (
            <TaskCard key={t.id} task={t} onOpen={onTaskClick} onToggleDone={onToggleDone} onScheduleOs={onScheduleOs} />
          ))}
        </Section>
      )}

      <Section label="Hoje" count={todayTasks.length} tone="text-foreground">
        {todayTasks.length === 0 && (
          <p className="text-xs text-muted-foreground py-1">Nada com prazo ou horário para hoje.</p>
        )}
        {todayTasks.map((t: any) => (
          <TaskCard key={t.id} task={t} onOpen={onTaskClick} onToggleDone={onToggleDone} onScheduleOs={onScheduleOs} />
        ))}
      </Section>

      {noDate.length > 0 && (
        <Section label="Sem data" count={noDate.length} tone="text-muted-foreground">
          {noDate.map((t: any) => (
            <TaskCard key={t.id} task={t} onOpen={onTaskClick} onToggleDone={onToggleDone} onScheduleOs={onScheduleOs} />
          ))}
        </Section>
      )}

      {snoozed.length > 0 && (
        <Section label="Adiadas" count={snoozed.length} tone="text-muted-foreground">
          {snoozed.map((t: any) => (
            <TaskCard key={t.id} task={t} onOpen={onTaskClick} onToggleDone={onToggleDone} onScheduleOs={onScheduleOs} />
          ))}
        </Section>
      )}
    </div>
  );
}

// ============================================================
// WEEK VIEW
// ============================================================
function WeekView({
  weekStart, orders, tasks, technicians, onCardClick, onCellClick, onTaskClick, onTaskDrop,
}: {
  weekStart: Date;
  orders: any[];
  tasks: any[];
  technicians: { id: string; full_name: string }[];
  onCardClick: (id: string) => void;
  onCellClick: (technicianId: string, date: Date) => void;
  onTaskClick: (task: ExistingTask) => void;
  onTaskDrop: (task: any, technicianId: string, dateKey: string) => void;
}) {
  const { t } = useI18n();
  const ag = t.agenda as any;
  const WEEKDAYS = ag.weekdaysShort as string[];
  const days = useMemo(
    () => Array.from({ length: 7 }, (_, i) => addDays(weekStart, i)),
    [weekStart],
  );
  const today = new Date();

  const ordersByTechAndDay = useMemo(() => {
    const map = new Map<string, any[]>();
    for (const o of orders) {
      if (!o.scheduled_start_at) continue;
      const dayKey = toLocalDateInput(new Date(o.scheduled_start_at));
      const techs = o.service_order_technicians || [];
      if (techs.length === 0) {
        const k = `__unassigned__|${dayKey}`;
        if (!map.has(k)) map.set(k, []);
        map.get(k)!.push(o);
      } else {
        for (const t of techs) {
          const k = `${t.user_id}|${dayKey}`;
          if (!map.has(k)) map.set(k, []);
          map.get(k)!.push(o);
        }
      }
    }
    return map;
  }, [orders]);

  const tasksByTechAndDay = useMemo(() => {
    const map = new Map<string, any[]>();
    for (const t of tasks) {
      if (!t.scheduled_start_at) continue;
      const dayKey = toLocalDateInput(new Date(t.scheduled_start_at));
      const k = `${t.assignee_user_id || '__unassigned__'}|${dayKey}`;
      if (!map.has(k)) map.set(k, []);
      map.get(k)!.push(t);
    }
    return map;
  }, [tasks]);

  // Linhas = técnicos + qualquer pessoa com tarefa na semana (admin/financeiro/vendas)
  const rows = useMemo(() => {
    const extra = new Map<string, string>();
    for (const t of tasks) {
      if (t.assignee_user_id && t.app_users?.full_name
          && !technicians.some((x) => x.id === t.assignee_user_id)) {
        extra.set(t.assignee_user_id, t.app_users.full_name);
      }
    }
    return [
      ...technicians,
      ...Array.from(extra.entries()).map(([id, full_name]) => ({ id, full_name })),
      { id: '__unassigned__', full_name: 'Sem responsável' },
    ];
  }, [technicians, tasks]);

  // Mobile (< lg): dias empilhados — zero scroll horizontal (Princípio 0)
  const mobileDays = days.map((d) => {
    const dayKey = toLocalDateInput(d);
    const dayOrders: any[] = [];
    const dayTasks: any[] = [];
    for (const r of rows) {
      dayOrders.push(...(ordersByTechAndDay.get(`${r.id}|${dayKey}`) || []));
      dayTasks.push(...(tasksByTechAndDay.get(`${r.id}|${dayKey}`) || []));
    }
    return { date: d, orders: dayOrders, tasks: dayTasks };
  });

  return (
    <>
    <div className="lg:hidden space-y-3">
      {mobileDays.map(({ date, orders: dOrders, tasks: dTasks }, i) => (
        <div key={i} className={cn('rounded-md border p-2.5 space-y-1.5', sameDay(date, today) && 'ring-1 ring-primary')}>
          <div className="flex items-center justify-between text-xs font-semibold">
            <span className={sameDay(date, today) ? 'text-primary' : 'text-muted-foreground'}>
              {WEEKDAYS[i]} · {date.getDate()}/{date.getMonth() + 1}
            </span>
            <span className="text-[10px] text-muted-foreground">
              {dOrders.length + dTasks.length > 0 ? `${dOrders.length + dTasks.length} item(ns)` : ''}
            </span>
          </div>
          {dOrders.length === 0 && dTasks.length === 0 && (
            <p className="text-[11px] text-muted-foreground">Livre</p>
          )}
          {dOrders.map((o) => (
            <div
              key={`mo-${o.id}`}
              onClick={() => onCardClick(o.id)}
              className={cn(
                'rounded-md p-1.5 text-xs cursor-pointer',
                statusConfig[o.status as keyof typeof statusConfig]?.className || 'bg-muted text-muted-foreground',
              )}
            >
              <span className="font-mono text-[10px] opacity-70 mr-1.5">{o.service_order_number}</span>
              <span className="font-medium">{o.clients?.name || '—'}</span>
              {o.scheduled_start_at && <span className="float-right font-semibold text-[10px]">{fmtTime(o.scheduled_start_at)}</span>}
            </div>
          ))}
          {dTasks.map((t) => (
            <div
              key={`mt-${t.id}`}
              onClick={() => onTaskClick(t)}
              className={cn(
                'rounded-md p-1.5 text-xs cursor-pointer',
                TASK_PRIORITY_CLASSES[t.priority] || TASK_PRIORITY_CLASSES.normal,
                t.status === 'done' && 'opacity-60 line-through',
              )}
            >
              <span className="font-medium">{t.title}</span>
              <span className="float-right text-[10px]">
                {t.app_users?.full_name ? t.app_users.full_name.split(' ')[0] : ''}
                {t.scheduled_start_at ? ` · ${fmtTime(t.scheduled_start_at)}` : ''}
              </span>
            </div>
          ))}
        </div>
      ))}
    </div>

    <div className="hidden lg:block">
      <div>
        <div className="grid grid-cols-[160px_repeat(7,1fr)] gap-1">
          <div className="p-2 text-xs font-semibold text-muted-foreground">Técnico</div>
          {days.map((d, i) => (
            <div
              key={i}
              className={cn(
                'p-2 text-center text-xs font-semibold rounded-md',
                sameDay(d, today) ? 'bg-primary/10 text-primary' : 'text-muted-foreground',
              )}
            >
              <div>{WEEKDAYS[i]}</div>
              <div className="text-sm font-bold text-foreground">{d.getDate()}/{d.getMonth() + 1}</div>
            </div>
          ))}

          {rows.map((tech) => (
            <div key={tech.id} className="contents">
              <div className="p-2 text-sm font-medium border-t flex items-center">
                {tech.full_name}
              </div>
              {days.map((d, i) => {
                const dayKey = toLocalDateInput(d);
                const cellOrders = ordersByTechAndDay.get(`${tech.id}|${dayKey}`) || [];
                const cellTasks = tasksByTechAndDay.get(`${tech.id}|${dayKey}`) || [];
                // Workload (padrão Asana/Sunsama): horas ocupadas no dia da pessoa
                const loadH = [...cellOrders, ...cellTasks].reduce((s: number, it: any) => {
                  const st = it.scheduled_start_at ? new Date(it.scheduled_start_at).getTime() : 0;
                  const en = it.scheduled_end_at ? new Date(it.scheduled_end_at).getTime() : 0;
                  return s + (st && en && en > st ? (en - st) / 3600000 : 0);
                }, 0);
                return (
                  <div
                    key={`${tech.id}-${i}`}
                    className={cn(
                      'border-t min-h-[88px] p-1 space-y-1 cursor-pointer hover:bg-muted/40 transition-colors rounded-sm',
                      sameDay(d, today) && 'bg-primary/5',
                    )}
                    onClick={(e) => {
                      if ((e.target as HTMLElement).closest('[data-card]')) return;
                      if (tech.id === '__unassigned__') return;
                      onCellClick(tech.id, d);
                    }}
                    onDragOver={(e) => e.preventDefault()}
                    onDrop={(e) => {
                      e.preventDefault();
                      try {
                        const payload = JSON.parse(e.dataTransfer.getData('application/x-agenda-task'));
                        if (payload?.id) onTaskDrop(payload, tech.id, dayKey);
                      } catch { /* drop de algo que não é tarefa */ }
                    }}
                  >
                    {loadH > 0 && (
                      <div className={cn(
                        'text-[10px] font-semibold text-right pr-1 tabular-nums',
                        loadH >= 8 ? 'text-destructive' : loadH >= 6 ? 'text-amber-600 dark:text-amber-400' : 'text-muted-foreground',
                      )}>
                        {Number.isInteger(loadH) ? loadH : loadH.toFixed(1)}h{loadH >= 8 ? ' ⚠' : ''}
                      </div>
                    )}
                    {cellOrders.map((o) => (
                      <div
                        key={`o-${o.id}`}
                        data-card
                        onClick={() => onCardClick(o.id)}
                        className={cn(
                          'rounded-md p-1.5 text-xs cursor-pointer hover:ring-1 hover:ring-primary transition-all',
                          statusConfig[o.status as keyof typeof statusConfig]?.className || 'bg-muted text-muted-foreground',
                        )}
                      >
                        <div className="flex items-center justify-between gap-1">
                          <span className="font-mono text-[10px] opacity-70">
                            {o.service_order_number}
                          </span>
                          {o.scheduled_start_at && (
                            <span className="text-[10px] font-semibold">
                              {fmtTime(o.scheduled_start_at)}
                            </span>
                          )}
                        </div>
                        <div className="font-medium truncate">
                          {o.clients?.name || '—'}
                        </div>
                        {o.vessels?.name && (
                          <div className="truncate opacity-75 text-[10px]">
                            {o.vessels.name}
                          </div>
                        )}
                      </div>
                    ))}
                    {cellTasks.map((t) => (
                      <div
                        key={`t-${t.id}`}
                        data-card
                        draggable={!!t.scheduled_start_at}
                        onDragStart={(e) => {
                          e.dataTransfer.setData('application/x-agenda-task', JSON.stringify(t));
                          e.dataTransfer.effectAllowed = 'move';
                        }}
                        onClick={(e) => { e.stopPropagation(); onTaskClick(t); }}
                        className={cn(
                          'rounded-md p-1.5 text-xs cursor-pointer hover:ring-1 hover:ring-primary transition-all',
                          TASK_PRIORITY_CLASSES[t.priority] || TASK_PRIORITY_CLASSES.normal,
                          t.status === 'done' && 'opacity-60 line-through',
                        )}
                      >
                        <div className="flex items-center justify-between gap-1">
                          <span className="text-[10px] uppercase tracking-wide opacity-70 flex items-center gap-1">
                            <ListChecks className="h-3 w-3" /> Tarefa
                          </span>
                          {t.scheduled_start_at && (
                            <span className="text-[10px] font-semibold">
                              {fmtTime(t.scheduled_start_at)}
                            </span>
                          )}
                        </div>
                        <div className="font-medium truncate">{t.title}</div>
                        {t.location && (
                          <div className="truncate opacity-75 text-[10px]">{t.location}</div>
                        )}
                      </div>
                    ))}
                  </div>
                );
              })}
            </div>
          ))}
        </div>
      </div>
    </div>
    </>
  );
}

// ============================================================
// MONTH VIEW
// ============================================================
function MonthView({
  cursor, orders, tasks, selectedDay, onSelectDay, onCardClick, onTaskClick,
}: {
  cursor: Date;
  orders: any[];
  tasks: any[];
  selectedDay: Date | null;
  onSelectDay: (d: Date | null) => void;
  onCardClick: (id: string) => void;
  onTaskClick: (task: ExistingTask) => void;
}) {
  const { t } = useI18n();
  const ag = t.agenda as any;
  const WEEKDAYS = ag.weekdaysShort as string[];
  const MONTH_NAMES = ag.monthNames as string[];
  const statusLabels = t.status as Record<string, string>;
  const today = new Date();
  const first = startOfMonth(cursor);
  const gridStart = startOfWeek(first);
  const days = useMemo(
    () => Array.from({ length: 42 }, (_, i) => addDays(gridStart, i)),
    [gridStart],
  );

  const ordersByDay = useMemo(() => {
    const map = new Map<string, any[]>();
    for (const o of orders) {
      if (!o.scheduled_start_at) continue;
      const k = toLocalDateInput(new Date(o.scheduled_start_at));
      if (!map.has(k)) map.set(k, []);
      map.get(k)!.push(o);
    }
    return map;
  }, [orders]);

  const tasksByDay = useMemo(() => {
    const map = new Map<string, any[]>();
    for (const t of tasks) {
      if (!t.scheduled_start_at) continue;
      const k = toLocalDateInput(new Date(t.scheduled_start_at));
      if (!map.has(k)) map.set(k, []);
      map.get(k)!.push(t);
    }
    return map;
  }, [tasks]);

  const selectedKey = selectedDay ? toLocalDateInput(selectedDay) : null;
  const selectedOrders = selectedKey ? ordersByDay.get(selectedKey) || [] : [];
  const selectedTasks = selectedKey ? tasksByDay.get(selectedKey) || [] : [];

  return (
    <div className="grid gap-4 grid-cols-1 lg:grid-cols-[1fr_320px]">
      <div>
        <div className="text-center text-lg font-semibold mb-3">
          {MONTH_NAMES[cursor.getMonth()]} {cursor.getFullYear()}
        </div>
        <div className="grid grid-cols-7 gap-1">
          {WEEKDAYS.map((w) => (
            <div key={w} className="p-2 text-center text-xs font-semibold text-muted-foreground">
              {w}
            </div>
          ))}
          {days.map((d, i) => {
            const dayKey = toLocalDateInput(d);
            const dayOrders = ordersByDay.get(dayKey) || [];
            const dayTasks = tasksByDay.get(dayKey) || [];
            const inMonth = d.getMonth() === cursor.getMonth();
            const isToday = sameDay(d, today);
            const isSelected = selectedDay && sameDay(d, selectedDay);
            return (
              <button
                key={i}
                onClick={() => onSelectDay(d)}
                className={cn(
                  'min-h-[80px] rounded-md border p-2 text-left transition-colors',
                  inMonth ? 'bg-background' : 'bg-muted/30 text-muted-foreground',
                  isToday && 'ring-2 ring-primary',
                  isSelected && 'bg-primary/10 border-primary',
                  'hover:bg-muted/50',
                )}
              >
                <div className="text-sm font-medium">{d.getDate()}</div>
                <div className="mt-1 flex flex-wrap gap-1">
                  {dayOrders.length > 0 && (
                    <span className="inline-flex items-center rounded-full bg-primary/15 text-primary px-2 py-0.5 text-[10px] font-medium">
                      {dayOrders.length} OS
                    </span>
                  )}
                  {dayTasks.length > 0 && (
                    <span className="inline-flex items-center rounded-full bg-secondary text-secondary-foreground px-2 py-0.5 text-[10px] font-medium">
                      {dayTasks.length} tarefa{dayTasks.length > 1 ? 's' : ''}
                    </span>
                  )}
                </div>
              </button>
            );
          })}
        </div>
      </div>

      <Card className="p-4 space-y-3 max-h-[600px] overflow-y-auto">
        <div className="flex items-center gap-2 text-sm font-semibold">
          <CalendarDays className="h-4 w-4" />
          {selectedDay
            ? selectedDay.toLocaleDateString('pt-BR', { weekday: 'long', day: 'numeric', month: 'long' })
            : 'Selecione um dia'}
        </div>
        {!selectedDay && (
          <p className="text-xs text-muted-foreground">
            Clique em um dia do calendário para ver OS e tarefas programadas.
          </p>
        )}
        {selectedDay && selectedOrders.length === 0 && selectedTasks.length === 0 && (
          <p className="text-xs text-muted-foreground">Nenhuma OS ou tarefa neste dia.</p>
        )}
        {selectedOrders.map((o) => (
          <div
            key={`o-${o.id}`}
            onClick={() => onCardClick(o.id)}
            className={cn(
              'rounded-md p-2 text-xs cursor-pointer hover:ring-1 hover:ring-primary transition-all',
              statusConfig[o.status as keyof typeof statusConfig]?.className || 'bg-muted text-muted-foreground',
            )}
          >
            <div className="flex items-center justify-between">
              <span className="font-mono opacity-70">{o.service_order_number}</span>
              {o.scheduled_start_at && (
                <span className="font-semibold">{fmtTime(o.scheduled_start_at)}</span>
              )}
            </div>
            <div className="font-medium mt-0.5">
              {o.clients?.name || '—'}
            </div>
            {o.vessels?.name && (
              <div className="opacity-75 text-[11px]">{o.vessels.name}</div>
            )}
            <StatusBadge className={cn('mt-1', statusConfig[o.status as keyof typeof statusConfig]?.className || 'bg-muted text-muted-foreground')}>
              {statusLabels[o.status] || o.status}
            </StatusBadge>
          </div>
        ))}
        {selectedTasks.map((t) => (
          <div
            key={`t-${t.id}`}
            onClick={() => onTaskClick(t)}
            className={cn(
              'rounded-md p-2 text-xs cursor-pointer hover:ring-1 hover:ring-primary transition-all',
              TASK_PRIORITY_CLASSES[t.priority] || TASK_PRIORITY_CLASSES.normal,
              t.status === 'done' && 'opacity-60 line-through',
            )}
          >
            <div className="flex items-center justify-between">
              <span className="uppercase tracking-wide opacity-70 text-[10px] flex items-center gap-1">
                <ListChecks className="h-3 w-3" /> Tarefa
              </span>
              {t.scheduled_start_at && (
                <span className="font-semibold">{fmtTime(t.scheduled_start_at)}</span>
              )}
            </div>
            <div className="font-medium mt-0.5">{t.title}</div>
            {t.app_users?.full_name && (
              <div className="opacity-75 text-[11px]">{t.app_users.full_name}</div>
            )}
            {t.location && (
              <div className="opacity-75 text-[11px]">{t.location}</div>
            )}
          </div>
        ))}
      </Card>
    </div>
  );
}

// ============================================================
// QUICK SCHEDULE DIALOG (OS)
// ============================================================
function QuickScheduleDialog({
  open, onOpenChange, technicians, prefillTechnicianId, prefillDate, prefillOrderId,
}: {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  technicians: { id: string; full_name: string }[];
  prefillTechnicianId?: string;
  prefillDate?: string;
  prefillOrderId?: string;
}) {
  const { data: schedulable = [] } = useSchedulableOrders();
  const quickSchedule = useQuickSchedule();

  const [orderId, setOrderId] = useState('');
  const [technicianId, setTechnicianId] = useState('');
  const [date, setDate] = useState('');
  const [startTime, setStartTime] = useState('09:00');
  const [endTime, setEndTime] = useState('11:00');
  // Local submitting flag prevents double-submit during the brief async window
  // before quickSchedule.isPending becomes true after mutateAsync is called
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (open) {
      setOrderId(prefillOrderId || '');
      setTechnicianId(prefillTechnicianId || '');
      setDate(prefillDate || toLocalDateInput(new Date()));
      setStartTime('09:00');
      setEndTime('11:00');
      setSubmitting(false);
    }
  }, [open, prefillTechnicianId, prefillDate, prefillOrderId]);

  const handleSave = async () => {
    if (submitting || quickSchedule.isPending) return;
    if (!orderId || !technicianId || !date || !startTime) {
      toast.error('Preencha OS, técnico, data e hora de início');
      return;
    }
    const startISO = new Date(`${date}T${startTime}:00`).toISOString();
    const endISO = endTime ? new Date(`${date}T${endTime}:00`).toISOString() : null;

    setSubmitting(true);
    try {
      const res: any = await quickSchedule.mutateAsync({
        service_order_id: orderId,
        technician_user_id: technicianId,
        scheduled_start_at: startISO,
        scheduled_end_at: endISO,
      });
      // Success: only reached if mutateAsync resolves without throwing
      toast.success('OS agendada com sucesso');
      if (res?.warning) toast.warning(res.warning);
      onOpenChange(false);
    } catch (err: any) {
      // Error: only reached if mutateAsync throws (mutationFn threw)
      toast.error(err?.message || 'Erro ao agendar OS');
      setSubmitting(false);
    }
  };

  const isBusy = submitting || quickSchedule.isPending;

  return (
    <Dialog open={open} onOpenChange={(v) => { if (!isBusy) onOpenChange(v); }}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Agendar Ordem de Serviço</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <div className="space-y-2">
            <Label>Ordem de Serviço *</Label>
            <EntityCombobox
              value={orderId}
              onChange={setOrderId}
              placeholder="Selecione uma OS"
              options={schedulable.map((o: any) => ({
                value: o.id,
                label: `${o.service_order_number} — ${o.clients?.name || '—'}`,
                description: o.vessels?.name || undefined,
                searchTerms: [
                  o.service_order_number,
                  o.clients?.name || '',
                  o.vessels?.name || '',
                ],
              }))}
            />
          </div>

          <div className="space-y-2">
            <Label>Técnico *</Label>
            <EntityCombobox
              value={technicianId}
              onChange={setTechnicianId}
              placeholder="Selecione um técnico"
              options={technicians.map((t) => ({
                value: t.id,
                label: t.full_name,
                description: undefined,
              }))}
            />
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
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={isBusy}>
            Cancelar
          </Button>
          <Button onClick={handleSave} disabled={isBusy}>
            {isBusy && <Loader2 className="h-4 w-4 animate-spin mr-1" />}
            {isBusy ? 'Agendando...' : 'Agendar'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
