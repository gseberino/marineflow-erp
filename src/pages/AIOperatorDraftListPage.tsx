import { useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { FileText, Filter, Search, Ban } from "lucide-react";
import { PageHeader } from "@/components/PageHeader";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
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
import { Textarea } from "@/components/ui/textarea";
import { toast } from "sonner";
import {
  useAIOperatorDrafts,
  useCancelAIOperatorDraft,
  type AIOperatorDraftListItem,
} from "@/hooks/use-ai-operator-drafts";
import {
  DRAFT_KIND_LABELS,
  DRAFT_STATUS_LABELS,
  formatDraftKind,
  formatDraftStatus,
  statusBadgeVariant,
} from "@/lib/ai-operator-display";

function formatMoney(value: number | null) {
  if (value == null) return "Sem estimativa";
  return new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(value);
}

const CANCELLABLE_STATUSES = new Set(["draft", "awaiting_info"]);

export default function AIOperatorDraftListPage() {
  const { data, isLoading } = useAIOperatorDrafts();
  const cancelDraft = useCancelAIOperatorDraft();
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState("all");
  const [kindFilter, setKindFilter] = useState("all");
  const [sortBy, setSortBy] = useState("recent");
  const [showCancelled, setShowCancelled] = useState(false);
  const [cancelTarget, setCancelTarget] = useState<AIOperatorDraftListItem | null>(null);
  const [cancelReason, setCancelReason] = useState("");

  const drafts = useMemo(() => {
    const normalizedSearch = search.trim().toLowerCase();
    const filtered = (data || []).filter((draft) => {
      const matchesSearch =
        normalizedSearch.length === 0 ||
        [draft.title, draft.summary, draft.client_name, draft.vessel_name]
          .filter(Boolean)
          .join(" ")
          .toLowerCase()
          .includes(normalizedSearch);
      const matchesStatus = statusFilter === "all" || draft.status === statusFilter;
      const matchesKind = kindFilter === "all" || draft.kind === kindFilter;
      const matchesCancelled = showCancelled || draft.status !== "cancelled";
      return matchesSearch && matchesStatus && matchesKind && matchesCancelled;
    });

    return filtered.sort((left, right) => {
      const leftDate = new Date(left.updated_at).getTime();
      const rightDate = new Date(right.updated_at).getTime();
      return sortBy === "recent" ? rightDate - leftDate : leftDate - rightDate;
    });
  }, [data, search, statusFilter, kindFilter, sortBy, showCancelled]);

  const handleConfirmCancel = async () => {
    if (!cancelTarget) return;
    try {
      await cancelDraft.mutateAsync({
        draftId: cancelTarget.id,
        reason: cancelReason.trim() || undefined,
      });
      toast.success("Rascunho cancelado. Trilha de auditoria preservada.");
    } catch (error: any) {
      toast.error(error?.message || "Falha ao cancelar rascunho.");
    } finally {
      setCancelTarget(null);
      setCancelReason("");
    }
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader
        title="Rascunhos do Operador"
        description="Rascunhos internos persistentes do MarineFlow AI Operator. Eles não são Ordens de Serviço oficiais."
      />

      <Card className="border-dashed">
        <CardContent className="flex flex-col gap-3 p-4 lg:flex-row lg:items-center">
          <div className="relative flex-1">
            <Search className="pointer-events-none absolute left-3 top-3.5 h-4 w-4 text-muted-foreground" />
            <Input
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder="Buscar por título, resumo, cliente ou embarcação"
              className="pl-9"
            />
          </div>
          <div className="flex flex-col gap-3 sm:flex-row">
            <Select value={statusFilter} onValueChange={setStatusFilter}>
              <SelectTrigger className="w-full sm:w-[200px]">
                <SelectValue placeholder="Status" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">Todos os status</SelectItem>
                {Object.entries(DRAFT_STATUS_LABELS).map(([value, label]) => (
                  <SelectItem key={value} value={value}>
                    {label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Select value={kindFilter} onValueChange={setKindFilter}>
              <SelectTrigger className="w-full sm:w-[200px]">
                <SelectValue placeholder="Tipo" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">Todos os tipos</SelectItem>
                {Object.entries(DRAFT_KIND_LABELS).map(([value, label]) => (
                  <SelectItem key={value} value={value}>
                    {label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Select value={sortBy} onValueChange={setSortBy}>
              <SelectTrigger className="w-full sm:w-[170px]">
                <SelectValue placeholder="Ordenação" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="recent">Mais recentes</SelectItem>
                <SelectItem value="oldest">Mais antigos</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div className="flex items-center gap-2 sm:ml-auto">
            <Switch
              id="show-cancelled"
              checked={showCancelled}
              onCheckedChange={setShowCancelled}
            />
            <Label htmlFor="show-cancelled" className="text-xs">
              Mostrar cancelados
            </Label>
          </div>
        </CardContent>
      </Card>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        {isLoading ? (
          Array.from({ length: 4 }).map((_, index) => <Card key={index} className="h-48 animate-pulse bg-muted/40" />)
        ) : drafts.length === 0 ? (
          <Card className="col-span-full border-dashed">
            <CardContent className="flex flex-col items-center gap-3 py-16 text-center">
              <FileText className="h-10 w-10 text-muted-foreground/40" />
              <div>
                <p className="font-medium">Nenhum rascunho encontrado</p>
                <p className="text-sm text-muted-foreground">
                  Ajuste os filtros ou crie um novo rascunho pelo Modo Operador.
                </p>
              </div>
            </CardContent>
          </Card>
        ) : (
          drafts.map((draft) => {
            const canCancel = CANCELLABLE_STATUSES.has(draft.status);
            const isCancelled = draft.status === "cancelled";
            return (
              <Card
                key={draft.id}
                className={`overflow-hidden ${
                  isCancelled ? "border-destructive/20 opacity-80" : "border-primary/10"
                }`}
              >
                <CardHeader className="pb-3">
                  <div className="flex flex-wrap items-center gap-2">
                    <Badge variant="outline" className="border-primary/30 text-primary">
                      Rascunho interno do Operador
                    </Badge>
                    <Badge variant="secondary">{formatDraftKind(draft.kind)}</Badge>
                    <Badge variant={statusBadgeVariant(draft.status)}>{formatDraftStatus(draft.status)}</Badge>
                  </div>
                  <CardTitle className="text-lg">{draft.title || "Sem título"}</CardTitle>
                  {draft.summary && <p className="text-sm text-muted-foreground">{draft.summary}</p>}
                </CardHeader>
                <CardContent className="space-y-4">
                  <div className="grid grid-cols-1 gap-2 text-sm sm:grid-cols-2">
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
                      <span className="text-muted-foreground">Perguntas pendentes</span>
                      <p>{draft.pending_questions.length}</p>
                    </div>
                  </div>

                  <div className="rounded-lg bg-muted/40 p-3 text-sm">
                    <div className="flex items-center gap-2 text-muted-foreground">
                      <Filter className="h-4 w-4" />
                      <span>Este rascunho ainda não é uma Ordem de Serviço.</span>
                    </div>
                    <p className="mt-2 font-medium">{formatMoney(draft.estimated_total)}</p>
                  </div>

                  <div className="flex flex-wrap items-center justify-between gap-2 border-t pt-3">
                    <p className="text-xs text-muted-foreground">
                      Atualizado em {new Date(draft.updated_at).toLocaleString("pt-BR")}
                    </p>
                    <div className="flex gap-2">
                      {canCancel && (
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={() => setCancelTarget(draft)}
                          className="gap-1"
                          disabled={cancelDraft.isPending}
                        >
                          <Ban className="h-4 w-4" /> Cancelar
                        </Button>
                      )}
                      <Link to={`/operator/drafts/${draft.id}`}>
                        <Button size="sm">Abrir detalhes</Button>
                      </Link>
                    </div>
                  </div>
                </CardContent>
              </Card>
            );
          })
        )}
      </div>

      <AlertDialog
        open={cancelTarget !== null}
        onOpenChange={(open) => {
          if (!open) {
            setCancelTarget(null);
            setCancelReason("");
          }
        }}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Cancelar rascunho?</AlertDialogTitle>
            <AlertDialogDescription>
              Cancelar não apaga o rascunho — ele continua disponível na auditoria, mas sai da
              visualização principal. Use quando o rascunho foi criado por engano. Drafts aprovados,
              rejeitados, convertidos ou com ações pendentes não podem ser cancelados nesta fase.
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
