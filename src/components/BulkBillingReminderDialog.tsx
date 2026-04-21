import { useMemo, useState } from 'react';
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Label } from '@/components/ui/label';
import { Loader2, Send, AlertTriangle } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { useReceivables } from '@/hooks/use-financial';
import { useClients } from '@/hooks/use-clients';
import { normalizePhoneE164 } from '@/lib/masks';
import { useWhatsAppTemplates, applyTemplateVariables } from '@/hooks/use-whatsapp-templates';
import { useI18n } from '@/i18n';
import { useQueryClient } from '@tanstack/react-query';

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  /** Filtro inicial: 'overdue' (vencidas) ou 'upcoming' (vence em N dias) */
  initialFilter?: 'overdue' | 'upcoming' | 'all';
  /** Janela em dias para "upcoming" */
  upcomingDays?: number;
}

export function BulkBillingReminderDialog({ open, onOpenChange, initialFilter = 'overdue', upcomingDays = 7 }: Props) {
  const { data: receivables } = useReceivables();
  const { data: clients } = useClients();
  const { data: templates } = useWhatsAppTemplates('billing');
  const { formatCurrency, formatDate } = useI18n();
  const queryClient = useQueryClient();

  const [filter, setFilter] = useState<'overdue' | 'upcoming' | 'all'>(initialFilter);
  const [templateId, setTemplateId] = useState<string>('');
  const [customMessage, setCustomMessage] = useState<string>('');
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [sending, setSending] = useState(false);

  const clientById = useMemo(() => {
    const m = new Map<string, any>();
    (clients || []).forEach(c => m.set(c.id, c));
    return m;
  }, [clients]);

  const candidates = useMemo(() => {
    const today = new Date(); today.setHours(0,0,0,0);
    const limitUpcoming = new Date(today); limitUpcoming.setDate(limitUpcoming.getDate() + upcomingDays);
    return (receivables || [])
      .filter((r: any) => r.status !== 'paid' && r.status !== 'cancelled')
      .filter((r: any) => {
        const due = new Date(r.due_date); due.setHours(0,0,0,0);
        if (filter === 'overdue') return due < today;
        if (filter === 'upcoming') return due >= today && due <= limitUpcoming;
        return true;
      })
      .map((r: any) => {
        const client = clientById.get(r.client_id);
        const phoneRaw = client?.whatsapp || client?.phone || '';
        return {
          ...r,
          client_name: client?.full_name_or_company_name || 'Cliente',
          phone_normalized: normalizePhoneE164(phoneRaw),
          has_phone: !!normalizePhoneE164(phoneRaw),
        };
      });
  }, [receivables, clientById, filter, upcomingDays]);

  const eligible = candidates.filter(c => c.has_phone);

  // Template default ao abrir / quando mudar filtro
  useMemo(() => {
    if (!templates?.length || templateId) return;
    const preferKey = filter === 'overdue' ? 'vencida' : 'lembrete';
    const t = templates.find(x => x.name.toLowerCase().includes(preferKey)) || templates[0];
    if (t) { setTemplateId(t.id); setCustomMessage(t.body); }
  }, [templates, filter, templateId]);

  const handleTemplateChange = (id: string) => {
    setTemplateId(id);
    const tpl = templates?.find(x => x.id === id);
    if (tpl) setCustomMessage(tpl.body);
  };

  const toggleAll = () => {
    if (selectedIds.size === eligible.length) setSelectedIds(new Set());
    else setSelectedIds(new Set(eligible.map(e => e.id)));
  };

  const renderForReceivable = (r: any) => applyTemplateVariables(customMessage, {
    cliente: r.client_name,
    descricao: r.description,
    valor: formatCurrency(Number(r.balance_amount ?? r.amount)),
    vencimento: formatDate(r.due_date),
    os: r.service_order_id ? `(OS vinculada)` : '',
    link: '', // sem link público de cobrança individual
  });

  async function handleSend() {
    if (!selectedIds.size) { toast.error('Selecione ao menos uma cobrança.'); return; }
    setSending(true);
    const tId = toast.loading(`Enviando ${selectedIds.size} mensagem(ns)…`);
    let ok = 0, fail = 0;
    for (const id of selectedIds) {
      const r = eligible.find(e => e.id === id);
      if (!r) continue;
      try {
        const { data, error } = await supabase.functions.invoke('whatsapp-send', {
          body: {
            phone: r.phone_normalized,
            kind: 'text',
            message: renderForReceivable(r),
            receivable_id: r.id,
            service_order_id: r.service_order_id || undefined,
            context: 'billing_bulk',
          },
        });
        if (error || (data as any)?.error) throw new Error((data as any)?.error || error?.message);
        ok++;
      } catch (e: any) {
        console.error('bulk send error', r.id, e);
        fail++;
      }
    }
    setSending(false);
    toast.success(`${ok} enviada(s)${fail ? `, ${fail} falha(s)` : ''}.`, { id: tId });
    queryClient.invalidateQueries({ queryKey: ['whatsapp-send-status'] });
    if (!fail) onOpenChange(false);
  }

  return (
    <Dialog open={open} onOpenChange={v => !sending && onOpenChange(v)}>
      <DialogContent className="max-w-3xl">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2"><Send className="h-5 w-5" /> Cobrança em massa via WhatsApp</DialogTitle>
          <DialogDescription>Selecione cobranças e envie via Z-API com template.</DialogDescription>
        </DialogHeader>

        <div className="grid gap-4">
          <div className="flex flex-wrap items-center gap-2">
            <Label className="!mb-0">Filtro:</Label>
            <Button size="sm" variant={filter === 'overdue' ? 'default' : 'outline'} onClick={() => { setFilter('overdue'); setSelectedIds(new Set()); }}>Vencidas</Button>
            <Button size="sm" variant={filter === 'upcoming' ? 'default' : 'outline'} onClick={() => { setFilter('upcoming'); setSelectedIds(new Set()); }}>A vencer ({upcomingDays}d)</Button>
            <Button size="sm" variant={filter === 'all' ? 'default' : 'outline'} onClick={() => { setFilter('all'); setSelectedIds(new Set()); }}>Todas pendentes</Button>
          </div>

          <div>
            <Label>Template</Label>
            <select
              className="w-full h-10 rounded-md border border-input bg-background px-3 text-sm"
              value={templateId}
              onChange={e => handleTemplateChange(e.target.value)}
            >
              <option value="">— selecionar —</option>
              {(templates || []).map(t => (
                <option key={t.id} value={t.id}>{t.name}</option>
              ))}
            </select>
          </div>

          <div>
            <Label>Mensagem (use placeholders)</Label>
            <Textarea rows={4} value={customMessage} onChange={e => setCustomMessage(e.target.value)} />
            <p className="text-xs text-muted-foreground mt-1">Placeholders: {'{cliente}'} {'{descricao}'} {'{valor}'} {'{vencimento}'}</p>
          </div>

          <div className="border rounded-lg overflow-hidden">
            <div className="flex items-center justify-between px-3 py-2 bg-muted/30 border-b">
              <div className="flex items-center gap-2">
                <Checkbox
                  checked={selectedIds.size === eligible.length && eligible.length > 0}
                  onCheckedChange={toggleAll}
                />
                <span className="text-sm font-medium">
                  {selectedIds.size} de {eligible.length} selecionada(s)
                </span>
              </div>
              {candidates.length > eligible.length && (
                <span className="text-xs text-amber-700 inline-flex items-center gap-1">
                  <AlertTriangle className="h-3 w-3" />
                  {candidates.length - eligible.length} sem telefone
                </span>
              )}
            </div>
            <div className="max-h-[40vh] overflow-y-auto divide-y">
              {eligible.length === 0 && (
                <p className="p-6 text-sm text-muted-foreground text-center">Nenhuma cobrança elegível.</p>
              )}
              {eligible.map(r => (
                <label key={r.id} className="flex items-start gap-3 p-3 hover:bg-muted/30 cursor-pointer">
                  <Checkbox
                    checked={selectedIds.has(r.id)}
                    onCheckedChange={v => {
                      const next = new Set(selectedIds);
                      if (v) next.add(r.id); else next.delete(r.id);
                      setSelectedIds(next);
                    }}
                    className="mt-1"
                  />
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium truncate">{r.client_name}</p>
                    <p className="text-xs text-muted-foreground truncate">{r.description}</p>
                    <p className="text-xs">
                      <span className="font-mono">{formatCurrency(Number(r.balance_amount ?? r.amount))}</span>
                      {' • '}
                      <span>{formatDate(r.due_date)}</span>
                      {' • '}
                      <span className="text-muted-foreground">{r.phone_normalized}</span>
                    </p>
                  </div>
                </label>
              ))}
            </div>
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={sending}>Cancelar</Button>
          <Button onClick={handleSend} disabled={sending || !selectedIds.size} className="gap-2">
            {sending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
            Enviar {selectedIds.size || ''}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
