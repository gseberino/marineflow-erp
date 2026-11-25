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
import { diaBR } from "../agenda-dia.ts";
import { logEdgeError } from "../log-error.ts";
import { soAClasseDoErro } from "./classe-do-erro.ts";

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

// ═══ ROTINA DE IA QUE FALHA CALADA (pacote 1, V2, 24/11/2026) ═══
//
// De 12 a 24/11 a triagem de e-mail falhou em 95 e-mails (o provedor ficou sem saldo) e app_error_logs
// não ganhou nenhuma linha: o catch só escrevia o motivo no próprio e-mail. Rotina automática que chama
// o modelo e falha passa a registrar aqui, e a manhã das 07:30 lê a soma por rotina (secretario-coleta.ts,
// frase "IA que falhou desde ontem" da linha "Hoje"). Sem mensagem nova, sem tabela e sem migration.
//
// O mesmo truque do contexto, agora por DIA de Brasília: "rotina-ia:triagem_email@2026-11-24" abre uma
// linha por rotina e dia, e o `occurrences` dela é a contagem do dia. Se o texto do erro mudar em
// palavras, o dia ganha mais de uma linha; a soma por rotina continua certa.
//
// Só a CLASSE do erro vai para o registro (classe-do-erro.ts: "HTTP 402 (sem crédito)", "tempo esgotado"…),
// nunca a mensagem dele: o erro do provedor carrega o corpo da resposta, que pode devolver um trecho do
// e-mail ou da mensagem enviada para ler. Quem falha já classifica; aqui a frase é conferida de novo
// (soAClasseDoErro), e o que não for da lista fechada é gravado como "erro não classificado".
// Função sob pedido (botão, ferramenta do assistente) não registra aqui: o erro já aparece para quem pediu.

export type RotinaDeIA = "triagem_email" | "casar_fornecedor" | "detector_agenda" | "followup";

/** Como a rotina é dita ao dono na manhã. */
export const ROTULO_DA_ROTINA: Readonly<Record<RotinaDeIA, string>> = {
  triagem_email: "triagem de e-mail",
  casar_fornecedor: "leitura do prazo do fornecedor",
  detector_agenda: "detector da agenda",
  followup: "acompanhamento automático",
};

const PREFIXO_DA_ROTINA = "rotina-ia:";

/** O LIKE que acha (e tira da conta dos "erros registrados") as linhas das rotinas de IA. */
export const PADRAO_DO_CONTEXTO_DE_ROTINA = `${PREFIXO_DA_ROTINA}%`;

/** "rotina-ia:triagem_email@2026-11-24" (dia de Brasília): uma linha por rotina e dia em app_error_logs. */
export function contextoDaRotina(rotina: RotinaDeIA, agora: Date): string {
  return `${PREFIXO_DA_ROTINA}${rotina}@${diaBR(agora)}`;
}

/** A rotina de um contexto lido, ou null (contexto de outra coisa ou rotina que este código não conhece). */
export function rotinaDoContexto(contexto: unknown): RotinaDeIA | null {
  const m = /^rotina-ia:([a-z_]+)@\d{4}-\d{2}-\d{2}$/.exec(String(contexto ?? ""));
  return m && Object.hasOwn(ROTULO_DA_ROTINA, m[1]) ? m[1] as RotinaDeIA : null;
}

/**
 * Uma rotina automática de IA que falhou. Nunca lança (logEdgeError não lança); o chamador dá `await`
 * para o log sair antes de a função terminar.
 *
 * `mensagem` é a classe do erro (classeDoErro). O que vier fora da lista fechada é gravado como "erro não
 * classificado"; vazio, como "falha sem mensagem de erro" (logEdgeError descartaria a mensagem vazia, e a
 * falha sem texto ainda conta). Não há como passar o erro em si: a pilha dele começa pela mensagem, e
 * logEdgeError a gravaria nos detalhes.
 */
export async function registrarFalhaDeRotina(
  admin: Db,
  p: { rotina: RotinaDeIA; mensagem: string; agora?: Date },
): Promise<void> {
  await logEdgeError(admin, {
    context: contextoDaRotina(p.rotina, p.agora ?? new Date()),
    action: p.rotina,
    message: soAClasseDoErro(p.mensagem),
  });
}

/** Soma as ocorrências por rotina, na ordem de ROTULO_DA_ROTINA (puro). Contexto desconhecido não entra. */
export function somaPorRotina(
  linhas: Array<{ context?: string | null; occurrences?: number | null }> | null | undefined,
): Array<{ rotina: RotinaDeIA; vezes: number }> {
  const soma = new Map<RotinaDeIA, number>();
  for (const l of linhas ?? []) {
    const rotina = rotinaDoContexto(l?.context);
    if (!rotina) continue;
    soma.set(rotina, (soma.get(rotina) ?? 0) + (Number(l.occurrences) || 0));
  }
  return (Object.keys(ROTULO_DA_ROTINA) as RotinaDeIA[])
    .filter((r) => (soma.get(r) ?? 0) > 0)
    .map((r) => ({ rotina: r, vezes: soma.get(r)! }));
}

/**
 * As falhas por rotina nas linhas vistas desde `desde` (erro aberto), ou null quando a leitura falhou.
 * null não é "nenhuma": quem lê não conclui nada. A linha do dia entra inteira quando a última falha
 * dela caiu depois de `desde`.
 */
export async function falhasDeRotinaDesde(
  admin: Db,
  desde: Date,
): Promise<Array<{ rotina: RotinaDeIA; vezes: number }> | null> {
  try {
    const { data, error } = await admin
      .from("app_error_logs")
      .select("context, occurrences")
      .like("context", PADRAO_DO_CONTEXTO_DE_ROTINA)
      .eq("level", "error")
      .is("resolved_at", null)
      .gte("last_seen_at", desde.toISOString());
    if (error) return null;
    return somaPorRotina(data as Array<{ context?: string | null; occurrences?: number | null }> | null);
  } catch {
    return null;
  }
}
