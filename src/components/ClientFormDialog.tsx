import { useState, useEffect } from 'react';
import { useI18n } from '@/i18n';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { AddressFields } from '@/components/AddressFields';
import { useCreateClient, useUpdateClient, type Client } from '@/hooks/use-clients';
import { toast } from 'sonner';
import type { TablesInsert } from '@/integrations/supabase/types';

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  client?: Client | null;
  initialName?: string;
  onCreated?: (client: { id: string; full_name_or_company_name: string }) => void;
}

const empty = {
  type: 'individual' as string,
  full_name_or_company_name: '',
  cpf_cnpj: '',
  phone: '',
  whatsapp: '',
  email: '',
  postal_code: '',
  address_line_1: '',
  address_number: '',
  address_complement: '',
  neighborhood: '',
  address_line_2: '',
  city: '',
  state: '',
  country: 'Brazil',
  notes: '',
  active: true,
};

export function ClientFormDialog({ open, onOpenChange, client, initialName, onCreated }: Props) {
  const { t } = useI18n();
  const create = useCreateClient();
  const update = useUpdateClient();
  const [form, setForm] = useState(empty);
  const isEdit = !!client;

  useEffect(() => {
    if (client) {
      setForm({
        type: client.type,
        full_name_or_company_name: client.full_name_or_company_name,
        cpf_cnpj: client.cpf_cnpj ?? '',
        phone: client.phone ?? '',
        whatsapp: client.whatsapp ?? '',
        email: client.email ?? '',
        postal_code: client.postal_code ?? '',
        address_line_1: client.address_line_1 ?? '',
        address_number: '',
        address_complement: '',
        neighborhood: '',
        address_line_2: client.address_line_2 ?? '',
        city: client.city ?? '',
        state: client.state ?? '',
        country: client.country ?? 'Brazil',
        notes: client.notes ?? '',
        active: client.active,
      });
    } else {
      setForm({ ...empty, full_name_or_company_name: initialName || '' });
    }
  }, [client, open, initialName]);

  const set = (key: string, value: string | boolean | number | null) => setForm(prev => ({ ...prev, [key]: value as any }));

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const fullAddress = [form.address_line_1, form.address_number, form.address_complement].filter(Boolean).join(', ');
      const payload: TablesInsert<'clients'> = {
        type: form.type,
        full_name_or_company_name: form.full_name_or_company_name,
        cpf_cnpj: form.cpf_cnpj || null,
        phone: form.phone || null,
        whatsapp: form.whatsapp || null,
        email: form.email || null,
        address_line_1: fullAddress || null,
        address_line_2: form.address_line_2 || null,
        city: form.city || null,
        state: form.state || null,
        postal_code: form.postal_code || null,
        country: form.country || 'Brazil',
        notes: form.notes || null,
        active: form.active,
      };

      if (isEdit && client) {
        await update.mutateAsync({ id: client.id, ...payload });
        toast.success(t.clients.updateSuccess);
      } else {
        const result = await create.mutateAsync(payload);
        toast.success(t.clients.createSuccess);
        if (onCreated && result) {
          onCreated({ id: result.id, full_name_or_company_name: result.full_name_or_company_name });
        }
      }
      onOpenChange(false);
    } catch (err: any) {
      toast.error(err.message);
    }
  };

  const isPending = create.isPending || update.isPending;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{isEdit ? t.clients.editClient : t.clients.newClient}</DialogTitle>
        </DialogHeader>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <div className="col-span-2">
              <Label>{t.common.type}</Label>
              <Select value={form.type} onValueChange={v => set('type', v)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="individual">{t.common.individual}</SelectItem>
                  <SelectItem value="company">{t.common.company}</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="col-span-2">
              <Label>{t.clients.fullName} *</Label>
              <Input required value={form.full_name_or_company_name} onChange={e => set('full_name_or_company_name', e.target.value)} />
            </div>
            <div>
              <Label>{form.type === 'company' ? t.clients.cnpj : t.clients.cpf}</Label>
              <Input value={form.cpf_cnpj} onChange={e => set('cpf_cnpj', e.target.value)} />
            </div>
            <div>
              <Label>{t.clients.email}</Label>
              <Input type="email" value={form.email} onChange={e => set('email', e.target.value)} />
            </div>
            <div>
              <Label>{t.clients.phone}</Label>
              <Input value={form.phone} onChange={e => set('phone', e.target.value)} />
            </div>
            <div>
              <Label>{t.clients.whatsapp}</Label>
              <Input value={form.whatsapp} onChange={e => set('whatsapp', e.target.value)} />
            </div>
          </div>

          <AddressFields
            showCoordinates={false}
            value={{
              postal_code: form.postal_code,
              address_line_1: form.address_line_1,
              address_number: form.address_number,
              address_complement: form.address_complement,
              neighborhood: form.neighborhood,
              city: form.city,
              state: form.state,
              country: form.country,
            }}
            onChange={(field, val) => set(field, val)}
          />

          <div className="space-y-4">
            <div>
              <Label>{t.common.notes}</Label>
              <Textarea value={form.notes} onChange={e => set('notes', e.target.value)} />
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
