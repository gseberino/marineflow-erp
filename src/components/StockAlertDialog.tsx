import { useState } from 'react';
import { AlertTriangle, ShoppingCart, Loader2, PackagePlus } from 'lucide-react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useCreatePOFromOS } from '@/hooks/use-purchase-orders';

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  serviceOrderId: string;
  productId: string;
  productName: string;
  needed: number;
  available: number;
  unitCost: number;
  suppliers?: { id: string; name: string }[];
  leadTimeDays?: number;
  onAddAnyway: () => void;   // proceed with negative stock
}

const fmt = (v: number) =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);

export function StockAlertDialog({
  open, onOpenChange,
  serviceOrderId, productId, productName,
  needed, available, unitCost,
  suppliers = [],
  leadTimeDays,
  onAddAnyway,
}: Props) {
  const createPO = useCreatePOFromOS();
  const missing = needed - Math.max(0, available);

  const [supplierId, setSupplierId] = useState(suppliers[0]?.id ?? '');
  const [expectedDate, setExpectedDate] = useState(() => {
    if (!leadTimeDays) return '';
    const d = new Date();
    d.setDate(d.getDate() + leadTimeDays);
    return d.toISOString().split('T')[0];
  });

  const handleCreatePO = async () => {
    await createPO.mutateAsync({
      serviceOrderId,
      productId,
      productName,
      quantity:     missing,
      unitCost,
      supplierId:   supplierId || undefined,
      expectedDate: expectedDate || undefined,
    });
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={v => !createPO.isPending && onOpenChange(v)}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2 text-amber-700">
            <AlertTriangle className="h-5 w-5" />
            Estoque insuficiente
          </DialogTitle>
          <DialogDescription asChild>
            <div className="space-y-2 mt-1">
              <p className="text-sm font-medium text-foreground">{productName}</p>
              <div className="grid grid-cols-3 gap-2 text-center">
                <div className="rounded bg-muted p-2">
                  <div className="text-lg font-bold">{available}</div>
                  <div className="text-xs text-muted-foreground">Em estoque</div>
                </div>
                <div className="rounded bg-muted p-2">
                  <div className="text-lg font-bold">{needed}</div>
                  <div className="text-xs text-muted-foreground">Necessário</div>
                </div>
                <div className="rounded bg-amber-100 border border-amber-200 p-2">
                  <div className="text-lg font-bold text-amber-700">{missing}</div>
                  <div className="text-xs text-amber-600">Faltam</div>
                </div>
              </div>
            </div>
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3 py-2">
          <p className="text-sm font-medium">Criar ordem de compra para {missing} un.?</p>

          {/* Supplier */}
          {suppliers.length > 0 && (
            <div className="space-y-1.5">
              <Label className="text-xs">Fornecedor</Label>
              <Select value={supplierId} onValueChange={setSupplierId}>
                <SelectTrigger className="h-8 text-sm"><SelectValue placeholder="Selecionar..." /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="">Sem fornecedor definido</SelectItem>
                  {suppliers.map(s => (
                    <SelectItem key={s.id} value={s.id}>{s.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          )}

          {/* Expected date */}
          <div className="space-y-1.5">
            <Label className="text-xs">
              Previsão de chegada
              {leadTimeDays ? ` (lead time: ${leadTimeDays} dias)` : ''}
            </Label>
            <Input type="date" className="h-8 text-sm" value={expectedDate}
              onChange={e => setExpectedDate(e.target.value)} />
          </div>

          {/* Cost summary */}
          <div className="rounded bg-muted/40 px-3 py-2 text-xs flex justify-between">
            <span className="text-muted-foreground">Valor estimado da compra:</span>
            <span className="font-semibold">{fmt(missing * unitCost)}</span>
          </div>
        </div>

        <DialogFooter className="gap-2 sm:gap-0 flex-col sm:flex-row">
          <Button
            variant="ghost"
            size="sm"
            className="text-muted-foreground text-xs"
            onClick={() => { onAddAnyway(); onOpenChange(false); }}
            disabled={createPO.isPending}
          >
            Adicionar assim mesmo (estoque negativo)
          </Button>
          <div className="flex gap-2">
            <Button variant="outline" onClick={() => onOpenChange(false)} disabled={createPO.isPending}>
              Cancelar
            </Button>
            <Button
              onClick={handleCreatePO}
              disabled={createPO.isPending}
              className="gap-2 bg-amber-600 hover:bg-amber-700 text-white"
            >
              {createPO.isPending
                ? <Loader2 className="h-4 w-4 animate-spin" />
                : <ShoppingCart className="h-4 w-4" />
              }
              {createPO.isPending ? 'Criando PO...' : `Criar PO — ${missing} un.`}
            </Button>
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
