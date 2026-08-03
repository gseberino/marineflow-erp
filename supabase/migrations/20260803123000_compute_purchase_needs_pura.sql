-- ─────────────────────────────────────────────────────────────────────────────
-- Separa o CÁLCULO da BUSCA, espelhando o desenho da lib TypeScript.
--
-- Motivo: a versão anterior só sabia calcular a partir do banco, e as OS reais
-- hoje têm todo o estoque zerado e nenhuma OC aberta — ou seja, os dados de
-- produção exercitam apenas o caso trivial ("falta tudo") e não provam nada
-- sobre reserva, saldo de OC ou duas linhas do mesmo produto. Com o cálculo
-- isolado, os 14 casos de src/lib/purchase-needs.test.ts podem ser rodados
-- contra o SQL sem inserir uma linha sequer no banco.
--
-- compute_purchase_needs — recebe os quatro insumos como jsonb e devolve o
--   mesmo formato da lib. É immutable: mesma entrada, mesma saída, sem I/O.
-- get_os_purchase_needs — apenas busca os insumos e delega. Assim existe UM
--   lugar onde a regra vive, e não dois que podem divergir.
--
-- A ORDEM DOS ARRAYS IMPORTA e é preservada com `with ordinality`: é ela que
-- decide qual linha consome o estoque primeiro quando duas pedem o mesmo
-- produto. Quem chama é responsável por ordenar de forma determinística.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.compute_purchase_needs(
  p_so_id     uuid,
  p_parts     jsonb,
  p_free      jsonb,
  p_avail     jsonb,
  p_on_order  jsonb
)
returns jsonb
language sql
immutable
set search_path = public
as $$
with
avail as (
  select e->>'id' as product_id,
         greatest(0, coalesce((e->>'stock_quantity')::numeric, 0)
                   - coalesce((e->>'reserved_quantity')::numeric, 0)) as total_available
  from jsonb_array_elements(coalesce(p_avail, '[]'::jsonb)) e
),
on_order as (
  select e->>'product_id' as product_id,
         sum(greatest(0, coalesce((e->>'quantity')::numeric, 0)
                       - coalesce((e->>'received_qty')::numeric, 0))) as total_on_order
  from jsonb_array_elements(coalesce(p_on_order, '[]'::jsonb)) e
  group by 1
),
parts as (
  select e->>'id'                                    as id,
         e->>'product_id'                            as product_id,
         coalesce((e->>'quantity')::numeric, 0)      as required,
         coalesce((e->>'unit_cost_snapshot')::numeric, 0) as unit_cost,
         coalesce(e->>'product_name', 'Produto')     as description,
         e->>'product_unit'                          as unit,
         ord                                         as seq
  from jsonb_array_elements(coalesce(p_parts, '[]'::jsonb)) with ordinality as t(e, ord)
),
parts_ctx as (
  select pt.*,
         coalesce(a.total_available, 0) as total_available,
         coalesce(o.total_on_order, 0)  as total_on_order,
         coalesce(sum(pt.required) over (
           partition by pt.product_id order by pt.seq
           rows between unbounded preceding and 1 preceding), 0) as required_before
  from parts pt
  left join avail    a on a.product_id = pt.product_id
  left join on_order o on o.product_id = pt.product_id
),
parts_stock as (
  select pc.*,
         greatest(0, least(pc.required,
                           greatest(0, pc.total_available - pc.required_before))) as available
  from parts_ctx pc
),
parts_gap as (
  select ps.*, greatest(0, ps.required - ps.available) as after_stock
  from parts_stock ps
),
parts_gap_ctx as (
  select pg.*,
         coalesce(sum(pg.after_stock) over (
           partition by pg.product_id order by pg.seq
           rows between unbounded preceding and 1 preceding), 0) as after_before
  from parts_gap pg
),
parts_final as (
  select pgc.*,
         greatest(0, least(pgc.after_stock,
                           greatest(0, pgc.total_on_order - pgc.after_before))) as on_order_qty
  from parts_gap_ctx pgc
),
parts_out as (
  select pf.id as source_id, 'part'::text as origin, pf.product_id,
         pf.description, pf.unit, pf.required, pf.available,
         pf.on_order_qty as on_order,
         greatest(0, pf.after_stock - pf.on_order_qty) as shortage,
         pf.unit_cost, pf.seq, 0 as grp
  from parts_final pf
),
free_out as (
  select e->>'id' as source_id, 'free_text'::text as origin,
         null::text as product_id,
         e->>'name_snapshot' as description,
         null::text as unit,
         coalesce((e->>'quantity')::numeric, 0) as required,
         0::numeric as available,
         0::numeric as on_order,
         coalesce((e->>'quantity')::numeric, 0) as shortage,
         coalesce((e->>'unit_price_snapshot')::numeric, 0) as unit_cost,
         ord as seq, 1 as grp
  from jsonb_array_elements(coalesce(p_free, '[]'::jsonb)) with ordinality as t(e, ord)
  where (e->>'service_id') is null
    and e->>'billing_unit_snapshot' = 'unit'
    and coalesce((e->>'quantity')::numeric, 0) > 0
),
ranked as (
  select o.*,
         case
           when o.origin = 'free_text'                          then 'uncatalogued'
           when o.shortage = 0 and o.required - o.available = 0 then 'ok'
           when o.shortage = 0                                  then 'on_order'
           when o.available > 0                                 then 'partial'
           else 'missing'
         end as status,
         case
           when o.origin = 'free_text'                          then 2
           when o.shortage = 0 and o.required - o.available = 0 then 4
           when o.shortage = 0                                  then 3
           when o.available > 0                                 then 1
           else 0
         end as rank
  from (select * from parts_out union all select * from free_out) o
),
item as (
  select r.*, jsonb_build_object(
    'sourceId', r.source_id, 'origin', r.origin, 'productId', r.product_id,
    'description', r.description, 'unit', r.unit, 'required', r.required,
    'available', r.available, 'onOrder', r.on_order, 'shortage', r.shortage,
    'status', r.status, 'unitCost', r.unit_cost) as js
  from ranked r
)
select jsonb_build_object(
  'serviceOrderId', p_so_id,
  -- peças antes de texto livre, cada grupo na ordem de entrada (igual à lib)
  'items',        coalesce((select jsonb_agg(js order by grp, seq) from item), '[]'::jsonb),
  'shortages',    coalesce((select jsonb_agg(js order by rank, shortage desc)
                            from item where shortage > 0), '[]'::jsonb),
  'shortageCount',(select count(*) from item where shortage > 0),
  'estimatedCost',coalesce((select sum(shortage * unit_cost) from item where shortage > 0), 0),
  'needsPurchase',exists (select 1 from item where shortage > 0)
);
$$;

comment on function public.compute_purchase_needs(uuid, jsonb, jsonb, jsonb, jsonb) is
  'Calculo puro da necessidade de compra (sem I/O). Espelha computePurchaseNeeds de src/lib/purchase-needs.ts. A ordem dos arrays decide quem consome o estoque primeiro.';

-- A busca passa a apenas montar os insumos e delegar.
create or replace function public.get_os_purchase_needs(p_so_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  select public.compute_purchase_needs(
    p_so_id,
    coalesce((select jsonb_agg(jsonb_build_object(
        'id', sop.id, 'product_id', sop.product_id, 'quantity', sop.quantity,
        'unit_cost_snapshot', sop.unit_cost_snapshot,
        'product_name', p.name, 'product_unit', p.unit)
        order by sop.created_at, sop.id)
      from service_order_parts sop
      left join products p on p.id = sop.product_id
      where sop.service_order_id = p_so_id), '[]'::jsonb),
    coalesce((select jsonb_agg(jsonb_build_object(
        'id', s.id, 'service_id', s.service_id, 'name_snapshot', s.name_snapshot,
        'billing_unit_snapshot', s.billing_unit_snapshot, 'quantity', s.quantity,
        'unit_price_snapshot', s.unit_price_snapshot)
        order by s.created_at, s.id)
      from service_order_services s
      where s.service_order_id = p_so_id), '[]'::jsonb),
    coalesce((select jsonb_agg(jsonb_build_object(
        'id', pa.id, 'stock_quantity', pa.stock_quantity, 'reserved_quantity', pa.reserved_quantity))
      from product_availability pa
      where pa.id in (select sop.product_id from service_order_parts sop
                      where sop.service_order_id = p_so_id)), '[]'::jsonb),
    coalesce((select jsonb_agg(jsonb_build_object(
        'product_id', poi.product_id, 'quantity', poi.quantity, 'received_qty', poi.received_qty))
      from purchase_order_items poi
      join purchase_orders po on po.id = poi.purchase_order_id
      where po.status in ('draft', 'sent', 'partial')
        and poi.product_id in (select sop.product_id from service_order_parts sop
                               where sop.service_order_id = p_so_id)), '[]'::jsonb)
  );
$$;

revoke all on function public.compute_purchase_needs(uuid, jsonb, jsonb, jsonb, jsonb) from public;
grant execute on function public.compute_purchase_needs(uuid, jsonb, jsonb, jsonb, jsonb) to authenticated, service_role;
revoke all on function public.get_os_purchase_needs(uuid) from public;
grant execute on function public.get_os_purchase_needs(uuid) to authenticated, service_role;
