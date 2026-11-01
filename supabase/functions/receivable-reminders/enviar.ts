// Um lembrete de cobrança: envia e só marca "lembrete enviado" quando o envio foi confirmado.
//
// Até 29/09/2026 a rotina chamava provider.sendText e não olhava a resposta. Só que o provedor
// não lança exceção quando o WhatsApp recusa: devolve { ok: false }. A rotina então gravava
// reminder_sent_at (o recebível nunca mais recebia lembrete), contava como "enviado" e deixava a
// reserva do dia presa. Mesma família do "Enviado" falso da tela (whatsapp-send, 29/09).
//
// Retorno F0a-1 (05/11/2026): o lembrete deixa de ir direto ao provedor e passa pelo whatsapp-send
// como envio automático (origem "sistema"). Ganha de uma vez o que faltava: entra na conversa, o
// opt-out e o "Cliente Final" recusam (canal_bloqueado), a janela de horário vale, a reserva sem
// banco não envia e a falha incerta não reenvia. A reserva da chave passa a ser do whatsapp-send.
// E não sai mais no domingo nem no feriado: o dia útil seguinte cobre o que caiu nele.

/** O "referente a …" da cobrança. A descrição do recebível vence; sem ela, o número da OS como vem
 * (já traz o prefixo: "OS-00060", "ORÇ-00112"), nunca "OS OS-00060"; sem os dois, "cobrança pendente". */
export function descricaoDaCobranca(
  descricao: string | null | undefined,
  numeroDaOs: string | null | undefined,
): string {
  return descricao || numeroDaOs || "cobrança pendente";
}

/** Soma dias a uma data YYYY-MM-DD (meio-dia UTC: sem surpresa de fuso nem de horário de verão). */
export function somarDias(dia: string, dias: number): string {
  const d = new Date(`${dia}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + dias);
  return d.toISOString().slice(0, 10);
}

/** Dias corridos de `de` até `ate` (YYYY-MM-DD). */
export function diasEntre(de: string, ate: string): number {
  return Math.round((Date.parse(`${ate}T12:00:00Z`) - Date.parse(`${de}T12:00:00Z`)) / 86_400_000);
}

/**
 * Vencimentos que este dia útil lembra: os que cairiam hoje e os que cairiam nos dias sem envio
 * desde o último dia útil (domingo, feriado). Sem dia pulado, é só o vencimento de hoje + N, como
 * antes. Ex.: N = 3, segunda depois de sábado útil → quarta e quinta.
 */
export function vencimentosDoDia(hoje: string, ultimoDiaUtil: string, diasAntes: number): { de: string; ate: string } {
  return { de: somarDias(ultimoDiaUtil, diasAntes + 1), ate: somarDias(hoje, diasAntes) };
}

/** "vence *hoje*", "vence *amanhã*" ou "vence em *N dias*". */
export function textoDoPrazo(dias: number): string {
  if (dias <= 0) return "vence *hoje*";
  if (dias === 1) return "vence *amanhã*";
  return `vence em *${dias} dias*`;
}

/** Resposta do whatsapp-send, como chega. */
export interface RespostaDoEnvio {
  status: number;
  // deno-lint-ignore no-explicit-any
  corpo: any;
}

export type ResultadoDoLembrete =
  | { situacao: "enviado" }
  | { situacao: "ja_enviado" }
  | { situacao: "recusado"; motivo: string }
  | { situacao: "erro"; erro: string };

// deno-lint-ignore no-explicit-any
type DbClient = any;

export async function enviarLembrete(p: {
  admin: DbClient;
  chamarEnvio: (corpo: Record<string, unknown>) => Promise<RespostaDoEnvio>;
  chave: string;
  phone: string;
  message: string;
  recebivelId: string;
  ordemId?: string | null;
}): Promise<ResultadoDoLembrete> {
  let resposta: RespostaDoEnvio;
  try {
    resposta = await p.chamarEnvio({
      phone: p.phone,
      kind: "text",
      message: p.message,
      receivable_id: p.recebivelId,
      ...(p.ordemId ? { service_order_id: p.ordemId } : {}),
      context: "receivable_reminder",
      dedupe_key: p.chave,
      origem: "sistema",
    });
  } catch (e) {
    return { situacao: "erro", erro: e instanceof Error ? e.message : String(e) };
  }

  const corpo = resposta.corpo ?? {};
  if (resposta.status >= 200 && resposta.status < 300 && corpo.success === true) {
    // "deduplicated" = a mesma chave já tinha saído (rodada anterior que não gravou a marca).
    await p.admin.from("receivables").update({ reminder_sent_at: new Date().toISOString() }).eq("id", p.recebivelId);
    return corpo.deduplicated ? { situacao: "ja_enviado" } : { situacao: "enviado" };
  }
  if (resposta.status === 422 && corpo.recusado === true) {
    return { situacao: "recusado", motivo: String(corpo.error ?? corpo.codigo ?? "recusado") };
  }
  return { situacao: "erro", erro: String(corpo.error ?? `HTTP ${resposta.status}`) };
}
