// Agrupar orçamentos (15/10/2026): N orçamentos abertos do MESMO cliente e da MESMA embarcação viram UM
// orçamento novo (agrupar_orcamentos, migration 20261015180000). Quem decide é o banco; estas funções só
// antecipam na tela o que ele vai recusar ou avisar, para o dono escolher sabendo o que acontece.
// Decisões do dono: preços mantidos; condição de pagamento, contato e comissão vêm do orçamento PRINCIPAL
// (comissão recalculada sobre o total novo); desagrupar sempre possível enquanto o novo estiver em aberto.

export const MIN_AGRUPAR = 2;
export const MAX_AGRUPAR = 10;

export type CandidatoAgrupar = {
  id: string;
  service_order_number: string;
  status: string;
  quote_status: string | null;
  grand_total: number | null;
  created_at: string;
  client_id: string;
  vessel_id: string;
  signed_at: string | null;
  converted_to_os_at: string | null;
  merged_into_id: string | null;
  discount_amount: number | null;
  tax_amount: number | null;
  commission_rate: number | null;
  commissioned_user_id: string | null;
  commissioned_person: string | null;
  payment_condition_preset_id: string | null;
  payment_conditions: string | null;
  travel_cost_total: number | null;
  problem_description: string | null;
};

export const emReais = (v: number): string =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);

/**
 * Por que este orçamento não pode entrar no agrupamento (null = pode).
 *
 * A ordem importa: a origem de um agrupamento fica `cancelled` — "Já agrupado" diz mais que "Cancelado".
 * As outras recusas do banco (dinheiro/nota/compra ligados, repasse de taxa do cartão, total desatualizado)
 * não cabem nas colunas da lista e chegam como a frase do próprio banco ao tentar agrupar.
 */
export function motivoForaDoAgrupamento(
  c: Pick<CandidatoAgrupar, 'status' | 'quote_status' | 'signed_at' | 'converted_to_os_at' | 'merged_into_id'>,
): string | null {
  if (c.merged_into_id) return 'Já agrupado';
  if (c.converted_to_os_at) return 'Já virou OS';
  if (c.status === 'cancelled') return 'Cancelado';
  if (c.status !== 'draft') return 'Já virou OS';
  if (c.signed_at) return 'Assinado pelo cliente';
  if (c.quote_status === 'rejected') return 'Reprovado';
  return null;
}

const centavos = (v: number | null | undefined) => Math.round((Number(v) || 0) * 100);

/**
 * Soma dos totais em centavos (0,1 + 0,2 = 0,3, não 0,30000000000000004). É o `p_total_esperado`:
 * o banco compara com a soma que ele mesmo lê e recusa se alguém mexeu num orçamento com a tela aberta.
 */
export function somaDosTotais(cs: ReadonlyArray<Pick<CandidatoAgrupar, 'grand_total'>>): number {
  return cs.reduce((t, c) => t + centavos(c.grand_total), 0) / 100;
}

/** Um orçamento tem uma embarcação só: agrupar exige o mesmo cliente E a mesma embarcação. */
export function mesmoClienteEEmbarcacao(rows: ReadonlyArray<{ client_id: string; vessel_id: string }>): boolean {
  if (rows.length === 0) return true;
  const [primeiro] = rows;
  return rows.every((r) => r.client_id === primeiro!.client_id && r.vessel_id === primeiro!.vessel_id);
}

const porData = (cs: ReadonlyArray<CandidatoAgrupar>) =>
  [...cs].sort((a, b) => a.created_at.localeCompare(b.created_at) || a.id.localeCompare(b.id));

const texto = (s: string | null | undefined) => (s ?? '').trim().replace(/\s+/g, ' ');

const porcentagem = (v: number) => `${v.toLocaleString('pt-BR', { maximumFractionDigits: 2 })}%`;

function descreverComissao(c: CandidatoAgrupar): string {
  const taxa = Number(c.commission_rate) || 0;
  if (taxa <= 0) return `${c.service_order_number} sem comissão`;
  const quem = texto(c.commissioned_person);
  return `${c.service_order_number} ${porcentagem(taxa)}${quem ? ` (${quem})` : ''}`;
}

/**
 * Avisos do que muda ao juntar (frases prontas para a tela). Nada aqui impede o agrupamento, exceto o
 * deslocamento duplo, que o banco recusa — o aviso chega antes para o dono acertar o orçamento primeiro.
 */
export function diferencasEntreOrcamentos(cs: ReadonlyArray<CandidatoAgrupar>): string[] {
  const lista = porData(cs);
  if (lista.length < 2) return [];
  const avisos: string[] = [];

  const chaveComissao = (c: CandidatoAgrupar) =>
    [Number(c.commission_rate) || 0, c.commissioned_user_id ?? '', texto(c.commissioned_person).toLowerCase()].join('|');
  if (new Set(lista.map(chaveComissao)).size > 1) {
    avisos.push(
      `Comissões diferentes: ${lista.map(descreverComissao).join('; ')}. Vale a do principal, recalculada sobre o total novo.`,
    );
  }

  const chavePagamento = (c: CandidatoAgrupar) =>
    `${c.payment_condition_preset_id ?? ''}|${texto(c.payment_conditions).toLowerCase()}`;
  if (new Set(lista.map(chavePagamento)).size > 1) {
    avisos.push('Condições de pagamento diferentes entre os orçamentos. Vale a do principal.');
  }

  const comDesconto = lista.filter((c) => centavos(c.discount_amount) !== 0);
  if (comDesconto.length > 0) {
    const total = somaDosTotais(comDesconto.map((c) => ({ grand_total: c.discount_amount })));
    avisos.push(
      `Desconto no cabeçalho em ${comDesconto.map((c) => c.service_order_number).join(', ')}: no agrupado vira um desconto só de ${emReais(total)}, sobre o orçamento inteiro (não mais sobre os itens de cada um).`,
    );
  }

  const comImposto = lista.filter((c) => centavos(c.tax_amount) !== 0);
  if (comImposto.length > 0) {
    const total = somaDosTotais(comImposto.map((c) => ({ grand_total: c.tax_amount })));
    avisos.push(
      `Imposto no cabeçalho em ${comImposto.map((c) => c.service_order_number).join(', ')}: no agrupado vira um valor só de ${emReais(total)}, sobre o orçamento inteiro.`,
    );
  }

  const comDeslocamento = lista.filter((c) => centavos(c.travel_cost_total) !== 0);
  if (comDeslocamento.length > 1) {
    avisos.push(
      `Mais de um orçamento tem deslocamento (${comDeslocamento.map((c) => c.service_order_number).join(', ')}). Deixe o deslocamento em um só antes de agrupar, para não cobrar a viagem duas vezes.`,
    );
  }

  return avisos;
}

/**
 * A gravação foi recusada porque o orçamento mudou de papel em outra aba/por outra pessoa: foi agrupado
 * em outro (guarda da origem) ou já foi desagrupado (guarda do agrupado). As frases são as do banco
 * (migration 20261015180000); 42501 sozinho não basta — é também o código de qualquer falta de permissão.
 */
export function ehRecusaDeAgrupamento(e: unknown): boolean {
  const msg = String((e as { message?: unknown } | null)?.message ?? '');
  return msg.includes('foi agrupado em') || msg.includes('foi desagrupado');
}

/** O principal sugerido é o mais antigo (mesma ordem do banco: created_at, depois id). '' sem candidatos. */
export function principalPadrao(cs: ReadonlyArray<Pick<CandidatoAgrupar, 'id' | 'created_at'>>): string {
  let melhor: Pick<CandidatoAgrupar, 'id' | 'created_at'> | null = null;
  for (const c of cs) {
    if (!melhor || c.created_at < melhor.created_at || (c.created_at === melhor.created_at && c.id < melhor.id)) melhor = c;
  }
  return melhor?.id ?? '';
}
