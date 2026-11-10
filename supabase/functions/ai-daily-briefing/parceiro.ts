// O parceiro no fechamento das 17:30 (retorno rápido, F4, P11.2). Spec: retorno-rapido/f4/spec.md, P11.2 e C-FECH-P.
//
// O fechamento PEDE, não abre: nenhum cron abre o cartão do parceiro. Às 17:30 o painel `aguardando` já está na fila, e a
// tarde só escreve a linha ("Pátio da MP: 4 veículos, 2 mudaram · *parceiro* para liberar"). Quem abre é o dono, com
// *parceiro*. Por isso nada aqui chama RPC de cartão ou de envio.
//
// Tudo o que é dado vem do banco (parceiro_resumo_fechamento: só contagens e rótulos, sem nome de cliente e sem telefone).
// Aqui só se confere a forma: a linha que traz telefone ou e-mail sai (falha fecha), e o resto vai como veio. As linhas
// entram nos extras do fechamento (fixa = false): saem antes de tudo quando a tarde não cabe.
//
// Falha fecha: erro, função ausente (antes do deploy da F4) ou forma inesperada = null, e a tarde sai como antes. O erro
// (fora a função ausente) vai a app_error_logs (ai-daily-briefing, parceiro:fechamento), como lerRetorno. Nunca lança.
// Não importa nada de _shared/ai/.
//
// Reverter: tirar a chamada a lerParceiro de secretario-tarde.ts (o campo opcional some sozinho).

import { logEdgeError } from "../_shared/log-error.ts";

// deno-lint-ignore no-explicit-any
type Admin = any;

/** Quantas linhas do parceiro cabem no fechamento (são extras: as primeiras a sair). */
export const LINHAS_MAX_DO_PARCEIRO = 5;
const LINHA_MAX = 200;

const FUNCAO_AUSENTE = new Set(["PGRST202", "42883"]);

/** Telefone (8 dígitos ou mais, com ou sem separador) ou e-mail: a linha não sai. */
function temDadoDeContato(l: string): boolean {
  return /\d(?:[\s().-]*\d){7,}/.test(l) || /\S@\S/.test(l);
}

function linhasDe(data: unknown): string[] | null {
  if (data === null || data === undefined || typeof data !== "object" || Array.isArray(data)) return null;
  const linhas = (data as { linhas?: unknown }).linhas;
  if (linhas === null || linhas === undefined) return [];
  if (!Array.isArray(linhas)) return null;
  return linhas
    .filter((l): l is string => typeof l === "string")
    .map((l) => l.trim())
    .filter((l) => l !== "" && !l.includes("\n") && l.length <= LINHA_MAX && !temDadoDeContato(l))
    .slice(0, LINHAS_MAX_DO_PARCEIRO);
}

/**
 * parceiro_resumo_fechamento(p_agora) — contrato C-FECH-P. As linhas, já prontas; [] = nada do parceiro hoje; null =
 * erro, função ausente ou forma inesperada (a tarde de antes). Nunca lança.
 */
export async function lerParceiro(admin: Admin, agora: Date): Promise<string[] | null> {
  try {
    const { data, error } = await admin.rpc("parceiro_resumo_fechamento", { p_agora: agora.toISOString() });
    if (error) throw error;
    const linhas = linhasDe(data);
    // nulo é "nada a dizer" (como em lerRetorno); só a forma errada vai a app_error_logs
    if (linhas === null && data != null) {
      console.warn(JSON.stringify({ fn: "ai-daily-briefing", parceiro: "forma_inesperada" }));
      await logEdgeError(admin, {
        context: "ai-daily-briefing",
        action: "parceiro:fechamento",
        message: "parceiro: parceiro_resumo_fechamento devolveu uma forma inesperada; a linha do parceiro ficou de fora",
        details: { codigo: "forma_inesperada" },
      });
    }
    return linhas;
  } catch (e) {
    const codigo = String((e as { code?: unknown })?.code ?? (e as Error)?.name ?? "erro");
    console.warn(JSON.stringify({ fn: "ai-daily-briefing", parceiro: "leitura_falhou", codigo }));
    if (!FUNCAO_AUSENTE.has(codigo)) {
      await logEdgeError(admin, {
        context: "ai-daily-briefing",
        action: "parceiro:fechamento",
        message: `parceiro: a leitura de parceiro_resumo_fechamento falhou: ${String((e as { message?: unknown })?.message ?? codigo).slice(0, 300)}`,
        details: { codigo },
        error: e,
      });
    }
    return null;
  }
}
