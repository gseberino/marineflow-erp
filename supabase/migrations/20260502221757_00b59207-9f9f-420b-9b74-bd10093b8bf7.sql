CREATE OR REPLACE FUNCTION public.deduct_stock_on_os_complete()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed' THEN
    UPDATE products p
    SET stock_quantity = GREATEST(0, p.stock_quantity - sop.quantity)
    FROM service_order_parts sop
    WHERE sop.service_order_id = NEW.id
      AND sop.product_id = p.id;

    INSERT INTO inventory_movements (
      product_id, movement_type, quantity_delta,
      reference_type, reference_id, notes, unit_cost_snapshot
    )
    SELECT
      sop.product_id,
      'service_order_usage',
      -sop.quantity,
      'service_order',
      NEW.id,
      'Baixa automática ao concluir OS ' || NEW.service_order_number,
      sop.unit_cost_snapshot
    FROM service_order_parts sop
    WHERE sop.service_order_id = NEW.id
      AND sop.product_id IS NOT NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_deduct_stock_on_os_complete ON public.service_orders;

CREATE TRIGGER trg_deduct_stock_on_os_complete
  AFTER UPDATE ON public.service_orders
  FOR EACH ROW EXECUTE FUNCTION public.deduct_stock_on_os_complete();