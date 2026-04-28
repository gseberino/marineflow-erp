import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

export type CostCenter = {
  id: string;
  name: string;
  type: 'revenue' | 'expense' | 'both';
  parent_id: string | null;
  active: boolean;
};

export function useCostCenters() {
  return useQuery({
    queryKey: ['cost-centers'],
    queryFn: async () => {
      // Return hardcoded structure if table doesn't exist yet (for local development)
      try {
        const { data, error } = await supabase
          .from('cost_centers')
          .select('*')
          .order('name');
        if (error) throw error;
        return data as CostCenter[];
      } catch (err) {
        console.warn('Cost centers table may not exist yet, using defaults.');
        return [
          { id: '1', name: 'Receitas Operacionais', type: 'revenue', parent_id: null, active: true },
          { id: '2', name: 'Deduções e Impostos', type: 'expense', parent_id: null, active: true },
          { id: '3', name: 'Custos Variáveis (CPV/CSV)', type: 'expense', parent_id: null, active: true },
          { id: '4', name: 'Despesas Operacionais Fixas', type: 'expense', parent_id: null, active: true },
          { id: '5', name: 'Despesas com Pessoal', type: 'expense', parent_id: null, active: true },
          { id: '6', name: 'Despesas Administrativas', type: 'expense', parent_id: null, active: true },
          { id: '7', name: 'Resultado Financeiro (Taxas/Juros)', type: 'expense', parent_id: null, active: true },
        ] as CostCenter[];
      }
    },
  });
}
