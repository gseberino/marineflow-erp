import { ReactNode } from 'react';
import { cn } from '@/lib/utils';
import type { StatusTone } from './StatusChip';

const hintTone: Record<StatusTone, string> = {
  info: 'text-info',
  success: 'text-success',
  warning: 'text-warning',
  critical: 'text-destructive',
  neutral: 'text-muted-foreground',
};

interface KPIStatProps {
  label: string;
  value: string;
  /** Linha auxiliar (delta, detalhe). Tom semântico opcional. */
  hint?: ReactNode;
  tone?: StatusTone;
  icon?: ReactNode;
  onClick?: () => void;
  className?: string;
}

/**
 * Substitui KPIBox (Dashboard) e KPICard (components) — um único componente.
 * Clicável quando `onClick` existe (leva à lista já filtrada).
 */
export function KPIStat({ label, value, hint, tone = 'neutral', icon, onClick, className }: KPIStatProps) {
  const Wrapper: 'button' | 'div' = onClick ? 'button' : 'div';
  return (
    <Wrapper
      onClick={onClick}
      className={cn(
        'rounded-lg border bg-card p-4 text-left transition-colors',
        onClick && 'cursor-pointer hover:border-primary/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
        className,
      )}
    >
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0 space-y-1">
          <p className="truncate text-xs font-medium text-muted-foreground">{label}</p>
          <p className="text-xl font-bold tracking-tight tabular-nums">{value}</p>
          {hint && <div className={cn('text-xs font-medium', hintTone[tone])}>{hint}</div>}
        </div>
        {icon && <div className="rounded-md bg-primary/10 p-2 text-primary">{icon}</div>}
      </div>
    </Wrapper>
  );
}
