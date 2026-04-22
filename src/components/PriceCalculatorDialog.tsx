import { useEffect, useMemo, useState } from 'react';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { MoneyInput } from '@/components/MoneyInput';
import { useI18n } from '@/i18n';
import { calculateSalePrice, calculateByMarkup } from '@/lib/price-calculator';

type Method = 'margin' | 'markup';

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  /** Initial cost price (auto-filled from product cost) */
  initialCost?: number;
  /** Initial sale price (current value of the field being edited) */
  initialPrice?: number;
  /** Initial profit margin % (used in margin mode) */
  initialMargin?: number;
  /** Initial markup % (used in markup mode) */
  initialMarkup?: number;
  /** Initial tax rate % */
  initialTaxRate?: number;
  /** Initial commission rate % */
  initialCommissionRate?: number;
  /** Default method (margin or markup) */
  defaultMethod?: Method;
  /** Called with the final sale price when user confirms */
  onConfirm: (salePrice: number) => void;
}

export function PriceCalculatorDialog({
  open,
  onOpenChange,
  initialCost = 0,
  initialPrice = 0,
  initialMargin = 30,
  initialMarkup = 50,
  initialTaxRate = 0,
  initialCommissionRate = 0,
  defaultMethod = 'margin',
  onConfirm,
}: Props) {
  const { formatCurrency } = useI18n();

  const [method, setMethod] = useState<Method>(defaultMethod);
  const [cost, setCost] = useState(initialCost);
  const [margin, setMargin] = useState(initialMargin);
  const [markup, setMarkup] = useState(initialMarkup);
  const [tax, setTax] = useState(initialTaxRate);
  const [commission, setCommission] = useState(initialCommissionRate);

  // Reset on open
  useEffect(() => {
    if (open) {
      setMethod(defaultMethod);
      setCost(initialCost);
      setMargin(initialMargin);
      setMarkup(initialMarkup);
      setTax(initialTaxRate);
      setCommission(initialCommissionRate);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);

  const breakdown = useMemo(() => {
    if (method === 'markup') {
      return calculateByMarkup({
        cost_price: cost,
        profit_margin: margin,
        tax_rate: tax,
        commission_rate: commission,
        markup,
      });
    }
    return calculateSalePrice({
      cost_price: cost,
      profit_margin: margin,
      tax_rate: tax,
      commission_rate: commission,
    });
  }, [method, cost, margin, markup, tax, commission]);

  const impossible = method === 'margin' && (margin + tax + commission) >= 100;

  const handleConfirm = () => {
    onConfirm(Number(breakdown.sale_price.toFixed(2)));
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Formador de Preço</DialogTitle>
          <DialogDescription>
            Calcule o preço de venda usando margem ou markup.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <Tabs value={method} onValueChange={(v) => setMethod(v as Method)}>
            <TabsList className="grid w-full grid-cols-2">
              <TabsTrigger value="margin">Margem</TabsTrigger>
              <TabsTrigger value="markup">Markup</TabsTrigger>
            </TabsList>
          </Tabs>

          <p className="text-xs text-muted-foreground">
            {method === 'margin'
              ? 'Preço = Custo ÷ (1 − margem% − impostos% − comissão%)'
              : 'Preço = Custo × (1 + markup%)'}
          </p>

          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label className="text-xs">Custo (R$)</Label>
              <MoneyInput value={cost} onValueChange={setCost} className="text-sm" />
            </div>

            {method === 'margin' ? (
              <div>
                <Label className="text-xs">Margem %</Label>
                <MoneyInput value={margin} onValueChange={setMargin} className="text-sm" />
              </div>
            ) : (
              <div>
                <Label className="text-xs">Markup %</Label>
                <MoneyInput value={markup} onValueChange={setMarkup} className="text-sm" />
              </div>
            )}

            <div>
              <Label className="text-xs">Impostos %</Label>
              <MoneyInput value={tax} onValueChange={setTax} className="text-sm" />
            </div>
            <div>
              <Label className="text-xs">Comissão %</Label>
              <MoneyInput value={commission} onValueChange={setCommission} className="text-sm" />
            </div>
          </div>

          <div className="rounded-xl border bg-muted/30 p-4 space-y-2 text-sm">
            <div className="flex justify-between">
              <span className="text-muted-foreground">Custo</span>
              <span>{formatCurrency(cost)}</span>
            </div>
            <div className="border-t my-1" />
            <div className="flex justify-between">
              <span className="text-amber-600">Impostos ({tax}%)</span>
              <span className="text-amber-600">{formatCurrency(breakdown.tax_amount)}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-blue-600">Comissão ({commission}%)</span>
              <span className="text-blue-600">{formatCurrency(breakdown.commission_amount)}</span>
            </div>
            <div className="flex justify-between">
              <span className={breakdown.profit_amount > 0 ? 'text-emerald-600' : 'text-destructive'}>
                Lucro líquido
              </span>
              <span className={breakdown.profit_amount > 0 ? 'text-emerald-600 font-medium' : 'text-destructive font-medium'}>
                {formatCurrency(breakdown.profit_amount)}
              </span>
            </div>
            <div className="border-t my-1" />
            <div className="flex justify-between items-center">
              <span className="font-bold text-base">PREÇO DE VENDA</span>
              <span className="font-bold text-xl">{formatCurrency(breakdown.sale_price)}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-xs text-muted-foreground">Markup sobre custo</span>
              <span className="text-xs text-muted-foreground">{breakdown.markup}%</span>
            </div>
          </div>

          {impossible && (
            <div className="rounded-lg border border-destructive/30 bg-destructive/10 p-3 text-sm text-destructive">
              ⚠️ Soma de margem + impostos + comissão ≥ 100% — preço impossível.
            </div>
          )}
        </div>

        <DialogFooter>
          <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
            Cancelar
          </Button>
          <Button type="button" onClick={handleConfirm} disabled={impossible || breakdown.sale_price <= 0}>
            Aplicar preço
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
