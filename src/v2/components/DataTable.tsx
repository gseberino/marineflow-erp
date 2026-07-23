import { ReactNode, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { ChevronDown, ChevronRight } from 'lucide-react';
import { cn } from '@/lib/utils';

export type Density = 'compact' | 'regular' | 'relaxed';

export interface DataColumn<T> {
  key: string;
  header: ReactNode;
  /** Largura mínima usada pelo orçamento de colunas (px). */
  minWidth: number;
  /**
   * Importância: 0 = identidade (nunca escondida); números maiores saem
   * primeiro quando não cabem. O que sai vai para a linha expansível.
   */
  priority: number;
  align?: 'left' | 'right';
  render: (row: T) => ReactNode;
  /** Rótulo usado quando a coluna aparece na linha expansível. */
  detailLabel?: string;
}

interface DataTableProps<T> {
  rows: T[];
  rowKey: (row: T) => string;
  columns: DataColumn<T>[];
  density?: Density;
  selectable?: boolean;
  /** Até 2 ações rápidas visíveis por linha (nível 1). O resto vai no menu. */
  rowActions?: (row: T) => ReactNode;
  onRowClick?: (row: T) => void;
  /** Barra de ações em massa — só aparece com seleção ativa. */
  bulkBar?: (selectedKeys: string[], clear: () => void) => ReactNode;
  emptyMessage?: string;
  isLoading?: boolean;
  className?: string;
}

const densityCell: Record<Density, string> = {
  compact: 'py-1.5',
  regular: 'py-2.5',
  relaxed: 'py-3.5',
};

const CHECKBOX_W = 40;
/* 3 botões de 32px + 2 gaps de 4px + padding horizontal 16px = 120px; folga de 8px. */
const ACTIONS_W = 128;
const EXPANDER_W = 24;

/**
 * Tabela universal do MarineFlow v2.
 *
 * Princípio 0 — zero scroll horizontal, por construção:
 * um ResizeObserver mede a largura real do contêiner e a tabela exibe apenas
 * as colunas que cabem (ordenadas por `priority`); as demais ficam na linha
 * expansível "▾", a um clique. O wrapper usa overflow-hidden — se a conta
 * falhar, o conteúdo trunca; nunca aparece barra de rolagem lateral.
 */
export function DataTable<T>({
  rows,
  rowKey,
  columns,
  density = 'regular',
  selectable = false,
  rowActions,
  onRowClick,
  bulkBar,
  emptyMessage = 'Nenhum registro encontrado.',
  isLoading = false,
  className,
}: DataTableProps<T>) {
  const wrapRef = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState<number | null>(null);
  const [expanded, setExpanded] = useState<string | null>(null);
  const [selected, setSelected] = useState<Set<string>>(new Set());

  useLayoutEffect(() => {
    const el = wrapRef.current;
    if (!el) return;
    const ro = new ResizeObserver((entries) => {
      const w = entries[0]?.contentRect.width;
      if (w) setWidth(w);
    });
    ro.observe(el);
    setWidth(el.clientWidth);
    return () => ro.disconnect();
  }, []);

  const { visible, hidden } = useMemo(() => {
    const sorted = [...columns].sort((a, b) => a.priority - b.priority);
    if (width === null) {
      // Antes da primeira medição: só as colunas de identidade, sem risco de estouro.
      const vis = sorted.filter((c) => c.priority <= 0);
      return { visible: vis, hidden: sorted.filter((c) => c.priority > 0) };
    }
    let budget = width - EXPANDER_W - (selectable ? CHECKBOX_W : 0) - (rowActions ? ACTIONS_W : 0);
    const vis: DataColumn<T>[] = [];
    const hid: DataColumn<T>[] = [];
    for (const col of sorted) {
      if (col.priority <= 0 || col.minWidth <= budget) {
        vis.push(col);
        budget -= col.minWidth;
      } else {
        hid.push(col);
      }
    }
    // Preserva a ordem declarada nas visíveis (não a ordem de prioridade).
    const declared = columns.filter((c) => vis.includes(c));
    return { visible: declared, hidden: hid };
  }, [columns, width, selectable, rowActions]);

  const keys = rows.map(rowKey);
  const allSelected = keys.length > 0 && keys.every((k) => selected.has(k));
  const someSelected = keys.some((k) => selected.has(k));

  const toggleAll = () =>
    setSelected((prev) => {
      if (allSelected) return new Set([...prev].filter((k) => !keys.includes(k)));
      return new Set([...prev, ...keys]);
    });

  const toggleOne = (key: string) =>
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });

  const clearSelection = () => setSelected(new Set());
  const selectedKeys = [...selected].filter((k) => keys.includes(k));

  return (
    <div ref={wrapRef} className={cn('overflow-hidden rounded-lg border bg-card', className)}>
      <table className="w-full table-fixed text-sm">
        <colgroup>
          {selectable && <col style={{ width: CHECKBOX_W }} />}
          <col style={{ width: EXPANDER_W + (visible[0]?.minWidth ?? 120) }} />
          {visible.slice(1).map((c) => (
            <col key={c.key} style={{ width: c.minWidth }} />
          ))}
          {rowActions && <col style={{ width: ACTIONS_W }} />}
        </colgroup>
        <thead>
          <tr className="border-b bg-muted/60">
            {selectable && (
              <th className="px-3">
                <input
                  type="checkbox"
                  aria-label="Selecionar todos"
                  className="h-4 w-4 cursor-pointer accent-primary"
                  checked={allSelected}
                  ref={(el) => { if (el) el.indeterminate = someSelected && !allSelected; }}
                  onChange={toggleAll}
                />
              </th>
            )}
            {visible.map((c) => (
              <th
                key={c.key}
                className={cn(
                  'truncate px-3 py-2.5 text-xs font-semibold uppercase tracking-wide text-muted-foreground',
                  c.align === 'right' ? 'text-right' : 'text-left',
                )}
              >
                {c.header}
              </th>
            ))}
            {rowActions && <th aria-label="Ações" />}
          </tr>
        </thead>
        <tbody>
          {isLoading ? (
            <tr>
              <td colSpan={visible.length + (selectable ? 1 : 0) + (rowActions ? 1 : 0)} className="px-3 py-10 text-center text-muted-foreground">
                Carregando…
              </td>
            </tr>
          ) : rows.length === 0 ? (
            <tr>
              <td colSpan={visible.length + (selectable ? 1 : 0) + (rowActions ? 1 : 0)} className="px-3 py-10 text-center text-muted-foreground">
                {emptyMessage}
              </td>
            </tr>
          ) : (
            rows.map((row) => {
              const key = rowKey(row);
              const isExpanded = expanded === key;
              return (
                <RowGroup
                  key={key}
                  row={row}
                  rowKeyValue={key}
                  visible={visible}
                  hidden={hidden}
                  density={density}
                  selectable={selectable}
                  isSelected={selected.has(key)}
                  onToggleSelect={() => toggleOne(key)}
                  isExpanded={isExpanded}
                  onToggleExpand={() => setExpanded(isExpanded ? null : key)}
                  rowActions={rowActions}
                  onRowClick={onRowClick}
                />
              );
            })
          )}
        </tbody>
      </table>
      {bulkBar && selectedKeys.length > 0 && (
        <div className="flex items-center gap-3 border-t bg-foreground px-4 py-2 text-sm text-background">
          {bulkBar(selectedKeys, clearSelection)}
        </div>
      )}
    </div>
  );
}

interface RowGroupProps<T> {
  row: T;
  rowKeyValue: string;
  visible: DataColumn<T>[];
  hidden: DataColumn<T>[];
  density: Density;
  selectable: boolean;
  isSelected: boolean;
  onToggleSelect: () => void;
  isExpanded: boolean;
  onToggleExpand: () => void;
  rowActions?: (row: T) => ReactNode;
  onRowClick?: (row: T) => void;
}

function RowGroup<T>({
  row, rowKeyValue, visible, hidden, density, selectable,
  isSelected, onToggleSelect, isExpanded, onToggleExpand, rowActions, onRowClick,
}: RowGroupProps<T>) {
  const pad = densityCell[density];
  const colSpan = visible.length + (selectable ? 1 : 0) + (rowActions ? 1 : 0);
  const hasDetails = hidden.length > 0;
  const Chevron = isExpanded ? ChevronDown : ChevronRight;

  return (
    <>
      <tr
        className={cn(
          'group border-b transition-colors last:border-0',
          isExpanded ? 'bg-primary/5' : 'hover:bg-muted/40',
          onRowClick && 'cursor-pointer',
        )}
        onClick={onRowClick ? () => onRowClick(row) : undefined}
      >
        {selectable && (
          <td className="px-3" onClick={(e) => e.stopPropagation()}>
            <input
              type="checkbox"
              aria-label={`Selecionar ${rowKeyValue}`}
              className="h-4 w-4 cursor-pointer accent-primary"
              checked={isSelected}
              onChange={onToggleSelect}
            />
          </td>
        )}
        {visible.map((c, i) => (
          <td
            key={c.key}
            className={cn('truncate px-3', pad, c.align === 'right' && 'text-right tabular-nums')}
          >
            {i === 0 && hasDetails ? (
              <span className="flex items-center gap-1">
                <button
                  type="button"
                  aria-label={isExpanded ? 'Recolher detalhes' : 'Ver detalhes'}
                  aria-expanded={isExpanded}
                  className="-ml-1 shrink-0 rounded p-0.5 text-muted-foreground hover:bg-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                  onClick={(e) => { e.stopPropagation(); onToggleExpand(); }}
                >
                  <Chevron className="h-3.5 w-3.5" />
                </button>
                <span className="min-w-0 truncate">{c.render(row)}</span>
              </span>
            ) : (
              c.render(row)
            )}
          </td>
        ))}
        {rowActions && (
          <td className={cn('px-2 text-right', pad)} onClick={(e) => e.stopPropagation()}>
            <span className="inline-flex items-center gap-1 opacity-70 transition-opacity group-hover:opacity-100">
              {rowActions(row)}
            </span>
          </td>
        )}
      </tr>
      {isExpanded && hasDetails && (
        <tr className="border-b bg-primary/5 last:border-0">
          <td colSpan={colSpan} className="px-3 pb-2.5 pt-0">
            <dl className="flex flex-wrap gap-x-6 gap-y-1 pl-6 text-xs text-muted-foreground">
              {hidden.map((c) => (
                <div key={c.key} className="flex items-baseline gap-1.5">
                  <dt className="font-semibold uppercase tracking-wide">{c.detailLabel ?? c.key}:</dt>
                  <dd className="text-foreground">{c.render(row)}</dd>
                </div>
              ))}
            </dl>
          </td>
        </tr>
      )}
    </>
  );
}
