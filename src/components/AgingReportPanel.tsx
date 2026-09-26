// Quem deve e a quem devo — o aging dos dois lados (26/09/2026).
//
// Era só "a receber", numa tabela de 700 px de largura mínima (rolagem lateral no celular).
// Agora tem a alternância A receber | A pagar, com as MESMAS faixas (src/lib/aging.ts), e a
// lista por pessoa usa a DataTable: o que não cabe na largura vai para a linha que abre.
import { useState } from 'react';
import { useAgingReport, useAgingAPagar, type AgingBucket, type AgingReportData } from '@/hooks/use-financial';
import { Skeleton } from '@/components/ui/skeleton';
import { Button } from '@/components/ui/button';
import { DataTable, type DataColumn } from '@/v2/components/DataTable';
import { AlertTriangle, CheckCircle2, Clock, TrendingUp, CalendarClock, Download } from 'lucide-react';
import { exportToCSV } from '@/lib/export';

const fmt = (v: number) =>
  v.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });

const pct = (part: number, total: number) =>
  total === 0 ? '0%' : `${Math.round((part / total) * 100)}%`;

export type LadoDoAging = 'receber' | 'pagar';

interface BucketCardProps {
  label: string;
  days: string;
  amount: number;
  total: number;
  colorClass: string;
  icon: React.ReactNode;
}

function BucketCard({ label, days, amount, total, colorClass, icon }: BucketCardProps) {
  return (
    <div className={`min-w-0 space-y-1 rounded-lg border p-4 ${colorClass}`}>
      <div className="flex items-center justify-between gap-1">
        <span className="truncate text-xs font-semibold uppercase tracking-wide text-muted-foreground">{label}</span>
        {icon}
      </div>
      <p className="truncate text-lg font-bold tabular-nums">{fmt(amount)}</p>
      <p className="text-xs text-muted-foreground">{days} · {pct(amount, total)} do total</p>
    </div>
  );
}

const TEXTOS: Record<LadoDoAging, { quem: string; vazio: string; vazioDetalhe: string; arquivo: string; atraso: string }> = {
  receber: {
    quem: 'Cliente', vazio: 'Nenhuma conta a receber em aberto', vazioDetalhe: 'Todas as contas a receber estão quitadas.',
    arquivo: 'aging_a_receber', atraso: 'de clientes com mais de 90 dias de atraso',
  },
  pagar: {
    quem: 'Fornecedor ou favorecido', vazio: 'Nenhuma conta a pagar em aberto', vazioDetalhe: 'Todas as contas a pagar estão quitadas.',
    arquivo: 'aging_a_pagar', atraso: 'em contas suas com mais de 90 dias de atraso',
  },
};

/** Um lado do aging, já lido. Sem hooks: cada lado tem a sua consulta (abaixo), e só a do lado aberto roda. */
function AgingConteudo({ lado, data, isLoading, error }: {
  lado: LadoDoAging;
  data: AgingReportData | undefined;
  isLoading: boolean;
  error: unknown;
}) {
  const textos = TEXTOS[lado];

  if (isLoading) {
    return (
      <div className="space-y-4">
        <div className="grid grid-cols-2 gap-3 md:grid-cols-5">
          {[1, 2, 3, 4, 5].map(i => <Skeleton key={i} className="h-24 rounded-lg" />)}
        </div>
        <Skeleton className="h-48 rounded-lg" />
      </div>
    );
  }

  if (error) {
    return <p className="text-sm text-destructive">Não consegui ler as contas em aberto: {String((error as Error).message ?? 'erro')}</p>;
  }

  if (!data || data.buckets.length === 0) {
    return (
      <div className="space-y-2 rounded-xl border bg-card p-12 text-center">
        <CheckCircle2 className="mx-auto h-10 w-10 text-success" />
        <p className="font-medium">{textos.vazio}</p>
        <p className="text-sm text-muted-foreground">{textos.vazioDetalhe}</p>
      </div>
    );
  }

  const { totals, buckets } = data;

  const handleExport = () => {
    exportToCSV(
      buckets.map(b => ({
        nome: b.client_name,
        a_vencer: b.future,
        atraso_1_30d: b.days_1_30,
        atraso_31_60d: b.days_31_60,
        atraso_61_90d: b.days_61_90,
        atraso_mais_90d: b.over_90,
        total: b.total,
      })),
      textos.arquivo,
      [
        { key: 'nome', label: textos.quem },
        { key: 'a_vencer', label: 'A Vencer', format: (v: unknown) => fmt(Number(v)) },
        { key: 'atraso_1_30d', label: '1–30d Atraso', format: (v: unknown) => fmt(Number(v)) },
        { key: 'atraso_31_60d', label: '31–60d Atraso', format: (v: unknown) => fmt(Number(v)) },
        { key: 'atraso_61_90d', label: '61–90d Atraso', format: (v: unknown) => fmt(Number(v)) },
        { key: 'atraso_mais_90d', label: '+90d Atraso', format: (v: unknown) => fmt(Number(v)) },
        { key: 'total', label: 'Total', format: (v: unknown) => fmt(Number(v)) },
      ],
    );
  };

  const valor = (v: number, cor: string) => (v > 0 ? <span className={cor}>{fmt(v)}</span> : <span className="text-muted-foreground">—</span>);
  const colunas: DataColumn<AgingBucket>[] = [
    { key: 'nome', header: textos.quem, minWidth: 180, priority: 0, render: (b) => <span className="truncate font-medium">{b.client_name}</span> },
    { key: 'total', header: 'Total', minWidth: 116, priority: 1, align: 'right', detailLabel: 'Total', render: (b) => <span className="font-semibold">{fmt(b.total)}</span> },
    { key: 'over_90', header: '+90d', minWidth: 110, priority: 2, align: 'right', detailLabel: 'Mais de 90 dias', render: (b) => valor(b.over_90, 'font-bold text-destructive') },
    { key: 'd61', header: '61–90d', minWidth: 110, priority: 3, align: 'right', detailLabel: '61 a 90 dias', render: (b) => valor(b.days_61_90, 'font-medium text-orange-700') },
    { key: 'd31', header: '31–60d', minWidth: 110, priority: 3, align: 'right', detailLabel: '31 a 60 dias', render: (b) => valor(b.days_31_60, 'font-medium text-amber-700') },
    { key: 'd1', header: '1–30d', minWidth: 110, priority: 3, align: 'right', detailLabel: '1 a 30 dias', render: (b) => valor(b.days_1_30, 'font-medium text-yellow-700') },
    { key: 'futuro', header: 'A vencer', minWidth: 110, priority: 2, align: 'right', detailLabel: 'A vencer', render: (b) => valor(b.future, 'text-blue-600') },
  ];

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-xs text-muted-foreground">
          Total em aberto: <span className="font-semibold text-foreground">{fmt(totals.total)}</span>
          {totals.over_90 > 0 && (
            <span className="ml-3 font-medium text-destructive">
              ⚠ {fmt(totals.over_90)} {textos.atraso}
            </span>
          )}
        </p>
        <Button variant="outline" size="sm" onClick={handleExport} className="gap-1.5 text-xs">
          <Download className="h-3.5 w-3.5" /> Exportar CSV
        </Button>
      </div>

      <div className="grid grid-cols-2 gap-3 md:grid-cols-5">
        <BucketCard label="A vencer" days="Vence no futuro" amount={totals.future} total={totals.total}
          colorClass="border-blue-200 bg-blue-50/40 dark:bg-blue-950/20" icon={<CalendarClock className="h-4 w-4 shrink-0 text-blue-500" />} />
        <BucketCard label="1–30 dias" days="1–30 dias em atraso" amount={totals.days_1_30} total={totals.total}
          colorClass="border-yellow-200 bg-yellow-50/40 dark:bg-yellow-950/20" icon={<Clock className="h-4 w-4 shrink-0 text-yellow-500" />} />
        <BucketCard label="31–60 dias" days="31–60 dias em atraso" amount={totals.days_31_60} total={totals.total}
          colorClass="border-amber-200 bg-amber-50/40 dark:bg-amber-950/20" icon={<AlertTriangle className="h-4 w-4 shrink-0 text-amber-500" />} />
        <BucketCard label="61–90 dias" days="61–90 dias em atraso" amount={totals.days_61_90} total={totals.total}
          colorClass="border-orange-200 bg-orange-50/40 dark:bg-orange-950/20" icon={<AlertTriangle className="h-4 w-4 shrink-0 text-orange-500" />} />
        <BucketCard label="+90 dias" days="Mais de 90 dias em atraso" amount={totals.over_90} total={totals.total}
          colorClass="border-destructive/30 bg-destructive/5" icon={<TrendingUp className="h-4 w-4 shrink-0 text-destructive" />} />
      </div>

      <DataTable<AgingBucket>
        rows={buckets}
        rowKey={(b) => b.client_id}
        columns={colunas}
        density="compact"
        emptyMessage="Nada em aberto."
      />
      <p className="text-xs text-muted-foreground">
        Total: a vencer {fmt(totals.future)} · 1–30d {fmt(totals.days_1_30)} · 31–60d {fmt(totals.days_31_60)} ·
        61–90d {fmt(totals.days_61_90)} · +90d {fmt(totals.over_90)}
      </p>
    </div>
  );
}

function AgingAReceber() {
  const { data, isLoading, error } = useAgingReport();
  return <AgingConteudo lado="receber" data={data} isLoading={isLoading} error={error} />;
}

function AgingAPagar() {
  const { data, isLoading, error } = useAgingAPagar();
  return <AgingConteudo lado="pagar" data={data} isLoading={isLoading} error={error} />;
}

/** Quem deve à empresa e a quem ela deve, por tempo de atraso, com a alternância dos dois lados. */
export function AgingReportPanel({ ladoInicial = 'receber' }: { ladoInicial?: LadoDoAging } = {}) {
  const [lado, setLado] = useState<LadoDoAging>(ladoInicial);
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap gap-1" role="group" aria-label="Lado do aging">
        {([['receber', 'A receber'], ['pagar', 'A pagar']] as const).map(([v, r]) => (
          <Button key={v} size="sm" variant={lado === v ? 'default' : 'outline'} className="h-8 text-xs" aria-pressed={lado === v} onClick={() => setLado(v)}>
            {r}
          </Button>
        ))}
      </div>
      {lado === 'receber' ? <AgingAReceber /> : <AgingAPagar />}
    </div>
  );
}
