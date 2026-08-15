/**
 * Grandeza medida em campo: número, unidade e o que é plausível.
 *
 * ═══ POR QUE ISTO EXISTE ═══
 *
 * A resposta da distância no ORÇ-00074 veio assim:
 *
 *   "entre o banco e o inversor... 2,5 metros. E até o quadro é de 2 metros"
 *
 * O motor leu 2,5, ignorou o resto e dimensionou cabo para metade do percurso.
 * A pergunta pedia dois trechos e tinha um campo só — isso foi corrigido
 * desdobrando a pergunta. Este arquivo cuida da outra metade: o número passa a
 * ser gravado como número, com a unidade ao lado, em vez de ser garimpado no
 * meio da frase toda vez que alguém precisar dele.
 *
 * O TEXTO CONTINUA. É ele que carrega o contexto — "2,5 medido por cima do
 * forro" diz algo que o número não diz. Trocar um pelo outro seria perder
 * informação para ganhar conveniência; aqui os dois convivem.
 */

/** O que se conclui de uma resposta de grandeza. */
export interface MeasureCheck {
  /** O número extraído, se houver um só. */
  value: number | null;
  /** Quantos números a resposta contém — mais de um é sinal de pergunta mal feita. */
  numberCount: number;
  /** Aviso para quem está preenchendo. Nunca bloqueia. */
  warning: string | null;
}

/** Todos os números de um texto, aceitando vírgula decimal. */
export function extractNumbers(text: string | null | undefined): number[] {
  if (!text) return [];
  const limpo = String(text).replace(/,/g, '.');
  const achados = limpo.match(/-?\d+\.?\d*/g) || [];
  return achados.map(Number).filter((n) => Number.isFinite(n));
}

/**
 * Confere a resposta contra a unidade e a faixa esperadas.
 *
 * AVISA, NUNCA BARRA. Faixa que impede leitura correta é pior que faixa
 * nenhuma: o mundo real tem exceção, quem está no local vê o que o cadastro não
 * previu, e um alerta que impede vira alerta que se aprende a ignorar.
 */
export function checkMeasure(
  raw: string | number | null | undefined,
  opts: { unit?: string | null; min?: number | null; max?: number | null } = {},
): MeasureCheck {
  const texto = raw === null || raw === undefined ? '' : String(raw);
  const numeros = typeof raw === 'number' ? [raw] : extractNumbers(texto);

  if (numeros.length === 0) {
    return {
      value: null,
      numberCount: 0,
      warning: texto.trim() ? 'Não encontrei um número nesta resposta.' : null,
    };
  }

  // Mais de um número: quase sempre a pergunta pediu duas coisas. Somar por
  // conta própria seria pior — podem ser alternativas ("2,5 ou 3"), trechos a
  // somar, ou um valor com tolerância.
  if (numeros.length > 1) {
    return {
      value: numeros[0],
      numberCount: numeros.length,
      warning:
        `Encontrei ${numeros.length} números (${numeros.join(', ')}). ` +
        `Vou usar ${numeros[0]} — se forem trechos a somar, escreva o total.`,
    };
  }

  const valor = numeros[0];
  const { min, max, unit } = opts;

  if (min !== null && min !== undefined && valor < min) {
    return {
      value: valor,
      numberCount: 1,
      warning:
        `${valor}${unit ? ' ' + unit : ''} está abaixo do que se costuma ver ` +
        `(a partir de ${min}${unit ? ' ' + unit : ''}). Confira a vírgula e a unidade.`,
    };
  }

  if (max !== null && max !== undefined && valor > max) {
    return {
      value: valor,
      numberCount: 1,
      warning:
        `${valor}${unit ? ' ' + unit : ''} está acima do que se costuma ver ` +
        `(até ${max}${unit ? ' ' + unit : ''}). Confira a vírgula e a unidade.`,
    };
  }

  return { value: valor, numberCount: 1, warning: null };
}
