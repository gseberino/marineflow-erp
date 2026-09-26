// Os lançamentos do DRE de um ano, com o grupo do plano de contas já resolvido.
//
// Morava dentro do DREPanel; saiu para cá (26/09/2026) porque o Resumo do mês da Central de
// relatórios precisa do MESMO "vendido" e do MESMO resultado do DRE — ler de outro jeito daria
// dois números para a mesma pergunta.
import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { lerEmPaginas } from '@/lib/ler-em-paginas';
import type { LancamentoDRE, GrupoDRE } from '@/lib/dre';

export function useLancamentosDRE(ano: number) {
  return useQuery({
    queryKey: ['dre-lancamentos', ano],
    queryFn: async (): Promise<LancamentoDRE[]> => {
      const de = `${ano}-01-01`;
      const ate = `${ano}-12-31`;

      // Em páginas: 2026 já passou de 1.000 despesas, e a leitura de uma vez deixava ~35
      // (≈ R$ 9,9 mil) fora do resultado sem aviso nenhum.
      const [cats, paysData, recsData] = await Promise.all([
        supabase.from('financial_categories').select('name, type, dre_group'),
        // Cancelada não é despesa. A consulta de receitas sempre filtrou; a de despesas
        // não, e cada lançamento cancelado continuava pesando no resultado.
        lerEmPaginas((i, f) => supabase.from('payables').select('id, issue_date, amount, expense_category')
          .neq('status', 'cancelled')
          .gte('issue_date', de).lte('issue_date', ate)
          .order('id').range(i, f)),
        lerEmPaginas((i, f) => supabase.from('receivables').select('id, issue_date, amount, category, status')
          .gte('issue_date', de).lte('issue_date', ate)
          .order('id').range(i, f)),
      ]);
      if (cats.error) throw cats.error;

      const grupoDe = new Map<string, GrupoDRE>();
      for (const c of (cats.data ?? []) as Array<{ name: string; type: string; dre_group: GrupoDRE | null }>) {
        if (c.dre_group) grupoDe.set(`${c.type}:${c.name}`, c.dre_group);
      }

      const despesas: LancamentoDRE[] = (paysData as Array<{ issue_date: string; amount: number; expense_category: string | null }>).map((p) => ({
        data: p.issue_date,
        valor: Number(p.amount),
        categoria: p.expense_category,
        grupo: p.expense_category ? grupoDe.get(`payable:${p.expense_category}`) ?? null : null,
        tipo: 'despesa',
      }));

      const receitas: LancamentoDRE[] = (recsData as Array<{ issue_date: string; amount: number; category: string | null; status: string | null }>)
        // Receita cancelada não é receita — entraria inflando o faturamento.
        .filter((r) => r.status !== 'cancelled')
        .map((r) => ({
          data: r.issue_date,
          valor: Number(r.amount),
          categoria: r.category,
          // Receita sem categoria ainda é receita: a natureza do lançamento já diz onde
          // entra, diferente da despesa, onde é a categoria que define o grupo.
          grupo: (r.category ? grupoDe.get(`receivable:${r.category}`) : null) ?? 'receita',
          tipo: 'receita',
        }));

      return [...despesas, ...receitas];
    },
    staleTime: 60_000,
  });
}
