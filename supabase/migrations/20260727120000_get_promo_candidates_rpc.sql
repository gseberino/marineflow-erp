-- Motor de curadoria do "vendedor autônomo": ranqueia produtos por POTENCIAL DE PROMOÇÃO no
-- status. Prioriza o que temos para vender (disponível = físico − reservado), boa margem, COM
-- foto (postável) e encalhado (parado há tempo). Fonte única p/ agente e UI. Read-only.
create or replace function public.get_promo_candidates(p_limit int default 10)
returns table(
  product_id uuid, name text, sku text, image_url text,
  sale_price numeric, cost_price numeric, margin_pct numeric,
  stock_quantity numeric, reserved_quantity numeric, available numeric,
  last_sold_at timestamptz, days_since_sold int, has_image boolean, score numeric
)
language sql
stable
security definer
set search_path to 'public'
as $$
  with sold as (
    select sop.product_id, max(so.created_at) as last_sold_at
    from service_order_parts sop
    join service_orders so on so.id = sop.service_order_id
    group by sop.product_id
  )
  select
    p.id, p.name, p.sku, p.image_url,
    p.sale_price, p.cost_price,
    case when coalesce(p.cost_price,0) > 0
         then round((p.sale_price - p.cost_price) / p.cost_price * 100, 1) else null end as margin_pct,
    p.stock_quantity, p.reserved_quantity,
    (p.stock_quantity - coalesce(p.reserved_quantity,0)) as available,
    s.last_sold_at,
    case when s.last_sold_at is not null then extract(day from now() - s.last_sold_at)::int else null end as days_since_sold,
    (p.image_url is not null and p.image_url <> '') as has_image,
    (
      least((p.stock_quantity - coalesce(p.reserved_quantity,0)), 10) * 1.0
      + coalesce(case when coalesce(p.cost_price,0) > 0
                 then least((p.sale_price - p.cost_price) / nullif(p.cost_price,0) * 100, 100) else 0 end, 0) * 0.1
      + case when (p.image_url is not null and p.image_url <> '') then 5 else 0 end
      + case when s.last_sold_at is null or s.last_sold_at < now() - interval '60 days' then 3 else 0 end
    ) as score
  from products p
  left join sold s on s.product_id = p.id
  where p.active
    and (p.stock_quantity - coalesce(p.reserved_quantity,0)) > 0
  order by score desc
  limit greatest(1, least(p_limit, 50));
$$;

revoke all on function public.get_promo_candidates(int) from public, anon;
grant execute on function public.get_promo_candidates(int) to authenticated, service_role;
