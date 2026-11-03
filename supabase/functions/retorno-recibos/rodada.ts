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
//    retorno_saida_autorizada), telefone só de dígitos e dedupe_key "retorno:…" (chave de outro emissor
//    já concluída faria o whatsapp-send responder "já enviado" sem nada sair). Item torto = recusada/validador
//    com a regra 'contexto' e o código do problema: três na mesma hora rebaixam o tipo (vigia, passo 10);
//  - item sem id de saída legível não tem como ser registrado: a rodada para (erro 'item_malformado') e o
//    vigia devolve ou fecha a saída presa (passo 9). O mesmo item de volta na mesma rodada só é aceito depois
//    de um reagendar e com a mesma chave; com outra chave é recusado sem envio; depois de qualquer outro
//    desfecho a rodada para (erro 'item_repetido') sem enviar nem registrar de novo.
//
// Imports só do validador: nada de _shared/ai/ nem de _shared/agenda/ (isolamento_test.ts, J.1).
//
// Reverter: primeiro desligar o cron 'retorno-minuto' (P9; sem ele ninguém chama a edge), depois apagar a
// pasta supabase/functions/retorno-recibos/ e o bloco [functions.retorno-recibos] do supabase/config.toml.

import { type ContextoDoValidador, type RegraDoValidador, validarSaida } from "../_shared/retorno/validador.ts";

// ─── Contratos ───────────────────────────────────────────────────────────────────────────────────

export const RPC_PEGAR = "retorno_pegar";
export const RPC_DECISAO = "retorno_registrar_decisao";
export const RPC_LOG = "log_app_error";

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

/** O item que retorno_pegar devolve (contrato C-PEGAR). A rodada o lê como dado não confiável. */
export interface ItemDoRetorno {
  saida_id: string;
  tentativa: number;
  dedupe_key: string;
  tipo: string;
  variante: string | null;
  origem: "retorno_recibo" | "retorno_coleta" | "retorno_adiamento";
  classe: string;
  modo: "sombra" | "ligado";
  phone: string;
  texto: string;
  validador: ContextoDoValidador;
}

const ORIGENS_DO_RETORNO: ReadonlySet<string> = new Set(["retorno_recibo", "retorno_coleta", "retorno_adiamento"]);

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

async function pegar(db: Db, agora: Date): Promise<Pegou> {
  try {
    const { data, error } = await db.rpc(RPC_PEGAR, { p_agora: agora.toISOString() });
    if (error) return { erro: codigoDoErro(error) };
    return { dado: data ?? null };
  } catch (e) {
    return { erro: codigoDoErro(e) };
  }
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

/** O problema do item que impede o envio (e o registro honesto na sombra), ou null. */
function problemaDoItem(item: Record<string, unknown>): string | null {
  if (item.modo !== "sombra" && item.modo !== "ligado") return "modo_desconhecido";
  if (typeof item.origem !== "string" || !ORIGENS_DO_RETORNO.has(item.origem)) return "origem_invalida";
  if (typeof item.phone !== "string" || !TELEFONE.test(item.phone)) return "telefone_invalido";
  const chave = item.dedupe_key;
  if (typeof chave !== "string" || !chave.startsWith("retorno:") || chave.length > 200) return "chave_invalida";
  return null;
}

function validar(texto: unknown, ctx: unknown): RegraDoValidador[] {
  try {
    const r = validarSaida(typeof texto === "string" ? texto : "", ctx as ContextoDoValidador | null | undefined);
    return r.ok ? [] : [...r.regras];
  } catch {
    return ["erro"]; // validarSaida nunca lança; se lançar, reprova
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
  try {
    const inicio = deps.agora().getTime();
    while (resumo.itens < deps.maxItens && deps.agora().getTime() - inicio < deps.limiteMs) {
      // 1. Pegar.
      const pegou = await pegar(db, deps.agora());
      if ("erro" in pegou) {
        resumo.erro = pegou.erro;
        break;
      }
      if (pegou.dado === null) break;
      resumo.itens++;

      const item = pegou.dado;
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
      const problema = antes && antes.chave !== item.dedupe_key ? "chave_trocada" : problemaDoItem(item);
      const regras = validar(item.texto, item.validador);
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
        message: item.texto as string,
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
