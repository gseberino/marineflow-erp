import { useEffect, useState } from 'react';
import { CheckCircle2, ShoppingCart, Loader2, PackageCheck, AlertTriangle } from 'lucide-react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { supabase } from '@/integrations/supabase/client';
import { useCreatePOFromOS } from '@/hooks/use-purchase-orders';
import { useToast } from '@/hooks/use-toast';
import { cn } from '@/lib/utils';

interface PartStockItem {
  id: string;
  product_id: string;
  name: string;
  sku?: string;
  quantity: number;
  unit_cost: number;
  stock_quantity: number;
  supplier_id?: string;
  supplier_name?: string;
  lead_time_days?: number;
}

type Decision = 'confirmed' | 'create_po';

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  serviceOrderId: string;
  serviceOrderNumber: string;
}

const fmt = (v: number) =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);

export function StockConfirmationDialog({ open, onOpenChange, serviceOrderId, serviceOrderNumber }: Props) {
  const { toast } = useToast();
  const createPO = useCreatePOFromOS();

  const [parts, setParts] = useState<PartStockItem[]>([]);
  const [decisions, setDecisions] = useState<Record<string, Decision>>({});
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (!open || !serviceOrderId) return;
    setLoading(true);
    setDecisions({});

    const fetch = async () => {
      // Fetch parts with product stock and preferred supplier
      const { data: partsData } = await supabase
        .from('service_order_parts')
        .select(`
          id, product_id, quantity, unit_cost_snapshot,
          products(name, sku, stock_quantity,
            product_suppliers(supplier_id, lead_time_days, is_preferred,
              suppliers(id, name)
            )
          )
        `)
        .eq('service_order_id', serviceOrderId);

      const items: PartStockItem[] = (partsData ?? []).map((p: any) => {
        const prod = p.products;
        const preferredSupplier = (prod?.product_suppliers ?? []).find((ps: any) => ps.is_preferred)
          ?? (prod?.product_suppliers ?? [])[0];
        return {
          id: p.id,
          product_id: p.product_id,
          name: prod?.name ?? 'Produto',
          sku: prod?.sku ?? undefined,
          quantity: Number(p.quantity),
          unit_cost: Number(p.unit_cost_snapshot),
          stock_quantity: Number(prod?.stock_quantity ?? 0),
          supplier_id: preferredSupplier?.suppliers?.id,
          supplier_name: preferredSupplier?.suppliers?.name,
          lead_time_days: preferredSupplier?.lead_time_days,
        };
      });

      setParts(items);

      // Auto-suggest decisions based on stock
      const auto: Record<string, Decision> = {};
      for (const item of items) {
        auto[item.id] = item.stock_quantity >= item.quantity ? 'confirmed' : 'create_po';
      }
      setDecisions(auto);
      setLoading(false);
    };

    fetch();
  }, [open, serviceOrderId]);

  const setDecision = (id: string, d: Decision) =>
    setDecisions(prev => ({ ...prev, [id]: d }));

  const needPO    = parts.filter(p => decisions[p.id] === 'create_po');
  const confirmed = parts.filter(p => decisions[p.id] === 'confirmed');

  const handleConfirm = async () => {
    if (submitting) return;
    setSubmitting(true);
    try {
      // Create POs for items that need ordering
      for (const part of needPO) {
        const expectedDate = part.lead_time_days
          ? new Date(Date.now() + part.lead_time_days * 86400000).toISOString().split('T')[0]
          : undefined;

        await createPO.mutateAsync({
          serviceOrderId,
          productId:    part.product_id,
          productName:  part.name,
          quantity:     part.quantity,
          unitCost:     part.unit_cost,
          supplierId:   part.supplier_id,
          expectedDate,
        });
      }

      if (needPO.length > 0) {
        toast({
          title: `${needPO.length} OC(s) geradas`,
          description: `OS movida para "Aguardando Peças". ${confirmed.length} iten(s) confirmados no estoque.`,
        });
      } else {
        toast({ title: 'Estoque confirmado para todos os itens.' });
      }
      onOpenChange(false);
    } catch (err: any) {
      toast({ title: 'Erro ao processar', description: err.message, variant: 'destructive' });
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={v => !submitting && onOpenChange(v)}>
      <DialogContent className="max-w-lg flex flex-col max-h-[90vh]">
        <DialogHeader className="shrink-0">
          <DialogTitle className="flex items-center gap-2">
            <PackageCheck className="h-5 w-5 text-blue-600" />
            Confirmar estoque — {serviceOrderNumber}
          </DialogTitle>
          <DialogDescription>
            O orçamento foi convertido em OS. Confirme se cada peça está disponível fisicamente.
            Itens não disponíveis terão uma Ordem de Compra gerada automaticamente.
          </DialogDescription>
        </DialogHeader>

        {/* Scrollable body */}
        <div className="flex-1 overflow-y-auto min-h-0 py-1 pr-1 space-y-2">
          {loading ? (
            <div className="flex items-center justify-center py-8 text-muted-foreground">
              <Loader2 className="h-5 w-5 animate-spin mr-2" /> Carregando peças...
            </div>
          ) : parts.length === 0 ? (
            <div className="py-6 text-center text-sm text-muted-foreground">
              Nenhuma peça registrada neste orçamento.
            </div>
          ) : (
            parts.map(part => {
              const decision = decisions[part.id];
              const stockOk  = part.stock_quantity >= part.quantity;
              const stockGap = part.quantity - Math.max(0, part.stock_quantity);

              return (
                <div key={part.id} className={cn(
                  'rounded-lg border p-3 space-y-2 transition-colors',
                  decision === 'confirmed' ? 'border-green-200 bg-green-50' : 'border-amber-200 bg-amber-50',
                )}>
                  <div className="flex justify-between items-start gap-2">
                    <div className="min-w-0">
                      <p className="text-sm font-medium truncate">{part.name}</p>
                      <p className="text-xs text-muted-foreground">
                        {part.sku && `SKU: ${part.sku} · `}
                        Necessário: {part.quantity} un.
                        {' · '}
                        <span className={part.stock_quantity >= part.quantity ? 'text-green-700' : 'text-amber-700'}>
                          Sistema: {part.stock_quantity} un.
                        </span>
                      </p>
                    </div>
                    {!stockOk && (
                      <Badge className="bg-amber-100 text-amber-700 border-amber-200 gap-1 shrink-0">
                        <AlertTriangle className="h-3 w-3" /> Faltam {stockGap}
                      </Badge>
                    )}
                  </div>

                  <div className="flex gap-2">
                    <Button
                      type="button"
                      size="sm"
                      variant="outline"
                      onClick={() => setDecision(part.id, 'confirmed')}
                      className={cn(
                        'flex-1 h-8 text-xs gap-1 transition-colors',
                        decision === 'confirmed'
                          ? 'bg-green-600 text-white border-green-600 hover:bg-green-700'
                          : 'hover:bg-green-50 hover:border-green-300 hover:text-green-700',
                      )}
                    >
                      <CheckCircle2 className="h-3.5 w-3.5" />
                      No estoque físico ✓
                    </Button>
                    <Button
                      type="button"
                      size="sm"
                      variant="outline"
                      onClick={() => setDecision(part.id, 'create_po')}
                      className={cn(
                        'flex-1 h-8 text-xs gap-1 transition-colors',
                        decision === 'create_po'
                          ? 'bg-amber-500 text-white border-amber-500 hover:bg-amber-600'
                          : 'hover:bg-amber-50 hover:border-amber-300 hover:text-amber-700',
                      )}
                    >
                      <ShoppingCart className="h-3.5 w-3.5" />
                      Gerar OC {part.supplier_name ? `(${part.supplier_name})` : ''}
                    </Button>
                  </div>
                </div>
              );
            })
          )}
        </div>

        {/* Fixed footer area */}
        {!loading && parts.length > 0 && (
          <div className="shrink-0 rounded-lg bg-muted/40 px-3 py-2 text-xs flex flex-wrap justify-between gap-1">
            <span className="text-muted-foreground">
              <span className="text-green-700 font-medium">{confirmed.length}</span> no estoque ·{' '}
              <span className="text-amber-700 font-medium">{needPO.length}</span> gerar OC
            </span>
            {needPO.length > 0 && (
              <span className="text-amber-700 font-medium">
                Estimado: {fmt(needPO.reduce((s, p) => s + p.quantity * p.unit_cost, 0))}
              </span>
            )}
          </div>
        )}

        <DialogFooter className="shrink-0 pt-2">
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={submitting}>
            Fazer depois
          </Button>
          <Button
            onClick={handleConfirm}
            disabled={loading || submitting || parts.length === 0}
            className="gap-2"
          >
            {submitting && <Loader2 className="h-4 w-4 animate-spin" />}
            {submitting ? 'Processando...' : needPO.length > 0
              ? `Confirmar e gerar ${needPO.length} OC(s)`
              : 'Confirmar estoque'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
