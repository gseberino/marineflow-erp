/**
 * Um bloco do dia na Semana de produção (Fase 3, P7a): "OS · cliente · bem", quem vai, "dia n de N", "✔ cliente
 * confirmou" e o resultado do dia. A reserva vem listrada e diz "a confirmar" (lugar guardado, não compromisso). O texto
 * sai pronto do banco (agenda_tela_semana).
 */
import { CheckCircle2 } from 'lucide-react';
import type { BlocoDoDia } from '@/hooks/use-agenda-producao';
import { cn } from '@/lib/utils';

export function BlocoDaOs({ bloco, onAbrir }: { bloco: BlocoDoDia; onAbrir: (os: string) => void }) {
  const titulo = [bloco.numero, bloco.cliente, bloco.bem].filter(Boolean).join(' · ');
  return (
    <button
      type="button"
      onClick={() => onAbrir(bloco.os)}
      className={cn(
        'w-full min-w-0 rounded-md border p-2 text-left text-sm transition-colors hover:border-primary/60',
        bloco.reserva
          ? 'border-dashed bg-[repeating-linear-gradient(135deg,transparent,transparent_6px,hsl(var(--muted))_6px,hsl(var(--muted))_12px)]'
          : 'bg-card',
      )}
      data-testid={`bloco-${bloco.numero}`}
    >
      <div className="flex min-w-0 flex-wrap items-baseline justify-between gap-x-2">
        <span className="min-w-0 break-words font-medium">{titulo}</span>
        {bloco.hora && <span className="shrink-0 text-xs tabular-nums text-muted-foreground">{bloco.hora}</span>}
      </div>
      {bloco.pessoas_texto && <p className="mt-0.5 break-words text-xs text-muted-foreground">{bloco.pessoas_texto}</p>}
      <div className="mt-1 flex flex-wrap gap-x-3 gap-y-1 text-xs">
        {bloco.reserva_texto && <span className="font-medium text-amber-700 dark:text-amber-400">{bloco.reserva_texto}</span>}
        {bloco.condicao && <span className="break-words text-muted-foreground">{bloco.condicao}</span>}
        {bloco.dia_texto && <span>{bloco.dia_texto}</span>}
        {bloco.confirmado_cliente && (
          <span className="inline-flex items-center gap-1 text-emerald-700 dark:text-emerald-400">
            <CheckCircle2 className="h-3 w-3" aria-hidden /> cliente confirmou
          </span>
        )}
        {bloco.fixada && <span className="text-muted-foreground">fixado</span>}
        {bloco.resultado_texto && <span className="font-medium">{bloco.resultado_texto}</span>}
      </div>
    </button>
  );
}
