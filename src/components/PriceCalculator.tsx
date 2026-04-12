import { useMemo } from 'react';
import { useI18n } from '@/i18n';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Button } from '@/components/ui/button';
import { calculateSalePrice, calculateMarginFromPrice } from '@/lib/price-calculator';

interface Props {
  costPrice: number;
  salePrice: number;
  profitMargin: number;
  taxRate: number;
  commissionRate: number;
  currency?: string;
  mode: 'calculate' | 'direct';
  onModeChange: (m: 'calculate' | 'direct') => void;
  onSalePriceChange: (v: number) => void;
  onProfitMarginChange: (v: number) => void;
  onTaxRateChange: (v: number) => void;
  onCommissionRateChange: (v: number) => void;
}

export function PriceCalculator({
  costPrice, salePrice, profitMargin, taxRate, commissionRate,
  mode, onModeChange,
  onSalePriceChange, onProfitMarginChange, onTaxRateChange, onCommissionRateChange,
}: Props) {
  const { t, formatCurrency } = useI18n();
  const p = t.products as any;

  const breakdown = useMemo(() =>
    calculateSalePrice({ cost_price: costPrice, profit_margin: profitMargin, tax_rate: taxRate, commission_rate: commissionRate }),
    [costPrice, profitMargin, taxRate, commissionRate]
  );

  const effectiveSalePrice = mode === 'calculate' ? breakdown.sale_price : salePrice;
  const resultingMargin = mode === 'direct'
    ? calculateMarginFromPrice(costPrice, salePrice, taxRate, commissionRate)
    : profitMargin;

  const directBreakdown = useMemo(() => {
    if (mode !== 'direct') return breakdown;
    return calculateSalePrice({ cost_price: costPrice, profit_margin: resultingMargin, tax_rate: taxRate, commission_rate: commissionRate });
  }, [mode, costPrice, salePrice, resultingMargin, taxRate, commissionRate]);

  const bd = mode === 'calculate' ? breakdown : directBreakdown;

  // Sync calculated price to parent in calculate mode
  const prevCalcPrice = useMemo(() => {
    if (mode === 'calculate' && breakdown.sale_price > 0) {
      onSalePriceChange(breakdown.sale_price);
    }
    return breakdown.sale_price;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [breakdown.sale_price, mode]);

  const impossiblePrice = (profitMargin + taxRate + commissionRate) >= 100;

  return (
    <div className="space-y-4">
      {/* Mode toggle */}
      <div className="flex gap-1 p-1 rounded-lg bg-muted/50 w-fit">
        <Button
          type="button" size="sm" variant={mode === 'calculate' ? 'default' : 'outline'}
          onClick={() => onModeChange('calculate')}
          className="h-7 text-xs"
        >
          {p.calculateMode || 'Calcular preço'}
        </Button>
        <Button
          type="button" size="sm" variant={mode === 'direct' ? 'default' : 'outline'}
          onClick={() => onModeChange('direct')}
          className="h-7 text-xs"
        >
          {p.directMode || 'Preço direto'}
        </Button>
      </div>

      {/* Input grid */}
      <div className="grid grid-cols-2 gap-3">
        <div>
          <Label className="text-xs">{p.cost || 'Custo'} (R$)</Label>
          <Input type="number" value={costPrice} readOnly className="bg-muted/30 text-sm" />
        </div>
        <div>
          <Label className="text-xs">{p.profitMargin || 'Margem %'}</Label>
          <Input
            type="number" step="0.01" min="0"
            value={mode === 'calculate' ? profitMargin : resultingMargin}
            readOnly={mode === 'direct'}
            className={mode === 'direct' ? 'bg-muted/30 text-sm' : 'text-sm'}
            onChange={e => onProfitMarginChange(parseFloat(e.target.value) || 0)}
          />
        </div>
        <div>
          <Label className="text-xs">{p.taxRateField || 'Impostos %'}</Label>
          <Input
            type="number" step="0.01" min="0"
            value={taxRate}
            className="text-sm"
            onChange={e => onTaxRateChange(parseFloat(e.target.value) || 0)}
          />
        </div>
        <div>
          <Label className="text-xs">{p.commissionField || 'Comissão %'}</Label>
          <Input
            type="number" step="0.01" min="0"
            value={commissionRate}
            className="text-sm"
            onChange={e => onCommissionRateChange(parseFloat(e.target.value) || 0)}
          />
        </div>
        {mode === 'direct' && (
          <div className="col-span-2">
            <Label className="text-xs">{p.salePrice || 'Preço de Venda'}</Label>
            <Input
              type="number" step="0.01" min="0"
              value={salePrice}
              className="text-sm"
              onChange={e => onSalePriceChange(parseFloat(e.target.value) || 0)}
            />
          </div>
        )}
      </div>

      {/* Breakdown card */}
      <div className="rounded-xl border bg-muted/30 p-4 space-y-2 text-sm">
        <div className="flex justify-between">
          <span className="text-muted-foreground">Preço de custo</span>
          <span>{formatCurrency(costPrice)}</span>
        </div>
        <div className="border-t my-1" />
        <div className="flex justify-between">
          <span className="text-amber-600">Impostos ({taxRate}%)</span>
          <span className="text-amber-600">{formatCurrency(bd.tax_amount)}</span>
        </div>
        <div className="flex justify-between">
          <span className="text-blue-600">Comissão ({commissionRate}%)</span>
          <span className="text-blue-600">{formatCurrency(bd.commission_amount)}</span>
        </div>
        <div className="flex justify-between">
          <span className={bd.profit_amount > 0 ? 'text-emerald-600' : 'text-destructive'}>
            {p.netProfit || 'Lucro líquido'}
          </span>
          <span className={bd.profit_amount > 0 ? 'text-emerald-600 font-medium' : 'text-destructive font-medium'}>
            {formatCurrency(bd.profit_amount)}
          </span>
        </div>
        <div className="border-t my-1" />
        <div className="flex justify-between items-center">
          <span className="font-bold text-base">PREÇO DE VENDA</span>
          <span className="font-bold text-xl">{formatCurrency(mode === 'calculate' ? bd.sale_price : salePrice)}</span>
        </div>
        <div className="flex justify-between">
          <span className="text-xs text-muted-foreground">{p.markupLabel || 'Markup sobre custo'}</span>
          <span className="text-xs text-muted-foreground">{bd.markup}%</span>
        </div>
      </div>

      {/* Warnings */}
      {impossiblePrice && (
        <div className="rounded-lg border border-destructive/30 bg-destructive/10 p-3 text-sm text-destructive">
          ⚠️ {p.impossiblePrice || 'Soma ≥ 100% — preço impossível'}
        </div>
      )}
      {!impossiblePrice && profitMargin > 0 && profitMargin < 10 && mode === 'calculate' && (
        <div className="rounded-lg border border-amber-300/30 bg-amber-50 p-3 text-sm text-amber-700">
          ⚠️ {p.marginWarning || 'Margem muito baixa — verifique se o preço cobre todos os custos'}
        </div>
      )}
      {mode === 'direct' && resultingMargin < 0 && (
        <div className="rounded-lg border border-destructive/30 bg-destructive/10 p-3 text-sm text-destructive">
          ⚠️ {p.belowCost || 'Preço abaixo do custo'}
        </div>
      )}
    </div>
  );
}
