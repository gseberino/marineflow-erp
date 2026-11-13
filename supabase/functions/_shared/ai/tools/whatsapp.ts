import {
  blockTechnician,
  cargosQueContam,
  lerRetrato,
  lerSolicitante,
  NON_TECHNICIAN_ROLES,
  type Role,
  type ToolCtx,
  type ToolDef,
} from "./registry.ts";
import { chaveDeEnvio, diaLocal, hashCurto, liberarEnvio } from "../../whatsapp/idempotencia.ts";
import { RECUSA_CLIENTE_FINAL } from "../comms/compliance-guard.ts";
import { chavesForaDoAssistente, foraDoAssistente } from "../parceiro-fora-da-ia.ts";
import { guardaDeEnvio } from "../comms/send-guard.ts";
import { registrarEnvio } from "../comms/send-log.ts";
import { documentTypeFor } from "../../pdf/document-type.ts";
import { fmtCurrency, vencimentoDoOrcamento } from "../../pdf/documento.ts";
import { dataBR, diaBR, somarDiasAoDia } from "../../pdf/datas.ts";
import { diasDeValidade } from "../../dias-de-validade.ts";
import { guardarEEntregar, impressaoDigitalDoDocumento, montarDocumentoDaOrdem, montarResumoDeValores } from "../../pdf/gerar-e-guardar.ts";
import { desviadoPorTeste, modoDeTesteSemNumero, numeroDeTesteAtivo } from "../../whatsapp/marcar-enviado.ts";
import { normalizePhoneNumber } from "../../whatsapp/normalize.ts";
import { pixEsperandoNoExtrato } from "./pix-esperando.ts";
import {
  cadastrarContatoDoAgendamento,
  destinoDoAgendamento,
  horarioDoAgendamento,
  quandoPorExtenso,
  telefoneLegivel,
  telefoneParaEnvio,
  validarAgendamento,
} from "./agendamento.ts";
import { validarMensagem } from "./resposta.ts";
import { agrupadoEm, ehOsAgrupada } from "./service-orders.ts";
// Frente financeiro (07/10/2026): o lembrete enviado entra no histórico da cobrança, como na tela.
import { registrarEnvioDaCobranca } from "./cobrancas.ts";
// Retorno F5 (P11.4): a O21 e a O22 que o banco devolve passam pelo validador do retorno (o isolamento proíbe só o caminho
// contrário: _shared/retorno/ nunca importa _shared/ai/).
import { validarSaida } from "../../retorno/validador.ts";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Pedido de cotação sem cotação (07/10/2026): crie antes, como a tela. */
export const SEM_COTACAO =
  "Para mandar pedido de cotação, crie a cotação antes (create_quote_request, com os fornecedores e os itens) e mande pelo quote_request_id — é ela que leva o código COT e os itens numerados e registra quem recebeu.";

// Prévia amigável de mídia ("identificar e encaminhar" — sem custo de vision/transcrição).
function prettyPreview(body?: string | null): string | null {
  const b = (body || "").trim();
  if (!b) return null;
  if (b === "[audio]") return "🎤 áudio";
  if (b === "[image]") return "📷 imagem";
  if (b === "[video]") return "🎬 vídeo";
  if (b === "[document]") return "📎 arquivo";
  return b.slice(0, 100);
}

/**
 * POST na edge whatsapp-send — o caminho único de envio das tools (texto e documento).
 * Lê env em tempo de chamada (não no import do módulo) para não quebrar testes que nunca
 * chamam isto.
 *
 * No canal WhatsApp não há JWT de usuário (o toolCtx traz jwt=""), então usamos a
 * service-role key: o whatsapp-send tem um bypass explícito (isServiceRoleCall) para
 * chamadas de sistema. No painel, jwt é o token real do usuário.
 *
 * NÃO enviar header `apikey`: espelha o chamador que já funciona
 * (whatsapp-process-scheduled manda só Authorization: Bearer <service_role>).
 * Enviar `apikey: anon` JUNTO com um bearer service_role faz o gateway rejeitar com
 * 401 (sem corpo) por conflito de papel — foi o "HTTP 401" que o envio do agente dava.
 * O whatsapp-send roda com verify_jwt=true (não está no config.toml, vale o padrão): o
 * gateway exige um JWT válido, e o Bearer já é um — o apikey não acrescenta nada.
 *
 * 15/10/2026: todo envio daqui vai com `origem: "assistente"` — o whatsapp-send passa a gravar a
 * mensagem na conversa (whatsapp_messages) com a origem e, quando quem chama passa `sent_by`, com
 * quem mandou (registro-do-envio.ts). `sent_by` que não é id de usuário não vai (o ctx dos testes
 * tem "u1"); no painel quem manda é o usuário do JWT, e o whatsapp-send ignora o do corpo.
 */
async function postarWhatsappSend(corpo: Record<string, unknown>, jwt: string, signal?: AbortSignal): Promise<Response> {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const authToken = jwt || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const { sent_by, ...resto } = corpo;
  const quem = typeof sent_by === "string" && UUID_RE.test(sent_by) ? { sent_by } : {};
  return await fetch(`${supabaseUrl}/functions/v1/whatsapp-send`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${authToken}`,
    },
    body: JSON.stringify({ ...resto, ...quem, origem: "assistente" }),
    signal,
  });
}

/**
 * Manda um PDF (por URL que a Evolution baixa) para um número.
 *
 * `context` é obrigatório e nunca 'quote': com context='quote' + service_order_id o
 * whatsapp-send marca o orçamento como ENVIADO AO CLIENTE (whatsapp-send/index.ts), e daí
 * vêm a expiração automática, a tarefa de follow-up e o briefing tratando como enviado.
 * Quem chama daqui não passa service_order_id — o vínculo fica na auditoria do agente.
 */
export async function enviarDocumentoWhatsapp(p: {
  phone: string;
  url: string;
  filename: string;
  caption: string;
  context: string;
  jwt: string;
  dedupeKey?: string;
  limiteMs?: number;
}): Promise<{ ok: true; deduplicated?: boolean } | { ok: false; error: string; semResposta?: boolean }> {
  if (p.context === "quote") return { ok: false, error: "context 'quote' marca o orçamento como enviado ao cliente" };
  const controle = new AbortController();
  const relogio = setTimeout(() => controle.abort(), p.limiteMs ?? 25_000);
  try {
    const r = await postarWhatsappSend({
      phone: p.phone,
      kind: "document",
      document_url: p.url,
      document_filename: p.filename,
      document_caption: p.caption,
      context: p.context,
      ...(p.dedupeKey ? { dedupe_key: p.dedupeKey } : {}),
    }, p.jwt, controle.signal);
    const data = await r.json().catch(() => ({}));
    if (!r.ok) {
      const erro = (data as any).error;
      return { ok: false, error: typeof erro === "string" ? erro : erro ? JSON.stringify(erro) : `HTTP ${r.status}` };
    }
    return { ok: true, ...((data as any).deduplicated ? { deduplicated: true } : {}) };
  } catch (e) {
    // Sem resposta HTTP (tempo esgotado ou rede): desfecho desconhecido — ver enviarOrdemAoCliente.
    const abortado = e instanceof DOMException && e.name === "AbortError";
    return {
      ok: false,
      error: abortado ? "o envio pelo WhatsApp não respondeu em 25 s" : e instanceof Error ? e.message : String(e),
      semResposta: true,
    };
  } finally {
    clearTimeout(relogio);
  }
}

/**
 * Manda uma ORDEM (orçamento/OS) ao CLIENTE — texto com o link, ou o PDF com o link na legenda.
 *
 * Caminho PRÓPRIO, separado de `enviarDocumentoWhatsapp`, e é de propósito: aquele recusa
 * context='quote' para que o PDF que o dono pede PARA SI nunca marque o orçamento como
 * enviado. Aqui é o contrário — é o envio ao cliente, e ele TEM de levar context +
 * service_order_id: é o que vincula o registro do audit_log à ordem e deixa o whatsapp-send
 * marcar 'sent' quando o envio foi de fato ao cliente. Quem decide se marca é a edge
 * (_shared/whatsapp/marcar-enviado.ts): só marca se o destino for o telefone do cliente da
 * ordem, fora do modo de teste, em orçamento draft não convertido. Tirar a recusa de lá para
 * reaproveitar a função abriria o caminho de volta ao bug de 26/09/2026 (ORÇ-00072 e
 * ORÇ-00078 rejeitados sozinhos depois de envios que só foram ao número de teste).
 *
 * `context` é tipado: só 'quote' ou 'service_order'. `phone` vem do cadastro do cliente —
 * nunca de um argumento da tool.
 */
export async function enviarOrdemAoCliente(p: {
  phone: string;
  serviceOrderId: string;
  context: "quote" | "service_order";
  jwt: string;
  dedupeKey: string;
  conteudo: { kind: "text"; message: string } | { kind: "document"; url: string; filename: string; caption: string };
  /** Documento: 25 s (a Evolution baixa o arquivo dentro da chamada). Texto: sem corte, como sempre foi. */
  limiteMs?: number;
  /** Quem confirmou o envio (ctx.userId): fica na conversa como quem mandou (15/10/2026). */
  sentBy?: string;
  /**
   * Retorno F5 (P11.4, P11.9): o envio pelo cartão do retorno vai com orcamento_via "cartao", e o whatsapp-send o registra
   * com essa via (viaDoOrcamento). Ausente = a via da origem (assistente).
   */
  viaDoOrcamento?: "cartao";
}): Promise<
  | { ok: true; deduplicated?: boolean; messageId?: string | null }
  | { ok: false; error: string; semResposta?: boolean }
> {
  const limite = p.limiteMs ?? (p.conteudo.kind === "document" ? 25_000 : null);
  const controle = new AbortController();
  const relogio = limite ? setTimeout(() => controle.abort(), limite) : null;
  const conteudo = p.conteudo.kind === "text"
    ? { kind: "text", message: p.conteudo.message }
    : {
      kind: "document",
      document_url: p.conteudo.url,
      document_filename: p.conteudo.filename,
      document_caption: p.conteudo.caption,
    };
  try {
    const r = await postarWhatsappSend({
      phone: p.phone,
      ...conteudo,
      context: p.context,
      service_order_id: p.serviceOrderId,
      dedupe_key: p.dedupeKey,
      ...(p.sentBy ? { sent_by: p.sentBy } : {}),
      ...(p.viaDoOrcamento === "cartao" ? { orcamento_via: "cartao" } : {}),
    }, p.jwt, controle.signal);
    const data = await r.json().catch(() => ({}));
    if (!r.ok) {
      const erro = (data as any).error;
      return { ok: false, error: typeof erro === "string" ? erro : erro ? JSON.stringify(erro) : `HTTP ${r.status}` };
    }
    if ((data as any).deduplicated) return { ok: true, deduplicated: true, messageId: null };
    return { ok: true, messageId: (data as any).messageId ?? null };
  } catch (e) {
    // Nenhuma resposta HTTP: tempo esgotado ou rede. A edge pode ter reservado a chave e até
    // enviado — `semResposta` é o que diz a quem chama que o desfecho é desconhecido (e que
    // só nesse caso a chave pode ser liberada).
    const abortado = e instanceof DOMException && e.name === "AbortError";
    return abortado
      ? { ok: false, error: `o envio pelo WhatsApp não respondeu em ${Math.round((limite ?? 0) / 1000)} s`, semResposta: true }
      : { ok: false, error: e instanceof Error ? e.message : String(e), semResposta: true };
  } finally {
    if (relogio) clearTimeout(relogio);
  }
}

// ─── Envio de orçamento/OS ao cliente: formato, cargos e resumo da confirmação ──────────

/**
 * Os jeitos de mandar uma ordem ao cliente pelo assistente. 'pdf' (05/10/2026, pedido do dono):
 * só o arquivo — sem número, total e link na legenda. Para quando ele já conversou com o cliente
 * e só quer que o orçamento chegue; a legenda é a frase dele (custom_message) ou nenhuma.
 */
export type FormatoDoEnvio = "pdf_e_link" | "pdf" | "link" | "resumo";

/**
 * Decisão do dono (05/10/2026): o padrão é SÓ o ARQUIVO PDF — com a frase dele na legenda, se
 * ele deu uma, ou sem texto. "Ainda não estou seguro de utilizar o link; a maioria dos clientes
 * atendo de forma presencial." Número, total e link (pdf_e_link) e "só o link" são quando ele
 * pede. (Até 05/10 o padrão era pdf_e_link — decisão de 26/09/2026.)
 */
export const FORMATO_PADRAO: FormatoDoEnvio = "pdf";

/**
 * O formato pedido. Ausente/vazio → o padrão. Valor desconhecido → null: a tool recusa em vez
 * de adivinhar (adivinhar 'link' mandaria menos do que o dono quis; adivinhar 'pdf' mandaria
 * preço e PIX sem ele ter pedido).
 *
 * A trava de autonomia (autonomy-policy.ts, NEVER_AUTONOMOUS_WHEN) normaliza igual — só
 * "link" é liberável; o teste confere que as duas leituras não se separam.
 */
/**
 * Retorno F4 (P12.2): para quem vai a ordem. Só "parceiro" (sem espaço nem maiúscula) é o parceiro; qualquer outro valor,
 * ou nenhum, é o cliente — o envio de sempre, sem ler a chave pdf_parceiro_ligado. A trava de autonomia normaliza igual.
 */
export function destinoDoEnvio(args: { destino?: unknown } | null | undefined): "cliente" | "parceiro" {
  return String(args?.destino ?? "").trim().toLowerCase() === "parceiro" ? "parceiro" : "cliente";
}

export function formatoDoEnvio(args: { formato?: unknown } | null | undefined): FormatoDoEnvio | null {
  const bruto = args?.formato;
  if (bruto === undefined || bruto === null || String(bruto).trim() === "") return FORMATO_PADRAO;
  const f = String(bruto).trim().toLowerCase();
  return f === "link" || f === "pdf_e_link" || f === "pdf" || f === "resumo" ? f : null;
}

/**
 * Quem pode mandar o PDF ao cliente. Lista explícita, e NÃO `NON_TECHNICIAN_ROLES`: aquela
 * inclui o vendedor externo, e o PDF leva preço, dados bancários e a chave PIX da empresa
 * num arquivo que não se desfaz. O formato 'link' mantém os cargos de sempre.
 */
export const CARGOS_DO_PDF_AO_CLIENTE: Role[] = ["admin", "financial", "seller"];

/**
 * Tamanho máximo da mensagem personalizada, por formato. No PDF ela é a abertura da legenda, e
 * o whatsapp-send recusa legenda acima de 1024 caracteres — o resto da legenda (número, total e
 * link) ocupa ~160, então 800 deixa folga. No 'pdf' ela é a legenda inteira (1000, abaixo dos
 * 1024). No link ela é o texto inteiro (limite 4096).
 *
 * Recusa em vez de cortar: a confirmação mostra a mensagem INTEIRA, e o "sim" é sobre ela —
 * cortar depois mandaria ao cliente um texto que o dono não leu (até 26/09/2026 o resumo cortava
 * em 200 caracteres e o envio mandava tudo).
 */
export const LIMITE_DA_MENSAGEM: Record<FormatoDoEnvio, number> = { pdf_e_link: 800, pdf: 1000, link: 4000, resumo: 800 };

/**
 * Formato e cargo do envio ao cliente — a MESMA checagem no gancho `preValidar` (antes de a
 * pendência nascer, para o dono não aprovar no sino um pedido que vai falhar) e no `execute`
 * (depois do "sim").
 *
 * Cargo: o de quem PEDIU (gravado na pendência, ver gravarSolicitante) e o de quem executa
 * têm de poder mandar o PDF (cargosQueContam, em registry.ts). Sem isto, o admin que aprovasse
 * no painel a pendência de um vendedor externo mandaria o PDF com o cargo dele.
 */
export function validarPedidoDeEnvio(
  args: Record<string, unknown> | null | undefined,
  ctx: Pick<ToolCtx, "userRole" | "userId">,
): ({ error: string } & Record<string, unknown>) | null {
  const formato = formatoDoEnvio(args);
  if (!formato) return { error: `Formato "${String(args?.formato)}" não existe. Use 'pdf' (padrão, só o arquivo), 'pdf_e_link', 'resumo' (valores em texto) ou 'link'.` };
  // Retorno F4 (P12.2): ao parceiro, só o PDF. O link público não passa pela via reduzida e continua valendo depois de um
  // veto; o resumo põe valor em texto. Recusado aqui, antes de a pendência nascer.
  if (destinoDoEnvio(args) === "parceiro" && formato !== "pdf") {
    return {
      error: "Ao parceiro vai só o PDF (formato 'pdf'), em via reduzida: o link continua valendo depois de um veto, e o resumo põe valor em texto. Nada foi enviado.",
      nada_enviado: true,
    };
  }
  const mensagem = typeof args?.custom_message === "string" ? args.custom_message.trim() : "";
  if (mensagem.length > LIMITE_DA_MENSAGEM[formato]) {
    return {
      error: `A mensagem personalizada tem ${mensagem.length} caracteres; ${formato === "link" ? "no envio só do link" : formato === "resumo" ? "no resumo de valores" : "junto do PDF"} cabem até ${LIMITE_DA_MENSAGEM[formato]}. Encurte e peça de novo.`,
      nada_enviado: true,
    };
  }
  // Os formatos com arquivo e o resumo levam preço e PIX: mesma lista de cargos.
  if (formato === "link") return null;
  if (cargosQueContam(args, ctx).every((c) => CARGOS_DO_PDF_AO_CLIENTE.includes(c as Role))) return null;
  const solicitante = lerSolicitante(args);
  const outraPessoaPediu = !!solicitante && solicitante.user_id !== ctx.userId &&
    !CARGOS_DO_PDF_AO_CLIENTE.includes(solicitante.cargo as Role);
  const quem = outraPessoaPediu ? `O cargo de quem pediu (${solicitante!.nome ?? "outro usuário"})` : "Seu cargo";
  return {
    error: `${quem} não manda o PDF ao cliente (o arquivo leva preço e dados de pagamento). Posso mandar só o link, com formato 'link' — é um envio novo e pede nova confirmação.`,
    alternativa: "formato 'link'",
    nada_enviado: true,
  };
}

/**
 * O resumo de valores com a frase do dono (05/10/2026): ela entra logo depois do "Olá, Fulano!",
 * antes dos valores — é o contexto da conversa ("como combinamos por telefone…"). Sem frase, o
 * resumo vai como o botão da tela monta.
 */
export function resumoComFrase(resumo: string, frase: string): string {
  const f = frase.trim();
  if (!f) return resumo;
  const linhas = resumo.split("\n");
  const ola = linhas.findIndex((l) => l.startsWith("Olá"));
  linhas.splice(ola >= 0 ? ola + 1 : 1, 0, f);
  return linhas.join("\n");
}

/** "••••1234" — o dono reconhece o número pelo final; o resumo não expõe o telefone inteiro. */
export function mascararTelefone(telefone: unknown): string {
  const digitos = String(telefone ?? "").replace(/\D/g, "");
  return digitos.length >= 4 ? `••••${digitos.slice(-4)}` : "••••";
}

// (F5, P11.4) orcamento_enviado_em: a coluna da F5 (20270112100000), no ar antes desta edge (8.2: migrations, depois edges)
const CAMPOS_DA_ORDEM_PARA_ENVIO =
  "id, service_order_number, share_token, client_id, status, grand_total, quote_status, created_at, quote_validity_days, quote_validity_date, cancellation_reason, origem, orcamento_enviado_em";

// ─── Retorno F5 (P11.4, C-VAL-ENVIO): a validade contada do envio, em todo envio de orçamento ─────────────────────────
// A data é a de orcamento_validade_do_envio (hoje + validade_orcamento_dias no 1º envio; a de antes no reenvio; vencida =
// nenhuma linha), e a legenda (O21) e a linha (O22) vêm prontas do banco, conferidas aqui pelo validador do retorno. A chave
// desligada (o padrão) devolve 'desligada': nada muda. A função ainda não publicada, também.

/** O que o envio usa da validade: a data, o motivo, a O21 e a O22 (já conferidas; nulas quando reprovadas ou vencida). */
export interface ValidadeDoEnvio {
  /** aaaa-mm-dd; null = sem data da F5 (desligada, funil, cargo, erro) */
  data: string | null;
  /** fixou | previa | ja_enviado | vencida | mudou | desligada | funil | cargo | erro */
  motivo: string;
  legenda: string | null;
  linha: string | null;
  aviso?: string;
}

const AVISO_LINHA_REPROVADA = "A linha da validade não entrou na legenda: confira na tela.";
const AVISO_VALIDADE_SEM_FIXAR = "Não consegui fixar a validade do envio; o PDF sai com a validade do cadastro.";
const FUNCAO_AUSENTE_NA_VALIDADE = new Set(["PGRST202", "42883"]);
const DIA_ISO = /^\d{4}-\d{2}-\d{2}$/;

/** "2026-12-15" → "15/12" (o dd/mm que a frase do dono pode já trazer). */
function ddmmDoDia(dia: string): string {
  const [, m, d] = dia.split("-");
  return `${d}/${m}`;
}

/**
 * orcamento_validade_do_envio(p_os, p_agora, p_gravar, p_esperada), pela chave de serviço (o p_agora vale). A legenda e a
 * linha passam por validarSaida com o contexto que o banco devolveu; reprovadas, saem nulas com o aviso. Nunca lança: erro =
 * motivo 'erro', sem data, com o aviso de que o PDF sai com a validade do cadastro.
 */
export async function validadeDoEnvio(
  admin: any,
  so: { id: string },
  opcoes: { agora: Date; gravar: boolean; esperada?: string | null },
): Promise<ValidadeDoEnvio> {
  const erro: ValidadeDoEnvio = { data: null, motivo: "erro", legenda: null, linha: null, aviso: AVISO_VALIDADE_SEM_FIXAR };
  try {
    const { data, error } = await admin.rpc("orcamento_validade_do_envio", {
      p_os: so.id, p_agora: opcoes.agora.toISOString(), p_gravar: opcoes.gravar, p_esperada: opcoes.esperada ?? null,
    });
    if (error) {
      // a F5 ainda não publicada: como a chave desligada (nada muda)
      if (FUNCAO_AUSENTE_NA_VALIDADE.has(String(error.code ?? ""))) return { data: null, motivo: "desligada", legenda: null, linha: null };
      return erro;
    }
    const r = (data ?? {}) as Record<string, unknown>;
    if (r.ok !== true) return r.motivo === "cargo" ? { data: null, motivo: "cargo", legenda: null, linha: null } : erro;
    const motivo = r.fixou === true ? "fixou" : typeof r.motivo === "string" && r.motivo ? r.motivo : "erro";
    if (motivo === "erro") return erro;
    const dia = typeof r.data === "string" && DIA_ISO.test(r.data) ? r.data : null;
    const v: ValidadeDoEnvio = { data: dia, motivo, legenda: null, linha: null };
    if (motivo === "vencida" || motivo === "mudou" || !dia) return v;
    const legenda = typeof r.legenda === "string" && r.legenda.trim() ? r.legenda.trim() : null;
    const linha = typeof r.linha === "string" && r.linha.trim() ? r.linha.trim() : null;
    if (!legenda && !linha) return v;
    // deno-lint-ignore no-explicit-any
    const contexto = r.contexto as any;
    const passa = (t: string | null) => t === null || validarSaida(t, contexto).ok;
    if (!passa(legenda) || !passa(linha)) return { ...v, aviso: AVISO_LINHA_REPROVADA };
    return { ...v, legenda, linha };
  } catch {
    return erro;
  }
}

/**
 * As opções do resumo de valores (montarResumoDeValores), as mesmas no resumo do *sim* e no envio: vencida → sem a linha da
 * validade; com data e outro motivo (a prévia, a data fixada ou a do 1º envio) → "válida até" essa data; sem a F5 (sem
 * validade, desligada, funil, cargo, erro) → undefined, o resumo de sempre, com a validade do cadastro.
 */
export function opcoesDoResumo(v?: ValidadeDoEnvio | null): { semValidade?: boolean; validadeAte?: string } | undefined {
  if (!v) return undefined;
  if (v.motivo === "vencida") return { semValidade: true };
  if (v.data && v.motivo !== "mudou") return { validadeAte: v.data };
  return undefined;
}

/** O *sim* chegou noutro dia e a data andou: nada sai (o *sim* é sobre o texto que sai). */
function fraseDoDiaQueVirou(antes: string | null, depois: string | null): string {
  const de = antes && DIA_ISO.test(antes) ? ddmmDoDia(antes) : "a data do pedido";
  const para = depois && DIA_ISO.test(depois) ? ddmmDoDia(depois) : "a de hoje";
  return `Desde o pedido, a validade do envio passou de ${de} para ${para} (o dia virou). Nada foi enviado ao cliente — peça de novo para confirmar com a data de agora.`;
}

/** As linhas que contam a verdade da validade no resumo do *sim* (P11.4); nenhuma sem a F5. */
function linhasDaValidadeNoResumo(so: { service_order_number?: string | null }, v: ValidadeDoEnvio | null): string[] {
  if (!v) return [];
  if (v.motivo === "vencida" && v.data) {
    return [`⚠️ O ${so.service_order_number} venceu em ${ddmmDoDia(v.data)}: o PDF sai com essa data. Para renovar, mude a validade na tela antes de mandar.`];
  }
  if (v.motivo === "previa" && v.data) {
    return [`Validade: até ${dataBR(v.data)}, contada de hoje (a data conta do envio: se você confirmar noutro dia, eu peço de novo).`];
  }
  if (v.motivo === "ja_enviado" && v.data) return [`Validade: até ${dataBR(v.data)}, a data do 1º envio.`];
  return v.aviso ? [`⚠️ ${v.aviso}`] : [];
}

/**
 * Retorno F3 (K6): 7 dias CONTADOS DO ENVIO, escritos no PDF. A data fica em quote_validity_date, que o PDF e a R19 já leem.
 * Vale para ORÇ do retorno e para o que sai pelo cartão, e é refeita a cada tentativa enquanto o orçamento está em rascunho:
 * PDF que falha não congela a data. Depois de 'sent' não renova (D13). Nunca lança: erro aqui segue o envio e devolve o aviso.
 *
 * Retorno F5 (P11.4): o ramo da F3 (com origem ou data do cartão) fica como está. O ramo novo (sem origem e sem data do
 * cartão, só orçamento) é validadeDoEnvio(gravar: true, esperada) e devolve `doEnvio` (mais o aviso_validade quando há aviso);
 * a chave desligada devolve {}, como hoje. `aoParceiro`: só o ramo da F3 (o parceiro não é o cliente, R-12; a data é a do
 * envio ao cliente). `soRamoNovo` (o link e o resumo): o ramo da F3 não roda (nunca rodou neles).
 */
export async function fixarValidadeDoEnvio(
  admin: any,
  so: { id: string; status?: string | null; quote_status?: string | null; origem?: string | null; quote_validity_date?: string | null },
  dataDoCartao?: string | null,
  agora: Date = new Date(),
  opcoes?: { aoParceiro?: boolean; soRamoNovo?: boolean; esperada?: string | null },
): Promise<{ aviso_validade?: string; doEnvio?: ValidadeDoEnvio }> {
  if (!dataDoCartao && !so.origem) {
    if (opcoes?.aoParceiro) return {};
    // OS não é orçamento: o banco diria 'ja_enviado' com a O21 ("Segue o OS-…")
    if (documentTypeFor(String(so.status ?? "")) !== "quote") return {};
    const doEnvio = await validadeDoEnvio(admin, so, { agora, gravar: true, esperada: opcoes?.esperada ?? null });
    if (doEnvio.motivo === "desligada") return {};
    return { doEnvio, ...(doEnvio.aviso ? { aviso_validade: doEnvio.aviso } : {}) };
  }
  if (opcoes?.soRamoNovo) return {};
  try {
    if (so.quote_status !== "draft") return {};
    const { data: cfg } = await admin.from("retorno_config").select("validade_orcamento_dias").maybeSingle();
    const n = diasDeValidade(cfg?.validade_orcamento_dias) ?? 7;
    const data = dataDoCartao ?? somarDiasAoDia(diaBR(agora), n);
    const { error } = await admin.from("service_orders").update({ quote_validity_days: n, quote_validity_date: data }).eq("id", so.id);
    if (error) throw error;
    return {};
  } catch {
    return { aviso_validade: "Não consegui gravar a validade; o PDF saiu com a validade antiga, confira na tela." };
  }
}

/** Ordem cancelada: se ela é a origem de um agrupamento, a frase aponta o orçamento (ou a OS) que vale agora. */
export function frasesDaOrdemCancelada(so: { service_order_number?: string; status?: unknown; cancellation_reason?: unknown }) {
  const agrupado = agrupadoEm(so);
  // OS agrupada (28/10/2026): "foi agrupada em OS-…", e o que vale é a OS nova.
  if (agrupado && ehOsAgrupada(so)) {
    return {
      aviso: `⚠️ ${so.service_order_number} foi agrupada em ${agrupado} — o envio será recusado; mande a ${agrupado}.`,
      erro: `${so.service_order_number} foi agrupada em ${agrupado} e não vale mais sozinha: mande a ${agrupado} ao cliente.`,
    };
  }
  return agrupado
    ? {
      aviso: `⚠️ ${so.service_order_number} foi agrupado em ${agrupado} — o envio será recusado; mande o ${agrupado}.`,
      erro: `${so.service_order_number} foi agrupado em ${agrupado} e não vale mais sozinho: mande o ${agrupado} ao cliente.`,
    }
    : {
      aviso: "⚠️ A ordem está CANCELADA — o envio será recusado.",
      erro: `A ordem ${so.service_order_number} está CANCELADA: não se manda ao cliente. Se ela voltou a valer, mude o status dela na tela antes de mandar.`,
    };
}

/**
 * No formato 'link' a mensagem personalizada SUBSTITUI o texto padrão. Se ela não traz o link,
 * o link vai no fim: "só o link" que chega sem link nenhum não é o que o dono pediu. Reconhece
 * pelo token, que é a parte do link que não muda de domínio para domínio.
 */
export function mensagemComLink(mensagem: string, link: string, shareToken: string): string {
  return mensagem.includes(shareToken) ? mensagem : `${mensagem}\n\n${link}`;
}

/**
 * A legenda do PDF no formato 'pdf' (decisão do dono, 20/10/2026): a frase dele (custom_message); sem ela, a
 * frase padrão — a mesma frase da tela de envio (src/lib/whatsapp-mensagem-ao-cliente.ts, corpoPadrao), sem
 * saudação, porque quase sempre ele já está conversando com o cliente; com sem_legenda ("só o arquivo"),
 * nenhuma. O resumo da confirmação e o envio usam esta função: o "sim" é sobre o texto que sai.
 *
 * Retorno F5 (P11.4): a linha da validade vem do banco (validadeDoEnvio), numa 2ª linha na tela e dentro da O21 no
 * assistente. Sem o 3º argumento, byte a byte a de antes. Com ele: sem frase e sem sem_legenda, a O21 ("Segue o ORÇ-00123,
 * conforme solicitado. Ele vale até terça (15/12). …"); com a frase do dono, ela inteira e, se não traz o dd/mm da data, a
 * O22 numa 2ª linha; vencida (sem legenda nem linha) ou legenda nula → a de antes. Continua síncrona e pura.
 */
export function legendaDoPdf(
  args: Record<string, unknown> | null | undefined,
  so: { service_order_number?: string | null; status?: string | null },
  validade?: ValidadeDoEnvio | null,
): string {
  const frase = typeof args?.custom_message === "string" ? args.custom_message.trim() : "";
  if (frase) {
    const linha = validade?.linha && validade.data && validade.motivo !== "vencida" ? validade.linha : null;
    return linha && !frase.includes(ddmmDoDia(validade!.data!)) ? `${frase}\n${linha}` : frase;
  }
  if (args?.sem_legenda === true || args?.sem_legenda === "true") return "";
  if (validade?.legenda && validade.motivo !== "vencida") return validade.legenda;
  const numero = String(so.service_order_number ?? "").trim();
  if (!numero) return "";
  return documentTypeFor(String(so.status ?? "")) === "quote"
    ? `Segue o ${numero}, conforme solicitado. Qualquer dúvida, estamos à disposição.`
    : `Segue a ${numero}. Qualquer dúvida, estamos à disposição.`;
}

/**
 * O retrato do envio que o dono aprova: o telefone do cadastro (em hash — o payload da pendência
 * não precisa do número) e o total. Tirado quando a pendência nasce (ToolDef.retratoDaPendencia);
 * o execute compara com o de agora. Sem isto, trocar o WhatsApp do cliente ou o valor do
 * orçamento entre o pedido e o "sim" mandava o arquivo para outro número, ou com outro preço,
 * do que o resumo mostrou.
 */
// deno-lint-ignore no-explicit-any
export async function retratoDoEnvio(admin: any, args: Record<string, unknown>, autor?: string | null): Promise<Record<string, unknown> | null> {
  const { data: so } = await buscarOrdemParaEnvio(admin, args?.service_order_id);
  if (!so) return null;
  // Retorno F4 (P12.2): ao parceiro, o retrato é o do número que parceiro_destino_do_pdf devolve (em hash), com o destino,
  // o parceiro e o número mascarado. Destino recusado: sem retrato (o execute recusa de novo, pela mesma regra).
  if (destinoDoEnvio(args) === "parceiro") {
    const d = await destinoDoParceiro(admin, so.id, autor ?? null, typeof args?.parceiro_id === "string" ? args.parceiro_id : null);
    if (!d.ok) return null;
    const digitosDoParceiro = String(d.phone).replace(/\D/g, "");
    return { telefone: hashCurto(digitosDoParceiro), total: Number(so.grand_total) || 0, destino: "parceiro", parceiro_id: d.parceiro_id, numero: `••${digitosDoParceiro.slice(-4)}` };
  }
  const { data: c } = so.client_id
    ? await admin.from("clients").select("whatsapp, phone").eq("id", so.client_id).maybeSingle()
    : { data: null };
  const digitos = String(c?.whatsapp || c?.phone || "").replace(/\D/g, "");
  // Retorno F5 (P11.4): a data que o resumo do *sim* mostrou (a prévia, sem gravar); o execute a passa como p_esperada, e o
  // *sim* de outro dia, com a data andando, não envia. Sem a F5 (desligada), o retrato de antes.
  const v = documentTypeFor(so.status) === "quote" && !so.origem ? await validadeDoEnvio(admin, so, { agora: new Date(), gravar: false }) : null;
  const daValidade = !v || v.motivo === "desligada" ? {} : v.data ? { validade: v.data } : { validade_motivo: v.motivo };
  return { telefone: hashCurto(digitos), total: Number(so.grand_total) || 0, ...daValidade };
}

/** Retorno F4 (C-DESTINO): a resposta de parceiro_destino_do_pdf. */
export type DestinoDoParceiro =
  | { ok: true; phone: string; chave8: string; rotulo: string; papel: string; interessado_id: string; parceiro_id: string; reduzir: boolean }
  | { ok: false; motivo: string; frase: string };

const DESTINO_INDISPONIVEL = "Não consegui conferir o destino do PDF ao parceiro; nada saiu.";

/**
 * Retorno F4 (P12.2): o único destino do PDF ao parceiro. Só o dono (o banco confere p_autor), regra do documento, número
 * único confirmado; nunca por nome, nunca de argumento de telefone. Erro ou resposta torta = recusa (falha fecha).
 */
// deno-lint-ignore no-explicit-any
export async function destinoDoParceiro(admin: any, os: string, autor: string | null, parceiro: string | null): Promise<DestinoDoParceiro> {
  try {
    const { data, error } = await admin.rpc("parceiro_destino_do_pdf", { p_os: os, p_autor: autor, p_parceiro: parceiro });
    if (error || !data || typeof data !== "object") return { ok: false, motivo: "erro", frase: DESTINO_INDISPONIVEL };
    const d = data as Record<string, unknown>;
    if (d.ok !== true) {
      return { ok: false, motivo: String(d.motivo ?? "erro"), frase: typeof d.frase === "string" && d.frase ? d.frase : DESTINO_INDISPONIVEL };
    }
    if (typeof d.phone !== "string" || String(d.phone).replace(/\D/g, "").length < 10) return { ok: false, motivo: "erro", frase: DESTINO_INDISPONIVEL };
    return {
      ok: true, phone: d.phone, chave8: String(d.chave8 ?? ""), rotulo: String(d.rotulo ?? "o parceiro"), papel: String(d.papel ?? ""),
      interessado_id: String(d.interessado_id ?? ""), parceiro_id: String(d.parceiro_id ?? ""), reduzir: d.reduzir !== false,
    };
  } catch {
    return { ok: false, motivo: "erro", frase: DESTINO_INDISPONIVEL };
  }
}

/** O que mudou entre o retrato aprovado e o estado de agora, em português; null = nada. */
export function oQueMudouDesdeOPedido(
  retrato: Record<string, unknown>,
  agora: { digitos: string; total: unknown },
  quem: "cliente" | "parceiro" = "cliente",
): string | null {
  const mudancas: string[] = [];
  if (typeof retrato.telefone === "string" && retrato.telefone !== hashCurto(agora.digitos)) {
    mudancas.push(quem === "parceiro" ? "o número do parceiro que recebe o PDF mudou" : "o WhatsApp do cliente no cadastro mudou");
  }
  const antes = Number(retrato.total);
  const depois = Number(agora.total) || 0;
  if (retrato.total !== undefined && Number.isFinite(antes) && Math.abs(antes - depois) > 0.005) {
    mudancas.push(`o total mudou (era ${fmtCurrency(antes)}, agora ${fmtCurrency(depois)})`);
  }
  return mudancas.length ? mudancas.join(" e ") : null;
}

/**
 * Pendência gravada ANTES do formato PDF (26/09/2026): não tem `_solicitante` (toda pendência
 * nova tem) nem `formato`. O dono a aprovou vendo o resumo antigo — o envio de sempre, que era
 * só o link. Lida hoje pelo padrão novo, mandaria um PDF com preço e PIX que ninguém viu.
 */
export function lerPendenciaDoEnvio(payload: Record<string, unknown>): Record<string, unknown> {
  const semFormato = payload?.formato === undefined || payload?.formato === null || String(payload.formato).trim() === "";
  return !lerSolicitante(payload) && semFormato ? { ...payload, formato: "link" } : payload;
}

/** Acha a ordem pelo UUID ou pelo número (ORÇ-00086 / OS-00075 / formato antigo). */
// deno-lint-ignore no-explicit-any
async function buscarOrdemParaEnvio(admin: any, idOuNumero: unknown) {
  const valor = String(idOuNumero ?? "");
  let q = admin.from("service_orders").select(CAMPOS_DA_ORDEM_PARA_ENVIO);
  q = UUID_RE.test(valor) ? q.eq("id", valor) : q.eq("service_order_number", valor);
  return await q.maybeSingle();
}

/**
 * Resumo da confirmação de send_service_order_link (painel e "sim <PIN>" no WhatsApp).
 *
 * Até 26/09/2026 o resumo era a lista crua dos argumentos: "OS/Orçamento: ORÇ-00086". O dono
 * dava o PIN sem ver PARA QUEM ia, em que número e com que valor — e agora o padrão manda um
 * arquivo com preço e PIX, que não se desfaz. O "sim" tem de ser sobre o que vai sair de fato:
 * cliente, telefone (mascarado), número, total e formato. O telefone é o do cadastro, que é o
 * único destino que a tool aceita.
 *
 * null = não achou a ordem; quem chama cai no resumo genérico.
 *
 * `agora` só existe para o teste fixar o dia; em produção é o relógio.
 */
export async function resumirEnvioAoCliente(
  // deno-lint-ignore no-explicit-any
  admin: any,
  args: Record<string, unknown>,
  agora: Date = new Date(),
  /** Retorno F4 (P12.2): quem pede o "sim" — o destino ao parceiro só responde ao dono. Sem destino, não é lido. */
  autor?: string | null,
): Promise<string | null> {
  // Retorno F4: a chave pdf_parceiro_ligado só é lida com destino parceiro, e antes de qualquer outra leitura
  if (destinoDoEnvio(args) === "parceiro" && !(await pdfAoParceiroLigado(admin))) {
    return "⚠️ O PDF ao parceiro está desligado — o envio será recusado.";
  }
  const { data: so } = await buscarOrdemParaEnvio(admin, args?.service_order_id);
  if (!so) return null;
  if (destinoDoEnvio(args) === "parceiro") return await resumirEnvioAoParceiro(admin, args, so, autor ?? null);
  const { data: c } = so.client_id
    ? await admin.from("clients").select("name, display_name, whatsapp, phone, opt_out_whatsapp, generico").eq("id", so.client_id).maybeSingle()
    : { data: null };
  const formato = formatoDoEnvio(args as { formato?: unknown });
  const rotulo = documentTypeFor(so.status) === "quote" ? "Orçamento" : "Ordem de Serviço";
  // Retorno F5 (P11.4): uma chamada, sem gravar, para todo formato: o dono lê no *sim* a legenda e o resumo exatos do envio
  // do mesmo dia (no dia seguinte, o 'mudou' impede o envio). Só orçamento sem origem (o do retorno segue o ramo da F3).
  const v = documentTypeFor(so.status) === "quote" && !so.origem ? await validadeDoEnvio(admin, so, { agora, gravar: false }) : null;
  const comF5 = !!v && !["desligada", "funil", "cargo", "erro"].includes(v.motivo);
  const telefone = c?.whatsapp || c?.phone;
  const linhas = [
    `Cliente: *${c?.name || "—"}*`,
    telefone ? `WhatsApp: ${mascararTelefone(telefone)} (do cadastro)` : "WhatsApp: ⚠️ cliente sem WhatsApp/telefone no cadastro — o envio vai falhar",
    `${rotulo}: *${so.service_order_number}* — Total *${fmtCurrency(Number(so.grand_total) || 0)}*`,
    formato === "link"
      ? "Formato: *só o link* (para ver online e aprovar)"
      : formato === "pdf_e_link"
      ? "Formato: *PDF anexado + link* (o arquivo com preço e PIX vai na conversa)"
      : formato === "pdf"
      ? "Formato: *só o PDF*, sem link (o arquivo com preço e PIX vai na conversa)"
      : formato === "resumo"
      ? "Formato: *resumo de valores em texto* (sem PDF nem link) — vai exatamente isto:"
      : `Formato: ⚠️ "${String(args?.formato)}" não existe — o envio será recusado`,
  ];
  // A mensagem INTEIRA: o "sim" é sobre o texto que o cliente vai ler. Acima do limite o envio é
  // recusado (validarPedidoDeEnvio), e o resumo diz isso em vez de mostrar um pedaço.
  const mensagem = typeof args?.custom_message === "string" ? args.custom_message.trim() : "";
  // Só o PDF sem frase dele (20/10/2026): vai a frase padrão — ou nada, se ele pediu "só o arquivo". O dono
  // tem de ver no "sim" exatamente a legenda que o cliente vai ler.
  if (!mensagem && formato === "pdf") {
    const legenda = legendaDoPdf(args, so, v);
    linhas.push(legenda ? `Legenda: "${legenda}"` : "Legenda: nenhuma (só o arquivo)");
  }
  // Resumo: o "sim" é sobre o TEXTO que o cliente vai ler — ele vai inteiro na confirmação, com a
  // frase do dono já no lugar (05/10/2026).
  if (formato === "resumo") {
    const { data: linhasDeConfig } = await admin.from("app_settings").select("key, value");
    const cfg: Record<string, string> = {};
    for (const r of (linhasDeConfig ?? []) as Array<{ key: string; value: unknown }>) cfg[r.key] = String(r.value ?? "");
    // (F5) com a mesma data do envio do mesmo dia (opcoesDoResumo): uma validade só no texto
    const montado = await montarResumoDeValores(admin, so, cfg, opcoesDoResumo(v));
    linhas.push(montado.ok ? `\n${resumoComFrase(montado.texto, mensagem)}\n` : `⚠️ Não consegui montar o resumo (${montado.motivo}) — o envio será recusado.`);
  }
  if (mensagem && formato !== "resumo") {
    // (F5) no PDF, a legenda que sai de verdade: a frase do dono e, sem o dd/mm, a linha da validade numa 2ª linha
    linhas.push(`${formato === "pdf" ? "Legenda" : "Mensagem"}: "${formato === "pdf" ? legendaDoPdf(args, so, v) : mensagem}"`);
    if (formato && mensagem.length > LIMITE_DA_MENSAGEM[formato]) {
      linhas.push(`⚠️ A mensagem tem ${mensagem.length} caracteres (limite ${LIMITE_DA_MENSAGEM[formato]}) — o envio será recusado.`);
    } else if (formato === "link" && so.share_token && !mensagem.includes(so.share_token)) {
      linhas.push("(a mensagem não traz o link: ele vai no fim dela)");
    }
  }
  if (so.status === "cancelled") linhas.push(frasesDaOrdemCancelada(so).aviso);
  // (F5) no pdf_e_link, a linha da validade logo depois da abertura (a mesma regra do dd/mm da frase)
  if (formato === "pdf_e_link" && v?.linha && v.data && !mensagem.includes(ddmmDoDia(v.data))) linhas.push(`Na legenda: "${v.linha}"`);
  // (F5, P11.4) o resumo diz a verdade de cada caso: o 1º envio (a data conta do envio), o reenvio (a data do 1º envio) e
  // o vencido (a data passada, uma vez só)
  linhas.push(...linhasDaValidadeNoResumo(so, v));
  // A validade que o PDF vai imprimir, pela MESMA conta do documento e do aviso de vencimento
  // (vencimentoDoOrcamento). Não bloqueia: reenviar um orçamento vencido para reabrir a conversa é
  // legítimo — mas o dono tem de saber, antes do "sim", que o cliente vai ler uma data passada.
  // (F5) só sem a validade do envio (desligada, funil, cargo, erro): com ela, a data é a da F5 e a frase é a de cima.
  if (documentTypeFor(so.status) === "quote" && !comF5) {
    const { data: padrao } = await admin.from("app_settings").select("value").eq("key", "quote_validity_days").maybeSingle();
    const ultimoDia = vencimentoDoOrcamento(so, { quote_validity_days: padrao?.value }, agora);
    if (ultimoDia) {
      linhas.push(`⚠️ A validade acabou em ${dataBR(ultimoDia)}: o PDF sai com essa data, já vencida. Para renovar, mude a validade do orçamento na tela antes de mandar — ou confirme assim mesmo.`);
    }
  }
  // Em 26/09/2026, 41 dos 51 orçamentos estavam 'rejected' — a maioria vencida pela rotina
  // quote-reminders, que já não rejeita (R19 só avisa). A recusa no funil é um fato à parte da
  // data: um orçamento recusado pelo cliente ontem ainda está dentro da validade.
  if (so.status === "draft" && so.quote_status === "rejected") {
    linhas.push("⚠️ Este orçamento está marcado como RECUSADO no funil.");
  }
  if (c?.opt_out_whatsapp) linhas.push("⚠️ O cliente pediu para não receber WhatsApp (opt-out) — o envio será recusado.");
  if (c?.generico) linhas.push('⚠️ É o cadastro genérico "Cliente Final", com o telefone de um terceiro — o envio será recusado.');
  return linhas.join("\n");
}

// ─── Retorno F4 (P12.2): o PDF ao parceiro ──────────────────────────────────────────────────────────────────────────
// Só com destino "parceiro" e retorno_config.pdf_parceiro_ligado. O destino é SÓ o de parceiro_destino_do_pdf (dono, regra
// do documento, número único confirmado); o cadastro do cliente nem é lido. Só o PDF, em via reduzida quando o banco diz
// `reduzir`, com contexto service_order (o whatsapp-send não marca 'sent', R-12). O registro vai a ai_comms_log com
// audiência parceiro e o papel, sem nome: é a fonte da medida (P14).

/** A chave do envio ao parceiro; erro ou ausência = desligada (falha fecha). Só é lida com destino parceiro. */
// deno-lint-ignore no-explicit-any
async function pdfAoParceiroLigado(admin: any): Promise<boolean> {
  try {
    const { data, error } = await admin.from("retorno_config").select("pdf_parceiro_ligado").maybeSingle();
    return !error && data?.pdf_parceiro_ligado === true;
  } catch {
    return false;
  }
}

const PAPEL_NO_RESUMO: Record<string, string> = { contratante: "ela contrata", pagador: "ela paga" };

/** O resumo do "sim" do PDF ao parceiro: para quem (o rótulo do banco, com o número mascarado), qual documento e a via. */
async function resumirEnvioAoParceiro(
  // deno-lint-ignore no-explicit-any
  admin: any,
  args: Record<string, unknown>,
  // deno-lint-ignore no-explicit-any
  so: any,
  autor: string | null,
): Promise<string> {
  const d = await destinoDoParceiro(admin, so.id, autor, typeof args?.parceiro_id === "string" ? args.parceiro_id : null);
  if (!d.ok) return `⚠️ ${d.frase.replace(/\s*Nada saiu\.?$|;\s*nada saiu\.?$/i, "")} — o envio será recusado.`;
  const rotulo = documentTypeFor(so.status) === "quote" ? "Orçamento" : "Ordem de Serviço";
  const linhas = [
    `PDF *para a ${d.rotulo}*${PAPEL_NO_RESUMO[d.papel] ? ` (${PAPEL_NO_RESUMO[d.papel]})` : ""}`,
    `${rotulo}: *${so.service_order_number}* — Total *${fmtCurrency(Number(so.grand_total) || 0)}*`,
    d.reduzir
      ? "Formato: *só o PDF*, em via reduzida: nome e inicial do cliente, sem CPF, telefone, e-mail nem endereço"
      : "Formato: *só o PDF* (a ordem é da própria parceira: vai com os dados dela)",
  ];
  const mensagem = typeof args?.custom_message === "string" ? args.custom_message.trim() : "";
  if (mensagem) {
    linhas.push(`Legenda: "${mensagem}"`);
    if (mensagem.length > LIMITE_DA_MENSAGEM.pdf) linhas.push(`⚠️ A mensagem tem ${mensagem.length} caracteres (limite ${LIMITE_DA_MENSAGEM.pdf}) — o envio será recusado.`);
  } else {
    const legenda = legendaDoPdf(args, so);
    linhas.push(legenda ? `Legenda: "${legenda}"` : "Legenda: nenhuma (só o arquivo)");
  }
  if (so.status === "cancelled") linhas.push(frasesDaOrdemCancelada(so).aviso);
  return linhas.join("\n");
}

/** O execute com destino parceiro. Nunca lê telefone dos argumentos nem do cadastro do cliente. */
async function enviarPdfAoParceiro(args: Record<string, unknown>, ctx: ToolCtx): Promise<Record<string, unknown>> {
  const { admin, jwt, settings } = ctx;
  // 0. a chave, antes de qualquer outra leitura
  if (!(await pdfAoParceiroLigado(admin))) return { error: "O envio de PDF ao parceiro está desligado; nada saiu.", nada_enviado: true };
  const { data: so, error: soErr } = await buscarOrdemParaEnvio(admin, args.service_order_id);
  if (soErr || !so) return { error: `OS não encontrada. Verifique se o número ou ID está correto. Valor recebido: "${args.service_order_id}"`, nada_enviado: true };
  if (so.status === "cancelled") return { error: frasesDaOrdemCancelada(so).erro, nada_enviado: true };
  if (!so.share_token) return { error: `A ${so.service_order_number} não possui link público ainda. Abra a OS no app, clique em "Compartilhar" para gerar o link, e tente novamente.`, nada_enviado: true };

  // 1. o destino, pela regra do documento; o parceiro só vem do retrato (que o sistema grava), nunca do argumento
  const retrato = lerRetrato(args);
  const d = await destinoDoParceiro(admin, so.id, ctx.userId ?? null, typeof retrato?.parceiro_id === "string" ? retrato.parceiro_id : null);
  if (!d.ok) return { error: d.frase, nada_enviado: true };
  const phone = d.phone;
  const digitos = phone.replace(/\D/g, "");
  const mudou = retrato ? oQueMudouDesdeOPedido(retrato, { digitos, total: so.grand_total }, "parceiro") : null;
  if (mudou) return { error: `Desde o pedido, ${mudou}. Nada foi enviado — peça de novo para confirmar com os dados de agora.`, nada_enviado: true };

  // 2. a guarda: janela e valor_a_parceiro com o papel (o documento leva valor)
  const legenda = legendaDoPdf(args, so);
  const preview = `[pdf parceiro] papel=${d.papel || "nenhum"}`;
  if (legenda.length > 1024) return { error: "A mensagem personalizada ficou longa demais para a legenda do PDF (limite do WhatsApp). Encurte e tente de novo.", nada_enviado: true };
  const papel = (d.papel === "indicou" || d.papel === "contratante" || d.papel === "pagador") ? d.papel : null;
  const g = guardaDeEnvio(legenda, {
    tipo: "os_link", audiencia: "parceiro", canal: "whatsapp", destinatarioIdentificado: true, papelDoParceiro: papel, documentoComValor: true,
  });
  if (g.bloqueado) {
    await registrarEnvio(admin, { tipo: "os_link", audiencia: "parceiro", entityKind: "service_order", entityId: so.id, phone, preview, status: "blocked", blockCode: g.codigoBloqueio });
    return { error: g.motivo, nada_enviado: true };
  }

  // 3. o documento, em via reduzida quando o banco diz reduzir
  // (F5, P11.4) ao parceiro, só o ramo da F3: nunca fixa "hoje + 7" (a data é a do envio ao cliente, K6; o parceiro não é o
  // cliente, R-12), e nunca há doEnvio
  const validade = await fixarValidadeDoEnvio(admin, so, ctx.validadeDoCartao, new Date(), { aoParceiro: true });
  const montado = await montarDocumentoDaOrdem(admin, so, settings, { ocultarDadosDoCliente: d.reduzir });
  if (!montado.ok) {
    await registrarEnvio(admin, { tipo: "os_link", audiencia: "parceiro", entityKind: "service_order", entityId: so.id, phone, preview: `${preview} não gerado`, status: "failed" });
    return { error: `O PDF não foi gerado (${montado.motivo}). Nada foi enviado ao parceiro.`, nada_enviado: true };
  }
  const doc = montado.doc;
  const modoTeste = desviadoPorTeste(settings);
  // 4. a chave anti-duplicado leva o número do parceiro; contexto service_order: o whatsapp-send não marca 'sent'
  const chave = chaveDeEnvio("os-pdf", so.id, digitos, diaLocal(), impressaoDigitalDoDocumento(doc.html), modoTeste ? "teste" : null);
  const entrega = await guardarEEntregar({
    admin,
    doc,
    shareToken: so.share_token,
    baseUrl: settings.app_public_url || "",
    rotuloDoLog: "send_service_order_link (parceiro)",
    entregar: (url) =>
      enviarOrdemAoCliente({
        phone,
        serviceOrderId: so.id,
        context: "service_order",
        jwt,
        dedupeKey: chave,
        sentBy: ctx.userId,
        conteudo: { kind: "document", url, filename: doc.nomeDoArquivo, caption: legenda },
      }),
  });
  if (!entrega.ok) {
    await registrarEnvio(admin, { tipo: "os_link", audiencia: "parceiro", entityKind: "service_order", entityId: so.id, phone, preview: `${preview} não gerado`, status: "failed" });
    return { error: `O PDF não foi gerado (${entrega.motivo}). Nada foi enviado ao parceiro.`, nada_enviado: true };
  }
  const envio = entrega.valor;
  if (!envio.ok) {
    if (envio.semResposta) await liberarEnvio(admin, chave).catch(() => {});
    await registrarEnvio(admin, { tipo: "os_link", audiencia: "parceiro", entityKind: "service_order", entityId: so.id, phone, preview, status: "failed" });
    return envio.semResposta
      ? { error: `O WhatsApp não confirmou o envio do PDF ao parceiro (${envio.error}): pode ter chegado ou não. Confira antes de reenviar.` }
      : { error: `O WhatsApp recusou o envio do PDF ao parceiro (${envio.error}). Nada foi enviado.`, nada_enviado: true };
  }
  const rotuloDoc = `${doc.rotulo} ${doc.numero}`;
  const teste = modoTeste ? { desviado_para_teste: true } : {};
  if (envio.deduplicated) {
    return { ok: true, deduplicated: true, aviso: `Este mesmo PDF (${rotuloDoc}) já foi enviado hoje a ${d.rotulo}; não reenviei.`, destino: "parceiro", destino_chave8: digitos.slice(-8), ...validade, ...teste };
  }
  await registrarEnvio(admin, { tipo: "os_link", audiencia: "parceiro", entityKind: "service_order", entityId: so.id, phone, preview, status: "sent" });
  return {
    ok: true,
    formato: "pdf",
    destino: "parceiro",
    enviado_para: modoTeste ? "o número de TESTE do WhatsApp (modo de teste ligado), não o parceiro" : `a ${d.rotulo}`,
    documento: rotuloDoc,
    total: doc.total,
    arquivo: doc.nomeDoArquivo,
    destino_chave8: digitos.slice(-8),
    observacao: modoTeste
      ? "O modo de teste do WhatsApp está ligado: o PDF foi para o número de teste, NÃO para o parceiro. Diga isso."
      : d.reduzir
      ? "O parceiro recebeu o PDF em via reduzida (nome e inicial do cliente, sem CPF, telefone, e-mail nem endereço)."
      : "O parceiro recebeu o PDF.",
    ...validade,
    ...teste,
  };
}

/**
 * O PDF não saiu: NADA foi ao cliente. O caminho de volta é mandar só o link — um envio novo,
 * com nova confirmação. Trocar o formato sozinho mandaria ao cliente algo que o dono não
 * aprovou.
 *
 * A oferta vai DENTRO do `error`, não só em `orientacao`: depois do "sim" (painel ou
 * "sim <PIN>" no WhatsApp) quem fala com o dono é o ai-agent, sem o modelo, e ele mostra só
 * "⚠️ <título> — falhou: <error>".
 */
function anexoFalhou(motivo: string) {
  return {
    error: `O PDF não foi anexado (${motivo}). Nada foi enviado ao cliente. Se quiser, mando só o link — é um envio novo e pede nova confirmação.`,
    nada_enviado: true,
    alternativa: "mandar só o link (formato 'link')",
    orientacao:
      "Diga ao usuário que o anexo do PDF falhou e que NADA foi enviado ao cliente — não diga que mandou. Ofereça mandar só o link: se ele aceitar, chame send_service_order_link de novo com formato='link' (é um envio novo e pede nova confirmação). Não troque o formato por conta própria.",
  };
}

/**
 * Usa a edge function whatsapp-send (não whatsapp-send-text) para respeitar
 * wa_test_mode/wa_test_number do app_settings.
 */
export async function sendWhatsapp(phone: string, message: string, jwt: string, dedupeKey?: string, sentBy?: string) {
  const r = await postarWhatsappSend({
    phone, message, kind: "text", ...(dedupeKey ? { dedupe_key: dedupeKey } : {}), ...(sentBy ? { sent_by: sentBy } : {}),
  }, jwt);
  const data = await r.json().catch(() => ({}));
  if (!r.ok) return { error: (data as any).error || `HTTP ${r.status}` };
  if ((data as any).deduplicated) {
    // A edge reconheceu a chave: esta mesma mensagem já saiu hoje para este número.
    return { ok: true, messageId: null, deduplicated: true, aviso: "Esta mesma mensagem já tinha sido enviada hoje para este número; não reenviei." };
  }
  return { ok: true, messageId: (data as any).messageId };
}

export const whatsappTools: ToolDef[] = [
  {
    name: "send_whatsapp_message",
    description:
      "Envia mensagem de WhatsApp (sempre com a confirmação do usuário, que vê para quem, o número, a ÚLTIMA mensagem que a pessoa mandou e o texto). " +
      "Forneça to_phone (o número da conversa, como veio de get_whatsapp_conversation) OU client_id. " +
      "Para RESPONDER uma conversa, leia antes com get_whatsapp_conversation e chame esta tool com a resposta sugerida — a confirmação é a sugestão.",
    input_schema: {
      type: "object",
      properties: {
        to_phone: { type: "string", description: "Número do destinatário (o da conversa), em qualquer formato." },
        client_id: { type: "string", description: "UUID do cliente do cadastro." },
        message: { type: "string", description: "O texto que vai ao destinatário." },
      },
      required: ["message"],
    },
    // "pior caso" para o filtro por cargo — o risco real depende do destinatário.
    risk: "high",
    roles: NON_TECHNICIAN_ROLES,
    computeRisk: (args) => (args?.client_id ? "high" : "medium"),
    // Mensagem vazia ou número inválido: recusado antes de pedir a confirmação (06/10/2026).
    preValidar: (args) => validarMensagem(args),
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const invalida = validarMensagem(args);
      if (invalida) return invalida;
      const { sb, jwt } = ctx;
      let phone: string | null = args.to_phone ? telefoneParaEnvio(args.to_phone) : null;
      if (!phone && args.client_id) {
        const { data: c } = await sb.from("clients").select("whatsapp, phone").eq("id", args.client_id).maybeSingle();
        phone = c?.whatsapp || c?.phone;
      }
      if (!phone) return { error: "Telefone não fornecido nem encontrado para o cliente." };
      // Idempotência: mesmo texto, mesmo número, mesmo dia = um envio (protege contra o
      // laço do agente repetir a tool após um timeout).
      const chave = chaveDeEnvio("agente-msg", String(phone).replace(/\D/g, ""), diaLocal(), hashCurto(String(args.message)));
      return await sendWhatsapp(phone, args.message, jwt, chave, ctx.userId);
    },
  },
  {
    name: "send_supplier_quote_request",
    description:
      // O passo a passo do ciclo (ler resposta -> registrar preço -> comparar -> aplicar ->
      // gerar OC) vivia aqui E na seção COTAÇÃO A FORNECEDORES do system prompt. Uma cópia
      // basta, e o lugar do workflow é o prompt — descrição de tool é contrato.
      "Envia o pedido de uma COTAÇÃO já criada (create_quote_request) por WhatsApp aos FORNECEDORES dela (ação sensível — pede confirmação). Informe quote_request_id (o id ou o código COT-XXXXX): vão o código e os itens numerados, o que faz a resposta do fornecedor voltar interpretável. supplier_ids só se for mandar a parte dos fornecedores (ou acrescentar um). Vai pela FILA de envio, como o botão Enviar da tela, e fica registrado quem recebeu. O envio é o começo do ciclo de cotação, não o fim.",
    input_schema: {
      type: "object",
      properties: {
        quote_request_id: { type: "string", description: "Id ou código (COT-XXXXX) da cotação criada com create_quote_request. Obrigatório." },
        supplier_ids: { type: "array", items: { type: "string" }, description: "Só se for mandar a uma parte dos fornecedores da cotação, ou acrescentar um (de suggest_suppliers/create_supplier). Sem isto, vai a todos os da cotação." },
        notes: { type: "string", description: "Observação opcional que VAI na mensagem (ex.: condição de pagamento). NÃO use para prazo (quem define é o fornecedor, só se ele perguntar) nem para descrever a aplicação/'pra que serve' (confunde quem atende)." },
      },
      required: ["quote_request_id"],
    },
    risk: "high",
    roles: NON_TECHNICIAN_ROLES,
    // Sem cotação não há envio (07/10/2026): o pedido avulso não tinha código nem itens
    // numerados, não ficava em quote_request_sends e a resposta não tinha onde ser registrada.
    preValidar: (args) => (args?.quote_request_id ? null : { error: SEM_COTACAO }),
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      // Admin e financeiro: as policies de quote_requests/quote_request_sends (pelo WhatsApp o
      // assistente grava sem RLS).
      if (!["admin", "financial"].includes(ctx.userRole)) return { error: "Cotação a fornecedor é do administrador e do financeiro." };
      if (!args.quote_request_id) return { error: SEM_COTACAO };
      const { admin, userId, settings } = ctx;

      // ── A cotação, os itens e os fornecedores (leitura que falha não vira "não achei") ──
      const ref = String(args.quote_request_id).trim();
      const digitosDaCotacao = ref.replace(/\D/g, "").replace(/^0+(?=\d)/, "");
      let q = admin.from("quote_requests").select("id, code, status, sent_supplier_ids");
      q = UUID_RE.test(ref) ? q.eq("id", ref) : q.eq("code", `COT-${digitosDaCotacao.padStart(5, "0")}`);
      const { data: req, error: reqErr } = await q.maybeSingle();
      if (reqErr) return { error: `A consulta da cotação falhou (${reqErr.message}). Nada foi enviado.` };
      if (!req) return { error: `Cotação ${ref} não encontrada. Nada foi enviado.` };
      if (req.status !== "open") return { error: `A cotação ${req.code} está ${req.status === "closed" ? "fechada" : "cancelada"} — reabra antes de mandar.` };
      const { data: qItems, error: itErr } = await admin
        .from("quote_request_items")
        .select("position, description, quantity")
        .eq("quote_request_id", req.id)
        .order("position", { ascending: true });
      if (itErr) return { error: `A consulta dos itens da cotação falhou (${itErr.message}). Nada foi enviado.` };
      const items = (qItems || []) as Array<{ position: number; description: string; quantity: number }>;
      if (!items.length) return { error: `A cotação ${req.code} não tem itens para mandar.` };
      const daCotacao: string[] = (req.sent_supplier_ids as string[]) || [];
      const pedidos: string[] = Array.isArray(args.supplier_ids) && args.supplier_ids.length ? [...new Set(args.supplier_ids as string[])] : daCotacao;
      if (!pedidos.length) return { error: `A cotação ${req.code} não tem fornecedor. Diga para quem mandar (supplier_ids).` };

      // Modo de teste: a fila NÃO aplica wa_test_mode (quem aplica é o whatsapp-send) — o desvio é
      // feito aqui, como na tela. Ligado sem número de teste, a tela recusa: aqui também.
      const numeroDeTeste = numeroDeTesteAtivo(settings);
      if (modoDeTesteSemNumero(settings)) return { error: "Modo de teste do WhatsApp ligado sem número de teste configurado. Nada foi enviado." };

      const { data: suppliers, error: supErr } = await admin.from("suppliers").select("id, name, trade_name, phone, opt_out_whatsapp").in("id", pedidos);
      if (supErr) return { error: `A consulta dos fornecedores falhou (${supErr.message}). Nada foi enviado.` };
      const byId: Record<string, any> = Object.fromEntries((suppliers || []).map((s: any) => [s.id, s]));

      // Fornecedor novo na cotação (pedido para alguém fora da lista): entra em sent_supplier_ids,
      // como o "incluir fornecedor" da tela — senão a resposta dele não teria cotação onde cair.
      const novos = pedidos.filter((id) => byId[id] && !daCotacao.includes(id));
      if (novos.length) {
        const { error: incErr } = await admin.from("quote_requests").update({ sent_supplier_ids: [...daCotacao, ...novos] }).eq("id", req.id);
        if (incErr) return { error: `Não consegui incluir o fornecedor na cotação (${incErr.message}). Nada foi enviado.` };
      }

      const company = settings.company_name || "nossa empresa";
      // Itens NUMERADOS: é o que faz o fornecedor responder "1 - R$ 850 - 5 dias".
      const itemLines = items
        .map((it, i) => `${it.position ?? i + 1}. ${it.quantity ? `${Number(it.quantity)}x ` : ""}${it.description ?? ""}`.trimEnd())
        .join("\n");
      // Mensagem ENXUTA de propósito, IDÊNTICA à do botão Enviar da tela (useSendQuoteRequest): o
      // fornecedor não recebe dois formatos conforme quem disparou. Saudação + itens numerados; sem
      // descrever a aplicação, sem estipular prazo, sem ensinar a responder. Só um args.notes
      // explícito (ex.: condição de pagamento) vai junto; req.notes fica interno.
      const msg =
        `Olá, tudo bem? Aqui é da ${company}.\n` +
        `Gostaríamos de uma cotação (${req.code}):\n${itemLines}` +
        `${args.notes ? `\n\n${args.notes}` : ""}\n\n` +
        `Obrigado!`;

      const resultados: Array<{ fornecedor: string; status: string }> = [];
      const avisos = new Set<string>();
      let enfileirados = 0;
      for (const sid of pedidos) {
        const sup = byId[sid];
        if (!sup) { resultados.push({ fornecedor: sid, status: "não encontrado" }); continue; }
        const nomeForn = sup.trade_name || sup.name || sid;
        if (sup.opt_out_whatsapp) { resultados.push({ fornecedor: nomeForn, status: "opt-out (não receber)" }); continue; }
        // Mesma normalização e mesma régua de número da tela (normalizeWhatsappPhone/isUsableWhatsappPhone).
        const phone = normalizePhoneNumber(String(sup.phone || ""));
        if (!(phone.startsWith("55") && (phone.length === 12 || phone.length === 13))) {
          resultados.push({ fornecedor: nomeForn, status: sup.phone ? "telefone inválido" : "sem WhatsApp cadastrado" });
          continue;
        }
        // Portão de comunicação: conformidade (bloqueia) + estilo (avisa).
        const g = guardaDeEnvio(msg, { tipo: "cotacao", audiencia: "fornecedor", canal: "whatsapp", destinatarioIdentificado: true });
        if (g.bloqueado) {
          resultados.push({ fornecedor: nomeForn, status: `bloqueado: ${g.motivo}` });
          await registrarEnvio(admin, { tipo: "cotacao", audiencia: "fornecedor", entityKind: "supplier", entityId: sid, phone, preview: msg, status: "blocked", blockCode: g.codigoBloqueio });
          continue;
        }
        g.avisos.forEach((a) => avisos.add(a));
        const destino = numeroDeTeste ?? phone;
        // Pela FILA, como a tela (07/10/2026): o worker repete sozinho e a mensagem sobrevive ao
        // WhatsApp fora do ar. Antes ia direto e não gravava quote_request_sends — a cotação dizia
        // "enviada" sem registro de quem recebeu. A dedupe_key (índice único da fila) faz o mesmo
        // pedido repetido no mesmo dia não sair duas vezes.
        const { data: fila, error: qErr } = await admin.from("whatsapp_send_queue").insert({
          phone_normalized: destino,
          message: msg,
          source: "quote_request",
          source_ref_id: req.id,
          priority: 2,
          dedupe_key: chaveDeEnvio("cotacao-fila", req.code, sid, diaLocal(), hashCurto(msg), numeroDeTeste ? "teste" : null),
        }).select("id").single();
        if (qErr) {
          const repetido = qErr.code === "23505";
          resultados.push({ fornecedor: nomeForn, status: repetido ? "já enviado hoje" : `falhou: ${qErr.message}` });
          if (!repetido) await registrarEnvio(admin, { tipo: "cotacao", audiencia: "fornecedor", entityKind: "supplier", entityId: sid, phone, preview: msg, status: "failed" });
          continue;
        }
        const { error: envErr } = await admin.from("quote_request_sends").insert({
          quote_request_id: req.id,
          supplier_id: sid,
          phone_normalized: destino,
          queue_id: fila.id,
          created_by: userId || null,
        });
        enfileirados++;
        resultados.push({ fornecedor: nomeForn, status: envErr ? `na fila (mas o registro do envio falhou: ${envErr.message})` : "na fila de envio" });
        await registrarEnvio(admin, { tipo: "cotacao", audiencia: "fornecedor", entityKind: "supplier", entityId: sid, phone, preview: msg, status: "sent" });
      }
      if (!enfileirados) {
        return { error: `Nenhum envio saiu. ${resultados.map((r) => `${r.fornecedor}: ${r.status}`).join(" · ")}`, cotacao: req.code, resultados };
      }
      return {
        ok: true,
        cotacao: req.code,
        enviados: enfileirados,
        total: pedidos.length,
        resultados,
        observacao: numeroDeTeste
          ? "Modo de teste do WhatsApp ligado: foi para o número de TESTE, não aos fornecedores. Diga isso."
          : "Vai pela fila de envio: sai em até um minuto (se o WhatsApp estiver fora do ar, sai quando voltar).",
        ...(avisos.size ? { avisos_estilo: [...avisos] } : {}),
      };
    },
  },
  {
    name: "send_collection_reminder",
    description: "Envia um lembrete de cobrança por WhatsApp para o contato da cobrança.",
    input_schema: {
      type: "object",
      properties: { collection_id: { type: "string" }, custom_message: { type: "string" } },
      required: ["collection_id"],
    },
    // Sempre envia pro contato da cobrança — sempre cliente, nunca equipe.
    risk: "high",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { sb, admin, jwt } = ctx;
      const { data: col, error } = await sb
        .from("collections")
        .select("id, amount, due_date, contact_whatsapp, phone, contact_name, client_id, description, status")
        .eq("id", args.collection_id)
        .maybeSingle();
      if (error || !col) return { error: "Cobrança não encontrada" };
      // Cobrança paga ou cancelada não se cobra (07/10/2026): cobrar quem pagou custa a relação.
      if (col.status === "paid" || col.status === "cancelled") {
        return { error: `Esta cobrança está ${col.status === "paid" ? "paga" : "cancelada"}: não mando lembrete.` };
      }
      // D21 (dono, 17/09/2026): piso de materialidade — abaixo dele não se cobra por mensagem.
      const { data: cfgPiso } = await admin.from("app_settings").select("value").eq("key", "collection_min_amount").maybeSingle();
      const piso = Number((cfgPiso as { value?: string } | null)?.value) || 0;
      if (piso > 0 && Number(col.amount) < piso) {
        return { error: `Cobrança de R$ ${Number(col.amount).toFixed(2)} fica abaixo do piso de R$ ${piso} (Configurações): só listar, não cobrar por WhatsApp.` };
      }
      // Pix do cliente esperando no Extrato: pode ser este pagamento. Não cobra até decidir a linha
      // (aplicar na conta, ou aprovar como receita nova) — cobrar quem pagou custa a relação.
      if (col.client_id) {
        const pix = (await pixEsperandoNoExtrato(ctx, [String(col.client_id)])).get(String(col.client_id)) ?? [];
        if (pix.length) {
          const lista = pix.map((p) => `R$ ${p.valor.toFixed(2)}${p.data ? ` de ${p.data}` : ""}`).join(", ");
          return {
            error: `Este cliente tem Pix esperando no Extrato (${lista}): pode ser este pagamento. `
              + "Confira no Extrato (Este Pix paga…) antes de cobrar; se for outra coisa, decida a linha lá e cobre depois.",
          };
        }
      }
      // Perfil do contato: nome usado (display_name) e opt-out.
      let c: any = null;
      if (col.client_id) {
        const r = await sb.from("clients").select("whatsapp, phone, name, display_name, opt_out_whatsapp, generico").eq("id", col.client_id).maybeSingle();
        c = r.data;
      }
      if (c?.opt_out_whatsapp) return { error: "Este cliente pediu para não receber mensagens no WhatsApp (opt-out). Cobre por outro canal." };
      // A cobrança pode ter contato próprio; só recusa quando o destino seria o telefone do cadastro genérico.
      if (c?.generico && !col.contact_whatsapp && !col.phone) return { error: RECUSA_CLIENTE_FINAL, nada_enviado: true };
      const phone = col.contact_whatsapp || col.phone || c?.whatsapp || c?.phone;
      if (!phone) return { error: "Sem telefone para enviar o lembrete." };
      const fmt = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(col.amount);
      const nomeUsado = c?.display_name || col.contact_name || (c?.name ? String(c.name).trim().split(/\s+/)[0] : "");
      const msg =
        args.custom_message ||
        `Olá${nomeUsado ? ` ${nomeUsado}` : ""}, lembrete amigável: você possui um valor de ${fmt} com vencimento em ${col.due_date}. Qualquer dúvida estamos à disposição.`;
      // Portão: conformidade (horário, número identificado) bloqueia; estilo (ameaça) avisa.
      const g = guardaDeEnvio(msg, { tipo: "cobranca", audiencia: "cliente", canal: "whatsapp", destinatarioIdentificado: !!col.client_id, texto: msg });
      if (g.bloqueado) {
        await registrarEnvio(admin, { tipo: "cobranca", audiencia: "cliente", entityKind: "client", entityId: col.client_id, phone, preview: msg, status: "blocked", blockCode: g.codigoBloqueio });
        return { error: g.motivo };
      }
      const r = await sendWhatsapp(phone, msg, jwt, chaveDeEnvio("cobranca", col.id, diaLocal()), ctx.userId);
      // Enviado: o contato 'whatsapp_sent' no histórico e a situação 'enviada', como a tela faz
      // (useSendCollectionWhatsApp) — antes só o last_auto_sent_at mudava (07/10/2026).
      const avisoDoRegistro = r.ok && !r.deduplicated
        ? await registrarEnvioDaCobranca(admin, col, ctx.userId, "Lembrete enviado pelo assistente (WhatsApp)")
        : null;
      await registrarEnvio(admin, { tipo: "cobranca", audiencia: "cliente", entityKind: "client", entityId: col.client_id, phone, preview: msg, status: r.ok ? "sent" : "failed" });
      return { ...r, ...(g.avisos.length ? { avisos_estilo: g.avisos } : {}), ...(avisoDoRegistro ? { aviso: avisoDoRegistro } : {}) };
    },
  },
  {
    name: "send_service_order_link",
    description:
      "Envia um orçamento/OS AO CLIENTE pelo WhatsApp, sempre para o WhatsApp/telefone do cadastro do cliente (não existe campo de telefone). Use sempre que o usuário pedir 'enviar orçamento', 'mandar OS', 'enviar para o cliente' etc. PADRÃO (formato='pdf', ou sem formato): SÓ o ARQUIVO PDF, igual ao botão Baixar — com custom_message, a frase do usuário é a legenda inteira; sem ela, vai a legenda padrão 'Segue o ORÇ-00123, conforme solicitado. Qualquer dúvida, estamos à disposição.'; com sem_legenda=true (o usuário pediu 'só o arquivo', 'sem legenda', 'sem texto'), vai sem texto. formato='pdf_e_link' acrescenta na legenda o número, o total e o link para ver online e aprovar — use SÓ quando o usuário pedir o link ou o total junto ('com o link', 'para ele aprovar online'). formato='resumo' manda os VALORES EM TEXTO, sem PDF nem link: total, sinal para iniciar, chave PIX/banco e o saldo na conclusão, pela condição de pagamento do orçamento (o mesmo texto do botão 'Resumo' da tela) — use quando o usuário pedir 'manda os valores', 'o resumo', 'quanto ele paga de sinal'; com custom_message, a frase dele entra logo depois do cumprimento. formato='link' manda só o link, em texto — use apenas quando o usuário pedir 'só o link' ou quando o PDF falhar e ele aceitar. Vendedor externo só pode formato='link'. O campo service_order_id aceita TANTO o UUID (campo 'id' do list_service_orders) QUANTO o número do documento (ex: 'ORÇ-00001' para orçamentos, 'OS-00042' para OS, ou o formato antigo 'OS-2026-XXXXX'). Prefira sempre o UUID.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string", description: "UUID (campo id) ou número da OS (campo numero, ex: OS-2026-152542)" },
        formato: {
          type: "string",
          enum: ["pdf_e_link", "pdf", "resumo", "link"],
          description: "pdf (padrão) = só o arquivo (legenda = custom_message; sem ela, a frase padrão; com sem_legenda=true, nenhuma); pdf_e_link = arquivo com número, total e link na legenda, quando o usuário pedir o link; resumo = valores em texto (total, sinal, PIX, saldo), sem PDF nem link; link = só o link em texto, quando o usuário pedir.",
        },
        custom_message: { type: "string", description: "Mensagem personalizada. No formato link substitui o texto padrão (se não trouxer o link, ele vai no fim; até 4000 caracteres); no pdf_e_link vira a primeira linha da legenda (número, total e link vêm sempre; até 800 caracteres); no pdf é a legenda inteira — a frase que o dono quer junto do arquivo (até 1000 caracteres; sem ela, vai a frase padrão, ou nada com sem_legenda=true); no resumo entra logo depois do cumprimento (até 800)." },
        sem_legenda: { type: "boolean", description: "Só no formato pdf: true quando o usuário pedir o arquivo SEM texto ('só o arquivo', 'sem legenda', 'sem mensagem'). Sem isso e sem custom_message, vai a legenda padrão." },
        destino: {
          type: "string",
          enum: ["cliente", "parceiro"],
          description: "cliente (padrão) = o WhatsApp do cadastro do cliente, como sempre. parceiro = só quando o dono pedir o PDF à parceira (ex.: 'manda o pdf do 1 pra MP'): vai SÓ o PDF (formato 'pdf'), em via reduzida, ao número que o sistema escolhe pelo vínculo confirmado; nunca existe campo de telefone.",
        },
      },
      required: ["service_order_id"],
    },
    // Sempre envia pro cliente dono da OS — sempre cliente, nunca equipe. Sem computeRisk de
    // propósito: nenhum argumento torna isto "baixo risco", e o PDF nunca roda sem o "sim"
    // (ver NEVER_AUTONOMOUS_WHEN em autonomy-policy.ts).
    risk: "high",
    roles: NON_TECHNICIAN_ROLES,
    // Formato inexistente e PDF pedido por vendedor externo são recusados ANTES de a pendência
    // nascer: o sino não mostra "PDF anexado" para um pedido que o execute vai recusar.
    preValidar: (args, ctx) => validarPedidoDeEnvio(args, ctx),
    // A pendência grava quem pediu: o execute revalida o cargo DELE, não o de quem aprova.
    gravarSolicitante: true,
    // E o retrato do que foi aprovado (telefone e total): mudou até o "sim", não envia.
    // Retorno F4: com destino parceiro, o número que o banco devolve (parceiro_destino_do_pdf pede o autor).
    retratoDaPendencia: (args, ctx) => retratoDoEnvio(ctx.admin, args, ctx.userId),
    lerPendencia: lerPendenciaDoEnvio,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      // Antes de ler qualquer coisa: o PDF leva preço e PIX, e o vendedor externo não manda —
      // nem pela mão de um admin que aprove a pendência dele (validarPedidoDeEnvio).
      const recusado = validarPedidoDeEnvio(args, ctx);
      if (recusado) return recusado;
      // Retorno F4 (P12.2): ao parceiro, um caminho próprio, antes de ler o telefone do cliente. Sem destino (ou com outro
      // destino), daqui para baixo é o envio ao cliente de sempre, e a chave pdf_parceiro_ligado nem é lida.
      if (destinoDoEnvio(args) === "parceiro") return await enviarPdfAoParceiro(args, ctx);
      const formato = formatoDoEnvio(args)!;
      const { admin, jwt, appOrigin, settings } = ctx;
      const { data: so, error: soErr } = await buscarOrdemParaEnvio(admin, args.service_order_id);
      if (soErr || !so) return { error: `OS não encontrada. Verifique se o número ou ID está correto. Valor recebido: "${args.service_order_id}"` };
      if (so.status === "cancelled") {
        // Sem sugerir a tool de reabrir OS: ela reabre OS CONCLUÍDA/FATURADA e, no caminho,
        // cancela pagamentos e zera recebíveis — não é o caminho de uma ordem cancelada.
        return { error: frasesDaOrdemCancelada(so).erro };
      }
      // O número já traz o prefixo ("OS-00060", "ORÇ-00112"): vai como vem, sem "OS " na frente.
      if (!so.share_token) return { error: `A ${so.service_order_number} não possui link público ainda. Abra a OS no app, clique em "Compartilhar" para gerar o link, e tente novamente.` };
      // Destino: SÓ o cadastro do cliente da ordem. Nenhum telefone dos argumentos é lido —
      // é o que garante que o arquivo com preço e PIX vai para quem é dono do orçamento.
      const { data: c } = await admin.from("clients").select("whatsapp, phone, name, display_name, opt_out_whatsapp, generico").eq("id", so.client_id).maybeSingle();
      if (c?.opt_out_whatsapp) return { error: "Este cliente pediu para não receber mensagens no WhatsApp (opt-out)." };
      if (c?.generico) return { error: RECUSA_CLIENTE_FINAL, nada_enviado: true };
      const phone = c?.whatsapp || c?.phone;
      if (!phone) return { error: "Cliente sem WhatsApp/telefone cadastrado." };
      const origin = appOrigin || settings.app_public_url || "https://marineflow-erp.vercel.app";
      const link = `${origin}/view/${so.share_token}`;
      const nomeUsado = c?.display_name || (c?.name ? String(c.name).trim().split(/\s+/)[0] : "");
      // 'quote' só para orçamento: é o que deixa o whatsapp-send marcar 'sent' (e ele ainda
      // confere destino, modo de teste e status). OS vai como 'service_order' — só o vínculo.
      const contexto = documentTypeFor(so.status) === "quote" ? "quote" as const : "service_order" as const;
      const digitos = String(phone).replace(/\D/g, "");
      // O "sim" foi sobre o telefone e o total do resumo: se mudaram desde o pedido, não envia.
      const retrato = lerRetrato(args);
      const mudou = retrato ? oQueMudouDesdeOPedido(retrato, { digitos, total: so.grand_total }) : null;
      if (mudou) {
        return {
          error: `Desde o pedido, ${mudou}. Nada foi enviado ao cliente — peça de novo para confirmar com os dados de agora.`,
          nada_enviado: true,
        };
      }
      // Modo de teste: o whatsapp-send desvia o envio para o número de teste (e aí não marca o
      // orçamento como enviado). Entra nas chaves anti-duplicado: sem isso, o envio de teste
      // reservava a chave do CLIENTE e, desligado o modo no mesmo dia, o envio de verdade ouvia
      // "já foi enviado hoje" — sem o cliente ter recebido nada. Fora do desvio a parte some
      // (chaveDeEnvio descarta null) e a chave é a mesma de sempre.
      // A pergunta é "a edge VAI desviar?", não "o interruptor está ligado?": ligado sem número
      // de teste a edge manda ao cliente — a chave tem de ser a do cliente e o resultado não
      // pode dizer "foi para o teste". Por isso a mesma função da edge (marcar-enviado.ts).
      const modoTeste = desviadoPorTeste(settings);
      const marcaDeTeste = modoTeste ? "teste" : null;
      // Retorno F5 (P11.4): a data que o resumo do *sim* mostrou (retrato); o banco recusa ('mudou') se o dia virou.
      const esperada = typeof retrato?.validade === "string" ? retrato.validade : null;
      // (P11.9) o PDF do cartão do retorno chega ao whatsapp-send com orcamento_via "cartao"
      const viaDoOrcamento = ctx.envioPeloCartao === true ? { viaDoOrcamento: "cartao" as const } : {};

      if (formato === "link") {
        // (F5) o envio do orçamento conta os 7 dias em todo formato; no link, nenhuma linha (o portal mostra a data)
        const { doEnvio, ...validade } = await fixarValidadeDoEnvio(admin, so, ctx.validadeDoCartao, new Date(), { soRamoNovo: true, esperada });
        if (doEnvio?.motivo === "mudou") return { error: fraseDoDiaQueVirou(esperada, doEnvio.data), nada_enviado: true };
        const personalizada = typeof args.custom_message === "string" ? args.custom_message.trim() : "";
        const msg = personalizada
          ? mensagemComLink(personalizada, link, so.share_token)
          // "do orçamento ORÇ-00112" ou "da OS-00060": o número já diz o que é (nunca "da OS ORÇ-…")
          : `Olá${nomeUsado ? ` ${nomeUsado}` : ""}, segue o link ${contexto === "quote" ? `do orçamento ${so.service_order_number}` : `da ${so.service_order_number}`}: ${link}`;
        const g = guardaDeEnvio(msg, { tipo: "os_link", audiencia: "cliente", canal: "whatsapp", destinatarioIdentificado: !!so.client_id });
        if (g.bloqueado) {
          await registrarEnvio(admin, { tipo: "os_link", audiencia: "cliente", entityKind: "service_order", entityId: so.id, phone, preview: msg, status: "blocked", blockCode: g.codigoBloqueio });
          return { error: g.motivo };
        }
        const envio = await enviarOrdemAoCliente({
          phone,
          serviceOrderId: so.id,
          context: contexto,
          jwt,
          dedupeKey: chaveDeEnvio("os-link", so.id, digitos, diaLocal(), marcaDeTeste),
          sentBy: ctx.userId,
          conteudo: { kind: "text", message: msg },
          ...viaDoOrcamento,
        });
        // Mesmo formato de resposta de antes (sendWhatsapp), para o modelo ler igual.
        const r = !envio.ok
          ? { error: envio.error }
          : envio.deduplicated
          ? { ok: true, messageId: null, deduplicated: true, aviso: "Esta mesma mensagem já tinha sido enviada hoje para este número; não reenviei." }
          : { ok: true, messageId: envio.messageId ?? null };
        await registrarEnvio(admin, { tipo: "os_link", audiencia: "cliente", entityKind: "service_order", entityId: so.id, phone, preview: msg, status: envio.ok ? "sent" : "failed" });
        // (F5) só o aviso_validade, nunca doEnvio (que traz a legenda e o motivo)
        return { ...r, ...(g.avisos.length ? { avisos_estilo: g.avisos } : {}), ...validade };
      }

      // ── formato 'resumo': os valores em texto (05/10/2026) ─────────────────────────────
      if (formato === "resumo") {
        // (F5) a data do envio no texto ("⏳ Proposta válida até …"), a mesma do resumo do *sim* (opcoesDoResumo)
        const { doEnvio, ...validade } = await fixarValidadeDoEnvio(admin, so, ctx.validadeDoCartao, new Date(), { soRamoNovo: true, esperada });
        if (doEnvio?.motivo === "mudou") return { error: fraseDoDiaQueVirou(esperada, doEnvio.data), nada_enviado: true };
        const resumo = await montarResumoDeValores(admin, so, settings, opcoesDoResumo(doEnvio));
        if (!resumo.ok) {
          await registrarEnvio(admin, { tipo: "os_link", audiencia: "cliente", entityKind: "service_order", entityId: so.id, phone, preview: `[resumo] não montado: ${resumo.motivo}`, status: "failed" });
          return { error: `Não consegui montar o resumo de valores (${resumo.motivo}). Nada foi enviado ao cliente.`, nada_enviado: true };
        }
        const frase = typeof args.custom_message === "string" ? args.custom_message.trim() : "";
        const texto = resumoComFrase(resumo.texto, frase);
        const gr = guardaDeEnvio(texto, { tipo: "os_link", audiencia: "cliente", canal: "whatsapp", destinatarioIdentificado: !!so.client_id });
        if (gr.bloqueado) {
          await registrarEnvio(admin, { tipo: "os_link", audiencia: "cliente", entityKind: "service_order", entityId: so.id, phone, preview: `[resumo] ${texto}`, status: "blocked", blockCode: gr.codigoBloqueio });
          return { error: gr.motivo };
        }
        const envio = await enviarOrdemAoCliente({
          phone,
          serviceOrderId: so.id,
          context: contexto,
          jwt,
          // Mesmo texto para o mesmo número no mesmo dia sai uma vez só; mudou um valor, a chave muda.
          dedupeKey: chaveDeEnvio("os-resumo", so.id, digitos, diaLocal(), hashCurto(texto), marcaDeTeste),
          sentBy: ctx.userId,
          conteudo: { kind: "text", message: texto },
          ...viaDoOrcamento,
        });
        await registrarEnvio(admin, { tipo: "os_link", audiencia: "cliente", entityKind: "service_order", entityId: so.id, phone, preview: `[resumo] ${texto}`, status: envio.ok ? "sent" : "failed" });
        if (!envio.ok) return { error: `O WhatsApp não aceitou o resumo (${envio.error}). Nada foi confirmado como enviado.`, nada_enviado: !envio.semResposta, ...validade };
        if (envio.deduplicated) return { ok: true, deduplicated: true, aviso: `Este mesmo resumo (${resumo.rotulo} ${resumo.numero}) já foi enviado hoje para este cliente; não reenviei.`, ...validade };
        return {
          ok: true,
          formato: "resumo",
          enviado_para: modoTeste ? "o número de TESTE do WhatsApp (modo de teste ligado), não o cliente" : `o WhatsApp do cliente (${mascararTelefone(phone)})`,
          documento: `${resumo.rotulo} ${resumo.numero}`,
          observacao: modoTeste
            ? "O modo de teste do WhatsApp está ligado: o resumo foi para o número de teste, NÃO para o cliente. Diga isso."
            : "O cliente recebeu o resumo de valores em texto (total, sinal, saldo e como pagar).",
          ...(gr.avisos.length ? { avisos_estilo: gr.avisos } : {}),
          ...validade,
        };
      }

      // Retorno F3 (K6): a validade que sai no PDF é a do ENVIO. A data entra em quote_validity_date antes de montar, e o
      // montarDocumentoDaOrdem relê a ordem pelo id: `so` daqui em diante não usa os campos de validade.
      // Retorno F5 (P11.4): o ramo novo (sem origem e sem data do cartão) fixa hoje + 7 pelo banco e devolve a O21/O22.
      const { doEnvio, ...validade } = await fixarValidadeDoEnvio(admin, so, ctx.validadeDoCartao, new Date(), { esperada });
      if (doEnvio?.motivo === "mudou") return { error: fraseDoDiaQueVirou(esperada, doEnvio.data), nada_enviado: true };
      // ── formato 'pdf_e_link': o arquivo do Baixar, com o link na legenda ──────────────
      const montado = await montarDocumentoDaOrdem(admin, so, settings);
      if (!montado.ok) {
        await registrarEnvio(admin, { tipo: "os_link", audiencia: "cliente", entityKind: "service_order", entityId: so.id, phone, preview: `[${formato === "pdf" ? "pdf" : "pdf+link"}] não gerado: ${montado.motivo}`, status: "failed" });
        return anexoFalhou(montado.motivo);
      }
      const doc = montado.doc;
      const personalizada = typeof args.custom_message === "string" ? args.custom_message.trim() : "";
      const abertura = personalizada ||
        `Olá${nomeUsado ? ` ${nomeUsado}` : ""}, segue ${doc.tipoDoc === "quote" ? "o orçamento" : "a ordem de serviço"} em PDF.`;
      // pdf_e_link: número, total e link vêm SEMPRE, mesmo com mensagem personalizada — o dono
      // aprovou o envio vendo esses três no resumo. pdf: a legenda é só a frase dele (ou nada), e
      // o resumo da confirmação mostrou exatamente isso.
      // (F5) no pdf_e_link, a O22 logo depois da abertura, com a mesma regra do dd/mm da frase do dono
      const linhaDaValidade = doEnvio?.linha && doEnvio.data && !abertura.includes(ddmmDoDia(doEnvio.data)) ? `\n${doEnvio.linha}` : "";
      const legenda = formato === "pdf"
        ? legendaDoPdf(args, so, doEnvio)
        : `${abertura}${linhaDaValidade}\n\n${doc.rotulo} ${doc.numero} — Total ${doc.total}\nPara ver online e aprovar: ${link}`;
      const marca = formato === "pdf" ? "[pdf]" : "[pdf+link]";
      // O whatsapp-send recusa legenda acima de 1024 caracteres (zod). Melhor dizer agora do
      // que gerar o PDF e ouvir um 400.
      if (legenda.length > 1024) return { error: "A mensagem personalizada ficou longa demais para a legenda do PDF (limite do WhatsApp). Encurte e tente de novo." };
      // Portão de comunicação ANTES de gerar o arquivo: fora da janela 8h–20h não adianta renderizar.
      const g = guardaDeEnvio(legenda, { tipo: "os_link", audiencia: "cliente", canal: "whatsapp", destinatarioIdentificado: !!so.client_id });
      if (g.bloqueado) {
        await registrarEnvio(admin, { tipo: "os_link", audiencia: "cliente", entityKind: "service_order", entityId: so.id, phone, preview: `${marca} ${legenda}`, status: "blocked", blockCode: g.codigoBloqueio });
        return { error: g.motivo };
      }

      // Anti-duplicado pelo CONTEÚDO do documento, não por updated_at: o mesmo PDF para o mesmo
      // número no mesmo dia sai uma vez só (o laço do agente repetindo a tool depois de um
      // tempo esgotado não manda dois arquivos ao cliente). Mudou item, valor ou validade, o
      // conteúdo muda e o envio passa. O carimbo "Emitido em" fica fora da conta.
      const chave = chaveDeEnvio("os-pdf", so.id, digitos, diaLocal(), impressaoDigitalDoDocumento(doc.html), marcaDeTeste);
      const entrega = await guardarEEntregar({
        admin,
        doc,
        shareToken: so.share_token,
        baseUrl: settings.app_public_url || "",
        rotuloDoLog: "send_service_order_link",
        entregar: (url) =>
          enviarOrdemAoCliente({
            phone,
            serviceOrderId: so.id,
            context: contexto,
            jwt,
            dedupeKey: chave,
            sentBy: ctx.userId,
            conteudo: { kind: "document", url, filename: doc.nomeDoArquivo, caption: legenda },
            ...viaDoOrcamento,
          }),
      });
      if (!entrega.ok) {
        // Renderizar, guardar ou assinar falhou: `entregar` nem foi chamado — nada saiu.
        await registrarEnvio(admin, { tipo: "os_link", audiencia: "cliente", entityKind: "service_order", entityId: so.id, phone, preview: `${marca} não gerado: ${entrega.motivo}`, status: "failed" });
        return anexoFalhou(entrega.motivo);
      }
      const envio = entrega.valor;
      if (!envio.ok) {
        // Libera a chave SÓ quando não houve resposta definitiva (25 s esgotados, rede): a edge
        // reservou a chave antes de chamar a Evolution e, com a tool tendo desistido no meio, a
        // reserva ficaria de pé — o próximo pedido ouviria "já enviado" sem nada entregue. Um
        // PDF repetido ao cliente é o erro menor.
        // Com resposta definitiva, NÃO mexe: 400/401/500 a edge devolve ANTES de reservar — a
        // chave, se existe, é de um envio anterior JÁ CONCLUÍDO, e apagá-la abriria a porta
        // para mandar o mesmo PDF de novo; no 502 a própria edge já liberou.
        if (envio.semResposta) await liberarEnvio(admin, chave).catch(() => {});
        await registrarEnvio(admin, { tipo: "os_link", audiencia: "cliente", entityKind: "service_order", entityId: so.id, phone, preview: `${marca} ${legenda}`, status: "failed" });
        if (envio.semResposta) {
          return {
            error: `O WhatsApp não confirmou o envio do PDF (${envio.error}): pode ter chegado ou não. Confira a conversa do cliente antes de reenviar.`,
            orientacao:
              "Diga que o envio não foi confirmado. Antes de oferecer reenviar, confira a conversa do cliente (get_whatsapp_conversation) para ver se o PDF chegou; se não chegou, ofereça reenviar ou mandar só o link (formato='link') — os dois pedem nova confirmação.",
          };
        }
        return anexoFalhou(`o WhatsApp recusou o envio: ${envio.error}`);
      }
      const rotuloDoc = `${doc.rotulo} ${doc.numero}`;
      if (envio.deduplicated) {
        return { ok: true, deduplicated: true, aviso: `Este mesmo PDF (${rotuloDoc}) já foi enviado hoje para este cliente; não reenviei.`, destino_chave8: digitos.slice(-8), ...validade, ...(modoTeste ? { desviado_para_teste: true } : {}) };
      }
      await registrarEnvio(admin, { tipo: "os_link", audiencia: "cliente", entityKind: "service_order", entityId: so.id, phone, preview: `${marca} ${legenda}`, status: "sent" });
      // Modo de teste (calculado lá em cima): dizer "chegou ao cliente" seria fingir.
      // Sem URL e sem token no resultado: ele fica gravado no histórico do agente.
      return {
        ok: true,
        formato,
        enviado_para: modoTeste ? "o número de TESTE do WhatsApp (modo de teste ligado), não o cliente" : `o WhatsApp do cliente (${mascararTelefone(phone)})`,
        documento: rotuloDoc,
        cliente: doc.cliente,
        total: doc.total,
        arquivo: doc.nomeDoArquivo,
        observacao: modoTeste
          ? "O modo de teste do WhatsApp está ligado: o PDF foi para o número de teste, NÃO para o cliente. Diga isso."
          : formato === "pdf"
          ? (personalizada
            ? "O cliente recebeu o PDF com a sua frase na legenda (sem link)."
            : legenda
            ? `O cliente recebeu o PDF com a legenda padrão ("${legenda}"), sem link.`
            : "O cliente recebeu só o PDF, sem texto nem link.")
          : "O cliente recebeu o PDF com o link para ver online e aprovar.",
        ...(g.avisos.length ? { avisos_estilo: g.avisos } : {}),
        destino_chave8: digitos.slice(-8),
        ...validade,
        // Retorno F3: sem isto, o cartão diria "PDF enviado a Ana" e fecharia o caso com o PDF no número de teste.
        ...(modoTeste ? { desviado_para_teste: true } : {}),
      };
    },
  },
  {
    name: "schedule_whatsapp_message",
    description:
      "Agenda uma mensagem WhatsApp para OUTRA PESSOA em data/hora específica (horário de Brasília). Use para 'manda amanhã cedo para o Fulano', 'agenda para segunda às 9h'. 'Amanhã cedo' = 08:00. Só entre 8h e 20h. Destino: client_id (cliente do cadastro) OU phone (o número que o usuário disser, com DDD) + contact_name (o nome, quando a pessoa não está cadastrada — vira o nome da conversa no MarineFlow). Nunca invente número: sem número e sem cadastro, pergunte. Sempre pede a confirmação do usuário, que vê o nome, o número inteiro, o dia e a mensagem. Para envios com link de OS, informe service_order_id.",
    input_schema: {
      type: "object",
      properties: {
        phone: { type: "string", description: "WhatsApp do destinatário, como o usuário disser (ex.: '47 99915-9654'; o sistema completa o 55). Obrigatório se não informar client_id." },
        client_id: { type: "string", description: "UUID do cliente — busca o WhatsApp/telefone automaticamente." },
        contact_name: { type: "string", description: "Nome de quem vai receber, quando NÃO é cliente do cadastro (ex.: 'Carlos da Marina X'). Vira o nome da conversa no MarineFlow." },
        message: { type: "string", description: "Texto da mensagem a ser enviada." },
        scheduled_at: { type: "string", description: "Data e hora do envio, horário de Brasília (ex.: 2026-10-06T08:00). Entre 8h e 20h." },
        recurrence_type: { type: "string", enum: ["once", "daily", "weekly", "monthly"], description: "Recorrência do envio. Padrão: once." },
        service_order_id: { type: "string", description: "UUID ou número da OS para envio de link (send_mode=link)." },
        send_mode: { type: "string", enum: ["text", "link"], description: "Modo de envio. Padrão: text. Use 'link' para enviar o link público de uma OS." },
      },
      required: ["message", "scheduled_at"],
    },
    // "pior caso" para o filtro por cargo — client_id/service_order_id indicam cliente.
    risk: "high",
    roles: NON_TECHNICIAN_ROLES,
    computeRisk: (args) => (args?.client_id || args?.service_order_id ? "high" : "medium"),
    // Número, horário e mensagem conferidos ANTES da pendência (05/10/2026): o dono não aprova um
    // agendamento que vai falhar, nem um "08:00" que sairia às 05:00.
    preValidar: (args) => validarAgendamento(args),
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const invalido = validarAgendamento(args);
      if (invalido) return invalido;
      const { sb, admin, userId } = ctx;
      let phone = telefoneParaEnvio(args.phone);
      const clientId = args.client_id || null;

      if (clientId) {
        const { data: c } = await sb.from("clients").select("whatsapp, phone").eq("id", clientId).maybeSingle();
        phone = telefoneParaEnvio(c?.whatsapp || c?.phone) ?? phone;
      }
      if (!phone) return { error: "Telefone não informado ou inválido. Forneça o WhatsApp com DDD, ou o cliente do cadastro." };

      let soId: string | null = null;
      if (args.service_order_id) {
        const isUUID = UUID_RE.test(String(args.service_order_id));
        if (isUUID) {
          soId = args.service_order_id;
        } else {
          const { data: so } = await admin.from("service_orders").select("id").eq("service_order_number", args.service_order_id).maybeSingle();
          soId = so?.id || null;
        }
      }

      const hora = horarioDoAgendamento(args.scheduled_at);
      if ("error" in hora) return hora;
      const scheduledAt = hora.iso;
      const sendMode = args.send_mode || (soId ? "link" : "text");
      const recurrenceType = args.recurrence_type || "once";

      const { data: created, error: insErr } = await admin
        .from("whatsapp_scheduled_sends")
        .insert({
          phone,
          message: args.message,
          scheduled_at: scheduledAt,
          next_run_at: scheduledAt,
          recurrence_type: recurrenceType,
          send_mode: sendMode,
          target_kind: soId ? "service_order" : "manual",
          service_order_id: soId,
          client_id: clientId,
          status: "pending",
          created_by: userId,
          auto_retry: true,
          max_attempts: 3,
        })
        .select()
        .single();

      if (insErr) return { error: insErr.message };
      // Contato novo: o nome vai para a conversa do WhatsApp no MarineFlow (não cria cliente).
      // Número que já é de um cliente do cadastro (a confirmação disse "cliente do cadastro",
      // 15/10/2026): não ganha uma conversa com outro nome.
      const contato = !clientId && typeof args.contact_name === "string" &&
          (await destinoDoAgendamento(admin, { phone })).origem !== "cliente"
        ? await cadastrarContatoDoAgendamento(admin, phone, args.contact_name)
        : null;
      return {
        ok: true,
        scheduled_id: created.id,
        para: telefoneLegivel(phone),
        quando: `${quandoPorExtenso(created.scheduled_at)} (Brasília)`,
        recurrence_type: created.recurrence_type,
        message_preview: created.message.slice(0, 100),
        ...(contato === "criado" ? { contato: `Contato novo cadastrado no WhatsApp do MarineFlow: ${String(args.contact_name).trim()}` } : {}),
        ...(contato === "nomeado" ? { contato: `A conversa desse número passou a se chamar ${String(args.contact_name).trim()}` } : {}),
        orientacao: "Confirme ao usuário para quem, o número e o dia/hora por extenso (campo 'quando').",
      };
    },
  },
  {
    name: "list_scheduled_whatsapp",
    description: "Lista as mensagens WhatsApp agendadas. Pode filtrar por status.",
    input_schema: {
      type: "object",
      properties: {
        status: { type: "string", enum: ["pending", "sent", "failed", "cancelled", "all"], description: "Filtro de status. Padrão: pending." },
        limit: { type: "number", description: "Máximo de registros. Padrão: 10." },
      },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      const status = args.status || "pending";
      const limit = Math.min(Number(args.limit) || 10, 30);

      let q = admin
        .from("whatsapp_scheduled_sends")
        .select("id, phone, message, status, next_run_at, recurrence_type, send_mode, last_error, client_id")
        .order("next_run_at", { ascending: true })
        .limit(limit);

      if (status !== "all") q = q.eq("status", status);

      const { data, error } = await q;
      if (error) return { error: error.message };
      return { results: data, count: data?.length ?? 0 };
    },
  },
  {
    name: "cancel_scheduled_whatsapp",
    description: "Cancela um agendamento de WhatsApp pelo ID.",
    input_schema: {
      type: "object",
      properties: { scheduled_id: { type: "string", description: "UUID do agendamento a cancelar." } },
      required: ["scheduled_id"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      const { error } = await admin.from("whatsapp_scheduled_sends").update({ status: "cancelled" }).eq("id", args.scheduled_id);
      if (error) return { error: error.message };
      return { ok: true, cancelled_id: args.scheduled_id };
    },
  },
  {
    // ÚNICA tool de WhatsApp SEM restrição de cargo, e é de propósito.
    // Decisão do dono (10/08/2026): o técnico não dispara nem agenda WhatsApp pelo
    // assistente — as outras oito ganharam NON_TECHNICIAN_ROLES. Esta ficou de fora
    // porque não fala com ninguém: busca o telefone do PRÓPRIO solicitante em app_users
    // pelo ctx.userId e agenda para ele mesmo. Não aceita client_id nem telefone livre,
    // então não há caminho para chegar a um cliente. É ferramenta de trabalho pessoal.
    name: "schedule_self_reminder",
    description:
      "LEMBRETE PARA O PRÓPRIO USUÁRIO (a pessoa que está falando com você), NUNCA para um cliente. Use SEMPRE que o pedido for 'me lembre', 'me avise', 'lembrete pra mim', 'não me deixe esquecer', 'me cutuca amanhã' etc. Agenda uma mensagem de WhatsApp para o número do próprio solicitante. NÃO use client_id, NÃO use schedule_whatsapp_message, NÃO peça confirmação — é uma ação interna e segura.",
    input_schema: {
      type: "object",
      properties: {
        message: {
          type: "string",
          description: "O texto que a pessoa vai receber. Escreva claro e amigável, já com a lista de pendências que ela pediu para lembrar (uma por linha).",
        },
        delay_minutes: {
          type: "number",
          description: "Para lembretes RELATIVOS ('daqui a X minutos/horas'): minutos a partir de AGORA (ex.: 'daqui a 3 min' → 3; 'em 2 horas' → 120). Use este campo nesses casos e NÃO calcule horário absoluto. Com delay_minutes, pode omitir scheduled_at.",
        },
        scheduled_at: {
          type: "string",
          description: "Para horário ABSOLUTO ('amanhã 8h', 'hoje 15h'): data/hora ISO 8601 no horário de Brasília (ex: 2026-07-19T08:00:00 — pode omitir o fuso, o sistema assume Brasília). 'bem cedo'/'de manhã' → 07:00; 'amanhã' sem hora → 08:00. NÃO use para 'daqui a X' (use delay_minutes).",
        },
        recurrence_type: {
          type: "string",
          enum: ["once", "daily", "weekly", "monthly"],
          description: "Recorrência do lembrete. Padrão: once (uma vez).",
        },
      },
      required: ["message"],
    },
    risk: "low",
    async execute(args, { admin, userId }) {
      let when: Date;
      if (args.delay_minutes != null && Number(args.delay_minutes) > 0) {
        // Lembrete relativo: o servidor calcula "agora + X" (sem conta de fuso pelo modelo).
        when = new Date(Date.now() + Number(args.delay_minutes) * 60000);
      } else {
        const raw = String(args.scheduled_at || "").trim();
        // Horário absoluto sem fuso (naive) → interpreta como Brasília (-03:00), não UTC.
        const hasTz = /[zZ]$|[+-]\d{2}:?\d{2}$/.test(raw);
        when = new Date(hasTz || !raw ? raw : `${raw}-03:00`);
      }
      if (isNaN(when.getTime())) return { error: "Data/hora do lembrete inválida. Informe delay_minutes (relativo) ou scheduled_at (absoluto)." };
      // Rede de segurança: se caiu no passado (ex.: erro de fuso), joga 1 min à frente em vez
      // de disparar imediatamente.
      if (when.getTime() < Date.now() - 30000) when = new Date(Date.now() + 60000);
      const { data: u } = await admin.from("app_users").select("phone_normalized, full_name").eq("id", userId).maybeSingle();
      const phone = (u?.phone_normalized || "").replace(/\D/g, "");
      if (!phone) {
        return { error: "Você ainda não tem um número de WhatsApp cadastrado para receber lembretes. Cadastre em Configurações → Usuários (aba IA/Zap)." };
      }
      // Envelope padronizado do lembrete (com nome, se houver) — evita mensagem crua/genérica.
      const firstName = String(u?.full_name || "").trim().split(/\s+/)[0] || "";
      const reminderText = firstName
        ? `⏰ *Lembrete, ${firstName}!*\n\n${args.message}`
        : `⏰ *Lembrete!*\n\n${args.message}`;
      const scheduledAt = when.toISOString();
      const { data: created, error } = await admin
        .from("whatsapp_scheduled_sends")
        .insert({
          phone,
          message: reminderText,
          scheduled_at: scheduledAt,
          next_run_at: scheduledAt,
          recurrence_type: args.recurrence_type || "once",
          send_mode: "text",
          target_kind: "self_reminder",
          status: "pending",
          created_by: userId,
          auto_retry: true,
          max_attempts: 3,
        })
        .select("id, scheduled_at, recurrence_type")
        .single();
      if (error) return { error: error.message };
      return {
        ok: true,
        reminder_id: created.id,
        scheduled_at: created.scheduled_at,
        recurrence_type: created.recurrence_type,
        message_preview: args.message.slice(0, 120),
      };
    },
  },
  {
    name: "list_unanswered_messages",
    description:
      "CAIXA DE ENTRADA — mensagens recebidas ainda NÃO respondidas. Use quando perguntarem quem mandou mensagem, o que chegou, quem está esperando resposta, ou pedirem o resumo do WhatsApp. Retorna os contatos cuja última mensagem recebida veio DEPOIS da última resposta enviada, com nome, há quanto tempo chegou, quantas não lidas, se é cliente vinculado ou outro contato, e uma prévia. Só leitura.",
    input_schema: {
      type: "object",
      properties: {
        since_hours: { type: "number", description: "Opcional: considerar só mensagens recebidas nas últimas N horas (ex.: 24 = 'hoje', 48). Sem valor = todas as pendentes." },
        limit: { type: "number", description: "Máximo de contatos a retornar. Padrão 15, teto 30." },
      },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      const limit = Math.min(Math.max(Number(args.limit) || 15, 1), 30);
      const since = Number(args.since_hours) > 0
        ? new Date(Date.now() - Number(args.since_hours) * 3_600_000).toISOString()
        : null;
      // Fonte da verdade = whatsapp_messages (via RPC whatsapp_pending_inbox). NÃO usa o
      // cache whatsapp_leads, que pode congelar. Pendente = última entrada depois da
      // última saída, por telefone; exclui a equipe interna (IA no WhatsApp).
      const { data, error } = await admin.rpc("whatsapp_pending_inbox", { _since: since, _limit: limit });
      if (error) return { error: error.message };
      const rows = (data as any[]) || [];
      if (rows.length === 0) {
        return { ok: true, total: 0, pendentes: [], message: "Nenhuma mensagem pendente de resposta." };
      }
      const now = Date.now();
      // Retorno F4 (P12.4, linha 5): número confirmado de parceiro, com parceiro_historico_na_ia falso, sem a prévia; o
      // contato e a hora ficam (o dono sabe quem espera). Falha fecha.
      const fora = await chavesForaDoAssistente(admin);
      const pendentes = rows.map((r: any) => {
        const mins = Math.max(0, Math.round((now - new Date(r.last_inbound_at).getTime()) / 60000));
        const ha = mins < 60 ? `${mins} min` : mins < 1440 ? `${Math.round(mins / 60)} h` : `${Math.round(mins / 1440)} d`;
        return {
          contato: r.contato,
          tipo: r.is_client ? "cliente" : "contato",
          ha,
          recebida_em: r.last_inbound_at,
          nao_lidas: r.unread_count || 0,
          previa: foraDoAssistente(fora, r.phone) ? null : prettyPreview(r.last_body),
        };
      });
      return { ok: true, total: pendentes.length, pendentes };
    },
  },
  {
    name: "mute_contact",
    description:
      "SILENCIAR um contato na caixa de entrada / digest de mensagens. Use quando o usuário disser 'não me avise sobre X', 'silenciar fulano', 'esse contato não é relevante', 'pode ignorar a [empresa]', 'para de me lembrar do fornecedor Y'. O contato para de aparecer em 'quem está esperando resposta'. Informe phone (só dígitos) OU name (parte do nome). Baixo risco.",
    input_schema: {
      type: "object",
      properties: {
        phone: { type: "string", description: "Telefone do contato (só dígitos, DDI+DDD). Opcional se informar o nome." },
        name: { type: "string", description: "Nome (ou parte) do contato. Opcional se informar o telefone." },
      },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      const phone = String(args.phone || "").replace(/\D/g, "");
      const name = String(args.name || "").trim();
      if (!phone && !name) return { error: "Diga o telefone ou o nome do contato a silenciar." };
      const nowIso = new Date().toISOString();
      if (phone) {
        const { data: existing } = await admin.from("whatsapp_leads").select("id, name, phone_normalized").eq("phone_normalized", phone);
        if (existing && existing.length > 0) {
          await admin.from("whatsapp_leads").update({ muted_at: nowIso }).in("id", existing.map((l: any) => l.id));
          return { ok: true, silenciados: existing.map((l: any) => l.name || l.phone_normalized) };
        }
        const { data: created, error } = await admin.from("whatsapp_leads")
          .insert({ phone_normalized: phone, name: name || null, status: "pending", muted_at: nowIso })
          .select("name, phone_normalized").single();
        if (error) return { error: error.message };
        return { ok: true, silenciados: [created.name || created.phone_normalized] };
      }
      const { data: matches } = await admin.from("whatsapp_leads").select("id, name, phone_normalized").ilike("name", `%${name}%`).limit(10);
      if (!matches || matches.length === 0) return { error: `Não encontrei nenhum contato com "${name}".` };
      if (matches.length > 1) {
        return { precisa_desambiguar: true, opcoes: matches.map((l: any) => ({ nome: l.name, phone: l.phone_normalized })), instrucao: "Pergunte ao usuário qual silenciar e chame de novo com o phone específico." };
      }
      await admin.from("whatsapp_leads").update({ muted_at: nowIso }).eq("id", matches[0].id);
      return { ok: true, silenciados: [matches[0].name || matches[0].phone_normalized] };
    },
  },
  {
    name: "unmute_contact",
    description:
      "REATIVAR um contato silenciado (volta a aparecer na caixa de entrada / digest). Use quando o usuário disser 'volte a me avisar sobre X', 'reativar fulano', 'tirar do silêncio'. Informe phone OU name.",
    input_schema: {
      type: "object",
      properties: {
        phone: { type: "string", description: "Telefone do contato (só dígitos). Opcional se informar o nome." },
        name: { type: "string", description: "Nome (ou parte) do contato. Opcional se informar o telefone." },
      },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      const phone = String(args.phone || "").replace(/\D/g, "");
      const name = String(args.name || "").trim();
      if (!phone && !name) return { error: "Diga o telefone ou o nome do contato a reativar." };
      let q = admin.from("whatsapp_leads").select("id, name, phone_normalized").not("muted_at", "is", null);
      q = phone ? q.eq("phone_normalized", phone) : q.ilike("name", `%${name}%`);
      const { data: matches } = await q.limit(10);
      if (!matches || matches.length === 0) return { error: "Não encontrei contato silenciado com esse dado." };
      if (matches.length > 1) {
        return { precisa_desambiguar: true, opcoes: matches.map((l: any) => ({ nome: l.name, phone: l.phone_normalized })) };
      }
      await admin.from("whatsapp_leads").update({ muted_at: null }).eq("id", matches[0].id);
      return { ok: true, reativado: matches[0].name || matches[0].phone_normalized };
    },
  },
  {
    name: "link_whatsapp_lead_to_client",
    description:
      "VINCULAR um contato/lead do WhatsApp a um cliente cadastrado, para as mensagens dele passarem a aparecer no histórico do cliente. Use quando o usuário disser 'esse número é do fulano', 'liga esse contato ao cliente X', 'o lead tal é o cliente Y'. Informe o lead (telefone ou nome) e o cliente (id ou nome). Não cria cliente novo: se o cliente não existir, diga isso.",
    input_schema: {
      type: "object",
      properties: {
        phone: { type: "string", description: "Telefone do contato (só dígitos, DDI+DDD). Opcional se informar lead_name." },
        lead_name: { type: "string", description: "Nome (ou parte) do contato na caixa de entrada. Opcional se informar phone." },
        client_id: { type: "string", description: "Id do cliente. Opcional se informar client_name." },
        client_name: { type: "string", description: "Nome (ou parte) do cliente cadastrado. Opcional se informar client_id." },
      },
    },
    risk: "medium",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      const phone = String(args.phone || "").replace(/\D/g, "");
      const leadName = String(args.lead_name || "").trim();
      const clientId = String(args.client_id || "").trim();
      const clientName = String(args.client_name || "").trim();
      if (!phone && !leadName) return { error: "Diga o telefone ou o nome do contato a vincular." };
      if (!clientId && !clientName) return { error: "Diga o id ou o nome do cliente ao qual vincular." };

      let ql = admin.from("whatsapp_leads").select("id, name, phone_normalized, status, linked_client_id");
      ql = phone ? ql.eq("phone_normalized", phone) : ql.ilike("name", `%${leadName}%`);
      const { data: leads } = await ql.limit(10);
      if (!leads || leads.length === 0) return { error: "Não encontrei esse contato na caixa de entrada do WhatsApp." };
      if (leads.length > 1) {
        return { precisa_desambiguar: "contato", opcoes: leads.map((l: any) => ({ nome: l.name, phone: l.phone_normalized })) };
      }
      const lead = leads[0] as any;

      let qc = admin.from("clients").select("id, name, display_name, whatsapp, phone").eq("active", true);
      qc = UUID_RE.test(clientId) ? qc.eq("id", clientId) : qc.ilike("name", `%${clientName}%`);
      const { data: clientes } = await qc.limit(10);
      if (!clientes || clientes.length === 0) return { error: "Não encontrei esse cliente no cadastro. Se for cliente novo, cadastre antes de vincular." };
      if (clientes.length > 1) {
        return { precisa_desambiguar: "cliente", opcoes: clientes.map((c: any) => ({ id: c.id, nome: c.display_name || c.name })) };
      }
      const cliente = clientes[0] as any;

      if (lead.linked_client_id === cliente.id) {
        return { ok: true, ja_estava: true, contato: lead.name || lead.phone_normalized, cliente: cliente.display_name || cliente.name };
      }
      // Mesmo caminho da tela (useLinkLeadToClient): lead vira "linked" e as mensagens já
      // recebidas desse telefone passam a pertencer ao cliente.
      const { error: e1 } = await admin.from("whatsapp_leads")
        .update({ status: "linked", linked_client_id: cliente.id, updated_at: new Date().toISOString() })
        .eq("id", lead.id);
      if (e1) return { error: `Falha ao vincular: ${e1.message}` };
      const { count } = await admin.from("whatsapp_messages")
        .update({ client_id: cliente.id }, { count: "exact" })
        .eq("phone_normalized", lead.phone_normalized)
        .is("client_id", null);
      // Sem WhatsApp no cadastro, o telefone do contato vira o WhatsApp do cliente: é o que
      // faz o próximo envio ao cliente sair pelo número certo.
      if (!cliente.whatsapp && !cliente.phone) {
        await admin.from("clients").update({ whatsapp: lead.phone_normalized }).eq("id", cliente.id);
      }
      return {
        ok: true,
        contato: lead.name || lead.phone_normalized,
        cliente: cliente.display_name || cliente.name,
        mensagens_vinculadas: count ?? 0,
      };
    },
  },
];
