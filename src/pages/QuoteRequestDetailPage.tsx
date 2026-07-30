import { useMemo, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import {
  AlertTriangle, ArrowLeft, Award, Check, CircleDollarSign, Clock, Handshake,
  Package, ShoppingCart, Sparkles, Truck, Undo2, X,
} from 'lucide-react';
import { toast } from 'sonner';
import { PageHeader } from '@/components/PageHeader';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card, CardContent } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { cn } from '@/lib/utils';
import { useSuppliers } from '@/hooks/use-suppliers';
import {
  useApplyQuotePrice, useCloseQuoteRequest, useCreatePOsFromQuote, useQuoteRequest,
  useRecordQuoteResponse, useReopenQuoteRequest, QUOTE_STATUS_LABELS,
  type BasketChoice,
} from '@/hooks/use-quote-requests';
import {
  agingLevel, buildQuoteComparison, businessDaysSince, computeBasketTotal,
  suggestBestBasket, type Offer,
} from '@/lib/quote-comparison';

/**
 * Mapa de cotação — onde a decisão de compra acontece.
 *
 * O mapa clássico do mercado é uma matriz (itens em linhas × fornecedores em colunas).
 * Aqui ela é montada como um bloco por item com as ofertas ordenadas dentro, por uma
 * razão dura: matriz com N fornecedores só cabe na tela com rolagem lateral, e
 * rolagem lateral é proibida neste produto. O bloco por item preserva o que a matriz
 * dá de valor — comparar lado a lado, ver o melhor, escolher por linha — e escala
 * para qualquer número de fornecedores, inclusive no celular.
 */

const fmtBRL = (v: number) =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);

const fmtQty = (v: number) =>
  new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 3 }).format(v);

export default function QuoteRequestDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { data: quote, isLoading } = useQuoteRequest(id);
  const { data: suppliers } = useSuppliers();

  const recordResponse = useRecordQuoteResponse();
  const applyPrice = useApplyQuotePrice();
  const createPOs = useCreatePOsFromQuote();
  const closeQuote = useCloseQuoteRequest();
  const reopenQuote = useReopenQuoteRequest();

  /** item → fornecedor escolhido */
  const [chosen, setChosen] = useState<Record<string, string | undefined>>({});
  /** custos de pacote informados na negociação (não persistidos — ver nota abaixo) */
  const [freight, setFreight] = useState<Record<string, number>>({});
  const [confirmDirect, setConfirmDirect] = useState(false);
  const [salePriceItem, setSalePriceItem] = useState<{ itemId: string; serviceId: string; price: number; description: string } | null>(null);

  const supplierById = useMemo(() => {
    const map = new Map<string, any>();
    for (const s of suppliers ?? []) map.set((s as any).id, s);
    return map;
  }, [suppliers]);

  const comparison = useMemo(() => {
    if (!quote) return null;
    const consulted = quote.sent_supplier_ids ?? [];
    const responded = (quote.quote_responses ?? []).map(r => r.supplier_id);
    const ids = [...new Set([...consulted, ...responded])];
    return buildQuoteComparison(
      (quote.quote_request_items ?? []).map(i => ({
        id: i.id, position: i.position, description: i.description,
        quantity: i.quantity, product_id: i.product_id,
      })),
      (quote.quote_responses ?? []).map(r => ({
        id: r.id, supplier_id: r.supplier_id, quote_request_item_id: r.quote_request_item_id,
        unit_price: r.unit_price, lead_time_days: r.lead_time_days,
        confirmed: r.confirmed, source: r.source,
      })),
      ids.map(sid => ({
        id: sid,
        name: supplierById.get(sid)?.name ?? 'Fornecedor',
        freight: freight[sid] ?? 0,
      })),
    );
  }, [quote, supplierById, freight]);

  const basket = useMemo(
    () => (comparison ? computeBasketTotal(comparison, chosen) : null),
    [comparison, chosen],
  );

  const itemById = useMemo(() => {
    const map = new Map<string, any>();
    for (const i of quote?.quote_request_items ?? []) map.set(i.id, i);
    return map;
  }, [quote]);

  if (isLoading) {
    return (
      <div className="space-y-4">
        <Skeleton className="h-10 w-64" />
        <Skeleton className="h-32 w-full" />
        <Skeleton className="h-64 w-full" />
      </div>
    );
  }

  if (!quote || !comparison || !basket) {
    return (
      <Card>
        <CardContent className="flex flex-col items-center gap-3 py-12 text-center">
          <p className="font-medium">Cotação não encontrada</p>
          <Button variant="outline" onClick={() => navigate('/purchasing/quotes')}>
            Voltar para as cotações
          </Button>
        </CardContent>
      </Card>
    );
  }

  const days = businessDaysSince(quote.created_at);
  const aging = agingLevel(days);
  const isOpen = quote.status === 'open';
  const noResponses = comparison.respondedSupplierIds.length === 0;

  function handleChoose(itemId: string, supplierId: string) {
    setChosen(prev => ({ ...prev, [itemId]: prev[itemId] === supplierId ? undefined : supplierId }));
  }

  function handleSuggest() {
    const suggestion = suggestBestBasket(comparison!);
    if (!Object.keys(suggestion).length) {
      toast.error('Nenhum preço registrado ainda — não há o que sugerir.');
      return;
    }
    setChosen(suggestion);
    toast.success('Selecionado o melhor preço de cada item. Ajuste o que quiser antes de gerar a compra.');
  }

  function buildChoices(): BasketChoice[] {
    return basket!.lines.map(line => {
      const item = itemById.get(line.itemId);
      const offer = comparison!.rows.find(r => r.itemId === line.itemId)!.offers[line.supplierId];
      return {
        itemId: line.itemId,
        supplierId: line.supplierId,
        description: item?.description ?? 'Item',
        quantity: Number(item?.quantity) || 0,
        unitPrice: offer.unitPrice,
        productId: item?.product_id ?? null,
      };
    });
  }

  async function handleGeneratePOs() {
    await createPOs.mutateAsync({
      quoteRequestId: quote!.id,
      quoteCode: quote!.code,
      serviceOrderId: quote!.service_order_id,
      choices: buildChoices(),
    });
    navigate('/purchase-orders');
  }

  /** Compra direta: fechou no WhatsApp, sem emitir pedido formal. */
  async function handleDirectPurchase() {
    const choices = buildChoices();
    const names = [...new Set(choices.map(c => supplierById.get(c.supplierId)?.name ?? 'fornecedor'))];
    await closeQuote.mutateAsync({
      id: quote!.id,
      note: `Compra direta (sem OC) com ${names.join(', ')} — ${fmtBRL(basket!.total)}.`,
    });
    setConfirmDirect(false);
  }

  async function handleApplyCosts() {
    const choices = buildChoices();
    let applied = 0;
    let needsSaleConfirm: typeof salePriceItem = null;

    for (const c of choices) {
      const item = itemById.get(c.itemId);
      if (!item) continue;
      if (item.service_order_part_id) {
        await applyPrice.mutateAsync({
          itemId: c.itemId,
          unitPrice: c.unitPrice,
          serviceOrderPartId: item.service_order_part_id,
          serviceOrderId: quote!.service_order_id,
        });
        applied++;
      } else if (item.service_order_service_id && !needsSaleConfirm) {
        // Material avulso mexe no preço AO CLIENTE — um por vez, com confirmação.
        needsSaleConfirm = {
          itemId: c.itemId,
          serviceId: item.service_order_service_id,
          price: c.unitPrice,
          description: c.description,
        };
      }
    }

    if (applied === 0 && !needsSaleConfirm) {
      toast.error('Nenhum item escolhido veio de um orçamento — não há linha para atualizar.');
    }
    if (needsSaleConfirm) setSalePriceItem(needsSaleConfirm);
  }

  const hasOrigin = (quote.quote_request_items ?? []).some(
    i => i.service_order_part_id || i.service_order_service_id,
  );

  return (
    <div className="space-y-6 animate-fade-in pb-28">
      <div>
        <Link
          to="/purchasing/quotes"
          className="inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground"
        >
          <ArrowLeft className="h-3.5 w-3.5" /> Cotações
        </Link>
      </div>

      <PageHeader
        title={quote.code}
        description={
          quote.service_orders
            ? `${quote.service_orders.service_order_number}${quote.service_orders.clients?.name ? ` · ${quote.service_orders.clients.name}` : ''}`
            : 'Cotação sem vínculo com orçamento'
        }
      >
        {isOpen ? (
          <>
            <Button variant="outline" size="sm" className="gap-1" onClick={handleSuggest}>
              <Sparkles className="h-3.5 w-3.5" /> Melhor preço
            </Button>
            <Button
              variant="outline"
              size="sm"
              className="gap-1 text-muted-foreground"
              onClick={() => closeQuote.mutate({ id: quote.id, cancel: true })}
            >
              <X className="h-3.5 w-3.5" /> Cancelar
            </Button>
          </>
        ) : (
          <Button variant="outline" size="sm" className="gap-1" onClick={() => reopenQuote.mutate(quote.id)}>
            <Undo2 className="h-3.5 w-3.5" /> Reabrir
          </Button>
        )}
      </PageHeader>

      {/* Estado da cotação: o que precisa de atenção vem antes dos números. */}
      <div className="flex flex-wrap items-center gap-2 text-sm">
        <span className={cn(
          'rounded-full px-2.5 py-1 text-xs font-medium',
          isOpen ? 'bg-blue-100 text-blue-700 dark:bg-blue-900/40 dark:text-blue-300'
                 : 'bg-muted text-muted-foreground',
        )}>
          {QUOTE_STATUS_LABELS[quote.status]}
        </span>
        {isOpen && (
          <span className={cn(
            'inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-medium',
            aging === 'late' ? 'bg-red-100 text-red-700 dark:bg-red-900/40 dark:text-red-300'
            : aging === 'due' ? 'bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-300'
            : 'bg-muted text-muted-foreground',
          )}>
            <Clock className="h-3 w-3" />
            {days === 0 ? 'criada hoje' : `${days} ${days === 1 ? 'dia útil' : 'dias úteis'}`}
          </span>
        )}
        <span className="text-muted-foreground">
          {comparison.itemCount} {comparison.itemCount === 1 ? 'item' : 'itens'} ·{' '}
          {comparison.respondedSupplierIds.length} de {(quote.sent_supplier_ids ?? []).length || '—'} responderam
        </span>
      </div>

      {quote.notes && (
        <p className="rounded-lg border bg-muted/40 p-3 text-sm text-muted-foreground">{quote.notes}</p>
      )}

      {noResponses ? (
        <Card className={aging === 'fresh' ? undefined : 'border-amber-500/40 bg-amber-500/5'}>
          <CardContent className="space-y-3 py-8 text-center">
            <Handshake className="mx-auto h-8 w-8 text-muted-foreground" />
            <div>
              <p className="font-medium">Nenhum preço registrado ainda</p>
              <p className="mx-auto mt-1 max-w-md text-sm text-muted-foreground">
                {aging === 'fresh'
                  ? 'Quando o fornecedor responder, registre o preço item a item abaixo — o comparativo se monta sozinho.'
                  : `Enviada há ${days} dias úteis sem resposta. A janela normal é de 3 a 5 dias úteis: vale cobrar.`}
              </p>
            </div>
          </CardContent>
        </Card>
      ) : (
        <section className="space-y-2">
          <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">
            Pacotes por fornecedor
          </h2>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-3">
            {comparison.packages.map(pkg => (
              <div
                key={pkg.supplierId}
                className={cn(
                  'rounded-xl border bg-card p-4 shadow-sm',
                  pkg.isBestPackage && 'border-emerald-500/60 ring-1 ring-emerald-500/30',
                )}
              >
                <div className="flex items-start justify-between gap-2">
                  <p className="min-w-0 flex-1 font-medium leading-tight">{pkg.name}</p>
                  {pkg.isBestPackage && (
                    <span className="inline-flex shrink-0 items-center gap-1 rounded-full bg-emerald-100 px-2 py-0.5 text-[11px] font-medium text-emerald-700 dark:bg-emerald-900/40 dark:text-emerald-300">
                      <Award className="h-3 w-3" /> melhor pacote
                    </span>
                  )}
                </div>

                <p className="mt-2 text-xl font-semibold tabular-nums">{fmtBRL(pkg.packageTotal)}</p>
                <div className="mt-1 space-y-0.5 text-xs text-muted-foreground">
                  <p className={cn(!pkg.isComplete && 'font-medium text-amber-600 dark:text-amber-400')}>
                    {pkg.quotedItems} de {comparison.itemCount} itens
                    {!pkg.isComplete && ' — pacote incompleto'}
                  </p>
                  {pkg.maxLeadTimeDays !== null && (
                    <p className="inline-flex items-center gap-1">
                      <Truck className="h-3 w-3" /> entrega em até {pkg.maxLeadTimeDays} dias
                    </p>
                  )}
                </div>

                <div className="mt-3 flex items-center gap-2 border-t pt-2">
                  <label className="text-xs text-muted-foreground" htmlFor={`freight-${pkg.supplierId}`}>
                    Frete
                  </label>
                  <Input
                    id={`freight-${pkg.supplierId}`}
                    type="number"
                    inputMode="decimal"
                    min={0}
                    step="any"
                    value={freight[pkg.supplierId] ?? ''}
                    onChange={e =>
                      setFreight(prev => ({ ...prev, [pkg.supplierId]: parseFloat(e.target.value) || 0 }))
                    }
                    placeholder="0,00"
                    className="h-7 w-24 text-right text-xs"
                  />
                </div>
              </div>
            ))}
          </div>
          {comparison.splitSavings > 0 && (
            <p className="rounded-lg border border-emerald-500/40 bg-emerald-500/5 p-3 text-sm">
              Dividindo a compra entre fornecedores, o total cai para{' '}
              <strong className="tabular-nums">{fmtBRL(comparison.bestPerLineTotal)}</strong> —{' '}
              <strong className="tabular-nums">{fmtBRL(comparison.splitSavings)}</strong> a menos que
              comprar tudo do melhor pacote único.
            </p>
          )}
        </section>
      )}

      <section className="space-y-2">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">
            Itens e ofertas
          </h2>
          {comparison.unquotedCount > 0 && (
            <span className="inline-flex items-center gap-1 text-xs text-amber-600 dark:text-amber-400">
              <AlertTriangle className="h-3.5 w-3.5" />
              {comparison.unquotedCount} {comparison.unquotedCount === 1 ? 'item sem' : 'itens sem'} nenhum preço
            </span>
          )}
        </div>

        <div className="space-y-3">
          {comparison.rows.map(row => {
            const offers = Object.values(row.offers).sort((a, b) => a.unitPrice - b.unitPrice);
            const item = itemById.get(row.itemId);
            const chosenSupplier = chosen[row.itemId];
            return (
              <div key={row.itemId} className="rounded-xl border bg-card shadow-sm">
                <div className="flex flex-wrap items-baseline justify-between gap-2 border-b p-3">
                  <div className="min-w-0 flex-1">
                    <p className="font-medium leading-tight">
                      <span className="mr-1.5 text-xs tabular-nums text-muted-foreground">{row.position}.</span>
                      {row.description}
                    </p>
                    <p className="mt-0.5 text-xs text-muted-foreground">
                      {fmtQty(row.quantity)} {item?.product_id ? 'un · do catálogo' : 'un · texto livre'}
                    </p>
                  </div>
                  {row.unquoted && (
                    <span className="rounded-full bg-amber-100 px-2 py-0.5 text-[11px] font-medium text-amber-800 dark:bg-amber-900/40 dark:text-amber-300">
                      sem preço
                    </span>
                  )}
                </div>

                <div className="divide-y">
                  {offers.map(offer => (
                    <OfferRow
                      key={offer.responseId}
                      offer={offer}
                      supplierName={supplierById.get(offer.supplierId)?.name ?? 'Fornecedor'}
                      isChosen={chosenSupplier === offer.supplierId}
                      disabled={!isOpen}
                      onChoose={() => handleChoose(row.itemId, offer.supplierId)}
                    />
                  ))}
                </div>

                {isOpen && (
                  <PriceEntryRow
                    consultedSupplierIds={[...new Set([
                      ...(quote.sent_supplier_ids ?? []),
                      ...comparison.respondedSupplierIds,
                    ])]}
                    alreadyQuoted={Object.keys(row.offers)}
                    supplierById={supplierById}
                    pending={recordResponse.isPending}
                    onSubmit={(supplierId, unitPrice, leadTimeDays) =>
                      recordResponse.mutate({
                        quoteRequestId: quote.id,
                        supplierId,
                        itemId: row.itemId,
                        unitPrice,
                        leadTimeDays,
                      })
                    }
                  />
                )}
              </div>
            );
          })}
        </div>
      </section>

      {/* Barra da decisão: só aparece quando há escolha, e some quando fechada. */}
      {isOpen && basket.chosenCount > 0 && (
        <div className="fixed inset-x-0 bottom-0 z-40 border-t bg-card/95 p-3 shadow-lg backdrop-blur supports-[backdrop-filter]:bg-card/80">
          <div className="mx-auto flex max-w-6xl flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
            <div className="text-sm">
              <p className="font-medium">
                {basket.chosenCount} de {comparison.itemCount} itens escolhidos
                {basket.supplierCount > 1 && ` · ${basket.supplierCount} fornecedores`}
              </p>
              <p className="text-muted-foreground">
                Total da cesta: <strong className="tabular-nums text-foreground">{fmtBRL(basket.total)}</strong>
              </p>
            </div>
            <div className="flex flex-wrap gap-2">
              {hasOrigin && (
                <Button variant="outline" size="sm" className="gap-1" onClick={handleApplyCosts} disabled={applyPrice.isPending}>
                  <CircleDollarSign className="h-3.5 w-3.5" /> Aplicar no orçamento
                </Button>
              )}
              <Button variant="outline" size="sm" className="gap-1" onClick={() => setConfirmDirect(true)}>
                <Package className="h-3.5 w-3.5" /> Compra direta
              </Button>
              <Button size="sm" className="gap-1" onClick={handleGeneratePOs} disabled={createPOs.isPending}>
                <ShoppingCart className="h-3.5 w-3.5" />
                {basket.supplierCount > 1 ? `Gerar ${basket.supplierCount} OCs` : 'Gerar ordem de compra'}
              </Button>
            </div>
          </div>
        </div>
      )}

      <AlertDialog open={confirmDirect} onOpenChange={setConfirmDirect}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Registrar compra direta?</AlertDialogTitle>
            <AlertDialogDescription>
              A cotação será fechada com a escolha registrada na observação, <strong>sem gerar ordem de
              compra</strong>. Use quando você já fechou com o fornecedor e a nota vai entrar depois
              pela Entrada de Mercadoria. Sem OC não há confronto pedido × nota nem cobrança de entrega.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Voltar</AlertDialogCancel>
            <AlertDialogAction onClick={handleDirectPurchase}>
              Fechar como compra direta
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      <AlertDialog open={!!salePriceItem} onOpenChange={o => !o && setSalePriceItem(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Este item não tem custo separado</AlertDialogTitle>
            <AlertDialogDescription>
              <strong>{salePriceItem?.description}</strong> foi digitado livremente no orçamento e só tem
              preço ao cliente — não há campo de custo. Aplicar {fmtBRL(salePriceItem?.price ?? 0)} vai
              alterar <strong>o valor que o cliente paga</strong> e o total do orçamento, sem nenhuma
              margem sobre a compra. Confirma?
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Não aplicar</AlertDialogCancel>
            <AlertDialogAction
              onClick={async () => {
                if (!salePriceItem) return;
                await applyPrice.mutateAsync({
                  itemId: salePriceItem.itemId,
                  unitPrice: salePriceItem.price,
                  serviceOrderServiceId: salePriceItem.serviceId,
                  serviceOrderId: quote.service_order_id,
                  asSalePrice: true,
                });
                setSalePriceItem(null);
              }}
            >
              Aplicar como preço ao cliente
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}

function OfferRow({
  offer, supplierName, isChosen, disabled, onChoose,
}: {
  offer: Offer;
  supplierName: string;
  isChosen: boolean;
  disabled: boolean;
  onChoose: () => void;
}) {
  return (
    <div className={cn('flex flex-wrap items-center gap-x-3 gap-y-1 p-3', isChosen && 'bg-primary/5')}>
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-medium">{supplierName}</p>
        <div className="mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-0.5 text-xs text-muted-foreground">
          <span className="tabular-nums">{fmtBRL(offer.unitPrice)} / un</span>
          {offer.leadTimeDays !== null && <span>· {offer.leadTimeDays} dias</span>}
          {offer.isBestPrice && (
            <span className="font-medium text-emerald-600 dark:text-emerald-400">· melhor preço</span>
          )}
          {offer.isOutlier && (
            <span className="inline-flex items-center gap-0.5 font-medium text-amber-600 dark:text-amber-400">
              <AlertTriangle className="h-3 w-3" />
              {/* Uma string única: fragmentar em nós separados atrapalha leitor de tela. */}
              <span>{`${Math.round(offer.deviationFromMean * 100)}% acima da média`}</span>
            </span>
          )}
          {offer.source !== 'manual' && <span className="opacity-70">· via {offer.source}</span>}
        </div>
      </div>
      <p className="shrink-0 text-sm font-semibold tabular-nums">{fmtBRL(offer.lineTotal)}</p>
      <Button
        size="sm"
        variant={isChosen ? 'default' : 'outline'}
        className="h-7 shrink-0 gap-1 px-2 text-xs"
        onClick={onChoose}
        disabled={disabled}
      >
        {isChosen ? <><Check className="h-3 w-3" /> escolhido</> : 'escolher'}
      </Button>
    </div>
  );
}

/** Registro manual de preço: o que a tela dá e o agente já tinha. */
function PriceEntryRow({
  consultedSupplierIds, alreadyQuoted, supplierById, pending, onSubmit,
}: {
  consultedSupplierIds: string[];
  alreadyQuoted: string[];
  supplierById: Map<string, any>;
  pending: boolean;
  onSubmit: (supplierId: string, unitPrice: number, leadTimeDays: number | null) => void;
}) {
  const [supplierId, setSupplierId] = useState('');
  const [price, setPrice] = useState('');
  const [lead, setLead] = useState('');

  const options = consultedSupplierIds.filter(id => !alreadyQuoted.includes(id));
  if (!options.length) return null;

  function submit() {
    const value = parseFloat(price.replace(',', '.'));
    if (!supplierId) { toast.error('Escolha o fornecedor.'); return; }
    if (!Number.isFinite(value) || value <= 0) { toast.error('Informe o preço unitário.'); return; }
    onSubmit(supplierId, value, lead ? parseInt(lead, 10) : null);
    setPrice(''); setLead(''); setSupplierId('');
  }

  return (
    <div className="flex flex-wrap items-end gap-2 border-t bg-muted/30 p-3">
      <div className="min-w-[10rem] flex-1">
        <label className="text-[11px] uppercase tracking-wide text-muted-foreground">Fornecedor</label>
        <select
          value={supplierId}
          onChange={e => setSupplierId(e.target.value)}
          className="mt-0.5 h-8 w-full rounded-md border border-input bg-background px-2 text-sm"
        >
          <option value="">selecione…</option>
          {options.map(id => (
            <option key={id} value={id}>{supplierById.get(id)?.name ?? 'Fornecedor'}</option>
          ))}
        </select>
      </div>
      <div className="w-24">
        <label className="text-[11px] uppercase tracking-wide text-muted-foreground">R$ / un</label>
        <Input
          value={price}
          onChange={e => setPrice(e.target.value)}
          inputMode="decimal"
          placeholder="0,00"
          className="mt-0.5 h-8 text-right"
        />
      </div>
      <div className="w-20">
        <label className="text-[11px] uppercase tracking-wide text-muted-foreground">dias</label>
        <Input
          value={lead}
          onChange={e => setLead(e.target.value)}
          inputMode="numeric"
          placeholder="—"
          className="mt-0.5 h-8 text-right"
        />
      </div>
      <Button size="sm" variant="secondary" className="h-8" onClick={submit} disabled={pending}>
        Registrar
      </Button>
    </div>
  );
}
