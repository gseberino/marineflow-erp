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
import {
  useServiceSystems, AXIS_LABEL, DEPENDS_ON_ORDER, DEPENDS_ON_ORDER_LABEL,
  systemChoiceToDb, systemDbToChoice,
} from '@/hooks/use-service-systems';
import { VERBOS, VERB_LABEL } from '@/hooks/use-service-classification';

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
  const { data: sistemas = [] } = useServiceSystems();

  // `category` (texto livre) foi aposentado em 02/08: estava vazio em 257 dos
  // 262 serviços e concorria com service_system, que é o que de fato classifica
  // — é ele que traz a abertura e o fechamento de segurança do roteiro.
  const VAZIO = {
    name: '',
    description: '',
    service_system: '',
    service_verb: '',
    billing_unit: 'hour',
    default_price: 0,
    currency: 'BRL',
    active: true,
    default_warranty_days: 0,
  };
  const [form, setForm] = useState(VAZIO);

  useEffect(() => {
    if (editData) {
      setForm({
        name: editData.name || '',
        description: editData.description || '',
        service_system: editData.service_system || '',
        service_verb: editData.service_verb || '',
        billing_unit: editData.billing_unit || 'hour',
        default_price: editData.default_price || 0,
        currency: editData.currency || 'BRL',
        active: editData.active ?? true,
        default_warranty_days: editData.default_warranty_days ?? 0,
      });
    } else {
      setForm(VAZIO);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [editData, open]);

  const set = (field: string, value: any) => setForm((p) => ({ ...p, [field]: value }));

  const handleSave = async () => {
    if (!form.name.trim()) return;
    try {
      // A coluna é `name`. O código antigo mandava `service_name`, que não
      // existe no schema — salvar por este diálogo falhava em silêncio para
      // quem não olhava o toast de erro.
      // Vazio vira null de propósito: '' violaria a FK de service_systems, e
      // sistema nulo tem significado ("depende da OS").
      const payload = {
        ...form,
        service_system: form.service_system || null,
        service_verb: form.service_verb || null,
      };
      if (editData?.id) {
        await update.mutateAsync({ id: editData.id, ...payload });
        toast.success(t.services.updateSuccess);
      } else {
        const result = await create.mutateAsync(payload);
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
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{editData ? t.services.editService : t.services.newService}</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <div>
            <Label>{t.services.serviceName} *</Label>
            <Input value={form.name} onChange={(e) => set('name', e.target.value)} className="mt-1" />
          </div>
          <div>
            <Label>{t.common.description}</Label>
            <Textarea value={form.description} onChange={(e) => set('description', e.target.value)} rows={2} className="mt-1" />
          </div>
          {/* Os dois eixos que geram o roteiro. O sistema decide a preparação e
              o fechamento de segurança; o verbo decide o corpo. Deixar o sistema
              em branco é dizer "depende da OS" — aí quem monta a OS escolhe. */}
          <div className="grid gap-4 sm:grid-cols-2">
            <div>
              <Label>{AXIS_LABEL}</Label>
              <Select
                value={systemDbToChoice(form.service_system)}
                onValueChange={(v) => set('service_system', systemChoiceToDb(v) ?? '')}
              >
                <SelectTrigger className="mt-1">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {/* Primeiro item de propósito: é a escolha que transforma o
                      serviço em genérico, e antes ela não existia. */}
                  <SelectItem value={DEPENDS_ON_ORDER}>{DEPENDS_ON_ORDER_LABEL}</SelectItem>
                  {sistemas.map((s) => (
                    <SelectItem key={s.slug} value={s.slug}>{s.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {!form.service_system && (
                <p className="mt-1 text-[11px] text-muted-foreground">
                  Cada OS vai perguntar qual sistema este serviço toca — e o roteiro sai diferente
                  conforme a resposta.
                </p>
              )}
            </div>
            <div>
              <Label>O que se faz (verbo)</Label>
              <Select value={form.service_verb} onValueChange={(v) => set('service_verb', v)}>
                <SelectTrigger className="mt-1">
                  <SelectValue placeholder="Não definido" />
                </SelectTrigger>
                <SelectContent>
                  {VERBOS.map((v) => (
                    <SelectItem key={v} value={v}>{VERB_LABEL[v] ?? v}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4">
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
          <div className="flex items-center gap-4">
            <div className="flex items-center gap-2">
              <Switch checked={form.active} onCheckedChange={(v) => set('active', v)} />
              <Label>{t.common.active}</Label>
            </div>
            <div className="flex-1">
              <Label className="text-xs">Garantia Padrão (dias)</Label>
              <Input type="number" min="0" value={(form as any).default_warranty_days ?? 0} onChange={(e) => set('default_warranty_days', Number(e.target.value))} />
            </div>
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
