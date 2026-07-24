-- Preço sugerido de um produto = ÚLTIMO praticado a ESTE cliente → último praticado (global)
-- → preço de catálogo. Fonte ÚNICA para o agente IA e para a UI (sem divergência de lógica).
-- Devolve também a ORIGEM e a DATA, para que o vendedor saiba de onde veio o número.
-- O "praticado" hoje mora no snapshot de cada peça de OS/orçamento (service_order_parts).

create or replace function public.resolve_practiced_price(
  p_product_id uuid,
  p_client_id  uuid default null
)
returns table(price numeric, source text, ref_date timestamptz)
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare
  r record;
begin
  -- 1) Último praticado a ESTE cliente.
  if p_client_id is not null then
    select sop.unit_sale_snapshot as price, so.created_at as ref_date
      into r
    from service_order_parts sop
    join service_orders so on so.id = sop.service_order_id
    where sop.product_id = p_product_id
      and so.client_id = p_client_id
      and sop.unit_sale_snapshot is not null
      and sop.unit_sale_snapshot > 0
    order by so.created_at desc
    limit 1;
    if found then
      return query select r.price, 'último praticado a este cliente'::text, r.ref_date;
      return;
    end if;
  end if;

  -- 2) Último praticado a QUALQUER cliente.
  select sop.unit_sale_snapshot as price, so.created_at as ref_date
    into r
  from service_order_parts sop
  join service_orders so on so.id = sop.service_order_id
  where sop.product_id = p_product_id
    and sop.unit_sale_snapshot is not null
    and sop.unit_sale_snapshot > 0
  order by so.created_at desc
  limit 1;
  if found then
    return query select r.price, 'último praticado (outro cliente)'::text, r.ref_date;
    return;
  end if;

  -- 3) Catálogo (cadastro atual).
  select p.sale_price as price into r from products p where p.id = p_product_id;
  return query select coalesce(r.price, 0)::numeric, 'catálogo'::text, null::timestamptz;
end;
$$;

grant execute on function public.resolve_practiced_price(uuid, uuid) to authenticated, service_role, anon;
