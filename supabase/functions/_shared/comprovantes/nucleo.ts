// Peças puras do fluxo de comprovantes do WhatsApp (F1, 11/10/2026 — spec-f1-final.md, seção 6).
// Sem rede e sem banco: tudo aqui tem teste em nucleo_test.ts.
//
// O que mora aqui:
//   - a leitura da legenda e a rota de cada mídia do dono (agente | comprovante | ambos);
//   - o caminho no bucket e o nome do arquivo no Dropbox;
//   - o texto do aviso ao dono (só informativo) e o par que vai para o histórico do assistente.
//
// Regras de privacidade: nada aqui escreve log; o aviso nunca usa nome lido pelo OCR (fornecedor só
// do cadastro, senão o CNPJ formatado) e nunca leva CPF.
import { dataEmSaoPaulo } from "../dropbox/nucleo.ts";
import type { Modo } from "./modo.ts";

/** A pasta dos comprovantes no Dropbox. CONSTANTE (decisão 9): app_settings não desvia arquivo. */
export const PASTA_COMPROVANTES = "/MANAGEMENT/FINANCIALS/COMPROVANTES";
export const PASTA_A_CLASSIFICAR = `${PASTA_COMPROVANTES}/_A CLASSIFICAR`;
/** F2: o arquivo do CMP cancelado pelo dono (com " CANCELADO" no nome). */
export const PASTA_CANCELADOS = `${PASTA_COMPROVANTES}/_CANCELADOS`;
/** F2: os pessoais, por mês (PESSOAL/AAAA-MM); nada no financeiro. */
export const PASTA_PESSOAL = `${PASTA_COMPROVANTES}/PESSOAL`;
/** Como a pasta aparece no texto ao dono. */
const PASTA_NO_AVISO = "COMPROVANTES/_A CLASSIFICAR";

export type Rota = "agente" | "comprovante" | "ambos";

// ---------------------------------------------------------------------------------------------
// Legenda e rota
// ---------------------------------------------------------------------------------------------

/**
 * Primeira palavra que diz "isto é comprovante" (comparada sem acento e em minúsculas).
 * Sem "c" (11/10/2026): no WhatsApp "c" é "você" ("c viu isso?"); volta se o dono decidir
 * (pendência 5 da spec).
 */
const PALAVRAS_CHAVE = new Set([
  "cmp", "cupom", "cupons", "nota", "notas", "nf", "nfe", "nfce", "nfse", "pix", "comprovante",
  "comprovantes", "recibo", "boleto", "insumo", "estoque", "empresa", "adm", "pessoal",
]);

function semAcento(s: string): string {
  return s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
}

/** Pontuação/símbolo/espaço no começo do resto ("cupom: OS 12" → "OS 12"). */
const LIXO_NO_COMECO = /^[\s\p{P}\p{S}]+/u;

export type Legenda = { forcado: boolean; dica: string | null; temTexto: boolean };

type Token = { texto: string; fim: number };

/** Quantos tokens do começo formam uma referência de OS ("os 123", "OS-123", "os123"); 0 = nenhuma. */
function referenciaDeOs(tokens: Token[]): number {
  if (tokens[0] && /^os\d+$/.test(tokens[0].texto)) return 1;
  if (tokens[0]?.texto === "os" && tokens[1] && /\d/.test(tokens[1].texto)) return 2;
  return 0;
}

/** Os tokens são SÓ uma referência de OS, sem mais nada. */
function soReferenciaDeOs(tokens: Token[]): boolean {
  const n = referenciaDeOs(tokens);
  return n > 0 && n === tokens.length;
}

/**
 * A legenda (SÓ o caption da foto/documento; nunca o nome do arquivo — decisão 1).
 *
 * - `forcado` (o dono AFIRMOU que é comprovante: o CMP nasce na chegada) só com a palavra-chave
 *   SOZINHA ("cupom") ou seguida só de uma referência de OS ("cupom OS 123"). Palavra-chave com
 *   texto livre ("nota que o cliente mandou", "pessoal, olha isso") não força: o arquivo entra no
 *   fluxo e a classificação do leitor decide o CMP (11/10/2026: "nota", "pessoal", "empresa" e
 *   "estoque" começam frases comuns).
 * - `os <número>` sozinho NUNCA força: é a foto do serviço que o assistente anexa à OS
 *   (attach_photo_to_service_order). Vai como legenda comum, com a OS na dica.
 * - `dica`: o resto depois da palavra-chave (para a F2); com "os <número>", a legenda inteira.
 * - `temTexto`: existe texto além de uma palavra-chave sozinha — com texto, a mensagem vai ao
 *   assistente na chegada (rota "ambos").
 */
export function lerLegenda(caption: string | null | undefined): Legenda {
  const original = typeof caption === "string" ? caption.trim() : "";
  if (!original) return { forcado: false, dica: null, temTexto: false };

  const tokens: Token[] = [...original.matchAll(/[\p{L}\p{N}]+/gu)].map((m) => ({
    texto: semAcento(m[0]),
    fim: (m.index ?? 0) + m[0].length,
  }));
  if (tokens.length === 0) return { forcado: false, dica: null, temTexto: true };
  // "NF-e", "NFC-e", "NFS-e" são uma palavra só
  if (["nf", "nfc", "nfs"].includes(tokens[0].texto) && tokens[1]?.texto === "e"
      && /^[-.]$/.test(original.slice(tokens[0].fim, tokens[1].fim - 1))) {
    tokens.splice(0, 2, { texto: `${tokens[0].texto}e`, fim: tokens[1].fim });
  }

  const resto = (fim: number) => original.slice(fim).replace(LIXO_NO_COMECO, "").trim();
  const [primeiro] = tokens;

  if (PALAVRAS_CHAVE.has(primeiro.texto)) {
    const r = resto(primeiro.fim);
    const depois = tokens.slice(1);
    const forcado = depois.length === 0 || soReferenciaDeOs(depois);
    return { forcado, dica: r || null, temTexto: r.length > 0 };
  }
  // "os 123", "OS 0105 Brisa": a OS é a informação — vai na dica, sem forçar
  if (referenciaDeOs(tokens) > 0) return { forcado: false, dica: original, temTexto: true };
  return { forcado: false, dica: null, temTexto: true };
}

/**
 * O documento pode ser comprovante pelo mimetype que o WhatsApp declarou? PDF, XML, imagem, binário
 * genérico (octet-stream: às vezes é um PDF) ou sem mimetype = sim; planilha, zip, docx… = não.
 */
export function documentoPodeSerComprovante(mimetype: string | null | undefined): boolean {
  const m = String(mimetype ?? "").split(";")[0].trim().toLowerCase();
  if (!m) return true;
  return m === "application/pdf" || m === "application/xml" || m === "text/xml" || m === "application/octet-stream" ||
    m.startsWith("image/");
}

/**
 * Para onde vai a mídia (seção 3.2 da spec):
 *   off, quem não é o dono, não-mídia ou sem id da mensagem → "agente" (o código de hoje);
 *   documento com mimetype que nunca é comprovante (xlsx, zip, docx…) → "agente": nem baixa;
 *   sombra → "ambos" (o assistente recebe tudo como hoje; o fluxo só guarda, lê e arquiva);
 *   dono   → sem legenda ou só a palavra-chave → "comprovante"; qualquer outro texto → "ambos".
 */
export function rotaDaMensagem(p: {
  modo: Modo;
  ehDono: boolean;
  mediaKind: "image" | "document" | null | undefined;
  temMsgId: boolean;
  caption: string | null | undefined;
  mimetype?: string | null;
}): Rota {
  if (p.modo !== "sombra" && p.modo !== "dono") return "agente";
  if (!p.ehDono || !p.temMsgId) return "agente";
  if (p.mediaKind !== "image" && p.mediaKind !== "document") return "agente";
  if (p.mediaKind === "document" && !documentoPodeSerComprovante(p.mimetype)) return "agente";
  if (p.modo === "sombra") return "ambos";
  return lerLegenda(p.caption).temTexto ? "ambos" : "comprovante";
}

// ---------------------------------------------------------------------------------------------
// Arquivo: extensão e caminho no bucket
// ---------------------------------------------------------------------------------------------

export type Extensao = "jpg" | "png" | "webp" | "heic" | "pdf" | "xml";

const EXT_DO_MIME: Record<string, Extensao> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "image/heic": "heic",
  "image/heif": "heic",
  "application/pdf": "pdf",
  "application/xml": "xml",
  "text/xml": "xml",
};

export function extensaoDoMime(mime: string): Extensao | null {
  const m = String(mime ?? "").split(";")[0].trim().toLowerCase();
  return EXT_DO_MIME[m] ?? null;
}

/** "AAAA/MM/<id>.<ext>", com o mês de São Paulo da chegada (um objeto por linha). */
export function caminhoNoBucket(id: string, recebidoEm: Date, ext: string): string {
  const dia = dataEmSaoPaulo(recebidoEm);
  return `${dia.slice(0, 4)}/${dia.slice(5, 7)}/${id.toLowerCase()}.${ext}`;
}

// ---------------------------------------------------------------------------------------------
// Nome no Dropbox
// ---------------------------------------------------------------------------------------------

/** A forma `DadosDoArquivo` das RPCs (seção 4.3 da spec). */
export type DadosDoArquivo = {
  id: string;
  codigo: string | null;
  situacao: string;
  tipo: string | null;
  valor: string | number | null;
  valor_confianca: string | null;
  data_compra: string | null;
  hora_compra: string | null;
  recebido_em: string;
  fornecedor_nome: string | null;
  arquivo_path: string;
  arquivo_mime: string | null;
};

export const SIGLAS: Record<string, string> = {
  nfce: "NFCE",
  nfe_danfe: "NFE",
  nfe_xml: "NFE-XML",
  nfse: "NFS",
  cupom_nao_fiscal: "CF",
  pix: "PIX",
  boleto_pago: "CP",
  boleto: "BOL",
  cartao: "CARTAO",
  fatura: "FT",
  guia: "GUIA",
  recibo: "REC",
  agendado: "AGEND",
  pedido: "PED",
  outro: "DOC",
  nao_documento: "DOC",
};

/** Caracteres que o Dropbox (e o Windows do dono) não aceitam em nome de arquivo. */
export function limparNome(s: string): string {
  return s.replace(/[\\/:*?"<>|]+/g, "-").replace(/[\u0000-\u001f\u007f]+/g, "").replace(/\s+/g, " ").trim();
}

function diaValido(s: string | null | undefined): string | null {
  return typeof s === "string" && /^\d{4}-\d{2}-\d{2}$/.test(s) ? s : null;
}

function diaDoRecebimento(recebidoEm: string | null | undefined): string {
  const d = recebidoEm ? new Date(recebidoEm) : new Date(NaN);
  return dataEmSaoPaulo(Number.isNaN(d.getTime()) ? new Date() : d);
}

/** "12:57:56" → "12h57"; desconhecida → null. */
export function horaNoNome(h: string | null | undefined): string | null {
  const m = typeof h === "string" ? /^(\d{2}):(\d{2})/.exec(h) : null;
  return m ? `${m[1]}h${m[2]}` : null;
}

/** "62.00" → "R$ 62,00"; "1234.5" → "R$ 1.234,50"; inválido → null. */
export function formatarReais(v: string | number | null | undefined): string | null {
  if (v === null || v === undefined || v === "") return null;
  const n = Number(v);
  if (!Number.isFinite(n) || n <= 0) return null;
  const [inteiro, centavos] = n.toFixed(2).split(".");
  return `R$ ${inteiro.replace(/\B(?=(\d{3})+(?!\d))/g, ".")},${centavos}`;
}

/** Fornecedor do cadastro no nome do arquivo: sem acento, até 40 caracteres. */
export function fornecedorNoNome(nome: string | null | undefined): string | null {
  if (!nome) return null;
  const s = limparNome(nome.normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^\x20-\x7e]/g, ""));
  const corte = s.slice(0, 40).trim();
  return corte || null;
}

export function extensaoDoCaminho(caminho: string | null | undefined): string | null {
  const m = typeof caminho === "string" ? /\.([a-z0-9]{2,5})$/i.exec(caminho) : null;
  return m ? m[1].toLowerCase() : null;
}

/**
 * "AAAA-MM-DD HHhMM CMP-00123 SIGLA R$ 62,00 Fornecedor.ext".
 * Data = data da compra, senão o dia da chegada em São Paulo; sem hora se desconhecida; valor SÓ
 * com selo "alta"; fornecedor só do cadastro. CMP sem leitura: "AAAA-MM-DD CMP-00123 A LER.ext".
 * Sem destino e sem pagamento na F1.
 */
export function nomeNoDropbox(d: DadosDoArquivo): string {
  const ext = extensaoDoCaminho(d.arquivo_path) ?? extensaoDoMime(d.arquivo_mime ?? "") ?? "bin";
  const codigo = limparNome(d.codigo || "CMP");
  if (d.situacao !== "lido") return `${limparNome(`${diaDoRecebimento(d.recebido_em)} ${codigo} A LER`)}.${ext}`;

  const partes: string[] = [diaValido(d.data_compra) ?? diaDoRecebimento(d.recebido_em)];
  const hora = horaNoNome(d.hora_compra);
  if (hora) partes.push(hora);
  partes.push(codigo, SIGLAS[d.tipo ?? ""] ?? "DOC");
  if (d.valor_confianca === "alta") {
    const reais = formatarReais(d.valor);
    if (reais) partes.push(reais);
  }
  const fornecedor = fornecedorNoNome(d.fornecedor_nome);
  if (fornecedor) partes.push(fornecedor);
  return `${limparNome(partes.join(" "))}.${ext}`;
}

// ---------------------------------------------------------------------------------------------
// Aviso ao dono (só informativo) e o par do histórico do assistente
// ---------------------------------------------------------------------------------------------

/** Um item de `comprovante_reservar_aviso` (RPC 7 da spec). */
export type ItemDoAviso = {
  id: string;
  codigo: string | null;
  decisao: "cmp" | "cmp_sem_leitura" | "duplicado" | "nao_guardado";
  tipo: string | null;
  valor: string | number | null;
  valor_confianca: string | null;
  data_compra: string | null;
  fornecedor_nome: string | null;
  emitente_cnpj: string | null;
  cnpj_confianca: string | null;
  recebido_em: string;
  erro: string | null;
  duplicado: { codigo: string | null; data_compra: string | null; valor: string | number | null } | null;
};

export const TIPO_NO_AVISO: Record<string, string> = {
  nfce: "cupom NFC-e",
  nfe_danfe: "nota fiscal (DANFE)",
  nfe_xml: "XML de nota fiscal",
  nfse: "nota fiscal de serviço",
  cupom_nao_fiscal: "cupom não fiscal",
  pix: "comprovante de Pix",
  boleto_pago: "comprovante de boleto pago",
  boleto: "boleto",
  cartao: "via de cartão",
  fatura: "fatura",
  guia: "guia",
  recibo: "recibo",
  agendado: "pagamento agendado",
  pedido: "pedido",
};

const FECHO = "Ainda não lancei nada. Não precisa responder.";
const MAX_AVISO = 4096;

/** "2026-10-08" → "08/10". */
export function diaMes(d: string | null | undefined): string | null {
  const v = diaValido(d);
  return v ? `${v.slice(8, 10)}/${v.slice(5, 7)}` : null;
}

/** "11222333000181" → "11.222.333/0001-81" (aceita o CNPJ alfanumérico). */
export function formatarCnpj(c: string | null | undefined): string | null {
  const s = String(c ?? "").toUpperCase();
  if (!/^[0-9A-Z]{12}[0-9]{2}$/.test(s)) return null;
  return `${s.slice(0, 2)}.${s.slice(2, 5)}.${s.slice(5, 8)}/${s.slice(8, 12)}-${s.slice(12)}`;
}

function horaEmSaoPaulo(iso: string): string | null {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  return new Intl.DateTimeFormat("pt-BR", { timeZone: "America/Sao_Paulo", hour: "2-digit", minute: "2-digit" }).format(d);
}

/** "a", "a e b", "a, b e c"; mais de 5: "a, b, c, d, e e mais N". */
export function listaPt(itens: string[]): string {
  if (itens.length <= 1) return itens[0] ?? "";
  if (itens.length > 5) return `${itens.slice(0, 5).join(", ")} e mais ${itens.length - 5}`;
  return `${itens.slice(0, -1).join(", ")} e ${itens[itens.length - 1]}`;
}

function numeroDoCodigo(codigo: string | null): number | null {
  const m = codigo ? /^CMP-(\d+)$/.exec(codigo) : null;
  return m ? Number(m[1]) : null;
}

/** "CMP-00123 a CMP-00127" quando contínuos; senão a lista (até 5 e "e mais N"). */
export function faixaDeCodigos(codigos: string[]): string {
  const comNumero = codigos.map((c) => ({ c, n: numeroDoCodigo(c) }));
  if (comNumero.length >= 3 && comNumero.every((x) => x.n !== null)) {
    const ordenados = [...comNumero].sort((a, b) => (a.n as number) - (b.n as number));
    const continuos = ordenados.every((x, i) => i === 0 || (x.n as number) === (ordenados[i - 1].n as number) + 1);
    if (continuos) return `${ordenados[0].c} a ${ordenados[ordenados.length - 1].c}`;
    return listaPt(ordenados.map((x) => x.c));
  }
  return listaPt(codigos);
}

/** Quem é o fornecedor no aviso: o nome do cadastro ou o CNPJ formatado; nunca nome do OCR. */
function fornecedorNoAviso(i: ItemDoAviso): string | null {
  const cnpj = formatarCnpj(i.emitente_cnpj);
  const conferido = Boolean(cnpj) && i.cnpj_confianca === "alta";
  if (i.fornecedor_nome) return conferido ? `${i.fornecedor_nome} (CNPJ conferido)` : i.fornecedor_nome;
  if (cnpj) return conferido ? `CNPJ ${cnpj} (conferido)` : `CNPJ ${cnpj}`;
  return null;
}

/** Valor no aviso: omitido com selo baixa; "(confira)" quando o selo não é alta. */
function valorNoAviso(i: ItemDoAviso): string | null {
  if (i.valor_confianca === "baixa") return null;
  const reais = formatarReais(i.valor);
  if (!reais) return null;
  return i.valor_confianca === "alta" ? reais : `${reais} (confira)`;
}

function fraseDosCmp(cmps: ItemDoAviso[]): string {
  if (cmps.length === 1) {
    const i = cmps[0];
    const partes = [TIPO_NO_AVISO[i.tipo ?? ""] ?? "documento", fornecedorNoAviso(i), diaMes(i.data_compra), valorNoAviso(i)]
      .filter((p): p is string => Boolean(p));
    return `${i.codigo ?? "Comprovante"} guardado: ${partes.join(", ")}. Está em ${PASTA_NO_AVISO}.`;
  }
  const conferidos = cmps.filter((i) => i.valor_confianca === "alta" && formatarReais(i.valor)).length;
  const resto = cmps.length - conferidos;
  const conferencia = [
    conferidos > 0 ? `${conferidos} com valor conferido` : null,
    resto > 0 ? `${resto} para conferir` : null,
  ].filter(Boolean).join(", ");
  const codigos = faixaDeCodigos(cmps.map((i) => i.codigo ?? "?"));
  return `Guardei ${cmps.length} comprovantes: ${codigos}. ${conferencia}. Estão em ${PASTA_NO_AVISO}.`;
}

function fraseDosDuplicados(dups: ItemDoAviso[]): string {
  if (dups.length === 1) {
    const d = dups[0].duplicado;
    if (!d?.codigo) return "Esse comprovante já estava guardado. Não guardei de novo.";
    const detalhes = [diaMes(d.data_compra), formatarReais(d.valor)].filter(Boolean).join(", ");
    return `Esse comprovante já é o ${d.codigo}${detalhes ? ` (${detalhes})` : ""}. Não guardei de novo.`;
  }
  const codigos = dups.map((i) => i.duplicado?.codigo).filter((c): c is string => Boolean(c));
  return `${dups.length} comprovantes já estavam guardados${codigos.length ? `: ${listaPt(codigos)}` : ""}. Não guardei de novo.`;
}

function fraseDosSemLeitura(itens: ItemDoAviso[]): string {
  if (itens.length === 1) {
    return `${itens[0].codigo ?? "Comprovante"} guardado, mas não consegui ler o arquivo. Está em ${PASTA_NO_AVISO} com 'A LER' no nome.`;
  }
  const codigos = listaPt(itens.map((i) => i.codigo ?? "?"));
  return `${codigos} guardados, mas não consegui ler os arquivos. Estão em ${PASTA_NO_AVISO} com 'A LER' no nome.`;
}

function motivoDeNaoGuardar(erro: string | null): string {
  if (erro === "formato_nao_suportado") return "o formato não é foto, PDF nem XML";
  if (erro === "arquivo_grande") return "passa de 15 MB";
  return "o WhatsApp não entregou a mídia";
}

function fraseDosNaoGuardados(itens: ItemDoAviso[]): string {
  if (itens.length === 1) {
    const i = itens[0];
    const hora = horaEmSaoPaulo(i.recebido_em);
    return `Não consegui guardar o arquivo que você mandou${hora ? ` às ${hora}` : ""} (${motivoDeNaoGuardar(i.erro)}). Pode mandar de novo como foto ou PDF?`;
  }
  const horas = itens.map((i) => horaEmSaoPaulo(i.recebido_em)).filter((h): h is string => Boolean(h));
  return `Não consegui guardar ${itens.length} arquivos que você mandou${horas.length ? ` (às ${listaPt(horas)})` : ""}. Pode mandar de novo como foto ou PDF?`;
}

/**
 * O aviso ao dono. Uma frase por categoria, na ordem: guardados, repetidos, sem leitura, não
 * guardados; o fecho ("Ainda não lancei nada. Não precisa responder.") uma vez só, quando há CMP
 * lido (os textos de cada categoria são os da spec, seção 6.1). Sem emoji. Até 4096 caracteres.
 */
export function textoDoAviso(itens: ItemDoAviso[]): string {
  const por = (d: ItemDoAviso["decisao"]) => itens.filter((i) => i.decisao === d);
  const cmps = por("cmp");
  const dups = por("duplicado");
  const semLeitura = por("cmp_sem_leitura");
  const naoGuardados = por("nao_guardado");
  const frases: string[] = [];
  if (cmps.length) frases.push(fraseDosCmp(cmps));
  if (dups.length) frases.push(fraseDosDuplicados(dups));
  if (semLeitura.length) frases.push(fraseDosSemLeitura(semLeitura));
  if (naoGuardados.length) frases.push(fraseDosNaoGuardados(naoGuardados));
  if (cmps.length) frases.push(FECHO);
  const texto = frases.join(" ");
  return texto.length <= MAX_AVISO ? texto : `${texto.slice(0, MAX_AVISO - 1)}…`;
}

function plural(n: number, um: string, varios: string): string {
  return `${n} ${n === 1 ? um : varios}`;
}

/**
 * O par que entra em ai_operator_messages a cada aviso (lacuna 3): o assistente fica sabendo do
 * que o sistema disse ao dono. A marca 🤖 diz que não foi o dono que escreveu. Sem CPF e sem
 * texto do OCR: só o aviso e as referências.
 */
export function historicoDoAviso(itens: ItemDoAviso[], texto: string): { user: string; assistant: string } {
  const guardados = itens.filter((i) => i.decisao === "cmp" || i.decisao === "cmp_sem_leitura").length;
  const repetidos = itens.filter((i) => i.decisao === "duplicado").length;
  const naoGuardados = itens.filter((i) => i.decisao === "nao_guardado").length;
  const contagem = [
    plural(guardados, "arquivo guardado", "arquivos guardados"),
    repetidos ? plural(repetidos, "repetido", "repetidos") : null,
    naoGuardados ? plural(naoGuardados, "não guardado", "não guardados") : null,
  ].filter(Boolean).join(", ");
  const referencias = itens.map((i) => {
    if (i.codigo) return `${i.codigo} (id ${i.id})`;
    if (i.decisao === "duplicado" && i.duplicado?.codigo) return `repetido de ${i.duplicado.codigo} (id ${i.id})`;
    return `arquivo sem número (id ${i.id})`;
  });
  return {
    user: `🤖 Aviso automático do sistema de comprovantes (não foi o dono que escreveu): ${contagem}.`,
    assistant: `${texto}\n\nReferência: ${referencias.join(", ")}. Nada foi lançado no financeiro.`,
  };
}

// ---------------------------------------------------------------------------------------------
// Chave de idempotência do aviso (whatsapp-send dedupe_key)
// ---------------------------------------------------------------------------------------------

const K = new Uint32Array([
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
]);

/**
 * SHA-256 síncrono (o WebCrypto só tem a versão assíncrona). Só para a chave do aviso; o hash do
 * arquivo usa crypto.subtle (midia.ts). Conferido contra o WebCrypto no teste.
 */
export function sha256HexSync(texto: string): string {
  const msg = new TextEncoder().encode(texto);
  const tamanho = Math.ceil((msg.length + 9) / 64) * 64;
  const buf = new Uint8Array(tamanho);
  buf.set(msg);
  buf[msg.length] = 0x80;
  const dv = new DataView(buf.buffer);
  const bits = msg.length * 8;
  dv.setUint32(tamanho - 8, Math.floor(bits / 0x100000000));
  dv.setUint32(tamanho - 4, bits >>> 0);
  const h = new Uint32Array([0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]);
  const w = new Uint32Array(64);
  const rotr = (x: number, n: number) => (x >>> n) | (x << (32 - n));
  for (let off = 0; off < tamanho; off += 64) {
    for (let i = 0; i < 16; i++) w[i] = dv.getUint32(off + i * 4);
    for (let i = 16; i < 64; i++) {
      const s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
      const s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0;
    }
    let [a, b, c, d, e, f, g, hh] = h;
    for (let i = 0; i < 64; i++) {
      const s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      const ch = (e & f) ^ (~e & g);
      const t1 = (hh + s1 + ch + K[i] + w[i]) >>> 0;
      const s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      const maj = (a & b) ^ (a & c) ^ (b & c);
      const t2 = (s0 + maj) >>> 0;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) >>> 0;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) >>> 0;
    }
    h[0] = (h[0] + a) >>> 0;
    h[1] = (h[1] + b) >>> 0;
    h[2] = (h[2] + c) >>> 0;
    h[3] = (h[3] + d) >>> 0;
    h[4] = (h[4] + e) >>> 0;
    h[5] = (h[5] + f) >>> 0;
    h[6] = (h[6] + g) >>> 0;
    h[7] = (h[7] + hh) >>> 0;
  }
  return [...h].map((x) => x.toString(16).padStart(8, "0")).join("");
}

/** "cmp:aviso:<16 hex do sha256 dos ids ordenados>": o mesmo lote nunca sai duas vezes. */
export function chaveDoAviso(ids: string[]): string {
  const ordenados = [...ids].map((s) => s.toLowerCase()).sort();
  return `cmp:aviso:${sha256HexSync(ordenados.join(",")).slice(0, 16)}`;
}
