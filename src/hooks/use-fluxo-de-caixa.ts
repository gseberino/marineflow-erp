// O fluxo de caixa pelo extrato — leitura do banco. A regra de quais linhas contam mora em
// supabase/functions/_shared/banking/fluxo-de-caixa.ts (pura, testada, a mesma do assistente);
// aqui só se busca o que ela precisa.
import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { lerEmPaginas } from '@/lib/ler-em-paginas';
import {
  montarFluxoDeCaixa, hojeEmBrasilia, ultimosMeses, limitesDosMeses,
  COLUNAS_DO_FLUXO, FUNCAO_DA_RAIZ_DA_EMPRESA,
  type FluxoDeCaixa, type LinhaDoFluxo, type OpcoesDoFluxo,
} from '@/lib/fluxo-de-caixa';

/**
 * As linhas de conta corrente e Caixa do período, TODAS: em páginas, porque o servidor corta
 * em 1.000 linhas sem avisar (ver lerEmPaginas). O cartão de crédito já fica de fora aqui —
 * não é caixa —, o resto das regras é da lib. Leia sempre meses INTEIROS: o pareamento de
 * cada mês usa todas as linhas dele.
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

let raizEmCache: Promise<string | null> | null = null;

/**
 * A raiz do CNPJ da empresa (8 dígitos): o Pix ou TED com ela do outro lado é transferência entre
 * contas suas. Não muda — uma leitura por sessão. Se falhar, a regra segue sem ela (só a marca e
 * o par) e a próxima leitura tenta de novo.
 */
export function lerRaizDaEmpresa(): Promise<string | null> {
  if (!raizEmCache) {
    raizEmCache = Promise.resolve(supabase.rpc(FUNCAO_DA_RAIZ_DA_EMPRESA as never))
      .then(({ data, error }) => {
        if (error) throw error;
        const raiz: unknown = data;
        return typeof raiz === 'string' && raiz.length === 8 ? raiz : null;
      })
      .catch(() => {
        raizEmCache = null;
        return null;
      });
  }
  return raizEmCache;
}

/** As linhas e o que a regra precisa saber além delas. */
export async function lerExtratoDoFluxo(de: string, ate: string): Promise<{ linhas: LinhaDoFluxo[]; opcoes: OpcoesDoFluxo }> {
  const [linhas, raizDaEmpresa] = await Promise.all([lerLinhasDoFluxo(de, ate), lerRaizDaEmpresa()]);
  return { linhas, opcoes: { raizDaEmpresa } };
}

/** Os `quantosMeses` meses que terminam em `ateMes` ('AAAA-MM'; padrão: o mês corrente). */
export async function carregarFluxoDeCaixa(quantosMeses: number, ateMes?: string): Promise<FluxoDeCaixa> {
  const hoje = hojeEmBrasilia();
  const meses = ultimosMeses(quantosMeses, ateMes ?? hoje);
  const { de, ate } = limitesDosMeses(meses);
  const { linhas, opcoes } = await lerExtratoDoFluxo(de, ate);
  return montarFluxoDeCaixa(linhas, meses, hoje, opcoes);
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
