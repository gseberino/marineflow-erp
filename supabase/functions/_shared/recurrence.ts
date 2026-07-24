// Subconjunto de RRULE (RFC 5545) para a Agenda & Tarefas 2.0.
// Suportado: FREQ=DAILY|WEEKLY|MONTHLY, INTERVAL, BYDAY (só WEEKLY), UNTIL.
// Fora do escopo (de propósito, ver plano §3): COUNT, BYSETPOS, EXDATE, timezones
// nomeados — o Brasil não tem DST desde 2019, então aritmética UTC preserva a
// hora local de forma estável.

export interface ParsedRRule {
  freq: 'DAILY' | 'WEEKLY' | 'MONTHLY';
  interval: number;
  byday: number[]; // 0=DO ... 6=SA (getUTCDay)
  until: Date | null;
}

const BYDAY_MAP: Record<string, number> = { SU: 0, MO: 1, TU: 2, WE: 3, TH: 4, FR: 5, SA: 6 };

export function parseRRule(rrule: string): ParsedRRule | null {
  if (!rrule) return null;
  const parts: Record<string, string> = {};
  for (const seg of rrule.replace(/^RRULE:/i, '').split(';')) {
    const [k, v] = seg.split('=');
    if (k && v) parts[k.trim().toUpperCase()] = v.trim().toUpperCase();
  }
  const freq = parts['FREQ'];
  if (freq !== 'DAILY' && freq !== 'WEEKLY' && freq !== 'MONTHLY') return null;
  const interval = Math.max(1, parseInt(parts['INTERVAL'] || '1', 10) || 1);
  const byday = (parts['BYDAY'] || '')
    .split(',')
    .map((d) => BYDAY_MAP[d])
    .filter((n) => n !== undefined);
  let until: Date | null = null;
  if (parts['UNTIL']) {
    const m = parts['UNTIL'].match(/^(\d{4})(\d{2})(\d{2})(T(\d{2})(\d{2})(\d{2})Z?)?$/);
    if (m) {
      until = new Date(Date.UTC(+m[1], +m[2] - 1, +m[3], m[5] ? +m[5] : 23, m[6] ? +m[6] : 59, m[7] ? +m[7] : 59));
    }
  }
  return { freq, interval, byday, until };
}

/**
 * Ocorrências FUTURAS de uma série dentro de [windowStart, windowEnd], preservando
 * a hora do DTSTART. A própria data do DTSTART não é retornada (o registro-pai já
 * representa a primeira ocorrência).
 */
export function expandOccurrences(
  rrule: string,
  dtstart: Date,
  windowStart: Date,
  windowEnd: Date,
  maxOccurrences = 120,
): Date[] {
  const rule = parseRRule(rrule);
  if (!rule) return [];
  const out: Date[] = [];
  const limitEnd = rule.until && rule.until < windowEnd ? rule.until : windowEnd;

  if (rule.freq === 'DAILY') {
    const step = rule.interval * 86400000;
    for (let t = dtstart.getTime() + step; t <= limitEnd.getTime(); t += step) {
      const d = new Date(t);
      if (d >= windowStart) out.push(d);
      if (out.length >= maxOccurrences) break;
    }
    return out;
  }

  if (rule.freq === 'WEEKLY') {
    const days = rule.byday.length > 0 ? rule.byday : [dtstart.getUTCDay()];
    // Início da semana (domingo) do DTSTART, em UTC
    const weekStart = new Date(dtstart);
    weekStart.setUTCDate(weekStart.getUTCDate() - weekStart.getUTCDay());
    for (let w = 0; ; w++) {
      const base = new Date(weekStart.getTime() + w * rule.interval * 7 * 86400000);
      if (base.getTime() > limitEnd.getTime()) break;
      for (const dow of days.slice().sort()) {
        const d = new Date(base);
        d.setUTCDate(d.getUTCDate() + dow);
        d.setUTCHours(dtstart.getUTCHours(), dtstart.getUTCMinutes(), dtstart.getUTCSeconds(), 0);
        if (d <= dtstart) continue;
        if (d > limitEnd) continue;
        if (d >= windowStart) out.push(d);
        if (out.length >= maxOccurrences) return out;
      }
      if (w > 600) break; // trava de segurança
    }
    return out;
  }

  // MONTHLY: mesmo dia do mês do DTSTART; meses sem o dia (31 → fev) são pulados
  const day = dtstart.getUTCDate();
  for (let m = 1; ; m++) {
    const d = new Date(Date.UTC(
      dtstart.getUTCFullYear(),
      dtstart.getUTCMonth() + m * rule.interval,
      1,
      dtstart.getUTCHours(), dtstart.getUTCMinutes(), dtstart.getUTCSeconds(),
    ));
    d.setUTCDate(day);
    if (d.getUTCDate() !== day) continue; // mês sem esse dia
    if (d.getTime() > limitEnd.getTime()) break;
    if (d >= windowStart && d > dtstart) out.push(d);
    if (out.length >= maxOccurrences) break;
    if (m > 600) break;
  }
  return out;
}
