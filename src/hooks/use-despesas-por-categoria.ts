// "Para onde foi o dinheiro" — as despesas dos últimos meses, pela mesma fonte do DRE e da
// tela Despesas (payables pela data do lançamento, sem canceladas). A conta é da lib.
import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { lerEmPaginas } from '@/lib/ler-em-paginas';
import { hojeEmBrasilia, limitesDosMeses, ultimosMeses } from '@/lib/fluxo-de-caixa';
import type { DespesaDoMes } from '@/lib/despesas-por-categoria';

export interface DespesasDosMeses {
  meses: string[];
  linhas: DespesaDoMes[];
  /** Categoria → linha do DRE (dre_group). */
  grupoDe: Map<string, string>;
}

export function useDespesasDosMeses(quantosMeses: number) {
  return useQuery({
    queryKey: ['despesas-por-categoria', quantosMeses],
    queryFn: async (): Promise<DespesasDosMeses> => {
      const meses = ultimosMeses(quantosMeses, hojeEmBrasilia());
      const { de, ate } = limitesDosMeses(meses);
      const [cats, linhas] = await Promise.all([
        supabase.from('financial_categories').select('name, dre_group').eq('type', 'payable'),
        // Em páginas: 2026 já passou de 1.000 despesas (ver lerEmPaginas).
        lerEmPaginas((i, f) => supabase.from('payables')
          .select('id, issue_date, amount, expense_category')
          .neq('status', 'cancelled')
          .gte('issue_date', de).lte('issue_date', ate)
          .order('id')
          .range(i, f)),
      ]);
      if (cats.error) throw cats.error;
      const grupoDe = new Map<string, string>();
      for (const c of (cats.data ?? []) as Array<{ name: string; dre_group: string | null }>) {
        if (c.dre_group) grupoDe.set(c.name, c.dre_group);
      }
      return { meses, linhas: linhas as DespesaDoMes[], grupoDe };
    },
    staleTime: 60_000,
  });
}
