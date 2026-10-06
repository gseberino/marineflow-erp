// Os cômodos do Financeiro e as rotas de cada um (reorganização de 26/09/2026).
//
// Antes, toda rota /v2/financial/<secao> mostrava a MESMA barra com 14 abas. O dono: "ainda
// achei abas demais". A regra que ele aprovou (e que AppLayout.menu.test.tsx guarda): MENU é
// destino — o que vou fazer agora —, ABA é recorte do mesmo material; nada nos dois lugares.
//
// Agora cada rota abre SÓ o seu assunto, com título próprio e, quando precisa, UM nível de
// abas: /v2/financial/<cômodo>/<aba>. Os links antigos continuam valendo: cada seção que
// deixou de existir leva ao lugar novo (tabela ANTIGAS abaixo). Tudo aqui é puro, para o
// mapa de links antigos ser testado sem montar a tela.

export type Comodo = 'visao' | 'extrato' | 'conciliacao' | 'pagar' | 'despesas' | 'diarias' | 'bancos' | 'cadastro';

export interface AbaDoComodo {
  aba: string;
  rotulo: string;
  /** A frase de "para que serve", embaixo do título, quando esta aba está aberta. */
  paraQueServe: string;
}

export interface DefinicaoDoComodo {
  comodo: Comodo;
  /** Segmento da rota: /v2/financial/<secao>. Vazio = a raiz (/v2/financial). */
  secao: string;
  nome: string;
  paraQueServe: string;
  /** Um nível só. A primeira é a padrão e não aparece na rota. */
  abas: AbaDoComodo[];
}

/**
 * Para que serve cada cômodo, numa frase — embaixo do título, sempre visível (pedido do dono,
 * 26/09/2026: "um breve resumo de para que serve cada aba").
 */
export const PARA_QUE_SERVE = {
  overview: 'Como está o dinheiro hoje: quanto há em cada conta e no Caixa, o que você tem a receber e a pagar, e o que entrou e saiu pelo extrato. Lucro ou prejuízo fica na Central de relatórios.',
  dre: 'Diz se a empresa deu lucro ou prejuízo no período: o que foi vendido menos custos e despesas, pela data do lançamento. Não é o saldo do banco.',
  payables: 'O que a empresa ainda deve pagar. O que já saiu, com a categoria de cada gasto, fica em Despesas.',
  reembolsos: 'O que técnicos pagaram do próprio bolso numa OS e a empresa ainda precisa devolver.',
  despesas: 'Tudo o que saiu (bancos, cartão, Caixa e bolso de sócio) e em que categoria entrou. Aqui você confere e corrige.',
  comissoes: 'Comissões de técnicos e vendedores. Aprovar cria a conta a pagar.',
  forecast: 'Previsão semana a semana, pelo que vence a receber e a pagar nas próximas 8 semanas: vai faltar dinheiro em alguma semana?',
  inbox: 'O que o banco trouxe e ainda precisa de uma decisão sua, conta por conta. Aprovar só registra: nenhum pagamento é feito.',
  saldo: 'O mês de uma conta como no app do banco, com o saldo linha a linha e o que cada movimento virou no sistema.',
  fora: 'O que saiu da fila sem virar lançamento (duplicata, fatura, transferência entre contas suas), com o motivo e o botão Devolver.',
  reconciliation: 'Confere se o que foi lançado tem a linha correspondente no banco. No Extrato você parte do banco; aqui, do que você lançou.',
  cartoes: 'As faturas do cartão de crédito: compras de cada ciclo, pagamento e juros. Compra no débito não fica aqui.',
  rules: 'O que você ensinou o sistema a classificar. "Preencher e esperar meu OK" só sugere; "Lançar sozinha" lança sem clique.',
  fechamento: 'Confere se o mês está completo e trava os números. Mês fechado não muda sem um motivo.',
  cadastro: 'Cadastros que atrapalham o reconhecimento automático (apelido ruim, CNPJ faltando ou duplicado), com a correção sugerida.',
  banks: 'Os bancos ligados ao sistema e o saldo de cada conta. O dia a dia do que entrou e saiu fica no Extrato.',
  aging: 'Quem deve à empresa e a quem a empresa deve, por tempo de atraso: a vencer, 1–30, 31–60, 61–90 e mais de 90 dias.',
  diarias: 'Os dias que cada freelancer trabalhou, o que ele recebeu e o saldo com ele: você deve, adiantado ou quitado. O pagamento vem do extrato do banco (ou "Registrar pagamento"); aqui se lança o dia e se fecha o acerto.',
  diariasExtrato: 'Dia a dia de um freelancer, com o saldo corrido: cada diária e cada pagamento, com a conta de onde saiu.',
  diariasGrade: 'O mês inteiro de todos os freelancers: clique num dia para marcar dia inteiro, meio período ou falta, e para corrigir ou excluir.',
} as const;

export const COMODOS: Record<Comodo, DefinicaoDoComodo> = {
  visao: { comodo: 'visao', secao: '', nome: 'Visão Geral', paraQueServe: PARA_QUE_SERVE.overview, abas: [] },
  extrato: {
    comodo: 'extrato', secao: 'inbox', nome: 'Extrato', paraQueServe: PARA_QUE_SERVE.inbox,
    abas: [
      { aba: 'revisar', rotulo: 'Para revisar', paraQueServe: PARA_QUE_SERVE.inbox },
      { aba: 'saldo', rotulo: 'Extrato com saldo', paraQueServe: PARA_QUE_SERVE.saldo },
      { aba: 'fora', rotulo: 'Fora da fila', paraQueServe: PARA_QUE_SERVE.fora },
      { aba: 'cartao', rotulo: 'Cartão de crédito', paraQueServe: PARA_QUE_SERVE.cartoes },
      { aba: 'regras', rotulo: 'Regras', paraQueServe: PARA_QUE_SERVE.rules },
    ],
  },
  conciliacao: {
    comodo: 'conciliacao', secao: 'reconciliation', nome: 'Conciliação', paraQueServe: PARA_QUE_SERVE.reconciliation,
    abas: [
      { aba: 'conciliacao', rotulo: 'Conciliação', paraQueServe: PARA_QUE_SERVE.reconciliation },
      { aba: 'fechar', rotulo: 'Fechar o mês', paraQueServe: PARA_QUE_SERVE.fechamento },
    ],
  },
  pagar: {
    comodo: 'pagar', secao: 'payables', nome: 'Contas a Pagar', paraQueServe: PARA_QUE_SERVE.payables,
    abas: [
      { aba: 'aberto', rotulo: 'Em aberto', paraQueServe: PARA_QUE_SERVE.payables },
      { aba: 'reembolsos', rotulo: 'Reembolsos', paraQueServe: PARA_QUE_SERVE.reembolsos },
      { aba: 'comissoes', rotulo: 'Comissões', paraQueServe: PARA_QUE_SERVE.comissoes },
    ],
  },
  despesas: { comodo: 'despesas', secao: 'despesas', nome: 'Despesas', paraQueServe: PARA_QUE_SERVE.despesas, abas: [] },
  // Diárias de freelancers (28/09/2026): destino próprio no menu (decisão D6 do dono).
  diarias: {
    comodo: 'diarias', secao: 'diarias', nome: 'Diárias', paraQueServe: PARA_QUE_SERVE.diarias,
    abas: [
      { aba: 'resumo', rotulo: 'Resumo', paraQueServe: PARA_QUE_SERVE.diarias },
      { aba: 'grade', rotulo: 'Grade do mês', paraQueServe: PARA_QUE_SERVE.diariasGrade },
      { aba: 'extrato', rotulo: 'Extrato', paraQueServe: PARA_QUE_SERVE.diariasExtrato },
    ],
  },
  bancos: { comodo: 'bancos', secao: 'banks', nome: 'Contas bancárias', paraQueServe: PARA_QUE_SERVE.banks, abas: [] },
  cadastro: { comodo: 'cadastro', secao: 'cadastro', nome: 'Saúde do cadastro', paraQueServe: PARA_QUE_SERVE.cadastro, abas: [] },
};

const COMODO_DA_SECAO = new Map<string, Comodo>(
  Object.values(COMODOS).filter((c) => c.secao).map((c) => [c.secao, c.comodo]),
);

/**
 * Seções que deixaram de ser aba solta e o lugar novo de cada uma. Favoritos, mensagens do
 * assistente e o menu de ontem apontam para elas: quebrar esses links seria trocar um
 * problema de navegação por outro.
 */
export const ANTIGAS: Record<string, string> = {
  overview: '/v2/financial',
  receivables: '/v2/receivables',
  collections: '/v2/receivables/cobrancas',
  extrato: '/v2/financial/inbox',
  ignoradas: '/v2/financial/inbox/fora',
  cartoes: '/v2/financial/inbox/cartao',
  rules: '/v2/financial/inbox/regras',
  fechamento: '/v2/financial/reconciliation/fechar',
  comissoes: '/v2/financial/payables/comissoes',
  reimbursements: '/v2/financial/payables/reembolsos',
  dre: '/v2/reports/dre',
  aging: '/v2/reports/aging',
  forecast: '/v2/reports/fluxo',
};

/** O endereço de um cômodo (e aba). A aba padrão não aparece no endereço. */
export function rotaDoComodo(comodo: Comodo, aba?: string | null): string {
  const def = COMODOS[comodo];
  const raiz = def.secao ? `/v2/financial/${def.secao}` : '/v2/financial';
  if (!aba || def.abas.length === 0 || aba === def.abas[0].aba) return raiz;
  return `${raiz}/${aba}`;
}

export type RotaDoFinanceiro =
  | { tipo: 'comodo'; comodo: Comodo; aba: string | null }
  | { tipo: 'redirecionar'; para: string };

/**
 * O que a rota /v2/financial[/secao[/aba]] (com ?tab= antigo) deve mostrar.
 *
 * - `?tab=` sem seção (link de antes de 19/09) vira a rota da seção;
 * - seção antiga vai para o lugar novo;
 * - seção ou aba desconhecida leva à raiz do cômodo mais próximo — tela em branco nunca
 *   (era o que acontecia com a notificação "Recebível em atraso").
 */
export function resolverFinanceiro(secao?: string | null, aba?: string | null, tabDaQuery?: string | null): RotaDoFinanceiro {
  if (!secao) {
    if (tabDaQuery) {
      return { tipo: 'redirecionar', para: ANTIGAS[tabDaQuery] ?? (COMODO_DA_SECAO.has(tabDaQuery) ? `/v2/financial/${tabDaQuery}` : '/v2/financial') };
    }
    return { tipo: 'comodo', comodo: 'visao', aba: null };
  }
  const comodo = COMODO_DA_SECAO.get(secao);
  if (!comodo) return { tipo: 'redirecionar', para: ANTIGAS[secao] ?? '/v2/financial' };
  const def = COMODOS[comodo];
  if (!aba) return { tipo: 'comodo', comodo, aba: def.abas[0]?.aba ?? null };
  if (def.abas.some((a) => a.aba === aba)) return { tipo: 'comodo', comodo, aba };
  return { tipo: 'redirecionar', para: rotaDoComodo(comodo) };
}

/** A frase de "para que serve" do que está aberto (cômodo + aba). */
export function paraQueServeDe(comodo: Comodo, aba: string | null): string {
  const def = COMODOS[comodo];
  return def.abas.find((a) => a.aba === aba)?.paraQueServe ?? def.paraQueServe;
}
