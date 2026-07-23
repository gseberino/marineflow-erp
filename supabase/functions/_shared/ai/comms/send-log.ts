// Registro best-effort de cada envio externo — alimenta a CADÊNCIA (contar toques) e o
// LOOP DE APRENDIZADO (enviado × resposta). Nunca lança: falha aqui não pode derrubar o envio.

export interface RegistroEnvio {
  tipo: string; // cotacao|cobranca|os_link|follow_up
  audiencia?: string; // cliente|fornecedor
  entityKind?: string; // client|supplier|service_order|collection
  entityId?: string | null;
  phone?: string | null;
  preview?: string;
  status: "sent" | "blocked" | "failed";
  blockCode?: string;
}

export async function registrarEnvio(admin: any, r: RegistroEnvio): Promise<void> {
  try {
    await admin.from("ai_comms_log").insert({
      tipo: r.tipo,
      audiencia: r.audiencia ?? null,
      entity_kind: r.entityKind ?? null,
      entity_id: r.entityId ?? null,
      phone: r.phone ?? null,
      message_preview: (r.preview ?? "").slice(0, 300),
      status: r.status,
      block_code: r.blockCode ?? null,
    });
  } catch {
    // best-effort — silencioso
  }
}
