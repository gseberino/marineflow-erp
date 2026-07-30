import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Plus, Trash2, Wand2 } from 'lucide-react';
import { toast } from 'sonner';
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Checkbox } from '@/components/ui/checkbox';
import { cn } from '@/lib/utils';
import { useSuppliers } from '@/hooks/use-suppliers';
import { useCreateQuoteRequest, type NewQuoteItem } from '@/hooks/use-quote-requests';
import { fetchPurchaseNeeds } from '@/hooks/use-purchase-needs';

/**
 * Nova cotação. Aceita item do catálogo e texto livre no mesmo pedido, porque é
 * assim que a operação funciona: parte do que se cota tem cadastro, parte é
 * "cabo 70mm² vermelho" escrito na hora.
 *
 * Quando vem de uma OS, os itens já entram preenchidos pela necessidade líquida —
 * o operador não redigita o que o sistema já sabe que falta.
 */

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  /** quando vem da OS: pré-carrega os itens em falta e mantém o vínculo */
  serviceOrderId?: string | null;
  serviceOrderLabel?: string | null;
  prefilledItems?: NewQuoteItem[];
}

interface DraftItem extends NewQuoteItem {
  key: string;
}

let seq = 0;
const newKey = () => `it-${++seq}`;

export function NewQuoteRequestDialog({
  open, onOpenChange, serviceOrderId, serviceOrderLabel, prefilledItems,
}: Props) {
  const navigate = useNavigate();
  const createQuote = useCreateQuoteRequest();
  const { data: suppliers } = useSuppliers();

  const [items, setItems] = useState<DraftItem[]>([]);
  const [supplierIds, setSupplierIds] = useState<string[]>([]);
  const [notes, setNotes] = useState('');
  const [supplierSearch, setSupplierSearch] = useState('');
  const [loadingNeeds, setLoadingNeeds] = useState(false);

  // Reabrir o diálogo sempre parte de um estado limpo — vazamento de estado entre
  // aberturas já causou bug neste repo (import de XML, 22/07).
  useEffect(() => {
    if (!open) return;
    setSupplierIds([]);
    setNotes('');
    setSupplierSearch('');
    if (prefilledItems?.length) {
      setItems(prefilledItems.map(i => ({ ...i, key: newKey() })));
      return;
    }
    setItems([{ key: newKey(), description: '', quantity: 1 }]);
    if (serviceOrderId) {
      setLoadingNeeds(true);
      fetchPurchaseNeeds(serviceOrderId)
        .then(needs => {
          if (!needs.shortages.length) return;
          setItems(needs.shortages.map(s => ({
            key: newKey(),
            description: s.description,
            quantity: s.shortage,
            product_id: s.productId,
            service_order_part_id: s.origin === 'part' ? s.sourceId : null,
            service_order_service_id: s.origin === 'free_text' ? s.sourceId : null,
          })));
        })
        .catch(() => { /* sem necessidade calculada, segue com linha vazia */ })
        .finally(() => setLoadingNeeds(false));
    }
  }, [open, serviceOrderId, prefilledItems]);

  const filteredSuppliers = useMemo(() => {
    const list = suppliers ?? [];
    const term = supplierSearch.trim().toLowerCase();
    const base = term
      ? list.filter((s: any) =>
          (s.name ?? '').toLowerCase().includes(term) ||
          (s.trade_name ?? '').toLowerCase().includes(term))
      : list;
    // Selecionados sempre visíveis, para não "desaparecerem" ao filtrar.
    const selected = list.filter((s: any) => supplierIds.includes(s.id));
    const merged = [...selected, ...base.filter((s: any) => !supplierIds.includes(s.id))];
    return merged.slice(0, 40);
  }, [suppliers, supplierSearch, supplierIds]);

  const validItems = items.filter(i => i.description.trim() && Number(i.quantity) > 0);

  function updateItem(key: string, patch: Partial<DraftItem>) {
    setItems(prev => prev.map(i => (i.key === key ? { ...i, ...patch } : i)));
  }

  async function handleSave() {
    if (!validItems.length) {
      toast.error('Informe ao menos um item com descrição e quantidade.');
      return;
    }
    const created = await createQuote.mutateAsync({
      items: validItems.map(({ key: _k, ...rest }) => rest),
      serviceOrderId: serviceOrderId ?? null,
      supplierIds,
      notes: notes.trim() || null,
    });
    onOpenChange(false);
    if (created?.id) navigate(`/purchasing/quotes/${created.id}`);
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[92vh] max-w-2xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Nova cotação</DialogTitle>
          <DialogDescription>
            {serviceOrderLabel
              ? `Itens em falta de ${serviceOrderLabel}. Confira antes de enviar.`
              : 'Itens podem ser do catálogo ou digitados livremente.'}
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-5">
          <section className="space-y-2">
            <div className="flex items-center justify-between">
              <Label>Itens a cotar</Label>
              {loadingNeeds && (
                <span className="inline-flex items-center gap-1 text-xs text-muted-foreground">
                  <Wand2 className="h-3 w-3 animate-pulse" /> buscando o que falta…
                </span>
              )}
            </div>
            <div className="space-y-2">
              {items.map((item, idx) => (
                <div key={item.key} className="flex items-start gap-2">
                  <span className="mt-2.5 w-5 shrink-0 text-right text-xs tabular-nums text-muted-foreground">
                    {idx + 1}
                  </span>
                  <Input
                    value={item.description}
                    onChange={e => updateItem(item.key, { description: e.target.value })}
                    placeholder="Descrição do item"
                    className="flex-1"
                  />
                  <Input
                    type="number"
                    inputMode="decimal"
                    min={0}
                    step="any"
                    value={item.quantity}
                    onChange={e => updateItem(item.key, { quantity: parseFloat(e.target.value) || 0 })}
                    className="w-20 shrink-0 text-right"
                    aria-label="Quantidade"
                  />
                  <Button
                    type="button"
                    variant="ghost"
                    size="icon"
                    className="shrink-0 text-muted-foreground hover:text-destructive"
                    onClick={() => setItems(prev => prev.filter(i => i.key !== item.key))}
                    aria-label="Remover item"
                    disabled={items.length === 1}
                  >
                    <Trash2 className="h-4 w-4" />
                  </Button>
                </div>
              ))}
            </div>
            <Button
              type="button"
              variant="outline"
              size="sm"
              className="gap-1"
              onClick={() => setItems(prev => [...prev, { key: newKey(), description: '', quantity: 1 }])}
            >
              <Plus className="h-3.5 w-3.5" /> Adicionar item
            </Button>
          </section>

          <section className="space-y-2">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <Label>Fornecedores a consultar</Label>
              <span className="text-xs text-muted-foreground">
                {supplierIds.length} selecionado{supplierIds.length === 1 ? '' : 's'}
              </span>
            </div>
            <Input
              value={supplierSearch}
              onChange={e => setSupplierSearch(e.target.value)}
              placeholder="Buscar fornecedor…"
            />
            <div className="max-h-48 space-y-0.5 overflow-y-auto rounded-md border p-1">
              {filteredSuppliers.length === 0 ? (
                <p className="p-3 text-sm text-muted-foreground">Nenhum fornecedor encontrado.</p>
              ) : (
                filteredSuppliers.map((s: any) => {
                  const checked = supplierIds.includes(s.id);
                  return (
                    <label
                      key={s.id}
                      className={cn(
                        'flex cursor-pointer items-center gap-2 rounded px-2 py-1.5 text-sm hover:bg-accent',
                        checked && 'bg-accent/60',
                      )}
                    >
                      <Checkbox
                        checked={checked}
                        onCheckedChange={v =>
                          setSupplierIds(prev => (v ? [...prev, s.id] : prev.filter(id => id !== s.id)))
                        }
                      />
                      <span className="min-w-0 flex-1 truncate">{s.name}</span>
                      {!s.phone && (
                        <span className="shrink-0 text-[11px] text-muted-foreground">sem telefone</span>
                      )}
                    </label>
                  );
                })
              )}
            </div>
            <p className="text-xs text-muted-foreground">
              A cotação é criada aqui; o envio por WhatsApp continua sendo feito pelo agente,
              que já monta a mensagem com os itens numerados.
            </p>
          </section>

          <section className="space-y-2">
            <Label htmlFor="quote-notes">Observação interna</Label>
            <Textarea
              id="quote-notes"
              value={notes}
              onChange={e => setNotes(e.target.value)}
              placeholder="Para que serve, urgência, condição desejada… (não vai na mensagem ao fornecedor)"
              rows={2}
            />
          </section>
        </div>

        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)}>Cancelar</Button>
          <Button onClick={handleSave} disabled={createQuote.isPending || !validItems.length}>
            {createQuote.isPending ? 'Criando…' : `Criar cotação (${validItems.length})`}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
