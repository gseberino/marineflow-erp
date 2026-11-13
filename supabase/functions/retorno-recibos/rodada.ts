// A rodada da edge retorno-recibos: pega no banco, uma a uma, as saídas do retorno que venceram, confere o
// texto de cada uma no validador e registra o desfecho. Na sombra, só "eu teria mandado"; ligada, envia
// pelo whatsapp-send (Retorno rápido ao cliente, F1, parte P11; sobe em sombra em 16/11/2026).
//
// ═══ POR QUE É ASSIM ═══
//
// Quem decide é o banco (IA pensa, sistema preenche). retorno_pegar (contrato C-PEGAR) escolhe o item com
// FOR UPDATE SKIP LOCKED, confere tudo de novo, monta o texto fixo, decide o modo do caso e reserva a saída
// ('preparada' na sombra, 'enviando' ligada): duas rodadas nunca pegam o mesmo item, e a trava não depende
// do envio. Aqui fica só o que o banco não faz: rodar o validador (_shared/retorno/validador.ts, que falha
// fechado) e falar com o whatsapp-send. Cada desfecho volta ao banco por retorno_registrar_decisao
// (contrato C-DECISAO).
//
// Regras desta rodada:
//  - o validador roda em TODO item, também na sombra (B.5.5): reprovado = recusada/validador, nada sai;
//  - na sombra, NENHUMA chamada de envio;
//  - a dedupe_key é sempre a que o banco devolveu. A única nova volta de um item é a do 503
//    (reserva_indisponivel), quando a reserva do whatsapp-send não aconteceu, e com a MESMA chave. A incerta
//    é final: pode ter saído, e nunca há 2ª tentativa. Erro ao registrar depois de enviar deixa a saída em
//    'enviando', e o vigia (retorno_vigia, passo 9) a passa a incerta: nunca reenvia;
//  - erro nunca trava a fila e a rodada nunca lança: o erro do retorno_pegar para a rodada (o cron chama de
//    novo no minuto seguinte); a exceção no envio vira incerta; a falha ao registrar vai ao log
//    (log_app_error) e o próximo item segue;
//  - o log nunca leva telefone nem texto do cliente: só o id da saída e códigos.
//
// Onde a especificação deixou aberto, ficou o que fecha (registrado na entrega da P11):
//  - resposta que a tabela do estadoDoEnvio não lista: outro 5xx (inclusive o 503 sem reserva_indisponivel e
//    o 502 sem o corpo do whatsapp-send, que podem ser do gateway depois de a função ter rodado), 2xx sem
//    success e status estranho viram incerta (pode ter saído; sem 2ª tentativa); outro 4xx (404, 429, o 422
//    sem recusado) vira recusada/provedor (o pedido não foi processado);
//  - antes de enviar (e também na sombra, que simula o ligado), o item tem de ter modo "sombra" ou "ligado",
//    origem do retorno (sem ela o whatsapp-send o trataria como automático comum, sem o portão
//    retorno_saida_autorizada), telefone só de dígitos e dedupe_key com o prefixo do emissor que o devolveu
//    ("retorno:…", "parceiro:…" ou "orcamento:…", PREFIXO_DA_CHAVE; chave de outro emissor já concluída faria o
//    whatsapp-send responder "já enviado" sem nada sair). Item torto = recusada/validador
//    com a regra 'contexto' e o código do problema: três na mesma hora rebaixam o tipo (vigia, passo 10);
//  - item sem id de saída legível não tem como ser registrado: a rodada para (erro 'item_malformado') e o
//    vigia devolve ou fecha a saída presa (passo 9). O mesmo item de volta na mesma rodada só é aceito depois
//    de um reagendar e com a mesma chave; com outra chave é recusado sem envio; depois de qualquer outro
//    desfecho a rodada para (erro 'item_repetido') sem enviar nem registrar de novo.
//
// ═══ F4 (P5.2): as saídas do parceiro ═══
//
// Quando retorno_pegar devolve nulo, a mesma rodada (no mesmo orçamento de tempo) passa a parceiro_pegar (C-PEGAR-P),
// e não volta a perguntar ao retorno: o retorno vem sempre antes. O item do parceiro tem origem retorno_parceiro ou
// retorno_aviso e chave "parceiro:…"; o do retorno, as origens da F1–F3 e chave "retorno:…": trocado = item torto. O
// validador do parceiro (validarSaidaAoParceiro) vale só para o item de parceiro_pegar com audiência "parceiro"; o do
// retorno com audiência "parceiro" reprova pela audiência. O painel e o pátio vêm com linhas [{n, texto}]: cada linha
// passa no validador antes do todo, e as reprovadas saem por parceiro_saida_sem_linhas (C-LINHAS), chamada uma vez; o
// texto novo é validado uma vez só. {caiu: true}, erro ou resposta torta = recusada/validador, e o texto antigo nunca
// sai. parceiro_pegar ausente (PGRST202, 42883: a edge subiu antes da migration) é silêncio.
//
// ═══ F5 (P5.2): as saídas do orçamento ═══
//
// O booleano deParceiro virou o emissor ('retorno' | 'parceiro' | 'orcamento'). A rodada pergunta aos três pegar nessa ordem
// (ORDEM_DOS_EMISSORES), na mesma rodada e no mesmo orçamento de tempo: nulo passa ao próximo, e o emissor esgotado não é
// chamado de novo. O prefixo da chave (PREFIXO_DA_CHAVE) e as origens (EMISSOR_DA_ORIGEM, a fonte única que substituiu
// ORIGENS_DO_RETORNO e ORIGENS_DO_PARCEIRO) são de cada emissor: a chave ou a origem de um emissor no item de outro é item
// torto. O item do orcamento_pegar (C-PEGAR-O: origem retorno_orcamento, chave "orcamento:…") passa em validarSaida
// (audiência "cliente"), como o do retorno. orcamento_pegar ausente (PGRST202, 42883) também é silêncio; o retorno_pegar
// ausente continua erro. O context do envio é "retorno:<id da saída>" para os três (é o que o whatsapp-send lê).
//
// Imports só do validador: nada de _shared/ai/ nem de _shared/agenda/ (isolamento_test.ts, J.1).
//
// Reverter: primeiro desligar o cron 'retorno-minuto' (P9; sem ele ninguém chama a edge), depois apagar a
// pasta supabase/functions/retorno-recibos/ e o bloco [functions.retorno-recibos] do supabase/config.toml. Só a F4:
// tirar RPC_PEGAR_PARCEIRO, RPC_SEM_LINHAS, as duas origens do parceiro e o emissor 'parceiro' da rodada. Só a F5: tirar
// RPC_PEGAR_ORCAMENTO, a origem retorno_orcamento e o emissor 'orcamento' (ORDEM_DOS_EMISSORES, RPC_DO_EMISSOR e
// PREFIXO_DA_CHAVE); as chaves "retorno:", "parceiro:" e "orcamento:" continuam de um emissor cada.

import {
  type ContextoAoParceiro,
  type ContextoDoValidador,
  type RegraDoValidador,
  validarSaida,
  validarSaidaAoParceiro,
} from "../_shared/retorno/validador.ts";

// ─── Contratos ───────────────────────────────────────────────────────────────────────────────────

export const RPC_PEGAR = "retorno_pegar";
export const RPC_PEGAR_PARCEIRO = "parceiro_pegar";
export const RPC_PEGAR_ORCAMENTO = "orcamento_pegar";
export const RPC_SEM_LINHAS = "parceiro_saida_sem_linhas";
export const RPC_DECISAO = "retorno_registrar_decisao";
export const RPC_LOG = "log_app_error";
export const RPC_CARTAO_DEVIDO = "retorno_cartao_devido";
export const RPC_CARTAO_ABRIR = "retorno_cartao_abrir";
export const RPC_CARTAO_ENVIADO = "retorno_cartao_enviado";

/** Tempo máximo de uma chamada ao whatsapp-send. Esgotado = incerta (pode ter saído). */
export const TEMPO_DO_ENVIO_MS = 25_000;

/** O que o banco responde (o formato do supabase-js). */
export interface RespostaDoBanco {
  data: unknown;
  error: { code?: string; message?: string } | null;
}

/** O pedaço do cliente do supabase-js que a rodada usa: só RPC. */
export interface Db {
  rpc(fn: string, args: Record<string, unknown>): PromiseLike<RespostaDoBanco>;
}

export interface Envio {
  phone: string;
  message: string;
  origem: string;
  context: string;
  dedupe_key: string;
}

export interface RespostaDoEnvio {
  status: number;
  body: Record<string, unknown> | null;
  erroDeRede?: boolean;
}

export interface ResumoDaRodada {
  itens: number;
  sombra: number;
  enviadas: number;
  incertas: number;
  recusadas: number;
  reagendadas: number;
  erro?: string;
}

export interface DependenciasDaRodada {
  agora: () => Date;
  enviar: (e: Envio) => Promise<RespostaDoEnvio>;
  limiteMs: number;
  maxItens: number;
}

export type EstadoDoEnvio = "enviada" | "incerta" | "recusada" | "reagendar";

/** O cartão ao dono (F2, P10.4): sem origem, é chamada de sistema, e o dono é da equipe. */
export interface EnvioAoDono {
  phone: string;
  message: string;
  dedupe_key: string;
}

export interface ResumoDoCartao {
  acao: string | null;
  erro?: string;
}

/**
 * O item que retorno_pegar devolve (contrato C-PEGAR), ou parceiro_pegar (C-PEGAR-P, F4: origem do parceiro, chave
 * "parceiro:…", validador com audiência "cliente" ou "parceiro" e, no painel e no pátio, as linhas), ou orcamento_pegar
 * (C-PEGAR-O, F5: origem retorno_orcamento, chave "orcamento:…", validador com audiência "cliente"). A rodada o lê como
 * dado não confiável.
 */
export interface ItemDoRetorno {
  saida_id: string;
  tentativa: number;
  dedupe_key: string;
  tipo: string;
  variante: string | null;
  origem:
    | "retorno_recibo"
    | "retorno_coleta"
    | "retorno_adiamento"
    | "retorno_modelo"
    | "retorno_parceiro"
    | "retorno_aviso"
    | "retorno_orcamento";
  classe: string;
  modo: "sombra" | "ligado";
  phone: string;
  texto: string;
  validador: ContextoDoValidador | ContextoAoParceiro;
  linhas?: Array<{ n: number; texto: string }>;
}

/** F5 (P5.2): quem devolveu o item. A ordem da rodada é esta: o retorno antes, depois o parceiro, depois o orçamento. */
export type Emissor = "retorno" | "parceiro" | "orcamento";
const ORDEM_DOS_EMISSORES: readonly Emissor[] = ["retorno", "parceiro", "orcamento"];
const RPC_DO_EMISSOR: Record<Emissor, string> = { retorno: RPC_PEGAR, parceiro: RPC_PEGAR_PARCEIRO, orcamento: RPC_PEGAR_ORCAMENTO };

/** O prefixo da dedupe_key de cada emissor (a chave do banco, 6.1). Chave de um emissor no item de outro = chave_invalida. */
export const PREFIXO_DA_CHAVE: Record<Emissor, string> = { retorno: "retorno:", parceiro: "parceiro:", orcamento: "orcamento:" };

/**
 * A origem de cada emissor. Substitui ORIGENS_DO_RETORNO e ORIGENS_DO_PARCEIRO (uma fonte só); as chaves são, na mesma ordem,
 * a lista ORIGENS_DO_RETORNO do whatsapp-send (_shared/whatsapp/registro-do-envio.ts).
 */
export const EMISSOR_DA_ORIGEM: Readonly<Record<string, Emissor>> = {
  retorno_recibo: "retorno",
  retorno_coleta: "retorno",
  retorno_adiamento: "retorno",
  retorno_modelo: "retorno",
  retorno_parceiro: "parceiro",
  retorno_aviso: "parceiro",
  retorno_orcamento: "orcamento",
};

// F4 e F5: a função do parceiro ou do orçamento ainda não existe no banco (a edge subiu antes da migration): silêncio,
// nunca erro. A do retorno ausente continua erro.
const FUNCAO_AUSENTE: ReadonlySet<string> = new Set(["PGRST202", "42883"]);

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// O phone_normalized do banco é só dígitos (DDI + DDD + número; E.164 tem no máximo 15).
const TELEFONE = /^\d{10,15}$/;

// Código que pode ir ao banco e ao log: curto e sem espaço (nunca a mensagem, que pode trazer dado).
const CODIGO = /^[A-Za-z0-9_.:-]{1,64}$/;

// ─── Pequenos auxiliares ─────────────────────────────────────────────────────────────────────────

function ehObjeto(v: unknown): v is Record<string, unknown> {
  return v !== null && typeof v === "object" && !Array.isArray(v);
}

function campo(v: unknown, nome: string): unknown {
  return ehObjeto(v) ? v[nome] : undefined;
}

/** Só o código do erro (ou o nome da exceção), nunca a mensagem. Sem código legível, "erro". */
function codigoDoErro(e: unknown): string {
  for (const c of [campo(e, "code"), campo(e, "name")]) {
    if (typeof c === "string" && CODIGO.test(c)) return c;
  }
  return "erro";
}

// ─── estadoDoEnvio: a resposta do whatsapp-send vira o desfecho da saída ─────────────────────────

/**
 * Mapeia a resposta do whatsapp-send (index.ts do ramo; contrato C-ENVIO) no estado que vai ao
 * retorno_registrar_decisao. Só a 503 com reserva_indisponivel reagenda (a reserva não aconteceu);
 * tudo o que pode ter saído é incerta, que é final.
 */
export function estadoDoEnvio(r: RespostaDoEnvio): { estado: EstadoDoEnvio; detalhe: Record<string, unknown> } {
  const status = r?.status;
  const corpo = ehObjeto(r?.body) ? (r.body as Record<string, unknown>) : null;
  if (r?.erroDeRede === true || typeof status !== "number" || !Number.isInteger(status) || status <= 0) {
    // Rede caída ou tempo esgotado: o pedido pode ter chegado e a mensagem, saído.
    return { estado: "incerta", detalhe: { codigo: "rede" } };
  }
  const http = { http_status: status };

  if (status >= 200 && status < 300) {
    if (corpo?.success === true) {
      const id = typeof corpo.messageId === "string" && corpo.messageId !== "" ? corpo.messageId : null;
      return {
        estado: "enviada",
        detalhe: { ...http, provider_message_id: id, ...(corpo.deduplicated === true ? { codigo: "deduplicada" } : {}) },
      };
    }
    return { estado: "incerta", detalhe: { ...http, codigo: "resposta_sem_sucesso" } };
  }
  if (status === 409) return { estado: "incerta", detalhe: { ...http, codigo: "em_andamento" } };
  if (status === 422) {
    if (corpo?.recusado === true) {
      const codigo = typeof corpo.codigo === "string" && CODIGO.test(corpo.codigo) ? corpo.codigo : "recusado";
      return { estado: "recusada", detalhe: { ...http, motivo: "canal", codigo } };
    }
    return { estado: "recusada", detalhe: { ...http, motivo: "provedor" } };
  }
  if (status === 503 && corpo?.reserva_indisponivel === true) {
    return { estado: "reagendar", detalhe: { ...http, codigo: "reserva_indisponivel" } };
  }
  if (status === 502) {
    if (corpo?.incerto === true) return { estado: "incerta", detalhe: { ...http, codigo: "incerto" } };
    // O 502 do whatsapp-send sempre traz "error": é a falha certa do provedor, com a chave liberada.
    if (typeof corpo?.error === "string") return { estado: "recusada", detalhe: { ...http, motivo: "provedor" } };
    return { estado: "incerta", detalhe: { ...http, codigo: "resposta_ilegivel" } };
  }
  if (status >= 500) return { estado: "incerta", detalhe: { ...http, codigo: "erro_do_servidor" } };
  if (status >= 400) return { estado: "recusada", detalhe: { ...http, motivo: "provedor" } };
  return { estado: "incerta", detalhe: { ...http, codigo: "status_inesperado" } };
}

// ─── O envio pelo whatsapp-send (contrato C-ENVIO) ───────────────────────────────────────────────

/**
 * O `enviar` de produção: POST no whatsapp-send com a chave de serviço (chamada de sistema: só assim as
 * origens do retorno valem). Nunca lança: rede caída e tempo esgotado viram `erroDeRede`; corpo que não é
 * um objeto JSON vira `body: null`.
 */
export function envioPeloWhatsappSend(
  supabaseUrl: string,
  chaveDeServico: string,
  buscar: typeof fetch = fetch,
  tempoMs: number = TEMPO_DO_ENVIO_MS,
): (e: Envio) => Promise<RespostaDoEnvio> {
  const url = supabaseUrl.replace(/\/+$/, "") + "/functions/v1/whatsapp-send";
  return async (e: Envio): Promise<RespostaDoEnvio> => {
    let res: Response;
    try {
      res = await buscar(url, {
        method: "POST",
        headers: { Authorization: "Bearer " + chaveDeServico, "Content-Type": "application/json" },
        body: JSON.stringify({
          phone: e.phone,
          kind: "text",
          message: e.message,
          origem: e.origem,
          context: e.context,
          dedupe_key: e.dedupe_key,
        }),
        signal: AbortSignal.timeout(tempoMs),
      });
    } catch {
      return { status: 0, body: null, erroDeRede: true };
    }
    let body: Record<string, unknown> | null = null;
    try {
      const lido: unknown = await res.json();
      body = ehObjeto(lido) ? lido : null;
    } catch {
      body = null;
    }
    return { status: res.status, body };
  };
}

// ─── Conversa com o banco ────────────────────────────────────────────────────────────────────────

type Pegou = { erro: string } | { dado: unknown };

/**
 * retorno_pegar, parceiro_pegar ou orcamento_pegar. A do parceiro ou a do orçamento ausente no banco (PGRST202, 42883) vale
 * como fila vazia; a do retorno ausente é erro.
 */
async function pegar(db: Db, agora: Date, rpc: string = RPC_PEGAR): Promise<Pegou> {
  try {
    const { data, error } = await db.rpc(rpc, { p_agora: agora.toISOString() });
    if (error) {
      const codigo = codigoDoErro(error);
      if (rpc !== RPC_PEGAR && FUNCAO_AUSENTE.has(codigo)) return { dado: null };
      return { erro: codigo };
    }
    return { dado: data ?? null };
  } catch (e) {
    return { erro: codigoDoErro(e) };
  }
}

/** F4 (C-LINHAS): o texto sem as linhas reprovadas, ou o motivo de recusar o item inteiro. Nunca lança. */
async function semLinhas(
  db: Db,
  saida: string,
  reprovadas: Array<{ n: number; regras: RegraDoValidador[] }>,
  agora: Date,
): Promise<{ texto: string; validador: unknown } | { codigo: "linhas_caiu" | "sem_linhas_erro" }> {
  try {
    const { data, error } = await db.rpc(RPC_SEM_LINHAS, {
      p_saida: saida,
      p_ns: reprovadas.map((r) => r.n),
      p_regras: reprovadas,
      p_agora: agora.toISOString(),
    });
    if (error) return { codigo: "sem_linhas_erro" };
    if (campo(data, "caiu") === true) return { codigo: "linhas_caiu" };
    const texto = campo(data, "texto");
    if (typeof texto !== "string" || texto === "") return { codigo: "sem_linhas_erro" };
    return { texto, validador: campo(data, "validador") };
  } catch {
    return { codigo: "sem_linhas_erro" };
  }
}

/** F4: as linhas do painel e do pátio, conferidas: [{n inteiro ≥ 1, texto}]. null = torta (ou faltando onde é exigida). */
function linhasDoItem(item: Record<string, unknown>): Array<{ n: number; texto: string }> | null {
  const linhas = item.linhas;
  if (!Array.isArray(linhas) || linhas.length === 0) return null;
  const lidas: Array<{ n: number; texto: string }> = [];
  for (const l of linhas) {
    const n = campo(l, "n");
    const texto = campo(l, "texto");
    if (typeof n !== "number" || !Number.isInteger(n) || n < 1 || typeof texto !== "string") return null;
    lidas.push({ n, texto });
  }
  return lidas;
}

/** F4: o painel e o pátio com linhas (o pátio "vazio" não tem). */
function temLinhas(item: Record<string, unknown>): boolean {
  return item.tipo === "parceiro_painel" || (item.tipo === "parceiro_patio" && item.variante !== "vazio");
}

/** Registra o desfecho (C-DECISAO). Falha (erro, `ok` diferente de true, exceção) vai ao log; nunca lança. */
async function registrar(db: Db, saida: string, estado: string, detalhe: Record<string, unknown>): Promise<void> {
  let codigo: string;
  try {
    const { data, error } = await db.rpc(RPC_DECISAO, { p_saida: saida, p_estado: estado, p_detalhe: detalhe });
    if (!error && campo(data, "ok") === true) return;
    const doBanco = campo(data, "erro");
    codigo = error ? codigoDoErro(error) : typeof doBanco === "string" && CODIGO.test(doBanco) ? doBanco : "sem_ok";
  } catch (e) {
    codigo = codigoDoErro(e);
  }
  console.error(`[retorno-recibos] decisão não registrada: saída ${saida}, estado ${estado}, ${codigo}`);
  try {
    // log_app_error agrupa pela mensagem sem números e ids: a mensagem é fixa, o resto vai em details.
    await db.rpc(RPC_LOG, {
      p_source: "edge",
      p_message: "retorno-recibos: a decisão da saída não foi registrada",
      p_context: "retorno-recibos",
      p_action: "registrar",
      p_level: "error",
      p_details: { saida, estado, codigo },
    });
  } catch {
    /* um log que derruba a rodada seria pior que não ter log */
  }
}

// ─── O item ──────────────────────────────────────────────────────────────────────────────────────

/**
 * O problema do item que impede o envio (e o registro honesto na sombra), ou null. Cada emissor tem as origens dele
 * (EMISSOR_DA_ORIGEM) e o prefixo da chave dele (PREFIXO_DA_CHAVE): F1–F3 "retorno:…", F4 "parceiro:…", F5 "orcamento:…".
 */
function problemaDoItem(item: Record<string, unknown>, emissor: Emissor): string | null {
  if (item.modo !== "sombra" && item.modo !== "ligado") return "modo_desconhecido";
  if (typeof item.origem !== "string" || EMISSOR_DA_ORIGEM[item.origem] !== emissor) return "origem_invalida";
  if (typeof item.phone !== "string" || !TELEFONE.test(item.phone)) return "telefone_invalido";
  const chave = item.dedupe_key;
  const prefixo = PREFIXO_DA_CHAVE[emissor];
  if (typeof chave !== "string" || !chave.startsWith(prefixo) || chave.length <= prefixo.length || chave.length > 200) {
    return "chave_invalida";
  }
  return null;
}

/**
 * O validador do item. F4: o texto À PARCEIRA (item de parceiro_pegar que não é o aviso ao cliente final) passa em
 * validarSaidaAoParceiro, e o contexto tem de ter audiência "parceiro"; todo o resto (o retorno e o aviso ao cliente
 * final, retorno_aviso) passa em validarSaida. Nos dois, audiência ausente reprova com 'contexto' e outra com
 * 'audiencia', como hoje: um contexto "cliente" nunca faz o texto à parceira passar pelo validador do cliente.
 */
function validar(texto: unknown, ctx: unknown, aoParceiro = false): RegraDoValidador[] {
  try {
    const t = typeof texto === "string" ? texto : "";
    const r = aoParceiro
      ? validarSaidaAoParceiro(t, ctx as ContextoAoParceiro)
      : validarSaida(t, ctx as ContextoDoValidador | null | undefined);
    return r.ok ? [] : [...r.regras];
  } catch {
    return ["erro"]; // o validador nunca lança; se lançar, reprova
  }
}

/** O enviar injetado, sem lançar: exceção ou resposta torta = erro de rede (incerta). */
async function enviarSemLancar(enviar: DependenciasDaRodada["enviar"], e: Envio): Promise<RespostaDoEnvio> {
  try {
    const r = await enviar(e);
    return ehObjeto(r) ? r : { status: 0, body: null, erroDeRede: true };
  } catch {
    return { status: 0, body: null, erroDeRede: true };
  }
}

// ─── A rodada ────────────────────────────────────────────────────────────────────────────────────

/**
 * Laço até `limiteMs` (pelo relógio de `agora`) ou `maxItens`: pega, valida, registra (sombra) ou envia e
 * registra (ligado). Nunca lança; `erro` diz por que a rodada parou antes da hora.
 */
export async function rodada(db: Db, deps: DependenciasDaRodada): Promise<ResumoDaRodada> {
  const resumo: ResumoDaRodada = { itens: 0, sombra: 0, enviadas: 0, incertas: 0, recusadas: 0, reagendadas: 0 };
  // saída → a chave com que foi tentada e se o desfecho foi reagendar (a única volta permitida)
  const tentadas = new Map<string, { chave: unknown; reagendada: boolean }>();
  // F5 (P5.2): o índice do emissor da vez em ORDEM_DOS_EMISSORES. Esgotado um emissor nesta rodada, nunca se volta a ele.
  let fila = 0;
  try {
    const inicio = deps.agora().getTime();
    while (resumo.itens < deps.maxItens && deps.agora().getTime() - inicio < deps.limiteMs) {
      // 1. Pegar: o retorno antes; nulo, o parceiro (F4); nulo, o orçamento (F5). Tudo no mesmo orçamento de tempo.
      let emissor: Emissor = ORDEM_DOS_EMISSORES[0];
      let dado: unknown = null;
      let erroAoPegar: string | null = null;
      while (fila < ORDEM_DOS_EMISSORES.length) {
        emissor = ORDEM_DOS_EMISSORES[fila];
        const pegou = await pegar(db, deps.agora(), RPC_DO_EMISSOR[emissor]);
        if ("erro" in pegou) {
          erroAoPegar = pegou.erro;
          break;
        }
        dado = pegou.dado;
        if (dado !== null) break;
        fila++;
      }
      if (erroAoPegar !== null) {
        resumo.erro = erroAoPegar;
        break;
      }
      if (dado === null) break;
      const deParceiro = emissor === "parceiro";
      resumo.itens++;

      const item = dado;
      const id = campo(item, "saida_id");
      if (!ehObjeto(item) || typeof id !== "string" || !UUID.test(id)) {
        console.error("[retorno-recibos] item sem id de saída legível: rodada parada");
        resumo.erro = "item_malformado";
        break;
      }
      const saida = id.toLowerCase();
      const antes = tentadas.get(saida);
      if (antes && !antes.reagendada) {
        console.error(`[retorno-recibos] saída ${saida} voltou na mesma rodada sem reagendar: rodada parada`);
        resumo.erro = "item_repetido";
        break;
      }

      // 2. Validar (também na sombra).
      let problema = antes && antes.chave !== item.dedupe_key ? "chave_trocada" : problemaDoItem(item, emissor);
      let texto: unknown = item.texto;
      let ctx: unknown = item.validador;
      // F4: o validador é escolhido pela origem (de parceiro_pegar, só o aviso ao cliente final, retorno_aviso, vai ao
      //     validador do cliente), e o contexto tem de bater.
      const aoParceiro = deParceiro && item.origem !== "retorno_aviso";

      // 2a. F4: o painel e o pátio, linha a linha. A linha reprovada sai (parceiro_saida_sem_linhas, uma chamada) e o
      //     resto segue; o texto novo é validado uma vez só, abaixo. Nunca sai o texto antigo.
      if (problema === null && deParceiro && temLinhas(item)) {
        const linhas = linhasDoItem(item);
        if (linhas === null) {
          problema = "linhas_invalidas";
        } else {
          const reprovadas = linhas
            .map((l) => ({ n: l.n, regras: validar(l.texto, ctx, aoParceiro) }))
            .filter((l) => l.regras.length > 0);
          if (reprovadas.length > 0) {
            const novo = await semLinhas(db, saida, reprovadas, deps.agora());
            if ("codigo" in novo) {
              await registrar(db, saida, "recusada", {
                motivo: "validador",
                regras: [...new Set(reprovadas.flatMap((l) => l.regras))],
                codigo: novo.codigo,
              });
              resumo.recusadas++;
              tentadas.set(saida, { chave: item.dedupe_key, reagendada: false });
              continue;
            }
            texto = novo.texto;
            ctx = novo.validador;
          }
        }
      }

      const regras = validar(texto, ctx, aoParceiro);
      if (problema !== null && !regras.includes("contexto")) regras.push("contexto");
      if (regras.length > 0) {
        await registrar(db, saida, "recusada", {
          motivo: "validador",
          regras,
          ...(problema !== null ? { codigo: problema } : {}),
        });
        resumo.recusadas++;
        tentadas.set(saida, { chave: item.dedupe_key, reagendada: false });
        continue;
      }

      // 3. Sombra: só registra o "eu teria mandado".
      if (item.modo === "sombra") {
        await registrar(db, saida, "sombra", { validador: { ok: true } });
        resumo.sombra++;
        tentadas.set(saida, { chave: item.dedupe_key, reagendada: false });
        continue;
      }

      // 4. Ligado: envia com a chave do banco e registra o desfecho.
      const chave = item.dedupe_key as string;
      const resposta = await enviarSemLancar(deps.enviar, {
        phone: item.phone as string,
        message: texto as string,
        origem: item.origem as string,
        context: "retorno:" + saida,
        dedupe_key: chave,
      });
      const { estado, detalhe } = estadoDoEnvio(resposta);
      tentadas.set(saida, { chave, reagendada: estado === "reagendar" });
      await registrar(db, saida, estado, { validador: { ok: true }, ...detalhe });
      if (estado === "enviada") resumo.enviadas++;
      else if (estado === "incerta") resumo.incertas++;
      else if (estado === "recusada") resumo.recusadas++;
      else resumo.reagendadas++;
    }
  } catch (e) {
    // Só o relógio injetado poderia lançar aqui: o resto já se protege.
    resumo.erro = codigoDoErro(e);
  }
  return resumo;
}

// ─── rodadaDoCartao (F2, P10.4): o cartão do meio-dia e do acorde ────────────────────────────────────────────────────

/** O envio ao dono: o mesmo POST, sem origem e sem contexto. */
export function envioAoDonoPeloWhatsappSend(
  supabaseUrl: string,
  chaveDeServico: string,
  buscar: typeof fetch = fetch,
  tempoMs: number = TEMPO_DO_ENVIO_MS,
): (e: EnvioAoDono) => Promise<RespostaDoEnvio> {
  const url = supabaseUrl.replace(/\/+$/, "") + "/functions/v1/whatsapp-send";
  return async (e: EnvioAoDono): Promise<RespostaDoEnvio> => {
    let res: Response;
    try {
      res = await buscar(url, {
        method: "POST",
        headers: { Authorization: "Bearer " + chaveDeServico, "Content-Type": "application/json" },
        body: JSON.stringify({ phone: e.phone, kind: "text", message: e.message, dedupe_key: e.dedupe_key }),
        signal: AbortSignal.timeout(tempoMs),
      });
    } catch {
      return { status: 0, body: null, erroDeRede: true };
    }
    let body: Record<string, unknown> | null = null;
    try {
      const lido: unknown = await res.json();
      body = ehObjeto(lido) ? lido : null;
    } catch {
      body = null;
    }
    return { status: res.status, body };
  };
}

/** O dia local de Brasília (sem horário de verão desde 2019). */
function diaDeBrasilia(agora: Date): string {
  return new Date(agora.getTime() - 3 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

/**
 * Antes da rodada dos recibos, e nunca lança. retorno_cartao_devido diz se há cartão a abrir; ocupado, ja_vivo e vazio o
 * banco já resolveu, e aqui só se anota. Cartão ou lista vão ao dono, e o resultado volta a retorno_cartao_enviado.
 */
export async function rodadaDoCartao(
  db: Db,
  deps: { agora: () => Date; enviarAoDono: (e: EnvioAoDono) => Promise<RespostaDoEnvio> },
): Promise<ResumoDoCartao> {
  try {
    const agora = deps.agora();
    const pAgora = agora.toISOString();
    const devido = await db.rpc(RPC_CARTAO_DEVIDO, { p_agora: pAgora });
    if (devido.error) return { acao: null, erro: codigoDoErro(devido.error) };
    if (!ehObjeto(devido.data)) return { acao: null };
    const gatilho = devido.data.gatilho;
    if (typeof gatilho !== "string") return { acao: null, erro: "devido_ilegivel" };

    const aberto = await db.rpc(RPC_CARTAO_ABRIR, {
      p_gatilho: gatilho,
      p_agora: pAgora,
      p_aviso: typeof devido.data.aviso_id === "string" ? devido.data.aviso_id : null,
    });
    if (aberto.error) return { acao: null, erro: codigoDoErro(aberto.error) };
    if (!ehObjeto(aberto.data)) return { acao: null, erro: "abrir_ilegivel" };
    const acao = typeof aberto.data.acao === "string" ? aberto.data.acao : null;
    if (acao !== "cartao" && acao !== "lista") return { acao };

    const { cartao_id: cartao, phone, texto } = aberto.data;
    if (typeof cartao !== "string" || typeof phone !== "string" || typeof texto !== "string") {
      return { acao, erro: "abrir_incompleto" };
    }
    const dedupe = gatilho === "meio_dia" ? `retorno-cartao:meio_dia:${diaDeBrasilia(agora)}` : `retorno-cartao:${cartao}`;
    const r = await deps.enviarAoDono({ phone, message: texto, dedupe_key: dedupe });
    const ok = r.status >= 200 && r.status < 300 && r.body?.success === true;
    const waId = ok && typeof r.body?.messageId === "string" ? r.body.messageId : null;
    await db.rpc(RPC_CARTAO_ENVIADO, { p_cartao: cartao, p_ok: ok, p_wa_id: waId, p_agora: pAgora });
    return ok ? { acao } : { acao, erro: "envio_falhou" };
  } catch (e) {
    return { acao: null, erro: codigoDoErro(e) };
  }
}
