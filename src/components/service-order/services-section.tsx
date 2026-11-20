/* Seção E — Serviços de Mão de Obra da OS, extraída 1:1 do ServiceOrderForm (Fase 3, passo 5). */
import { useMemo, useState, type Dispatch, type SetStateAction } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { Loader2, Pencil, Plus, Sparkles, Trash2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { ServiceTimer } from '@/components/ServiceTimer';
import { useServiceOrderSteps } from '@/hooks/use-service-steps';
import { useLinesMissingSystem } from '@/hooks/use-service-systems';
import { LineSystemPicker } from './line-system-picker';
import { LineViaTecnico } from './line-via-tecnico';
import { useI18n } from '@/i18n';
import { ServiceCardFormComponent, QuickDiscountPopover, BILLING_UNIT_LABELS } from './form-parts';
import { AcoesDaLinha } from '@/components/AcoesDaLinha';
import { useConfirmacao } from '@/components/Confirmacao';
import { useOptionalAuth } from '@/hooks/use-auth';
import {
  useCancelarPedidoDeInstrucoes, useDecidirInstrucoes, useInstrucoesSugeridas, usePedirInstrucoes,
} from '@/hooks/use-instrucoes-sugeridas';
import { estadoDoPedido } from '@/lib/instrucoes-sugeridas';
import { motivoDaFalha } from '@/lib/orcamento-tecnico-ia';
import { numerarLinhas } from '../../../supabase/functions/_shared/linhas-da-os';

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
  // Excluir serviço ia num clique, sem confirmar (inventário de 03/10/2026): agora no menu, confirmado.
  const { pedir: pedirConfirmacao, dialogo } = useConfirmacao();

  // O número do serviço no papel (Q1 do dono, 17/11: mostrar). A lista já vem na ordem canônica (created_at, id), e a
  // cobrança conta no número (regra 4A). É o mesmo número do cartão da via e do "serviço N" no WhatsApp.
  const numeroPorLinha = useMemo(
    () => new Map(numerarLinhas((soServices || []) as Array<{ id: string }>).map((l) => [l.id, l.numero])),
    [soServices],
  );

  // Instrução sugerida pelo assistente (via v2, F2, canal A). Só o admin pede e aprova; OS nova não tem linha gravada.
  const admin = useOptionalAuth()?.user?.role === 'admin';
  const osDasSugestoes = !isNew && orderId && admin ? orderId : undefined;
  const { data: sugeridas } = useInstrucoesSugeridas(osDasSugestoes);
  const pedirInstrucoes = usePedirInstrucoes(osDasSugestoes);
  const decidirInstrucoes = useDecidirInstrucoes(osDasSugestoes);
  const cancelarPedido = useCancelarPedidoDeInstrucoes(osDasSugestoes);
  // As edições dos cartões (id da sugestão → texto): o "Aprovar todas" leva o que está escrito em cada um.
  const [edicoes, setEdicoes] = useState<Record<string, string>>({});
  const pendentes = useMemo(() => sugeridas?.pendentes ?? [], [sugeridas]);
  const sugestaoPorLinha = useMemo(() => new Map(pendentes.map((p) => [p.linha_id, p])), [pendentes]);
  const estadoDoAssistente = sugeridas ? estadoDoPedido(sugeridas) : 'livre';
  const assistenteTrabalhando = estadoDoAssistente === 'na_fila' || estadoDoAssistente === 'rascunhando';
  const ocupada = decidirInstrucoes.isPending;
  const textoDoCartao = (id: string, sugerido: string) => edicoes[id] ?? sugerido;
  const aprovarTodas = () => decidirInstrucoes.mutate(
    pendentes.map((p) => ({ id: p.id, acao: 'aprovar' as const, texto: textoDoCartao(p.id, p.texto) })),
    { onSuccess: () => setEdicoes({}) },
  );

  return (
    <>
      {dialogo}
      {/* E - Labor Services — always visible (with always-on entry row) */}
      <section className="rounded-xl border bg-card shadow-sm overflow-hidden">
        <div className="p-5 border-b">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <h2 className="font-semibold text-sm">{t.services.laborSection}</h2>
            {osDasSugestoes && sugeridas?.em_uso && assistenteTrabalhando && (
              <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
                <Loader2 className="h-3.5 w-3.5 animate-spin" />
                <span>
                  {estadoDoAssistente === 'rascunhando'
                    ? (sugeridas.job?.linhas === 1 ? 'Rascunhando 1 instrução…' : `Rascunhando ${sugeridas.job?.linhas ?? ''} instruções…`)
                    : 'Na fila: o assistente continua quando o computador do escritório voltar.'}
                </span>
                {sugeridas.job && (
                  <button
                    type="button"
                    className="underline underline-offset-2 hover:text-foreground"
                    onClick={() => cancelarPedido.mutate(sugeridas.job!.id)}
                    disabled={cancelarPedido.isPending}
                  >
                    Cancelar
                  </button>
                )}
              </div>
            )}
            {osDasSugestoes && sugeridas?.em_uso && !assistenteTrabalhando && sugeridas.elegiveis > 0 && (
              <Button
                size="sm"
                variant="outline"
                className="h-8 text-xs"
                onClick={() => pedirInstrucoes.mutate()}
                disabled={pedirInstrucoes.isPending}
                title="O assistente sugere a instrução ao técnico de cada serviço sem instrução. Só as que você aprovar saem na via."
              >
                <Sparkles className="h-3.5 w-3.5 mr-1" />
                {estadoDoAssistente === 'falhou' ? 'Tentar de novo' : 'Rascunhar instruções'} ({sugeridas.elegiveis})
              </Button>
            )}
          </div>
          {osDasSugestoes && estadoDoAssistente === 'falhou' && sugeridas?.job && (
            <p className="text-xs text-amber-700 dark:text-amber-400 mt-1">
              O pedido de instruções não terminou. {motivoDaFalha({ error_code: sugeridas.job.error_code, error: sugeridas.job.error })}
            </p>
          )}
          {isNew && (
            <p className="text-xs text-muted-foreground mt-1">
              Itens adicionados aqui serão salvos quando você criar a OS.
            </p>
          )}
        </div>

        {osDasSugestoes && pendentes.length > 0 && (
          <div className="px-5 py-2.5 border-b bg-sky-50/60 dark:bg-sky-950/30 flex flex-wrap items-center justify-between gap-2 text-xs">
            <span>
              {pendentes.length === 1
                ? '1 instrução sugerida pelo assistente espera sua aprovação.'
                : `${pendentes.length} instruções sugeridas pelo assistente esperam sua aprovação.`}
              {' '}Só as aprovadas saem na via do técnico.
            </span>
            <Button size="sm" className="h-7 text-xs" onClick={aprovarTodas} disabled={ocupada}>
              Aprovar todas
            </Button>
          </div>
        )}

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
            /** O número do serviço no papel (só linha gravada). */
            numero?: number;
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
                  {opts.numero != null && (
                    <span className="mr-1.5 text-muted-foreground tabular-nums" title="Número do serviço na via do técnico">
                      {opts.numero} ·
                    </span>
                  )}
                  <span>{opts.name}</span>
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
                title="Editar" aria-label="Editar este serviço"
              >
                <Pencil className="h-3.5 w-3.5" />
              </Button>
              <AcoesDaLinha
                rotulo={opts.name}
                menu={[{
                  texto: 'Excluir este serviço', icone: Trash2, perigo: true,
                  onClick: () => pedirConfirmacao({
                    titulo: `Excluir ${opts.name}?`,
                    descricao: opts.isDraft ? 'O serviço sai do rascunho.' : 'O serviço sai da OS e o total é recalculado.',
                    confirmar: 'Excluir',
                    acao: opts.onDelete,
                  }),
                }]}
              />
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
                const sugestao = sugestaoPorLinha.get(s.id);
                return renderCollapsedRow({
                  keyId: s.id,
                  numero: numeroPorLinha.get(s.id),
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
                  below: orderId ? (
                    <>
                      {pendentePorLinha.has(s.id) && (
                        <LineSystemPicker linha={pendentePorLinha.get(s.id)!} />
                      )}
                      {/* Como a linha sai na via do técnico (fase 2, 01/10/2026). */}
                      <LineViaTecnico
                        line={s}
                        orderId={orderId}
                        sugestao={sugestao ? {
                          sugestao,
                          texto: textoDoCartao(sugestao.id, sugestao.texto),
                          onEditar: (texto) => setEdicoes((prev) => ({ ...prev, [sugestao.id]: texto })),
                          onAprovar: (texto) => decidirInstrucoes.mutate([{ id: sugestao.id, acao: 'aprovar', texto }]),
                          onDescartar: () => decidirInstrucoes.mutate([{ id: sugestao.id, acao: 'descartar' }]),
                          ocupada,
                        } : undefined}
                      />
                    </>
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
