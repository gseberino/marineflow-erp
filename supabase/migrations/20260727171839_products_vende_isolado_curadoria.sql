-- Separa "produto que se vende sozinho" de "complementar de sistema".
--
-- Motivo: cabo, sensor, interface e adaptador fazem parte de um sistema — não
-- fazem sentido como oferta avulsa. Antes disto, get_promo_candidates filtrava
-- só is_equipment, e 10 dos 12 primeiros candidatos a promoção eram
-- complementares; as fotos recém-carregadas ainda os empurraram para o topo,
-- porque o score dá +5 para quem tem imagem.
--
-- Aditiva e reversível: a coluna nasce true (comportamento atual) e só os
-- complementares viram false. A foto continua no cadastro — ela é desejada no
-- orçamento; o que muda é o item nunca virar post sozinho.

alter table products add column if not exists vende_isolado boolean not null default true;

comment on column products.vende_isolado is
  'Produto que se vende isoladamente. false = complementar de sistema (cabo, sensor, interface, fusível, suporte): aparece em orçamento e no leve-junto, mas nunca vira oferta avulsa na curadoria de promoção.';

update products
set vende_isolado = false
where vende_isolado is distinct from false
  and name ~* '(cabo|cable|chicote|extens[ãa]o|extensor|adaptador|conector|terminador|splitter|dongle|interface|fus[ií]vel|porta.?fus|trilho|suporte|tampa|antena|^tela |^display|multicontrole|painel de controle|controle remoto|sensor|passa.?cabo|macho|f[êe]mea|micro.?c\y)'
  -- nomes que citam um acessório mas descrevem o equipamento em si
  and name !~* '(painel solar|placa solar|bateria lifepo4|controlador de carga|monitor de bateria)';

create or replace function public.get_promo_candidates(p_limit integer default 10)
returns table(product_id uuid, name text, sku text, image_url text, sale_price numeric,
              cost_price numeric, margin_pct numeric, stock_quantity numeric,
              reserved_quantity numeric, available numeric, last_sold_at timestamp with time zone,
              days_since_sold integer, has_image boolean, score numeric)
language sql
stable
security definer
set search_path to 'public'
as $function$
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
    and p.is_equipment is true
    and p.vende_isolado
    and (p.stock_quantity - coalesce(p.reserved_quantity,0)) > 0
  order by score desc
  limit greatest(1, least(p_limit, 50));
$function$;
