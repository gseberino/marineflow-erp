// Parser determinístico de captura rápida em pt-BR para a Agenda.
// "amanhã 14h ligar pro João" → { title: "ligar pro João", due/scheduled }
// Sem IA: instantâneo e offline; o caminho por linguagem livre continua no agente.

const WEEKDAYS: Record<string, number> = {
  domingo: 0, segunda: 1, 'segunda-feira': 1, terca: 2, terça: 2, 'terça-feira': 2,
  quarta: 3, 'quarta-feira': 3, quinta: 4, 'quinta-feira': 4,
  sexta: 5, 'sexta-feira': 5, sabado: 6, sábado: 6,
};

export interface QuickTaskParse {
  title: string;
  /** dia-alvo em Date local (00:00) ou null se não citado */
  date: Date | null;
  /** hora HH:MM se citada */
  time: string | null;
  priority: 'urgent' | 'high' | null;
}

export function parseQuickTask(input: string, now: Date = new Date()): QuickTaskParse {
  let text = ` ${input.trim()} `;
  let date: Date | null = null;
  let time: string | null = null;
  let priority: 'urgent' | 'high' | null = null;

  const strip = (re: RegExp) => { text = text.replace(re, ' '); };

  // prioridade
  if (/\s(urgente|!!)\s/i.test(text)) { priority = 'urgent'; strip(/\s(urgente|!!)\s/i); }
  else if (/\s(importante|!)\s/i.test(text)) { priority = 'high'; strip(/\s(importante|!)\s/i); }

  // dia
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  if (/\shoje\s/i.test(text)) { date = today; strip(/\shoje\s/i); }
  else if (/\samanh[ãa]\s/i.test(text)) {
    date = new Date(today.getTime() + 86400000); strip(/\samanh[ãa]\s/i);
  } else {
    const wd = text.toLowerCase().match(/\s(domingo|segunda(?:-feira)?|ter[cç]a(?:-feira)?|quarta(?:-feira)?|quinta(?:-feira)?|sexta(?:-feira)?|s[áa]bado)\s/);
    if (wd) {
      const target = WEEKDAYS[wd[1]];
      let diff = (target - today.getDay() + 7) % 7;
      if (diff === 0) diff = 7; // "sexta" numa sexta = a PRÓXIMA sexta
      date = new Date(today.getTime() + diff * 86400000);
      strip(new RegExp(`\\s${wd[1]}\\s`, 'i'));
    } else {
      // dd/mm ou dd/mm/aaaa
      const dm = text.match(/\s(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?\s/);
      if (dm) {
        const y = dm[3] ? (dm[3].length === 2 ? 2000 + Number(dm[3]) : Number(dm[3])) : today.getFullYear();
        const cand = new Date(y, Number(dm[2]) - 1, Number(dm[1]));
        if (!Number.isNaN(cand.getTime())) {
          date = cand;
          if (!dm[3] && cand < today) date = new Date(y + 1, Number(dm[2]) - 1, Number(dm[1]));
          strip(/\s(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?\s/);
        }
      }
    }
  }

  // hora: 14h, 14h30, 14:30, "as 9"
  const hm = text.match(/\s(?:[àa]s\s+)?(\d{1,2})(?:[:h](\d{2}))?h?\s/i);
  if (hm) {
    const h = Number(hm[1]);
    if (h >= 0 && h <= 23) {
      time = `${String(h).padStart(2, '0')}:${hm[2] ?? '00'}`;
      strip(/\s(?:[àa]s\s+)?(\d{1,2})(?:[:h](\d{2}))?h?\s/i);
      if (!date) date = today; // hora sem dia = hoje
    }
  }

  const title = text.replace(/\s+/g, ' ').trim();
  return { title, date, time, priority };
}
