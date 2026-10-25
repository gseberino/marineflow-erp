import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { AlertTriangle, ClipboardList, Clock, PackageSearch } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';
import { usePurchaseNeeds } from '@/hooks/use-purchase-needs';
import { useSOLinkedQuotes } from '@/hooks/use-quote-requests';
import { agingLevel, businessDaysSince } from '@/lib/quote-comparison';
import { PurchaseNeedsDialog } from '@/components/purchasing/PurchaseNeedsDialog';

/**
 * Faixa de compras dentro da OS.
 *
 * O diálogo da aprovação aparece uma vez; esta faixa fica. É o que evita o caso
 * "cliquei em Depois e esqueci": quem abrir a OS depois vê que falta material antes
 * de mandar o técnico. Também é o único lugar da OS que mostra COTAÇÃO — a seção
 * "Compras vinculadas" só conhece ordem de compra.
 *
 * Fica invisível quando não há nada a comprar: faixa que aparece sempre para dizer
 * "está tudo bem" vira ruído e deixa de ser lida.
 */

/** Rascunho não compra (é orçamento); concluída/faturada/cancelada não compra mais. */
const SILENT_STATUSES = new Set(['draft', 'completed', 'invoiced', 'cancelled']);

interface Props {
  serviceOrderId?: string;
  serviceOrderNumber?: string | null;
  clientName?: string | null;
  status?: string;
  isNew?: boolean;
}

export function PurchaseNeedsBanner({
  serviceOrderId, serviceOrderNumber, clientName, status, isNew,
}: Props) {
  const active = !!serviceOrderId && !isNew && !SILENT_STATUSES.has(status ?? '');
  const { data: needs, isError, isFetching, refetch } = usePurchaseNeeds(serviceOrderId, active);
  const { data: linkedQuotes } = useSOLinkedQuotes(active ? serviceOrderId : undefined);
  const [dialogOpen, setDialogOpen] = useState(false);

  const openQuote = useMemo(
    () => (linkedQuotes ?? []).find(q => q.status === 'open'),
    [linkedQuotes],
  );

  const quoteInfo = useMemo(() => {
    if (!openQuote) return null;
    const days = businessDaysSince(openQuote.created_at);
    const priced = (openQuote.quote_responses ?? []).filter(
      r => r.quote_request_item_id && Number(r.unit_price) > 0,
    );
    return { days, level: agingLevel(days), hasAnswer: priced.length > 0 };
  }, [openQuote]);

  /* Pedido e ainda não chegou (24/10/2026). Sem isto a faixa sumia quando a falta zerava
     pela OC aberta, e a OS parecia pronta com a peça no fornecedor: a OS-00104 tem o
     compressor só na OC-00004. "Nada a comprar" não é "tudo na mão". */
  const aCaminho = (needs?.items ?? []).filter(i => i.status === 'on_order');

  if (!active) return null;
  /* A conta não carregou (revisão de 23/10/2026): sumir aqui diria "nada a comprar" sem ter lido
     nada. Uma linha discreta, sem o vermelho da falta, e o caminho para tentar de novo. */
  if (isError && !needs) {
    return (
      <section className="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-dashed p-3 text-xs text-muted-foreground">
        <span className="flex items-center gap-2">
          <AlertTriangle className="h-3.5 w-3.5 shrink-0" />
          Não consegui conferir as compras desta OS.
        </span>
        <Button size="sm" variant="ghost" className="h-7 text-xs" disabled={isFetching} onClick={() => refetch()}>
          {isFetching ? 'Conferindo…' : 'Tentar de novo'}
        </Button>
      </section>
    );
  }
  // Sem falta, sem cotação aberta e nada a caminho: não há nada a dizer.
  if (!needs?.shortageCount && !openQuote && !aCaminho.length) return null;

  const shortageCount = needs?.shortageCount ?? 0;
  const critical = shortageCount > 0 && !openQuote;

  return (
    <>
      <section
        className={cn(
          'rounded-xl border p-4 shadow-sm',
          critical ? 'border-destructive/40 bg-destructive/5'
                   : 'border-amber-500/40 bg-amber-500/5',
        )}
      >
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div className="min-w-0 flex-1">
            <h2 className="flex items-center gap-2 text-sm font-semibold">
              {shortageCount > 0
                ? <><AlertTriangle className="h-4 w-4 shrink-0 text-destructive" />
                    {shortageCount === 1 ? '1 item precisa de compra' : `${shortageCount} itens precisam de compra`}</>
                : openQuote
                  ? <><ClipboardList className="h-4 w-4 shrink-0" /> Cotação em andamento</>
                  : <><Clock className="h-4 w-4 shrink-0" />
                      {aCaminho.length === 1 ? '1 item a caminho' : `${aCaminho.length} itens a caminho`}</>}
            </h2>

            {shortageCount > 0 && needs && (
              <ul className="mt-2 space-y-0.5 text-xs text-muted-foreground">
                {needs.shortages.slice(0, 4).map(item => (
                  <li key={`${item.origin}-${item.sourceId}`} className="truncate">
                    <span className="text-foreground">{item.description}</span>
                    {' — falta '}
                    {new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 3 }).format(item.shortage)}
                    {item.available > 0 && ` (tem ${new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 3 }).format(item.available)} disponível)`}
                    {item.origin === 'dono'
                      ? ' · citado por você (sem preço)'
                      : item.status === 'uncatalogued' && ' · sem cadastro'}
                  </li>
                ))}
                {needs.shortages.length > 4 && (
                  <li className="italic">e mais {needs.shortages.length - 4}…</li>
                )}
              </ul>
            )}

            {aCaminho.length > 0 && (
              <ul className="mt-2 space-y-0.5 text-xs text-muted-foreground">
                {aCaminho.slice(0, 4).map(item => (
                  <li key={`${item.origin}-${item.sourceId}`} className="truncate">
                    <span className="text-foreground">{item.description}</span>
                    {item.purchaseOrderNumber
                      ? ` — pedido na ${item.purchaseOrderNumber}, chegou?`
                      : ' — já pedido, chegou?'}
                  </li>
                ))}
                {aCaminho.length > 4 && (
                  <li className="italic">e mais {aCaminho.length - 4}…</li>
                )}
              </ul>
            )}

            {openQuote && quoteInfo && (
              <p className="mt-2 text-xs">
                <Link
                  to={`/purchasing/quotes/${openQuote.id}`}
                  className="font-medium underline underline-offset-2"
                >
                  {openQuote.code}
                </Link>
                {' · '}
                <span className={cn(
                  quoteInfo.level === 'late' && !quoteInfo.hasAnswer && 'font-medium text-destructive',
                  quoteInfo.level === 'due' && !quoteInfo.hasAnswer && 'font-medium text-amber-600 dark:text-amber-400',
                  'text-muted-foreground',
                )}>
                  {quoteInfo.hasAnswer
                    ? 'respondida — falta decidir'
                    : quoteInfo.days === 0
                      ? 'enviada hoje, sem resposta'
                      : `sem resposta há ${quoteInfo.days} ${quoteInfo.days === 1 ? 'dia útil' : 'dias úteis'}`}
                </span>
                {!quoteInfo.hasAnswer && quoteInfo.level !== 'fresh' && (
                  <span className="ml-1 inline-flex items-center gap-0.5 text-muted-foreground">
                    <Clock className="h-3 w-3" /> vale cobrar
                  </span>
                )}
              </p>
            )}
          </div>

          <Button
            size="sm"
            variant={critical ? 'default' : 'outline'}
            className="shrink-0 gap-1"
            onClick={() => setDialogOpen(true)}
          >
            <PackageSearch className="h-3.5 w-3.5" /> Resolver
          </Button>
        </div>
      </section>

      {dialogOpen && serviceOrderId && (
        <PurchaseNeedsDialog
          open={dialogOpen}
          onOpenChange={setDialogOpen}
          serviceOrderId={serviceOrderId}
          serviceOrderNumber={serviceOrderNumber}
          clientName={clientName}
        />
      )}
    </>
  );
}
