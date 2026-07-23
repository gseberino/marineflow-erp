import { ReactNode } from 'react';
import { cn } from '@/lib/utils';
import type { StatusTone } from './StatusChip';

const severityBorder: Record<StatusTone, string> = {
  info: 'border-l-info',
  success: 'border-l-success',
  warning: 'border-l-warning',
  critical: 'border-l-destructive',
  neutral: 'border-l-transparent',
};

interface EntityCardProps {
  /** Identificador destacado (ex.: nº da OS) — cor de link/realce. */
  id?: ReactNode;
  /** Chip(s) de status no canto direito do cabeçalho. */
  badge?: ReactNode;
  title: ReactNode;
  /** Linhas secundárias — no máximo 2: só o que decide a ação. */
  lines?: ReactNode[];
  /** Severidade vira borda esquerda (reforço além da cor do chip). */
  severity?: StatusTone;
  /** Ações com alvo ≥44px — a primária deve ser um Button default. */
  actions?: ReactNode;
  onClick?: () => void;
  className?: string;
}

/**
 * Padrão mobile: abaixo de `md`, listas usam EntityCard no lugar de tabela.
 * Zero scroll horizontal por construção — o conteúdo trunca, nunca estoura.
 */
export function EntityCard({ id, badge, title, lines = [], severity = 'neutral', actions, onClick, className }: EntityCardProps) {
  const clickable = !!onClick;
  return (
    <div
      role={clickable ? 'button' : undefined}
      tabIndex={clickable ? 0 : undefined}
      onClick={onClick}
      onKeyDown={clickable ? (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onClick?.(); } } : undefined}
      className={cn(
        'rounded-lg border border-l-[3px] bg-card p-3.5 shadow-sm',
        severityBorder[severity],
        clickable && 'cursor-pointer transition-colors hover:border-primary/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
        className,
      )}
    >
      <div className="flex items-center justify-between gap-2">
        {id && <span className="min-w-0 truncate text-sm font-bold text-accent">{id}</span>}
        {badge && <span className="flex shrink-0 items-center gap-1">{badge}</span>}
      </div>
      <p className="mt-0.5 truncate font-semibold">{title}</p>
      {lines.map((line, i) => (
        <p key={i} className="truncate text-sm text-muted-foreground">{line}</p>
      ))}
      {actions && (
        <div
          className="mt-3 flex items-center gap-2 [&>*]:min-h-11"
          onClick={(e) => e.stopPropagation()}
        >
          {actions}
        </div>
      )}
    </div>
  );
}
