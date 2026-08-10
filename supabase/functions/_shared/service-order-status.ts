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

/** Linha para o system prompt do agente, montada da mesma fonte. */
export function statusOsParaPrompt(): string {
  return STATUS_OS.map((s) => `${s}=${ROTULOS_STATUS_OS[s]}`).join(", ") + ".";
}
