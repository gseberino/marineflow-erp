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
// Fase 3 (P3): também a mudança genérica de status da tela e a assinatura do cliente, que chamam a porta COMPLETA
// (20261026100100) — statusPelaTelaSemAPorta e argumentosDaPortaCompleta, no fim. Essa parte sai com a Fase 3 aplicada.
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

// ─── Fase 3 (P3, 24/10/2026): a mudança genérica de status pela tela e pela assinatura ─────────────────────────────
//
// A tela (useUpdateServiceOrderStatus), a assinatura do cliente (submit-signature) e o assistente (a conversão e o faturar
// de update_service_order_status) chamam a porta COMPLETA da Fase 3 — as vias 'tela' e 'assinatura', a conclusão com as
// cobranças, o faturar e a conversão nascem na migration 20261026100100. Para a chamada só achar essa porta, ela leva
// p_check_out (o 9º argumento, que só a da Fase 3 tem; vai null): com a porta da Fase 2 (8 argumentos, sem as vias
// novas) ou sem porta nenhuma, o PostgREST responde PGRST202 (ehPortaAusente) e o caminho de antes vale — em vez de a
// porta da Fase 2 recusar "Caminho desconhecido" e a tela inteira parar de mudar status. SAI quando a Fase 3 estiver
// aplicada em produção (junto com o resto deste arquivo).

/** Os argumentos da porta completa (a da Fase 3): p_check_out vai sempre, para a de 8 argumentos não servir. */
export function argumentosDaPortaCompleta(osId: string, para: string, via: string, extra: Record<string, unknown> = {}) {
  return { p_os: osId, p_para: para, p_via: via, p_check_out: null, ...extra };
}

export interface OpcoesDoCaminhoDeAntes {
  /**
   * As cobranças da conclusão do caminho de antes (a tela: ensureCompletionReceivables). Erro aqui não impede concluir —
   * era assim antes (o D7 que a porta corrige). Ausente = nenhuma cobrança (a assinatura de antes não lançava).
   */
  cobrancasDaConclusao?: (osId: string, dia: string) => Promise<unknown>;
  /** O relógio (testes). */
  agora?: () => Date;
}

export interface ResultadoDoCaminhoDeAntes {
  mudou: boolean;
  /** a 1ª saída do orçamento (o número troca só o prefixo: ORÇ-00042 → OS-00042) */
  convertido: boolean;
  numero: string | null;
  /** a linha da OS depois do UPDATE */
  linha: Record<string, unknown> | null;
}

/** AAAA-MM-DD no fuso de quem roda (a tela usava o dia do navegador). */
function diaLocal(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

/**
 * PLANO B da tela e da assinatura: o caminho de antes da porta (o de useUpdateServiceOrderStatus até a Fase 3), só com a
 * porta completa ausente. A conversão na 1ª saída do orçamento (converted_to_os_at, original_quote_amount e o número com
 * o prefixo trocado), o início ao passar a em andamento, a saída e as cobranças (opcoes.cobrancasDaConclusao) ao concluir,
 * e um UPDATE. Leitura ou UPDATE com erro = lança.
 */
export async function statusPelaTelaSemAPorta(
  db: Cliente,
  osId: string,
  para: string,
  opcoes: OpcoesDoCaminhoDeAntes = {},
): Promise<ResultadoDoCaminhoDeAntes> {
  const agora = (opcoes.agora ?? (() => new Date()))();
  const { data: atual, error: erroLeitura } = await db
    .from("service_orders")
    .select("status, converted_to_os_at, service_order_number, grand_total, original_quote_amount, check_in_at, check_out_at")
    .eq("id", osId)
    .maybeSingle();
  if (erroLeitura) throw erroLeitura;
  if (!atual) throw new Error("Não encontrei a OS.");

  const mudanca: Record<string, unknown> = { status: para };
  let convertido = false;
  let numero: string | null = atual.service_order_number ?? null;
  if (para !== "draft" && atual.status === "draft" && !atual.converted_to_os_at) {
    convertido = true;
    mudanca.converted_to_os_at = agora.toISOString();
    if (!atual.original_quote_amount && atual.grand_total) mudanca.original_quote_amount = atual.grand_total;
    numero = String(atual.service_order_number ?? "").startsWith("ORÇ-")
      ? String(atual.service_order_number).replace("ORÇ-", "OS-")
      : (atual.service_order_number ?? null);
    mudanca.service_order_number = numero;
  }
  if (para === "in_progress" && !atual.check_in_at) mudanca.check_in_at = agora.toISOString();
  if (para === "completed") {
    if (!atual.check_out_at) mudanca.check_out_at = agora.toISOString();
    if (opcoes.cobrancasDaConclusao) {
      try {
        await opcoes.cobrancasDaConclusao(osId, diaLocal(agora));
      } catch (e) {
        console.error("cobranças da conclusão (caminho de antes da porta) falharam", e);
      }
    }
  }
  const { data: linha, error } = await db.from("service_orders").update(mudanca).eq("id", osId).select().single();
  if (error) throw error;
  return { mudou: atual.status !== para || convertido, convertido, numero, linha: linha ?? null };
}
