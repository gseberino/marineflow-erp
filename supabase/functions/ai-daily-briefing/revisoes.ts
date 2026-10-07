// Seção "Revisões" do resumo das 07:30 (planos de manutenção com lembretes, 07/10/2026).
//
// Antes, o resumo só tinha a heurística "serviço concluído há 12+ meses" — que não sabe de plano,
// de adiamento nem de resposta do cliente. Agora os planos (view v_maintenance_plans_due) vêm
// primeiro: o que vence em 30 dias, o que venceu, quem respondeu ao lembrete nas últimas 24h e os
// lembretes que esperam o "sim" do dono; a heurística antiga fica só para embarcações SEM plano.
//
// Puro de propósito, como extrato.ts: o index.ts lê o banco, isto só escreve — testado sem rede
// (revisoes_test.ts).

export interface PlanoDoResumo {
  plan_id: string;
  vessel_id: string;
  vessel_name: string | null;
  client_name: string | null;
  name: string;
  estimated_value: number | string | null;
  next_due_on: string;
  dias_para_vencer: number;
  situacao: "em_dia" | "na_janela" | "vencida" | "adiada";
}

/** Evento client_replied das últimas 24h (maintenance_plan_events). */
export interface RespostaRecente {
  plan_id: string;
  texto: string | null;
}

export interface SecaoDeRevisoes {
  linhas: string[];
  sugestao: string | null;
  acao: string | null;
}

const MOSTRAR = 3;
const HORIZONTE = 30;

function ddmm(dia: string): string {
  const [, m, d] = dia.slice(0, 10).split("-");
  return d && m ? `${d}/${m}` : dia;
}

function num(v: number | string | null | undefined): number {
  const n = Number(v ?? 0);
  return Number.isFinite(n) ? n : 0;
}

/** Embarcações com plano ATIVO: a heurística dos 12 meses não fala delas. */
export function embarcacoesComPlano(planos: PlanoDoResumo[]): Set<string> {
  return new Set(planos.map((p) => String(p.vessel_id)));
}

export function secaoDeRevisoes(
  planos: PlanoDoResumo[],
  respostas: RespostaRecente[],
  aguardandoSim: number,
  moeda: (v: number) => string,
  hoje: string, // AAAA-MM-DD, Brasília
): SecaoDeRevisoes {
  if (planos.length === 0 && aguardandoSim === 0) return { linhas: [], sugestao: null, acao: null };

  const porVencimento = (a: PlanoDoResumo, b: PlanoDoResumo) => a.next_due_on.localeCompare(b.next_due_on);
  const vencendo = planos
    .filter((p) => (p.situacao === "em_dia" || p.situacao === "na_janela") && p.dias_para_vencer >= 0 && p.dias_para_vencer <= HORIZONTE)
    .sort(porVencimento);
  const vencidas = planos.filter((p) => p.situacao === "vencida").sort(porVencimento);
  const mes = hoje.slice(0, 7);
  const doMes = planos.filter((p) => p.situacao !== "adiada" && p.next_due_on.slice(0, 7) === mes);
  const previstoNoMes = doMes.reduce((s, p) => s + num(p.estimated_value), 0);
  const porId = new Map(planos.map((p) => [p.plan_id, p]));
  const responderam = respostas.filter((r) => porId.has(r.plan_id));

  if (vencendo.length === 0 && vencidas.length === 0 && responderam.length === 0 && aguardandoSim === 0) {
    return { linhas: [], sugestao: null, acao: null };
  }

  const nome = (p: PlanoDoResumo) => `${p.vessel_name ?? "Embarcação"} — ${p.name}`;
  const valor = (p: PlanoDoResumo) => (num(p.estimated_value) > 0 ? ` · ${moeda(num(p.estimated_value))}` : "");

  const linhas: string[] = ["", "🛠️ *Revisões*"];
  if (vencendo.length > 0) {
    linhas.push(`   Vencendo em 30 dias: *${vencendo.length}*`);
    for (const p of vencendo.slice(0, MOSTRAR)) linhas.push(`   • ${nome(p)} · ${ddmm(p.next_due_on)}${valor(p)}`);
    if (vencendo.length > MOSTRAR) linhas.push(`   …e mais ${vencendo.length - MOSTRAR}`);
  }
  if (vencidas.length > 0) {
    linhas.push(`   ⚠️ Vencidas: *${vencidas.length}*`);
    for (const p of vencidas.slice(0, MOSTRAR)) linhas.push(`   • ${nome(p)} · venceu ${ddmm(p.next_due_on)}${valor(p)}`);
    if (vencidas.length > MOSTRAR) linhas.push(`   …e mais ${vencidas.length - MOSTRAR}`);
  }
  if (responderam.length > 0) {
    linhas.push(`   💬 Responderam ao lembrete (24h): *${responderam.length}*`);
    for (const r of responderam.slice(0, MOSTRAR)) {
      const p = porId.get(r.plan_id)!;
      const texto = (r.texto ?? "").trim();
      linhas.push(`   • ${p.client_name ?? p.vessel_name ?? "Cliente"} (${p.vessel_name ?? p.name})${texto ? `: "${texto.slice(0, 50)}${texto.length > 50 ? "…" : ""}"` : ""}`);
    }
  }
  if (aguardandoSim > 0) {
    linhas.push(`   ⏳ Lembretes esperando o seu *sim*: *${aguardandoSim}*`);
  }
  if (previstoNoMes > 0) linhas.push(`   💰 Previsto em revisões neste mês: ${moeda(previstoNoMes)}`);

  // Sugestão do dia: a vencida mais antiga primeiro (é a que mais perde), senão a próxima a vencer.
  const alvo = vencidas[0] ?? vencendo[0] ?? null;
  const sugestao = alvo
    ? alvo.situacao === "vencida"
      ? `agendar a revisão vencida do *${alvo.vessel_name ?? "barco"}* (${alvo.name}, venceu em ${ddmm(alvo.next_due_on)}). Me peça *revisões do mês* que eu listo e preparo o lembrete.`
      : `oferecer a *${alvo.name}* do *${alvo.vessel_name ?? "barco"}* (vence ${ddmm(alvo.next_due_on)}). Me peça *revisões do mês* que eu preparo o lembrete — só sai com o seu sim.`
    : null;
  const acao = vencendo.length + vencidas.length > 0 ? "   • *Revisões do mês*" : null;
  return { linhas, sugestao, acao };
}
