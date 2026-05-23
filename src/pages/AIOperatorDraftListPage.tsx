import { useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { FileText, Filter, Search } from "lucide-react";
import { PageHeader } from "@/components/PageHeader";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useAIOperatorDrafts } from "@/hooks/use-ai-operator-drafts";

function formatMoney(value: number | null) {
  if (value == null) return "Sem estimativa";
  return new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(value);
}

export default function AIOperatorDraftListPage() {
  const { data, isLoading } = useAIOperatorDrafts();
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState("all");
  const [kindFilter, setKindFilter] = useState("all");
  const [sortBy, setSortBy] = useState("recent");

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
      return matchesSearch && matchesStatus && matchesKind;
    });

    return filtered.sort((left, right) => {
      const leftDate = new Date(left.updated_at).getTime();
      const rightDate = new Date(right.updated_at).getTime();
      return sortBy === "recent" ? rightDate - leftDate : leftDate - rightDate;
    });
  }, [data, search, statusFilter, kindFilter, sortBy]);

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader
        title="Rascunhos do Operador"
        description="Rascunhos internos persistentes do MarineFlow AI Operator. Eles nao sao Ordens de Servico oficiais."
      />

      <Card className="border-dashed">
        <CardContent className="flex flex-col gap-3 p-4 lg:flex-row lg:items-center">
          <div className="relative flex-1">
            <Search className="pointer-events-none absolute left-3 top-3.5 h-4 w-4 text-muted-foreground" />
            <Input
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder="Buscar por titulo, resumo, cliente ou embarcacao"
              className="pl-9"
            />
          </div>
          <div className="flex flex-col gap-3 sm:flex-row">
            <Select value={statusFilter} onValueChange={setStatusFilter}>
              <SelectTrigger className="w-full sm:w-[170px]">
                <SelectValue placeholder="Status" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">Todos os status</SelectItem>
                <SelectItem value="draft">Draft</SelectItem>
                <SelectItem value="awaiting_info">Awaiting info</SelectItem>
                <SelectItem value="awaiting_approval">Awaiting approval</SelectItem>
                <SelectItem value="approved">Approved</SelectItem>
                <SelectItem value="rejected">Rejected</SelectItem>
                <SelectItem value="converted">Converted</SelectItem>
              </SelectContent>
            </Select>
            <Select value={kindFilter} onValueChange={setKindFilter}>
              <SelectTrigger className="w-full sm:w-[170px]">
                <SelectValue placeholder="Tipo" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">Todos os tipos</SelectItem>
                <SelectItem value="quote">Orcamento</SelectItem>
                <SelectItem value="diagnosis">Diagnostico</SelectItem>
                <SelectItem value="service_plan">Plano de servico</SelectItem>
                <SelectItem value="response_suggestion">Resposta sugerida</SelectItem>
                <SelectItem value="note">Nota tecnica</SelectItem>
              </SelectContent>
            </Select>
            <Select value={sortBy} onValueChange={setSortBy}>
              <SelectTrigger className="w-full sm:w-[170px]">
                <SelectValue placeholder="Ordenacao" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="recent">Mais recentes</SelectItem>
                <SelectItem value="oldest">Mais antigos</SelectItem>
              </SelectContent>
            </Select>
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
          drafts.map((draft) => (
            <Card key={draft.id} className="overflow-hidden border-primary/10">
              <CardHeader className="pb-3">
                <div className="flex flex-wrap items-center gap-2">
                  <Badge variant="outline" className="border-primary/30 text-primary">
                    Rascunho interno do Operador
                  </Badge>
                  <Badge variant="secondary">{draft.kind}</Badge>
                  <Badge variant="outline">{draft.status}</Badge>
                </div>
                <CardTitle className="text-lg">{draft.title || "Sem titulo"}</CardTitle>
                {draft.summary && <p className="text-sm text-muted-foreground">{draft.summary}</p>}
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="grid grid-cols-1 gap-2 text-sm sm:grid-cols-2">
                  <div>
                    <span className="text-muted-foreground">Cliente</span>
                    <p>{draft.client_name || "Cliente nao vinculado"}</p>
                  </div>
                  <div>
                    <span className="text-muted-foreground">Embarcacao</span>
                    <p>{draft.vessel_name || "Embarcacao nao vinculada"}</p>
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
                    <span>Este rascunho ainda nao e uma Ordem de Servico.</span>
                  </div>
                  <p className="mt-2 font-medium">{formatMoney(draft.estimated_total)}</p>
                </div>

                <div className="flex items-center justify-between border-t pt-3">
                  <p className="text-xs text-muted-foreground">
                    Atualizado em {new Date(draft.updated_at).toLocaleString("pt-BR")}
                  </p>
                  <Link to={`/operator/drafts/${draft.id}`}>
                    <Button size="sm">Abrir detalhe</Button>
                  </Link>
                </div>
              </CardContent>
            </Card>
          ))
        )}
      </div>
    </div>
  );
}
