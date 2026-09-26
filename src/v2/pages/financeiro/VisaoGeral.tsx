// Visão Geral do Financeiro: quanto dinheiro há hoje, o que entrou e saiu pelo extrato, e o
// que vence nos próximos 30 dias. Sem abas — é a porta de entrada.
import { useMemo, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import {
  Bar, CartesianGrid, ComposedChart, Line, ResponsiveContainer,
  Tooltip as RechartsTooltip, XAxis, YAxis,
} from 'recharts';
import { useI18n } from '@/i18n';
import { useReceivables, usePayables, useFinancialSummary, useCashFlow } from '@/hooks/use-financial';
import { useFluxoDeCaixa } from '@/hooks/use-fluxo-de-caixa';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { PaymentDialog } from '@/components/PaymentDialog';
import { SaldosDasContas } from '@/components/SaldosDasContas';
import { AjudaDoExtrato, FicouDeFora } from '@/components/FluxoDoExtrato';
import { KPIStat } from '@/v2/components/KPIStat';

type ContaCurta = {
  id: string;
  description: string;
  due_date: string;
  status?: string | null;
  balance_amount?: number | null;
  clients?: { name?: string } | null;
};

export function VisaoGeral() {
  const { t, formatCurrency, formatDate } = useI18n();
  const navigate = useNavigate();
  const { data: recData, error: recError } = useReceivables();
  const { data: payData, error: payError } = usePayables();
  const { data: summary, isLoading: loadingSummary, error: summaryError } = useFinancialSummary();
  const [cfMonths, setCfMonths] = useState(6);
  // O gráfico (formato { month, inflow, outflow, net }) e o que ficou à parte leem a MESMA
  // entrada de cache: uma consulta só ao extrato.
  const { data: cashFlow } = useCashFlow(cfMonths);
  const { data: fluxo } = useFluxoDeCaixa(cfMonths);
  const [paymentTarget, setPaymentTarget] = useState<{ receivable?: ContaCurta; payable?: ContaCurta } | null>(null);

  const receivables = useMemo(() => (recData ?? []) as unknown as ContaCurta[], [recData]);
  const payables = useMemo(() => (payData ?? []) as unknown as ContaCurta[], [payData]);

  const today = new Date();
  const in30 = new Date(today.getTime() + 30 * 86400000);
  const upcomingRec = receivables.filter((r) => r.status !== 'paid' && r.status !== 'cancelled' && new Date(r.due_date) <= in30).slice(0, 5);
  const upcomingPay = payables.filter((p) => p.status !== 'paid' && p.status !== 'cancelled' && new Date(p.due_date) <= in30).slice(0, 5);
  const periodBalance = (cashFlow ?? []).reduce((s: number, m: { net: number }) => s + m.net, 0);
  const erro = (summaryError || recError || payError) as Error | null;

  return (
    <div className="space-y-4">
      {/* Primeiro, quanto dinheiro há hoje — o que todo dono procura primeiro. */}
      <SaldosDasContas />
      {erro && (
        <div className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-destructive/40 bg-destructive/5 p-3 text-sm">
          <span className="text-destructive">Erro ao carregar os números do Financeiro: {erro.message || 'verifique sua conexão.'}</span>
          <Button size="sm" variant="outline" onClick={() => window.location.reload()}>Recarregar página</Button>
        </div>
      )}
      {loadingSummary ? (
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
          {[1, 2, 3, 4].map((i) => <Skeleton key={i} className="h-24 rounded-lg" />)}
        </div>
      ) : (
        <>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <KPIStat
              label={t.financial.totalReceivables}
              value={formatCurrency(summary?.total_receivable || 0)}
              hint={summary?.overdue_receivable ? `${formatCurrency(summary.overdue_receivable)} vencidos` : 'sem atrasos'}
              tone={summary?.overdue_receivable ? 'critical' : 'success'}
              onClick={() => navigate('/v2/receivables')}
            />
            <KPIStat
              label={t.financial.pendingPayables}
              value={formatCurrency(summary?.total_payable || 0)}
              hint={summary?.overdue_payable ? `${formatCurrency(summary.overdue_payable)} vencidos` : 'sem atrasos'}
              tone={summary?.overdue_payable ? 'critical' : 'success'}
              onClick={() => navigate('/v2/financial/payables')}
            />
            {/* Pelo EXTRATO: antes era a tabela de pagamentos registrados à mão (52 no sistema
                inteiro), e o mês parecia não ter gastado nada. */}
            <KPIStat
              label="Entrou no mês (extrato)"
              value={formatCurrency(summary?.entrou_no_mes || 0)}
              tone="success"
              hint="nas contas e no Caixa"
              ajuda={<AjudaDoExtrato rotulo="De onde vem o Entrou no mês" />}
            />
            <KPIStat
              label="Saiu no mês (extrato)"
              value={formatCurrency(summary?.saiu_no_mes || 0)}
              hint="cartão conta quando a fatura é paga"
              ajuda={<AjudaDoExtrato rotulo="De onde vem o Saiu no mês" />}
            />
          </div>

          <div className="overflow-hidden rounded-lg border bg-card p-4">
            <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
              <h3 className="flex items-center gap-1 text-sm font-bold">
                Fluxo de caixa pelo extrato
                <AjudaDoExtrato rotulo="Como o fluxo de caixa é calculado" />
              </h3>
              <div className="flex gap-1" role="group" aria-label="Período do gráfico">
                {[3, 6, 12].map((m) => (
                  <Button key={m} size="sm" variant={cfMonths === m ? 'secondary' : 'ghost'} aria-pressed={cfMonths === m} onClick={() => setCfMonths(m)}>
                    {m}m
                  </Button>
                ))}
              </div>
            </div>
            {cashFlow && cashFlow.length > 0 ? (
              <>
                <ResponsiveContainer width="100%" height={280}>
                  <ComposedChart data={cashFlow}>
                    <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" vertical={false} />
                    <XAxis dataKey="month" tick={{ fontSize: 12, fill: 'hsl(var(--muted-foreground))' }} axisLine={false} tickLine={false} />
                    <YAxis tick={{ fontSize: 11, fill: 'hsl(var(--muted-foreground))' }} tickFormatter={(v: number) => `${(v / 1000).toFixed(0)}k`} width={44} axisLine={false} tickLine={false} />
                    <RechartsTooltip formatter={(v: number) => formatCurrency(v)} cursor={{ fill: 'hsl(var(--muted))' }} />
                    <Bar dataKey="inflow" name="Entrou" fill="hsl(var(--success))" radius={[3, 3, 0, 0]} />
                    <Bar dataKey="outflow" name="Saiu" fill="hsl(var(--destructive))" radius={[3, 3, 0, 0]} />
                    <Line dataKey="net" name="Resultado" stroke="hsl(var(--primary))" strokeWidth={2} dot />
                  </ComposedChart>
                </ResponsiveContainer>
                <p className="mt-1 text-sm">
                  Entrou menos saiu no período:{' '}
                  <span className={`font-bold tabular-nums ${periodBalance >= 0 ? 'text-success' : 'text-destructive'}`}>{formatCurrency(periodBalance)}</span>
                </p>
                {fluxo && (
                  <FicouDeFora
                    transferencias={fluxo.total.transferencias}
                    creditoDoCartao={fluxo.total.creditoDoCartao}
                    className="mt-1 text-xs text-muted-foreground"
                  />
                )}
                <p className="mt-2 text-xs">
                  <Link to="/v2/reports/fluxo" className="font-medium text-accent underline-offset-2 hover:underline">
                    Mês a mês e as próximas 8 semanas, na Central de relatórios
                  </Link>
                </p>
              </>
            ) : (
              <p className="py-8 text-center text-sm text-muted-foreground">{t.common.noResults}</p>
            )}
          </div>

          <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
            <div className="rounded-lg border bg-card p-4">
              <h3 className="mb-3 text-sm font-bold">{t.financial.upcomingReceivables}</h3>
              {upcomingRec.length === 0 ? <p className="text-sm text-muted-foreground">{t.common.noResults}</p> : (
                <div className="space-y-2">
                  {upcomingRec.map((r) => (
                    <div key={r.id} className="flex items-center justify-between gap-2 border-b pb-2 text-sm last:border-0">
                      <span className="min-w-0 overflow-hidden">
                        <span className="block truncate font-medium">{r.clients?.name || r.description}</span>
                        <span className="block truncate text-xs text-muted-foreground">{formatDate(r.due_date)}</span>
                      </span>
                      <span className="flex shrink-0 items-center gap-2">
                        <span className="font-semibold tabular-nums">{formatCurrency(Number(r.balance_amount ?? 0))}</span>
                        <Button size="sm" variant="outline" onClick={() => setPaymentTarget({ receivable: r })}>{t.financial.registerPayment}</Button>
                      </span>
                    </div>
                  ))}
                </div>
              )}
            </div>
            <div className="rounded-lg border bg-card p-4">
              <h3 className="mb-3 text-sm font-bold">{t.financial.upcomingPayables}</h3>
              {upcomingPay.length === 0 ? <p className="text-sm text-muted-foreground">{t.common.noResults}</p> : (
                <div className="space-y-2">
                  {upcomingPay.map((p) => (
                    <div key={p.id} className="flex items-center justify-between gap-2 border-b pb-2 text-sm last:border-0">
                      <span className="min-w-0 overflow-hidden">
                        <span className="block truncate font-medium">{p.description}</span>
                        <span className="block truncate text-xs text-muted-foreground">{formatDate(p.due_date)}</span>
                      </span>
                      <span className="flex shrink-0 items-center gap-2">
                        <span className="font-semibold tabular-nums">{formatCurrency(Number(p.balance_amount ?? 0))}</span>
                        <Button size="sm" variant="outline" onClick={() => setPaymentTarget({ payable: p })}>{t.financial.registerPayment}</Button>
                      </span>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        </>
      )}

      {paymentTarget && (
        <PaymentDialog
          open={!!paymentTarget}
          onOpenChange={() => setPaymentTarget(null)}
          receivable={paymentTarget.receivable as never}
          payable={paymentTarget.payable as never}
        />
      )}
    </div>
  );
}
