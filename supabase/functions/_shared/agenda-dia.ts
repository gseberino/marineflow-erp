// O dia de trabalho de Brasília, em um lugar só: a tela, as ferramentas do assistente e o
// Secretário perguntam aqui "o que cabe neste dia" (Agenda de Produção, Fase 0, 23/10/2026).
//
// POR QUE ISTO EXISTE: a OS guarda uma JANELA CORRIDA (scheduled_start_at → scheduled_end_at),
// não horas de trabalho. Na história do banco, as janelas agendadas vão de 2 h a 104,5 h: uma OS
// de "06/10 06:00 a 08/10 18:00" são três dias de serviço, e não 60 horas seguidas. Cada leitor
// tratava essa janela de um jeito, e todos erravam:
//
//   · a grade da semana e o mês só punham a OS no dia do INÍCIO — nos outros dias a pessoa
//     aparecia "Livre" (D4);
//   · a carga do dia somava a janela inteira: uma OS de 72 h virava "72h ⚠" num dia só (D5);
//   · as leituras do assistente montavam o dia em UTC: depois das 21 h de Brasília, "hoje" já
//     era amanhã (D6).
//
// A regra daqui: uma OS toca todo dia de Brasília que a janela cruza, e em cada dia ocupa a
// parte da janela que cai nele, com TETO na jornada. Uma janela de 72 h dá no máximo 8 h por dia.
//
// Este arquivo não importa nada de propósito: a tela (Vite) o carrega por caminho relativo, como
// já faz com service-order-status.ts, e as Edge Functions (Deno) importam direto.

/**
 * A jornada de um dia de trabalho, em horas. É o ÚNICO literal de jornada: o teto da carga por
 * OS, o "dia cheio" da grade e o aviso de sobrecarga leem daqui. A Fase 1 troca pela capacidade
 * por pessoa (agenda_disponibilidade); até lá, todo mundo tem 8 h.
 */
export const JORNADA_PADRAO_HORAS = 8;

/** Brasília não tem horário de verão desde 2019: o deslocamento é fixo. */
const FUSO_BR = "-03:00";
const DESLOCAMENTO_BR_MS = 3 * 3600000;
const DIA_MS = 86400000;
const SO_DATA = /^\d{4}-\d{2}-\d{2}$/;

type Instante = string | number | Date;

function ms(v: Instante): number {
  return v instanceof Date ? v.getTime() : typeof v === "number" ? v : new Date(v).getTime();
}

/** O dia de Brasília ('AAAA-MM-DD') em que cai um instante. Às 22 h de Brasília ainda é hoje. */
export function diaBR(instante: Instante): string {
  return new Date(ms(instante) - DESLOCAMENTO_BR_MS).toISOString().slice(0, 10);
}

/** O dia seguinte (ou anterior, com n negativo) de um 'AAAA-MM-DD'. Meio-dia UTC: sem tropeço de fuso. */
export function somarDias(dia: string, n: number): string {
  return new Date(new Date(`${dia}T12:00:00Z`).getTime() + n * DIA_MS).toISOString().slice(0, 10);
}

/**
 * Os limites de um dia de Brasília, [00:00, 24:00), em ISO UTC.
 *
 * Aceita o dia ('AAAA-MM-DD') ou um instante qualquer (ISO, Date, epoch): o instante vira o dia
 * de Brasília em que ele cai. Sem argumento, é hoje em Brasília.
 */
export function limitesDoDiaBR(dia: Instante = Date.now()): { de: string; ate: string; dia: string } {
  const d = typeof dia === "string" && SO_DATA.test(dia) ? dia : diaBR(dia);
  const de = new Date(`${d}T00:00:00${FUSO_BR}`).toISOString();
  const ate = new Date(new Date(de).getTime() + DIA_MS).toISOString();
  return { de, ate, dia: d };
}

/**
 * A janela [ini, fim) cruza o intervalo [de, ate)? Sem fim (ou com fim antes do início), vale só
 * o instante do início: ele precisa cair dentro do intervalo.
 */
export function cruzaODia(
  ini: Instante | null | undefined,
  fim: Instante | null | undefined,
  de: Instante,
  ate: Instante,
): boolean {
  if (ini === null || ini === undefined) return false;
  const i = ms(ini), d = ms(de), a = ms(ate);
  if (!Number.isFinite(i)) return false;
  const f = fim === null || fim === undefined ? NaN : ms(fim);
  if (!Number.isFinite(f) || f <= i) return i >= d && i < a;
  return i < a && f > d;
}

/**
 * Quantas horas a janela [ini, fim) ocupa no dia de Brasília `dia`: a sobreposição com o dia,
 * com TETO na jornada. Uma janela de 72 h dá 8 h em cada dia, nunca 24. Sem fim, não há
 * duração para contar: 0.
 */
export function horasNoDia(
  ini: Instante | null | undefined,
  fim: Instante | null | undefined,
  dia: string,
  jornada: number = JORNADA_PADRAO_HORAS,
): number {
  if (ini === null || ini === undefined || fim === null || fim === undefined) return 0;
  const i = ms(ini), f = ms(fim);
  if (!Number.isFinite(i) || !Number.isFinite(f) || f <= i) return 0;
  const { de, ate } = limitesDoDiaBR(dia);
  const sobreposicao = Math.min(f, ms(ate)) - Math.max(i, ms(de));
  if (sobreposicao <= 0) return 0;
  return Math.min(sobreposicao / 3600000, jornada);
}

/**
 * Os dias de Brasília ('AAAA-MM-DD') que a janela [ini, fim) toca, recortados ao período visível
 * [deDia, ateDia] (os dois inclusos). Sem fim, só o dia do início. Uma janela que termina à
 * meia-noite exata não toca o dia que começa ali.
 */
export function diasDaJanela(
  ini: Instante | null | undefined,
  fim: Instante | null | undefined,
  deDia: string,
  ateDia: string,
): string[] {
  if (ini === null || ini === undefined) return [];
  const i = ms(ini);
  if (!Number.isFinite(i)) return [];
  const f = fim === null || fim === undefined ? NaN : ms(fim);
  const primeiro = diaBR(i);
  const ultimo = Number.isFinite(f) && f > i ? diaBR(f - 1) : primeiro;
  // 'AAAA-MM-DD' compara como texto na mesma ordem das datas.
  let dia = primeiro > deDia ? primeiro : deDia;
  const fimDoRecorte = ultimo < ateDia ? ultimo : ateDia;
  const dias: string[] = [];
  while (dia <= fimDoRecorte) {
    dias.push(dia);
    dia = somarDias(dia, 1);
  }
  return dias;
}

/**
 * O texto do `.or()` do PostgREST que traz toda OS cuja janela ainda não acabou em `de`: termina
 * DEPOIS de `de`, ou não tem fim e começa em `de` ou depois. É SEMPRE usado junto com
 * `.lt('scheduled_start_at', ate)` — os dois juntos são a interseção com [de, ate).
 *
 * O fim é EXCLUSIVO (`gt`), como em cruzaODia, diasDaJanela e horasNoDia: a OS que termina à
 * 00:00 exata não toca o dia que começa ali. Até a revisão de 23/10/2026 era `gte`, e essa OS
 * entrava no dia seguinte nas leituras que não refiltram em JS (my_agenda, list_team_agenda,
 * get_situation_overview e check_technician_availability, que ainda a marcava de vários dias),
 * enquanto a grade e o Secretário, que refiltram, a deixavam de fora: o mesmo dia saía diferente
 * na tela e no assistente.
 *
 * `de` é ISO (toISOString), que não tem vírgula: não precisa de aspas nem do orContem.
 */
export function filtroQueCruza(de: string): string {
  return `scheduled_end_at.gt.${de},and(scheduled_end_at.is.null,scheduled_start_at.gte.${de})`;
}
