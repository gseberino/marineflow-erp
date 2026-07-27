import { useI18n } from '@/i18n';
import { useCashForecast, useDuplicatePayables } from '@/hooks/use-financial';
import { StatusBadge } from '@/components/StatusBadge';
import { AlertTriangle, TrendingDown, TrendingUp } from 'lucide-react';

/**
 * Programação de pagamentos: o que está comprometido nas próximas semanas.
 *
 * O painel responde "o que vence e quando", não "quanto vou ter no banco" — o sistema não
 * conhece o saldo real da conta, e projetar saldo a partir de um número desconhecido seria
 * inventar. Nada aqui movimenta dinheiro: é leitura do que já está programado.
 */
export function CashForecastPanel() {
  const { formatCurrency } = useI18n();
  const { data: forecast, isLoading } = useCashForecast(8);
  const { data: duplicadas } = useDuplicatePayables();

  if (isLoading) {
    return <p className="text-sm text-muted-foreground py-4">Calculando a programação...</p>;
  }
  if (!forecast || forecast.weeks.length === 0) {
    return <p className="text-sm text-muted-foreground py-4">Nada programado para as próximas semanas.</p>;
  }

  const { weeks, totalEntradas, totalSaidas, semanasNegativas } = forecast;
  const saldoPeriodo = totalEntradas - totalSaidas;
  // Escala das barras: a maior movimentação da janela vira 100%.
  const maiorMovimento = Math.max(...weeks.map(w => Math.max(w.entradas, w.saidas)), 1);

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-2">
        {[
          { l: 'A receber (8 semanas)', v: formatCurrency(totalEntradas), c: 'text-success' },
          { l: 'A pagar (8 semanas)', v: formatCurrency(totalSaidas), c: 'text-destructive' },
          { l: 'Resultado do período', v: formatCurrency(saldoPeriodo), c: saldoPeriodo >= 0 ? 'text-success' : 'text-destructive' },
          { l: 'Semanas no vermelho', v: String(semanasNegativas), c: semanasNegativas > 0 ? 'text-warning' : '' },
        ].map(k => (
          <div key={k.l} className="rounded-lg border bg-card px-3 py-2">
            <p className="text-[11px] uppercase tracking-wide text-muted-foreground">{k.l}</p>
            <p className={`text-lg font-semibold tabular-nums ${k.c}`}>{k.v}</p>
          </div>
        ))}
      </div>

      {semanasNegativas > 0 && (
        <div className="rounded-lg border border-warning/40 bg-warning/5 p-3 text-sm flex items-start gap-2">
          <AlertTriangle className="h-4 w-4 text-warning shrink-0 mt-0.5" />
          <span>
            Em {semanasNegativas} das próximas 8 semanas sai mais do que entra. Vale antecipar
            cobranças ou renegociar vencimentos nessas semanas.
          </span>
        </div>
      )}

      <div className="rounded-lg border bg-card overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b bg-muted/40">
                <th className="text-left py-2 px-3 font-medium">Semana</th>
                <th className="text-right py-2 px-3 font-medium">Entra</th>
                <th className="text-right py-2 px-3 font-medium">Sai</th>
                <th className="text-right py-2 px-3 font-medium">Resultado</th>
                <th className="text-right py-2 px-3 font-medium hidden sm:table-cell">Acumulado</th>
              </tr>
            </thead>
            <tbody>
              {weeks.map(w => (
                <tr key={w.inicio} className="border-b last:border-0">
                  <td className="py-2 px-3">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span>{w.rotulo}</span>
                      {w.contemAtrasados && (
                        <StatusBadge className="bg-destructive/10 text-destructive">inclui vencidas</StatusBadge>
                      )}
                    </div>
                    {/* Proporção visual das duas pontas, para bater o olho e ver a pressão. */}
                    <div className="flex items-center gap-1 mt-1 max-w-[220px]">
                      <div className="h-1.5 rounded-full bg-success/70" style={{ width: `${(w.entradas / maiorMovimento) * 100}%` }} />
                      <div className="h-1.5 rounded-full bg-destructive/70" style={{ width: `${(w.saidas / maiorMovimento) * 100}%` }} />
                    </div>
                  </td>
                  <td className="py-2 px-3 text-right tabular-nums text-success">
                    {w.entradas > 0 ? formatCurrency(w.entradas) : '—'}
                  </td>
                  <td className="py-2 px-3 text-right tabular-nums text-destructive">
                    {w.saidas > 0 ? formatCurrency(w.saidas) : '—'}
                  </td>
                  <td className={`py-2 px-3 text-right tabular-nums font-medium ${w.liquido < 0 ? 'text-destructive' : w.liquido > 0 ? 'text-success' : 'text-muted-foreground'}`}>
                    <span className="inline-flex items-center gap-1">
                      {w.liquido < 0 ? <TrendingDown className="h-3 w-3" /> : w.liquido > 0 ? <TrendingUp className="h-3 w-3" /> : null}
                      {w.liquido !== 0 ? formatCurrency(w.liquido) : '—'}
                    </span>
                  </td>
                  <td className={`py-2 px-3 text-right tabular-nums hidden sm:table-cell ${w.acumulado < 0 ? 'text-destructive' : 'text-muted-foreground'}`}>
                    {formatCurrency(w.acumulado)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {(duplicadas?.length ?? 0) > 0 && (
        <div className="rounded-lg border border-warning/40 bg-warning/5 p-3 space-y-2">
          <p className="text-sm font-medium flex items-center gap-2">
            <AlertTriangle className="h-4 w-4 text-warning" />
            Possível lançamento em duplicidade
          </p>
          {duplicadas!.map((d, i) => (
            <div key={i} className="text-sm">
              <span className="font-medium">{d.fornecedor}</span>
              <span className="text-muted-foreground"> — {d.contas.length} contas de {formatCurrency(d.valor)} no mesmo mês:</span>
              <ul className="text-xs text-muted-foreground mt-0.5 space-y-0.5">
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
