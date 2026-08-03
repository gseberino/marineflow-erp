-- ─────────────────────────────────────────────────────────────────────────────
-- get_os_purchase_needs(p_so_id) — necessidade de compra de uma OS, no banco.
--
-- Fecha o aceite da Fase C0 do plano de Compras ("paridade lib × RPC"), que ficou
-- para trás: a RPC nunca foi criada. Enquanto isso, a MESMA regra passou a existir
-- escrita duas vezes, em duas linguagens:
--   • src/lib/purchase-needs.ts          (TypeScript, usado pelas telas)
--   • task-automations/rules.ts:518-562  (Deno, reimplementada para a regra R16)
-- Duas cópias divergem em silêncio: quem corrigir uma não tem como saber da outra.
-- Esta função passa a ser a terceira — e é de propósito a que o AGENTE usa, que
-- hoje não tem ferramenta nenhuma para responder "o que falta comprar nesta OS".
-- A convergência das outras duas fica para depois, com esta como referência.
--
-- A conta é a necessidade LÍQUIDA, idêntica à da lib:
--     falta = necessário − disponível − já pedido
--     disponível = stock_quantity − reserved_quantity   (view product_availability)
--     já pedido  = Σ (quantity − received_qty) das OCs em draft/sent/partial
--
-- DUAS SUTILEZAS que uma implementação ingênua erraria:
--
-- 1. CONSUMO SEQUENCIAL. Várias linhas da OS podem apontar para o MESMO produto.
--    O disponível é consumido linha a linha, senão duas linhas "enxergam" a mesma
--    peça e nenhuma das duas compra. A lib faz isso com um acumulador; aqui sai de
--    janela (soma do necessário das linhas anteriores do mesmo produto), que é
--    equivalente: enquanto o estoque cobre, cada linha satura no que pediu; quando
--    acaba, as seguintes ficam em zero.
--
-- 2. ORDEM DETERMINÍSTICA (created_at, id). A lib herda a ordem que o PostgREST
--    devolver, e o hook não pede ORDER BY nenhum — ou seja, hoje o resultado do
--    front depende de uma ordem que o Postgres não garante. Com estoque 4 e duas
--    linhas do mesmo produto pedindo 5 e 1, uma ordem acusa 2 itens em falta e a
--    outra acusa 1. O total em falta é o mesmo nos dois casos; o que muda é como
--    ele se distribui entre as linhas. Aqui a ordem é fixa.
--
-- Escopo do que conta como compra (decisão do dono, 29/07/2026):
--   • PEÇAS (service_order_parts) — product_id é NOT NULL, sempre há catálogo;
--   • TEXTO LIVRE — material avulso, que vive em service_order_services com
--     service_id NULL e billing_unit 'unit'. Sem cadastro, logo sem estoque: a
--     necessidade é a quantidade inteira. Mão de obra ('hour') e deslocamento
--     ('visit') NÃO são compra e ficam de fora.
--
-- security invoker + REVOKE de anon na mesma migration: a função lê custo de
-- aquisição, que a RLS de compras restringe a admin/financeiro. Com security
-- definer ela furaria essa restrição para qualquer autenticado.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.get_os_purchase_needs(p_so_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
with
avail as (
  select pa.id as product_id,
         greatest(0, coalesce(pa.stock_quantity, 0) - coalesce(pa.reserved_quantity, 0)) as total_available
  from product_availability pa
),
on_order as (
  select poi.product_id,
         sum(greatest(0, coalesce(poi.quantity, 0) - coalesce(poi.received_qty, 0))) as total_on_order
  from purchase_order_items poi
  join purchase_orders po on po.id = poi.purchase_order_id
  where po.status in ('draft', 'sent', 'partial')
  group by poi.product_id
),
parts as (
  select sop.id,
         sop.product_id,
         coalesce(sop.quantity, 0)           as required,
         coalesce(sop.unit_cost_snapshot, 0) as unit_cost,
         coalesce(p.name, 'Produto')         as description,
         p.unit,
         row_number() over (order by sop.created_at, sop.id) as seq
  from service_order_parts sop
  left join products p on p.id = sop.product_id
  where sop.service_order_id = p_so_id
),
parts_ctx as (
  select pt.*,
         coalesce(a.total_available, 0) as total_available,
         coalesce(o.total_on_order, 0)  as total_on_order,
         -- necessário das linhas ANTERIORES do mesmo produto (exclusivo)
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
  select ps.*,
         greatest(0, ps.required - ps.available) as after_stock
  from parts_stock ps
),
parts_gap_ctx as (
  select pg.*,
         -- o que as linhas anteriores do mesmo produto já consumiram de OC aberta
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
  select pf.id            as source_id,
         'part'::text     as origin,
         pf.product_id,
         pf.description,
         pf.unit,
         pf.required,
         pf.available,
         pf.on_order_qty  as on_order,
         greatest(0, pf.after_stock - pf.on_order_qty) as shortage,
         pf.unit_cost,
         pf.seq
  from parts_final pf
),
free_out as (
  select sos.id              as source_id,
         'free_text'::text   as origin,
         null::uuid          as product_id,
         sos.name_snapshot   as description,
         null::text          as unit,
         coalesce(sos.quantity, 0)              as required,
         0::numeric                             as available,
         0::numeric                             as on_order,
         coalesce(sos.quantity, 0)              as shortage,
         coalesce(sos.unit_price_snapshot, 0)   as unit_cost,
         row_number() over (order by sos.created_at, sos.id) as seq
  from service_order_services sos
  where sos.service_order_id = p_so_id
    and sos.service_id is null
    and sos.billing_unit_snapshot = 'unit'
    and coalesce(sos.quantity, 0) > 0
),
todos as (
  select o.*,
         case
           when o.origin = 'free_text'                     then 'uncatalogued'
           when o.shortage = 0 and o.required - o.available = 0 then 'ok'
           when o.shortage = 0                             then 'on_order'
           when o.available > 0                            then 'partial'
           else 'missing'
         end as status
  from (select * from parts_out union all select * from free_out) o
),
-- Ordem de resolução: quem não tem nada primeiro, depois parcial, depois sem
-- cadastro; desempate pelo tamanho da falta. Igual ao rank da lib.
ranked as (
  select t.*,
         case t.status
           when 'missing'      then 0
           when 'partial'      then 1
           when 'uncatalogued' then 2
           when 'on_order'     then 3
           else 4
         end as rank
  from todos t
)
select jsonb_build_object(
  'serviceOrderId', p_so_id,
  'items', coalesce((
    select jsonb_agg(jsonb_build_object(
             'sourceId', r.source_id, 'origin', r.origin, 'productId', r.product_id,
             'description', r.description, 'unit', r.unit, 'required', r.required,
             'available', r.available, 'onOrder', r.on_order, 'shortage', r.shortage,
             'status', r.status, 'unitCost', r.unit_cost)
           order by r.origin desc, r.seq)
    from ranked r), '[]'::jsonb),
  'shortages', coalesce((
    select jsonb_agg(jsonb_build_object(
             'sourceId', r.source_id, 'origin', r.origin, 'productId', r.product_id,
             'description', r.description, 'unit', r.unit, 'required', r.required,
             'available', r.available, 'onOrder', r.on_order, 'shortage', r.shortage,
             'status', r.status, 'unitCost', r.unit_cost)
           order by r.rank, r.shortage desc)
    from ranked r where r.shortage > 0), '[]'::jsonb),
  'shortageCount', (select count(*) from ranked where shortage > 0),
  'estimatedCost', coalesce((select sum(shortage * unit_cost) from ranked where shortage > 0), 0),
  'needsPurchase', exists (select 1 from ranked where shortage > 0)
);
$$;

comment on function public.get_os_purchase_needs(uuid) is
  'Necessidade LÍQUIDA de compra de uma OS (falta = necessário − disponível − já pedido). '
  'Espelha src/lib/purchase-needs.ts; é a via do agente de IA. Ordem determinística por (created_at, id).';

-- A função lê custo de aquisição: fechar para anon explicitamente. O EXECUTE
-- default de funções é PUBLIC, então revogar de PUBLIC é o que de fato fecha.
revoke all on function public.get_os_purchase_needs(uuid) from public;
grant execute on function public.get_os_purchase_needs(uuid) to authenticated, service_role;
