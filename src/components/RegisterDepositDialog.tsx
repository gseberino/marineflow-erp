import { useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Loader2, DollarSign, Info, Percent, Tag, Hash, Paperclip, X, CalendarClock } from 'lucide-react';
import { StockConfirmationDialog } from '@/components/StockConfirmationDialog';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Textarea } from '@/components/ui/textarea';
import { DatePickerBR, todayISO } from '@/components/ui/date-picker-br';
import { useToast } from '@/hooks/use-toast';
import { useAppSettings } from '@/hooks/use-app-settings';
import { supabase } from '@/integrations/supabase/client';
import { useQueryClient } from '@tanstack/react-query';
import { cn } from '@/lib/utils';
import { depositAmountFromPcts, signalPctsFromInstallments, computeScheduleFromParts, type DepositInstallment } from '@/lib/quote-deposit';
import { usePaymentConditionPresets } from '@/hooks/use-payment-conditions';
import { addDays, format, parseISO } from 'date-fns';

const PAYMENT_METHODS = [
  { value: 'pix',           label: 'PIX' },
  { value: 'cash',          label: 'Dinheiro' },
  { value: 'bank_transfer', label: 'Transferência Bancária' },
  { value: 'debit_card',    label: 'Cartão de Débito' },
  { value: 'credit_card',   label: 'Cartão de Crédito' },
  { value: 'boleto',        label: 'Boleto' },
  { value: 'check',         label: 'Cheque' },
];

type DepositMode = 'category' | 'percent' | 'fixed';

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  serviceOrderId: string;
  serviceOrderNumber: string;
  grandTotal: number;
  navigateOnSuccess?: boolean;
  // Pre-fill from payment condition preset
  presetServicesPct?: number;
  presetPartsPct?: number;
  laborCost?: number;
  partsCost?: number;
  // Sincronização com o orçamento: o sinal por categoria é sobre valores COM desconto.
  // discountRatio = base(líquido)/subtotal(bruto); expensesTotal e presetExpensesPct entram
  // na parcela como o orçamento faz. Padrões (1/0) preservam o comportamento antigo.
  discountRatio?: number;
  expensesTotal?: number;
  presetExpensesPct?: number;
  /** Rótulo da condição de pagamento já definida no orçamento — para o seletor já vir marcado. */
  appliedConditionLabel?: string;
  /** Parcelas da condição — usadas na prévia do saldo quando não é um preset nomeado (custom). */
  installments?: DepositInstallment[];
  /** Entrega prevista (scheduled_end_at) — vencimento das parcelas de saldo do tipo "na entrega". */
  scheduledEndAt?: string | null;
}

const fmt = (v: number) =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);

export function RegisterDepositDialog({
  open,
  onOpenChange,
  serviceOrderId,
  serviceOrderNumber,
  grandTotal,
  navigateOnSuccess = true,
  presetServicesPct,
  presetPartsPct,
  laborCost = 0,
  partsCost = 0,
  discountRatio = 1,
  expensesTotal = 0,
  presetExpensesPct = 0,
  appliedConditionLabel = '',
  installments,
  scheduledEndAt,
}: Props) {
  const { toast } = useToast();
  const navigate = useNavigate();
  const qc = useQueryClient();
  const { data: settingsMap } = useAppSettings();
  const { data: paymentPresets } = usePaymentConditionPresets();

  const depositPctGlobal = Number(settingsMap?.['quote_deposit_percentage'] ?? 30);
  const defaultMethod    = settingsMap?.['default_payment_method'] ?? 'pix';
  const defaultFee       = Number(settingsMap?.['default_card_fee_percent'] ?? 0);

  // Determine initial mode: category if preset has specific pcts, else percent
  const hasPresetPcts = (presetServicesPct !== undefined && presetServicesPct > 0) ||
                        (presetPartsPct !== undefined && presetPartsPct > 0);

  const [mode, setMode]             = useState<DepositMode>(hasPresetPcts ? 'category' : 'percent');
  const [servicesPct, setServicesPct] = useState(presetServicesPct ?? 0);
  const [partsPct, setPartsPct]       = useState(presetPartsPct ?? 0);
  const [expensesPct, setExpensesPct] = useState(presetExpensesPct);
  const [presetLabel, setPresetLabel] = useState('');
  const [globalPct, setGlobalPct]     = useState(depositPctGlobal);
  const [fixedValue, setFixedValue]   = useState('');
  const [method, setMethod]           = useState(defaultMethod);
  const [cardFee, setCardFee]         = useState(String(defaultFee));
  const [date, setDate]               = useState(todayISO());
  const [notes, setNotes]             = useState('');
  const [loading, setLoading]         = useState(false);
  const [stockConfirmOpen, setStockConfirmOpen] = useState(false);
  const [receiptUrl, setReceiptUrl]   = useState('');
  const [receiptPath, setReceiptPath] = useState('');
  const [uploadingReceipt, setUploadingReceipt] = useState(false);
  const receiptInputRef = useRef<HTMLInputElement>(null);

  // Reset geral ao abrir (não depende dos presets, que podem chegar depois via fetch).
  useEffect(() => {
    if (!open) return;
    setGlobalPct(depositPctGlobal);
    setFixedValue('');
    setMethod(defaultMethod);
    setCardFee(String(defaultFee));
    setDate(todayISO());
    setNotes('');
    setPresetLabel('');
    setReceiptUrl('');
    setReceiptPath('');
  }, [open]);

  // Sincroniza os % com o preset do orçamento — inclusive quando ele chega ASSÍNCRONO (a lista
  // busca a condição ao abrir). Só mexe nos %/modo, sem resetar método/data/observações.
  useEffect(() => {
    if (!open) return;
    setServicesPct(presetServicesPct ?? 0);
    setPartsPct(presetPartsPct ?? 0);
    setExpensesPct(presetExpensesPct ?? 0);
    if ((presetServicesPct ?? 0) > 0 || (presetPartsPct ?? 0) > 0) setMode('category');
  }, [open, presetServicesPct, presetPartsPct, presetExpensesPct]);

  // Marca no seletor a condição JÁ definida no orçamento (só se ela existir na lista de presets —
  // condições avulsas/custom não têm rótulo a exibir). Roda também quando os presets chegam async.
  useEffect(() => {
    if (!open) return;
    const lbl = appliedConditionLabel || '';
    setPresetLabel(lbl && (paymentPresets || []).some((p: any) => p.label === lbl) ? lbl : '');
  }, [open, appliedConditionLabel, paymentPresets]);

  // Escolha de uma condição de pagamento pré-cadastrada direto no diálogo (agiliza o lançamento
  // sem abrir o orçamento). Preenche serviços/peças/despesas % com a parcela de SINAL do preset.
  const applyPreset = (label: string) => {
    setPresetLabel(label);
    const preset = (paymentPresets || []).find((p: any) => p.label === label);
    const pcts = preset ? signalPctsFromInstallments((preset as any).installments) : null;
    if (pcts) {
      setServicesPct(pcts.servicesPct);
      setPartsPct(pcts.partsPct);
      setExpensesPct(pcts.expensesPct);
      setMode('category');
      // Condição sem parcela de entrada (0%): avisa em vez de deixar o valor mudar sem explicação.
      if (pcts.servicesPct === 0 && pcts.partsPct === 0 && pcts.expensesPct === 0) {
        toast({ title: 'Condição sem entrada', description: 'Essa condição não prevê sinal (0%). Ajuste os % ou escolha outra.' });
      }
    } else {
      toast({ title: 'Condição sem parcela de sinal', description: 'Nenhuma parcela de entrada (aprovação/dia 0) foi definida nessa condição.' });
    }
  };

  // Valores COM desconto (o mesmo discountRatio que o orçamento aplica). Padrão ratio=1
  // mantém o comportamento antigo quando o caller não passa o desconto.
  const ratio = discountRatio && discountRatio > 0 ? discountRatio : 1;
  const laborNet = laborCost * ratio;
  const partsNet = partsCost * ratio;
  const expensesComponent = Math.round((expensesTotal * expensesPct / 100) * ratio * 100) / 100;

  // (D) Quanto de desconto do orçamento já está embutido nos valores exibidos.
  const discountApplied = Math.round((laborCost + partsCost + expensesTotal) * (1 - ratio) * 100) / 100;

  // (C) Prévia do saldo: parcelas da condição selecionada (preset nomeado ou custom do orçamento),
  // fora a entrada, com a mesma conta do sinal. Reage à condição escolhida no seletor.
  const activeInstallments = useMemo<DepositInstallment[]>(() => {
    const p = (paymentPresets || []).find((x: any) => x.label === presetLabel);
    if (p && Array.isArray((p as any).installments)) return (p as any).installments as DepositInstallment[];
    return Array.isArray(installments) ? installments : [];
  }, [presetLabel, paymentPresets, installments]);

  const schedule = useMemo(
    () => computeScheduleFromParts(laborCost, partsCost, expensesTotal, ratio, activeInstallments),
    [laborCost, partsCost, expensesTotal, ratio, activeInstallments],
  );

  // Vencimento de cada parcela do saldo:
  //  - 'delivery' → entrega prevista (scheduled_end_at); sem ela, fallback de +30 dias do sinal.
  //  - 'days'     → data do sinal + N dias.
  const deliveryISO = scheduledEndAt ? scheduledEndAt.slice(0, 10) : '';
  const resolveDueDate = (row: { days: number; dueBasis: 'delivery' | 'days' }): string => {
    const base = parseISO(date);
    if (row.dueBasis === 'delivery') {
      return deliveryISO || format(addDays(base, 30), 'yyyy-MM-dd');
    }
    return format(addDays(base, row.days || 0), 'yyyy-MM-dd');
  };

  // Calculate deposit amount from current mode
  const calcAmount = (): number => {
    if (mode === 'category') {
      // Fonte única (mesma conta do orçamento): (labor·svc% + parts·parts% + desp·exp%) × ratio.
      return depositAmountFromPcts(laborCost, partsCost, expensesTotal, ratio, servicesPct, partsPct, expensesPct);
    }
    if (mode === 'percent') {
      // grandTotal já é o valor líquido (com desconto) — não reaplicar ratio.
      return Math.round(grandTotal * globalPct / 100 * 100) / 100;
    }
    return parseFloat(fixedValue.replace(',', '.')) || 0;
  };

  const depositAmount = calcAmount();
  const isCredit      = method === 'credit_card';
  const feeAmt        = isCredit ? depositAmount * (parseFloat(cardFee) / 100) : 0;
  const netAmt        = depositAmount - feeAmt;
  const isValid       = depositAmount > 0 && date;

  // (E) Anexa o comprovante do pagamento — mesmo bucket/padrão dos comprovantes de despesa.
  const handleReceiptUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploadingReceipt(true);
    try {
      const ext = file.name.split('.').pop() || 'bin';
      const uuid = (crypto as any).randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
      const path = `deposits/${serviceOrderId}/${uuid}.${ext}`;
      const { error: upErr } = await supabase.storage.from('expense-receipts').upload(path, file, { contentType: file.type, upsert: false });
      if (upErr) throw upErr;
      const { data: urlData } = supabase.storage.from('expense-receipts').getPublicUrl(path);
      setReceiptUrl(urlData.publicUrl);
      setReceiptPath(path);
      toast({ title: 'Comprovante anexado' });
    } catch (err: any) {
      toast({ title: 'Erro ao anexar comprovante', description: err.message, variant: 'destructive' });
    } finally {
      setUploadingReceipt(false);
      if (receiptInputRef.current) receiptInputRef.current.value = '';
    }
  };

  const handleRemoveReceipt = async () => {
    if (receiptPath) {
      try { await supabase.storage.from('expense-receipts').remove([receiptPath]); } catch { /* segue limpando o form */ }
    }
    setReceiptUrl('');
    setReceiptPath('');
  };

  const handleConfirm = async () => {
    if (!isValid) return;
    setLoading(true);
    try {
      // Saldo como CONTA A RECEBER: monta as parcelas do saldo (com vencimento resolvido) e a RPC
      // cria um recebível PENDENTE por parcela + a cobrança vinculada (sem auto-envio). Só no modo
      // "por categoria" — em %/valor fixo o sinal é ad-hoc e não reconcilia com o saldo da condição.
      const balancePayload = mode === 'category'
        ? schedule.balance.map((r) => ({
            description: `${r.label} — ${serviceOrderNumber}`,
            amount: r.amount,
            due_date: resolveDueDate(r),
          }))
        : [];

      const { data, error } = await supabase.rpc('register_deposit_and_convert', {
        p_service_order_id:     serviceOrderId,
        p_amount:               depositAmount,
        p_payment_date:         date,
        p_payment_method:       method,
        p_card_fee_percent:     isCredit ? parseFloat(cardFee) : 0,
        p_notes:                notes.trim() || null,
        p_balance_installments: balancePayload.length > 0 ? balancePayload : null,
        p_create_collections:   true,
      });
      if (error) throw error;
      const paymentId = (data as any)?.payment_id as string | undefined;
      const balanceCreated = Number((data as any)?.balance_receivables ?? 0);

      // (B) Se o usuário trocou a condição no diálogo, grava-a no orçamento para PDF/saldo baterem.
      if (presetLabel && presetLabel !== appliedConditionLabel) {
        const preset = (paymentPresets || []).find((p: any) => p.label === presetLabel);
        if (preset) {
          await supabase.from('service_orders').update({
            payment_condition_preset_id: (preset as any).id,
            payment_conditions: (preset as any).label,
          } as never).eq('id', serviceOrderId);
        }
      }

      // (E) Vincula o comprovante ao pagamento recém-criado.
      if (receiptUrl && paymentId) {
        await supabase.from('payments').update({
          receipt_url: receiptUrl,
          receipt_storage_path: receiptPath,
        } as never).eq('id', paymentId);
      }

      toast({
        title: 'Sinal registrado!',
        description: balanceCreated > 0
          ? `${serviceOrderNumber} convertido em OS · saldo lançado em ${balanceCreated} conta(s) a receber. Confirme o estoque.`
          : `${serviceOrderNumber} convertido em OS. Confirme o estoque das peças.`,
      });
      qc.invalidateQueries({ queryKey: ['service-orders'] });
      qc.invalidateQueries({ queryKey: ['receivables'] });
      qc.invalidateQueries({ queryKey: ['collections'] });
      onOpenChange(false);
      // Open stock confirmation step
      setStockConfirmOpen(true);
    } catch (err: any) {
      toast({ title: 'Erro ao registrar sinal', description: err.message, variant: 'destructive' });
    } finally {
      setLoading(false);
    }
  };

  const ModeBtn = ({ m, label, icon: Icon }: { m: DepositMode; label: string; icon: any }) => (
    <button
      type="button"
      onClick={() => setMode(m)}
      className={cn(
        'flex items-center gap-1.5 px-3 py-1.5 rounded-md text-xs font-medium border transition-colors',
        mode === m
          ? 'bg-primary text-primary-foreground border-primary'
          : 'bg-background text-muted-foreground border-border hover:bg-muted',
      )}
    >
      <Icon className="h-3.5 w-3.5" /> {label}
    </button>
  );

  return (
    <>
    {stockConfirmOpen && (
      <StockConfirmationDialog
        open={stockConfirmOpen}
        onOpenChange={v => {
          setStockConfirmOpen(v);
          if (!v && navigateOnSuccess) navigate(`/service-orders/${serviceOrderId}`);
        }}
        serviceOrderId={serviceOrderId}
        serviceOrderNumber={serviceOrderNumber}
      />
    )}
    <Dialog open={open} onOpenChange={v => !loading && onOpenChange(v)}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <DollarSign className="h-5 w-5 text-orange-500" />
            Registrar pagamento do sinal
          </DialogTitle>
          <DialogDescription>
            {serviceOrderNumber} · Total: {fmt(grandTotal)}
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4 py-1">
          {/* Condição de pagamento pré-cadastrada — preenche os % do sinal na hora */}
          {(paymentPresets || []).length > 0 && (
            <div className="space-y-1.5">
              <Label className="text-xs text-muted-foreground">Condição de pagamento</Label>
              <Select value={presetLabel} onValueChange={applyPreset}>
                <SelectTrigger>
                  <SelectValue placeholder="Escolher condição pré-cadastrada…" />
                </SelectTrigger>
                <SelectContent>
                  {(paymentPresets || []).map((p: any) => (
                    <SelectItem key={p.id} value={p.label}>{p.label}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          )}

          {/* Mode selector */}
          <div className="space-y-1.5">
            <Label className="text-xs text-muted-foreground">Modo de cálculo</Label>
            <div className="flex gap-2 flex-wrap">
              <ModeBtn m="category" label="Por categoria" icon={Tag} />
              <ModeBtn m="percent"  label="% do total"   icon={Percent} />
              <ModeBtn m="fixed"    label="Valor fixo"    icon={Hash} />
            </div>
          </div>

          {/* (D) Desconto do orçamento já embutido — dá confiança de que o valor está sincronizado */}
          {mode === 'category' && discountApplied > 0 && (
            <p className="text-xs text-muted-foreground -mt-1">
              Valores já com o desconto do orçamento aplicado (−{fmt(discountApplied)}).
            </p>
          )}

          {/* Mode: category */}
          {mode === 'category' && (
            <div className="rounded-lg border bg-muted/30 p-3 space-y-3">
              <div className="flex items-center justify-between text-sm">
                <span className="text-muted-foreground">Serviços ({fmt(laborNet)})</span>
                <div className="flex items-center gap-2">
                  <Input
                    type="number" min="0" max="100" step="5"
                    className="w-20 h-7 text-right text-sm"
                    value={servicesPct}
                    onChange={e => { setServicesPct(Math.min(100, parseFloat(e.target.value) || 0)); setPresetLabel(''); }}
                  />
                  <span className="text-xs text-muted-foreground w-24 text-right">
                    = {fmt(laborNet * servicesPct / 100)}
                  </span>
                </div>
              </div>
              <div className="flex items-center justify-between text-sm">
                <span className="text-muted-foreground">Peças ({fmt(partsNet)})</span>
                <div className="flex items-center gap-2">
                  <Input
                    type="number" min="0" max="100" step="5"
                    className="w-20 h-7 text-right text-sm"
                    value={partsPct}
                    onChange={e => { setPartsPct(Math.min(100, parseFloat(e.target.value) || 0)); setPresetLabel(''); }}
                  />
                  <span className="text-xs text-muted-foreground w-24 text-right">
                    = {fmt(partsNet * partsPct / 100)}
                  </span>
                </div>
              </div>
              {expensesComponent > 0 && (
                <div className="flex items-center justify-between text-sm">
                  <span className="text-muted-foreground">Despesas ({expensesPct}%)</span>
                  <span className="text-xs text-muted-foreground w-24 text-right">= {fmt(expensesComponent)}</span>
                </div>
              )}
              <div className="flex items-center justify-between pt-2 border-t font-medium text-sm">
                <span>Total do sinal</span>
                <span className="text-lg font-bold text-orange-600">{fmt(depositAmount)}</span>
              </div>
            </div>
          )}

          {/* Mode: percent */}
          {mode === 'percent' && (
            <div className="flex items-center gap-3">
              <Input
                type="number" min="0" max="100" step="5"
                className="w-24 text-center font-semibold text-lg"
                value={globalPct}
                onChange={e => setGlobalPct(Math.min(100, parseFloat(e.target.value) || 0))}
              />
              <span className="text-muted-foreground text-sm">% do total =</span>
              <span className="text-lg font-bold text-orange-600">{fmt(depositAmount)}</span>
            </div>
          )}

          {/* Mode: fixed */}
          {mode === 'fixed' && (
            <div className="flex items-center gap-2">
              <span className="text-muted-foreground text-sm">R$</span>
              <Input
                className="text-right text-lg font-semibold"
                value={fixedValue}
                onChange={e => setFixedValue(e.target.value)}
                placeholder="0,00"
              />
            </div>
          )}

          {/* (C) Prévia do saldo — as parcelas que vêm depois da entrada, com a mesma conta do sinal.
              Só no modo "por categoria": nos modos %/valor fixo o sinal é ad-hoc e não gera saldo. */}
          {mode === 'category' && schedule.balance.length > 0 && (
            <div className="rounded-lg border bg-muted/20 p-3 space-y-1.5 text-sm">
              <div className="flex items-center gap-1.5 text-xs font-medium text-muted-foreground">
                <CalendarClock className="h-3.5 w-3.5" /> Saldo após o sinal
              </div>
              {schedule.balance.map((r, i) => {
                const dueLabel = r.dueBasis === 'delivery'
                  ? (deliveryISO ? `entrega ${format(parseISO(deliveryISO), 'dd/MM/yyyy')}` : 'na entrega')
                  : `${r.days} dia${r.days === 1 ? '' : 's'}`;
                return (
                  <div key={i} className="flex items-center justify-between">
                    <span className="text-muted-foreground">{r.label} · {dueLabel}</span>
                    <span>{fmt(r.amount)}</span>
                  </div>
                );
              })}
              <div className="flex items-center justify-between pt-1.5 border-t font-medium">
                <span>Total do saldo</span>
                <span>{fmt(schedule.balanceTotal)}</span>
              </div>
              <p className="text-[11px] text-muted-foreground">
                Ao confirmar, essas cobranças são criadas automaticamente (sem envio de WhatsApp).
              </p>
            </div>
          )}

          {/* Payment method */}
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label>Meio de pagamento</Label>
              <Select value={method} onValueChange={setMethod}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {PAYMENT_METHODS.map(m => (
                    <SelectItem key={m.value} value={m.value}>{m.label}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>Data</Label>
              <DatePickerBR value={date} onChange={setDate} />
            </div>
          </div>

          {/* Card fee */}
          {isCredit && (
            <div className="flex items-center gap-3 rounded-lg bg-blue-50 border border-blue-200 p-3 text-sm">
              <div className="flex items-center gap-2">
                <Label className="text-blue-700 whitespace-nowrap">Taxa cartão</Label>
                <Input
                  type="number" min="0" max="10" step="0.1"
                  className="w-20 h-7 text-right"
                  value={cardFee}
                  onChange={e => setCardFee(e.target.value)}
                />
                <span className="text-blue-600">%</span>
              </div>
              <span className="ml-auto text-blue-700">
                Líquido: <strong>{fmt(netAmt)}</strong>
              </span>
            </div>
          )}

          {/* Notes */}
          <div className="space-y-1.5">
            <Label>Observações <span className="text-muted-foreground font-normal">(opcional)</span></Label>
            <Textarea
              value={notes}
              onChange={e => setNotes(e.target.value)}
              rows={2}
              className="resize-none"
              placeholder="Comprovante, referência..."
            />
          </div>

          {/* (E) Comprovante do pagamento (opcional) */}
          <div className="space-y-1.5">
            <Label>Comprovante <span className="text-muted-foreground font-normal">(opcional)</span></Label>
            {receiptUrl ? (
              <div className="flex items-center gap-2 text-sm">
                <a href={receiptUrl} target="_blank" rel="noreferrer" className="flex items-center gap-1 text-blue-600 underline">
                  <Paperclip className="h-3.5 w-3.5" /> Comprovante anexado
                </a>
                <Button type="button" variant="ghost" size="sm" onClick={handleRemoveReceipt} className="h-6 px-2 text-muted-foreground">
                  <X className="h-3.5 w-3.5" />
                </Button>
              </div>
            ) : (
              <div>
                <input
                  ref={receiptInputRef}
                  type="file"
                  accept="image/*,application/pdf"
                  className="hidden"
                  onChange={handleReceiptUpload}
                />
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  disabled={uploadingReceipt}
                  onClick={() => receiptInputRef.current?.click()}
                  className="gap-1.5"
                >
                  {uploadingReceipt ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Paperclip className="h-3.5 w-3.5" />}
                  Anexar comprovante
                </Button>
              </div>
            )}
          </div>

          {/* Warning */}
          <div className="flex gap-2 rounded-lg bg-orange-50 border border-orange-200 p-3 text-sm text-orange-800">
            <Info className="h-4 w-4 shrink-0 mt-0.5" />
            <span>Ao confirmar, o orçamento será convertido em <strong>Ordem de Serviço</strong> automaticamente.</span>
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={loading}>
            Cancelar
          </Button>
          <Button
            onClick={handleConfirm}
            disabled={!isValid || loading}
            className="gap-2 bg-orange-500 hover:bg-orange-600 text-white"
          >
            {loading
              ? <Loader2 className="h-4 w-4 animate-spin" />
              : <DollarSign className="h-4 w-4" />
            }
            {loading ? 'Registrando...' : `Confirmar — ${fmt(depositAmount)}`}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
    </>
  );
}
