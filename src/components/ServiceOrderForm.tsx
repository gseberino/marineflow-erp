import { useState, useEffect, useCallback, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import { ServiceTimer } from '@/components/ServiceTimer';
import { useI18n } from '@/i18n';
import { useClients } from '@/hooks/use-clients';
import { useVessels } from '@/hooks/use-vessels';
import { useMarinas } from '@/hooks/use-marinas';
import { useProducts } from '@/hooks/use-products';
import { useServices } from '@/hooks/use-services';
import { useCardFees } from '@/hooks/use-card-fees';
import { useSOLinkedPOs, useUpdatePurchaseOrder } from '@/hooks/use-purchase-orders';
import {
  useCreateServiceOrder,
  useUpdateServiceOrder,
  useUpdateServiceOrderStatus,
  useServiceOrderParts,
  useAddServiceOrderPart,
  useRemoveServiceOrderPart,
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
} from '@/hooks/use-service-orders';
import { useAppUsers, useCommissionableUsers, USER_ROLES } from '@/hooks/use-app-users';
import { usePaymentConditionPresets } from '@/hooks/use-payment-conditions';
import { useCollectionsByOS } from '@/hooks/use-collections';
import { useReceivablesByServiceOrder, usePaymentsByServiceOrder } from '@/hooks/use-financial';
import { useVesselContacts, VESSEL_CONTACT_ROLES } from '@/hooks/use-vessel-contacts';
import { ClientCombobox } from '@/components/ClientCombobox';
import { VesselSelect } from '@/components/VesselSelect';
import { EntityCombobox, type EntityOption } from '@/components/EntityCombobox';
import { QuickProductDialog } from '@/components/QuickProductDialog';
import { MarinaFormDialog } from '@/components/MarinaFormDialog';
import { QuickSupplierDialog } from '@/components/QuickSupplierDialog';
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
import { StockAlertDialog } from '@/components/StockAlertDialog';
import { ReceivePODialog } from '@/components/ReceivePODialog';
import { OPERATIONAL_EXPENSE_CATEGORIES } from '@/lib/expense-categories';
import { calculateDisplacement, calculateTravelCost } from '@/lib/displacement';
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

interface Props {
  orderId?: string;
  orderData?: any;
  isLoading?: boolean;
}

const SERVICE_TYPES = [
  'diagnosis', 'repair', 'installation', 'preventive_maintenance',
  'consulting', 'engineering_project', 'commissioning', 'inspection',
] as const;

const PRIORITIES = ['low', 'normal', 'high', 'urgent'] as const;
const STATUSES = [
  'draft', 'scheduled', 'open', 'in_progress', 'awaiting_parts',
  'awaiting_client', 'approved', 'completed', 'invoiced', 'cancelled',
] as const;

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
};

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
  const total = draft.quantity * draft.unit_price;
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
        <div className="md:col-span-6">
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
        <div className="md:col-span-6">
          <Label>Total</Label>
          <Input readOnly value={formatCurrency(total)} className="bg-muted" />
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
}: PartCardFormProps) {
  const [showSuggestions, setShowSuggestions] = useState(false);
  const [uploading, setUploading] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);
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
  const total = draft.quantity * draft.unit_sale;
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
          <Label>Total</Label>
          <Input readOnly value={formatCurrency(total)} className="bg-muted" />
        </div>
      </div>
      <div className="grid grid-cols-1 md:grid-cols-12 gap-3">
        <div className="md:col-span-4">
          <Label>Preço de custo</Label>
          <MoneyInput
            value={draft.unit_cost}
            onValueChange={(v) => onUpdate({ unit_cost: v })}
          />
        </div>
        <div className="md:col-span-4">
          <Label>Preço de venda</Label>
          <MoneyInput
            value={draft.unit_sale}
            onValueChange={(v) => onUpdate({ unit_sale: v })}
          />
        </div>
        <div className="md:col-span-4 flex items-end">
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

export function ServiceOrderForm({ orderId, orderData, isLoading }: Props) {
  const navigate = useNavigate();
  const { t, formatCurrency, formatDateTime, formatDate } = useI18n();
  const isNew = !orderId;

  const { data: clients } = useClients();
  const { data: allVessels } = useVessels();
  const { data: marinas } = useMarinas();
  const { data: products } = useProducts();
  const { data: suppliers } = useSuppliers();
  const { data: appUsers } = useAppUsers();
  const { data: commissionableUsers } = useCommissionableUsers();
  const { data: services } = useServices();
  const { data: cardFees } = useCardFees();
  const { data: paymentPresets } = usePaymentConditionPresets();
  const { data: pdfData } = usePDFData(isNew ? undefined : orderId);
  const queryClient = useQueryClient();
  const openPdfDialog = (type: 'quote' | 'service_order' | 'invoice') => {
    if (orderId) {
      queryClient.invalidateQueries({ queryKey: ['pdf-data', orderId] });
    }
    setPdfDialogType(type);
  };

  const handleDirectDownload = async (type: 'quote' | 'service_order' | 'invoice') => {
    if (!pdfData || !orderId) return;
    setDownloadingType(type);
    try {
      await downloadPDF({ ...pdfData, documentType: type }, DEFAULT_PDF_OPTIONS);
      toast.success('PDF baixado com sucesso');
    } catch (e: any) {
      console.error('PDF download failed:', e);
      toast.error('Erro ao gerar o PDF para download');
    } finally {
      setDownloadingType(null);
    }
  };

  const createSO = useCreateServiceOrder();
  const updateSO = useUpdateServiceOrder();
  const updateStatus = useUpdateServiceOrderStatus();
  const cancelSO = useCancelServiceOrder();
  const reopenSO = useReopenServiceOrder();
  const duplicate = useDuplicateServiceOrder();

  const { data: parts } = useServiceOrderParts(orderId);
  const addPart = useAddServiceOrderPart();
  const removePart = useRemoveServiceOrderPart();
  const { data: linkedPOs } = useSOLinkedPOs(orderId);
  const updatePO = useUpdatePurchaseOrder();
  const [stockAlert, setStockAlert] = useState<{ cardKey: string; productId: string; productName: string; needed: number; available: number; unitCost: number; unitSale: number; notes?: string; suppliers: { id: string; name: string }[]; leadTimeDays?: number; } | null>(null);
  const [receivePOTarget, setReceivePOTarget] = useState<any>(null);

  const { data: soServices } = useServiceOrderServices(orderId);
  const addService = useAddServiceOrderService();
  const removeService = useRemoveServiceOrderService();

  const { data: timeEntries } = useTimeEntries(orderId);
  const addTime = useAddTimeEntry();
  const removeTime = useRemoveTimeEntry();

  const { data: soExpenses } = useServiceOrderExpenses(orderId);
  const addExpense = useAddServiceOrderExpense();
  const updateExpense = useUpdateServiceOrderExpense();
  const removeExpense = useRemoveServiceOrderExpense();
  
  const { isOptimizing, optimizeText } = useAITextOptimizer();

  // Form state
  const [form, setForm] = useState<Record<string, any>>({
    status: 'draft',
    priority: 'normal',
    service_type: 'repair',
    client_id: '',
    vessel_id: '',
    marina_id: '',
    requested_by_name: '',
    requested_by_contact_id: '',
    scheduled_start_at: '',
    scheduled_end_at: '',
    problem_description: '',
    initial_findings: '',
    diagnosis: '',
    solution_applied: '',
    technician_notes: '',
    extra_notes: '',
    internal_notes: '',
    customer_visible_report: '',
    travel_distance_km: 0,
    travel_cost_per_km: 3.5,
    technician_count_for_travel: 1,
    travel_cost_total: 0,
    travel_hours: 0,
    ferry_cost: 0,
    travel_type: 'comercial' as 'comercial' | 'urgencia' | 'fds_feriado',
    discount_amount: 0,
    tax_amount: 0,
    subcontract_cost_total: 0,
    commission_rate: 0,
    commission_amount: 0,
    commissioned_person: '',
    commissioned_user_id: '',
    payment_conditions: '',
    payment_condition_preset_id: '',
    financial_notes: '',
    payment_method_preferred: '',
    quote_validity_days: 15,
    signed_at: '' as string,
  });

  const [manualTravel, setManualTravel] = useState(false);
  const [selectedTechnicians, setSelectedTechnicians] = useState<string[]>([]);
  const [extraFieldsOpen, setExtraFieldsOpen] = useState(false);
  const [discountServicesPct, setDiscountServicesPct] = useState(0);
  const [discountPartsPct, setDiscountPartsPct] = useState(0);
  const [showTravelDialog, setShowTravelDialog] = useState(false);
  const [showExpensesDialog, setShowExpensesDialog] = useState(false);
  const [showTimeDialog, setShowTimeDialog] = useState(false);
  const [showFinancialDialog, setShowFinancialDialog] = useState(false);
  const [depositDialogOpen, setDepositDialogOpen] = useState(false);
  const [showCommission, setShowCommission] = useState(false);
  const [depositFromFinancial, setDepositFromFinancial] = useState(false);
  const { data: vesselContacts } = useVesselContacts(form.vessel_id || undefined);

  // Part inline-card state (matches the services pattern)
  type PartCardDraft = {
    product_id: string;
    name: string;
    unit: string;
    quantity: number;
    unit_cost: number;
    unit_sale: number;
    notes: string;
    image_url?: string | null;
  };
  const emptyPartCard = (): PartCardDraft => ({
    product_id: '',
    name: '',
    unit: 'un',
    quantity: 1,
    unit_cost: 0,
    unit_sale: 0,
    notes: '',
    image_url: null,
  });
  const [editingPart, setEditingPart] = useState<Record<string, PartCardDraft>>({});
  const [openNewPartCards, setOpenNewPartCards] = useState<string[]>([]);
  const [priceCalcCardKey, setPriceCalcCardKey] = useState<string | null>(null);
  const updatePartLine = useUpdateServiceOrderPart();
  // Kept for backwards compatibility (no longer opened from the parts row)
  const [quickProductOpen, setQuickProductOpen] = useState(false);
  const [quickProductName, setQuickProductName] = useState('');
  const [quickMarinaOpen, setQuickMarinaOpen] = useState(false);
  const [quickMarinaName, setQuickMarinaName] = useState('');
  const [quickSupplierOpen, setQuickSupplierOpen] = useState(false);
  const [quickSupplierName, setQuickSupplierName] = useState('');

  // Service line cards (inline expanding cards)
  type SvcCardDraft = {
    service_id: string;
    name_snapshot: string;
    description_snapshot: string;
    billing_unit_snapshot: string;
    quantity: number;
    unit_price: number;
    notes: string;
    technician_user_id: string;
    warranty_months?: number;
  };
  const emptySvcCard = (): SvcCardDraft => ({
    service_id: '',
    name_snapshot: '',
    description_snapshot: '',
    billing_unit_snapshot: 'hour',
    quantity: 1,
    unit_price: 0,
    notes: '',
    technician_user_id: '',
    warranty_months: 0,
  });
  // Editing state per row id (persisted: row.id, draft: tempId, new: 'new-N')
  const [editingSvc, setEditingSvc] = useState<Record<string, SvcCardDraft>>({});
  const [openNewSvcCards, setOpenNewSvcCards] = useState<string[]>([]);
  const [showNewServiceDialog, setShowNewServiceDialog] = useState(false);
  const updateSvcLine = useUpdateServiceOrderService();

  // Draft items used while OS is new (no orderId yet) — persisted on save
  type DraftPart = {
    tempId: string;
    product_id: string;
    name: string;
    quantity: number;
    unit_cost: number;
    unit_sale: number;
    warranty_months?: number;
    serial_number?: string;
  };
  type DraftService = {
    tempId: string;
    service_id?: string;
    name_snapshot: string;
    description_snapshot?: string;
    billing_unit_snapshot: string;
    quantity: number;
    unit_price_snapshot: number;
    notes?: string;
    warranty_months?: number;
  };
  const [draftParts, setDraftParts] = useState<DraftPart[]>([]);
  const [draftServices, setDraftServices] = useState<DraftService[]>([]);

  // Time form
  const [timeForm, setTimeForm] = useState({
    technician_user_id: '', started_at: '', ended_at: '', duration_minutes: 0, billable: true, notes: '',
  });
  const [showTimeForm, setShowTimeForm] = useState(false);

  // Expense form
  const [expForm, setExpForm] = useState({
    category: '', description: '', amount: 0, currency: 'BRL',
    expense_date: new Date().toISOString().slice(0, 10),
    paid_by: 'company' as 'company' | 'technician',
    technician_user_id: '', receipt_url: '', receipt_storage_path: '', notes: '',
    also_create_payable: false,
    supplier_id: '',
  });
  const [showExpForm, setShowExpForm] = useState(false);
  const [editingExpenseId, setEditingExpenseId] = useState<string | null>(null);
  const [uploadingReceipt, setUploadingReceipt] = useState(false);
  const receiptInputRef = useRef<HTMLInputElement | null>(null);

  // Card installments
  const [selectedInstallments, setSelectedInstallments] = useState(1);
  const [showCancelDialog, setShowCancelDialog] = useState(false);
  const [showReopenDialog, setShowReopenDialog] = useState(false);
  const [cancelReason, setCancelReason] = useState('');
  const [reopenReason, setReopenReason] = useState('');
  const [showZapiHistory, setShowZapiHistory] = useState(false);
  const [whatsAppTarget, setWhatsAppTarget] = useState<SendViaWhatsAppTarget | null>(null);
  const { data: waHistory } = useWhatsAppSendHistory(orderId || null);
  const lastWaSend = waHistory?.[0];
  const [pdfDialogType, setPdfDialogType] = useState<'quote' | 'service_order' | 'invoice' | null>(null);
  const [downloadingType, setDownloadingType] = useState<'quote' | 'service_order' | 'invoice' | null>(null);
  const [waPreview, setWaPreview] = useState<{ phone: string; message: string; url: string; clientName: string } | null>(null);
  const [waEditMessage, setWaEditMessage] = useState('');
  const [waEditPhone, setWaEditPhone] = useState('');
  const [presetKey, setPresetKey] = useState(0);

  const [generatingCollections, setGeneratingCollections] = useState(false);
  const prevSignedAt = useRef<string | null>(null);
  const topActionsRef = useRef<HTMLDivElement | null>(null);
  const bottomSaveRef = useRef<HTMLDivElement | null>(null);
  const [topVisible, setTopVisible] = useState(true);
  const [bottomVisible, setBottomVisible] = useState(false);
  const { data: osCollections } = useCollectionsByOS(orderId);
  // M1: recebíveis desta OS para resumo financeiro
  const { data: soReceivables } = useReceivablesByServiceOrder(orderId);
  // M2: histórico de pagamentos desta OS
  const { data: soPayments } = usePaymentsByServiceOrder(orderId);
  const [showPaymentHistory, setShowPaymentHistory] = useState(false);

  useEffect(() => {
    const targets: Array<{ el: HTMLElement | null; setter: (v: boolean) => void }> = [
      { el: topActionsRef.current, setter: setTopVisible },
      { el: bottomSaveRef.current, setter: setBottomVisible },
    ];
    const observers: IntersectionObserver[] = [];
    for (const { el, setter } of targets) {
      if (!el) continue;
      const io = new IntersectionObserver(
        ([entry]) => setter(entry.isIntersecting),
        { rootMargin: '0px', threshold: 0.01 },
      );
      io.observe(el);
      observers.push(io);
    }
    return () => observers.forEach((o) => o.disconnect());
  }, [isLoading, orderId]);

  const handleGenerateCollections = useCallback(async () => {
    if (!orderId) return;
    setGeneratingCollections(true);
    try {
      const { generateCollectionsFromOS } = await import('@/lib/generate-collections');
      const approvalDate = form.signed_at
        ? form.signed_at.slice(0, 10)
        : new Date().toISOString().slice(0, 10);
      const result = await generateCollectionsFromOS({
        serviceOrderId: orderId,
        approvalDate,
        trigger: 'status_change',
      });
      if (result.skipped) {
        toast.info('Cobranças já existem para esta OS ou valor é zero.');
      } else {
        toast.success(`${result.created} cobrança(s) gerada(s) e enviadas por WhatsApp!`);
      }
    } catch (err: any) {
      toast.error(err?.message || 'Erro ao gerar cobranças');
    } finally {
      setGeneratingCollections(false);
    }
  }, [orderId, form.signed_at]);

  // Auto-generate collections when OS is signed
  useEffect(() => {
    if (!orderId || !form.signed_at) return;
    if (prevSignedAt.current === form.signed_at) return;
    if (prevSignedAt.current === null) {
      // first observation — only trigger on transition, not on initial load
      prevSignedAt.current = form.signed_at;
      return;
    }
    prevSignedAt.current = form.signed_at;
    handleGenerateCollections();
  }, [form.signed_at, orderId, handleGenerateCollections]);

  useEffect(() => {
    if (orderData) {
      const d = orderData;
      setForm({
        status: d.status || 'draft',
        priority: d.priority || 'normal',
        service_type: d.service_type || 'repair',
        client_id: d.client_id || '',
        vessel_id: d.vessel_id || '',
        marina_id: d.marina_id || '',
        requested_by_name: d.requested_by_name || '',
        requested_by_contact_id: d.requested_by_contact_id || '',
        scheduled_start_at: d.scheduled_start_at ? d.scheduled_start_at.slice(0, 16) : '',
        scheduled_end_at: d.scheduled_end_at ? d.scheduled_end_at.slice(0, 16) : '',
        problem_description: d.problem_description || '',
        initial_findings: d.initial_findings || '',
        diagnosis: d.diagnosis || '',
        solution_applied: d.solution_applied || '',
        technician_notes: d.technician_notes || '',
        extra_notes: d.extra_notes || '',
        internal_notes: d.internal_notes || '',
        customer_visible_report: d.customer_visible_report || '',
        travel_distance_km: d.travel_distance_km || 0,
        travel_cost_per_km: d.travel_cost_per_km || 3.5,
        technician_count_for_travel: d.technician_count_for_travel || 1,
        travel_cost_total: d.travel_cost_total || 0,
        travel_hours: d.travel_hours || 0,
        ferry_cost: d.ferry_cost || 0,
        travel_type: (d.travel_type as any) || 'comercial',
        discount_amount: d.discount_amount || 0,
        tax_amount: d.tax_amount || 0,
        subcontract_cost_total: d.subcontract_cost_total || 0,
        commission_rate: d.commission_rate || 0,
        commission_amount: d.commission_amount || 0,
        commissioned_person: d.commissioned_person || '',
        commissioned_user_id: d.commissioned_user_id || '',
        payment_conditions: d.payment_conditions || '',
        payment_condition_preset_id: d.payment_condition_preset_id || '',
        financial_notes: d.financial_notes || '',
        payment_method_preferred: d.payment_method_preferred || '',
        quote_validity_days: d.quote_validity_days ?? 15,
        signed_at: d.signed_at || '',
      });
      if (d.service_order_technicians) {
        setSelectedTechnicians(d.service_order_technicians.map((t: any) => t.user_id));
      }
      setDiscountServicesPct(Number(d.discount_services_pct) || 0);
      setDiscountPartsPct(Number(d.discount_parts_pct) || 0);
      // Open extra fields if any has content
      if (d.initial_findings || d.diagnosis || d.solution_applied || d.internal_notes || d.customer_visible_report || d.extra_notes) {
        setExtraFieldsOpen(true);
      }
    }
  }, [orderData]);

  const set = (field: string, value: any) => setForm((p) => ({ ...p, [field]: value }));

  // Filter vessels by client
  const clientVessels = allVessels?.filter((v) => v.client_id === form.client_id) || [];

  // Auto-select single vessel
  useEffect(() => {
    if (form.client_id && clientVessels.length === 1 && !form.vessel_id) {
      set('vessel_id', clientVessels[0].id);
      if (clientVessels[0].marina_id) set('marina_id', clientVessels[0].marina_id);
    }
  }, [form.client_id, clientVessels.length]);

  // Auto displacement
  const runDisplacement = useCallback(async () => {
    const marina = marinas?.find((m) => m.id === form.marina_id);
    if (!marina?.latitude || !marina?.longitude) return;
    try {
      const result = await calculateDisplacement(
        Number(marina.latitude),
        Number(marina.longitude),
        form.technician_count_for_travel
      );
      set('travel_distance_km', result.distance_km);
      set('travel_cost_per_km', result.cost_per_km);
      set('travel_cost_total', result.total_cost);
    } catch (e) {
      console.error('Displacement calc failed', e);
    }
  }, [form.marina_id, form.technician_count_for_travel, marinas]);

  // Financial summary
  const laborCost = orderData?.labor_cost_total || 0;
  const partsCost = orderData?.parts_cost_total || 0;
  const operationalCost = orderData?.operational_cost_total || 0;
  const expensesTotal = operationalCost
    + (form.travel_cost_total || 0)
    + (form.subcontract_cost_total || 0);
  const selectedPreset = (paymentPresets || []).find(
    (p: any) =>
      p.id === form.payment_condition_preset_id ||
      (p.label === form.payment_conditions && !form.payment_condition_preset_id)
  );
  const installmentRows = Array.isArray(selectedPreset?.installments)
    ? (selectedPreset.installments as any[]).map((r: any) => ({
        label: r.label || '',
        services_pct: Number(r.services_pct ?? r.percent ?? 0),
        parts_pct: Number(r.parts_pct ?? r.percent ?? 0),
        expenses_pct: Number(r.expenses_pct ?? 0),
        days_after_approval: Number(r.days_after_approval ?? 0),
        tipo: r.tipo as 'aprovacao' | 'entrega' | 'prazo' | undefined,
      }))
    : [];
  const subtotal = laborCost + partsCost + operationalCost + (form.travel_cost_total || 0) + (form.subcontract_cost_total || 0);
  const grandTotal = subtotal - (form.discount_amount || 0) + (form.tax_amount || 0);
  // Apply the discount ratio proportionally to each installment row
  const discountRatio = subtotal > 0 ? grandTotal / subtotal : 1;
  const calcInstallmentAmount = (row: typeof installmentRows[0]) => {
    const gross =
      (laborCost * row.services_pct / 100)
      + (partsCost * row.parts_pct / 100)
      + (expensesTotal * row.expenses_pct / 100);
    return Math.round(gross * discountRatio * 100) / 100;
  };

  // Sinal (deposit) row from preset — first installment with tipo='aprovacao' or days=0
  const signalRow = installmentRows.find(r => r.tipo === 'aprovacao' || r.days_after_approval === 0);
  const signalAmount = signalRow ? calcInstallmentAmount(signalRow) : null;

  // Card fee calculation
  const selectedFee = cardFees?.find((f) => f.installments === selectedInstallments);
  const feePercent = selectedFee?.fee_percent || 0;
  const cardGross = feePercent > 0 ? grandTotal / (1 - Number(feePercent) / 100) : grandTotal;
  const cardFeeAmount = cardGross - grandTotal;
  const installmentValue = selectedInstallments > 0 ? cardGross / selectedInstallments : cardGross;

  // Parts profit (edit-mode only, never in PDF)
  const partsRevenue = (parts || []).reduce((sum: number, p: any) => sum + (p.line_total_sale || 0), 0);
  const partsCostItems = (parts || []).reduce((sum: number, p: any) => sum + (p.line_total_cost || 0), 0);
  const partsProfit = partsRevenue - partsCostItems;
  const partsMarginPct = partsRevenue > 0 ? (partsProfit / partsRevenue) * 100 : 0;

  // Section subtotals
  const servicesItemCount = (soServices || []).length;
  const billableHours = orderData?.labor_hours_total || 0;
  const partsItemCount = (parts || []).length;

  // M1: Totais financeiros da OS a partir dos recebíveis reais
  const soTotalCharged = (soReceivables || []).reduce((s, r) => s + Number((r as any).amount || 0), 0);
  const soTotalPaid    = (soReceivables || []).reduce((s, r) => s + Number((r as any).paid_amount || 0), 0);
  const soBalance      = (soReceivables || []).reduce((s, r) => s + Number((r as any).balance_amount || 0), 0);
  const soPayStatus = soBalance <= 0 && soTotalCharged > 0 ? 'paid'
    : soTotalPaid > 0 ? 'partially_paid' : 'unpaid';

  const handleSave = async () => {
    if (!form.client_id || !form.vessel_id || !form.problem_description) {
      toast.error('Preencha cliente, embarcação e descrição do problema');
      return;
    }
    try {
      const { signed_at: _signedAt, ...formForSave } = form;
      // Helper: convert empty string to null for UUID fields
      const uuidOrNull = (v: string | null | undefined) => (v && v.trim() !== '' ? v : null);

      const payload = {
        ...formForSave,
        scheduled_start_at: form.scheduled_start_at || null,
        scheduled_end_at: form.scheduled_end_at || null,
        commissioned_user_id: uuidOrNull(form.commissioned_user_id),
        requested_by_contact_id: uuidOrNull(form.requested_by_contact_id),
        marina_id: uuidOrNull(form.marina_id),
        payment_conditions: form.payment_conditions || null,
        payment_condition_preset_id: uuidOrNull(form.payment_condition_preset_id),
        // Always persist the computed grand_total so the PDF and receivables
        // always reflect the current discount/tax/travel values.
        grand_total: Math.round(grandTotal * 100) / 100,
        discount_services_pct: discountServicesPct,
        discount_parts_pct: discountPartsPct,
        financial_notes: form.financial_notes || null,
        payment_method_preferred: form.payment_method_preferred || null,
        quote_validity_days: form.quote_validity_days || 15,
      };

      if (isNew) {
        const result = await createSO.mutateAsync(payload);
        const { supabase } = await import('@/integrations/supabase/client');
        const validTechs = selectedTechnicians.filter(uid => uid && uid.trim() !== '');
        if (validTechs.length > 0) {
          await supabase.from('service_order_technicians').insert(
            validTechs.map((uid) => ({ service_order_id: result.id, user_id: uid }))
          );
        }
        if (selectedTechnicians.length > 0) {
          for (const uid of selectedTechnicians) {
            if (!uid || uid.trim() === '') continue;
            supabase.functions.invoke('send-push-notification', {
              body: {
                user_id: uid,
                title: 'Nova OS atribuída',
                body: `Você foi atribuído à OS ${result.service_order_number ?? ''}`,
                url: `/service-orders/${result.id}`,
              },
            }).catch((e) => console.warn('push notify failed', e));
          }
        }
        // Persist any draft parts entered before the OS existed
        for (const dp of draftParts) {
          try {
            await addPart.mutateAsync({
              service_order_id: result.id,
              product_id: dp.product_id,
              quantity: dp.quantity,
              unit_cost_snapshot: dp.unit_cost,
              unit_sale_snapshot: dp.unit_sale,
            });
          } catch (err) {
            console.error('Failed to persist draft part', err);
          }
        }
        for (const ds of draftServices) {
          try {
            await addService.mutateAsync({
              service_order_id: result.id,
              service_id: ds.service_id || undefined,
              name_snapshot: ds.name_snapshot,
              description_snapshot: ds.description_snapshot || undefined,
              billing_unit_snapshot: ds.billing_unit_snapshot,
              quantity: ds.quantity,
              unit_price_snapshot: ds.unit_price_snapshot,
              notes: ds.notes || undefined,
              technician_user_id: (ds as any).technician_user_id || null,
            });
          } catch (err) {
            console.error('Failed to persist draft service', err);
          }
        }
        toast.success('Ordem de serviço criada com sucesso');
        navigate(`/service-orders/${result.id}`);
      } else {
        await updateSO.mutateAsync({ id: orderId!, ...payload });
        const { supabase } = await import('@/integrations/supabase/client');
        const { data: existingTechs } = await supabase
          .from('service_order_technicians')
          .select('user_id')
          .eq('service_order_id', orderId!);
        const existingIds = new Set((existingTechs ?? []).map((t: any) => t.user_id));
        await supabase.from('service_order_technicians').delete().eq('service_order_id', orderId!);
        const validTechs = selectedTechnicians.filter(uid => uid && uid.trim() !== '');
        if (validTechs.length > 0) {
          await supabase.from('service_order_technicians').insert(
            validTechs.map((uid) => ({ service_order_id: orderId!, user_id: uid }))
          );
        }
        if (selectedTechnicians.length > 0) {
          const newlyAssigned = selectedTechnicians.filter((uid) => !existingIds.has(uid));
          for (const uid of newlyAssigned) {
            if (!uid || uid.trim() === '') continue;
            supabase.functions.invoke('send-push-notification', {
              body: {
                user_id: uid,
                title: 'Nova OS atribuída',
                body: `Você foi atribuído à OS ${form.service_order_number ?? ''}`,
                url: `/service-orders/${orderId}`,
              },
            }).catch((e) => console.warn('push notify failed', e));
          }
        }
        toast.success('Ordem de serviço atualizada');

        // Audit log for financial field changes
        if (orderData) {
          const financialFields = ['discount_amount', 'tax_amount', 'grand_total', 'commission_rate', 'commission_amount'] as const;
          const changed: Record<string, { before: any; after: any }> = {};
          for (const f of financialFields) {
            const before = (orderData as any)[f];
            const after = (payload as any)[f] ?? (form as any)[f];
            if (before !== undefined && after !== undefined && Number(before) !== Number(after)) {
              changed[f] = { before, after };
            }
          }
          if (Object.keys(changed).length > 0) {
            writeAuditLog({
              table_name: 'service_orders',
              record_id: orderId!,
              action: 'update' as any,
              new_value: { financial_changes: changed },
              reason: 'Campos financeiros alterados manualmente',
            }).catch(() => {});
          }
        }

        // M4: Auto-gerar cobranças quando OS é concluída com preset de parcelamento
        if (form.status === 'completed' && form.payment_condition_preset_id) {
          const { generateCollectionsFromOS } = await import('@/lib/generate-collections');
          generateCollectionsFromOS({
            serviceOrderId: orderId!,
            approvalDate: new Date().toISOString().slice(0, 10),
            trigger: 'status_change',
          })
            .then((res) => {
              if (res.created > 0) {
                toast.success(`${res.created} cobrança(s) parcelada(s) gerada(s) automaticamente.`);
              }
            })
            .catch((err) => console.error('auto-generate-collections (completed) failed', err));
        }

        // Auto-trigger collection generation when status becomes 'invoiced'
        if (form.status === 'invoiced') {
          const { generateCollectionsFromOS } = await import('@/lib/generate-collections');
          generateCollectionsFromOS({
            serviceOrderId: orderId!,
            approvalDate: new Date().toISOString().slice(0, 10),
            trigger: 'invoice',
          })
            .then((res) => {
              if (res.created > 0) {
                toast.success(`${res.created} cobrança(s) gerada(s) automaticamente.`);
              }
            })
            .catch((err) => console.error('auto-generate-collections (invoice) failed', err));
        }
      }
    } catch (e: any) {
      toast.error(e.message || 'Erro ao salvar');
    }
  };

  const handleStatusChange = async (newStatus: string) => {
    if (!orderId) return;
    try {
      await updateStatus.mutateAsync({ id: orderId, status: newStatus });
      toast.success(`Status alterado para ${(t.status as Record<string, string>)[newStatus]}`);

      // Deposit alert: when completing/invoicing, check if a deposit was already paid
      if (newStatus === 'completed' || newStatus === 'invoiced') {
        const { data: deposits } = await (await import('@/integrations/supabase/client')).supabase
          .from('receivables')
          .select('paid_amount')
          .eq('service_order_id', orderId)
          .eq('is_deposit', true)
          .eq('status', 'paid');

        const totalDeposit = (deposits || []).reduce((sum, r) => sum + (r.paid_amount || 0), 0);
        if (totalDeposit > 0) {
          const fmt = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(totalDeposit);
          toast.info(`Sinal de ${fmt} já foi recebido. Lembre-se de descontar no valor da cobrança final.`, { duration: 8000 });
        }
      }
    } catch (e: any) {
      toast.error(e.message || 'Erro ao alterar status');
    }
  };

  const handleDuplicate = async () => {
    if (!orderId) return;
    try {
      // In the form context, replicate the same type as the source:
      // draft → quote (ORÇ), anything else → order (OS)
      const mode = orderData?.status === 'draft' ? 'quote' : 'order';
      const newSO = await duplicate.mutateAsync({ sourceId: orderId, mode });
      toast.success(mode === 'quote' ? 'Orçamento duplicado!' : 'OS duplicada com sucesso!');
      navigate(`/service-orders/${(newSO as any).id}`);
    } catch (e: any) {
      toast.error(e?.message || 'Erro ao duplicar');
    }
  };

  // Ensure the product exists in the catalog. If product_id is empty,
  // create a new entry in `products` and return the new id.
  const ensureProductInCatalog = async (draft: PartCardDraft): Promise<string> => {
    if (draft.product_id) return draft.product_id;
    const { data, error } = await supabase
      .from('products')
      .insert({
        name: draft.name,
        cost_price: draft.unit_cost,
        sale_price: draft.unit_sale,
        unit: draft.unit || 'un',
        active: true,
        fiscal_complete: false,
        stock_quantity: 0,
        minimum_stock: 0,
        cost_currency: 'BRL',
        sale_currency: 'BRL',
      } as any)
      .select('id')
      .single();
    if (error) throw error;
    queryClient.invalidateQueries({ queryKey: ['products'] });
    return data.id as string;
  };

  const addNewPartCard = () => {
    const key = `new-${crypto.randomUUID()}`;
    setEditingPart((prev) => ({ ...prev, [key]: emptyPartCard() }));
    setOpenNewPartCards((prev) => [...prev, key]);
  };

  const cancelPartCard = (key: string, isNewCard: boolean) => {
    setEditingPart((prev) => {
      const next = { ...prev };
      delete next[key];
      return next;
    });
    if (isNewCard) {
      setOpenNewPartCards((prev) => prev.filter((k) => k !== key));
    }
  };

  const startEditPersistedPart = (row: any) => {
    setEditingPart((prev) => ({
      ...prev,
      [row.id]: {
        product_id: row.product_id || '',
        name: row.products?.name || '',
        unit: row.products?.unit || 'un',
        quantity: Number(row.quantity) || 1,
        unit_cost: Number(row.unit_cost_snapshot) || 0,
        unit_sale: Number(row.unit_sale_snapshot) || 0,
        notes: row.notes || '',
      },
    }));
  };

  const handleConfirmNewPartCard = async (cardKey: string) => {
    const draft = editingPart[cardKey];
    if (!draft) return;
    if (!draft.name.trim() || draft.quantity <= 0) {
      toast.error('Preencha nome e quantidade');
      return;
    }
    try {
      const productId = await ensureProductInCatalog(draft);

      // Stock check: only for actual OS (non-draft). During the quote phase
      // the OS doesn't exist yet, so creating a PO at this point makes no sense —
      // the PO flow is triggered later at the moment of conversion (StockConfirmationDialog).
      if (!isNew && orderId && draft.quantity > 0 && orderData?.status !== 'draft') {
        const { data: prodData } = await supabase
          .from('products')
          .select('stock_quantity, minimum_stock, product_suppliers(supplier_id, suppliers(id, name)), product_suppliers!inner(lead_time_days)')
          .eq('id', productId)
          .maybeSingle();
        const available = prodData?.stock_quantity ?? 0;
        if (available < draft.quantity) {
          const suppliers = ((prodData as any)?.product_suppliers ?? [])
            .map((ps: any) => ps.suppliers)
            .filter(Boolean)
            .map((s: any) => ({ id: s.id, name: s.name }));
          const leadTimeDays = (prodData as any)?.product_suppliers?.[0]?.lead_time_days ?? undefined;
          setStockAlert({
            cardKey: cardKey,
            productId,
            productName: draft.name,
            needed: draft.quantity,
            available: Math.max(0, available),
            unitCost: draft.unit_cost,
            unitSale: draft.unit_sale,
            notes: draft.notes,
            suppliers,
            leadTimeDays,
          });
          return; // pause — user chooses action in dialog
        }
      }

      if (isNew) {
        setDraftParts((prev) => [
          ...prev,
          {
            tempId: crypto.randomUUID(),
            product_id: productId,
            name: draft.name,
            quantity: draft.quantity,
            unit_cost: draft.unit_cost,
            unit_sale: draft.unit_sale,
          },
        ]);
        toast.success('Peça adicionada (será salva ao criar a OS)');
      } else {
        if (!orderId) return;
        await addPart.mutateAsync({
          service_order_id: orderId,
          product_id: productId,
          quantity: draft.quantity,
          unit_cost_snapshot: draft.unit_cost,
          unit_sale_snapshot: draft.unit_sale,
          notes: draft.notes || undefined,
        });
        toast.success('Peça adicionada');
      }
      setOpenNewPartCards((prev) => prev.filter((k) => k !== cardKey));
      setEditingPart((prev) => {
        const next = { ...prev };
        delete next[cardKey];
        return next;
      });
    } catch (e: any) {
      toast.error(e.message || 'Erro ao adicionar peça');
    }
  };

  const handleConfirmEditPart = async (rowId: string, originalRow: any) => {
    const draft = editingPart[rowId];
    if (!draft || !orderId) return;
    if (!draft.name.trim() || draft.quantity <= 0) {
      toast.error('Preencha nome e quantidade');
      return;
    }
    try {
      const productId = await ensureProductInCatalog(draft);
      await updatePartLine.mutateAsync({
        id: rowId,
        service_order_id: orderId,
        product_id: productId,
        previous_quantity: Number(originalRow.quantity) || 0,
        quantity: draft.quantity,
        unit_cost_snapshot: draft.unit_cost,
        unit_sale_snapshot: draft.unit_sale,
        notes: draft.notes || null,
      });
      setEditingPart((prev) => {
        const next = { ...prev };
        delete next[rowId];
        return next;
      });
      toast.success('Peça atualizada');
    } catch (e: any) {
      toast.error(e.message || 'Erro ao atualizar peça');
    }
  };


  // Ensure the service exists in the catalog. If service_id is empty,
  // create a new entry in `services` and return the new id.
  const ensureServiceInCatalog = async (draft: SvcCardDraft): Promise<string> => {
    if (draft.service_id) return draft.service_id;
    const { data, error } = await supabase
      .from('services')
      .insert({
        name: draft.name_snapshot,
        default_price: draft.unit_price,
        billing_unit: draft.billing_unit_snapshot,
        active: true,
      } as any)
      .select('id')
      .single();
    if (error) throw error;
    queryClient.invalidateQueries({ queryKey: ['services'] });
    return data.id as string;
  };

  // Confirm a service card (insert new line on the OS)
  const handleConfirmNewSvcCard = async (cardKey: string) => {
    const draft = editingSvc[cardKey];
    if (!draft) return;
    if (!draft.name_snapshot.trim() || draft.quantity <= 0) {
      toast.error('Preencha descrição e quantidade');
      return;
    }
    try {
      let serviceId = draft.service_id;
      // For non-draft (persisted OS) we always sync catalog. For draft OS we
      // also create the catalog entry so it becomes reusable immediately.
      if (!serviceId) {
        serviceId = await ensureServiceInCatalog(draft);
      }
      if (isNew) {
        setDraftServices((prev) => [
          ...prev,
          {
            tempId: crypto.randomUUID(),
            service_id: serviceId || undefined,
            name_snapshot: draft.name_snapshot,
            description_snapshot: draft.description_snapshot || undefined,
            billing_unit_snapshot: draft.billing_unit_snapshot,
            quantity: draft.quantity,
            unit_price_snapshot: draft.unit_price,
            notes: draft.notes || undefined,
            warranty_months: draft.warranty_months || 0,
            // technician_user_id is held client-side until OS is created
            ...(draft.technician_user_id ? { technician_user_id: draft.technician_user_id } : {}),
          } as any,
        ]);
        toast.success('Serviço adicionado (será salvo ao criar a OS)');
      } else {
        if (!orderId) return;
        await addService.mutateAsync({
          service_order_id: orderId,
          service_id: serviceId || undefined,
          name_snapshot: draft.name_snapshot,
          description_snapshot: draft.description_snapshot || undefined,
          billing_unit_snapshot: draft.billing_unit_snapshot,
          quantity: draft.quantity,
          unit_price_snapshot: draft.unit_price,
          notes: draft.notes || undefined,
          technician_user_id: draft.technician_user_id || null,
          warranty_months: draft.warranty_months || 0,
        } as any);
        toast.success('Serviço adicionado');
      }
      // Close the card
      setOpenNewSvcCards((prev) => prev.filter((k) => k !== cardKey));
      setEditingSvc((prev) => {
        const next = { ...prev };
        delete next[cardKey];
        return next;
      });
    } catch (e: any) {
      toast.error(e.message || 'Erro ao adicionar serviço');
    }
  };

  // Confirm an edit on an existing persisted line
  const handleConfirmEditSvc = async (rowId: string) => {
    const draft = editingSvc[rowId];
    if (!draft || !orderId) return;
    if (!draft.name_snapshot.trim() || draft.quantity <= 0) {
      toast.error('Preencha descrição e quantidade');
      return;
    }
    try {
      let serviceId = draft.service_id;
      if (!serviceId) serviceId = await ensureServiceInCatalog(draft);
      await updateSvcLine.mutateAsync({
        id: rowId,
        service_order_id: orderId,
        service_id: serviceId || null,
        name_snapshot: draft.name_snapshot,
        description_snapshot: draft.description_snapshot || null,
        billing_unit_snapshot: draft.billing_unit_snapshot,
        quantity: draft.quantity,
        unit_price_snapshot: draft.unit_price,
        notes: draft.notes || null,
        technician_user_id: draft.technician_user_id || null,
      });
      setEditingSvc((prev) => {
        const next = { ...prev };
        delete next[rowId];
        return next;
      });
      toast.success('Serviço atualizado');
    } catch (e: any) {
      toast.error(e.message || 'Erro ao atualizar serviço');
    }
  };

  const addNewSvcCard = () => {
    const key = `new-${crypto.randomUUID()}`;
    setEditingSvc((prev) => ({ ...prev, [key]: emptySvcCard() }));
    setOpenNewSvcCards((prev) => [...prev, key]);
  };

  const cancelSvcCard = (key: string, isNewCard: boolean) => {
    setEditingSvc((prev) => {
      const next = { ...prev };
      delete next[key];
      return next;
    });
    if (isNewCard) {
      setOpenNewSvcCards((prev) => prev.filter((k) => k !== key));
    }
  };

  const startEditPersisted = (row: any) => {
    setEditingSvc((prev) => ({
      ...prev,
      [row.id]: {
        service_id: row.service_id || '',
        name_snapshot: row.name_snapshot || '',
        description_snapshot: row.description_snapshot || '',
        billing_unit_snapshot: row.billing_unit_snapshot || 'hour',
        quantity: Number(row.quantity) || 1,
        unit_price: Number(row.unit_price_snapshot) || 0,
        notes: row.notes || '',
        technician_user_id: row.technician_user_id || '',
      },
    }));
  };


  const handleAddTime = async () => {
    if (!orderId || !timeForm.technician_user_id || !timeForm.started_at) return;
    try {
      await addTime.mutateAsync({
        service_order_id: orderId,
        ...timeForm,
        ended_at: timeForm.ended_at || undefined,
      });
      setTimeForm({ technician_user_id: '', started_at: '', ended_at: '', duration_minutes: 0, billable: true, notes: '' });
      setShowTimeForm(false);
      toast.success('Registro de tempo adicionado');
    } catch (e: any) {
      toast.error(e.message || 'Erro ao registrar tempo');
    }
  };

  const resetExpForm = () => {
    setExpForm({
      category: '', description: '', amount: 0, currency: 'BRL',
      expense_date: new Date().toISOString().slice(0, 10),
      paid_by: 'company', technician_user_id: '', receipt_url: '', receipt_storage_path: '', notes: '',
      also_create_payable: false,
      supplier_id: '',
    });
    setEditingExpenseId(null);
  };

  const handleEditExpense = (exp: any) => {
    setExpForm({
      category: exp.category || '',
      description: exp.description || '',
      amount: Number(exp.amount) || 0,
      currency: exp.currency || 'BRL',
      expense_date: exp.expense_date || new Date().toISOString().slice(0, 10),
      paid_by: (exp.paid_by as 'company' | 'technician') || 'company',
      technician_user_id: exp.technician_user_id || '',
      receipt_url: exp.receipt_url || '',
      receipt_storage_path: exp.receipt_storage_path || '',
      notes: exp.notes || '',
      also_create_payable: false,
      supplier_id: exp.supplier_id || '',
    });
    setEditingExpenseId(exp.id);
    setShowExpForm(true);
  };

  const handleUploadReceipt = async (file: File) => {
    if (!orderId) {
      toast.error('Salve a OS primeiro antes de anexar comprovantes');
      return;
    }
    if (file.size > 5 * 1024 * 1024) {
      toast.error('Arquivo excede 5MB');
      return;
    }
    setUploadingReceipt(true);
    try {
      const ext = file.name.split('.').pop() || 'bin';
      const uuid = (crypto as any).randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
      const path = `expenses/${orderId}/${uuid}.${ext}`;
      const { error: upErr } = await supabase.storage
        .from('expense-receipts')
        .upload(path, file, { contentType: file.type, upsert: false });
      if (upErr) throw upErr;
      const { data: urlData } = supabase.storage.from('expense-receipts').getPublicUrl(path);
      setExpForm((prev) => ({ ...prev, receipt_url: urlData.publicUrl, receipt_storage_path: path }));
      toast.success('Comprovante anexado');
    } catch (e: any) {
      toast.error(e.message || 'Erro ao enviar comprovante');
    } finally {
      setUploadingReceipt(false);
      if (receiptInputRef.current) receiptInputRef.current.value = '';
    }
  };

  const handleRemoveReceipt = async () => {
    const path = expForm.receipt_storage_path;
    if (path) {
      try {
        await supabase.storage.from('expense-receipts').remove([path]);
      } catch {
        /* swallow — still clear form */
      }
    }
    setExpForm((prev) => ({ ...prev, receipt_url: '', receipt_storage_path: '' }));
  };

  const handleAddExpense = async () => {
    if (!orderId || !expForm.category || !expForm.description || expForm.amount <= 0) return;
    try {
      if (editingExpenseId) {
        await updateExpense.mutateAsync({
          id: editingExpenseId,
          service_order_id: orderId,
          category: expForm.category,
          description: expForm.description,
          amount: expForm.amount,
          currency: expForm.currency,
          expense_date: expForm.expense_date,
          paid_by: expForm.paid_by,
          technician_user_id: expForm.paid_by === 'technician' ? expForm.technician_user_id || null : null,
          receipt_url: expForm.receipt_url || null,
          receipt_storage_path: expForm.receipt_storage_path || null,
          supplier_id: expForm.supplier_id || null,
          notes: expForm.notes || null,
        });
        toast.success('Despesa atualizada');
      } else {
        await addExpense.mutateAsync({
          service_order_id: orderId,
          category: expForm.category,
          description: expForm.description,
          amount: expForm.amount,
          currency: expForm.currency,
          expense_date: expForm.expense_date,
          paid_by: expForm.paid_by,
          technician_user_id: expForm.paid_by === 'technician' ? expForm.technician_user_id || undefined : undefined,
          receipt_url: expForm.receipt_url || undefined,
          receipt_storage_path: expForm.receipt_storage_path || undefined,
          supplier_id: expForm.supplier_id || undefined,
          notes: expForm.notes || undefined,
          also_create_payable: expForm.also_create_payable,
        });
        toast.success('Despesa adicionada');
      }
      resetExpForm();
      setShowExpForm(false);
    } catch (e: any) {
      console.error('Erro ao salvar despesa:', e);
      toast.error(e?.message || e?.details || 'Erro ao salvar despesa');
    }
  };

  useEffect(() => {
    if (timeForm.started_at && timeForm.ended_at) {
      const start = new Date(timeForm.started_at).getTime();
      const end = new Date(timeForm.ended_at).getTime();
      if (end > start) {
        setTimeForm((p) => ({ ...p, duration_minutes: Math.round((end - start) / 60000) }));
      }
    }
  }, [timeForm.started_at, timeForm.ended_at]);

  if (isLoading) return <div className="space-y-4">{Array.from({ length: 6 }).map((_, i) => <Skeleton key={i} className="h-20 w-full" />)}</div>;

  const currentStatus = form.status;
  const validTransitions = STATUS_TRANSITIONS[currentStatus] || [];
  const marina = marinas?.find((m) => m.id === form.marina_id);
  const isLocked = currentStatus === 'invoiced' || currentStatus === 'cancelled';

  const handleCancel = async () => {
    if (!orderId || cancelReason.length < 5) return;
    try {
      await cancelSO.mutateAsync({ id: orderId, reason: cancelReason });
      toast.success(t.serviceOrders.cancelSuccess);
      setShowCancelDialog(false);
      navigate('/service-orders');
    } catch (e: any) { toast.error(e.message); }
  };

  const handleReopen = async () => {
    if (!orderId || reopenReason.length < 5) return;
    try {
      await reopenSO.mutateAsync({ id: orderId, reason: reopenReason });
      toast.success(t.serviceOrders.reopenSuccess);
      setShowReopenDialog(false);
    } catch (e: any) { toast.error(e.message); }
  };

  return (
    <div className="space-y-6 animate-fade-in max-w-5xl">
      {/* Invoiced lock banner */}
      {isLocked && !isNew && (
        <div className="flex items-center justify-between rounded-lg border border-amber-200 bg-amber-50 p-4">
          <div className="flex items-center gap-2">
            <Lock className="h-5 w-5 text-amber-600" />
            <span className="text-sm font-medium text-amber-800">{t.serviceOrders.osLocked}</span>
          </div>
          {currentStatus === 'invoiced' && (
            <Button variant="outline" size="sm" onClick={() => setShowReopenDialog(true)}>
              <RotateCcw className="h-4 w-4 mr-1" /> {t.serviceOrders.reopenOS}
            </Button>
          )}
        </div>
      )}

      {/* Deposit pending banner */}
      {!isNew && (orderData as any)?.quote_status === 'awaiting_deposit' && form.status === 'draft' && (
        <div className="flex items-center justify-between rounded-lg border border-orange-200 bg-orange-50 p-4">
          <div className="flex items-center gap-2">
            <DollarSign className="h-5 w-5 text-orange-600 shrink-0" />
            <div>
              <p className="text-sm font-medium text-orange-800">Aguardando pagamento do sinal</p>
              <p className="text-xs text-orange-600 mt-0.5">O orçamento será convertido em OS automaticamente após o registro.</p>
            </div>
          </div>
          <Button
            variant="outline"
            size="sm"
            className="border-orange-300 text-orange-700 hover:bg-orange-100 gap-1 shrink-0"
            onClick={() => setDepositDialogOpen(true)}
          >
            <DollarSign className="h-4 w-4" /> Registrar sinal
          </Button>
        </div>
      )}

      {/* Deposit dialog */}
      {!isNew && orderId && (
        <RegisterDepositDialog
          open={depositDialogOpen}
          onOpenChange={v => { setDepositDialogOpen(v); if (!v) setDepositFromFinancial(false); }}
          serviceOrderId={orderId}
          serviceOrderNumber={orderData?.service_order_number || ''}
          grandTotal={grandTotal}
          laborCost={laborCost}
          partsCost={partsCost}
          presetServicesPct={depositFromFinancial && signalRow ? signalRow.services_pct : undefined}
          presetPartsPct={depositFromFinancial && signalRow ? signalRow.parts_pct : undefined}
        />
      )}

      {/* Header */}
      <div className="flex items-center gap-3 flex-wrap">
        <Button variant="ghost" size="icon" onClick={() => navigate('/service-orders')}>
          <ArrowLeft className="h-5 w-5" />
        </Button>
        <div className="flex-1 min-w-0">
          <h1 className="text-2xl font-bold truncate">
            {isNew ? t.serviceOrders.newOrder : orderData?.service_order_number}
          </h1>
          {!isNew && (
            <div className="flex items-center gap-2 mt-1">
              <StatusBadge className={statusConfig[currentStatus]?.className || ''}>
                {(t.status as Record<string, string>)[currentStatus]}
              </StatusBadge>
              <span className={priorityConfig[form.priority]?.className || ''}>
                {(t.priority as Record<string, string>)[form.priority]}
              </span>
              {lastWaSend && (
                <TooltipProvider>
                  <Tooltip>
                    <TooltipTrigger asChild>
                      <button
                        type="button"
                        onClick={() => setShowZapiHistory(true)}
                        className="inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-xs hover:bg-muted transition-colors"
                        aria-label="Ver histórico de envios WhatsApp"
                      >
                        {lastWaSend.success ? (
                          <CheckCircle2 className="h-3.5 w-3.5 text-success" />
                        ) : (
                          <XCircle className="h-3.5 w-3.5 text-destructive" />
                        )}
                        <span className={lastWaSend.success ? 'text-success' : 'text-destructive'}>
                          WhatsApp: {lastWaSend.success ? 'enviado' : 'falhou'}
                        </span>
                        <HistoryIcon className="h-3 w-3 text-muted-foreground" />
                      </button>
                    </TooltipTrigger>
                    <TooltipContent side="bottom" className="max-w-xs">
                      <div className="text-xs space-y-1">
                        <div className="font-medium">
                          Último envio: {new Date(lastWaSend.changed_at).toLocaleString('pt-BR')}
                        </div>
                        {!lastWaSend.success && (
                          <div className="text-destructive">
                            {(lastWaSend.new_value as any)?.provider_result?.error
                              || (lastWaSend.new_value as any)?.zapi_response?.error
                              || lastWaSend.reason
                              || `HTTP ${(lastWaSend.new_value as any)?.http_status ?? '?'}`}
                          </div>
                        )}
                        <div className="text-muted-foreground italic">Clique para ver histórico completo</div>
                      </div>
                    </TooltipContent>
                  </Tooltip>
                </TooltipProvider>
              )}
            </div>
          )}
        </div>
        <div ref={topActionsRef} className="flex gap-2 flex-wrap">
          {!isNew && (
            <>
              <Button variant="outline" size="sm" onClick={() => openPdfDialog('quote')} className="gap-1">
                <FileText className="h-4 w-4" />
                {t.pdf.quote}
              </Button>
              <Button
                variant="outline"
                size="sm"
                onClick={() => handleDirectDownload('quote')}
                disabled={!pdfData || downloadingType === 'quote'}
                title="Baixar Orçamento em PDF"
                className="gap-1"
              >
                {downloadingType === 'quote' ? <Loader2 className="h-4 w-4 animate-spin" /> : <Download className="h-4 w-4" />}
                Baixar
              </Button>
              <Button variant="outline" size="sm" onClick={() => openPdfDialog('service_order')} className="gap-1">
                <Printer className="h-4 w-4" />
                OS
              </Button>
              <Button
                variant="outline"
                size="sm"
                onClick={() => handleDirectDownload('service_order')}
                disabled={!pdfData || downloadingType === 'service_order'}
                title="Baixar OS em PDF"
                className="gap-1"
              >
                {downloadingType === 'service_order' ? <Loader2 className="h-4 w-4 animate-spin" /> : <Download className="h-4 w-4" />}
                Baixar
              </Button>
              {(currentStatus === 'completed' || currentStatus === 'invoiced') && (
                <>
                  <Button variant="outline" size="sm" onClick={() => openPdfDialog('invoice')} className="gap-1">
                    <Receipt className="h-4 w-4" />
                    Fatura
                  </Button>
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => handleDirectDownload('invoice')}
                    disabled={!pdfData || downloadingType === 'invoice'}
                    title="Baixar Fatura em PDF"
                    className="gap-1"
                  >
                    {downloadingType === 'invoice' ? <Loader2 className="h-4 w-4 animate-spin" /> : <Download className="h-4 w-4" />}
                    Baixar
                  </Button>
                </>
              )}
              {orderData?.share_token && (
                <Button
                  variant="outline"
                  size="sm"
                  className="gap-1 border-green-600 text-green-700 hover:bg-green-50 hover:text-green-800 dark:hover:bg-green-950"
                  onClick={() => {
                    const url = `${window.location.origin}/view/${orderData.share_token}`;
                    const phoneRaw = (orderData?.clients as any)?.whatsapp || (orderData?.clients as any)?.phone || '';
                    const phone = normalizePhoneE164(phoneRaw);
                    const clientName = (orderData?.clients as any)?.name || '';
                    const msg = `Olá${clientName ? ' ' + clientName : ''}, segue o link da Ordem de Serviço ${orderData.service_order_number}: ${url}`;
                    setWaEditPhone(phone);
                    setWaEditMessage(msg);
                    setWaPreview({ phone, message: msg, url, clientName });
                    void writeAuditLog({
                      table_name: 'service_orders',
                      record_id: orderData.id,
                      action: 'whatsapp_preview' as any,
                      new_value: {
                        share_token: orderData.share_token,
                        public_url: url,
                        phone_raw: String(phoneRaw),
                        phone_normalized: phone,
                        client_name: clientName,
                      },
                      reason: 'Abriu pré-visualização do WhatsApp',
                    });
                    recordWhatsAppEvent({
                      source: 'detail_dialog',
                      action: 'preview',
                      serviceOrderId: orderData.id,
                      serviceOrderNumber: orderData.service_order_number,
                      shareToken: orderData.share_token,
                      phoneRaw: String(phoneRaw),
                      phoneNormalized: phone,
                    });
                  }}
                >
                  <MessageCircle className="h-4 w-4" />
                  WhatsApp
                </Button>
              )}
              {orderData?.share_token && (
                <DropdownMenu>
                  <DropdownMenuTrigger asChild>
                    <Button
                      variant="outline"
                      size="sm"
                      className="gap-1 border-accent text-accent hover:bg-accent/10"
                    >
                      <Send className="h-4 w-4" />
                      Enviar WhatsApp
                      <ChevronDown className="h-3 w-3 opacity-60" />
                    </Button>
                  </DropdownMenuTrigger>
                  <DropdownMenuContent align="end">
                    <DropdownMenuItem
                      onClick={() => setWhatsAppTarget({
                        kind: 'service_order',
                        serviceOrderId: orderData.id,
                        serviceOrderNumber: orderData.service_order_number,
                        shareToken: orderData.share_token,
                        clientId: (orderData?.clients as any)?.id || (orderData as any)?.client_id || null,
                        clientName: (orderData?.clients as any)?.name || null,
                        clientPhone: (orderData?.clients as any)?.whatsapp || (orderData?.clients as any)?.phone || null,
                        documentType: 'service_order',
                      })}
                    >
                      <Printer className="h-4 w-4 mr-2" /> Enviar OS
                    </DropdownMenuItem>
                    <DropdownMenuItem
                      onClick={() => setWhatsAppTarget({
                        kind: 'service_order',
                        serviceOrderId: orderData.id,
                        serviceOrderNumber: orderData.service_order_number,
                        shareToken: orderData.share_token,
                        clientId: (orderData?.clients as any)?.id || (orderData as any)?.client_id || null,
                        clientName: (orderData?.clients as any)?.name || null,
                        clientPhone: (orderData?.clients as any)?.whatsapp || (orderData?.clients as any)?.phone || null,
                        documentType: 'quote',
                      })}
                    >
                      <FileText className="h-4 w-4 mr-2" /> Enviar Orçamento
                    </DropdownMenuItem>
                  </DropdownMenuContent>
                </DropdownMenu>
              )}
              <Button
                variant="outline"
                size="sm"
                onClick={handleDuplicate}
                disabled={isNew || duplicate.isPending}
                className="gap-1"
              >
                <Copy className="h-4 w-4" />
                Duplicar
              </Button>
            </>
          )}
          {!isNew && !isLocked && currentStatus !== 'cancelled' && (
            <Button variant="outline" size="sm" className="text-destructive" onClick={() => setShowCancelDialog(true)}>
              <Ban className="h-4 w-4 mr-1" /> {t.serviceOrders.cancelOS}
            </Button>
          )}
          {!isNew && !isLocked && validTransitions.length > 0 && (
            <Select value={currentStatus} onValueChange={handleStatusChange}>
              <SelectTrigger className="w-[200px]">
                <SelectValue>
                  <span className="text-muted-foreground text-xs mr-1">Status:</span>
                  <span className="font-medium">{(t.status as Record<string, string>)[currentStatus]}</span>
                </SelectValue>
              </SelectTrigger>
              <SelectContent>
                <SelectItem value={currentStatus} disabled className="opacity-60">
                  {(t.status as Record<string, string>)[currentStatus]} (atual)
                </SelectItem>
                {validTransitions.map((s) => (
                  <SelectItem key={s} value={s}>
                    → {(t.status as Record<string, string>)[s]}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          )}
          {!isLocked && (
            <Button onClick={handleSave} disabled={createSO.isPending || updateSO.isPending}
              className="bg-accent text-accent-foreground hover:bg-accent/90">
              {t.common.save}
            </Button>
          )}
        </div>
      </div>

      {/* Cancel Dialog */}
      <Dialog open={showCancelDialog} onOpenChange={setShowCancelDialog}>
        <DialogContent>
          <DialogHeader><DialogTitle>{t.serviceOrders.cancelOS}</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <div className="flex items-start gap-2 rounded-lg border border-destructive/30 bg-destructive/5 p-3">
              <AlertTriangle className="h-5 w-5 text-destructive shrink-0 mt-0.5" />
              <p className="text-sm">{t.serviceOrders.cancelWarning}</p>
            </div>
            <div>
              <Label>{t.serviceOrders.cancelReason}</Label>
              <Textarea value={cancelReason} onChange={e => setCancelReason(e.target.value)} placeholder="..." />
            </div>
            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={() => setShowCancelDialog(false)}>{t.common.cancel}</Button>
              <Button variant="destructive" onClick={handleCancel} disabled={cancelReason.length < 5 || cancelSO.isPending}>
                {t.serviceOrders.confirmCancel}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Reopen Dialog */}
      <Dialog open={showReopenDialog} onOpenChange={setShowReopenDialog}>
        <DialogContent>
          <DialogHeader><DialogTitle>{t.serviceOrders.reopenOS}</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <div className="flex items-start gap-2 rounded-lg border border-amber-200 bg-amber-50 p-3">
              <AlertTriangle className="h-5 w-5 text-amber-600 shrink-0 mt-0.5" />
              <p className="text-sm">{t.serviceOrders.reopenWarning}</p>
            </div>
            <div>
              <Label>{t.serviceOrders.reopenReason}</Label>
              <Textarea value={reopenReason} onChange={e => setReopenReason(e.target.value)} placeholder="..." />
            </div>
            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={() => setShowReopenDialog(false)}>{t.common.cancel}</Button>
              <Button onClick={handleReopen} disabled={reopenReason.length < 5 || reopenSO.isPending}>
                {t.serviceOrders.confirmReopen}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* A - Identification */}
      <section className="rounded-xl border bg-card p-5 shadow-sm space-y-4">
        <h2 className="font-semibold text-sm">{t.serviceOrders.tabOverview}</h2>
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <div>
            <Label>{t.common.status}</Label>
            <Select value={form.status} onValueChange={(v) => set('status', v)} disabled={!isNew}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {STATUSES.map((s) => (
                  <SelectItem key={s} value={s}>{(t.status as Record<string, string>)[s]}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div>
            <Label>{t.serviceOrders.priority}</Label>
            <Select value={form.priority} onValueChange={(v) => set('priority', v)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {PRIORITIES.map((p) => (
                  <SelectItem key={p} value={p}>{(t.priority as Record<string, string>)[p]}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div>
            <Label>{t.common.type}</Label>
            <Select value={form.service_type} onValueChange={(v) => set('service_type', v)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {SERVICE_TYPES.map((st) => (
                  <SelectItem key={st} value={st}>{(t.serviceType as Record<string, string>)[st]}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        </div>
      </section>

      {/* B - Client & Vessel */}
      <section className="rounded-xl border bg-card p-5 shadow-sm space-y-4">
        <h2 className="font-semibold text-sm">{t.serviceOrders.clientAndVessel}</h2>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div>
            <Label>{t.serviceOrders.client} *</Label>
            <ClientCombobox
              value={form.client_id}
              onChange={(clientId) => {
                set('client_id', clientId);
                set('vessel_id', '');
                set('requested_by_contact_id', '');
                set('requested_by_name', '');
              }}
              clients={clients}
              disabled={isLocked}
            />
          </div>
          <div>
            <Label>{t.serviceOrders.vessel} *</Label>
            <VesselSelect
              value={form.vessel_id}
              clientId={form.client_id}
              vessels={clientVessels}
              disabled={!form.client_id || isLocked}
              onChange={(vesselId) => {
                set('vessel_id', vesselId);
                set('requested_by_contact_id', '');
                const vessel = allVessels?.find(v => v.id === vesselId);
                if (vessel?.marina_id) set('marina_id', vessel.marina_id);
              }}
              onVesselCreated={(vessel) => {
                set('vessel_id', vessel.id);
                if (vessel.marina_id) set('marina_id', vessel.marina_id);
              }}
            />
          </div>
          <div>
            <Label>{t.serviceOrders.marina}</Label>
            <EntityCombobox
              value={form.marina_id}
              onChange={(v) => set('marina_id', v)}
              options={(marinas || []).filter((m) => m.active).map((m) => ({
                value: m.id,
                label: m.name,
                description: m.city || undefined,
              }))}
              placeholder="—"
              onCreate={(typed) => {
                setQuickMarinaName(typed);
                setQuickMarinaOpen(true);
              }}
              createLabel="+ Cadastrar nova marina"
            />
          </div>
          <div>
            <Label>{t.serviceOrders.requestedBy}</Label>
            {vesselContacts && vesselContacts.length > 0 ? (
              <Select
                value={form.requested_by_contact_id || 'none'}
                onValueChange={(v) => {
                  const contact = vesselContacts.find(c => c.id === v);
                  setForm(f => ({
                    ...f,
                    requested_by_contact_id: v === 'none' ? '' : v,
                    requested_by_name: contact?.full_name || '',
                  }));
                }}
                disabled={isLocked}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Selecionar contato" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">—</SelectItem>
                  {vesselContacts.map(c => (
                    <SelectItem key={c.id} value={c.id}>
                      <span className="flex items-center gap-1">
                        {c.full_name}
                        <span className="text-xs text-muted-foreground">
                          ({VESSEL_CONTACT_ROLES.find(r => r.value === c.role)?.label || c.role})
                        </span>
                      </span>
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            ) : (
              <div>
                <Input
                  value={form.requested_by_name}
                  onChange={e => set('requested_by_name', e.target.value)}
                  placeholder="Nome do solicitante"
                  disabled={isLocked}
                />
                {form.vessel_id && (
                  <p className="text-xs text-muted-foreground mt-1">
                    Cadastre contatos na embarcação para aparecerem aqui
                  </p>
                )}
              </div>
            )}
          </div>
        </div>
      </section>

      {/* C - Scheduling + Technicians (merged) */}
      <section className="rounded-xl border bg-card p-5 shadow-sm space-y-4">
        <h2 className="font-semibold text-sm">{t.serviceOrders.schedule}</h2>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div>
            <Label>{t.serviceOrders.scheduledStart}</Label>
            <Input type="datetime-local" value={form.scheduled_start_at} onChange={(e) => set('scheduled_start_at', e.target.value)} />
          </div>
          <div>
            <Label>{t.serviceOrders.scheduledEnd}</Label>
            <Input type="datetime-local" value={form.scheduled_end_at} onChange={(e) => set('scheduled_end_at', e.target.value)} />
          </div>
        </div>
        {/* Technicians */}
        <div>
          <Label>{t.serviceOrders.technicians}</Label>
          <div className="flex flex-wrap gap-2 mt-1">
            {(appUsers || []).filter((u: any) =>
              u.id && u.id.trim() !== '' &&
              ['admin', 'technician', 'seller'].includes(u.role)
            ).map((u) => (
              <label key={u.id} className="flex items-center gap-1.5 text-sm border rounded-lg px-3 py-1.5 cursor-pointer hover:bg-muted transition-colors">
                <input
                  type="checkbox"
                  checked={selectedTechnicians.includes(u.id)}
                  onChange={(e) => {
                    const next = e.target.checked
                      ? [...selectedTechnicians, u.id]
                      : selectedTechnicians.filter((id) => id !== u.id);
                    setSelectedTechnicians(next);
                    set('technician_count_for_travel', next.length || 1);
                  }}
                />
                {u.full_name}
              </label>
            ))}
          </div>
        </div>
      </section>

      {/* D - Problem & Technical (compact with collapsible) */}
      <section className="rounded-xl border bg-card p-5 shadow-sm space-y-4">
        <div className="flex items-center justify-between">
          <h2 className="font-semibold text-sm">{t.serviceOrders.problemDescription}</h2>
        </div>
        <div>
          <div className="flex items-center justify-between mb-1">
            <Label>{t.serviceOrders.problemDescription} *</Label>
            <Button
              type="button"
              variant="ghost"
              size="sm"
              className="h-6 px-2 text-xs text-primary hover:text-primary hover:bg-primary/10"
              onClick={async () => {
                const optimized = await optimizeText(form.problem_description);
                if (optimized) set('problem_description', optimized);
              }}
              disabled={isOptimizing || !form.problem_description || isLocked}
            >
              <Sparkles className="h-3 w-3 mr-1" /> IA
            </Button>
          </div>
          <Textarea value={form.problem_description} onChange={(e) => set('problem_description', e.target.value)} rows={3} disabled={isLocked} />
        </div>
        <Collapsible>
          <CollapsibleTrigger asChild>
            <button type="button" className="flex items-center gap-2 text-sm font-medium text-muted-foreground hover:text-foreground transition-colors w-full text-left">
              <ChevronDown className="h-3.5 w-3.5 transition-transform [[data-state=open]>&]:rotate-180" />
              Observações para impressão (PDF)
            </button>
          </CollapsibleTrigger>
          <CollapsibleContent className="pt-2">
            <Textarea
              value={form.extra_notes || ''}
              onChange={e => set('extra_notes', e.target.value)}
              placeholder="Informações específicas para este cliente, condições especiais, garantias, prazos..."
              rows={2}
              disabled={isLocked}
            />
          </CollapsibleContent>
        </Collapsible>

        {/* Photos (Only if editing existing OS) */}
        {orderData?.id && (
          <Collapsible>
            <CollapsibleTrigger asChild>
              <button type="button" className="flex items-center gap-2 text-sm font-medium text-muted-foreground hover:text-foreground transition-colors w-full text-left">
                <ChevronDown className="h-3.5 w-3.5 transition-transform [[data-state=open]>&]:rotate-180" />
                <Camera className="h-3.5 w-3.5" />
                Fotos da OS
              </button>
            </CollapsibleTrigger>
            <CollapsibleContent className="pt-3">
              <ServiceOrderPhotos serviceOrderId={orderData.id} />
            </CollapsibleContent>
          </Collapsible>
        )}
      </section>

      {/* E - Labor Services — always visible (with always-on entry row) */}
      <section className="rounded-xl border bg-card shadow-sm overflow-hidden">
        <div className="p-5 border-b">
          <h2 className="font-semibold text-sm">{t.services.laborSection}</h2>
          {isNew && (
            <p className="text-xs text-muted-foreground mt-1">
              Itens adicionados aqui serão salvos quando você criar a OS.
            </p>
          )}
        </div>

        {/* List of services as collapsible cards + add button */}
        {(() => {
          const persisted = (soServices || []) as any[];
          const drafts = isNew ? draftServices : [];
          const technicians = (appUsers || []).filter(
            (u: any) => u.role === 'technician' || u.role === 'admin'
          );

          // ServiceCardFormComponent is defined at module scope to preserve input focus.

          const renderCollapsedRow = (opts: {
            keyId: string;
            name: string;
            description?: string;
            unit: string;
            quantity: number;
            unitPrice: number;
            total: number;
            isDraft?: boolean;
            onExpand: () => void;
            onDelete: () => void;
            extra?: React.ReactNode;
          }) => (
            <div
              key={opts.keyId}
              className={`flex items-center gap-3 px-4 py-3 border-b last:border-0 ${
                opts.isDraft ? 'bg-amber-50/40' : ''
              }`}
            >
              <div className="flex-1 min-w-0">
                <div className="font-medium truncate">
                  {opts.name}
                  {opts.isDraft && (
                    <span className="ml-2 inline-flex items-center rounded-full bg-amber-100 px-2 py-0.5 text-[10px] font-medium text-amber-800">
                      rascunho
                    </span>
                  )}
                </div>
                {opts.description && (
                  <div className="text-xs text-muted-foreground truncate">
                    {opts.description}
                  </div>
                )}
              </div>
              <div className="hidden sm:block w-20 text-center text-xs text-muted-foreground">
                {BILLING_UNIT_LABELS[opts.unit] || opts.unit}
              </div>
              <div className="hidden sm:block w-16 text-center text-sm">
                {opts.quantity}
              </div>
              <div className="hidden md:block w-28 text-right text-sm">
                {formatCurrency(opts.unitPrice)}
              </div>
              <div className="w-28 text-right font-semibold">
                {formatCurrency(opts.total)}
              </div>
              {opts.extra}
              <Button
                variant="ghost"
                size="icon"
                className="h-8 w-8"
                onClick={opts.onExpand}
                title="Editar"
              >
                <Pencil className="h-3.5 w-3.5" />
              </Button>
              <Button
                variant="ghost"
                size="icon"
                className="h-8 w-8 text-destructive"
                onClick={opts.onDelete}
                title="Excluir"
              >
                <Trash2 className="h-3.5 w-3.5" />
              </Button>
            </div>
          );

          return (
            <div>
              {persisted.length === 0 && drafts.length === 0 && openNewSvcCards.length === 0 && (
                <p className="text-sm text-muted-foreground p-5">
                  {t.services.noServicesLinked}
                </p>
              )}

              {/* Header row labels */}
              {(persisted.length > 0 || drafts.length > 0) && (
                <div className="hidden sm:flex items-center gap-3 px-4 py-2 text-xs text-muted-foreground bg-muted/40 border-b">
                  <div className="flex-1">{t.services.serviceName}</div>
                  <div className="w-20 text-center">{t.services.billingUnit}</div>
                  <div className="w-16 text-center">{t.serviceOrders.qty}</div>
                  <div className="hidden md:block w-28 text-right">{t.serviceOrders.unitPrice}</div>
                  <div className="w-28 text-right">{t.common.total}</div>
                  <div className="w-16" />
                </div>
              )}

              {/* Persisted rows */}
              {persisted.map((s: any) => {
                const isEditing = !!editingSvc[s.id];
                if (isEditing) {
                  return (
                    <div key={s.id} className="border-b last:border-0">
                      <ServiceCardFormComponent
                        cardKey={s.id}
                        draft={editingSvc[s.id]}
                        services={services || []}
                        appUsers={appUsers || []}
                        formatCurrency={formatCurrency}
                        onUpdate={(patch) =>
                          setEditingSvc((prev) => ({
                            ...prev,
                            [s.id]: { ...prev[s.id], ...patch },
                          }))
                        }
                        onConfirm={() => handleConfirmEditSvc(s.id)}
                        onCancel={() => cancelSvcCard(s.id, false)}
                        confirmDisabled={updateSvcLine.isPending}
                      />
                    </div>
                  );
                }
                return renderCollapsedRow({
                  keyId: s.id,
                  name: s.name_snapshot,
                  description: s.description_snapshot,
                  unit: s.billing_unit_snapshot,
                  quantity: s.quantity,
                  unitPrice: s.unit_price_snapshot,
                  total: s.line_total,
                  onExpand: () => startEditPersisted(s),
                  onDelete: () =>
                    removeService.mutate({ id: s.id, service_order_id: orderId! }),
                  extra: orderId ? (
                    <ServiceTimer
                      serviceLineId={s.id}
                      serviceOrderId={orderId}
                      startedAt={s.started_at || null}
                      finishedAt={s.finished_at || null}
                      elapsedMinutes={s.elapsed_minutes || 0}
                      onUpdate={() =>
                        queryClient.invalidateQueries({ queryKey: ['so-services', orderId] })
                      }
                    />
                  ) : undefined,
                });
              })}

              {/* Draft rows (OS not saved yet) */}
              {drafts.map((d) =>
                renderCollapsedRow({
                  keyId: d.tempId,
                  name: d.name_snapshot,
                  description: d.description_snapshot,
                  unit: d.billing_unit_snapshot,
                  quantity: d.quantity,
                  unitPrice: d.unit_price_snapshot,
                  total: d.unit_price_snapshot * d.quantity,
                  isDraft: true,
                  onExpand: () => {
                    // Move draft into edit card and remove from drafts list
                    const key = `new-${d.tempId}`;
                    setEditingSvc((prev) => ({
                      ...prev,
                      [key]: {
                        service_id: d.service_id || '',
                        name_snapshot: d.name_snapshot,
                        description_snapshot: d.description_snapshot || '',
                        billing_unit_snapshot: d.billing_unit_snapshot,
                        quantity: d.quantity,
                        unit_price: d.unit_price_snapshot,
                        notes: d.notes || '',
                        technician_user_id: (d as any).technician_user_id || '',
                      },
                    }));
                    setOpenNewSvcCards((prev) => [...prev, key]);
                    setDraftServices((prev) => prev.filter((x) => x.tempId !== d.tempId));
                  },
                  onDelete: () =>
                    setDraftServices((prev) => prev.filter((x) => x.tempId !== d.tempId)),
                })
              )}

              {/* New (unsaved) cards */}
              {openNewSvcCards.map((key) => (
                <div key={key} className="border-b last:border-0">
                  <ServiceCardFormComponent
                    cardKey={key}
                    draft={editingSvc[key]}
                    services={services || []}
                    appUsers={appUsers || []}
                    formatCurrency={formatCurrency}
                    onUpdate={(patch) =>
                      setEditingSvc((prev) => ({
                        ...prev,
                        [key]: { ...prev[key], ...patch },
                      }))
                    }
                    onConfirm={() => handleConfirmNewSvcCard(key)}
                    onCancel={() => cancelSvcCard(key, true)}
                    confirmDisabled={addService.isPending}
                  />
                </div>
              ))}

              {/* Add button */}
              <div className="p-4 flex flex-wrap gap-2">
                <Button size="sm" variant="outline" onClick={addNewSvcCard}>
                  <Plus className="h-3.5 w-3.5 mr-1" /> Adicionar Serviço
                </Button>
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={() => setShowNewServiceDialog(true)}
                >
                  {t.services.registerNew}
                </Button>
              </div>
            </div>
          );
        })()}

        {/* Services subtotal bar */}
        {servicesItemCount > 0 && !isNew && (
          <div className="px-5 py-3 border-t bg-muted/30 flex items-center justify-between text-sm flex-wrap gap-2">
            <span className="text-muted-foreground">{servicesItemCount} {servicesItemCount === 1 ? 'serviço' : 'serviços'}{billableHours > 0 ? ` · ${billableHours.toFixed(1)}h faturáveis` : ''}</span>
            <span className="font-semibold">{formatCurrency(laborCost)}</span>
          </div>
        )}
      </section>

      {/* New Service Dialog */}
      <ServiceFormDialog open={showNewServiceDialog} onOpenChange={setShowNewServiceDialog} />

      {!isNew && (
        <Dialog open={showTravelDialog} onOpenChange={setShowTravelDialog}>
          <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
            <DialogHeader>
              <DialogTitle className="flex items-center gap-2">
                <MapPin className="h-4 w-4" /> Deslocamento
              </DialogTitle>
            </DialogHeader>
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <h2 className="font-semibold text-sm">{t.serviceOrders.travel}</h2>
                {marina?.latitude && (
                  <Button variant="outline" size="sm" onClick={runDisplacement} className="gap-1">
                    <RefreshCw className="h-3 w-3" />
                    {t.serviceOrders.recalculate}
                  </Button>
                )}
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 mt-3">
                <div>
                  <Label>Distância total (km ida+volta)</Label>
                  <Input type="number" min={0} step="0.1"
                    value={form.travel_distance_km}
                    onChange={(e) => {
                      const km = parseFloat(e.target.value) || 0;
                      set('travel_distance_km', km);
                      if (!manualTravel) {
                        set('travel_cost_total', calculateTravelCost({
                          distance_km: km,
                          travel_hours: form.travel_hours,
                          technician_count: form.technician_count_for_travel,
                          ferry_cost: form.ferry_cost,
                          travel_type: form.travel_type,
                        }));
                      }
                    }}
                  />
                </div>
                <div>
                  <Label>Tempo de deslocamento (horas)</Label>
                  <Input type="number" min={0} step="0.5"
                    value={form.travel_hours}
                    onChange={(e) => {
                      const hours = parseFloat(e.target.value) || 0;
                      set('travel_hours', hours);
                      if (!manualTravel) {
                        set('travel_cost_total', calculateTravelCost({
                          distance_km: form.travel_distance_km,
                          travel_hours: hours,
                          technician_count: form.technician_count_for_travel,
                          ferry_cost: form.ferry_cost,
                          travel_type: form.travel_type,
                        }));
                      }
                    }}
                  />
                </div>
                <div>
                  <Label>Técnicos no deslocamento</Label>
                  <Select
                    value={String(form.technician_count_for_travel)}
                    onValueChange={(v) => {
                      const count = parseInt(v) || 1;
                      set('technician_count_for_travel', count);
                      if (!manualTravel) {
                        set('travel_cost_total', calculateTravelCost({
                          distance_km: form.travel_distance_km,
                          travel_hours: form.travel_hours,
                          technician_count: count,
                          ferry_cost: form.ferry_cost,
                          travel_type: form.travel_type,
                        }));
                      }
                    }}
                  >
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="1">1 técnico — R$ 90,00/h</SelectItem>
                      <SelectItem value="2">2 técnicos — R$ 170,00/h</SelectItem>
                      <SelectItem value="3">3 técnicos — R$ 250,00/h</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div>
                  <Label>Tipo de atendimento</Label>
                  <Select
                    value={form.travel_type}
                    onValueChange={(v: any) => {
                      set('travel_type', v);
                      if (!manualTravel) {
                        set('travel_cost_total', calculateTravelCost({
                          distance_km: form.travel_distance_km,
                          travel_hours: form.travel_hours,
                          technician_count: form.technician_count_for_travel,
                          ferry_cost: form.ferry_cost,
                          travel_type: v,
                        }));
                      }
                    }}
                  >
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="comercial">Comercial (sem acréscimo)</SelectItem>
                      <SelectItem value="urgencia">Urgência fora do horário (+50%)</SelectItem>
                      <SelectItem value="fds_feriado">Final de semana / Feriado (+30%)</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
              </div>

              {/* Travessia de balsa */}
              <div className="mt-3 space-y-2">
                <div>
                  <Label>Valor da travessia de balsa / ferry (R$)</Label>
                  <MoneyInput
                    value={form.ferry_cost}
                    onValueChange={(v) => {
                      set('ferry_cost', v);
                      if (!manualTravel) {
                        set('travel_cost_total', calculateTravelCost({
                          distance_km: form.travel_distance_km,
                          travel_hours: form.travel_hours,
                          technician_count: form.technician_count_for_travel,
                          ferry_cost: v,
                          travel_type: form.travel_type,
                        }));
                      }
                    }}
                  />
                </div>
              </div>

              {/* Total calculado */}
              <div className="mt-4 flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <Label>Total deslocamento</Label>
                  <label className="flex items-center gap-1 text-xs text-muted-foreground">
                    <input type="checkbox" checked={manualTravel}
                      onChange={(e) => setManualTravel(e.target.checked)} />
                    Ajuste manual
                  </label>
                </div>
                {manualTravel ? (
                  <MoneyInput
                    value={form.travel_cost_total}
                    onValueChange={(v) => set('travel_cost_total', v)}
                  />
                ) : (
                  <span className="text-lg font-semibold">
                    {formatCurrency(form.travel_cost_total)}
                  </span>
                )}
              </div>

              {/* Breakdown do cálculo */}
              {!manualTravel && form.travel_cost_total > 0 && (
                <div className="mt-2 text-xs text-muted-foreground space-y-0.5">
                  <div>• Km: {form.travel_distance_km} km × R$ 1,10 = {formatCurrency(form.travel_distance_km * 1.10)}</div>
                  {form.travel_hours > 0 && (
                    <div>• Horas: {form.travel_hours}h × {formatCurrency(
                      form.technician_count_for_travel === 1 ? 90 :
                      form.technician_count_for_travel === 2 ? 170 : 250
                    )}/h = {formatCurrency(form.travel_hours * (
                      form.technician_count_for_travel === 1 ? 90 :
                      form.technician_count_for_travel === 2 ? 170 : 250
                    ))}</div>
                  )}
                  {form.ferry_cost > 0 && <div>• Balsa: {formatCurrency(form.ferry_cost)}</div>}
                  {form.travel_type !== 'comercial' && (
                    <div>• Acréscimo {form.travel_type === 'urgencia' ? '50% (urgência)' : '30% (FDS/feriado)'}</div>
                  )}
                </div>
              )}
            </div>
          </DialogContent>
        </Dialog>
      )}

      {/* F - Parts — always visible (with always-on entry row) */}
      <section className="rounded-xl border bg-card shadow-sm overflow-hidden">
        <div className="p-5 border-b">
          <h2 className="font-semibold text-sm">{t.serviceOrders.parts}</h2>
          {isNew && (
            <p className="text-xs text-muted-foreground mt-1">
              Itens adicionados aqui serão salvos quando você criar a OS.
            </p>
          )}
        </div>

        {/* List of parts as collapsible cards + add button */}
        {(() => {
          const persisted = (parts || []) as any[];
          const drafts = isNew ? draftParts : [];

          // PartCardFormComponent and PART_UNITS are defined at module scope to preserve input focus.

          const renderCollapsedPartRow = (opts: {
            keyId: string;
            name: string;
            unit?: string;
            quantity: number;
            unitPrice: number;
            total: number;
            isDraft?: boolean;
            image_url?: string | null;
            warranty_expires_at?: string | null;
            onExpand: () => void;
            onDelete: () => void;
          }) => (
            <div
              key={opts.keyId}
              className={`flex items-center gap-3 px-4 py-3 border-b last:border-0 ${
                opts.isDraft ? 'bg-amber-50/40' : ''
              }`}
            >
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  {opts.image_url ? (
                    <img
                      src={opts.image_url}
                      alt={opts.name}
                      className="h-8 w-8 rounded object-cover flex-shrink-0"
                    />
                  ) : (
                    <div className="h-8 w-8 rounded bg-muted flex items-center justify-center flex-shrink-0">
                      <Package className="h-4 w-4 text-muted-foreground" />
                    </div>
                  )}
                  <div>
                    <div className="font-medium text-sm">{opts.name}</div>
                    {opts.isDraft && (
                      <span className="inline-flex items-center rounded-full bg-amber-100 px-2 py-0.5 text-[10px] font-medium text-amber-800">
                        rascunho
                      </span>
                    )}
                    {opts.warranty_expires_at && new Date(opts.warranty_expires_at) > new Date() && (
                      <span className="ml-2 text-[10px] text-green-700 bg-green-100 rounded px-1">
                        Garantia até {new Date(opts.warranty_expires_at).toLocaleDateString('pt-BR')}
                      </span>
                    )}
                  </div>
                </div>
              </div>
              {opts.unit && (
                <div className="hidden sm:block w-16 text-center text-xs text-muted-foreground">
                  {opts.unit}
                </div>
              )}
              <div className="hidden sm:block w-16 text-center text-sm">
                {opts.quantity}
              </div>
              <div className="hidden md:block w-28 text-right text-sm">
                {formatCurrency(opts.unitPrice)}
              </div>
              <div className="w-28 text-right font-semibold">
                {formatCurrency(opts.total)}
              </div>
              <Button
                variant="ghost"
                size="icon"
                className="h-8 w-8"
                onClick={opts.onExpand}
                title="Editar"
              >
                <Pencil className="h-3.5 w-3.5" />
              </Button>
              <Button
                variant="ghost"
                size="icon"
                className="h-8 w-8 text-destructive"
                onClick={opts.onDelete}
                title="Excluir"
              >
                <Trash2 className="h-3.5 w-3.5" />
              </Button>
            </div>
          );

          return (
            <div>
              {persisted.length === 0 && drafts.length === 0 && openNewPartCards.length === 0 && (
                <p className="text-sm text-muted-foreground p-5">
                  {t.serviceOrders.noPartsYet}
                </p>
              )}

              {/* Header row labels */}
              {(persisted.length > 0 || drafts.length > 0) && (
                <div className="hidden sm:flex items-center gap-3 px-4 py-2 text-xs text-muted-foreground bg-muted/40 border-b">
                  <div className="flex-1">{t.serviceOrders.product}</div>
                  <div className="w-16 text-center">Un</div>
                  <div className="w-16 text-center">{t.serviceOrders.qty}</div>
                  <div className="hidden md:block w-28 text-right">{t.serviceOrders.unitPrice}</div>
                  <div className="w-28 text-right">{t.common.total}</div>
                  <div className="w-16" />
                </div>
              )}

              {/* Persisted rows */}
              {persisted.map((p: any) => {
                const isEditing = !!editingPart[p.id];
                if (isEditing) {
                  return (
                    <div key={p.id} className="border-b last:border-0">
                      <PartCardFormComponent
                        cardKey={p.id}
                        draft={editingPart[p.id]}
                        products={products || []}
                        formatCurrency={formatCurrency}
                        onUpdate={(patch) =>
                          setEditingPart((prev) => ({
                            ...prev,
                            [p.id]: { ...prev[p.id], ...patch },
                          }))
                        }
                        onConfirm={() => handleConfirmEditPart(p.id, p)}
                        onCancel={() => cancelPartCard(p.id, false)}
                        onOpenPriceCalc={() => setPriceCalcCardKey(p.id)}
                        confirmDisabled={updatePartLine.isPending}
                        supabase={supabase}
                      />
                    </div>
                  );
                }
                return renderCollapsedPartRow({
                  keyId: p.id,
                  name: p.products?.name || 'Produto',
                  unit: p.products?.unit,
                  quantity: p.quantity,
                  unitPrice: p.unit_sale_snapshot,
                  total: p.line_total_sale,
                  image_url: p.products?.image_url || null,
                  warranty_expires_at: p.warranty_expires_at || null,
                  onExpand: () => startEditPersistedPart(p),
                  onDelete: () =>
                    removePart.mutate({
                      id: p.id,
                      service_order_id: orderId!,
                      product_id: p.product_id,
                      quantity: p.quantity,
                      unit_cost_snapshot: p.unit_cost_snapshot,
                    }),
                });
              })}

              {/* Draft rows (OS not saved yet) */}
              {drafts.map((d) =>
                renderCollapsedPartRow({
                  keyId: d.tempId,
                  name: d.name,
                  quantity: d.quantity,
                  unitPrice: d.unit_sale,
                  total: d.unit_sale * d.quantity,
                  isDraft: true,
                  image_url: (products?.find(pr => pr.id === d.product_id) as any)?.image_url || null,
                  onExpand: () => {
                    const key = `new-${d.tempId}`;
                    const prod = products?.find((p) => p.id === d.product_id);
                    setEditingPart((prev) => ({
                      ...prev,
                      [key]: {
                        product_id: d.product_id,
                        name: d.name,
                        unit: prod?.unit || 'un',
                        quantity: d.quantity,
                        unit_cost: d.unit_cost,
                        unit_sale: d.unit_sale,
                        notes: '',
                      },
                    }));
                    setOpenNewPartCards((prev) => [...prev, key]);
                    setDraftParts((prev) => prev.filter((x) => x.tempId !== d.tempId));
                  },
                  onDelete: () =>
                    setDraftParts((prev) => prev.filter((x) => x.tempId !== d.tempId)),
                })
              )}

              {/* New (unsaved) cards */}
              {openNewPartCards.map((key) => (
                <div key={key} className="border-b last:border-0">
                  <PartCardFormComponent
                    cardKey={key}
                    draft={editingPart[key]}
                    products={products || []}
                    formatCurrency={formatCurrency}
                    onUpdate={(patch) =>
                      setEditingPart((prev) => ({
                        ...prev,
                        [key]: { ...prev[key], ...patch },
                      }))
                    }
                    onConfirm={() => handleConfirmNewPartCard(key)}
                    onCancel={() => cancelPartCard(key, true)}
                    onOpenPriceCalc={() => setPriceCalcCardKey(key)}
                    confirmDisabled={addPart.isPending}
                    supabase={supabase}
                  />
                </div>
              ))}

              {/* Add button */}
              <div className="p-4">
                <Button size="sm" variant="outline" onClick={addNewPartCard}>
                  <Plus className="h-3.5 w-3.5 mr-1" /> Adicionar Peça
                </Button>
              </div>
            </div>
          );
        })()}

        {/* Parts subtotal + profit bar (edit-mode only) */}
        {partsItemCount > 0 && !isNew && (
          <div className="px-5 py-3 border-t bg-muted/30 flex items-center justify-between text-sm flex-wrap gap-2">
            <div className="flex items-center gap-4 flex-wrap">
              <span className="text-muted-foreground">{partsItemCount} {partsItemCount === 1 ? 'peça' : 'peças'}</span>
              {partsProfit !== 0 && (
                <span className={partsProfit >= 0 ? 'text-emerald-600 text-xs' : 'text-red-600 text-xs'}>
                  Lucro peças: {partsProfit >= 0 ? '+' : ''}{formatCurrency(partsProfit)}
                  {partsRevenue > 0 && ` (${partsMarginPct.toFixed(1)}%)`}
                </span>
              )}
            </div>
            <span className="font-semibold">{formatCurrency(partsRevenue)}</span>
          </div>
        )}
      </section>

      {!isNew && (
        <Dialog open={showExpensesDialog} onOpenChange={setShowExpensesDialog}>
          <DialogContent className="max-w-3xl max-h-[90vh] overflow-y-auto">
            <DialogHeader>
              <DialogTitle className="flex items-center gap-2">
                <Receipt className="h-4 w-4" /> Despesas Operacionais
              </DialogTitle>
            </DialogHeader>
            <div className="space-y-0">
              <div className="flex items-center justify-between pb-3">
                <h2 className="font-semibold text-sm">{t.serviceOrders.operationalExpenses}</h2>
                <Button variant="outline" size="sm" className="gap-1" onClick={() => setShowExpForm(!showExpForm)}>
                  <Plus className="h-3 w-3" /> {t.serviceOrders.addExpense}
                </Button>
              </div>
              {showExpForm && (
                <div className="p-4 border rounded-lg bg-muted/30 space-y-3 mb-3">
                  <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                    <div>
                      <Label>{t.products.category}</Label>
                      <Select value={expForm.category} onValueChange={(v) => setExpForm({ ...expForm, category: v })}>
                        <SelectTrigger><SelectValue placeholder={t.products.category} /></SelectTrigger>
                        <SelectContent>
                          {OPERATIONAL_EXPENSE_CATEGORIES.map((c) => (
                            <SelectItem key={c} value={c}>{c}</SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                    <div>
                      <Label>{t.serviceOrders.expenseDate}</Label>
                      <Input type="date" value={expForm.expense_date} onChange={(e) => setExpForm({ ...expForm, expense_date: e.target.value })} />
                    </div>
                    <div>
                      <Label>{t.common.amount}</Label>
                      <MoneyInput value={expForm.amount}
                        onValueChange={(v) => setExpForm({ ...expForm, amount: v })} />
                    </div>
                  </div>
                  <div>
                    <Label>{t.common.description}</Label>
                    <Input value={expForm.description} onChange={(e) => setExpForm({ ...expForm, description: e.target.value })} />
                  </div>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <div>
                      <Label>{t.serviceOrders.paidBy}</Label>
                      <Select value={expForm.paid_by} onValueChange={(v: 'company' | 'technician') => setExpForm({ ...expForm, paid_by: v })}>
                        <SelectTrigger><SelectValue /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="company">{t.serviceOrders.paidByCompany}</SelectItem>
                          <SelectItem value="technician">{t.serviceOrders.paidByTechnician}</SelectItem>
                        </SelectContent>
                      </Select>
                    </div>
                    {expForm.paid_by === 'technician' && (
                      <div>
                        <Label>{t.serviceOrders.technicians}</Label>
                        <Select value={expForm.technician_user_id} onValueChange={(v) => setExpForm({ ...expForm, technician_user_id: v })}>
                          <SelectTrigger><SelectValue placeholder={t.serviceOrders.technicians} /></SelectTrigger>
                          <SelectContent>
                            {appUsers?.map((u) => (
                              <SelectItem key={u.id} value={u.id}>{u.full_name}</SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                        <p className="text-xs text-warning mt-1">{t.serviceOrders.pendingReimbursement}</p>
                      </div>
                    )}
                  </div>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <div>
                      <Label>Comprovante</Label>
                      <input
                        ref={receiptInputRef}
                        type="file"
                        accept="image/*,application/pdf"
                        capture="environment"
                        className="hidden"
                        onChange={(e) => {
                          const f = e.target.files?.[0];
                          if (f) handleUploadReceipt(f);
                        }}
                      />
                      {expForm.receipt_url ? (
                        <div className="flex items-center gap-2 mt-1 p-2 rounded-md border bg-background">
                          {/\.(png|jpe?g|gif|webp|svg)$/i.test(expForm.receipt_url) ? (
                            <img
                              src={expForm.receipt_url}
                              alt="Comprovante"
                              className="h-[60px] w-[60px] object-cover rounded border"
                            />
                          ) : (
                            <div className="h-[60px] w-[60px] flex items-center justify-center rounded border bg-muted">
                              <FileText className="h-6 w-6 text-muted-foreground" />
                            </div>
                          )}
                          <a
                            href={expForm.receipt_url}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="text-xs text-primary hover:underline truncate flex-1"
                          >
                            Ver comprovante
                          </a>
                          <Button
                            type="button"
                            variant="ghost"
                            size="icon"
                            className="h-7 w-7"
                            onClick={handleRemoveReceipt}
                          >
                            <X className="h-3.5 w-3.5" />
                          </Button>
                        </div>
                      ) : (
                        <Button
                          type="button"
                          variant="outline"
                          size="sm"
                          className="w-full gap-2 mt-1"
                          onClick={() => receiptInputRef.current?.click()}
                          disabled={uploadingReceipt}
                        >
                          <Paperclip className="h-3.5 w-3.5" />
                          {uploadingReceipt ? 'Enviando...' : '📎 Anexar comprovante'}
                        </Button>
                      )}
                    </div>
                    <div>
                      <Label>{t.common.notes}</Label>
                      <Input value={expForm.notes} onChange={(e) => setExpForm({ ...expForm, notes: e.target.value })} />
                    </div>
                  </div>
                  <div>
                    <Label>Fornecedor</Label>
                    <EntityCombobox
                      value={expForm.supplier_id}
                      onChange={(v) => setExpForm({ ...expForm, supplier_id: v })}
                      options={(suppliers || []).filter((s) => s.active).map((s) => ({
                        value: s.id,
                        label: s.name,
                        description: s.cnpj_cpf || undefined,
                      }))}
                      placeholder="—"
                      onCreate={(typed) => {
                        setQuickSupplierName(typed);
                        setQuickSupplierOpen(true);
                      }}
                      createLabel="+ Cadastrar novo fornecedor"
                    />
                  </div>
                  {!editingExpenseId && (
                    <label className="flex items-center gap-2 text-sm cursor-pointer">
                      <input type="checkbox" checked={expForm.also_create_payable}
                        onChange={(e) => setExpForm({ ...expForm, also_create_payable: e.target.checked })} />
                      {t.serviceOrders.alsoCreatePayable}
                    </label>
                  )}
                  <div className="flex gap-2">
                    <Button size="sm" onClick={handleAddExpense} disabled={addExpense.isPending || updateExpense.isPending}>
                      {editingExpenseId ? 'Atualizar' : t.common.save}
                    </Button>
                    <Button size="sm" variant="outline" onClick={() => { resetExpForm(); setShowExpForm(false); }}>
                      {t.common.cancel}
                    </Button>
                  </div>
                </div>
              )}
              {(!soExpenses || soExpenses.length === 0) ? (
                <p className="text-sm text-muted-foreground p-5">{t.serviceOrders.noExpensesYet}</p>
              ) : (
                <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b bg-muted/50">
                      <th className="px-4 py-2 text-left font-medium text-muted-foreground">{t.common.date}</th>
                      <th className="px-4 py-2 text-left font-medium text-muted-foreground">{t.products.category}</th>
                      <th className="px-4 py-2 text-left font-medium text-muted-foreground">{t.common.description}</th>
                      <th className="px-4 py-2 text-left font-medium text-muted-foreground hidden sm:table-cell">Fornecedor</th>
                      <th className="px-4 py-2 text-left font-medium text-muted-foreground hidden sm:table-cell">{t.serviceOrders.paidBy}</th>
                      <th className="px-4 py-2 text-center font-medium text-muted-foreground hidden md:table-cell">Comprovante</th>
                      <th className="px-4 py-2 text-right font-medium text-muted-foreground">{t.common.amount}</th>
                      <th className="px-4 py-2 w-20"></th>
                    </tr>
                  </thead>
                  <tbody>
                    {soExpenses.map((exp: any) => (
                      <tr key={exp.id} className="border-b last:border-0">
                        <td className="px-4 py-3 text-muted-foreground">{formatDate(exp.expense_date)}</td>
                        <td className="px-4 py-3"><StatusBadge className="bg-secondary text-secondary-foreground">{exp.category}</StatusBadge></td>
                        <td className="px-4 py-3 font-medium">{exp.description}</td>
                        <td className="px-4 py-3 text-muted-foreground hidden sm:table-cell">
                          {exp.suppliers?.name || '—'}
                        </td>
                        <td className="px-4 py-3 hidden sm:table-cell">
                          {exp.paid_by === 'technician' ? (
                            <span className="text-warning">{exp.app_users?.full_name || t.serviceOrders.paidByTechnician}
                              {!exp.reimbursed && <StatusBadge className="bg-warning/15 text-warning ml-1">{t.serviceOrders.pendingReimbursement}</StatusBadge>}
                              {exp.reimbursed && <StatusBadge className="bg-success/15 text-success ml-1">{t.serviceOrders.reimbursed}</StatusBadge>}
                            </span>
                          ) : t.serviceOrders.paidByCompany}
                        </td>
                        <td className="px-4 py-3 text-center hidden md:table-cell">
                          {exp.receipt_url ? (
                            /\.(png|jpe?g|gif|webp|svg)$/i.test(exp.receipt_url) ? (
                              <a href={exp.receipt_url} target="_blank" rel="noopener noreferrer" className="inline-block">
                                <img src={exp.receipt_url} alt="Comprovante" className="h-8 w-8 object-cover rounded border inline-block" />
                              </a>
                            ) : (
                              <a href={exp.receipt_url} target="_blank" rel="noopener noreferrer" className="text-primary inline-flex items-center gap-1 hover:underline">
                                <FileImage className="h-4 w-4" />
                                <ExternalLink className="h-3 w-3" />
                              </a>
                            )
                          ) : (
                            <span className="text-muted-foreground">—</span>
                          )}
                        </td>
                        <td className="px-4 py-3 text-right font-semibold">{formatCurrency(Number(exp.amount))}</td>
                        <td className="px-4 py-3">
                          <div className="flex items-center justify-end gap-1">
                            <Button variant="ghost" size="icon" className="h-7 w-7"
                              onClick={() => handleEditExpense(exp)}>
                              <Pencil className="h-3.5 w-3.5" />
                            </Button>
                            <Button variant="ghost" size="icon" className="h-7 w-7 text-destructive"
                              onClick={() => removeExpense.mutate({ id: exp.id, service_order_id: orderId! })}>
                              <Trash2 className="h-3.5 w-3.5" />
                            </Button>
                          </div>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
                </div>
              )}
            </div>
          </DialogContent>
        </Dialog>
      )}

      {!isNew && (
        <Dialog open={showTimeDialog} onOpenChange={setShowTimeDialog}>
          <DialogContent className="max-w-3xl max-h-[90vh] overflow-y-auto">
            <DialogHeader>
              <DialogTitle className="flex items-center gap-2">
                <Clock className="h-4 w-4" /> Controle de Horas
              </DialogTitle>
            </DialogHeader>
            <div className="space-y-0">
              <div className="flex items-center justify-between pb-3">
                <div>
                  <h2 className="font-semibold text-sm">{t.services.timeSection}</h2>
                  <p className="text-xs text-muted-foreground mt-0.5">{t.services.timeNote}</p>
                </div>
                <Button variant="outline" size="sm" className="gap-1" onClick={() => setShowTimeForm(!showTimeForm)}>
                  <Plus className="h-3 w-3" /> {t.serviceOrders.addTimeEntry}
                </Button>
              </div>
              {showTimeForm && (
                <div className="p-4 border rounded-lg bg-muted/30 space-y-3 mb-3">
                  <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                    <div>
                      <Label>{t.serviceOrders.technicians}</Label>
                      <Select value={timeForm.technician_user_id}
                        onValueChange={(v) => setTimeForm({ ...timeForm, technician_user_id: v })}>
                        <SelectTrigger><SelectValue placeholder="Selecionar técnico" /></SelectTrigger>
                        <SelectContent>
                          {appUsers?.map((u) => (
                            <SelectItem key={u.id} value={u.id}>{u.full_name}</SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                    <div>
                      <Label>{t.serviceOrders.scheduledStart}</Label>
                      <Input type="datetime-local" value={timeForm.started_at}
                        onChange={(e) => setTimeForm({ ...timeForm, started_at: e.target.value })} />
                    </div>
                    <div>
                      <Label>{t.serviceOrders.scheduledEnd}</Label>
                      <Input type="datetime-local" value={timeForm.ended_at}
                        onChange={(e) => setTimeForm({ ...timeForm, ended_at: e.target.value })} />
                    </div>
                  </div>
                  <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                    <div>
                      <Label>Duração (min)</Label>
                      <Input type="number" value={timeForm.duration_minutes}
                        onChange={(e) => setTimeForm({ ...timeForm, duration_minutes: parseInt(e.target.value) || 0 })} />
                    </div>
                    <div className="flex items-end gap-2">
                      <label className="flex items-center gap-1.5 text-sm">
                        <Switch checked={timeForm.billable}
                          onCheckedChange={(v) => setTimeForm({ ...timeForm, billable: v })} />
                        {t.serviceOrders.billable}
                      </label>
                    </div>
                    <div>
                      <Label>{t.common.notes}</Label>
                      <Input value={timeForm.notes}
                        onChange={(e) => setTimeForm({ ...timeForm, notes: e.target.value })} />
                    </div>
                  </div>
                  <div className="flex gap-2">
                    <Button size="sm" onClick={handleAddTime} disabled={addTime.isPending}>{t.common.save}</Button>
                    <Button size="sm" variant="outline" onClick={() => setShowTimeForm(false)}>{t.common.cancel}</Button>
                  </div>
                </div>
              )}
              {(!timeEntries || timeEntries.length === 0) ? (
                <p className="text-sm text-muted-foreground p-5">{t.serviceOrders.noTimeEntries}</p>
              ) : (
                <div className="divide-y">
                  {timeEntries.map((te: any) => (
                    <div key={te.id} className="flex items-start justify-between p-4">
                      <div>
                        <p className="text-sm font-medium">{te.app_users?.full_name}</p>
                        {te.notes && <p className="text-xs text-muted-foreground">{te.notes}</p>}
                        <p className="text-xs text-muted-foreground mt-1">
                          {formatDateTime(te.started_at)} → {te.ended_at ? formatDateTime(te.ended_at) : '...'}
                        </p>
                      </div>
                      <div className="flex items-center gap-3">
                        <div className="text-right">
                          <p className="text-sm font-semibold">{((te.duration_minutes || 0) / 60).toFixed(1)}h</p>
                          <StatusBadge className={te.billable ? 'bg-success/15 text-success' : 'bg-muted text-muted-foreground'}>
                            {te.billable ? t.serviceOrders.billable : t.serviceOrders.nonBillable}
                          </StatusBadge>
                        </div>
                        <Button variant="ghost" size="icon" className="h-7 w-7 text-destructive"
                          onClick={() => removeTime.mutate({ id: te.id, service_order_id: orderId! })}>
                          <Trash2 className="h-3.5 w-3.5" />
                        </Button>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </DialogContent>
        </Dialog>
      )}

      {/* G - Linked Purchase Orders */}
      {!isNew && orderId && linkedPOs && linkedPOs.length > 0 && (
        <section className="rounded-xl border bg-card shadow-sm overflow-hidden">
          <div className="p-4 border-b flex items-center justify-between">
            <h2 className="font-semibold text-sm flex items-center gap-2">
              <Package className="h-4 w-4 text-muted-foreground" />
              Compras vinculadas ({linkedPOs.length})
            </h2>
          </div>
          <div className="divide-y">
            {linkedPOs.map(po => {
              const totalItems = (po.purchase_order_items ?? []).length;
              const isReceived = po.status === 'received';
              const isCancelled = po.status === 'cancelled';
              const statusColors: Record<string, string> = {
                draft: 'bg-muted text-muted-foreground',
                sent: 'bg-blue-100 text-blue-700',
                partial: 'bg-amber-100 text-amber-700',
                received: 'bg-green-100 text-green-700',
                cancelled: 'bg-red-100 text-red-600 line-through',
              };
              const statusLabels: Record<string, string> = {
                draft: 'Rascunho', sent: 'Enviada', partial: 'Parcial', received: 'Recebida', cancelled: 'Cancelada',
              };
              const estimatedDate = po.expected_date
                ? new Date(po.expected_date + 'T12:00:00').toLocaleDateString('pt-BR')
                : null;
              return (
                <div key={po.id} className="px-4 py-3 flex items-center justify-between gap-3 flex-wrap">
                  <div className="space-y-0.5 min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="font-medium text-sm">{po.po_number}</span>
                      <span className={"inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium " + (statusColors[po.status] || 'bg-muted text-muted-foreground')}>
                        {statusLabels[po.status] ?? po.status}
                      </span>
                    </div>
                    <p className="text-xs text-muted-foreground">
                      {po.suppliers?.name ?? 'Fornecedor não definido'}
                      {totalItems > 0 && " · " + totalItems + (totalItems === 1 ? ' item' : ' itens')}
                      {estimatedDate && !isReceived && " · Previsão: " + estimatedDate}
                      {po.total_amount > 0 && " · " + formatCurrency(po.total_amount)}
                    </p>
                  </div>
                  <div className="flex gap-2 shrink-0">
                    {!isReceived && !isCancelled && (
                      <Button size="sm" variant="outline"
                        className="h-7 text-xs gap-1 text-green-700 border-green-300 hover:bg-green-50"
                        onClick={() => setReceivePOTarget(po)}>
                        <PackagePlus className="h-3.5 w-3.5" /> Registrar recebimento
                      </Button>
                    )}
                    {po.status === 'draft' && (
                      <Button size="sm" variant="ghost"
                        className="h-7 text-xs gap-1 text-blue-700"
                        onClick={() => updatePO.mutateAsync({ id: po.id, status: 'sent' })}>
                        Marcar como enviada
                      </Button>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        </section>
      )}

      {/* H - Financial Mini-Summary */}
      <div className="rounded-xl border bg-card shadow-sm overflow-hidden">
        {/* Row 1: line items */}
        <div className="px-4 pt-4 pb-2 flex items-center justify-between gap-4 flex-wrap">
          <div className="flex items-center gap-5 text-sm flex-wrap">
            {laborCost > 0 && (
              <span className="text-muted-foreground">
                Serviços: <span className="font-semibold text-foreground">{formatCurrency(laborCost)}</span>
              </span>
            )}
            {partsCost > 0 && (
              <span className="text-muted-foreground">
                Peças: <span className="font-semibold text-foreground">{formatCurrency(partsCost)}</span>
              </span>
            )}
            {(form.travel_cost_total || 0) > 0 && (
              <span className="text-muted-foreground">
                Desl.: <span className="font-semibold text-foreground">{formatCurrency(form.travel_cost_total)}</span>
              </span>
            )}
            {(form.discount_amount || 0) > 0 && (
              <span className="text-red-600 text-xs">
                Desconto: −{formatCurrency(form.discount_amount || 0)}
              </span>
            )}
          </div>
          <div className="flex flex-col items-end">
            <span className="font-bold text-lg text-accent">
              {formatCurrency(grandTotal)}
            </span>
            {/* M6: Valor orçado vs realizado — exibe variação quando há diferença */}
            {(orderData as any)?.original_quote_amount > 0 &&
              Math.abs(grandTotal - (orderData as any).original_quote_amount) > 0.01 && (
              <span className="text-[10px] text-muted-foreground">
                orçado {formatCurrency((orderData as any).original_quote_amount)}{' '}
                <span className={grandTotal > (orderData as any).original_quote_amount
                  ? 'text-destructive font-medium'
                  : 'text-emerald-600 font-medium'}>
                  {grandTotal > (orderData as any).original_quote_amount ? '+' : ''}
                  {formatCurrency(grandTotal - (orderData as any).original_quote_amount)}
                </span>
              </span>
            )}
          </div>
        </div>

        {/* Row 2: composition % + parts profit (edit-mode only) */}
        {!isNew && (subtotal > 0 || partsRevenue > 0) && (
          <div className="px-4 py-1.5 border-t bg-muted/20 flex items-center gap-4 text-xs text-muted-foreground flex-wrap">
            {laborCost > 0 && subtotal > 0 && (
              <span>Serviços: {((laborCost / subtotal) * 100).toFixed(0)}%</span>
            )}
            {partsCost > 0 && subtotal > 0 && (
              <span>Peças: {((partsCost / subtotal) * 100).toFixed(0)}%</span>
            )}
            {partsRevenue > 0 && (
              <span className={`ml-auto font-medium ${partsProfit >= 0 ? 'text-emerald-600' : 'text-red-600'}`}>
                Lucro peças: {partsProfit >= 0 ? '+' : ''}{formatCurrency(partsProfit)} ({partsMarginPct.toFixed(1)}%)
              </span>
            )}
          </div>
        )}

        {/* M1: Resumo de recebíveis reais — só exibe se existem recebíveis */}
        {!isNew && (soReceivables || []).length > 0 && (
          <div className="px-4 py-2 border-t bg-blue-50/40 dark:bg-blue-950/20 flex items-center gap-4 flex-wrap text-xs">
            <span className="text-muted-foreground">
              Cobrado: <span className="font-semibold text-foreground">{formatCurrency(soTotalCharged)}</span>
            </span>
            <span className="text-muted-foreground">
              Recebido: <span className="font-semibold text-emerald-600">{formatCurrency(soTotalPaid)}</span>
            </span>
            {soBalance > 0.01 && (
              <span className="text-muted-foreground">
                Em aberto: <span className="font-semibold text-destructive">{formatCurrency(soBalance)}</span>
              </span>
            )}
            <span className={`ml-auto inline-flex items-center px-2 py-0.5 rounded-full text-[10px] font-semibold ${
              soPayStatus === 'paid'           ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-900/40'
              : soPayStatus === 'partially_paid' ? 'bg-amber-100 text-amber-700 dark:bg-amber-900/40'
              : 'bg-muted text-muted-foreground'
            }`}>
              {soPayStatus === 'paid' ? 'Quitado' : soPayStatus === 'partially_paid' ? 'Parcial' : 'Pendente'}
            </span>
          </div>
        )}

        {/* M2: Histórico de pagamentos — colapsável */}
        {!isNew && (soPayments || []).length > 0 && (
          <div className="border-t">
            <button
              type="button"
              className="w-full flex items-center justify-between px-4 py-2 text-xs text-muted-foreground hover:bg-muted/30 transition-colors"
              onClick={() => setShowPaymentHistory(v => !v)}
            >
              <span className="flex items-center gap-1.5">
                <Receipt className="h-3.5 w-3.5" />
                Histórico de pagamentos ({soPayments.length})
              </span>
              <ChevronDown className={`h-3.5 w-3.5 transition-transform ${showPaymentHistory ? 'rotate-180' : ''}`} />
            </button>
            {showPaymentHistory && (
              <div className="px-4 pb-3 space-y-0.5">
                {(soPayments || []).map((p: any) => (
                  <div key={p.id} className="grid grid-cols-[80px_1fr_auto] gap-2 items-center text-xs py-1.5 border-b border-dashed last:border-0">
                    <span className="text-muted-foreground tabular-nums">
                      {new Date(p.payment_date + 'T12:00:00').toLocaleDateString('pt-BR')}
                    </span>
                    <span className="text-muted-foreground truncate capitalize">
                      {(p.payment_method || '—').replace(/_/g, ' ')}
                      {p.installments > 1 ? ` ${p.installments}x` : ''}
                    </span>
                    <span className="font-semibold text-emerald-600 tabular-nums">
                      {formatCurrency(Number(p.net_amount || p.amount))}
                    </span>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}

        {/* Row 3: action buttons */}
        <div className="px-4 py-2 border-t flex items-center gap-2 flex-wrap">
          {!isNew && (
            <>
              <Button variant="ghost" size="sm" className="gap-1 text-xs h-7" onClick={() => setShowTravelDialog(true)}>
                <MapPin className="h-3 w-3" /> Deslocamento
              </Button>
              <Button variant="ghost" size="sm" className="gap-1 text-xs h-7" onClick={() => setShowExpensesDialog(true)}>
                <Receipt className="h-3 w-3" /> Despesas
              </Button>
              <Button variant="ghost" size="sm" className="gap-1 text-xs h-7" onClick={() => setShowTimeDialog(true)}>
                <Clock className="h-3 w-3" /> Horas
              </Button>
            </>
          )}
          <Button
            variant="outline"
            size="sm"
            className="gap-1.5 text-xs h-7 ml-auto"
            onClick={() => setShowFinancialDialog(true)}
          >
            <Calculator className="h-3.5 w-3.5" />
            Composição Financeira
            {/* M5: dot indicator quando financial_notes está preenchido */}
            {form.financial_notes?.trim() && (
              <span className="h-2 w-2 rounded-full bg-amber-400 ml-0.5 animate-pulse" title="Observações financeiras preenchidas" />
            )}
          </Button>
        </div>
      </div>

      {/* Financial Dialog — reorganized */}
      <Dialog open={showFinancialDialog} onOpenChange={setShowFinancialDialog}>
        <DialogContent className="max-w-2xl max-h-[92vh] flex flex-col p-0 gap-0">
          {/* Sticky header */}
          <div className="px-6 pt-5 pb-3 border-b">
            <DialogTitle className="flex items-center gap-2 text-base">
              <Calculator className="h-4 w-4" /> Composição Financeira
            </DialogTitle>
          </div>

          {/* Scrollable body */}
          <div className="overflow-y-auto flex-1 px-6 py-4 space-y-5">

            {/* ── SECTION 1: CUSTOS ── */}
            <div className="space-y-2">
              <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide flex items-center gap-1.5">
                <Receipt className="h-3.5 w-3.5" /> Custos
              </p>
              <div className="rounded-lg border bg-muted/20 divide-y text-sm">
                {[
                  { label: t.serviceOrders.labor,           value: laborCost },
                  { label: t.serviceOrders.parts,           value: partsCost },
                  { label: t.serviceOrders.operationalCost, value: operationalCost },
                  { label: t.serviceOrders.travel,          value: form.travel_cost_total },
                ].map(({ label, value }) => (
                  <div key={label} className="flex justify-between px-3 py-1.5">
                    <span className="text-muted-foreground">{label}</span>
                    <span className={value > 0 ? 'font-medium' : 'text-muted-foreground/50'}>{formatCurrency(value || 0)}</span>
                  </div>
                ))}
                <div className="flex justify-between px-3 py-1.5 items-center">
                  <span className="text-muted-foreground">{t.serviceOrders.subcontract}</span>
                  <MoneyInput className="w-28 h-7 text-right text-sm" value={form.subcontract_cost_total}
                    onValueChange={(v) => set('subcontract_cost_total', v)} disabled={isLocked} />
                </div>
                <div className="flex justify-between px-3 py-2 bg-muted/40 rounded-b-lg font-medium">
                  <span>Subtotal</span>
                  <span>{formatCurrency(subtotal)}</span>
                </div>
              </div>
            </div>

            {/* ── SECTION 2: AJUSTES ── */}
            <div className="space-y-2">
              <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide flex items-center gap-1.5">
                <Tag className="h-3.5 w-3.5" /> Ajustes
              </p>
              <div className="rounded-lg border bg-muted/20 p-3 space-y-3 text-sm">
                {/* Discount */}
                <div className="space-y-2">
                  <p className="text-xs text-muted-foreground font-medium">Desconto</p>
                  <div className="grid grid-cols-2 gap-2">
                    <div className="space-y-1">
                      <Label className="text-xs text-muted-foreground">↳ Serviços (%)</Label>
                      <div className="flex items-center gap-1.5">
                        <Input type="number" min="0" max="100" step="0.5"
                          className="w-16 h-7 text-right text-xs" value={discountServicesPct || ''}
                          placeholder="0" disabled={isLocked}
                          onChange={e => {
                            const pct = Math.max(0, Math.min(100, parseFloat(e.target.value) || 0));
                            setDiscountServicesPct(pct);
                            set('discount_amount', Math.round((laborCost * pct / 100 + partsCost * discountPartsPct / 100) * 100) / 100);
                          }} />
                        <span className="text-xs text-muted-foreground">{formatCurrency(laborCost * discountServicesPct / 100)}</span>
                      </div>
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs text-muted-foreground">↳ Peças (%)</Label>
                      <div className="flex items-center gap-1.5">
                        <Input type="number" min="0" max="100" step="0.5"
                          className="w-16 h-7 text-right text-xs" value={discountPartsPct || ''}
                          placeholder="0" disabled={isLocked}
                          onChange={e => {
                            const pct = Math.max(0, Math.min(100, parseFloat(e.target.value) || 0));
                            setDiscountPartsPct(pct);
                            set('discount_amount', Math.round((laborCost * discountServicesPct / 100 + partsCost * pct / 100) * 100) / 100);
                          }} />
                        <span className="text-xs text-muted-foreground">{formatCurrency(partsCost * discountPartsPct / 100)}</span>
                      </div>
                    </div>
                  </div>
                  <div className="flex items-center justify-between pt-1 border-t border-dashed">
                    <Label className="text-xs font-medium text-destructive">Total desconto</Label>
                    <MoneyInput className="w-28 h-7 text-right text-sm text-destructive font-medium"
                      value={form.discount_amount}
                      onValueChange={v => {
                        set('discount_amount', v);
                        if (!v) { setDiscountServicesPct(0); setDiscountPartsPct(0); }
                        else {
                          const base = laborCost + partsCost;
                          if (base > 0) {
                            setDiscountServicesPct(Math.min(100, Math.round((v * (laborCost / base) / laborCost) * 1000) / 10));
                            setDiscountPartsPct(Math.min(100, Math.round((v * (partsCost / base) / partsCost) * 1000) / 10));
                          }
                        }
                      }} disabled={isLocked} />
                  </div>
                </div>

                {/* Tax */}
                <div className="flex items-center justify-between pt-2 border-t border-dashed">
                  <Label className="text-sm">{t.serviceOrders.tax}</Label>
                  <MoneyInput className="w-28 h-7 text-right text-sm" value={form.tax_amount}
                    onValueChange={v => set('tax_amount', v)} disabled={isLocked} />
                </div>

                {/* Margin warning */}
                {grandTotal > 0 && subtotal > 0 && (grandTotal / subtotal) < 0.85 && (
                  <div className="flex items-center gap-2 text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded px-2 py-1.5">
                    <AlertTriangle className="h-3.5 w-3.5 shrink-0" />
                    Desconto alto — margem reduzida a {(((grandTotal - subtotal) / subtotal) * 100).toFixed(1)}%
                  </div>
                )}
              </div>
            </div>

            {/* ── SECTION 3: CONDIÇÕES DE RECEBIMENTO ── */}
            <div className="space-y-2">
              <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide flex items-center gap-1.5">
                <CreditCard className="h-3.5 w-3.5" /> Condições de Recebimento
              </p>
              <div className="rounded-lg border bg-muted/20 p-3 space-y-3">
                <div className="flex gap-2 items-center">
                  <Select key={presetKey} onValueChange={v => {
                    const preset = (paymentPresets || []).find((p: any) => p.label === v);
                    set('payment_conditions', v);
                    set('payment_condition_preset_id', preset?.id || '');
                    setPresetKey(k => k + 1);
                  }} disabled={isLocked}>
                    <SelectTrigger className="w-44 h-8 text-sm">
                      <SelectValue placeholder="Pré-definidas..." />
                    </SelectTrigger>
                    <SelectContent>
                      {(paymentPresets || []).map((p: any) => (
                        <SelectItem key={p.id} value={p.label}>{p.label}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <Input value={form.payment_conditions || ''} onChange={e => set('payment_conditions', e.target.value)}
                    placeholder="Ou descreva livremente..." disabled={isLocked} className="flex-1 h-8 text-sm" />
                </div>

                {/* Installment preview */}
                {selectedPreset && installmentRows.length > 0 && grandTotal > 0 && (
                  <div className="rounded-md bg-background border divide-y text-sm">
                    {installmentRows.map((row, i) => {
                      const amount = calcInstallmentAmount(row);
                      const isSignal = row.tipo === 'aprovacao' || row.days_after_approval === 0;
                      const daysLabel = row.tipo === 'entrega' ? 'na entrega'
                        : row.tipo === 'prazo' || row.days_after_approval > 0 ? `em ${row.days_after_approval} dias`
                        : 'na aprovação';
                      return (
                        <div key={i} className={`flex justify-between items-center px-3 py-2 ${isSignal ? 'bg-orange-50' : ''}`}>
                          <div>
                            <span className="font-medium">{row.label || `Parcela ${i + 1}`}</span>
                            <span className="ml-1.5 text-xs text-muted-foreground">({daysLabel})</span>
                            {isSignal && <span className="ml-1.5 text-xs font-medium text-orange-600">● sinal</span>}
                          </div>
                          <span className="font-semibold">{formatCurrency(amount)}</span>
                        </div>
                      );
                    })}
                  </div>
                )}

                {/* Sinal button */}
                {!isNew && orderId && signalAmount !== null && (orderData as any)?.quote_status === 'awaiting_deposit' && (
                  <Button
                    type="button"
                    className="w-full gap-2 bg-orange-500 hover:bg-orange-600 text-white"
                    onClick={() => { setShowFinancialDialog(false); setDepositFromFinancial(true); setDepositDialogOpen(true); }}
                  >
                    <DollarSign className="h-4 w-4" />
                    Registrar sinal — {formatCurrency(signalAmount)}
                  </Button>
                )}

                {/* Generate collections button */}
                {orderId && grandTotal > 0 && form.payment_conditions &&
                  (form.status === 'completed' || form.status === 'invoiced' || !!form.signed_at) && (
                  <Button variant="outline" size="sm" onClick={handleGenerateCollections}
                    disabled={generatingCollections}
                    className="gap-2 text-green-700 border-green-300 hover:bg-green-50 w-full">
                    <CreditCard className="h-4 w-4" />
                    {generatingCollections ? 'Gerando...' : 'Gerar Cobranças'}
                  </Button>
                )}

                {orderId && osCollections && osCollections.length > 0 && (
                  <div className="rounded-lg border bg-muted/20 p-3 space-y-1">
                    <p className="text-xs font-semibold text-muted-foreground flex items-center gap-1.5">
                      <CreditCard className="h-3.5 w-3.5" /> Cobranças Geradas ({osCollections.length})
                    </p>
                    {osCollections.map(c => (
                      <div key={c.id} className="grid grid-cols-[1fr_auto_auto] gap-2 items-center text-xs px-2 py-1.5 rounded bg-background border">
                        <span className="truncate">{c.description || 'Cobrança'}</span>
                        <span className="font-medium">{formatCurrency(Number(c.amount))}</span>
                        <span className="text-muted-foreground">{new Date(c.due_date).toLocaleDateString('pt-BR')}</span>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </div>

            {/* ── SECTION 4: SIMULADOR DE RECEBIMENTO ── */}
            <div className="space-y-2">
              <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide flex items-center gap-1.5">
                <Calculator className="h-3.5 w-3.5" /> Simulador de Recebimento
              </p>
              <div className="rounded-lg border bg-muted/20 p-3 space-y-3">
                {/* PIX */}
                <div className="flex justify-between items-center text-sm">
                  <span className="text-muted-foreground font-medium">PIX / Transferência</span>
                  <span className="font-bold text-lg">{formatCurrency(grandTotal)}</span>
                </div>
                <div className="border-t border-dashed pt-3 space-y-2">
                  <p className="text-xs text-muted-foreground font-medium flex items-center gap-1.5">
                    <CreditCard className="h-3.5 w-3.5" /> Cartão de Crédito
                  </p>
                  <div className="grid grid-cols-3 gap-1.5 text-xs">
                    {[1,2,3,4,5,6].map(n => {
                      const fee = cardFees?.find((f: any) => f.installments === n);
                      const feePct = fee?.fee_percent || 0;
                      const gross = feePct > 0 ? grandTotal / (1 - Number(feePct) / 100) : grandTotal;
                      const perInstall = gross / n;
                      const isSelected = selectedInstallments === n;
                      return (
                        <button key={n} type="button"
                          onClick={() => setSelectedInstallments(n)}
                          className={`rounded border p-1.5 text-left transition-colors ${isSelected ? 'bg-primary text-primary-foreground border-primary' : 'bg-background hover:bg-muted'}`}>
                          <div className="font-semibold">{n}x {formatCurrency(perInstall)}</div>
                          {feePct > 0 && (
                            <div className={`text-[10px] ${isSelected ? 'text-primary-foreground/70' : 'text-muted-foreground'}`}>
                              taxa {Number(feePct).toFixed(1)}%
                            </div>
                          )}
                        </button>
                      );
                    })}
                  </div>
                  {selectedInstallments > 0 && (() => {
                    const fee = cardFees?.find((f: any) => f.installments === selectedInstallments);
                    const feePct = fee?.fee_percent || 0;
                    const gross = feePct > 0 ? grandTotal / (1 - Number(feePct) / 100) : grandTotal;
                    return (
                      <div className="rounded bg-muted/40 px-3 py-2 text-xs space-y-1">
                        <div className="flex justify-between"><span className="text-muted-foreground">Valor a cobrar:</span><span className="font-semibold">{formatCurrency(gross)}</span></div>
                        {feePct > 0 && <div className="flex justify-between"><span className="text-muted-foreground">Taxa ({Number(feePct).toFixed(2)}%):</span><span className="text-destructive">−{formatCurrency(gross - grandTotal)}</span></div>}
                        <div className="flex justify-between border-t pt-1 text-success font-medium"><span>Você recebe líquido:</span><span>{formatCurrency(grandTotal)}</span></div>
                      </div>
                    );
                  })()}
                </div>
              </div>
            </div>

            {/* ── SECTION 5: DETALHES DO PDF ── */}
            <div className="space-y-2">
              <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide flex items-center gap-1.5">
                <FileText className="h-3.5 w-3.5" /> Detalhes do PDF
              </p>
              <div className="rounded-lg border bg-muted/20 p-3 space-y-3 text-sm">
                <div className="grid grid-cols-2 gap-3">
                  <div className="space-y-1.5">
                    <Label className="text-xs">Forma de pagamento preferida</Label>
                    <Select value={form.payment_method_preferred || 'none'} onValueChange={v => set('payment_method_preferred', v === 'none' ? '' : v)} disabled={isLocked}>
                      <SelectTrigger className="h-8 text-sm"><SelectValue placeholder="Padrão (todas)" /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="none">Padrão (todas as opções)</SelectItem>
                        {[{v:'pix',l:'PIX'},{v:'bank_transfer',l:'Transferência'},{v:'cash',l:'Dinheiro'},{v:'debit_card',l:'Débito'},{v:'credit_card',l:'Crédito'},{v:'boleto',l:'Boleto'}].map(m => (
                          <SelectItem key={m.v} value={m.v}>{m.l}</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                  <div className="space-y-1.5">
                    <Label className="text-xs">Validade do orçamento (dias)</Label>
                    <Input type="number" min="1" className="h-8 text-sm"
                      value={form.quote_validity_days || 15}
                      onChange={e => set('quote_validity_days', parseInt(e.target.value) || 15)}
                      disabled={isLocked} />
                  </div>
                </div>
                <div className="space-y-1.5">
                  <Label className="text-xs flex items-center gap-1.5">
                    Observações financeiras
                    <span className="text-muted-foreground">(aparece no PDF)</span>
                    {/* M5: badge quando preenchido */}
                    {form.financial_notes?.trim() && (
                      <span className="inline-flex items-center gap-0.5 px-1.5 py-0.5 rounded-full text-[10px] font-medium bg-amber-100 text-amber-700 border border-amber-200">
                        <AlertTriangle className="h-2.5 w-2.5" />
                        preenchido
                      </span>
                    )}
                  </Label>
                  <Textarea value={form.financial_notes || ''} onChange={e => set('financial_notes', e.target.value)}
                    rows={2} className="resize-none text-sm" placeholder="Condições especiais, avisos de pagamento..."
                    disabled={isLocked} />
                </div>
              </div>
            </div>

            {/* ── SECTION 6: COMISSÃO (collapsible) ── */}
            <div className="rounded-lg border bg-muted/20 overflow-hidden">
              <button type="button"
                className="w-full flex items-center justify-between px-3 py-2.5 text-sm text-muted-foreground hover:text-foreground hover:bg-muted/40 transition-colors"
                onClick={() => setShowCommission(v => !v)}>
                <span className="flex items-center gap-1.5 font-medium text-xs uppercase tracking-wide">
                  <Receipt className="h-3.5 w-3.5" /> Comissão (uso interno)
                </span>
                <ChevronDown className={`h-4 w-4 transition-transform ${showCommission ? 'rotate-180' : ''}`} />
              </button>
              {showCommission && (
                <div className="px-3 pb-3 pt-1 space-y-3 border-t text-sm">
                  <div className="flex justify-between items-center">
                    <Label className="text-sm text-muted-foreground">{(t.serviceOrders as any).commissionedPerson || 'Comissionado'}</Label>
                    <Select value={form.commissioned_user_id || 'none'} onValueChange={v => {
                      const user = commissionableUsers?.find(u => u.id === v);
                      setForm(f => ({ ...f, commissioned_user_id: v === 'none' ? '' : v, commissioned_person: user?.full_name || '' }));
                    }} disabled={isLocked}>
                      <SelectTrigger className="w-48 h-8 text-sm"><SelectValue placeholder="Selecionar" /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="none">—</SelectItem>
                        {(commissionableUsers || []).map(u => (
                          <SelectItem key={u.id} value={u.id}>{u.full_name} ({USER_ROLES.find(r => r.value === u.role)?.label || u.role})</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                  <div className="flex justify-between items-center">
                    <Label className="text-sm text-muted-foreground">Comissão (%)</Label>
                    <div className="flex items-center gap-2">
                      <Input type="number" step="0.01" className="w-20 h-8 text-right text-sm"
                        value={form.commission_rate}
                        onChange={e => {
                          const rate = parseFloat(e.target.value) || 0;
                          setForm(f => ({ ...f, commission_rate: rate, commission_amount: Math.round(grandTotal * rate / 100 * 100) / 100 }));
                        }} disabled={isLocked} />
                      {(form.commission_rate || 0) > 0 && (
                        <span className="text-xs text-muted-foreground">= {formatCurrency(grandTotal * (form.commission_rate || 0) / 100)}</span>
                      )}
                    </div>
                  </div>
                  {(form.commission_amount || 0) > 0 && (
                    <div className="rounded bg-muted/40 px-3 py-2 text-xs space-y-1">
                      <div className="flex justify-between"><span>Total bruto:</span><span>{formatCurrency(grandTotal)}</span></div>
                      <div className="flex justify-between text-muted-foreground"><span>Comissão ({form.commission_rate}%):</span><span>−{formatCurrency(form.commission_amount || 0)}</span></div>
                      <div className="flex justify-between font-semibold border-t pt-1"><span>Líquido empresa:</span><span>{formatCurrency(grandTotal - (form.commission_amount || 0))}</span></div>
                    </div>
                  )}
                </div>
              )}
            </div>

          </div>{/* end scrollable body */}

          {/* ── STICKY FOOTER: TOTAL ── */}
          <div className="border-t px-6 py-3 flex items-center justify-between bg-card rounded-b-lg">
            <div className="text-sm">
              {(form.discount_amount || 0) > 0 && (
                <span className="text-muted-foreground text-xs">
                  Subtotal {formatCurrency(subtotal)} · Desc. −{formatCurrency(form.discount_amount || 0)}
                  {(form.tax_amount || 0) > 0 ? ` · Taxa +${formatCurrency(form.tax_amount || 0)}` : ''}
                </span>
              )}
            </div>
            <div className="flex items-baseline gap-2">
              <span className="text-sm text-muted-foreground">{t.serviceOrders.grandTotal}</span>
              <span className="text-2xl font-bold text-accent">{formatCurrency(grandTotal)}</span>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Stock Alert Dialog — shown when part has insufficient stock */}
      {stockAlert && orderId && (
        <StockAlertDialog
          open={!!stockAlert}
          onOpenChange={v => { if (!v) setStockAlert(null); }}
          serviceOrderId={orderId}
          productId={stockAlert.productId}
          productName={stockAlert.productName}
          needed={stockAlert.needed}
          available={stockAlert.available}
          unitCost={stockAlert.unitCost}
          suppliers={stockAlert.suppliers}
          leadTimeDays={stockAlert.leadTimeDays}
          onAddAnyway={async () => {
            if (!orderId) return;
            await addPart.mutateAsync({
              service_order_id: orderId,
              product_id: stockAlert.productId,
              quantity: stockAlert.needed,
              unit_cost_snapshot: stockAlert.unitCost,
              unit_sale_snapshot: stockAlert.unitSale,
              notes: stockAlert.notes,
            });
            setOpenNewPartCards(prev => prev.filter(k => k !== stockAlert.cardKey));
            setEditingPart(prev => { const n = { ...prev }; delete n[stockAlert.cardKey]; return n; });
            setStockAlert(null);
            toast.success('Peça adicionada (estoque negativo)');
          }}
        />
      )}

      {/* Receive PO Dialog */}
      {receivePOTarget && (
        <ReceivePODialog
          open={!!receivePOTarget}
          onOpenChange={v => { if (!v) setReceivePOTarget(null); }}
          po={receivePOTarget}
        />
      )}

      {/* Notes & Technical Reports */}
      <section className="rounded-xl border bg-card p-5 shadow-sm space-y-4">
        <h2 className="font-semibold text-sm">Observações e Laudos Técnicos</h2>
        <Collapsible open={extraFieldsOpen} onOpenChange={setExtraFieldsOpen}>
          <CollapsibleTrigger asChild>
            <Button variant="ghost" size="sm" className="gap-2 text-muted-foreground hover:text-foreground">
              <ChevronDown className={`h-4 w-4 transition-transform ${extraFieldsOpen ? 'rotate-180' : ''}`} />
              Campos adicionais (diagnóstico, laudo...)
            </Button>
          </CollapsibleTrigger>
          <CollapsibleContent className="space-y-4 pt-3">
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
              <div>
                <div className="flex items-center justify-between mb-1">
                  <Label>{t.serviceOrders.technicianNotes}</Label>
                  <Button type="button" variant="ghost" size="sm" className="h-6 px-2 text-xs text-primary hover:text-primary hover:bg-primary/10"
                    onClick={async () => set('technician_notes', await optimizeText(form.technician_notes))} disabled={isOptimizing || !form.technician_notes || isLocked}>
                    <Sparkles className="h-3 w-3 mr-1" /> IA
                  </Button>
                </div>
                <Textarea value={form.technician_notes} onChange={(e) => set('technician_notes', e.target.value)} rows={2} disabled={isLocked} />
              </div>
              <div>
                <div className="flex items-center justify-between mb-1">
                  <Label>{t.serviceOrders.initialFindings}</Label>
                  <Button type="button" variant="ghost" size="sm" className="h-6 px-2 text-xs text-primary hover:text-primary hover:bg-primary/10"
                    onClick={async () => set('initial_findings', await optimizeText(form.initial_findings))} disabled={isOptimizing || !form.initial_findings || isLocked}>
                    <Sparkles className="h-3 w-3 mr-1" /> IA
                  </Button>
                </div>
                <Textarea value={form.initial_findings} onChange={(e) => set('initial_findings', e.target.value)} rows={2} disabled={isLocked} />
              </div>
              <div>
                <div className="flex items-center justify-between mb-1">
                  <Label>{t.serviceOrders.diagnosis}</Label>
                  <Button type="button" variant="ghost" size="sm" className="h-6 px-2 text-xs text-primary hover:text-primary hover:bg-primary/10"
                    onClick={async () => set('diagnosis', await optimizeText(form.diagnosis))} disabled={isOptimizing || !form.diagnosis || isLocked}>
                    <Sparkles className="h-3 w-3 mr-1" /> IA
                  </Button>
                </div>
                <Textarea value={form.diagnosis} onChange={(e) => set('diagnosis', e.target.value)} rows={2} disabled={isLocked} />
              </div>
              <div>
                <div className="flex items-center justify-between mb-1">
                  <Label>{t.serviceOrders.solutionApplied}</Label>
                  <Button type="button" variant="ghost" size="sm" className="h-6 px-2 text-xs text-primary hover:text-primary hover:bg-primary/10"
                    onClick={async () => set('solution_applied', await optimizeText(form.solution_applied))} disabled={isOptimizing || !form.solution_applied || isLocked}>
                    <Sparkles className="h-3 w-3 mr-1" /> IA
                  </Button>
                </div>
                <Textarea value={form.solution_applied} onChange={(e) => set('solution_applied', e.target.value)} rows={2} disabled={isLocked} />
              </div>
              <div>
                <div className="flex items-center justify-between mb-1">
                  <Label>{t.serviceOrders.internalNotes}</Label>
                  <Button type="button" variant="ghost" size="sm" className="h-6 px-2 text-xs text-primary hover:text-primary hover:bg-primary/10"
                    onClick={async () => set('internal_notes', await optimizeText(form.internal_notes))} disabled={isOptimizing || !form.internal_notes || isLocked}>
                    <Sparkles className="h-3 w-3 mr-1" /> IA
                  </Button>
                </div>
                <Textarea value={form.internal_notes} onChange={(e) => set('internal_notes', e.target.value)} rows={2} disabled={isLocked} />
              </div>
              <div>
                <div className="flex items-center justify-between mb-1">
                  <Label>{t.serviceOrders.customerReport}</Label>
                  <Button type="button" variant="ghost" size="sm" className="h-6 px-2 text-xs text-primary hover:text-primary hover:bg-primary/10"
                    onClick={async () => set('customer_visible_report', await optimizeText(form.customer_visible_report))} disabled={isOptimizing || !form.customer_visible_report || isLocked}>
                    <Sparkles className="h-3 w-3 mr-1" /> IA
                  </Button>
                </div>
                <Textarea value={form.customer_visible_report} onChange={(e) => set('customer_visible_report', e.target.value)} rows={2} disabled={isLocked} />
              </div>
            </div>
          </CollapsibleContent>
        </Collapsible>
      </section>

      {/* Signatures */}
      {!isNew && orderId && (
        <section className="rounded-xl border bg-card p-5 shadow-sm space-y-4">
          <div className="flex items-center justify-between">
            <h2 className="font-semibold text-sm flex items-center gap-2">
              <FileText className="h-4 w-4" />
              Assinaturas do Cliente
            </h2>
          </div>
          <ServiceOrderSignatures serviceOrderId={orderId} />
        </section>
      )}

      {/* Bottom Save bar (mirrors top action) */}
      {!isLocked && (
        <div ref={bottomSaveRef} className="flex justify-end pt-2">
          <Button
            onClick={handleSave}
            disabled={createSO.isPending || updateSO.isPending}
            size="lg"
            className="bg-accent text-accent-foreground hover:bg-accent/90 min-w-[180px]"
          >
            {t.common.save}
          </Button>
        </div>
      )}

      {/* Sticky floating Save — visível só quando topo E rodapé estão fora da tela */}
      {!isLocked && !topVisible && !bottomVisible && (
        <div className="sticky bottom-4 z-30 flex justify-end pointer-events-none">
          <Button
            onClick={handleSave}
            disabled={createSO.isPending || updateSO.isPending}
            size="lg"
            className="pointer-events-auto bg-accent text-accent-foreground hover:bg-accent/90 shadow-lg shadow-accent/30 gap-2"
          >
            {createSO.isPending || updateSO.isPending ? 'Salvando...' : t.common.save}
          </Button>
        </div>
      )}

      {/* PDF Options Dialog */}
      <PDFOptionsDialog
        open={!!pdfDialogType && !!pdfData}
        onOpenChange={v => { if (!v) setPdfDialogType(null); }}
        documentType={pdfDialogType || 'quote'}
        initialValidityDays={form.quote_validity_days || 15}
        hasProductImages={pdfData?.parts?.some((p: any) => !!p.image_url) ?? false}
        onGenerate={async (action, options, validity, dueDate) => {
          if (!pdfData || !pdfDialogType) return;
          const payload = { ...pdfData, documentType: pdfDialogType };
          const opts = { ...options, validity, dueDate };
          if (action === 'download') {
            try {
              await downloadPDF(payload, opts);
              toast.success('PDF baixado com sucesso');
              setPdfDialogType(null);
            } catch (e: any) {
              console.error('PDF download failed:', e);
              toast.error('Erro ao gerar o PDF para download');
            }
          } else {
            generatePDF(payload, opts);
            setPdfDialogType(null);
          }
        }}
      />

      {/* WhatsApp Preview Dialog */}
      <Dialog open={!!waPreview} onOpenChange={v => { if (!v) setWaPreview(null); }}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <MessageCircle className="h-5 w-5 text-green-600" />
              Enviar via WhatsApp
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            {waPreview?.clientName && (
              <div className="text-sm text-muted-foreground">
                Cliente: <span className="font-medium text-foreground">{waPreview.clientName}</span>
              </div>
            )}
            <div className="space-y-2">
              <Label htmlFor="wa-phone">Número (com DDI + DDD)</Label>
              <Input
                id="wa-phone"
                value={waEditPhone}
                onChange={e => setWaEditPhone(e.target.value.replace(/\D/g, ''))}
                placeholder="Ex: 5521999999999"
              />
              {!waEditPhone && (
                <p className="text-xs text-muted-foreground">
                  Sem número: o WhatsApp pedirá para você escolher o contato.
                </p>
              )}
            </div>
            <div className="space-y-2">
              <Label htmlFor="wa-message">Mensagem</Label>
              <Textarea
                id="wa-message"
                value={waEditMessage}
                onChange={e => setWaEditMessage(e.target.value)}
                rows={5}
              />
            </div>
            <div className="rounded-md border bg-muted/40 p-3 text-xs break-all">
              <div className="font-medium text-foreground mb-1">Link público:</div>
              {waPreview?.url}
            </div>
            <div className="flex justify-end gap-2 pt-2">
              <Button variant="outline" onClick={() => setWaPreview(null)}>
                Cancelar
              </Button>
              <Button
                className="bg-green-600 hover:bg-green-700 text-white gap-1"
                onClick={() => {
                  const waUrl = waEditPhone
                    ? `https://wa.me/${waEditPhone}?text=${encodeURIComponent(waEditMessage)}`
                    : `https://wa.me/?text=${encodeURIComponent(waEditMessage)}`;
                  let opened = false;
                  try {
                    const w = window.open(waUrl, '_blank', 'noopener,noreferrer');
                    opened = !!w;
                  } catch {
                    opened = false;
                  }
                  if (orderData?.id) {
                    void writeAuditLog({
                      table_name: 'service_orders',
                      record_id: orderData.id,
                      action: 'whatsapp_send' as any,
                      new_value: {
                        share_token: orderData.share_token,
                        public_url: waPreview?.url,
                        phone_used: waEditPhone || null,
                        had_phone: !!waEditPhone,
                        wa_url: waUrl,
                        window_opened: opened,
                      },
                      reason: opened
                        ? 'Link do WhatsApp aberto'
                        : 'Falha ao abrir janela do WhatsApp (provável bloqueio de pop-up)',
                    });
                  }
                  recordWhatsAppEvent({
                    source: 'detail_dialog',
                    action: 'send',
                    serviceOrderId: orderData?.id,
                    serviceOrderNumber: orderData?.service_order_number,
                    shareToken: orderData?.share_token,
                    phoneNormalized: waEditPhone || undefined,
                    opened,
                    popupBlocked: !opened,
                    errorMessage: !opened ? 'window.open returned null (likely popup blocker)' : undefined,
                  });
                  setWaPreview(null);
                }}
              >
                <MessageCircle className="h-4 w-4" />
                Abrir WhatsApp
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      <WhatsAppSendHistoryDialog
        open={showZapiHistory}
        onOpenChange={setShowZapiHistory}
        serviceOrderId={showZapiHistory ? (orderId || null) : null}
        serviceOrderNumber={orderData?.service_order_number}
      />

      <SendViaWhatsAppDialog
        open={!!whatsAppTarget}
        onOpenChange={v => { if (!v) setWhatsAppTarget(null); }}
        target={whatsAppTarget}
      />

      <QuickProductDialog
        open={quickProductOpen}
        onOpenChange={setQuickProductOpen}
        initialName={quickProductName}
        onCreated={() => {
          // Kept for backwards compatibility; new flow uses inline part cards.
        }}
      />

      <PriceCalculatorDialog
        open={!!priceCalcCardKey}
        onOpenChange={(v) => { if (!v) setPriceCalcCardKey(null); }}
        initialCost={priceCalcCardKey ? (editingPart[priceCalcCardKey]?.unit_cost || 0) : 0}
        initialPrice={priceCalcCardKey ? (editingPart[priceCalcCardKey]?.unit_sale || 0) : 0}
        onConfirm={(price) => {
          if (!priceCalcCardKey) return;
          setEditingPart((prev) => ({
            ...prev,
            [priceCalcCardKey]: { ...prev[priceCalcCardKey], unit_sale: price },
          }));
        }}
      />

      <MarinaFormDialog
        open={quickMarinaOpen}
        onOpenChange={setQuickMarinaOpen}
        marina={null}
        onSaved={(marina) => {
          set('marina_id', marina.id);
          setQuickMarinaOpen(false);
        }}
      />

      <QuickSupplierDialog
        open={quickSupplierOpen}
        onOpenChange={setQuickSupplierOpen}
        initialName={quickSupplierName}
        onCreated={(s) => setExpForm((prev) => ({ ...prev, supplier_id: s.id }))}
      />
    </div>
  );
}
