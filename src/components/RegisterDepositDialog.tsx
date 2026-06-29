import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Loader2, DollarSign, Info, Percent, Tag, Hash } from 'lucide-react';
import { StockConfirmationDialog } from '@/components/StockConfirmationDialog';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Textarea } from '@/components/ui/textarea';
import { useToast } from '@/hooks/use-toast';
import { useAppSettings } from '@/hooks/use-app-settings';
import { supabase } from '@/integrations/supabase/client';
import { useQueryClient } from '@tanstack/react-query';
import { cn } from '@/lib/utils';

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
}: Props) {
  const { toast } = useToast();
  const navigate = useNavigate();
  const qc = useQueryClient();
  const { data: settingsMap } = useAppSettings();

  const depositPctGlobal = Number(settingsMap?.['quote_deposit_percentage'] ?? 30);
  const defaultMethod    = settingsMap?.['default_payment_method'] ?? 'pix';
  const defaultFee       = Number(settingsMap?.['default_card_fee_percent'] ?? 0);

  // Determine initial mode: category if preset has specific pcts, else percent
  const hasPresetPcts = (presetServicesPct !== undefined && presetServicesPct > 0) ||
                        (presetPartsPct !== undefined && presetPartsPct > 0);

  const [mode, setMode]             = useState<DepositMode>(hasPresetPcts ? 'category' : 'percent');
  const [servicesPct, setServicesPct] = useState(presetServicesPct ?? 0);
  const [partsPct, setPartsPct]       = useState(presetPartsPct ?? 0);
  const [globalPct, setGlobalPct]     = useState(depositPctGlobal);
  const [fixedValue, setFixedValue]   = useState('');
  const [method, setMethod]           = useState(defaultMethod);
  const [cardFee, setCardFee]         = useState(String(defaultFee));
  const [date, setDate]               = useState(new Date().toISOString().split('T')[0]);
  const [notes, setNotes]             = useState('');
  const [loading, setLoading]         = useState(false);
  const [stockConfirmOpen, setStockConfirmOpen] = useState(false);

  useEffect(() => {
    if (!open) return;
    const initMode: DepositMode = hasPresetPcts ? 'category' : 'percent';
    setMode(initMode);
    setServicesPct(presetServicesPct ?? 0);
    setPartsPct(presetPartsPct ?? 0);
    setGlobalPct(depositPctGlobal);
    setFixedValue('');
    setMethod(defaultMethod);
    setCardFee(String(defaultFee));
    setDate(new Date().toISOString().split('T')[0]);
    setNotes('');
  }, [open]);

  // Calculate deposit amount from current mode
  const calcAmount = (): number => {
    if (mode === 'category') {
      return Math.round(
        (laborCost * servicesPct / 100 + partsCost * partsPct / 100) * 100
      ) / 100;
    }
    if (mode === 'percent') {
      return Math.round(grandTotal * globalPct / 100 * 100) / 100;
    }
    return parseFloat(fixedValue.replace(',', '.')) || 0;
  };

  const depositAmount = calcAmount();
  const isCredit      = method === 'credit_card';
  const feeAmt        = isCredit ? depositAmount * (parseFloat(cardFee) / 100) : 0;
  const netAmt        = depositAmount - feeAmt;
  const isValid       = depositAmount > 0 && date;

  const handleConfirm = async () => {
    if (!isValid) return;
    setLoading(true);
    try {
      const { error } = await supabase.rpc('register_deposit_and_convert', {
        p_service_order_id:  serviceOrderId,
        p_amount:            depositAmount,
        p_payment_date:      date,
        p_payment_method:    method,
        p_card_fee_percent:  isCredit ? parseFloat(cardFee) : 0,
        p_notes:             notes.trim() || null,
      });
      if (error) throw error;

      toast({
        title: 'Sinal registrado!',
        description: `${serviceOrderNumber} convertido em OS. Confirme o estoque das peças.`,
      });
      qc.invalidateQueries({ queryKey: ['service-orders'] });
      qc.invalidateQueries({ queryKey: ['receivables'] });
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
          {/* Mode selector */}
          <div className="space-y-1.5">
            <Label className="text-xs text-muted-foreground">Modo de cálculo</Label>
            <div className="flex gap-2 flex-wrap">
              <ModeBtn m="category" label="Por categoria" icon={Tag} />
              <ModeBtn m="percent"  label="% do total"   icon={Percent} />
              <ModeBtn m="fixed"    label="Valor fixo"    icon={Hash} />
            </div>
          </div>

          {/* Mode: category */}
          {mode === 'category' && (
            <div className="rounded-lg border bg-muted/30 p-3 space-y-3">
              <div className="flex items-center justify-between text-sm">
                <span className="text-muted-foreground">Serviços ({fmt(laborCost)})</span>
                <div className="flex items-center gap-2">
                  <Input
                    type="number" min="0" max="100" step="5"
                    className="w-20 h-7 text-right text-sm"
                    value={servicesPct}
                    onChange={e => setServicesPct(Math.min(100, parseFloat(e.target.value) || 0))}
                  />
                  <span className="text-xs text-muted-foreground w-24 text-right">
                    = {fmt(laborCost * servicesPct / 100)}
                  </span>
                </div>
              </div>
              <div className="flex items-center justify-between text-sm">
                <span className="text-muted-foreground">Peças ({fmt(partsCost)})</span>
                <div className="flex items-center gap-2">
                  <Input
                    type="number" min="0" max="100" step="5"
                    className="w-20 h-7 text-right text-sm"
                    value={partsPct}
                    onChange={e => setPartsPct(Math.min(100, parseFloat(e.target.value) || 0))}
                  />
                  <span className="text-xs text-muted-foreground w-24 text-right">
                    = {fmt(partsCost * partsPct / 100)}
                  </span>
                </div>
              </div>
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
              <Input type="date" value={date} onChange={e => setDate(e.target.value)} />
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
