// Diárias de freelancers: o que a tela precisa saber sem ir ao banco.
//
// O saldo NÃO é calculado aqui: vem pronto de `conta_corrente_freelancer`/`resumo_freelancers`
// (migration 20260928190000), a mesma conta que o assistente vai usar. Aqui ficam só os rótulos,
// o período dos atalhos e a prévia do valor do dia no formulário.
import { hojeLocal } from '@/lib/dia';

export type Jornada = 'inteiro' | 'meio' | 'faltou';
export type EstadoDoSaldo = 'deve' | 'adiantado' | 'quitado' | 'semdias';
export type PeriodoDasDiarias = 'mes' | 'mes_anterior' | 'tudo';

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
  { valor: 'mes', rotulo: 'Este mês' },
  { valor: 'mes_anterior', rotulo: 'Mês anterior' },
  { valor: 'tudo', rotulo: 'Tudo' },
];

const dois = (n: number) => String(n).padStart(2, '0');

/** De e até ('AAAA-MM-DD') do atalho; "tudo" é sem limite (o banco começa no início da conta). */
export function intervaloDoPeriodo(p: PeriodoDasDiarias, hoje: string = hojeLocal()): { de: string | null; ate: string | null } {
  if (p === 'tudo') return { de: null, ate: null };
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

const DIAS = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'];

/** "qui 24/09" — o mesmo formato das mensagens do banco. */
export function diaCurto(data: string): string {
  const [a, m, d] = data.slice(0, 10).split('-').map(Number);
  return `${DIAS[new Date(a, m - 1, d).getDay()]} ${dois(d)}/${dois(m)}`;
}
