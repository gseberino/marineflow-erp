import { useState } from 'react';
import { Loader2, PackageCheck, CheckCircle2 } from 'lucide-react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { useReceivePO, PO_STATUS_COLORS, type PurchaseOrder } from '@/hooks/use-purchase-orders';
import { cn } from '@/lib/utils';

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  po: PurchaseOrder;
}

export function ReceivePODialog({ open, onOpenChange, po }: Props) {
  const receivePO = useReceivePO();

  // Local qty state per item: itemId → received qty this session
  const [receiveQtys, setReceiveQtys] = useState<Record<string, number>>({});

  const items = po.purchase_order_items ?? [];

  const setQty = (itemId: string, val: number) =>
    setReceiveQtys(prev => ({ ...prev, [itemId]: Math.max(0, val) }));

  const totalBeingReceived = Object.values(receiveQtys).reduce((s, v) => s + v, 0);
  const hasAny = totalBeingReceived > 0;

  const handleConfirm = async () => {
    const payload = Object.entries(receiveQtys)
      .filter(([, qty]) => qty > 0)
      .map(([po_item_id, received_qty]) => ({ po_item_id, received_qty }));

    if (!payload.length) return;
    await receivePO.mutateAsync({ poId: po.id, items: payload });
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={v => !receivePO.isPending && onOpenChange(v)}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <PackageCheck className="h-5 w-5 text-green-600" />
            Registrar recebimento — {po.po_number}
          </DialogTitle>
          <DialogDescription>
            {po.suppliers?.name ?? 'Fornecedor não definido'} · Informe as quantidades que chegaram hoje.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3 py-1 max-h-[50vh] overflow-y-auto pr-1">
          {items.map(item => {
            const pending    = item.quantity - item.received_qty;
            const entering   = receiveQtys[item.id] ?? 0;
            const isComplete = item.received_qty >= item.quantity;

            return (
              <div key={item.id} className={cn(
                'rounded-lg border p-3 space-y-2',
                isComplete ? 'opacity-50 bg-muted/30' : 'bg-card',
              )}>
                <div className="flex justify-between items-start gap-2">
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium truncate">{item.description}</p>
                    {item.products?.sku && (
                      <p className="text-xs text-muted-foreground">SKU: {item.products.sku}</p>
                    )}
                  </div>
                  {isComplete
                    ? <Badge className="gap-1 bg-green-100 text-green-700 border-green-200 shrink-0">
                        <CheckCircle2 className="h-3 w-3" /> Recebido
                      </Badge>
                    : <span className="text-xs text-muted-foreground whitespace-nowrap shrink-0">
                        Pendente: {pending} {/* unit */}
                      </span>
                  }
                </div>

                {!isComplete && (
                  <div className="flex items-center gap-3">
                    <Label className="text-xs text-muted-foreground whitespace-nowrap">
                      Qtd recebida agora:
                    </Label>
                    <Input
                      type="number"
                      min={0}
                      max={pending}
                      step={1}
                      className="w-24 h-7 text-right text-sm"
                      value={entering || ''}
                      placeholder="0"
                      onChange={e => setQty(item.id, parseFloat(e.target.value) || 0)}
                    />
                    <button
                      type="button"
                      className="text-xs text-blue-600 hover:underline"
                      onClick={() => setQty(item.id, pending)}
                    >
                      Tudo ({pending})
                    </button>
                  </div>
                )}
              </div>
            );
          })}
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={receivePO.isPending}>
            Cancelar
          </Button>
          <Button
            onClick={handleConfirm}
            disabled={!hasAny || receivePO.isPending}
            className="gap-2 bg-green-600 hover:bg-green-700 text-white"
          >
            {receivePO.isPending
              ? <Loader2 className="h-4 w-4 animate-spin" />
              : <PackageCheck className="h-4 w-4" />
            }
            {receivePO.isPending ? 'Registrando...' : 'Confirmar recebimento'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
