import { ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { cn } from '@/lib/utils';

export interface Crumb {
  label: string;
  to?: string;
}

interface PageShellProps {
  /** Trilha: o último item é a página atual (sem link). */
  breadcrumb?: Crumb[];
  title: string;
  /** Contagem ao lado do título (ex.: total de registros). */
  count?: number;
  description?: string;
  /** Ações da página — a primária deve ser um Button default (gold). */
  actions?: ReactNode;
  children: ReactNode;
  className?: string;
}

export function PageShell({ breadcrumb, title, count, description, actions, children, className }: PageShellProps) {
  return (
    <div className={cn('space-y-4', className)}>
      <header className="space-y-1">
        {breadcrumb && breadcrumb.length > 0 && (
          <nav aria-label="Trilha de navegação" className="text-xs text-muted-foreground">
            {breadcrumb.map((c, i) => {
              const last = i === breadcrumb.length - 1;
              return (
                <span key={`${c.label}-${i}`}>
                  {c.to && !last ? (
                    <Link to={c.to} className="hover:text-foreground hover:underline">{c.label}</Link>
                  ) : (
                    <span className={last ? 'font-semibold text-foreground' : undefined}>{c.label}</span>
                  )}
                  {!last && <span aria-hidden className="mx-1.5">/</span>}
                </span>
              );
            })}
          </nav>
        )}
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h1 className="text-2xl font-bold tracking-tight">
            {title}
            {typeof count === 'number' && (
              <span className="ml-2 align-middle text-sm font-semibold text-muted-foreground tabular-nums">{count}</span>
            )}
          </h1>
          {actions && <div className="flex items-center gap-2">{actions}</div>}
        </div>
        {description && <p className="text-sm text-muted-foreground">{description}</p>}
      </header>
      {children}
    </div>
  );
}
