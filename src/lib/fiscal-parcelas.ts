/**
 * Parcelas de uma nota (duplicatas da NF-e e recebíveis da baixa da nota avulsa).
 *
 * Extraído de FiscalEmission.tsx (D33, 30/09/2026) para ter teste. A divisão antiga fazia
 * `Math.floor((total / n) * 100) / 100` em ponto flutuante e, em ~2,5% das combinações de valor
 * e número de parcelas, saía um centavo abaixo (R$ 1,14 em 2 → 0,56 + 0,58). Agora a conta é em
 * centavos inteiros: as N−1 primeiras levam o valor cheio e a última leva o resto.
 */

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
