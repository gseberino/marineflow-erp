// Quanto cada favorecido recebeu no ano (27/09/2026).
//
// A tela de Favorecidos mostrava só o cadastro. A pergunta que se faz sobre uma pessoa é
// "quanto paguei a ela este ano?" — o pró-labore e a retirada do sócio, o que o diarista
// levou, o que vai para o informe de rendimentos. Conta a pagar não tem data de pagamento
// própria: quando veio do extrato (todas as de favorecido, hoje), a data do lançamento É a
// data do banco. Por isso o ano é pelo lançamento. Cancelado não conta.

export interface LancamentoDoFavorecido {
  payee_id: string | null;
  amount: number | string | null;
  paid_amount: number | string | null;
  status: string | null;
  expense_category: string | null;
}

export interface TotalDoFavorecido {
  pago: number;
  aPagar: number;
  /** Lançamentos com algum valor pago. */
  pagamentos: number;
  /** O pago por categoria, do maior para o menor: pró-labore, retirada e reembolso separados. */
  porCategoria: Array<{ categoria: string; valor: number }>;
}

const centavos = (v: unknown) => Math.round((Number(v) || 0) * 100);

export function totaisPorFavorecido(linhas: LancamentoDoFavorecido[]): Map<string, TotalDoFavorecido> {
  const soma = new Map<string, { pago: number; aPagar: number; pagamentos: number; categorias: Map<string, number> }>();
  for (const l of linhas) {
    if (!l.payee_id || l.status === 'cancelled') continue;
    const valor = centavos(l.amount);
    if (valor <= 0) continue;
    // "paid" é pago inteiro; nos outros vale o que já foi pago, nunca mais que o valor.
    const pago = l.status === 'paid' ? valor : Math.min(valor, Math.max(0, centavos(l.paid_amount)));
    const t = soma.get(l.payee_id) ?? { pago: 0, aPagar: 0, pagamentos: 0, categorias: new Map<string, number>() };
    t.pago += pago;
    t.aPagar += valor - pago;
    if (pago > 0) {
      t.pagamentos += 1;
      const categoria = l.expense_category?.trim() || 'Sem categoria';
      t.categorias.set(categoria, (t.categorias.get(categoria) ?? 0) + pago);
    }
    soma.set(l.payee_id, t);
  }
  return new Map([...soma].map(([id, t]) => [id, {
    pago: t.pago / 100,
    aPagar: t.aPagar / 100,
    pagamentos: t.pagamentos,
    porCategoria: [...t.categorias]
      .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
      .map(([categoria, v]) => ({ categoria, valor: v / 100 })),
  }]));
}

/** O total dos favorecidos em tela (a aba escolhida), para a linha de resumo. */
export function somaDosFavorecidos(ids: string[], totais: Map<string, TotalDoFavorecido>) {
  let pago = 0;
  let aPagar = 0;
  let pagamentos = 0;
  for (const id of ids) {
    const t = totais.get(id);
    if (!t) continue;
    pago += centavos(t.pago);
    aPagar += centavos(t.aPagar);
    pagamentos += t.pagamentos;
  }
  return { pago: pago / 100, aPagar: aPagar / 100, pagamentos };
}
