import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { lerAnalise, nomeDoMes, type Analise } from "./vigia-do-negocio.ts";

const reais = (n: number) => `R$ ${n.toFixed(2)}`;

// O retrato de 07/10/2026 (ensaio da rpc nos dados reais), resumido.
const real: Analise = {
  margem_alvo_pct: 30,
  meses: [
    { mes: "2026-05", receita: 33332.44, custo_direto: 28956.54, despesas: 29166.01, resultado: -24790.11, pronto: true, em_andamento: false },
    { mes: "2026-06", receita: 57442.92, custo_direto: 14020.62, despesas: 12977.49, resultado: 30444.81, pronto: true, em_andamento: false },
    { mes: "2026-07", receita: 47447.36, custo_direto: 16901.39, despesas: 11301.13, resultado: 19244.84, pronto: true, em_andamento: false },
    { mes: "2026-08", receita: 28699.86, custo_direto: 15171.07, despesas: 6728.01, resultado: 6800.78, pronto: false, em_andamento: false },
    { mes: "2026-10", receita: 7600, custo_direto: 550, despesas: 0.43, resultado: 7049.57, pronto: false, em_andamento: true },
  ],
  equilibrio: { meses_usados: 3, so_meses_prontos: true, margem_de_contribuicao_pct: 56.7, despesas_fixas_por_mes: 17814.88, receita_media_por_mes: 46074.24, receita_minima_por_mes: 31430.81 },
  por_sistema: [
    { sistema: "eletrico_dc", os: 4, receita: 64293.27, lucro: 30507.42, margem_pct: 47.5, pct_da_receita: 62.1 },
    { sistema: "sem_sistema", os: 6, receita: 31956.88, lucro: 16378.68, margem_pct: 51.3, pct_da_receita: 30.9 },
  ],
  em_alta: [
    { categoria: "Compras de mercadorias", mes: "2026-07", no_mes: 8101.54, media_3_meses_antes: 3673.9, alta_pct: 121 },
    { categoria: "Aluguel e condomínio", mes: "2026-07", no_mes: 4620.53, media_3_meses_antes: 1386.75, alta_pct: 233 },
  ],
  mao_de_obra_sem_os: { diarias: 31, valor: 3630 },
};

Deno.test("nomeDoMes", () => assertEquals(nomeDoMes("2026-07"), "jul/26"));

Deno.test("dado real de 07/10: julho acima do equilíbrio, despesa em alta, elétrico DC concentra → marketing", () => {
  const r = lerAnalise(real, reais);
  assertStringIncludes(r.constatacoes[0], "✅ jul/26 faturou R$ 47447.36, acima do mínimo de R$ 31430.81");
  assertStringIncludes(r.constatacoes[1], "*Compras de mercadorias* em jul/26: R$ 8101.54 contra R$ 3673.90");
  assertStringIncludes(r.constatacoes[1], "Outras 1 categorias");
  assertStringIncludes(r.constatacoes[2], "*elétrico DC* trouxe 62,1% da receita");
  assertStringIncludes(r.sugestao!, "divulgação de *elétrico DC*");
  // As ressalvas: agosto não fechado e as diárias sem OS.
  assertStringIncludes(r.constatacoes[3], "ago/26");
  assertStringIncludes(r.constatacoes[3], "R$ 3630.00 de diárias sem OS");
});

Deno.test("maio/26 de verdade: faturou acima do mínimo médio mas deu prejuízo — o resultado real vem primeiro", () => {
  const r = lerAnalise({ ...real, meses: real.meses!.slice(0, 1) }, reais);
  assertStringIncludes(r.constatacoes[0], "⚠️ mai/26 fechou com prejuízo de R$ 24790.11: faturou R$ 33332.44");
  assertStringIncludes(r.constatacoes[0], "R$ 28956.54 de custo direto");
  assertStringIncludes(r.sugestao!, "subir a margem ou o volume");
});

Deno.test("sistema com margem abaixo do alvo (2+ OS) vira constatação de preço", () => {
  const r = lerAnalise({ ...real, por_sistema: [{ sistema: "refrigeracao", os: 3, receita: 3000, lucro: 600, margem_pct: 20, pct_da_receita: 10 }] }, reais);
  assert(r.constatacoes.some((c) => c.includes("*refrigeração* deram 20% de margem (alvo: 30%)")));
});

Deno.test("sem dado nenhum, nada a dizer", () => {
  const r = lerAnalise({}, reais);
  assertEquals(r.constatacoes, []);
  assertEquals(r.sugestao, null);
});

Deno.test("faturou abaixo do mínimo mas fechou positivo: avisa e explica", () => {
  const r = lerAnalise({ ...real, meses: [{ mes: "2026-08", receita: 20000, custo_direto: 5000, despesas: 6000, resultado: 9000, pronto: true, em_andamento: false }] }, reais);
  assertStringIncludes(r.constatacoes[0], "⚠️ ago/26 faturou R$ 20000.00, abaixo dos R$ 31430.81");
  assertStringIncludes(r.constatacoes[0], "custos do mês ficaram abaixo da média");
});
