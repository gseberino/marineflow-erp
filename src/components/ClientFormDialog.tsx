import { useState, useEffect } from 'react';
import { useI18n } from '@/i18n';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { AddressFields } from '@/components/AddressFields';
import { useCreateClient, useUpdateClient, type Client } from '@/hooks/use-clients';
import { useCnpj } from '@/hooks/use-cnpj';
import { toast } from 'sonner';
import type { TablesInsert } from '@/integrations/supabase/types';
import { maskCPF, maskCNPJ, maskPhone } from '@/lib/masks';
import {
  useClientWhatsAppSettings,
  useUpsertClientWhatsAppSetting,
  useDeleteClientWhatsAppSetting,
  pickClientSetting,
  type ClientWhatsAppContext,
} from '@/hooks/use-client-whatsapp-settings';
import { Trash2, Search, Loader2 } from 'lucide-react';

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  client?: Client | null;
  initialName?: string;
  onCreated?: (client: { id: string; name: string }) => void;
}

const empty = {
  type: 'individual' as string,
  name: '',
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
  const { cnpjLoading, fetchByCnpj } = useCnpj();
  const [form, setForm] = useState(empty);
  const isEdit = !!client;

  useEffect(() => {
    if (client) {
      setForm({
        type: client.type,
        name: client.full_name_or_company_name,
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
      setForm({ ...empty, name: initialName || '' });
    }
  }, [client, open, initialName]);

  const set = (key: string, value: string | boolean | number | null) => setForm(prev => ({ ...prev, [key]: value as any }));

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const fullAddress = [form.address_line_1, form.address_number, form.address_complement].filter(Boolean).join(', ');
      const payload: TablesInsert<'clients'> = {
        type: form.type,
        full_name_or_company_name: form.name,
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
          onCreated({ id: result.id, name: result.full_name_or_company_name });
        }
      }
      onOpenChange(false);
    } catch (err: any) {
      const msg = err?.message || err?.details
        || 'Erro ao salvar cliente.';
      toast.error(msg);
      console.error('ClientFormDialog error:', err);
    }
  };

  const handleCnpjSearch = async () => {
    if (!form.cpf_cnpj || form.cpf_cnpj.length < 14) return;
    const data = await fetchByCnpj(form.cpf_cnpj);
    if (data) {
      setForm(prev => ({
        ...prev,
        name: data.nome_fantasia || data.razao_social || prev.name,
        postal_code: data.cep || prev.postal_code,
        address_line_1: data.logradouro || prev.address_line_1,
        address_number: data.numero || prev.address_number,
        address_complement: data.complemento || prev.address_complement,
        neighborhood: data.bairro || prev.neighborhood,
        city: data.municipio || prev.city,
        state: data.uf || prev.state,
        phone: data.ddd_telefone_1 || prev.phone,
        email: data.email || prev.email,
      }));
      toast.success('Dados preenchidos via Receita Federal');
    }
  };

  const isPending = create.isPending || update.isPending;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{isEdit ? t.clients.editClient : t.clients.newClient}</DialogTitle>
        </DialogHeader>
        <Tabs defaultValue="data" className="w-full">
          <TabsList className="grid grid-cols-2 w-full">
            <TabsTrigger value="data">Dados do cliente</TabsTrigger>
            <TabsTrigger value="zapi" disabled={!isEdit}>
              WhatsApp / Z-API
            </TabsTrigger>
          </TabsList>

          <TabsContent value="data">
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
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
              <Input required value={form.name} onChange={e => set('name', e.target.value)} />
            </div>
            <div className="col-span-2">
              <Label>{form.type === 'company' ? t.clients.cnpj : t.clients.cpf}</Label>
              <div className="flex gap-2">
                <Input
                  value={form.cpf_cnpj}
                  onChange={e => set('cpf_cnpj', form.type === 'company' ? maskCNPJ(e.target.value) : maskCPF(e.target.value))}
                  placeholder={form.type === 'company' ? '00.000.000/0001-00' : '000.000.000-00'}
                  maxLength={form.type === 'company' ? 18 : 14}
                />
                {form.type === 'company' && (
                  <Button type="button" variant="outline" onClick={handleCnpjSearch} disabled={cnpjLoading || form.cpf_cnpj.length < 14}>
                    {cnpjLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : <Search className="h-4 w-4" />}
                  </Button>
                )}
              </div>
            </div>
            <div>
              <Label>{t.clients.email}</Label>
              <Input type="email" value={form.email} onChange={e => set('email', e.target.value)} />
            </div>
            <div>
              <Label>{t.clients.phone}</Label>
              <Input value={form.phone} onChange={e => set('phone', maskPhone(e.target.value))} placeholder="(47) 99999-9999" maxLength={15} />
            </div>
            <div>
              <Label>{t.clients.whatsapp}</Label>
              <Input value={form.whatsapp} onChange={e => set('whatsapp', maskPhone(e.target.value))} placeholder="(47) 99999-9999" maxLength={15} />
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
          </TabsContent>

          <TabsContent value="zapi">
            {isEdit && client ? (
              <ZapiSettingsTab clientId={client.id} />
            ) : (
              <p className="text-sm text-muted-foreground py-6 text-center">
                Salve o cliente primeiro para configurar mensagens Z-API.
              </p>
            )}
          </TabsContent>
        </Tabs>
      </DialogContent>
    </Dialog>
  );
}

// ----------------- Aba Z-API -----------------

const CONTEXT_LABELS: Record<ClientWhatsAppContext, string> = {
  service_order: 'Ordem de Serviço',
  quote: 'Orçamento',
  billing: 'Cobrança / Recibo',
};

const PLACEHOLDER_HINT = 'Variáveis: {cliente} {os} {descricao} {valor} {vencimento} {link}';

function ZapiSettingsTab({ clientId }: { clientId: string }) {
  const { data: settings, isLoading } = useClientWhatsAppSettings(clientId);
  const upsert = useUpsertClientWhatsAppSetting();
  const remove = useDeleteClientWhatsAppSetting();
  const [activeCtx, setActiveCtx] = useState<ClientWhatsAppContext>('service_order');

  const current = pickClientSetting(settings, activeCtx);
  const [draft, setDraft] = useState({
    message_body: '',
    link_title: '',
    link_description: '',
    pdf_filename_pattern: '',
  });

  useEffect(() => {
    setDraft({
      message_body: current?.message_body ?? '',
      link_title: current?.link_title ?? '',
      link_description: current?.link_description ?? '',
      pdf_filename_pattern: current?.pdf_filename_pattern ?? '',
    });
  }, [activeCtx, current?.id]);

  const handleSave = async () => {
    await upsert.mutateAsync({
      client_id: clientId,
      context: activeCtx,
      message_body: draft.message_body || null,
      link_title: draft.link_title || null,
      link_description: draft.link_description || null,
      pdf_filename_pattern: draft.pdf_filename_pattern || null,
    });
  };

  const handleClear = async () => {
    if (!current) return;
    if (!confirm(`Remover configuração de "${CONTEXT_LABELS[activeCtx]}"?`)) return;
    await remove.mutateAsync({ client_id: clientId, context: activeCtx });
  };

  if (isLoading) {
    return <p className="text-sm text-muted-foreground py-6 text-center">Carregando…</p>;
  }

  return (
    <div className="space-y-4 pt-2">
      <div className="flex flex-wrap gap-1.5">
        {(Object.keys(CONTEXT_LABELS) as ClientWhatsAppContext[]).map(ctx => {
          const has = !!pickClientSetting(settings, ctx);
          const isActive = ctx === activeCtx;
          return (
            <button
              key={ctx}
              type="button"
              onClick={() => setActiveCtx(ctx)}
              className={`px-3 py-1.5 rounded-md text-sm border transition-colors ${
                isActive
                  ? 'bg-primary text-primary-foreground border-primary'
                  : 'bg-background hover:bg-muted border-input'
              }`}
            >
              {CONTEXT_LABELS[ctx]}
              {has && <span className="ml-1.5 text-xs opacity-70">●</span>}
            </button>
          );
        })}
      </div>

      <p className="text-xs text-muted-foreground">{PLACEHOLDER_HINT}</p>

      <div className="space-y-3">
        <div>
          <Label>Mensagem (corpo)</Label>
          <Textarea
            rows={4}
            value={draft.message_body}
            onChange={e => setDraft(d => ({ ...d, message_body: e.target.value }))}
            placeholder="Olá {cliente}, segue {descricao}…"
          />
        </div>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div>
            <Label>Título do link (preview)</Label>
            <Input
              value={draft.link_title}
              onChange={e => setDraft(d => ({ ...d, link_title: e.target.value }))}
              placeholder="OS {os}"
            />
          </div>
          <div>
            <Label>Descrição do link (preview)</Label>
            <Input
              value={draft.link_description}
              onChange={e => setDraft(d => ({ ...d, link_description: e.target.value }))}
              placeholder="Toque para visualizar"
            />
          </div>
        </div>
        <div>
          <Label>Padrão do nome do arquivo PDF</Label>
          <Input
            value={draft.pdf_filename_pattern}
            onChange={e => setDraft(d => ({ ...d, pdf_filename_pattern: e.target.value }))}
            placeholder="OS-{os}-{cliente}.pdf"
          />
        </div>
      </div>

      <div className="flex justify-between items-center pt-2 border-t">
        <Button
          type="button"
          variant="ghost"
          size="sm"
          onClick={handleClear}
          disabled={!current || remove.isPending}
          className="text-destructive hover:text-destructive"
        >
          <Trash2 className="h-4 w-4 mr-1" /> Limpar
        </Button>
        <Button type="button" onClick={handleSave} disabled={upsert.isPending}>
          Salvar mensagem
        </Button>
      </div>
    </div>
  );
}
