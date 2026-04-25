import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { Button } from '@/components/ui/button';
import { Check, X, ShieldCheck } from 'lucide-react';
import type { Proposal } from '@/hooks/use-ai-agent';

export function AIConfirmCard({
  proposal,
  status,
  onConfirm,
  onCancel,
  disabled,
}: {
  proposal: Proposal;
  status: 'pending' | 'confirmed' | 'cancelled';
  onConfirm: () => void;
  onCancel: () => void;
  disabled?: boolean;
}) {
  return (
    <div className="rounded-lg border border-primary/40 bg-primary/5 p-3">
      <div className="flex items-center gap-2 mb-2">
        <ShieldCheck className="h-4 w-4 text-primary" />
        <span className="text-xs font-semibold uppercase tracking-wide text-primary">
          Confirmação necessária
        </span>
      </div>
      <h4 className="font-semibold text-sm mb-2">{proposal.title}</h4>
      <div className="prose prose-sm dark:prose-invert max-w-none mb-3 [&>*:first-child]:mt-0 [&>*:last-child]:mb-0">
        <ReactMarkdown remarkPlugins={[remarkGfm]}>{proposal.summary_markdown}</ReactMarkdown>
      </div>
      {status === 'pending' && (
        <div className="flex gap-2">
          <Button size="sm" onClick={onConfirm} disabled={disabled} className="gap-1">
            <Check className="h-4 w-4" /> Confirmar
          </Button>
          <Button size="sm" variant="outline" onClick={onCancel} disabled={disabled} className="gap-1">
            <X className="h-4 w-4" /> Cancelar
          </Button>
        </div>
      )}
      {status === 'confirmed' && (
        <p className="text-xs text-muted-foreground italic">✓ Confirmado — executando…</p>
      )}
      {status === 'cancelled' && (
        <p className="text-xs text-muted-foreground italic">✕ Cancelado pelo usuário.</p>
      )}
    </div>
  );
}
