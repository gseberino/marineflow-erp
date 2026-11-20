// Extrato financeiro do cliente: pré-visualiza o texto (editável), permite copiar e enviar por
// WhatsApp (edge whatsapp-send, kind:'text' — respeita wa_test_mode). Nada é enviado sem confirmar.
//
// Com as travas do "Cobrar juntas" (dono, 20/11/2026: "Sim, as mesmas travas"): o extrato manda o
// saldo em aberto com a chave Pix, então é cobrança. A regra é a MESMA (travaDoCobrarJuntas, em
// _shared/receivables/cobrar-juntas.ts): cadastro genérico, nada em aberto, piso, Pix do cliente
// esperando no Extrato, opt-out, telefone e horário de cobrança. O destino é o WhatsApp do cadastro
// (só exibido; antes era um campo editável — cobrança a número digitado expõe a dívida a terceiro).
// No envio, useEnviarExtrato relê tudo, recusa se o saldo mudou e manda com a chave do dia.
// A tela mostra o motivo quando barra, antes do botão.
import { useEffect, useMemo, useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { AlertTriangle, Loader2, Send, Copy, Check, FileText } from 'lucide-react';
import { toast } from 'sonner';
import { useAppSettings } from '@/hooks/use-app-settings';
import { horaDoCobrarJuntas, useEnviarExtrato, usePixEsperandoDoCliente } from '@/hooks/use-cobrar-juntas';
import { buildClientStatement, type StatementItem } from '@/lib/client-statement';
import type { ClienteParaCobrar } from '@/components/client/CobrarJuntasDialog';
import { saldoDaConta, travaDoCobrarJuntas } from '../../supabase/functions/_shared/receivables/cobrar-juntas';

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  cliente: ClienteParaCobrar;
  items: StatementItem[];
}

export function ClientStatementDialog({ open, onOpenChange, cliente, items }: Props) {
  const [message, setMessage] = useState('');
  const [copied, setCopied] = useState(false);
  const { data: settingsMap } = useAppSettings();
  const pixKey = settingsMap?.['pix_key'] ?? null;
  const piso = Number(settingsMap?.['collection_min_amount']) || 0;
  const pix = usePixEsperandoDoCliente(cliente.id, open && !cliente.generico);
  const enviar = useEnviarExtrato();

  // O envio vai SEMPRE ao cadastro (o hook relê na hora); aqui só se mostra o número.
  const phone = cliente.whatsapp || cliente.phone || '';

  // As contas com saldo (as que o extrato cobra), com o saldo que a tela mostra.
  const contasComSaldo = useMemo(
    () => (items || [])
      .filter((r) => !!r.id && saldoDaConta(r) > 0)
      .map((r) => ({ id: r.id as string, saldo: saldoDaConta(r) })),
    [items],
  );
  const total = Math.round(contasComSaldo.reduce((s, c) => s + c.saldo, 0) * 100) / 100;

  useEffect(() => {
    if (!open) return;
    setMessage(buildClientStatement({ clientName: cliente.name, items, pixKey }));
    setCopied(false);
  }, [open, cliente.name, items, pixKey]);

  const trava = pix.error
    ? (pix.error as Error).message
    : travaDoCobrarJuntas({
      clienteNome: cliente.name,
      generico: cliente.generico,
      optOut: cliente.opt_out_whatsapp,
      piso,
      totalEmAberto: total,
      pixEsperando: pix.data ?? [],
      telefone: phone,
      horaBrasilia: horaDoCobrarJuntas(),
    });
  const carregando = !cliente.generico && pix.isLoading;
  const sending = enviar.isPending;
  const podeEnviar = !trava && !carregando && message.trim().length > 0;

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(message);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      toast.error('Não foi possível copiar');
    }
  };

  const handleSend = () => {
    if (!podeEnviar) return;
    enviar.mutate(
      { cliente, mensagem: message, contas: contasComSaldo },
      {
        onSuccess: (r) => {
          if (r.deduplicado) {
            toast.info(r.modoTeste
              ? 'Este mesmo extrato já tinha saído hoje para o número de teste: não enviei de novo.'
              : 'Este mesmo extrato já tinha saído hoje: não enviei de novo.');
          } else if (r.modoTeste) {
            toast.warning(r.aviso);
          } else {
            toast.success('Extrato enviado ao cliente.');
          }
          onOpenChange(false);
        },
        onError: (e) => toast.error((e as Error).message || 'Erro ao enviar o extrato'),
      },
    );
  };

  return (
    <Dialog open={open} onOpenChange={v => !sending && onOpenChange(v)}>
      <DialogContent className="max-h-[90dvh] max-w-md overflow-y-auto" data-testid="enviar-extrato">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <FileText className="h-5 w-5 text-primary" />
            Extrato financeiro do cliente
          </DialogTitle>
          <DialogDescription>Revise e envie o extrato — nada é enviado sem confirmar.</DialogDescription>
        </DialogHeader>

        <div className="min-w-0 space-y-3 py-1">
          <div className="space-y-1.5">
            <Label className="text-xs text-muted-foreground">WhatsApp do cadastro</Label>
            <p className="break-words rounded-md border bg-muted/40 px-3 py-2 text-sm tabular-nums" data-testid="enviar-extrato-fone">
              {phone || 'Sem telefone no cadastro'}
            </p>
            <p className="text-xs text-muted-foreground">Para mandar a outro número, corrija o cadastro do cliente.</p>
          </div>
          <div className="space-y-1.5">
            <div className="flex items-center justify-between">
              <Label htmlFor="enviar-extrato-msg" className="text-xs text-muted-foreground">Extrato</Label>
              <Button type="button" variant="ghost" size="sm" onClick={handleCopy} className="h-6 gap-1 px-2 text-xs">
                {copied ? <Check className="h-3.5 w-3.5 text-success" /> : <Copy className="h-3.5 w-3.5" />}
                {copied ? 'Copiado' : 'Copiar'}
              </Button>
            </div>
            <Textarea
              id="enviar-extrato-msg"
              value={message}
              onChange={e => setMessage(e.target.value)}
              rows={12}
              className="resize-none break-words font-mono text-sm"
              disabled={sending}
            />
          </div>
          {trava && (
            <p role="alert" className="flex gap-2 rounded-md border border-destructive/40 bg-destructive/10 px-3 py-2 text-sm text-destructive">
              <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
              <span className="min-w-0 break-words">{trava}</span>
            </p>
          )}
        </div>

        <DialogFooter className="gap-2 sm:gap-0">
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={sending}>
            Fechar
          </Button>
          <Button onClick={handleSend} disabled={!podeEnviar || sending} className="gap-2">
            {sending || carregando ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
            Enviar ao cliente
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
