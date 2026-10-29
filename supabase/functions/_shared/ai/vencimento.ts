// A linha que o vencimento deixa na conversa (aprovação em lote, Fase 1, 29/10/2026).
//
// POR QUE: a pendência vence em 24 h sem avisar ninguém (expire-pending-actions só marcava 'expired'). Em 90 dias foram 26
// vencidas, 24 delas itens de pedidos com várias ações que o dono nunca viu; e o assistente, sem saber, dizia depois
// "ainda espera o seu sim" sobre o que já tinha vencido. A linha entra em ai_operator_messages (source 'system'): o
// modelo lê na próxima conversa. O aviso no WhatsApp é da Fase 5 (decisão 9 do dono: só das 7h às 21h).
// Módulo sem imports de propósito: a edge expire-pending-actions o leva sem carregar o agente.

const LIMITE_DE_ITENS = 10;

function quando(iso: string | null | undefined): string {
  if (!iso) return "";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  return ` (pedido de ${d.toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo", day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" })})`;
}

/** O texto da linha para as pendências de UMA conversa que acabaram de vencer. "" = nada a dizer. */
export function textoDoVencimento(itens: Array<{ title?: string | null; created_at?: string | null }>): string {
  if (itens.length === 0) return "";
  const titulo = (t: { title?: string | null }) => String(t.title || "ação pendente").trim();
  if (itens.length === 1) return `⏰ Venceu sem resposta: *${titulo(itens[0])}*${quando(itens[0].created_at)}. Nada foi feito.`;
  const linhas = itens.slice(0, LIMITE_DE_ITENS).map((t) => `- *${titulo(t)}*${quando(t.created_at)}`);
  if (itens.length > LIMITE_DE_ITENS) linhas.push(`- e mais ${itens.length - LIMITE_DE_ITENS}`);
  return `⏰ Venceram sem resposta ${itens.length} pedidos (nada foi feito):\n${linhas.join("\n")}`;
}

/**
 * A conversa onde o modelo vai LER a linha. No WhatsApp a conversa nasce de novo depois de 4 h sem mensagem e a pendência
 * vale 24 h: quase toda vencida nasceu numa conversa que já foi trocada (revisão de 29/10/2026). Lá, a linha vai para a
 * conversa aberta mais recente do mesmo telefone — a mesma que resolveOrCreateWhatsAppSession escolhe. No painel, e em
 * qualquer dúvida, fica a conversa da pendência.
 */
// deno-lint-ignore no-explicit-any
export async function conversaOndeOModeloLe(admin: any, sessionId: string): Promise<string> {
  try {
    const { data: s } = await admin.from("ai_operator_sessions").select("id, channel, external_thread_key").eq("id", sessionId).maybeSingle();
    if (!s || s.channel !== "whatsapp" || !s.external_thread_key) return sessionId;
    const { data: atual } = await admin
      .from("ai_operator_sessions")
      .select("id")
      .eq("channel", "whatsapp")
      .eq("external_thread_key", s.external_thread_key)
      .eq("status", "open")
      .order("last_activity_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    return typeof atual?.id === "string" && atual.id ? atual.id : sessionId;
  } catch {
    return sessionId;
  }
}

/** Agrupa as vencidas por conversa (as sem sessão ficam de fora: não há conversa onde escrever). */
export function vencidasPorConversa<T extends { session_id?: string | null }>(vencidas: T[]): Map<string, T[]> {
  const porSessao = new Map<string, T[]>();
  for (const v of vencidas) {
    if (!v.session_id) continue;
    const lista = porSessao.get(v.session_id) ?? [];
    lista.push(v);
    porSessao.set(v.session_id, lista);
  }
  return porSessao;
}
