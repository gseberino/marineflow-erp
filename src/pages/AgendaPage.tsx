import { useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { PageHeader } from '@/components/PageHeader';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { StatusBadge } from '@/components/StatusBadge';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { ChevronLeft, ChevronRight, CalendarDays, Plus, Loader2 } from 'lucide-react';
import { cn } from '@/lib/utils';
import { useAgendaOrders, useTechnicians, useSchedulableOrders, useQuickSchedule } from '@/hooks/use-agenda';
import { toast } from 'sonner';
import { useI18n } from '@/i18n';
import { statusConfig } from '@/lib/constants';

type ViewMode = 'week' | 'month';

function startOfWeek(d: Date): Date {
  const date = new Date(d);
  date.setHours(0, 0, 0, 0);
  const day = date.getDay(); // 0=Sun
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
  const x = new Date(d.getFullYear(), d.getMonth(), 1);
  return x;
}

function endOfMonth(d: Date): Date {
  const x = new Date(d.getFullYear(), d.getMonth() + 1, 0, 23, 59, 59, 999);
  return x;
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

export default function AgendaPage() {
  const navigate = useNavigate();
  const [view, setView] = useState<ViewMode>('week');
  const [cursor, setCursor] = useState(() => new Date());
  const [selectedDay, setSelectedDay] = useState<Date | null>(null);

  const [dialogOpen, setDialogOpen] = useState(false);
  const [prefill, setPrefill] = useState<{ technicianId?: string; date?: string }>({});

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

  const { data: orders = [], isLoading } = useAgendaOrders(
    range.from.toISOString(),
    range.to.toISOString(),
  );
  const { data: technicians = [] } = useTechnicians();

  const handleNav = (delta: number) => {
    if (view === 'week') setCursor(addDays(cursor, delta * 7));
    else setCursor(new Date(cursor.getFullYear(), cursor.getMonth() + delta, 1));
  };

  const openQuickSchedule = (technicianId?: string, date?: Date) => {
    setPrefill({
      technicianId,
      date: date ? toLocalDateInput(date) : toLocalDateInput(new Date()),
    });
    setDialogOpen(true);
  };

  return (
    <div className="space-y-4">
      <PageHeader
        title="Agenda"
        description="Programação de ordens de serviço por técnico e data"
      >
        <Button onClick={() => openQuickSchedule()}>
          <Plus className="h-4 w-4" /> Agendar OS
        </Button>
      </PageHeader>

      <Card className="p-4 space-y-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div className="flex items-center gap-1 rounded-md border p-1">
            <Button
              size="sm"
              variant={view === 'week' ? 'default' : 'ghost'}
              onClick={() => setView('week')}
            >Semana</Button>
            <Button
              size="sm"
              variant={view === 'month' ? 'default' : 'ghost'}
              onClick={() => setView('month')}
            >Mês</Button>
          </div>

          <div className="flex items-center gap-2">
            <Button size="sm" variant="outline" onClick={() => handleNav(-1)}>
              <ChevronLeft className="h-4 w-4" />
              {view === 'week' ? 'Semana anterior' : 'Mês anterior'}
            </Button>
            <Button size="sm" variant="outline" onClick={() => setCursor(new Date())}>
              Hoje
            </Button>
            <Button size="sm" variant="outline" onClick={() => handleNav(1)}>
              {view === 'week' ? 'Semana seguinte' : 'Mês seguinte'}
              <ChevronRight className="h-4 w-4" />
            </Button>
          </div>
        </div>

        {isLoading ? (
          <div className="flex items-center justify-center py-12 text-muted-foreground">
            <Loader2 className="h-5 w-5 animate-spin" />
          </div>
        ) : view === 'week' ? (
          <WeekView
            weekStart={range.from}
            orders={orders}
            technicians={technicians}
            onCardClick={(id) => navigate(`/service-orders/${id}`)}
            onCellClick={openQuickSchedule}
          />
        ) : (
          <MonthView
            cursor={cursor}
            orders={orders}
            selectedDay={selectedDay}
            onSelectDay={setSelectedDay}
            onCardClick={(id) => navigate(`/service-orders/${id}`)}
          />
        )}
      </Card>

      <QuickScheduleDialog
        open={dialogOpen}
        onOpenChange={setDialogOpen}
        technicians={technicians}
        prefillTechnicianId={prefill.technicianId}
        prefillDate={prefill.date}
      />
    </div>
  );
}

// ============================================================
// WEEK VIEW
// ============================================================
function WeekView({
  weekStart, orders, technicians, onCardClick, onCellClick,
}: {
  weekStart: Date;
  orders: any[];
  technicians: { id: string; full_name: string }[];
  onCardClick: (id: string) => void;
  onCellClick: (technicianId: string, date: Date) => void;
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
      const d = new Date(o.scheduled_start_at);
      const dayKey = toLocalDateInput(d);
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

  const rows = [
    ...technicians,
    { id: '__unassigned__', full_name: 'Sem técnico atribuído' },
  ];

  return (
    <div className="overflow-x-auto">
      <div className="min-w-[900px]">
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
                        key={o.id}
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
  cursor, orders, selectedDay, onSelectDay, onCardClick,
}: {
  cursor: Date;
  orders: any[];
  selectedDay: Date | null;
  onSelectDay: (d: Date | null) => void;
  onCardClick: (id: string) => void;
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

  const selectedOrders = selectedDay
    ? ordersByDay.get(toLocalDateInput(selectedDay)) || []
    : [];

  return (
    <div className="grid gap-4 lg:grid-cols-[1fr_320px]">
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
                {dayOrders.length > 0 && (
                  <div className="mt-1">
                    <span className="inline-flex items-center rounded-full bg-primary/15 text-primary px-2 py-0.5 text-[10px] font-medium">
                      {dayOrders.length} OS
                    </span>
                  </div>
                )}
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
            Clique em um dia do calendário para ver as OS programadas.
          </p>
        )}
        {selectedDay && selectedOrders.length === 0 && (
          <p className="text-xs text-muted-foreground">Nenhuma OS agendada neste dia.</p>
        )}
        {selectedOrders.map((o) => (
          <div
            key={o.id}
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
      </Card>
    </div>
  );
}

// ============================================================
// QUICK SCHEDULE DIALOG
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

  // Reset when opening
  useMemo(() => {
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
            <Select value={orderId} onValueChange={setOrderId}>
              <SelectTrigger><SelectValue placeholder="Selecione uma OS" /></SelectTrigger>
              <SelectContent>
                {schedulable.map((o: any) => (
                  <SelectItem key={o.id} value={o.id}>
                    {o.service_order_number} — {o.clients?.full_name_or_company_name || '—'}
                    {o.vessels?.boat_name ? ` (${o.vessels.boat_name})` : ''}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-2">
            <Label>Técnico *</Label>
            <Select value={technicianId} onValueChange={setTechnicianId}>
              <SelectTrigger><SelectValue placeholder="Selecione um técnico" /></SelectTrigger>
              <SelectContent>
                {technicians.map((t) => (
                  <SelectItem key={t.id} value={t.id}>{t.full_name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
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
