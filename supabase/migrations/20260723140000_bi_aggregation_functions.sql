-- Views de BI (Onda 5). Aplicado em prod via MCP (bi_aggregation_functions). Só OS reais.
create or replace function bi_revenue_by_brand(_since date default null, _brand text default null)
returns table(brand text, revenue numeric, cost numeric, qty numeric)
language sql stable set search_path = public as $$
  select coalesce(pr.brand,'(sem marca)'), coalesce(sum(p.line_total_sale),0)::numeric,
         coalesce(sum(p.line_total_cost),0)::numeric, coalesce(sum(p.quantity),0)::numeric
  from service_order_parts p join service_orders so on so.id=p.service_order_id
  left join products pr on pr.id=p.product_id
  where so.status not in ('draft','cancelled') and (_since is null or so.created_at>=_since)
    and (_brand is null or pr.brand ilike '%'||_brand||'%') group by 1 order by 2 desc nulls last;
$$;
create or replace function bi_margin_by_category(_since date default null)
returns table(category text, revenue numeric, cost numeric)
language sql stable set search_path = public as $$
  select coalesce(pr.category,'(sem categoria)'), coalesce(sum(p.line_total_sale),0)::numeric, coalesce(sum(p.line_total_cost),0)::numeric
  from service_order_parts p join service_orders so on so.id=p.service_order_id
  left join products pr on pr.id=p.product_id
  where so.status not in ('draft','cancelled') and (_since is null or so.created_at>=_since) group by 1 order by 2 desc nulls last;
$$;
create or replace function bi_top_clients(_since date default null, _limit int default 10)
returns table(client_id uuid, name text, revenue numeric, os_count bigint)
language sql stable set search_path = public as $$
  select so.client_id, c.name, coalesce(sum(so.grand_total),0)::numeric, count(*)::bigint
  from service_orders so left join clients c on c.id=so.client_id
  where so.status not in ('draft','cancelled') and (_since is null or so.created_at>=_since)
  group by so.client_id, c.name order by 3 desc nulls last limit greatest(_limit,1);
$$;
