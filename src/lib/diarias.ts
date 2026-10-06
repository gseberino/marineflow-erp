// Diárias de freelancers: o que a tela precisa saber sem ir ao banco.
//
// O saldo NÃO é calculado aqui: vem pronto de `conta_corrente_freelancer`/`resumo_freelancers`
// (migration 20260928190000), a mesma conta que o assistente vai usar. Aqui ficam só os rótulos,
// o período dos atalhos e a prévia do valor do dia no formulário.
import { hojeLocal } from '@/lib/dia';

export type Jornada = 'inteiro' | 'meio' | 'faltou';
export type EstadoDoSaldo = 'deve' | 'adiantado' | 'quitado' | 'semdias';
/**
 * Períodos do extrato e do resumo. "Em aberto" e "desde o último pagamento" dependem da pessoa e
 * são calculados pelo banco (_periodo_do_atalho, migration 20261006200000); "personalizado" usa
 * De/Até escolhidos na tela (pedido do dono, 06/10/2026).
 */
export type PeriodoDasDiarias =
  | 'em_aberto' | 'desde_ultimo_pagamento' | 'ultimos_15_dias' | 'semana_atual'
  | 'mes' | 'mes_anterior' | 'tudo' | 'personalizado';

export const JORNADAS: { valor: Jornada; rotulo: string; fracao: number }[] = [
  { valor: 'inteiro', rotulo: 'Dia inteiro', fracao: 1 },
  { valor: 'meio', rotulo: 'Meio período', fracao: 0.5 },
  { valor: 'faltou', rotulo: 'Não trabalhou', fracao: 0 },
];

export function rotuloDaJornada(j: Jornada | null | undefined): string {
  return JORNADAS.find((x) => x.valor === j)?.rotulo ?? '—';
}

export const ESTADO_DO_SALDO: Record<EstadoDoSaldo, { rotulo: string; classe: string }> = {
  deve: { rotulo: 'Você deve', classe: 'text-destructive' },
  adiantado: { rotulo: 'Adiantado', classe: 'text-sky-700 dark:text-sky-400' },
  quitado: { rotulo: 'Quitado', classe: 'text-success' },
  semdias: { rotulo: 'Sem dias lançados', classe: 'text-amber-700 dark:text-amber-400' },
};

export const PERIODOS: { valor: PeriodoDasDiarias; rotulo: string }[] = [
  { valor: 'em_aberto', rotulo: 'Em aberto (a pagar)' },
  { valor: 'desde_ultimo_pagamento', rotulo: 'Desde o último pagamento' },
  { valor: 'ultimos_15_dias', rotulo: 'Últimos 15 dias' },
  { valor: 'semana_atual', rotulo: 'Esta semana' },
  { valor: 'mes', rotulo: 'Este mês' },
  { valor: 'mes_anterior', rotulo: 'Mês anterior' },
  { valor: 'tudo', rotulo: 'Tudo' },
  { valor: 'personalizado', rotulo: 'Escolher datas…' },
];

/** O nome do atalho no banco, para os períodos que o banco calcula por pessoa. */
const ATALHO_NO_BANCO: Partial<Record<PeriodoDasDiarias, string>> = {
  em_aberto: 'em_aberto',
  desde_ultimo_pagamento: 'desde_ultimo_pagamento',
  ultimos_15_dias: 'ultimos_15_dias',
  semana_atual: 'semana_atual',
};

/** O que vai para as funções do banco: De/Até, ou o atalho que o banco resolve por pessoa. */
export interface PedidoDePeriodo { de: string | null; ate: string | null; atalho: string | null }

export function pedidoDoPeriodo(
  p: PeriodoDasDiarias,
  escolhido: { de?: string | null; ate?: string | null } = {},
  hoje: string = hojeLocal(),
): PedidoDePeriodo {
  const atalho = ATALHO_NO_BANCO[p];
  if (atalho) return { de: null, ate: null, atalho };
  if (p === 'personalizado') return { de: escolhido.de || null, ate: escolhido.ate || null, atalho: null };
  return { ...intervaloDoPeriodo(p, hoje), atalho: null };
}

const dois = (n: number) => String(n).padStart(2, '0');

/** De e até ('AAAA-MM-DD') dos períodos de calendário; os demais ficam sem limite aqui. */
export function intervaloDoPeriodo(p: PeriodoDasDiarias, hoje: string = hojeLocal()): { de: string | null; ate: string | null } {
  if (p !== 'mes' && p !== 'mes_anterior') return { de: null, ate: null };
  const [a, m] = hoje.split('-').map(Number);
  const ano = p === 'mes' ? a : m === 1 ? a - 1 : a;
  const mes = p === 'mes' ? m : m === 1 ? 12 : m - 1;
  const ultimo = new Date(ano, mes, 0).getDate();
  return { de: `${ano}-${dois(mes)}-01`, ate: `${ano}-${dois(mes)}-${dois(ultimo)}` };
}

/** A mesma conta da coluna gerada `work_shifts.valor_dia` — só para a prévia do formulário. */
export function valorDoDia(jornada: Jornada, diaria: number, extras = 0, descontos = 0): number {
  const fracao = JORNADAS.find((x) => x.valor === jornada)?.fracao ?? 0;
  return Math.round((fracao * diaria + extras - descontos) * 100) / 100;
}

// ── Grade do mês ────────────────────────────────────────────────────────────────────────────

/** 'AAAA-MM' de uma data 'AAAA-MM-DD'. */
export function mesDe(data: string): string {
  return data.slice(0, 7);
}

/** Soma meses a 'AAAA-MM' (negativo volta). */
export function somarMes(mes: string, n: number): string {
  const [a, m] = mes.split('-').map(Number);
  const d = new Date(a, m - 1 + n, 1);
  return `${d.getFullYear()}-${dois(d.getMonth() + 1)}`;
}

/** Primeiro e último dia do mês, 'AAAA-MM-DD'. */
export function intervaloDoMes(mes: string): { de: string; ate: string } {
  const [a, m] = mes.split('-').map(Number);
  return { de: `${mes}-01`, ate: `${mes}-${dois(new Date(a, m, 0).getDate())}` };
}

/** Todos os dias do mês, em ordem. */
export function diasDoMes(mes: string): string[] {
  const { ate } = intervaloDoMes(mes);
  const ultimo = Number(ate.slice(8));
  return Array.from({ length: ultimo }, (_, i) => `${mes}-${dois(i + 1)}`);
}

const MESES = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];

/** "Setembro de 2026". */
export function nomeDoMes(mes: string): string {
  const [a, m] = mes.split('-').map(Number);
  const nome = MESES[m - 1];
  return `${nome.charAt(0).toUpperCase()}${nome.slice(1)} de ${a}`;
}

/**
 * Os dias de `de` a `ate` (inclusive) para lançar de uma vez; sábado e domingo só se marcados.
 * Mesma regra da ferramenta do assistente (tools/diarias.ts): dia útil por padrão.
 */
export function datasDoIntervalo(de: string, ate: string, incluir: { sabado?: boolean; domingo?: boolean } = {}): string[] {
  if (!de || !ate || de > ate) return [];
  const out: string[] = [];
  const [a, m, d] = de.split('-').map(Number);
  for (let i = 0; i < 400; i++) {
    const dia = new Date(a, m - 1, d + i);
    const iso = `${dia.getFullYear()}-${dois(dia.getMonth() + 1)}-${dois(dia.getDate())}`;
    if (iso > ate) break;
    const dow = dia.getDay();
    if ((dow !== 6 || incluir.sabado) && (dow !== 0 || incluir.domingo)) out.push(iso);
  }
  return out;
}

export function ehFimDeSemana(data: string): boolean {
  const [a, m, d] = data.split('-').map(Number);
  const dia = new Date(a, m - 1, d).getDay();
  return dia === 0 || dia === 6;
}

const DIAS = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'];

/** "qui 24/09" — o mesmo formato das mensagens do banco. */
export function diaCurto(data: string): string {
  const [a, m, d] = data.slice(0, 10).split('-').map(Number);
  return `${DIAS[new Date(a, m - 1, d).getDay()]} ${dois(d)}/${dois(m)}`;
}
