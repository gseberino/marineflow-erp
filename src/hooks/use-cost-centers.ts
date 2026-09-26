import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

export type CostCenter = {
  id: string;
  name: string;
  type: 'revenue' | 'expense' | 'both';
  parent_id: string | null;
  active: boolean;
};

/**
 * Todos os centros de custo, ativos e desativados.
 *
 * Os sete antigos (Receitas Operacionais, Custos Variáveis…) eram grupos do DRE e foram
 * DESATIVADOS em 27/09/2026 — não apagados: o que já foi lançado neles continua apontando para
 * eles. Quem oferece escolha usa `centrosParaEscolher`, que mostra só os ativos (e o desativado
 * que o lançamento já tem, para não sumir da tela).
 *
 * A versão anterior devolvia uma lista inventada (ids "1" a "7") quando a leitura falhava — um
 * id que não existe, gravado sem erro nenhum até o banco recusar. Erro de leitura agora é erro.
 */
export function useCostCenters() {
  return useQuery({
    queryKey: ['cost-centers'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('cost_centers')
        .select('*')
        .order('name');
      if (error) throw error;
      return (data ?? []) as CostCenter[];
    },
    staleTime: 5 * 60_000,
  });
}

/**
 * Os centros que cabem numa escolha: ativos, do lado certo (despesa ou receita), e o que o
 * lançamento já tem mesmo que desativado — marcado como tal.
 */
export function centrosParaEscolher(
  centros: CostCenter[] | undefined,
  lado: 'payable' | 'receivable',
  atual?: string | null,
): Array<CostCenter & { rotulo: string }> {
  const doLado = (c: CostCenter) => c.type === 'both' || c.type === (lado === 'payable' ? 'expense' : 'revenue');
  return (centros ?? [])
    .filter((c) => (c.active && doLado(c)) || (!!atual && c.id === atual))
    .map((c) => ({ ...c, rotulo: c.active ? c.name : `${c.name} (desativado)` }));
}
