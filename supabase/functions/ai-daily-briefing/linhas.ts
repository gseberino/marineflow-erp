// Linhas soltas do resumo da manhã — lógica pura, sem banco.
//
// Consertos de 15/10/2026 (Passo 0 do "secretário"), sem mudar o formato do resumo:
//   · Propostas de lançamento: somavam em valor absoluto saída, entrada e transferência
//     (51 = 46 saídas + 4 entradas + 1 transferência viravam "R$ 35.044,76" de uma coisa só).
//   · Contadores zerados ("Agendamentos hoje: 0", "Aprovações da IA pendentes: 0") ocupavam
//     linha todo dia.
//   · Orçamento sem número nem barco ("Cliente Final" repetido não diz qual é) e nome de contato
//     com quebra de linha (o da Climatec partia a lista em três linhas).
//   · O resumo que falhava ao enviar desistia em ~20 min (3 tentativas); em 09 e 13/10 o WhatsApp
//     voltou antes das 09:00 e a manhã não chegou.

import { diaBR } from "../_shared/pdf/datas.ts";

/** "rótulo: *n*" — ou null quando é zero (zero não ocupa linha). */
export function linhaSeHouver(rotulo: string, n: number | null | undefined): string | null {
  const v = Number(n ?? 0);
  return v > 0 ? `${rotulo}: *${v}*` : null;
}

/** Nome de contato numa linha só: espaços e quebras viram um espaço; corta em `max` com "…". */
export function nomeDeContato(s: string | null | undefined, max = 40): string {
  const limpo = String(s ?? "").replace(/\s+/g, " ").trim();
  if (limpo.length <= max) return limpo;
  return `${limpo.slice(0, max - 1).trimEnd()}…`;
}

export interface OrcamentoDoResumo {
  numero: string;
  cliente: string;
  barco: string | null;
  valor: number;
  dias: number;
  expired: boolean;
  expiringSoon: boolean;
}

/** "   • ORÇ-00095 · MP MOTOR HOMES (Industrailer Scania) — R$ 14.461,00 · parado 8d" */
export function linhaDoOrcamento(q: OrcamentoDoResumo, fmt: (v: number) => string): string {
  const tag = q.expired ? " · ⚠️ expirado" : q.expiringSoon ? " · ⏳ expira em breve" : "";
  const barco = q.barco ? ` (${q.barco})` : "";
  return `   • ${q.numero} · ${q.cliente}${barco} — ${fmt(q.valor)} · parado ${q.dias}d${tag}`;
}

/**
 * "🧾 Propostas de lançamento esperando você: *51* — 46 saídas (…) · 4 entradas (…) · 1 transferência (…)"
 * Conta e soma por tipo (os valores da fila são sempre positivos; o sentido está no `kind`). Alerta do
 * vigilante (anomaly) não é proposta de lançamento. null quando não há proposta.
 */
export function linhaDasPropostas(
  rows: Array<{ kind: string | null; suggested_amount: number | string | null }>,
  fmt: (v: number) => string,
): string | null {
  const grupos: Array<{ kinds: string[] | null; um: string; varios: string; n: number; soma: number }> = [
    { kinds: ["create_payable"], um: "saída", varios: "saídas", n: 0, soma: 0 },
    { kinds: ["create_receivable"], um: "entrada", varios: "entradas", n: 0, soma: 0 },
    { kinds: ["internal_transfer"], um: "transferência", varios: "transferências", n: 0, soma: 0 },
    { kinds: null, um: "outra", varios: "outras", n: 0, soma: 0 },
  ];
  let total = 0;
  for (const r of rows ?? []) {
    if (r.kind === "anomaly") continue;
    const g = grupos.find((x) => x.kinds?.includes(String(r.kind))) ?? grupos[grupos.length - 1];
    g.n++;
    g.soma += Math.abs(Number(r.suggested_amount ?? 0));
    total++;
  }
  if (total === 0) return null;
  const partes = grupos.filter((g) => g.n > 0).map((g) => `${g.n} ${g.n === 1 ? g.um : g.varios} (${fmt(Math.round(g.soma * 100) / 100)})`);
  return `🧾 Propostas de lançamento esperando você: *${total}* — ${partes.join(" · ")}`;
}

/** Brasília não tem horário de verão desde 2019: o deslocamento é fixo. */
const FUSO_BR = "-03:00";
/**
 * Intervalo REAL entre tentativas, medido na fila: o worker reagenda a falha para +5 min, mas roda
 * de 5 em 5 min (cron) e a nova hora cai segundos depois da volta seguinte — a tentativa sai 10 min
 * depois (resumos de 09 e 13/10/2026: 07:35, 07:45, 07:55). Com 5 min aqui, as 19 tentativas das
 * 07:30 iriam até ~10:35, não até 09:00 (e o "não chegou" do vigia só sairia às 11:05).
 */
const INTERVALO_DA_FILA_MS = 10 * 60_000;

/**
 * Quantas tentativas a fila precisa para seguir tentando até `horaBR` ("09:00") de hoje, em
 * Brasília: uma a cada 10 min a partir de agora. Nunca menos que 3 (o padrão da fila).
 */
export function tentativasAte(horaBR: string, agora: Date): number {
  const limite = new Date(`${diaBR(agora)}T${horaBR}:00${FUSO_BR}`).getTime();
  const intervalos = Math.ceil((limite - agora.getTime()) / INTERVALO_DA_FILA_MS);
  return Math.max(3, intervalos + 1);
}
