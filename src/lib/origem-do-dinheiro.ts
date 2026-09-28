// De qual conta ou cartão da HBR o dinheiro saiu (pedido do dono, 28/09/2026).
//
// "Fatura de cartão" ou "Conta corrente" não diz ONDE conferir: a HBR tem conta no C6, no Nubank
// e na InfinitePay, cartões nos dois primeiros (o Nubank com vários virtuais) e o Caixa em
// dinheiro. Com o banco e o final do cartão, quem confere vai direto ao aplicativo certo.

export interface ContaDaHBR {
  label?: string | null;
  institution?: string | null;
  provider?: string | null;
}

export interface LinhaDeOrigem {
  source_type?: string | null;
  card_last_digits?: string | null;
}

/** Nomes de banco como o dono os chama (o rótulo da conexão vem como o cadastro deixou). */
const NOMES: Array<[RegExp, string]> = [
  [/^c6\b/i, 'C6'],
  [/^nu(bank|\s*pagamentos)?\b/i, 'Nubank'],
  [/^infinite\s*pay\b/i, 'InfinitePay'],
  [/^(banco\s+)?inter\b/i, 'Inter'],
  [/^ita[uú]\b/i, 'Itaú'],
  [/^bradesco\b/i, 'Bradesco'],
  [/^santander\b/i, 'Santander'],
  [/^(banco do brasil|bb)\b/i, 'Banco do Brasil'],
  [/^sicredi\b/i, 'Sicredi'],
  [/^sicoob\b/i, 'Sicoob'],
  [/^mercado\s*pago\b/i, 'Mercado Pago'],
];

/** "C6 - Conta PJ HBR" → "C6"; "Nubank PJ HBR" → "Nubank"; "Infinitepay PJ - HBR" → "InfinitePay". */
export function nomeDoBanco(conta: ContaDaHBR | null | undefined): string | null {
  const texto = String(conta?.label ?? conta?.institution ?? '').trim();
  if (!texto) return null;
  for (const [padrao, nome] of NOMES) if (padrao.test(texto)) return nome;
  // Desconhecido: a primeira palavra do rótulo, antes de " - " ou do espaço.
  return texto.split(/\s+-\s+|\s+/)[0] || null;
}

/**
 * "Conta C6", "Cartão Nubank final 4922", "Caixa (dinheiro)". Sem a conta (linha antiga,
 * importada à mão), só o tipo: "Conta corrente" / "Cartão de crédito". null sem linha do banco.
 */
export function origemDoDinheiro(
  linha: LinhaDeOrigem | null | undefined, conta?: ContaDaHBR | null,
): string | null {
  if (!linha) return null;
  const tipo = linha.source_type ?? 'bank';
  if (tipo === 'cash' || conta?.provider === 'caixa') return 'Caixa (dinheiro)';
  const banco = nomeDoBanco(conta);
  if (tipo === 'credit_card') {
    const final = String(linha.card_last_digits ?? '').replace(/\D/g, '').slice(-4);
    return `${banco ? `Cartão ${banco}` : 'Cartão de crédito'}${final ? ` final ${final}` : ''}`;
  }
  return banco ? `Conta ${banco}` : 'Conta corrente';
}
