// Motor de apuração: de jornada trabalhada para valor a pagar.
//
// Funções PURAS de propósito — nada de banco aqui. É o que permite testar as regras da CLT com
// casos de borda (turno que cruza a meia-noite, hora extra noturna, domingo) sem subir nada.
//
// Regras implementadas (ver plans/marineflow-jornada-e-pagamento-de-equipe.md §2.3):
//   hora normal        = salário mensal ÷ divisor (220 por padrão)
//   hora extra diurna  = +50%  (art. 59 CLT)
//   adicional noturno  = +20%  entre 22h e 5h (art. 73 CLT)
//   domingo/feriado    = +100%
//   hora extra noturna = cumulativa: hora × 1,20 × 1,50 = × 1,80
//   DSR                = total de horas extras ÷ dias úteis × domingos e feriados
//
// Percentuais são PADRÃO, não verdade: convenção coletiva pode elevá-los, e por isso vêm do
// perfil e não de constante no código.

export const FUSO_BRASIL = "America/Sao_Paulo";

export type ModoPagamento = "hora" | "diaria" | "mensal" | "empreitada";
export type TipoTurno = "normal" | "diaria" | "folga" | "falta" | "atestado" | "feriado";

export interface WorkProfile {
  id: string;
  modo_pagamento: ModoPagamento;
  valor_hora?: number | null;
  valor_diaria?: number | null;
  valor_mensal?: number | null;
  meia_diaria_ate_horas?: number | null;
  jornada_diaria_horas: number;
  divisor_mensal: number;
  pct_hora_extra: number;
  pct_noturno: number;
  pct_domingo: number;
  paga_dsr: boolean;
}

export interface Turno {
  id?: string;
  data: string;              // YYYY-MM-DD (data local)
  inicio?: string | null;    // ISO
  fim?: string | null;       // ISO
  intervalo_minutos?: number | null;
  duracao_minutos?: number | null;
  tipo: TipoTurno;
}

export interface Apuracao {
  horas_normais: number;
  horas_extras: number;
  horas_noturnas: number;
  horas_domingo: number;
  diarias_inteiras: number;
  diarias_meias: number;
  valor_normais: number;
  valor_extras: number;
  valor_noturnas: number;
  valor_domingo: number;
  valor_diarias: number;
  valor_mensal: number;
  valor_dsr: number;
  valor_comissoes: number;
  descontos: number;
  valor_bruto: number;
  detalhamento: Array<Record<string, unknown>>;
  avisos: string[];
}

const arred = (n: number) => Math.round(n * 100) / 100;

/** Hora do dia (0-23) e dia da semana no fuso de Brasília, não no fuso do servidor.
 *  A Edge Function roda em UTC — usar getHours() daria 21h para um turno das 18h. */
export function emBrasilia(iso: string): { hora: number; minuto: number; diaSemana: number; dataLocal: string } {
  const d = new Date(iso);
  const fmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: FUSO_BRASIL, hour12: false,
    year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", weekday: "short",
  });
  const p = Object.fromEntries(fmt.formatToParts(d).map((x) => [x.type, x.value]));
  const semana: Record<string, number> = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };
  return {
    hora: Number(p.hour) % 24,
    minuto: Number(p.minute),
    diaSemana: semana[p.weekday as string] ?? 0,
    dataLocal: `${p.year}-${p.month}-${p.day}`,
  };
}

/** Minutos do turno que caem na janela noturna (22h–5h), fatiando minuto a minuto a partir do
 *  início. Turno que cruza a meia-noite é o caso normal aqui, não a exceção. */
export function minutosNoturnos(inicioIso: string, fimIso: string, intervaloMin = 0): number {
  const ini = new Date(inicioIso).getTime();
  const fim = new Date(fimIso).getTime();
  if (!(fim > ini)) return 0;

  const totalMin = Math.floor((fim - ini) / 60000);
  let noturnos = 0;
  for (let m = 0; m < totalMin; m++) {
    const { hora } = emBrasilia(new Date(ini + m * 60000).toISOString());
    if (hora >= 22 || hora < 5) noturnos++;
  }
  // O intervalo (almoço) é descontado proporcionalmente: sem saber quando foi, distribuir é mais
  // honesto que assumir que caiu todo no diurno.
  if (intervaloMin > 0 && totalMin > 0) {
    noturnos = Math.max(0, noturnos - Math.round((noturnos / totalMin) * intervaloMin));
  }
  return noturnos;
}

/** Duração efetiva do turno em minutos, já sem o intervalo. */
export function duracaoDoTurno(t: Turno): number {
  if (typeof t.duracao_minutos === "number") return Math.max(0, t.duracao_minutos);
  if (!t.inicio || !t.fim) return 0;
  const bruto = Math.floor((new Date(t.fim).getTime() - new Date(t.inicio).getTime()) / 60000);
  return Math.max(0, bruto - (t.intervalo_minutos ?? 0));
}

/** Turnos que não são trabalho: folga, falta e atestado não geram valor por hora nem diária.
 *  Atestado em CLT é assunto de folha (a contadora trata), não de apuração de jornada. */
const NAO_TRABALHADO: TipoTurno[] = ["folga", "falta", "atestado"];

export function apurar(
  perfil: WorkProfile,
  turnos: Turno[],
  extras: { comissoes?: number; descontos?: number; diasUteis?: number; domingosEFeriados?: number } = {},
): Apuracao {
  const r: Apuracao = {
    horas_normais: 0, horas_extras: 0, horas_noturnas: 0, horas_domingo: 0,
    diarias_inteiras: 0, diarias_meias: 0,
    valor_normais: 0, valor_extras: 0, valor_noturnas: 0, valor_domingo: 0,
    valor_diarias: 0, valor_mensal: 0, valor_dsr: 0,
    valor_comissoes: extras.comissoes ?? 0, descontos: extras.descontos ?? 0,
    valor_bruto: 0, detalhamento: [], avisos: [],
  };

  const valorHora = perfil.modo_pagamento === "mensal"
    ? (perfil.valor_mensal ?? 0) / (perfil.divisor_mensal || 220)
    : (perfil.valor_hora ?? 0);

  for (const t of turnos) {
    if (NAO_TRABALHADO.includes(t.tipo)) {
      r.detalhamento.push({ data: t.data, tipo: t.tipo, valor: 0 });
      continue;
    }

    // ---- Diária: o que vale é o dia, não o relógio ----
    if (t.tipo === "diaria" || perfil.modo_pagamento === "diaria") {
      const vd = perfil.valor_diaria ?? 0;
      if (vd === 0) r.avisos.push(`Turno de ${t.data} é diária, mas o perfil não tem valor de diária.`);
      const horas = duracaoDoTurno(t) / 60;
      const limiteMeia = perfil.meia_diaria_ate_horas ?? null;
      // Sem horas registradas, uma diária é uma diária inteira — é assim que se combina no campo.
      const meia = limiteMeia !== null && horas > 0 && horas <= limiteMeia;
      if (meia) { r.diarias_meias += 1; r.valor_diarias += vd * 0.5; }
      else { r.diarias_inteiras += 1; r.valor_diarias += vd; }
      r.detalhamento.push({ data: t.data, tipo: "diaria", horas: arred(horas), meia, valor: arred(meia ? vd * 0.5 : vd) });
      continue;
    }

    // ---- Por hora (ou mensalista com hora extra) ----
    const minutos = duracaoDoTurno(t);
    if (minutos === 0) continue;
    const horas = minutos / 60;

    const ref = t.inicio ?? `${t.data}T12:00:00-03:00`;
    const { diaSemana } = emBrasilia(ref);
    const ehDomingo = diaSemana === 0 || t.tipo === "feriado";

    const minNot = t.inicio && t.fim ? minutosNoturnos(t.inicio, t.fim, t.intervalo_minutos ?? 0) : 0;
    const hNot = minNot / 60;
    const hDiurnas = Math.max(0, horas - hNot);

    if (ehDomingo) {
      // Domingo/feriado paga em dobro sobre a hora normal; não se soma extra por cima.
      r.horas_domingo += horas;
      r.valor_domingo += horas * valorHora * (1 + perfil.pct_domingo / 100);
      r.detalhamento.push({ data: t.data, tipo: "domingo_feriado", horas: arred(horas), valor: arred(horas * valorHora * (1 + perfil.pct_domingo / 100)) });
      continue;
    }

    const jornada = perfil.jornada_diaria_horas || 8;
    const hNormais = Math.min(horas, jornada);
    const hExtras = Math.max(0, horas - jornada);

    // As horas extras são as ÚLTIMAS do turno, então são as que têm mais chance de cair no
    // noturno. Atribuir o noturno primeiro às extras é o que reflete a jornada real.
    const notNasExtras = Math.min(hNot, hExtras);
    const notNasNormais = Math.max(0, hNot - notNasExtras);
    const normaisDiurnas = Math.max(0, hNormais - notNasNormais);
    const extrasDiurnas = Math.max(0, hExtras - notNasExtras);

    const fatorExtra = 1 + perfil.pct_hora_extra / 100;
    const fatorNot = 1 + perfil.pct_noturno / 100;

    const vNormaisDiurnas = normaisDiurnas * valorHora;
    const vNormaisNoturnas = notNasNormais * valorHora * fatorNot;
    const vExtrasDiurnas = extrasDiurnas * valorHora * fatorExtra;
    const vExtrasNoturnas = notNasExtras * valorHora * fatorNot * fatorExtra; // × 1,20 × 1,50

    r.horas_normais += hNormais;
    r.horas_extras += hExtras;
    r.horas_noturnas += hNot;
    r.valor_normais += vNormaisDiurnas;
    r.valor_noturnas += vNormaisNoturnas + vExtrasNoturnas;
    r.valor_extras += vExtrasDiurnas;

    r.detalhamento.push({
      data: t.data, tipo: "normal",
      horas: arred(horas), horas_extras: arred(hExtras), horas_noturnas: arred(hNot),
      valor: arred(vNormaisDiurnas + vNormaisNoturnas + vExtrasDiurnas + vExtrasNoturnas),
    });
    // hDiurnas fica implícito na decomposição acima; mantido no cálculo para clareza da conta.
    void hDiurnas;
  }

  // ---- Mensalista: o salário entra cheio; as extras acima já foram somadas ----
  if (perfil.modo_pagamento === "mensal") {
    r.valor_mensal = perfil.valor_mensal ?? 0;
    r.valor_normais = 0; // a hora normal do mensalista já está dentro do salário
    r.horas_normais = arred(r.horas_normais);
  }

  // ---- DSR sobre as horas extras (só CLT) ----
  if (perfil.paga_dsr && (r.valor_extras + r.valor_noturnas) > 0) {
    const dias = extras.diasUteis ?? 0;
    const dom = extras.domingosEFeriados ?? 0;
    if (dias > 0) {
      r.valor_dsr = ((r.valor_extras + r.valor_noturnas) / dias) * dom;
    } else {
      r.avisos.push("Perfil paga DSR, mas não vieram dias úteis do período — DSR ficou zerado.");
    }
  }

  r.valor_bruto =
    r.valor_normais + r.valor_extras + r.valor_noturnas + r.valor_domingo +
    r.valor_diarias + r.valor_mensal + r.valor_dsr + r.valor_comissoes - r.descontos;

  for (const k of ["horas_normais","horas_extras","horas_noturnas","horas_domingo","diarias_inteiras","diarias_meias",
                   "valor_normais","valor_extras","valor_noturnas","valor_domingo","valor_diarias","valor_mensal",
                   "valor_dsr","valor_comissoes","descontos","valor_bruto"] as const) {
    r[k] = arred(r[k] as number) as never;
  }
  return r;
}

/** Dias úteis e domingos/feriados de um intervalo — insumo do DSR. Feriados municipais não
 *  entram: o sistema não tem calendário deles, e inventar data seria pior que pedir. */
export function diasDoPeriodo(de: string, ate: string): { diasUteis: number; domingosEFeriados: number } {
  const ini = new Date(`${de}T12:00:00-03:00`);
  const fim = new Date(`${ate}T12:00:00-03:00`);
  let uteis = 0, domingos = 0;
  for (let d = new Date(ini); d <= fim; d.setDate(d.getDate() + 1)) {
    const { diaSemana } = emBrasilia(d.toISOString());
    if (diaSemana === 0) domingos++;
    else uteis++;
  }
  return { diasUteis: uteis, domingosEFeriados: domingos };
}
