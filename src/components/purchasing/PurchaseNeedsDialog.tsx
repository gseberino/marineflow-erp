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
  const { data: needs, isLoading, isError, isFetching, refetch } = usePurchaseNeeds(serviceOrderId, open);
  /* A conta não carregou (revisão de 23/10/2026). O hook lança em toda leitura com erro, mas
     o diálogo só lia `data`: sem ela, o título caía em "Tudo disponível para executar" e a OS
     parecia pronta porque a conta falhou (ex.: front publicado antes da view
     v_oc_itens_a_caminho). Com um resultado anterior na mão, ele continua valendo. */
  const falhou = isError && !needs;
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

  /* O material que o dono citou e não está no orçamento (origem 'dono') NÃO vai para a OC nem para a cotação (revisão da
     Fase 4, C2, R1): sem linha da OS a que ligar, a OC nasceria sem vínculo e com R$ 0, a falta continuaria (aparecendo
     duas vezes, falta e a caminho), a R16 nunca resolveria e o botão geraria outra OC. Quem compra diz "comprei" ao
     assistente (a linha vira comprada) ou põe no orçamento. */
  const compraveis = useMemo(() => (needs?.shortages ?? []).filter(s => s.origin !== 'dono'), [needs]);
  const citados = (needs?.shortages ?? []).length - compraveis.length;

  const prefilled = useMemo(
    () => compraveis.map(s => ({
      description: s.description,
      quantity: s.shortage,
      product_id: s.productId,
      service_order_part_id: s.origin === 'part' ? s.sourceId : null,
      service_order_service_id: s.origin === 'free_text' ? s.sourceId : null,
    })),
    [compraveis],
  );

  const label = serviceOrderNumber
    ? `${serviceOrderNumber}${clientName ? ` · ${clientName}` : ''}`
    : 'esta OS';

  /* Pedido e ainda não chegou (24/10/2026). Nada a comprar não quer dizer "tudo
     disponível": a OS-00104 zera a falta com o compressor ainda na OC-00004. */
  const aCaminho = (needs?.items ?? []).filter(i => i.status === 'on_order').length;

  return (
    <>
      <Dialog open={open} onOpenChange={onOpenChange}>
        <DialogContent className="max-h-[92vh] max-w-xl overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <ShoppingCart className="h-5 w-5 text-primary" />
              {isLoading
                ? 'Verificando o estoque…'
                : falhou
                  ? 'Não consegui conferir o estoque'
                  : needs?.shortageCount
                    ? `${needs.shortageCount} ${needs.shortageCount === 1 ? 'item precisa' : 'itens precisam'} de compra`
                    : aCaminho
                      ? `Nada a comprar — ${aCaminho === 1 ? '1 item a caminho' : `${aCaminho} itens a caminho`}`
                      : 'Tudo disponível para executar'}
            </DialogTitle>
            <DialogDescription>
              {serviceOrderNumber ? `${serviceOrderNumber} aprovada.` : 'Orçamento aprovado.'}{' '}
              {isLoading
                ? 'Conferindo disponível (físico menos reservado) e o que já está pedido.'
                : falhou
                  ? 'A conta do que falta comprar não carregou: não dá para dizer se está tudo disponível.'
                  : needs?.shortageCount
                    ? 'Você pode resolver agora ou deixar para depois — a pendência não se perde.'
                    : aCaminho
                      ? 'O que foi pedido ainda não chegou: confira a entrega antes de agendar.'
                      : 'Nenhuma peça em falta, nada a comprar.'}
            </DialogDescription>
          </DialogHeader>

          {isLoading ? (
            <div className="space-y-2">
              {[0, 1, 2].map(i => <Skeleton key={i} className="h-12 w-full" />)}
            </div>
          ) : falhou ? (
            <div className="rounded-lg border border-destructive/40 bg-destructive/5 p-3">
              <p className="flex items-center gap-2 text-sm font-medium">
                <AlertTriangle className="h-4 w-4 shrink-0 text-destructive" />
                Confira antes de agendar ou de comprar.
              </p>
              <Button
                size="sm"
                variant="outline"
                className="mt-2 h-7 text-xs"
                disabled={isFetching}
                onClick={() => refetch()}
              >
                {isFetching ? 'Conferindo…' : 'Tentar de novo'}
              </Button>
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
                  <span className="block text-xs">
                    pelo último custo conhecido — a cotação dá o número real.
                    {!!needs.semPreco && ` Fora ${needs.semPreco === 1 ? '1 item citado por você, sem preço' : `${needs.semPreco} itens citados por você, sem preço`}.`}
                  </span>
                </p>
              )}

              {citados > 0 && (
                <p className="rounded-lg border border-amber-500/40 bg-amber-500/5 p-3 text-xs text-muted-foreground">
                  {citados === 1
                    ? 'O item citado por você fica fora da ordem de compra e da cotação: ele não está no orçamento.'
                    : `Os ${citados} itens citados por você ficam fora da ordem de compra e da cotação: eles não estão no orçamento.`}
                  {' '}Quando comprar, diga “comprei” ao assistente, ou ponha no orçamento.
                </p>
              )}
            </div>
          )}

          <DialogFooter className="flex-col gap-2 sm:flex-row">
            <Button variant="ghost" onClick={() => onOpenChange(false)} className="sm:mr-auto">
              {needs?.shortageCount ? 'Depois' : 'Fechar'}
            </Button>
            {compraveis.length > 0 && (
              <>
                <Button variant="outline" className="gap-1" onClick={() => setQuoteOpen(true)}>
                  <ClipboardList className="h-4 w-4" />
                  {openQuote ? 'Nova cotação' : `Cotar ${compraveis.length} ${compraveis.length === 1 ? 'item' : 'itens'}`}
                </Button>
                <Button
                  className="gap-1"
                  disabled={createPOs.isPending}
                  onClick={async () => {
                    await createPOs.mutateAsync({
                      serviceOrderId,
                      items: compraveis.map(s => ({
                        productId: s.productId,
                        description: s.description,
                        quantity: s.shortage,
                        unitCost: s.unitCost,
                        // Fase 4 (P2): a linha da OS que a OC compra (o material citado pelo dono não entra: C2, R1).
                        serviceOrderPartId: s.origin === 'part' ? s.sourceId : null,
                        serviceOrderServiceId: s.origin === 'free_text' ? s.sourceId : null,
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
        {/* Item de texto livre pedido em OC da própria OS: não há estoque a mostrar
            ("disponível 0" diria que falta), só a OC e a pergunta que importa. Desde a Fase 4 (P2) o
            item de texto livre com OC ligada a ele também: a caminho ("chegou?") ou já recebido. */}
        {item.origin === 'purchase_order' || (item.origin === 'free_text' && item.purchaseOrderNumber && item.shortage === 0) ? (
          <p className="mt-0.5 text-xs text-muted-foreground">
            precisa {fmtQty(item.required)} · {item.status === 'ok'
              ? `chegou pela ${item.purchaseOrderNumber ?? 'OC'}`
              : `pedido na ${item.purchaseOrderNumber ?? 'OC'} — chegou?`}
          </p>
        ) : item.origin === 'dono' ? (
          /* Material que o dono citou e não está no orçamento (Fase 4, P2): sem cadastro e sem preço. */
          <p className="mt-0.5 text-xs text-muted-foreground">
            precisa {fmtQty(item.required)} · citado por você (sem preço)
            {item.onOrder > 0 && ` · pedido ${fmtQty(item.onOrder)}`}
          </p>
        ) : (
          <p className="mt-0.5 text-xs text-muted-foreground">
            precisa {fmtQty(item.required)}
            {item.status !== 'uncatalogued' && ` · disponível ${fmtQty(item.available)}`}
            {item.onOrder > 0 && ` · pedido ${fmtQty(item.onOrder)}`}
          </p>
        )}
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
