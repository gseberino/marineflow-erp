import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import {
  comItensACaminho, computePurchaseNeeds, descontarReservaDaPropriaOs,
  type ItemACaminhoInput, type PurchaseNeeds,
} from '@/lib/purchase-needs';

/**
 * Necessidade de compra de uma OS. Busca os insumos e delega o cálculo para a lib
 * pura (src/lib/purchase-needs.ts), que é onde a regra vive e é testada. É o espelho
 * da RPC get_os_purchase_needs (a via do agente e do motor R16): a mesma montagem,
 * com o mesmo cenário provado nos dois lados.
 *
 * A disponibilidade sai de `product_availability` (físico − reservado) e não da
 * tabela products crua, para não ignorar as reservas do modelo de estoque v2 — mas
 * sem a reserva da PRÓPRIA OS (24/10/2026), que é por isso que se lê o status dela.
 *
 * O "já pedido" e o que vem a caminho por OC de texto livre saem da view
 * `v_oc_itens_a_caminho`, a mesma que a RPC lê: OC aberta há menos de 60 dias e sem
 * OS encerrada. A regra de "OC viva" fica num lugar só (antes, aqui, toda OC
 * draft/sent/partial contava, de qualquer idade e de OS já faturada).
 *
 * Toda leitura com erro LANÇA: falha que vira lista vazia diria "nada a comprar".
 * A única exceção é a classificação do texto livre (ver abaixo), cuja falha mantém
 * o material na conta.
 */
export async function fetchPurchaseNeeds(serviceOrderId: string): Promise<PurchaseNeeds> {
  const [osRes, partsRes, servicesRes, aCaminhoRes] = await Promise.all([
    // Só o status: decide se a OS reserva estoque (STATUS_QUE_RESERVAM).
    supabase
      .from('service_orders')
      .select('status')
      .eq('id', serviceOrderId)
      .maybeSingle(),
    supabase
      .from('service_order_parts')
      .select('id, product_id, quantity, unit_cost_snapshot, products(name, unit)')
      .eq('service_order_id', serviceOrderId)
      // Ordem FIXA, igual à da RPC. O cálculo consome o estoque linha a linha, então
      // sem isto o resultado dependia da ordem que o Postgres devolvesse: com estoque
      // 4 e duas linhas do mesmo produto pedindo 5 e 1, uma ordem acusa dois itens em
      // falta e a outra acusa um. O total não muda; a distribuição entre as linhas sim.
      .order('created_at', { ascending: true })
      .order('id', { ascending: true }),
    supabase
      .from('service_order_services')
      .select('id, service_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot')
      .eq('service_order_id', serviceOrderId)
      .order('created_at', { ascending: true })
      .order('id', { ascending: true }),
    // O que foi pedido em OC de TEXTO LIVRE desta OS e ainda não chegou. Mesmo filtro e
    // mesma ordem da CTE a_caminho de get_os_purchase_needs.
    supabase
      .from('v_oc_itens_a_caminho')
      .select('purchase_order_item_id, po_number, description, quantity, pendente, unit_cost')
      .eq('service_order_id', serviceOrderId)
      .is('product_id', null)
      .gt('pendente', 0)
      .order('po_criada_em', { ascending: true })
      .order('purchase_order_item_id', { ascending: true }),
  ]);
  if (osRes.error) throw osRes.error;
  if (partsRes.error) throw partsRes.error;
  if (servicesRes.error) throw servicesRes.error;
  if (aCaminhoRes.error) throw aCaminhoRes.error;

  const parts = (partsRes.data ?? []).map((p: any) => ({
    id: p.id,
    product_id: p.product_id,
    quantity: p.quantity,
    unit_cost_snapshot: p.unit_cost_snapshot,
    product_name: p.products?.name ?? null,
    product_unit: p.products?.unit ?? null,
  }));

  const productIds = [...new Set(parts.map(p => p.product_id).filter(Boolean))];

  // Sem peça no catálogo não há o que consultar de estoque nem de OC.
  let availability: any[] = [];
  let onOrder: any[] = [];
  if (productIds.length) {
    const [availRes, poRes] = await Promise.all([
      supabase
        .from('product_availability')
        .select('id, stock_quantity, reserved_quantity')
        .in('id', productIds),
      // "Já pedido" só de OC viva: a view já filtra status, idade e OS encerrada.
      supabase
        .from('v_oc_itens_a_caminho')
        .select('product_id, quantity, received_qty')
        .in('product_id', productIds),
    ]);
    if (availRes.error) throw availRes.error;
    if (poRes.error) throw poRes.error;
    // O reservado que entra na conta é o de OUTRAS OS (a mesma CTE `propria` da RPC).
    // A view tipa o id como anulável; o filtro .in('id', …) só devolve linha com id.
    const lidas = (availRes.data ?? []).flatMap((a) => (a.id
      ? [{ id: a.id, stock_quantity: a.stock_quantity, reserved_quantity: a.reserved_quantity }]
      : []));
    availability = descontarReservaDaPropriaOs(lidas, parts, osRes.data?.status);
    onOrder = (poRes.data ?? []).map((i: any) => ({
      product_id: i.product_id,
      quantity: i.quantity,
      received_qty: i.received_qty,
    }));
  }

  /* Mão de obra digitada como texto livre não é compra. A separação vive no banco
     (`free_text_is_material`) e é consultada em lote — reimplementar a regra aqui
     criaria mais uma cópia de algo que já existe em TypeScript, Deno e SQL.
     Caso real (OS-00060): "Instalação 2x Carregador DC/DC" e "Cabo 16mm²" chegam
     idênticos — service_id nulo, unidade 'unit' — e os dois apareciam para cotar. */
  const livres = (servicesRes.data ?? []) as any[];
  const candidatos = livres
    .filter((s) => s.service_id === null && s.billing_unit_snapshot === 'unit')
    .map((s) => s.name_snapshot)
    .filter(Boolean);

  let ehMaterial: Record<string, boolean> = {};
  if (candidatos.length) {
    const { data, error } = await (supabase.rpc as any)('classify_free_text_materials', {
      p_textos: [...new Set(candidatos)],
    });
    // Falha na classificação não pode esconder material a comprar: sem resposta,
    // todos seguem entrando (comportamento anterior), e no máximo sobra ruído.
    if (!error) ehMaterial = (data ?? {}) as Record<string, boolean>;
  }

  const needs = computePurchaseNeeds({
    serviceOrderId,
    parts,
    freeTextItems: livres.map((s) => ({
      ...s,
      is_material: ehMaterial[s.name_snapshot],
    })),
    availability,
    onOrder,
  });
  // A view tipa toda coluna como anulável; na origem (purchase_order_items/purchase_orders)
  // nenhuma destas é nula.
  const aCaminho: ItemACaminhoInput[] = (aCaminhoRes.data ?? []).map((l) => ({
    purchase_order_item_id: l.purchase_order_item_id ?? '',
    po_number: l.po_number ?? '',
    description: l.description ?? '',
    quantity: l.quantity ?? 0,
    pendente: l.pendente ?? 0,
    unit_cost: l.unit_cost,
  }));
  return comItensACaminho(needs, aCaminho);
}

export function usePurchaseNeeds(serviceOrderId: string | undefined, enabled = true) {
  return useQuery({
    queryKey: ['purchase-needs', serviceOrderId],
    queryFn: () => fetchPurchaseNeeds(serviceOrderId!),
    enabled: !!serviceOrderId && enabled,
    staleTime: 30_000,
  });
}
