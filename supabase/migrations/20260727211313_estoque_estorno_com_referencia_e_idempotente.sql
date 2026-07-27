-- FASE A — estancar a criação de estoque fantasma.
--
-- Defeito: ao sair de completed/invoiced, trg_so_status_stock devolvia ao estoque
-- TODAS as peças presentes na OS naquele instante, sem verificar se aquelas peças
-- chegaram a ser baixadas, e sem impedir que o mesmo estorno acontecesse de novo.
-- Resultado medido: 45 produtos com estoque e nenhuma compra; o Bico Injetor Volvo
-- Penta D4 recebeu 3 estornos de +4 da MESMA OS, sem nenhuma baixa.
--
-- Correção, seguindo o que SAP e Dynamics 365 BC fazem:
--   SAP  — o estorno referencia o documento original; é a referência que determina
--          o que e quanto estornar.
--   BC   — "uma entrada só pode ser revertida uma vez".
-- Aqui: cada devolução aponta para a BAIXA que ela reverte (reverses_movement_id),
-- e um índice único garante que nenhuma baixa seja revertida duas vezes. Ciclos
-- legítimos (faturar → reabrir → faturar → reabrir) seguem funcionando, porque
-- cada ciclo gera a sua própria baixa e a sua própria reversão.

alter table inventory_movements
  add column if not exists reverses_movement_id uuid references inventory_movements(id);

comment on column inventory_movements.reverses_movement_id is
  'Baixa que este movimento reverte. Único: uma baixa só pode ser revertida uma vez (regra do Dynamics 365 BC). Nulo em movimentos que não são estorno.';

create unique index if not exists ux_inventory_movements_reverses
  on inventory_movements(reverses_movement_id)
  where reverses_movement_id is not null;

create or replace function public.trg_so_status_stock()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  r record;
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
         where id = r.product_id;
        insert into public.inventory_movements(
          product_id, movement_type, quantity_delta, reference_type, reference_id, unit_cost_snapshot)
        values (r.product_id, 'service_order_usage', -r.quantity, 'service_order', new.id, r.unit_cost_snapshot);
      end loop;

    -- Sai de CONSUMIDO: devolve SOMENTE o que tem baixa registrada e ainda não
    -- revertida. Peça acrescentada depois do faturamento nunca teve baixa, logo
    -- não gera devolução — era exatamente daí que vinha o estoque fantasma.
    elsif was_consumed and not is_consumed then
      for r in
        select m.id, m.product_id, m.quantity_delta, m.unit_cost_snapshot
          from public.inventory_movements m
         where m.reference_type = 'service_order'
           and m.reference_id = new.id
           and m.movement_type in ('service_order_usage','service_usage')
           and m.quantity_delta < 0
           and not exists (
             select 1 from public.inventory_movements e
              where e.reverses_movement_id = m.id
           )
      loop
        update public.products
           set stock_quantity = stock_quantity + (-r.quantity_delta)
         where id = r.product_id;
        insert into public.inventory_movements(
          product_id, movement_type, quantity_delta, reference_type, reference_id,
          unit_cost_snapshot, reverses_movement_id, notes)
        values (r.product_id, 'return', -r.quantity_delta, 'service_order', new.id,
                r.unit_cost_snapshot, r.id,
                'Estorno da baixa ' || r.id || ' (saída de ' || old.status || ' para ' || new.status || ')');
      end loop;
    end if;

    -- completed <-> invoiced (ambos consumidos) não mexem no físico.
    for r in select distinct product_id from public.service_order_parts where service_order_id = new.id loop
      perform public.recompute_product_reservations(r.product_id);
    end loop;
  end if;

  return new;
end;
$function$;
