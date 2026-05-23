import { useMemo, useState } from "react";
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
  const [selectedClientId, setSelectedClientId] = useState(proposal.client?.id ?? "");
  const [selectedVesselId, setSelectedVesselId] = useState(proposal.vessel?.id ?? "");
  const clientOptions = proposal.client_candidates ?? [];
  const vesselOptions = proposal.vessel_candidates ?? [];
  const selectedClient = useMemo(
    () => proposal.client ?? clientOptions.find((candidate) => candidate.id === selectedClientId) ?? null,
    [clientOptions, proposal.client, selectedClientId]
  );
  const selectedVessel = useMemo(
    () => proposal.vessel ?? vesselOptions.find((candidate) => candidate.id === selectedVesselId) ?? null,
    [proposal.vessel, selectedVesselId, vesselOptions]
  );
  const clientLine = selectedClient?.name ?? null;
  const vesselLine = selectedVessel?.name ?? null;
  const canConfirm = !!(selectedClient || selectedVessel);
  const confirmProposal = { ...proposal, client: selectedClient, vessel: selectedVessel };

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
      {proposal.compatibility?.message && (
        <p className="text-xs text-muted-foreground">{proposal.compatibility.message}</p>
      )}
      {clientOptions.length > 0 && (
        <div className="space-y-1">
          <p className="text-xs font-medium text-muted-foreground">Selecione o cliente</p>
          <div className="grid gap-1">
            {clientOptions.map((candidate) => (
              <Button
                key={candidate.id}
                type="button"
                variant={selectedClientId === candidate.id ? "default" : "outline"}
                size="sm"
                className="justify-start"
                onClick={() => setSelectedClientId(candidate.id)}
                disabled={disabled || status !== "pending"}
              >
                {candidate.name || "Cliente sem nome"}
                {candidate.subtitle ? ` - ${candidate.subtitle}` : ""}
              </Button>
            ))}
          </div>
        </div>
      )}
      {vesselOptions.length > 0 && (
        <div className="space-y-1">
          <p className="text-xs font-medium text-muted-foreground">Selecione a embarcacao</p>
          <div className="grid gap-1">
            {vesselOptions.map((candidate) => (
              <Button
                key={candidate.id}
                type="button"
                variant={selectedVesselId === candidate.id ? "default" : "outline"}
                size="sm"
                className="justify-start"
                onClick={() => setSelectedVesselId(candidate.id)}
                disabled={disabled || status !== "pending"}
              >
                {candidate.name || "Embarcacao sem nome"}
                {candidate.subtitle ? ` - ${candidate.subtitle}` : ""}
              </Button>
            ))}
          </div>
        </div>
      )}
      {proposal.rationale && <p className="text-xs italic text-muted-foreground">{proposal.rationale}</p>}
      {status === "pending" && (
        <div className="flex gap-2">
          <Button size="sm" onClick={() => onConfirm(confirmProposal)} disabled={disabled || !canConfirm} className="gap-1">
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
