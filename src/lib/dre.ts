// Montagem do DRE — lógica pura, para poder ser testada sem tela.
//
// O DRE anterior agrupava por CENTRO DE CUSTO, campo que nunca foi preenchido em nenhum
// dos 367 lançamentos: o relatório existia e mostrava zero em tudo. Este monta pelos
// grupos do plano de contas (`dre_group`), que é onde a classificação de fato mora.

/** Grupos do plano de contas, na ordem em que aparecem no resultado. */
export type GrupoDRE =
  | 'receita'
  | 'custo_direto'
  | 'despesa_operacional'
  | 'financeiro'
  | 'nao_operacional';

export interface LancamentoDRE {
  /** Data que define a competência. */
  data: string;
  valor: number;
  categoria: string | null;
  grupo: GrupoDRE | null;
  tipo: 'receita' | 'despesa';
}

export interface LinhaDRE {
  chave: string;
  rotulo: string;
  valor: number;
  /** Linha somada (subtotal/resultado) — desenhada com mais peso. */
  total?: boolean;
  /** Percentual sobre a receita líquida. Só faz sentido quando há receita. */
  percentual?: number | null;
  /** Abre em categorias. */
  detalhe?: Array<{ categoria: string; valor: number }>;
}

const ROTULO_GRUPO: Record<GrupoDRE, string> = {
  receita: 'Receita',
  custo_direto: 'Custo dos serviços e produtos',
  despesa_operacional: 'Despesas operacionais',
  financeiro: 'Resultado financeiro',
  nao_operacional: 'Não operacional',
};

/** Soma por categoria dentro de um grupo, da maior para a menor. */
function porCategoria(lancs: LancamentoDRE[]): Array<{ categoria: string; valor: number }> {
  const mapa = new Map<string, number>();
  for (const l of lancs) {
    const c = l.categoria ?? 'Sem categoria';
    mapa.set(c, (mapa.get(c) ?? 0) + l.valor);
  }
  return [...mapa.entries()]
    .map(([categoria, valor]) => ({ categoria, valor }))
    .sort((a, b) => b.valor - a.valor);
}

/**
 * Monta o resultado do período.
 *
 * A estrutura segue a de prestadora de serviços: receita menos o custo do que foi
 * entregue dá o lucro bruto; menos as despesas de manter a empresa aberta dá o resultado
 * operacional; menos juros e tarifas dá o resultado do período.
 *
 * O grupo `nao_operacional` fica FORA de tudo, somado à parte. É o que mais engana num
 * resultado caseiro: pagamento de fatura de cartão, transferência entre contas próprias e
 * aplicação financeira movimentam muito dinheiro e não são despesa. No extrato desta
 * empresa, só o pagamento de fatura soma R$ 30 mil — jogá-lo no resultado transformaria
 * um mês bom em prejuízo.
 */
export function montarDRE(lancamentos: LancamentoDRE[]): {
  linhas: LinhaDRE[];
  receitaTotal: number;
  resultado: number;
  naoOperacional: number;
  semGrupo: number;
} {
  const do_ = (g: GrupoDRE) => lancamentos.filter((l) => l.grupo === g);
  const soma = (ls: LancamentoDRE[]) => ls.reduce((s, l) => s + l.valor, 0);

  const receitas = do_('receita');
  const custos = do_('custo_direto');
  const despesas = do_('despesa_operacional');
  const financeiro = do_('financeiro');
  const naoOper = do_('nao_operacional');

  // Lançamento sem grupo não entra em lugar nenhum — e some do resultado sem avisar.
  // Contamos para poder DENUNCIAR, em vez de deixar o total mentir por omissão.
  const semGrupo = soma(lancamentos.filter((l) => !l.grupo));

  const receitaTotal = soma(receitas);
  const custoTotal = soma(custos);
  const despesaTotal = soma(despesas);
  const financeiroTotal = soma(financeiro);
  const naoOperacional = soma(naoOper);

  const lucroBruto = receitaTotal - custoTotal;
  const resultadoOperacional = lucroBruto - despesaTotal;
  const resultado = resultadoOperacional - financeiroTotal;

  const pct = (v: number) => (receitaTotal > 0 ? (v / receitaTotal) * 100 : null);

  const linhas: LinhaDRE[] = [
    {
      chave: 'receita', rotulo: ROTULO_GRUPO.receita, valor: receitaTotal,
      percentual: receitaTotal > 0 ? 100 : null, detalhe: porCategoria(receitas),
    },
    {
      chave: 'custo_direto', rotulo: `(−) ${ROTULO_GRUPO.custo_direto}`, valor: -custoTotal,
      percentual: pct(-custoTotal), detalhe: porCategoria(custos),
    },
    { chave: 'lucro_bruto', rotulo: '= Lucro bruto', valor: lucroBruto, total: true, percentual: pct(lucroBruto) },
    {
      chave: 'despesa_operacional', rotulo: `(−) ${ROTULO_GRUPO.despesa_operacional}`, valor: -despesaTotal,
      percentual: pct(-despesaTotal), detalhe: porCategoria(despesas),
    },
    {
      chave: 'resultado_operacional', rotulo: '= Resultado operacional', valor: resultadoOperacional,
      total: true, percentual: pct(resultadoOperacional),
    },
    {
      chave: 'financeiro', rotulo: `(−) ${ROTULO_GRUPO.financeiro}`, valor: -financeiroTotal,
      percentual: pct(-financeiroTotal), detalhe: porCategoria(financeiro),
    },
    {
      chave: 'resultado', rotulo: '= Resultado do período', valor: resultado,
      total: true, percentual: pct(resultado),
    },
  ];

  return { linhas, receitaTotal, resultado, naoOperacional, semGrupo };
}

/** Recorta os lançamentos de um mês (competência pela data informada). */
export function doMes(lancamentos: LancamentoDRE[], ano: number, mes: number): LancamentoDRE[] {
  return lancamentos.filter((l) => {
    // Fatiar a string evita o deslocamento de fuso que `new Date('2026-07-01')` provoca:
    // em UTC-3 a data volta um dia e o lançamento do dia 1º cai no mês anterior.
    const [a, m] = l.data.split('-').map(Number);
    return a === ano && m === mes;
  });
}

export const ROTULOS_GRUPO = ROTULO_GRUPO;
