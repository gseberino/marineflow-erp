import { Check, Clock, AlertTriangle, Send, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';

/**
 * Onde esta cotação REALMENTE está, e qual é o próximo passo.
 *
 * Nasceu de um caso concreto: as três cotações de produção ficaram 11 dias exibindo
 * "enviada a 2 fornecedores" sem que uma única mensagem tivesse saído, porque a lista
 * de fornecedores era preenchida na criação e nada distinguia "escolhi" de "mandei".
 * O dono não tinha como perceber — a tela dizia que estava tudo certo.
 *
 * Por isso cada etapa aqui é apurada de um FATO no banco, nunca presumida, e a etapa
 * que falta traz o botão que a executa. Um passo só acende quando aconteceu de verdade.
 */

export type StepState = 'done' | 'current' | 'pending' | 'problem';

export interface QuoteStep {
  key: string;
  label: string;
  /** O que já se sabe sobre esta etapa — aparece abaixo do rótulo. */
  detail?: string;
  state: StepState;
}

interface Props {
  steps: QuoteStep[];
  /** Ação da etapa pendente. Só aparece quando há o que fazer. */
  action?: { label: string; onClick: () => void; loading?: boolean; icon?: 'send' };
  className?: string;
}

const DOT: Record<StepState, string> = {
  done:    'bg-emerald-600 text-white border-emerald-600',
  current: 'bg-primary text-primary-foreground border-primary',
  problem: 'bg-amber-500 text-white border-amber-500',
  pending: 'bg-muted text-muted-foreground border-border',
};

const TEXT: Record<StepState, string> = {
  done:    'text-foreground',
  current: 'text-foreground font-medium',
  problem: 'text-amber-700 dark:text-amber-400 font-medium',
  pending: 'text-muted-foreground',
};

export function QuoteProgressStrip({ steps, action, className }: Props) {
  return (
    <div className={cn('rounded-xl border bg-card p-4', className)}>
      {/* flex-wrap e não grid de N colunas: com 5 etapas, qualquer largura fixa
          empurraria a página para o lado no celular. */}
      <ol className="flex flex-wrap items-start gap-x-5 gap-y-3">
        {steps.map((s, i) => (
          <li key={s.key} className="flex min-w-0 items-start gap-2">
            <span
              className={cn(
                'mt-0.5 flex h-5 w-5 flex-none items-center justify-center rounded-full border text-[11px] font-semibold',
                DOT[s.state],
              )}
              aria-hidden="true"
            >
              {s.state === 'done' ? <Check className="h-3 w-3" />
                : s.state === 'problem' ? <AlertTriangle className="h-3 w-3" />
                : s.state === 'current' ? <Clock className="h-3 w-3" />
                : i + 1}
            </span>
            <span className="min-w-0">
              <span className={cn('block text-sm leading-tight', TEXT[s.state])}>{s.label}</span>
              {s.detail && (
                <span className="block text-xs leading-tight text-muted-foreground">{s.detail}</span>
              )}
            </span>
          </li>
        ))}
      </ol>

      {action && (
        <div className="mt-3 border-t pt-3">
          <Button size="sm" className="gap-1.5" onClick={action.onClick} disabled={action.loading}>
            {action.loading ? <Loader2 className="h-3.5 w-3.5 animate-spin" />
              : action.icon === 'send' ? <Send className="h-3.5 w-3.5" /> : null}
            {action.label}
          </Button>
        </div>
      )}
    </div>
  );
}
