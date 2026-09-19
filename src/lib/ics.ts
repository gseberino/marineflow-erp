/**
 * Exportação da agenda em .ics (iCalendar, RFC 5545) — abre no Google Agenda, Apple
 * Calendário e Outlook. Função pura: recebe tarefas, devolve texto. Quem baixa é a tela.
 *
 * Regras que importam:
 *  · Compromisso com início/fim vira evento com hora (DTSTART/DTEND em UTC).
 *  · Tarefa só com prazo vira evento de DIA INTEIRO na data do prazo (VALUE=DATE); o
 *    DTEND de dia inteiro é EXCLUSIVO, por isso é o dia seguinte.
 *  · Sem data nenhuma, não vira evento — calendário não tem onde pôr.
 *  · Texto é escapado (vírgula, ponto e vírgula, quebra de linha) e as linhas dobram em
 *    75 octetos, como a RFC pede; leitores tolerantes ignoram, os rígidos exigem.
 */

export interface TarefaParaIcs {
  id: string;
  title: string;
  description?: string | null;
  location?: string | null;
  scheduled_start_at?: string | null;
  scheduled_end_at?: string | null;
  due_at?: string | null;
  all_day?: boolean | null;
  status?: string | null;
}

const pad = (n: number) => String(n).padStart(2, '0');

/** 20260919T133000Z */
export function icsUtc(iso: string): string {
  const d = new Date(iso);
  return `${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}T${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}${pad(d.getUTCSeconds())}Z`;
}

/** 20260919 (data local do aparelho de quem exporta). */
export function icsDate(iso: string, deslocaDias = 0): string {
  const d = new Date(iso);
  d.setDate(d.getDate() + deslocaDias);
  return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}`;
}

export function icsEscape(texto: string): string {
  return String(texto ?? '')
    .replace(/\\/g, '\\\\')
    .replace(/;/g, '\\;')
    .replace(/,/g, '\\,')
    .replace(/\r?\n/g, '\\n');
}

/** Dobra em 75 octetos com continuação por espaço (RFC 5545 §3.1). */
export function icsFold(linha: string): string {
  const bytes = new TextEncoder().encode(linha);
  if (bytes.length <= 75) return linha;
  const partes: string[] = [];
  let atual = '';
  let tamanho = 0;
  for (const ch of linha) {
    const b = new TextEncoder().encode(ch).length;
    const limite = partes.length === 0 ? 75 : 74; // a continuação começa com espaço
    if (tamanho + b > limite) {
      partes.push(atual);
      atual = ch;
      tamanho = b;
    } else {
      atual += ch;
      tamanho += b;
    }
  }
  if (atual) partes.push(atual);
  return partes.map((p, i) => (i === 0 ? p : ` ${p}`)).join('\r\n');
}

export function tarefaParaVevento(t: TarefaParaIcs, agora: Date = new Date()): string | null {
  const inicio = t.scheduled_start_at || null;
  const fim = t.scheduled_end_at || null;
  const prazo = t.due_at || null;

  let datas: string[];
  if (inicio && !t.all_day) {
    const fimReal = fim || new Date(new Date(inicio).getTime() + 60 * 60_000).toISOString();
    datas = [`DTSTART:${icsUtc(inicio)}`, `DTEND:${icsUtc(fimReal)}`];
  } else if (inicio || prazo) {
    const base = (inicio || prazo) as string;
    datas = [`DTSTART;VALUE=DATE:${icsDate(base)}`, `DTEND;VALUE=DATE:${icsDate(base, 1)}`];
  } else {
    return null;
  }

  const linhas = [
    'BEGIN:VEVENT',
    `UID:marineflow-tarefa-${t.id}@hbrmarine`,
    `DTSTAMP:${icsUtc(agora.toISOString())}`,
    ...datas,
    `SUMMARY:${icsEscape(t.title)}`,
    t.description ? `DESCRIPTION:${icsEscape(t.description)}` : null,
    t.location ? `LOCATION:${icsEscape(t.location)}` : null,
    `STATUS:${t.status === 'done' ? 'COMPLETED' : t.status === 'cancelled' ? 'CANCELLED' : 'CONFIRMED'}`,
    'END:VEVENT',
  ].filter((l): l is string => !!l);
  return linhas.map(icsFold).join('\r\n');
}

export function gerarIcs(tarefas: TarefaParaIcs[], agora: Date = new Date()): string {
  const eventos = tarefas.map((t) => tarefaParaVevento(t, agora)).filter((v): v is string => !!v);
  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//HBR Marine Solutions//MarineFlow ERP//PT-BR',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'X-WR-CALNAME:MarineFlow · Agenda',
    ...eventos,
    'END:VCALENDAR',
    '',
  ].join('\r\n');
}
