// O status da OS depois da assinatura do cliente, pela porta única (Agenda de Produção, Fase 3, P3 — 24/10/2026).
//
// Até aqui submit-signature gravava o status configurado (app_settings.signature_status_after) no mesmo UPDATE da
// assinatura: com 'completed' a OS ficava concluída sem a saída e sem as cobranças da condição (NOVO-agenda-13); com
// 'approved' (o valor de produção) o orçamento ficava aprovado SEM converter — o número continuava ORÇ- e a tela nunca mais
// convertia (NOVO-agenda-23, a ORÇ-00070) — e uma OS em andamento voltava para aprovada. Agora a assinatura grava só os
// campos dela e o status vai pela porta (os_transicionar_status, via 'assinatura', sem autor, pela service_role): orçamento
// → aprovada converte trocando só o prefixo; em andamento não volta; concluir lança a saída e as cobranças.
//
// A assinatura é a prova do cliente e já está gravada quando isto roda: o status é consequência, não condição. A porta que
// recusa, o erro de banco ou a rede que cai viram uma linha em app_error_logs e a resposta segue com o status em que a OS
// ficou. PLANO B (_shared/porta-ausente.ts): sem a porta completa no banco (PGRST202/42883), o caminho de antes da porta.
import { argumentosDaPortaCompleta, ehPortaAusente, statusPelaTelaSemAPorta } from "../_shared/porta-ausente.ts";
import { logEdgeError } from "../_shared/log-error.ts";

// deno-lint-ignore no-explicit-any
type Cliente = any;

export interface StatusDepoisDaAssinatura {
  /** o status em que a OS ficou */
  status: string;
  mudou: boolean;
  /** a frase da porta (ou do que deu errado), para o registro */
  texto: string;
  /** por onde foi: a porta, o caminho de antes dela, ou nada (recusa/erro: o status ficou) */
  caminho: "porta" | "sem_a_porta" | "recusa" | "erro";
}

/**
 * Pede à porta o status configurado para depois da assinatura. Nunca lança: a assinatura já está gravada.
 * `statusAtual` é o que a OS tinha quando a assinatura chegou (vale quando nada muda).
 */
export async function statusDepoisDaAssinatura(
  admin: Cliente,
  os: { id: string; status: string; service_order_number?: string | null },
  para: string,
): Promise<StatusDepoisDaAssinatura> {
  try {
    const { data, error } = await admin.rpc("os_transicionar_status", argumentosDaPortaCompleta(os.id, para, "assinatura"));
    if (error) {
      if (!ehPortaAusente(error)) throw error;
      const antes = await statusPelaTelaSemAPorta(admin, os.id, para);
      return { status: para, mudou: antes.mudou, texto: "", caminho: "sem_a_porta" };
    }
    const r = (data ?? {}) as { ok?: boolean; mudou?: boolean; para?: string; texto?: string };
    const texto = String(r.texto ?? "");
    if (r.ok !== true) {
      await logEdgeError(admin, {
        context: "submit-signature",
        action: "status",
        level: "warn",
        message: `a porta não mudou o status da ${os.service_order_number ?? os.id} depois da assinatura: ${texto}`,
        details: { service_order_id: os.id, para, de: os.status },
      });
      return { status: os.status, mudou: false, texto, caminho: "recusa" };
    }
    return { status: String(r.para ?? os.status), mudou: r.mudou === true, texto, caminho: "porta" };
  } catch (e) {
    const err = e as { message?: unknown; code?: unknown };
    await logEdgeError(admin, {
      context: "submit-signature",
      action: "status",
      message: `o status da ${os.service_order_number ?? os.id} não mudou depois da assinatura: ${String(err?.message ?? e)}`,
      details: { service_order_id: os.id, para, de: os.status, code: err?.code ?? null },
      error: e,
    });
    return { status: os.status, mudou: false, texto: String(err?.message ?? e), caminho: "erro" };
  }
}
