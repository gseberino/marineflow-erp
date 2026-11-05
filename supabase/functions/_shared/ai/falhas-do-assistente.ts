// As falhas do assistente, contadas por hora (Retorno rápido, F0a-2, 05/11/2026).
//
// ═══ POR QUE EXISTE ═══
//
// Em 28/10 a reserva do OpenRouter ficou sem crédito e ninguém soube: as falhas do ai-agent só iam
// para o console, e app_error_logs tinha 0 linhas dele. O vigia do negócio (ai-business-monitor, de
// hora em hora) precisa saber "o assistente falhou 3 vezes na última hora" para avisar o dono.
//
// ═══ POR QUE A HORA MORA NO CONTEXTO ═══
//
// log_app_error agrupa pela impressão digital (origem + contexto + texto sem os números) e só soma
// `occurrences`: contar linhas não diz quantas falhas houve, e a soma é de todo o tempo. O contexto
// entra na impressão digital sem normalização, então "ai-agent@2026-11-05T16" abre uma linha por
// hora, e o `occurrences` dela é a contagem daquela hora. Sem tabela nova e sem migration.
//
// A conta olha a hora corrente e a anterior: a janela real fica entre 1 e 2 horas, conforme o minuto
// e quando a última falha caiu. Basta para o aviso, que é de "continua falhando", não de auditoria.
import { logEdgeError } from "../log-error.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

/** A partir de quantas falhas na última hora o vigia avisa o dono. */
export const LIMITE_DE_FALHAS_NA_HORA = 3;

const UMA_HORA_MS = 60 * 60 * 1000;

/** "ai-agent@2026-11-05T16": a hora em UTC, para uma linha por hora em app_error_logs. */
export function contextoDaHora(agora: Date): string {
  return `ai-agent@${agora.toISOString().slice(0, 13)}`;
}

/** Os contextos que a conta lê: a hora corrente e a anterior. */
export function contextosDaUltimaHora(agora: Date): [string, string] {
  return [contextoDaHora(agora), contextoDaHora(new Date(agora.getTime() - UMA_HORA_MS))];
}

/**
 * Um turno do assistente que terminou sem resposta. Conta para o aviso do vigia. Nunca lança
 * (logEdgeError não lança); o chamador dá `await` para o log sair antes de a função terminar.
 */
export async function registrarFalhaDoAssistente(
  admin: Db,
  p: { onde: string; mensagem: string; erro?: unknown; agora?: Date },
): Promise<void> {
  await logEdgeError(admin, {
    context: contextoDaHora(p.agora ?? new Date()),
    action: p.onde,
    message: p.mensagem,
    error: p.erro,
  });
}

/** Soma as ocorrências das linhas lidas (puro). */
export function somaDeFalhas(linhas: Array<{ occurrences?: number | null }> | null | undefined): number {
  return (linhas ?? []).reduce((soma, l) => soma + (Number(l.occurrences) || 0), 0);
}

/**
 * Quantas falhas na última hora, ou null quando a leitura falhou. null não é "zero": quem lê não
 * conclui nada, nem que está tudo bem.
 */
export async function falhasNaUltimaHora(admin: Db, agora: Date): Promise<number | null> {
  try {
    const { data, error } = await admin
      .from("app_error_logs")
      .select("occurrences")
      .in("context", contextosDaUltimaHora(agora))
      .eq("level", "error")
      .is("resolved_at", null)
      .gte("last_seen_at", new Date(agora.getTime() - UMA_HORA_MS).toISOString());
    if (error) return null;
    return somaDeFalhas(data as Array<{ occurrences?: number | null }> | null);
  } catch {
    return null;
  }
}
