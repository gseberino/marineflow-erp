import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import {
  aplicarSituacaoDoMaterial, comItensACaminho, comOcLigada, computePurchaseNeeds, descontarReservaDaPropriaOs,
  type ItemACaminhoInput, type LinhaDeMaterialInput, type LinhaDeOcLigadaInput, type PurchaseNeeds,
} from '@/lib/purchase-needs';

/** Os códigos de "a tabela não existe": PGRST205 (cache do PostgREST) e 42P01 (Postgres). */
const TABELA_AUSENTE = new Set(['PGRST205', '42P01']);
/** O código de "a coluna não existe" (Postgres 42703): o vínculo de linha da OC antes da migration 20261027100000. */
const COLUNA_AUSENTE = '42703';

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
 * `v_oc_itens_a_caminho`, a mesma que a RPC lê. O "já pedido" de catálogo só conta a
 * linha com `conta_como_ja_pedido` (OC aberta há menos de `agenda_config.oc_viva_dias` — 60 por
 * padrão; Agenda de Produção, Fase 4 — e sem OS encerrada):
 * a regra de "OC viva" fica num lugar só (antes, aqui, toda OC draft/sent/partial
 * contava, de qualquer idade e de OS já faturada). O que vem a caminho para a própria
 * OS não tem idade: a linha não abate falta, e cortá-la só a esconderia (revisão de
 * 23/10: a OC-00004 da OS-00104 sairia da conta em 12/12 com o compressor no fornecedor).
 *
 * A OC que diz de qual linha da OS ela compra (Agenda de Produção, Fase 4, P2): as linhas de OC
 * desta OS ligadas a uma linha de serviço (purchase_order_items.service_order_service_id), inclusive
 * as já recebidas, refazem o item de texto livre (`comOcLigada`, o espelho da CTE `ligadas` de
 * os_necessidade_bruta) e saem do "a caminho". Enquanto a coluna não existe (o front publicado antes
 * da migration 20261027100000), a leitura conta como sem vínculo: a conta de antes.
 *
 * Por último, o que o dono disse de cada linha (os_material, Agenda de Produção, 24/10/2026):
 * comprado ou a caminho conta como já pedido, na mão como disponível, dispensado sai — a
 * mesma camada final da RPC (aplicar_os_material) —, e (Fase 4, P2) o material que ele citou
 * entra na lista, sem preço. O técnico não lê os_material (RLS): a
 * leitura volta vazia, sem erro, e ele vê a conta bruta, como na RPC. Enquanto a tabela não
 * existe (o front sai pela Vercel no push; a migration 20261024160000 espera o OK do dono), a
 * leitura conta como sem linhas: a conta bruta, a mesma da RPC que está no ar.
 *
 * Toda leitura com erro LANÇA: falha que vira lista vazia diria "nada a comprar".
 * A única exceção é a classificação do texto livre (ver abaixo), cuja falha mantém
 * o material na conta.
 */
export async function fetchPurchaseNeeds(serviceOrderId: string): Promise<PurchaseNeeds> {
  const [osRes, partsRes, servicesRes, aCaminhoRes, materialRes, ligadasRes] = await Promise.all([
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
    // mesma ordem da CTE a_caminho de get_os_purchase_needs — sem conta_como_ja_pedido:
    // o rascunho de 61 dias continua sendo o que a OS espera chegar.
    supabase
      .from('v_oc_itens_a_caminho')
      .select('purchase_order_item_id, po_number, description, quantity, pendente, unit_cost')
      .eq('service_order_id', serviceOrderId)
      .is('product_id', null)
      .gt('pendente', 0)
      .order('po_criada_em', { ascending: true })
      .order('purchase_order_item_id', { ascending: true }),
    // O que o dono disse de cada linha. A mesma ordem da RPC (por id): ela decide quem casa
    // primeiro se duas linhas apontarem para o mesmo item.
    // Fase 4 (P2): + o id e a descrição (o material citado pelo dono entra na lista com eles).
    supabase
      .from('os_material')
      .select('id, descricao, service_order_part_id, service_order_service_id, purchase_order_item_id, origem, situacao, fonte, quantidade_necessaria, quantidade_na_mao')
      .eq('service_order_id', serviceOrderId)
      .order('id', { ascending: true }),
    // Fase 4 (P2): as linhas de OC desta OS ligadas a uma linha de serviço, de OC fora de cancelada e de
    // qualquer situação (a recebida também: é ela que põe o material na mão). A mesma CTE `ligadas` do banco.
    supabase
      .from('purchase_order_items')
      .select('id, service_order_service_id, quantity, received_qty, purchase_orders!inner(po_number, status, service_order_id, created_at)')
      .eq('purchase_orders.service_order_id', serviceOrderId)
      .neq('purchase_orders.status', 'cancelled')
      .not('service_order_service_id', 'is', null),
  ]);
  if (osRes.error) throw osRes.error;
  if (partsRes.error) throw partsRes.error;
  if (servicesRes.error) throw servicesRes.error;
  if (aCaminhoRes.error) throw aCaminhoRes.error;
  // os_material: só a tabela que ainda não existe (PGRST205 do PostgREST, 42P01 do Postgres) vira "sem
  // linhas" — a conta bruta, igual à RPC em produção antes da migration. Qualquer outro erro lança.
  if (materialRes.error && !TABELA_AUSENTE.has(String((materialRes.error as { code?: unknown }).code ?? ''))) {
    throw materialRes.error;
  }
  // O vínculo de linha: só a coluna que ainda não existe (42703) vira "sem vínculo" — a conta de antes. Qualquer
  // outro erro lança.
  if (ligadasRes.error && String((ligadasRes.error as { code?: unknown }).code ?? '') !== COLUNA_AUSENTE) {
    throw ligadasRes.error;
  }

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
      // "Já pedido" só de OC viva: a view filtra o status, e conta_como_ja_pedido, a idade
      // e a OS encerrada.
      supabase
        .from('v_oc_itens_a_caminho')
        .select('product_id, quantity, received_qty')
        .eq('conta_como_ja_pedido', true)
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
  // As linhas de OC ligadas (Fase 4, P2). O embed !inner vem como objeto (a FK é de muitos para um).
  const ligadas: LinhaDeOcLigadaInput[] = (ligadasRes.error ? [] : (ligadasRes.data ?? []) as any[])
    .flatMap((l: any) => (l.service_order_service_id && l.purchase_orders
      ? [{
          purchase_order_item_id: l.id,
          service_order_service_id: l.service_order_service_id,
          po_number: l.purchase_orders.po_number ?? '',
          po_status: l.purchase_orders.status ?? '',
          po_criada_em: l.purchase_orders.created_at ?? '',
          quantity: l.quantity ?? 0,
          received_qty: l.received_qty ?? 0,
        }]
      : []));
  const linhaDaOc = new Map(ligadas.map((l) => [l.purchase_order_item_id, l.service_order_service_id]));
  // A view tipa toda coluna como anulável; na origem (purchase_order_items/purchase_orders)
  // nenhuma destas é nula. A linha da OS que cada linha da OC compra vem da leitura acima (a view não precisa
  // da coluna nova: o front publicado antes da migration continua lendo).
  const aCaminho: ItemACaminhoInput[] = (aCaminhoRes.data ?? []).map((l) => ({
    purchase_order_item_id: l.purchase_order_item_id ?? '',
    po_number: l.po_number ?? '',
    description: l.description ?? '',
    quantity: l.quantity ?? 0,
    pendente: l.pendente ?? 0,
    unit_cost: l.unit_cost,
    service_order_service_id: linhaDaOc.get(l.purchase_order_item_id ?? '') ?? null,
  }));
  const linhas: LinhaDeMaterialInput[] = materialRes.data ?? [];
  return aplicarSituacaoDoMaterial(comItensACaminho(comOcLigada(needs, ligadas), aCaminho), linhas);
}

export function usePurchaseNeeds(serviceOrderId: string | undefined, enabled = true) {
  return useQuery({
    queryKey: ['purchase-needs', serviceOrderId],
    queryFn: () => fetchPurchaseNeeds(serviceOrderId!),
    enabled: !!serviceOrderId && enabled,
    staleTime: 30_000,
  });
}
