-- ─────────────────────────────────────────────────────────────────────────────
-- Mão de obra deixa de aparecer como item a cotar com fornecedor.
--
-- Relatado pelo dono em 05/08/2026: o aviso "11 itens precisam de compra" da
-- OS-00060 listava, lado a lado, "Cabo elétrico 16mm²" e "Instalação 2x Carregador
-- DC/DC 50A". Cotar instalação com fornecedor de peça não faz sentido.
--
-- POR QUE ACONTECIA: os dois chegam ao banco IDÊNTICOS — `service_order_services`
-- com `service_id` nulo e `billing_unit_snapshot = 'unit'`. A regra existente já
-- excluía hora e visita (mão de obra medida em tempo/deslocamento), mas serviço
-- cobrado por unidade era indistinguível de material. O dado não carregava a
-- diferença; nenhuma regra sobre esses campos poderia acertar.
--
-- COMO FICOU: `free_text_is_material` decide pelo texto, reaproveitando o
-- `classify_service_text` que já existe no repo (regex determinística e auditável,
-- do Ciclo do Serviço). Duas camadas, nesta ordem:
--   1. Substantivo GENÉRICO de material no início vence o verbo — "Materiais e
--      insumos complementares de instalação" é material, apesar do "instalação".
--      A lista é curta de propósito: nome de produto (cabo, roda, fusível) NÃO
--      entra, porque aparece também em serviço — "Rodados de Alumínio - Remoção,
--      Transporte e Reinstalação" é mão de obra.
--   2. Sem esse prefixo, verbo reconhecido ⇒ serviço; nada indicando trabalho ⇒
--      material (é o caso de "Cabo elétrico 16mm²", "Fusível ANL/MIDI").
-- Resultado nos 7 itens reais da OS-00060: 7 de 7 corretos, e a lista caiu de 11
-- para 7 itens.
--
-- `classify_free_text_materials` existe para a TELA consultar em lote, em vez de
-- reimplementar a regra em TypeScript: a conta de necessidade já vive em três
-- linguagens (TS, Deno, SQL) e não vale criar mais uma divergência possível.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.free_text_is_material(p_texto text)
returns boolean
language sql
immutable
set search_path = public, extensions
as $$
  select case
    when unaccent(lower(coalesce(p_texto, ''))) ~
         '^\s*(materiais|material|insumos?|kit|pecas?|produtos?|componentes?|conjunto)\M'
      then true
    when (public.classify_service_text(p_texto)->>'verbo') is not null
      then false
    else true
  end;
$$;

comment on function public.free_text_is_material(text) is
  'Item de texto livre da OS e MATERIAL (comprave) ou mao de obra? Substantivo GENERICO de material no inicio (material/insumo/kit/peca) tem precedencia sobre o verbo; nome de produto nao entra na lista porque aparece tambem em servico.';

revoke all on function public.free_text_is_material(text) from public;
revoke all on function public.free_text_is_material(text) from anon;
grant execute on function public.free_text_is_material(text) to authenticated, service_role;

create or replace function public.classify_free_text_materials(p_textos text[])
returns jsonb
language sql
stable
set search_path = public
as $$
  select coalesce(jsonb_object_agg(t, public.free_text_is_material(t)), '{}'::jsonb)
  from (select distinct unnest(coalesce(p_textos, '{}'::text[])) as t) s
  where t is not null;
$$;

comment on function public.classify_free_text_materials(text[]) is
  'Classifica varios textos livres de uma vez (material x mao de obra). Existe para a tela nao reimplementar a regra em TypeScript.';

revoke all on function public.classify_free_text_materials(text[]) from public;
revoke all on function public.classify_free_text_materials(text[]) from anon;
grant execute on function public.classify_free_text_materials(text[]) to authenticated, service_role;

-- O cálculo puro passa a aplicar o filtro (serve agente e motor R16).
-- Nota: deixa de ser `immutable` porque agora depende de classify_service_text,
-- que lê tabela de blocos — `stable` é a categoria correta.
create or replace function public.compute_purchase_needs(
  p_so_id uuid, p_parts jsonb, p_free jsonb, p_avail jsonb, p_on_order jsonb
)
returns jsonb
language sql
stable
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
  select e->>'id' as id, e->>'product_id' as product_id,
         coalesce((e->>'quantity')::numeric, 0) as required,
         coalesce((e->>'unit_cost_snapshot')::numeric, 0) as unit_cost,
         coalesce(e->>'product_name', 'Produto') as description,
         e->>'product_unit' as unit, ord as seq
  from jsonb_array_elements(coalesce(p_parts, '[]'::jsonb)) with ordinality as t(e, ord)
),
parts_ctx as (
  select pt.*, coalesce(a.total_available, 0) as total_available,
         coalesce(o.total_on_order, 0) as total_on_order,
         coalesce(sum(pt.required) over (partition by pt.product_id order by pt.seq
           rows between unbounded preceding and 1 preceding), 0) as required_before
  from parts pt
  left join avail a on a.product_id = pt.product_id
  left join on_order o on o.product_id = pt.product_id
),
parts_stock as (
  select pc.*, greatest(0, least(pc.required, greatest(0, pc.total_available - pc.required_before))) as available
  from parts_ctx pc
),
parts_gap as (select ps.*, greatest(0, ps.required - ps.available) as after_stock from parts_stock ps),
parts_gap_ctx as (
  select pg.*, coalesce(sum(pg.after_stock) over (partition by pg.product_id order by pg.seq
    rows between unbounded preceding and 1 preceding), 0) as after_before
  from parts_gap pg
),
parts_final as (
  select pgc.*, greatest(0, least(pgc.after_stock, greatest(0, pgc.total_on_order - pgc.after_before))) as on_order_qty
  from parts_gap_ctx pgc
),
parts_out as (
  select pf.id as source_id, 'part'::text as origin, pf.product_id, pf.description, pf.unit,
         pf.required, pf.available, pf.on_order_qty as on_order,
         greatest(0, pf.after_stock - pf.on_order_qty) as shortage, pf.unit_cost, pf.seq, 0 as grp
  from parts_final pf
),
free_out as (
  select e->>'id' as source_id, 'free_text'::text as origin, null::text as product_id,
         e->>'name_snapshot' as description, null::text as unit,
         coalesce((e->>'quantity')::numeric, 0) as required,
         0::numeric as available, 0::numeric as on_order,
         coalesce((e->>'quantity')::numeric, 0) as shortage,
         coalesce((e->>'unit_price_snapshot')::numeric, 0) as unit_cost,
         ord as seq, 1 as grp
  from jsonb_array_elements(coalesce(p_free, '[]'::jsonb)) with ordinality as t(e, ord)
  where (e->>'service_id') is null
    and e->>'billing_unit_snapshot' = 'unit'
    and coalesce((e->>'quantity')::numeric, 0) > 0
    and public.free_text_is_material(e->>'name_snapshot')
),
ranked as (
  select o.*, case
      when o.origin = 'free_text' then 'uncatalogued'
      when o.shortage = 0 and o.required - o.available = 0 then 'ok'
      when o.shortage = 0 then 'on_order'
      when o.available > 0 then 'partial' else 'missing' end as status,
    case
      when o.origin = 'free_text' then 2
      when o.shortage = 0 and o.required - o.available = 0 then 4
      when o.shortage = 0 then 3
      when o.available > 0 then 1 else 0 end as rank
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
  'items',        coalesce((select jsonb_agg(js order by grp, seq) from item), '[]'::jsonb),
  'shortages',    coalesce((select jsonb_agg(js order by rank, shortage desc) from item where shortage > 0), '[]'::jsonb),
  'shortageCount',(select count(*) from item where shortage > 0),
  'estimatedCost',coalesce((select sum(shortage * unit_cost) from item where shortage > 0), 0),
  'needsPurchase',exists (select 1 from item where shortage > 0)
);
$$;
