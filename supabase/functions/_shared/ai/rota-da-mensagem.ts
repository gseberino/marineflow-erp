// O rastro por mensagem recebida do dono (pacote 1, C4, 25/11/2026).
//
// ═══ POR QUE EXISTE ═══
//
// Medido em 24/11/2026: 28 de 623 mensagens do dono em 90 dias (7 de 278 em 30) não deixaram linha na
// conversa, pedido nem erro. O limite por minuto, as camadas do orçamento, do parceiro e do retorno, a trava
// do comprovante, o PIN solto na frase, a conversa dos comprovantes e o despacho que falha respondiam (ou
// calavam) sem pegada: não dava para dizer para onde uma mensagem tinha ido.
//
// ═══ O QUE GRAVA ═══
//
// Uma linha em ai_operator_audit por mensagem, com event_type "rota:<camada>" e actor_kind = event_category
// = "channel" (os dois CHECKs aceitam; conferido no catálogo em 25/11/2026). Sem tabela nova, sem migration.
// O turno que virou pedido para o Claude da assinatura ganha depois uma segunda linha, "rota:entrega", ligada
// pelo job_id (a entrega não sabe de qual mensagem veio; por isso ela vai sem mensagem_id).
//
// ═══ O QUE NUNCA GRAVA ═══
//
// O texto da mensagem, o telefone e o PIN. O payload só leva ids (mensagem_id, job_id), o canal, o tempo em
// ms e um `detalhe` que é rótulo: o comando que a camada reconheceu ("segura", "retorno"…), o código da causa
// de uma falha, o status HTTP. Todo detalhe passa por rotuloDaRota: frase, telefone e número com tamanho de
// PIN não passam e viram null. A chave `turno` não é usada: trabalhoNaAuditoria (pedido-do-turno.ts) filtra
// por ela para saber o que um pedido gravou, e uma rota com `turno` seria lida como trabalho do pedido.
//
// ═══ NUNCA DERRUBA NEM ATRASA ═══
//
// registrarRota nunca lança: a falha vai ao console só com o código do erro. No ai-agent a gravação roda no
// fundo (rastrearResposta, noFundoDaRota), fora do caminho da resposta.

// deno-lint-ignore no-explicit-any
type Db = any;

/**
 * As camadas em que uma mensagem pode parar. "em_espera", "resposta_antiga" e "espera_vencida" são do "um turno por
 * vez" (C1) e "aviso_demora" é do aviso de turno longo (C2-c): os dois foram adiados e nenhum código devolve essas
 * rotas ainda; os nomes ficam reservados aqui para o rastro não mudar quando eles chegarem.
 */
export const CAMADAS_DA_ROTA = [
  "limite_por_minuto", "nao_autorizado", "orcamento", "parceiro", "retorno", "trava_comprovante", "trava_agenda",
  "confirmacao", "pin_na_frase", "secretario", "agenda", "atalho_pdf", "modelo_max", "modelo_openrouter",
  "aviso_falha", "em_espera", "resposta_antiga", "comprovantes", "despacho_falhou", "entrega", "aviso_demora",
  "espera_vencida", "erro", "desconhecida",
] as const;

export type CamadaDaRota = typeof CAMADAS_DA_ROTA[number];

/** O prefixo do event_type. A tela de atividade tira estas linhas da lista dos últimos eventos (`rota:%`). */
export const PREFIXO_DA_ROTA = "rota:";

const RE_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
/** Começa por letra; depois só letra sem acento, dígito, "_", "-", "." e ":"; até 60 caracteres, sem espaço. */
const RE_ROTULO = /^[a-z][a-z0-9_.:-]{0,59}$/i;
/** 4 dígitos seguidos ou mais: o tamanho de um PIN (4 a 8) e o de um telefone. Status HTTP (3) passa. */
const RE_NUMERO_LONGO = /\d{4}/;

/**
 * Só rótulo passa (pura): "segura", "pessoal_desfaz", "aviso:login", "http_546". Frase (tem espaço ou acento),
 * número solto, telefone e qualquer coisa com 4 dígitos seguidos viram null. É a última conferência antes de gravar:
 * mesmo que uma camada um dia devolva texto no lugar do comando, o texto não entra no rastro.
 */
export function rotuloDaRota(v: unknown): string | null {
  if (typeof v !== "string") return null;
  return RE_ROTULO.test(v) && !RE_NUMERO_LONGO.test(v) ? v : null;
}

/** "aviso:login", "interrompido:timeout" (pura). Código fora do padrão de rótulo vira "outro". */
export function detalheComCodigo(prefixo: "aviso" | "interrompido", codigo: unknown): string {
  return `${prefixo}:${rotuloDaRota(codigo) ?? "outro"}`;
}

/**
 * O que a entrega do Claude da assinatura mandou ao dono, em rótulo (pura). A ordem é a de respostaDoTurnoNoWhatsApp:
 * a lista de opções vence o cartão, e o cartão vence o fluxo dos comprovantes. O turno que parou no meio diz o código.
 */
export function detalheDaEntrega(e: {
  interrompido?: boolean;
  codigo?: unknown;
  interrupcao?: { proposal?: unknown; options?: unknown; fluxo?: unknown } | null;
}): string {
  if (e.interrompido) return detalheComCodigo("interrompido", e.codigo);
  const i = e.interrupcao ?? {};
  if (i.options) return "lista";
  if (i.proposal) return "cartao";
  if (i.fluxo) return "fluxo";
  return "resposta";
}

const uuidOuNulo = (v: unknown): string | null => (typeof v === "string" && RE_UUID.test(v) ? v : null);
const presente = (v: unknown): boolean => v !== undefined && v !== null && v !== false && v !== "";

/**
 * Pura: lê o corpo e o status de verdade que o tratador do WhatsApp devolveu e diz em que camada a mensagem parou.
 * Só chaves e rótulos do corpo são lidos; nenhum texto de mensagem passa por aqui (o tratador não devolve texto).
 *
 * `claude_max` vem antes de `session_id` porque o turno que foi para a fila do Claude devolve os dois.
 */
export function rotaDaResposta(
  corpo: Record<string, unknown> | null | undefined,
  status: number,
): { camada: CamadaDaRota; detalhe: string | null; jobId: string | null } {
  const c: Record<string, unknown> = corpo && typeof corpo === "object" ? corpo : {};
  const rota = (camada: CamadaDaRota, detalhe: unknown = null, jobId: unknown = null) => ({
    camada, detalhe: rotuloDaRota(detalhe), jobId: uuidOuNulo(jobId),
  });

  if (c.skipped === "rate_limited") return rota("limite_por_minuto");
  if (status === 403) return rota("nao_autorizado");
  if (status >= 500) return rota("erro");

  if (presente(c.orcamento)) return rota("orcamento", c.orcamento);
  if (presente(c.parceiro)) return rota("parceiro", c.parceiro);
  if (presente(c.retorno)) return rota("retorno", c.retorno);
  if (c.travado === "comprovante") return rota("trava_comprovante");
  if (c.travado === "agenda") return rota("trava_agenda");
  if (presente(c.confirmacao)) return rota("confirmacao", c.confirmacao);
  if (c.pin_na_frase === true) return rota("pin_na_frase");
  if (presente(c.secretario)) return rota("secretario", c.secretario);
  if (presente(c.agenda)) return rota("agenda", c.agenda);
  if (presente(c.atalho)) return rota("atalho_pdf", c.atalho);
  // C1 (adiado): a mensagem segurada devolve a posição dela na espera
  if (c.em_espera !== undefined && c.em_espera !== null && c.em_espera !== false) {
    const posicao = Number(c.em_espera);
    return rota("em_espera", Number.isInteger(posicao) && posicao >= 0 && posicao < 1000 ? `posicao_${posicao}` : null);
  }
  if (c.espera === "resposta_antiga") return rota("resposta_antiga");
  if (c.entregue === "aviso") return rota("aviso_falha", c.causa);
  if (presente(c.claude_max)) return rota("modelo_max", null, c.claude_max);
  if (presente(c.session_id)) return rota("modelo_openrouter");
  return rota("desconhecida", status === 200 ? null : `http_${status}`);
}

/** Só o código do erro vai ao console: a mensagem do banco pode trazer a linha que falhou. */
function codigoDoErro(e: unknown): string {
  const codigo = (e as { code?: unknown } | null)?.code;
  if (typeof codigo === "string" && /^[A-Za-z0-9_]{1,20}$/.test(codigo)) return codigo;
  const nome = (e as { name?: unknown } | null)?.name;
  return typeof nome === "string" && /^[A-Za-z]{1,40}$/.test(nome) ? nome : "erro";
}

export interface RotaARegistrar {
  /** A conversa (ai_operator_sessions.id). null antes de a sessão existir (limite por minuto, webhook). */
  sessionId: string | null;
  /** whatsapp_messages.id da mensagem recebida. null na entrega (ligada pelo job) e em quem chama sem o id. */
  mensagemId: string | null;
  canal: "whatsapp";
  camada: CamadaDaRota;
  /** Rótulo: o comando da camada, o código da causa, o status. Nunca texto de mensagem (rotuloDaRota confere). */
  detalhe?: string | null;
  jobId?: string | null;
  /** Quanto o tratador levou, em milissegundos. */
  ms?: number | null;
  /** C1 (adiado): a mensagem saiu da espera. */
  daEspera?: boolean;
}

/** A linha que vai a ai_operator_audit (pura). Tudo conferido aqui: id que não é uuid, detalhe que não é rótulo e
 *  camada desconhecida não chegam ao banco como vieram. */
export function linhaDaRota(p: RotaARegistrar): {
  session_id: string | null;
  actor_kind: "channel";
  event_category: "channel";
  event_type: string;
  payload: Record<string, unknown>;
} {
  const camada: CamadaDaRota = (CAMADAS_DA_ROTA as readonly string[]).includes(p.camada) ? p.camada : "desconhecida";
  const ms = typeof p.ms === "number" && Number.isFinite(p.ms) && p.ms >= 0 ? Math.round(p.ms) : null;
  return {
    session_id: uuidOuNulo(p.sessionId),
    actor_kind: "channel",
    event_category: "channel",
    event_type: `${PREFIXO_DA_ROTA}${camada}`,
    payload: {
      mensagem_id: uuidOuNulo(p.mensagemId),
      canal: "whatsapp",
      detalhe: rotuloDaRota(p.detalhe),
      job_id: uuidOuNulo(p.jobId),
      ms,
      ...(p.daEspera === true ? { da_espera: true } : {}),
    },
  };
}

/**
 * Grava a rota. Nunca lança: banco fora, CHECK, rede — tudo vira uma linha no console com a camada e o código do
 * erro, sem o texto da mensagem (que nem chega aqui). Quem chama decide se espera: no ai-agent ela roda no fundo.
 */
export async function registrarRota(admin: Db, p: RotaARegistrar): Promise<void> {
  let evento = `${PREFIXO_DA_ROTA}desconhecida`;
  try {
    const linha = linhaDaRota(p);
    evento = linha.event_type;
    const { error } = await admin.from("ai_operator_audit").insert(linha);
    if (error) console.error(`[rota] ${evento} não foi gravada: ${codigoDoErro(error)}`);
  } catch (e) {
    console.error(`[rota] ${evento} não foi gravada: ${codigoDoErro(e)}`);
  }
}

/**
 * Fora do caminho da resposta: com EdgeRuntime.waitUntil a função só termina quando a gravação termina, e a resposta
 * não espera por ela; sem ele (teste, outro runtime) a promessa segue sozinha. Nunca lança, e a promessa que
 * rejeitasse não vira erro solto. O mesmo padrão do noFundo do whatsapp-webhook.
 */
export function noFundoDaRota(promessa: Promise<unknown>): void {
  const segura = Promise.resolve(promessa).catch(() => null);
  try {
    const runtime = (globalThis as { EdgeRuntime?: { waitUntil?: (p: Promise<unknown>) => unknown } }).EdgeRuntime;
    if (typeof runtime?.waitUntil === "function") runtime.waitUntil(segura);
  } catch {
    // sem waitUntil utilizável: a promessa já segue sozinha
  }
}

/**
 * A rota de uma resposta do tratador do WhatsApp: lida do que ele devolveu (rotaDaResposta) e gravada no fundo.
 * `res` null = o tratador lançou (rota "erro"). `status` é o status de verdade: o ai-agent responde sempre HTTP 200 e
 * guarda o status no cabeçalho X-Actual-Status, que quem chama lê.
 *
 * Síncrona e nunca lança. A cópia do corpo é tirada aqui, antes de a resposta sair (depois o corpo já foi lido por quem
 * envia); a leitura da cópia e a gravação seguem sem ninguém esperar. Sem conseguir a cópia, ou com corpo que não é
 * JSON, a linha sai do mesmo jeito, só pelo status.
 */
export function rastrearResposta(
  admin: Db,
  res: Response | null,
  p: { sessionId: string | null; mensagemId: string | null; ms?: number | null; status?: number },
): void {
  try {
    const base = { sessionId: p.sessionId, mensagemId: p.mensagemId, canal: "whatsapp" as const, ms: p.ms ?? null };
    if (!res) {
      noFundoDaRota(registrarRota(admin, { ...base, camada: "erro" }));
      return;
    }
    const status = typeof p.status === "number" && p.status > 0 ? p.status : res.status;
    let copia: Response | null = null;
    try {
      copia = res.clone();
    } catch {
      copia = null; // corpo já lido por alguém: não há o que copiar
    }
    noFundoDaRota((async () => {
      let corpo: Record<string, unknown> | null = null;
      try {
        corpo = copia ? await copia.json() : null;
      } catch {
        corpo = null;
      }
      await registrarRota(admin, { ...base, ...rotaDaResposta(corpo, status) });
    })());
  } catch (e) {
    console.error(`[rota] a resposta do turno não pôde ser lida: ${codigoDoErro(e)}`);
  }
}
