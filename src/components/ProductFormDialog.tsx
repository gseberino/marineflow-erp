import { useState, useEffect, useMemo } from 'react';
import { useI18n } from '@/i18n';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Separator } from '@/components/ui/separator';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';
import { useCreateProduct, useUpdateProduct, type Product } from '@/hooks/use-products';
import { useProductSuppliers, useAddProductSupplier, useUpdateProductSupplier, useRemoveProductSupplier } from '@/hooks/use-product-suppliers';
import { useSuppliers } from '@/hooks/use-suppliers';
import { useProductCategories } from '@/hooks/use-product-categories';
import { useAppSettings } from '@/hooks/use-app-settings';
import { toast } from 'sonner';
import type { TablesInsert } from '@/integrations/supabase/types';
import { Plus, Trash2, Star, ChevronDown, ExternalLink, Info, X, Upload, Package } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { Skeleton } from '@/components/ui/skeleton';
import { PriceCalculator } from '@/components/PriceCalculator';
import { PriceCalculatorDialog } from '@/components/PriceCalculatorDialog';
import { CSOSN_OPTIONS, FISCAL_ORIGIN_OPTIONS } from '@/lib/price-calculator';
import { MoneyInput } from '@/components/MoneyInput';

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
  image_url: null,
  ncm: '',
  csosn: '400',
  fiscal_origin: 0,
  icms_rate: 0,
  ipi_rate: 0,
  pis_rate: 0,
  cofins_rate: 0,
  commission_rate: 0,
  profit_margin: 0,
  use_global_fiscal: true,
  product_category_id: null,
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

  const [priceMode, setPriceMode] = useState<'calculate' | 'direct'>('calculate');
  const [useGlobal, setUseGlobal] = useState(true);
  const [fiscalOpen, setFiscalOpen] = useState(false);
  const [priceOpen, setPriceOpen] = useState(true);

  // App settings
  const { data: settings } = useAppSettings();

  // Product categories
  const { data: productCategories } = useProductCategories();

  // Supplier section
  const { data: productSuppliers, isLoading: psLoading } = useProductSuppliers(product?.id);
  const { data: allSuppliers } = useSuppliers();
  const addPS = useAddProductSupplier();
  const updatePS = useUpdateProductSupplier();
  const removePS = useRemoveProductSupplier();
  const [showAddSupplier, setShowAddSupplier] = useState(false);
  const [supplierForm, setSupplierForm] = useState(emptySupplierForm);

  // Initialize form from product or defaults
  useEffect(() => {
    if (product) {
      const p = product as any;
      setForm({
        product_name: p.product_name,
        sku: p.sku ?? '',
        category: p.category ?? '',
        brand: p.brand ?? '',
        unit: p.unit ?? 'pcs',
        cost_price: p.cost_price ?? 0,
        cost_currency: p.cost_currency ?? 'BRL',
        sale_price: p.sale_price ?? 0,
        sale_currency: p.sale_currency ?? 'BRL',
        stock_quantity: p.stock_quantity ?? 0,
        minimum_stock: p.minimum_stock ?? 0,
        location_bin: p.location_bin ?? '',
        barcode: p.barcode ?? '',
        notes: p.notes ?? '',
        active: p.active,
        image_url: p.image_url ?? null,
        ncm: p.ncm ?? '',
        csosn: p.csosn ?? '400',
        fiscal_origin: p.fiscal_origin ?? 0,
        icms_rate: p.icms_rate ?? 0,
        ipi_rate: p.ipi_rate ?? 0,
        pis_rate: p.pis_rate ?? 0,
        cofins_rate: p.cofins_rate ?? 0,
        commission_rate: p.commission_rate ?? 0,
        profit_margin: p.profit_margin ?? 0,
        use_global_fiscal: p.use_global_fiscal !== false,
        product_category_id: p.product_category_id ?? null,
      });
      setUseGlobal(p.use_global_fiscal !== false);
    } else {
      setForm(empty);
      setUseGlobal(true);
    }
    setShowAddSupplier(false);
    setSupplierForm(emptySupplierForm);
    setPriceMode('calculate');
  }, [product, open]);

  // Apply global defaults when settings load for new products
  useEffect(() => {
    if (!product && settings) {
      const s = settings as any;
      setForm(prev => ({
        ...prev,
        profit_margin: prev.profit_margin || Number(s.default_profit_margin) || 30,
        icms_rate: prev.icms_rate || Number(s.simples_aliquota) || 6,
        commission_rate: prev.commission_rate || Number(s.default_commission_rate) || 0,
        csosn: prev.csosn || s.default_csosn || '400',
        fiscal_origin: prev.fiscal_origin ?? s.default_fiscal_origin ?? 0,
      }));
    }
  }, [settings, product]);

  const set = (key: string, value: any) => setForm(prev => ({ ...prev, [key]: value }));
  const setSF = (key: string, value: any) => setSupplierForm(prev => ({ ...prev, [key]: value }));

  // Image upload state
  const [uploading, setUploading] = useState(false);
  const [calcOpen, setCalcOpen] = useState(false);
  const fileInputRef = (typeof window !== 'undefined') ? null : null;

  const handleImageUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = ''; // permite re-selecionar o mesmo arquivo depois
    if (!file) return;

    const allowed = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp'];
    if (!allowed.includes(file.type)) {
      toast.error('Formato inválido. Use JPG, PNG ou WEBP.');
      return;
    }
    if (file.size > 2 * 1024 * 1024) {
      toast.error('Arquivo muito grande. Máximo 2MB.');
      return;
    }

    setUploading(true);
    try {
      const ext = (file.name.split('.').pop() || 'jpg').toLowerCase();
      const productFolder = product?.id || 'new';
      const uuid = (crypto as any).randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
      const path = `products/${productFolder}/${uuid}.${ext}`;

      const { error: uploadError } = await supabase.storage
        .from('product-images')
        .upload(path, file, { contentType: file.type, upsert: false });
      if (uploadError) throw uploadError;

      const { data: pub } = supabase.storage.from('product-images').getPublicUrl(path);
      set('image_url', pub.publicUrl);
      toast.success('Imagem enviada.');
    } catch (err: any) {
      console.error('Upload error:', err);
      toast.error(err?.message || 'Erro ao enviar imagem.');
    } finally {
      setUploading(false);
    }
  };

  const handleImageRemove = async () => {
    const url: string | null | undefined = (form as any).image_url;
    if (!url) return;
    try {
      const marker = '/product-images/';
      const idx = url.indexOf(marker);
      if (idx >= 0) {
        const path = url.substring(idx + marker.length);
        await supabase.storage.from('product-images').remove([path]);
      }
    } catch (err) {
      console.error('Remove error:', err);
    } finally {
      set('image_url', null);
    }
  };

  // Category change handler
  const handleCategoryChange = (categoryId: string) => {
    const cat = productCategories?.find(c => c.id === categoryId);
    if (!cat) return;
    setForm(prev => ({
      ...prev,
      product_category_id: categoryId,
      category: cat.name,
      profit_margin: cat.default_profit_margin ?? prev.profit_margin,
      commission_rate: cat.default_commission_rate ?? prev.commission_rate,
      csosn: cat.default_csosn || prev.csosn,
      fiscal_origin: cat.default_fiscal_origin ?? prev.fiscal_origin,
      icms_rate: cat.default_icms_rate ?? prev.icms_rate,
      ipi_rate: cat.default_ipi_rate ?? prev.ipi_rate,
      pis_rate: cat.default_pis_rate ?? prev.pis_rate,
      cofins_rate: cat.default_cofins_rate ?? prev.cofins_rate,
    }));
  };

  // Fiscal hierarchy: product override → category → global
  const selectedCategory = useMemo(() => {
    if (!form.product_category_id || !productCategories) return null;
    return productCategories.find(c => c.id === form.product_category_id) || null;
  }, [form.product_category_id, productCategories]);

  const s = settings as any;

  const effectiveNCM = !useGlobal ? ((form as any).ncm || '') : (selectedCategory?.default_ncm || '');
  const effectiveCSOSN = !useGlobal ? ((form as any).csosn || '400') : (selectedCategory?.default_csosn || s?.default_csosn || '400');
  const effectiveOrigin = !useGlobal ? ((form as any).fiscal_origin ?? 0) : (selectedCategory?.default_fiscal_origin ?? s?.default_fiscal_origin ?? 0);
  const effectiveICMS = !useGlobal ? ((form as any).icms_rate ?? 0) : (selectedCategory?.default_icms_rate ?? s?.default_icms_rate ?? 0);

  const fiscalSource = !useGlobal
    ? 'Personalizado para este produto'
    : selectedCategory
      ? `Categoria: ${selectedCategory.name}`
      : 'Global (Configurações)';

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
      const msg = err?.message || err?.details
        || 'Erro ao salvar produto.';
      toast.error(msg);
      console.error('ProductFormDialog error:', err);
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
      const msg = err?.message || err?.details
        || 'Erro ao salvar produto.';
      toast.error(msg);
      console.error('ProductFormDialog error:', err);
    }
  };

  const handleTogglePreferred = async (psId: string, currentVal: boolean) => {
    if (!product) return;
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
  const p = t.products as any;

  return (
    <>
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

            {/* Foto do produto */}
            <div className="col-span-2">
              <Label>Foto do produto</Label>
              <div className="mt-1 flex items-center gap-3">
                {(form as any).image_url ? (
                  <div className="relative h-20 w-20 shrink-0 overflow-hidden rounded-md border bg-muted">
                    <img
                      src={(form as any).image_url}
                      alt={form.product_name || 'Produto'}
                      className="h-full w-full object-cover"
                    />
                    <button
                      type="button"
                      onClick={handleImageRemove}
                      className="absolute -right-1 -top-1 flex h-5 w-5 items-center justify-center rounded-full bg-destructive text-destructive-foreground shadow hover:opacity-90"
                      aria-label="Remover imagem"
                    >
                      <X className="h-3 w-3" />
                    </button>
                  </div>
                ) : (
                  <div className="flex h-20 w-20 shrink-0 items-center justify-center rounded-md border border-dashed bg-muted/40 text-muted-foreground">
                    <Package className="h-7 w-7" />
                  </div>
                )}
                <div className="flex flex-col gap-1">
                  <input
                    id="product-image-upload"
                    type="file"
                    accept="image/jpeg,image/jpg,image/png,image/webp"
                    className="hidden"
                    onChange={handleImageUpload}
                    disabled={uploading}
                  />
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    className="gap-1"
                    disabled={uploading}
                    onClick={() => document.getElementById('product-image-upload')?.click()}
                  >
                    <Upload className="h-3.5 w-3.5" />
                    {uploading ? 'Enviando...' : ((form as any).image_url ? 'Trocar foto' : 'Adicionar foto')}
                  </Button>
                  <p className="text-[10px] text-muted-foreground">JPG, PNG ou WEBP, máx 2MB.</p>
                </div>
              </div>
            </div>
            <div>
              <Label>{t.products.sku}</Label>
              <Input value={form.sku ?? ''} onChange={e => set('sku', e.target.value)} />
            </div>

            {/* Category Select */}
            <div>
              <div className="flex items-center justify-between">
                <Label>{p.productCategoryId || t.products.category}</Label>
                <a
                  href="/settings?tab=product-categories"
                  target="_blank"
                  className="text-[10px] text-primary hover:underline flex items-center gap-0.5"
                >
                  {p.manageCategories || 'Gerenciar categorias'} <ExternalLink className="h-2.5 w-2.5" />
                </a>
              </div>
              <Select
                value={form.product_category_id ?? ''}
                onValueChange={handleCategoryChange}
              >
                <SelectTrigger><SelectValue placeholder={t.products.category} /></SelectTrigger>
                <SelectContent>
                  {(productCategories || []).map(cat => (
                    <SelectItem key={cat.id} value={cat.id}>{cat.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {selectedCategory && (
                <p className="text-[10px] text-muted-foreground mt-1">
                  Margem padrão: {selectedCategory.default_profit_margin}%
                  {selectedCategory.is_commissionable
                    ? ` · Comissão: ${selectedCategory.default_commission_rate}%`
                    : ' · Não comissionável'}
                </p>
              )}
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
              <MoneyInput value={form.cost_price ?? 0} onValueChange={v => set('cost_price', v)} />
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
              <div className="flex gap-2 items-center">
                <MoneyInput value={form.sale_price ?? 0} onValueChange={v => set('sale_price', v)} className="flex-1" />
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={() => setCalcOpen(true)}
                  title="Formador de preço"
                >
                  💰
                </Button>
              </div>
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
              <Label>{t.common.notes}</Label>
              <Textarea value={form.notes ?? ''} onChange={e => set('notes', e.target.value)} />
            </div>
            <div className="flex items-center gap-2 col-span-2">
              <Switch checked={form.active ?? true} onCheckedChange={v => set('active', v)} />
              <Label>{t.common.active}</Label>
            </div>
          </div>

          {/* Price Calculator Section */}
          <Collapsible open={priceOpen} onOpenChange={setPriceOpen}>
            <CollapsibleTrigger className="flex items-center justify-between w-full py-2 text-sm font-semibold hover:text-primary transition-colors">
              {p.priceCalculator || 'Formação de Preço'}
              <ChevronDown className={`h-4 w-4 transition-transform ${priceOpen ? 'rotate-180' : ''}`} />
            </CollapsibleTrigger>
            <CollapsibleContent className="space-y-3">
              {selectedCategory && !selectedCategory.is_commissionable && (
                <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-xs text-amber-800 flex items-start gap-2">
                  <span>⚠️</span>
                  <span>
                    A categoria <strong>{selectedCategory.name}</strong> não permite comissionamento. O campo comissão será ignorado no cálculo do preço.
                  </span>
                </div>
              )}
               <PriceCalculator
                costPrice={Number(form.cost_price) || 0}
                salePrice={Number(form.sale_price) || 0}
                profitMargin={Number((form as any).profit_margin) || 0}
                taxRate={Number((form as any).icms_rate) || 0}
                commissionRate={Number((form as any).commission_rate) || 0}
                mode={priceMode}
                onModeChange={setPriceMode}
                onSalePriceChange={v => set('sale_price', v)}
                onProfitMarginChange={v => set('profit_margin', v)}
                onTaxRateChange={v => set('icms_rate', v)}
                onCommissionRateChange={v => set('commission_rate', v)}
                isCommissionable={selectedCategory ? (selectedCategory.is_commissionable ?? true) : true}
              />
            </CollapsibleContent>
          </Collapsible>

          {/* Fiscal Data Section */}
          <Collapsible open={fiscalOpen} onOpenChange={setFiscalOpen}>
            <CollapsibleTrigger className="flex items-center justify-between w-full py-2 text-sm font-semibold hover:text-primary transition-colors">
              {p.fiscalData || 'Dados Fiscais'}
              <ChevronDown className={`h-4 w-4 transition-transform ${fiscalOpen ? 'rotate-180' : ''}`} />
            </CollapsibleTrigger>
            <CollapsibleContent className="space-y-4 pt-2">

              {/* Effective fiscal summary */}
              <div className="rounded-lg border bg-muted/30 p-3 space-y-2">
                <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide">
                  {p.fiscalEffective || 'Configuração fiscal efetiva'}
                </p>
                <div className="grid grid-cols-4 gap-2 text-sm">
                  <div>
                    <span className="text-[10px] text-muted-foreground block">NCM</span>
                    <span className="font-medium">{effectiveNCM || '—'}</span>
                  </div>
                  <div>
                    <span className="text-[10px] text-muted-foreground block">CSOSN</span>
                    <span className="font-medium">{effectiveCSOSN}</span>
                  </div>
                  <div>
                    <span className="text-[10px] text-muted-foreground block">Origem</span>
                    <span className="font-medium">{effectiveOrigin}</span>
                  </div>
                  <div>
                    <span className="text-[10px] text-muted-foreground block">ICMS</span>
                    <span className="font-medium">{effectiveICMS}%</span>
                  </div>
                </div>
                <p className="text-[10px] text-muted-foreground">
                  {p.fiscalSource || 'Fonte'}: {fiscalSource}
                </p>
              </div>

              {/* Override toggle */}
              <label className="flex items-center gap-2 text-sm cursor-pointer">
                <input
                  type="checkbox"
                  checked={!useGlobal}
                  onChange={e => {
                    const custom = e.target.checked;
                    setUseGlobal(!custom);
                    set('use_global_fiscal', !custom);
                  }}
                  className="rounded border-input"
                />
                <div>
                  <span className="font-medium">{p.customizeFiscal || 'Personalizar dados fiscais para este produto'}</span>
                  <p className="text-[10px] text-muted-foreground">
                    {p.customizeFiscalHelper || 'Sobrescreve os padrões globais e de categoria'}
                  </p>
                </div>
              </label>

              {/* Custom fiscal fields */}
              {!useGlobal && (
                <div className="space-y-3 border-l-2 border-primary/20 pl-3">
                  <p className="text-xs font-semibold text-muted-foreground uppercase">
                    {p.fiscalClassification || 'Classificação Fiscal'}
                  </p>
                  <div>
                    <Label>NCM (8 dígitos)</Label>
                    <Input
                      value={(form as any).ncm ?? ''}
                      onChange={e => set('ncm', e.target.value.replace(/\D/g, '').slice(0, 8))}
                      placeholder="00000000"
                    />
                    <p className="text-[10px] text-muted-foreground mt-1">
                      {p.ncmHelper2 || 'Obrigatório na NF-e. Consulte a tabela NCM da Receita Federal.'}
                    </p>
                  </div>
                  <div>
                    <Label>CSOSN</Label>
                    <Select value={(form as any).csosn ?? '400'} onValueChange={v => set('csosn', v)}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>
                        {CSOSN_OPTIONS.map(o => <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>)}
                      </SelectContent>
                    </Select>
                    <p className="text-[10px] text-muted-foreground mt-1">
                      {p.csosnHelper || 'Situação tributária do ICMS. Mais comum para revenda: 400.'}
                    </p>
                  </div>
                  <div>
                    <Label>{p.fiscalOrigin || 'Origem'}</Label>
                    <Select value={String((form as any).fiscal_origin ?? 0)} onValueChange={v => set('fiscal_origin', Number(v))}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>
                        {FISCAL_ORIGIN_OPTIONS.map(o => <SelectItem key={o.value} value={String(o.value)}>{o.label}</SelectItem>)}
                      </SelectContent>
                    </Select>
                    <p className="text-[10px] text-muted-foreground mt-1">
                      {p.originHelper || '0 — Nacional. 1 ou 2 — Estrangeira (importado).'}
                    </p>
                  </div>

                  <div className="flex items-center gap-1 mt-2">
                    <p className="text-xs font-semibold text-muted-foreground uppercase">
                      {p.fiscalRates || 'Alíquotas'}
                    </p>
                    <div className="group relative">
                      <Info className="h-3 w-3 text-muted-foreground" />
                      <div className="absolute bottom-full left-0 mb-1 hidden group-hover:block w-56 p-2 rounded bg-popover border text-[10px] text-muted-foreground shadow-lg z-50">
                        {p.simplesRatesInfo || 'No Simples Nacional, alíquotas são informativas para a NF-e'}
                      </div>
                    </div>
                  </div>
                  <div className="grid grid-cols-2 gap-3">
                    <div>
                      <Label className="text-xs">ICMS %</Label>
                      <Input type="number" step="0.0001" value={(form as any).icms_rate ?? 0} onChange={e => set('icms_rate', parseFloat(e.target.value) || 0)} />
                    </div>
                    <div>
                      <Label className="text-xs">IPI %</Label>
                      <Input type="number" step="0.0001" value={(form as any).ipi_rate ?? 0} onChange={e => set('ipi_rate', parseFloat(e.target.value) || 0)} />
                      <p className="text-[10px] text-muted-foreground">{p.ipiHelper || 'Geralmente 0% no Simples'}</p>
                    </div>
                    <div>
                      <Label className="text-xs">PIS %</Label>
                      <Input type="number" step="0.0001" value={(form as any).pis_rate ?? 0} onChange={e => set('pis_rate', parseFloat(e.target.value) || 0)} />
                      <p className="text-[10px] text-muted-foreground">{p.pisHelper || 'Incluso no DAS'}</p>
                    </div>
                    <div>
                      <Label className="text-xs">COFINS %</Label>
                      <Input type="number" step="0.0001" value={(form as any).cofins_rate ?? 0} onChange={e => set('cofins_rate', parseFloat(e.target.value) || 0)} />
                      <p className="text-[10px] text-muted-foreground">{p.cofinsHelper || 'Incluso no DAS'}</p>
                    </div>
                  </div>
                </div>
              )}

              <Separator />

              {/* Identification */}
              <p className="text-xs font-semibold text-muted-foreground uppercase">
                {p.fiscalIdentification || 'Identificação'}
              </p>
              <div>
                <Label>{p.barcode || 'Código de Barras (EAN-13 / GTIN)'}</Label>
                <Input value={form.barcode ?? ''} onChange={e => set('barcode', e.target.value)} />
              </div>


            </CollapsibleContent>
          </Collapsible>

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
                          <Button type="button" variant="ghost" size="sm"
                            onClick={() => handleTogglePreferred(ps.id, ps.is_preferred ?? false)} title={t.suppliers.preferred}>
                            <Star className={`h-4 w-4 ${ps.is_preferred ? 'text-amber-500 fill-amber-500' : 'text-muted-foreground'}`} />
                          </Button>
                          <Button type="button" variant="ghost" size="sm"
                            onClick={() => removePS.mutate({ id: ps.id, product_id: product.id })}>
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
    <PriceCalculatorDialog
      open={calcOpen}
      onOpenChange={setCalcOpen}
      initialCost={Number(form.cost_price) || 0}
      initialPrice={Number(form.sale_price) || 0}
      onConfirm={(price) => set('sale_price', price)}
    />
    </>
  );
}
