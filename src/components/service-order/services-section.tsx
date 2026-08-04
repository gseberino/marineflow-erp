/* Seção E — Serviços de Mão de Obra da OS, extraída 1:1 do ServiceOrderForm (Fase 3, passo 5). */
import { useMemo, type Dispatch, type SetStateAction } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { Pencil, Plus, Trash2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { ServiceTimer } from '@/components/ServiceTimer';
import { useServiceOrderSteps } from '@/hooks/use-service-steps';
import { useLinesMissingSystem } from '@/hooks/use-service-systems';
import { LineSystemPicker } from './line-system-picker';
import { useI18n } from '@/i18n';
import { ServiceCardFormComponent, QuickDiscountPopover, BILLING_UNIT_LABELS } from './form-parts';

interface ServicesSectionProps {
  isNew: boolean;
  orderId?: string;
  services: any[] | undefined;
  soServices: any[] | undefined;
  appUsers: any[] | undefined;
  servicesItemCount: number;
  laborCost: number;
  billableHours: number;
  draftServices: any[];
  setDraftServices: Dispatch<SetStateAction<any[]>>;
  editingSvc: Record<string, any>;
  setEditingSvc: Dispatch<SetStateAction<Record<string, any>>>;
  openNewSvcCards: string[];
  setOpenNewSvcCards: Dispatch<SetStateAction<string[]>>;
  setShowNewServiceDialog: Dispatch<SetStateAction<boolean>>;
  addNewSvcCard: (...args: any[]) => any;
  cancelSvcCard: (...args: any[]) => any;
  handleConfirmNewSvcCard: (...args: any[]) => any;
  handleConfirmEditSvc: (...args: any[]) => any;
  startEditPersisted: (...args: any[]) => any;
  applyQuickDiscountToService: (...args: any[]) => any;
  updateSvcLine: any;
  removeService: any;
  addService: any;
}

export function ServicesSection(props: ServicesSectionProps) {
  const {
    isNew, orderId, services, soServices, appUsers,
    servicesItemCount, laborCost, billableHours,
    draftServices, setDraftServices, editingSvc, setEditingSvc,
    openNewSvcCards, setOpenNewSvcCards, setShowNewServiceDialog,
    addNewSvcCard, cancelSvcCard, handleConfirmNewSvcCard, handleConfirmEditSvc,
    startEditPersisted, applyQuickDiscountToService,
    updateSvcLine, removeService, addService,
  } = props;
  const queryClient = useQueryClient();
  // Linhas que já têm roteiro: nelas o cronômetro vira leitura, porque o tempo
  // passa a vir da soma dos passos (aba Roteiro). Dois donos do mesmo número é
  // como o dado se perde. O cache do react-query é o mesmo do painel do roteiro.
  const { data: routeSteps = [] } = useServiceOrderSteps(isNew ? undefined : orderId);
  const linesWithRoute = useMemo(
    () => new Set(routeSteps.map((s) => s.service_order_service_id).filter(Boolean) as string[]),
    [routeSteps],
  );
  // Serviço genérico ("diagnóstico no local") precisa dizer que sistema toca —
  // e precisa dizer AQUI, porque é o sistema que define o tempo previsto e, com
  // ele, o valor do orçamento.
  const { data: semSistema = [] } = useLinesMissingSystem(isNew ? undefined : orderId);
  const pendentePorLinha = useMemo(
    () => new Map(semSistema.map((l) => [l.line_id, l])),
    [semSistema],
  );
  const { t, formatCurrency } = useI18n();

  return (
    <>
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
            discountPct?: number;
            discountAmount?: number;
            onExpand: () => void;
            onDelete: () => void;
            onApplyDiscount?: (pct: number, discountAmount: number) => void;
            /** Cabe na própria linha, ao lado dos valores (ex.: cronômetro). */
            extra?: React.ReactNode;
            /**
             * Ocupa a largura toda LOGO ABAIXO da linha.
             *
             * Existe porque a linha é um flex horizontal e o nome do serviço vive
             * num `flex-1 min-w-0` com truncate: qualquer bloco largo colocado
             * entre os valores rouba o espaço dele e o nome some — foi o que
             * aconteceu com o aviso de classificação em 03/08. Bloco largo desce.
             */
            below?: React.ReactNode;
          }) => (
            <div
              key={opts.keyId}
              className={`border-b last:border-0 ${opts.isDraft ? 'bg-amber-50/40' : ''}`}
            >
            <div className="flex items-center gap-3 px-4 py-3">
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
            {opts.below && <div className="px-4 pb-3">{opts.below}</div>}
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
                  discountPct: s.discount_pct,
                  discountAmount: s.discount_amount,
                  onApplyDiscount: (pct: number, discountAmount: number) => applyQuickDiscountToService(s, pct, discountAmount),
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
                      managedByRoute={linesWithRoute.has(s.id)}
                      onUpdate={() =>
                        queryClient.invalidateQueries({ queryKey: ['so-services', orderId] })
                      }
                    />
                  ) : undefined,
                  // Abaixo da linha, com a largura toda: aqui o aviso não
                  // disputa espaço com o nome do serviço.
                  below: orderId && pendentePorLinha.has(s.id) ? (
                    <LineSystemPicker linha={pendentePorLinha.get(s.id)!} />
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
                  total: Math.round((d.unit_price_snapshot * d.quantity - (d.discount_amount || 0)) * 100) / 100,
                  discountPct: d.discount_pct,
                  discountAmount: d.discount_amount,
                  onApplyDiscount: (pct: number, discountAmount: number) =>
                    setDraftServices((prev) => prev.map((x) => (x.tempId === d.tempId ? { ...x, discount_pct: pct, discount_amount: discountAmount } : x))),
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
                        discount_pct: (d as any).discount_pct || 0,
                        discount_amount: (d as any).discount_amount || 0,
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
    </>
  );
}
