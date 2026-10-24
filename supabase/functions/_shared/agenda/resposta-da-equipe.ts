// Agenda de Produção, Fase 3 (P4, 24/10/2026): a mensagem do técnico que chega pelo WhatsApp (o número dele não é login
// de administrador: o Roberto tem login inativo, o João nem tem). O whatsapp-webhook chama agenda_resposta_da_equipe
// ANTES da confirmação do cliente (registrar_confirmacao_do_cliente) e da conferência do recibo de diárias
// (registrar_conferencia_do_freelancer); quando o banco diz que a mensagem é da agenda ("consumiu"), as duas não leem o
// mesmo texto — o "ok" tem um dono só (NOVO-agenda-17: decide a última mensagem que o sistema mandou a ele).
//
// O banco decide tudo (spec-fase3 §7.4): o modo (agenda_config.modo_equipe desligado = nada; sombra = só registra e
// devolve consumiu false), quem é (o telefone da lista da rotina ou com diária vigente), a leitura sem IA e a resposta,
// que ele mesmo enfileira (com a janela e o teto). Aqui nada é enviado.
//
// Nunca lança: erro = false (o webhook segue como hoje) e uma linha em app_error_logs; a função que ainda não existe (a
// migration 20261026100300 não aplicada) também é false, sem registro (seria uma linha por mensagem).

import { logEdgeError } from "../log-error.ts";

// deno-lint-ignore no-explicit-any
type Cliente = any;

export const RPC_RESPOSTA_DA_EQUIPE = "agenda_resposta_da_equipe";
/** A mensagem maior que isto não é resposta à ficha (é conversa): nem vai ao banco. */
export const RESPOSTA_DA_EQUIPE_MAX = 500;

/** A função ainda não existe no banco (PostgREST não acha, ou o Postgres não acha). */
function funcaoAusente(e: { code?: unknown; message?: unknown } | null | undefined): boolean {
  const code = String(e?.code ?? "");
  return code === "PGRST202" || code === "42883";
}

/**
 * A mensagem é a resposta de alguém da equipe à agenda (e o banco já cuidou dela)? true = o webhook pula a confirmação do
 * cliente e a conferência do recibo. Nunca lança.
 */
export async function respostaDaEquipe(
  admin: Cliente,
  p: { phone: string; body: string | null | undefined; messageId?: string | null },
): Promise<boolean> {
  const texto = typeof p.body === "string" ? p.body : "";
  if (!texto.trim() || texto.trim().length > RESPOSTA_DA_EQUIPE_MAX || !p.phone) return false;
  try {
    const { data, error } = await admin.rpc(RPC_RESPOSTA_DA_EQUIPE, {
      p_phone: p.phone, p_body: texto, p_message_id: p.messageId ?? null,
    });
    if (error) {
      if (funcaoAusente(error)) return false;
      throw error;
    }
    return !!data && typeof data === "object" && (data as { consumiu?: unknown }).consumiu === true;
  } catch (e) {
    await logEdgeError(admin, {
      context: "whatsapp-webhook",
      action: "agenda:equipe",
      message: `resposta da equipe à agenda falhou (a mensagem seguiu como sempre): ${String((e as { message?: unknown })?.message ?? e)}`,
      details: { code: (e as { code?: unknown })?.code ?? null },
      error: e,
    });
    return false;
  }
}
