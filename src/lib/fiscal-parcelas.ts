/**
 * Parcelas de uma nota (duplicatas da NF-e e recebíveis da baixa da nota avulsa).
 *
 * Extraído de FiscalEmission.tsx (D33, 30/09/2026) para ter teste. A divisão antiga fazia
 * `Math.floor((total / n) * 100) / 100` em ponto flutuante e, em ~2,5% das combinações de valor
 * e número de parcelas, saía um centavo abaixo (R$ 1,14 em 2 → 0,56 + 0,58). Agora a conta é em
 * centavos inteiros: as N−1 primeiras levam o valor cheio e a última leva o resto.
 */

import { dataDaNota } from './nota-fiscal-leitura';

export interface Parcela {
  due_date: string;
  amount: number;
  method: string;
}

/** Soma `dias` a uma data AAAA-MM-DD, em UTC (sem depender do fuso de quem roda). */
function somarDias(data: string, dias: number): string {
  const [a, m, d] = data.split('-').map(Number);
  return new Date(Date.UTC(a, m - 1, d + dias)).toISOString().slice(0, 10);
}

/**
 * Divide o total em N parcelas, a primeira vencendo em `primeiroVencimento` e as outras de
 * `intervaloDias` em `intervaloDias` dias. A última recebe o arredondamento, e a soma fecha exata.
 */
export function montarParcelas(
  total: number,
  n: number,
  primeiroVencimento: string,
  intervaloDias: number,
  metodo: string,
): Parcela[] {
  const centavos = Math.round(total * 100);
  const cheia = Math.floor(centavos / n);
  const parcelas: Parcela[] = [];
  for (let i = 0; i < n; i++) {
    const c = i === n - 1 ? centavos - cheia * (n - 1) : cheia;
    parcelas.push({ due_date: somarDias(primeiroVencimento, i * intervaloDias), amount: c / 100, method: metodo });
  }
  return parcelas;
}

/** Intervalo em dias entre as duas primeiras parcelas de um plano (mínimo 1). */
export function intervaloDasParcelas(parcelas: Array<{ due_date: string }>): number {
  if (parcelas.length < 2) return 30;
  const d0 = Date.parse(parcelas[0].due_date + 'T00:00:00Z');
  const d1 = Date.parse(parcelas[1].due_date + 'T00:00:00Z');
  return Math.max(1, Math.round((d1 - d0) / 86_400_000));
}

/** O plano com que o diálogo de baixa da nota avulsa abre. */
export interface PlanoDaBaixa {
  modo: 'avista' | 'parcelado';
  n: number;
  primeiroVencimento: string;
  intervaloDias: number;
  metodo: string;
  /** O plano que a PRÓPRIA NOTA declarou, palavra por palavra (null se não declarou). */
  parcelasDaNota: Parcela[] | null;
}

/**
 * Com que plano a baixa da nota avulsa começa.
 *
 * Nota parcelada: o plano dela, intacto. A reconstrução por N parcelas iguais só acerta
 * quando o plano é perfeitamente regular; na NF-e 2/25 a nota diz 5.237,99 / 5.237,99 /
 * 5.238,02 e a reconstrução dava 5.238,00 três vezes.
 *
 * Nota sem plano: à vista, com o vencimento na data da própria nota (o único ponto de partida
 * honesto; "hoje + 30" não vinha de lugar nenhum). A data é o dia LOCAL da nota: pela hora UTC,
 * a nota emitida depois das 21h sugeria o dia seguinte (corrigido no D33, 01/10/2026).
 */
export function planoInicialDaBaixa(doc: unknown, agora: Date = new Date()): PlanoDaBaixa {
  const d = doc as {
    payment_terms?: { mode?: string; method?: string; installments?: unknown } | null;
    request_payload?: { payments?: Array<{ method?: string }> } | null;
  } | null;
  const pt = d?.payment_terms;
  const inst = (Array.isArray(pt?.installments) ? pt!.installments : []) as Array<Record<string, unknown>>;
  const metodo = String(pt?.method || d?.request_payload?.payments?.[0]?.method || '15');

  if (pt?.mode === 'parcelado' && inst.length > 1) {
    const parcelasDaNota = inst.map((p) => ({
      due_date: String(p.due_date),
      amount: Number(p.amount),
      method: String(p.method || metodo),
    }));
    return {
      modo: 'parcelado', n: inst.length, primeiroVencimento: String(inst[0].due_date),
      intervaloDias: intervaloDasParcelas(parcelasDaNota), metodo, parcelasDaNota,
    };
  }

  const daNota = dataDaNota(doc);
  const base = daNota ? new Date(daNota) : agora;
  const dia = `${base.getFullYear()}-${String(base.getMonth() + 1).padStart(2, '0')}-${String(base.getDate()).padStart(2, '0')}`;
  return { modo: 'avista', n: 2, primeiroVencimento: dia, intervaloDias: 30, metodo, parcelasDaNota: null };
}

/**
 * As parcelas que serão lançadas de fato na baixa da nota avulsa.
 *
 * Enquanto o usuário não mexe em nada, vale o plano da nota, intacto. Assim que ele altera
 * parcelas, vencimento, intervalo ou forma de pagamento, a conta é refeita a partir do que ele
 * escolheu (e a tela avisa que diverge da nota). À vista → null (um recebível só).
 */
export function parcelasParaLancar(p: {
  modo: 'avista' | 'parcelado';
  ajustado: boolean;
  parcelasDaNota: Parcela[] | null;
  total: number;
  n: number;
  primeiroVencimento: string;
  intervaloDias: number;
  metodo: string;
}): Parcela[] | null {
  if (p.modo !== 'parcelado') return null;
  if (!p.ajustado && p.parcelasDaNota && p.parcelasDaNota.length > 0) return p.parcelasDaNota;
  if (p.n < 1 || !p.primeiroVencimento) return null;
  return montarParcelas(p.total, p.n, p.primeiroVencimento, p.intervaloDias, p.metodo);
}
