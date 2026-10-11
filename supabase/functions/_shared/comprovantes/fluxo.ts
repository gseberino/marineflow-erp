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
//
// F2 (11/10/2026 — spec-f2.md, 5.8): a conversa. Com app_settings.comprovante_fluxo = 'dono' e
// comprovante_conversa = 'on', cada CMP entra na fila do telefone do dono e o sistema pergunta um de
// cada vez (responder / pendentes / desempatar), grava só depois do "sim" (o banco grava pelas rotas
// que já existem) e leva o arquivo ao destino final no Dropbox com o índice do mês. Desligada, o
// caminho é o da F1, sem mudança.
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
import { garantirPastaDoBarco, type PastaDoBarco, pastaRegistradaDoBarco } from "../dropbox/pasta.ts";
import { numeroDeTesteAtivo } from "../whatsapp/marcar-enviado.ts";
import {
  type EstadoDoTelefone,
  lerEstadoDoTelefone,
  marcarPerguntaEnviada,
  type Opcao,
  quemResponde,
  textoDoDesempate,
} from "../whatsapp/pergunta-ativa.ts";
import {
  classeDoComando,
  type Comando,
  type Interpretacao,
  interpretarResposta,
  lerComando,
  pareceDica,
  respostaNaoEntendida,
} from "./respostas.ts";
import {
  type Cancelamento,
  type CmpResumo,
  type Efeito,
  type Gravacao,
  historicoDoFluxo,
  type ItemPendente,
  MARCA_DO_FLUXO,
  motivoDoNaoGravado,
  numeroDoCmp,
  type PerguntaDoBanco,
  prefixoDaPergunta,
  TEXTO_CORRIGIR_COMO,
  TEXTO_FALHA,
  TEXTO_SEM_CMP,
  textoCorrigido,
  textoCorrigirIncompleto,
  textoDaGravacao,
  textoDaPergunta,
  textoDica,
  textoDoCancelamento,
  textoDoCartao,
  textoDosPendentes,
  textoFeito,
  textoInvalida,
  textoJaGravado,
  textoLote,
  textoNaFila,
  textoNaoEntendi,
  textoNaoExiste,
  textoNaoGravado,
  textoOcupado,
  textoOkNaoAprova,
  textoPulado,
  textoQualCmp,
  textoRetomadaInterrompida,
  textoSair,
  textoSemMotivo,
} from "./conversa.ts";
import {
  caminhoDoIndice,
  csvDoIndice,
  type DestinoDoArquivo,
  type LinhaDoIndice,
  mesDoArquivo,
  nomeCancelado,
  nomeDoCaminho,
  nomeFinal,
  pastaFinal,
  semCpf,
  usaPastaDoBarco,
} from "./destino.ts";

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

type MetaDoDropbox = { id: string; path_display: string; rev: string };

export type DropboxDoFluxo = {
  enviar(caminho: string, bytes: Uint8Array<ArrayBuffer>, autorename?: boolean): Promise<MetaDoDropbox>;
  /** F2: move_v2 (mantém o id), substituir por rev (o índice do mês), criar pasta e o rpc genérico (pasta do barco). */
  mover(de: string, para: string, autorename?: boolean): Promise<MetaDoDropbox>;
  substituir(caminho: string, bytes: Uint8Array<ArrayBuffer>, rev: string | null): Promise<MetaDoDropbox & { conflito: boolean }>;
  criarPasta(caminho: string): Promise<{ id: string; path_display: string }>;
  rpc<T>(rota: string, corpo: unknown | null): Promise<T>;
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
  /** F2, para os testes; o padrão é garantirPastaDoBarco (com pasta-base) ou pastaRegistradaDoBarco (null = nenhuma). */
  pastaDoBarco?(dbx: DropboxDoFluxo, p: { vesselId: string; clientId: string; barco: string | null; cliente: string | null; pastaBase: string }): Promise<PastaDoBarco | null>;
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

  // F2: com a conversa ligada (modo dono + comprovante_conversa on), os CMPs entram na fila e o
  // sistema pergunta; o aviso informativo da F1 fica só para repetidos, não guardados e o que não
  // entrou na fila. Desligada (ou erro ao entrar na fila): a F1 sem mudança.
  const estado = await lerEstadoDoTelefone(deps.admin, phone, null);
  if (estado.conversa && estado.dono) {
    const cmps = itens.filter((i) => i.decisao === "cmp" || i.decisao === "cmp_sem_leitura");
    let entraram: Set<string> | null = new Set();
    let ordem: Array<{ id: string; codigo: string | null }> = [];
    if (cmps.length) {
      try {
        const e = await rpc<{ entraram?: Array<{ id: string; codigo?: string }> }>(deps, "comprovante_conversa_entrar", { p_ids: cmps.map((i) => i.id) });
        ordem = (Array.isArray(e?.entraram) ? e.entraram : []).map((x) => ({ id: String(x?.id), codigo: x?.codigo ? String(x.codigo) : null }));
        entraram = new Set(ordem.map((x) => x.id));
      } catch (e) {
        deps.log("conversa_entrar_falhou", { codigo: codigoDoErro(e) });
        entraram = null;
      }
    }
    if (entraram) {
      const informar = itens.filter((i) => !entraram.has(i.id));
      if (informar.length) await avisarItens(phone, informar, deps);
      deps.log("conversa_fila", { entraram: entraram.size, informados: informar.length });
      if (entraram.size > 0) {
        await consultarCnpjsDosIds([...entraram], deps);
        try {
          // a abertura pergunta o CMP que ACABOU de chegar (o banco devolve na ordem do número), não um
          // antigo da fila; sem perguntar agora (ocupado, conversa em andamento), uma linha avisa
          const r = await abrirPergunta(phone, "abertura", deps, null, ordem[0]?.id ?? null);
          if (!r.perguntou && r.motivo && ["ocupado", "conversa_em_andamento", "pausada"].includes(r.motivo)) {
            const codigos = ordem.map((x) => x.codigo).filter((c): c is string => Boolean(c));
            const numero = Number(/(\d+)$/.exec(codigos[0] ?? "")?.[1] ?? 0) || null;
            await enviarMensagem(phone, textoNaFila(codigos, numero, r.ocupadoCom), `cmp:fila:${ordem[0].id}`, null, deps);
          }
        } catch (e) {
          deps.log("pergunta_falhou", { codigo: codigoDoErro(e) }); // o vigia pergunta depois
        }
      }
      return itens.length;
    }
  }
  return await avisarItens(phone, itens, deps);
}

/**
 * O aviso informativo da F1 para estes itens já reservados: protege a pendência viva, envia por
 * whatsapp-send e grava o par 🤖 no histórico. Sem confirmação de envio, a reserva DESTES itens
 * volta para o vigia. Devolve quantos foram avisados.
 */
async function avisarItens(phone: string, itens: ItemDoAviso[], deps: DependenciasDoFluxo): Promise<number> {
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
  /** F2: arquivos levados ao destino final, índices do mês regravados, CNPJs consultados, perguntas abertas. */
  movidos: number;
  indices: number;
  cnpj: number;
  perguntas: number;
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
    movidos: 0, indices: 0, cnpj: 0, perguntas: 0,
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

  // F2: a conversa (o banco só devolve trabalho com a conversa ligada ou com arquivo/índice pendente).
  // Erro na reserva não derruba o vigia da F1: só registra.
  // deno-lint-ignore no-explicit-any
  let conversa: any = null;
  if (temTempo()) {
    try {
      conversa = await rpc(deps, "comprovantes_vigia_conversa", { p_limite: LIMITE_DO_VIGIA });
    } catch (e) {
      deps.log("vigia_conversa_falhou", { codigo: codigoDoErro(e) });
    }
  }
  if (conversa) {
    await cada<DadosDoArquivo>(conversa.subir, "subir_conversa", async (d) => {
      if (await subirNoDropbox(d, deps)) n.dropbox++;
    });
    await cada<string | { id: string }>(conversa.mover, "mover", async (x) => {
      const id = typeof x === "string" ? x : x?.id;
      if (id && (await moverComMes(id, deps)).movido) n.movidos++;
    });
    await cada<string>(conversa.indices, "indice", async (mes) => {
      if (await atualizarIndice(mes, deps)) n.indices++;
    });
    // o CNPJ antes das perguntas: o cabeçalho já sai com o nome da Receita
    await cada<string>((Array.isArray(conversa.cnpj) ? conversa.cnpj : []).slice(0, LIMITE_DE_CNPJ), "cnpj", async (c) => {
      await consultarCnpj(c, deps);
      n.cnpj++;
    });
    await cada<string>(conversa.perguntar, "perguntar", async (phone) => {
      if (await perguntarProximo(phone, "vigia", deps)) n.perguntas++;
    });
  }
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

// =============================================================================================
// F2: a conversa (spec-f2.md, 5.8)
// =============================================================================================

/** No máximo 3 consultas à BrasilAPI por rodada (dado público: só o CNPJ do fornecedor sai daqui). */
const LIMITE_DE_CNPJ = 3;
const PRAZO_DA_BRASILAPI_MS = 8_000;
const JANELA_DO_HISTORICO_MS = 2 * 60 * 60_000;
const MAX_HISTORICO = 4000;

/**
 * Envia ao dono pelo whatsapp-send (context "comprovante": o texto não vai ao audit_log) com a chave
 * anti-duplicado. "enviado" traz o id do WhatsApp (null quando a chave já tinha saído antes);
 * 409 = a mesma chave sem desfecho numa tentativa anterior ("em_andamento": não repete agora).
 */
export async function enviarAoDono(
  phone: string,
  texto: string,
  chave: string,
  deps: DependenciasDoFluxo,
): Promise<{ status: "enviado" | "em_andamento" | "falhou"; messageId: string | null }> {
  try {
    const res = await deps.fetch(`${deps.supabaseUrl}/functions/v1/whatsapp-send`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${deps.serviceRoleKey}` },
      body: JSON.stringify({ phone, kind: "text", message: texto, context: "comprovante", dedupe_key: chave }),
      signal: AbortSignal.timeout(20_000),
    });
    const corpo = await res.json().catch(() => ({})) as Record<string, unknown>;
    if (res.ok && !corpo?.error) {
      return { status: "enviado", messageId: typeof corpo.messageId === "string" && corpo.messageId ? corpo.messageId : null };
    }
    if (res.status === 409) return { status: "em_andamento", messageId: null };
    deps.log("envio_nao_confirmado", { status: res.status });
  } catch {
    deps.log("envio_nao_confirmado", { status: 0 });
  }
  return { status: "falhou", messageId: null };
}

/**
 * Envia a mensagem. `abre` = a pergunta NOVA que ela abre: sem confirmação de envio, volta ao banco
 * (o CMP volta à fila; o vigia tenta depois). `reenvia` = a pergunta aberta que ela REAPRESENTA (a
 * resposta não serviu, o "responda sim a este resumo"). Nos dois casos, o envio confirmado fica
 * registrado na pergunta (enviada_em + o id do WhatsApp: a citação do reenvio também acha).
 */
async function enviarMensagem(
  phone: string,
  texto: string,
  chave: string,
  abre: PerguntaDoBanco | null,
  deps: DependenciasDoFluxo,
  reenvia: string | null = null,
): Promise<boolean> {
  const envio = await enviarAoDono(phone, texto, chave, deps);
  if (abre && envio.status === "falhou") {
    await rpc(deps, "comprovante_pergunta_nao_enviada", { p_pergunta_id: abre.pergunta_id });
    deps.log("pergunta_nao_enviada", { id: abre.cmp?.id ?? null, passo: abre.passo });
    return false;
  }
  const alvo = abre?.pergunta_id ?? reenvia;
  if (alvo && envio.status !== "falhou") await marcarPerguntaEnviada(deps.admin, alvo, envio.messageId);
  if (abre) deps.log("pergunta", { id: abre.cmp?.id ?? null, passo: abre.passo, envio: envio.status });
  return envio.status !== "falhou";
}

// deno-lint-ignore no-explicit-any
async function lerConfiguracoes(deps: DependenciasDoFluxo, chaves: string[]): Promise<Record<string, any>> {
  const { data, error } = await deps.admin.from("app_settings").select("key, value").in("key", chaves);
  if (error) throw new FalhaDoFluxo(`ler_configuracoes:${error.code ?? "erro"}`);
  return Object.fromEntries(((data ?? []) as Array<{ key: string; value: unknown }>).map((r) => [r.key, r.value ?? null]));
}

/**
 * O modo de teste do whatsapp-send desvia tudo para o número de teste: as respostas viriam de outro
 * telefone. Ligado (ou sem conseguir conferir), a conversa não abre pergunta.
 */
async function modoDeTesteLigado(deps: DependenciasDoFluxo): Promise<boolean> {
  try {
    const s = await lerConfiguracoes(deps, ["wa_test_mode", "wa_test_number", "zapi_test_mode", "zapi_test_number"]);
    const texto = Object.fromEntries(Object.entries(s).map(([k, v]) => [k, v == null ? null : String(v)]));
    return numeroDeTesteAtivo(texto) !== null;
  } catch {
    return true;
  }
}

/** O que a abertura de uma pergunta devolveu: perguntou (e enviou), ou o porquê de não. */
type Aberta = { perguntou: boolean; motivo: string | null; ocupadoCom: string | null; codigo: string | null };

/** comprovante_proxima_pergunta + o envio; sem perguntar, o motivo (a abertura avisa numa linha). */
async function abrirPergunta(
  phone: string,
  motivo: string,
  deps: DependenciasDoFluxo,
  prefixo?: string | null,
  cmp?: string | null,
): Promise<Aberta> {
  if (await modoDeTesteLigado(deps)) {
    deps.log("pergunta_recusada", { motivo: "modo_de_teste" });
    return { perguntou: false, motivo: "modo_de_teste", ocupadoCom: null, codigo: null };
  }
  // deno-lint-ignore no-explicit-any
  const r = await rpc<any>(deps, "comprovante_proxima_pergunta", { p_phone: phone, p_motivo: motivo, p_cmp: cmp ?? null });
  if (!r?.perguntou) {
    deps.log("pergunta_nao_aberta", { motivo: String(r?.motivo ?? ""), fila: Number(r?.fila ?? 0) });
    return {
      perguntou: false, motivo: typeof r?.motivo === "string" ? r.motivo : null,
      ocupadoCom: typeof r?.ocupado_por?.titulo === "string" ? r.ocupado_por.titulo : null,
      codigo: typeof r?.codigo === "string" ? r.codigo : null,
    };
  }
  const p = r as PerguntaDoBanco;
  const texto = textoDaPergunta(p, prefixo ?? prefixoDaPergunta(p, motivo));
  const enviou = await enviarMensagem(phone, texto, p.dedupe_key, p, deps);
  return { perguntou: enviou, motivo: enviou ? null : "nao_enviada", ocupadoCom: null, codigo: p.cmp?.codigo ?? null };
}

/**
 * Abre a próxima pergunta do telefone (comprovante_proxima_pergunta) e a envia. `motivo` ∈ abertura,
 * vigia, depois_de_gravar, pendentes, cmp, lote_antigo, pular, reabrir, retomar. true = perguntou.
 */
export async function perguntarProximo(
  phone: string,
  motivo: string,
  deps: DependenciasDoFluxo,
  prefixo?: string | null,
  cmp?: string | null,
): Promise<boolean> {
  return (await abrirPergunta(phone, motivo, deps, prefixo, cmp)).perguntou;
}

/**
 * A pendência do assistente que tinha tirado a pergunta de um CMP foi respondida (o ai-agent avisa):
 * reabre a pergunta DAQUELE CMP (sem esperar o vigia, que só pergunta em horário comercial).
 */
export async function retomar(p: { phone: string }, deps: DependenciasDoFluxo): Promise<{ perguntou: boolean }> {
  if (typeof p?.phone !== "string" || !/^\d{10,15}$/.test(p.phone)) return { perguntou: false };
  const dono = await donoDoWhatsApp(deps.admin);
  if (!dono || dono.phone !== p.phone) return { perguntou: false };
  return { perguntou: await perguntarProximo(p.phone, "retomar", deps) };
}

// ---------------------------------------------------------------------------------------------
// responder / pendentes / desempatar (porta chamadaInterna: só o whatsapp-webhook)
// ---------------------------------------------------------------------------------------------

export type CorpoDoResponder = {
  message_id: string;
  phone: string;
  texto: string;
  citado?: string | null;
  destino?: string;
};

type Recusa = { ok: false; motivo: string };

/**
 * O edge reconfere tudo (a decisão do webhook é só um atalho): mensagem gravada, RECEBIDA, do
 * telefone do dono. O texto vem do corpo (o webhook leu do evento), nunca de whatsapp_messages.body
 * (que a equipe consegue editar).
 */
async function conferirMensagemDoDono(messageId: unknown, phone: unknown, deps: DependenciasDoFluxo): Promise<{ ok: true } | Recusa> {
  if (typeof messageId !== "string" || !UUID.test(messageId) || typeof phone !== "string" || !/^\d{10,15}$/.test(phone)) {
    return { ok: false, motivo: "entrada_invalida" };
  }
  const msg = await lerMensagem(deps, messageId);
  if (!msg) return { ok: false, motivo: "mensagem_inexistente" };
  if (msg.direction !== "inbound") return { ok: false, motivo: "nao_e_recebida" };
  if (msg.phone_normalized !== phone) return { ok: false, motivo: "telefone_divergente" };
  const dono = await donoDoWhatsApp(deps.admin);
  if (!dono || dono.phone !== phone) return { ok: false, motivo: "dono_divergente" };
  return { ok: true };
}

type Contexto = { phone: string; messageId: string; chave: string; texto: string; estado: EstadoDoTelefone };
type Saida = { status: 200; corpo: { tratada: boolean; resultado?: string; motivo?: string } };

const DESTINOS_DO_RESPONDER = new Set(["comprovante", "comprovante_reabrir", "comando", "dica", "foto_do_cmp", "nao_entendi"]);

/** A frase de resposta ao passo da última pergunta de CMP (a resposta atrasada): de dado, não sim/não/ok. */
function respondeAUltima(estado: EstadoDoTelefone, texto: string, agora: Date): boolean {
  const u = estado.ultima_do_cmp;
  if (!u || estado.ativa) return false;
  const i = interpretarResposta(u.passo, u.opcoes, texto, agora);
  return i !== null && i.tipo !== "sim" && i.tipo !== "nao" && i.tipo !== "ok";
}

export async function responder(
  p: CorpoDoResponder,
  deps: DependenciasDoFluxo,
): Promise<{ status: 200 | 422; corpo: { tratada: boolean; resultado?: string; motivo?: string } }> {
  const recusar = (motivo: string) => {
    deps.log("responder_recusado", { motivo });
    return { status: 422 as const, corpo: { tratada: false, motivo } };
  };
  if (typeof p?.texto !== "string" || !p.texto.trim() || p.texto.length > 4000) return recusar("entrada_invalida");
  if (p.citado != null && (typeof p.citado !== "string" || p.citado.length > 128)) return recusar("entrada_invalida");
  if (p.destino != null && !DESTINOS_DO_RESPONDER.has(String(p.destino))) return recusar("entrada_invalida");
  const conf = await conferirMensagemDoDono(p.message_id, p.phone, deps);
  if (!conf.ok) return recusar(conf.motivo);

  const citado = p.citado ? String(p.citado) : null;
  const estado = await lerEstadoDoTelefone(deps.admin, p.phone, citado);
  if (!estado.conversa || !estado.dono) return { status: 200, corpo: { tratada: false, resultado: "desligada" } };

  const agora = deps.agora();
  const comando = lerComando(p.texto, agora);
  const ativa = estado.ativa?.origem === "comprovante" ? estado.ativa : null;
  const interp = ativa ? interpretarResposta(ativa.passo, ativa.opcoes, p.texto, agora) : null;
  const decisao = quemResponde({
    texto: p.texto, citado, estado, ehRespostaValida: interp !== null, ehComando: classeDoComando(comando), agora,
    ehRespostaAUltima: respondeAUltima(estado, p.texto, agora),
    ehDica: pareceDica(p.texto),
    ehNaoEntendida: interp === null && respostaNaoEntendida(p.texto),
  });
  deps.log("responder", { destino: decisao.destino, motivo: decisao.motivo });
  const ctx: Contexto = { phone: p.phone, messageId: p.message_id, chave: `cmp:r:${p.message_id}`, texto: p.texto, estado };

  switch (decisao.destino) {
    case "assistente":
      return { status: 200, corpo: { tratada: false, resultado: "assistente" } };
    case "pendentes":
      await listarPendentes(p.phone, p.message_id, deps);
      return { status: 200, corpo: { tratada: false, resultado: "pendentes" } };
    case "ambiguo":
      await falarDoEmpate(ctx, deps);
      return trata("desempate");
    case "comando":
      return await executarComando(comando as Comando, ctx, deps);
    case "dica":
      return await guardarDica(ctx, deps);
    case "foto_do_cmp":
      return await respostaAFoto(ctx, deps, agora);
    case "nao_entendi":
      return await naoEntendi(ctx, deps);
    default: {
      if (comando) return await executarComando(comando, ctx, deps);
      // a pergunta respondida: a citada (aberta ou fechada), a ativa, ou a última fechada (resposta atrasada)
      let alvo: { id: string; passo: string | null; opcoes: Opcao[] } | null = null;
      if (estado.citada?.origem === "comprovante") {
        alvo = estado.citada.id === ativa?.id
          ? { id: ativa.id, passo: ativa.passo, opcoes: ativa.opcoes }
          : await perguntaPeloId(estado.citada.id, deps);
      } else if (ativa) {
        alvo = { id: ativa.id, passo: ativa.passo, opcoes: ativa.opcoes };
      } else if (decisao.motivo === "resposta_atrasada" && estado.ultima_do_cmp) {
        const u = estado.ultima_do_cmp;
        alvo = { id: u.id, passo: u.passo, opcoes: u.opcoes };
      }
      if (!alvo) return { status: 200, corpo: { tratada: false, resultado: "sem_pergunta" } };
      const i = alvo.id === ativa?.id ? interp : interpretarResposta(alvo.passo, alvo.opcoes, p.texto, agora);
      if (!i) return { status: 200, corpo: { tratada: false, resultado: "texto_livre" } };
      return await responderA(alvo, i, ctx, deps);
    }
  }
}

/**
 * comprovante_responder na pergunta e o texto ao dono. Se a RPC falhou, nada foi gravado (a transação
 * voltou): aqui se sabe disso, e o aviso "mande de novo" sai com a MESMA chave do aviso do webhook
 * (cmp:f:<mensagem>) — o whatsapp-send manda uma vez só.
 */
async function responderA(
  alvo: { id: string; passo: string | null; opcoes: Opcao[] },
  i: Interpretacao,
  ctx: Contexto,
  deps: DependenciasDoFluxo,
): Promise<Saida> {
  // deno-lint-ignore no-explicit-any
  let r: any;
  try {
    r = await rpc(deps, "comprovante_responder", {
      p: { pergunta_id: alvo.id, message_id: ctx.messageId, interpretacao: i, versao: null },
    });
  } catch (e) {
    await enviarAoDono(ctx.phone, TEXTO_FALHA, `cmp:f:${ctx.messageId}`, deps);
    throw e;
  }
  return await falarDaResposta(r, { ...ctx, respondida: alvo.id, interp: i, passo: alvo.passo }, deps);
}

/** O passo e as opções da pergunta citada que já fechou: o banco aplica a resposta ao que o dono VIU nela. */
async function perguntaPeloId(id: string, deps: DependenciasDoFluxo): Promise<{ id: string; passo: string | null; opcoes: Opcao[] } | null> {
  const { data, error } = await deps.admin.from("whatsapp_perguntas").select("id, passo, opcoes, origem").eq("id", id).maybeSingle();
  if (error) throw new FalhaDoFluxo(`ler_pergunta:${error.code ?? "erro"}`);
  if (!data || data.origem !== "comprovante") return null;
  return { id: String(data.id), passo: data.passo ?? null, opcoes: Array.isArray(data.opcoes) ? data.opcoes as Opcao[] : [] };
}

/** A última pergunta de um CMP (aberta ou não): a citação da FOTO responde a ela. */
async function ultimaPerguntaDoCmp(cmp: string, deps: DependenciasDoFluxo): Promise<{ id: string; passo: string | null; opcoes: Opcao[] } | null> {
  const { data, error } = await deps.admin.from("whatsapp_perguntas").select("id, passo, opcoes")
    .eq("referencia_id", cmp).eq("origem", "comprovante").order("aberta_em", { ascending: false }).limit(1);
  if (error) throw new FalhaDoFluxo(`ler_pergunta:${error.code ?? "erro"}`);
  const d = Array.isArray(data) ? data[0] : null;
  return d ? { id: String(d.id), passo: d.passo ?? null, opcoes: Array.isArray(d.opcoes) ? d.opcoes as Opcao[] : [] } : null;
}

function trata(resultado: string): Saida {
  return { status: 200, corpo: { tratada: true, resultado } };
}

/** A pergunta que veio é NOVA (o banco abriu outra) ou a mesma reapresentada? Muda a chave do envio. */
function chaveDaPergunta(
  proxima: PerguntaDoBanco | null,
  respondida: string | null,
  chaveDaResposta: string,
): { chave: string; abre: PerguntaDoBanco | null; reenvia: string | null } {
  if (proxima && proxima.pergunta_id && proxima.pergunta_id !== respondida) return { chave: proxima.dedupe_key, abre: proxima, reenvia: null };
  return { chave: chaveDaResposta, abre: null, reenvia: proxima?.pergunta_id ?? null };
}

/** "sim, mas é da OS 12": começou com sim/não e veio texto a mais (o "ok" do confirmar). */
function simComTextoAMais(texto: string): boolean {
  const t = String(texto ?? "").trim().toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
  return /^(?:sim|nao|isso|pode)\b/.test(t) && t.split(/\s+/).length > 1;
}

/** O resultado do comprovante_responder vira o texto ao dono (seção 3.3). */
async function falarDaResposta(
  // deno-lint-ignore no-explicit-any
  r: any,
  ctx: Contexto & { respondida: string; interp: Interpretacao; passo: string | null },
  deps: DependenciasDoFluxo,
): Promise<Saida> {
  const cmp = (r?.cmp ?? null) as CmpResumo | null;
  const codigo = cmp?.codigo ?? "comprovante";
  const proxima = (r?.proxima ?? null) as PerguntaDoBanco | null;
  const resultado = String(r?.resultado ?? "");
  // no nao_gravado o motivo é a mensagem da rota (pode trazer dado): no log, só motivo que é código
  const motivoDoLog = typeof r?.motivo === "string" && /^[a-z_]{1,40}$/.test(r.motivo) ? r.motivo : null;
  deps.log("resposta", { id: cmp?.id ?? null, resultado, motivo: motivoDoLog });

  switch (resultado) {
    case "ignorada": {
      if (r?.motivo === "desligada") return { status: 200, corpo: { tratada: false, resultado: "desligada" } };
      // já gravado/cancelado: responde aqui (um "1" a uma pergunta velha nunca cai no assistente)
      const texto = cmp?.situacao === "cancelado"
        ? `O ${codigo} foi cancelado.`
        : textoJaGravado(codigo, cmp ? numeroDoCmp(cmp) : null);
      await enviarMensagem(ctx.phone, texto, ctx.chave, null, deps);
      return trata("ignorada");
    }
    case "ok_nao_aprova":
      await enviarMensagem(ctx.phone, textoOkNaoAprova(codigo, simComTextoAMais(ctx.texto)), ctx.chave, null, deps);
      return trata(resultado);
    case "nao_gravado": {
      // o motivo cru da rota nunca vai ao dono nem ao log: vira texto fixo; o código do erro vai ao app_error_logs
      const codigoErro = typeof r?.codigo_erro === "string" && /^[0-9A-Z]{5}$/.test(r.codigo_erro) ? r.codigo_erro : null;
      const conhecido = motivoDoNaoGravado(r?.motivo, null).conhecido;
      if (!conhecido) {
        await logEdgeError(deps.admin, {
          context: "comprovantes-whatsapp", action: "gravar", level: "error",
          message: `nao_gravado:${codigoErro ?? "sem_codigo"}`, details: { cmp_id: cmp?.id ?? null },
        });
      }
      await enviarMensagem(ctx.phone, textoNaoGravado(codigo, r?.motivo, cmp ? numeroDoCmp(cmp) : null, codigoErro), ctx.chave, null, deps);
      return trata(resultado);
    }
    case "invalida": {
      const soSimOuNao = r?.motivo === "so_sim_ou_nao";
      const aviso = soSimOuNao ? textoOkNaoAprova(codigo) : textoInvalida(ctx.interp, ctx.passo, r?.motivo).trim();
      const { chave, abre, reenvia } = chaveDaPergunta(proxima, ctx.respondida, ctx.chave);
      const texto = proxima && !soSimOuNao ? [aviso, textoDaPergunta(proxima)].filter(Boolean).join("\n") : aviso;
      await enviarMensagem(ctx.phone, texto, chave, abre, deps, reenvia);
      return trata(resultado);
    }
    case "corrigir": {
      if (r?.motivo === "cancelar_pede_motivo") {
        await enviarMensagem(ctx.phone, textoSemMotivo(numeroDoCmp(cmp ?? { numero: null, codigo }) ?? 0), ctx.chave, null, deps);
        return trata(resultado);
      }
      return await falarDaPergunta(proxima, null, ctx, codigo, r, deps, resultado);
    }
    case "resumo":
      return await falarDaPergunta(proxima, r?.motivo === "versao_mudou" ? "O resumo mudou; confira de novo." : null, ctx, codigo, r, deps, resultado);
    case "proximo":
      return await falarDaPergunta(proxima, r?.motivo === "depois" ? textoPulado(codigo) : null, ctx, codigo, r, deps, resultado);
    case "gravado": {
      const gravacao = (r?.gravacao ?? null) as Gravacao | null;
      const texto = textoDaGravacao({ cmp: cmp as CmpResumo, gravacao, proxima });
      const { chave, abre } = chaveDaPergunta(proxima, ctx.respondida, ctx.chave);
      await enviarMensagem(ctx.phone, texto, chave, abre, deps);
      if (cmp?.id) {
        const soAGravacao = textoDaGravacao({ cmp, gravacao, proxima: null }).split("\n\n")[0];
        depoisDoArquivo(ctx.phone, cmp.id, gravacao?.mes ?? null, `${codigo} gravado`, `${codigo} (id ${cmp.id})`, soAGravacao, deps);
      }
      return trata(resultado);
    }
    default:
      deps.log("resposta_desconhecida", { resultado });
      return trata("desconhecido");
  }
}

/** Manda a próxima pergunta (com uma linha antes, se há) ou, sem ela, o "ocupado"/"anotei". */
async function falarDaPergunta(
  proxima: PerguntaDoBanco | null,
  antes: string | null,
  ctx: Contexto & { respondida?: string },
  codigo: string,
  // deno-lint-ignore no-explicit-any
  r: any,
  deps: DependenciasDoFluxo,
  resultado: string,
): Promise<Saida> {
  if (proxima) {
    const { chave, abre, reenvia } = chaveDaPergunta(proxima, ctx.respondida ?? null, ctx.chave);
    const corpo = textoDaPergunta(proxima);
    await enviarMensagem(ctx.phone, antes ? `${antes}\n\n${corpo}` : corpo, chave, abre, deps, reenvia);
    return trata(resultado);
  }
  let texto: string;
  if (r?.motivo === "ocupado") texto = textoOcupado(codigo, r?.ocupado_por?.titulo);
  else if (antes) texto = antes;
  else texto = `Anotei para o ${codigo}.`;
  await enviarMensagem(ctx.phone, texto, ctx.chave, null, deps);
  return trata(resultado);
}

/**
 * O empate (a resposta podia ser para o CMP ou para o assistente): nada é aplicado. Com a pergunta
 * do CMP "interrompida" pela conversa com o assistente, ela é reapresentada (uma pergunta nova, não
 * interrompida: a próxima resposta vale); senão, o texto pede para citar a mensagem certa.
 */
async function falarDoEmpate(ctx: Contexto, deps: DependenciasDoFluxo): Promise<void> {
  const ativa = ctx.estado.ativa?.origem === "comprovante" ? ctx.estado.ativa : null;
  if (ativa?.interrompida_em && !ctx.estado.pendencia) {
    // deno-lint-ignore no-explicit-any
    const r = await rpc<any>(deps, "comprovante_proxima_pergunta", { p_phone: ctx.phone, p_motivo: "reabrir", p_cmp: ativa.referencia_id });
    if (r?.perguntou) {
      const p = r as PerguntaDoBanco;
      await enviarMensagem(ctx.phone, `${textoRetomadaInterrompida(p.cmp?.codigo ?? ativa.referencia_codigo ?? "comprovante")}\n\n${textoDaPergunta(p)}`,
        p.dedupe_key, p, deps);
      return;
    }
  }
  await enviarMensagem(ctx.phone, textoDoDesempate(ctx.estado), `cmp:d:${ctx.messageId}`, null, deps);
}

/** O texto solto logo depois da foto: dica do CMP que está chegando (não vai ao assistente). */
async function guardarDica(ctx: Contexto, deps: DependenciasDoFluxo): Promise<Saida> {
  const alvo = ctx.estado.cmp_chegando;
  if (!alvo) return { status: 200, corpo: { tratada: false, resultado: "assistente" } };
  // deno-lint-ignore no-explicit-any
  const r = await rpc<any>(deps, "comprovante_acrescentar_dica", { p_id: alvo.id, p_texto: ctx.texto, p_message_id: ctx.messageId });
  if (!r?.ok) return { status: 200, corpo: { tratada: false, resultado: "assistente" } };
  await enviarMensagem(ctx.phone, textoDica(typeof r.codigo === "string" ? r.codigo : alvo.codigo), ctx.chave, null, deps);
  return trata("dica");
}

/**
 * O dono citou a FOTO de um CMP: gravado → o cartão; senão, a resposta vale para a última pergunta
 * dele (se responde ao passo), ou o texto vira dica dele e a pergunta dele abre ("cmp N").
 */
async function respostaAFoto(ctx: Contexto, deps: DependenciasDoFluxo, agora: Date): Promise<Saida> {
  const foto = ctx.estado.citado_cmp;
  if (!foto) return { status: 200, corpo: { tratada: false, resultado: "assistente" } };
  const numero = Number(/(\d+)$/.exec(foto.codigo)?.[1] ?? 0);
  if (foto.gravado || foto.situacao === "cancelado") return await executarComando({ comando: "cmp", numero }, ctx, deps);
  const ultima = await ultimaPerguntaDoCmp(foto.id, deps);
  const i = ultima ? interpretarResposta(ultima.passo, ultima.opcoes, ctx.texto, agora) : null;
  if (ultima && i && ultima.passo !== "confirmar") return await responderA(ultima, i, ctx, deps);
  if (pareceDica(ctx.texto)) {
    await rpc(deps, "comprovante_acrescentar_dica", { p_id: foto.id, p_texto: ctx.texto, p_message_id: ctx.messageId });
  }
  return await executarComando({ comando: "cmp", numero }, ctx, deps);
}

/** Mensagem curta que não é resposta: "Não entendi para o CMP-00124…" + a pergunta de novo. */
async function naoEntendi(ctx: Contexto, deps: DependenciasDoFluxo): Promise<Saida> {
  const ativa = ctx.estado.ativa?.origem === "comprovante" ? ctx.estado.ativa : null;
  if (!ativa) return { status: 200, corpo: { tratada: false, resultado: "assistente" } };
  const codigo = ativa.referencia_codigo ?? "comprovante";
  // deno-lint-ignore no-explicit-any
  const r = await rpc<any>(deps, "comprovante_proxima_pergunta", { p_phone: ctx.phone, p_motivo: "reabrir", p_cmp: ativa.referencia_id });
  if (r?.perguntou) {
    const p = r as PerguntaDoBanco;
    await enviarMensagem(ctx.phone, `${textoNaoEntendi(codigo)}\n\n${textoDaPergunta(p)}`, p.dedupe_key, p, deps);
  } else {
    await enviarMensagem(ctx.phone, textoNaoEntendi(codigo), ctx.chave, null, deps);
  }
  return trata("nao_entendi");
}

function codigoDoNumero(n: number | null | undefined): string {
  return n ? `CMP-${String(n).padStart(5, "0")}` : "comprovante";
}

const MOTIVO_DO_CORRIGIR: Record<string, string> = {
  valor_invalido: "o valor não serve (ex.: 62,50)",
  data_invalida: "a data não serve (não pode ser futura)",
  forma_invalida: "a forma de pagamento não serve (pix, débito, crédito, dinheiro, boleto ou transferência)",
  os_nao_existe: "não achei essa OS",
  os_cancelada: "a OS está cancelada",
  os_rascunho: "a OS ainda é rascunho",
  categoria_nao_achada: "não achei essa categoria (mande *corrigir categoria* para ver a lista)",
};

/** O que vem depois de "corrigir" no texto do dono (para repetir no "qual dos dois?"). */
function comandoDoCorrigir(texto: string): string {
  const t = String(texto ?? "").trim().replace(/^[\s🎤"'“”‘’«»]+/u, "");
  const m = /^corrig\w*\s+(.+)$/i.exec(t);
  return (m?.[1] ?? "").replace(/[.!]+$/u, "").slice(0, 60);
}

/** comprovante_comando (cmp N, pular, sair, lote antigo, cancelar, feito, corrigir) e o texto de cada resultado. */
async function executarComando(cmd: Comando, ctx: Contexto, deps: DependenciasDoFluxo): Promise<Saida> {
  const falar = async (texto: string, abre: PerguntaDoBanco | null = null) => {
    await enviarMensagem(ctx.phone, texto, abre ? abre.dedupe_key : ctx.chave, abre, deps);
  };
  if (cmd.comando === "pendentes") {
    await listarPendentes(ctx.phone, ctx.messageId, deps);
    return { status: 200, corpo: { tratada: false, resultado: "pendentes" } };
  }
  if (cmd.comando === "corrigir_incompleto") {
    await falar(textoCorrigirIncompleto(cmd.campo));
    return trata("corrigir_incompleto");
  }
  if (cmd.comando === "corrigir_menu") {
    // no resumo, "corrigir" sozinho = "não" (o menu do corrigir); fora dele, como mandar
    const ativa = ctx.estado.ativa?.origem === "comprovante" ? ctx.estado.ativa : null;
    if (ativa?.passo === "confirmar") return await responderA({ id: ativa.id, passo: ativa.passo, opcoes: ativa.opcoes }, { tipo: "nao" }, ctx, deps);
    await falar(TEXTO_CORRIGIR_COMO);
    return trata("corrigir_como");
  }
  if (cmd.comando === "cancelar_contexto") {
    // "cancelar esse <motivo>": o CMP da pergunta aberta, senão o CMP em contexto (sempre com o código na resposta)
    const codigo = ctx.estado.ativa?.origem === "comprovante" ? ctx.estado.ativa.referencia_codigo : ctx.estado.cmp_em_contexto?.codigo;
    const numero = Number(/(\d+)$/.exec(String(codigo ?? ""))?.[1] ?? 0);
    if (!numero) {
      await falar(TEXTO_SEM_CMP);
      return trata("sem_cmp");
    }
    return await executarComando({ comando: "cancelar", numero, motivo: cmd.motivo }, ctx, deps);
  }
  if (cmd.comando === "cancelar" && (cmd.motivo ?? "").replace(/[^\p{L}]/gu, "").length < 3) {
    await falar(textoSemMotivo(cmd.numero));
    return trata("motivo_obrigatorio");
  }

  // deno-lint-ignore no-explicit-any
  const r = await rpc<any>(deps, "comprovante_comando", { p: { phone: ctx.phone, message_id: ctx.messageId, ...cmd } });
  const resultado = String(r?.resultado ?? "");
  deps.log("comando", { comando: cmd.comando, resultado });
  const numero = "numero" in cmd ? cmd.numero : null;
  const codigo = String(r?.codigo ?? r?.cmp?.codigo ?? r?.cancelamento?.codigo ?? codigoDoNumero(numero));
  const pergunta = (r?.pergunta ?? null) as PerguntaDoBanco | null;
  const motivoDoDono = cmd.comando === "cancelar" ? cmd.motivo : null;

  switch (resultado) {
    case "desligada":
      return { status: 200, corpo: { tratada: false, resultado } };
    case "cartao":
      await falar(textoDoCartao(r.cmp as CmpResumo, (r.efeitos ?? []) as Efeito[]));
      break;
    case "nao_existe":
      await falar(textoNaoExiste((cmd as { cmp?: number }).cmp ?? numero ?? 0));
      break;
    case "pergunta": {
      const antes = textoCorrigido(codigo, r?.corrigido);
      if (pergunta) await falar(antes ? `${antes}\n\n${textoDaPergunta(pergunta)}` : textoDaPergunta(pergunta), pergunta);
      else if (r?.motivo === "ocupado") await falar([antes, textoOcupado(codigo, r?.ocupado_por?.titulo)].filter(Boolean).join("\n"));
      else await falar(antes ?? `Não há o que perguntar sobre o ${codigo} agora.`);
      break;
    }
    case "qual_cmp":
      await falar(textoQualCmp(String(r?.gravado ?? "CMP"), String(r?.aberto ?? "CMP"), comandoDoCorrigir(ctx.texto)));
      break;
    case "pulado": {
      const antes = r?.codigo ? textoPulado(String(r.codigo)) : "Não há comprovante aberto para pular.";
      if (pergunta) await falar(`${antes}\n\n${textoDaPergunta(pergunta)}`, pergunta);
      else await falar(antes);
      break;
    }
    case "pausado":
      await falar(textoSair(Number(r?.fila ?? 0), Number(/(\d+)$/.exec(String(r?.codigo ?? ""))?.[1] ?? 0) || null));
      break;
    case "lote": {
      const entraram = Array.isArray(r?.entraram) ? r.entraram : [];
      const texto = String(textoLote(entraram, Number(r?.restam ?? 0)));
      if (pergunta) await falar(`${texto}\n\n${textoDaPergunta(pergunta)}`, pergunta);
      else await falar(texto);
      break;
    }
    case "motivo_obrigatorio":
      await falar(textoSemMotivo(numero ?? 0));
      break;
    case "cancelamento_recusado":
      await falar(textoDoCancelamento(codigo, motivoDoDono, (r?.cancelamento ?? null) as Cancelamento | null));
      break;
    case "cancelado": {
      const texto = textoDoCancelamento(codigo, motivoDoDono, (r?.cancelamento ?? null) as Cancelamento | null);
      if (pergunta) await falar(`${texto}\n\nPróximo: ${textoDaPergunta(pergunta)}`, pergunta);
      else await falar(texto);
      const id = await idDoCmp(ctx.phone, numero, deps);
      if (id) depoisDoArquivo(ctx.phone, id, null, `${codigo} cancelado`, `${codigo} (id ${id})`, texto, deps);
      break;
    }
    case "feito":
      await falar(textoFeito(codigo, Array.isArray(r?.resolvidas) ? r.resolvidas : []));
      break;
    case "ja_gravado":
      await falar(textoJaGravado(codigo, numeroDoCmp({ numero: null, codigo }) ?? numero));
      break;
    case "ja_cancelado":
      await falar(`O ${codigo} foi cancelado.`);
      break;
    case "sem_cmp":
      await falar(TEXTO_SEM_CMP);
      break;
    case "invalida":
      await falar(`Não consegui corrigir o ${codigo}: ${MOTIVO_DO_CORRIGIR[String(r?.motivo)] ?? "o dado não serve"}.`);
      break;
    default:
      deps.log("comando_desconhecido", { resultado });
      return trata("desconhecido");
  }
  return trata(resultado);
}

/** O id do CMP pelo número (o cancelamento não devolve o id; o arquivo vai a _CANCELADOS na hora). */
async function idDoCmp(phone: string, numero: number | null, deps: DependenciasDoFluxo): Promise<string | null> {
  if (!numero) return null;
  try {
    const { data } = await deps.admin.from("comprovantes").select("id").eq("numero", numero).eq("phone_normalized", phone).maybeSingle();
    return typeof data?.id === "string" ? data.id : null;
  } catch {
    return null; // o vigia move depois (dropbox_pendente = 'cancelar')
  }
}

/** Em segundo plano: o arquivo ao destino, o índice do mês e o par do histórico do assistente. */
function depoisDoArquivo(
  phone: string,
  id: string,
  mes: string | null,
  resumo: string,
  referencia: string,
  texto: string,
  deps: DependenciasDoFluxo,
): void {
  emSegundoPlano(deps, "depois_do_sim", (async () => {
    const m = await moverComMes(id, deps);
    const doMes = m.mes ?? mes;
    if (doMes) await atualizarIndice(doMes, deps);
    await gravarNoHistorico(phone, resumo, referencia, texto, deps);
  })());
}

async function listarPendentes(phone: string, messageId: string, deps: DependenciasDoFluxo): Promise<{ enviada: boolean; itens: number }> {
  // deno-lint-ignore no-explicit-any
  const r = await rpc<any>(deps, "comprovantes_pendentes", { p_phone: phone });
  const abertos = (Array.isArray(r?.abertos) ? r.abertos : []) as ItemPendente[];
  const texto = textoDosPendentes({ abertos, total: r?.total, antigos: r?.antigos });
  if (!texto) return { enviada: false, itens: 0 };
  const enviada = await enviarMensagem(phone, texto, `cmp:pend:${messageId}`, null, deps);
  if (enviada) await gravarNoHistorico(phone, "lista dos comprovantes em aberto", null, texto, deps);
  deps.log("pendentes", { itens: abertos.length, enviada });
  return { enviada, itens: abertos.length };
}

/**
 * "pendentes": primeiro os comprovantes em aberto (só se há algum; senão não manda nada) — o
 * webhook despacha a mensagem ao assistente depois, para as pendências gerais de hoje.
 */
export async function pendentes(p: { message_id: string; phone: string }, deps: DependenciasDoFluxo): Promise<{ enviada: boolean; itens: number }> {
  const conf = await conferirMensagemDoDono(p?.message_id, p?.phone, deps);
  if (!conf.ok) {
    deps.log("pendentes_recusado", { motivo: conf.motivo });
    return { enviada: false, itens: 0 };
  }
  const estado = await lerEstadoDoTelefone(deps.admin, p.phone, null);
  if (!estado.conversa || !estado.dono) return { enviada: false, itens: 0 };
  return await listarPendentes(p.phone, p.message_id, deps);
}

/**
 * Empate entre a pergunta do CMP e a pendência do assistente (< 2 min), a pergunta do CMP que a
 * pendência acabou de substituir, ou a pergunta do CMP "interrompida" pela conversa com o assistente:
 * nada é aplicado; pede para citar (ou reapresenta a pergunta do CMP).
 */
export async function desempatar(p: { message_id: string; phone: string; citado?: string | null }, deps: DependenciasDoFluxo): Promise<{ enviada: boolean }> {
  const conf = await conferirMensagemDoDono(p?.message_id, p?.phone, deps);
  if (!conf.ok) {
    deps.log("desempatar_recusado", { motivo: conf.motivo });
    return { enviada: false };
  }
  const estado: EstadoDoTelefone = await lerEstadoDoTelefone(deps.admin, p.phone, typeof p.citado === "string" ? p.citado : null);
  if (!estado.conversa || (estado.ativa?.origem !== "comprovante" && !estado.cmp_substituido)) return { enviada: false };
  await falarDoEmpate({ phone: p.phone, messageId: p.message_id, chave: `cmp:r:${p.message_id}`, texto: "", estado }, deps);
  return { enviada: true };
}

// ---------------------------------------------------------------------------------------------
// Dropbox: o destino final (move_v2 com o nome final) e o índice do mês
// ---------------------------------------------------------------------------------------------

function resumoDoErro(e: unknown): string {
  return String((e as { resumo?: unknown })?.resumo ?? "");
}

async function subirDoBucket(d: DestinoDoArquivo, destino: string, dbx: DropboxDoFluxo, deps: DependenciasDoFluxo): Promise<MetaDoDropbox | null> {
  if (!d.arquivo_path) return null;
  const baixado = await deps.admin.storage.from(BUCKET).download(d.arquivo_path);
  if (baixado?.error || !baixado?.data) return null;
  const bytes = new Uint8Array(await (baixado.data as Blob).arrayBuffer());
  return await dbx.enviar(destino, bytes, true);
}

/**
 * Leva o arquivo do CMP ao destino final (comprovante_destino_do_arquivo decide; aqui só a pasta e
 * o nome): com dropbox_id, move_v2 (mesmo id); sem ele (a cópia da F1 não subiu), envia direto do
 * bucket — nunca duas cópias. Falha → comprovante_dropbox_mover_falhou (backoff do banco). O
 * movimento feito (o dropbox_pendente LIDO agora) vai junto: se o dono cancelou no meio, o banco
 * não apaga o "cancelar" pedido depois.
 */
async function moverComMes(id: string, deps: DependenciasDoFluxo): Promise<{ movido: boolean; mes: string | null }> {
  const d = await rpc<DestinoDoArquivo | null>(deps, "comprovante_destino_do_arquivo", { p_id: id });
  if (!d?.id) return { movido: false, mes: null };
  const mes = mesDoArquivo(d);
  if (!d.dropbox_pendente) return { movido: false, mes };
  const pendente = d.dropbox_pendente;
  const falhar = async (codigo: string) => {
    const f = await rpc(deps, "comprovante_dropbox_mover_falhou", { p_id: id, p_erro: codigo.slice(0, 300), p_pendente: pendente });
    deps.log("mover_falhou", { id, codigo, desistiu: Boolean(f?.desistiu) });
    return { movido: false, mes };
  };
  let dbx: DropboxDoFluxo | null;
  try {
    dbx = await deps.dropbox();
  } catch {
    return await falhar("dropbox_conexao_ilegivel");
  }
  if (!dbx) return await falhar("dropbox_sem_conexao");

  const cancelado = d.cancelado === true || d.situacao === "cancelado" || d.dropbox_pendente === "cancelar";
  let meta: MetaDoDropbox | null = null;
  try {
    let raizDoBarco: string | null = null;
    if (!cancelado && d.destino === "os" && d.os) {
      const base = String((await lerConfiguracoes(deps, ["dropbox_pasta_base"])).dropbox_pasta_base ?? "").trim();
      if (usaPastaDoBarco(d, Boolean(base))) {
        const p = { vesselId: String(d.os.vessel_id), clientId: String(d.os.client_id), barco: d.os.barco, cliente: d.os.cliente, pastaBase: base };
        // pasta nova só nasce com a pasta-base configurada (sem ela, nasceria na raiz do Dropbox):
        // sem base, só a registrada que ainda existe; nenhuma → a pasta do mês
        const pasta = deps.pastaDoBarco
          ? await deps.pastaDoBarco(dbx, p)
          : base
          ? await garantirPastaDoBarco(deps.admin, dbx, p)
          : await pastaRegistradaDoBarco(deps.admin, dbx, p.vesselId);
        raizDoBarco = pasta?.caminho ?? null;
      }
    }
    const pasta = pastaFinal(d, raizDoBarco);
    // a pasta das compras nasce aqui, na primeira compra do barco (o modelo de pastas do barco não muda)
    if (raizDoBarco) await dbx.criarPasta(pasta);
    const nome = cancelado ? nomeCancelado(nomeDoCaminho(d.dropbox_caminho) ?? nomeFinal(d)) : nomeFinal(d);
    const destino = `${pasta}/${nome}`;

    if (d.dropbox_id) {
      // onde está agora (pelo id): já no destino (a gravação anterior não registrou) → só registra
      let atual: MetaDoDropbox | null = null;
      try {
        atual = await dbx.rpc<MetaDoDropbox>("files/get_metadata", { path: d.dropbox_id });
      } catch (e) {
        if (!resumoDoErro(e).startsWith("path/not_found")) throw e;
      }
      if (atual && atual.path_display.toLowerCase() === destino.toLowerCase()) meta = atual;
      else if (atual) meta = await dbx.mover(d.dropbox_id, destino, true);
      else meta = await subirDoBucket(d, destino, dbx, deps); // o dono apagou a cópia: sobe de novo
    } else {
      meta = await subirDoBucket(d, destino, dbx, deps);
    }
  } catch (e) {
    if (e instanceof FalhaDoFluxo) throw e;
    return await falhar(codigoDoDropbox(e));
  }
  if (!meta) return await falhar("arquivo_indisponivel");
  // Moveu: a partir daqui, falha do banco NÃO pede outro movimento (o get_metadata acha no destino).
  await rpc(deps, "comprovante_dropbox_movido", {
    p_id: id, p_dropbox_id: meta.id, p_caminho: meta.path_display, p_rev: meta.rev ?? null, p_pendente: pendente,
  });
  deps.log("dropbox_movido", { id, cancelado });
  return { movido: true, mes };
}

export async function moverNoDropbox(id: string, deps: DependenciasDoFluxo): Promise<boolean> {
  return (await moverComMes(id, deps)).movido;
}

/**
 * Regrava o "_INDICE AAAA-MM.csv" do mês com TODOS os CMPs dele (inclusive os das pastas dos barcos,
 * PESSOAL e cancelados): substituir pelo rev guardado; conflito (o dono mexeu) → novo arquivo, e o
 * registro passa a apontar para ele.
 */
export async function atualizarIndice(mes: string, deps: DependenciasDoFluxo): Promise<boolean> {
  const m = /^(\d{4}-\d{2})/.exec(String(mes ?? ""))?.[1];
  if (!m) return false;
  const pMes = `${m}-01`;
  const falhar = async (codigo: string) => {
    const f = await rpc(deps, "comprovante_indice_falhou", { p_mes: pMes, p_erro: codigo.slice(0, 300) });
    deps.log("indice_falhou", { mes: m, codigo, desistiu: Boolean(f?.desistiu) });
    return false;
  };
  // deno-lint-ignore no-explicit-any
  const r = await rpc<any>(deps, "comprovantes_indice_do_mes", { p_mes: pMes });
  const linhas = (Array.isArray(r) ? r : Array.isArray(r?.linhas) ? r.linhas : []) as LinhaDoIndice[];

  let registro: { caminho: string | null; rev: string | null };
  if (r && !Array.isArray(r) && ("rev" in r || "caminho" in r)) {
    registro = { caminho: r.caminho ?? null, rev: r.rev ?? null };
  } else {
    const { data, error } = await deps.admin.from("comprovantes_indice_mensal").select("caminho, rev").eq("mes", pMes).maybeSingle();
    if (error) throw new FalhaDoFluxo(`ler_indice:${error.code ?? "erro"}`);
    registro = { caminho: data?.caminho ?? null, rev: data?.rev ?? null };
  }

  let dbx: DropboxDoFluxo | null;
  try {
    dbx = await deps.dropbox();
  } catch {
    return await falhar("dropbox_conexao_ilegivel");
  }
  if (!dbx) return await falhar("dropbox_sem_conexao");

  const comRev = Boolean(registro.caminho && registro.rev);
  const caminho = comRev ? String(registro.caminho) : caminhoDoIndice(m);
  let meta: MetaDoDropbox & { conflito: boolean };
  try {
    meta = await dbx.substituir(caminho, new TextEncoder().encode(csvDoIndice(linhas)), comRev ? registro.rev : null);
  } catch (e) {
    return await falhar(codigoDoDropbox(e));
  }
  await rpc(deps, "comprovante_indice_gravado", {
    p_mes: pMes, p_dropbox_id: meta.id, p_caminho: meta.path_display, p_rev: meta.rev, p_linhas: linhas.length,
  });
  deps.log("indice_gravado", { mes: m, linhas: linhas.length, conflito: meta.conflito });
  return true;
}

// ---------------------------------------------------------------------------------------------
// Fornecedor pela Receita (BrasilAPI, com cache no banco) — nunca do OCR
// ---------------------------------------------------------------------------------------------

function textoCurto(v: unknown, max: number): string | null {
  return typeof v === "string" && v.trim() ? v.trim().slice(0, max) : null;
}

/**
 * GET https://brasilapi.com.br/api/cnpj/v1/<14> (8 s) → comprovante_cnpj_cache. Fora do ar: nada (o
 * texto mostra o CNPJ). O nome vai SEM CPF (a razão social do MEI traz o do titular; o banco também limpa).
 */
export async function consultarCnpj(cnpj: string, deps: DependenciasDoFluxo): Promise<void> {
  if (!/^\d{14}$/.test(String(cnpj ?? ""))) return;
  let res: Response;
  try {
    res = await deps.fetch(`https://brasilapi.com.br/api/cnpj/v1/${cnpj}`, {
      headers: { Accept: "application/json" },
      signal: AbortSignal.timeout(PRAZO_DA_BRASILAPI_MS),
    });
  } catch {
    deps.log("cnpj_sem_resposta", {});
    return;
  }
  if (res.status === 404 || res.status === 400) {
    await res.body?.cancel().catch(() => {});
    await rpc(deps, "comprovante_cnpj_cache", { p_cnpj: cnpj, p_dados: { encontrado: false } });
    deps.log("cnpj", { encontrado: false });
    return;
  }
  if (!res.ok) {
    await res.body?.cancel().catch(() => {});
    deps.log("cnpj_recusado", { status: res.status });
    return;
  }
  const j = await res.json().catch(() => null) as Record<string, unknown> | null;
  if (!j) return;
  await rpc(deps, "comprovante_cnpj_cache", {
    p_cnpj: cnpj,
    p_dados: {
      encontrado: true,
      razao_social: textoCurto(semCpf(textoCurto(j.razao_social, 300)), 200),
      nome_fantasia: textoCurto(semCpf(textoCurto(j.nome_fantasia, 300)), 200),
      situacao_cadastral: textoCurto(j.descricao_situacao_cadastral ?? j.situacao_cadastral, 60),
    },
  });
  deps.log("cnpj", { encontrado: true });
}

/** Os CNPJs destes CMPs ainda sem cache (no máximo 3), antes de perguntar. Nunca lança. */
async function consultarCnpjsDosIds(ids: string[], deps: DependenciasDoFluxo): Promise<void> {
  try {
    const lista = await rpc<unknown>(deps, "comprovantes_cnpj_a_consultar", { p_ids: ids, p_limite: LIMITE_DE_CNPJ });
    const cnpjs = (Array.isArray(lista) ? lista : []).filter((c): c is string => typeof c === "string").slice(0, LIMITE_DE_CNPJ);
    await Promise.allSettled(cnpjs.map((c) => consultarCnpj(c, deps)));
  } catch (e) {
    deps.log("cnpj_falhou", { codigo: codigoDoErro(e) });
  }
}

// ---------------------------------------------------------------------------------------------
// O par do histórico do assistente (gravação, cancelamento, pendentes)
// ---------------------------------------------------------------------------------------------

/**
 * Grava o par 🤖 em ai_operator_messages para o assistente ter o contexto. Se as duas últimas linhas
 * da sessão já são um par deste fluxo de menos de 2 h, acrescenta ao assistant (até 4000 caracteres)
 * em vez de inserir outro par. As perguntas e as respostas do menu NÃO entram. Nunca lança.
 */
async function gravarNoHistorico(phone: string, resumo: string, referencia: string | null, texto: string, deps: DependenciasDoFluxo): Promise<void> {
  try {
    const dono = await donoDoWhatsApp(deps.admin);
    if (!dono || dono.phone !== phone) return;
    const sessao = deps.sessaoDoWhatsApp
      ? await deps.sessaoDoWhatsApp(phone, dono.id)
      : await resolveOrCreateWhatsAppSession(deps.admin, phone, dono.id);
    const h = historicoDoFluxo(resumo, referencia, texto);
    const agora = deps.agora().getTime();
    const { data: ultimas, error: eLer } = await deps.admin
      .from("ai_operator_messages")
      .select("id, role, content, created_at")
      .eq("session_id", sessao)
      .order("created_at", { ascending: false })
      .limit(2);
    const [ultima, penultima] = (eLer ? [] : (ultimas ?? [])) as Array<{ id: string; role: string; content: string; created_at: string }>;
    if (
      ultima?.role === "assistant" && penultima?.role === "user" && String(penultima.content ?? "").startsWith(MARCA_DO_FLUXO) &&
      agora - Date.parse(ultima.created_at) < JANELA_DO_HISTORICO_MS
    ) {
      const junto = `${ultima.content}\n\n${h.assistant}`;
      if (junto.length <= MAX_HISTORICO) {
        const { error } = await deps.admin.from("ai_operator_messages").update({ content: junto }).eq("id", ultima.id);
        if (error) deps.log("historico_nao_gravado", { codigo: error.code ?? "erro" });
        return;
      }
    }
    const { error } = await deps.admin.from("ai_operator_messages").insert([
      { session_id: sessao, role: "user", source: "whatsapp", created_at: new Date(agora).toISOString(), content: h.user },
      { session_id: sessao, role: "assistant", source: "whatsapp", created_at: new Date(agora + 1).toISOString(), content: h.assistant.slice(0, MAX_HISTORICO) },
    ]);
    if (error) deps.log("historico_nao_gravado", { codigo: error.code ?? "erro" });
  } catch (e) {
    deps.log("historico_nao_gravado", { codigo: codigoDoErro(e) });
  }
}
