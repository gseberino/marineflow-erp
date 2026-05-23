import { FileText, Check } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import type { OperatorDraftCandidate } from "@/hooks/use-ai-operator";
import {
  formatDraftKind,
  formatDraftStatus,
  statusBadgeVariant,
} from "@/lib/ai-operator-display";

type Props = {
  candidates: OperatorDraftCandidate[];
  status: "pending" | "resolved";
  selectedDraftId?: string | null;
  disabled?: boolean;
  onSelect: (candidate: OperatorDraftCandidate) => void;
};

export function AIOperatorDraftSelectionCard({
  candidates,
  status,
  selectedDraftId,
  disabled,
  onSelect,
}: Props) {
  if (candidates.length === 0) {
    return (
      <div className="rounded-lg border border-dashed border-amber-500/40 bg-amber-500/5 p-3 text-xs text-amber-700">
        Nenhum rascunho ativo encontrado para selecionar. Crie um novo pelo Operador ou ajuste sua descrição.
      </div>
    );
  }

  return (
    <div className="space-y-2 rounded-lg border border-primary/30 bg-primary/[0.04] p-3">
      <div className="flex items-center gap-2">
        <FileText className="h-4 w-4 text-primary" />
        <span className="text-xs font-semibold uppercase tracking-wide text-primary">
          {status === "resolved" ? "Rascunho selecionado" : "Selecione o rascunho"}
        </span>
      </div>
      <p className="text-xs text-muted-foreground">
        {status === "resolved"
          ? "Continuando o atendimento no rascunho escolhido."
          : "Você mencionou um rascunho existente. Escolha qual continuar — nenhum novo rascunho será criado."}
      </p>
      <ul className="space-y-2">
        {candidates.map((candidate) => {
          const isSelected = selectedDraftId === candidate.id;
          return (
            <li
              key={candidate.id}
              className={`rounded-md border p-2 text-sm transition-colors ${
                isSelected ? "border-primary bg-primary/10" : "border-border bg-background"
              }`}
            >
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0 flex-1">
                  <p className="truncate font-medium">{candidate.title || "Sem título"}</p>
                  <div className="mt-1 flex flex-wrap items-center gap-1.5">
                    <Badge variant="secondary" className="text-[10px]">
                      {formatDraftKind(candidate.kind)}
                    </Badge>
                    <Badge variant={statusBadgeVariant(candidate.status)} className="text-[10px]">
                      {formatDraftStatus(candidate.status)}
                    </Badge>
                  </div>
                  <p className="mt-1 text-xs text-muted-foreground">
                    {candidate.client_name || "Cliente não vinculado"} ·{" "}
                    {candidate.vessel_name || "Embarcação não vinculada"}
                  </p>
                  {candidate.summary && (
                    <p className="mt-1 line-clamp-2 text-xs text-muted-foreground">{candidate.summary}</p>
                  )}
                </div>
                <Button
                  size="sm"
                  variant={isSelected ? "default" : "outline"}
                  disabled={disabled || status === "resolved"}
                  onClick={() => onSelect(candidate)}
                  className="gap-1 shrink-0"
                >
                  {isSelected ? <Check className="h-3.5 w-3.5" /> : null}
                  {isSelected ? "Selecionado" : "Continuar este"}
                </Button>
              </div>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
