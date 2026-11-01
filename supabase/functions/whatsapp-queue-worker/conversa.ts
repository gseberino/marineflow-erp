// O envio da fila entra na conversa (Retorno rápido, F0b, 06/11/2026). A regra de quem entra e o
// formato da linha moram em _shared/whatsapp/registro-do-envio.ts; aqui, só a gravação.
//
// Nunca muda o desfecho do envio: a mensagem já saiu, e qualquer falha aqui vai só ao log. O
// 23505 (wa_message_id repetido) é o webhook que gravou o eco primeiro.
import { filaGravaNaConversa, linhaDaMensagemDaFila } from "../_shared/whatsapp/registro-do-envio.ts";
import type { ItemDaFila } from "./enviar.ts";

// deno-lint-ignore no-explicit-any
type DbClient = any;

/** O gravador de um lote: lê uma vez, no primeiro envio, quem conversa com o assistente. */
export function criarRegistroNaConversa(admin: DbClient): (item: ItemDaFila, providerMessageId: string | null) => Promise<void> {
  let doAssistente: Promise<Array<string | null>> | null = null;
  return async (item, providerMessageId) => {
    try {
      doAssistente ??= admin
        .from("app_users")
        .select("phone_normalized")
        .eq("ai_whatsapp_enabled", true)
        .not("phone_normalized", "is", null)
        .then(({ data, error }: { data: Array<{ phone_normalized: string | null }> | null; error: unknown }) => {
          if (error) throw error;
          return (data ?? []).map((u) => u.phone_normalized);
        });
      const telefonesDoAssistente = await doAssistente!;
      if (!filaGravaNaConversa({ fonte: item.source, telefone: item.phone_normalized, telefonesDoAssistente })) return;
      const { data: anterior } = await admin
        .from("whatsapp_messages")
        .select("client_id, lead_id, supplier_id")
        .eq("phone_normalized", item.phone_normalized)
        .or("client_id.not.is.null,lead_id.not.is.null,supplier_id.not.is.null")
        .order("occurred_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      const { error } = await admin.from("whatsapp_messages").insert(linhaDaMensagemDaFila(item, providerMessageId, anterior));
      if (error && error.code !== "23505") {
        console.warn(`[whatsapp-queue-worker] envio saiu, mas não entrou na conversa: ${error.code ?? ""} ${error.message ?? ""}`);
      }
    } catch (e) {
      // Sem saber quem fala com o assistente, não grava (a conversa com ele não é conversa com cliente).
      doAssistente = null;
      console.warn("[whatsapp-queue-worker] registro na conversa falhou:", e instanceof Error ? e.message : e);
    }
  };
}
