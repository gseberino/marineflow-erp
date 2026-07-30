/* ─────────────────────────────────────────────────────────────────────────────
   Composição Financeira da OS — extraída 1:1 do ServiceOrderForm (Fase 3).

   O JSX veio do bloco original sem alteração; toda a matemática continua no
   pai (via props) e em src/lib/os-financials.ts. showCommission e presetKey
   moraram aqui porque só este bloco os usa. Mudança de comportamento deve
   começar pelos testes de os-financials.test.ts.
──────────────────────────────────────────────────────────────────────────── */
import { useState } from 'react';
import type { Dispatch, SetStateAction } from 'react';
import {
  AlertTriangle, Calculator, ChevronDown, CreditCard, DollarSign,
  FileText, Receipt, Tag,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Textarea } from '@/components/ui/textarea';
import { MoneyInput } from '@/components/MoneyInput';
import { useI18n } from '@/i18n';
import { USER_ROLES } from '@/hooks/use-app-users';
import type { InstallmentRow } from '@/lib/os-financials';
import { CustomInstallmentEditor } from './form-parts';

interface FinancialSectionProps {
  showFinancialDialog: boolean;
  setShowFinancialDialog: Dispatch<SetStateAction<boolean>>;
  form: Record<string, any>;
  set: (field: string, value: any) => void;
  setForm: Dispatch<SetStateAction<Record<string, any>>>;
  orderId?: string;
  orderData: any;
  isNew: boolean;
  isLocked: boolean;
  clientView: boolean;
  laborCost: number;
  partsCost: number;
  operationalCost: number;
  expensesTotal: number;
  subtotal: number;
  base: number;
  grandTotal: number;
  discountRatio: number;
  cardFeeAmount: number;
  signalAmount: number | null;
  discountServicesPct: number;
  discountPartsPct: number;
  applyBulkLineDiscount: (target: 'services' | 'parts' | 'both', pct: number) => void | Promise<void>;
  issRatePct: number;
  defaultQuoteValidityDays: number;
  paymentPresets: any[] | undefined;
  selectedPreset: any;
  installmentRows: InstallmentRow[];
  calcInstallmentAmount: (row: InstallmentRow) => number;
  cardFees: any[] | null | undefined;
  selectedInstallments: number;
  setSelectedInstallments: Dispatch<SetStateAction<number>>;
  setDepositFromFinancial: Dispatch<SetStateAction<boolean>>;
  setDepositDialogOpen: Dispatch<SetStateAction<boolean>>;
  handleGenerateCollections: () => void | Promise<void>;
  generatingCollections: boolean;
  osCollections: any[] | undefined;
  commissionableUsers: any[] | undefined;
}

export function FinancialSection(props: FinancialSectionProps) {
  const {
    showFinancialDialog,
    setShowFinancialDialog,
    form,
    set,
    setForm,
    orderId,
    orderData,
    isNew,
    isLocked,
    clientView,
    laborCost,
    partsCost,
    operationalCost,
    expensesTotal,
    subtotal,
    base,
    grandTotal,
    discountRatio,
    cardFeeAmount,
    signalAmount,
    discountServicesPct,
    discountPartsPct,
    applyBulkLineDiscount,
    issRatePct,
    defaultQuoteValidityDays,
    paymentPresets,
    selectedPreset,
    installmentRows,
    calcInstallmentAmount,
    cardFees,
    selectedInstallments,
    setSelectedInstallments,
    setDepositFromFinancial,
    setDepositDialogOpen,
    handleGenerateCollections,
    generatingCollections,
    osCollections,
    commissionableUsers,
  } = props;
  const { t, formatCurrency } = useI18n();
  const [showCommission, setShowCommission] = useState(false);
  const [presetKey, setPresetKey] = useState(0);
  const customInstallments = (form as any).custom_payment_installments;

  return (
      <Collapsible open={showFinancialDialog} onOpenChange={setShowFinancialDialog} className="rounded-lg border bg-card mt-3">
        <CollapsibleTrigger asChild>
          <button type="button" className="w-full flex items-center justify-between px-6 py-3 border-b text-left">
            <span className="flex items-center gap-2 text-base font-semibold">
              <Calculator className="h-4 w-4" /> Composição Financeira
            </span>
            <span className="flex items-center gap-2">
              <span className="text-sm text-muted-foreground hidden sm:inline">{formatCurrency(grandTotal)}</span>
              <ChevronDown className={`h-4 w-4 transition-transform ${showFinancialDialog ? 'rotate-180' : ''}`} />
            </span>
          </button>
        </CollapsibleTrigger>

        <CollapsibleContent>
          <div className="px-6 py-4 space-y-5">

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
                  <p className="text-xs text-muted-foreground font-medium">Desconto por linha (%)</p>
                  <p className="text-[11px] text-muted-foreground -mt-1">Aplica o desconto diretamente em cada linha de serviço/peça da OS.</p>
                  <div className="grid grid-cols-2 gap-2">
                    <div className="space-y-1">
                      <Label className="text-xs text-muted-foreground">↳ Serviços (%)</Label>
                      <div className="flex items-center gap-1.5">
                        <Input type="number" min="0" max="100" step="0.5"
                          className="w-16 h-7 text-right text-xs" value={discountServicesPct || ''}
                          placeholder="0" disabled={isLocked}
                          onChange={e => {
                            const pct = Math.max(0, Math.min(100, parseFloat(e.target.value) || 0));
                            applyBulkLineDiscount('services', pct);
                          }} />
                        <span className="text-xs text-muted-foreground">−{formatCurrency(laborCost * discountServicesPct / 100)}</span>
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
                            applyBulkLineDiscount('parts', pct);
                          }} />
                        <span className="text-xs text-muted-foreground">−{formatCurrency(partsCost * discountPartsPct / 100)}</span>
                      </div>
                    </div>
                  </div>

                  {/* Atalhos rápidos — aplicam o mesmo % em lote a todas as linhas de serviço e peça */}
                  {!isLocked && (laborCost + partsCost) > 0 && (
                    <div className="flex flex-wrap items-center gap-1.5 pt-1">
                      {[5, 10, 15].map(p => (
                        <button key={p} type="button" onClick={() => applyBulkLineDiscount('both', p)}
                          className="text-[11px] px-2 py-0.5 rounded border border-border text-muted-foreground hover:border-destructive/50 hover:text-destructive transition-colors">
                          −{p}% em todas as linhas
                        </button>
                      ))}
                      {(discountServicesPct > 0 || discountPartsPct > 0) && (
                        <button type="button"
                          onClick={() => applyBulkLineDiscount('both', 0)}
                          className="text-[11px] px-2 py-0.5 rounded border border-border text-muted-foreground hover:bg-muted transition-colors ml-auto">
                          Limpar desconto por linha
                        </button>
                      )}
                    </div>
                  )}

                  <div className="flex items-center justify-between pt-2 border-t border-dashed">
                    <div>
                      <Label className="text-xs font-medium text-destructive">Desconto adicional (valor fixo)</Label>
                      <p className="text-[11px] text-muted-foreground">Ajuste extra de fechamento, somado por cima do já descontado por linha.</p>
                    </div>
                    <MoneyInput className="w-28 h-7 text-right text-sm text-destructive font-medium"
                      value={form.discount_amount}
                      onValueChange={v => set('discount_amount', v)}
                      disabled={isLocked} />
                  </div>
                  {grandTotal > 0 && (
                    <div className="flex flex-wrap items-center gap-1.5">
                      <button type="button"
                        onClick={() => {
                          const step = grandTotal >= 1000 ? 100 : 10;
                          const target = Math.floor(grandTotal / step) * step;
                          const extraDiscount = Math.round((grandTotal - target) * 100) / 100;
                          if (extraDiscount > 0) {
                            set('discount_amount', Math.round(((form.discount_amount || 0) + extraDiscount) * 100) / 100);
                          }
                        }}
                        className="text-[11px] px-2 py-0.5 rounded border border-border text-muted-foreground hover:border-primary/50 hover:text-primary transition-colors">
                        ⌄ Arredondar {formatCurrency(grandTotal >= 1000 ? Math.floor(grandTotal / 100) * 100 : Math.floor(grandTotal / 10) * 10)}
                      </button>
                      {(form.discount_amount || 0) > 0 && (
                        <button type="button"
                          onClick={() => set('discount_amount', 0)}
                          className="text-[11px] px-2 py-0.5 rounded border border-border text-muted-foreground hover:bg-muted transition-colors">
                          Limpar valor fixo
                        </button>
                      )}
                    </div>
                  )}
                </div>

                {/* Tax + ISS quick-apply */}
                <div className="space-y-1.5 pt-2 border-t border-dashed">
                  <div className="flex items-center justify-between">
                    <Label className="text-sm">{t.serviceOrders.tax}</Label>
                    <MoneyInput className="w-28 h-7 text-right text-sm" value={form.tax_amount}
                      onValueChange={v => set('tax_amount', v)} disabled={isLocked} />
                  </div>
                  {!isLocked && issRatePct > 0 && (
                    <div className="flex items-center gap-2 justify-end">
                      <button
                        type="button"
                        onClick={() => {
                          // ISS incide sobre a base (subtotal - desconto)
                          const base = Math.max(0, subtotal - (form.discount_amount || 0));
                          set('tax_amount', Math.round(base * issRatePct) / 100);
                        }}
                        className="text-[11px] px-2 py-0.5 rounded border border-blue-300 text-blue-700 hover:bg-blue-50 transition-colors"
                      >
                        Aplicar ISS {issRatePct}%
                      </button>
                      {form.tax_amount > 0 && (
                        <button
                          type="button"
                          onClick={() => set('tax_amount', 0)}
                          className="text-[11px] px-2 py-0.5 rounded border border-border text-muted-foreground hover:bg-muted transition-colors"
                        >
                          Zerar
                        </button>
                      )}
                    </div>
                  )}
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
                {(orderData as any)?.converted_to_os_at ? (
                  // Já convertida em OS: a condição de pagamento já foi decidida (e o sinal já
                  // gerou um recebível real) — mostrar só um resumo somente-leitura em vez do
                  // seletor/tabela de configuração, que não faz mais sentido reabrir aqui.
                  <p className="text-sm">
                    <span className="text-muted-foreground">Condição de pagamento: </span>
                    <span className="font-medium">{form.payment_conditions || '—'}</span>
                  </p>
                ) : (
                  <>
                    <div className="flex gap-2 items-center">
                      <Select key={presetKey} onValueChange={v => {
                        if (v === '__custom__') {
                          set('payment_condition_preset_id', '');
                          set('payment_conditions', 'Personalizado');
                          if (!Array.isArray(customInstallments) || customInstallments.length === 0) {
                            set('custom_payment_installments', [
                              { label: 'Parcela 1', services_pct: 100, parts_pct: 100, expenses_pct: 100, days_after_approval: 0, tipo: 'aprovacao' },
                            ]);
                          }
                          setPresetKey(k => k + 1);
                          return;
                        }
                        const preset = (paymentPresets || []).find((p: any) => p.label === v);
                        set('payment_conditions', v);
                        set('payment_condition_preset_id', preset?.id || '');
                        set('custom_payment_installments', null);
                        setPresetKey(k => k + 1);
                      }} disabled={isLocked}>
                        <SelectTrigger className="w-44 h-8 text-sm">
                          <SelectValue placeholder="Pré-definidas..." />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="__custom__">Personalizado</SelectItem>
                          {(paymentPresets || []).map((p: any) => (
                            <SelectItem key={p.id} value={p.label}>{p.label}</SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                      <Input value={form.payment_conditions || ''} onChange={e => set('payment_conditions', e.target.value)}
                        placeholder="Ou descreva livremente..." disabled={isLocked} className="flex-1 h-8 text-sm" />
                    </div>

                    {/* Editor de parcelas personalizado (sem preset selecionado) */}
                    {!selectedPreset && Array.isArray(customInstallments) && (
                      <CustomInstallmentEditor
                        installments={installmentRows}
                        onChange={(rows) => set('custom_payment_installments', rows)}
                        laborCost={laborCost}
                        partsCost={partsCost}
                        expensesTotal={expensesTotal}
                        discountRatio={discountRatio}
                        formatCurrency={formatCurrency}
                        disabled={isLocked}
                      />
                    )}

                    {/* Installment preview (preset) */}
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
                  </>
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
                      const gross = feePct > 0 ? base / (1 - Number(feePct) / 100) : base;
                      const perInstall = gross / n;
                      const isSelected = selectedInstallments === n;
                      return (
                        <button key={n} type="button"
                          onClick={() => { setSelectedInstallments(n); set('card_installments', n); }}
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
                    const gross = feePct > 0 ? base / (1 - Number(feePct) / 100) : base;
                    return (
                      <div className="rounded bg-muted/40 px-3 py-2 text-xs space-y-1">
                        <div className="flex justify-between"><span className="text-muted-foreground">Valor a cobrar:</span><span className="font-semibold">{formatCurrency(gross)}</span></div>
                        {feePct > 0 && <div className="flex justify-between"><span className="text-muted-foreground">Taxa ({Number(feePct).toFixed(2)}%):</span><span className="text-destructive">−{formatCurrency(gross - base)}</span></div>}
                        <div className="flex justify-between border-t pt-1 text-success font-medium"><span>Você recebe líquido:</span><span>{formatCurrency(base)}</span></div>
                      </div>
                    );
                  })()}
                  <label className="flex items-center gap-2 text-sm cursor-pointer pt-2 border-t mt-2">
                    <input type="checkbox" checked={form.card_fee_passthrough_enabled}
                      onChange={(e) => set('card_fee_passthrough_enabled', e.target.checked)} />
                    Repassar taxa de cartão ao cliente
                    <span className="text-xs text-muted-foreground">
                      ({selectedInstallments}x — soma {formatCurrency(cardFeeAmount)} ao total)
                    </span>
                  </label>
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
                      value={form.quote_validity_days || defaultQuoteValidityDays}
                      onChange={e => set('quote_validity_days', parseInt(e.target.value) || defaultQuoteValidityDays)}
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

            {/* ── SECTION 6: COMISSÃO (collapsible, oculto na visão Cliente) ── */}
            {!clientView && (
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
            )}{/* end !clientView commission */}

          </div>{/* end scrollable body */}

          {/* ── RESUMO DO TOTAL (dentro da seção, complementar à barra fixa) ── */}
          <div className="border-t px-6 py-3 flex items-center justify-between bg-muted/30 rounded-b-lg">
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
        </CollapsibleContent>
      </Collapsible>
  );
}
