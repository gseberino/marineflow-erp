import { useState, useEffect } from 'react';
import { useI18n } from '@/i18n';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useCreateProduct, useUpdateProduct, type Product } from '@/hooks/use-products';
import { toast } from 'sonner';
import type { TablesInsert } from '@/integrations/supabase/types';

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  product?: Product | null;
}

const empty: TablesInsert<'products'> = {
  product_name: '',
  sku: '',
  category: '',
  brand: '',
  unit: 'pcs',
  cost_price: 0,
  cost_currency: 'BRL',
  sale_price: 0,
  sale_currency: 'BRL',
  stock_quantity: 0,
  minimum_stock: 0,
  location_bin: '',
  barcode: '',
  notes: '',
  active: true,
};

export function ProductFormDialog({ open, onOpenChange, product }: Props) {
  const { t } = useI18n();
  const create = useCreateProduct();
  const update = useUpdateProduct();
  const [form, setForm] = useState<TablesInsert<'products'>>(empty);
  const isEdit = !!product;

  useEffect(() => {
    if (product) {
      setForm({
        product_name: product.product_name,
        sku: product.sku ?? '',
        category: product.category ?? '',
        brand: product.brand ?? '',
        unit: product.unit ?? 'pcs',
        cost_price: product.cost_price ?? 0,
        cost_currency: product.cost_currency ?? 'BRL',
        sale_price: product.sale_price ?? 0,
        sale_currency: product.sale_currency ?? 'BRL',
        stock_quantity: product.stock_quantity ?? 0,
        minimum_stock: product.minimum_stock ?? 0,
        location_bin: product.location_bin ?? '',
        barcode: product.barcode ?? '',
        notes: product.notes ?? '',
        active: product.active,
      });
    } else {
      setForm(empty);
    }
  }, [product, open]);

  const set = (key: string, value: any) => setForm(prev => ({ ...prev, [key]: value }));

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      if (isEdit && product) {
        const { stock_quantity, ...rest } = form;
        await update.mutateAsync({ id: product.id, ...rest });
        toast.success(t.products.updateSuccess);
      } else {
        await create.mutateAsync({ ...form, stock_quantity: 0 });
        toast.success(t.products.createSuccess);
      }
      onOpenChange(false);
    } catch (err: any) {
      toast.error(err.message);
    }
  };

  const isPending = create.isPending || update.isPending;
  const currencies = ['BRL', 'USD', 'EUR'];

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{isEdit ? t.products.editProduct : t.products.newProduct}</DialogTitle>
        </DialogHeader>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <div className="col-span-2">
              <Label>{t.products.productName} *</Label>
              <Input required value={form.product_name} onChange={e => set('product_name', e.target.value)} />
            </div>
            <div>
              <Label>{t.products.sku}</Label>
              <Input value={form.sku ?? ''} onChange={e => set('sku', e.target.value)} />
            </div>
            <div>
              <Label>{t.products.category}</Label>
              <Input value={form.category ?? ''} onChange={e => set('category', e.target.value)} />
            </div>
            <div>
              <Label>{t.products.brand}</Label>
              <Input value={form.brand ?? ''} onChange={e => set('brand', e.target.value)} />
            </div>
            <div>
              <Label>{t.products.unit}</Label>
              <Input value={form.unit ?? 'pcs'} onChange={e => set('unit', e.target.value)} />
            </div>
            <div>
              <Label>{t.products.cost}</Label>
              <Input type="number" step="0.01" min="0" value={form.cost_price ?? 0} onChange={e => set('cost_price', Number(e.target.value))} />
            </div>
            <div>
              <Label>{t.products.costCurrency}</Label>
              <Select value={form.cost_currency ?? 'BRL'} onValueChange={v => set('cost_currency', v)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {currencies.map(c => <SelectItem key={c} value={c}>{c}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label>{t.products.salePrice}</Label>
              <Input type="number" step="0.01" min="0" value={form.sale_price ?? 0} onChange={e => set('sale_price', Number(e.target.value))} />
            </div>
            <div>
              <Label>{t.products.saleCurrency}</Label>
              <Select value={form.sale_currency ?? 'BRL'} onValueChange={v => set('sale_currency', v)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {currencies.map(c => <SelectItem key={c} value={c}>{c}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            {isEdit && (
              <div className="col-span-2">
                <Label>{t.products.stock}: {form.stock_quantity}</Label>
                <p className="text-xs text-muted-foreground">{t.products.stockManagedNote}</p>
              </div>
            )}
            <div>
              <Label>{t.products.minimumStock}</Label>
              <Input type="number" step="0.01" min="0" value={form.minimum_stock ?? 0} onChange={e => set('minimum_stock', Number(e.target.value))} />
            </div>
            <div>
              <Label>{t.products.locationBin}</Label>
              <Input value={form.location_bin ?? ''} onChange={e => set('location_bin', e.target.value)} />
            </div>
            <div className="col-span-2">
              <Label>{t.products.barcode}</Label>
              <Input value={form.barcode ?? ''} onChange={e => set('barcode', e.target.value)} />
            </div>
            <div className="col-span-2">
              <Label>{t.common.notes}</Label>
              <Textarea value={form.notes ?? ''} onChange={e => set('notes', e.target.value)} />
            </div>
            <div className="flex items-center gap-2 col-span-2">
              <Switch checked={form.active ?? true} onCheckedChange={v => set('active', v)} />
              <Label>{t.common.active}</Label>
            </div>
          </div>
          <div className="flex justify-end gap-2 pt-2">
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>{t.common.cancel}</Button>
            <Button type="submit" disabled={isPending}>{t.common.save}</Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}
