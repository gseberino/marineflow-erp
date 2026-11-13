import { useState, useEffect, useId } from 'react';
import { ChevronDown, Loader2, RotateCcw, DollarSign, XCircle, ArrowRightCircle } from 'lucide-react';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { Button } from '@/components/ui/button';
import { useToast } from '@/hooks/use-toast';
import { useUpdateQuoteStatus, QUOTE_STATUS_TRANSITIONS, MOTIVOS_DA_PERDA, NOTA_DA_PERDA_MAX, type MotivoDaPerda } from '@/hooks/use-service-orders';
import { quoteStatusConfig } from '@/lib/constants';
import { RegisterDepositDialog } from '@/components/RegisterDepositDialog';
import { cn } from '@/lib/utils';
import { supabase } from '@/integrations/supabase/client';
import { usePaymentConditionPresets } from '@/hooks/use-payment-conditions';
import { computeDeposit, type DepositComputation } from '@/lib/quote-deposit';
import { useConverterSemSinal } from '@/components/ConverterSemSinal';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Label } from '@/components/ui/label';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { Textarea } from '@/components/ui/textarea';
import { Campo } from '@/components/Campo';

interface Props {
  orderId: string;
  currentQuoteStatus: string;
  serviceOrderNumber?: string;
  grandTotal?: number;
  laborCost?: number;
  partsCost?: number;
  /** Retorno F5 (P12.3): o motivo do perdido, mostrado no selo do reprovado ("Reprovado · fechou com outro") */
  motivoPerda?: string | null;
}

// ─── Retorno F5 (P12.2 e P12.3): o motivo da perda ─────────────────────────────────────────────────────────────
/** As opções do seletor, com o sentido por extenso (a mesma lista fechada do banco, sem o sem_motivo_antigo). */
const OPCOES_DO_MOTIVO: Record<MotivoDaPerda, string> = {
  sumiu: 'Sumiu (sem resposta)',
  fechou_com_outro: 'Fechou com outro',
  desistiu: 'Desistiu',
  preco: 'Preço',
  prazo: 'Prazo',
  outro: 'Outro',
};

const NO_SELO: Record<string, string> = {
  sumiu: 'sumiu', fechou_com_outro: 'fechou com outro', desistiu: 'desistiu', preco: 'preço', prazo: 'prazo', outro: 'outro',
  sem_motivo_antigo: 'sem motivo (antigo)',
};

/** O motivo como o selo o mostra ("Reprovado · fechou com outro"); sem motivo, null (o selo de antes). */
export function rotuloDoMotivoDaPerda(motivo: string | null | undefined): string | null {
  return motivo ? (NO_SELO[motivo] ?? null) : null;
}

/**
 * A janela do perdido: o rótulo acima, as seis opções e a nota opcional (até 200 caracteres). O botão só se habilita com um
 * motivo; sem confirmação extra: marcar perdido é reversível pela própria tela (Reprovado → Em elaboração).
 */
function JanelaDoPerdido({ aberta, ocupado, numero, onFechar, onConfirmar }: {
  aberta: boolean;
  ocupado: boolean;
  numero: string;
  onFechar: () => void;
  onConfirmar: (motivo: MotivoDaPerda, nota: string) => void | Promise<void>;
}) {
  const id = useId();
  const [motivo, setMotivo] = useState<MotivoDaPerda | ''>('');
  const [nota, setNota] = useState('');
  useEffect(() => {
    if (aberta) {
      setMotivo('');
      setNota('');
    }
  }, [aberta]);
  return (
    <Dialog open={aberta} onOpenChange={(v) => { if (!v && !ocupado) onFechar(); }}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle>Marcar {numero || 'o orçamento'} como perdido</DialogTitle>
          <DialogDescription>O cliente não seguiu com este orçamento. Dá para reabrir depois, pela própria tela.</DialogDescription>
        </DialogHeader>
        <div className="space-y-4">
          <Campo rotulo="Por que o orçamento foi perdido?">
            <RadioGroup value={motivo} onValueChange={(v) => setMotivo(v as MotivoDaPerda)} className="flex flex-col gap-2" aria-label="Por que o orçamento foi perdido?">
              {MOTIVOS_DA_PERDA.map((m) => (
                <div key={m} className="flex items-center gap-2">
                  <RadioGroupItem value={m} id={`${id}-${m}`} disabled={ocupado} />
                  <Label htmlFor={`${id}-${m}`} className="cursor-pointer font-normal">{OPCOES_DO_MOTIVO[m]}</Label>
                </div>
              ))}
            </RadioGroup>
          </Campo>
          <Campo rotulo="Nota (se quiser)" htmlFor={`${id}-nota`}>
            <Textarea
              id={`${id}-nota`}
              value={nota}
              onChange={(e) => setNota(e.target.value)}
              maxLength={NOTA_DA_PERDA_MAX}
              rows={2}
              placeholder="Ex.: fechou com a concorrente pelo preço"
              className="resize-none"
              disabled={ocupado}
            />
          </Campo>
        </div>
        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={onFechar} disabled={ocupado}>Voltar</Button>
          <Button onClick={() => { if (motivo) void onConfirmar(motivo, nota); }} disabled={!motivo || ocupado}>
            {ocupado && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            Marcar como perdido
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

export function QuoteStatusQuickChange({ orderId, currentQuoteStatus, serviceOrderNumber = '', grandTotal = 0, laborCost = 0, partsCost = 0, motivoPerda }: Props) {
  const { toast } = useToast();
  const updateQuoteStatus = useUpdateQuoteStatus();
  const { data: paymentPresets } = usePaymentConditionPresets();
  const [depositOpen, setDepositOpen] = useState(false);
  const [abandoning, setAbandoning] = useState(false);
  const [deposit, setDeposit] = useState<DepositComputation | null>(null);
  const [appliedLabel, setAppliedLabel] = useState('');
  const [installments, setInstallments] = useState<any[] | null>(null);
  const [scheduledEndAt, setScheduledEndAt] = useState<string | null>(null);
  // (F5) o seletor do motivo: "Reprovado" não grava antes dele
  const [perdendo, setPerdendo] = useState(false);
  const semSinal = useConverterSemSinal();
  const isBusy = updateQuoteStatus.isPending || abandoning || semSinal.convertendo;
  // Aprovado ou aguardando sinal: dá para seguir sem entrada, com tudo na conclusão.
  const pedirSemSinal = () => semSinal.pedir({ id: orderId, number: serviceOrderNumber, grandTotal });

  // Ao abrir "Receber sinal": carrega os dados do orçamento + a condição de pagamento e computa
  // o sinal pela MESMA lib que o orçamento usa — para a janela bater exatamente com o orçamento
  // (com desconto e com o preset já definido), sem precisar abrir o orçamento.
  useEffect(() => {
    if (!depositOpen) return;
    let cancelled = false;
    (async () => {
      const { data: so } = await supabase
        .from('service_orders')
        .select('labor_cost_total, parts_cost_total, operational_cost_total, travel_cost_total, subcontract_cost_total, is_travel_billable, discount_amount, tax_amount, payment_condition_preset_id, payment_conditions, custom_payment_installments, scheduled_end_at')
        .eq('id', orderId)
        .maybeSingle();
      if (cancelled || !so) return;
      const o = so as any;
      const preset = (paymentPresets || []).find(
        (p: any) => p.id === o.payment_condition_preset_id ||
          (p.label === o.payment_conditions && !o.payment_condition_preset_id),
      );
      const installments = Array.isArray(preset?.installments)
        ? preset!.installments
        : (Array.isArray(o.custom_payment_installments) ? o.custom_payment_installments : null);
      setDeposit(computeDeposit(o, installments));
      setAppliedLabel((preset as any)?.label ?? '');
      setInstallments(installments);
      setScheduledEndAt(o.scheduled_end_at ?? null);
    })();
    return () => { cancelled = true; };
  }, [depositOpen, orderId, paymentPresets]);

  const cfg = quoteStatusConfig[currentQuoteStatus];
  // (F5, P12.3) "Reprovado · fechou com outro"; o antigo, "Reprovado · sem motivo (antigo)"
  const doMotivo = currentQuoteStatus === 'rejected' ? rotuloDoMotivoDaPerda(motivoPerda) : null;
  const rotuloDoSelo = doMotivo ? `${cfg?.label ?? currentQuoteStatus} · ${doMotivo}` : (cfg?.label ?? currentQuoteStatus);
  const validTransitions = QUOTE_STATUS_TRANSITIONS[currentQuoteStatus] ?? [];
  const isAwaitingDeposit = currentQuoteStatus === 'awaiting_deposit';

  const handleTransition = async (target: string) => {
    // (F5, P12.2) perdido sempre com motivo: o seletor abre, e nada é gravado antes dele
    if (target === 'rejected') {
      setPerdendo(true);
      return;
    }
    try {
      await updateQuoteStatus.mutateAsync({ id: orderId, quoteStatus: target });
      const label = quoteStatusConfig[target]?.label ?? target;
      toast({ title: `Status atualizado para "${label}"` });
    } catch (err: any) {
      toast({ title: 'Erro ao atualizar status', description: err.message, variant: 'destructive' });
    }
  };

  // (F5, P12.2) o motivo escolhido no seletor, com a nota
  const marcarPerdido = async (motivo: MotivoDaPerda, nota: string) => {
    try {
      await updateQuoteStatus.mutateAsync({ id: orderId, quoteStatus: 'rejected', motivoPerda: motivo, notaPerda: nota });
      setPerdendo(false);
      toast({ title: `Status atualizado para "${quoteStatusConfig.rejected?.label ?? 'Reprovado'}"` });
    } catch (err: any) {
      toast({ title: 'Erro ao atualizar status', description: err.message, variant: 'destructive' });
    }
  };

  const handleAbandon = async () => {
    setAbandoning(true);
    try {
      // (F5) a desistência do cliente é o motivo desistiu, num clique, como antes
      await updateQuoteStatus.mutateAsync({ id: orderId, quoteStatus: 'rejected', motivoPerda: 'desistiu' });
      toast({ title: 'Orçamento marcado como desistência do cliente.' });
    } catch (err: any) {
      toast({ title: 'Erro', description: err.message, variant: 'destructive' });
    } finally {
      setAbandoning(false);
    }
  };

  // awaiting_deposit: show "Receber sinal" + "Desistência" buttons
  if (isAwaitingDeposit) {
    return (
      <>
        <div className="flex items-center gap-1.5 flex-wrap">
          <span className={cn('inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium', cfg?.className)}>
            {cfg?.label}
          </span>
          <Button
            type="button"
            size="sm"
            disabled={isBusy}
            onClick={() => setDepositOpen(true)}
            className="h-6 px-2 text-xs gap-1 bg-orange-500 hover:bg-orange-600 text-white"
          >
            {isBusy && !abandoning ? <Loader2 className="h-3 w-3 animate-spin" /> : <DollarSign className="h-3 w-3" />}
            Receber sinal
          </Button>
          <Button
            type="button"
            size="sm"
            variant="outline"
            disabled={isBusy}
            onClick={pedirSemSinal}
            className="h-6 px-2 text-xs gap-1"
            title="Converter em OS sem sinal — o valor inteiro fica para a conclusão"
          >
            <ArrowRightCircle className="h-3 w-3" />
            Sem sinal
          </Button>
          <Button
            type="button"
            size="sm"
            variant="ghost"
            disabled={isBusy}
            onClick={handleAbandon}
            className="h-6 px-2 text-xs gap-1 text-destructive hover:text-destructive hover:bg-destructive/10"
            title="Desistência do cliente"
          >
            {abandoning ? <Loader2 className="h-3 w-3 animate-spin" /> : <XCircle className="h-3 w-3" />}
            Desistência
          </Button>
        </div>
        <RegisterDepositDialog
          open={depositOpen}
          onOpenChange={v => { setDepositOpen(v); if (!v) { setDeposit(null); setAppliedLabel(''); setInstallments(null); setScheduledEndAt(null); } }}
          serviceOrderId={orderId}
          serviceOrderNumber={serviceOrderNumber}
          grandTotal={grandTotal}
          laborCost={laborCost}
          partsCost={partsCost}
          discountRatio={deposit?.discountRatio ?? 1}
          expensesTotal={deposit?.expensesTotal ?? 0}
          presetServicesPct={deposit?.signal?.servicesPct}
          presetPartsPct={deposit?.signal?.partsPct}
          presetExpensesPct={deposit?.signal?.expensesPct}
          appliedConditionLabel={appliedLabel}
          installments={installments ?? undefined}
          scheduledEndAt={scheduledEndAt}
        />
        {semSinal.dialogo}
      </>
    );
  }

  const badge = (
    <button
      type="button"
      disabled={isBusy || validTransitions.length === 0}
      className={cn(
        'inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-medium transition-opacity',
        cfg?.className,
        isBusy ? 'opacity-50 cursor-wait'
          : validTransitions.length === 0 ? 'cursor-default'
          : 'cursor-pointer hover:opacity-80',
      )}
    >
      {isBusy
        ? <Loader2 className="h-3 w-3 animate-spin" />
        : <>{rotuloDoSelo}{validTransitions.length > 0 && <ChevronDown className="h-3 w-3 opacity-60" />}</>
      }
    </button>
  );

  // No transitions available (terminal with no reactivation)
  if (validTransitions.length === 0) {
    return (
      <span className={cn('inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium', cfg?.className)}>
        {rotuloDoSelo}
      </span>
    );
  }

  return (
    <>
    <DropdownMenu>
      <DropdownMenuTrigger asChild>{badge}</DropdownMenuTrigger>
      <DropdownMenuContent align="start" className="w-56">
        <DropdownMenuLabel className="text-[10px] font-semibold text-muted-foreground uppercase tracking-wide">
          Mover para
        </DropdownMenuLabel>
        <DropdownMenuSeparator />
        {validTransitions.map(target => {
          const targetCfg = quoteStatusConfig[target];
          const isReactivate = target === 'draft' && currentQuoteStatus === 'rejected';
          return (
            <DropdownMenuItem
              key={target}
              onClick={() => handleTransition(target)}
              className={cn(
                'gap-2 cursor-pointer',
                isReactivate && 'text-blue-700 focus:text-blue-700 focus:bg-blue-50',
              )}
            >
              {isReactivate && <RotateCcw className="h-3.5 w-3.5 shrink-0" />}
              <span className={cn(
                'inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium',
                targetCfg?.className,
              )}>
                {targetCfg?.label ?? target}
              </span>
            </DropdownMenuItem>
          );
        })}
        {currentQuoteStatus === 'approved' && (
          <>
            <DropdownMenuSeparator />
            <DropdownMenuItem onClick={pedirSemSinal} className="gap-2 cursor-pointer">
              <ArrowRightCircle className="h-3.5 w-3.5 shrink-0" />
              Converter em OS sem sinal
            </DropdownMenuItem>
          </>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
    {semSinal.dialogo}
    <JanelaDoPerdido
      aberta={perdendo}
      ocupado={updateQuoteStatus.isPending}
      numero={serviceOrderNumber}
      onFechar={() => setPerdendo(false)}
      onConfirmar={marcarPerdido}
    />
    </>
  );
}
