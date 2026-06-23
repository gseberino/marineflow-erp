import { useState } from 'react';
import { Bookmark, BookmarkPlus, Check, Trash2, ChevronDown, Star, Calendar } from 'lucide-react';
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
  type SavedFilterType,
} from '@/hooks/use-saved-filters';
import { toast } from 'sonner';
import { cn } from '@/lib/utils';

// ─── Contextual date presets ─────────────────────────────────────────────────

const pad = (n: number) => String(n).padStart(2, '0');
const iso = (d: Date) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;

function buildContextualPresets(fromField: string, toField: string) {
  const now = new Date();
  const y = now.getFullYear();
  const m = now.getMonth();

  const thisMonthStart = new Date(y, m, 1);
  const lastMonthStart = new Date(y, m - 1, 1);
  const lastMonthEnd = new Date(y, m, 0);
  const twoWeeksAgo = new Date(now); twoWeeksAgo.setDate(now.getDate() - 13);
  const yearStart = new Date(y, 0, 1);

  return [
    {
      label: 'Este mês',
      config: { [fromField]: iso(thisMonthStart), [toField]: iso(now) },
    },
    {
      label: 'Mês passado',
      config: { [fromField]: iso(lastMonthStart), [toField]: iso(lastMonthEnd) },
    },
    {
      label: 'Últimas 2 semanas',
      config: { [fromField]: iso(twoWeeksAgo), [toField]: iso(now) },
    },
    {
      label: 'Este ano',
      config: { [fromField]: iso(yearStart), [toField]: iso(now) },
    },
  ];
}

// ─── Component ───────────────────────────────────────────────────────────────

interface Props<T> {
  filterType: SavedFilterType;
  currentConfig: T;
  onApply: (config: Partial<T>) => void;
  hasActiveFilters?: boolean;
  /** When provided, shows contextual date presets (Este mês, Mês passado, etc.) */
  dateFields?: { from: string; to: string };
}

export function FilterPresets<T>({
  filterType,
  currentConfig,
  onApply,
  hasActiveFilters = true,
  dateFields,
}: Props<T>) {
  const { data: presets = [] } = useSavedFilters(filterType);
  const createPreset = useCreateSavedFilter();
  const deletePreset = useDeleteSavedFilter();
  const setDefault = useSetDefaultFilter();
  const [saveOpen, setSaveOpen] = useState(false);
  const [name, setName] = useState('');

  const defaultPreset = (presets as any[]).find(p => p.is_default);
  const contextualPresets = dateFields
    ? buildContextualPresets(dateFields.from, dateFields.to)
    : [];

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

  const handleDelete = async (id: string, n: string, isDefault: boolean) => {
    if (!confirm(`Excluir preset "${n}"?`)) return;
    try {
      await deletePreset.mutateAsync({ id, filterType, isDefault });
      toast.success('Preset removido');
    } catch (e: any) {
      toast.error(e?.message || 'Erro ao excluir');
    }
  };

  const handleToggleDefault = async (p: any) => {
    const makeDefault = !p.is_default;
    try {
      await setDefault.mutateAsync({
        id: p.id,
        filterType,
        config: p.filter_config,
        makeDefault,
      });
      toast.success(makeDefault ? `"${p.name}" definido como padrão` : 'Padrão removido');
    } catch (e: any) {
      toast.error(e?.message || 'Erro ao atualizar padrão');
    }
  };

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="outline" size="sm" className="gap-1">
            {defaultPreset ? (
              <Star className="h-3.5 w-3.5 fill-amber-400 text-amber-400" />
            ) : (
              <Bookmark className="h-3.5 w-3.5" />
            )}
            <span className="hidden sm:inline">Presets</span>
            {presets.length > 0 && (
              <span className="ml-0.5 text-xs text-muted-foreground">({presets.length})</span>
            )}
            <ChevronDown className="h-3 w-3 opacity-60" />
          </Button>
        </DropdownMenuTrigger>

        <DropdownMenuContent align="end" className="w-64">

          {/* Contextual date presets */}
          {contextualPresets.length > 0 && (
            <>
              <DropdownMenuLabel className="flex items-center gap-1.5 text-xs">
                <Calendar className="h-3 w-3" />
                Períodos sugeridos
              </DropdownMenuLabel>
              {contextualPresets.map(cp => (
                <DropdownMenuItem
                  key={cp.label}
                  onSelect={(e) => {
                    e.preventDefault();
                    onApply(cp.config as Partial<T>);
                  }}
                  className="text-xs text-muted-foreground hover:text-foreground"
                >
                  <span className="ml-5">{cp.label}</span>
                </DropdownMenuItem>
              ))}
              <DropdownMenuSeparator />
            </>
          )}

          {/* Saved presets */}
          <DropdownMenuLabel className="text-xs">Filtros salvos</DropdownMenuLabel>
          {presets.length === 0 ? (
            <div className="px-2 py-3 text-xs text-muted-foreground">
              Nenhum preset ainda. Configure os filtros e clique em "Salvar atual".
            </div>
          ) : (
            (presets as any[]).map((p) => (
              <DropdownMenuItem
                key={p.id}
                className="flex items-center justify-between gap-2 group pr-1"
                onSelect={(e) => {
                  e.preventDefault();
                  onApply(p.filter_config as Partial<T>);
                  toast.success(`Preset "${p.name}" aplicado`);
                }}
              >
                <div className="flex items-center gap-2 min-w-0">
                  <Check className="h-3 w-3 text-accent shrink-0" />
                  <span className="truncate">{p.name}</span>
                  {p.is_default && (
                    <span className="text-[10px] text-amber-500 font-medium shrink-0">padrão</span>
                  )}
                </div>
                <div className="flex items-center gap-0.5 shrink-0">
                  {/* Star: set/unset default */}
                  <button
                    type="button"
                    onClick={(e) => {
                      e.stopPropagation();
                      handleToggleDefault(p);
                    }}
                    className={cn(
                      'p-1 rounded transition-colors',
                      p.is_default
                        ? 'text-amber-400'
                        : 'opacity-0 group-hover:opacity-100 text-muted-foreground hover:text-amber-400',
                    )}
                    aria-label={p.is_default ? 'Remover padrão' : 'Definir como padrão'}
                    title={p.is_default ? 'Remover padrão' : 'Definir como padrão'}
                  >
                    <Star className={cn('h-3 w-3', p.is_default && 'fill-amber-400')} />
                  </button>
                  {/* Delete */}
                  <button
                    type="button"
                    onClick={(e) => {
                      e.stopPropagation();
                      handleDelete(p.id, p.name, p.is_default);
                    }}
                    className="p-1 rounded opacity-0 group-hover:opacity-100 text-muted-foreground hover:text-destructive transition-colors"
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
              Os filtros atuais serão salvos com este nome. Clique em ⭐ para aplicá-lo automaticamente ao abrir a página.
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
