import { useEffect, useMemo, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { ArrowLeft, Bot, Loader2, Save } from "lucide-react";
import { PageHeader } from "@/components/PageHeader";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { ClientCombobox } from "@/components/ClientCombobox";
import { VesselSelect } from "@/components/VesselSelect";
import { useClients } from "@/hooks/use-clients";
import { useVesselsForClient } from "@/hooks/use-vessels";
import {
  useAIOperatorDraftDetail,
  useLinkAIOperatorDraftEntities,
} from "@/hooks/use-ai-operator-drafts";
import { useAIOperator } from "@/hooks/use-ai-operator";
import { AIChatMessage } from "@/components/ai/AIChatMessage";
import { AIOperatorPendingActionCard } from "@/components/ai/AIOperatorPendingActionCard";

function formatMoney(value: number | null) {
  if (value == null) return "Sem estimativa";
  return new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(value);
}

export default function AIOperatorDraftDetailPage() {
  const { id } = useParams();
  const { data, isLoading } = useAIOperatorDraftDetail(id);
  const { data: clients } = useClients();
  const [selectedClientId, setSelectedClientId] = useState("");
  const [selectedVesselId, setSelectedVesselId] = useState("");
  const { data: vessels = [] } = useVesselsForClient(selectedClientId || undefined);
  const linkEntities = useLinkAIOperatorDraftEntities();
  const [showOperator, setShowOperator] = useState(false);
  const [operatorInput, setOperatorInput] = useState("");

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

  const groupedItems = useMemo(() => data?.items || [], [data]);

  if (isLoading) {
    return (
      <div className="flex items-center gap-2 text-sm text-muted-foreground">
        <Loader2 className="h-4 w-4 animate-spin" /> Carregando rascunho...
      </div>
    );
  }

  if (!data) {
    return <div className="text-sm text-destructive">Rascunho nao encontrado.</div>;
  }

  const handleSaveLinks = async () => {
    await linkEntities.mutateAsync({
      draftId: data.draft.id,
      clientId: selectedClientId || null,
      vesselId: selectedVesselId || null,
    });
  };

  const handleContinue = async () => {
    const text = operatorInput.trim();
    if (!text) return;
    setOperatorInput("");
    await operator.sendMessage(text);
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader
        title={data.draft.title || "Rascunho do Operador"}
        description="Detalhe persistente do rascunho interno do MarineFlow AI Operator."
      >
        <Link to="/operator/drafts">
          <Button variant="outline" className="gap-2">
            <ArrowLeft className="h-4 w-4" /> Voltar para Rascunhos
          </Button>
        </Link>
        <Button className="gap-2" onClick={() => setShowOperator((current) => !current)}>
          <Bot className="h-4 w-4" /> Continuar com o Operador
        </Button>
      </PageHeader>

      <Card className="border-primary/20 bg-primary/[0.03]">
        <CardContent className="space-y-2 p-4">
          <div className="flex flex-wrap items-center gap-2">
            <Badge variant="outline" className="border-primary/30 text-primary">
              Rascunho interno do Operador
            </Badge>
            <Badge variant="secondary">{data.draft.kind}</Badge>
            <Badge variant="outline">{data.draft.status}</Badge>
          </div>
          <p className="text-sm font-medium">Este registro ainda nao e uma Ordem de Servico.</p>
          <p className="text-sm text-muted-foreground">
            Nenhuma OS oficial foi criada automaticamente e nenhuma acao sensivel foi executada.
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
              {data.draft.summary && <p>{data.draft.summary}</p>}
              <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
                <div>
                  <span className="text-muted-foreground">Cliente</span>
                  <p>{data.draft.client_name || "Cliente nao vinculado"}</p>
                </div>
                <div>
                  <span className="text-muted-foreground">Embarcacao</span>
                  <p>{data.draft.vessel_name || "Embarcacao nao vinculada"}</p>
                </div>
                <div>
                  <span className="text-muted-foreground">Itens</span>
                  <p>{data.draft.item_count} itens</p>
                </div>
                <div>
                  <span className="text-muted-foreground">Estimativa</span>
                  <p>{formatMoney(data.draft.estimated_total)}</p>
                </div>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Itens tecnicos</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              {groupedItems.map((item) => (
                <div key={item.id} className="rounded-lg border p-3 text-sm">
                  <div className="flex items-center justify-between gap-2">
                    <Badge variant="outline">{item.item_kind}</Badge>
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

          {showOperator && (
            <Card>
              <CardHeader>
                <CardTitle>Continuar com o Operador</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="rounded-lg border border-dashed px-3 py-2 text-xs text-muted-foreground">
                  Esta conversa continua no mesmo contexto seguro do rascunho. Nenhum UUID precisa ser digitado.
                </div>
                <div className="max-h-[360px] space-y-3 overflow-y-auto rounded-lg border p-3">
                  {operator.display.length === 0 && !operator.loading && (
                    <p className="text-sm text-muted-foreground">
                      Retome o atendimento a partir deste rascunho. O contexto da sessao e do draft ja foi carregado.
                    </p>
                  )}
                  {operator.display.map((item, index) => {
                    if (item.kind === "message") {
                      return <AIChatMessage key={index} role={item.role} content={item.content} />;
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
                <div className="flex gap-2">
                  <Textarea
                    value={operatorInput}
                    onChange={(event) => setOperatorInput(event.target.value)}
                    placeholder="Continue este atendimento tecnico..."
                    rows={3}
                  />
                  <Button onClick={handleContinue} disabled={operator.loading || !operatorInput.trim()}>
                    Enviar
                  </Button>
                </div>
              </CardContent>
            </Card>
          )}
        </div>

        <div className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle>Vinculo estruturado</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="space-y-2">
                <label className="text-sm font-medium">Cliente</label>
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
                <label className="text-sm font-medium">Embarcacao</label>
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
                Salvar vinculos com validacao segura
              </Button>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Pendencias e proximos passos</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4 text-sm">
              <div>
                <p className="font-medium">Perguntas pendentes</p>
                <ul className="mt-2 list-disc space-y-1 pl-4">
                  {data.draft.pending_questions.length > 0 ? (
                    data.draft.pending_questions.map((question, index) => <li key={index}>{question}</li>)
                  ) : (
                    <li>Nenhuma pergunta pendente registrada.</li>
                  )}
                </ul>
              </div>
              <div>
                <p className="font-medium">Hipoteses</p>
                <ul className="mt-2 list-disc space-y-1 pl-4">
                  {data.draft.hypotheses.length > 0 ? (
                    data.draft.hypotheses.map((item, index) => <li key={index}>{item}</li>)
                  ) : (
                    <li>Nenhuma hipotese registrada.</li>
                  )}
                </ul>
              </div>
              <div>
                <p className="font-medium">Proximos passos</p>
                <ul className="mt-2 list-disc space-y-1 pl-4">
                  {data.draft.next_steps.length > 0 ? (
                    data.draft.next_steps.map((item, index) => <li key={index}>{item}</li>)
                  ) : (
                    <li>Nenhum proximo passo registrado.</li>
                  )}
                </ul>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Trilha basica</CardTitle>
            </CardHeader>
            <CardContent className="space-y-2 text-sm">
              <p>Criado em {new Date(data.draft.created_at).toLocaleString("pt-BR")}</p>
              <p>Atualizado em {new Date(data.draft.updated_at).toLocaleString("pt-BR")}</p>
              {data.session && <p>Ultima atividade da sessao em {new Date(data.session.last_activity_at).toLocaleString("pt-BR")}</p>}
              <p>Nenhuma OS oficial vinculada a este rascunho.</p>
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}
