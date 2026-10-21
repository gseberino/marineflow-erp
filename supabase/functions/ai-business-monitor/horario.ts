// Horário, dia e textos do vigia do negócio (ai-business-monitor) — funções puras, testáveis sem banco.
//
// Até 15/10/2026 o vigia usava o dia UTC (`now.toISOString().slice(0, 10)`): às 21:05 de Brasília
// já é 00:05 UTC do dia seguinte, a chave `stale_quotes:<amanhã>` era nova e o aviso de orçamentos
// parados saía às 21:10, todo dia (ai_operator_alerts_log: 11, 12, 13 e 14/10 às 21:05). E não havia
// janela de horário: o "saldo do banco não bate" saía às 06:05. Agora o vigia só avisa das 8h às 20h
// de Brasília; o que aparecer fora disso espera a primeira rodada da manhã (08:05), já com a chave
// do dia certo.
import { diaBR } from "../_shared/pdf/datas.ts";

const FUSO = "America/Sao_Paulo";

/** Primeira hora (inclusive) e última hora (exclusive) em que o vigia avisa, em Brasília. */
export const PRIMEIRA_HORA = 8;
export const ULTIMA_HORA = 20;

// Minutos entre tentativas da fila e quantas cabem até as 20h: moram em _shared/uma-voz/janela.ts desde 20/10/2026
// (todo acorde da voz única que vai pela fila usa a mesma conta). Reexportados aqui para quem já os importava.
export { INTERVALO_DA_FILA_MIN, tentativasAteAs20h } from "../_shared/uma-voz/janela.ts";

/** Hora cheia (0–23) de Brasília no instante `agora`, em qualquer máquina. */
export function horaBrasilia(agora: Date): number {
  const h = new Intl.DateTimeFormat("en-US", { timeZone: FUSO, hour: "2-digit", hour12: false }).format(agora);
  return parseInt(h, 10) % 24;
}

/** Das 8h às 19h59 de Brasília. Fora disso o vigia não reivindica nem envia nada. */
export function podeAvisarAgora(agora: Date): boolean {
  const h = horaBrasilia(agora);
  return h >= PRIMEIRA_HORA && h < ULTIMA_HORA;
}

/** O dia (aaaa-mm-dd) que vai na chave do aviso e no "vence hoje": o de Brasília. */
export function diaDoAviso(agora: Date): string {
  return diaBR(agora);
}

/** Meia-noite de Brasília do dia de `agora`, em ISO (UTC). */
export function inicioDoDiaBR(agora: Date): string {
  return new Date(`${diaBR(agora)}T00:00:00-03:00`).toISOString();
}

/** Meia-noite de Brasília do dia 1º do mês de `agora`, em ISO (UTC). O Brasil não tem horário de verão desde 2019. */
export function inicioDoMesBR(agora: Date): string {
  return new Date(`${diaBR(agora).slice(0, 7)}-01T00:00:00-03:00`).toISOString();
}

/** O aviso de que o resumo da manhã não chegou. "como estão as coisas?" cai no panorama do assistente. */
export const TEXTO_RESUMO_NAO_CHEGOU =
  "☀️ O resumo das 07:30 de hoje não chegou: o WhatsApp ficou fora do ar. Escreva *como estão as coisas?* que eu mostro o principal agora.";

/**
 * (20/10/2026) A manhã que quebrou ANTES de entrar na fila (spec uma voz §1.7-1): o ai-daily-briefing caiu antes do
 * insert e não há linha nenhuma — o WhatsApp não tem culpa.
 */
export const TEXTO_MANHA_QUEBROU =
  "☀️ O resumo das 07:30 de hoje não chegou: deu um erro ao montá-lo. Escreva *como estão as coisas?* que eu mostro o principal agora.";

/** A partir de quando "nenhuma linha da manhã na fila" conta como "a manhã não chegou" (a 1ª rodada do vigia é 08:05). */
export const MANHA_SEM_LINHA_DESDE_MIN = 8 * 60;

/** Linha do resumo de hoje na fila (whatsapp_send_queue, source ai_briefing). */
export interface ResumoNaFila {
  phone_normalized: string | null;
  status: string | null;
}

/**
 * Telefones cujo resumo de hoje desistiu (failed) e que não têm outro resumo de hoje entregue ou
 * ainda a caminho (sent, pending, sending). Ordem estável (a da fila), sem repetir.
 */
export function telefonesSemResumo(linhas: ResumoNaFila[]): string[] {
  const cobertos = new Set<string>();
  for (const l of linhas) {
    if (l.phone_normalized && ["sent", "pending", "sending"].includes(String(l.status))) cobertos.add(l.phone_normalized);
  }
  const out: string[] = [];
  for (const l of linhas) {
    const p = l.phone_normalized;
    if (!p || l.status !== "failed" || cobertos.has(p) || out.includes(p)) continue;
    out.push(p);
  }
  return out;
}

/**
 * (20/10/2026) A manhã do dono quebrou antes de entrar na fila: já passou das 08:00 de Brasília e não existe NENHUMA
 * linha ai_briefing de hoje para o telefone dele (nem enviada, nem na fila, nem falhada — a falhada é o caso de
 * telefonesSemResumo, com o texto do WhatsApp fora). Sem telefone (dono não lido) = false.
 */
export function manhaSemLinha(linhas: ResumoNaFila[], phone: string | null | undefined, agora: Date): boolean {
  if (!phone) return false;
  const [h, m] = new Intl.DateTimeFormat("en-GB", { timeZone: FUSO, hour: "2-digit", minute: "2-digit", hour12: false })
    .format(agora).split(":").map((x) => parseInt(x, 10) % 24);
  if (h * 60 + m < MANHA_SEM_LINHA_DESDE_MIN) return false;
  return !linhas.some((l) => l.phone_normalized === phone);
}

/**
 * O resumo de hoje já cobre os orçamentos parados (ele lista os parados há 2 dias ou mais): foi
 * entregue ou ainda está na fila. Só então o aviso `stale_quotes` fica de fora.
 */
export function resumoDeHojeCobre(linhas: ResumoNaFila[]): boolean {
  return linhas.some((l) => ["sent", "pending", "sending"].includes(String(l.status)));
}
