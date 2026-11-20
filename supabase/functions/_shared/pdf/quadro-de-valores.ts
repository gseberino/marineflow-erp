/**
 * O quadro de valores do orçamento/OS — as linhas acima do VALOR TOTAL — num lugar só.
 *
 * Quem usa: o PDF (linhasDoResumo, em documento.ts, desenha estas linhas em HTML) e o resumo em
 * TEXTO do WhatsApp (src/lib/quote-whatsapp-summary.ts na tela e o espelho _shared/pdf/resumo-whatsapp.ts
 * no assistente). Antes cada um montava o seu quadro, e o texto divergia do PDF: com o Deslocamento
 * desmarcado as linhas do texto não somavam o total, e os impostos nunca apareciam nele.
 *
 * A regra (decisão do dono, 20/11/2026; para o texto: "Sim, mesma regra do PDF"):
 *  - as parcelas são as de calc_so_totals: serviços + peças + deslocamento faturável + despesas +
 *    terceiros − desconto + impostos + taxa de cartão;
 *  - deslocamento, impostos e taxa de cartão desmarcados (ocultos) viram UMA linha "Outros encargos"
 *    com a soma deles — o valor continua no total, que é o do banco;
 *  - desconto desmarcado: o desconto GERAL vira uma linha neutra "Ajustes" (negativa). Encargo
 *    negativo não existe, e juntar desconto com encargo numa linha só esconderia os dois.
 * Assim as linhas visíveis sempre somam o total.
 *
 * Importável dos dois lados (Deno e Vite): nenhum import, nada de navegador.
 */

/** Os campos da ordem que o quadro lê (os mesmos de service_orders). */
export interface OrdemDoQuadro {
  labor_cost_total?: number | null;
  parts_cost_total?: number | null;
  operational_cost_total?: number | null;
  subcontract_cost_total?: number | null;
  travel_cost_total?: number | null;
  is_travel_billable?: boolean | null;
  discount_amount?: number | null;
  discount_services_pct?: number | null;
  discount_parts_pct?: number | null;
  tax_amount?: number | null;
  card_fee_amount?: number | null;
  card_installments?: number | null;
}

/** O que entra no quadro. Cada lado traduz as suas opções para isto. */
export interface OpcoesDoQuadro {
  /** A linha "Serviços" entra. */
  servicos: boolean;
  /** A linha "Peças e materiais" entra. */
  pecas: boolean;
  /** Linhas próprias; desmarcadas, o valor vai para "Outros encargos". */
  deslocamento: boolean;
  impostos: boolean;
  taxaCartao: boolean;
  /** Linha própria do desconto geral; desmarcado, ele vai para "Ajustes". */
  desconto: boolean;
  /** Soma dos descontos dados item a item: com ela, o desconto do quadro é "adicional". */
  descontoDosItens?: number;
}

export interface LinhaDoQuadro {
  rotulo: string;
  /** Sempre positivo; `negativo` diz se subtrai. */
  valor: number;
  negativo: boolean;
  /**
   * 'detalhe' é a quebra do desconto por percentual (↳ …): explica a linha seguinte e NÃO entra
   * na soma. 'destaque' é a linha do desconto que vem depois dessa quebra.
   */
  tipo: 'normal' | 'detalhe' | 'destaque';
}

const arred2 = (v: number) => Math.round(v * 100) / 100;
const num = (v: unknown) => Number(v) || 0;

export function linhasDoQuadroDeValores(so: OrdemDoQuadro, o: OpcoesDoQuadro): LinhaDoQuadro[] {
  const linhas: LinhaDoQuadro[] = [];
  const add = (rotulo: string, valor: number, negativo = false, tipo: LinhaDoQuadro['tipo'] = 'normal') =>
    linhas.push({ rotulo, valor, negativo, tipo });

  const descontoGeral = Math.max(0, num(so.discount_amount));
  const deslocamento = so.is_travel_billable === false ? 0 : num(so.travel_cost_total);
  const imposto = num(so.tax_amount);
  const taxaCartao = num(so.card_fee_amount);
  const operacional = num(so.operational_cost_total);
  const terceiros = num(so.subcontract_cost_total);

  if (o.servicos) add('Serviços', num(so.labor_cost_total));
  if (o.pecas) add('Peças e materiais', num(so.parts_cost_total));
  if (o.deslocamento && deslocamento > 0) add('Deslocamento / logística', deslocamento);
  if (operacional > 0) add('Outras despesas', operacional);
  if (terceiros > 0) add('Serviços de terceiros', terceiros);

  if (o.desconto && descontoGeral > 0) {
    // Com desconto nos itens também, o do quadro é "adicional" — senão o cliente lê o mesmo
    // desconto duas vezes.
    const rotulo = (o.descontoDosItens ?? 0) > 0 ? 'Desconto adicional' : 'Desconto';
    const sPct = num(so.discount_services_pct);
    const pPct = num(so.discount_parts_pct);
    if (sPct > 0 || pPct > 0) {
      const dSvc = arred2(num(so.labor_cost_total) * sPct / 100);
      const dPts = arred2(num(so.parts_cost_total) * pPct / 100);
      if (dSvc > 0) add(`↳ ${rotulo} em serviços (${sPct}%)`, dSvc, true, 'detalhe');
      if (dPts > 0) add(`↳ ${rotulo} em peças (${pPct}%)`, dPts, true, 'detalhe');
      add(rotulo, descontoGeral, true, 'destaque');
    } else {
      add(rotulo, descontoGeral, true);
    }
  }

  if (o.impostos && imposto > 0) add('Impostos', imposto);
  if (o.taxaCartao && taxaCartao > 0) {
    add(`Taxa de cartão${so.card_installments ? ` (${so.card_installments}x)` : ''}`, taxaCartao);
  }

  // O que foi desmarcado continua no total do banco; aqui volta ao quadro com rótulo neutro.
  const encargos = arred2(
    (o.deslocamento ? 0 : Math.max(0, deslocamento))
    + (o.impostos ? 0 : imposto)
    + (o.taxaCartao ? 0 : taxaCartao),
  );
  if (encargos > 0) add('Outros encargos', encargos);
  if (!o.desconto && descontoGeral > 0) add('Ajustes', descontoGeral, true);

  return linhas;
}

/** A soma das linhas que contam (sem as quebras ↳). É o que o quadro promete: igual ao total. */
export function somaDoQuadro(linhas: LinhaDoQuadro[]): number {
  return arred2(linhas.reduce((s, l) => (l.tipo === 'detalhe' ? s : s + (l.negativo ? -l.valor : l.valor)), 0));
}

const brl = (v: number) =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);

/**
 * O quadro em texto de WhatsApp: "• Serviços: R$ 1.000,00", "• Desconto: −R$ 50,00"; a quebra por
 * percentual sai recuada, sem marcador ("   ↳ Desconto em serviços (10%): −R$ 30,00").
 */
export function quadroDeValoresEmTexto(linhas: LinhaDoQuadro[]): string[] {
  return linhas.map((l) => {
    const valor = `${l.negativo ? '−' : ''}${brl(l.valor)}`;
    return l.tipo === 'detalhe' ? `   ${l.rotulo}: ${valor}` : `• ${l.rotulo}: ${valor}`;
  });
}
