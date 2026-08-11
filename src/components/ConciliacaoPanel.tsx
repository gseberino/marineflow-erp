// Conciliação — a pergunta certa, feita do lado certo.
//
// A tela antiga (BankReconciliation) partia do EXTRATO: listava toda linha que o banco
// trouxe e ainda não tinha sido tratada, e chamava isso de conciliação. O gestor descreveu
// o problema melhor do que qualquer documento:
//
//   "Conciliação bancária eu faço com tudo aquilo que eu lancei no sistema e vou comparar
//    com o extrato. E não o inverso. Eu analiso tudo o que tem no extrato e todas as
//    transações aparecem ali, sendo que eu não lancei nenhuma no sistema."
//
// É a divisão que o mercado faz: QuickBooks separa "For Review" de "Reconcile"; NetSuite
// separa "Match Bank Data" de "Reconcile Account Statement". Triagem do extrato é uma
// tela — o Extrato. Conferir o que foi registrado é outra — esta.
//
// O QUE ESTA TELA ENCONTROU AO NASCER
// Nenhum dos 23 recebíveis tinha vínculo com o extrato, e 16 estavam marcados como PAGOS.
// O dinheiro entrou no banco, alguém deu baixa no sistema, e os dois lados nunca se
// encontraram — que é o outro lado dos 87 créditos (R$ 628 mil) parados no Extrato, e a
// razão de eles faltarem no DRE.
import { useMemo, useState } from 'react';
import { Card } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { useI18n } from '@/i18n';
import {
  useLancamentosSemExtrato, useLancamentosConciliados, useExtratoLivre,
  useConciliarLancamento, useDesconciliarLancamento,
  type LancamentoParaConciliar, type LadoDoLancamento, type LinhaDoExtratoLivre,
} from '@/hooks/use-conciliacao';
import { Link2, Link2Off, Search, AlertTriangle, CheckCircle2, ArrowRight } from 'lucide-react';

type Aba = 'sem_extrato' | 'conciliados';

/** Quão perto o valor do extrato está do lançamento — vira a ordem dos candidatos. */
function distancia(lancamento: number, extrato: number): number {
  return Math.abs(Math.abs(lancamento) - Math.abs(extrato));
}

/** Dias entre o vencimento e a data do extrato. Sem data, não pontua. */
function diasDeDistancia(due: string | null, extrato: string): number {
  if (!due) return 999;
  const ms = Math.abs(new Date(extrato).getTime() - new Date(due).getTime());
  return Math.round(ms / 86_400_000);
}

export interface ConciliacaoPanelProps {
  /**
   * Aba controlada de fora. Quando a tela dona guarda o estado na URL (é o caso de
   * `/v2/financial/conciliacao`), o painel deixa de ter opinião própria e obedece — sem isso,
   * recarregar a página com `?aba=casadas` voltaria para "Sem par" e o link compartilhado
   * apontaria para o lugar errado.
   *
   * Omitido, o painel volta a gerenciar a aba sozinho (é como a tela legada o usa).
   */
  aba?: Aba;
  onAbaChange?: (aba: Aba) => void;
  /** Esconde a barra de abas quando quem desenha as abas é a tela de fora. */
  ocultarAbas?: boolean;
}

export function ConciliacaoPanel({ aba: abaControlada, onAbaChange, ocultarAbas }: ConciliacaoPanelProps = {}) {
  const { formatCurrency, formatDate } = useI18n();
  const [abaInterna, setAbaInterna] = useState<Aba>('sem_extrato');
  const aba = abaControlada ?? abaInterna;
  const setAba = (v: Aba) => { setAbaInterna(v); onAbaChange?.(v); };
  const [ladoFiltro, setLadoFiltro] = useState<LadoDoLancamento | 'todos'>('todos');
  const [busca, setBusca] = useState('');
  const [abertoId, setAbertoId] = useState<string | null>(null);

  const semExtrato = useLancamentosSemExtrato(ladoFiltro === 'todos' ? undefined : ladoFiltro);
  const conciliados = useLancamentosConciliados();
  const conciliar = useConciliarLancamento();
  const desconciliar = useDesconciliarLancamento();

  const lista = aba === 'sem_extrato' ? semExtrato : conciliados;

  const filtrada = useMemo(() => {
    const termo = busca.trim().toLowerCase();
    let base = lista.data ?? [];
    if (aba === 'conciliados' && ladoFiltro !== 'todos') base = base.filter(l => l.lado === ladoFiltro);
    if (!termo) return base;
    return base.filter(l =>
      (l.description ?? '').toLowerCase().includes(termo) ||
      (l.contraparte ?? '').toLowerCase().includes(termo) ||
      String(l.amount).includes(termo));
  }, [lista.data, busca, aba, ladoFiltro]);

  const comDiferenca = useMemo(
    () => (conciliados.data ?? []).filter(l => l.diferenca != null && Number(l.diferenca) !== 0),
    [conciliados.data]);

  // Erro precisa aparecer. Uma lista vazia por falha de consulta parece "nada a fazer", e
  // essa confusão já custou caro aqui antes (PGRST201 com a fila inteira invisível).
  if (lista.error) {
    return (
      <Card className="p-6 border-destructive/40">
        <div className="flex items-start gap-3">
          <AlertTriangle className="h-5 w-5 text-destructive shrink-0 mt-0.5" />
          <div className="min-w-0">
            <h3 className="font-semibold">Não deu para carregar a conciliação</h3>
            <p className="text-sm text-muted-foreground mt-1 break-words">{lista.error.message}</p>
          </div>
        </div>
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      <div>
        <h2 className="text-lg font-semibold">Conciliação</h2>
        <p className="text-sm text-muted-foreground mt-0.5">
          O que você lançou no sistema, conferido contra o extrato. Para tratar o que o banco
          trouxe e ainda não virou lançamento, use o <strong>Extrato</strong>.
        </p>
      </div>

      {comDiferenca.length > 0 && (
        <Card className="p-3 border-amber-500/40 bg-amber-500/5">
          <div className="flex items-center gap-2 text-sm">
            <AlertTriangle className="h-4 w-4 text-amber-600 shrink-0" />
            <span className="min-w-0">
              <strong>{comDiferenca.length}</strong>{' '}
              {comDiferenca.length === 1 ? 'lançamento conciliado tem' : 'lançamentos conciliados têm'}{' '}
              valor diferente do extrato.
            </span>
          </div>
        </Card>
      )}

      <div className="flex flex-wrap items-center gap-2">
        {!ocultarAbas && (
          <div className="flex rounded-lg border p-0.5">
            {([
              { k: 'sem_extrato' as Aba, r: 'Sem par no extrato', n: semExtrato.data?.length },
              { k: 'conciliados' as Aba, r: 'Conciliados', n: conciliados.data?.length },
            ]).map(t => (
              <button
                key={t.k}
                onClick={() => { setAba(t.k); setAbertoId(null); }}
                className={`px-3 py-1.5 text-sm rounded-md transition-colors ${
                  aba === t.k ? 'bg-primary text-primary-foreground' : 'hover:bg-muted'}`}
              >
                {t.r}{t.n != null && ` (${t.n})`}
              </button>
            ))}
          </div>
        )}

        <div className="flex rounded-lg border p-0.5">
          {([
            { k: 'todos' as const, r: 'Tudo' },
            { k: 'payable' as const, r: 'A pagar' },
            { k: 'receivable' as const, r: 'A receber' },
          ]).map(t => (
            <button
              key={t.k}
              onClick={() => setLadoFiltro(t.k)}
              className={`px-3 py-1.5 text-sm rounded-md transition-colors ${
                ladoFiltro === t.k ? 'bg-secondary' : 'hover:bg-muted'}`}
            >
              {t.r}
            </button>
          ))}
        </div>

        <div className="relative flex-1 min-w-[180px]">
          <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <Input
            value={busca}
            onChange={e => setBusca(e.target.value)}
            placeholder="Buscar por descrição, contraparte ou valor"
            className="pl-8"
          />
        </div>
      </div>

      {lista.isLoading ? (
        <div className="space-y-2">
          {[0, 1, 2, 3].map(i => <Skeleton key={i} className="h-16 w-full" />)}
        </div>
      ) : filtrada.length === 0 ? (
        <Card className="p-8 text-center">
          <CheckCircle2 className="h-8 w-8 text-muted-foreground/50 mx-auto mb-2" />
          <p className="text-sm text-muted-foreground">
            {busca
              ? 'Nada encontrado com esse termo.'
              : aba === 'sem_extrato'
                ? 'Todo lançamento tem par no extrato.'
                : 'Nenhum lançamento conciliado ainda.'}
          </p>
        </Card>
      ) : (
        <div className="space-y-2">
          {filtrada.map(l => (
            <LinhaDoLancamento
              key={`${l.lado}-${l.id}`}
              lancamento={l}
              aberto={abertoId === `${l.lado}-${l.id}`}
              onAlternar={() => setAbertoId(a => a === `${l.lado}-${l.id}` ? null : `${l.lado}-${l.id}`)}
              onConciliar={bt => conciliar.mutate(
                { lado: l.lado, id: l.id, bankTransactionId: bt },
                { onSuccess: () => setAbertoId(null) })}
              onDesconciliar={() => l.bank_transaction_id && desconciliar.mutate({
                lado: l.lado, id: l.id, bankTransactionId: l.bank_transaction_id })}
              ocupado={conciliar.isPending || desconciliar.isPending}
              formatCurrency={formatCurrency}
              formatDate={formatDate}
            />
          ))}
        </div>
      )}
    </div>
  );
}

function LinhaDoLancamento({
  lancamento: l, aberto, onAlternar, onConciliar, onDesconciliar, ocupado,
  formatCurrency, formatDate,
}: {
  lancamento: LancamentoParaConciliar;
  aberto: boolean;
  onAlternar: () => void;
  onConciliar: (bankTransactionId: string) => void;
  onDesconciliar: () => void;
  ocupado: boolean;
  formatCurrency: (n: number) => string;
  formatDate: (d: string) => string;
}) {
  const ehPagar = l.lado === 'payable';
  const temDiferenca = l.diferenca != null && Number(l.diferenca) !== 0;

  return (
    <Card className="overflow-hidden">
      {/* min-w-0 nos filhos flex: sem isso o texto longo empurra a linha e nasce barra de
          rolagem lateral, que é justamente o que não pode acontecer aqui. */}
      <button
        onClick={onAlternar}
        className="w-full text-left p-3 hover:bg-muted/40 transition-colors flex items-center gap-3"
      >
        <Badge variant="outline" className={`shrink-0 ${ehPagar ? 'text-destructive' : 'text-success'}`}>
          {ehPagar ? 'A pagar' : 'A receber'}
        </Badge>

        <div className="min-w-0 flex-1">
          <p className="font-medium truncate">{l.contraparte || l.description || 'Sem descrição'}</p>
          <p className="text-xs text-muted-foreground truncate">
            {l.contraparte && l.description ? `${l.description} · ` : ''}
            {l.due_date ? `vence ${formatDate(l.due_date)}` : 'sem vencimento'}
            {l.categoria ? ` · ${l.categoria}` : ''}
          </p>
        </div>

        {l.situacao === 'conciliado' && (
          <div className="hidden sm:block min-w-0 text-right">
            <p className="text-xs text-muted-foreground truncate">
              {l.extrato_data ? formatDate(l.extrato_data) : ''} no extrato
            </p>
            {temDiferenca && (
              <p className="text-xs text-amber-600 tabular-nums">
                difere {formatCurrency(Math.abs(Number(l.diferenca)))}
              </p>
            )}
          </div>
        )}

        <span className={`font-semibold tabular-nums shrink-0 ${ehPagar ? 'text-destructive' : 'text-success'}`}>
          {formatCurrency(Number(l.amount))}
        </span>
      </button>

      {aberto && (
        <div className="border-t p-3 bg-muted/20">
          {l.situacao === 'conciliado' ? (
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div className="min-w-0 text-sm">
                <p className="text-muted-foreground">Casado com a linha do extrato:</p>
                <p className="truncate">
                  {l.extrato_data ? formatDate(l.extrato_data) : '—'} ·{' '}
                  {l.extrato_descricao || 'Sem descrição'} ·{' '}
                  <span className="tabular-nums">{formatCurrency(Number(l.extrato_valor ?? 0))}</span>
                </p>
              </div>
              <Button variant="outline" size="sm" onClick={onDesconciliar} disabled={ocupado}>
                <Link2Off className="h-4 w-4 mr-1.5" />
                Desfazer vínculo
              </Button>
            </div>
          ) : (
            <CandidatosDoExtrato
              lancamento={l}
              onEscolher={onConciliar}
              ocupado={ocupado}
              formatCurrency={formatCurrency}
              formatDate={formatDate}
            />
          )}
        </div>
      )}
    </Card>
  );
}

/**
 * Candidatos do extrato para um lançamento.
 *
 * A ordem é por proximidade de VALOR primeiro e DATA depois, porque é assim que uma pessoa
 * procura. Só entram linhas do sinal certo — casar uma saída com uma entrada é um erro
 * silencioso, já que o valor bate.
 */
function CandidatosDoExtrato({
  lancamento: l, onEscolher, ocupado, formatCurrency, formatDate,
}: {
  lancamento: LancamentoParaConciliar;
  onEscolher: (id: string) => void;
  ocupado: boolean;
  formatCurrency: (n: number) => string;
  formatDate: (d: string) => string;
}) {
  const livres = useExtratoLivre(l.lado);

  const ordenados = useMemo(() => {
    const linhas: LinhaDoExtratoLivre[] = livres.data ?? [];
    return [...linhas]
      .map(t => ({
        t,
        dv: distancia(Number(l.amount), Number(t.amount)),
        dd: diasDeDistancia(l.due_date, t.transaction_date),
      }))
      .sort((a, b) => (a.dv - b.dv) || (a.dd - b.dd))
      .slice(0, 12);
  }, [livres.data, l.amount, l.due_date]);

  if (livres.isLoading) return <Skeleton className="h-20 w-full" />;

  if (livres.error) {
    return (
      <p className="text-sm text-destructive break-words">
        Não deu para buscar as linhas do extrato: {livres.error.message}
      </p>
    );
  }

  if (ordenados.length === 0) {
    return (
      <p className="text-sm text-muted-foreground">
        Nenhuma linha de {l.lado === 'payable' ? 'saída' : 'entrada'} livre no extrato. Se o
        dinheiro passou pelo banco, ele pode já ter virado outro lançamento.
      </p>
    );
  }

  return (
    <div className="space-y-1.5">
      <p className="text-xs text-muted-foreground">
        Linhas do extrato mais próximas — valor primeiro, depois data:
      </p>
      {ordenados.map(({ t, dv, dd }) => {
        const exato = dv < 0.005;
        return (
          <div
            key={t.id}
            className="flex items-center gap-2 rounded-md border bg-background p-2 text-sm"
          >
            <div className="min-w-0 flex-1">
              <p className="truncate">
                {t.counterparty_name || t.description || 'Sem descrição'}
              </p>
              <p className="text-xs text-muted-foreground truncate">
                {formatDate(t.transaction_date)}
                {t.e_cartao ? ' · cartão' : ''}
                {dd < 999 ? ` · ${dd} ${dd === 1 ? 'dia' : 'dias'} do vencimento` : ''}
              </p>
            </div>

            <span className="tabular-nums shrink-0">{formatCurrency(Number(t.amount))}</span>

            {exato ? (
              <Badge className="shrink-0 bg-success/15 text-success hover:bg-success/15">
                valor exato
              </Badge>
            ) : (
              <span className="text-xs text-muted-foreground tabular-nums shrink-0">
                +{formatCurrency(dv)}
              </span>
            )}

            <Button
              size="sm"
              variant={exato ? 'default' : 'outline'}
              onClick={() => onEscolher(t.id)}
              disabled={ocupado}
              className="shrink-0"
            >
              <Link2 className="h-4 w-4 mr-1" />
              Casar
              <ArrowRight className="h-3 w-3 ml-1" />
            </Button>
          </div>
        );
      })}
    </div>
  );
}
