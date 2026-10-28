// "Cobrar juntas" (Fase 0 do Fechar juntas, 28/10/2026): escolhe as OS do cliente que têm saldo,
// monta UMA mensagem (o extrato filtrado, com o número da OS e o saldo de cada conta) e envia pelo
// WhatsApp com as travas do lembrete de cobrança. Não junta nada no banco: cada conta continua na
// sua OS (para juntar OS que ainda não começaram, é o Agrupar OS).
//
// Recusas aparecem ANTES do botão, com o texto pronto da regra (cadastro genérico, 2 a 10 OS, piso,
// Pix esperando no Extrato, opt-out, sem telefone, fora do horário de cobrança). Enviar não tem
// confirmação extra: o próprio botão é a confirmação e não há perda (padrão da casa: useConfirmacao
// só com perda real). O destino é o WhatsApp do cadastro, só exibido (como a tool cobrar_juntas).
import { useEffect, useMemo, useState } from 'react';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { AlertTriangle, Check, Copy, Info, Layers, Loader2, Send } from 'lucide-react';
import { toast } from 'sonner';
import { useAppSettings } from '@/hooks/use-app-settings';
import {
  horaDoCobrarJuntas, useCobrancasFormais, useEnviarCobrarJuntas, usePixEsperandoDoCliente,
} from '@/hooks/use-cobrar-juntas';
import { buildClientStatement, type StatementItem } from '@/lib/client-statement';
import {
  osComSaldo, resumoDoCobrarJuntas, saldoDaConta, SEM_COBRANCA_FORMAL, travaDoCobrarJuntas, type ContaDoCliente,
} from '../../../supabase/functions/_shared/receivables/cobrar-juntas';

const brl = (v: number) => new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);

export interface ClienteParaCobrar {
  id: string;
  name?: string | null;
  /** clients.generico: cadastro de balcão ("Cliente Final"), sem CPF/CNPJ. */
  generico?: boolean | null;
  opt_out_whatsapp?: boolean | null;
  whatsapp?: string | null;
  phone?: string | null;
}

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  cliente: ClienteParaCobrar;
  /** As contas do cliente (com service_order_id e numero_os). As sem saldo ficam de fora sozinhas. */
  contas: Array<ContaDoCliente & StatementItem>;
  /** OS já marcadas ao abrir (ex.: as escolhidas na tabela). Vazio = todas as que têm saldo. */
  osIniciais?: string[];
}

export function CobrarJuntasDialog({ open, onOpenChange, cliente, contas, osIniciais }: Props) {
  const oss = useMemo(() => osComSaldo(contas), [contas]);
  const [escolhidas, setEscolhidas] = useState<Set<string>>(new Set());
  const [message, setMessage] = useState('');
  const [copied, setCopied] = useState(false);
  const { data: settingsMap } = useAppSettings();
  const pixKey = settingsMap?.['pix_key'] ?? null;
  const piso = Number(settingsMap?.['collection_min_amount']) || 0;
  const pix = usePixEsperandoDoCliente(cliente.id, open && !cliente.generico);
  const enviar = useEnviarCobrarJuntas();

  // O envio vai SEMPRE ao cadastro (o hook relê na hora); aqui só se mostra o número.
  const phone = cliente.whatsapp || cliente.phone || '';

  // Ao abrir: marca as OS pedidas (ou todas).
  useEffect(() => {
    if (!open) return;
    const pedidas = (osIniciais ?? []).filter((id) => oss.some((o) => o.service_order_id === id));
    setEscolhidas(new Set(pedidas.length ? pedidas : oss.map((o) => o.service_order_id)));
    setCopied(false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);

  const servicoIds = useMemo(() => [...escolhidas], [escolhidas]);
  const selecionadas = oss.filter((o) => escolhidas.has(o.service_order_id));
  const total = Math.round(selecionadas.reduce((s, o) => s + o.saldo, 0) * 100) / 100;
  const contasEscolhidas = selecionadas.flatMap((o) => o.contas.map((c) => ({ id: c.id, saldo: saldoDaConta(c) })));
  const contaIds = contasEscolhidas.map((c) => c.id);
  const cobrancas = useCobrancasFormais(contaIds, servicoIds, open && !cliente.generico);

  // A mensagem acompanha a escolha das OS (a edição à mão vale até mudar a escolha).
  useEffect(() => {
    if (!open) return;
    setMessage(buildClientStatement({ clientName: cliente.name, items: contas, pixKey, servicoIds }));
  }, [open, cliente.name, contas, pixKey, servicoIds]);

  const trava = pix.error
    ? (pix.error as Error).message
    : travaDoCobrarJuntas({
      clienteNome: cliente.name,
      generico: cliente.generico,
      quantidadeOs: selecionadas.length,
      optOut: cliente.opt_out_whatsapp,
      piso,
      totalEmAberto: total,
      pixEsperando: pix.data ?? [],
      telefone: phone,
      horaBrasilia: horaDoCobrarJuntas(),
    });
  // Sem cobrança formal, o envio não fica registrado: aviso (não trava), antes do botão.
  const semCobrancaFormal = !trava && cobrancas.data === 0;
  const carregando = !cliente.generico && pix.isLoading;
  const podeEnviar = !trava && !carregando && selecionadas.length > 0 && message.trim().length > 0;

  const alternar = (id: string, marcado: boolean) => {
    setEscolhidas((atual) => {
      const novo = new Set(atual);
      if (marcado) novo.add(id); else novo.delete(id);
      return novo;
    });
  };

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
      { cliente, mensagem: message, contas: contasEscolhidas, servicoIds },
      {
        onSuccess: (r) => {
          if (r.deduplicado) {
            toast.info('Esta mesma cobrança já tinha saído hoje: não enviei de novo.');
          } else {
            toast.success(`Cobrança enviada: ${resumoDoCobrarJuntas(selecionadas)}.`);
            if (r.aviso) toast.warning(r.aviso);
          }
          onOpenChange(false);
        },
        onError: (e) => toast.error((e as Error).message || 'Erro ao enviar a cobrança'),
      },
    );
  };

  const sending = enviar.isPending;

  return (
    <Dialog open={open} onOpenChange={(v) => !sending && onOpenChange(v)}>
      <DialogContent
        className="max-h-[90dvh] max-w-lg overflow-y-auto pb-[max(1.5rem,env(safe-area-inset-bottom))]"
        data-testid="cobrar-juntas"
      >
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Layers className="h-5 w-5 text-primary" />
            Cobrar juntas
          </DialogTitle>
          <DialogDescription>
            Uma mensagem só com o saldo das OS escolhidas. Cada conta continua na sua OS; nada é enviado sem você clicar em Enviar.
          </DialogDescription>
        </DialogHeader>

        <div className="min-w-0 space-y-3 py-1">
          <div className="space-y-1.5">
            <Label className="text-xs text-muted-foreground">OS com saldo em aberto</Label>
            {oss.length === 0 ? (
              <p className="rounded-md border bg-muted/40 px-3 py-2 text-sm text-muted-foreground">
                Nenhuma OS deste cliente tem saldo em aberto.
              </p>
            ) : (
              <ul className="space-y-1.5">
                {oss.map((o) => {
                  const marcado = escolhidas.has(o.service_order_id);
                  return (
                    <li key={o.service_order_id}>
                      <label className="flex min-w-0 cursor-pointer items-center gap-3 rounded-md border bg-card px-3 py-2 text-sm">
                        <Checkbox
                          checked={marcado}
                          onCheckedChange={(v) => alternar(o.service_order_id, v === true)}
                          aria-label={`Cobrar a ${o.numero_os}`}
                          disabled={sending}
                        />
                        <span className="min-w-0 flex-1">
                          <span className="block truncate font-semibold">{o.numero_os}</span>
                          <span className="block truncate text-xs text-muted-foreground">
                            {o.contas.length === 1 ? '1 conta' : `${o.contas.length} contas`}
                            {o.vencido ? ' · vencida' : ''}
                          </span>
                        </span>
                        <span className={`shrink-0 font-semibold tabular-nums ${o.vencido ? 'text-destructive' : ''}`}>
                          {brl(o.saldo)}
                        </span>
                      </label>
                    </li>
                  );
                })}
              </ul>
            )}
            {oss.length > 0 && (
              <p className="flex items-center justify-between gap-2 rounded-md bg-muted/40 px-3 py-1.5 text-sm">
                <span>{selecionadas.length === 1 ? '1 OS escolhida' : `${selecionadas.length} OS escolhidas`}</span>
                <b className="tabular-nums" data-testid="cobrar-juntas-total">{brl(total)}</b>
              </p>
            )}
          </div>

          <div className="space-y-1.5">
            <Label className="text-xs text-muted-foreground">WhatsApp do cadastro</Label>
            <p className="break-words rounded-md border bg-muted/40 px-3 py-2 text-sm tabular-nums" data-testid="cobrar-juntas-fone">
              {phone || 'Sem telefone no cadastro'}
            </p>
            <p className="text-xs text-muted-foreground">Para mandar a outro número, corrija o cadastro do cliente.</p>
          </div>

          <div className="space-y-1.5">
            <div className="flex items-center justify-between">
              <Label htmlFor="cobrar-juntas-msg" className="text-xs text-muted-foreground">Mensagem</Label>
              <Button type="button" variant="ghost" size="sm" onClick={handleCopy} className="h-6 gap-1 px-2 text-xs">
                {copied ? <Check className="h-3.5 w-3.5 text-success" /> : <Copy className="h-3.5 w-3.5" />}
                {copied ? 'Copiado' : 'Copiar'}
              </Button>
            </div>
            <Textarea
              id="cobrar-juntas-msg"
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              rows={10}
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
          {semCobrancaFormal && (
            <p
              className="flex gap-2 rounded-md border border-warning/40 bg-warning/10 px-3 py-2 text-sm"
              data-testid="cobrar-juntas-sem-cobranca"
            >
              <Info className="mt-0.5 h-4 w-4 shrink-0 text-warning" />
              <span className="min-w-0 break-words">{SEM_COBRANCA_FORMAL}</span>
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
