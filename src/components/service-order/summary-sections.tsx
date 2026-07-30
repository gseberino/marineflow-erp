/* Seções G+H da OS — Pedidos de Compra vinculados e Mini-Resumo Financeiro
   (botões Despesas/Horas/Composição) — extraídas 1:1 do ServiceOrderForm
   (Fase 3, passo 7). */
import type { Dispatch, SetStateAction } from 'react';
import { toast } from 'sonner';
import { Calculator, ChevronDown, Clock, DollarSign, MapPin, Package, PackagePlus, Receipt } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { useI18n } from '@/i18n';
import { PurchaseNeedsBanner } from '@/components/purchasing/PurchaseNeedsBanner';

interface SummarySectionsProps {
  isNew: boolean;
  orderId?: string;
  orderData: any;
  form: Record<string, any>;
  clientView: boolean;
  setClientView: Dispatch<SetStateAction<boolean>>;
  linkedPOs: any[] | undefined;
  updatePO: any;
  setReceivePOTarget: Dispatch<SetStateAction<any>>;
  laborCost: number;
  partsCost: number;
  subtotal: number;
  grandTotal: number;
  partsRevenue: number;
  partsProfit: number;
  partsMarginPct: number;
  soReceivables: any[] | undefined;
  soPayments: any[] | undefined;
  soTotalCharged: number;
  soTotalPaid: number;
  soBalance: number;
  soPayStatus: string;
  showPaymentHistory: boolean;
  setShowPaymentHistory: Dispatch<SetStateAction<boolean>>;
  setPaymentDialogReceivable: Dispatch<SetStateAction<any>>;
  createReceivable: any;
  showFinancialDialog: boolean;
  setShowFinancialDialog: Dispatch<SetStateAction<boolean>>;
  setShowExpensesDialog: Dispatch<SetStateAction<boolean>>;
  setShowTimeDialog: Dispatch<SetStateAction<boolean>>;
  setShowTravelDialog: Dispatch<SetStateAction<boolean>>;
}

export function SummarySections(props: SummarySectionsProps) {
  const {
    isNew, orderId, orderData, form, clientView, setClientView,
    linkedPOs, updatePO, setReceivePOTarget,
    laborCost, partsCost, subtotal, grandTotal,
    partsRevenue, partsProfit, partsMarginPct,
    soReceivables, soPayments, soTotalCharged, soTotalPaid, soBalance, soPayStatus,
    showPaymentHistory, setShowPaymentHistory, setPaymentDialogReceivable, createReceivable,
    showFinancialDialog, setShowFinancialDialog,
    setShowExpensesDialog, setShowTimeDialog, setShowTravelDialog,
  } = props;
  const { t, formatCurrency } = useI18n();

  return (
    <>
      {/* Faixa de compras: some sozinha quando não há falta nem cotação aberta.
          Busca os próprios dados para não engordar o contrato de props desta seção. */}
      <PurchaseNeedsBanner
        serviceOrderId={orderId}
        serviceOrderNumber={orderData?.service_order_number ?? form?.service_order_number}
        clientName={orderData?.clients?.name}
        status={orderData?.status ?? form?.status}
        isNew={isNew}
      />

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
        {/* Toggle de visão Interno/Cliente */}
        {!isNew && (
          <div className="px-4 pt-2 flex items-center justify-end">
            <div className="inline-flex items-center rounded-full border bg-muted/40 p-0.5 text-[11px]">
              <button type="button"
                onClick={() => setClientView(false)}
                className={`px-2.5 py-0.5 rounded-full transition-colors ${!clientView ? 'bg-background shadow-sm font-medium text-foreground' : 'text-muted-foreground'}`}>
                Interno
              </button>
              <button type="button"
                onClick={() => setClientView(true)}
                className={`px-2.5 py-0.5 rounded-full transition-colors ${clientView ? 'bg-background shadow-sm font-medium text-foreground' : 'text-muted-foreground'}`}>
                Cliente
              </button>
            </div>
          </div>
        )}
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

        {/* Row 2: composition % + parts profit (edit-mode only, escondido na visão Cliente) */}
        {!isNew && !clientView && (subtotal > 0 || partsRevenue > 0) && (
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

        {/* M1: Gestão financeira integrada — sempre visível em OS salva */}
        {!isNew && (
          <div className="border-t">
            {/* Cabeçalho com totais e badge de status */}
            <div className="px-4 py-2 bg-blue-50/40 dark:bg-blue-950/20 flex items-center gap-3 flex-wrap text-xs">
              {(soReceivables || []).length > 0 ? (
                <>
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
                    soPayStatus === 'paid'            ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-900/40'
                    : soPayStatus === 'partially_paid' ? 'bg-amber-100 text-amber-700 dark:bg-amber-900/40'
                    : 'bg-muted text-muted-foreground'
                  }`}>
                    {soPayStatus === 'paid' ? 'Quitado' : soPayStatus === 'partially_paid' ? 'Parcial' : 'Não faturado'}
                  </span>
                </>
              ) : (
                <>
                  <span className="text-muted-foreground">
                    Valor a cobrar: <span className="font-semibold text-foreground">{formatCurrency(grandTotal)}</span>
                  </span>
                  <span className="ml-auto inline-flex items-center px-2 py-0.5 rounded-full text-[10px] font-semibold bg-muted text-muted-foreground">
                    Sem lançamentos
                  </span>
                </>
              )}
            </div>

            {/* Lista de recebíveis com ações */}
            {(soReceivables || []).length > 0 && (
              <div className="divide-y divide-dashed">
                {(soReceivables || []).map((rec: any) => {
                  const isPaid = rec.status === 'paid';
                  const isPartial = rec.status === 'partially_paid';
                  const bal = Number(rec.balance_amount || 0);
                  return (
                    <div key={rec.id} className="px-4 py-2 flex items-center gap-3 text-xs hover:bg-muted/20 transition-colors">
                      {/* Descrição + vencimento */}
                      <div className="flex-1 min-w-0">
                        <p className="font-medium truncate text-foreground">{rec.description || 'Recebível'}</p>
                        {rec.due_date && (
                          <p className="text-muted-foreground text-[10px]">
                            Vence: {new Date(rec.due_date + 'T12:00:00').toLocaleDateString('pt-BR')}
                          </p>
                        )}
                      </div>
                      {/* Valores */}
                      <div className="text-right shrink-0">
                        <p className="font-semibold">{formatCurrency(Number(rec.amount))}</p>
                        {isPartial && (
                          <p className="text-[10px] text-amber-600">Saldo: {formatCurrency(bal)}</p>
                        )}
                      </div>
                      {/* Badge status */}
                      <span className={`shrink-0 inline-flex items-center px-2 py-0.5 rounded-full text-[10px] font-semibold ${
                        isPaid    ? 'bg-emerald-100 text-emerald-700'
                        : isPartial ? 'bg-amber-100 text-amber-700'
                        : 'bg-muted text-muted-foreground'
                      }`}>
                        {isPaid ? 'Pago' : isPartial ? 'Parcial' : 'Pendente'}
                      </span>
                      {/* Botão registrar pagamento */}
                      {!isPaid && bal > 0 && (
                        <Button
                          type="button"
                          size="sm"
                          variant="outline"
                          className="h-7 text-xs px-2 shrink-0 gap-1 border-primary/40 text-primary hover:bg-primary/5"
                          onClick={() => setPaymentDialogReceivable(rec)}
                        >
                          <DollarSign className="h-3 w-3" />
                          {isPartial ? 'Complementar' : 'Registrar pgto.'}
                        </Button>
                      )}
                    </div>
                  );
                })}
              </div>
            )}

            {/* Botão criar recebível manual (quando não há nenhum ainda e OS não é nova) */}
            {(soReceivables || []).length === 0 && grandTotal > 0 && (
              <div className="px-4 py-2 flex items-center justify-between">
                <span className="text-xs text-muted-foreground">Nenhum lançamento financeiro ainda</span>
                <Button
                  type="button"
                  size="sm"
                  variant="outline"
                  className="h-7 text-xs px-2 gap-1 border-primary/40 text-primary hover:bg-primary/5"
                  disabled={createReceivable.isPending}
                  onClick={async () => {
                    if (!orderId || !orderData?.client_id) return;
                    try {
                      const rec = await createReceivable.mutateAsync({
                        client_id: orderData.client_id,
                        service_order_id: orderId,
                        description: `${orderData?.service_order_number || 'OS'} — saldo final`,
                        issue_date: new Date().toISOString().split('T')[0],
                        due_date: new Date().toISOString().split('T')[0],
                        amount: grandTotal,
                      });
                      setPaymentDialogReceivable(rec);
                    } catch (e: any) {
                      toast.error(e?.message || 'Erro ao criar recebível');
                    }
                  }}
                >
                  <DollarSign className="h-3 w-3" />
                  Lançar recebível
                </Button>
              </div>
            )}
          </div>
        )}

        {/* M2: Histórico de pagamentos — colapsável, só aparece quando há pagamentos */}
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
            onClick={() => setShowFinancialDialog((v) => !v)}
          >
            <Calculator className="h-3.5 w-3.5" />
            {showFinancialDialog ? 'Ocultar' : 'Ver'} Composição Financeira
            {/* M5: dot indicator quando financial_notes está preenchido */}
            {form.financial_notes?.trim() && (
              <span className="h-2 w-2 rounded-full bg-amber-400 ml-0.5 animate-pulse" title="Observações financeiras preenchidas" />
            )}
          </Button>
        </div>
      </div>
    </>
  );
}
