// O fluxo de caixa pelo extrato — leitura do banco. A regra de quais linhas contam mora em
// supabase/functions/_shared/banking/fluxo-de-caixa.ts (pura, testada, a mesma do assistente);
// aqui só se busca o que ela precisa.
import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { lerEmPaginas } from '@/lib/ler-em-paginas';
import {
  montarFluxoDeCaixa, hojeEmBrasilia, ultimosMeses, limitesDosMeses, somarDias,
  MARGEM_PARA_PAREAR, COLUNAS_DO_FLUXO,
  type FluxoDeCaixa, type LinhaDoFluxo,
} from '@/lib/fluxo-de-caixa';

/**
 * As linhas de conta corrente e Caixa do período, TODAS: em páginas, porque o servidor corta
 * em 1.000 linhas sem avisar (ver lerEmPaginas). O cartão de crédito já fica de fora aqui —
 * não é caixa —, o resto das regras é da lib.
 */
export async function lerLinhasDoFluxo(de: string, ate: string): Promise<LinhaDoFluxo[]> {
  return lerEmPaginas((i, f) => supabase
    .from('bank_transactions')
    .select(COLUNAS_DO_FLUXO)
    .in('source_type', ['bank', 'cash'])
    .gte('transaction_date', de)
    .lte('transaction_date', ate)
    .order('transaction_date')
    .order('id')
    .range(i, f));
}

/** Os `quantosMeses` meses que terminam em `ateMes` ('AAAA-MM'; padrão: o mês corrente). */
export async function carregarFluxoDeCaixa(quantosMeses: number, ateMes?: string): Promise<FluxoDeCaixa> {
  const hoje = hojeEmBrasilia();
  const meses = ultimosMeses(quantosMeses, ateMes ?? hoje);
  const { de, ate } = limitesDosMeses(meses);
  // Alguns dias a mais de cada lado: a outra perna de uma transferência feita na virada do mês
  // mora do outro lado do recorte. Essas linhas só servem para parear — não somam.
  const linhas = await lerLinhasDoFluxo(somarDias(de, -MARGEM_PARA_PAREAR), somarDias(ate, MARGEM_PARA_PAREAR));
  return montarFluxoDeCaixa(linhas, meses, hoje);
}

/** Chave única do cache: o gráfico da Visão Geral e a Central leem a mesma entrada. */
export const chaveDoFluxo = (quantosMeses: number, ateMes?: string) =>
  ['fluxo-de-caixa', quantosMeses, ateMes ?? 'atual'] as const;

export function useFluxoDeCaixa(quantosMeses: number, ateMes?: string) {
  return useQuery({
    queryKey: chaveDoFluxo(quantosMeses, ateMes),
    queryFn: () => carregarFluxoDeCaixa(quantosMeses, ateMes),
    staleTime: 60_000,
  });
}
