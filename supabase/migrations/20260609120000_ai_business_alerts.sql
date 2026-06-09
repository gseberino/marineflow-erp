-- ai_business_alerts: proactive business monitoring alerts
-- Populated by the ai-business-monitor edge function (cron every hour).

CREATE TABLE IF NOT EXISTS public.ai_business_alerts (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_type      text        NOT NULL,
  severity        text        NOT NULL DEFAULT 'warning'
                              CHECK (severity IN ('critical', 'warning', 'info')),
  title           text        NOT NULL,
  description     text        NOT NULL,
  entity_type     text,
  entity_id       uuid,
  entity_number   text,
  resolved_at     timestamptz,
  first_seen_at   timestamptz NOT NULL DEFAULT now(),
  last_seen_at    timestamptz NOT NULL DEFAULT now(),
  metadata        jsonb       NOT NULL DEFAULT '{}',
  UNIQUE (alert_type, entity_id)
);

CREATE INDEX IF NOT EXISTS ai_business_alerts_active_idx
  ON public.ai_business_alerts (severity, last_seen_at DESC)
  WHERE resolved_at IS NULL;

CREATE INDEX IF NOT EXISTS ai_business_alerts_entity_idx
  ON public.ai_business_alerts (entity_id)
  WHERE resolved_at IS NULL;

ALTER TABLE public.ai_business_alerts ENABLE ROW LEVEL SECURITY;

-- Authenticated active users can read all alerts (agents and admins surface them)
CREATE POLICY "ai_alerts_read"
  ON public.ai_business_alerts
  FOR SELECT
  TO authenticated
  USING (private.ai_op_is_active(auth.uid()));

-- Schedule the business monitor to run every hour at :05
DO $$
BEGIN
  PERFORM cron.unschedule('ai-business-monitor');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
  'ai-business-monitor',
  '5 * * * *',
  $cmd$
  SELECT net.http_post(
    url        := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/ai-business-monitor',
    headers    := jsonb_build_object(
      'Content-Type',  'application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body       := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
  $cmd$
);
