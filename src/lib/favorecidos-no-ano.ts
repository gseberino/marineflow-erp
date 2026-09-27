// Quanto cada favorecido recebeu no ano (27/09/2026).
//
// A tela de Favorecidos mostrava só o cadastro. A pergunta que se faz sobre uma pessoa é
// "quanto paguei a ela este ano?" — o pró-labore e a retirada do sócio, o que o diarista
// levou, o que vai para o informe de rendimentos. Conta a pagar não tem data de pagamento
// própria: quando veio do extrato (todas as de favorecido, hoje), a data do lançamento É a
// data do banco. Por isso o ano é pelo lançamento. Cancelado não conta.
//
// Quem recebeu: o favorecido ligado ao lançamento — e, sem ele, o do MESMO CPF/CNPJ (documento
// igual identifica, regra do dono): primeiro o da linha do banco, para onde o dinheiro foi; depois
// o do fornecedor ligado. Na revisão de 27/09/2026 o sócio aparecia com R$ 26,7 mil em 2026 e
// tinha recebido R$ 40,2 mil: 26 pró-labores estavam no cadastro de FORNECEDOR com o CPF dele.
// O que entra pelo documento aparece separado, com o fornecedor em que foi lançado — é também o
// jeito de achar lançamento no cadastro errado (2 pagamentos ao CPF do Mickael em "VIA S.A.").

export interface LancamentoDoFavorecido {
  payee_id: string | null;
  amount: number | string | null;
  paid_amount: number | string | null;
  status: string | null;
  expense_category: string | null;
  /** CPF/CNPJ na linha do banco (para quem o dinheiro foi). */
  documento_da_linha?: string | null;
  /** CPF/CNPJ e nome do fornecedor ligado ao lançamento. */
  documento_do_fornecedor?: string | null;
  nome_do_fornecedor?: string | null;
}

export interface FavorecidoComDocumento {
  id: string;
  document: string | null;
}

export interface TotalDoFavorecido {
  pago: number;
  aPagar: number;
  /** Lançamentos com algum valor pago. */
  pagamentos: number;
  /** O pago por categoria, do maior para o menor: pró-labore, retirada e reembolso separados. */
  porCategoria: Array<{ categoria: string; valor: number }>;
  /** O que entrou pelo CPF/CNPJ, sem o favorecido ligado — por onde foi lançado. */
  peloDocumento: Array<{ lancadoEm: string; lancamentos: number; valor: number }>;
}

const centavos = (v: unknown) => Math.round((Number(v) || 0) * 100);

/** Só os dígitos, com o zero à esquerda que planilha costuma comer (como _doc_normalizado). */
export function documentoNormalizado(p: unknown): string {
  const d = String(p ?? '').replace(/\D/g, '');
  return d.length === 13 ? d.padStart(14, '0') : d.length === 10 ? d.padStart(11, '0') : d;
}

export function totaisPorFavorecido(
  linhas: LancamentoDoFavorecido[], favorecidos: FavorecidoComDocumento[] = [],
): Map<string, TotalDoFavorecido> {
  // Documento de UM favorecido só: dois com o mesmo documento é dúvida, e dúvida não soma.
  const donos = new Map<string, string[]>();
  for (const f of favorecidos) {
    const d = documentoNormalizado(f.document);
    if (d.length === 11 || d.length === 14) donos.set(d, [...(donos.get(d) ?? []), f.id]);
  }
  const doDocumento = (doc: unknown) => {
    const ids = donos.get(documentoNormalizado(doc));
    return ids && ids.length === 1 ? ids[0] : null;
  };

  const soma = new Map<string, {
    pago: number; aPagar: number; pagamentos: number; categorias: Map<string, number>;
    documento: Map<string, { lancamentos: number; valor: number }>;
  }>();
  for (const l of linhas) {
    if (l.status === 'cancelled') continue;
    const valor = centavos(l.amount);
    if (valor <= 0) continue;
    let id = l.payee_id;
    let lancadoEm: string | null = null;
    if (!id) {
      const pelaLinha = doDocumento(l.documento_da_linha);
      id = pelaLinha ?? doDocumento(l.documento_do_fornecedor);
      if (!id) continue;
      lancadoEm = l.nome_do_fornecedor?.trim() || 'sem cadastro ligado';
    }
    // "paid" é pago inteiro; nos outros vale o que já foi pago, nunca mais que o valor.
    const pago = l.status === 'paid' ? valor : Math.min(valor, Math.max(0, centavos(l.paid_amount)));
    const t = soma.get(id) ?? {
      pago: 0, aPagar: 0, pagamentos: 0, categorias: new Map<string, number>(),
      documento: new Map<string, { lancamentos: number; valor: number }>(),
    };
    t.pago += pago;
    t.aPagar += valor - pago;
    if (pago > 0) {
      t.pagamentos += 1;
      const categoria = l.expense_category?.trim() || 'Sem categoria';
      t.categorias.set(categoria, (t.categorias.get(categoria) ?? 0) + pago);
    }
    if (lancadoEm) {
      const d = t.documento.get(lancadoEm) ?? { lancamentos: 0, valor: 0 };
      d.lancamentos += 1;
      d.valor += valor;
      t.documento.set(lancadoEm, d);
    }
    soma.set(id, t);
  }
  return new Map([...soma].map(([id, t]) => [id, {
    pago: t.pago / 100,
    aPagar: t.aPagar / 100,
    pagamentos: t.pagamentos,
    porCategoria: [...t.categorias]
      .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
      .map(([categoria, v]) => ({ categoria, valor: v / 100 })),
    peloDocumento: [...t.documento]
      .sort((a, b) => b[1].valor - a[1].valor || a[0].localeCompare(b[0]))
      .map(([lancadoEm, d]) => ({ lancadoEm, lancamentos: d.lancamentos, valor: d.valor / 100 })),
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
