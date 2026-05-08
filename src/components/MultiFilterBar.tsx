/**
 * MultiFilterBar — componente de filtro multi-select reutilizável.
 *
 * Uso:
 *   const mf = useMultiFilter({ status: [], priority: [], search: '', dateFrom: '', dateTo: '' });
 *
 *   <MultiFilterBar
 *     filters={mf.filters}
 *     activeCount={mf.activeCount}
 *     onToggle={mf.toggle}
 *     onSetField={mf.setField}
 *     onClearAll={mf.clearAll}
 *     groups={[
 *       { type: 'multi', field: 'status', label: 'Status', options: [...] },
 *       { type: 'multi', field: 'priority', label: 'Prioridade', options: [...] },
 *       { type: 'daterange', fromField: 'dateFrom', toField: 'dateTo', label: 'Período' },
 *     ]}
 *   />
 */
import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Filter, X } from 'lucide-react';
import { cn } from '@/lib/utils';

// ─── Types ─────────────────────────────────────────────────────────────────

export type FilterOption = {
  value: string;
  label: string;
  /** Optional Tailwind className for the chip (e.g. colour) */
  chipClass?: string;
};

export type FilterGroupConfig =
  | {
      type: 'multi';
      field: string;
      label: string;
      options: FilterOption[];
    }
  | {
      type: 'daterange';
      fromField: string;
      toField: string;
      label: string;
    };

interface MultiFilterBarProps {
  /** Filter state from useMultiFilter */
  filters: Record<string, string[] | string>;
  activeCount: number;
  /** Called for multi-select toggles */
  onToggle: (field: any, value: string) => void;
  /** Called for direct field sets (dates, etc.) */
  onSetField: (field: any, value: any) => void;
  /** Reset all filters */
  onClearAll: () => void;
  /** Groups to render inside the panel */
  groups: FilterGroupConfig[];
  /** Extra buttons rendered next to the trigger (e.g. Export CSV) */
  extra?: React.ReactNode;
  /** Search input value — pass '' to hide search */
  search?: string;
  onSearchChange?: (v: string) => void;
  searchPlaceholder?: string;
}

// ─── Date presets ───────────────────────────────────────────────────────────

const DATE_PRESETS = [
  { label: 'Hoje', key: 'today' },
  { label: 'Esta semana', key: 'week' },
  { label: 'Este mês', key: 'month' },
  { label: 'Mês passado', key: 'last_month' },
];

function applyDatePreset(key: string): { from: string; to: string } {
  const now = new Date();
  const pad = (n: number) => String(n).padStart(2, '0');
  const iso = (d: Date) =>
    `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;

  if (key === 'today') {
    const s = iso(now);
    return { from: s, to: s };
  }
  if (key === 'week') {
    const from = new Date(now);
    from.setDate(now.getDate() - 6);
    return { from: iso(from), to: iso(now) };
  }
  if (key === 'month') {
    return {
      from: `${now.getFullYear()}-${pad(now.getMonth() + 1)}-01`,
      to: iso(now),
    };
  }
  if (key === 'last_month') {
    const lm = new Date(now.getFullYear(), now.getMonth() - 1, 1);
    const lmEnd = new Date(now.getFullYear(), now.getMonth(), 0);
    return { from: iso(lm), to: iso(lmEnd) };
  }
  return { from: '', to: '' };
}

// ─── Component ──────────────────────────────────────────────────────────────

export function MultiFilterBar({
  filters,
  activeCount,
  onToggle,
  onSetField,
  onClearAll,
  groups,
  extra,
  search,
  onSearchChange,
  searchPlaceholder = 'Buscar…',
}: MultiFilterBarProps) {
  const [open, setOpen] = useState(false);

  return (
    <div className="flex flex-wrap items-center gap-2">
      {/* Search input (optional) */}
      {onSearchChange !== undefined && (
        <div className="relative flex-1 min-w-[180px]">
          <Filter className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground pointer-events-none" />
          <Input
            className="pl-9"
            placeholder={searchPlaceholder}
            value={search ?? ''}
            onChange={e => onSearchChange(e.target.value)}
          />
        </div>
      )}

      {/* Filter trigger */}
      <Popover open={open} onOpenChange={setOpen}>
        <PopoverTrigger asChild>
          <Button
            variant={activeCount > 0 ? 'default' : 'outline'}
            size="sm"
            className="gap-2 relative"
          >
            <Filter className="h-4 w-4" />
            Filtros
            {activeCount > 0 && (
              <Badge
                className="ml-1 h-5 min-w-5 px-1 rounded-full text-[10px] bg-background text-foreground"
              >
                {activeCount}
              </Badge>
            )}
          </Button>
        </PopoverTrigger>

        <PopoverContent
          align="start"
          className="w-[520px] max-w-[95vw] p-4 space-y-4"
          onOpenAutoFocus={e => e.preventDefault()}
        >
          {groups.map((group, gi) => {
            if (group.type === 'multi') {
              const selected = (filters[group.field] as string[]) ?? [];
              const allSelected = selected.length === 0;

              return (
                <div key={gi} className="space-y-1.5">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-semibold text-muted-foreground uppercase tracking-wide">
                      {group.label}
                    </span>
                    {!allSelected && (
                      <button
                        type="button"
                        onClick={() => onSetField(group.field, [])}
                        className="text-[10px] text-muted-foreground hover:text-foreground underline-offset-2 hover:underline"
                      >
                        Limpar
                      </button>
                    )}
                  </div>
                  <div className="flex flex-wrap gap-1.5">
                    {/* "Todos" chip */}
                    <button
                      type="button"
                      onClick={() => onSetField(group.field, [])}
                      className={cn(
                        'px-2.5 py-0.5 rounded-full text-xs border transition-colors',
                        allSelected
                          ? 'bg-primary text-primary-foreground border-primary'
                          : 'bg-background text-muted-foreground border-border hover:border-primary/50',
                      )}
                    >
                      Todos
                    </button>

                    {group.options.map(opt => {
                      const active = selected.includes(opt.value);
                      return (
                        <button
                          key={opt.value}
                          type="button"
                          onClick={() => onToggle(group.field, opt.value)}
                          className={cn(
                            'px-2.5 py-0.5 rounded-full text-xs border transition-colors',
                            active
                              ? cn('bg-primary/10 text-primary border-primary/50 font-medium', opt.chipClass)
                              : 'bg-background text-muted-foreground border-border hover:border-primary/50',
                          )}
                        >
                          {opt.label}
                        </button>
                      );
                    })}
                  </div>
                </div>
              );
            }

            if (group.type === 'daterange') {
              const from = (filters[group.fromField] as string) ?? '';
              const to = (filters[group.toField] as string) ?? '';
              const hasDate = from || to;

              return (
                <div key={gi} className="space-y-1.5">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-semibold text-muted-foreground uppercase tracking-wide">
                      {group.label}
                    </span>
                    {hasDate && (
                      <button
                        type="button"
                        onClick={() => {
                          onSetField(group.fromField, '');
                          onSetField(group.toField, '');
                        }}
                        className="text-[10px] text-muted-foreground hover:text-foreground underline-offset-2 hover:underline"
                      >
                        Limpar
                      </button>
                    )}
                  </div>

                  {/* Quick presets */}
                  <div className="flex flex-wrap gap-1.5">
                    {DATE_PRESETS.map(preset => {
                      const { from: pFrom, to: pTo } = applyDatePreset(preset.key);
                      const active = from === pFrom && to === pTo;
                      return (
                        <button
                          key={preset.key}
                          type="button"
                          onClick={() => {
                            if (active) {
                              onSetField(group.fromField, '');
                              onSetField(group.toField, '');
                            } else {
                              onSetField(group.fromField, pFrom);
                              onSetField(group.toField, pTo);
                            }
                          }}
                          className={cn(
                            'px-2.5 py-0.5 rounded-full text-xs border transition-colors',
                            active
                              ? 'bg-primary/10 text-primary border-primary/50 font-medium'
                              : 'bg-background text-muted-foreground border-border hover:border-primary/50',
                          )}
                        >
                          {preset.label}
                        </button>
                      );
                    })}
                  </div>

                  {/* Manual range */}
                  <div className="flex items-center gap-2">
                    <Input
                      type="date"
                      className="h-8 text-xs"
                      value={from}
                      max={to || undefined}
                      onChange={e => onSetField(group.fromField, e.target.value)}
                    />
                    <span className="text-muted-foreground text-xs shrink-0">até</span>
                    <Input
                      type="date"
                      className="h-8 text-xs"
                      value={to}
                      min={from || undefined}
                      onChange={e => onSetField(group.toField, e.target.value)}
                    />
                  </div>
                </div>
              );
            }

            return null;
          })}

          {/* Footer actions */}
          {activeCount > 0 && (
            <div className="pt-2 border-t flex justify-end">
              <Button
                variant="ghost"
                size="sm"
                className="gap-1 text-muted-foreground"
                onClick={() => { onClearAll(); setOpen(false); }}
              >
                <X className="h-3.5 w-3.5" />
                Limpar todos os filtros
              </Button>
            </div>
          )}
        </PopoverContent>
      </Popover>

      {/* Active filter chips (quick-remove) */}
      {activeCount > 0 && (
        <button
          type="button"
          onClick={onClearAll}
          className="flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground transition-colors"
        >
          <X className="h-3 w-3" />
          Limpar
        </button>
      )}

      {/* Extra buttons (e.g. Export CSV) */}
      {extra}
    </div>
  );
}
