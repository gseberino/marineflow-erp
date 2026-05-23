import { useState } from "react";
import { Link } from "react-router-dom";
import { FileText, ChevronDown, ChevronUp, Loader2 } from "lucide-react";
import { useAIOperatorDraftDetail } from "@/hooks/use-ai-operator-drafts";

const KIND_LABELS: Record<string, string> = {
  quote: "Orcamento (rascunho)",
  diagnosis: "Diagnostico",
  service_plan: "Plano de Servico",
  agenda_proposal: "Proposta de Agenda",
  response_suggestion: "Sugestao de Resposta",
  note: "Nota tecnica",
};

const ITEM_KIND_LABELS: Record<string, string> = {
  service: "Mao de obra",
  product: "Produto",
  product_to_quote: "Item a cotar",
  displacement: "Deslocamento",
  engineering: "Engenharia/Diagnostico",
  pending_question: "Pergunta pendente",
  risk: "Risco / observacao",
  reference: "Referencia",
};

export function AIOperatorDraftCard({ draftId }: { draftId: string }) {
  const [expanded, setExpanded] = useState(true);
  const { data, isLoading } = useAIOperatorDraftDetail(draftId);
  const draft = data?.draft ?? null;
  const items = data?.items ?? [];

  if (isLoading) {
    return (
      <div className="flex items-center gap-2 rounded-lg border bg-muted/30 p-3 text-xs text-muted-foreground">
        <Loader2 className="h-3.5 w-3.5 animate-spin" /> Carregando rascunho do operador...
      </div>
    );
  }

  if (!draft) {
    return (
      <div className="rounded-lg border border-red-500/40 bg-red-500/5 p-3 text-xs text-red-600">
        Rascunho nao encontrado.
      </div>
    );
  }

  const fmtMoney = (value: number | null) =>
    value == null ? "-" : new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(value);

  return (
    <div className="space-y-2 rounded-lg border border-primary/30 bg-primary/[0.03] p-3">
      <div className="flex items-start gap-2">
        <FileText className="mt-0.5 h-4 w-4 shrink-0 text-primary" />
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-xs font-semibold uppercase tracking-wide text-primary">
              {KIND_LABELS[draft.kind] ?? draft.kind}
            </span>
            <span className="rounded bg-muted px-1.5 py-0.5 text-[10px] text-muted-foreground">
              {draft.status}
            </span>
          </div>
          <h4 className="mt-1 text-sm font-semibold">{draft.title || "Sem titulo"}</h4>
          {draft.summary && <p className="mt-1 whitespace-pre-line text-xs text-muted-foreground">{draft.summary}</p>}
          <p className="mt-2 text-[11px] font-medium text-primary">
            Rascunho interno do Operador - ainda nao e uma Ordem de Servico.
          </p>
        </div>
        <button
          onClick={() => setExpanded((current) => !current)}
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
              <span className="font-medium">Estimativa de referencia: </span>
              <span>{fmtMoney(draft.estimated_total)}</span>
              <span className="ml-1 text-[10px]">(nao e preco fechado)</span>
            </div>
          )}

          {items.length > 0 && (
            <div>
              <div className="mb-1 font-medium text-muted-foreground">Itens</div>
              <ul className="space-y-1">
                {items.map((item) => (
                  <li key={item.id} className="border-l-2 border-muted pl-2">
                    <div className="flex items-start justify-between gap-2">
                      <div>
                        <span className="text-[10px] uppercase tracking-wide text-muted-foreground">
                          {ITEM_KIND_LABELS[item.item_kind] ?? item.item_kind}
                        </span>
                        <div>{item.description}</div>
                        {item.notes && <div className="italic text-muted-foreground">{item.notes}</div>}
                      </div>
                      {item.estimated_total != null && (
                        <div className="text-right text-muted-foreground">{fmtMoney(item.estimated_total)}</div>
                      )}
                    </div>
                  </li>
                ))}
              </ul>
            </div>
          )}

          {draft.pending_questions.length > 0 && (
            <div>
              <div className="mb-1 font-medium text-muted-foreground">Perguntas pendentes</div>
              <ul className="list-disc space-y-0.5 pl-4">
                {draft.pending_questions.map((question, index) => (
                  <li key={index}>{question}</li>
                ))}
              </ul>
            </div>
          )}

          {draft.next_steps.length > 0 && (
            <div>
              <div className="mb-1 font-medium text-muted-foreground">Proximos passos</div>
              <ul className="list-disc space-y-0.5 pl-4">
                {draft.next_steps.map((step, index) => (
                  <li key={index}>{step}</li>
                ))}
              </ul>
            </div>
          )}

          {draft.hypotheses.length > 0 && (
            <div>
              <div className="mb-1 font-medium text-muted-foreground">Hipoteses</div>
              <ul className="list-disc space-y-0.5 pl-4">
                {draft.hypotheses.map((hypothesis, index) => (
                  <li key={index}>{hypothesis}</li>
                ))}
              </ul>
            </div>
          )}

          <div className="pt-1">
            <Link
              to={`/operator/drafts/${draft.id}`}
              className="text-xs font-medium text-primary hover:underline"
              aria-label="Abrir detalhe do rascunho"
            >
              Abrir detalhe do rascunho
            </Link>
          </div>
        </div>
      )}
    </div>
  );
}
