// Prompt OPT-IN de conclusão: ao concluir a OS com saldo, pergunta se deseja avisar o cliente de que o serviço
// terminou. Nada é enviado sem o usuário confirmar; o aviso usa a edge whatsapp-send (kind:'text'), que respeita
// wa_test_mode.
// O aviso NÃO leva o saldo nem a chave Pix (dono, 26/11/2026: "2. A"): eles iam a um número que se digita à mão, sem
// as travas da cobrança. Para cobrar, "Cobrar o cliente" abre a conferência da ficha (CobrarClienteDialog): o WhatsApp
// do cadastro, as travas e a cobrança de tudo que ele tem em aberto. Fechada a cobrança, o fluxo da conclusão termina.
import { useEffect, useRef, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Loader2, Send, CheckCircle2, Wallet } from 'lucide-react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { buildCompletionMessage } from '@/lib/completion-message';
import { CobrarClienteDialog } from '@/components/client/CobrarClienteDialog';

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  serviceOrderId: string;
  osNumber: string;
  /** Cliente da OS: com ele e saldo, "Cobrar o cliente" abre a conferência da ficha. */
  clientId?: string | null;
  clientName?: string | null;
  clientPhone?: string | null;
  /** Saldo em aberto da OS: aparece para quem conclui, nunca na mensagem ao cliente. */
  balance?: number | null;
  /** Tipo da unidade da OS (para o emoji). Ausente: o diálogo lê pela OS. */
  assetType?: string | null;
}

const fmtBRL = (v: number) =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);

export function CompletionSendDialog({
  open, onOpenChange, serviceOrderId, osNumber, clientId, clientName, clientPhone, balance, assetType,
}: Props) {
  const [phone, setPhone] = useState('');
  const [message, setMessage] = useState('');
  const [sending, setSending] = useState(false);
  // O aviso já foi; o diálogo fica só com o "cobrar o saldo?".
  const [avisado, setAvisado] = useState(false);
  // A conferência da cobrança está aberta (este diálogo some enquanto isso).
  const [cobrando, setCobrando] = useState(false);
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
    if (!open) { editouRef.current = false; setAvisado(false); setCobrando(false); return; }
    setPhone(clientPhone || '');
    if (!editouRef.current) setMessage(buildCompletionMessage({ clientName, osNumber, assetType: tipo }));
  }, [open, clientPhone, clientName, osNumber, tipo]);

  const saldo = Number(balance || 0);
  const temSaldo = saldo > 0.009;
  const podeCobrar = temSaldo && !!clientId;
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
      toast.success('Aviso de conclusão enviado ao cliente.');
      if (podeCobrar) setAvisado(true);
      else onOpenChange(false);
    } catch (e: any) {
      toast.error(e.message || 'Erro ao enviar a mensagem');
    } finally {
      setSending(false);
    }
  };

  // Fechada a conferência (enviou ou desistiu), a conclusão termina: não volta ao aviso.
  const fecharCobranca = () => { setCobrando(false); onOpenChange(false); };

  const botaoCobrar = (
    <Button variant={avisado ? 'default' : 'outline'} onClick={() => setCobrando(true)} disabled={sending} className="gap-2">
      <Wallet className="h-4 w-4" />
      Cobrar o cliente
    </Button>
  );

  return (
    <>
      <Dialog open={open && !cobrando} onOpenChange={v => !sending && onOpenChange(v)}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <CheckCircle2 className="h-5 w-5 text-green-600" />
              {avisado ? 'Aviso enviado — cobrar o saldo?' : 'Serviço concluído — avisar o cliente?'}
            </DialogTitle>
            <DialogDescription>
              {osNumber}
              {temSaldo ? ` · saldo de ${fmtBRL(saldo)}` : ' · tudo quitado'}
            </DialogDescription>
          </DialogHeader>

          {avisado ? (
            <p className="py-1 text-sm text-muted-foreground">
              O aviso de conclusão foi enviado. O saldo segue em aberto: "Cobrar o cliente" mostra a mensagem da cobrança e as
              travas antes de enviar.
            </p>
          ) : (
            <div className="space-y-3 py-1">
              <div className="space-y-1.5">
                <Label className="text-xs text-muted-foreground">WhatsApp do cliente</Label>
                <Input value={phone} onChange={e => setPhone(e.target.value)} placeholder="(00) 00000-0000" />
              </div>
              <div className="space-y-1.5">
                <Label className="text-xs text-muted-foreground">Mensagem</Label>
                <Textarea value={message} onChange={e => { editouRef.current = true; setMessage(e.target.value); }} rows={6} className="resize-none text-sm" />
              </div>
              {!digits && (
                <p className="text-xs text-amber-600">Este cliente não tem WhatsApp cadastrado — informe o número para enviar.</p>
              )}
              {temSaldo && (
                <p className="text-xs text-muted-foreground" data-testid="conclusao-sem-valor">
                  O aviso não leva valor nem Pix.{' '}
                  {podeCobrar
                    ? 'Para cobrar o saldo, use "Cobrar o cliente": mostra a cobrança de tudo que ele tem em aberto, com as travas, antes de enviar.'
                    : 'Esta OS não tem cliente do cadastro: para cobrar o saldo, ligue a OS a um cliente.'}
                </p>
              )}
            </div>
          )}

          <DialogFooter className="gap-2 sm:gap-0">
            {avisado ? (
              <>
                <Button variant="outline" onClick={() => onOpenChange(false)}>Fechar</Button>
                {botaoCobrar}
              </>
            ) : (
              <>
                <Button variant="outline" onClick={() => onOpenChange(false)} disabled={sending}>
                  Não enviar agora
                </Button>
                {podeCobrar && botaoCobrar}
                <Button onClick={handleSend} disabled={!canSend || sending} className="gap-2 bg-green-600 hover:bg-green-700 text-white">
                  {sending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
                  Enviar ao cliente
                </Button>
              </>
            )}
          </DialogFooter>
        </DialogContent>
      </Dialog>
      <CobrarClienteDialog clienteId={open && cobrando && clientId ? clientId : null} onFechar={fecharCobranca} />
    </>
  );
}
