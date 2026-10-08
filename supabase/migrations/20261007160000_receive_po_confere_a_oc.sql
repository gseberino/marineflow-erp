-- receive_po confere a OC antes de receber (07/10/2026, defeitos de tela).
--
-- POR QUE: a rotina de recebimento (tela: ReceivePODialog → useReceivePO; assistente:
-- receive_purchase_order) aceitava qualquer coisa —
--   · OC CANCELADA ou já TODA RECEBIDA recebia de novo: entrava estoque (movimento 'purchase') e a
--     situação voltava para 'partial'/'received';
--   · item de OUTRA OC (po_item_id de outra ordem) era recebido em nome desta: o received_qty da outra
--     OC subia e o movimento de estoque ficava apontando para esta;
--   · quantidade zero ou negativa virava movimento de estoque (negativo = saída).
-- A tool do assistente já conferia isso antes de chamar (compras-ciclo.ts); a tela não. A conferência
-- agora mora no banco, para os dois caminhos. O resto da função é o MESMO de produção (fase E do
-- ledger: o saldo sobe pelo movimento; conta a pagar quando tudo chega).
--
-- Medido em 07/10/2026: 0 movimentos com reference_type = 'purchase_order' e 2 OCs recebidas/canceladas
-- — nenhum dado muda; só recebimentos inválidos passam a ser recusados com a mensagem.

create or replace function public.receive_po(p_po_id uuid, p_items jsonb, p_due_days integer default 30)
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
DECLARE
  v_item        jsonb;
  v_poi         record;
  v_new_rcv     numeric;
  v_qtd         numeric;
  v_po          record;
  v_all_done    boolean := true;
  v_any_done    boolean := false;
  v_new_status  text;
  v_payable_id  uuid;
  v_total       numeric;
BEGIN
  -- A OC primeiro, travada: só rascunho, enviada ou recebida em parte recebem.
  SELECT * INTO v_po FROM public.purchase_orders WHERE id = p_po_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ordem de compra não encontrada.'; END IF;
  IF v_po.status = 'cancelled' THEN
    RAISE EXCEPTION 'A % está cancelada — não recebe. Volte-a para rascunho antes, se a compra continua.', v_po.po_number;
  END IF;
  IF v_po.status = 'received' THEN
    RAISE EXCEPTION 'A % já está toda recebida.', v_po.po_number;
  END IF;

  -- Process each item
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_qtd := (v_item->>'received_qty')::numeric;
    IF v_qtd IS NULL OR v_qtd <= 0 THEN
      RAISE EXCEPTION 'Quantidade recebida tem de ser maior que zero.';
    END IF;

    -- Só item DESTA OC.
    SELECT * INTO v_poi
      FROM public.purchase_order_items
     WHERE id = (v_item->>'po_item_id')::uuid
       AND purchase_order_id = p_po_id
       FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'O item % não é da % — nada foi recebido.', v_item->>'po_item_id', v_po.po_number;
    END IF;

    v_new_rcv := COALESCE(v_poi.received_qty, 0) + v_qtd;
    v_new_rcv := LEAST(v_new_rcv, v_poi.quantity); -- cap at ordered qty

    -- Update received_qty on item
    UPDATE public.purchase_order_items
       SET received_qty = v_new_rcv
     WHERE id = v_poi.id;

    -- O saldo sobe pelo movimento abaixo (fase E); aqui só a data da última entrada.
    UPDATE public.products
       SET last_stock_entry_at = NOW()
     WHERE id = v_poi.product_id;

    -- Inventory movement
    INSERT INTO public.inventory_movements
      (product_id, movement_type, quantity_delta, reference_type, reference_id, unit_cost_snapshot)
    VALUES
      (v_poi.product_id, 'purchase', v_qtd,
       'purchase_order', p_po_id, v_poi.unit_cost);

    v_any_done := true;
    IF v_new_rcv < v_poi.quantity THEN v_all_done := false; END IF;
  END LOOP;

  -- Check if ALL items across the entire PO are fully received
  SELECT bool_and(received_qty >= quantity)
    INTO v_all_done
    FROM public.purchase_order_items
   WHERE purchase_order_id = p_po_id;

  v_new_status := CASE
    WHEN v_all_done THEN 'received'
    WHEN v_any_done THEN 'partial'
    ELSE v_po.status
  END;

  -- Create payable when fully received and no payable yet
  IF v_new_status = 'received' AND v_po.payable_id IS NULL AND v_po.supplier_id IS NOT NULL THEN
    SELECT COALESCE(SUM(received_qty * unit_cost), 0)
      INTO v_total
      FROM public.purchase_order_items
     WHERE purchase_order_id = p_po_id;

    INSERT INTO public.payables
      (supplier_id, description, amount, balance_amount, paid_amount,
       issue_date, due_date, status, origin)
    VALUES
      (v_po.supplier_id,
       'Recebimento ' || v_po.po_number,
       v_total, v_total, 0,
       CURRENT_DATE, CURRENT_DATE + p_due_days,
       'pending', 'purchase_order')
    RETURNING id INTO v_payable_id;

    UPDATE public.purchase_orders
       SET status     = v_new_status,
           payable_id = v_payable_id,
           received_date = CURRENT_DATE
     WHERE id = p_po_id;
  ELSE
    UPDATE public.purchase_orders
       SET status = v_new_status,
           received_date = CASE WHEN v_new_status = 'received' THEN CURRENT_DATE ELSE received_date END
     WHERE id = p_po_id;
  END IF;

  RETURN json_build_object(
    'status',      v_new_status,
    'payable_id',  v_payable_id,
    'all_received', v_all_done
  );
END;
$function$;

-- create or replace mantém os privilégios; reafirmados para a migration valer sozinha.
revoke all on function public.receive_po(uuid, jsonb, integer) from public, anon;
grant execute on function public.receive_po(uuid, jsonb, integer) to authenticated, service_role;

do $$
begin
  if has_function_privilege('anon', 'public.receive_po(uuid, jsonb, integer)', 'execute') then
    raise exception 'receive_po exposta ao anon';
  end if;
  if not has_function_privilege('authenticated', 'public.receive_po(uuid, jsonb, integer)', 'execute') then
    raise exception 'receive_po sem acesso para quem está logado';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261007160000', 'receive_po_confere_a_oc')
on conflict do nothing;
