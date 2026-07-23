import { ReactNode } from 'react';
import { cn } from '@/lib/utils';

export type StatusTone = 'info' | 'success' | 'warning' | 'critical' | 'neutral';

const toneClasses: Record<StatusTone, string> = {
  info: 'bg-info/10 text-info',
  success: 'bg-success/10 text-success',
  warning: 'bg-warning/10 text-warning',
  critical: 'bg-destructive/10 text-destructive',
  neutral: 'bg-muted text-muted-foreground',
};

/** Mapa único de status de OS → tom semântico (substitui os className soltos de statusConfig). */
export const serviceOrderStatusTone: Record<string, StatusTone> = {
  draft: 'neutral',
  scheduled: 'info',
  open: 'info',
  in_progress: 'info',
  awaiting_parts: 'warning',
  awaiting_client: 'warning',
  completed: 'success',
  invoiced: 'success',
  cancelled: 'critical',
};

export const priorityTone: Record<string, StatusTone> = {
  low: 'neutral',
  normal: 'neutral',
  high: 'warning',
  urgent: 'critical',
};

interface StatusChipProps {
  tone?: StatusTone;
  /** Ponto colorido à esquerda — reforço além da cor (estado nunca é só cor). */
  dot?: boolean;
  className?: string;
  children: ReactNode;
}

export function StatusChip({ tone = 'neutral', dot = false, className, children }: StatusChipProps) {
  return (
    <span
      className={cn(
        'inline-flex items-center gap-1.5 whitespace-nowrap rounded-full px-2.5 py-0.5 text-xs font-semibold',
        toneClasses[tone],
        className,
      )}
    >
      {dot && <span aria-hidden className="h-1.5 w-1.5 shrink-0 rounded-full bg-current" />}
      {children}
    </span>
  );
}
