// Uma voz só (secretário, Passo 4, 15/10/2026): os horários do dono, puros e testáveis sem banco.
// Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-uma-voz.md (§3.4, §3.5, §5)
//
//   07:30        a manhã (mensagem fixa)
//   07:30–09:30  a janela da manhã: só a manhã pergunta (nenhum cartão de sim/não de outra fonte)
//   08:00–20:00  pode acordar o dono (sem cartão até 09:30)
//   17:30        o fechamento (seg–sex; Passo 3)
//
// Três fontes do mesmo padrão: estas constantes, o SQL de aviso_registrar/_aviso_proxima_mensagem
// (20261016101000) e o de _comprovante_vigia_pode (20261016100000). O ensaio da bancada
// (rodar-uma-voz.mjs) compara proximaMensagemFixa com a função SQL numa grade de horários.
// O Brasil não tem horário de verão desde 2019: Brasília = UTC−3 o ano todo.

const BRASILIA_MS = 3 * 60 * 60 * 1000;

/** Minutos desde a meia-noite (hh*60+mm). */
const hm = (h: number, m = 0) => h * 60 + m;

export const MANHA_MIN = hm(7, 30);
/** Fim da janela da manhã: a partir daqui outras fontes podem perguntar (e o acorde pode ter cartão). */
export const FIM_DA_JANELA_DA_MANHA_MIN = hm(9, 30);
export const FECHAMENTO_MIN = hm(17, 30);
/** Primeira hora (inclusive) e última (exclusive) em que o dono pode ser acordado. */
export const ACORDE_DE_MIN = hm(8);
export const ACORDE_ATE_MIN = hm(20);

/** O instante em Brasília: dia (aaaa-mm-dd), dia da semana (0 = domingo) e minutos desde a meia-noite. */
export function emBrasilia(agora: Date): { dia: string; dow: number; min: number } {
  const d = new Date(agora.getTime() - BRASILIA_MS);
  return { dia: d.toISOString().slice(0, 10), dow: d.getUTCDay(), min: d.getUTCHours() * 60 + d.getUTCMinutes() };
}

/** Das 07:30 às 09:29 de Brasília, qualquer dia: só a manhã pergunta. */
export function naJanelaDaManha(agora: Date): boolean {
  const { min } = emBrasilia(agora);
  return min >= MANHA_MIN && min < FIM_DA_JANELA_DA_MANHA_MIN;
}

/** Já passou das 09:30 de Brasília (no dia de `agora`). */
export function depoisDaJanelaDaManha(agora: Date): boolean {
  return emBrasilia(agora).min >= FIM_DA_JANELA_DA_MANHA_MIN;
}

/** Das 08:00 às 19:59 de Brasília: o portão pode acordar o dono. */
export function podeAcordar(agora: Date): boolean {
  const { min } = emBrasilia(agora);
  return min >= ACORDE_DE_MIN && min < ACORDE_ATE_MIN;
}

/** O acorde pode levar cartão de sim/não: dentro das 08–20 e depois da janela da manhã. */
export function acordeComCartao(agora: Date): boolean {
  return podeAcordar(agora) && depoisDaJanelaDaManha(agora);
}

/** aaaa-mm-dd + n dias. */
function somarDias(dia: string, n: number): string {
  const d = new Date(`${dia}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

/** O instante (UTC) de hh:mm de Brasília no dia aaaa-mm-dd. */
function as(dia: string, min: number): Date {
  const hh = String(Math.floor(min / 60)).padStart(2, "0");
  const mm = String(min % 60).padStart(2, "0");
  return new Date(`${dia}T${hh}:${mm}:00-03:00`);
}

/** A segunda-feira (aaaa-mm-dd) da semana do dia: chave semanal ("certificado vence em 20 dias"). */
export function segundaDaSemana(dia: string): string {
  const dow = new Date(`${dia}T12:00:00Z`).getUTCDay();
  return somarDias(dia, -((dow + 6) % 7));
}

export type DestinoGuardado = "proxima_fixa" | "hoje" | "escritorio";
export type MensagemFixa = "manha" | "fechamento";

/**
 * A próxima mensagem fixa que pode levar um aviso guardado (espelho de _aviso_proxima_mensagem):
 *   'hoje'       → só a manhã (07:30 de hoje se ainda não passou; senão a de amanhã);
 *   'escritorio' → só o fechamento (17:30 do próximo seg–sex);
 *   o resto      → a primeira: manhã de hoje (antes das 07:30), fechamento de hoje (seg–sex antes das
 *                  17:30), manhã de amanhã; sábado → manhã de domingo (D7) ou de segunda.
 * Feriado não entra: o guardado espera a primeira mensagem fixa que SAIR depois de `aPartirDe`.
 */
export function proximaMensagemFixa(
  agora: Date,
  destino: DestinoGuardado,
  sabado: "domingo" | "segunda" = "domingo",
): { mensagem: MensagemFixa; aPartirDe: Date } {
  const { dia, dow, min } = emBrasilia(agora);
  if (destino === "hoje") {
    return { mensagem: "manha", aPartirDe: as(min < MANHA_MIN ? dia : somarDias(dia, 1), MANHA_MIN) };
  }
  if (destino === "escritorio") {
    let d = dow >= 1 && dow <= 5 && min < FECHAMENTO_MIN ? dia : somarDias(dia, 1);
    for (let i = 0; i < 7; i++) {
      const w = new Date(`${d}T12:00:00Z`).getUTCDay();
      if (w !== 0 && w !== 6) break;
      d = somarDias(d, 1);
    }
    return { mensagem: "fechamento", aPartirDe: as(d, FECHAMENTO_MIN) };
  }
  if (min < MANHA_MIN) return { mensagem: "manha", aPartirDe: as(dia, MANHA_MIN) };
  if (dow >= 1 && dow <= 5 && min < FECHAMENTO_MIN) return { mensagem: "fechamento", aPartirDe: as(dia, FECHAMENTO_MIN) };
  if (dow === 6 && sabado === "segunda") return { mensagem: "manha", aPartirDe: as(somarDias(dia, 2), MANHA_MIN) };
  return { mensagem: "manha", aPartirDe: as(somarDias(dia, 1), MANHA_MIN) };
}
