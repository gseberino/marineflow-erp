import { useState, useEffect, useCallback } from 'react';
import { useI18n } from '@/i18n';
import { useProducts } from '@/hooks/use-products';
import { useServices } from '@/hooks/use-services';
import { supabase } from '@/integrations/supabase/client';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Checkbox } from '@/components/ui/checkbox';
import { Switch } from '@/components/ui/switch';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Search, Save, Loader2, X } from 'lucide-react';
import { toast } from 'sonner';

// 03/10/2026: o saldo do produto só muda por movimento (ledger, fase E — o banco recusa a escrita
// direta). A edição em lote gravava stock_quantity direto: salvar falhava no meio, com parte salva.
// O estoque passa por ajustar_estoque (movimento com motivo); o resto, pela atualização normal. No
// celular, cada item vira um cartão — nada de rolagem lateral (Princípio 0 da interface).

interface BulkEditorProps {
  entityType: 'products' | 'services';
  open: boolean;
  onOpenChange: (v: boolean) => void;
}

function useTelaEstreita(largura: number): boolean {
  const consulta = `(max-width: ${largura - 1}px)`;
  const [estreita, setEstreita] = useState(() => typeof window !== 'undefined' && window.matchMedia?.(consulta).matches === true);
  useEffect(() => {
    const mql = window.matchMedia?.(consulta);
    if (!mql) return;
    const mudou = () => setEstreita(mql.matches);
    mql.addEventListener('change', mudou);
    mudou();
    return () => mql.removeEventListener('change', mudou);
  }, [consulta]);
  return estreita;
}

export function BulkEditor({ entityType, open, onOpenChange }: BulkEditorProps) {
  const { t, formatCurrency } = useI18n();
  // A tabela precisa de ~1.050 px (9 colunas editáveis): abaixo disso, cartões — no celular e no
  // tablet. O diálogo vai até 1.152 px (max-w-6xl).
  const celular = useTelaEstreita(1100);
  const { data: products, refetch: refetchProducts } = useProducts();
  const { data: services, refetch: refetchServices } = useServices();

  const [data, setData] = useState<any[]>([]);
  const [changes, setChanges] = useState<Record<string, Record<string, any>>>({});
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [search, setSearch] = useState('');
  const [filterActive, setFilterActive] = useState<'all' | 'active' | 'inactive'>('all');
  const [bulkAction, setBulkAction] = useState<null | 'category' | 'price'>(null);
  const [bulkCategory, setBulkCategory] = useState('');
  const [priceMode, setPriceMode] = useState<'increase' | 'decrease' | 'fixed'>('increase');
  const [priceValue, setPriceValue] = useState(0);
  const [priceSale, setPriceSale] = useState(true);
  const [priceCost, setPriceCost] = useState(false);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (open) {
      if (entityType === 'products') setData(products ?? []);
      else setData(services ?? []);
      setChanges({});
      setSelected(new Set());
      setBulkAction(null);
    }
  }, [open, entityType, products, services]);

  const getVal = useCallback((item: any, field: string) => {
    return changes[item.id]?.[field] ?? item[field];
  }, [changes]);

  const setVal = useCallback((id: string, field: string, value: any) => {
    setChanges(prev => ({
      ...prev,
      [id]: { ...prev[id], [field]: value },
    }));
  }, []);

  const filtered = data.filter(item => {
    const name = entityType === 'products' ? getVal(item, 'name') : getVal(item, 'name');
    if (search && !String(name).toLowerCase().includes(search.toLowerCase())) return false;
    const active = getVal(item, 'active');
    if (filterActive === 'active' && !active) return false;
    if (filterActive === 'inactive' && active) return false;
    return true;
  }).slice(0, 200);

  const toggleAll = () => {
    if (selected.size === filtered.length) setSelected(new Set());
    else setSelected(new Set(filtered.map(i => i.id)));
  };

  const applyBulkCategory = () => {
    selected.forEach(id => setVal(id, 'category', bulkCategory));
    setBulkAction(null);
  };

  const applyBulkPrice = () => {
    selected.forEach(id => {
      const item = data.find(d => d.id === id);
      if (!item) return;
      if (entityType === 'products') {
        if (priceSale) {
          const current = getVal(item, 'sale_price') || 0;
          const newPrice = priceMode === 'fixed' ? priceValue :
            priceMode === 'increase' ? current * (1 + priceValue / 100) :
            current * (1 - priceValue / 100);
          setVal(id, 'sale_price', Math.round(newPrice * 100) / 100);
        }
        if (priceCost) {
          const current = getVal(item, 'cost_price') || 0;
          const newPrice = priceMode === 'fixed' ? priceValue :
            priceMode === 'increase' ? current * (1 + priceValue / 100) :
            current * (1 - priceValue / 100);
          setVal(id, 'cost_price', Math.round(newPrice * 100) / 100);
        }
      } else {
        const current = getVal(item, 'default_price') || 0;
        const newPrice = priceMode === 'fixed' ? priceValue :
          priceMode === 'increase' ? current * (1 + priceValue / 100) :
          current * (1 - priceValue / 100);
        setVal(id, 'default_price', Math.round(newPrice * 100) / 100);
      }
    });
    setBulkAction(null);
  };

  const toggleActive = (active: boolean) => {
    selected.forEach(id => setVal(id, 'active', active));
  };

  const changedCount = Object.keys(changes).length;

  const handleSave = async () => {
    setSaving(true);
    const table = entityType === 'products' ? 'products' : 'services';
    const falharam: Record<string, Record<string, any>> = {};
    let primeiroErro = '';
    try {
      for (const [id, vals] of Object.entries(changes)) {
        try {
          const { stock_quantity: novoSaldo, ...resto } = vals as Record<string, any>;
          if (Object.keys(resto).length > 0) {
            const { error } = await supabase.from(table).update(resto as any).eq('id', id);
            if (error) throw error;
          }
          if (entityType === 'products' && novoSaldo !== undefined) {
            const { error } = await supabase.rpc('ajustar_estoque' as never, {
              p_produto: id,
              p_nova_quantidade: Number(novoSaldo) || 0,
              p_motivo: 'Edição em lote',
            } as never);
            if (error) throw error;
          }
        } catch (err: any) {
          falharam[id] = vals;
          if (!primeiroErro) {
            const nome = data.find((d) => d.id === id)?.name ?? id;
            primeiroErro = `${nome}: ${err?.message ?? 'erro'}`;
          }
        }
      }
      const n = Object.keys(falharam).length;
      if (n === 0) toast.success(t.imports.changesSaved);
      else toast.error(`${n} item(ns) não salvaram e continuam marcados. ${primeiroErro}`);
      // O que salvou sai da lista de mudanças; o que falhou fica para tentar de novo.
      setChanges(falharam);
      if (entityType === 'products') refetchProducts();
      else refetchServices();
    } finally {
      setSaving(false);
    }
  };

  // Função, não componente: um componente declarado aqui dentro é um tipo novo a cada render, e o
  // React desmontava o campo a cada tecla — perdia o foco depois do primeiro caractere (03/10/2026).
  const EditCell = ({ id, field, type = 'text', item }: { id: string; field: string; type?: string; item: any }) => {
    const val = getVal(item, field);
    const isChanged = changes[id]?.[field] !== undefined;
    return (
      <Input
        className={`h-7 text-xs ${isChanged ? 'bg-warning/10' : ''}`}
        type={type}
        value={val ?? ''}
        onChange={e => setVal(id, field, type === 'number' ? parseFloat(e.target.value) || 0 : e.target.value)}
      />
    );
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-6xl max-h-[90vh] overflow-hidden flex flex-col">
        <DialogHeader>
          <DialogTitle>{t.imports.bulkEdit} — {entityType === 'products' ? t.nav.products : t.nav.services}</DialogTitle>
        </DialogHeader>

        {/* Toolbar */}
        <div className="flex flex-wrap items-center gap-2 pb-2 border-b">
          <div className="relative flex-1 min-w-[200px]">
            <Search className="absolute left-2 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-muted-foreground" />
            <Input className="h-8 pl-8 text-xs" placeholder={t.common.search} value={search} onChange={e => setSearch(e.target.value)} />
          </div>
          <div className="flex gap-1">
            {(['all', 'active', 'inactive'] as const).map(f => (
              <Button key={f} size="sm" variant={filterActive === f ? 'default' : 'outline'} className="h-7 text-xs"
                onClick={() => setFilterActive(f)}>
                {f === 'all' ? t.financial.sourceAll : f === 'active' ? t.common.active : t.common.inactive}
              </Button>
            ))}
          </div>
          <span className="text-xs text-muted-foreground">{filtered.length} registros</span>
        </div>

        {/* Bulk actions */}
        {selected.size > 0 && (
          <div className="flex flex-wrap items-center gap-2 py-2 px-3 bg-accent/5 rounded-lg">
            <span className="text-xs font-medium">{t.imports.bulkSelected.replace('{count}', String(selected.size))}</span>
            <Button size="sm" variant="outline" className="h-7 text-xs" onClick={() => setBulkAction('category')}>{t.imports.bulkSetCategory}</Button>
            <Button size="sm" variant="outline" className="h-7 text-xs" onClick={() => setBulkAction('price')}>{t.imports.bulkSetPrice}</Button>
            <Button size="sm" variant="outline" className="h-7 text-xs" onClick={() => toggleActive(true)}>{t.common.active}</Button>
            <Button size="sm" variant="outline" className="h-7 text-xs" onClick={() => toggleActive(false)}>{t.common.inactive}</Button>
            <Button aria-label="Limpar a seleção" size="sm" variant="ghost" className="h-7 text-xs" onClick={() => setSelected(new Set())}><X className="h-3 w-3" /></Button>
          </div>
        )}

        {bulkAction === 'category' && (
          <div className="flex items-center gap-2 p-2 border rounded">
            <Input className="h-7 text-xs flex-1" placeholder={t.imports.bulkSetCategory} value={bulkCategory} onChange={e => setBulkCategory(e.target.value)} />
            <Button size="sm" className="h-7" onClick={applyBulkCategory}>{t.common.save}</Button>
            <Button aria-label="Cancelar a troca de categoria" size="sm" variant="ghost" className="h-7" onClick={() => setBulkAction(null)}><X className="h-3 w-3" /></Button>
          </div>
        )}

        {bulkAction === 'price' && (
          <div className="flex flex-wrap items-center gap-2 p-2 border rounded">
            <div className="flex gap-1">
              {([['increase', t.imports.increasePercent], ['decrease', t.imports.decreasePercent], ['fixed', t.imports.setFixed]] as const).map(([m, label]) => (
                <Button key={m} size="sm" variant={priceMode === m ? 'default' : 'outline'} className="h-7 text-xs"
                  onClick={() => setPriceMode(m as any)}>{label}</Button>
              ))}
            </div>
            <Input type="number" className="h-7 text-xs w-24" value={priceValue} onChange={e => setPriceValue(parseFloat(e.target.value) || 0)} />
            {entityType === 'products' && (
              <>
                <label className="flex items-center gap-1 text-xs"><Checkbox checked={priceSale} onCheckedChange={v => setPriceSale(!!v)} />Venda</label>
                <label className="flex items-center gap-1 text-xs"><Checkbox checked={priceCost} onCheckedChange={v => setPriceCost(!!v)} />Custo</label>
              </>
            )}
            <Button size="sm" className="h-7" onClick={applyBulkPrice}>{t.common.save}</Button>
            <Button aria-label="Cancelar a troca de preço" size="sm" variant="ghost" className="h-7" onClick={() => setBulkAction(null)}><X className="h-3 w-3" /></Button>
          </div>
        )}

        {/* Celular: um cartão por item, campos empilhados (sem rolagem lateral). */}
        {celular ? (
          <div className="flex-1 overflow-y-auto space-y-2" data-testid="bulk-cartoes">
            {filtered.map(item => {
              const isSelected = selected.has(item.id);
              const campo = (field: string, rotulo: string, type = 'text') => (
                <label className="space-y-0.5 min-w-0">
                  <span className="block text-[11px] text-muted-foreground">{rotulo}</span>
                  {EditCell({ id: item.id, field: field, type: type, item: item })}
                </label>
              );
              return (
                <div key={item.id} className={`rounded border p-2 space-y-2 ${isSelected ? 'bg-accent/5' : ''}`}>
                  <div className="flex items-center gap-2">
                    <Checkbox
                      aria-label={`Selecionar ${item.name}`}
                      checked={isSelected}
                      onCheckedChange={() => {
                        const next = new Set(selected);
                        if (isSelected) next.delete(item.id); else next.add(item.id);
                        setSelected(next);
                      }}
                    />
                    <div className="flex-1 min-w-0">{EditCell({ id: item.id, field: "name", item: item })}</div>
                    <Switch aria-label={`${item.name} ativo`} checked={!!getVal(item, 'active')} onCheckedChange={v => setVal(item.id, 'active', v)} />
                  </div>
                  <div className="grid grid-cols-2 gap-2">
                    {entityType === 'products' ? (
                      <>
                        {campo('sku', 'SKU')}
                        {campo('category', t.products.category)}
                        {campo('brand', t.products.brand)}
                        {campo('cost_price', t.products.cost, 'number')}
                        {campo('sale_price', t.products.salePrice, 'number')}
                        {campo('stock_quantity', t.products.stock, 'number')}
                        {campo('minimum_stock', t.products.min, 'number')}
                      </>
                    ) : (
                      <>
                        {campo('category', t.services.category)}
                        {campo('billing_unit', t.services.billingUnit)}
                        {campo('default_price', t.services.defaultPrice, 'number')}
                      </>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        ) : (
        <div className="flex-1 overflow-y-auto border rounded">
          <table className="text-xs w-full">
            <thead className="sticky top-0 bg-card z-10">
              <tr className="border-b bg-muted/50">
                <th className="px-2 py-2 w-8"><Checkbox checked={selected.size === filtered.length && filtered.length > 0} onCheckedChange={toggleAll} /></th>
                {entityType === 'products' ? (
                  <>
                    <th className="px-2 py-2 text-left font-medium">SKU</th>
                    <th className="px-2 py-2 text-left font-medium min-w-[200px]">{t.products.title}</th>
                    <th className="px-2 py-2 text-left font-medium">{t.products.category}</th>
                    <th className="px-2 py-2 text-left font-medium">{t.products.brand}</th>
                    <th className="px-2 py-2 text-right font-medium">{t.products.cost}</th>
                    <th className="px-2 py-2 text-right font-medium">{t.products.salePrice}</th>
                    <th className="px-2 py-2 text-right font-medium">{t.products.stock}</th>
                    <th className="px-2 py-2 text-right font-medium">{t.products.min}</th>
                    <th className="px-2 py-2 text-center font-medium">{t.common.active}</th>
                  </>
                ) : (
                  <>
                    <th className="px-2 py-2 text-left font-medium min-w-[200px]">{t.services.serviceName}</th>
                    <th className="px-2 py-2 text-left font-medium">{t.services.category}</th>
                    <th className="px-2 py-2 text-left font-medium">{t.services.billingUnit}</th>
                    <th className="px-2 py-2 text-right font-medium">{t.services.defaultPrice}</th>
                    <th className="px-2 py-2 text-center font-medium">{t.common.active}</th>
                  </>
                )}
              </tr>
            </thead>
            <tbody>
              {filtered.map(item => {
                const isSelected = selected.has(item.id);
                return (
                  <tr key={item.id} className={`border-b hover:bg-muted/20 ${isSelected ? 'bg-accent/5' : ''}`}>
                    <td className="px-2 py-1">
                      <Checkbox checked={isSelected} onCheckedChange={() => {
                        const next = new Set(selected);
                        if (isSelected) next.delete(item.id); else next.add(item.id);
                        setSelected(next);
                      }} />
                    </td>
                    {entityType === 'products' ? (
                      <>
                        <td className="px-2 py-1">{EditCell({ id: item.id, field: "sku", item: item })}</td>
                        <td className="px-2 py-1">{EditCell({ id: item.id, field: "name", item: item })}</td>
                        <td className="px-2 py-1">{EditCell({ id: item.id, field: "category", item: item })}</td>
                        <td className="px-2 py-1">{EditCell({ id: item.id, field: "brand", item: item })}</td>
                        <td className="px-2 py-1">{EditCell({ id: item.id, field: "cost_price", type: "number", item: item })}</td>
                        <td className="px-2 py-1">{EditCell({ id: item.id, field: "sale_price", type: "number", item: item })}</td>
                        <td className="px-2 py-1">{EditCell({ id: item.id, field: "stock_quantity", type: "number", item: item })}</td>
                        <td className="px-2 py-1">{EditCell({ id: item.id, field: "minimum_stock", type: "number", item: item })}</td>
                        <td className="px-2 py-1 text-center">
                          <Switch checked={!!getVal(item, 'active')} onCheckedChange={v => setVal(item.id, 'active', v)} />
                        </td>
                      </>
                    ) : (
                      <>
                        <td className="px-2 py-1">{EditCell({ id: item.id, field: "name", item: item })}</td>
                        <td className="px-2 py-1">{EditCell({ id: item.id, field: "category", item: item })}</td>
                        <td className="px-2 py-1">{EditCell({ id: item.id, field: "billing_unit", item: item })}</td>
                        <td className="px-2 py-1">{EditCell({ id: item.id, field: "default_price", type: "number", item: item })}</td>
                        <td className="px-2 py-1 text-center">
                          <Switch checked={!!getVal(item, 'active')} onCheckedChange={v => setVal(item.id, 'active', v)} />
                        </td>
                      </>
                    )}
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
        )}

        {/* Footer */}
        <div className="flex items-center justify-end gap-2 pt-2 border-t">
          {changedCount > 0 && (
            <Button onClick={handleSave} disabled={saving} className="gap-2">
              {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
              {t.imports.saveChanges} ({changedCount})
            </Button>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}
