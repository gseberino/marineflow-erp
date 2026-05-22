import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { FileText, ChevronDown, ChevronUp, Loader2 } from 'lucide-react';

type Draft = {
  id: string;
  kind: string;
  status: string;
  title: string | null;
  summary: string | null;
  interpreted_intent: string | null;
  interpreted_category: string | null;
  estimated_total: number | null;
  pending_questions: string[] | null;
  next_steps: string[] | null;
  hypotheses: string[] | null;
};

type DraftItem = {
  id: string;
  item_kind: string;
  description: string;
  notes: string | null;
  quantity: number | null;
  unit: string | null;
  unit_price: number | null;
  estimated_total: number | null;
  confidence: string | null;
};

const KIND_LABELS: Record<string, string> = {
  quote: '📋 Orçamento (rascunho)',
  diagnosis: '🩺 Diagnóstico',
  service_plan: '🛠️ Plano de Serviço',
  agenda_proposal: '📅 Proposta de Agenda',
  response_suggestion: '💬 Sugestão de Resposta',
  note: '📝 Nota técnica',
};

const ITEM_KIND_LABELS: Record<string, string> = {
  service: 'Mão de obra',
  product: 'Produto',
  product_to_quote: 'Item a cotar',
  displacement: 'Deslocamento',
  engineering: 'Engenharia/Diagnóstico',
  pending_question: 'Pergunta pendente',
  risk: 'Risco / observação',
  reference: 'Referência',
};

export function AIOperatorDraftCard({ draftId }: { draftId: string }) {
  const [draft, setDraft] = useState<Draft | null>(null);
  const [items, setItems] = useState<DraftItem[]>([]);
  const [expanded, setExpanded] = useState(true);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    async function load() {
      setLoading(true);
      const [{ data: d }, { data: its }] = await Promise.all([
        supabase.from('ai_operator_drafts').select('*').eq('id', draftId).maybeSingle(),
        supabase.from('ai_operator_draft_items').select('*').eq('draft_id', draftId).order('position'),
      ]);
      if (cancelled) return;
      setDraft((d as Draft) ?? null);
      setItems((its as DraftItem[]) ?? []);
      setLoading(false);
    }
    load();
    return () => {
      cancelled = true;
    };
  }, [draftId]);

  if (loading) {
    return (
      <div className="rounded-lg border bg-muted/30 p-3 flex items-center gap-2 text-xs text-muted-foreground">
        <Loader2 className="h-3.5 w-3.5 animate-spin" /> Carregando rascunho do operador…
      </div>
    );
  }
  if (!draft) {
    return (
      <div className="rounded-lg border border-red-500/40 bg-red-500/5 p-3 text-xs text-red-600">
        Rascunho não encontrado.
      </div>
    );
  }

  const fmtMoney = (v: number | null) =>
    v == null ? '—' : new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);

  return (
    <div className="rounded-lg border border-primary/30 bg-primary/[0.03] p-3 space-y-2">
      <div className="flex items-start gap-2">
        <FileText className="h-4 w-4 text-primary mt-0.5 shrink-0" />
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="text-xs font-semibold uppercase tracking-wide text-primary">
              {KIND_LABELS[draft.kind] ?? draft.kind}
            </span>
            <span className="text-[10px] px-1.5 py-0.5 rounded bg-muted text-muted-foreground">
              {draft.status}
            </span>
          </div>
          <h4 className="text-sm font-semibold mt-1">{draft.title || 'Sem título'}</h4>
          {draft.summary && (
            <p className="text-xs text-muted-foreground mt-1 whitespace-pre-line">{draft.summary}</p>
          )}
        </div>
        <button
          onClick={() => setExpanded((e) => !e)}
          className="text-muted-foreground hover:text-foreground"
          aria-label="Expandir"
        >
          {expanded ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
        </button>
      </div>

      {expanded && (
        <div className="space-y-2 pl-6 text-xs">
          {draft.estimated_total != null && (
            <div className="text-muted-foreground">
              <span className="font-medium">Estimativa de referência: </span>
              <span>{fmtMoney(draft.estimated_total)}</span>
              <span className="text-[10px] ml-1">(não é preço fechado)</span>
            </div>
          )}

          {items.length > 0 && (
            <div>
              <div className="font-medium text-muted-foreground mb-1">Itens</div>
              <ul className="space-y-1">
                {items.map((it) => (
                  <li key={it.id} className="border-l-2 border-muted pl-2">
                    <div className="flex justify-between gap-2 items-start">
                      <div>
                        <span className="text-[10px] uppercase tracking-wide text-muted-foreground">
                          {ITEM_KIND_LABELS[it.item_kind] ?? it.item_kind}
                        </span>
                        <div>{it.description}</div>
                        {it.notes && <div className="text-muted-foreground italic">{it.notes}</div>}
                      </div>
                      {it.estimated_total != null && (
                        <div className="text-right text-muted-foreground">{fmtMoney(it.estimated_total)}</div>
                      )}
                    </div>
                  </li>
                ))}
              </ul>
            </div>
          )}

          {Array.isArray(draft.pending_questions) && draft.pending_questions.length > 0 && (
            <div>
              <div className="font-medium text-muted-foreground mb-1">Perguntas pendentes</div>
              <ul className="list-disc pl-4 space-y-0.5">
                {draft.pending_questions.map((q, i) => (
                  <li key={i}>{q}</li>
                ))}
              </ul>
            </div>
          )}

          {Array.isArray(draft.next_steps) && draft.next_steps.length > 0 && (
            <div>
              <div className="font-medium text-muted-foreground mb-1">Próximos passos</div>
              <ul className="list-disc pl-4 space-y-0.5">
                {draft.next_steps.map((s, i) => (
                  <li key={i}>{s}</li>
                ))}
              </ul>
            </div>
          )}

          {Array.isArray(draft.hypotheses) && draft.hypotheses.length > 0 && (
            <div>
              <div className="font-medium text-muted-foreground mb-1">Hipóteses</div>
              <ul className="list-disc pl-4 space-y-0.5">
                {draft.hypotheses.map((h, i) => (
                  <li key={i}>{h}</li>
                ))}
              </ul>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
