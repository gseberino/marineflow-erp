import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { cn } from '@/lib/utils';
import { Check, X, Pencil, MessageSquare, Mic, Quote, Loader2, CalendarDays } from 'lucide-react';
import { toast } from 'sonner';
import { useAcceptSuggestion, useDismissSuggestion } from '@/hooks/use-agenda';

const DETECTOR_LABEL: Record<string, string> = {
  promise: 'Você prometeu',
  client_request: 'Cliente pediu',
  third_party_deadline: 'Prazo combinado',
  followup: 'Sem resposta',
  voice_note: 'Seu recado',
};

/** Os motivos de descarte mais comuns, a um toque; o campo aceita qualquer outro. */
const MOTIVOS_RAPIDOS = ['Já resolvido', 'Não é tarefa', 'Duplicada', 'Entendeu errado'];

function fmtWhen(s: any): string | null {
  const iso = s.suggested_start_at || s.suggested_due_at;
  if (!iso) return null;
  const d = new Date(iso);
  const dia = d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
  if (s.suggested_start_at) {
    return `${dia} ${d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}`;
  }
  return dia;
}

/**
 * Card da Caixa de Entrada: mostra o que a IA entendeu E a frase original que gerou
 * (evidência — o que permite decidir em 1 segundo e mata alucinação).
 */
export function SuggestionCard({ suggestion }: { suggestion: any }) {
  const accept = useAcceptSuggestion();
  const dismiss = useDismissSuggestion();
  const [editing, setEditing] = useState(false);
  const [title, setTitle] = useState(suggestion.title);
  // Motivo do descarte (07/10/2026): a coluna dismiss_reason existia e a tela nunca preenchia.
  // Opcional — é o que ensina o detector a não sugerir de novo o que não serve.
  const [descartando, setDescartando] = useState(false);
  const [motivo, setMotivo] = useState('');

  const when = fmtWhen(suggestion);
  const isVoice = suggestion.origin !== 'whatsapp';
  const busy = accept.isPending || dismiss.isPending;

  const descartar = () => {
    dismiss.mutate({ id: suggestion.id, reason: motivo.trim() || undefined }, {
      onSuccess: () => toast.success('Descartada'),
      onError: (e: any) => toast.error(e?.message || 'Erro'),
    });
  };

  const doAccept = () => {
    accept.mutate(
      { suggestion, overrides: editing && title.trim() ? { title: title.trim() } as any : undefined },
      {
        onSuccess: () => toast.success('Tarefa criada'),
        onError: (e: any) => toast.error(e?.message || 'Erro ao aceitar'),
      },
    );
  };

  return (
    <div className="rounded-md border bg-card p-3 space-y-2.5">
      <div className="flex items-start gap-2">
        <span className={cn(
          'mt-0.5 inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-semibold shrink-0',
          isVoice ? 'bg-violet-500/10 text-violet-700 dark:text-violet-400'
                  : 'bg-primary/10 text-primary',
        )}>
          {isVoice ? <Mic className="h-3 w-3" /> : <MessageSquare className="h-3 w-3" />}
          {DETECTOR_LABEL[suggestion.detector] || 'Sugestão'}
        </span>
        <div className="min-w-0 flex-1">
          {editing ? (
            <Input
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              className="h-8 text-sm"
              autoFocus
              onKeyDown={(e) => { if (e.key === 'Enter') doAccept(); }}
            />
          ) : (
            <p className="text-sm font-medium leading-snug">{suggestion.title}</p>
          )}
          <div className="mt-1 flex flex-wrap items-center gap-x-2.5 gap-y-1 text-[11px] text-muted-foreground">
            {suggestion.contact_label && <span>{suggestion.contact_label}</span>}
            {when && (
              <span className="inline-flex items-center gap-1">
                <CalendarDays className="h-3 w-3" /> {when}
              </span>
            )}
            {suggestion.priority === 'urgent' && <span className="text-destructive font-semibold">urgente</span>}
          </div>
        </div>
      </div>

      {/* Evidência: a frase literal que originou a sugestão */}
      <div className="flex gap-2 rounded bg-muted/50 px-2.5 py-1.5">
        <Quote className="h-3 w-3 shrink-0 mt-0.5 text-muted-foreground" />
        <p className="text-[11px] italic text-muted-foreground line-clamp-3">{suggestion.evidence}</p>
      </div>

      <div className="flex items-center gap-2">
        <Button size="sm" className="h-7 flex-1" onClick={doAccept} disabled={busy}>
          {accept.isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Check className="h-3.5 w-3.5 mr-1" />}
          Aceitar
        </Button>
        <Button size="sm" variant="outline" className="h-7" disabled={busy}
          onClick={() => setEditing((v) => !v)}>
          <Pencil className="h-3.5 w-3.5 mr-1" /> {editing ? 'Cancelar' : 'Ajustar'}
        </Button>
        <Button aria-label="Descartar esta sugestão" size="sm" variant="ghost" className="h-7 text-muted-foreground" disabled={busy}
          aria-expanded={descartando}
          onClick={() => setDescartando((v) => !v)}>
          <X className="h-3.5 w-3.5" />
        </Button>
      </div>

      {descartando && (
        <div className="space-y-1.5 rounded border border-dashed p-2">
          <div className="flex flex-wrap gap-1">
            {MOTIVOS_RAPIDOS.map((m) => (
              <Button key={m} type="button" size="sm" variant={motivo === m ? 'secondary' : 'outline'}
                className="h-6 px-2 text-[11px]" onClick={() => setMotivo(motivo === m ? '' : m)}>
                {m}
              </Button>
            ))}
          </div>
          <div className="flex items-center gap-2">
            <Input value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="Motivo (opcional)"
              aria-label="Motivo do descarte" className="h-7 min-w-0 flex-1 text-xs"
              onKeyDown={(e) => { if (e.key === 'Enter') descartar(); }} />
            <Button size="sm" variant="destructive" className="h-7 shrink-0" disabled={busy} onClick={descartar}>
              Descartar
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}
