import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { StatusBadge } from '@/components/StatusBadge';
import { useI18n } from '@/i18n';
import { useFinancialCategories } from '@/hooks/use-financial-categories';
import { useSuppliers } from '@/hooks/use-suppliers';
import { useClients } from '@/hooks/use-clients';
import { useSavedFilters, useCreateSavedFilter, useDeleteSavedFilter } from '@/hooks/use-saved-filters';
import { Filter, X, Star, Trash2 } from 'lucide-react';
import { toast } from 'sonner';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';

export type FinancialFilters = {
  search: string;
  status: string[];
  dateFrom: string;
  dateTo: string;
  datePreset: string;
  categories: string[];
  suppliers: string[];
  clients: string[];
  amountMin: number | null;
  amountMax: number | null;
  origin: string[];
};

export const defaultFilters: FinancialFilters = {
  search: '', status: [], dateFrom: '', dateTo: '', datePreset: '',
  categories: [], suppliers: [], clients: [],
  amountMin: null, amountMax: null, origin: [],
};

function countActive(f: FinancialFilters): number {
  let c = 0;
  if (f.search) c++;
  if (f.status.length) c++;
  if (f.dateFrom || f.dateTo || f.datePreset) c++;
  if (f.categories.length) c++;
  if (f.suppliers.length) c++;
  if (f.clients.length) c++;
  if (f.amountMin !== null || f.amountMax !== null) c++;
  if (f.origin.length) c++;
  return c;
}

interface Props {
  type: 'payable' | 'receivable';
  filters: FinancialFilters;
  onChange: (filters: FinancialFilters) => void;
}

export function FinancialFilterPanel({ type, filters, onChange }: Props) {
  const { t } = useI18n();
  const ft = t.financial as any;
  const [open, setOpen] = useState(false);
  const [saveName, setSaveName] = useState('');
  const [showSave, setShowSave] = useState(false);
  const { data: categories } = useFinancialCategories(type);
  const { data: suppliersList } = useSuppliers();
  const { data: clientsList } = useClients();
  const { data: saved } = useSavedFilters(type);
  const createSaved = useCreateSavedFilter();
  const deleteSaved = useDeleteSavedFilter();

  const activeCount = countActive(filters);

  const toggleArray = (arr: string[], val: string) =>
    arr.includes(val) ? arr.filter(v => v !== val) : [...arr, val];

  const applyDatePreset = (preset: string) => {
    const now = new Date();
    let from = '', to = '';
    if (preset === 'this_month') {
      from = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-01`;
      to = now.toISOString().split('T')[0];
    } else if (preset === 'last_month') {
      const lm = new Date(now.getFullYear(), now.getMonth() - 1, 1);
      from = lm.toISOString().split('T')[0];
      to = new Date(now.getFullYear(), now.getMonth(), 0).toISOString().split('T')[0];
    } else if (preset === 'last_30') {
      from = new Date(now.getTime() - 30 * 86400000).toISOString().split('T')[0];
      to = now.toISOString().split('T')[0];
    } else if (preset === 'last_90') {
      from = new Date(now.getTime() - 90 * 86400000).toISOString().split('T')[0];
      to = now.toISOString().split('T')[0];
    } else if (preset === 'this_year') {
      from = `${now.getFullYear()}-01-01`;
      to = now.toISOString().split('T')[0];
    }
    onChange({ ...filters, datePreset: preset, dateFrom: from, dateTo: to });
  };

  const handleSave = async () => {
    if (!saveName.trim()) return;
    try {
      await createSaved.mutateAsync({ name: saveName.trim(), filter_type: type, filter_config: filters });
      toast.success(ft.saveFilter);
      setSaveName('');
      setShowSave(false);
    } catch { toast.error('Erro'); }
  };

  const datePresets = [
    { key: 'this_month', label: ft.thisMonth },
    { key: 'last_month', label: ft.lastMonth },
    { key: 'last_30', label: ft.last30days },
    { key: 'last_90', label: ft.last90days },
    { key: 'this_year', label: ft.thisYear },
    { key: 'custom', label: ft.customRange },
  ];

  const statuses = [
    { key: 'pending', label: (t.paymentStatus as any).pending },
    { key: 'partially_paid', label: (t.paymentStatus as any).partially_paid },
    { key: 'paid', label: (t.paymentStatus as any).paid },
    { key: 'overdue', label: (t.paymentStatus as any).overdue },
    { key: 'cancelled', label: (t.paymentStatus as any).cancelled },
  ];

  return (
    <div className="space-y-2">
      <div className="flex items-center gap-2">
        <Button variant={open ? 'default' : 'outline'} size="sm" onClick={() => setOpen(!open)}>
          <Filter className="h-4 w-4 mr-1" />
          {ft.advancedFilters}
          {activeCount > 0 && (
            <StatusBadge className="bg-primary/20 text-primary-foreground ml-1">{activeCount}</StatusBadge>
          )}
        </Button>
        <Input
          placeholder={t.common.search}
          className="max-w-xs"
          value={filters.search}
          onChange={e => onChange({ ...filters, search: e.target.value })}
        />
        {activeCount > 0 && (
          <Button variant="ghost" size="sm" onClick={() => onChange({ ...defaultFilters })}>
            <X className="h-3 w-3 mr-1" />{ft.clearFilters}
          </Button>
        )}
      </div>

      {open && (
        <div className="rounded-xl border bg-card p-4 shadow-lg space-y-4 max-w-4xl">
          {/* Date range */}
          <div>
            <Label className="text-xs text-muted-foreground mb-1 block">{t.common.date}</Label>
            <div className="flex flex-wrap gap-1">
              {datePresets.map(p => (
                <Button key={p.key} size="sm" variant={filters.datePreset === p.key ? 'default' : 'outline'}
                  onClick={() => p.key === 'custom' ? onChange({ ...filters, datePreset: 'custom' }) : applyDatePreset(p.key)}>
                  {p.label}
                </Button>
              ))}
            </div>
            {filters.datePreset === 'custom' && (
              <div className="flex gap-2 mt-2">
                <div><Label className="text-xs">{ft.dateFrom}</Label><Input type="date" value={filters.dateFrom} onChange={e => onChange({ ...filters, dateFrom: e.target.value })} /></div>
                <div><Label className="text-xs">{ft.dateTo}</Label><Input type="date" value={filters.dateTo} onChange={e => onChange({ ...filters, dateTo: e.target.value })} /></div>
              </div>
            )}
          </div>

          {/* Status chips */}
          <div>
            <Label className="text-xs text-muted-foreground mb-1 block">{t.common.status}</Label>
            <div className="flex flex-wrap gap-1">
              {statuses.map(s => (
                <Button key={s.key} size="sm" variant={filters.status.includes(s.key) ? 'default' : 'outline'}
                  onClick={() => onChange({ ...filters, status: toggleArray(filters.status, s.key) })}>
                  {s.label}
                </Button>
              ))}
            </div>
          </div>

          {/* Categories */}
          <div>
            <Label className="text-xs text-muted-foreground mb-1 block">{ft.allCategories}</Label>
            <div className="flex flex-wrap gap-1">
              {(categories || []).map(c => (
                <Button key={c.id} size="sm" variant={filters.categories.includes(c.name) ? 'default' : 'outline'}
                  onClick={() => onChange({ ...filters, categories: toggleArray(filters.categories, c.name) })}>
                  <span className="w-2 h-2 rounded-full mr-1" style={{ backgroundColor: c.color || '#6b7280' }} />
                  {c.name}
                </Button>
              ))}
            </div>
          </div>

          {/* Suppliers (payable) or Clients (receivable) */}
          {type === 'payable' ? (
            <div>
              <Label className="text-xs text-muted-foreground mb-1 block">{ft.allSuppliers}</Label>
              <div className="flex flex-wrap gap-1 max-h-24 overflow-y-auto">
                {(suppliersList || []).map(s => (
                  <Button key={s.id} size="sm" variant={filters.suppliers.includes(s.name) ? 'default' : 'outline'}
                    onClick={() => onChange({ ...filters, suppliers: toggleArray(filters.suppliers, s.name) })}>
                    {s.name}
                  </Button>
                ))}
              </div>
            </div>
          ) : (
            <div>
              <Label className="text-xs text-muted-foreground mb-1 block">{ft.allClients}</Label>
              <div className="flex flex-wrap gap-1 max-h-24 overflow-y-auto">
                {(clientsList || []).map(c => (
                  <Button key={c.id} size="sm" variant={filters.clients.includes(c.name) ? 'default' : 'outline'}
                    onClick={() => onChange({ ...filters, clients: toggleArray(filters.clients, c.name) })}>
                    {c.name}
                  </Button>
                ))}
              </div>
            </div>
          )}

          {/* Amount range */}
          <div className="flex gap-3 items-end">
            <div><Label className="text-xs">{ft.amountMin}</Label><Input type="number" placeholder={ft.anyAmount} className="w-32" value={filters.amountMin ?? ''} onChange={e => onChange({ ...filters, amountMin: e.target.value ? Number(e.target.value) : null })} /></div>
            <div><Label className="text-xs">{ft.amountMax}</Label><Input type="number" placeholder={ft.anyAmount} className="w-32" value={filters.amountMax ?? ''} onChange={e => onChange({ ...filters, amountMax: e.target.value ? Number(e.target.value) : null })} /></div>
          </div>

          {/* Origin (payable only) */}
          {type === 'payable' && (
            <div>
              <Label className="text-xs text-muted-foreground mb-1 block">Origem</Label>
              <div className="flex flex-wrap gap-1">
                {[
                  { key: 'manual', label: ft.originManual },
                  { key: 'service_order_expense', label: ft.originServiceOrder },
                  { key: 'bank_reconciliation', label: ft.originReconciliation },
                ].map(o => (
                  <Button key={o.key} size="sm" variant={filters.origin.includes(o.key) ? 'default' : 'outline'}
                    onClick={() => onChange({ ...filters, origin: toggleArray(filters.origin, o.key) })}>
                    {o.label}
                  </Button>
                ))}
              </div>
            </div>
          )}

          {/* Actions */}
          <div className="flex items-center justify-between border-t pt-3">
            <Button variant="ghost" size="sm" onClick={() => onChange({ ...defaultFilters })}>
              {ft.clearFilters}
            </Button>
            <div className="flex items-center gap-2">
              {showSave ? (
                <div className="flex items-center gap-1">
                  <Input placeholder={ft.filterName} className="w-40 h-8" value={saveName} onChange={e => setSaveName(e.target.value)} />
                  <Button size="sm" onClick={handleSave} disabled={createSaved.isPending}>{t.common.save}</Button>
                  <Button size="sm" variant="ghost" onClick={() => setShowSave(false)}><X className="h-3 w-3" /></Button>
                </div>
              ) : (
                <Button size="sm" variant="outline" onClick={() => setShowSave(true)}>
                  <Star className="h-3 w-3 mr-1" />{ft.saveFilter}
                </Button>
              )}
              {(saved || []).length > 0 && (
                <Popover>
                  <PopoverTrigger asChild>
                    <Button size="sm" variant="outline">{ft.savedFilters} ({saved?.length})</Button>
                  </PopoverTrigger>
                  <PopoverContent className="w-64 p-2" align="end">
                    <div className="space-y-1">
                      {(saved || []).map(sf => (
                        <div key={sf.id} className="flex items-center justify-between p-1.5 rounded hover:bg-muted/50 text-sm">
                          <button className="text-left flex-1 font-medium" onClick={() => { onChange(sf.filter_config as any); }}>
                            {sf.name}
                          </button>
                          <Button size="sm" variant="ghost" className="h-6 w-6 p-0" onClick={() => deleteSaved.mutate({ id: sf.id, filterType: type, isDefault: (sf as any).is_default ?? false })}>
                            <Trash2 className="h-3 w-3 text-destructive" />
                          </Button>
                        </div>
                      ))}
                    </div>
                  </PopoverContent>
                </Popover>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export function applyFilters(items: any[], filters: FinancialFilters, type: 'payable' | 'receivable') {
  return items.filter(item => {
    if (filters.search) {
      const s = filters.search.toLowerCase();
      const desc = (item.description || '').toLowerCase();
      const name = type === 'payable'
        ? ((item as any).suppliers?.name || item.name || '').toLowerCase()
        : ((item as any).clients?.name || '').toLowerCase();
      if (!desc.includes(s) && !name.includes(s)) return false;
    }
    if (filters.status.length > 0) {
      const isOverdue = item.status !== 'paid' && item.status !== 'cancelled' && new Date(item.due_date) < new Date();
      const effective = isOverdue ? 'overdue' : item.status;
      if (!filters.status.includes(effective)) return false;
    }
    if (filters.dateFrom && new Date(item.due_date) < new Date(filters.dateFrom)) return false;
    if (filters.dateTo && new Date(item.due_date) > new Date(filters.dateTo)) return false;
    if (filters.categories.length > 0) {
      const cat = type === 'payable' ? item.expense_category : item.category;
      if (!filters.categories.includes(cat)) return false;
    }
    if (type === 'payable' && filters.suppliers.length > 0) {
      const sup = (item as any).suppliers?.name || item.name;
      if (!filters.suppliers.includes(sup)) return false;
    }
    if (type === 'receivable' && filters.clients.length > 0) {
      const client = (item as any).clients?.name;
      if (!filters.clients.includes(client)) return false;
    }
    if (filters.amountMin !== null && Number(item.amount) < filters.amountMin) return false;
    if (filters.amountMax !== null && Number(item.amount) > filters.amountMax) return false;
    if (type === 'payable' && filters.origin.length > 0) {
      if (!filters.origin.includes(item.origin || 'manual')) return false;
    }
    return true;
  });
}
