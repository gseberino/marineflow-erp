import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { lerLinhasDoFluxo } from '@/hooks/use-fluxo-de-caixa';
import {
  hojeEmBrasilia, somarDias, somarFluxoDoPeriodo, ultimosMeses, MARGEM_PARA_PAREAR,
} from '@/lib/fluxo-de-caixa';

/**
 * O "Entrou no mês" do painel: o dinheiro que entrou nas contas e no Caixa pelo EXTRATO, com a
 * regra da Central de relatórios — o mesmo número do Resumo do mês e do assistente. Até
 * 27/09/2026 era a soma da tabela `payments` (as baixas registradas à mão), que quase ninguém
 * usa: o painel dizia um valor, a Central outro e o assistente um terceiro.
 *
 * A comparação é com o MESMO trecho do mês anterior (do dia 1º até o mesmo dia): comparar dez
 * dias deste mês com o mês anterior inteiro dava sempre "caiu".
 */
export function entrouNoMesPeloExtrato(linhas: Parameters<typeof somarFluxoDoPeriodo>[0], hoje: string) {
  const inicio = `${hoje.slice(0, 7)}-01`;
  const inicioAnterior = `${ultimosMeses(2, hoje)[0]}-01`;
  const ultimoDiaAnterior = somarDias(inicio, -1);
  const mesmoDia = `${inicioAnterior.slice(0, 8)}${hoje.slice(8, 10)}`;
  const ateNoAnterior = mesmoDia < ultimoDiaAnterior ? mesmoDia : ultimoDiaAnterior;
  return {
    esteMes: somarFluxoDoPeriodo(linhas, inicio, hoje, hoje).entrou,
    mesmoTrechoDoAnterior: somarFluxoDoPeriodo(linhas, inicioAnterior, ateNoAnterior, hoje).entrou,
  };
}

export function useDashboardData() {
  const today = new Date().toISOString().split('T')[0];
  const firstOfMonth = `${today.substring(0, 7)}-01`;
  const in7days = new Date(Date.now() + 7 * 86400000).toISOString().split('T')[0];
  const hojeLocal = hojeEmBrasilia();

  return useQuery({
    queryKey: ['dashboard'],
    queryFn: async () => {
      const [
        receivablesRes,
        payablesRes,
        linhasDoFluxo,
        overdueReceivablesRes,
        openOrdersRes,
        ordersByStatusRes,
        completedThisMonthRes,
        upcomingOrdersRes,
        revenueChartRes,
      ] = await Promise.all([
        supabase.from('receivables')
          .select('balance_amount')
          .not('status', 'in', '("paid","cancelled")'),

        supabase.from('payables')
          .select('balance_amount')
          .not('status', 'in', '("paid","cancelled")'),

        // Do 1º dia do mês anterior até hoje, com a margem para parear transferência.
        lerLinhasDoFluxo(
          somarDias(`${ultimosMeses(2, hojeLocal)[0]}-01`, -MARGEM_PARA_PAREAR),
          somarDias(hojeLocal, MARGEM_PARA_PAREAR),
        ),

        supabase.from('receivables')
          .select('balance_amount')
          .not('status', 'in', '("paid","cancelled")')
          .lt('due_date', today),

        supabase.from('service_orders')
          .select('id, service_order_number, status, grand_total, scheduled_start_at, clients(name), vessels(name)')
          .not('status', 'in', '("completed","invoiced","cancelled")')
          .order('created_at', { ascending: false })
          .limit(8),

        supabase.from('service_orders')
          .select('status')
          .not('status', 'in', '("cancelled")'),

        supabase.from('service_orders')
          .select('grand_total')
          .in('status', ['completed', 'invoiced'])
          .gte('updated_at', firstOfMonth),

        supabase.from('service_orders')
          .select('id, service_order_number, scheduled_start_at, clients(name), vessels(name), status')
          .in('status', ['scheduled', 'open'])
          .gte('scheduled_start_at', today)
          .lte('scheduled_start_at', in7days)
          .order('scheduled_start_at', { ascending: true })
          .limit(5),

        supabase.from('payments')
          .select('payment_date, amount')
          .not('receivable_id', 'is', null)
          .eq('status', 'confirmed')
          .gte('payment_date', (() => {
            const d = new Date();
            d.setMonth(d.getMonth() - 5);
            return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`;
          })())
          .order('payment_date', { ascending: true }),
      ]);

      // Low stock (separate query since we need JS filter for column comparison)
      const lowStockRes = await supabase
        .from('products')
        .select('id, name, stock_quantity, minimum_stock, product_categories(name)')
        .eq('active', true)
        .gt('minimum_stock', 0)
        .order('name')
        .limit(50);

      const lowStock = (lowStockRes.data || [])
        .filter(p => (p.stock_quantity ?? 0) < (p.minimum_stock ?? 0))
        .slice(0, 5);

      // Process revenue chart data
      const monthNames = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];
      const now = new Date();
      const revenueByMonth: Record<string, number> = {};
      for (let i = 5; i >= 0; i--) {
        const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
        const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
        revenueByMonth[key] = 0;
      }
      for (const p of revenueChartRes.data || []) {
        const key = p.payment_date.substring(0, 7);
        if (revenueByMonth[key] !== undefined) {
          revenueByMonth[key] += Number(p.amount);
        }
      }
      const revenueChart = Object.entries(revenueByMonth).map(([key, value]) => {
        const [, m] = key.split('-');
        return {
          month: `${monthNames[parseInt(m) - 1]}/${key.slice(2, 4)}`,
          revenue: Math.round(value * 100) / 100,
        };
      });

      // Process status counts
      const statusCounts: Record<string, number> = {};
      for (const so of ordersByStatusRes.data || []) {
        statusCounts[so.status] = (statusCounts[so.status] || 0) + 1;
      }

      // Sum helpers
      const sum = (rows: any[] | null, field = 'balance_amount') =>
        (rows || []).reduce((s: number, r: any) => s + Number(r[field] || 0), 0);

      const entrou = entrouNoMesPeloExtrato(linhasDoFluxo, hojeLocal);
      const collectedThisMonth = entrou.esteMes;
      /** Até o mesmo dia do mês anterior — não o mês anterior inteiro. */
      const collectedLastMonth = entrou.mesmoTrechoDoAnterior;
      const revenueGrowth = collectedLastMonth > 0
        ? Math.round(((collectedThisMonth - collectedLastMonth) / collectedLastMonth) * 100)
        : null;

      return {
        totalReceivable: sum(receivablesRes.data),
        totalPayable: sum(payablesRes.data),
        collectedThisMonth,
        collectedLastMonth,
        revenueGrowth,
        overdueReceivables: sum(overdueReceivablesRes.data),

        openOrders: openOrdersRes.data || [],
        openOrdersCount: (openOrdersRes.data || []).length,
        statusCounts,
        completedThisMonth: completedThisMonthRes.data?.length || 0,
        completedThisMonthValue: sum(completedThisMonthRes.data || [], 'grand_total'),
        upcomingOrders: upcomingOrdersRes.data || [],

        revenueChart,
        lowStock,
      };
    },
    staleTime: 60 * 1000,
    refetchInterval: 5 * 60 * 1000,
  });
}
