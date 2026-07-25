-- Correção dos conjuntos de status do estoque v2 para casar com a REALIDADE dos dados e NÃO
-- quebrar o módulo fiscal (emissão de NF-e faz completed -> invoiced):
--   ORÇAMENTO (sem efeito no estoque): draft, open, pending
--   COMPROMETIDO (reserva):            approved, scheduled, in_progress, awaiting_parts, awaiting_client, reopened
--   CONSUMIDO (baixa física):          completed, invoiced   <- invoiced é consumido, NÃO reabertura
--   LIBERADO:                          cancelled
-- Bugs corrigidos: (1) invoiced antes estornava (completed->invoiced devolvia estoque);
-- (2) os nomes reais são awaiting_parts/awaiting_client, não waiting_parts/waiting_approval.

create or replace function public.recompute_product_reservations(_product uuid)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  update public.products p
     set reserved_quantity = coalesce((
       select sum(sop.quantity)
       from public.service_order_parts sop
       join public.service_orders so on so.id = sop.service_order_id
       where sop.product_id = p.id
         and so.status in ('approved','scheduled','in_progress','awaiting_parts','awaiting_client','reopened')
     ), 0)
   where p.id = _product;
end;
$$;

create or replace function public.trg_so_status_stock()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare
  r record;
  was_consumed boolean := old.status in ('completed','invoiced');
  is_consumed  boolean := new.status in ('completed','invoiced');
begin
  if not public.stock_model_v2_on() then return new; end if;
  if new.status is distinct from old.status then
    if is_consumed and not was_consumed then
      for r in select product_id, quantity, unit_cost_snapshot from public.service_order_parts where service_order_id = new.id loop
        update public.products set stock_quantity = stock_quantity - r.quantity where id = r.product_id;
        insert into public.inventory_movements(product_id, movement_type, quantity_delta, reference_type, reference_id, unit_cost_snapshot)
          values (r.product_id, 'service_order_usage', -r.quantity, 'service_order', new.id, r.unit_cost_snapshot);
      end loop;
    elsif was_consumed and not is_consumed then
      for r in select product_id, quantity, unit_cost_snapshot from public.service_order_parts where service_order_id = new.id loop
        update public.products set stock_quantity = stock_quantity + r.quantity where id = r.product_id;
        insert into public.inventory_movements(product_id, movement_type, quantity_delta, reference_type, reference_id, unit_cost_snapshot)
          values (r.product_id, 'return', r.quantity, 'service_order', new.id, r.unit_cost_snapshot);
      end loop;
    end if;
    -- completed <-> invoiced (ambos consumidos) não mexem no físico.
    for r in select distinct product_id from public.service_order_parts where service_order_id = new.id loop
      perform public.recompute_product_reservations(r.product_id);
    end loop;
  end if;
  return new;
end;
$$;

create or replace function public.reconcile_stock_to_v2()
returns void language plpgsql security definer set search_path to 'public' as $$
declare r record;
begin
  for r in
    select sop.product_id, sum(sop.quantity) q
    from public.service_order_parts sop
    join public.service_orders so on so.id = sop.service_order_id
    where so.status in ('draft','open','pending','approved','scheduled','in_progress','awaiting_parts','awaiting_client','reopened')
    group by sop.product_id
  loop
    update public.products set stock_quantity = stock_quantity + r.q where id = r.product_id;
  end loop;
  for r in select id from public.products loop
    perform public.recompute_product_reservations(r.id);
  end loop;
end;
$$;

revoke all on function public.recompute_product_reservations(uuid) from public, anon, authenticated;
revoke all on function public.reconcile_stock_to_v2() from public, anon, authenticated;
grant execute on function public.reconcile_stock_to_v2() to service_role;
