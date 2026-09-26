// Central de relatórios › Para onde foi o dinheiro: despesas por categoria, mês a mês.
//
// Sem tabela larga (princípio nº 0 do dono: nada de rolagem lateral): cada categoria é um
// cartão com o total e uma barrinha por mês, que cabe no celular.
import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { useI18n } from '@/i18n';
import { useDespesasDosMeses } from '@/hooks/use-despesas-por-categoria';
import { ROTULO_DO_GRUPO } from '@/hooks/use-despesas';
import { montarDespesasPorCategoria } from '@/lib/despesas-por-categoria';
import { nomeDoMes, rotuloDoMes } from '@/lib/fluxo-de-caixa';
import { Skeleton } from '@/components/ui/skeleton';
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';
import { Ajuda } from '@/components/Ajuda';
import { cn } from '@/lib/utils';

/** Barrinhas de um valor por mês; a maior da escala vira 100%. */
function BarrasDosMeses({ meses, valores, escala, className }: {
  meses: string[]; valores: number[]; escala: number; className?: string;
}) {
  const { formatCurrency } = useI18n();
  return (
    <div className={cn('grid gap-1', className)} style={{ gridTemplateColumns: `repeat(${meses.length}, minmax(0, 1fr))` }}>
      {meses.map((m, i) => (
        <div key={m} className="flex min-w-0 flex-col items-center gap-0.5" title={`${nomeDoMes(m)}: ${formatCurrency(valores[i])}`}>
          <div className="flex h-10 w-full items-end rounded-sm bg-muted/60">
            <div
              className="w-full rounded-sm bg-primary"
              style={{ height: `${escala > 0 && valores[i] > 0 ? Math.max(4, (valores[i] / escala) * 100) : 0}%` }}
            />
          </div>
          <span className="text-[10px] leading-none text-muted-foreground">{rotuloDoMes(m).slice(0, 3)}</span>
        </div>
      ))}
    </div>
  );
}

export function ParaOndeFoi() {
  const { formatCurrency } = useI18n();
  const { data, isLoading, error } = useDespesasDosMeses(6);
  const [incluirFora, setIncluirFora] = useState(false);
  const r = useMemo(
    () => (data ? montarDespesasPorCategoria(data.linhas, data.grupoDe, data.meses, incluirFora) : null),
    [data, incluirFora],
  );

  if (isLoading) return <Skeleton className="h-64 w-full rounded-lg" />;
  if (error || !r) {
    return <p className="text-sm text-destructive">Não consegui ler as despesas: {String((error as Error)?.message ?? 'erro')}</p>;
  }

  const maiorDoMes = Math.max(...r.totalPorMes, 0);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="flex flex-wrap items-center gap-1 text-sm">
          Nos últimos 6 meses: <b className="tabular-nums">{formatCurrency(r.total)}</b> em {r.categorias.length} categoria(s)
          <Ajuda rotulo="Como é contado">
            Pela data do lançamento, como o DRE e a tela Despesas: tudo o que foi lançado como despesa (banco,
            cartão de crédito, Caixa e bolso de sócio), sem os cancelados. O que ainda está no Extrato esperando
            decisão não entra.
          </Ajuda>
        </p>
        <div className="flex items-center gap-2">
          <Switch id="incluir-fora-central" checked={incluirFora} onCheckedChange={setIncluirFora} />
          <Label htmlFor="incluir-fora-central" className="text-xs">Incluir o que fica fora do resultado</Label>
          <Ajuda rotulo="O que fica fora do resultado">
            Pagamento da fatura do cartão (cada compra já foi contada quando aconteceu), transferência entre
            contas suas, retirada, empréstimo e aplicação. Não são despesa: somá-los contaria o mesmo dinheiro
            duas vezes. Desligado, o total bate com o DRE.
          </Ajuda>
        </div>
      </div>

      <div className="rounded-lg border bg-card p-3">
        <p className="mb-2 text-xs font-medium text-muted-foreground">Total de cada mês</p>
        <BarrasDosMeses meses={r.meses} valores={r.totalPorMes} escala={maiorDoMes} />
        <ul className="mt-2 grid grid-cols-2 gap-x-3 gap-y-0.5 text-xs sm:grid-cols-3">
          {r.meses.map((m, i) => (
            <li key={m} className="flex min-w-0 justify-between gap-2">
              <span className="text-muted-foreground">{rotuloDoMes(m)}</span>
              <span className="tabular-nums">{formatCurrency(r.totalPorMes[i])}</span>
            </li>
          ))}
        </ul>
      </div>

      {r.categorias.length === 0 ? (
        <p className="text-sm text-muted-foreground">Nenhuma despesa lançada nestes meses.</p>
      ) : (
        <ul className="grid grid-cols-1 gap-2 lg:grid-cols-2">
          {r.categorias.map((c) => (
            <li key={c.categoria} className="min-w-0 rounded-lg border bg-card p-3">
              <div className="flex min-w-0 items-baseline justify-between gap-2">
                <span className="min-w-0 truncate font-medium">{c.categoria}</span>
                <span className="shrink-0 font-semibold tabular-nums">{formatCurrency(c.total)}</span>
              </div>
              <p className="mb-2 text-xs text-muted-foreground">
                {c.quantidade} lançamento(s) · {c.grupo ? ROTULO_DO_GRUPO[c.grupo] ?? c.grupo : 'categoria sem linha no DRE'}
                {r.total > 0 && ` · ${Math.round((c.total / r.total) * 100)}% do total`}
              </p>
              {/* Escala da própria categoria: a pergunta aqui é "gastei mais ou menos com isto?". */}
              <BarrasDosMeses meses={r.meses} valores={c.porMes} escala={Math.max(...c.porMes, 0)} />
            </li>
          ))}
        </ul>
      )}

      <p className="text-xs text-muted-foreground">
        Para ver cada lançamento e corrigir a categoria:{' '}
        <Link to="/v2/financial/despesas" className="underline underline-offset-2 hover:text-foreground">Financeiro › Despesas</Link>.
      </p>
    </div>
  );
}
