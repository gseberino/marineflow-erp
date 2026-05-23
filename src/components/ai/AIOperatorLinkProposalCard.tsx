import { Link2, Check, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import type { OperatorLinkProposal } from "@/hooks/use-ai-operator";

type Props = {
  proposal: OperatorLinkProposal;
  status: "pending" | "confirmed" | "rejected";
  disabled?: boolean;
  onConfirm: (proposal: OperatorLinkProposal) => void;
  onReject: (draftId: string) => void;
};

export function AIOperatorLinkProposalCard({ proposal, status, disabled, onConfirm, onReject }: Props) {
  const clientLine = proposal.client?.name ?? null;
  const vesselLine = proposal.vessel?.name ?? null;

  return (
    <div className="space-y-2 rounded-lg border border-primary/30 bg-primary/[0.04] p-3">
      <div className="flex items-center gap-2">
        <Link2 className="h-4 w-4 text-primary" />
        <span className="text-xs font-semibold uppercase tracking-wide text-primary">
          Proposta de vínculo
        </span>
      </div>
      <p className="text-sm">
        Vincular o rascunho{" "}
        <strong>{proposal.draft_title || "(sem título)"}</strong>
        {clientLine ? (
          <>
            {" "}
            ao cliente <strong>{clientLine}</strong>
          </>
        ) : null}
        {vesselLine ? (
          <>
            {clientLine ? " e " : " à "}
            embarcação <strong>{vesselLine}</strong>
          </>
        ) : null}
        ?
      </p>
      {proposal.rationale && <p className="text-xs italic text-muted-foreground">{proposal.rationale}</p>}
      {status === "pending" && (
        <div className="flex gap-2">
          <Button size="sm" onClick={() => onConfirm(proposal)} disabled={disabled} className="gap-1">
            <Check className="h-4 w-4" /> Confirmar vínculo
          </Button>
          <Button
            size="sm"
            variant="outline"
            onClick={() => onReject(proposal.draft_id)}
            disabled={disabled}
            className="gap-1"
          >
            <X className="h-4 w-4" /> Rejeitar
          </Button>
        </div>
      )}
      {status === "confirmed" && (
        <p className="text-xs italic text-emerald-700">✓ Vínculo confirmado. Os dados foram atualizados.</p>
      )}
      {status === "rejected" && (
        <p className="text-xs italic text-muted-foreground">✕ Proposta dispensada. Nenhum vínculo foi gravado.</p>
      )}
    </div>
  );
}
