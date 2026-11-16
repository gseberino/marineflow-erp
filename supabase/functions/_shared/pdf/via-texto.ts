// Limpeza de texto da via do técnico (porte da via v2, F1, 16/11/2026).
//
// Vem da bancada aprovada pelo dono (proposta/via-v2.ts e enxuta/R/conteudo.ts). Serve a três perguntas da via:
//   · que serviço é COBRANÇA (frete, deslocamento, insumos) e sai da lista de cartões (resposta 4A do dono)?
//   · que nota de material é recado interno do escritório e não vai ao papel (rodada 3, item j)?
//   · qual é o título curto de cada serviço e o pedido do cliente limpo (o quadro de Atenção lê os dois)?
//
// Na bancada, limparRuido e limparPedido também passavam o texto em CAIXA ALTA para frase (semCaixaAlta). Aqui não:
// o que este módulo devolve só é COMPARADO (sempre por `normalizar`, em minúsculas), nunca impresso — mudar só a caixa
// não muda nenhuma resposta.
//
// Puro (sem Deno, sem rede): a tela importa por src/lib/route-sheet.ts (Vite) e as edge functions pelo Deno.

/**
 * Tira do texto toda linha com valor em reais. A descrição da OS também vai para o
 * orçamento do cliente; se um dia alguém escrever condição de pagamento nela, o
 * técnico continua sem ver preço (decisão do dono, 12/08: preço não vai na via).
 */
export function semValores(texto: string | null | undefined): string {
  if (!texto) return '';
  return texto
    .split(/\r?\n/)
    .filter((linha) => !/R\$/i.test(linha))
    .join('\n')
    .trim();
}

/** Sem acento e em minúsculas — para comparar palavras inteiras com \b. */
export function normalizar(t: string | null | undefined): string {
  return (t ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
}

/**
 * Ruído de escritório que não é trabalho do técnico: valor provisório, cortesia, "sem custo", horas de
 * cobrança coladas no nome ("2,5 HH", "(1,5h)"), "ITEM ADICIONAL (identificado pela HBR)", "Justificativa: …",
 * "Mão de obra —"/"Mão de obra de" e "Serviço de" na frente do nome, "Fornecimento e instalação" → "Instalação".
 * Preço no nome: sai SÓ o trecho com R$ (semValores apagaria a linha inteira e o cartão ficaria sem nome).
 */
export function limparRuido(texto: string | null | undefined): string {
  const semPreco = (texto ?? '')
    // parêntese que fala de preço sai inteiro: "(R$ 1.200,00 a confirmar)"
    .replace(/\s*\([^()]*R\$[^()]*\)/gi, '')
    .replace(/\s*[—–-]?\s*\(?\s*R\$\s*[\d.]+(?:,\d{2})?\s*\)?(?:\s*(?:\/|por)\s*\w+)?/gi, '');
  let t = semValores(semPreco);
  if (!t) return '';
  t = t
    .replace(/\s*[—–-]\s*valor provis[óo]rio[^—–\n]*?(\(aguardando cota[çc][ãa]o\))?(?=$|\n)/gi, '')
    .replace(/\s*\(\s*valor a definir[^)]*\)/gi, '')
    .replace(/\s*\(?\s*aguardando cota[çc][ãa]o\s*\)?/gi, '')
    .replace(/\s*\(\s*cortesia\s*\)/gi, '')
    .replace(/\s*[—–-]\s*cortesia\b\.?/gi, '')
    .replace(/\s*[—–-]\s*sem custo\b\.?/gi, '')
    .replace(/\s*\(\s*ITEM ADICIONAL\s*[—–-]?\s*identificado pela HBR\s*\)/gi, '')
    .replace(/^\s*ITEM ADICIONAL\s*\(identificado pela HBR\)\s*[—–:-]\s*/gi, '')
    .replace(/\s*Justificativa:[^\n]*/gi, '')
    .replace(/[.,;]?\s*\d+(?:[.,]\d+)?\s*HH\b\.?/g, '')
    .replace(/\s*\(\s*\d+(?:[.,]\d+)?\s*h(?:\d+)?\s*\)/gi, '')
    .replace(/^\s*m[ãa]o de obra\s*[—–:-]\s*/i, '')
    .replace(/^\s*m[ãa]o de obra\s+(?:de|para)\s+/i, '')
    .replace(/^\s*servi[çc]o de\s+/i, '')
    .replace(/^\s*fornecimento e (instala[çc][ãa]o)\b/i, '$1')
    .replace(/\s+\./g, '.')
    .replace(/[ \t]{2,}/g, ' ')
    .trim();
  return t.charAt(0).toUpperCase() + t.slice(1);
}

/**
 * Título curto do serviço: corta no primeiro " — " / " – " / ": " / " - " com 12 letras ou mais antes (a regra da
 * ficha da agenda, _agenda_tarefa_texto); sem isso e com mais de 70 caracteres, corta no primeiro " (" ou na primeira
 * vírgula/ponto e vírgula depois de 25 caracteres. Um título que ainda passe de 70 é cortado de novo pela vírgula.
 * O resto começa sempre com " — " (o separador fica um só), com espaço inseparável antes.
 */
export function tituloCurto(nomeLimpo: string): { titulo: string; resto: string } {
  const nome = nomeLimpo.trim();
  const letras = (s: string) => s.replace(/[^A-Za-zÀ-ÿ]/g, '').length;
  const porVirgula = (s: string): number => {
    if (s.length <= 70) return -1;
    // Parêntese só quando é o fecho do nome ("… para a pintura (pintura e montagem …)"); "(quarto) e dianteiro (sala)" não.
    const p = s.indexOf(' (', 25);
    if (p > 0 && s.endsWith(')') && s.indexOf('(', p + 2) < 0) return p;
    const re = /[,;]\s/g;
    let m: RegExpExecArray | null;
    while ((m = re.exec(s))) if (m.index >= 25) return m.index;
    return -1;
  };
  const arrumar = (resto: string) => resto.replace(/^\s+[—–-]\s+/, '\u00a0— ');
  const sep = /\s[—–-]\s|:\s/g;
  let m: RegExpExecArray | null;
  while ((m = sep.exec(nome))) {
    const antes = nome.slice(0, m.index);
    if (letras(antes) >= 12) {
      const titulo = antes.trim();
      const resto = nome.slice(m.index);
      const k = porVirgula(titulo);
      if (k > 0) return { titulo: titulo.slice(0, k).trim(), resto: titulo.slice(k) + arrumar(resto) };
      return { titulo, resto: arrumar(resto) };
    }
  }
  const k = porVirgula(nome);
  if (k > 0) return { titulo: nome.slice(0, k).trim(), resto: nome.slice(k) };
  return { titulo: nome, resto: '' };
}

/** O título curto do serviço a partir do nome cru da linha (o do cartão da bancada; vazio vira "Serviço"). */
export function tituloDoServico(nome: string | null | undefined): string {
  return tituloCurto(limparRuido(nome) || 'Serviço').titulo || 'Serviço';
}

/**
 * Pedido do cliente limpo. Primeiro junta as linhas quebradas no meio da frase (sem colar item de lista "1)", "2."
 * ou "- "); DEPOIS tira, com a frase inteira: o cabeçalho de entrega ao cliente ("Descrição dos serviços executados"),
 * a cláusula de garantia ("a garantia limita-se…" — um pedido técnico que cita garantia fica), "sem cobrança" e o
 * "[OS-00100]" das fusões.
 */
export function limparPedido(texto: string | null | undefined): string {
  const t = semValores(texto).replace(/\[(OS|ORÇ|ORC)-\d+\]\s*/g, '');
  const juntas: string[] = [];
  for (const l of t.split(/\r?\n/).map((x) => x.trim())) {
    if (!l) { if (juntas.length && juntas[juntas.length - 1] !== '') juntas.push(''); continue; }
    const ant = juntas[juntas.length - 1];
    const item = /^(?:\d+\s*[.)]|[-•*–]\s)/.test(l);
    if (ant && !item && !/[.:!?)]$/.test(ant) && /^[a-zà-ÿ0-9(]/.test(l)) juntas[juntas.length - 1] = `${ant} ${l}`;
    else juntas.push(l);
  }
  return juntas
    .map((p) => p
      .replace(/^descri[çc][ãa]o dos servi[çc]os(?: executados| realizados)?:?$/i, '')
      .replace(/(?:observa[çc][ãa]o:\s*)?(?:a\s+)?garantia\s+(?:limita-se|se limita|cobre|n[ãa]o cobre|n[ãa]o se estende|[ée] de|[ée] v[áa]lida|vale)\b[^.]*\.?/gi, '')
      .replace(/,?\s*sem (?:cobran[çc]a|custo)\b/gi, '')
      .replace(/\s+\./g, '.')
      .trim())
    .filter((p, i, a) => p || (i > 0 && a[i - 1]))
    .join('\n').replace(/\n{2,}/g, '\n').trim();
}

/**
 * A nota do material que vai ao papel. Recado interno do sistema ("Cadastrado pelo orçamento — confirmar preço e
 * completar cadastro fiscal.", "Convertido de linha de serviço… Valor provisório") não vai: é do escritório, não do
 * técnico (rodada 3, item j). Linha com R$ também não (semValores). A nota escrita por gente continua.
 */
export function notaDoMaterial(nota: string | null | undefined): string | null {
  const t = semValores(nota);
  if (!t) return null;
  if (/cadastrado pelo or[çc]amento|confirmar pre[çc]o|cadastro fiscal|convertido de linha|valor provis[óo]rio|aguardando cota/i.test(t)) return null;
  return t;
}

/** Frete, deslocamento e insumos: palavra inteira, no título curto já sem acento e em minúsculas. */
export const COBRANCA = /\bfrete\b|\bdeslocamento\b|\binsumos?\b/;

/**
 * A linha é COBRANÇA (resposta 4A do dono, 15/11/2026): frete, deslocamento ou insumos no TÍTULO CURTO. Ela sai dos
 * cartões da via e da tela "Lançar a via", e os outros serviços mantêm o número. Só o título conta: "Retirada e
 * reinstalação do carregador — inclui frete de ida e volta" é serviço (o frete está depois do travessão).
 * A mesma regra roda no Postgres (F2, private._via_eh_cobranca) sobre a lista de casos de via-cobranca-casos.ts.
 */
export function ehCobranca(nome: string | null | undefined): boolean {
  return COBRANCA.test(normalizar(tituloDoServico(nome)));
}
