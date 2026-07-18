import { useState } from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { Button } from '@/components/ui/button';
import { Check, X, ShieldCheck, Pencil } from 'lucide-react';
import type { Proposal } from '@/hooks/use-ai-agent';

export function AIConfirmCard({
  proposal,
  status,
  onConfirm,
  onCancel,
  disabled,
}: {
  proposal: Proposal;
  status: 'pending' | 'confirmed' | 'cancelled' | 'executed';
  onConfirm: (note?: string) => void;
  onCancel: (note?: string) => void;
  disabled?: boolean;
}) {
  const [showNote, setShowNote] = useState(false);
  const [note, setNote] = useState('');
  const trimmed = note.trim();

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
        <>
          {showNote && (
            <div className="mb-2">
              <textarea
                value={note}
                onChange={(e) => setNote(e.target.value)}
                placeholder="Ex.: 'use um tom mais amigável', 'o valor era 500'. A IA guarda pra acertar da próxima."
                disabled={disabled}
                className="w-full min-h-[60px] rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
              />
              <p className="mt-1 text-[11px] text-muted-foreground">
                Isto ensina a IA para as próximas — não muda esta ação. Se estiver errada, use Cancelar.
              </p>
            </div>
          )}
          <div className="flex flex-wrap gap-2">
            <Button size="sm" onClick={() => onConfirm(trimmed || undefined)} disabled={disabled} className="gap-1">
              <Check className="h-4 w-4" /> Confirmar
            </Button>
            <Button size="sm" variant="outline" onClick={() => onCancel(trimmed || undefined)} disabled={disabled} className="gap-1">
              <X className="h-4 w-4" /> Cancelar
            </Button>
            {!showNote && (
              <Button
                size="sm"
                variant="ghost"
                onClick={() => setShowNote(true)}
                disabled={disabled}
                className="gap-1 text-muted-foreground"
              >
                <Pencil className="h-3.5 w-3.5" /> Ensinar a IA
              </Button>
            )}
          </div>
        </>
      )}
      {status === 'confirmed' && (
        <p className="text-xs text-muted-foreground italic flex items-center gap-1">
          <span className="animate-pulse">⏳</span> Executando ação…
        </p>
      )}
      {status === 'executed' && (
        <p className="text-xs text-green-600 dark:text-green-400 italic">✅ Ação executada com sucesso.</p>
      )}
      {status === 'cancelled' && (
        <p className="text-xs text-muted-foreground italic">✕ Cancelado pelo usuário.</p>
      )}
    </div>
  );
}
