import { useState, useEffect, useMemo } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { MoneyInput } from '@/components/MoneyInput';
import { calculateSalePrice } from '@/lib/price-calculator';

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  initialCost?: number;
  initialPrice?: number;
  onConfirm: (price: number) => void;
}

export function PriceCalculatorDialog({ open, onOpenChange, initialCost = 0, initialPrice = 0, onConfirm }: Props) {
  const [mode, setMode] = useState<'margin' | 'markup'>('margin');
  const [cost, setCost] = useState(initialCost);
  const [margin, setMargin] = useState(30);
  const [markup, setMarkup] = useState(50);
  const [tax, setTax] = useState(0);
  const [commission, setCommission] = useState(0);

  useEffect(() => {
    if (open) {
      setCost(initialCost);
    }
  }, [open, initialCost]);

  const result = useMemo(() => {
    if (mode === 'margin') {
      return calculateSalePrice({
        cost_price: cost,
        profit_margin: margin,
        tax_rate: tax,
        commission_rate: commission,
      });
    }
    // Markup: price = cost × (1 + markup/100), then add tax and commission on top
    const base = cost * (1 + markup / 100);
    const divisor = 1 - tax / 100 - commission / 100;
    const sale_price = divisor > 0 ? base / divisor : 0;
    const tax_amount = sale_price * (tax / 100);
    const commission_amount = sale_price * (commission / 100);
    const profit_amount = sale_price - cost - tax_amount - commission_amount;
    return {
      cost_price: cost,
      profit_margin: 0,
      tax_rate: tax,
      commission_rate: commission,
      sale_price: Math.round(sale_price * 100) / 100,
      tax_amount: Math.round(tax_amount * 100) / 100,
      commission_amount: Math.round(commission_amount * 100) / 100,
      profit_amount: Math.round(profit_amount * 100) / 100,
      markup,
    };
  }, [mode, cost, margin, markup, tax, commission]);

  const handleConfirm = () => {
    onConfirm(result.sale_price);
    onOpenChange(false);
  };

  const fmt = (n: number) => n.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>💰 Formador de Preço</DialogTitle>
        </DialogHeader>

        <Tabs value={mode} onValueChange={(v) => setMode(v as 'margin' | 'markup')}>
          <TabsList className="grid w-full grid-cols-2">
            <TabsTrigger value="margin">Margem</TabsTrigger>
            <TabsTrigger value="markup">Markup</TabsTrigger>
          </TabsList>
        </Tabs>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div className="col-span-2">
            <Label className="text-xs">Preço de Custo (R$)</Label>
            <MoneyInput value={cost} onValueChange={setCost} />
          </div>
          {mode === 'margin' ? (
            <div className="col-span-2">
              <Label className="text-xs">Margem de lucro (%)</Label>
              <MoneyInput value={margin} onValueChange={setMargin} />
            </div>
          ) : (
            <div className="col-span-2">
              <Label className="text-xs">Markup (%)</Label>
              <MoneyInput value={markup} onValueChange={setMarkup} />
            </div>
          )}
          <div>
            <Label className="text-xs">Impostos (%)</Label>
            <MoneyInput value={tax} onValueChange={setTax} />
          </div>
          <div>
            <Label className="text-xs">Comissão (%)</Label>
            <MoneyInput value={commission} onValueChange={setCommission} />
          </div>
        </div>

        <div className="rounded-lg border bg-muted/30 p-3 space-y-1 text-sm">
          <div className="flex justify-between"><span className="text-muted-foreground">Custo</span><span>{fmt(cost)}</span></div>
          <div className="flex justify-between"><span className="text-muted-foreground">Impostos</span><span>{fmt(result.tax_amount)}</span></div>
          <div className="flex justify-between"><span className="text-muted-foreground">Comissão</span><span>{fmt(result.commission_amount)}</span></div>
          <div className="flex justify-between"><span className="text-muted-foreground">Lucro líquido</span><span>{fmt(result.profit_amount)}</span></div>
          <div className="border-t pt-1 flex justify-between font-bold"><span>PREÇO DE VENDA</span><span>{fmt(result.sale_price)}</span></div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancelar</Button>
          <Button onClick={handleConfirm}>Usar este preço</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
