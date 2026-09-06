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

/** dd/mm[/aaaa] — reconhecer e remover usam o MESMO padrão. */
const DATA_RE = /\s(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?\s/;

/**
 * Hora só com marcador explícito: "às 9", "as 9", "14h", "14h30", "14:30".
 * Número solto ("comprar 3 cabos") é QUANTIDADE, nunca hora. [NOVO-018a]
 * Grupos: 1=h e 2=min do ramo "às"; 3=h e 4=min do ramo "h"; 5=min do ramo ":".
 */
const HORA_RE = /\s(?:[àa]s\s+(\d{1,2})(?:[:h](\d{2}))?h?|(\d{1,2})(?:h(\d{2})?|:(\d{2})))\s/i;

/** O JS normaliza 30/02 para 02/03 em vez de falhar; só a conferência revela. [NOVO-018b] */
const ehDataReal = (d: Date, dia: number, mes: number, ano: number) =>
  d.getDate() === dia && d.getMonth() === mes - 1 && d.getFullYear() === ano;

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
      const dm = text.match(DATA_RE);
      if (dm) {
        const d = Number(dm[1]);
        const mes = Number(dm[2]);
        const y = dm[3] ? (dm[3].length === 2 ? 2000 + Number(dm[3]) : Number(dm[3])) : today.getFullYear();
        const cand = new Date(y, mes - 1, d);
        // Data que não existe (30/02, 31/11) não vira outro dia: fica no título, sem data.
        if (ehDataReal(cand, d, mes, y)) {
          let escolhida: Date | null = cand;
          if (!dm[3] && cand < today) {
            const proximo = new Date(y + 1, mes - 1, d); // "se já passou, é do ano que vem"
            escolhida = ehDataReal(proximo, d, mes, y + 1) ? proximo : null; // 29/02 em ano não bissexto
          }
          if (escolhida) { date = escolhida; strip(DATA_RE); }
        }
      }
    }
  }

  // hora: 14h, 14h30, 14:30, "às 9" — sempre com marcador (h, :, "às"/"as")
  const hm = text.match(HORA_RE);
  if (hm) {
    const h = Number(hm[1] ?? hm[3]);
    const min = hm[2] ?? hm[4] ?? hm[5] ?? '00';
    if (h >= 0 && h <= 23 && Number(min) <= 59) {
      time = `${String(h).padStart(2, '0')}:${min}`;
      strip(HORA_RE);
      if (!date) date = today; // hora sem dia = hoje
    }
  }

  const title = text.replace(/\s+/g, ' ').trim();
  return { title, date, time, priority };
}
