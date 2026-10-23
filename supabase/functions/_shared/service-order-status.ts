/**
 * Os status de `service_orders`, em um lugar só.
 *
 * ═══ POR QUE ISTO EXISTE ═══
 *
 * A auditoria encontrou a MESMA lista errada copiada em quatro lugares
 * (MF-AUD-005/006/007/008). Ela continha quatro status que o banco **rejeita**
 * — `pending`, `waiting_parts`, `waiting_approval`, `reopened` — e omitia
 * `open`, que é o status normal de uma OS aberta.
 *
 * O estrago não era teórico: o dropdown de agendamento da Agenda não mostrava
 * as OS em `open` (o dono via a lista vazia), e a visão "sem próxima ação" do
 * agente reportava menos OS descobertas do que existiam. O plano
 * `marineflow-contexto-vivo.md` chegou a corrigir a lista **no detector** em
 * 27/07 — e os outros três call sites ficaram, porque a correção foi pontual.
 *
 * Este arquivo mora em `_shared/` porque precisa ser alcançável pelos dois
 * lados: as Edge Functions importam direto, e o frontend importa por caminho
 * relativo (mesmo precedente de `_shared/banking/mcc.ts`, já usado em
 * `src/components/BankReconciliation.tsx`). Não depende de nada do Deno — são
 * constantes puras, de propósito, para poder atravessar essa fronteira.
 *
 * ⚠️ A fonte da verdade é o CHECK da tabela. `service-order-status_test.ts` lê a
 * migration mais recente que define `service_orders_status_check` e falha se
 * esta lista divergir. Ao mudar o CHECK, mude aqui — o teste cobra.
 */

/** Todos os valores aceitos por `service_orders.status` (espelha o CHECK). */
export const STATUS_OS = [
  "draft",
  "scheduled",
  "open",
  "in_progress",
  "awaiting_parts",
  "awaiting_client",
  "approved",
  "completed",
  "invoiced",
  "cancelled",
] as const;

export type StatusOS = (typeof STATUS_OS)[number];

/**
 * Trabalho em aberto: nem rascunho (ainda é orçamento), nem encerrado
 * (concluída/faturada/cancelada). É o recorte de "o que está acontecendo".
 */
export const STATUS_OS_ATIVAS: readonly StatusOS[] = [
  "approved",
  "scheduled",
  "open",
  "in_progress",
  "awaiting_parts",
  "awaiting_client",
] as const;

/**
 * O que pode receber agendamento. Inclui `draft` de propósito: um orçamento
 * recém-aprovado precisa aparecer no diálogo antes de virar OS. Exclui as
 * encerradas — reagendar OS concluída ou cancelada não faz sentido.
 */
export const STATUS_OS_AGENDAVEIS: readonly StatusOS[] = [
  "draft",
  "approved",
  "scheduled",
  "open",
  "in_progress",
  "awaiting_parts",
  "awaiting_client",
] as const;

/** Rótulos em pt-BR. Um por status, sem sobra e sem falta — o teste cobra os dois. */
export const ROTULOS_STATUS_OS: Record<StatusOS, string> = {
  draft: "Orçamento",
  scheduled: "Agendada",
  open: "Aberta",
  in_progress: "Em andamento",
  awaiting_parts: "Aguardando peças",
  awaiting_client: "Aguardando cliente",
  approved: "Aprovada",
  completed: "Concluída",
  invoiced: "Faturada",
  cancelled: "Cancelada",
};

/**
 * O que agendar faz com o status, para cada status. Um `Record` completo de propósito: um status
 * novo no CHECK não compila aqui até alguém decidir o que acontece com ele ao ganhar data.
 *
 *  · 'scheduled' → passa a agendada;
 *  · null        → a data é gravada e o status fica como está (nunca regride);
 *  · 'encerrada' → recusa: OS encerrada não se agenda.
 */
const AO_AGENDAR: Record<StatusOS, "scheduled" | null | "encerrada"> = {
  approved: "scheduled",
  open: "scheduled",
  // Já está.
  scheduled: null,
  // Orçamento ganha data sem virar OS. Exigir sinal pago antes de agendar (d08) é da Fase 2.
  draft: null,
  // Trabalho já andando: voltar para 'scheduled' apagaria o progresso.
  in_progress: null,
  awaiting_parts: null,
  awaiting_client: null,
  completed: "encerrada",
  invoiced: "encerrada",
  cancelled: "encerrada",
};

/**
 * O status que a OS passa a ter ao ganhar data. null = fica como está (nunca regride).
 *
 * É a regra única dos três caminhos que agendam — o diálogo "Agendar OS" da Agenda
 * (useQuickSchedule), a tool `schedule_service_order` e a macro `approve_quote_full` — e a
 * semente da porta única de status da Fase 2. Até 23/10/2026 cada caminho decidia sozinho: a
 * tela só passava a 'scheduled' a partir de 'pending' (status que não existe, então nunca), e o
 * assistente forçava 'scheduled' por cima de 'in_progress' e 'awaiting_parts'.
 *
 * O status NÃO depende de haver técnico: agendar sem responsável também vale.
 *
 * @throws Error "OS encerrada não se agenda" para concluída, faturada ou cancelada.
 */
export function statusAoAgendar(atual: string): StatusOS | null {
  const decisao = (AO_AGENDAR as Record<string, "scheduled" | null | "encerrada" | undefined>)[atual];
  if (decisao === "encerrada") {
    throw new Error(`OS encerrada não se agenda (${ROTULOS_STATUS_OS[atual as StatusOS]}).`);
  }
  // Status fora do CHECK não existe no banco; se aparecer, não inventa transição.
  return decisao ?? null;
}

/** Linha para o system prompt do agente, montada da mesma fonte. */
export function statusOsParaPrompt(): string {
  return STATUS_OS.map((s) => `${s}=${ROTULOS_STATUS_OS[s]}`).join(", ") + ".";
}
