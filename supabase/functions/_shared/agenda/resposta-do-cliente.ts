// Agenda de Produção, Fase 5 (P4, 27/10/2026): a mensagem do CLIENTE que chega pelo WhatsApp depois de uma mensagem da
// agenda (o SIM à confirmação, "pode ser sexta?", "não dá terça", "a chave fica com o marinheiro", "PARAR", o áudio). O
// whatsapp-webhook chama agenda_resposta_do_cliente DEPOIS da resposta da equipe e ANTES da confirmação de 30/09
// (registrar_confirmacao_do_cliente) e da conferência do recibo de diárias: quando o banco diz que a mensagem é da agenda
// ("consumiu"), as duas não leem o mesmo texto — o "ok" tem um dono só.
//
// Aqui só se LÊ a intenção (classificarRespostaDoCliente: sem IA, o extrator de datas da Fase 4); o banco decide tudo
// (spec-fase5 §5.4): o modo (agenda_config.modo_cliente desligado = nada; sombra = só registra e devolve consumiu false),
// quem é, a que mensagem responde, o SIM pela regra única de 30/09, o áudio que nunca confirma, a data convertida, o
// replano, o acesso, o opt-out e o que vai ao dono. Nada é enviado ao cliente.
//
// Nunca lança: erro = false (o webhook segue como hoje) e uma linha em app_error_logs; a função que ainda não existe (a
// migration 20261028100400 não aplicada) também é false, sem registro (seria uma linha por mensagem).

import { logEdgeError } from "../log-error.ts";
import { classificarRespostaDoCliente } from "../ai/comms/reply-router.ts";

// deno-lint-ignore no-explicit-any
type Cliente = any;

export const RPC_RESPOSTA_DO_CLIENTE = "agenda_resposta_do_cliente";
/** O banco guarda até isto do texto (agenda_cliente_respostas.texto); o leitor lê a mensagem inteira. */
export const RESPOSTA_DO_CLIENTE_MAX = 500;

/** O tipo da mensagem como o banco aceita (agenda_cliente_respostas.tipo_msg). */
export type TipoDaMensagem = "text" | "audio" | "image" | "document" | "video" | "outro";

export function tipoDaMensagem(t: string | null | undefined): TipoDaMensagem {
  return t === "text" || t === "audio" || t === "image" || t === "document" || t === "video" ? t : "outro";
}

/** A função ainda não existe no banco (PostgREST não acha, ou o Postgres não acha). */
function funcaoAusente(e: { code?: unknown; message?: unknown } | null | undefined): boolean {
  const code = String(e?.code ?? "");
  return code === "PGRST202" || code === "42883";
}

/**
 * A mensagem é a resposta do cliente a uma mensagem da agenda (e o banco já cuidou dela)? true = o webhook pula a
 * confirmação de 30/09 e a conferência do recibo. `messageId` = whatsapp_messages.id (a linha que o webhook gravou).
 * O áudio também vem (tipo "audio", corpo "[audio]"): o banco o leva ao dono. Nunca lança.
 */
export async function respostaDoCliente(
  admin: Cliente,
  p: { phone: string; body: string | null | undefined; messageId?: string | null; tipo?: string | null },
): Promise<boolean> {
  const texto = typeof p.body === "string" ? p.body : "";
  const tipo = tipoDaMensagem(p.tipo ?? "text");
  if (!p.phone || (tipo === "text" && !texto.trim())) return false;
  const leitura = tipo === "text"
    ? classificarRespostaDoCliente(texto)
    : { intencao: "outro" as const, expressao: null };
  try {
    const { data, error } = await admin.rpc(RPC_RESPOSTA_DO_CLIENTE, {
      p_phone: p.phone,
      p_body: texto.slice(0, RESPOSTA_DO_CLIENTE_MAX),
      p_message_id: p.messageId ?? null,
      p_tipo_msg: tipo,
      p_intencao: leitura.intencao,
      p_expressao: leitura.expressao,
    });
    if (error) {
      if (funcaoAusente(error)) return false;
      throw error;
    }
    return !!data && typeof data === "object" && (data as { consumiu?: unknown }).consumiu === true;
  } catch (e) {
    await logEdgeError(admin, {
      context: "whatsapp-webhook",
      action: "agenda:cliente",
      message: `resposta do cliente à agenda falhou (a mensagem seguiu como sempre): ${String((e as { message?: unknown })?.message ?? e)}`,
      details: { code: (e as { code?: unknown })?.code ?? null },
      error: e,
    });
    return false;
  }
}
