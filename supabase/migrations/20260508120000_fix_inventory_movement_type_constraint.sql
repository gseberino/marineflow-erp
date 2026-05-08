-- Add 'service_order_usage' to the inventory_movements.movement_type constraint.
-- The trigger trg_deduct_stock_on_os_complete uses this value but it was
-- missing from the allowed list, causing a check constraint violation on OS
-- completion. Also drop the trigger to prevent double stock deduction
-- (stock is already deducted by the app when parts are added to an OS).

ALTER TABLE public.inventory_movements
  DROP CONSTRAINT IF EXISTS inventory_movements_movement_type_check;

ALTER TABLE public.inventory_movements
  ADD CONSTRAINT inventory_movements_movement_type_check
  CHECK (movement_type IN (
    'purchase', 'manual_adjustment', 'service_usage', 'service_order_usage',
    'return', 'transfer', 'manual_add', 'manual_remove', 'import', 'fiscal_note_entry'
  ));

-- Drop the trigger that double-deducts stock on OS completion.
-- Stock deduction is handled at part-add time by the application layer.
DROP TRIGGER IF EXISTS trg_deduct_stock_on_os_complete ON public.service_orders;
