// Idempotência de envio de WhatsApp (caminho direto, edge whatsapp-send).
//
// Quem envia monta uma chave estável para "esta mensagem, para este destinatário, nesta
// ocasião" e a edge reserva a chave antes de chamar o provedor. Reserva repetida = já
// enviada = não envia de novo. Falha no provedor libera a reserva para a tentativa seguinte.
//
// A fila (whatsapp_send_queue) tem a própria proteção, por gatilho no banco; ver a migration
// 20260919120000_whatsapp_idempotencia_de_envio.sql.

// deno-lint-ignore no-explicit-any
type DbClient = any;

/** Hash curto e determinístico (djb2 em base 36). Serve para chave, não para segurança. */
export function hashCurto(texto: string): string {
  let h = 5381;
  for (let i = 0; i < texto.length; i++) {
    h = ((h << 5) + h + texto.charCodeAt(i)) | 0;
  }
  return (h >>> 0).toString(36);
}

/** Dia local (America/Sao_Paulo) no formato YYYY-MM-DD; escopo natural das chaves diárias. */
export function diaLocal(d: Date = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Sao_Paulo",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(d);
}

/** Junta partes com ':' descartando vazias; espaços viram '_' para a chave não ter surpresa. */
export function chaveDeEnvio(...partes: Array<string | number | null | undefined>): string {
  return partes
    .filter((p) => p !== null && p !== undefined && String(p).trim() !== "")
    .map((p) => String(p).trim().replace(/\s+/g, "_"))
    .join(":")
    .slice(0, 200);
}

export type ResultadoReserva = "nova" | "repetida" | "erro";

/**
 * Reserva a chave. "nova" = pode enviar; "repetida" = já foi enviada, não envie;
 * "erro" = banco indisponível — quem chama decide (a edge segue e envia: melhor um
 * duplicado raro do que uma cobrança que nunca sai).
 */
export async function reservarEnvio(
  admin: DbClient,
  chave: string,
  meta: { phone?: string; contexto?: string } = {},
): Promise<ResultadoReserva> {
  const { error } = await admin.from("whatsapp_send_idempotencia").insert({
    chave,
    phone_normalized: meta.phone ?? null,
    contexto: meta.contexto ?? null,
  });
  if (!error) return "nova";
  if (error.code === "23505") return "repetida";
  console.warn("[idempotencia] reserva falhou, seguindo sem proteção:", error.message);
  return "erro";
}

/** Libera a reserva quando o envio falhou, para a próxima tentativa passar. */
export async function liberarEnvio(admin: DbClient, chave: string): Promise<void> {
  await admin.from("whatsapp_send_idempotencia").delete().eq("chave", chave);
}

/** Registra o id do provedor na reserva (rastro) e apaga reservas com mais de 30 dias. */
export async function concluirEnvio(admin: DbClient, chave: string, providerMessageId?: string | null): Promise<void> {
  if (providerMessageId) {
    await admin.from("whatsapp_send_idempotencia").update({ provider_message_id: providerMessageId }).eq("chave", chave);
  }
  const limite = new Date(Date.now() - 30 * 24 * 3600 * 1000).toISOString();
  await admin.from("whatsapp_send_idempotencia").delete().lt("criado_em", limite);
}
