import { useState, useEffect } from 'react';
import { useI18n } from '@/i18n';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { useCreateMarina, useUpdateMarina, type Marina } from '@/hooks/use-marinas';
import { toast } from 'sonner';
import type { TablesInsert } from '@/integrations/supabase/types';

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  marina?: Marina | null;
}

const empty: TablesInsert<'marinas'> = {
  marina_name: '',
  contact_name: '',
  contact_phone: '',
  contact_email: '',
  address_line_1: '',
  city: '',
  state: '',
  postal_code: '',
  country: 'Brazil',
  latitude: undefined,
  longitude: undefined,
  access_notes: '',
  billing_notes: '',
  active: true,
};

export function MarinaFormDialog({ open, onOpenChange, marina }: Props) {
  const { t } = useI18n();
  const create = useCreateMarina();
  const update = useUpdateMarina();
  const [form, setForm] = useState<TablesInsert<'marinas'>>(empty);
  const isEdit = !!marina;

  useEffect(() => {
    if (marina) {
      setForm({
        marina_name: marina.marina_name,
        contact_name: marina.contact_name ?? '',
        contact_phone: marina.contact_phone ?? '',
        contact_email: marina.contact_email ?? '',
        address_line_1: marina.address_line_1 ?? '',
        city: marina.city ?? '',
        state: marina.state ?? '',
        postal_code: marina.postal_code ?? '',
        country: marina.country ?? 'Brazil',
        latitude: marina.latitude ?? undefined,
        longitude: marina.longitude ?? undefined,
        access_notes: marina.access_notes ?? '',
        billing_notes: marina.billing_notes ?? '',
        active: marina.active,
      });
    } else {
      setForm(empty);
    }
  }, [marina, open]);

  const set = (key: string, value: any) => setForm(prev => ({ ...prev, [key]: value }));

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      if (isEdit && marina) {
        await update.mutateAsync({ id: marina.id, ...form });
        toast.success(t.marinas.updateSuccess);
      } else {
        await create.mutateAsync(form);
        toast.success(t.marinas.createSuccess);
      }
      onOpenChange(false);
    } catch (err: any) {
      toast.error(err.message);
    }
  };

  const isPending = create.isPending || update.isPending;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{isEdit ? t.marinas.editMarina : t.marinas.newMarina}</DialogTitle>
        </DialogHeader>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <div className="col-span-2">
              <Label>{t.marinas.marinaName} *</Label>
              <Input required value={form.marina_name} onChange={e => set('marina_name', e.target.value)} />
            </div>
            <div>
              <Label>{t.marinas.contactName}</Label>
              <Input value={form.contact_name ?? ''} onChange={e => set('contact_name', e.target.value)} />
            </div>
            <div>
              <Label>{t.marinas.contactPhone}</Label>
              <Input value={form.contact_phone ?? ''} onChange={e => set('contact_phone', e.target.value)} />
            </div>
            <div className="col-span-2">
              <Label>{t.marinas.contactEmail}</Label>
              <Input type="email" value={form.contact_email ?? ''} onChange={e => set('contact_email', e.target.value)} />
            </div>
            <div className="col-span-2">
              <Label>{t.clients.addressLine1}</Label>
              <Input value={form.address_line_1 ?? ''} onChange={e => set('address_line_1', e.target.value)} />
            </div>
            <div>
              <Label>{t.clients.city}</Label>
              <Input value={form.city ?? ''} onChange={e => set('city', e.target.value)} />
            </div>
            <div>
              <Label>{t.clients.state}</Label>
              <Input maxLength={2} value={form.state ?? ''} onChange={e => set('state', e.target.value.toUpperCase())} />
            </div>
            <div>
              <Label>{t.clients.postalCode}</Label>
              <Input value={form.postal_code ?? ''} onChange={e => set('postal_code', e.target.value)} />
            </div>
            <div>
              <Label>{t.clients.country}</Label>
              <Input value={form.country ?? 'Brazil'} onChange={e => set('country', e.target.value)} />
            </div>
            <div>
              <Label>{t.settings.latitude}</Label>
              <Input type="number" step="0.0000001" value={form.latitude ?? ''} onChange={e => set('latitude', e.target.value ? Number(e.target.value) : undefined)} />
            </div>
            <div>
              <Label>{t.settings.longitude}</Label>
              <Input type="number" step="0.0000001" value={form.longitude ?? ''} onChange={e => set('longitude', e.target.value ? Number(e.target.value) : undefined)} />
            </div>
            <div className="col-span-2">
              <Label>{t.marinas.accessNotes}</Label>
              <Textarea value={form.access_notes ?? ''} onChange={e => set('access_notes', e.target.value)} />
            </div>
            <div className="col-span-2">
              <Label>{t.marinas.billingNotes}</Label>
              <Textarea value={form.billing_notes ?? ''} onChange={e => set('billing_notes', e.target.value)} />
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
