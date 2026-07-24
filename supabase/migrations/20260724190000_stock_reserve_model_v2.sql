-- Modelo de estoque v2 (reserva/baixa no tempo certo), decidido pelo dono:
--   • orçamento (draft/open/pending) NÃO mexe no estoque;
--   • aprovação/OS comprometida  -> RESERVA (reserved_quantity; disponível = físico − reservado);
--   • CONCLUSÃO da OS            -> baixa FÍSICA;
--   • falta de estoque não bloqueia o orçamento (só avisa na efetivação).
--
-- Hoje o modelo antigo baixa o físico no ADD-da-peça (frontend e agente), inclusive em orçamento.
-- Este modelo é DERIVADO (reserva = Σ peças de OS comprometidas-não-concluídas) — à prova de drift —
-- e fica INERTE atrás da flag app_settings.stock_model_v2='on'. Aplicar esta migration NÃO muda
-- comportamento nenhum; a virada é feita depois, com validação, ligando a flag + reconciliação.

alter table public.products
  add column if not exists reserved_quantity numeric not null default 0;

-- Flag: só quando 'on' o v2 age (triggers no-op caso contrário).
create or replace function public.stock_model_v2_on()
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select coalesce((select lower(value) = 'on' from app_settings where key = 'stock_model_v2'), false);
$$;

-- Statuses "comprometidos" (reservam estoque): aprovado até em andamento, ainda não concluído.
-- draft/open/pending = orçamento (não reserva); completed/invoiced = já baixado; cancelled = solto.
create or replace function public.recompute_product_reservations(_product uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  update public.products p
     set reserved_quantity = coalesce((
       select sum(sop.quantity)
       from public.service_order_parts sop
       join public.service_orders so on so.id = sop.service_order_id
       where sop.product_id = p.id
         and so.status in ('approved','scheduled','in_progress','waiting_parts','waiting_approval','reopened')
     ), 0)
   where p.id = _product;
end;
$$;

-- Disponibilidade para leitura (UI/agente): físico, reservado e disponível.
create or replace view public.product_availability as
  select id, name, sku, unit,
         stock_quantity,
         reserved_quantity,
         (stock_quantity - reserved_quantity) as available_quantity
  from public.products;

-- Trigger: qualquer mudança de peça recomputa a reserva do(s) produto(s) afetado(s).
create or replace function public.trg_parts_reservation()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if public.stock_model_v2_on() then
    if tg_op = 'UPDATE' and new.product_id is distinct from old.product_id then
      perform public.recompute_product_reservations(old.product_id);
    end if;
    perform public.recompute_product_reservations(coalesce(new.product_id, old.product_id));
  end if;
  return coalesce(new, old);
end;
$$;

drop trigger if exists parts_reservation on public.service_order_parts;
create trigger parts_reservation
  after insert or update or delete on public.service_order_parts
  for each row execute function public.trg_parts_reservation();

-- Trigger: mudança de status da OS. Baixa física ao concluir; estorno ao reabrir; e recomputa
-- as reservas dos produtos da OS (que entram/saem do conjunto comprometido).
create or replace function public.trg_so_status_stock()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  r record;
begin
  if not public.stock_model_v2_on() then
    return new;
  end if;
  if new.status is distinct from old.status then
    -- CONCLUSÃO: baixa física de cada peça.
    if new.status = 'completed' and old.status <> 'completed' then
      for r in select product_id, quantity, unit_cost_snapshot from public.service_order_parts where service_order_id = new.id loop
        update public.products set stock_quantity = stock_quantity - r.quantity where id = r.product_id;
        insert into public.inventory_movements(product_id, movement_type, quantity_delta, reference_type, reference_id, unit_cost_snapshot)
          values (r.product_id, 'service_order_usage', -r.quantity, 'service_order', new.id, r.unit_cost_snapshot);
      end loop;
    end if;
    -- REABERTURA (sai de concluído): estorna a baixa física.
    if old.status = 'completed' and new.status <> 'completed' then
      for r in select product_id, quantity, unit_cost_snapshot from public.service_order_parts where service_order_id = new.id loop
        update public.products set stock_quantity = stock_quantity + r.quantity where id = r.product_id;
        insert into public.inventory_movements(product_id, movement_type, quantity_delta, reference_type, reference_id, unit_cost_snapshot)
          values (r.product_id, 'return', r.quantity, 'service_order', new.id, r.unit_cost_snapshot);
      end loop;
    end if;
    -- Recomputa reservas dos produtos desta OS.
    for r in select distinct product_id from public.service_order_parts where service_order_id = new.id loop
      perform public.recompute_product_reservations(r.product_id);
    end loop;
  end if;
  return new;
end;
$$;

drop trigger if exists so_status_stock on public.service_orders;
create trigger so_status_stock
  after update of status on public.service_orders
  for each row execute function public.trg_so_status_stock();

-- Reconciliação (rodar UMA vez, ao ligar a flag, após validar): o modelo antigo baixou o físico
-- no add para TODAS as OSs (inclusive orçamentos). No v2, orçamento não baixa e OS comprometida só
-- reserva. Esta RPC devolve ao físico o que foi baixado de OSs NÃO concluídas e NÃO canceladas, e
-- então recomputa as reservas. É reversível na prática desfazendo o inverso; rode com o sistema
-- em janela controlada.
create or replace function public.reconcile_stock_to_v2()
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  r record;
begin
  for r in
    select sop.product_id, sum(sop.quantity) q
    from public.service_order_parts sop
    join public.service_orders so on so.id = sop.service_order_id
    where so.status in ('draft','open','pending','approved','scheduled','in_progress','waiting_parts','waiting_approval','reopened')
    group by sop.product_id
  loop
    update public.products set stock_quantity = stock_quantity + r.q where id = r.product_id;
  end loop;

  for r in select id from public.products loop
    perform public.recompute_product_reservations(r.id);
  end loop;
end;
$$;

grant execute on function public.stock_model_v2_on() to authenticated, service_role, anon;
grant execute on function public.recompute_product_reservations(uuid) to authenticated, service_role;
grant execute on function public.reconcile_stock_to_v2() to service_role;
grant select on public.product_availability to authenticated, service_role, anon;
