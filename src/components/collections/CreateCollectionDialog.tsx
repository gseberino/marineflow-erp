import { useEffect, useMemo, useRef, useState } from 'react';
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
import {
  escolherRecebivel, recebivelDaEscolha, saldoDoRecebivel, type RecebivelDaOS,
} from '@/lib/recebivel-da-cobranca';

/** Situações em que a cobrança ainda espera pagamento (as mesmas de criar_cobranca). */
const COBRANCA_ABERTA = ['pending', 'sent', 'viewed', 'overdue', 'disputed'];
const brl = (v: number) => v.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
const ddmm = (iso: string | null) => (iso ? iso.slice(0, 10).split('-').reverse().join('/') : '—');

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
  // A conta a receber que esta cobrança cobra (07/10/2026): sem o vínculo, a cobrança nunca
  // fica paga sozinha quando a conta é paga (gatilho sync_collection_from_receivable).
  const [contasDaOS, setContasDaOS] = useState<RecebivelDaOS[] | null>(null);
  const [erroDasContas, setErroDasContas] = useState<string | null>(null);
  const [parcelaId, setParcelaId] = useState('');
  const [jaCobrada, setJaCobrada] = useState<string | null>(null);

  const { data: clients } = useClients();
  const { data: serviceOrders } = useServiceOrders();
  const { data: templates } = useCollectionTemplates();
  const create = useCreateCollection();

  const eligibleSO = useMemo(() => {
    return (serviceOrders || []).filter(so =>
      ['completed', 'invoiced', 'in_service', 'awaiting_signature'].includes(so.status as string)
    );
  }, [serviceOrders]);

  // OS escolhida: o cliente dela e as contas a receber (para ligar a cobrança à parcela em aberto).
  // Só a troca de OS recarrega: a lista de OS sendo relida (foco na janela) não pode apagar a
  // parcela já escolhida — por isso a OS é lida pela ref, não é dependência do efeito.
  const osRef = useRef(eligibleSO);
  osRef.current = eligibleSO;
  useEffect(() => {
    setContasDaOS(null); setErroDasContas(null); setParcelaId(''); setJaCobrada(null);
    if (origin !== 'os' || !serviceOrderId) return;
    let vivo = true;
    (async () => {
      const so = osRef.current.find(s => s.id === serviceOrderId);
      if (!so) return;
      setClientId(so.client_id);
      const { data, error } = await supabase
        .from('receivables')
        .select('id, description, amount, balance_amount, due_date, status')
        .eq('service_order_id', serviceOrderId)
        .neq('status', 'cancelled')
        .order('due_date', { ascending: true })
        .limit(50);
      if (!vivo) return;
      // Leitura que falha não vira "OS sem conta": a cobrança sairia sem vínculo sem ninguém saber.
      if (error) { setErroDasContas(`Não consegui ler as contas a receber desta OS (${error.message}).`); return; }
      const contas = (data ?? []) as RecebivelDaOS[];
      setContasDaOS(contas);
      const escolha = escolherRecebivel(contas);
      if (escolha.tipo === 'uma') {
        setAmount(String(saldoDoRecebivel(escolha.recebivel)));
        setDueDate(escolha.recebivel.due_date || '');
      } else if (escolha.tipo === 'sem_conta') {
        setAmount(String(so.grand_total ?? ''));
      }
    })();
    return () => { vivo = false; };
  }, [serviceOrderId, origin]);

  const escolha = useMemo(
    () => (origin === 'os' && contasDaOS ? escolherRecebivel(contasDaOS, parcelaId) : null),
    [origin, contasDaOS, parcelaId],
  );
  const recebivel = escolha ? recebivelDaEscolha(escolha) : null;

  // A mesma parcela não ganha duas cobranças abertas (criar_cobranca recusa igual).
  useEffect(() => {
    setJaCobrada(null);
    if (!recebivel) return;
    let vivo = true;
    (async () => {
      const { data, error } = await supabase
        .from('collections')
        .select('id, amount, due_date')
        .eq('receivable_id', recebivel.id)
        .in('status', COBRANCA_ABERTA)
        .limit(1);
      if (!vivo) return;
      if (error) { setJaCobrada(`Não consegui conferir as cobranças desta parcela (${error.message}).`); return; }
      const ja = (data ?? [])[0] as { amount: number; due_date: string } | undefined;
      if (ja) setJaCobrada(`Já existe cobrança aberta para esta parcela (${brl(Number(ja.amount))}, vence ${ddmm(ja.due_date)}). Altere a existente.`);
    })();
    return () => { vivo = false; };
  }, [recebivel?.id]);

  const escolherParcela = (id: string) => {
    setParcelaId(id);
    const r = contasDaOS?.find((c) => c.id === id);
    if (r) { setAmount(String(saldoDoRecebivel(r))); setDueDate(r.due_date || ''); }
  };

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
    setContasDaOS(null); setErroDasContas(null); setParcelaId(''); setJaCobrada(null);
  };

  // Na OS: as contas lidas, a parcela escolhida quando há várias, nada pago por inteiro e sem cobrança repetida.
  const vinculoOk = origin === 'standalone' || (
    !!escolha && !erroDasContas && !jaCobrada && escolha.tipo !== 'pagas' && !(escolha.tipo === 'escolher' && !recebivel)
  );
  const canSave = clientId && amount && dueDate && (origin === 'standalone' ? description : serviceOrderId) && vinculoOk;

  const handleSave = async () => {
    if (!canSave) return;
    const tmpl = templates?.find(t => t.id === templateId);
    await create.mutateAsync({
      client_id: clientId,
      service_order_id: origin === 'os' ? serviceOrderId : null,
      receivable_id: origin === 'os' ? recebivel?.id ?? null : null,
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
              {erroDasContas && <p className="text-xs text-destructive">{erroDasContas}</p>}
              {escolha?.tipo === 'pagas' && (
                <p className="text-xs text-destructive">As contas a receber desta OS estão pagas: não há o que cobrar.</p>
              )}
              {escolha?.tipo === 'sem_conta' && (
                <p className="text-xs text-muted-foreground">
                  Esta OS ainda não tem conta a receber: a cobrança fica sem vínculo e não se marca como paga sozinha.
                </p>
              )}
              {escolha?.tipo === 'uma' && (
                <p className="text-xs text-muted-foreground">
                  Cobra «{escolha.recebivel.description ?? 'parcela'}» — fica paga sozinha quando a conta for paga.
                </p>
              )}
              {escolha?.tipo === 'escolher' && (
                <div className="space-y-1">
                  <Label>Parcela *</Label>
                  <Select value={parcelaId} onValueChange={escolherParcela}>
                    <SelectTrigger><SelectValue placeholder={`${escolha.abertas.length} parcelas em aberto — qual?`} /></SelectTrigger>
                    <SelectContent>
                      {escolha.abertas.map((r) => (
                        <SelectItem key={r.id} value={r.id}>
                          {r.description ?? 'Parcela'} · {brl(saldoDoRecebivel(r))} · vence {ddmm(r.due_date)}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              )}
              {jaCobrada && <p className="text-xs text-destructive">{jaCobrada}</p>}
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
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
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
