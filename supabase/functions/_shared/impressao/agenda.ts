// As OS da Agenda de Produção que a impressão usa ("as vias de hoje", "minha via"). Arquivo pequeno de propósito: o
// resumo da manhã (ai-daily-briefing) só precisa contar, sem carregar o gerador de PDF.
//
// A mesma regra de pessoasDaOs (pdf/via-do-tecnico-dados.ts): alocação publicada ou fixada; reserva não conta.

// deno-lint-ignore no-explicit-any
type Admin = any;

/** Hoje em Brasília (aaaa-mm-dd). */
export function hojeNoEscritorio(agora: Date = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Sao_Paulo", year: "numeric", month: "2-digit", day: "2-digit" })
    .format(agora);
}

/** As OS da agenda de um dia, sem repetir. `payeeId` = só as da pessoa. Lança no erro de leitura. */
export async function osDaAgendaDoDia(admin: Admin, dia: string, payeeId?: string | null): Promise<string[]> {
  let q = admin.from("agenda_alocacoes").select("service_order_id")
    .eq("dia", dia).in("estado", ["publicada", "fixada"]).neq("tipo", "reserva");
  if (payeeId) q = q.eq("payee_id", payeeId);
  const { data, error } = await q;
  if (error) throw new Error(`não consegui ler a agenda (${error.message})`);
  return [...new Set(((data ?? []) as Array<{ service_order_id: string | null }>).map((a) => a.service_order_id).filter((x): x is string => !!x))];
}

/** O próximo dia de agenda da pessoa, de hoje em diante, com as OS dela nesse dia. Nada marcado = null. Lança no erro. */
export async function proximoDiaDaPessoa(admin: Admin, payeeId: string, agora: Date = new Date()): Promise<{ dia: string; os: string[] } | null> {
  const { data, error } = await admin.from("agenda_alocacoes").select("dia")
    .eq("payee_id", payeeId).in("estado", ["publicada", "fixada"]).neq("tipo", "reserva")
    .gte("dia", hojeNoEscritorio(agora)).order("dia", { ascending: true }).limit(1);
  if (error) throw new Error(`não consegui ler a agenda (${error.message})`);
  const dia = (data ?? [])[0]?.dia as string | undefined;
  if (!dia) return null;
  return { dia, os: await osDaAgendaDoDia(admin, dia, payeeId) };
}
