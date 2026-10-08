-- Prova: receive_po recusa OC cancelada/recebida, item de outra OC e quantidade zero
-- (migration 20261007160000_receive_po_confere_a_oc). Termina em ROLLBACK: nada fica gravado.
--
-- Antes da migration, os casos 1–4 PASSAVAM (estoque entrava e a situação mudava) — este teste falha.
--   1. OC cancelada → recusa, nada muda;
--   2. OC toda recebida → recusa;
--   3. item de OUTRA OC → recusa e o item da outra OC não muda;
--   4. quantidade zero → recusa;
--   5. caminho feliz: recebe em parte → 'partial', movimento de estoque de +1.
-- Rodar: npx supabase db query --linked -f supabase/tests/receive_po_confere_a_oc.sql

begin;

do $teste$
declare
  v_prod   uuid;
  v_oc1    uuid;
  v_oc2    uuid;
  v_it1    uuid;
  v_it2    uuid;
  v_ok     boolean;
  v_n      int;
  v_status text;
  v_rcv    numeric;
begin
  select id into v_prod from products order by created_at limit 1;
  if v_prod is null then raise exception 'FALHOU: nenhum produto para montar a OC de teste'; end if;

  insert into purchase_orders (po_number, status) values ('OC-TESTE-990001', 'sent') returning id into v_oc1;
  insert into purchase_orders (po_number, status) values ('OC-TESTE-990002', 'sent') returning id into v_oc2;
  insert into purchase_order_items (purchase_order_id, product_id, description, quantity, unit_cost)
  values (v_oc1, v_prod, 'item teste 1', 2, 10) returning id into v_it1;
  insert into purchase_order_items (purchase_order_id, product_id, description, quantity, unit_cost)
  values (v_oc2, v_prod, 'item teste 2', 2, 10) returning id into v_it2;

  -- 1. Cancelada
  update purchase_orders set status = 'cancelled' where id = v_oc1;
  v_ok := false;
  begin
    perform receive_po(v_oc1, jsonb_build_array(jsonb_build_object('po_item_id', v_it1, 'received_qty', 1)));
  exception when others then v_ok := sqlerrm ilike '%cancelada%';
  end;
  if not v_ok then raise exception 'FALHOU 1: OC cancelada recebeu'; end if;

  -- 2. Toda recebida
  update purchase_orders set status = 'received' where id = v_oc1;
  v_ok := false;
  begin
    perform receive_po(v_oc1, jsonb_build_array(jsonb_build_object('po_item_id', v_it1, 'received_qty', 1)));
  exception when others then v_ok := sqlerrm ilike '%toda recebida%';
  end;
  if not v_ok then raise exception 'FALHOU 2: OC recebida recebeu de novo'; end if;
  update purchase_orders set status = 'sent' where id = v_oc1;

  -- 3. Item de outra OC
  v_ok := false;
  begin
    perform receive_po(v_oc1, jsonb_build_array(jsonb_build_object('po_item_id', v_it2, 'received_qty', 1)));
  exception when others then v_ok := sqlerrm ilike '%não é da%';
  end;
  if not v_ok then raise exception 'FALHOU 3: item de outra OC foi recebido'; end if;
  select received_qty into v_rcv from purchase_order_items where id = v_it2;
  if v_rcv <> 0 then raise exception 'FALHOU 3: o item da outra OC mudou (%).', v_rcv; end if;

  -- 4. Quantidade zero
  v_ok := false;
  begin
    perform receive_po(v_oc1, jsonb_build_array(jsonb_build_object('po_item_id', v_it1, 'received_qty', 0)));
  exception when others then v_ok := sqlerrm ilike '%maior que zero%';
  end;
  if not v_ok then raise exception 'FALHOU 4: quantidade zero passou'; end if;

  -- 5. Caminho feliz
  perform receive_po(v_oc1, jsonb_build_array(jsonb_build_object('po_item_id', v_it1, 'received_qty', 1)));
  select status into v_status from purchase_orders where id = v_oc1;
  select count(*) into v_n from inventory_movements
   where reference_type = 'purchase_order' and reference_id = v_oc1 and quantity_delta = 1 and product_id = v_prod;
  if v_status <> 'partial' or v_n <> 1 then
    raise exception 'FALHOU 5: esperava partial com 1 movimento, veio % com %', v_status, v_n;
  end if;

  raise notice 'OK: receive_po confere a OC (5 casos).';
end
$teste$;

rollback;
