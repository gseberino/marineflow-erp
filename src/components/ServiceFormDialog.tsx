import { useState, useEffect } from 'react';
import { useI18n } from '@/i18n';
import { useCreateService, useUpdateService } from '@/hooks/use-services';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Button } from '@/components/ui/button';
import { Switch } from '@/components/ui/switch';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { toast } from 'sonner';
import { MoneyInput } from '@/components/MoneyInput';

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  editData?: any;
  onCreated?: (service: any) => void;
}

export function ServiceFormDialog({ open, onOpenChange, editData, onCreated }: Props) {
  const { t } = useI18n();
  const create = useCreateService();
  const update = useUpdateService();

  const [form, setForm] = useState({
    service_name: '',
    description: '',
    category: '',
    billing_unit: 'hour',
    default_price: 0,
    currency: 'BRL',
    active: true,
  });

  useEffect(() => {
    if (editData) {
      setForm({
        service_name: editData.service_name || '',
        description: editData.description || '',
        category: editData.category || '',
        billing_unit: editData.billing_unit || 'hour',
        default_price: editData.default_price || 0,
        currency: editData.currency || 'BRL',
        active: editData.active ?? true,
      });
    } else {
      setForm({ service_name: '', description: '', category: '', billing_unit: 'hour', default_price: 0, currency: 'BRL', active: true });
    }
  }, [editData, open]);

  const set = (field: string, value: any) => setForm((p) => ({ ...p, [field]: value }));

  const handleSave = async () => {
    if (!form.service_name.trim()) return;
    try {
      if (editData?.id) {
        await update.mutateAsync({ id: editData.id, ...form });
        toast.success(t.services.updateSuccess);
      } else {
        const result = await create.mutateAsync(form);
        toast.success(t.services.createSuccess);
        onCreated?.(result);
      }
      onOpenChange(false);
    } catch (e: any) {
      toast.error(e.message || 'Erro');
    }
  };

  const billingUnits = [
    { value: 'hour', label: t.services.unitHour },
    { value: 'visit', label: t.services.unitVisit },
    { value: 'day', label: t.services.unitDay },
    { value: 'unit', label: t.services.unitUnit },
  ];

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>{editData ? t.services.editService : t.services.newService}</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <div>
            <Label>{t.services.serviceName} *</Label>
            <Input value={form.service_name} onChange={(e) => set('service_name', e.target.value)} className="mt-1" />
          </div>
          <div>
            <Label>{t.common.description}</Label>
            <Textarea value={form.description} onChange={(e) => set('description', e.target.value)} rows={2} className="mt-1" />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <Label>{t.services.category}</Label>
              <Input value={form.category} onChange={(e) => set('category', e.target.value)} className="mt-1" />
            </div>
            <div>
              <Label>{t.services.billingUnit}</Label>
              <Select value={form.billing_unit} onValueChange={(v) => set('billing_unit', v)}>
                <SelectTrigger className="mt-1"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {billingUnits.map((u) => (
                    <SelectItem key={u.value} value={u.value}>{u.label}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <Label>{t.services.defaultPrice}</Label>
              <MoneyInput value={form.default_price} onValueChange={(v) => set('default_price', v)} className="mt-1" />
            </div>
            <div>
              <Label>{t.products.costCurrency}</Label>
              <Select value={form.currency} onValueChange={(v) => set('currency', v)}>
                <SelectTrigger className="mt-1"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="BRL">BRL</SelectItem>
                  <SelectItem value="USD">USD</SelectItem>
                  <SelectItem value="EUR">EUR</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <Switch checked={form.active} onCheckedChange={(v) => set('active', v)} />
            <Label>{t.common.active}</Label>
          </div>
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={() => onOpenChange(false)}>{t.common.cancel}</Button>
            <Button onClick={handleSave} disabled={create.isPending || update.isPending}
              className="bg-accent text-accent-foreground hover:bg-accent/90">
              {t.common.save}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
