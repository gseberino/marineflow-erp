// Peças determinísticas do canal WhatsApp interno (Fase 4) — tudo aqui roda ANTES do
// LLM (custo $0) ou monta o texto que o LLM não precisa formatar. A orquestração do
// turno completo fica em ai-agent/index.ts (que já tem acesso a runAgentLoop,
// buildSystemBlocks etc.) — este módulo só as partes puras/testáveis isoladamente.

const APPROVE_WORDS = ["sim", "s", "ok", "confirmar", "1"];
const REJECT_WORDS = ["não", "nao", "n", "cancelar", "2"];

export type ConfirmationReply = { decision: "approve"; pin?: string } | { decision: "reject" };

/**
 * Reconhece uma resposta de confirmação/rejeição, com PIN opcional depois da palavra
 * ("sim 4321"). Retorna null se o texto não parece uma confirmação (segue pro LLM).
 */
export function parseConfirmationReply(text: string): ConfirmationReply | null {
  const parts = text.trim().toLowerCase().split(/\s+/);
  const first = parts[0] || "";
  if (APPROVE_WORDS.includes(first)) {
    const pinCandidate = parts[1];
    const pin = pinCandidate && /^\d{3,8}$/.test(pinCandidate) ? pinCandidate : undefined;
    return { decision: "approve", pin };
  }
  if (REJECT_WORDS.includes(first)) return { decision: "reject" };
  return null;
}

/** Reconhece a escolha de um número (1-indexed) dentro de uma lista de opções pendente. */
export function parseOptionReply(text: string, optionCount: number): number | null {
  const trimmed = text.trim();
  if (!/^\d+$/.test(trimmed)) return null;
  const n = parseInt(trimmed, 10);
  if (n < 1 || n > optionCount) return null;
  return n;
}

/** Monta o texto de lista numerada que o WhatsApp mostra em vez dos botões do painel. */
export function formatOptionsAsNumberedText(question: string, options: Array<{ label: string; value: string }>): string {
  const lines = options.map((o, i) => `${i + 1}) ${o.label}`);
  return `${question}\n${lines.join("\n")}`;
}

/** Mesma tradução usada pelo painel (use-ai-agent.ts selectOption) — UUID vira "label (id: valor)". */
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function resolveOptionAsUserText(option: { label: string; value: string }): string {
  if (option.value === "__refine__") return "Quero refinar a busca — me peça mais detalhes para encontrar o registro correto.";
  if (UUID_RE.test(option.value)) return `${option.label} (id: ${option.value})`;
  return option.label;
}

/** O rodapé que diz como responder a uma pendência — na proposta e na reapresentação. */
export function notaDeConfirmacao(risco: string | null | undefined): string {
  return risco === "high"
    ? "\n\nPara aprovar, responda: *sim <SEU PIN>*. Para rejeitar: *não*."
    : "\n\nResponda *sim* para aprovar ou *não* para rejeitar.";
}

/**
 * A pendência da conversa anterior que ainda espera resposta, para ir junto na conversa nova.
 *
 * POR QUE (27/09/2026): a conversa acaba com 4h sem mensagem, e a pendência vale 24h. O dono
 * respondeu "Nao" 18h depois de um pedido de envio ao cliente; a conversa nova nasceu sem a
 * pendência, o "Nao" foi para o modelo como frase solta e voltou "Tudo bem! Fico por aqui" —
 * com a pendência ainda aberta. Um "sim <PIN>" atrasado teria mandado o PIN ao modelo.
 *
 * Só a pendência VIVA (status pending e dentro do prazo) passa, com as tentativas de PIN já
 * gastas (esperar 4h não zera o limite de 3). `pendencia_herdada` avisa o turno de que ela não
 * foi apresentada nesta conversa: aprovação sem PIN a reapresenta em vez de executar
 * (decidirPendenciaHerdada).
 */
export async function pendenciaParaHerdar(
  // deno-lint-ignore no-explicit-any
  admin: any,
  metadataAnterior: Record<string, unknown> | null | undefined,
  agora: Date = new Date(),
): Promise<Record<string, unknown> | null> {
  const id = metadataAnterior?.pending_confirm_action_id;
  if (typeof id !== "string" || !id) return null;
  const { data: pendencia } = await admin
    .from("ai_operator_pending_actions")
    .select("id, status, expires_at")
    .eq("id", id)
    .maybeSingle();
  if (!pendencia || pendencia.status !== "pending") return null;
  if (pendencia.expires_at && new Date(pendencia.expires_at).getTime() <= agora.getTime()) return null;
  return {
    pending_confirm_action_id: id,
    pin_attempts: Number(metadataAnterior?.pin_attempts) || 0,
    pendencia_herdada: true,
  };
}

/**
 * A pendência desta conversa ainda espera resposta (status pending e dentro do prazo)? Devolve o
 * que o lembrete precisa mostrar; null = não há, ou já foi resolvida/expirou.
 *
 * POR QUE (05/10/2026): todo turno que passava pelo modelo e terminava em texto zerava
 * pending_confirm_action_id — mas a pendência continuava viva por 24h. O dono pediu o PDF do
 * ORÇ-00113 ao cliente (pendência criada), mandou "Sem o link, somente o pdf" (turno de texto: a
 * referência sumiu) e depois "Não": o "não" foi para o modelo, que disse que cancelaria — e não
 * havia como; o envio seguiu pendente.
 */
export async function pendenciaQueSegueEsperando(
  // deno-lint-ignore no-explicit-any
  admin: any,
  metadata: Record<string, unknown> | null | undefined,
  agora: Date = new Date(),
): Promise<{ title: string; risk_level: string | null } | null> {
  const id = metadata?.pending_confirm_action_id;
  if (typeof id !== "string" || !id) return null;
  const { data: pendencia } = await admin
    .from("ai_operator_pending_actions")
    .select("status, expires_at, title, risk_level")
    .eq("id", id)
    .maybeSingle();
  if (!pendencia || pendencia.status !== "pending") return null;
  if (pendencia.expires_at && new Date(pendencia.expires_at).getTime() <= agora.getTime()) return null;
  return { title: String(pendencia.title || "ação pendente"), risk_level: pendencia.risk_level ?? null };
}

/**
 * O que fazer com a resposta a uma pendência que veio da conversa anterior.
 *
 * Recusar é sempre seguro. Aprovar com PIN é intenção explícita. Aprovar SEM PIN ("sim", "ok",
 * "1") pode ser resposta a outra coisa — o resumo das 07:30 chega pelo mesmo número, e um "ok"
 * a ele não pode executar o pedido da noite anterior. Nesse caso a pendência é mostrada de
 * novo, com a hora do pedido, e a PRÓXIMA resposta decide.
 */
export function decidirPendenciaHerdada(resposta: ConfirmationReply): "resolver" | "reapresentar" {
  return resposta.decision === "approve" && !resposta.pin ? "reapresentar" : "resolver";
}

/** O texto da pendência mostrada de novo na conversa nova. */
export function textoDaPendenciaReapresentada(pendencia: {
  title: string;
  summary?: string | null;
  risk_level?: string | null;
  created_at?: string | null;
}): string {
  const quando = pendencia.created_at
    ? new Date(pendencia.created_at).toLocaleString("pt-BR", {
      timeZone: "America/Sao_Paulo", day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit",
    })
    : null;
  const cabecalho = quando ? `Este pedido de ${quando} ainda espera a sua resposta:` : "Este pedido ainda espera a sua resposta:";
  return `${cabecalho}\n⚠️ ${pendencia.title}\n${pendencia.summary ?? ""}${notaDeConfirmacao(pendencia.risk_level)}`;
}

/** Sessão de WhatsApp: reusa se ativa há menos de 4h, senão cria uma nova (levando a pendência viva). */
export async function resolveOrCreateWhatsAppSession(admin: any, phoneNormalized: string, appUserId: string): Promise<string> {
  const fourHoursAgoIso = new Date(Date.now() - 4 * 60 * 60 * 1000).toISOString();
  const { data: existing } = await admin
    .from("ai_operator_sessions")
    .select("id, last_activity_at, metadata")
    .eq("channel", "whatsapp")
    .eq("external_thread_key", phoneNormalized)
    .eq("status", "open")
    .order("last_activity_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (existing && existing.last_activity_at >= fourHoursAgoIso) return existing.id;

  // Best-effort: sem a herança a conversa nova nasce como sempre nasceu.
  let heranca: Record<string, unknown> | null = null;
  try {
    heranca = existing ? await pendenciaParaHerdar(admin, existing.metadata) : null;
  } catch { /* segue sem herdar */ }

  const { data: created, error } = await admin
    .from("ai_operator_sessions")
    .insert({
      channel: "whatsapp",
      channel_provider: "evolution",
      owner_user_id: appUserId,
      external_thread_key: phoneNormalized,
      status: "open",
      ...(heranca ? { metadata: heranca } : {}),
    })
    .select("id")
    .single();
  if (error || !created) throw new Error(`Falha ao criar sessão WhatsApp: ${error?.message || "erro desconhecido"}`);
  return created.id;
}

/** ~10 msgs/min por telefone, contadas em whatsapp_messages (mensagens inbound). */
export async function checkWhatsAppRateLimit(admin: any, phoneNormalized: string, maxPerMinute = 10): Promise<boolean> {
  const oneMinuteAgoIso = new Date(Date.now() - 60_000).toISOString();
  const { count } = await admin
    .from("whatsapp_messages")
    .select("*", { count: "exact", head: true })
    .eq("phone_normalized", phoneNormalized)
    .eq("direction", "inbound")
    .gte("occurred_at", oneMinuteAgoIso);
  return (count ?? 0) < maxPerMinute;
}

/**
 * Entrega a resposta da IA. Tenta ENVIO IMEDIATO via whatsapp-send (que aplica typing
 * delay/presence e test mode); se falhar, cai no whatsapp_send_queue (worker a cada ~1 min)
 * para não perder a mensagem. O envio direto elimina o atraso de até ~60s do tick do worker,
 * que era a maior parte da latência percebida na conversa.
 */
export async function queueWhatsAppReply(admin: any, phoneNormalized: string, message: string): Promise<void> {
  try {
    const url = `${Deno.env.get("SUPABASE_URL")}/functions/v1/whatsapp-send`;
    const res = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`,
      },
      body: JSON.stringify({ phone: phoneNormalized, message, kind: "text" }),
    });
    const body = await res.json().catch(() => ({}));
    if (res.ok && !(body as Record<string, unknown>)?.["error"]) return; // enviado na hora
  } catch (_e) {
    // rede/timeout — cai para a fila abaixo
  }
  // Fallback: enfileira (o worker reenvia em ~1 min) para garantir entrega.
  await admin.from("whatsapp_send_queue").insert({ phone_normalized: phoneNormalized, message, source: "ai_agent" });
}

/**
 * Uma pendência por conversa (05/10/2026): quando o turno cria uma pendência NOVA e a anterior
 * ainda esperava, a anterior é cancelada — senão ela ficava órfã por 24h (a conversa só guarda
 * uma referência), aprovável pelo sino do painel sem ninguém lembrar dela. Caso real: o dono
 * pediu o ORÇ-00113 "sem o link" depois de um pedido com link; o primeiro envio seguia vivo.
 * Devolve o aviso que vai junto da resposta ("" = nada foi cancelado).
 */
export async function cancelarPendenciaSubstituida(
  // deno-lint-ignore no-explicit-any
  admin: any,
  antes: Record<string, unknown>,
  depois: Record<string, unknown>,
  userId: string,
): Promise<string> {
  const velha = antes?.pending_confirm_action_id;
  const nova = depois?.pending_confirm_action_id;
  if (typeof velha !== "string" || !velha || !nova || velha === nova) return "";
  const { data } = await admin
    .from("ai_operator_pending_actions")
    .update({ status: "rejected", rejected_by_user_id: userId, rejected_at: new Date().toISOString() })
    .eq("id", velha)
    .eq("status", "pending")
    .select("title, action_name, session_id");
  // deno-lint-ignore no-explicit-any
  const p = (data as any[] | null)?.[0];
  if (!p) return "";
  await admin.from("ai_operator_audit").insert({
    session_id: p.session_id,
    pending_action_id: velha,
    actor_user_id: userId,
    actor_kind: "system",
    event_type: `superseded:${p.action_name}`,
    event_category: "data",
    payload: { channel: "whatsapp", substituida_por: nova },
  });
  return `

(O pedido anterior — ${p.title} — foi cancelado: vale só este.)`;
}
