// A ordem e o número das linhas de uma OS, e o achador de "serviço N" (porte da via do técnico v2, F0, 16/11/2026).
//
// Um lugar só para três perguntas que estavam espalhadas:
//   · em que ordem saem as linhas? `created_at`, depois `id` (a ordem que o banco já usa na agenda). Sem o `id`, as
//     linhas gravadas num INSERT só (o mesmo `now()`) saíam na ordem física, que um UPDATE troca;
//   · qual é o número do serviço? A posição na OS INTEIRA nessa ordem, contando as linhas de cobrança (regra 4A: a
//     cobrança sai do papel, mas o número dos outros fica). Quem lê ordena; `numerarLinhas` só numera;
//   · que linha o dono quis dizer com "o 4", "serviço 4", "nº 4", "o quarto", "LiFePO4"? `acharLinha`: id → número →
//     ordinal → nome igual → palavra inteira → começo de palavra. Mais de uma candidata = pergunta; nunca escolhe sozinho.
//
// Puro (sem Deno, sem banco): a tela importa daqui também. Os casos de teste moram em linhas-da-os-casos.ts, para a
// conta SQL da F2 (private._via_linhas_numeradas) rodar a MESMA lista.

/** O mínimo para ordenar uma linha. Sem `created_at` a linha vai para o fim (como NULLS LAST do Postgres). */
export interface LinhaOrdenavel {
  id?: string | null;
  created_at?: string | null;
}

const INSTANTE = /^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}:\d{2})(?:\.(\d+))?\s*(Z|[+-]\d{2}(?::?\d{2})?)?$/i;

/**
 * O instante como texto que ordena igual ao Postgres: segundos desde 1970 (12 dígitos) e a fração com 6 dígitos.
 * Nunca `Date.parse` no instante inteiro: ele corta os microssegundos e cria empate falso ("…:00.12" e "…:00.1201"
 * viram o mesmo milissegundo). O `Date.parse` aqui só lê os segundos, já com o fuso; a fração vem do texto.
 */
export function chaveDoInstante(ts: string | null | undefined): string | null {
  const m = INSTANTE.exec(String(ts ?? '').trim());
  if (!m) return null;
  const [, dia, hora, fracao = '', fusoBruto] = m;
  let fuso = (fusoBruto ?? 'Z').toUpperCase();
  if (fuso !== 'Z') {
    const digitos = fuso.slice(1).replace(':', '');
    fuso = `${fuso[0]}${digitos.slice(0, 2)}:${(digitos.slice(2) || '00').padEnd(2, '0')}`;
  }
  const ms = Date.parse(`${dia}T${hora}${fuso}`);
  if (Number.isNaN(ms)) return null;
  const segundos = Math.floor(ms / 1000);
  return `${String(segundos).padStart(12, '0')}.${(fracao + '000000').slice(0, 6)}`;
}

/** A comparação de `ordenarLinhas`: `created_at` (nulo por último), depois `id` em minúsculas (= ordem de bytes do uuid). */
export function compararLinhas(a: LinhaOrdenavel, b: LinhaOrdenavel): number {
  const ka = chaveDoInstante(a.created_at);
  const kb = chaveDoInstante(b.created_at);
  if (ka !== kb) {
    if (ka === null) return 1;
    if (kb === null) return -1;
    return ka < kb ? -1 : 1;
  }
  const ia = String(a.id ?? '').toLowerCase();
  const ib = String(b.id ?? '').toLowerCase();
  return ia < ib ? -1 : ia > ib ? 1 : 0;
}

/** As linhas na ordem canônica (`created_at, id`). Devolve uma cópia; empate total mantém a ordem recebida. */
export function ordenarLinhas<T extends LinhaOrdenavel>(linhas: readonly T[]): T[] {
  return [...linhas].sort(compararLinhas);
}

/** Põe o número do serviço (1, 2, 3…) na ordem RECEBIDA — não reordena: quem lê do banco já ordenou. */
export function numerarLinhas<T>(linhas: readonly T[]): Array<T & { numero: number }> {
  return linhas.map((l, i) => ({ ...l, numero: i + 1 }));
}

/**
 * `n` instantes em sequência depois de `base` (base + 1 ms, base + 2 ms…), para gravar várias linhas num INSERT só
 * sem empatar (o precedente é `_agrupar_os_montar`: `v_ts + interval '1 millisecond'`). `base` = o `created_at` da OS
 * que o banco devolveu; sem ele, o relógio de quem grava.
 */
export function instantesEmSequencia(base: string | null | undefined, n: number, agora: () => number = Date.now): string[] {
  const ms = base ? Date.parse(String(base)) : NaN;
  const inicio = Number.isNaN(ms) ? agora() : ms;
  return Array.from({ length: n }, (_, i) => new Date(inicio + i + 1).toISOString());
}

// ═══ "Serviço N": o que foi dito → a linha ═════════════════════════════════════════════════════════

/** Minúsculas, sem acento, espaços simples. */
export function semAcento(s: unknown): string {
  return String(s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/_/g, ' ')
    .replace(/\s+/g, ' ').trim();
}

/**
 * O número, quando o texto INTEIRO é uma referência a número: "4", "o 4", "serviço 4", "serviço número 4", "nº 4",
 * "n° 4", "no 4", "4º", "#4", "item 4", "linha 4". "LiFePO4", "bateria 200 Ah" e "220V" não são número.
 * Outra grafia do mesmo número também é número: "serviço #4", "o serviço #4", "item #4", "No. 4", "(4)", "4️⃣" —
 * tirando as palavras vazias, "serviço/item/linha" e "n/nr/num/número", sobra UM número só. Sem isso o texto caía no
 * caminho do nome como a palavra "4" e casava com "Cabo flexível 4 mm" (revisão da F0, achador-1).
 */
export function numeroDito(texto: unknown): number | null {
  const t = semAcento(texto).replace(/[.?!,;:]+$/, '').trim();
  const m = /^(?:(?:o|a)\s+)?(?:servico|serv\.?|item|linha|n[º°o.]?|numero|#)?\s*(?:numero|n[º°o.])?\s*(\d{1,3})\s*[º°ª]?$/.exec(t);
  if (m) return Number(m[1]);
  const resto = palavrasDitas(texto).filter((p) => !/^(n|no|nr|num|numero|servico|serv|item|linha)$/.test(p));
  return resto.length === 1 && /^\d{1,3}$/.test(resto[0]) ? Number(resto[0]) : null;
}

/** Só números ("4", "4 e 5", "1000")? Número solto nunca casa nome por palavra: "4" não acha "Cabo flexível 4 mm". */
function soNumeros(ditas: readonly string[]): boolean {
  return ditas.every((p) => /^\d+$/.test(p));
}

/** Os ordinais por extenso, sem acento, no masculino ("quarta" vira "quarto" antes de procurar). */
export const ORDINAIS = ['primeiro', 'segundo', 'terceiro', 'quarto', 'quinto', 'sexto', 'setimo', 'oitavo', 'nono', 'decimo'];

/**
 * O número, quando o texto INTEIRO é um ordinal por extenso: "o quarto", "quarta", "o quarto serviço", "a segunda
 * linha". Fica de fora do numeroDito de propósito: "quarto" também é cômodo ("Ar-condicionado do quarto") e "segundo"
 * é palavra comum — quem chama decide quando perguntar (revisão da F0, achador-2).
 */
export function ordinalDito(texto: unknown): number | null {
  const resto = palavrasDitas(texto).filter((p) => !/^(servico|serv|item|linha)$/.test(p));
  if (resto.length !== 1) return null;
  const i = ORDINAIS.indexOf(resto[0].replace(/a$/, 'o'));
  return i >= 0 ? i + 1 : null;
}

/** As palavras que não identificam serviço nenhum (as mesmas do acharServico antigo). */
const PALAVRAS_VAZIAS = new Set(['de', 'do', 'da', 'dos', 'das', 'o', 'a', 'os', 'as', 'e', 'em', 'no', 'na', 'com', 'para', 'pra', 'um', 'uma']);

/** Palavras de um texto: separadas por tudo o que não é letra ou número ("DC-DC" → dc, dc). */
function palavras(texto: unknown): string[] {
  return semAcento(texto).split(/[^a-z0-9]+/).filter(Boolean);
}

/**
 * As palavras do que foi dito, sem as vazias e sem o "serviço"/"item"/"linha" do começo ("serviço do inversor"). As
 * vazias saem PRIMEIRO: com artigo na frente ("o serviço do inversor") o "serviço" também sai — antes ele ficava e
 * passava a ser exigido no nome (revisão da F0, achador-4).
 */
function palavrasDitas(texto: unknown): string[] {
  const sem = palavras(texto).filter((p) => !PALAVRAS_VAZIAS.has(p));
  return /^(servico|serv|item|linha)$/.test(sem[0] ?? '') && sem.length > 1 ? sem.slice(1) : sem;
}

/**
 * Todas as palavras ditas (sem as vazias) são palavras INTEIRAS do nome? "DC-DC" casa com "conversor DC-DC"; "4" não
 * casa com "LiFePO4"; "do" sozinho não casa com nada; só número ("4", "4 e 5") não casa com nada ("cabo 4" casa com
 * "Cabo 4 mm"). É a troca do `includes` (pedaço de texto) nas tools.
 */
export function temAsPalavras(nome: unknown, dito: unknown): boolean {
  const ditas = palavrasDitas(dito);
  if (!ditas.length || soNumeros(ditas)) return false;
  const doNome = new Set(palavras(nome));
  return ditas.every((p) => doNome.has(p));
}

/**
 * Toda palavra dita está no nome inteira ou, com 4 letras ou mais, é COMEÇO de uma palavra do nome ("parametriz" acha
 * "Parametrização"; "abraçadeira" acha "Abraçadeiras nylon"). Só número nunca casa. É o último passo do acharLinha; em
 * remover/editar item só SUGERE na pergunta — nunca executa por ele (revisão da F0, achador-3).
 */
export function comecaComAsPalavras(nome: unknown, dito: unknown): boolean {
  const ditas = palavrasDitas(dito);
  if (!ditas.length || soNumeros(ditas)) return false;
  const doNome = palavras(nome);
  return ditas.every((p) => doNome.includes(p) || (p.length >= 4 && doNome.some((w) => w.startsWith(p))));
}

/**
 * O nome tem o ordinal `n` como palavra ("quarto", "quarta") ou como começo de palavra ("quartos")? É o cômodo que "o
 * quarto" também pode querer dizer. O mesmo critério do caminho do nome (comecaComAsPalavras): só a palavra inteira
 * deixava "Ar-condicionado dos quartos" de fora, e o ordinal escolhia calado o serviço 4 (revisão final, c-3).
 */
export function temOOrdinalNoNome(nome: unknown, n: number): boolean {
  const ordinal = ORDINAIS[n - 1];
  if (!ordinal) return false;
  return [ordinal, ordinal.replace(/o$/, 'a')].some((forma) => comecaComAsPalavras(nome, forma));
}

/**
 * A 1ª palavra dita (sem as vazias) é "linha" e o nome NÃO tem a palavra "linha"? O palavrasDitas tira o "linha" do
 * começo como rótulo ("a linha do LED" acha "Fita LED externa"), mas em peça e serviço náutico "linha" é substantivo
 * (linha de combustível, linha d'água, linha de ancoragem): sem ele, "combustível" sozinho acha o "Filtro de
 * combustível". Remover/editar item usa isto para PERGUNTAR em vez de executar (revisão final, c-2).
 */
export function linhaDitaForaDoNome(nome: unknown, dito: unknown): boolean {
  const ditas = palavras(dito).filter((p) => !PALAVRAS_VAZIAS.has(p));
  return ditas[0] === 'linha' && !palavras(nome).includes('linha');
}

/** Uma linha numerada, com o nome como sai no papel. */
export interface LinhaNumerada {
  id: string;
  numero: number;
  nome: string;
}

/** "3 · Troca do inversor". */
export function rotuloDaLinha(l: { numero: number; nome: string }): string {
  return `${l.numero} · ${l.nome}`;
}

/** "1 · Instalação; 2 · Troca…" — a lista que acompanha toda pergunta. */
export function listaDasLinhas(linhas: ReadonlyArray<{ numero: number; nome: string }>): string {
  return linhas.map(rotuloDaLinha).join('; ');
}

export type Achado<T> =
  | { linha: T }
  | { motivo: 'ambiguo'; opcoes: T[]; erro: string }
  | { motivo: 'fora_da_faixa' | 'nao_achei'; erro: string };

/**
 * A linha que o dono quis dizer. `linhas` já na ordem canônica e numeradas (`numerarLinhas`). Ordem de busca:
 * id exato → número dito → ordinal por extenso ("o quarto") → rótulo "N · nome" (número E nome batem) → nome igual →
 * todas as palavras ditas são palavras inteiras do nome → começo de palavra (≥ 4 letras: "parametriz" acha
 * "Parametrização"). Mais de uma candidata em qualquer passo = pergunta.
 */
export function acharLinha<T extends LinhaNumerada>(linhas: readonly T[], dito: unknown): Achado<T> {
  const bruto = String(dito ?? '').trim();
  const lista = listaDasLinhas(linhas);
  const naoAchei = { motivo: 'nao_achei' as const, erro: `Não achei o serviço "${bruto}" nesta OS. Serviços: ${lista || 'nenhum'}.` };
  if (!bruto) return naoAchei;
  const porId = linhas.find((l) => l.id === bruto);
  if (porId) return { linha: porId };

  const total = linhas.length;
  const foraDaFaixa = (n: number) => ({
    motivo: 'fora_da_faixa' as const,
    erro: `A OS tem ${total} serviço${total === 1 ? '' : 's'}; não existe o ${n}. Serviços: ${lista || 'nenhum'}.`,
  });
  const n = numeroDito(bruto);
  if (n !== null) {
    const l = linhas.find((x) => x.numero === n);
    if (l) return { linha: l };
    return foraDaFaixa(n);
  }

  // "o quarto", "a segunda" (ordinal por extenso) é o número — mas se a palavra também está no nome de outra linha
  // ("Ar-condicionado do quarto", "… dos quartos"), pergunta: nunca escolhe entre o 4º e o cômodo (revisão da F0,
  // achador-2; o plural pelo começo de palavra, revisão final c-3).
  const ord = ordinalDito(bruto);
  if (ord !== null) {
    const porNumero = linhas.find((x) => x.numero === ord);
    const porNome = linhas.filter((l) => l !== porNumero && temOOrdinalNoNome(l.nome, ord));
    if (!porNome.length) return porNumero ? { linha: porNumero } : foraDaFaixa(ord);
    return {
      motivo: 'ambiguo',
      opcoes: porNumero ? [porNumero, ...porNome] : porNome,
      erro: `"${bruto}" pode ser o serviço ${ord} (${porNumero ? rotuloDaLinha(porNumero) : `a OS tem ${total}`}) ou o que tem ` +
        `"${ORDINAIS[ord - 1]}" no nome: ${listaDasLinhas(porNome)}. Use o número.`,
    };
  }

  const escolher = (todas: T[]): Achado<T> | null => {
    // "a linha d'água", "a linha de combustível" (NOVO-via-10, decidido com a F2 em 20/11/2026): dita na frente, "linha"
    // pode ser rótulo ("a linha do LED") ou substantivo náutico. Fica quem tem "linha" no nome; se ninguém tem, pergunta
    // — nunca marca calado a "Troca da bomba d'água" por "a linha d'água".
    const candidatas = todas.filter((l) => !linhaDitaForaDoNome(l.nome, bruto));
    if (todas.length && !candidatas.length) {
      return {
        motivo: 'ambiguo',
        opcoes: todas,
        erro: `"${bruto}" pode ser ${listaDasLinhas(todas)}, mas "linha" não está no nome. Use o número.`,
      };
    }
    if (candidatas.length === 1) return { linha: candidatas[0] };
    if (candidatas.length > 1) {
      return {
        motivo: 'ambiguo',
        opcoes: candidatas,
        erro: `"${bruto}" casa com mais de um serviço: ${listaDasLinhas(candidatas)}. Use o número.`,
      };
    }
    return null;
  };

  // O rótulo que as próprias perguntas mostram ("4 · Fita LED externa", "4 - Fita LED externa"), copiado de volta: vale
  // só se o nome bate com a linha 4; senão segue o caminho normal, que pergunta (revisão da F0, achador-4).
  const rotulo = /^(\d{1,3})\s*[·.:\-–—]\s*(.+)$/.exec(bruto);
  if (rotulo) {
    const l = linhas.find((x) => x.numero === Number(rotulo[1]));
    if (l && semAcento(l.nome) === semAcento(rotulo[2])) return { linha: l };
  }

  const alvo = semAcento(bruto);
  const iguais = escolher(linhas.filter((l) => semAcento(l.nome) === alvo));
  if (iguais) return iguais;

  const ditas = palavrasDitas(bruto);
  if (!ditas.length || soNumeros(ditas)) return naoAchei;
  const inteiras = escolher(linhas.filter((l) => temAsPalavras(l.nome, bruto)));
  if (inteiras) return inteiras;

  const comeco = escolher(linhas.filter((l) => comecaComAsPalavras(l.nome, bruto)));
  if (comeco) return comeco;
  return naoAchei;
}
