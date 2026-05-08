import { useRecordHistory } from '@/hooks/use-audit-log';
import { formatDistanceToNow, format } from 'date-fns';
import { ptBR } from 'date-fns/locale';
import {
  RefreshCw, XCircle, RotateCcw, GitCommit, Pencil, Clock,
} from 'lucide-react';
import { Skeleton } from '@/components/ui/skeleton';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';
import { Badge } from '@/components/ui/badge';
import { cn } from '@/lib/utils';

// ── Action metadata ────────────────────────────────────────────────────────────
const ACTION_META: Record<string, { icon: typeof Pencil; color: string; label: string; bg: string }> = {
  update:         { icon: Pencil,      color: 'text-blue-600',   bg: 'bg-blue-50 dark:bg-blue-950/50',   label: 'Atualização' },
  cancel:         { icon: XCircle,     color: 'text-red-600',    bg: 'bg-red-50 dark:bg-red-950/50',     label: 'Cancelamento' },
  reopen:         { icon: RotateCcw,   color: 'text-amber-600',  bg: 'bg-amber-50 dark:bg-amber-950/50', label: 'Reabertura' },
  reversal:       { icon: RefreshCw,   color: 'text-purple-600', bg: 'bg-purple-50 dark:bg-purple-950/50', label: 'Estorno' },
  cascade_update: { icon: GitCommit,   color: 'text-muted-foreground', bg: 'bg-muted/40',               label: 'Atualização em cascata' },
};

// ── Field labels ───────────────────────────────────────────────────────────────
const FIELD_LABELS: Record<string, string> = {
  status:           'Status',
  priority:         'Prioridade',
  title:            'Título',
  description:      'Descrição',
  findings:         'Diagnóstico',
  scheduled_date:   'Data agendada',
  due_date:         'Prazo',
  assigned_technician: 'Técnico',
  client_id:        'Cliente',
  vessel_id:        'Embarcação',
  marina_id:        'Marina',
  type:             'Tipo',
  internal_notes:   'Notas internas',
  total_amount:     'Valor total',
  labor_cost:       'Mão de obra',
  discount:         'Desconto',
  payment_method:   'Forma de pagamento',
  payment_status:   'Status do pagamento',
  supplier_id:      'Fornecedor',
};

const STATUS_LABELS: Record<string, string> = {
  pending:        'Pendente',
  scheduled:      'Agendada',
  in_progress:    'Em andamento',
  waiting_parts:  'Aguardando peças',
  waiting_approval: 'Aguardando aprovação',
  completed:      'Concluída',
  invoiced:       'Faturada',
  paid:           'Paga',
  cancelled:      'Cancelada',
  reopened:       'Reaberta',
};

const PRIORITY_LABELS: Record<string, string> = {
  low:      'Baixa',
  medium:   'Média',
  high:     'Alta',
  urgent:   'Urgente',
};

function translateValue(field: string, value: unknown): string {
  if (value === null || value === undefined || value === '') return '—';
  const str = String(value);
  if (field === 'status') return STATUS_LABELS[str] || str;
  if (field === 'priority') return PRIORITY_LABELS[str] || str;
  // ISO date
  if (/^\d{4}-\d{2}-\d{2}/.test(str)) {
    try {
      return format(new Date(str), 'dd/MM/yyyy HH:mm', { locale: ptBR });
    } catch { return str; }
  }
  return str;
}

function DiffRow({ field, prev, next }: { field: string; prev: unknown; next: unknown }) {
  const label = FIELD_LABELS[field] || field;
  const prevStr = translateValue(field, prev);
  const nextStr = translateValue(field, next);
  if (prevStr === nextStr) return null;
  return (
    <div className="flex flex-wrap items-baseline gap-x-2 gap-y-0.5 text-xs">
      <span className="text-muted-foreground font-medium min-w-[90px]">{label}:</span>
      <span className="line-through text-muted-foreground/60">{prevStr}</span>
      <span className="text-foreground font-medium">{nextStr}</span>
    </div>
  );
}

// ── Main component ─────────────────────────────────────────────────────────────
export function ServiceOrderTimeline({ orderId }: { orderId: string | undefined }) {
  const { data: history, isLoading } = useRecordHistory('service_orders', orderId);

  if (isLoading) {
    return (
      <div className="space-y-4 py-4 px-1">
        {[1, 2, 3].map(i => (
          <div key={i} className="flex gap-3">
            <Skeleton className="h-8 w-8 rounded-full flex-shrink-0" />
            <div className="flex-1 space-y-2">
              <Skeleton className="h-4 w-32" />
              <Skeleton className="h-3 w-48" />
            </div>
          </div>
        ))}
      </div>
    );
  }

  if (!history || history.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-12 text-center">
        <Clock className="h-10 w-10 text-muted-foreground/40 mb-3" />
        <p className="text-sm text-muted-foreground">Nenhuma alteração registrada ainda.</p>
        <p className="text-xs text-muted-foreground/60 mt-1">
          Alterações nesta OS serão registradas aqui automaticamente.
        </p>
      </div>
    );
  }

  return (
    <TooltipProvider>
      <ol className="relative border-l border-border ml-4 space-y-6 py-2">
        {history.map((entry) => {
          const meta = ACTION_META[entry.action] || ACTION_META.update;
          const Icon = meta.icon;
          const changedAt = entry.changed_at ? new Date(entry.changed_at) : null;

          // Compute diff fields
          const prev = entry.previous_value as Record<string, unknown> | null;
          const next = entry.new_value as Record<string, unknown> | null;
          const allFields = new Set([
            ...Object.keys(prev || {}),
            ...Object.keys(next || {}),
          ]);
          // Filter to only known fields that actually changed
          const diffFields = [...allFields].filter((f) => {
            const p = prev?.[f];
            const n = next?.[f];
            return p !== n && (FIELD_LABELS[f] || f === 'status' || f === 'priority');
          });

          return (
            <li key={entry.id} className="ml-5">
              {/* Icon dot */}
              <span className={cn(
                'absolute -left-3.5 flex h-7 w-7 items-center justify-center rounded-full border bg-background',
                meta.bg,
              )}>
                <Icon className={cn('h-3.5 w-3.5', meta.color)} />
              </span>

              {/* Content card */}
              <div className="rounded-lg border bg-card p-3 shadow-sm">
                <div className="flex items-start justify-between gap-2 flex-wrap">
                  <div className="flex items-center gap-2">
                    <Badge
                      variant="outline"
                      className={cn('text-[10px] py-0 h-5 font-semibold border', meta.color)}
                    >
                      {meta.label}
                    </Badge>
                    <span className="text-xs text-muted-foreground">
                      por <span className="font-medium text-foreground">{entry.changed_by}</span>
                    </span>
                  </div>
                  {changedAt && (
                    <Tooltip>
                      <TooltipTrigger asChild>
                        <span className="text-xs text-muted-foreground cursor-default">
                          {formatDistanceToNow(changedAt, { addSuffix: true, locale: ptBR })}
                        </span>
                      </TooltipTrigger>
                      <TooltipContent side="left">
                        <p className="text-xs">{format(changedAt, "dd/MM/yyyy 'às' HH:mm:ss", { locale: ptBR })}</p>
                      </TooltipContent>
                    </Tooltip>
                  )}
                </div>

                {/* Diff rows */}
                {diffFields.length > 0 && (
                  <div className="mt-2 space-y-1 border-t pt-2">
                    {diffFields.map((field) => (
                      <DiffRow
                        key={field}
                        field={field}
                        prev={prev?.[field]}
                        next={next?.[field]}
                      />
                    ))}
                  </div>
                )}

                {/* Reason */}
                {entry.reason && (
                  <div className="mt-2 border-t pt-2">
                    <p className="text-xs text-muted-foreground">
                      <span className="font-medium">Motivo:</span> {entry.reason}
                    </p>
                  </div>
                )}
              </div>
            </li>
          );
        })}
      </ol>
    </TooltipProvider>
  );
}
