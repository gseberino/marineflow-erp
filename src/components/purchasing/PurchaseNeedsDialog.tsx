import { useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  AlertTriangle, CheckCircle2, ClipboardList, Clock, ShoppingCart, Truck,
} from 'lucide-react';
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { cn } from '@/lib/utils';
import { usePurchaseNeeds } from '@/hooks/use-purchase-needs';
import { useCreatePOsFromShortages } from '@/hooks/use-purchase-orders';
import { useSOLinkedQuotes } from '@/hooks/use-quote-requests';
import { agingLevel, businessDaysSince } from '@/lib/quote-comparison';
import { NEED_STATUS_LABELS, type NeedStatus, type PurchaseNeedItem } from '@/lib/purchase-needs';
import { NewQuoteRequestDialog } from '@/components/purchasing/NewQuoteRequestDialog';

/**
 * O aviso de compra na aprovação do orçamento.
 *
 * Aparece uma vez, no instante em que o orçamento vira OS — o mesmo lugar onde o
 * SAP Business One abre o assistente de compras. É o momento em que a decisão é
 * barata: o cliente acabou de aprovar, ninguém agendou nada ainda, e dá tempo de
 * cotar antes de prometer prazo.
 *
 * NÃO BLOQUEIA. A decisão de modelo de estoque já registrada neste sistema é
 * "falta de estoque não bloqueia o orçamento, só avisa na efetivação", e o dono
 * confirmou. Fechar sem agir é uma escolha legítima: a regra R16 do motor de
 * automação cria a tarefa e o assunto volta sozinho.
 */

const STATUS_STYLE: Record<NeedStatus, { dot: string; text: string }> = {
  missing: { dot: 'bg-destructive', text: 'text-destructive' },
  partial: { dot: 'bg-amber-500', text: 'text-amber-600 dark:text-amber-400' },
  uncatalogued: { dot: 'bg-amber-500', text: 'text-amber-600 dark:text-amber-400' },
  on_order: { dot: 'bg-blue-500', text: 'text-blue-600 dark:text-blue-400' },
  ok: { dot: 'bg-emerald-500', text: 'text-emerald-600 dark:text-emerald-400' },
};

const fmtBRL = (v: number) =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);

const fmtQty = (v: number) =>
  new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 3 }).format(v);

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  serviceOrderId: string;
  serviceOrderNumber?: string | null;
  clientName?: string | null;
}

export function PurchaseNeedsDialog({
  open, onOpenChange, serviceOrderId, serviceOrderNumber, clientName,
}: Props) {
  const navigate = useNavigate();
  const { data: needs, isLoading } = usePurchaseNeeds(serviceOrderId, open);
  const { data: linkedQuotes } = useSOLinkedQuotes(open ? serviceOrderId : undefined);
  const createPOs = useCreatePOsFromShortages();
  const [quoteOpen, setQuoteOpen] = useState(false);

  const openQuote = useMemo(
    () => (linkedQuotes ?? []).find(q => q.status === 'open'),
    [linkedQuotes],
  );

  const quoteAging = useMemo(() => {
    if (!openQuote) return null;
    const days = businessDaysSince(openQuote.created_at);
    const priced = (openQuote.quote_responses ?? []).filter(
      r => r.quote_request_item_id && Number(r.unit_price) > 0,
    );
    return {
      days,
      level: agingLevel(days),
      responded: new Set(priced.map(r => r.supplier_id)).size,
      hasAnswer: priced.length > 0,
    };
  }, [openQuote]);

  const prefilled = useMemo(
    () => (needs?.shortages ?? []).map(s => ({
      description: s.description,
      quantity: s.shortage,
      product_id: s.productId,
      service_order_part_id: s.origin === 'part' ? s.sourceId : null,
      service_order_service_id: s.origin === 'free_text' ? s.sourceId : null,
    })),
    [needs],
  );

  const label = serviceOrderNumber
    ? `${serviceOrderNumber}${clientName ? ` · ${clientName}` : ''}`
    : 'esta OS';

  return (
    <>
      <Dialog open={open} onOpenChange={onOpenChange}>
        <DialogContent className="max-h-[92vh] max-w-xl overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <ShoppingCart className="h-5 w-5 text-primary" />
              {isLoading
                ? 'Verificando o estoque…'
                : needs?.shortageCount
                  ? `${needs.shortageCount} ${needs.shortageCount === 1 ? 'item precisa' : 'itens precisam'} de compra`
                  : 'Tudo disponível para executar'}
            </DialogTitle>
            <DialogDescription>
              {serviceOrderNumber ? `${serviceOrderNumber} aprovada.` : 'Orçamento aprovado.'}{' '}
              {isLoading
                ? 'Conferindo disponível (físico menos reservado) e o que já está pedido.'
                : needs?.shortageCount
                  ? 'Você pode resolver agora ou deixar para depois — a pendência não se perde.'
                  : 'Nenhuma peça em falta, nada a comprar.'}
            </DialogDescription>
          </DialogHeader>

          {isLoading ? (
            <div className="space-y-2">
              {[0, 1, 2].map(i => <Skeleton key={i} className="h-12 w-full" />)}
            </div>
          ) : (
            <div className="space-y-4">
              {/* Cotação que já existe para esta OS: o erro clássico aqui seria
                  o operador abrir uma segunda cotação dos mesmos itens. */}
              {openQuote && quoteAging && (
                <div className={cn(
                  'rounded-lg border p-3',
                  quoteAging.level === 'late' ? 'border-destructive/40 bg-destructive/5'
                  : quoteAging.hasAnswer ? 'border-primary/40 bg-primary/5'
                  : 'border-amber-500/40 bg-amber-500/5',
                )}>
                  <p className="flex flex-wrap items-center gap-x-2 gap-y-1 text-sm font-medium">
                    <ClipboardList className="h-4 w-4 shrink-0" />
                    Já existe a {openQuote.code} para esta OS
                  </p>
                  <p className="mt-1 text-xs text-muted-foreground">
                    {(openQuote.sent_supplier_ids ?? []).length} fornecedor(es) ·{' '}
                    {quoteAging.hasAnswer
                      ? `${quoteAging.responded} respondeu(ram) — falta decidir`
                      : quoteAging.days === 0
                        ? 'criada hoje, sem resposta'
                        : `sem resposta há ${quoteAging.days} ${quoteAging.days === 1 ? 'dia útil' : 'dias úteis'}`}
                  </p>
                  <Button
                    size="sm"
                    variant="outline"
                    className="mt-2 h-7 gap-1 text-xs"
                    onClick={() => {
                      onOpenChange(false);
                      navigate(`/purchasing/quotes/${openQuote.id}`);
                    }}
                  >
                    {quoteAging.hasAnswer ? 'Comparar ofertas' : 'Abrir cotação'}
                  </Button>
                </div>
              )}

              {needs && needs.items.length > 0 && (
                <ul className="space-y-1.5">
                  {[...needs.shortages, ...needs.items.filter(i => i.shortage === 0)].map(item => (
                    <NeedRow key={`${item.origin}-${item.sourceId}`} item={item} />
                  ))}
                </ul>
              )}

              {needs && needs.items.length === 0 && (
                <p className="rounded-lg border bg-muted/40 p-3 text-sm text-muted-foreground">
                  Esta OS não tem peça nem material lançado — nada a comprar.
                </p>
              )}

              {needs && needs.estimatedCost > 0 && (
                <p className="text-sm text-muted-foreground">
                  Investimento estimado no que falta:{' '}
                  <strong className="tabular-nums text-foreground">{fmtBRL(needs.estimatedCost)}</strong>
                  <span className="block text-xs">pelo último custo conhecido — a cotação dá o número real.</span>
                </p>
              )}
            </div>
          )}

          <DialogFooter className="flex-col gap-2 sm:flex-row">
            <Button variant="ghost" onClick={() => onOpenChange(false)} className="sm:mr-auto">
              {needs?.shortageCount ? 'Depois' : 'Fechar'}
            </Button>
            {!!needs?.shortageCount && (
              <>
                <Button variant="outline" className="gap-1" onClick={() => setQuoteOpen(true)}>
                  <ClipboardList className="h-4 w-4" />
                  {openQuote ? 'Nova cotação' : `Cotar ${needs.shortageCount} ${needs.shortageCount === 1 ? 'item' : 'itens'}`}
                </Button>
                <Button
                  className="gap-1"
                  disabled={createPOs.isPending}
                  onClick={async () => {
                    await createPOs.mutateAsync({
                      serviceOrderId,
                      items: (needs?.shortages ?? []).map(s => ({
                        productId: s.productId,
                        description: s.description,
                        quantity: s.shortage,
                        unitCost: s.unitCost,
                      })),
                    });
                    onOpenChange(false);
                    navigate('/purchase-orders');
                  }}
                >
                  <Truck className="h-4 w-4" />
                  {createPOs.isPending ? 'Gerando…' : 'Gerar ordem de compra'}
                </Button>
              </>
            )}
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <NewQuoteRequestDialog
        open={quoteOpen}
        onOpenChange={v => {
          setQuoteOpen(v);
          if (!v) onOpenChange(false);
        }}
        serviceOrderId={serviceOrderId}
        serviceOrderLabel={label}
        prefilledItems={prefilled}
      />
    </>
  );
}

function NeedRow({ item }: { item: PurchaseNeedItem }) {
  const style = STATUS_STYLE[item.status];
  const covered = item.shortage === 0;
  return (
    <li className="flex items-start gap-2.5 rounded-lg border bg-card p-2.5">
      <span className={cn('mt-1.5 h-2 w-2 shrink-0 rounded-full', style.dot)} aria-hidden="true" />
      <div className="min-w-0 flex-1">
        <p className={cn('truncate text-sm', covered ? 'text-muted-foreground' : 'font-medium')}>
          {item.description}
        </p>
        <p className="mt-0.5 text-xs text-muted-foreground">
          precisa {fmtQty(item.required)}
          {item.status !== 'uncatalogued' && ` · disponível ${fmtQty(item.available)}`}
          {item.onOrder > 0 && ` · pedido ${fmtQty(item.onOrder)}`}
        </p>
      </div>
      <span className={cn('shrink-0 text-xs font-medium', style.text)}>
        {covered
          ? (item.status === 'on_order'
              ? <span className="inline-flex items-center gap-1"><Clock className="h-3 w-3" />{NEED_STATUS_LABELS[item.status]}</span>
              : <span className="inline-flex items-center gap-1"><CheckCircle2 className="h-3 w-3" />{NEED_STATUS_LABELS[item.status]}</span>)
          : <span className="inline-flex items-center gap-1"><AlertTriangle className="h-3 w-3" />falta {fmtQty(item.shortage)}</span>}
      </span>
    </li>
  );
}
