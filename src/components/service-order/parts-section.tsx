/* Seção F — Peças da OS, extraída 1:1 do ServiceOrderForm (Fase 3, passo 4). */
import type { Dispatch, SetStateAction } from 'react';
import { Package, Pencil, Plus, Trash2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { supabase } from '@/integrations/supabase/client';
import { useI18n } from '@/i18n';
import { PartCardFormComponent, QuickDiscountPopover } from './form-parts';

interface PartsSectionProps {
  isNew: boolean;
  orderId?: string;
  orderData: any;
  parts: any[] | undefined;
  products: any[] | undefined;
  partsItemCount: number;
  partsRevenue: number;
  partsProfit: number;
  partsMarginPct: number;
  draftParts: any[];
  setDraftParts: Dispatch<SetStateAction<any[]>>;
  editingPart: Record<string, any>;
  setEditingPart: Dispatch<SetStateAction<Record<string, any>>>;
  openNewPartCards: string[];
  setOpenNewPartCards: Dispatch<SetStateAction<string[]>>;
  setPriceCalcCardKey: Dispatch<SetStateAction<string | null>>;
  addNewPartCard: (...args: any[]) => any;
  cancelPartCard: (...args: any[]) => any;
  handleConfirmNewPartCard: (...args: any[]) => any;
  handleConfirmEditPart: (...args: any[]) => any;
  startEditPersistedPart: (...args: any[]) => any;
  applyQuickDiscountToPart: (...args: any[]) => any;
  updatePartLine: any;
  removePart: any;
  addPart: any;
}

export function PartsSection(props: PartsSectionProps) {
  const {
    isNew, orderId, orderData, parts, products,
    partsItemCount, partsRevenue, partsProfit, partsMarginPct,
    draftParts, setDraftParts, editingPart, setEditingPart,
    openNewPartCards, setOpenNewPartCards, setPriceCalcCardKey,
    addNewPartCard, cancelPartCard, handleConfirmNewPartCard, handleConfirmEditPart,
    startEditPersistedPart, applyQuickDiscountToPart,
    updatePartLine, removePart, addPart,
  } = props;
  const { t, formatCurrency } = useI18n();

  return (
    <>
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
            discountPct?: number;
            discountAmount?: number;
            onExpand: () => void;
            onDelete: () => void;
            onApplyDiscount?: (pct: number, discountAmount: number) => void;
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
                {(opts.discountPct || 0) > 0 && (
                  <div className="text-[10px] font-normal text-destructive">−{opts.discountPct}%</div>
                )}
              </div>
              {opts.onApplyDiscount && (
                <QuickDiscountPopover
                  quantity={opts.quantity}
                  unitPrice={opts.unitPrice}
                  discountPct={opts.discountPct || 0}
                  discountAmount={opts.discountAmount || 0}
                  formatCurrency={formatCurrency}
                  onApply={opts.onApplyDiscount}
                />
              )}
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
                        clientId={orderData?.client_id}
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
                  discountPct: p.discount_pct,
                  discountAmount: p.discount_amount,
                  onApplyDiscount: (pct: number, discountAmount: number) => applyQuickDiscountToPart(p, pct, discountAmount),
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
                  total: Math.round((d.unit_sale * d.quantity - (d.discount_amount || 0)) * 100) / 100,
                  discountPct: d.discount_pct,
                  discountAmount: d.discount_amount,
                  onApplyDiscount: (pct: number, discountAmount: number) =>
                    setDraftParts((prev) => prev.map((x) => (x.tempId === d.tempId ? { ...x, discount_pct: pct, discount_amount: discountAmount } : x))),
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
                        discount_pct: d.discount_pct || 0,
                        discount_amount: d.discount_amount || 0,
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
                    clientId={orderData?.client_id}
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
    </>
  );
}
