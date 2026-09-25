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

/** hh:mm no horário de Brasília. */
export function horaBR(d: Date): string {
  return d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit', timeZone: FUSO });
}

/** "dd/mm/aaaa, hh:mm:ss" no horário de Brasília — o carimbo de "Emitido em". */
export function dataHoraBR(d: Date): string {
  return d.toLocaleString('pt-BR', { timeZone: FUSO });
}

/**
 * O dia de Brasília em que `d` aconteceu, mais `dias` — dd/mm/aaaa.
 *
 * A validade do orçamento conta do dia da EMISSÃO. Somar dias ao instante e depois
 * formatar daria o dia errado sempre que o instante caísse, em UTC, num dia diferente
 * do de Brasília; aqui a soma é feita sobre o dia de calendário.
 */
export function somarDiasBR(d: Date, dias: number): string {
  const [ano, mes, dia] = new Intl.DateTimeFormat('en-CA', {
    timeZone: FUSO, year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(d).split('-').map(Number);
  const alvo = new Date(Date.UTC(ano, mes - 1, dia + dias));
  const dd = String(alvo.getUTCDate()).padStart(2, '0');
  const mm = String(alvo.getUTCMonth() + 1).padStart(2, '0');
  return `${dd}/${mm}/${alvo.getUTCFullYear()}`;
}
