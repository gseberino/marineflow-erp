import { useAgingReport } from '@/hooks/use-financial';
import { Skeleton } from '@/components/ui/skeleton';
import { AlertTriangle, CheckCircle2, Clock, TrendingUp } from 'lucide-react';

const fmt = (v: number) =>
  v.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });

const pct = (part: number, total: number) =>
  total === 0 ? '0%' : `${Math.round((part / total) * 100)}%`;

interface BucketProps {
  label: string;
  days: string;
  amount: number;
  total: number;
  colorClass: string;
  icon: React.ReactNode;
}

function BucketCard({ label, days, amount, total, colorClass, icon }: BucketProps) {
  return (
    <div className={`rounded-lg border p-4 space-y-1 ${colorClass}`}>
      <div className="flex items-center justify-between">
        <span className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">{label}</span>
        {icon}
      </div>
      <p className="text-lg font-bold">{fmt(amount)}</p>
      <p className="text-xs text-muted-foreground">{days} · {pct(amount, total)} do total</p>
    </div>
  );
}

export function AgingReportPanel() {
  const { data, isLoading } = useAgingReport();

  if (isLoading) {
    return (
      <div className="space-y-4">
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
          {[1, 2, 3, 4].map(i => <Skeleton key={i} className="h-24 rounded-lg" />)}
        </div>
        <Skeleton className="h-48 rounded-lg" />
      </div>
    );
  }

  if (!data || data.buckets.length === 0) {
    return (
      <div className="rounded-xl border bg-card p-12 text-center space-y-2">
        <CheckCircle2 className="h-10 w-10 mx-auto text-success" />
        <p className="font-medium">Nenhum recebível em aberto</p>
        <p className="text-sm text-muted-foreground">Todas as contas a receber estão quitadas.</p>
      </div>
    );
  }

  const { totals, buckets } = data;

  return (
    <div className="space-y-6">
      {/* Totais por faixa */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <BucketCard
          label="Corrente / até 30d"
          days="0–30 dias"
          amount={totals.current}
          total={totals.total}
          colorClass="border-border"
          icon={<Clock className="h-4 w-4 text-muted-foreground" />}
        />
        <BucketCard
          label="31–60 dias"
          days="31–60 dias em atraso"
          amount={totals.days_31_60}
          total={totals.total}
          colorClass="border-amber-200 bg-amber-50/40 dark:bg-amber-950/20"
          icon={<AlertTriangle className="h-4 w-4 text-amber-500" />}
        />
        <BucketCard
          label="61–90 dias"
          days="61–90 dias em atraso"
          amount={totals.days_61_90}
          total={totals.total}
          colorClass="border-orange-200 bg-orange-50/40 dark:bg-orange-950/20"
          icon={<AlertTriangle className="h-4 w-4 text-orange-500" />}
        />
        <BucketCard
          label="+90 dias"
          days="Mais de 90 dias em atraso"
          amount={totals.over_90}
          total={totals.total}
          colorClass="border-destructive/30 bg-destructive/5"
          icon={<TrendingUp className="h-4 w-4 text-destructive" />}
        />
      </div>

      <p className="text-xs text-muted-foreground text-right">
        Total em aberto: <span className="font-semibold">{fmt(totals.total)}</span>
      </p>

      {/* Tabela por cliente */}
      <div className="rounded-xl border bg-card shadow-sm overflow-x-auto">
        <table className="w-full text-sm min-w-[600px]">
          <thead>
            <tr className="border-b bg-muted/50">
              <th className="px-4 py-3 text-left font-medium text-muted-foreground">Cliente</th>
              <th className="px-4 py-3 text-right font-medium text-muted-foreground">Corrente</th>
              <th className="px-4 py-3 text-right font-medium text-amber-600">31–60d</th>
              <th className="px-4 py-3 text-right font-medium text-orange-600">61–90d</th>
              <th className="px-4 py-3 text-right font-medium text-destructive">+90d</th>
              <th className="px-4 py-3 text-right font-medium text-muted-foreground">Total</th>
            </tr>
          </thead>
          <tbody>
            {buckets.map(b => (
              <tr key={b.client_id} className="border-b last:border-0 hover:bg-muted/20">
                <td className="px-4 py-2.5 font-medium truncate max-w-[200px]">{b.client_name}</td>
                <td className="px-4 py-2.5 text-right tabular-nums">
                  {b.current > 0 ? fmt(b.current) : <span className="text-muted-foreground">—</span>}
                </td>
                <td className="px-4 py-2.5 text-right tabular-nums">
                  {b.days_31_60 > 0
                    ? <span className="text-amber-700 font-medium">{fmt(b.days_31_60)}</span>
                    : <span className="text-muted-foreground">—</span>}
                </td>
                <td className="px-4 py-2.5 text-right tabular-nums">
                  {b.days_61_90 > 0
                    ? <span className="text-orange-700 font-medium">{fmt(b.days_61_90)}</span>
                    : <span className="text-muted-foreground">—</span>}
                </td>
                <td className="px-4 py-2.5 text-right tabular-nums">
                  {b.over_90 > 0
                    ? <span className="text-destructive font-bold">{fmt(b.over_90)}</span>
                    : <span className="text-muted-foreground">—</span>}
                </td>
                <td className="px-4 py-2.5 text-right font-semibold tabular-nums">{fmt(b.total)}</td>
              </tr>
            ))}
          </tbody>
          <tfoot>
            <tr className="border-t bg-muted/30">
              <td className="px-4 py-2.5 font-semibold text-xs uppercase tracking-wide text-muted-foreground">Total</td>
              <td className="px-4 py-2.5 text-right font-semibold tabular-nums">{fmt(totals.current)}</td>
              <td className="px-4 py-2.5 text-right font-semibold tabular-nums text-amber-700">{fmt(totals.days_31_60)}</td>
              <td className="px-4 py-2.5 text-right font-semibold tabular-nums text-orange-700">{fmt(totals.days_61_90)}</td>
              <td className="px-4 py-2.5 text-right font-semibold tabular-nums text-destructive">{fmt(totals.over_90)}</td>
              <td className="px-4 py-2.5 text-right font-bold tabular-nums">{fmt(totals.total)}</td>
            </tr>
          </tfoot>
        </table>
      </div>
    </div>
  );
}
