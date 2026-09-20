// Aba "CategoriesTab" de Configurações. Extraída de SettingsPage.tsx em 20/09/2026 (o arquivo
// tinha 1.981 linhas); comportamento idêntico, só mudou de endereço.
import { useState } from 'react';
import { useI18n } from '@/i18n';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Tag } from 'lucide-react';
import { useFinancialCategories, useCreateFinancialCategory, useUpdateFinancialCategory } from '@/hooks/use-financial-categories';
import { Switch } from '@/components/ui/switch';
import { toast } from 'sonner';

export function CategoriesTab() {
  const { t } = useI18n();
  const st = t.settings as any;
  const { data: payableCats } = useFinancialCategories('payable');
  const { data: receivableCats } = useFinancialCategories('receivable');
  const createCat = useCreateFinancialCategory();
  const updateCat = useUpdateFinancialCategory();

  const [newPayName, setNewPayName] = useState('');
  const [newPayColor, setNewPayColor] = useState('#6b7280');
  const [newRecName, setNewRecName] = useState('');
  const [newRecColor, setNewRecColor] = useState('#6b7280');
  const [showNewPay, setShowNewPay] = useState(false);
  const [showNewRec, setShowNewRec] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editName, setEditName] = useState('');

  const handleCreate = async (type: 'payable' | 'receivable') => {
    const name = type === 'payable' ? newPayName : newRecName;
    const color = type === 'payable' ? newPayColor : newRecColor;
    if (!name.trim()) return;
    try {
      await createCat.mutateAsync({ name: name.trim(), type, color });
      if (type === 'payable') { setNewPayName(''); setNewPayColor('#6b7280'); setShowNewPay(false); }
      else { setNewRecName(''); setNewRecColor('#6b7280'); setShowNewRec(false); }
      toast.success(st.newCategory);
    } catch { toast.error('Erro'); }
  };

  const handleRename = async (id: string) => {
    if (!editName.trim()) return;
    try {
      await updateCat.mutateAsync({ id, name: editName.trim() });
      setEditingId(null);
    } catch { toast.error('Erro'); }
  };

  const renderColumn = (
    title: string, cats: any[] | undefined, type: 'payable' | 'receivable',
    showNew: boolean, setShowNew: (v: boolean) => void,
    newName: string, setNewName: (v: string) => void,
    newColor: string, setNewColor: (v: string) => void
  ) => (
    <div className="rounded-xl border bg-card p-6 shadow-sm">
      <h3 className="text-sm font-semibold mb-4 flex items-center gap-2"><Tag className="h-4 w-4" /> {title}</h3>
      <div className="space-y-2">
        {(cats || []).map(c => (
          <div key={c.id} className="flex items-center gap-3 p-2 rounded-lg hover:bg-muted/50">
            <span className="w-3 h-3 rounded-full shrink-0" style={{ backgroundColor: c.color || '#6b7280' }} />
            {editingId === c.id ? (
              <Input className="h-7 text-sm flex-1" value={editName} onChange={e => setEditName(e.target.value)}
                onBlur={() => handleRename(c.id)} onKeyDown={e => e.key === 'Enter' && handleRename(c.id)} autoFocus />
            ) : (
              <button className="flex-1 text-left text-sm font-medium hover:underline"
                onClick={() => { setEditingId(c.id); setEditName(c.name); }}>
                {c.name}
              </button>
            )}
            <Switch checked={c.active} onCheckedChange={v => updateCat.mutate({ id: c.id, active: v })} />
          </div>
        ))}
      </div>
      {showNew ? (
        <div className="mt-3 p-3 rounded-lg border bg-muted/30 space-y-2">
          <div className="flex gap-2">
            <Input placeholder={st.categoryName} value={newName} onChange={e => setNewName(e.target.value)} className="flex-1 h-8" />
            <input type="color" value={newColor} onChange={e => setNewColor(e.target.value)} className="w-8 h-8 rounded cursor-pointer" />
          </div>
          <div className="flex gap-1">
            <Button size="sm" onClick={() => handleCreate(type)} disabled={createCat.isPending}>{t.common.save}</Button>
            <Button size="sm" variant="ghost" onClick={() => setShowNew(false)}>{t.common.cancel}</Button>
          </div>
        </div>
      ) : (
        <Button variant="outline" size="sm" className="mt-3" onClick={() => setShowNew(true)}>
          + {st.newCategory}
        </Button>
      )}
    </div>
  );

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
      {renderColumn(st.payableCategories, payableCats, 'payable', showNewPay, setShowNewPay, newPayName, setNewPayName, newPayColor, setNewPayColor)}
      {renderColumn(st.receivableCategories, receivableCats, 'receivable', showNewRec, setShowNewRec, newRecName, setNewRecName, newRecColor, setNewRecColor)}
    </div>
  );
}
