// Idade das contas em aberto (aging) — a mesma conta para quem me deve e a quem eu devo.
//
// As faixas são as de sempre: a vencer, 1–30, 31–60, 61–90 e mais de 90 dias de atraso.
// A conta era feita só para contas a receber, dentro do hook; o lado a pagar (26/09/2026)
// precisava da MESMA régua, então ela saiu para cá, pura e testada.

export interface ContaEmAberto {
  /** Quem deve (cliente) ou a quem se deve (fornecedor/favorecido). */
  parteId: string;
  parteNome: string;
  /** 'AAAA-MM-DD' */
  vencimento: string;
  saldo: number;
}

export interface AgingBucket {
  client_id: string;
  client_name: string;
  future: number;     // A vencer (vencimento no futuro)
  days_1_30: number;  // 1–30 dias em atraso
  days_31_60: number;
  days_61_90: number;
  over_90: number;
  total: number;
}

export interface AgingReportData {
  buckets: AgingBucket[];
  totals: { future: number; days_1_30: number; days_31_60: number; days_61_90: number; over_90: number; total: number };
  generated_at: string;
}

const centavos = (v: number) => Math.round(v * 100);

/**
 * Agrupa por parte e distribui cada saldo na faixa do atraso. `hoje` é a meia-noite local
 * de referência; o vencimento também é lido à meia-noite local, para o fuso não mudar o dia.
 */
export function montarAging(contas: ContaEmAberto[], hoje: Date = new Date()): AgingReportData {
  const base = new Date(hoje);
  base.setHours(0, 0, 0, 0);

  const mapa = new Map<string, AgingBucket>();
  for (const c of contas) {
    const saldo = Number(c.saldo || 0);
    if (!(saldo > 0)) continue;
    let b = mapa.get(c.parteId);
    if (!b) {
      b = { client_id: c.parteId, client_name: c.parteNome, future: 0, days_1_30: 0, days_31_60: 0, days_61_90: 0, over_90: 0, total: 0 };
      mapa.set(c.parteId, b);
    }
    const venc = new Date(`${c.vencimento.slice(0, 10)}T00:00:00`);
    const atraso = Math.round((base.getTime() - venc.getTime()) / 86_400_000);
    b.total += saldo;
    if (atraso < 0) b.future += saldo;
    else if (atraso <= 30) b.days_1_30 += saldo;
    else if (atraso <= 60) b.days_31_60 += saldo;
    else if (atraso <= 90) b.days_61_90 += saldo;
    else b.over_90 += saldo;
  }

  const arred = (b: AgingBucket): AgingBucket => ({
    ...b,
    future: centavos(b.future) / 100,
    days_1_30: centavos(b.days_1_30) / 100,
    days_31_60: centavos(b.days_31_60) / 100,
    days_61_90: centavos(b.days_61_90) / 100,
    over_90: centavos(b.over_90) / 100,
    total: centavos(b.total) / 100,
  });

  // Quem está há mais tempo devendo vem primeiro; empate, o maior valor.
  const buckets = [...mapa.values()].map(arred).sort((a, b) => b.over_90 - a.over_90 || b.total - a.total);
  const soma = (k: keyof Omit<AgingBucket, 'client_id' | 'client_name'>) =>
    buckets.reduce((s, b) => s + centavos(b[k]), 0) / 100;
  return {
    buckets,
    totals: {
      future: soma('future'), days_1_30: soma('days_1_30'), days_31_60: soma('days_31_60'),
      days_61_90: soma('days_61_90'), over_90: soma('over_90'), total: soma('total'),
    },
    generated_at: new Date().toISOString(),
  };
}
