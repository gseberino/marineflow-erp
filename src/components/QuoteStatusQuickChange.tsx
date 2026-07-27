import { useState, useEffect } from 'react';
import { ChevronDown, Loader2, RotateCcw, DollarSign, XCircle } from 'lucide-react';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { Button } from '@/components/ui/button';
import { useToast } from '@/hooks/use-toast';
import { useUpdateQuoteStatus, QUOTE_STATUS_TRANSITIONS } from '@/hooks/use-service-orders';
import { quoteStatusConfig } from '@/lib/constants';
import { RegisterDepositDialog } from '@/components/RegisterDepositDialog';
import { cn } from '@/lib/utils';
import { supabase } from '@/integrations/supabase/client';
import { usePaymentConditionPresets } from '@/hooks/use-payment-conditions';
import { computeDeposit, type DepositComputation } from '@/lib/quote-deposit';

interface Props {
  orderId: string;
  currentQuoteStatus: string;
  serviceOrderNumber?: string;
  grandTotal?: number;
  laborCost?: number;
  partsCost?: number;
}

export function QuoteStatusQuickChange({ orderId, currentQuoteStatus, serviceOrderNumber = '', grandTotal = 0, laborCost = 0, partsCost = 0 }: Props) {
  const { toast } = useToast();
  const updateQuoteStatus = useUpdateQuoteStatus();
  const { data: paymentPresets } = usePaymentConditionPresets();
  const [depositOpen, setDepositOpen] = useState(false);
  const [abandoning, setAbandoning] = useState(false);
  const [deposit, setDeposit] = useState<DepositComputation | null>(null);
  const [appliedLabel, setAppliedLabel] = useState('');
  const [installments, setInstallments] = useState<any[] | null>(null);
  const isBusy = updateQuoteStatus.isPending || abandoning;

  // Ao abrir "Receber sinal": carrega os dados do orçamento + a condição de pagamento e computa
  // o sinal pela MESMA lib que o orçamento usa — para a janela bater exatamente com o orçamento
  // (com desconto e com o preset já definido), sem precisar abrir o orçamento.
  useEffect(() => {
    if (!depositOpen) return;
    let cancelled = false;
    (async () => {
      const { data: so } = await supabase
        .from('service_orders')
        .select('labor_cost_total, parts_cost_total, operational_cost_total, travel_cost_total, subcontract_cost_total, is_travel_billable, discount_amount, tax_amount, payment_condition_preset_id, payment_conditions, custom_payment_installments')
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
    })();
    return () => { cancelled = true; };
  }, [depositOpen, orderId, paymentPresets]);

  const cfg = quoteStatusConfig[currentQuoteStatus];
  const validTransitions = QUOTE_STATUS_TRANSITIONS[currentQuoteStatus] ?? [];
  const isAwaitingDeposit = currentQuoteStatus === 'awaiting_deposit';

  const handleTransition = async (target: string) => {
    try {
      await updateQuoteStatus.mutateAsync({ id: orderId, quoteStatus: target });
      const label = quoteStatusConfig[target]?.label ?? target;
      toast({ title: `Status atualizado para "${label}"` });
    } catch (err: any) {
      toast({ title: 'Erro ao atualizar status', description: err.message, variant: 'destructive' });
    }
  };

  const handleAbandon = async () => {
    setAbandoning(true);
    try {
      await updateQuoteStatus.mutateAsync({ id: orderId, quoteStatus: 'rejected' });
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
          onOpenChange={v => { setDepositOpen(v); if (!v) { setDeposit(null); setAppliedLabel(''); setInstallments(null); } }}
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
        />
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
        : <>{cfg?.label ?? currentQuoteStatus}{validTransitions.length > 0 && <ChevronDown className="h-3 w-3 opacity-60" />}</>
      }
    </button>
  );

  // No transitions available (terminal with no reactivation)
  if (validTransitions.length === 0) {
    return (
      <span className={cn('inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium', cfg?.className)}>
        {cfg?.label ?? currentQuoteStatus}
      </span>
    );
  }

  return (
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
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
