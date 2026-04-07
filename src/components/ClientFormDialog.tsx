import { useState, useEffect } from 'react';
import { useI18n } from '@/i18n';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useCreateClient, useUpdateClient, type Client } from '@/hooks/use-clients';
import { toast } from 'sonner';
import type { TablesInsert } from '@/integrations/supabase/types';

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  client?: Client | null;
}

const empty: TablesInsert<'clients'> = {
  type: 'individual',
  full_name_or_company_name: '',
  cpf_cnpj: '',
  phone: '',
  whatsapp: '',
  email: '',
  address_line_1: '',
  address_line_2: '',
  city: '',
  state: '',
  postal_code: '',
  country: 'Brazil',
  notes: '',
  active: true,
};

export function ClientFormDialog({ open, onOpenChange, client }: Props) {
  const { t } = useI18n();
  const create = useCreateClient();
  const update = useUpdateClient();
  const [form, setForm] = useState<TablesInsert<'clients'>>(empty);
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
        address_line_1: client.address_line_1 ?? '',
        address_line_2: client.address_line_2 ?? '',
        city: client.city ?? '',
        state: client.state ?? '',
        postal_code: client.postal_code ?? '',
        country: client.country ?? 'Brazil',
        notes: client.notes ?? '',
        active: client.active,
      });
    } else {
      setForm(empty);
    }
  }, [client, open]);

  const set = (key: string, value: string | boolean) => setForm(prev => ({ ...prev, [key]: value }));

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      if (isEdit && client) {
        await update.mutateAsync({ id: client.id, ...form });
        toast.success(t.clients.updateSuccess);
      } else {
        await create.mutateAsync(form);
        toast.success(t.clients.createSuccess);
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
              <Input value={form.cpf_cnpj ?? ''} onChange={e => set('cpf_cnpj', e.target.value)} />
            </div>
            <div>
              <Label>{t.clients.email}</Label>
              <Input type="email" value={form.email ?? ''} onChange={e => set('email', e.target.value)} />
            </div>
            <div>
              <Label>{t.clients.phone}</Label>
              <Input value={form.phone ?? ''} onChange={e => set('phone', e.target.value)} />
            </div>
            <div>
              <Label>{t.clients.whatsapp}</Label>
              <Input value={form.whatsapp ?? ''} onChange={e => set('whatsapp', e.target.value)} />
            </div>
            <div className="col-span-2">
              <Label>{t.clients.addressLine1}</Label>
              <Input value={form.address_line_1 ?? ''} onChange={e => set('address_line_1', e.target.value)} />
            </div>
            <div className="col-span-2">
              <Label>{t.clients.addressLine2}</Label>
              <Input value={form.address_line_2 ?? ''} onChange={e => set('address_line_2', e.target.value)} />
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
            <div className="col-span-2">
              <Label>{t.common.notes}</Label>
              <Textarea value={form.notes ?? ''} onChange={e => set('notes', e.target.value)} />
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
