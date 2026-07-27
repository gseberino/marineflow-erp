import { Card } from '@/components/ui/card';
import { AlertTriangle, CircleDot, MessageSquareQuote, Wrench, Package, FileText, DollarSign, ShoppingCart } from 'lucide-react';
import { useEntityOpenLoops, type OpenLoop } from '@/hooks/use-agenda';
import { useAuth } from '@/hooks/use-auth';

/**
 * "O que está em aberto com este contato agora" — os fios soltos (Fase 13).
 *
 * Duas origens convivem no mesmo painel de propósito: o que o ERP prova (OS, título,
 * entrega) e o que ficou combinado na conversa e ainda não virou fato. O segundo grupo é o
 * que costumava se perder — por isso ele é marcado, não escondido.
 *
 * O painel é somente leitura: nada aqui fecha um fio à mão. Quem fecha é o ERP, no motor de
 * 15 min. Um botão de "resolver" aqui só criaria divergência com o banco.
 */

/** Técnico não vê dinheiro — mesma regra do get_client_360 e do resto do sistema. */
const FIOS_FINANCEIROS = new Set(['receivable', 'payable']);

const ICONE: Record<string, typeof Wrench> = {
  service_order: Wrench,
  delivery: Package,
  quote: FileText,
  receivable: DollarSign,
  payable: DollarSign,
  purchase_order: ShoppingCart,
};

function formatarPrazo(iso: string | null): string | null {
  if (!iso) return null;
  return new Date(iso).toLocaleDateString('pt-BR', {
    day: '2-digit', month: '2-digit', timeZone: 'America/Sao_Paulo',
  });
}

function LinhaFio({ fio }: { fio: OpenLoop }) {
  const Icone = ICONE[fio.kind] ?? CircleDot;
  const prazo = formatarPrazo(fio.due_at);
  const daConversa = fio.source === 'conversation';

  return (
    <div className="flex items-start gap-2.5 rounded-md border border-border/60 p-2.5">
      <Icone
        className={`h-4 w-4 mt-0.5 shrink-0 ${
          fio.atrasado ? 'text-destructive' : 'text-muted-foreground'
        }`}
      />
      {/* min-w-0 é o que impede o texto longo de empurrar a largura do card */}
      <div className="min-w-0 flex-1 space-y-1">
        <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
          <span className="text-sm font-medium break-words">{fio.title}</span>
          {fio.atrasado && (
            <span className="inline-flex items-center gap-1 rounded-full bg-destructive/10 px-1.5 py-0.5 text-[10px] font-semibold text-destructive">
              <AlertTriangle className="h-3 w-3" /> atrasado
            </span>
          )}
          {daConversa && (
            <span className="inline-flex items-center gap-1 rounded-full bg-amber-500/10 px-1.5 py-0.5 text-[10px] font-medium text-amber-700 dark:text-amber-400">
              <MessageSquareQuote className="h-3 w-3" /> combinado na conversa
            </span>
          )}
          {fio.mentions > 1 && (
            <span className="rounded-full bg-muted px-1.5 py-0.5 text-[10px] text-muted-foreground">
              cobrado {fio.mentions}×
            </span>
          )}
        </div>

        {fio.detail && (
          <p className="text-xs text-muted-foreground break-words line-clamp-2">{fio.detail}</p>
        )}

        {/* A frase literal que originou o fio: é o que permite conferir sem abrir a conversa. */}
        {daConversa && fio.evidence && (
          <p className="text-xs italic text-muted-foreground break-words line-clamp-2">
            “{fio.evidence}”
          </p>
        )}

        <div className="flex flex-wrap gap-x-3 gap-y-0.5 text-[11px] text-muted-foreground">
          {prazo && <span className={fio.atrasado ? 'text-destructive font-medium' : ''}>prazo {prazo}</span>}
          {fio.service_order_number && <span>OS {fio.service_order_number}</span>}
        </div>
      </div>
    </div>
  );
}

export function OpenLoopsPanel({
  entityType,
  entityId,
  title = 'Em aberto agora',
  /** Sem nada pendente, o painel some. Ele fica acima da dobra: card vazio ali é só ruído. */
  hideWhenEmpty = true,
}: {
  entityType: 'client' | 'supplier';
  entityId: string | undefined;
  title?: string;
  hideWhenEmpty?: boolean;
}) {
  const { data: todos = [], isLoading } = useEntityOpenLoops(entityType, entityId);
  const { user } = useAuth();

  const fios = user?.role === 'technician'
    ? todos.filter((f) => !FIOS_FINANCEIROS.has(f.kind))
    : todos;

  if (!entityId) return null;
  if (hideWhenEmpty && !isLoading && fios.length === 0) return null;

  const atrasados = fios.filter((f) => f.atrasado).length;

  return (
    <Card className="p-4 space-y-3">
      <div className="flex flex-wrap items-center gap-2 text-sm font-semibold">
        <CircleDot className="h-4 w-4 text-primary" /> {title}
        {fios.length > 0 && (
          <span className="rounded-full bg-primary/10 px-2 py-0.5 text-[11px] font-medium text-primary">
            {fios.length}
          </span>
        )}
        {atrasados > 0 && (
          <span className="rounded-full bg-destructive/10 px-2 py-0.5 text-[11px] font-medium text-destructive">
            {atrasados} atrasado{atrasados > 1 ? 's' : ''}
          </span>
        )}
      </div>

      {isLoading && <p className="text-xs text-muted-foreground">Carregando…</p>}

      {!isLoading && fios.length === 0 && (
        <p className="text-xs text-muted-foreground">Nada pendente com este contato.</p>
      )}

      <div className="space-y-1.5">
        {fios.map((f) => <LinhaFio key={f.id} fio={f} />)}
      </div>
    </Card>
  );
}
