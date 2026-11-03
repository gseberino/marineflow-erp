// O validador que falha FECHADO: a última porta antes de um texto automático do retorno sair.
//
// ═══ POR QUE EXISTE (Retorno rápido ao cliente, F1, 16/11/2026) ═══
//
// O texto do retorno é do banco (_retorno_texto, molde _agenda_cliente_texto): modelo fixo, campos
// preenchidos pelo sistema, falta de dado = erro. Mesmo assim, um campo errado ou um modelo novo pode
// levar ao cliente o que nunca deveria sair: valor, documento, telefone, uma promessa sem fonte, a
// data, a hora, a OS ou o nome de outro cliente, um trecho copiado do que o cliente escreveu (R1-12).
// Aqui o texto pronto é conferido contra o contexto que o banco montou (retorno_pegar, contrato
// C-VAL) pelas regras do plano B.5 e pelas palavras proibidas de B.4.3. A edge retorno-recibos roda
// o validador em TODO item, também na sombra (B.5.5): reprovado = recusada/validador, nada sai.
//
// Falha fechado:
//  - todas as regras são checadas e o resultado lista TODAS as que falharam (não para na 1ª);
//  - contexto ausente ou malformado reprova ('contexto'), e as regras que dependem dele correm com
//    lista de permissão vazia, marcas falsas e o que der para ler das listas de bloqueio: falta de
//    dado nunca vira exceção a favor do envio;
//  - qualquer exceção aqui dentro reprova com 'erro'; validarSaida nunca lança.
//
// As palavras são comparadas sem acento e em minúsculas (NFKC, que também desfaz dígito e letra de
// largura cheia), sempre como palavra inteira ou começo de palavra, para "Custódio" não virar
// "custo" nem "nos" virar "os". As datas, horas e OS só passam quando o trecho inteiro casado está
// dentro de uma ocorrência de um valor que o banco permitiu: "segunda (09/11)" permitido não deixa
// passar "segunda (16/11)".
//
// Onde a especificação deixou a regra em aberto, ficou a leitura que bloqueia mais (registrado na
// entrega da parte P10): dinheiro também barra preço, boleto, pagamento, parcela, custo, dinheiro,
// "gratuito", "por cento" e valor com centavos (350,00); dado pessoal barra 10 ou mais dígitos
// seguidos (não só 11 e 14), telefone local sem DDD (99999-1234), qualquer "@" colado a texto e
// endereço com cara de domínio (wa.me, bit.ly); a placa casa em maiúscula ou minúscula; a data pega
// qualquer número/número, sem âncora no fim, como o `\d{1,2}/\d{1,2}` da especificação ("11/2026",
// "1/2027" e "09/111" reprovam), e o mesmo com traço (dd-mm, mm-aaaa, aaaa-mm-dd), por isso telefone,
// CPF e CNPJ com traço ou barra entre dígitos reprovam também em data_fora, além de dado_pessoal; a
// data também pega "anteontem" e os nomes dos meses ("março" só com cedilha, para não confundir com
// "marco"); a hora também pega "19 horas", "10h30", "30 min", "meio-dia" e "meia-noite"; a OS pega
// "OS 70", "OS nº 70" e "orçamento 12"; a promessa pega "garantimos", "prometemos", "fica pronta",
// "ficará pronto"; o emoji inclui bandeira, tom de pele e o seletor de emoji (U+FE0F); o tamanho conta
// unidades UTF-16 (nunca menos que os caracteres).
//
// O eco do cliente (R1-12) é lido pelo propósito, não pela letra da linha da especificação ("4
// palavras do cliente que não estão nos trechos_do_modelo"): as quadras de cada trecho separado
// nunca atravessam um {campo}, e "Boa tarde! Aqui é o assistente" reprovava porque o cliente abriu
// com "Boa tarde, aqui é o Pedro" (a abertura mais comum de número novo). Eco é a quadra que está num
// texto do cliente e tem pelo menos uma palavra que o banco não escreveu. O banco escreveu a palavra
// que fica inteira dentro de uma ocorrência, no texto, de um trecho do modelo, de um valor permitido
// (data, hora, nome) ou de um valor das listas fechadas dos {campos} que não vêm no contexto
// (cumprimento e de_quando, spec P3.1). Decisão registrada na entrega da correção da parte P10.
//
// Sem import nenhum, de propósito: o teste de isolamento (isolamento_test.ts) fica trivial, e o
// validador não muda quando muda o resto do WhatsApp.
//
// Reverter: apagar este arquivo, validador_test.ts e isolamento_test.ts (a edge retorno-recibos
// importa validarSaida daqui: sem ela, retirar também a edge).

export interface ContextoDoValidador {
  audiencia: "cliente";
  datas_permitidas: string[]; // como aparecem no texto: "hoje", "amanhã", "segunda (09/11)", "09/11", "ontem"
  horas_permitidas: string[]; // "10h", "19h", "21:40"
  nome_permitido: string | null;
  nomes_de_outros: string[];
  os_permitidas: string[]; // vazio na F1
  textos_do_cliente: string[]; // corpos das recebidas do caso (só para o eco; nunca entram no texto)
  trechos_do_modelo: string[]; // o texto fixo sem os {campos}
  marcas: { tem_proposta: boolean; tem_topo: boolean; cliente_ouviu: boolean; conferida: boolean };
}

export type RegraDoValidador =
  | "vazio"
  | "contexto"
  | "audiencia"
  | "dinheiro"
  | "dado_pessoal"
  | "promessa"
  | "data_fora"
  | "hora_fora"
  | "os_de_outro"
  | "nome_de_outro"
  | "afirmacao_sem_dado"
  | "eco_do_cliente"
  | "emoji"
  | "tamanho"
  | "palavra_proibida"
  | "erro";

export type ResultadoDoValidador = { ok: true } | { ok: false; regras: RegraDoValidador[] };

/** Ao cliente: no máximo 400 caracteres e 5 linhas (B.5, R2 P20). */
export const LIMITE_DE_CARACTERES = 400;
export const LIMITE_DE_LINHAS = 5;

/**
 * Confere o texto que vai ao cliente. `{ ok: true }` só quando nenhuma regra falhou; senão, a lista de
 * todas as que falharam, na ordem de RegraDoValidador. Nunca lança: exceção vira `['erro']`.
 */
export function validarSaida(
  texto: string,
  ctx: ContextoDoValidador | null | undefined,
): ResultadoDoValidador {
  try {
    const regras = conferir(texto, ctx);
    return regras.length === 0 ? { ok: true } : { ok: false, regras };
  } catch {
    return { ok: false, regras: ["erro"] };
  }
}

// ─── Normalização ────────────────────────────────────────────────────────────────────────────────

// "Palavra inteira": nem letra nem dígito colado antes (ou depois). Com a flag u.
const ANTES = "(?<![\\p{L}\\p{N}])";
const DEPOIS = "(?![\\p{L}\\p{N}])";

/**
 * Forma de comparação: NFKC (desfaz largura cheia, letra estilizada, espaço sem quebra), minúsculas,
 * sem caractere invisível de formatação (\p{Cf}), dígito de outra escrita vira "0" (continua dígito
 * para as regras de número) e, com `semAcento`, sem acento (ç → c, ã → a).
 */
function preparar(s: string, semAcento: boolean): string {
  let r = s.normalize("NFKC").toLowerCase().normalize("NFC")
    .replace(/\p{Cf}/gu, "")
    .replace(/\p{Nd}/gu, (d) => (d >= "0" && d <= "9" ? d : "0"));
  if (semAcento) r = r.normalize("NFD").replace(/\p{M}/gu, "");
  return r;
}

function escapar(s: string): string {
  // Só os caracteres de sintaxe: com a flag u, escapar "-" fora de classe é erro.
  return s.replace(/[.*+?^${}()|[\]\\/]/g, "\\$&");
}

/** O trecho [inicio, fim) está inteiro dentro de alguma ocorrência de algum permitido? */
function coberto(t: string, inicio: number, fim: number, permitidos: string[]): boolean {
  for (const p of permitidos) {
    if (p.length === 0) continue;
    for (let k = t.indexOf(p); k !== -1 && k <= inicio; k = t.indexOf(p, k + 1)) {
      if (fim <= k + p.length) return true;
    }
  }
  return false;
}

/** Algum trecho casado por algum padrão (todos com a flag g) fica fora dos permitidos? */
function algumForaDe(t: string, padroes: RegExp[], permitidos: string[]): boolean {
  for (const padrao of padroes) {
    for (const m of t.matchAll(padrao)) {
      const i = m.index ?? 0;
      if (!coberto(t, i, i + m[0].length, permitidos)) return true;
    }
  }
  return false;
}

// ─── Regras de texto (sem contexto) ──────────────────────────────────────────────────────────────

const INVISIVEL_OU_ESPACO = /[\s\p{Cf}]/gu;

const DINHEIRO: RegExp[] = [
  /\$/u, // R$, US$
  /%/u,
  /(?<!\d)\d+,\d{2}(?!\d)/u, // 350,00
  new RegExp(
    ANTES +
      "(?:reais|sinal|sinais|pix|descontos?|gratis|gratuit[oa]s?|sem\\s+custos?|custos?|precos?|boletos?" +
      "|pagamentos?|parcelas?|dinheiro|por\\s+cento)" + DEPOIS,
    "u",
  ),
];

const DADO_PESSOAL: RegExp[] = [
  /\d{3}\.?\d{3}\.?\d{3}-?\d{2}/u, // CPF
  /\d{2}\.?\d{3}\.?\d{3}\/?\d{4}-?\d{2}/u, // CNPJ
  /\(\d{2}\)\s?9?\d{4}-?\d{4}/u, // (xx) 9xxxx-xxxx
  /(?<!\d)9?\d{4}[-.]\d{4}(?!\d)/u, // telefone local, sem DDD
  /\S@|@\S/u, // e-mail (ou @perfil)
  /[0-9a-f]{8}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{12}/u, // chave Pix aleatória (uuid)
  /[a-z]{3}-?\d[a-z0-9]\d{2}/u, // placa: ABC-1234, ABC1D23
  /http|www\.|\.com|\.br|[\p{L}\p{N}]\.\p{L}{2,}/u, // link, domínio
];

// Dígitos seguidos, com ou sem pontuação entre eles (ponto, traço, barra, espaço, parênteses, +).
const SEQUENCIA_DE_DIGITOS = /\d(?:[\s.\-\/()+]*\d)*/gu;
const MINIMO_DE_DIGITOS = 10; // telefone 10–13, CPF 11, CNPJ 14; mais que isso também

function temDadoPessoal(t: string): boolean {
  if (DADO_PESSOAL.some((r) => r.test(t))) return true;
  for (const m of t.matchAll(SEQUENCIA_DE_DIGITOS)) {
    if (m[0].replace(/\D/g, "").length >= MINIMO_DE_DIGITOS) return true;
  }
  return false;
}

const PROMESSA = new RegExp(
  ANTES +
    "(?:garanto|garantimos|prometo|prometemos|pode\\s+deixar|com\\s+certeza" +
    "|fica(?:m|ra|rao)?\\s+pront[oa]s?|pront[oa]s?\\s+ate)",
  "u",
);

// Datas e dias: só passam cobertos por datas_permitidas ou trechos_do_modelo (o "hoje" do T22).
// Sem âncora no fim, e o trecho casado leva todos os dígitos: "09/11" permitido não cobre "09/111"
// nem "09/11/2026", e "segunda (09/11)" continua passando.
const DATAS: RegExp[] = [
  /(?<!\d)\d+\/\d+(?:\/\d+)*/gu, // 09/11, 9/11/2026, 11/2026
  /(?<!\d)\d+-\d+(?:-\d+)*/gu, // 09-11, 11-2026, 2026-11-09
  new RegExp(
    ANTES +
      "(?:segunda|terca|quarta|quinta|sexta|sabado|domingo|seg|ter|qua|qui|sex|sab|dom" +
      "|amanha|hoje|ontem|anteontem" +
      "|janeiro|fevereiro|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro)" + DEPOIS,
    "gu",
  ),
];
// "março" sem acento é "marco" (de marcar): esta só casa no texto que guarda o acento.
const DATAS_COM_ACENTO: RegExp[] = [new RegExp(ANTES + "março" + DEPOIS, "gu")];

// Horas: só passam cobertas por horas_permitidas.
const HORAS: RegExp[] = [
  /(?<!\d)\d+\s?h(?:oras?|rs?|s)?(?!\p{L})\d*/gu, // 19h, 19 h, 19hs, 19 horas, 10h30
  /(?<!\d)\d+:\d+/gu, // 21:40
  /(?<!\d)\d+\s?min/gu, // 30 min, 30 minutos
  new RegExp(ANTES + "mei[oa][\\s-]?(?:dia|noite)" + DEPOIS, "gu"), // meio-dia, meia-noite
];

// OS e orçamento: só passam cobertos por os_permitidas (vazio na F1).
const OS: RegExp[] = [new RegExp(ANTES + "(?:os|orc|orcamento)[\\s\\-–—#.:°no]*\\d+", "gu")];

const JA_AVISADO = new RegExp(ANTES + "(?:foi|foram|ja|esta|estao|ficou)\\s+avisad", "u");
const CONFERIDA = /conferid/u;
const EM_PREPARACAO = new RegExp(ANTES + "em\\s+prepar", "u");
const ABRE_A_LISTA = new RegExp(ANTES + "abr(?:e|ir|imos|indo)\\s+a\\s+lista", "u");

const EMOJI = /[\p{Extended_Pictographic}\p{Regional_Indicator}\p{Emoji_Modifier}\u{FE0F}\u{20E3}]/u;

const QUEBRA_DE_LINHA = /\r\n|\r|\n|\u000b|\u000c|\u0085|\u2028|\u2029/;

const PALAVRA = /[\p{L}\p{N}]+/gu;

// Valores das listas fechadas do _retorno_texto (spec P3.1) que o banco p\u00f5e nos {campos} e que o
// contexto n\u00e3o traz: cumprimento e de_quando. Para o eco, s\u00e3o palavras que o banco escreveu.
const LISTAS_FECHADAS_DOS_CAMPOS = ["Bom dia", "Boa tarde", "Boa noite", "de ontem \u00e0 noite", "desta madrugada"];

// B.4.3: "Palavras que nenhum texto usa".
const PALAVRAS_PROIBIDAS: RegExp[] = [
  ANTES + "previas?" + DEPOIS,
  ANTES + "cheg[a-z]*\\s+com\\s+o\\s+valor",
  ANTES + "em\\s+campo",
  ANTES + "frente\\s+da\\s+fila",
  ANTES + "topo\\s+da\\s+lista",
  ANTES + "em\\s+atendimento",
  ANTES + "ja\\s+foi\\s+conferid",
  ANTES + "mar(?:c|qu)[a-z]*\\s+como\\s+prioridade",
].map((fonte) => new RegExp(fonte, "u"));

// ─── Contexto ────────────────────────────────────────────────────────────────────────────────────

interface ContextoLido {
  malformado: boolean;
  audienciaErrada: boolean;
  datas: string[]; // datas_permitidas + trechos_do_modelo, preparados sem acento
  datasComAcento: string[]; // os mesmos, preparados com acento
  horas: string[];
  os: string[];
  nomesDeOutros: string[];
  textosDoCliente: string[];
  // o que o banco escreveu (só para o eco): trechos do modelo, datas, horas e nome permitidos e as
  // listas fechadas dos {campos}, preparados sem acento
  escritoPeloBanco: string[];
  marcas: { tem_proposta: boolean; tem_topo: boolean; cliente_ouviu: boolean; conferida: boolean };
}

const MARCAS = ["tem_proposta", "tem_topo", "cliente_ouviu", "conferida"] as const;

function ehListaDeTexto(v: unknown): v is string[] {
  return Array.isArray(v) && v.every((x) => typeof x === "string");
}

/**
 * Lê o contexto uma vez só. Campo faltando ou de tipo errado = malformado. Lista de PERMISSÃO
 * malformada vale vazia (permite menos); lista de BLOQUEIO malformada guarda o que der para ler
 * (bloqueia mais); marca só vale quando é exatamente `true`. Um getter que lança sobe até o catch de
 * validarSaida ('erro').
 */
function lerContexto(ctx: unknown): ContextoLido {
  const estado = { malformado: false };
  const marcas = { tem_proposta: false, tem_topo: false, cliente_ouviu: false, conferida: false };
  if (ctx === null || typeof ctx !== "object" || Array.isArray(ctx)) {
    return {
      malformado: true, audienciaErrada: false, datas: [], datasComAcento: [], horas: [], os: [],
      nomesDeOutros: [], textosDoCliente: [], escritoPeloBanco: [], marcas,
    };
  }
  const o = ctx as Record<string, unknown>;
  const permissao = (v: unknown): string[] => {
    if (ehListaDeTexto(v)) return v;
    estado.malformado = true;
    return [];
  };
  const bloqueio = (v: unknown): string[] => {
    if (ehListaDeTexto(v)) return v;
    estado.malformado = true;
    return Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : [];
  };

  const audiencia = o.audiencia;
  if (typeof audiencia !== "string") estado.malformado = true;
  const datas = permissao(o.datas_permitidas);
  const horas = permissao(o.horas_permitidas);
  const nome = o.nome_permitido;
  if (nome !== null && typeof nome !== "string") estado.malformado = true;
  const nomesDeOutros = bloqueio(o.nomes_de_outros);
  const os = permissao(o.os_permitidas);
  const textosDoCliente = bloqueio(o.textos_do_cliente);
  const trechos = permissao(o.trechos_do_modelo);
  const m = o.marcas;
  if (m === null || typeof m !== "object" || Array.isArray(m)) {
    estado.malformado = true;
  } else {
    const lidas = m as Record<string, unknown>;
    for (const k of MARCAS) {
      const v = lidas[k];
      if (typeof v !== "boolean") estado.malformado = true;
      marcas[k] = v === true;
    }
  }

  const semAcento = (l: string[]) => l.map((s) => preparar(s, true));
  return {
    malformado: estado.malformado,
    // Ausente já é 'contexto'; presente e diferente de "cliente" (parceiro é F4) é 'audiencia'.
    audienciaErrada: audiencia !== undefined && audiencia !== "cliente",
    datas: semAcento([...datas, ...trechos]),
    datasComAcento: [...datas, ...trechos].map((s) => preparar(s, false)),
    horas: semAcento(horas),
    os: semAcento(os),
    nomesDeOutros: semAcento(nomesDeOutros).map((s) => s.trim()).filter((s) => s.length > 0),
    textosDoCliente: semAcento(textosDoCliente),
    escritoPeloBanco: semAcento([
      ...trechos, ...datas, ...horas, ...(typeof nome === "string" ? [nome] : []), ...LISTAS_FECHADAS_DOS_CAMPOS,
    ]).map((s) => s.trim()).filter((s) => s.length > 0),
    marcas,
  };
}

// ─── Regras que dependem do contexto ─────────────────────────────────────────────────────────────

function citaNome(t: string, nomes: string[]): boolean {
  for (const nome of nomes) {
    const partes = nome.split(/\s+/u).filter((p) => p.length > 0);
    if (partes.length === 0) continue;
    if (new RegExp(ANTES + partes.map(escapar).join("\\s+") + DEPOIS, "u").test(t)) return true;
  }
  return false;
}

/** As sequências de 4 palavras de um texto já preparado. */
function quadras(t: string): string[] {
  const palavras = t.match(PALAVRA) ?? [];
  const r: string[] = [];
  for (let i = 0; i + 4 <= palavras.length; i++) r.push(palavras.slice(i, i + 4).join(" "));
  return r;
}

/**
 * R1-12: 4 palavras seguidas que o cliente escreveu, com pelo menos uma que o banco não escreveu.
 * A palavra é do banco quando fica inteira dentro de uma ocorrência, no texto, de algum valor de
 * `escritoPeloBanco` (a mesma cobertura por posição das datas): "Boa tarde! Aqui é o assistente"
 * não ecoa "Boa tarde, aqui é o Pedro", mas "Boa tarde, aqui é o Pedro" escrito no texto ecoa.
 */
function ecoaOCliente(t: string, textosDoCliente: string[], escritoPeloBanco: string[]): boolean {
  const doCliente = new Set(textosDoCliente.flatMap(quadras));
  if (doCliente.size === 0) return false;
  const palavras = [...t.matchAll(PALAVRA)].map((m) => {
    const i = m.index ?? 0;
    return { palavra: m[0], doBanco: coberto(t, i, i + m[0].length, escritoPeloBanco) };
  });
  for (let i = 0; i + 4 <= palavras.length; i++) {
    const q = palavras.slice(i, i + 4);
    if (doCliente.has(q.map((p) => p.palavra).join(" ")) && q.some((p) => !p.doBanco)) return true;
  }
  return false;
}

function afirmaSemDado(t: string, marcas: ContextoLido["marcas"]): boolean {
  return (JA_AVISADO.test(t) && !marcas.cliente_ouviu) ||
    (CONFERIDA.test(t) && !marcas.conferida) ||
    (EM_PREPARACAO.test(t) && !marcas.tem_proposta) ||
    (ABRE_A_LISTA.test(t) && !marcas.tem_topo);
}

// ─── Todas as regras ─────────────────────────────────────────────────────────────────────────────

function conferir(texto: unknown, ctx: unknown): RegraDoValidador[] {
  // Texto que não é string (veio nulo do JSON) é tratado como vazio: nunca sai.
  const bruto = typeof texto === "string" ? texto : "";
  const c = lerContexto(ctx);
  const t = preparar(bruto, true);
  const tComAcento = preparar(bruto, false);
  const regras: RegraDoValidador[] = [];

  if (bruto.replace(INVISIVEL_OU_ESPACO, "").length === 0) regras.push("vazio");
  if (c.malformado) regras.push("contexto");
  if (c.audienciaErrada) regras.push("audiencia");
  if (DINHEIRO.some((r) => r.test(t))) regras.push("dinheiro");
  if (temDadoPessoal(t)) regras.push("dado_pessoal");
  if (PROMESSA.test(t)) regras.push("promessa");
  if (
    algumForaDe(t, DATAS, c.datas) ||
    algumForaDe(tComAcento, DATAS_COM_ACENTO, c.datasComAcento)
  ) regras.push("data_fora");
  if (algumForaDe(t, HORAS, c.horas)) regras.push("hora_fora");
  if (algumForaDe(t, OS, c.os)) regras.push("os_de_outro");
  if (citaNome(t, c.nomesDeOutros)) regras.push("nome_de_outro");
  if (afirmaSemDado(t, c.marcas)) regras.push("afirmacao_sem_dado");
  if (ecoaOCliente(t, c.textosDoCliente, c.escritoPeloBanco)) regras.push("eco_do_cliente");
  if (EMOJI.test(bruto)) regras.push("emoji");
  if (bruto.length > LIMITE_DE_CARACTERES || bruto.split(QUEBRA_DE_LINHA).length > LIMITE_DE_LINHAS) {
    regras.push("tamanho");
  }
  if (PALAVRAS_PROIBIDAS.some((r) => r.test(t))) regras.push("palavra_proibida");
  return regras;
}
