// PLANO B da porta única de status (Agenda de Produção, revisão da Fase 2 — 24/10/2026).
//
// A tela (Vite, publicada pela Vercel a cada merge na main) e o check-in do assistente chamam os_transicionar_status, que
// nasce na migration 20261025100100. Se o código sair antes da migration, a chamada volta "a função não existe" e, sem
// isto, o "Agendar OS" gravava a data e dava erro (a OS deixava de passar a Agendada), a OC criada da OS deixava de pôr a
// OS em "Aguardando peças" e o check-in se perdia inteiro. Aqui: reconhecer a função ausente e voltar ao caminho de antes
// da porta, só nesse caso — qualquer outro erro continua erro.
//
// SAI quando a Fase 2 estiver aplicada em produção: src/test/porta-unica-status.test.ts congela este arquivo na lista dos
// que escrevem status por fora da porta (e cobra que a exceção saia junto quando ele deixar de escrever).
//
// Este arquivo não importa nada de propósito: a tela o carrega por caminho relativo (como agenda-modo.ts) e as Edge
// Functions (Deno) importam direto.

// deno-lint-ignore no-explicit-any
type Cliente = any;

/** O erro é "a função não existe" (PostgREST PGRST202: fora do cache do esquema; Postgres 42883: função indefinida)? */
export function ehPortaAusente(e: unknown): boolean {
  if (!e || typeof e !== "object") return false;
  const code = (e as { code?: unknown }).code;
  return code === "PGRST202" || code === "42883";
}

/** O erro é a recusa de quem pede da porta ("Você não pode mudar o status desta OS.", 42501)? */
export function ehSemDireitoNaPorta(e: unknown): boolean {
  return !!e && typeof e === "object" && (e as { code?: unknown }).code === "42501";
}

/**
 * O status como era antes da porta, só com a porta ausente: um UPDATE que só vale se a OS ainda está num dos status de
 * `de` (o mesmo filtro que os caminhos usavam). true = mudou. Erro sobe (nunca vira "não mudou" calado).
 */
export async function statusSemAPorta(db: Cliente, osId: string, para: string, de: readonly string[]): Promise<boolean> {
  const { data, error } = await db.from("service_orders").update({ status: para }).eq("id", osId).in("status", [...de]).select("id");
  if (error) throw error;
  return Array.isArray(data) && data.length > 0;
}
