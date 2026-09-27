// Central de relatórios › Fluxo de caixa: o que passou pelas contas mês a mês (extrato) e a
// previsão das próximas 8 semanas partindo do saldo de hoje.
import { useState } from 'react';
import { ChevronDown } from 'lucide-react';
import { useI18n } from '@/i18n';
import { useFluxoDeCaixa } from '@/hooks/use-fluxo-de-caixa';
import { useSaldoDasContas } from '@/hooks/use-saldo-das-contas';
import { ROTULO_DO_DESTINO, nomeDoMes, rotuloDoMes, type DestinoDeFora, type MesDoFluxo } from '@/lib/fluxo-de-caixa';
import { Skeleton } from '@/components/ui/skeleton';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';
import { CashForecastPanel } from '@/components/CashForecastPanel';
import { AjudaDoExtrato, FicouDeFora, GraficoDoFluxo } from '@/components/FluxoDoExtrato';
import { DataTable, type DataColumn } from '@/v2/components/DataTable';
import { cn } from '@/lib/utils';

function MesAMes() {
  const { formatCurrency } = useI18n();
  const { data, isLoading, error } = useFluxoDeCaixa(12);
  const [verFora, setVerFora] = useState(false);

  if (isLoading) return <Skeleton className="h-72 w-full rounded-lg" />;
  if (error || !data) {
    return <p className="text-sm text-destructive">Não consegui ler o extrato: {String((error as Error)?.message ?? 'erro')}</p>;
  }

  const linhas = [...data.meses].reverse(); // o mês mais recente primeiro, na lista
  const colunas: DataColumn<MesDoFluxo>[] = [
    { key: 'mes', header: 'Mês', minWidth: 96, priority: 0, render: (m) => <span className="font-medium" title={nomeDoMes(m.mes)}>{rotuloDoMes(m.mes)}</span> },
    {
      key: 'resultado', header: 'Resultado', minWidth: 116, priority: 1, align: 'right', detailLabel: 'Entrou menos saiu',
      render: (m) => <span className={cn('font-semibold', m.liquido < 0 ? 'text-destructive' : 'text-success')}>{formatCurrency(m.liquido)}</span>,
    },
    { key: 'entrou', header: 'Entrou', minWidth: 116, priority: 2, align: 'right', detailLabel: 'Entrou', render: (m) => formatCurrency(m.entrou) },
    { key: 'saiu', header: 'Saiu', minWidth: 116, priority: 2, align: 'right', detailLabel: 'Saiu', render: (m) => formatCurrency(m.saiu) },
    {
      key: 'transf', header: 'Transferências', minWidth: 150, priority: 3, align: 'right', detailLabel: 'À parte — transferências entre contas suas',
      render: (m) => (m.transferencias.entrou || m.transferencias.saiu)
        ? <span className="text-muted-foreground">+{formatCurrency(m.transferencias.entrou)} / −{formatCurrency(m.transferencias.saiu)}</span>
        : <span className="text-muted-foreground">—</span>,
    },
    {
      key: 'cartao', header: 'Crédito do cartão', minWidth: 140, priority: 4, align: 'right', detailLabel: 'À parte — crédito do cartão na conta',
      render: (m) => (m.creditoDoCartao.entrou || m.creditoDoCartao.saiu)
        ? <span className="text-muted-foreground">{formatCurrency(m.creditoDoCartao.entrou - m.creditoDoCartao.saiu)}</span>
        : <span className="text-muted-foreground">—</span>,
    },
  ];
  const fora = Object.entries(data.deFora) as Array<[DestinoDeFora, { quantidade: number; valor: number }]>;

  return (
    <div className="space-y-3">
      <div className="overflow-hidden rounded-lg border bg-card p-4">
        <h3 className="mb-3 flex items-center gap-1 text-sm font-bold">
          Mês a mês, pelo extrato — últimos 12 meses
          <AjudaDoExtrato rotulo="Como o fluxo de caixa é calculado" />
        </h3>
        <GraficoDoFluxo meses={data.meses} />
        <p className="mt-2 text-sm">
          Nos 12 meses: entrou <b className="tabular-nums">{formatCurrency(data.total.entrou)}</b>, saiu{' '}
          <b className="tabular-nums">{formatCurrency(data.total.saiu)}</b> — resultado{' '}
          <b className={cn('tabular-nums', data.total.liquido < 0 ? 'text-destructive' : 'text-success')}>{formatCurrency(data.total.liquido)}</b>.
        </p>
        <FicouDeFora transferencias={data.total.transferencias} creditoDoCartao={data.total.creditoDoCartao} className="mt-1 text-xs text-muted-foreground" />
        {fora.length > 0 && (
          <Collapsible open={verFora} onOpenChange={setVerFora} className="mt-2">
            <CollapsibleTrigger className="inline-flex items-center gap-1 text-xs font-medium text-accent underline-offset-2 hover:underline">
              O que não entrou em conta nenhuma
              <ChevronDown className={cn('h-3.5 w-3.5 transition-transform', verFora && 'rotate-180')} aria-hidden />
            </CollapsibleTrigger>
            <CollapsibleContent>
              <ul className="mt-1 space-y-0.5 text-xs text-muted-foreground">
                {fora.map(([destino, v]) => (
                  <li key={destino}>
                    {ROTULO_DO_DESTINO[destino]}: {v.quantidade} linha(s), {formatCurrency(v.valor)}
                  </li>
                ))}
              </ul>
            </CollapsibleContent>
          </Collapsible>
        )}
      </div>
      <DataTable<MesDoFluxo>
        rows={linhas}
        rowKey={(m) => m.mes}
        columns={colunas}
        density="compact"
        emptyMessage="Sem movimento no extrato."
      />
    </div>
  );
}

function ProximasSemanas() {
  const { formatCurrency } = useI18n();
  const { data: saldos, isLoading, error } = useSaldoDasContas();
  const semSaldo = (saldos?.contas ?? []).filter((c) => c.saldo == null);

  return (
    <div className="space-y-3">
      <h3 className="text-sm font-bold">Próximas 8 semanas</h3>
      {isLoading ? (
        <Skeleton className="h-10 w-full" />
      ) : error || !saldos ? (
        <p className="text-sm text-amber-600">
          Não consegui ler o saldo de hoje; a previsão abaixo mostra só o que entra e sai, sem o saldo de partida.
        </p>
      ) : (
        <p className="text-sm">
          Parte do saldo de hoje: <b className="tabular-nums">{formatCurrency(saldos.disponivel)}</b>{' '}
          <span className="text-muted-foreground">
            — a soma do que cada banco informou na última busca e do Caixa em dinheiro (as mesmas fichas da Visão Geral).
          </span>
          {semSaldo.length > 0 && (
            <span className="block text-xs text-amber-600">
              Sem saldo informado ainda, fica de fora do ponto de partida: {semSaldo.map((c) => c.nome).join(', ')}.
            </span>
          )}
        </p>
      )}
      <CashForecastPanel saldoInicial={saldos && !error ? saldos.disponivel : null} />
      <div className="rounded-lg border bg-muted/40 p-3 text-xs text-muted-foreground">
        <p className="font-medium text-foreground">O que a previsão não inclui</p>
        <p className="mt-1">
          Ela soma as contas a receber e a pagar em aberto, pelo vencimento; a fatura de cada cartão com as
          compras já feitas, no dia provável de pagamento; e os gastos que se repetem todo mês, pela média. Não
          entram: compras no cartão que ainda vão ser feitas; gastos do dia a dia que variam de um mês para outro
          (combustível, Pix avulso, peças); vendas que ainda não viraram conta a receber; e o que está no Extrato
          esperando decisão. Contas vencidas e não pagas entram na primeira semana.
        </p>
      </div>
    </div>
  );
}

export function FluxoDeCaixaSecao() {
  return (
    <div className="space-y-6">
      <MesAMes />
      <ProximasSemanas />
    </div>
  );
}
