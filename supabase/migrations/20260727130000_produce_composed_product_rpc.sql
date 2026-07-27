-- Módulo de PRODUÇÃO (BOM): produzir um composto/kit consome os componentes do estoque e credita
-- o produto acabado. Atômico, checa disponibilidade (não consome estoque reservado) antes de
-- consumir. Não toca em OS → não dispara os triggers do estoque v2 (que agem em service_order_*).
create or replace function public.produce_composed_product(p_parent uuid, p_qty numeric default 1)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_type text;
  r record;
  v_falta jsonb := '[]'::jsonb;
  v_consumido jsonb := '[]'::jsonb;
begin
  if p_qty is null or p_qty <= 0 then
    return jsonb_build_object('ok', false, 'error', 'Quantidade deve ser maior que zero.');
  end if;

  select product_type into v_type from products where id = p_parent;
  if v_type is null then
    return jsonb_build_object('ok', false, 'error', 'Produto não encontrado.');
  end if;
  if v_type not in ('composto', 'kit') then
    return jsonb_build_object('ok', false, 'error', 'Produto não é composto/kit — não tem receita para produzir.');
  end if;
  if not exists (select 1 from product_components where parent_product_id = p_parent) then
    return jsonb_build_object('ok', false, 'error', 'Produto composto sem componentes cadastrados.');
  end if;

  -- 1) Checa disponibilidade de TODOS os componentes (disponível = físico − reservado).
  for r in
    select pc.component_product_id, pc.quantity as need_per, c.name,
           c.stock_quantity, coalesce(c.reserved_quantity, 0) as reserved
    from product_components pc
    join products c on c.id = pc.component_product_id
    where pc.parent_product_id = p_parent
  loop
    if (r.stock_quantity - r.reserved) < (r.need_per * p_qty) then
      v_falta := v_falta || jsonb_build_object(
        'produto', r.name, 'necessario', r.need_per * p_qty, 'disponivel', r.stock_quantity - r.reserved);
    end if;
  end loop;
  if jsonb_array_length(v_falta) > 0 then
    return jsonb_build_object('ok', false, 'error', 'Estoque insuficiente de componentes.', 'faltantes', v_falta);
  end if;

  -- 2) Consome os componentes + registra o movimento.
  for r in
    select pc.component_product_id, pc.quantity as need_per, c.name, c.cost_price
    from product_components pc
    join products c on c.id = pc.component_product_id
    where pc.parent_product_id = p_parent
  loop
    update products set stock_quantity = stock_quantity - (r.need_per * p_qty) where id = r.component_product_id;
    insert into inventory_movements(product_id, movement_type, quantity_delta, reference_type, unit_cost_snapshot, notes)
      values (r.component_product_id, 'manual_remove_stock', -(r.need_per * p_qty), 'production', r.cost_price,
              'Consumo em produção de composto/kit');
    v_consumido := v_consumido || jsonb_build_object('produto', r.name, 'consumido', r.need_per * p_qty);
  end loop;

  -- 3) Credita o produto acabado.
  update products set stock_quantity = stock_quantity + p_qty where id = p_parent;
  insert into inventory_movements(product_id, movement_type, quantity_delta, reference_type, notes)
    values (p_parent, 'manual_add_stock', p_qty, 'production', 'Produção de composto/kit');

  return jsonb_build_object(
    'ok', true, 'produzido', p_qty, 'consumidos', v_consumido,
    'novo_estoque_pai', (select stock_quantity from products where id = p_parent));
end;
$$;

revoke all on function public.produce_composed_product(uuid, numeric) from public, anon;
grant execute on function public.produce_composed_product(uuid, numeric) to authenticated, service_role;
