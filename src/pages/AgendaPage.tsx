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
import { ChevronLeft, ChevronRight, CalendarDays, Plus, Loader2, ListChecks, Briefcase } from 'lucide-react';
import { cn } from '@/lib/utils';
import {
  useAgendaOrders,
  useAgendaTasks,
  useTechnicians,
  useSchedulableOrders,
  useQuickSchedule,
} from '@/hooks/use-agenda';
import { AgendaTaskDialog, type ExistingTask } from '@/components/AgendaTaskDialog';
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

type ViewMode = 'week' | 'month';

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
  const [view, setView] = useState<ViewMode>('week');
  const [cursor, setCursor] = useState(() => new Date());
  const [selectedDay, setSelectedDay] = useState<Date | null>(null);

  const [osDialogOpen, setOsDialogOpen] = useState(false);
  const [taskDialogOpen, setTaskDialogOpen] = useState(false);
  const [editingTask, setEditingTask] = useState<ExistingTask | null>(null);
  const [prefill, setPrefill] = useState<{ technicianId?: string; date?: string }>({});
  const [techFilter, setTechFilter] = useState<string>('all');

  const range = useMemo(() => {
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

  const isLoading = loadingOrders || loadingTasks;

  const filteredOrders = useMemo(() => (
    techFilter === 'all'
      ? orders
      : (orders || []).filter((o: any) =>
          (o.service_order_technicians || []).some((t: any) => t.user_id === techFilter || t.technician_user_id === techFilter)
        )
  ), [orders, techFilter]);
  const filteredTasks = useMemo(() => (
    techFilter === 'all'
      ? tasks
      : (tasks || []).filter((t: any) => t.technician_user_id === techFilter)
  ), [tasks, techFilter]);

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
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div className="flex items-center gap-1 rounded-md border p-1">
            <Button size="sm" variant={view === 'week' ? 'default' : 'ghost'} onClick={() => setView('week')}>
              Semana
            </Button>
            <Button size="sm" variant={view === 'month' ? 'default' : 'ghost'} onClick={() => setView('month')}>
              Mês
            </Button>
          </div>

          <div className="flex items-center gap-2 flex-wrap">
            <Button size="sm" variant="outline" onClick={() => handleNav(-1)}>
              <ChevronLeft className="h-4 w-4" />
              <span className="hidden sm:inline">{view === 'week' ? 'Semana anterior' : 'Mês anterior'}</span>
            </Button>
            <Button size="sm" variant="outline" onClick={() => setCursor(new Date())}>Hoje</Button>
            <Button size="sm" variant="outline" onClick={() => handleNav(1)}>
              <span className="hidden sm:inline">{view === 'week' ? 'Semana seguinte' : 'Mês seguinte'}</span>
              <ChevronRight className="h-4 w-4" />
            </Button>
            <Select value={techFilter} onValueChange={setTechFilter}>
              <SelectTrigger className="w-[180px]">
                <SelectValue placeholder="Filtrar por técnico" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">Todos os técnicos</SelectItem>
                {technicians.map((tech) => (
                  <SelectItem key={tech.id} value={tech.id}>{tech.full_name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
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
        ) : view === 'week' ? (
          <WeekView
            weekStart={range.from}
            orders={filteredOrders}
            tasks={filteredTasks}
            technicians={technicians}
            onCardClick={(id) => navigate(`/service-orders/${id}`)}
            onCellClick={openQuickSchedule}
            onTaskClick={(t) => openTaskDialog(undefined, undefined, t)}
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
        onOpenChange={setOsDialogOpen}
        technicians={technicians}
        prefillTechnicianId={prefill.technicianId}
        prefillDate={prefill.date}
      />

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
// WEEK VIEW
// ============================================================
function WeekView({
  weekStart, orders, tasks, technicians, onCardClick, onCellClick, onTaskClick,
}: {
  weekStart: Date;
  orders: any[];
  tasks: any[];
  technicians: { id: string; full_name: string }[];
  onCardClick: (id: string) => void;
  onCellClick: (technicianId: string, date: Date) => void;
  onTaskClick: (task: ExistingTask) => void;
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
      const k = `${t.technician_user_id}|${dayKey}`;
      if (!map.has(k)) map.set(k, []);
      map.get(k)!.push(t);
    }
    return map;
  }, [tasks]);

  const rows = [
    ...technicians,
    { id: '__unassigned__', full_name: 'Sem técnico atribuído' },
  ];

  return (
    <div className="-mx-4 px-4 overflow-x-auto">
      <div className="min-w-[700px]">
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
                  >
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
                          {o.clients?.full_name_or_company_name || '—'}
                        </div>
                        {o.vessels?.boat_name && (
                          <div className="truncate opacity-75 text-[10px]">
                            {o.vessels.boat_name}
                          </div>
                        )}
                      </div>
                    ))}
                    {cellTasks.map((t) => (
                      <div
                        key={`t-${t.id}`}
                        data-card
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
              {o.clients?.full_name_or_company_name || '—'}
            </div>
            {o.vessels?.boat_name && (
              <div className="opacity-75 text-[11px]">{o.vessels.boat_name}</div>
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
  open, onOpenChange, technicians, prefillTechnicianId, prefillDate,
}: {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  technicians: { id: string; full_name: string }[];
  prefillTechnicianId?: string;
  prefillDate?: string;
}) {
  const { data: schedulable = [] } = useSchedulableOrders();
  const quickSchedule = useQuickSchedule();

  const [orderId, setOrderId] = useState('');
  const [technicianId, setTechnicianId] = useState('');
  const [date, setDate] = useState('');
  const [startTime, setStartTime] = useState('09:00');
  const [endTime, setEndTime] = useState('11:00');

  useEffect(() => {
    if (open) {
      setOrderId('');
      setTechnicianId(prefillTechnicianId || '');
      setDate(prefillDate || toLocalDateInput(new Date()));
      setStartTime('09:00');
      setEndTime('11:00');
    }
  }, [open, prefillTechnicianId, prefillDate]);

  const handleSave = async () => {
    if (!orderId || !technicianId || !date || !startTime) {
      toast.error('Preencha OS, técnico, data e hora de início');
      return;
    }
    const startISO = new Date(`${date}T${startTime}:00`).toISOString();
    const endISO = endTime ? new Date(`${date}T${endTime}:00`).toISOString() : null;

    try {
      await quickSchedule.mutateAsync({
        service_order_id: orderId,
        technician_user_id: technicianId,
        scheduled_start_at: startISO,
        scheduled_end_at: endISO,
      });
      toast.success('OS agendada com sucesso');
      onOpenChange(false);
    } catch (err: any) {
      toast.error(err?.message || 'Erro ao agendar OS');
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
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
                label: `${o.service_order_number} — ${o.clients?.full_name_or_company_name || '—'}`,
                description: o.vessels?.boat_name || undefined,
                searchTerms: [
                  o.service_order_number,
                  o.clients?.full_name_or_company_name || '',
                  o.vessels?.boat_name || '',
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
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancelar</Button>
          <Button onClick={handleSave} disabled={quickSchedule.isPending}>
            {quickSchedule.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
            Agendar
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
