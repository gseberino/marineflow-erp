import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { Button } from '@/components/ui/button';
import { Check, X, ShieldAlert, ShieldCheck } from 'lucide-react';
import type { OperatorPendingAction } from '@/hooks/use-ai-operator';

const RISK_COLORS: Record<string, string> = {
  low: 'text-emerald-600 border-emerald-500/40 bg-emerald-500/5',
  medium: 'text-amber-600 border-amber-500/40 bg-amber-500/5',
  high: 'text-orange-600 border-orange-500/40 bg-orange-500/5',
  critical: 'text-red-600 border-red-500/40 bg-red-500/5',
};

const RISK_LABELS: Record<string, string> = {
  low: 'Baixo',
  medium: 'Médio',
  high: 'Alto',
  critical: 'Crítico',
};

export function AIOperatorPendingActionCard({
  action,
  status,
  disabled,
  onApprove,
  onReject,
}: {
  action: OperatorPendingAction;
  status: 'pending' | 'approved' | 'rejected';
  disabled?: boolean;
  onApprove: (id: string) => void;
  onReject: (id: string) => void;
}) {
  const colorCls = RISK_COLORS[action.risk_level] ?? RISK_COLORS.high;

  return (
    <div className={`rounded-lg border p-3 ${colorCls}`}>
      <div className="flex items-center gap-2 mb-2">
        {action.risk_level === 'low' ? (
          <ShieldCheck className="h-4 w-4" />
        ) : (
          <ShieldAlert className="h-4 w-4" />
        )}
        <span className="text-xs font-semibold uppercase tracking-wide">
          Ação sensível — risco {RISK_LABELS[action.risk_level] ?? action.risk_level}
        </span>
      </div>
      <h4 className="font-semibold text-sm mb-1">{action.title}</h4>
      <p className="text-xs text-muted-foreground mb-2">{action.risk_reason}</p>
      {action.summary_markdown && (
        <div className="prose prose-sm dark:prose-invert max-w-none mb-3 [&>*:first-child]:mt-0 [&>*:last-child]:mb-0">
          <ReactMarkdown remarkPlugins={[remarkGfm]}>{action.summary_markdown}</ReactMarkdown>
        </div>
      )}
      {status === 'pending' && (
        <>
          <p className="text-[11px] text-muted-foreground italic mb-2">
            Nesta fase, aprovar apenas <strong>registra sua intenção</strong>. A execução real
            (envio ao cliente, criação de OS oficial, agendamento, alteração de estoque) será
            habilitada em ciclo posterior, com executor dedicado.
          </p>
          <div className="flex gap-2">
            <Button size="sm" onClick={() => onApprove(action.id)} disabled={disabled} className="gap-1">
              <Check className="h-4 w-4" /> Aprovar intenção
            </Button>
            <Button
              size="sm"
              variant="outline"
              onClick={() => onReject(action.id)}
              disabled={disabled}
              className="gap-1"
            >
              <X className="h-4 w-4" /> Rejeitar
            </Button>
          </div>
        </>
      )}
      {status === 'approved' && (
        <p className="text-xs italic">
          ✅ Intenção registrada. <strong>Nada foi executado</strong> — a execução real virá em
          ciclo posterior.
        </p>
      )}
      {status === 'rejected' && <p className="text-xs italic">✕ Rejeitado pelo usuário.</p>}
    </div>
  );
}
