/**
 * Necessidade de compra de uma OS — cálculo puro (sem I/O, testável).
 *
 * A pergunta que isto responde é "o que ainda falta comprar para executar esta OS?",
 * e a resposta NUNCA é "tem ou não tem em estoque". É a necessidade LÍQUIDA:
 *
 *     falta = necessário − disponível − já pedido
 *     disponível = stock_quantity − reservado por OUTRAS OS   (view product_availability)
 *     já pedido  = Σ (quantity − received_qty) das OCs vivas do produto (view v_oc_itens_a_caminho)
 *
 * Por que descontar o reservado: o modelo de estoque v2 (migration 20260724190000,
 * flag stock_model_v2='on') reserva a peça quando a OS é comprometida. Ignorar a
 * reserva faria duas OS "enxergarem" a mesma peça e nenhuma das duas compraria.
 * Mas o reservado do banco inclui a reserva da PRÓPRIA OS: descontá-lo inteiro fazia
 * a OS dizer que faltava a peça que estava guardada para ela. Desde 24/10/2026 a
 * montagem dos insumos devolve a reserva própria (`descontarReservaDaPropriaOs`) —
 * a fórmula abaixo continua recebendo "o reservado", que agora é o de outras OS.
 *
 * Por que descontar o já pedido: sem isso, toda visita à tela sugere comprar de novo
 * algo que já está a caminho — o erro clássico de sugestão de reposição. "Vivo" quer
 * dizer OC aberta há menos de 60 dias e sem OS encerrada: OC esquecida não abate falta.
 *
 * O que vem a caminho por OC de TEXTO LIVRE da própria OS (o compressor da OS-00104
 * na OC-00004) entra em `items` como 'on_order', com origem 'purchase_order' e falta 0
 * (`comItensACaminho`): não pede compra, mas não deixa a OS parecer pronta.
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

/**
 * De onde vem a linha: peça do catálogo, material de texto livre da OS ou item de
 * texto livre de OC da própria OS que ainda não chegou ('purchase_order').
 */
export type NeedOrigin = 'part' | 'free_text' | 'purchase_order';

export interface PurchaseNeedItem {
  /**
   * id da linha de origem (service_order_parts.id, service_order_services.id ou,
   * para 'purchase_order', purchase_order_items.id)
   */
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
  /** só em origin 'purchase_order': a OC em que o item foi pedido ("OC-00004") */
  purchaseOrderNumber?: string;
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
  /**
   * O item é MATERIAL (compra-se) ou mão de obra digitada à mão?
   *
   * Vem classificado de fora porque a regra vive no banco
   * (`free_text_is_material`), e reimplementá-la aqui criaria mais uma cópia de
   * uma regra que já existe em três linguagens. Quando ausente, o comportamento
   * é o antigo: todo texto livre com unidade 'unit' conta como compra.
   *
   * O caso real que motivou isto (OS-00060): "Instalação 2x Carregador DC/DC" e
   * "Cabo elétrico 16mm²" chegam ao banco IDÊNTICOS — service_id nulo, unidade
   * 'unit' — e os dois apareciam na mesma lista de itens a cotar.
   */
  is_material?: boolean;
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
  /** itens de OC viva (view v_oc_itens_a_caminho: draft/sent/partial, < 60 dias, OS não encerrada) */
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
  if (item.service_id !== null) return false;
  if (!PURCHASABLE_BILLING_UNITS.has(item.billing_unit_snapshot)) return false;
  // Classificação explícita manda; sem ela, mantém o comportamento anterior.
  return item.is_material !== false;
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

// ── Montagem dos insumos (24/10/2026) ────────────────────────────────────────
// Ficam FORA de computePurchaseNeeds de propósito: a fórmula pura e a sua irmã SQL
// (compute_purchase_needs) não mudam de assinatura. Quem monta os insumos — o hook
// aqui, get_os_purchase_needs no banco — aplica estas duas peças, e o mesmo cenário
// é provado nos dois lados (use-purchase-needs.test.ts ×
// supabase/tests/purchase_needs_reserva_e_a_caminho.sql).

/**
 * Status em que a OS RESERVA estoque. É a lista de recompute_product_reservations
 * (supabase/migrations/20260724220000_stock_v2_status_sets_fix.sql) e da CTE `os` de
 * get_os_purchase_needs (20261024150100); src/test/status-que-reservam.test.ts cobra
 * que as três sejam iguais. 'open' fica fora: hoje não reserva (NOVO-agenda-01).
 */
export const STATUS_QUE_RESERVAM = [
  'approved', 'scheduled', 'in_progress', 'awaiting_parts', 'awaiting_client', 'reopened',
] as const;

export function osReservaEstoque(status: string | null | undefined): boolean {
  return (STATUS_QUE_RESERVAM as readonly string[]).includes(status ?? '');
}

/**
 * Tira do reservado a reserva da PRÓPRIA OS, para o disponível dela não descontar a
 * peça que já está guardada para ela. O reservado do banco é a soma das peças de toda
 * OS que reserva; a reserva desta é a soma das peças dela por produto — só se o status
 * dela reserva. Piso em zero: com o reservado defasado (menor que a reserva própria),
 * o disponível nunca passa do físico.
 */
export function descontarReservaDaPropriaOs(
  availability: AvailabilityInput[],
  parts: Array<Pick<PartInput, 'product_id' | 'quantity'>>,
  statusDaOs: string | null | undefined,
): AvailabilityInput[] {
  if (!osReservaEstoque(statusDaOs)) return availability;
  const propria = new Map<string, number>();
  for (const p of parts) {
    propria.set(p.product_id, (propria.get(p.product_id) ?? 0) + num(p.quantity));
  }
  return availability.map((a) => ({
    ...a,
    reserved_quantity: Math.max(num(a.reserved_quantity) - (propria.get(a.id) ?? 0), 0),
  }));
}

/** Linha de texto livre de OC da própria OS (view v_oc_itens_a_caminho, product_id nulo). */
export interface ItemACaminhoInput {
  purchase_order_item_id: string;
  po_number: string;
  description: string;
  quantity: number | string;
  /** quantidade − recebido */
  pendente: number | string;
  unit_cost?: number | string | null;
}

/**
 * Anexa a `items` o que foi pedido em OC de texto livre da própria OS e ainda não
 * chegou, como 'on_order' (origem 'purchase_order', falta 0). shortages, shortageCount,
 * estimatedCost e needsPurchase NÃO mudam: nada disso pede compra. Mas a OS também não
 * fica com a lista vazia — o que a faria parecer pronta com o compressor ainda no
 * fornecedor (OS-00104, OC-00004). A ordem é a de quem chama (OC mais antiga primeiro).
 */
export function comItensACaminho(needs: PurchaseNeeds, linhas: ItemACaminhoInput[]): PurchaseNeeds {
  const aCaminho: PurchaseNeedItem[] = linhas
    .filter((l) => num(l.pendente) > 0)
    .map((l) => ({
      sourceId: l.purchase_order_item_id,
      origin: 'purchase_order',
      productId: null,
      description: l.description,
      unit: null,
      required: num(l.quantity),
      available: 0,
      onOrder: num(l.pendente),
      shortage: 0,
      status: 'on_order',
      unitCost: num(l.unit_cost),
      purchaseOrderNumber: l.po_number,
    }));
  if (!aCaminho.length) return needs;
  return { ...needs, items: [...needs.items, ...aCaminho] };
}

/** Rótulo curto para chip/selo na UI. */
export const NEED_STATUS_LABELS: Record<NeedStatus, string> = {
  ok: 'Em estoque',
  on_order: 'Já pedido',
  partial: 'Falta parte',
  missing: 'Sem estoque',
  uncatalogued: 'Sem cadastro',
};
