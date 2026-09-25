// Busca das telas do financeiro: uma caixa só que entende nome, CPF/CNPJ e valor.
//
// Quem procura uma linha do extrato procura do jeito que lembra dela: "coremma", "o Pix de
// 1.250", "aquele CNPJ 12.345.678". Obrigar a escolher antes em que campo buscar é o que faz
// a busca não ser usada. Por isso o mesmo texto é testado como nome, como documento (só os
// dígitos) e como valor (no formato brasileiro, com vírgula).

/** Minúsculo e sem acento: "Alimentação" acha "alimentacao" e vice-versa. */
export function normalizar(texto: string | null | undefined): string {
  return (texto ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();
}

/**
 * O valor que a pessoa digitou, se o texto for um valor: "150", "150,50", "1.250,00",
 * "R$ 50". Texto com letra não é valor — "OS-60" não pode virar 60.
 */
export function valorDigitado(termo: string): number | null {
  const t = termo.trim();
  if (!/^(r\$\s*)?[\d.,]+$/i.test(t)) return null;
  let limpo = t.replace(/^r\$\s*/i, '');
  // "1.250,00" ou "1250,5": vírgula é o decimal. "1.250" sem vírgula: ponto é milhar só
  // quando separa grupos de três ("1.250"); "12.5" é decimal.
  if (limpo.includes(',')) limpo = limpo.replace(/\./g, '').replace(',', '.');
  else if (/^\d{1,3}(\.\d{3})+$/.test(limpo)) limpo = limpo.replace(/\./g, '');
  const n = Number(limpo);
  return Number.isFinite(n) && n > 0 ? n : null;
}

export interface CriterioDeBusca {
  termo: string;
  /** ISO date, inclusive. */
  de?: string;
  ate?: string;
}

export interface AlvoDaBusca {
  textos: Array<string | null | undefined>;
  valores: Array<number | string | null | undefined>;
  data?: string | null;
}

/** Valor bate com folga de centavo ou 0,5% — o extrato arredonda, a nota nem sempre. */
function valorBate(alvo: number, procurado: number): boolean {
  return Math.abs(Math.abs(alvo) - procurado) <= Math.max(0.01, procurado * 0.005);
}

export function casaComBusca(alvo: AlvoDaBusca, c: CriterioDeBusca): boolean {
  const data = (alvo.data ?? '').slice(0, 10);
  if (c.de && (!data || data < c.de)) return false;
  if (c.ate && (!data || data > c.ate)) return false;

  const termo = c.termo.trim();
  if (!termo) return true;

  const t = normalizar(termo);
  if (alvo.textos.some((x) => normalizar(x).includes(t))) return true;

  // Documento: CPF e CNPJ chegam com e sem pontuação. Cinco dígitos já identificam.
  const digitos = termo.replace(/\D/g, '');
  if (digitos.length >= 5 && alvo.textos.some((x) => (x ?? '').replace(/\D/g, '').includes(digitos))) return true;

  const valor = valorDigitado(termo);
  if (valor != null && alvo.valores.some((v) => v != null && v !== '' && valorBate(Number(v), valor))) return true;

  return false;
}

export function buscaAtiva(c: CriterioDeBusca): boolean {
  return !!(c.termo.trim() || c.de || c.ate);
}
