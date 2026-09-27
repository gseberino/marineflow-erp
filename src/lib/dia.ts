// Datas sem hora ('AAAA-MM-DD') são um DIA do calendário, não um instante.
//
// `new Date('2026-09-26')` lê meia-noite em UTC — em Brasília, 25/09 às 21h. Em Contas a Pagar e
// a Receber (revisão de 27/09/2026) isso fazia a conta que vence HOJE aparecer "Em atraso" e
// "1d em atraso", a de 1º de outubro cair no grupo de setembro e o CSV sair com o dia anterior.
// É o mesmo cuidado do formatDate (src/i18n/context.tsx).

const SO_DATA = /^\d{4}-\d{2}-\d{2}$/;

/** Remonta 'AAAA-MM-DD' no fuso local, no dia que está escrito; data com hora passa direto. */
export function comoDiaLocal(data: string): Date {
  if (!SO_DATA.test(data)) return new Date(data);
  const [a, m, d] = data.split('-').map(Number);
  return new Date(a, m - 1, d);
}

/** Hoje no calendário local, 'AAAA-MM-DD'. */
export function hojeLocal(agora: Date = new Date()): string {
  const m = String(agora.getMonth() + 1).padStart(2, '0');
  const d = String(agora.getDate()).padStart(2, '0');
  return `${agora.getFullYear()}-${m}-${d}`;
}

/** Quantos dias do calendário faltam até a data (0 = hoje; negativo = já passou). */
export function diasAte(data: string, agora: Date = new Date()): number {
  const alvo = comoDiaLocal(data.slice(0, 10));
  const hoje = new Date(agora.getFullYear(), agora.getMonth(), agora.getDate());
  // round: um dia com horário de verão tem 23 ou 25 horas.
  return Math.round((alvo.getTime() - hoje.getTime()) / 86_400_000);
}
