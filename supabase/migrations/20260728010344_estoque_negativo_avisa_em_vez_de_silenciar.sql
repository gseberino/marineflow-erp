-- FASE D — política de estoque negativo: AVISAR (decisão do dono, 27/07/2026).
--
-- Não bloqueia: a operação real precisa continuar quando a nota de entrada ainda
-- não chegou. É a mesma justificativa que o ERPNext dá para o "Allow Negative
-- Stock" existir — empresas que lançam a entrada com atraso travariam sem ele.
-- Bloquear aqui também criaria o contorno pior: alguém cadastra um produto novo
-- para escapar da trava, e voltamos às duplicatas.
--
-- O que muda: quando a baixa leva o saldo abaixo de zero, o movimento passa a
-- registrar isso por escrito, e uma view expõe a dívida de lançamento. O furo
-- deixa de ser silencioso — que foi como se acumularam R$ 380 mil sem ninguém ver.

create or replace function public.trg_so_status_stock()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  r record;
  saldo_novo numeric;
  was_consumed boolean := old.status in ('completed','invoiced');
  is_consumed  boolean := new.status in ('completed','invoiced');
begin
  if not public.stock_model_v2_on() then return new; end if;

  if new.status is distinct from old.status then

    -- Entra em CONSUMIDO: baixa física, uma baixa por peça.
    if is_consumed and not was_consumed then
      for r in select product_id, quantity, unit_cost_snapshot
                 from public.service_order_parts
                where service_order_id = new.id loop
        update public.products
           set stock_quantity = stock_quantity - r.quantity
         where id = r.product_id
        returning stock_quantity into saldo_novo;

        insert into public.inventory_movements(
          product_id, movement_type, quantity_delta, reference_type, reference_id,
          unit_cost_snapshot, notes)
        values (r.product_id, 'service_order_usage', -r.quantity, 'service_order', new.id,
                r.unit_cost_snapshot,
                case when saldo_novo < 0
                     then 'ALERTA: saldo ficou negativo (' || saldo_novo
                          || '). A entrada desta peça nunca foi lancada.'
                     else null end);
      end loop;

    -- Sai de CONSUMIDO: devolve SOMENTE o que tem baixa registrada e ainda não
    -- revertida (SAP: estorno com referência; BC: uma reversão por entrada).
    elsif was_consumed and not is_consumed then
      for r in
        select m.id, m.product_id, m.quantity_delta, m.unit_cost_snapshot
          from public.inventory_movements m
         where m.reference_type = 'service_order'
           and m.reference_id = new.id
           and m.movement_type in ('service_order_usage','service_usage')
           and m.quantity_delta < 0
           and not exists (select 1 from public.inventory_movements e where e.reverses_movement_id = m.id)
      loop
        update public.products
           set stock_quantity = stock_quantity + (-r.quantity_delta)
         where id = r.product_id;
        insert into public.inventory_movements(
          product_id, movement_type, quantity_delta, reference_type, reference_id,
          unit_cost_snapshot, reverses_movement_id, notes)
        values (r.product_id, 'return', -r.quantity_delta, 'service_order', new.id,
                r.unit_cost_snapshot, r.id,
                'Estorno da baixa ' || r.id || ' (saida de ' || old.status || ' para ' || new.status || ')');
      end loop;
    end if;

    for r in select distinct product_id from public.service_order_parts where service_order_id = new.id loop
      perform public.recompute_product_reservations(r.product_id);
    end loop;
  end if;

  return new;
end;
$function$;

-- A dívida de lançamento, pronta para o painel e para o agente.
create or replace view public.v_estoque_entradas_pendentes as
select
  p.id            as product_id,
  p.name,
  p.sku,
  p.brand,
  p.stock_quantity                as saldo,
  abs(p.stock_quantity)           as unidades_a_lancar,
  round(abs(p.stock_quantity) * coalesce(p.cost_price, p.sale_price, 0), 2) as custo_estimado,
  p.is_equipment,
  (select max(m.created_at) from public.inventory_movements m
    where m.product_id = p.id and m.notes like 'ALERTA:%')  as ultimo_alerta,
  (select count(*) from public.inventory_movements m
    where m.product_id = p.id and m.notes like 'ALERTA:%')  as vezes_que_ficou_negativo
from public.products p
where p.active and p.stock_quantity < 0
order by abs(p.stock_quantity) * coalesce(p.cost_price, p.sale_price, 0) desc;

comment on view public.v_estoque_entradas_pendentes is
  'Peças usadas cuja entrada nunca foi lancada. Politica: avisar, nao bloquear (decisao do dono, 27/07/2026).';

grant select on public.v_estoque_entradas_pendentes to authenticated;
