/**
 * A mensagem que a TELA manda ao cliente pelo "Enviar via WhatsApp": a abertura (saudação), o
 * corpo padrão e o que acontece com o link online.
 *
 * POR QUE ISTO EXISTE (pedido do dono, 20/10/2026): "não é necessário enviar o link para o
 * cliente, mesmo que eu deselecione a opção de enviar o link na interface do sistema, o link
 * acaba sendo enviado". Três caminhos levavam o link sem ele pedir:
 *  1. o diálogo abria no modo Link;
 *  2. o Resumo viajava como 'link' — a Evolution cola a URL no fim do texto (15/10, 15:37: um
 *     resumo de valores saiu com o /view/… no fim);
 *  3. os modelos do banco trazem {link} no texto ("Acesso: {link}") — a URL entrava no corpo
 *     mesmo com a caixa desmarcada.
 * Agora o link só vai quando a caixa "Enviar também o link online" está marcada (ou quando ele
 * escolhe o modo Link, que é mandar SÓ o link). É a mesma decisão de 05/10/2026 do assistente
 * (supabase/functions/_shared/ai/tools/whatsapp.ts, FORMATO_PADRAO = 'pdf'): o padrão é o
 * arquivo, sem link.
 *
 * E a saudação: "na grande maioria das vezes, eu estou conversando já com o cliente e mando
 * uma mensagem rápida ou um áudio explicando" — o padrão é SEM saudação; "Olá" e "Bom dia/Boa
 * tarde/Boa noite" ficam a um clique.
 *
 * Funções puras: nada aqui envia nem lê a tela. O diálogo monta, mostra e só então envia.
 */

// ─── Saudação ────────────────────────────────────────────────────────────────

export type Saudacao = 'nenhuma' | 'ola' | 'periodo';

export const SAUDACAO_PADRAO: Saudacao = 'nenhuma';

/** Onde a tela lembra a última escolha de saudação de quem está usando. */
export const CHAVE_DA_SAUDACAO = 'wa.saudacao';

export function ehSaudacao(v: unknown): v is Saudacao {
  return v === 'nenhuma' || v === 'ola' || v === 'periodo';
}

/**
 * Só o primeiro nome — a mensagem é conversa, não ofício. Nome todo em maiúsculas ("ROBSON",
 * como vários cadastros estão) sai "Robson": "Boa tarde, ROBSON!" parece grito.
 */
export function primeiroNome(nome?: string | null): string {
  const primeiro = (nome || '').trim().split(/\s+/)[0] || '';
  // "Nelson - S.I. 7.8" → "Nelson"; um nome que é só sinal ou número não é nome.
  if (!/\p{L}/u.test(primeiro)) return '';
  if (primeiro.length > 1 && primeiro === primeiro.toLocaleUpperCase('pt-BR')) {
    return primeiro.charAt(0) + primeiro.slice(1).toLocaleLowerCase('pt-BR');
  }
  return primeiro;
}

/** A hora em Brasília (0–23), qualquer que seja o fuso do computador de quem envia. */
export function horaEmBrasilia(agora: Date): number {
  const hora = new Intl.DateTimeFormat('pt-BR', {
    timeZone: 'America/Sao_Paulo',
    hour: 'numeric',
    hourCycle: 'h23',
  }).format(agora);
  return Number(hora) % 24;
}

/** Até 12h bom dia, até 18h boa tarde, depois boa noite — no horário de Brasília. */
export function periodoDoDia(agora: Date): 'Bom dia' | 'Boa tarde' | 'Boa noite' {
  const h = horaEmBrasilia(agora);
  if (h < 12) return 'Bom dia';
  if (h < 18) return 'Boa tarde';
  return 'Boa noite';
}

/**
 * O texto da abertura: '' (sem saudação), "Olá, Sandro!" ou "Boa tarde, Sandro!". Sem nome no
 * cadastro: "Olá!" / "Boa tarde!".
 */
export function textoDaSaudacao(saudacao: Saudacao, nomeDoCliente: string | null | undefined, agora: Date): string {
  if (saudacao === 'nenhuma') return '';
  const nome = primeiroNome(nomeDoCliente);
  const palavra = saudacao === 'ola' ? 'Olá' : periodoDoDia(agora);
  return nome ? `${palavra}, ${nome}!` : `${palavra}!`;
}

/** Os itens do campo "Saudação", já com o nome do cliente e o período de agora. */
export function opcoesDeSaudacao(nomeDoCliente: string | null | undefined, agora: Date): Array<{ value: Saudacao; label: string }> {
  return [
    { value: 'nenhuma', label: 'Sem saudação' },
    { value: 'ola', label: textoDaSaudacao('ola', nomeDoCliente, agora) },
    { value: 'periodo', label: `${textoDaSaudacao('periodo', nomeDoCliente, agora)} (pelo horário)` },
  ];
}

const escapar = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

const PALAVRAS_DE_SAUDACAO = ['olá', 'ola', 'oi', 'bom dia', 'boa tarde', 'boa noite'];

/**
 * Tira a saudação do começo de um texto: "Olá Sandro Roberto, segue…", "Boa tarde, Sandro! Segue…",
 * "Olá! Segue…". O nome só sai junto quando é o do cliente (completo ou o primeiro) — "Olá, tudo
 * bem?" não perde o "tudo bem". Devolve o resto (com a primeira letra maiúscula) e o espaço que
 * separava a saudação do resto (para manter uma quebra de linha que já existia).
 */
function separarSaudacao(texto: string, nomeDoCliente?: string | null): { resto: string; separador: string; tinha: boolean } {
  const nomes = [...new Set([(nomeDoCliente || '').trim(), (nomeDoCliente || '').trim().split(/\s+/)[0] || '', primeiroNome(nomeDoCliente)])]
    .filter(Boolean)
    .sort((a, b) => b.length - a.length)
    .map(escapar);
  const saud = PALAVRAS_DE_SAUDACAO.map(escapar).join('|');
  const nome = nomes.length ? `(?:[ \\t]*,?[ \\t]*(?:${nomes.join('|')})(?=[\\s,!.]|$))?` : '';
  const re = new RegExp(`^(?:${saud})(?=[\\s,!.]|$)${nome}[ \\t]*[!,.]?(\\s*)`, 'iu');
  const m = texto.match(re);
  if (!m) return { resto: texto, separador: ' ', tinha: false };
  const resto = texto.slice(m[0].length);
  const separador = m[1].includes('\n') ? m[1] : ' ';
  return { resto: resto.charAt(0).toLocaleUpperCase('pt-BR') + resto.slice(1), separador, tinha: true };
}

/** O resumo de valores abre com o cabeçalho em negrito ("*Orçamento ORÇ-…* — Empresa"). */
const CABECALHO_EM_NEGRITO = /^\*[^*\n]+\*/;

/**
 * Troca SÓ a abertura da mensagem — o corpo que a pessoa já editou fica como está.
 *
 * No resumo de valores a saudação é uma linha própria logo abaixo do cabeçalho; no resto, é o
 * começo da primeira frase ("Boa tarde, Sandro! Segue o ORÇ-00555…"). `nova` vazia = tira a
 * saudação.
 */
export function trocarSaudacao(mensagem: string, nova: string, nomeDoCliente?: string | null): string {
  const linhas = mensagem.split('\n');
  if (linhas.length > 1 && CABECALHO_EM_NEGRITO.test(linhas[0])) {
    const [cabecalho, ...resto] = linhas;
    const { resto: semSaudacao, tinha } = separarSaudacao(resto[0] ?? '', nomeDoCliente);
    if (tinha) {
      if (semSaudacao.trim() === '') resto.shift();
      else resto[0] = semSaudacao;
    }
    if (nova) resto.unshift(nova);
    return [cabecalho, ...resto].join('\n');
  }
  const { resto, separador } = separarSaudacao(mensagem, nomeDoCliente);
  if (!nova) return resto;
  return resto ? `${nova}${separador}${resto}` : nova;
}

// ─── Corpo padrão ────────────────────────────────────────────────────────────

export type TipoDoEnvio = 'quote' | 'service_order' | 'billing';

/**
 * O corpo padrão, curto e sem emoji. O número já traz o prefixo ("ORÇ-00555", "OS-00100"):
 * "Segue o ORÇ-00555", nunca "o Orçamento ORÇ-00555". Número antigo sem prefixo ganha a
 * palavra na frente, para a frase não ficar "Segue o 00555".
 */
export function corpoPadrao(p: { tipo: TipoDoEnvio; numero?: string | null; descricao?: string | null }): string {
  const fecho = 'Qualquer dúvida, estamos à disposição.';
  const numero = (p.numero || '').trim();
  if (p.tipo === 'quote') {
    const doc = /^OR[ÇC]/i.test(numero) ? numero : `orçamento ${numero}`.trim();
    return `Segue o ${doc}, conforme solicitado. ${fecho}`;
  }
  if (p.tipo === 'service_order') {
    const doc = /^OS/i.test(numero) ? numero : `OS ${numero}`.trim();
    return `Segue a ${doc}. ${fecho}`;
  }
  const descricao = (p.descricao || '').trim().replace(/[\s.;,:!]+$/, '');
  return descricao ? `Segue a cobrança referente a ${descricao}. ${fecho}` : `Segue a cobrança. ${fecho}`;
}

/** Abertura + corpo padrão: "Boa tarde, Sandro! Segue o ORÇ-00555, conforme solicitado. …". */
export function mensagemPadrao(p: {
  tipo: TipoDoEnvio;
  numero?: string | null;
  descricao?: string | null;
  saudacao: Saudacao;
  nomeDoCliente?: string | null;
  agora: Date;
}): string {
  const abertura = textoDaSaudacao(p.saudacao, p.nomeDoCliente, p.agora);
  const corpo = corpoPadrao(p);
  return abertura ? `${abertura} ${corpo}` : corpo;
}

// ─── Link online ─────────────────────────────────────────────────────────────

/**
 * Tira do texto o link público e a frase que o apresenta, sem deixar pontuação solta.
 *
 * O link é: a variável {link}/{{link}} que um modelo deixou sem valor, a URL pública deste
 * documento e qualquer endereço …/view/<token> (outro documento colado, outro domínio). A
 * frase que o apresenta é o trecho da mesma oração que termina em ":" logo antes dele —
 * "Acesso: ", "Acompanhe pelo link: ", "Detalhes: ", "Link online: ".
 *
 * "Olá Sandro, segue o orçamento ORÇ-1 no valor de 1.250,00. Acesso: {link}"
 *   → "Olá Sandro, segue o orçamento ORÇ-1 no valor de 1.250,00."
 */
export function tirarLinkDoTexto(texto: string, urlPublica?: string | null): string {
  const alternativas = [
    '\\{\\{\\s*link\\s*\\}\\}',
    '\\{link\\}',
    'https?:\\/\\/[^\\s]*\\/view\\/[A-Za-z0-9_-]+[^\\s]*?(?=[.,;:!?)]*(?:\\s|$))',
  ];
  if (urlPublica) alternativas.unshift(escapar(urlPublica));
  const link = `(?:${alternativas.join('|')})`;
  // A frase que apresenta: começa num limite de oração (início da linha, ". ", ", ", "(") e
  // termina em ":" logo antes do link. Sem ":" sai só o link.
  const comApresentacao = new RegExp(`(^|[.!?;,(][ \\t]*|[ \\t])[ \\t]*(?:[^.!?;,:(\\n]*:[ \\t]*)?${link}`, 'giu');

  let mudou = false;
  const linhas = texto.split('\n').map((linha) => {
    const sem = linha.replace(comApresentacao, (_m, antes: string) => antes);
    if (sem === linha) return linha;
    mudou = true;
    let limpa = sem
      .replace(/\(\s*\)/g, '')              // "(acesse: …)" que sobrou vazio
      .replace(/[ \t]+([.,;:!?])/g, '$1')   // espaço antes de pontuação
      .replace(/[,;:]+(?=[.!?])/g, '')      // ",." → "."
      // ".." → "." (reticências ficam). Sem lookbehind de propósito: Safari antigo (iPhone) não
      // o conhece e o módulo inteiro deixaria de carregar.
      .replace(/\.{2,}/g, (m) => (m.length === 2 ? '.' : m))
      .replace(/[ \t]{2,}/g, ' ')
      .replace(/[ \t]*[,;:]+[ \t]*$/, '.')  // "…foi aberta," no fim → "…foi aberta."
      .trimEnd();
    if (!/^[ \t]/.test(linha)) limpa = limpa.trimStart();
    // Linha que era só o link (ou a frase dele) some inteira.
    return /^[\s.,;:!?-]*$/.test(limpa) ? null : limpa;
  });
  if (!mudou) return texto;
  return linhas
    .filter((l): l is string => l !== null)
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

/** Há link público (ou {link}) neste texto? */
export function temLinkNoTexto(texto: string, urlPublica?: string | null): boolean {
  return tirarLinkDoTexto(texto, urlPublica) !== texto;
}

// ─── Como a mensagem viaja ───────────────────────────────────────────────────

/**
 * O modo escolhido na tela. 'texto' é só a mensagem — a cobrança, que não tem PDF nem resumo
 * de valores neste diálogo (o seletor de modo nem aparece).
 */
export type ModoDaTela = 'document' | 'resumo' | 'link' | 'texto';

/** Como a mensagem VIAJA até o whatsapp-send — 'text', 'link' ou 'document'. */
export type Transporte = 'text' | 'link' | 'document';

/**
 * Em que modo o diálogo abre: PDF quando dá para gerar; senão Resumo; Link só se for o único
 * possível; senão só a mensagem.
 */
export function modoInicial(p: { podePdf: boolean; podeResumo: boolean; podeLink: boolean }): ModoDaTela {
  if (p.podePdf) return 'document';
  if (p.podeResumo) return 'resumo';
  if (p.podeLink) return 'link';
  return 'texto';
}

export interface EnvioPreparado {
  transporte: Transporte;
  /** O texto que vai (no 'document', a base da legenda). */
  mensagem: string;
  /** A legenda do PDF: a mensagem, mais "Link online: …" quando a caixa está marcada. */
  legenda: string;
  /** O link vai? (modo Link, ou a caixa marcada com URL pública disponível) */
  linkVai: boolean;
  /** O texto tinha um link que saiu porque a caixa está desmarcada. */
  linkTirado: boolean;
}

/**
 * O que sai, dado o modo, o texto da tela e a caixa "Enviar também o link online".
 *
 * - Link: é a escolha de mandar o link — vai com ele.
 * - PDF: a legenda é a mensagem; com a caixa marcada ganha "Link online: …" no fim.
 * - Resumo e mensagem: caixa desmarcada = TEXTO, sem URL nenhuma; marcada = 'link' (a Evolution
 *   põe a URL no fim, como era antes).
 * Caixa desmarcada: qualquer link público que esteja no texto sai (tirarLinkDoTexto).
 */
export function prepararEnvio(p: {
  modo: ModoDaTela;
  mensagem: string;
  enviarLink: boolean;
  urlPublica?: string | null;
}): EnvioPreparado {
  const url = p.urlPublica || '';
  const linkVai = p.modo === 'link' || (p.enviarLink && !!url);
  const mensagem = linkVai ? p.mensagem : tirarLinkDoTexto(p.mensagem, url);
  const linkTirado = mensagem !== p.mensagem;
  const transporte: Transporte =
    p.modo === 'document' ? 'document' : p.modo === 'link' ? 'link' : linkVai ? 'link' : 'text';
  const legenda =
    p.modo === 'document' && linkVai && !mensagem.includes(url)
      ? (mensagem.trim() ? `${mensagem}\n\nLink online: ${url}` : `Link online: ${url}`)
      : mensagem;
  return { transporte, mensagem, legenda, linkVai, linkTirado };
}
