// A orquestração da edge comprovantes-whatsapp (F1, 11/10/2026 — spec-f1-final.md, seções 3 e 6).
//
// Quem decide é o BANCO (as RPCs da M3): número do CMP, duplicado, encaminhar ao assistente, aviso,
// novas tentativas. Esta camada só faz o que o banco não alcança: baixar a mídia da Evolution,
// guardar no bucket, subir no Dropbox, reagir/avisar no WhatsApp e chamar o assistente — sempre
// quando a RPC devolve a ordem (encaminhar=true, subir_dropbox=true, itens do aviso).
//
// Dependências injetadas (admin, WhatsApp, Dropbox, fetch, relógio, log) para os testes rodarem
// sem rede. Logs: só ids, códigos de erro, decisões e tempos — nunca legenda, texto, valor, CNPJ
// ou nome (erro do banco vira só o código: a mensagem do Postgres pode trazer a linha recusada).
import { EvolutionProvider } from "../whatsapp/evolution-provider.ts";
import type { IncomingMessageEvent } from "../whatsapp/types.ts";
import { type Dono, donoDoWhatsApp } from "../whatsapp/dono.ts";
import { pendenciaQueSegueEsperando, resolveOrCreateWhatsAppSession } from "../ai/whatsapp-channel.ts";
import { logEdgeError } from "../log-error.ts";
import { lerModoDoComprovante } from "./modo.ts";
import {
  caminhoNoBucket,
  chaveDoAviso,
  type DadosDoArquivo,
  historicoDoAviso,
  type ItemDoAviso,
  lerLegenda,
  nomeNoDropbox,
  PASTA_A_CLASSIFICAR,
  textoDoAviso,
} from "./nucleo.ts";
import {
  baixarMidiaPelaChave,
  type ChaveDaMensagem,
  chaveConfere,
  chaveDoPayload,
  LIMITE_BYTES,
  type ResultadoDoDownload,
  sha256Hex,
  tamanhoDeclarado,
  tipoReal,
} from "./midia.ts";

export const BUCKET = "comprovantes";
/** URL assinada de 24 h (decisão 3: o prazo do job também é de 24 h). */
const VALIDADE_DA_URL_S = 86_400;
/** Folga para a função terminar antes do timeout de 60 s do pg_net que chama o vigia (M4). */
export const ORCAMENTO_DO_VIGIA_MS = 45_000;
const LIMITE_DO_VIGIA = 10;
const LIMITE_DA_REPESCAGEM = 20;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// deno-lint-ignore no-explicit-any
type Admin = any;

export type DropboxDoFluxo = {
  enviar(caminho: string, bytes: Uint8Array<ArrayBuffer>, autorename?: boolean): Promise<{ id: string; path_display: string; rev: string }>;
};

export type CamposDoLog = Record<string, string | number | boolean | null | undefined>;

export type DependenciasDoFluxo = {
  admin: Admin;
  whatsapp: { sendReaction?(to: string, messageId: string, fromMe: boolean, emoji: string): Promise<unknown> } | null;
  dropbox(): Promise<DropboxDoFluxo | null>;
  fetch: typeof fetch;
  agora(): Date;
  log(evento: string, campos?: CamposDoLog): void;
  supabaseUrl: string;
  serviceRoleKey: string;
  internalSecret: string;
  /** EdgeRuntime.waitUntil; sem ele, a promessa roda solta (com catch). */
  waitUntil?(p: Promise<unknown>): void;
  /** Para os testes; o padrão é baixarMidiaPelaChave (com a key guardada na linha). */
  baixar?(chave: ChaveDaMensagem): Promise<ResultadoDoDownload>;
  /** Para os testes; o padrão é resolveOrCreateWhatsAppSession. */
  sessaoDoWhatsApp?(phone: string, donoId: string): Promise<string>;
};

/** Log padrão da função: uma linha JSON, só com os campos seguros que quem chama passou. */
export function logDoFluxo(evento: string, campos: CamposDoLog = {}): void {
  console.log(JSON.stringify({ fn: "comprovantes-whatsapp", evento, ...campos }));
}

/** Falha com código (nunca conteúdo): vira o `erro` da resposta e o app_error_logs. */
export class FalhaDoFluxo extends Error {
  constructor(readonly codigo: string) {
    super(codigo);
  }
}

export function codigoDoErro(e: unknown): string {
  if (e instanceof FalhaDoFluxo) return e.codigo;
  return `erro_inesperado:${(e as Error)?.name ?? "desconhecido"}`;
}

// deno-lint-ignore no-explicit-any
async function rpc<T = any>(deps: DependenciasDoFluxo, nome: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await deps.admin.rpc(nome, args);
  if (error) throw new FalhaDoFluxo(`${nome}:${error.code ?? "erro"}`);
  return data as T;
}

/** Roda em segundo plano (waitUntil); a falha vira log com código, nunca exceção solta. */
function emSegundoPlano(deps: DependenciasDoFluxo, acao: string, p: Promise<unknown>): void {
  const guardada = p.catch(async (e) => {
    const codigo = codigoDoErro(e);
    deps.log("segundo_plano_falhou", { acao, codigo });
    await logEdgeError(deps.admin, { context: "comprovantes-whatsapp", message: codigo, action: acao });
  });
  if (deps.waitUntil) deps.waitUntil(guardada);
}

const PARSER = new EvolutionProvider({ apiUrl: "", apiKey: "", instance: "" });

function reparse(raw: unknown): IncomingMessageEvent | null {
  return PARSER.parseIncomingWebhook(raw);
}

function corte(s: string | null | undefined, max: number): string | null {
  if (typeof s !== "string" || !s) return null;
  return s.length <= max ? s : s.slice(0, max);
}

async function reagir(deps: DependenciasDoFluxo, phone: string | null | undefined, waId: string | null | undefined, emoji: string): Promise<void> {
  if (!phone || !waId || !deps.whatsapp?.sendReaction) return;
  try {
    await deps.whatsapp.sendReaction(phone, waId, false, emoji);
  } catch {
    deps.log("reacao_falhou", { emoji: emoji || "remover" });
  }
}

type Mensagem = {
  id: string;
  wa_message_id: string | null;
  phone_normalized: string;
  message_type: string;
  direction?: string;
  raw_payload: unknown;
  occurred_at: string;
};

async function lerMensagem(deps: DependenciasDoFluxo, id: string): Promise<Mensagem | null> {
  const { data, error } = await deps.admin
    .from("whatsapp_messages")
    .select("id, wa_message_id, phone_normalized, message_type, direction, raw_payload, occurred_at")
    .eq("id", id)
    .maybeSingle();
  if (error) throw new FalhaDoFluxo(`ler_mensagem:${error.code ?? "erro"}`);
  return (data as Mensagem | null) ?? null;
}

type RespostaDoReceber = { id: string; novo: boolean; situacao: string };

/**
 * comprovante_receber com o que o parser leu da mensagem gravada (legenda = só o caption) e a key
 * da Evolution JÁ conferida: é a cópia que o download usa daqui em diante (comprovantes.wa_key).
 */
async function registrar(
  deps: DependenciasDoFluxo,
  msg: Mensagem,
  ev: IncomingMessageEvent,
  chave: ChaveDaMensagem | null,
  p: { modo: "sombra" | "dono"; rota: "comprovante" | "ambos"; origem: "webhook" | "repescagem"; dono: Dono },
): Promise<{ ok: true; r: RespostaDoReceber } | { ok: false; motivo: string }> {
  const legenda = lerLegenda(ev.caption);
  const { data, error } = await deps.admin.rpc("comprovante_receber", {
    p: {
      message_id: msg.id,
      wa_message_id: msg.wa_message_id,
      wa_key: chave,
      phone_normalized: msg.phone_normalized,
      dono_id: p.dono.id,
      modo: p.modo,
      rota: p.rota,
      origem: p.origem,
      tipo_whatsapp: ev.mediaKind,
      forcado: legenda.forcado,
      legenda: corte(ev.caption, 1024),
      dica_da_legenda: corte(legenda.dica, 1024),
      nome_arquivo: corte(ev.fileName, 255),
      mime_declarado: corte(ev.mimetype, 100),
      recebido_em: msg.occurred_at,
    },
  });
  if (error?.code === "42501") return { ok: false, motivo: "dono_divergente" };
  if (error?.code === "22023") return { ok: false, motivo: "entrada_recusada" };
  if (error) throw new FalhaDoFluxo(`comprovante_receber:${error.code ?? "erro"}`);
  return { ok: true, r: data as RespostaDoReceber };
}

// ---------------------------------------------------------------------------------------------
// receber (porta chamadaInterna: só o whatsapp-webhook)
// ---------------------------------------------------------------------------------------------

export type CorpoDaResposta = { aceito: boolean; id?: string; novo?: boolean; motivo?: string };

export async function receber(
  p: { message_id: string; modo: string; rota: string; dono_id: string },
  deps: DependenciasDoFluxo,
): Promise<{ status: 200 | 422; corpo: CorpoDaResposta }> {
  const recusar = (motivo: string) => {
    deps.log("receber_recusado", { motivo });
    return { status: 422 as const, corpo: { aceito: false, motivo } };
  };
  if (
    typeof p?.message_id !== "string" || !UUID.test(p.message_id) ||
    typeof p?.dono_id !== "string" || !UUID.test(p.dono_id) ||
    (p.modo !== "sombra" && p.modo !== "dono") ||
    (p.rota !== "comprovante" && p.rota !== "ambos")
  ) return recusar("entrada_invalida");
  const modo = p.modo;
  const rota = p.rota;

  const msg = await lerMensagem(deps, p.message_id);
  if (!msg) return recusar("mensagem_inexistente");
  if (msg.direction !== "inbound") return recusar("nao_e_recebida");
  const dono = await donoDoWhatsApp(deps.admin);
  if (!dono || dono.id !== p.dono_id || dono.phone !== msg.phone_normalized) return recusar("dono_divergente");
  if (!msg.wa_message_id) return recusar("sem_wa_message_id");
  const ev = reparse(msg.raw_payload);
  if (!ev?.mediaKind) return recusar("sem_midia");
  // key de outra conversa ou enviada pelo sistema: o webhook cai no despacho de hoje (422)
  const chave = chaveDoPayload(msg.raw_payload);
  if (chave && !chaveConfere(chave, msg.phone_normalized, msg.wa_message_id)) return recusar("chave_divergente");

  const reg = await registrar(deps, msg, ev, chave, { modo, rota, origem: "webhook", dono });
  if (!reg.ok) return recusar(reg.motivo);
  const { r } = reg;
  deps.log("recebido", { id: r.id, novo: r.novo, rota, modo });
  if (!r.novo) return { status: 200, corpo: { aceito: true, id: r.id, novo: false } };

  emSegundoPlano(deps, "processar", (async () => {
    if (modo === "dono") await reagir(deps, msg.phone_normalized, msg.wa_message_id, "⏳");
    await processarArquivo({
      id: r.id,
      chave,
      phone: msg.phone_normalized,
      wa_message_id: msg.wa_message_id,
      recebido_em: msg.occurred_at,
      tamanho_declarado: tamanhoDeclarado(msg.raw_payload),
    }, deps);
  })());
  return { status: 200, corpo: { aceito: true, id: r.id, novo: true } };
}

// ---------------------------------------------------------------------------------------------
// processarArquivo: baixa, confere o tipo real, guarda no bucket e entrega ao banco
// ---------------------------------------------------------------------------------------------

type ResultadoDaFalha = {
  id: string;
  final: boolean;
  proxima_em?: string | null;
  situacao?: string;
  encaminhar?: boolean;
  texto_para_assistente?: string | null;
  modo?: string;
  forcado?: boolean;
  phone_normalized?: string;
  wa_message_id?: string;
  dono_id?: string;
  /** A linha já não estava em "recebido" (outra chamada chegou antes): nada a fazer aqui. */
  ignorado?: boolean;
};

async function finalizarFalha(r: ResultadoDaFalha | null, deps: DependenciasDoFluxo): Promise<void> {
  if (!r?.final || r.ignorado) return;
  if (r.encaminhar && r.texto_para_assistente && r.phone_normalized && r.dono_id) {
    encaminharEmSegundoPlano({ phone: r.phone_normalized, dono_id: r.dono_id, texto: r.texto_para_assistente }, deps);
  }
  if (r.modo === "dono" && r.phone_normalized) {
    await reagir(deps, r.phone_normalized, r.wa_message_id, "");
    await talvezAvisar(r.phone_normalized, false, deps);
  }
}

async function falhaDeDownload(id: string, erro: string, deps: DependenciasDoFluxo): Promise<string> {
  const r = await rpc<ResultadoDaFalha>(deps, "comprovante_download_falhou", { p_id: id, p_erro: erro });
  deps.log("download_falhou", { id, erro, final: Boolean(r?.final) });
  await finalizarFalha(r, deps);
  return r?.final ? "falhou" : "tentar_de_novo";
}

async function falhaFinal(id: string, erro: string, deps: DependenciasDoFluxo): Promise<string> {
  const r = await rpc<ResultadoDaFalha>(deps, "comprovante_falhou", { p_id: id, p_erro: erro });
  deps.log("falhou", { id, erro, ignorado: Boolean(r?.ignorado) });
  await finalizarFalha(r, deps);
  return "falhou";
}

/** O que o download precisa, tudo da linha de comprovantes (nunca relido de whatsapp_messages). */
export type ItemParaBaixar = {
  id: string;
  /** comprovantes.wa_key: a key conferida na chegada. */
  chave: unknown;
  /** comprovantes.phone_normalized e wa_message_id: a key tem de ser desta conversa e desta mensagem. */
  phone: string | null | undefined;
  wa_message_id: string | null | undefined;
  /** comprovantes.recebido_em (o mês do caminho no bucket). */
  recebido_em: string | null | undefined;
  /** fileLength declarado pelo WhatsApp, quando o payload está à mão (só na chegada). */
  tamanho_declarado?: number | null;
};

/**
 * Baixa a mídia, confere o tipo pelos bytes, guarda em comprovantes/AAAA/MM/<id>.<ext> e chama
 * comprovante_guardar_arquivo (que cria o job do leitor, ou acusa o duplicado).
 * Devolve a decisão (para log e teste).
 *
 * Toda falha tem desfecho: a esperada vira o código dela; a inesperada (exceção da RPC, do Storage,
 * bug) vira upload_falhou, que conta nas 3 tentativas e depois encerra encaminhando ao assistente.
 * O objeto que subiu e ficou sem dono é apagado na hora (senão nunca entraria na lista do vigia).
 */
export async function processarArquivo(item: ItemParaBaixar, deps: DependenciasDoFluxo): Promise<string> {
  const bucket = deps.admin.storage.from(BUCKET);
  let semDono: string | null = null; // caminho que subiu e o banco ainda não registrou
  try {
    if (!chaveConfere(item.chave, item.phone, item.wa_message_id)) return await falhaDeDownload(item.id, "sem_chave", deps);
    const chave = item.chave;

    const declarado = item.tamanho_declarado ?? null;
    if (declarado !== null && declarado > LIMITE_BYTES) return await falhaFinal(item.id, "arquivo_grande", deps);

    const t0 = Date.now();
    const baixado = await (deps.baixar ?? ((k: ChaveDaMensagem) => baixarMidiaPelaChave(k, { fetch: deps.fetch })))(chave);
    if (!baixado.ok) {
      if (baixado.erro === "arquivo_grande") return await falhaFinal(item.id, "arquivo_grande", deps);
      return await falhaDeDownload(item.id, baixado.erro, deps);
    }
    const bytes = baixado.bytes;
    if (bytes.length > LIMITE_BYTES) return await falhaFinal(item.id, "arquivo_grande", deps);
    const tipo = tipoReal(bytes);
    if (!tipo) return await falhaFinal(item.id, "formato_nao_suportado", deps);

    const sha256 = await sha256Hex(bytes);
    const chegada = new Date(String(item.recebido_em ?? ""));
    const caminho = caminhoNoBucket(item.id, Number.isNaN(chegada.getTime()) ? deps.agora() : chegada, tipo.ext);
    const subida = await bucket.upload(caminho, bytes, { contentType: tipo.mime, upsert: true });
    if (subida?.error) return await falhaDeDownload(item.id, "upload_falhou", deps);
    semDono = caminho;
    const assinada = await bucket.createSignedUrl(caminho, VALIDADE_DA_URL_S);
    const url = assinada?.data?.signedUrl;
    if (assinada?.error || typeof url !== "string") throw new FalhaDoFluxo("url_assinada");

    const g = await rpc(deps, "comprovante_guardar_arquivo", {
      p_id: item.id,
      p_arquivo: { path: caminho, mime_real: tipo.mime, bytes: bytes.length, sha256 },
      p_url: url,
    });
    // O banco respondeu: daqui em diante o objeto é da linha (ou já era — ja_guardado com o mesmo
    // caminho; apagar aqui levaria o original). O vigia cuida do que for apagar.
    semDono = null;
    deps.log("guardado", { id: item.id, decisao: g?.decisao ?? (g?.ja_guardado ? "ja_guardado" : null), bytes: bytes.length, ms: Date.now() - t0 });
    if (g?.ja_guardado) return "ja_guardado";

    if (g?.decisao === "duplicado") {
      if (g.apagar_arquivo_agora) {
        const remocao = await bucket.remove([caminho]);
        if (remocao?.error) deps.log("apagar_duplicado_falhou", { id: item.id }); // o vigia apaga depois
        else await rpc(deps, "comprovante_arquivo_apagado", { p_id: item.id });
      }
      if (g.modo === "dono") {
        await reagir(deps, g.phone_normalized, g.wa_message_id, "✅");
        await talvezAvisar(g.phone_normalized, false, deps);
      }
      return "duplicado";
    }
    return String(g?.decisao ?? "na_fila");
  } catch (e) {
    deps.log("processar_falhou", { id: item.id, codigo: codigoDoErro(e) });
    // Linha que já tinha desfecho (a falha veio depois dele, no aviso por exemplo, ou a resposta do
    // banco se perdeu depois do commit): o banco devolve ignorado e o objeto fica — pode ser dela.
    const r = await rpc<ResultadoDaFalha>(deps, "comprovante_download_falhou", { p_id: item.id, p_erro: "upload_falhou" });
    if (semDono && !r?.ignorado) {
      const remocao = await bucket.remove([semDono]).catch(() => ({ error: true }));
      if (remocao?.error) deps.log("apagar_sem_dono_falhou", { id: item.id });
    }
    deps.log("download_falhou", { id: item.id, erro: "upload_falhou", final: Boolean(r?.final) });
    await finalizarFalha(r, deps);
    return r?.final ? "falhou" : "tentar_de_novo";
  }
}

// ---------------------------------------------------------------------------------------------
// entrega (porta x-cron-secret: o gatilho de ai_jobs e o vigia)
// ---------------------------------------------------------------------------------------------

/**
 * comprovante_aplicar_leitura lançou: a transação dela desfez tudo (inclusive a marca de entrega) e
 * o job voltaria ao vigia a cada 2 min para sempre. comprovante_entrega_falhou conta em transação
 * própria e, na 3ª, desiste com desfecho (falhou; sem número, segue ao assistente). Antes disso, a
 * exceção sobe (o vigia tenta de novo).
 */
async function entregaQueFalhou(jobId: string, erro: unknown, deps: DependenciasDoFluxo): Promise<{ decisao: string }> {
  // deno-lint-ignore no-explicit-any
  let f: any;
  try {
    f = await rpc(deps, "comprovante_entrega_falhou", { p_job_id: jobId });
  } catch {
    throw erro; // sem conseguir contar, vale o erro original (o vigia tenta de novo)
  }
  deps.log("entrega_falhou", { job_id: jobId, codigo: codigoDoErro(erro), tentativas: f?.tentativas ?? null, desistiu: Boolean(f?.desistiu) });
  if (!f?.desistiu) throw erro;
  if (f.encaminhar && f.texto_para_assistente && f.phone_normalized && f.dono_id) {
    encaminharEmSegundoPlano({ phone: f.phone_normalized, dono_id: f.dono_id, texto: f.texto_para_assistente }, deps);
  }
  if (f.modo === "dono" && f.phone_normalized) {
    await reagir(deps, f.phone_normalized, f.wa_message_id, f.codigo ? "✅" : "");
    await talvezAvisar(f.phone_normalized, false, deps);
  }
  return { decisao: "falhou" };
}

export async function entregar(jobId: string, deps: DependenciasDoFluxo): Promise<{ decisao: string }> {
  // deno-lint-ignore no-explicit-any
  let r: any;
  try {
    r = await rpc(deps, "comprovante_aplicar_leitura", { p_job_id: jobId });
  } catch (e) {
    return await entregaQueFalhou(jobId, e, deps);
  }
  const decisao = String(r?.decisao ?? "ignorado");
  deps.log("entrega", { job_id: jobId, id: r?.id ?? null, decisao });
  if (decisao === "ignorado" || decisao === "reenfileirar") return { decisao };

  if (r.subir_dropbox && r.arquivo) await subirNoDropbox(r.arquivo as DadosDoArquivo, deps);
  if (r.encaminhar && r.texto_para_assistente && r.phone_normalized && r.dono_id) {
    encaminharEmSegundoPlano({ phone: r.phone_normalized, dono_id: r.dono_id, texto: r.texto_para_assistente }, deps);
  }
  if (r.modo === "dono" && r.phone_normalized) {
    const guardado = decisao === "cmp" || decisao === "duplicado" || (decisao === "falhou" && Boolean(r.codigo));
    await reagir(deps, r.phone_normalized, r.wa_message_id, guardado ? "✅" : "");
    await talvezAvisar(r.phone_normalized, false, deps);
  }
  return { decisao };
}

// ---------------------------------------------------------------------------------------------
// Dropbox
// ---------------------------------------------------------------------------------------------

function codigoDoDropbox(e: unknown): string {
  const x = e as { status?: number; resumo?: string };
  if (typeof x?.status === "number") return `dropbox_${x.status}${x.resumo ? `:${String(x.resumo).slice(0, 100)}` : ""}`;
  return "dropbox_erro";
}

/** Sobe a cópia em _A CLASSIFICAR (add + autorename: nunca sobrescreve). true = subiu. */
export async function subirNoDropbox(d: DadosDoArquivo, deps: DependenciasDoFluxo): Promise<boolean> {
  const falhar = async (codigo: string) => {
    const r = await rpc(deps, "comprovante_dropbox_falhou", { p_id: d.id, p_erro: codigo.slice(0, 300) });
    deps.log("dropbox_falhou", { id: d.id, codigo, desistiu: Boolean(r?.desistiu) });
    return false;
  };
  let dbx: DropboxDoFluxo | null;
  try {
    dbx = await deps.dropbox();
  } catch {
    return await falhar("dropbox_conexao_ilegivel");
  }
  if (!dbx) return await falhar("dropbox_sem_conexao");

  const baixado = await deps.admin.storage.from(BUCKET).download(d.arquivo_path);
  if (baixado?.error || !baixado?.data) return await falhar("arquivo_indisponivel");
  const bytes = new Uint8Array(await (baixado.data as Blob).arrayBuffer());

  let meta: { id: string; path_display: string; rev: string };
  try {
    meta = await dbx.enviar(`${PASTA_A_CLASSIFICAR}/${nomeNoDropbox(d)}`, bytes, true);
  } catch (e) {
    return await falhar(codigoDoDropbox(e));
  }
  // Subiu: a partir daqui, falha do banco NÃO pede nova subida (viraria uma cópia "(1)").
  await rpc(deps, "comprovante_no_dropbox", { p_id: d.id, p_dropbox_id: meta.id, p_caminho: meta.path_display, p_rev: meta.rev });
  deps.log("dropbox_ok", { id: d.id });
  return true;
}

// ---------------------------------------------------------------------------------------------
// Aviso ao dono e encaminhamento ao assistente
// ---------------------------------------------------------------------------------------------

/**
 * Envia o aviso pelo whatsapp-send (context "comprovante": o whatsapp-send não guarda o texto em
 * audit_log). Sem whatsapp_send_queue: aquela fila qualquer logado lê e EDITA antes do envio, e o
 * aviso traz fornecedor e valor do dono. Quem não confirmou o envio desfaz a reserva e o vigia tenta
 * de novo (comprovante_aviso_falhou).
 */
async function enviarAviso(phone: string, texto: string, chave: string, deps: DependenciasDoFluxo): Promise<"enviado" | "em_andamento" | "falhou"> {
  try {
    const res = await deps.fetch(`${deps.supabaseUrl}/functions/v1/whatsapp-send`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${deps.serviceRoleKey}` },
      body: JSON.stringify({ phone, kind: "text", message: texto, context: "comprovante", dedupe_key: chave }),
      signal: AbortSignal.timeout(20_000),
    });
    const corpo = await res.json().catch(() => ({})) as Record<string, unknown>;
    if (res.ok && !corpo?.error) return "enviado";
    // 409 = a mesma chave está sem desfecho numa tentativa anterior: repetir agora duplicaria.
    if (res.status === 409) return "em_andamento";
    deps.log("aviso_nao_enviado", { status: res.status });
  } catch {
    deps.log("aviso_nao_enviado", { status: 0 });
  }
  return "falhou";
}

/**
 * O aviso chega na mesma conversa do assistente, sem ninguém ter pedido. Se há uma pendência viva
 * (ex.: lembrete de revisão a cliente esperando "sim"), um "ok" do dono ao aviso a aprovaria. Marca
 * pendencia_herdada — a mesma proteção do resumo das 07:30: "sim"/"ok" sem PIN reapresenta a
 * pendência em vez de executar (decidirPendenciaHerdada no ai-agent). Antes do envio, para o "ok"
 * nunca chegar primeiro.
 */
async function protegerPendencia(sessao: string, deps: DependenciasDoFluxo): Promise<boolean> {
  const { data, error } = await deps.admin.from("ai_operator_sessions").select("metadata").eq("id", sessao).maybeSingle();
  if (error) throw new FalhaDoFluxo(`ler_sessao:${error.code ?? "erro"}`);
  const metadata = ((data as { metadata?: Record<string, unknown> } | null)?.metadata ?? {}) as Record<string, unknown>;
  if (metadata.pendencia_herdada === true) return false;
  if (!(await pendenciaQueSegueEsperando(deps.admin, metadata, deps.agora()))) return false;
  const { error: e2 } = await deps.admin.from("ai_operator_sessions")
    .update({ metadata: { ...metadata, pendencia_herdada: true } })
    .eq("id", sessao);
  if (e2) throw new FalhaDoFluxo(`marcar_pendencia:${e2.code ?? "erro"}`);
  return true;
}

/**
 * Reserva o aviso no banco (que espera a fila do telefone esvaziar, ou 10 min com `forcar`),
 * protege a pendência viva da conversa, envia por whatsapp-send e grava o par 🤖 user/assistant no
 * histórico do assistente. Sem confirmação de envio (ou sem conseguir proteger a pendência), a
 * reserva volta para o vigia. Devolve quantos itens foram avisados.
 */
export async function talvezAvisar(phone: string, forcar: boolean, deps: DependenciasDoFluxo): Promise<number> {
  const r = await rpc(deps, "comprovante_reservar_aviso", { p_phone: phone, p_forcar: forcar });
  const itens: ItemDoAviso[] = Array.isArray(r?.itens) ? r.itens : [];
  if (itens.length === 0) return 0;
  const ids = itens.map((i) => i.id);
  const devolver = async (motivo: string) => {
    const f = await rpc(deps, "comprovante_aviso_falhou", { p_ids: ids });
    deps.log("aviso_devolvido", { itens: ids.length, motivo, desistiu: Number(f?.desistiu ?? 0) });
    return 0;
  };

  let sessao: string | null = null;
  try {
    const dono = await donoDoWhatsApp(deps.admin);
    if (dono && dono.phone === phone) {
      sessao = deps.sessaoDoWhatsApp
        ? await deps.sessaoDoWhatsApp(phone, dono.id)
        : await resolveOrCreateWhatsAppSession(deps.admin, phone, dono.id);
      if (await protegerPendencia(sessao, deps)) deps.log("pendencia_protegida", { itens: ids.length });
    }
  } catch (e) {
    return await devolver(codigoDoErro(e));
  }

  const texto = textoDoAviso(itens);
  const envio = await enviarAviso(phone, texto, chaveDoAviso(ids), deps);
  deps.log("aviso", { itens: itens.length, envio });
  if (envio === "falhou") return await devolver("envio");

  if (sessao) {
    try {
      const h = historicoDoAviso(itens, texto);
      const t0 = deps.agora().getTime();
      const { error } = await deps.admin.from("ai_operator_messages").insert([
        { session_id: sessao, role: "user", source: "whatsapp", created_at: new Date(t0).toISOString(), content: h.user },
        { session_id: sessao, role: "assistant", source: "whatsapp", created_at: new Date(t0 + 1).toISOString(), content: h.assistant },
      ]);
      if (error) deps.log("historico_nao_gravado", { codigo: error.code ?? "erro" });
    } catch (e) {
      deps.log("historico_nao_gravado", { codigo: codigoDoErro(e) });
    }
  }
  return itens.length;
}

/** POST ai-agent como o whatsapp-webhook faz (x-internal-secret), com o body de hoje da mensagem. */
export async function encaminharAoAssistente(p: { phone: string; dono_id: string; texto: string }, deps: DependenciasDoFluxo): Promise<void> {
  try {
    const res = await deps.fetch(`${deps.supabaseUrl}/functions/v1/ai-agent`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-internal-secret": deps.internalSecret },
      body: JSON.stringify({ channel: "whatsapp", phone_normalized: p.phone, app_user_id: p.dono_id, text: p.texto }),
    });
    await res.body?.cancel().catch(() => {});
    deps.log("encaminhado", { status: res.status });
  } catch {
    deps.log("encaminhar_falhou", { status: 0 });
  }
}

/** O turno do assistente demora (é um modelo): não segura a entrega nem o vigia. */
function encaminharEmSegundoPlano(p: { phone: string; dono_id: string; texto: string }, deps: DependenciasDoFluxo): void {
  emSegundoPlano(deps, "encaminhar", encaminharAoAssistente(p, deps));
}

// ---------------------------------------------------------------------------------------------
// vigiar (pg_cron a cada 2 min, só quando há trabalho) e repescar (manual, com OK)
// ---------------------------------------------------------------------------------------------

export type ContagemDoVigia = {
  baixados: number;
  entregues: number;
  reenfileirados: number;
  dropbox: number;
  apagados: number;
  avisos: number;
  expurgados: number;
  /** Linhas que a rede de 1 h do banco encerrou (sem_desfecho) e quantas seguiram ao assistente. */
  sem_desfecho: number;
  encaminhados: number;
};

type ItemDoBaixar = { id: string; wa_key?: unknown; phone_normalized?: string; wa_message_id?: string; recebido_em?: string };

/**
 * A ordem importa (orçamento de 45 s): primeiro o que é barato ou tem prazo de privacidade —
 * encaminhar o que a rede de 1 h encerrou, apagar originais vencidos (decisão 13) e entregar
 * leituras prontas —; depois os downloads, que podem ser lentos; Dropbox e avisos por último.
 */
export async function vigiar(deps: DependenciasDoFluxo, orcamentoMs = ORCAMENTO_DO_VIGIA_MS): Promise<ContagemDoVigia> {
  const inicio = deps.agora().getTime();
  const lote = await rpc(deps, "comprovantes_vigia_lote", { p_limite: LIMITE_DO_VIGIA });
  const n: ContagemDoVigia = {
    baixados: 0, entregues: 0, reenfileirados: 0, dropbox: 0, apagados: 0, avisos: 0,
    expurgados: Number(lote?.expurgados ?? 0), sem_desfecho: Number(lote?.sem_desfecho ?? 0), encaminhados: 0,
  };
  const temTempo = () => deps.agora().getTime() - inicio < orcamentoMs;
  const bucket = deps.admin.storage.from(BUCKET);

  async function cada<T>(lista: unknown, etapa: string, fazer: (x: T) => Promise<void>): Promise<void> {
    for (const x of (Array.isArray(lista) ? lista : []) as T[]) {
      if (!temTempo()) return;
      try {
        await fazer(x);
      } catch (e) {
        deps.log("vigia_item_falhou", { etapa, codigo: codigoDoErro(e) });
      }
    }
  }

  await cada<{ phone_normalized: string; dono_id: string; texto: string }>(lote?.encaminhar, "encaminhar", (x) => {
    if (x?.phone_normalized && x?.dono_id && x?.texto) {
      encaminharEmSegundoPlano({ phone: x.phone_normalized, dono_id: x.dono_id, texto: x.texto }, deps);
      n.encaminhados++;
    }
    return Promise.resolve();
  });
  await cada<{ id: string; arquivo_path: string }>(lote?.apagar, "apagar", async (a) => {
    const remocao = await bucket.remove([a.arquivo_path]);
    if (remocao?.error) throw new FalhaDoFluxo("storage_remove");
    await rpc(deps, "comprovante_arquivo_apagado", { p_id: a.id });
    n.apagados++;
  });
  await cada<{ job_id: string }>(lote?.entregar, "entregar", async (e) => {
    await entregar(e.job_id, deps);
    n.entregues++;
  });
  await cada<{ id: string; arquivo_path: string }>(lote?.reenfileirar, "reenfileirar", async (r) => {
    const assinada = await bucket.createSignedUrl(r.arquivo_path, VALIDADE_DA_URL_S);
    const url = assinada?.data?.signedUrl;
    if (assinada?.error || typeof url !== "string") throw new FalhaDoFluxo("url_assinada");
    const res = await rpc(deps, "comprovante_pedir_leitura", { p_id: r.id, p_url: url });
    if (res?.ok) n.reenfileirados++;
    else deps.log("reenfileirar_recusado", { id: r.id, motivo: String(res?.motivo ?? "") });
  });
  await cada<ItemDoBaixar>(lote?.baixar, "baixar", async (b) => {
    await processarArquivo({
      id: b.id, chave: b.wa_key ?? null, phone: b.phone_normalized, wa_message_id: b.wa_message_id, recebido_em: b.recebido_em,
    }, deps);
    n.baixados++;
  });
  await cada<DadosDoArquivo>(lote?.dropbox, "dropbox", async (d) => {
    if (await subirNoDropbox(d, deps)) n.dropbox++;
  });
  await cada<string>(lote?.avisar, "avisar", async (phone) => {
    n.avisos += await talvezAvisar(phone, true, deps);
  });
  deps.log("vigia", { ...n, ms: deps.agora().getTime() - inicio });
  return n;
}

export type ResultadoDaRepescagem =
  | { ok: true; processadas: number; restantes: number }
  | { ok: false; motivo: "modo_off" | "sem_dono" | "desde_invalido" };

/**
 * Mídias do dono desde `desde` que ainda não têm linha: comprovante_receber com origem
 * "repescagem" (o banco nunca encaminha essas) e processarArquivo, EM SEQUÊNCIA, até `limite`
 * (máx. 20). Quem já tem linha volta novo=false e é pulado (idempotente pelo wa_message_id).
 * `restantes` = mensagens do período ainda não conferidas nesta chamada.
 */
export async function repescar(p: { desde: string; limite?: number }, deps: DependenciasDoFluxo): Promise<ResultadoDaRepescagem> {
  const modo = await lerModoDoComprovante(deps.admin);
  if (modo === "off") return { ok: false, motivo: "modo_off" };
  const desde = new Date(String(p?.desde ?? ""));
  if (!p?.desde || Number.isNaN(desde.getTime())) return { ok: false, motivo: "desde_invalido" };
  const limite = Math.max(1, Math.min(LIMITE_DA_REPESCAGEM, Math.trunc(Number(p.limite ?? LIMITE_DA_REPESCAGEM)) || LIMITE_DA_REPESCAGEM));
  const dono = await donoDoWhatsApp(deps.admin);
  if (!dono) return { ok: false, motivo: "sem_dono" };

  const campos = "id, wa_message_id, phone_normalized, message_type, direction, raw_payload, occurred_at";
  const base = () =>
    deps.admin.from("whatsapp_messages").select(campos)
      .eq("direction", "inbound").eq("phone_normalized", dono.phone).gte("occurred_at", desde.toISOString());
  const [midias, envelopes] = await Promise.all([
    base().in("message_type", ["image", "document"]).order("occurred_at", { ascending: true }).limit(200),
    base().eq("message_type", "text").not("raw_payload->data->message->documentWithCaptionMessage", "is", null)
      .order("occurred_at", { ascending: true }).limit(200),
  ]);
  if (midias.error || envelopes.error) throw new FalhaDoFluxo(`ler_mensagens:${(midias.error ?? envelopes.error).code ?? "erro"}`);
  const candidatas = [...(midias.data ?? []), ...(envelopes.data ?? [])] as Mensagem[];
  candidatas.sort((a, b) => String(a.occurred_at).localeCompare(String(b.occurred_at)));

  const inicio = deps.agora().getTime();
  let processadas = 0;
  let conferidas = 0;
  for (const msg of candidatas) {
    if (processadas >= limite || deps.agora().getTime() - inicio >= ORCAMENTO_DO_VIGIA_MS) break;
    conferidas++;
    const ev = reparse(msg.raw_payload);
    if (!ev?.mediaKind || !msg.wa_message_id) continue;
    // a linha de whatsapp_messages pode ter sido escrita por qualquer logado: só entra a mensagem cuja
    // key é desta conversa (a do dono), recebida e com o mesmo id
    const chave = chaveDoPayload(msg.raw_payload);
    if (!chaveConfere(chave, dono.phone, msg.wa_message_id)) {
      deps.log("repescagem_chave_divergente", { message_id: msg.id });
      continue;
    }
    const reg = await registrar(deps, msg, ev, chave, { modo, rota: "comprovante", origem: "repescagem", dono });
    if (!reg.ok || !reg.r.novo) continue;
    await processarArquivo({
      id: reg.r.id,
      chave,
      phone: msg.phone_normalized,
      wa_message_id: msg.wa_message_id,
      recebido_em: msg.occurred_at,
      tamanho_declarado: tamanhoDeclarado(msg.raw_payload),
    }, deps);
    processadas++;
  }
  const restantes = candidatas.length - conferidas;
  deps.log("repescagem", { processadas, restantes });
  return { ok: true, processadas, restantes };
}
