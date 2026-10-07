// Leitura da análise do negócio (rpc analise_do_negocio, migration 20261007100000) em constatações
// curtas — o que o resumo da manhã (segunda-feira e dia 1) e o sino dizem ao dono (07/10/2026).
//
// Pedido do dono: avisar quando a margem precisa de ajuste para não ter prejuízo, quando uma despesa
// subiu muito em relação aos meses anteriores e qual tipo de serviço concentra a receita (para
// trabalhar marketing em cima). Regras desta leitura:
//   · conclusão sobre resultado só com mês FECHADO ("Mês pronto?"); mês aberto vira ressalva;
//   · no máximo 3 constatações e 1 sugestão — o resumo já é longo;
//   · número sempre com a base ("contra R$ X de média") — "subiu" sozinho não ajuda a decidir.

export interface Analise {
  margem_alvo_pct?: number;
  meses?: { mes: string; receita: number; custo_direto: number; despesas: number; resultado: number; pronto: boolean; em_andamento: boolean }[];
  equilibrio?: {
    meses_usados?: number; so_meses_prontos?: boolean; margem_de_contribuicao_pct?: number | null;
    despesas_fixas_por_mes?: number | null; receita_media_por_mes?: number | null; receita_minima_por_mes?: number | null;
  };
  por_sistema?: { sistema: string; os: number; receita: number; lucro: number; margem_pct: number | null; pct_da_receita: number | null }[];
  em_alta?: { categoria: string; mes: string; no_mes: number; media_3_meses_antes: number; alta_pct: number | null }[];
  mao_de_obra_sem_os?: { diarias: number; valor: number };
}

const NOME_DO_SISTEMA: Record<string, string> = {
  eletrico_dc: "elétrico DC", eletrico_ac: "elétrico AC", eletronico: "eletrônica", refrigeracao: "refrigeração",
  hidraulico: "hidráulica", gas: "gás", mecanico: "mecânica", estrutural: "estrutural", sem_sistema: "sem sistema definido",
};
export const nomeDoSistema = (s: string) => NOME_DO_SISTEMA[s] ?? s.replace(/_/g, " ");

const MES = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"];
export const nomeDoMes = (aaaaMm: string) => `${MES[Number(aaaaMm.slice(5, 7)) - 1] ?? aaaaMm}/${aaaaMm.slice(2, 4)}`;

/** A partir de quanto da receita um sistema "concentra" (vira sugestão de marketing). */
export const CONCENTRACAO_PCT = 40;

export function lerAnalise(a: Analise, reais: (n: number) => string): { constatacoes: string[]; sugestao: string | null; titulo: string } {
  const constatacoes: string[] = [];
  let sugestao: string | null = null;
  const meses = a.meses ?? [];
  const eq = a.equilibrio ?? {};
  const fechados = meses.filter((m) => m.pronto);
  const ultimoFechado = fechados[fechados.length - 1];
  const abertos = meses.filter((m) => !m.pronto && !m.em_andamento).map((m) => nomeDoMes(m.mes));

  // 1) Ponto de equilíbrio × último mês fechado
  // O resultado REAL do mês vem primeiro: maio/26 faturou acima do mínimo médio e fechou com
  // prejuízo de R$ 24,8 mil (custos do mês muito acima da média) — "acima do mínimo" ali mentiria.
  if (ultimoFechado && (ultimoFechado.resultado < 0 || eq.receita_minima_por_mes)) {
    const min = eq.receita_minima_por_mes ?? 0;
    const r = ultimoFechado.receita;
    const base = eq.so_meses_prontos ? "" : " (estimativa: ainda há poucos meses fechados)";
    const sugestaoDeMargem = `subir a margem ou o volume: com margem de contribuição de ${eq.margem_de_contribuicao_pct}% e ${reais(eq.despesas_fixas_por_mes ?? 0)} de despesas fixas por mês, cada ${reais(1000)} vendido a mais cobre ${reais(10 * (eq.margem_de_contribuicao_pct ?? 0))} de custo fixo. Me peça a margem por serviço para ver onde ajustar.`;
    if (ultimoFechado.resultado < 0) {
      const custos = ultimoFechado.custo_direto + ultimoFechado.despesas;
      constatacoes.push(`⚠️ ${nomeDoMes(ultimoFechado.mes)} fechou com prejuízo de ${reais(-ultimoFechado.resultado)}: faturou ${reais(r)} e gastou ${reais(custos)} (${reais(ultimoFechado.custo_direto)} de custo direto, ${reais(ultimoFechado.despesas)} de despesas).` +
        (min && r < min ? ` O mínimo para não ter prejuízo é ${reais(min)}/mês${base}.` : ""));
      sugestao = sugestaoDeMargem;
    } else if (min && r < min) {
      constatacoes.push(`⚠️ ${nomeDoMes(ultimoFechado.mes)} faturou ${reais(r)}, abaixo dos ${reais(min)} que a HBR precisa por mês para não ter prejuízo${base}. Fechou positivo (${reais(ultimoFechado.resultado)}) porque os custos do mês ficaram abaixo da média.`);
      sugestao = sugestaoDeMargem;
    } else {
      constatacoes.push(`✅ ${nomeDoMes(ultimoFechado.mes)} faturou ${reais(r)}, acima do mínimo de ${reais(min)}/mês para não ter prejuízo${base}. Resultado: ${reais(ultimoFechado.resultado)}.`);
    }
  }

  // 2) Despesa em alta (a maior)
  const alta = (a.em_alta ?? [])[0];
  if (alta) {
    const quanto = alta.alta_pct != null ? `+${alta.alta_pct}%` : "nova";
    constatacoes.push(`📈 *${alta.categoria}* em ${nomeDoMes(alta.mes)}: ${reais(alta.no_mes)} contra ${reais(alta.media_3_meses_antes)} de média nos 3 meses anteriores (${quanto}).` +
      ((a.em_alta ?? []).length > 1 ? ` Outras ${(a.em_alta ?? []).length - 1} categorias subiram; me peça a análise do negócio.` : ""));
  }

  // 3) Concentração da receita / margem por sistema
  const sistemas = (a.por_sistema ?? []).filter((s) => s.sistema !== "sem_sistema");
  const forte = sistemas.find((s) => (s.pct_da_receita ?? 0) >= CONCENTRACAO_PCT);
  const alvo = a.margem_alvo_pct ?? 30;
  const fraco = sistemas.find((s) => s.os >= 2 && s.margem_pct != null && s.margem_pct < alvo);
  if (fraco) {
    constatacoes.push(`🔧 Serviços de *${nomeDoSistema(fraco.sistema)}* deram ${fraco.margem_pct}% de margem (alvo: ${alvo}%) em ${fraco.os} OS — vale rever o preço.`);
  } else if (forte) {
    constatacoes.push(`🎯 *${nomeDoSistema(forte.sistema)}* trouxe ${forte.pct_da_receita}% da receita das OS (${reais(forte.receita)}, margem ${forte.margem_pct}%).`);
  }
  if (forte && !sugestao) {
    sugestao = `trabalhar a divulgação de *${nomeDoSistema(forte.sistema)}*: é ${forte.pct_da_receita}% da receita das OS. Anúncio, post com antes/depois de um serviço feito ou contato com clientes antigos desse tipo de serviço trazem mais do que já dá certo.`;
  }

  // Ressalvas que mudam a leitura
  const ressalvas: string[] = [];
  if (abertos.length) ressalvas.push(`meses ainda não fechados (${abertos.join(", ")}) ficaram de fora`);
  const sem = a.mao_de_obra_sem_os;
  if (sem && sem.diarias > 0) ressalvas.push(`${reais(sem.valor)} de diárias sem OS ligada — a margem por serviço está otimista`);
  if (ressalvas.length && constatacoes.length) constatacoes.push(`_Obs.: ${ressalvas.join("; ")}._`);

  return { constatacoes: constatacoes.slice(0, 4), sugestao, titulo: "📊 *Vigia do negócio*" };
}
