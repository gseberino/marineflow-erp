import { useState, useEffect } from 'react';
import { useI18n } from '@/i18n';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { AddressFields } from '@/components/AddressFields';
import { useCreateMarina, useUpdateMarina, type Marina } from '@/hooks/use-marinas';
import { toast } from 'sonner';
import type { TablesInsert } from '@/integrations/supabase/types';
import { maskPhone } from '@/lib/masks';

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  marina?: Marina | null;
  onSaved?: (marina: Marina) => void;
}

const empty = {
  name: '',
  contact_name: '',
  phone: '',
  email: '',
  postal_code: '',
  address_line_1: '',
  address_number: '',
  address_complement: '',
  neighborhood: '',
  city: '',
  state: '',
  country: 'Brazil',
  latitude: null as number | null,
  longitude: null as number | null,
  access_notes: '',
  billing_notes: '',
  active: true,
};

export function MarinaFormDialog({ open, onOpenChange, marina, onSaved }: Props) {
  const { t } = useI18n();
  const create = useCreateMarina();
  const update = useUpdateMarina();
  const [form, setForm] = useState(empty);
  const isEdit = !!marina;

  useEffect(() => {
    if (marina) {
      setForm({
        name: marina.name ?? marina.marina_name ?? '',
        contact_name: marina.contact_name ?? '',
        phone: marina.contact_phone ?? '',
        email: marina.contact_email ?? '',
        postal_code: marina.postal_code ?? '',
        address_line_1: marina.address_line_1 ?? '',
        address_number: '',
        address_complement: '',
        neighborhood: '',
        city: marina.city ?? '',
        state: marina.state ?? '',
        country: marina.country ?? 'Brazil',
        latitude: marina.latitude ?? null,
        longitude: marina.longitude ?? null,
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
      const fullAddress = [form.address_line_1, form.address_number, form.address_complement].filter(Boolean).join(', ');
      const payload: TablesInsert<'marinas'> = {
        marina_name: form.name,
        contact_name: form.contact_name || null,
        contact_phone: form.phone || null,
        contact_email: form.email || null,
        address_line_1: fullAddress || null,
        city: form.city || null,
        state: form.state || null,
        postal_code: form.postal_code || null,
        country: form.country || 'Brazil',
        latitude: form.latitude,
        longitude: form.longitude,
        access_notes: form.access_notes || null,
        billing_notes: form.billing_notes || null,
        active: form.active,
      };

      if (isEdit && marina) {
        const updated = await update.mutateAsync({ id: marina.id, ...payload });
        toast.success(t.marinas.updateSuccess);
        onSaved?.((updated as Marina) ?? ({ ...marina, ...payload } as Marina));
      } else {
        const created = await create.mutateAsync(payload);
        toast.success(t.marinas.createSuccess);
        onSaved?.(created as Marina);
      }
      onOpenChange(false);
    } catch (err: any) {
      const msg = err?.message || err?.details
        || 'Erro ao salvar marina.';
      toast.error(msg);
      console.error('MarinaFormDialog error:', err);
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
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div className="col-span-2">
              <Label>{t.marinas.marinaName} *</Label>
              <Input required value={form.name} onChange={e => set('name', e.target.value)} />
            </div>
            <div>
              <Label>{t.marinas.contactName}</Label>
              <Input value={form.contact_name} onChange={e => set('contact_name', e.target.value)} />
            </div>
            <div>
              <Label>{t.marinas.contactPhone}</Label>
              <Input value={form.phone} onChange={e => set('phone', maskPhone(e.target.value))} placeholder="(47) 99999-9999" maxLength={15} />
            </div>
            <div className="col-span-2">
              <Label>{t.marinas.contactEmail}</Label>
              <Input type="email" value={form.email} onChange={e => set('email', e.target.value)} />
            </div>
          </div>

          <AddressFields
            showCoordinates={true}
            value={{
              postal_code: form.postal_code,
              address_line_1: form.address_line_1,
              address_number: form.address_number,
              address_complement: form.address_complement,
              neighborhood: form.neighborhood,
              city: form.city,
              state: form.state,
              country: form.country,
              latitude: form.latitude,
              longitude: form.longitude,
            }}
            onChange={(field, val) => set(field, val)}
          />

          <div className="space-y-4">
            <div>
              <Label>{t.marinas.accessNotes}</Label>
              <Textarea value={form.access_notes} onChange={e => set('access_notes', e.target.value)} />
            </div>
            <div>
              <Label>{t.marinas.billingNotes}</Label>
              <Textarea value={form.billing_notes} onChange={e => set('billing_notes', e.target.value)} />
            </div>
            <div className="flex items-center gap-2">
              <Switch checked={form.active} onCheckedChange={v => set('active', v)} />
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
