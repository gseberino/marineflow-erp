// [RATEIO-DESCONTO] Desconto GLOBAL da OS rateado entre NFS-e (serviços) e NF-e (peças).
//
// Nasceu de nota real: na 1ª emissão de produção (27/08/2026), a OS-00060 tinha desconto
// global de R$ 560,67 e ele não entrou em documento nenhum — NFS-e saiu com os serviços
// BRUTOS e a NF-e com as peças BRUTAS, somando R$ 560,67 a mais do que o cliente paga.
// Nota maior que a cobrança = imposto pago a mais + divergência com o financeiro.
//
// Regra: o desconto global é rateado PROPORCIONALMENTE às bases (serviços × peças) e,
// dentro das peças, proporcionalmente ao valor de cada item — com o resíduo de centavos
// no último item com valor, para a soma fechar exata. Determinístico: as duas pontes
// (NFS-e e NF-e) chamam esta MESMA função com as MESMAS bases e obtêm partes que somam
// exatamente o desconto total.
//
// Função PURA (sem fetch/Deno) — roda no Vitest e no edge, como product-fiscal.ts.

export interface RateioDesconto {
  /** Parte do desconto que abate a NFS-e (serviços). */
  descontoServicos: number;
  /** Parte do desconto que abate a NF-e (peças) — soma dos por-item. */
  descontoPecas: number;
  /** Desconto de cada item de peça, na ordem recebida (soma == descontoPecas). */
  descontosPorItem: number[];
}

const r2 = (n: number) => Math.round(n * 100) / 100;

/**
 * @param descontoTotal desconto global da OS (service_orders.discount_amount)
 * @param baseServicos  soma das linhas de serviço (líquidas de desconto POR LINHA)
 *                      + deslocamento faturável + operacional + subcontratação
 * @param valoresPecas  valor bruto de cada item de peça (qtd × unitário), na ordem da nota
 */
export function ratearDescontoGlobal(
  descontoTotal: number,
  baseServicos: number,
  valoresPecas: number[],
): RateioDesconto {
  const desconto = r2(Math.max(0, Number(descontoTotal) || 0));
  const servicos = Math.max(0, Number(baseServicos) || 0);
  const pecas = valoresPecas.map((v) => Math.max(0, Number(v) || 0));
  const totalPecas = pecas.reduce((a, b) => a + b, 0);
  const baseTotal = servicos + totalPecas;

  if (desconto === 0 || baseTotal === 0) {
    return { descontoServicos: 0, descontoPecas: 0, descontosPorItem: pecas.map(() => 0) };
  }

  // O desconto não pode passar da base (OS com desconto > total é dado quebrado — o
  // rateio trava no teto em vez de produzir item negativo).
  const efetivo = Math.min(desconto, r2(baseTotal));

  const descontoServicos = r2(efetivo * (servicos / baseTotal));
  const descontoPecas = r2(efetivo - descontoServicos);

  // Por item: proporcional, resíduo no ÚLTIMO item com valor (fecha o centavo).
  const descontosPorItem = pecas.map(() => 0);
  if (descontoPecas > 0 && totalPecas > 0) {
    let acumulado = 0;
    let ultimoComValor = -1;
    for (let i = 0; i < pecas.length; i++) {
      if (pecas[i] > 0) ultimoComValor = i;
    }
    for (let i = 0; i < pecas.length; i++) {
      if (pecas[i] <= 0) continue;
      if (i === ultimoComValor) {
        descontosPorItem[i] = r2(descontoPecas - acumulado);
      } else {
        const parte = r2(descontoPecas * (pecas[i] / totalPecas));
        // Nunca deixa o desconto do item passar do valor do item.
        descontosPorItem[i] = Math.min(parte, pecas[i]);
        acumulado = r2(acumulado + descontosPorItem[i]);
      }
    }
    // Guarda final: resíduo no último não pode exceder o valor do item (caso extremo de
    // item minúsculo no fim) — o excedente volta para o maior item.
    if (ultimoComValor >= 0 && descontosPorItem[ultimoComValor] > pecas[ultimoComValor]) {
      const excesso = r2(descontosPorItem[ultimoComValor] - pecas[ultimoComValor]);
      descontosPorItem[ultimoComValor] = pecas[ultimoComValor];
      let maior = 0;
      for (let i = 1; i < pecas.length; i++) {
        if (pecas[i] - descontosPorItem[i] > pecas[maior] - descontosPorItem[maior]) maior = i;
      }
      descontosPorItem[maior] = r2(descontosPorItem[maior] + excesso);
    }
  }

  return { descontoServicos, descontoPecas, descontosPorItem };
}
