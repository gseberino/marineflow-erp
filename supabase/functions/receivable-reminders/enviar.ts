// Um lembrete de cobrança: envia e só marca "lembrete enviado" quando o provedor confirmou.
//
// Até 29/09/2026 a rotina chamava provider.sendText e não olhava a resposta. Só que o provedor
// não lança exceção quando o WhatsApp recusa: devolve { ok: false }. A rotina então gravava
// reminder_sent_at (o recebível nunca mais recebia lembrete), contava como "enviado" e deixava a
// reserva do dia presa. Mesma família do "Enviado" falso da tela (whatsapp-send, 29/09).
import type { SendResult, WhatsAppProvider } from "../_shared/whatsapp/types.ts";
import { concluirEnvio, liberarEnvio } from "../_shared/whatsapp/idempotencia.ts";

// deno-lint-ignore no-explicit-any
type DbClient = any;

export async function enviarLembrete(p: {
  admin: DbClient;
  provider: Pick<WhatsAppProvider, "sendText">;
  chave: string;
  phone: string;
  message: string;
  recebivelId: string;
}): Promise<{ ok: true } | { ok: false; erro: string }> {
  let resultado: SendResult;
  try {
    resultado = await p.provider.sendText(p.phone, p.message);
  } catch (e) {
    resultado = { ok: false, error: e instanceof Error ? e.message : String(e), retryable: true };
  }

  if (!resultado.ok) {
    // Não saiu: a chave volta a ficar livre e a próxima rodada tenta de novo.
    await liberarEnvio(p.admin, p.chave);
    return { ok: false, erro: resultado.error || "o WhatsApp não confirmou o envio" };
  }

  await concluirEnvio(p.admin, p.chave, resultado.providerMessageId || null);
  await p.admin.from("receivables").update({ reminder_sent_at: new Date().toISOString() }).eq("id", p.recebivelId);
  return { ok: true };
}
