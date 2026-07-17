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

/** Sessão de WhatsApp: reusa se ativa há menos de 4h, senão cria uma nova. */
export async function resolveOrCreateWhatsAppSession(admin: any, phoneNormalized: string, appUserId: string): Promise<string> {
  const fourHoursAgoIso = new Date(Date.now() - 4 * 60 * 60 * 1000).toISOString();
  const { data: existing } = await admin
    .from("ai_operator_sessions")
    .select("id, last_activity_at")
    .eq("channel", "whatsapp")
    .eq("external_thread_key", phoneNormalized)
    .eq("status", "open")
    .order("last_activity_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (existing && existing.last_activity_at >= fourHoursAgoIso) return existing.id;

  const { data: created, error } = await admin
    .from("ai_operator_sessions")
    .insert({ channel: "whatsapp", channel_provider: "evolution", owner_user_id: appUserId, external_thread_key: phoneNormalized, status: "open" })
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
