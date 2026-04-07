import { useState, useEffect } from 'react';
import { useI18n } from '@/i18n';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Separator } from '@/components/ui/separator';
import { useCreateProduct, useUpdateProduct, type Product } from '@/hooks/use-products';
import { useProductSuppliers, useAddProductSupplier, useUpdateProductSupplier, useRemoveProductSupplier } from '@/hooks/use-product-suppliers';
import { useSuppliers } from '@/hooks/use-suppliers';
import { toast } from 'sonner';
import type { TablesInsert } from '@/integrations/supabase/types';
import { Plus, Trash2, Star } from 'lucide-react';
import { Skeleton } from '@/components/ui/skeleton';

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

const emptySupplierForm = {
  supplier_id: '',
  supplier_sku: '',
  cost_price: 0,
  currency: 'BRL',
  lead_time_days: 0,
  minimum_order_qty: 1,
  is_preferred: false,
  notes: '',
};

export function ProductFormDialog({ open, onOpenChange, product }: Props) {
  const { t, formatCurrency } = useI18n();
  const create = useCreateProduct();
  const update = useUpdateProduct();
  const [form, setForm] = useState<TablesInsert<'products'>>(empty);
  const isEdit = !!product;

  // Supplier section
  const { data: productSuppliers, isLoading: psLoading } = useProductSuppliers(product?.id);
  const { data: allSuppliers } = useSuppliers();
  const addPS = useAddProductSupplier();
  const updatePS = useUpdateProductSupplier();
  const removePS = useRemoveProductSupplier();
  const [showAddSupplier, setShowAddSupplier] = useState(false);
  const [supplierForm, setSupplierForm] = useState(emptySupplierForm);

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
    setShowAddSupplier(false);
    setSupplierForm(emptySupplierForm);
  }, [product, open]);

  const set = (key: string, value: any) => setForm(prev => ({ ...prev, [key]: value }));
  const setSF = (key: string, value: any) => setSupplierForm(prev => ({ ...prev, [key]: value }));

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

  const handleAddSupplier = async () => {
    if (!product || !supplierForm.supplier_id) return;
    try {
      await addPS.mutateAsync({
        product_id: product.id,
        supplier_id: supplierForm.supplier_id,
        supplier_sku: supplierForm.supplier_sku || null,
        cost_price: supplierForm.cost_price || null,
        currency: supplierForm.currency,
        lead_time_days: supplierForm.lead_time_days || null,
        minimum_order_qty: supplierForm.minimum_order_qty,
        is_preferred: supplierForm.is_preferred,
        notes: supplierForm.notes || null,
      });
      setShowAddSupplier(false);
      setSupplierForm(emptySupplierForm);
    } catch (err: any) {
      toast.error(err.message);
    }
  };

  const handleTogglePreferred = async (psId: string, currentVal: boolean) => {
    if (!product) return;
    // If setting to preferred, unset others first
    if (!currentVal && productSuppliers) {
      for (const ps of productSuppliers) {
        if (ps.is_preferred && ps.id !== psId) {
          await updatePS.mutateAsync({ id: ps.id, product_id: product.id, is_preferred: false });
        }
      }
    }
    await updatePS.mutateAsync({ id: psId, product_id: product.id, is_preferred: !currentVal });
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

          {/* Supplier section — edit mode only */}
          {isEdit && product && (
            <>
              <Separator />
              <div>
                <div className="flex items-center justify-between mb-3">
                  <h4 className="text-sm font-semibold">{t.suppliers.title}</h4>
                  <Button type="button" variant="outline" size="sm" onClick={() => setShowAddSupplier(!showAddSupplier)}>
                    <Plus className="h-4 w-4 mr-1" /> {t.suppliers.addSupplier}
                  </Button>
                </div>

                {psLoading ? (
                  <Skeleton className="h-16" />
                ) : (productSuppliers ?? []).length === 0 && !showAddSupplier ? (
                  <p className="text-sm text-muted-foreground">{t.suppliers.noSuppliersLinked}</p>
                ) : (
                  <div className="space-y-2">
                    {(productSuppliers ?? []).map((ps: any) => (
                      <div key={ps.id} className="flex items-center justify-between p-3 rounded-lg border bg-muted/30 text-sm">
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-2">
                            <span className="font-medium">{ps.suppliers?.supplier_name}</span>
                            {ps.is_preferred && <Star className="h-3 w-3 text-amber-500 fill-amber-500" />}
                          </div>
                          <div className="text-xs text-muted-foreground flex flex-wrap gap-x-3 mt-0.5">
                            {ps.supplier_sku && <span>SKU: {ps.supplier_sku}</span>}
                            {ps.cost_price != null && <span>{formatCurrency(ps.cost_price, ps.currency ?? 'BRL')}</span>}
                            {ps.lead_time_days != null && <span>{ps.lead_time_days} {t.suppliers.leadTimeDays}</span>}
                          </div>
                        </div>
                        <div className="flex items-center gap-1 shrink-0">
                          <Button
                            type="button"
                            variant="ghost"
                            size="sm"
                            onClick={() => handleTogglePreferred(ps.id, ps.is_preferred ?? false)}
                            title={t.suppliers.preferred}
                          >
                            <Star className={`h-4 w-4 ${ps.is_preferred ? 'text-amber-500 fill-amber-500' : 'text-muted-foreground'}`} />
                          </Button>
                          <Button
                            type="button"
                            variant="ghost"
                            size="sm"
                            onClick={() => removePS.mutate({ id: ps.id, product_id: product.id })}
                          >
                            <Trash2 className="h-4 w-4 text-destructive" />
                          </Button>
                        </div>
                      </div>
                    ))}
                  </div>
                )}

                {showAddSupplier && (
                  <div className="mt-3 p-3 rounded-lg border space-y-3">
                    <div>
                      <Label>{t.suppliers.selectSupplier} *</Label>
                      <Select value={supplierForm.supplier_id} onValueChange={v => setSF('supplier_id', v)}>
                        <SelectTrigger><SelectValue placeholder={t.suppliers.selectSupplier} /></SelectTrigger>
                        <SelectContent>
                          {(allSuppliers ?? []).filter(s => s.active).map(s => (
                            <SelectItem key={s.id} value={s.id}>{s.supplier_name}</SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                    <div className="grid grid-cols-2 gap-3">
                      <div>
                        <Label>{t.suppliers.supplierSku}</Label>
                        <Input value={supplierForm.supplier_sku} onChange={e => setSF('supplier_sku', e.target.value)} />
                      </div>
                      <div>
                        <Label>{t.products.cost}</Label>
                        <Input type="number" step="0.01" value={supplierForm.cost_price} onChange={e => setSF('cost_price', Number(e.target.value))} />
                      </div>
                      <div>
                        <Label>{t.products.costCurrency}</Label>
                        <Select value={supplierForm.currency} onValueChange={v => setSF('currency', v)}>
                          <SelectTrigger><SelectValue /></SelectTrigger>
                          <SelectContent>
                            {currencies.map(c => <SelectItem key={c} value={c}>{c}</SelectItem>)}
                          </SelectContent>
                        </Select>
                      </div>
                      <div>
                        <Label>{t.suppliers.leadTimeDays}</Label>
                        <Input type="number" value={supplierForm.lead_time_days} onChange={e => setSF('lead_time_days', Number(e.target.value))} />
                      </div>
                      <div>
                        <Label>{t.suppliers.minimumQty}</Label>
                        <Input type="number" step="0.001" value={supplierForm.minimum_order_qty} onChange={e => setSF('minimum_order_qty', Number(e.target.value))} />
                      </div>
                      <div className="flex items-center gap-2 pt-5">
                        <Switch checked={supplierForm.is_preferred} onCheckedChange={v => setSF('is_preferred', v)} />
                        <Label>{t.suppliers.preferred}</Label>
                      </div>
                    </div>
                    <div className="flex justify-end gap-2">
                      <Button type="button" variant="ghost" size="sm" onClick={() => setShowAddSupplier(false)}>{t.common.cancel}</Button>
                      <Button type="button" size="sm" onClick={handleAddSupplier} disabled={!supplierForm.supplier_id || addPS.isPending}>{t.common.save}</Button>
                    </div>
                  </div>
                )}
              </div>
            </>
          )}

          <div className="flex justify-end gap-2 pt-2">
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>{t.common.cancel}</Button>
            <Button type="submit" disabled={isPending}>{t.common.save}</Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}
