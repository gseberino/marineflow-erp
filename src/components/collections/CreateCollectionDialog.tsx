import { useEffect, useMemo, useState } from 'react';
import {
  Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import { Switch } from '@/components/ui/switch';
import { ClientCombobox } from '@/components/ClientCombobox';
import { useClients } from '@/hooks/use-clients';
import { useServiceOrders } from '@/hooks/use-service-orders';
import { useCollectionTemplates, useCreateCollection } from '@/hooks/use-collections';
import { supabase } from '@/integrations/supabase/client';
import { maskPhone } from '@/lib/masks';

interface Props { open: boolean; onOpenChange: (v: boolean) => void }

export function CreateCollectionDialog({ open, onOpenChange }: Props) {
  const [origin, setOrigin] = useState<'os' | 'standalone'>('os');
  const [serviceOrderId, setServiceOrderId] = useState('');
  const [clientId, setClientId] = useState('');
  const [description, setDescription] = useState('');
  const [amount, setAmount] = useState('');
  const [dueDate, setDueDate] = useState('');
  const [contactName, setContactName] = useState('');
  const [contactPhone, setContactPhone] = useState('');
  const [contactWhatsapp, setContactWhatsapp] = useState('');
  const [overrideContact, setOverrideContact] = useState(false);
  const [templateId, setTemplateId] = useState<string>('');
  const [sendMethod, setSendMethod] = useState<'text_link' | 'text' | 'pdf'>('text_link');
  const [autoRule, setAutoRule] = useState(false);

  const { data: clients } = useClients();
  const { data: serviceOrders } = useServiceOrders();
  const { data: templates } = useCollectionTemplates();
  const create = useCreateCollection();

  const eligibleSO = useMemo(() => {
    return (serviceOrders || []).filter(so =>
      ['completed', 'invoiced', 'in_service', 'awaiting_signature'].includes(so.status as string)
    );
  }, [serviceOrders]);

  // Auto-fill from selected SO
  useEffect(() => {
    if (origin !== 'os' || !serviceOrderId) return;
    (async () => {
      const so = eligibleSO.find(s => s.id === serviceOrderId);
      if (!so) return;
      setClientId(so.client_id);
      const { data: rec } = await supabase
        .from('receivables')
        .select('id, amount, balance_amount, due_date')
        .eq('service_order_id', serviceOrderId)
        .order('due_date', { ascending: false })
        .limit(1)
        .maybeSingle();
      if (rec) {
        setAmount(String(rec.balance_amount ?? rec.amount ?? so.grand_total ?? ''));
        setDueDate(rec.due_date || '');
      } else {
        setAmount(String(so.grand_total ?? ''));
      }
    })();
  }, [serviceOrderId, origin, eligibleSO]);

  // Default contact from client
  const selectedClient = clients?.find(c => c.id === clientId);
  useEffect(() => {
    if (overrideContact || !selectedClient) return;
    setContactName(selectedClient.name);
    setContactPhone(selectedClient.phone || '');
    setContactWhatsapp(selectedClient.whatsapp || selectedClient.phone || '');
  }, [selectedClient, overrideContact]);

  // Default template
  useEffect(() => {
    if (!templateId && templates?.length) {
      const def = templates.find(t => t.is_default) || templates[0];
      if (def) {
        setTemplateId(def.id);
        setSendMethod(def.send_method);
      }
    }
  }, [templates, templateId]);

  const reset = () => {
    setOrigin('os'); setServiceOrderId(''); setClientId(''); setDescription('');
    setAmount(''); setDueDate(''); setContactName(''); setContactPhone('');
    setContactWhatsapp(''); setOverrideContact(false); setTemplateId('');
    setSendMethod('text_link'); setAutoRule(false);
  };

  const canSave = clientId && amount && dueDate && (origin === 'standalone' ? description : serviceOrderId);

  const handleSave = async () => {
    if (!canSave) return;
    const tmpl = templates?.find(t => t.id === templateId);
    await create.mutateAsync({
      client_id: clientId,
      service_order_id: origin === 'os' ? serviceOrderId : null,
      description: origin === 'standalone' ? description : null,
      standalone_amount: origin === 'standalone' ? Number(amount) : null,
      amount: Number(amount),
      due_date: dueDate,
      contact_name: contactName || null,
      phone: contactPhone || null,
      contact_whatsapp: contactWhatsapp || null,
      send_method: sendMethod,
      message_template: tmpl?.body || null,
      auto_rule_enabled: autoRule,
      status: 'pending',
    });
    reset();
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={(v) => { if (!v) reset(); onOpenChange(v); }}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader><DialogTitle>Nova Cobrança</DialogTitle></DialogHeader>

        <div className="grid gap-4 py-2">
          <div className="flex gap-2">
            <Button type="button" variant={origin === 'os' ? 'default' : 'outline'} size="sm"
              onClick={() => setOrigin('os')}>Vinculada a OS</Button>
            <Button type="button" variant={origin === 'standalone' ? 'default' : 'outline'} size="sm"
              onClick={() => setOrigin('standalone')}>Avulsa</Button>
          </div>

          {origin === 'os' ? (
            <div className="space-y-2">
              <Label>Ordem de Serviço</Label>
              <Select value={serviceOrderId} onValueChange={setServiceOrderId}>
                <SelectTrigger><SelectValue placeholder="Selecionar OS..." /></SelectTrigger>
                <SelectContent>
                  {eligibleSO.map(so => (
                    <SelectItem key={so.id} value={so.id}>
                      {so.service_order_number} — {(so as any).client?.name || 'Cliente'}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          ) : (
            <div className="space-y-2">
              <Label>Descrição</Label>
              <Textarea value={description} onChange={e => setDescription(e.target.value)}
                placeholder="Descrição da cobrança avulsa" rows={2} />
            </div>
          )}

          <div className="space-y-2">
            <Label>Cliente</Label>
            <ClientCombobox value={clientId} onChange={(id) => setClientId(id)} clients={clients} />
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label>Valor (R$)</Label>
              <Input type="number" step="0.01" value={amount} onChange={e => setAmount(e.target.value)} />
            </div>
            <div className="space-y-2">
              <Label>Vencimento</Label>
              <Input type="date" value={dueDate} onChange={e => setDueDate(e.target.value)} />
            </div>
          </div>

          <div className="border-t pt-3 space-y-2">
            <div className="flex items-center justify-between">
              <Label className="text-sm font-semibold">Contato para envio</Label>
              <div className="flex items-center gap-2 text-xs">
                <span className="text-muted-foreground">Sobrescrever</span>
                <Switch checked={overrideContact} onCheckedChange={setOverrideContact} />
              </div>
            </div>
            <div className="grid grid-cols-3 gap-3">
              <Input placeholder="Nome" value={contactName} onChange={e => setContactName(e.target.value)} disabled={!overrideContact && !!selectedClient} />
              <Input placeholder="Telefone" value={contactPhone}
                onChange={e => setContactPhone(maskPhone(e.target.value))} disabled={!overrideContact && !!selectedClient} />
              <Input placeholder="WhatsApp" value={contactWhatsapp}
                onChange={e => setContactWhatsapp(maskPhone(e.target.value))} disabled={!overrideContact && !!selectedClient} />
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label>Template</Label>
              <Select value={templateId} onValueChange={(v) => {
                setTemplateId(v);
                const t = templates?.find(x => x.id === v);
                if (t) setSendMethod(t.send_method);
              }}>
                <SelectTrigger><SelectValue placeholder="Template..." /></SelectTrigger>
                <SelectContent>
                  {(templates || []).map(t => (
                    <SelectItem key={t.id} value={t.id}>{t.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label>Método de envio</Label>
              <Select value={sendMethod} onValueChange={(v: any) => setSendMethod(v)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="text_link">Texto + Link</SelectItem>
                  <SelectItem value="text">Só texto</SelectItem>
                  <SelectItem value="pdf">PDF anexo</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>

          <div className="flex items-center justify-between rounded-lg border p-3">
            <div>
              <Label>Régua automática</Label>
              <p className="text-xs text-muted-foreground">Envia lembretes antes/depois do vencimento</p>
            </div>
            <Switch checked={autoRule} onCheckedChange={setAutoRule} />
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancelar</Button>
          <Button onClick={handleSave} disabled={!canSave || create.isPending}>
            {create.isPending ? 'Salvando...' : 'Salvar'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
