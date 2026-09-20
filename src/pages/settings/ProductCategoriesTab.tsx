// Aba "ProductCategoriesTab" de Configurações. Extraída de SettingsPage.tsx em 20/09/2026 (o arquivo
// tinha 1.981 linhas); comportamento idêntico, só mudou de endereço.
import { useState } from 'react';
import { useI18n } from '@/i18n';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Package } from 'lucide-react';
import { useAllProductCategories, useCreateProductCategory, useUpdateProductCategory } from '@/hooks/use-product-categories';
import { Switch } from '@/components/ui/switch';
import { toast } from 'sonner';

export function ProductCategoriesTab() {
  const { t } = useI18n();
  const st = t.settings as any;
  const { data: categories, isLoading } = useAllProductCategories();
  const createCat = useCreateProductCategory();
  const updateCat = useUpdateProductCategory();

  const [showNew, setShowNew] = useState(false);
  const [newForm, setNewForm] = useState({
    name: '',
    default_profit_margin: 30,
    default_commission_rate: 0,
    is_commissionable: true,
    default_csosn: '400',
    default_ncm: '',
  });
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editField, setEditField] = useState<string>('');
  const [editValue, setEditValue] = useState<any>('');

  const handleCreate = async () => {
    if (!newForm.name.trim()) return;
    try {
      await createCat.mutateAsync({
        name: newForm.name.trim(),
        default_profit_margin: newForm.default_profit_margin,
        default_commission_rate: newForm.default_commission_rate,
        is_commissionable: newForm.is_commissionable,
        default_csosn: newForm.default_csosn,
        default_ncm: newForm.default_ncm || null,
      });
      setShowNew(false);
      setNewForm({ name: '', default_profit_margin: 30, default_commission_rate: 0, is_commissionable: true, default_csosn: '400', default_ncm: '' });
      toast.success(st.newProductCategory || 'Categoria criada');
    } catch (e: any) {
      toast.error(e.message || 'Erro');
    }
  };

  const handleInlineEdit = async (id: string, field: string, value: any) => {
    try {
      await updateCat.mutateAsync({ id, [field]: value });
      setEditingId(null);
    } catch (e: any) {
      toast.error(e.message || 'Erro');
    }
  };

  if (isLoading) return <p className="text-sm text-muted-foreground">{t.common.loading}</p>;

  return (
    <div className="space-y-4 max-w-4xl">
      <div className="rounded-lg border border-primary/20 bg-primary/5 p-3 text-sm">
        <Package className="h-4 w-4 inline mr-1.5 text-primary" />
        {st.productCategoriesInfo || 'As categorias definem margens e comissões padrão para grupos de produtos. Produtos herdam estas configurações mas podem ter valores personalizados individualmente.'}
      </div>

      <div className="rounded-xl border bg-card shadow-sm overflow-x-auto scrollbar-thin">
        <table className="w-full text-sm min-w-[700px]">
          <thead>
            <tr className="border-b bg-muted/50">
              <th className="px-4 py-2 text-left font-medium text-muted-foreground">Nome</th>
              <th className="px-3 py-2 text-right font-medium text-muted-foreground">{st.defaultProfitMargin || 'Margem %'}</th>
              <th className="px-3 py-2 text-right font-medium text-muted-foreground">{st.defaultCommissionRate || 'Comissão %'}</th>
              <th className="px-3 py-2 text-center font-medium text-muted-foreground">Comissionável</th>
              <th className="px-3 py-2 text-left font-medium text-muted-foreground">NCM</th>
              <th className="px-3 py-2 text-center font-medium text-muted-foreground">{t.common.active}</th>
            </tr>
          </thead>
          <tbody>
            {(categories || []).map(cat => (
              <tr key={cat.id} className="border-b last:border-0 hover:bg-muted/30">
                <td className="px-4 py-2">
                  {editingId === cat.id && editField === 'name' ? (
                    <Input
                      className="h-7 text-sm"
                      value={editValue}
                      onChange={e => setEditValue(e.target.value)}
                      onBlur={() => handleInlineEdit(cat.id, 'name', editValue)}
                      onKeyDown={e => e.key === 'Enter' && handleInlineEdit(cat.id, 'name', editValue)}
                      autoFocus
                    />
                  ) : (
                    <button
                      className="font-medium hover:underline text-left"
                      onClick={() => { setEditingId(cat.id); setEditField('name'); setEditValue(cat.name); }}
                    >
                      {cat.name}
                    </button>
                  )}
                </td>
                <td className="px-3 py-2 text-right">
                  {editingId === cat.id && editField === 'default_profit_margin' ? (
                    <Input
                      type="number" step="0.01" className="h-7 text-sm w-20 ml-auto text-right"
                      value={editValue}
                      onChange={e => setEditValue(e.target.value)}
                      onBlur={() => handleInlineEdit(cat.id, 'default_profit_margin', parseFloat(editValue) || 0)}
                      autoFocus
                    />
                  ) : (
                    <button
                      className="hover:underline"
                      onClick={() => { setEditingId(cat.id); setEditField('default_profit_margin'); setEditValue(cat.default_profit_margin); }}
                    >
                      {cat.default_profit_margin}%
                    </button>
                  )}
                </td>
                <td className="px-3 py-2 text-right">
                  {editingId === cat.id && editField === 'default_commission_rate' ? (
                    <Input
                      type="number" step="0.01" className="h-7 text-sm w-20 ml-auto text-right"
                      value={editValue}
                      onChange={e => setEditValue(e.target.value)}
                      onBlur={() => handleInlineEdit(cat.id, 'default_commission_rate', parseFloat(editValue) || 0)}
                      autoFocus
                    />
                  ) : (
                    <button
                      className="hover:underline"
                      onClick={() => { setEditingId(cat.id); setEditField('default_commission_rate'); setEditValue(cat.default_commission_rate); }}
                    >
                      {cat.default_commission_rate}%
                    </button>
                  )}
                </td>
                <td className="px-3 py-2 text-center">
                  <Switch
                    checked={cat.is_commissionable ?? true}
                    onCheckedChange={v => updateCat.mutate({ id: cat.id, is_commissionable: v })}
                  />
                </td>
                <td className="px-3 py-2">
                  {editingId === cat.id && editField === 'default_ncm' ? (
                    <Input
                      className="h-7 text-sm w-24"
                      value={editValue}
                      maxLength={8}
                      onChange={e => setEditValue(e.target.value.replace(/\D/g, '').slice(0, 8))}
                      onBlur={() => handleInlineEdit(cat.id, 'default_ncm', editValue || null)}
                      autoFocus
                    />
                  ) : (
                    <button
                      className="hover:underline text-muted-foreground"
                      onClick={() => { setEditingId(cat.id); setEditField('default_ncm'); setEditValue(cat.default_ncm || ''); }}
                    >
                      {cat.default_ncm || '—'}
                    </button>
                  )}
                </td>
                <td className="px-3 py-2 text-center">
                  <Switch
                    checked={cat.active ?? true}
                    onCheckedChange={v => updateCat.mutate({ id: cat.id, active: v })}
                  />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <p className="text-xs text-muted-foreground">{(categories || []).length} categorias cadastradas</p>

      {showNew ? (
        <div className="rounded-xl border bg-card p-4 shadow-sm space-y-3">
          <h4 className="text-sm font-semibold">{st.newProductCategory || 'Nova Categoria'}</h4>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div className="col-span-2">
              <label className="text-xs font-medium text-muted-foreground">Nome *</label>
              <Input value={newForm.name} onChange={e => setNewForm(p => ({ ...p, name: e.target.value }))} className="mt-1" />
            </div>
            <div>
              <label className="text-xs font-medium text-muted-foreground">{st.defaultProfitMargin || 'Margem %'}</label>
              <Input type="number" step="0.01" value={newForm.default_profit_margin}
                onChange={e => setNewForm(p => ({ ...p, default_profit_margin: parseFloat(e.target.value) || 0 }))} className="mt-1" />
            </div>
            <div>
              <label className="text-xs font-medium text-muted-foreground">{st.defaultCommissionRate || 'Comissão %'}</label>
              <Input type="number" step="0.01" value={newForm.default_commission_rate}
                onChange={e => setNewForm(p => ({ ...p, default_commission_rate: parseFloat(e.target.value) || 0 }))} className="mt-1" />
            </div>
            <div className="flex items-center gap-2 col-span-2 pt-1">
              <Switch
                checked={newForm.is_commissionable}
                onCheckedChange={v => setNewForm(p => ({ ...p, is_commissionable: v }))}
              />
              <label className="text-xs">Permite comissionamento</label>
            </div>
            <div>
              <label className="text-xs font-medium text-muted-foreground">NCM Padrão</label>
              <Input value={newForm.default_ncm} maxLength={8}
                onChange={e => setNewForm(p => ({ ...p, default_ncm: e.target.value.replace(/\D/g, '').slice(0, 8) }))} className="mt-1" />
            </div>
          </div>
          <div className="flex gap-2">
            <Button size="sm" onClick={handleCreate} disabled={createCat.isPending || !newForm.name.trim()}>{t.common.save}</Button>
            <Button size="sm" variant="ghost" onClick={() => setShowNew(false)}>{t.common.cancel}</Button>
          </div>
        </div>
      ) : (
        <Button variant="outline" size="sm" onClick={() => setShowNew(true)}>
          + {st.newProductCategory || 'Nova Categoria'}
        </Button>
      )}
    </div>
  );
}
