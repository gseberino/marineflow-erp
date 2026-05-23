import { useEffect, useMemo, useRef, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { ArrowLeft, Ban, Bot, Loader2, Save, Send } from "lucide-react";
import { PageHeader } from "@/components/PageHeader";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { toast } from "sonner";
import { ClientCombobox } from "@/components/ClientCombobox";
import { VesselSelect } from "@/components/VesselSelect";
import { useClients } from "@/hooks/use-clients";
import { useVesselsForClient } from "@/hooks/use-vessels";
import {
  useAIOperatorDraftDetail,
  useCancelAIOperatorDraft,
  useLinkAIOperatorDraftEntities,
} from "@/hooks/use-ai-operator-drafts";
import { useAIOperator } from "@/hooks/use-ai-operator";
import { AIChatMessage } from "@/components/ai/AIChatMessage";
import { AIOperatorDraftSelectionCard } from "@/components/ai/AIOperatorDraftSelectionCard";
import { AIOperatorLinkProposalCard } from "@/components/ai/AIOperatorLinkProposalCard";
import { AIOperatorPendingActionCard } from "@/components/ai/AIOperatorPendingActionCard";
import {
  formatDraftKind,
  formatDraftItemKind,
  formatDraftStatus,
  statusBadgeVariant,
} from "@/lib/ai-operator-display";

function formatMoney(value: number | null) {
  if (value == null) return "Sem estimativa";
  return new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(value);
}

const CANCELLABLE_STATUSES = new Set(["draft", "awaiting_info"]);

export default function AIOperatorDraftDetailPage() {
  const { id } = useParams();
  const { data, isLoading } = useAIOperatorDraftDetail(id);
  const { data: clients } = useClients();
  const [selectedClientId, setSelectedClientId] = useState("");
  const [selectedVesselId, setSelectedVesselId] = useState("");
  const { data: vessels = [] } = useVesselsForClient(selectedClientId || undefined);
  const linkEntities = useLinkAIOperatorDraftEntities();
  const cancelDraft = useCancelAIOperatorDraft();
  const [operatorOpen, setOperatorOpen] = useState(false);
  const [operatorInput, setOperatorInput] = useState("");
  const [cancelOpen, setCancelOpen] = useState(false);
  const [cancelReason, setCancelReason] = useState("");
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  const operator = useAIOperator(
    { route: `/operator/drafts/${id}`, entityType: "operator_draft", entityId: id },
    {
      initialSessionId: data?.session?.id ?? null,
      initialDraftId: data?.draft.id ?? null,
    }
  );

  useEffect(() => {
    if (!data) return;
    setSelectedClientId(data.draft.client_id || "");
    setSelectedVesselId(data.draft.vessel_id || "");
  }, [data]);

  useEffect(() => {
    if (operatorOpen) {
      // Foca o textarea ao abrir o drawer — UX óbvia.
      requestAnimationFrame(() => textareaRef.current?.focus());
    }
  }, [operatorOpen]);

  const groupedItems = useMemo(() => data?.items || [], [data]);

  if (isLoading) {
    return (
      <div className="flex items-center gap-2 text-sm text-muted-foreground">
        <Loader2 className="h-4 w-4 animate-spin" /> Carregando rascunho...
      </div>
    );
  }

  if (!data) {
    return <div className="text-sm text-destructive">Rascunho não encontrado.</div>;
  }

  const draft = data.draft;
  const canCancel = CANCELLABLE_STATUSES.has(draft.status);
  const hasOpenPending = (data.pendingActions || []).some((pa: any) => pa.status === "pending");

  const handleSaveLinks = async () => {
    try {
      await linkEntities.mutateAsync({
        draftId: draft.id,
        clientId: selectedClientId || null,
        vesselId: selectedVesselId || null,
      });
      toast.success("Vínculos atualizados com validação segura.");
    } catch (error: any) {
      toast.error(error?.message || "Falha ao atualizar vínculos.");
    }
  };

  const handleContinue = async () => {
    const text = operatorInput.trim();
    if (!text) return;
    setOperatorInput("");
    await operator.sendMessage(text);
  };

  const handleConfirmCancel = async () => {
    try {
      await cancelDraft.mutateAsync({
        draftId: draft.id,
        reason: cancelReason.trim() || undefined,
      });
      toast.success("Rascunho cancelado. Trilha de auditoria preservada.");
      setCancelOpen(false);
      setCancelReason("");
    } catch (error: any) {
      toast.error(error?.message || "Falha ao cancelar rascunho.");
    }
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader
        title={draft.title || "Rascunho do Operador"}
        description="Detalhe persistente do rascunho interno do MarineFlow AI Operator."
      >
        <Link to="/operator/drafts">
          <Button variant="outline" className="gap-2">
            <ArrowLeft className="h-4 w-4" /> Voltar para Rascunhos
          </Button>
        </Link>
        {canCancel && (
          <Button
            variant="outline"
            className="gap-2 border-destructive/40 text-destructive hover:bg-destructive/10"
            onClick={() => setCancelOpen(true)}
            disabled={cancelDraft.isPending || hasOpenPending}
            title={hasOpenPending ? "Resolva as ações pendentes antes de cancelar." : undefined}
          >
            <Ban className="h-4 w-4" /> Cancelar rascunho
          </Button>
        )}
        <Button className="gap-2" onClick={() => setOperatorOpen(true)}>
          <Bot className="h-4 w-4" /> Continuar com o Operador
        </Button>
      </PageHeader>

      <Card className="border-primary/20 bg-primary/[0.03]">
        <CardContent className="space-y-2 p-4">
          <div className="flex flex-wrap items-center gap-2">
            <Badge variant="outline" className="border-primary/30 text-primary">
              Rascunho interno do Operador
            </Badge>
            <Badge variant="secondary">{formatDraftKind(draft.kind)}</Badge>
            <Badge variant={statusBadgeVariant(draft.status)}>{formatDraftStatus(draft.status)}</Badge>
          </div>
          <p className="text-sm font-medium">Este registro ainda não é uma Ordem de Serviço.</p>
          <p className="text-sm text-muted-foreground">
            Nenhuma OS oficial foi criada automaticamente e nenhuma ação sensível foi executada.
          </p>
        </CardContent>
      </Card>

      <div className="grid grid-cols-1 gap-4 xl:grid-cols-[1.4fr_0.9fr]">
        <div className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle>Resumo operacional</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4 text-sm">
              {draft.summary && <p>{draft.summary}</p>}
              <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
                <div>
                  <span className="text-muted-foreground">Cliente</span>
                  <p>{draft.client_name || "Cliente não vinculado"}</p>
                </div>
                <div>
                  <span className="text-muted-foreground">Embarcação</span>
                  <p>{draft.vessel_name || "Embarcação não vinculada"}</p>
                </div>
                <div>
                  <span className="text-muted-foreground">Itens</span>
                  <p>{draft.item_count} itens</p>
                </div>
                <div>
                  <span className="text-muted-foreground">Estimativa</span>
                  <p>{formatMoney(draft.estimated_total)}</p>
                </div>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Itens técnicos</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              {groupedItems.length === 0 && (
                <p className="text-sm text-muted-foreground">Nenhum item registrado ainda.</p>
              )}
              {groupedItems.map((item) => (
                <div key={item.id} className="rounded-lg border p-3 text-sm">
                  <div className="flex items-center justify-between gap-2">
                    <Badge variant="outline">{formatDraftItemKind(item.item_kind)}</Badge>
                    <span className="text-xs text-muted-foreground">
                      {item.estimated_total != null ? formatMoney(item.estimated_total) : "Sem valor fechado"}
                    </span>
                  </div>
                  <p className="mt-2 font-medium">{item.description}</p>
                  {item.notes && <p className="mt-1 text-muted-foreground">{item.notes}</p>}
                </div>
              ))}
            </CardContent>
          </Card>
        </div>

        <div className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle>Vínculo estruturado</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="space-y-2">
                <Label className="text-sm font-medium">Cliente</Label>
                <ClientCombobox
                  value={selectedClientId}
                  onChange={(clientId) => {
                    setSelectedClientId(clientId);
                    setSelectedVesselId("");
                  }}
                  clients={clients}
                />
              </div>
              <div className="space-y-2">
                <Label className="text-sm font-medium">Embarcação</Label>
                <VesselSelect
                  value={selectedVesselId}
                  onChange={setSelectedVesselId}
                  vessels={(vessels as any[]) || []}
                  clientId={selectedClientId}
                  disabled={!selectedClientId}
                />
              </div>
              <Button
                onClick={handleSaveLinks}
                disabled={linkEntities.isPending}
                className="w-full gap-2"
              >
                <Save className="h-4 w-4" />
                Salvar vínculos com validação segura
              </Button>
              <p className="text-[11px] text-muted-foreground">
                Vínculo passa pela validação de visibilidade RLS do ERP. UUIDs não são exibidos.
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Pendências e próximos passos</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4 text-sm">
              <div>
                <p className="font-medium">Perguntas pendentes</p>
                <ul className="mt-2 list-disc space-y-1 pl-4">
                  {draft.pending_questions.length > 0 ? (
                    draft.pending_questions.map((question, index) => <li key={index}>{question}</li>)
                  ) : (
                    <li>Nenhuma pergunta pendente registrada.</li>
                  )}
                </ul>
              </div>
              <div>
                <p className="font-medium">Hipóteses</p>
                <ul className="mt-2 list-disc space-y-1 pl-4">
                  {draft.hypotheses.length > 0 ? (
                    draft.hypotheses.map((item, index) => <li key={index}>{item}</li>)
                  ) : (
                    <li>Nenhuma hipótese registrada.</li>
                  )}
                </ul>
              </div>
              <div>
                <p className="font-medium">Próximos passos</p>
                <ul className="mt-2 list-disc space-y-1 pl-4">
                  {draft.next_steps.length > 0 ? (
                    draft.next_steps.map((item, index) => <li key={index}>{item}</li>)
                  ) : (
                    <li>Nenhum próximo passo registrado.</li>
                  )}
                </ul>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Trilha básica</CardTitle>
            </CardHeader>
            <CardContent className="space-y-2 text-sm">
              <p>Criado em {new Date(draft.created_at).toLocaleString("pt-BR")}</p>
              <p>Atualizado em {new Date(draft.updated_at).toLocaleString("pt-BR")}</p>
              {data.session && (
                <p>
                  Última atividade da sessão em{" "}
                  {new Date(data.session.last_activity_at).toLocaleString("pt-BR")}
                </p>
              )}
              <p>Nenhuma OS oficial vinculada a este rascunho.</p>
            </CardContent>
          </Card>
        </div>
      </div>

      <Sheet open={operatorOpen} onOpenChange={setOperatorOpen}>
        <SheetContent side="right" className="flex w-full flex-col gap-0 p-0 sm:max-w-md">
          <SheetHeader className="border-b px-4 py-3">
            <SheetTitle className="flex items-center gap-2 text-base">
              <Bot className="h-4 w-4 text-primary" /> Continuar com o Operador
            </SheetTitle>
            <SheetDescription className="text-xs">
              Conversa no contexto do rascunho{" "}
              <strong>{draft.title || "(sem título)"}</strong>.
            </SheetDescription>
          </SheetHeader>

          <div className="flex-1 space-y-3 overflow-y-auto px-4 py-3">
            <div className="rounded-md border border-dashed bg-muted/40 px-3 py-2 text-[11px] text-muted-foreground">
              Conversa segura: nenhum UUID é exibido e nenhuma ação sensível é executada sem
              confirmação. As mensagens daqui sempre operam neste rascunho.
            </div>
            {operator.display.length === 0 && !operator.loading && (
              <p className="text-sm text-muted-foreground">
                Retome o atendimento. O contexto da sessão e do rascunho já foi carregado.
              </p>
            )}
            {operator.display.map((item, index) => {
              if (item.kind === "message") {
                return <AIChatMessage key={index} role={item.role} content={item.content} />;
              }
              if (item.kind === "draft_selection") {
                return (
                  <AIOperatorDraftSelectionCard
                    key={index}
                    candidates={item.candidates}
                    status={item.status}
                    selectedDraftId={item.selectedDraftId}
                    disabled={operator.loading}
                    onSelect={operator.selectDraftCandidate}
                  />
                );
              }
              if (item.kind === "link_proposal") {
                return (
                  <AIOperatorLinkProposalCard
                    key={index}
                    proposal={item.proposal}
                    status={item.status}
                    disabled={operator.loading}
                    onConfirm={operator.confirmLinkProposal}
                    onReject={operator.rejectLinkProposal}
                  />
                );
              }
              if (item.kind === "pending_action") {
                return (
                  <AIOperatorPendingActionCard
                    key={index}
                    action={item.action}
                    status={item.status}
                    disabled={operator.loading}
                    onApprove={operator.approveAction}
                    onReject={operator.rejectAction}
                  />
                );
              }
              return null;
            })}
            {operator.loading && (
              <div className="flex items-center gap-2 text-sm text-muted-foreground">
                <Loader2 className="h-4 w-4 animate-spin" /> Operador trabalhando...
              </div>
            )}
          </div>

          <div className="border-t px-4 py-3">
            <div className="flex gap-2">
              <Textarea
                ref={textareaRef}
                value={operatorInput}
                onChange={(event) => setOperatorInput(event.target.value)}
                onKeyDown={(event) => {
                  if (event.key === "Enter" && !event.shiftKey) {
                    event.preventDefault();
                    handleContinue();
                  }
                }}
                placeholder="Continue este atendimento técnico..."
                rows={3}
                className="resize-none"
              />
              <Button
                onClick={handleContinue}
                disabled={operator.loading || !operatorInput.trim()}
                size="icon"
                className="h-9 w-9 shrink-0 self-end"
              >
                <Send className="h-4 w-4" />
              </Button>
            </div>
            <p className="mt-1 text-[10px] text-muted-foreground">
              Enter envia · Shift+Enter quebra linha
            </p>
          </div>
        </SheetContent>
      </Sheet>

      <AlertDialog open={cancelOpen} onOpenChange={setCancelOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Cancelar este rascunho?</AlertDialogTitle>
            <AlertDialogDescription>
              Cancelar não apaga o rascunho — ele continua na trilha de auditoria, mas sai da
              visualização principal. Use quando o rascunho foi criado por engano. Não é possível
              cancelar drafts aprovados, rejeitados, convertidos ou com ações pendentes ainda em
              aberto.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <div className="space-y-2">
            <Label htmlFor="cancel-reason" className="text-sm">
              Justificativa (opcional)
            </Label>
            <Textarea
              id="cancel-reason"
              value={cancelReason}
              onChange={(event) => setCancelReason(event.target.value)}
              placeholder="Ex.: rascunho criado por engano pelo Operador."
              rows={3}
            />
          </div>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={cancelDraft.isPending}>Voltar</AlertDialogCancel>
            <AlertDialogAction
              onClick={handleConfirmCancel}
              disabled={cancelDraft.isPending}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              Confirmar cancelamento
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
