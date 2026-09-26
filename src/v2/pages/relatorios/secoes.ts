// As seções da Central de relatórios (26/09/2026).
//
// Pedido do dono: "tudo que é demonstrativo ou relatório deveria estar em uma só aba, e lá
// dentro teria opções de aging, gráficos etc.". A Central é essa porta única: /v2/reports/<seção>,
// um nível só de abas. Puro, para o mapa de links antigos ser testado sem montar a tela.

export type SecaoDaCentral = 'resumo' | 'fluxo' | 'dre' | 'categorias' | 'aging' | 'operacao';

export interface DefinicaoDaSecao {
  secao: SecaoDaCentral;
  rotulo: string;
  paraQueServe: string;
}

export const SECOES_DA_CENTRAL: DefinicaoDaSecao[] = [
  {
    secao: 'resumo', rotulo: 'Resumo do mês',
    paraQueServe: 'Os quatro números de um mês: o que entrou e saiu das contas, o que foi vendido e o resultado.',
  },
  {
    secao: 'fluxo', rotulo: 'Fluxo de caixa',
    paraQueServe: 'O dinheiro que entrou e saiu das contas, mês a mês, e a previsão das próximas 8 semanas a partir do saldo de hoje.',
  },
  {
    secao: 'dre', rotulo: 'Resultado (DRE)',
    paraQueServe: 'Diz se a empresa deu lucro ou prejuízo no período: o que foi vendido menos custos e despesas, pela data do lançamento. Não é o saldo do banco.',
  },
  {
    secao: 'categorias', rotulo: 'Para onde foi o dinheiro',
    paraQueServe: 'As despesas por categoria, mês a mês, nos últimos 6 meses — as mesmas do DRE e da tela Despesas.',
  },
  {
    secao: 'aging', rotulo: 'Quem deve e a quem devo',
    paraQueServe: 'O que falta receber e o que falta pagar, por tempo de atraso: a vencer, 1–30, 31–60, 61–90 e mais de 90 dias.',
  },
  {
    secao: 'operacao', rotulo: 'Operação',
    paraQueServe: 'Os números das ordens de serviço: receita por cliente, andamento, peças, técnicos e lucro por OS. Conta só OS aprovada.',
  },
];

/** As partes da antiga tela "Gerenciais" (?tab=), que hoje vivem em Operação. */
export const PARTES_DA_OPERACAO = ['revenue', 'performance', 'parts', 'technicians', 'profitability'] as const;
export type ParteDaOperacao = typeof PARTES_DA_OPERACAO[number];

export type RotaDaCentral =
  | { tipo: 'secao'; secao: SecaoDaCentral }
  | { tipo: 'redirecionar'; para: string };

/** O que /v2/reports[/secao] (com ?tab= antigo) deve mostrar. Link antigo nunca cai em branco. */
export function resolverCentral(secao?: string | null, tabDaQuery?: string | null): RotaDaCentral {
  if (!secao) {
    // /v2/reports?tab=parts — o link da antiga "Gerenciais" — abre Operação já nessa parte.
    if (tabDaQuery && (PARTES_DA_OPERACAO as readonly string[]).includes(tabDaQuery)) {
      return { tipo: 'redirecionar', para: `/v2/reports/operacao?tab=${tabDaQuery}` };
    }
    return { tipo: 'secao', secao: 'resumo' };
  }
  const conhecida = SECOES_DA_CENTRAL.find((s) => s.secao === secao);
  if (conhecida) return { tipo: 'secao', secao: conhecida.secao };
  return { tipo: 'redirecionar', para: '/v2/reports' };
}

/** Endereço de uma seção; o Resumo é a raiz. */
export function rotaDaSecao(secao: SecaoDaCentral): string {
  return secao === 'resumo' ? '/v2/reports' : `/v2/reports/${secao}`;
}
