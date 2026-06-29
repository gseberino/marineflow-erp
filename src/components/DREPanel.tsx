import { useState, useMemo } from 'react';
import { Button } from '@/components/ui/button';
import { Download } from 'lucide-react';
import { exportToCSV } from '@/lib/export';
import { useReceivables, usePayables, usePayments } from '@/hooks/use-financial';
import { useCostCenters } from '@/hooks/use-cost-centers';
import { useI18n } from '@/i18n';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Skeleton } from '@/components/ui/skeleton';
import { ResponsiveContainer, BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip as RechartsTooltip, Legend } from 'recharts';

export function DREPanel() {
  const { formatCurrency } = useI18n();
  const { data: receivables, isLoading: loadRec } = useReceivables();
  const { data: payables, isLoading: loadPay } = usePayables();
  const { data: costCenters, isLoading: loadCc } = useCostCenters();
  const [year, setYear] = useState<number>(new Date().getFullYear());

  const isLoading = loadRec || loadPay || loadCc;

  const dreData = useMemo(() => {
    if (!receivables || !payables || !costCenters) return null;

    const months = Array.from({ length: 12 }, (_, i) => i + 1);
    
    // Group all confirmed payments by month and cost center
    // Currently, our payments don't carry the cost_center, but their parent receivables/payables do.
    // For DRE, it's common to use the competence method (accrual basis - due_date or issue_date) 
    // or cash basis (payment_date). We'll use accrual basis (due_date) for a classic DRE, 
    // or just assume a simple structure. Let's use due_date.

    const structure = costCenters.filter(cc => !cc.parent_id);

    const resultByMonth = months.map(m => {
      const monthData: any = { month: m, label: new Date(year, m - 1, 1).toLocaleDateString('pt-BR', { month: 'short' }) };
      
      const recThisMonth = receivables.filter(r => new Date(r.due_date).getFullYear() === year && new Date(r.due_date).getMonth() + 1 === m);
      const payThisMonth = payables.filter(p => new Date(p.due_date).getFullYear() === year && new Date(p.due_date).getMonth() + 1 === m);

      // Simple DRE aggregation
      let grossRevenue = 0;
      recThisMonth.forEach(r => grossRevenue += Number(r.amount));
      
      monthData['Receitas Operacionais'] = grossRevenue;

      structure.forEach(cc => {
        if (cc.type === 'expense') {
          let sum = 0;
          payThisMonth.forEach(p => {
            // match by cost_center_id or fallback to name matching (for mock)
            if ((p as any).cost_center_id === cc.id || p.expense_category === cc.name) {
              sum += Number(p.amount);
            }
          });
          monthData[cc.name] = sum;
        }
      });

      // Calculate totals
      const deductions = monthData['Deduções e Impostos'] || 0;
      const netRevenue = grossRevenue - deductions;
      const variableCosts = monthData['Custos Variáveis (CPV/CSV)'] || 0;
      const grossProfit = netRevenue - variableCosts;
      
      let fixedCosts = 0;
      ['Despesas Operacionais Fixas', 'Despesas com Pessoal', 'Despesas Administrativas'].forEach(cat => {
        fixedCosts += monthData[cat] || 0;
      });

      const operatingProfit = grossProfit - fixedCosts;
      const financialResult = -(monthData['Resultado Financeiro (Taxas/Juros)'] || 0);
      const netIncome = operatingProfit + financialResult;

      monthData.netRevenue = netRevenue;
      monthData.grossProfit = grossProfit;
      monthData.operatingProfit = operatingProfit;
      monthData.netIncome = netIncome;

      return monthData;
    });

    return resultByMonth;
  }, [receivables, payables, costCenters, year]);

  if (isLoading || !dreData) return <Skeleton className="h-[400px] w-full" />;

  const yearTotal = dreData.reduce((acc, curr) => {
    Object.keys(curr).forEach(k => {
      if (typeof curr[k] === 'number' && k !== 'month') {
        acc[k] = (acc[k] || 0) + curr[k];
      }
    });
    return acc;
  }, {} as any);

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center gap-3 flex-wrap">
        <h3 className="text-lg font-bold">Demonstrativo de Resultados (DRE)</h3>
        <div className="flex items-center gap-2">
          <Button
            variant="outline" size="sm"
            className="gap-1.5 text-xs"
            onClick={() => {
              const rows = [
                { conta: 'Receitas Operacionais', ...Object.fromEntries(dreData.map(d => [d.label, d['Receitas Operacionais'] || 0])), total: yearTotal['Receitas Operacionais'] || 0 },
                { conta: '(-) Deduções e Impostos', ...Object.fromEntries(dreData.map(d => [d.label, d['Deduções e Impostos'] || 0])), total: yearTotal['Deduções e Impostos'] || 0 },
                { conta: '= Receita Líquida', ...Object.fromEntries(dreData.map(d => [d.label, d.netRevenue || 0])), total: yearTotal.netRevenue || 0 },
                { conta: '(-) Custos Variáveis', ...Object.fromEntries(dreData.map(d => [d.label, d['Custos Variáveis (CPV/CSV)'] || 0])), total: yearTotal['Custos Variáveis (CPV/CSV)'] || 0 },
                { conta: '= Lucro Bruto', ...Object.fromEntries(dreData.map(d => [d.label, d.grossProfit || 0])), total: yearTotal.grossProfit || 0 },
                { conta: '(-) Desp. Operacionais', ...Object.fromEntries(dreData.map(d => [d.label, d['Despesas Operacionais Fixas'] || 0])), total: yearTotal['Despesas Operacionais Fixas'] || 0 },
                { conta: '= Lucro Operacional', ...Object.fromEntries(dreData.map(d => [d.label, d.operatingProfit || 0])), total: yearTotal.operatingProfit || 0 },
                { conta: '(-) Resultado Financeiro', ...Object.fromEntries(dreData.map(d => [d.label, d['Resultado Financeiro'] || 0])), total: yearTotal['Resultado Financeiro'] || 0 },
                { conta: '= Lucro Líquido', ...Object.fromEntries(dreData.map(d => [d.label, d.netIncome || 0])), total: yearTotal.netIncome || 0 },
              ];
              const cols = [
                { key: 'conta', label: 'Conta' },
                ...dreData.map(d => ({ key: d.label, label: d.label, format: (v: any) => Number(v || 0).toFixed(2).replace('.', ',') })),
                { key: 'total', label: `Total ${year}`, format: (v: any) => Number(v || 0).toFixed(2).replace('.', ',') },
              ];
              exportToCSV(rows, `dre_${year}`, cols);
            }}
          >
            <Download className="h-3.5 w-3.5" /> Exportar CSV
          </Button>
          <Select value={String(year)} onValueChange={v => setYear(Number(v))}>
            <SelectTrigger className="w-[120px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {[year - 1, year, year + 1].map(y => (
                <SelectItem key={y} value={String(y)}>{y}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-sm text-muted-foreground">Receita Líquida Anual</CardTitle></CardHeader>
          <CardContent><p className="text-2xl font-bold">{formatCurrency(yearTotal.netRevenue || 0)}</p></CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-sm text-muted-foreground">Lucro Operacional Anual</CardTitle></CardHeader>
          <CardContent><p className={`text-2xl font-bold ${(yearTotal.operatingProfit || 0) >= 0 ? 'text-success' : 'text-destructive'}`}>{formatCurrency(yearTotal.operatingProfit || 0)}</p></CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-sm text-muted-foreground">Lucro Líquido Anual</CardTitle></CardHeader>
          <CardContent><p className={`text-2xl font-bold ${(yearTotal.netIncome || 0) >= 0 ? 'text-success' : 'text-destructive'}`}>{formatCurrency(yearTotal.netIncome || 0)}</p></CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-sm">Evolução do Resultado Líquido</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="h-[300px] w-full">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={dreData}>
                <CartesianGrid strokeDasharray="3 3" vertical={false} />
                <XAxis dataKey="label" fontSize={12} tickLine={false} />
                <YAxis fontSize={12} tickLine={false} tickFormatter={(v) => `R$${(v/1000).toFixed(0)}k`} />
                <RechartsTooltip formatter={(val: number) => formatCurrency(val)} />
                <Legend />
                <Bar dataKey="Receitas Operacionais" name="Receita Bruta" fill="#3b82f6" radius={[4, 4, 0, 0]} />
                <Bar dataKey="netIncome" name="Lucro Líquido" fill="#10b981" radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </CardContent>
      </Card>

      <Card className="overflow-hidden">
        <div className="overflow-x-auto scrollbar-thin">
          <table className="w-full text-sm text-left min-w-[1200px]">
            <thead className="bg-muted/50 text-muted-foreground">
              <tr>
                <th className="px-4 py-3 font-medium">Conta</th>
                <th className="px-4 py-3 font-medium text-right">Total {year}</th>
                {dreData.map(d => (
                  <th key={d.month} className="px-4 py-3 font-medium text-right min-w-[100px]">{d.label}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y">
              {/* DRE Structure Rows */}
              <tr className="hover:bg-muted/30">
                <td className="px-4 py-3 font-semibold">(=) Receita Bruta</td>
                <td className="px-4 py-3 text-right font-semibold">{formatCurrency(yearTotal['Receitas Operacionais'] || 0)}</td>
                {dreData.map(d => <td key={d.month} className="px-4 py-3 text-right">{formatCurrency(d['Receitas Operacionais'] || 0)}</td>)}
              </tr>
              <tr className="hover:bg-muted/30">
                <td className="px-4 py-3 pl-8 text-muted-foreground">(-) Deduções e Impostos</td>
                <td className="px-4 py-3 text-right">{formatCurrency(yearTotal['Deduções e Impostos'] || 0)}</td>
                {dreData.map(d => <td key={d.month} className="px-4 py-3 text-right text-muted-foreground">{formatCurrency(d['Deduções e Impostos'] || 0)}</td>)}
              </tr>
              <tr className="hover:bg-muted/30 bg-primary/5">
                <td className="px-4 py-3 font-bold text-primary">(=) Receita Líquida</td>
                <td className="px-4 py-3 text-right font-bold text-primary">{formatCurrency(yearTotal.netRevenue || 0)}</td>
                {dreData.map(d => <td key={d.month} className="px-4 py-3 text-right font-medium text-primary">{formatCurrency(d.netRevenue || 0)}</td>)}
              </tr>
              <tr className="hover:bg-muted/30">
                <td className="px-4 py-3 pl-8 text-muted-foreground">(-) Custos Variáveis (CPV/CSV)</td>
                <td className="px-4 py-3 text-right">{formatCurrency(yearTotal['Custos Variáveis (CPV/CSV)'] || 0)}</td>
                {dreData.map(d => <td key={d.month} className="px-4 py-3 text-right text-muted-foreground">{formatCurrency(d['Custos Variáveis (CPV/CSV)'] || 0)}</td>)}
              </tr>
              <tr className="hover:bg-muted/30 bg-primary/5">
                <td className="px-4 py-3 font-bold">(=) Lucro Bruto</td>
                <td className="px-4 py-3 text-right font-bold">{formatCurrency(yearTotal.grossProfit || 0)}</td>
                {dreData.map(d => <td key={d.month} className="px-4 py-3 text-right font-medium">{formatCurrency(d.grossProfit || 0)}</td>)}
              </tr>
              <tr className="hover:bg-muted/30">
                <td className="px-4 py-3 pl-8 text-muted-foreground">(-) Despesas Operacionais (Totais)</td>
                <td className="px-4 py-3 text-right">{formatCurrency((yearTotal.grossProfit || 0) - (yearTotal.operatingProfit || 0))}</td>
                {dreData.map(d => <td key={d.month} className="px-4 py-3 text-right text-muted-foreground">{formatCurrency((d.grossProfit || 0) - (d.operatingProfit || 0))}</td>)}
              </tr>
              <tr className="hover:bg-muted/30 bg-primary/5">
                <td className="px-4 py-3 font-bold">(=) Lucro Operacional</td>
                <td className="px-4 py-3 text-right font-bold">{formatCurrency(yearTotal.operatingProfit || 0)}</td>
                {dreData.map(d => <td key={d.month} className="px-4 py-3 text-right font-medium">{formatCurrency(d.operatingProfit || 0)}</td>)}
              </tr>
              <tr className="hover:bg-muted/30">
                <td className="px-4 py-3 pl-8 text-muted-foreground">(-) Resultado Financeiro</td>
                <td className="px-4 py-3 text-right">{formatCurrency(yearTotal['Resultado Financeiro (Taxas/Juros)'] || 0)}</td>
                {dreData.map(d => <td key={d.month} className="px-4 py-3 text-right text-muted-foreground">{formatCurrency(d['Resultado Financeiro (Taxas/Juros)'] || 0)}</td>)}
              </tr>
              <tr className="bg-success/10">
                <td className="px-4 py-3 font-bold text-success-foreground text-lg">(=) Lucro Líquido</td>
                <td className="px-4 py-3 text-right font-bold text-success-foreground text-lg">{formatCurrency(yearTotal.netIncome || 0)}</td>
                {dreData.map(d => <td key={d.month} className="px-4 py-3 text-right font-bold text-success-foreground">{formatCurrency(d.netIncome || 0)}</td>)}
              </tr>
            </tbody>
          </table>
        </div>
      </Card>
    </div>
  );
}
