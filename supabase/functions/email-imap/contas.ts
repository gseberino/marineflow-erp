// O que vence, fatia 1 (21/11/2026): o boleto lido no e-mail vira CONTA A PAGAR.
//
// Pedido do dono (21/11): controle do que vence. O e-mail já lia os boletos (dados.ts, por dígito verificador, sem IA),
// mas só informava; a conta a pagar só existia se alguém lançasse — e ninguém lançava (9 contas em aberto contra 1.829
// nascidas do extrato, depois de pagas). Decisão do dono: criar a conta sozinho ao ler o boleto. Nada é pago.
//
// Quem decide tudo é o banco (contas_a_pagar_do_email: liga à conta que já existe, não recria a cancelada, não cria o
// que parece pago nem o histórico). Aqui só se chama a RPC, no mesmo molde de remessas.ts:
//   · registrarContas(admin, id): depois do update de dados_extraidos (e no ?reextrair=1). NUNCA lança — a leitura do
//     e-mail não pode cair por causa do financeiro: o erro vai para app_error_logs (context email-imap, action
//     financeiro:contas-do-boleto). A função ausente (migration 20270221100000 ainda não aplicada) é silêncio.
//   · conta que a RPC não conseguiu criar (devolve barradas > 0 com o motivo) também vai para app_error_logs.

import { logEdgeError } from "../_shared/log-error.ts";
import type { BoletoDoEmail } from "../_shared/email/dados.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

export const RPC_CONTAS = "contas_a_pagar_do_email";

/** A função ainda não existe (a migration não foi aplicada): como antes, sem erro. */
function semAMigration(error: { code?: string } | null | undefined): boolean {
  return ["PGRST202", "42883"].includes(String(error?.code ?? ""));
}

/** Há boleto nos dados do e-mail? (só então a RPC é chamada) */
export function temBoleto(dados: { boletos?: BoletoDoEmail[] } | null | undefined): boolean {
  return (dados?.boletos ?? []).length > 0;
}

/**
 * A RPC das contas para um e-mail. Devolve o que ela devolveu ({criadas, ligadas, ja_existiam, ignoradas,
 * parecem_pagas, antigas, barradas, erros} ou {pulado: true}) ou null (função ausente, ou erro registrado). Nunca lança.
 */
export async function registrarContas(admin: Db, emailId: string): Promise<Record<string, unknown> | null> {
  try {
    const { data, error } = await admin.rpc(RPC_CONTAS, { p_email_message_id: emailId });
    if (error) {
      if (semAMigration(error)) return null;
      throw new Error(`${error.code ?? "?"}: ${error.message}`);
    }
    const r = (data ?? null) as Record<string, unknown> | null;
    if (r && Number(r.barradas ?? 0) > 0) {
      await logEdgeError(admin, {
        context: "email-imap", action: "financeiro:contas-do-boleto", level: "error",
        message: `${r.barradas} boleto(s) do e-mail ${emailId} não viraram conta a pagar: ${(Array.isArray(r.erros) ? r.erros : []).join(" | ")}`.slice(0, 500),
        details: { email_message_id: emailId, resultado: r },
      });
    }
    return r;
  } catch (e) {
    await logEdgeError(admin, {
      context: "email-imap", action: "financeiro:contas-do-boleto", level: "error",
      message: `conta a pagar do boleto do e-mail ${emailId} não registrada: ${(e as Error)?.message ?? e}`,
      details: { email_message_id: emailId }, error: e,
    });
    return null;
  }
}
