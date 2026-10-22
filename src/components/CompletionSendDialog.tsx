// Prompt OPT-IN de conclusão: ao concluir a OS, pergunta se deseja enviar ao cliente a mensagem
// de "serviço concluído" (com o saldo pendente, quando houver). Nada é enviado sem o usuário
// confirmar. Usa a edge whatsapp-send (kind:'text'), que respeita wa_test_mode.
import { useEffect, useRef, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Loader2, Send, CheckCircle2 } from 'lucide-react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { useAppSettings } from '@/hooks/use-app-settings';
import { buildCompletionMessage } from '@/lib/completion-message';

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  serviceOrderId: string;
  osNumber: string;
  clientName?: string | null;
  clientPhone?: string | null;
  balance?: number | null;
  dueDate?: string | null;
  /** Tipo da unidade da OS (para o emoji). Ausente: o diálogo lê pela OS. */
  assetType?: string | null;
}

const fmtBRL = (v: number) =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);

export function CompletionSendDialog({
  open, onOpenChange, serviceOrderId, osNumber, clientName, clientPhone, balance, dueDate, assetType,
}: Props) {
  const [phone, setPhone] = useState('');
  const [message, setMessage] = useState('');
  const [sending, setSending] = useState(false);
  const { data: settingsMap } = useAppSettings();
  const pixKey = settingsMap?.['pix_key'] ?? null;
  // O tipo da unidade só decide o emoji (🛥️/🚐): leitura leve; se falhar, a mensagem sai sem emoji.
  const { data: tipoLido } = useQuery({
    queryKey: ['tipo-da-unidade-da-os', serviceOrderId],
    enabled: open && assetType === undefined && !!serviceOrderId,
    staleTime: 60_000,
    queryFn: async () => {
      const { data, error } = await supabase.from('service_orders').select('vessels(asset_type)').eq('id', serviceOrderId).maybeSingle();
      if (error) return null;
      return ((data as { vessels?: { asset_type?: string | null } | null } | null)?.vessels?.asset_type) ?? null;
    },
  });
  const tipo = assetType !== undefined ? assetType : tipoLido;
  // O texto escrito pelo usuário não é refeito quando o tipo chega depois.
  const editouRef = useRef(false);

  useEffect(() => {
    if (!open) { editouRef.current = false; return; }
    setPhone(clientPhone || '');
    if (!editouRef.current) setMessage(buildCompletionMessage({ clientName, osNumber, balance, dueDate, pixKey, assetType: tipo }));
  }, [open, clientPhone, clientName, osNumber, balance, dueDate, pixKey, tipo]);

  const digits = phone.replace(/\D/g, '');
  const canSend = digits.length >= 10 && message.trim().length > 0;

  const handleSend = async () => {
    if (!canSend) return;
    setSending(true);
    try {
      const normalized = digits.startsWith('55') ? digits : `55${digits}`;
      const { error } = await supabase.functions.invoke('whatsapp-send', {
        body: { phone: normalized, message, context: 'service_order', kind: 'text', service_order_id: serviceOrderId },
      });
      if (error) throw error;
      toast.success('Mensagem de conclusão enviada ao cliente.');
      onOpenChange(false);
    } catch (e: any) {
      toast.error(e.message || 'Erro ao enviar a mensagem');
    } finally {
      setSending(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={v => !sending && onOpenChange(v)}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <CheckCircle2 className="h-5 w-5 text-green-600" />
            Serviço concluído — avisar o cliente?
          </DialogTitle>
          <DialogDescription>
            {osNumber}
            {Number(balance || 0) > 0
              ? ` · saldo de ${fmtBRL(Number(balance))}`
              : ' · tudo quitado'}
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3 py-1">
          <div className="space-y-1.5">
            <Label className="text-xs text-muted-foreground">WhatsApp do cliente</Label>
            <Input value={phone} onChange={e => setPhone(e.target.value)} placeholder="(00) 00000-0000" />
          </div>
          <div className="space-y-1.5">
            <Label className="text-xs text-muted-foreground">Mensagem</Label>
            <Textarea value={message} onChange={e => { editouRef.current = true; setMessage(e.target.value); }} rows={7} className="resize-none text-sm" />
          </div>
          {!digits && (
            <p className="text-xs text-amber-600">Este cliente não tem WhatsApp cadastrado — informe o número para enviar.</p>
          )}
        </div>

        <DialogFooter className="gap-2 sm:gap-0">
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={sending}>
            Não enviar agora
          </Button>
          <Button onClick={handleSend} disabled={!canSend || sending} className="gap-2 bg-green-600 hover:bg-green-700 text-white">
            {sending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
            Enviar ao cliente
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
