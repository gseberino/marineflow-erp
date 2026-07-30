// Caixa de entrada financeira — onde o gestor decide o que o sistema propôs.
//
// O problema que esta tela resolve: passaram R$ 926 mil em saídas pela conta no último ano
// e existem 5 contas a pagar registradas. A despesa não foi lançada porque lançar 1.500
// linhas à mão é trabalho que ninguém faz. Aqui o sistema chega com tudo preenchido e o
// gestor só confirma — o esforço vira leitura, não digitação.
//
// Duas faixas, conforme a decisão do usuário: até R$ 500 aprova em bloco (é onde está o
// volume e o risco é baixo); acima disso, uma a uma, porque valor grande merece o olho.
import { useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Checkbox } from '@/components/ui/checkbox';
import { Skeleton } from '@/components/ui/skeleton';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';
import { useI18n } from '@/i18n';
import { supabase } from '@/integrations/supabase/client';
import {
  useFinanceReviewQueue, useGerarPropostas, useAprovarPropostas, useRecusarPropostas,
  LIMITE_LOTE, type PropostaFinanceira, type Correcao,
} from '@/hooks/use-finance-review';
import {
  Sparkles, Check, X, ChevronDown, ArrowLeftRight, TrendingDown, Info, RefreshCw,
} from 'lucide-react';

/** Categorias ativas do plano de contas, para corrigir a sugestão sem sair da tela. */
function useCategorias(tipo: 'payable' | 'receivable') {
  return useQuery({
    queryKey: ['financial-categories', tipo],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('financial_categories')
        .select('name, dre_group')
        .eq('type', tipo).eq('active', true)
        .order('sort_order');
      if (error) throw error;
      return (data ?? []) as { name: string; dre_group: string | null }[];
    },
    staleTime: 10 * 60_000,
  });
}

function corDaConfianca(c: number): string {
  if (c >= 85) return 'bg-success/10 text-success border-success/30';
  if (c >= 60) return 'bg-warning/10 text-warning border-warning/30';
  return 'bg-muted text-muted-foreground';
}

function rotuloDaConfianca(c: number): string {
  if (c >= 85) return 'Alta';
  if (c >= 60) return 'Média';
  return 'Baixa';
}

interface LinhaProps {
  p: PropostaFinanceira;
  categorias: { name: string }[];
  selecionada: boolean;
  onSelecionar: (marcada: boolean) => void;
  correcao: Correcao | undefined;
  onCorrigir: (c: Correcao) => void;
  onAprovar: () => void;
  onRecusar: () => void;
  ocupado: boolean;
  /** Em lote a seleção manda; individualmente cada linha tem seus botões. */
  modoLote: boolean;
}

function LinhaProposta({
  p, categorias, selecionada, onSelecionar, correcao, onCorrigir,
  onAprovar, onRecusar, ocupado, modoLote,
}: LinhaProps) {
  const { formatCurrency, formatDate } = useI18n();
  const [aberta, setAberta] = useState(false);

  const transferencia = p.kind === 'internal_transfer';
  const categoria = correcao?.category ?? p.suggested_category ?? '';

  return (
    <Card className="p-3">
      <div className="flex items-start gap-3">
        {modoLote && (
          <Checkbox
            checked={selecionada}
            onCheckedChange={(v) => onSelecionar(v === true)}
            className="mt-1 shrink-0"
            aria-label={`Selecionar ${p.title}`}
          />
        )}

        <div className="min-w-0 flex-1">
          {/* min-w-0 + truncate: histórico de banco é longo e sem isto empurra a linha
              para fora da tela. Nunca deve haver rolagem lateral. */}
          <div className="flex flex-wrap items-center gap-2">
            {transferencia
              ? <ArrowLeftRight className="h-4 w-4 shrink-0 text-primary" />
              : <TrendingDown className="h-4 w-4 shrink-0 text-destructive" />}
            <span className="truncate font-medium">{p.title}</span>
            <Badge variant="outline" className={`shrink-0 text-xs ${corDaConfianca(p.confidence)}`}>
              {rotuloDaConfianca(p.confidence)} · {p.confidence}%
            </Badge>
          </div>

          <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-muted-foreground">
            <span>{p.suggested_date ? formatDate(p.suggested_date) : '—'}</span>
            <span className="font-semibold text-foreground">
              {formatCurrency(Number(p.suggested_amount ?? 0))}
            </span>
            {transferencia
              ? <Badge variant="secondary" className="text-xs">Não entra no resultado</Badge>
              : <span className="truncate">{categoria || 'Sem categoria'}</span>}
          </div>

          <Collapsible open={aberta} onOpenChange={setAberta}>
            <CollapsibleTrigger asChild>
              <button type="button" className="mt-1 inline-flex items-center gap-1 text-xs text-primary hover:underline">
                <Info className="h-3 w-3" />
                Por que o sistema propôs isto
                <ChevronDown className={`h-3 w-3 transition-transform ${aberta ? 'rotate-180' : ''}`} />
              </button>
            </CollapsibleTrigger>
            <CollapsibleContent className="mt-2 space-y-2">
              <p className="rounded-md bg-muted/50 p-2 text-xs text-muted-foreground">
                {p.reasoning || 'Sem justificativa registrada.'}
              </p>

              {!transferencia && (
                <div className="max-w-sm">
                  <label className="mb-1 block text-xs font-medium">Categoria</label>
                  <Select value={categoria} onValueChange={(v) => onCorrigir({ ...correcao, category: v })}>
                    <SelectTrigger className="h-8 text-xs">
                      <SelectValue placeholder="Escolher categoria" />
                    </SelectTrigger>
                    <SelectContent>
                      {categorias.map((c) => (
                        <SelectItem key={c.name} value={c.name}>{c.name}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              )}
            </CollapsibleContent>
          </Collapsible>
        </div>

        {!modoLote && (
          <div className="flex shrink-0 gap-1">
            <Button size="sm" variant="outline" disabled={ocupado} onClick={onAprovar} title="Aprovar">
              <Check className="h-4 w-4" />
            </Button>
            <Button size="sm" variant="ghost" disabled={ocupado} onClick={onRecusar} title="Recusar">
              <X className="h-4 w-4" />
            </Button>
          </div>
        )}
      </div>
    </Card>
  );
}

export function FinanceReviewInbox() {
  const { formatCurrency } = useI18n();
  const { data: propostas = [], isLoading } = useFinanceReviewQueue();
  const { data: categorias = [] } = useCategorias('payable');

  const gerar = useGerarPropostas();
  const aprovar = useAprovarPropostas();
  const recusar = useRecusarPropostas();
  const ocupado = gerar.isPending || aprovar.isPending || recusar.isPending;

  const [selecionadas, setSelecionadas] = useState<Set<string>>(new Set());
  const [correcoes, setCorrecoes] = useState<Record<string, Correcao>>({});

  const { lote, individuais, totalValor } = useMemo(() => {
    const lote: PropostaFinanceira[] = [];
    const individuais: PropostaFinanceira[] = [];
    let totalValor = 0;
    for (const p of propostas) {
      totalValor += Number(p.suggested_amount ?? 0);
      // Transferência entre contas vai sempre para a revisão individual: confirmar que
      // dois lançamentos são o mesmo dinheiro é decisão de fato, não volume.
      if (p.kind !== 'internal_transfer' && Number(p.suggested_amount ?? 0) < LIMITE_LOTE) lote.push(p);
      else individuais.push(p);
    }
    return { lote, individuais, totalValor };
  }, [propostas]);

  const marcar = (id: string, marcada: boolean) => {
    setSelecionadas((s) => {
      const n = new Set(s);
      if (marcada) n.add(id); else n.delete(id);
      return n;
    });
  };

  const marcarTodasDoLote = (marcar: boolean) => {
    setSelecionadas(marcar ? new Set(lote.map((p) => p.id)) : new Set());
  };

  const corrigir = (id: string, c: Correcao) => setCorrecoes((m) => ({ ...m, [id]: c }));

  const aprovarSelecionadas = () => {
    const ids = [...selecionadas];
    if (ids.length === 0) return;
    const overrides: Record<string, Correcao> = {};
    for (const id of ids) if (correcoes[id]) overrides[id] = correcoes[id];
    aprovar.mutate({ ids, overrides }, { onSuccess: () => setSelecionadas(new Set()) });
  };

  const valorSelecionado = useMemo(
    () => lote.filter((p) => selecionadas.has(p.id)).reduce((s, p) => s + Number(p.suggested_amount ?? 0), 0),
    [lote, selecionadas],
  );

  if (isLoading) {
    return <div className="space-y-2">{[...Array(4)].map((_, i) => <Skeleton key={i} className="h-20 rounded-xl" />)}</div>;
  }

  return (
    <div className="space-y-4">
      <Card className="p-4">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div className="min-w-0">
            <h3 className="flex items-center gap-2 font-semibold">
              <Sparkles className="h-4 w-4 text-primary" />
              Caixa de entrada financeira
            </h3>
            <p className="mt-1 text-sm text-muted-foreground">
              O sistema lê o extrato e propõe o lançamento pronto. Aprovar cria o registro da
              despesa — <strong>nenhum pagamento é feito aqui</strong>.
            </p>
          </div>
          <div className="flex shrink-0 gap-2">
            <Button variant="outline" size="sm" disabled={ocupado} onClick={() => gerar.mutate(false)}>
              <RefreshCw className={`mr-2 h-4 w-4 ${gerar.isPending ? 'animate-spin' : ''}`} />
              Analisar extrato
            </Button>
          </div>
        </div>

        {propostas.length > 0 && (
          <div className="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-4">
            {[
              { rotulo: 'Propostas', valor: String(propostas.length) },
              { rotulo: 'Valor total', valor: formatCurrency(totalValor) },
              { rotulo: `Até ${formatCurrency(LIMITE_LOTE)}`, valor: String(lote.length) },
              { rotulo: 'Revisar uma a uma', valor: String(individuais.length) },
            ].map((k) => (
              <div key={k.rotulo} className="rounded-lg border p-2">
                <p className="truncate text-xs text-muted-foreground">{k.rotulo}</p>
                <p className="truncate text-lg font-semibold">{k.valor}</p>
              </div>
            ))}
          </div>
        )}
      </Card>

      {propostas.length === 0 && (
        <Card className="p-8 text-center">
          <p className="text-muted-foreground">
            Nenhuma proposta pendente. Use <strong>Analisar extrato</strong> para o sistema varrer
            as movimentações dos últimos 90 dias que ainda não viraram lançamento.
          </p>
        </Card>
      )}

      {lote.length > 0 && (
        <div className="space-y-2">
          <div className="flex flex-wrap items-center justify-between gap-2 rounded-lg border bg-muted/30 p-2">
            <div className="flex items-center gap-2">
              <Checkbox
                checked={selecionadas.size > 0 && selecionadas.size === lote.length}
                onCheckedChange={(v) => marcarTodasDoLote(v === true)}
                aria-label="Selecionar todas do lote"
              />
              <span className="text-sm font-medium">
                Aprovação em lote — até {formatCurrency(LIMITE_LOTE)} ({lote.length})
              </span>
            </div>
            <div className="flex items-center gap-2">
              {selecionadas.size > 0 && (
                <span className="text-xs text-muted-foreground">
                  {selecionadas.size} · {formatCurrency(valorSelecionado)}
                </span>
              )}
              <Button size="sm" disabled={ocupado || selecionadas.size === 0} onClick={aprovarSelecionadas}>
                <Check className="mr-2 h-4 w-4" />
                Aprovar selecionadas
              </Button>
            </div>
          </div>

          {lote.map((p) => (
            <LinhaProposta
              key={p.id} p={p} categorias={categorias} modoLote
              selecionada={selecionadas.has(p.id)}
              onSelecionar={(m) => marcar(p.id, m)}
              correcao={correcoes[p.id]}
              onCorrigir={(c) => corrigir(p.id, c)}
              onAprovar={() => aprovar.mutate({ ids: [p.id], overrides: correcoes[p.id] ? { [p.id]: correcoes[p.id] } : {} })}
              onRecusar={() => recusar.mutate({ ids: [p.id] })}
              ocupado={ocupado}
            />
          ))}
        </div>
      )}

      {individuais.length > 0 && (
        <div className="space-y-2">
          <div className="rounded-lg border bg-muted/30 p-2">
            <p className="text-sm font-medium">
              Revisar uma a uma — acima de {formatCurrency(LIMITE_LOTE)} e transferências ({individuais.length})
            </p>
          </div>
          {individuais.map((p) => (
            <LinhaProposta
              key={p.id} p={p} categorias={categorias} modoLote={false}
              selecionada={false} onSelecionar={() => {}}
              correcao={correcoes[p.id]}
              onCorrigir={(c) => corrigir(p.id, c)}
              onAprovar={() => aprovar.mutate({ ids: [p.id], overrides: correcoes[p.id] ? { [p.id]: correcoes[p.id] } : {} })}
              onRecusar={() => recusar.mutate({ ids: [p.id] })}
              ocupado={ocupado}
            />
          ))}
        </div>
      )}
    </div>
  );
}
