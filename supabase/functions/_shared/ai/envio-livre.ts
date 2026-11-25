// Mensagem de TEXTO LIVRE para fora: quem recebe de fato e o que o texto diz (pacote 1 do assistente, S1, 24/11/2026).
//
// ═══ POR QUE EXISTE ═══
//
// Regra do dono (24/11/2026): a mensagem de texto livre pede PIN quando vai a CLIENTE ou quando o texto cita VALOR, DATA
// ou PROMESSA; para fornecedor e equipe basta o "sim" (se o texto a eles citar valor, data ou promessa, pede PIN).
// Destinatário sem cadastro conta como cliente.
//
// (25/11/2026, cartão IA-19) Para fornecedor, equipe e o próprio dono o PIN passou a ser só pelo DINHEIRO. A escolha do
// dono: "PIN só quando o texto fala de dinheiro (valor, Pix, pagamento). Data, horário e prazo saem só com o 'sim'."
// O aviso do horário ao técnico sai com o "sim"; "fecha por R$ 4.200" ao fornecedor pede PIN. Para cliente, parceiro,
// número sem cadastro e número em mais de um tipo de cadastro nada mudou: PIN sempre, e o motivo segue dizendo valor,
// data e promessa. Ver CONTEUDO_PARA_FORNECEDOR_E_EQUIPE.
//
// Até aqui o PIN era decidido pelo ARGUMENTO que o modelo escolhia: com client_id, PIN; com to_phone, só "sim". E a
// descrição da ferramenta manda usar to_phone para responder uma conversa. Em 90 dias, 19 de 23 mensagens propostas com
// to_phone iam a número do cadastro de clientes, e 8 saíram sem PIN (spec-seguranca.md do pacote 1). Aqui o risco é
// decidido no SERVIDOR, pelo número que vai receber, conferido contra os cadastros, e pelo texto.
//
// Só leitura: nada aqui grava nem envia. É o gancho ToolDef.riscoNoServidor de send_whatsapp_message e de
// schedule_whatsapp_message (tools/whatsapp.ts). O gancho só SOBE o risco calculado pelos argumentos (agent.ts).
//
// Tudo o que não der para conferir cai no lado seguro (PIN): leitura do banco que falha, lista grande demais para
// conferir, número inválido ou de grupo, número que está em mais de um tipo de cadastro, cadastro inativo de equipe.
//
// (Revisão do pacote 1, 24/11/2026) Cadastro de fornecedor ou de favorecido criado ou alterado há menos de 24 horas
// também não conta: o número segue valendo como cliente. Sem isso o modelo voltava a escolher o risco: cadastrar o
// número como fornecedor (create_supplier, update_supplier e link_contact_to_entity rodam direto, sem cartão) trocava
// o PIN pelo "sim" na mensagem seguinte do mesmo turno. Ver CADASTRO_RECENTE_MS.
//
// Reverter: tirar `riscoNoServidor` das duas ferramentas (uma linha cada); este arquivo fica inerte.
import { chaveTelefone, mesmoTelefone } from "./phone.ts";
import { detectarPromessa } from "./promessa.ts";
import { type CampoDoNumero, numeroDoEnvio } from "./tools/agendamento.ts";
import type { RiscoNoServidor, ToolCtx } from "./tools/registry.ts";
// As listas de valor, data e promessa são as do validador do retorno (uma régua só). O isolamento proíbe só o caminho
// contrário: _shared/retorno/ nunca importa _shared/ai/.
import { citaValorDataOuPromessa } from "../retorno/validador.ts";

// ─── Quem recebe ────────────────────────────────────────────────────────────────────────────────────────────────────

export type Destino = "cliente" | "parceiro" | "sem_cadastro" | "fornecedor" | "equipe" | "o_proprio";

/** O número que vai receber (null = não deu para saber) e os tipos de cadastro em que ele aparece, sem repetir. */
export interface QuemRecebe {
  telefone: string | null;
  destinos: Destino[];
  /**
   * true = o número está num cadastro de fornecedor ou de favorecido criado ou alterado há menos de 24 horas, que por
   * isso NÃO entrou em `destinos` (CADASTRO_RECENTE_MS). Só muda o motivo dito no cartão quando não sobra outro cadastro.
   */
  cadastroRecente?: boolean;
}

/**
 * (Revisão do pacote 1, 24/11/2026) Por quanto tempo o cadastro de fornecedor ou de favorecido criado ou alterado NÃO
 * conta como "fornecedor" nem como "equipe": 24 horas, a validade do cartão de confirmação.
 *
 * Por quê: "fornecedor e equipe, só o sim" é o lado menos protegido da regra, e quem escreve nesses cadastros é o
 * próprio assistente, sem cartão (create_supplier, update_supplier, link_contact_to_entity) ou com um "sim" (favorecido).
 * Contando o cadastro feito na hora, o número sem cadastro (PIN) virava "fornecedor" (só o "sim") numa escrita calada.
 * Quem lê é o banco: created_at tem padrão now() e updated_at é regravado em todo update pelos gatilhos
 * set_updated_at_suppliers e payees_updated_at (conferidos em produção em 24/11/2026; nenhuma linha sem as datas).
 * Custo: quem acabou de ser cadastrado ou corrigido pede PIN por um dia (em 24/11/2026, 0 dos 534 fornecedores e 0 dos
 * 9 favorecidos tinham sido mexidos nas 24 horas anteriores).
 */
export const CADASTRO_RECENTE_MS = 24 * 3600_000;

/**
 * O cadastro foi criado ou alterado há menos de 24 horas? Sem data, com data ilegível ou com data no futuro não dá
 * para afirmar que é antigo: conta como recente (lado seguro).
 */
function cadastroRecente(linha: Record<string, unknown>, agora: number): boolean {
  for (const campo of ["created_at", "updated_at"]) {
    const valor = linha[campo];
    const quando = typeof valor === "string" ? Date.parse(valor) : NaN;
    if (!Number.isFinite(quando) || agora - quando < CADASTRO_RECENTE_MS) return true;
  }
  return false;
}

/** A ordem em que os destinos aparecem (do mais protegido para o menos). */
const ORDEM_DOS_DESTINOS: Destino[] = ["cliente", "parceiro", "fornecedor", "equipe", "o_proprio"];

/**
 * Acima disto, numa tabela, o casamento não é conferido linha a linha: lança, e o risco vai para o lado seguro. O filtro
 * do banco quase nunca devolve mais de uma ou duas linhas (ver padraoDoNumero).
 */
export const LIMITE_POR_CADASTRO = 50;

/**
 * O filtro do banco para "termina com estes 8 dígitos", tolerante ao jeito como o número foi digitado: os 8 dígitos em
 * ordem, com qualquer coisa entre eles ("%9%9%1%5%9%6%5%4%"). Os cadastros guardam o telefone como foi escrito
 * ("(47) 99915-9654", "+351 966 776 422", "47 9 9915 96 54"); todo número que termina com a chave casa com o padrão, em
 * qualquer formato. O contrário não vale (o padrão é mais largo), então quem decide é mesmoTelefone, linha a linha.
 */
export function padraoDoNumero(chave: string): string {
  return `%${chave.split("").join("%")}%`;
}

type Linha = Record<string, unknown>;

/** Lê uma lista. Erro do banco, resposta que não é lista ou lista no limite = lança (não dá para afirmar nada). */
async function lerLista(consulta: PromiseLike<{ data: unknown; error: unknown }>, onde: string): Promise<Linha[]> {
  const { data, error } = await consulta;
  if (error) throw new Error(`leitura de ${onde} falhou`);
  if (!Array.isArray(data)) throw new Error(`leitura de ${onde} sem resposta`);
  if (data.length >= LIMITE_POR_CADASTRO) throw new Error(`${onde}: linhas demais para conferir`);
  return data as Linha[];
}

const texto = (v: unknown): string | null => (typeof v === "string" ? v : null);

/**
 * Em que cadastros o número aparece, pelos 8 últimos dígitos (ai/phone.ts, a régua da casa). `clienteId` = o envio veio
 * com client_id e o número é o do cadastro dele: é cliente, e as outras tabelas ainda são lidas (o número pode ser
 * também de fornecedor ou da equipe).
 *
 *  · clients (whatsapp ou phone), ativo ou não            → "cliente"
 *  · parceiro_numeros (qualquer situação)                 → "parceiro"
 *  · suppliers (phone), ativo ou não                      → "fornecedor"
 *  · app_users ATIVO: o de quem pede → "o_proprio"; outro → "equipe". Inativo não conta (quem saiu é de fora)
 *  · payees ATIVO (prestador, comissionado, sócio)        → "equipe" ("o_proprio" se for o favorecido de quem pede)
 *  · em nenhum                                            → "sem_cadastro"
 *
 * O cadastro de fornecedor ou de favorecido criado ou alterado há menos de 24 horas NÃO conta (CADASTRO_RECENTE_MS):
 * a linha é pulada e `cadastroRecente` sai true. Os outros cadastros do mesmo número contam como sempre.
 *
 * Leitura que falha LANÇA; quem chama trata como risco alto. `admin` é o service-role: o risco não pode depender do
 * que a RLS de quem pede deixa ver. `agora` só existe para o teste escolher a hora.
 */
export async function quemRecebe(
  // deno-lint-ignore no-explicit-any
  admin: any,
  telefone: string | null | undefined,
  quem: { userId: string; clienteId?: string | null },
  agora: Date = new Date(),
): Promise<QuemRecebe> {
  const chave = chaveTelefone(telefone);
  if (!telefone || !chave) return { telefone: null, destinos: [] };
  const padrao = padraoDoNumero(chave);
  const L = LIMITE_POR_CADASTRO;
  const [clientes, fornecedores, favorecidos, usuarios, parceiros] = await Promise.all([
    lerLista(admin.from("clients").select("id, whatsapp, phone").or(`whatsapp.ilike.${padrao},phone.ilike.${padrao}`).limit(L), "clientes"),
    lerLista(admin.from("suppliers").select("id, phone, created_at, updated_at").ilike("phone", padrao).limit(L), "fornecedores"),
    lerLista(admin.from("payees").select("id, phone, active, app_user_id, created_at, updated_at").ilike("phone", padrao).limit(L), "favorecidos"),
    lerLista(
      admin.from("app_users").select("id, phone, phone_normalized, active").or(`phone_normalized.ilike.${padrao},phone.ilike.${padrao}`).limit(L),
      "usuários",
    ),
    lerLista(admin.from("parceiro_numeros").select("id, chave").eq("chave", chave).limit(L), "números de parceiro"),
  ]);

  const achados = new Set<Destino>();
  if (quem.clienteId) achados.add("cliente");
  if (clientes.some((c) => mesmoTelefone(texto(c.whatsapp), telefone) || mesmoTelefone(texto(c.phone), telefone))) achados.add("cliente");
  if (parceiros.some((n) => n.chave === chave)) achados.add("parceiro");
  // Fornecedor e favorecido são os cadastros em que o assistente escreve: o criado ou alterado há menos de 24 horas é pulado.
  const agoraMs = agora.getTime();
  let recente = false;
  for (const s of fornecedores) {
    if (!mesmoTelefone(texto(s.phone), telefone)) continue;
    if (cadastroRecente(s, agoraMs)) recente = true;
    else achados.add("fornecedor");
  }
  for (const u of usuarios) {
    if (u.active !== true) continue;
    if (!mesmoTelefone(texto(u.phone_normalized), telefone) && !mesmoTelefone(texto(u.phone), telefone)) continue;
    achados.add(u.id === quem.userId ? "o_proprio" : "equipe");
  }
  for (const f of favorecidos) {
    if (f.active !== true || !mesmoTelefone(texto(f.phone), telefone)) continue;
    if (cadastroRecente(f, agoraMs)) recente = true;
    else achados.add(f.app_user_id && f.app_user_id === quem.userId ? "o_proprio" : "equipe");
  }
  const destinos = ORDEM_DOS_DESTINOS.filter((d) => achados.has(d));
  return { telefone, destinos: destinos.length > 0 ? destinos : ["sem_cadastro"], ...(recente ? { cadastroRecente: true } : {}) };
}

// ─── O que o texto diz ──────────────────────────────────────────────────────────────────────────────────────────────

export interface ConteudoDoTexto {
  valor: boolean;
  data: boolean;
  promessa: boolean;
}

const ANTES = "(?<![\\p{L}\\p{N}])";
const DEPOIS = "(?![\\p{L}\\p{N}])";

/** Minúsculas e sem acento (NFKC desfaz letra estilizada e largura cheia), para as listas daqui. */
function semAcento(s: string): string {
  return s.normalize("NFKC").toLowerCase().normalize("NFD").replace(/\p{M}/gu, "");
}

// O que a lista do validador não tem, porque foi escrita para o texto FIXO do retorno. No texto livre o valor também vem
// abreviado ou por extenso, sem moeda ("uns 2 mil", "trezentos", "sai 350"), e a data vem relativa ("semana que vem",
// "dia 12", "em 5 dias"). São complementos pequenos: a régua continua sendo a do validador.
const VALOR_NO_TEXTO_LIVRE: RegExp[] = [
  // "2 mil", "1,5 mil", "2k", "300 conto", "50 pila"
  new RegExp("(?<![\\p{L}\\p{N}.,])\\d+(?:[.,]\\d+)?\\s*(?:mil|k|contos?|pilas?)" + DEPOIS, "u"),
  // por extenso: "mil", "dois mil", "cem", "cento e vinte", "trezentos", "um milhão"
  new RegExp(
    ANTES + "(?:mil|cem|cento|duzent[oa]s|trezent[oa]s|quatrocent[oa]s|quinhent[oa]s|seiscent[oa]s|setecent[oa]s|oitocent[oa]s" +
      "|novecent[oa]s|milhao|milhoes)" + DEPOIS,
    "u",
  ),
  // dezena por extenso com a moeda falada: "cinquenta conto", "vinte e cinco pila" ("reais" já está na lista do validador)
  new RegExp(
    ANTES + "(?:dez|vinte|trinta|quarenta|cinquenta|sessenta|setenta|oitenta|noventa)(?:\\s+e\\s+\\p{L}+)?\\s+(?:contos?|pilas?)" + DEPOIS,
    "u",
  ),
  // número logo depois de verbo de preço: "sai 350", "custa 1200", "cobro 80", "fica por 350", "faço por 300"
  new RegExp(
    ANTES + "(?:sai|saiu|saem|custa|custam|custou|cobra|cobro|cobrou|cobramos|pago|paga|pagamos|paguei|fica\\s+por|ficou\\s+por" +
      "|faco\\s+por|fazemos\\s+por|fecho\\s+por|fechamos\\s+por)\\s+(?:uns\\s+|umas\\s+|por\\s+|a\\s+)?\\d",
    "u",
  ),
];

// (25/11/2026, cartão IA-19) Pagamento falado sem número. Para fornecedor e equipe o PIN passou a ser só pelo dinheiro,
// e "já paguei", "vou transferir agora" e "depósito feito" não trazem moeda nem número para as listas de cima acharem.
// As três famílias inteiras (pagar, transferir, depositar), palavra inteira e sem acento: "apagar" e "página" não casam.
// Ficam de fora, de propósito, as palavras do pedido comum a fornecedor (orçamento, cotação, estoque, entrega, nota,
// comprovante): "me manda o orçamento", "tem em estoque?" e "chega quando?" saem só com o "sim".
// Lado seguro conhecido: "deposito" também é o depósito de guardar peça ("tem no depósito?"), e acusa.
const PAGAMENTO_FALADO: RegExp[] = [
  new RegExp(
    ANTES + "(?:pagar|pago|paga|pagos|pagas|paguei|pagou|pagamos|pagam|pagaram|pagando|pague|paguem|pagarei|pagara|pagaremos|pagarao)" + DEPOIS,
    "u",
  ),
  new RegExp(
    ANTES + "(?:transferir|transferi|transfiro|transfere|transferiu|transferimos|transferindo|transferid[oa]s?|transferencias?)" + DEPOIS,
    "u",
  ),
  new RegExp(ANTES + "(?:depositar|depositei|deposita|depositou|depositamos|depositando|depositad[oa]s?|depositos?)" + DEPOIS, "u"),
];

const DATA_NO_TEXTO_LIVRE: RegExp[] = [
  // relativas que a lista do validador não tem
  new RegExp(
    ANTES + "(?:semana\\s+que\\s+vem|mes\\s+que\\s+vem|ano\\s+que\\s+vem|proxim[oa]\\s+(?:semana|mes|ano)" +
      "|(?:fim|final)\\s+de\\s+semana|(?:fim|final)\\s+d[oe]\\s+(?:mes|ano)|depois\\s+de\\s+amanha|quinzena)" + DEPOIS,
    "u",
  ),
  // "dia 12", "até o dia 5"
  new RegExp(ANTES + "dia\\s+\\d{1,2}" + DEPOIS, "u"),
  // prazo: "em 5 dias", "3 dias úteis", "daqui a 2 semanas", "uma semana", "dois dias"
  new RegExp(ANTES + "\\d+\\s+(?:dias?|semanas?|mes|meses)" + DEPOIS, "u"),
  new RegExp(
    ANTES + "(?:um|uma|dois|duas|tres|quatro|cinco|seis|sete|oito|nove|dez|quinze|vinte|trinta)\\s+(?:dias?|semanas?|mes|meses)" + DEPOIS,
    "u",
  ),
];

/**
 * O texto cita valor, data/hora ou promessa? Erra para o lado de ACHAR (um PIN a mais custa pouco; um valor ou uma
 * promessa que sai sem o dono ver custa caro).
 *   valor    = a lista do validador do retorno (R$, %, 350,00, reais, pix, preço, boleto, sinal, "valor de 3"…), valor
 *              abreviado, por extenso ou depois de verbo de preço, ou pagamento falado sem número ("já paguei",
 *              "transferência feita", "vou depositar"). É o "fala de dinheiro" da regra de fornecedor e equipe;
 *   data     = a lista do validador (dd/mm, dia da semana, hoje/amanhã/ontem, mês, 19h, 21:40, 30 min) ou data relativa;
 *   promessa = a lista do validador ("garanto", "pode deixar", "fica pronto") ou a promessa do dono de ai/promessa.ts
 *              ("te mando", "vou enviar", "amanhã mando", "deixa comigo").
 * Nunca lança: exceção = tudo verdadeiro.
 */
export function conteudoQuePedePin(textoDaMensagem: unknown): ConteudoDoTexto {
  try {
    const bruto = typeof textoDaMensagem === "string" ? textoDaMensagem : String(textoDaMensagem ?? "");
    const doValidador = citaValorDataOuPromessa(bruto);
    const t = semAcento(bruto);
    return {
      valor: doValidador.valor || VALOR_NO_TEXTO_LIVRE.some((r) => r.test(t)) || PAGAMENTO_FALADO.some((r) => r.test(t)),
      data: doValidador.data || DATA_NO_TEXTO_LIVRE.some((r) => r.test(t)),
      promessa: doValidador.promessa || detectarPromessa(bruto, new Date()) !== null,
    };
  } catch {
    return { valor: true, data: true, promessa: true };
  }
}

/** "valor", "valor e data", "valor, data e promessa". */
function juntar(partes: string[]): string {
  if (partes.length <= 1) return partes.join("");
  return `${partes.slice(0, -1).join(", ")} e ${partes[partes.length - 1]}`;
}

/** O que o texto cita, em palavras: "valor", "valor e data", "valor, data e promessa". null = não cita nada. */
export function oQueCita(c: ConteudoDoTexto): string | null {
  const cita = [c.valor ? "valor" : "", c.data ? "data" : "", c.promessa ? "promessa" : ""].filter((p) => p !== "");
  return cita.length > 0 ? juntar(cita) : null;
}

/**
 * O aviso do cartão do PDF e do link da OS (send_service_order_link) quando a frase escrita pelo assistente
 * (custom_message) cita valor, data ou promessa. Só diz onde olhar: o PIN desse envio já existe e não muda.
 * null = sem frase ou frase que não cita nada (o cartão fica como sempre foi).
 *
 * "Confira antes de aprovar" (acabamento da leva A, 24/11/2026; era "antes do PIN"): o mesmo cartão aparece no chat do
 * app, onde a aprovação é por botão, sem PIN.
 */
export function avisoDaFraseDoAssistente(frase: unknown): string | null {
  // O link que a frase já traz (o da OS, com o código do compartilhamento) não é valor nem data: sai antes de conferir,
  // senão os números do código acusariam "data" em quase toda frase com link.
  const t = typeof frase === "string" ? frase.replace(/(?:https?:\/\/|www\.)\S+/gi, " ").trim() : "";
  if (!t) return null;
  const cita = oQueCita(conteudoQuePedePin(t));
  return cita ? `⚠️ A frase da legenda foi escrita pelo assistente e cita ${cita}. Confira antes de aprovar.` : null;
}

// ─── A regra ────────────────────────────────────────────────────────────────────────────────────────────────────────

/**
 * O que, no texto, faz a mensagem a fornecedor, equipe ou ao próprio dono pedir PIN. As três leituras da regra do dono:
 *   "dinheiro" (a que vale, cartão IA-19 de 25/11/2026): só quando o texto fala de dinheiro (o campo `valor`); data,
 *              hora, prazo e promessa, sozinhos, saem só com o "sim";
 *   "tudo"     (a de 24/11/2026): valor, data ou promessa pedem PIN;
 *   "nada"     : fornecedor e equipe sempre só o "sim".
 * Voltar atrás é trocar a palavra da constante (uma linha). Para cliente, parceiro, número sem cadastro e número em mais
 * de um tipo de cadastro a leitura não muda nada: PIN sempre.
 */
export type ConteudoParaFornecedorEEquipe = "dinheiro" | "tudo" | "nada";
export const CONTEUDO_PARA_FORNECEDOR_E_EQUIPE: ConteudoParaFornecedorEEquipe = "dinheiro";

const ROTULO_DO_DESTINO: Record<Destino, string> = {
  cliente: "de cliente",
  parceiro: "de parceiro",
  fornecedor: "de fornecedor",
  equipe: "da equipe",
  o_proprio: "seu",
  sem_cadastro: "sem cadastro",
};

/** Frases do cartão quando não dá para saber quem recebe. */
export const FALHA_AO_CONFERIR_QUEM_RECEBE = "não consegui conferir quem recebe";
export const NUMERO_QUE_NAO_FECHA = "não consegui identificar o número de quem recebe (vale como cliente)";
/** O número só aparece em cadastro de fornecedor ou de favorecido criado ou alterado há menos de 24 horas. */
export const CADASTRO_FEITO_HA_POUCO = "o cadastro deste número foi criado ou alterado há menos de 24 horas (vale como cliente)";

/**
 * A regra pura (sem banco): risco e motivo pelo destino e pelo conteúdo. O motivo é o que o dono lê depois de
 * "🔒 No WhatsApp, pede PIN: ". null = só o "sim" (fornecedor, equipe ou o próprio dono, com texto que não fala de
 * dinheiro).
 *
 *  · sem número conferido                            → PIN
 *  · número em mais de um tipo de cadastro           → PIN ("vale o mais protegido"), mesmo sem cliente entre eles
 *  · cliente, parceiro ou sem cadastro               → PIN (sem cadastro por ter só cadastro feito há pouco: diz isso)
 *  · fornecedor, equipe ou o próprio, com dinheiro   → PIN, e o motivo diz só o que disparou: "o texto cita valor"
 *  · fornecedor, equipe ou o próprio, sem dinheiro   → só "sim", mesmo com data, hora, prazo ou promessa no texto
 *
 * Nas quatro primeiras linhas o motivo junta tudo o que o texto cita (valor, data e promessa), como sempre. `leitura`
 * só existe para o teste e para voltar atrás (CONTEUDO_PARA_FORNECEDOR_E_EQUIPE); leitura que não existe vale "tudo".
 */
export function riscoDoEnvioLivrePorDestino(
  q: QuemRecebe,
  c: ConteudoDoTexto,
  leitura: ConteudoParaFornecedorEEquipe = CONTEUDO_PARA_FORNECEDOR_E_EQUIPE,
): { risco: "high" | "medium"; motivo: string | null } {
  const cita = oQueCita(c);
  const doTexto = cita ? `o texto cita ${cita}` : null;
  const destinos = [...new Set(q.destinos)];
  let doDestino: string | null = null;
  if (q.telefone === null || destinos.length === 0) doDestino = NUMERO_QUE_NAO_FECHA;
  else if (destinos.length > 1) doDestino = `o número é ${juntar(destinos.map((d) => ROTULO_DO_DESTINO[d]))} (vale o mais protegido)`;
  else if (destinos[0] === "cliente") doDestino = "vai a cliente";
  else if (destinos[0] === "parceiro") doDestino = "o número é de parceiro";
  else if (destinos[0] === "sem_cadastro") doDestino = q.cadastroRecente === true ? CADASTRO_FEITO_HA_POUCO : "o número não tem cadastro (vale como cliente)";
  if (doDestino) return { risco: "high", motivo: doTexto ? `${doDestino}; ${doTexto}` : doDestino };
  // Daqui para baixo o destino é um só: fornecedor, equipe ou o próprio dono. Quem decide é o texto, pela leitura que vale.
  if (leitura === "nada") return { risco: "medium", motivo: null };
  if (leitura === "dinheiro") return c.valor ? { risco: "high", motivo: "o texto cita valor" } : { risco: "medium", motivo: null };
  return doTexto ? { risco: "high", motivo: doTexto } : { risco: "medium", motivo: null };
}

/**
 * O gancho das duas ferramentas (ToolDef.riscoNoServidor). `campo` é onde vem o número: to_phone em
 * send_whatsapp_message, phone em schedule_whatsapp_message. Nunca lança e nunca devolve menos que "medium": o que não
 * der para conferir vale risco alto.
 */
export async function riscoDaMensagemLivre(
  args: Record<string, unknown> | null | undefined,
  ctx: Pick<ToolCtx, "admin" | "userId">,
  campo: CampoDoNumero,
): Promise<RiscoNoServidor> {
  try {
    const conteudo = conteudoQuePedePin(args?.message);
    // O MESMO número que o cartão mostra e que o envio usa (numeroDoEnvio). Destino que não fecha (número inválido ou de
    // grupo, client_id e número diferentes, cliente sem número): a validação e o resumo recusam antes do cartão; se um
    // dia não recusarem, o risco já é o alto.
    const destino = await numeroDoEnvio(ctx.admin, { client_id: args?.client_id, telefone: args?.[campo] }, campo);
    if (!destino.ok) return riscoDoEnvioLivrePorDestino({ telefone: null, destinos: [] }, conteudo);
    const q = await quemRecebe(ctx.admin, destino.telefone, { userId: ctx.userId, clienteId: destino.cliente?.id ?? null });
    return riscoDoEnvioLivrePorDestino(q, conteudo);
  } catch {
    return { risco: "high", motivo: FALHA_AO_CONFERIR_QUEM_RECEBE };
  }
}
