import { useState, useEffect, useRef } from 'react';
import { Bookmark, BookmarkPlus, Trash2, ChevronDown, Star, Calendar } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import {
  useSavedFilters,
  useCreateSavedFilter,
  useDeleteSavedFilter,
  useSetDefaultFilter,
  type SavedFilter,
  type SavedFilterType,
} from '@/hooks/use-saved-filters';
import { toast } from 'sonner';
import { cn } from '@/lib/utils';

// ─── Contextual date presets ────────────────────────────────────────────────

type DateRange = { dateFrom: string; dateTo: string };

function buildDatePresets(): Array<{ label: string; config: DateRange }> {
  const pad = (n: number) => String(n).padStart(2, '0');
  const iso = (d: Date) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  const now = new Date();

  const thisMonthStart = new Date(now.getFullYear(), now.getMonth(), 1);
  const thisMonthEnd = new Date(now.getFullYear(), now.getMonth() + 1, 0);

  const lastMonthStart = new Date(now.getFullYear(), now.getMonth() - 1, 1);
  const lastMonthEnd = new Date(now.getFullYear(), now.getMonth(), 0);

  const thisWeekStart = new Date(now);
  thisWeekStart.setDate(now.getDate() - now.getDay() + (now.getDay() === 0 ? -6 : 1));
  const thisWeekEnd = new Date(thisWeekStart);
  thisWeekEnd.setDate(thisWeekStart.getDate() + 6);

  return [
    { label: 'Esta semana', config: { dateFrom: iso(thisWeekStart), dateTo: iso(thisWeekEnd) } },
    { label: 'Este mês', config: { dateFrom: iso(thisMonthStart), dateTo: iso(thisMonthEnd) } },
    { label: 'Mês anterior', config: { dateFrom: iso(lastMonthStart), dateTo: iso(lastMonthEnd) } },
  ];
}

function hasDateFields(config: Record<string, any>): boolean {
  return 'dateFrom' in config || 'dateTo' in config;
}

// ─── Props ───────────────────────────────────────────────────────────────────

interface Props<T extends Record<string, any>> {
  filterType: SavedFilterType;
  currentConfig: T;
  onApply: (config: T) => void;
  hasActiveFilters?: boolean;
  /** When true (default), auto-applies the saved default preset on first load
   *  if no other filters are already active. Pass false to suppress (e.g. when
   *  URL params are driving the initial state). */
  autoApplyDefault?: boolean;
}

// ─── Component ───────────────────────────────────────────────────────────────

export function FilterPresets<T extends Record<string, any>>({
  filterType,
  currentConfig,
  onApply,
  hasActiveFilters = false,
  autoApplyDefault = true,
}: Props<T>) {
  const { data: presets = [] } = useSavedFilters(filterType);
  const createPreset = useCreateSavedFilter();
  const deletePreset = useDeleteSavedFilter();
  const setDefault = useSetDefaultFilter();
  const [saveOpen, setSaveOpen] = useState(false);
  const [name, setName] = useState('');

  // Always-fresh ref so the effect closure is never stale
  const onApplyRef = useRef(onApply);
  onApplyRef.current = onApply;

  const appliedDefaultRef = useRef(false);
  // Track the last filterType so we can reset the flag when it changes.
  // This happens when the user switches tabs in ServiceOrderList
  // (filterType goes from 'service_orders' → 'quotes').
  const lastFilterTypeRef = useRef(filterType);

  // ── Unified auto-apply: localStorage (instant) → Supabase (fallback) ─────
  useEffect(() => {
    // Reset flag when filterType changes (e.g. tab switch) so the new
    // filter type gets a fresh chance to apply its own default.
    if (lastFilterTypeRef.current !== filterType) {
      lastFilterTypeRef.current = filterType;
      appliedDefaultRef.current = false;
    }

    if (appliedDefaultRef.current || !autoApplyDefault || hasActiveFilters) return;

    // Fast path: localStorage — populated when user sets a default
    const lsKey = `mf-default-${filterType}`;
    const cached = localStorage.getItem(lsKey);
    if (cached) {
      try {
        onApplyRef.current(JSON.parse(cached) as T);
        appliedDefaultRef.current = true;
        return;
      } catch {
        localStorage.removeItem(lsKey);
      }
    }

    // Slow path: wait for Supabase data
    if (presets.length === 0) return;
    const defaultPreset = presets.find((p: SavedFilter) => p.is_default);
    if (defaultPreset) {
      onApplyRef.current(defaultPreset.filter_config as T);
      appliedDefaultRef.current = true;
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [presets, hasActiveFilters, filterType, autoApplyDefault]);

  const handleSave = async () => {
    if (!name.trim()) {
      toast.error('Dê um nome para o preset');
      return;
    }
    try {
      await createPreset.mutateAsync({
        name: name.trim(),
        filter_type: filterType,
        filter_config: currentConfig as any,
      });
      toast.success('Preset salvo');
      setName('');
      setSaveOpen(false);
    } catch (e: any) {
      toast.error(e?.message || 'Erro ao salvar preset');
    }
  };

  const handleDelete = async (id: string, n: string) => {
    if (!confirm(`Excluir preset "${n}"?`)) return;
    try {
      await deletePreset.mutateAsync(id);
      toast.success('Preset removido');
    } catch (e: any) {
      toast.error(e?.message || 'Erro ao excluir');
    }
  };

  const handleToggleDefault = async (preset: SavedFilter, e: React.MouseEvent) => {
    e.stopPropagation();
    const makingDefault = !preset.is_default;
    try {
      await setDefault.mutateAsync({
        id: preset.id,
        filterType,
        filterConfig: preset.filter_config,
        isDefault: makingDefault,
      });
      toast.success(makingDefault ? `"${preset.name}" definido como padrão` : 'Padrão removido');
    } catch (e: any) {
      toast.error(e?.message || 'Erro ao definir padrão');
    }
  };

  const defaultPreset = presets.find((p: SavedFilter) => p.is_default);
  const datePresets = hasDateFields(currentConfig) ? buildDatePresets() : [];
  const totalCount = presets.length;

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button
            variant="outline"
            size="sm"
            className={cn('gap-1', defaultPreset && 'border-amber-400/60 text-amber-600 dark:text-amber-400')}
          >
            <Bookmark className="h-3.5 w-3.5" />
            <span className="hidden sm:inline">Presets</span>
            {totalCount > 0 && (
              <span className="ml-0.5 text-xs text-muted-foreground">({totalCount})</span>
            )}
            {defaultPreset && (
              <Star className="h-3 w-3 fill-amber-400 text-amber-400 ml-0.5" />
            )}
            <ChevronDown className="h-3 w-3 opacity-60" />
          </Button>
        </DropdownMenuTrigger>

        <DropdownMenuContent align="end" className="w-72">

          {/* ── Contextual date presets ── */}
          {datePresets.length > 0 && (
            <>
              <DropdownMenuLabel className="text-xs flex items-center gap-1.5">
                <Calendar className="h-3 w-3" /> Sugestões de período
              </DropdownMenuLabel>
              {datePresets.map(dp => (
                <DropdownMenuItem
                  key={dp.label}
                  className="text-xs"
                  onSelect={() => {
                    onApply({ ...currentConfig, ...dp.config } as T);
                    toast.success(`Período: ${dp.label}`);
                  }}
                >
                  {dp.label}
                </DropdownMenuItem>
              ))}
              <DropdownMenuSeparator />
            </>
          )}

          {/* ── Saved presets ── */}
          <DropdownMenuLabel className="text-xs">Filtros salvos</DropdownMenuLabel>

          {presets.length === 0 ? (
            <div className="px-2 py-3 text-xs text-muted-foreground">
              Nenhum preset ainda. Configure os filtros e clique em "Salvar atual".
            </div>
          ) : (
            presets.map((p: SavedFilter) => (
              <DropdownMenuItem
                key={p.id}
                className="flex items-center justify-between gap-2 group pr-1"
                onSelect={(e) => {
                  e.preventDefault();
                  onApply(p.filter_config as T);
                  toast.success(`Preset "${p.name}" aplicado`);
                }}
              >
                <div className="flex items-center gap-2 min-w-0 flex-1">
                  <span className="truncate">{p.name}</span>
                  {p.is_default && (
                    <span className="shrink-0 text-[10px] font-medium text-amber-600 dark:text-amber-400 bg-amber-50 dark:bg-amber-900/30 px-1.5 py-0.5 rounded-full">
                      padrão
                    </span>
                  )}
                </div>

                <div className="flex items-center gap-0.5 shrink-0">
                  {/* ⭐ Toggle default */}
                  <button
                    type="button"
                    onClick={(e) => handleToggleDefault(p, e)}
                    disabled={setDefault.isPending}
                    title={p.is_default ? 'Remover como padrão' : 'Definir como padrão'}
                    className={cn(
                      'p-1 rounded transition-colors',
                      p.is_default
                        ? 'text-amber-400 hover:text-amber-500'
                        : 'opacity-0 group-hover:opacity-100 text-muted-foreground hover:text-amber-400',
                    )}
                  >
                    <Star
                      className={cn('h-3.5 w-3.5', p.is_default && 'fill-amber-400')}
                    />
                  </button>

                  {/* 🗑 Delete */}
                  <button
                    type="button"
                    onClick={(e) => {
                      e.stopPropagation();
                      handleDelete(p.id, p.name);
                    }}
                    className="opacity-0 group-hover:opacity-100 p-1 rounded text-muted-foreground hover:text-destructive transition-colors"
                    aria-label="Excluir preset"
                  >
                    <Trash2 className="h-3 w-3" />
                  </button>
                </div>
              </DropdownMenuItem>
            ))
          )}

          <DropdownMenuSeparator />
          <DropdownMenuItem
            onSelect={(e) => {
              e.preventDefault();
              if (!hasActiveFilters) {
                toast.info('Configure ao menos um filtro antes de salvar');
                return;
              }
              setSaveOpen(true);
            }}
          >
            <BookmarkPlus className="h-3.5 w-3.5 mr-2" />
            Salvar atual…
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>

      <Dialog open={saveOpen} onOpenChange={setSaveOpen}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>Salvar preset de filtros</DialogTitle>
          </DialogHeader>
          <div className="space-y-2">
            <label className="text-sm font-medium">Nome</label>
            <Input
              autoFocus
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Ex.: Urgentes deste mês"
              onKeyDown={(e) => {
                if (e.key === 'Enter') handleSave();
              }}
            />
            <p className="text-xs text-muted-foreground">
              Os filtros atuais serão salvos com este nome para aplicação rápida.
            </p>
          </div>
          <DialogFooter>
            <Button variant="ghost" onClick={() => setSaveOpen(false)}>
              Cancelar
            </Button>
            <Button onClick={handleSave} disabled={createPreset.isPending}>
              Salvar
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
