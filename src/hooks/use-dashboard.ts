import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { lerLinhasDoFluxo } from '@/hooks/use-fluxo-de-caixa';
import {
  hojeEmBrasilia, montarFluxoDeCaixa, rotuloDoMes, somarDias, somarFluxoDoPeriodo, ultimosMeses,
  MARGEM_PARA_PAREAR, type LinhaDoFluxo,
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
  // O gráfico dos 6 meses e o "Entrou no mês" saem da MESMA leitura do extrato.
  const seisMeses = ultimosMeses(6, hojeLocal);

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
      ] = await Promise.all([
        supabase.from('receivables')
          .select('balance_amount')
          .not('status', 'in', '("paid","cancelled")'),

        supabase.from('payables')
          .select('balance_amount')
          .not('status', 'in', '("paid","cancelled")'),

        // Os 6 meses do gráfico até hoje, com a margem para parear transferência. Um erro aqui
        // apaga só os números do extrato, não o painel inteiro (as outras leituras devolvem o
        // erro em vez de lançar; esta lança).
        lerLinhasDoFluxo(
          somarDias(`${seisMeses[0]}-01`, -MARGEM_PARA_PAREAR),
          somarDias(hojeLocal, MARGEM_PARA_PAREAR),
        ).then(
          (linhas) => ({ linhas, erro: null as string | null }),
          (e: unknown) => ({ linhas: [] as LinhaDoFluxo[], erro: (e as Error)?.message ?? String(e) }),
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

      // O gráfico: o que ENTROU nas contas mês a mês pelo extrato, com a regra da Central de
      // relatórios. Até 27/09/2026 somava a tabela `payments` (as baixas registradas à mão) e
      // mostrava quase nada ao lado do "Entrou no mês".
      const erroDoExtrato = linhasDoFluxo.erro;
      const revenueChart = erroDoExtrato
        ? []
        : montarFluxoDeCaixa(linhasDoFluxo.linhas, seisMeses, hojeLocal).meses
          .map((m) => ({ month: rotuloDoMes(m.mes), revenue: m.entrou }));

      // Process status counts
      const statusCounts: Record<string, number> = {};
      for (const so of ordersByStatusRes.data || []) {
        statusCounts[so.status] = (statusCounts[so.status] || 0) + 1;
      }

      // Sum helpers
      const sum = (rows: any[] | null, field = 'balance_amount') =>
        (rows || []).reduce((s: number, r: any) => s + Number(r[field] || 0), 0);

      // null = não deu para ler o extrato: a tela diz isso em vez de mostrar R$ 0,00.
      const entrou = erroDoExtrato ? null : entrouNoMesPeloExtrato(linhasDoFluxo.linhas, hojeLocal);
      const collectedThisMonth = entrou?.esteMes ?? null;
      /** Até o mesmo dia do mês anterior — não o mês anterior inteiro. */
      const collectedLastMonth = entrou?.mesmoTrechoDoAnterior ?? null;
      const revenueGrowth = entrou && entrou.mesmoTrechoDoAnterior > 0
        ? Math.round(((entrou.esteMes - entrou.mesmoTrechoDoAnterior) / entrou.mesmoTrechoDoAnterior) * 100)
        : null;

      return {
        totalReceivable: sum(receivablesRes.data),
        totalPayable: sum(payablesRes.data),
        collectedThisMonth,
        collectedLastMonth,
        revenueGrowth,
        erroDoExtrato,
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
