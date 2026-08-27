// [F-DESC-01] O desconto da ORDEM repartido entre os documentos fiscais.
//
// ═══ POR QUE ISTO EXISTE ═══
//
// A OS tem DUAS camadas de desconto, e a emissão só enxergava a primeira:
//
//   1. por LINHA, já embutido em `line_total` (R$ 200,00 unitário → R$ 170,00
//      de subtotal). Este sempre chegou às notas, porque as pontes somam
//      `line_total`.
//   2. da ORDEM, em `service_orders.discount_amount` — o "Desconto Especial".
//      Este NUNCA era lido.
//
// Na OS-00075 isso produziu uma NFS-e de R$ 538,33 para uma ordem de R$ 500,00:
// serviços 538,33 + peças 192,01 = 730,34, menos 230,34 de desconto. As duas
// notas somariam 730,34 — R$ 230,34 de faturamento que não existe. Como a HBR é
// Simples Nacional, o ISS sai no DAS, que é calculado sobre a RECEITA
// declarada: receita inflada vira imposto pago a mais.
//
// ═══ A RAZÃO, E POR QUE NÃO É A MESMA DO PDF ═══
//
// O PDF calcula a fatia de cada parcela com `grand_total / subtotal`. Aqui essa
// fórmula não serve: `grand_total` já carrega imposto e taxa de cartão, que não
// são desconto e não podem entrar na conta de quanto abater de cada nota.
//
// A razão daqui isola o desconto:
//
//     razao = 1 − desconto / (serviços + peças + despesas)
//
// Sem desconto, `razao` é 1 e nada muda — nenhuma nota que já saía correta muda
// de valor.
//
// ═══ AS DESPESAS ENTRAM NA BASE, E ISSO É DELIBERADO ═══
//
// Deslocamento, custo operacional e subcontratação entram no denominador porque
// o desconto foi dado sobre o total da ordem — é assim que `recalc_so_totals`
// chega ao `grand_total`. Elas não viram nota nenhuma, então a soma das duas
// notas fica MENOR que o total da OS quando existem. Está certo: o que não é
// documento fiscal não deveria aparecer em documento fiscal.
//
// Puro (sem fetch/Deno), como `service-fiscal.ts`: roda no Vitest e no edge.

export interface TotaisDaOrdem {
  /** Soma dos `line_total` das linhas de serviço (já com o desconto por linha). */
  subtotalServicos: number;
  /** Soma dos itens de peça, a preço de venda. */
  subtotalPecas: number;
  /** Deslocamento + operacional + subcontratação. */
  despesas?: number | null;
  /** `service_orders.discount_amount` — o desconto da ORDEM. */
  desconto?: number | null;
  /** Quando o desconto foi atribuído por seção, em vez de geral. */
  descontoServicosPct?: number | null;
  descontoPecasPct?: number | null;
}

export interface DescontoRepartido {
  /** Quanto do desconto cabe aos serviços. */
  descontoServicos: number;
  /** Quanto cabe às peças. */
  descontoPecas: number;
  /** Subtotal de serviço já líquido — o que vai na NFS-e. */
  servicosLiquido: number;
  /** Subtotal de peças já líquido — o alvo da soma dos `vDesc` da NF-e. */
  pecasLiquido: number;
  /** Como a repartição foi decidida, para a tela poder dizer. */
  criterio: "sem_desconto" | "por_secao" | "proporcional";
}

const r2 = (n: number) => Math.round(n * 100) / 100;
const num = (v: number | null | undefined) => (Number.isFinite(Number(v)) ? Number(v) : 0);

/**
 * Reparte o desconto da ordem entre serviços e peças.
 *
 * Respeita a intenção quando ela foi registrada: se `discount_services_pct` ou
 * `discount_parts_pct` estiverem preenchidos, foi alguém dizendo de onde o
 * desconto saiu, e não cabe ao código adivinhar diferente. Só quando os dois
 * estão zerados — o caso comum, e o da OS-00075 — a repartição é proporcional.
 */
export function repartirDescontoDaOrdem(t: TotaisDaOrdem): DescontoRepartido {
  const servicos = r2(num(t.subtotalServicos));
  const pecas = r2(num(t.subtotalPecas));
  const despesas = r2(num(t.despesas));
  const desconto = r2(num(t.desconto));

  if (desconto <= 0) {
    return {
      descontoServicos: 0,
      descontoPecas: 0,
      servicosLiquido: servicos,
      pecasLiquido: pecas,
      criterio: "sem_desconto",
    };
  }

  const pctServicos = num(t.descontoServicosPct);
  const pctPecas = num(t.descontoPecasPct);

  if (pctServicos > 0 || pctPecas > 0) {
    // Atribuição explícita. Não se force a fechar com `desconto`: quem preencheu
    // os percentuais decidiu, e "corrigir" a decisão aqui seria inventar.
    const dS = Math.min(servicos, r2(servicos * pctServicos / 100));
    const dP = Math.min(pecas, r2(pecas * pctPecas / 100));
    return {
      descontoServicos: dS,
      descontoPecas: dP,
      servicosLiquido: r2(servicos - dS),
      pecasLiquido: r2(pecas - dP),
      criterio: "por_secao",
    };
  }

  const base = r2(servicos + pecas + despesas);
  if (base <= 0) {
    return {
      descontoServicos: 0,
      descontoPecas: 0,
      servicosLiquido: servicos,
      pecasLiquido: pecas,
      criterio: "sem_desconto",
    };
  }

  // Desconto maior que a base seria dado incoerente; abater tudo é o único
  // resultado que não produz valor negativo em documento fiscal.
  const razao = Math.max(0, 1 - desconto / base);

  const servicosLiquido = r2(servicos * razao);
  const pecasLiquido = r2(pecas * razao);

  return {
    descontoServicos: r2(servicos - servicosLiquido),
    descontoPecas: r2(pecas - pecasLiquido),
    servicosLiquido,
    pecasLiquido,
    criterio: "proporcional",
  };
}

/**
 * Distribui um desconto entre itens, proporcionalmente ao valor de cada um.
 *
 * O resíduo do arredondamento vai para o ITEM DE MAIOR VALOR, não para o
 * último: somar centavo a centavo em cima do item mais barato pode empurrá-lo
 * para desconto maior que o próprio preço, e `vDesc > vProd` é rejeição na
 * SEFAZ. A soma devolvida bate EXATAMENTE com o desconto pedido.
 */
export function distribuirDescontoNosItens(
  valores: number[],
  descontoTotal: number,
): number[] {
  const alvo = r2(num(descontoTotal));
  if (alvo <= 0 || valores.length === 0) return valores.map(() => 0);

  const total = r2(valores.reduce((a, v) => a + num(v), 0));
  if (total <= 0) return valores.map(() => 0);

  const efetivo = Math.min(alvo, total);
  const bruto = valores.map((v) => Math.min(num(v), r2(num(v) * efetivo / total)));
  const somado = r2(bruto.reduce((a, v) => a + v, 0));
  const residuo = r2(efetivo - somado);

  if (residuo !== 0) {
    let alvoIdx = 0;
    for (let i = 1; i < valores.length; i++) {
      if (num(valores[i]) > num(valores[alvoIdx])) alvoIdx = i;
    }
    // Nunca deixa o desconto passar do valor do item.
    bruto[alvoIdx] = r2(Math.min(num(valores[alvoIdx]), bruto[alvoIdx] + residuo));
  }

  return bruto;
}
