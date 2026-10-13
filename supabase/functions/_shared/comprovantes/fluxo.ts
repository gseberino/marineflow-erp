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
//
// F3 (11/10/2026 — spec-f3.md, 4.4): a pergunta do extrato ("apareceu no extrato, ligo?"), no mesmo
// registro único (passo "banco"): o banco escolhe as linhas e o nível (comprovante_banco_proxima) e
// aplica a resposta (comprovante_banco_responder, com o autor = o dono); aqui só se abre, envia e
// fala. Abre depois da gravação (azul), no "cmp N" com a pergunta pendente e pelo vigia
// (comprovantes_vigia_banco: horário, espaçamento e limite são do banco; a fila da F2 vem primeiro).
// Sem conversa ligada ou com o modo de teste do whatsapp-send, nada é perguntado. O índice da pasta
// PESSOAL (padrão do dono: a contadora não vê os pessoais) é regravado pelo vigia como o do mês.
//
// Ajustes do dono (11/10/2026 — spec-ajustes-dono.md): o SIM já aprova a linha no Extrato — quando a
// R4 ou a gravação devolvem `aprovar` (a proposta classificada), o edge chama o finance-review
// (approve_cmp, interna, com o dono como quem decide) ANTES de montar o texto, que diz "lancei no
// Extrato" ou "não consegui aprovar agora: tento de novo na próxima rodada" (o "gerar" tenta de
// novo). A regra E ("quem pagou?" depois de 5 dias sem aparecer em conta da empresa) é o passo
// "banco_quem" da mesma R4: esperando / regravado / não trocado.
//
// O assistente opera o CMP (11/10/2026 — spec-assistente-opera-cmp.md): a ação `completar` recebe do
// assistente (tool completar_comprovante) o que o dono disse em conversa e aplica por uma RPC só
// (comprovante_completar, 12/10/2026 — spec-observacao-atomica-prefixo.md), tudo ou nada; por dentro,
// as mesmas do menu e do *corrigir* (comprovante_comando e comprovante_responder). Nada grava no
// financeiro: a última pergunta (ou o resumo) vai ao dono numa mensagem só, e só o sim dele grava. No
// "para quê", a palavra de categoria é dica (B): grava a categoria e repergunta o destino com o mesmo
// menu. A observação do dono (*corrigir obs …*, *observação: …* ou a da tool) fica guardada no CMP.
import { EvolutionProvider } from "../whatsapp/evolution-provider.ts";
import type { IncomingMessageEvent } from "../whatsapp/types.ts";
import { type Dono, donoDoWhatsApp } from "../whatsapp/dono.ts";
import { pendenciaQueSegueEsperando, resolveOrCreateWhatsAppSession } from "../ai/whatsapp-channel.ts";
import { logEdgeError } from "../log-error.ts";
import { conversaDosComprovantesLigada, lerModoDoComprovante } from "./modo.ts";
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
  categoriaDaPalavra,
  classeDoComando,
  type Comando,
  ehPassoDoExtrato,
  type Interpretacao,
  interpretarResposta,
  lerComando,
  type Palavra,
  pareceDica,
  respostaNaoEntendida,
} from "./respostas.ts";
import {
  type AAprovar,
  type Aprovacao,
  type Cancelamento,
  type CmpResumo,
  comAPergunta,
  type ItemAnotado,
  textoDaCategoriaAnotada,
  textoDoAnotadoNaConversa,
  textosDosItensAnotados,
  type Efeito,
  ehEstadoDoQuemPagou,
  ehPerguntaAzul,
  type Gravacao,
  historicoDoFluxo,
  type ItemPendente,
  MARCA_DO_FLUXO,
  motivoDoNaoGravado,
  motivoDoNaoLigado,
  numeroDoCmp,
  type PerguntaDoBanco,
  type PerguntaDoExtrato,
  prefixoDaPergunta,
  prefixoDaPerguntaDoExtrato,
  type RespostaDoBanco,
  textoDaPerguntaDoExtrato,
  textoDoLigado,
  textoDoMudou,
  textoDoNaoTrocado,
  textoDoQuemEsperando,
  textoDoRecusado,
  textoDoRegravado,
  textoInvalidaDoExtrato,
  textoInvalidaDoQuemPagou,
  textoNaoLigado,
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
  textosDosAvisos,
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
  caminhoDoIndicePessoal,
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
  /** Ajustes do dono: o CRON_SECRET da chamada interna ao finance-review (approve_cmp). */
  cronSecret?: string;
  /**
   * Ajustes do dono, para os testes: aprovar no Extrato a linha que o sim ligou. O padrão é o POST
   * interno ao finance-review (approve_cmp, 15 s). Nunca lança: falha = { ok: false, motivo }.
   */
  aprovarNoExtrato?(cmpId: string, donoId: string): Promise<Aprovacao>;
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
          let r = await abrirPergunta(phone, "abertura", deps, null, ordem[0]?.id ?? null);
          // F3: ocupado com a pergunta do extrato (o vigia abre e ela vale 2 h)? O comprovante novo passa
          // na frente: ela cede a vez (fecha "substituida"; o vigia volta a ela depois) e a F2 pergunta já
          if (!r.perguntou && r.motivo === "ocupado" && await cederPerguntaDoExtrato(phone, deps)) {
            r = await abrirPergunta(phone, "abertura", deps, null, ordem[0]?.id ?? null);
          }
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
  /**
   * F2: arquivos levados ao destino final, índices regravados, CNPJs consultados, perguntas abertas.
   * F3: `indices` inclui os da pasta PESSOAL e `perguntas` as do extrato (a forma da resposta não muda;
   * o log do vigia traz os dois números à parte).
   */
  movidos: number;
  indices: number;
  cnpj: number;
  perguntas: number;
};

/** F3: no máximo 5 telefones por rodada do vigia para a pergunta do extrato (R6). */
const LIMITE_DO_VIGIA_DO_BANCO = 5;

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
  /** F3, só para o log: quantos dos índices são da pasta PESSOAL e quantas perguntas são do extrato. */
  const f3 = { indices_pessoais: 0, perguntas_banco: 0 };
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
    // F3: o índice próprio da pasta PESSOAL (o do mês, da contadora, não lista os pessoais)
    await cada<string>(conversa.indices_pessoais, "indice_pessoal", async (mes) => {
      if (await atualizarIndicePessoal(mes, deps)) {
        n.indices++;
        f3.indices_pessoais++;
      }
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

  // F3: a pergunta do extrato, DEPOIS da conversa da F2 (o banco só devolve o telefone que passou no
  // horário, no espaçamento de 4 h, no limite de 3 e com a fila da F2 vazia). Erro só registra.
  if (temTempo()) {
    // deno-lint-ignore no-explicit-any
    let banco: any = null;
    try {
      banco = await rpc(deps, "comprovantes_vigia_banco", { p_limite: LIMITE_DO_VIGIA_DO_BANCO });
    } catch (e) {
      deps.log("vigia_banco_falhou", { codigo: codigoDoErro(e) });
    }
    await cada<string>(banco?.perguntar, "perguntar_banco", async (phone) => {
      if (await perguntarBanco(phone, "vigia", deps)) {
        n.perguntas++;
        f3.perguntas_banco++;
      }
    });
  }
  deps.log("vigia", { ...n, ...f3, ms: deps.agora().getTime() - inicio });
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
 * (o CMP volta à fila; a pergunta do vigia que não saiu não conta como tentativa e ele tenta de novo
 * em 4 h — 13/10/2026). `reenvia` = a pergunta aberta que ela REAPRESENTA (a
 * resposta não serviu, o "responda sim a este resumo"). Nos dois casos, o envio confirmado fica
 * registrado na pergunta (enviada_em + o id do WhatsApp: a citação do reenvio também acha).
 */
/** A pergunta que a mensagem abre: a da fila da F2 (PerguntaDoBanco) ou a do extrato da F3 (PerguntaDoExtrato). */
type PerguntaQueAbre = { pergunta_id: string; passo: string; cmp?: { id?: string | null } | null };

async function enviarMensagem(
  phone: string,
  texto: string,
  chave: string,
  abre: PerguntaQueAbre | null,
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
// F3: a pergunta do extrato (comprovante_banco_proxima = R3 da spec-f3.md)
// ---------------------------------------------------------------------------------------------

/**
 * R3 sem enviar: a pergunta do extrato aberta pelo banco, ou null (desligada, cinza, ocupado, modo
 * de teste, erro). `motivo` ∈ vigia, depois_de_gravar, pendentes, cmp, reabrir; o vigia é quem
 * respeita horário/espaçamento (o banco confere). Nunca lança: a falha vira log com o código.
 */
async function abrirPerguntaDoExtrato(
  phone: string,
  motivo: string,
  cmp: string | null,
  deps: DependenciasDoFluxo,
): Promise<PerguntaDoExtrato | null> {
  if (await modoDeTesteLigado(deps)) {
    deps.log("pergunta_extrato_recusada", { motivo: "modo_de_teste" });
    return null;
  }
  try {
    // deno-lint-ignore no-explicit-any
    const r = await rpc<any>(deps, "comprovante_banco_proxima", { p_phone: phone, p_motivo: motivo, p_cmp: cmp ?? null });
    if (!r?.perguntou || typeof r?.pergunta_id !== "string") {
      deps.log("pergunta_extrato_nao_aberta", { motivo: typeof r?.motivo === "string" ? r.motivo.slice(0, 40) : null, origem: motivo });
      return null;
    }
    return r as PerguntaDoExtrato;
  } catch (e) {
    deps.log("pergunta_extrato_falhou", { codigo: codigoDoErro(e), origem: motivo });
    return null;
  }
}

/**
 * R10: a pergunta do extrato aberta no telefone cede a vez ao comprovante novo (só ela: a da F2 e a
 * pendência do assistente, não). true = cedeu. Nunca lança: a falha vira log com o código.
 */
async function cederPerguntaDoExtrato(phone: string, deps: DependenciasDoFluxo): Promise<boolean> {
  try {
    const r = await rpc<{ cedeu?: boolean; codigo?: string | null }>(deps, "comprovante_banco_ceder", { p_phone: phone });
    if (r?.cedeu) deps.log("pergunta_extrato_cedeu", { codigo: typeof r.codigo === "string" ? r.codigo.slice(0, 20) : null });
    return Boolean(r?.cedeu);
  } catch (e) {
    deps.log("pergunta_extrato_ceder_falhou", { codigo: codigoDoErro(e) });
    return false;
  }
}

/**
 * Abre a pergunta do extrato (R3) e a envia (com a retomada do vigia: "Ainda falta ligar o CMP-00124
 * ao extrato."). Envio não confirmado → comprovante_pergunta_nao_enviada (a tentativa do vigia que
 * não saiu não conta: o banco a devolve — 13/10/2026). true = perguntou.
 */
export async function perguntarBanco(phone: string, motivo: string, deps: DependenciasDoFluxo, cmp: string | null = null): Promise<boolean> {
  const p = await abrirPerguntaDoExtrato(phone, motivo, cmp, deps);
  if (!p) return false;
  const texto = textoDaPerguntaDoExtrato(p, prefixoDaPerguntaDoExtrato(p, motivo));
  const enviou = await enviarMensagem(phone, texto, p.dedupe_key, p, deps);
  deps.log("pergunta_extrato", { id: p.cmp?.id ?? null, nivel: p.banco?.nivel ?? null, origem: motivo, enviada: enviou });
  return enviou;
}

/**
 * Depois de ligar (o dono respondeu): a próxima pergunta, a da fila da F2 primeiro (o comprovante
 * novo espera mais que a linha do extrato), senão outra do extrato. Sem enviar; null = nenhuma.
 */
async function proximaDepoisDoExtrato(
  phone: string,
  deps: DependenciasDoFluxo,
): Promise<{ f2: PerguntaDoBanco; extrato: null } | { f2: null; extrato: PerguntaDoExtrato } | null> {
  if (await modoDeTesteLigado(deps)) return null;
  try {
    // deno-lint-ignore no-explicit-any
    const r = await rpc<any>(deps, "comprovante_proxima_pergunta", { p_phone: phone, p_motivo: "depois_de_gravar", p_cmp: null });
    if (r?.perguntou && typeof r?.pergunta_id === "string") return { f2: r as PerguntaDoBanco, extrato: null };
  } catch (e) {
    deps.log("pergunta_nao_aberta", { codigo: codigoDoErro(e) });
  }
  const b = await abrirPerguntaDoExtrato(phone, "depois_de_gravar", null, deps);
  return b ? { f2: null, extrato: b } : null;
}

// ---------------------------------------------------------------------------------------------
// Ajustes do dono: o sim aprova a linha no Extrato (finance-review, approve_cmp)
// ---------------------------------------------------------------------------------------------

const PRAZO_DA_APROVACAO_MS = 15_000;

/**
 * O POST interno ao finance-review (approve_cmp) com o CRON_SECRET e o dono como quem decide (a
 * aprovação tem dono, como a da tela). Nunca lança: sem segredo, fora do ar ou sem resposta em 15 s
 * = { ok: false } (o "gerar" do Extrato tenta de novo).
 */
async function aprovarPeloFinanceReview(cmpId: string, donoId: string, deps: DependenciasDoFluxo): Promise<Aprovacao> {
  if (!deps.cronSecret) return { ok: false, motivo: "sem_resposta" };
  try {
    const res = await deps.fetch(`${deps.supabaseUrl}/functions/v1/finance-review`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-cron-secret": deps.cronSecret },
      body: JSON.stringify({ action: "approve_cmp", cmp_id: cmpId, acting_user_id: donoId }),
      signal: AbortSignal.timeout(PRAZO_DA_APROVACAO_MS),
    });
    // deno-lint-ignore no-explicit-any
    const j = await res.json().catch(() => null) as any;
    if (!res.ok || !j || typeof j !== "object") return { ok: false, motivo: "sem_resposta" };
    return { ok: j.ok === true, nada: j.nada === true, motivo: typeof j.motivo === "string" ? j.motivo.slice(0, 200) : null };
  } catch {
    return { ok: false, motivo: "sem_resposta" };
  }
}

/**
 * Se a R4/gravação disse qual proposta o sim aprova (`aprovar`), aprova agora — antes de montar o
 * texto, que diz o que aconteceu. Sem `aprovar`, null (nada a aprovar agora: a linha já tinha
 * lançamento, ou a proposta ainda não está na fila e o "gerar" aprova quando ela entrar). Nunca lança;
 * o log leva só o código.
 */
async function aprovarSeHouver(
  cmpId: string | null | undefined,
  donoId: string | null | undefined,
  aAprovar: AAprovar | undefined,
  deps: DependenciasDoFluxo,
): Promise<Aprovacao | null> {
  if (!cmpId || !aAprovar || typeof aAprovar !== "object" || !aAprovar.proposta_id) return null;
  let r: Aprovacao;
  if (!donoId) r = { ok: false, motivo: "sem_resposta" };
  else {
    try {
      r = await (deps.aprovarNoExtrato ? deps.aprovarNoExtrato(cmpId, donoId) : aprovarPeloFinanceReview(cmpId, donoId, deps));
    } catch {
      r = { ok: false, motivo: "sem_resposta" };
    }
  }
  const motivo = typeof r?.motivo === "string" && /^[a-z_:0-9]{1,40}$/.test(r.motivo) ? r.motivo : r?.motivo ? "texto" : null;
  deps.log("aprovacao_do_sim", { id: cmpId, ok: Boolean(r?.ok), nada: Boolean(r?.nada), motivo });
  return r ?? { ok: false, motivo: "sem_resposta" };
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
async function conferirMensagemDoDono(messageId: unknown, phone: unknown, deps: DependenciasDoFluxo): Promise<{ ok: true; donoId: string } | Recusa> {
  if (typeof messageId !== "string" || !UUID.test(messageId) || typeof phone !== "string" || !/^\d{10,15}$/.test(phone)) {
    return { ok: false, motivo: "entrada_invalida" };
  }
  const msg = await lerMensagem(deps, messageId);
  if (!msg) return { ok: false, motivo: "mensagem_inexistente" };
  if (msg.direction !== "inbound") return { ok: false, motivo: "nao_e_recebida" };
  if (msg.phone_normalized !== phone) return { ok: false, motivo: "telefone_divergente" };
  const dono = await donoDoWhatsApp(deps.admin);
  if (!dono || dono.phone !== phone) return { ok: false, motivo: "dono_divergente" };
  return { ok: true, donoId: dono.id };
}

/** `donoId`: quem responde (F3: o autor que comprovante_banco_responder confere contra o dono do CMP). */
type Contexto = { phone: string; messageId: string; chave: string; texto: string; estado: EstadoDoTelefone; donoId?: string | null };
type Saida = { status: 200; corpo: { tratada: boolean; resultado?: string; motivo?: string } };

const DESTINOS_DO_RESPONDER = new Set(["comprovante", "comprovante_reabrir", "comando", "dica", "foto_do_cmp", "nao_entendi"]);

/**
 * A frase de resposta ao passo da última pergunta de CMP (a resposta atrasada): de dado, não
 * sim/não/ok. F3: a pergunta do extrato que fechou sem resposta não é reaberta por um número solto
 * (o vigia pergunta de novo, com as linhas de agora); citando a mensagem dela, vale.
 */
function respondeAUltima(estado: EstadoDoTelefone, texto: string, agora: Date): boolean {
  const u = estado.ultima_do_cmp;
  if (!u || estado.ativa || ehPassoDoExtrato(u.passo)) return false;
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
  const ctx: Contexto = { phone: p.phone, messageId: p.message_id, chave: `cmp:r:${p.message_id}`, texto: p.texto, estado, donoId: conf.donoId };

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
      let alvo: AlvoDaResposta | null = null;
      if (estado.citada?.origem === "comprovante") {
        alvo = estado.citada.id === ativa?.id
          ? { id: ativa.id, passo: ativa.passo, opcoes: ativa.opcoes, codigo: ativa.referencia_codigo }
          : await perguntaPeloId(estado.citada.id, deps);
      } else if (ativa) {
        alvo = { id: ativa.id, passo: ativa.passo, opcoes: ativa.opcoes, codigo: ativa.referencia_codigo };
      } else if (decisao.motivo === "resposta_atrasada" && estado.ultima_do_cmp) {
        const u = estado.ultima_do_cmp;
        alvo = { id: u.id, passo: u.passo, opcoes: u.opcoes, codigo: u.referencia_codigo };
      }
      if (!alvo) return { status: 200, corpo: { tratada: false, resultado: "sem_pergunta" } };
      const i = alvo.id === ativa?.id ? interp : interpretarResposta(alvo.passo, alvo.opcoes, p.texto, agora);
      if (!i) return { status: 200, corpo: { tratada: false, resultado: "texto_livre" } };
      // F3: a pergunta do extrato de um CMP já gravado tem a RPC dela (o comprovante_responder ignora o
      // gravado) — também o "quem pagou?" da regra E (passo banco_quem)
      if (ehPassoDoExtrato(alvo.passo)) return await responderAoExtrato(alvo, i, ctx, deps);
      return await responderA(alvo, i, ctx, deps);
    }
  }
}

/** A pergunta a que a resposta vale; `codigo` = o CMP dela (referencia_codigo: a dica de categoria precisa do número). */
type AlvoDaResposta = { id: string; passo: string | null; opcoes: Opcao[]; codigo?: string | null };

/** "CMP-00124" → 124 (null se não dá para ler). */
function numeroDoCodigo(codigo: string | null | undefined): number | null {
  const n = Number(/(\d+)\s*$/.exec(String(codigo ?? ""))?.[1] ?? 0);
  return n > 0 ? n : null;
}

/**
 * comprovante_responder na pergunta e o texto ao dono. Se a RPC falhou, nada foi gravado (a transação
 * voltou): aqui se sabe disso, e o aviso "mande de novo" sai com a MESMA chave do aviso do webhook
 * (cmp:f:<mensagem>) — o whatsapp-send manda uma vez só.
 *
 * B (11/10/2026): a categoria como dica nunca chega ao comprovante_responder. Só a categoria
 * ("combustível") → o comando corrigir categoria do CMP da pergunta (fecha a pergunta e repergunta o
 * destino com o mesmo menu). A palavra com a categoria ("combustível da empresa") → responde a palavra
 * e depois grava a categoria pelo comando (que fecha, sem envio, a pergunta que a resposta abriu), numa
 * mensagem só.
 */
async function responderA(
  alvo: AlvoDaResposta,
  i: Interpretacao,
  ctx: Contexto,
  deps: DependenciasDoFluxo,
): Promise<Saida> {
  if (i.tipo === "categoria") {
    const numero = numeroDoCodigo(alvo.codigo);
    if (!numero) return await naoEntendi(ctx, deps);
    return await executarComando({ comando: "corrigir", campo: "categoria", categoria: i.categoria, cmp: numero }, ctx, deps, { comoDica: true });
  }
  const categoria = i.tipo === "palavra" ? i.categoria ?? null : null;
  const interpretacao: Interpretacao = i.tipo === "palavra" ? { tipo: "palavra", valor: i.valor } : i;
  // deno-lint-ignore no-explicit-any
  let r: any;
  try {
    r = await rpc(deps, "comprovante_responder", {
      p: { pergunta_id: alvo.id, message_id: ctx.messageId, interpretacao, versao: null },
    });
  } catch (e) {
    await enviarAoDono(ctx.phone, TEXTO_FALHA, `cmp:f:${ctx.messageId}`, deps);
    throw e;
  }
  const numero = r?.cmp ? numeroDoCmp(r.cmp as CmpResumo) : null;
  if (categoria && numero && (r?.resultado === "proximo" || r?.resultado === "resumo")) {
    const feito = await categoriaDepoisDaResposta(categoria, numero, r, ctx, deps);
    if (feito) return feito;
  }
  return await falarDaResposta(r, { ...ctx, respondida: alvo.id, interp: interpretacao, passo: alvo.passo }, deps);
}

/**
 * B: a resposta ("empresa") já foi aplicada; agora a categoria dita junto, pelo comando corrigir do
 * CMP. Com a pergunta seguinte: a linha da categoria e ela, com a chave dela. null = a categoria não
 * pegou (inválida, outro resultado): quem chama fala da resposta como sempre (a pergunta que ela
 * abriu segue aberta). A falha da RPC não perde a resposta: também cai no texto de sempre.
 */
async function categoriaDepoisDaResposta(
  categoria: string,
  numero: number,
  // deno-lint-ignore no-explicit-any
  respondida: any,
  ctx: Contexto,
  deps: DependenciasDoFluxo,
): Promise<Saida | null> {
  // deno-lint-ignore no-explicit-any
  let c: any;
  try {
    c = await rpc(deps, "comprovante_comando", {
      p: { phone: ctx.phone, message_id: ctx.messageId, comando: "corrigir", campo: "categoria", categoria, cmp: numero },
    });
  } catch (e) {
    deps.log("categoria_da_dica_falhou", { codigo: codigoDoErro(e) });
    return null;
  }
  deps.log("comando", { comando: "corrigir", resultado: String(c?.resultado ?? "") });
  if (c?.resultado !== "pergunta") return null;
  const pergunta = (c.pergunta ?? null) as PerguntaDoBanco | null;
  const linha = textoDaCategoriaAnotada(String(c?.corrigido?.valor ?? categoria), pergunta?.passo ?? null);
  if (pergunta) {
    await enviarMensagem(ctx.phone, comAPergunta(linha, pergunta), pergunta.dedupe_key, pergunta, deps);
  } else {
    const codigo = String(c?.codigo ?? respondida?.cmp?.codigo ?? "comprovante");
    await enviarMensagem(ctx.phone, [linha, textoOcupado(codigo, respondida?.ocupado_por?.titulo)].join("\n"), ctx.chave, null, deps);
  }
  return trata(String(respondida?.resultado ?? "proximo"));
}

/**
 * F3: comprovante_banco_responder (R4) na pergunta do extrato, com o autor = o dono (o banco confere
 * contra o dono do CMP e is_admin). Se a RPC falhou, nada mudou: o aviso "mande de novo" sai com a
 * MESMA chave do aviso do webhook (cmp:f:<mensagem>), como na F2.
 */
async function responderAoExtrato(
  alvo: { id: string; passo: string | null; opcoes: Opcao[] },
  i: Interpretacao,
  ctx: Contexto,
  deps: DependenciasDoFluxo,
): Promise<Saida> {
  let r: RespostaDoBanco;
  try {
    r = await rpc<RespostaDoBanco>(deps, "comprovante_banco_responder", {
      p: { pergunta_id: alvo.id, message_id: ctx.messageId, interpretacao: i, autor: ctx.donoId ?? null },
    });
  } catch (e) {
    await enviarAoDono(ctx.phone, TEXTO_FALHA, `cmp:f:${ctx.messageId}`, deps);
    throw e;
  }
  return await falarDaRespostaDoExtrato(r, { ...ctx, respondida: alvo.id, interp: i, opcoes: alvo.opcoes, passo: alvo.passo }, deps);
}

/** O resultado da R4 vira o texto ao dono (spec-f3.md, 4.3). "ignorada": nada (tratada, sem mensagem). */
async function falarDaRespostaDoExtrato(
  r: RespostaDoBanco | null,
  ctx: Contexto & { respondida: string; interp: Interpretacao; opcoes: Opcao[]; passo?: string | null },
  deps: DependenciasDoFluxo,
): Promise<Saida> {
  const cmp = (r?.cmp ?? null) as CmpResumo | null;
  const ativa = ctx.estado.ativa?.origem === "comprovante" ? ctx.estado.ativa : null;
  const codigo = cmp?.codigo ?? (ativa?.id === ctx.respondida ? ativa.referencia_codigo : null) ?? "comprovante";
  const numero = cmp ? numeroDoCmp(cmp) : null;
  const resultado = String(r?.resultado ?? "");
  const quemPagou = ctx.passo === "banco_quem";
  const azul = ehPerguntaAzul({ opcoes: ctx.opcoes, banco: null });
  const linhasNaLista = ctx.opcoes.filter((o) => o.n > 0).length;
  const ate = r?.ate ?? cmp?.banco?.ate ?? null;
  // o motivo da rota pode trazer dado: no log, só o que é código
  const motivoDoLog = typeof r?.motivo === "string" && /^[a-z_]{1,40}$/.test(r.motivo) ? r.motivo : null;
  deps.log("resposta_extrato", { id: cmp?.id ?? null, resultado, motivo: motivoDoLog });

  switch (resultado) {
    case "ignorada":
      // CMP cancelado ou já ligado: a pergunta velha não faz nada (e não vai ao assistente)
      return trata("ignorada");
    case "ligado": {
      if (!cmp) return trata("ligado");
      // ajustes do dono: o sim já aprova a linha no Extrato — antes do texto, que diz o que aconteceu
      const aprovacao = await aprovarSeHouver(cmp.id, ctx.donoId, r?.aprovar, deps);
      // o "motivo" do ligado é o aviso da ligação (ex.: a linha já foi lançada em outro registro)
      const aviso = typeof r?.motivo === "string" ? textosDosAvisos([r.motivo], cmp, r?.ligacao ? [r.ligacao] : null, true) : [];
      const texto = [textoDoLigado(cmp, r?.ligacao ?? null, aprovacao), ...aviso].join("\n");
      // a próxima: a que a R4 trouxe, senão a da fila da F2 primeiro e depois outra do extrato
      const prox = r?.proxima
        ? { f2: null, extrato: r.proxima }
        : await proximaDepoisDoExtrato(ctx.phone, deps);
      if (prox?.f2) {
        await enviarMensagem(ctx.phone, `${texto}\n\nPróximo: ${textoDaPergunta(prox.f2)}`, prox.f2.dedupe_key, prox.f2, deps);
      } else if (prox?.extrato) {
        await enviarMensagem(ctx.phone, `${texto}\n\nPróximo: ${textoDaPerguntaDoExtrato(prox.extrato)}`, prox.extrato.dedupe_key, prox.extrato, deps);
      } else {
        await enviarMensagem(ctx.phone, texto, ctx.chave, null, deps);
      }
      // o par do histórico: o assistente fica sabendo da ligação feita pelo dono
      emSegundoPlano(deps, "historico_extrato", gravarNoHistorico(ctx.phone, `${cmp.codigo} ligado ao extrato`, `${cmp.codigo} (id ${cmp.id})`, texto, deps));
      return trata("ligado");
    }
    case "recusado":
      // "nenhuma" (azul: 0/não) ou "nao_e_essa" (verde); sem o motivo, pelo menu da pergunta
      await enviarMensagem(ctx.phone, textoDoRecusado(codigo, ate, r?.motivo ? r.motivo === "nenhuma" : azul), ctx.chave, null, deps);
      return trata("recusado");
    case "mudou": {
      const nova = r?.proxima ?? null;
      await enviarMensagem(ctx.phone, textoDoMudou(codigo, ate, nova), nova ? nova.dedupe_key : ctx.chave, nova, deps);
      return trata("mudou");
    }
    case "invalida": {
      const anterior = r?.motivo === "resposta_anterior_a_pergunta";
      const proxima = r?.proxima ?? null;
      const azulDaProxima = proxima ? ehPerguntaAzul(proxima) : azul;
      const opcoesDaProxima = proxima ? proxima.opcoes.filter((o) => o.n > 0).length : linhasNaLista;
      const aviso = anterior
        ? "Essa resposta chegou antes desta pergunta; responda de novo a ela:"
        : r?.motivo === "pergunta_fechada"
        ? "Essa pergunta já tinha fechado; esta é a de agora:"
        : (proxima ? proxima.passo === "banco_quem" : quemPagou)
        ? textoInvalidaDoQuemPagou(codigo, opcoesDaProxima)
        : textoInvalidaDoExtrato(codigo, azulDaProxima, opcoesDaProxima);
      if (proxima) {
        const nova = proxima.pergunta_id !== ctx.respondida;
        await enviarMensagem(ctx.phone, `${aviso}\n${textoDaPerguntaDoExtrato(proxima)}`, nova ? proxima.dedupe_key : ctx.chave,
          nova ? proxima : null, deps, nova ? null : proxima.pergunta_id);
      } else if (anterior && cmp) {
        // sem a pergunta de volta, reapresenta com o que o dono viu nela (as opções)
        const deNovo: PerguntaDoExtrato = {
          pergunta_id: ctx.respondida, dedupe_key: ctx.chave, cmp, passo: quemPagou ? "banco_quem" : "banco", opcoes: ctx.opcoes, banco: null,
        };
        await enviarMensagem(ctx.phone, `${aviso}\n${textoDaPerguntaDoExtrato(deNovo)}`, ctx.chave, null, deps, ctx.respondida);
      } else {
        await enviarMensagem(ctx.phone, aviso, ctx.chave, null, deps);
      }
      return trata("invalida");
    }
    case "ok_nao_aprova":
      // "ok", número ou frase curta no verde: nunca liga; pede o sim de novo
      await enviarMensagem(ctx.phone, quemPagou ? textoInvalidaDoQuemPagou(codigo, linhasNaLista) : textoInvalidaDoExtrato(codigo, false), ctx.chave, null, deps);
      return trata("ok_nao_aprova");
    // ── regra E (ajustes do dono): o "quem pagou?" depois de 5 dias sem aparecer em conta da empresa ──
    case "esperando":
      // a empresa pagou: continua esperando o extrato (até os 30/45 dias)
      await enviarMensagem(ctx.phone, textoDoQuemEsperando(codigo, ate), ctx.chave, null, deps);
      return trata("esperando");
    case "regravado": {
      if (!cmp) return trata("regravado");
      // desfez e gravou de novo, na mesma transação (o reembolso, o crédito nas Diárias ou só o arquivo)
      const gravacao = (r?.gravacao ?? null) as Gravacao | null;
      const aprovacao = await aprovarSeHouver(cmp.id, ctx.donoId, gravacao?.aprovar, deps);
      const texto = textoDoRegravado(cmp, gravacao, aprovacao);
      await enviarMensagem(ctx.phone, texto, ctx.chave, null, deps);
      // o arquivo muda de nome/pasta (PESSOAL, BOLSO, TECNICO) e o assistente fica sabendo
      depoisDoArquivo(ctx.phone, cmp.id, gravacao?.mes ?? null, `${cmp.codigo} corrigido (quem pagou)`, `${cmp.codigo} (id ${cmp.id})`, texto, deps);
      return trata("regravado");
    }
    case "nao_trocado": {
      const codigoErro = typeof (r as { codigo_erro?: unknown })?.codigo_erro === "string" &&
          /^[0-9A-Z]{5}$/.test(String((r as { codigo_erro?: unknown }).codigo_erro))
        ? String((r as { codigo_erro?: unknown }).codigo_erro)
        : null;
      const texto = textoDoNaoTrocado(codigo, r, numero, codigoErro);
      if (texto.includes("deu um erro no sistema")) {
        await logEdgeError(deps.admin, {
          context: "comprovantes-whatsapp", action: "trocar_pagador", level: "error",
          message: `nao_trocado:${codigoErro ?? "sem_codigo"}`, details: { cmp_id: cmp?.id ?? null },
        });
      }
      await enviarMensagem(ctx.phone, texto, ctx.chave, null, deps);
      return trata("nao_trocado");
    }
    case "nao_ligado": {
      const codigoErro = typeof (r as { codigo_erro?: unknown })?.codigo_erro === "string" &&
          /^[0-9A-Z]{5}$/.test(String((r as { codigo_erro?: unknown }).codigo_erro))
        ? String((r as { codigo_erro?: unknown }).codigo_erro)
        : null;
      if (motivoDoNaoLigado(r?.motivo, numero, codigoErro).startsWith("deu um erro no sistema")) {
        await logEdgeError(deps.admin, {
          context: "comprovantes-whatsapp", action: "ligar_linha", level: "error",
          message: `nao_ligado:${codigoErro ?? "sem_codigo"}`, details: { cmp_id: cmp?.id ?? null },
        });
      }
      await enviarMensagem(ctx.phone, textoNaoLigado(codigo, r?.motivo, numero, codigoErro), ctx.chave, null, deps);
      return trata("nao_ligado");
    }
    default:
      deps.log("resposta_desconhecida", { resultado });
      return trata("desconhecido");
  }
}

/** O passo e as opções da pergunta citada que já fechou: o banco aplica a resposta ao que o dono VIU nela. */
async function perguntaPeloId(id: string, deps: DependenciasDoFluxo): Promise<AlvoDaResposta | null> {
  const { data, error } = await deps.admin.from("whatsapp_perguntas").select("id, passo, opcoes, origem, referencia_codigo").eq("id", id).maybeSingle();
  if (error) throw new FalhaDoFluxo(`ler_pergunta:${error.code ?? "erro"}`);
  if (!data || data.origem !== "comprovante") return null;
  return {
    id: String(data.id), passo: data.passo ?? null, opcoes: Array.isArray(data.opcoes) ? data.opcoes as Opcao[] : [],
    codigo: typeof data.referencia_codigo === "string" ? data.referencia_codigo : null,
  };
}

/** A última pergunta de um CMP (aberta ou não): a citação da FOTO responde a ela. */
async function ultimaPerguntaDoCmp(cmp: string, deps: DependenciasDoFluxo): Promise<AlvoDaResposta | null> {
  const { data, error } = await deps.admin.from("whatsapp_perguntas").select("id, passo, opcoes, referencia_codigo")
    .eq("referencia_id", cmp).eq("origem", "comprovante").order("aberta_em", { ascending: false }).limit(1);
  if (error) throw new FalhaDoFluxo(`ler_pergunta:${error.code ?? "erro"}`);
  const d = Array.isArray(data) ? data[0] : null;
  return d
    ? {
      id: String(d.id), passo: d.passo ?? null, opcoes: Array.isArray(d.opcoes) ? d.opcoes as Opcao[] : [],
      codigo: typeof d.referencia_codigo === "string" ? d.referencia_codigo : null,
    }
    : null;
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
      // ajustes do dono: gravou e ligou à linha (verde) → o mesmo sim já aprova a linha no Extrato
      const aprovacao = await aprovarSeHouver(cmp?.id, ctx.donoId, gravacao?.aprovar, deps);
      // F3: sem próxima da fila e com linhas parecidas no extrato (azul), a pergunta do extrato sai
      // na mesma mensagem ("No extrato: …"), com a chave dela
      const banco = !proxima && gravacao?.banco?.perguntar === true && cmp?.id
        ? await abrirPerguntaDoExtrato(ctx.phone, "depois_de_gravar", cmp.id, deps)
        : null;
      const texto = textoDaGravacao({ cmp: cmp as CmpResumo, gravacao, proxima, banco, aprovacao });
      const { chave, abre } = banco ? { chave: banco.dedupe_key, abre: banco as PerguntaQueAbre } : chaveDaPergunta(proxima, ctx.respondida, ctx.chave);
      await enviarMensagem(ctx.phone, texto, chave, abre, deps);
      if (cmp?.id) {
        const soAGravacao = textoDaGravacao({ cmp, gravacao, proxima: null, aprovacao }).split("\n\n")[0];
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
  if (ativa?.interrompida_em && !ctx.estado.pendencia && ehPassoDoExtrato(ativa.passo)) {
    // F3: a pergunta do extrato reapresentada (a R3 recalcula as linhas)
    const p = await abrirPerguntaDoExtrato(ctx.phone, "reabrir", ativa.referencia_id, deps);
    if (p) {
      await enviarMensagem(ctx.phone, `${textoRetomadaInterrompida(p.cmp?.codigo ?? ativa.referencia_codigo ?? "comprovante")}\n\n${textoDaPerguntaDoExtrato(p)}`,
        p.dedupe_key, p, deps);
      return;
    }
  } else if (ativa?.interrompida_em && !ctx.estado.pendencia) {
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
  if (ultima && !ultima.codigo) ultima.codigo = foto.codigo;
  const i = ultima ? interpretarResposta(ultima.passo, ultima.opcoes, ctx.texto, agora) : null;
  if (ultima && i && ehPassoDoExtrato(ultima.passo)) return await responderAoExtrato(ultima, i, ctx, deps);
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
  if (ehPassoDoExtrato(ativa.passo)) {
    // F3: a pergunta do extrato de novo (a R3 recalcula as linhas); a da fila da F2 não serve aqui
    const p = await abrirPerguntaDoExtrato(ctx.phone, "reabrir", ativa.referencia_id, deps);
    if (p) await enviarMensagem(ctx.phone, `${textoNaoEntendi(codigo)}\n\n${textoDaPerguntaDoExtrato(p)}`, p.dedupe_key, p, deps);
    else await enviarMensagem(ctx.phone, textoNaoEntendi(codigo), ctx.chave, null, deps);
    return trata("nao_entendi");
  }
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
  obs_longa: "a observação passa de 200 letras",
};

/**
 * O que vem depois de "corrigir" no texto do dono (para repetir no "qual dos dois?"). A (12/10/2026):
 * "obs: <texto>"/"observação: <texto>", sem o corrigir, vira "obs <texto>".
 */
function comandoDoCorrigir(texto: string): string {
  const t = String(texto ?? "").trim().replace(/^[\s🎤"'“”‘’«»]+/u, "");
  const m = /^corrig\w*\s+(.+)$/i.exec(t);
  const obs = m ? null : /^(?:obs|observa[cç][aã]o)\s*:\s*(.+)$/is.exec(t);
  const resto = m?.[1] ?? (obs ? `obs ${obs[1].replace(/\s+/g, " ").trim()}` : "");
  return resto.replace(/[.!]+$/u, "").slice(0, 60);
}

/**
 * comprovante_comando (cmp N, pular, sair, lote antigo, cancelar, feito, corrigir) e o texto de cada resultado.
 * `comoDica` (B, 11/10/2026): o corrigir categoria veio da palavra no "para quê" — a linha é "Categoria
 * anotada…" (com a repergunta do destino) e a categoria recusada vira "Não entendi" + a pergunta de novo.
 */
async function executarComando(cmd: Comando, ctx: Contexto, deps: DependenciasDoFluxo, opcoes: { comoDica?: boolean } = {}): Promise<Saida> {
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
    if (ativa?.passo === "confirmar") {
      return await responderA({ id: ativa.id, passo: ativa.passo, opcoes: ativa.opcoes, codigo: ativa.referencia_codigo }, { tipo: "nao" }, ctx, deps);
    }
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
    case "cartao": {
      const c = r.cmp as CmpResumo;
      await falar(textoDoCartao(c, (r.efeitos ?? []) as Efeito[]));
      // F3: CMP gravado com a pergunta do extrato pendente (ou o "quem pagou?" da regra E) → a
      // pergunta, numa segunda mensagem
      if (c?.id && (c.banco?.estado === "perguntar" || c.banco?.estado === "pergunta_aberta" || ehEstadoDoQuemPagou(c.banco?.estado))) {
        await perguntarBanco(ctx.phone, "cmp", deps, c.id);
      }
      break;
    }
    case "nao_existe":
      await falar(textoNaoExiste((cmd as { cmp?: number }).cmp ?? numero ?? 0));
      break;
    case "pergunta": {
      const antes = opcoes.comoDica
        ? textoDaCategoriaAnotada(String(r?.corrigido?.valor ?? ""), pergunta?.passo ?? null)
        : textoCorrigido(codigo, r?.corrigido);
      if (pergunta) await falar(comAPergunta(antes, pergunta), pergunta);
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
      // a dica de categoria que o banco não achou (categoria desativada): a mesma pergunta de novo
      if (opcoes.comoDica) return await naoEntendi(ctx, deps);
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
// completar: o assistente passa ao fluxo o que o dono disse em conversa (A, 11/10/2026 —
// spec-assistente-opera-cmp.md, 2.2). Porta chamadaInterna (o ai-agent e o erp-mcp, pela tool
// completar_comprovante). Uma RPC só (comprovante_completar, 12/10/2026 —
// spec-observacao-atomica-prefixo.md, 3), tudo ou nada; por dentro, as mesmas do menu
// (comprovante_comando campo a campo, comprovante_responder nos passos sem comando). Nada grava no
// financeiro: só o sim do dono ao resumo grava (o banco recusa o sim sem mensagem do dono).
// ---------------------------------------------------------------------------------------------

const DESTINOS_DO_COMPLETAR = new Set(["os", "estoque", "insumo", "empresa", "pessoal"]);
const TIPOS_NA_OS_DO_COMPLETAR = new Set(["peca", "despesa"]);
const FORMAS_DO_COMPLETAR = new Set(["pix", "debito", "credito", "dinheiro", "boleto", "transferencia"]);
const QUEM_PAGOU_DO_COMPLETAR = new Set(["empresa", "socio", "tecnico", "cliente"]);

/** O que a tool manda, já normalizado por ela (o edge reconfere tudo). */
export type CorpoDoCompletar = {
  phone: string;
  /** O app_users.id de quem pede: tem de ser o dono. */
  autor: string;
  /** O número do CMP (1 = CMP-00001). */
  cmp: number;
  /** "235.97". */
  valor?: string | null;
  /** AAAA-MM-DD. */
  data?: string | null;
  destino?: string | null;
  /** O número da OS (112 = OS-00112 ou ORÇ-00112). */
  os?: number | null;
  tipo_na_os?: string | null;
  /** A palavra do dono ou o nome da categoria. */
  categoria?: string | null;
  forma?: string | null;
  quem_pagou?: string | null;
  tecnico?: string | null;
  /**
   * O que o dono disse para ficar anotado no CMP (o porquê do valor diferente, …). Fica guardada no
   * comprovante (A, 12/10/2026): vai ao resumo, ao índice e à descrição do lançamento; nunca ao log.
   */
  observacao?: string | null;
};

export type ResultadoDoCompletar = {
  ok: boolean;
  motivo?: string;
  /** observacao_obrigatoria: o valor lido no comprovante ("204.87"). */
  valor_lido?: string | null;
  codigo?: string;
  /** "categoria", "os", "para", "valor", "data", "forma", "obs", "quem_pagou", "tecnico", "tipo_na_os". */
  aplicados: string[];
  /** O que veio e não foi usado (o passo não chegou, ou parou antes). */
  ignorados: string[];
  /** O que ficou anotado, como o dono lê. */
  anotado?: string[];
  recusado?: { campo: string; motivo: string; texto: string } | null;
  /** O passo da pergunta que foi ao dono ("confirmar" = o resumo). */
  passo?: string | null;
  enviada: boolean;
  /** O telefone está ocupado (pendência do assistente, outra pergunta): a pergunta vai depois. */
  ocupado?: boolean;
  ocupado_por?: string | null;
  cmp?: {
    valor: string | null; data: string | null; destino: string | null; os: string | null; categoria: string | null;
    forma: string | null; quem_pagou: string | null; tipo_na_os: string | null; observacao: string | null;
  } | null;
};

/** Texto opcional: ausente/vazio = null; outro tipo ou longo demais = undefined (entrada inválida). */
function textoDoCorpo(v: unknown, max: number): string | null | undefined {
  if (v == null || v === "") return null;
  if (typeof v !== "string") return undefined;
  const t = v.replace(/[\n\r\t]+/g, " ").replace(/\s+/g, " ").trim();
  if (t.length > max) return undefined;
  return t || null;
}

/** Do enum: ausente = null; fora dele = undefined. */
function enumDoCorpo(v: unknown, valores: ReadonlySet<string>): string | null | undefined {
  if (v == null || v === "") return null;
  return typeof v === "string" && valores.has(v) ? v : undefined;
}

function dataQueExiste(s: string): boolean {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (!m) return false;
  const d = new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]), 12));
  return d.toISOString().slice(0, 10) === s;
}

/** A entrada do completar conferida (tipos, formatos, enums, limites); null = entrada inválida. */
// deno-lint-ignore no-explicit-any
function corpoDoCompletar(p: any): CorpoDoCompletar | null {
  if (!p || typeof p !== "object") return null;
  if (typeof p.phone !== "string" || !/^\d{10,15}$/.test(p.phone)) return null;
  if (typeof p.autor !== "string" || !UUID.test(p.autor)) return null;
  if (typeof p.cmp !== "number" && typeof p.cmp !== "string") return null;
  const cmp = Number(p.cmp);
  if (!Number.isInteger(cmp) || cmp < 1 || cmp > 999_999) return null;

  let valor: string | null = null;
  if (p.valor != null && p.valor !== "") {
    if (typeof p.valor !== "string" || !/^\d{1,10}\.\d{2}$/.test(p.valor) || !(Number(p.valor) > 0) || Number(p.valor) > 999_999.99) return null;
    valor = p.valor;
  }
  let data: string | null = null;
  if (p.data != null && p.data !== "") {
    if (typeof p.data !== "string" || !dataQueExiste(p.data)) return null;
    data = p.data;
  }
  let os: number | null = null;
  if (p.os != null && p.os !== "") {
    os = Number(p.os);
    if ((typeof p.os !== "number" && typeof p.os !== "string") || !Number.isInteger(os) || os < 1 || os > 999_999) return null;
  }
  const destino = enumDoCorpo(p.destino, DESTINOS_DO_COMPLETAR);
  const tipoNaOs = enumDoCorpo(p.tipo_na_os, TIPOS_NA_OS_DO_COMPLETAR);
  const forma = enumDoCorpo(p.forma, FORMAS_DO_COMPLETAR);
  const quemPagou = enumDoCorpo(p.quem_pagou, QUEM_PAGOU_DO_COMPLETAR);
  const categoria = textoDoCorpo(p.categoria, 80);
  const tecnico = textoDoCorpo(p.tecnico, 60);
  const observacao = textoDoCorpo(p.observacao, 200);
  if ([destino, tipoNaOs, forma, quemPagou, categoria, tecnico, observacao].some((x) => x === undefined)) return null;
  // a OS dita é o destino "os": outro destino junto não combina
  if (os !== null && destino && destino !== "os") return null;
  return {
    phone: p.phone, autor: p.autor, cmp, valor, data, os, destino: os !== null ? "os" : destino ?? null,
    tipo_na_os: tipoNaOs ?? null, categoria: categoria ?? null, forma: forma ?? null, quem_pagou: quemPagou ?? null,
    tecnico: tecnico ?? null, observacao: observacao ?? null,
  };
}

/** numeric do banco (número ou texto) → número; nulo/ilegível → null. */
function numeroDoBanco(v: unknown): number | null {
  if (v == null || v === "") return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

/** O rótulo do campo na linha "Não usei" ("OS-00999", "valor R$ 9,00", "categoria \"x\""). */
function rotuloDoNaoUsado(campo: string, corpo: CorpoDoCompletar): string {
  switch (campo) {
    case "os": return corpo.os ? `OS-${String(corpo.os).padStart(5, "0")}` : "a OS";
    case "valor": return `valor R$ ${String(corpo.valor ?? "").replace(".", ",")}`;
    case "data": return `data ${corpo.data ? `${corpo.data.slice(8, 10)}/${corpo.data.slice(5, 7)}` : ""}`.trim();
    case "forma": return `forma ${corpo.forma ?? ""}`.trim();
    case "para": return `para ${corpo.destino ?? ""}`.trim();
    case "categoria": return `categoria "${String(corpo.categoria ?? "").replace(/"/g, "").slice(0, 40)}"`;
    case "quem_pagou": return "quem pagou";
    case "tecnico": return `técnico ${String(corpo.tecnico ?? "").replace(/"/g, "").slice(0, 40)}`.trim();
    case "tipo_na_os": return "peça ou despesa";
    case "obs": return "a observação";
    default: return campo;
  }
}

/** O porquê da recusa numa frase curta (sem o exemplo entre parênteses nem a instrução do menu). */
function porqueDoNaoUsado(motivo: string, i: Interpretacao | null, passo: string | null): string {
  const doCorrigir = MOTIVO_DO_CORRIGIR[motivo];
  if (doCorrigir) return doCorrigir.replace(/\s*\(.*\)\s*$/, "");
  if (motivo === "opcao_fora" || motivo === "resposta_nao_serve") return "não vale para este comprovante";
  const frase = textoInvalida(i, passo, motivo).trim().split(/(?<=[.!?])\s/)[0].replace(/[.!?]+$/, "").trim();
  return frase ? frase.charAt(0).toLowerCase() + frase.slice(1) : "não serve";
}

/**
 * A resposta que o banco deu ao passo (a tabela das respostas da comprovante_completar): o porquê da
 * recusa de um passo sai da mesma interpretação. Passo nulo (recusa de uma correção) = null.
 */
function interpretacaoDoPasso(passo: string | null, corpo: CorpoDoCompletar): Interpretacao | null {
  switch (passo) {
    case "quem_pagou": return corpo.quem_pagou ? { tipo: "palavra", valor: corpo.quem_pagou as Palavra } : null;
    case "qual_tecnico": return corpo.tecnico ? { tipo: "nome", texto: corpo.tecnico } : null;
    case "tipo_na_os": return corpo.tipo_na_os ? { tipo: "palavra", valor: corpo.tipo_na_os as Palavra } : null;
    case "como_pagou": return corpo.forma ? { tipo: "palavra", valor: corpo.forma as Palavra } : null;
    case "qual_os": return corpo.os ? { tipo: "os", numero: corpo.os } : null;
    default: return null;
  }
}

/** Uma lista de textos do banco (aplicados, ja_estava, ignorados); o resto é descartado. */
function listaDoBanco(v: unknown): string[] {
  return Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : [];
}

/** Os itens anotados que o banco devolve ({campo, valor, lido?, nome?}). */
function itensDoBanco(v: unknown): ItemAnotado[] {
  if (!Array.isArray(v)) return [];
  return v
    .filter((i) => i && typeof i === "object" && typeof (i as { campo?: unknown }).campo === "string")
    .map((i) => {
      const x = i as Record<string, unknown>;
      return {
        campo: String(x.campo),
        valor: x.valor == null ? null : String(x.valor),
        ...(x.lido != null ? { lido: String(x.lido) } : {}),
        ...(x.nome != null ? { nome: String(x.nome) } : {}),
      };
    });
}

/** O CMP como ficou (o que vai ao assistente; o resumo do banco). */
function cmpDoCompletar(c: CmpResumo | null | undefined): ResultadoDoCompletar["cmp"] {
  if (!c) return null;
  return {
    valor: c.valor ?? null, data: c.data ?? null, destino: c.destino ?? null, os: c.os?.numero ?? null, categoria: c.categoria ?? null,
    forma: c.forma ?? null, quem_pagou: c.quem_pagou ?? null, tipo_na_os: c.tipo_na_os ?? null, observacao: c.observacao ?? null,
  };
}

/**
 * O assistente completa o CMP com o que o dono disse em conversa. A edge confere a entrada, o dono, a
 * conversa e o modo de teste (o banco não sabe dele) e chama UMA RPC, comprovante_completar: as
 * recusas antes de escrever (CMP, valor diferente do lido sem observação, data futura), as correções
 * na ordem fixa pelo comprovante_comando e as respostas aos passos sem comando pelo
 * comprovante_responder (nunca o confirmar nem o mesma_compra) — tudo numa transação, tudo ou nada.
 * Uma recusa no meio não deixa nada anotado e nada é enviado (a tool pede para corrigir ou tirar o
 * campo). Com `ok`, uma mensagem só ao dono: a linha "anotei o que você disse na conversa" e a última
 * pergunta (ou o resumo), com a chave dela.
 */
export async function completar(p: unknown, deps: DependenciasDoFluxo): Promise<{ status: 200 | 422; corpo: ResultadoDoCompletar }> {
  const corpo = corpoDoCompletar(p);
  if (!corpo) {
    deps.log("completar_recusado", { motivo: "entrada_invalida" });
    return { status: 422, corpo: { ok: false, motivo: "entrada_invalida", aplicados: [], ignorados: [], enviada: false } };
  }
  const recusar = (motivo: string, extra: Partial<ResultadoDoCompletar> = {}) => {
    deps.log("completar_recusado", { motivo });
    return { status: 200 as const, corpo: { ok: false, motivo, aplicados: [], ignorados: [], enviada: false, ...extra } };
  };

  const dono = await donoDoWhatsApp(deps.admin);
  if (!dono || dono.phone !== corpo.phone || dono.id !== corpo.autor) return recusar("nao_e_o_dono");
  if (!conversaDosComprovantesLigada(await lerConfiguracoes(deps, ["comprovante_fluxo", "comprovante_conversa"]))) return recusar("desligada");
  if (await modoDeTesteLigado(deps)) return recusar("modo_de_teste");

  // a categoria vai traduzida pela palavra do dono ("almoço" → "Alimentação de campo"), ou crua
  const categoria = corpo.categoria ? (categoriaDaPalavra(corpo.categoria) ?? corpo.categoria) : null;
  // deno-lint-ignore no-explicit-any
  const r = await rpc<any>(deps, "comprovante_completar", { p: { ...corpo, categoria } });
  const resultado = String(r?.resultado ?? "");
  const temCodigo = typeof r?.codigo === "string" && r.codigo !== "";
  const codigo = temCodigo ? String(r.codigo) : codigoDoNumero(corpo.cmp);
  const lido = numeroDoBanco(r?.valor_lido);
  const valorLido = lido !== null ? lido.toFixed(2) : null;
  const ignorados = listaDoBanco(r?.ignorados);
  if (r?.desconhecido != null) deps.log("completar_desconhecido", { resultado: String(r.desconhecido) });

  // ── recusa dentro do bloco: o banco desfez tudo (correções e perguntas); nenhuma mensagem ──
  if (resultado === "recusado") {
    const campo = String(r?.recusado?.campo ?? "");
    const motivo = String(r?.recusado?.motivo ?? "");
    const passo = typeof r?.recusado?.passo === "string" ? r.recusado.passo : null;
    const recusado = { campo, motivo, texto: `${rotuloDoNaoUsado(campo, corpo)} (${porqueDoNaoUsado(motivo, interpretacaoDoPasso(passo, corpo), passo)})` };
    deps.log("completar", { id: String(r?.id ?? ""), aplicados: 0, ignorados: ignorados.length, passo: null, enviada: false, recusado: campo });
    return {
      status: 200,
      corpo: {
        ok: true, codigo, aplicados: [], ignorados, anotado: [], recusado, passo: null, enviada: false, ocupado: false, ocupado_por: null,
        valor_lido: valorLido, cmp: null,
      },
    };
  }
  // ── as recusas antes de escrever (nao_existe, ja_gravado, observacao_obrigatoria…) e a corrida no
  //    meio (o bloco desfeito): o motivo do banco ──
  if (resultado !== "ok") {
    return recusar(resultado || "desconhecido", { ...(temCodigo ? { codigo } : {}), ...(valorLido ? { valor_lido: valorLido } : {}) });
  }

  // ── uma mensagem só: a linha do que foi anotado e a última pergunta (ou o resumo) ──
  const itens = itensDoBanco(r?.itens);
  const aplicados = listaDoBanco(r?.aplicados);
  const final = (r?.pergunta ?? null) as PerguntaDoBanco | null;
  // a observação da frase: a anotada agora (o banco já a manda sem CPF) ou a que já estava igual
  const obsAnotada = itens.find((i) => i.campo === "obs")?.valor ?? null;
  const obsIgual = listaDoBanco(r?.ja_estava).includes("obs") ? (final?.cmp?.observacao ?? semCpf(corpo.observacao)) : null;
  let enviada = false;
  if (final) {
    const linha = textoDoAnotadoNaConversa(codigo, itens, obsAnotada ?? obsIgual, null, ignorados.length > 0);
    enviada = await enviarMensagem(corpo.phone, comAPergunta(linha, final), final.dedupe_key, final, deps);
  }
  deps.log("completar", {
    id: String(r?.id ?? ""), aplicados: aplicados.length, ignorados: ignorados.length, passo: final?.passo ?? null, enviada, recusado: null,
  });
  return {
    status: 200,
    corpo: {
      ok: true, codigo, aplicados, ignorados, anotado: textosDosItensAnotados(itens), recusado: null, passo: final?.passo ?? null, enviada,
      ocupado: !final && r?.ocupado === true,
      ocupado_por: !final && typeof r?.ocupado_por === "string" ? r.ocupado_por : null,
      valor_lido: valorLido, cmp: cmpDoCompletar(final?.cmp),
    },
  };
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
 * Regrava o "_INDICE AAAA-MM.csv" do mês com os CMPs que o banco manda (os das pastas dos barcos e os
 * cancelados; desde a F3, sem os PESSOAIS, que têm o índice da pasta deles): substituir pelo rev
 * guardado; conflito (o dono mexeu) → novo arquivo, e o registro passa a apontar para ele.
 */
export async function atualizarIndice(mes: string, deps: DependenciasDoFluxo): Promise<boolean> {
  return await gravarIndice(mes, INDICE_DO_MES, deps);
}

/**
 * F3: regrava o "_INDICE PESSOAL AAAA-MM.csv" da pasta COMPROVANTES/PESSOAL/AAAA-MM (só os PESSOAIS:
 * o índice da contadora não os lista). As mesmas regras do índice do mês (rev, conflito, backoff).
 */
export async function atualizarIndicePessoal(mes: string, deps: DependenciasDoFluxo): Promise<boolean> {
  return await gravarIndice(mes, INDICE_PESSOAL, deps);
}

/** As RPCs, o registro e o caminho de cada índice (o do mês: RPCs 19-21 da F2; o PESSOAL: R7-R9 da F3). */
type QualIndice = {
  linhas: string;
  gravado: string;
  falhou: string;
  tabela: string;
  caminho: (mes: string) => string;
  log: string;
};

const INDICE_DO_MES: QualIndice = {
  linhas: "comprovantes_indice_do_mes", gravado: "comprovante_indice_gravado", falhou: "comprovante_indice_falhou",
  tabela: "comprovantes_indice_mensal", caminho: caminhoDoIndice, log: "indice",
};

const INDICE_PESSOAL: QualIndice = {
  linhas: "comprovantes_indice_pessoal_do_mes", gravado: "comprovante_indice_pessoal_gravado",
  falhou: "comprovante_indice_pessoal_falhou", tabela: "comprovantes_indice_pessoal", caminho: caminhoDoIndicePessoal,
  log: "indice_pessoal",
};

async function gravarIndice(mes: string, qual: QualIndice, deps: DependenciasDoFluxo): Promise<boolean> {
  const m = /^(\d{4}-\d{2})/.exec(String(mes ?? ""))?.[1];
  if (!m) return false;
  const pMes = `${m}-01`;
  const falhar = async (codigo: string) => {
    const f = await rpc(deps, qual.falhou, { p_mes: pMes, p_erro: codigo.slice(0, 300) });
    deps.log(`${qual.log}_falhou`, { mes: m, codigo, desistiu: Boolean(f?.desistiu) });
    return false;
  };
  // deno-lint-ignore no-explicit-any
  const r = await rpc<any>(deps, qual.linhas, { p_mes: pMes });
  const linhas = (Array.isArray(r) ? r : Array.isArray(r?.linhas) ? r.linhas : []) as LinhaDoIndice[];

  let registro: { caminho: string | null; rev: string | null };
  if (r && !Array.isArray(r) && ("rev" in r || "caminho" in r)) {
    registro = { caminho: r.caminho ?? null, rev: r.rev ?? null };
  } else {
    const { data, error } = await deps.admin.from(qual.tabela).select("caminho, rev").eq("mes", pMes).maybeSingle();
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
  const caminho = comRev ? String(registro.caminho) : qual.caminho(m);
  let meta: MetaDoDropbox & { conflito: boolean };
  try {
    meta = await dbx.substituir(caminho, new TextEncoder().encode(csvDoIndice(linhas)), comRev ? registro.rev : null);
  } catch (e) {
    return await falhar(codigoDoDropbox(e));
  }
  await rpc(deps, qual.gravado, {
    p_mes: pMes, p_dropbox_id: meta.id, p_caminho: meta.path_display, p_rev: meta.rev, p_linhas: linhas.length,
  });
  deps.log(`${qual.log}_gravado`, { mes: m, linhas: linhas.length, conflito: meta.conflito });
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
