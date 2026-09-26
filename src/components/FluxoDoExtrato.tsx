// Peças de tela do fluxo de caixa pelo extrato, usadas na Visão Geral e na Central de
// relatórios: o "?" que diz o que entra e o que fica de fora, a linha do que ficou à parte e
// o gráfico mês a mês. A regra dos números é de src/lib/fluxo-de-caixa.ts.
import {
  Bar, CartesianGrid, ComposedChart, Line, ResponsiveContainer,
  Tooltip as RechartsTooltip, XAxis, YAxis,
} from 'recharts';
import { useI18n } from '@/i18n';
import { Ajuda } from '@/components/Ajuda';
import { rotuloDoMes, type EntrouSaiu, type MesDoFluxo } from '@/lib/fluxo-de-caixa';

/** O "?" ao lado de Entrou/Saiu: de onde vem o número e o que não entra nele. */
export function AjudaDoExtrato({ rotulo = 'Como o extrato é somado' }: { rotulo?: string }) {
  return (
    <Ajuda rotulo={rotulo}>
      Soma do que entrou e saiu das contas do banco e do Caixa em dinheiro, pela data do extrato.
      <br />
      <b>Não entram:</b> transferência entre contas suas; dinheiro que o cartão de crédito pôs na
      conta (Pix no crédito — é dívida, não receita); compra no cartão de crédito, que conta quando a
      fatura é paga; linha repetida da importação manual de julho; lançamento estornado; linha ainda
      pendente no banco e linha com data no futuro.
    </Ajuda>
  );
}

const temValor = (s: EntrouSaiu) => s.entrou !== 0 || s.saiu !== 0;

/** O que ficou à parte (sem somar em Entrou/Saiu), dito por extenso. */
export function FicouDeFora({ transferencias, creditoDoCartao, className }: {
  transferencias: EntrouSaiu;
  creditoDoCartao: EntrouSaiu;
  className?: string;
}) {
  const { formatCurrency } = useI18n();
  const partes: string[] = [];
  if (temValor(transferencias)) {
    partes.push(`transferências entre contas suas (entrou ${formatCurrency(transferencias.entrou)}, saiu ${formatCurrency(transferencias.saiu)})`);
  }
  if (temValor(creditoDoCartao)) {
    partes.push(`crédito do cartão posto na conta, que é dívida (${formatCurrency(creditoDoCartao.entrou - creditoDoCartao.saiu)})`);
  }
  return (
    <p className={className ?? 'text-xs text-muted-foreground'}>
      {partes.length === 0
        ? 'Nada ficou à parte neste período: não houve transferência entre contas suas nem crédito do cartão na conta.'
        : `Ficaram à parte, sem somar em Entrou e Saiu: ${partes.join(' e ')}.`}
    </p>
  );
}

/** Barras de Entrou e Saiu e a linha do resultado, mês a mês. */
export function GraficoDoFluxo({ meses, altura = 260 }: { meses: MesDoFluxo[]; altura?: number }) {
  const { formatCurrency } = useI18n();
  const dados = meses.map((m) => ({ mes: rotuloDoMes(m.mes), entrou: m.entrou, saiu: m.saiu, resultado: m.liquido }));
  return (
    <ResponsiveContainer width="100%" height={altura}>
      <ComposedChart data={dados}>
        <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" vertical={false} />
        <XAxis dataKey="mes" tick={{ fontSize: 12, fill: 'hsl(var(--muted-foreground))' }} axisLine={false} tickLine={false} />
        <YAxis tick={{ fontSize: 11, fill: 'hsl(var(--muted-foreground))' }} tickFormatter={(v: number) => `${(v / 1000).toFixed(0)}k`} width={44} axisLine={false} tickLine={false} />
        <RechartsTooltip formatter={(v: number) => formatCurrency(v)} cursor={{ fill: 'hsl(var(--muted))' }} />
        <Bar dataKey="entrou" name="Entrou" fill="hsl(var(--success))" radius={[3, 3, 0, 0]} />
        <Bar dataKey="saiu" name="Saiu" fill="hsl(var(--destructive))" radius={[3, 3, 0, 0]} />
        <Line dataKey="resultado" name="Resultado" stroke="hsl(var(--primary))" strokeWidth={2} dot />
      </ComposedChart>
    </ResponsiveContainer>
  );
}
