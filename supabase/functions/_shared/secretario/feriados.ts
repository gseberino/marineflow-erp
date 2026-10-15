// Domingo e feriado: a manhã nova vira UMA linha ("nada precisa de você hoje; lista se quiser ver").
//
// Feriados (conferidos em 15/10/2026):
//   · nacionais fixos: 01/01, 21/04, 01/05, 07/09, 12/10, 02/11, 15/11, 20/11 (Consciência Negra,
//     nacional desde a Lei 14.759/2023) e 25/12;
//   · Sexta-feira Santa (Páscoa − 2, nacional);
//   · Itajaí: 15/06 (aniversário da cidade, o feriado municipal).
// Ficam FORA, de propósito: Carnaval e Corpus Christi (ponto facultativo em Itajaí — manhã normal) e o
// estadual de SC (11/08, que os decretos estaduais transferem para o domingo seguinte: não muda dia útil).
// Fontes: calendário de Itajaí (proximoferiado.net/feriados/sc/itajai) e decretos de SC (legisweb).

import { diaDaSemana, somarDias } from "./base.ts";

const FIXOS: Record<string, string> = {
  "01-01": "Ano-Novo",
  "04-21": "Tiradentes",
  "05-01": "Dia do Trabalho",
  "06-15": "aniversário de Itajaí",
  "09-07": "Independência",
  "10-12": "Nossa Senhora Aparecida",
  "11-02": "Finados",
  "11-15": "Proclamação da República",
  "11-20": "Consciência Negra",
  "12-25": "Natal",
};

/** Domingo de Páscoa do ano (algoritmo de Meeus/Jones/Butcher, calendário gregoriano). */
export function pascoa(ano: number): string {
  const a = ano % 19;
  const b = Math.floor(ano / 100);
  const c = ano % 100;
  const d = Math.floor(b / 4);
  const e = b % 4;
  const f = Math.floor((b + 8) / 25);
  const g = Math.floor((b - f + 1) / 3);
  const h = (19 * a + b - d - g + 15) % 30;
  const i = Math.floor(c / 4);
  const k = c % 4;
  const l = (32 + 2 * e + 2 * i - h - k) % 7;
  const m = Math.floor((a + 11 * h + 22 * l) / 451);
  const mes = Math.floor((h + l - 7 * m + 114) / 31);
  const dia = ((h + l - 7 * m + 114) % 31) + 1;
  return `${ano}-${String(mes).padStart(2, "0")}-${String(dia).padStart(2, "0")}`;
}

/** O nome do feriado do dia 'aaaa-mm-dd', ou null. */
export function feriadoDoDia(dia: string): string | null {
  const d = dia.slice(0, 10);
  const fixo = FIXOS[d.slice(5)];
  if (fixo) return fixo;
  if (d === somarDias(pascoa(Number(d.slice(0, 4))), -2)) return "Sexta-feira Santa";
  return null;
}

export type TipoDoDia = "util" | "domingo" | "feriado";

/** Domingo vale antes do feriado (o texto diz "Domingo"). */
export function tipoDoDia(dia: string): TipoDoDia {
  if (diaDaSemana(dia) === 0) return "domingo";
  return feriadoDoDia(dia) ? "feriado" : "util";
}
