// Despesas: o que saiu, em que categoria entrou e quem classificou (26/09/2026).
//
// Três visões do mesmo período: "Por categoria" (quanto foi para cada lugar), "Todas as saídas"
// (cada uma, com de onde saiu e quem decidiu) e "Para conferir" (o que merece um olhar: Outras
// despesas, sem quem recebeu, lançado sozinho). Corrigir abre o mesmo "Corrigir" das outras
// telas — trilha, mês fechado e valor do banco travado continuam valendo.
import { useMemo, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';
import { useI18n } from '@/i18n';
import {
  useDespesas, totaisPorCategoria, ROTULO_DO_GRUPO, ROTULO_QUEM_CLASSIFICOU, type Despesa,
} from '@/hooks/use-despesas';
import { CorrigirLancamentoDialog } from '@/components/CorrigirLancamentoDialog';
import { Ajuda } from '@/components/Ajuda';
import { Pencil, X } from 'lucide-react';
import { cn } from '@/lib/utils';

type Periodo = 'mes' | 'mes_passado' | 'tres_meses' | 'ano';
const PERIODOS: Array<[Periodo, string]> = [
  ['mes', 'Este mês'], ['mes_passado', 'Mês passado'], ['tres_meses', 'Últimos 3 meses'], ['ano', 'Este ano'],
];

/** Intervalo do período, em datas de Brasília. */
export function intervaloDoPeriodo(p: Periodo, agora = new Date()): [string, string] {
  const br = new Date(agora.getTime() - 3 * 3600_000);
  const a = br.getUTCFullYear();
  const m = br.getUTCMonth();
  const iso = (d: Date) => d.toISOString().slice(0, 10);
  const dia = (ano: number, mes: number, d: number) => new Date(Date.UTC(ano, mes, d));
  if (p === 'mes') return [iso(dia(a, m, 1)), iso(dia(a, m + 1, 0))];
  if (p === 'mes_passado') return [iso(dia(a, m - 1, 1)), iso(dia(a, m, 0))];
  if (p === 'tres_meses') return [iso(dia(a, m - 2, 1)), iso(dia(a, m + 1, 0))];
  return [`${a}-01-01`, `${a}-12-31`];
}

type Visao = 'categoria' | 'todas' | 'conferir';

function LinhaDaDespesa({ d, onCorrigir }: { d: Despesa; onCorrigir: (d: Despesa) => void }) {
  const { formatCurrency, formatDate } = useI18n();
  return (
    <li className="flex min-w-0 items-start gap-2 p-2.5">
      <span className="min-w-0 flex-1">
        <span className="flex min-w-0 items-baseline gap-2">
          <span className="shrink-0 text-xs text-muted-foreground tabular-nums">{formatDate(d.data)}</span>
          <span className="truncate font-medium">{d.quem}</span>
        </span>
        <span className="block truncate text-xs text-muted-foreground">
          <b className="font-medium text-foreground/80">{d.categoria}</b> · de {d.deOnde} · {ROTULO_QUEM_CLASSIFICOU[d.quemClassificou]}
          {d.os ? ` · ${d.os}` : ''}
          {d.status !== 'paid' ? ' · em aberto' : ''}
        </span>
        {d.descricao && d.descricao !== d.quem && <span className="block truncate text-xs text-muted-foreground">{d.descricao}</span>}
      </span>
      <span className="shrink-0 text-right">
        <span className="block font-semibold tabular-nums">{formatCurrency(d.valor)}</span>
        <Button size="sm" variant="ghost" className="mt-0.5 h-7 gap-1 px-2 text-xs" onClick={() => onCorrigir(d)} aria-label={`Corrigir ${d.quem}`}>
          <Pencil className="h-3 w-3" /> Corrigir
        </Button>
      </span>
    </li>
  );
}

function ListaDeDespesas({ despesas, onCorrigir }: { despesas: Despesa[]; onCorrigir: (d: Despesa) => void }) {
  const [limite, setLimite] = useState(100);
  if (despesas.length === 0) return <p className="p-3 text-sm text-muted-foreground">Nada neste recorte.</p>;
  return (
    <>
      <ul className="divide-y rounded-md border text-sm">
        {despesas.slice(0, limite).map((d) => <LinhaDaDespesa key={d.id} d={d} onCorrigir={onCorrigir} />)}
      </ul>
      {despesas.length > limite && (
        <Button variant="ghost" size="sm" className="mt-1" onClick={() => setLimite((n) => n + 200)}>
          Mostrar mais ({despesas.length - limite} restantes)
        </Button>
      )}
    </>
  );
}

export function DespesasPanel() {
  const { formatCurrency } = useI18n();
  const [periodo, setPeriodo] = useState<Periodo>('mes');
  const [de, ate] = intervaloDoPeriodo(periodo);
  const { data = [], isLoading, error } = useDespesas(de, ate);
  const [incluirFora, setIncluirFora] = useState(false);
  const [visao, setVisao] = useState<Visao>('categoria');
  const [categoria, setCategoria] = useState<string | null>(null);
  const [busca, setBusca] = useState('');
  const [corrigindo, setCorrigindo] = useState<Despesa | null>(null);

  // Por padrão fica de fora o que não é despesa do resultado (fatura do cartão — a compra já
  // foi contada —, empréstimo, aplicação, transferência entre contas): assim o total bate com o DRE.
  const doResultado = useMemo(() => data.filter((d) => incluirFora || d.grupo !== 'nao_operacional'), [data, incluirFora]);
  const total = doResultado.reduce((s, d) => s + d.valor, 0);
  const totais = useMemo(() => totaisPorCategoria(doResultado), [doResultado]);
  const maior = totais[0]?.valor ?? 0;
  const filtradas = useMemo(() => {
    const b = busca.trim().toLowerCase();
    return doResultado.filter((d) => (!categoria || d.categoria === categoria)
      && (!b || `${d.quem} ${d.descricao} ${d.categoria} ${d.deOnde}`.toLowerCase().includes(b)));
  }, [doResultado, categoria, busca]);
  const paraConferir = useMemo(() => ([
    ['Em "Outras despesas"', 'A categoria genérica esconde para onde foi o dinheiro. Corrija para o DRE dizer a verdade.', doResultado.filter((d) => d.categoria === 'Outras despesas' || d.categoria === 'Sem categoria')],
    ['Sem quem recebeu', 'O banco não informou o nome ("DEBITO DE CARTAO", "TRANSF ENVIADA PIX"). Diga quem foi, se lembrar.', doResultado.filter((d) => d.semNome)],
    ['Lançados sozinhos', 'O que o sistema lançou sem clique — por uma regra sua ou por confiança alta.', doResultado.filter((d) => d.quemClassificou === 'regra' || d.quemClassificou === 'confianca')],
  ] as Array<[string, string, Despesa[]]>), [doResultado]);

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <div className="flex flex-wrap gap-1" role="group" aria-label="Período">
          {PERIODOS.map(([p, r]) => (
            <Button key={p} size="sm" variant={periodo === p ? 'default' : 'outline'} className="h-8 text-xs" aria-pressed={periodo === p} onClick={() => setPeriodo(p)}>{r}</Button>
          ))}
        </div>
        <div className="flex items-center gap-2 sm:ml-auto">
          <Switch id="incluir-fora" checked={incluirFora} onCheckedChange={setIncluirFora} />
          <Label htmlFor="incluir-fora" className="text-xs">Incluir o que fica fora do resultado</Label>
          <Ajuda rotulo="O que fica fora do resultado">
            Pagamento da fatura do cartão (cada compra já foi contada quando aconteceu), empréstimo,
            aplicação e transferência entre contas suas. Não são despesa: somá-los contaria o mesmo
            dinheiro duas vezes. Desligado, o total bate com o DRE.
          </Ajuda>
        </div>
      </div>

      {isLoading ? <Skeleton className="h-40 w-full" /> : error ? (
        <p className="text-sm text-destructive">Não consegui ler as despesas: {String((error as Error).message)}</p>
      ) : (
        <>
          <p className="flex flex-wrap items-center gap-1 text-sm">
            Saiu no período: <b className="tabular-nums">{formatCurrency(total)}</b> em {doResultado.length} despesa(s)
            <Ajuda rotulo="Como é contado">
              Pela data do lançamento (como o DRE), de todas as origens: banco, cartão de crédito, Caixa e
              bolso de sócio. O que você ainda vai pagar aparece como "em aberto".
            </Ajuda>
          </p>

          <div className="flex flex-wrap gap-1" role="tablist" aria-label="Visão das despesas">
            {([['categoria', 'Por categoria'], ['todas', 'Todas as saídas'], ['conferir', 'Para conferir']] as const).map(([v, r]) => (
              <Button key={v} role="tab" aria-selected={visao === v} size="sm" variant={visao === v ? 'default' : 'outline'} className="h-8 text-xs" onClick={() => setVisao(v)}>{r}</Button>
            ))}
          </div>

          {visao === 'categoria' && (
            totais.length === 0 ? <p className="text-sm text-muted-foreground">Nenhuma despesa no período.</p> : (
              <ul className="space-y-1.5">
                {totais.map((t) => (
                  <li key={t.categoria}>
                    <button type="button" onClick={() => { setCategoria(t.categoria); setVisao('todas'); }}
                      className="w-full rounded-md border bg-card p-2.5 text-left hover:bg-muted/50">
                      <span className="flex min-w-0 items-baseline justify-between gap-2">
                        <span className="min-w-0 truncate font-medium">{t.categoria}</span>
                        <span className="shrink-0 font-semibold tabular-nums">{formatCurrency(t.valor)}</span>
                      </span>
                      <span className="mt-1 block h-1.5 overflow-hidden rounded bg-muted">
                        <span className={cn('block h-full rounded', t.grupo === 'nao_operacional' ? 'bg-muted-foreground/40' : 'bg-primary')}
                          style={{ width: `${maior > 0 ? Math.max(2, (t.valor / maior) * 100) : 0}%` }} />
                      </span>
                      <span className="mt-1 block text-xs text-muted-foreground">
                        {t.quantidade} saída(s) · {t.grupo ? ROTULO_DO_GRUPO[t.grupo] ?? t.grupo : 'categoria sem linha no DRE'}
                      </span>
                    </button>
                  </li>
                ))}
              </ul>
            )
          )}

          {visao === 'todas' && (
            <div className="space-y-2">
              <div className="flex flex-wrap items-center gap-2">
                <Input value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Buscar por quem, descrição ou conta" className="h-9 w-full sm:w-72" aria-label="Buscar despesas" />
                {categoria && (
                  <Button size="sm" variant="secondary" className="h-8 gap-1 text-xs" onClick={() => setCategoria(null)}>
                    {categoria} <X className="h-3 w-3" aria-label="Tirar o filtro de categoria" />
                  </Button>
                )}
                <span className="text-xs text-muted-foreground">
                  {filtradas.length} · {formatCurrency(filtradas.reduce((s, d) => s + d.valor, 0))}
                </span>
              </div>
              <ListaDeDespesas despesas={filtradas} onCorrigir={setCorrigindo} />
            </div>
          )}

          {visao === 'conferir' && (
            <div className="space-y-3">
              {paraConferir.map(([titulo, porque, lista]) => (
                <Card key={titulo} className="p-3">
                  <p className="text-sm font-medium">{titulo}: {lista.length} · {formatCurrency(lista.reduce((s, d) => s + d.valor, 0))}</p>
                  <p className="mb-2 text-xs text-muted-foreground">{porque}</p>
                  {lista.length > 0 && <ListaDeDespesas despesas={lista} onCorrigir={setCorrigindo} />}
                </Card>
              ))}
              <p className="text-xs text-muted-foreground">
                As compras no débito que ainda estão no Extrato esperando você dizer a loja ficam em Extrato › Para revisar.
              </p>
            </div>
          )}
        </>
      )}

      {corrigindo && (
        <CorrigirLancamentoDialog tipo="payable" lancamento={corrigindo.bruto as never} onFechar={() => setCorrigindo(null)} />
      )}
    </div>
  );
}
