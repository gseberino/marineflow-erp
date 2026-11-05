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
//
// Municipais do LOCAL do serviço (não da HBR): Balneário Camboriú 20/07 (Decreto 12.108/2025 de BC e
// proximoferiado.net/feriados/sc/balneario-camboriu). Ficam fora: o 11/08 de SC, Carnaval, Corpus Christi, 24/12 e 31/12 à tarde
// (facultativos) e o 28/05 de BC (só aparece em calendário comercial). Eles moram ao lado do calendário da HBR: feriadoDoDia e
// tipoDoDia não os veem, e o secretário e a fila continuam no de Itajaí. Mudou aqui, muda agenda_feriado_municipal() na mesma leva
// (a receita está em feriados-municipais-paridade_test.ts).

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

/** Os feriados do município do local: a chave é a de normalizarMunicipio(); a de dentro, "mm-dd". */
export const FERIADOS_MUNICIPAIS: Record<string, Record<string, string>> = {
  "balneario camboriu": { "07-20": "aniversário de Balneário Camboriú" },
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

/**
 * A chave de FERIADOS_MUNICIPAIS: minúsculo, sem acento, pontuação vira espaço, espaços colapsados. A mesma saída de _agenda_normal
 * (SQL) para os municípios da lista; por isso a barra fica, como lá: "Balneário/Camboriú" não casa em nenhum dos dois lados.
 */
export function normalizarMunicipio(municipio: string | null | undefined): string {
  return (municipio ?? "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9/ ]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/** O nome do feriado do município no dia 'aaaa-mm-dd', ou null. Os mesmos de agenda_feriado_municipal() no banco. */
export function feriadoMunicipal(dia: string, municipio: string | null | undefined): string | null {
  return FERIADOS_MUNICIPAIS[normalizarMunicipio(municipio)]?.[dia.slice(5, 10)] ?? null;
}

/** O feriado que vale no local: o da HBR primeiro, porque ele vale em qualquer lugar. Igual a agenda_feriado_do_local() no banco. */
export function feriadoDoLocal(dia: string, municipio: string | null | undefined): string | null {
  return feriadoDoDia(dia) ?? feriadoMunicipal(dia, municipio);
}
