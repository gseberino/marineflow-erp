/**
 * Necessidade de compra de uma OS — cálculo puro (sem I/O, testável).
 *
 * A pergunta que isto responde é "o que ainda falta comprar para executar esta OS?",
 * e a resposta NUNCA é "tem ou não tem em estoque". É a necessidade LÍQUIDA:
 *
 *     falta = necessário − disponível − já pedido
 *     disponível = stock_quantity − reserved_quantity   (view product_availability)
 *     já pedido  = Σ (quantity − received_qty) das OCs abertas do produto
 *
 * Por que descontar o reservado: o modelo de estoque v2 (migration 20260724190000,
 * flag stock_model_v2='on') reserva a peça quando a OS é comprometida. Ignorar a
 * reserva faria duas OS "enxergarem" a mesma peça e nenhuma das duas compraria.
 *
 * Por que descontar o já pedido: sem isso, toda visita à tela sugere comprar de novo
 * algo que já está a caminho — o erro clássico de sugestão de reposição.
 *
 * O que entra na conta (decisão do dono, 29/07/2026):
 *   • PEÇAS (service_order_parts) — product_id é NOT NULL, então sempre há catálogo;
 *     entram quando o disponível não cobre a quantidade.
 *   • ITENS DE TEXTO LIVRE — material avulso digitado na OS, que vive em
 *     service_order_services com service_id NULL e billing_unit 'unit'. Não têm
 *     cadastro, logo não têm estoque: a necessidade é a quantidade inteira.
 *     Mão de obra ('hour') e deslocamento ('visit') NÃO são compra e ficam fora.
 */

/** Unidades de faturamento de serviço que representam MATERIAL (comprável). */
const PURCHASABLE_BILLING_UNITS = new Set(['unit']);

export type NeedStatus =
  /** disponível cobre tudo — nada a fazer */
  | 'ok'
  /** o já pedido cobre o que falta — só esperar a entrega */
  | 'on_order'
  /** parte do necessário está disponível, o resto falta */
  | 'partial'
  /** nada disponível */
  | 'missing'
  /** item sem cadastro (texto livre): sempre precisa comprar */
  | 'uncatalogued';

export type NeedOrigin = 'part' | 'free_text';

export interface PurchaseNeedItem {
  /** id da linha de origem (service_order_parts.id ou service_order_services.id) */
  sourceId: string;
  origin: NeedOrigin;
  productId: string | null;
  description: string;
  unit: string | null;
  /** quantidade pedida na OS */
  required: number;
  /** físico − reservado (0 para item sem cadastro) */
  available: number;
  /** em ordens de compra abertas, ainda não recebido */
  onOrder: number;
  /** o que ainda precisa ser comprado — nunca negativo */
  shortage: number;
  status: NeedStatus;
  /** custo unitário conhecido, para estimar o investimento */
  unitCost: number;
}

export interface PurchaseNeeds {
  serviceOrderId: string;
  items: PurchaseNeedItem[];
  /** só os itens com shortage > 0, na ordem em que devem ser resolvidos */
  shortages: PurchaseNeedItem[];
  /** quantos itens precisam de compra */
  shortageCount: number;
  /** soma de shortage × custo unitário conhecido (0 quando o custo é desconhecido) */
  estimatedCost: number;
  /** true quando há qualquer item a comprar — é o gatilho do aviso e da regra R16 */
  needsPurchase: boolean;
}

// ── Entradas (o hook/RPC preenche; a lib não busca nada) ─────────────────────

export interface PartInput {
  id: string;
  product_id: string;
  quantity: number | string;
  unit_cost_snapshot?: number | string | null;
  /** nome e unidade vêm do embed de products */
  product_name?: string | null;
  product_unit?: string | null;
}

export interface FreeTextInput {
  id: string;
  service_id: string | null;
  name_snapshot: string;
  billing_unit_snapshot: string;
  quantity: number | string;
  unit_price_snapshot?: number | string | null;
}

export interface AvailabilityInput {
  id: string;
  stock_quantity: number | string | null;
  reserved_quantity: number | string | null;
}

export interface OnOrderInput {
  product_id: string;
  quantity: number | string;
  received_qty: number | string | null;
}

export interface ComputeInput {
  serviceOrderId: string;
  parts: PartInput[];
  freeTextItems: FreeTextInput[];
  availability: AvailabilityInput[];
  /** itens de OCs em status draft/sent/partial (as que ainda vão entregar) */
  onOrder: OnOrderInput[];
}

/** numeric do Postgres chega como string via PostgREST — normalizar sempre. */
function num(v: number | string | null | undefined): number {
  if (v === null || v === undefined) return 0;
  const n = typeof v === 'number' ? v : parseFloat(v);
  return Number.isFinite(n) ? n : 0;
}

/** Um item de texto livre só conta como compra se for material, não mão de obra. */
export function isPurchasableFreeText(item: FreeTextInput): boolean {
  return item.service_id === null && PURCHASABLE_BILLING_UNITS.has(item.billing_unit_snapshot);
}

export function computePurchaseNeeds(input: ComputeInput): PurchaseNeeds {
  const availableByProduct = new Map<string, number>();
  for (const a of input.availability) {
    availableByProduct.set(a.id, num(a.stock_quantity) - num(a.reserved_quantity));
  }

  const onOrderByProduct = new Map<string, number>();
  for (const o of input.onOrder) {
    const pending = Math.max(0, num(o.quantity) - num(o.received_qty));
    onOrderByProduct.set(o.product_id, (onOrderByProduct.get(o.product_id) ?? 0) + pending);
  }

  const items: PurchaseNeedItem[] = [];

  // Peças do catálogo: desconta disponível e o que já está a caminho.
  // Várias linhas podem apontar para o MESMO produto na mesma OS; o disponível
  // é consumido na ordem das linhas para não prometer a mesma peça duas vezes.
  const consumedAvailable = new Map<string, number>();
  const consumedOnOrder = new Map<string, number>();

  for (const p of input.parts) {
    const required = num(p.quantity);
    const totalAvailable = Math.max(0, availableByProduct.get(p.product_id) ?? 0);
    const alreadyUsed = consumedAvailable.get(p.product_id) ?? 0;
    const available = Math.max(0, Math.min(required, totalAvailable - alreadyUsed));
    consumedAvailable.set(p.product_id, alreadyUsed + available);

    const afterStock = Math.max(0, required - available);

    const totalOnOrder = onOrderByProduct.get(p.product_id) ?? 0;
    const onOrderUsed = consumedOnOrder.get(p.product_id) ?? 0;
    const onOrder = Math.max(0, Math.min(afterStock, totalOnOrder - onOrderUsed));
    consumedOnOrder.set(p.product_id, onOrderUsed + onOrder);

    const shortage = Math.max(0, afterStock - onOrder);

    let status: NeedStatus;
    if (shortage === 0 && afterStock === 0) status = 'ok';
    else if (shortage === 0) status = 'on_order';
    else if (available > 0) status = 'partial';
    else status = 'missing';

    items.push({
      sourceId: p.id,
      origin: 'part',
      productId: p.product_id,
      description: p.product_name || 'Produto',
      unit: p.product_unit ?? null,
      required,
      available,
      onOrder,
      shortage,
      status,
      unitCost: num(p.unit_cost_snapshot),
    });
  }

  // Texto livre: sem cadastro, sem estoque — a necessidade é a quantidade inteira.
  for (const f of input.freeTextItems) {
    if (!isPurchasableFreeText(f)) continue;
    const required = num(f.quantity);
    if (required <= 0) continue;
    items.push({
      sourceId: f.id,
      origin: 'free_text',
      productId: null,
      description: f.name_snapshot,
      unit: null,
      required,
      available: 0,
      onOrder: 0,
      shortage: required,
      status: 'uncatalogued',
      unitCost: num(f.unit_price_snapshot),
    });
  }

  // Ordem de resolução: quem não tem nada primeiro, depois parcial, depois sem cadastro.
  const rank: Record<NeedStatus, number> = {
    missing: 0, partial: 1, uncatalogued: 2, on_order: 3, ok: 4,
  };
  const shortages = items
    .filter(i => i.shortage > 0)
    .sort((a, b) => rank[a.status] - rank[b.status] || b.shortage - a.shortage);

  const estimatedCost = shortages.reduce((s, i) => s + i.shortage * i.unitCost, 0);

  return {
    serviceOrderId: input.serviceOrderId,
    items,
    shortages,
    shortageCount: shortages.length,
    estimatedCost,
    needsPurchase: shortages.length > 0,
  };
}

/** Rótulo curto para chip/selo na UI. */
export const NEED_STATUS_LABELS: Record<NeedStatus, string> = {
  ok: 'Em estoque',
  on_order: 'Já pedido',
  partial: 'Falta parte',
  missing: 'Sem estoque',
  uncatalogued: 'Sem cadastro',
};
