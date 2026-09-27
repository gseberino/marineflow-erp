import { useI18n } from '@/i18n';
import { useCashForecast, useDuplicatePayables, type ForecastWeek } from '@/hooks/use-financial';
import { StatusBadge } from '@/components/StatusBadge';
import { DataTable, type DataColumn } from '@/v2/components/DataTable';
import { AlertTriangle, TrendingDown, TrendingUp } from 'lucide-react';

type Semana = ForecastWeek & { saldoPrevisto: number | null };

/**
 * Programação de caixa: o que está comprometido nas próximas 8 semanas.
 *
 * Nada aqui movimenta dinheiro: é leitura do que já está programado (contas a receber e a
 * pagar em aberto, pelo vencimento) e, desde 27/09/2026, da fatura de cada cartão e dos gastos
 * que se repetem todo mês — a tela diz de onde vem cada um.
 *
 * Com `saldoInicial` (26/09/2026), a previsão parte do dinheiro que há HOJE — a soma dos saldos
 * que os bancos informam e do Caixa, a mesma das fichas de saldo — e diz o saldo previsto no
 * fim de cada semana. Antes o sistema não conhecia o saldo real da conta, e o painel mostrava
 * só entradas e saídas: projetar saldo a partir de um número desconhecido seria inventar. Sem
 * o saldo (fichas ainda carregando ou com erro), o painel volta a esse modo.
 */
export function CashForecastPanel({ saldoInicial = null }: { saldoInicial?: number | null } = {}) {
  const { formatCurrency } = useI18n();
  const { data: forecast, isLoading } = useCashForecast(8);
  const { data: duplicadas } = useDuplicatePayables();

  if (isLoading) {
    return <p className="py-4 text-sm text-muted-foreground">Calculando a programação...</p>;
  }
  if (!forecast || forecast.weeks.length === 0) {
    return <p className="py-4 text-sm text-muted-foreground">Nada programado para as próximas semanas.</p>;
  }

  const { weeks, totalEntradas, totalSaidas, semanasNegativas } = forecast;
  const extras = forecast.extras ?? { faturas: [], recorrentes: [], avisos: [] };
  const faturasNaPrevisao = extras.faturas.filter((f) => f.naPrevisao);
  const dataCurta = (d: string) => d.slice(8, 10) + '/' + d.slice(5, 7);
  const saldoPeriodo = totalEntradas - totalSaidas;
  const comSaldo = saldoInicial != null;
  const semanas: Semana[] = weeks.map((w) => ({
    ...w,
    saldoPrevisto: comSaldo ? Math.round((saldoInicial + w.acumulado) * 100) / 100 : null,
  }));
  const noVermelho = semanas.filter((w) => (w.saldoPrevisto ?? 0) < 0);
  const saldoNoFim = semanas[semanas.length - 1].saldoPrevisto;
  // Escala das barras: a maior movimentação da janela vira 100%.
  const maiorMovimento = Math.max(...weeks.map((w) => Math.max(w.entradas, w.saidas)), 1);

  const cartoes = comSaldo
    ? [
      { l: 'Saldo de hoje', v: formatCurrency(saldoInicial), c: saldoInicial < 0 ? 'text-destructive' : '' },
      { l: 'A receber (8 semanas)', v: formatCurrency(totalEntradas), c: 'text-success' },
      { l: 'Sai (8 semanas)', v: formatCurrency(totalSaidas), c: 'text-destructive' },
      { l: 'Saldo previsto no fim', v: formatCurrency(saldoNoFim ?? 0), c: (saldoNoFim ?? 0) < 0 ? 'text-destructive' : 'text-success' },
    ]
    : [
      { l: 'A receber (8 semanas)', v: formatCurrency(totalEntradas), c: 'text-success' },
      { l: 'Sai (8 semanas)', v: formatCurrency(totalSaidas), c: 'text-destructive' },
      { l: 'Resultado do período', v: formatCurrency(saldoPeriodo), c: saldoPeriodo >= 0 ? 'text-success' : 'text-destructive' },
      { l: 'Semanas no vermelho', v: String(semanasNegativas), c: semanasNegativas > 0 ? 'text-warning' : '' },
    ];

  const colunas: DataColumn<Semana>[] = [
    {
      key: 'semana', header: 'Semana', minWidth: 170, priority: 0,
      render: (w) => (
        <span className="block min-w-0">
          <span className="flex flex-wrap items-center gap-2">
            <span>{w.rotulo}</span>
            {w.contemAtrasados && (
              <StatusBadge className="bg-destructive/10 text-destructive">inclui vencidas</StatusBadge>
            )}
          </span>
          {/* Proporção visual das duas pontas, para bater o olho e ver a pressão. */}
          <span className="mt-1 flex max-w-[220px] items-center gap-1">
            <span className="h-1.5 rounded-full bg-success/70" style={{ width: `${(w.entradas / maiorMovimento) * 100}%` }} />
            <span className="h-1.5 rounded-full bg-destructive/70" style={{ width: `${(w.saidas / maiorMovimento) * 100}%` }} />
          </span>
        </span>
      ),
    },
    ...(comSaldo ? [{
      key: 'saldo', header: 'Saldo previsto', minWidth: 124, priority: 1, align: 'right' as const, detailLabel: 'Saldo previsto no fim da semana',
      render: (w: Semana) => (
        <span className={`font-semibold ${(w.saldoPrevisto ?? 0) < 0 ? 'text-destructive' : ''}`}>{formatCurrency(w.saldoPrevisto ?? 0)}</span>
      ),
    }] : []),
    {
      key: 'entra', header: 'Entra', minWidth: 112, priority: 2, align: 'right', detailLabel: 'Entra',
      render: (w) => <span className="text-success">{w.entradas > 0 ? formatCurrency(w.entradas) : '—'}</span>,
    },
    {
      key: 'sai', header: 'Sai', minWidth: 112, priority: 2, align: 'right', detailLabel: 'Sai',
      render: (w) => (
        <span className="block text-destructive">
          {w.saidas > 0 ? formatCurrency(w.saidas) : '—'}
          {/* De onde vem a saída, quando não é só conta lançada. */}
          {((w.saidasDaFatura ?? 0) > 0 || (w.saidasRecorrentes ?? 0) > 0) && (
            <span className="block text-[11px] font-normal text-muted-foreground">
              {[
                (w.saidasDaFatura ?? 0) > 0 ? `fatura ${formatCurrency(w.saidasDaFatura ?? 0)}` : null,
                (w.saidasRecorrentes ?? 0) > 0 ? `fixos ${formatCurrency(w.saidasRecorrentes ?? 0)}` : null,
              ].filter(Boolean).join(' · ')}
            </span>
          )}
        </span>
      ),
    },
    {
      key: 'resultado', header: 'Resultado', minWidth: 120, priority: comSaldo ? 3 : 1, align: 'right', detailLabel: 'Resultado da semana',
      render: (w) => (
        <span className={`inline-flex items-center gap-1 font-medium ${w.liquido < 0 ? 'text-destructive' : w.liquido > 0 ? 'text-success' : 'text-muted-foreground'}`}>
          {w.liquido < 0 ? <TrendingDown className="h-3 w-3" /> : w.liquido > 0 ? <TrendingUp className="h-3 w-3" /> : null}
          {w.liquido !== 0 ? formatCurrency(w.liquido) : '—'}
        </span>
      ),
    },
    ...(comSaldo ? [] : [{
      key: 'acumulado', header: 'Acumulado', minWidth: 120, priority: 4, align: 'right' as const, detailLabel: 'Acumulado',
      render: (w: Semana) => <span className={w.acumulado < 0 ? 'text-destructive' : 'text-muted-foreground'}>{formatCurrency(w.acumulado)}</span>,
    }]),
  ];

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-2 lg:grid-cols-4">
        {cartoes.map((k) => (
          <div key={k.l} className="min-w-0 rounded-lg border bg-card px-3 py-2">
            <p className="truncate text-[11px] uppercase tracking-wide text-muted-foreground">{k.l}</p>
            <p className={`truncate text-lg font-semibold tabular-nums ${k.c}`}>{k.v}</p>
          </div>
        ))}
      </div>

      {comSaldo && noVermelho.length > 0 ? (
        <div className="flex items-start gap-2 rounded-lg border border-destructive/40 bg-destructive/5 p-3 text-sm">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-destructive" />
          <span>
            O saldo previsto fica negativo em {noVermelho.length} das próximas 8 semanas — a primeira é{' '}
            <b>{noVermelho[0].rotulo.toLowerCase()}</b>. Vale antecipar cobranças ou renegociar vencimentos.
          </span>
        </div>
      ) : semanasNegativas > 0 && (
        <div className="flex items-start gap-2 rounded-lg border border-warning/40 bg-warning/5 p-3 text-sm">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-warning" />
          <span>
            Em {semanasNegativas} das próximas 8 semanas sai mais do que entra. Vale antecipar
            cobranças ou renegociar vencimentos nessas semanas.
          </span>
        </div>
      )}

      <DataTable<Semana>
        rows={semanas}
        rowKey={(w) => w.inicio}
        columns={colunas}
        density="compact"
        emptyMessage="Nada programado."
      />

      {(faturasNaPrevisao.length > 0 || extras.recorrentes.length > 0 || extras.avisos.length > 0) && (
        <div className="space-y-2 rounded-lg border bg-card p-3 text-sm">
          <p className="font-medium">Além das contas lançadas, a previsão soma:</p>
          {faturasNaPrevisao.length > 0 && (
            <ul className="space-y-1">
              {faturasNaPrevisao.map((f) => (
                <li key={`${f.conta}-${f.situacao}`} className="min-w-0">
                  <span className="font-medium">Fatura {f.conta}</span>{' '}
                  <span className="tabular-nums">{formatCurrency(f.valor)}</span>
                  <span className="text-muted-foreground">
                    {' — '}
                    {f.situacao === 'fechada'
                      ? `fatura fechada em ${dataCurta(f.fechamento)}, ${f.compras} compra(s), menos o que já foi pago`
                      : `${f.compras} compra(s) do ciclo aberto até hoje (fecha em ${dataCurta(f.fechamento)})`}
                    {f.vencida
                      ? `; venceu por volta de ${dataCurta(f.vencimento)} e não aparece pagamento — confira`
                      : `; vence por volta de ${dataCurta(f.vencimento)}`}
                  </span>
                </li>
              ))}
            </ul>
          )}
          {extras.recorrentes.length > 0 && (
            <p className="min-w-0">
              <span className="font-medium">Gastos que se repetem todo mês</span>
              <span className="text-muted-foreground">
                {' (média dos meses em que apareceram, espalhada pelos dias, menos o que já está lançado): '}
                {extras.recorrentes.map((g) => `${g.categoria} ${formatCurrency(g.mediaMensal)}/mês`).join('; ')}.
              </span>
            </p>
          )}
          {extras.avisos.map((a) => (
            <p key={a} className="flex items-start gap-2 text-warning">
              <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
              <span>{a}</span>
            </p>
          ))}
        </div>
      )}

      {(duplicadas?.length ?? 0) > 0 && (
        <div className="space-y-2 rounded-lg border border-warning/40 bg-warning/5 p-3">
          <p className="flex items-center gap-2 text-sm font-medium">
            <AlertTriangle className="h-4 w-4 text-warning" />
            Possível lançamento em duplicidade
          </p>
          {duplicadas!.map((d, i) => (
            <div key={i} className="text-sm">
              <span className="font-medium">{d.fornecedor}</span>
              <span className="text-muted-foreground"> — {d.contas.length} contas de {formatCurrency(d.valor)} no mesmo mês:</span>
              <ul className="mt-0.5 space-y-0.5 text-xs text-muted-foreground">
                {d.contas.map((c: any) => (
                  <li key={c.id}>• {c.description || 'Sem descrição'} · vence {String(c.due_date).split('-').reverse().join('/')}</li>
                ))}
              </ul>
            </div>
          ))}
          <p className="text-xs text-muted-foreground">
            Podem ser parcelas legítimas — confira antes de cancelar qualquer uma.
          </p>
        </div>
      )}
    </div>
  );
}
