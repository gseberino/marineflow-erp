/**
 * Mapa de cotação — cálculo puro do comparativo entre fornecedores.
 *
 * Três tradições do mercado, reunidas:
 *   • Mapa de cotação (BR): fornecedores em colunas ordenadas do melhor PACOTE ao
 *     pior, com selo no vencedor. "Pacote" = itens cotados − desconto + frete, e não
 *     a soma nua dos unitários — quem tem frete alto pode perder mesmo com item barato.
 *   • Compare Order Lines (Odoo): decisão por LINHA, permitindo dividir a compra
 *     entre fornecedores (a cesta escolhida).
 *   • Bid tabulation (construção): sinalizar quem desvia muito da média da linha,
 *     porque desvio grande normalmente é erro de entendimento do item, não preço bom.
 *
 * O que este arquivo NÃO faz: decidir. Ele calcula o melhor por linha, o melhor
 * pacote e o custo da cesta; a escolha é sempre do usuário.
 */

/** Acima deste desvio para cima da média da linha, a oferta é sinalizada. */
export const OUTLIER_THRESHOLD = 0.3;

export interface ComparisonResponseInput {
  id: string;
  supplier_id: string;
  quote_request_item_id: string | null;
  unit_price: number | string | null;
  lead_time_days: number | null;
  confirmed: boolean;
  source: string;
}

export interface ComparisonItemInput {
  id: string;
  position: number;
  description: string;
  quantity: number | string;
  product_id: string | null;
}

export interface ComparisonSupplierInput {
  id: string;
  name: string;
  /** custos de pacote informados na negociação, não por item */
  freight?: number | string | null;
  discount?: number | string | null;
  payment_terms?: string | null;
  quote_valid_until?: string | null;
}

export interface Offer {
  responseId: string;
  supplierId: string;
  unitPrice: number;
  lineTotal: number;
  leadTimeDays: number | null;
  confirmed: boolean;
  source: string;
  /** menor unitário da linha */
  isBestPrice: boolean;
  /** acima de OUTLIER_THRESHOLD da média da linha */
  isOutlier: boolean;
  /** quanto acima (ou abaixo) da média da linha, em fração */
  deviationFromMean: number;
}

export interface ComparisonRow {
  itemId: string;
  position: number;
  description: string;
  quantity: number;
  /** ofertas indexadas por fornecedor; ausência = fornecedor não cotou este item */
  offers: Record<string, Offer>;
  offerCount: number;
  bestUnitPrice: number | null;
  meanUnitPrice: number | null;
  /** true quando ninguém cotou — o buraco que impede fechar a cotação */
  unquoted: boolean;
}

export interface SupplierPackage {
  supplierId: string;
  name: string;
  /** itens que o fornecedor cotou, de quantos existem */
  quotedItems: number;
  itemsTotal: number;
  freight: number;
  discount: number;
  /** itensTotal − desconto + frete: o número que ordena as colunas */
  packageTotal: number;
  /** maior prazo entre os itens cotados — é o que define quando a obra anda */
  maxLeadTimeDays: number | null;
  paymentTerms: string | null;
  validUntil: string | null;
  /** cotou tudo? pacote incompleto não é comparável de igual para igual */
  isComplete: boolean;
  /** menor packageTotal entre os pacotes COMPLETOS */
  isBestPackage: boolean;
}

export interface BasketLine {
  itemId: string;
  supplierId: string;
  lineTotal: number;
}

export interface QuoteComparison {
  rows: ComparisonRow[];
  packages: SupplierPackage[];
  /** total se comprar tudo do melhor pacote completo (null se nenhum for completo) */
  bestPackageTotal: number | null;
  /** total pegando o menor preço de cada linha, ainda que de fornecedores diferentes */
  bestPerLineTotal: number;
  /** o que se economiza dividindo a compra em vez de comprar tudo de um só */
  splitSavings: number;
  itemCount: number;
  /** itens que ninguém cotou */
  unquotedCount: number;
  respondedSupplierIds: string[];
}

function num(v: number | string | null | undefined): number {
  if (v === null || v === undefined) return 0;
  const n = typeof v === 'number' ? v : parseFloat(v);
  return Number.isFinite(n) ? n : 0;
}

export function buildQuoteComparison(
  items: ComparisonItemInput[],
  responses: ComparisonResponseInput[],
  suppliers: ComparisonSupplierInput[],
): QuoteComparison {
  const sortedItems = [...items].sort((a, b) => a.position - b.position);

  // Só respostas com preço e item entram no comparativo; resposta solta (ex.: o
  // fornecedor mandou um "bom dia") não pode virar coluna nem média.
  const priced = responses.filter(r => r.quote_request_item_id && num(r.unit_price) > 0);
  const respondedSupplierIds = [...new Set(priced.map(r => r.supplier_id))];

  const rows: ComparisonRow[] = sortedItems.map(item => {
    const qty = num(item.quantity);
    const mine = priced.filter(r => r.quote_request_item_id === item.id);

    const prices = mine.map(r => num(r.unit_price));
    const best = prices.length ? Math.min(...prices) : null;
    const mean = prices.length ? prices.reduce((s, p) => s + p, 0) / prices.length : null;

    const offers: Record<string, Offer> = {};
    for (const r of mine) {
      const unitPrice = num(r.unit_price);
      const deviation = mean && mean > 0 ? (unitPrice - mean) / mean : 0;
      // Com uma só oferta não existe desvio a apontar — a média É ela.
      const isOutlier = prices.length > 1 && deviation > OUTLIER_THRESHOLD;
      offers[r.supplier_id] = {
        responseId: r.id,
        supplierId: r.supplier_id,
        unitPrice,
        lineTotal: unitPrice * qty,
        leadTimeDays: r.lead_time_days,
        confirmed: r.confirmed,
        source: r.source,
        isBestPrice: best !== null && unitPrice === best,
        isOutlier,
        deviationFromMean: deviation,
      };
    }

    return {
      itemId: item.id,
      position: item.position,
      description: item.description,
      quantity: qty,
      offers,
      offerCount: mine.length,
      bestUnitPrice: best,
      meanUnitPrice: mean,
      unquoted: mine.length === 0,
    };
  });

  const packages: SupplierPackage[] = suppliers
    .filter(s => respondedSupplierIds.includes(s.id))
    .map(s => {
      const quoted = rows.filter(r => r.offers[s.id]);
      const itemsTotal = quoted.reduce((sum, r) => sum + r.offers[s.id].lineTotal, 0);
      const freight = num(s.freight);
      const discount = num(s.discount);
      const leads = quoted
        .map(r => r.offers[s.id].leadTimeDays)
        .filter((d): d is number => d !== null && d !== undefined);
      return {
        supplierId: s.id,
        name: s.name,
        quotedItems: quoted.length,
        itemsTotal,
        freight,
        discount,
        packageTotal: itemsTotal - discount + freight,
        maxLeadTimeDays: leads.length ? Math.max(...leads) : null,
        paymentTerms: s.payment_terms ?? null,
        validUntil: s.quote_valid_until ?? null,
        isComplete: quoted.length === rows.length && rows.length > 0,
        isBestPackage: false,
      };
    })
    .sort((a, b) => {
      // Pacote completo vem antes: comparar um parcial com um completo pelo total
      // premiaria quem deixou item de fora.
      if (a.isComplete !== b.isComplete) return a.isComplete ? -1 : 1;
      return a.packageTotal - b.packageTotal;
    });

  const complete = packages.filter(p => p.isComplete);
  const bestPackageTotal = complete.length ? complete[0].packageTotal : null;
  if (complete.length) {
    const winner = packages.find(p => p.supplierId === complete[0].supplierId);
    if (winner) winner.isBestPackage = true;
  }

  const bestPerLineTotal = rows.reduce(
    (sum, r) => sum + (r.bestUnitPrice !== null ? r.bestUnitPrice * r.quantity : 0),
    0,
  );

  return {
    rows,
    packages,
    bestPackageTotal,
    bestPerLineTotal,
    // Só faz sentido falar de economia quando existe um pacote completo para comparar.
    splitSavings: bestPackageTotal !== null ? Math.max(0, bestPackageTotal - bestPerLineTotal) : 0,
    itemCount: rows.length,
    unquotedCount: rows.filter(r => r.unquoted).length,
    respondedSupplierIds,
  };
}

/** Custo da cesta escolhida (item → fornecedor), para o rodapé da tela. */
export function computeBasketTotal(
  comparison: QuoteComparison,
  chosen: Record<string, string | undefined>,
): { lines: BasketLine[]; total: number; chosenCount: number; supplierCount: number } {
  const lines: BasketLine[] = [];
  for (const row of comparison.rows) {
    const supplierId = chosen[row.itemId];
    if (!supplierId) continue;
    const offer = row.offers[supplierId];
    if (!offer) continue;
    lines.push({ itemId: row.itemId, supplierId, lineTotal: offer.lineTotal });
  }
  return {
    lines,
    total: lines.reduce((s, l) => s + l.lineTotal, 0),
    chosenCount: lines.length,
    supplierCount: new Set(lines.map(l => l.supplierId)).size,
  };
}

/** Pré-seleção: o melhor preço de cada linha. Ponto de partida, não decisão. */
export function suggestBestBasket(comparison: QuoteComparison): Record<string, string> {
  const out: Record<string, string> = {};
  for (const row of comparison.rows) {
    if (row.bestUnitPrice === null) continue;
    const winner = Object.values(row.offers).find(o => o.isBestPrice);
    if (winner) out[row.itemId] = winner.supplierId;
  }
  return out;
}

/**
 * Aging da cotação em dias ÚTEIS desde o envio. A literatura de compras trabalha
 * com janela de 3 a 5 dias úteis para resposta, então contar fim de semana daria
 * alarme falso na segunda-feira.
 */
export function businessDaysSince(from: string | Date, now: Date = new Date()): number {
  const start = typeof from === 'string' ? new Date(from) : from;
  if (Number.isNaN(start.getTime())) return 0;
  let days = 0;
  const cursor = new Date(start);
  cursor.setHours(0, 0, 0, 0);
  const end = new Date(now);
  end.setHours(0, 0, 0, 0);
  while (cursor < end) {
    cursor.setDate(cursor.getDate() + 1);
    const dow = cursor.getDay();
    if (dow !== 0 && dow !== 6) days++;
  }
  return days;
}

export type AgingLevel = 'fresh' | 'due' | 'late';

/** 0-2 dias úteis = no prazo · 3-4 = cobrar · 5+ = atrasada. */
export function agingLevel(businessDays: number): AgingLevel {
  if (businessDays >= 5) return 'late';
  if (businessDays >= 3) return 'due';
  return 'fresh';
}
