// Extrato financeiro do cliente: pré-visualiza o texto (editável), permite copiar e enviar por
// WhatsApp (edge whatsapp-send, kind:'text' — respeita wa_test_mode). Nada é enviado sem confirmar.
import { useEffect, useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Loader2, Send, Copy, Check, FileText } from 'lucide-react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { useAppSettings } from '@/hooks/use-app-settings';
import { buildClientStatement, type StatementItem } from '@/lib/client-statement';

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  clientName?: string | null;
  clientPhone?: string | null;
  items: StatementItem[];
}

export function ClientStatementDialog({ open, onOpenChange, clientName, clientPhone, items }: Props) {
  const [phone, setPhone] = useState('');
  const [message, setMessage] = useState('');
  const [sending, setSending] = useState(false);
  const [copied, setCopied] = useState(false);
  const { data: settingsMap } = useAppSettings();
  const pixKey = settingsMap?.['pix_key'] ?? null;

  useEffect(() => {
    if (!open) return;
    setPhone(clientPhone || '');
    setMessage(buildClientStatement({ clientName, items, pixKey }));
    setCopied(false);
  }, [open, clientPhone, clientName, items, pixKey]);

  const digits = phone.replace(/\D/g, '');
  const canSend = digits.length >= 10 && message.trim().length > 0;

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(message);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      toast.error('Não foi possível copiar');
    }
  };

  const handleSend = async () => {
    if (!canSend) return;
    setSending(true);
    try {
      const normalized = digits.startsWith('55') ? digits : `55${digits}`;
      const { error } = await supabase.functions.invoke('whatsapp-send', {
        body: { phone: normalized, message, context: 'billing', kind: 'text' },
      });
      if (error) throw error;
      toast.success('Extrato enviado ao cliente.');
      onOpenChange(false);
    } catch (e: any) {
      toast.error(e.message || 'Erro ao enviar o extrato');
    } finally {
      setSending(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={v => !sending && onOpenChange(v)}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <FileText className="h-5 w-5 text-primary" />
            Extrato financeiro do cliente
          </DialogTitle>
          <DialogDescription>Revise e envie o extrato — nada é enviado sem confirmar.</DialogDescription>
        </DialogHeader>

        <div className="space-y-3 py-1">
          <div className="space-y-1.5">
            <Label className="text-xs text-muted-foreground">WhatsApp do cliente</Label>
            <Input value={phone} onChange={e => setPhone(e.target.value)} placeholder="(00) 00000-0000" />
          </div>
          <div className="space-y-1.5">
            <div className="flex items-center justify-between">
              <Label className="text-xs text-muted-foreground">Extrato</Label>
              <Button type="button" variant="ghost" size="sm" onClick={handleCopy} className="h-6 gap-1 px-2 text-xs">
                {copied ? <Check className="h-3.5 w-3.5 text-success" /> : <Copy className="h-3.5 w-3.5" />}
                {copied ? 'Copiado' : 'Copiar'}
              </Button>
            </div>
            <Textarea value={message} onChange={e => setMessage(e.target.value)} rows={12} className="resize-none text-sm font-mono" />
          </div>
        </div>

        <DialogFooter className="gap-2 sm:gap-0">
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={sending}>
            Fechar
          </Button>
          <Button onClick={handleSend} disabled={!canSend || sending} className="gap-2">
            {sending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
            Enviar ao cliente
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
