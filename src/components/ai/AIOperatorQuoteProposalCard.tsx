import { Check, FileText, X } from "lucide-react";
import { Link } from "react-router-dom";
import { Button } from "@/components/ui/button";
import type { OperatorQuoteProposal } from "@/hooks/use-ai-operator";

type Props = {
  proposal: OperatorQuoteProposal;
  status: "pending" | "created" | "rejected";
  disabled?: boolean;
  externalQuote?: { id: string; quote_number: string | null; status: string | null; path: string } | null;
  onConfirm: (proposal: OperatorQuoteProposal) => void;
  onReject: (draftId: string) => void;
};

const statusLabel: Record<OperatorQuoteProposal["initial_status"], string> = {
  draft: "Rascunho formal",
  pending_product: "Pendente de produto/cotacao",
};

export function AIOperatorQuoteProposalCard({
  proposal,
  status,
  disabled,
  externalQuote,
  onConfirm,
  onReject,
}: Props) {
  return (
    <div className="space-y-3 rounded-lg border border-primary/30 bg-primary/[0.04] p-3">
      <div className="flex items-center gap-2">
        <FileText className="h-4 w-4 text-primary" />
        <span className="text-xs font-semibold uppercase tracking-wide text-primary">
          Proposta de orcamento formal
        </span>
      </div>

      <div className="space-y-1 text-sm">
        <p>
          Criar orcamento formal para <strong>{proposal.draft_title || "(sem titulo)"}</strong>.
        </p>
        <p>
          Cliente: <strong>{proposal.client_name || "nao vinculado"}</strong>
        </p>
        <p>
          Embarcacao: <strong>{proposal.vessel_name || "nao vinculada"}</strong>
        </p>
      </div>

      <div className="grid grid-cols-2 gap-2 text-xs text-muted-foreground">
        <div>Itens: {proposal.item_count}</div>
        <div>Servicos: {proposal.service_count}</div>
        <div>Produtos: {proposal.part_count}</div>
        <div>Pendentes: {proposal.pending_item_count}</div>
        <div>Perguntas: {proposal.pending_questions_count}</div>
        <div>Status inicial: {statusLabel[proposal.initial_status]}</div>
      </div>

      <div className="rounded-md bg-background/70 p-2 text-xs text-muted-foreground">
        Sera criado um orcamento formal no ERP. Nao sera criada OS, nao sera enviado WhatsApp,
        nao havera movimentacao de estoque, financeiro ou agenda.
      </div>

      {status === "pending" && (
        <div className="flex gap-2">
          <Button size="sm" onClick={() => onConfirm(proposal)} disabled={disabled} className="gap-1">
            <Check className="h-4 w-4" /> Confirmar orcamento
          </Button>
          <Button
            size="sm"
            variant="outline"
            onClick={() => onReject(proposal.draft_id)}
            disabled={disabled}
            className="gap-1"
          >
            <X className="h-4 w-4" /> Cancelar
          </Button>
        </div>
      )}

      {status === "created" && externalQuote && (
        <div className="space-y-2">
          <p className="text-xs italic text-emerald-700">
            Orcamento formal criado. Nenhuma Ordem de Servico foi criada.
          </p>
          <Button asChild size="sm" variant="outline">
            <Link to={externalQuote.path}>Abrir orcamento formal</Link>
          </Button>
        </div>
      )}

      {status === "rejected" && (
        <p className="text-xs italic text-muted-foreground">
          Proposta dispensada. Nenhum orcamento formal foi criado.
        </p>
      )}
    </div>
  );
}
