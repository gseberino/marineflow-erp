// O turno da tarde do resumo (secretário, Passo 3, 15/10/2026) — a chave e o calendário, puros.
// Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-fechamento.md §1 e §2.
//
// app_settings.fechamento_formato:
//   desligado → nada às 17:30 (é o valor com que a chave nasce);
//   sombra    → monta e GUARDA (resumo_tarde), sem enviar;
//   ligado    → envia ao dono, só nos dias em que a manhã foi a nova (as letras são as que ele recebeu).
// Valor desconhecido, chave ausente ou erro de leitura = "desligado". Três fontes do mesmo padrão: este
// "desligado", a linha da migration 20261015210000 e a ausência da chave.
//
// Que turno é cada dia (seg–sex; sábado, domingo e feriado não têm tarde):
//   · revisao_mes    — o 1º dia útil do mês (o dia 1 em sábado, domingo ou feriado vai para o próximo dia útil);
//   · revisao_semana — o 1º dia útil da semana; se ele já é o da revisão do mês, o dia útil seguinte;
//   · fechamento     — os outros.
// A pergunta da sexta vai na tarde do último dia útil da semana (sexta; se for feriado, quinta).

import { diaDaSemana, somarDias } from "./base.ts";
import { tipoDoDia } from "./feriados.ts";

export type FormatoDoFechamento = "desligado" | "sombra" | "ligado";
export type TurnoDaTarde = "fechamento" | "revisao_semana" | "revisao_mes";

export const CHAVE_DO_FECHAMENTO = "fechamento_formato";

/** "ligado", " Sombra ", "\"ligado\"" → o formato; qualquer outra coisa → "desligado". */
export function lerFormatoDoFechamento(v: unknown): FormatoDoFechamento {
  if (typeof v !== "string") return "desligado";
  const s = v.trim().replace(/^"(.*)"$/, "$1").trim().toLowerCase();
  return s === "sombra" || s === "ligado" ? s : "desligado";
}

/** O turno pedido na URL: "tarde" (o do dia) ou um turno forçado (só no dry-run). */
export function lerTurnoPedido(v: string | null): "tarde" | TurnoDaTarde | null {
  const s = String(v ?? "").trim().toLowerCase();
  return s === "tarde" || s === "fechamento" || s === "revisao_semana" || s === "revisao_mes" ? s : null;
}

/** Dia útil da tarde: segunda a sexta, sem feriado (o mesmo calendário da manhã). */
export function ehDiaUtilDaTarde(dia: string): boolean {
  const ds = diaDaSemana(dia);
  return ds >= 1 && ds <= 5 && tipoDoDia(dia) === "util";
}

/** O 1º dia útil (seg–sex, sem feriado) do mês de `dia`. */
export function diaDaRevisaoDoMes(dia: string): string {
  let d = `${dia.slice(0, 7)}-01`;
  for (let i = 0; i < 10 && !ehDiaUtilDaTarde(d); i++) d = somarDias(d, 1);
  return d;
}

/** Os dias úteis (seg–sex, sem feriado) da semana de `dia`, em ordem. */
export function diasUteisDaSemana(dia: string): string[] {
  const ds = diaDaSemana(dia); // 0 = domingo
  const segunda = somarDias(dia, ds === 0 ? -6 : 1 - ds);
  return [0, 1, 2, 3, 4].map((i) => somarDias(segunda, i)).filter(ehDiaUtilDaTarde);
}

/**
 * O dia da revisão da semana de `dia`: o 1º dia útil da semana, ou o seguinte se o 1º já é o da revisão do
 * mês (nunca duas revisões no mesmo dia). null = a semana não tem um dia para ela.
 */
export function diaDaRevisaoDaSemana(dia: string): string | null {
  const uteis = diasUteisDaSemana(dia);
  const livres = uteis.filter((d) => d !== diaDaRevisaoDoMes(d));
  return livres[0] ?? null;
}

/** O turno da tarde de `dia`, ou null (sábado, domingo, feriado). */
export function turnoDaTarde(dia: string): TurnoDaTarde | null {
  if (!ehDiaUtilDaTarde(dia)) return null;
  if (dia === diaDaRevisaoDoMes(dia)) return "revisao_mes";
  if (dia === diaDaRevisaoDaSemana(dia)) return "revisao_semana";
  return "fechamento";
}

/** A tarde de `dia` leva a pergunta da sexta: é o último dia útil da semana. */
export function ehDiaDaPerguntaDaSemana(dia: string): boolean {
  const uteis = diasUteisDaSemana(dia);
  return uteis.length > 0 && uteis[uteis.length - 1] === dia;
}

/** O próximo dia com manhã (seg–sáb, sem feriado) depois de `dia`: o "Amanhã" do fechamento. */
export function proximoDiaComManha(dia: string): string {
  let d = somarDias(dia, 1);
  for (let i = 0; i < 10 && tipoDoDia(d) !== "util"; i++) d = somarDias(d, 1);
  return d;
}
