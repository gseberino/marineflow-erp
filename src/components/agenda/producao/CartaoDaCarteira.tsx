/**
 * Um cartão da Carteira de produção (Fase 3, P7a): número · cliente · bem, o estado, a idade em dias úteis com a cor
 * (borda e texto: "há 23 dias úteis" — nunca só a cor), a próxima ação e quem trava. Tudo pronto do banco
 * (agenda_tela_carteira; os limiares da cor são de agenda_config).
 */
import type { CartaoDaCarteiraDados, CorDaIdade } from '@/hooks/use-agenda-producao';
import { cn } from '@/lib/utils';

const BORDA: Record<CorDaIdade, string> = {
  normal: 'border-l-border',
  laranja: 'border-l-orange-500',
  vermelho: 'border-l-red-600',
};
const TEXTO_DA_IDADE: Record<CorDaIdade, string> = {
  normal: 'text-muted-foreground',
  laranja: 'font-medium text-orange-700 dark:text-orange-400',
  vermelho: 'font-semibold text-red-700 dark:text-red-400',
};

export function CartaoDaCarteira({ cartao, rotuloDoGrupo, onAbrir }: {
  cartao: CartaoDaCarteiraDados;
  rotuloDoGrupo: string;
  onAbrir: (os: string) => void;
}) {
  const titulo = [cartao.numero, cartao.cliente, cartao.bem].filter(Boolean).join(' · ');
  return (
    <button
      type="button"
      onClick={() => onAbrir(cartao.os)}
      className={cn('w-full min-w-0 rounded-md border border-l-4 bg-card p-3 text-left transition-colors hover:border-primary/60',
                    BORDA[cartao.cor])}
      data-testid={`cartao-${cartao.numero}`}
    >
      <p className="break-words text-sm font-medium">{titulo}</p>
      <p className="mt-0.5 text-xs text-muted-foreground">{rotuloDoGrupo}</p>
      {cartao.estado && <p className="mt-1 break-words text-sm">{cartao.estado}</p>}
      <p className={cn('mt-1 text-xs', TEXTO_DA_IDADE[cartao.cor])}>{cartao.idade_texto}</p>
      {cartao.proxima_acao && (
        <p className="mt-1 break-words text-sm"><span className="text-muted-foreground">Próxima ação: </span>{cartao.proxima_acao}</p>
      )}
      {cartao.quem_trava_texto && <p className="mt-0.5 text-xs font-medium">{cartao.quem_trava_texto}</p>}
    </button>
  );
}
