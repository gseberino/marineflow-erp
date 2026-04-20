import { useState, useEffect } from 'react';
import { useI18n } from '@/i18n';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { AddressFields } from '@/components/AddressFields';
import { useCreateSupplier, useUpdateSupplier, type Supplier } from '@/hooks/use-suppliers';
import { toast } from 'sonner';
import type { TablesInsert } from '@/integrations/supabase/types';
import { maskCPFCNPJ, maskPhone } from '@/lib/masks';

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  supplier?: Supplier | null;
}

const empty = {
  supplier_name: '',
  trade_name: '',
  cnpj_cpf: '',
  contact_name: '',
  contact_phone: '',
  contact_email: '',
  website: '',
  postal_code: '',
  address_line_1: '',
  address_number: '',
  address_complement: '',
  neighborhood: '',
  city: '',
  state: '',
  country: 'Brazil',
  payment_terms: '',
  notes: '',
  active: true,
};

export function SupplierFormDialog({ open, onOpenChange, supplier }: Props) {
  const { t } = useI18n();
  const create = useCreateSupplier();
  const update = useUpdateSupplier();
  const [form, setForm] = useState(empty);
  const isEdit = !!supplier;

  useEffect(() => {
    if (supplier) {
      setForm({
        supplier_name: supplier.supplier_name,
        trade_name: supplier.trade_name ?? '',
        cnpj_cpf: supplier.cnpj_cpf ?? '',
        contact_name: supplier.contact_name ?? '',
        contact_phone: supplier.contact_phone ?? '',
        contact_email: supplier.contact_email ?? '',
        website: supplier.website ?? '',
        postal_code: supplier.postal_code ?? '',
        address_line_1: supplier.address_line_1 ?? '',
        address_number: supplier.address_number ?? '',
        address_complement: supplier.address_complement ?? '',
        neighborhood: supplier.neighborhood ?? '',
        city: supplier.city ?? '',
        state: supplier.state ?? '',
        country: supplier.country ?? 'Brazil',
        payment_terms: supplier.payment_terms ?? '',
        notes: supplier.notes ?? '',
        active: supplier.active,
      });
    } else {
      setForm(empty);
    }
  }, [supplier, open]);

  const set = (key: string, value: any) => setForm(prev => ({ ...prev, [key]: value }));

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const fullAddress = [form.address_line_1, form.address_number, form.address_complement].filter(Boolean).join(', ');
      const payload: TablesInsert<'suppliers'> = {
        supplier_name: form.supplier_name,
        trade_name: form.trade_name || null,
        cnpj_cpf: form.cnpj_cpf || null,
        contact_name: form.contact_name || null,
        contact_phone: form.contact_phone || null,
        contact_email: form.contact_email || null,
        website: form.website || null,
        postal_code: form.postal_code || null,
        address_line_1: fullAddress || null,
        address_number: form.address_number || null,
        address_complement: form.address_complement || null,
        neighborhood: form.neighborhood || null,
        city: form.city || null,
        state: form.state || null,
        country: form.country || 'Brazil',
        payment_terms: form.payment_terms || null,
        notes: form.notes || null,
        active: form.active,
      };

      if (isEdit && supplier) {
        await update.mutateAsync({ id: supplier.id, ...payload });
        toast.success(t.suppliers.updateSuccess);
      } else {
        await create.mutateAsync(payload);
        toast.success(t.suppliers.createSuccess);
      }
      onOpenChange(false);
    } catch (err: any) {
      const msg = err?.message || err?.details
        || 'Erro ao salvar fornecedor.';
      toast.error(msg);
      console.error('SupplierFormDialog error:', err);
    }
  };

  const isPending = create.isPending || update.isPending;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{isEdit ? t.suppliers.editSupplier : t.suppliers.newSupplier}</DialogTitle>
        </DialogHeader>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <Label>{t.suppliers.supplierName} *</Label>
            <Input required value={form.supplier_name} onChange={e => set('supplier_name', e.target.value)} />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <Label>{t.suppliers.tradeName}</Label>
              <Input value={form.trade_name} onChange={e => set('trade_name', e.target.value)} />
            </div>
            <div>
              <Label>{t.suppliers.cnpj}</Label>
              <Input value={form.cnpj_cpf} onChange={e => set('cnpj_cpf', maskCPFCNPJ(e.target.value))} placeholder="00.000.000/0001-00" maxLength={18} />
            </div>
            <div>
              <Label>{t.suppliers.contactName}</Label>
              <Input value={form.contact_name} onChange={e => set('contact_name', e.target.value)} />
            </div>
            <div>
              <Label>{t.clients.phone}</Label>
              <Input value={form.contact_phone} onChange={e => set('contact_phone', maskPhone(e.target.value))} placeholder="(47) 99999-9999" maxLength={15} />
            </div>
            <div>
              <Label>{t.clients.email}</Label>
              <Input type="email" value={form.contact_email} onChange={e => set('contact_email', e.target.value)} />
            </div>
            <div>
              <Label>Website</Label>
              <Input value={form.website} onChange={e => set('website', e.target.value)} />
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

          <div className="grid grid-cols-2 gap-4">
            <div className="col-span-2">
              <Label>{t.suppliers.paymentTerms}</Label>
              <Input value={form.payment_terms} onChange={e => set('payment_terms', e.target.value)} />
            </div>
            <div className="col-span-2">
              <Label>{t.common.notes}</Label>
              <Textarea value={form.notes} onChange={e => set('notes', e.target.value)} />
            </div>
            <div className="flex items-center gap-2 col-span-2">
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
