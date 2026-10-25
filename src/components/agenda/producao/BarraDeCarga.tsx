/**
 * A carga do dia de uma pessoa na Semana de produção (Fase 3, P7a): "Roberto 2/2" e a barra. A cor vem pronta do banco
 * (verde até a carga_max de agenda_config, âmbar até 100%, vermelho acima) e nunca fala sozinha: o texto diz os meios-dias
 * usados sobre os esperados, e o vermelho diz "acima" em palavras.
 */
import type { CorDaCarga, PessoaDoDia } from '@/hooks/use-agenda-producao';
import { cn } from '@/lib/utils';

const COR_DA_BARRA: Record<CorDaCarga, string> = {
  verde: 'bg-emerald-500',
  ambar: 'bg-amber-500',
  vermelho: 'bg-red-600',
};

const PALAVRA_DA_COR: Record<CorDaCarga, string> = {
  verde: 'com folga',
  ambar: 'cheio',
  vermelho: 'acima da carga',
};

export function BarraDeCarga({ pessoa }: { pessoa: PessoaDoDia }) {
  // A barra não passa de cheia (o "acima" vai no texto); sem esperado e com uso, cheia e vermelha.
  const largura = pessoa.meios_esperados > 0
    ? Math.min(100, Math.round((pessoa.meios_usados / pessoa.meios_esperados) * 100))
    : (pessoa.meios_usados > 0 ? 100 : 0);
  return (
    <div
      className="flex min-w-0 items-center gap-2 rounded-md border px-2 py-1 text-xs"
      data-testid={`carga-${pessoa.payee_id}`}
      title={`${pessoa.texto}: ${PALAVRA_DA_COR[pessoa.cor]}`}
    >
      <span className="min-w-0 truncate font-medium">{pessoa.texto}</span>
      <span
        className="relative h-2 w-12 shrink-0 overflow-hidden rounded-full bg-muted"
        role="img"
        aria-label={`${pessoa.texto}, ${PALAVRA_DA_COR[pessoa.cor]}`}
      >
        <span className={cn('absolute inset-y-0 left-0 rounded-full', COR_DA_BARRA[pessoa.cor])} style={{ width: `${largura}%` }} />
      </span>
      {pessoa.cor === 'vermelho' && <span className="shrink-0 font-semibold text-red-700 dark:text-red-400">acima</span>}
    </div>
  );
}
