/* ─────────────────────────────────────────────────────────────────────────────
   Subcomponentes do formulário de OS — extraídos 1:1 do ServiceOrderForm
   (Fase 3 UI v2, decomposição sobre a rede de paridade os-financials).
   Cards inline de serviço/peça, popover de desconto rápido e editor de
   parcelas customizadas. Nível de módulo para preservar o foco dos inputs.
──────────────────────────────────────────────────────────────────────────── */
import { useState, useEffect, useCallback, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import {
  computeOsFinancials, normalizeInstallmentRows,
  calcInstallmentAmount as calcInstallmentAmountPure,
  findSignalRow, simulateCardReceipt, computeItemDiscountTotal,
  computePartsProfit, computeReceivablesStatus,
} from '@/lib/os-financials';
import { ServiceTimer } from '@/components/ServiceTimer';
import { useI18n } from '@/i18n';
import { useClients } from '@/hooks/use-clients';
import { useVessels } from '@/hooks/use-vessels';
import { useMarinas } from '@/hooks/use-marinas';
import { useProducts } from '@/hooks/use-products';
import { useServices } from '@/hooks/use-services';
import { useCardFees } from '@/hooks/use-card-fees';
import { useAppSettings } from '@/hooks/use-app-settings';
import { useSOLinkedPOs, useUpdatePurchaseOrder } from '@/hooks/use-purchase-orders';
import {
  useCreateServiceOrder,
  useUpdateServiceOrder,
  useUpdateServiceOrderStatus,
  useServiceOrderParts,
  useAddServiceOrderPart,
  useRemoveServiceOrderPart,
  isStockModelV2,
  useServiceOrderServices,
  useAddServiceOrderService,
  useRemoveServiceOrderService,
  useTimeEntries,
  useAddTimeEntry,
  useRemoveTimeEntry,
  STATUS_TRANSITIONS,
  useCancelServiceOrder,
  useReopenServiceOrder,
  useDuplicateServiceOrder,
  recalcTotals,
} from '@/hooks/use-service-orders';
import { useAppUsers, useCommissionableUsers, USER_ROLES } from '@/hooks/use-app-users';
import { usePaymentConditionPresets } from '@/hooks/use-payment-conditions';
import { useCollectionsByOS } from '@/hooks/use-collections';
import { useReceivablesByServiceOrder, usePaymentsByServiceOrder, useCreateReceivable } from '@/hooks/use-financial';
import { PaymentDialog } from '@/components/PaymentDialog';
import { useVesselContacts, VESSEL_CONTACT_ROLES } from '@/hooks/use-vessel-contacts';
import { ClientCombobox } from '@/components/ClientCombobox';
import { VesselSelect } from '@/components/VesselSelect';
import { EntityCombobox, type EntityOption } from '@/components/EntityCombobox';
import { QuickProductDialog } from '@/components/QuickProductDialog';
import { MarinaFormDialog } from '@/components/MarinaFormDialog';
import { QuickSupplierDialog } from '@/components/QuickSupplierDialog';
import { ServiceOrderFinancialSummary, type FinancialWaterfallLine } from '@/components/ServiceOrderFinancialSummary';
import { useSuppliers } from '@/hooks/use-suppliers';
import { useServiceOrderExpenses, useAddServiceOrderExpense, useUpdateServiceOrderExpense, useRemoveServiceOrderExpense } from '@/hooks/use-service-order-expenses';
import { useUpdateServiceOrderService } from '@/hooks/use-service-order-services';
import { useUpdateServiceOrderPart } from '@/hooks/use-service-order-parts';
import { PriceCalculatorDialog } from '@/components/PriceCalculatorDialog';
import { supabase } from '@/integrations/supabase/client';
import { usePDFData } from '@/hooks/use-pdf';
import { generatePDF, downloadPDF, DEFAULT_PDF_OPTIONS } from '@/lib/pdf-generator';
import type { PDFOptions } from '@/lib/pdf-generator';
import { PDFOptionsDialog } from '@/components/PDFOptionsDialog';
import { RegisterDepositDialog } from '@/components/RegisterDepositDialog';
import { CompletionSendDialog } from '@/components/CompletionSendDialog';
import { StockAlertDialog } from '@/components/StockAlertDialog';
import { ReceivePODialog } from '@/components/ReceivePODialog';
import { calculateDisplacement, calculateTravelCost, travelRatesFromSettings } from '@/lib/displacement';
import { statusConfig, priorityConfig } from '@/lib/constants';
import { StatusBadge } from '@/components/StatusBadge';
import { ServiceFormDialog } from '@/components/ServiceFormDialog';
import { ServiceOrderSignatures } from '@/components/ServiceOrderSignatures';
import { ServiceOrderPhotos } from '@/components/ServiceOrderPhotos';
import { WhatsAppSendHistoryDialog } from '@/components/WhatsAppSendHistoryDialog';
import { SendViaWhatsAppDialog, type SendViaWhatsAppTarget } from '@/components/SendViaWhatsAppDialog';
import { useWhatsAppSendHistory } from '@/hooks/use-whatsapp-send-log';
import { CheckCircle2, XCircle, History as HistoryIcon, Send, Sparkles } from 'lucide-react';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';
import { Popover, PopoverTrigger, PopoverContent } from '@/components/ui/popover';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Skeleton } from '@/components/ui/skeleton';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { ArrowLeft, Plus, Trash2, RefreshCw, AlertTriangle, Calculator, CreditCard, Receipt, Lock, RotateCcw, Ban, FileText, Printer, ChevronDown, MessageCircle, Pencil, Paperclip, X, FileImage, ExternalLink, Package, Copy, Camera, MapPin, Clock, Download, Loader2, DollarSign, Tag, Percent, Hash, PackagePlus } from 'lucide-react';
import { toast } from 'sonner';
import { normalizePhoneE164 } from '@/lib/masks';
import { MoneyInput } from '@/components/MoneyInput';
import { writeAuditLog } from '@/hooks/use-audit-log';
import { recordWhatsAppEvent } from '@/lib/diagnostics';
import { useAITextOptimizer } from '@/hooks/use-ai-text-optimizer';


const BILLING_UNIT_LABELS: Record<string, string> = {
  hour: 'h',
  visit: 'visita(s)',
  day: 'dia(s)',
  unit: 'un.',
};

// ===== Types & components for inline service/part cards (module-level to preserve input focus) =====
type SvcCardState = {
  service_id: string;
  name_snapshot: string;
  description_snapshot: string;
  billing_unit_snapshot: string;
  quantity: number;
  unit_price: number;
  notes: string;
  technician_user_id: string;
  warranty_days?: number;
  warranty_months?: number;
  discount_pct?: number;
  discount_amount?: number;
};

type PartCardState = {
  product_id: string;
  name: string;
  unit: string;
  quantity: number;
  unit_cost: number;
  unit_sale: number;
  notes: string;
  image_url?: string | null;
  warranty_days?: number;
  warranty_months?: number;
  serial_number?: string;
  discount_pct?: number;
  discount_amount?: number;
};

type DiscountFieldState = { pct: number; discountAmount: number; finalValue: number };

/**
 * `discountAmount` (R$) é a fonte da verdade — o que de fato é persistido e
 * usado para calcular `line_total`. `pct` é só um valor derivado para exibição
 * no campo de percentual (arredondado a 2 casas, já que é inerentemente sem
 * precisão exata para descontos como R$10,12 sobre R$1.000,00 = 1,012%).
 */
function computeDiscountState(raw: number, discountAmount: number): DiscountFieldState {
  const amt = Math.max(0, Math.min(raw, Number.isFinite(discountAmount) ? discountAmount : 0));
  const finalValue = Math.round((raw - amt) * 100) / 100;
  const pct = raw > 0 ? Math.round((amt / raw) * 10000) / 100 : 0;
  return { pct, discountAmount: amt, finalValue };
}

/**
 * Mantém os 3 campos de desconto (%, R$ e valor final) consistentes entre si.
 * Editar R$ ou valor final nunca reintroduz o desconto arredondado a 2 casas
 * de percentual — o valor exato digitado (ou a subtração exata raw−final) é
 * que fica armazenado, evitando a perda de centavos e a disputa entre o
 * `value` externo e o `display` interno do MoneyInput. Só o campo de %
 * (editado diretamente) computa `discountAmount` a partir de um percentual —
 * esse é o único modo onde arredondar a 2 casas é esperado/correto, porque
 * o usuário escolheu % como unidade.
 * Os setters retornam o `pct` recém-calculado para quem precisar persistir
 * (ex: onUpdate) de forma síncrona — mas quem persiste deve gravar
 * `discount_amount` (retornado via `discountAmount` no estado), não o `pct`.
 */
function useDiscountFields(raw: number, initialAmount: number) {
  const [state, setState] = useState<DiscountFieldState>(() => computeDiscountState(raw, initialAmount || 0));

  useEffect(() => {
    setState((s) => computeDiscountState(raw, s.discountAmount));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [raw]);

  const setFromPct = (newPct: number): { pct: number; discountAmount: number } => {
    const clamped = Math.max(0, Math.min(100, Number.isFinite(newPct) ? newPct : 0));
    const discountAmount = Math.round((raw * clamped) / 100 * 100) / 100;
    const next = computeDiscountState(raw, discountAmount);
    setState(next);
    return { pct: clamped, discountAmount: next.discountAmount };
  };

  const setFromAmount = (v: number): { pct: number; discountAmount: number } => {
    const next = computeDiscountState(raw, v);
    setState(next);
    return { pct: next.pct, discountAmount: next.discountAmount };
  };

  const setFromFinal = (v: number): { pct: number; discountAmount: number } => {
    const finalValue = Math.max(0, Math.min(raw, Number.isFinite(v) ? v : 0));
    const discountAmount = Math.round((raw - finalValue) * 100) / 100;
    const next = computeDiscountState(raw, discountAmount);
    setState(next);
    return { pct: next.pct, discountAmount: next.discountAmount };
  };

  const reset = (newAmount: number) => setState(computeDiscountState(raw, newAmount || 0));

  return { ...state, setFromPct, setFromAmount, setFromFinal, reset };
}

interface QuickDiscountPopoverProps {
  quantity: number;
  unitPrice: number;
  discountPct: number;
  discountAmount: number;
  formatCurrency: (n: number) => string;
  onApply: (pct: number, discountAmount: number) => void | Promise<void>;
}

/**
 * Atalho de desconto na linha colapsada da lista (sem abrir o card de edição
 * inteiro). Componente próprio (não uma função inline) para poder usar estado
 * local — os 3 campos (%, R$, valor final) ficam sincronizados entre si, e só
 * são persistidos quando o usuário clica em "Aplicar".
 */
function QuickDiscountPopover({ quantity, unitPrice, discountPct, discountAmount: discountAmountProp, formatCurrency, onApply }: QuickDiscountPopoverProps) {
  const [open, setOpen] = useState(false);
  const [applying, setApplying] = useState(false);
  const raw = quantity * unitPrice;
  const { pct, discountAmount, finalValue, setFromPct, setFromAmount, setFromFinal, reset } = useDiscountFields(raw, discountAmountProp || 0);

  const handleApply = async (nextPct: number, nextAmount: number) => {
    setApplying(true);
    try {
      await onApply(nextPct, nextAmount);
      setOpen(false);
    } finally {
      setApplying(false);
    }
  };

  return (
    <Popover open={open} onOpenChange={(v) => { setOpen(v); if (v) reset(discountAmountProp || 0); }}>
      <PopoverTrigger asChild>
        <Button
          type="button"
          variant="ghost"
          size="icon"
          className={`h-8 w-8 ${(discountPct || 0) > 0 ? 'text-destructive' : 'text-muted-foreground'}`}
          title="Aplicar desconto neste item"
        >
          <Percent className="h-3.5 w-3.5" />
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-64 space-y-3" align="end">
        <p className="text-xs font-medium text-muted-foreground">Desconto neste item</p>
        <div className="space-y-1">
          <Label className="text-xs">Desconto (%)</Label>
          <Input type="number" min={0} max={100} step="0.01"
            value={pct}
            onChange={(e) => setFromPct(parseFloat(e.target.value))} />
        </div>
        <div className="space-y-1">
          <Label className="text-xs">Desconto (R$)</Label>
          <MoneyInput
            value={discountAmount}
            onValueChange={setFromAmount}
          />
        </div>
        <div className="space-y-1">
          <Label className="text-xs">Valor final</Label>
          <MoneyInput
            value={finalValue}
            onValueChange={setFromFinal}
          />
          <p className="text-[11px] text-muted-foreground">Preço cheio: {formatCurrency(raw)}</p>
        </div>
        <div className="flex gap-2 pt-1">
          <Button type="button" size="sm" disabled={applying} onClick={() => handleApply(pct, discountAmount)}>
            {applying ? 'Aplicando...' : 'Aplicar'}
          </Button>
          {(discountPct || 0) > 0 && (
            <Button type="button" size="sm" variant="outline" disabled={applying} onClick={() => { reset(0); handleApply(0, 0); }}>
              Remover
            </Button>
          )}
        </div>
      </PopoverContent>
    </Popover>
  );
}

interface ServiceCardFormProps {
  cardKey: string;
  draft: SvcCardState | undefined;
  services: any[];
  appUsers: any[];
  formatCurrency: (n: number) => string;
  onUpdate: (patch: Partial<SvcCardState>) => void;
  onConfirm: () => void;
  onCancel: () => void;
  confirmDisabled?: boolean;
}

function ServiceCardFormComponent({
  draft,
  services,
  appUsers,
  formatCurrency,
  onUpdate,
  onConfirm,
  onCancel,
  confirmDisabled,
}: ServiceCardFormProps) {
  const [showSuggestions, setShowSuggestions] = useState(false);
  const svcRaw = draft ? draft.quantity * draft.unit_price : 0;
  const { pct: discountPct, finalValue: total, setFromPct: setSvcPct, setFromFinal: setSvcFinal } = useDiscountFields(svcRaw, draft?.discount_amount || 0);
  if (!draft) return null;
  const technicians = (appUsers || []).filter(
    (u: any) => u.role === 'technician' || u.role === 'admin'
  );
  const nameQuery = draft.name_snapshot.toLowerCase();
  const suggestions = (services || [])
    .filter((s: any) => s.active)
    .filter((s: any) => {
      if (!nameQuery) return false;
      if (s.id === draft.service_id) return false;
      return (
        (s.name || '').toLowerCase().includes(nameQuery) ||
        (s.description || '').toLowerCase().includes(nameQuery)
      );
    })
    .slice(0, 6);
  return (
    <div className="p-4 space-y-3 bg-muted/20">
      <div className="grid grid-cols-1 md:grid-cols-12 gap-3">
        <div className="md:col-span-6 relative">
          <Label>Descrição</Label>
          <Input
            value={draft.name_snapshot}
            onChange={(e) =>
              onUpdate({ name_snapshot: e.target.value, service_id: '' })
            }
            onFocus={() => setShowSuggestions(true)}
            onBlur={() => setTimeout(() => setShowSuggestions(false), 150)}
            placeholder="Digite ou selecione um serviço"
            autoComplete="off"
          />
          {showSuggestions && suggestions.length > 0 && (
            <div className="absolute z-20 mt-1 w-full rounded-md border bg-popover shadow-md max-h-60 overflow-auto">
              {suggestions.map((s: any) => (
                <button
                  key={s.id}
                  type="button"
                  className="w-full text-left px-3 py-2 text-sm hover:bg-accent"
                  onClick={() => {
                    onUpdate({
                      service_id: s.id,
                      name_snapshot: s.name,
                      description_snapshot: s.description || '',
                      billing_unit_snapshot: s.billing_unit || 'hour',
                      unit_price: Number(s.default_price) || 0,
                      warranty_days: s.default_warranty_days || 0,
                    });
                    setShowSuggestions(false);
                  }}
                >
                  <div className="font-medium">{s.name}</div>
                  <div className="text-xs text-muted-foreground">
                    {BILLING_UNIT_LABELS[s.billing_unit] || s.billing_unit} —{' '}
                    {formatCurrency(s.default_price || 0)}
                    {s.description ? ` · ${s.description}` : ''}
                  </div>
                </button>
              ))}
            </div>
          )}
        </div>
        <div className="md:col-span-2">
          <Label>Quantidade</Label>
          <Input
            type="number"
            min={0.001}
            step="any"
            value={draft.quantity}
            onChange={(e) => onUpdate({ quantity: parseFloat(e.target.value) || 0 })}
          />
        </div>
        <div className="md:col-span-2">
          <Label>Unidade</Label>
          <Select
            value={draft.billing_unit_snapshot}
            onValueChange={(v) => onUpdate({ billing_unit_snapshot: v })}
          >
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="hour">hora</SelectItem>
              <SelectItem value="visit">visita</SelectItem>
              <SelectItem value="day">dia</SelectItem>
              <SelectItem value="unit">unidade</SelectItem>
            </SelectContent>
          </Select>
        </div>
        <div className="md:col-span-2">
          <Label>Valor unitário</Label>
          <MoneyInput
            value={draft.unit_price}
            onValueChange={(v) => onUpdate({ unit_price: v })}
          />
        </div>
      </div>
      <div className="grid grid-cols-1 md:grid-cols-12 gap-3">
        <div className="md:col-span-5">
          <Label>Técnico responsável</Label>
          <Select
            value={draft.technician_user_id || 'none'}
            onValueChange={(v) =>
              onUpdate({ technician_user_id: v === 'none' ? '' : v })
            }
          >
            <SelectTrigger>
              <SelectValue placeholder="Selecionar técnico" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="none">— Nenhum —</SelectItem>
              {technicians.map((u: any) => (
                <SelectItem key={u.id} value={u.id}>
                  {u.full_name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div className="md:col-span-2">
          <Label>Desconto (%)</Label>
          <Input
            type="number"
            min={0}
            max={100}
            step="0.01"
            value={discountPct}
            onChange={(e) => { const r = setSvcPct(parseFloat(e.target.value)); onUpdate({ discount_pct: r.pct, discount_amount: r.discountAmount }); }}
          />
        </div>
        <div className="md:col-span-5">
          <Label>Valor final{discountPct > 0 ? ` (−${discountPct}%)` : ''}</Label>
          <MoneyInput
            value={total}
            onValueChange={(v) => { const r = setSvcFinal(v); onUpdate({ discount_pct: r.pct, discount_amount: r.discountAmount }); }}
          />
          <p className="text-[11px] text-muted-foreground mt-0.5">Digite o valor já arredondado — o desconto (%) é calculado sozinho.</p>
        </div>
      </div>
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
        <div className="col-span-1">
          <Label>Garantia (dias)</Label>
          <Input
            type="number"
            min="0"
            value={(draft as any).warranty_days ?? 0}
            onChange={(e) => onUpdate({ warranty_days: parseInt(e.target.value) || 0 } as any)}
          />
        </div>
        <div className="col-span-1">
          <Label>Observações</Label>
          <Textarea
            rows={1}
            value={draft.notes}
            onChange={(e) => onUpdate({ notes: e.target.value })}
          />
        </div>
      </div>
      <div>
        <Label>Garantia (meses)</Label>
        <Input
          type="number"
          min={0}
          max={60}
          value={draft.warranty_months || 0}
          onChange={(e) => onUpdate({ warranty_months: parseInt(e.target.value) || 0 })}
          placeholder="0 = sem garantia"
          className="h-8"
        />
        {(draft.warranty_months || 0) > 0 && (
          <p className="text-xs text-muted-foreground mt-1">
            Vence em: {new Date(Date.now() + (draft.warranty_months || 0) * 30 * 86400000).toLocaleDateString('pt-BR')}
          </p>
        )}
      </div>
      <div className="flex gap-2">
        <Button size="sm" onClick={onConfirm} disabled={confirmDisabled}>
          <CheckCircle2 className="h-3.5 w-3.5 mr-1" /> Confirmar
        </Button>
        <Button size="sm" variant="outline" onClick={onCancel}>
          <X className="h-3.5 w-3.5 mr-1" /> Cancelar
        </Button>
      </div>
    </div>
  );
}

const PART_UNITS = ['un', 'm', 'kg', 'l', 'm²', 'hr', 'pcs'];

interface PartCardFormProps {
  cardKey: string;
  draft: PartCardState | undefined;
  products: any[];
  formatCurrency: (n: number) => string;
  onUpdate: (patch: Partial<PartCardState>) => void;
  onConfirm: () => void;
  onCancel: () => void;
  onOpenPriceCalc: () => void;
  confirmDisabled?: boolean;
  supabase: typeof supabase;
  clientId?: string;
}

function PartCardFormComponent({
  draft,
  products,
  formatCurrency,
  onUpdate,
  onConfirm,
  onCancel,
  onOpenPriceCalc,
  confirmDisabled,
  supabase: sb,
  clientId,
}: PartCardFormProps) {
  const [showSuggestions, setShowSuggestions] = useState(false);
  const [uploading, setUploading] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const partRaw = draft ? draft.quantity * draft.unit_sale : 0;
  const { pct: discountPct, finalValue: total, setFromPct: setPartPct, setFromFinal: setPartFinal } = useDiscountFields(partRaw, draft?.discount_amount || 0);
  if (!draft) return null;
  const nameQuery = draft.name.toLowerCase();
  const suggestions = (products || [])
    .filter((p: any) => p.active)
    .filter((p: any) => {
      if (!nameQuery) return false;
      if (p.id === draft.product_id) return false;
      return (
        (p.name || '').toLowerCase().includes(nameQuery) ||
        (p.sku || '').toLowerCase().includes(nameQuery) ||
        (p.brand || '').toLowerCase().includes(nameQuery)
      );
    })
    .slice(0, 6);
  const unitOptions = Array.from(new Set([...PART_UNITS, draft.unit].filter(Boolean)));

  const handlePickFile = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file || !draft.product_id) return;
    if (file.size > 2 * 1024 * 1024) {
      toast.error('Imagem maior que 2MB');
      return;
    }
    if (!['image/jpeg', 'image/jpg', 'image/png', 'image/webp'].includes(file.type)) {
      toast.error('Formato inválido. Use JPG, PNG ou WEBP.');
      return;
    }
    setUploading(true);
    try {
      const ext = file.name.split('.').pop() || 'jpg';
      const path = `products/${draft.product_id}/${crypto.randomUUID()}.${ext}`;
      const { error: upErr } = await sb.storage
        .from('product-images')
        .upload(path, file, { contentType: file.type, upsert: false });
      if (upErr) throw upErr;
      const { data: pub } = sb.storage.from('product-images').getPublicUrl(path);
      const publicUrl = pub.publicUrl;
      const { error: updErr } = await sb
        .from('products')
        .update({ image_url: publicUrl })
        .eq('id', draft.product_id);
      if (updErr) throw updErr;
      onUpdate({ image_url: publicUrl, warranty_days: (draft as any).warranty_days || 0 });
      toast.success('Foto adicionada');
    } catch (err: any) {
      toast.error(err?.message || 'Erro ao enviar imagem');
    } finally {
      setUploading(false);
    }
  };

  const handleRemoveImage = async () => {
    if (!draft.product_id || !draft.image_url) return;
    setUploading(true);
    try {
      const url = draft.image_url;
      const marker = '/product-images/';
      const idx = url.indexOf(marker);
      if (idx >= 0) {
        const path = url.substring(idx + marker.length);
        await sb.storage.from('product-images').remove([path]);
      }
      await sb.from('products').update({ image_url: null }).eq('id', draft.product_id);
      onUpdate({ image_url: null });
    } catch (err: any) {
      toast.error(err?.message || 'Erro ao remover');
    } finally {
      setUploading(false);
    }
  };

  return (
    <div className="p-4 space-y-3 bg-muted/20">
      <div className="grid grid-cols-1 md:grid-cols-12 gap-3">
        <div className="md:col-span-6 relative">
          <Label>Nome / Descrição</Label>
          <Input
            value={draft.name}
            onChange={(e) => onUpdate({ name: e.target.value, product_id: '' })}
            onFocus={() => setShowSuggestions(true)}
            onBlur={() => setTimeout(() => setShowSuggestions(false), 150)}
            placeholder="Digite ou selecione um produto"
            autoComplete="off"
          />
          {showSuggestions && suggestions.length > 0 && (
            <div className="absolute z-20 mt-1 w-full rounded-md border bg-popover shadow-md max-h-60 overflow-auto">
              {suggestions.map((p: any) => (
                <button
                  key={p.id}
                  type="button"
                  className="w-full text-left px-3 py-2 text-sm hover:bg-accent"
                  onClick={() => {
                    // Preço do catálogo imediato (resposta instantânea); em seguida busca o
                    // PRATICADO (este cliente → global → catálogo) e ajusta o unit_sale se houver
                    // histórico. Falha na busca mantém o catálogo — nunca trava a seleção.
                    onUpdate({
                      product_id: p.id,
                      name: p.name,
                      unit: p.unit || 'un',
                      unit_cost: Number(p.cost_price) || 0,
                      unit_sale: Number(p.sale_price) || 0,
                      image_url: p.image_url || null,
                      warranty_days: p.default_warranty_days || 0,
                    });
                    setShowSuggestions(false);
                    void (async () => {
                      try {
                        const { data } = await (sb as any).rpc('resolve_practiced_price', { p_product_id: p.id, p_client_id: clientId ?? null });
                        const row = Array.isArray(data) ? data[0] : data;
                        if (row && row.price != null && Number(row.price) > 0) {
                          onUpdate({ unit_sale: Number(row.price) });
                        }
                      } catch { /* mantém o preço do catálogo */ }
                    })();
                  }}
                >
                  <div className="font-medium">{p.name}</div>
                  <div className="text-xs text-muted-foreground">
                    {formatCurrency(p.sale_price || 0)}
                    {p.sku ? ` · SKU ${p.sku}` : ''}
                    {p.brand ? ` · ${p.brand}` : ''}
                  </div>
                </button>
              ))}
            </div>
          )}
          {/* Photo upload */}
          <div className="mt-2">
            {!draft.product_id ? (
              <p className="text-xs text-muted-foreground">
                Salve o produto primeiro para adicionar foto.
              </p>
            ) : draft.image_url ? (
              <div className="flex items-center gap-2">
                <img
                  src={draft.image_url}
                  alt="Foto do produto"
                  className="h-12 w-12 rounded object-cover border"
                />
                <Button
                  type="button"
                  variant="ghost"
                  size="icon"
                  className="h-7 w-7"
                  onClick={handleRemoveImage}
                  disabled={uploading}
                  title="Remover foto"
                >
                  <X className="h-3.5 w-3.5" />
                </Button>
              </div>
            ) : (
              <>
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={() => fileInputRef.current?.click()}
                  disabled={uploading}
                >
                  📷 {uploading ? 'Enviando...' : 'Adicionar foto'}
                </Button>
                <input
                  ref={fileInputRef}
                  type="file"
                  accept="image/*"
                  capture="environment"
                  className="hidden"
                  onChange={handlePickFile}
                />
              </>
            )}
          </div>
        </div>
        <div className="md:col-span-2">
          <Label>Quantidade</Label>
          <Input
            type="number"
            min={0.001}
            step="any"
            value={draft.quantity}
            onChange={(e) => onUpdate({ quantity: parseFloat(e.target.value) || 0 })}
          />
        </div>
        <div className="md:col-span-2">
          <Label>Unidade</Label>
          <Select value={draft.unit || 'un'} onValueChange={(v) => onUpdate({ unit: v })}>
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {unitOptions.map((u) => (
                <SelectItem key={u} value={u}>{u}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div className="md:col-span-2">
          <Label>Valor final{discountPct > 0 ? ` (−${discountPct}%)` : ''}</Label>
          <MoneyInput
            value={total}
            onValueChange={(v) => { const r = setPartFinal(v); onUpdate({ discount_pct: r.pct, discount_amount: r.discountAmount }); }}
          />
        </div>
      </div>
      <div className="grid grid-cols-1 md:grid-cols-12 gap-3">
        <div className="md:col-span-3">
          <Label>Preço de custo</Label>
          <MoneyInput
            value={draft.unit_cost}
            onValueChange={(v) => onUpdate({ unit_cost: v })}
          />
        </div>
        <div className="md:col-span-3">
          <Label>Preço de venda</Label>
          <MoneyInput
            value={draft.unit_sale}
            onValueChange={(v) => onUpdate({ unit_sale: v })}
          />
        </div>
        <div className="md:col-span-3">
          <Label>Desconto (%)</Label>
          <Input
            type="number"
            min={0}
            max={100}
            step="0.01"
            value={discountPct}
            onChange={(e) => { const r = setPartPct(parseFloat(e.target.value)); onUpdate({ discount_pct: r.pct, discount_amount: r.discountAmount }); }}
          />
        </div>
        <div className="md:col-span-3 flex items-end">
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={onOpenPriceCalc}
            title="Formador de preço"
          >
            <Calculator className="h-3.5 w-3.5 mr-1" /> Calcular preço
          </Button>
        </div>
      </div>
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
        <div className="col-span-1">
          <Label>Garantia (dias)</Label>
          <Input
            type="number"
            min="0"
            value={(draft as any).warranty_days ?? 0}
            onChange={(e) => onUpdate({ warranty_days: parseInt(e.target.value) || 0 } as any)}
          />
        </div>
        <div className="col-span-1">
          <Label>Observações</Label>
          <Textarea
            rows={1}
            value={draft.notes}
            onChange={(e) => onUpdate({ notes: e.target.value })}
          />
        </div>
      </div>
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
        <div>
          <Label>Número de série (opcional)</Label>
          <Input
            value={draft.serial_number || ''}
            onChange={(e) => onUpdate({ serial_number: e.target.value })}
            placeholder="Ex: VE123456"
            className="h-8 text-sm"
          />
        </div>
        <div>
          <Label>Garantia (meses)</Label>
          <Input
            type="number"
            min={0}
            max={60}
            value={draft.warranty_months || 0}
            onChange={(e) => onUpdate({ warranty_months: parseInt(e.target.value) || 0 })}
            placeholder="0 = sem garantia"
            className="h-8 text-sm"
          />
        </div>
      </div>
      <div className="flex gap-2">
        <Button size="sm" onClick={onConfirm} disabled={confirmDisabled}>
          <CheckCircle2 className="h-3.5 w-3.5 mr-1" /> Confirmar
        </Button>
        <Button size="sm" variant="outline" onClick={onCancel}>
          <X className="h-3.5 w-3.5 mr-1" /> Cancelar
        </Button>
      </div>
    </div>
  );
}

type CustomInstallmentRow = {
  label: string;
  services_pct: number;
  parts_pct: number;
  expenses_pct: number;
  days_after_approval: number;
  tipo?: 'aprovacao' | 'entrega' | 'prazo';
};

interface CustomInstallmentEditorProps {
  installments: CustomInstallmentRow[];
  onChange: (rows: CustomInstallmentRow[]) => void;
  laborCost: number;
  partsCost: number;
  expensesTotal: number;
  discountRatio: number;
  formatCurrency: (n: number) => string;
  disabled?: boolean;
}

/**
 * Editor de parcelas personalizado — usado quando nenhum preset pré-definido
 * bate com o que foi acordado com o cliente. Cada linha guarda um único %
 * (aplicado igualmente a services_pct/parts_pct/expenses_pct), o que
 * matematicamente equivale a "X% do total" — evita pedir 3 campos por
 * parcela, e reaproveita o mesmo shape de PaymentInstallment usado pelos
 * presets, então toda a lógica downstream (calcInstallmentAmount, sinal,
 * RegisterDepositDialog) funciona sem mudança nenhuma.
 */
function CustomInstallmentEditor({
  installments, onChange, laborCost, partsCost, expensesTotal, discountRatio, formatCurrency, disabled,
}: CustomInstallmentEditorProps) {
  const totalPct = installments.reduce((s, r) => s + (r.services_pct || 0), 0);

  const updateRow = (i: number, patch: Partial<CustomInstallmentRow>) => {
    onChange(installments.map((r, idx) => (idx === i ? { ...r, ...patch } : r)));
  };
  const removeRow = (i: number) => {
    onChange(installments.filter((_, idx) => idx !== i));
  };
  const addRow = () => {
    onChange([...installments, { label: `Parcela ${installments.length + 1}`, services_pct: 0, parts_pct: 0, expenses_pct: 0, days_after_approval: 0, tipo: 'prazo' }]);
  };

  return (
    <div className="space-y-2">
      <div className="rounded-md bg-background border divide-y text-sm">
        {installments.map((row, i) => {
          const amount = Math.round((laborCost * row.services_pct / 100 + partsCost * row.parts_pct / 100 + expensesTotal * row.expenses_pct / 100) * discountRatio * 100) / 100;
          return (
            <div key={i} className="flex flex-wrap items-center gap-2 px-3 py-2">
              <Input
                value={row.label}
                onChange={(e) => updateRow(i, { label: e.target.value })}
                placeholder={`Parcela ${i + 1}`}
                disabled={disabled}
                className="h-7 text-xs flex-1 min-w-[100px]"
              />
              <Input
                type="number" min={0} max={100} step="0.01"
                value={row.services_pct}
                onChange={(e) => {
                  const pct = Math.max(0, Math.min(100, parseFloat(e.target.value) || 0));
                  updateRow(i, { services_pct: pct, parts_pct: pct, expenses_pct: pct });
                }}
                disabled={disabled}
                className="h-7 text-xs w-16"
                title="Percentual do total"
              />
              <span className="text-xs text-muted-foreground">%</span>
              <Select
                value={row.tipo === 'entrega' ? 'entrega' : row.days_after_approval > 0 ? 'prazo' : 'aprovacao'}
                onValueChange={(v) => updateRow(i, {
                  tipo: v as 'aprovacao' | 'entrega' | 'prazo',
                  days_after_approval: v === 'prazo' ? (row.days_after_approval || 30) : 0,
                })}
                disabled={disabled}
              >
                <SelectTrigger className="h-7 text-xs w-28"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="aprovacao">Na aprovação</SelectItem>
                  <SelectItem value="prazo">Após X dias</SelectItem>
                  <SelectItem value="entrega">Na entrega</SelectItem>
                </SelectContent>
              </Select>
              {row.tipo === 'prazo' && (
                <Input
                  type="number" min={1} step="1"
                  value={row.days_after_approval}
                  onChange={(e) => updateRow(i, { days_after_approval: parseInt(e.target.value) || 0 })}
                  disabled={disabled}
                  className="h-7 text-xs w-16"
                  title="Dias após aprovação"
                />
              )}
              <span className="font-semibold text-xs ml-auto">{formatCurrency(amount)}</span>
              <Button type="button" variant="ghost" size="icon" className="h-7 w-7 text-destructive" onClick={() => removeRow(i)} disabled={disabled}>
                <Trash2 className="h-3.5 w-3.5" />
              </Button>
            </div>
          );
        })}
      </div>
      <div className="flex items-center justify-between">
        <Button type="button" variant="outline" size="sm" onClick={addRow} disabled={disabled}>
          <Plus className="h-3.5 w-3.5 mr-1" /> Parcela
        </Button>
        {Math.abs(totalPct - 100) > 0.01 && (
          <span className="text-xs text-amber-600">Soma dos % = {totalPct.toFixed(2)}% (não fecha 100%)</span>
        )}
      </div>
    </div>
  );
}


export { ServiceCardFormComponent, PartCardFormComponent, CustomInstallmentEditor, QuickDiscountPopover, BILLING_UNIT_LABELS };
export type { SvcCardState, PartCardState, CustomInstallmentRow };
