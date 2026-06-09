-- ai_lifecycle_events: audit log of OS status transitions, fired by trigger.
-- Also used by ai-agent to answer "what happened to this OS?"

CREATE TABLE IF NOT EXISTS public.ai_lifecycle_events (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type      text        NOT NULL DEFAULT 'service_order',
  entity_id        uuid        NOT NULL,
  entity_number    text,
  event_type       text        NOT NULL,  -- 'status_change'
  old_value        text,
  new_value        text,
  metadata         jsonb       NOT NULL DEFAULT '{}',
  created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ai_lifecycle_events_entity_idx
  ON public.ai_lifecycle_events (entity_id, created_at DESC);

ALTER TABLE public.ai_lifecycle_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ai_lifecycle_events_read"
  ON public.ai_lifecycle_events
  FOR SELECT
  TO authenticated
  USING (private.ai_op_is_active(auth.uid()));

-- Trigger function: fires async HTTP on service_order status change.
-- Uses pg_net (async, does NOT block the transaction).
CREATE OR REPLACE FUNCTION private.ai_so_status_change_hook()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_secret text;
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;

  SELECT value INTO v_secret
  FROM app_settings
  WHERE key = 'cron_worker_secret'
  LIMIT 1;

  PERFORM net.http_post(
    url                  := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/ai-lifecycle-hooks',
    headers              := jsonb_build_object(
      'Content-Type',      'application/json',
      'x-trigger-secret',  COALESCE(v_secret, '')
    ),
    body                 := jsonb_build_object(
      'service_order_id',      NEW.id::text,
      'service_order_number',  NEW.service_order_number,
      'old_status',            OLD.status,
      'new_status',            NEW.status,
      'client_id',             NEW.client_id::text,
      'invoicing_status',      NEW.invoicing_status,
      'grand_total',           NEW.grand_total
    ),
    timeout_milliseconds := 8000
  );

  RETURN NEW;
END;
$$;

-- Attach to service_orders AFTER UPDATE (async, safe)
DROP TRIGGER IF EXISTS trg_ai_so_lifecycle ON public.service_orders;

CREATE TRIGGER trg_ai_so_lifecycle
  AFTER UPDATE OF status ON public.service_orders
  FOR EACH ROW
  EXECUTE FUNCTION private.ai_so_status_change_hook();
