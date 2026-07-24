import { useNavigate } from 'react-router-dom';
import { Checkbox } from '@/components/ui/checkbox';
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { cn } from '@/lib/utils';
import {
  Bot, Cog, Briefcase, User, DollarSign, ShoppingCart, Package, FileText,
  Anchor, Clock, CalendarDays, MapPin, AlarmClock, Timer,
} from 'lucide-react';
import { toast } from 'sonner';
import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { PaymentDialog } from '@/components/PaymentDialog';
import { supabase } from '@/integrations/supabase/client';
import { useSnoozeTask, type RelatedEntityType } from '@/hooks/use-agenda';

const ENTITY_CONFIG: Record<RelatedEntityType, { label: string; Icon: typeof Briefcase; route: (id: string) => string }> = {
  service_order:  { label: 'OS',         Icon: Briefcase,    route: (id) => `/service-orders/${id}` },
  quote:          { label: 'Orçamento',  Icon: FileText,     route: (id) => `/service-orders/${id}` },
  external_quote: { label: 'Orçamento',  Icon: FileText,     route: (id) => `/external-quotes/${id}` },
  client:         { label: 'Cliente',    Icon: User,         route: (id) => `/clients/${id}` },
  vessel:         { label: 'Embarcação', Icon: Anchor,       route: () => '/service-orders' },
  receivable:     { label: 'Recebível',  Icon: DollarSign,   route: () => '/financial' },
  payable:        { label: 'Pagável',    Icon: DollarSign,   route: () => '/financial' },
  purchase_order: { label: 'OC',         Icon: ShoppingCart, route: () => '/purchase-orders' },
  collection:     { label: 'Cobrança',   Icon: DollarSign,   route: () => '/financial' },
  stock_item:     { label: 'Estoque',    Icon: Package,      route: () => '/inventory' },
};

const PRIORITY_BAR: Record<string, string> = {
  low: 'bg-muted-foreground/30',
  normal: 'bg-primary/40',
  high: 'bg-amber-500',
  urgent: 'bg-destructive',
};

const SOURCE_BADGE: Record<string, { label: string; Icon: typeof Bot; className: string }> = {
  ai:         { label: 'IA',     Icon: Bot, className: 'text-violet-600 bg-violet-500/10 dark:text-violet-400' },
  automation: { label: 'Auto',   Icon: Cog, className: 'text-teal-700 bg-teal-500/10 dark:text-teal-400' },
  recurrence: { label: 'Recorr.', Icon: AlarmClock, className: 'text-sky-700 bg-sky-500/10 dark:text-sky-400' },
};

function fmtWhen(t: any): { text: string; overdue: boolean } | null {
  const now = new Date();
  const dateOpts: Intl.DateTimeFormatOptions = { day: '2-digit', month: '2-digit' };
  if (t.scheduled_start_at) {
    const d = new Date(t.scheduled_start_at);
    const time = d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
    const sameDay = d.toDateString() === now.toDateString();
    return {
      text: sameDay ? time : `${d.toLocaleDateString('pt-BR', dateOpts)} ${time}`,
      overdue: (t.scheduled_end_at ? new Date(t.scheduled_end_at) : d) < now,
    };
  }
  if (t.due_at) {
    const d = new Date(t.due_at);
    const sameDay = d.toDateString() === now.toDateString();
    return {
      text: sameDay ? 'hoje' : d.toLocaleDateString('pt-BR', dateOpts),
      overdue: d < new Date(now.getFullYear(), now.getMonth(), now.getDate()),
    };
  }
  return null;
}

/** Botão "que resolve": a ação do fluxo que encerra a tarefa, direto no card (padrão Pipedrive/HubSpot). */
function TaskActionButton({ task, onScheduleOs }: { task: any; onScheduleOs?: (task: any) => void }) {
  const navigate = useNavigate();
  const [payOpen, setPayOpen] = useState(false);
  const [payRecord, setPayRecord] = useState<any>(null);
  const et = task.related_entity_type as RelatedEntityType | null;
  if (!et || task.status === 'done') return null;

  const openPayment = async (e: React.MouseEvent) => {
    e.stopPropagation();
    const table = et === 'receivable' ? 'receivables' : 'payables';
    const { data, error } = await supabase.from(table).select('*, clients(name)').eq('id', task.related_entity_id).maybeSingle();
    if (error || !data) { toast.error('Registro financeiro não encontrado'); return; }
    if ((data as any).status === 'paid') { toast.info('Este título já está pago — a tarefa se resolve no próximo ciclo.'); return; }
    setPayRecord(data);
    setPayOpen(true);
  };

  const actions: Partial<Record<RelatedEntityType, { label: string; onClick: (e: React.MouseEvent) => void }>> = {
    receivable: { label: 'Registrar pagamento', onClick: openPayment },
    payable: { label: 'Registrar pagamento', onClick: openPayment },
    purchase_order: { label: 'Receber OC', onClick: (e) => { e.stopPropagation(); navigate('/purchase-orders'); } },
    stock_item: { label: 'Repor', onClick: (e) => { e.stopPropagation(); navigate('/inventory/smart-purchase'); } },
    service_order: task.automation_key?.startsWith('r1:') && onScheduleOs
      ? { label: 'Agendar OS', onClick: (e) => { e.stopPropagation(); onScheduleOs(task); } }
      : undefined,
  };
  const action = actions[et];
  if (!action) return null;

  return (
    <>
      <Button
        size="sm"
        variant="outline"
        className="h-6 px-2 text-[11px] border-primary/40 text-primary hover:bg-primary/10"
        onClick={action.onClick}
      >
        {action.label}
      </Button>
      {payRecord && (
        <span onClick={(e) => e.stopPropagation()}>
          <PaymentDialog
            open={payOpen}
            onOpenChange={(v: boolean) => { setPayOpen(v); if (!v) setPayRecord(null); }}
            receivable={et === 'receivable' ? payRecord : undefined}
            payable={et === 'payable' ? payRecord : undefined}
          />
        </span>
      )}
    </>
  );
}

export function TaskCard({
  task, onOpen, onToggleDone, compact = false, onScheduleOs,
}: {
  task: any;
  onOpen?: (task: any) => void;
  onToggleDone?: (id: string, done: boolean) => void;
  compact?: boolean;
  onScheduleOs?: (task: any) => void;
}) {
  const navigate = useNavigate();
  const snooze = useSnoozeTask();
  const done = task.status === 'done';
  const snoozed = task.snoozed_until && new Date(task.snoozed_until) > new Date();

  const doSnooze = (until: string | null, label: string) => {
    snooze.mutate({ id: task.id, until }, {
      onSuccess: () => toast.success(label),
      onError: (e: any) => toast.error(e?.message || 'Erro ao adiar'),
    });
  };
  const tomorrow8 = () => {
    const d = new Date();
    d.setDate(d.getDate() + 1);
    d.setHours(8, 0, 0, 0);
    return d.toISOString();
  };
  const entity = task.related_entity_type
    ? ENTITY_CONFIG[task.related_entity_type as RelatedEntityType]
    : null;
  const source = SOURCE_BADGE[task.source];
  const when = fmtWhen(task);
  const checklist: { done: boolean }[] = Array.isArray(task.checklist) ? task.checklist : [];
  const checklistDone = checklist.filter((c) => c.done).length;

  return (
    <div
      className={cn(
        'group relative flex items-start gap-2.5 rounded-md border bg-card pl-3 pr-2.5 py-2 transition-colors',
        onOpen && 'cursor-pointer hover:bg-muted/40',
        done && 'opacity-55',
      )}
      onClick={() => onOpen?.(task)}
    >
      <span className={cn('absolute left-0 top-1.5 bottom-1.5 w-1 rounded-full', PRIORITY_BAR[task.priority] || PRIORITY_BAR.normal)} />
      {onToggleDone && (
        <span onClick={(e) => e.stopPropagation()} className="pt-0.5">
          <Checkbox
            checked={done}
            onCheckedChange={(v) => onToggleDone(task.id, v === true)}
            aria-label={done ? 'Reabrir tarefa' : 'Concluir tarefa'}
          />
        </span>
      )}
      <div className="min-w-0 flex-1">
        <div className={cn('text-sm font-medium leading-snug', done && 'line-through')}>
          {task.title}
        </div>
        <div className="mt-1 flex flex-wrap items-center gap-x-2.5 gap-y-1 text-[11px] text-muted-foreground">
          {when && (
            <span className={cn('inline-flex items-center gap-1', when.overdue && !done && 'text-destructive font-semibold')}>
              {task.scheduled_start_at ? <Clock className="h-3 w-3" /> : <CalendarDays className="h-3 w-3" />}
              {when.text}
            </span>
          )}
          {task.app_users?.full_name && (
            <span className="inline-flex items-center gap-1">
              <User className="h-3 w-3" /> {task.app_users.full_name.split(' ')[0]}
            </span>
          )}
          {entity && (
            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation();
                navigate(entity.route(task.related_entity_id));
              }}
              className="inline-flex items-center gap-1 rounded-full bg-primary/10 px-2 py-0.5 font-medium text-primary hover:bg-primary/20 transition-colors"
            >
              <entity.Icon className="h-3 w-3" /> {entity.label}
            </button>
          )}
          {source && (
            <span className={cn('inline-flex items-center gap-1 rounded-full px-2 py-0.5 font-medium', source.className)}>
              <source.Icon className="h-3 w-3" /> {source.label}
            </span>
          )}
          {checklist.length > 0 && (
            <span>☑ {checklistDone}/{checklist.length}</span>
          )}
          {!compact && task.location && (
            <span className="inline-flex items-center gap-1"><MapPin className="h-3 w-3" /> {task.location}</span>
          )}
          {!compact && task.clients?.name && <span>{task.clients.name}</span>}
          {snoozed && (
            <span className="inline-flex items-center gap-1 text-sky-600 dark:text-sky-400">
              <Timer className="h-3 w-3" /> adiada
            </span>
          )}
          <TaskActionButton task={task} onScheduleOs={onScheduleOs} />
        </div>
      </div>
      {!done && onToggleDone && (
        <span onClick={(e) => e.stopPropagation()}>
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <button
                type="button"
                aria-label="Adiar tarefa"
                className="opacity-0 group-hover:opacity-100 focus:opacity-100 transition-opacity rounded p-1 text-muted-foreground hover:bg-muted"
              >
                <Timer className="h-3.5 w-3.5" />
              </button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <DropdownMenuItem onClick={() => doSnooze(new Date(Date.now() + 3600000).toISOString(), 'Adiada por 1 hora')}>
                Adiar 1 hora
              </DropdownMenuItem>
              <DropdownMenuItem onClick={() => doSnooze(tomorrow8(), 'Adiada para amanhã 08:00')}>
                Adiar para amanhã
              </DropdownMenuItem>
              {snoozed && (
                <DropdownMenuItem onClick={() => doSnooze(null, 'Adiamento removido')}>
                  Remover adiamento
                </DropdownMenuItem>
              )}
            </DropdownMenuContent>
          </DropdownMenu>
        </span>
      )}
    </div>
  );
}
