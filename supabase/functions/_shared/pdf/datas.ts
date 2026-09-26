/**
 * Datas do documento no calendário de Brasília, em qualquer máquina.
 *
 * ═══ POR QUE EXISTE ═══
 *
 * O documento formatava datas com `toLocaleDateString('pt-BR')` sem fuso: vale o relógio
 * de quem gera. No navegador do escritório isso é Brasília e passava despercebido. Na Edge
 * Function do assistente o relógio é UTC, três horas à frente — um orçamento criado às
 * 23h30 sairia "emitido" no dia seguinte, com a validade um dia mais longa.
 *
 * E havia um erro que a tela já cometia: coluna `date` do banco (`payments.payment_date`)
 * chega como 'aaaa-mm-dd'. Pela regra do JavaScript essa forma é meia-noite em UTC, e o
 * navegador em Brasília mostrava o DIA ANTERIOR — "Pago em 19/09" para um pagamento de
 * 20/09. Dia de calendário não tem fuso; aqui ele sai como está.
 *
 * São dois tipos de valor, tratados de dois jeitos:
 *   · dia de calendário ('aaaa-mm-dd')  → impresso como está, sem conversão;
 *   · instante (timestamptz, Date)      → convertido para o dia/hora de Brasília.
 */

const FUSO = 'America/Sao_Paulo';
const DIA_DE_CALENDARIO = /^(\d{4})-(\d{2})-(\d{2})$/;

/** dd/mm/aaaa. Dia de calendário sai como está; instante, no dia de Brasília. */
export function dataBR(valor: string | Date): string {
  if (typeof valor === 'string') {
    const m = DIA_DE_CALENDARIO.exec(valor.trim());
    if (m) return `${m[3]}/${m[2]}/${m[1]}`;
  }
  const d = typeof valor === 'string' ? new Date(valor) : valor;
  return d.toLocaleDateString('pt-BR', { timeZone: FUSO });
}

/**
 * O dia de calendário 'aaaa-mm-dd' contido em `valor`, se for um dia que existe; senão null.
 *
 * É o filtro da data fixa de validade (service_orders.quote_validity_date): o PDF imprime
 * "Válido até" com ela e a R19 avisa no dia seguinte a ela, então os dois precisam concordar
 * sobre o que é uma data. Aceita o começo de um timestamp ('2026-09-30T00:00:00'); recusa
 * vazio, texto solto e dia que não existe ('2026-02-31'), que `dataBR` imprimiria como está.
 */
export function diaDeCalendario(valor: unknown): string | null {
  if (typeof valor !== 'string') return null;
  const dia = valor.trim().slice(0, 10);
  const m = DIA_DE_CALENDARIO.exec(dia);
  if (!m) return null;
  const [ano, mes, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  const t = new Date(Date.UTC(ano, mes - 1, d));
  return t.getUTCFullYear() === ano && t.getUTCMonth() === mes - 1 && t.getUTCDate() === d ? dia : null;
}

/** hh:mm no horário de Brasília. */
export function horaBR(d: Date): string {
  return d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit', timeZone: FUSO });
}

/** "dd/mm/aaaa, hh:mm:ss" no horário de Brasília — o carimbo de "Emitido em". */
export function dataHoraBR(d: Date): string {
  return d.toLocaleString('pt-BR', { timeZone: FUSO });
}

/**
 * O dia de calendário de Brasília (aaaa-mm-dd) em que o instante `d` aconteceu.
 *
 * É o "hoje" de quem compara datas no servidor: a Edge Function roda em UTC, e entre 21h e
 * meia-noite de Brasília `toISOString().slice(0, 10)` já devolve o dia seguinte.
 */
export function diaBR(d: Date): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: FUSO, year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(d);
}

/** Dia de calendário ('aaaa-mm-dd') mais `dias`. Sem fuso nenhum: dia não tem hora. */
export function somarDiasAoDia(dia: string, dias: number): string {
  const [ano, mes, d] = String(dia).slice(0, 10).split('-').map(Number);
  return new Date(Date.UTC(ano, mes - 1, d + dias)).toISOString().slice(0, 10);
}

/**
 * O dia de Brasília em que `d` aconteceu, mais `dias` — dd/mm/aaaa.
 *
 * A validade do orçamento conta do dia da EMISSÃO. Somar dias ao instante e depois
 * formatar daria o dia errado sempre que o instante caísse, em UTC, num dia diferente
 * do de Brasília; aqui a soma é feita sobre o dia de calendário.
 *
 * É a mesma conta do aviso de orçamento vencido (task-automations, R19): o "até" que o
 * cliente lê no PDF e o dia em que o dono é avisado saem daqui, não de duas cópias.
 */
export function somarDiasBR(d: Date, dias: number): string {
  return dataBR(somarDiasAoDia(diaBR(d), dias));
}
