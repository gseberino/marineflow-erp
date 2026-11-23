// O que vence, fatia 2 (22/11/2026): a conta com boleto conhecido é BAIXADA quando o banco mostra o pagamento.
//
// A exceção que o dono abriu em 22/11/2026 à regra dele de 26/09 ("ligar dinheiro a conta deve sempre questionar",
// _shared/banking/vinculo.ts): só no caso seguro — saída por boleto, valor igual no centavo, banco do boleto igual ao
// banco da saída, uma conta só (ou a parcela de vencimento mais próximo do mesmo fornecedor). Todo o resto continua
// sendo pergunta na fila.
//
// Quem decide tudo é o banco (baixar_pelo_boleto, migration 20270222100000). Aqui só se chama a RPC, na varredura,
// ANTES do "lançar sozinho" — para a saída que paga uma conta existente não virar despesa nova ao lado dela:
//   · baixarPeloBoleto(admin, reservadas): NUNCA lança — a varredura não pode cair por causa disto. O erro vai para
//     app_error_logs (context finance-review, action baixa-pelo-boleto). A função ausente (migration ainda não
//     aplicada) é silêncio, como antes.
//   · conta que a RPC não conseguiu baixar (barradas > 0, ex.: mês fechado) também vai para app_error_logs.
//   · as linhas reservadas da rodada (comprovante, anotação do dono) não entram: quem decide essas é o dono.

import { logEdgeError } from "../_shared/log-error.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

export const RPC_BAIXA = "baixar_pelo_boleto";

export interface BaixaPeloBoleto {
  /** Quantas contas foram baixadas nesta rodada. */
  baixadas: number;
  /** As linhas do banco que saíram da fila por isso. */
  transacoes: string[];
}

const NADA: BaixaPeloBoleto = { baixadas: 0, transacoes: [] };

/** A função ainda não existe (a migration não foi aplicada): como antes, sem erro. */
function semAMigration(error: { code?: string } | null | undefined): boolean {
  return ["PGRST202", "42883"].includes(String(error?.code ?? ""));
}

/** A RPC da baixa. Devolve o que foi baixado (zero em qualquer falha, já registrada). Nunca lança. */
export async function baixarPeloBoleto(admin: Db, reservadas: Iterable<string> = []): Promise<BaixaPeloBoleto> {
  try {
    const { data, error } = await admin.rpc(RPC_BAIXA, { p_exceto: [...new Set(reservadas)] });
    if (error) {
      if (semAMigration(error)) return NADA;
      throw new Error(`${error.code ?? "?"}: ${error.message}`);
    }
    const r = (data ?? {}) as Record<string, unknown>;
    if (Number(r.barradas ?? 0) > 0) {
      await logEdgeError(admin, {
        context: "finance-review", action: "baixa-pelo-boleto", level: "error",
        message: `${r.barradas} conta(s) com boleto não foram baixadas: ${(Array.isArray(r.erros) ? r.erros : []).join(" | ")}`.slice(0, 500),
        details: { resultado: r },
      });
    }
    const itens = Array.isArray(r.itens) ? r.itens as { transacao?: unknown }[] : [];
    return {
      baixadas: Number(r.baixadas ?? 0) || 0,
      transacoes: itens.map((i) => String(i?.transacao ?? "")).filter(Boolean),
    };
  } catch (e) {
    await logEdgeError(admin, {
      context: "finance-review", action: "baixa-pelo-boleto", level: "error",
      message: `baixa pelo boleto não rodou: ${(e as Error)?.message ?? e}`,
      error: e,
    });
    return NADA;
  }
}

/** A frase da varredura (vazia quando nada foi baixado). */
export function mensagemDaBaixa(baixadas: number): string {
  if (!(baixadas > 0)) return "";
  return baixadas === 1
    ? `1 conta baixada pelo boleto — veja em "Lançados sozinhos"`
    : `${baixadas} contas baixadas pelo boleto — veja em "Lançados sozinhos"`;
}
