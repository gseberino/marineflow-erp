ALTER TABLE public.service_orders DROP CONSTRAINT IF EXISTS service_orders_status_check;
ALTER TABLE public.service_orders ADD CONSTRAINT service_orders_status_check
  CHECK (status = ANY (ARRAY['draft','scheduled','open','in_progress','awaiting_parts','awaiting_client','approved','completed','invoiced','cancelled']));