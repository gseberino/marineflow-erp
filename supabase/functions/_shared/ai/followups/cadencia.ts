// Cadência das missões de acompanhamento ("Deixar a IA acompanhar") — funções PURAS.
//
// Parâmetros calibrados pela pesquisa do dossiê (plans/marineflow-ia-acompanha.md, §6):
// janela seg-sex 9h-18h de Brasília (mais estrita que o CDC), cadência contada PARA TRÁS do
// prazo (D-7, D-3, D-1) e, sem prazo, 2d / 4d / 7d; nunca dois toques no mesmo dia. Diferente
// da cadência de cobrança (comms/cadence.ts, 6 toques), aqui o teto vem da missão (3 para
// fornecedor, 2 para cliente — decisão do dono de 30/08/2026).

const FUSO = "America/Sao_Paulo";

/** Partes de data/hora em Brasília, sem depender do fuso do servidor. */
export function partesBrasilia(agora: Date): { diaSemana: number; hora: number; dataISO: string } {
  const fmt = new Intl.DateTimeFormat("en-US", {
    timeZone: FUSO, weekday: "short", hour: "2-digit", hour12: false,
    year: "numeric", month: "2-digit", day: "2-digit",
  });
  const p: Record<string, string> = {};
  for (const { type, value } of fmt.formatToParts(agora)) p[type] = value;
  const dias: Record<string, number> = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };
  return {
    diaSemana: dias[p.weekday] ?? 0,
    hora: parseInt(p.hour, 10) % 24,
    dataISO: `${p.year}-${p.month}-${p.day}`,
  };
}

/** Seg-sex, das 9h às 17h59 de Brasília. */
export function dentroDaJanela(agora: Date = new Date()): boolean {
  const { diaSemana, hora } = partesBrasilia(agora);
  return diaSemana >= 1 && diaSemana <= 5 && hora >= 9 && hora < 18;
}

/** Dois toques no mesmo dia (de Brasília) é proibido. */
export function jaTocouHoje(ultimoToqueEm: string | null | undefined, agora: Date = new Date()): boolean {
  if (!ultimoToqueEm) return false;
  const u = new Date(ultimoToqueEm);
  if (isNaN(u.getTime())) return false;
  return partesBrasilia(u).dataISO === partesBrasilia(agora).dataISO;
}

const DIA = 86_400_000;

/**
 * Próxima abertura da janela (dia útil, 9h de Brasília = 12:00Z; o Brasil não tem horário de
 * verão desde 2019). Se agora ainda é antes das 9h de um dia útil, é hoje mesmo.
 * É onde cai uma mensagem aprovada fora do horário: agendada, nunca perdida nem enviada à noite.
 */
export function proximaJanela(agora: Date = new Date()): Date {
  for (let i = 0; i < 8; i++) {
    const dia = new Date(agora.getTime() + i * DIA);
    const { diaSemana, dataISO, hora } = partesBrasilia(dia);
    if (diaSemana < 1 || diaSemana > 5) continue;
    if (i === 0 && hora >= 9) continue;
    return new Date(`${dataISO}T12:00:00Z`);
  }
  return new Date(agora.getTime() + DIA);
}

/**
 * Quando cai o próximo toque depois do toque de número `toqueFeito` (1-based).
 * Com prazo: os toques restantes se distribuem para trás do prazo (D-7, D-3, D-1); se o prazo
 * já está perto demais, o próximo é amanhã — nunca hoje de novo. Sem prazo: +2d, +4d, +7d.
 * Devolve null quando não há mais toques (a missão passa a esperar resposta/prazo).
 */
export function proximoToqueApos(
  toqueFeito: number,
  maxToques: number,
  prazoFinal: string | null | undefined,
  agora: Date = new Date(),
): Date | null {
  if (toqueFeito >= maxToques) return null;
  const amanha = new Date(agora.getTime() + DIA);
  const prazo = prazoFinal ? new Date(prazoFinal) : null;
  if (prazo && !isNaN(prazo.getTime())) {
    // Marcos para trás do prazo, do mais distante ao mais próximo. Com 2 toques usa D-3/D-1;
    // com 3, D-7/D-3/D-1. O toque que acabou de sair ocupa o primeiro marco livre.
    const marcos = maxToques >= 3 ? [7, 3, 1] : [3, 1];
    const proximoMarco = marcos[Math.min(toqueFeito, marcos.length - 1)];
    const candidato = new Date(prazo.getTime() - proximoMarco * DIA);
    return candidato > amanha ? candidato : amanha;
  }
  const intervalos = [2, 4, 7];
  const dias = intervalos[Math.min(toqueFeito - 1, intervalos.length - 1)];
  return new Date(agora.getTime() + dias * DIA);
}

/**
 * Depois do último toque possível, quanto tempo esperar resposta antes de devolver ao dono:
 * até o prazo, ou 3 dias, o que vier primeiro.
 */
export function esperaFinalEsgotada(
  ultimoToqueEm: string | null | undefined,
  prazoFinal: string | null | undefined,
  agora: Date = new Date(),
): boolean {
  if (prazoFinal && new Date(prazoFinal).getTime() <= agora.getTime()) return true;
  if (!ultimoToqueEm) return false;
  return agora.getTime() - new Date(ultimoToqueEm).getTime() >= 3 * DIA;
}
