/**
 * A regra de repetição da tarefa (agenda_tasks.rrule) como o diálogo mostra e edita (07/10/2026).
 *
 * O diálogo só lia FREQ e UNTIL e regravava "FREQ=X;UNTIL=Y": editar uma tarefa criada pelo
 * assistente com "a cada 15 dias" (INTERVAL=15) ou "toda segunda e quinta" (BYDAY=MO,TH) apagava
 * essas partes ao salvar — mesmo sem mexer na repetição. Agora o diálogo lê e edita o intervalo e os
 * dias da semana, e conserva qualquer parte que não entende.
 *
 * Dia da semana do BYDAY é o de UTC, porque é o que o motor compara (getUTCDay em
 * _shared/recurrence.ts): às 21h de Brasília já é o dia seguinte em UTC. O assistente monta assim
 * (montarRecorrencia, _shared/ai/tools/agenda.ts); aqui é o mesmo deslocamento, pelo horário da
 * tarefa (a âncora). Na tela os dias aparecem no calendário de Brasília.
 */

export type Frequencia = 'DAILY' | 'WEEKLY' | 'MONTHLY';

export interface Repeticao {
  freq: Frequencia;
  /** "A cada N" dias/semanas/meses; 1 = todo. */
  intervalo: number;
  /** Dias da semana em Brasília (0 = domingo … 6 = sábado). Só vale para semanal. */
  dias: number[];
  /** Último dia (AAAA-MM-DD) ou ''. */
  ate: string;
  /** Partes da regra que o diálogo não edita (COUNT, BYMONTHDAY…): voltam como vieram. */
  outras: string[];
}

const CODIGO_DO_DIA = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA'];
export const LETRA_DO_DIA = ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'];
export const NOME_DO_DIA = ['domingo', 'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado'];
const BRT_MS = 3 * 3600_000;

/** Quantos dias o dia de UTC está à frente do de Brasília no horário da âncora (0 ou 1). */
function deslocamento(ancoraISO: string | null | undefined): number {
  if (!ancoraISO) return 0;
  const d = new Date(ancoraISO);
  if (Number.isNaN(d.getTime())) return 0;
  return (d.getUTCDay() - new Date(d.getTime() - BRT_MS).getUTCDay() + 7) % 7;
}

/** A rrule gravada → o que o diálogo mostra. null = não repete (ou regra que o motor não entende). */
export function lerRepeticao(rrule: string | null | undefined, ancoraISO?: string | null): Repeticao | null {
  if (!rrule) return null;
  let freq: Frequencia | null = null;
  let intervalo = 1;
  let dias: number[] = [];
  let ate = '';
  const outras: string[] = [];
  const desloc = deslocamento(ancoraISO);
  for (const parte of rrule.replace(/^RRULE:/i, '').split(';')) {
    const [k, v = ''] = parte.split('=');
    const chave = (k ?? '').trim().toUpperCase();
    const valor = v.trim().toUpperCase();
    if (!chave) continue;
    if (chave === 'FREQ') {
      if (valor === 'DAILY' || valor === 'WEEKLY' || valor === 'MONTHLY') freq = valor;
    } else if (chave === 'INTERVAL') {
      intervalo = Math.max(1, parseInt(valor, 10) || 1);
    } else if (chave === 'BYDAY') {
      dias = valor.split(',').map((c) => CODIGO_DO_DIA.indexOf(c)).filter((n) => n >= 0)
        .map((n) => (n - desloc + 7) % 7);
    } else if (chave === 'UNTIL') {
      const m = valor.match(/^(\d{4})(\d{2})(\d{2})/);
      if (m) ate = `${m[1]}-${m[2]}-${m[3]}`;
    } else {
      outras.push(parte.trim());
    }
  }
  if (!freq) return null;
  return { freq, intervalo, dias: [...new Set(dias)].sort(), ate, outras };
}

/** O que o diálogo mostra → a rrule que o motor entende (BYDAY no dia de UTC da nova âncora). */
export function montarRrule(r: Repeticao, ancoraISO?: string | null): string {
  const desloc = deslocamento(ancoraISO);
  const partes = [`FREQ=${r.freq}`];
  const intervalo = Math.max(1, Math.floor(Number(r.intervalo) || 1));
  if (intervalo > 1) partes.push(`INTERVAL=${intervalo}`);
  if (r.freq === 'WEEKLY' && r.dias.length) {
    const codigos = [...new Set(r.dias)].sort().map((d) => CODIGO_DO_DIA[(d + desloc) % 7]);
    partes.push(`BYDAY=${[...new Set(codigos)].join(',')}`);
  }
  partes.push(...r.outras);
  if (r.ate) partes.push(`UNTIL=${r.ate.replace(/-/g, '')}`);
  return partes.join(';');
}

/** "a cada 15 dias", "toda segunda e quinta", "a cada 2 meses" — para o diálogo conferir. */
export function descreverRepeticao(r: Repeticao): string {
  const n = r.intervalo;
  if (r.freq === 'DAILY') return n > 1 ? `a cada ${n} dias` : 'todo dia';
  if (r.freq === 'MONTHLY') return n > 1 ? `a cada ${n} meses` : 'todo mês';
  const dias = r.dias.map((d) => NOME_DO_DIA[d]);
  const lista = dias.length > 1 ? `${dias.slice(0, -1).join(', ')} e ${dias[dias.length - 1]}` : dias[0] ?? 'semana';
  return n > 1 ? `a cada ${n} semanas${dias.length ? ` (${lista})` : ''}` : `toda ${lista}`;
}
