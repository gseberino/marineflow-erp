import { useState } from 'react';
import { Bookmark, BookmarkPlus, Check, Trash2, ChevronDown } from 'lucide-react';
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
  type SavedFilterType,
} from '@/hooks/use-saved-filters';
import { toast } from 'sonner';

interface Props<T> {
  filterType: SavedFilterType;
  /** Current filter state to be saved */
  currentConfig: T;
  /** Apply a saved preset to the current page state */
  onApply: (config: T) => void;
  /** Optional: detect if any filter is active to enable Save button */
  hasActiveFilters?: boolean;
}

export function FilterPresets<T>({
  filterType,
  currentConfig,
  onApply,
  hasActiveFilters = true,
}: Props<T>) {
  const { data: presets = [] } = useSavedFilters(filterType);
  const createPreset = useCreateSavedFilter();
  const deletePreset = useDeleteSavedFilter();
  const [saveOpen, setSaveOpen] = useState(false);
  const [name, setName] = useState('');

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

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="outline" size="sm" className="gap-1">
            <Bookmark className="h-3.5 w-3.5" />
            <span className="hidden sm:inline">Presets</span>
            {presets.length > 0 && (
              <span className="ml-0.5 text-xs text-muted-foreground">({presets.length})</span>
            )}
            <ChevronDown className="h-3 w-3 opacity-60" />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="w-64">
          <DropdownMenuLabel className="text-xs">Filtros salvos</DropdownMenuLabel>
          {presets.length === 0 ? (
            <div className="px-2 py-3 text-xs text-muted-foreground">
              Nenhum preset ainda. Configure os filtros e clique em "Salvar atual".
            </div>
          ) : (
            presets.map((p: any) => (
              <DropdownMenuItem
                key={p.id}
                className="flex items-center justify-between gap-2 group"
                onSelect={(e) => {
                  e.preventDefault();
                  onApply(p.filter_config as T);
                  toast.success(`Preset "${p.name}" aplicado`);
                }}
              >
                <div className="flex items-center gap-2 min-w-0">
                  <Check className="h-3 w-3 text-accent shrink-0" />
                  <span className="truncate">{p.name}</span>
                </div>
                <button
                  type="button"
                  onClick={(e) => {
                    e.stopPropagation();
                    handleDelete(p.id, p.name);
                  }}
                  className="opacity-0 group-hover:opacity-100 text-muted-foreground hover:text-destructive transition"
                  aria-label="Excluir preset"
                >
                  <Trash2 className="h-3 w-3" />
                </button>
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
