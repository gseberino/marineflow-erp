// Extrato financeiro do cliente: pré-visualiza o texto (editável), permite copiar e enviar por
// WhatsApp (edge whatsapp-send, kind:'text' — respeita wa_test_mode). Nada é enviado sem confirmar.
//
// Com as travas do "Cobrar juntas" (dono, 20/11/2026: "Sim, as mesmas travas"): o extrato manda o
// saldo em aberto com a chave Pix, então é cobrança. A regra é a MESMA (travaDoExtrato, em
// _shared/receivables/cobrar-juntas.ts): cadastro genérico, piso, Pix do cliente esperando no
// Extrato, opt-out, telefone e horário de cobrança. O destino é o WhatsApp do cadastro (só exibido;
// antes era um campo editável — cobrança a número digitado expõe a dívida a terceiro).
// No envio, useEnviarExtrato relê tudo, recusa se o saldo mudou e manda com a chave do dia.
// A tela mostra o motivo quando barra, antes do botão.
//
// Respostas do dono (20/11/2026):
// - Sem nada em aberto, o extrato SAI como comprovante de quitação (o texto diz "quitado"); só o
//   genérico, o opt-out, o telefone e o horário barram. Não é cobrança: nada é registrado.
// - Com saldo, "conta como cobrança do dia": depois do envio, a cobrança fica registrada (e a da
//   conta que não tem nenhuma é criada junto, como no Cobrar juntas). O aviso aparece antes do botão.
//
// modo "cobranca" (dono, 26/11/2026: "1. A" — os botões sem trava da tela ganham esta conferência): o botão da linha em
// Contas a Receber e o da aba Cobranças abrem este diálogo pelo CobrarClienteDialog. A mensagem é a cobrança do cliente
// inteiro (só as contas com saldo, o texto do "cobra o Fulano" do assistente), sem comprovante de quitação, com as travas
// do Cobrar juntas; o envio é useEnviarCobrancaDoCliente, que registra como o extrato com saldo. Nos dois modos, quem já
// recebeu cobrança hoje ganha um aviso antes do botão (não trava: o dono decide).
import { useEffect, useMemo, useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { AlertTriangle, Loader2, Send, Copy, Check, FileText, Info } from 'lucide-react';
import { toast } from 'sonner';
import { useAppSettings } from '@/hooks/use-app-settings';
import {
  avisoDeCobradoHoje, horaDoCobrarJuntas, useCobradoHoje, useCobrancasFormais, useEnviarCobrancaDoCliente, useEnviarExtrato,
  usePixEsperandoDoCliente,
} from '@/hooks/use-cobrar-juntas';
import { buildClientStatement, type StatementItem } from '@/lib/client-statement';
import type { ClienteParaCobrar } from '@/components/client/CobrarJuntasDialog';
import {
  avisoDaCobrancaCriada, contasSemCobranca, saldoDaConta, travaDoCobrarJuntas, travaDoExtrato,
} from '../../supabase/functions/_shared/receivables/cobrar-juntas';

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  cliente: ClienteParaCobrar;
  items: StatementItem[];
  /** "extrato" (padrão): o Enviar extrato da ficha. "cobranca": a cobrança do cliente pela tela (só o que tem saldo). */
  modo?: 'extrato' | 'cobranca';
}

const plural = (n: number, um: string, varios: string) => `${n} ${n === 1 ? um : varios}`;

export function ClientStatementDialog({ open, onOpenChange, cliente, items, modo = 'extrato' }: Props) {
  const cobranca = modo === 'cobranca';
  const [message, setMessage] = useState('');
  const [copied, setCopied] = useState(false);
  const { data: settingsMap } = useAppSettings();
  const pixKey = settingsMap?.['pix_key'] ?? null;
  const piso = Number(settingsMap?.['collection_min_amount']) || 0;
  const enviar = useEnviarExtrato();
  const cobrar = useEnviarCobrancaDoCliente();

  // O envio vai SEMPRE ao cadastro (o hook relê na hora); aqui só se mostra o número.
  const phone = cliente.whatsapp || cliente.phone || '';

  // As contas com saldo (as que o extrato cobra), com o saldo que a tela mostra.
  const contasComSaldo = useMemo(
    () => (items || [])
      .filter((r) => !!r.id && saldoDaConta(r) > 0)
      .map((r) => ({ id: r.id as string, saldo: saldoDaConta(r), service_order_id: r.service_order_id ?? null })),
    [items],
  );
  const total = Math.round(contasComSaldo.reduce((s, c) => s + c.saldo, 0) * 100) / 100;
  const lancamentos = (items || []).filter((r) => r.status !== 'cancelled').length;
  // A cobrança sem saldo não vira comprovante de quitação: a trava diz que não há o que cobrar.
  const quitado = !cobranca && !(total > 0) && lancamentos > 0;

  // Pix esperando só importa quando há o que cobrar (no comprovante de quitação não se lê).
  const pix = usePixEsperandoDoCliente(cliente.id, open && !cliente.generico && total > 0);
  // As cobranças abertas das contas com saldo (e das OS delas, a "Total" sem conta): quais ganham cobrança.
  const contaIds = useMemo(() => contasComSaldo.map((c) => c.id), [contasComSaldo]);
  const osIds = useMemo(
    () => [...new Set(contasComSaldo.map((c) => c.service_order_id).filter((x): x is string => !!x))],
    [contasComSaldo],
  );
  const cobrancas = useCobrancasFormais(contaIds, osIds, open && !cliente.generico && total > 0);
  // Quem já recebeu cobrança hoje (qualquer caminho que registra): aviso antes do botão, não trava.
  const cobradoHoje = useCobradoHoje(cliente.id, open && !cliente.generico && total > 0);

  useEffect(() => {
    if (!open) return;
    setMessage(buildClientStatement({ clientName: cliente.name, items, pixKey, cobranca }));
    setCopied(false);
  }, [open, cliente.name, items, pixKey, cobranca]);

  const entradaDasTravas = {
    clienteNome: cliente.name,
    generico: cliente.generico,
    optOut: cliente.opt_out_whatsapp,
    piso,
    totalEmAberto: total,
    pixEsperando: pix.data ?? [],
    telefone: phone,
    horaBrasilia: horaDoCobrarJuntas(),
  };
  const trava = total > 0 && pix.error
    ? (pix.error as Error).message
    : cobranca
      ? travaDoCobrarJuntas({ ...entradaDasTravas, quantidadeOs: null })
      : travaDoExtrato({ ...entradaDasTravas, lancamentos });
  // O que acontece com o envio, antes do botão: quitação não é cobrança; com saldo é a cobrança do dia.
  const criadas = !trava && total > 0 && cobrancas.data
    ? avisoDaCobrancaCriada(contasSemCobranca(contasComSaldo, cobrancas.data).length)
    : null;
  const efeito = trava
    ? null
    : quitado
      ? 'Tudo quitado: o extrato sai como comprovante de quitação e não conta como cobrança.'
      : `${cobranca ? 'A mensagem' : 'O extrato com saldo'} conta como a cobrança de hoje deste cliente (fica registrado em Cobranças).${criadas ? ` ${criadas}` : ''}`;
  const jaCobrado = trava || quitado
    ? null
    : cobradoHoje.error
      ? 'Não consegui conferir se este cliente já recebeu cobrança hoje. Confira em Cobranças antes de enviar.'
      : avisoDeCobradoHoje(cobradoHoje.data);
  const carregando = !cliente.generico && total > 0 && pix.isLoading;
  const sending = enviar.isPending || cobrar.isPending;
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
    if (cobranca) {
      cobrar.mutate(
        { cliente, mensagem: message, contas: contasComSaldo.map(({ id, saldo }) => ({ id, saldo })) },
        {
          onSuccess: (r) => {
            if (r.deduplicado) {
              toast.info(r.modoTeste
                ? 'Esta mesma cobrança já tinha saído hoje para o número de teste: não enviei de novo.'
                : 'Esta mesma cobrança já tinha saído hoje: não enviei de novo.');
            } else if (r.modoTeste || r.aviso) {
              toast.warning(r.aviso);
            } else {
              const criadasAgora = r.cobrancasCriadas ?? 0;
              toast.success(`Cobrança enviada ao cliente. Ficou registrada como a cobrança de hoje${
                criadasAgora ? ` (${plural(criadasAgora, 'cobrança criada', 'cobranças criadas')} em Cobranças)` : ''}.`);
            }
            onOpenChange(false);
          },
          onError: (e) => toast.error((e as Error).message || 'Erro ao enviar a cobrança'),
        },
      );
      return;
    }
    enviar.mutate(
      { cliente, mensagem: message, contas: contasComSaldo.map(({ id, saldo }) => ({ id, saldo })) },
      {
        onSuccess: (r) => {
          if (r.deduplicado) {
            toast.info(r.modoTeste
              ? 'Este mesmo extrato já tinha saído hoje para o número de teste: não enviei de novo.'
              : 'Este mesmo extrato já tinha saído hoje: não enviei de novo.');
          } else if (r.modoTeste || r.aviso) {
            toast.warning(r.aviso);
          } else if (r.quitacao) {
            toast.success('Comprovante de quitação enviado ao cliente.');
          } else {
            const criadasAgora = r.cobrancasCriadas ?? 0;
            toast.success(`Extrato enviado ao cliente. Ficou registrado como a cobrança de hoje${
              criadasAgora ? ` (${plural(criadasAgora, 'cobrança criada', 'cobranças criadas')} em Cobranças)` : ''}.`);
          }
          onOpenChange(false);
        },
        onError: (e) => toast.error((e as Error).message || 'Erro ao enviar o extrato'),
      },
    );
  };

  return (
    <Dialog open={open} onOpenChange={v => !sending && onOpenChange(v)}>
      <DialogContent className="max-h-[90dvh] max-w-md overflow-y-auto" data-testid="enviar-extrato" data-modo={modo}>
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <FileText className="h-5 w-5 shrink-0 text-primary" />
            <span className="min-w-0 break-words">
              {cobranca ? `Cobrar ${(cliente.name || '').trim() || 'o cliente'}` : quitado ? 'Comprovante de quitação' : 'Extrato financeiro do cliente'}
            </span>
          </DialogTitle>
          <DialogDescription>
            {cobranca
              ? 'Uma mensagem com tudo que o cliente tem em aberto. Revise e envie — nada é enviado sem confirmar.'
              : 'Revise e envie o extrato — nada é enviado sem confirmar.'}
          </DialogDescription>
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
              <Label htmlFor="enviar-extrato-msg" className="text-xs text-muted-foreground">{cobranca ? 'Mensagem' : 'Extrato'}</Label>
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
          {jaCobrado && (
            <p className="flex gap-2 rounded-md border border-warning/40 bg-warning/10 px-3 py-2 text-sm" data-testid="enviar-extrato-ja-cobrado">
              <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-warning" />
              <span className="min-w-0 break-words">{jaCobrado}</span>
            </p>
          )}
          {efeito && (
            <p className="flex gap-2 rounded-md border bg-muted/40 px-3 py-2 text-sm" data-testid="enviar-extrato-efeito">
              <Info className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />
              <span className="min-w-0 break-words">{efeito}</span>
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
