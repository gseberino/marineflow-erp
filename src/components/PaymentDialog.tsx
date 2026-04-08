import { useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useI18n } from '@/i18n';
import { usePayments, useRegisterPayment } from '@/hooks/use-financial';
import { useCardFees } from '@/hooks/use-card-fees';
import { toast } from 'sonner';
import { Separator } from '@/components/ui/separator';
import { StatusBadge } from '@/components/StatusBadge';

interface PaymentDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  receivable?: any;
  payable?: any;
}

const METHOD_OPTIONS = [
  { value: 'pix', labelKey: 'pix' },
  { value: 'credit_card', labelKey: 'credit_card' },
  { value: 'debit_card', labelKey: 'debit_card' },
  { value: 'cash', labelKey: 'cash' },
  { value: 'bank_transfer', labelKey: 'bank_transfer' },
  { value: 'check', labelKey: 'check' },
] as const;

export function PaymentDialog({ open, onOpenChange, receivable, payable }: PaymentDialogProps) {
  const { t, formatCurrency } = useI18n();
  const record = receivable || payable;
  const isReceivable = !!receivable;
  const parentId = record?.id;

  const { data: payments } = usePayments(
    isReceivable ? parentId : undefined,
    !isReceivable ? parentId : undefined
  );
  const { data: cardFees } = useCardFees();
  const registerPayment = useRegisterPayment();

  const [showDetailed, setShowDetailed] = useState(false);
  const [method, setMethod] = useState('pix');
  const [installments, setInstallments] = useState(1);
  const [paymentDate, setPaymentDate] = useState(new Date().toISOString().split('T')[0]);
  const [amount, setAmount] = useState(Number(record?.balance_amount || 0));
  const [notes, setNotes] = useState('');

  if (!record) return null;

  const balance = Number(record.balance_amount || 0);
  const totalAmount = Number(record.amount || 0);
  const paidSoFar = Number(record.paid_amount || 0);

  const selectedFee = method === 'credit_card' && cardFees
    ? cardFees.find(f => f.installments === installments)?.fee_percent || 0
    : 0;
  const feePercent = Number(selectedFee);
  const grossAmount = feePercent > 0 ? amount / (1 - feePercent / 100) : amount;
  const feeAmount = grossAmount - amount;

  const handleQuickPay = async () => {
    try {
      await registerPayment.mutateAsync({
        receivable_id: isReceivable ? parentId : undefined,
        payable_id: !isReceivable ? parentId : undefined,
        payment_date: new Date().toISOString().split('T')[0],
        amount: balance,
        payment_method: method,
        installments: method === 'credit_card' ? installments : 1,
        card_fee_percent: feePercent,
        net_amount: balance,
      });
      toast.success(t.financial.markAsPaid);
      onOpenChange(false);
    } catch { toast.error('Erro ao registrar pagamento'); }
  };

  const handleDetailedPay = async () => {
    try {
      await registerPayment.mutateAsync({
        receivable_id: isReceivable ? parentId : undefined,
        payable_id: !isReceivable ? parentId : undefined,
        payment_date: paymentDate,
        amount,
        payment_method: method,
        installments: method === 'credit_card' ? installments : 1,
        card_fee_percent: feePercent,
        net_amount: amount,
        notes,
      });
      toast.success(t.financial.registerPayment);
      onOpenChange(false);
    } catch { toast.error('Erro ao registrar pagamento'); }
  };

  const methods = t.financial.methods as Record<string, string>;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{t.financial.registerPayment}</DialogTitle>
        </DialogHeader>

        <div className="space-y-4">
          {/* Summary */}
          <div className="rounded-lg border p-4 space-y-2">
            <p className="font-medium">{record.description}</p>
            <div className="grid grid-cols-3 gap-2 text-sm">
              <div><span className="text-muted-foreground">{t.common.amount}:</span><br /><span className="font-semibold">{formatCurrency(totalAmount)}</span></div>
              <div><span className="text-muted-foreground">Pago:</span><br /><span className="font-semibold text-success">{formatCurrency(paidSoFar)}</span></div>
              <div><span className="text-muted-foreground">{t.common.balance}:</span><br /><span className="font-semibold text-warning">{formatCurrency(balance)}</span></div>
            </div>
          </div>

          {/* Payment history */}
          {payments && payments.length > 0 && (
            <div>
              <p className="text-sm font-medium text-muted-foreground mb-2">{t.financial.paymentHistory}</p>
              <div className="space-y-1">
                {payments.map(p => (
                  <div key={p.id} className="flex justify-between text-sm border-b pb-1">
                    <span>{new Date(p.payment_date).toLocaleDateString('pt-BR')}</span>
                    <span className="text-muted-foreground">{methods[p.payment_method] || p.payment_method}</span>
                    <span className="font-medium">{formatCurrency(Number(p.amount))}</span>
                  </div>
                ))}
              </div>
            </div>
          )}

          <Separator />

          {/* Method selection */}
          <div className="space-y-2">
            <Label>{t.financial.paymentMethod}</Label>
            <Select value={method} onValueChange={setMethod}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {METHOD_OPTIONS.map(m => (
                  <SelectItem key={m.value} value={m.value}>{methods[m.value] || m.value}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {/* Card installments */}
          {method === 'credit_card' && cardFees && (
            <div className="space-y-2">
              <Label>{t.serviceOrders.cardInstallments}</Label>
              <div className="flex gap-1">
                {cardFees.map(f => (
                  <Button key={f.installments} size="sm"
                    variant={installments === f.installments ? 'default' : 'outline'}
                    onClick={() => setInstallments(f.installments)}>
                    {f.installments}x
                  </Button>
                ))}
              </div>
              {feePercent > 0 && (
                <div className="text-sm space-y-1 bg-muted/50 rounded-md p-3">
                  <div className="flex justify-between"><span>{t.serviceOrders.cardGrossAmount}:</span><span className="font-bold">{formatCurrency(grossAmount)}</span></div>
                  {installments > 1 && <div className="flex justify-between"><span>{t.serviceOrders.cardInstallmentValue}:</span><span>{formatCurrency(grossAmount / installments)}</span></div>}
                  <div className="flex justify-between text-muted-foreground"><span>{t.serviceOrders.cardFeeAmount} ({feePercent}%):</span><span>{formatCurrency(feeAmount)}</span></div>
                  <div className="flex justify-between text-success"><span>{t.serviceOrders.cardNetAmount}:</span><span className="font-semibold">{formatCurrency(showDetailed ? amount : balance)}</span></div>
                </div>
              )}
            </div>
          )}

          {/* Quick pay */}
          {!showDetailed && (
            <Button className="w-full" onClick={handleQuickPay} disabled={registerPayment.isPending || balance <= 0}>
              {t.financial.markAsPaid} ({formatCurrency(balance)})
            </Button>
          )}

          {/* Toggle */}
          <button className="text-sm text-primary underline" onClick={() => setShowDetailed(!showDetailed)}>
            {showDetailed ? '← Pagamento rápido' : t.financial.partialPayment}
          </button>

          {/* Detailed */}
          {showDetailed && (
            <div className="space-y-3 border-t pt-3">
              <div className="grid grid-cols-2 gap-3">
                <div><Label>{t.financial.paymentDate}</Label><Input type="date" value={paymentDate} onChange={e => setPaymentDate(e.target.value)} /></div>
                <div><Label>{t.common.amount}</Label><Input type="number" step="0.01" value={amount} onChange={e => setAmount(parseFloat(e.target.value) || 0)} /></div>
              </div>
              {amount > 0 && (
                <p className="text-sm">
                  {t.financial.remainingBalance}: <span className={balance - amount < 0 ? 'text-destructive font-semibold' : 'text-success font-semibold'}>
                    {formatCurrency(Math.max(0, balance - amount))}
                  </span>
                  {amount > balance && <span className="text-destructive text-xs ml-2">(pagamento a maior)</span>}
                </p>
              )}
              <div><Label>{t.common.notes}</Label><Input value={notes} onChange={e => setNotes(e.target.value)} /></div>
              <Button className="w-full" onClick={handleDetailedPay} disabled={registerPayment.isPending || amount <= 0}>
                {t.financial.registerPayment}
              </Button>
            </div>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}
